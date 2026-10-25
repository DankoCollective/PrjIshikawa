#!/usr/bin/env python3
"""Measure frozen V13-44 decomposed within-document passage reranking."""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import sys
import time
from pathlib import Path
from typing import Any, Mapping, Sequence

import measure_synthetic_corpus_v2_without_ingestion as base
import measure_synthetic_corpus_v3_preingestion as v3
import measure_v13_40_bounded_ranking_candidates as v40
import measure_v13_41_supplemental_ranking as v41


VARIANT_CONFIGS = (
    ("facet3_b2_e1_c0", 3, 2, 1, 0),
    ("facet5_b2_e1_c0", 5, 2, 1, 0),
    ("facet5_b1_e1_c0", 5, 1, 1, 0),
    ("facet5_b1_e2_c0", 5, 1, 2, 0),
    ("facet5_b2_e1_c1", 5, 2, 1, 1),
)
VARIANT_ORDER = tuple(item[0] for item in VARIANT_CONFIGS)
CONFIG_BY_NAME = {
    name: {
        "shortlist_per_lane": shortlist,
        "baseline_weight": baseline,
        "best_facet_weight": expansion,
        "facet_coverage_weight": coverage,
    }
    for name, shortlist, baseline, expansion, coverage in VARIANT_CONFIGS
}
MAX_FACETS = 4
MIN_FACET_WORDS = 3
RRF_CONSTANT = 60
CLAUSE_BOUNDARY = re.compile(
    r"\s*(?:;|\b(?:and|or)\b(?=\s+(?:what|when|where|who|why|how|which|whether|under)\b))\s*",
    re.IGNORECASE,
)
WORD = re.compile(r"[A-Za-z0-9]+(?:[-'][A-Za-z0-9]+)*")


def decompose_query(question: str) -> tuple[str, ...]:
    """Return at most four deterministic clauses without semantic invention."""

    base.require(
        isinstance(question, str)
        and question.strip() == question
        and question
        and len(question) <= 4096,
        "query_decomposition_input_invalid",
    )
    source = question[:-1] if question.endswith("?") else question
    clauses = [item.strip(" ,:.-") for item in CLAUSE_BOUNDARY.split(source)]
    clauses = [item for item in clauses if len(WORD.findall(item)) >= MIN_FACET_WORDS]
    unique: list[str] = []
    for clause in clauses:
        folded = clause.casefold()
        if folded not in {item.casefold() for item in unique}:
            unique.append(clause)
    # An indivisible question still receives bounded within-document expansion.
    result = tuple(unique[:MAX_FACETS]) if len(unique) > 1 else (question,)
    base.require(
        1 <= len(result) <= MAX_FACETS
        and all(item.strip() == item and item for item in result),
        "query_decomposition_result_invalid",
    )
    return result


def _rank_contribution(rank: int, weight: int) -> float:
    base.require(rank >= 1 and weight >= 0, "rerank_contribution_invalid")
    return weight / (RRF_CONSTANT + rank)


def decomposed_rerank(
    baseline: Sequence[Any],
    facet_lanes: Sequence[Mapping[str, Sequence[Any]]],
    config: Mapping[str, int],
    fused_candidate_type: Any,
) -> tuple[Any, ...]:
    """Fuse baseline RRF with each candidate's best query-facet RRF score."""

    base.require(
        1 <= len(facet_lanes) <= MAX_FACETS
        and set(config)
        == {
            "shortlist_per_lane",
            "baseline_weight",
            "best_facet_weight",
            "facet_coverage_weight",
        }
        and config["shortlist_per_lane"] in {3, 5}
        and config["baseline_weight"] in {1, 2}
        and config["best_facet_weight"] in {1, 2}
        and config["facet_coverage_weight"] in {0, 1},
        "decomposed_rerank_config_invalid",
    )
    states: dict[str, dict[str, Any]] = {}
    for rank, candidate in enumerate(baseline, 1):
        states[candidate.chunk_id] = {
            "document_id": candidate.document_id,
            "document_version_id": candidate.document_version_id,
            "document_key": candidate.document_key,
            "baseline_score": float(candidate.fused_score),
            "baseline_rank": rank,
            "exact_priority": bool(candidate.exact_priority),
            "retrieval_group_id": candidate.retrieval_group_id,
            "authoritative_chunk_ids": candidate.authoritative_chunk_ids,
            "retrieval_scoring_only": candidate.retrieval_scoring_only,
            "facet_scores": {},
            "best_expansion_rank": 10**9,
        }
    for facet_index, lanes in enumerate(facet_lanes):
        base.require(set(lanes) == {"lexical", "vector"}, "facet_lane_inventory_invalid")
        per_facet: dict[str, float] = {}
        for lane_name, lane_weight in (("lexical", 2), ("vector", 4)):
            seen: set[str] = set()
            for candidate in lanes[lane_name]:
                base.require(
                    candidate.chunk_id not in seen and candidate.lane == lane_name,
                    "facet_lane_candidate_invalid",
                )
                seen.add(candidate.chunk_id)
                state = states.setdefault(
                    candidate.chunk_id,
                    {
                        "document_id": candidate.document_id,
                        "document_version_id": candidate.document_version_id,
                        "document_key": candidate.document_key,
                        "baseline_score": 0.0,
                        "baseline_rank": 10**9,
                        "exact_priority": False,
                        "retrieval_group_id": candidate.retrieval_group_id,
                        "authoritative_chunk_ids": candidate.authoritative_chunk_ids,
                        "retrieval_scoring_only": candidate.retrieval_scoring_only,
                        "facet_scores": {},
                        "best_expansion_rank": 10**9,
                    },
                )
                base.require(
                    (
                        state["document_id"],
                        state["document_version_id"],
                        state["document_key"],
                    )
                    == (
                        candidate.document_id,
                        candidate.document_version_id,
                        candidate.document_key,
                    ),
                    "rerank_candidate_identity_conflict",
                )
                contribution = _rank_contribution(candidate.rank, lane_weight)
                per_facet[candidate.chunk_id] = (
                    per_facet.get(candidate.chunk_id, 0.0) + contribution
                )
                state["best_expansion_rank"] = min(
                    state["best_expansion_rank"], candidate.rank
                )
        for chunk_id, score in per_facet.items():
            states[chunk_id]["facet_scores"][facet_index] = score

    fused: list[Any] = []
    facet_count = len(facet_lanes)
    for chunk_id, state in states.items():
        facet_scores = tuple(state["facet_scores"].values())
        best_facet = max(facet_scores, default=0.0)
        coverage = len(facet_scores)
        coverage_score = coverage / ((RRF_CONSTANT + 1) * facet_count)
        score = (
            config["baseline_weight"] * state["baseline_score"]
            + config["best_facet_weight"] * best_facet
            + config["facet_coverage_weight"] * coverage_score
        )
        fused.append(
            fused_candidate_type(
                chunk_id=chunk_id,
                document_id=state["document_id"],
                document_version_id=state["document_version_id"],
                document_key=state["document_key"],
                fused_score=score,
                exact_priority=state["exact_priority"],
                evidence=(),
                retrieval_group_id=state["retrieval_group_id"],
                authoritative_chunk_ids=state["authoritative_chunk_ids"],
                retrieval_scoring_only=state["retrieval_scoring_only"],
            )
        )
    result = tuple(
        sorted(
            fused,
            key=lambda item: (
                -int(item.exact_priority),
                -item.fused_score,
                states[item.chunk_id]["baseline_rank"],
                states[item.chunk_id]["best_expansion_rank"],
                item.chunk_id,
            ),
        )
    )
    base.require(result, "decomposed_rerank_empty")
    return result


def _rank_movements(
    reference: Sequence[Mapping[str, Any]], candidate: Sequence[Mapping[str, Any]]
) -> dict[str, int]:
    ref = {item["case_id"]: item for item in reference if item["family"] == "body"}
    other = {item["case_id"]: item for item in candidate if item["family"] == "body"}
    base.require(set(ref) == set(other) and len(ref) == 120, "rank_comparison_invalid")
    counts = {
        "improved": 0,
        "unchanged": 0,
        "regressed": 0,
        "missing_fixed": 0,
        "new_missing": 0,
    }
    for case_id in sorted(ref):
        before = ref[case_id]["first_relevant_rank"]
        after = other[case_id]["first_relevant_rank"]
        before_value = 21 if before is None else before
        after_value = 21 if after is None else after
        if before is None and after is not None:
            counts["missing_fixed"] += 1
        if before is not None and after is None:
            counts["new_missing"] += 1
        if after_value < before_value:
            counts["improved"] += 1
        elif after_value > before_value:
            counts["regressed"] += 1
        else:
            counts["unchanged"] += 1
    base.require(sum(counts[key] for key in ("improved", "unchanged", "regressed")) == 120,
                 "rank_comparison_count_invalid")
    return counts


def evaluate(
    connection: Any,
    cases: Sequence[base.Case],
    query_vectors: Sequence[Sequence[float]],
    facet_vectors: Mapping[str, Sequence[Sequence[float]]],
    candidate_vectors: Mapping[str, Sequence[float]],
    atomic: Sequence[base.CandidateRecord],
    representatives: Sequence[base.CandidateRecord],
    raw: Mapping[str, Mapping[str, Any]],
    canonical: Mapping[str, base.CandidateRecord],
    profile: Any,
    lane_candidate_type: Any,
    fused_candidate_type: Any,
    collapse_retrieval_groups: Any,
    expand_authoritative_candidates: Any,
    reciprocal_rank_fusion: Any,
) -> tuple[dict[str, Any], dict[str, Any]]:
    names = ("accepted_v6", *VARIANT_ORDER)
    selections: dict[str, list[dict[str, Any]]] = {name: [] for name in names}
    expansions: dict[str, list[dict[str, Any]]] = {name: [] for name in names}
    atomic_ids = {item.chunk_id for item in atomic}

    for case, query_vector in zip(cases, query_vectors, strict=True):
        permitted = base.permitted_candidates(case, atomic)
        exact = v3.enrich_lane(base.exact_lane(case, permitted, lane_candidate_type), raw)
        use_representations = not exact
        searchable = v40.searchable_candidates(
            case, permitted, representatives, raw, canonical,
            use_representations=use_representations,
        )
        lexical = v3.enrich_lane(
            base.lexical_lane(connection, case.question, searchable, canonical,
                              lane_candidate_type),
            raw,
        )
        vector = v3.enrich_lane(
            base.vector_lane(query_vector, searchable, candidate_vectors,
                             lane_candidate_type),
            raw,
        )
        baseline = v40.select_results(
            exact, lexical, vector,
            use_representations=use_representations,
            profile=profile,
            collapse_retrieval_groups=collapse_retrieval_groups,
            reciprocal_rank_fusion=reciprocal_rank_fusion,
        )
        selected_by_name: dict[str, tuple[Any, ...]] = {"accepted_v6": baseline}
        diagnostics: dict[str, dict[str, Any]] = {}

        if case.family == "body":
            facets = decompose_query(case.question)
            vectors = facet_vectors[case.case_id]
            base.require(len(facets) == len(vectors), "facet_vector_inventory_invalid")
            for depth in (3, 5):
                shortlist = v41.balanced_shortlist(exact, lexical, vector, depth)
                expanded_searchable = v40.searchable_candidates(
                    case, permitted, representatives, raw, canonical,
                    use_representations=use_representations,
                    allowed_refs=set(shortlist),
                )
                lanes: list[dict[str, tuple[Any, ...]]] = []
                for facet, facet_vector in zip(facets, vectors, strict=True):
                    facet_lexical = v3.enrich_lane(
                        base.lexical_lane(
                            connection, facet, expanded_searchable, canonical,
                            lane_candidate_type,
                        ),
                        raw,
                    )
                    facet_vector_lane = v3.enrich_lane(
                        base.vector_lane(
                            facet_vector, expanded_searchable, candidate_vectors,
                            lane_candidate_type,
                        ),
                        raw,
                    )
                    lanes.append({"lexical": facet_lexical, "vector": facet_vector_lane})
                diagnostics[str(depth)] = {
                    "facet_sha256": [
                        hashlib.sha256(item.encode("utf-8")).hexdigest()
                        for item in facets
                    ],
                    "facet_count": len(facets),
                    "document_shortlist": list(shortlist),
                    "expanded_searchable_count": len(expanded_searchable),
                    "facet_lanes": [
                        {
                            lane_name: [
                                base.rank_record(rank, item, canonical)
                                for rank, item in enumerate(lane, 1)
                            ]
                            for lane_name, lane in facet_lane.items()
                        }
                        for facet_lane in lanes
                    ],
                }
                for name in VARIANT_ORDER:
                    config = CONFIG_BY_NAME[name]
                    if config["shortlist_per_lane"] != depth:
                        continue
                    fused = decomposed_rerank(
                        baseline, lanes, config, fused_candidate_type
                    )
                    if use_representations:
                        fused = collapse_retrieval_groups(fused)
                    selected_by_name[name] = tuple(fused[: profile.fused_candidate_depth])
        else:
            for name in VARIANT_ORDER:
                selected_by_name[name] = baseline

        base.require(set(selected_by_name) == set(names), "variant_selection_missing")
        for name in names:
            selected = selected_by_name[name]
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
            config = None if name == "accepted_v6" else CONFIG_BY_NAME[name]
            measured["decomposed_rerank_config"] = config
            measured["decomposition"] = (
                None if config is None or case.family != "body"
                else diagnostics[str(config["shortlist_per_lane"])]
            )
            selections[name].append(measured)
            matched = sum(
                any(base.matches(canonical[item.chunk_id], evidence) for item in expanded)
                for evidence in case.required_evidence
            )
            expansions[name].append({
                "case_id": case.case_id,
                "family": case.family,
                "matched_evidence_count": matched,
                "required_evidence_count": len(case.required_evidence),
                "expanded_atomic_count": len(expanded),
            })

    variants = {
        name: v41.summarize_variant(selections[name], expansions[name])
        for name in names
    }
    movements = {
        name: _rank_movements(selections["accepted_v6"], selections[name])
        for name in VARIANT_ORDER
    }
    return variants, movements


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
    python_root = arguments.python_root.resolve(strict=True)
    sys.path.insert(0, str(python_root))
    from embed_document_candidates_via_endpoint import DOCUMENT_PREFIX, EndpointClient, wipe
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
    base.require(chunks.get("method_profile_id") == arguments.chunk_profile_id,
                 "accepted_chunk_profile_invalid")
    cases = v3.load_cases(truth)
    atomic, representatives, raw = v3.representation_inventory(chunks)
    candidates = atomic + representatives
    canonical = {item.chunk_id: item for item in candidates}
    profile = ACCEPTED_RETRIEVAL_PROFILE
    base.require(
        profile.exact_weight == 1
        and profile.lexical_weight == 2
        and profile.vector_weight == 4
        and profile.exact_candidate_depth == 1
        and profile.lexical_candidate_depth == 20
        and profile.vector_candidate_depth == 20
        and profile.fused_candidate_depth == 20
        and profile.rrf_constant == RRF_CONSTANT
        and profile.section_page_representatives is True
        and profile.document_local_duplicate_canonicalization is True,
        "accepted_retrieval_profile_changed",
    )

    facets_by_case = {
        case.case_id: decompose_query(case.question)
        for case in cases if case.family == "body"
    }
    facet_inputs = [
        facet
        for case in cases if case.family == "body"
        for facet in facets_by_case[case.case_id]
    ]
    secret_text = os.environ.pop("ISHIKAWA_NOMIC_API_KEY", "")
    base.require(
        32 <= len(secret_text) <= 1024 and "\n" not in secret_text
        and "\r" not in secret_text,
        "nomic_credential_invalid",
    )
    secret = bytearray(secret_text.encode("utf-8"))
    secret_text = ""
    embedding_started = time.perf_counter_ns()
    try:
        client = EndpointClient(arguments.embedding_url, arguments.tokenizer_url, secret)
        runtime_identity = client.model_identity()
        candidate_raw, candidate_tokens = v3.embed_inputs(
            client, [DOCUMENT_PREFIX + item.retrieval_text for item in candidates]
        )
        query_vectors, query_tokens = v3.embed_inputs(
            client, [base.QUERY_PREFIX + item.question for item in cases]
        )
        facet_raw, facet_tokens = v3.embed_inputs(
            client, [base.QUERY_PREFIX + item for item in facet_inputs]
        )
    finally:
        if "client" in locals():
            client.close()
        wipe(secret)
    embedding_ms = (time.perf_counter_ns() - embedding_started) / 1_000_000
    candidate_vectors = {
        item.chunk_id: vector for item, vector in zip(candidates, candidate_raw, strict=True)
    }
    facet_vectors: dict[str, tuple[Sequence[float], ...]] = {}
    offset = 0
    for case in cases:
        if case.family != "body":
            continue
        count = len(facets_by_case[case.case_id])
        facet_vectors[case.case_id] = tuple(facet_raw[offset:offset + count])
        offset += count
    base.require(offset == len(facet_raw), "facet_embedding_alignment_invalid")

    try:
        import psycopg
        connection = psycopg.connect(
            host=str(arguments.postgresql_socket),
            port=arguments.postgresql_port,
            dbname="postgres",
            user=arguments.postgresql_user,
            connect_timeout=5,
            autocommit=True,
        )
    except Exception as error:
        raise base.MeasurementError("temporary_postgresql_connection_failed") from error
    retrieval_started = time.perf_counter_ns()
    try:
        connection.execute("BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
        state = connection.execute(
            "SELECT current_setting('transaction_read_only'), current_database(), current_user"
        ).fetchone()
        base.require(state == ("on", "postgres", arguments.postgresql_user),
                     "temporary_postgresql_boundary_invalid")
        variants, movements = evaluate(
            connection, cases, query_vectors, facet_vectors, candidate_vectors,
            atomic, representatives, raw, canonical, profile, LaneCandidate,
            FusedCandidate, collapse_retrieval_groups,
            expand_authoritative_candidates, reciprocal_rank_fusion,
        )
        connection.rollback()
    finally:
        connection.close()
    retrieval_ms = (time.perf_counter_ns() - retrieval_started) / 1_000_000
    for name in VARIANT_ORDER:
        variants[name]["rank_movement"] = movements[name]

    qualified = [
        name for name in VARIANT_ORDER
        if variants[name]["gate"]["status"] == "qualified"
    ]
    selected = max(qualified, key=lambda name: selection_key(name, variants[name])) \
        if qualified else None
    artifact: dict[str, Any] = {
        "artifact_kind": "ishikawa_v13_44_decomposed_passage_reranking_experiment",
        "schema_version": 1,
        "corpus_identity": "synthetic-corpus-v3",
        "measurement_class": "evaluation_only_no_promotion",
        "source_sha256": {
            "chunks": arguments.expected_chunks_sha256,
            "retrieval_truth": arguments.expected_truth_sha256,
        },
        "profiles": {
            "chunk_profile_id": arguments.chunk_profile_id,
            "retrieval_profile_id": profile.digest,
        },
        "experiment": {
            "variant_order": list(VARIANT_ORDER),
            "variant_configs": CONFIG_BY_NAME,
            "body_mrr_gate": "0.89",
            "body_coverage_gate": "120/120",
            "maximum_facets": MAX_FACETS,
            "minimum_facet_words": MIN_FACET_WORDS,
            "decomposition": "punctuation_or_interrogative_conjunction_no_semantic_invention",
            "document_shortlist": "balanced_union_per_primary_lane_plus_exact",
            "passage_expansion": "all_permitted_v6_candidates_inside_shortlist",
            "final_reranker": "baseline_plus_best_facet_rrf_with_optional_coverage",
            "primary_weights": {"exact": 1, "lexical": 2, "vector": 4},
            "facet_weights": {"lexical": 2, "vector": 4},
            "rrf_constant": RRF_CONSTANT,
            "learned_reranker": False,
            "selection_order": [
                "body_mrr_at_20_desc",
                "body_relevant_at_5_desc",
                "body_regression_count_asc",
                "declared_variant_order",
            ],
        },
        "candidate_inventory": {
            "documents": 30,
            "atomic": len(atomic),
            "representatives": len(representatives),
            "passage_total": len(candidates),
        },
        "case_inventory": {"body": 120, "relationship": 30, "header": 30, "total": 180},
        "runtime_identity_digest": runtime_identity,
        "token_usage": {
            "candidate_embedding_tokens": candidate_tokens,
            "query_embedding_tokens": query_tokens,
            "decomposed_query_embedding_tokens": facet_tokens,
        },
        "latency_ms": {
            "embeddings": format(embedding_ms, ".3f"),
            "retrieval_and_measurement": format(retrieval_ms, ".3f"),
        },
        "variants": variants,
        "qualified_candidates": qualified,
        "selected_candidate": selected,
        "selection_status": "qualified_for_separate_freeze" if selected else "not_met",
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
            "decomposed_query_text_retained": False,
            "query_vectors_retained": False,
            "source_text_retained": False,
        },
        "promotion_authorized": False,
        "next_gate": "review_and_separately_freeze_any_selected_candidate",
    }
    identity = {
        key: value for key, value in artifact.items()
        if key not in {"latency_ms", "variants"}
    }
    artifact["experiment_id"] = base.domain_digest(
        "ishikawa.v13-44-decomposed-passage-reranking-experiment.v1", identity
    )
    base.write_exclusive(arguments.output, base.canonical_json_bytes(artifact) + b"\n")
    print("purpose=measure_v13_44_decomposed_passage_reranking")
    for name in ("accepted_v6", *VARIANT_ORDER):
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
    print("v13_44_decomposed_passage_reranking_measurement=pass")


def self_test() -> None:
    assert decompose_query(
        "What steps apply to misuse or loss, and when is the control incomplete?"
    ) == (
        "What steps apply to misuse or loss",
        "when is the control incomplete",
    )
    assert decompose_query("What policy applies?") == ("What policy applies?",)
    assert len(VARIANT_ORDER) == len(set(VARIANT_ORDER)) == 5
    assert set(CONFIG_BY_NAME) == set(VARIANT_ORDER)

    class Fused:
        def __init__(self, chunk: str, score: float, rank: int):
            self.chunk_id = chunk
            self.document_id = "document"
            self.document_version_id = "version"
            self.document_key = "key"
            self.fused_score = score
            self.exact_priority = False
            self.retrieval_group_id = chunk
            self.authoritative_chunk_ids = (chunk,)
            self.retrieval_scoring_only = False
            self.rank = rank

    class Lane:
        def __init__(self, chunk: str, lane: str, rank: int):
            self.chunk_id = chunk
            self.document_id = "document"
            self.document_version_id = "version"
            self.document_key = "key"
            self.lane = lane
            self.rank = rank
            self.retrieval_group_id = chunk
            self.authoritative_chunk_ids = (chunk,)
            self.retrieval_scoring_only = False

    class Result:
        def __init__(self, **values: Any):
            self.__dict__.update(values)

    baseline = (Fused("baseline", 0.10, 1), Fused("expanded", 0.01, 2))
    lanes = ({
        "lexical": (Lane("expanded", "lexical", 1),),
        "vector": (Lane("expanded", "vector", 1),),
    },)
    result = decomposed_rerank(
        baseline,
        lanes,
        CONFIG_BY_NAME["facet5_b1_e2_c0"],
        Result,
    )
    assert [item.chunk_id for item in result] == ["expanded", "baseline"]
    print("v13_44_decomposed_passage_reranking_measurement_self_test=pass")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--python-root", type=Path)
    parser.add_argument("--chunks", type=Path)
    parser.add_argument("--expected-chunks-sha256")
    parser.add_argument("--chunk-profile-id")
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
        arguments.chunk_profile_id,
        arguments.truth,
        arguments.embedding_url,
        arguments.tokenizer_url,
        arguments.postgresql_socket,
        arguments.postgresql_port,
        arguments.postgresql_user,
        arguments.output,
    )
    if any(value is None for value in required):
        parser.error("measurement arguments are required without --self-test")
    try:
        execute(arguments)
    except (base.MeasurementError, OSError, ValueError, KeyError) as error:
        print(
            f"v13_44_decomposed_passage_reranking_measurement=blocked;reason={error}",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
