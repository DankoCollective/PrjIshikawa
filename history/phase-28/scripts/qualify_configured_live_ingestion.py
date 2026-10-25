#!/usr/bin/env python3
"""Exercise configured ingestion with a live document stage and disposable database."""

from __future__ import annotations

import hashlib
import io
import json
import os
import re
import shutil
import sys
from pathlib import Path

PACKAGE_ROOT = Path(__file__).resolve(strict=True).parent / "Ishikawa" / "application" / "python"
if PACKAGE_ROOT.is_dir():
    sys.path.insert(0, str(PACKAGE_ROOT))

import psycopg

from ishikawa.document_producer import METHOD_PROFILE_ID, ProducerArtifactBundle
from ishikawa.ingestion_runtime import assemble_configured_ingestion_runtime
from ishikawa.live_document_stage import (
    LiveDocumentStageError,
    NativeLiveDocumentArtifactStageFactory,
)
from ishikawa.operator_ingestion import OperatorIngestionPaths


EXPECTED_DOCUMENTS = 6
EXPECTED_PAGES = 27
EXPECTED_STRUCTURAL_UNITS = 231
EXPECTED_CHUNKS = 126
EXPECTED_DIMENSION = 768
ADD_ACTION_SUMMARY = "actions=add:6,reprocess:0,retire:0,reuse:0,revise:0"
REUSE_ACTION_SUMMARY = "actions=add:0,reprocess:0,retire:0,reuse:6,revise:0"
SAFE_REASON = re.compile(r"[a-z][a-z0-9_]{0,127}")
CURRENT_STAGE = "setup"


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise RuntimeError(reason)


def set_stage(stage: str) -> None:
    global CURRENT_STAGE
    CURRENT_STAGE = stage


def emit_blocked(
    stage: str,
    reason: str,
    *,
    stage_calls: int = 0,
    retention_calls: int = 0,
    retained_objects: int = 0,
) -> int:
    safe_stage = stage if stage in {
        "setup", "validation", "publication", "reuse", "inventory", "artifact"
    } else "setup"
    safe_reason = reason if SAFE_REASON.fullmatch(reason) else "unhandled_runtime_failure"
    print(
        "configured_live_ingestion_runner=blocked;"
        f"stage={safe_stage};reason={safe_reason};stage_calls={stage_calls};"
        f"retention_calls={retention_calls};retained_objects={retained_objects}"
    )
    return 1


def require_output_contract(
    output: io.StringIO,
    *,
    action_summary: str,
    mutation_performed: bool,
    reason: str,
) -> None:
    lines = output.getvalue().splitlines()
    expected = (
        "outcome=PASS",
        action_summary,
        f"mutation_performed={str(mutation_performed).lower()}",
        "ishikawa_ingestion=pass;exit_code=0",
    )
    require(all(lines.count(line) == 1 for line in expected), reason)


def scalar(connection, query: str):
    row = connection.execute(query).fetchone()
    require(row is not None, "required_database_result_absent")
    return row[0]


def read_credential() -> str:
    raw = sys.stdin.buffer.readline(2049)
    extra = sys.stdin.buffer.read(1)
    require(not extra, "credential_input_too_large")
    if raw.endswith(b"\n"):
        raw = raw[:-1]
    require(32 <= len(raw) <= 1024 and b"\x00" not in raw, "credential_input_invalid")
    try:
        value = raw.decode("utf-8")
    except UnicodeDecodeError as error:
        raise RuntimeError("credential_input_invalid") from error
    return value


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def private_json_write(path: Path, value: dict[str, object]) -> None:
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
        json.dump(value, stream, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        stream.write("\n")


def run_qualification() -> int:
    if len(sys.argv) != 10 or not sys.argv[1].startswith("ishikawa_live_ingestion_test"):
        raise RuntimeError("disposable_database_and_runtime_paths_required")
    database = sys.argv[1]
    runtime_config = Path(sys.argv[2]).resolve(strict=True)
    operator_config = Path(sys.argv[3]).resolve(strict=True)
    source_root = Path(sys.argv[4]).resolve(strict=True)
    report_root = Path(sys.argv[5]).resolve(strict=True)
    work_root = Path(sys.argv[6]).resolve(strict=True)
    retained_root = Path(sys.argv[7]).resolve(strict=True)
    executable = Path(sys.argv[8]).resolve(strict=True)
    output_path = Path(sys.argv[9])
    for path in (runtime_config, operator_config, source_root, report_root, work_root, retained_root):
        require(path.is_dir() and not path.is_symlink(), "runtime_path_unsafe")
    require(executable.is_file() and not executable.is_symlink() and os.access(executable, os.X_OK),
            "pipeline_executable_unsafe")
    require(not output_path.exists() and output_path.parent == report_root.parent,
            "qualification_output_unsafe")

    nomic_credential = read_credential()
    environment = {
        "ISHIKAWA_NOMIC_API_KEY": nomic_credential,
        "ISHIKAWA_POSTGRESQL_INGEST_PASSWORD": "disposable-connector-value",
    }
    connection_calls = 0
    stage_calls = 0
    stage_failure_reason = ""
    retention_calls = 0
    retained_objects: set[str] = set()

    def connector(**values):
        nonlocal connection_calls
        connection_calls += 1
        require(values == {
            "host": "127.0.0.1",
            "port": 5432,
            "dbname": "rag_catalog",
            "user": "rag_ingest",
            "password": "disposable-connector-value",
            "connect_timeout": 10,
            "application_name": "ishikawa-ingestion",
        }, "configured_database_parameters_mismatch")
        connection = psycopg.connect(
            host="/var/run/postgresql",
            port=5432,
            dbname=database,
            user="postgres",
            autocommit=True,
            application_name="ishikawa-live-ingestion-qualification",
        )
        connection.execute("SET ROLE rag_ingest")
        require(scalar(connection, "SELECT current_user") == "rag_ingest",
                "ingestion_role_not_applied")
        return connection

    native_factory = NativeLiveDocumentArtifactStageFactory(executable)

    def stage_factory(dependencies, credential_provider):
        native_stage = native_factory(dependencies, credential_provider)

        def counted_stage(batch, manifest, workspace):
            nonlocal stage_calls, stage_failure_reason
            stage_calls += 1
            try:
                return native_stage(batch, manifest, workspace)
            except LiveDocumentStageError as error:
                stage_failure_reason = str(error)
                raise

        return counted_stage

    def retain(bundle: ProducerArtifactBundle) -> None:
        nonlocal retention_calls
        require(isinstance(bundle, ProducerArtifactBundle), "retention_bundle_invalid")
        retention_calls += 1
        for source, digest in (
            (bundle.normalized_path, bundle.normalized_sha256),
            (bundle.chunk_path, bundle.chunk_sha256),
            (bundle.embedding_path, bundle.embedding_sha256),
        ):
            require(file_sha256(source) == digest, "retention_source_identity_mismatch")
            directory = retained_root / digest[:2]
            directory.mkdir(mode=0o700, exist_ok=True)
            os.chmod(directory, 0o700)
            destination = directory / digest
            require(not destination.exists(), "retained_artifact_already_exists")
            descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(descriptor, "wb") as output, source.open("rb") as input_stream:
                shutil.copyfileobj(input_stream, output)
            require(file_sha256(destination) == digest, "retained_artifact_identity_mismatch")
            retained_objects.add(digest)

    set_stage("setup")
    paths = OperatorIngestionPaths(
        operator_config / "document_classes.yaml",
        operator_config / "document_catalog.yaml",
        operator_config / "ingestion_manifest.yaml",
        source_root,
        report_root,
    )
    runtime = assemble_configured_ingestion_runtime(
        paths,
        runtime_config_root=runtime_config,
        work_root=work_root,
        artifact_stage_factory=stage_factory,
        artifact_retainer=retain,
        environment=environment,
        database_connector=connector,
    )
    require(runtime.policy.method_profile_id == METHOD_PROFILE_ID, "method_profile_mismatch")

    set_stage("validation")
    validation_output = io.StringIO()
    require(runtime.execute("validate-only", output=validation_output) == 0,
            "validation_only_failed")
    require_output_contract(
        validation_output,
        action_summary=ADD_ACTION_SUMMARY,
        mutation_performed=False,
        reason="validation_output_mismatch",
    )
    require(stage_calls == 0 and retention_calls == 0, "validation_invoked_pipeline")

    set_stage("publication")
    publication_output = io.StringIO()
    publication_status = runtime.execute("publish", output=publication_output)
    if publication_status != 0:
        if stage_failure_reason:
            failure_reason = stage_failure_reason
        elif stage_calls == 0:
            failure_reason = "publication_not_entered"
        elif retention_calls == 0:
            failure_reason = "artifact_adapter_failed"
        elif len(retained_objects) != 3:
            failure_reason = "artifact_retention_failed"
        else:
            failure_reason = "database_writer_failed"
        return emit_blocked(
            "publication",
            failure_reason,
            stage_calls=stage_calls,
            retention_calls=retention_calls,
            retained_objects=len(retained_objects),
        )
    require_output_contract(
        publication_output,
        action_summary=ADD_ACTION_SUMMARY,
        mutation_performed=True,
        reason="publication_output_mismatch",
    )
    require(stage_calls == 1 and retention_calls == 1 and len(retained_objects) == 3,
            "live_pipeline_invocation_mismatch")

    set_stage("reuse")
    reuse_output = io.StringIO()
    require(runtime.execute("publish", output=reuse_output) == 0, "reuse_failed")
    require_output_contract(
        reuse_output,
        action_summary=REUSE_ACTION_SUMMARY,
        mutation_performed=False,
        reason="reuse_output_mismatch",
    )
    require(stage_calls == 1 and retention_calls == 1, "reuse_invoked_pipeline")
    require(connection_calls == 3, "database_connection_count_mismatch")

    set_stage("inventory")
    with psycopg.connect(
        host="/var/run/postgresql", port=5432, dbname=database, user="postgres"
    ) as connection:
        counts = {
            "documents": scalar(connection, "SELECT count(*) FROM rag.documents"),
            "active_documents": scalar(connection, "SELECT count(*) FROM rag_search.active_documents"),
            "pages": scalar(connection, "SELECT sum(page_count) FROM rag.document_versions"),
            "structural_units": scalar(connection, "SELECT count(*) FROM rag.structural_units"),
            "chunks": scalar(connection, "SELECT count(*) FROM rag.chunks"),
            "citations": scalar(connection, "SELECT count(*) FROM rag.citation_anchors"),
            "embeddings": scalar(connection, "SELECT count(*) FROM rag.chunk_embeddings"),
            "active_chunks": scalar(connection, "SELECT count(*) FROM rag_search.active_chunks"),
            "active_embeddings": scalar(connection, "SELECT count(*) FROM rag_search.active_embeddings"),
            "embedding_dimension": scalar(
                connection,
                "SELECT vector_dims(embedding) FROM rag_search.active_embeddings LIMIT 1",
            ),
        }
    expected = {
        "documents": EXPECTED_DOCUMENTS,
        "active_documents": EXPECTED_DOCUMENTS,
        "pages": EXPECTED_PAGES,
        "structural_units": EXPECTED_STRUCTURAL_UNITS,
        "chunks": EXPECTED_CHUNKS,
        "citations": EXPECTED_CHUNKS,
        "embeddings": EXPECTED_CHUNKS,
        "active_chunks": EXPECTED_CHUNKS,
        "active_embeddings": EXPECTED_CHUNKS,
        "embedding_dimension": EXPECTED_DIMENSION,
    }
    require(counts == expected, "persisted_inventory_mismatch")

    artifact = {
        "schema_version": 1,
        "outcome": "pass",
        "method_profile_id": runtime.policy.method_profile_id,
        "documents": counts["documents"],
        "pages": counts["pages"],
        "structural_units": counts["structural_units"],
        "chunks": counts["chunks"],
        "citations": counts["citations"],
        "embeddings": counts["embeddings"],
        "embedding_dimension": counts["embedding_dimension"],
        "validation_planned_adds": EXPECTED_DOCUMENTS,
        "published_documents": EXPECTED_DOCUMENTS,
        "reused_documents": EXPECTED_DOCUMENTS,
        "database_connections": connection_calls,
        "live_stage_calls": stage_calls,
        "artifact_retention_calls": retention_calls,
        "retained_artifact_objects": len(retained_objects),
        "accepted_database_changed": False,
        "credential_retained": False,
    }
    set_stage("artifact")
    private_json_write(output_path, artifact)
    nomic_credential = ""
    environment.clear()
    print("validation_only=pass;planned_adds=6;stage_calls=0;database_mutations=0")
    print("publication=pass;published_documents=6;live_stage_calls=1;artifact_retention_calls=1")
    print("reuse=pass;reused_documents=6;live_stage_calls_after_reuse=1")
    print("persisted_documents=6;pages=27;structural_units=231;chunks=126;citations=126;embeddings=126")
    print("embedding_dimension=768;database_connections=3;retained_artifact_objects=3")
    print("credential_retained=false;source_paths_reported=false;raw_content_reported=false")
    print("configured_live_ingestion_qualification=pass")
    return 0


def main() -> int:
    try:
        return run_qualification()
    except Exception as error:
        message = str(error)
        if not SAFE_REASON.fullmatch(message):
            error_name = re.sub(r"[^a-z0-9]+", "", type(error).__name__.lower())
            message = f"{error_name}_failure" if error_name else "unhandled_runtime_failure"
        return emit_blocked(CURRENT_STAGE, message)


if __name__ == "__main__":
    raise SystemExit(main())
