#!/usr/bin/env python3
"""Qualify concrete Ishikawa readiness with injected local dependencies.

Role:
    This helper proves lazy assembly, the complete ready state, and each
    fail-closed readiness category without contacting a real dependency.

Mental model:
    Build a temporary installed layout, inject one read-only active database
    and two healthy model endpoints, then perturb configuration, storage,
    corpus state, and health results one category at a time.
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
import tempfile
from pathlib import Path
from typing import Any


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Qualify concrete readiness locally.")
    parser.add_argument("--python-root", required=True)
    parser.add_argument("--config-root", required=True)
    parser.add_argument("--output", required=True)
    return parser.parse_args()


def require_directory(path: Path, label: str) -> Path:
    if not path.is_absolute() or path.is_symlink() or not path.is_dir():
        raise ValueError(f"{label}_unsafe")
    return path.resolve(strict=True)


def require_output(path: Path) -> Path:
    if not path.is_absolute() or path.exists() or path.is_symlink() or not path.parent.is_dir():
        raise ValueError("output_path_unsafe")
    return path


class Result:
    def __init__(self, row: tuple[str, str, bool]):
        self.row = row

    def fetchone(self) -> tuple[str, str, bool]:
        return self.row


class Connection:
    def __init__(self, row: tuple[str, str, bool]):
        self.row = row
        self.rolled_back = False
        self.closed = False

    def execute(self, statement: str) -> Result:
        if "ishikawa.readiness.active-corpus.v1" not in statement:
            raise ValueError("database_statement_invalid")
        return Result(self.row)

    def rollback(self) -> None:
        self.rolled_back = True

    def close(self) -> None:
        self.closed = True


def write_receipt(path: Path, payload: dict[str, Any]) -> None:
    encoded = json.dumps(
        payload,
        ensure_ascii=True,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8") + b"\n"
    with path.open("xb") as output_stream:
        output_stream.write(encoded)


def evaluate(python_root: Path, config_source: Path) -> dict[str, Any]:
    sys.path.insert(0, str(python_root))
    from ishikawa.readiness import (
        ActiveCorpusProbe,
        HealthHTTPResponse,
        NativeHealthProbe,
        ProtectedStorageProbe,
        assemble_configured_readiness_probe,
    )
    from ishikawa.runtime import assemble_configured_retrieval_runtime

    environment_reads: list[str] = []

    class Environment(dict[str, str]):
        def __getitem__(self, key: str) -> str:
            environment_reads.append(key)
            return super().__getitem__(key)

    environment = Environment(
        {
            "ISHIKAWA_GEMMA_API_KEY": "injected-gemma-credential",
            "ISHIKAWA_NOMIC_API_KEY": "injected-nomic-credential",
            "ISHIKAWA_POSTGRESQL_PASSWORD": "injected-database-credential",
        }
    )
    database_connections: list[Connection] = []
    health_ports: list[int] = []

    def connect(**_parameters: Any) -> Connection:
        connection = Connection(("rag_retrieval", "on", True))
        database_connections.append(connection)
        return connection

    def healthy_exchange(request: Any) -> HealthHTTPResponse:
        health_ports.append(request.endpoint.port)
        return HealthHTTPResponse(200, 0)

    with tempfile.TemporaryDirectory(prefix="ishikawa-readiness-") as temporary_root:
        product_root = Path(temporary_root) / "Ishikawa"
        config_root = product_root / "config"
        logs_root = product_root / "state/logs"
        config_root.mkdir(parents=True)
        logs_root.mkdir(parents=True)
        for source in config_source.glob("*.yaml"):
            shutil.copyfile(source, config_root / source.name)

        runtime = assemble_configured_retrieval_runtime(
            config_root,
            environment=environment,
        )
        readiness = assemble_configured_readiness_probe(
            product_root,
            runtime,
            environment=environment,
            database_connector=connect,
            health_exchange=healthy_exchange,
        )
        lazy_assembly = not environment_reads and not database_connections and not health_ports
        complete_ready = readiness()

        drift_path = config_root / "scope_profile.yaml"
        original = drift_path.read_bytes()
        drift_path.write_bytes(original + b"# qualification drift\n")
        configuration_drift_closed = not readiness()
        drift_path.write_bytes(original)

        hidden_logs = product_root / "state/logs-hidden"
        logs_root.rename(hidden_logs)
        storage_missing_closed = not readiness()
        hidden_logs.rename(logs_root)

        inactive_connection = Connection(("rag_retrieval", "on", False))
        inactive_corpus_closed = not ActiveCorpusProbe(lambda: inactive_connection)()
        database_cleanup = inactive_connection.rolled_back and inactive_connection.closed

        failed_health = NativeHealthProbe(
            readiness.gemma_probe.endpoint,
            lambda: "injected-gemma-credential",
            lambda _request: HealthHTTPResponse(503, 0),
        )
        unhealthy_model_closed = not failed_health()

    expected_reads = [
        "ISHIKAWA_POSTGRESQL_PASSWORD",
        "ISHIKAWA_GEMMA_API_KEY",
        "ISHIKAWA_NOMIC_API_KEY",
    ] * 3
    if not (
        lazy_assembly
        and complete_ready
        and configuration_drift_closed
        and storage_missing_closed
        and inactive_corpus_closed
        and database_cleanup
        and unhealthy_model_closed
        and environment_reads == expected_reads
        and len(database_connections) == 3
        and all(connection.rolled_back and connection.closed for connection in database_connections)
        and health_ports == [8000, 8001] * 3
    ):
        raise ValueError("readiness_qualification_failed")

    return {
        "active_corpus_required": True,
        "component_count": 5,
        "configuration_drift_fails_closed": True,
        "credential_reads_during_assembly": 0,
        "database_cleanup": True,
        "dependency_contact_during_assembly": False,
        "healthy_result": True,
        "health_endpoint_count": 2,
        "inactive_corpus_fails_closed": True,
        "purpose": "concrete_readiness_qualification",
        "receipt_schema_version": 1,
        "storage_missing_fails_closed": True,
        "target_contact": False,
        "unhealthy_model_fails_closed": True,
    }


def main() -> int:
    arguments = parse_arguments()
    try:
        python_root = require_directory(Path(arguments.python_root), "python_root")
        config_root = require_directory(Path(arguments.config_root), "config_root")
        output_path = require_output(Path(arguments.output))
        result = evaluate(python_root, config_root)
        write_receipt(output_path, result)
    except (OSError, ValueError) as error:
        print(f"concrete_readiness_qualification=blocked;reason={error}", file=sys.stderr)
        return 1
    print("readiness_components=5;complete_ready=true;active_corpus_required=true")
    print("lazy_assembly=true;credential_reads=0;dependency_contact=false")
    print("configuration_drift=not-ready;storage_missing=not-ready")
    print("inactive_corpus=not-ready;unhealthy_model=not-ready")
    print("database_cleanup=pass;client_component_details=false")
    print("concrete_readiness_qualification=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
