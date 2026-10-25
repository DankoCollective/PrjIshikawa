#!/usr/bin/env python3
"""Qualify normalized header metadata and chunk propagation for corpus v2."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


class QualificationError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise QualificationError("input_json_invalid") from error
    if not isinstance(value, dict):
        raise QualificationError("input_json_invalid")
    return value


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--python-root", required=True)
    parser.add_argument("--archive", required=True)
    parser.add_argument("--source-manifest", required=True)
    parser.add_argument("--truth", required=True)
    parser.add_argument("--normalized-output", required=True)
    parser.add_argument("--chunks-output", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_arguments()
    python_root = Path(args.python_root).resolve()
    for path in (Path(args.archive), Path(args.source_manifest), Path(args.truth)):
        if not path.is_file() or path.is_symlink():
            raise QualificationError("input_file_missing_or_unsafe")
    for path in (Path(args.normalized_output), Path(args.chunks_output)):
        if path.exists() or path.is_symlink() or not path.is_absolute():
            raise QualificationError("output_path_invalid")
    sys.path.insert(0, str(python_root))
    from ishikawa.chunking import build_chunk_candidates, chunk_candidates_json_bytes
    from ishikawa.normalization import normalize_extraction_archive, normalized_json_bytes

    archive = Path(args.archive)
    normalized = normalize_extraction_archive(
        archive,
        args.source_manifest,
        expected_archive_sha256=sha256_file(archive),
    )
    truth = load_json(Path(args.truth))
    expected = {item["filename"]: item for item in truth.get("documents", [])}
    expected_by_doc_id = {item["doc_id"]: item for item in truth.get("documents", [])}
    documents = normalized.get("documents")
    if (
        not isinstance(documents, list)
        or len(documents) != 6
        or len(expected) != 6
        or len(expected_by_doc_id) != 6
    ):
        raise QualificationError("document_inventory_invalid")
    observed_labels: set[str] = set()
    observed_departments: set[str] = set()
    info_technology_documents: set[str] = set()
    for document in documents:
        filename = document.get("filename")
        header = document.get("document_control_header")
        if filename not in expected or not isinstance(header, dict):
            raise QualificationError("header_inventory_invalid")
        fields = header.get("fields")
        if not isinstance(fields, dict) or len(fields) != 6:
            raise QualificationError("header_field_inventory_invalid")
        department = fields.get("department", {}).get("value")
        if department != expected[filename]["department"]:
            raise QualificationError("department_value_mismatch")
        if header.get("page_numbers") != [1] or header.get("repeated") is not False:
            raise QualificationError("masthead_not_first_page_only")
        context = header.get("document_context")
        if not isinstance(context, dict) or context.get("value") != expected[filename]["document_context"]:
            raise QualificationError("document_context_mismatch")
        organization = header.get("organization_name")
        if (
            not isinstance(organization, dict)
            or organization.get("value") != expected[filename]["organization_name"]
        ):
            raise QualificationError("organization_name_mismatch")
        if header.get("logo_handling") != "non_text_visual_ignored":
            raise QualificationError("logo_handling_mismatch")
        observed_departments.add(department)
        observed_labels.update(fields["department"]["source_labels"])
        if department == "Information Technology":
            info_technology_documents.add(filename)
        header_lines = set(header["line_ids"])
        covered_as_furniture = {
            span["line_id"]
            for unit in document["units"]
            if unit["kind"] == "page_furniture"
            for span in unit["source_spans"]
        }
        if not header_lines.issubset(covered_as_furniture):
            raise QualificationError("header_body_exclusion_failed")
        if any(
            span["line_id"] in header_lines
            for unit in document["units"]
            if unit["kind"] != "page_furniture"
            for span in unit["source_spans"]
        ):
            raise QualificationError("header_semantic_leak")
        if not any(
            unit["kind"] != "page_furniture" and unit["page_start"] == 1
            for unit in document["units"]
        ):
            raise QualificationError("first_semantic_body_page_invalid")
    if observed_labels != {"Department", "Dept", "Dept."}:
        raise QualificationError("department_label_normalization_failed")
    if len(observed_departments) < 4:
        raise QualificationError("department_depth_insufficient")
    if info_technology_documents != {
        "OPS_17_CTL_2001.pdf", "Form_TST9001.pdf", "SOP_42_IR_2006.pdf"
    }:
        raise QualificationError("department_cross_document_fixture_invalid")

    chunks = build_chunk_candidates(normalized)
    candidate_count = 0
    for document in chunks["documents"]:
        expected_document = expected_by_doc_id.get(document.get("document_ref"))
        if expected_document is None:
            raise QualificationError("chunk_document_identity_mismatch")
        metadata_candidates = [
            candidate for candidate in document["candidates"]
            if candidate.get("projection_kind") == "document_control_metadata"
        ]
        if len(metadata_candidates) != 1:
            raise QualificationError("document_control_candidate_count_invalid")
        metadata_candidate = metadata_candidates[0]
        if (
            metadata_candidate.get("context_text") != "Document control metadata"
            or metadata_candidate.get("citation_anchor", {}).get("page_start") != 1
            or metadata_candidate.get("citation_anchor", {}).get("page_end") != 1
            or metadata_candidate.get("projection_properties", {}).get(
                "retrieval_representative"
            ) is not True
        ):
            raise QualificationError("document_control_candidate_invalid")
        for required_line in (
            f"Document Context: {expected_document['document_context']}",
            f"Organization: {expected_document['organization_name']}",
            f"Department: {expected_document['department']}",
        ):
            if required_line not in metadata_candidate.get("retrieval_text", ""):
                raise QualificationError("document_control_candidate_text_invalid")
        for candidate in document["candidates"]:
            candidate_count += 1
            control = candidate.get("retrieval_filters", {}).get("document_control")
            if not isinstance(control, dict) or not control.get("department"):
                raise QualificationError("chunk_header_filter_missing")
            if control.get("document_context") != expected_document["document_context"]:
                raise QualificationError("chunk_document_context_filter_mismatch")
            if control.get("organization_name") != expected_document["organization_name"]:
                raise QualificationError("chunk_organization_filter_mismatch")
            if (
                candidate is not metadata_candidate
                and "Document control metadata" in candidate.get("context_text", "")
            ):
                raise QualificationError("body_chunk_header_context_duplicated")
    if candidate_count < 120:
        raise QualificationError("chunk_inventory_too_small")

    normalized_path = Path(args.normalized_output)
    chunks_path = Path(args.chunks_output)
    normalized_path.write_bytes(normalized_json_bytes(normalized))
    chunks_path.write_bytes(chunk_candidates_json_bytes(chunks))
    normalized_path.chmod(0o600)
    chunks_path.chmod(0o600)
    print(
        "header_aware_corpus_v2_qualification=pass;documents=6;"
        f"departments={len(observed_departments)};candidates={candidate_count};"
        f"normalized_sha256={sha256_file(normalized_path)};"
        f"chunks_sha256={sha256_file(chunks_path)}"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except QualificationError as error:
        print(f"header_aware_corpus_v2_qualification=blocked;reason={error}")
        raise SystemExit(1)
    except Exception as error:
        print(
            "header_aware_corpus_v2_qualification=blocked;"
            f"reason=bounded_runtime_failure;error_type={type(error).__name__}"
        )
        raise SystemExit(1)
