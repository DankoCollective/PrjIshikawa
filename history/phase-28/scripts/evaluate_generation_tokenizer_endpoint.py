#!/usr/bin/env python3
"""Evaluate a content-free configured-tokenizer endpoint artifact."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any, Mapping, NoReturn


EXPECTED_MODEL = "google/gemma-4-26B-A4B-it"
HEX = re.compile(r"^[0-9a-f]{64}$")
FIELDS = {
    "add_special_tokens",
    "credential_retained",
    "deterministic_repeat",
    "endpoint_path",
    "endpoint_scope",
    "minimum_model_length",
    "model_generation_called",
    "observed_token_count",
    "probe_sha256",
    "purpose",
    "raw_text_retained",
    "request_count",
    "response_contract",
    "schema_version",
    "served_model",
}


def fail(reason: str) -> NoReturn:
    print(f"generation_tokenizer_endpoint_evaluation=blocked;reason={reason}")
    raise SystemExit(1)


def validate(document: Any, expected_probe_sha256: str) -> Mapping[str, Any]:
    if not isinstance(document, Mapping) or set(document) != FIELDS:
        fail("artifact_schema_invalid")
    count = document["observed_token_count"]
    if (
        document["schema_version"] != 1
        or document["purpose"] != "configured_generation_tokenizer_endpoint_qualification"
        or document["served_model"] != EXPECTED_MODEL
        or document["endpoint_scope"] != "loopback"
        or document["endpoint_path"] != "/tokenize"
        or document["minimum_model_length"] != 204800
        or document["request_count"] != 2
        or document["add_special_tokens"] is not True
        or document["deterministic_repeat"] is not True
        or document["response_contract"] != "validated"
        or document["raw_text_retained"] is not False
        or document["credential_retained"] is not False
        or document["model_generation_called"] is not False
        or document["probe_sha256"] != expected_probe_sha256
        or HEX.fullmatch(expected_probe_sha256) is None
        or type(count) is not int
        or not 1 <= count <= 2048
    ):
        fail("artifact_contract_invalid")
    return document


def self_test() -> None:
    probe = "1" * 64
    valid = {
        "add_special_tokens": True,
        "credential_retained": False,
        "deterministic_repeat": True,
        "endpoint_path": "/tokenize",
        "endpoint_scope": "loopback",
        "minimum_model_length": 204800,
        "model_generation_called": False,
        "observed_token_count": 13,
        "probe_sha256": probe,
        "purpose": "configured_generation_tokenizer_endpoint_qualification",
        "raw_text_retained": False,
        "request_count": 2,
        "response_contract": "validated",
        "schema_version": 1,
        "served_model": EXPECTED_MODEL,
    }
    validate(valid, probe)
    print("generation_tokenizer_endpoint_evaluator_self_test=pass")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact")
    parser.add_argument("--expected-probe-sha256")
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
        return
    if not arguments.artifact or not arguments.expected_probe_sha256:
        fail("arguments_missing")
    path = Path(arguments.artifact)
    if not path.is_file() or path.is_symlink():
        fail("artifact_missing_or_unsafe")
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail("artifact_json_invalid")
    result = validate(document, arguments.expected_probe_sha256)
    print(f"endpoint_scope=loopback;endpoint_path=/tokenize;served_model={EXPECTED_MODEL}")
    print(
        f"requests=2;observed_token_count={result['observed_token_count']};"
        "deterministic_repeat=true"
    )
    print(
        "response_contract=validated;minimum_model_length=204800;"
        "model_generation_called=false"
    )
    print("raw_text_retained=false;credential_retained=false")
    print("generation_tokenizer_endpoint_evaluation=pass")


if __name__ == "__main__":
    main()
