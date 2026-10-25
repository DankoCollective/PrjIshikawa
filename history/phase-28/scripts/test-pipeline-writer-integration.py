#!/usr/bin/env python3
"""Prove accepted synthetic artifacts through the incremental writer."""

from __future__ import annotations

import sys
from pathlib import Path

import psycopg

from ishikawa.artifact_adapter import load_prepared_documents
from ishikawa.persistence import load_catalog_keys, load_published_state, write_incremental_plan
from ishikawa.planner import plan_ingestion
from ishikawa.validators import (
    validate_class_registry,
    validate_document_catalog,
    validate_ingestion_manifest,
)
from ishikawa.yaml_loader import load_restricted_yaml


METHOD_PROFILE_ID = "13fd11355c7eee3b35faadea8e14c5df0787eb70578129377c836e55dff303e4"
EMBEDDING_SPACE_ID = "fd970d304662357a07f7712639bdc0c70cc7e72b22f04c126acce57a6f9143a3"


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise RuntimeError(reason)


def scalar(connection: psycopg.Connection, query: str, parameters=()):
    row = connection.execute(query, parameters).fetchone()
    if row is None:
        raise RuntimeError("required query returned no row")
    return row[0]


def main() -> int:
    if len(sys.argv) != 8 or not sys.argv[1].startswith("ishikawa_pipeline_test"):
        raise RuntimeError("one safe disposable database and six payload paths are required")
    database = sys.argv[1]
    config_root = Path(sys.argv[2])
    source_root = Path(sys.argv[3])
    normalized_path = Path(sys.argv[4])
    chunk_path = Path(sys.argv[5])
    embedding_path = Path(sys.argv[6])
    identity_path = Path(sys.argv[7])
    identities = dict(
        line.split("  ", 1)[::-1]
        for line in identity_path.read_text(encoding="ascii").splitlines()
        if line
    )

    registry = validate_class_registry(
        load_restricted_yaml(config_root / "document_classes.yaml", label="class registry")
    )
    catalog = validate_document_catalog(
        load_restricted_yaml(config_root / "document_catalog.yaml", label="document catalog")
    )
    manifest = validate_ingestion_manifest(
        load_restricted_yaml(config_root / "ingestion_manifest.yaml", label="ingestion manifest")
    )
    prepared = load_prepared_documents(
        normalized_path=normalized_path,
        normalized_sha256=identities[normalized_path.name],
        chunk_path=chunk_path,
        chunk_sha256=identities[chunk_path.name],
        embedding_path=embedding_path,
        embedding_sha256=identities[embedding_path.name],
        manifest=manifest,
        source_root=source_root,
    )
    require(len(prepared) == 6, "prepared document count mismatch")
    require(sum(len(item.structural_units) for item in prepared) == 230, "structural unit count mismatch")
    require(sum(len(item.chunks) for item in prepared) == 125, "chunk count mismatch")
    require({item.embedding_space.identity for item in prepared} == {EMBEDDING_SPACE_ID}, "embedding identity mismatch")

    connection_info = f"dbname={database} host=/var/run/postgresql port=5432 user=postgres"
    with psycopg.connect(connection_info, autocommit=True) as connection:
        connection.execute("SET ROLE rag_ingest")
        plan = plan_ingestion(
            registry,
            catalog,
            manifest,
            source_root=source_root,
            method_profile_id=METHOD_PROFILE_ID,
            published_state={},
            prior_catalog_keys=set(),
        )
        require(plan.overall_outcome == "PASS", "initial validation plan failed")
        require(plan.action_counts()["add"] == 6, "initial plan is not six additions")
        result = write_incremental_plan(connection, registry, catalog, manifest, plan, prepared)
        require(result.outcome == "PUBLISHED" and result.published_document_count == 6, "publication failed")

        expected_counts = (3, 6, 6, 6, 230, 125, 125, 125, 1, 125, 6)
        actual_counts = connection.execute(
            """SELECT
              (SELECT count(*) FROM rag.document_classes),
              (SELECT count(*) FROM rag.documents),
              (SELECT count(*) FROM rag.document_versions),
              (SELECT count(*) FROM rag.document_artifact_sets),
              (SELECT count(*) FROM rag.structural_units),
              (SELECT count(*) FROM rag.chunks),
              (SELECT count(*) FROM rag.chunk_structural_units),
              (SELECT count(*) FROM rag.citation_anchors),
              (SELECT count(*) FROM rag.embedding_spaces),
              (SELECT count(*) FROM rag.chunk_embeddings),
              (SELECT count(*) FROM rag.active_document_versions)"""
        ).fetchone()
        require(actual_counts == expected_counts, "persisted object count mismatch")
        active_counts = connection.execute(
            """SELECT
              (SELECT count(*) FROM rag_search.active_documents),
              (SELECT count(*) FROM rag_search.active_chunks),
              (SELECT count(*) FROM rag_search.active_citations),
              (SELECT count(*) FROM rag_search.active_embeddings)"""
        ).fetchone()
        require(active_counts == (6, 125, 125, 125), "active projection count mismatch")
        require(
            scalar(connection, "SELECT count(*) FROM rag.chunks WHERE total_embedding_token_count <> content_token_count + context_token_count + prefix_token_count") == 0,
            "stored token sum mismatch",
        )
        require(
            connection.execute("SELECT min(total_embedding_token_count), max(total_embedding_token_count) FROM rag.chunks").fetchone() == (10, 57),
            "stored token range mismatch",
        )
        require(
            scalar(connection, "SELECT count(*) FROM rag.chunks WHERE lexical_vector IS NULL") == 0,
            "lexical vector missing",
        )
        require(
            scalar(connection, "SELECT count(*) FROM rag.chunk_embeddings WHERE vector_dims(embedding) <> 768") == 0,
            "stored embedding dimension mismatch",
        )
        require(
            scalar(connection, "SELECT count(*) FROM rag.chunk_embeddings WHERE embedding_space_id=%s", (EMBEDDING_SPACE_ID,)) == 125,
            "stored embedding space mismatch",
        )
        expected_input_digests = sorted(
            chunk.submitted_input_digest for document in prepared for chunk in document.chunks
        )
        stored_input_digests = sorted(
            row[0] for row in connection.execute("SELECT submitted_input_digest FROM rag.chunk_embeddings").fetchall()
        )
        require(stored_input_digests == expected_input_digests, "stored input digest mismatch")

        active = load_published_state(connection)
        reuse_plan = plan_ingestion(
            registry,
            catalog,
            manifest,
            source_root=source_root,
            method_profile_id=METHOD_PROFILE_ID,
            published_state=active,
            prior_catalog_keys=load_catalog_keys(connection),
        )
        require(reuse_plan.action_counts()["reuse"] == 6, "reuse plan mismatch")
        reuse_result = write_incremental_plan(connection, registry, catalog, manifest, reuse_plan)
        require(reuse_result.outcome == "SKIPPED" and reuse_result.reused_document_count == 6, "reuse skip failed")
        require(scalar(connection, "SELECT count(*) FROM rag.chunks") == 125, "reuse changed chunk count")

    with psycopg.connect(connection_info, autocommit=True) as retrieval:
        retrieval.execute("SET ROLE rag_retrieval")
        require(scalar(retrieval, "SELECT count(*) FROM rag_search.active_chunks") == 125, "retrieval view read failed")
        denied = False
        try:
            retrieval.execute("SELECT count(*) FROM rag.chunks").fetchone()
        except psycopg.errors.InsufficientPrivilege:
            denied = True
        require(denied, "retrieval role read a base table")

    print("runner_purpose=test_accepted_pipeline_artifacts_with_disposable_native_postgresql")
    print(f"python_version={sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")
    print(f"psycopg_version={psycopg.__version__}")
    print("synthetic_documents=6;organizational_documents=0")
    print("prepared_structural_units=230;prepared_chunks=125;prepared_embeddings=125")
    print("token_count_min=10;token_count_max=57;token_sum_contract=pass")
    print(f"embedding_space_id={EMBEDDING_SPACE_ID};embedding_dimension=768")
    print("writer_action=add_6;reuse_verification=skipped_6")
    print("active_projection=documents_6_chunks_125_citations_125_embeddings_125")
    print("retrieval_role_active_view_read=pass;retrieval_role_base_table_read=denied")
    print("pipeline_writer_postgresql_integration=pass")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(
            "pipeline_writer_postgresql_integration=blocked;"
            f"reason={type(error).__name__}",
            file=sys.stderr,
        )
        raise
