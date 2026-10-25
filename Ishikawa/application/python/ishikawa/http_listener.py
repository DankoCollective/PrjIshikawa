"""Bounded standard-library HTTP listener for the Ishikawa Retrieval API."""

from __future__ import annotations

import ipaddress
import re
import secrets
import socket
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

from .api_contract import ApiContractError, ApiPolicy, decode_chat_request
from .canonical import canonical_json_bytes
from .deployment import RetrievalDeployment
from .document_view import (
    DocumentViewContractError,
    DocumentViewNotAvailable,
    decode_document_view_request,
)
from .retrieval_service import RetrievalOperationalTelemetry, RetrievalServiceExecution


CHAT_PATH = "/v1/chat"
LIVENESS_PATH = "/live"
READINESS_PATH = "/ready"
DEPENDENCIES_PATH = "/dependencies"
DOCUMENT_PATH = "/v1/document"
MEDIA_TYPE = "application/json"
MAXIMUM_RESPONSE_BYTES = 4 * 1024 * 1024
_IDENTITY = re.compile(r"^[0-9a-f]{64}$")


class HTTPListenerContractError(ValueError):
    """Raised when listener construction leaves the qualified boundary."""


@dataclass(frozen=True, slots=True)
class ListenerEvent:
    request_id: str
    outcome: str
    http_status: int
    duration_ms: int
    stage_trace: tuple[str, ...] = ()
    stage_durations_ms: tuple[tuple[str, int], ...] = ()
    retrieval_telemetry: RetrievalOperationalTelemetry | None = None


RequestExecutor = Callable[[Any, str], RetrievalServiceExecution]
RequestIdentityFactory = Callable[[], str]
EventSink = Callable[[ListenerEvent], None]
ReadinessProbe = Callable[[], bool]
DocumentReader = Callable[[Any], bytes]


def _transport_error(request_id: str, code: str, message: str) -> bytes:
    return canonical_json_bytes(
        {
            "error": {"code": code, "message": message},
            "request_id": request_id,
            "schema": "ishikawa.transport-error.v1",
        }
    )


def _health_response(status: str) -> bytes:
    """Return the intentionally content-free service health envelope."""

    return canonical_json_bytes(
        {
            "schema": "ishikawa.health.v1",
            "status": status,
        }
    )


def _dependency_response(gemma: bool, nomic: bool) -> bytes:
    """Return only the two model-service availability states needed by the UI."""

    return canonical_json_bytes(
        {
            "gemma": "available" if gemma else "unavailable",
            "nomic": "available" if nomic else "unavailable",
            "schema": "ishikawa.dependency-health.v1",
        }
    )


class RetrievalHTTPServer(ThreadingHTTPServer):
    """Loopback-only HTTP server with bounded active request execution."""

    daemon_threads = True
    block_on_close = True
    allow_reuse_address = False
    request_queue_size = 16

    def __init__(
        self,
        deployment: RetrievalDeployment,
        api_policy: ApiPolicy,
        executor: RequestExecutor,
        request_identity_factory: RequestIdentityFactory,
        event_sink: EventSink,
        readiness_probe: ReadinessProbe,
        document_reader: DocumentReader | None = None,
    ) -> None:
        if not isinstance(deployment, RetrievalDeployment):
            raise HTTPListenerContractError("retrieval deployment is invalid")
        if not isinstance(api_policy, ApiPolicy) or not callable(executor):
            raise HTTPListenerContractError("listener dependency is invalid")
        if (
            not callable(request_identity_factory)
            or not callable(event_sink)
            or not callable(readiness_probe)
            or (document_reader is not None and not callable(document_reader))
        ):
            raise HTTPListenerContractError("listener callback is invalid")
        self.deployment = deployment
        self.api_policy = api_policy
        self.executor = executor
        self.request_identity_factory = request_identity_factory
        self.event_sink = event_sink
        self.readiness_probe = readiness_probe
        self.document_reader = document_reader
        self.request_slots = threading.BoundedSemaphore(
            deployment.maximum_concurrent_requests
        )
        super().__init__((deployment.bind_host, deployment.port), RetrievalRequestHandler)


class RetrievalRequestHandler(BaseHTTPRequestHandler):
    """Exact nonstreaming HTTP/1.1 boundary with no default access logging."""

    protocol_version = "HTTP/1.1"
    server_version = ""
    sys_version = ""

    @property
    def retrieval_server(self) -> RetrievalHTTPServer:
        if not isinstance(self.server, RetrievalHTTPServer):
            raise HTTPListenerContractError("unexpected HTTP server")
        return self.server

    def setup(self) -> None:
        self._request_started_ns = time.monotonic_ns()
        super().setup()
        self.connection.settimeout(
            self.retrieval_server.deployment.request_read_timeout_seconds
        )

    def log_message(self, _format: str, *_arguments: Any) -> None:
        return

    def version_string(self) -> str:
        return ""

    def _request_identity(self) -> str:
        try:
            value = self.retrieval_server.request_identity_factory()
        except Exception:
            value = ""
        return value if isinstance(value, str) and _IDENTITY.fullmatch(value) else secrets.token_hex(32)

    def _record(
        self,
        request_id: str,
        outcome: str,
        status: int,
        stage_trace: tuple[str, ...] = (),
        stage_durations_ms: tuple[tuple[str, int], ...] = (),
        retrieval_telemetry: RetrievalOperationalTelemetry | None = None,
    ) -> None:
        try:
            elapsed_ns = max(0, time.monotonic_ns() - self._request_started_ns)
            duration_ms = min(86400000, elapsed_ns // 1000000)
            self.retrieval_server.event_sink(
                ListenerEvent(
                    request_id,
                    outcome,
                    status,
                    duration_ms,
                    stage_trace,
                    stage_durations_ms,
                    retrieval_telemetry,
                )
            )
        except Exception:
            pass

    def _send_bytes(
        self,
        status: HTTPStatus,
        body: bytes,
        *,
        request_id: str,
        outcome: str,
        extra_headers: tuple[tuple[str, str], ...] = (),
        include_body: bool = True,
        stage_trace: tuple[str, ...] = (),
        stage_durations_ms: tuple[tuple[str, int], ...] = (),
        retrieval_telemetry: RetrievalOperationalTelemetry | None = None,
    ) -> None:
        self.send_response_only(status.value)
        self.send_header("Content-Type", MEDIA_TYPE)
        self.send_header("Content-Length", str(len(body) if include_body else 0))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Connection", "close")
        for name, value in extra_headers:
            self.send_header(name, value)
        self.end_headers()
        if include_body:
            self.wfile.write(body)
        self.close_connection = True
        self._record(
            request_id,
            outcome,
            status.value,
            stage_trace,
            stage_durations_ms,
            retrieval_telemetry,
        )

    def _send_error_response(
        self,
        status: HTTPStatus,
        code: str,
        message: str,
        *,
        request_id: str | None = None,
        include_body: bool = True,
        extra_headers: tuple[tuple[str, str], ...] = (),
    ) -> None:
        identity = request_id or self._request_identity()
        self._send_bytes(
            status,
            _transport_error(identity, code, message),
            request_id=identity,
            outcome=code.lower(),
            extra_headers=extra_headers,
            include_body=include_body,
        )

    def send_error(
        self,
        code: int,
        message: str | None = None,
        explain: str | None = None,
    ) -> None:
        del message, explain
        try:
            status = HTTPStatus(code)
        except ValueError:
            status = HTTPStatus.INTERNAL_SERVER_ERROR
        self._send_error_response(
            status,
            "HTTP_REQUEST_REJECTED",
            "The HTTP request was rejected.",
            include_body=self.command != "HEAD",
        )

    def handle_expect_100(self) -> bool:
        self._send_error_response(
            HTTPStatus.EXPECTATION_FAILED,
            "HTTP_EXPECTATION_UNSUPPORTED",
            "HTTP expectations are not supported.",
        )
        return False

    def _method_not_allowed(self, *, include_body: bool = True) -> None:
        self._send_error_response(
            HTTPStatus.METHOD_NOT_ALLOWED,
            "HTTP_METHOD_NOT_ALLOWED",
            "Only POST is accepted.",
            include_body=include_body,
            extra_headers=(("Allow", "POST"),),
        )

    def do_GET(self) -> None:
        request_id = self._request_identity()
        try:
            peer = ipaddress.ip_address(self.client_address[0])
        except ValueError:
            peer = None
        if peer is None or not peer.is_loopback:
            self._send_error_response(
                HTTPStatus.FORBIDDEN,
                "HTTP_CLIENT_FORBIDDEN",
                "The client is not permitted.",
                request_id=request_id,
            )
            return
        if self.path == LIVENESS_PATH:
            self._send_bytes(
                HTTPStatus.OK,
                _health_response("live"),
                request_id=request_id,
                outcome="health_live",
            )
            return
        if self.path == READINESS_PATH:
            try:
                ready = self.retrieval_server.readiness_probe() is True
            except Exception:
                ready = False
            self._send_bytes(
                HTTPStatus.OK if ready else HTTPStatus.SERVICE_UNAVAILABLE,
                _health_response("ready" if ready else "not-ready"),
                request_id=request_id,
                outcome="health_ready" if ready else "health_not_ready",
            )
            return
        if self.path == DEPENDENCIES_PATH:
            gemma = False
            nomic = False
            try:
                states = dict(
                    self.retrieval_server.readiness_probe.inspect_dependencies()
                )
                gemma = states.get("gemma") is True
                nomic = states.get("nomic") is True
            except Exception:
                pass
            self._send_bytes(
                HTTPStatus.OK,
                _dependency_response(gemma, nomic),
                request_id=request_id,
                outcome="dependency_health",
            )
            return
        if self.path in {CHAT_PATH, DOCUMENT_PATH}:
            self._method_not_allowed()
            return
        self._send_error_response(
            HTTPStatus.NOT_FOUND,
            "HTTP_PATH_NOT_FOUND",
            "The requested path does not exist.",
            request_id=request_id,
        )

    do_PUT = _method_not_allowed
    do_PATCH = _method_not_allowed
    do_DELETE = _method_not_allowed
    do_OPTIONS = _method_not_allowed

    def do_HEAD(self) -> None:
        self._method_not_allowed(include_body=False)

    def do_POST(self) -> None:
        request_id = self._request_identity()
        try:
            peer = ipaddress.ip_address(self.client_address[0])
        except ValueError:
            peer = None
        if peer is None or not peer.is_loopback:
            self._send_error_response(
                HTTPStatus.FORBIDDEN,
                "HTTP_CLIENT_FORBIDDEN",
                "The client is not permitted.",
                request_id=request_id,
            )
            return
        if self.path not in {CHAT_PATH, DOCUMENT_PATH}:
            self._send_error_response(
                HTTPStatus.NOT_FOUND,
                "HTTP_PATH_NOT_FOUND",
                "The requested path does not exist.",
                request_id=request_id,
            )
            return
        if self.headers.get("Transfer-Encoding") is not None:
            self._send_error_response(
                HTTPStatus.BAD_REQUEST,
                "HTTP_TRANSFER_ENCODING_UNSUPPORTED",
                "Transfer encoding is not supported.",
                request_id=request_id,
            )
            return
        if self.headers.get("Expect") is not None:
            self._send_error_response(
                HTTPStatus.EXPECTATION_FAILED,
                "HTTP_EXPECTATION_UNSUPPORTED",
                "HTTP expectations are not supported.",
                request_id=request_id,
            )
            return
        content_types = self.headers.get_all("Content-Type", failobj=[])
        if content_types != [MEDIA_TYPE]:
            self._send_error_response(
                HTTPStatus.UNSUPPORTED_MEDIA_TYPE,
                "HTTP_MEDIA_TYPE_UNSUPPORTED",
                "Content-Type must be application/json.",
                request_id=request_id,
            )
            return
        content_lengths = self.headers.get_all("Content-Length", failobj=[])
        if len(content_lengths) != 1 or not content_lengths[0].isdigit():
            self._send_error_response(
                HTTPStatus.BAD_REQUEST,
                "HTTP_CONTENT_LENGTH_INVALID",
                "One valid Content-Length header is required.",
                request_id=request_id,
            )
            return
        content_length = int(content_lengths[0])
        if content_length < 1 or content_length > self.retrieval_server.api_policy.maximum_request_bytes:
            self._send_error_response(
                HTTPStatus.REQUEST_ENTITY_TOO_LARGE,
                "HTTP_REQUEST_TOO_LARGE",
                "The request body is outside the accepted size.",
                request_id=request_id,
            )
            return
        if not self.retrieval_server.request_slots.acquire(blocking=False):
            self._send_error_response(
                HTTPStatus.SERVICE_UNAVAILABLE,
                "HTTP_SERVICE_BUSY",
                "The service is temporarily busy.",
                request_id=request_id,
            )
            return
        try:
            try:
                body = self.rfile.read(content_length)
            except (OSError, socket.timeout):
                self._send_error_response(
                    HTTPStatus.REQUEST_TIMEOUT,
                    "HTTP_REQUEST_TIMEOUT",
                    "The request body was not received in time.",
                    request_id=request_id,
                )
                return
            if len(body) != content_length:
                self._send_error_response(
                    HTTPStatus.BAD_REQUEST,
                    "HTTP_REQUEST_INCOMPLETE",
                    "The request body was incomplete.",
                    request_id=request_id,
                )
                return
            if self.path == DOCUMENT_PATH:
                if self.retrieval_server.document_reader is None:
                    self._send_error_response(
                        HTTPStatus.SERVICE_UNAVAILABLE,
                        "DOCUMENT_VIEW_UNAVAILABLE",
                        "Document viewing is temporarily unavailable.",
                        request_id=request_id,
                    )
                    return
                try:
                    document_request = decode_document_view_request(body)
                    response = self.retrieval_server.document_reader(document_request)
                    if not isinstance(response, bytes) or not response:
                        raise HTTPListenerContractError(
                            "document reader response is invalid"
                        )
                    if len(response) > MAXIMUM_RESPONSE_BYTES:
                        raise HTTPListenerContractError(
                            "document response exceeds the HTTP boundary"
                        )
                except DocumentViewContractError:
                    self._send_error_response(
                        HTTPStatus.BAD_REQUEST,
                        "DOCUMENT_REQUEST_INVALID",
                        "The document request is invalid.",
                        request_id=request_id,
                    )
                    return
                except DocumentViewNotAvailable:
                    self._send_error_response(
                        HTTPStatus.NOT_FOUND,
                        "DOCUMENT_VERSION_NOT_ACTIVE",
                        "The exact active document version is unavailable.",
                        request_id=request_id,
                    )
                    return
                except Exception:
                    self._send_error_response(
                        HTTPStatus.SERVICE_UNAVAILABLE,
                        "DOCUMENT_VIEW_UNAVAILABLE",
                        "Document viewing is temporarily unavailable.",
                        request_id=request_id,
                    )
                    return
                self._send_bytes(
                    HTTPStatus.OK,
                    response,
                    request_id=request_id,
                    outcome="document_view",
                )
                return
            try:
                request = decode_chat_request(body, self.retrieval_server.api_policy)
            except ApiContractError:
                self._send_error_response(
                    HTTPStatus.BAD_REQUEST,
                    "HTTP_REQUEST_INVALID",
                    "The request body is invalid.",
                    request_id=request_id,
                )
                return
            try:
                execution = self.retrieval_server.executor(request, request_id)
                if not isinstance(execution, RetrievalServiceExecution):
                    raise HTTPListenerContractError("executor result is invalid")
                response = execution.response.canonical_bytes()
                if len(response) > MAXIMUM_RESPONSE_BYTES:
                    raise HTTPListenerContractError("response exceeds the HTTP boundary")
            except Exception:
                self._send_error_response(
                    HTTPStatus.INTERNAL_SERVER_ERROR,
                    "HTTP_INTERNAL_ERROR",
                    "The request could not be completed.",
                    request_id=request_id,
                )
                return
            self._send_bytes(
                HTTPStatus.OK,
                response,
                request_id=request_id,
                outcome=f"application_{execution.response.body['status']}",
                stage_trace=execution.stage_trace,
                stage_durations_ms=execution.stage_durations_ms,
                retrieval_telemetry=execution.retrieval_telemetry,
            )
        finally:
            self.retrieval_server.request_slots.release()


def create_retrieval_http_server(
    deployment: RetrievalDeployment,
    api_policy: ApiPolicy,
    executor: RequestExecutor,
    *,
    request_identity_factory: RequestIdentityFactory | None = None,
    event_sink: EventSink | None = None,
    readiness_probe: ReadinessProbe | None = None,
    document_reader: DocumentReader | None = None,
) -> RetrievalHTTPServer:
    """Construct but do not start the qualified loopback listener."""

    identity_factory = request_identity_factory or (lambda: secrets.token_hex(32))
    sink = event_sink or (lambda _event: None)
    # Readiness stays closed until the configured dependency probe is supplied.
    probe = readiness_probe or (lambda: False)
    return RetrievalHTTPServer(
        deployment,
        api_policy,
        executor,
        identity_factory,
        sink,
        probe,
        document_reader,
    )
