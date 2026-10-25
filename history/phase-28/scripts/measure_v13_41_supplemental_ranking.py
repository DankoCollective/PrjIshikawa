#!/usr/bin/env python3
"""Measure the frozen V13-41 supplemental retrieval topology."""

from __future__ import annotations

import argparse
import os
import sys
import time
from fractions import Fraction
from pathlib import Path
from typing import Any, Mapping, Sequence

import measure_synthetic_corpus_v2_without_ingestion as base
import measure_synthetic_corpus_v3_preingestion as v3
import measure_v13_40_bounded_ranking_candidates as v40


VARIANT_CONFIGS = (
    ("balanced3_pl1_pv0", 3, 1, 0),
    ("balanced3_pl0_pv1", 3, 0, 1),
    ("balanced3_pl1_pv1", 3, 1, 1),
    ("balanced3_pl1_pv2", 3, 1, 2),
    ("balanced3_pl2_pv1", 3, 2, 1),
    ("balanced5_pl1_pv0", 5, 1, 0),
    ("balanced5_pl0_pv1", 5, 0, 1),
    ("balanced5_pl1_pv1", 5, 1, 1),
    ("balanced5_pl1_pv2", 5, 1, 2),
    ("balanced5_pl2_pv1", 5, 2, 1),
)
VARIANT_ORDER = tuple(item[0] for item in VARIANT_CONFIGS)
CONFIG_BY_NAME = {
    name: {"shortlist_per_lane": depth, "passage_lexical_weight": lexical,
           "passage_vector_weight": vector}
    for name, depth, lexical, vector in VARIANT_CONFIGS
}


def unique_documents(candidates: Sequence[Any], depth: int) -> tuple[str, ...]:
    result: list[str] = []
    for candidate in candidates:
        if candidate.document_key not in result:
            result.append(candidate.document_key)
        if len(result) == depth:
            break
    return tuple(result)


def balanced_shortlist(
    exact: Sequence[Any],
    lexical: Sequence[Any],
    vector: Sequence[Any],
    depth: int,
) -> tuple[str, ...]:
    base.require(depth in {3, 5}, "balanced_shortlist_depth_invalid")
    exact_documents = unique_documents(exact, len(exact))
    lexical_documents = unique_documents(lexical, depth)
    vector_documents = unique_documents(vector, depth)
    ordered: list[str] = []
    for document_ref in exact_documents:
        if document_ref not in ordered:
            ordered.append(document_ref)
    for index in range(depth):
        for documents in (lexical_documents, vector_documents):
            if index < len(documents) and documents[index] not in ordered:
                ordered.append(documents[index])
    base.require(ordered, "balanced_shortlist_empty")
    base.require(
        set(lexical_documents) <= set(ordered)
        and set(vector_documents) <= set(ordered)
        and set(exact_documents) <= set(ordered)
        and len(ordered) <= depth * 2 + len(exact_documents),
        "balanced_shortlist_invalid",
    )
    return tuple(ordered)


def supplemental_fusion(
    lanes: Mapping[str, Sequence[Any]],
    weights: Mapping[str, int],
    fused_candidate_type: Any,
    *,
    rrf_constant: int = 60,
) -> tuple[Any, ...]:
    expected_lanes = {
        "exact",
        "identity_lexical",
        "identity_vector",
        "passage_lexical",
        "passage_vector",
    }
    base.require(set(lanes) == expected_lanes, "supplemental_lane_inventory_invalid")
    base.require(
        set(weights) == expected_lanes
        and weights["exact"] == 1
        and weights["identity_lexical"] == 2
        and weights["identity_vector"] == 4
        and weights["passage_lexical"] in {0, 1, 2}
        and weights["passage_vector"] in {0, 1, 2}
        and (weights["passage_lexical"], weights["passage_vector"])
        in {(1, 0), (0, 1), (1, 1), (1, 2), (2, 1)},
        "supplemental_weights_invalid",
    )
    accumulated: dict[str, dict[str, Any]] = {}
    for lane_name in (
        "exact",
        "identity_lexical",
        "identity_vector",
        "passage_lexical",
        "passage_vector",
    ):
        weight = weights[lane_name]
        seen: set[str] = set()
        for candidate in lanes[lane_name]:
            base.require(candidate.chunk_id not in seen, "supplemental_lane_duplicate")
            seen.add(candidate.chunk_id)
            if weight == 0:
                continue
            state = accumulated.setdefault(
                candidate.chunk_id,
                {
                    "document_id": candidate.document_id,
                    "document_version_id": candidate.document_version_id,
                    "document_key": candidate.document_key,
                    "score": Fraction(0, 1),
                    "best_rank": candidate.rank,
                    "exact_priority": False,
                    "retrieval_group_id": candidate.retrieval_group_id,
                    "authoritative_chunk_ids": candidate.authoritative_chunk_ids,
                    "retrieval_scoring_only": candidate.retrieval_scoring_only,
                },
            )
            base.require(
                (
                    state["document_id"],
                    state["document_version_id"],
                    state["document_key"],
                    state["retrieval_group_id"],
                    state["authoritative_chunk_ids"],
                    state["retrieval_scoring_only"],
                )
                == (
                    candidate.document_id,
                    candidate.document_version_id,
                    candidate.document_key,
                    candidate.retrieval_group_id,
                    candidate.authoritative_chunk_ids,
                    candidate.retrieval_scoring_only,
                ),
                "supplemental_candidate_conflict",
            )
            state["score"] += Fraction(weight, rrf_constant + candidate.rank)
            state["best_rank"] = min(state["best_rank"], candidate.rank)
            state["exact_priority"] = state["exact_priority"] or lane_name == "exact"
    fused = tuple(
        fused_candidate_type(
            chunk_id=chunk_id,
            document_id=state["document_id"],
            document_version_id=state["document_version_id"],
            document_key=state["document_key"],
            fused_score=float(state["score"]),
            exact_priority=state["exact_priority"],
            evidence=(),
            retrieval_group_id=state["retrieval_group_id"],
            authoritative_chunk_ids=state["authoritative_chunk_ids"],
            retrieval_scoring_only=state["retrieval_scoring_only"],
        )
        for chunk_id, state in sorted(
            accumulated.items(),
            key=lambda item: (
                -int(item[1]["exact_priority"]),
                -item[1]["score"],
                item[1]["best_rank"],
                item[0],
            ),
        )
    )
    base.require(fused, "supplemental_fusion_empty")
    return fused


def summarize_variant(
    selection: Sequence[Mapping[str, Any]],
    expansion: Sequence[Mapping[str, Any]],
) -> dict[str, Any]:
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
            "selection": list(selection),
            "expanded_atomic_diagnostic": list(expansion),
        },
    }


def evaluate_pass(
    connection: Any,
    cases: Sequence[base.Case],
    query_vectors: Sequence[Sequence[float]],
    current_vectors: Mapping[str, Sequence[float]],
    passage_vectors: Mapping[str, Sequence[float]],
    atomic: Sequence[base.CandidateRecord],
    representatives: Sequence[base.CandidateRecord],
    raw: Mapping[str, Mapping[str, Any]],
    canonical_by_chunk: Mapping[str, base.CandidateRecord],
    passage_by_chunk: Mapping[str, base.CandidateRecord],
    profile: Any,
    variant_names: Sequence[str],
    lane_candidate_type: Any,
    fused_candidate_type: Any,
    collapse_retrieval_groups: Any,
    expand_authoritative_candidates: Any,
    reciprocal_rank_fusion: Any,
    *,
    include_reference: bool,
) -> dict[str, Any]:
    base.require(
        variant_names
        and len(set(variant_names)) == len(variant_names)
        and set(variant_names) <= set(VARIANT_ORDER),
        "requested_variant_inventory_invalid",
    )
    result_names = (("reference_current_identity",) if include_reference else ()) + tuple(
        variant_names
    )
    selection: dict[str, list[dict[str, Any]]] = {name: [] for name in result_names}
    expansion: dict[str, list[dict[str, Any]]] = {name: [] for name in result_names}
    atomic_ids = {item.chunk_id for item in atomic}
    required_depths = sorted(
        {CONFIG_BY_NAME[name]["shortlist_per_lane"] for name in variant_names}
    )

    for case, query_vector in zip(cases, query_vectors, strict=True):
        permitted_atomic = base.permitted_candidates(case, atomic)
        exact = v3.enrich_lane(
            base.exact_lane(case, permitted_atomic, lane_candidate_type), raw
        )
        use_representations = not exact
        current_searchable = v40.searchable_candidates(
            case,
            permitted_atomic,
            representatives,
            raw,
            canonical_by_chunk,
            use_representations=use_representations,
        )
        current_lexical = v3.enrich_lane(
            base.lexical_lane(
                connection,
                case.question,
                current_searchable,
                canonical_by_chunk,
                lane_candidate_type,
            ),
            raw,
        )
        current_vector = v3.enrich_lane(
            base.vector_lane(
                query_vector,
                current_searchable,
                current_vectors,
                lane_candidate_type,
            ),
            raw,
        )

        if include_reference:
            selected = v40.select_results(
                exact,
                current_lexical,
                current_vector,
                use_representations=use_representations,
                profile=profile,
                collapse_retrieval_groups=collapse_retrieval_groups,
                reciprocal_rank_fusion=reciprocal_rank_fusion,
            )
            expanded = expand_authoritative_candidates(selected)
            measured = base.measure_case(
                case,
                exact,
                current_lexical,
                current_vector,
                selected,
                permitted_atomic,
                canonical_by_chunk,
            )
            measured["document_shortlist"] = []
            measured["supplemental_weights"] = {
                "passage_lexical": 0,
                "passage_vector": 0,
            }
            selection["reference_current_identity"].append(measured)
            matched = sum(
                any(
                    base.matches(canonical_by_chunk[item.chunk_id], evidence)
                    for item in expanded
                )
                for evidence in case.required_evidence
            )
            expansion["reference_current_identity"].append(
                {
                    "case_id": case.case_id,
                    "family": case.family,
                    "matched_evidence_count": matched,
                    "required_evidence_count": len(case.required_evidence),
                    "expanded_atomic_count": len(expanded),
                }
            )

        lanes_by_depth: dict[int, dict[str, Any]] = {}
        for depth in required_depths:
            shortlist = balanced_shortlist(
                exact, current_lexical, current_vector, depth
            )
            allowed_refs = set(shortlist)
            restricted_current = v40.searchable_candidates(
                case,
                permitted_atomic,
                representatives,
                raw,
                canonical_by_chunk,
                use_representations=use_representations,
                allowed_refs=allowed_refs,
            )
            restricted_passage = v40.searchable_candidates(
                case,
                permitted_atomic,
                representatives,
                raw,
                passage_by_chunk,
                use_representations=use_representations,
                allowed_refs=allowed_refs,
            )
            identity_lexical = v3.enrich_lane(
                base.lexical_lane(
                    connection,
                    case.question,
                    restricted_current,
                    canonical_by_chunk,
                    lane_candidate_type,
                ),
                raw,
            )
            identity_vector = v3.enrich_lane(
                base.vector_lane(
                    query_vector,
                    restricted_current,
                    current_vectors,
                    lane_candidate_type,
                ),
                raw,
            )
            passage_lexical = v3.enrich_lane(
                base.lexical_lane(
                    connection,
                    case.question,
                    restricted_passage,
                    canonical_by_chunk,
                    lane_candidate_type,
                ),
                raw,
            )
            passage_vector = v3.enrich_lane(
                base.vector_lane(
                    query_vector,
                    restricted_passage,
                    passage_vectors,
                    lane_candidate_type,
                ),
                raw,
            )
            lanes_by_depth[depth] = {
                "shortlist": shortlist,
                "searchable_count": len(restricted_current),
                "exact": exact,
                "identity_lexical": identity_lexical,
                "identity_vector": identity_vector,
                "passage_lexical": passage_lexical,
                "passage_vector": passage_vector,
            }

        for name in variant_names:
            config = CONFIG_BY_NAME[name]
            lanes = lanes_by_depth[config["shortlist_per_lane"]]
            weights = {
                "exact": 1,
                "identity_lexical": 2,
                "identity_vector": 4,
                "passage_lexical": config["passage_lexical_weight"],
                "passage_vector": config["passage_vector_weight"],
            }
            fused = supplemental_fusion(
                {key: lanes[key] for key in weights},
                weights,
                fused_candidate_type,
                rrf_constant=60,
            )
            if use_representations:
                fused = collapse_retrieval_groups(fused)
            selected = tuple(fused[:20])
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
                case,
                exact,
                lanes["identity_lexical"],
                lanes["identity_vector"],
                selected,
                permitted_atomic,
                canonical_by_chunk,
            )
            measured["supplemental_lanes"] = {
                "passage_lexical": [
                    base.rank_record(rank, item, canonical_by_chunk)
                    for rank, item in enumerate(lanes["passage_lexical"], 1)
                ],
                "passage_vector": [
                    base.rank_record(rank, item, canonical_by_chunk)
                    for rank, item in enumerate(lanes["passage_vector"], 1)
                ],
            }
            measured["document_shortlist"] = list(lanes["shortlist"])
            measured["searchable_candidate_count"] = lanes["searchable_count"]
            measured["supplemental_weights"] = {
                "passage_lexical": config["passage_lexical_weight"],
                "passage_vector": config["passage_vector_weight"],
            }
            selection[name].append(measured)
            matched = sum(
                any(
                    base.matches(canonical_by_chunk[item.chunk_id], evidence)
                    for item in expanded
                )
                for evidence in case.required_evidence
            )
            expansion[name].append(
                {
                    "case_id": case.case_id,
                    "family": case.family,
                    "matched_evidence_count": matched,
                    "required_evidence_count": len(case.required_evidence),
                    "expanded_atomic_count": len(expanded),
                }
            )

    return {
        name: summarize_variant(selection[name], expansion[name])
        for name in result_names
    }


def selection_key(name: str, result: Mapping[str, Any]) -> tuple[Fraction, int, int]:
    body = result["metrics"]["body"]
    return (
        Fraction(body["mrr_fraction_numerator"], body["mrr_fraction_denominator"]),
        body["relevant_at_5"],
        -VARIANT_ORDER.index(name),
    )


def worst_pass_key(
    name: str,
    initial: Mapping[str, Any],
    repeats: Sequence[Mapping[str, Any]],
) -> tuple[Fraction, int, int]:
    records = [initial[name], *(item[name] for item in repeats)]
    mrr = min(
        Fraction(
            item["metrics"]["body"]["mrr_fraction_numerator"],
            item["metrics"]["body"]["mrr_fraction_denominator"],
        )
        for item in records
    )
    top_five = min(item["metrics"]["body"]["relevant_at_5"] for item in records)
    return (mrr, top_five, -VARIANT_ORDER.index(name))


def execute(arguments: argparse.Namespace) -> None:
    python_root = arguments.python_root.resolve(strict=True)
    sys.path.insert(0, str(python_root))
    from embed_document_candidates_via_endpoint import (
        DOCUMENT_PREFIX,
        EndpointClient,
        wipe,
    )
    from ishikawa.method_profile import ACCEPTED_RETRIEVAL_PROFILE
    from ishikawa.retrieval import (
        FusedCandidate,
        LaneCandidate,
        collapse_retrieval_groups,
        expand_authoritative_candidates,
        reciprocal_rank_fusion,
    )

    chunks = base.load_bound_json(
        arguments.chunks, arguments.expected_chunks_sha256, 32 * 1024 * 1024
    )
    truth = base.load_bound_json(
        arguments.truth, arguments.expected_truth_sha256, 4 * 1024 * 1024
    )
    cases = v3.load_cases(truth)
    atomic, representatives, raw = v3.representation_inventory(chunks)
    candidates = atomic + representatives
    canonical_by_chunk = {item.chunk_id: item for item in candidates}
    passage_candidates = tuple(v40.passage_record(item, raw) for item in candidates)
    passage_by_chunk = {item.chunk_id: item for item in passage_candidates}
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
    try:
        client = EndpointClient(
            arguments.embedding_url, arguments.tokenizer_url, secret
        )
        try:
            runtime_identity = client.model_identity()
        except Exception as error:
            raise base.MeasurementError("embedding_runtime_unavailable") from error
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
        try:
            connection.execute(
                "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY"
            )
            state = connection.execute(
                "SELECT current_setting('transaction_read_only'), current_database(), current_user"
            ).fetchone()
            base.require(
                state == ("on", "postgres", arguments.postgresql_user),
                "temporary_postgresql_boundary_invalid",
            )

            pass_records: list[dict[str, Any]] = []
            repeats: list[dict[str, Any]] = []
            initial_qualified: list[str] = []
            finalists: list[str] = []
            total_embedding_tokens = 0
            total_embedding_ms = 0.0
            total_retrieval_ms = 0.0

            for pass_index in range(3):
                if pass_index > 0 and not finalists:
                    break
                embedding_started = time.perf_counter_ns()
                try:
                    current_raw, current_tokens = v3.embed_inputs(
                        client,
                        [DOCUMENT_PREFIX + item.retrieval_text for item in candidates],
                    )
                    passage_raw, passage_tokens = v3.embed_inputs(
                        client,
                        [
                            DOCUMENT_PREFIX + item.retrieval_text
                            for item in passage_candidates
                        ],
                    )
                    query_vectors, query_tokens = v3.embed_inputs(
                        client, [base.QUERY_PREFIX + item.question for item in cases]
                    )
                except Exception as error:
                    raise base.MeasurementError(
                        f"embedding_pass_{pass_index + 1}_failed"
                    ) from error
                embedding_ms = (
                    time.perf_counter_ns() - embedding_started
                ) / 1_000_000
                total_embedding_ms += embedding_ms
                total_embedding_tokens += current_tokens + passage_tokens + query_tokens
                current_vectors = {
                    item.chunk_id: vector
                    for item, vector in zip(candidates, current_raw, strict=True)
                }
                passage_vectors = {
                    item.chunk_id: vector
                    for item, vector in zip(
                        passage_candidates, passage_raw, strict=True
                    )
                }
                requested = VARIANT_ORDER if pass_index == 0 else tuple(finalists)
                retrieval_started = time.perf_counter_ns()
                try:
                    results = evaluate_pass(
                        connection,
                        cases,
                        query_vectors,
                        current_vectors,
                        passage_vectors,
                        atomic,
                        representatives,
                        raw,
                        canonical_by_chunk,
                        passage_by_chunk,
                        profile,
                        requested,
                        LaneCandidate,
                        FusedCandidate,
                        collapse_retrieval_groups,
                        expand_authoritative_candidates,
                        reciprocal_rank_fusion,
                        include_reference=pass_index == 0,
                    )
                except base.MeasurementError:
                    raise
                except Exception as error:
                    raise base.MeasurementError(
                        f"retrieval_pass_{pass_index + 1}_failed"
                    ) from error
                retrieval_ms = (
                    time.perf_counter_ns() - retrieval_started
                ) / 1_000_000
                total_retrieval_ms += retrieval_ms
                pass_records.append(
                    {
                        "pass": pass_index + 1,
                        "fresh_embeddings": True,
                        "embedding_tokens": current_tokens
                        + passage_tokens
                        + query_tokens,
                        "embedding_ms": format(embedding_ms, ".3f"),
                        "retrieval_ms": format(retrieval_ms, ".3f"),
                        "variants": results,
                    }
                )
                if pass_index == 0:
                    initial_qualified = [
                        name
                        for name in VARIANT_ORDER
                        if results[name]["gate"]["status"] == "qualified"
                    ]
                    finalists = sorted(
                        initial_qualified,
                        key=lambda name: selection_key(name, results[name]),
                        reverse=True,
                    )[:3]
                else:
                    repeats.append(results)
            connection.rollback()
        finally:
            connection.close()
    finally:
        if "client" in locals():
            client.close()
        wipe(secret)

    initial = pass_records[0]["variants"]
    repeat_qualified = [
        name
        for name in finalists
        if len(repeats) == 2
        and all(item[name]["gate"]["status"] == "qualified" for item in repeats)
    ]
    selected_candidate = (
        max(
            repeat_qualified,
            key=lambda name: worst_pass_key(name, initial, repeats),
        )
        if repeat_qualified
        else None
    )
    artifact: dict[str, Any] = {
        "artifact_kind": "ishikawa_v13_41_supplemental_ranking_experiment",
        "schema_version": 1,
        "corpus_identity": "synthetic-corpus-v3",
        "measurement_class": "evaluation_only_no_promotion",
        "source_sha256": {
            "chunks": arguments.expected_chunks_sha256,
            "retrieval_truth": arguments.expected_truth_sha256,
        },
        "retrieval_profile": {
            "reference_profile_id": profile.digest,
            "exact_candidate_depth": 1,
            "identity_lexical_candidate_depth": 20,
            "identity_vector_candidate_depth": 20,
            "passage_lexical_candidate_depth": 20,
            "passage_vector_candidate_depth": 20,
            "fused_candidate_depth": 20,
            "rrf_constant": 60,
            "primary_weights": {"exact": 1, "identity_lexical": 2, "identity_vector": 4},
            "learned_reranker": False,
        },
        "experiment": {
            "variant_order": list(VARIANT_ORDER),
            "variant_configs": CONFIG_BY_NAME,
            "balanced_shortlist": "union_of_top_unique_documents_per_primary_lane_plus_exact",
            "body_mrr_gate": "0.89",
            "maximum_initial_candidates": 10,
            "maximum_finalists": 3,
            "required_fresh_repeat_passes": 2,
            "selection_order": [
                "worst_pass_body_mrr_at_20_desc",
                "worst_pass_body_relevant_at_5_desc",
                "declared_variant_order",
            ],
        },
        "candidate_inventory": {
            "documents": 30,
            "atomic": len(atomic),
            "representatives": len(representatives),
            "total": len(candidates),
        },
        "case_inventory": {
            "body": 120,
            "relationship": 30,
            "header": 30,
            "total": len(cases),
        },
        "runtime_identity_digest": runtime_identity,
        "measurement_passes": pass_records,
        "initial_qualified_candidates": initial_qualified,
        "initial_finalists": finalists,
        "repeat_qualified_candidates": repeat_qualified,
        "selected_candidate": selected_candidate,
        "selection_status": "qualified" if selected_candidate else "not_met",
        "token_usage": {"all_embedding_tokens": total_embedding_tokens},
        "latency_ms": {
            "all_embeddings": format(total_embedding_ms, ".3f"),
            "all_retrieval_and_measurement": format(total_retrieval_ms, ".3f"),
        },
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
            "runtime_flat_file_index": False,
            "question_text_retained": False,
            "query_vectors_retained": False,
            "source_text_retained": False,
        },
        "promotion_authorized": False,
        "next_gate": "review_and_separately_freeze_any_selected_candidate",
    }
    identity_source = {
        key: value
        for key, value in artifact.items()
        if key not in {"latency_ms", "measurement_passes"}
    }
    artifact["experiment_id"] = base.domain_digest(
        "ishikawa.v13-41-supplemental-ranking-experiment.v1", identity_source
    )
    base.write_exclusive(arguments.output, base.canonical_json_bytes(artifact) + b"\n")

    print("purpose=measure_v13_41_supplemental_ranking")
    reference = initial["reference_current_identity"]
    body = reference["metrics"]["body"]
    print(
        f"reference=current_identity;body_mrr_at_20={body['mrr_at_20']};"
        f"body_relevant_at_5={body['relevant_at_5']}/120;"
        f"body_relevant_at_20={body['relevant_at_20']}/120"
    )
    for name in VARIANT_ORDER:
        candidate = initial[name]
        body = candidate["metrics"]["body"]
        print(
            f"variant={name};body_mrr_at_20={body['mrr_at_20']};"
            f"body_relevant_at_5={body['relevant_at_5']}/120;"
            f"body_relevant_at_20={body['relevant_at_20']}/120;"
            f"gate={candidate['gate']['status']};"
            f"failed_checks={','.join(candidate['gate']['failed_checks']) if candidate['gate']['failed_checks'] else 'none'}"
        )
    print(
        f"initial_qualified={','.join(initial_qualified) if initial_qualified else 'none'};"
        f"initial_finalists={','.join(finalists) if finalists else 'none'};"
        f"fresh_repeat_passes={len(repeats)};"
        f"repeat_qualified={','.join(repeat_qualified) if repeat_qualified else 'none'}"
    )
    print(
        f"selection_status={artifact['selection_status']};"
        f"selected_candidate={selected_candidate or 'none'};promotion_authorized=false"
    )
    print("v13_41_supplemental_ranking_measurement=pass")


def self_test() -> None:
    class Candidate:
        def __init__(self, chunk: str, document: str, lane: str, rank: int):
            self.chunk_id = chunk
            self.document_id = document + "-id"
            self.document_version_id = document + "-version"
            self.document_key = document
            self.lane = lane
            self.rank = rank
            self.raw_score = 1.0 / rank
            self.retrieval_group_id = chunk
            self.authoritative_chunk_ids = (chunk,)
            self.retrieval_scoring_only = False

    class Fused:
        def __init__(self, **values: Any):
            self.__dict__.update(values)

    exact = ()
    lexical = (
        Candidate("la1", "lex-a", "lexical", 1),
        Candidate("la2", "lex-a", "lexical", 2),
        Candidate("lb", "lex-b", "lexical", 3),
        Candidate("lc", "lex-c", "lexical", 4),
    )
    vector = (
        Candidate("va", "vec-a", "vector", 1),
        Candidate("vb", "vec-b", "vector", 2),
        Candidate("vc", "vec-c", "vector", 3),
    )
    shortlist = balanced_shortlist(exact, lexical, vector, 3)
    assert shortlist == ("lex-a", "vec-a", "lex-b", "vec-b", "lex-c", "vec-c")
    assert set(unique_documents(lexical, 3)) <= set(shortlist)
    assert set(unique_documents(vector, 3)) <= set(shortlist)
    assert len(VARIANT_ORDER) == 10 and len(set(VARIANT_ORDER)) == 10
    assert set(CONFIG_BY_NAME) == set(VARIANT_ORDER)
    lanes = {
        "exact": exact,
        "identity_lexical": lexical,
        "identity_vector": vector,
        "passage_lexical": lexical,
        "passage_vector": vector,
    }
    fused = supplemental_fusion(
        lanes,
        {
            "exact": 1,
            "identity_lexical": 2,
            "identity_vector": 4,
            "passage_lexical": 1,
            "passage_vector": 1,
        },
        Fused,
    )
    assert fused and fused[0].chunk_id == "va"
    assert all(item.evidence == () for item in fused)
    print("v13_41_supplemental_ranking_measurement_self_test=pass")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--python-root", type=Path)
    parser.add_argument("--chunks", type=Path)
    parser.add_argument("--expected-chunks-sha256")
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
        arguments.python_root,
        arguments.chunks,
        arguments.expected_chunks_sha256,
        arguments.truth,
        arguments.expected_truth_sha256,
        arguments.embedding_url,
        arguments.tokenizer_url,
        arguments.postgresql_socket,
        arguments.postgresql_port,
        arguments.postgresql_user,
        arguments.output,
    )
    base.require(all(value is not None for value in required), "arguments_missing")
    execute(arguments)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except base.MeasurementError as error:
        print(f"v13_41_supplemental_ranking_measurement=blocked;reason={error}")
        raise SystemExit(1) from error
