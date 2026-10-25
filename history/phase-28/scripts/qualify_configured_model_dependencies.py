#!/usr/bin/env python3
"""Qualify configured tokenizer and embedding dependencies from an app host.

The caller owns endpoint transport. This program reads the endpoint URLs from
the supplied configuration, requires loopback endpoints, makes bounded
synthetic calls through the production adapters, and never manages forwarding.
"""

from __future__ import annotations

import argparse
import hashlib
import math
import os
import sys
from pathlib import Path
from typing import Any, NoReturn
from urllib.parse import urlsplit

from ishikawa.canonical import canonical_json_bytes
from ishikawa.native_adapters import (
    ACCEPTED_EMBEDDING_SPACE_ID,
    EMBEDDING_DIMENSION,
    NOMIC_MODEL,
    EmbeddingHTTPResponse,
    EmbeddingResponseError,
    EmbeddingTransportError,
    NativeQueryEmbeddingAdapter,
    build_query_embedding_request,
    native_embedding_exchange,
    validate_query_embedding_response,
)
from ishikawa.reconstruction import validate_reconstruction_profile
from ishikawa.retrieval_service import RetrievalDependencyUnavailable
from ishikawa.runtime import validate_runtime_dependencies
from ishikawa.tokenization import NativeGenerationTokenCounter
from ishikawa.yaml_loader import load_restricted_yaml


TOKEN_PROBE = "Synthetic policy question: What review steps apply before publication?"
EMBEDDING_PROBE = "What review steps apply before publication?"
TOKEN_PROBE_SHA256 = hashlib.sha256(TOKEN_PROBE.encode("utf-8")).hexdigest()
EMBEDDING_PROBE_SHA256 = hashlib.sha256(EMBEDDING_PROBE.encode("utf-8")).hexdigest()
EXPECTED_GENERATION_MODEL = "google/gemma-4-26B-A4B-it"
MINIMUM_MODEL_LENGTH = 204800
MAX_CREDENTIAL_BYTES = 1024
MAX_VECTOR_DELTA = 0.00001


class QualificationError(RuntimeError):
    pass


def fail(reason: str) -> NoReturn:
    print(f"configured_model_dependencies=blocked;reason={reason}")
    raise SystemExit(1)


def wipe(value: bytearray) -> None:
    for index in range(len(value)):
        value[index] = 0


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def require_source(path: Path, expected_sha256: str) -> None:
    if (
        len(expected_sha256) != 64
        or any(character not in "0123456789abcdef" for character in expected_sha256)
        or not path.is_file()
        or path.is_symlink()
        or path.stat().st_size > 1024 * 1024
        or sha256_file(path) != expected_sha256
    ):
        fail("configuration_identity_mismatch")


def read_credentials() -> tuple[bytearray, bytearray]:
    payload = bytearray()
    maximum = (MAX_CREDENTIAL_BYTES * 2) + 1
    while len(payload) <= maximum:
        block = os.read(sys.stdin.fileno(), maximum + 1 - len(payload))
        if not block:
            break
        payload.extend(block)
    if len(payload) > maximum or payload.count(b"\n") != 1 or b"\r" in payload:
        wipe(payload)
        fail("operator_credentials_format_invalid")
    boundary = payload.index(b"\n")
    gemma = bytearray(payload[:boundary])
    nomic = bytearray(payload[boundary + 1 :])
    wipe(payload)
    if not (
        32 <= len(gemma) <= MAX_CREDENTIAL_BYTES
        and 32 <= len(nomic) <= MAX_CREDENTIAL_BYTES
    ):
        wipe(gemma)
        wipe(nomic)
        fail("operator_credentials_format_invalid")
    return gemma, nomic


def require_loopback_endpoint(url: str, path: str, port: int) -> None:
    parsed = urlsplit(url)
    if (
        parsed.scheme != "http"
        or parsed.hostname != "127.0.0.1"
        or parsed.port != port
        or parsed.path != path
        or parsed.query
        or parsed.fragment
    ):
        fail("configured_endpoint_boundary_mismatch")


def write_artifact(path: Path, value: dict[str, Any]) -> str:
    if path.exists() or path.is_symlink() or not path.parent.is_dir():
        fail("output_path_unsafe")
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(canonical_json_bytes(value) + b"\n")
    except OSError:
        fail("output_write_failed")
    return sha256_file(path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--credential-stdin", action="store_true")
    parser.add_argument("--runtime-config", type=Path, required=True)
    parser.add_argument("--runtime-config-sha256", required=True)
    parser.add_argument("--reconstruction-profile", type=Path, required=True)
    parser.add_argument("--reconstruction-profile-sha256", required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    if not arguments.credential_stdin:
        fail("attended_credential_pipe_required")
    require_source(arguments.runtime_config, arguments.runtime_config_sha256)
    require_source(
        arguments.reconstruction_profile,
        arguments.reconstruction_profile_sha256,
    )

    try:
        dependencies = validate_runtime_dependencies(
            load_restricted_yaml(arguments.runtime_config, label="runtime dependencies")
        )
        reconstruction = validate_reconstruction_profile(
            load_restricted_yaml(
                arguments.reconstruction_profile,
                label="reconstruction profile",
            )
        )
    except Exception:
        fail("configuration_validation_failed")

    if reconstruction.tokenizer_model != EXPECTED_GENERATION_MODEL:
        fail("generation_model_mismatch")
    require_loopback_endpoint(
        dependencies.tokenization_endpoint.url, "/tokenize", 8000
    )
    require_loopback_endpoint(
        dependencies.embedding_endpoint.url, "/v1/embeddings", 8001
    )

    gemma_secret, nomic_secret = read_credentials()
    gemma_key = ""
    nomic_key = ""
    token_counter = None
    embedding_adapter = None
    try:
        try:
            gemma_key = bytes(gemma_secret).decode("utf-8")
            nomic_key = bytes(nomic_secret).decode("utf-8")
        except UnicodeError:
            fail("operator_credentials_not_utf8")

        token_counter = NativeGenerationTokenCounter(
            endpoint=dependencies.tokenization_endpoint,
            served_model=reconstruction.tokenizer_model,
            minimum_model_length=MINIMUM_MODEL_LENGTH,
            credential_provider=lambda: gemma_key,
        )
        try:
            first_token_count = token_counter(TOKEN_PROBE)
            second_token_count = token_counter(TOKEN_PROBE)
        except RetrievalDependencyUnavailable:
            fail("tokenization_dependency_unavailable")

        observed_embedding_response: EmbeddingHTTPResponse | None = None
        observed_embedding_transport_reason = ""

        def observed_embedding_exchange(prepared):
            nonlocal observed_embedding_response, observed_embedding_transport_reason
            try:
                observed_embedding_response = native_embedding_exchange(prepared)
                return observed_embedding_response
            except EmbeddingTransportError as error:
                observed_embedding_transport_reason = error.reason_code
                raise

        embedding_adapter = NativeQueryEmbeddingAdapter(
            endpoint=dependencies.embedding_endpoint,
            credential_provider=lambda: nomic_key,
            exchange=observed_embedding_exchange,
        )
        try:
            first_embedding = embedding_adapter(EMBEDDING_PROBE)
            second_embedding = embedding_adapter(EMBEDDING_PROBE)
        except RetrievalDependencyUnavailable:
            if observed_embedding_transport_reason:
                fail(f"embedding_transport_{observed_embedding_transport_reason}")
            if observed_embedding_response is None:
                fail("embedding_transport_unobserved_failure")
            if observed_embedding_response.status != 200:
                fail(f"embedding_http_{observed_embedding_response.status}")
            try:
                validate_query_embedding_response(
                    observed_embedding_response,
                    build_query_embedding_request(EMBEDDING_PROBE),
                )
            except EmbeddingResponseError as error:
                fail(f"embedding_response_{error.reason_code}")
            fail("embedding_dependency_unclassified")
    except SystemExit:
        raise
    except Exception:
        fail("unexpected_dependency_failure")
    finally:
        token_counter = None
        embedding_adapter = None
        gemma_key = ""
        nomic_key = ""
        wipe(gemma_secret)
        wipe(nomic_secret)

    if first_token_count != second_token_count or not 1 <= first_token_count <= 2048:
        fail("tokenization_repeat_mismatch")
    if (
        first_embedding.embedding_space_id != ACCEPTED_EMBEDDING_SPACE_ID
        or second_embedding.embedding_space_id != ACCEPTED_EMBEDDING_SPACE_ID
        or first_embedding.request_identity != second_embedding.request_identity
        or first_embedding.prompt_tokens != second_embedding.prompt_tokens
        or len(first_embedding.vector) != EMBEDDING_DIMENSION
        or len(second_embedding.vector) != EMBEDDING_DIMENSION
    ):
        fail("embedding_contract_mismatch")
    maximum_delta = max(
        abs(left - right)
        for left, right in zip(first_embedding.vector, second_embedding.vector, strict=True)
    )
    if not math.isfinite(maximum_delta) or maximum_delta > MAX_VECTOR_DELTA:
        fail("embedding_repeat_tolerance_exceeded")

    artifact = {
        "boundaries": {
            "database_contact": False,
            "forwarding_changed": False,
            "generation_called": False,
            "operator_managed_transport": True,
            "ports_required_preexisting": True,
        },
        "configuration": {
            "reconstruction_policy_identity": reconstruction.digest,
            "reconstruction_profile_sha256": arguments.reconstruction_profile_sha256,
            "runtime_dependency_identity": dependencies.digest,
            "runtime_dependencies_sha256": arguments.runtime_config_sha256,
        },
        "embedding": {
            "dimension": EMBEDDING_DIMENSION,
            "embedding_space_id": ACCEPTED_EMBEDDING_SPACE_ID,
            "maximum_repeat_delta": format(maximum_delta, ".12g"),
            "model": NOMIC_MODEL,
            "prompt_tokens": first_embedding.prompt_tokens,
            "probe_sha256": EMBEDDING_PROBE_SHA256,
            "request_count": 2,
            "request_mode": "singleton",
        },
        "endpoints": {
            "embedding": {
                "host": "127.0.0.1",
                "path": "/v1/embeddings",
                "port": 8001,
            },
            "tokenization": {
                "host": "127.0.0.1",
                "path": "/tokenize",
                "port": 8000,
            },
        },
        "purpose": "configured_live_model_dependency_qualification",
        "schema_version": 1,
        "security": {
            "credentials_retained": False,
            "raw_probe_text_retained": False,
            "vectors_retained": False,
        },
        "tokenization": {
            "deterministic_repeat": True,
            "minimum_model_length": MINIMUM_MODEL_LENGTH,
            "model": EXPECTED_GENERATION_MODEL,
            "observed_token_count": first_token_count,
            "probe_sha256": TOKEN_PROBE_SHA256,
            "request_count": 2,
        },
    }
    artifact_sha256 = write_artifact(arguments.output, artifact)
    print(
        "configured_endpoints=pass;tokenization_port=8000;embedding_port=8001;"
        "transport_owner=operator"
    )
    print(
        f"tokenization_adapter=pass;requests=2;count={first_token_count};"
        f"minimum_model_length={MINIMUM_MODEL_LENGTH}"
    )
    print(
        f"embedding_adapter=pass;requests=2;dimension={EMBEDDING_DIMENSION};"
        f"prompt_tokens={first_embedding.prompt_tokens};maximum_repeat_delta={format(maximum_delta, '.12g')}"
    )
    print(
        f"qualification_artifact=pass;sha256={artifact_sha256};"
        "credentials_retained=false;raw_text_retained=false;vectors_retained=false"
    )
    print("configured_model_dependency_qualification=pass")


if __name__ == "__main__":
    main()
