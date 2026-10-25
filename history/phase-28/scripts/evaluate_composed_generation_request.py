#!/usr/bin/env python3
"""Evaluate one content-free composed-request token measurement."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, NoReturn


EXPECTED_MODEL = "google/gemma-4-26B-A4B-it"
EXPECTED_MAX_MODEL_LEN = 204800
EXPECTED_APPLICATION_LIMIT = 32768
EXPECTED_ANSWER_RESERVE = 2048
HEX = re.compile(r"^[0-9a-f]{64}$")


def fail(reason: str) -> NoReturn:
    print(f"composed_request_token_evaluation=blocked;reason={reason}")
    raise SystemExit(1)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def read_json(path: Path, reason: str) -> dict[str, Any]:
    if not path.is_file() or path.is_symlink():
        fail(reason)
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail(reason)
    if not isinstance(value, dict):
        fail(reason)
    return value


def require_hex(value: Any, reason: str, *, image: bool = False) -> str:
    if image and isinstance(value, str):
        value = value.removeprefix("sha256:")
    if not isinstance(value, str) or HEX.fullmatch(value) is None:
        fail(reason)
    return value


def evaluate(
    artifact_path: Path,
    expected_source_sha256: str,
    tokenizer_path: Path,
    expected_tokenizer_sha256: str,
    expected_request_identity: str,
    expected_prompt_identity: str,
    expected_policy_identity: str,
) -> None:
    if sha256_file(tokenizer_path) != expected_tokenizer_sha256:
        fail("accepted_tokenizer_artifact_identity_mismatch")
    tokenizer = read_json(tokenizer_path, "accepted_tokenizer_artifact_invalid")
    artifact = read_json(artifact_path, "measurement_artifact_invalid")
    required = {
        "application_context_limit", "chat_template_sha256", "configured_max_model_len",
        "enable_thinking", "measurements", "model_called", "model_manifest_sha256",
        "prompt_identity", "purpose", "raw_text_retained", "reconstruction_policy_identity",
        "request_identity", "runtime_image_id", "schema_version", "served_model",
        "source_sha256", "tokenizer_class", "tokenizer_files", "tokenizer_identity", "vocab_size",
    }
    if set(artifact) != required:
        fail("measurement_artifact_contract_mismatch")
    if (
        artifact["schema_version"] != 1
        or artifact["purpose"] != "composed_generation_request_token_measurement"
        or artifact["source_sha256"] != expected_source_sha256
        or artifact["served_model"] != EXPECTED_MODEL
        or artifact["configured_max_model_len"] != EXPECTED_MAX_MODEL_LEN
        or artifact["application_context_limit"] != EXPECTED_APPLICATION_LIMIT
        or artifact["enable_thinking"] is not False
        or artifact["raw_text_retained"] is not False
        or artifact["model_called"] is not False
        or artifact["request_identity"] != expected_request_identity
        or artifact["prompt_identity"] != expected_prompt_identity
        or artifact["reconstruction_policy_identity"] != expected_policy_identity
    ):
        fail("measurement_artifact_contract_mismatch")
    for name in (
        "source_sha256", "chat_template_sha256", "model_manifest_sha256",
        "prompt_identity", "reconstruction_policy_identity", "request_identity",
        "tokenizer_identity",
    ):
        require_hex(artifact[name], "measurement_identity_invalid")
    require_hex(artifact["runtime_image_id"], "measurement_identity_invalid", image=True)
    tokenizer_fields = (
        "served_model", "configured_max_model_len", "runtime_image_id",
        "model_manifest_sha256", "tokenizer_files", "chat_template_sha256",
        "tokenizer_identity", "tokenizer_class", "vocab_size",
    )
    if tokenizer.get("purpose") != "generation_tokenizer_qualification_measurement":
        fail("accepted_tokenizer_artifact_invalid")
    if any(artifact[name] != tokenizer.get(name) for name in tokenizer_fields):
        fail("deployed_tokenizer_identity_drift")
    files = artifact["tokenizer_files"]
    if (
        not isinstance(files, dict)
        or set(files) != {"chat_template.jinja", "config.json", "tokenizer.json", "tokenizer_config.json"}
        or any(not isinstance(value, str) or HEX.fullmatch(value) is None for value in files.values())
        or files["chat_template.jinja"] != artifact["chat_template_sha256"]
    ):
        fail("tokenizer_file_identity_invalid")
    measurements = artifact["measurements"]
    expected_measurements = {
        "answer_token_reserve", "application_remaining_tokens", "evidence_excerpt_tokens",
        "history_content_tokens", "prompt_tokens", "question_tokens",
        "service_remaining_tokens", "system_content_tokens", "total_reserved_tokens",
        "untrusted_payload_tokens",
    }
    if not isinstance(measurements, dict) or set(measurements) != expected_measurements:
        fail("token_measurement_contract_mismatch")
    scalars = expected_measurements - {"evidence_excerpt_tokens", "history_content_tokens"}
    if (
        any(type(measurements[name]) is not int for name in scalars)
        or measurements["prompt_tokens"] < 1
        or measurements["system_content_tokens"] < 1
        or measurements["untrusted_payload_tokens"] < 1
        or measurements["question_tokens"] < 1
        or measurements["answer_token_reserve"] != EXPECTED_ANSWER_RESERVE
        or not isinstance(measurements["history_content_tokens"], list)
        or len(measurements["history_content_tokens"]) != 2
        or not isinstance(measurements["evidence_excerpt_tokens"], list)
        or len(measurements["evidence_excerpt_tokens"]) != 3
        or any(type(value) is not int or value < 1 for value in measurements["history_content_tokens"] + measurements["evidence_excerpt_tokens"])
    ):
        fail("token_measurement_invalid")
    total = measurements["prompt_tokens"] + measurements["answer_token_reserve"]
    if (
        measurements["total_reserved_tokens"] != total
        or measurements["application_remaining_tokens"] != EXPECTED_APPLICATION_LIMIT - total
        or measurements["service_remaining_tokens"] != EXPECTED_MAX_MODEL_LEN - total
        or total > EXPECTED_APPLICATION_LIMIT
        or measurements["application_remaining_tokens"] < 0
    ):
        fail("context_budget_accounting_mismatch")
    print("purpose=evaluate_composed_generation_request_tokens")
    print(f"served_model={EXPECTED_MODEL};configured_max_model_len={EXPECTED_MAX_MODEL_LEN}")
    print(f"tokenizer_identity={artifact['tokenizer_identity']};chat_template_sha256={artifact['chat_template_sha256']}")
    print(f"generation_prompt_id={artifact['prompt_identity']};generation_request_id={artifact['request_identity']}")
    print(
        f"prompt_tokens={measurements['prompt_tokens']};answer_token_reserve={EXPECTED_ANSWER_RESERVE};"
        f"total_reserved_tokens={total};application_context_limit={EXPECTED_APPLICATION_LIMIT};"
        f"application_remaining_tokens={measurements['application_remaining_tokens']}"
    )
    print(
        f"system_content_tokens={measurements['system_content_tokens']};"
        f"untrusted_payload_tokens={measurements['untrusted_payload_tokens']};"
        f"history_turns={len(measurements['history_content_tokens'])};"
        f"evidence_excerpts={len(measurements['evidence_excerpt_tokens'])}"
    )
    print("system_role_template_compatibility=pass;exact_request_budget_fit=pass")
    print("model_called=false;credential_read=false;raw_text_retained=false")
    print("composed_request_token_evaluation=pass")
    print(f"measurement_artifact_sha256={sha256_file(artifact_path)}")


def self_test() -> None:
    files = {
        "chat_template.jinja": "a" * 64,
        "config.json": "b" * 64,
        "tokenizer.json": "c" * 64,
        "tokenizer_config.json": "d" * 64,
    }
    tokenizer = {
        "purpose": "generation_tokenizer_qualification_measurement",
        "served_model": EXPECTED_MODEL,
        "configured_max_model_len": EXPECTED_MAX_MODEL_LEN,
        "runtime_image_id": "sha256:" + "e" * 64,
        "model_manifest_sha256": "f" * 64,
        "tokenizer_files": files,
        "chat_template_sha256": files["chat_template.jinja"],
        "tokenizer_identity": "1" * 64,
        "tokenizer_class": "SyntheticTokenizer",
        "vocab_size": 262144,
    }
    request_id, prompt_id, policy_id, source_id = "2" * 64, "3" * 64, "4" * 64, "5" * 64
    artifact = {
        "application_context_limit": EXPECTED_APPLICATION_LIMIT,
        "chat_template_sha256": tokenizer["chat_template_sha256"],
        "configured_max_model_len": EXPECTED_MAX_MODEL_LEN,
        "enable_thinking": False,
        "measurements": {
            "answer_token_reserve": EXPECTED_ANSWER_RESERVE,
            "application_remaining_tokens": EXPECTED_APPLICATION_LIMIT - 3048,
            "evidence_excerpt_tokens": [10, 11, 12],
            "history_content_tokens": [8, 9],
            "prompt_tokens": 1000,
            "question_tokens": 7,
            "service_remaining_tokens": EXPECTED_MAX_MODEL_LEN - 3048,
            "system_content_tokens": 100,
            "total_reserved_tokens": 3048,
            "untrusted_payload_tokens": 850,
        },
        "model_called": False,
        "model_manifest_sha256": tokenizer["model_manifest_sha256"],
        "prompt_identity": prompt_id,
        "purpose": "composed_generation_request_token_measurement",
        "raw_text_retained": False,
        "reconstruction_policy_identity": policy_id,
        "request_identity": request_id,
        "runtime_image_id": tokenizer["runtime_image_id"],
        "schema_version": 1,
        "served_model": EXPECTED_MODEL,
        "source_sha256": source_id,
        "tokenizer_class": tokenizer["tokenizer_class"],
        "tokenizer_files": files,
        "tokenizer_identity": tokenizer["tokenizer_identity"],
        "vocab_size": tokenizer["vocab_size"],
    }
    with tempfile.TemporaryDirectory(prefix="composed-request-evaluator-") as temporary:
        root = Path(temporary)
        tokenizer_path = root / "tokenizer.json"
        artifact_path = root / "measurement.json"
        tokenizer_path.write_bytes(canonical_bytes(tokenizer) + b"\n")
        artifact_path.write_bytes(canonical_bytes(artifact) + b"\n")
        command = [
            sys.executable, __file__, "--artifact", str(artifact_path),
            "--expected-source-sha256", source_id,
            "--accepted-tokenizer", str(tokenizer_path),
            "--expected-accepted-tokenizer-sha256", sha256_file(tokenizer_path),
            "--expected-request-identity", request_id,
            "--expected-prompt-identity", prompt_id,
            "--expected-policy-identity", policy_id,
        ]
        completed = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        if completed.returncode != 0 or b"composed_request_token_evaluation=pass\n" not in completed.stdout:
            fail("evaluator_self_test_valid_artifact_rejected")
        artifact["measurements"]["total_reserved_tokens"] += 1
        artifact_path.write_bytes(canonical_bytes(artifact) + b"\n")
        rejected = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        if rejected.returncode == 0 or b"reason=context_budget_accounting_mismatch\n" not in rejected.stdout:
            fail("evaluator_self_test_invalid_budget_accepted")
    print("composed_request_evaluator_self_test=pass")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact")
    parser.add_argument("--expected-source-sha256")
    parser.add_argument("--accepted-tokenizer")
    parser.add_argument("--expected-accepted-tokenizer-sha256")
    parser.add_argument("--expected-request-identity")
    parser.add_argument("--expected-prompt-identity")
    parser.add_argument("--expected-policy-identity")
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test:
        if any(
            value is not None
            for value in (
                arguments.artifact, arguments.expected_source_sha256,
                arguments.accepted_tokenizer, arguments.expected_accepted_tokenizer_sha256,
                arguments.expected_request_identity, arguments.expected_prompt_identity,
                arguments.expected_policy_identity,
            )
        ):
            parser.error("--self-test cannot be combined with artifact arguments")
        self_test()
        return
    required = (
        arguments.artifact, arguments.expected_source_sha256,
        arguments.accepted_tokenizer, arguments.expected_accepted_tokenizer_sha256,
        arguments.expected_request_identity, arguments.expected_prompt_identity,
        arguments.expected_policy_identity,
    )
    if any(value is None for value in required):
        parser.error("all artifact and expected-identity arguments are required")
    for value in (
        arguments.expected_source_sha256, arguments.expected_accepted_tokenizer_sha256,
        arguments.expected_request_identity, arguments.expected_prompt_identity,
        arguments.expected_policy_identity,
    ):
        require_hex(value, "expected_identity_invalid")
    evaluate(
        Path(arguments.artifact), arguments.expected_source_sha256,
        Path(arguments.accepted_tokenizer), arguments.expected_accepted_tokenizer_sha256,
        arguments.expected_request_identity, arguments.expected_prompt_identity,
        arguments.expected_policy_identity,
    )


if __name__ == "__main__":
    main()
