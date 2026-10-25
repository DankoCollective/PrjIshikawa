#!/usr/bin/env python3
"""Return content-free stage history for explicitly named request identities."""

from __future__ import annotations

import argparse
import json
import os
import platform
import re
import socket
import stat
import tempfile
from pathlib import Path
from typing import Any


IDENTITY = re.compile(r"^[0-9a-f]{64}$")
CASE = re.compile(r"^[A-Z]-[0-9]{3}$")
LOG_NAME = re.compile(r"^(retrieval|metrics)\.jsonl(?:\.[1-9][0-9]*)?$")
MAXIMUM_LOG_BYTES = 128 * 1024 * 1024


class DiagnosticError(ValueError):
    """Stable failure for an invalid or incomplete diagnostic boundary."""


def _object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise DiagnosticError("duplicate JSON field")
        value[key] = item
    return value


def _records(log_root: Path, prefix: str) -> list[dict[str, Any]]:
    candidates = sorted(
        path
        for path in log_root.iterdir()
        if LOG_NAME.fullmatch(path.name) and path.name.startswith(prefix)
    )
    total_bytes = 0
    records: list[dict[str, Any]] = []
    for path in candidates:
        metadata = path.lstat()
        if not stat.S_ISREG(metadata.st_mode):
            raise DiagnosticError("log input is unsafe")
        total_bytes += metadata.st_size
        if total_bytes > MAXIMUM_LOG_BYTES:
            raise DiagnosticError("log input exceeds the bounded size")
        with path.open("r", encoding="utf-8") as handle:
            for line_number, line in enumerate(handle, start=1):
                if not line.endswith("\n") or len(line) > 65536:
                    raise DiagnosticError("log record is malformed")
                try:
                    value = json.loads(line, object_pairs_hook=_object)
                except (json.JSONDecodeError, UnicodeError) as error:
                    raise DiagnosticError("log record is invalid JSON") from error
                if not isinstance(value, dict):
                    raise DiagnosticError("log record is not an object")
                value["_source_order"] = (path.name, line_number)
                records.append(value)
    return records


def _failure_boundary(stages: tuple[str, ...]) -> tuple[str, str]:
    if not stages or stages[-1] != "dependency-unavailable":
        raise DiagnosticError("dependency failure stage is absent")
    previous = stages[-2] if len(stages) > 1 else "none"
    boundaries = {
        "direct-injection-passed": "scope-classification",
        "scope-allowed": "query-resolution",
        "query-resolved": "retrieval",
        "retrieval-completed": "post-retrieval-validation",
        "indirect-injection-passed": "sufficiency",
        "sufficiency-passed": "grounded-generation",
    }
    return previous, boundaries.get(previous, "unresolved-stage")


def inspect_requests(product_root: Path, cases: tuple[tuple[str, str], ...]) -> dict[str, Any]:
    root = product_root.resolve(strict=True)
    log_root = root / "state" / "logs"
    if not log_root.is_dir() or log_root.is_symlink():
        raise DiagnosticError("log root is unsafe")
    retrieval_records = _records(log_root, "retrieval.jsonl")
    metric_records = _records(log_root, "metrics.jsonl")
    observations: list[dict[str, Any]] = []
    for case_id, request_id in cases:
        outcomes = [
            record
            for record in retrieval_records
            if record.get("request_id") == request_id
            and record.get("component") == "retrieval-api"
            and record.get("stage") == "http-response"
        ]
        if len(outcomes) != 1:
            raise DiagnosticError("request outcome is missing or ambiguous")
        outcome = outcomes[0]
        stage_records = [
            record
            for record in metric_records
            if record.get("request_id") == request_id
            and record.get("metric_name") == "pipeline_stage_completed_total"
            and record.get("value") == 1
            and isinstance(record.get("labels"), dict)
            and isinstance(record["labels"].get("stage"), str)
        ]
        stage_records.sort(
            key=lambda item: (
                item.get("timestamp_utc", ""),
                item["_source_order"][0],
                item["_source_order"][1],
            )
        )
        stages = tuple(record["labels"]["stage"] for record in stage_records)
        previous, boundary = _failure_boundary(stages)
        # Application outcomes use a valid versioned response envelope. The
        # HTTP exchange therefore succeeds with 200 while the body and the
        # classified outcome report the dependency failure.
        if outcome.get("outcome") != "application_temporarily_unavailable" or outcome.get(
            "http_status"
        ) != 200:
            raise DiagnosticError("request outcome does not match the retained baseline")
        observations.append(
            {
                "case_id": case_id,
                "failure_boundary": boundary,
                "http_status": 200,
                "last_completed_stage": previous,
                "outcome": "temporarily-unavailable",
                "request_id": request_id,
                "stage_trace": list(stages),
            }
        )
    return {
        "artifact_kind": "ishikawa_content_free_request_diagnostics",
        "cases": observations,
        "raw_content_retained": False,
        "schema_version": 1,
    }


def _write(path: Path, value: dict[str, Any]) -> None:
    if not path.is_absolute() or path.exists() or path.is_symlink():
        raise DiagnosticError("output path is unsafe")
    parent = path.parent.resolve(strict=True)
    if parent.is_symlink():
        raise DiagnosticError("output parent is unsafe")
    flags = os.O_CREAT | os.O_EXCL | os.O_WRONLY
    flags |= getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags, 0o600)
    try:
        encoded = json.dumps(
            value, ensure_ascii=True, allow_nan=False, sort_keys=True, separators=(",", ":")
        ).encode("utf-8") + b"\n"
        os.write(descriptor, encoded)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _os_version() -> tuple[str, str]:
    values: dict[str, str] = {}
    for line in Path("/etc/os-release").read_text(encoding="utf-8").splitlines():
        if "=" not in line:
            continue
        key, raw = line.split("=", 1)
        values[key] = raw.strip().strip('"')
    return values.get("ID", ""), values.get("VERSION_ID", "")


def self_test() -> None:
    first = "1" * 64
    second = "2" * 64
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        log_root = root / "state" / "logs"
        log_root.mkdir(parents=True)
        retrieval = []
        metrics = []
        for index, request_id in enumerate((first, second), start=1):
            retrieval.append(
                {
                    "component": "retrieval-api",
                    "http_status": 200,
                    "outcome": "application_temporarily_unavailable",
                    "request_id": request_id,
                    "stage": "http-response",
                }
            )
            for sequence, stage in enumerate(
                ("request-accepted", "direct-injection-passed", "scope-allowed", "query-resolved", "dependency-unavailable")
            ):
                metrics.append(
                    {
                        "labels": {"stage": stage},
                        "metric_name": "pipeline_stage_completed_total",
                        "request_id": request_id,
                        "timestamp_utc": f"2026-01-0{index}T00:00:0{sequence}.000Z",
                        "value": 1,
                    }
                )
        (log_root / "retrieval.jsonl").write_text(
            "".join(json.dumps(item) + "\n" for item in retrieval), encoding="utf-8"
        )
        (log_root / "metrics.jsonl").write_text(
            "".join(json.dumps(item) + "\n" for item in metrics), encoding="utf-8"
        )
        result = inspect_requests(root, (("R-001", first), ("R-003", second)))
        assert len(result["cases"]) == 2
        assert all(item["failure_boundary"] == "retrieval" for item in result["cases"])
        assert all(item["http_status"] == 200 for item in result["cases"])
    print("request_stage_history_self_test=pass")


def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--self-test", action="store_true")
    mode.add_argument("--inspect", action="store_true")
    parser.add_argument("--product-root")
    parser.add_argument("--expected-hostname")
    parser.add_argument("--expected-os-version")
    parser.add_argument("--case", action="append", default=[])
    parser.add_argument("--output")
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
        return 0
    if not all(
        isinstance(value, str) and value
        for value in (
            arguments.product_root,
            arguments.expected_hostname,
            arguments.expected_os_version,
            arguments.output,
        )
    ):
        raise DiagnosticError("inspection argument is missing")
    cases: list[tuple[str, str]] = []
    for value in arguments.case:
        if not isinstance(value, str) or "=" not in value:
            raise DiagnosticError("case argument is invalid")
        case_id, request_id = value.split("=", 1)
        if CASE.fullmatch(case_id) is None or IDENTITY.fullmatch(request_id) is None:
            raise DiagnosticError("case argument is invalid")
        cases.append((case_id, request_id))
    if len(cases) != 2 or len(set(cases)) != 2:
        raise DiagnosticError("exactly two unique cases are required")
    hostname = socket.gethostname().split(".", 1)[0]
    os_id, os_version = _os_version()
    if hostname != arguments.expected_hostname or os_id != "ubuntu" or os_version != arguments.expected_os_version:
        raise DiagnosticError("target identity does not match")
    result = inspect_requests(Path(arguments.product_root), tuple(cases))
    result["target"] = {
        "architecture": platform.machine(),
        "hostname": hostname,
        "os_id": os_id,
        "os_version": os_version,
    }
    _write(Path(arguments.output), result)
    for item in result["cases"]:
        print(
            f"diagnostic_case={item['case_id']};outcome={item['outcome']};"
            f"http_status={item['http_status']};failure_boundary={item['failure_boundary']};"
            f"last_completed_stage={item['last_completed_stage']};"
            f"stage_count={len(item['stage_trace'])}"
        )
    print("request_diagnostics=pass;cases=2;raw_content_retained=false")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except DiagnosticError as error:
        print(f"request_diagnostics=blocked;reason={str(error).replace(' ', '_')}")
        raise SystemExit(1)
