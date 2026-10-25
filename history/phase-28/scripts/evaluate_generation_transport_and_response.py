#!/usr/bin/env python3
"""Qualify the native generation transport and grounded-response validator."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any, NoReturn

from ishikawa.canonical import canonical_json_bytes
from ishikawa.generation import GenerationRequest
from ishikawa.generation_transport import (
    GenerationEndpoint,
    GenerationHTTPResponse,
    GenerationResponseError,
    execute_generation_request,
    prepare_generation_request,
    validate_generation_response,
)


EXPECTED_MODEL = "google/gemma-4-26B-A4B-it"
EXPECTED_PROMPT_TOKENS = 884
EXPECTED_ANSWER_RESERVE = 2048
EXPECTED_TOTAL_RESERVED = 2932
EXPECTED_APPLICATION_REMAINING = 29836


def fail(reason: str) -> NoReturn:
    print(f"generation_transport_response_qualification=blocked;reason={reason}")
    raise SystemExit(1)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_json(path: Path, expected_sha256: str, reason: str) -> dict[str, Any]:
    if not path.is_file() or path.is_symlink() or sha256_file(path) != expected_sha256:
        fail(reason)
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail(reason)
    if not isinstance(value, dict):
        fail(reason)
    return value


def request_from_artifact(artifact: dict[str, Any]) -> GenerationRequest:
    if set(artifact) != {
        "body", "chunk_source_sha256", "prompt_identity", "purpose",
        "reconstruction_policy_identity", "request_identity", "schema_version",
        "synthetic_only",
    }:
        fail("request_artifact_contract_mismatch")
    body = artifact["body"]
    if not isinstance(body, dict) or body.get("model") != EXPECTED_MODEL:
        fail("request_artifact_contract_mismatch")
    try:
        messages = body["messages"]
        payload = json.loads(messages[1]["content"])
        citations = payload["allowed_citation_ids"]
    except (KeyError, IndexError, TypeError, json.JSONDecodeError):
        fail("request_artifact_contract_mismatch")
    if (
        artifact["purpose"] != "synthetic_grounded_generation_request"
        or artifact["schema_version"] != 1
        or artifact["synthetic_only"] is not True
        or body.get("max_tokens") != EXPECTED_ANSWER_RESERVE
        or body.get("stream") is not False
        or body.get("temperature") != 1.0
        or body.get("top_p") != 0.95
        or body.get("top_k") != 64
        or body.get("chat_template_kwargs") != {"enable_thinking": False}
        or not isinstance(citations, list)
        or not citations
        or any(not isinstance(item, str) for item in citations)
    ):
        fail("request_artifact_contract_mismatch")
    return GenerationRequest(
        body=body,
        prompt_identity=artifact["prompt_identity"],
        request_identity=artifact["request_identity"],
        allowed_citation_ids=tuple(citations),
    )


def response_for(request: GenerationRequest) -> dict[str, Any]:
    first, second = request.allowed_citation_ids[:2]
    first_claim = "Assign event ID EVT-0001."
    second_claim = "Record detection time."
    content = {
        "answer": f"{first_claim} {second_claim}",
        "claims": [
            {"text": first_claim, "citation_ids": [first]},
            {"text": second_claim, "citation_ids": [second]},
        ],
    }
    return {
        "choices": [
            {
                "finish_reason": "stop",
                "index": 0,
                "message": {
                    "content": canonical_json_bytes(content).decode("utf-8"),
                    "role": "assistant",
                },
            }
        ],
        "created": 1,
        "id": "chatcmpl-synthetic-qualification",
        "model": EXPECTED_MODEL,
        "object": "chat.completion",
        "usage": {
            "completion_tokens": 24,
            "prompt_tokens": EXPECTED_PROMPT_TOKENS,
            "total_tokens": 908,
        },
    }


def http_response(value: dict[str, Any]) -> GenerationHTTPResponse:
    return GenerationHTTPResponse(
        200,
        "application/json; charset=utf-8",
        canonical_json_bytes(value),
    )


def expect_rejection(
    value: dict[str, Any],
    request: GenerationRequest,
    expected_reason: str,
) -> None:
    try:
        validate_generation_response(http_response(value), request)
    except GenerationResponseError as error:
        if error.reason_code == expected_reason:
            return
    fail("failure_path_matrix_mismatch")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", required=True)
    parser.add_argument("--expected-request-sha256", required=True)
    parser.add_argument("--measurement", required=True)
    parser.add_argument("--expected-measurement-sha256", required=True)
    arguments = parser.parse_args()

    request_artifact = read_json(
        Path(arguments.request),
        arguments.expected_request_sha256,
        "request_artifact_identity_mismatch",
    )
    measurement = read_json(
        Path(arguments.measurement),
        arguments.expected_measurement_sha256,
        "measurement_artifact_identity_mismatch",
    )
    values = measurement.get("measurements")
    if (
        measurement.get("purpose") != "composed_generation_request_token_measurement"
        or measurement.get("source_sha256") != arguments.expected_request_sha256
        or measurement.get("request_identity") != request_artifact.get("request_identity")
        or measurement.get("prompt_identity") != request_artifact.get("prompt_identity")
        or not isinstance(values, dict)
        or values.get("prompt_tokens") != EXPECTED_PROMPT_TOKENS
        or values.get("answer_token_reserve") != EXPECTED_ANSWER_RESERVE
        or values.get("total_reserved_tokens") != EXPECTED_TOTAL_RESERVED
        or values.get("application_remaining_tokens") != EXPECTED_APPLICATION_REMAINING
    ):
        fail("accepted_request_measurement_mismatch")

    request = request_from_artifact(request_artifact)
    endpoint = GenerationEndpoint(
        "http://127.0.0.1:8000/v1/chat/completions",
        timeout_seconds=90,
        maximum_response_bytes=1024 * 1024,
    )
    prepared = prepare_generation_request(
        endpoint,
        request,
        "synthetic-runtime-credential",
    )
    if (
        prepared.host != "127.0.0.1"
        or prepared.port != 8000
        or prepared.path != "/v1/chat/completions"
        or prepared.headers.get("Authorization") != "Bearer synthetic-runtime-credential"
        or b"synthetic-runtime-credential" in prepared.body
        or prepared.body != request.canonical_bytes()
    ):
        fail("prepared_request_contract_mismatch")

    calls = 0
    valid_response = response_for(request)

    def exchange(_prepared):
        nonlocal calls
        calls += 1
        return http_response(valid_response)

    answer = execute_generation_request(
        endpoint,
        request,
        "synthetic-runtime-credential",
        exchange=exchange,
    )
    if (
        calls != 1
        or len(answer.claims) != 2
        or answer.prompt_tokens != EXPECTED_PROMPT_TOKENS
        or answer.completion_tokens != 24
        or answer.total_tokens != 908
    ):
        fail("valid_response_contract_mismatch")

    unknown_citation = json.loads(json.dumps(valid_response))
    model_output = json.loads(unknown_citation["choices"][0]["message"]["content"])
    model_output["claims"][0]["citation_ids"] = ["f" * 64]
    unknown_citation["choices"][0]["message"]["content"] = canonical_json_bytes(
        model_output
    ).decode("utf-8")
    expect_rejection(unknown_citation, request, "MODEL_CITATION_NOT_ALLOWED")

    incomplete = json.loads(json.dumps(valid_response))
    incomplete["choices"][0]["finish_reason"] = "length"
    expect_rejection(incomplete, request, "MODEL_COMPLETION_INCOMPLETE")

    unauthorized_channel = json.loads(json.dumps(valid_response))
    unauthorized_channel["choices"][0]["message"]["reasoning"] = (
        "synthetic-private-channel"
    )
    expect_rejection(
        unauthorized_channel,
        request,
        "MODEL_UNAUTHORIZED_OUTPUT_CHANNEL",
    )

    uncited_answer = json.loads(json.dumps(valid_response))
    model_output = json.loads(uncited_answer["choices"][0]["message"]["content"])
    model_output["answer"] = "Uncited text. " + model_output["answer"]
    uncited_answer["choices"][0]["message"]["content"] = canonical_json_bytes(
        model_output
    ).decode("utf-8")
    expect_rejection(uncited_answer, request, "MODEL_CITATION_COVERAGE_INVALID")

    bad_usage = json.loads(json.dumps(valid_response))
    bad_usage["usage"]["completion_tokens"] = EXPECTED_ANSWER_RESERVE + 1
    bad_usage["usage"]["total_tokens"] = (
        EXPECTED_PROMPT_TOKENS + EXPECTED_ANSWER_RESERVE + 1
    )
    expect_rejection(bad_usage, request, "UPSTREAM_USAGE_INVALID")

    print("purpose=qualify_generation_transport_and_grounded_response_validation")
    print(
        f"request_sha256={arguments.expected_request_sha256};"
        f"measurement_sha256={arguments.expected_measurement_sha256}"
    )
    print(
        f"generation_request_id={request.request_identity};"
        f"generation_prompt_id={request.prompt_identity}"
    )
    print(
        "configurable_endpoint=pass;native_standard_library_transport=pass;"
        "single_post_no_retry=pass"
    )
    print("runtime_credential_header_only=pass;request_body_identity=pass")
    print(
        "openai_vllm_envelope_validation=pass;usage_validation=pass;"
        "answer_reserve_enforced=pass"
    )
    print(
        "grounded_json_validation=pass;citation_allowlist_validation=pass;"
        "complete_claim_coverage=pass"
    )
    print(
        "failure_path_matrix=pass;cases=unknown_citation,incomplete_completion,"
        "unauthorized_channel,uncited_answer,invalid_usage"
    )
    print(
        "network_contact=false;model_call=false;database_contact=false;"
        "credential_read=false"
    )
    print("generation_transport_response_qualification=pass")


if __name__ == "__main__":
    main()
