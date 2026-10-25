#!/usr/bin/env python3
"""Evaluate configured operator-ingestion assembly without external contact."""

from __future__ import annotations

import argparse
import io
import os
import tempfile
from pathlib import Path

from ishikawa.canonical import canonical_json_bytes, file_sha256
from ishikawa.document_producer import NativeDocumentProducer
from ishikawa.ingestion_runtime import assemble_configured_ingestion_runtime
from ishikawa.operator_ingestion import OperatorIngestionPaths


class Rows:
    def fetchall(self):
        return []


class PlanningConnection:
    def __init__(self) -> None:
        self.calls: list[str] = []
        self.closed = False

    def execute(self, sql, _parameters=()):
        if "ishikawa.load-published-state" in sql:
            self.calls.append("load-published-state")
            return Rows()
        if "ishikawa.load-catalog-keys" in sql:
            self.calls.append("load-catalog-keys")
            return Rows()
        raise RuntimeError("unexpected_planning_database_operation")

    def close(self) -> None:
        self.closed = True


class ObservedEnvironment(dict):
    def __init__(self) -> None:
        super().__init__(
            ISHIKAWA_NOMIC_API_KEY="synthetic-nomic-secret",
            ISHIKAWA_POSTGRESQL_INGEST_PASSWORD="synthetic-database-secret",
        )
        self.reads: list[str] = []

    def __getitem__(self, key: str) -> str:
        self.reads.append(key)
        return super().__getitem__(key)


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
    parser.add_argument("--runtime-config-root", required=True, type=Path)
    parser.add_argument("--operator-config-root", required=True, type=Path)
    parser.add_argument("--source-root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()

    require(
        arguments.runtime_config_root.is_dir()
        and not arguments.runtime_config_root.is_symlink()
        and arguments.operator_config_root.is_dir()
        and not arguments.operator_config_root.is_symlink()
        and arguments.source_root.is_dir()
        and not arguments.source_root.is_symlink(),
        "configuration_or_source_root_unsafe",
    )
    require(
        arguments.output.is_absolute()
        and not arguments.output.exists()
        and not arguments.output.is_symlink()
        and arguments.output.parent.is_dir(),
        "output_path_unsafe",
    )

    environment = ObservedEnvironment()
    connector_parameters: list[dict[str, object]] = []
    connections: list[PlanningConnection] = []
    stage_factory_calls = 0
    stage_calls = 0
    retention_calls = 0
    provider = None

    def connector(**parameters):
        connector_parameters.append(parameters)
        connection = PlanningConnection()
        connections.append(connection)
        return connection

    def stage_factory(policy, credential_provider):
        nonlocal stage_factory_calls, provider
        stage_factory_calls += 1
        provider = credential_provider
        require(policy.served_model == "nomic-ai/nomic-embed-text-v1.5", "model_mismatch")
        require(policy.embedding_endpoint.parsed.path == "/v1/embeddings", "embedding_path_mismatch")
        require(policy.tokenization_endpoint.parsed.path == "/tokenize", "tokenizer_path_mismatch")

        def forbidden_stage(_batch, _manifest, _workspace):
            nonlocal stage_calls
            stage_calls += 1
            raise RuntimeError("validation_only_invoked_artifact_stage")

        return forbidden_stage

    def retainer(_bundle):
        nonlocal retention_calls
        retention_calls += 1
        raise RuntimeError("validation_only_invoked_artifact_retainer")

    with tempfile.TemporaryDirectory(prefix="configured-ingestion-runtime-") as temporary:
        root = Path(temporary)
        work = root / "work"
        work.mkdir(mode=0o700)
        paths = OperatorIngestionPaths(
            arguments.operator_config_root / "document_classes.yaml",
            arguments.operator_config_root / "document_catalog.yaml",
            arguments.operator_config_root / "ingestion_manifest.yaml",
            arguments.source_root,
            root / "reports",
        )
        runtime = assemble_configured_ingestion_runtime(
            paths,
            runtime_config_root=arguments.runtime_config_root,
            work_root=work,
            artifact_stage_factory=stage_factory,
            artifact_retainer=retainer,
            environment=environment,
            database_connector=connector,
        )
        require(isinstance(runtime.ports.producer, NativeDocumentProducer), "producer_not_concrete")
        require(stage_factory_calls == 1, "stage_factory_count_mismatch")
        require(environment.reads == [], "assembly_read_credential")
        require(connector_parameters == [], "assembly_opened_database")
        require(stage_calls == 0 and retention_calls == 0, "assembly_processed_document")

        output = io.StringIO()
        status = runtime.execute("validate-only", output=output)
        require(status == 0, "validate_only_status_mismatch")
        require(environment.reads == ["ISHIKAWA_POSTGRESQL_INGEST_PASSWORD"], "credential_read_mismatch")
        require(len(connections) == 1 and connections[0].closed, "connection_lifecycle_mismatch")
        require(
            connections[0].calls == ["load-published-state", "load-catalog-keys"],
            "planning_read_contract_mismatch",
        )
        require(len(connector_parameters) == 1, "connector_count_mismatch")
        parameters = connector_parameters[0]
        require(parameters.get("user") == "rag_ingest", "database_role_mismatch")
        require(parameters.get("dbname") == "rag_catalog", "database_name_mismatch")
        require(parameters.get("application_name") == "ishikawa-ingestion", "application_name_mismatch")
        require("options" not in parameters, "unexpected_read_only_option")
        require(stage_calls == 0 and retention_calls == 0, "validation_only_processed_document")
        require(provider is not None, "nomic_provider_absent")
        require("ISHIKAWA_NOMIC_API_KEY" not in environment.reads, "validation_read_nomic_credential")
        terminal = output.getvalue()
        require("synthetic-database-secret" not in terminal, "database_secret_disclosed")
        require("synthetic-nomic-secret" not in terminal, "nomic_secret_disclosed")
        require(str(arguments.source_root) not in terminal, "source_path_disclosed")
        require(
            all((os.stat(path).st_mode & 0o777) == 0o600 for path in (root / "reports").iterdir()),
            "report_mode_mismatch",
        )

    policy = runtime.policy
    artifact = {
        "schema_version": 1,
        "purpose": "configured_operator_ingestion_runtime_qualification",
        "runtime_identity": policy.digest,
        "method_profile_id": policy.method_profile_id,
        "database_name": policy.dependencies.database_name,
        "database_user": policy.dependencies.database_user,
        "database_application_name": "ishikawa-ingestion",
        "database_read_only": False,
        "embedding_path": policy.dependencies.embedding_endpoint.parsed.path,
        "tokenization_path": policy.dependencies.tokenization_endpoint.parsed.path,
        "embedding_batch_size": policy.dependencies.embedding_batch_size,
        "assembly_credential_reads": 0,
        "assembly_dependency_calls": 0,
        "validation_database_connections": 1,
        "validation_database_credential_reads": 1,
        "validation_nomic_credential_reads": 0,
        "validation_artifact_stage_calls": stage_calls,
        "validation_artifact_retention_calls": retention_calls,
        "target_contact": False,
        "database_contact": False,
        "model_call": False,
        "source_content_retained": False,
    }
    artifact_sha256, artifact_bytes = write_exclusive(arguments.output, artifact)
    print(
        "runtime_components=fixed_operator_paths,native_psycopg_ingest,protected_nomic_provider,"
        "native_document_producer,incremental_writer"
    )
    print(
        "postgresql=rag_catalog;role=rag_ingest;application_name=ishikawa-ingestion;"
        "read_only=false"
    )
    print("nomic=embedding_/v1/embeddings,tokenization_/tokenize;batch_size=16")
    print("assembly=pass;dependency_calls=0;credential_reads=0;documents_processed=0")
    print(
        "validation_only=pass;database_connections=1;database_credential_reads=1;"
        "nomic_credential_reads=0;artifact_stage_calls=0;artifact_retention_calls=0"
    )
    print("operator_paths=fixed;source_paths_exposed=false;credentials_in_yaml=false")
    print("target_contact=false;database_contact=false;model_call=false;source_content_retained=false")
    print(f"runtime_identity={policy.digest};method_profile_id={policy.method_profile_id}")
    print(f"qualification_artifact_sha256={artifact_sha256};qualification_artifact_bytes={artifact_bytes}")
    print("configured_operator_ingestion_runtime_qualification=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
