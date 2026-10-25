#!/usr/bin/env python3
"""Validate measured Nomic relevance-query embeddings without logging text."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
from pathlib import Path
from typing import Any, NoReturn


MODEL_ID = "nomic-ai/nomic-embed-text-v1.5"
MODEL_REVISION = "e9b6763023c676ca8431644204f50c2b100d9aab"
MODEL_SHA256 = "9e7d262b1fe5ea350782829496efa831901b77486bbde1cea54a4c822d010d5c"
TOKENIZER_SHA256 = "d241a60d5e8f04cc1b2b3e9ef7a4921b27bf526d9f6050ab90f9267a1f9e5c66"
QUERY_PREFIX = "search_query: "
DOCUMENT_PREFIX = "search_document: "
DIMENSION = 768
MAXIMUM_TOKENS = 2048
TARGET_TOKENS = 512
TOLERANCE = 1e-5
EXPECTED_CASES = 12
HEX = re.compile(r"^[0-9a-f]{64}$")
LINE_PATTERN = re.compile(
    r"^\[relevance-embedding\] [A-Za-z0-9_.:/=@+,-]+(?: [A-Za-z0-9_.:/=@+,-]+)*$"
)


class EvaluationError(RuntimeError):
    pass


def fail(reason: str) -> NoReturn:
    raise EvaluationError(reason)


def canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, allow_nan=False, sort_keys=True, separators=(",", ":")
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
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_json(path: Path, maximum_bytes: int) -> Any:
    if not path.is_file() or path.is_symlink() or path.stat().st_size > maximum_bytes:
        fail("unsafe_or_oversized_json")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail("invalid_json")


def expected_space() -> dict[str, Any]:
    return {
        "schema_version": 1,
        "model_id": MODEL_ID,
        "model_revision": MODEL_REVISION,
        "model_sha256": MODEL_SHA256,
        "tokenizer_sha256": TOKENIZER_SHA256,
        "pooling": "mean_tokens",
        "document_prefix": DOCUMENT_PREFIX,
        "dimension": DIMENSION,
        "maximum_input_tokens": MAXIMUM_TOKENS,
        "initial_target_tokens": TARGET_TOKENS,
        "token_count_mode": "with_special_tokens",
        "vector_transform": "none",
        "distance": "cosine",
        "numeric_tolerance": TOLERANCE,
    }


def parse_target_result(path: Path) -> dict[str, str]:
    if not path.is_file() or path.is_symlink() or path.stat().st_size > 1024 * 1024:
        fail("unsafe_target_result")
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError):
        fail("invalid_target_result")
    if not lines or any(LINE_PATTERN.fullmatch(line) is None for line in lines):
        fail("target_result_contains_unstructured_output")
    if sum(" result=PASS " in f" {line} " for line in lines) != 1:
        fail("target_result_pass_marker_invalid")
    if any(" result=BLOCKED " in f" {line} " for line in lines):
        fail("target_result_contains_blocked_marker")
    if sum(" credential_source=operator_attended_tty " in f" {line} " for line in lines) != 1:
        fail("target_result_credential_marker_invalid")
    if sum(" cleanup=" in line for line in lines) != 1:
        fail("target_result_cleanup_marker_invalid")
    fields: dict[str, str] = {}
    for line in lines:
        for token in line.split()[1:]:
            if "=" in token:
                key, value = token.split("=", 1)
                fields[key] = value
    required = {
        "result": "PASS",
        "model_identity": "pass",
        "tokenizer_identity": "pass",
        "tokenizer_service_agreement": "pass",
        "embeddings": "pass",
        "finite_vectors": "pass",
        "calibration_eligible": "true",
        "publication_eligible": "false",
        "raw_text_logged": "false",
        "vectors_logged": "false",
        "credential_recorded": "false",
        "queries": "12",
        "responsive": "6",
        "nonresponsive": "6",
    }
    if any(fields.get(key) != value for key, value in required.items()):
        fail("target_result_required_fact_missing")
    return fields


def evaluate(arguments: argparse.Namespace) -> dict[str, Any]:
    if HEX.fullmatch(arguments.expected_cases_sha256 or "") is None:
        fail("expected_case_identity_invalid")
    if sha256_file(arguments.cases) != arguments.expected_cases_sha256:
        fail("case_set_identity_mismatch")
    cases = load_json(arguments.cases, 1024 * 1024)
    queries = load_json(arguments.queries, 1024 * 1024)
    artifact = load_json(arguments.artifact, 32 * 1024 * 1024)
    result_fields = parse_target_result(arguments.target_result)
    if not isinstance(cases, dict) or cases.get("artifact_kind") != "relevance_calibration_cases":
        fail("case_set_contract_invalid")
    source_cases = {item["case_id"]: item for item in cases.get("cases", [])}
    if len(source_cases) != EXPECTED_CASES:
        fail("case_set_inventory_invalid")
    if not isinstance(queries, dict) or set(queries) != {
        "artifact_kind", "cases", "query_set_digest", "schema_version", "source_case_set_sha256"
    }:
        fail("query_set_contract_invalid")
    query_digest_input = dict(queries)
    query_digest_input.pop("query_set_digest")
    if (
        queries["schema_version"] != 1
        or queries["artifact_kind"] != "relevance_embedding_queries"
        or queries["source_case_set_sha256"] != arguments.expected_cases_sha256
        or queries["query_set_digest"] != domain_digest(
            "ishikawa.relevance-embedding-query-set.v1", query_digest_input
        )
    ):
        fail("query_set_identity_invalid")
    query_sha256 = sha256_file(arguments.queries)
    query_cases = {item["case_id"]: item for item in queries["cases"]}
    if set(query_cases) != set(source_cases):
        fail("query_case_coverage_invalid")
    for case_id, query in query_cases.items():
        source = source_cases[case_id]
        expected_digest = domain_digest(
            "ishikawa.retrieval-question.v1", {"question": source["question"]}
        )
        if (
            query != {
                "case_id": case_id,
                "class": source["class"],
                "question": source["question"],
                "question_digest": expected_digest,
            }
        ):
            fail("query_case_mapping_invalid")

    space = expected_space()
    space_id = domain_digest("ishikawa.embedding-space.v1", space)
    if (
        not isinstance(artifact, dict)
        or artifact.get("schema_version") != 1
        or artifact.get("artifact_kind") != "measured_nomic_relevance_query_embeddings"
        or artifact.get("source_query_input_sha256") != query_sha256
        or artifact.get("source_case_set_sha256") != arguments.expected_cases_sha256
        or artifact.get("case_count") != EXPECTED_CASES
        or artifact.get("class_counts") != {"nonresponsive": 6, "responsive": 6}
        or artifact.get("query_method") != {
            "schema_version": 1,
            "query_prefix": QUERY_PREFIX,
            "embedding_request_batch_size": 1,
        }
        or artifact.get("embedding_space") != space
        or artifact.get("embedding_space_id") != space_id
        or artifact.get("calibration_eligible") is not True
        or artifact.get("publication_eligible") is not False
        or artifact.get("publication_blocker") != "relevance_retrieval_observation_pending"
    ):
        fail("embedding_artifact_contract_mismatch")
    records = artifact.get("records")
    if not isinstance(records, list) or len(records) != EXPECTED_CASES:
        fail("embedding_record_count_invalid")

    seen: set[str] = set()
    totals: list[int] = []
    norms: list[float] = []
    for record in records:
        if not isinstance(record, dict):
            fail("embedding_record_invalid")
        case_id = record.get("case_id")
        if case_id not in query_cases or case_id in seen:
            fail("embedding_case_mapping_invalid")
        seen.add(case_id)
        query = query_cases[case_id]
        exact_input = QUERY_PREFIX + query["question"]
        input_digest = domain_digest("ishikawa.embedding-input.v1", {"input": exact_input})
        expected_embedding_id = domain_digest(
            "ishikawa.relevance-query-embedding.v1",
            {"case_id": case_id, "embedding_space_id": space_id, "submitted_input_digest": input_digest},
        )
        if (
            record.get("schema_version") != 1
            or record.get("query_embedding_id") != expected_embedding_id
            or record.get("class") != query["class"]
            or record.get("question_digest") != query["question_digest"]
            or record.get("embedding_space_id") != space_id
            or record.get("query_prefix") != QUERY_PREFIX
            or record.get("submitted_input_digest") != input_digest
            or record.get("vector_dimension") != DIMENSION
            or record.get("vector_transform") != "none"
        ):
            fail("embedding_record_identity_invalid")
        accounting = record.get("token_accounting")
        integer_fields = (
            "question_tokens_without_special", "prefix_tokens_without_special",
            "total_without_special", "special_token_count", "total_embedding_input_tokens",
        )
        if (
            not isinstance(accounting, dict)
            or accounting.get("tokenizer_sha256") != TOKENIZER_SHA256
            or accounting.get("count_mode") != "with_special_tokens"
            or any(
                not isinstance(accounting.get(field), int) or accounting[field] < 0
                for field in integer_fields
            )
            or not 0 < accounting["total_embedding_input_tokens"] <= MAXIMUM_TOKENS
            or accounting["total_without_special"] + accounting["special_token_count"]
            != accounting["total_embedding_input_tokens"]
        ):
            fail("embedding_token_accounting_invalid")
        vector = record.get("vector")
        if (
            not isinstance(vector, list)
            or len(vector) != DIMENSION
            or any(
                not isinstance(value, (int, float))
                or isinstance(value, bool)
                or not math.isfinite(float(value))
                for value in vector
            )
        ):
            fail("embedding_vector_invalid")
        norm = math.sqrt(sum(float(value) ** 2 for value in vector))
        if (
            norm == 0.0
            or not isinstance(record.get("vector_norm"), (int, float))
            or not math.isclose(norm, float(record["vector_norm"]), rel_tol=1e-12, abs_tol=1e-12)
        ):
            fail("embedding_vector_norm_invalid")
        totals.append(accounting["total_embedding_input_tokens"])
        norms.append(norm)
    if seen != set(query_cases):
        fail("embedding_record_coverage_incomplete")
    digest_input = dict(artifact)
    stored_digest = digest_input.pop("query_embedding_set_digest", None)
    if stored_digest != domain_digest("ishikawa.relevance-query-embedding-set.v1", digest_input):
        fail("embedding_set_digest_invalid")

    artifact_sha256 = sha256_file(arguments.artifact)
    artifact_bytes = arguments.artifact.stat().st_size
    expected_result = {
        "dimension": str(DIMENSION),
        "token_min": str(min(totals)),
        "token_max": str(max(totals)),
        "over_model_ceiling": "0",
        "batches": "12",
        "embedding_space_id": space_id,
        "query_embedding_set_digest": stored_digest,
        "artifact_sha256": artifact_sha256,
        "artifact_bytes": str(artifact_bytes),
    }
    if any(result_fields.get(key) != value for key, value in expected_result.items()):
        fail("target_result_and_artifact_disagree")
    return {
        "artifact_bytes": artifact_bytes,
        "artifact_sha256": artifact_sha256,
        "norm_max": max(norms),
        "norm_min": min(norms),
        "set_digest": stored_digest,
        "space_id": space_id,
        "token_max": max(totals),
        "token_min": min(totals),
    }


def self_test() -> None:
    assert expected_space()["dimension"] == DIMENSION
    assert LINE_PATTERN.fullmatch("[relevance-embedding] result=PASS value=1") is not None
    assert LINE_PATTERN.fullmatch("raw question") is None
    print("relevance_query_embedding_evaluator_self_test=PASS")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cases", type=Path)
    parser.add_argument("--expected-cases-sha256")
    parser.add_argument("--queries", type=Path)
    parser.add_argument("--artifact", type=Path)
    parser.add_argument("--target-result", type=Path)
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    try:
        if arguments.self_test:
            self_test()
            return 0
        if not all((
            arguments.cases, arguments.expected_cases_sha256, arguments.queries,
            arguments.artifact, arguments.target_result,
        )):
            fail("required_argument_missing")
        summary = evaluate(arguments)
    except (EvaluationError, KeyError, TypeError, ValueError, OSError) as exc:
        reason = str(exc) if isinstance(exc, EvaluationError) else "bounded_runtime_failure"
        print(f"relevance_query_embedding_evaluation=blocked;reason={reason}")
        return 1
    print("purpose=evaluate_measured_nomic_relevance_query_embeddings")
    print(
        f"records=12;responsive=6;nonresponsive=6;dimension={DIMENSION};"
        f"token_min={summary['token_min']};token_max={summary['token_max']};over_model_ceiling=0"
    )
    print(
        f"embedding_space_id={summary['space_id']};"
        f"query_embedding_set_digest={summary['set_digest']}"
    )
    print(
        f"artifact_sha256={summary['artifact_sha256']};"
        f"artifact_bytes={summary['artifact_bytes']}"
    )
    print("relevance_query_embedding_evaluation=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
