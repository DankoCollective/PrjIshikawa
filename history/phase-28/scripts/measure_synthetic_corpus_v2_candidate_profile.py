#!/usr/bin/env python3
"""Measure isolated corpus-v2 metadata routing and sibling assembly."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from fractions import Fraction
from pathlib import Path
from typing import Any, Mapping, Sequence

import measure_synthetic_corpus_v2_without_ingestion as base


METADATA_QUERY = re.compile(
    r"\b(?:organization|document\s+context|effective\s+date|policy\s+number|"
    r"applicability(?:\s*/\s*class)?|department|dept\.?|approval)\b",
    re.IGNORECASE,
)


def load_v2_body_cases(value: Mapping[str, Any]) -> tuple[base.Case, ...]:
    changes = value.get("layout_changes_from_v1")
    base.require(
        value.get("artifact_kind") == "ishikawa_synthetic_corpus_v2_body_retrieval_cases"
        and value.get("schema_version") == 1
        and value.get("synthetic_content_only") is True
        and value.get("evaluation_only") is True
        and value.get("excluded_from_corpus_ingestion") is True
        and value.get("excluded_from_generation_context") is True
        and changes == [{
            "case_ids": ["E-010", "E-011", "E-012"],
            "document": "Synthetic Operations Control 2002",
            "from_page": 2,
            "reason": "leading_blank_page_removed_before_v2_masthead",
            "to_page": 1,
        }],
        "v2_body_truth_contract_invalid",
    )
    adapted = dict(value)
    adapted["artifact_kind"] = "ishikawa_extended_retrieval_mrr_cases"
    cases = base.load_body_cases(adapted)
    expected = {
        item.case_id: tuple((evidence.document_ref, evidence.page) for evidence in item.required_evidence)
        for item in cases
    }
    base.require(
        expected["E-010"] == (("SYN-V2-002", 1),)
        and expected["E-011"] == (("SYN-V2-002", 1),)
        and expected["E-012"] == (("SYN-V2-002", 1),),
        "v2_body_truth_page_correction_missing",
    )
    return cases


def flatten_candidates(source: Mapping[str, Any]) -> tuple[base.CandidateRecord, ...]:
    documents = source.get("documents")
    base.require(isinstance(documents, list) and len(documents) == 6, "candidate_inventory_invalid")
    records: list[base.CandidateRecord] = []
    seen: set[str] = set()
    for document in documents:
        base.require(
            isinstance(document, dict)
            and isinstance(document.get("document_ref"), str)
            and isinstance(document.get("candidates"), list),
            "candidate_inventory_invalid",
        )
        for ordinal, candidate in enumerate(document["candidates"]):
            control = candidate.get("retrieval_filters", {}).get("document_control")
            anchor = candidate.get("citation_anchor")
            base.require(
                isinstance(candidate, dict)
                and isinstance(control, dict)
                and isinstance(anchor, dict)
                and isinstance(candidate.get("chunk_id"), str)
                and candidate["chunk_id"] not in seen
                and isinstance(candidate.get("projection_kind"), str)
                and isinstance(candidate.get("retrieval_text"), str)
                and isinstance(control.get("department"), str)
                and isinstance(control.get("department_normalized"), str)
                and isinstance(control.get("department_aliases"), list)
                and type(anchor.get("page_start")) is int
                and type(anchor.get("page_end")) is int,
                "candidate_metadata_invalid",
            )
            seen.add(candidate["chunk_id"])
            records.append(base.CandidateRecord(
                candidate["chunk_id"],
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
            ))
    base.require(len(records) > 139, "candidate_assembly_inventory_invalid")
    base.require(
        sum(item.projection_kind == "document_control_metadata" for item in records) == 6,
        "document_control_candidate_inventory_invalid",
    )
    base.require(
        sum(item.projection_kind == "compatible_sibling_assembly" for item in records)
        == source.get("experiment", {}).get("compatible_sibling_assemblies")
        and source.get("experiment", {}).get("production_profile_changed") is False,
        "candidate_assembly_inventory_invalid",
    )
    return tuple(records)


def metadata_lane_enabled(case: base.Case) -> bool:
    return case.family != "body" or case.department is not None or METADATA_QUERY.search(case.question) is not None


def lane_candidates(
    case: base.Case,
    permitted: Sequence[base.CandidateRecord],
) -> tuple[base.CandidateRecord, ...]:
    if metadata_lane_enabled(case):
        return tuple(permitted)
    return tuple(
        candidate for candidate in permitted
        if candidate.projection_kind != "document_control_metadata"
    )


def execute(arguments: argparse.Namespace) -> None:
    chunks = base.load_bound_json(arguments.chunks, arguments.expected_chunks_sha256, 32 * 1024 * 1024)
    body_source = base.load_bound_json(
        arguments.body_cases, arguments.expected_body_cases_sha256, 2 * 1024 * 1024
    )
    header_source = base.load_bound_json(
        arguments.header_cases, arguments.expected_header_cases_sha256, 1024 * 1024
    )
    embeddings = base.load_bound_json(
        arguments.document_embeddings,
        arguments.expected_document_embeddings_sha256,
        192 * 1024 * 1024,
    )
    body_cases = load_v2_body_cases(body_source)
    header_cases = base.load_header_cases(header_source)
    cases = body_cases + header_cases
    candidates = flatten_candidates(chunks)
    by_chunk = {candidate.chunk_id: candidate for candidate in candidates}
    vectors = base.validate_embedding_artifact(
        embeddings, arguments.expected_chunks_sha256, candidates
    )

    secret_text = os.environ.pop("ISHIKAWA_NOMIC_API_KEY", "")
    base.require(32 <= len(secret_text) <= 1024 and "\n" not in secret_text, "nomic_credential_invalid")
    secret = bytearray(secret_text.encode("utf-8"))
    secret_text = ""
    sys.path.insert(0, str(arguments.python_root))
    from embed_document_candidates_via_endpoint import EndpointClient, wipe
    from ishikawa.retrieval import LaneCandidate, reciprocal_rank_fusion

    try:
        client = EndpointClient(arguments.embedding_url, arguments.tokenizer_url, secret)
        runtime_identity = client.model_identity()
        base.require(
            runtime_identity == embeddings.get("runtime_identity_digest"),
            "embedding_runtime_identity_changed",
        )
        query_vectors: list[list[float]] = []
        query_usage = 0
        inputs = [base.QUERY_PREFIX + case.question for case in cases]
        for start in range(0, len(inputs), 16):
            batch, usage = client.embeddings(inputs[start:start + 16])
            query_vectors.extend(batch)
            query_usage += usage
    finally:
        if "client" in locals():
            client.close()
        wipe(secret)
    base.require(len(query_vectors) == len(cases), "query_embedding_coverage_invalid")

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

    results: list[dict[str, Any]] = []
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
            permitted = base.permitted_candidates(case, candidates)
            searchable = lane_candidates(case, permitted)
            exact = base.exact_lane(case, permitted, LaneCandidate)
            lexical = base.lexical_lane(
                connection, case.question, searchable, by_chunk, LaneCandidate
            )
            vector = base.vector_lane(query_vector, searchable, vectors, LaneCandidate)
            fused = reciprocal_rank_fusion(
                {"exact": exact, "lexical": lexical, "vector": vector},
                rrf_constant=60,
                lane_weights={"exact": 1, "lexical": 1, "vector": 4},
            )[:20]
            result = base.measure_case(
                case, exact, lexical, vector, fused, permitted, by_chunk
            )
            result["document_control_metadata_lane_enabled"] = metadata_lane_enabled(case)
            result["searchable_candidate_count"] = len(searchable)
            result["searchable_sibling_assembly_count"] = sum(
                candidate.projection_kind == "compatible_sibling_assembly"
                for candidate in searchable
            )
            results.append(result)
        connection.rollback()
    finally:
        connection.close()

    body_results = results[:base.BODY_CASE_COUNT]
    header_results = results[base.BODY_CASE_COUNT:]
    body_metrics = base.aggregate(body_results)
    header_metrics = base.aggregate(header_results)
    gate = (
        Fraction(
            body_metrics["mrr_fraction_numerator"],
            body_metrics["mrr_fraction_denominator"],
        ) > Fraction(91, 100)
        and body_metrics["relevant_at_20"] == base.BODY_CASE_COUNT
        and header_metrics["relevant_at_5"] == base.HEADER_CASE_COUNT
        and header_metrics["required_evidence_matched_at_20"]
        == header_metrics["required_evidence_total"]
    )
    artifact: dict[str, Any] = {
        "schema_version": 1,
        "artifact_kind": "ishikawa_synthetic_corpus_v2_candidate_profile_observation",
        "source_chunks_sha256": arguments.expected_chunks_sha256,
        "source_document_embeddings_sha256": arguments.expected_document_embeddings_sha256,
        "body_case_set_sha256": arguments.expected_body_cases_sha256,
        "header_case_set_sha256": arguments.expected_header_cases_sha256,
        "chunk_method_profile_id": chunks["method_profile_id"],
        "retrieval_profile": {
            "exact_candidate_depth": 1,
            "lexical_candidate_depth": 20,
            "vector_candidate_depth": 20,
            "fused_candidate_depth": 20,
            "rrf_constant": 60,
            "lane_weights": {"exact": 1, "lexical": 1, "vector": 4},
            "learned_reranker": False,
            "metadata_lane_routing": "explicit_header_department_or_exact_only",
            "compatible_sibling_assembly": "additive_same_parent_same_page_maximum_8",
        },
        "truth_usage": {
            "evaluation_only": True,
            "corpus_ingestion": False,
            "generation_context": False,
            "production_retrieval_hint": False,
            "black_corpus_application": False,
        },
        "document_count": 6,
        "candidate_count": len(candidates),
        "compatible_sibling_assembly_count": sum(
            candidate.projection_kind == "compatible_sibling_assembly"
            for candidate in candidates
        ),
        "query_embedding_count": len(cases),
        "query_embedding_usage_tokens": query_usage,
        "body_metrics": body_metrics,
        "header_metrics": header_metrics,
        "preingestion_measurement_gate": "pass" if gate else "not_met",
        "database_boundary": "private_temporary_postgresql_repeatable_read_read_only",
        "database_tables_read": False,
        "database_write": False,
        "accepted_v1_database_contact": False,
        "gemma_contact": False,
        "question_text_retained": False,
        "query_vectors_retained": False,
        "source_text_retained": False,
        "credentials_retained": False,
        "production_profile_changed": False,
        "cases": results,
    }
    artifact["observation_set_id"] = base.domain_digest(
        "ishikawa.synthetic-corpus-v2-candidate-profile-observation.v1", artifact
    )
    payload = base.canonical_json_bytes(artifact)
    base.write_exclusive(arguments.output, payload)
    print(
        f"case_count={len(cases)};body_cases={base.BODY_CASE_COUNT};"
        f"header_cases={base.HEADER_CASE_COUNT};query_embeddings={len(cases)}"
    )
    print(
        f"body_mrr_at_20={body_metrics['mrr_at_20']};"
        f"body_relevant_at_5={body_metrics['relevant_at_5']}/{base.BODY_CASE_COUNT};"
        f"body_relevant_at_20={body_metrics['relevant_at_20']}/{base.BODY_CASE_COUNT}"
    )
    print(
        f"header_mrr_at_20={header_metrics['mrr_at_20']};"
        f"header_relevant_at_5={header_metrics['relevant_at_5']}/{base.HEADER_CASE_COUNT};"
        f"header_required_evidence_at_20={header_metrics['required_evidence_matched_at_20']}/"
        f"{header_metrics['required_evidence_total']}"
    )
    print(
        f"candidate_count={len(candidates)};compatible_sibling_assemblies="
        f"{artifact['compatible_sibling_assembly_count']}"
    )
    print(
        f"preingestion_measurement_gate={'pass' if gate else 'not_met'};"
        "strict_body_target=greater_than_0.91"
    )
    print(
        "truth_evaluation_only=true;truth_ingested=false;truth_sent_to_gemma=false;"
        "truth_applied_to_black_corpus=false;production_profile_changed=false"
    )
    print(
        f"observation_set_id={artifact['observation_set_id']};"
        f"artifact_sha256={hashlib.sha256(payload).hexdigest()};artifact_bytes={len(payload)}"
    )
    print("synthetic_corpus_v2_candidate_profile_measurement=pass")


def self_test() -> None:
    body = base.Case("E-001", "body", "What is the effective date?", None, None, ())
    ordinary = base.Case("E-002", "body", "What controls apply?", None, None, ())
    header = base.Case("H-001", "header-metadata", "What applies?", None, None, ())
    assert metadata_lane_enabled(body)
    assert not metadata_lane_enabled(ordinary)
    assert metadata_lane_enabled(header)
    print("synthetic_corpus_v2_candidate_profile_measurement_self_test=pass")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--python-root", type=Path)
    parser.add_argument("--chunks", type=Path)
    parser.add_argument("--expected-chunks-sha256")
    parser.add_argument("--document-embeddings", type=Path)
    parser.add_argument("--expected-document-embeddings-sha256")
    parser.add_argument("--body-cases", type=Path)
    parser.add_argument("--expected-body-cases-sha256")
    parser.add_argument("--header-cases", type=Path)
    parser.add_argument("--expected-header-cases-sha256")
    parser.add_argument("--embedding-url", default="http://127.0.0.1:8001/v1/embeddings")
    parser.add_argument("--tokenizer-url", default="http://127.0.0.1:8001/tokenize")
    parser.add_argument("--postgresql-socket", type=Path)
    parser.add_argument("--postgresql-port", type=int, default=65432)
    parser.add_argument("--postgresql-user")
    parser.add_argument("--output", type=Path)
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
        return 0
    required = (
        arguments.python_root, arguments.chunks, arguments.expected_chunks_sha256,
        arguments.document_embeddings, arguments.expected_document_embeddings_sha256,
        arguments.body_cases, arguments.expected_body_cases_sha256,
        arguments.header_cases, arguments.expected_header_cases_sha256,
        arguments.postgresql_socket, arguments.postgresql_user, arguments.output,
    )
    base.require(all(item is not None for item in required), "required_argument_missing")
    base.require(
        arguments.python_root.is_absolute()
        and arguments.python_root.is_dir()
        and arguments.postgresql_socket.is_absolute()
        and str(arguments.postgresql_socket).startswith("/tmp/")
        and 1024 <= arguments.postgresql_port <= 65535
        and re.fullmatch(r"[a-z_][a-z0-9_-]{0,62}", arguments.postgresql_user),
        "runtime_boundary_invalid",
    )
    execute(arguments)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except base.MeasurementError as error:
        print(
            f"synthetic_corpus_v2_candidate_profile_measurement=blocked;reason={error}",
            file=sys.stderr,
        )
        raise SystemExit(1)
