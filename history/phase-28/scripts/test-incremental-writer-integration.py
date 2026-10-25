#!/usr/bin/env python3
"""Disposable synthetic integration proof for the incremental writer."""

from __future__ import annotations

import hashlib
import sys
import tempfile
from pathlib import Path

import psycopg

from ishikawa.persistence import load_published_state, write_incremental_plan
from ishikawa.persistence_models import (
    EmbeddingSpace,
    PreparedChunk,
    PreparedDocument,
    PreparedStructuralUnit,
)
from ishikawa.planner import plan_ingestion
from ishikawa.validators import (
    validate_class_registry,
    validate_document_catalog,
    validate_ingestion_manifest,
)

METHOD_PROFILE_ID = "a" * 64


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise RuntimeError(reason)


def scalar(connection: psycopg.Connection, query: str, parameters=()):
    row = connection.execute(query, parameters).fetchone()
    if row is None:
        raise RuntimeError("required integration query returned no row")
    return row[0]


def registry():
    return validate_class_registry(
        {
            "schema_version": 1,
            "classes": [
                {"class_id": "policy", "display_name": "Policy", "status": "active"},
                {
                    "class_id": "regulation",
                    "display_name": "Regulation",
                    "status": "active",
                },
            ],
        }
    )


def catalog(items):
    return validate_document_catalog({"schema_version": 1, "documents": items})


def manifest(*, path=None, key=None, class_id=None, retirement=None):
    documents = []
    retirements = []
    if path is not None:
        documents.append({"source_path": path, "document_key": key, "class_id": class_id})
    if retirement is not None:
        retirements.append({"document_key": retirement})
    return validate_ingestion_manifest(
        {"schema_version": 1, "documents": documents, "retirements": retirements}
    )


def write_pdf(path: Path, label: str) -> str:
    content = f"%PDF-1.4\nSynthetic Ishikawa integration fixture: {label}\n%%EOF\n".encode()
    path.write_bytes(content)
    return hashlib.sha256(content).hexdigest()


def embedding_space():
    return EmbeddingSpace(
        model_name="nomic-embed-text-v1.5",
        model_revision="synthetic-integration",
        model_digest="b" * 64,
        tokenizer_digest="c" * 64,
        pooling_method="mean",
        document_prefix="search_document: ",
        query_prefix="search_query: ",
    )


def prepared(key: str, class_id: str, source_digest: str, label: str, *, config="english"):
    unit = PreparedStructuralUnit(
        ordinal=0,
        structural_kind="paragraph",
        page_start=1,
        page_end=1,
        structural_path=("Synthetic",),
        source_anchor={"page": 1, "fixture": True},
        normalized_text=f"Synthetic procedure text for {label}.",
    )
    chunk = PreparedChunk(
        ordinal=0,
        projection_kind="narrative",
        retrieval_text=f"Synthetic\nSynthetic procedure text for {label}.",
        structural_unit_ordinals=(0,),
        relevant_excerpt=f"Synthetic procedure text for {label}.",
        page_start=1,
        page_end=1,
        structural_path=("Synthetic",),
        citation_anchor={"page": 1},
        embedding=(1.0,) + (0.0,) * 767,
        content_token_count=6,
        context_token_count=1,
        prefix_token_count=2,
        special_token_count=0,
        submitted_input_digest="d" * 64,
        processing_profile="hierarchical_narrative",
        lexical_search_config=config,
    )
    return PreparedDocument(
        document_key=key,
        class_id=class_id,
        source_digest=source_digest,
        page_count=1,
        processing_profiles=("hierarchical_narrative",),
        structural_units=(unit,),
        chunks=(chunk,),
        embedding_space=embedding_space(),
        language="en",
    )


def plan(registry_value, catalog_value, manifest_value, root, published):
    return plan_ingestion(
        registry_value,
        catalog_value,
        manifest_value,
        source_root=root,
        method_profile_id=METHOD_PROFILE_ID,
        published_state=published,
        prior_catalog_keys=None,
    )


def main() -> int:
    if len(sys.argv) != 2 or not sys.argv[1].startswith("ishikawa_writer_test"):
        raise RuntimeError("one safe disposable database name is required")
    database = sys.argv[1]
    connection_info = f"dbname={database} host=/var/run/postgresql port=5432 user=postgres"
    registry_value = registry()

    with tempfile.TemporaryDirectory(prefix="ishikawa-writer-fixture.") as temporary:
        root = Path(temporary)
        policies = root / "policies"
        policies.mkdir(mode=0o700)
        alpha = policies / "alpha.pdf"
        beta = policies / "beta.pdf"
        rollback = policies / "rollback.pdf"

        with psycopg.connect(connection_info, autocommit=True) as connection:
            connection.execute("SET ROLE rag_ingest")

            alpha_catalog = catalog(
                [{"document_key": "policy.alpha", "display_name": "Alpha", "status": "active"}]
            )
            alpha_manifest = manifest(
                path="policies/alpha.pdf", key="policy.alpha", class_id="policy"
            )

            alpha_v1 = write_pdf(alpha, "alpha-v1")
            add_plan = plan(registry_value, alpha_catalog, alpha_manifest, root, {})
            require(add_plan.entries[0].action == "add", "add planning failed")
            add_result = write_incremental_plan(
                connection,
                registry_value,
                alpha_catalog,
                alpha_manifest,
                add_plan,
                (prepared("policy.alpha", "policy", alpha_v1, "alpha-v1"),),
            )
            require(add_result.outcome == "PUBLISHED", "add publication failed")

            active = load_published_state(connection)
            reuse_plan = plan(registry_value, alpha_catalog, alpha_manifest, root, active)
            require(reuse_plan.entries[0].action == "reuse", "reuse planning failed")
            reuse_result = write_incremental_plan(
                connection, registry_value, alpha_catalog, alpha_manifest, reuse_plan
            )
            require(reuse_result.outcome == "SKIPPED", "reuse skip failed")

            alpha_v2 = write_pdf(alpha, "alpha-v2")
            active = load_published_state(connection)
            revise_plan = plan(registry_value, alpha_catalog, alpha_manifest, root, active)
            require(revise_plan.entries[0].action == "revise", "revision planning failed")
            revise_result = write_incremental_plan(
                connection,
                registry_value,
                alpha_catalog,
                alpha_manifest,
                revise_plan,
                (prepared("policy.alpha", "policy", alpha_v2, "alpha-v2"),),
            )
            require(revise_result.outcome == "PUBLISHED", "revision publication failed")

            regulation_manifest = manifest(
                path="policies/alpha.pdf", key="policy.alpha", class_id="regulation"
            )
            active = load_published_state(connection)
            reprocess_plan = plan(
                registry_value, alpha_catalog, regulation_manifest, root, active
            )
            require(reprocess_plan.entries[0].action == "reprocess", "reprocess planning failed")
            reprocess_result = write_incremental_plan(
                connection,
                registry_value,
                alpha_catalog,
                regulation_manifest,
                reprocess_plan,
                (prepared("policy.alpha", "regulation", alpha_v2, "alpha-v2-regulation"),),
            )
            require(reprocess_result.outcome == "PUBLISHED", "reprocess publication failed")

            beta_manifest = manifest(
                path="policies/beta.pdf", key="policy.beta", class_id="policy"
            )
            active = load_published_state(connection)
            quarantine_plan = plan(
                registry_value, alpha_catalog, beta_manifest, root, active
            )
            require(quarantine_plan.overall_outcome == "QUARANTINED", "quarantine planning failed")
            quarantine_result = write_incremental_plan(
                connection, registry_value, alpha_catalog, beta_manifest, quarantine_plan
            )
            require(quarantine_result.quarantine_record_count == 1, "quarantine write failed")

            beta_digest = write_pdf(beta, "beta-v1")
            expanded_catalog = catalog(
                [
                    {"document_key": "policy.alpha", "display_name": "Alpha", "status": "active"},
                    {"document_key": "policy.beta", "display_name": "Beta", "status": "active"},
                ]
            )
            active = load_published_state(connection)
            remediation_plan = plan(
                registry_value, expanded_catalog, beta_manifest, root, active
            )
            remediation_result = write_incremental_plan(
                connection,
                registry_value,
                expanded_catalog,
                beta_manifest,
                remediation_plan,
                (prepared("policy.beta", "policy", beta_digest, "beta-v1"),),
            )
            require(remediation_result.outcome == "PUBLISHED", "remediation publication failed")
            remediation_contract = scalar(
                connection,
                """SELECT count(*) FROM rag_private.quarantine_records
                   WHERE resolution_code='successful_retry'
                     AND resolved_at IS NOT NULL AND resolved_by_run_id IS NOT NULL""",
            )
            require(remediation_contract == 1, "quarantine remediation linkage failed")

            rollback_digest = write_pdf(rollback, "rollback-v1")
            rollback_catalog = catalog(
                [
                    {"document_key": "policy.alpha", "display_name": "Alpha", "status": "active"},
                    {"document_key": "policy.beta", "display_name": "Beta", "status": "active"},
                    {
                        "document_key": "policy.rollback",
                        "display_name": "Rollback",
                        "status": "active",
                    },
                ]
            )
            rollback_manifest = manifest(
                path="policies/rollback.pdf", key="policy.rollback", class_id="policy"
            )
            active = load_published_state(connection)
            rollback_plan = plan(
                registry_value, rollback_catalog, rollback_manifest, root, active
            )
            rollback_failed = False
            try:
                write_incremental_plan(
                    connection,
                    registry_value,
                    rollback_catalog,
                    rollback_manifest,
                    rollback_plan,
                    (
                        prepared(
                            "policy.rollback",
                            "policy",
                            rollback_digest,
                            "rollback-v1",
                            config="not_a_postgresql_text_search_configuration",
                        ),
                    ),
                )
            except psycopg.Error:
                rollback_failed = True
            require(rollback_failed, "synthetic transaction failure was not triggered")
            require(
                scalar(
                    connection,
                    "SELECT count(*) FROM rag.documents WHERE document_key='policy.rollback'",
                )
                == 0,
                "failed batch leaked a catalog document",
            )

            retired_catalog = catalog(
                [
                    {"document_key": "policy.alpha", "display_name": "Alpha", "status": "retired"},
                    {"document_key": "policy.beta", "display_name": "Beta", "status": "active"},
                ]
            )
            retirement_manifest = manifest(retirement="policy.alpha")
            active = load_published_state(connection)
            retirement_plan = plan(
                registry_value, retired_catalog, retirement_manifest, root, active
            )
            retirement_result = write_incremental_plan(
                connection,
                registry_value,
                retired_catalog,
                retirement_manifest,
                retirement_plan,
            )
            require(retirement_result.retired_document_count == 1, "retirement failed")

            active_document_count = scalar(connection, "SELECT count(*) FROM rag_search.active_documents")
            active_chunk_count = scalar(connection, "SELECT count(*) FROM rag_search.active_chunks")
            active_citation_count = scalar(connection, "SELECT count(*) FROM rag_search.active_citations")
            active_embedding_count = scalar(connection, "SELECT count(*) FROM rag_search.active_embeddings")
            require(
                (active_document_count, active_chunk_count, active_citation_count, active_embedding_count)
                == (1, 1, 1, 1),
                "active retrieval projection mismatch",
            )
            require(
                scalar(
                    connection,
                    "SELECT count(*) FROM rag_search.active_documents WHERE document_key='policy.beta'",
                )
                == 1,
                "unexpected active document after retirement",
            )

        with psycopg.connect(connection_info, autocommit=True) as retrieval:
            retrieval.execute("SET ROLE rag_retrieval")
            require(
                scalar(retrieval, "SELECT count(*) FROM rag_search.active_chunks") == 1,
                "retrieval role cannot read the active view",
            )
            base_table_denied = False
            try:
                retrieval.execute("SELECT count(*) FROM rag.chunks").fetchone()
            except psycopg.errors.InsufficientPrivilege:
                base_table_denied = True
            require(base_table_denied, "retrieval role unexpectedly read a base table")

    print("runner_purpose=test_incremental_writer_with_disposable_native_postgresql")
    print(f"python_version={sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")
    print(f"psycopg_version={psycopg.__version__}")
    print("synthetic_documents=3;organizational_documents=0")
    print("writer_actions=add_reuse_revise_reprocess_quarantine_remediate_retire")
    print("atomic_failure_rollback=pass")
    print("active_projection=document_1_chunk_1_citation_1_embedding_1")
    print("retrieval_role_active_view_read=pass;retrieval_role_base_table_read=denied")
    print("incremental_writer_postgresql_integration=pass")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(
            "incremental_writer_postgresql_integration=blocked;"
            f"reason={type(error).__name__}",
            file=sys.stderr,
        )
        raise
