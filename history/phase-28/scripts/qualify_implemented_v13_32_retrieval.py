#!/usr/bin/env python3
"""Qualify V13-32 retrieval directly from the implemented application source."""

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

import measure_published_v2_section_page_experiment as experiment
import measure_synthetic_corpus_v2_candidate_profile as candidate_measurement
import measure_synthetic_corpus_v2_without_ingestion as base


EXPECTED_CANDIDATE_ID = (
    "bf732e402004d70b0aa3318e179fe1a1e14d0bd4a70aaa2b4d71528088b7d518"
)
EXPECTED_CHUNK_METHOD_ID = (
    "0c16e785006d8f68cf942bf9f76a84d0d837b84be629fe898898d319f45d34a1"
)
EXPECTED_RETRIEVAL_PROFILE_ID = (
    "96915e0cbb0547bebf3af54b21d92a3ec923bba6e058ad2460ced05336d41a1d"
)
EXPECTED_CHUNK_SET_DIGEST = (
    "64672ba2d446a60a8ba299d356eb2bc0d758cd07ce47f6d117979e6c2d759baa"
)
EXPECTED_RUNTIME_IDENTITY = (
    "220da5d172594311924d3400ac60049fc92d18d5c8117ff35b5edf5d2337b0db"
)
EXPECTED_PROFILE = {
    "rrf_constant": 60,
    "exact_weight": 1,
    "lexical_weight": 2,
    "vector_weight": 4,
    "lexical_depth": 20,
    "vector_depth": 20,
}


def elapsed_ms(started_ns: int) -> float:
    return (time.perf_counter_ns() - started_ns) / 1_000_000


def gate_met(body: Mapping[str, Any], header: Mapping[str, Any]) -> bool:
    body_mrr = Fraction(
        body["mrr_fraction_numerator"], body["mrr_fraction_denominator"]
    )
    return (
        body_mrr >= Fraction(89, 100)
        and body["relevant_at_5"] == 60
        and body["relevant_at_20"] == 60
        and body["required_evidence_matched_at_20"] == 60
        and body["required_evidence_total"] == 60
        and header["mrr_at_20"] == "1.000000"
        and header["relevant_at_5"] == 8
        and header["relevant_at_20"] == 8
        and header["required_evidence_matched_at_20"] == 11
        and header["required_evidence_total"] == 11
    )


def representation_inventory(
    source: Mapping[str, Any],
) -> tuple[
    tuple[base.CandidateRecord, ...],
    tuple[base.CandidateRecord, ...],
    dict[str, Mapping[str, Any]],
]:
    records = experiment.remapped_candidates(source, 168)
    raw = {
        candidate["chunk_id"]: candidate
        for document in source["documents"]
        for candidate in document["candidates"]
    }
    base.require(len(raw) == 168, "implemented_candidate_identity_collision")
    atomic = tuple(
        item for item in records if item.projection_kind != "section_page_representative"
    )
    representatives = tuple(
        item for item in records if item.projection_kind == "section_page_representative"
    )
    base.require(
        len(atomic) == 139 and len(representatives) == 29,
        "implemented_candidate_inventory_invalid",
    )
    atomic_ids = {item.chunk_id for item in atomic}
    atomic_by_id = {item.chunk_id: item for item in atomic}
    canonical = 0
    component_memberships = 0
    group_owners: dict[str, tuple[str, str]] = {}
    for item in records:
        candidate = raw[item.chunk_id]
        properties = candidate.get("projection_properties")
        base.require(isinstance(properties, dict), "representation_metadata_invalid")
        group_id = properties.get("retrieval_group_id")
        base.require(
            isinstance(group_id, str)
            and len(group_id) == 64
            and all(character in "0123456789abcdef" for character in group_id),
            "retrieval_group_identity_invalid",
        )
        owner = (item.document_id, item.document_version_id)
        base.require(
            group_owners.setdefault(group_id, owner) == owner,
            "retrieval_group_crosses_document_identity",
        )
        scoring_only = properties.get("retrieval_scoring_only")
        is_canonical = properties.get("document_local_content_canonical")
        base.require(
            type(scoring_only) is bool and type(is_canonical) is bool,
            "representation_flags_invalid",
        )
        if item.projection_kind == "section_page_representative":
            components = properties.get("component_chunk_ids")
            base.require(
                scoring_only is True
                and properties.get("atomic_evidence_authoritative") is True
                and isinstance(components, list)
                and components
                and len(components) == len(set(components))
                and set(components) <= atomic_ids,
                "representative_component_contract_invalid",
            )
            base.require(
                all(
                    (
                        atomic_by_id[component].document_id,
                        atomic_by_id[component].document_version_id,
                    )
                    == owner
                    and raw[component]["projection_properties"][
                        "retrieval_group_id"
                    ]
                    == group_id
                    for component in components
                ),
                "representative_component_owner_invalid",
            )
            component_memberships += len(components)
        else:
            base.require(scoring_only is False, "atomic_candidate_marked_scoring_only")
            canonical += int(is_canonical)
    base.require(canonical == 118, "canonical_atomic_inventory_invalid")
    base.require(component_memberships == 123, "component_membership_inventory_invalid")
    return atomic, representatives, raw


def enrich_lane(
    candidates: Sequence[Any], raw: Mapping[str, Mapping[str, Any]]
) -> tuple[Any, ...]:
    enriched = []
    for candidate in candidates:
        properties = raw[candidate.chunk_id]["projection_properties"]
        scoring_only = properties["retrieval_scoring_only"]
        authoritative = (
            tuple(properties["component_chunk_ids"])
            if scoring_only
            else (candidate.chunk_id,)
        )
        enriched.append(
            replace(
                candidate,
                retrieval_group_id=properties["retrieval_group_id"],
                authoritative_chunk_ids=authoritative,
                retrieval_scoring_only=scoring_only,
                document_local_content_canonical=properties[
                    "document_local_content_canonical"
                ],
            )
        )
    return tuple(enriched)


def embed_inputs(client: Any, inputs: Sequence[str]) -> tuple[list[list[float]], int]:
    vectors: list[list[float]] = []
    tokens = 0
    for start in range(0, len(inputs), 16):
        batch, usage = client.embeddings(list(inputs[start : start + 16]))
        vectors.extend(batch)
        tokens += usage
    base.require(len(vectors) == len(inputs), "embedding_inventory_incomplete")
    return vectors, tokens


def execute(arguments: argparse.Namespace) -> int:
    python_root = arguments.python_root.resolve(strict=True)
    sys.path.insert(0, str(python_root))
    from embed_document_candidates_via_endpoint import (
        DOCUMENT_PREFIX,
        EndpointClient,
        wipe,
    )
    from ishikawa.chunking import build_chunk_candidates, chunk_candidates_json_bytes
    from ishikawa.method_profile import ACCEPTED_RETRIEVAL_PROFILE
    from ishikawa.retrieval import (
        LaneCandidate,
        collapse_retrieval_groups,
        expand_authoritative_candidates,
        reciprocal_rank_fusion,
    )

    normalized = base.load_bound_json(
        arguments.normalized, arguments.expected_normalized_sha256, 64 * 1024 * 1024
    )
    body_source = base.load_bound_json(
        arguments.body_cases, arguments.expected_body_cases_sha256, 2 * 1024 * 1024
    )
    header_source = base.load_bound_json(
        arguments.header_cases, arguments.expected_header_cases_sha256, 1024 * 1024
    )
    prior = base.load_bound_json(
        arguments.prior_qualification,
        arguments.expected_prior_qualification_sha256,
        8 * 1024 * 1024,
    )
    base.require(
        prior.get("artifact_kind")
        == "ishikawa_selected_v2_retrieval_finalist_live_qualification"
        and prior.get("qualification_gate_met") is True
        and prior.get("deterministic_across_measured_runs") is True
        and prior.get("candidate_profile") == EXPECTED_PROFILE
        and len(prior.get("runs", [])) == 5
        and all(
            run["candidate_metrics"]["body"]["mrr_at_20"] == "0.915833"
            for run in prior.get("runs", [])
        ),
        "prior_live_qualification_invalid",
    )

    first = build_chunk_candidates(normalized)
    second = build_chunk_candidates(normalized)
    base.require(
        chunk_candidates_json_bytes(first) == chunk_candidates_json_bytes(second),
        "implemented_candidate_construction_not_repeatable",
    )
    profile = ACCEPTED_RETRIEVAL_PROFILE
    base.require(
        first.get("method_profile_id") == EXPECTED_CHUNK_METHOD_ID
        and first.get("chunk_candidate_set_digest") == EXPECTED_CHUNK_SET_DIGEST
        and profile.digest == EXPECTED_RETRIEVAL_PROFILE_ID
        and {
            "rrf_constant": profile.rrf_constant,
            "exact_weight": profile.exact_weight,
            "lexical_weight": profile.lexical_weight,
            "vector_weight": profile.vector_weight,
            "lexical_depth": profile.lexical_candidate_depth,
            "vector_depth": profile.vector_candidate_depth,
        }
        == EXPECTED_PROFILE
        and profile.section_page_representatives is True
        and profile.document_local_duplicate_canonicalization is True
        and profile.representative_evidence == "expand_to_ordered_atomic_members",
        "implemented_profile_invalid",
    )
    atomic, representatives, raw = representation_inventory(first)
    candidates = atomic + representatives
    by_chunk = {item.chunk_id: item for item in candidates}
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
    embedding_started = time.perf_counter_ns()
    try:
        client = EndpointClient(arguments.embedding_url, arguments.tokenizer_url, secret)
        base.require(
            client.model_identity() == EXPECTED_RUNTIME_IDENTITY,
            "embedding_runtime_identity_changed",
        )
        candidate_vectors, candidate_tokens = embed_inputs(
            client, [DOCUMENT_PREFIX + item.retrieval_text for item in candidates]
        )
        query_vectors, query_tokens = embed_inputs(
            client, [base.QUERY_PREFIX + case.question for case in cases]
        )
    finally:
        if "client" in locals():
            client.close()
        wipe(secret)
    embedding_ms = elapsed_ms(embedding_started)
    base.require(query_tokens == 1204, "query_embedding_token_inventory_changed")
    vectors = {
        item.chunk_id: vector for item, vector in zip(candidates, candidate_vectors, strict=True)
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

    selection_results = []
    expanded_results = []
    atomic_ids = {item.chunk_id for item in atomic}
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
        for case, query_vector in zip(cases, query_vectors, strict=True):
            permitted_atomic = base.permitted_candidates(case, atomic)
            exact = enrich_lane(
                base.exact_lane(case, permitted_atomic, LaneCandidate), raw
            )
            use_representations = not exact
            permitted_refs = {item.document_ref for item in permitted_atomic}
            searchable_atomic = tuple(
                item
                for item in permitted_atomic
                if not use_representations
                or raw[item.chunk_id]["projection_properties"][
                    "document_local_content_canonical"
                ]
            )
            permitted_representatives = tuple(
                item for item in representatives if item.document_ref in permitted_refs
            )
            searchable = searchable_atomic + (
                permitted_representatives if use_representations else ()
            )
            lexical = enrich_lane(
                base.lexical_lane(
                    connection, case.question, searchable, by_chunk, LaneCandidate
                ),
                raw,
            )
            vector = enrich_lane(
                base.vector_lane(query_vector, searchable, vectors, LaneCandidate), raw
            )
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
            selected = fused[: profile.fused_candidate_depth]
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
            selection_results.append(
                base.measure_case(
                    case,
                    exact,
                    lexical,
                    vector,
                    selected,
                    permitted_atomic,
                    by_chunk,
                )
            )
            expanded_result = base.measure_case(
                case,
                exact,
                lexical,
                vector,
                expanded,
                permitted_atomic,
                by_chunk,
            )
            expanded_result.pop("lanes")
            expanded_result["authoritative_evidence_matched_count"] = sum(
                any(base.matches(by_chunk[item.chunk_id], expected) for item in expanded)
                for expected in case.required_evidence
            )
            expanded_result["authoritative_evidence_required_count"] = len(
                case.required_evidence
            )
            expanded_results.append(expanded_result)
        connection.rollback()
    finally:
        connection.close()
    retrieval_ms = elapsed_ms(retrieval_started)

    body = base.aggregate(selection_results[: base.BODY_CASE_COUNT])
    header = base.aggregate(selection_results[base.BODY_CASE_COUNT :])
    expanded_body = base.aggregate(expanded_results[: base.BODY_CASE_COUNT])
    expanded_header = base.aggregate(expanded_results[base.BODY_CASE_COUNT :])
    expanded_body_evidence = sum(
        item["authoritative_evidence_matched_count"]
        for item in expanded_results[: base.BODY_CASE_COUNT]
    )
    expanded_header_evidence = sum(
        item["authoritative_evidence_matched_count"]
        for item in expanded_results[base.BODY_CASE_COUNT :]
    )
    expansion_complete = expanded_body_evidence == 60 and expanded_header_evidence == 11
    passed = gate_met(body, header) and expansion_complete
    artifact: dict[str, Any] = {
        "artifact_kind": "ishikawa_implemented_v13_32_retrieval_qualification",
        "boundaries": {
            "accepted_database_contact": False,
            "accepted_database_write": False,
            "black_corpus_access": False,
            "corpus_changed": False,
            "gemma_contact": False,
            "nomic_contact": True,
            "private_temporary_postgresql": True,
            "profile_changed": False,
            "truth_changed": False,
        },
        "candidate_identity": EXPECTED_CANDIDATE_ID,
        "candidate_inventory": {
            "atomic": len(atomic),
            "canonical_atomic": sum(
                bool(raw[item.chunk_id]["projection_properties"]["document_local_content_canonical"])
                for item in atomic
            ),
            "representatives": len(representatives),
            "total": len(candidates),
        },
        "chunk_candidate_set_digest": first["chunk_candidate_set_digest"],
        "chunk_method_profile_id": first["method_profile_id"],
        "gate": {
            "ranking_boundary": "collapsed_structural_selection_before_atomic_evidence_expansion",
            "body_mrr_at_20_minimum": "0.890000",
            "body_relevant_at_5": "60/60",
            "body_required_evidence_at_20": "60/60",
            "header_mrr_at_20": "1.000000",
            "header_relevant_at_5": "8/8",
            "header_required_evidence_at_20": "11/11",
            "atomic_expansion_required_evidence": "71/71",
        },
        "latency_ms": {
            "fresh_candidate_and_query_embeddings": format(embedding_ms, ".3f"),
            "retrieval_and_measurement": format(retrieval_ms, ".3f"),
        },
        "metrics": {
            "body": body,
            "header": header,
            "expanded_atomic_diagnostic": {
                "body": expanded_body,
                "header": expanded_header,
                "authoritative_evidence": {
                    "body_matched": expanded_body_evidence,
                    "body_total": 60,
                    "header_matched": expanded_header_evidence,
                    "header_total": 11,
                },
            },
        },
        "next_gate": "complete_retrieval_api_and_gemma_evaluation",
        "qualification_gate_met": passed,
        "retrieval_profile": EXPECTED_PROFILE,
        "retrieval_profile_id": profile.digest,
        "schema_version": 2,
        "source_sha256": {
            "body_truth": arguments.expected_body_cases_sha256,
            "header_truth": arguments.expected_header_cases_sha256,
            "normalized": arguments.expected_normalized_sha256,
            "prior_qualification": arguments.expected_prior_qualification_sha256,
        },
        "token_usage": {
            "candidate_embedding_tokens": candidate_tokens,
            "query_embedding_tokens": query_tokens,
        },
        "results": {
            "selection": selection_results,
            "expanded_atomic_diagnostic": expanded_results,
        },
    }
    artifact["qualification_id"] = base.domain_digest(
        "ishikawa.implemented-v13-32-retrieval-qualification.v2",
        {
            key: value
            for key, value in artifact.items()
            if key not in {"latency_ms", "results"}
        },
    )
    payload = base.canonical_json_bytes(artifact) + b"\n"
    base.write_exclusive(arguments.output, payload)
    print("purpose=qualify_implemented_v13_32_retrieval")
    print(
        f"candidate_identity={EXPECTED_CANDIDATE_ID};"
        f"chunk_method_id={EXPECTED_CHUNK_METHOD_ID};"
        f"retrieval_profile_id={EXPECTED_RETRIEVAL_PROFILE_ID}"
    )
    print(
        f"body_mrr_at_20={body['mrr_at_20']};"
        f"body_top5={body['relevant_at_5']}/60;"
        f"body_required_evidence={body['required_evidence_matched_at_20']}/60"
    )
    print(
        f"header_mrr_at_20={header['mrr_at_20']};"
        f"header_top5={header['relevant_at_5']}/8;"
        f"header_required_evidence={header['required_evidence_matched_at_20']}/11"
    )
    print(
        f"expanded_atomic_diagnostic_mrr_at_20={expanded_body['mrr_at_20']};"
        f"expanded_atomic_top5={expanded_body['relevant_at_5']}/60;"
        "expanded_atomic_required_evidence="
        f"{expanded_body_evidence}/60;"
        "expanded_header_required_evidence="
        f"{expanded_header_evidence}/11"
    )
    print(
        f"candidate_embedding_tokens={candidate_tokens};"
        f"query_embedding_tokens={query_tokens};"
        f"artifact_sha256={hashlib.sha256(payload).hexdigest()}"
    )
    if not passed:
        print("implemented_v13_32_retrieval_qualification=blocked;reason=retrieval_gate_not_met")
        return 1
    print("implemented_v13_32_retrieval_qualification=pass")
    return 0


def self_test() -> int:
    body = {
        "mrr_fraction_numerator": 89,
        "mrr_fraction_denominator": 100,
        "relevant_at_5": 60,
        "relevant_at_20": 60,
        "required_evidence_matched_at_20": 60,
        "required_evidence_total": 60,
    }
    header = {
        "mrr_at_20": "1.000000",
        "relevant_at_5": 8,
        "relevant_at_20": 8,
        "required_evidence_matched_at_20": 11,
        "required_evidence_total": 11,
    }
    assert gate_met(body, header)
    assert not gate_met({**body, "relevant_at_5": 59}, header)
    assert EXPECTED_PROFILE["lexical_weight"] == 2
    print("implemented_v13_32_retrieval_qualification_self_test=pass")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--python-root", type=Path)
    parser.add_argument("--normalized", type=Path)
    parser.add_argument("--expected-normalized-sha256")
    parser.add_argument("--body-cases", type=Path)
    parser.add_argument("--expected-body-cases-sha256")
    parser.add_argument("--header-cases", type=Path)
    parser.add_argument("--expected-header-cases-sha256")
    parser.add_argument("--prior-qualification", type=Path)
    parser.add_argument("--expected-prior-qualification-sha256")
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
        arguments.normalized,
        arguments.expected_normalized_sha256,
        arguments.body_cases,
        arguments.expected_body_cases_sha256,
        arguments.header_cases,
        arguments.expected_header_cases_sha256,
        arguments.prior_qualification,
        arguments.expected_prior_qualification_sha256,
        arguments.postgresql_socket,
        arguments.postgresql_port,
        arguments.postgresql_user,
        arguments.output,
    )
    base.require(all(value is not None and value is not False for value in required), "mode_invalid")
    return execute(arguments)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except base.MeasurementError as error:
        print(f"implemented_v13_32_retrieval_qualification=blocked;reason={error}")
        raise SystemExit(1)
