#!/usr/bin/env python3
"""Validate the content-free application-host runtime qualification artifact."""

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
FIELDS = {
    "application_status",
    "architecture",
    "configuration_sha256",
    "dependency_calls",
    "environment_reads",
    "external_dependency_reachability",
    "http_status",
    "listener",
    "organizational_content_used",
    "purpose",
    "pyyaml_version",
    "python_version",
    "raw_request_retained",
    "raw_response_retained",
    "request_id_valid",
    "runtime_identity",
    "schema_version",
    "secret_values_read",
}


def fail(reason: str) -> NoReturn:
    print(f"application_host_runtime_evaluation=blocked;reason={reason}")
    raise SystemExit(1)


def validate(document: Any) -> Mapping[str, Any]:
    if not isinstance(document, Mapping) or set(document) != FIELDS:
        fail("artifact_schema_invalid")
    configuration = document["configuration_sha256"]
    listener = document["listener"]
    if (
        document["schema_version"] != 1
        or document["purpose"] != "configured_application_host_runtime_qualification"
        or document["application_status"] != "security-rejected"
        or document["architecture"] not in {"x86_64", "amd64"}
        or not isinstance(document["python_version"], str)
        or re.fullmatch(r"3\.12\.[0-9]+", document["python_version"]) is None
        or document["pyyaml_version"] != "6.0.1"
        or document["http_status"] != 200
        or document["dependency_calls"] != 0
        or document["environment_reads"] != 0
        or document["external_dependency_reachability"] != "not_qualified"
        or document["organizational_content_used"] is not False
        or document["raw_request_retained"] is not False
        or document["raw_response_retained"] is not False
        or document["request_id_valid"] is not True
        or document["secret_values_read"] is not False
        or not isinstance(document["runtime_identity"], str)
        or HEX.fullmatch(document["runtime_identity"]) is None
        or not isinstance(configuration, Mapping)
        or set(configuration) != CONFIG_NAMES
        or any(not isinstance(value, str) or HEX.fullmatch(value) is None for value in configuration.values())
        or listener != {
            "bind_host": "127.0.0.1",
            "chat_path": "/v1/chat",
            "port": 1384,
            "shutdown": "pass",
        }
    ):
        fail("artifact_contract_invalid")
    return document


def self_test() -> None:
    valid = {
        "application_status": "security-rejected",
        "architecture": "x86_64",
        "configuration_sha256": {name: "1" * 64 for name in CONFIG_NAMES},
        "dependency_calls": 0,
        "environment_reads": 0,
        "external_dependency_reachability": "not_qualified",
        "http_status": 200,
        "listener": {"bind_host": "127.0.0.1", "chat_path": "/v1/chat", "port": 1384, "shutdown": "pass"},
        "organizational_content_used": False,
        "purpose": "configured_application_host_runtime_qualification",
        "pyyaml_version": "6.0.1",
        "python_version": "3.12.3",
        "raw_request_retained": False,
        "raw_response_retained": False,
        "request_id_valid": True,
        "runtime_identity": "2" * 64,
        "schema_version": 1,
        "secret_values_read": False,
    }
    validate(valid)
    print("application_host_runtime_evaluator_self_test=pass")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact")
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
        return
    if not arguments.artifact:
        fail("artifact_argument_missing")
    path = Path(arguments.artifact)
    if not path.is_file() or path.is_symlink():
        fail("artifact_missing_or_unsafe")
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail("artifact_json_invalid")
    result = validate(document)
    print(
        f"application_host_python={result['python_version']};"
        f"pyyaml={result['pyyaml_version']};architecture=amd64"
    )
    print("runtime_assembly=pass;configuration_profiles=12;listener=127.0.0.1:1384")
    print("synthetic_security_short_circuit=pass;dependency_calls=0;secret_values_read=false")
    print("external_dependency_reachability=not_qualified")
    print("application_host_runtime_evaluation=pass")


if __name__ == "__main__":
    main()
