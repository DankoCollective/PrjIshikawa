#!/usr/bin/env python3
"""Measure accepted chunk candidates and create Nomic embedding artifacts.

This target-local helper is intentionally self-contained. It validates the
pinned model/runtime, reads one operator-supplied credential from standard
input, measures exact submitted inputs with the tokenizer inside the running
container, calls the loopback OpenAI-compatible embedding endpoint, and writes
one protected JSON artifact. It emits content-free status only.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import socket
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, NoReturn, Sequence


sys.dont_write_bytecode = True

EXPECTED_MODEL_ID = "nomic-ai/nomic-embed-text-v1.5"
EXPECTED_MODEL_REVISION = "e9b6763023c676ca8431644204f50c2b100d9aab"
EXPECTED_MODEL_SHA256 = "9e7d262b1fe5ea350782829496efa831901b77486bbde1cea54a4c822d010d5c"
EXPECTED_TOKENIZER_SHA256 = "d241a60d5e8f04cc1b2b3e9ef7a4921b27bf526d9f6050ab90f9267a1f9e5c66"
EXPECTED_DIMENSION = 768
EXPECTED_MAX_MODEL_LEN = 2048
INITIAL_TARGET_TOKENS = 512
EXPECTED_LICENSE = "apache-2.0"
DOCUMENT_PREFIX = "search_document: "
DEFAULT_BASE_URL = "http://127.0.0.1:8001"
DEFAULT_MODEL_ROOT = Path("/models/nomic")
DEFAULT_CONTAINER = "vllm-nomic"
MAX_INPUT_BYTES = 16 * 1024 * 1024
MAX_RESPONSE_BYTES = 64 * 1024 * 1024
MAX_CREDENTIAL_BYTES = 1024
MAX_CANDIDATES = 4096
DEFAULT_BATCH_SIZE = 16
NUMERIC_TOLERANCE = 1e-5


class QualificationError(RuntimeError):
    """A stable chunk-embedding qualification failure."""


def fail(reason: str) -> NoReturn:
    raise QualificationError(reason)


def emit(**fields: object) -> None:
    print(
        "[chunk-embedding] "
        + " ".join(f"{key}={value}" for key, value in fields.items()),
        flush=True,
    )


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
            for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
                digest.update(block)
    except OSError:
        fail("required_file_unreadable")
    return digest.hexdigest()


def read_json_file(path: Path, maximum_bytes: int) -> dict[str, Any]:
    if not path.is_file() or path.is_symlink():
        fail("unsafe_or_missing_json_input")
    try:
        if path.stat().st_size > maximum_bytes:
            fail("json_input_exceeds_size_limit")
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail("invalid_json_input")
    if not isinstance(value, dict):
        fail("json_input_is_not_object")
    return value


def run(
    arguments: Sequence[str], *, input_bytes: bytes | None = None, timeout: int = 180
) -> subprocess.CompletedProcess[bytes]:
    try:
        return subprocess.run(
            list(arguments),
            input=input_bytes,
            stdin=None if input_bytes is not None else subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired):
        fail("required_command_failed_to_execute")


def require_hex_digest(value: Any, reason: str) -> str:
    if (
        not isinstance(value, str)
        or len(value) != 64
        or any(character not in "0123456789abcdef" for character in value)
    ):
        fail(reason)
    return value


def validate_artifacts(model_root: Path) -> None:
    model_path = model_root / "model.safetensors"
    tokenizer_path = model_root / "tokenizer.json"
    config_path = model_root / "config.json"
    pooling_path = model_root / "1_Pooling" / "config.json"
    readme_path = model_root / "README.md"
    if sha256_file(model_path) != EXPECTED_MODEL_SHA256:
        fail("model_artifact_identity_mismatch")
    if sha256_file(tokenizer_path) != EXPECTED_TOKENIZER_SHA256:
        fail("tokenizer_artifact_identity_mismatch")
    config = read_json_file(config_path, 1024 * 1024)
    pooling = read_json_file(pooling_path, 1024 * 1024)
    if (
        config.get("model_type") != "nomic_bert"
        or config.get("hidden_size") != EXPECTED_DIMENSION
        or config.get("max_position_embeddings") != EXPECTED_MAX_MODEL_LEN
    ):
        fail("model_configuration_mismatch")
    if (
        pooling.get("word_embedding_dimension") != EXPECTED_DIMENSION
        or pooling.get("pooling_mode_mean_tokens") is not True
        or any(
            pooling.get(field) is True
            for field in (
                "pooling_mode_cls_token",
                "pooling_mode_max_tokens",
                "pooling_mode_mean_sqrt_len_tokens",
                "pooling_mode_weightedmean_tokens",
                "pooling_mode_lasttoken",
            )
        )
    ):
        fail("pooling_configuration_mismatch")
    try:
        readme = readme_path.read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        fail("model_license_metadata_unreadable")
    if f"license: {EXPECTED_LICENSE}" not in readme:
        fail("model_license_metadata_mismatch")


def argument_value(arguments: list[str], option: str) -> str | None:
    for index, value in enumerate(arguments):
        if value == option and index + 1 < len(arguments):
            return arguments[index + 1]
        prefix = f"{option}="
        if value.startswith(prefix):
            return value[len(prefix) :]
    return None


def validate_runtime(container: str) -> str:
    inspected = run([
        "/usr/bin/docker",
        "container",
        "inspect",
        "--format",
        "{{json .Args}}|{{.Image}}|{{.Config.Image}}",
        container,
    ])
    if inspected.returncode != 0:
        fail("managed_embedding_container_not_running")
    try:
        args_text, image_id, _ = inspected.stdout.decode("utf-8").strip().split("|", 2)
        container_args = json.loads(args_text)
    except (UnicodeError, ValueError, json.JSONDecodeError):
        fail("embedding_container_identity_malformed")
    if not isinstance(container_args, list) or not all(
        isinstance(item, str) for item in container_args
    ):
        fail("embedding_container_arguments_malformed")
    expected = {
        "--served-model-name": EXPECTED_MODEL_ID,
        "--runner": "pooling",
        "--max-model-len": str(EXPECTED_MAX_MODEL_LEN),
        "--dtype": "auto",
    }
    for option, value in expected.items():
        if argument_value(container_args, option) != value:
            fail("embedding_container_argument_mismatch")
    version = run([
        "/usr/bin/docker", "exec", container, "python3", "-c",
        "import vllm; print(vllm.__version__)",
    ])
    if version.returncode != 0:
        fail("vllm_version_unavailable")
    try:
        vllm_version = version.stdout.decode("utf-8").strip()
    except UnicodeError:
        fail("vllm_version_malformed")
    if not vllm_version or any(character.isspace() for character in vllm_version):
        fail("vllm_version_malformed")
    return f"{image_id}|{vllm_version}"


def read_operator_credential() -> bytearray:
    value = bytearray()
    while len(value) <= MAX_CREDENTIAL_BYTES:
        block = os.read(sys.stdin.fileno(), MAX_CREDENTIAL_BYTES + 1 - len(value))
        if not block:
            break
        value.extend(block)
    if not 32 <= len(value) <= MAX_CREDENTIAL_BYTES or b"\n" in value or b"\r" in value:
        wipe(value)
        fail("operator_credential_format_invalid")
    return value


def wipe(value: bytearray) -> None:
    for index in range(len(value)):
        value[index] = 0


def validate_base_url(value: str) -> str:
    parsed = urllib.parse.urlparse(value)
    if (
        parsed.scheme != "http"
        or parsed.hostname not in {"127.0.0.1", "localhost", "::1"}
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
    ):
        fail("base_url_not_uncredentialed_loopback_http")
    return value.rstrip("/")


class NomicClient:
    def __init__(self, base_url: str, secret: bytearray) -> None:
        self.base_url = validate_base_url(base_url)
        try:
            self.authorization = "Bearer " + bytes(secret).decode("utf-8")
        except UnicodeError:
            fail("operator_credential_not_utf8")

    def close(self) -> None:
        self.authorization = ""

    def request(self, method: str, path: str, payload: dict[str, Any] | None = None) -> dict[str, Any]:
        data = None
        headers = {"Authorization": self.authorization}
        if payload is not None:
            data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(
            f"{self.base_url}{path}", data=data, headers=headers, method=method
        )
        try:
            with urllib.request.urlopen(request, timeout=180) as response:
                body = response.read(MAX_RESPONSE_BYTES + 1)
                status = response.status
        except urllib.error.HTTPError as exc:
            exc.read(MAX_RESPONSE_BYTES + 1)
            fail(f"embedding_endpoint_http_{exc.code}")
        except (urllib.error.URLError, TimeoutError, OSError):
            fail("embedding_endpoint_transport_failure")
        if status != 200 or len(body) > MAX_RESPONSE_BYTES:
            fail("embedding_endpoint_response_invalid")
        try:
            document = json.loads(body)
        except (UnicodeError, json.JSONDecodeError):
            fail("embedding_endpoint_response_not_json")
        if not isinstance(document, dict):
            fail("embedding_endpoint_response_not_object")
        return document

    def model_ready(self) -> None:
        document = self.request("GET", "/v1/models")
        records = document.get("data")
        selected = None
        if isinstance(records, list):
            selected = next(
                (
                    item for item in records
                    if isinstance(item, dict) and item.get("id") == EXPECTED_MODEL_ID
                ),
                None,
            )
        if not isinstance(selected, dict):
            fail("accepted_model_not_advertised")
        if selected.get("max_model_len") not in {None, EXPECTED_MAX_MODEL_LEN}:
            fail("advertised_model_limit_mismatch")

    def embeddings(self, inputs: list[str]) -> tuple[list[list[float]], int]:
        if not inputs or any(not isinstance(item, str) or not item.strip() for item in inputs):
            fail("empty_embedding_input")
        document = self.request(
            "POST", "/v1/embeddings", {"model": EXPECTED_MODEL_ID, "input": inputs}
        )
        if document.get("model") != EXPECTED_MODEL_ID:
            fail("embedding_response_model_mismatch")
        records = document.get("data")
        if not isinstance(records, list) or len(records) != len(inputs):
            fail("embedding_response_cardinality_mismatch")
        ordered: list[list[float] | None] = [None] * len(inputs)
        for record in records:
            if not isinstance(record, dict):
                fail("embedding_response_record_malformed")
            index = record.get("index")
            vector = record.get("embedding")
            if (
                not isinstance(index, int)
                or not 0 <= index < len(inputs)
                or ordered[index] is not None
                or not isinstance(vector, list)
                or len(vector) != EXPECTED_DIMENSION
                or any(
                    not isinstance(item, (int, float))
                    or isinstance(item, bool)
                    or not math.isfinite(float(item))
                    for item in vector
                )
            ):
                fail("embedding_response_vector_invalid")
            converted = [float(item) for item in vector]
            if vector_norm(converted) == 0.0:
                fail("embedding_response_zero_vector")
            ordered[index] = converted
        if any(item is None for item in ordered):
            fail("embedding_response_vector_missing")
        usage = document.get("usage")
        prompt_tokens = usage.get("prompt_tokens") if isinstance(usage, dict) else None
        if not isinstance(prompt_tokens, int) or prompt_tokens <= 0:
            fail("embedding_response_usage_invalid")
        return [item for item in ordered if item is not None], prompt_tokens


def vector_norm(vector: Sequence[float]) -> float:
    return math.sqrt(sum(value * value for value in vector))


def maximum_delta(left: Sequence[float], right: Sequence[float]) -> float:
    if len(left) != len(right):
        fail("repeat_vector_dimension_mismatch")
    return max(abs(a - b) for a, b in zip(left, right, strict=True))


def validate_candidates(document: dict[str, Any]) -> list[dict[str, Any]]:
    profile = document.get("method_profile")
    method_profile_id = document.get("method_profile_id")
    digest_input = dict(document)
    candidate_set_digest = digest_input.pop("chunk_candidate_set_digest", None)
    if (
        document.get("schema_version") != 1
        or document.get("artifact_kind") != "non_publishable_structural_chunk_candidates"
        or not isinstance(profile, dict)
        or method_profile_id != domain_digest("ishikawa.chunk-method-profile.v1", profile)
        or candidate_set_digest != domain_digest("ishikawa.chunk-candidate-set.v1", digest_input)
        or document.get("token_measurement_status") != "pending_authoritative_nomic_measurement"
        or document.get("publication_eligible") is not False
    ):
        fail("chunk_candidate_contract_mismatch")
    documents = document.get("documents")
    if not isinstance(documents, list) or not documents:
        fail("chunk_candidate_document_inventory_invalid")
    candidates: list[dict[str, Any]] = []
    seen: set[str] = set()
    for source_document in documents:
        if not isinstance(source_document, dict):
            fail("chunk_candidate_document_invalid")
        for candidate in source_document.get("candidates", []):
            if not isinstance(candidate, dict):
                fail("chunk_candidate_invalid")
            chunk_id = require_hex_digest(candidate.get("chunk_id"), "chunk_identity_invalid")
            if chunk_id in seen:
                fail("chunk_identity_duplicate")
            seen.add(chunk_id)
            content = candidate.get("content_text")
            context = candidate.get("context_text")
            retrieval = candidate.get("retrieval_text")
            expected_retrieval = f"{context}\n\n{content}" if context else content
            if (
                not isinstance(content, str)
                or not content.strip()
                or not isinstance(context, str)
                or retrieval != expected_retrieval
                or candidate.get("method_profile_id") != method_profile_id
                or candidate.get("publication_eligibility")
                != {"eligible": False, "blockers": ["nomic_token_measurement_pending"]}
            ):
                fail("chunk_candidate_projection_invalid")
            candidates.append(candidate)
    if not candidates or len(candidates) > MAX_CANDIDATES:
        fail("chunk_candidate_count_mismatch")
    return candidates


def tokenizer_measure(container: str, candidates: list[dict[str, Any]]) -> dict[str, list[int]]:
    request = {
        "exact": [DOCUMENT_PREFIX + item["retrieval_text"] for item in candidates],
        "content": [item["content_text"] for item in candidates],
        "context": [item["context_text"] for item in candidates],
        "prefix": [DOCUMENT_PREFIX] * len(candidates),
    }
    code = (
        "import json,sys;"
        "from transformers import AutoTokenizer;"
        "x=json.load(sys.stdin);"
        "t=AutoTokenizer.from_pretrained('/models/nomic',local_files_only=True,trust_remote_code=False);"
        "c=lambda v,s:[len(t.encode(i,add_special_tokens=s)) for i in v];"
        "print(json.dumps({'total_with_special':c(x['exact'],True),"
        "'total_without_special':c(x['exact'],False),"
        "'content_without_special':c(x['content'],False),"
        "'context_without_special':c(x['context'],False),"
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
    expected_keys = {
        "total_with_special",
        "total_without_special",
        "content_without_special",
        "context_without_special",
        "prefix_without_special",
    }
    if not isinstance(result, dict) or set(result) != expected_keys:
        fail("authoritative_tokenizer_output_invalid")
    for key, values in result.items():
        if (
            not isinstance(values, list)
            or len(values) != len(candidates)
            or any(not isinstance(value, int) or value < 0 for value in values)
            or (key.startswith("total_") and any(value <= 0 for value in values))
        ):
            fail("authoritative_tokenizer_counts_invalid")
    return result


def create_embedding_artifact(
    source: dict[str, Any],
    source_sha256: str,
    candidates: list[dict[str, Any]],
    measurements: dict[str, list[int]],
    client: NomicClient,
    runtime_identity: str,
    batch_size: int,
) -> tuple[dict[str, Any], dict[str, Any]]:
    totals = measurements["total_with_special"]
    if any(value > EXPECTED_MAX_MODEL_LEN for value in totals):
        fail("candidate_exceeds_model_token_ceiling")
    inputs = [DOCUMENT_PREFIX + item["retrieval_text"] for item in candidates]
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

    embedding_space = {
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
    embedding_space_id = domain_digest("ishikawa.embedding-space.v1", embedding_space)
    records: list[dict[str, Any]] = []
    norms: list[float] = []
    for index, (candidate, exact_input, vector) in enumerate(zip(candidates, inputs, vectors, strict=True)):
        input_digest = domain_digest(
            "ishikawa.embedding-input.v1", {"input": exact_input}
        )
        artifact_id = domain_digest(
            "ishikawa.embedding-artifact.v1",
            {
                "chunk_id": candidate["chunk_id"],
                "embedding_space_id": embedding_space_id,
                "submitted_input_digest": input_digest,
            },
        )
        norm = vector_norm(vector)
        norms.append(norm)
        records.append({
            "schema_version": 1,
            "embedding_artifact_id": artifact_id,
            "chunk_id": candidate["chunk_id"],
            "embedding_space_id": embedding_space_id,
            "submitted_input_digest": input_digest,
            "token_accounting": {
                "tokenizer_sha256": EXPECTED_TOKENIZER_SHA256,
                "count_mode": "with_special_tokens",
                "content_tokens_without_special": measurements["content_without_special"][index],
                "context_tokens_without_special": measurements["context_without_special"][index],
                "prefix_tokens_without_special": measurements["prefix_without_special"][index],
                "total_without_special": measurements["total_without_special"][index],
                "total_embedding_input_tokens": totals[index],
            },
            "target_evaluation": {
                "initial_target_tokens": INITIAL_TARGET_TOKENS,
                "within_initial_target": totals[index] <= INITIAL_TARGET_TOKENS,
                "within_model_ceiling": True,
            },
            "vector": vector,
            "vector_dimension": EXPECTED_DIMENSION,
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
        "runtime_identity_digest": domain_digest(
            "ishikawa.embedding-runtime-observation.v1", {"runtime": runtime_identity}
        ),
        "publication_eligible": False,
        "publication_blocker": "retrieval_profile_calibration_pending",
        "records": records,
    }
    artifact["embedding_set_digest"] = domain_digest(
        "ishikawa.embedding-set.v1", artifact
    )
    summary = {
        "candidates": len(records),
        "batch_count": math.ceil(len(records) / batch_size),
        "observed_usage": observed_usage,
        "token_min": min(totals),
        "token_max": max(totals),
        "over_target": sum(value > INITIAL_TARGET_TOKENS for value in totals),
        "norm_min": min(norms),
        "norm_max": max(norms),
        "repeat_delta": repeat_delta,
    }
    return artifact, summary


def write_exclusive(path: Path, payload: bytes) -> None:
    if not path.is_absolute() or path.exists() or path.is_symlink():
        fail("unsafe_output_path")
    if not path.parent.is_dir() or path.parent.is_symlink():
        fail("unsafe_output_parent")
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)


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
    if sha256_file(arguments.input) != expected_input_sha256:
        fail("chunk_candidate_file_identity_mismatch")
    source = read_json_file(arguments.input, MAX_INPUT_BYTES)
    candidates = validate_candidates(source)

    emit(schema="chunk-embedding-qualification/v1", operation="measure_and_embed")
    validate_artifacts(arguments.model_root)
    runtime_identity = validate_runtime(arguments.container)

    secret = read_operator_credential()
    client: NomicClient | None = None
    try:
        client = NomicClient(arguments.base_url, secret)
        client.model_ready()
        measurements = tokenizer_measure(arguments.container, candidates)
        artifact, summary = create_embedding_artifact(
            source,
            expected_input_sha256,
            candidates,
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
    artifact_sha256 = hashlib.sha256(payload).hexdigest()
    emit(
        model_identity="pass",
        tokenizer_identity="pass",
        tokenizer_service_agreement="pass",
        token_count_mode="with_special_tokens",
    )
    emit(
        candidates=summary["candidates"],
        batches=summary["batch_count"],
        token_min=summary["token_min"],
        token_max=summary["token_max"],
        over_initial_target=summary["over_target"],
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
        embedding_set_digest=artifact["embedding_set_digest"],
        artifact_sha256=artifact_sha256,
        artifact_bytes=len(payload),
    )
    emit(
        result="PASS",
        publication_eligible="false",
        next_gate="retrieval_profile_calibration",
        raw_text_logged="false",
        vectors_logged="false",
        credential_recorded="false",
    )


def self_test() -> None:
    sample = {"b": 2, "a": 1}
    assert canonical_json_bytes(sample) == b'{"a":1,"b":2}'
    assert domain_digest("test", sample) == domain_digest("test", {"a": 1, "b": 2})
    assert math.isclose(vector_norm([3.0, 4.0]), 5.0)
    assert math.isclose(maximum_delta([1.0, 2.0], [1.0, 2.5]), 0.5)
    assert validate_base_url("http://127.0.0.1:8001") == "http://127.0.0.1:8001"
    try:
        validate_base_url("https://example.invalid")
    except QualificationError:
        pass
    else:
        raise AssertionError("non-loopback URL must fail")
    print("chunk_embedding_qualifier_self_test=PASS")


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
    except QualificationError as exc:
        emit(result="BLOCKED", reason=str(exc))
        return 1
    except (KeyError, TypeError, ValueError, OSError):
        emit(result="BLOCKED", reason="bounded_runtime_failure")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
