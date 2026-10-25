#!/usr/bin/env python3
"""Measure the published synthetic-corpus-v2 through the live PostgreSQL lanes."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from dataclasses import replace
from pathlib import Path
from typing import Any


class LiveMeasurementError(RuntimeError):
    """Stable content-free live-measurement failure."""


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise LiveMeasurementError(reason)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_bound_json(path: Path, expected_sha256: str, maximum_bytes: int) -> dict[str, Any]:
    require(
        path.is_absolute()
        and path.is_file()
        and not path.is_symlink()
        and path.stat().st_size <= maximum_bytes,
        "json_input_unsafe",
    )
    require(sha256_file(path) == expected_sha256, "json_identity_mismatch")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise LiveMeasurementError("json_input_invalid") from error
    require(isinstance(value, dict), "json_input_invalid")
    return value


def self_test() -> int:
    require(
        len({"SYN-V2-001", "SYN-V2-002", "SYN-V2-003"}) == 3,
        "self_test_failed",
    )
    print("live_synthetic_corpus_v2_retrieval_measurement_self_test=pass")
    return 0


def execute(arguments: argparse.Namespace) -> int:
    scripts_root = Path(arguments.scripts_root).resolve(strict=True)
    python_root = Path(arguments.python_root).resolve(strict=True)
    config_root = Path(arguments.config_root).resolve(strict=True)
    sys.path.insert(0, str(scripts_root))
    sys.path.insert(0, str(python_root))

    import measure_synthetic_corpus_v2_candidate_profile as candidate_measurement
    import measure_synthetic_corpus_v2_without_ingestion as base
    import psycopg
    from ishikawa.method_profile import validate_retrieval_profile
    from ishikawa.native_adapters import (
        ACCEPTED_EMBEDDING_SPACE_ID,
        NativeQueryEmbeddingAdapter,
    )
    from ishikawa.retrieval import (
        CandidateFilters,
        LaneCandidate,
        lexical_search,
        reciprocal_rank_fusion,
        vector_search,
    )
    from ishikawa.runtime import ProtectedEnvironmentValue, validate_runtime_dependencies
    from ishikawa.yaml_loader import load_restricted_yaml

    chunks_path = Path(arguments.chunks).resolve(strict=True)
    body_path = Path(arguments.body_cases).resolve(strict=True)
    header_path = Path(arguments.header_cases).resolve(strict=True)
    chunks = load_bound_json(chunks_path, arguments.expected_chunks_sha256, 32 * 1024 * 1024)
    body_source = load_bound_json(
        body_path, arguments.expected_body_cases_sha256, 2 * 1024 * 1024
    )
    header_source = load_bound_json(
        header_path, arguments.expected_header_cases_sha256, 1024 * 1024
    )
    body_cases = candidate_measurement.load_v2_body_cases(body_source)
    header_cases = base.load_header_cases(header_source)
    cases = body_cases + header_cases
    ref_to_key = {
        "SYN-V2-001": "policy.ops-17-control-2001",
        "SYN-V2-002": "policy.ops-17-control-2002",
        "SYN-V2-003": "policy.schedule-2003",
        "SYN-V2-004": "form.tst-9001",
        "SYN-V2-005": "policy.governance-manual",
        "SYN-V2-006": "procedure.incident-reporting",
    }
    key_to_ref = {value: key for key, value in ref_to_key.items()}
    require(
        {
            document.get("document_ref")
            for document in chunks.get("documents", [])
            if isinstance(document, dict)
        }
        == set(key_to_ref),
        "published_document_reference_inventory_invalid",
    )
    scoring_chunks = {
        **chunks,
        "documents": [
            {**document, "document_ref": key_to_ref[document["document_ref"]]}
            for document in chunks["documents"]
        ],
    }
    artifact_candidates = base.flatten_candidates(scoring_chunks)
    artifact_by_chunk = {item.chunk_id: item for item in artifact_candidates}
    expected_chunk_contracts = {
        item["chunk_id"]: item
        for document in chunks["documents"]
        for item in document["candidates"]
    }
    require(
        len(cases) == 68 and len(artifact_candidates) == 139,
        "measurement_inventory_invalid",
    )

    profile = validate_retrieval_profile(
        load_restricted_yaml(config_root / "method_profile.yaml", label="method profile")
    )
    dependencies = validate_runtime_dependencies(
        load_restricted_yaml(
            config_root / "runtime_dependencies.yaml", label="runtime dependencies"
        )
    )
    require(
        profile.exact_candidate_depth == 1
        and profile.lexical_candidate_depth == 20
        and profile.vector_candidate_depth == 20
        and profile.fused_candidate_depth == 20
        and profile.rrf_constant == 60
        and (profile.exact_weight, profile.lexical_weight, profile.vector_weight)
        == (1, 1, 4)
        and profile.learned_reranker is False,
        "retrieval_profile_changed",
    )

    database_password = os.environ.pop("ISHIKAWA_POSTGRESQL_PASSWORD", "")
    require(
        1 <= len(database_password) <= 4096
        and "\n" not in database_password
        and "\r" not in database_password,
        "database_credential_invalid",
    )
    try:
        connection = psycopg.connect(
            host="127.0.0.1",
            port=arguments.postgresql_port,
            dbname="rag_catalog",
            user="rag_retrieval",
            password=database_password,
            connect_timeout=5,
        )
    except Exception as error:
        raise LiveMeasurementError("isolated_postgresql_connection_failed") from error
    finally:
        database_password = ""

    embed_query = NativeQueryEmbeddingAdapter(
        dependencies.embedding_endpoint,
        ProtectedEnvironmentValue(
            dependencies.embedding_credential_environment, os.environ
        ),
    )
    results: list[dict[str, Any]] = []
    lane_totals = {"exact": 0, "lexical": 0, "vector": 0, "fused": 0}
    query_tokens = 0
    try:
        connection.execute("BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
        boundary = connection.execute(
            """SELECT current_user, current_database(),
                      current_setting('transaction_read_only'),
                      current_setting('transaction_isolation')"""
        ).fetchone()
        require(
            boundary == ("rag_retrieval", "rag_catalog", "on", "repeatable read"),
            "database_boundary_invalid",
        )
        inventory = connection.execute(
            """SELECT
                 (SELECT count(*) FROM rag_search.active_documents),
                 (SELECT coalesce(sum(page_count), 0) FROM rag_search.active_documents),
                 (SELECT count(*) FROM rag_search.active_chunks),
                 (SELECT count(*) FROM rag_search.active_citations),
                 (SELECT count(*) FROM rag_search.active_embeddings),
                 (SELECT count(*) FROM rag_search.active_chunks
                    WHERE projection_kind = 'document_control_metadata')"""
        ).fetchone()
        require(inventory == (6, 26, 139, 139, 139, 6), "corpus_inventory_invalid")

        rows = connection.execute(
            """SELECT ac.chunk_id, ac.document_id, ac.document_version_id,
                      ac.document_key, ac.artifact_set_id, ac.ordinal,
                      ac.projection_kind, ac.retrieval_text,
                      ac.retrieval_text_digest, ac.retrieval_filters,
                      ac.client_metadata, ci.page_start, ci.page_end
               FROM rag_search.active_chunks ac
               JOIN rag_search.active_citations ci ON ci.chunk_id = ac.chunk_id
               ORDER BY ac.chunk_id"""
        ).fetchall()
        require(len(rows) == 139, "published_candidate_inventory_invalid")
        persisted_by_producer: dict[str, Any] = {}
        seen_published_ids: set[str] = set()
        for row in rows:
            client_metadata = row[10]
            producer_chunk_id = (
                client_metadata.get("producer_chunk_id")
                if isinstance(client_metadata, dict)
                else None
            )
            expected = artifact_by_chunk.get(producer_chunk_id)
            expected_contract = expected_chunk_contracts.get(producer_chunk_id)
            require(expected is not None, "published_chunk_identity_mismatch")
            require(
                isinstance(expected_contract, dict),
                "published_chunk_contract_missing",
            )
            expected_document_key = ref_to_key[expected.document_ref]
            expected_document = next(
                document
                for document in chunks["documents"]
                if document["document_ref"] == expected_document_key
            )
            expected_document_id = base.domain_digest(
                "ishikawa.document.v1", {"document_key": expected_document_key}
            )
            expected_document_version_id = base.domain_digest(
                "ishikawa.document-version.v1",
                {
                    "document_id": expected_document_id,
                    "source_digest": expected_document["source_sha256"],
                },
            )
            expected_artifact_retrieval_digest = base.domain_digest(
                "ishikawa.retrieval-text.v1",
                {"retrieval_text": expected.retrieval_text},
            )
            expected_published_retrieval_digest = base.domain_digest(
                "ishikawa.retrieval-text.v1", expected.retrieval_text
            )
            expected_published_chunk_id = base.domain_digest(
                "ishikawa.chunk.v1",
                {
                    "artifact_set_id": row[4],
                    "ordinal": expected.ordinal,
                    "digest": expected_published_retrieval_digest,
                },
            )
            control = row[9].get("document_control") if isinstance(row[9], dict) else None
            require(
                expected_contract.get("retrieval_text_digest")
                == expected_artifact_retrieval_digest
                and row[0] == expected_published_chunk_id
                and row[0] not in seen_published_ids
                and row[1] == expected_document_id
                and row[2] == expected_document_version_id
                and row[3] == expected_document_key
                and isinstance(row[4], str)
                and len(row[4]) == 64
                and all(character in "0123456789abcdef" for character in row[4])
                and row[5] == expected.ordinal
                and row[6] == expected.projection_kind
                and row[7] == expected.retrieval_text
                and row[8] == expected_published_retrieval_digest
                and row[9] == expected_contract.get("retrieval_filters")
                and isinstance(control, dict)
                and control.get("department_normalized") == expected.department_normalized
                and row[11] == expected.page_start
                and row[12] == expected.page_end,
                "published_chunk_projection_mismatch",
            )
            seen_published_ids.add(row[0])
            require(
                producer_chunk_id not in persisted_by_producer,
                "published_producer_identity_duplicate",
            )
            persisted_by_producer[producer_chunk_id] = replace(
                expected,
                chunk_id=row[0],
                document_id=row[1],
                document_version_id=row[2],
                document_ref=key_to_ref[row[3]],
                ordinal=row[5],
            )
        require(
            set(persisted_by_producer) == set(artifact_by_chunk),
            "published_producer_identity_coverage_mismatch",
        )
        candidates = tuple(
            persisted_by_producer[item.chunk_id] for item in artifact_candidates
        )
        by_chunk = {item.chunk_id: item for item in candidates}

        for case in cases:
            embedding = embed_query(case.question)
            require(
                embedding.embedding_space_id == ACCEPTED_EMBEDDING_SPACE_ID,
                "embedding_space_changed",
            )
            query_tokens += embedding.prompt_tokens
            permitted = base.permitted_candidates(case, candidates)
            permitted_refs = {item.document_ref for item in permitted}
            filters = CandidateFilters(
                document_keys=(
                    ()
                    if len(permitted_refs) == len(ref_to_key)
                    else tuple(sorted(ref_to_key[item] for item in permitted_refs))
                )
            )
            exact = tuple(
                replace(item, document_key=ref_to_key[item.document_key])
                for item in base.exact_lane(case, permitted, LaneCandidate)
            )
            lexical = lexical_search(
                connection,
                case.question,
                depth=profile.lexical_candidate_depth,
                text_search_config=profile.lexical_search_config,
                filters=filters,
            )
            vector = vector_search(
                connection,
                embedding.vector,
                embedding.embedding_space_id,
                depth=profile.vector_candidate_depth,
                filters=filters,
            )
            fused = reciprocal_rank_fusion(
                {"exact": exact, "lexical": lexical, "vector": vector},
                rrf_constant=profile.rrf_constant,
                lane_weights={"exact": 1, "lexical": 1, "vector": 4},
            )[: profile.fused_candidate_depth]
            result = base.measure_case(
                case, exact, lexical, vector, fused, permitted, by_chunk
            )
            results.append(result)
            lane_totals["exact"] += len(exact)
            lane_totals["lexical"] += len(lexical)
            lane_totals["vector"] += len(vector)
            lane_totals["fused"] += len(fused)
        connection.execute("ROLLBACK")
    finally:
        connection.close()

    body_metrics = base.aggregate(results[: base.BODY_CASE_COUNT])
    header_metrics = base.aggregate(results[base.BODY_CASE_COUNT :])
    require(
        header_metrics["mrr_at_20"] == "1.000000"
        and header_metrics["relevant_at_5"] == 8
        and header_metrics["relevant_at_20"] == 8
        and header_metrics["required_evidence_matched_at_20"] == 11
        and header_metrics["required_evidence_total"] == 11,
        "published_header_gate_not_reproduced",
    )
    baseline_reproduced = (
        body_metrics["mrr_at_20"] == "0.811825"
        and body_metrics["relevant_at_5"] == 54
        and body_metrics["relevant_at_20"] == 57
    )

    artifact = {
        "artifact_kind": "ishikawa_live_synthetic_corpus_v2_retrieval_observation",
        "schema_version": 1,
        "body_case_set_sha256": arguments.expected_body_cases_sha256,
        "header_case_set_sha256": arguments.expected_header_cases_sha256,
        "published_chunks_sha256": arguments.expected_chunks_sha256,
        "retrieval_profile_id": profile.digest,
        "retrieval_profile": profile.observation_contract(),
        "database_boundary": "isolated_postgresql_repeatable_read_read_only",
        "postgresql_port": arguments.postgresql_port,
        "corpus_inventory": {
            "documents": 6,
            "pages": 26,
            "chunks": 139,
            "citations": 139,
            "embeddings": 139,
            "metadata_candidates": 6,
        },
        "query_embedding_count": len(cases),
        "query_embedding_tokens": query_tokens,
        "lane_candidate_totals": lane_totals,
        "body_metrics": body_metrics,
        "header_metrics": header_metrics,
        "preingestion_atomic_baseline": {
            "expected_mrr_at_20": "0.811825",
            "expected_relevant_at_5": 54,
            "expected_relevant_at_20": 57,
            "exactly_reproduced": baseline_reproduced,
        },
        "optimization_gate_used": False,
        "database_write": False,
        "gemma_contact": False,
        "question_text_retained": False,
        "query_vectors_retained": False,
        "source_text_retained": False,
        "cases": results,
    }
    artifact["observation_set_id"] = base.domain_digest(
        "ishikawa.live-synthetic-corpus-v2-retrieval-observation.v1", artifact
    )
    payload = base.canonical_json_bytes(artifact) + b"\n"
    output = Path(arguments.output)
    base.write_exclusive(output, payload)
    print("purpose=measure_published_synthetic_corpus_v2_retrieval")
    print("case_count=68;body_cases=60;header_cases=8;query_embeddings=68")
    print(
        f"body_mrr_at_20={body_metrics['mrr_at_20']};"
        f"body_relevant_at_5={body_metrics['relevant_at_5']}/60;"
        f"body_relevant_at_20={body_metrics['relevant_at_20']}/60"
    )
    print(
        f"header_mrr_at_20={header_metrics['mrr_at_20']};"
        f"header_relevant_at_5={header_metrics['relevant_at_5']}/8;"
        f"header_required_evidence_at_20="
        f"{header_metrics['required_evidence_matched_at_20']}/11"
    )
    print(
        f"preingestion_baseline_reproduced={str(baseline_reproduced).lower()};"
        "preingestion_baseline_comparison_recorded=true;database_write=false;"
        "gemma_contact=false;optimization_gate_used=false"
    )
    print(
        f"observation_set_id={artifact['observation_set_id']};"
        f"artifact_sha256={hashlib.sha256(payload).hexdigest()};"
        f"artifact_bytes={len(payload)}"
    )
    print("live_synthetic_corpus_v2_retrieval_measurement=pass")
    return 0


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--scripts-root")
    parser.add_argument("--python-root")
    parser.add_argument("--config-root")
    parser.add_argument("--chunks")
    parser.add_argument("--expected-chunks-sha256")
    parser.add_argument("--body-cases")
    parser.add_argument("--expected-body-cases-sha256")
    parser.add_argument("--header-cases")
    parser.add_argument("--expected-header-cases-sha256")
    parser.add_argument("--postgresql-port", type=int, default=5433)
    parser.add_argument("--output")
    arguments = parser.parse_args()
    if arguments.self_test == arguments.run:
        raise LiveMeasurementError("mode_invalid")
    required = (
        arguments.scripts_root,
        arguments.python_root,
        arguments.config_root,
        arguments.chunks,
        arguments.expected_chunks_sha256,
        arguments.body_cases,
        arguments.expected_body_cases_sha256,
        arguments.header_cases,
        arguments.expected_header_cases_sha256,
        arguments.output,
    )
    if arguments.run and not all(required):
        raise LiveMeasurementError("argument_missing")
    require(1024 <= arguments.postgresql_port <= 65535, "postgresql_port_invalid")
    return arguments


def main() -> int:
    try:
        arguments = parse_arguments()
        return self_test() if arguments.self_test else execute(arguments)
    except LiveMeasurementError as error:
        print(
            f"live_synthetic_corpus_v2_retrieval_measurement=blocked;reason={error}",
            file=sys.stderr,
        )
        return 1
    except KeyboardInterrupt:
        print(
            "live_synthetic_corpus_v2_retrieval_measurement=blocked;reason=interrupted",
            file=sys.stderr,
        )
        return 130
    except Exception as error:
        print(
            "live_synthetic_corpus_v2_retrieval_measurement=blocked;"
            f"reason=bounded_{type(error).__name__}",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
