#!/usr/bin/env python3
"""Run one bounded synthetic scope-classifier request without logging text."""

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
from runtime.generation_transport import (
    GenerationEndpoint,
    GenerationResponseError,
    GenerationTransportError,
    native_http_exchange,
)
from runtime.scope import ScopeRequest, ScopeResponseError, validate_scope_profile
from runtime.scope_transport import prepare_scope_request, validate_scope_response
from runtime.yaml_loader import load_restricted_yaml


EXPECTED_MODEL = "google/gemma-4-26B-A4B-it"
MAX_CREDENTIAL_BYTES = 1024
HEX = re.compile(r"^[0-9a-f]{64}$")


def fail(reason: str) -> NoReturn:
    print(f"[scope-classifier] result=BLOCKED reason={reason}")
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
    expected_policy_identity: str,
    policy,
) -> ScopeRequest:
    if (
        not path.is_file()
        or path.is_symlink()
        or sha256_file(path) != expected_sha256
        or any(
            HEX.fullmatch(value) is None
            for value in (expected_request_identity, expected_prompt_identity, expected_policy_identity)
        )
    ):
        fail("request_identity_mismatch")
    try:
        artifact = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail("request_artifact_invalid")
    if not isinstance(artifact, dict) or set(artifact) != {
        "body", "policy_identity", "prompt_identity", "purpose",
        "request_identity", "schema_version", "synthetic_only",
    }:
        fail("request_artifact_invalid")
    body = artifact["body"]
    if (
        artifact["purpose"] != "synthetic_scope_classifier_request"
        or artifact["schema_version"] != 1
        or artifact["synthetic_only"] is not True
        or artifact["request_identity"] != expected_request_identity
        or artifact["prompt_identity"] != expected_prompt_identity
        or artifact["policy_identity"] != expected_policy_identity
        or policy.digest != expected_policy_identity
        or not isinstance(body, dict)
        or set(body) != {
            "chat_template_kwargs", "max_tokens", "messages", "model", "stream",
            "temperature", "top_k", "top_p",
        }
        or body.get("model") != EXPECTED_MODEL
        or body.get("max_tokens") != policy.max_output_tokens
        or body.get("stream") is not False
        or body.get("temperature") != 1.0
        or body.get("top_p") != 0.95
        or body.get("top_k") != 64
        or body.get("chat_template_kwargs") != {"enable_thinking": False}
        or not isinstance(body.get("messages"), list)
        or len(body["messages"]) != 2
    ):
        fail("request_artifact_invalid")
    return ScopeRequest(
        body=body,
        policy_identity=artifact["policy_identity"],
        prompt_identity=artifact["prompt_identity"],
        request_identity=artifact["request_identity"],
    )


def write_artifact(path: Path, source_sha256: str, request: ScopeRequest, result) -> str:
    value: dict[str, Any] = {
        "clarification": result.decision.clarification,
        "completion_tokens": result.completion_tokens,
        "decision": result.decision.decision,
        "finish_reason": result.finish_reason,
        "model": EXPECTED_MODEL,
        "policy_identity": request.policy_identity,
        "prompt_identity": request.prompt_identity,
        "prompt_tokens": result.prompt_tokens,
        "purpose": "bounded_live_scope_classification",
        "reason_code": result.decision.reason_code,
        "request_identity": request.request_identity,
        "schema_version": 1,
        "source_sha256": source_sha256,
        "synthetic_only": True,
        "total_tokens": result.total_tokens,
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
    parser.add_argument("--expected-policy-identity", required=True)
    parser.add_argument("--profile", required=True)
    parser.add_argument("--expected-profile-sha256", required=True)
    parser.add_argument("--endpoint", default="http://127.0.0.1:8000/v1/chat/completions")
    parser.add_argument("--output", required=True)
    parser.add_argument("--rejected-output", required=True)
    arguments = parser.parse_args()
    if not arguments.credential_stdin:
        fail("attended_credential_pipe_required")
    profile_path = Path(arguments.profile)
    output = Path(arguments.output)
    rejected_output = Path(arguments.rejected_output)
    if (
        not profile_path.is_file()
        or profile_path.is_symlink()
        or sha256_file(profile_path) != arguments.expected_profile_sha256
        or output.exists()
        or output.is_symlink()
        or not output.parent.is_dir()
        or rejected_output.exists()
        or rejected_output.is_symlink()
        or not rejected_output.parent.is_dir()
        or output == rejected_output
    ):
        fail("input_or_output_path_unsafe")
    try:
        policy = validate_scope_profile(load_restricted_yaml(profile_path, label="scope profile"))
    except Exception:
        fail("scope_profile_invalid")
    request = read_request(
        Path(arguments.input),
        arguments.expected_input_sha256,
        arguments.expected_request_identity,
        arguments.expected_prompt_identity,
        arguments.expected_policy_identity,
        policy,
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
            maximum_response_bytes=1024 * 1024,
        )
        if endpoint.parsed.hostname not in {"127.0.0.1", "localhost", "::1"}:
            fail("endpoint_not_loopback")
        prepared = prepare_scope_request(endpoint, request, api_key)
        response = native_http_exchange(prepared)
        try:
            result = validate_scope_response(response, request, policy)
        except (GenerationResponseError, ScopeResponseError):
            write_rejected_response(rejected_output, response.body)
            raise
    except GenerationTransportError as error:
        fail(error.reason_code)
    except GenerationResponseError as error:
        fail(error.reason_code)
    except ScopeResponseError as error:
        fail(error.reason_code)
    except SystemExit:
        raise
    except Exception:
        fail("unexpected_scope_failure")
    finally:
        prepared = None
        api_key = ""
        wipe(secret)
    artifact_sha256 = write_artifact(output, arguments.expected_input_sha256, request, result)
    print(f"[scope-classifier] identity=pass model={EXPECTED_MODEL} request_id={request.request_identity}")
    print(
        f"[scope-classifier] usage=pass prompt_tokens={result.prompt_tokens} "
        f"completion_tokens={result.completion_tokens} total_tokens={result.total_tokens}"
    )
    print(
        f"[scope-classifier] validation=pass decision={result.decision.decision} "
        f"reason_code={result.decision.reason_code} clarification_present="
        f"{str(result.decision.clarification is not None).lower()}"
    )
    print(f"[scope-classifier] artifact=pass artifact_sha256={artifact_sha256} raw_text_logged=false")
    print("[scope-classifier] result=PASS next=local_scope_result_evaluation")


if __name__ == "__main__":
    main()
