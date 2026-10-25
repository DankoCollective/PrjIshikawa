#!/usr/bin/env python3
"""Replay one synthetic incident query through Ishikawa's retrieval gate.

The private artifact contains synthetic query terms, ranked stable document and
chunk identities, and deterministic gate observations. It never contains
credentials, embedding vectors, document text, or model response bodies.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from dataclasses import replace
from pathlib import Path
from typing import Any, Mapping, Sequence


QUESTION = "There has been an incident concerning controlled materials. What do i need to do?"
CONTROLLED_MATERIALS_KEY = "policy.ops-17-control-2001"
INCIDENT_PROCEDURE_KEY = "procedure.incident-reporting"
EXPECTED_INVENTORY = (6, 27, 126, 126, 126)


class DiagnosticError(RuntimeError):
    """Stable diagnostic failure without credential or source-text content."""


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise DiagnosticError(reason)


def stable_identity(label: str) -> str:
    return hashlib.sha256(f"ishikawa-v1.3-retrieval-trace:{label}".encode()).hexdigest()


def score(value: float) -> str:
    return format(value, ".17g")


def load_candidate_metadata(
    connection: Any, chunk_ids: Sequence[str]
) -> dict[str, dict[str, Any]]:
    identities = tuple(dict.fromkeys(chunk_ids))
    if not identities:
        return {}
    rows = connection.execute(
        """/* ishikawa.answer-quality-trace.candidate-metadata */
        SELECT ac.chunk_id, ac.document_id, ac.document_version_id,
               ac.document_key, ac.display_name, ac.class_id, ad.page_count,
               ac.projection_kind, ac.ordinal, ci.page_start, ci.page_end,
               ci.structural_path
        FROM rag_search.active_chunks ac
        JOIN rag_search.active_documents ad
          ON ad.document_version_id = ac.document_version_id
        JOIN rag_search.active_citations ci ON ci.chunk_id = ac.chunk_id
        WHERE ac.chunk_id = ANY(%s::text[])
        ORDER BY ac.chunk_id, ci.page_start, ci.page_end, ci.citation_id
        """,
        (list(identities),),
    ).fetchall()
    grouped: dict[str, dict[str, Any]] = {}
    for row in rows:
        require(
            isinstance(row, Sequence)
            and not isinstance(row, (str, bytes))
            and len(row) == 12,
            "candidate_metadata_invalid",
        )
        (
            chunk_id,
            document_id,
            document_version_id,
            document_key,
            display_name,
            document_class,
            page_count,
            projection_kind,
            ordinal,
            page_start,
            page_end,
            structural_path,
        ) = row
        require(
            all(
                isinstance(value, str) and value
                for value in (
                    chunk_id,
                    document_id,
                    document_version_id,
                    document_key,
                    display_name,
                    document_class,
                    projection_kind,
                )
            )
            and type(page_count) is int
            and page_count > 0
            and type(ordinal) is int
            and ordinal >= 0
            and type(page_start) is int
            and type(page_end) is int
            and 1 <= page_start <= page_end <= page_count
            and isinstance(structural_path, list)
            and all(isinstance(item, str) and item for item in structural_path),
            "candidate_metadata_invalid",
        )
        immutable = {
            "chunk_id": chunk_id,
            "document_id": document_id,
            "document_version_id": document_version_id,
            "document_key": document_key,
            "display_name": display_name,
            "document_class": document_class,
            "page_count": page_count,
            "projection_kind": projection_kind,
            "ordinal": ordinal,
        }
        record = grouped.setdefault(
            chunk_id,
            {**immutable, "pages": [], "structural_paths": []},
        )
        require(
            all(record[key] == value for key, value in immutable.items()),
            "candidate_metadata_conflict",
        )
        page_range = [page_start, page_end]
        path = list(structural_path)
        if page_range not in record["pages"]:
            record["pages"].append(page_range)
        if path not in record["structural_paths"]:
            record["structural_paths"].append(path)
    require(set(grouped) == set(identities), "candidate_metadata_incomplete")
    return grouped


def lane_record(candidate: Any, metadata: Mapping[str, Mapping[str, Any]]) -> dict[str, Any]:
    item = metadata[candidate.chunk_id]
    return {
        **item,
        "rank": candidate.rank,
        "raw_score": score(candidate.raw_score),
        "exact_reason": candidate.exact_reason,
        "retrieval_variant": candidate.retrieval_variant,
    }


def fused_record(
    rank: int, candidate: Any, metadata: Mapping[str, Mapping[str, Any]]
) -> dict[str, Any]:
    item = metadata[candidate.chunk_id]
    return {
        **item,
        "rank": rank,
        "fused_score": score(candidate.fused_score),
        "exact_priority": candidate.exact_priority,
        "lane_evidence": [
            {
                "lane": evidence.lane,
                "rank": evidence.rank,
                "raw_score": score(evidence.raw_score),
                "exact_reason": evidence.exact_reason,
                "retrieval_variant": evidence.retrieval_variant,
            }
            for evidence in candidate.evidence
        ],
    }


def first_document_rank(
    records: Sequence[Mapping[str, Any]], document_key: str
) -> int | None:
    return next(
        (item["rank"] for item in records if item["document_key"] == document_key),
        None,
    )


def document_positions(
    records: Sequence[Mapping[str, Any]], document_key: str
) -> dict[str, Any]:
    selected = [item for item in records if item["document_key"] == document_key]
    return {
        "document_key": document_key,
        "first_rank": first_document_rank(records, document_key),
        "result_count": len(selected),
        "ranks": [item["rank"] for item in selected],
        "pages": list(
            dict.fromkeys(
                tuple(page)
                for item in selected
                for page in item["pages"]
            )
        ),
    }


def measure_lexemes(
    connection: Any, question: str, chunk_ids: Sequence[str]
) -> dict[str, Any]:
    question_row = connection.execute(
        """/* ishikawa.answer-quality-trace.question-lexemes */
        SELECT tsvector_to_array(to_tsvector('english'::regconfig, %s))
        """,
        (question,),
    ).fetchone()
    require(
        question_row is not None and isinstance(question_row[0], list),
        "question_lexeme_measurement_failed",
    )
    question_lexemes = tuple(sorted(set(question_row[0])))
    evidence_lexemes: set[str] = set()
    if chunk_ids:
        rows = connection.execute(
            """/* ishikawa.answer-quality-trace.evidence-lexemes */
            SELECT
              ac.chunk_id,
              tsvector_to_array(
                ac.lexical_vector
                || to_tsvector(
                     'english'::regconfig,
                     concat_ws(
                       ' ',
                       ac.display_name,
                       translate(ac.class_id, '_.-', '   '),
                       (
                         SELECT string_agg(path.value, ' ' ORDER BY path.ordinality)
                         FROM jsonb_array_elements_text(ci.structural_path)
                           WITH ORDINALITY AS path(value, ordinality)
                       ),
                       'page ' || ci.page_start::text,
                       CASE
                         WHEN ci.page_end <> ci.page_start
                           THEN 'page ' || ci.page_end::text
                         ELSE NULL
                       END
                     )
                   )
              )
            FROM rag_search.active_chunks ac
            JOIN rag_search.active_citations ci ON ci.chunk_id = ac.chunk_id
            WHERE ac.chunk_id = ANY(%s::text[])
            ORDER BY ac.chunk_id, ci.citation_id
            """,
            (list(chunk_ids),),
        ).fetchall()
        require(
            {row[0] for row in rows} == set(chunk_ids),
            "evidence_lexeme_identity_mismatch",
        )
        for _chunk_id, lexemes in rows:
            require(isinstance(lexemes, list), "evidence_lexeme_measurement_failed")
            evidence_lexemes.update(lexemes)
    supported = tuple(sorted(set(question_lexemes) & evidence_lexemes))
    unsupported = tuple(sorted(set(question_lexemes) - evidence_lexemes))
    return {
        "question": list(question_lexemes),
        "supported": list(supported),
        "unsupported": list(unsupported),
        "supported_count": len(supported),
        "question_count": len(question_lexemes),
        "support_fraction": f"{len(supported)}/{len(question_lexemes)}",
    }


def relationship_record(
    candidate: Any, metadata: Mapping[str, Mapping[str, Any]]
) -> dict[str, Any]:
    item = metadata[candidate.chunk_id]
    return {
        **item,
        "retrieval_rank": candidate.retrieval_rank,
        "origin": candidate.origin,
        "inclusion_reason": candidate.inclusion_reason,
        "relationship_provenance": list(candidate.relationship_provenance),
    }


def self_test() -> int:
    records = (
        {"document_key": INCIDENT_PROCEDURE_KEY, "rank": 1, "pages": [[1, 1]]},
        {"document_key": CONTROLLED_MATERIALS_KEY, "rank": 4, "pages": [[1, 1]]},
        {"document_key": CONTROLLED_MATERIALS_KEY, "rank": 9, "pages": [[3, 3]]},
    )
    summary = document_positions(records, CONTROLLED_MATERIALS_KEY)
    require(
        summary["first_rank"] == 4
        and summary["result_count"] == 2
        and summary["ranks"] == [4, 9]
        and summary["pages"] == [(1, 1), (3, 3)],
        "self_test_document_positions_failed",
    )
    require(len(stable_identity("conversation")) == 64, "self_test_identity_failed")
    print("incident_retrieval_quality_trace_self_test=pass")
    return 0


def run(arguments: argparse.Namespace) -> int:
    python_root = Path(arguments.python_root).resolve(strict=True)
    config_root = Path(arguments.config_root).resolve(strict=True)
    output_path = Path(arguments.output)
    require(
        python_root.is_dir()
        and config_root.is_dir()
        and output_path.is_absolute()
        and not output_path.exists()
        and not output_path.is_symlink(),
        "runtime_path_invalid",
    )
    sys.path.insert(0, str(python_root))

    from ishikawa.api_contract import REQUEST_SCHEMA, parse_chat_request
    from ishikawa.canonical import canonical_json_bytes, domain_digest
    from ishikawa.postgres_retrieval import (
        NativePostgresRetrievalAdapter,
        _load_relationship_candidates,
        _merge_exact_candidates,
    )
    from ishikawa.relevance import measure_citable_evidence_relevance
    from ishikawa.retrieval import (
        CandidateFilters,
        exact_document_page_lookup,
        exact_lookup,
        exact_term_lookup,
        extract_explicit_page,
        extract_structured_terms,
        lexical_search,
        reciprocal_rank_fusion,
        vector_search,
    )
    from ishikawa.runtime import assemble_configured_retrieval_runtime

    runtime = assemble_configured_retrieval_runtime(config_root, environment=os.environ)
    request = parse_chat_request(
        {
            "schema": REQUEST_SCHEMA,
            "conversation_id": stable_identity("conversation"),
            "turn_id": stable_identity("turn"),
            "message": QUESTION,
            "history": [],
            "source_references": [],
            "filters": {"document_classes": [], "document_keys": []},
        },
        runtime.policies.api,
    )
    resolution = runtime.ports.resolve_query(request)
    require(
        resolution.status == "resolved"
        and resolution.resolved_query == QUESTION
        and not resolution.source_constraints
        and resolution.used_model is False,
        "query_resolution_not_deterministic",
    )
    adapter = runtime.ports.retrieve_evidence
    require(
        isinstance(adapter, NativePostgresRetrievalAdapter),
        "retrieval_adapter_unexpected",
    )
    embeddings: list[Any] = []

    def capture_embedding(query: str) -> Any:
        embedding = adapter.query_embedder(query)
        embeddings.append(embedding)
        return embedding

    replay_adapter = replace(adapter, query_embedder=capture_embedding)
    replay = replay_adapter(request, resolution)
    require(len(embeddings) == 1, "embedding_call_count_invalid")
    embedding = embeddings[0]

    version_ids = tuple(item.source_id for item in resolution.source_constraints)
    filters = CandidateFilters(
        document_classes=request.filters.document_classes,
        document_keys=request.filters.document_keys,
        document_version_ids=version_ids,
    )
    connection = adapter.connection_factory()
    try:
        connection.execute(
            "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY"
        )
        boundary = connection.execute(
            """/* ishikawa.answer-quality-trace.boundary */
            SELECT current_user, current_database(),
                   current_setting('transaction_read_only'),
                   current_setting('transaction_isolation')
            """
        ).fetchone()
        require(
            boundary == ("rag_retrieval", "rag_catalog", "on", "repeatable read"),
            "database_boundary_invalid",
        )
        inventory = connection.execute(
            """/* ishikawa.answer-quality-trace.inventory */
            SELECT
              (SELECT count(*) FROM rag_search.active_documents),
              (SELECT coalesce(sum(page_count), 0) FROM rag_search.active_documents),
              (SELECT count(*) FROM rag_search.active_chunks),
              (SELECT count(*) FROM rag_search.active_citations),
              (SELECT count(*) FROM rag_search.active_embeddings)
            """
        ).fetchone()
        require(inventory == EXPECTED_INVENTORY, "corpus_inventory_invalid")

        exact_items: list[Any] = []
        for source in resolution.source_constraints:
            exact_items.extend(
                exact_lookup(
                    connection,
                    "citation_id" if source.citation_id is not None else "document_version_id",
                    source.citation_id or source.source_id,
                    depth=adapter.retrieval_policy.exact_candidate_depth,
                    filters=filters,
                )
            )
        terms = extract_structured_terms(resolution.resolved_query)
        explicit_page = extract_explicit_page(resolution.resolved_query)
        page_routed = False
        if explicit_page is not None and len(terms) == 1:
            page_matches = exact_document_page_lookup(
                connection,
                terms[0],
                explicit_page,
                depth=adapter.retrieval_policy.exact_candidate_depth,
                filters=filters,
            )
            exact_items.extend(page_matches)
            page_routed = bool(page_matches)
        if not page_routed:
            for term in terms:
                exact_items.extend(
                    exact_term_lookup(
                        connection,
                        term,
                        depth=adapter.retrieval_policy.exact_candidate_depth,
                        filters=filters,
                    )
                )
        exact = _merge_exact_candidates(exact_items)
        lexical = lexical_search(
            connection,
            resolution.resolved_query,
            depth=adapter.retrieval_policy.lexical_candidate_depth,
            text_search_config=adapter.retrieval_policy.lexical_search_config,
            filters=filters,
        )
        vector = vector_search(
            connection,
            embedding.vector,
            embedding.embedding_space_id,
            depth=adapter.retrieval_policy.vector_candidate_depth,
            filters=filters,
        )
        fused = reciprocal_rank_fusion(
            {"exact": exact, "lexical": lexical, "vector": vector},
            rrf_constant=adapter.retrieval_policy.rrf_constant,
            lane_weights={
                "exact": adapter.retrieval_policy.exact_weight,
                "lexical": adapter.retrieval_policy.lexical_weight,
                "vector": adapter.retrieval_policy.vector_weight,
            },
        )[: adapter.retrieval_policy.fused_candidate_depth]
        relationship_candidates, _relationship_metadata, relationship_required, relationship_covered = (
            _load_relationship_candidates(
                connection,
                direct_fused=fused,
                query=resolution.resolved_query,
                query_embedding=embedding,
                filters=filters,
                retrieval_policy=adapter.retrieval_policy,
                relationship_registry=adapter.relationship_registry,
            )
        )
        all_ids = [
            item.chunk_id
            for lane in (exact, lexical, vector, fused, relationship_candidates)
            for item in lane
        ]
        metadata = load_candidate_metadata(connection, all_ids)
        lane_records = {
            "exact": [lane_record(item, metadata) for item in exact],
            "lexical": [lane_record(item, metadata) for item in lexical],
            "vector": [lane_record(item, metadata) for item in vector],
        }
        fused_records = [
            fused_record(rank, item, metadata)
            for rank, item in enumerate(fused, start=1)
        ]
        relation_records = [
            relationship_record(item, metadata) for item in relationship_candidates
        ]
        relevance = measure_citable_evidence_relevance(
            connection,
            resolution.resolved_query,
            fused,
            adapter.relevance_policy,
        )
        lexemes = measure_lexemes(
            connection,
            resolution.resolved_query,
            [item.chunk_id for item in fused[: adapter.relevance_policy.fused_depth]],
        )
        require(
            lexemes["supported_count"] == relevance.supported_count
            and lexemes["question_count"] == relevance.question_lexeme_count,
            "relevance_replay_mismatch",
        )
        connection.execute("ROLLBACK")
    finally:
        connection.close()

    telemetry = replay.telemetry
    require(telemetry is not None, "retrieval_telemetry_absent")
    reason = replay.sufficiency.reason_code
    relevance_only_block = reason == "RELEVANCE_INSUFFICIENT"
    controlled_positions = {
        lane: document_positions(records, CONTROLLED_MATERIALS_KEY)
        for lane, records in {**lane_records, "fused": fused_records}.items()
    }
    incident_positions = {
        lane: document_positions(records, INCIDENT_PROCEDURE_KEY)
        for lane, records in {**lane_records, "fused": fused_records}.items()
    }
    artifact: dict[str, Any] = {
        "artifact_kind": "ishikawa_v1_3_incident_retrieval_quality_trace",
        "schema_version": 1,
        "synthetic_content_only": True,
        "question": QUESTION,
        "question_sha256": hashlib.sha256(QUESTION.encode()).hexdigest(),
        "query_resolution": {
            "status": resolution.status,
            "resolved_query": resolution.resolved_query,
            "used_model": resolution.used_model,
            "structured_terms": list(terms),
            "explicit_page": explicit_page,
            "source_constraint_count": len(resolution.source_constraints),
        },
        "profiles": {
            "runtime": runtime.policies.digest,
            "retrieval": adapter.retrieval_policy.digest,
            "relevance": adapter.relevance_policy.digest,
            "sufficiency": adapter.sufficiency_policy.digest,
            "relationships": adapter.relationship_registry.digest,
        },
        "database_boundary": "repeatable_read_read_only",
        "corpus_inventory": dict(
            zip(("documents", "pages", "chunks", "citations", "embeddings"), EXPECTED_INVENTORY)
        ),
        "embedding": {
            "request_identity": embedding.request_identity,
            "space_identity": embedding.embedding_space_id,
            "prompt_tokens": embedding.prompt_tokens,
            "vector_retained": False,
        },
        "lanes": lane_records,
        "fused": fused_records,
        "relationship_expansion": {
            "required": relationship_required,
            "covered": relationship_covered,
            "candidates": relation_records,
        },
        "relevance": {
            "status": relevance.status,
            "reason_code": relevance.reason_code,
            "profile_identity": relevance.profile_identity,
            "fused_depth": relevance.fused_depth,
            "measured_chunks": relevance.fused_chunk_count,
            "lexemes": lexemes,
            "accepted_threshold": "supported_count * 5 >= question_count * 3",
        },
        "sufficiency": {
            "status": replay.sufficiency.status,
            "reason_code": reason,
            "policy_identity": replay.sufficiency.policy_identity,
            "evidence_passages": replay.sufficiency.evidence_passages,
            "citation_count": replay.sufficiency.citation_count,
            "relevance_profile_identity": replay.sufficiency.relevance_profile_identity,
            "would_reach_generation_if_only_relevance_gate_relaxed": relevance_only_block,
            "counterfactual_does_not_prove_answer_quality": True,
        },
        "telemetry": {
            "lane_states": [list(item) for item in telemetry.lane_states],
            "fused_candidate_count": telemetry.fused_candidate_count,
            "authorized_candidate_count": telemetry.authorized_candidate_count,
            "reconstructed_unit_count": telemetry.reconstructed_unit_count,
            "citation_count": telemetry.citation_count,
            "context_tokens_used": telemetry.context_tokens_used,
            "context_token_limit": telemetry.context_token_limit,
            "nomic_query_tokens": telemetry.nomic_query_tokens,
        },
        "target_documents": {
            "controlled_materials_policy": controlled_positions,
            "incident_notification_procedure": incident_positions,
        },
        "contacts": {
            "database_read_only": True,
            "nomic_query_embedding": True,
            "gemma_tokenizer": True,
            "gemma_scope": False,
            "gemma_query_resolution": False,
            "gemma_answer_generation": False,
        },
        "retention": {
            "credentials": False,
            "embedding_vectors": False,
            "document_text": False,
            "model_response_bodies": False,
        },
    }
    artifact["observation_identity"] = domain_digest(
        "ishikawa.v1.3.incident-retrieval-quality-trace.v1", artifact
    )
    payload = canonical_json_bytes(artifact) + b"\n"
    descriptor = os.open(output_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)

    print("purpose=trace_v1_3_incident_retrieval_quality")
    print(
        f"sufficiency_status={replay.sufficiency.status};sufficiency_reason={reason};"
        f"relevance_status={relevance.status}"
    )
    print(
        f"relevance_support={relevance.supported_count}/{relevance.question_lexeme_count};"
        f"controlled_materials_fused_first_rank={controlled_positions['fused']['first_rank']};"
        f"incident_procedure_fused_first_rank={incident_positions['fused']['first_rank']}"
    )
    print(
        f"relaxing_only_relevance_gate_would_reach_generation={str(relevance_only_block).lower()};"
        "answer_quality_proven=false"
    )
    print(
        f"observation_identity={artifact['observation_identity']};"
        f"artifact_sha256={hashlib.sha256(payload).hexdigest()};artifact_bytes={len(payload)}"
    )
    print("incident_retrieval_quality_trace=pass")
    return 0


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--python-root")
    parser.add_argument("--config-root")
    parser.add_argument("--output")
    arguments = parser.parse_args()
    if arguments.self_test == arguments.run:
        raise DiagnosticError("mode_invalid")
    if arguments.run and not all(
        (arguments.python_root, arguments.config_root, arguments.output)
    ):
        raise DiagnosticError("argument_missing")
    return arguments


def main() -> int:
    try:
        arguments = parse_arguments()
        return self_test() if arguments.self_test else run(arguments)
    except DiagnosticError as error:
        print(
            f"incident_retrieval_quality_trace=blocked;reason={error}",
            file=sys.stderr,
        )
        return 1
    except Exception:
        print(
            "incident_retrieval_quality_trace=blocked;reason=unexpected_failure",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
