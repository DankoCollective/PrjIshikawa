#!/usr/bin/env python3
"""Validate a returned measured Nomic embedding artifact without logging content."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
from pathlib import Path
from typing import Any, NoReturn


MODEL_ID = "nomic-ai/nomic-embed-text-v1.5"
MODEL_REVISION = "e9b6763023c676ca8431644204f50c2b100d9aab"
MODEL_SHA256 = "9e7d262b1fe5ea350782829496efa831901b77486bbde1cea54a4c822d010d5c"
TOKENIZER_SHA256 = "d241a60d5e8f04cc1b2b3e9ef7a4921b27bf526d9f6050ab90f9267a1f9e5c66"
DOCUMENT_PREFIX = "search_document: "
DIMENSION = 768
MAXIMUM_TOKENS = 2048
TARGET_TOKENS = 512
TOLERANCE = 1e-5
LINE_PATTERN = re.compile(
    r"^\[chunk-embedding\] [A-Za-z0-9_.:/=@+,-]+(?: [A-Za-z0-9_.:/=@+,-]+)*$"
)


class EvaluationError(RuntimeError):
    pass


def fail(reason: str) -> NoReturn:
    raise EvaluationError(reason)


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
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_json(path: Path, maximum_bytes: int) -> dict[str, Any]:
    if not path.is_file() or path.is_symlink() or path.stat().st_size > maximum_bytes:
        fail("unsafe_or_oversized_json")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail("invalid_json")
    if not isinstance(value, dict):
        fail("json_not_object")
    return value


def expected_embedding_space() -> dict[str, Any]:
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
        "vector_transform": "none",
        "publication_eligible": "false",
        "raw_text_logged": "false",
        "vectors_logged": "false",
        "credential_recorded": "false",
    }
    if any(fields.get(key) != value for key, value in required.items()):
        fail("target_result_required_fact_missing")
    return fields


def evaluate(arguments: argparse.Namespace) -> dict[str, Any]:
    if sha256_file(arguments.candidates) != arguments.expected_candidate_sha256:
        fail("candidate_file_identity_mismatch")
    candidates_document = load_json(arguments.candidates, 16 * 1024 * 1024)
    artifact = load_json(arguments.artifact, 256 * 1024 * 1024)
    result_fields = parse_target_result(arguments.target_result)
    method_profile = candidates_document.get("method_profile")
    method_profile_id = candidates_document.get("method_profile_id")
    candidate_set_digest = candidates_document.get("chunk_candidate_set_digest")
    digest_input = dict(candidates_document)
    digest_input.pop("chunk_candidate_set_digest", None)
    if (
        not isinstance(method_profile, dict)
        or method_profile_id
        != domain_digest("ishikawa.chunk-method-profile.v1", method_profile)
        or candidate_set_digest
        != domain_digest("ishikawa.chunk-candidate-set.v1", digest_input)
    ):
        fail("candidate_contract_mismatch")
    candidates = {
        candidate["chunk_id"]: candidate
        for document in candidates_document.get("documents", [])
        for candidate in document.get("candidates", [])
    }
    if not candidates or len(candidates) > 4096:
        fail("candidate_count_mismatch")

    space = expected_embedding_space()
    space_id = domain_digest("ishikawa.embedding-space.v1", space)
    if (
        artifact.get("schema_version") != 1
        or artifact.get("artifact_kind") != "measured_nomic_chunk_embeddings"
        or artifact.get("source_chunk_candidate_sha256")
        != arguments.expected_candidate_sha256
        or artifact.get("source_chunk_candidate_set_digest") != candidate_set_digest
        or artifact.get("source_method_profile_id") != method_profile_id
        or artifact.get("embedding_space") != space
        or artifact.get("embedding_space_id") != space_id
        or artifact.get("publication_eligible") is not False
        or artifact.get("publication_blocker") != "retrieval_profile_calibration_pending"
    ):
        fail("embedding_artifact_contract_mismatch")
    records = artifact.get("records")
    if not isinstance(records, list) or len(records) != len(candidates):
        fail("embedding_record_count_mismatch")
    seen: set[str] = set()
    totals: list[int] = []
    norms: list[float] = []
    for record in records:
        if not isinstance(record, dict):
            fail("embedding_record_invalid")
        chunk_id = record.get("chunk_id")
        if chunk_id not in candidates or chunk_id in seen:
            fail("embedding_record_chunk_mapping_invalid")
        seen.add(chunk_id)
        candidate = candidates[chunk_id]
        exact_input = DOCUMENT_PREFIX + candidate["retrieval_text"]
        input_digest = domain_digest("ishikawa.embedding-input.v1", {"input": exact_input})
        embedding_id = domain_digest(
            "ishikawa.embedding-artifact.v1",
            {
                "chunk_id": chunk_id,
                "embedding_space_id": space_id,
                "submitted_input_digest": input_digest,
            },
        )
        if (
            record.get("embedding_artifact_id") != embedding_id
            or record.get("embedding_space_id") != space_id
            or record.get("submitted_input_digest") != input_digest
            or record.get("vector_dimension") != DIMENSION
            or record.get("vector_transform") != "none"
        ):
            fail("embedding_record_identity_invalid")
        accounting = record.get("token_accounting")
        if not isinstance(accounting, dict):
            fail("token_accounting_invalid")
        total = accounting.get("total_embedding_input_tokens")
        component_fields = (
            "content_tokens_without_special",
            "context_tokens_without_special",
            "prefix_tokens_without_special",
            "total_without_special",
        )
        if (
            accounting.get("tokenizer_sha256") != TOKENIZER_SHA256
            or accounting.get("count_mode") != "with_special_tokens"
            or not isinstance(total, int)
            or not 0 < total <= MAXIMUM_TOKENS
            or any(
                not isinstance(accounting.get(field), int) or accounting[field] < 0
                for field in component_fields
            )
        ):
            fail("token_accounting_invalid")
        target = record.get("target_evaluation")
        if target != {
            "initial_target_tokens": TARGET_TOKENS,
            "within_initial_target": total <= TARGET_TOKENS,
            "within_model_ceiling": True,
        }:
            fail("target_evaluation_invalid")
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
        observed_norm = math.sqrt(sum(float(value) ** 2 for value in vector))
        stored_norm = record.get("vector_norm")
        if (
            observed_norm == 0.0
            or not isinstance(stored_norm, (int, float))
            or not math.isclose(observed_norm, float(stored_norm), rel_tol=1e-12, abs_tol=1e-12)
        ):
            fail("embedding_vector_norm_invalid")
        totals.append(total)
        norms.append(observed_norm)
    if seen != set(candidates):
        fail("embedding_record_coverage_incomplete")
    stored_set_digest = artifact.get("embedding_set_digest")
    digest_input = dict(artifact)
    digest_input.pop("embedding_set_digest", None)
    if stored_set_digest != domain_digest("ishikawa.embedding-set.v1", digest_input):
        fail("embedding_set_digest_invalid")

    artifact_sha256 = sha256_file(arguments.artifact)
    artifact_bytes = arguments.artifact.stat().st_size
    expected_result_facts = {
        "candidates": str(len(candidates)),
        "dimension": str(DIMENSION),
        "token_min": str(min(totals)),
        "token_max": str(max(totals)),
        "over_initial_target": str(sum(value > TARGET_TOKENS for value in totals)),
        "over_model_ceiling": "0",
        "embedding_space_id": space_id,
        "embedding_set_digest": stored_set_digest,
        "artifact_sha256": artifact_sha256,
        "artifact_bytes": str(artifact_bytes),
    }
    if any(result_fields.get(key) != value for key, value in expected_result_facts.items()):
        fail("target_result_and_artifact_disagree")
    return {
        "records": len(records),
        "token_min": min(totals),
        "token_max": max(totals),
        "over_target": sum(value > TARGET_TOKENS for value in totals),
        "norm_min": min(norms),
        "norm_max": max(norms),
        "space_id": space_id,
        "set_digest": stored_set_digest,
        "artifact_sha256": artifact_sha256,
        "artifact_bytes": artifact_bytes,
    }


def self_test() -> None:
    space = expected_embedding_space()
    assert space["dimension"] == DIMENSION
    assert space["document_prefix"] == DOCUMENT_PREFIX
    assert domain_digest("test", {"b": 2, "a": 1}) == domain_digest(
        "test", {"a": 1, "b": 2}
    )
    assert LINE_PATTERN.fullmatch("[chunk-embedding] result=PASS value=1") is not None
    assert LINE_PATTERN.fullmatch("raw text") is None
    print("chunk_embedding_evaluator_self_test=PASS")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidates", type=Path)
    parser.add_argument("--expected-candidate-sha256")
    parser.add_argument("--artifact", type=Path)
    parser.add_argument("--target-result", type=Path)
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        if arguments.self_test:
            self_test()
            return 0
        if not all((
            arguments.candidates,
            arguments.expected_candidate_sha256,
            arguments.artifact,
            arguments.target_result,
        )):
            fail("required_argument_missing")
        summary = evaluate(arguments)
    except (EvaluationError, KeyError, TypeError, ValueError, OSError) as exc:
        reason = str(exc) if isinstance(exc, EvaluationError) else "bounded_runtime_failure"
        print(f"chunk_embedding_evaluation=blocked;reason={reason}")
        return 1
    print("purpose=evaluate_measured_nomic_chunk_embeddings")
    print(
        f"records={summary['records']};dimension={DIMENSION};"
        f"token_min={summary['token_min']};token_max={summary['token_max']};"
        f"over_initial_target={summary['over_target']};over_model_ceiling=0"
    )
    print(
        f"embedding_space_id={summary['space_id']};"
        f"embedding_set_digest={summary['set_digest']}"
    )
    print(
        f"artifact_sha256={summary['artifact_sha256']};"
        f"artifact_bytes={summary['artifact_bytes']}"
    )
    print("chunk_embedding_evaluation=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
