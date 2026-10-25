#!/usr/bin/env python3
"""Revalidate one checksum-bound retained generation response without a model call."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
from pathlib import Path
from typing import Any, NoReturn

from ishikawa.canonical import canonical_json_bytes
from ishikawa.generation import GenerationRequest
from ishikawa.generation_transport import GenerationHTTPResponse, validate_generation_response


EXPECTED_MODEL = "google/gemma-4-26B-A4B-it"
EXPECTED_OFFLINE_PROMPT_TOKENS = 884
EXPECTED_LIVE_PROMPT_TOKENS = 885
EXPECTED_NULLABLE_FIELDS = {
    "top.ec_transfer_params",
    "top.metrics",
    "top.prompt_text",
    "choice.routed_experts",
    "message.annotations",
}
HEX = re.compile(r"^[0-9a-f]{64}$")


def fail(reason: str) -> NoReturn:
    print(f"retained_generation_revalidation=blocked;reason={reason}")
    raise SystemExit(1)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_request(
    path: Path,
    expected_sha256: str,
    expected_request_identity: str,
    expected_prompt_identity: str,
) -> GenerationRequest:
    if (
        not path.is_file()
        or path.is_symlink()
        or sha256_file(path) != expected_sha256
        or HEX.fullmatch(expected_request_identity) is None
        or HEX.fullmatch(expected_prompt_identity) is None
    ):
        fail("request_identity_mismatch")
    try:
        artifact = json.loads(path.read_text(encoding="utf-8"))
        body = artifact["body"]
        payload = json.loads(body["messages"][1]["content"])
        citations = payload["allowed_citation_ids"]
    except (OSError, UnicodeError, json.JSONDecodeError, KeyError, IndexError, TypeError):
        fail("request_artifact_invalid")
    if (
        artifact.get("purpose") != "synthetic_grounded_generation_request"
        or artifact.get("schema_version") != 1
        or artifact.get("synthetic_only") is not True
        or artifact.get("request_identity") != expected_request_identity
        or artifact.get("prompt_identity") != expected_prompt_identity
        or not isinstance(body, dict)
        or body.get("model") != EXPECTED_MODEL
        or not isinstance(citations, list)
        or len(citations) != 3
        or any(not isinstance(item, str) or HEX.fullmatch(item) is None for item in citations)
    ):
        fail("request_artifact_invalid")
    return GenerationRequest(
        body=body,
        prompt_identity=artifact["prompt_identity"],
        request_identity=artifact["request_identity"],
        allowed_citation_ids=tuple(citations),
    )


def inspect_compatibility_fields(body: bytes) -> None:
    try:
        envelope = json.loads(body)
        choice = envelope["choices"][0]
        message = choice["message"]
        content = message["content"]
    except (UnicodeError, json.JSONDecodeError, KeyError, IndexError, TypeError):
        fail("retained_response_invalid")
    observed = {
        "top.ec_transfer_params": envelope.get("ec_transfer_params", object()),
        "top.metrics": envelope.get("metrics", object()),
        "top.prompt_text": envelope.get("prompt_text", object()),
        "choice.routed_experts": choice.get("routed_experts", object()),
        "message.annotations": message.get("annotations", object()),
    }
    if set(observed) != EXPECTED_NULLABLE_FIELDS or any(value is not None for value in observed.values()):
        fail("nullable_compatibility_field_mismatch")
    if (
        not isinstance(content, str)
        or not content.startswith("```json\n")
        or not content.endswith("\n```")
        or content.count("```") != 2
    ):
        fail("isolated_json_fence_mismatch")


def write_artifact(
    path: Path,
    source_request_sha256: str,
    request: GenerationRequest,
    answer: Any,
) -> str:
    value: dict[str, Any] = {
        "answer": answer.answer,
        "answer_sha256": hashlib.sha256(answer.answer.encode("utf-8")).hexdigest(),
        "claims": [
            {"citation_ids": list(item.citation_ids), "text": item.text}
            for item in answer.claims
        ],
        "completion_tokens": answer.completion_tokens,
        "finish_reason": answer.finish_reason,
        "model": EXPECTED_MODEL,
        "prompt_identity": request.prompt_identity,
        "prompt_tokens": answer.prompt_tokens,
        "purpose": "bounded_live_grounded_generation",
        "request_identity": request.request_identity,
        "schema_version": 1,
        "source_sha256": source_request_sha256,
        "synthetic_only": True,
        "total_tokens": answer.total_tokens,
    }
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(canonical_json_bytes(value) + b"\n")
    except OSError:
        fail("output_write_failed")
    return sha256_file(path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", required=True)
    parser.add_argument("--expected-request-sha256", required=True)
    parser.add_argument("--expected-request-identity", required=True)
    parser.add_argument("--expected-prompt-identity", required=True)
    parser.add_argument("--response", required=True)
    parser.add_argument("--expected-response-sha256", required=True)
    parser.add_argument("--output", required=True)
    arguments = parser.parse_args()
    for identity in (arguments.expected_request_sha256, arguments.expected_response_sha256):
        if HEX.fullmatch(identity) is None:
            fail("expected_identity_invalid")
    response_path = Path(arguments.response)
    output_path = Path(arguments.output)
    if (
        not response_path.is_file()
        or response_path.is_symlink()
        or sha256_file(response_path) != arguments.expected_response_sha256
        or output_path.exists()
        or output_path.is_symlink()
        or not output_path.parent.is_dir()
    ):
        fail("response_or_output_path_invalid")
    request = read_request(
        Path(arguments.request),
        arguments.expected_request_sha256,
        arguments.expected_request_identity,
        arguments.expected_prompt_identity,
    )
    body = response_path.read_bytes()
    inspect_compatibility_fields(body)
    answer = validate_generation_response(
        GenerationHTTPResponse(200, "application/json", body), request
    )
    if answer.prompt_tokens != EXPECTED_LIVE_PROMPT_TOKENS:
        fail("live_prompt_token_count_mismatch")
    artifact_sha256 = write_artifact(
        output_path, arguments.expected_request_sha256, request, answer
    )
    distinct_citations = len(
        {citation for claim in answer.claims for citation in claim.citation_ids}
    )
    print("purpose=revalidate_retained_grounded_generation_without_model_call")
    print(
        "nullable_compatibility_fields=5;all_empty=pass;"
        "isolated_json_fence=pass;surrounding_prose=false"
    )
    print(
        f"offline_prompt_tokens={EXPECTED_OFFLINE_PROMPT_TOKENS};"
        f"live_prompt_tokens={answer.prompt_tokens};prompt_token_delta="
        f"{answer.prompt_tokens - EXPECTED_OFFLINE_PROMPT_TOKENS}"
    )
    print(
        f"claims={len(answer.claims)};distinct_citations={distinct_citations};"
        "display_answer_source=validated_claims"
    )
    print(f"accepted_artifact_sha256={artifact_sha256}")
    print("retained_generation_revalidation=pass;model_call=false;credential_read=false")


if __name__ == "__main__":
    main()
