#!/usr/bin/env python3
"""Loopback-only synthetic grounded-generation capture proxy for Script 201.

The proxy forwards supported Gemma requests without changing their bodies. It
retains only grounded-answer exchanges, identified by Ishikawa's strict JSON
schema name. Authorization headers are forwarded in memory and never written.
"""

from __future__ import annotations

import argparse
import hashlib
import http.client
import json
import os
import re
import signal
import tempfile
import threading
import time
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Mapping, NoReturn
from urllib.parse import urlsplit

from ishikawa.generation import GenerationRequest
from ishikawa.generation_transport import (
    GenerationHTTPResponse,
    GenerationResponseError,
    validate_generation_response,
)


_ALLOWED_PATHS = frozenset({"/health", "/tokenize", "/v1/chat/completions", "/v1/models"})
_CAPTURE_SCHEMA_NAME = "ishikawa_grounded_answer"
_CITATION_ALIAS = re.compile(r"^C[1-9][0-9]*$")
_MAX_REQUEST_BYTES = 16 * 1024 * 1024
_MAX_RESPONSE_BYTES = 16 * 1024 * 1024


class CaptureError(ValueError):
    """Stable qualification-capture failure."""


def fail(reason: str) -> NoReturn:
    raise CaptureError(reason)


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, separators=(",", ":"), sort_keys=True
    ).encode("utf-8")


def exact_mapping(value: Any, fields: frozenset[str], reason: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping) or set(value) != fields:
        fail(reason)
    return value


def decode_json(value: bytes, reason: str) -> Any:
    try:
        return json.loads(value.decode("utf-8", errors="strict"))
    except (UnicodeError, json.JSONDecodeError) as error:
        raise CaptureError(reason) from error


def grounded_request(value: bytes) -> tuple[dict[str, Any], tuple[str, ...], tuple[tuple[str, ...], ...]] | None:
    body = decode_json(value, "request_json_invalid")
    if not isinstance(body, dict):
        fail("request_schema_invalid")
    response_format = body.get("response_format")
    if response_format is None:
        return None
    if not isinstance(response_format, Mapping):
        fail("response_format_invalid")
    json_schema = response_format.get("json_schema")
    if not isinstance(json_schema, Mapping) or json_schema.get("name") != _CAPTURE_SCHEMA_NAME:
        return None
    messages = body.get("messages")
    if not isinstance(messages, list) or len(messages) != 2:
        fail("generation_messages_invalid")
    user_message = messages[1]
    if (
        not isinstance(user_message, Mapping)
        or user_message.get("role") != "user"
        or not isinstance(user_message.get("content"), str)
    ):
        fail("generation_user_message_invalid")
    payload = decode_json(
        user_message["content"].encode("utf-8"), "generation_payload_json_invalid"
    )
    if not isinstance(payload, Mapping):
        fail("generation_payload_invalid")
    allowed = payload.get("allowed_citation_ids")
    groups = payload.get("required_citation_groups")
    if (
        not isinstance(allowed, list)
        or not allowed
        or len(set(allowed)) != len(allowed)
        or any(
            not isinstance(item, str) or _CITATION_ALIAS.fullmatch(item) is None
            for item in allowed
        )
        or not isinstance(groups, list)
    ):
        fail("generation_citation_contract_invalid")
    normalized_groups: list[tuple[str, ...]] = []
    for raw_group in groups:
        group = exact_mapping(
            raw_group,
            frozenset({"citation_ids", "reason"}),
            "generation_required_group_invalid",
        )
        citation_ids = group["citation_ids"]
        if (
            not isinstance(citation_ids, list)
            or not citation_ids
            or len(set(citation_ids)) != len(citation_ids)
            or any(item not in allowed for item in citation_ids)
            or not isinstance(group["reason"], str)
            or not group["reason"]
        ):
            fail("generation_required_group_invalid")
        normalized_groups.append(tuple(citation_ids))
    return body, tuple(allowed), tuple(normalized_groups)


def analyze(
    request_body: bytes,
    *,
    response_status: int,
    response_content_type: str,
    response_body: bytes,
) -> dict[str, Any]:
    parsed = grounded_request(request_body)
    if parsed is None:
        fail("grounded_request_required")
    body, allowed_aliases, alias_groups = parsed
    citation_aliases = tuple(
        (alias, hashlib.sha256(f"capture:{alias}".encode("utf-8")).hexdigest())
        for alias in allowed_aliases
    )
    citation_by_alias = dict(citation_aliases)
    allowed = tuple(citation_by_alias[alias] for alias in allowed_aliases)
    groups = tuple(
        tuple(citation_by_alias[alias] for alias in group)
        for group in alias_groups
    )
    request = GenerationRequest(
        body,
        "0" * 64,
        "0" * 64,
        allowed,
        citation_aliases,
        groups,
    )
    try:
        answer = validate_generation_response(
            GenerationHTTPResponse(
                response_status,
                response_content_type,
                response_body,
            ),
            request,
        )
    except GenerationResponseError as error:
        return {
            "completion_tokens": None,
            "finish_reason": None,
            "prompt_tokens": None,
            "reason": error.reason_code,
            "segment_count": None,
            "total_tokens": None,
            "validator": "blocked",
        }
    return {
        "completion_tokens": answer.completion_tokens,
        "finish_reason": answer.finish_reason,
        "prompt_tokens": answer.prompt_tokens,
        "reason": None,
        "segment_count": len(answer.segments),
        "total_tokens": answer.total_tokens,
        "validator": "pass",
    }


def write_exclusive(path: Path, value: bytes) -> None:
    if path.exists() or path.is_symlink() or not path.parent.is_dir() or path.parent.is_symlink():
        fail("capture_output_path_invalid")
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(value)


@dataclass(frozen=True, slots=True)
class Upstream:
    host: str
    port: int


class CaptureServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, handler, *, upstream: Upstream, capture_root: Path):
        super().__init__(address, handler)
        self.upstream = upstream
        self.capture_root = capture_root
        self.capture_lock = threading.Lock()
        self.capture_count = 0
        self.capture_failed = False

    def retain(
        self,
        request_body: bytes,
        *,
        response_status: int,
        response_content_type: str,
        response_body: bytes,
        elapsed_milliseconds: int,
    ) -> None:
        analysis = analyze(
            request_body,
            response_status=response_status,
            response_content_type=response_content_type,
            response_body=response_body,
        )
        request_sha256 = hashlib.sha256(request_body).hexdigest()
        response_sha256 = hashlib.sha256(response_body).hexdigest()
        with self.capture_lock:
            self.capture_count += 1
            attempt = self.capture_count
            attempt_root = self.capture_root / f"attempt-{attempt:02d}"
            attempt_root.mkdir(mode=0o700)
            write_exclusive(attempt_root / "request-body.json", request_body)
            write_exclusive(attempt_root / "response-body.json", response_body)
            metadata = {
                **analysis,
                "allowed_citation_count": len(grounded_request(request_body)[1]),
                "attempt": attempt,
                "elapsed_milliseconds": elapsed_milliseconds,
                "http_status": response_status,
                "request_bytes": len(request_body),
                "request_sha256": request_sha256,
                "response_bytes": len(response_body),
                "response_content_type": response_content_type,
                "response_sha256": response_sha256,
                "schema_version": 1,
                "synthetic_content_only": True,
            }
            write_exclusive(attempt_root / "analysis.json", canonical_bytes(metadata) + b"\n")
            summary = (
                f"attempt={attempt};elapsed_milliseconds={elapsed_milliseconds};"
                f"http_status={response_status};validator={analysis['validator']};"
                f"reason={analysis['reason'] or 'none'};"
                f"allowed_citations={metadata['allowed_citation_count']};"
                f"request_sha256={request_sha256};response_sha256={response_sha256}\n"
            ).encode("utf-8")
            write_exclusive(attempt_root / "summary.txt", summary)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server: CaptureServer

    def log_message(self, _format: str, *_args: Any) -> None:
        return

    def do_GET(self) -> None:  # noqa: N802
        self._forward()

    def do_POST(self) -> None:  # noqa: N802
        self._forward()

    def _forward(self) -> None:
        if self.path not in _ALLOWED_PATHS or self.command not in {"GET", "POST"}:
            self.send_error(404)
            return
        try:
            raw_length = self.headers.get("Content-Length", "0")
            length = int(raw_length)
        except ValueError:
            self.send_error(400)
            return
        if not 0 <= length <= _MAX_REQUEST_BYTES:
            self.send_error(413)
            return
        request_body = self.rfile.read(length) if length else b""
        if len(request_body) != length:
            self.send_error(400)
            return
        headers = {
            name: value
            for name in ("Accept", "Authorization", "Content-Type")
            if (value := self.headers.get(name)) is not None
        }
        connection = http.client.HTTPConnection(
            self.server.upstream.host,
            self.server.upstream.port,
            timeout=330,
        )
        started = time.monotonic_ns()
        try:
            connection.request(self.command, self.path, body=request_body or None, headers=headers)
            response = connection.getresponse()
            response_body = response.read(_MAX_RESPONSE_BYTES + 1)
            response_status = response.status
            response_content_type = response.getheader("Content-Type", "")
            if len(response_body) > _MAX_RESPONSE_BYTES:
                raise CaptureError("upstream_response_too_large")
        except (OSError, TimeoutError, http.client.HTTPException, CaptureError):
            error_body = b'{"error":"capture_proxy_upstream_unavailable"}'
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(error_body)))
            self.end_headers()
            self.wfile.write(error_body)
            return
        finally:
            connection.close()
        elapsed = max(1, (time.monotonic_ns() - started) // 1_000_000)
        try:
            if request_body and grounded_request(request_body) is not None:
                self.server.retain(
                    request_body,
                    response_status=response_status,
                    response_content_type=response_content_type,
                    response_body=response_body,
                    elapsed_milliseconds=elapsed,
                )
        except Exception:
            self.server.capture_failed = True
        self.send_response(response_status)
        self.send_header("Content-Type", response_content_type or "application/octet-stream")
        self.send_header("Content-Length", str(len(response_body)))
        self.end_headers()
        self.wfile.write(response_body)


def parse_upstream(value: str) -> Upstream:
    parsed = urlsplit(value)
    if (
        parsed.scheme != "http"
        or parsed.hostname != "127.0.0.1"
        or parsed.port not in {8000, 18000}
        or parsed.path not in {"", "/"}
        or parsed.query
        or parsed.fragment
        or parsed.username is not None
        or parsed.password is not None
    ):
        fail("upstream_boundary_invalid")
    return Upstream(parsed.hostname, parsed.port)


def self_test() -> int:
    citation = "C1"
    payload = {
        "allowed_citation_ids": [citation],
        "conversation": [],
        "conversation_id": "b" * 64,
        "evidence_groups": [],
        "question": "Synthetic question?",
        "required_citation_groups": [],
        "schema": "ishikawa.grounded-generation-input.v3",
        "turn_id": "c" * 64,
    }
    body = {
        "chat_template_kwargs": {"enable_thinking": False},
        "max_tokens": 2048,
        "messages": [
            {"content": "Synthetic system instruction.", "role": "system"},
            {"content": canonical_bytes(payload).decode("utf-8"), "role": "user"},
        ],
        "model": "google/gemma-4-26B-A4B-it",
        "response_format": {
            "type": "json_schema",
            "json_schema": {"name": _CAPTURE_SCHEMA_NAME, "strict": True, "schema": {}},
        },
        "stream": False,
        "temperature": 1.0,
        "top_k": 64,
        "top_p": 0.95,
    }
    content = canonical_bytes(
        {"segments": [{"citation_ids": [citation], "text": "Synthetic answer."}]}
    ).decode("utf-8")
    response = canonical_bytes(
        {
            "choices": [
                {
                    "finish_reason": "stop",
                    "index": 0,
                    "message": {"content": content, "role": "assistant"},
                }
            ],
            "created": 1,
            "id": "chatcmpl-synthetic",
            "model": body["model"],
            "object": "chat.completion",
            "usage": {"completion_tokens": 8, "prompt_tokens": 32, "total_tokens": 40},
        }
    )
    result = analyze(
        canonical_bytes(body),
        response_status=200,
        response_content_type="application/json",
        response_body=response,
    )
    assert result["validator"] == "pass"
    invalid = json.loads(response)
    invalid["choices"][0]["finish_reason"] = "length"
    result = analyze(
        canonical_bytes(body),
        response_status=200,
        response_content_type="application/json",
        response_body=canonical_bytes(invalid),
    )
    assert result == {
        "completion_tokens": None,
        "finish_reason": None,
        "prompt_tokens": None,
        "reason": "MODEL_COMPLETION_INCOMPLETE",
        "segment_count": None,
        "total_tokens": None,
        "validator": "blocked",
    }
    assert grounded_request(canonical_bytes({"messages": []})) is None
    assert parse_upstream("http://127.0.0.1:18000") == Upstream("127.0.0.1", 18000)

    class FakeUpstreamHandler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"
        authorization = ""

        def log_message(self, _format: str, *_args: Any) -> None:
            return

        def do_POST(self) -> None:  # noqa: N802
            length = int(self.headers.get("Content-Length", "0"))
            self.rfile.read(length)
            type(self).authorization = self.headers.get("Authorization", "")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(response)))
            self.end_headers()
            self.wfile.write(response)

    with tempfile.TemporaryDirectory(prefix="ishikawa-capture-self-test.") as temporary:
        capture_root = Path(temporary) / "captures"
        capture_root.mkdir(mode=0o700)
        upstream_server = ThreadingHTTPServer(
            ("127.0.0.1", 0), FakeUpstreamHandler
        )
        upstream_thread = threading.Thread(
            target=upstream_server.serve_forever, daemon=True
        )
        upstream_thread.start()
        proxy_server = CaptureServer(
            ("127.0.0.1", 0),
            Handler,
            upstream=Upstream("127.0.0.1", upstream_server.server_port),
            capture_root=capture_root,
        )
        proxy_thread = threading.Thread(target=proxy_server.serve_forever, daemon=True)
        proxy_thread.start()
        authorization = "Bearer synthetic-secret-never-retain"
        try:
            connection = http.client.HTTPConnection(
                "127.0.0.1", proxy_server.server_port, timeout=5
            )
            connection.request(
                "POST",
                "/tokenize",
                body=canonical_bytes({"messages": []}),
                headers={
                    "Authorization": authorization,
                    "Content-Type": "application/json",
                },
            )
            forwarded = connection.getresponse()
            assert forwarded.status == 200
            forwarded.read()
            connection.close()
            assert not list(capture_root.iterdir())

            request_bytes = canonical_bytes(body)
            connection = http.client.HTTPConnection(
                "127.0.0.1", proxy_server.server_port, timeout=5
            )
            connection.request(
                "POST",
                "/v1/chat/completions",
                body=request_bytes,
                headers={
                    "Authorization": authorization,
                    "Content-Type": "application/json",
                },
            )
            forwarded = connection.getresponse()
            assert forwarded.status == 200
            assert forwarded.read() == response
            connection.close()

            attempt = capture_root / "attempt-01"
            assert (attempt / "request-body.json").read_bytes() == request_bytes
            assert (attempt / "response-body.json").read_bytes() == response
            retained_analysis = decode_json(
                (attempt / "analysis.json").read_bytes(), "self_test_analysis_invalid"
            )
            assert retained_analysis["validator"] == "pass"
            assert retained_analysis["reason"] is None
            retained = b"".join(
                path.read_bytes() for path in sorted(attempt.iterdir())
            )
            assert authorization.encode("utf-8") not in retained
            assert b"synthetic-secret-never-retain" not in retained
            assert FakeUpstreamHandler.authorization == authorization
            assert proxy_server.capture_count == 1
            assert proxy_server.capture_failed is False
        finally:
            proxy_server.shutdown()
            proxy_server.server_close()
            upstream_server.shutdown()
            upstream_server.server_close()
            proxy_thread.join(timeout=5)
            upstream_thread.join(timeout=5)
    print("v1_3_generation_capture_proxy_self_test=pass")
    return 0


def serve(arguments: argparse.Namespace) -> int:
    capture_root = arguments.capture_root
    if (
        not capture_root.is_absolute()
        or not capture_root.is_dir()
        or capture_root.is_symlink()
        or any(capture_root.iterdir())
    ):
        fail("capture_root_invalid")
    upstream = parse_upstream(arguments.upstream_base_url)
    server = CaptureServer(
        ("127.0.0.1", arguments.listen_port),
        Handler,
        upstream=upstream,
        capture_root=capture_root,
    )

    def stop(_number, _frame) -> None:
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)
    print(
        f"v1_3_generation_capture_proxy=ready;port={arguments.listen_port}",
        flush=True,
    )
    try:
        server.serve_forever(poll_interval=0.2)
    finally:
        server.server_close()
    if server.capture_failed:
        print("v1_3_generation_capture_proxy=blocked;reason=capture_failed", flush=True)
        return 1
    print(
        f"v1_3_generation_capture_proxy=stopped;captures={server.capture_count}",
        flush=True,
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--serve", action="store_true")
    parser.add_argument("--listen-port", type=int, default=18002)
    parser.add_argument("--upstream-base-url")
    parser.add_argument("--capture-root", type=Path)
    arguments = parser.parse_args()
    if arguments.self_test == arguments.serve:
        fail("mode_invalid")
    if arguments.self_test:
        return self_test()
    if (
        arguments.upstream_base_url is None
        or arguments.capture_root is None
        or not 1024 <= arguments.listen_port <= 65535
    ):
        fail("serve_arguments_invalid")
    return serve(arguments)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except CaptureError as error:
        print(f"v1_3_generation_capture_proxy=blocked;reason={error}")
        raise SystemExit(1)
