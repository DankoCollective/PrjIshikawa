#!/usr/bin/env python3
"""Compare the frozen V13-40 retrieval candidates without publishing them."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
from dataclasses import replace
from fractions import Fraction
from pathlib import Path
from typing import Any, Mapping, Sequence

import measure_synthetic_corpus_v2_without_ingestion as base
import measure_synthetic_corpus_v3_preingestion as v3


VARIANT_ORDER = (
    "current_identity_both",
    "identity_lexical_passage_vector",
    "passage_only",
    "two_stage_top3",
    "two_stage_top5",
)
BODY_MRR_GATE = Fraction(89, 100)


def passage_record(
    candidate: base.CandidateRecord,
    raw: Mapping[str, Mapping[str, Any]],
) -> base.CandidateRecord:
    """Remove only the trusted V13-39 retrieval-only identity prefix."""

    source = raw[candidate.chunk_id]
    identity = source["projection_properties"].get(
        "retrieval_document_identity_context"
    )
    base.require(isinstance(identity, dict), "identity_context_missing")
    included = identity.get("included_in_retrieval_text")
    if candidate.projection_kind == "document_control_metadata":
        base.require(included is False, "metadata_identity_context_invalid")
        return candidate
    base.require(
        included is True
        and identity.get("document_context") == candidate.document_context
        and identity.get("policy_number") == candidate.policy_number,
        "identity_context_invalid",
    )
    lines = candidate.retrieval_text.splitlines()
    expected = (
        f"Document: {candidate.document_context}",
        f"Document identifier: {candidate.policy_number}",
    )
    base.require(
        len(lines) >= 4 and tuple(lines[:2]) == expected,
        "identity_prefix_invalid",
    )
    text = "\n".join(lines[2:]).strip()
    base.require(text and not text.startswith("Document:"), "passage_text_invalid")
    return replace(candidate, retrieval_text=text)


def searchable_candidates(
    case: base.Case,
    permitted_atomic: Sequence[base.CandidateRecord],
    representatives: Sequence[base.CandidateRecord],
    raw: Mapping[str, Mapping[str, Any]],
    view: Mapping[str, base.CandidateRecord],
    *,
    use_representations: bool,
    allowed_refs: set[str] | None = None,
) -> tuple[base.CandidateRecord, ...]:
    permitted_refs = {item.document_ref for item in permitted_atomic}
    if allowed_refs is not None:
        permitted_refs &= allowed_refs
    atomic = tuple(
        view[item.chunk_id]
        for item in permitted_atomic
        if item.document_ref in permitted_refs
        and (
            case.family == "header"
            or item.projection_kind != "document_control_metadata"
        )
        and (
            not use_representations
            or raw[item.chunk_id]["projection_properties"][
                "document_local_content_canonical"
            ]
        )
    )
    scoring = (
        tuple(
            view[item.chunk_id]
            for item in representatives
            if item.document_ref in permitted_refs
        )
        if use_representations
        else ()
    )
    result = atomic + scoring
    base.require(result, "searchable_candidate_set_empty")
    return result


def document_shortlist(
    exact: Sequence[Any],
    lexical: Sequence[Any],
    vector: Sequence[Any],
    depth: int,
) -> tuple[str, ...]:
    """Rank documents by each lane's best rank, never by chunk frequency."""

    base.require(depth in {3, 5}, "document_shortlist_depth_invalid")
    best: dict[str, dict[str, int]] = {}
    for lane, candidates in (
        ("exact", exact),
        ("lexical", lexical),
        ("vector", vector),
    ):
        for item in candidates:
            ranks = best.setdefault(item.document_key, {})
            ranks[lane] = min(ranks.get(lane, item.rank), item.rank)
    weights = {"exact": 1, "lexical": 2, "vector": 4}
    scored = []
    for document_ref, ranks in best.items():
        score = sum(
            Fraction(weights[lane], 60 + rank)
            for lane, rank in ranks.items()
        )
        scored.append((score, document_ref))
    scored.sort(key=lambda item: (-item[0], item[1]))
    result = tuple(document_ref for _, document_ref in scored[:depth])
    base.require(result, "document_shortlist_empty")
    return result


def select_results(
    exact: Sequence[Any],
    lexical: Sequence[Any],
    vector: Sequence[Any],
    *,
    use_representations: bool,
    profile: Any,
    collapse_retrieval_groups: Any,
    reciprocal_rank_fusion: Any,
) -> tuple[Any, ...]:
    fused = reciprocal_rank_fusion(
        {"exact": exact, "lexical": lexical, "vector": vector},
        rrf_constant=profile.rrf_constant,
        lane_weights={
            "exact": profile.exact_weight,
            "lexical": profile.lexical_weight,
            "vector": profile.vector_weight,
        },
    )
    if use_representations:
        fused = collapse_retrieval_groups(fused)
    return tuple(fused[: profile.fused_candidate_depth])


def gate_for(
    metrics: Mapping[str, Mapping[str, Any]],
    expansion_matched: int,
    expansion_total: int,
) -> dict[str, Any]:
    body = metrics["body"]
    relationship = metrics["relationship"]
    header = metrics["header"]
    checks = {
        "body_mrr_at_20": Fraction(
            body["mrr_fraction_numerator"], body["mrr_fraction_denominator"]
        )
        >= BODY_MRR_GATE,
        "body_relevant_at_20": body["relevant_at_20"] == 120,
        "body_required_evidence_at_20": (
            body["required_evidence_matched_at_20"]
            == body["required_evidence_total"]
            == 120
        ),
        "relationship_relevant_at_20": relationship["relevant_at_20"] == 30,
        "relationship_required_evidence_at_20": (
            relationship["required_evidence_matched_at_20"]
            == relationship["required_evidence_total"]
            == 30
        ),
        "header_mrr_at_20": header["mrr_at_20"] == "1.000000",
        "header_relevant_at_20": header["relevant_at_20"] == 30,
        "header_required_evidence_at_20": (
            header["required_evidence_matched_at_20"]
            == header["required_evidence_total"]
            == 30
        ),
        "authoritative_expansion": (
            expansion_matched == expansion_total == 180
        ),
    }
    failed = [name for name, passed in checks.items() if not passed]
    return {
        "status": "qualified" if not failed else "not_met",
        "checks": checks,
        "failed_checks": failed,
    }


def candidate_sort_key(
    name: str, variants: Mapping[str, Mapping[str, Any]]
) -> tuple[Fraction, int, int]:
    body = variants[name]["metrics"]["body"]
    return (
        Fraction(body["mrr_fraction_numerator"], body["mrr_fraction_denominator"]),
        body["relevant_at_5"],
        -VARIANT_ORDER.index(name),
    )


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
    passage_candidates = tuple(passage_record(item, raw) for item in candidates)
    passage_by_chunk = {item.chunk_id: item for item in passage_candidates}
    base.require(
        set(canonical_by_chunk) == set(passage_by_chunk),
        "passage_candidate_inventory_invalid",
    )

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
        client = EndpointClient(
            arguments.embedding_url, arguments.tokenizer_url, secret
        )
        runtime_identity = client.model_identity()
        current_vectors_raw, current_tokens = v3.embed_inputs(
            client,
            [DOCUMENT_PREFIX + item.retrieval_text for item in candidates],
        )
        passage_vectors_raw, passage_tokens = v3.embed_inputs(
            client,
            [DOCUMENT_PREFIX + item.retrieval_text for item in passage_candidates],
        )
        query_vectors, query_tokens = v3.embed_inputs(
            client, [base.QUERY_PREFIX + item.question for item in cases]
        )
    finally:
        if "client" in locals():
            client.close()
        wipe(secret)
    embedding_ms = (time.perf_counter_ns() - embedding_started) / 1_000_000
    current_vectors = {
        item.chunk_id: vector
        for item, vector in zip(candidates, current_vectors_raw, strict=True)
    }
    passage_vectors = {
        item.chunk_id: vector
        for item, vector in zip(passage_candidates, passage_vectors_raw, strict=True)
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
        raise base.MeasurementError(
            "temporary_postgresql_connection_failed"
        ) from error

    selection: dict[str, list[dict[str, Any]]] = {
        name: [] for name in VARIANT_ORDER
    }
    expansion: dict[str, list[dict[str, Any]]] = {
        name: [] for name in VARIANT_ORDER
    }
    atomic_ids = {item.chunk_id for item in atomic}
    retrieval_started = time.perf_counter_ns()
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
        for case, query_vector in zip(cases, query_vectors, strict=True):
            permitted_atomic = base.permitted_candidates(case, atomic)
            exact = v3.enrich_lane(
                base.exact_lane(case, permitted_atomic, LaneCandidate), raw
            )
            use_representations = not exact
            current_searchable = searchable_candidates(
                case,
                permitted_atomic,
                representatives,
                raw,
                canonical_by_chunk,
                use_representations=use_representations,
            )
            passage_searchable = searchable_candidates(
                case,
                permitted_atomic,
                representatives,
                raw,
                passage_by_chunk,
                use_representations=use_representations,
            )
            current_lexical = v3.enrich_lane(
                base.lexical_lane(
                    connection,
                    case.question,
                    current_searchable,
                    canonical_by_chunk,
                    LaneCandidate,
                ),
                raw,
            )
            current_vector = v3.enrich_lane(
                base.vector_lane(
                    query_vector,
                    current_searchable,
                    current_vectors,
                    LaneCandidate,
                ),
                raw,
            )
            passage_lexical = v3.enrich_lane(
                base.lexical_lane(
                    connection,
                    case.question,
                    passage_searchable,
                    canonical_by_chunk,
                    LaneCandidate,
                ),
                raw,
            )
            passage_vector = v3.enrich_lane(
                base.vector_lane(
                    query_vector,
                    passage_searchable,
                    passage_vectors,
                    LaneCandidate,
                ),
                raw,
            )
            lanes: dict[str, tuple[tuple[Any, ...], tuple[Any, ...], tuple[str, ...]]] = {
                "current_identity_both": (
                    current_lexical,
                    current_vector,
                    (),
                ),
                "identity_lexical_passage_vector": (
                    current_lexical,
                    passage_vector,
                    (),
                ),
                "passage_only": (passage_lexical, passage_vector, ()),
            }
            for depth, name in ((3, "two_stage_top3"), (5, "two_stage_top5")):
                shortlist = document_shortlist(
                    exact, current_lexical, current_vector, depth
                )
                restricted = searchable_candidates(
                    case,
                    permitted_atomic,
                    representatives,
                    raw,
                    passage_by_chunk,
                    use_representations=use_representations,
                    allowed_refs=set(shortlist),
                )
                lexical = v3.enrich_lane(
                    base.lexical_lane(
                        connection,
                        case.question,
                        restricted,
                        canonical_by_chunk,
                        LaneCandidate,
                    ),
                    raw,
                )
                vector = v3.enrich_lane(
                    base.vector_lane(
                        query_vector,
                        restricted,
                        passage_vectors,
                        LaneCandidate,
                    ),
                    raw,
                )
                lanes[name] = (lexical, vector, shortlist)

            for name in VARIANT_ORDER:
                lexical, vector, shortlist = lanes[name]
                selected = select_results(
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
                    case,
                    exact,
                    lexical,
                    vector,
                    selected,
                    permitted_atomic,
                    canonical_by_chunk,
                )
                measured["used_section_page_representatives"] = use_representations
                measured["searchable_candidate_count"] = (
                    len(current_searchable)
                    if name.startswith("current_")
                    else len(passage_searchable)
                    if not shortlist
                    else sum(
                        item.document_ref in set(shortlist)
                        for item in passage_searchable
                    )
                )
                measured["document_shortlist"] = list(shortlist)
                selection[name].append(measured)
                matched = sum(
                    any(
                        base.matches(
                            canonical_by_chunk[item.chunk_id], evidence
                        )
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
        connection.rollback()
    finally:
        connection.close()
    retrieval_ms = (time.perf_counter_ns() - retrieval_started) / 1_000_000

    variants: dict[str, dict[str, Any]] = {}
    for name in VARIANT_ORDER:
        metrics = {
            family: v3.family_metrics(selection[name], family)
            for family in ("body", "relationship", "header")
        }
        metrics["overall"] = base.aggregate(selection[name])
        expansion_matched = sum(
            item["matched_evidence_count"] for item in expansion[name]
        )
        expansion_total = sum(
            item["required_evidence_count"] for item in expansion[name]
        )
        variants[name] = {
            "metrics": metrics,
            "authoritative_expansion": {
                "matched_evidence": expansion_matched,
                "required_evidence": expansion_total,
                "complete": expansion_matched == expansion_total,
            },
            "gate": gate_for(metrics, expansion_matched, expansion_total),
            "results": {
                "selection": selection[name],
                "expanded_atomic_diagnostic": expansion[name],
            },
        }

    qualified = [
        name
        for name in VARIANT_ORDER
        if variants[name]["gate"]["status"] == "qualified"
    ]
    selected_candidate = (
        max(qualified, key=lambda name: candidate_sort_key(name, variants))
        if qualified
        else None
    )
    artifact: dict[str, Any] = {
        "artifact_kind": "ishikawa_v13_40_bounded_ranking_experiment",
        "schema_version": 1,
        "corpus_identity": "synthetic-corpus-v3",
        "measurement_class": "evaluation_only_no_promotion",
        "source_sha256": {
            "chunks": arguments.expected_chunks_sha256,
            "retrieval_truth": arguments.expected_truth_sha256,
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
            "document_affinity": "best_rank_per_lane",
            "document_shortlist_depths": [3, 5],
            "selection_order": [
                "body_mrr_at_20_desc",
                "body_relevant_at_5_desc",
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
        "token_usage": {
            "current_document_embedding_tokens": current_tokens,
            "passage_document_embedding_tokens": passage_tokens,
            "query_embedding_tokens": query_tokens,
        },
        "latency_ms": {
            "embeddings": format(embedding_ms, ".3f"),
            "retrieval_and_measurement": format(retrieval_ms, ".3f"),
        },
        "variants": variants,
        "qualified_candidates": qualified,
        "selected_candidate": selected_candidate,
        "selection_status": "qualified" if selected_candidate else "not_met",
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
        if key not in {"latency_ms", "variants"}
    }
    artifact["experiment_id"] = base.domain_digest(
        "ishikawa.v13-40-bounded-ranking-experiment.v1", identity_source
    )
    base.write_exclusive(arguments.output, base.canonical_json_bytes(artifact) + b"\n")

    print("purpose=measure_v13_40_bounded_ranking_candidates")
    for name in VARIANT_ORDER:
        body = variants[name]["metrics"]["body"]
        gate = variants[name]["gate"]
        print(
            f"variant={name};body_mrr_at_20={body['mrr_at_20']};"
            f"body_relevant_at_5={body['relevant_at_5']}/120;"
            f"body_relevant_at_20={body['relevant_at_20']}/120;"
            f"gate={gate['status']};"
            f"failed_checks={','.join(gate['failed_checks']) if gate['failed_checks'] else 'none'}"
        )
    print(
        f"selection_status={artifact['selection_status']};"
        f"selected_candidate={selected_candidate or 'none'};"
        "promotion_authorized=false"
    )
    print("v13_40_bounded_ranking_measurement=pass")


def self_test() -> None:
    candidate = base.CandidateRecord(
        "chunk", "doc", "version", "SYN-V3-001", 1, "narrative",
        "Document: Acceptable Use\nDocument identifier: 99 TST 2001\n"
        "Section: I. Purpose\n\nOperators must comply.",
        1, 1, "99 TST 2001", "Acceptable Use", "IT", "it", ("IT",),
    )
    raw = {
        "chunk": {
            "projection_properties": {
                "retrieval_document_identity_context": {
                    "included_in_retrieval_text": True,
                    "document_context": "Acceptable Use",
                    "policy_number": "99 TST 2001",
                }
            }
        }
    }
    stripped = passage_record(candidate, raw)
    assert stripped.retrieval_text == "Section: I. Purpose\n\nOperators must comply."

    class Lane:
        def __init__(self, key: str, rank: int):
            self.document_key = key
            self.rank = rank

    shortlist = document_shortlist(
        (), (Lane("doc-a", 1), Lane("doc-a", 2), Lane("doc-b", 3)),
        (Lane("doc-b", 1), Lane("doc-c", 2)), 3,
    )
    assert shortlist == ("doc-b", "doc-c", "doc-a")
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
    assert gate_for(metrics, 180, 180)["status"] == "qualified"
    metrics["body"]["relevant_at_20"] = 119
    assert gate_for(metrics, 180, 180)["status"] == "not_met"
    print("v13_40_bounded_ranking_measurement_self_test=pass")


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
        print(f"v13_40_bounded_ranking_measurement=blocked;reason={error}")
        raise SystemExit(1) from error
