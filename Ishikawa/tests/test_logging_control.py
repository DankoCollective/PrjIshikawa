from __future__ import annotations

import io
import json
import os
import socket
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from ishikawa.logging_control import (
    CONTROL_REQUEST_SCHEMA,
    LoggingControlError,
    LoggingControlRequest,
    LoggingControlServer,
    decode_control_request,
    decode_control_response,
    encode_control_request,
    execute_logging_control,
    native_control_exchange,
)
from ishikawa.observability import ConfiguredObservability, validate_logging_profile
from ishikawa.yaml_loader import load_restricted_yaml


def identity(character: str) -> str:
    return character * 64


class FixedClock:
    def __call__(self) -> datetime:
        return datetime(2026, 10, 21, 1, 0, tzinfo=timezone.utc)


class LoggingControlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[1]
        cls.policy = validate_logging_profile(
            load_restricted_yaml(
                root / "config/templates/logging_profile.yaml",
                label="logging profile",
            )
        )

    def configured(self, root: Path) -> ConfiguredObservability:
        log_root = root / "state/logs"
        run_root = root / "state/run"
        log_root.mkdir(parents=True)
        run_root.mkdir(parents=True)
        return ConfiguredObservability(
            self.policy,
            log_root,
            FixedClock(),
            control_root=run_root,
        )

    def test_request_contract_is_exact_bounded_and_duplicate_safe(self):
        request = LoggingControlRequest(
            "enable",
            "investigate_response",
            300,
            identity("a"),
        )
        self.assertEqual(decode_control_request(encode_control_request(request)[:-1]), request)
        for encoded in (
            b'{"action":"status","action":"disable","schema":"'
            + CONTROL_REQUEST_SCHEMA.encode()
            + b'"}',
            json.dumps(
                {
                    "action": "status",
                    "schema": CONTROL_REQUEST_SCHEMA,
                    "extra": True,
                }
            ).encode(),
            b"x" * 4097,
        ):
            with self.subTest(encoded=encoded[:40]), self.assertRaises(LoggingControlError):
                decode_control_request(encoded)

    def test_owner_only_server_supports_status_enable_and_disable(self):
        with tempfile.TemporaryDirectory() as temporary_root:
            root = Path(temporary_root) / "Ishikawa"
            observability = self.configured(root)
            server = LoggingControlServer(observability, root / "state/run")
            server.start()
            try:
                self.assertEqual(os.stat(server.socket_path).st_mode & 0o777, 0o600)
                status = decode_control_response(
                    native_control_exchange(
                        server.socket_path,
                        encode_control_request(LoggingControlRequest("status")),
                    )
                )
                self.assertEqual(status["profile"], "default")
                enabled = decode_control_response(
                    native_control_exchange(
                        server.socket_path,
                        encode_control_request(
                            LoggingControlRequest(
                                "enable",
                                "investigate_response",
                                300,
                                identity("b"),
                            )
                        ),
                    )
                )
                self.assertEqual(enabled["profile"], "verbose")
                self.assertEqual(observability.controller.active_profile(), "default")
                self.assertEqual(
                    observability.controller.active_profile(identity("b")), "verbose"
                )
                disabled = decode_control_response(
                    native_control_exchange(
                        server.socket_path,
                        encode_control_request(LoggingControlRequest("disable")),
                    )
                )
                self.assertEqual(disabled["profile"], "default")
            finally:
                server.stop()
            self.assertFalse(server.failed)
            self.assertFalse(server.socket_path.exists())
            events = [
                json.loads(line)["event_code"]
                for line in (root / "state/logs/audit.jsonl")
                .read_text(encoding="utf-8")
                .splitlines()
            ]
            self.assertEqual(
                events,
                ["VERBOSE_CAPTURE_ENABLED", "VERBOSE_CAPTURE_DISABLED"],
            )

    def test_installed_command_uses_fixed_product_socket(self):
        with tempfile.TemporaryDirectory() as temporary_root:
            root = Path(temporary_root) / "Ishikawa"
            observability = self.configured(root)
            server = LoggingControlServer(observability, root / "state/run")
            server.start()
            try:
                output = io.StringIO()
                result = execute_logging_control(
                    [
                        "enable",
                        "--reason",
                        "incident_review",
                        "--duration-seconds",
                        "60",
                        "--scope",
                        "service",
                    ],
                    product_root=root,
                    output=output,
                )
                self.assertEqual(result, 0)
                self.assertEqual(
                    output.getvalue(),
                    "ishikawa_logging_control=pass;action=enable;profile=verbose\n",
                )
            finally:
                server.stop()

    def test_bad_arguments_fail_without_contacting_a_socket(self):
        with tempfile.TemporaryDirectory() as temporary_root:
            root = Path(temporary_root) / "Ishikawa"
            root.mkdir()
            output = io.StringIO()
            result = execute_logging_control(
                ["enable", "--duration-seconds", "60", "--scope", "service"],
                product_root=root,
                output=output,
            )
        self.assertEqual(result, 1)
        self.assertEqual(
            output.getvalue(),
            "ishikawa_logging_control=blocked;reason=control_unavailable\n",
        )

    def test_malformed_request_fails_closed_without_stopping_server(self):
        with tempfile.TemporaryDirectory() as temporary_root:
            root = Path(temporary_root) / "Ishikawa"
            observability = self.configured(root)
            server = LoggingControlServer(observability, root / "state/run")
            server.start()
            try:
                client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                client.connect(str(server.socket_path))
                client.sendall(b"not-json\n")
                client.shutdown(socket.SHUT_WR)
                rejected = decode_control_response(client.recv(4096).rstrip(b"\n"))
                client.close()
                self.assertEqual(rejected["status"], "error")
                accepted = decode_control_response(
                    native_control_exchange(
                        server.socket_path,
                        encode_control_request(LoggingControlRequest("status")),
                    )
                )
                self.assertEqual(accepted["status"], "ok")
            finally:
                server.stop()

    def test_existing_socket_path_is_never_replaced(self):
        with tempfile.TemporaryDirectory() as temporary_root:
            root = Path(temporary_root) / "Ishikawa"
            observability = self.configured(root)
            socket_path = root / "state/run/logging-control.sock"
            socket_path.write_text("operator-owned", encoding="utf-8")
            server = LoggingControlServer(observability, root / "state/run")
            with self.assertRaises(LoggingControlError):
                server.start()
            self.assertEqual(socket_path.read_text(encoding="utf-8"), "operator-owned")


if __name__ == "__main__":
    unittest.main()
