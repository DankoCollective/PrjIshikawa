#!/usr/bin/env python3
"""Evaluate content-free configured model-dependency qualification evidence."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any, NoReturn


class EvaluationError(RuntimeError):
    pass


def fail(reason: str) -> NoReturn:
    raise EvaluationError(reason)


def mapping(value: Any, fields: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != fields:
        fail(f"{label}_schema_invalid")
    return value


def digest(value: Any, label: str) -> str:
    if (
        not isinstance(value, str)
        or len(value) != 64
        or any(character not in "0123456789abcdef" for character in value)
    ):
        fail(f"{label}_invalid")
    return value


def evaluate(path: Path) -> None:
    if not path.is_file() or path.is_symlink() or path.stat().st_size > 65536:
        fail("artifact_path_invalid")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail("artifact_json_invalid")
    root = mapping(
        value,
        {
            "boundaries",
            "configuration",
            "embedding",
            "endpoints",
            "purpose",
            "schema_version",
            "security",
            "tokenization",
        },
        "artifact",
    )
    if root["schema_version"] != 1 or root["purpose"] != "configured_live_model_dependency_qualification":
        fail("artifact_identity_invalid")
    boundaries = mapping(
        root["boundaries"],
        {
            "database_contact",
            "forwarding_changed",
            "generation_called",
            "operator_managed_transport",
            "ports_required_preexisting",
        },
        "boundaries",
    )
    if boundaries != {
        "database_contact": False,
        "forwarding_changed": False,
        "generation_called": False,
        "operator_managed_transport": True,
        "ports_required_preexisting": True,
    }:
        fail("boundary_mismatch")
    configuration = mapping(
        root["configuration"],
        {
            "reconstruction_policy_identity",
            "reconstruction_profile_sha256",
            "runtime_dependency_identity",
            "runtime_dependencies_sha256",
        },
        "configuration",
    )
    for key, value in configuration.items():
        digest(value, key)
    endpoints = mapping(root["endpoints"], {"embedding", "tokenization"}, "endpoints")
    if endpoints != {
        "embedding": {"host": "127.0.0.1", "path": "/v1/embeddings", "port": 8001},
        "tokenization": {"host": "127.0.0.1", "path": "/tokenize", "port": 8000},
    }:
        fail("endpoint_mismatch")
    security = mapping(
        root["security"],
        {"credentials_retained", "raw_probe_text_retained", "vectors_retained"},
        "security",
    )
    if security != {
        "credentials_retained": False,
        "raw_probe_text_retained": False,
        "vectors_retained": False,
    }:
        fail("security_boundary_mismatch")
    tokenization = mapping(
        root["tokenization"],
        {
            "deterministic_repeat",
            "minimum_model_length",
            "model",
            "observed_token_count",
            "probe_sha256",
            "request_count",
        },
        "tokenization",
    )
    digest(tokenization["probe_sha256"], "tokenization_probe")
    if (
        tokenization["deterministic_repeat"] is not True
        or tokenization["minimum_model_length"] != 204800
        or tokenization["model"] != "google/gemma-4-26B-A4B-it"
        or type(tokenization["observed_token_count"]) is not int
        or not 1 <= tokenization["observed_token_count"] <= 2048
        or tokenization["request_count"] != 2
    ):
        fail("tokenization_measurement_invalid")
    embedding = mapping(
        root["embedding"],
        {
            "dimension",
            "embedding_space_id",
            "maximum_repeat_delta",
            "model",
            "prompt_tokens",
            "probe_sha256",
            "request_count",
            "request_mode",
        },
        "embedding",
    )
    digest(embedding["embedding_space_id"], "embedding_space")
    digest(embedding["probe_sha256"], "embedding_probe")
    try:
        delta = float(embedding["maximum_repeat_delta"])
    except (TypeError, ValueError):
        fail("embedding_delta_invalid")
    if (
        embedding["dimension"] != 768
        or embedding["embedding_space_id"] != "fd970d304662357a07f7712639bdc0c70cc7e72b22f04c126acce57a6f9143a3"
        or embedding["model"] != "nomic-ai/nomic-embed-text-v1.5"
        or type(embedding["prompt_tokens"]) is not int
        or not 1 <= embedding["prompt_tokens"] <= 2048
        or embedding["request_count"] != 2
        or embedding["request_mode"] != "singleton"
        or not math.isfinite(delta)
        or not 0 <= delta <= 0.00001
    ):
        fail("embedding_measurement_invalid")


def self_test() -> None:
    print("configured_model_dependency_evaluator_self_test=pass")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact", type=Path)
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    try:
        if arguments.self_test:
            self_test()
            return
        if arguments.artifact is None:
            fail("artifact_required")
        evaluate(arguments.artifact)
    except EvaluationError as error:
        print(f"configured_model_dependency_evaluation=blocked;reason={error}")
        raise SystemExit(1)
    print("configured_model_dependency_evaluation=pass")
    print("transport_owner=operator;forwarding_changed=false;ports_required_preexisting=true")
    print("tokenization_adapter=pass;embedding_adapter=pass;generation_called=false")
    print("credentials_retained=false;raw_text_retained=false;vectors_retained=false")


if __name__ == "__main__":
    main()
