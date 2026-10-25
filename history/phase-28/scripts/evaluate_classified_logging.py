#!/usr/bin/env python3
"""Qualify classified Ishikawa logging entirely in temporary local storage.

Role:
    Exercise profile filtering, protected JSONL, audit separation, bounded
    verbose activation, automatic restoration, rotation, and unsafe-input
    rejection without contacting any runtime dependency.

Mental model:
    Load the deployable profile, emit synthetic typed events into isolated
    directories, inspect their exact classification boundaries, scan all
    retained bytes for prohibited canaries, and keep only a content-free
    qualification receipt.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Qualify classified local logging.")
    parser.add_argument("--python-root", required=True)
    parser.add_argument("--config-root", required=True)
    parser.add_argument("--output", required=True)
    return parser.parse_args()


def require_directory(path: Path, label: str) -> Path:
    if not path.is_absolute() or path.is_symlink() or not path.is_dir():
        raise ValueError(f"{label}_unsafe")
    return path.resolve(strict=True)


def require_output(path: Path) -> Path:
    if not path.is_absolute() or path.exists() or path.is_symlink() or not path.parent.is_dir():
        raise ValueError("output_path_unsafe")
    return path


def read_records(path: Path) -> list[dict[str, Any]]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]


def write_receipt(path: Path, payload: dict[str, Any]) -> None:
    encoded = json.dumps(
        payload,
        ensure_ascii=True,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8") + b"\n"
    with path.open("xb") as destination:
        destination.write(encoded)


def evaluate(python_root: Path, config_root: Path) -> dict[str, Any]:
    sys.path.insert(0, str(python_root))
    from ishikawa.http_listener import ListenerEvent
    from ishikawa.observability import (
        LOG_PROFILES,
        ClassifiedEvent,
        ConfiguredObservability,
        ObservabilityContractError,
        ProtectedJSONLWriter,
        VerboseActivation,
        validate_logging_profile,
    )
    from ishikawa.yaml_loader import load_restricted_yaml

    policy = validate_logging_profile(
        load_restricted_yaml(
            config_root / "logging_profile.yaml",
            label="logging profile",
        )
    )
    current_time = [datetime(2026, 10, 21, 0, 0, tzinfo=timezone.utc)]

    def clock() -> datetime:
        return current_time[0]

    secret_canaries = (
        b"Bearer prohibited-secret",
        b"password=prohibited-secret",
        b"private-key-prohibited-secret",
        b"vector-prohibited-secret",
    )
    request_id = "a" * 64
    with tempfile.TemporaryDirectory(prefix="ishikawa-logging-") as temporary_root:
        root = Path(temporary_root)
        default_root = root / "default"
        debug_root = root / "debug"
        verbose_root = root / "verbose"
        rotation_root = root / "rotation"
        for directory in (default_root, debug_root, verbose_root, rotation_root):
            directory.mkdir(mode=0o700)

        default_logging = ConfiguredObservability(policy, default_root, clock)
        default_logging.listener_event(
            ListenerEvent(
                request_id,
                "application_answered",
                200,
                12,
                ("request-accepted", "generation-complete"),
            )
        )
        default_record = read_records(default_root / policy.operational_filename)[0]
        default_boundary = (
            default_record["classification"] == ["operational"]
            and default_record["request_id"] == request_id
            and "diagnostic" not in default_record
            and "restricted" not in default_record
        )

        debug_raw = dict(
            load_restricted_yaml(
                config_root / "logging_profile.yaml",
                label="logging profile",
            )
        )
        debug_raw["base_profile"] = "debug"
        debug_policy = validate_logging_profile(debug_raw)
        debug_logging = ConfiguredObservability(debug_policy, debug_root, clock)
        debug_logging.operational.write(
            ClassifiedEvent(
                "retrieval-api",
                "retrieval",
                "RETRIEVAL_COMPLETED",
                "info",
                "completed",
                request_id=request_id,
                diagnostic={"lane_counts": {"exact": 1, "lexical": 2, "vector": 3}},
                restricted={"question": "synthetic restricted content"},
            )
        )
        debug_record = read_records(debug_root / debug_policy.operational_filename)[0]
        debug_boundary = (
            debug_record["classification"] == ["operational", "diagnostic"]
            and "lane_counts" in debug_record["diagnostic"]
            and "restricted" not in debug_record
        )

        verbose_logging = ConfiguredObservability(policy, verbose_root, clock)
        activation = VerboseActivation(
            "investigate_response",
            request_id,
            current_time[0],
            current_time[0] + timedelta(minutes=5),
        )
        verbose_logging.activate_verbose(activation)
        verbose_logging.operational.write(
            ClassifiedEvent(
                "retrieval-api",
                "generation",
                "GENERATION_COMPLETED",
                "info",
                "completed",
                request_id=request_id,
                restricted={"answer": "synthetic restricted content\nencoded as one record"},
            )
        )
        current_time[0] += timedelta(minutes=6)
        verbose_logging.operational.write(
            ClassifiedEvent(
                "retrieval-api",
                "generation",
                "GENERATION_COMPLETED",
                "info",
                "completed",
                request_id=request_id,
                restricted={"answer": "synthetic expired content"},
            )
        )
        verbose_records = read_records(verbose_root / policy.operational_filename)
        verbose_boundary = (
            len(verbose_records) == 2
            and verbose_records[0]["profile"] == "verbose"
            and "restricted" in verbose_records[0]
            and verbose_records[1]["profile"] == "default"
            and "restricted" not in verbose_records[1]
        )
        second_activation = VerboseActivation(
            "investigate_response",
            "service",
            current_time[0],
            current_time[0] + timedelta(minutes=5),
        )
        verbose_logging.activate_verbose(second_activation)
        verbose_logging.stop_verbose()
        emergency_stop_boundary = verbose_logging.controller.active_profile() == "default"
        audit_records = read_records(verbose_root / policy.audit_filename)
        audit_boundary = (
            len(audit_records) == 3
            and audit_records[0]["event_code"] == "VERBOSE_CAPTURE_ENABLED"
            and audit_records[0]["reason_code"] == "investigate_response"
            and audit_records[0]["scope"] == "request"
            and audit_records[-1]["event_code"] == "VERBOSE_CAPTURE_DISABLED"
            and all("restricted" not in record for record in audit_records)
        )

        rejected_prohibited_field = False
        try:
            ClassifiedEvent(
                "retrieval-api",
                "request",
                "REQUEST_RECEIVED",
                "info",
                "accepted",
                diagnostic={"authorization": "Bearer prohibited-secret"},
            ).validated()
        except ObservabilityContractError:
            rejected_prohibited_field = True

        rotation_raw = dict(debug_raw)
        rotation_raw.update(
            {
                "base_profile": "default",
                "maximum_event_bytes": 1024,
                "maximum_file_bytes": 1100,
                "retained_file_count": 3,
            }
        )
        rotation_policy = validate_logging_profile(rotation_raw)
        rotation_writer = ProtectedJSONLWriter(
            rotation_root,
            rotation_policy.operational_filename,
            rotation_policy,
        )
        for index in range(5):
            rotation_writer.append({"index": index, "padding": "x" * 700})
        rotation_boundary = (
            (rotation_root / "retrieval.jsonl").is_file()
            and (rotation_root / "retrieval.jsonl.1").is_file()
            and (rotation_root / "retrieval.jsonl.2").is_file()
            and not (rotation_root / "retrieval.jsonl.3").exists()
        )

        protected_modes = all(
            os.stat(path).st_mode & 0o777 == 0o600
            for path in root.rglob("*.jsonl")
        )
        retained_bytes = b"".join(
            path.read_bytes() for path in root.rglob("*.jsonl*") if path.is_file()
        )
        secret_scan_passed = not any(canary in retained_bytes for canary in secret_canaries)
        line_integrity = all(
            all(isinstance(json.loads(line), dict) for line in path.read_text().splitlines())
            for path in root.rglob("*.jsonl*")
            if path.is_file()
        )

    if not all(
        (
            LOG_PROFILES == ("default", "debug", "verbose"),
            default_boundary,
            debug_boundary,
            verbose_boundary,
            emergency_stop_boundary,
            audit_boundary,
            rejected_prohibited_field,
            rotation_boundary,
            protected_modes,
            secret_scan_passed,
            line_integrity,
        )
    ):
        raise ValueError("classified_logging_qualification_failed")

    return {
        "audit_separate_and_content_free": True,
        "automatic_verbose_restoration": True,
        "default_operational_only": True,
        "debug_content_free_diagnostics": True,
        "dependency_contact": False,
        "event_schema": "ishikawa.log-event.v1",
        "profile_count": 3,
        "prohibited_field_rejection": True,
        "protected_file_modes": True,
        "purpose": "classified_logging_qualification",
        "record_forgery_resistance": True,
        "receipt_schema_version": 1,
        "rotation_bounded": True,
        "secret_canary_scan": "pass",
        "target_contact": False,
        "verbose_bounded_and_scoped": True,
    }


def main() -> int:
    arguments = parse_arguments()
    try:
        python_root = require_directory(Path(arguments.python_root), "python_root")
        config_root = require_directory(Path(arguments.config_root), "config_root")
        output_path = require_output(Path(arguments.output))
        result = evaluate(python_root, config_root)
        write_receipt(output_path, result)
    except (OSError, ValueError) as error:
        print(f"classified_logging_qualification=blocked;reason={error}", file=sys.stderr)
        return 1
    print("logging_profiles=default,debug,verbose;profile_count=3")
    print("default=operational-only;debug=content-free-diagnostic")
    print("verbose=bounded-scoped;automatic_restoration=pass;emergency_stop=pass")
    print("audit=separate-content-free;rotation=bounded;file_mode=0600")
    print("record_forgery_resistance=pass;prohibited_field_rejection=pass")
    print("secret_canary_scan=pass;target_contact=false;dependency_contact=false")
    print("classified_logging_qualification=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
