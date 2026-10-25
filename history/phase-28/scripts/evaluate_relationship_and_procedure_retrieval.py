#!/usr/bin/env python3
"""Qualify bounded relationship and complete-procedure retrieval locally."""

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
    def __init__(self, mode: str):
        self.mode = mode
        self.executions: list[tuple[str, tuple[Any, ...]]] = []
        self.current: Any = None
        self.rollback_count = 0
        self.close_count = 0

    @property
    def direct(self) -> tuple[Any, ...]:
        return (ident("a"), ident("b"), ident("c"), "procedure.incident-reporting", 1.0)

    def execute(self, sql: str, parameters=()):
        parameters = tuple(parameters)
        self.executions.append((sql, parameters))
        if "postgres-retrieval.boundary" in sql:
            self.current = ("rag_retrieval", "on", "repeatable read")
        elif "retrieval.exact.citation" in sql:
            self.current = [self.direct]
        elif "retrieval.lexical" in sql:
            self.current = (
                [(ident("8"), ident("9"), ident("0"), "regulation.records", 0.7)]
                if [ident("0")] in parameters
                else [(*self.direct[:4], 0.8)]
            )
        elif "retrieval.vector" in sql:
            self.current = (
                [(ident("8"), ident("9"), ident("0"), "regulation.records", 0.75)]
                if [ident("0")] in parameters
                else [(*self.direct[:4], 0.9)]
            )
        elif "postgres-retrieval.relationship-one-hop" in sql:
            self.current = [
                (
                    ident("5"), "explicit_reference.document", ident("b"),
                    ident("9"), ident("0"), ident("6"),
                )
            ] if self.mode == "relationship" else []
        elif "postgres-retrieval.complete-procedure-inventory" in sql:
            self.current = [
                self.direct,
                (ident("f"), ident("b"), ident("c"), "procedure.incident-reporting", 1.0),
            ]
        elif "postgres-retrieval.hydrate" in sql:
            requested = set(parameters[0])
            rows = [
                (
                    ident("a"), ident("b"), ident("c"),
                    "procedure.incident-reporting", "Incident Reporting Procedure",
                    "policy_sop", ident("d"),
                    "Incidents must be reported promptly to the duty officer.",
                    "paragraph", 4, ident("e"), 2, 2,
                    ["Reporting", "Initial report"],
                ),
                (
                    ident("f"), ident("b"), ident("c"),
                    "procedure.incident-reporting", "Incident Reporting Procedure",
                    "policy_sop", ident("4"),
                    "Notify the records coordinator after the initial report.",
                    "procedure_step", 5, ident("5"), 3, 3,
                    ["Reporting", "Follow-up"],
                ),
                (
                    ident("8"), ident("9"), ident("0"),
                    "regulation.records", "Records Regulation",
                    "policy_sop", ident("1"),
                    "The referenced regulation requires records preservation.",
                    "paragraph", 2, ident("2"), 1, 1,
                    ["Records", "Preservation"],
                ),
            ]
            self.current = [row for row in rows if row[0] in requested]
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
    sources = tuple(
        (getattr(arguments, f"{name}_profile"), getattr(arguments, f"expected_{name}_profile_sha256"))
        for name in (
            "api", "resolution", "method", "reconstruction", "relevance",
            "sufficiency", "relationship",
        )
    )
    for path, expected in sources:
        require_identity(path, expected)
    load = lambda path, label: load_restricted_yaml(path, label=label)
    api = validate_api_profile(load(arguments.api_profile, "API profile"))
    resolution_policy = validate_query_resolution_profile(
        load(arguments.resolution_profile, "resolution profile")
    )
    retrieval = validate_retrieval_profile(load(arguments.method_profile, "method profile"))
    reconstruction = validate_reconstruction_profile(
        load(arguments.reconstruction_profile, "reconstruction profile")
    )
    relevance = validate_relevance_profile(load(arguments.relevance_profile, "relevance profile"))
    sufficiency = validate_sufficiency_profile(
        load(arguments.sufficiency_profile, "sufficiency profile")
    )
    relationships = validate_relationship_registry(
        load(arguments.relationship_profile, "relationship profile")
    )

    results: dict[str, Any] = {}
    for mode in ("relationship", "complete"):
        request_value = {
            "conversation_id": ident("1"),
            "filters": {
                "document_classes": ["policy_sop"],
                "document_keys": [] if mode == "relationship" else ["procedure.incident-reporting"],
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
        request = decode_chat_request(canonical_json_bytes(request_value), api)
        query = (
            "What additional incident reporting requirements apply?"
            if mode == "relationship"
            else "Provide the complete procedure."
        )
        resolution = ResolvedRetrievalQuery(
            "resolved", request.message, query,
            (ResolvedSourceConstraint(ident("c"), "Source 1", "Incident Reporting Procedure", ident("e")),),
            request.filters, None, resolution_policy.digest, ident("6"), True,
        )
        connection = QualificationConnection(mode)
        embedded: list[str] = []

        def embed(value: str) -> ValidatedQueryEmbedding:
            embedded.append(value)
            return ValidatedQueryEmbedding(
                tuple([0.01] * 768), 12, ACCEPTED_EMBEDDING_SPACE_ID, ident("7")
            )

        adapter = NativePostgresRetrievalAdapter(
            lambda: connection, embed, lambda text: max(1, len(text.split())),
            lambda messages, _kwargs: max(
                1, sum(len(message["content"].split()) for message in messages)
            ),
            retrieval, reconstruction, relevance, sufficiency, relationships,
        )
        result = adapter(request, resolution)
        statements = "\n".join(sql for sql, _ in connection.executions)
        if (
            result.sufficiency.status != "sufficient"
            or embedded != [query]
            or connection.rollback_count != 1
            or connection.close_count != 1
            or "FROM rag." in statements
            or "FROM rag_private." in statements
        ):
            fail(f"{mode}_adapter_boundary_mismatch")
        if mode == "relationship":
            if (
                {source.source_id for source in result.sources} != {ident("c"), ident("0")}
                or "postgres-retrieval.relationship-one-hop" not in statements
                or "postgres-retrieval.complete-procedure-inventory" in statements
            ):
                fail("relationship_path_mismatch")
        elif (
            len(result.sources) != 1
            or result.sources[0].source_id != ident("c")
            or len(result.sources[0].excerpts) != 2
            or "postgres-retrieval.complete-procedure-inventory" not in statements
            or "postgres-retrieval.relationship-one-hop" in statements
        ):
            fail("complete_procedure_path_mismatch")
        results[mode] = {
            "source_groups": len(result.sources),
            "citations": sum(len(source.excerpts) for source in result.sources),
        }

    artifact = {
        "complete_procedure": {
            "assembly": "source_order_atomic",
            "intent": "explicit_resolved_query",
            "inventory": "exact_active_document_version",
            **results["complete"],
        },
        "contact": {
            "credential_read": False, "database": False, "model": False, "network": False,
        },
        "purpose": "relationship_and_complete_procedure_retrieval_qualification",
        "relationship": {
            "direction": "outgoing",
            "maximum_hops": relationships.maximum_hops,
            "per_target_depth": 3,
            "provenance": "seed_edge_target_version_citation",
            "seed_scope": "direct_citation_chunks",
            "target_search": "lexical_vector_rrf",
            **results["relationship"],
        },
        "schema_version": 1,
    }
    return {
        "artifact_sha256": write_artifact(arguments.output, artifact),
        "relationship_profile_identity": relationships.method_profile_id,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    for name in (
        "api", "resolution", "method", "reconstruction", "relevance",
        "sufficiency", "relationship",
    ):
        parser.add_argument(f"--{name}-profile", type=Path, required=True)
        parser.add_argument(f"--expected-{name}-profile-sha256", required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    try:
        result = evaluate(arguments)
    except (EvaluationError, KeyError, TypeError, ValueError, OSError) as error:
        reason = str(error) if isinstance(error, EvaluationError) else "bounded_runtime_failure"
        print(f"relationship_and_procedure_retrieval_qualification=blocked;reason={reason}")
        return 1
    print("relationship_expansion=pass;maximum_hops=1;direction=outgoing;seed_scope=direct_citation_chunks;target_scope=active_authorized_version")
    print("relationship_evidence=pass;origin=relationship;provenance=seed_edge_target_version_citation;target_search=lexical_vector_rrf;per_target_depth=3")
    print("complete_procedure=pass;intent=explicit_resolved_query;inventory=exact_active_document_version;assembly=source_order_atomic")
    print("failure_boundary=fail_closed_relationship_coverage;complete_procedure=all_or_context_limit")
    print("database_boundary=repeatable_read_read_only;views=rag_search_only")
    print("network_contact=false;database_contact=false;model_call=false;credential_read=false")
    print(f"relationship_profile_identity={result['relationship_profile_identity']}")
    print(f"artifact_sha256={result['artifact_sha256']}")
    print("relationship_and_procedure_retrieval_qualification=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
