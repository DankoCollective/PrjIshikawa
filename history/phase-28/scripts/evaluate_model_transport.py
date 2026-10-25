#!/usr/bin/env python3
"""Validate a content-free application-host model-transport artifact."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any, Mapping, NoReturn


HOST = re.compile(r"^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$")
FIELDS = {
    "api_credentials_read",
    "architecture",
    "direct_native_ports_reachable",
    "embedding_calls",
    "identity_source",
    "inference_calls",
    "model_host",
    "organizational_content_used",
    "purpose",
    "python_version",
    "raw_health_bodies_retained",
    "schema_version",
    "tokenization_calls",
    "tunnel",
}


def fail(reason: str) -> NoReturn:
    print(f"model_transport_evaluation=blocked;reason={reason}")
    raise SystemExit(1)


def validate(document: Any) -> Mapping[str, Any]:
    if not isinstance(document, Mapping) or set(document) != FIELDS:
        fail("artifact_schema_invalid")
    if (
        document["schema_version"] != 1
        or document["purpose"] != "application_host_model_transport_qualification"
        or document["architecture"] not in {"x86_64", "amd64"}
        or not isinstance(document["python_version"], str)
        or re.fullmatch(r"3\.12\.[0-9]+", document["python_version"]) is None
        or not isinstance(document["model_host"], str)
        or HOST.fullmatch(document["model_host"]) is None
        or document["identity_source"] != "forwarded_ephemeral_agent"
        or document["direct_native_ports_reachable"] != {"gemma": False, "nomic": False}
        or document["api_credentials_read"] is not False
        or document["organizational_content_used"] is not False
        or document["raw_health_bodies_retained"] is not False
        or document["embedding_calls"] != 0
        or document["inference_calls"] != 0
        or document["tokenization_calls"] != 0
        or document["tunnel"]
        != {
            "connection_count": 1,
            "gemma_health_status": 200,
            "gemma_local_endpoint": "127.0.0.1:8000",
            "nomic_health_status": 200,
            "nomic_local_endpoint": "127.0.0.1:8001",
            "shutdown": "pass",
        }
    ):
        fail("artifact_contract_invalid")
    return document


def self_test() -> None:
    valid = {
        "api_credentials_read": False,
        "architecture": "x86_64",
        "direct_native_ports_reachable": {"gemma": False, "nomic": False},
        "embedding_calls": 0,
        "identity_source": "forwarded_ephemeral_agent",
        "inference_calls": 0,
        "model_host": "model.internal",
        "organizational_content_used": False,
        "purpose": "application_host_model_transport_qualification",
        "python_version": "3.12.3",
        "raw_health_bodies_retained": False,
        "schema_version": 1,
        "tokenization_calls": 0,
        "tunnel": {
            "connection_count": 1,
            "gemma_health_status": 200,
            "gemma_local_endpoint": "127.0.0.1:8000",
            "nomic_health_status": 200,
            "nomic_local_endpoint": "127.0.0.1:8001",
            "shutdown": "pass",
        },
    }
    validate(valid)
    print("model_transport_evaluator_self_test=pass")


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
    print(f"application_host_python={result['python_version']};architecture=amd64")
    print("direct_native_model_ports=blocked")
    print("ssh_tunnel_connections=1;forwarded_ports=8000,8001")
    print("gemma_health_status=200;nomic_health_status=200")
    print("tunnel_shutdown=pass;api_credentials_read=false;model_calls=0")
    print("model_transport_evaluation=pass")


if __name__ == "__main__":
    main()
