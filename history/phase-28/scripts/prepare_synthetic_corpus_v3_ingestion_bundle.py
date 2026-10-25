#!/usr/bin/env python3
"""Assemble one ephemeral, checksum-verified corpus-v3 ingestion bundle."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import sys
from pathlib import Path
from typing import Any


DOCUMENT_KEYS = (
    "policy.ops-17-control-2001",
    "policy.ops-17-control-2002",
    "policy.schedule-2003",
    "form.tst-9001",
    "policy.governance-manual",
    "procedure.incident-reporting",
    "procedure.controlled-materials-handling",
    "procedure.controlled-activity-scheduling",
    "form.schedule-change-9011",
    "policy.after-hours-operations",
    "checklist.operational-readiness",
    "policy.records-retention",
    "procedure.record-correction",
    "form.decision-record-9020",
    "guide.audit-evidence",
    "policy.incident-classification",
    "procedure.incident-escalation",
    "form.incident-intake-9030",
    "guide.post-incident-review",
    "policy.acceptable-use",
    "policy.remote-access",
    "standard.mobile-device",
    "form.use-exception-9040",
    "procedure.security-event-reporting",
    "policy.third-party-access",
    "procedure.personnel-access-lifecycle",
    "standard.data-classification",
    "form.access-authorization-9050",
    "procedure.privileged-access-review",
    "policy.information-sharing",
)
KEY = re.compile(r"^[a-z0-9]+(?:[._-][a-z0-9]+)*$")
HEX = re.compile(r"^[0-9a-f]{64}$")


class BundleError(RuntimeError):
    """Stable bundle-assembly failure."""


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise BundleError(reason)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_json(path: Path, label: str) -> dict[str, Any]:
    require(path.is_file() and not path.is_symlink(), f"{label}_unsafe")
    try:
        value = json.loads(path.read_text(encoding="utf-8", errors="strict"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise BundleError(f"{label}_invalid") from error
    require(isinstance(value, dict), f"{label}_invalid")
    return value


def verify_manifest(root: Path) -> None:
    manifest = root / "SHA256SUMS"
    require(manifest.is_file() and not manifest.is_symlink(), "checksum_manifest_unsafe")
    seen: set[str] = set()
    for line in manifest.read_text(encoding="utf-8", errors="strict").splitlines():
        parts = line.split(maxsplit=1)
        require(len(parts) == 2 and HEX.fullmatch(parts[0]) is not None, "checksum_manifest_invalid")
        relative = parts[1].lstrip("* ")
        candidate = Path(relative)
        require(
            relative not in seen
            and not candidate.is_absolute()
            and ".." not in candidate.parts,
            "checksum_manifest_invalid",
        )
        path = root / candidate
        require(path.is_file() and not path.is_symlink(), "candidate_file_unsafe")
        require(sha256(path) == parts[0], "candidate_file_identity_mismatch")
        seen.add(relative)


def yaml_scalar(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def assemble(candidate: Path, class_registry: Path, output: Path) -> None:
    candidate = candidate.resolve(strict=True)
    class_registry = class_registry.resolve(strict=True)
    require(candidate.is_dir() and not candidate.is_symlink(), "candidate_unsafe")
    require(class_registry.is_file() and not class_registry.is_symlink(), "class_registry_unsafe")
    require(output.is_absolute() and not output.exists() and output.parent.is_dir(), "output_unsafe")
    verify_manifest(candidate)

    manifest = load_json(candidate / "manifest.json", "manifest")
    source_manifest = load_json(candidate / "source_manifest.json", "source_manifest")
    truth = load_json(candidate / "evaluation" / "corpus_truth.json", "corpus_truth")
    normalized = load_json(candidate / "qualification" / "normalized.json", "normalized")
    require(
        manifest.get("status") == "synthetic_corpus_v3_candidate"
        and manifest.get("document_count") == 30
        and manifest.get("page_count") == 150
        and manifest.get("relationship_count") == 90
        and manifest.get("accepted_v1_mutated") is False
        and manifest.get("accepted_v2_mutated") is False,
        "manifest_contract_invalid",
    )
    documents = truth.get("documents")
    source_files = source_manifest.get("files")
    require(
        truth.get("corpus_identity") == "synthetic-corpus-v3"
        and isinstance(documents, list)
        and len(documents) == 30
        and isinstance(source_files, list)
        and len(source_files) == 30
        and isinstance(normalized.get("documents"), list)
        and len(normalized["documents"]) == 30,
        "corpus_inventory_invalid",
    )
    require(
        len(DOCUMENT_KEYS) == 30
        and len(set(DOCUMENT_KEYS)) == 30
        and all(KEY.fullmatch(item) is not None for item in DOCUMENT_KEYS),
        "document_key_registry_invalid",
    )
    sources_by_id = {item.get("doc_id"): item for item in source_files}
    require(len(sources_by_id) == 30, "source_identity_inventory_invalid")
    expected_ids = [f"SYN-V3-{index:03d}" for index in range(1, 31)]
    require([item.get("doc_id") for item in documents] == expected_ids, "truth_order_invalid")
    require(set(sources_by_id) == set(expected_ids), "source_identity_inventory_invalid")

    output.mkdir(mode=0o700)
    (output / "config").mkdir(mode=0o700)
    (output / "source").mkdir(mode=0o700)
    shutil.copyfile(class_registry, output / "config" / "document_classes.yaml")

    catalog = ["schema_version: 1", "documents:"]
    ingestion = ["schema_version: 1", "documents:"]
    key_map: dict[str, str] = {}
    for index, (document, document_key) in enumerate(zip(documents, DOCUMENT_KEYS, strict=True), 1):
        doc_id = f"SYN-V3-{index:03d}"
        source = sources_by_id[doc_id]
        filename = source.get("filename")
        require(
            document.get("doc_id") == doc_id
            and document.get("filename") == filename
            and isinstance(filename, str)
            and isinstance(document.get("title"), str)
            and document["title"].strip() == document["title"],
            "document_contract_invalid",
        )
        source_path = candidate / "source" / filename
        require(
            source_path.is_file()
            and not source_path.is_symlink()
            and sha256(source_path) == source.get("sha256"),
            "source_file_identity_mismatch",
        )
        shutil.copyfile(source_path, output / "source" / filename)
        class_id = (
            "administrative_form"
            if document.get("document_type") in {"form", "checklist"}
            else "policy_sop"
        )
        catalog.extend(
            (
                f"  - document_key: {yaml_scalar(document_key)}",
                f"    display_name: {yaml_scalar(document['title'])}",
                "    status: active",
            )
        )
        ingestion.extend(
            (
                f"  - source_path: {yaml_scalar(filename)}",
                f"    document_key: {yaml_scalar(document_key)}",
                f"    class_id: {yaml_scalar(class_id)}",
            )
        )
        key_map[doc_id] = document_key
    ingestion.append("retirements: []")
    (output / "config" / "document_catalog.yaml").write_text(
        "\n".join(catalog) + "\n", encoding="utf-8"
    )
    (output / "config" / "ingestion_manifest.yaml").write_text(
        "\n".join(ingestion) + "\n", encoding="utf-8"
    )
    receipt = {
        "schema": "ishikawa.synthetic-corpus-v3-ephemeral-ingestion-bundle.v1",
        "corpus_identity": "synthetic-corpus-v3",
        "document_count": 30,
        "page_count": 150,
        "relationship_pair_count": 90,
        "document_keys": key_map,
        "persistent_flat_file_index": False,
        "destination": "disposable_postgresql_qualification_cluster",
    }
    (output / "bundle-receipt.json").write_text(
        json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    paths = sorted(
        path for path in output.rglob("*") if path.is_file() and path.name != "SHA256SUMS"
    )
    (output / "SHA256SUMS").write_text(
        "".join(f"{sha256(path)}  {path.relative_to(output).as_posix()}\n" for path in paths),
        encoding="utf-8",
    )
    verify_manifest(output)


def main() -> int:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--candidate", type=Path)
    parser.add_argument("--class-registry", type=Path)
    parser.add_argument("--output", type=Path)
    arguments = parser.parse_args()
    if arguments.self_test:
        require(
            len(DOCUMENT_KEYS) == len(set(DOCUMENT_KEYS)) == 30
            and all(KEY.fullmatch(item) for item in DOCUMENT_KEYS),
            "self_test_failed",
        )
        print("synthetic_corpus_v3_ingestion_bundle_self_test=pass")
        return 0
    require(
        arguments.candidate is not None
        and arguments.class_registry is not None
        and arguments.output is not None,
        "argument_missing",
    )
    assemble(arguments.candidate, arguments.class_registry, arguments.output)
    print("synthetic_corpus_v3_ingestion_bundle=pass;documents=30;pages=150;relationship_pairs=90")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BundleError as error:
        print(f"synthetic_corpus_v3_ingestion_bundle=blocked;reason={error}", file=sys.stderr)
        raise SystemExit(1)
