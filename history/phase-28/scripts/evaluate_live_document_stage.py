#!/usr/bin/env python3
"""Evaluate live synthetic document artifacts without emitting source content."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
from typing import Any, NoReturn


MAXIMUM_JSON_BYTES = 128 * 1024 * 1024
COSINE_DISTANCE_TOLERANCE = 1e-5
MINIMUM_COSINE_SIMILARITY = 1.0 - COSINE_DISTANCE_TOLERANCE
COORDINATE_DELTA_DIAGNOSTIC_REFERENCE = 1e-5
EXPECTED_EMBEDDING_SPACE_ID = "fd970d304662357a07f7712639bdc0c70cc7e72b22f04c126acce57a6f9143a3"
EXPECTED_METHOD_PROFILE_ID = "5797961aee919aa73bbd99d6cc188084d57d22839a1d4cff0febc2e73e17b4b0"


def fail(reason: str) -> NoReturn:
    print(f"live_document_stage_evaluation=blocked;reason={reason}")
    raise SystemExit(1)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
    except OSError:
        fail("artifact_unreadable")
    return digest.hexdigest()


def read_json(path: Path) -> dict[str, Any]:
    if (
        not path.is_file()
        or path.is_symlink()
        or path.stat().st_size > MAXIMUM_JSON_BYTES
    ):
        fail("artifact_unsafe")
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail("artifact_json_invalid")
    if not isinstance(document, dict):
        fail("artifact_json_invalid")
    return document


def require_hex(value: Any, reason: str) -> str:
    if (
        not isinstance(value, str)
        or len(value) != 64
        or any(character not in "0123456789abcdef" for character in value)
    ):
        fail(reason)
    return value


def compare_documents(observed: dict[str, Any], accepted: dict[str, Any]) -> None:
    if (
        observed.get("schema_version") != 1
        or observed.get("method") != accepted.get("method")
        or observed.get("transform_rules") != accepted.get("transform_rules")
        or observed.get("source_manifest_sha256") != accepted.get("source_manifest_sha256")
        or observed.get("documents") != accepted.get("documents")
    ):
        fail("normalized_semantic_baseline_mismatch")
    documents = observed["documents"]
    if (
        len(documents) != 6
        or sum(item.get("page_count", 0) for item in documents) != 27
        or sum(len(item.get("blank_pages", [])) for item in documents) != 1
        or sum(len(item.get("units", [])) for item in documents) != 230
    ):
        fail("normalized_inventory_mismatch")


def flatten_candidates(document: dict[str, Any]) -> list[dict[str, Any]]:
    documents = document.get("documents")
    if not isinstance(documents, list):
        fail("chunk_inventory_invalid")
    values: list[dict[str, Any]] = []
    for source in documents:
        candidates = source.get("candidates") if isinstance(source, dict) else None
        if not isinstance(candidates, list) or any(not isinstance(item, dict) for item in candidates):
            fail("chunk_inventory_invalid")
        values.extend(candidates)
    return values


def compare_chunks(observed: dict[str, Any], accepted: dict[str, Any]) -> list[dict[str, Any]]:
    if (
        observed.get("schema_version") != 1
        or observed.get("artifact_kind") != "non_publishable_structural_chunk_candidates"
        or observed.get("method_profile_id") != EXPECTED_METHOD_PROFILE_ID
        or observed.get("method_profile") != accepted.get("method_profile")
        or observed.get("documents") != accepted.get("documents")
        or observed.get("publication_eligible") is not False
    ):
        fail("chunk_semantic_baseline_mismatch")
    require_hex(observed.get("chunk_candidate_set_digest"), "chunk_set_identity_invalid")
    candidates = flatten_candidates(observed)
    if len(candidates) != 126 or len({item.get("chunk_id") for item in candidates}) != 126:
        fail("chunk_inventory_invalid")
    return candidates


def compare_embeddings(
    observed: dict[str, Any], accepted: dict[str, Any]
) -> tuple[float, float]:
    if (
        observed.get("schema_version") != 1
        or observed.get("artifact_kind") != "measured_nomic_chunk_embeddings"
        or observed.get("embedding_space_id") != EXPECTED_EMBEDDING_SPACE_ID
        or observed.get("embedding_space") != accepted.get("embedding_space")
        or observed.get("source_method_profile_id") != EXPECTED_METHOD_PROFILE_ID
        or observed.get("publication_eligible") is not False
        or observed.get("publication_blocker") != "retrieval_profile_calibration_pending"
    ):
        fail("embedding_contract_mismatch")
    observed_records = observed.get("records")
    accepted_records = accepted.get("records")
    if (
        not isinstance(observed_records, list)
        or not isinstance(accepted_records, list)
        or len(observed_records) != 126
        or len(accepted_records) != 126
    ):
        fail("embedding_inventory_mismatch")
    accepted_by_chunk = {
        item.get("chunk_id"): item
        for item in accepted_records
        if isinstance(item, dict)
    }
    if len(accepted_by_chunk) != 126:
        fail("accepted_embedding_inventory_invalid")
    maximum_delta = 0.0
    minimum_cosine_similarity = 1.0
    seen: set[str] = set()
    for item in observed_records:
        if not isinstance(item, dict):
            fail("embedding_record_invalid")
        chunk_id = item.get("chunk_id")
        reference = accepted_by_chunk.get(chunk_id)
        if not isinstance(chunk_id, str) or not isinstance(reference, dict) or chunk_id in seen:
            fail("embedding_record_identity_mismatch")
        seen.add(chunk_id)
        for field in (
            "schema_version",
            "embedding_artifact_id",
            "chunk_id",
            "embedding_space_id",
            "submitted_input_digest",
            "token_accounting",
            "target_evaluation",
            "vector_dimension",
            "vector_transform",
        ):
            if item.get(field) != reference.get(field):
                fail("embedding_record_metadata_mismatch")
        vector = item.get("vector")
        expected_vector = reference.get("vector")
        if (
            not isinstance(vector, list)
            or not isinstance(expected_vector, list)
            or len(vector) != 768
            or len(expected_vector) != 768
        ):
            fail("embedding_vector_invalid")
        dot_product = 0.0
        observed_squared_norm = 0.0
        accepted_squared_norm = 0.0
        for left, right in zip(vector, expected_vector, strict=True):
            if (
                not isinstance(left, (int, float))
                or isinstance(left, bool)
                or not isinstance(right, (int, float))
                or isinstance(right, bool)
                or not math.isfinite(float(left))
                or not math.isfinite(float(right))
            ):
                fail("embedding_vector_invalid")
            observed_value = float(left)
            accepted_value = float(right)
            maximum_delta = max(maximum_delta, abs(observed_value - accepted_value))
            dot_product += observed_value * accepted_value
            observed_squared_norm += observed_value * observed_value
            accepted_squared_norm += accepted_value * accepted_value
        if observed_squared_norm == 0.0 or accepted_squared_norm == 0.0:
            fail("embedding_vector_invalid")
        cosine_similarity = dot_product / math.sqrt(
            observed_squared_norm * accepted_squared_norm
        )
        if not math.isfinite(cosine_similarity):
            fail("embedding_vector_invalid")
        cosine_similarity = max(-1.0, min(1.0, cosine_similarity))
        minimum_cosine_similarity = min(minimum_cosine_similarity, cosine_similarity)
        observed_norm = item.get("vector_norm")
        if not isinstance(observed_norm, (int, float)) or not math.isfinite(float(observed_norm)):
            fail("embedding_vector_invalid")
    if seen != set(accepted_by_chunk):
        fail("embedding_record_identity_mismatch")
    return maximum_delta, minimum_cosine_similarity


def write_artifact(path: Path, document: dict[str, Any]) -> tuple[str, int]:
    if path.exists() or path.is_symlink() or not path.parent.is_dir():
        fail("output_path_unsafe")
    payload = json.dumps(
        document,
        ensure_ascii=False,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8") + b"\n"
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)
    return hashlib.sha256(payload).hexdigest(), len(payload)


def self_test() -> None:
    assert require_hex("a" * 64, "bad") == "a" * 64
    sample = {"documents": [{"candidates": [{"chunk_id": "a"}]}]}
    assert flatten_candidates(sample) == [{"chunk_id": "a"}]
    print("live_document_stage_evaluator_self_test=pass")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--normalized", type=Path)
    parser.add_argument("--chunks", type=Path)
    parser.add_argument("--embeddings", type=Path)
    parser.add_argument("--accepted-normalized", type=Path)
    parser.add_argument("--accepted-chunks", type=Path)
    parser.add_argument("--accepted-embeddings", type=Path)
    parser.add_argument("--extraction", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
        return
    required = (
        arguments.normalized,
        arguments.chunks,
        arguments.embeddings,
        arguments.accepted_normalized,
        arguments.accepted_chunks,
        arguments.accepted_embeddings,
        arguments.extraction,
        arguments.output,
    )
    if any(item is None for item in required):
        fail("required_argument_missing")
    assert arguments.extraction is not None
    if not arguments.extraction.is_file() or arguments.extraction.is_symlink():
        fail("extraction_artifact_unsafe")

    observed_normalized = read_json(arguments.normalized)
    accepted_normalized = read_json(arguments.accepted_normalized)
    compare_documents(observed_normalized, accepted_normalized)
    observed_chunks = read_json(arguments.chunks)
    accepted_chunks = read_json(arguments.accepted_chunks)
    candidates = compare_chunks(observed_chunks, accepted_chunks)
    observed_embeddings = read_json(arguments.embeddings)
    accepted_embeddings = read_json(arguments.accepted_embeddings)
    maximum_delta, minimum_cosine_similarity = compare_embeddings(
        observed_embeddings, accepted_embeddings
    )
    maximum_cosine_distance = max(0.0, 1.0 - minimum_cosine_similarity)
    cosine_baseline = (
        "pass"
        if maximum_cosine_distance <= COSINE_DISTANCE_TOLERANCE
        else "blocked"
    )
    coordinate_reference_exceeded = (
        maximum_delta > COORDINATE_DELTA_DIAGNOSTIC_REFERENCE
    )

    artifact = {
        "schema_version": 1,
        "purpose": "live_document_stage_qualification",
        "source_fixture": "fully_synthetic_no_source_text",
        "documents": 6,
        "pages": 27,
        "blank_pages": 1,
        "normalized_structural_units": 230,
        "chunk_candidates": len(candidates),
        "embedding_records": len(observed_embeddings["records"]),
        "embedding_dimension": 768,
        "method_profile_id": EXPECTED_METHOD_PROFILE_ID,
        "embedding_space_id": EXPECTED_EMBEDDING_SPACE_ID,
        "maximum_vector_coordinate_delta": maximum_delta,
        "coordinate_delta_diagnostic_reference": COORDINATE_DELTA_DIAGNOSTIC_REFERENCE,
        "coordinate_reference_exceeded": coordinate_reference_exceeded,
        "minimum_vector_cosine_similarity": minimum_cosine_similarity,
        "maximum_vector_cosine_distance": maximum_cosine_distance,
        "cosine_distance_tolerance": COSINE_DISTANCE_TOLERANCE,
        "extraction_sha256": sha256_file(arguments.extraction),
        "normalized_sha256": sha256_file(arguments.normalized),
        "chunks_sha256": sha256_file(arguments.chunks),
        "embeddings_sha256": sha256_file(arguments.embeddings),
        "semantic_baseline": "pass",
        "cosine_baseline": cosine_baseline,
        "raw_text_logged": False,
        "vectors_logged": False,
    }
    artifact_sha256, artifact_bytes = write_artifact(arguments.output, artifact)
    print("purpose=evaluate_live_document_stage")
    print("source_fixture=fully_synthetic_no_source_text;documents=6;pages=27;blank_pages=1")
    print("normalized_structural_units=230;chunk_candidates=126;embedding_records=126")
    print(
        f"method_profile_id={EXPECTED_METHOD_PROFILE_ID};"
        f"embedding_space_id={EXPECTED_EMBEDDING_SPACE_ID}"
    )
    print(
        f"maximum_vector_coordinate_delta={maximum_delta:.9g};"
        f"coordinate_delta_diagnostic_reference={COORDINATE_DELTA_DIAGNOSTIC_REFERENCE:.9g};"
        f"coordinate_reference_exceeded={str(coordinate_reference_exceeded).lower()}"
    )
    print(
        f"minimum_vector_cosine_similarity={minimum_cosine_similarity:.12g};"
        f"maximum_vector_cosine_distance={maximum_cosine_distance:.12g};"
        f"cosine_distance_tolerance={COSINE_DISTANCE_TOLERANCE:.9g}"
    )
    print(
        f"semantic_baseline=pass;cosine_baseline={cosine_baseline};"
        "raw_text_logged=false;vectors_logged=false"
    )
    print(f"qualification_artifact_sha256={artifact_sha256};qualification_artifact_bytes={artifact_bytes}")
    if cosine_baseline != "pass":
        fail("embedding_cosine_baseline_mismatch")
    print("live_document_stage_evaluation=pass")


if __name__ == "__main__":
    main()
