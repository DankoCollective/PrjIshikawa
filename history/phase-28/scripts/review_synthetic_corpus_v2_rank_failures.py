#!/usr/bin/env python3
"""Review retained corpus-v2 retrieval ranks without changing the candidate."""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


def _load(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise SystemExit(f"json_root_not_object:{path}")
    return value


def _write_json(path: Path, value: dict[str, Any]) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _candidate_inventory(candidate: dict[str, Any]) -> dict[str, dict[str, Any]]:
    inventory: dict[str, dict[str, Any]] = {}
    for document in candidate["documents"]:
        document_ref = document["document_ref"]
        for item in document["candidates"]:
            chunk_id = item["chunk_id"]
            if chunk_id in inventory:
                raise SystemExit(f"duplicate_chunk_id:{chunk_id}")
            inventory[chunk_id] = {**item, "document_ref": document_ref}
    return inventory


def _expected_pairs(case: dict[str, Any]) -> set[tuple[str, int]]:
    return {
        (item["document_ref"], int(item["page"]))
        for item in case["matched_evidence"]
    }


def _rank_for_pairs(
    fused: list[dict[str, Any]], expected: set[tuple[str, int]]
) -> int | None:
    for rank, item in enumerate(fused, start=1):
        pages = range(int(item["page_start"]), int(item["page_end"]) + 1)
        if any((item["document_ref"], page) in expected for page in pages):
            return rank
    return None


def _page_diversified(fused: list[dict[str, Any]]) -> list[dict[str, Any]]:
    seen: set[tuple[str, int, int]] = set()
    result: list[dict[str, Any]] = []
    for item in fused:
        key = (item["document_ref"], int(item["page_start"]), int(item["page_end"]))
        if key in seen:
            continue
        seen.add(key)
        result.append(item)
    return result


def _mrr(ranks: list[int | None], depth: int = 20) -> str:
    score = sum(1 / rank for rank in ranks if rank is not None and rank <= depth)
    return f"{score / len(ranks):.6f}"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--observation", required=True)
    parser.add_argument("--baseline-observation", required=True)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--truth", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    observation_path = Path(args.observation).resolve()
    baseline_path = Path(args.baseline_observation).resolve()
    candidate_path = Path(args.candidate).resolve()
    truth_path = Path(args.truth).resolve()
    output_path = Path(args.output).resolve()
    for path in (observation_path, baseline_path, candidate_path, truth_path):
        if not path.is_file() or path.is_symlink():
            raise SystemExit(f"input_missing_or_unsafe:{path}")
    if output_path.exists() or output_path.is_symlink():
        raise SystemExit("output_already_exists")

    observation = _load(observation_path)
    baseline = _load(baseline_path)
    candidate = _load(candidate_path)
    truth = _load(truth_path)
    if observation["artifact_kind"] != "ishikawa_synthetic_corpus_v2_candidate_profile_observation":
        raise SystemExit("observation_kind_invalid")
    if observation["preingestion_measurement_gate"] != "not_met":
        raise SystemExit("observation_gate_not_not_met")
    if observation["body_metrics"]["mrr_at_20"] != "0.870992":
        raise SystemExit("observation_body_mrr_changed")
    if baseline["body_metrics"]["mrr_at_20"] != "0.811825":
        raise SystemExit("baseline_body_mrr_changed")
    if truth.get("evaluation_only") is not True:
        raise SystemExit("truth_not_evaluation_only")
    if truth.get("excluded_from_corpus_ingestion") is not True:
        raise SystemExit("truth_ingestion_boundary_missing")
    if truth.get("excluded_from_generation_context") is not True:
        raise SystemExit("truth_generation_boundary_missing")
    if candidate.get("publication_eligible") is not False:
        raise SystemExit("candidate_unexpectedly_publishable")

    inventory = _candidate_inventory(candidate)
    if len(inventory) != 163:
        raise SystemExit("candidate_count_changed")
    truth_by_id = {item["case_id"]: item for item in truth["cases"]}
    current_by_id = {item["case_id"]: item for item in observation["cases"]}
    baseline_by_id = {item["case_id"]: item for item in baseline["cases"]}
    body_ids = [f"E-{index:03d}" for index in range(1, 61)]
    if not all(
        case_id in truth_by_id and case_id in current_by_id and case_id in baseline_by_id
        for case_id in body_ids
    ):
        raise SystemExit("body_case_inventory_changed")

    rank_distribution = Counter(
        int(current_by_id[case_id]["first_relevant_rank"]) for case_id in body_ids
    )
    improved: list[str] = []
    worsened: list[str] = []
    unchanged: list[str] = []
    review_cases: list[dict[str, Any]] = []
    page_diversified_ranks: list[int | None] = []

    for case_id in body_ids:
        current_case = current_by_id[case_id]
        baseline_case = baseline_by_id[case_id]
        current_rank = int(current_case["first_relevant_rank"])
        baseline_rank_value = baseline_case["first_relevant_rank"]
        baseline_rank = int(baseline_rank_value) if baseline_rank_value is not None else None
        if baseline_rank is None or current_rank < baseline_rank:
            improved.append(case_id)
        elif current_rank > baseline_rank:
            worsened.append(case_id)
        else:
            unchanged.append(case_id)

        expected = _expected_pairs(current_case)
        diversified = _page_diversified(current_case["fused"])
        page_diversified_rank = _rank_for_pairs(diversified, expected)
        page_diversified_ranks.append(page_diversified_rank)
        if current_rank == 1:
            continue

        fused_detail: list[dict[str, Any]] = []
        for fused_item in current_case["fused"][:10]:
            source = inventory[fused_item["chunk_id"]]
            fused_detail.append(
                {
                    "rank": int(fused_item["rank"]),
                    "chunk_id": fused_item["chunk_id"],
                    "document_ref": fused_item["document_ref"],
                    "page_start": int(fused_item["page_start"]),
                    "page_end": int(fused_item["page_end"]),
                    "projection_kind": source["projection_kind"],
                    "parent_unit_id": source.get("parent_unit_id"),
                    "content_digest": source["content_digest"],
                    "content_excerpt": " ".join(source["content_text"].split())[:240],
                }
            )

        first_relevant = current_case["fused"][current_rank - 1]
        first_relevant_candidate = inventory[first_relevant["chunk_id"]]
        equivalent_pages: set[int] = set()
        for item in inventory.values():
            if item["document_ref"] != first_relevant["document_ref"]:
                continue
            if item["content_digest"] != first_relevant_candidate["content_digest"]:
                continue
            anchor = item["citation_anchor"]
            equivalent_pages.update(
                range(int(anchor["page_start"]), int(anchor["page_end"]) + 1)
            )

        parent_page_groups: dict[tuple[str, int, int, str], set[str]] = defaultdict(set)
        for detail in fused_detail[:current_rank]:
            parent = detail["parent_unit_id"]
            if not parent:
                continue
            key = (
                detail["document_ref"],
                detail["page_start"],
                detail["page_end"],
                parent,
            )
            parent_page_groups[key].add(detail["projection_kind"])
        assembly_atomic_competition = any(
            "compatible_sibling_assembly" in kinds and len(kinds) > 1
            for kinds in parent_page_groups.values()
        )
        review_cases.append(
            {
                "case_id": case_id,
                "question": truth_by_id[case_id]["question"],
                "expected_evidence": truth_by_id[case_id]["relevant_evidence"],
                "baseline_rank": baseline_rank,
                "current_rank": current_rank,
                "page_diversified_rank": page_diversified_rank,
                "assembly_atomic_competition_before_relevant": assembly_atomic_competition,
                "first_relevant_content_equivalent_pages": sorted(equivalent_pages),
                "top_ten": fused_detail,
            }
        )

    e032 = next(item for item in review_cases if item["case_id"] == "E-032")
    if e032["first_relevant_content_equivalent_pages"] != list(range(1, 12)):
        raise SystemExit("e032_equivalent_page_inventory_changed")
    e015 = next(item for item in review_cases if item["case_id"] == "E-015")
    if not e015["assembly_atomic_competition_before_relevant"]:
        raise SystemExit("e015_competition_signature_missing")

    result = {
        "schema_version": 1,
        "artifact_kind": "ishikawa_synthetic_corpus_v2_rank_failure_review",
        "source_sha256": {
            "observation": _sha256(observation_path),
            "baseline_observation": _sha256(baseline_path),
            "candidate": _sha256(candidate_path),
            "truth": _sha256(truth_path),
        },
        "boundaries": {
            "accepted_database_contact": False,
            "black_corpus_access": False,
            "corpus_ingestion": False,
            "database_write": False,
            "gemma_contact": False,
            "model_contact": False,
            "production_profile_changed": False,
            "truth_evaluation_only": True,
            "truth_used_by_retrieval": False,
        },
        "observed": {
            "baseline_body_mrr_at_20": baseline["body_metrics"]["mrr_at_20"],
            "current_body_mrr_at_20": observation["body_metrics"]["mrr_at_20"],
            "current_header_mrr_at_20": observation["header_metrics"]["mrr_at_20"],
            "rank_distribution": {
                str(rank): count for rank, count in sorted(rank_distribution.items())
            },
            "improved_case_ids": improved,
            "worsened_case_ids": worsened,
            "unchanged_case_count": len(unchanged),
            "non_rank_one_case_count": len(review_cases),
            "page_diversified_body_mrr_at_20": _mrr(page_diversified_ranks),
        },
        "findings": [
            {
                "finding_id": "F-001",
                "classification": "assembly_atomic_self_competition",
                "evidence_case_ids": [
                    item["case_id"]
                    for item in review_cases
                    if item["assembly_atomic_competition_before_relevant"]
                ],
                "interpretation": (
                    "Assemblies and their atomic source units can both consume fused ranks. "
                    "A later experiment may test post-fusion source-unit-aware diversification."
                ),
            },
            {
                "finding_id": "F-002",
                "classification": "page_truth_penalizes_identical_repeated_evidence",
                "evidence_case_ids": ["E-032"],
                "equivalent_pages": e032["first_relevant_content_equivalent_pages"],
                "interpretation": (
                    "E-032 retrieves the exact expected sentence at rank 1 on another page, "
                    "while the current scorer accepts only physical page 1."
                ),
            },
            {
                "finding_id": "F-003",
                "classification": "page_only_diversification_not_sufficient",
                "counterfactual_body_mrr_at_20": _mrr(page_diversified_ranks),
                "interpretation": (
                    "Collapsing repeated document-page results alone does not establish the "
                    "strict promotion target and must not be promoted as a fix."
                ),
            },
        ],
        "review_cases": review_cases,
        "next_gate": "design_bounded_evidence_equivalence_and_source_unit_diversification_experiment",
        "promotion_authorized": False,
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    _write_json(output_path, result)
    print(
        f"baseline_body_mrr_at_20={result['observed']['baseline_body_mrr_at_20']};"
        f"current_body_mrr_at_20={result['observed']['current_body_mrr_at_20']};"
        f"header_mrr_at_20={result['observed']['current_header_mrr_at_20']}"
    )
    print(
        "rank_distribution="
        + ",".join(
            f"{rank}:{count}"
            for rank, count in result["observed"]["rank_distribution"].items()
        )
    )
    print(
        f"improved_cases={','.join(improved) or 'none'};"
        f"worsened_cases={','.join(worsened) or 'none'};"
        f"non_rank_one_cases={len(review_cases)}"
    )
    print(
        "finding_F001=assembly_atomic_self_competition;cases="
        + ",".join(result["findings"][0]["evidence_case_ids"])
    )
    print(
        "finding_F002=page_truth_penalizes_identical_repeated_evidence;"
        "case=E-032;equivalent_pages="
        + ",".join(str(page) for page in e032["first_relevant_content_equivalent_pages"])
    )
    print(
        f"finding_F003=page_only_diversification_not_sufficient;"
        f"counterfactual_body_mrr_at_20={result['observed']['page_diversified_body_mrr_at_20']}"
    )
    print("promotion_authorized=false")
    print(f"review_artifact_sha256={_sha256(output_path)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
