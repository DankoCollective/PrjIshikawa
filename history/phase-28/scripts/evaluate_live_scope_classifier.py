#!/usr/bin/env python3
"""Evaluate one protected synthetic live scope-classifier artifact."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any, NoReturn


EXPECTED_MODEL = "google/gemma-4-26B-A4B-it"
HEX = re.compile(r"^[0-9a-f]{64}$")


def fail(reason: str) -> NoReturn:
    print(f"live_scope_classifier_evaluation=blocked;reason={reason}")
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


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact", required=True)
    parser.add_argument("--measurement", required=True)
    parser.add_argument("--expected-measurement-sha256", required=True)
    parser.add_argument("--expected-source-sha256", required=True)
    parser.add_argument("--expected-request-identity", required=True)
    parser.add_argument("--expected-prompt-identity", required=True)
    parser.add_argument("--expected-policy-identity", required=True)
    arguments = parser.parse_args()
    artifact_path = Path(arguments.artifact)
    measurement_path = Path(arguments.measurement)
    if sha256_file(measurement_path) != arguments.expected_measurement_sha256:
        fail("measurement_identity_mismatch")
    artifact = read_json(artifact_path, "artifact_invalid")
    measurement = read_json(measurement_path, "measurement_invalid")
    for value in (
        arguments.expected_source_sha256,
        arguments.expected_request_identity,
        arguments.expected_prompt_identity,
        arguments.expected_policy_identity,
    ):
        if HEX.fullmatch(value) is None:
            fail("expected_identity_invalid")
    required = {
        "clarification", "completion_tokens", "decision", "finish_reason", "model",
        "policy_identity", "prompt_identity", "prompt_tokens", "purpose", "reason_code",
        "request_identity", "schema_version", "source_sha256", "synthetic_only", "total_tokens",
    }
    offline_prompt_tokens = measurement.get("measurements", {}).get("prompt_tokens")
    if (
        not isinstance(artifact, dict)
        or set(artifact) != required
        or measurement.get("purpose") != "scope_classifier_request_token_measurement"
        or type(offline_prompt_tokens) is not int
        or artifact["purpose"] != "bounded_live_scope_classification"
        or artifact["schema_version"] != 1
        or artifact["synthetic_only"] is not True
        or artifact["model"] != EXPECTED_MODEL
        or artifact["source_sha256"] != arguments.expected_source_sha256
        or artifact["request_identity"] != arguments.expected_request_identity
        or artifact["prompt_identity"] != arguments.expected_prompt_identity
        or artifact["policy_identity"] != arguments.expected_policy_identity
        or artifact["finish_reason"] != "stop"
        or artifact["decision"] != "allow"
        or artifact["reason_code"] != "prior_answer_or_source_followup"
        or artifact["clarification"] is not None
        or type(artifact["prompt_tokens"]) is not int
        or artifact["prompt_tokens"] not in {offline_prompt_tokens, offline_prompt_tokens + 1}
        or type(artifact["completion_tokens"]) is not int
        or not 1 <= artifact["completion_tokens"] <= 128
        or artifact["total_tokens"] != artifact["prompt_tokens"] + artifact["completion_tokens"]
    ):
        fail("artifact_contract_mismatch")
    print("purpose=evaluate_bounded_live_scope_classifier")
    print(
        f"model={EXPECTED_MODEL};offline_prompt_tokens={offline_prompt_tokens};"
        f"live_prompt_tokens={artifact['prompt_tokens']};prompt_token_delta={artifact['prompt_tokens'] - offline_prompt_tokens}"
    )
    print(
        f"completion_tokens={artifact['completion_tokens']};total_tokens={artifact['total_tokens']};"
        f"decision={artifact['decision']};reason_code={artifact['reason_code']}"
    )
    print("strict_response_validation=pass;expected_scope_decision=pass;clarification_semantics=pass")
    print("synthetic_only=true;raw_text_in_routine_report=false")
    print("live_scope_classifier_evaluation=pass")
    print(f"scope_artifact_sha256={sha256_file(artifact_path)}")


if __name__ == "__main__":
    main()
