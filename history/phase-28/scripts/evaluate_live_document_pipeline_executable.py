#!/usr/bin/env python3
"""Qualify the installed pipeline orchestration with accepted stage artifacts."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import tempfile
from pathlib import Path

from ishikawa.artifact_pipeline import NOMIC_MODEL, PipelineLayout, run_artifact_pipeline
from ishikawa.canonical import canonical_json_bytes, file_sha256
from ishikawa.document_producer import METHOD_PROFILE_ID
from ishikawa.operator_ingestion import OperatorIngestionPaths, load_operator_configuration


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise RuntimeError(reason)


def argument(command: tuple[str, ...], name: str) -> Path:
    return Path(command[command.index(name) + 1])


def write_exclusive(path: Path, document: dict[str, object]) -> tuple[str, int]:
    payload = canonical_json_bytes(document) + b"\n"
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)
    return file_sha256(str(path)), len(payload)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--python-root", required=True, type=Path)
    parser.add_argument("--pipeline-executable", required=True, type=Path)
    parser.add_argument("--capture", required=True, type=Path)
    parser.add_argument("--normalize", required=True, type=Path)
    parser.add_argument("--chunk", required=True, type=Path)
    parser.add_argument("--embed", required=True, type=Path)
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

    for path in (
        arguments.python_root,
        arguments.config_root,
        arguments.source_root,
    ):
        require(path.is_absolute() and path.is_dir() and not path.is_symlink(), "input_root_unsafe")
    for path in (
        arguments.pipeline_executable,
        arguments.capture,
        arguments.normalize,
        arguments.chunk,
        arguments.embed,
        arguments.normalized,
        arguments.chunks,
        arguments.embeddings,
    ):
        require(path.is_absolute() and path.is_file() and not path.is_symlink(), "input_file_unsafe")
    require(os.access(arguments.pipeline_executable, os.X_OK), "pipeline_executable_not_executable")
    for path, digest in (
        (arguments.normalized, arguments.normalized_sha256),
        (arguments.chunks, arguments.chunks_sha256),
        (arguments.embeddings, arguments.embeddings_sha256),
    ):
        require(file_sha256(str(path)) == digest, "accepted_artifact_identity_mismatch")
    require(
        arguments.output.is_absolute()
        and not arguments.output.exists()
        and not arguments.output.is_symlink()
        and arguments.output.parent.is_dir(),
        "output_path_unsafe",
    )

    paths = OperatorIngestionPaths(
        arguments.config_root / "document_classes.yaml",
        arguments.config_root / "document_catalog.yaml",
        arguments.config_root / "ingestion_manifest.yaml",
        arguments.source_root,
        arguments.output.parent / "unused-reports",
    )
    _, _, manifest = load_operator_configuration(paths)
    documents = []
    for item in sorted(manifest.documents, key=lambda value: value.document_key):
        source = arguments.source_root.joinpath(*item.source_path.split("/"))
        documents.append(
            {
                "action": "add",
                "document_key": item.document_key,
                "class_id": item.class_id,
                "relative_source_path": item.source_path,
                "source_sha256": file_sha256(str(source)),
            }
        )
    request = {
        "schema_version": 1,
        "validation_id": "1" * 64,
        "method_profile_id": METHOD_PROFILE_ID,
        "manifest_digest": manifest.digest,
        "documents": documents,
    }

    stage_calls: list[str] = []
    credential_observations: list[bool] = []
    staged_document_count = 0
    staged_source_hashes: set[str] = set()
    work_roots: tuple[Path, ...] = ()
    with tempfile.TemporaryDirectory(prefix="live-document-pipeline-executable-") as temporary:
        root = Path(temporary)
        workspace = root / "workspace"
        workspace.mkdir(mode=0o700)
        request_path = workspace / "stage-request.json"
        request_path.write_bytes(canonical_json_bytes(request) + b"\n")
        layout = PipelineLayout(
            arguments.python_root,
            arguments.capture,
            arguments.normalize,
            arguments.chunk,
            arguments.embed,
        )

        def runner(command, credential, _cwd, stdout_path, stderr_path):
            nonlocal staged_document_count, staged_source_hashes
            stdout_path.write_bytes(b"")
            stderr_path.write_bytes(b"")
            stage = Path(command[2]).name
            stage_calls.append(stage)
            credential_observations.append(credential is not None)
            if stage == arguments.capture.name:
                source_manifest = json.loads(
                    argument(command, "--source-manifest").read_text(encoding="utf-8")
                )
                staged_document_count = len(source_manifest["files"])
                staged_source_hashes = {item["sha256"] for item in source_manifest["files"]}
                require(
                    source_manifest["fixture_status"] == "operator_manifest_bound_source",
                    "source_manifest_status_mismatch",
                )
                for item in source_manifest["files"]:
                    staged = argument(command, "--input-dir") / item["filename"]
                    require(file_sha256(str(staged)) == item["sha256"], "staged_source_mismatch")
                argument(command, "--archive").write_bytes(b"qualified extraction boundary")
            elif stage == arguments.normalize.name:
                require(
                    command[command.index("--expected-archive-sha256") + 1]
                    == file_sha256(str(argument(command, "--archive"))),
                    "extraction_link_mismatch",
                )
                shutil.copyfile(arguments.normalized, argument(command, "--output"))
            elif stage == arguments.chunk.name:
                require(
                    command[command.index("--expected-input-sha256") + 1]
                    == arguments.normalized_sha256,
                    "normalization_link_mismatch",
                )
                shutil.copyfile(arguments.chunks, argument(command, "--output"))
            elif stage == arguments.embed.name:
                require(credential == b"synthetic-pipeline-secret-value", "credential_transport_mismatch")
                require(
                    command[command.index("--expected-input-sha256") + 1]
                    == arguments.chunks_sha256,
                    "chunk_link_mismatch",
                )
                shutil.copyfile(arguments.embeddings, argument(command, "--output"))
            else:
                return 9
            return 0

        result = run_artifact_pipeline(
            request_path=request_path.resolve(),
            source_root=arguments.source_root,
            workspace=workspace.resolve(),
            embedding_url="http://127.0.0.1:8001/v1/embeddings",
            tokenization_url="http://127.0.0.1:8001/tokenize",
            served_model=NOMIC_MODEL,
            batch_size=16,
            credential=bytearray(b"synthetic-pipeline-secret-value"),
            layout=layout,
            runner=runner,
        )
        work_roots = tuple(workspace.glob(".artifact-pipeline-*"))
        observed_result = json.loads((workspace / "stage-result.json").read_text(encoding="utf-8"))
        require(observed_result == result, "stage_result_mismatch")
        require(file_sha256(str(workspace / "normalized.json")) == arguments.normalized_sha256, "normalized_mismatch")
        require(file_sha256(str(workspace / "chunks.json")) == arguments.chunks_sha256, "chunks_mismatch")
        require(file_sha256(str(workspace / "embeddings.json")) == arguments.embeddings_sha256, "embeddings_mismatch")

    expected_source_hashes = {item["source_sha256"] for item in documents}
    require(stage_calls == [arguments.capture.name, arguments.normalize.name, arguments.chunk.name, arguments.embed.name], "stage_order_mismatch")
    require(credential_observations == [False, False, False, True], "credential_scope_mismatch")
    require(staged_document_count == 6 and staged_source_hashes == expected_source_hashes, "document_scope_mismatch")
    require(not work_roots, "pipeline_workspace_not_cleaned")

    artifact = {
        "schema_version": 1,
        "purpose": "live_document_pipeline_executable_qualification",
        "pipeline_command": "ishikawa-produce-artifacts",
        "request_documents": 6,
        "stage_order": ["extraction", "normalization", "chunking", "embedding"],
        "credential_stage_count": 1,
        "credential_retained": False,
        "temporary_source_workspace_retained": False,
        "normalized_sha256": arguments.normalized_sha256,
        "chunk_sha256": arguments.chunks_sha256,
        "embedding_sha256": arguments.embeddings_sha256,
        "target_contact": False,
        "database_contact": False,
        "model_call": False,
        "source_content_retained": False,
        "vectors_retained": False,
    }
    artifact_sha256, artifact_bytes = write_exclusive(arguments.output, artifact)
    print("purpose=qualify_live_document_pipeline_executable")
    print("pipeline_command=ishikawa-produce-artifacts;request_contract=pass;result_contract=pass")
    print("stage_order=extraction,normalization,chunking,embedding;stage_calls=4")
    print("requested_documents=6;staged_documents=6;whole_corpus_implicit=false")
    print("credential_stage_count=1;credential_in_arguments=false;credential_retained=false")
    print("temporary_source_workspace_cleanup=pass;artifact_checksum_binding=pass")
    print("target_contact=false;database_contact=false;model_call=false;source_content_retained=false;vectors_retained=false")
    print(f"qualification_artifact_sha256={artifact_sha256};qualification_artifact_bytes={artifact_bytes}")
    print("live_document_pipeline_executable_qualification=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
