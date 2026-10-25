#!/usr/bin/env python3
"""Measure the frozen retrieval implementation over synthetic corpus v3.

This is an observational pre-ingestion measurement.  It uses an isolated,
read-only PostgreSQL transaction only for native lexical ranking and calls the
existing loopback Nomic endpoint.  It does not publish a corpus or change a
retrieval profile.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
from dataclasses import replace
from pathlib import Path
from typing import Any, Mapping, Sequence

import measure_synthetic_corpus_v2_without_ingestion as base


EXPECTED_DOCUMENTS = 30
EXPECTED_ATOMIC = 786
EXPECTED_REPRESENTATIVES = 157
EXPECTED_CANDIDATES = 943
EXPECTED_BODY = 120
EXPECTED_RELATIONSHIP = 30
EXPECTED_HEADER = 30


def elapsed_ms(started_ns: int) -> float:
    return (time.perf_counter_ns() - started_ns) / 1_000_000


def load_cases(source: Mapping[str, Any]) -> tuple[base.Case, ...]:
    records = source.get("cases")
    counts = source.get("case_counts")
    base.require(
        source.get("artifact_kind")
        == "ishikawa_synthetic_corpus_v3_retrieval_truth"
        and source.get("schema_version") == 1
        and source.get("corpus_identity") == "synthetic-corpus-v3"
        and source.get("synthetic_content_only") is True
        and source.get("evaluation_only") is True
        and source.get("excluded_from_corpus_ingestion") is True
        and source.get("excluded_from_generation_context") is True
        and source.get("manual_review_required") is False
        and source.get("metric") == "MRR@20"
        and counts
        == {
            "body": EXPECTED_BODY,
            "header": EXPECTED_HEADER,
            "relationship": EXPECTED_RELATIONSHIP,
            "total": EXPECTED_BODY + EXPECTED_RELATIONSHIP + EXPECTED_HEADER,
        }
        and isinstance(records, list)
        and len(records) == 180,
        "retrieval_truth_contract_invalid",
    )
    cases: list[base.Case] = []
    for record in records:
        base.require(
            isinstance(record, dict)
            and set(record) == {
                "case_id", "family", "question", "required_evidence"
            }
            and record["family"] in {"body", "relationship", "header"}
            and isinstance(record["case_id"], str)
            and isinstance(record["question"], str)
            and record["question"].strip() == record["question"]
            and isinstance(record["required_evidence"], list)
            and len(record["required_evidence"]) == 1,
            "retrieval_case_contract_invalid",
        )
        evidence_record = record["required_evidence"][0]
        base.require(
            isinstance(evidence_record, dict)
            and set(evidence_record) == {"document_ref", "page"}
            and isinstance(evidence_record["document_ref"], str)
            and evidence_record["document_ref"].startswith("SYN-V3-")
            and type(evidence_record["page"]) is int
            and 1 <= evidence_record["page"] <= 5,
            "retrieval_evidence_contract_invalid",
        )
        cases.append(
            base.Case(
                record["case_id"],
                record["family"],
                record["question"],
                None,
                None,
                (
                    base.ExpectedEvidence(
                        evidence_record["document_ref"], evidence_record["page"]
                    ),
                ),
            )
        )
    base.require(
        sum(item.family == "body" for item in cases) == EXPECTED_BODY
        and sum(item.family == "relationship" for item in cases)
        == EXPECTED_RELATIONSHIP
        and sum(item.family == "header" for item in cases) == EXPECTED_HEADER
        and len({item.case_id for item in cases}) == len(cases)
        and len({item.question for item in cases}) == len(cases),
        "retrieval_case_inventory_invalid",
    )
    return tuple(cases)


def representation_inventory(
    source: Mapping[str, Any],
) -> tuple[
    tuple[base.CandidateRecord, ...],
    tuple[base.CandidateRecord, ...],
    dict[str, Mapping[str, Any]],
]:
    documents = source.get("documents")
    base.require(
        source.get("artifact_kind") == "non_publishable_structural_chunk_candidates"
        and source.get("publication_eligible") is False
        and isinstance(documents, list)
        and len(documents) == EXPECTED_DOCUMENTS,
        "candidate_source_contract_invalid",
    )
    records: list[base.CandidateRecord] = []
    raw: dict[str, Mapping[str, Any]] = {}
    for document in documents:
        base.require(
            isinstance(document, dict)
            and isinstance(document.get("document_ref"), str)
            and isinstance(document.get("candidates"), list),
            "candidate_document_contract_invalid",
        )
        for ordinal, candidate in enumerate(document["candidates"]):
            control = candidate.get("retrieval_filters", {}).get("document_control")
            anchor = candidate.get("citation_anchor")
            properties = candidate.get("projection_properties")
            chunk_id = candidate.get("chunk_id")
            base.require(
                isinstance(candidate, dict)
                and isinstance(chunk_id, str)
                and chunk_id not in raw
                and isinstance(control, dict)
                and isinstance(anchor, dict)
                and isinstance(properties, dict)
                and isinstance(candidate.get("projection_kind"), str)
                and isinstance(candidate.get("retrieval_text"), str)
                and isinstance(control.get("department"), str)
                and isinstance(control.get("department_normalized"), str)
                and isinstance(control.get("department_aliases"), list)
                and type(anchor.get("page_start")) is int
                and type(anchor.get("page_end")) is int,
                "candidate_metadata_invalid",
            )
            raw[chunk_id] = candidate
            records.append(
                base.CandidateRecord(
                    chunk_id,
                    candidate["document_id"],
                    candidate["document_version_id"],
                    document["document_ref"],
                    ordinal,
                    candidate["projection_kind"],
                    candidate["retrieval_text"],
                    anchor["page_start"],
                    anchor["page_end"],
                    control.get("policy_number"),
                    control.get("document_context"),
                    control["department"],
                    control["department_normalized"],
                    tuple(control["department_aliases"]),
                )
            )
    base.require(len(records) == EXPECTED_CANDIDATES, "candidate_count_invalid")
    atomic = tuple(
        item for item in records if item.projection_kind != "section_page_representative"
    )
    representatives = tuple(
        item for item in records if item.projection_kind == "section_page_representative"
    )
    base.require(
        len(atomic) == EXPECTED_ATOMIC
        and len(representatives) == EXPECTED_REPRESENTATIVES
        and sum(item.projection_kind == "document_control_metadata" for item in atomic)
        == EXPECTED_DOCUMENTS,
        "representation_inventory_invalid",
    )
    atomic_ids = {item.chunk_id for item in atomic}
    owners: dict[str, tuple[str, str]] = {}
    membership_count = 0
    for item in records:
        properties = raw[item.chunk_id]["projection_properties"]
        group_id = properties.get("retrieval_group_id")
        base.require(
            isinstance(group_id, str)
            and len(group_id) == 64
            and all(character in "0123456789abcdef" for character in group_id)
            and type(properties.get("retrieval_scoring_only")) is bool
            and type(properties.get("document_local_content_canonical")) is bool,
            "retrieval_representation_metadata_invalid",
        )
        owner = (item.document_id, item.document_version_id)
        base.require(
            owners.setdefault(group_id, owner) == owner,
            "retrieval_group_crosses_document_identity",
        )
        if item.projection_kind == "section_page_representative":
            components = properties.get("component_chunk_ids")
            base.require(
                properties["retrieval_scoring_only"] is True
                and properties.get("atomic_evidence_authoritative") is True
                and isinstance(components, list)
                and components
                and len(components) == len(set(components))
                and set(components) <= atomic_ids,
                "representative_component_contract_invalid",
            )
            membership_count += len(components)
        else:
            base.require(
                properties["retrieval_scoring_only"] is False,
                "atomic_marked_scoring_only",
            )
    base.require(membership_count == 756, "representative_membership_count_invalid")
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
    base.require(len(vectors) == len(inputs), "query_embedding_inventory_incomplete")
    return vectors, tokens


def family_metrics(
    results: Sequence[Mapping[str, Any]], family: str
) -> dict[str, Any]:
    selected = [item for item in results if item["family"] == family]
    return base.aggregate(selected)


def execute(arguments: argparse.Namespace) -> None:
    python_root = arguments.python_root.resolve(strict=True)
    sys.path.insert(0, str(python_root))
    from embed_document_candidates_via_endpoint import EndpointClient, wipe
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
    embeddings = base.load_bound_json(
        arguments.document_embeddings,
        arguments.expected_document_embeddings_sha256,
        256 * 1024 * 1024,
    )
    cases = load_cases(truth)
    atomic, representatives, raw = representation_inventory(chunks)
    candidates = atomic + representatives
    by_chunk = {item.chunk_id: item for item in candidates}
    vectors = base.validate_embedding_artifact(
        embeddings, arguments.expected_chunks_sha256, candidates
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
        and profile.document_local_duplicate_canonicalization is True
        and profile.representative_evidence == "expand_to_ordered_atomic_members",
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
    query_started = time.perf_counter_ns()
    try:
        client = EndpointClient(arguments.embedding_url, arguments.tokenizer_url, secret)
        base.require(
            client.model_identity() == embeddings.get("runtime_identity_digest"),
            "embedding_runtime_identity_changed",
        )
        query_vectors, query_tokens = embed_inputs(
            client, [base.QUERY_PREFIX + item.question for item in cases]
        )
    finally:
        if "client" in locals():
            client.close()
        wipe(secret)
    query_embedding_ms = elapsed_ms(query_started)

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

    selection_results: list[dict[str, Any]] = []
    expanded_results: list[dict[str, Any]] = []
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
                if (
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
            selection = base.measure_case(
                case, exact, lexical, vector, selected, permitted_atomic, by_chunk
            )
            selection["used_section_page_representatives"] = use_representations
            selection["searchable_candidate_count"] = len(searchable)
            selection_results.append(selection)
            matched = sum(
                any(base.matches(by_chunk[item.chunk_id], evidence) for item in expanded)
                for evidence in case.required_evidence
            )
            expanded_results.append(
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
    retrieval_ms = elapsed_ms(retrieval_started)

    metrics = {
        family: family_metrics(selection_results, family)
        for family in ("body", "relationship", "header")
    }
    metrics["overall"] = base.aggregate(selection_results)
    expansion_matched = sum(item["matched_evidence_count"] for item in expanded_results)
    expansion_total = sum(item["required_evidence_count"] for item in expanded_results)
    artifact: dict[str, Any] = {
        "artifact_kind": "ishikawa_synthetic_corpus_v3_preingestion_retrieval_observation",
        "schema_version": 1,
        "corpus_identity": "synthetic-corpus-v3",
        "measurement_class": "observational_baseline_no_promotion_gate",
        "source_sha256": {
            "chunks": arguments.expected_chunks_sha256,
            "document_embeddings": arguments.expected_document_embeddings_sha256,
            "retrieval_truth": arguments.expected_truth_sha256,
        },
        "retrieval_profile": {
            "profile_id": profile.digest,
            "exact_candidate_depth": profile.exact_candidate_depth,
            "lexical_candidate_depth": profile.lexical_candidate_depth,
            "vector_candidate_depth": profile.vector_candidate_depth,
            "fused_candidate_depth": profile.fused_candidate_depth,
            "rrf_constant": profile.rrf_constant,
            "lane_weights": {
                "exact": profile.exact_weight,
                "lexical": profile.lexical_weight,
                "vector": profile.vector_weight,
            },
            "section_page_representatives": True,
            "document_local_duplicate_canonicalization": True,
            "learned_reranker": False,
        },
        "candidate_inventory": {
            "documents": EXPECTED_DOCUMENTS,
            "atomic": len(atomic),
            "representatives": len(representatives),
            "total": len(candidates),
        },
        "case_inventory": {
            "body": EXPECTED_BODY,
            "relationship": EXPECTED_RELATIONSHIP,
            "header": EXPECTED_HEADER,
            "total": len(cases),
        },
        "metrics": metrics,
        "authoritative_expansion": {
            "matched_evidence": expansion_matched,
            "required_evidence": expansion_total,
            "complete": expansion_matched == expansion_total,
        },
        "token_usage": {"query_embedding_tokens": query_tokens},
        "latency_ms": {
            "query_embeddings": format(query_embedding_ms, ".3f"),
            "retrieval_and_measurement": format(retrieval_ms, ".3f"),
        },
        "boundaries": {
            "accepted_database_contact": False,
            "accepted_database_write": False,
            "black_corpus_access": False,
            "corpus_ingestion": False,
            "corpus_v1_changed": False,
            "corpus_v2_changed": False,
            "corpus_v3_changed": False,
            "gemma_contact": False,
            "nomic_contact": True,
            "private_temporary_postgresql": True,
            "profile_changed": False,
            "question_text_retained_in_observation": False,
            "query_vectors_retained": False,
            "source_text_retained_in_observation": False,
        },
        "promotion_gate_used": False,
        "next_gate": "review_v3_observational_metrics_before_isolated_ingestion",
        "results": {
            "selection": selection_results,
            "expanded_atomic_diagnostic": expanded_results,
        },
    }
    identity_source = {
        key: value
        for key, value in artifact.items()
        if key not in {"latency_ms", "results"}
    }
    artifact["observation_id"] = base.domain_digest(
        "ishikawa.synthetic-corpus-v3-preingestion-observation.v1",
        identity_source,
    )
    base.write_exclusive(
        arguments.output, base.canonical_json_bytes(artifact) + b"\n"
    )
    print("purpose=measure_synthetic_corpus_v3_preingestion_retrieval")
    for family in ("body", "relationship", "header", "overall"):
        metric = metrics[family]
        print(
            f"{family}_mrr_at_20={metric['mrr_at_20']};"
            f"relevant_at_5={metric['relevant_at_5']}/{metric['case_count']};"
            f"relevant_at_20={metric['relevant_at_20']}/{metric['case_count']};"
            f"required_evidence_at_20={metric['required_evidence_matched_at_20']}/"
            f"{metric['required_evidence_total']}"
        )
    print(
        f"authoritative_expansion={expansion_matched}/{expansion_total};"
        "promotion_gate_used=false;database_ingestion=false;gemma_contact=false"
    )
    print("synthetic_corpus_v3_preingestion_measurement=pass")


def self_test() -> None:
    records = [
        {"family": "body", "first_relevant_rank": 1, "relevant_within_top_five": True,
         "required_evidence_count": 1, "matched_evidence_count": 1},
        {"family": "body", "first_relevant_rank": 2, "relevant_within_top_five": True,
         "required_evidence_count": 1, "matched_evidence_count": 1},
    ]
    metrics = family_metrics(records, "body")
    assert metrics["mrr_at_20"] == "0.750000"
    assert metrics["relevant_at_20"] == 2
    print("synthetic_corpus_v3_preingestion_measurement_self_test=pass")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--python-root", type=Path)
    parser.add_argument("--chunks", type=Path)
    parser.add_argument("--expected-chunks-sha256")
    parser.add_argument("--document-embeddings", type=Path)
    parser.add_argument("--expected-document-embeddings-sha256")
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
        arguments.document_embeddings,
        arguments.expected_document_embeddings_sha256,
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
        print(
            f"synthetic_corpus_v3_preingestion_measurement=blocked;reason={error}",
            file=sys.stderr,
        )
        raise SystemExit(1) from error
    except KeyboardInterrupt:
        print(
            "synthetic_corpus_v3_preingestion_measurement=blocked;reason=interrupted",
            file=sys.stderr,
        )
        raise SystemExit(130)
