#!/usr/bin/env python3
"""Review rank failures in the accepted published corpus-v2 lane capture."""

from __future__ import annotations

import argparse
import hashlib
import json
from fractions import Fraction
from pathlib import Path
from typing import Any


class RankReviewError(RuntimeError):
    """Stable failure at the content-free rank-review boundary."""


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise RankReviewError(reason)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_json(path: Path) -> dict[str, Any]:
    require(path.is_file() and not path.is_symlink(), "json_input_unsafe")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise RankReviewError("json_input_invalid") from error
    require(isinstance(value, dict), "json_input_invalid")
    return value


def write_json(path: Path, value: dict[str, Any]) -> None:
    require(not path.exists() and not path.is_symlink(), "output_exists")
    path.write_text(
        json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def evidence_matches(item: dict[str, Any], evidence: dict[str, Any]) -> bool:
    return (
        item.get("document_ref") == evidence.get("document_ref")
        and int(item.get("page_start", 0)) <= int(evidence.get("page", -1))
        <= int(item.get("page_end", 0))
    )


def is_relevant(item: dict[str, Any], evidence: list[dict[str, Any]]) -> bool:
    return any(evidence_matches(item, target) for target in evidence)


def first_relevant_rank(
    items: list[dict[str, Any]], evidence: list[dict[str, Any]]
) -> int | None:
    for rank, item in enumerate(items, start=1):
        if is_relevant(item, evidence):
            return rank
    return None


def rank_distribution(ranks: list[int]) -> dict[str, int]:
    result: dict[str, int] = {}
    for rank in sorted(set(ranks)):
        result[str(rank)] = ranks.count(rank)
    return result


def minimum_rank_one_promotions(ranks: list[int], target: Fraction) -> int:
    current_sum = sum((Fraction(1, rank) for rank in ranks), Fraction(0, 1))
    gains = sorted((Fraction(1, 1) - Fraction(1, rank) for rank in ranks), reverse=True)
    for count in range(len(gains) + 1):
        if current_sum + sum(gains[:count], Fraction(0, 1)) > target * len(ranks):
            return count
    raise RankReviewError("strict_target_unreachable")


def review_case(case: dict[str, Any], best: dict[str, Any]) -> dict[str, Any]:
    evidence = case["matched_evidence"]
    current_rank = int(case["first_relevant_rank"])
    blockers = case["fused"][: current_rank - 1]
    target_documents = {item["document_ref"] for item in evidence}
    same_document_wrong_page = sum(
        item["document_ref"] in target_documents for item in blockers
    )
    other_document = len(blockers) - same_document_wrong_page
    if same_document_wrong_page and other_document:
        blocker_shape = "mixed"
    elif same_document_wrong_page:
        blocker_shape = "same_document_wrong_page"
    else:
        blocker_shape = "other_document"
    improved = set(best["improved_body_case_ids"])
    regressed = set(best["regressed_body_case_ids"])
    case_id = case["case_id"]
    effect = (
        "improved"
        if case_id in improved
        else "regressed"
        if case_id in regressed
        else "unchanged"
    )
    lane_ranks = {
        lane: first_relevant_rank(case["lanes"][lane], evidence)
        for lane in ("exact", "lexical", "vector")
    }
    lexical_rank = lane_ranks["lexical"]
    vector_rank = lane_ranks["vector"]
    if lexical_rank is None and vector_rank is None:
        lane_leader = "neither"
    elif lexical_rank is None:
        lane_leader = "vector"
    elif vector_rank is None:
        lane_leader = "lexical"
    elif lexical_rank < vector_rank:
        lane_leader = "lexical"
    elif vector_rank < lexical_rank:
        lane_leader = "vector"
    else:
        lane_leader = "tie"
    return {
        "case_id": case_id,
        "required_evidence": evidence,
        "current_fused_first_relevant_rank": current_rank,
        "lane_first_relevant_rank": lane_ranks,
        "lane_leader": lane_leader,
        "scope": (
            "single_document"
            if len(case["permitted_document_refs"]) == 1
            else "corpus_wide"
        ),
        "blockers_before_first_relevant": {
            "count": len(blockers),
            "same_document_wrong_page": same_document_wrong_page,
            "other_document": other_document,
            "shape": blocker_shape,
            "distinct_document_count": len(
                {item["document_ref"] for item in blockers}
            ),
        },
        "best_profile_effect": effect,
    }


def build_review(
    observation_path: Path, optimization_path: Path
) -> dict[str, Any]:
    observation = load_json(observation_path)
    optimization = load_json(optimization_path)
    require(
        observation.get("artifact_kind")
        == "ishikawa_live_synthetic_corpus_v2_retrieval_observation"
        and observation.get("schema_version") == 1
        and observation.get("database_boundary")
        == "isolated_postgresql_repeatable_read_read_only"
        and observation.get("database_write") is False
        and observation.get("gemma_contact") is False,
        "observation_contract_invalid",
    )
    require(
        optimization.get("artifact_kind")
        == "ishikawa_live_synthetic_corpus_v2_optimization_search"
        and optimization.get("schema_version") == 1
        and optimization.get("strict_gate_profile_count") == 0
        and optimization.get("boundaries", {}).get("database_contact") is False
        and optimization.get("boundaries", {}).get("model_contact") is False
        and optimization.get("boundaries", {}).get("production_profile_changed")
        is False,
        "optimization_contract_invalid",
    )
    cases = observation.get("cases")
    require(isinstance(cases, list) and len(cases) == 68, "case_inventory_invalid")
    body_cases = [case for case in cases if case.get("family") == "body"]
    header_cases = [case for case in cases if case.get("family") != "body"]
    require(len(body_cases) == 60 and len(header_cases) == 8, "case_family_invalid")
    require(
        observation.get("body_metrics", {}).get("mrr_at_20") == "0.873056"
        and observation.get("body_metrics", {}).get("relevant_at_5") == 58
        and observation.get("body_metrics", {}).get("relevant_at_20") == 60
        and observation.get("header_metrics", {}).get("mrr_at_20") == "1.000000"
        and observation.get("header_metrics", {}).get("relevant_at_5") == 8
        and observation.get("header_metrics", {}).get(
            "required_evidence_matched_at_20"
        )
        == 11,
        "accepted_live_metrics_changed",
    )
    current = optimization["current_profile_replay"]
    best = optimization["best_profile"]
    require(
        current["body_metrics"]["mrr_at_20"] == "0.873056"
        and current["header_metrics"]["mrr_at_20"] == "1.000000"
        and best["body_metrics"]["mrr_at_20"] == "0.882103"
        and best["body_metrics"]["relevant_at_5"] == 59
        and best["body_metrics"]["relevant_at_20"] == 60
        and best["header_metrics"]["mrr_at_20"] == "1.000000"
        and best["improved_body_case_ids"] == ["E-015", "E-026", "E-033"]
        and best["regressed_body_case_ids"] == ["E-024", "E-032"],
        "accepted_optimization_result_changed",
    )
    observed_ranks = {
        case["case_id"]: int(case["first_relevant_rank"]) for case in body_cases
    }
    replay_ranks = {
        case_id: rank
        for case_id, rank in current["case_ranks"].items()
        if case_id.startswith("E-")
    }
    require(observed_ranks == replay_ranks, "baseline_rank_replay_changed")

    below_rank_one = [case for case in body_cases if case["first_relevant_rank"] > 1]
    records = [review_case(case, best) for case in below_rank_one]
    ranks = [int(case["first_relevant_rank"]) for case in body_cases]
    blocker_shapes = {
        shape: sum(
            record["blockers_before_first_relevant"]["shape"] == shape
            for record in records
        )
        for shape in ("same_document_wrong_page", "other_document", "mixed")
    }
    lane_leaders = {
        leader: sum(record["lane_leader"] == leader for record in records)
        for leader in ("lexical", "vector", "tie", "neither")
    }
    same_page_pressure = sum(
        record["blockers_before_first_relevant"]["same_document_wrong_page"] > 0
        for record in records
    )
    cross_document_pressure = sum(
        record["blockers_before_first_relevant"]["other_document"] > 0
        for record in records
    )
    strict_target = Fraction(91, 100)
    return {
        "artifact_kind": "ishikawa_published_synthetic_corpus_v2_atomic_rank_failure_review",
        "schema_version": 1,
        "source_sha256": {
            "live_observation": sha256_file(observation_path),
            "bounded_optimization": sha256_file(optimization_path),
        },
        "accepted_baseline": {
            "body_mrr_at_20": "0.873056",
            "body_relevant_at_5": 58,
            "body_relevant_at_20": 60,
            "header_mrr_at_20": "1.000000",
            "header_relevant_at_5": 8,
            "header_required_evidence_at_20": "11/11",
            "rank_distribution": rank_distribution(ranks),
            "rank_one_cases": ranks.count(1),
            "below_rank_one_cases": len(records),
            "outside_top_five_case_ids": [
                case["case_id"] for case in body_cases if case["first_relevant_rank"] > 5
            ],
        },
        "bounded_search": {
            "profiles_evaluated": optimization["search_space"]["profile_count"],
            "strict_gate_profiles": optimization["strict_gate_profile_count"],
            "best_body_mrr_at_20": best["body_metrics"]["mrr_at_20"],
            "best_body_relevant_at_5": best["body_metrics"]["relevant_at_5"],
            "best_body_relevant_at_20": best["body_metrics"]["relevant_at_20"],
            "best_profile": best["profile"],
            "improved_body_case_ids": best["improved_body_case_ids"],
            "regressed_body_case_ids": best["regressed_body_case_ids"],
            "promotion_authorized": False,
        },
        "rank_failure_summary": {
            "case_count": len(records),
            "blocker_shapes": blocker_shapes,
            "cases_with_same_document_wrong_page_pressure": same_page_pressure,
            "cases_with_cross_document_pressure": cross_document_pressure,
            "lane_leaders": lane_leaders,
            "exact_lane_relevant_cases": sum(
                record["lane_first_relevant_rank"]["exact"] is not None
                for record in records
            ),
            "single_document_scope_cases": sum(
                record["scope"] == "single_document" for record in records
            ),
            "corpus_wide_scope_cases": sum(
                record["scope"] == "corpus_wide" for record in records
            ),
            "minimum_current_rank_one_promotions_to_exceed_strict_target": (
                minimum_rank_one_promotions(ranks, strict_target)
            ),
            "strict_target": ">0.91",
        },
        "rank_failures": records,
        "conclusions": {
            "weight_depth_rrf_search_exhausted": True,
            "header_metadata_path_is_not_current_limiting_factor": True,
            "current_profile_remains_frozen": True,
            "published_corpus_changed": False,
            "truth_changed": False,
            "candidate_representation_changed": False,
            "new_retrieval_candidate_authorized": False,
            "dominant_observed_pressures": [
                "same_document_wrong_page_competition",
                "cross_document_competition",
                "lexical_vector_rank_disagreement",
            ],
        },
        "boundaries": {
            "content_free_output": True,
            "question_text_retained": False,
            "source_text_retained": False,
            "database_contact": False,
            "model_contact": False,
            "credential_read": False,
            "black_corpus_access": False,
            "corpus_changed": False,
            "truth_changed": False,
            "service_changed": False,
            "package_changed": False,
            "production_profile_changed": False,
        },
        "next_gate": (
            "design_bounded_section_page_aware_candidate_experiment_"
            "without_profile_or_corpus_promotion"
        ),
    }


def self_test() -> int:
    evidence = [{"document_ref": "D1", "page": 2}]
    items = [
        {"document_ref": "D1", "page_start": 1, "page_end": 1},
        {"document_ref": "D2", "page_start": 2, "page_end": 2},
        {"document_ref": "D1", "page_start": 2, "page_end": 3},
    ]
    require(first_relevant_rank(items, evidence) == 3, "self_test_failed")
    require(
        minimum_rank_one_promotions([1, 2, 5, 10], Fraction(3, 4)) == 2,
        "self_test_failed",
    )
    print("published_v2_atomic_rank_failure_review_self_test=pass")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--observation")
    parser.add_argument("--optimization")
    parser.add_argument("--output")
    arguments = parser.parse_args()
    if arguments.self_test:
        return self_test()
    require(
        all((arguments.observation, arguments.optimization, arguments.output)),
        "arguments_missing",
    )
    result = build_review(
        Path(arguments.observation).resolve(strict=True),
        Path(arguments.optimization).resolve(strict=True),
    )
    write_json(Path(arguments.output), result)
    print("published_v2_atomic_rank_failure_review=pass")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RankReviewError as error:
        print(f"published_v2_atomic_rank_failure_review=blocked;reason={error}")
        raise SystemExit(1) from error
