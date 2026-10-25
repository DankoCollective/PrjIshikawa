#!/usr/bin/env python3
"""Evaluate one content-free scope-request tokenizer measurement."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any, NoReturn


EXPECTED_MODEL = "google/gemma-4-26B-A4B-it"
EXPECTED_MAX_MODEL_LEN = 204800
EXPECTED_APPLICATION_LIMIT = 32768
EXPECTED_SCOPE_OUTPUT_RESERVE = 128
HEX = re.compile(r"^[0-9a-f]{64}$")


def fail(reason: str) -> NoReturn:
    print(f"scope_request_token_evaluation=blocked;reason={reason}")
    raise SystemExit(1)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


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


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact", required=True)
    parser.add_argument("--expected-source-sha256", required=True)
    parser.add_argument("--accepted-tokenizer", required=True)
    parser.add_argument("--expected-accepted-tokenizer-sha256", required=True)
    parser.add_argument("--expected-request-identity", required=True)
    parser.add_argument("--expected-prompt-identity", required=True)
    parser.add_argument("--expected-policy-identity", required=True)
    arguments = parser.parse_args()
    artifact_path = Path(arguments.artifact)
    tokenizer_path = Path(arguments.accepted_tokenizer)
    if sha256_file(tokenizer_path) != arguments.expected_accepted_tokenizer_sha256:
        fail("accepted_tokenizer_artifact_identity_mismatch")
    tokenizer = read_json(tokenizer_path, "accepted_tokenizer_artifact_invalid")
    artifact = read_json(artifact_path, "measurement_artifact_invalid")
    required = {
        "application_context_limit", "chat_template_sha256", "configured_max_model_len",
        "enable_thinking", "measurements", "model_called", "model_manifest_sha256",
        "prompt_identity", "purpose", "raw_text_retained", "request_identity",
        "runtime_image_id", "schema_version", "scope_policy_identity", "served_model",
        "source_sha256", "tokenizer_class", "tokenizer_files", "tokenizer_identity", "vocab_size",
    }
    if set(artifact) != required:
        fail("measurement_artifact_contract_mismatch")
    if (
        artifact["schema_version"] != 1
        or artifact["purpose"] != "scope_classifier_request_token_measurement"
        or artifact["source_sha256"] != arguments.expected_source_sha256
        or artifact["served_model"] != EXPECTED_MODEL
        or artifact["configured_max_model_len"] != EXPECTED_MAX_MODEL_LEN
        or artifact["application_context_limit"] != EXPECTED_APPLICATION_LIMIT
        or artifact["enable_thinking"] is not False
        or artifact["raw_text_retained"] is not False
        or artifact["model_called"] is not False
        or artifact["request_identity"] != arguments.expected_request_identity
        or artifact["prompt_identity"] != arguments.expected_prompt_identity
        or artifact["scope_policy_identity"] != arguments.expected_policy_identity
    ):
        fail("measurement_artifact_contract_mismatch")
    for name in (
        "source_sha256", "chat_template_sha256", "model_manifest_sha256", "prompt_identity",
        "scope_policy_identity", "request_identity", "tokenizer_identity",
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
        "application_remaining_tokens", "history_content_tokens", "prompt_tokens",
        "question_tokens", "scope_output_reserve", "service_remaining_tokens",
        "source_reference_tokens", "system_content_tokens", "total_reserved_tokens",
        "untrusted_payload_tokens",
    }
    if not isinstance(measurements, dict) or set(measurements) != expected_measurements:
        fail("token_measurement_contract_mismatch")
    scalar_names = expected_measurements - {"history_content_tokens", "source_reference_tokens"}
    if (
        any(type(measurements[name]) is not int for name in scalar_names)
        or measurements["prompt_tokens"] < 1
        or measurements["system_content_tokens"] < 1
        or measurements["untrusted_payload_tokens"] < 1
        or measurements["question_tokens"] < 1
        or measurements["scope_output_reserve"] != EXPECTED_SCOPE_OUTPUT_RESERVE
        or not isinstance(measurements["history_content_tokens"], list)
        or len(measurements["history_content_tokens"]) != 2
        or not isinstance(measurements["source_reference_tokens"], list)
        or len(measurements["source_reference_tokens"]) != 1
        or any(type(item) is not int or item < 1 for item in measurements["history_content_tokens"] + measurements["source_reference_tokens"])
    ):
        fail("token_measurement_invalid")
    total = measurements["prompt_tokens"] + EXPECTED_SCOPE_OUTPUT_RESERVE
    if (
        measurements["total_reserved_tokens"] != total
        or measurements["application_remaining_tokens"] != EXPECTED_APPLICATION_LIMIT - total
        or measurements["service_remaining_tokens"] != EXPECTED_MAX_MODEL_LEN - total
        or total > EXPECTED_APPLICATION_LIMIT
        or measurements["application_remaining_tokens"] < 0
    ):
        fail("context_budget_accounting_mismatch")
    print("purpose=evaluate_scope_classifier_request_tokens")
    print(f"served_model={EXPECTED_MODEL};configured_max_model_len={EXPECTED_MAX_MODEL_LEN}")
    print(f"tokenizer_identity={artifact['tokenizer_identity']};chat_template_sha256={artifact['chat_template_sha256']}")
    print(f"scope_policy_identity={artifact['scope_policy_identity']};scope_prompt_identity={artifact['prompt_identity']};scope_request_identity={artifact['request_identity']}")
    print(
        f"prompt_tokens={measurements['prompt_tokens']};scope_output_reserve={EXPECTED_SCOPE_OUTPUT_RESERVE};"
        f"total_reserved_tokens={total};application_context_limit={EXPECTED_APPLICATION_LIMIT};"
        f"application_remaining_tokens={measurements['application_remaining_tokens']}"
    )
    print(
        f"system_content_tokens={measurements['system_content_tokens']};"
        f"untrusted_payload_tokens={measurements['untrusted_payload_tokens']};"
        f"history_turns={len(measurements['history_content_tokens'])};source_references={len(measurements['source_reference_tokens'])}"
    )
    print("system_role_template_compatibility=pass;exact_scope_request_budget_fit=pass")
    print("model_called=false;credential_read=false;raw_text_retained=false")
    print("scope_request_token_evaluation=pass")
    print(f"measurement_artifact_sha256={sha256_file(artifact_path)}")


if __name__ == "__main__":
    main()
