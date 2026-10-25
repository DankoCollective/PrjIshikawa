#!/usr/bin/env python3
"""Verify the configured Nomic embedding service on the model host.

The verification is read-only. It binds the accepted model artifacts and live
vLLM runtime, accepts an operator-entered API credential through standard
input, and emits bounded content-free results. It never reads a stored
credential or prints prompts, responses, vectors, credentials, or raw service
errors.
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
EXPECTED_LICENSE = "apache-2.0"
DEFAULT_BASE_URL = "http://127.0.0.1:8001"
DEFAULT_MODEL_ROOT = Path("/models/nomic")
DEFAULT_CONTAINER = "vllm-nomic"
MAX_RESPONSE_BYTES = 16 * 1024 * 1024
MAX_CREDENTIAL_BYTES = 1024


class VerificationError(RuntimeError):
    """An embedding-service acceptance condition failed."""


def fail(message: str) -> NoReturn:
    raise VerificationError(message)


def emit(**fields: object) -> None:
    rendered = " ".join(f"{key}={value}" for key, value in fields.items())
    print(f"[embedding-verification] {rendered}", flush=True)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
                digest.update(block)
    except OSError as exc:
        fail(f"cannot hash required artifact {path}: {exc.strerror}")
    return digest.hexdigest()


def read_json_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        fail(f"cannot decode required JSON artifact {path}: {exc}")
    if not isinstance(value, dict):
        fail(f"required JSON artifact is not an object: {path}")
    return value


def run(
    arguments: Sequence[str], *, input_bytes: bytes | None = None
) -> subprocess.CompletedProcess[bytes]:
    try:
        return subprocess.run(
            list(arguments),
            input=input_bytes,
            stdin=None if input_bytes is not None else subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=120,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        fail(f"cannot execute required command {arguments[0]}: {exc}")


def require_command(path: Path) -> None:
    if not path.is_file() or not os.access(path, os.X_OK):
        fail(f"required executable is unavailable: {path}")


def validate_artifacts(model_root: Path) -> None:
    model_path = model_root / "model.safetensors"
    tokenizer_path = model_root / "tokenizer.json"
    config_path = model_root / "config.json"
    pooling_path = model_root / "1_Pooling" / "config.json"
    readme_path = model_root / "README.md"

    observed_model_hash = sha256_file(model_path)
    observed_tokenizer_hash = sha256_file(tokenizer_path)
    if observed_model_hash != EXPECTED_MODEL_SHA256:
        fail("model artifact digest differs from the accepted Nomic snapshot")
    if observed_tokenizer_hash != EXPECTED_TOKENIZER_SHA256:
        fail("tokenizer artifact digest differs from the accepted Nomic snapshot")

    config = read_json_object(config_path)
    if (
        config.get("model_type") != "nomic_bert"
        or config.get("hidden_size") != EXPECTED_DIMENSION
        or config.get("max_position_embeddings") != EXPECTED_MAX_MODEL_LEN
    ):
        fail("model configuration differs from the accepted embedding tuple")

    pooling = read_json_object(pooling_path)
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
        fail("pooling configuration is not the accepted mean-token posture")

    try:
        readme = readme_path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        fail(f"cannot read model license metadata: {exc}")
    if f"license: {EXPECTED_LICENSE}" not in readme:
        fail("model README does not declare the accepted Apache-2.0 license")

    emit(
        artifacts="pass",
        model_revision=EXPECTED_MODEL_REVISION,
        model_sha256=observed_model_hash,
        tokenizer_sha256=observed_tokenizer_hash,
        pooling="mean_tokens",
        configured_dtype=config.get("torch_dtype", "unknown"),
        license=EXPECTED_LICENSE,
    )


def argument_value(arguments: list[str], option: str) -> str | None:
    for index, value in enumerate(arguments):
        if value == option and index + 1 < len(arguments):
            return arguments[index + 1]
        prefix = f"{option}="
        if value.startswith(prefix):
            return value[len(prefix) :]
    return None


def validate_runtime(container: str) -> None:
    docker = Path("/usr/bin/docker")
    require_command(docker)

    inspected = run(
        [
            str(docker),
            "container",
            "inspect",
            "--format",
            "{{json .Args}}|{{.Image}}|{{.Config.Image}}",
            container,
        ]
    )
    if inspected.returncode != 0:
        fail("the managed Nomic container is not running")
    try:
        args_text, image_id, image_reference = (
            inspected.stdout.decode("utf-8").strip().split("|", 2)
        )
        container_args = json.loads(args_text)
    except (UnicodeError, ValueError, json.JSONDecodeError) as exc:
        fail(f"cannot decode bounded Nomic container identity: {exc}")
    if not isinstance(container_args, list) or not all(
        isinstance(item, str) for item in container_args
    ):
        fail("Nomic container arguments are malformed")

    expected_arguments = {
        "--served-model-name": EXPECTED_MODEL_ID,
        "--runner": "pooling",
        "--max-model-len": str(EXPECTED_MAX_MODEL_LEN),
        "--dtype": "auto",
    }
    for option, expected in expected_arguments.items():
        if argument_value(container_args, option) != expected:
            fail(f"live Nomic container argument differs: {option}")

    version = run(
        [
            str(docker),
            "exec",
            container,
            "python3",
            "-c",
            "import vllm; print(vllm.__version__)",
        ]
    )
    if version.returncode != 0:
        fail("cannot read the vLLM version from the running container")
    try:
        vllm_version = version.stdout.decode("utf-8").strip()
    except UnicodeError as exc:
        fail(f"vLLM version is not UTF-8: {exc}")
    if not vllm_version or any(character.isspace() for character in vllm_version):
        fail("vLLM version output is malformed")

    emit(
        runtime="pass",
        container=container,
        image_id=image_id,
        image_reference=image_reference,
        vllm_version=vllm_version,
        runner="pooling",
        dtype_policy="auto",
        max_model_len=EXPECTED_MAX_MODEL_LEN,
    )


def read_operator_credential() -> bytearray:
    """Read one bounded credential from the anonymous standard-input pipe."""
    value = bytearray()
    while len(value) <= MAX_CREDENTIAL_BYTES:
        block = os.read(sys.stdin.fileno(), MAX_CREDENTIAL_BYTES + 1 - len(value))
        if not block:
            break
        value.extend(block)
    if (
        not 32 <= len(value) <= MAX_CREDENTIAL_BYTES
        or b"\n" in value
        or b"\r" in value
    ):
        wipe(value)
        fail("operator-provided credential has an invalid bounded format")
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
        fail("base URL must be an uncredentialed loopback HTTP URL")
    return value.rstrip("/")


class NomicClient:
    def __init__(self, base_url: str, secret: bytearray) -> None:
        self.base_url = validate_base_url(base_url)
        try:
            self.authorization = "Bearer " + bytes(secret).decode("utf-8")
        except UnicodeError:
            fail("decrypted Nomic credential is not UTF-8")

    def close(self) -> None:
        self.authorization = ""

    def request(
        self,
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
    ) -> tuple[int, dict[str, Any] | None]:
        data = None
        headers = {"Authorization": self.authorization}
        if payload is not None:
            data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(
            f"{self.base_url}{path}", data=data, headers=headers, method=method
        )
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                body = response.read(MAX_RESPONSE_BYTES + 1)
                status = response.status
        except urllib.error.HTTPError as exc:
            exc.read(MAX_RESPONSE_BYTES + 1)
            return exc.code, None
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            fail(f"Nomic request transport failed for {path}: {type(exc).__name__}")
        if len(body) > MAX_RESPONSE_BYTES:
            fail("Nomic response exceeds the bounded verification limit")
        try:
            decoded = json.loads(body)
        except (UnicodeError, json.JSONDecodeError):
            fail("Nomic success response is not valid JSON")
        if not isinstance(decoded, dict):
            fail("Nomic success response is not a JSON object")
        return status, decoded

    def embeddings(self, inputs: str | list[str]) -> tuple[list[list[float]], int]:
        values = [inputs] if isinstance(inputs, str) else inputs
        if not values or any(not isinstance(value, str) or not value.strip() for value in values):
            fail("empty embedding input was rejected by the verification adapter")
        status, document = self.request(
            "POST",
            "/v1/embeddings",
            {"model": EXPECTED_MODEL_ID, "input": inputs},
        )
        if status != 200 or document is None:
            fail(f"embedding request returned HTTP {status}")
        if document.get("model") != EXPECTED_MODEL_ID:
            fail("embedding response model identity differs")
        records = document.get("data")
        if not isinstance(records, list) or len(records) != len(values):
            fail("embedding response cardinality differs from request")
        ordered: list[list[float] | None] = [None] * len(values)
        for record in records:
            if not isinstance(record, dict):
                fail("embedding response contains a malformed record")
            index = record.get("index")
            vector = record.get("embedding")
            if (
                not isinstance(index, int)
                or not 0 <= index < len(values)
                or ordered[index] is not None
                or not isinstance(vector, list)
                or len(vector) != EXPECTED_DIMENSION
                or any(
                    not isinstance(value, (int, float))
                    or isinstance(value, bool)
                    or not math.isfinite(float(value))
                    for value in vector
                )
            ):
                fail("embedding response contains an invalid vector")
            ordered[index] = [float(value) for value in vector]
        if any(vector is None for vector in ordered):
            fail("embedding response contains a missing vector")
        usage = document.get("usage")
        prompt_tokens = usage.get("prompt_tokens") if isinstance(usage, dict) else None
        if not isinstance(prompt_tokens, int) or prompt_tokens <= 0:
            fail("embedding response lacks positive prompt-token usage")
        return [vector for vector in ordered if vector is not None], prompt_tokens

    def expect_rejection(self, payload: dict[str, Any], label: str) -> None:
        status, _ = self.request("POST", "/v1/embeddings", payload)
        if not 400 <= status <= 499:
            fail(f"{label} request was not rejected with HTTP 4xx")
        emit(rejection=label, status=status)


def prefixed(role: str, text: str) -> str:
    if role not in {"search_document", "search_query"}:
        fail("unsupported Nomic task prefix")
    if not isinstance(text, str) or not text.strip():
        fail("empty text is prohibited before Nomic submission")
    return f"{role}: {text}"


def vector_norm(vector: Sequence[float]) -> float:
    return math.sqrt(sum(value * value for value in vector))


def cosine(left: Sequence[float], right: Sequence[float]) -> float:
    left_norm = vector_norm(left)
    right_norm = vector_norm(right)
    if left_norm == 0.0 or right_norm == 0.0:
        fail("zero vector cannot participate in cosine comparison")
    return sum(a * b for a, b in zip(left, right, strict=True)) / (
        left_norm * right_norm
    )


def max_absolute_delta(left: Sequence[float], right: Sequence[float]) -> float:
    if len(left) != len(right):
        fail("cannot compare vectors with different dimensions")
    return max(abs(a - b) for a, b in zip(left, right, strict=True))


def tokenizer_counts(container: str, inputs: list[str]) -> tuple[list[int], list[int]]:
    code = (
        "import json,sys;"
        "from transformers import AutoTokenizer;"
        "x=json.load(sys.stdin);"
        "t=AutoTokenizer.from_pretrained('/models/nomic',local_files_only=True,"
        "trust_remote_code=False);"
        "print(json.dumps({'with_special':[len(t.encode(v,add_special_tokens=True)) "
        "for v in x],'without_special':[len(t.encode(v,add_special_tokens=False)) "
        "for v in x]},separators=(',',':')))"
    )
    completed = run(
        [
            "/usr/bin/docker",
            "exec",
            "-i",
            container,
            "python3",
            "-c",
            code,
        ],
        input_bytes=json.dumps(inputs).encode("utf-8"),
    )
    if completed.returncode != 0:
        fail("independent tokenizer count inside the vLLM image failed")
    try:
        document = json.loads(completed.stdout)
        with_special = document["with_special"]
        without_special = document["without_special"]
    except (UnicodeError, json.JSONDecodeError, KeyError, TypeError):
        fail("independent tokenizer count returned malformed output")
    if (
        not isinstance(with_special, list)
        or not isinstance(without_special, list)
        or len(with_special) != len(inputs)
        or len(without_special) != len(inputs)
        or any(not isinstance(value, int) or value <= 0 for value in with_special)
        or any(not isinstance(value, int) or value <= 0 for value in without_special)
    ):
        fail("independent tokenizer counts are invalid")
    return with_special, without_special


def require_token_agreement(
    observed: int,
    with_special: int,
    without_special: int,
    label: str,
) -> str:
    if observed == with_special:
        return "with_special_tokens"
    if observed == without_special:
        return "without_special_tokens"
    fail(
        f"service token usage disagrees with the pinned tokenizer for {label}: "
        f"service={observed}, with_special={with_special}, "
        f"without_special={without_special}"
    )


def execute(arguments: argparse.Namespace) -> None:
    if os.geteuid() != 0:
        fail("run the verification as root through attended sudo")
    if not arguments.credential_stdin:
        fail("credential must be supplied through the attended input pipe")

    emit(
        schema="embedding-service-verification/v1",
        host=socket.gethostname(),
        operation="read_only_compatibility_verification",
    )
    validate_artifacts(arguments.model_root)
    validate_runtime(arguments.container)

    secret = read_operator_credential()
    client: NomicClient | None = None
    try:
        client = NomicClient(arguments.base_url, secret)

        status, models = client.request("GET", "/v1/models")
        if status != 200 or models is None:
            fail(f"model identity request returned HTTP {status}")
        model_records = models.get("data")
        selected = None
        if isinstance(model_records, list):
            selected = next(
                (
                    record
                    for record in model_records
                    if isinstance(record, dict)
                    and record.get("id") == EXPECTED_MODEL_ID
                ),
                None,
            )
        if not isinstance(selected, dict):
            fail("live service does not advertise the accepted Nomic model")
        advertised_limit = selected.get("max_model_len")
        if advertised_limit not in {None, EXPECTED_MAX_MODEL_LEN}:
            fail("live service advertises an unexpected maximum model length")
        emit(
            identity="pass",
            model=EXPECTED_MODEL_ID,
            advertised_max_model_len=advertised_limit or "not_reported",
        )

        documents = [
            prefixed(
                "search_document",
                "Employees attach receipts to travel reimbursement claims.",
            ),
            prefixed(
                "search_document",
                "The server maintenance window begins on Sunday evening.",
            ),
            prefixed(
                "search_document",
                "Visitors display identification badges while in the facility.",
            ),
        ]
        query = prefixed(
            "search_query", "What is required for a travel reimbursement claim?"
        )

        document_vectors, batch_tokens = client.embeddings(documents)
        query_vectors, query_tokens = client.embeddings(query)
        single_vectors, single_tokens = client.embeddings(documents[0])
        repeat_vectors, repeat_tokens = client.embeddings(documents[0])

        with_special, without_special = tokenizer_counts(
            arguments.container, documents + [query]
        )
        batch_mode = require_token_agreement(
            batch_tokens,
            sum(with_special[:3]),
            sum(without_special[:3]),
            "document batch",
        )
        query_mode = require_token_agreement(
            query_tokens, with_special[3], without_special[3], "query"
        )
        single_mode = require_token_agreement(
            single_tokens, with_special[0], without_special[0], "single document"
        )
        repeat_mode = require_token_agreement(
            repeat_tokens, with_special[0], without_special[0], "repeat document"
        )
        modes = {batch_mode, query_mode, single_mode, repeat_mode}
        if len(modes) != 1:
            fail("service token-count mode is inconsistent between requests")
        emit(tokenizer_agreement="pass", count_mode=modes.pop())

        repeat_delta = max_absolute_delta(single_vectors[0], repeat_vectors[0])
        batch_delta = max_absolute_delta(single_vectors[0], document_vectors[0])
        if repeat_delta > arguments.numeric_tolerance:
            fail("identical repeated embedding exceeds the numeric tolerance")
        if batch_delta > arguments.numeric_tolerance:
            fail("single and batched embedding exceed the numeric tolerance")

        query_vector = query_vectors[0]
        similarities = [cosine(query_vector, vector) for vector in document_vectors]
        ranking = sorted(range(len(similarities)), key=similarities.__getitem__, reverse=True)
        if ranking[0] != 0:
            fail("synthetic prefix-and-cosine discrimination ranked the wrong passage first")
        margin = similarities[0] - similarities[ranking[1]]
        norms = [vector_norm(vector) for vector in document_vectors + query_vectors]
        emit(
            embedding="pass",
            dimensions=EXPECTED_DIMENSION,
            finite_vectors="pass",
            cardinality="pass",
            repeat_max_abs_delta=f"{repeat_delta:.9g}",
            batch_max_abs_delta=f"{batch_delta:.9g}",
            numeric_tolerance=f"{arguments.numeric_tolerance:.9g}",
        )
        emit(
            discrimination="pass",
            expected_top_rank=0,
            observed_top_rank=ranking[0],
            cosine_margin=f"{margin:.9g}",
            vector_norm_min=f"{min(norms):.9g}",
            vector_norm_max=f"{max(norms):.9g}",
            storage_transform="none",
            recommended_distance="cosine",
        )

        try:
            prefixed("search_query", "")
        except VerificationError:
            emit(rejection="empty_input_local_guard", status="pass")
        else:
            fail("empty-input local guard did not fail closed")

        client.expect_rejection(
            {"model": f"{EXPECTED_MODEL_ID}-invalid", "input": query},
            "unknown_model",
        )
        client.expect_rejection(
            {"model": EXPECTED_MODEL_ID, "input": {"invalid": True}},
            "malformed_input",
        )
        client.expect_rejection(
            {
                "model": EXPECTED_MODEL_ID,
                "input": prefixed("search_document", "word " * 2200),
            },
            "over_model_limit",
        )
    finally:
        if client is not None:
            client.close()
        wipe(secret)

    emit(
        result="PASS",
        disposition="embedding_tuple_and_adapter_compatible",
        raw_vectors_recorded="false",
        prompts_recorded="false",
        credential_recorded="false",
        full_corpus_retrieval_qualification="separate_acceptance_required",
    )


def self_test() -> None:
    assert prefixed("search_query", "question") == "search_query: question"
    assert prefixed("search_document", "passage") == "search_document: passage"
    try:
        prefixed("search_query", "  ")
    except VerificationError:
        pass
    else:
        raise AssertionError("empty input must fail")
    assert math.isclose(vector_norm([3.0, 4.0]), 5.0)
    assert math.isclose(cosine([1.0, 0.0], [2.0, 0.0]), 1.0)
    assert math.isclose(max_absolute_delta([1.0, 2.0], [1.0, 2.5]), 0.5)
    assert require_token_agreement(4, 4, 2, "test") == "with_special_tokens"
    assert require_token_agreement(2, 4, 2, "test") == "without_special_tokens"
    completed = run(
        [
            sys.executable,
            "-c",
            "import sys; sys.stdout.buffer.write(sys.stdin.buffer.read())",
        ],
        input_bytes=b"verification-input",
    )
    assert completed.returncode == 0 and completed.stdout == b"verification-input"
    print("embedding_service_verifier_self_test=PASS")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--model-root", type=Path, default=DEFAULT_MODEL_ROOT)
    parser.add_argument("--credential-stdin", action="store_true")
    parser.add_argument("--container", default=DEFAULT_CONTAINER)
    parser.add_argument("--numeric-tolerance", type=float, default=1e-5)
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    arguments = parse_args(argv)
    try:
        if arguments.self_test:
            self_test()
        else:
            if not 0.0 < arguments.numeric_tolerance <= 1e-3:
                fail("numeric tolerance must be greater than zero and at most 1e-3")
            execute(arguments)
        return 0
    except (VerificationError, AssertionError) as exc:
        print(f"[embedding-verification] result=BLOCKED reason={exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
