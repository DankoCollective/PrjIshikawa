#!/usr/bin/env python3
"""Measure four bounded section/page retrieval variants without publication."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import statistics
import sys
import time
from collections import defaultdict
from dataclasses import replace
from fractions import Fraction
from pathlib import Path
from typing import Any, Mapping, Sequence

import measure_synthetic_corpus_v2_candidate_profile as candidate_measurement
import measure_synthetic_corpus_v2_without_ingestion as base


KEY_TO_REF = {
    "policy.ops-17-control-2001": "SYN-V2-001",
    "policy.ops-17-control-2002": "SYN-V2-002",
    "policy.schedule-2003": "SYN-V2-003",
    "form.tst-9001": "SYN-V2-004",
    "policy.governance-manual": "SYN-V2-005",
    "procedure.incident-reporting": "SYN-V2-006",
}
VARIANTS = (
    "atomic_baseline",
    "atomic_duplicate_canonical",
    "section_page",
    "section_page_duplicate_canonical",
)


def load(path: Path, expected_sha256: str, maximum: int) -> dict[str, Any]:
    return base.load_bound_json(path, expected_sha256, maximum)


def remapped_candidates(source: Mapping[str, Any], expected_count: int) -> tuple[base.CandidateRecord, ...]:
    documents = source.get("documents")
    base.require(isinstance(documents, list) and len(documents) == 6, "candidate_inventory_invalid")
    records: list[base.CandidateRecord] = []
    seen: set[str] = set()
    for document in documents:
        document_key = document.get("document_ref")
        base.require(document_key in KEY_TO_REF, "document_reference_invalid")
        for ordinal, item in enumerate(document.get("candidates", [])):
            control = item.get("retrieval_filters", {}).get("document_control")
            anchor = item.get("citation_anchor")
            base.require(
                isinstance(control, dict)
                and isinstance(anchor, dict)
                and isinstance(item.get("chunk_id"), str)
                and item["chunk_id"] not in seen
                and isinstance(item.get("projection_kind"), str)
                and isinstance(item.get("retrieval_text"), str)
                and isinstance(control.get("department"), str)
                and isinstance(control.get("department_normalized"), str)
                and isinstance(control.get("department_aliases"), list)
                and type(anchor.get("page_start")) is int
                and type(anchor.get("page_end")) is int,
                "candidate_metadata_invalid",
            )
            seen.add(item["chunk_id"])
            records.append(base.CandidateRecord(
                item["chunk_id"], item["document_id"], item["document_version_id"],
                KEY_TO_REF[document_key], ordinal, item["projection_kind"],
                item["retrieval_text"], anchor["page_start"], anchor["page_end"],
                control.get("policy_number"), control.get("document_context"),
                control["department"], control["department_normalized"],
                tuple(control["department_aliases"]),
            ))
    base.require(len(records) == expected_count, "candidate_count_mismatch")
    return tuple(records)


def published_atomic_candidates(
    raw_candidates: Sequence[base.CandidateRecord],
    atomic_source: Mapping[str, Any],
    normalized_path: Path,
    atomic_chunks_path: Path,
    atomic_embeddings_path: Path,
    promotion_bundle: Path,
) -> tuple[tuple[base.CandidateRecord, ...], dict[str, str]]:
    """Reproduce the producer-to-published identity transformation offline."""

    from ishikawa.artifact_adapter import load_prepared_documents
    from ishikawa.canonical import domain_digest, file_sha256
    from ishikawa.operator_ingestion import OperatorIngestionPaths, load_operator_configuration
    from ishikawa.persistence import _artifact_set_id, _document_id, _document_version_id

    config_root = promotion_bundle / "config"
    source_root = promotion_bundle / "source"
    paths = OperatorIngestionPaths(
        config_root / "document_classes.yaml",
        config_root / "document_catalog.yaml",
        config_root / "ingestion_manifest.yaml",
        source_root,
        promotion_bundle,
    )
    _registry, _catalog, manifest = load_operator_configuration(paths)
    prepared = load_prepared_documents(
        normalized_path=normalized_path,
        normalized_sha256=file_sha256(str(normalized_path)),
        chunk_path=atomic_chunks_path,
        chunk_sha256=file_sha256(str(atomic_chunks_path)),
        embedding_path=atomic_embeddings_path,
        embedding_sha256=file_sha256(str(atomic_embeddings_path)),
        manifest=manifest,
        source_root=source_root,
    )
    raw_by_id = {item.chunk_id: item for item in raw_candidates}
    raw_contracts = {
        item["chunk_id"]: item
        for document in atomic_source["documents"]
        for item in document["candidates"]
    }
    published_by_raw: dict[str, base.CandidateRecord] = {}
    raw_to_published: dict[str, str] = {}
    for document in prepared:
        base.require(document.document_key in KEY_TO_REF, "prepared_document_key_invalid")
        document_id = _document_id(document.document_key)
        version_id = _document_version_id(document_id, document.source_digest)
        artifact_set_id = _artifact_set_id(
            version_id, atomic_source["method_profile_id"], document.class_id
        )
        for chunk in document.chunks:
            raw_id = chunk.client_metadata.get("producer_chunk_id")
            raw = raw_by_id.get(raw_id)
            contract = raw_contracts.get(raw_id)
            base.require(
                raw is not None
                and isinstance(contract, dict)
                and raw_id not in published_by_raw
                and chunk.retrieval_text == raw.retrieval_text
                and chunk.projection_kind == raw.projection_kind
                and chunk.page_start == raw.page_start
                and chunk.page_end == raw.page_end,
                "producer_projection_mapping_invalid",
            )
            retrieval_digest = domain_digest(
                "ishikawa.retrieval-text.v1", chunk.retrieval_text
            )
            published_id = domain_digest(
                "ishikawa.chunk.v1",
                {
                    "artifact_set_id": artifact_set_id,
                    "ordinal": chunk.ordinal,
                    "digest": retrieval_digest,
                },
            )
            raw_to_published[raw_id] = published_id
            published_by_raw[raw_id] = replace(
                raw,
                chunk_id=published_id,
                document_id=document_id,
                document_version_id=version_id,
                document_ref=KEY_TO_REF[document.document_key],
                ordinal=chunk.ordinal,
            )
    base.require(
        len(published_by_raw) == 139
        and set(published_by_raw) == set(raw_by_id)
        and len(set(raw_to_published.values())) == 139,
        "published_identity_inventory_invalid",
    )
    return (
        tuple(published_by_raw[item.chunk_id] for item in raw_candidates),
        raw_to_published,
    )


def artifact_indexes(
    atomic_source: Mapping[str, Any],
    representative_source: Mapping[str, Any],
    raw_to_published: Mapping[str, str],
) -> tuple[dict[str, tuple[str, str, int] | tuple[str]], set[str]]:
    group_by_chunk: dict[str, tuple[str, str, int] | tuple[str]] = {}
    canonical: set[str] = set()
    digest_groups: dict[tuple[str, str], list[str]] = defaultdict(list)
    for document in atomic_source["documents"]:
        document_ref = KEY_TO_REF[document["document_ref"]]
        for item in document["candidates"]:
            published_id = raw_to_published[item["chunk_id"]]
            anchor = item["citation_anchor"]
            if (
                item["projection_kind"] != "document_control_metadata"
                and isinstance(item.get("parent_unit_id"), str)
            ):
                group_by_chunk[published_id] = (
                    document_ref, item["parent_unit_id"], anchor["page_start"]
                )
            else:
                group_by_chunk[published_id] = (published_id,)
            if item["projection_kind"] != "document_control_metadata":
                digest_groups[(document_ref, item["content_digest"])].append(published_id)
    for members in digest_groups.values():
        canonical.add(members[0])
    for document in representative_source["documents"]:
        document_ref = KEY_TO_REF[document["document_ref"]]
        for item in document["candidates"]:
            group_by_chunk[item["chunk_id"]] = (
                document_ref,
                item["parent_unit_id"],
                item["citation_anchor"]["page_start"],
            )
    base.require(len(group_by_chunk) == 168 and len(canonical) == 112, "group_index_changed")
    return group_by_chunk, canonical


def collapse_groups(
    fused: Sequence[Any], group_by_chunk: Mapping[str, tuple[Any, ...]]
) -> tuple[Any, ...]:
    selected: list[Any] = []
    seen: set[tuple[Any, ...]] = set()
    for item in fused:
        key = group_by_chunk[item.chunk_id]
        if key not in seen:
            seen.add(key)
            selected.append(item)
    return tuple(selected)


def percentile(values: Sequence[float], fraction: float) -> float:
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, int((len(ordered) - 1) * fraction + 0.999999)))
    return ordered[index]


def measure_variant(
    variant: str,
    cases: Sequence[base.Case],
    query_vectors: Sequence[Sequence[float]],
    connection: Any,
    atomic: Sequence[base.CandidateRecord],
    representatives: Sequence[base.CandidateRecord],
    vectors: Mapping[str, Sequence[float]],
    by_chunk: Mapping[str, base.CandidateRecord],
    group_by_chunk: Mapping[str, tuple[Any, ...]],
    canonical: set[str],
    lane_candidate_type: Any,
    fuse: Any,
    *,
    retain_cases: bool,
) -> tuple[dict[str, Any], list[dict[str, Any]], list[float]]:
    use_sections = variant.startswith("section_page")
    use_canonical = variant.endswith("duplicate_canonical")
    results: list[dict[str, Any]] = []
    latency_ms: list[float] = []
    for case, query_vector in zip(cases, query_vectors, strict=True):
        started = time.perf_counter_ns()
        permitted_atomic = base.permitted_candidates(case, atomic)
        exact = base.exact_lane(case, permitted_atomic, lane_candidate_type)
        section_route = use_sections and case.family == "body" and not exact
        canonical_route = use_canonical and case.family == "body" and not exact
        permitted_refs = {item.document_ref for item in permitted_atomic}
        searchable_atomic = tuple(
            item for item in permitted_atomic
            if not canonical_route
            or item.projection_kind == "document_control_metadata"
            or item.chunk_id in canonical
        )
        permitted_representatives = tuple(
            item for item in representatives if item.document_ref in permitted_refs
        )
        searchable = searchable_atomic + (
            permitted_representatives if section_route else ()
        )
        lexical = base.lexical_lane(
            connection, case.question, searchable, by_chunk, lane_candidate_type
        )
        vector = base.vector_lane(query_vector, searchable, vectors, lane_candidate_type)
        fused = fuse(
            {"exact": exact, "lexical": lexical, "vector": vector},
            rrf_constant=60,
            lane_weights={"exact": 1, "lexical": 1, "vector": 4},
        )
        if section_route:
            fused = collapse_groups(fused, group_by_chunk)
        fused = fused[:20]
        latency_ms.append((time.perf_counter_ns() - started) / 1_000_000)
        result = base.measure_case(
            case, exact, lexical, vector, fused, permitted_atomic, by_chunk
        )
        if retain_cases:
            result["section_page_route"] = section_route
            result["duplicate_canonical_route"] = canonical_route
            result["searchable_candidate_count"] = len(searchable)
        results.append(result)
    body = base.aggregate(results[:base.BODY_CASE_COUNT])
    header = base.aggregate(results[base.BODY_CASE_COUNT:])
    eligible = (
        Fraction(body["mrr_fraction_numerator"], body["mrr_fraction_denominator"])
        > Fraction(91, 100)
        and body["relevant_at_20"] == 60
        and body["required_evidence_matched_at_20"] == 60
        and header["mrr_at_20"] == "1.000000"
        and header["relevant_at_5"] == 8
        and header["required_evidence_matched_at_20"] == 11
    )
    summary = {
        "name": variant,
        "body_metrics": body,
        "header_metrics": header,
        "eligibility_gate_met": eligible,
        "latency_ms": {
            "median": format(statistics.median(latency_ms), ".3f"),
            "p95": format(percentile(latency_ms, 0.95), ".3f"),
            "maximum": format(max(latency_ms), ".3f"),
            "diagnostic_only": True,
        },
    }
    return summary, results, latency_ms


def execute(arguments: argparse.Namespace) -> int:
    python_root = arguments.python_root.resolve(strict=True)
    sys.path.insert(0, str(python_root))
    from embed_document_candidates_via_endpoint import EndpointClient, wipe
    from ishikawa.retrieval import LaneCandidate, reciprocal_rank_fusion

    arguments.normalized = arguments.normalized.resolve(strict=True)
    arguments.promotion_bundle = arguments.promotion_bundle.resolve(strict=True)
    promotion_manifest = arguments.promotion_bundle / "SHA256SUMS"
    base.require(
        arguments.normalized.is_file()
        and not arguments.normalized.is_symlink()
        and base.sha256_file(arguments.normalized) == arguments.expected_normalized_sha256
        and arguments.promotion_bundle.is_dir()
        and not arguments.promotion_bundle.is_symlink()
        and promotion_manifest.is_file()
        and not promotion_manifest.is_symlink()
        and base.sha256_file(promotion_manifest)
        == arguments.expected_promotion_manifest_sha256,
        "published_identity_source_invalid",
    )

    design = load(arguments.design, arguments.expected_design_sha256, 4 * 1024 * 1024)
    atomic_source = load(arguments.atomic_chunks, arguments.expected_atomic_chunks_sha256, 32 * 1024 * 1024)
    representative_source = load(
        arguments.representatives, arguments.expected_representatives_sha256, 32 * 1024 * 1024
    )
    atomic_embeddings_source = load(
        arguments.atomic_embeddings, arguments.expected_atomic_embeddings_sha256, 192 * 1024 * 1024
    )
    representative_embeddings_source = load(
        arguments.representative_embeddings,
        arguments.expected_representative_embeddings_sha256,
        64 * 1024 * 1024,
    )
    body_source = load(arguments.body_cases, arguments.expected_body_cases_sha256, 2 * 1024 * 1024)
    header_source = load(arguments.header_cases, arguments.expected_header_cases_sha256, 1024 * 1024)
    accepted = load(arguments.accepted_observation, arguments.expected_accepted_observation_sha256, 16 * 1024 * 1024)
    base.require(
        design.get("artifact_kind")
        == "ishikawa_published_synthetic_corpus_v2_section_page_experiment_design"
        and [item["name"] for item in design.get("variants", [])] == list(VARIANTS)
        and design.get("candidate_inventory", {}).get("eligible_section_page_groups") == 29,
        "design_contract_invalid",
    )
    base.require(
        accepted.get("body_metrics", {}).get("mrr_at_20") == "0.873056"
        and accepted.get("body_metrics", {}).get("relevant_at_5") == 58
        and accepted.get("body_metrics", {}).get("relevant_at_20") == 60
        and accepted.get("header_metrics", {}).get("mrr_at_20") == "1.000000",
        "accepted_baseline_invalid",
    )
    raw_atomic = remapped_candidates(atomic_source, 139)
    representatives = remapped_candidates(representative_source, 29)
    atomic, raw_to_published = published_atomic_candidates(
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
        atomic_embeddings_source, arguments.expected_atomic_chunks_sha256, raw_atomic
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
    atomic_vectors = {
        raw_to_published[raw_id]: vector for raw_id, vector in raw_atomic_vectors.items()
    }
    vectors = {**atomic_vectors, **representative_vectors}
    group_by_chunk, canonical = artifact_indexes(
        atomic_source, representative_source, raw_to_published
    )
    body_cases = candidate_measurement.load_v2_body_cases(body_source)
    header_cases = base.load_header_cases(header_source)
    cases = body_cases + header_cases

    secret_text = os.environ.pop("ISHIKAWA_NOMIC_API_KEY", "")
    base.require(32 <= len(secret_text) <= 1024 and "\n" not in secret_text, "nomic_credential_invalid")
    secret = bytearray(secret_text.encode("utf-8"))
    secret_text = ""
    try:
        client = EndpointClient(arguments.embedding_url, arguments.tokenizer_url, secret)
        base.require(
            client.model_identity() == atomic_embeddings_source["runtime_identity_digest"],
            "embedding_runtime_identity_changed",
        )
        query_vectors: list[list[float]] = []
        query_tokens = 0
        inputs = [base.QUERY_PREFIX + case.question for case in cases]
        for start in range(0, len(inputs), 16):
            batch, usage = client.embeddings(inputs[start:start + 16])
            query_vectors.extend(batch)
            query_tokens += usage
    finally:
        if "client" in locals():
            client.close()
        wipe(secret)
    base.require(len(query_vectors) == 68, "query_embedding_coverage_invalid")

    try:
        import psycopg
        connection = psycopg.connect(
            host=str(arguments.postgresql_socket), port=arguments.postgresql_port,
            dbname="postgres", user=arguments.postgresql_user, connect_timeout=5,
        )
    except Exception as error:
        raise base.MeasurementError("temporary_postgresql_connection_failed") from error
    first_pass: list[dict[str, Any]] = []
    retained_cases: dict[str, list[dict[str, Any]]] = {}
    try:
        connection.execute("BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
        state = connection.execute(
            "SELECT current_setting('transaction_read_only'), current_database(), current_user"
        ).fetchone()
        base.require(state == ("on", "postgres", arguments.postgresql_user), "database_boundary_invalid")
        for variant in VARIANTS:
            summary, results, _latency = measure_variant(
                variant, cases, query_vectors, connection, atomic, representatives,
                vectors, by_chunk, group_by_chunk, canonical, LaneCandidate,
                reciprocal_rank_fusion, retain_cases=True,
            )
            first_pass.append(summary)
            retained_cases[variant] = results
        replay: list[dict[str, Any]] = []
        for variant in VARIANTS:
            summary, results, _latency = measure_variant(
                variant, cases, query_vectors, connection, atomic, representatives,
                vectors, by_chunk, group_by_chunk, canonical, LaneCandidate,
                reciprocal_rank_fusion, retain_cases=False,
            )
            replay.append(summary)
            base.require(
                [
                    (item["case_id"], item["first_relevant_rank"], item["matched_evidence"])
                    for item in results
                ]
                == [
                    (item["case_id"], item["first_relevant_rank"], item["matched_evidence"])
                    for item in retained_cases[variant]
                ],
                "deterministic_replay_failed",
            )
        connection.rollback()
    finally:
        connection.close()
    # The deterministic replay is also the warm pass: query vectors and the
    # PostgreSQL text-search path have already been exercised once.
    for measured, warm in zip(first_pass, replay, strict=True):
        measured["latency_ms"] = {
            **warm["latency_ms"],
            "measurement_pass": 2,
        }
    baseline = first_pass[0]
    base.require(
        baseline["body_metrics"] == accepted["body_metrics"]
        and baseline["header_metrics"] == accepted["header_metrics"],
        "accepted_atomic_baseline_replay_failed",
    )
    eligible = [item["name"] for item in first_pass if item["eligibility_gate_met"]]
    case_observations = {
        name: [
            {
                "case_id": item["case_id"],
                "family": item["family"],
                "query_sha256": item["query_sha256"],
                "first_relevant_rank": item["first_relevant_rank"],
                "relevant_within_top_five": item["relevant_within_top_five"],
                "matched_evidence_count": item["matched_evidence_count"],
                "fused_chunk_ids": [entry["chunk_id"] for entry in item["fused"]],
                "section_page_route": item["section_page_route"],
                "duplicate_canonical_route": item["duplicate_canonical_route"],
                "searchable_candidate_count": item["searchable_candidate_count"],
            }
            for item in retained_cases[name]
        ]
        for name in VARIANTS
    }
    artifact: dict[str, Any] = {
        "schema_version": 1,
        "artifact_kind": "ishikawa_published_v2_section_page_candidate_experiment",
        "source_sha256": {
            "design": arguments.expected_design_sha256,
            "atomic_chunks": arguments.expected_atomic_chunks_sha256,
            "representatives": arguments.expected_representatives_sha256,
            "atomic_embeddings": arguments.expected_atomic_embeddings_sha256,
            "representative_embeddings": arguments.expected_representative_embeddings_sha256,
            "body_truth": arguments.expected_body_cases_sha256,
            "header_truth": arguments.expected_header_cases_sha256,
            "accepted_observation": arguments.expected_accepted_observation_sha256,
            "normalized": arguments.expected_normalized_sha256,
            "promotion_manifest": arguments.expected_promotion_manifest_sha256,
        },
        "inventory": {
            "atomic_candidates": 139,
            "section_page_representatives": 29,
            "maximum_pre_collapse_candidates": 168,
            "cases": 68,
            "query_embedding_tokens": query_tokens,
        },
        "frozen_profile": design["frozen_profile"],
        "accepted_atomic_baseline_exactly_replayed": True,
        "deterministic_replay": True,
        "variants": first_pass,
        "eligible_variants": eligible,
        "case_observations": case_observations,
        "truth_usage": {
            "evaluation_only": True,
            "corpus_ingestion": False,
            "generation_context": False,
            "black_corpus_application": False,
        },
        "boundaries": {
            "private_temporary_postgresql": True,
            "database_tables_read": False,
            "database_write": False,
            "accepted_database_contact": False,
            "nomic_contact": True,
            "gemma_contact": False,
            "corpus_changed": False,
            "truth_changed": False,
            "production_profile_changed": False,
            "candidate_promoted": False,
        },
        "next_gate": (
            "review_section_page_candidate_experiment_before_any_freeze"
            if eligible else "review_section_page_experiment_failures_before_new_design"
        ),
    }
    artifact["observation_set_id"] = base.domain_digest(
        "ishikawa.published-v2-section-page-candidate-experiment.v1", artifact
    )
    payload = base.canonical_json_bytes(artifact) + b"\n"
    base.write_exclusive(arguments.output, payload)
    print("purpose=measure_bounded_section_page_candidate_experiment")
    for item in first_pass:
        print(
            f"variant={item['name']};body_mrr_at_20={item['body_metrics']['mrr_at_20']};"
            f"body_relevant_at_5={item['body_metrics']['relevant_at_5']}/60;"
            f"body_relevant_at_20={item['body_metrics']['relevant_at_20']}/60;"
            f"gate={'pass' if item['eligibility_gate_met'] else 'not_met'};"
            f"warm_p95_ms={item['latency_ms']['p95']}"
        )
    print(
        f"eligible_variants={','.join(eligible) if eligible else 'none'};"
        "accepted_atomic_baseline_exactly_replayed=true;deterministic_replay=true"
    )
    print(f"artifact_sha256={hashlib.sha256(payload).hexdigest()};artifact_bytes={len(payload)}")
    print("published_v2_section_page_candidate_experiment=pass")
    return 0


def self_test() -> int:
    sample = type("Candidate", (), {})
    first = sample(); first.chunk_id = "a"
    second = sample(); second.chunk_id = "b"
    third = sample(); third.chunk_id = "c"
    assert collapse_groups((first, second, third), {"a": ("x",), "b": ("x",), "c": ("y",)}) == (first, third)
    assert percentile([1.0, 2.0, 3.0], 0.95) == 3.0
    print("published_v2_section_page_candidate_experiment_self_test=pass")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--python-root", type=Path)
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
    parser.add_argument("--accepted-observation", type=Path)
    parser.add_argument("--expected-accepted-observation-sha256")
    parser.add_argument("--embedding-url", default="http://127.0.0.1:8001/v1/embeddings")
    parser.add_argument("--tokenizer-url", default="http://127.0.0.1:8001/tokenize")
    parser.add_argument("--postgresql-socket", type=Path)
    parser.add_argument("--postgresql-port", type=int, default=65432)
    parser.add_argument("--postgresql-user")
    parser.add_argument("--output", type=Path)
    arguments = parser.parse_args()
    if arguments.self_test == arguments.run:
        raise base.MeasurementError("mode_invalid")
    if arguments.self_test:
        return self_test()
    required = tuple(
        value for key, value in vars(arguments).items()
        if key not in {"self_test", "run", "embedding_url", "tokenizer_url", "postgresql_port"}
    )
    base.require(all(item is not None for item in required), "required_argument_missing")
    base.require(
        arguments.python_root.is_absolute()
        and arguments.python_root.is_dir()
        and arguments.postgresql_socket.is_absolute()
        and str(arguments.postgresql_socket).startswith("/tmp/")
        and 1024 <= arguments.postgresql_port <= 65535,
        "runtime_boundary_invalid",
    )
    return execute(arguments)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except base.MeasurementError as error:
        print(f"published_v2_section_page_candidate_experiment=blocked;reason={error}", file=sys.stderr)
        raise SystemExit(1)
