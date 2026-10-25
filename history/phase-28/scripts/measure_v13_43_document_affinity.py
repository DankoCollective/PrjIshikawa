#!/usr/bin/env python3
"""Measure the frozen V13-43 document-affinity supplemental signal."""

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
import measure_v13_41_supplemental_ranking as v41


VARIANT_CONFIGS = (
    ("doc_l1_v0", 1, 0),
    ("doc_l0_v1", 0, 1),
    ("doc_l1_v1", 1, 1),
    ("doc_l1_v2", 1, 2),
    ("doc_l2_v1", 2, 1),
)
VARIANT_ORDER = tuple(item[0] for item in VARIANT_CONFIGS)
CONFIG_BY_NAME = {
    name: {"document_lexical_weight": lexical, "document_vector_weight": vector}
    for name, lexical, vector in VARIANT_CONFIGS
}


def scope_inventory(
    source: Mapping[str, Any], expected_profile_id: str
) -> tuple[tuple[base.CandidateRecord, ...], dict[str, base.CandidateRecord]]:
    documents = source.get("documents")
    base.require(
        source.get("artifact_kind")
        == "non_publishable_document_scope_affinity_representations"
        and source.get("profile_id") == expected_profile_id
        and source.get("profile", {}).get("name")
        == "ishikawa-document-scope-affinity-v1-experiment"
        and source.get("publication_eligible") is False
        and isinstance(documents, list)
        and len(documents) == 30,
        "document_scope_affinity_source_invalid",
    )
    records: list[base.CandidateRecord] = []
    for ordinal, document in enumerate(documents):
        record = document.get("representation")
        base.require(
            isinstance(record, dict)
            and record.get("projection_kind") == "document_scope_affinity"
            and record.get("profile_id") == expected_profile_id
            and record.get("document_id") == document.get("document_id")
            and record.get("document_version_id") == document.get("document_version_id")
            and isinstance(record.get("representation_id"), str)
            and isinstance(record.get("retrieval_text"), str)
            and record["retrieval_text"]
            and isinstance(record.get("retrieval_filters"), dict)
            and isinstance(record.get("contextual_fields"), dict),
            "document_scope_affinity_record_invalid",
        )
        context = record["contextual_fields"].get(
            "retrieval_document_scope_context"
        )
        control = record["retrieval_filters"].get("document_control")
        base.require(
            isinstance(context, dict)
            and isinstance(control, dict)
            and context.get("displayable") is False
            and context.get("citable") is False
            and record["contextual_fields"].get("displayable") is False
            and record["contextual_fields"].get("citable") is False
            and record["contextual_fields"].get("generation_eligible") is False
            and record["contextual_fields"].get("authoritative_evidence") is False
            and context.get("document_context") == control.get("document_context")
            and context.get("policy_number") == control.get("policy_number")
            and context.get("department") == control.get("department")
            and context.get("applicability_class") == control.get("applicability_class")
            and isinstance(context.get("purpose_scope_source_unit_ids"), list)
            and context["purpose_scope_source_unit_ids"],
            "document_scope_affinity_boundary_invalid",
        )
        records.append(base.CandidateRecord(
            record["representation_id"],
            document["document_id"],
            document["document_version_id"],
            document["document_ref"],
            ordinal,
            "document_scope_affinity",
            record["retrieval_text"],
            1,
            1,
            control["policy_number"],
            control["document_context"],
            control["department"],
            control["department_normalized"],
            tuple(control["department_aliases"]),
        ))
    base.require(
        len({item.chunk_id for item in records}) == 30
        and len({item.document_ref for item in records}) == 30,
        "document_scope_affinity_inventory_invalid",
    )
    result = tuple(records)
    return result, {item.chunk_id: item for item in result}


def document_affinity_fusion(
    exact: Sequence[Any],
    lexical: Sequence[Any],
    vector: Sequence[Any],
    document_lexical: Sequence[Any],
    document_vector: Sequence[Any],
    document_lexical_weight: int,
    document_vector_weight: int,
    fused_candidate_type: Any,
    *,
    rrf_constant: int = 60,
) -> tuple[Any, ...]:
    base.require(
        (document_lexical_weight, document_vector_weight)
        in {(1, 0), (0, 1), (1, 1), (1, 2), (2, 1)},
        "document_affinity_weights_invalid",
    )
    accumulated: dict[str, dict[str, Any]] = {}
    for lane_name, weight, lane in (
        ("exact", 1, exact),
        ("lexical", 2, lexical),
        ("vector", 4, vector),
    ):
        seen: set[str] = set()
        for candidate in lane:
            base.require(candidate.chunk_id not in seen, "passage_lane_duplicate")
            seen.add(candidate.chunk_id)
            state = accumulated.setdefault(candidate.chunk_id, {
                "document_id": candidate.document_id,
                "document_version_id": candidate.document_version_id,
                "document_key": candidate.document_key,
                "score": Fraction(0, 1),
                "passage_score": Fraction(0, 1),
                "best_rank": candidate.rank,
                "exact_priority": False,
                "retrieval_group_id": candidate.retrieval_group_id,
                "authoritative_chunk_ids": candidate.authoritative_chunk_ids,
                "retrieval_scoring_only": candidate.retrieval_scoring_only,
            })
            base.require(
                (state["document_id"], state["document_version_id"], state["document_key"])
                == (candidate.document_id, candidate.document_version_id, candidate.document_key),
                "passage_candidate_conflict",
            )
            contribution = Fraction(weight, rrf_constant + candidate.rank)
            state["score"] += contribution
            state["passage_score"] += contribution
            state["best_rank"] = min(state["best_rank"], candidate.rank)
            state["exact_priority"] = state["exact_priority"] or lane_name == "exact"

    affinity_ranks: dict[str, dict[str, int]] = {}
    for lane_name, lane in (
        ("document_lexical", document_lexical),
        ("document_vector", document_vector),
    ):
        seen_documents: set[str] = set()
        for candidate in lane:
            base.require(
                candidate.document_key not in seen_documents,
                "document_affinity_lane_duplicate",
            )
            seen_documents.add(candidate.document_key)
            affinity_ranks.setdefault(candidate.document_key, {})[lane_name] = candidate.rank
    for state in accumulated.values():
        ranks = affinity_ranks.get(state["document_key"], {})
        if document_lexical_weight and "document_lexical" in ranks:
            state["score"] += Fraction(
                document_lexical_weight,
                rrf_constant + ranks["document_lexical"],
            )
        if document_vector_weight and "document_vector" in ranks:
            state["score"] += Fraction(
                document_vector_weight,
                rrf_constant + ranks["document_vector"],
            )
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
                -item[1]["passage_score"],
                item[1]["best_rank"],
                item[0],
            ),
        )
    )
    base.require(fused, "document_affinity_fusion_empty")
    return fused


def _document_lane_records(
    lane: Sequence[Any], by_chunk: Mapping[str, base.CandidateRecord]
) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for expected_rank, item in enumerate(lane, 1):
        metadata = by_chunk.get(item.chunk_id)
        base.require(
            metadata is not None
            and metadata.document_ref == item.document_key
            and item.rank == expected_rank,
            "document_affinity_lane_contract_invalid",
        )
        records.append({
            "document_ref": item.document_key,
            "rank": item.rank,
            "score": item.raw_score,
            "variant": item.retrieval_variant or item.lane,
        })
    return records


def evaluate(
    connection: Any,
    cases: Sequence[base.Case],
    query_vectors: Sequence[Sequence[float]],
    passage_vectors: Mapping[str, Sequence[float]],
    scope_vectors: Mapping[str, Sequence[float]],
    atomic: Sequence[base.CandidateRecord],
    representatives: Sequence[base.CandidateRecord],
    raw: Mapping[str, Mapping[str, Any]],
    canonical: Mapping[str, base.CandidateRecord],
    scope_records: Sequence[base.CandidateRecord],
    scope_by_chunk: Mapping[str, base.CandidateRecord],
    profile: Any,
    lane_candidate_type: Any,
    fused_candidate_type: Any,
    collapse_retrieval_groups: Any,
    expand_authoritative_candidates: Any,
    reciprocal_rank_fusion: Any,
) -> dict[str, Any]:
    names = ("accepted_v6", *VARIANT_ORDER)
    selections: dict[str, list[dict[str, Any]]] = {name: [] for name in names}
    expansions: dict[str, list[dict[str, Any]]] = {name: [] for name in names}
    atomic_ids = {item.chunk_id for item in atomic}
    for case, query_vector in zip(cases, query_vectors, strict=True):
        permitted = base.permitted_candidates(case, atomic)
        permitted_refs = {item.document_ref for item in permitted}
        exact = v3.enrich_lane(
            base.exact_lane(case, permitted, lane_candidate_type), raw
        )
        use_representations = not exact
        searchable = v40.searchable_candidates(
            case, permitted, representatives, raw, canonical,
            use_representations=use_representations,
        )
        lexical = v3.enrich_lane(
            base.lexical_lane(connection, case.question, searchable, canonical, lane_candidate_type),
            raw,
        )
        vector = v3.enrich_lane(
            base.vector_lane(query_vector, searchable, passage_vectors, lane_candidate_type),
            raw,
        )
        permitted_scope = tuple(
            item for item in scope_records if item.document_ref in permitted_refs
        )
        document_lexical = base.lexical_lane(
            connection, case.question, permitted_scope, scope_by_chunk, lane_candidate_type
        )
        document_vector = base.vector_lane(
            query_vector, permitted_scope, scope_vectors, lane_candidate_type
        )
        for name in names:
            if name == "accepted_v6":
                selected = v40.select_results(
                    exact, lexical, vector,
                    use_representations=use_representations,
                    profile=profile,
                    collapse_retrieval_groups=collapse_retrieval_groups,
                    reciprocal_rank_fusion=reciprocal_rank_fusion,
                )
                weights = {"document_lexical": 0, "document_vector": 0}
            else:
                config = CONFIG_BY_NAME[name]
                fused = document_affinity_fusion(
                    exact, lexical, vector, document_lexical, document_vector,
                    config["document_lexical_weight"],
                    config["document_vector_weight"],
                    fused_candidate_type,
                    rrf_constant=60,
                )
                if use_representations:
                    fused = collapse_retrieval_groups(fused)
                selected = tuple(fused[:20])
                weights = {
                    "document_lexical": config["document_lexical_weight"],
                    "document_vector": config["document_vector_weight"],
                }
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
            measured["document_affinity_weights"] = weights
            measured["document_affinity_lanes"] = {
                "lexical": _document_lane_records(document_lexical, scope_by_chunk),
                "vector": _document_lane_records(document_vector, scope_by_chunk),
            }
            measured["searchable_candidate_count"] = len(searchable)
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
    return {
        name: v41.summarize_variant(selections[name], expansions[name])
        for name in names
    }


def selection_key(name: str, result: Mapping[str, Any]) -> tuple[Fraction, int, int]:
    body = result["metrics"]["body"]
    return (
        Fraction(body["mrr_fraction_numerator"], body["mrr_fraction_denominator"]),
        body["relevant_at_5"],
        -VARIANT_ORDER.index(name),
    )


def execute(arguments: argparse.Namespace) -> None:
    python_root = arguments.python_root.resolve(strict=True)
    sys.path.insert(0, str(python_root))
    from embed_document_candidates_via_endpoint import DOCUMENT_PREFIX, EndpointClient, wipe
    from ishikawa.method_profile import ACCEPTED_RETRIEVAL_PROFILE
    from ishikawa.retrieval import (
        FusedCandidate, LaneCandidate, collapse_retrieval_groups,
        expand_authoritative_candidates, reciprocal_rank_fusion,
    )

    chunks = base.load_bound_json(
        arguments.chunks, arguments.expected_chunks_sha256, 32 * 1024 * 1024
    )
    scopes = base.load_bound_json(
        arguments.document_scopes,
        arguments.expected_document_scopes_sha256,
        2 * 1024 * 1024,
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
    scope_records, scope_by_chunk = scope_inventory(scopes, arguments.scope_profile_id)
    profile = ACCEPTED_RETRIEVAL_PROFILE
    base.require(
        profile.exact_weight == 1 and profile.lexical_weight == 2
        and profile.vector_weight == 4 and profile.exact_candidate_depth == 1
        and profile.lexical_candidate_depth == 20 and profile.vector_candidate_depth == 20
        and profile.fused_candidate_depth == 20 and profile.rrf_constant == 60
        and profile.section_page_representatives is True
        and profile.document_local_duplicate_canonicalization is True,
        "accepted_retrieval_profile_changed",
    )

    secret_text = os.environ.pop("ISHIKAWA_NOMIC_API_KEY", "")
    base.require(32 <= len(secret_text) <= 1024 and "\n" not in secret_text
                 and "\r" not in secret_text, "nomic_credential_invalid")
    secret = bytearray(secret_text.encode("utf-8"))
    secret_text = ""
    embedding_started = time.perf_counter_ns()
    try:
        client = EndpointClient(arguments.embedding_url, arguments.tokenizer_url, secret)
        runtime_identity = client.model_identity()
        passage_raw, passage_tokens = v3.embed_inputs(
            client, [DOCUMENT_PREFIX + item.retrieval_text for item in candidates]
        )
        scope_raw, scope_tokens = v3.embed_inputs(
            client, [DOCUMENT_PREFIX + item.retrieval_text for item in scope_records]
        )
        query_vectors, query_tokens = v3.embed_inputs(
            client, [base.QUERY_PREFIX + item.question for item in cases]
        )
    finally:
        if "client" in locals(): client.close()
        wipe(secret)
    embedding_ms = (time.perf_counter_ns() - embedding_started) / 1_000_000
    passage_vectors = {
        item.chunk_id: vector for item, vector in zip(candidates, passage_raw, strict=True)
    }
    scope_vectors = {
        item.chunk_id: vector for item, vector in zip(scope_records, scope_raw, strict=True)
    }

    try:
        import psycopg
        connection = psycopg.connect(
            host=str(arguments.postgresql_socket), port=arguments.postgresql_port,
            dbname="postgres", user=arguments.postgresql_user, connect_timeout=5,
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
        variants = evaluate(
            connection, cases, query_vectors, passage_vectors, scope_vectors,
            atomic, representatives, raw, canonical, scope_records, scope_by_chunk,
            profile, LaneCandidate, FusedCandidate, collapse_retrieval_groups,
            expand_authoritative_candidates, reciprocal_rank_fusion,
        )
        connection.rollback()
    finally:
        connection.close()
    retrieval_ms = (time.perf_counter_ns() - retrieval_started) / 1_000_000

    qualified = [
        name for name in VARIANT_ORDER
        if variants[name]["gate"]["status"] == "qualified"
    ]
    selected = max(qualified, key=lambda name: selection_key(name, variants[name])) \
        if qualified else None
    artifact: dict[str, Any] = {
        "artifact_kind": "ishikawa_v13_43_document_affinity_experiment",
        "schema_version": 1,
        "corpus_identity": "synthetic-corpus-v3",
        "measurement_class": "evaluation_only_no_promotion",
        "source_sha256": {
            "chunks": arguments.expected_chunks_sha256,
            "document_scopes": arguments.expected_document_scopes_sha256,
            "retrieval_truth": arguments.expected_truth_sha256,
        },
        "profiles": {
            "chunk_profile_id": arguments.chunk_profile_id,
            "scope_profile_id": arguments.scope_profile_id,
            "retrieval_profile_id": profile.digest,
        },
        "experiment": {
            "variant_order": list(VARIANT_ORDER),
            "variant_configs": CONFIG_BY_NAME,
            "body_mrr_gate": "0.89",
            "passage_weights": {"exact": 1, "lexical": 2, "vector": 4},
            "rrf_constant": 60,
            "selection_order": [
                "body_mrr_at_20_desc", "body_relevant_at_5_desc", "declared_variant_order",
            ],
        },
        "candidate_inventory": {
            "documents": 30, "atomic": len(atomic),
            "representatives": len(representatives), "passage_total": len(candidates),
            "document_scope_affinity": len(scope_records),
        },
        "case_inventory": {"body": 120, "relationship": 30, "header": 30, "total": 180},
        "runtime_identity_digest": runtime_identity,
        "token_usage": {
            "passage_embedding_tokens": passage_tokens,
            "document_scope_embedding_tokens": scope_tokens,
            "query_embedding_tokens": query_tokens,
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
            "accepted_database_contact": False, "accepted_database_write": False,
            "black_corpus_access": False, "corpus_ingestion": False,
            "corpus_v3_changed": False, "gemma_contact": False, "nomic_contact": True,
            "private_temporary_postgresql": True, "production_profile_changed": False,
            "retained_runtime_flat_file_index": False, "question_text_retained": False,
            "query_vectors_retained": False, "source_text_retained": False,
            "document_scope_citable": False, "document_scope_displayable": False,
            "document_scope_generation_eligible": False,
        },
        "promotion_authorized": False,
        "next_gate": "review_and_separately_freeze_any_selected_candidate",
    }
    identity = {key: value for key, value in artifact.items()
                if key not in {"latency_ms", "variants"}}
    artifact["experiment_id"] = base.domain_digest(
        "ishikawa.v13-43-document-affinity-experiment.v1", identity
    )
    base.write_exclusive(arguments.output, base.canonical_json_bytes(artifact) + b"\n")
    print("purpose=measure_v13_43_document_affinity")
    for name in ("accepted_v6", *VARIANT_ORDER):
        body = variants[name]["metrics"]["body"]
        print(f"variant={name};body_mrr_at_20={body['mrr_at_20']};"
              f"body_relevant_at_5={body['relevant_at_5']}/120;"
              f"body_relevant_at_20={body['relevant_at_20']}/120;"
              f"gate={variants[name]['gate']['status']}")
    print(f"selection_status={artifact['selection_status']};"
          f"selected_candidate={selected or 'none'};promotion_authorized=false")
    print("v13_43_document_affinity_measurement=pass")


def self_test() -> None:
    class Candidate:
        def __init__(self, chunk: str, document: str, rank: int):
            self.chunk_id = chunk; self.document_id = document
            self.document_version_id = document + "-v"; self.document_key = document
            self.rank = rank; self.retrieval_group_id = chunk
            self.authoritative_chunk_ids = (chunk,); self.retrieval_scoring_only = False
            self.raw_score = 1.0 / rank; self.retrieval_variant = "strict"
            self.lane = "lexical"
    class Scope:
        def __init__(self, document: str): self.document_ref = document
    class Fused:
        def __init__(self, **values): self.__dict__.update(values)
    lexical = (
        Candidate("a1", "doc-a", 1), Candidate("b", "doc-b", 2),
        Candidate("a2", "doc-a", 3),
    )
    vector = (
        Candidate("b", "doc-b", 1), Candidate("a1", "doc-a", 2),
        Candidate("a2", "doc-a", 3),
    )
    document_lexical = (Candidate("da", "doc-a", 1), Candidate("db", "doc-b", 2))
    document_vector = (Candidate("db", "doc-b", 1), Candidate("da", "doc-a", 2))
    fused = document_affinity_fusion(
        (), lexical, vector, document_lexical, document_vector, 1, 0, Fused
    )
    order = [item.chunk_id for item in fused]
    assert set(order) == {"a1", "a2", "b"}
    assert order.index("a1") < order.index("a2")
    assert CONFIG_BY_NAME["doc_l1_v2"] == {
        "document_lexical_weight": 1, "document_vector_weight": 2
    }
    assert _document_lane_records(
        document_lexical,
        {"da": Scope("doc-a"), "db": Scope("doc-b")},
    ) == [
        {"document_ref": "doc-a", "rank": 1, "score": 1.0, "variant": "strict"},
        {"document_ref": "doc-b", "rank": 2, "score": 0.5, "variant": "strict"},
    ]
    print("v13_43_document_affinity_measurement_self_test=pass")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--python-root", type=Path)
    parser.add_argument("--chunks", type=Path)
    parser.add_argument("--expected-chunks-sha256")
    parser.add_argument("--document-scopes", type=Path)
    parser.add_argument("--expected-document-scopes-sha256")
    parser.add_argument("--chunk-profile-id")
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
        self_test(); return 0
    required = (
        arguments.python_root, arguments.chunks, arguments.document_scopes,
        arguments.chunk_profile_id, arguments.scope_profile_id, arguments.truth,
        arguments.embedding_url, arguments.tokenizer_url, arguments.postgresql_socket,
        arguments.postgresql_port, arguments.postgresql_user, arguments.output,
    )
    if any(value is None for value in required):
        parser.error("measurement arguments are required without --self-test")
    try:
        execute(arguments)
    except (base.MeasurementError, OSError, ValueError, KeyError) as error:
        print(f"v13_43_document_affinity_measurement=blocked;reason={error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
