#!/usr/bin/env python3
"""Qualify one configured live-runtime request against an empty catalog."""

from __future__ import annotations

import argparse
import hashlib
import http.client
import importlib
import json
import os
import re
import sys
import threading
from collections import Counter
from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace
from typing import Any, NoReturn

from ishikawa.canonical import canonical_json_bytes
from ishikawa.native_adapters import native_embedding_exchange
from ishikawa.runtime import (
    assemble_configured_retrieval_runtime,
    native_psycopg_connect,
)
from ishikawa.generation_transport import native_http_exchange
from ishikawa.tokenization import native_tokenization_exchange


HEX = re.compile(r"^[0-9a-f]{64}$")
QUESTION = (
    "Under the organization's incident-reporting operating procedure, what professional "
    "reporting requirements must an employee follow?"
)
QUESTION_SHA256 = hashlib.sha256(QUESTION.encode("utf-8")).hexdigest()
EXPECTED_CONFIG_NAMES = (
    "api_profile.yaml",
    "deployment.yaml",
    "injection_profile.yaml",
    "method_profile.yaml",
    "query_resolution_profile.yaml",
    "reconstruction_profile.yaml",
    "relationship_types.yaml",
    "relevance_profile.yaml",
    "retrieval_service_profile.yaml",
    "runtime_dependencies.yaml",
    "scope_profile.yaml",
    "sufficiency_profile.yaml",
)
MAX_CREDENTIAL_BYTES = 1024


def fail(reason: str) -> NoReturn:
    print(f"configured_live_runtime=blocked;reason={reason}")
    raise SystemExit(1)


def wipe(value: bytearray) -> None:
    for index in range(len(value)):
        value[index] = 0


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_credentials() -> tuple[bytearray, bytearray, bytearray]:
    payload = bytearray()
    maximum = (MAX_CREDENTIAL_BYTES * 3) + 2
    while len(payload) <= maximum:
        block = os.read(sys.stdin.fileno(), maximum + 1 - len(payload))
        if not block:
            break
        payload.extend(block)
    if (
        len(payload) > maximum
        or payload.count(b"\n") != 2
        or b"\r" in payload
        or b"\x00" in payload
    ):
        wipe(payload)
        fail("operator_credentials_format_invalid")
    first, second = (index for index, byte in enumerate(payload) if byte == 10)
    gemma = bytearray(payload[:first])
    nomic = bytearray(payload[first + 1 : second])
    database = bytearray(payload[second + 1 :])
    wipe(payload)
    if not (
        32 <= len(gemma) <= MAX_CREDENTIAL_BYTES
        and 32 <= len(nomic) <= MAX_CREDENTIAL_BYTES
        and 1 <= len(database) <= MAX_CREDENTIAL_BYTES
    ):
        wipe(gemma)
        wipe(nomic)
        wipe(database)
        fail("operator_credentials_format_invalid")
    return gemma, nomic, database


def write_artifact(path: Path, value: dict[str, Any]) -> str:
    if path.exists() or path.is_symlink() or not path.parent.is_dir():
        fail("output_path_unsafe")
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(canonical_json_bytes(value) + b"\n")
    except OSError:
        fail("output_write_failed")
    return sha256_file(path)


def instrument_executor(executor, traces: list[tuple[str, ...]]):
    """Observe one configured executor without closing over its replacement."""

    if not callable(executor) or not isinstance(traces, list):
        raise TypeError("executor observation input is invalid")

    def observed(request, request_id):
        execution = executor(request, request_id)
        trace = execution.stage_trace
        if not isinstance(trace, tuple) or any(not isinstance(item, str) for item in trace):
            raise TypeError("executor observation result is invalid")
        traces.append(trace)
        return execution

    return observed


def observer_self_test() -> None:
    calls: list[tuple[object, object]] = []
    traces: list[tuple[str, ...]] = []
    expected = SimpleNamespace(stage_trace=("self-test",))

    def configured(request, request_id):
        calls.append((request, request_id))
        return expected

    observed = instrument_executor(configured, traces)
    actual = observed("request", "request-id")
    if actual is not expected or calls != [("request", "request-id")] or traces != [("self-test",)]:
        fail("executor_observer_self_test_failed")
    print("configured_executor_observer_self_test=pass")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--credential-stdin", action="store_true")
    parser.add_argument("--config-root", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--self-test-observer", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test_observer:
        if arguments.credential_stdin or arguments.config_root is not None or arguments.output is not None:
            fail("executor_observer_self_test_arguments_invalid")
        observer_self_test()
        return
    try:
        psycopg = importlib.import_module("psycopg")
        yaml = importlib.import_module("yaml")
    except ImportError:
        fail("host_python_dependency_missing")
    if not arguments.credential_stdin:
        fail("attended_credential_pipe_required")
    if arguments.config_root is None or arguments.output is None:
        fail("runtime_arguments_missing")
    if (
        not arguments.config_root.is_dir()
        or arguments.config_root.is_symlink()
        or arguments.output.exists()
        or arguments.output.is_symlink()
        or not arguments.output.parent.is_dir()
    ):
        fail("path_contract_invalid")
    for name in EXPECTED_CONFIG_NAMES:
        path = arguments.config_root / name
        if not path.is_file() or path.is_symlink() or path.stat().st_size > 1024 * 1024:
            fail("configuration_source_invalid")

    gemma_secret, nomic_secret, database_secret = read_credentials()
    gemma_key = ""
    nomic_key = ""
    database_password = ""
    counters: Counter[str] = Counter()
    environment_reads: list[str] = []
    traces: list[tuple[str, ...]] = []

    class ObservedEnvironment(dict[str, str]):
        def __getitem__(self, key: str) -> str:
            environment_reads.append(key)
            return super().__getitem__(key)

    try:
        try:
            gemma_key = bytes(gemma_secret).decode("utf-8")
            nomic_key = bytes(nomic_secret).decode("utf-8")
            database_password = bytes(database_secret).decode("utf-8")
        except UnicodeError:
            fail("operator_credentials_not_utf8")

        environment = ObservedEnvironment(
            ISHIKAWA_GEMMA_API_KEY=gemma_key,
            ISHIKAWA_NOMIC_API_KEY=nomic_key,
            ISHIKAWA_POSTGRESQL_PASSWORD=database_password,
        )

        def generation_exchange(prepared):
            counters["generation"] += 1
            try:
                body = json.loads(prepared.body)
            except (UnicodeError, json.JSONDecodeError):
                raise RuntimeError("generation request observation failed")
            if body.get("max_tokens") != 128:
                raise RuntimeError("unexpected grounded generation call")
            counters["scope"] += 1
            return native_http_exchange(prepared)

        def embedding_exchange(prepared):
            counters["embedding"] += 1
            return native_embedding_exchange(prepared)

        def tokenization_exchange(prepared):
            counters["tokenization"] += 1
            return native_tokenization_exchange(prepared)

        def database_connector(**parameters):
            counters["database"] += 1
            expected = {
                "application_name": "ishikawa-retrieval-api",
                "connect_timeout": 10,
                "dbname": "rag_catalog",
                "host": "127.0.0.1",
                "options": "-c default_transaction_read_only=on",
                "port": 5432,
                "user": "rag_retrieval",
            }
            observed = {key: value for key, value in parameters.items() if key != "password"}
            if observed != expected or parameters.get("password") != database_password:
                raise RuntimeError("database connection boundary invalid")
            return native_psycopg_connect(**parameters)

        runtime = assemble_configured_retrieval_runtime(
            arguments.config_root,
            environment=environment,
            database_connector=database_connector,
            generation_exchange=generation_exchange,
            embedding_exchange=embedding_exchange,
            tokenization_exchange=tokenization_exchange,
        )
        if environment_reads or counters:
            fail("assembly_touched_dependency")

        runtime = replace(runtime, executor=instrument_executor(runtime.executor, traces))
        events = []
        listener = runtime.create_http_server(event_sink=events.append)
        if listener.server_address != ("127.0.0.1", 1384):
            listener.server_close()
            fail("listener_address_invalid")
        thread = threading.Thread(target=listener.serve_forever, daemon=True)
        thread.start()
        request = canonical_json_bytes(
            {
                "conversation_id": "1" * 64,
                "filters": {"document_classes": [], "document_keys": []},
                "history": [],
                "message": QUESTION,
                "schema": "ishikawa.chat-request.v1",
                "source_references": [],
                "turn_id": "2" * 64,
            }
        )
        response_status = 0
        response_headers: dict[str, str] = {}
        response_body = b""
        try:
            connection = http.client.HTTPConnection("127.0.0.1", 1384, timeout=300)
            connection.request(
                "POST",
                "/v1/chat",
                body=request,
                headers={"Content-Type": "application/json"},
            )
            response = connection.getresponse()
            response_status = response.status
            response_headers = dict(response.getheaders())
            response_body = response.read()
            connection.close()
        finally:
            listener.shutdown()
            listener.server_close()
            thread.join(timeout=10)
        if thread.is_alive():
            fail("listener_shutdown_failed")
        try:
            document = json.loads(response_body.decode("utf-8"))
        except (UnicodeError, json.JSONDecodeError):
            fail("response_json_invalid")

        expected_trace = (
            "request-accepted",
            "direct-injection-passed",
            "scope-allowed",
            "query-resolved",
            "retrieval-completed",
            "sufficiency-blocked",
        )
        header_contract = (
            response_headers.get("Content-Type") == "application/json"
            and response_headers.get("Cache-Control") == "no-store"
            and response_headers.get("X-Content-Type-Options") == "nosniff"
            and "Server" not in response_headers
        )
        request_id = document.get("request_id")
        envelope_contract = (
            document.get("schema") == "ishikawa.chat-response.v1"
            and document.get("status") == "insufficient-evidence"
            and isinstance(document.get("error"), dict)
            and document["error"].get("code") == "EVIDENCE_INSUFFICIENT"
            and document.get("answer") is None
            and document.get("clarification") is None
            and document.get("claims") == []
            and document.get("sources") == []
            and isinstance(request_id, str)
            and HEX.fullmatch(request_id) is not None
        )
        trace_contract = traces == [expected_trace]
        event_contract = (
            len(events) == 1
            and events[0].outcome == "application_insufficient-evidence"
            and events[0].http_status == 200
            and events[0].request_id == request_id
        )
        if not (
            response_status == 200
            and header_contract
            and envelope_contract
            and trace_contract
            and event_contract
        ):
            allowed_statuses = {
                "answered",
                "clarification-required",
                "insufficient-evidence",
                "out-of-scope",
                "security-rejected",
                "context-limit",
                "temporarily-unavailable",
                "internal-error",
            }
            observed_status = document.get("status")
            if observed_status not in allowed_statuses:
                observed_status = "unrecognized"
            observed_error = document.get("error")
            observed_error_code = (
                observed_error.get("code", "none")
                if isinstance(observed_error, dict)
                else "none"
            )
            if not isinstance(observed_error_code, str) or re.fullmatch(
                r"[A-Z][A-Z0-9_]{2,63}|none", observed_error_code
            ) is None:
                observed_error_code = "unrecognized"
            safe_trace = "unrecognized"
            if traces and all(
                isinstance(stage, str)
                and re.fullmatch(r"[a-z][a-z0-9-]{1,63}", stage) is not None
                for trace in traces
                for stage in trace
            ):
                safe_trace = ",".join(stage for trace in traces for stage in trace)
            observed_event = "none"
            if len(events) == 1 and re.fullmatch(
                r"[a-z][a-z0-9_-]{1,95}", events[0].outcome
            ) is not None:
                observed_event = events[0].outcome
            print(
                f"response_observation=http_{response_status};"
                f"status={observed_status};error_code={observed_error_code}"
            )
            print(
                f"response_headers_contract={'pass' if header_contract else 'blocked'};"
                f"response_envelope_contract={'pass' if envelope_contract else 'blocked'};"
                f"response_trace_contract={'pass' if trace_contract else 'blocked'};"
                f"response_event_contract={'pass' if event_contract else 'blocked'}"
            )
            print(f"observed_stage_trace={safe_trace};observed_event={observed_event}")
            print(
                f"scope_calls={counters['scope']};"
                f"embedding_calls={counters['embedding']};"
                f"database_connections={counters['database']};"
                f"tokenization_calls={counters['tokenization']};"
                f"generation_calls={counters['generation']}"
            )
            fail("runtime_response_contract_invalid")
        if counters != Counter(
            {"generation": 1, "scope": 1, "embedding": 1, "database": 1, "tokenization": 2}
        ):
            fail("dependency_call_count_invalid")
        if Counter(environment_reads) != Counter(
            {
                "ISHIKAWA_GEMMA_API_KEY": 3,
                "ISHIKAWA_NOMIC_API_KEY": 1,
                "ISHIKAWA_POSTGRESQL_PASSWORD": 1,
            }
        ):
            fail("credential_read_count_invalid")

        configuration_sha256 = {
            name: sha256_file(arguments.config_root / name) for name in EXPECTED_CONFIG_NAMES
        }
        artifact = {
            "application": {
                "error_code": "EVIDENCE_INSUFFICIENT",
                "http_status": 200,
                "listener": "127.0.0.1:1384",
                "listener_shutdown": True,
                "request_id_valid": True,
                "stage_trace": list(expected_trace),
                "status": "insufficient-evidence",
            },
            "configuration_sha256": configuration_sha256,
            "dependencies": {
                "database_connections": counters["database"],
                "embedding_calls": counters["embedding"],
                "grounded_generation_calls": 0,
                "scope_calls": counters["scope"],
                "tokenization_calls": counters["tokenization"],
            },
            "environment_reads": {
                "gemma": 3,
                "nomic": 1,
                "postgresql": 1,
            },
            "host_runtime": {
                "architecture": os.uname().machine,
                "psycopg_version": psycopg.__version__,
                "pyyaml_version": yaml.__version__,
                "python_version": ".".join(str(item) for item in sys.version_info[:3]),
            },
            "purpose": "configured_live_runtime_empty_catalog_qualification",
            "runtime_identity": runtime.policies.digest,
            "schema_version": 1,
            "security": {
                "credentials_retained": False,
                "raw_request_retained": False,
                "raw_response_retained": False,
                "vectors_retained": False,
            },
            "synthetic_question_sha256": QUESTION_SHA256,
        }
        artifact_sha256 = write_artifact(arguments.output, artifact)
    except SystemExit:
        raise
    except Exception:
        fail("unexpected_runtime_failure")
    finally:
        gemma_key = ""
        nomic_key = ""
        database_password = ""
        wipe(gemma_secret)
        wipe(nomic_secret)
        wipe(database_secret)

    print("runtime_assembly=pass;configuration_profiles=12")
    print("listener_endpoint=127.0.0.1:1384;http_status=200;listener_shutdown=pass")
    print("application_status=insufficient-evidence;error_code=EVIDENCE_INSUFFICIENT")
    print("scope_calls=1;query_resolution=deterministic;grounded_generation_calls=0")
    print("embedding_calls=1;database_connections=1;tokenization_calls=2")
    print("database_name=rag_catalog;database_role=rag_retrieval;transaction=read_only")
    print("credentials_retained=false;raw_request_retained=false;raw_response_retained=false;vectors_retained=false")
    print(f"runtime_identity={runtime.policies.digest}")
    print(f"qualification_artifact=pass;sha256={artifact_sha256}")
    print("configured_live_runtime_qualification=pass")


if __name__ == "__main__":
    main()
