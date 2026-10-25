#!/usr/bin/env python3
"""Statically qualify one generated 30-document synthetic corpus v3."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from pypdf import PdfReader


class QualificationError(RuntimeError):
    pass


def _load_json(path: Path) -> dict[str, Any]:
    if not path.is_file() or path.is_symlink():
        raise QualificationError("required_json_unsafe")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise QualificationError("required_json_invalid") from error
    if not isinstance(value, dict):
        raise QualificationError("required_json_invalid")
    return value


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def qualify(root: Path) -> dict[str, Any]:
    if not root.is_dir() or root.is_symlink():
        raise QualificationError("corpus_root_unsafe")
    manifest = _load_json(root / "manifest.json")
    source_manifest = _load_json(root / "source_manifest.json")
    truth = _load_json(root / "evaluation" / "corpus_truth.json")
    if (
        manifest.get("schema_version") != 3
        or manifest.get("status") != "synthetic_corpus_v3_candidate"
        or manifest.get("source_corpus_content_used") is not False
        or manifest.get("accepted_v1_mutated") is not False
        or manifest.get("accepted_v2_mutated") is not False
    ):
        raise QualificationError("manifest_contract_invalid")
    expected_counts = {
        "document_count": 30,
        "page_count": 150,
        "v2_anchor_document_count": 6,
        "new_document_count": 24,
        "relationship_count": 90,
    }
    for key, expected in expected_counts.items():
        if manifest.get(key) != expected:
            raise QualificationError(f"{key}_invalid")
    if not isinstance(manifest.get("department_count"), int) or manifest["department_count"] < 10:
        raise QualificationError("department_count_invalid")
    files = manifest.get("files")
    if not isinstance(files, list) or not files:
        raise QualificationError("manifest_files_invalid")
    for record in files:
        if not isinstance(record, dict) or set(record) != {"path", "bytes", "sha256"}:
            raise QualificationError("manifest_file_record_invalid")
        relative = record["path"]
        if not isinstance(relative, str) or relative.startswith("/") or ".." in Path(relative).parts:
            raise QualificationError("manifest_file_path_invalid")
        path = root / relative
        if not path.is_file() or path.is_symlink() or path.stat().st_size != record["bytes"] or _sha256(path) != record["sha256"]:
            raise QualificationError("manifest_file_identity_invalid")

    source_files = source_manifest.get("files")
    documents = truth.get("documents")
    relationships = truth.get("relationships")
    if (
        source_manifest.get("schema_version") != 1
        or source_manifest.get("fixture_status") != "fully_synthetic_no_source_text"
        or not isinstance(source_files, list)
        or len(source_files) != 30
        or truth.get("schema_version") != 3
        or truth.get("corpus_identity") != "synthetic-corpus-v3"
        or truth.get("document_count") != 30
        or truth.get("page_count") != 150
        or not isinstance(documents, list)
        or len(documents) != 30
        or not isinstance(relationships, list)
        or len(relationships) != 90
    ):
        raise QualificationError("truth_inventory_invalid")
    header = truth.get("header_contract")
    footer = truth.get("footer_contract")
    if (
        not isinstance(header, dict)
        or header.get("scope") != "first_page_only"
        or header.get("non_text_logo") is not True
        or header.get("department_label_variants") != ["Department:", "Dept:", "Dept.:"]
        or not isinstance(footer, dict)
        or footer.get("scope") != "every_page"
        or footer.get("left_organization_abbreviation") != "SEO"
        or footer.get("right_organization_abbreviation") != "SEO"
        or footer.get("center_page_pattern") != "Page N of M"
        or footer.get("semantic_retrieval") is not False
    ):
        raise QualificationError("header_footer_contract_invalid")

    by_doc_id = {item.get("doc_id"): item for item in documents if isinstance(item, dict)}
    by_policy = {item.get("policy_number"): item for item in documents if isinstance(item, dict)}
    if len(by_doc_id) != 30 or len(by_policy) != 30:
        raise QualificationError("document_identity_not_unique")
    if sum(item.get("v2_anchor") is True for item in documents) != 6:
        raise QualificationError("v2_anchor_inventory_invalid")
    if {item.get("department_label") for item in documents} != {"Department:", "Dept:", "Dept.:"}:
        raise QualificationError("department_label_inventory_invalid")
    departments = {item.get("department") for item in documents}
    if len(departments) < 10 or None in departments:
        raise QualificationError("department_inventory_invalid")

    source_by_name = {item.get("filename"): item for item in source_files if isinstance(item, dict)}
    if len(source_by_name) != 30:
        raise QualificationError("source_identity_not_unique")
    page_digests: set[str] = set()
    document_text_digests: set[str] = set()
    table_documents = 0
    for document in documents:
        filename = document.get("filename")
        source = source_by_name.get(filename)
        if source is None:
            raise QualificationError("source_document_missing")
        path = root / "source" / filename
        if not path.is_file() or path.is_symlink() or _sha256(path) != source.get("sha256"):
            raise QualificationError("source_document_identity_invalid")
        reader = PdfReader(path)
        if len(reader.pages) != 5 or document.get("pages") != 5:
            raise QualificationError("document_page_count_invalid")
        extracted = [(page.extract_text() or "") for page in reader.pages]
        if any(not text.strip() for text in extracted):
            raise QualificationError("document_blank_page")
        first = extracted[0]
        for label in ("Effective Date:", "Policy Number:", "Applicability/Class:", "Date of Review:", "Approval:"):
            if label not in first:
                raise QualificationError("masthead_field_missing")
        if document["department_label"] not in first or document["department"] not in first:
            raise QualificationError("masthead_department_missing")
        for page_number, text in enumerate(extracted, start=1):
            for expected in (
                "SEO Policy",
                document["policy_number"],
                f"Page {page_number} of 5",
                "For SEO Use Only",
                document["effective_date"],
                document["review_date"],
            ):
                if expected not in text:
                    raise QualificationError("footer_contract_missing")
            page_digests.add(hashlib.sha256(text.encode("utf-8")).hexdigest())
        combined = "\n".join(extracted)
        if document["control_code"] not in combined or document["record"] not in combined:
            raise QualificationError("document_unique_content_missing")
        if all(reference not in combined for reference in document["references"]):
            raise QualificationError("document_reference_text_missing")
        document_text_digests.add(hashlib.sha256(combined.encode("utf-8")).hexdigest())
        if document["document_type"] in {"form", "checklist"}:
            table_documents += 1
            if not all(label in extracted[2] for label in ("Field", "Value", "Required", "Status")):
                raise QualificationError("structured_table_missing")
    if len(page_digests) != 150 or len(document_text_digests) != 30:
        raise QualificationError("content_diversity_invalid")
    if table_documents < 5:
        raise QualificationError("structured_document_inventory_invalid")

    relationship_pairs = set()
    for relationship in relationships:
        if not isinstance(relationship, dict):
            raise QualificationError("relationship_invalid")
        source = by_doc_id.get(relationship.get("source_doc_id"))
        target = by_doc_id.get(relationship.get("target_doc_id"))
        if source is None or target is None or source is target:
            raise QualificationError("relationship_endpoint_invalid")
        if relationship.get("source_policy_number") != source["policy_number"] or relationship.get("target_policy_number") != target["policy_number"] or relationship.get("relation") != "explicit_reference":
            raise QualificationError("relationship_identity_invalid")
        relationship_pairs.add((source["doc_id"], target["doc_id"]))
    if len(relationship_pairs) != 90:
        raise QualificationError("relationship_duplicate")

    return {
        "documents": 30,
        "pages": 150,
        "v2_anchors": 6,
        "new_documents": 24,
        "departments": len(departments),
        "relationships": 90,
        "unique_pages": 150,
        "structured_documents": table_documents,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus-root", required=True)
    args = parser.parse_args()
    try:
        summary = qualify(Path(args.corpus_root).resolve())
    except (QualificationError, OSError, ValueError) as error:
        reason = str(error) if isinstance(error, QualificationError) else "unexpected_qualification_failure"
        print(f"synthetic_corpus_v3_qualification=blocked;reason={reason}")
        return 1
    print(
        "synthetic_corpus_v3_qualification=pass;"
        + ";".join(f"{key}={value}" for key, value in summary.items())
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
