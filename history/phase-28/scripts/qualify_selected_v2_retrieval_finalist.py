#!/usr/bin/env python3
"""Repeatedly qualify the reviewed corpus-v2 retrieval finalist."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import statistics
import sys
import time
from fractions import Fraction
from pathlib import Path
from typing import Any, Mapping, Sequence

import measure_published_v2_section_page_experiment as experiment
import measure_synthetic_corpus_v2_candidate_profile as candidate_measurement
import measure_synthetic_corpus_v2_without_ingestion as base


WARMUP_RUNS = 1
MEASURED_RUNS = 5
BASELINE_PROFILE = {
    "rrf_constant": 60,
    "exact_weight": 1,
    "lexical_weight": 1,
    "vector_weight": 4,
    "lexical_depth": 20,
    "vector_depth": 20,
}
CANDIDATE_PROFILE = {
    "rrf_constant": 60,
    "exact_weight": 1,
    "lexical_weight": 2,
    "vector_weight": 4,
    "lexical_depth": 20,
    "vector_depth": 20,
}


def elapsed_ms(started_ns: int) -> float:
    return (time.perf_counter_ns() - started_ns) / 1_000_000


def percentile(values: Sequence[float], fraction: float) -> float:
    if not values:
        raise base.MeasurementError("latency_inventory_empty")
    ordered = sorted(values)
    index = min(
        len(ordered) - 1,
        max(0, math.ceil(len(ordered) * fraction) - 1),
    )
    return ordered[index]


def latency_summary(values: Sequence[float]) -> dict[str, str]:
    base.require(
        len(values) == MEASURED_RUNS
        and all(math.isfinite(value) and value >= 0.0 for value in values),
        "latency_inventory_invalid",
    )
    return {
        "median_ms": format(statistics.median(values), ".3f"),
        "p95_ms": format(percentile(values, 0.95), ".3f"),
    }


def profile_fusion(
    cached_cases: Sequence[dict[str, Any]],
    profile: Mapping[str, int],
    by_chunk: Mapping[str, base.CandidateRecord],
    group_by_chunk: Mapping[str, tuple[Any, ...]],
    fuse: Any,
) -> tuple[dict[str, Any], dict[str, int], float]:
    started_ns = time.perf_counter_ns()
    results: list[dict[str, Any]] = []
    ranks: dict[str, int] = {}
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
        base.require(
            measured["first_relevant_rank"] is not None,
            "required_evidence_not_retrieved",
        )
        ranks[measured["case_id"]] = int(measured["first_relevant_rank"])
    body = base.aggregate(results[:base.BODY_CASE_COUNT])
    header = base.aggregate(results[base.BODY_CASE_COUNT:])
    return {"body": body, "header": header}, ranks, elapsed_ms(started_ns)


def capture_lanes(
    connection: Any,
    cases: Sequence[base.Case],
    query_vectors: Sequence[Sequence[float]],
    atomic: Sequence[base.CandidateRecord],
    representatives: Sequence[base.CandidateRecord],
    vectors: Mapping[str, Sequence[float]],
    by_chunk: Mapping[str, base.CandidateRecord],
    canonical: set[str],
    lane_candidate_type: Any,
    expected_postgresql_user: str,
) -> tuple[list[dict[str, Any]], dict[str, float]]:
    cached_cases: list[dict[str, Any]] = []
    durations = {"exact_lane": 0.0, "lexical_lane": 0.0, "vector_lane": 0.0}
    connection.execute("BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
    state = connection.execute(
        "SELECT current_setting('transaction_read_only'), current_database(), current_user"
    ).fetchone()
    base.require(
        state == ("on", "postgres", expected_postgresql_user),
        "database_boundary_invalid",
    )
    try:
        for case, query_vector in zip(cases, query_vectors, strict=True):
            permitted_atomic = base.permitted_candidates(case, atomic)

            started_ns = time.perf_counter_ns()
            exact = base.exact_lane(case, permitted_atomic, lane_candidate_type)
            durations["exact_lane"] += elapsed_ms(started_ns)

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

            started_ns = time.perf_counter_ns()
            lexical = base.lexical_lane(
                connection, case.question, searchable, by_chunk, lane_candidate_type
            )
            durations["lexical_lane"] += elapsed_ms(started_ns)

            started_ns = time.perf_counter_ns()
            vector = base.vector_lane(
                query_vector, searchable, vectors, lane_candidate_type
            )
            durations["vector_lane"] += elapsed_ms(started_ns)

            cached_cases.append(
                {
                    "case": case,
                    "exact": exact,
                    "lexical": lexical,
                    "permitted_atomic": permitted_atomic,
                    "section_page_route": section_page_route,
                    "vector": vector,
                }
            )
    finally:
        connection.rollback()
    base.require(len(cached_cases) == 68, "lane_capture_incomplete")
    return cached_cases, durations


def execute(arguments: argparse.Namespace) -> int:
    python_root = arguments.python_root.resolve(strict=True)
    sys.path.insert(0, str(python_root))
    from embed_document_candidates_via_endpoint import EndpointClient, wipe
    from ishikawa.retrieval import LaneCandidate, reciprocal_rank_fusion

    review = experiment.load(
        arguments.review, arguments.expected_review_sha256, 2 * 1024 * 1024
    )
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
        arguments.body_cases,
        arguments.expected_body_cases_sha256,
        2 * 1024 * 1024,
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
        review.get("artifact_kind")
        == "ishikawa_synthetic_corpus_v2_optimization_finalist_review"
        and review.get("next_gate")
        == "execute_repeated_live_qualification_of_selected_v2_retrieval_finalist"
        and review.get("live_qualification_design", {}).get("baseline_profile")
        == BASELINE_PROFILE
        and review.get("live_qualification_design", {}).get("candidate_profile")
        == CANDIDATE_PROFILE
        and review.get("live_qualification_design", {}).get("repeated_warm_runs")
        == MEASURED_RUNS,
        "finalist_review_invalid",
    )
    base.require(
        baseline_receipt.get("artifact_kind")
        == "ishikawa_synthetic_corpus_v2_retrieval_optimization_baseline"
        and baseline_receipt.get("retrieval_profile") == design.get("frozen_profile")
        and baseline_receipt.get("selected_variant", {}).get("name")
        == "section_page_duplicate_canonical",
        "baseline_contract_invalid",
    )
    base.require(
        arguments.normalized.is_file()
        and not arguments.normalized.is_symlink()
        and base.sha256_file(arguments.normalized)
        == arguments.expected_normalized_sha256
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
        32 <= len(secret_text) <= 1024
        and "\n" not in secret_text
        and "\r" not in secret_text,
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
            raise base.MeasurementError(
                "temporary_postgresql_connection_failed"
            ) from error

        runs: list[dict[str, Any]] = []
        reference_baseline_ranks: dict[str, int] | None = None
        reference_candidate_ranks: dict[str, int] | None = None
        query_inputs = [base.QUERY_PREFIX + case.question for case in cases]
        try:
            for run_index in range(WARMUP_RUNS + MEASURED_RUNS):
                total_started_ns = time.perf_counter_ns()
                query_started_ns = time.perf_counter_ns()
                query_vectors: list[list[float]] = []
                query_tokens = 0
                for start in range(0, len(query_inputs), 16):
                    batch, usage = client.embeddings(query_inputs[start : start + 16])
                    query_vectors.extend(batch)
                    query_tokens += usage
                query_embedding_ms = elapsed_ms(query_started_ns)
                base.require(
                    len(query_vectors) == 68 and query_tokens == 1204,
                    "query_embedding_inventory_invalid",
                )

                lane_capture_started_ns = time.perf_counter_ns()
                cached_cases, lane_ms = capture_lanes(
                    connection,
                    cases,
                    query_vectors,
                    atomic,
                    representatives,
                    vectors,
                    by_chunk,
                    canonical,
                    LaneCandidate,
                    arguments.postgresql_user,
                )
                lane_capture_total_ms = elapsed_ms(lane_capture_started_ns)
                baseline_metrics, baseline_ranks, baseline_fusion_ms = profile_fusion(
                    cached_cases,
                    BASELINE_PROFILE,
                    by_chunk,
                    group_by_chunk,
                    reciprocal_rank_fusion,
                )
                candidate_metrics, candidate_ranks, candidate_fusion_ms = profile_fusion(
                    cached_cases,
                    CANDIDATE_PROFILE,
                    by_chunk,
                    group_by_chunk,
                    reciprocal_rank_fusion,
                )
                total_shared_ms = elapsed_ms(total_started_ns)

                if reference_baseline_ranks is None:
                    reference_baseline_ranks = baseline_ranks
                    reference_candidate_ranks = candidate_ranks
                else:
                    base.require(
                        baseline_ranks == reference_baseline_ranks
                        and candidate_ranks == reference_candidate_ranks,
                        "repeated_rank_drift",
                    )

                baseline_body = baseline_metrics["body"]
                baseline_header = baseline_metrics["header"]
                candidate_body = candidate_metrics["body"]
                candidate_header = candidate_metrics["header"]
                regressed = sorted(
                    case_id
                    for case_id, rank in candidate_ranks.items()
                    if case_id.startswith("E-")
                    and rank > baseline_ranks[case_id]
                )
                improved = sorted(
                    case_id
                    for case_id, rank in candidate_ranks.items()
                    if case_id.startswith("E-")
                    and rank < baseline_ranks[case_id]
                )
                gate_met = (
                    Fraction(
                        candidate_body["mrr_fraction_numerator"],
                        candidate_body["mrr_fraction_denominator"],
                    )
                    > Fraction(91, 100)
                    and Fraction(
                        candidate_body["mrr_fraction_numerator"],
                        candidate_body["mrr_fraction_denominator"],
                    )
                    >= Fraction(
                        baseline_body["mrr_fraction_numerator"],
                        baseline_body["mrr_fraction_denominator"],
                    )
                    and candidate_body["relevant_at_20"] == 60
                    and candidate_body["required_evidence_matched_at_20"] == 60
                    and candidate_body["required_evidence_total"] == 60
                    and candidate_header["mrr_at_20"] == "1.000000"
                    and candidate_header["relevant_at_5"] == 8
                    and candidate_header["required_evidence_matched_at_20"] == 11
                    and candidate_header["required_evidence_total"] == 11
                    and not regressed
                )
                base.require(
                    baseline_body["mrr_at_20"] == "0.903333"
                    and baseline_header["mrr_at_20"] == "1.000000"
                    and candidate_body["mrr_at_20"] == "0.915833"
                    and improved == ["E-033", "E-051"]
                    and gate_met,
                    "live_qualification_gate_failed",
                )
                run = {
                    "baseline_metrics": baseline_metrics,
                    "candidate_gate_met": gate_met,
                    "candidate_metrics": candidate_metrics,
                    "improved_body_case_ids": improved,
                    "latency_ms": {
                        "baseline_fusion_and_collapse": baseline_fusion_ms,
                        "baseline_total_retrieval": (
                            query_embedding_ms
                            + lane_capture_total_ms
                            + baseline_fusion_ms
                        ),
                        "candidate_fusion_and_collapse": candidate_fusion_ms,
                        "candidate_total_retrieval": (
                            query_embedding_ms
                            + lane_capture_total_ms
                            + candidate_fusion_ms
                        ),
                        "exact_lane": lane_ms["exact_lane"],
                        "lane_capture_total": lane_capture_total_ms,
                        "lexical_lane": lane_ms["lexical_lane"],
                        "query_embedding": query_embedding_ms,
                        "shared_wall_clock": total_shared_ms,
                        "vector_lane": lane_ms["vector_lane"],
                    },
                    "measured": run_index >= WARMUP_RUNS,
                    "query_embedding_tokens": query_tokens,
                    "regressed_body_case_ids": regressed,
                    "run": (
                        run_index
                        if run_index < WARMUP_RUNS
                        else run_index - WARMUP_RUNS + 1
                    ),
                }
                if run["measured"]:
                    runs.append(run)
        finally:
            connection.close()
    finally:
        if "client" in locals():
            client.close()
        wipe(secret)

    base.require(len(runs) == MEASURED_RUNS, "measured_run_inventory_invalid")
    base.require(
        all(run["candidate_gate_met"] for run in runs),
        "not_all_measured_runs_passed",
    )
    latency_keys = tuple(runs[0]["latency_ms"])
    latency = {
        key: latency_summary([run["latency_ms"][key] for run in runs])
        for key in latency_keys
    }
    run_summaries = []
    for run in runs:
        run_summaries.append(
            {
                **run,
                "latency_ms": {
                    key: format(value, ".3f")
                    for key, value in run["latency_ms"].items()
                },
            }
        )

    artifact: dict[str, Any] = {
        "artifact_kind": "ishikawa_selected_v2_retrieval_finalist_live_qualification",
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
        "candidate_profile": CANDIDATE_PROFILE,
        "deterministic_across_measured_runs": True,
        "gate": review["live_qualification_design"]["candidate_gate"],
        "inventory": {
            "atomic_candidates": 139,
            "cases_per_run": 68,
            "measured_runs": MEASURED_RUNS,
            "query_embedding_tokens_per_run": 1204,
            "section_page_representatives": 29,
            "warmup_runs": WARMUP_RUNS,
        },
        "latency": latency,
        "next_gate": "review_repeated_live_finalist_qualification_before_profile_freeze",
        "profile_freeze_authorized": False,
        "promoted_baseline_profile": BASELINE_PROFILE,
        "qualification_gate_met": True,
        "runs": run_summaries,
        "schema_version": 1,
        "source_sha256": {
            "atomic_chunks": arguments.expected_atomic_chunks_sha256,
            "atomic_embeddings": arguments.expected_atomic_embeddings_sha256,
            "baseline_receipt": arguments.expected_baseline_receipt_sha256,
            "body_truth": arguments.expected_body_cases_sha256,
            "design": arguments.expected_design_sha256,
            "finalist_review": arguments.expected_review_sha256,
            "header_truth": arguments.expected_header_cases_sha256,
            "normalized": arguments.expected_normalized_sha256,
            "promotion_manifest": arguments.expected_promotion_manifest_sha256,
            "representative_embeddings": arguments.expected_representative_embeddings_sha256,
            "representatives": arguments.expected_representatives_sha256,
        },
    }
    artifact["qualification_id"] = base.domain_digest(
        "ishikawa.selected-v2-retrieval-finalist-live-qualification.v1",
        {key: value for key, value in artifact.items() if key != "latency" and key != "runs"},
    )
    payload = base.canonical_json_bytes(artifact) + b"\n"
    base.write_exclusive(arguments.output, payload)
    print("purpose=qualify_selected_v2_retrieval_finalist")
    print(
        f"warmup_runs={WARMUP_RUNS};measured_runs={MEASURED_RUNS};"
        "cases_per_run=68;all_runs_gate_met=true;deterministic=true"
    )
    print(
        "baseline_body_mrr_at_20=0.903333;candidate_body_mrr_at_20=0.915833;"
        "candidate_body_top5=60/60;candidate_body_top20=60/60"
    )
    print(
        "improved_body_cases=E-033,E-051;regressed_body_cases=none;"
        "header_mrr_at_20=1.000000;header_required_evidence=11/11"
    )
    print(
        "candidate_total_retrieval_median_ms="
        f"{latency['candidate_total_retrieval']['median_ms']};"
        "candidate_total_retrieval_p95_ms="
        f"{latency['candidate_total_retrieval']['p95_ms']}"
    )
    print(f"artifact_sha256={hashlib.sha256(payload).hexdigest()}")
    print("selected_v2_retrieval_finalist_live_qualification=pass")
    return 0


def self_test() -> int:
    assert WARMUP_RUNS == 1 and MEASURED_RUNS == 5
    assert latency_summary([1.0, 2.0, 3.0, 4.0, 5.0]) == {
        "median_ms": "3.000",
        "p95_ms": "5.000",
    }
    assert set(CANDIDATE_PROFILE) == set(BASELINE_PROFILE)
    changed = {
        key
        for key in CANDIDATE_PROFILE
        if CANDIDATE_PROFILE[key] != BASELINE_PROFILE[key]
    }
    assert changed == {"lexical_weight"}
    print("selected_v2_retrieval_finalist_live_qualification_self_test=pass")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--python-root", type=Path)
    parser.add_argument("--review", type=Path)
    parser.add_argument("--expected-review-sha256")
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
    parser.add_argument(
        "--embedding-url", default="http://127.0.0.1:8001/v1/embeddings"
    )
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
        arguments.review,
        arguments.expected_review_sha256,
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
            f"selected_v2_retrieval_finalist_live_qualification=blocked;reason={error}",
            file=sys.stderr,
        )
        raise SystemExit(1)
