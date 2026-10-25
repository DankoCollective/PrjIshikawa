#!/usr/bin/env python3
"""Prepare and evaluate the bounded live pipeline target qualification."""

from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path
from typing import Any

from ishikawa.artifact_adapter import load_prepared_documents
from ishikawa.canonical import canonical_json_bytes, domain_digest, file_sha256
from ishikawa.document_producer import METHOD_PROFILE_ID
from ishikawa.operator_ingestion import OperatorIngestionPaths, load_operator_configuration


NOMIC_MODEL = "nomic-ai/nomic-embed-text-v1.5"


def fail(reason: str) -> None:
    print(f"live_document_pipeline_target_evaluation=blocked;reason={reason}")
    raise SystemExit(1)


def load_json(path: Path, label: str) -> dict[str, Any]:
    if not path.is_file() or path.is_symlink() or path.stat().st_size > 128 * 1024 * 1024:
        fail(f"{label}_unsafe")
    try:
        value = json.loads(
            path.read_text(encoding="utf-8"),
            parse_constant=lambda _value: (_ for _ in ()).throw(ValueError()),
        )
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError):
        fail(f"{label}_invalid")
    if not isinstance(value, dict):
        fail(f"{label}_invalid")
    return value


def write_exclusive(path: Path, value: dict[str, Any]) -> tuple[str, int]:
    if not path.is_absolute() or path.exists() or path.is_symlink() or not path.parent.is_dir():
        fail("output_path_unsafe")
    payload = canonical_json_bytes(value) + b"\n"
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)
    return file_sha256(str(path)), len(payload)


def operator_inputs(config_root: Path, source_root: Path):
    if (
        not config_root.is_absolute()
        or not config_root.is_dir()
        or config_root.is_symlink()
        or not source_root.is_absolute()
        or not source_root.is_dir()
        or source_root.is_symlink()
    ):
        fail("operator_input_root_unsafe")
    paths = OperatorIngestionPaths(
        config_root / "document_classes.yaml",
        config_root / "document_catalog.yaml",
        config_root / "ingestion_manifest.yaml",
        source_root,
        source_root / ".unused-reports",
    )
    return load_operator_configuration(paths)


def prepare(arguments: argparse.Namespace) -> int:
    _, _, manifest = operator_inputs(arguments.config_root, arguments.source_root)
    documents = []
    for item in sorted(manifest.documents, key=lambda value: value.document_key):
        source = arguments.source_root.joinpath(*item.source_path.split("/"))
        if not source.is_file() or source.is_symlink():
            fail("source_file_unsafe")
        documents.append(
            {
                "action": "add",
                "document_key": item.document_key,
                "class_id": item.class_id,
                "relative_source_path": item.source_path,
                "source_sha256": file_sha256(str(source)),
            }
        )
    validation_id = domain_digest(
        "ishikawa.live-document-pipeline-target-qualification.v1",
        {"manifest_digest": manifest.digest, "documents": documents},
    )
    request = {
        "schema_version": 1,
        "validation_id": validation_id,
        "method_profile_id": METHOD_PROFILE_ID,
        "manifest_digest": manifest.digest,
        "documents": documents,
    }
    digest, size = write_exclusive(arguments.output, request)
    print("purpose=prepare_live_document_pipeline_target_request")
    print(f"requested_documents={len(documents)};whole_corpus_implicit=false")
    print(f"validation_id={validation_id};manifest_digest={manifest.digest}")
    print(f"request_sha256={digest};request_bytes={size}")
    print("live_document_pipeline_target_request=pass")
    return 0


def evaluate(arguments: argparse.Namespace) -> int:
    _, _, manifest = operator_inputs(arguments.config_root, arguments.source_root)
    request = load_json(arguments.request, "request")
    result = load_json(arguments.result, "result")
    expected_result_fields = {
        "schema_version",
        "outcome",
        "validation_id",
        "method_profile_id",
        "manifest_digest",
        "served_model",
        "normalized_sha256",
        "chunk_sha256",
        "embedding_sha256",
        "credential_retained",
    }
    if set(result) != expected_result_fields:
        fail("result_contract_invalid")
    expected = {
        "schema_version": 1,
        "outcome": "pass",
        "validation_id": request.get("validation_id"),
        "method_profile_id": METHOD_PROFILE_ID,
        "manifest_digest": manifest.digest,
        "served_model": NOMIC_MODEL,
        "credential_retained": False,
    }
    if any(result.get(key) != value for key, value in expected.items()):
        fail("result_contract_mismatch")
    artifacts = (
        (arguments.normalized, result.get("normalized_sha256")),
        (arguments.chunks, result.get("chunk_sha256")),
        (arguments.embeddings, result.get("embedding_sha256")),
    )
    for path, digest in artifacts:
        if (
            not isinstance(digest, str)
            or len(digest) != 64
            or not path.is_file()
            or path.is_symlink()
            or file_sha256(str(path)) != digest
        ):
            fail("artifact_identity_mismatch")
    try:
        prepared = load_prepared_documents(
            normalized_path=arguments.normalized,
            normalized_sha256=result["normalized_sha256"],
            chunk_path=arguments.chunks,
            chunk_sha256=result["chunk_sha256"],
            embedding_path=arguments.embeddings,
            embedding_sha256=result["embedding_sha256"],
            manifest=manifest,
            source_root=arguments.source_root,
        )
    except (RuntimeError, OSError, TypeError, ValueError):
        fail("artifact_adapter_rejected")
    documents = len(prepared)
    pages = sum(item.page_count for item in prepared)
    units = sum(len(item.structural_units) for item in prepared)
    chunks = sum(len(item.chunks) for item in prepared)
    dimensions = {item.embedding_space.dimension for item in prepared}
    keys = {item.document_key for item in prepared}
    expected_keys = {item.document_key for item in manifest.documents}
    if (
        documents != 6
        or pages != 27
        or units != 231
        or chunks != 126
        or dimensions != {768}
        or keys != expected_keys
    ):
        fail("prepared_inventory_mismatch")
    structural_paths = sum(
        1
        for document in prepared
        for unit in document.structural_units
        if unit.structural_path
    )
    if structural_paths == 0:
        fail("structural_path_inventory_empty")

    artifact = {
        "schema_version": 1,
        "purpose": "live_document_pipeline_target_qualification",
        "documents": documents,
        "pages": pages,
        "structural_units": units,
        "chunks": chunks,
        "embedding_dimension": 768,
        "documents_with_stable_keys": len(keys),
        "structural_units_with_paths": structural_paths,
        "request_contract": "pass",
        "result_contract": "pass",
        "artifact_adapter": "pass",
        "credential_retained": False,
        "source_content_retained": False,
        "vectors_retained": False,
        "database_contact": False,
        "generation_model_contact": False,
    }
    digest, size = write_exclusive(arguments.output, artifact)
    print("purpose=evaluate_live_document_pipeline_target")
    print("request_contract=pass;result_contract=pass;artifact_adapter=pass")
    print(f"documents={documents};pages={pages};structural_units={units};chunks={chunks}")
    print(f"embedding_dimension=768;documents_with_stable_keys={len(keys)};structural_units_with_paths={structural_paths}")
    print("database_contact=false;generation_model_contact=false;credential_retained=false")
    print(f"qualification_artifact_sha256={digest};qualification_artifact_bytes={size}")
    print("live_document_pipeline_target_evaluation=pass")
    return 0


def self_test() -> int:
    with tempfile.TemporaryDirectory() as temporary:
        path = Path(temporary) / "value.json"
        path.write_bytes(canonical_json_bytes({"schema_version": 1}) + b"\n")
        if load_json(path, "self_test") != {"schema_version": 1}:
            return 1
    print("live_document_pipeline_target_evaluator_self_test=pass")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    subparsers = parser.add_subparsers(dest="operation")
    prepare_parser = subparsers.add_parser("prepare")
    prepare_parser.add_argument("--config-root", required=True, type=Path)
    prepare_parser.add_argument("--source-root", required=True, type=Path)
    prepare_parser.add_argument("--output", required=True, type=Path)
    evaluate_parser = subparsers.add_parser("evaluate")
    evaluate_parser.add_argument("--config-root", required=True, type=Path)
    evaluate_parser.add_argument("--source-root", required=True, type=Path)
    evaluate_parser.add_argument("--request", required=True, type=Path)
    evaluate_parser.add_argument("--result", required=True, type=Path)
    evaluate_parser.add_argument("--normalized", required=True, type=Path)
    evaluate_parser.add_argument("--chunks", required=True, type=Path)
    evaluate_parser.add_argument("--embeddings", required=True, type=Path)
    evaluate_parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()
    if arguments.self_test:
        return self_test()
    if arguments.operation == "prepare":
        return prepare(arguments)
    if arguments.operation == "evaluate":
        return evaluate(arguments)
    parser.error("one operation is required")


if __name__ == "__main__":
    raise SystemExit(main())
