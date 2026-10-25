#!/usr/bin/env python3
"""Apply the frozen strict T12 gate to one fresh 60-case MRR observation."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from fractions import Fraction
from pathlib import Path
from typing import Any, Sequence


EXPECTED_CASE_COUNT = 60
STRICT_TARGET = Fraction(91, 100)
T12_DIRECT_CASES = ("E-034", "E-036", "E-040", "E-046", "E-052")
HEX_64 = re.compile(r"[0-9a-f]{64}")


class T12ClassificationError(RuntimeError):
    """Stable, content-free T12 classification failure."""


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise T12ClassificationError(reason)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def strict_gate(mrr: Fraction) -> str:
    return "pass" if mrr > STRICT_TARGET else "not_met"


def metrics_for_ranks(ranks: Sequence[int | None]) -> dict[str, Any]:
    require(len(ranks) == EXPECTED_CASE_COUNT, "rank_count_invalid")
    require(all(rank is None or 1 <= rank <= 20 for rank in ranks), "rank_invalid")
    reciprocal_sum = sum(
        (Fraction(1, rank) if rank is not None else Fraction(0, 1)) for rank in ranks
    )
    mrr = reciprocal_sum / EXPECTED_CASE_COUNT
    return {
        "mrr_at_20": format(float(mrr), ".6f"),
        "mrr_fraction_numerator": mrr.numerator,
        "mrr_fraction_denominator": mrr.denominator,
        "cases_with_relevant_at_20": sum(rank is not None for rank in ranks),
        "cases_with_relevant_at_5": sum(rank is not None and rank <= 5 for rank in ranks),
        "promotion_gate": strict_gate(mrr),
    }


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def self_test() -> int:
    require(strict_gate(Fraction(91, 100)) == "not_met", "strict_boundary_failed")
    require(strict_gate(Fraction(911, 1000)) == "pass", "strict_above_boundary_failed")
    projected = Fraction(6619, 7200)
    require(
        format(float(projected), ".6f") == "0.919306"
        and strict_gate(projected) == "pass",
        "projected_metric_failed",
    )
    print("t12_extended_mrr_classifier_self_test=pass")
    return 0


def load_input(path: Path) -> dict[str, Any]:
    require(path.is_absolute() and path.is_file() and not path.is_symlink(), "input_unsafe")
    require(path.stat().st_size <= 5 * 1024 * 1024, "input_too_large")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise T12ClassificationError("input_invalid") from error
    require(isinstance(value, dict), "input_contract_invalid")
    required_keys = {
        "artifact_kind", "case_count", "case_set_sha256", "cases", "corpus_inventory",
        "database_boundary", "database_write", "deployment_profile_id", "embedding_space_id",
        "gemma_contact", "lane_candidate_totals", "manual_review_performed", "metrics",
        "mrr_threshold", "observation_set_id", "promotion_gate_basis", "query_vectors_retained",
        "question_text_retained", "retrieval_profile", "retrieval_profile_id",
        "runtime_dependency_profile_id", "schema_version", "source_text_retained",
    }
    require(set(value) == required_keys, "input_contract_invalid")
    require(
        value.get("artifact_kind") == "ishikawa_extended_retrieval_mrr_observation"
        and value.get("schema_version") == 1
        and value.get("case_count") == EXPECTED_CASE_COUNT
        and isinstance(value.get("case_set_sha256"), str)
        and HEX_64.fullmatch(value["case_set_sha256"]) is not None
        and isinstance(value.get("retrieval_profile_id"), str)
        and HEX_64.fullmatch(value["retrieval_profile_id"]) is not None
        and value.get("database_boundary") == "repeatable_read_read_only"
        and value.get("mrr_threshold") == "0.850000"
        and value.get("promotion_gate_basis") == "mrr_at_20_only"
        and value.get("manual_review_performed") is False
        and value.get("gemma_contact") is False
        and value.get("database_write") is False
        and value.get("question_text_retained") is False
        and value.get("query_vectors_retained") is False
        and value.get("source_text_retained") is False,
        "input_contract_invalid",
    )
    return value


def run(arguments: argparse.Namespace) -> int:
    input_path = Path(arguments.input).resolve(strict=True)
    output_path = Path(arguments.output)
    require(
        output_path.is_absolute() and not output_path.exists() and not output_path.is_symlink(),
        "output_unsafe",
    )
    value = load_input(input_path)
    cases = value.get("cases")
    require(isinstance(cases, list) and len(cases) == EXPECTED_CASE_COUNT, "cases_invalid")
    expected_ids = {f"E-{index:03d}" for index in range(1, EXPECTED_CASE_COUNT + 1)}
    seen: set[str] = set()
    ranks: list[int | None] = []
    t12_ranks: dict[str, int] = {}
    for item in cases:
        require(
            isinstance(item, dict)
            and set(item) == {"case_id", "query_sha256", "first_relevant_rank", "reciprocal_rank"}
            and isinstance(item.get("case_id"), str)
            and item["case_id"] not in seen
            and isinstance(item.get("query_sha256"), str)
            and HEX_64.fullmatch(item["query_sha256"]) is not None
            and (item.get("first_relevant_rank") is None or type(item["first_relevant_rank"]) is int),
            "case_contract_invalid",
        )
        rank = item["first_relevant_rank"]
        require(rank is None or 1 <= rank <= 20, "case_rank_invalid")
        seen.add(item["case_id"])
        ranks.append(rank)
        if item["case_id"] in T12_DIRECT_CASES:
            require(rank == 1, "t12_direct_route_rank_invalid")
            t12_ranks[item["case_id"]] = rank
    require(seen == expected_ids, "case_inventory_invalid")
    require(tuple(sorted(t12_ranks)) == T12_DIRECT_CASES, "t12_case_inventory_invalid")

    metrics = metrics_for_ranks(ranks)
    input_metrics = value.get("metrics")
    require(
        isinstance(input_metrics, dict)
        and input_metrics.get("mrr_at_20") == metrics["mrr_at_20"]
        and input_metrics.get("mrr_fraction_numerator") == metrics["mrr_fraction_numerator"]
        and input_metrics.get("mrr_fraction_denominator") == metrics["mrr_fraction_denominator"]
        and input_metrics.get("cases_with_relevant_at_20") == metrics["cases_with_relevant_at_20"]
        and input_metrics.get("cases_with_relevant_at_5") == metrics["cases_with_relevant_at_5"],
        "input_metrics_invalid",
    )

    artifact: dict[str, Any] = {
        "artifact_kind": "ishikawa_t12_extended_retrieval_mrr_observation",
        "schema_version": 1,
        "source_observation_set_id": value["observation_set_id"],
        "source_observation_sha256": sha256_file(input_path),
        "case_set_sha256": value["case_set_sha256"],
        "case_count": EXPECTED_CASE_COUNT,
        "retrieval_profile_id": value["retrieval_profile_id"],
        "retrieval_profile": value["retrieval_profile"],
        "deployment_profile_id": value["deployment_profile_id"],
        "runtime_dependency_profile_id": value["runtime_dependency_profile_id"],
        "embedding_space_id": value["embedding_space_id"],
        "database_boundary": value["database_boundary"],
        "corpus_inventory": value["corpus_inventory"],
        "lane_candidate_totals": value["lane_candidate_totals"],
        "metrics": metrics,
        "promotion_gate_basis": "strict_mrr_at_20_only",
        "strict_production_target": "greater_than_0.91",
        "t12_direct_page_case_ranks": t12_ranks,
        "manual_review_performed": False,
        "gemma_contact": False,
        "database_write": False,
        "question_text_retained": False,
        "query_vectors_retained": False,
        "source_text_retained": False,
        "cases": cases,
    }
    artifact["observation_set_id"] = hashlib.sha256(
        b"ishikawa.t12-extended-retrieval-mrr-observation.v1\x00" + canonical_bytes(artifact)
    ).hexdigest()
    payload = canonical_bytes(artifact) + b"\n"
    descriptor = os.open(output_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)
    print("purpose=classify_fresh_t12_extended_retrieval_mrr")
    print(
        f"mrr_at_20={metrics['mrr_at_20']};strict_target=greater_than_0.91;"
        f"relevant_at_5={metrics['cases_with_relevant_at_5']}/60;"
        f"relevant_at_20={metrics['cases_with_relevant_at_20']}/60"
    )
    print("t12_direct_page_cases=5/5;t12_direct_page_first_relevant_rank=1")
    print(
        f"promotion_gate={metrics['promotion_gate']};gate_basis=strict_mrr_at_20_only;"
        "manual_review_performed=false"
    )
    print(
        f"observation_set_id={artifact['observation_set_id']};"
        f"artifact_sha256={hashlib.sha256(payload).hexdigest()};artifact_bytes={len(payload)}"
    )
    print("t12_extended_mrr_classifier=pass")
    return 0


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--input")
    parser.add_argument("--output")
    arguments = parser.parse_args()
    if arguments.self_test == arguments.run:
        raise T12ClassificationError("mode_invalid")
    if arguments.run and not all((arguments.input, arguments.output)):
        raise T12ClassificationError("argument_missing")
    return arguments


def main() -> int:
    try:
        arguments = parse_arguments()
        return self_test() if arguments.self_test else run(arguments)
    except T12ClassificationError as error:
        print(f"t12_extended_mrr_classifier=blocked;reason={error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("t12_extended_mrr_classifier=blocked;reason=interrupted", file=sys.stderr)
        return 130
    except Exception as error:
        print(
            f"t12_extended_mrr_classifier=blocked;reason=bounded_{type(error).__name__}",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
