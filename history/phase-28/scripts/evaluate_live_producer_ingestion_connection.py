#!/usr/bin/env python3
"""Connect accepted live document artifacts to operator ingestion safely."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import tempfile
from pathlib import Path

from ishikawa.canonical import canonical_json_bytes, file_sha256
from ishikawa.document_producer import (
    METHOD_PROFILE_ID,
    NativeDocumentProducer,
    ProducerArtifactBundle,
)
from ishikawa.operator_ingestion import (
    OperatorIngestionPaths,
    load_operator_configuration,
    run_operator_ingestion,
)
from ishikawa.persistence_models import WriteResult


EXPECTED_EMBEDDING_SPACE_ID = (
    "fd970d304662357a07f7712639bdc0c70cc7e72b22f04c126acce57a6f9143a3"
)


class Rows:
    """Minimal read-only result used by the planning boundary."""

    def __init__(self, values=()):
        self.values = list(values)

    def fetchall(self):
        return list(self.values)


class EmptyPlanningConnection:
    """Expose only the two reads allowed during empty-corpus planning."""

    def __init__(self):
        self.tags: list[str] = []

    def execute(self, sql, _parameters=()):
        if "ishikawa.load-published-state" in sql:
            self.tags.append("load-published-state")
            return Rows()
        if "ishikawa.load-catalog-keys" in sql:
            self.tags.append("load-catalog-keys")
            return Rows()
        raise RuntimeError("unexpected_planning_database_operation")


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise RuntimeError(reason)


def write_exclusive(path: Path, document: dict[str, object]) -> tuple[str, int]:
    payload = canonical_json_bytes(document) + b"\n"
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)
    return file_sha256(str(path)), len(payload)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config-root", required=True, type=Path)
    parser.add_argument("--source-root", required=True, type=Path)
    parser.add_argument("--normalized", required=True, type=Path)
    parser.add_argument("--normalized-sha256", required=True)
    parser.add_argument("--chunks", required=True, type=Path)
    parser.add_argument("--chunks-sha256", required=True)
    parser.add_argument("--embeddings", required=True, type=Path)
    parser.add_argument("--embeddings-sha256", required=True)
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()

    for path, expected, label in (
        (arguments.normalized, arguments.normalized_sha256, "normalized"),
        (arguments.chunks, arguments.chunks_sha256, "chunks"),
        (arguments.embeddings, arguments.embeddings_sha256, "embeddings"),
    ):
        require(path.is_file() and not path.is_symlink(), f"{label}_artifact_unsafe")
        require(file_sha256(str(path)) == expected, f"{label}_artifact_identity_mismatch")
    require(
        arguments.config_root.is_dir()
        and not arguments.config_root.is_symlink()
        and arguments.source_root.is_dir()
        and not arguments.source_root.is_symlink(),
        "operator_input_root_unsafe",
    )
    require(
        arguments.output.is_absolute()
        and not arguments.output.exists()
        and not arguments.output.is_symlink()
        and arguments.output.parent.is_dir(),
        "output_path_unsafe",
    )

    with tempfile.TemporaryDirectory(prefix="live-producer-connection-") as temporary:
        root = Path(temporary)
        work_root = root / "work"
        report_root = root / "reports"
        work_root.mkdir(mode=0o700)
        paths = OperatorIngestionPaths(
            arguments.config_root / "document_classes.yaml",
            arguments.config_root / "document_catalog.yaml",
            arguments.config_root / "ingestion_manifest.yaml",
            arguments.source_root,
            report_root / "validate",
        )
        _, _, manifest = load_operator_configuration(paths)

        stage_calls = 0
        retention_calls = 0
        writer_calls = 0
        stage_workspaces: list[Path] = []
        prepared_counts: tuple[int, int, int, int] | None = None

        def artifact_stage(batch, subset, workspace):
            nonlocal stage_calls
            stage_calls += 1
            stage_workspaces.append(workspace)
            require(len(batch.documents) == 6, "production_batch_count_mismatch")
            require({item.action for item in batch.documents} == {"add"}, "production_action_mismatch")
            require(len(subset.documents) == 6 and not subset.retirements, "production_subset_mismatch")
            outputs: list[tuple[Path, str]] = []
            for source, name, expected in (
                (arguments.normalized, "normalized.json", arguments.normalized_sha256),
                (arguments.chunks, "chunks.json", arguments.chunks_sha256),
                (arguments.embeddings, "embeddings.json", arguments.embeddings_sha256),
            ):
                destination = workspace / name
                shutil.copyfile(source, destination)
                require(file_sha256(str(destination)) == expected, "workspace_artifact_copy_mismatch")
                outputs.append((destination, expected))
            return ProducerArtifactBundle(
                outputs[0][0], outputs[0][1],
                outputs[1][0], outputs[1][1],
                outputs[2][0], outputs[2][1],
            )

        def retain(bundle):
            nonlocal retention_calls
            retention_calls += 1
            require(
                file_sha256(str(bundle.normalized_path)) == bundle.normalized_sha256
                and file_sha256(str(bundle.chunk_path)) == bundle.chunk_sha256
                and file_sha256(str(bundle.embedding_path)) == bundle.embedding_sha256,
                "retained_bundle_identity_mismatch",
            )

        producer = NativeDocumentProducer(
            manifest=manifest,
            work_root=work_root.resolve(),
            artifact_stage=artifact_stage,
            artifact_retainer=retain,
        )

        validation_connection = EmptyPlanningConnection()
        validation = run_operator_ingestion(
            paths=paths,
            method_profile_id=METHOD_PROFILE_ID,
            connection=validation_connection,
            validate_only=True,
            producer=producer,
            writer=lambda *_items: (_ for _ in ()).throw(
                RuntimeError("validation_only_writer_called")
            ),
        )
        require(validation.exit_code == 0, "validation_only_failed")
        require(validation.plan.action_counts().get("add") == 6, "validation_plan_mismatch")
        require(stage_calls == 0 and retention_calls == 0, "validation_only_produced_documents")
        require(
            validation_connection.tags == ["load-published-state", "load-catalog-keys"],
            "validation_database_read_contract_mismatch",
        )

        def writer(_connection, _registry, _catalog, _manifest, plan, prepared):
            nonlocal writer_calls, prepared_counts
            writer_calls += 1
            require(plan.overall_outcome == "PASS", "writer_plan_outcome_mismatch")
            require(len(prepared) == 6, "prepared_document_count_mismatch")
            prepared_counts = (
                sum(item.page_count for item in prepared),
                sum(len(item.structural_units) for item in prepared),
                sum(len(item.chunks) for item in prepared),
                len({item.embedding_space.identity for item in prepared}),
            )
            require(prepared_counts == (27, 231, 126, 1), "prepared_inventory_mismatch")
            require(
                {item.embedding_space.identity for item in prepared}
                == {EXPECTED_EMBEDDING_SPACE_ID},
                "prepared_embedding_space_mismatch",
            )
            require(
                all(len(chunk.embedding) == 768 for item in prepared for chunk in item.chunks),
                "prepared_embedding_dimension_mismatch",
            )
            return WriteResult(
                ingestion_run_id="1" * 64,
                publication_batch_id="2" * 64,
                outcome="PUBLISHED",
                published_document_count=6,
                retired_document_count=0,
                reused_document_count=0,
                quarantine_record_count=0,
            )

        actual_paths = OperatorIngestionPaths(
            paths.class_registry,
            paths.document_catalog,
            paths.ingestion_manifest,
            paths.source_root,
            report_root / "publish",
        )
        publication_connection = EmptyPlanningConnection()
        publication = run_operator_ingestion(
            paths=actual_paths,
            method_profile_id=METHOD_PROFILE_ID,
            connection=publication_connection,
            validate_only=False,
            producer=producer,
            writer=writer,
        )
        require(publication.exit_code == 0, "publication_exit_code_mismatch")
        require(
            publication.write_result is not None
            and publication.write_result.outcome == "PUBLISHED"
            and publication.write_result.published_document_count == 6,
            "publication_result_mismatch",
        )
        require(
            stage_calls == 1 and retention_calls == 1 and writer_calls == 1,
            "connection_call_count_mismatch",
        )
        require(stage_workspaces and not stage_workspaces[0].exists(), "producer_workspace_not_cleaned")
        require(prepared_counts == (27, 231, 126, 1), "prepared_inventory_absent")
        require(
            (os.stat(validation.json_report).st_mode & 0o777) == 0o600
            and (os.stat(publication.json_report).st_mode & 0o777) == 0o600,
            "protected_report_mode_mismatch",
        )
        require(str(arguments.source_root) not in publication.terminal_summary, "source_path_disclosed")

    artifact = {
        "schema_version": 1,
        "purpose": "live_producer_ingestion_connection_qualification",
        "method_profile_id": METHOD_PROFILE_ID,
        "embedding_space_id": EXPECTED_EMBEDDING_SPACE_ID,
        "validation_only": "pass",
        "validation_only_producer_calls": 0,
        "live_artifact_stage_calls": stage_calls,
        "artifact_retention_calls": retention_calls,
        "writer_handoff_calls": writer_calls,
        "prepared_documents": 6,
        "prepared_pages": 27,
        "prepared_structural_units": 231,
        "prepared_chunks": 126,
        "embedding_dimension": 768,
        "producer_workspace_cleanup": "pass",
        "protected_reports": "pass",
        "source_paths_disclosed": False,
        "target_contact": False,
        "database_contact": False,
        "model_call": False,
        "credential_read": False,
        "source_content_retained": False,
    }
    artifact_sha256, artifact_bytes = write_exclusive(arguments.output, artifact)
    print("purpose=connect_accepted_live_document_stage_to_operator_ingestion")
    print("validation_only=pass;producer_calls=0;writer_calls=0")
    print("publication=pass;producer_calls=1;artifact_retention_calls=1;writer_handoff_calls=1")
    print("prepared_documents=6;pages=27;structural_units=231;chunks=126;embedding_dimension=768")
    print(f"method_profile_id={METHOD_PROFILE_ID};embedding_space_id={EXPECTED_EMBEDDING_SPACE_ID}")
    print("workspace_cleanup=pass;protected_reports=pass;source_paths_disclosed=false")
    print("target_contact=false;database_contact=false;model_call=false;credential_read=false")
    print(f"qualification_artifact_sha256={artifact_sha256};qualification_artifact_bytes={artifact_bytes}")
    print("live_producer_ingestion_connection_qualification=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
