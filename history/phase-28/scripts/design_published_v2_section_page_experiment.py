#!/usr/bin/env python3
"""Build a content-free manifest for the bounded section/page experiment."""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


class ExperimentDesignError(RuntimeError):
    """Stable failure at the experiment-design boundary."""


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise ExperimentDesignError(reason)


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
        raise ExperimentDesignError("json_input_invalid") from error
    require(isinstance(value, dict), "json_input_invalid")
    return value


def write_json(path: Path, value: dict[str, Any]) -> None:
    require(not path.exists() and not path.is_symlink(), "output_exists")
    path.write_text(
        json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def candidate_inventory(
    chunk_artifact: dict[str, Any]
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    metadata: list[dict[str, Any]] = []
    body: list[dict[str, Any]] = []
    identities: set[str] = set()
    for document in chunk_artifact["documents"]:
        document_ref = document["document_ref"]
        for candidate in document["candidates"]:
            chunk_id = candidate["chunk_id"]
            require(chunk_id not in identities, "candidate_identity_duplicate")
            identities.add(chunk_id)
            entry = {
                "document_ref": document_ref,
                "chunk_id": chunk_id,
                "projection_kind": candidate["projection_kind"],
                "parent_unit_id": candidate.get("parent_unit_id"),
                "page_start": int(candidate["citation_anchor"]["page_start"]),
                "page_end": int(candidate["citation_anchor"]["page_end"]),
                "sequence": candidate["sequence"],
                "content_digest": candidate["content_digest"],
                "source_unit_ids": candidate["source_unit_ids"],
            }
            if candidate["projection_kind"] == "document_control_metadata":
                metadata.append(entry)
            else:
                body.append(entry)
    require(len(identities) == 139, "candidate_inventory_changed")
    return metadata, body


def build_design(
    review_path: Path,
    chunks_path: Path,
    body_truth_path: Path,
    header_truth_path: Path,
    plan_path: Path,
) -> dict[str, Any]:
    review = load_json(review_path)
    chunks = load_json(chunks_path)
    body_truth = load_json(body_truth_path)
    header_truth = load_json(header_truth_path)
    require(
        review.get("artifact_kind")
        == "ishikawa_published_synthetic_corpus_v2_atomic_rank_failure_review"
        and review.get("schema_version") == 1
        and review.get("accepted_baseline", {}).get("body_mrr_at_20")
        == "0.873056"
        and review.get("accepted_baseline", {}).get("header_mrr_at_20")
        == "1.000000"
        and review.get("rank_failure_summary", {}).get("case_count") == 12
        and review.get("bounded_search", {}).get("strict_gate_profiles") == 0
        and review.get("conclusions", {}).get("current_profile_remains_frozen")
        is True
        and review.get("conclusions", {}).get("new_retrieval_candidate_authorized")
        is False,
        "rank_review_contract_invalid",
    )
    require(
        chunks.get("artifact_kind") == "non_publishable_structural_chunk_candidates"
        and chunks.get("publication_eligible") is False
        and chunks.get("token_measurement_status")
        == "pending_authoritative_nomic_measurement",
        "chunk_artifact_contract_invalid",
    )
    require(
        body_truth.get("artifact_kind")
        == "ishikawa_synthetic_corpus_v2_body_retrieval_cases"
        and body_truth.get("schema_version") == 1
        and body_truth.get("evaluation_only") is True
        and body_truth.get("excluded_from_corpus_ingestion") is True
        and len(body_truth.get("cases", [])) == 60,
        "body_truth_contract_invalid",
    )
    require(
        header_truth.get("artifact_kind")
        == "ishikawa_synthetic_corpus_v2_header_retrieval_cases"
        and header_truth.get("schema_version") == 1
        and header_truth.get("synthetic_content_only") is True
        and len(header_truth.get("cases", [])) == 8,
        "header_truth_contract_invalid",
    )
    require(plan_path.is_file() and not plan_path.is_symlink(), "plan_unsafe")

    metadata, body = candidate_inventory(chunks)
    require(len(metadata) == 6 and len(body) == 133, "projection_inventory_changed")
    section_groups: dict[tuple[str, str, int], list[dict[str, Any]]] = defaultdict(list)
    for candidate in body:
        parent = candidate["parent_unit_id"]
        require(candidate["page_start"] == candidate["page_end"], "multipage_atom_found")
        if parent is not None:
            section_groups[
                (candidate["document_ref"], parent, candidate["page_start"])
            ].append(candidate)
    require(
        len(section_groups) == 29
        and sum(len(group) for group in section_groups.values()) == 123,
        "section_page_inventory_changed",
    )
    group_sizes = Counter(len(group) for group in section_groups.values())
    duplicate_groups: dict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    for candidate in body:
        duplicate_groups[
            (candidate["document_ref"], candidate["content_digest"])
        ].append(candidate)
    repeated = [group for group in duplicate_groups.values() if len(group) > 1]
    require(
        len(repeated) == 3
        and sum(len(group) for group in repeated) == 24
        and sum(len(group) - 1 for group in repeated) == 21,
        "duplicate_inventory_changed",
    )
    variant_names = [
        "atomic_baseline",
        "atomic_duplicate_canonical",
        "section_page",
        "section_page_duplicate_canonical",
    ]
    return {
        "artifact_kind": "ishikawa_published_synthetic_corpus_v2_section_page_experiment_design",
        "schema_version": 1,
        "source_sha256": {
            "rank_review": sha256_file(review_path),
            "chunk_artifact": sha256_file(chunks_path),
            "body_truth": sha256_file(body_truth_path),
            "header_truth": sha256_file(header_truth_path),
            "experiment_plan": sha256_file(plan_path),
        },
        "accepted_baseline": review["accepted_baseline"],
        "frozen_profile": {
            "exact_candidate_depth": 1,
            "lexical_candidate_depth": 20,
            "vector_candidate_depth": 20,
            "fused_candidate_depth": 20,
            "rrf_constant": 60,
            "lane_weights": {"exact": 1, "lexical": 1, "vector": 4},
            "learned_reranker": False,
        },
        "candidate_inventory": {
            "published_atomic_candidates": 139,
            "document_control_metadata_candidates": 6,
            "body_atomic_candidates": 133,
            "eligible_section_page_groups": len(section_groups),
            "grouped_body_atomic_candidates": sum(
                len(group) for group in section_groups.values()
            ),
            "ungrouped_body_atomic_candidates": sum(
                candidate["parent_unit_id"] is None for candidate in body
            ),
            "maximum_pre_collapse_candidates": 139 + len(section_groups),
            "section_page_group_size_distribution": {
                str(size): count for size, count in sorted(group_sizes.items())
            },
            "duplicate_evidence_groups": len(repeated),
            "duplicate_member_occurrences": sum(len(group) for group in repeated),
            "repeated_occurrences_beyond_canonical": sum(
                len(group) - 1 for group in repeated
            ),
        },
        "variants": [
            {
                "name": name,
                "section_page_representatives": name.startswith("section_page"),
                "document_local_duplicate_canonicalization": name.endswith(
                    "duplicate_canonical"
                ),
            }
            for name in variant_names
        ],
        "construction_contract": {
            "section_page_identity": [
                "document_version",
                "parent_structural_unit",
                "physical_page",
            ],
            "source_order_stable": True,
            "heading_emitted_once": True,
            "metadata_candidates_excluded": True,
            "atomic_evidence_authoritative": True,
            "representative_used_for_retrieval_scoring_only": True,
            "exact_nomic_token_measurement_required": True,
            "over_ceiling_action": "block",
            "silent_truncation": False,
        },
        "ranking_contract": {
            "frozen_profile_only": True,
            "body_group_key": [
                "document_version",
                "parent_structural_unit",
                "physical_page",
            ],
            "group_score": "highest_fused_member_score",
            "tie_break": "deterministic_candidate_identity",
            "metadata_and_exact_routes_bypass_body_collapse": True,
            "selected_group_expands_to_ordered_atomic_members": True,
        },
        "measurement_contract": {
            "variant_count": 4,
            "body_cases": 60,
            "header_cases": 8,
            "fresh_nomic_representative_embeddings": True,
            "fresh_postgresql_lexical_ranks": True,
            "private_disposable_postgresql": True,
            "warm_latency_diagnostic": True,
            "gemma_contact": False,
        },
        "eligibility_gate": {
            "body_mrr_at_20": ">0.91",
            "body_required_evidence_at_20": "60/60",
            "header_mrr_at_20": "1.000000",
            "header_relevant_at_5": "8/8",
            "header_required_evidence_at_20": "11/11",
            "deterministic_replay_required": True,
            "top_five_and_regressions_are_diagnostics": True,
            "automatic_promotion": False,
        },
        "boundaries": {
            "question_text_retained": False,
            "source_text_retained": False,
            "black_corpus_access": False,
            "database_contact": False,
            "model_contact": False,
            "credential_read": False,
            "corpus_changed": False,
            "truth_changed": False,
            "service_changed": False,
            "package_changed": False,
            "production_profile_changed": False,
            "candidate_promoted": False,
        },
        "next_gate": "execute_bounded_section_page_candidate_experiment",
    }


def self_test() -> int:
    counts = Counter([1, 1, 2, 5])
    require(dict(sorted(counts.items())) == {1: 2, 2: 1, 5: 1}, "self_test_failed")
    print("published_v2_section_page_experiment_design_self_test=pass")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--review")
    parser.add_argument("--chunks")
    parser.add_argument("--body-truth")
    parser.add_argument("--header-truth")
    parser.add_argument("--plan")
    parser.add_argument("--output")
    arguments = parser.parse_args()
    if arguments.self_test:
        return self_test()
    require(
        all(
            (
                arguments.review,
                arguments.chunks,
                arguments.body_truth,
                arguments.header_truth,
                arguments.plan,
                arguments.output,
            )
        ),
        "arguments_missing",
    )
    result = build_design(
        Path(arguments.review).resolve(strict=True),
        Path(arguments.chunks).resolve(strict=True),
        Path(arguments.body_truth).resolve(strict=True),
        Path(arguments.header_truth).resolve(strict=True),
        Path(arguments.plan).resolve(strict=True),
    )
    write_json(Path(arguments.output), result)
    print("published_v2_section_page_experiment_design=pass")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ExperimentDesignError as error:
        print(f"published_v2_section_page_experiment_design=blocked;reason={error}")
        raise SystemExit(1) from error
