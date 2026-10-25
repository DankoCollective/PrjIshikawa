#!/usr/bin/env python3
"""Search bounded fusion profiles on the promoted corpus-v2 retrieval baseline."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import sys
import time
from fractions import Fraction
from itertools import product
from pathlib import Path
from typing import Any, Mapping, Sequence

import measure_published_v2_section_page_experiment as experiment
import measure_synthetic_corpus_v2_candidate_profile as candidate_measurement
import measure_synthetic_corpus_v2_without_ingestion as base


RRF_CONSTANTS = (10, 20, 40, 60, 80, 100)
LEXICAL_WEIGHTS = (1, 2, 3, 4, 5, 6, 8)
VECTOR_WEIGHTS = (1, 2, 3, 4, 5, 6, 8)
LANE_DEPTHS = (10, 15, 20)
PROFILE_COUNT = 6 * 7 * 7 * 3 * 3
PROMOTED_VARIANT = "section_page_duplicate_canonical"
PROMOTED_PROFILE = {
    "rrf_constant": 60,
    "exact_weight": 1,
    "lexical_weight": 1,
    "vector_weight": 4,
    "lexical_depth": 20,
    "vector_depth": 20,
}


def profile_distance(profile: Mapping[str, int]) -> int:
    return (
        abs(profile["rrf_constant"] - PROMOTED_PROFILE["rrf_constant"]) // 10
        + abs(profile["lexical_weight"] - PROMOTED_PROFILE["lexical_weight"])
        + abs(profile["vector_weight"] - PROMOTED_PROFILE["vector_weight"])
        + abs(profile["lexical_depth"] - PROMOTED_PROFILE["lexical_depth"]) // 5
        + abs(profile["vector_depth"] - PROMOTED_PROFILE["vector_depth"]) // 5
    )


def result_sort_key(result: Mapping[str, Any]) -> tuple[Any, ...]:
    metrics = result["body_metrics"]
    mrr = Fraction(
        metrics["mrr_fraction_numerator"], metrics["mrr_fraction_denominator"]
    )
    return (
        -int(result["acceptance_gate_met"]),
        -mrr,
        -metrics["relevant_at_5"],
        len(result["regressed_body_case_ids"]),
        result["profile_distance_from_promoted"],
        json.dumps(result["profile"], sort_keys=True),
    )


def evaluate_profile(
    cached_cases: Sequence[dict[str, Any]],
    profile: Mapping[str, int],
    by_chunk: Mapping[str, base.CandidateRecord],
    group_by_chunk: Mapping[str, tuple[Any, ...]],
    fuse: Any,
    baseline_ranks: Mapping[str, int],
) -> dict[str, Any]:
    results: list[dict[str, Any]] = []
    case_ranks: dict[str, int | None] = {}
    for cached in cached_cases:
        fused = fuse(
            {
                "exact": cached["exact"],
                "lexical": cached["lexical"][: profile["lexical_depth"]],
                "vector": cached["vector"][: profile["vector_depth"]],
            },
            rrf_constant=profile["rrf_constant"],
            lane_weights={
                "exact": profile["exact_weight"],
                "lexical": profile["lexical_weight"],
                "vector": profile["vector_weight"],
            },
        )
        if cached["section_page_route"]:
            fused = experiment.collapse_groups(fused, group_by_chunk)
        measured = base.measure_case(
            cached["case"],
            cached["exact"],
            cached["lexical"],
            cached["vector"],
            fused[:20],
            cached["permitted_atomic"],
            by_chunk,
        )
        results.append(measured)
        case_ranks[measured["case_id"]] = measured["first_relevant_rank"]
    body = base.aggregate(results[:base.BODY_CASE_COUNT])
    header = base.aggregate(results[base.BODY_CASE_COUNT:])
    regressed = sorted(
        case_id
        for case_id, rank in case_ranks.items()
        if case_id.startswith("E-")
        and (rank is None or rank > baseline_ranks[case_id])
    )
    improved = sorted(
        case_id
        for case_id, rank in case_ranks.items()
        if case_id.startswith("E-")
        and rank is not None
        and rank < baseline_ranks[case_id]
    )
    gate_met = (
        Fraction(body["mrr_fraction_numerator"], body["mrr_fraction_denominator"])
        >= Fraction(89, 100)
        and body["relevant_at_20"] == 60
        and body["required_evidence_matched_at_20"] == 60
        and body["required_evidence_total"] == 60
        and header["mrr_at_20"] == "1.000000"
        and header["relevant_at_5"] == 8
        and header["required_evidence_matched_at_20"] == 11
        and header["required_evidence_total"] == 11
    )
    return {
        "acceptance_gate_met": gate_met,
        "body_metrics": body,
        "case_ranks": case_ranks,
        "header_metrics": header,
        "improved_body_case_ids": improved,
        "profile": dict(profile),
        "profile_distance_from_promoted": profile_distance(profile),
        "regressed_body_case_ids": regressed,
    }


def execute(arguments: argparse.Namespace) -> int:
    python_root = arguments.python_root.resolve(strict=True)
    sys.path.insert(0, str(python_root))
    from embed_document_candidates_via_endpoint import EndpointClient, wipe
    from ishikawa.retrieval import LaneCandidate, reciprocal_rank_fusion

    baseline_receipt = experiment.load(
        arguments.baseline_receipt,
        arguments.expected_baseline_receipt_sha256,
        2 * 1024 * 1024,
    )
    design = experiment.load(
        arguments.design, arguments.expected_design_sha256, 4 * 1024 * 1024
    )
    atomic_source = experiment.load(
        arguments.atomic_chunks,
        arguments.expected_atomic_chunks_sha256,
        32 * 1024 * 1024,
    )
    representative_source = experiment.load(
        arguments.representatives,
        arguments.expected_representatives_sha256,
        32 * 1024 * 1024,
    )
    atomic_embeddings_source = experiment.load(
        arguments.atomic_embeddings,
        arguments.expected_atomic_embeddings_sha256,
        192 * 1024 * 1024,
    )
    representative_embeddings_source = experiment.load(
        arguments.representative_embeddings,
        arguments.expected_representative_embeddings_sha256,
        64 * 1024 * 1024,
    )
    body_source = experiment.load(
        arguments.body_cases, arguments.expected_body_cases_sha256, 2 * 1024 * 1024
    )
    header_source = experiment.load(
        arguments.header_cases,
        arguments.expected_header_cases_sha256,
        1024 * 1024,
    )
    arguments.normalized = arguments.normalized.resolve(strict=True)
    arguments.promotion_bundle = arguments.promotion_bundle.resolve(strict=True)
    promotion_manifest = arguments.promotion_bundle / "SHA256SUMS"

    base.require(
        baseline_receipt.get("artifact_kind")
        == "ishikawa_synthetic_corpus_v2_retrieval_optimization_baseline"
        and baseline_receipt.get("state")
        == "promoted_frozen_optimization_baseline"
        and baseline_receipt.get("decision", {}).get("id") == "V13-31"
        and baseline_receipt.get("accepted_gate", {}).get("body_mrr_at_20")
        == ">=0.890000"
        and baseline_receipt.get("selected_variant", {}).get("name")
        == PROMOTED_VARIANT
        and baseline_receipt.get("selected_variant", {})
        .get("metrics", {})
        .get("body", {})
        .get("mrr_at_20")
        == "0.903333"
        and baseline_receipt.get("next_gate")
        == "optimize_frozen_synthetic_corpus_v2_retrieval_baseline",
        "baseline_receipt_invalid",
    )
    base.require(
        baseline_receipt.get("retrieval_profile") == design.get("frozen_profile")
        and design.get("artifact_kind")
        == "ishikawa_published_synthetic_corpus_v2_section_page_experiment_design"
        and any(
            item == {
                "document_local_duplicate_canonicalization": True,
                "name": PROMOTED_VARIANT,
                "section_page_representatives": True,
            }
            for item in design.get("variants", [])
        ),
        "promoted_variant_contract_invalid",
    )
    base.require(
        arguments.normalized.is_file()
        and not arguments.normalized.is_symlink()
        and base.sha256_file(arguments.normalized)
        == arguments.expected_normalized_sha256
        and arguments.promotion_bundle.is_dir()
        and not arguments.promotion_bundle.is_symlink()
        and promotion_manifest.is_file()
        and not promotion_manifest.is_symlink()
        and base.sha256_file(promotion_manifest)
        == arguments.expected_promotion_manifest_sha256,
        "published_identity_source_invalid",
    )

    raw_atomic = experiment.remapped_candidates(atomic_source, 139)
    representatives = experiment.remapped_candidates(representative_source, 29)
    atomic, raw_to_published = experiment.published_atomic_candidates(
        raw_atomic,
        atomic_source,
        arguments.normalized,
        arguments.atomic_chunks,
        arguments.atomic_embeddings,
        arguments.promotion_bundle,
    )
    by_chunk = {item.chunk_id: item for item in atomic + representatives}
    base.require(len(by_chunk) == 168, "combined_candidate_inventory_invalid")
    raw_atomic_vectors = base.validate_embedding_artifact(
        atomic_embeddings_source,
        arguments.expected_atomic_chunks_sha256,
        raw_atomic,
    )
    representative_vectors = base.validate_embedding_artifact(
        representative_embeddings_source,
        arguments.expected_representatives_sha256,
        representatives,
    )
    base.require(
        atomic_embeddings_source["embedding_space_id"]
        == representative_embeddings_source["embedding_space_id"],
        "embedding_space_mismatch",
    )
    vectors = {
        **{
            raw_to_published[raw_id]: vector
            for raw_id, vector in raw_atomic_vectors.items()
        },
        **representative_vectors,
    }
    group_by_chunk, canonical = experiment.artifact_indexes(
        atomic_source, representative_source, raw_to_published
    )
    cases = (
        candidate_measurement.load_v2_body_cases(body_source)
        + base.load_header_cases(header_source)
    )
    base.require(len(cases) == 68, "case_inventory_invalid")

    secret_text = os.environ.pop("ISHIKAWA_NOMIC_API_KEY", "")
    base.require(
        32 <= len(secret_text) <= 1024 and "\n" not in secret_text,
        "nomic_credential_invalid",
    )
    secret = bytearray(secret_text.encode("utf-8"))
    secret_text = ""
    try:
        client = EndpointClient(
            arguments.embedding_url, arguments.tokenizer_url, secret
        )
        base.require(
            client.model_identity()
            == atomic_embeddings_source["runtime_identity_digest"],
            "embedding_runtime_identity_changed",
        )
        query_vectors: list[list[float]] = []
        query_tokens = 0
        inputs = [base.QUERY_PREFIX + case.question for case in cases]
        for start in range(0, len(inputs), 16):
            batch, usage = client.embeddings(inputs[start : start + 16])
            query_vectors.extend(batch)
            query_tokens += usage
    finally:
        if "client" in locals():
            client.close()
        wipe(secret)
    base.require(len(query_vectors) == 68, "query_embedding_coverage_invalid")

    try:
        import psycopg

        connection = psycopg.connect(
            host=str(arguments.postgresql_socket),
            port=arguments.postgresql_port,
            dbname="postgres",
            user=arguments.postgresql_user,
            connect_timeout=5,
        )
    except Exception as error:
        raise base.MeasurementError("temporary_postgresql_connection_failed") from error

    cached_cases: list[dict[str, Any]] = []
    lane_capture_started = time.perf_counter()
    try:
        connection.execute("BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
        state = connection.execute(
            "SELECT current_setting('transaction_read_only'), current_database(), current_user"
        ).fetchone()
        base.require(
            state == ("on", "postgres", arguments.postgresql_user),
            "database_boundary_invalid",
        )
        for case, query_vector in zip(cases, query_vectors, strict=True):
            permitted_atomic = base.permitted_candidates(case, atomic)
            exact = base.exact_lane(case, permitted_atomic, LaneCandidate)
            section_page_route = case.family == "body" and not exact
            duplicate_canonical_route = case.family == "body" and not exact
            permitted_refs = {item.document_ref for item in permitted_atomic}
            searchable_atomic = tuple(
                item
                for item in permitted_atomic
                if not duplicate_canonical_route
                or item.projection_kind == "document_control_metadata"
                or item.chunk_id in canonical
            )
            permitted_representatives = tuple(
                item
                for item in representatives
                if item.document_ref in permitted_refs
            )
            searchable = searchable_atomic + (
                permitted_representatives if section_page_route else ()
            )
            lexical = base.lexical_lane(
                connection, case.question, searchable, by_chunk, LaneCandidate
            )
            vector = base.vector_lane(
                query_vector, searchable, vectors, LaneCandidate
            )
            cached_cases.append(
                {
                    "case": case,
                    "duplicate_canonical_route": duplicate_canonical_route,
                    "exact": exact,
                    "lexical": lexical,
                    "permitted_atomic": permitted_atomic,
                    "searchable_candidate_count": len(searchable),
                    "section_page_route": section_page_route,
                    "vector": vector,
                }
            )
        connection.rollback()
    finally:
        connection.close()
    lane_capture_elapsed_ms = int((time.perf_counter() - lane_capture_started) * 1000)
    base.require(len(cached_cases) == 68, "lane_capture_incomplete")

    empty_baseline_ranks = {
        case.case_id: 20 for case in cases if case.family == "body"
    }
    promoted = evaluate_profile(
        cached_cases,
        PROMOTED_PROFILE,
        by_chunk,
        group_by_chunk,
        reciprocal_rank_fusion,
        empty_baseline_ranks,
    )
    expected_body = baseline_receipt["selected_variant"]["metrics"]["body"]
    expected_header = baseline_receipt["selected_variant"]["metrics"]["header"]
    base.require(
        promoted["body_metrics"] == expected_body
        and promoted["header_metrics"] == expected_header,
        "promoted_baseline_replay_drift",
    )
    baseline_ranks = {
        case_id: int(rank)
        for case_id, rank in promoted["case_ranks"].items()
        if case_id.startswith("E-") and rank is not None
    }
    base.require(len(baseline_ranks) == 60, "promoted_baseline_rank_inventory_invalid")
    promoted = evaluate_profile(
        cached_cases,
        PROMOTED_PROFILE,
        by_chunk,
        group_by_chunk,
        reciprocal_rank_fusion,
        baseline_ranks,
    )

    search_started = time.perf_counter()
    results: list[dict[str, Any]] = []
    for rrf_constant, lexical_weight, vector_weight, lexical_depth, vector_depth in product(
        RRF_CONSTANTS,
        LEXICAL_WEIGHTS,
        VECTOR_WEIGHTS,
        LANE_DEPTHS,
        LANE_DEPTHS,
    ):
        profile = {
            "rrf_constant": rrf_constant,
            "exact_weight": 1,
            "lexical_weight": lexical_weight,
            "vector_weight": vector_weight,
            "lexical_depth": lexical_depth,
            "vector_depth": vector_depth,
        }
        results.append(
            evaluate_profile(
                cached_cases,
                profile,
                by_chunk,
                group_by_chunk,
                reciprocal_rank_fusion,
                baseline_ranks,
            )
        )
    search_elapsed_ms = int((time.perf_counter() - search_started) * 1000)
    base.require(len(results) == PROFILE_COUNT, "search_space_invalid")
    results.sort(key=result_sort_key)
    replayed_promoted = next(
        item for item in results if item["profile"] == PROMOTED_PROFILE
    )
    base.require(
        replayed_promoted["body_metrics"] == promoted["body_metrics"]
        and replayed_promoted["header_metrics"] == promoted["header_metrics"]
        and replayed_promoted["case_ranks"] == promoted["case_ranks"],
        "promoted_profile_search_replay_drift",
    )
    best = results[0]
    finalist_replay = evaluate_profile(
        cached_cases,
        best["profile"],
        by_chunk,
        group_by_chunk,
        reciprocal_rank_fusion,
        baseline_ranks,
    )
    base.require(best == finalist_replay, "best_finalist_replay_drift")
    qualifying_count = sum(item["acceptance_gate_met"] for item in results)
    no_regression_count = sum(
        item["acceptance_gate_met"] and not item["regressed_body_case_ids"]
        for item in results
    )
    finalists = copy.deepcopy(results[:25])
    for item in finalists:
        item.pop("case_ranks")
    promoted_summary = copy.deepcopy(replayed_promoted)
    promoted_summary.pop("case_ranks")
    best_summary = copy.deepcopy(best)
    best_summary.pop("case_ranks")

    artifact: dict[str, Any] = {
        "artifact_kind": "ishikawa_promoted_v2_section_page_optimization_search",
        "baseline_replay": promoted_summary,
        "boundaries": {
            "accepted_database_contact": False,
            "black_corpus_access": False,
            "candidate_promoted": False,
            "corpus_changed": False,
            "database_tables_read": False,
            "database_write": False,
            "gemma_contact": False,
            "nomic_contact": True,
            "private_temporary_postgresql": True,
            "production_profile_changed": False,
            "truth_changed": False,
        },
        "best_observed_profile": best_summary,
        "deterministic_finalist_replay": True,
        "finalists": finalists,
        "inventory": {
            "atomic_candidates": 139,
            "cases": 68,
            "maximum_pre_collapse_candidates": 168,
            "query_embedding_tokens": query_tokens,
            "section_page_representatives": 29,
        },
        "measurement": {
            "finalist_latency_requires_live_remeasurement": True,
            "lane_capture_elapsed_ms": lane_capture_elapsed_ms,
            "profile_search_elapsed_ms": search_elapsed_ms,
        },
        "next_gate": "review_promoted_baseline_optimization_finalists_before_profile_freeze",
        "profile_counts": {
            "acceptance_gate": qualifying_count,
            "acceptance_gate_without_body_regressions": no_regression_count,
            "evaluated": len(results),
        },
        "schema_version": 1,
        "search_space": {
            "exact_weight": 1,
            "lane_depth_limit": 20,
            "lexical_depths": list(LANE_DEPTHS),
            "lexical_weights": list(LEXICAL_WEIGHTS),
            "profile_count": PROFILE_COUNT,
            "rrf_constants": list(RRF_CONSTANTS),
            "vector_depths": list(LANE_DEPTHS),
            "vector_weights": list(VECTOR_WEIGHTS),
        },
        "selection_rules": {
            "body_mrr_at_20": ">=0.890000",
            "body_relevant_at_20": "60/60",
            "body_required_evidence_at_20": "60/60",
            "header_mrr_at_20": "1.000000",
            "header_relevant_at_5": "8/8",
            "header_required_evidence_at_20": "11/11",
            "offline_search_authorizes_profile_promotion": False,
            "ranking": [
                "acceptance_gate",
                "highest_body_mrr_at_20",
                "highest_body_relevant_at_5",
                "fewest_regressed_body_cases",
                "shortest_distance_from_promoted_profile",
            ],
        },
        "source_sha256": {
            "atomic_chunks": arguments.expected_atomic_chunks_sha256,
            "atomic_embeddings": arguments.expected_atomic_embeddings_sha256,
            "baseline_receipt": arguments.expected_baseline_receipt_sha256,
            "body_truth": arguments.expected_body_cases_sha256,
            "design": arguments.expected_design_sha256,
            "header_truth": arguments.expected_header_cases_sha256,
            "normalized": arguments.expected_normalized_sha256,
            "promotion_manifest": arguments.expected_promotion_manifest_sha256,
            "representative_embeddings": arguments.expected_representative_embeddings_sha256,
            "representatives": arguments.expected_representatives_sha256,
        },
    }
    artifact["observation_set_id"] = base.domain_digest(
        "ishikawa.promoted-v2-section-page-optimization-search.v1", artifact
    )
    payload = base.canonical_json_bytes(artifact) + b"\n"
    base.write_exclusive(arguments.output, payload)
    print("purpose=search_promoted_v2_section_page_retrieval_optimizations")
    print(
        f"profiles_evaluated={len(results)};acceptance_gate_profiles={qualifying_count};"
        f"no_regression_profiles={no_regression_count}"
    )
    print(
        f"baseline_body_mrr_at_20={promoted['body_metrics']['mrr_at_20']};"
        f"baseline_body_relevant_at_5={promoted['body_metrics']['relevant_at_5']}/60;"
        f"baseline_body_relevant_at_20={promoted['body_metrics']['relevant_at_20']}/60"
    )
    print(
        "best_profile="
        + json.dumps(best["profile"], sort_keys=True, separators=(",", ":"))
    )
    print(
        f"best_body_mrr_at_20={best['body_metrics']['mrr_at_20']};"
        f"best_body_relevant_at_5={best['body_metrics']['relevant_at_5']}/60;"
        f"best_body_relevant_at_20={best['body_metrics']['relevant_at_20']}/60;"
        f"best_regressed_body_cases={len(best['regressed_body_case_ids'])}"
    )
    print(
        f"lane_capture_elapsed_ms={lane_capture_elapsed_ms};"
        f"profile_search_elapsed_ms={search_elapsed_ms};"
        f"query_embedding_tokens={query_tokens}"
    )
    print(f"artifact_sha256={hashlib.sha256(payload).hexdigest()}")
    print("promoted_v2_section_page_optimization_search=pass")
    return 0


def self_test() -> int:
    assert PROFILE_COUNT == 2646
    assert profile_distance(PROMOTED_PROFILE) == 0
    sample = {
        "acceptance_gate_met": True,
        "body_metrics": {
            "mrr_fraction_numerator": 9,
            "mrr_fraction_denominator": 10,
            "relevant_at_5": 60,
        },
        "profile": PROMOTED_PROFILE,
        "profile_distance_from_promoted": 0,
        "regressed_body_case_ids": [],
    }
    assert result_sort_key(sample)[0:5] == (-1, Fraction(-9, 10), -60, 0, 0)
    print("promoted_v2_section_page_optimization_search_self_test=pass")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--python-root", type=Path)
    parser.add_argument("--baseline-receipt", type=Path)
    parser.add_argument("--expected-baseline-receipt-sha256")
    parser.add_argument("--design", type=Path)
    parser.add_argument("--expected-design-sha256")
    parser.add_argument("--atomic-chunks", type=Path)
    parser.add_argument("--expected-atomic-chunks-sha256")
    parser.add_argument("--representatives", type=Path)
    parser.add_argument("--expected-representatives-sha256")
    parser.add_argument("--atomic-embeddings", type=Path)
    parser.add_argument("--expected-atomic-embeddings-sha256")
    parser.add_argument("--normalized", type=Path)
    parser.add_argument("--expected-normalized-sha256")
    parser.add_argument("--promotion-bundle", type=Path)
    parser.add_argument("--expected-promotion-manifest-sha256")
    parser.add_argument("--representative-embeddings", type=Path)
    parser.add_argument("--expected-representative-embeddings-sha256")
    parser.add_argument("--body-cases", type=Path)
    parser.add_argument("--expected-body-cases-sha256")
    parser.add_argument("--header-cases", type=Path)
    parser.add_argument("--expected-header-cases-sha256")
    parser.add_argument("--embedding-url", default="http://127.0.0.1:8001/v1/embeddings")
    parser.add_argument("--tokenizer-url", default="http://127.0.0.1:8001/tokenize")
    parser.add_argument("--postgresql-socket", type=Path)
    parser.add_argument("--postgresql-port", type=int)
    parser.add_argument("--postgresql-user")
    parser.add_argument("--output", type=Path)
    arguments = parser.parse_args()
    if arguments.self_test:
        base.require(not arguments.run, "mode_invalid")
        return self_test()
    required = (
        arguments.run,
        arguments.python_root,
        arguments.baseline_receipt,
        arguments.expected_baseline_receipt_sha256,
        arguments.design,
        arguments.expected_design_sha256,
        arguments.atomic_chunks,
        arguments.expected_atomic_chunks_sha256,
        arguments.representatives,
        arguments.expected_representatives_sha256,
        arguments.atomic_embeddings,
        arguments.expected_atomic_embeddings_sha256,
        arguments.normalized,
        arguments.expected_normalized_sha256,
        arguments.promotion_bundle,
        arguments.expected_promotion_manifest_sha256,
        arguments.representative_embeddings,
        arguments.expected_representative_embeddings_sha256,
        arguments.body_cases,
        arguments.expected_body_cases_sha256,
        arguments.header_cases,
        arguments.expected_header_cases_sha256,
        arguments.postgresql_socket,
        arguments.postgresql_port,
        arguments.postgresql_user,
        arguments.output,
    )
    base.require(all(value is not None for value in required), "arguments_incomplete")
    base.require(
        arguments.postgresql_socket.is_absolute()
        and str(arguments.postgresql_socket).startswith("/tmp/")
        and 1024 <= arguments.postgresql_port <= 65535,
        "runtime_boundary_invalid",
    )
    return execute(arguments)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except base.MeasurementError as error:
        print(
            f"promoted_v2_section_page_optimization_search=blocked;reason={error}",
            file=sys.stderr,
        )
        raise SystemExit(1)
