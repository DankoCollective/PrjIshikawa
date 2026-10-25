#!/usr/bin/env python3
"""Search bounded corpus-v2 fusion/diversification profiles from cached lanes."""

from __future__ import annotations

import argparse
import hashlib
import json
from fractions import Fraction
from pathlib import Path
from typing import Any, Iterable


RRF_CONSTANTS = (10, 20, 40, 60, 80, 100)
LEXICAL_WEIGHTS = (1, 2, 3, 4, 5, 6, 8)
VECTOR_WEIGHTS = (1, 2, 3, 4, 5, 6, 8)
LANE_DEPTHS = (10, 15, 20)
DIVERSIFICATION_MODES = (
    "none",
    "source_unit_overlap_first",
    "document_page_cap_2",
    "document_page_cap_1",
)
CURRENT_PROFILE = {
    "rrf_constant": 60,
    "exact_weight": 1,
    "lexical_weight": 1,
    "vector_weight": 4,
    "lexical_depth": 20,
    "vector_depth": 20,
    "diversification": "none",
}


def _load(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise SystemExit(f"json_root_not_object:{path}")
    return value


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _write_json(path: Path, value: dict[str, Any]) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _candidate_inventory(candidate: dict[str, Any]) -> dict[str, dict[str, Any]]:
    inventory: dict[str, dict[str, Any]] = {}
    for document in candidate["documents"]:
        document_ref = document["document_ref"]
        for item in document["candidates"]:
            chunk_id = item["chunk_id"]
            if chunk_id in inventory:
                raise SystemExit(f"duplicate_chunk_id:{chunk_id}")
            anchor = item["citation_anchor"]
            source_unit_ids = item.get("source_unit_ids")
            if not isinstance(source_unit_ids, list) or not source_unit_ids:
                source_unit_id = anchor.get("source_unit_id")
                source_unit_ids = [source_unit_id] if isinstance(source_unit_id, str) else []
            inventory[chunk_id] = {
                "chunk_id": chunk_id,
                "document_ref": document_ref,
                "page_start": int(anchor["page_start"]),
                "page_end": int(anchor["page_end"]),
                "projection_kind": item["projection_kind"],
                "source_unit_ids": tuple(source_unit_ids),
                "content_digest": item["content_digest"],
            }
    return inventory


def _fuse(case: dict[str, Any], profile: dict[str, Any]) -> list[str]:
    weights = {
        "exact": profile["exact_weight"],
        "lexical": profile["lexical_weight"],
        "vector": profile["vector_weight"],
    }
    depths = {
        "exact": 1,
        "lexical": profile["lexical_depth"],
        "vector": profile["vector_depth"],
    }
    accumulated: dict[str, dict[str, Any]] = {}
    for lane in ("exact", "lexical", "vector"):
        for item in case["lanes"][lane][: depths[lane]]:
            chunk_id = item["chunk_id"]
            state = accumulated.setdefault(
                chunk_id,
                {"score": Fraction(0, 1), "exact": False, "ranks": []},
            )
            rank = int(item["rank"])
            state["score"] += Fraction(weights[lane], profile["rrf_constant"] + rank)
            state["ranks"].append(rank)
            state["exact"] = state["exact"] or lane == "exact"
    return sorted(
        accumulated,
        key=lambda chunk_id: (
            -int(accumulated[chunk_id]["exact"]),
            -accumulated[chunk_id]["score"],
            min(accumulated[chunk_id]["ranks"]),
            chunk_id,
        ),
    )


def _diversify(
    chunk_ids: Iterable[str],
    inventory: dict[str, dict[str, Any]],
    mode: str,
) -> list[str]:
    if mode == "none":
        return list(chunk_ids)
    result: list[str] = []
    if mode == "source_unit_overlap_first":
        seen_units: set[str] = set()
        for chunk_id in chunk_ids:
            source_units = set(inventory[chunk_id]["source_unit_ids"])
            if source_units and source_units & seen_units:
                continue
            result.append(chunk_id)
            seen_units.update(source_units)
        return result
    cap = 2 if mode == "document_page_cap_2" else 1
    counts: dict[tuple[str, int, int], int] = {}
    for chunk_id in chunk_ids:
        item = inventory[chunk_id]
        key = (item["document_ref"], item["page_start"], item["page_end"])
        count = counts.get(key, 0)
        if count >= cap:
            continue
        counts[key] = count + 1
        result.append(chunk_id)
    return result


def _matches(item: dict[str, Any], expected: tuple[str, int]) -> bool:
    return (
        item["document_ref"] == expected[0]
        and item["page_start"] <= expected[1] <= item["page_end"]
    )


def _case_metrics(
    case: dict[str, Any],
    chunk_ids: list[str],
    inventory: dict[str, dict[str, Any]],
    equivalence_digest: str | None = None,
) -> dict[str, Any]:
    expected = tuple(
        (item["document_ref"], int(item["page"])) for item in case["matched_evidence"]
    )
    top_twenty = chunk_ids[:20]
    first_rank: int | None = None
    matched: set[tuple[str, int]] = set()
    for rank, chunk_id in enumerate(top_twenty, start=1):
        item = inventory[chunk_id]
        item_matches = [pair for pair in expected if _matches(item, pair)]
        if equivalence_digest is not None and item["content_digest"] == equivalence_digest:
            item_matches = list(expected)
        if item_matches and first_rank is None:
            first_rank = rank
        matched.update(item_matches)
    return {
        "first_relevant_rank": first_rank,
        "relevant_within_top_five": first_rank is not None and first_rank <= 5,
        "relevant_within_top_twenty": first_rank is not None,
        "matched_evidence_count": len(matched),
        "required_evidence_count": len(expected),
    }


def _aggregate(results: list[dict[str, Any]]) -> dict[str, Any]:
    reciprocal = sum(
        Fraction(1, result["first_relevant_rank"])
        for result in results
        if result["first_relevant_rank"] is not None
        and result["first_relevant_rank"] <= 20
    )
    count = len(results)
    return {
        "mrr_at_20": f"{float(reciprocal / count):.6f}",
        "mrr_fraction_numerator": (reciprocal / count).numerator,
        "mrr_fraction_denominator": (reciprocal / count).denominator,
        "relevant_at_5": sum(result["relevant_within_top_five"] for result in results),
        "relevant_at_20": sum(result["relevant_within_top_twenty"] for result in results),
        "required_evidence_matched_at_20": sum(
            result["matched_evidence_count"] for result in results
        ),
        "required_evidence_total": sum(
            result["required_evidence_count"] for result in results
        ),
    }


def _profile_distance(profile: dict[str, Any]) -> int:
    return (
        abs(profile["rrf_constant"] - CURRENT_PROFILE["rrf_constant"]) // 10
        + abs(profile["lexical_weight"] - CURRENT_PROFILE["lexical_weight"])
        + abs(profile["vector_weight"] - CURRENT_PROFILE["vector_weight"])
        + abs(profile["lexical_depth"] - CURRENT_PROFILE["lexical_depth"]) // 5
        + abs(profile["vector_depth"] - CURRENT_PROFILE["vector_depth"]) // 5
        + (0 if profile["diversification"] == "none" else 10)
    )


def _evaluate_profile(
    cases: list[dict[str, Any]],
    inventory: dict[str, dict[str, Any]],
    profile: dict[str, Any],
    baseline_ranks: dict[str, int],
    e032_digest: str,
) -> dict[str, Any]:
    body_results: list[dict[str, Any]] = []
    body_equivalence_results: list[dict[str, Any]] = []
    header_results: list[dict[str, Any]] = []
    case_ranks: dict[str, int | None] = {}
    for case in cases:
        fused = _fuse(case, profile)
        diversified = _diversify(fused, inventory, profile["diversification"])
        strict = _case_metrics(case, diversified, inventory)
        case_ranks[case["case_id"]] = strict["first_relevant_rank"]
        if case["family"] == "body":
            body_results.append(strict)
            body_equivalence_results.append(
                _case_metrics(
                    case,
                    diversified,
                    inventory,
                    e032_digest if case["case_id"] == "E-032" else None,
                )
            )
        else:
            header_results.append(strict)
    body = _aggregate(body_results)
    body_equivalence = _aggregate(body_equivalence_results)
    header = _aggregate(header_results)
    regressed = [
        case_id
        for case_id, rank in case_ranks.items()
        if case_id.startswith("E-")
        and (rank is None or rank > baseline_ranks[case_id])
    ]
    improved = [
        case_id
        for case_id, rank in case_ranks.items()
        if case_id.startswith("E-")
        and rank is not None
        and rank < baseline_ranks[case_id]
    ]
    eligible = (
        Fraction(body["mrr_fraction_numerator"], body["mrr_fraction_denominator"])
        > Fraction(91, 100)
        and body["relevant_at_20"] == 60
        and header["relevant_at_5"] == 8
        and header["required_evidence_matched_at_20"]
        == header["required_evidence_total"]
    )
    return {
        "profile": profile,
        "body_metrics": body,
        "body_equivalence_diagnostic": body_equivalence,
        "header_metrics": header,
        "strict_gate_met": eligible,
        "regressed_body_case_ids": regressed,
        "improved_body_case_ids": improved,
        "profile_distance_from_current": _profile_distance(profile),
        "case_ranks": case_ranks,
    }


def _sort_key(result: dict[str, Any]) -> tuple[Any, ...]:
    metrics = result["body_metrics"]
    fraction = Fraction(
        metrics["mrr_fraction_numerator"], metrics["mrr_fraction_denominator"]
    )
    return (
        -int(result["strict_gate_met"]),
        -fraction,
        -metrics["relevant_at_5"],
        len(result["regressed_body_case_ids"]),
        result["profile_distance_from_current"],
        json.dumps(result["profile"], sort_keys=True),
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--observation", required=True)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--rank-review", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    observation_path = Path(args.observation).resolve()
    candidate_path = Path(args.candidate).resolve()
    review_path = Path(args.rank_review).resolve()
    output_path = Path(args.output).resolve()
    for path in (observation_path, candidate_path, review_path):
        if not path.is_file() or path.is_symlink():
            raise SystemExit(f"input_missing_or_unsafe:{path}")
    if output_path.exists() or output_path.is_symlink():
        raise SystemExit("output_already_exists")

    observation = _load(observation_path)
    candidate = _load(candidate_path)
    review = _load(review_path)
    if observation["body_metrics"]["mrr_at_20"] != "0.870992":
        raise SystemExit("observation_identity_invalid")
    if observation["body_metrics"]["required_evidence_matched_at_20"] != 60:
        raise SystemExit("body_expected_evidence_incomplete")
    if observation["header_metrics"]["required_evidence_matched_at_20"] != 11:
        raise SystemExit("header_expected_evidence_incomplete")
    if review["promotion_authorized"] is not False:
        raise SystemExit("rank_review_boundary_invalid")
    if candidate["publication_eligible"] is not False:
        raise SystemExit("candidate_unexpectedly_publishable")

    inventory = _candidate_inventory(candidate)
    cases = list(observation["cases"])
    if len(inventory) != 163 or len(cases) != 68:
        raise SystemExit("input_inventory_changed")
    baseline_ranks = {
        case["case_id"]: int(case["first_relevant_rank"])
        for case in cases
        if case["family"] == "body"
    }
    e032 = next(case for case in cases if case["case_id"] == "E-032")
    e032_chunk = e032["fused"][int(e032["first_relevant_rank"]) - 1]["chunk_id"]
    e032_digest = inventory[e032_chunk]["content_digest"]

    results: list[dict[str, Any]] = []
    for rrf_constant in RRF_CONSTANTS:
        for lexical_weight in LEXICAL_WEIGHTS:
            for vector_weight in VECTOR_WEIGHTS:
                for lexical_depth in LANE_DEPTHS:
                    for vector_depth in LANE_DEPTHS:
                        for diversification in DIVERSIFICATION_MODES:
                            profile = {
                                "rrf_constant": rrf_constant,
                                "exact_weight": 1,
                                "lexical_weight": lexical_weight,
                                "vector_weight": vector_weight,
                                "lexical_depth": lexical_depth,
                                "vector_depth": vector_depth,
                                "diversification": diversification,
                            }
                            results.append(
                                _evaluate_profile(
                                    cases,
                                    inventory,
                                    profile,
                                    baseline_ranks,
                                    e032_digest,
                                )
                            )
    results.sort(key=_sort_key)
    current = next(result for result in results if result["profile"] == CURRENT_PROFILE)
    if current["body_metrics"]["mrr_at_20"] != "0.870992":
        raise SystemExit("cached_lane_replay_drift")
    strict_gate_count = sum(result["strict_gate_met"] for result in results)
    finalists = results[:25]
    for result in finalists:
        result.pop("case_ranks")
    output = {
        "schema_version": 1,
        "artifact_kind": "ishikawa_synthetic_corpus_v2_optimization_search",
        "source_sha256": {
            "observation": _sha256(observation_path),
            "candidate": _sha256(candidate_path),
            "rank_review": _sha256(review_path),
        },
        "search_space": {
            "rrf_constants": list(RRF_CONSTANTS),
            "lexical_weights": list(LEXICAL_WEIGHTS),
            "vector_weights": list(VECTOR_WEIGHTS),
            "lexical_depths": list(LANE_DEPTHS),
            "vector_depths": list(LANE_DEPTHS),
            "diversification_modes": list(DIVERSIFICATION_MODES),
            "profile_count": len(results),
            "cached_lane_depth_limit": 20,
        },
        "selection_rules": {
            "profile_selection_uses_strict_document_page_truth": True,
            "e032_content_equivalence_is_diagnostic_only": True,
            "strict_body_mrr_target": "greater_than_0.91",
            "strict_body_relevant_at_20": 60,
            "header_relevant_at_5": 8,
            "header_required_evidence_at_20": 11,
            "retrieval_profile_promotion_from_offline_search": False,
        },
        "current_profile_replay": current,
        "strict_gate_profile_count": strict_gate_count,
        "finalists": finalists,
        "best_profile": finalists[0],
        "boundaries": {
            "cached_lane_replay_only": True,
            "database_contact": False,
            "model_contact": False,
            "credential_read": False,
            "black_corpus_access": False,
            "truth_changed": False,
            "retrieval_source_changed": False,
            "production_profile_changed": False,
            "retrieval_profile_promotion_authorized": False,
            "corpus_v2_promotion_blocked_by_optimization": False,
        },
        "primary_next_gate": "continue_synthetic_corpus_v2_promotion",
        "optional_optimization_next_step": (
            "review_optimization_finalists_then_live_remeasure_selected_profiles_with_latency"
        ),
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    _write_json(output_path, output)
    best = output["best_profile"]
    print(f"profiles_evaluated={len(results)};strict_gate_profiles={strict_gate_count}")
    print(
        f"current_body_mrr_at_20={current['body_metrics']['mrr_at_20']};"
        f"current_body_relevant_at_5={current['body_metrics']['relevant_at_5']}/60"
    )
    print("best_profile=" + json.dumps(best["profile"], sort_keys=True, separators=(",", ":")))
    print(
        f"best_strict_body_mrr_at_20={best['body_metrics']['mrr_at_20']};"
        f"best_body_relevant_at_5={best['body_metrics']['relevant_at_5']}/60;"
        f"best_body_relevant_at_20={best['body_metrics']['relevant_at_20']}/60"
    )
    print(
        f"best_equivalence_diagnostic_mrr_at_20="
        f"{best['body_equivalence_diagnostic']['mrr_at_20']};"
        f"best_regressed_body_cases={len(best['regressed_body_case_ids'])}"
    )
    print("retrieval_profile_promotion_authorized=false")
    print("corpus_v2_promotion_blocked_by_optimization=false")
    print(f"optimization_artifact_sha256={_sha256(output_path)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
