#!/usr/bin/env python3
"""Exercise the complete read-only retrieval adapter in a disposable database."""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path
from typing import Any

import psycopg

from ishikawa.api_contract import decode_chat_request, validate_api_profile
from ishikawa.artifact_adapter import load_prepared_documents
from ishikawa.canonical import canonical_json_bytes
from ishikawa.method_profile import validate_retrieval_profile
from ishikawa.native_adapters import ValidatedQueryEmbedding
from ishikawa.persistence import write_incremental_plan
from ishikawa.planner import plan_ingestion
from ishikawa.postgres_retrieval import NativePostgresRetrievalAdapter
from ishikawa.query_resolution import (
    ResolvedRetrievalQuery,
    ResolvedSourceConstraint,
    validate_query_resolution_profile,
)
from ishikawa.reconstruction import validate_reconstruction_profile
from ishikawa.relevance import validate_relevance_profile
from ishikawa.relationships import (
    discover_prepared_relationships,
    validate_relationship_registry,
)
from ishikawa.sufficiency import validate_sufficiency_profile
from ishikawa.validators import (
    validate_class_registry,
    validate_document_catalog,
    validate_ingestion_manifest,
)
from ishikawa.yaml_loader import load_restricted_yaml


METHOD_PROFILE_ID = "5797961aee919aa73bbd99d6cc188084d57d22839a1d4cff0febc2e73e17b4b0"
EXPECTED_EMBEDDING_SPACE_ID = "fd970d304662357a07f7712639bdc0c70cc7e72b22f04c126acce57a6f9143a3"


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise RuntimeError(reason)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_json(path: Path, maximum_bytes: int) -> Any:
    require(path.is_file() and not path.is_symlink(), "unsafe JSON input")
    require(path.stat().st_size <= maximum_bytes, "oversized JSON input")
    return json.loads(path.read_text(encoding="utf-8"))


def scalar(connection: psycopg.Connection, query: str, parameters=()):
    row = connection.execute(query, parameters).fetchone()
    require(row is not None, "required query returned no row")
    return row[0]


class TracedConnection:
    """Record SQL markers while delegating to one native psycopg connection."""

    def __init__(self, connection: psycopg.Connection, statements: list[str]):
        self.connection = connection
        self.statements = statements

    def execute(self, statement, parameters=()):
        self.statements.append(str(statement))
        return self.connection.execute(statement, parameters)

    def rollback(self):
        self.connection.rollback()

    def close(self):
        self.connection.close()


def request_value(
    api_policy,
    *,
    message: str,
    version_id: str,
    citation_id: str,
    document_key: str | None,
):
    filters = {"document_classes": [], "document_keys": []}
    if document_key is not None:
        filters["document_keys"] = [document_key]
    return decode_chat_request(
        canonical_json_bytes(
            {
                "conversation_id": "1" * 64,
                "filters": filters,
                "history": [
                    {
                        "content": "Which procedure applies?",
                        "role": "user",
                        "turn_id": "2" * 64,
                    },
                    {
                        "content": "The prior response cited Source 1.",
                        "role": "assistant",
                        "turn_id": "3" * 64,
                    },
                ],
                "message": message,
                "schema": "ishikawa.chat-request.v1",
                "source_references": [
                    {
                        "citation_id": citation_id,
                        "source_id": version_id,
                        "source_label": "Source 1",
                    }
                ],
                "turn_id": "4" * 64,
            }
        ),
        api_policy,
    )


def main() -> int:
    if len(sys.argv) != 10 or not sys.argv[1].startswith("ishikawa_adapter_test"):
        raise RuntimeError("one safe disposable database and eight payload paths are required")
    database = sys.argv[1]
    config_root = Path(sys.argv[2])
    source_root = Path(sys.argv[3])
    normalized_path = Path(sys.argv[4])
    chunks_path = Path(sys.argv[5])
    embeddings_path = Path(sys.argv[6])
    query_embeddings_path = Path(sys.argv[7])
    identities_path = Path(sys.argv[8])
    expected_output_path = Path(sys.argv[9])
    require(not expected_output_path.exists(), "output path already exists")

    identities = dict(
        line.split("  ", 1)[::-1]
        for line in identities_path.read_text(encoding="ascii").splitlines()
        if line
    )
    for path in (normalized_path, chunks_path, embeddings_path, query_embeddings_path):
        require(sha256_file(path) == identities[path.name], "payload identity mismatch")

    load = lambda name: load_restricted_yaml(config_root / f"{name}.yaml", label=name)
    class_registry = validate_class_registry(load("document_classes"))
    catalog = validate_document_catalog(load("document_catalog"))
    manifest = validate_ingestion_manifest(load("ingestion_manifest"))
    api_policy = validate_api_profile(load("api_profile"))
    resolution_policy = validate_query_resolution_profile(load("query_resolution_profile"))
    retrieval_policy = validate_retrieval_profile(load("method_profile"))
    reconstruction_policy = validate_reconstruction_profile(load("reconstruction_profile"))
    relevance_policy = validate_relevance_profile(load("relevance_profile"))
    sufficiency_policy = validate_sufficiency_profile(load("sufficiency_profile"))
    relationship_registry = validate_relationship_registry(load("relationship_types"))

    prepared = load_prepared_documents(
        normalized_path=normalized_path,
        normalized_sha256=identities[normalized_path.name],
        chunk_path=chunks_path,
        chunk_sha256=identities[chunks_path.name],
        embedding_path=embeddings_path,
        embedding_sha256=identities[embeddings_path.name],
        manifest=manifest,
        source_root=source_root,
    )
    observations = discover_prepared_relationships(
        prepared,
        method_profile_id=METHOD_PROFILE_ID,
        registry=relationship_registry,
    )
    require(len(prepared) == 6, "prepared document count mismatch")
    require(sum(len(item.chunks) for item in prepared) == 126, "prepared chunk count mismatch")
    require(
        sum(item.outcome == "accepted" for item in observations) == 27
        and not any(item.requires_quarantine for item in observations),
        "relationship preparation mismatch",
    )

    connection_info = f"dbname={database} host=/var/run/postgresql port=5432 user=postgres"
    with psycopg.connect(connection_info, autocommit=True) as connection:
        connection.execute("SET ROLE rag_ingest")
        plan = plan_ingestion(
            class_registry,
            catalog,
            manifest,
            source_root=source_root,
            method_profile_id=METHOD_PROFILE_ID,
            published_state={},
            prior_catalog_keys=set(),
        )
        require(plan.overall_outcome == "PASS", "initial validation plan failed")
        result = write_incremental_plan(
            connection,
            class_registry,
            catalog,
            manifest,
            plan,
            prepared,
            relationship_registry=relationship_registry,
            relationship_observations=observations,
        )
        require(
            result.outcome == "PUBLISHED" and result.published_document_count == 6,
            "publication failed",
        )
        require(scalar(connection, "SELECT count(*) FROM rag_search.active_chunks") == 126,
                "active chunk count mismatch")
        require(scalar(connection, "SELECT count(*) FROM rag_search.active_relationships") == 27,
                "active relationship count mismatch")

    query_embeddings = load_json(query_embeddings_path, 32 * 1024 * 1024)
    require(
        query_embeddings.get("embedding_space_id") == EXPECTED_EMBEDDING_SPACE_ID
        and len(query_embeddings.get("records", [])) == 12,
        "query embedding artifact mismatch",
    )
    embedding_record = query_embeddings["records"][0]
    embedding = ValidatedQueryEmbedding(
        tuple(embedding_record["vector"]),
        embedding_record["token_accounting"]["total_embedding_input_tokens"],
        query_embeddings["embedding_space_id"],
        embedding_record["query_embedding_id"],
    )

    traces: list[list[str]] = []

    def connection_factory():
        raw = psycopg.connect(connection_info, autocommit=True)
        raw.execute("SET ROLE rag_retrieval")
        statements: list[str] = []
        traces.append(statements)
        return TracedConnection(raw, statements)

    embedded_queries: list[str] = []

    def embed_query(query: str) -> ValidatedQueryEmbedding:
        embedded_queries.append(query)
        return embedding

    adapter = NativePostgresRetrievalAdapter(
        connection_factory,
        embed_query,
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

    with psycopg.connect(connection_info, autocommit=True) as retrieval:
        retrieval.execute("SET ROLE rag_retrieval")
        relationship_row = retrieval.execute(
            """SELECT relationship.source_document_version_id,
                      relationship.evidence_citation_id,
                      target.document_version_id,
                      citation.chunk_id,
                      chunk.retrieval_text
               FROM rag_search.active_relationships relationship
               JOIN rag_search.active_documents target
                 ON target.document_id=relationship.target_identity
               JOIN rag_search.active_citations citation
                 ON citation.citation_id=relationship.evidence_citation_id
               JOIN rag_search.active_chunks chunk ON chunk.chunk_id=citation.chunk_id
               WHERE relationship.relationship_type='explicit_reference.document'
                 AND relationship.influences_retrieval=true
               ORDER BY relationship.relationship_id
               LIMIT 1"""
        ).fetchone()
        require(relationship_row is not None, "relationship scenario absent")
        procedure_row = retrieval.execute(
            """SELECT document.document_version_id, citation.citation_id
               FROM rag_search.active_documents document
               JOIN rag_search.active_citations citation
                 ON citation.document_version_id=document.document_version_id
               JOIN rag_search.active_chunks chunk ON chunk.chunk_id=citation.chunk_id
               WHERE document.document_key='procedure.incident-reporting'
               ORDER BY chunk.ordinal, citation.citation_id
               LIMIT 1"""
        ).fetchone()
        require(procedure_row is not None, "procedure scenario absent")

    relationship_version, relationship_citation, target_version, _, relationship_text = relationship_row
    relationship_request = request_value(
        api_policy,
        message="What does Source 1 say about its referenced document?",
        version_id=relationship_version,
        citation_id=relationship_citation,
        document_key=None,
    )
    relationship_resolution = ResolvedRetrievalQuery(
        "resolved",
        relationship_request.message,
        relationship_text,
        (
            ResolvedSourceConstraint(
                relationship_version, "Source 1", "Referenced source", relationship_citation
            ),
        ),
        relationship_request.filters,
        None,
        resolution_policy.digest,
        "6" * 64,
        True,
    )
    relationship_result = adapter(relationship_request, relationship_resolution)
    require(relationship_result.sufficiency.status == "sufficient",
            "relationship adapter result was not sufficient")
    require(target_version in {source.source_id for source in relationship_result.sources},
            "relationship target source was absent")

    procedure_version, procedure_citation = procedure_row
    procedure_request = request_value(
        api_policy,
        message="Provide the complete procedure from Source 1.",
        version_id=procedure_version,
        citation_id=procedure_citation,
        document_key="procedure.incident-reporting",
    )
    procedure_resolution = ResolvedRetrievalQuery(
        "resolved",
        procedure_request.message,
        "Provide the complete procedure for incident reporting.",
        (
            ResolvedSourceConstraint(
                procedure_version, "Source 1", "Incident Reporting Procedure", procedure_citation
            ),
        ),
        procedure_request.filters,
        None,
        resolution_policy.digest,
        "7" * 64,
        True,
    )
    procedure_result = adapter(procedure_request, procedure_resolution)
    require(procedure_result.sufficiency.status == "sufficient",
            "complete procedure result was not sufficient")
    require(
        len(procedure_result.sources) == 1
        and procedure_result.sources[0].source_id == procedure_version
        and len(procedure_result.sources[0].excerpts) > 1,
        "complete procedure source inventory mismatch",
    )

    require(len(embedded_queries) == 2, "query embedding call count mismatch")
    require(len(traces) == 2, "transaction trace count mismatch")
    relationship_sql = "\n".join(traces[0])
    procedure_sql = "\n".join(traces[1])
    require("postgres-retrieval.relationship-one-hop" in relationship_sql,
            "relationship SQL path absent")
    require("postgres-retrieval.complete-procedure-inventory" not in relationship_sql,
            "relationship path used complete inventory")
    require("postgres-retrieval.complete-procedure-inventory" in procedure_sql,
            "complete procedure SQL path absent")
    require("postgres-retrieval.relationship-one-hop" not in procedure_sql,
            "complete procedure path traversed relationships")
    require(
        all("FROM rag." not in trace and "FROM rag_private." not in trace for trace in traces),
        "adapter read a base schema",
    )

    with psycopg.connect(connection_info, autocommit=True) as retrieval:
        retrieval.execute("SET ROLE rag_retrieval")
        denied = False
        try:
            retrieval.execute("SELECT count(*) FROM rag.chunks").fetchone()
        except psycopg.errors.InsufficientPrivilege:
            denied = True
        require(denied, "retrieval role read a base table")

    output = {
        "complete_procedure_excerpts": len(procedure_result.sources[0].excerpts),
        "relationship_source_groups": len(relationship_result.sources),
    }
    expected_output_path.write_bytes(canonical_json_bytes(output) + b"\n")
    print("runner_purpose=qualify_complete_native_postgresql_retrieval_adapter")
    print(f"python_version={sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")
    print(f"psycopg_version={psycopg.__version__}")
    print("synthetic_documents=6;organizational_documents=0;active_chunks=126;active_relationships=27")
    print("adapter_scenarios=2;relationship=pass;complete_procedure=pass")
    print(f"relationship_target_source_present=true;relationship_source_groups={len(relationship_result.sources)}")
    print(f"complete_procedure_atomic=true;complete_procedure_excerpts={len(procedure_result.sources[0].excerpts)}")
    print("query_embedding=injected_accepted_vector;embedding_endpoint_contact=false;generation_model_contact=false")
    print("retrieval_transactions=2;isolation=repeatable_read;read_only=true;database_role=rag_retrieval")
    print("retrieval_role_active_view_read=pass;retrieval_role_base_table_read=denied")
    print("complete_retrieval_adapter_target_qualification=pass")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(
            "complete_retrieval_adapter_target_qualification=blocked;"
            f"reason={type(error).__name__}",
            file=sys.stderr,
        )
        raise
