#!/usr/bin/env python3
"""Create corpus-v3 catalog and ingestion YAML for one target-side run."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import tempfile
from pathlib import Path
from typing import Any


DOCUMENT_ID = re.compile(r"SYN-V3-[0-9]{3}\Z")
DOCUMENT_KEY = re.compile(r"[a-z0-9]+(?:[._-][a-z0-9]+)*\Z")
MANIFEST_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}\.yaml\Z")
HEX_DIGEST = re.compile(r"[0-9a-f]{64}\Z")
EXPECTED_DOCUMENTS = 30
EXPECTED_PAGES = 150
CLASS_BY_TYPE = {
    "checklist": "administrative_form",
    "form": "administrative_form",
    "guide": "policy_sop",
    "manual": "policy_sop",
    "policy": "policy_sop",
    "procedure": "policy_sop",
    "standard": "policy_sop",
}


class ConfigurationGenerationError(ValueError):
    """One corpus input or output violated the bounded run contract."""


def fail(reason: str) -> None:
    raise ConfigurationGenerationError(reason)


def regular_file(path: Path, reason: str) -> Path:
    if not path.is_file() or path.is_symlink():
        fail(reason)
    return path


def safe_directory(path: Path, reason: str) -> Path:
    if not path.is_absolute() or not path.is_dir() or path.is_symlink():
        fail(reason)
    return path.resolve(strict=True)


def load_json(path: Path, reason: str) -> Any:
    regular_file(path, reason)
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ConfigurationGenerationError(reason) from error


def text(value: Any, reason: str, maximum: int = 512) -> str:
    if (
        not isinstance(value, str)
        or not value
        or value != value.strip()
        or len(value) > maximum
        or "\x00" in value
        or "\r" in value
        or "\n" in value
    ):
        fail(reason)
    return value


def digest(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(block)
    return hasher.hexdigest()


def atomic_write(path: Path, content: str) -> None:
    parent = safe_directory(path.parent, "output_parent_unsafe")
    if path.exists() or path.is_symlink():
        fail("output_already_exists")
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=parent
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def quoted(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def generate(
    corpus_root: Path,
    source_root: Path,
    config_root: Path,
    manifest_name: str,
    *,
    expected_documents: int = EXPECTED_DOCUMENTS,
    expected_pages: int = EXPECTED_PAGES,
) -> tuple[Path, Path, str]:
    corpus = safe_directory(corpus_root, "corpus_root_unsafe")
    source = safe_directory(source_root, "source_root_unsafe")
    config = safe_directory(config_root, "config_root_unsafe")
    pending = safe_directory(config / "ingestion" / "pending", "pending_root_unsafe")
    if MANIFEST_NAME.fullmatch(manifest_name) is None or "/" in manifest_name:
        fail("manifest_name_invalid")

    truth_path = corpus / "corpus-truth.json"
    source_manifest_path = corpus / "source-manifest.json"
    keys_path = corpus / "document-keys.json"
    truth = load_json(truth_path, "corpus_truth_invalid")
    source_manifest = load_json(source_manifest_path, "source_manifest_invalid")
    keys = load_json(keys_path, "document_keys_invalid")
    if not isinstance(truth, dict) or truth.get("corpus_identity") != "synthetic-corpus-v3":
        fail("corpus_identity_invalid")
    documents = truth.get("documents")
    source_records = source_manifest.get("files") if isinstance(source_manifest, dict) else None
    if (
        not isinstance(documents, list)
        or not isinstance(source_records, list)
        or not isinstance(keys, dict)
        or len(documents) != expected_documents
        or len(source_records) != expected_documents
        or len(keys) != expected_documents
        or truth.get("document_count") != expected_documents
        or sum(item.get("pages", 0) for item in documents if isinstance(item, dict))
        != expected_pages
    ):
        fail("corpus_inventory_invalid")

    expected_ids = [f"SYN-V3-{index:03d}" for index in range(1, expected_documents + 1)]
    if [item.get("doc_id") for item in documents if isinstance(item, dict)] != expected_ids:
        fail("document_order_invalid")
    if [item.get("doc_id") for item in source_records if isinstance(item, dict)] != expected_ids:
        fail("source_order_invalid")
    if list(keys) != expected_ids:
        fail("document_key_order_invalid")

    catalog_lines = ["schema_version: 1", "", "documents:"]
    manifest_lines = ["schema_version: 1", "", "documents:"]
    seen_files: set[str] = set()
    seen_keys: set[str] = set()
    for document, record in zip(documents, source_records, strict=True):
        if not isinstance(document, dict) or not isinstance(record, dict):
            fail("document_record_invalid")
        doc_id = text(document.get("doc_id"), "document_id_invalid", 10)
        if DOCUMENT_ID.fullmatch(doc_id) is None or record.get("doc_id") != doc_id:
            fail("document_identity_mismatch")
        filename = text(record.get("filename"), "source_filename_invalid", 255)
        if (
            Path(filename).name != filename
            or Path(filename).suffix.lower() != ".pdf"
            or document.get("filename") != filename
            or filename in seen_files
        ):
            fail("source_filename_invalid")
        seen_files.add(filename)
        expected_digest = text(record.get("sha256"), "source_digest_invalid", 64)
        expected_bytes = record.get("bytes")
        if HEX_DIGEST.fullmatch(expected_digest) is None or type(expected_bytes) is not int or expected_bytes < 1:
            fail("source_manifest_record_invalid")
        transfer_source = regular_file(corpus / "source" / filename, "transfer_source_invalid")
        run_source = regular_file(source / filename, "run_source_invalid")
        if (
            transfer_source.stat().st_size != expected_bytes
            or run_source.stat().st_size != expected_bytes
            or digest(transfer_source) != expected_digest
            or digest(run_source) != expected_digest
        ):
            fail("source_bytes_mismatch")

        document_key = text(keys.get(doc_id), "document_key_invalid", 128)
        if DOCUMENT_KEY.fullmatch(document_key) is None or document_key in seen_keys:
            fail("document_key_invalid")
        seen_keys.add(document_key)
        display_name = text(document.get("title"), "display_name_invalid")
        document_type = text(document.get("document_type"), "document_type_invalid", 64)
        class_id = CLASS_BY_TYPE.get(document_type)
        if class_id is None:
            fail("document_type_unsupported")
        catalog_lines.extend(
            [
                f"  - document_key: {quoted(document_key)}",
                f"    display_name: {quoted(display_name)}",
                "    status: active",
            ]
        )
        manifest_lines.extend(
            [
                f"  - source_path: {quoted(filename)}",
                f"    document_key: {quoted(document_key)}",
                f"    class_id: {quoted(class_id)}",
            ]
        )
    if {item.name for item in source.iterdir() if item.is_file()} != seen_files:
        fail("run_source_inventory_invalid")

    manifest_lines.extend(["", "retirements: []"])
    catalog_path = config / "document_catalog.yaml"
    manifest_path = pending / manifest_name
    atomic_write(catalog_path, "\n".join(catalog_lines) + "\n")
    try:
        atomic_write(manifest_path, "\n".join(manifest_lines) + "\n")
    except Exception:
        catalog_path.unlink(missing_ok=True)
        raise
    return catalog_path, manifest_path, digest(source_manifest_path)


def self_test() -> None:
    with tempfile.TemporaryDirectory(prefix="ishikawa-corpus-config-self-test.") as temporary:
        root = Path(temporary)
        corpus = root / "corpus"
        run_source = root / "run-source"
        config = root / "config"
        (corpus / "source").mkdir(parents=True)
        run_source.mkdir()
        (config / "ingestion" / "pending").mkdir(parents=True)
        documents: list[dict[str, Any]] = []
        records: list[dict[str, Any]] = []
        keys: dict[str, str] = {}
        for index, document_type in enumerate(("policy", "form"), start=1):
            doc_id = f"SYN-V3-{index:03d}"
            filename = f"sample-{index}.pdf"
            body = b"%PDF-1.4\nsynthetic\n" + bytes([index])
            (corpus / "source" / filename).write_bytes(body)
            (run_source / filename).write_bytes(body)
            documents.append(
                {
                    "doc_id": doc_id,
                    "document_type": document_type,
                    "filename": filename,
                    "pages": 1,
                    "title": f"Sample {index}",
                }
            )
            records.append(
                {
                    "bytes": len(body),
                    "doc_id": doc_id,
                    "filename": filename,
                    "sha256": hashlib.sha256(body).hexdigest(),
                }
            )
            keys[doc_id] = f"sample.{index}"
        (corpus / "corpus-truth.json").write_text(
            json.dumps(
                {
                    "corpus_identity": "synthetic-corpus-v3",
                    "document_count": 2,
                    "documents": documents,
                }
            ),
            encoding="utf-8",
        )
        (corpus / "source-manifest.json").write_text(
            json.dumps({"files": records}), encoding="utf-8"
        )
        (corpus / "document-keys.json").write_text(json.dumps(keys), encoding="utf-8")
        catalog, manifest, _ = generate(
            corpus,
            run_source,
            config,
            "self-test.yaml",
            expected_documents=2,
            expected_pages=2,
        )
        if (
            'document_key: "sample.1"' not in catalog.read_text(encoding="utf-8")
            or 'class_id: "administrative_form"' not in manifest.read_text(encoding="utf-8")
        ):
            fail("self_test_output_invalid")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--corpus-root")
    parser.add_argument("--source-root")
    parser.add_argument("--config-root")
    parser.add_argument("--manifest-name", default="qualification-corpus-v3.yaml")
    arguments = parser.parse_args()
    try:
        if arguments.self_test:
            if arguments.corpus_root or arguments.source_root or arguments.config_root:
                fail("self_test_arguments_invalid")
            self_test()
            print("corpus_v3_ingestion_config_self_test=pass")
            return 0
        if not arguments.corpus_root or not arguments.source_root or not arguments.config_root:
            fail("required_argument_missing")
        catalog, manifest, source_identity = generate(
            Path(arguments.corpus_root),
            Path(arguments.source_root),
            Path(arguments.config_root),
            arguments.manifest_name,
        )
        print(
            "corpus_v3_ingestion_config=pass;documents=30;"
            f"catalog_sha256={digest(catalog)};manifest_sha256={digest(manifest)};"
            f"source_manifest_sha256={source_identity};created_on_target=true"
        )
        return 0
    except ConfigurationGenerationError as error:
        print(f"corpus_v3_ingestion_config=blocked;reason={error}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
