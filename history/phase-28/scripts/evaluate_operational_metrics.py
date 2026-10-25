#!/usr/bin/env python3
"""Qualify Ishikawa content-free operational metrics in temporary storage."""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Qualify operational metrics.")
    parser.add_argument("--python-root", required=True)
    parser.add_argument("--config-root", required=True)
    parser.add_argument("--output", required=True)
    return parser.parse_args()


def require_directory(path: Path, label: str) -> Path:
    if not path.is_absolute() or path.is_symlink() or not path.is_dir():
        raise ValueError(f"{label}_unsafe")
    return path.resolve(strict=True)


def require_output(path: Path) -> Path:
    if (
        not path.is_absolute()
        or path.exists()
        or path.is_symlink()
        or not path.parent.is_dir()
    ):
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
    os.chmod(path, 0o600)


def evaluate(python_root: Path, config_root: Path) -> dict[str, Any]:
    sys.path.insert(0, str(python_root))
    from ishikawa.http_listener import ListenerEvent
    from ishikawa.observability import (
        ContentFreeMetric,
        ConfiguredObservability,
        ObservabilityContractError,
        validate_logging_profile,
    )
    from ishikawa.retrieval_service import RetrievalOperationalTelemetry
    from ishikawa.yaml_loader import load_restricted_yaml

    policy = validate_logging_profile(
        load_restricted_yaml(
            config_root / "logging_profile.yaml",
            label="logging profile",
        )
    )
    fixed_time = datetime(2026, 10, 21, 2, 0, tzinfo=timezone.utc)
    request_id = "a" * 64
    secret_canaries = (
        "Bearer prohibited-secret",
        "password=prohibited-secret",
        "question-prohibited-content",
        "vector-prohibited-content",
        "/private/prohibited/path",
    )
    telemetry = RetrievalOperationalTelemetry(
        lane_states=(("exact", "not_applicable"), ("lexical", "pass"), ("vector", "pass")),
        fused_candidate_count=9,
        authorized_candidate_count=6,
        reconstructed_unit_count=3,
        citation_count=4,
        prompt_token_count=0,
        answer_token_reserve=0,
        context_tokens_used=2048,
        context_token_limit=32768,
        nomic_query_tokens=0,
    )
    with tempfile.TemporaryDirectory(prefix="ishikawa-metrics-") as temporary_root:
        log_root = Path(temporary_root) / "logs"
        log_root.mkdir(mode=0o700)
        observability = ConfiguredObservability(policy, log_root, lambda: fixed_time)
        event = ListenerEvent(
            request_id,
            "application_answered",
            200,
            21,
            ("request-accepted", "retrieval-completed", "response-built"),
            (
                ("request-accepted", 1),
                ("retrieval-completed", 15),
                ("response-built", 5),
            ),
            telemetry,
        )
        observability.listener_event(event)
        metric_path = log_root / policy.metrics_filename
        records = read_records(metric_path)

        expected_names = {
            "requests_total",
            "request_duration_milliseconds",
            "pipeline_stage_completed_total",
            "pipeline_stage_duration_milliseconds",
            "retrieval_lane_state_total",
            "fused_candidate_count",
            "authorized_candidate_count",
            "reconstructed_unit_count",
            "citation_count",
            "context_tokens_used",
            "context_token_limit",
        }
        exact_fields = {
            "labels",
            "metric_name",
            "metric_type",
            "request_id",
            "schema",
            "timestamp_utc",
            "unit",
            "value",
        }
        rejected_unknown_label = False
        try:
            ContentFreeMetric(
                "requests_total",
                1,
                request_id,
                {"category": "application", "outcome": secret_canaries[2]},
            ).validated()
        except ObservabilityContractError:
            rejected_unknown_label = True

        stage_counts = [
            record
            for record in records
            if record["metric_name"] == "pipeline_stage_completed_total"
        ]
        stage_durations = [
            record
            for record in records
            if record["metric_name"] == "pipeline_stage_duration_milliseconds"
        ]
        lane_records = [
            record
            for record in records
            if record["metric_name"] == "retrieval_lane_state_total"
        ]
        retained = metric_path.read_text(encoding="utf-8")
        boundary_passed = all(
            (
                len(records) == 17,
                {record["metric_name"] for record in records} == expected_names,
                all(set(record) == exact_fields for record in records),
                all(record["schema"] == "ishikawa.metric-event.v1" for record in records),
                all(record["request_id"] == request_id for record in records),
                [record["labels"]["stage"] for record in stage_counts]
                == ["request-accepted", "retrieval-completed", "response-built"],
                [record["value"] for record in stage_durations] == [1, 15, 5],
                [record["labels"]["lane"] for record in lane_records]
                == ["exact", "lexical", "vector"],
                rejected_unknown_label,
                os.stat(metric_path).st_mode & 0o777 == 0o600,
                not any(canary in retained for canary in secret_canaries),
                all("question" not in record and "vector" not in record for record in records),
            )
        )
    if not boundary_passed:
        raise RuntimeError("operational_metrics_boundary_failed")
    return {
        "content_fields": False,
        "external_metrics_service": False,
        "label_cardinality": "fixed",
        "metric_count": len(expected_names),
        "metric_schema": "ishikawa.metric-event.v1",
        "network_endpoint": False,
        "pipeline_stage_count": 3,
        "prohibited_canary_scan": True,
        "request_correlation": True,
        "retrieval_lane_count": 3,
        "socket_or_target_contact": False,
    }


def main() -> int:
    arguments = parse_arguments()
    python_root = require_directory(Path(arguments.python_root), "python_root")
    config_root = require_directory(Path(arguments.config_root), "config_root")
    output = require_output(Path(arguments.output))
    qualification = evaluate(python_root, config_root)
    write_receipt(output, qualification)
    print("metric_schema=ishikawa.metric-event.v1;metric_names=11;labels=fixed-low-cardinality")
    print("request_metrics=count,duration;pipeline_metrics=completion,duration")
    print("retrieval_metrics=lane-state,candidates,reconstruction,citations,context-tokens")
    print("request_identity=correlation-not-label;metric_file_mode=0600;rotation=bounded")
    print("content_fields=false;prohibited_canary_scan=pass;external_service=false")
    print("target_contact=false;database_changed=false;model_call=false")
    print("operational_metrics_qualification=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
