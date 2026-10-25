#!/usr/bin/env python3
"""Qualify the frozen V13-47 application ranking from implemented source."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import sys
from pathlib import Path
from typing import Any, Mapping, Sequence

import measure_synthetic_corpus_v2_without_ingestion as base
import measure_synthetic_corpus_v3_preingestion as v3
import measure_v13_41_supplemental_ranking as v41
import measure_v13_44_decomposed_passage_reranking as v44
import measure_v13_46_score_calibrated_global_reranking as v46


SOURCE_VARIANT = "facet5_b2_e1_c1"
SELECTED_VARIANT = "raw_l1_v3_fc1_d1_h010"


def _metadata(chunks: Mapping[str, Any]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for document in chunks["documents"]:
        for candidate in document["candidates"]:
            result[candidate["chunk_id"]] = {
                "candidate": candidate,
                "document_id": document["document_id"],
                "document_version_id": document["document_version_id"],
                "document_key": document["document_ref"],
            }
    return result


def _representation(record: Mapping[str, Any]) -> dict[str, Any]:
    candidate = record["candidate"]
    properties = candidate["projection_properties"]
    scoring_only = properties.get("retrieval_scoring_only") is True
    return {
        "document_id": record["document_id"],
        "document_version_id": record["document_version_id"],
        "document_key": record["document_key"],
        "retrieval_group_id": properties.get("retrieval_group_id"),
        "authoritative_chunk_ids": tuple(properties.get("component_chunk_ids", ()))
        if scoring_only else (candidate["chunk_id"],),
        "retrieval_scoring_only": scoring_only,
        "structural_path": tuple(candidate["citation_anchor"]["structural_path"]),
    }


def _lane(
    lane_name: str,
    rows: Sequence[Mapping[str, Any]],
    metadata: Mapping[str, Mapping[str, Any]],
    lane_type: Any,
) -> tuple[Any, ...]:
    return tuple(
        lane_type(
            chunk_id=row["chunk_id"],
            lane=lane_name,
            rank=rank,
            raw_score=float(row["score"]),
            exact_reason="structured_term_match" if lane_name == "exact" else None,
            retrieval_variant="strict" if lane_name == "lexical" else None,
            **_representation(metadata[row["chunk_id"]]),
        )
        for rank, row in enumerate(rows, start=1)
    )


def _baseline(
    rows: Sequence[Mapping[str, Any]],
    exact_ids: frozenset[str],
    metadata: Mapping[str, Mapping[str, Any]],
    fused_type: Any,
) -> tuple[Any, ...]:
    return tuple(
        fused_type(
            chunk_id=row["chunk_id"],
            fused_score=float(row["score"]),
            exact_priority=row["chunk_id"] in exact_ids,
            evidence=(),
            **_representation(metadata[row["chunk_id"]]),
        )
        for row in rows
    )


def _rank_records(
    ranked: Sequence[Any], metadata: Mapping[str, Mapping[str, Any]]
) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for rank, item in enumerate(ranked, start=1):
        raw = metadata[item.chunk_id]
        anchor = raw["candidate"]["citation_anchor"]
        records.append(
            {
                "chunk_id": item.chunk_id,
                "document_ref": raw["document_key"],
                "page_start": anchor["page_start"],
                "page_end": anchor["page_end"],
                "rank": rank,
                "score": format(item.fused_score, ".17g"),
            }
        )
    return records


def execute(arguments: argparse.Namespace) -> None:
    source = base.load_bound_json(
        arguments.source_observation,
        arguments.expected_source_observation_sha256,
        32 * 1024 * 1024,
    )
    selected = base.load_bound_json(
        arguments.selected_observation,
        arguments.expected_selected_observation_sha256,
        32 * 1024 * 1024,
    )
    normalized = base.load_bound_json(
        arguments.normalized,
        arguments.expected_normalized_sha256,
        32 * 1024 * 1024,
    )
    truth = base.load_bound_json(
        arguments.truth,
        arguments.expected_truth_sha256,
        4 * 1024 * 1024,
    )
    sys.path.insert(0, str(arguments.python_root.resolve(strict=True)))
    from ishikawa.canonical import canonical_json_bytes
    from ishikawa.chunking import METHOD_PROFILE_ID, build_chunk_candidates
    from ishikawa.method_profile import ACCEPTED_RETRIEVAL_PROFILE, validate_retrieval_profile
    from ishikawa.relationships import validate_relationship_registry
    from ishikawa.retrieval import (
        FusedCandidate,
        LaneCandidate,
        collapse_retrieval_groups,
        decomposed_candidate_pool,
        score_calibrated_global_rerank,
        uses_calibrated_body_route,
    )
    from ishikawa.yaml_loader import load_restricted_yaml

    for implementation_path in (
        arguments.retrieval_source,
        arguments.adapter_source,
        arguments.database_schema,
        arguments.method_profile,
        arguments.relationship_registry,
    ):
        base.require(
            implementation_path.is_absolute()
            and implementation_path.is_file()
            and not implementation_path.is_symlink(),
            "implementation_source_unsafe",
        )
    profile = validate_retrieval_profile(
        load_restricted_yaml(arguments.method_profile, label="method profile")
    )
    registry = validate_relationship_registry(
        load_restricted_yaml(arguments.relationship_registry, label="relationship registry")
    )
    base.require(
        profile.digest == ACCEPTED_RETRIEVAL_PROFILE.digest
        == arguments.expected_retrieval_profile_id
        and registry.base_retrieval_profile_id == profile.digest,
        "implemented_profile_identity_mismatch",
    )
    chunks = build_chunk_candidates(normalized)
    chunks_sha256 = hashlib.sha256(canonical_json_bytes(chunks)).hexdigest()
    base.require(
        METHOD_PROFILE_ID == arguments.expected_chunk_profile_id
        and chunks_sha256 == arguments.expected_chunks_sha256,
        "implemented_chunk_boundary_changed",
    )
    metadata = _metadata(chunks)
    cases = {item.case_id: item for item in v3.load_cases(truth)}
    reference_results = source["variants"]["accepted_v6"]["results"]["selection"]
    source_results = source["variants"][SOURCE_VARIANT]["results"]["selection"]
    target_results = selected["variants"][SELECTED_VARIANT]["results"]["selection"]
    reference_by_case = {item["case_id"]: item for item in reference_results}
    source_by_case = {item["case_id"]: item for item in source_results}
    target_by_case = {item["case_id"]: item for item in target_results}
    base.require(
        len(cases) == len(reference_by_case) == len(source_by_case)
        == len(target_by_case) == 180
        and set(cases) == set(reference_by_case) == set(source_by_case)
        == set(target_by_case),
        "qualification_case_inventory_invalid",
    )

    implemented: list[dict[str, Any]] = []
    exact_order_matches = 0
    first_relevant_matches = 0
    pool_matches = 0
    for case_id in sorted(cases):
        case = cases[case_id]
        reference = reference_by_case[case_id]
        source_result = source_by_case[case_id]
        target = target_by_case[case_id]
        route = uses_calibrated_body_route(
            case.question,
            page_routed=False,
            complete_structure_requested=False,
        )
        base.require(route == (case.family == "body"), "implemented_route_mismatch")
        if not route:
            base.require(
                source_result["fused"] == target["fused"],
                "unchanged_route_order_mismatch",
            )
            implemented.append(copy.deepcopy(target))
            exact_order_matches += 1
            first_relevant_matches += 1
            pool_matches += 1
            continue

        exact_ids = frozenset(item["chunk_id"] for item in reference["lanes"]["exact"])
        baseline = _baseline(
            reference["fused"], exact_ids, metadata, FusedCandidate
        )
        facet_lanes = tuple(
            {
                "lexical": _lane("lexical", lanes["lexical"], metadata, LaneCandidate),
                "vector": _lane("vector", lanes["vector"], metadata, LaneCandidate),
            }
            for lanes in source_result["decomposition"]["facet_lanes"]
        )
        pool = decomposed_candidate_pool(
            baseline,
            facet_lanes,
            rrf_constant=profile.rrf_constant,
            baseline_weight=profile.expansion_baseline_weight,
            best_facet_weight=profile.expansion_best_facet_weight,
            facet_coverage_weight=profile.expansion_facet_coverage_weight,
        )
        if profile.section_page_representatives and not exact_ids:
            pool = collapse_retrieval_groups(pool)
        pool = pool[: profile.fused_candidate_depth]
        expected_pool_ids = [item["chunk_id"] for item in source_result["fused"]]
        actual_pool_ids = [item.chunk_id for item in pool]
        base.require(
            actual_pool_ids == expected_pool_ids,
            f"implemented_candidate_pool_mismatch_{case_id}",
        )
        pool_matches += 1
        reranked = score_calibrated_global_rerank(
            pool,
            _lane("lexical", reference["lanes"]["lexical"], metadata, LaneCandidate),
            _lane("vector", reference["lanes"]["vector"], metadata, LaneCandidate),
            facet_lanes,
            case.question,
        )
        ranked_records = _rank_records(reranked, metadata)
        measured = v46.measured_result(
            source_result,
            ranked_records,
            v46.CONFIG_BY_NAME[SELECTED_VARIANT],
        )
        implemented.append(measured)
        if [item["chunk_id"] for item in ranked_records] == [
            item["chunk_id"] for item in target["fused"]
        ]:
            exact_order_matches += 1
        base.require(
            measured["first_relevant_rank"] == target["first_relevant_rank"],
            f"implemented_relevant_rank_mismatch_{case_id}",
        )
        first_relevant_matches += 1

    expansion = source["variants"][SOURCE_VARIANT]["results"][
        "expanded_atomic_diagnostic"
    ]
    summary = v41.summarize_variant(implemented, expansion)
    expected_summary = selected["variants"][SELECTED_VARIANT]
    base.require(
        summary["metrics"] == expected_summary["metrics"]
        and summary["gate"] == expected_summary["gate"]
        and summary["gate"]["status"] == "qualified"
        and summary["metrics"]["body"]["mrr_at_20"] == "0.895450"
        and summary["metrics"]["body"]["relevant_at_20"] == 120,
        "implemented_metrics_do_not_match_selected_candidate",
    )
    artifact = {
        "artifact_kind": "ishikawa_v13_47_application_ranking_qualification",
        "schema_version": 1,
        "implemented_retrieval_profile_id": profile.digest,
        "chunk_profile_id": METHOD_PROFILE_ID,
        "selected_candidate": SELECTED_VARIANT,
        "case_count": len(implemented),
        "candidate_pool_matches": pool_matches,
        "first_relevant_rank_matches": first_relevant_matches,
        "exact_full_order_matches": exact_order_matches,
        "metrics": summary["metrics"],
        "gate": summary["gate"],
        "source_sha256": {
            "v13_44_observation": arguments.expected_source_observation_sha256,
            "v13_46_observation": arguments.expected_selected_observation_sha256,
            "normalized_corpus": arguments.expected_normalized_sha256,
            "retrieval_truth": arguments.expected_truth_sha256,
            "accepted_v6_chunks": chunks_sha256,
        },
        "implementation_sha256": {
            "retrieval": base.sha256_file(arguments.retrieval_source),
            "postgres_retrieval": base.sha256_file(arguments.adapter_source),
            "method_profile": base.sha256_file(arguments.method_profile),
            "relationship_registry": base.sha256_file(arguments.relationship_registry),
            "database_schema": base.sha256_file(arguments.database_schema),
        },
        "boundaries": {
            "application_source_imported": True,
            "accepted_database_contact": False,
            "black_corpus_access": False,
            "corpus_ingestion": False,
            "gemma_contact": False,
            "nomic_contact": False,
            "postgresql_contact": False,
            "runtime_flat_file_index": False,
        },
        "qualification_status": "pass",
        "next_gate": "isolated_corpus_v3_ingestion_and_complete_api_qualification",
    }
    base.write_exclusive(arguments.output, base.canonical_json_bytes(artifact) + b"\n")
    print("purpose=qualify_v13_47_application_ranking")
    print(
        f"cases={len(implemented)};candidate_pool_matches={pool_matches};"
        f"first_relevant_rank_matches={first_relevant_matches};"
        f"exact_full_order_matches={exact_order_matches}"
    )
    print(
        "body_mrr_at_20=0.895450;body_coverage=120/120;"
        "relationship_coverage=30/30;header_coverage=30/30"
    )
    print("v13_47_application_ranking_qualification=pass")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--python-root", type=Path, required=True)
    parser.add_argument("--source-observation", type=Path, required=True)
    parser.add_argument("--expected-source-observation-sha256", required=True)
    parser.add_argument("--selected-observation", type=Path, required=True)
    parser.add_argument("--expected-selected-observation-sha256", required=True)
    parser.add_argument("--normalized", type=Path, required=True)
    parser.add_argument("--expected-normalized-sha256", required=True)
    parser.add_argument("--truth", type=Path, required=True)
    parser.add_argument("--expected-truth-sha256", required=True)
    parser.add_argument("--expected-chunks-sha256", required=True)
    parser.add_argument("--expected-chunk-profile-id", required=True)
    parser.add_argument("--expected-retrieval-profile-id", required=True)
    parser.add_argument("--method-profile", type=Path, required=True)
    parser.add_argument("--relationship-registry", type=Path, required=True)
    parser.add_argument("--retrieval-source", type=Path, required=True)
    parser.add_argument("--adapter-source", type=Path, required=True)
    parser.add_argument("--database-schema", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    try:
        execute(arguments)
    except (base.MeasurementError, OSError, ValueError, KeyError, AssertionError) as error:
        print(f"v13_47_application_ranking_qualification=blocked;reason={error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
