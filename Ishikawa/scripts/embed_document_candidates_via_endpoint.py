#!/usr/bin/env python3
"""Create measured document embeddings through a pre-existing loopback service."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, NoReturn


MODEL_ID = "nomic-ai/nomic-embed-text-v1.5"
MODEL_REVISION = "e9b6763023c676ca8431644204f50c2b100d9aab"
MODEL_SHA256 = "9e7d262b1fe5ea350782829496efa831901b77486bbde1cea54a4c822d010d5c"
TOKENIZER_SHA256 = "d241a60d5e8f04cc1b2b3e9ef7a4921b27bf526d9f6050ab90f9267a1f9e5c66"
DOCUMENT_PREFIX = "search_document: "
DIMENSION = 768
MAXIMUM_INPUT_TOKENS = 2048
INITIAL_TARGET_TOKENS = 512
NUMERIC_TOLERANCE = 1e-5
MINIMUM_COSINE_SIMILARITY = 1.0 - NUMERIC_TOLERANCE
MAXIMUM_INPUT_BYTES = 16 * 1024 * 1024
MAXIMUM_RESPONSE_BYTES = 64 * 1024 * 1024
MAXIMUM_CREDENTIAL_BYTES = 1024
ALLOWED_LOOPBACK_PORTS = frozenset({8001, 18001})


class StageError(RuntimeError):
    """A stable content-free production-stage failure."""


def fail(reason: str) -> NoReturn:
    print(f"document_embedding_stage=blocked;reason={reason}")
    raise SystemExit(1)


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
    try:
        with path.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
    except OSError as error:
        raise StageError("required_file_unreadable") from error
    return digest.hexdigest()


def read_json(path: Path) -> dict[str, Any]:
    if not path.is_file() or path.is_symlink() or path.stat().st_size > MAXIMUM_INPUT_BYTES:
        raise StageError("input_file_unsafe")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise StageError("input_json_invalid") from error
    if not isinstance(value, dict):
        raise StageError("input_json_invalid")
    return value


def read_credential() -> bytearray:
    value = bytearray()
    while len(value) <= MAXIMUM_CREDENTIAL_BYTES:
        block = os.read(sys.stdin.fileno(), MAXIMUM_CREDENTIAL_BYTES + 1 - len(value))
        if not block:
            break
        value.extend(block)
    if not 32 <= len(value) <= MAXIMUM_CREDENTIAL_BYTES or b"\n" in value or b"\r" in value:
        wipe(value)
        raise StageError("operator_credential_format_invalid")
    return value


def wipe(value: bytearray) -> None:
    for index in range(len(value)):
        value[index] = 0


def validate_loopback_url(value: str, path: str) -> str:
    parsed = urllib.parse.urlsplit(value)
    if (
        parsed.scheme != "http"
        or parsed.hostname != "127.0.0.1"
        or parsed.port not in ALLOWED_LOOPBACK_PORTS
        or parsed.path != path
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
    ):
        raise StageError("endpoint_boundary_invalid")
    return value


def request_json(
    url: str,
    authorization: str,
    *,
    method: str = "POST",
    payload: dict[str, Any] | None = None,
) -> dict[str, Any]:
    body = None if payload is None else canonical_json_bytes(payload)
    headers = {"Accept": "application/json", "Authorization": authorization}
    if body is not None:
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            response_body = response.read(MAXIMUM_RESPONSE_BYTES + 1)
            status = response.status
            content_type = response.headers.get_content_type()
    except urllib.error.HTTPError as error:
        error.read(MAXIMUM_RESPONSE_BYTES + 1)
        raise StageError(f"endpoint_http_{error.code}") from error
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        raise StageError("endpoint_transport_failure") from error
    if status != 200 or content_type != "application/json" or len(response_body) > MAXIMUM_RESPONSE_BYTES:
        raise StageError("endpoint_response_invalid")
    try:
        document = json.loads(response_body.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError) as error:
        raise StageError("endpoint_response_invalid") from error
    if not isinstance(document, dict):
        raise StageError("endpoint_response_invalid")
    return document


def require_hex(value: Any, reason: str) -> str:
    if (
        not isinstance(value, str)
        or len(value) != 64
        or any(character not in "0123456789abcdef" for character in value)
    ):
        raise StageError(reason)
    return value


def validate_candidates(source: dict[str, Any]) -> list[dict[str, Any]]:
    profile = source.get("method_profile")
    digest_input = dict(source)
    observed_digest = digest_input.pop("chunk_candidate_set_digest", None)
    if (
        source.get("schema_version") != 1
        or source.get("artifact_kind") != "non_publishable_structural_chunk_candidates"
        or not isinstance(profile, dict)
        or source.get("method_profile_id")
        != domain_digest("ishikawa.chunk-method-profile.v1", profile)
        or observed_digest != domain_digest("ishikawa.chunk-candidate-set.v1", digest_input)
        or source.get("publication_eligible") is not False
    ):
        raise StageError("chunk_candidate_contract_invalid")
    documents = source.get("documents")
    if not isinstance(documents, list) or not documents:
        raise StageError("chunk_candidate_inventory_invalid")
    candidates: list[dict[str, Any]] = []
    seen: set[str] = set()
    for document in documents:
        if not isinstance(document, dict) or not isinstance(document.get("candidates"), list):
            raise StageError("chunk_candidate_inventory_invalid")
        for candidate in document["candidates"]:
            if not isinstance(candidate, dict):
                raise StageError("chunk_candidate_invalid")
            chunk_id = require_hex(candidate.get("chunk_id"), "chunk_identity_invalid")
            content = candidate.get("content_text")
            context = candidate.get("context_text")
            expected = f"{context}\n\n{content}" if context else content
            if (
                chunk_id in seen
                or not isinstance(content, str)
                or not content.strip()
                or not isinstance(context, str)
                or candidate.get("retrieval_text") != expected
                or candidate.get("method_profile_id") != source.get("method_profile_id")
            ):
                raise StageError("chunk_candidate_invalid")
            seen.add(chunk_id)
            candidates.append(candidate)
    if not candidates or len(candidates) > 4096:
        raise StageError("chunk_candidate_inventory_invalid")
    return candidates


class EndpointClient:
    def __init__(self, embedding_url: str, tokenizer_url: str, credential: bytearray):
        self.embedding_url = validate_loopback_url(embedding_url, "/v1/embeddings")
        self.tokenizer_url = validate_loopback_url(tokenizer_url, "/tokenize")
        try:
            self.authorization = "Bearer " + bytes(credential).decode("utf-8")
        except UnicodeError as error:
            raise StageError("operator_credential_not_utf8") from error
        self.token_cache: dict[tuple[str, bool], int] = {}
        self.tokenization_calls = 0
        self.embedding_calls = 0

    def close(self) -> None:
        self.authorization = ""
        self.token_cache.clear()

    def model_identity(self) -> str:
        base = self.embedding_url.rsplit("/v1/embeddings", 1)[0]
        document = request_json(
            f"{base}/v1/models", self.authorization, method="GET"
        )
        records = document.get("data")
        selected = next(
            (
                item
                for item in records
                if isinstance(item, dict) and item.get("id") == MODEL_ID
            ),
            None,
        ) if isinstance(records, list) else None
        if not isinstance(selected, dict):
            raise StageError("accepted_model_not_advertised")
        maximum = selected.get("max_model_len")
        if maximum not in (None, MAXIMUM_INPUT_TOKENS):
            raise StageError("advertised_model_limit_mismatch")
        safe_identity = {
            key: selected[key]
            for key in sorted(selected)
            if key in {"id", "object", "owned_by", "max_model_len", "root", "parent"}
        }
        return domain_digest("ishikawa.live-embedding-endpoint.v1", safe_identity)

    def token_count(self, text: str, *, add_special_tokens: bool) -> int:
        if text == "" and not add_special_tokens:
            return 0
        key = (text, add_special_tokens)
        if key in self.token_cache:
            return self.token_cache[key]
        document = request_json(
            self.tokenizer_url,
            self.authorization,
            payload={
                "add_special_tokens": add_special_tokens,
                "model": MODEL_ID,
                "prompt": text,
                "return_token_strs": False,
            },
        )
        if set(document) not in (
            {"count", "max_model_len", "tokens"},
            {"count", "max_model_len", "tokens", "token_strs"},
        ):
            raise StageError("tokenizer_schema_invalid")
        if "token_strs" in document and document["token_strs"] not in (None, []):
            raise StageError("tokenizer_schema_invalid")
        count = document.get("count")
        maximum = document.get("max_model_len")
        tokens = document.get("tokens")
        if (
            type(count) is not int
            or count < 1
            or type(maximum) is not int
            or maximum < MAXIMUM_INPUT_TOKENS
            or not isinstance(tokens, list)
            or len(tokens) != count
            or any(type(item) is not int or item < 0 for item in tokens)
        ):
            raise StageError("tokenizer_result_invalid")
        self.token_cache[key] = count
        self.tokenization_calls += 1
        return count

    def embeddings(self, inputs: list[str]) -> tuple[list[list[float]], int]:
        document = request_json(
            self.embedding_url,
            self.authorization,
            payload={"model": MODEL_ID, "input": inputs},
        )
        self.embedding_calls += 1
        if document.get("model") != MODEL_ID:
            raise StageError("embedding_model_mismatch")
        records = document.get("data")
        if not isinstance(records, list) or len(records) != len(inputs):
            raise StageError("embedding_cardinality_mismatch")
        ordered: list[list[float] | None] = [None] * len(inputs)
        for record in records:
            if not isinstance(record, dict):
                raise StageError("embedding_record_invalid")
            index = record.get("index")
            vector = record.get("embedding")
            if (
                type(index) is not int
                or not 0 <= index < len(inputs)
                or ordered[index] is not None
                or not isinstance(vector, list)
                or len(vector) != DIMENSION
                or any(
                    not isinstance(item, (int, float))
                    or isinstance(item, bool)
                    or not math.isfinite(float(item))
                    for item in vector
                )
            ):
                raise StageError("embedding_record_invalid")
            ordered[index] = [float(item) for item in vector]
        usage = document.get("usage")
        prompt_tokens = usage.get("prompt_tokens") if isinstance(usage, dict) else None
        if type(prompt_tokens) is not int or prompt_tokens <= 0 or any(item is None for item in ordered):
            raise StageError("embedding_usage_invalid")
        return [item for item in ordered if item is not None], prompt_tokens


def vector_norm(vector: list[float]) -> float:
    return math.sqrt(sum(value * value for value in vector))


def cosine_similarity(left: list[float], right: list[float]) -> float:
    if len(left) != len(right) or not left:
        raise StageError("repeat_embedding_dimension_mismatch")
    left_norm = vector_norm(left)
    right_norm = vector_norm(right)
    if left_norm == 0.0 or right_norm == 0.0:
        raise StageError("repeat_embedding_zero_vector")
    value = sum(
        left_value * right_value
        for left_value, right_value in zip(left, right, strict=True)
    ) / (
        left_norm * right_norm
    )
    if not math.isfinite(value):
        raise StageError("repeat_embedding_cosine_invalid")
    return min(1.0, max(-1.0, value))


def write_exclusive(path: Path, payload: bytes) -> None:
    if not path.is_absolute() or path.exists() or path.is_symlink() or not path.parent.is_dir():
        raise StageError("output_path_unsafe")
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)


def build_artifact(
    source: dict[str, Any],
    source_sha256: str,
    candidates: list[dict[str, Any]],
    client: EndpointClient,
    runtime_identity: str,
    batch_size: int,
) -> tuple[dict[str, Any], dict[str, Any]]:
    inputs = [DOCUMENT_PREFIX + item["retrieval_text"] for item in candidates]
    measurements = {
        "total_with_special": [client.token_count(item, add_special_tokens=True) for item in inputs],
        "total_without_special": [client.token_count(item, add_special_tokens=False) for item in inputs],
        "content_without_special": [client.token_count(item["content_text"], add_special_tokens=False) for item in candidates],
        "context_without_special": [client.token_count(item["context_text"], add_special_tokens=False) for item in candidates],
        "prefix_without_special": [client.token_count(DOCUMENT_PREFIX, add_special_tokens=False)] * len(candidates),
    }
    if any(value > MAXIMUM_INPUT_TOKENS for value in measurements["total_with_special"]):
        raise StageError("candidate_exceeds_model_token_ceiling")
    for index in range(len(candidates)):
        component_total = (
            measurements["content_without_special"][index]
            + measurements["context_without_special"][index]
            + measurements["prefix_without_special"][index]
        )
        if component_total != measurements["total_without_special"][index]:
            raise StageError("token_bucket_accounting_mismatch")

    vectors: list[list[float]] = []
    observed_usage = 0
    first_batch_inputs: list[str] | None = None
    first_batch_vectors: list[list[float]] | None = None
    first_batch_expected_usage = 0
    for start in range(0, len(inputs), batch_size):
        batch_inputs = inputs[start : start + batch_size]
        batch_vectors, usage = client.embeddings(batch_inputs)
        expected_usage = sum(measurements["total_with_special"][start : start + batch_size])
        if usage != expected_usage:
            raise StageError("service_tokenizer_count_disagreement")
        if first_batch_inputs is None:
            first_batch_inputs = list(batch_inputs)
            first_batch_vectors = [list(vector) for vector in batch_vectors]
            first_batch_expected_usage = expected_usage
        vectors.extend(batch_vectors)
        observed_usage += usage
    if first_batch_inputs is None or first_batch_vectors is None:
        raise StageError("embedding_batch_missing")
    repeat, repeat_usage = client.embeddings(first_batch_inputs)
    if repeat_usage != first_batch_expected_usage:
        raise StageError("repeat_token_count_disagreement")
    repeat_delta = max(
        abs(left - right)
        for original, repeated in zip(first_batch_vectors, repeat, strict=True)
        for left, right in zip(original, repeated, strict=True)
    )
    repeat_minimum_cosine = min(
        cosine_similarity(original, repeated)
        for original, repeated in zip(first_batch_vectors, repeat, strict=True)
    )
    repeat_maximum_cosine_distance = 1.0 - repeat_minimum_cosine

    embedding_space = {
        "schema_version": 1,
        "model_id": MODEL_ID,
        "model_revision": MODEL_REVISION,
        "model_sha256": MODEL_SHA256,
        "tokenizer_sha256": TOKENIZER_SHA256,
        "pooling": "mean_tokens",
        "document_prefix": DOCUMENT_PREFIX,
        "dimension": DIMENSION,
        "maximum_input_tokens": MAXIMUM_INPUT_TOKENS,
        "initial_target_tokens": INITIAL_TARGET_TOKENS,
        "token_count_mode": "with_special_tokens",
        "vector_transform": "none",
        "distance": "cosine",
        "numeric_tolerance": NUMERIC_TOLERANCE,
    }
    embedding_space_id = domain_digest("ishikawa.embedding-space.v1", embedding_space)
    records = []
    norms = []
    for index, (candidate, exact_input, vector) in enumerate(zip(candidates, inputs, vectors, strict=True)):
        submitted_digest = domain_digest("ishikawa.embedding-input.v1", {"input": exact_input})
        norm = vector_norm(vector)
        if norm == 0.0:
            raise StageError("zero_embedding_vector")
        norms.append(norm)
        records.append({
            "schema_version": 1,
            "embedding_artifact_id": domain_digest(
                "ishikawa.embedding-artifact.v1",
                {
                    "chunk_id": candidate["chunk_id"],
                    "embedding_space_id": embedding_space_id,
                    "submitted_input_digest": submitted_digest,
                },
            ),
            "chunk_id": candidate["chunk_id"],
            "embedding_space_id": embedding_space_id,
            "submitted_input_digest": submitted_digest,
            "token_accounting": {
                "tokenizer_sha256": TOKENIZER_SHA256,
                "count_mode": "with_special_tokens",
                "content_tokens_without_special": measurements["content_without_special"][index],
                "context_tokens_without_special": measurements["context_without_special"][index],
                "prefix_tokens_without_special": measurements["prefix_without_special"][index],
                "total_without_special": measurements["total_without_special"][index],
                "total_embedding_input_tokens": measurements["total_with_special"][index],
            },
            "target_evaluation": {
                "initial_target_tokens": INITIAL_TARGET_TOKENS,
                "within_initial_target": measurements["total_with_special"][index] <= INITIAL_TARGET_TOKENS,
                "within_model_ceiling": True,
            },
            "vector": vector,
            "vector_dimension": DIMENSION,
            "vector_transform": "none",
            "vector_norm": norm,
        })
    artifact: dict[str, Any] = {
        "schema_version": 1,
        "artifact_kind": "measured_nomic_chunk_embeddings",
        "source_chunk_candidate_sha256": source_sha256,
        "source_chunk_candidate_set_digest": source["chunk_candidate_set_digest"],
        "source_method_profile_id": source["method_profile_id"],
        "embedding_space": embedding_space,
        "embedding_space_id": embedding_space_id,
        "runtime_identity_digest": runtime_identity,
        "publication_eligible": False,
        "publication_blocker": "retrieval_profile_calibration_pending",
        "records": records,
    }
    artifact["embedding_set_digest"] = domain_digest("ishikawa.embedding-set.v1", artifact)
    return artifact, {
        "candidates": len(records),
        "token_min": min(measurements["total_with_special"]),
        "token_max": max(measurements["total_with_special"]),
        "observed_usage": observed_usage,
        "repeat_delta": repeat_delta,
        "repeat_cardinality": len(first_batch_inputs),
        "repeat_minimum_cosine": repeat_minimum_cosine,
        "repeat_maximum_cosine_distance": repeat_maximum_cosine_distance,
        "repeat_within_tolerance": repeat_minimum_cosine >= MINIMUM_COSINE_SIMILARITY,
        "norm_min": min(norms),
        "norm_max": max(norms),
    }


def self_test() -> None:
    assert canonical_json_bytes({"b": 2, "a": 1}) == b'{"a":1,"b":2}'
    assert domain_digest("test", {"a": 1}) == domain_digest("test", {"a": 1})
    assert math.isclose(vector_norm([3.0, 4.0]), 5.0)
    assert math.isclose(cosine_similarity([1.0, 0.0], [1.0, 0.0]), 1.0)
    assert math.isclose(cosine_similarity([1.0, 0.0], [0.0, 1.0]), 0.0)
    assert validate_loopback_url("http://127.0.0.1:8001/tokenize", "/tokenize")
    assert validate_loopback_url("http://127.0.0.1:18001/tokenize", "/tokenize")
    print("document_embedding_endpoint_producer_self_test=pass")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path)
    parser.add_argument("--expected-input-sha256")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--embedding-url", default="http://127.0.0.1:8001/v1/embeddings")
    parser.add_argument("--tokenizer-url", default="http://127.0.0.1:8001/tokenize")
    parser.add_argument("--batch-size", type=int, default=16)
    parser.add_argument("--credential-stdin", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
        return
    try:
        if not arguments.credential_stdin or not arguments.input or not arguments.expected_input_sha256 or not arguments.output:
            raise StageError("required_argument_missing")
        if not 1 <= arguments.batch_size <= 64:
            raise StageError("batch_size_invalid")
        expected_sha256 = require_hex(arguments.expected_input_sha256, "expected_input_identity_invalid")
        if sha256_file(arguments.input) != expected_sha256:
            raise StageError("chunk_candidate_identity_mismatch")
        source = read_json(arguments.input)
        candidates = validate_candidates(source)
        credential = read_credential()
        client: EndpointClient | None = None
        try:
            client = EndpointClient(
                arguments.embedding_url,
                arguments.tokenizer_url,
                credential,
            )
            runtime_identity = client.model_identity()
            artifact, summary = build_artifact(
                source,
                expected_sha256,
                candidates,
                client,
                runtime_identity,
                arguments.batch_size,
            )
            tokenization_calls = client.tokenization_calls
            embedding_calls = client.embedding_calls
        finally:
            if client is not None:
                client.close()
            wipe(credential)
        payload = canonical_json_bytes(artifact)
        write_exclusive(arguments.output, payload)
        print("purpose=embed_document_chunk_candidates_via_preexisting_loopback_endpoint")
        print(
            f"documents={len(source['documents'])};candidates={summary['candidates']};"
            f"embedding_dimension={DIMENSION}"
        )
        print(
            f"token_min={summary['token_min']};token_max={summary['token_max']};"
            f"observed_usage={summary['observed_usage']}"
        )
        print(
            f"tokenization_calls={tokenization_calls};embedding_calls={embedding_calls};"
            f"repeat_request_cardinality={summary['repeat_cardinality']};"
            f"repeat_max_abs_delta={summary['repeat_delta']:.9g};"
            f"repeat_min_cosine_similarity={summary['repeat_minimum_cosine']:.12g};"
            f"repeat_max_cosine_distance={summary['repeat_maximum_cosine_distance']:.12g};"
            f"repeat_within_tolerance={str(summary['repeat_within_tolerance']).lower()}"
        )
        print(
            f"embedding_space_id={artifact['embedding_space_id']};"
            f"embedding_set_digest={artifact['embedding_set_digest']}"
        )
        print(
            f"artifact_sha256={hashlib.sha256(payload).hexdigest()};"
            f"artifact_bytes={len(payload)}"
        )
        print("credentials_retained=false;raw_text_logged=false;vectors_logged=false")
        print("document_embedding_stage=pass")
    except StageError as error:
        fail(str(error))


if __name__ == "__main__":
    main()
