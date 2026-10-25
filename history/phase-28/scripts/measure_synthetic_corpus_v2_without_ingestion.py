#!/usr/bin/env python3
"""Measure corpus-v2 hybrid retrieval without publishing it to PostgreSQL."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import sys
from dataclasses import dataclass
from fractions import Fraction
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence


BODY_CASE_COUNT = 60
HEADER_CASE_COUNT = 8
QUERY_PREFIX = "search_query: "
STRUCTURED_TERM = re.compile(r"\b(?:[0-9]{2,6}\s+[A-Z][A-Z0-9]{1,15}\s+[0-9]{2,8}|TST-[0-9]{4})\b")
PAGE_REFERENCE = re.compile(r"\bpage\s+([1-9][0-9]{0,5})\b", re.IGNORECASE)
DISPLAY_NAME_TO_DOCUMENT_REF = {
    "Synthetic Operations Control 2001": "SYN-V2-001",
    "Synthetic Operations Control 2002": "SYN-V2-002",
    "Synthetic Schedule 2003": "SYN-V2-003",
    "Synthetic TST-9001 Form": "SYN-V2-004",
    "Synthetic Governance Manual": "SYN-V2-005",
    "Synthetic Incident Reporting Procedure": "SYN-V2-006",
}


class MeasurementError(RuntimeError):
    """Stable content-free measurement failure."""


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise MeasurementError(reason)


def canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def domain_digest(domain: str, value: Any) -> str:
    digest = hashlib.sha256()
    digest.update(domain.encode("ascii"))
    digest.update(b"\x00")
    digest.update(canonical_json_bytes(value))
    return digest.hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def require_sha256(value: str, reason: str) -> str:
    require(
        isinstance(value, str)
        and len(value) == 64
        and all(character in "0123456789abcdef" for character in value),
        reason,
    )
    return value


def load_bound_json(path: Path, expected_sha256: str, maximum_bytes: int) -> dict[str, Any]:
    require(
        path.is_absolute()
        and path.is_file()
        and not path.is_symlink()
        and path.stat().st_size <= maximum_bytes,
        "json_input_unsafe",
    )
    require(sha256_file(path) == require_sha256(expected_sha256, "json_identity_invalid"), "json_identity_mismatch")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise MeasurementError("json_input_invalid") from error
    require(isinstance(value, dict), "json_input_invalid")
    return value


@dataclass(frozen=True, slots=True)
class ExpectedEvidence:
    document_ref: str
    page: int


@dataclass(frozen=True, slots=True)
class Case:
    case_id: str
    family: str
    question: str
    department: str | None
    clarification_reply: str | None
    required_evidence: tuple[ExpectedEvidence, ...]


@dataclass(frozen=True, slots=True)
class CandidateRecord:
    chunk_id: str
    document_id: str
    document_version_id: str
    document_ref: str
    ordinal: int
    projection_kind: str
    retrieval_text: str
    page_start: int
    page_end: int
    policy_number: str | None
    document_context: str | None
    department: str
    department_normalized: str
    department_aliases: tuple[str, ...]


def load_body_cases(value: Mapping[str, Any]) -> tuple[Case, ...]:
    records = value.get("cases")
    require(
        value.get("artifact_kind") == "ishikawa_extended_retrieval_mrr_cases"
        and value.get("schema_version") == 1
        and value.get("synthetic_content_only") is True
        and isinstance(records, list)
        and len(records) == BODY_CASE_COUNT,
        "body_case_contract_invalid",
    )
    cases = []
    for item in records:
        require(
            isinstance(item, dict)
            and set(item) == {"case_id", "question", "relevant_evidence"}
            and isinstance(item["case_id"], str)
            and isinstance(item["question"], str)
            and item["question"].strip() == item["question"]
            and isinstance(item["relevant_evidence"], list)
            and item["relevant_evidence"],
            "body_case_contract_invalid",
        )
        expected = []
        for evidence in item["relevant_evidence"]:
            require(
                isinstance(evidence, dict)
                and set(evidence) == {"display_name", "page"}
                and evidence["display_name"] in DISPLAY_NAME_TO_DOCUMENT_REF
                and type(evidence["page"]) is int
                and evidence["page"] >= 1,
                "body_evidence_contract_invalid",
            )
            expected.append(ExpectedEvidence(
                DISPLAY_NAME_TO_DOCUMENT_REF[evidence["display_name"]],
                evidence["page"],
            ))
        cases.append(Case(
            item["case_id"], "body", item["question"], None, None, tuple(expected)
        ))
    require(
        {item.case_id for item in cases}
        == {f"E-{index:03d}" for index in range(1, BODY_CASE_COUNT + 1)},
        "body_case_inventory_invalid",
    )
    return tuple(cases)


def load_header_cases(value: Mapping[str, Any]) -> tuple[Case, ...]:
    records = value.get("cases")
    require(
        value.get("artifact_kind")
        == "ishikawa_synthetic_corpus_v2_header_retrieval_cases"
        and value.get("schema_version") == 1
        and value.get("synthetic_content_only") is True
        and isinstance(records, list)
        and len(records) == HEADER_CASE_COUNT,
        "header_case_contract_invalid",
    )
    cases = []
    for item in records:
        require(
            isinstance(item, dict)
            and set(item) == {
                "case_id", "class", "question", "department",
                "clarification_reply", "required_evidence",
            }
            and isinstance(item["case_id"], str)
            and isinstance(item["class"], str)
            and isinstance(item["question"], str)
            and item["question"].strip() == item["question"]
            and (item["department"] is None or isinstance(item["department"], str))
            and (
                item["clarification_reply"] is None
                or isinstance(item["clarification_reply"], str)
            )
            and isinstance(item["required_evidence"], list)
            and item["required_evidence"],
            "header_case_contract_invalid",
        )
        expected = []
        for evidence in item["required_evidence"]:
            require(
                isinstance(evidence, dict)
                and set(evidence) == {"document_ref", "page"}
                and re.fullmatch(r"SYN-V2-[0-9]{3}", evidence["document_ref"])
                and type(evidence["page"]) is int
                and evidence["page"] >= 1,
                "header_evidence_contract_invalid",
            )
            expected.append(ExpectedEvidence(evidence["document_ref"], evidence["page"]))
        cases.append(Case(
            item["case_id"], item["class"], item["question"],
            item["department"], item["clarification_reply"], tuple(expected),
        ))
    require(
        {item.case_id for item in cases}
        == {f"H-{index:03d}" for index in range(1, HEADER_CASE_COUNT + 1)},
        "header_case_inventory_invalid",
    )
    return tuple(cases)


def flatten_candidates(source: Mapping[str, Any]) -> tuple[CandidateRecord, ...]:
    documents = source.get("documents")
    require(isinstance(documents, list) and len(documents) == 6, "candidate_inventory_invalid")
    records = []
    seen = set()
    for document in documents:
        require(
            isinstance(document, dict)
            and isinstance(document.get("document_ref"), str)
            and isinstance(document.get("candidates"), list),
            "candidate_inventory_invalid",
        )
        for ordinal, candidate in enumerate(document["candidates"]):
            require(isinstance(candidate, dict), "candidate_inventory_invalid")
            control = candidate.get("retrieval_filters", {}).get("document_control")
            anchor = candidate.get("citation_anchor")
            require(
                isinstance(control, dict)
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
            records.append(CandidateRecord(
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
    require(len(records) == 139, "candidate_count_mismatch")
    require(
        sum(item.projection_kind == "document_control_metadata" for item in records) == 6,
        "document_control_candidate_inventory_invalid",
    )
    return tuple(records)


def validate_embedding_artifact(
    value: Mapping[str, Any],
    chunks_sha256: str,
    candidates: Sequence[CandidateRecord],
) -> dict[str, list[float]]:
    records = value.get("records")
    require(
        value.get("artifact_kind") == "measured_nomic_chunk_embeddings"
        and value.get("schema_version") == 1
        and value.get("source_chunk_candidate_sha256") == chunks_sha256
        and value.get("publication_eligible") is False
        and isinstance(value.get("embedding_space_id"), str)
        and isinstance(records, list)
        and len(records) == len(candidates),
        "embedding_artifact_contract_invalid",
    )
    vectors = {}
    for item in records:
        vector = item.get("vector") if isinstance(item, dict) else None
        require(
            isinstance(item, dict)
            and isinstance(item.get("chunk_id"), str)
            and item["chunk_id"] not in vectors
            and isinstance(vector, list)
            and len(vector) == 768
            and all(
                isinstance(number, (int, float))
                and not isinstance(number, bool)
                and math.isfinite(float(number))
                for number in vector
            ),
            "embedding_record_invalid",
        )
        vectors[item["chunk_id"]] = [float(number) for number in vector]
    require(
        set(vectors) == {candidate.chunk_id for candidate in candidates},
        "embedding_coverage_invalid",
    )
    return vectors


def normalized_department(value: str) -> str:
    return " ".join(re.findall(r"[a-z0-9]+", value.casefold()))


def permitted_candidates(
    case: Case,
    candidates: Sequence[CandidateRecord],
) -> tuple[CandidateRecord, ...]:
    allowed_refs: set[str] | None = None
    folded_question = case.question.casefold()
    # A document context constrains retrieval only when the question explicitly
    # calls it a document.  Generic prose that happens to contain a short
    # context (for example, "decision record") must remain corpus-wide.
    context_refs = {
        candidate.document_ref
        for candidate in candidates
        if candidate.document_context
        and re.search(
            rf"(?<![A-Za-z0-9]){re.escape(candidate.document_context)}"
            rf"\s+document(?![A-Za-z0-9])",
            case.question,
            re.IGNORECASE,
        )
    }
    policy_refs = {
        candidate.document_ref
        for candidate in candidates
        if candidate.policy_number
        and re.search(
            rf"(?<![A-Za-z0-9]){re.escape(candidate.policy_number)}(?![A-Za-z0-9])",
            case.question,
            re.IGNORECASE,
        )
    }
    recognized_refs = context_refs | policy_refs
    if len(recognized_refs) == 1:
        allowed_refs = recognized_refs
    if case.department is not None:
        department = normalized_department(case.department)
        department_refs = {
            candidate.document_ref
            for candidate in candidates
            if candidate.department_normalized == department
        }
        require(department_refs, "department_filter_unresolved")
        allowed_refs = department_refs if allowed_refs is None else allowed_refs & department_refs
        require(allowed_refs, "document_and_department_filter_conflict")
        if case.clarification_reply is not None:
            require(
                any(
                    case.clarification_reply.casefold()
                    in {alias.casefold() for alias in candidate.department_aliases}
                    for candidate in candidates
                    if candidate.document_ref in department_refs
                ),
                "clarification_alias_unresolved",
            )
    if allowed_refs is None:
        return tuple(candidates)
    return tuple(candidate for candidate in candidates if candidate.document_ref in allowed_refs)


def exact_lane(
    case: Case,
    candidates: Sequence[CandidateRecord],
    lane_candidate_type: Any,
) -> tuple[Any, ...]:
    question = case.question
    terms = tuple(dict.fromkeys(match.group(0) for match in STRUCTURED_TERM.finditer(question)))
    pages = {int(match.group(1)) for match in PAGE_REFERENCE.finditer(question)}
    selected: list[CandidateRecord] = []
    if case.department is not None:
        selected = sorted(
            (
                candidate for candidate in candidates
                if candidate.projection_kind == "document_control_metadata"
            ),
            key=lambda item: (item.document_ref, item.ordinal, item.chunk_id),
        )
    if not selected and len(terms) == 1 and len(pages) == 1:
        owners = {
            candidate.document_ref
            for candidate in candidates
            if candidate.policy_number and candidate.policy_number.casefold() == terms[0].casefold()
        }
        if len(owners) == 1:
            page = next(iter(pages))
            selected = [
                candidate for candidate in candidates
                if candidate.document_ref in owners
                and candidate.page_start <= page <= candidate.page_end
            ]
    if not selected and terms:
        selected = [
            candidate for candidate in candidates
            if any(term.casefold() in candidate.retrieval_text.casefold() for term in terms)
        ]
    selected.sort(key=lambda item: (item.ordinal, item.chunk_id))
    return tuple(
        lane_candidate_type(
            item.chunk_id, item.document_id, item.document_version_id,
            item.document_ref, "exact", rank, 1.0, "preingestion_metadata_match",
        )
        for rank, item in enumerate(
            selected if case.department is not None else selected[:1],
            start=1,
        )
    )


LEXICAL_SQL = """/* ishikawa.v2-preingestion.lexical */
WITH candidates AS (
  SELECT * FROM jsonb_to_recordset(%s::jsonb)
    AS candidate(chunk_id text, retrieval_text text)
), request AS (
  SELECT websearch_to_tsquery('english'::regconfig, %s) AS query
)
SELECT candidate.chunk_id,
       ts_rank_cd(to_tsvector('english'::regconfig, candidate.retrieval_text), request.query)::float8
FROM candidates AS candidate CROSS JOIN request
WHERE request.query <> ''::tsquery
  AND to_tsvector('english'::regconfig, candidate.retrieval_text) @@ request.query
ORDER BY 2 DESC, candidate.chunk_id
LIMIT 20
"""


LEXICAL_FALLBACK_SQL = """/* ishikawa.v2-preingestion.lexical-or-fallback */
WITH candidates AS (
  SELECT * FROM jsonb_to_recordset(%s::jsonb)
    AS candidate(chunk_id text, retrieval_text text)
), lexemes AS (
  SELECT string_agg(lexeme, ' OR ' ORDER BY lexeme) AS query_text
  FROM unnest(tsvector_to_array(to_tsvector('english'::regconfig, %s))) AS lexeme
), request AS (
  SELECT websearch_to_tsquery('english'::regconfig, COALESCE(query_text, '')) AS query
  FROM lexemes
)
SELECT candidate.chunk_id,
       ts_rank_cd(to_tsvector('english'::regconfig, candidate.retrieval_text), request.query)::float8
FROM candidates AS candidate CROSS JOIN request
WHERE request.query <> ''::tsquery
  AND to_tsvector('english'::regconfig, candidate.retrieval_text) @@ request.query
ORDER BY 2 DESC, candidate.chunk_id
LIMIT 20
"""


def lexical_lane(
    connection: Any,
    question: str,
    candidates: Sequence[CandidateRecord],
    by_chunk: Mapping[str, CandidateRecord],
    lane_candidate_type: Any,
) -> tuple[Any, ...]:
    payload = json.dumps(
        [{"chunk_id": item.chunk_id, "retrieval_text": item.retrieval_text} for item in candidates],
        separators=(",", ":"),
    )
    rows = connection.execute(LEXICAL_SQL, (payload, question)).fetchall()
    variant = "strict"
    if not rows:
        rows = connection.execute(LEXICAL_FALLBACK_SQL, (payload, question)).fetchall()
        variant = "or_fallback"
    return tuple(
        lane_candidate_type(
            by_chunk[chunk_id].chunk_id,
            by_chunk[chunk_id].document_id,
            by_chunk[chunk_id].document_version_id,
            by_chunk[chunk_id].document_ref,
            "lexical",
            rank,
            float(score),
            None,
            variant,
        )
        for rank, (chunk_id, score) in enumerate(rows, start=1)
    )


def cosine_similarity(left: Sequence[float], right: Sequence[float]) -> float:
    left_norm = math.sqrt(sum(value * value for value in left))
    right_norm = math.sqrt(sum(value * value for value in right))
    require(left_norm > 0.0 and right_norm > 0.0, "zero_embedding_vector")
    result = sum(a * b for a, b in zip(left, right, strict=True)) / (left_norm * right_norm)
    require(math.isfinite(result), "cosine_similarity_invalid")
    return min(1.0, max(-1.0, result))


def vector_lane(
    query_vector: Sequence[float],
    candidates: Sequence[CandidateRecord],
    vectors: Mapping[str, Sequence[float]],
    lane_candidate_type: Any,
) -> tuple[Any, ...]:
    ranked = sorted(
        ((cosine_similarity(query_vector, vectors[item.chunk_id]), item) for item in candidates),
        key=lambda pair: (-pair[0], pair[1].chunk_id),
    )[:20]
    return tuple(
        lane_candidate_type(
            item.chunk_id, item.document_id, item.document_version_id,
            item.document_ref, "vector", rank, score,
        )
        for rank, (score, item) in enumerate(ranked, start=1)
    )


def matches(candidate: CandidateRecord, expected: ExpectedEvidence) -> bool:
    return (
        candidate.document_ref == expected.document_ref
        and candidate.page_start <= expected.page <= candidate.page_end
    )


def rank_record(rank: int, candidate: Any, by_chunk: Mapping[str, CandidateRecord]) -> dict[str, Any]:
    metadata = by_chunk[candidate.chunk_id]
    raw_score = getattr(candidate, "raw_score", None)
    fused_score = getattr(candidate, "fused_score", None)
    return {
        "rank": rank,
        "chunk_id": candidate.chunk_id,
        "document_ref": metadata.document_ref,
        "page_start": metadata.page_start,
        "page_end": metadata.page_end,
        "score": format(float(raw_score if raw_score is not None else fused_score), ".17g"),
    }


def measure_case(
    case: Case,
    exact: Sequence[Any],
    lexical: Sequence[Any],
    vector: Sequence[Any],
    fused: Sequence[Any],
    permitted: Sequence[CandidateRecord],
    by_chunk: Mapping[str, CandidateRecord],
) -> dict[str, Any]:
    fused_depth = tuple(fused[:20])
    first_rank = next(
        (
            rank for rank, item in enumerate(fused_depth, start=1)
            if any(matches(by_chunk[item.chunk_id], expected) for expected in case.required_evidence)
        ),
        None,
    )
    matched = [
        expected for expected in case.required_evidence
        if any(matches(by_chunk[item.chunk_id], expected) for item in fused_depth)
    ]
    return {
        "case_id": case.case_id,
        "family": case.family,
        "query_sha256": hashlib.sha256(case.question.encode("utf-8")).hexdigest(),
        "department_filter": case.department,
        "clarification_reply_sha256": (
            hashlib.sha256(case.clarification_reply.encode("utf-8")).hexdigest()
            if case.clarification_reply is not None else None
        ),
        "permitted_document_refs": sorted({item.document_ref for item in permitted}),
        "first_relevant_rank": first_rank,
        "relevant_within_top_five": first_rank is not None and first_rank <= 5,
        "required_evidence_count": len(case.required_evidence),
        "matched_evidence_count": len(matched),
        "matched_evidence": [
            {"document_ref": item.document_ref, "page": item.page} for item in matched
        ],
        "lanes": {
            "exact": [rank_record(rank, item, by_chunk) for rank, item in enumerate(exact, 1)],
            "lexical": [rank_record(rank, item, by_chunk) for rank, item in enumerate(lexical, 1)],
            "vector": [rank_record(rank, item, by_chunk) for rank, item in enumerate(vector, 1)],
        },
        "fused": [rank_record(rank, item, by_chunk) for rank, item in enumerate(fused_depth, 1)],
    }


def aggregate(results: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    require(results, "empty_metric_family")
    reciprocal = sum(
        Fraction(1, item["first_relevant_rank"])
        if item["first_relevant_rank"] is not None else Fraction(0, 1)
        for item in results
    ) / len(results)
    return {
        "case_count": len(results),
        "mrr_at_20": format(float(reciprocal), ".6f"),
        "mrr_fraction_numerator": reciprocal.numerator,
        "mrr_fraction_denominator": reciprocal.denominator,
        "relevant_at_5": sum(bool(item["relevant_within_top_five"]) for item in results),
        "relevant_at_20": sum(item["first_relevant_rank"] is not None for item in results),
        "required_evidence_matched_at_20": sum(item["matched_evidence_count"] for item in results),
        "required_evidence_total": sum(item["required_evidence_count"] for item in results),
    }


def write_exclusive(path: Path, payload: bytes) -> None:
    require(
        path.is_absolute()
        and not path.exists()
        and not path.is_symlink()
        and path.parent.is_dir()
        and not path.parent.is_symlink(),
        "output_path_unsafe",
    )
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)


def execute(arguments: argparse.Namespace) -> None:
    chunks = load_bound_json(arguments.chunks, arguments.expected_chunks_sha256, 16 * 1024 * 1024)
    body_source = load_bound_json(arguments.body_cases, arguments.expected_body_cases_sha256, 2 * 1024 * 1024)
    header_source = load_bound_json(arguments.header_cases, arguments.expected_header_cases_sha256, 1024 * 1024)
    embeddings = load_bound_json(
        arguments.document_embeddings,
        arguments.expected_document_embeddings_sha256,
        128 * 1024 * 1024,
    )
    body_cases = load_body_cases(body_source)
    header_cases = load_header_cases(header_source)
    cases = body_cases + header_cases
    candidates = flatten_candidates(chunks)
    by_chunk = {item.chunk_id: item for item in candidates}
    vectors = validate_embedding_artifact(
        embeddings, arguments.expected_chunks_sha256, candidates
    )

    secret_text = os.environ.pop("ISHIKAWA_NOMIC_API_KEY", "")
    require(32 <= len(secret_text) <= 1024 and "\n" not in secret_text, "nomic_credential_invalid")
    secret = bytearray(secret_text.encode("utf-8"))
    secret_text = ""
    sys.path.insert(0, str(arguments.python_root))
    from ishikawa.retrieval import LaneCandidate, reciprocal_rank_fusion
    from embed_document_candidates_via_endpoint import EndpointClient, wipe
    try:
        client = EndpointClient(arguments.embedding_url, arguments.tokenizer_url, secret)
        runtime_identity = client.model_identity()
        require(
            runtime_identity == embeddings.get("runtime_identity_digest"),
            "embedding_runtime_identity_changed",
        )
        query_vectors = []
        query_usage = 0
        inputs = [QUERY_PREFIX + item.question for item in cases]
        for start in range(0, len(inputs), 16):
            batch, usage = client.embeddings(inputs[start:start + 16])
            query_vectors.extend(batch)
            query_usage += usage
    finally:
        if "client" in locals():
            client.close()
        wipe(secret)
    require(len(query_vectors) == len(cases), "query_embedding_coverage_invalid")

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
        raise MeasurementError("temporary_postgresql_connection_failed") from error
    results = []
    try:
        connection.execute("BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
        state = connection.execute(
            "SELECT current_setting('transaction_read_only'), current_database(), current_user"
        ).fetchone()
        require(
            state == ("on", "postgres", arguments.postgresql_user),
            "temporary_postgresql_boundary_invalid",
        )
        for case, query_vector in zip(cases, query_vectors, strict=True):
            permitted = permitted_candidates(case, candidates)
            exact = exact_lane(case, permitted, LaneCandidate)
            lexical = lexical_lane(
                connection, case.question, permitted, by_chunk, LaneCandidate
            )
            vector = vector_lane(query_vector, permitted, vectors, LaneCandidate)
            fused = reciprocal_rank_fusion(
                {"exact": exact, "lexical": lexical, "vector": vector},
                rrf_constant=60,
                lane_weights={"exact": 1, "lexical": 1, "vector": 4},
            )[:20]
            results.append(measure_case(
                case, exact, lexical, vector, fused, permitted, by_chunk
            ))
        connection.rollback()
    finally:
        connection.close()

    body_results = results[:BODY_CASE_COUNT]
    header_results = results[BODY_CASE_COUNT:]
    body_metrics = aggregate(body_results)
    header_metrics = aggregate(header_results)
    measurement_gate = (
        Fraction(
            body_metrics["mrr_fraction_numerator"],
            body_metrics["mrr_fraction_denominator"],
        ) > Fraction(91, 100)
        and body_metrics["relevant_at_20"] == BODY_CASE_COUNT
        and header_metrics["relevant_at_5"] == HEADER_CASE_COUNT
        and header_metrics["required_evidence_matched_at_20"]
        == header_metrics["required_evidence_total"]
    )
    artifact: dict[str, Any] = {
        "schema_version": 1,
        "artifact_kind": "ishikawa_synthetic_corpus_v2_preingestion_retrieval_observation",
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
        },
        "document_count": 6,
        "candidate_count": len(candidates),
        "query_embedding_count": len(cases),
        "query_embedding_usage_tokens": query_usage,
        "body_metrics": body_metrics,
        "header_metrics": header_metrics,
        "preingestion_measurement_gate": "pass" if measurement_gate else "not_met",
        "database_boundary": "private_temporary_postgresql_repeatable_read_read_only",
        "database_tables_read": False,
        "database_write": False,
        "accepted_v1_database_contact": False,
        "gemma_contact": False,
        "question_text_retained": False,
        "query_vectors_retained": False,
        "source_text_retained": False,
        "credentials_retained": False,
        "cases": results,
    }
    artifact["observation_set_id"] = domain_digest(
        "ishikawa.synthetic-corpus-v2-preingestion-retrieval.v1", artifact
    )
    payload = canonical_json_bytes(artifact)
    write_exclusive(arguments.output, payload)
    print(
        f"case_count={len(cases)};body_cases={BODY_CASE_COUNT};"
        f"header_cases={HEADER_CASE_COUNT};query_embeddings={len(cases)}"
    )
    print(
        f"body_mrr_at_20={body_metrics['mrr_at_20']};"
        f"body_relevant_at_5={body_metrics['relevant_at_5']}/{BODY_CASE_COUNT};"
        f"body_relevant_at_20={body_metrics['relevant_at_20']}/{BODY_CASE_COUNT}"
    )
    print(
        f"header_mrr_at_20={header_metrics['mrr_at_20']};"
        f"header_relevant_at_5={header_metrics['relevant_at_5']}/{HEADER_CASE_COUNT};"
        "header_required_evidence_at_20="
        f"{header_metrics['required_evidence_matched_at_20']}/"
        f"{header_metrics['required_evidence_total']}"
    )
    print(
        f"preingestion_measurement_gate={'pass' if measurement_gate else 'not_met'};"
        "strict_body_target=greater_than_0.91"
    )
    print(
        "accepted_v1_database_contact=false;database_write=false;"
        "gemma_contact=false;question_text_retained=false;"
        "query_vectors_retained=false;source_text_retained=false;credentials_retained=false"
    )
    print(
        f"observation_set_id={artifact['observation_set_id']};"
        f"artifact_sha256={hashlib.sha256(payload).hexdigest()};artifact_bytes={len(payload)}"
    )
    print("synthetic_corpus_v2_preingestion_measurement=pass")


def self_test() -> None:
    assert normalized_department("Information Technology") == "information technology"
    assert normalized_department("Dept. 42") == "dept 42"
    assert math.isclose(cosine_similarity([1.0, 0.0], [1.0, 0.0]), 1.0)
    metrics = aggregate((
        {"first_relevant_rank": 1, "relevant_within_top_five": True,
         "matched_evidence_count": 1, "required_evidence_count": 1},
        {"first_relevant_rank": 2, "relevant_within_top_five": True,
         "matched_evidence_count": 1, "required_evidence_count": 1},
    ))
    assert metrics["mrr_at_20"] == "0.750000"
    print("synthetic_corpus_v2_preingestion_measurement_self_test=pass")


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
    require(all(item is not None for item in required), "required_argument_missing")
    require(
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
    except MeasurementError as error:
        print(
            f"synthetic_corpus_v2_preingestion_measurement=blocked;reason={error}",
            file=sys.stderr,
        )
        raise SystemExit(1)
