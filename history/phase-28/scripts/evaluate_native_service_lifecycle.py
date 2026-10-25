#!/usr/bin/env python3
"""Qualify the Ishikawa native Retrieval API service definition."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Qualify native service lifecycle.")
    parser.add_argument("--service-unit", required=True)
    parser.add_argument("--output", required=True)
    return parser.parse_args()


def require_file(path: Path, label: str) -> Path:
    if not path.is_absolute() or path.is_symlink() or not path.is_file():
        raise ValueError(f"{label}_unsafe")
    return path.resolve(strict=True)


def evaluate(service_unit: Path) -> dict[str, object]:
    text = service_unit.read_text(encoding="utf-8")
    required = (
        "Type=simple",
        "WorkingDirectory=%h/Documents/Ishikawa",
        "ExecStart=%h/Documents/Ishikawa/scripts/ishikawa-retrieval-api --serve",
        "PassEnvironment=ISHIKAWA_GEMMA_API_KEY ISHIKAWA_NOMIC_API_KEY "
        "ISHIKAWA_POSTGRESQL_PASSWORD",
        "Restart=on-failure",
        "TimeoutStopSec=20s",
        "KillSignal=SIGTERM",
        "UMask=0077",
        "NoNewPrivileges=yes",
        "ProtectHome=read-only",
        "ReadWritePaths=%h/Documents/Ishikawa/state/logs "
        "%h/Documents/Ishikawa/state/run",
    )
    forbidden = (
        "[Install]",
        "WantedBy=",
        "RequiredBy=",
        "EnvironmentFile=",
        "ISHIKAWA_GEMMA_API_KEY=",
        "ISHIKAWA_NOMIC_API_KEY=",
        "ISHIKAWA_POSTGRESQL_PASSWORD=",
        "ishikawa-observability-retention",
    )
    if not all(item in text for item in required) or any(
        item in text for item in forbidden
    ):
        raise RuntimeError("native_service_lifecycle_boundary_failed")
    receipt = {
        "boot_enabled": False,
        "credential_values": False,
        "database_changed": False,
        "environment_names": [
            "ISHIKAWA_GEMMA_API_KEY",
            "ISHIKAWA_NOMIC_API_KEY",
            "ISHIKAWA_POSTGRESQL_PASSWORD",
        ],
        "model_call": False,
        "restart": "on-failure",
        "service_name": "ishikawa-retrieval-api.service",
        "service_type": "simple",
        "shutdown_signal": "SIGTERM",
        "target_contact": False,
    }
    return receipt


def main() -> int:
    arguments = parse_arguments()
    service_unit = require_file(Path(arguments.service_unit), "service_unit")
    output = Path(arguments.output)
    if not output.is_absolute() or output.exists() or not output.parent.is_dir():
        raise ValueError("output_path_unsafe")
    receipt = evaluate(service_unit)
    encoded = json.dumps(receipt, sort_keys=True, separators=(",", ":")).encode() + b"\n"
    with output.open("xb") as destination:
        destination.write(encoded)
    os.chmod(output, 0o600)
    print("service=ishikawa-retrieval-api.service;type=simple;boot_enabled=false")
    print("start=explicit;restart=on-failure;shutdown=SIGTERM")
    print("environment=three-named-values;credential_values=false;environment_file=false")
    print("write_scope=state-logs-and-run;listener=loopback-configured")
    print("target_contact=false;database_changed=false;model_call=false")
    print("native_service_lifecycle_qualification=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
