#!/usr/bin/env python3
"""Measure frozen V13-46 score-calibrated global passage reranking.

The evaluator reuses the checksum-bound V13-44 lane observation.  It does not
repeat model or database work: V13-44 already retained every raw lane score,
the complete top-20 candidate pool, and all 180 case outcomes needed by this
bounded final-ordering experiment.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import re
import sys
import time
from pathlib import Path
from typing import Any, Mapping, Sequence

import measure_synthetic_corpus_v2_without_ingestion as base
import measure_synthetic_corpus_v3_preingestion as v3
import measure_v13_40_bounded_ranking_candidates as v40
import measure_v13_41_supplemental_ranking as v41
import measure_v13_44_decomposed_passage_reranking as v44


SOURCE_VARIANT = "facet5_b2_e1_c1"
REFERENCE_VARIANT = "v13_44_complete_coverage"
FEATURES = (
    "baseline_rrf",
    "original_lexical",
    "original_vector",
    "best_facet_lexical",
    "best_facet_vector",
    "vector_facet_coverage",
    "document_lexical_affinity",
    "document_vector_affinity",
    "heading_path_overlap",
)
VARIANT_CONFIGS = (
    (
        "raw_l1_v3_fc1_d1_h010",
        (0.0, 1.0, 3.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.10),
    ),
    (
        "rrf2_v3_fl1_fc1_d1_h010",
        (2.0, 0.0, 3.0, 1.0, 0.0, 1.0, 1.0, 0.0, 0.10),
    ),
    (
        "raw_l1_v3_fc1_d1_h025",
        (0.0, 1.0, 3.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.25),
    ),
    (
        "rrf1_l1_v3_fc1_d1_h010",
        (1.0, 1.0, 3.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.10),
    ),
    (
        "rrf2_v2_fl1_fv1_fc1_d1_h010",
        (2.0, 0.0, 2.0, 1.0, 1.0, 1.0, 1.0, 0.0, 0.10),
    ),
)
VARIANT_ORDER = tuple(item[0] for item in VARIANT_CONFIGS)
CONFIG_BY_NAME = {
    name: {feature: weight for feature, weight in zip(FEATURES, weights, strict=True)}
    for name, weights in VARIANT_CONFIGS
}
WORD = re.compile(r"[a-z0-9]+")
STOPWORDS = frozenset(
    {
        "a", "an", "and", "are", "be", "by", "do", "does", "for", "from",
        "how", "in", "is", "it", "its", "may", "must", "of", "on", "or",
        "should", "that", "the", "their", "this", "to", "under", "what",
        "when", "where", "which", "who", "why", "with",
    }
)


def normalized(values: Mapping[str, float]) -> dict[str, float]:
    """Min-max normalize one query-local signal without inventing missing hits."""

    base.require(
        all(isinstance(key, str) and key and math.isfinite(float(value))
            for key, value in values.items()),
        "score_normalization_input_invalid",
    )
    if not values:
        return {}
    low = min(float(value) for value in values.values())
    high = max(float(value) for value in values.values())
    if high == low:
        return {key: 1.0 for key in values}
    return {key: (float(value) - low) / (high - low) for key, value in values.items()}


def terms(value: str) -> frozenset[str]:
    base.require(isinstance(value, str) and "\x00" not in value, "term_input_invalid")
    return frozenset(
        item for item in WORD.findall(value.casefold())
        if len(item) > 1 and item not in STOPWORDS
    )


def heading_overlap(question: str, path: Sequence[str]) -> float:
    base.require(
        isinstance(path, (list, tuple))
        and path
        and all(isinstance(item, str) and item.strip() == item and item for item in path),
        "heading_path_invalid",
    )
    query_terms = terms(question)
    path_terms = terms(" ".join(path))
    union = query_terms | path_terms
    return len(query_terms & path_terms) / len(union) if union else 0.0


def _records_by_chunk(records: Sequence[Mapping[str, Any]]) -> dict[str, float]:
    result: dict[str, float] = {}
    for record in records:
        chunk_id = record.get("chunk_id")
        score = record.get("score")
        base.require(
            isinstance(chunk_id, str)
            and chunk_id not in result
            and isinstance(score, str)
            and math.isfinite(float(score)),
            "lane_record_invalid",
        )
        result[chunk_id] = float(score)
    return result


def feature_matrix(
    reference: Mapping[str, Any],
    source: Mapping[str, Any],
    question: str,
    raw_chunks: Mapping[str, Mapping[str, Any]],
) -> dict[str, dict[str, float]]:
    pool = source.get("fused")
    decomposition = source.get("decomposition")
    base.require(
        isinstance(pool, list)
        and 1 <= len(pool) <= 20
        and len({item.get("chunk_id") for item in pool}) == len(pool)
        and isinstance(decomposition, dict),
        "v13_44_candidate_pool_invalid",
    )
    pool_ids = {item["chunk_id"] for item in pool}
    matrix = {feature: {} for feature in FEATURES}
    matrix["baseline_rrf"] = normalized(_records_by_chunk(pool))
    for lane_name, feature in (
        ("lexical", "original_lexical"),
        ("vector", "original_vector"),
    ):
        records = reference.get("lanes", {}).get(lane_name)
        base.require(isinstance(records, list), "primary_lane_missing")
        values = _records_by_chunk(records)
        matrix[feature] = normalized(
            {chunk_id: value for chunk_id, value in values.items() if chunk_id in pool_ids}
        )

    facet_lanes = decomposition.get("facet_lanes")
    facet_count = decomposition.get("facet_count")
    base.require(
        isinstance(facet_lanes, list)
        and isinstance(facet_count, int)
        and facet_count == len(facet_lanes)
        and 1 <= facet_count <= v44.MAX_FACETS,
        "facet_lane_inventory_invalid",
    )
    vector_coverage: dict[str, int] = {}
    for lane_name, feature in (
        ("lexical", "best_facet_lexical"),
        ("vector", "best_facet_vector"),
    ):
        best: dict[str, float] = {}
        for lanes in facet_lanes:
            records = lanes.get(lane_name)
            base.require(isinstance(records, list), "facet_lane_missing")
            values = normalized(
                {
                    chunk_id: value
                    for chunk_id, value in _records_by_chunk(records).items()
                    if chunk_id in pool_ids
                }
            )
            for chunk_id, value in values.items():
                best[chunk_id] = max(best.get(chunk_id, 0.0), value)
                if lane_name == "vector":
                    vector_coverage[chunk_id] = vector_coverage.get(chunk_id, 0) + 1
        matrix[feature] = best
    matrix["vector_facet_coverage"] = {
        chunk_id: count / facet_count for chunk_id, count in vector_coverage.items()
    }

    for lane_name, feature in (
        ("lexical", "document_lexical_affinity"),
        ("vector", "document_vector_affinity"),
    ):
        document_scores: dict[str, float] = {}
        for record in reference["lanes"][lane_name]:
            document_ref = record["document_ref"]
            document_scores[document_ref] = max(
                document_scores.get(document_ref, -math.inf), float(record["score"])
            )
        document_scores = normalized(document_scores)
        matrix[feature] = {
            item["chunk_id"]: document_scores.get(item["document_ref"], 0.0)
            for item in pool
        }

    overlaps: dict[str, float] = {}
    for item in pool:
        chunk_id = item["chunk_id"]
        candidate = raw_chunks.get(chunk_id)
        anchor = candidate.get("citation_anchor") if isinstance(candidate, dict) else None
        path = anchor.get("structural_path") if isinstance(anchor, dict) else None
        base.require(
            candidate is not None
            and isinstance(path, list),
            "candidate_heading_path_missing",
        )
        overlaps[chunk_id] = heading_overlap(question, path)
    matrix["heading_path_overlap"] = normalized(overlaps)
    base.require(set(matrix) == set(FEATURES), "feature_matrix_incomplete")
    return matrix


def rerank(
    source: Mapping[str, Any],
    matrix: Mapping[str, Mapping[str, float]],
    config: Mapping[str, float],
) -> list[dict[str, Any]]:
    base.require(set(config) == set(FEATURES), "score_config_invalid")
    pool = source["fused"]
    source_rank = {item["chunk_id"]: rank for rank, item in enumerate(pool, 1)}

    def score(chunk_id: str) -> float:
        return sum(config[name] * matrix[name].get(chunk_id, 0.0) for name in FEATURES)

    ordered = sorted(
        pool,
        key=lambda item: (
            -score(item["chunk_id"]),
            -matrix["heading_path_overlap"].get(item["chunk_id"], 0.0),
            -matrix["baseline_rrf"].get(item["chunk_id"], 0.0),
            source_rank[item["chunk_id"]],
            item["chunk_id"],
        ),
    )
    result: list[dict[str, Any]] = []
    for rank, item in enumerate(ordered, 1):
        copy_item = dict(item)
        copy_item["rank"] = rank
        copy_item["score"] = format(score(item["chunk_id"]), ".17g")
        result.append(copy_item)
    base.require(
        len(result) == len(pool)
        and {item["chunk_id"] for item in result}
        == {item["chunk_id"] for item in pool},
        "calibrated_candidate_pool_changed",
    )
    return result


def _matches(record: Mapping[str, Any], evidence: Mapping[str, Any]) -> bool:
    return (
        record["document_ref"] == evidence["document_ref"]
        and record["page_start"] <= evidence["page"] <= record["page_end"]
    )


def measured_result(
    source: Mapping[str, Any],
    fused: Sequence[Mapping[str, Any]],
    config: Mapping[str, float],
) -> dict[str, Any]:
    result = copy.deepcopy(source)
    evidence = result.get("matched_evidence")
    base.require(isinstance(evidence, list) and evidence, "matched_evidence_missing")
    first_rank = next(
        (
            rank for rank, item in enumerate(fused, 1)
            if any(_matches(item, expected) for expected in evidence)
        ),
        None,
    )
    result["first_relevant_rank"] = first_rank
    result["relevant_within_top_five"] = first_rank is not None and first_rank <= 5
    result["fused"] = list(fused)
    result["score_calibration_config"] = dict(config)
    result["score_calibration_source"] = SOURCE_VARIANT
    return result


def selection_key(name: str, result: Mapping[str, Any]) -> tuple[float, int, int, int]:
    body = result["metrics"]["body"]
    movement = result["rank_movement"]
    return (
        float(body["mrr_at_20"]),
        body["relevant_at_5"],
        -movement["regressed"],
        -VARIANT_ORDER.index(name),
    )


def execute(arguments: argparse.Namespace) -> None:
    source = base.load_bound_json(
        arguments.source_observation,
        arguments.expected_source_observation_sha256,
        32 * 1024 * 1024,
    )
    normalized_source = base.load_bound_json(
        arguments.normalized, arguments.expected_normalized_sha256, 32 * 1024 * 1024
    )
    truth = base.load_bound_json(
        arguments.truth, arguments.expected_truth_sha256, 4 * 1024 * 1024
    )
    base.require(
        source.get("artifact_kind")
        == "ishikawa_v13_44_decomposed_passage_reranking_experiment"
        and source.get("selection_status") == "not_met"
        and source.get("selected_candidate") is None
        and source.get("promotion_authorized") is False
        and source.get("variants", {}).get(SOURCE_VARIANT, {}).get("metrics", {})
        .get("body", {}).get("mrr_at_20") == "0.823546"
        and source["variants"][SOURCE_VARIANT]["metrics"]["body"]
        ["relevant_at_20"] == 120,
        "v13_44_source_observation_invalid",
    )
    python_root = arguments.python_root.resolve(strict=True)
    sys.path.insert(0, str(python_root))
    from ishikawa.canonical import canonical_json_bytes
    from ishikawa.chunking import METHOD_PROFILE_ID, build_chunk_candidates

    chunks = build_chunk_candidates(normalized_source)
    chunk_sha256 = hashlib.sha256(canonical_json_bytes(chunks)).hexdigest()
    base.require(
        METHOD_PROFILE_ID == arguments.chunk_profile_id
        and chunks.get("method_profile_id") == arguments.chunk_profile_id
        and chunk_sha256 == arguments.expected_chunks_sha256
        and len(chunks.get("documents", [])) == 30
        and sum(len(item["candidates"]) for item in chunks["documents"]) == 943,
        "accepted_v6_chunks_changed",
    )
    raw_chunks = {
        candidate["chunk_id"]: candidate
        for document in chunks["documents"]
        for candidate in document["candidates"]
    }
    cases = {item.case_id: item for item in v3.load_cases(truth)}
    source_reference = source["variants"]["accepted_v6"]["results"]["selection"]
    source_candidate = source["variants"][SOURCE_VARIANT]["results"]["selection"]
    source_expansion = source["variants"][SOURCE_VARIANT]["results"][
        "expanded_atomic_diagnostic"
    ]
    base.require(
        len(cases) == len(source_reference) == len(source_candidate)
        == len(source_expansion) == 180,
        "case_inventory_invalid",
    )
    reference_by_case = {item["case_id"]: item for item in source_reference}
    candidate_by_case = {item["case_id"]: item for item in source_candidate}
    base.require(
        set(cases) == set(reference_by_case) == set(candidate_by_case)
        and all(
            hashlib.sha256(cases[case_id].question.encode("utf-8")).hexdigest()
            == candidate_by_case[case_id]["query_sha256"]
            for case_id in cases
        ),
        "case_identity_mismatch",
    )

    started = time.perf_counter_ns()
    selections: dict[str, list[dict[str, Any]]] = {
        REFERENCE_VARIANT: copy.deepcopy(source_candidate)
    }
    for name in VARIANT_ORDER:
        selections[name] = []
    for source_result in source_candidate:
        case_id = source_result["case_id"]
        if source_result["family"] != "body":
            for name in VARIANT_ORDER:
                copied = copy.deepcopy(source_result)
                copied["score_calibration_config"] = None
                copied["score_calibration_source"] = SOURCE_VARIANT
                selections[name].append(copied)
            continue
        matrix = feature_matrix(
            reference_by_case[case_id], source_result,
            cases[case_id].question, raw_chunks,
        )
        for name in VARIANT_ORDER:
            fused = rerank(source_result, matrix, CONFIG_BY_NAME[name])
            selections[name].append(
                measured_result(source_result, fused, CONFIG_BY_NAME[name])
            )
    base.require(
        all(len(items) == 180 for items in selections.values()),
        "variant_case_coverage_invalid",
    )
    variants = {
        REFERENCE_VARIANT: copy.deepcopy(source["variants"][SOURCE_VARIANT])
    }
    for name in VARIANT_ORDER:
        variants[name] = v41.summarize_variant(selections[name], source_expansion)
        variants[name]["rank_movement"] = v44._rank_movements(
            selections[REFERENCE_VARIANT], selections[name]
        )
    elapsed_ms = (time.perf_counter_ns() - started) / 1_000_000
    qualified = [
        name for name in VARIANT_ORDER
        if variants[name]["gate"]["status"] == "qualified"
    ]
    selected = max(qualified, key=lambda name: selection_key(name, variants[name])) \
        if qualified else None
    artifact: dict[str, Any] = {
        "artifact_kind": "ishikawa_v13_46_score_calibrated_global_reranking_experiment",
        "schema_version": 1,
        "corpus_identity": "synthetic-corpus-v3",
        "measurement_class": "evaluation_only_no_promotion",
        "source_sha256": {
            "v13_44_observation": arguments.expected_source_observation_sha256,
            "normalized_corpus": arguments.expected_normalized_sha256,
            "retrieval_truth": arguments.expected_truth_sha256,
            "accepted_v6_chunks": chunk_sha256,
        },
        "profiles": {
            "chunk_profile_id": arguments.chunk_profile_id,
            "retrieval_profile_id": arguments.retrieval_profile_id,
        },
        "experiment": {
            "source_variant": SOURCE_VARIANT,
            "reference_variant": REFERENCE_VARIANT,
            "variant_order": list(VARIANT_ORDER),
            "variant_configs": CONFIG_BY_NAME,
            "feature_order": list(FEATURES),
            "score_normalization": "query_local_min_max_nonhits_zero",
            "heading_path_signal": "normalized_nonstopword_jaccard",
            "final_tie_breaks": [
                "heading_path_overlap_desc", "baseline_rrf_desc",
                "v13_44_source_rank_asc", "chunk_id_asc",
            ],
            "body_mrr_gate": "0.89",
            "body_coverage_gate": "120/120",
            "candidate_pool": "unchanged_v13_44_top_20",
            "learned_reranker": False,
        },
        "candidate_inventory": source["candidate_inventory"],
        "case_inventory": source["case_inventory"],
        "runtime_identity_digest": source["runtime_identity_digest"],
        "latency_ms": {"score_calibration_and_measurement": format(elapsed_ms, ".3f")},
        "variants": variants,
        "qualified_candidates": qualified,
        "selected_candidate": selected,
        "selection_status": "qualified_for_separate_implementation" if selected else "not_met",
        "boundaries": {
            "accepted_database_contact": False,
            "accepted_database_write": False,
            "black_corpus_access": False,
            "corpus_ingestion": False,
            "corpus_v3_changed": False,
            "gemma_contact": False,
            "nomic_contact": False,
            "postgresql_contact": False,
            "production_profile_changed": False,
            "question_text_retained": False,
            "source_text_retained": False,
            "structural_path_text_retained": False,
            "vectors_retained": False,
            "retained_runtime_flat_file_index": False,
        },
        "promotion_authorized": False,
        "next_gate": (
            "freeze_selected_candidate_then_implement_and_qualify_application"
            if selected else "stop_heuristic_tuning_and_discuss_dedicated_reranker"
        ),
    }
    identity = {
        key: value for key, value in artifact.items()
        if key not in {"latency_ms", "variants"}
    }
    artifact["experiment_id"] = base.domain_digest(
        "ishikawa.v13-46-score-calibrated-global-reranking-experiment.v1", identity
    )
    base.write_exclusive(arguments.output, base.canonical_json_bytes(artifact) + b"\n")
    print("purpose=measure_v13_46_score_calibrated_global_reranking")
    for name in (REFERENCE_VARIANT, *VARIANT_ORDER):
        body = variants[name]["metrics"]["body"]
        movement = variants[name].get("rank_movement")
        movement_text = "reference" if movement is None else (
            f"improved:{movement['improved']},unchanged:{movement['unchanged']},"
            f"regressed:{movement['regressed']},missing_fixed:{movement['missing_fixed']},"
            f"new_missing:{movement['new_missing']}"
        )
        print(
            f"variant={name};body_mrr_at_20={body['mrr_at_20']};"
            f"body_relevant_at_5={body['relevant_at_5']}/120;"
            f"body_relevant_at_20={body['relevant_at_20']}/120;"
            f"movement={movement_text};gate={variants[name]['gate']['status']}"
        )
    print(
        f"selection_status={artifact['selection_status']};"
        f"selected_candidate={selected or 'none'};promotion_authorized=false"
    )
    print("v13_46_score_calibrated_global_reranking_measurement=pass")


def self_test() -> None:
    assert normalized({"a": 2.0, "b": 4.0}) == {"a": 0.0, "b": 1.0}
    assert normalized({"a": 2.0, "b": 2.0}) == {"a": 1.0, "b": 1.0}
    assert heading_overlap(
        "What incident response is required?", ["III. Incident Response"]
    ) > heading_overlap(
        "What incident response is required?", ["V. Records Retention"]
    )
    assert len(VARIANT_ORDER) == len(set(VARIANT_ORDER)) == 5
    assert set(CONFIG_BY_NAME) == set(VARIANT_ORDER)
    assert all(set(config) == set(FEATURES) for config in CONFIG_BY_NAME.values())
    assert all(config["heading_path_overlap"] > 0 for config in CONFIG_BY_NAME.values())
    assert all(
        config["document_lexical_affinity"] + config["document_vector_affinity"] > 0
        for config in CONFIG_BY_NAME.values()
    )
    print("v13_46_score_calibrated_global_reranking_measurement_self_test=pass")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--python-root", type=Path)
    parser.add_argument("--source-observation", type=Path)
    parser.add_argument("--expected-source-observation-sha256")
    parser.add_argument("--normalized", type=Path)
    parser.add_argument("--expected-normalized-sha256")
    parser.add_argument("--truth", type=Path)
    parser.add_argument("--expected-truth-sha256")
    parser.add_argument("--expected-chunks-sha256")
    parser.add_argument("--chunk-profile-id")
    parser.add_argument("--retrieval-profile-id")
    parser.add_argument("--output", type=Path)
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
        return 0
    required = (
        arguments.python_root, arguments.source_observation,
        arguments.expected_source_observation_sha256, arguments.normalized,
        arguments.expected_normalized_sha256, arguments.truth,
        arguments.expected_truth_sha256, arguments.expected_chunks_sha256,
        arguments.chunk_profile_id, arguments.retrieval_profile_id, arguments.output,
    )
    if any(value is None for value in required):
        parser.error("measurement arguments are required without --self-test")
    try:
        execute(arguments)
    except (base.MeasurementError, OSError, ValueError, KeyError, AssertionError) as error:
        print(
            f"v13_46_score_calibrated_global_reranking_measurement=blocked;reason={error}",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
