#!/usr/bin/env python3
"""Evaluate content-free configured live-runtime qualification evidence."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any, Mapping, NoReturn


HEX = re.compile(r"^[0-9a-f]{64}$")
CONFIG_NAMES = {
    "api_profile.yaml",
    "deployment.yaml",
    "injection_profile.yaml",
    "method_profile.yaml",
    "query_resolution_profile.yaml",
    "reconstruction_profile.yaml",
    "relationship_types.yaml",
    "relevance_profile.yaml",
    "retrieval_service_profile.yaml",
    "runtime_dependencies.yaml",
    "scope_profile.yaml",
    "sufficiency_profile.yaml",
}
TRACE = [
    "request-accepted",
    "direct-injection-passed",
    "scope-allowed",
    "query-resolved",
    "retrieval-completed",
    "sufficiency-blocked",
]


def fail(reason: str) -> NoReturn:
    print(f"configured_live_runtime_evaluation=blocked;reason={reason}")
    raise SystemExit(1)


def exact_mapping(value: Any, fields: set[str], label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping) or set(value) != fields:
        fail(f"{label}_schema_invalid")
    return value


def digest(value: Any, label: str) -> str:
    if not isinstance(value, str) or HEX.fullmatch(value) is None:
        fail(f"{label}_invalid")
    return value


def validate(document: Any) -> Mapping[str, Any]:
    root = exact_mapping(
        document,
        {
            "application",
            "configuration_sha256",
            "dependencies",
            "environment_reads",
            "host_runtime",
            "purpose",
            "runtime_identity",
            "schema_version",
            "security",
            "synthetic_question_sha256",
        },
        "artifact",
    )
    if (
        root["schema_version"] != 1
        or root["purpose"] != "configured_live_runtime_empty_catalog_qualification"
    ):
        fail("artifact_identity_invalid")
    digest(root["runtime_identity"], "runtime_identity")
    digest(root["synthetic_question_sha256"], "synthetic_question")

    configuration = exact_mapping(root["configuration_sha256"], CONFIG_NAMES, "configuration")
    for name, value in configuration.items():
        digest(value, f"configuration_{name}")
    application = exact_mapping(
        root["application"],
        {
            "error_code",
            "http_status",
            "listener",
            "listener_shutdown",
            "request_id_valid",
            "stage_trace",
            "status",
        },
        "application",
    )
    if application != {
        "error_code": "EVIDENCE_INSUFFICIENT",
        "http_status": 200,
        "listener": "127.0.0.1:1384",
        "listener_shutdown": True,
        "request_id_valid": True,
        "stage_trace": TRACE,
        "status": "insufficient-evidence",
    }:
        fail("application_contract_invalid")
    dependencies = exact_mapping(
        root["dependencies"],
        {
            "database_connections",
            "embedding_calls",
            "grounded_generation_calls",
            "scope_calls",
            "tokenization_calls",
        },
        "dependencies",
    )
    if dependencies != {
        "database_connections": 1,
        "embedding_calls": 1,
        "grounded_generation_calls": 0,
        "scope_calls": 1,
        "tokenization_calls": 2,
    }:
        fail("dependency_counts_invalid")
    if exact_mapping(
        root["environment_reads"], {"gemma", "nomic", "postgresql"}, "environment_reads"
    ) != {"gemma": 3, "nomic": 1, "postgresql": 1}:
        fail("environment_read_counts_invalid")
    host = exact_mapping(
        root["host_runtime"],
        {"architecture", "psycopg_version", "pyyaml_version", "python_version"},
        "host_runtime",
    )
    if (
        host["architecture"] not in {"x86_64", "amd64"}
        or host["psycopg_version"] != "3.1.17"
        or host["pyyaml_version"] != "6.0.1"
        or not isinstance(host["python_version"], str)
        or re.fullmatch(r"3\.12\.[0-9]+", host["python_version"]) is None
    ):
        fail("host_runtime_invalid")
    security = exact_mapping(
        root["security"],
        {"credentials_retained", "raw_request_retained", "raw_response_retained", "vectors_retained"},
        "security",
    )
    if security != {
        "credentials_retained": False,
        "raw_request_retained": False,
        "raw_response_retained": False,
        "vectors_retained": False,
    }:
        fail("security_boundary_invalid")
    return root


def self_test() -> None:
    valid = {
        "application": {
            "error_code": "EVIDENCE_INSUFFICIENT",
            "http_status": 200,
            "listener": "127.0.0.1:1384",
            "listener_shutdown": True,
            "request_id_valid": True,
            "stage_trace": TRACE,
            "status": "insufficient-evidence",
        },
        "configuration_sha256": {name: "1" * 64 for name in CONFIG_NAMES},
        "dependencies": {
            "database_connections": 1,
            "embedding_calls": 1,
            "grounded_generation_calls": 0,
            "scope_calls": 1,
            "tokenization_calls": 2,
        },
        "environment_reads": {"gemma": 3, "nomic": 1, "postgresql": 1},
        "host_runtime": {
            "architecture": "x86_64",
            "psycopg_version": "3.1.17",
            "pyyaml_version": "6.0.1",
            "python_version": "3.12.3",
        },
        "purpose": "configured_live_runtime_empty_catalog_qualification",
        "runtime_identity": "2" * 64,
        "schema_version": 1,
        "security": {
            "credentials_retained": False,
            "raw_request_retained": False,
            "raw_response_retained": False,
            "vectors_retained": False,
        },
        "synthetic_question_sha256": "3" * 64,
    }
    validate(valid)
    print("configured_live_runtime_evaluator_self_test=pass")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact", type=Path)
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
        return
    if arguments.artifact is None:
        fail("artifact_required")
    path = arguments.artifact
    if not path.is_file() or path.is_symlink() or path.stat().st_size > 65536:
        fail("artifact_path_invalid")
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail("artifact_json_invalid")
    result = validate(document)
    print("configured_live_runtime_evaluation=pass")
    print("application_status=insufficient-evidence;http_status=200;stage_trace=pass")
    print("scope_calls=1;embedding_calls=1;database_connections=1;tokenization_calls=2;grounded_generation_calls=0")
    print("credentials_retained=false;raw_request_retained=false;raw_response_retained=false;vectors_retained=false")
    print(f"runtime_identity={result['runtime_identity']}")


if __name__ == "__main__":
    main()
