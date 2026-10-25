"""Protected local operator control for bounded verbose logging.

Role:
    Serve and call one Unix-domain control channel owned by the running
    Ishikawa Retrieval API. The channel can inspect the active profile, enable
    one bounded verbose scope, or perform an emergency disable.

Mental model:
    Filesystem ownership and mode protect a fixed local socket. Requests and
    responses use exact, bounded JSON contracts. The server delegates state
    changes to the already-qualified in-memory logging controller, so restart
    always removes verbose state.

Side effects:
    The service creates and removes ``state/run/logging-control.sock``. The
    operator client contacts only that socket. No network port, credential,
    configuration file, database, model, or service definition is changed.
"""

from __future__ import annotations

import json
import os
import re
import socket
import stat
import struct
import threading
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from datetime import timedelta
from pathlib import Path
from typing import Any, TextIO

from .canonical import canonical_json_bytes
from .observability import ConfiguredObservability, VerboseActivation


CONTROL_SOCKET_FILENAME = "logging-control.sock"
CONTROL_REQUEST_SCHEMA = "ishikawa.logging-control-request.v1"
CONTROL_RESPONSE_SCHEMA = "ishikawa.logging-control-response.v1"
MAXIMUM_CONTROL_BYTES = 4096
_IDENTITY = re.compile(r"^[0-9a-f]{64}$")
_REASON_CODE = re.compile(r"^[a-z][a-z0-9_-]{0,95}$")


class LoggingControlError(ValueError):
    """Raised when a control request or local channel is invalid."""


def _reject_duplicate_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise LoggingControlError("control JSON contains a duplicate field")
        result[key] = value
    return result


def _decode_mapping(encoded: bytes) -> Mapping[str, Any]:
    if not isinstance(encoded, bytes) or not 1 <= len(encoded) <= MAXIMUM_CONTROL_BYTES:
        raise LoggingControlError("control payload size is invalid")
    try:
        value = json.loads(
            encoded.decode("utf-8"),
            object_pairs_hook=_reject_duplicate_pairs,
            parse_constant=lambda _value: (_ for _ in ()).throw(
                LoggingControlError("control JSON number is invalid")
            ),
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise LoggingControlError("control JSON is invalid") from error
    if not isinstance(value, Mapping):
        raise LoggingControlError("control payload is not a mapping")
    return value


@dataclass(frozen=True, slots=True)
class LoggingControlRequest:
    action: str
    reason_code: str | None = None
    duration_seconds: int | None = None
    scope: str | None = None

    def canonical(self) -> dict[str, Any]:
        if self.action == "enable":
            if (
                _REASON_CODE.fullmatch(self.reason_code or "") is None
                or type(self.duration_seconds) is not int
                or not 1 <= self.duration_seconds <= 86400
                or (
                    self.scope != "service"
                    and _IDENTITY.fullmatch(self.scope or "") is None
                )
            ):
                raise LoggingControlError("enable request is invalid")
            return {
                "action": "enable",
                "duration_seconds": self.duration_seconds,
                "reason_code": self.reason_code,
                "schema": CONTROL_REQUEST_SCHEMA,
                "scope": self.scope,
            }
        if self.action in {"disable", "status"}:
            if any(
                value is not None
                for value in (self.reason_code, self.duration_seconds, self.scope)
            ):
                raise LoggingControlError("control request fields are invalid")
            return {"action": self.action, "schema": CONTROL_REQUEST_SCHEMA}
        raise LoggingControlError("control action is invalid")


def encode_control_request(request: LoggingControlRequest) -> bytes:
    return canonical_json_bytes(request.canonical()) + b"\n"


def decode_control_request(encoded: bytes) -> LoggingControlRequest:
    value = _decode_mapping(encoded)
    if value.get("schema") != CONTROL_REQUEST_SCHEMA:
        raise LoggingControlError("control request schema is invalid")
    action = value.get("action")
    if action == "enable" and set(value) == {
        "action",
        "duration_seconds",
        "reason_code",
        "schema",
        "scope",
    }:
        request = LoggingControlRequest(
            "enable",
            value["reason_code"],
            value["duration_seconds"],
            value["scope"],
        )
    elif action in {"disable", "status"} and set(value) == {"action", "schema"}:
        request = LoggingControlRequest(action)
    else:
        raise LoggingControlError("control request fields are invalid")
    request.canonical()
    return request


def _response(action: str, status: str, profile: str | None = None) -> bytes:
    payload: dict[str, Any] = {
        "action": action,
        "schema": CONTROL_RESPONSE_SCHEMA,
        "status": status,
    }
    if profile is not None:
        payload["profile"] = profile
    return canonical_json_bytes(payload) + b"\n"


def decode_control_response(encoded: bytes) -> Mapping[str, Any]:
    value = _decode_mapping(encoded)
    if value.get("schema") != CONTROL_RESPONSE_SCHEMA:
        raise LoggingControlError("control response schema is invalid")
    status = value.get("status")
    action = value.get("action")
    expected = {"action", "schema", "status", "profile"} if status == "ok" else {
        "action",
        "schema",
        "status",
    }
    if (
        set(value) != expected
        or action not in {"enable", "disable", "status", "unknown"}
        or status not in {"ok", "error"}
        or (status == "ok" and value.get("profile") not in {"default", "debug", "verbose"})
    ):
        raise LoggingControlError("control response fields are invalid")
    return value


class LoggingControlServer:
    """Serve one owner-only Unix socket beside the protected log directory."""

    def __init__(self, observability: ConfiguredObservability, run_root: Path):
        if not isinstance(observability, ConfiguredObservability):
            raise LoggingControlError("configured observability is invalid")
        if not isinstance(run_root, Path) or not run_root.is_dir() or run_root.is_symlink():
            raise LoggingControlError("runtime control root is unsafe")
        self.observability = observability
        self.run_root = run_root.resolve(strict=True)
        if self.run_root.stat().st_uid != os.getuid():
            raise LoggingControlError("runtime control root is unsafe")
        self.socket_path = self.run_root / CONTROL_SOCKET_FILENAME
        self._listener: socket.socket | None = None
        self._thread: threading.Thread | None = None
        self._stopping = threading.Event()
        self._socket_inode: int | None = None
        self._failure = False

    @property
    def failed(self) -> bool:
        return self._failure

    def start(self) -> None:
        if self._listener is not None or self._thread is not None:
            raise LoggingControlError("logging control is already started")
        os.chmod(self.run_root, 0o700)
        try:
            self.socket_path.lstat()
        except FileNotFoundError:
            pass
        else:
            raise LoggingControlError("logging control socket already exists")
        listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            listener.bind(str(self.socket_path))
            os.chmod(self.socket_path, 0o600)
            metadata = self.socket_path.lstat()
            if not stat.S_ISSOCK(metadata.st_mode) or metadata.st_uid != os.getuid():
                raise LoggingControlError("logging control socket is unsafe")
            self._socket_inode = metadata.st_ino
            listener.listen(4)
            listener.settimeout(0.2)
        except BaseException:
            listener.close()
            self._remove_owned_socket()
            raise
        self._listener = listener
        self._stopping.clear()
        self._thread = threading.Thread(
            target=self._serve,
            name="ishikawa-logging-control",
            daemon=False,
        )
        self._thread.start()

    def _peer_is_owner(self, connection: socket.socket) -> bool:
        if not hasattr(socket, "SO_PEERCRED"):
            return True
        credentials = connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12)
        _process_id, user_id, _group_id = struct.unpack("3i", credentials)
        return user_id == os.getuid()

    def _receive(self, connection: socket.socket) -> bytes:
        received = bytearray()
        while len(received) <= MAXIMUM_CONTROL_BYTES:
            chunk = connection.recv(min(1024, MAXIMUM_CONTROL_BYTES + 1 - len(received)))
            if not chunk:
                break
            received.extend(chunk)
            if b"\n" in chunk:
                break
        if not received.endswith(b"\n") or received.count(b"\n") != 1:
            raise LoggingControlError("control record boundary is invalid")
        return bytes(received[:-1])

    def _execute(self, request: LoggingControlRequest) -> bytes:
        if request.action == "enable":
            now = self.observability.controller.clock()
            self.observability.activate_verbose(
                VerboseActivation(
                    request.reason_code or "",
                    request.scope or "",
                    now,
                    now + timedelta(seconds=request.duration_seconds or 0),
                )
            )
        elif request.action == "disable":
            self.observability.stop_verbose()
        profile = self.observability.controller.control_profile()
        return _response(request.action, "ok", profile)

    def _serve_connection(self, connection: socket.socket) -> None:
        action = "unknown"
        try:
            connection.settimeout(2)
            if not self._peer_is_owner(connection):
                raise LoggingControlError("control peer is not permitted")
            request = decode_control_request(self._receive(connection))
            action = request.action
            response = self._execute(request)
        except Exception:
            response = _response(action, "error")
        try:
            connection.sendall(response)
        except OSError:
            pass

    def _serve(self) -> None:
        try:
            while not self._stopping.is_set():
                listener = self._listener
                if listener is None:
                    break
                try:
                    connection, _address = listener.accept()
                except socket.timeout:
                    continue
                except OSError:
                    if self._stopping.is_set():
                        break
                    raise
                with connection:
                    self._serve_connection(connection)
        except Exception:
            self._failure = True

    def _remove_owned_socket(self) -> None:
        try:
            metadata = self.socket_path.lstat()
        except FileNotFoundError:
            return
        if (
            self._socket_inode is not None
            and metadata.st_ino == self._socket_inode
            and stat.S_ISSOCK(metadata.st_mode)
            and metadata.st_uid == os.getuid()
        ):
            self.socket_path.unlink()

    def stop(self) -> None:
        self._stopping.set()
        listener = self._listener
        if listener is not None:
            listener.close()
        thread = self._thread
        if thread is not None:
            thread.join(timeout=5)
            if thread.is_alive():
                self._failure = True
        self._listener = None
        self._thread = None
        self._remove_owned_socket()


def _require_control_socket(path: Path) -> Path:
    if not path.is_absolute() or path.is_symlink():
        raise LoggingControlError("logging control socket is unsafe")
    metadata = path.lstat()
    if (
        not stat.S_ISSOCK(metadata.st_mode)
        or metadata.st_uid != os.getuid()
        or metadata.st_mode & 0o077
    ):
        raise LoggingControlError("logging control socket is unsafe")
    return path


def native_control_exchange(socket_path: Path, request_bytes: bytes) -> bytes:
    path = _require_control_socket(socket_path)
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(3)
    try:
        client.connect(str(path))
        client.sendall(request_bytes)
        client.shutdown(socket.SHUT_WR)
        response = bytearray()
        while len(response) <= MAXIMUM_CONTROL_BYTES:
            chunk = client.recv(min(1024, MAXIMUM_CONTROL_BYTES + 1 - len(response)))
            if not chunk:
                break
            response.extend(chunk)
            if b"\n" in chunk:
                break
    finally:
        client.close()
    if not response.endswith(b"\n") or response.count(b"\n") != 1:
        raise LoggingControlError("control response boundary is invalid")
    return bytes(response[:-1])


def _parse_enable(arguments: Sequence[str]) -> LoggingControlRequest:
    values: dict[str, str] = {}
    index = 1
    while index < len(arguments):
        option = arguments[index]
        if option not in {"--reason", "--duration-seconds", "--scope", "--request-id"}:
            raise LoggingControlError("logging control arguments are invalid")
        if option in values or index + 1 >= len(arguments):
            raise LoggingControlError("logging control arguments are invalid")
        values[option] = arguments[index + 1]
        index += 2
    if set(values) not in (
        {"--reason", "--duration-seconds", "--scope"},
        {"--reason", "--duration-seconds", "--request-id"},
    ):
        raise LoggingControlError("logging control arguments are invalid")
    if "--scope" in values and values["--scope"] != "service":
        raise LoggingControlError("logging control scope is invalid")
    try:
        duration_seconds = int(values["--duration-seconds"], 10)
    except ValueError as error:
        raise LoggingControlError("logging control duration is invalid") from error
    request = LoggingControlRequest(
        "enable",
        values["--reason"],
        duration_seconds,
        values.get("--request-id", "service"),
    )
    request.canonical()
    return request


def execute_logging_control(
    arguments: Sequence[str],
    *,
    product_root: str | Path,
    output: TextIO,
) -> int:
    """Validate one operator action and send it to the running local service."""

    if tuple(arguments) in (("--help",), ("-h",)):
        output.write(
            "Usage: ishikawa-log-control status | disable | "
            "enable --reason CODE --duration-seconds N "
            "(--scope service | --request-id ID)\n"
        )
        return 0
    try:
        if tuple(arguments) in (("status",), ("disable",)):
            request = LoggingControlRequest(arguments[0])
        elif arguments and arguments[0] == "enable":
            request = _parse_enable(arguments)
        else:
            raise LoggingControlError("logging control arguments are invalid")
        root = Path(product_root).resolve(strict=True)
        socket_path = root / "state/run" / CONTROL_SOCKET_FILENAME
        response = decode_control_response(
            native_control_exchange(socket_path, encode_control_request(request))
        )
        if response["status"] != "ok" or response["action"] != request.action:
            raise LoggingControlError("logging control action failed")
    except Exception:
        output.write("ishikawa_logging_control=blocked;reason=control_unavailable\n")
        return 1
    output.write(
        "ishikawa_logging_control=pass;"
        f"action={response['action']};profile={response['profile']}\n"
    )
    return 0
