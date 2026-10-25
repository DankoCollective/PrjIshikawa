#!/usr/bin/env python3
"""Measure frozen V13-45 hierarchical document/section retrieval."""

from __future__ import annotations

import argparse
import hashlib
import os
import sys
import time
from dataclasses import replace
from fractions import Fraction
from pathlib import Path
from typing import Any, Mapping, Sequence

import measure_synthetic_corpus_v2_without_ingestion as base
import measure_synthetic_corpus_v3_preingestion as v3
import measure_v13_40_bounded_ranking_candidates as v40
import measure_v13_41_supplemental_ranking as v41
import measure_v13_44_decomposed_passage_reranking as v44


VARIANT_CONFIGS = (
    ("doc8_l2_v4_h2_p4", 8, 2, 4, 2, 4),
    ("doc16_l2_v4_h2_p4", 16, 2, 4, 2, 4),
    ("doc8_l1_v1_h2_p4", 8, 1, 1, 2, 4),
    ("doc16_l1_v1_h2_p4", 16, 1, 1, 2, 4),
    ("doc8_l2_v1_h2_p4", 8, 2, 1, 2, 4),
)
VARIANT_ORDER = tuple(item[0] for item in VARIANT_CONFIGS)
CONFIG_BY_NAME = {
    name: {
        "document_depth": depth,
        "document_lexical_weight": lexical,
        "document_vector_weight": vector,
        "heading_weight": heading,
        "passage_weight": passage,
    }
    for name, depth, lexical, vector, heading, passage in VARIANT_CONFIGS
}
RRF_CONSTANT = 60
LANE_WEIGHTS = {"lexical": 2, "vector": 4}


def heading_record(
    candidate: base.CandidateRecord,
    raw: Mapping[str, Mapping[str, Any]],
) -> base.CandidateRecord:
    """Create an ephemeral heading/path-only view of a section representative."""

    source = raw[candidate.chunk_id]
    anchor = source.get("citation_anchor")
    path = anchor.get("structural_path") if isinstance(anchor, dict) else None
    base.require(
        candidate.projection_kind == "section_page_representative"
        and isinstance(path, list)
        and path
        and len(path) <= 16
        and all(isinstance(item, str) and item.strip() == item and item for item in path),
        "section_heading_path_invalid",
    )
    return replace(candidate, retrieval_text="Section: " + " > ".join(path))


def _unique_document_ranks(candidates: Sequence[Any]) -> dict[str, int]:
    result: dict[str, int] = {}
    for candidate in candidates:
        if candidate.document_key not in result:
            result[candidate.document_key] = len(result) + 1
    return result


def rank_documents(
    exact: Sequence[Any],
    lexical: Sequence[Any],
    vector: Sequence[Any],
    config: Mapping[str, int],
) -> tuple[tuple[str, Fraction], ...]:
    """Rank unique documents from the existing primary lane order."""

    base.require(
        set(config) == {
            "document_depth",
            "document_lexical_weight",
            "document_vector_weight",
            "heading_weight",
            "passage_weight",
        }
        and config["document_depth"] in {8, 16}
        and config["document_lexical_weight"] in {1, 2}
        and config["document_vector_weight"] in {1, 4}
        and config["heading_weight"] == 2
        and config["passage_weight"] == 4,
        "hierarchical_config_invalid",
    )
    lane_ranks = {
        "exact": _unique_document_ranks(exact),
        "lexical": _unique_document_ranks(lexical),
        "vector": _unique_document_ranks(vector),
    }
    weights = {
        "exact": 1,
        "lexical": config["document_lexical_weight"],
        "vector": config["document_vector_weight"],
    }
    identities = set().union(*(set(item) for item in lane_ranks.values()))
    scored: list[tuple[str, Fraction, int]] = []
    for document_ref in identities:
        score = sum(
            (
                Fraction(weights[lane], RRF_CONSTANT + ranks[document_ref])
                for lane, ranks in lane_ranks.items()
                if document_ref in ranks
            ),
            Fraction(0, 1),
        )
        best_rank = min(
            ranks[document_ref]
            for ranks in lane_ranks.values()
            if document_ref in ranks
        )
        scored.append((document_ref, score, best_rank))
    scored.sort(key=lambda item: (-item[1], item[2], item[0]))
    result = tuple((document_ref, score) for document_ref, score, _ in scored)
    base.require(result, "hierarchical_document_ranking_empty")
    return result


def _rank_contribution(rank: int, lane_weight: int, signal_weight: int) -> Fraction:
    base.require(rank >= 1 and lane_weight > 0 and signal_weight > 0,
                 "section_rank_contribution_invalid")
    return Fraction(lane_weight * signal_weight, RRF_CONSTANT + rank)


def rank_sections(
    connection: Any,
    facets: Sequence[str],
    facet_vectors: Sequence[Sequence[float]],
    representatives: Sequence[base.CandidateRecord],
    headings: Mapping[str, base.CandidateRecord],
    passage_vectors: Mapping[str, Sequence[float]],
    heading_vectors: Mapping[str, Sequence[float]],
    config: Mapping[str, int],
    lane_candidate_type: Any,
) -> tuple[tuple[base.CandidateRecord, Fraction], ...]:
    """Rank sections inside one document using path and passage signals."""

    base.require(
        representatives
        and len(facets) == len(facet_vectors)
        and 1 <= len(facets) <= v44.MAX_FACETS
        and len({item.document_ref for item in representatives}) == 1,
        "within_document_section_inventory_invalid",
    )
    by_chunk = {item.chunk_id: item for item in representatives}
    heading_candidates = tuple(headings[item.chunk_id] for item in representatives)
    best_by_chunk = {item.chunk_id: Fraction(0, 1) for item in representatives}
    for facet, vector in zip(facets, facet_vectors, strict=True):
        lanes = {
            "heading_lexical": base.lexical_lane(
                connection, facet, heading_candidates, headings, lane_candidate_type
            ),
            "heading_vector": base.vector_lane(
                vector, heading_candidates, heading_vectors, lane_candidate_type
            ),
            "passage_lexical": base.lexical_lane(
                connection, facet, representatives, by_chunk, lane_candidate_type
            ),
            "passage_vector": base.vector_lane(
                vector, representatives, passage_vectors, lane_candidate_type
            ),
        }
        scores = {item.chunk_id: Fraction(0, 1) for item in representatives}
        for lane_name, candidates in lanes.items():
            signal_weight = (
                config["heading_weight"] if lane_name.startswith("heading_")
                else config["passage_weight"]
            )
            lane_weight = (
                LANE_WEIGHTS["lexical"] if lane_name.endswith("lexical")
                else LANE_WEIGHTS["vector"]
            )
            for candidate in candidates:
                scores[candidate.chunk_id] += _rank_contribution(
                    candidate.rank, lane_weight, signal_weight
                )
        for chunk_id, score in scores.items():
            best_by_chunk[chunk_id] = max(best_by_chunk[chunk_id], score)
    result = tuple(
        sorted(
            ((item, best_by_chunk[item.chunk_id]) for item in representatives),
            key=lambda pair: (
                -pair[1], pair[0].page_start, pair[0].page_end, pair[0].chunk_id
            ),
        )
    )
    base.require(result and all(score > 0 for _, score in result),
                 "within_document_section_ranking_invalid")
    return result


def round_robin_sections(
    document_order: Sequence[str],
    sections_by_document: Mapping[str, Sequence[tuple[Any, Fraction]]],
    fused_candidate_type: Any,
    raw: Mapping[str, Mapping[str, Any]],
    exact_document_refs: set[str],
    *,
    depth: int = 20,
) -> tuple[Any, ...]:
    """Emit each document's best section before any document's next section."""

    base.require(
        document_order
        and len(document_order) == len(set(document_order))
        and set(document_order) == set(sections_by_document)
        and depth == 20,
        "round_robin_section_inventory_invalid",
    )
    ordered: list[Any] = []
    section_index = 0
    while len(ordered) < depth:
        added = False
        for document_ref in document_order:
            sections = sections_by_document[document_ref]
            if section_index >= len(sections):
                continue
            candidate, section_score = sections[section_index]
            properties = raw[candidate.chunk_id]["projection_properties"]
            ordered.append(
                fused_candidate_type(
                    chunk_id=candidate.chunk_id,
                    document_id=candidate.document_id,
                    document_version_id=candidate.document_version_id,
                    document_key=candidate.document_ref,
                    fused_score=float(
                        Fraction(depth - len(ordered), depth) + section_score / 1000
                    ),
                    exact_priority=candidate.document_ref in exact_document_refs,
                    evidence=(),
                    retrieval_group_id=properties["retrieval_group_id"],
                    authoritative_chunk_ids=tuple(properties["component_chunk_ids"]),
                    retrieval_scoring_only=True,
                )
            )
            added = True
            if len(ordered) == depth:
                break
        if not added:
            break
        section_index += 1
    base.require(ordered, "round_robin_section_result_empty")
    return tuple(ordered)


def evaluate(
    connection: Any,
    cases: Sequence[base.Case],
    query_vectors: Sequence[Sequence[float]],
    facet_vectors: Mapping[str, Sequence[Sequence[float]]],
    candidate_vectors: Mapping[str, Sequence[float]],
    heading_vectors: Mapping[str, Sequence[float]],
    atomic: Sequence[base.CandidateRecord],
    representatives: Sequence[base.CandidateRecord],
    headings: Mapping[str, base.CandidateRecord],
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
        permitted_refs = {item.document_ref for item in permitted}
        exact = v3.enrich_lane(base.exact_lane(case, permitted, lane_candidate_type), raw)
        use_representations = not exact
        searchable = v40.searchable_candidates(
            case, permitted, representatives, raw, canonical,
            use_representations=use_representations,
        )
        lexical = v3.enrich_lane(
            base.lexical_lane(
                connection, case.question, searchable, canonical, lane_candidate_type
            ),
            raw,
        )
        vector = v3.enrich_lane(
            base.vector_lane(
                query_vector, searchable, candidate_vectors, lane_candidate_type
            ),
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
        hierarchy_by_name: dict[str, Mapping[str, Any] | None] = {
            "accepted_v6": None
        }

        if case.family == "body":
            facets = v44.decompose_query(case.question)
            vectors = facet_vectors[case.case_id]
            base.require(len(facets) == len(vectors), "facet_vector_inventory_invalid")
            permitted_representatives = tuple(
                item for item in representatives if item.document_ref in permitted_refs
            )
            reps_by_document: dict[str, tuple[base.CandidateRecord, ...]] = {
                document_ref: tuple(
                    item for item in permitted_representatives
                    if item.document_ref == document_ref
                )
                for document_ref in sorted(
                    {item.document_ref for item in permitted_representatives}
                )
            }
            exact_refs = {item.document_key for item in exact}
            ranked_documents_by_name = {
                name: rank_documents(exact, lexical, vector, CONFIG_BY_NAME[name])
                for name in VARIANT_ORDER
            }
            shortlists_by_name = {
                name: tuple(
                    document_ref
                    for document_ref, _ in ranked_documents_by_name[name]
                    if document_ref in reps_by_document
                )[: CONFIG_BY_NAME[name]["document_depth"]]
                for name in VARIANT_ORDER
            }
            base.require(
                all(shortlists_by_name.values()),
                "hierarchical_document_shortlist_empty",
            )
            section_documents = tuple(
                sorted(set().union(*(set(items) for items in shortlists_by_name.values())))
            )
            # All frozen candidates use the same section-signal weights.  Measure
            # each document once per case and reuse that deterministic ordering.
            section_config = CONFIG_BY_NAME[VARIANT_ORDER[0]]
            base.require(
                all(
                    config["heading_weight"] == section_config["heading_weight"]
                    and config["passage_weight"] == section_config["passage_weight"]
                    for config in CONFIG_BY_NAME.values()
                ),
                "section_weight_reuse_invalid",
            )
            section_ranks = {
                document_ref: rank_sections(
                    connection, facets, vectors,
                    reps_by_document[document_ref], headings,
                    candidate_vectors, heading_vectors, section_config,
                    lane_candidate_type,
                )
                for document_ref in section_documents
            }
            for name in VARIANT_ORDER:
                config = CONFIG_BY_NAME[name]
                ranked_documents = ranked_documents_by_name[name]
                shortlisted = shortlists_by_name[name]
                selected_by_name[name] = round_robin_sections(
                    shortlisted,
                    {document_ref: section_ranks[document_ref]
                     for document_ref in shortlisted},
                    fused_candidate_type, raw, exact_refs,
                )
                hierarchy_by_name[name] = {
                    "facet_count": len(facets),
                    "facet_sha256": [
                        hashlib.sha256(item.encode("utf-8")).hexdigest()
                        for item in facets
                    ],
                    "document_shortlist": list(shortlisted),
                    "document_ranking": [
                        {
                            "document_ref": document_ref,
                            "rank": rank,
                            "score": format(float(score), ".17g"),
                        }
                        for rank, (document_ref, score) in enumerate(
                            ranked_documents, 1
                        )
                    ],
                }
        else:
            for name in VARIANT_ORDER:
                selected_by_name[name] = baseline
                hierarchy_by_name[name] = None

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
            measured["hierarchical_config"] = (
                None
                if name == "accepted_v6" or case.family != "body"
                else CONFIG_BY_NAME[name]
            )
            measured["hierarchy"] = hierarchy_by_name[name]
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
        name: v44._rank_movements(selections["accepted_v6"], selections[name])
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
    headings = {
        item.chunk_id: heading_record(item, raw) for item in representatives
    }
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
        case.case_id: v44.decompose_query(case.question)
        for case in cases if case.family == "body"
    }
    facet_inputs = [
        facet
        for case in cases if case.family == "body"
        for facet in facets_by_case[case.case_id]
    ]
    secret_text = os.environ.pop("ISHIKAWA_NOMIC_API_KEY", "")
    base.require(
        32 <= len(secret_text) <= 1024
        and "\n" not in secret_text and "\r" not in secret_text,
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
        heading_raw, heading_tokens = v3.embed_inputs(
            client, [DOCUMENT_PREFIX + item.retrieval_text for item in headings.values()]
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
        item.chunk_id: vector
        for item, vector in zip(candidates, candidate_raw, strict=True)
    }
    heading_vectors = {
        item.chunk_id: vector
        for item, vector in zip(headings.values(), heading_raw, strict=True)
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
            heading_vectors, atomic, representatives, headings, raw, canonical,
            profile, LaneCandidate, FusedCandidate, collapse_retrieval_groups,
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
        "artifact_kind": "ishikawa_v13_45_hierarchical_document_section_experiment",
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
            "maximum_facets": v44.MAX_FACETS,
            "minimum_facet_words": v44.MIN_FACET_WORDS,
            "document_ranking": "unique_document_rrf_from_existing_primary_lanes",
            "section_ranking": "best_literal_facet_heading_path_plus_passage_rrf",
            "section_emission": "document_order_round_robin_best_section_first",
            "primary_weights": {"exact": 1, "lexical": 2, "vector": 4},
            "section_lane_weights": LANE_WEIGHTS,
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
            "ephemeral_heading_views": len(headings),
        },
        "case_inventory": {"body": 120, "relationship": 30, "header": 30, "total": 180},
        "runtime_identity_digest": runtime_identity,
        "token_usage": {
            "candidate_embedding_tokens": candidate_tokens,
            "heading_embedding_tokens": heading_tokens,
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
            "structural_path_text_retained": False,
        },
        "promotion_authorized": False,
        "next_gate": "review_and_separately_freeze_any_selected_candidate",
    }
    identity = {
        key: value for key, value in artifact.items()
        if key not in {"latency_ms", "variants"}
    }
    artifact["experiment_id"] = base.domain_digest(
        "ishikawa.v13-45-hierarchical-document-section-experiment.v1", identity
    )
    base.write_exclusive(arguments.output, base.canonical_json_bytes(artifact) + b"\n")
    print("purpose=measure_v13_45_hierarchical_document_section_ranking")
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
    print("v13_45_hierarchical_document_section_ranking_measurement=pass")


def self_test() -> None:
    class Candidate:
        def __init__(self, document_key: str, rank: int):
            self.document_key = document_key
            self.rank = rank

    lexical = (Candidate("A", 1), Candidate("A", 2), Candidate("B", 3))
    vector = (Candidate("B", 1), Candidate("C", 2), Candidate("A", 3))
    ranked = rank_documents(
        (), lexical, vector, CONFIG_BY_NAME["doc8_l2_v1_h2_p4"]
    )
    assert [item[0] for item in ranked] == ["A", "B", "C"]

    class Section:
        def __init__(self, chunk_id: str, document_ref: str):
            self.chunk_id = chunk_id
            self.document_id = document_ref + "-document"
            self.document_version_id = document_ref + "-version"
            self.document_ref = document_ref

    class Result:
        def __init__(self, **values: Any):
            self.__dict__.update(values)

    a1, a2, b1, b2 = (
        Section("a1", "A"), Section("a2", "A"),
        Section("b1", "B"), Section("b2", "B"),
    )
    raw = {
        item.chunk_id: {"projection_properties": {
            "retrieval_group_id": item.chunk_id + "-group",
            "component_chunk_ids": [item.chunk_id + "-atomic"],
        }}
        for item in (a1, a2, b1, b2)
    }
    emitted = round_robin_sections(
        ("A", "B"),
        {"A": ((a1, Fraction(2, 1)), (a2, Fraction(1, 1))),
         "B": ((b1, Fraction(2, 1)), (b2, Fraction(1, 1)))},
        Result, raw, set(),
    )
    assert [item.chunk_id for item in emitted] == ["a1", "b1", "a2", "b2"]
    assert len(VARIANT_ORDER) == len(set(VARIANT_ORDER)) == 5
    assert set(CONFIG_BY_NAME) == set(VARIANT_ORDER)
    print("v13_45_hierarchical_document_section_ranking_measurement_self_test=pass")


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
        arguments.expected_chunks_sha256,
        arguments.chunk_profile_id,
        arguments.truth,
        arguments.expected_truth_sha256,
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
            f"v13_45_hierarchical_document_section_ranking_measurement=blocked;reason={error}",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
