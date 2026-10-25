#!/usr/bin/env python3
"""Qualify the configured tokenizer endpoint without retaining probe text."""

from __future__ import annotations

import argparse
import hashlib
import os
import sys
from pathlib import Path
from typing import Any, NoReturn
from urllib.parse import urlsplit

from runtime.canonical import canonical_json_bytes
from runtime.retrieval_service import RetrievalDependencyUnavailable
from runtime.tokenization import NativeGenerationTokenCounter, TokenizationEndpoint


EXPECTED_MODEL = "google/gemma-4-26B-A4B-it"
PROBE_TEXT = "Synthetic policy question: What review steps apply before publication?"
PROBE_SHA256 = "1d393a3f08472104becb39a4fbefcc4d7d616ad7b6b1e4e93ba4aedcb61eee73"
MINIMUM_MODEL_LENGTH = 204800
MAX_CREDENTIAL_BYTES = 1024


def fail(reason: str) -> NoReturn:
    print(f"[generation-tokenizer-endpoint] result=BLOCKED reason={reason}")
    raise SystemExit(1)


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


def write_artifact(path: Path, count: int) -> str:
    value: dict[str, Any] = {
        "add_special_tokens": True,
        "credential_retained": False,
        "deterministic_repeat": True,
        "endpoint_path": "/tokenize",
        "endpoint_scope": "loopback",
        "minimum_model_length": MINIMUM_MODEL_LENGTH,
        "model_generation_called": False,
        "observed_token_count": count,
        "probe_sha256": PROBE_SHA256,
        "purpose": "configured_generation_tokenizer_endpoint_qualification",
        "raw_text_retained": False,
        "request_count": 2,
        "response_contract": "validated",
        "schema_version": 1,
        "served_model": EXPECTED_MODEL,
    }
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(canonical_json_bytes(value) + b"\n")
    except OSError:
        fail("output_write_failed")
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--credential-stdin", action="store_true")
    parser.add_argument("--endpoint", default="http://127.0.0.1:8000/tokenize")
    parser.add_argument("--expected-probe-sha256", required=True)
    parser.add_argument("--output", required=True)
    arguments = parser.parse_args()
    if not arguments.credential_stdin:
        fail("attended_credential_pipe_required")
    if arguments.expected_probe_sha256 != PROBE_SHA256:
        fail("probe_identity_mismatch")
    if hashlib.sha256(PROBE_TEXT.encode("utf-8")).hexdigest() != PROBE_SHA256:
        fail("probe_identity_mismatch")
    output = Path(arguments.output)
    if output.exists() or output.is_symlink() or not output.parent.is_dir():
        fail("output_path_unsafe")
    parsed = urlsplit(arguments.endpoint)
    if parsed.hostname not in {"127.0.0.1", "localhost", "::1"} or parsed.path != "/tokenize":
        fail("endpoint_not_loopback")

    secret = read_credential()
    api_key = ""
    counter = None
    try:
        try:
            api_key = bytes(secret).decode("utf-8")
        except UnicodeError:
            fail("operator_credential_not_utf8")
        counter = NativeGenerationTokenCounter(
            endpoint=TokenizationEndpoint(
                arguments.endpoint,
                timeout_seconds=120,
                maximum_response_bytes=4 * 1024 * 1024,
            ),
            served_model=EXPECTED_MODEL,
            minimum_model_length=MINIMUM_MODEL_LENGTH,
            credential_provider=lambda: api_key,
        )
        first_count = counter(PROBE_TEXT)
        second_count = counter(PROBE_TEXT)
    except RetrievalDependencyUnavailable:
        fail("tokenization_dependency_unavailable")
    except SystemExit:
        raise
    except Exception:
        fail("unexpected_tokenization_failure")
    finally:
        counter = None
        api_key = ""
        wipe(secret)

    if first_count != second_count or not 1 <= first_count <= 2048:
        fail("tokenization_repeat_mismatch")
    artifact_sha256 = write_artifact(output, first_count)
    print(
        f"[generation-tokenizer-endpoint] identity=pass model={EXPECTED_MODEL} "
        f"probe_sha256={PROBE_SHA256}"
    )
    print(
        f"[generation-tokenizer-endpoint] measurement=pass requests=2 "
        f"count={first_count} deterministic=true minimum_model_length={MINIMUM_MODEL_LENGTH}"
    )
    print(
        f"[generation-tokenizer-endpoint] artifact=pass artifact_sha256={artifact_sha256} "
        "raw_text_retained=false model_generation_called=false"
    )
    print("[generation-tokenizer-endpoint] result=PASS next=local_endpoint_evaluation")


if __name__ == "__main__":
    main()
