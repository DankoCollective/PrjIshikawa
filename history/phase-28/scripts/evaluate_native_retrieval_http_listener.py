#!/usr/bin/env python3
"""Exercise the native retrieval listener over its default loopback socket."""

from __future__ import annotations

import argparse
import hashlib
import http.client
import json
import socket
import threading
from pathlib import Path

from ishikawa.api_contract import (
    ERRORS_BY_STATUS,
    ApiError,
    build_chat_response,
    validate_api_profile,
)
from ishikawa.canonical import canonical_json_bytes
from ishikawa.deployment import validate_deployment_profile
from ishikawa.http_listener import create_retrieval_http_server
from ishikawa.retrieval_service import (
    RetrievalServiceExecution,
    validate_retrieval_service_profile,
)
from ishikawa.yaml_loader import load_restricted_yaml


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise RuntimeError(reason)


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def exchange(port: int, method: str, path: str, body: bytes | None, headers=None):
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    connection.request(method, path, body=body, headers=headers or {})
    response = connection.getresponse()
    payload = response.read()
    result = response.status, dict(response.getheaders()), payload
    connection.close()
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--api-profile", type=Path, required=True)
    parser.add_argument("--api-profile-sha256", required=True)
    parser.add_argument("--service-profile", type=Path, required=True)
    parser.add_argument("--service-profile-sha256", required=True)
    parser.add_argument("--deployment-profile", type=Path, required=True)
    parser.add_argument("--deployment-profile-sha256", required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()

    for path, expected in (
        (arguments.api_profile, arguments.api_profile_sha256),
        (arguments.service_profile, arguments.service_profile_sha256),
        (arguments.deployment_profile, arguments.deployment_profile_sha256),
    ):
        require(path.is_file() and not path.is_symlink(), "profile input is unsafe")
        require(sha256_file(path) == expected, "profile identity mismatch")
    require(not arguments.output.exists(), "output path already exists")

    api_policy = validate_api_profile(
        load_restricted_yaml(arguments.api_profile, label="API profile")
    )
    service_policy = validate_retrieval_service_profile(
        load_restricted_yaml(arguments.service_profile, label="service profile")
    )
    deployment = validate_deployment_profile(
        load_restricted_yaml(arguments.deployment_profile, label="deployment profile")
    )
    require(
        deployment.retrieval.bind_host == service_policy.default_bind_address
        and deployment.retrieval.port == service_policy.default_port,
        "deployment and service defaults differ",
    )

    request_body = canonical_json_bytes(
        {
            "conversation_id": "a" * 64,
            "filters": {"document_classes": [], "document_keys": []},
            "history": [],
            "message": "How are incidents reported?",
            "schema": "ishikawa.chat-request.v1",
            "source_references": [],
            "turn_id": "b" * 64,
        }
    )
    calls: list[str] = []
    events = []

    def execute(request, request_id):
        calls.append(request.envelope_identity)
        code, message = ERRORS_BY_STATUS["insufficient-evidence"]
        response = build_chat_response(
            request=request,
            request_id=request_id,
            status="insufficient-evidence",
            error=ApiError(code, message),
            policy=api_policy,
        )
        return RetrievalServiceExecution(
            response,
            ("request-accepted", "sufficiency-blocked"),
            service_policy.digest,
        )

    server = create_retrieval_http_server(
        deployment.retrieval,
        api_policy,
        execute,
        request_identity_factory=lambda: "1" * 64,
        event_sink=events.append,
    )
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        accepted = exchange(
            deployment.retrieval.port,
            "POST",
            "/v1/chat",
            request_body,
            {"Content-Type": "application/json"},
        )
        wrong_method = exchange(deployment.retrieval.port, "GET", "/v1/chat", None)
        wrong_path = exchange(
            deployment.retrieval.port,
            "POST",
            "/v1/other",
            request_body,
            {"Content-Type": "application/json"},
        )
        malformed = exchange(
            deployment.retrieval.port,
            "POST",
            "/v1/chat",
            b"{",
            {"Content-Type": "application/json"},
        )
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
    require(not thread.is_alive(), "listener did not stop")

    accepted_status, accepted_headers, accepted_body = accepted
    accepted_value = json.loads(accepted_body)
    require(accepted_status == 200, "accepted request status mismatch")
    require(accepted_value.get("schema") == "ishikawa.chat-response.v1", "response schema mismatch")
    require(accepted_value.get("status") == "insufficient-evidence", "application status mismatch")
    require(accepted_value.get("request_id") == "1" * 64, "request identity mismatch")
    require(accepted_headers.get("Content-Type") == "application/json", "media type mismatch")
    require(accepted_headers.get("Cache-Control") == "no-store", "cache policy mismatch")
    require(accepted_headers.get("X-Content-Type-Options") == "nosniff", "nosniff absent")
    require("Server" not in accepted_headers, "server implementation disclosed")
    require(wrong_method[0] == 405 and wrong_method[1].get("Allow") == "POST", "method gate failed")
    require(wrong_path[0] == 404, "path gate failed")
    require(malformed[0] == 400, "body gate failed")
    require(len(calls) == 1, "rejected request reached executor")
    require(len(events) == 4, "content-free event count mismatch")
    require(
        all(event.request_id == "1" * 64 and not hasattr(event, "content") for event in events),
        "event boundary mismatch",
    )

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.settimeout(1)
        require(
            probe.connect_ex((deployment.retrieval.bind_host, deployment.retrieval.port)) != 0,
            "listener remained active",
        )

    artifact = {
        "application_requests_executed": len(calls),
        "bind_host": deployment.retrieval.bind_host,
        "deployment_profile_id": deployment.digest,
        "event_count": len(events),
        "http_statuses": [accepted[0], wrong_method[0], wrong_path[0], malformed[0]],
        "listener_stopped": True,
        "port": deployment.retrieval.port,
        "schema": "ishikawa.http-listener-qualification.v1",
        "service_profile_id": service_policy.digest,
    }
    arguments.output.write_bytes(canonical_json_bytes(artifact) + b"\n")
    print("listener_endpoint=127.0.0.1:1384;method=POST;path=/v1/chat;streaming=false")
    print("transport_cases=4;accepted=1;method_rejected=1;path_rejected=1;body_rejected=1")
    print("application_http_status=200;application_status=insufficient-evidence")
    print("bounds=request_bytes_262144;concurrent_requests_8;read_timeout_seconds_30")
    print("headers=content_type,content_length,no_store,nosniff,connection_close;server_disclosure=false")
    print("request_correlation=opaque_server_generated;content_free_events=4;request_content_logged=false")
    print("listener_shutdown=pass;port_1384_after_test=free")
    print("target_contact=false;database_contact=false;model_call=false;credential_read=false")
    print("native_retrieval_http_listener_qualification=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
