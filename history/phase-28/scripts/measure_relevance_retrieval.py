#!/usr/bin/env python3
"""Measure relevance-calibration retrieval signals in a disposable database."""

from __future__ import annotations

import hashlib
import json
import os
import sys
from pathlib import Path
from typing import Any

import psycopg

from ishikawa.artifact_adapter import load_prepared_documents
from ishikawa.canonical import canonical_json_bytes
from ishikawa.persistence import write_incremental_plan
from ishikawa.planner import plan_ingestion
from ishikawa.retrieval import (
    LaneCandidate,
    exact_document_page_lookup,
    exact_term_lookup,
    extract_explicit_page,
    extract_structured_terms,
    lexical_search,
    reciprocal_rank_fusion,
    vector_search,
)
from ishikawa.validators import (
    validate_class_registry,
    validate_document_catalog,
    validate_ingestion_manifest,
)
from ishikawa.yaml_loader import load_restricted_yaml


METHOD_PROFILE_ID = "5797961aee919aa73bbd99d6cc188084d57d22839a1d4cff0febc2e73e17b4b0"
RETRIEVAL_PROFILE_ID = "33102734a29ea8170cffcfa7cdff6feae66d4663d09d7bca86c04a6419f77ad7"
EMBEDDING_SPACE_ID = "fd970d304662357a07f7712639bdc0c70cc7e72b22f04c126acce57a6f9143a3"
EXACT_DEPTH = 20
LEXICAL_DEPTH = 20
VECTOR_DEPTH = 20
FUSED_DEPTH = 20
RRF_CONSTANT = 60
EXPECTED_CASES = 12
LEXEME_SUPPORT_DEPTHS = (1, 3, 5, 10, 20)


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise RuntimeError(reason)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_json(path: Path, maximum_bytes: int) -> Any:
    require(path.is_file() and not path.is_symlink(), "unsafe JSON input")
    require(path.stat().st_size <= maximum_bytes, "oversized JSON input")
    return json.loads(path.read_text(encoding="utf-8"))


def scalar(connection: psycopg.Connection, query: str, parameters=()):
    row = connection.execute(query, parameters).fetchone()
    require(row is not None, "required query returned no row")
    return row[0]


def question_lexemes(
    connection: psycopg.Connection, question: str
) -> tuple[str, ...]:
    """Return PostgreSQL's deterministic English lexemes for one question."""

    row = connection.execute(
        """/* ishikawa.relevance.question-lexemes */
        SELECT tsvector_to_array(to_tsvector('english'::regconfig, %s))
        """,
        (question,),
    ).fetchone()
    require(row is not None and isinstance(row[0], list), "question lexeme query failed")
    lexemes = tuple(sorted(set(row[0])))
    require(lexemes and all(isinstance(item, str) and item for item in lexemes),
            "question lexeme inventory is invalid")
    return lexemes


def evidence_lexemes(
    connection: psycopg.Connection, chunk_ids: tuple[str, ...]
) -> tuple[str, ...]:
    """Return the union of stored English lexemes for selected active chunks."""

    if not chunk_ids:
        return ()
    rows = connection.execute(
        """/* ishikawa.relevance.evidence-lexemes */
        SELECT chunk_id, tsvector_to_array(lexical_vector)
        FROM rag_search.active_chunks
        WHERE chunk_id = ANY(%s::text[])
        ORDER BY chunk_id
        """,
        (list(chunk_ids),),
    ).fetchall()
    require(len(rows) == len(set(chunk_ids)), "fused evidence lexeme inventory mismatch")
    observed_ids = {row[0] for row in rows}
    require(observed_ids == set(chunk_ids), "fused evidence chunk identity mismatch")
    combined: set[str] = set()
    for _, values in rows:
        require(isinstance(values, list), "evidence lexeme query failed")
        require(all(isinstance(item, str) and item for item in values),
                "evidence lexeme inventory is invalid")
        combined.update(values)
    return tuple(sorted(combined))


def citable_evidence_lexemes(
    connection: psycopg.Connection, chunk_ids: tuple[str, ...]
) -> tuple[str, ...]:
    """Return lexemes from text plus the frozen citable evidence envelope."""

    if not chunk_ids:
        return ()
    rows = connection.execute(
        """/* ishikawa.relevance.citable-evidence-lexemes */
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
                     WHEN ci.page_end <> ci.page_start THEN 'page ' || ci.page_end::text
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
    observed_ids = {row[0] for row in rows}
    require(observed_ids == set(chunk_ids), "citable evidence identity mismatch")
    combined: set[str] = set()
    for _, values in rows:
        require(isinstance(values, list), "citable evidence lexeme query failed")
        require(
            all(isinstance(item, str) and item for item in values),
            "citable evidence lexeme inventory is invalid",
        )
        combined.update(values)
    return tuple(sorted(combined))


def build_support_measurement(
    query_lexemes: tuple[str, ...],
    fused: tuple[Any, ...],
    lexeme_loader: Any,
) -> dict[str, Any]:
    """Build one cumulative support measurement over unchanged fused ranks."""

    query_set = set(query_lexemes)
    measurements: list[dict[str, Any]] = []
    for depth in LEXEME_SUPPORT_DEPTHS:
        selected_ids = tuple(item.chunk_id for item in fused[:depth])
        selected_lexemes = set(lexeme_loader(selected_ids))
        supported = sorted(query_set & selected_lexemes)
        unsupported = sorted(query_set - selected_lexemes)
        measurements.append(
            {
                "depth": depth,
                "fused_chunk_count": len(selected_ids),
                "supported_lexemes": supported,
                "unsupported_lexemes": unsupported,
                "supported_count": len(supported),
                "unsupported_count": len(unsupported),
            }
        )
    return {
        "question_lexemes": list(query_lexemes),
        "question_lexeme_count": len(query_lexemes),
        "measurements": measurements,
    }


def measure_lexeme_support(
    connection: psycopg.Connection,
    question: str,
    fused: tuple[Any, ...],
) -> dict[str, Any]:
    """Measure question-lexeme coverage without changing retrieval ranking."""

    query_lexemes = question_lexemes(connection, question)
    return build_support_measurement(
        query_lexemes,
        fused,
        lambda selected_ids: evidence_lexemes(connection, selected_ids),
    )


def measure_citable_evidence_support(
    connection: psycopg.Connection,
    question: str,
    fused: tuple[Any, ...],
) -> dict[str, Any]:
    """Measure support using only the frozen citable evidence fields."""

    query_lexemes = question_lexemes(connection, question)
    return build_support_measurement(
        query_lexemes,
        fused,
        lambda selected_ids: citable_evidence_lexemes(connection, selected_ids),
    )


def merge_exact(candidates: list[tuple[int, LaneCandidate]]) -> tuple[LaneCandidate, ...]:
    selected: dict[str, tuple[int, LaneCandidate]] = {}
    for term_index, candidate in candidates:
        ordering = (term_index, candidate.rank, candidate.chunk_id)
        current = selected.get(candidate.chunk_id)
        if current is None or ordering < (current[0], current[1].rank, current[1].chunk_id):
            selected[candidate.chunk_id] = (term_index, candidate)
    ordered = sorted(
        selected.values(), key=lambda item: (item[0], item[1].rank, item[1].chunk_id)
    )
    return tuple(
        LaneCandidate(
            chunk_id=candidate.chunk_id,
            document_id=candidate.document_id,
            document_version_id=candidate.document_version_id,
            document_key=candidate.document_key,
            lane="exact",
            rank=rank,
            raw_score=candidate.raw_score,
            exact_reason=candidate.exact_reason,
        )
        for rank, (_, candidate) in enumerate(ordered[:EXACT_DEPTH], start=1)
    )


def lane_records(
    candidates: tuple[LaneCandidate, ...], database_to_producer: dict[str, str]
) -> list[dict[str, Any]]:
    return [
        {
            "chunk_id": database_to_producer[item.chunk_id],
            "rank": item.rank,
            "raw_score": item.raw_score,
            "exact_reason": item.exact_reason,
            "retrieval_variant": item.retrieval_variant,
        }
        for item in candidates
    ]


def main() -> int:
    if len(sys.argv) != 11 or not sys.argv[1].startswith("ishikawa_retrieval_calibration_test"):
        raise RuntimeError("one safe disposable database and nine payload paths are required")
    database = sys.argv[1]
    config_root = Path(sys.argv[2])
    source_root = Path(sys.argv[3])
    normalized_path = Path(sys.argv[4])
    chunk_path = Path(sys.argv[5])
    document_embedding_path = Path(sys.argv[6])
    identity_path = Path(sys.argv[7])
    query_input_path = Path(sys.argv[8])
    query_embedding_path = Path(sys.argv[9])
    output_path = Path(sys.argv[10])
    identities = dict(
        line.split("  ", 1)[::-1]
        for line in identity_path.read_text(encoding="ascii").splitlines()
        if line
    )
    for path in (
        normalized_path,
        chunk_path,
        document_embedding_path,
        query_input_path,
        query_embedding_path,
    ):
        require(sha256_file(path) == identities[path.name], "payload identity mismatch")

    query_input = load_json(query_input_path, 1024 * 1024)
    query_embeddings = load_json(query_embedding_path, 32 * 1024 * 1024)
    require(
        isinstance(query_input, dict)
        and set(query_input) == {
            "artifact_kind", "cases", "schema_version", "source_case_set_sha256",
            "source_query_embedding_sha256",
        }
        and query_input.get("schema_version") == 1
        and query_input.get("artifact_kind") == "relevance_retrieval_queries"
        and len(query_input.get("cases", [])) == EXPECTED_CASES,
        "query input contract mismatch",
    )
    require(
        isinstance(query_embeddings, dict)
        and query_embeddings.get("artifact_kind")
        == "relevance_retrieval_query_vectors"
        and query_embeddings.get("embedding_space_id") == EMBEDDING_SPACE_ID
        and query_embeddings.get("case_count") == EXPECTED_CASES
        and isinstance(query_embeddings.get("source_query_embedding_sha256"), str)
        and query_embeddings.get("source_query_embedding_sha256")
        == query_input.get("source_query_embedding_sha256")
        and query_embeddings.get("query_method")
        == {
            "schema_version": 1,
            "query_prefix": "search_query: ",
            "embedding_request_batch_size": 1,
        },
        "query embedding contract mismatch",
    )
    embedding_by_case = {
        record["case_id"]: record for record in query_embeddings.get("records", [])
    }
    require(len(embedding_by_case) == EXPECTED_CASES, "query embedding inventory mismatch")
    seen_cases: set[str] = set()
    for case in query_input["cases"]:
        require(
            isinstance(case, dict)
            and set(case) == {"case_id", "question", "question_digest"},
            "query case contract mismatch",
        )
        case_id = case["case_id"]
        require(case_id not in seen_cases, "duplicate query case")
        seen_cases.add(case_id)
        record = embedding_by_case.get(case_id)
        require(record is not None, "query embedding missing")
        require(
            set(record) == {"case_id", "question_digest", "vector", "vector_dimension"},
            "query embedding record contract mismatch",
        )
        require(record.get("question_digest") == case.get("question_digest"), "query digest mismatch")
        require(record.get("vector_dimension") == 768, "query vector dimension mismatch")

    registry = validate_class_registry(
        load_restricted_yaml(config_root / "document_classes.yaml", label="class registry")
    )
    catalog = validate_document_catalog(
        load_restricted_yaml(config_root / "document_catalog.yaml", label="document catalog")
    )
    manifest = validate_ingestion_manifest(
        load_restricted_yaml(config_root / "ingestion_manifest.yaml", label="ingestion manifest")
    )
    prepared = load_prepared_documents(
        normalized_path=normalized_path,
        normalized_sha256=identities[normalized_path.name],
        chunk_path=chunk_path,
        chunk_sha256=identities[chunk_path.name],
        embedding_path=document_embedding_path,
        embedding_sha256=identities[document_embedding_path.name],
        manifest=manifest,
        source_root=source_root,
    )
    require(len(prepared) == 6, "prepared document count mismatch")
    require(sum(len(item.chunks) for item in prepared) == 126, "prepared chunk count mismatch")

    connection_info = f"dbname={database} host=/var/run/postgresql port=5432 user=postgres"
    with psycopg.connect(connection_info, autocommit=True) as connection:
        connection.execute("SET ROLE rag_ingest")
        plan = plan_ingestion(
            registry,
            catalog,
            manifest,
            source_root=source_root,
            method_profile_id=METHOD_PROFILE_ID,
            published_state={},
            prior_catalog_keys=set(),
        )
        require(plan.overall_outcome == "PASS", "initial validation plan failed")
        result = write_incremental_plan(connection, registry, catalog, manifest, plan, prepared)
        require(
            result.outcome == "PUBLISHED" and result.published_document_count == 6,
            "publication failed",
        )
        require(
            scalar(connection, "SELECT count(*) FROM rag_search.active_chunks") == 126,
            "active chunk count mismatch",
        )
        require(
            scalar(connection, "SELECT count(*) FROM rag_search.active_embeddings") == 126,
            "active embedding count mismatch",
        )

    observations: list[dict[str, Any]] = []
    lane_totals = {"exact": 0, "lexical": 0, "vector": 0, "fused": 0}
    with psycopg.connect(connection_info, autocommit=True) as retrieval:
        retrieval.execute("SET ROLE rag_retrieval")
        identity_rows = retrieval.execute(
            """/* ishikawa.relevance.identity-map */
            SELECT chunk_id, client_metadata->>'producer_chunk_id'
            FROM rag_search.active_chunks
            ORDER BY chunk_id
            """
        ).fetchall()
        database_to_producer = dict(identity_rows)
        expected_producer_ids = {
            candidate["chunk_id"]
            for document in load_json(chunk_path, 32 * 1024 * 1024)["documents"]
            for candidate in document["candidates"]
        }
        require(len(database_to_producer) == 126, "active chunk identity map is invalid")
        require(
            set(database_to_producer.values()) == expected_producer_ids,
            "active and producer chunk identities do not align",
        )
        for case in query_input["cases"]:
            case_id = case["case_id"]
            question = case["question"]
            structured_terms = extract_structured_terms(question)
            explicit_page = extract_explicit_page(question)
            exact_parts: list[tuple[int, LaneCandidate]] = []
            if explicit_page is not None and len(structured_terms) == 1:
                exact_parts.extend(
                    (-1, candidate)
                    for candidate in exact_document_page_lookup(
                        retrieval, structured_terms[0], explicit_page, depth=EXACT_DEPTH
                    )
                )
            for term_index, term in enumerate(structured_terms):
                exact_parts.extend(
                    (term_index, candidate)
                    for candidate in exact_term_lookup(retrieval, term, depth=EXACT_DEPTH)
                )
            exact = merge_exact(exact_parts)
            lexical = lexical_search(retrieval, question, depth=LEXICAL_DEPTH)
            vector = vector_search(
                retrieval,
                embedding_by_case[case_id]["vector"],
                EMBEDDING_SPACE_ID,
                depth=VECTOR_DEPTH,
            )
            fused = reciprocal_rank_fusion(
                {"exact": exact, "lexical": lexical, "vector": vector},
                rrf_constant=RRF_CONSTANT,
            )[:FUSED_DEPTH]
            lexeme_support = measure_lexeme_support(retrieval, question, fused)
            citable_support = measure_citable_evidence_support(retrieval, question, fused)
            for lane, values in (("exact", exact), ("lexical", lexical), ("vector", vector)):
                lane_totals[lane] += len(values)
            lane_totals["fused"] += len(fused)
            observations.append(
                {
                    "case_id": case_id,
                    "question_digest": case["question_digest"],
                    "structured_term_count": len(structured_terms),
                    "explicit_page": explicit_page,
                    "lexeme_support": lexeme_support,
                    "citable_evidence_support": citable_support,
                    "lanes": {
                        "exact": lane_records(exact, database_to_producer),
                        "lexical": lane_records(lexical, database_to_producer),
                        "vector": lane_records(vector, database_to_producer),
                    },
                    "fused": [
                        {
                            "chunk_id": database_to_producer[item.chunk_id],
                            "rank": rank,
                            "fused_score": item.fused_score,
                            "exact_priority": item.exact_priority,
                            "lane_provenance": [evidence.lane for evidence in item.evidence],
                            "retrieval_variants": [
                                evidence.retrieval_variant
                                for evidence in item.evidence
                                if evidence.retrieval_variant is not None
                            ],
                        }
                        for rank, item in enumerate(fused, start=1)
                    ],
                }
            )
        denied = False
        try:
            retrieval.execute("SELECT count(*) FROM rag.chunks").fetchone()
        except psycopg.errors.InsufficientPrivilege:
            denied = True
        require(denied, "retrieval role read a base table")

    artifact: dict[str, Any] = {
        "schema_version": 1,
        "artifact_kind": "relevance_retrieval_observations",
        "source_query_input_sha256": identities[query_input_path.name],
        "source_query_embedding_sha256": query_embeddings["source_query_embedding_sha256"],
        "query_vector_payload_sha256": identities[query_embedding_path.name],
        "source_document_embedding_sha256": identities[document_embedding_path.name],
        "method_profile": {
            "schema_version": 1,
            "chunk_method_profile_id": METHOD_PROFILE_ID,
            "retrieval_profile_id": RETRIEVAL_PROFILE_ID,
            "lexical_search_config": "english",
            "lexical_fallback": "native_or_when_strict_empty",
            "explicit_page_route": "document_identifier_plus_page",
            "exact_candidate_depth": EXACT_DEPTH,
            "lexical_candidate_depth": LEXICAL_DEPTH,
            "vector_candidate_depth": VECTOR_DEPTH,
            "fused_candidate_depth": FUSED_DEPTH,
            "rrf_constant": RRF_CONSTANT,
            "lane_weights": {"exact": 1, "lexical": 1, "vector": 1},
            "vector_distance": "cosine",
            "learned_reranker": False,
        },
        "lexeme_support_method": {
            "schema_version": 1,
            "text_search_config": "english",
            "question_measurement": "to_tsvector",
            "evidence_measurement": "stored_chunk_lexical_vector_union",
            "evidence_order": "fused_rank",
            "fused_depths": list(LEXEME_SUPPORT_DEPTHS),
            "changes_retrieval_ranking": False,
            "threshold_selected": False,
            "model_authority": False,
        },
        "citable_evidence_support_method": {
            "schema_version": 1,
            "text_search_config": "english",
            "question_measurement": "to_tsvector",
            "evidence_fields": [
                "chunk_retrieval_text",
                "document_display_name",
                "assigned_class",
                "citation_structural_path",
                "citation_page",
            ],
            "evidence_order": "fused_rank",
            "fused_depths": list(LEXEME_SUPPORT_DEPTHS),
            "changes_retrieval_ranking": False,
            "exact_reference_routing": "preserved",
            "threshold_selected": False,
            "model_authority": False,
        },
        "embedding_space_id": EMBEDDING_SPACE_ID,
        "case_count": len(observations),
        "lane_candidate_totals": lane_totals,
        "cases": observations,
    }
    artifact["observation_set_digest"] = hashlib.sha256(
        b"ishikawa.relevance-retrieval-observations.v1\x00"
        + canonical_json_bytes(artifact)
    ).hexdigest()
    payload = canonical_json_bytes(artifact)
    descriptor = os.open(output_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)

    print("runner_purpose=measure_relevance_retrieval_signals")
    print(f"python_version={sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")
    print(f"psycopg_version={psycopg.__version__}")
    print("synthetic_documents=6;organizational_documents=0;relevance_truth_received=false")
    print("prepared_chunks=126;prepared_embeddings=126;query_embeddings=12")
    print(f"embedding_space_id={EMBEDDING_SPACE_ID};embedding_dimension=768")
    print(
        f"chunk_method_profile_id={METHOD_PROFILE_ID};retrieval_profile_id={RETRIEVAL_PROFILE_ID};"
        f"method_profile=exact_page_{EXACT_DEPTH}_lexical_strict_then_or_{LEXICAL_DEPTH}_vector_{VECTOR_DEPTH}_fused_{FUSED_DEPTH};"
        f"rrf_constant={RRF_CONSTANT};text_search_config=english"
    )
    print(
        f"candidate_totals_exact={lane_totals['exact']};lexical={lane_totals['lexical']};"
        f"vector={lane_totals['vector']};fused={lane_totals['fused']}"
    )
    print("retrieval_role_active_view_read=pass;retrieval_role_base_table_read=denied")
    print(
        "lexeme_support_measurement=postgresql_english;"
        "fused_depths=1,3,5,10,20;changes_retrieval_ranking=false;"
        "threshold_selected=false;model_authority=false"
    )
    print(
        "citable_evidence_support_measurement=postgresql_english;"
        "fields=chunk_text,display_name,assigned_class,structural_path,citation_page;"
        "fused_depths=1,3,5,10,20;changes_retrieval_ranking=false;"
        "exact_reference_routing=preserved;threshold_selected=false;model_authority=false"
    )
    print(f"observation_set_digest={artifact['observation_set_digest']}")
    print(
        f"observation_artifact_sha256={hashlib.sha256(payload).hexdigest()};"
        f"observation_artifact_bytes={len(payload)}"
    )
    print("held_out_retrieval_measurement=pass")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(
            "held_out_retrieval_measurement=blocked;"
            f"reason={type(error).__name__}",
            file=sys.stderr,
        )
        raise
