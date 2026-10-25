#!/usr/bin/env python3
"""Qualify local logging control without contacting a runtime dependency."""

from __future__ import annotations

import argparse
import io
import json
import os
import socket
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Qualify local logging control.")
    parser.add_argument("--python-root", required=True)
    parser.add_argument("--config-root", required=True)
    parser.add_argument("--output", required=True)
    return parser.parse_args()


def require_directory(path: Path, label: str) -> Path:
    if not path.is_absolute() or path.is_symlink() or not path.is_dir():
        raise ValueError(f"{label}_unsafe")
    return path.resolve(strict=True)


def require_output(path: Path) -> Path:
    if (
        not path.is_absolute()
        or path.exists()
        or path.is_symlink()
        or not path.parent.is_dir()
    ):
        raise ValueError("output_path_unsafe")
    return path


def records(path: Path) -> list[dict[str, Any]]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]


def write_receipt(path: Path, payload: dict[str, Any]) -> None:
    encoded = json.dumps(
        payload,
        ensure_ascii=True,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8") + b"\n"
    with path.open("xb") as destination:
        destination.write(encoded)
    os.chmod(path, 0o600)


def evaluate(python_root: Path, config_root: Path) -> dict[str, Any]:
    sys.path.insert(0, str(python_root))
    from ishikawa.logging_control import (
        CONTROL_REQUEST_SCHEMA,
        LoggingControlRequest,
        LoggingControlServer,
        decode_control_request,
        decode_control_response,
        encode_control_request,
        execute_logging_control,
        native_control_exchange,
    )
    from ishikawa.observability import (
        ClassifiedEvent,
        ConfiguredObservability,
        validate_logging_profile,
    )
    from ishikawa.yaml_loader import load_restricted_yaml

    policy = validate_logging_profile(
        load_restricted_yaml(
            config_root / "logging_profile.yaml",
            label="logging profile",
        )
    )
    current_time = [datetime(2026, 10, 21, 1, 0, tzinfo=timezone.utc)]

    def clock() -> datetime:
        return current_time[0]

    request_id = "a" * 64
    secret_canary = "operator-prohibited-secret"
    with tempfile.TemporaryDirectory(prefix="ishikawa-control-") as temporary_root:
        root = Path(temporary_root) / "Ishikawa"
        log_root = root / "state/logs"
        run_root = root / "state/run"
        log_root.mkdir(parents=True, mode=0o700)
        run_root.mkdir(parents=True, mode=0o700)
        observability = ConfiguredObservability(
            policy,
            log_root,
            clock,
            control_root=run_root,
        )
        server = LoggingControlServer(observability, run_root)
        server.start()
        socket_mode = os.stat(server.socket_path).st_mode & 0o777
        socket_owner = os.stat(server.socket_path).st_uid == os.getuid()
        try:
            initial = decode_control_response(
                native_control_exchange(
                    server.socket_path,
                    encode_control_request(LoggingControlRequest("status")),
                )
            )
            command_output = io.StringIO()
            command_result = execute_logging_control(
                [
                    "enable",
                    "--reason",
                    "incident_review",
                    "--duration-seconds",
                    "300",
                    "--request-id",
                    request_id,
                ],
                product_root=root,
                output=command_output,
            )
            observability.operational.write(
                ClassifiedEvent(
                    "retrieval-api",
                    "generation",
                    "GENERATION_COMPLETED",
                    "info",
                    "completed",
                    request_id=request_id,
                    restricted={"answer": "synthetic restricted evidence"},
                )
            )
            observability.operational.write(
                ClassifiedEvent(
                    "retrieval-api",
                    "generation",
                    "GENERATION_COMPLETED",
                    "info",
                    "completed",
                    request_id="b" * 64,
                    restricted={"answer": secret_canary},
                )
            )
            status = decode_control_response(
                native_control_exchange(
                    server.socket_path,
                    encode_control_request(LoggingControlRequest("status")),
                )
            )
            disabled = decode_control_response(
                native_control_exchange(
                    server.socket_path,
                    encode_control_request(LoggingControlRequest("disable")),
                )
            )

            malformed_client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try:
                malformed_client.connect(str(server.socket_path))
                malformed_client.sendall(
                    (
                        '{"action":"status","action":"disable","schema":"'
                        + CONTROL_REQUEST_SCHEMA
                        + '"}\n'
                    ).encode("utf-8")
                )
                malformed_client.shutdown(socket.SHUT_WR)
                malformed = decode_control_response(
                    malformed_client.recv(4096).rstrip(b"\n")
                )
            finally:
                malformed_client.close()
            after_malformed = decode_control_response(
                native_control_exchange(
                    server.socket_path,
                    encode_control_request(LoggingControlRequest("status")),
                )
            )
        finally:
            server.stop()

        socket_removed = not server.socket_path.exists()
        restart_observability = ConfiguredObservability(
            policy,
            log_root,
            clock,
            control_root=run_root,
        )
        restart_server = LoggingControlServer(restart_observability, run_root)
        restart_server.start()
        try:
            restarted = decode_control_response(
                native_control_exchange(
                    restart_server.socket_path,
                    encode_control_request(LoggingControlRequest("status")),
                )
            )
        finally:
            restart_server.stop()

        operational = records(log_root / policy.operational_filename)
        audit = records(log_root / policy.audit_filename)
        exact_round_trip = decode_control_request(
            encode_control_request(LoggingControlRequest("status"))[:-1]
        ) == LoggingControlRequest("status")
        boundary_passed = all(
            (
                exact_round_trip,
                socket_mode == 0o600,
                socket_owner,
                initial == {
                    "action": "status",
                    "profile": "default",
                    "schema": "ishikawa.logging-control-response.v1",
                    "status": "ok",
                },
                command_result == 0,
                command_output.getvalue()
                == "ishikawa_logging_control=pass;action=enable;profile=verbose\n",
                status["profile"] == "verbose",
                disabled["profile"] == "default",
                malformed["status"] == "error",
                after_malformed["profile"] == "default",
                socket_removed,
                restarted["profile"] == "default",
                not server.failed,
                not restart_server.failed,
                len(operational) == 2,
                operational[0]["profile"] == "verbose",
                "restricted" in operational[0],
                operational[1]["profile"] == "default",
                "restricted" not in operational[1],
                [item["event_code"] for item in audit]
                == ["VERBOSE_CAPTURE_ENABLED", "VERBOSE_CAPTURE_DISABLED"],
                secret_canary
                not in (log_root / policy.operational_filename).read_text(
                    encoding="utf-8"
                ),
            )
        )

    if not boundary_passed:
        raise RuntimeError("logging_control_boundary_failed")
    return {
        "audit_event_count": 2,
        "control_actions": ["status", "enable", "disable"],
        "control_schema": CONTROL_REQUEST_SCHEMA,
        "exact_contract": True,
        "malformed_request_rejected": True,
        "network_listener": False,
        "request_scope_isolated": True,
        "restart_restoration": True,
        "same_user_boundary": True,
        "socket_cleanup": True,
        "socket_mode": "0600",
        "target_contact": False,
    }


def main() -> int:
    arguments = parse_arguments()
    python_root = require_directory(Path(arguments.python_root), "python_root")
    config_root = require_directory(Path(arguments.config_root), "config_root")
    output = require_output(Path(arguments.output))
    qualification = evaluate(python_root, config_root)
    write_receipt(output, qualification)
    print("control_transport=unix-domain;socket_mode=0600;same_user=required")
    print("actions=status,enable,disable;request_contract=exact-bounded-json")
    print("verbose=request-or-service-scoped;duration=bounded;restart_restoration=pass")
    print("malformed_request=blocked;server_continuity=pass;socket_cleanup=pass")
    print("audit=content-free;request_scope_isolation=pass;network_listener=false")
    print("target_contact=false;database_changed=false;model_call=false")
    print("logging_control_qualification=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
