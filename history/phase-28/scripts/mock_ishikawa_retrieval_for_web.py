#!/usr/bin/env python3
"""Serve one content-safe local Retrieval API fixture for web qualification."""

from __future__ import annotations

import argparse
import json
import os
import re
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


IDENTITY = re.compile(r"^[0-9a-f]{64}$")
MAXIMUM_REQUEST_BYTES = 262_144


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run a local web qualification fixture.")
    parser.add_argument("--port-file", required=True)
    return parser.parse_args()


class FixtureHandler(BaseHTTPRequestHandler):
    """Expose only the qualified readiness and chat fixtures."""

    protocol_version = "HTTP/1.1"
    server_version = ""
    sys_version = ""

    def log_message(self, _format: str, *_arguments: Any) -> None:
        return

    def _send(self, status: HTTPStatus, value: dict[str, Any]) -> None:
        body = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
        self.send_response_only(status.value)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)
        self.close_connection = True

    def do_GET(self) -> None:
        if self.path == "/ready":
            self._send(
                HTTPStatus.OK,
                {"schema": "ishikawa.health.v1", "status": "ready"},
            )
            return
        self._send(
            HTTPStatus.NOT_FOUND,
            {
                "error": {
                    "code": "HTTP_PATH_NOT_FOUND",
                    "message": "The requested path does not exist.",
                },
                "request_id": "9" * 64,
                "schema": "ishikawa.transport-error.v1",
            },
        )

    def do_POST(self) -> None:
        if self.path != "/v1/chat" or self.headers.get("Content-Type") != "application/json":
            self._send(
                HTTPStatus.BAD_REQUEST,
                {
                    "error": {
                        "code": "HTTP_REQUEST_INVALID",
                        "message": "The request body is invalid.",
                    },
                    "request_id": "8" * 64,
                    "schema": "ishikawa.transport-error.v1",
                },
            )
            return
        length_text = self.headers.get("Content-Length", "")
        if not length_text.isdigit() or not 1 <= int(length_text) <= MAXIMUM_REQUEST_BYTES:
            self._send(HTTPStatus.BAD_REQUEST, self._transport_error())
            return
        try:
            request = json.loads(self.rfile.read(int(length_text)).decode("utf-8"))
            required = {
                "conversation_id",
                "filters",
                "history",
                "message",
                "schema",
                "source_references",
                "turn_id",
            }
            if (
                not isinstance(request, dict)
                or set(request) != required
                or request["schema"] != "ishikawa.chat-request.v1"
                or IDENTITY.fullmatch(request["conversation_id"]) is None
                or IDENTITY.fullmatch(request["turn_id"]) is None
            ):
                raise ValueError("request invalid")
        except (UnicodeError, json.JSONDecodeError, ValueError, TypeError):
            self._send(HTTPStatus.BAD_REQUEST, self._transport_error())
            return
        claim = "Reports are submitted promptly."
        self._send(
            HTTPStatus.OK,
            {
                "answer": claim,
                "claims": [{"citation_ids": ["f" * 64], "text": claim}],
                "clarification": None,
                "conversation_id": request["conversation_id"],
                "error": None,
                "request_id": "1" * 64,
                "schema": "ishikawa.chat-response.v1",
                "sources": [
                    {
                        "display_name": "Incident Reporting Procedure",
                        "document_class": "policy_sop",
                        "excerpts": [
                            {
                                "anchor": {"kind": "step", "label": "Step 2"},
                                "citation_id": "f" * 64,
                                "excerpt": claim,
                                "page_end": 2,
                                "page_start": 2,
                                "structural_path": ["Incident Reporting", "Submission"],
                            }
                        ],
                        "source_id": "e" * 64,
                        "source_label": "Source 1",
                    }
                ],
                "status": "answered",
                "turn_id": request["turn_id"],
            },
        )

    @staticmethod
    def _transport_error() -> dict[str, Any]:
        return {
            "error": {
                "code": "HTTP_REQUEST_INVALID",
                "message": "The request body is invalid.",
            },
            "request_id": "8" * 64,
            "schema": "ishikawa.transport-error.v1",
        }


def main() -> int:
    arguments = parse_arguments()
    port_file = Path(arguments.port_file)
    if not port_file.is_absolute() or port_file.exists() or not port_file.parent.is_dir():
        raise ValueError("port_file_unsafe")
    server = ThreadingHTTPServer(("127.0.0.1", 0), FixtureHandler)
    try:
        with port_file.open("x", encoding="utf-8") as destination:
            destination.write(f"{server.server_port}\n")
        os.chmod(port_file, 0o600)
        server.serve_forever(poll_interval=0.1)
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
