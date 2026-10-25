#!/usr/bin/env python3
"""Qualify responsive and nonresponsive synthetic relevance cases locally."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import unicodedata
from pathlib import Path
from typing import Any, NoReturn


HEX = re.compile(r"^[0-9a-f]{64}$")
RESPONSIVE_FIELDS = frozenset(
    {"case_id", "class", "question", "required_citations", "source_case_id"}
)
NONRESPONSIVE_FIELDS = frozenset(
    {"absence_terms", "case_id", "challenge_kind", "class", "question"}
)


class QualificationError(RuntimeError):
    pass


def fail(reason: str) -> NoReturn:
    raise QualificationError(reason)


def canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_json(path: Path, maximum_bytes: int) -> Any:
    if not path.is_file() or path.is_symlink() or path.stat().st_size > maximum_bytes:
        fail("unsafe_or_oversized_json")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail("invalid_json")


def require_source(path: Path, expected_sha256: str, maximum_bytes: int) -> Any:
    if HEX.fullmatch(expected_sha256 or "") is None or sha256_file(path) != expected_sha256:
        fail("source_identity_mismatch")
    return load_json(path, maximum_bytes)


def question_digest(question: str) -> str:
    return hashlib.sha256(
        b"ishikawa.relevance-question.v1\x00"
        + canonical_json_bytes({"question": question})
    ).hexdigest()


def corpus_text(chunks: Any) -> str:
    if not isinstance(chunks, dict) or chunks.get("schema_version") != 1:
        fail("chunk_contract_invalid")
    values: list[str] = []
    for document in chunks.get("documents", []):
        for chunk in document.get("candidates", []):
            for field in ("context_text", "content_text", "retrieval_text"):
                value = chunk.get(field)
                if isinstance(value, str):
                    values.append(value)
    if len(values) < 100:
        fail("chunk_inventory_invalid")
    return unicodedata.normalize("NFKC", "\n".join(values)).casefold()


def validate_cases(cases: Any, truth: Any, chunks: Any) -> dict[str, Any]:
    if not isinstance(cases, dict) or set(cases) != {
        "artifact_kind", "cases", "excluded_before_relevance", "schema_version"
    }:
        fail("case_set_fields_invalid")
    if cases["schema_version"] != 1 or cases["artifact_kind"] != "relevance_calibration_cases":
        fail("case_set_contract_invalid")
    records = cases["cases"]
    if not isinstance(records, list) or len(records) != 12:
        fail("case_inventory_invalid")
    if not isinstance(truth, list) or len(truth) != 7:
        fail("truth_inventory_invalid")
    truth_by_id = {item.get("id"): item for item in truth if isinstance(item, dict)}
    if set(truth_by_id) != {f"Q-{number:03d}" for number in range(1, 8)}:
        fail("truth_identity_invalid")
    excluded = cases["excluded_before_relevance"]
    if excluded != [{"reason": "scope_gate", "source_case_id": "Q-006"}]:
        fail("scope_exclusion_invalid")
    if truth_by_id["Q-006"].get("expected_abstention") is not True:
        fail("scope_exclusion_truth_invalid")

    responsive = [item for item in records if item.get("class") == "responsive"]
    nonresponsive = [item for item in records if item.get("class") == "nonresponsive"]
    if len(responsive) != 6 or len(nonresponsive) != 6:
        fail("class_balance_invalid")
    case_ids = [item.get("case_id") for item in records]
    if case_ids != [f"R-{number:03d}" for number in range(1, 7)] + [
        f"N-{number:03d}" for number in range(1, 7)
    ]:
        fail("case_identity_or_order_invalid")
    questions = [item.get("question") for item in records]
    if any(not isinstance(value, str) or not 12 <= len(value) <= 300 for value in questions):
        fail("question_invalid")
    if len(set(questions)) != len(questions):
        fail("duplicate_question")

    expected_sources = ["Q-001", "Q-002", "Q-003", "Q-004", "Q-005", "Q-007"]
    for item, source_id in zip(responsive, expected_sources, strict=True):
        if set(item) != RESPONSIVE_FIELDS or item["source_case_id"] != source_id:
            fail("responsive_case_fields_invalid")
        source = truth_by_id[source_id]
        if (
            item["question"] != source.get("query")
            or item["required_citations"] != source.get("required_citations")
            or not item["required_citations"]
        ):
            fail("responsive_truth_mismatch")

    accepted_challenges = ["corpus_absent"] * 3 + ["near_domain_absent"] * 3
    searchable_text = corpus_text(chunks)
    absent_terms_checked = 0
    for item, challenge in zip(nonresponsive, accepted_challenges, strict=True):
        if set(item) != NONRESPONSIVE_FIELDS or item["challenge_kind"] != challenge:
            fail("nonresponsive_case_fields_invalid")
        terms = item["absence_terms"]
        if not isinstance(terms, list) or not terms or any(
            not isinstance(term, str) or not 3 <= len(term) <= 80 for term in terms
        ):
            fail("absence_terms_invalid")
        for term in terms:
            normalized = unicodedata.normalize("NFKC", term).casefold()
            if normalized in searchable_text:
                fail("declared_absence_term_present")
            absent_terms_checked += 1

    digests = [
        {
            "case_id": item["case_id"],
            "class": item["class"],
            "question_digest": question_digest(item["question"]),
        }
        for item in records
    ]
    return {
        "absence_terms_checked": absent_terms_checked,
        "case_digests": digests,
        "near_domain_nonresponsive": 3,
        "nonresponsive": 6,
        "responsive": 6,
        "scope_excluded": 1,
    }


def write_artifact(path: Path, value: dict[str, Any]) -> str:
    if path.exists() or path.is_symlink() or not path.parent.is_dir():
        fail("output_path_invalid")
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(canonical_json_bytes(value) + b"\n")
    return sha256_file(path)


def self_test() -> None:
    assert question_digest("test") == question_digest("test")
    assert question_digest("test") != question_digest("Test")
    print("relevance_case_contract_evaluator_self_test=PASS")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cases", type=Path)
    parser.add_argument("--expected-cases-sha256")
    parser.add_argument("--truth", type=Path)
    parser.add_argument("--expected-truth-sha256")
    parser.add_argument("--chunks", type=Path)
    parser.add_argument("--expected-chunks-sha256")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    try:
        if arguments.self_test:
            self_test()
            return 0
        if not all(
            (
                arguments.cases,
                arguments.expected_cases_sha256,
                arguments.truth,
                arguments.expected_truth_sha256,
                arguments.chunks,
                arguments.expected_chunks_sha256,
                arguments.output,
            )
        ):
            fail("required_argument_missing")
        cases = require_source(arguments.cases, arguments.expected_cases_sha256, 1024 * 1024)
        truth = require_source(arguments.truth, arguments.expected_truth_sha256, 1024 * 1024)
        chunks = require_source(arguments.chunks, arguments.expected_chunks_sha256, 32 * 1024 * 1024)
        summary = validate_cases(cases, truth, chunks)
        artifact = {
            "absence_terms_checked": summary["absence_terms_checked"],
            "case_digests": summary["case_digests"],
            "case_set_sha256": arguments.expected_cases_sha256,
            "chunk_set_sha256": arguments.expected_chunks_sha256,
            "model_called": False,
            "near_domain_nonresponsive": summary["near_domain_nonresponsive"],
            "nonresponsive": summary["nonresponsive"],
            "purpose": "relevance_calibration_case_contract_qualification",
            "raw_question_text_retained": False,
            "responsive": summary["responsive"],
            "schema_version": 1,
            "scope_excluded": summary["scope_excluded"],
            "threshold_selected": False,
            "truth_sha256": arguments.expected_truth_sha256,
        }
        artifact_sha256 = write_artifact(arguments.output, artifact)
    except (QualificationError, KeyError, TypeError, ValueError, OSError) as exc:
        reason = str(exc) if isinstance(exc, QualificationError) else "bounded_runtime_failure"
        print(f"relevance_case_contract_qualification=blocked;reason={reason}")
        return 1
    print("purpose=qualify_responsive_and_nonresponsive_relevance_calibration_cases")
    print(
        f"cases=12;responsive={summary['responsive']};nonresponsive={summary['nonresponsive']};"
        f"near_domain_nonresponsive={summary['near_domain_nonresponsive']}"
    )
    print(
        f"scope_excluded={summary['scope_excluded']};absence_terms_checked={summary['absence_terms_checked']};"
        "responsive_truth_match=pass"
    )
    print("threshold_selected=false;model_call=false;network_contact=false;database_contact=false")
    print(f"relevance_case_qualification_artifact_sha256={artifact_sha256}")
    print("relevance_case_contract_qualification=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
