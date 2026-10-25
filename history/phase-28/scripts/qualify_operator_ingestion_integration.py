#!/usr/bin/env python3
"""Exercise operator-ingestion orchestration in disposable PostgreSQL."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import psycopg

from ishikawa.artifact_adapter import load_prepared_documents
from ishikawa.operator_ingestion import (
    OperatorIngestionPaths,
    load_operator_configuration,
    run_operator_ingestion,
)


METHOD_PROFILE_ID = "5797961aee919aa73bbd99d6cc188084d57d22839a1d4cff0febc2e73e17b4b0"
EMBEDDING_SPACE_ID = "fd970d304662357a07f7712639bdc0c70cc7e72b22f04c126acce57a6f9143a3"


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise RuntimeError(reason)


def scalar(connection, query: str, parameters=()):
    row = connection.execute(query, parameters).fetchone()
    if row is None:
        raise RuntimeError("required database result absent")
    return row[0]


def main() -> int:
    if len(sys.argv) != 9 or not sys.argv[1].startswith("ishikawa_ingestion_test"):
        raise RuntimeError("one disposable database and seven payload paths are required")
    database = sys.argv[1]
    config_root = Path(sys.argv[2])
    source_root = Path(sys.argv[3])
    normalized_path = Path(sys.argv[4])
    chunk_path = Path(sys.argv[5])
    embedding_path = Path(sys.argv[6])
    identity_path = Path(sys.argv[7])
    report_root = Path(sys.argv[8])
    identities = dict(
        line.split("  ", 1)[::-1]
        for line in identity_path.read_text(encoding="ascii").splitlines()
        if line
    )

    paths = OperatorIngestionPaths(
        config_root / "document_classes.yaml",
        config_root / "document_catalog.yaml",
        config_root / "ingestion_manifest.yaml",
        source_root,
        report_root / "validate",
    )
    connection_info = f"dbname={database} host=/var/run/postgresql port=5432 user=postgres"
    producer_calls = 0
    produced_documents = 0

    def producer(batch):
        nonlocal producer_calls, produced_documents
        producer_calls += 1
        require(len(batch.documents) == 6, "producer request count mismatch")
        require({item.action for item in batch.documents} == {"add"}, "producer action mismatch")
        prepared = load_prepared_documents(
            normalized_path=normalized_path,
            normalized_sha256=identities[normalized_path.name],
            chunk_path=chunk_path,
            chunk_sha256=identities[chunk_path.name],
            embedding_path=embedding_path,
            embedding_sha256=identities[embedding_path.name],
            manifest=load_operator_configuration(paths)[2],
            source_root=source_root,
        )
        require(len(prepared) == 6, "prepared document count mismatch")
        require(sum(len(item.chunks) for item in prepared) == 126, "prepared chunk count mismatch")
        require(
            {item.embedding_space.identity for item in prepared} == {EMBEDDING_SPACE_ID},
            "embedding space mismatch",
        )
        produced_documents += len(prepared)
        return prepared

    with psycopg.connect(connection_info, autocommit=True) as connection:
        connection.execute("SET ROLE rag_ingest")

        validation = run_operator_ingestion(
            paths=paths,
            method_profile_id=METHOD_PROFILE_ID,
            connection=connection,
            validate_only=True,
            producer=producer,
        )
        require(validation.exit_code == 0, "validation-only result failed")
        require(validation.plan.action_counts()["add"] == 6, "validation-only add plan mismatch")
        require(producer_calls == 0, "validation-only invoked producer")
        require(scalar(connection, "SELECT count(*) FROM rag.ingestion_runs") == 0,
                "validation-only mutated database")

        add_paths = OperatorIngestionPaths(
            paths.class_registry,
            paths.document_catalog,
            paths.ingestion_manifest,
            paths.source_root,
            report_root / "add",
        )
        publication = run_operator_ingestion(
            paths=add_paths,
            method_profile_id=METHOD_PROFILE_ID,
            connection=connection,
            validate_only=False,
            producer=producer,
        )
        require(publication.exit_code == 0, "publication exit code mismatch")
        require(publication.write_result is not None, "publication result absent")
        require(publication.write_result.outcome == "PUBLISHED", "publication outcome mismatch")
        require(publication.write_result.published_document_count == 6,
                "published document count mismatch")
        require(producer_calls == 1 and produced_documents == 6,
                "producer invocation mismatch")
        require(scalar(connection, "SELECT count(*) FROM rag_search.active_chunks") == 126,
                "active chunk count mismatch")
        require(scalar(connection, "SELECT count(*) FROM rag_search.active_embeddings") == 126,
                "active embedding count mismatch")

        reuse_paths = OperatorIngestionPaths(
            paths.class_registry,
            paths.document_catalog,
            paths.ingestion_manifest,
            paths.source_root,
            report_root / "reuse",
        )
        reuse = run_operator_ingestion(
            paths=reuse_paths,
            method_profile_id=METHOD_PROFILE_ID,
            connection=connection,
            validate_only=False,
            producer=producer,
        )
        require(reuse.write_result is not None and reuse.write_result.outcome == "SKIPPED",
                "reuse outcome mismatch")
        require(reuse.plan.action_counts()["reuse"] == 6, "reuse plan mismatch")
        require(producer_calls == 1, "reuse invoked producer")

        quarantine_manifest = config_root / "quarantine_manifest.yaml"
        quarantine_manifest.write_text(
            """schema_version: 1
documents:
  - source_path: missing.pdf
    document_key: policy.unknown
    class_id: policy_sop
retirements: []
""",
            encoding="utf-8",
        )
        quarantine_paths = OperatorIngestionPaths(
            paths.class_registry,
            paths.document_catalog,
            quarantine_manifest,
            paths.source_root,
            report_root / "quarantine",
        )
        quarantine = run_operator_ingestion(
            paths=quarantine_paths,
            method_profile_id=METHOD_PROFILE_ID,
            connection=connection,
            validate_only=False,
            producer=producer,
        )
        require(quarantine.exit_code != 0, "quarantine exit code mismatch")
        require(
            quarantine.write_result is not None
            and quarantine.write_result.outcome == "QUARANTINED"
            and quarantine.write_result.quarantine_record_count == 1,
            "quarantine persistence mismatch",
        )
        require(producer_calls == 1, "quarantine invoked producer")
        require(scalar(connection, "SELECT count(*) FROM rag_search.active_chunks") == 126,
                "quarantine changed active chunks")

        counts = connection.execute(
            """SELECT
              (SELECT count(*) FROM rag.document_classes),
              (SELECT count(*) FROM rag.documents),
              (SELECT count(*) FROM rag.document_versions),
              (SELECT count(*) FROM rag.document_artifact_sets),
              (SELECT count(*) FROM rag.structural_units),
              (SELECT count(*) FROM rag.chunks),
              (SELECT count(*) FROM rag.citation_anchors),
              (SELECT count(*) FROM rag.chunk_embeddings),
              (SELECT count(*) FROM rag.active_document_versions),
              (SELECT count(*) FROM rag_private.quarantine_records)"""
        ).fetchone()
        require(counts == (3, 6, 6, 6, 231, 126, 126, 126, 6, 1),
                "persisted object count mismatch")

    protected_reports = tuple(report_root.glob("*/*.json"))
    require(len(protected_reports) == 4, "protected report count mismatch")
    require(all((os.stat(path).st_mode & 0o777) == 0o600 for path in protected_reports),
            "protected report mode mismatch")
    require(
        all(
            not json.loads(path.read_text(encoding="utf-8"))["mutation_performed"]
            for path in protected_reports
            if path.parent.name == "validate"
        ),
        "validation report mutation flag mismatch",
    )

    print("runner_purpose=qualify_operator_ingestion_with_disposable_native_postgresql")
    print(f"python_version={sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")
    print(f"psycopg_version={psycopg.__version__}")
    print("validation_only=pass;planned_adds=6;producer_calls=0;database_mutations=0")
    print("publication=pass;published_documents=6;producer_calls=1;produced_documents=6")
    print("reuse=pass;reused_documents=6;producer_calls_after_reuse=1")
    print("quarantine=pass;quarantine_records=1;producer_calls_after_quarantine=1;active_chunks=126")
    print("persisted_documents=6;structural_units=231;chunks=126;citations=126;embeddings=126")
    print("reports=4;json_mode=0600;source_content_reported=false")
    print("embedding_endpoint_contact=false;generation_model_contact=false")
    print("operator_ingestion_target_qualification=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
