#!/usr/bin/env python3
"""Generate the immutable-masthead synthetic corpus v2 candidate.

The v1 fixture is read as a code library only.  V2 is emitted into a separate
operator-selected directory, adds the accepted masthead pattern to the first
page of every document, and keeps all content fictional.  It never mutates or
relabels the accepted v1 corpus.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
from typing import Any


DOCUMENTS = {
    "OPS_17_CTL_2001.pdf": {
        "doc_id": "SYN-V2-001",
        "document_context": "Controlled Materials Access",
        "organization_name": "Synthetic Example Organization",
        "effective_date": "2099-01-01",
        "policy_number": "99 TST 2001",
        "applicability_class": "Controlled Materials",
        "department_label": "Department:",
        "department": "Information Technology",
        "review_date": "2099-06-30",
        "approval": "Synthetic Board A",
    },
    "OPS_17_CTL_2002_RevA.pdf": {
        "doc_id": "SYN-V2-002",
        "document_context": "Controlled Access Exception Review",
        "organization_name": "Synthetic Example Organization",
        "effective_date": "2099-01-15",
        "policy_number": "99 TST 2002",
        "applicability_class": "Exception Review",
        "department_label": "Dept:",
        "department": "Operations Control",
        "review_date": "2099-07-15",
        "approval": "Synthetic Board B",
    },
    "31_SCH_2003.pdf": {
        "doc_id": "SYN-V2-003",
        "document_context": "Controlled Activity Scheduling",
        "organization_name": "Synthetic Example Organization",
        "effective_date": "2099-02-01",
        "policy_number": "99 TST 2003",
        "applicability_class": "Scheduled Activity",
        "department_label": "Dept.:",
        "department": "Scheduling Office",
        "review_date": "2099-08-01",
        "approval": "Synthetic Board C",
    },
    "Form_TST9001.pdf": {
        "doc_id": "SYN-V2-004",
        "document_context": "Controlled Access Exception Request",
        "organization_name": "Synthetic Example Organization",
        "effective_date": "2099-03-01",
        "policy_number": "TST-9001",
        "applicability_class": "Controlled Access Form",
        "department_label": "Department:",
        "department": "Information Technology",
        "review_date": "2099-09-01",
        "approval": "Synthetic Forms Office",
    },
    "Governance_Manual_2005_Revision_3.pdf": {
        "doc_id": "SYN-V2-005",
        "document_context": "Governance Records",
        "organization_name": "Synthetic Example Organization",
        "effective_date": "2099-03-15",
        "policy_number": "99 TST 2005",
        "applicability_class": "Governance Records",
        "department_label": "Dept:",
        "department": "Records Governance",
        "review_date": "2099-09-15",
        "approval": "Synthetic Board D",
    },
    "SOP_42_IR_2006.pdf": {
        "doc_id": "SYN-V2-006",
        "document_context": "Incident Reporting and Response",
        "organization_name": "Synthetic Example Organization",
        "effective_date": "2099-04-01",
        "policy_number": "99 TST 2006",
        "applicability_class": "Incident Response",
        "department_label": "Dept.:",
        "department": "Information Technology",
        "review_date": "2099-10-01",
        "approval": "Synthetic Response Office",
    },
}


V2_PAGE_REFERENCE_REWRITES = {
    "99 TST 2002, Page 2": "99 TST 2002, Page 1",
    "SYNTHETIC | 99 TST 2002 | Page 2": "SYNTHETIC | 99 TST 2002 | Page 1",
}
EXPECTED_V2_PAGE_REFERENCE_REWRITES = 3


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _load_v1(path: Path):
    if not path.is_file() or path.is_symlink():
        raise SystemExit("v1_generator_missing_or_unsafe")
    spec = importlib.util.spec_from_file_location("ishikawa_synthetic_corpus_v1", path)
    if spec is None or spec.loader is None:
        raise SystemExit("v1_generator_import_failed")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _masthead_commands(base: Any, metadata: dict[str, str]) -> list[str]:
    left = 54.0
    right = 558.0
    middle = 306.0
    top = 604.0
    row_height = 24.0
    commands = [
        # Synthetic stand-in for the raster logo.  It intentionally has no
        # text object, so text extraction must ignore it.
        "q 0.82 g 54.0 622.0 94.0 94.0 re f Q",
        base.text_command(metadata["organization_name"], 421.0, 758.0, 8, "F1"),
        base.line_command(54.0, 736.0, 558.0, 736.0, 0.6),
        base.text_command(metadata["document_context"], 190.0, 667.0, 19, "F2"),
    ]
    for row in range(4):
        y = top - row * row_height
        commands.append(base.line_command(left, y, right, y, 0.6))
    for x in (left, middle, right):
        commands.append(base.line_command(x, top, x, top - 3 * row_height, 0.6))
    rows = (
        (("Effective Date:", metadata["effective_date"]), ("Policy Number:", metadata["policy_number"])),
        (("Applicability/Class:", metadata["applicability_class"]), (metadata["department_label"], metadata["department"])),
        (("Date of Review:", metadata["review_date"]), ("Approval:", metadata["approval"])),
    )
    for row_index, row in enumerate(rows):
        y = top - 15.0 - row_index * row_height
        for cell_index, (label, value) in enumerate(row):
            x = left + 7.0 + cell_index * (middle - left)
            commands.append(base.text_command(label, x, y, 8, "F2"))
            value_offset = 112.0 if cell_index == 0 else 76.0
            commands.append(base.text_command(value, x + value_offset, y, 8, "F1"))
    return commands


def _add_first_page_masthead(
    base: Any,
    commands: list[str] | None,
    metadata: dict[str, str],
) -> list[str]:
    body = list(commands or [])
    return [
        "q", "1 0 0 1 0 -244 cm", *body, "Q",
        *_masthead_commands(base, metadata),
    ]


def _rewrite_v2_page_references(commands: list[str] | None) -> tuple[list[str] | None, int]:
    """Align v2-only cross-references after removing a leading blank page."""

    if commands is None:
        return None, 0
    rewritten: list[str] = []
    replacements = 0
    for command in commands:
        updated = command
        for source, target in V2_PAGE_REFERENCE_REWRITES.items():
            count = updated.count(source)
            if count:
                updated = updated.replace(source, target)
                replacements += count
        rewritten.append(updated)
    return rewritten, replacements


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--v1-generator", required=True)
    parser.add_argument("--output-root", required=True)
    args = parser.parse_args()
    output_root = Path(args.output_root).resolve()
    if output_root.exists() or output_root.is_symlink():
        raise SystemExit("output_root_already_exists")
    source_root = output_root / "source"
    evaluation_root = output_root / "evaluation"
    source_root.mkdir(parents=True, mode=0o700)
    evaluation_root.mkdir(mode=0o700)

    base = _load_v1(Path(args.v1_generator).resolve())
    pages_by_name = dict(base.policy_documents())
    pages_by_name["Form_TST9001.pdf"] = [base.form_page_one(), base.form_page_two()]
    if set(pages_by_name) != set(DOCUMENTS):
        raise SystemExit("v1_document_inventory_changed")
    emitted_pages: dict[str, list[list[str]]] = {}
    leading_blank_pages_removed: dict[str, int] = {}
    page_reference_rewrites = 0
    for filename in sorted(pages_by_name):
        metadata = DOCUMENTS[filename]
        source_pages = pages_by_name[filename]
        first_semantic_index = next(
            (index for index, page in enumerate(source_pages) if page),
            None,
        )
        if first_semantic_index is None:
            raise SystemExit("v1_document_has_no_semantic_page")
        leading_blank_pages_removed[filename] = first_semantic_index
        semantic_pages = []
        for source_page in source_pages[first_semantic_index:]:
            rewritten_page, rewrite_count = _rewrite_v2_page_references(source_page)
            semantic_pages.append(rewritten_page)
            page_reference_rewrites += rewrite_count
        pages = [
            _add_first_page_masthead(base, page, metadata) if index == 0 else list(page or [])
            for index, page in enumerate(semantic_pages)
        ]
        emitted_pages[filename] = pages
        base.write_pdf(source_root / filename, filename.removesuffix(".pdf"), pages)

    if page_reference_rewrites != EXPECTED_V2_PAGE_REFERENCE_REWRITES:
        raise SystemExit("v2_page_reference_rewrite_inventory_changed")

    source_manifest = {
        "schema_version": 1,
        "fixture_status": "fully_synthetic_no_source_text",
        "files": [
            {
                "bytes": (source_root / filename).stat().st_size,
                "doc_id": DOCUMENTS[filename]["doc_id"],
                "filename": filename,
                "sha256": _sha256(source_root / filename),
            }
            for filename in sorted(DOCUMENTS)
        ],
    }
    truth = {
        "schema_version": 2,
        "fixture_status": "fully_synthetic_no_source_text",
        "accepted_v1_mutated": False,
        "header_fields": [
            "Effective Date", "Policy Number", "Applicability/Class",
            "Department", "Date of Review", "Approval",
        ],
        "masthead_scope": "first_page_only",
        "first_semantic_body_page": 1,
        "leading_blank_page_policy": "removed_from_v2_before_masthead",
        "page_reference_rewrites": {
            "count": page_reference_rewrites,
            "document": "99 TST 2002",
            "from_page": 2,
            "to_page": 1,
        },
        "masthead_elements": [
            "non_text_logo", "organization_name", "document_context", "control_table",
        ],
        "logo_fixture": "non_text_graphic",
        "department_label_variants": ["Department:", "Dept:", "Dept.:"] ,
        "documents": [
            {
                "filename": filename,
                **DOCUMENTS[filename],
                "pages": len(emitted_pages[filename]),
                "leading_blank_pages_removed": leading_blank_pages_removed[filename],
            }
            for filename in sorted(DOCUMENTS)
        ],
        "quality_cases": [
            {
                "id": "V2-HDR-001",
                "question": "There has been an incident concerning controlled materials.",
                "clarification_reply": "IT",
                "expected_department": "Information Technology",
                "required_documents": ["OPS_17_CTL_2001.pdf", "SOP_42_IR_2006.pdf"],
            },
            {
                "id": "V2-HDR-002",
                "question": "Which scheduled-activity policies apply to the Scheduling Office?",
                "expected_department": "Scheduling Office",
                "required_documents": ["31_SCH_2003.pdf"],
            },
        ],
    }
    _write_json(output_root / "source_manifest.json", source_manifest)
    _write_json(evaluation_root / "header_acceptance_truth.json", truth)
    manifest = {
        "schema_version": 2,
        "status": "synthetic_corpus_v2_candidate",
        "source_corpus_content_used": False,
        "accepted_v1_mutated": False,
        "document_count": len(DOCUMENTS),
        "page_count": sum(len(pages) for pages in emitted_pages.values()),
        "departments": sorted({item["department"] for item in DOCUMENTS.values()}),
        "files": [
            {
                "path": path.relative_to(output_root).as_posix(),
                "bytes": path.stat().st_size,
                "sha256": _sha256(path),
            }
            for path in sorted(output_root.rglob("*"))
            if path.is_file() and path.name != "manifest.json"
        ],
    }
    _write_json(output_root / "manifest.json", manifest)
    print(
        f"synthetic_corpus_v2_generation=pass;documents=6;pages={manifest['page_count']};"
        f"departments={len(manifest['departments'])};mastheads=6;header_fields=6;"
        f"page_reference_rewrites={page_reference_rewrites}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
