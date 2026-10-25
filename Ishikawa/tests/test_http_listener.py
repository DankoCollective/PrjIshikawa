from __future__ import annotations

import copy
import http.client
import json
import socket
import threading
import unittest
from contextlib import contextmanager
from pathlib import Path

from ishikawa.api_contract import (
    ERRORS_BY_STATUS,
    ApiError,
    build_chat_response,
    validate_api_profile,
)
from ishikawa.deployment import (
    DeploymentContractError,
    RetrievalDeployment,
    validate_deployment_profile,
)
from ishikawa.http_listener import create_retrieval_http_server
from ishikawa.retrieval_service import RetrievalServiceExecution
from ishikawa.yaml_loader import load_restricted_yaml


def identity(character: str) -> str:
    return character * 64


def available_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


class HTTPListenerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[1]
        cls.api_policy = validate_api_profile(
            load_restricted_yaml(root / "config/templates/api_profile.yaml", label="API profile")
        )
        cls.raw_deployment = load_restricted_yaml(
            root / "config/templates/deployment.yaml", label="deployment profile"
        )
        cls.deployment = validate_deployment_profile(cls.raw_deployment)

    def request_body(self) -> bytes:
        return json.dumps(
            {
                "schema": "ishikawa.chat-request.v1",
                "conversation_id": identity("a"),
                "turn_id": identity("b"),
                "message": "How are incidents reported?",
                "history": [],
                "source_references": [],
                "filters": {"document_classes": [], "document_keys": []},
            },
            separators=(",", ":"),
        ).encode()

    def executor(self, calls):
        def execute(request, request_id):
            calls.append((request.message, request_id))
            code, message = ERRORS_BY_STATUS["insufficient-evidence"]
            response = build_chat_response(
                request=request,
                request_id=request_id,
                status="insufficient-evidence",
                error=ApiError(code, message),
                policy=self.api_policy,
            )
            return RetrievalServiceExecution(
                response,
                ("request-accepted", "sufficiency-blocked"),
                identity("c"),
            )

        return execute

    @contextmanager
    def server(
        self, executor, *, concurrency=2, events=None, readiness_probe=None,
        document_reader=None,
    ):
        deployment = RetrievalDeployment("127.0.0.1", available_port(), concurrency, 5)
        listener = create_retrieval_http_server(
            deployment,
            self.api_policy,
            executor,
            request_identity_factory=lambda: identity("1"),
            event_sink=(events.append if events is not None else None),
            readiness_probe=readiness_probe,
            document_reader=document_reader,
        )
        thread = threading.Thread(target=listener.serve_forever, daemon=True)
        thread.start()
        try:
            yield listener.server_address[1]
        finally:
            listener.shutdown()
            listener.server_close()
            thread.join(timeout=5)
            self.assertFalse(thread.is_alive())

    def exchange(self, port, method="POST", path="/v1/chat", body=None, headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
        connection.request(method, path, body=body, headers=headers or {})
        response = connection.getresponse()
        content = response.read()
        result = response.status, dict(response.getheaders()), content
        connection.close()
        return result

    def test_deployment_template_freezes_loopback_defaults(self):
        self.assertEqual(self.deployment.node_network_mode, "host")
        self.assertEqual(self.deployment.web.port, 3000)
        self.assertEqual(self.deployment.retrieval.bind_host, "127.0.0.1")
        self.assertEqual(self.deployment.retrieval.port, 1384)
        self.assertEqual(self.deployment.retrieval.maximum_concurrent_requests, 8)
        self.assertEqual(self.deployment.postgresql.port, 5432)
        self.assertEqual(len(self.deployment.digest), 64)

    def test_deployment_rejects_nonloopback_and_mismatched_url(self):
        raw = copy.deepcopy(self.raw_deployment)
        raw["retrieval"]["bind_host"] = "0.0.0.0"
        with self.assertRaisesRegex(DeploymentContractError, "loopback"):
            validate_deployment_profile(raw)
        raw = copy.deepcopy(self.raw_deployment)
        raw["web"]["retrieval_base_url"] = "http://127.0.0.1:9999"
        with self.assertRaisesRegex(DeploymentContractError, "does not match"):
            validate_deployment_profile(raw)

    def test_valid_post_returns_canonical_application_envelope(self):
        calls = []
        events = []
        with self.server(self.executor(calls), events=events) as port:
            status, headers, body = self.exchange(
                port,
                body=self.request_body(),
                headers={"Content-Type": "application/json"},
            )
        decoded = json.loads(body)
        self.assertEqual(status, 200)
        self.assertEqual(headers["Content-Type"], "application/json")
        self.assertEqual(headers["Cache-Control"], "no-store")
        self.assertEqual(headers["X-Content-Type-Options"], "nosniff")
        self.assertNotIn("Server", headers)
        self.assertEqual(decoded["schema"], "ishikawa.chat-response.v5")
        self.assertIsNone(decoded["diagnostics"])
        self.assertEqual(decoded["status"], "insufficient-evidence")
        self.assertEqual(decoded["request_id"], identity("1"))
        self.assertEqual(calls, [("How are incidents reported?", identity("1"))])
        self.assertEqual(events[0].outcome, "application_insufficient-evidence")

    def test_document_view_post_uses_separate_read_only_reader(self):
        calls = []

        def reader(request):
            calls.append(request)
            return json.dumps(
                {
                    "complete": True,
                    "next_section_offset": None,
                    "schema": "ishikawa.document-view-response.v2",
                    "sections": [],
                    "source": {
                        "display_name": "Document",
                        "document_class": "policy_sop",
                        "document_identifier": None,
                        "document_key": "policy.document",
                        "page_count": 1,
                        "source_id": identity("e"),
                    },
                    "total_sections": 1,
                },
                separators=(",", ":"),
            ).encode()

        body = json.dumps(
            {
                "schema": "ishikawa.document-view-request.v1",
                "section_limit": 4,
                "section_offset": 0,
                "source_id": identity("e"),
            },
            separators=(",", ":"),
        ).encode()
        with self.server(self.executor([]), document_reader=reader) as port:
            status, _, response = self.exchange(
                port,
                path="/v1/document",
                body=body,
                headers={"Content-Type": "application/json"},
            )
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(response)["schema"], "ishikawa.document-view-response.v2")
        self.assertEqual(calls[0].source_id, identity("e"))

    def test_wrong_method_and_path_are_fixed_transport_errors(self):
        calls = []
        with self.server(self.executor(calls)) as port:
            method_status, method_headers, method_body = self.exchange(port, method="GET")
            path_status, _, path_body = self.exchange(
                port,
                path="/v1/other",
                body=self.request_body(),
                headers={"Content-Type": "application/json"},
            )
        self.assertEqual(method_status, 405)
        self.assertEqual(method_headers["Allow"], "POST")
        self.assertEqual(json.loads(method_body)["error"]["code"], "HTTP_METHOD_NOT_ALLOWED")
        self.assertEqual(path_status, 404)
        self.assertEqual(json.loads(path_body)["error"]["code"], "HTTP_PATH_NOT_FOUND")
        self.assertEqual(calls, [])

    def test_health_routes_are_content_free_and_readiness_fails_closed(self):
        calls = []
        events = []
        with self.server(self.executor(calls), events=events) as port:
            live_status, _, live_body = self.exchange(port, method="GET", path="/live")
            ready_status, _, ready_body = self.exchange(port, method="GET", path="/ready")
            missing_status, _, missing_body = self.exchange(
                port, method="GET", path="/missing"
            )
        self.assertEqual(live_status, 200)
        self.assertEqual(
            json.loads(live_body),
            {"schema": "ishikawa.health.v1", "status": "live"},
        )
        self.assertEqual(ready_status, 503)
        self.assertEqual(
            json.loads(ready_body),
            {"schema": "ishikawa.health.v1", "status": "not-ready"},
        )
        self.assertEqual(missing_status, 404)
        self.assertEqual(json.loads(missing_body)["error"]["code"], "HTTP_PATH_NOT_FOUND")
        self.assertEqual(
            [event.outcome for event in events],
            ["health_live", "health_not_ready", "http_path_not_found"],
        )
        self.assertEqual(calls, [])

    def test_readiness_requires_exact_true_and_hides_probe_failures(self):
        calls = []
        probe_calls = []

        def ready():
            probe_calls.append("ready")
            return True

        with self.server(self.executor(calls), readiness_probe=ready) as port:
            ready_status, _, ready_body = self.exchange(port, method="GET", path="/ready")
        self.assertEqual(ready_status, 200)
        self.assertEqual(json.loads(ready_body)["status"], "ready")
        self.assertEqual(probe_calls, ["ready"])

        def fail():
            raise RuntimeError("private dependency detail")

        with self.server(self.executor(calls), readiness_probe=fail) as port:
            failed_status, _, failed_body = self.exchange(port, method="GET", path="/ready")
        self.assertEqual(failed_status, 503)
        self.assertEqual(json.loads(failed_body)["status"], "not-ready")
        self.assertNotIn("private dependency detail", failed_body.decode())
        self.assertEqual(calls, [])

    def test_dependency_route_exposes_only_gemma_and_nomic_states(self):
        class Inspection:
            components = (
                ("configuration", True),
                ("storage", True),
                ("postgresql", True),
                ("gemma", True),
                ("nomic", False),
            )

        class Probe:
            def __call__(self):
                return False

            def inspect_dependencies(self):
                return Inspection.components[-2:]

        with self.server(self.executor([]), readiness_probe=Probe()) as port:
            status, _, body = self.exchange(port, method="GET", path="/dependencies")
        self.assertEqual(status, 200)
        self.assertEqual(
            json.loads(body),
            {
                "gemma": "available",
                "nomic": "unavailable",
                "schema": "ishikawa.dependency-health.v1",
            },
        )

    def test_media_type_and_malformed_body_fail_before_execution(self):
        calls = []
        with self.server(self.executor(calls)) as port:
            media_status, _, media_body = self.exchange(
                port, body=self.request_body(), headers={"Content-Type": "text/plain"}
            )
            body_status, _, invalid_body = self.exchange(
                port, body=b"{", headers={"Content-Type": "application/json"}
            )
        self.assertEqual(media_status, 415)
        self.assertEqual(json.loads(media_body)["error"]["code"], "HTTP_MEDIA_TYPE_UNSUPPORTED")
        self.assertEqual(body_status, 400)
        self.assertEqual(json.loads(invalid_body)["error"]["code"], "HTTP_REQUEST_INVALID")
        self.assertEqual(calls, [])

    def test_oversized_declared_body_is_rejected_without_reading_it(self):
        calls = []
        with self.server(self.executor(calls)) as port:
            connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            connection.putrequest("POST", "/v1/chat")
            connection.putheader("Content-Type", "application/json")
            connection.putheader("Content-Length", str(self.api_policy.maximum_request_bytes + 1))
            connection.endheaders()
            response = connection.getresponse()
            body = response.read()
            connection.close()
        self.assertEqual(response.status, 413)
        self.assertEqual(json.loads(body)["error"]["code"], "HTTP_REQUEST_TOO_LARGE")
        self.assertEqual(calls, [])

    def test_unexpected_executor_failure_is_not_exposed(self):
        def fail(_request, _request_id):
            raise RuntimeError("private failure detail")

        with self.server(fail) as port:
            status, _, body = self.exchange(
                port,
                body=self.request_body(),
                headers={"Content-Type": "application/json"},
            )
        encoded = body.decode()
        self.assertEqual(status, 500)
        self.assertEqual(json.loads(body)["error"]["code"], "HTTP_INTERNAL_ERROR")
        self.assertNotIn("private failure detail", encoded)

    def test_concurrency_limit_fails_closed_without_running_second_request(self):
        started = threading.Event()
        release = threading.Event()
        calls = []
        first_result = []

        def slow(request, request_id):
            calls.append(request_id)
            started.set()
            release.wait(timeout=5)
            return self.executor([])(request, request_id)

        with self.server(slow, concurrency=1) as port:
            first = threading.Thread(
                target=lambda: first_result.append(
                    self.exchange(
                        port,
                        body=self.request_body(),
                        headers={"Content-Type": "application/json"},
                    )
                )
            )
            first.start()
            self.assertTrue(started.wait(timeout=5))
            second_status, _, second_body = self.exchange(
                port,
                body=self.request_body(),
                headers={"Content-Type": "application/json"},
            )
            release.set()
            first.join(timeout=5)
            self.assertFalse(first.is_alive())
        self.assertEqual(second_status, 503)
        self.assertEqual(json.loads(second_body)["error"]["code"], "HTTP_SERVICE_BUSY")
        self.assertEqual(len(calls), 1)
        self.assertEqual(first_result[0][0], 200)


if __name__ == "__main__":
    unittest.main()
