#!/usr/bin/env python3
"""Qualify the concrete live-stage process boundary using accepted artifacts."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import tempfile
from pathlib import Path

from ishikawa.canonical import canonical_json_bytes, file_sha256
from ishikawa.document_producer import METHOD_PROFILE_ID, NativeDocumentProducer
from ishikawa.ingestion_runtime import validate_ingestion_dependencies
from ishikawa.live_document_stage import NativeLiveDocumentArtifactStage
from ishikawa.operator_ingestion import (
    DocumentProductionRequest,
    OperatorIngestionPaths,
    ProductionBatch,
    load_operator_configuration,
)
from ishikawa.runtime import ProtectedEnvironmentValue
from ishikawa.yaml_loader import load_restricted_yaml


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
    parser.add_argument("--normalized", required=True, type=Path)
    parser.add_argument("--normalized-sha256", required=True)
    parser.add_argument("--chunks", required=True, type=Path)
    parser.add_argument("--chunks-sha256", required=True)
    parser.add_argument("--embeddings", required=True, type=Path)
    parser.add_argument("--embeddings-sha256", required=True)
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()

    for path, digest in (
        (arguments.normalized, arguments.normalized_sha256),
        (arguments.chunks, arguments.chunks_sha256),
        (arguments.embeddings, arguments.embeddings_sha256),
    ):
        require(path.is_file() and not path.is_symlink(), "accepted_artifact_unsafe")
        require(file_sha256(str(path)) == digest, "accepted_artifact_identity_mismatch")
    require(
        arguments.runtime_config_root.is_dir()
        and not arguments.runtime_config_root.is_symlink()
        and arguments.operator_config_root.is_dir()
        and not arguments.operator_config_root.is_symlink()
        and arguments.source_root.is_dir()
        and not arguments.source_root.is_symlink(),
        "input_root_unsafe",
    )
    require(
        arguments.output.is_absolute()
        and not arguments.output.exists()
        and not arguments.output.is_symlink()
        and arguments.output.parent.is_dir(),
        "output_path_unsafe",
    )

    dependencies = validate_ingestion_dependencies(
        load_restricted_yaml(
            arguments.runtime_config_root / "ingestion_dependencies.yaml",
            label="ingestion dependencies",
        )
    )
    paths = OperatorIngestionPaths(
        arguments.operator_config_root / "document_classes.yaml",
        arguments.operator_config_root / "document_catalog.yaml",
        arguments.operator_config_root / "ingestion_manifest.yaml",
        arguments.source_root,
        arguments.output.parent / "unused-reports",
    )
    _, _, manifest = load_operator_configuration(paths)
    configured = {item.document_key: item for item in manifest.documents}
    requests = []
    for document_key in sorted(configured):
        item = configured[document_key]
        source = arguments.source_root.joinpath(*item.source_path.split("/"))
        requests.append(
            DocumentProductionRequest(
                "add", document_key, item.class_id, item.source_path, file_sha256(str(source))
            )
        )
    batch = ProductionBatch(
        "1" * 64,
        METHOD_PROFILE_ID,
        arguments.source_root.resolve(),
        tuple(requests),
    )

    runner_calls = 0
    retention_calls = 0
    observed_command: tuple[str, ...] | None = None
    observed_request: dict[str, object] | None = None
    observed_credential = b""
    retained_while_present = False

    with tempfile.TemporaryDirectory(prefix="live-document-artifact-stage-") as temporary:
        root = Path(temporary)
        executable = root / "ishikawa-produce-artifacts"
        executable.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        executable.chmod(0o700)
        producer_work = root / "work"
        producer_work.mkdir(mode=0o700)

        def runner(command, credential, workspace, timeout):
            nonlocal runner_calls, observed_command, observed_request, observed_credential
            runner_calls += 1
            observed_command = command
            observed_credential = credential
            require(timeout == 3600, "stage_timeout_mismatch")
            request_path = Path(command[command.index("--request") + 1])
            observed_request = json.loads(request_path.read_text(encoding="utf-8"))
            outputs = (
                (arguments.normalized, workspace / "normalized.json", arguments.normalized_sha256),
                (arguments.chunks, workspace / "chunks.json", arguments.chunks_sha256),
                (arguments.embeddings, workspace / "embeddings.json", arguments.embeddings_sha256),
            )
            for source, destination, expected in outputs:
                shutil.copyfile(source, destination)
                require(file_sha256(str(destination)) == expected, "copied_artifact_mismatch")
            result = {
                "schema_version": 1,
                "outcome": "pass",
                "validation_id": observed_request["validation_id"],
                "method_profile_id": observed_request["method_profile_id"],
                "manifest_digest": observed_request["manifest_digest"],
                "served_model": dependencies.served_model,
                "normalized_sha256": arguments.normalized_sha256,
                "chunk_sha256": arguments.chunks_sha256,
                "embedding_sha256": arguments.embeddings_sha256,
                "credential_retained": False,
            }
            (workspace / "stage-result.json").write_bytes(canonical_json_bytes(result) + b"\n")
            return 0

        def retain(bundle):
            nonlocal retention_calls, retained_while_present
            retention_calls += 1
            retained_while_present = all(
                path.is_file()
                for path in (bundle.normalized_path, bundle.chunk_path, bundle.embedding_path)
            )

        stage = NativeLiveDocumentArtifactStage(
            executable.resolve(),
            dependencies,
            ProtectedEnvironmentValue(
                dependencies.nomic_credential_environment,
                {dependencies.nomic_credential_environment: "synthetic-stage-secret"},
            ),
            runner,
        )
        producer = NativeDocumentProducer(manifest, producer_work.resolve(), stage, retain)
        prepared = producer(batch)
        remaining_workspaces = tuple(producer_work.iterdir())

    require(runner_calls == 1, "runner_call_count_mismatch")
    require(retention_calls == 1 and retained_while_present, "retention_contract_mismatch")
    require(len(prepared) == 6, "prepared_document_count_mismatch")
    require(sum(item.page_count for item in prepared) == 27, "prepared_page_count_mismatch")
    require(sum(len(item.structural_units) for item in prepared) == 231, "prepared_unit_count_mismatch")
    require(sum(len(item.chunks) for item in prepared) == 126, "prepared_chunk_count_mismatch")
    require(not remaining_workspaces, "producer_workspace_not_cleaned")
    require(observed_command is not None and observed_request is not None, "stage_observation_absent")
    require(observed_credential == b"synthetic-stage-secret\n", "credential_transport_mismatch")
    require("synthetic-stage-secret" not in observed_command, "credential_in_arguments")
    require("synthetic-stage-secret" not in json.dumps(observed_request), "credential_in_request")
    require(len(observed_request["documents"]) == 6, "request_document_count_mismatch")
    require(
        {item["document_key"] for item in observed_request["documents"]} == set(configured),
        "request_document_coverage_mismatch",
    )

    artifact = {
        "schema_version": 1,
        "purpose": "live_document_artifact_stage_qualification",
        "method_profile_id": METHOD_PROFILE_ID,
        "served_model": dependencies.served_model,
        "process_calls": runner_calls,
        "credential_transport": "stdin",
        "credential_in_arguments": False,
        "credential_in_request": False,
        "requested_documents": 6,
        "prepared_documents": 6,
        "prepared_pages": 27,
        "prepared_structural_units": 231,
        "prepared_chunks": 126,
        "artifact_retention_calls": retention_calls,
        "producer_workspace_cleanup": "pass",
        "target_contact": False,
        "database_contact": False,
        "model_call": False,
        "source_content_retained": False,
        "vectors_retained": False,
    }
    artifact_sha256, artifact_bytes = write_exclusive(arguments.output, artifact)
    print("purpose=qualify_live_document_artifact_stage_process_boundary")
    print("stage_process_calls=1;requested_documents=6;whole_corpus_implicit=false")
    print("credential_transport=stdin;credential_in_arguments=false;credential_in_request=false")
    print("artifacts=normalized,chunks,embeddings;checksum_binding=pass;result_contract=pass")
    print("prepared_documents=6;pages=27;structural_units=231;chunks=126")
    print("artifact_retention_calls=1;producer_workspace_cleanup=pass")
    print("target_contact=false;database_contact=false;model_call=false;source_content_retained=false;vectors_retained=false")
    print(f"method_profile_id={METHOD_PROFILE_ID};served_model={dependencies.served_model}")
    print(f"qualification_artifact_sha256={artifact_sha256};qualification_artifact_bytes={artifact_bytes}")
    print("live_document_artifact_stage_qualification=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
