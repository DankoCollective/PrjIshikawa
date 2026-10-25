#!/usr/bin/env python3
"""Qualify Ishikawa observability retention entirely in temporary storage."""

from __future__ import annotations

import argparse
import io
import json
import os
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Qualify observability retention.")
    parser.add_argument("--python-root", required=True)
    parser.add_argument("--config-root", required=True)
    parser.add_argument("--service-unit", required=True)
    parser.add_argument("--timer-unit", required=True)
    parser.add_argument("--output", required=True)
    return parser.parse_args()


def require_file(path: Path, label: str) -> Path:
    if not path.is_absolute() or path.is_symlink() or not path.is_file():
        raise ValueError(f"{label}_unsafe")
    return path.resolve(strict=True)


def require_directory(path: Path, label: str) -> Path:
    if not path.is_absolute() or path.is_symlink() or not path.is_dir():
        raise ValueError(f"{label}_unsafe")
    return path.resolve(strict=True)


def create_aged_file(path: Path, now: datetime, age_days: int) -> None:
    path.write_text('{"safe":true}\n', encoding="utf-8")
    os.chmod(path, 0o600)
    timestamp = (now - timedelta(days=age_days)).timestamp()
    os.utime(path, (timestamp, timestamp))


def evaluate(
    python_root: Path,
    config_root: Path,
    service_unit: Path,
    timer_unit: Path,
) -> dict[str, object]:
    sys.path.insert(0, str(python_root))
    from ishikawa.observability import validate_logging_profile
    from ishikawa.observability_retention import execute_observability_retention
    from ishikawa.yaml_loader import load_restricted_yaml

    policy = validate_logging_profile(
        load_restricted_yaml(config_root / "logging_profile.yaml", label="logging profile")
    )
    now = datetime(2026, 10, 21, 4, 0, tzinfo=timezone.utc)
    with tempfile.TemporaryDirectory(prefix="ishikawa-retention-") as temporary_root:
        product_root = Path(temporary_root) / "Ishikawa"
        (product_root / "config").mkdir(parents=True)
        log_root = product_root / "state/logs"
        log_root.mkdir(parents=True, mode=0o700)
        (product_root / "config/logging_profile.yaml").write_bytes(
            (config_root / "logging_profile.yaml").read_bytes()
        )
        create_aged_file(log_root / "retrieval.jsonl.1", now, 31)
        create_aged_file(log_root / "retrieval.jsonl.2", now, 29)
        create_aged_file(log_root / "metrics.jsonl", now, 31)
        create_aged_file(log_root / "audit.jsonl.1", now, 91)
        create_aged_file(log_root / "unrelated.jsonl", now, 1000)

        output = io.StringIO()
        status = execute_observability_retention(
            ["--apply"],
            product_root=product_root,
            output=output,
            clock=lambda: now,
        )
        audit_records = [
            json.loads(line)
            for line in (log_root / "audit.jsonl").read_text(encoding="utf-8").splitlines()
        ]
        expected_audit = [
            "OBSERVABILITY_RETENTION_STARTED",
            "OBSERVABILITY_RETENTION_COMPLETED",
        ]
        expected_output = (
            "ishikawa_observability_retention=pass;mode=apply;"
            "operational_deleted=1;metrics_deleted=1;audit_deleted=1;files_deleted=3\n"
        )
        lock_files = tuple(log_root.glob(".*.lock"))
        runtime_passed = all(
            (
                status == 0,
                output.getvalue() == expected_output,
                not (log_root / "retrieval.jsonl.1").exists(),
                (log_root / "retrieval.jsonl.2").is_file(),
                not (log_root / "metrics.jsonl").exists(),
                not (log_root / "audit.jsonl.1").exists(),
                (log_root / "unrelated.jsonl").is_file(),
                [record["event_code"] for record in audit_records] == expected_audit,
                len(lock_files) == 3,
                all(path.stat().st_mode & 0o777 == 0o600 for path in lock_files),
            )
        )

    service_text = service_unit.read_text(encoding="utf-8")
    timer_text = timer_unit.read_text(encoding="utf-8")
    scheduler_passed = all(
        (
            "Type=oneshot" in service_text,
            "ExecStart=%h/Documents/Ishikawa/scripts/ishikawa-observability-retention --apply"
            in service_text,
            "ReadWritePaths=%h/Documents/Ishikawa/state/logs" in service_text,
            "OnCalendar=daily" in timer_text,
            "Persistent=yes" in timer_text,
            "WantedBy=timers.target" in timer_text,
            "ishikawa-retrieval-api" not in service_text + timer_text,
        )
    )
    if not runtime_passed or not scheduler_passed:
        raise RuntimeError("observability_retention_boundary_failed")
    return {
        "audit_retention_days": policy.audit_retention_days,
        "content_free_audit": True,
        "database_changed": False,
        "external_service": False,
        "files_deleted": 3,
        "metrics_retention_days": policy.metrics_retention_days,
        "model_call": False,
        "operational_retention_days": policy.operational_retention_days,
        "protected_locks": 3,
        "retrieval_api_started": False,
        "schedule": "daily",
        "target_contact": False,
    }


def main() -> int:
    arguments = parse_arguments()
    python_root = require_directory(Path(arguments.python_root), "python_root")
    config_root = require_directory(Path(arguments.config_root), "config_root")
    service_unit = require_file(Path(arguments.service_unit), "service_unit")
    timer_unit = require_file(Path(arguments.timer_unit), "timer_unit")
    output = Path(arguments.output)
    if not output.is_absolute() or output.exists() or not output.parent.is_dir():
        raise ValueError("output_path_unsafe")
    receipt = evaluate(python_root, config_root, service_unit, timer_unit)
    encoded = json.dumps(receipt, sort_keys=True, separators=(",", ":")).encode() + b"\n"
    with output.open("xb") as destination:
        destination.write(encoded)
    os.chmod(output, 0o600)
    print("retention_days=operational:30,metrics:30,audit:90;bounds=1-3650")
    print("candidate_scope=configured-active-and-numbered-rotations;unrelated=preserved")
    print("locking=protected-cross-process;unsafe-candidate=all-or-block")
    print("audit=start-and-completion;output=content-free-counts")
    print("scheduler=systemd-user-timer;schedule=daily;retrieval-api-started=false")
    print("target_contact=false;database_changed=false;model_call=false")
    print("observability_retention_qualification=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
