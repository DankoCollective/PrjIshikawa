#!/usr/bin/env python3
"""Create measured Nomic embeddings for qualified relevance questions."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import sys
from pathlib import Path
from typing import Any, NoReturn

sys.dont_write_bytecode = True

from qualify_chunk_embeddings import (
    DEFAULT_BASE_URL,
    DEFAULT_CONTAINER,
    DEFAULT_MODEL_ROOT,
    EXPECTED_DIMENSION,
    EXPECTED_MAX_MODEL_LEN,
    NomicClient,
    QualificationError,
    canonical_json_bytes,
    domain_digest,
    maximum_delta,
    read_operator_credential,
    require_hex_digest,
    run,
    sha256_file,
    validate_artifacts,
    validate_runtime,
    vector_norm,
    wipe,
    write_exclusive,
)


QUERY_PREFIX = "search_query: "
DOCUMENT_PREFIX = "search_document: "
EXPECTED_CASE_COUNT = 12
INITIAL_TARGET_TOKENS = 512
NUMERIC_TOLERANCE = 1e-5
MAX_INPUT_BYTES = 1024 * 1024
QUERY_REQUEST_BATCH_SIZE = 1
CASE_ID = re.compile(r"^[RN]-[0-9]{3}$")
HEX = re.compile(r"^[0-9a-f]{64}$")


class RelevanceEmbeddingError(RuntimeError):
    pass


def fail(reason: str) -> NoReturn:
    raise RelevanceEmbeddingError(reason)


def emit(**fields: object) -> None:
    print(
        "[relevance-embedding] "
        + " ".join(f"{key}={value}" for key, value in fields.items()),
        flush=True,
    )


def load_queries(path: Path, expected_sha256: str) -> tuple[list[dict[str, str]], str]:
    if not path.is_file() or path.is_symlink() or path.stat().st_size > MAX_INPUT_BYTES:
        fail("unsafe_or_oversized_query_input")
    if sha256_file(path) != expected_sha256:
        fail("query_input_identity_mismatch")
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail("query_input_json_invalid")
    if not isinstance(document, dict) or set(document) != {
        "artifact_kind", "cases", "query_set_digest", "schema_version", "source_case_set_sha256"
    }:
        fail("query_input_fields_invalid")
    source_identity = document["source_case_set_sha256"]
    if (
        document["schema_version"] != 1
        or document["artifact_kind"] != "relevance_embedding_queries"
        or HEX.fullmatch(source_identity or "") is None
    ):
        fail("query_input_contract_invalid")
    digest_input = dict(document)
    digest_input.pop("query_set_digest")
    if document["query_set_digest"] != domain_digest(
        "ishikawa.relevance-embedding-query-set.v1", digest_input
    ):
        fail("query_set_digest_invalid")
    records = document["cases"]
    if not isinstance(records, list) or len(records) != EXPECTED_CASE_COUNT:
        fail("query_inventory_invalid")
    expected_ids = [f"R-{number:03d}" for number in range(1, 7)] + [
        f"N-{number:03d}" for number in range(1, 7)
    ]
    accepted: list[dict[str, str]] = []
    for record, expected_id in zip(records, expected_ids, strict=True):
        if not isinstance(record, dict) or set(record) != {
            "case_id", "class", "question", "question_digest"
        }:
            fail("query_record_fields_invalid")
        case_id = record["case_id"]
        case_class = record["class"]
        question = record["question"]
        if (
            case_id != expected_id
            or CASE_ID.fullmatch(case_id) is None
            or case_class not in {"responsive", "nonresponsive"}
            or (case_id.startswith("R-") and case_class != "responsive")
            or (case_id.startswith("N-") and case_class != "nonresponsive")
            or not isinstance(question, str)
            or not question.strip()
            or question != question.strip()
            or len(question) > 4096
        ):
            fail("query_record_contract_invalid")
        expected_digest = domain_digest(
            "ishikawa.retrieval-question.v1", {"question": question}
        )
        if record["question_digest"] != expected_digest:
            fail("question_digest_invalid")
        accepted.append({"case_id": case_id, "class": case_class, "question": question})
    return accepted, source_identity


def tokenizer_measure(container: str, questions: list[str]) -> dict[str, list[int]]:
    request = {
        "exact": [QUERY_PREFIX + question for question in questions],
        "question": questions,
        "prefix": [QUERY_PREFIX] * len(questions),
    }
    code = (
        "import json,sys;"
        "from transformers import AutoTokenizer;"
        "x=json.load(sys.stdin);"
        "t=AutoTokenizer.from_pretrained('/models/nomic',local_files_only=True,trust_remote_code=False);"
        "c=lambda v,s:[len(t.encode(i,add_special_tokens=s)) for i in v];"
        "print(json.dumps({'total_with_special':c(x['exact'],True),"
        "'total_without_special':c(x['exact'],False),"
        "'question_without_special':c(x['question'],False),"
        "'prefix_without_special':c(x['prefix'],False)},separators=(',',':')))"
    )
    completed = run(
        ["/usr/bin/docker", "exec", "-i", container, "python3", "-c", code],
        input_bytes=canonical_json_bytes(request),
        timeout=300,
    )
    if completed.returncode != 0:
        fail("authoritative_tokenizer_execution_failed")
    try:
        result = json.loads(completed.stdout)
    except (UnicodeError, json.JSONDecodeError):
        fail("authoritative_tokenizer_output_invalid")
    expected = {
        "total_with_special", "total_without_special",
        "question_without_special", "prefix_without_special",
    }
    if not isinstance(result, dict) or set(result) != expected:
        fail("authoritative_tokenizer_output_invalid")
    for key, values in result.items():
        if (
            not isinstance(values, list)
            or len(values) != len(questions)
            or any(not isinstance(value, int) or value < 0 for value in values)
            or (key.startswith("total_") and any(value <= 0 for value in values))
        ):
            fail("authoritative_tokenizer_counts_invalid")
    return result


def embedding_space() -> dict[str, Any]:
    from qualify_chunk_embeddings import (
        EXPECTED_MODEL_ID, EXPECTED_MODEL_REVISION, EXPECTED_MODEL_SHA256,
        EXPECTED_TOKENIZER_SHA256,
    )
    return {
        "schema_version": 1,
        "model_id": EXPECTED_MODEL_ID,
        "model_revision": EXPECTED_MODEL_REVISION,
        "model_sha256": EXPECTED_MODEL_SHA256,
        "tokenizer_sha256": EXPECTED_TOKENIZER_SHA256,
        "pooling": "mean_tokens",
        "document_prefix": DOCUMENT_PREFIX,
        "dimension": EXPECTED_DIMENSION,
        "maximum_input_tokens": EXPECTED_MAX_MODEL_LEN,
        "initial_target_tokens": INITIAL_TARGET_TOKENS,
        "token_count_mode": "with_special_tokens",
        "vector_transform": "none",
        "distance": "cosine",
        "numeric_tolerance": NUMERIC_TOLERANCE,
    }


def create_artifact(
    cases: list[dict[str, str]],
    source_input_sha256: str,
    source_case_set_sha256: str,
    measurements: dict[str, list[int]],
    client: NomicClient,
    runtime_identity: str,
) -> tuple[dict[str, Any], dict[str, Any]]:
    from qualify_chunk_embeddings import EXPECTED_TOKENIZER_SHA256

    totals = measurements["total_with_special"]
    if any(value > EXPECTED_MAX_MODEL_LEN for value in totals):
        fail("query_exceeds_model_token_ceiling")
    inputs = [QUERY_PREFIX + case["question"] for case in cases]
    vectors: list[list[float]] = []
    observed_usage = 0
    for start in range(0, len(inputs), QUERY_REQUEST_BATCH_SIZE):
        stop = min(start + QUERY_REQUEST_BATCH_SIZE, len(inputs))
        batch_vectors, usage = client.embeddings(inputs[start:stop])
        if usage != sum(totals[start:stop]):
            fail("service_and_tokenizer_count_disagree")
        vectors.extend(batch_vectors)
        observed_usage += usage
    repeat_vectors, repeat_usage = client.embeddings([inputs[0]])
    if repeat_usage != totals[0]:
        fail("repeat_service_and_tokenizer_count_disagree")
    repeat_delta = maximum_delta(vectors[0], repeat_vectors[0])
    if repeat_delta > NUMERIC_TOLERANCE:
        emit(
            repeat_check="blocked",
            repeat_max_abs_delta=f"{repeat_delta:.9g}",
            numeric_tolerance=f"{NUMERIC_TOLERANCE:.9g}",
        )
        fail("repeat_embedding_exceeds_numeric_tolerance")

    space = embedding_space()
    space_id = domain_digest("ishikawa.embedding-space.v1", space)
    records: list[dict[str, Any]] = []
    norms: list[float] = []
    for index, (case, exact_input, vector) in enumerate(zip(cases, inputs, vectors, strict=True)):
        input_digest = domain_digest("ishikawa.embedding-input.v1", {"input": exact_input})
        question_digest = domain_digest(
            "ishikawa.retrieval-question.v1", {"question": case["question"]}
        )
        query_embedding_id = domain_digest(
            "ishikawa.relevance-query-embedding.v1",
            {
                "case_id": case["case_id"],
                "embedding_space_id": space_id,
                "submitted_input_digest": input_digest,
            },
        )
        total_without = measurements["total_without_special"][index]
        special_tokens = totals[index] - total_without
        if special_tokens < 0:
            fail("special_token_count_invalid")
        norm = vector_norm(vector)
        norms.append(norm)
        records.append({
            "schema_version": 1,
            "query_embedding_id": query_embedding_id,
            "case_id": case["case_id"],
            "class": case["class"],
            "question_digest": question_digest,
            "embedding_space_id": space_id,
            "query_prefix": QUERY_PREFIX,
            "submitted_input_digest": input_digest,
            "token_accounting": {
                "tokenizer_sha256": EXPECTED_TOKENIZER_SHA256,
                "count_mode": "with_special_tokens",
                "question_tokens_without_special": measurements["question_without_special"][index],
                "prefix_tokens_without_special": measurements["prefix_without_special"][index],
                "total_without_special": total_without,
                "special_token_count": special_tokens,
                "total_embedding_input_tokens": totals[index],
            },
            "vector": vector,
            "vector_dimension": EXPECTED_DIMENSION,
            "vector_transform": "none",
            "vector_norm": norm,
        })
    artifact: dict[str, Any] = {
        "schema_version": 1,
        "artifact_kind": "measured_nomic_relevance_query_embeddings",
        "source_query_input_sha256": source_input_sha256,
        "source_case_set_sha256": source_case_set_sha256,
        "case_count": len(records),
        "class_counts": {"nonresponsive": 6, "responsive": 6},
        "query_method": {
            "schema_version": 1,
            "query_prefix": QUERY_PREFIX,
            "embedding_request_batch_size": QUERY_REQUEST_BATCH_SIZE,
        },
        "embedding_space": space,
        "embedding_space_id": space_id,
        "runtime_identity_digest": domain_digest(
            "ishikawa.embedding-runtime-observation.v1", {"runtime": runtime_identity}
        ),
        "calibration_eligible": True,
        "publication_eligible": False,
        "publication_blocker": "relevance_retrieval_observation_pending",
        "records": records,
    }
    artifact["query_embedding_set_digest"] = domain_digest(
        "ishikawa.relevance-query-embedding-set.v1", artifact
    )
    return artifact, {
        "batches": math.ceil(len(records) / QUERY_REQUEST_BATCH_SIZE),
        "observed_usage": observed_usage,
        "norm_min": min(norms),
        "norm_max": max(norms),
        "repeat_delta": repeat_delta,
        "token_min": min(totals),
        "token_max": max(totals),
    }


def execute(arguments: argparse.Namespace) -> None:
    if os.geteuid() != 0:
        fail("root_execution_required")
    if not arguments.credential_stdin:
        fail("attended_credential_pipe_required")
    expected_input_sha256 = require_hex_digest(
        arguments.expected_input_sha256, "expected_input_identity_invalid"
    )
    cases, source_case_set_sha256 = load_queries(arguments.input, expected_input_sha256)

    emit(schema="relevance-query-embedding/v1", operation="measure_and_embed")
    validate_artifacts(arguments.model_root)
    runtime_identity = validate_runtime(arguments.container)
    secret = read_operator_credential()
    client: NomicClient | None = None
    try:
        client = NomicClient(arguments.base_url, secret)
        client.model_ready()
        measurements = tokenizer_measure(arguments.container, [case["question"] for case in cases])
        artifact, summary = create_artifact(
            cases, expected_input_sha256, source_case_set_sha256,
            measurements, client, runtime_identity,
        )
    finally:
        if client is not None:
            client.close()
        wipe(secret)

    payload = canonical_json_bytes(artifact)
    write_exclusive(arguments.output, payload)
    emit(
        model_identity="pass", tokenizer_identity="pass",
        tokenizer_service_agreement="pass", token_count_mode="with_special_tokens",
    )
    emit(
        queries=len(cases), responsive=6, nonresponsive=6,
        batches=summary["batches"], token_min=summary["token_min"],
        token_max=summary["token_max"], over_model_ceiling=0,
    )
    emit(
        embeddings="pass", dimension=EXPECTED_DIMENSION, finite_vectors="pass",
        vector_transform="none", repeat_max_abs_delta=f"{summary['repeat_delta']:.9g}",
        numeric_tolerance=f"{NUMERIC_TOLERANCE:.9g}",
        vector_norm_min=f"{summary['norm_min']:.9g}",
        vector_norm_max=f"{summary['norm_max']:.9g}",
    )
    emit(
        embedding_space_id=artifact["embedding_space_id"],
        query_embedding_set_digest=artifact["query_embedding_set_digest"],
        artifact_sha256=hashlib.sha256(payload).hexdigest(), artifact_bytes=len(payload),
    )
    emit(
        result="PASS", calibration_eligible="true", publication_eligible="false",
        next_gate="relevance_retrieval_observation", raw_text_logged="false",
        vectors_logged="false", credential_recorded="false",
    )


def self_test() -> None:
    assert CASE_ID.fullmatch("R-001") is not None
    assert CASE_ID.fullmatch("N-006") is not None
    assert CASE_ID.fullmatch("Q-001") is None
    assert embedding_space()["dimension"] == EXPECTED_DIMENSION
    assert QUERY_REQUEST_BATCH_SIZE == 1
    print("relevance_query_embedding_qualifier_self_test=PASS")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path)
    parser.add_argument("--expected-input-sha256")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--model-root", type=Path, default=DEFAULT_MODEL_ROOT)
    parser.add_argument("--container", default=DEFAULT_CONTAINER)
    parser.add_argument("--credential-stdin", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        if arguments.self_test:
            self_test()
        else:
            if not all((arguments.input, arguments.expected_input_sha256, arguments.output)):
                fail("required_argument_missing")
            execute(arguments)
    except (RelevanceEmbeddingError, QualificationError) as exc:
        emit(result="BLOCKED", reason=str(exc))
        return 1
    except (KeyError, TypeError, ValueError, OSError):
        emit(result="BLOCKED", reason="bounded_runtime_failure")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
