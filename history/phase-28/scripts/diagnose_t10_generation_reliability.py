#!/usr/bin/env python3
"""Probe one synthetic API case and retain only content-free stage evidence."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import re
import stat
import sys
import time
from pathlib import Path
from types import ModuleType
from typing import Any, Mapping, Sequence


PROBE_COUNT = 5
CASE_ID = "R-006"
EXPECTED_DISPLAY_NAME = "Synthetic Operations Control 2002"
EXPECTED_PAGE = 1
LOG_NAME = re.compile(r"^(retrieval|metrics)\.jsonl(?:\.[1-9][0-9]*)?$")
MAXIMUM_LOG_BYTES = 64 * 1024 * 1024
LOG_COMPLETION_TIMEOUT_SECONDS = 10.0
LOG_COMPLETION_POLL_SECONDS = 0.1


class DiagnosticError(RuntimeError):
    """Stable, content-free diagnostic failure."""


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise DiagnosticError(reason)


def digest_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, allow_nan=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")


def load_contract(path: Path) -> ModuleType:
    require(path.is_absolute() and path.is_file() and not path.is_symlink(), "contract_unsafe")
    specification = importlib.util.spec_from_file_location("ishikawa_diagnostic_contract", path)
    require(specification is not None and specification.loader is not None, "contract_load_failed")
    module = importlib.util.module_from_spec(specification)
    sys.modules[specification.name] = module
    try:
        specification.loader.exec_module(module)
    except Exception as error:
        raise DiagnosticError("contract_load_failed") from error
    for name in ("_loopback_chat_endpoint", "_post_json", "_request", "_validate_readiness", "_validate_response"):
        require(callable(getattr(module, name, None)), "contract_interface_invalid")
    return module


def load_case(path: Path) -> dict[str, Any]:
    require(path.is_absolute() and path.is_file() and not path.is_symlink(), "case_set_unsafe")
    require(path.stat().st_size <= 1024 * 1024, "case_set_too_large")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise DiagnosticError("case_set_invalid") from error
    require(
        isinstance(value, dict)
        and value.get("artifact_kind") == "ishikawa_retrieval_tuning_cases"
        and value.get("schema_version") == 2
        and value.get("synthetic_content_only") is True
        and isinstance(value.get("cases"), list)
        and len(value["cases"]) == 13,
        "case_set_contract_invalid",
    )
    selected = [item for item in value["cases"] if isinstance(item, dict) and item.get("case_id") == CASE_ID]
    require(len(selected) == 1, "diagnostic_case_missing")
    case = selected[0]
    require(
        set(case) == {"case_id", "class", "expected_status", "question", "required_evidence"}
        and case["class"] == "responsive"
        and case["expected_status"] == "answered"
        and isinstance(case["question"], str)
        and case["question"].strip() == case["question"]
        and case["required_evidence"]
        == [{"display_name": EXPECTED_DISPLAY_NAME, "page": EXPECTED_PAGE}],
        "diagnostic_case_contract_invalid",
    )
    return case


def log_generation_order(name: str, prefix: str) -> tuple[int, int]:
    """Return an oldest-to-current order for one retained JSONL name."""

    base_name = f"{prefix}.jsonl"
    if name == base_name:
        return (1, 0)
    suffix = name.removeprefix(f"{base_name}.")
    require(suffix.isdigit() and int(suffix) >= 1, "log_generation_invalid")
    # Higher suffixes are older. The unnumbered file is always current.
    return (0, -int(suffix))


def read_records(log_root: Path, prefix: str) -> list[dict[str, Any]]:
    require(log_root.is_dir() and not log_root.is_symlink(), "log_root_unsafe")
    candidates = [
        path for path in log_root.iterdir()
        if LOG_NAME.fullmatch(path.name) and path.name.startswith(prefix)
    ]
    candidates.sort(key=lambda path: log_generation_order(path.name, prefix))
    total_bytes = 0
    records: list[dict[str, Any]] = []
    for generation_index, path in enumerate(candidates):
        metadata = path.lstat()
        require(stat.S_ISREG(metadata.st_mode), "log_file_unsafe")
        total_bytes += metadata.st_size
        require(total_bytes <= MAXIMUM_LOG_BYTES, "log_input_too_large")
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except (OSError, UnicodeError) as error:
            raise DiagnosticError("log_input_invalid") from error
        for line_number, line in enumerate(lines, start=1):
            require(len(line) <= 65536, "log_record_too_large")
            try:
                value = json.loads(line)
            except json.JSONDecodeError as error:
                raise DiagnosticError("log_record_invalid") from error
            require(isinstance(value, dict), "log_record_invalid")
            value["_source_order"] = (generation_index, line_number)
            records.append(value)
    return records


def classify_trace(status: str, stages: Sequence[str]) -> str:
    require(stages and stages[0] == "request-accepted", "stage_trace_invalid")
    retried = "generation-retry" in stages
    if status == "answered":
        require(stages[-1] == "response-built", "answered_trace_invalid")
        return "answered_after_retry" if retried else "answered_first_attempt"
    if status == "temporarily-unavailable":
        require(stages[-1] == "dependency-unavailable", "dependency_trace_invalid")
        return "generation_failed_after_retry" if retried else "dependency_failed_without_generation_retry"
    require(stages[-1] == "internal-failure", "internal_trace_invalid")
    return "internal_failure"


def terminal_stage(status: str) -> str:
    if status == "answered":
        return "response-built"
    if status == "temporarily-unavailable":
        return "dependency-unavailable"
    if status == "internal-error":
        return "internal-failure"
    raise DiagnosticError("probe_status_invalid")


def stage_trace_for_request(
    request_id: str, metrics_records: Sequence[dict[str, Any]]
) -> list[str]:
    stages = [
        item for item in metrics_records
        if item.get("request_id") == request_id
        and item.get("metric_name") == "pipeline_stage_completed_total"
        and item.get("value") == 1
        and isinstance(item.get("labels"), dict)
        and isinstance(item["labels"].get("stage"), str)
    ]
    # The protected writer's append order is the authoritative stage sequence.
    # Wall-clock timestamps are evidence, not sequence numbers: several events
    # can share a millisecond and the host clock can be adjusted while running.
    stages.sort(key=lambda item: item["_source_order"])
    return [item["labels"]["stage"] for item in stages]


def observation_from_logs(
    probe: dict[str, Any], retrieval_records: Sequence[dict[str, Any]], metrics_records: Sequence[dict[str, Any]]
) -> dict[str, Any]:
    request_id = probe["request_id"]
    outcomes = [
        item for item in retrieval_records
        if item.get("request_id") == request_id
        and item.get("component") == "retrieval-api"
        and item.get("stage") == "http-response"
    ]
    require(len(outcomes) == 1, "request_outcome_missing_or_ambiguous")
    stage_trace = stage_trace_for_request(request_id, metrics_records)
    classification = classify_trace(probe["status"], stage_trace)
    outcome = outcomes[0]
    require(outcome.get("http_status") == 200, "http_status_invalid")
    return {
        **probe,
        "classification": classification,
        "operational_outcome": outcome.get("outcome"),
        "retry_observed": "generation-retry" in stage_trace,
        "stage_trace": stage_trace,
    }


def wait_for_observations(
    log_root: Path, probes: Sequence[dict[str, Any]]
) -> list[dict[str, Any]]:
    """Wait until protected logging has appended every terminal stage."""

    deadline = time.monotonic() + LOG_COMPLETION_TIMEOUT_SECONDS
    while True:
        retrieval_records = read_records(log_root, "retrieval")
        metrics_records = read_records(log_root, "metrics")
        complete = True
        for probe in probes:
            outcomes = [
                item for item in retrieval_records
                if item.get("request_id") == probe["request_id"]
                and item.get("component") == "retrieval-api"
                and item.get("stage") == "http-response"
            ]
            require(len(outcomes) <= 1, "request_outcome_ambiguous")
            trace = stage_trace_for_request(probe["request_id"], metrics_records)
            if len(outcomes) != 1 or not trace or trace[-1] != terminal_stage(probe["status"]):
                complete = False
                break
        if complete:
            return [
                observation_from_logs(probe, retrieval_records, metrics_records)
                for probe in probes
            ]
        if time.monotonic() >= deadline:
            raise DiagnosticError("stage_trace_capture_timeout")
        time.sleep(LOG_COMPLETION_POLL_SECONDS)


def summarize(observations: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    classifications = [item["classification"] for item in observations]
    answered = sum(item["status"] == "answered" for item in observations)
    unavailable = sum(item["status"] == "temporarily-unavailable" for item in observations)
    internal = sum(item["status"] == "internal-error" for item in observations)
    retried = sum(item["retry_observed"] for item in observations)
    failed_after_retry = classifications.count("generation_failed_after_retry")
    other_dependency = classifications.count("dependency_failed_without_generation_retry")
    if failed_after_retry:
        interpretation = "single_retry_insufficient_observed"
    elif other_dependency or internal:
        interpretation = "non_generation_or_internal_failure_observed"
    elif retried:
        interpretation = "single_retry_recovery_observed"
    else:
        interpretation = "no_failure_reproduced"
    return {
        "answered_count": answered,
        "generation_failed_after_retry_count": failed_after_retry,
        "generation_retried_count": retried,
        "internal_error_count": internal,
        "interpretation": interpretation,
        "non_generation_dependency_failure_count": other_dependency,
        "probe_count": len(observations),
        "temporarily_unavailable_count": unavailable,
    }


def validate_artifact(value: Any) -> dict[str, Any]:
    require(
        isinstance(value, dict)
        and set(value) == {"artifact_kind", "case_id", "observations", "raw_content_retained", "schema_version", "summary"}
        and value["artifact_kind"] == "ishikawa_t10_generation_reliability_diagnostic"
        and value["schema_version"] == 1
        and value["case_id"] == CASE_ID
        and value["raw_content_retained"] is False
        and isinstance(value["observations"], list)
        and len(value["observations"]) == PROBE_COUNT,
        "artifact_contract_invalid",
    )
    require(value["summary"] == summarize(value["observations"]), "artifact_summary_invalid")
    return value["summary"]


def self_test() -> int:
    names = ["metrics.jsonl", "metrics.jsonl.1", "metrics.jsonl.4", "metrics.jsonl.2"]
    require(
        sorted(names, key=lambda name: log_generation_order(name, "metrics"))
        == ["metrics.jsonl.4", "metrics.jsonl.2", "metrics.jsonl.1", "metrics.jsonl"],
        "self_test_log_order_failed",
    )
    require(classify_trace("answered", ("request-accepted", "response-built")) == "answered_first_attempt", "self_test_first_attempt_failed")
    require(classify_trace("answered", ("request-accepted", "generation-retry", "response-built")) == "answered_after_retry", "self_test_retry_recovery_failed")
    require(classify_trace("temporarily-unavailable", ("request-accepted", "generation-retry", "dependency-unavailable")) == "generation_failed_after_retry", "self_test_retry_failure_failed")
    require(terminal_stage("answered") == "response-built", "self_test_answered_terminal_failed")
    require(
        terminal_stage("temporarily-unavailable") == "dependency-unavailable",
        "self_test_dependency_terminal_failed",
    )
    require(terminal_stage("internal-error") == "internal-failure", "self_test_internal_terminal_failed")
    print("t10_generation_reliability_diagnostic_self_test=pass")
    return 0


def run(arguments: argparse.Namespace) -> int:
    contract = load_contract(Path(arguments.contract_helper).resolve(strict=True))
    case = load_case(Path(arguments.cases).resolve(strict=True))
    product_root = Path(arguments.product_root).resolve(strict=True)
    output = Path(arguments.output)
    require(product_root.is_dir() and not product_root.is_symlink(), "product_root_unsafe")
    require(output.is_absolute() and not output.exists() and not output.is_symlink(), "output_unsafe")
    endpoint = contract._loopback_chat_endpoint(arguments.endpoint)
    contract._validate_readiness(endpoint)
    probes: list[dict[str, Any]] = []
    for index in range(1, PROBE_COUNT + 1):
        probe_id = f"{CASE_ID}-{index:02d}"
        conversation_id = digest_text(f"ishikawa-v1.2-diagnostic-conversation:{probe_id}")
        turn_id = digest_text(f"ishikawa-v1.2-diagnostic-turn:{probe_id}")
        request = contract._request(case["question"], conversation_id, turn_id)
        started = time.monotonic_ns()
        response = contract._post_json(endpoint, request)
        elapsed = max(1, (time.monotonic_ns() - started + 999_999) // 1_000_000)
        metrics = contract._validate_response(
            response,
            conversation_id=conversation_id,
            turn_id=turn_id,
            required_evidence=case["required_evidence"],
        )
        status = metrics["status"]
        require(status in {"answered", "temporarily-unavailable", "internal-error"}, "probe_status_invalid")
        if status == "answered":
            require(
                metrics["required_evidence_returned_count"] == 1
                and metrics["required_evidence_cited_count"] == 1,
                "answered_evidence_invalid",
            )
        probes.append(
            {
                "elapsed_milliseconds": elapsed,
                "probe_id": probe_id,
                "request_id": response["request_id"],
                "required_evidence_cited_count": metrics["required_evidence_cited_count"],
                "required_evidence_returned_count": metrics["required_evidence_returned_count"],
                "status": status,
            }
        )
        print(f"probe_result={probe_id};status={status};elapsed_milliseconds={elapsed}", flush=True)

    log_root = product_root / "state" / "logs"
    observations = wait_for_observations(log_root, probes)
    summary = summarize(observations)
    artifact = {
        "artifact_kind": "ishikawa_t10_generation_reliability_diagnostic",
        "case_id": CASE_ID,
        "observations": observations,
        "raw_content_retained": False,
        "schema_version": 1,
        "summary": summary,
    }
    validate_artifact(artifact)
    payload = canonical_bytes(artifact) + b"\n"
    descriptor = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)
    print(
        f"probe_count={summary['probe_count']};answered={summary['answered_count']};"
        f"temporarily_unavailable={summary['temporarily_unavailable_count']};"
        f"generation_retried={summary['generation_retried_count']};"
        f"generation_failed_after_retry={summary['generation_failed_after_retry_count']};"
        f"other_dependency_failures={summary['non_generation_dependency_failure_count']};"
        f"internal_errors={summary['internal_error_count']}"
    )
    print(f"diagnostic_interpretation={summary['interpretation']};raw_content_retained=false")
    print(f"diagnostic_artifact_sha256={hashlib.sha256(payload).hexdigest()};diagnostic_artifact_bytes={len(payload)}")
    print("t10_generation_reliability_diagnostic=pass")
    return 0


def validate_mode(arguments: argparse.Namespace) -> int:
    path = Path(arguments.artifact).resolve(strict=True)
    require(path.is_file() and not path.is_symlink(), "artifact_unsafe")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise DiagnosticError("artifact_invalid") from error
    summary = validate_artifact(value)
    print(
        f"t10_generation_reliability_artifact=pass;probes={summary['probe_count']};"
        f"answered={summary['answered_count']};temporarily_unavailable={summary['temporarily_unavailable_count']};"
        f"interpretation={summary['interpretation']}"
    )
    return 0


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--self-test", action="store_true")
    mode.add_argument("--run", action="store_true")
    mode.add_argument("--validate-artifact", action="store_true")
    parser.add_argument("--contract-helper")
    parser.add_argument("--cases")
    parser.add_argument("--product-root")
    parser.add_argument("--endpoint")
    parser.add_argument("--output")
    parser.add_argument("--artifact")
    arguments = parser.parse_args()
    if arguments.run and not all((arguments.contract_helper, arguments.cases, arguments.product_root, arguments.endpoint, arguments.output)):
        raise DiagnosticError("argument_missing")
    if arguments.validate_artifact and not arguments.artifact:
        raise DiagnosticError("argument_missing")
    return arguments


def main() -> int:
    try:
        arguments = parse_arguments()
        if arguments.self_test:
            return self_test()
        if arguments.validate_artifact:
            return validate_mode(arguments)
        return run(arguments)
    except DiagnosticError as error:
        print(f"t10_generation_reliability_diagnostic=blocked;reason={error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("t10_generation_reliability_diagnostic=blocked;reason=interrupted", file=sys.stderr)
        return 130
    except Exception as error:
        print(f"t10_generation_reliability_diagnostic=blocked;reason=bounded_{type(error).__name__}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
