#!/usr/bin/env python3
"""Qualify the portable operator-ingestion command boundary without services."""

from __future__ import annotations

import argparse
import io
import os
import tempfile
from pathlib import Path

from ishikawa.canonical import canonical_json_bytes, file_sha256
from ishikawa.ingestion_command import IngestionCommandPorts, execute_ingestion_command
from ishikawa.persistence_models import WriteResult


class Rows:
    """Minimal read-only result for an empty published corpus."""

    def fetchall(self):
        return []


class PlanningConnection:
    """Observe only the two planning reads and explicit close."""

    def __init__(self) -> None:
        self.tags: list[str] = []
        self.closed = False

    def execute(self, sql, _parameters=()):
        if "ishikawa.load-published-state" in sql:
            self.tags.append("load-published-state")
            return Rows()
        if "ishikawa.load-catalog-keys" in sql:
            self.tags.append("load-catalog-keys")
            return Rows()
        raise RuntimeError("unexpected_planning_database_operation")

    def close(self) -> None:
        self.closed = True


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise RuntimeError(reason)


def write_exclusive(path: Path, document: dict[str, object]) -> tuple[str, int]:
    payload = canonical_json_bytes(document) + b"\n"
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)
    return file_sha256(str(path)), len(payload)


def command_arguments(
    mode: str,
    *,
    config_root: Path,
    source_root: Path,
    report_root: Path,
) -> list[str]:
    return [
        mode,
        "--class-registry",
        str((config_root / "document_classes.yaml").resolve()),
        "--document-catalog",
        str((config_root / "document_catalog.yaml").resolve()),
        "--ingestion-manifest",
        str((config_root / "ingestion_manifest.yaml").resolve()),
        "--source-root",
        str(source_root.resolve()),
        "--report-root",
        str(report_root.resolve()),
    ]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config-root", required=True, type=Path)
    parser.add_argument("--source-root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()

    for name in ("document_classes.yaml", "document_catalog.yaml", "ingestion_manifest.yaml"):
        path = arguments.config_root / name
        require(path.is_file() and not path.is_symlink(), "operator_configuration_unsafe")
    require(
        arguments.source_root.is_dir() and not arguments.source_root.is_symlink(),
        "operator_source_root_unsafe",
    )
    require(
        arguments.output.is_absolute()
        and not arguments.output.exists()
        and not arguments.output.is_symlink()
        and arguments.output.parent.is_dir(),
        "output_path_unsafe",
    )

    connections: list[PlanningConnection] = []
    producer_calls = 0
    writer_calls = 0

    def connection_factory() -> PlanningConnection:
        connection = PlanningConnection()
        connections.append(connection)
        return connection

    def producer(batch):
        nonlocal producer_calls
        producer_calls += 1
        require(len(batch.documents) == 6, "production_batch_count_mismatch")
        return tuple(object() for _ in batch.documents)

    def writer(_connection, _registry, _catalog, _manifest, plan, prepared):
        nonlocal writer_calls
        writer_calls += 1
        require(plan.overall_outcome == "PASS", "writer_plan_outcome_mismatch")
        require(len(prepared) == 6, "writer_prepared_count_mismatch")
        return WriteResult("1" * 64, "2" * 64, "PUBLISHED", 6, 0, 0, 0)

    outputs: list[str] = []
    with tempfile.TemporaryDirectory(prefix="portable-ingestion-entrypoint-") as temporary:
        root = Path(temporary)

        validation_output = io.StringIO()
        validation_status = execute_ingestion_command(
            command_arguments(
                "--validate-only",
                config_root=arguments.config_root,
                source_root=arguments.source_root,
                report_root=root / "validate",
            ),
            ports=IngestionCommandPorts(connection_factory, producer, writer),
            output=validation_output,
        )
        outputs.append(validation_output.getvalue())
        require(validation_status == 0, "validate_only_status_mismatch")
        require(producer_calls == 0 and writer_calls == 0, "validate_only_mutating_port_called")
        require(
            len(connections) == 1
            and connections[0].closed
            and connections[0].tags == ["load-published-state", "load-catalog-keys"],
            "validate_only_connection_contract_mismatch",
        )

        publication_output = io.StringIO()
        publication_status = execute_ingestion_command(
            command_arguments(
                "--publish",
                config_root=arguments.config_root,
                source_root=arguments.source_root,
                report_root=root / "publish",
            ),
            ports=IngestionCommandPorts(connection_factory, producer, writer),
            output=publication_output,
        )
        outputs.append(publication_output.getvalue())
        require(publication_status == 0, "publication_status_mismatch")
        require(producer_calls == 1 and writer_calls == 1, "publication_port_count_mismatch")
        require(
            len(connections) == 2
            and connections[1].closed
            and connections[1].tags == ["load-published-state", "load-catalog-keys"],
            "publication_connection_contract_mismatch",
        )

        missing_producer_output = io.StringIO()
        missing_producer_status = execute_ingestion_command(
            command_arguments(
                "--publish",
                config_root=arguments.config_root,
                source_root=arguments.source_root,
                report_root=root / "missing-producer",
            ),
            ports=IngestionCommandPorts(connection_factory, None, writer),
            output=missing_producer_output,
        )
        outputs.append(missing_producer_output.getvalue())
        require(missing_producer_status == 2, "missing_producer_status_mismatch")
        require(len(connections) == 2, "missing_producer_opened_connection")

        unknown_option_output = io.StringIO()
        unknown_option_status = execute_ingestion_command(
            command_arguments(
                "--validate-only",
                config_root=arguments.config_root,
                source_root=arguments.source_root,
                report_root=root / "unknown-option",
            )
            + ["--database-password", "private-value"],
            ports=IngestionCommandPorts(connection_factory, producer, writer),
            output=unknown_option_output,
        )
        outputs.append(unknown_option_output.getvalue())
        require(unknown_option_status == 2, "unknown_option_status_mismatch")
        require(len(connections) == 2, "unknown_option_opened_connection")

        def failing_writer(*_items):
            raise RuntimeError("private writer detail")

        failure_output = io.StringIO()
        failure_status = execute_ingestion_command(
            command_arguments(
                "--publish",
                config_root=arguments.config_root,
                source_root=arguments.source_root,
                report_root=root / "failure",
            ),
            ports=IngestionCommandPorts(connection_factory, producer, failing_writer),
            output=failure_output,
        )
        outputs.append(failure_output.getvalue())
        require(failure_status == 1, "runtime_failure_status_mismatch")
        require(len(connections) == 3 and connections[2].closed, "runtime_failure_not_closed")
        require(producer_calls == 2 and writer_calls == 1, "failure_port_count_mismatch")

        combined_output = "".join(outputs)
        require("private-value" not in combined_output, "secret_argument_disclosed")
        require("private writer detail" not in combined_output, "unexpected_detail_disclosed")
        require(str(arguments.source_root) not in combined_output, "source_path_disclosed")
        require(
            all((os.stat(path).st_mode & 0o777) == 0o600 for path in root.glob("*/*")),
            "protected_report_mode_mismatch",
        )

    artifact = {
        "schema_version": 1,
        "purpose": "portable_operator_ingestion_entrypoint_qualification",
        "scenarios": 5,
        "validate_only": "pass",
        "publish": "pass",
        "missing_producer": "pass",
        "unknown_option": "pass",
        "runtime_failure": "pass",
        "validate_only_producer_calls": 0,
        "validate_only_writer_calls": 0,
        "publish_producer_calls": 1,
        "publish_writer_calls": 1,
        "connections_opened": len(connections),
        "connections_closed": sum(connection.closed for connection in connections),
        "secrets_in_arguments": False,
        "unexpected_details_exposed": False,
        "source_paths_exposed": False,
        "target_contact": False,
        "database_contact": False,
        "model_call": False,
        "credential_read": False,
        "source_content_retained": False,
    }
    artifact_sha256, artifact_bytes = write_exclusive(arguments.output, artifact)
    print("purpose=qualify_portable_operator_ingestion_entrypoint")
    print(
        "entrypoint_scenarios=5;validate_only=pass;publish=pass;"
        "missing_producer=pass;unknown_option=pass;runtime_failure=pass"
    )
    print("validate_only_dependencies=producer_0,writer_0;publish_dependencies=producer_1,writer_1")
    print("connection_lifecycle=opened_3,closed_3;predependency_rejections=2")
    print("secrets_in_arguments=false;unexpected_details_exposed=false;source_paths_exposed=false")
    print("target_contact=false;database_contact=false;model_call=false;credential_read=false")
    print(f"qualification_artifact_sha256={artifact_sha256};qualification_artifact_bytes={artifact_bytes}")
    print("portable_operator_ingestion_entrypoint_qualification=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
