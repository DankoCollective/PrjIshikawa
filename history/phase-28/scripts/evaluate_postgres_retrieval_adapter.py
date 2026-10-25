#!/usr/bin/env python3
"""Qualify the native read-only PostgreSQL retrieval port without target contact."""

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
from ishikawa.method_profile import validate_retrieval_profile
from ishikawa.native_adapters import ACCEPTED_EMBEDDING_SPACE_ID, ValidatedQueryEmbedding
from ishikawa.postgres_retrieval import NativePostgresRetrievalAdapter
from ishikawa.query_resolution import (
    ResolvedRetrievalQuery,
    ResolvedSourceConstraint,
    validate_query_resolution_profile,
)
from ishikawa.reconstruction import validate_reconstruction_profile
from ishikawa.relevance import validate_relevance_profile
from ishikawa.relationships import validate_relationship_registry
from ishikawa.sufficiency import validate_sufficiency_profile
from ishikawa.yaml_loader import load_restricted_yaml


HEX = re.compile(r"^[0-9a-f]{64}$")


class EvaluationError(RuntimeError):
    pass


def fail(reason: str) -> NoReturn:
    raise EvaluationError(reason)


def ident(character: str) -> str:
    return character * 64


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
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(canonical_json_bytes(value) + b"\n")
    return sha256_file(path)


class QualificationConnection:
    def __init__(self):
        self.executions: list[tuple[str, tuple[Any, ...]]] = []
        self.current: Any = None
        self.rollback_count = 0
        self.close_count = 0

    def execute(self, sql, parameters=()):
        parameters = tuple(parameters)
        self.executions.append((sql, parameters))
        candidate = (ident("a"), ident("b"), ident("c"), "procedure.incident-reporting", 1.0)
        if "postgres-retrieval.boundary" in sql:
            self.current = ("rag_retrieval", "on", "repeatable read")
        elif "retrieval.exact.citation" in sql:
            self.current = [candidate]
        elif "retrieval.lexical" in sql:
            self.current = [(*candidate[:4], 0.8)]
        elif "retrieval.vector" in sql:
            self.current = [(*candidate[:4], 0.9)]
        elif "postgres-retrieval.hydrate" in sql:
            self.current = [
                (
                    ident("a"), ident("b"), ident("c"),
                    "procedure.incident-reporting", "Incident Reporting Procedure",
                    "policy_sop", ident("d"),
                    "Incidents must be reported promptly to the duty officer.",
                    "paragraph", 4, ident("e"), 2, 2,
                    ["Reporting", "Initial report"],
                )
            ]
        elif "relevance.question-lexemes" in sql:
            self.current = (["incident", "report", "requir"],)
        elif "relevance.citable-evidence-lexemes" in sql:
            self.current = [(ident("a"), ["incident", "report", "requir"])]
        else:
            self.current = []
        return self

    def fetchone(self):
        return self.current

    def fetchall(self):
        return self.current

    def rollback(self):
        self.rollback_count += 1

    def close(self):
        self.close_count += 1


def evaluate(arguments: argparse.Namespace) -> dict[str, Any]:
    sources = (
        (arguments.api_profile, arguments.expected_api_profile_sha256),
        (arguments.resolution_profile, arguments.expected_resolution_profile_sha256),
        (arguments.method_profile, arguments.expected_method_profile_sha256),
        (arguments.reconstruction_profile, arguments.expected_reconstruction_profile_sha256),
        (arguments.relevance_profile, arguments.expected_relevance_profile_sha256),
        (arguments.sufficiency_profile, arguments.expected_sufficiency_profile_sha256),
        (arguments.relationship_profile, arguments.expected_relationship_profile_sha256),
    )
    for path, expected in sources:
        require_identity(path, expected)
    load = lambda path, label: load_restricted_yaml(path, label=label)
    api_policy = validate_api_profile(load(arguments.api_profile, "API profile"))
    resolution_policy = validate_query_resolution_profile(
        load(arguments.resolution_profile, "query-resolution profile")
    )
    retrieval_policy = validate_retrieval_profile(
        load(arguments.method_profile, "method profile")
    )
    reconstruction_policy = validate_reconstruction_profile(
        load(arguments.reconstruction_profile, "reconstruction profile")
    )
    relevance_policy = validate_relevance_profile(
        load(arguments.relevance_profile, "relevance profile")
    )
    sufficiency_policy = validate_sufficiency_profile(
        load(arguments.sufficiency_profile, "sufficiency profile")
    )
    relationship_registry = validate_relationship_registry(
        load(arguments.relationship_profile, "relationship profile")
    )

    request = decode_chat_request(
        canonical_json_bytes(
            {
                "conversation_id": ident("1"),
                "filters": {
                    "document_classes": ["policy_sop"],
                    "document_keys": ["procedure.incident-reporting"],
                },
                "history": [
                    {"content": "How are incidents reported?", "role": "user", "turn_id": ident("2")},
                    {"content": "The prior answer cited Source 1.", "role": "assistant", "turn_id": ident("3")},
                ],
                "message": "What else does Source 1 say?",
                "schema": "ishikawa.chat-request.v1",
                "source_references": [
                    {"citation_id": ident("e"), "source_id": ident("c"), "source_label": "Source 1"}
                ],
                "turn_id": ident("4"),
            }
        ),
        api_policy,
    )
    resolution = ResolvedRetrievalQuery(
        "resolved",
        request.message,
        "What additional incident reporting requirements apply?",
        (ResolvedSourceConstraint(ident("c"), "Source 1", "Incident Reporting Procedure", ident("e")),),
        request.filters,
        None,
        resolution_policy.digest,
        ident("6"),
        True,
    )
    connection = QualificationConnection()
    embedded: list[str] = []

    def embed(query: str) -> ValidatedQueryEmbedding:
        embedded.append(query)
        return ValidatedQueryEmbedding(
            tuple([0.01] * 768), 12, ACCEPTED_EMBEDDING_SPACE_ID, ident("7")
        )

    adapter = NativePostgresRetrievalAdapter(
        lambda: connection,
        embed,
        lambda text: max(1, len(text.split())),
        lambda messages, _kwargs: max(
            1, sum(len(message["content"].split()) for message in messages)
        ),
        retrieval_policy,
        reconstruction_policy,
        relevance_policy,
        sufficiency_policy,
        relationship_registry,
    )
    result = adapter(request, resolution)
    if (
        result.sufficiency.status != "sufficient"
        or embedded != [resolution.resolved_query]
        or request.message in embedded
        or len(result.sources) != 1
        or result.sources[0].source_id != ident("c")
        or result.sources[0].excerpts[0].citation_id != ident("e")
        or connection.rollback_count != 1
        or connection.close_count != 1
    ):
        fail("adapter_composition_mismatch")
    statements = "\n".join(sql for sql, _ in connection.executions)
    for marker in (
        "postgres-retrieval.begin",
        "postgres-retrieval.boundary",
        "retrieval.exact.citation",
        "retrieval.lexical",
        "retrieval.vector",
        "postgres-retrieval.hydrate",
        "relevance.question-lexemes",
        "relevance.citable-evidence-lexemes",
    ):
        if marker not in statements:
            fail("database_path_incomplete")
    if "FROM rag." in statements or "FROM rag_private." in statements:
        fail("base_table_access_detected")
    filtered = [
        (sql, parameters)
        for sql, parameters in connection.executions
        if "retrieval.exact" in sql or "retrieval.lexical" in sql or "retrieval.vector" in sql
    ]
    if not filtered or any(
        "ac.class_id = ANY" not in sql
        or "ac.document_key = ANY" not in sql
        or "ac.document_version_id = ANY" not in sql
        or ["policy_sop"] not in parameters
        or ["procedure.incident-reporting"] not in parameters
        or [ident("c")] not in parameters
        for sql, parameters in filtered
    ):
        fail("pre_candidate_filter_mismatch")

    artifact = {
        "contact": {
            "credential_read": False,
            "database": False,
            "model": False,
            "network": False,
        },
        "database": {
            "expected_role": "rag_retrieval",
            "read_only_transaction": True,
            "transaction_isolation": "repeatable_read",
            "view_schema": "rag_search",
        },
        "deferred": ["one_hop_relationship_expansion", "complete_procedure_reconstruction"],
        "filters": {
            "post_hydration_recheck": True,
            "pre_candidate": True,
            "source_identity": "document_version",
        },
        "fusion": {
            "algorithm": retrieval_policy.fusion_algorithm,
            "depth": retrieval_policy.fused_candidate_depth,
            "rrf_constant": retrieval_policy.rrf_constant,
        },
        "lanes": ["exact", "lexical", "vector"],
        "purpose": "native_postgresql_retrieval_adapter_qualification",
        "query_embedding": {
            "full_transcript": False,
            "input": "resolved_query",
            "singleton": True,
        },
        "schema_version": 1,
        "source_groups": len(result.sources),
    }
    return {
        "artifact_sha256": write_artifact(arguments.output, artifact),
        "retrieval_profile_identity": retrieval_policy.digest,
        "reconstruction_profile_identity": reconstruction_policy.digest,
        "relevance_profile_identity": relevance_policy.digest,
        "sufficiency_profile_identity": sufficiency_policy.digest,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    for name in (
        "api", "resolution", "method", "reconstruction", "relevance", "sufficiency",
        "relationship",
    ):
        parser.add_argument(f"--{name}-profile", type=Path, required=True)
        parser.add_argument(f"--expected-{name}-profile-sha256", required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    try:
        result = evaluate(arguments)
    except (EvaluationError, KeyError, TypeError, ValueError, OSError) as error:
        reason = str(error) if isinstance(error, EvaluationError) else "bounded_runtime_failure"
        print(f"postgres_retrieval_adapter_qualification=blocked;reason={reason}")
        return 1
    print("retrieval_port=pass;database_role=rag_retrieval;transaction=repeatable_read_read_only;views=rag_search_only")
    print("query_embedding=resolved_query_only;full_transcript_embedded=false;singleton=true")
    print("candidate_lanes=exact,lexical,vector;fusion=reciprocal_rank_fusion;rrf_constant=60;fused_depth=20")
    print("filters=pre_candidate_and_post_hydration;source_identity=document_version")
    print("relevance=top3_citable_envelope;reconstruction=32k_budget;sufficiency=deterministic")
    print("relationship_expansion=deferred_to_next_gate;complete_procedure=deferred_to_next_gate")
    print("network_contact=false;database_contact=false;model_call=false;credential_read=false")
    print(f"retrieval_profile_identity={result['retrieval_profile_identity']}")
    print(f"reconstruction_profile_identity={result['reconstruction_profile_identity']}")
    print(f"relevance_profile_identity={result['relevance_profile_identity']}")
    print(f"sufficiency_profile_identity={result['sufficiency_profile_identity']}")
    print(f"artifact_sha256={result['artifact_sha256']}")
    print("postgres_retrieval_adapter_qualification=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
