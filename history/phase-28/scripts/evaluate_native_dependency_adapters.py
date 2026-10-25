#!/usr/bin/env python3
"""Qualify Ishikawa's native scope, generation, and query-embedding adapters."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
from pathlib import Path
from typing import Any, NoReturn

from ishikawa.api_contract import decode_chat_request, validate_api_profile
from ishikawa.canonical import canonical_json_bytes
from ishikawa.generation import GroundedEvidence
from ishikawa.generation_transport import GenerationEndpoint, GenerationHTTPResponse
from ishikawa.native_adapters import (
    ACCEPTED_EMBEDDING_SPACE_ID,
    EMBEDDING_DIMENSION,
    NOMIC_MODEL,
    QUERY_PREFIX,
    EmbeddingEndpoint,
    EmbeddingHTTPResponse,
    NativeGenerationAdapter,
    NativeQueryEmbeddingAdapter,
    NativeScopeAdapter,
)
from ishikawa.reconstruction import validate_reconstruction_profile
from ishikawa.scope import validate_scope_profile
from ishikawa.yaml_loader import load_restricted_yaml


HEX = re.compile(r"^[0-9a-f]{64}$")


class EvaluationError(RuntimeError):
    pass


def fail(reason: str) -> NoReturn:
    raise EvaluationError(reason)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def require_identity(path: Path, expected: str) -> None:
    if (
        HEX.fullmatch(expected or "") is None
        or not path.is_file()
        or path.is_symlink()
        or path.stat().st_size > 1024 * 1024
        or sha256_file(path) != expected
    ):
        fail("source_identity_mismatch")


def write_artifact(path: Path, value: dict[str, Any]) -> str:
    if path.exists() or path.is_symlink() or not path.parent.is_dir():
        fail("output_path_invalid")
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(canonical_json_bytes(value) + b"\n")
    except OSError:
        fail("artifact_write_failed")
    return sha256_file(path)


def ident(character: str) -> str:
    return character * 64


def evaluate(arguments: argparse.Namespace) -> dict[str, Any]:
    sources = (
        (arguments.api_profile, arguments.expected_api_profile_sha256),
        (arguments.scope_profile, arguments.expected_scope_profile_sha256),
        (
            arguments.reconstruction_profile,
            arguments.expected_reconstruction_profile_sha256,
        ),
    )
    for path, expected in sources:
        require_identity(path, expected)

    api_policy = validate_api_profile(
        load_restricted_yaml(arguments.api_profile, label="API profile")
    )
    scope_policy = validate_scope_profile(
        load_restricted_yaml(arguments.scope_profile, label="scope profile")
    )
    reconstruction_policy = validate_reconstruction_profile(
        load_restricted_yaml(
            arguments.reconstruction_profile, label="reconstruction profile"
        )
    )

    request = decode_chat_request(
        canonical_json_bytes(
            {
                "conversation_id": ident("a"),
                "filters": {"document_classes": [], "document_keys": []},
                "history": [
                    {
                        "content": "What is required?",
                        "role": "user",
                        "turn_id": ident("b"),
                    },
                    {
                        "content": "The prior answer cited Source 1.",
                        "role": "assistant",
                        "turn_id": ident("c"),
                    },
                ],
                "message": "What else does Source 1 say?",
                "schema": "ishikawa.chat-request.v1",
                "source_references": [
                    {
                        "citation_id": ident("f"),
                        "source_id": ident("e"),
                        "source_label": "Source 1",
                    }
                ],
                "turn_id": ident("d"),
            }
        ),
        api_policy,
    )

    credential_calls = 0

    def credential_provider() -> str:
        nonlocal credential_calls
        credential_calls += 1
        return "qualification-only-secret"

    embedding_calls: list[Any] = []

    def embedding_exchange(prepared):
        embedding_calls.append(prepared)
        body = {
            "data": [
                {
                    "embedding": [1.0] * EMBEDDING_DIMENSION,
                    "index": 0,
                    "object": "embedding",
                }
            ],
            "model": NOMIC_MODEL,
            "object": "list",
            "usage": {"prompt_tokens": 12, "total_tokens": 12},
        }
        return EmbeddingHTTPResponse(
            200, "application/json", canonical_json_bytes(body)
        )

    embedding_adapter = NativeQueryEmbeddingAdapter(
        EmbeddingEndpoint("http://127.0.0.1:8001/v1/embeddings"),
        credential_provider,
        embedding_exchange,
    )
    embedded = embedding_adapter(request.message)
    if (
        len(embedding_calls) != 1
        or embedded.embedding_space_id != ACCEPTED_EMBEDDING_SPACE_ID
        or len(embedded.vector) != EMBEDDING_DIMENSION
    ):
        fail("query_embedding_adapter_mismatch")
    prepared_embedding = embedding_calls[0]
    embedding_body = json.loads(prepared_embedding.body)
    if (
        embedding_body
        != {"input": QUERY_PREFIX + request.message, "model": NOMIC_MODEL}
        or b"qualification-only-secret" in prepared_embedding.body
        or prepared_embedding.headers.get("Authorization")
        != "Bearer qualification-only-secret"
    ):
        fail("query_embedding_request_mismatch")

    scope_calls: list[dict[str, Any]] = []

    def scope_exchange(prepared):
        scope_calls.append(json.loads(prepared.body))
        content = json.dumps(
            {
                "clarification": None,
                "decision": "allow",
                "reason_code": "prior_answer_or_source_followup",
            },
            separators=(",", ":"),
        )
        body = {
            "choices": [
                {
                    "finish_reason": "stop",
                    "index": 0,
                    "message": {
                        "content": content,
                        "reasoning": None,
                        "role": "assistant",
                    },
                }
            ],
            "created": 1,
            "id": "scope-qualification",
            "model": scope_policy.served_model,
            "object": "chat.completion",
            "usage": {
                "completion_tokens": 20,
                "prompt_tokens": 527,
                "total_tokens": 547,
            },
        }
        return GenerationHTTPResponse(
            200, "application/json", canonical_json_bytes(body)
        )

    resolved_references: list[str] = []

    def display_name_resolver(reference) -> str:
        resolved_references.append(reference.source_id)
        return "Incident Reporting Procedure"

    scope_adapter = NativeScopeAdapter(
        GenerationEndpoint("http://127.0.0.1:8000/v1/chat/completions"),
        scope_policy,
        credential_provider,
        display_name_resolver,
        scope_exchange,
    )
    scope_result = scope_adapter(request)
    scope_payload = json.loads(scope_calls[0]["messages"][1]["content"])
    if (
        scope_result.decision != "allow"
        or len(scope_calls) != 1
        or resolved_references != [ident("e")]
        or scope_payload["source_references"][0]["display_name"]
        != "Incident Reporting Procedure"
    ):
        fail("scope_adapter_mismatch")

    generation_calls: list[dict[str, Any]] = []
    evidence = GroundedEvidence(
        ident("f"),
        "Source 1",
        "Reports are submitted promptly.",
        2,
        2,
        ("Reporting",),
    )

    def generation_exchange(prepared):
        generation_calls.append(json.loads(prepared.body))
        content = json.dumps(
            {
                "answer": "Reports are submitted promptly.",
                "claims": [
                    {
                        "citation_ids": [ident("f")],
                        "text": "Reports are submitted promptly.",
                    }
                ],
            },
            separators=(",", ":"),
        )
        body = {
            "choices": [
                {
                    "finish_reason": "stop",
                    "index": 0,
                    "message": {
                        "content": content,
                        "reasoning": None,
                        "role": "assistant",
                    },
                }
            ],
            "created": 1,
            "id": "generation-qualification",
            "model": reconstruction_policy.tokenizer_model,
            "object": "chat.completion",
            "usage": {
                "completion_tokens": 20,
                "prompt_tokens": 100,
                "total_tokens": 120,
            },
        }
        return GenerationHTTPResponse(
            200, "application/json", canonical_json_bytes(body)
        )

    generation_adapter = NativeGenerationAdapter(
        GenerationEndpoint("http://127.0.0.1:8000/v1/chat/completions"),
        reconstruction_policy,
        credential_provider,
        generation_exchange,
    )
    answer = generation_adapter(request, (evidence,))
    if (
        len(generation_calls) != 1
        or len(answer.claims) != 1
        or answer.claims[0].citation_ids != (ident("f"),)
        or credential_calls != 3
    ):
        fail("generation_adapter_mismatch")

    artifact = {
        "credential_delivery": "runtime_provider_to_authorization_header",
        "embedding_dimension": EMBEDDING_DIMENSION,
        "embedding_space_id": ACCEPTED_EMBEDDING_SPACE_ID,
        "generation_adapter": "native_standard_library_http",
        "generation_model": reconstruction_policy.tokenizer_model,
        "model_call": False,
        "network_contact": False,
        "nomic_model": NOMIC_MODEL,
        "purpose": "native_dependency_adapter_qualification",
        "query_prefix": QUERY_PREFIX,
        "query_request_cardinality": 1,
        "retry": False,
        "schema_version": 1,
        "scope_adapter": "native_standard_library_http",
        "scope_model": scope_policy.served_model,
        "source_metadata_resolution": "required",
        "streaming": False,
        "vector_transform": "none",
    }
    artifact_sha256 = write_artifact(arguments.output, artifact)
    return {
        "artifact_sha256": artifact_sha256,
        "reconstruction_policy_identity": reconstruction_policy.digest,
        "scope_policy_identity": scope_policy.digest,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--api-profile", type=Path, required=True)
    parser.add_argument("--expected-api-profile-sha256", required=True)
    parser.add_argument("--scope-profile", type=Path, required=True)
    parser.add_argument("--expected-scope-profile-sha256", required=True)
    parser.add_argument("--reconstruction-profile", type=Path, required=True)
    parser.add_argument("--expected-reconstruction-profile-sha256", required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    try:
        result = evaluate(arguments)
    except (EvaluationError, KeyError, TypeError, ValueError, OSError) as error:
        reason = str(error) if isinstance(error, EvaluationError) else "bounded_runtime_failure"
        print(f"native_dependency_adapter_qualification=blocked;reason={reason}")
        return 1
    print(
        f"query_embedding_model={NOMIC_MODEL};query_prefix=search_query: ;"
        f"dimension={EMBEDDING_DIMENSION};singleton=true"
    )
    print(
        f"embedding_space_id={ACCEPTED_EMBEDDING_SPACE_ID};"
        "vector_transform=none;distance=cosine"
    )
    print(
        "scope_adapter=native;generation_adapter=native;"
        "source_metadata_resolution=required"
    )
    print(
        "transport=standard_library_http;streaming=false;retry=false;"
        "runtime_credentials=true"
    )
    print(
        f"scope_policy_identity={result['scope_policy_identity']};"
        f"reconstruction_policy_identity={result['reconstruction_policy_identity']}"
    )
    print("network_contact=false;database_contact=false;model_call=false;credential_read=false")
    print(f"artifact_sha256={result['artifact_sha256']}")
    print("native_dependency_adapter_qualification=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
