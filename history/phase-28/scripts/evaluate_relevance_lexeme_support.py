#!/usr/bin/env python3
"""Evaluate protected PostgreSQL lexeme-support observations without text."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
from pathlib import Path
from typing import Any, NoReturn


EXPECTED_SOURCE_IDS = tuple(f"R-{number:03d}" for number in range(1, 7)) + tuple(
    f"N-{number:03d}" for number in range(1, 7)
)
EXPECTED_TARGET_IDS = tuple(f"C-{number:03d}" for number in range(1, 13))
EXPECTED_DEPTHS = (1, 3, 5, 10, 20)
EXPECTED_METHOD = {
    "schema_version": 1,
    "text_search_config": "english",
    "question_measurement": "to_tsvector",
    "evidence_measurement": "stored_chunk_lexical_vector_union",
    "evidence_order": "fused_rank",
    "fused_depths": list(EXPECTED_DEPTHS),
    "changes_retrieval_ranking": False,
    "threshold_selected": False,
    "model_authority": False,
}
HEX = re.compile(r"^[0-9a-f]{64}$")
LEXEME = re.compile(r"^[^\x00-\x20\x7f]+$")


class EvaluationError(RuntimeError):
    pass


def fail(reason: str) -> NoReturn:
    raise EvaluationError(reason)


def canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, allow_nan=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def require_identity(path: Path, expected: str, maximum_bytes: int) -> None:
    if (
        HEX.fullmatch(expected or "") is None
        or not path.is_file()
        or path.is_symlink()
        or path.stat().st_size > maximum_bytes
        or sha256_file(path) != expected
    ):
        fail("source_identity_mismatch")


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail("invalid_json")


def validate_lexeme_list(value: Any) -> list[str]:
    if (
        not isinstance(value, list)
        or value != sorted(set(value))
        or any(not isinstance(item, str) or LEXEME.fullmatch(item) is None for item in value)
    ):
        fail("lexeme_inventory_invalid")
    return value


def evaluate(arguments: argparse.Namespace) -> dict[str, Any]:
    require_identity(arguments.cases, arguments.expected_cases_sha256, 1024 * 1024)
    require_identity(
        arguments.observations, arguments.expected_observations_sha256, 32 * 1024 * 1024
    )
    cases_document = load_json(arguments.cases)
    observations = load_json(arguments.observations)
    cases = cases_document.get("cases") if isinstance(cases_document, dict) else None
    if (
        not isinstance(cases, list)
        or tuple(item.get("case_id") for item in cases) != EXPECTED_SOURCE_IDS
    ):
        fail("relevance_case_inventory_invalid")
    source_by_target = dict(zip(EXPECTED_TARGET_IDS, cases))
    if (
        not isinstance(observations, dict)
        or observations.get("schema_version") != 1
        or observations.get("artifact_kind") != "relevance_retrieval_observations"
        or observations.get("case_count") != 12
        or observations.get("lexeme_support_method") != EXPECTED_METHOD
    ):
        fail("lexeme_support_method_mismatch")
    digest_input = dict(observations)
    stored_digest = digest_input.pop("observation_set_digest", None)
    expected_digest = hashlib.sha256(
        b"ishikawa.relevance-retrieval-observations.v1\x00"
        + canonical_json_bytes(digest_input)
    ).hexdigest()
    if stored_digest != expected_digest:
        fail("observation_set_digest_invalid")
    observed_cases = {item.get("case_id"): item for item in observations.get("cases", [])}
    if set(observed_cases) != set(EXPECTED_TARGET_IDS) or len(observed_cases) != 12:
        fail("observation_case_inventory_invalid")

    rows: list[dict[str, Any]] = []
    for target_id in EXPECTED_TARGET_IDS:
        source = source_by_target[target_id]
        observed = observed_cases[target_id]
        fused = observed.get("fused")
        support = observed.get("lexeme_support")
        if not isinstance(fused, list) or not isinstance(support, dict):
            fail("lexeme_support_case_invalid")
        query_lexemes = validate_lexeme_list(support.get("question_lexemes"))
        if not query_lexemes or support.get("question_lexeme_count") != len(query_lexemes):
            fail("question_lexeme_count_invalid")
        query_set = set(query_lexemes)
        measurements = support.get("measurements")
        if (
            not isinstance(measurements, list)
            or tuple(item.get("depth") for item in measurements) != EXPECTED_DEPTHS
        ):
            fail("lexeme_support_depth_inventory_invalid")
        prior_supported: set[str] = set()
        case_depths: dict[int, float] = {}
        for measurement in measurements:
            depth = measurement["depth"]
            if set(measurement) != {
                "depth",
                "fused_chunk_count",
                "supported_lexemes",
                "unsupported_lexemes",
                "supported_count",
                "unsupported_count",
            }:
                fail("lexeme_support_record_contract_invalid")
            supported = set(validate_lexeme_list(measurement["supported_lexemes"]))
            unsupported = set(validate_lexeme_list(measurement["unsupported_lexemes"]))
            if (
                supported & unsupported
                or supported | unsupported != query_set
                or measurement["supported_count"] != len(supported)
                or measurement["unsupported_count"] != len(unsupported)
                or measurement["fused_chunk_count"] != min(depth, len(fused))
                or not prior_supported.issubset(supported)
            ):
                fail("lexeme_support_partition_invalid")
            prior_supported = supported
            case_depths[depth] = len(supported) / len(query_set)
        rows.append(
            {
                "case_id": source["case_id"],
                "class": source["class"],
                "query_lexeme_count": len(query_lexemes),
                "depths": case_depths,
            }
        )

    ranges: dict[int, dict[str, float | bool]] = {}
    for depth in EXPECTED_DEPTHS:
        responsive = [row["depths"][depth] for row in rows if row["class"] == "responsive"]
        nonresponsive = [
            row["depths"][depth] for row in rows if row["class"] == "nonresponsive"
        ]
        ranges[depth] = {
            "responsive_min": min(responsive),
            "responsive_max": max(responsive),
            "nonresponsive_min": min(nonresponsive),
            "nonresponsive_max": max(nonresponsive),
            "strict_separation": min(responsive) > max(nonresponsive),
        }
    return {
        "rows": rows,
        "ranges": ranges,
        "digest": stored_digest,
        "artifact_sha256": sha256_file(arguments.observations),
        "artifact_bytes": arguments.observations.stat().st_size,
    }


def self_test() -> None:
    assert canonical_json_bytes({"b": 2, "a": 1}) == b'{"a":1,"b":2}'
    assert validate_lexeme_list(["approv", "polici"]) == ["approv", "polici"]
    assert len(EXPECTED_METHOD) == 9
    assert len(EXPECTED_SOURCE_IDS) == len(EXPECTED_TARGET_IDS) == 12
    print("relevance_lexeme_support_evaluator_self_test=PASS")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cases", type=Path)
    parser.add_argument("--expected-cases-sha256")
    parser.add_argument("--observations", type=Path)
    parser.add_argument("--expected-observations-sha256")
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
                arguments.observations,
                arguments.expected_observations_sha256,
            )
        ):
            fail("required_argument_missing")
        summary = evaluate(arguments)
    except (EvaluationError, KeyError, TypeError, ValueError, OSError) as error:
        reason = str(error) if isinstance(error, EvaluationError) else "bounded_runtime_failure"
        print(f"relevance_lexeme_support_evaluation=blocked;reason={reason}")
        return 1
    for row in summary["rows"]:
        depth_values = ";".join(
            f"d{depth}={row['depths'][depth]:.6f}" for depth in EXPECTED_DEPTHS
        )
        print(
            f"case_{row['case_id'].replace('-', '_')}={row['class']};"
            f"question_lexemes={row['query_lexeme_count']};{depth_values}"
        )
    for depth in EXPECTED_DEPTHS:
        values = summary["ranges"][depth]
        print(
            f"depth_{depth}_responsive_min={values['responsive_min']:.6f};"
            f"responsive_max={values['responsive_max']:.6f};"
            f"nonresponsive_min={values['nonresponsive_min']:.6f};"
            f"nonresponsive_max={values['nonresponsive_max']:.6f};"
            f"strict_separation={str(values['strict_separation']).lower()}"
        )
    print(
        f"observation_set_digest={summary['digest']};"
        f"observation_artifact_sha256={summary['artifact_sha256']};"
        f"observation_artifact_bytes={summary['artifact_bytes']}"
    )
    print("threshold_selected=false;model_authority=false;next_gate=review_lexeme_support_separation")
    print("relevance_lexeme_support_evaluation=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
