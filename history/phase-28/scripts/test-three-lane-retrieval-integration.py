#!/usr/bin/env python3
"""Prove exact, lexical, vector, and RRF retrieval over active views."""

from __future__ import annotations

import sys
from pathlib import Path

import psycopg

from ishikawa.artifact_adapter import load_prepared_documents
from ishikawa.persistence import load_catalog_keys, load_published_state, write_incremental_plan
from ishikawa.planner import plan_ingestion
from ishikawa.retrieval import exact_lookup, lexical_search, reciprocal_rank_fusion, vector_search
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
    if len(sys.argv) != 8 or not sys.argv[1].startswith("ishikawa_retrieval_test"):
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
    target_document = next(item for item in prepared if item.document_key == "policy.ops-17-control-2001")
    target_chunk = next(item for item in target_document.chunks if "Authorized Requester" in item.retrieval_text)

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
            scalar(connection, "SELECT count(*) FROM rag.chunks WHERE total_embedding_token_count <> content_token_count + context_token_count + prefix_token_count + special_token_count") == 0,
            "stored token sum mismatch",
        )
        require(
            scalar(connection, "SELECT count(*) FROM rag.chunks WHERE special_token_count <> 2") == 0,
            "stored special-token count mismatch",
        )
        require(
            scalar(
                connection,
                "SELECT count(*) FROM rag.chunks WHERE prefix_token_count <> (contextual_fields #>> '{token_accounting,prefix_tokens_without_special}')::integer",
            ) == 0,
            "stored prefix-token count mismatch",
        )
        require(
            scalar(
                connection,
                "SELECT count(*) FROM rag.chunks WHERE special_token_count <> (contextual_fields #>> '{token_accounting,special_tokens}')::integer",
            ) == 0,
            "stored token metadata mismatch",
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
        document_exact = exact_lookup(retrieval, "document_key", target_document.document_key, depth=10)
        require(len(document_exact) == 10, "document-key exact depth mismatch")
        require({item.document_key for item in document_exact} == {target_document.document_key}, "document-key exact filter mismatch")

        lexical = lexical_search(retrieval, "Authorized Requester", depth=10)
        require(lexical, "lexical lane returned no candidates")
        vector = vector_search(retrieval, target_chunk.embedding, EMBEDDING_SPACE_ID, depth=10)
        require(len(vector) == 10, "vector lane depth mismatch")
        require(abs(vector[0].raw_score - 1.0) <= 0.00001, "vector self-similarity mismatch")
        require(not vector_search(retrieval, target_chunk.embedding, "0" * 64, depth=10), "unknown embedding space produced candidates")
        exact = exact_lookup(retrieval, "chunk_id", vector[0].chunk_id, depth=10)
        require(len(exact) == 1 and exact[0].chunk_id == vector[0].chunk_id, "exact lane mismatch")
        require(any(item.chunk_id == exact[0].chunk_id for item in lexical), "lexical lane omitted target chunk")
        require(not exact_lookup(retrieval, "chunk_id", "0" * 64, depth=10), "an unknown chunk identity produced an exact hit")

        fused = reciprocal_rank_fusion({"exact": exact, "lexical": lexical, "vector": vector}, rrf_constant=60)
        replay = reciprocal_rank_fusion({"exact": exact, "lexical": lexical, "vector": vector}, rrf_constant=60)
        require(fused == replay, "RRF replay is not deterministic")
        require(fused[0].chunk_id == exact[0].chunk_id, "exact-priority fusion mismatch")
        require({item.lane for item in fused[0].evidence} == {"exact", "lexical", "vector"}, "fusion provenance mismatch")
        require(len({item.chunk_id for item in fused}) == len(fused), "fusion retained duplicate chunks")
        denied = False
        try:
            retrieval.execute("SELECT count(*) FROM rag.chunks").fetchone()
        except psycopg.errors.InsufficientPrivilege:
            denied = True
        require(denied, "retrieval role read a base table")

    print("runner_purpose=test_three_lane_retrieval_with_disposable_native_postgresql")
    print(f"python_version={sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")
    print(f"psycopg_version={psycopg.__version__}")
    print("synthetic_documents=6;organizational_documents=0")
    print("prepared_structural_units=230;prepared_chunks=125;prepared_embeddings=125")
    print("writer_fixture=documents_6_chunks_125_embeddings_125;schema_version=3")
    print(f"embedding_space_id={EMBEDDING_SPACE_ID};embedding_dimension=768")
    print("exact_lane=chunk_and_document_reference;exact_target_hits=1;missing_hits=0")
    print(f"lexical_lane=postgresql_full_text;candidate_depth=10;returned={len(lexical)};target_present=true")
    print(f"vector_lane=pgvector_cosine;candidate_depth=10;returned={len(vector)};target_rank=1")
    print(f"fusion=rrf;rrf_constant=60;fused_candidates={len(fused)};target_rank=1")
    print("fusion_deduplication=canonical_chunk_identity;fusion_provenance=exact_lexical_vector;deterministic_replay=pass")
    print("retrieval_role_active_view_read=pass;retrieval_role_base_table_read=denied")
    print("question_embedding=not_run;held_out_retrieval_calibration=not_run")
    print("three_lane_retrieval_foundation=pass")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(
            "three_lane_retrieval_foundation=blocked;"
            f"reason={type(error).__name__}",
            file=sys.stderr,
        )
        raise
