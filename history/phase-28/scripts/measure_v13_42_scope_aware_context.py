#!/usr/bin/env python3
"""Compare accepted and V13-42 scope-aware chunk representations."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
from fractions import Fraction
from pathlib import Path
from typing import Any, Mapping, Sequence

import measure_synthetic_corpus_v2_without_ingestion as base
import measure_synthetic_corpus_v3_preingestion as v3
import measure_v13_40_bounded_ranking_candidates as v40


VARIANT_ORDER = ("accepted_v6", "scope_aware_v7")
BODY_MRR_GATE = Fraction(89, 100)


def _inventory(
    source: Mapping[str, Any],
) -> tuple[
    tuple[base.CandidateRecord, ...],
    tuple[base.CandidateRecord, ...],
    dict[str, Mapping[str, Any]],
    dict[str, base.CandidateRecord],
]:
    atomic, representatives, raw = v3.representation_inventory(source)
    canonical = {item.chunk_id: item for item in atomic + representatives}
    base.require(len(canonical) == 943, "candidate_identity_collision")
    return atomic, representatives, raw, canonical


def _validate_scope_context(
    source: Mapping[str, Any], expected_profile_id: str
) -> None:
    base.require(
        source.get("method_profile_id") == expected_profile_id
        and source.get("method_profile", {}).get("name")
        == "ishikawa-structural-chunk-candidates-v7-scope-aware-experiment",
        "scope_aware_profile_invalid",
    )
    for document in source["documents"]:
        metadata_count = 0
        for candidate in document["candidates"]:
            properties = candidate["projection_properties"]
            context = properties.get("retrieval_document_scope_context")
            base.require(
                isinstance(context, dict)
                and set((
                    "document_context", "policy_number", "department",
                    "applicability_class", "purpose_scope_excerpt",
                    "purpose_scope_structural_path",
                    "purpose_scope_source_unit_ids", "maximum_characters",
                    "source", "included_in_retrieval_text", "displayable", "citable",
                )) <= set(context)
                and all(
                    isinstance(context[key], str) and context[key]
                    for key in (
                        "document_context", "policy_number", "department",
                        "applicability_class", "purpose_scope_excerpt",
                    )
                )
                and len(context["purpose_scope_excerpt"]) <= 768
                and context["maximum_characters"] == 768
                and isinstance(context["purpose_scope_structural_path"], list)
                and context["purpose_scope_structural_path"]
                and isinstance(context["purpose_scope_source_unit_ids"], list)
                and context["purpose_scope_source_unit_ids"]
                and context["displayable"] is False
                and context["citable"] is False,
                "scope_aware_context_invalid",
            )
            if candidate["projection_kind"] == "document_control_metadata":
                metadata_count += 1
                base.require(
                    context["included_in_retrieval_text"] is False
                    and "Document scope:" not in candidate["retrieval_text"],
                    "scope_aware_metadata_boundary_invalid",
                )
            else:
                expected_prefix = (
                    f"Document: {context['document_context']}\n"
                    f"Document identifier: {context['policy_number']}\n"
                    f"Department: {context['department']}\n"
                    f"Applicability/class: {context['applicability_class']}\n"
                    f"Document scope: {context['purpose_scope_excerpt']}\n"
                )
                base.require(
                    context["included_in_retrieval_text"] is True
                    and candidate["retrieval_text"].startswith(expected_prefix)
                    and "Effective Date:" not in candidate["context_text"]
                    and "Approval:" not in candidate["context_text"]
                    and "Organization:" not in candidate["context_text"],
                    "scope_aware_retrieval_boundary_invalid",
                )
        base.require(metadata_count == 1, "scope_aware_metadata_inventory_invalid")


def _evaluate_variant(
    connection: Any,
    cases: Sequence[base.Case],
    query_vectors: Sequence[Sequence[float]],
    vectors: Mapping[str, Sequence[float]],
    atomic: Sequence[base.CandidateRecord],
    representatives: Sequence[base.CandidateRecord],
    raw: Mapping[str, Mapping[str, Any]],
    canonical: Mapping[str, base.CandidateRecord],
    profile: Any,
    lane_candidate_type: Any,
    collapse_retrieval_groups: Any,
    expand_authoritative_candidates: Any,
    reciprocal_rank_fusion: Any,
) -> dict[str, Any]:
    selection: list[dict[str, Any]] = []
    expansion: list[dict[str, Any]] = []
    atomic_ids = {item.chunk_id for item in atomic}
    for case, query_vector in zip(cases, query_vectors, strict=True):
        permitted = base.permitted_candidates(case, atomic)
        exact = v3.enrich_lane(
            base.exact_lane(case, permitted, lane_candidate_type), raw
        )
        use_representations = not exact
        searchable = v40.searchable_candidates(
            case,
            permitted,
            representatives,
            raw,
            canonical,
            use_representations=use_representations,
        )
        lexical = v3.enrich_lane(
            base.lexical_lane(
                connection, case.question, searchable, canonical, lane_candidate_type
            ),
            raw,
        )
        vector = v3.enrich_lane(
            base.vector_lane(query_vector, searchable, vectors, lane_candidate_type),
            raw,
        )
        selected = v40.select_results(
            exact,
            lexical,
            vector,
            use_representations=use_representations,
            profile=profile,
            collapse_retrieval_groups=collapse_retrieval_groups,
            reciprocal_rank_fusion=reciprocal_rank_fusion,
        )
        expanded = expand_authoritative_candidates(selected)
        base.require(
            all(
                item.chunk_id in atomic_ids
                and item.retrieval_scoring_only is False
                and item.authoritative_chunk_ids == (item.chunk_id,)
                for item in expanded
            ),
            "authoritative_expansion_invalid",
        )
        measured = base.measure_case(
            case, exact, lexical, vector, selected, permitted, canonical
        )
        measured["used_section_page_representatives"] = use_representations
        measured["searchable_candidate_count"] = len(searchable)
        selection.append(measured)
        matched = sum(
            any(base.matches(canonical[item.chunk_id], evidence) for item in expanded)
            for evidence in case.required_evidence
        )
        expansion.append({
            "case_id": case.case_id,
            "family": case.family,
            "matched_evidence_count": matched,
            "required_evidence_count": len(case.required_evidence),
            "expanded_atomic_count": len(expanded),
        })
    metrics = {
        family: v3.family_metrics(selection, family)
        for family in ("body", "relationship", "header")
    }
    metrics["overall"] = base.aggregate(selection)
    matched = sum(item["matched_evidence_count"] for item in expansion)
    required = sum(item["required_evidence_count"] for item in expansion)
    return {
        "metrics": metrics,
        "authoritative_expansion": {
            "matched_evidence": matched,
            "required_evidence": required,
            "complete": matched == required,
        },
        "gate": v40.gate_for(metrics, matched, required),
        "results": {
            "selection": selection,
            "expanded_atomic_diagnostic": expansion,
        },
    }


def _rank_movements(
    accepted: Mapping[str, Any], scope_aware: Mapping[str, Any]
) -> dict[str, int]:
    left = {
        item["case_id"]: item["first_relevant_rank"]
        for item in accepted["results"]["selection"]
    }
    right = {
        item["case_id"]: item["first_relevant_rank"]
        for item in scope_aware["results"]["selection"]
    }
    base.require(left.keys() == right.keys(), "comparison_case_inventory_mismatch")
    improved = regressed = unchanged = 0
    for case_id in left:
        old = left[case_id] if left[case_id] is not None else 21
        new = right[case_id] if right[case_id] is not None else 21
        if new < old:
            improved += 1
        elif new > old:
            regressed += 1
        else:
            unchanged += 1
    return {"improved": improved, "regressed": regressed, "unchanged": unchanged}


def execute(arguments: argparse.Namespace) -> None:
    python_root = arguments.python_root.resolve(strict=True)
    sys.path.insert(0, str(python_root))
    from embed_document_candidates_via_endpoint import DOCUMENT_PREFIX, EndpointClient, wipe
    from ishikawa.method_profile import ACCEPTED_RETRIEVAL_PROFILE
    from ishikawa.retrieval import (
        LaneCandidate,
        collapse_retrieval_groups,
        expand_authoritative_candidates,
        reciprocal_rank_fusion,
    )

    accepted_source = base.load_bound_json(
        arguments.accepted_chunks,
        arguments.expected_accepted_chunks_sha256,
        32 * 1024 * 1024,
    )
    scope_source = base.load_bound_json(
        arguments.scope_chunks,
        arguments.expected_scope_chunks_sha256,
        48 * 1024 * 1024,
    )
    truth = base.load_bound_json(
        arguments.truth, arguments.expected_truth_sha256, 4 * 1024 * 1024
    )
    base.require(
        accepted_source.get("method_profile_id") == arguments.accepted_profile_id,
        "accepted_profile_invalid",
    )
    _validate_scope_context(scope_source, arguments.scope_profile_id)
    cases = v3.load_cases(truth)
    accepted_inventory = _inventory(accepted_source)
    scope_inventory = _inventory(scope_source)
    accepted_candidates = accepted_inventory[0] + accepted_inventory[1]
    scope_candidates = scope_inventory[0] + scope_inventory[1]
    profile = ACCEPTED_RETRIEVAL_PROFILE
    base.require(
        profile.exact_weight == 1
        and profile.lexical_weight == 2
        and profile.vector_weight == 4
        and profile.exact_candidate_depth == 1
        and profile.lexical_candidate_depth == 20
        and profile.vector_candidate_depth == 20
        and profile.fused_candidate_depth == 20
        and profile.rrf_constant == 60
        and profile.section_page_representatives is True
        and profile.document_local_duplicate_canonicalization is True,
        "accepted_retrieval_profile_changed",
    )

    secret_text = os.environ.pop("ISHIKAWA_NOMIC_API_KEY", "")
    base.require(
        32 <= len(secret_text) <= 1024
        and "\n" not in secret_text
        and "\r" not in secret_text,
        "nomic_credential_invalid",
    )
    secret = bytearray(secret_text.encode("utf-8"))
    secret_text = ""
    embedding_started = time.perf_counter_ns()
    try:
        client = EndpointClient(arguments.embedding_url, arguments.tokenizer_url, secret)
        runtime_identity = client.model_identity()
        accepted_raw_vectors, accepted_tokens = v3.embed_inputs(
            client,
            [DOCUMENT_PREFIX + item.retrieval_text for item in accepted_candidates],
        )
        scope_raw_vectors, scope_tokens = v3.embed_inputs(
            client,
            [DOCUMENT_PREFIX + item.retrieval_text for item in scope_candidates],
        )
        query_vectors, query_tokens = v3.embed_inputs(
            client, [base.QUERY_PREFIX + item.question for item in cases]
        )
    finally:
        if "client" in locals():
            client.close()
        wipe(secret)
    embedding_ms = (time.perf_counter_ns() - embedding_started) / 1_000_000
    accepted_vectors = {
        item.chunk_id: vector
        for item, vector in zip(accepted_candidates, accepted_raw_vectors, strict=True)
    }
    scope_vectors = {
        item.chunk_id: vector
        for item, vector in zip(scope_candidates, scope_raw_vectors, strict=True)
    }

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

    retrieval_started = time.perf_counter_ns()
    try:
        connection.execute("BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
        state = connection.execute(
            "SELECT current_setting('transaction_read_only'), current_database(), current_user"
        ).fetchone()
        base.require(
            state == ("on", "postgres", arguments.postgresql_user),
            "temporary_postgresql_boundary_invalid",
        )
        variants = {
            "accepted_v6": _evaluate_variant(
                connection, cases, query_vectors, accepted_vectors,
                *accepted_inventory, profile, LaneCandidate,
                collapse_retrieval_groups, expand_authoritative_candidates,
                reciprocal_rank_fusion,
            ),
            "scope_aware_v7": _evaluate_variant(
                connection, cases, query_vectors, scope_vectors,
                *scope_inventory, profile, LaneCandidate,
                collapse_retrieval_groups, expand_authoritative_candidates,
                reciprocal_rank_fusion,
            ),
        }
        connection.rollback()
    finally:
        connection.close()
    retrieval_ms = (time.perf_counter_ns() - retrieval_started) / 1_000_000

    movements = _rank_movements(variants["accepted_v6"], variants["scope_aware_v7"])
    scope_qualified = variants["scope_aware_v7"]["gate"]["status"] == "qualified"
    artifact: dict[str, Any] = {
        "artifact_kind": "ishikawa_v13_42_scope_aware_context_experiment",
        "schema_version": 1,
        "corpus_identity": "synthetic-corpus-v3",
        "measurement_class": "evaluation_only_no_promotion",
        "source_sha256": {
            "accepted_chunks": arguments.expected_accepted_chunks_sha256,
            "scope_aware_chunks": arguments.expected_scope_chunks_sha256,
            "retrieval_truth": arguments.expected_truth_sha256,
        },
        "chunk_profiles": {
            "accepted_v6": arguments.accepted_profile_id,
            "scope_aware_v7": arguments.scope_profile_id,
        },
        "retrieval_profile": {
            "profile_id": profile.digest,
            "exact_candidate_depth": 1,
            "lexical_candidate_depth": 20,
            "vector_candidate_depth": 20,
            "fused_candidate_depth": 20,
            "rrf_constant": 60,
            "lane_weights": {"exact": 1, "lexical": 2, "vector": 4},
            "learned_reranker": False,
        },
        "experiment": {
            "variant_order": list(VARIANT_ORDER),
            "body_mrr_gate": "0.89",
            "body_coverage_gate": "120/120",
            "relationship_coverage_gate": "30/30",
            "header_coverage_gate": "30/30",
            "authoritative_expansion_gate": "180/180",
            "scope_excerpt_maximum_characters": 768,
        },
        "candidate_inventory": {
            "documents_per_variant": 30,
            "atomic_per_variant": 786,
            "representatives_per_variant": 157,
            "total_per_variant": 943,
        },
        "case_inventory": {"body": 120, "relationship": 30, "header": 30, "total": 180},
        "runtime_identity_digest": runtime_identity,
        "token_usage": {
            "accepted_document_embedding_tokens": accepted_tokens,
            "scope_aware_document_embedding_tokens": scope_tokens,
            "query_embedding_tokens": query_tokens,
        },
        "latency_ms": {
            "embeddings": format(embedding_ms, ".3f"),
            "retrieval_and_measurement": format(retrieval_ms, ".3f"),
        },
        "variants": variants,
        "rank_movements": movements,
        "selection_status": "qualified_for_separate_freeze" if scope_qualified else "not_met",
        "selected_candidate": "scope_aware_v7" if scope_qualified else None,
        "boundaries": {
            "accepted_database_contact": False,
            "accepted_database_write": False,
            "black_corpus_access": False,
            "corpus_ingestion": False,
            "corpus_v3_changed": False,
            "gemma_contact": False,
            "nomic_contact": True,
            "private_temporary_postgresql": True,
            "production_profile_changed": False,
            "retained_runtime_flat_file_index": False,
            "question_text_retained": False,
            "query_vectors_retained": False,
            "source_text_retained": False,
        },
        "promotion_authorized": False,
        "next_gate": "review_metrics_and_separately_freeze_scope_aware_promotion_if_qualified",
    }
    identity_source = {
        key: value for key, value in artifact.items()
        if key not in {"latency_ms", "variants"}
    }
    artifact["experiment_id"] = base.domain_digest(
        "ishikawa.v13-42-scope-aware-context-experiment.v1", identity_source
    )
    base.write_exclusive(arguments.output, base.canonical_json_bytes(artifact) + b"\n")

    print("purpose=measure_v13_42_scope_aware_context")
    for name in VARIANT_ORDER:
        body = variants[name]["metrics"]["body"]
        print(
            f"variant={name};body_mrr_at_20={body['mrr_at_20']};"
            f"body_relevant_at_5={body['relevant_at_5']}/120;"
            f"body_relevant_at_20={body['relevant_at_20']}/120;"
            f"gate={variants[name]['gate']['status']}"
        )
    print(
        f"rank_movements=improved:{movements['improved']},"
        f"regressed:{movements['regressed']},unchanged:{movements['unchanged']}"
    )
    print(
        f"selection_status={artifact['selection_status']};"
        f"selected_candidate={artifact['selected_candidate'] or 'none'};"
        "promotion_authorized=false"
    )
    print("v13_42_scope_aware_context_measurement=pass")


def self_test() -> None:
    metrics = {
        "body": {
            "mrr_fraction_numerator": 89,
            "mrr_fraction_denominator": 100,
            "relevant_at_20": 120,
            "required_evidence_matched_at_20": 120,
            "required_evidence_total": 120,
        },
        "relationship": {
            "relevant_at_20": 30,
            "required_evidence_matched_at_20": 30,
            "required_evidence_total": 30,
        },
        "header": {
            "mrr_at_20": "1.000000",
            "relevant_at_20": 30,
            "required_evidence_matched_at_20": 30,
            "required_evidence_total": 30,
        },
    }
    assert v40.gate_for(metrics, 180, 180)["status"] == "qualified"
    assert BODY_MRR_GATE == Fraction(89, 100)
    accepted = {"results": {"selection": [
        {"case_id": "A", "first_relevant_rank": 2},
        {"case_id": "B", "first_relevant_rank": 1},
        {"case_id": "C", "first_relevant_rank": None},
    ]}}
    scope = {"results": {"selection": [
        {"case_id": "A", "first_relevant_rank": 1},
        {"case_id": "B", "first_relevant_rank": 2},
        {"case_id": "C", "first_relevant_rank": None},
    ]}}
    assert _rank_movements(accepted, scope) == {
        "improved": 1, "regressed": 1, "unchanged": 1
    }
    print("v13_42_scope_aware_context_measurement_self_test=pass")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--python-root", type=Path)
    parser.add_argument("--accepted-chunks", type=Path)
    parser.add_argument("--expected-accepted-chunks-sha256")
    parser.add_argument("--scope-chunks", type=Path)
    parser.add_argument("--expected-scope-chunks-sha256")
    parser.add_argument("--accepted-profile-id")
    parser.add_argument("--scope-profile-id")
    parser.add_argument("--truth", type=Path)
    parser.add_argument("--expected-truth-sha256")
    parser.add_argument("--embedding-url")
    parser.add_argument("--tokenizer-url")
    parser.add_argument("--postgresql-socket", type=Path)
    parser.add_argument("--postgresql-port", type=int)
    parser.add_argument("--postgresql-user")
    parser.add_argument("--output", type=Path)
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
        return 0
    required = (
        arguments.python_root, arguments.accepted_chunks, arguments.scope_chunks,
        arguments.accepted_profile_id, arguments.scope_profile_id, arguments.truth,
        arguments.embedding_url, arguments.tokenizer_url, arguments.postgresql_socket,
        arguments.postgresql_port, arguments.postgresql_user, arguments.output,
    )
    if any(value is None for value in required):
        parser.error("measurement arguments are required without --self-test")
    try:
        execute(arguments)
    except (base.MeasurementError, OSError, ValueError, KeyError) as error:
        print(f"v13_42_scope_aware_context_measurement=blocked;reason={error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
