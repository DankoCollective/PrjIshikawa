#!/usr/bin/env python3
"""Run one bounded synthetic grounded-generation request without logging text."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path
from typing import Any, NoReturn

from runtime.canonical import canonical_json_bytes
from runtime.generation import GenerationRequest
from runtime.generation_transport import (
    GenerationEndpoint,
    GenerationResponseError,
    GenerationTransportError,
    native_http_exchange,
    prepare_generation_request,
    validate_generation_response,
)


EXPECTED_MODEL = "google/gemma-4-26B-A4B-it"
MAX_CREDENTIAL_BYTES = 1024
HEX = re.compile(r"^[0-9a-f]{64}$")


def fail(reason: str) -> NoReturn:
    print(f"[grounded-generation] result=BLOCKED reason={reason}")
    raise SystemExit(1)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def wipe(value: bytearray) -> None:
    for index in range(len(value)):
        value[index] = 0


def read_credential() -> bytearray:
    value = bytearray()
    while len(value) <= MAX_CREDENTIAL_BYTES:
        block = os.read(sys.stdin.fileno(), MAX_CREDENTIAL_BYTES + 1 - len(value))
        if not block:
            break
        value.extend(block)
    if not 32 <= len(value) <= MAX_CREDENTIAL_BYTES or b"\n" in value or b"\r" in value:
        wipe(value)
        fail("operator_credential_format_invalid")
    return value


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
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail("request_artifact_invalid")
    if not isinstance(artifact, dict) or set(artifact) != {
        "body", "chunk_source_sha256", "prompt_identity", "purpose",
        "reconstruction_policy_identity", "request_identity", "schema_version",
        "synthetic_only",
    }:
        fail("request_artifact_invalid")
    body = artifact["body"]
    try:
        payload = json.loads(body["messages"][1]["content"])
        citations = payload["allowed_citation_ids"]
    except (KeyError, IndexError, TypeError, json.JSONDecodeError):
        fail("request_artifact_invalid")
    if (
        artifact["purpose"] != "synthetic_grounded_generation_request"
        or artifact["schema_version"] != 1
        or artifact["synthetic_only"] is not True
        or artifact["request_identity"] != expected_request_identity
        or artifact["prompt_identity"] != expected_prompt_identity
        or not isinstance(body, dict)
        or body.get("model") != EXPECTED_MODEL
        or body.get("max_tokens") != 2048
        or body.get("stream") is not False
        or body.get("temperature") != 1.0
        or body.get("top_p") != 0.95
        or body.get("top_k") != 64
        or body.get("chat_template_kwargs") != {"enable_thinking": False}
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


def write_artifact(
    path: Path,
    source_sha256: str,
    request: GenerationRequest,
    answer,
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
        "source_sha256": source_sha256,
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


def write_rejected_response(path: Path, body: bytes) -> None:
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(body)
    except OSError:
        fail("rejected_response_write_failed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--credential-stdin", action="store_true")
    parser.add_argument("--input", required=True)
    parser.add_argument("--expected-input-sha256", required=True)
    parser.add_argument("--expected-request-identity", required=True)
    parser.add_argument("--expected-prompt-identity", required=True)
    parser.add_argument("--endpoint", default="http://127.0.0.1:8000/v1/chat/completions")
    parser.add_argument("--output", required=True)
    parser.add_argument("--rejected-output", required=True)
    arguments = parser.parse_args()
    if not arguments.credential_stdin:
        fail("attended_credential_pipe_required")
    output = Path(arguments.output)
    rejected_output = Path(arguments.rejected_output)
    if (
        output.exists()
        or output.is_symlink()
        or not output.parent.is_dir()
        or rejected_output.exists()
        or rejected_output.is_symlink()
        or not rejected_output.parent.is_dir()
        or output == rejected_output
    ):
        fail("output_path_unsafe")
    request = read_request(
        Path(arguments.input),
        arguments.expected_input_sha256,
        arguments.expected_request_identity,
        arguments.expected_prompt_identity,
    )
    secret = read_credential()
    api_key = ""
    prepared = None
    try:
        try:
            api_key = bytes(secret).decode("utf-8")
        except UnicodeError:
            fail("operator_credential_not_utf8")
        endpoint = GenerationEndpoint(
            arguments.endpoint,
            timeout_seconds=600,
            maximum_response_bytes=4 * 1024 * 1024,
        )
        if endpoint.parsed.hostname not in {"127.0.0.1", "localhost", "::1"}:
            fail("endpoint_not_loopback")
        prepared = prepare_generation_request(endpoint, request, api_key)
        response = native_http_exchange(prepared)
        try:
            answer = validate_generation_response(response, request)
        except GenerationResponseError:
            write_rejected_response(rejected_output, response.body)
            raise
    except GenerationTransportError as error:
        fail(error.reason_code)
    except GenerationResponseError as error:
        fail(error.reason_code)
    except SystemExit:
        raise
    except Exception:
        fail("unexpected_generation_failure")
    finally:
        prepared = None
        api_key = ""
        wipe(secret)
    artifact_sha256 = write_artifact(
        output,
        arguments.expected_input_sha256,
        request,
        answer,
    )
    citation_count = len({item for claim in answer.claims for item in claim.citation_ids})
    print(
        f"[grounded-generation] identity=pass model={EXPECTED_MODEL} "
        f"request_id={request.request_identity}"
    )
    print(
        f"[grounded-generation] usage=pass prompt_tokens={answer.prompt_tokens} "
        f"completion_tokens={answer.completion_tokens} total_tokens={answer.total_tokens}"
    )
    print(
        f"[grounded-generation] validation=pass claims={len(answer.claims)} "
        f"citations={citation_count} answer_sha256="
        f"{hashlib.sha256(answer.answer.encode('utf-8')).hexdigest()}"
    )
    print(
        f"[grounded-generation] artifact=pass artifact_sha256={artifact_sha256} "
        "raw_text_logged=false"
    )
    print("[grounded-generation] result=PASS next=local_grounded_answer_evaluation")


if __name__ == "__main__":
    main()
