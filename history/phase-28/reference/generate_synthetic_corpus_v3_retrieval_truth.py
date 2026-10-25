#!/usr/bin/env python3
"""Build deterministic retrieval truth for the 30-document synthetic corpus v3.

The generated questions are evaluation fixtures only.  They are derived from
the synthetic corpus design truth, are never ingested, and are never supplied
to answer-generation models.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
from pathlib import Path
from typing import Any


HEX_DIGEST = re.compile(r"^[0-9a-f]{64}$")
EXPECTED_DOCUMENTS = 30
EXPECTED_BODY_CASES = 120
EXPECTED_RELATIONSHIP_CASES = 30
EXPECTED_HEADER_CASES = 30


class TruthError(RuntimeError):
    """Stable retrieval-truth construction failure."""


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise TruthError(reason)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def load_truth(path: Path, expected_sha256: str) -> dict[str, Any]:
    require(
        path.is_absolute()
        and path.is_file()
        and not path.is_symlink()
        and path.stat().st_size <= 4 * 1024 * 1024,
        "corpus_truth_unsafe",
    )
    require(
        HEX_DIGEST.fullmatch(expected_sha256) is not None
        and sha256_file(path) == expected_sha256,
        "corpus_truth_identity_mismatch",
    )
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise TruthError("corpus_truth_invalid") from error
    require(
        isinstance(value, dict)
        and value.get("schema_version") == 3
        and value.get("fixture_status") == "fully_synthetic_no_source_text"
        and value.get("corpus_identity") == "synthetic-corpus-v3"
        and value.get("accepted_v1_mutated") is False
        and value.get("accepted_v2_mutated") is False
        and value.get("document_count") == EXPECTED_DOCUMENTS
        and value.get("page_count") == 150
        and isinstance(value.get("documents"), list)
        and len(value["documents"]) == EXPECTED_DOCUMENTS,
        "corpus_truth_contract_invalid",
    )
    return value


def evidence(document_ref: str, page: int) -> list[dict[str, Any]]:
    return [{"document_ref": document_ref, "page": page}]


def build_cases(corpus: dict[str, Any]) -> list[dict[str, Any]]:
    cases: list[dict[str, Any]] = []
    for index, document in enumerate(corpus["documents"], start=1):
        required = {
            "doc_id", "policy_number", "title", "document_context", "department",
            "applicability_class", "effective_date", "review_date", "subject",
            "action", "record", "threshold", "control_code", "references", "pages",
        }
        require(
            isinstance(document, dict)
            and required <= set(document)
            and document["doc_id"] == f"SYN-V3-{index:03d}"
            and document["pages"] == 5
            and isinstance(document["references"], list)
            and len(document["references"]) == 3,
            "document_truth_contract_invalid",
        )
        document_ref = document["doc_id"]
        body_questions = (
            (
                1,
                f"What required control applies to {document['subject']}?",
            ),
            (
                2,
                f"Who is accountable for the {document['record']}, and what evidence must be complete?",
            ),
            (
                3,
                f"What required-control steps apply to {document['subject']}, and when is the control incomplete?",
            ),
            (
                4,
                f"How are ambiguous facts, exceptions, and urgent activity handled for {document['subject']}?",
            ),
        )
        for page, question in body_questions:
            case_number = (index - 1) * 4 + page
            cases.append({
                "case_id": f"B-{case_number:03d}",
                "family": "body",
                "question": question,
                "required_evidence": evidence(document_ref, page),
            })
        cases.append({
            "case_id": f"R-{index:03d}",
            "family": "relationship",
            "question": (
                f"Which references and review trigger are specified by the "
                f"{document['document_context']} document?"
            ),
            "required_evidence": evidence(document_ref, 5),
        })
        cases.append({
            "case_id": f"H-{index:03d}",
            "family": "header",
            "question": (
                f"For {document['policy_number']}, which department owns the document, "
                "what is its applicability/class, and when are its effective and review dates?"
            ),
            "required_evidence": evidence(document_ref, 1),
        })
    return cases


def validate_cases(cases: list[dict[str, Any]]) -> None:
    require(len(cases) == 180, "case_inventory_invalid")
    counts = {
        family: sum(item["family"] == family for item in cases)
        for family in ("body", "relationship", "header")
    }
    require(
        counts == {
            "body": EXPECTED_BODY_CASES,
            "relationship": EXPECTED_RELATIONSHIP_CASES,
            "header": EXPECTED_HEADER_CASES,
        },
        "case_family_inventory_invalid",
    )
    require(
        len({item["case_id"] for item in cases}) == len(cases)
        and len({item["question"] for item in cases}) == len(cases),
        "case_identity_not_unique",
    )
    coverage = {
        (evidence_item["document_ref"], evidence_item["page"])
        for item in cases
        for evidence_item in item["required_evidence"]
    }
    require(
        coverage
        == {
            (f"SYN-V3-{document:03d}", page)
            for document in range(1, EXPECTED_DOCUMENTS + 1)
            for page in range(1, 6)
        },
        "document_page_coverage_invalid",
    )


def write_exclusive(path: Path, payload: bytes) -> None:
    require(
        path.is_absolute()
        and not path.exists()
        and not path.is_symlink()
        and path.parent.is_dir()
        and not path.parent.is_symlink(),
        "output_path_unsafe",
    )
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)


def self_test() -> None:
    assert EXPECTED_BODY_CASES + EXPECTED_RELATIONSHIP_CASES + EXPECTED_HEADER_CASES == 180
    assert canonical_json_bytes({"b": 2, "a": 1}) == b'{"a":1,"b":2}'
    print("synthetic_corpus_v3_retrieval_truth_builder_self_test=pass")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--corpus-truth", type=Path)
    parser.add_argument("--expected-corpus-truth-sha256")
    parser.add_argument("--output", type=Path)
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
        return 0
    require(
        arguments.corpus_truth is not None
        and arguments.expected_corpus_truth_sha256 is not None
        and arguments.output is not None,
        "arguments_missing",
    )
    corpus = load_truth(
        arguments.corpus_truth.resolve(), arguments.expected_corpus_truth_sha256
    )
    cases = build_cases(corpus)
    validate_cases(cases)
    artifact = {
        "artifact_kind": "ishikawa_synthetic_corpus_v3_retrieval_truth",
        "schema_version": 1,
        "corpus_identity": "synthetic-corpus-v3",
        "synthetic_content_only": True,
        "evaluation_only": True,
        "excluded_from_corpus_ingestion": True,
        "excluded_from_generation_context": True,
        "manual_review_required": False,
        "metric": "MRR@20",
        "source_corpus_truth_sha256": arguments.expected_corpus_truth_sha256,
        "case_counts": {
            "body": EXPECTED_BODY_CASES,
            "relationship": EXPECTED_RELATIONSHIP_CASES,
            "header": EXPECTED_HEADER_CASES,
            "total": len(cases),
        },
        "coverage": {"documents": EXPECTED_DOCUMENTS, "document_pages": 150},
        "cases": cases,
    }
    write_exclusive(arguments.output.resolve(), canonical_json_bytes(artifact) + b"\n")
    print(
        "synthetic_corpus_v3_retrieval_truth=pass;"
        "cases=180;body=120;relationships=30;headers=30;"
        "documents=30;document_pages=150"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except TruthError as error:
        print(
            f"synthetic_corpus_v3_retrieval_truth=blocked;reason={error}",
            file=__import__("sys").stderr,
        )
        raise SystemExit(1) from error
