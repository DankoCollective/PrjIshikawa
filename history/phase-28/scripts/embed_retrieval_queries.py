#!/usr/bin/env python3
"""Create measured query embeddings for an accepted synthetic retrieval set.

This target-local helper validates the accepted Nomic runtime, excludes cases
marked for abstention, measures the exact ``search_query: `` inputs with the
authoritative tokenizer, calls the loopback embedding endpoint, and writes one
protected artifact. It emits content-free status only.
"""

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

# Set this before importing the shared target helper so attended root execution
# cannot leave a root-owned bytecode cache in the operator-owned staging tree.
sys.dont_write_bytecode = True

from qualify_chunk_embeddings import (
    DEFAULT_BASE_URL,
    DEFAULT_CONTAINER,
    DEFAULT_MODEL_ROOT,
    EXPECTED_DIMENSION,
    EXPECTED_LICENSE,
    EXPECTED_MAX_MODEL_LEN,
    EXPECTED_MODEL_ID,
    EXPECTED_MODEL_REVISION,
    EXPECTED_MODEL_SHA256,
    EXPECTED_TOKENIZER_SHA256,
    NomicClient,
    QualificationError,
    canonical_json_bytes,
    domain_digest,
    maximum_delta,
    require_hex_digest,
    run,
    sha256_file,
    validate_artifacts,
    validate_runtime,
    vector_norm,
    wipe,
    write_exclusive,
    read_operator_credential,
)

QUERY_PREFIX = "search_query: "
DOCUMENT_PREFIX = "search_document: "
EXPECTED_CASE_COUNT = 7
EXPECTED_ELIGIBLE_COUNT = 6
EXPECTED_EXCLUDED_COUNT = 1
INITIAL_TARGET_TOKENS = 512
NUMERIC_TOLERANCE = 1e-5
MAX_INPUT_BYTES = 1024 * 1024
DEFAULT_BATCH_SIZE = 16
CASE_ID = re.compile(r"^Q-[0-9]{3}$")


class QueryEmbeddingError(RuntimeError):
    """A stable query-embedding qualification failure."""


def fail(reason: str) -> NoReturn:
    raise QueryEmbeddingError(reason)


def emit(**fields: object) -> None:
    print(
        "[query-embedding] "
        + " ".join(f"{key}={value}" for key, value in fields.items()),
        flush=True,
    )


def load_cases(path: Path, expected_sha256: str) -> tuple[list[dict[str, Any]], int]:
    if not path.is_file() or path.is_symlink() or path.stat().st_size > MAX_INPUT_BYTES:
        fail("unsafe_or_oversized_retrieval_case_input")
    if sha256_file(path) != expected_sha256:
        fail("retrieval_case_file_identity_mismatch")
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail("retrieval_case_json_invalid")
    if not isinstance(document, list) or len(document) != EXPECTED_CASE_COUNT:
        fail("retrieval_case_inventory_invalid")
    eligible: list[dict[str, Any]] = []
    excluded = 0
    seen: set[str] = set()
    for case in document:
        if not isinstance(case, dict):
            fail("retrieval_case_invalid")
        case_id = case.get("id")
        intent = case.get("intent")
        question = case.get("query")
        if (
            not isinstance(case_id, str)
            or CASE_ID.fullmatch(case_id) is None
            or case_id in seen
            or not isinstance(intent, str)
            or not intent
            or not isinstance(question, str)
            or not question.strip()
        ):
            fail("retrieval_case_contract_invalid")
        seen.add(case_id)
        if case.get("expected_abstention") is True:
            excluded += 1
            continue
        citations = case.get("required_citations")
        if (
            not isinstance(citations, list)
            or not citations
            or any(not isinstance(item, str) or not item for item in citations)
        ):
            fail("eligible_retrieval_case_citations_invalid")
        eligible.append({"case_id": case_id, "intent": intent, "question": question})
    if len(eligible) != EXPECTED_ELIGIBLE_COUNT or excluded != EXPECTED_EXCLUDED_COUNT:
        fail("retrieval_case_eligibility_count_mismatch")
    return eligible, excluded


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
        "total_with_special",
        "total_without_special",
        "question_without_special",
        "prefix_without_special",
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
    cases: list[dict[str, Any]],
    excluded: int,
    source_sha256: str,
    measurements: dict[str, list[int]],
    client: NomicClient,
    runtime_identity: str,
    batch_size: int,
) -> tuple[dict[str, Any], dict[str, Any]]:
    totals = measurements["total_with_special"]
    if any(value > EXPECTED_MAX_MODEL_LEN for value in totals):
        fail("query_exceeds_model_token_ceiling")
    inputs = [QUERY_PREFIX + case["question"] for case in cases]
    vectors: list[list[float]] = []
    observed_usage = 0
    for start in range(0, len(inputs), batch_size):
        stop = min(start + batch_size, len(inputs))
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
            "ishikawa.query-embedding.v1",
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
            "intent": case["intent"],
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
        "artifact_kind": "measured_nomic_retrieval_query_embeddings",
        "source_retrieval_cases_sha256": source_sha256,
        "eligible_case_count": len(records),
        "excluded_abstention_case_count": excluded,
        "query_method": {
            "schema_version": 1,
            "query_prefix": QUERY_PREFIX,
            "eligibility_rule": "exclude_expected_abstention_true",
        },
        "embedding_space": space,
        "embedding_space_id": space_id,
        "runtime_identity_digest": domain_digest(
            "ishikawa.embedding-runtime-observation.v1", {"runtime": runtime_identity}
        ),
        "calibration_eligible": True,
        "publication_eligible": False,
        "publication_blocker": "retrieval_calibration_pending",
        "records": records,
    }
    artifact["query_embedding_set_digest"] = domain_digest(
        "ishikawa.query-embedding-set.v1", artifact
    )
    return artifact, {
        "queries": len(records),
        "excluded": excluded,
        "batches": math.ceil(len(records) / batch_size),
        "observed_usage": observed_usage,
        "token_min": min(totals),
        "token_max": max(totals),
        "norm_min": min(norms),
        "norm_max": max(norms),
        "repeat_delta": repeat_delta,
    }


def execute(arguments: argparse.Namespace) -> None:
    if os.geteuid() != 0:
        fail("root_execution_required")
    if not arguments.credential_stdin:
        fail("attended_credential_pipe_required")
    if not 1 <= arguments.batch_size <= 64:
        fail("batch_size_out_of_range")
    expected_input_sha256 = require_hex_digest(
        arguments.expected_input_sha256, "expected_input_identity_invalid"
    )
    cases, excluded = load_cases(arguments.input, expected_input_sha256)

    emit(schema="retrieval-query-embedding/v1", operation="measure_and_embed")
    validate_artifacts(arguments.model_root)
    runtime_identity = validate_runtime(arguments.container)
    secret = read_operator_credential()
    client: NomicClient | None = None
    try:
        client = NomicClient(arguments.base_url, secret)
        client.model_ready()
        measurements = tokenizer_measure(
            arguments.container, [case["question"] for case in cases]
        )
        artifact, summary = create_artifact(
            cases,
            excluded,
            expected_input_sha256,
            measurements,
            client,
            runtime_identity,
            arguments.batch_size,
        )
    finally:
        if client is not None:
            client.close()
        wipe(secret)

    payload = canonical_json_bytes(artifact)
    write_exclusive(arguments.output, payload)
    emit(
        model_identity="pass",
        tokenizer_identity="pass",
        tokenizer_service_agreement="pass",
        token_count_mode="with_special_tokens",
    )
    emit(
        eligible_queries=summary["queries"],
        excluded_abstention_queries=summary["excluded"],
        batches=summary["batches"],
        token_min=summary["token_min"],
        token_max=summary["token_max"],
        over_model_ceiling=0,
    )
    emit(
        embeddings="pass",
        dimension=EXPECTED_DIMENSION,
        finite_vectors="pass",
        vector_transform="none",
        repeat_max_abs_delta=f"{summary['repeat_delta']:.9g}",
        numeric_tolerance=f"{NUMERIC_TOLERANCE:.9g}",
        vector_norm_min=f"{summary['norm_min']:.9g}",
        vector_norm_max=f"{summary['norm_max']:.9g}",
    )
    emit(
        embedding_space_id=artifact["embedding_space_id"],
        query_embedding_set_digest=artifact["query_embedding_set_digest"],
        artifact_sha256=hashlib.sha256(payload).hexdigest(),
        artifact_bytes=len(payload),
    )
    emit(
        result="PASS",
        calibration_eligible="true",
        publication_eligible="false",
        next_gate="retrieval_calibration",
        raw_text_logged="false",
        vectors_logged="false",
        credential_recorded="false",
    )


def self_test() -> None:
    space = embedding_space()
    assert space["document_prefix"] == DOCUMENT_PREFIX
    assert domain_digest("test", {"b": 2, "a": 1}) == domain_digest(
        "test", {"a": 1, "b": 2}
    )
    assert CASE_ID.fullmatch("Q-001") is not None
    assert CASE_ID.fullmatch("Q-1") is None
    print("query_embedding_qualifier_self_test=PASS")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path)
    parser.add_argument("--expected-input-sha256")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--model-root", type=Path, default=DEFAULT_MODEL_ROOT)
    parser.add_argument("--container", default=DEFAULT_CONTAINER)
    parser.add_argument("--batch-size", type=int, default=DEFAULT_BATCH_SIZE)
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
    except (QueryEmbeddingError, QualificationError) as exc:
        emit(result="BLOCKED", reason=str(exc))
        return 1
    except (KeyError, TypeError, ValueError, OSError):
        emit(result="BLOCKED", reason="bounded_runtime_failure")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
