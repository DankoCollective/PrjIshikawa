#!/usr/bin/env python3
"""Review the content-free V13-45 hierarchical-ranking observation."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from collections import Counter
from decimal import Decimal
from pathlib import Path
from typing import Any, Mapping, Sequence


class ReviewError(RuntimeError):
    """Raised when the bound observation does not satisfy the review contract."""


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise ReviewError(reason)


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")


def load_bound(path: Path, expected_sha256: str) -> Mapping[str, Any]:
    require(path.is_file() and not path.is_symlink(), "observation_unsafe")
    payload = path.read_bytes()
    require(len(payload) <= 128 * 1024 * 1024, "observation_too_large")
    require(hashlib.sha256(payload).hexdigest() == expected_sha256,
            "observation_identity_changed")
    value = json.loads(payload)
    require(isinstance(value, dict), "observation_not_mapping")
    return value


def integer_counts(values: Sequence[int]) -> dict[str, int]:
    counts = Counter(values)
    return {str(key): counts[key] for key in sorted(counts)}


def selection_map(variant: Mapping[str, Any]) -> dict[str, Mapping[str, Any]]:
    rows = variant["results"]["selection"]
    require(isinstance(rows, list) and len(rows) == 180,
            "selection_inventory_invalid")
    result = {
        row["case_id"]: row for row in rows if row.get("family") == "body"
    }
    require(len(result) == 120, "body_selection_inventory_invalid")
    return result


def review(observation: Mapping[str, Any]) -> dict[str, Any]:
    require(
        observation.get("artifact_kind")
        == "ishikawa_v13_45_hierarchical_document_section_experiment"
        and observation.get("schema_version") == 1
        and observation.get("corpus_identity") == "synthetic-corpus-v3",
        "observation_contract_invalid",
    )
    require(
        observation.get("selection_status") == "not_met"
        and observation.get("selected_candidate") is None
        and observation.get("qualified_candidates") == []
        and observation.get("promotion_authorized") is False,
        "observation_result_invalid",
    )
    variants = observation["variants"]
    declared = observation["experiment"]["variant_order"]
    require(
        isinstance(declared, list)
        and len(declared) == 5
        and set(variants) == {"accepted_v6", *declared},
        "variant_inventory_invalid",
    )
    selections = {name: selection_map(variants[name]) for name in variants}
    case_ids = sorted(selections["accepted_v6"])
    require(
        all(sorted(items) == case_ids for items in selections.values()),
        "case_alignment_invalid",
    )

    targets: dict[str, tuple[str, int]] = {}
    for case_id in case_ids:
        evidence = {
            (item["document_ref"], item["page"])
            for name in variants
            for item in selections[name][case_id]["matched_evidence"]
        }
        require(len(evidence) == 1, "required_evidence_identity_unrecoverable")
        targets[case_id] = next(iter(evidence))

    baseline = selections["accepted_v6"]
    summaries: dict[str, Any] = {}
    for name in declared:
        counts: Counter[str] = Counter()
        final_ranks: list[int] = []
        document_ranks: list[int] = []
        section_positions: list[int] = []
        missing_case_ids: list[str] = []
        document_not_shortlisted_case_ids: list[str] = []
        section_not_emitted_case_ids: list[str] = []
        for case_id in case_ids:
            row = selections[name][case_id]
            base_row = baseline[case_id]
            document_ref, _ = targets[case_id]
            hierarchy = row["hierarchy"]
            require(isinstance(hierarchy, dict), "body_hierarchy_missing")
            shortlist = hierarchy["document_shortlist"]
            document_rank = {
                item["document_ref"]: item["rank"]
                for item in hierarchy["document_ranking"]
            }.get(document_ref)
            rank = row["first_relevant_rank"]
            if document_ref not in shortlist:
                counts["document_not_shortlisted"] += 1
                document_not_shortlisted_case_ids.append(case_id)
            elif rank is None:
                counts["section_not_emitted_within_top_20"] += 1
                section_not_emitted_case_ids.append(case_id)
            else:
                require(isinstance(rank, int) and 1 <= rank <= 20,
                        "relevant_rank_invalid")
                require(isinstance(document_rank, int) and document_rank >= 1,
                        "relevant_document_rank_invalid")
                counts["retrieved"] += 1
                final_ranks.append(rank)
                document_ranks.append(document_rank)
                position = sum(
                    item["document_ref"] == document_ref
                    for item in row["fused"][:rank]
                )
                require(position >= 1, "section_position_invalid")
                section_positions.append(position)
                if rank <= 5:
                    counts["relevant_within_top_5"] += 1
                if rank >= 9:
                    counts["relevant_at_rank_9_or_later"] += 1
                if document_rank == 1 and rank > 5:
                    counts["document_rank_1_but_section_after_rank_5"] += 1
            if rank is None:
                counts["missing"] += 1
                missing_case_ids.append(case_id)
            baseline_rank = base_row["first_relevant_rank"]
            if baseline_rank is None and rank is not None:
                counts["baseline_missing_fixed"] += 1
            if baseline_rank is not None and rank is None:
                counts["new_missing"] += 1
            baseline_value = 21 if baseline_rank is None else baseline_rank
            candidate_value = 21 if rank is None else rank
            if candidate_value < baseline_value:
                counts["improved"] += 1
            elif candidate_value > baseline_value:
                counts["regressed"] += 1
            else:
                counts["unchanged"] += 1
        body = variants[name]["metrics"]["body"]
        movement = variants[name]["rank_movement"]
        require(
            movement == {
                "improved": counts["improved"],
                "unchanged": counts["unchanged"],
                "regressed": counts["regressed"],
                "missing_fixed": counts["baseline_missing_fixed"],
                "new_missing": counts["new_missing"],
            },
            "rank_movement_disagrees",
        )
        summaries[name] = {
            "body_mrr_at_20": body["mrr_at_20"],
            "body_relevant_at_5": body["relevant_at_5"],
            "body_relevant_at_20": body["relevant_at_20"],
            "rank_movement": movement,
            "classification": dict(sorted(counts.items())),
            "final_relevant_rank_distribution": integer_counts(final_ranks),
            "relevant_document_rank_distribution": integer_counts(document_ranks),
            "relevant_section_position_within_document": integer_counts(
                section_positions
            ),
            "missing_case_ids": missing_case_ids,
            "document_not_shortlisted_case_ids":
                document_not_shortlisted_case_ids,
            "section_not_emitted_case_ids": section_not_emitted_case_ids,
        }

    baseline_mrr = Decimal(variants["accepted_v6"]["metrics"]["body"]["mrr_at_20"])
    best_name = max(
        declared,
        key=lambda name: Decimal(variants[name]["metrics"]["body"]["mrr_at_20"]),
    )
    best = summaries[best_name]
    require(
        all(Decimal(summaries[name]["body_mrr_at_20"]) < baseline_mrr
            for name in declared),
        "candidate_not_uniformly_below_baseline",
    )
    require(
        best["classification"]["document_rank_1_but_section_after_rank_5"] >= 25
        and int(best["relevant_section_position_within_document"].get("2", 0)) >= 30,
        "round_robin_failure_signature_absent",
    )
    return {
        "artifact_kind": "ishikawa_v13_45_hierarchical_failure_review",
        "schema_version": 1,
        "corpus_identity": "synthetic-corpus-v3",
        "baseline": {
            "variant": "accepted_v6",
            "body_mrr_at_20": variants["accepted_v6"]["metrics"]["body"]["mrr_at_20"],
            "body_relevant_at_5": variants["accepted_v6"]["metrics"]["body"]["relevant_at_5"],
            "body_relevant_at_20": variants["accepted_v6"]["metrics"]["body"]["relevant_at_20"],
        },
        "best_v13_45_variant": best_name,
        "variant_summaries": summaries,
        "findings": {
            "all_candidates_below_baseline": True,
            "strict_round_robin_is_primary_regression_source": True,
            "best_variant_relevant_section_second_within_document":
                int(best["relevant_section_position_within_document"].get("2", 0)),
            "best_variant_relevant_section_third_within_document":
                int(best["relevant_section_position_within_document"].get("3", 0)),
            "best_variant_document_rank_1_but_section_after_rank_5":
                best["classification"]["document_rank_1_but_section_after_rank_5"],
            "best_variant_relevant_at_rank_9_or_later":
                best["classification"]["relevant_at_rank_9_or_later"],
            "best_variant_missing_because_document_not_shortlisted":
                best["classification"].get("document_not_shortlisted", 0),
            "best_variant_missing_because_section_not_emitted_top_20":
                best["classification"].get("section_not_emitted_within_top_20", 0),
        },
        "recommendation": {
            "reject_v13_45_candidates": True,
            "preserve_v13_45_observation": True,
            "patch_authorized": False,
            "reason": "measured_frozen_topology_failed_not_an_execution_defect",
            "next_change_requires_separate_freeze": True,
            "next_boundary": "candidate_generation_and_cross_document_section_ordering",
        },
        "boundaries": {
            "accepted_database_contact": False,
            "black_corpus_access": False,
            "corpus_changed": False,
            "model_contact": False,
            "production_profile_changed": False,
            "question_text_retained": False,
            "source_text_retained": False,
            "vectors_retained": False,
        },
    }


def write_exclusive(path: Path, payload: bytes) -> None:
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)


def self_test() -> None:
    assert integer_counts([9, 1, 9, 2]) == {"1": 1, "2": 1, "9": 2}
    assert canonical_bytes({"b": 2, "a": 1}) == b'{"a":1,"b":2}'


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--observation", type=Path)
    parser.add_argument("--expected-sha256")
    parser.add_argument("--source-report-sha256")
    parser.add_argument("--output", type=Path)
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
        print("v13_45_hierarchical_failure_review_self_test=pass")
        return 0
    require(
        arguments.observation is not None
        and arguments.expected_sha256 is not None
        and arguments.source_report_sha256 is not None
        and arguments.output is not None,
        "required_argument_missing",
    )
    observation = load_bound(arguments.observation, arguments.expected_sha256)
    result = review(observation)
    result["source_observation_sha256"] = arguments.expected_sha256
    result["source_report_sha256"] = arguments.source_report_sha256
    result["review_id"] = hashlib.sha256(
        b"ishikawa.v13-45-hierarchical-failure-review.v1\0"
        + canonical_bytes(result)
    ).hexdigest()
    write_exclusive(arguments.output, canonical_bytes(result) + b"\n")
    print("v13_45_hierarchical_failure_review=pass")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ReviewError, json.JSONDecodeError, KeyError, TypeError, ValueError) as error:
        print(f"v13_45_hierarchical_failure_review=blocked;reason={error}", file=sys.stderr)
        raise SystemExit(1)
