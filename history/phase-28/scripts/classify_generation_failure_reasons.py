#!/usr/bin/env python3
"""Correlate content-free generation failure reasons with Script 134 probes."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import sys
from collections import Counter
from pathlib import Path
from typing import Any


_HEX = re.compile(r"^[0-9a-f]{64}$")
_REASON = re.compile(r"^[A-Z][A-Z0-9_]{0,95}$")
_FAMILIES = frozenset({"response_validation", "transport", "unclassified"})


class ClassificationError(RuntimeError):
    """Stable content-free diagnostic failure."""


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise ClassificationError(reason)


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, allow_nan=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")


def digest_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def read_json(path: Path, maximum_bytes: int) -> Any:
    require(path.is_absolute() and path.is_file() and not path.is_symlink(), "input_unsafe")
    metadata = path.stat()
    require(stat.S_ISREG(metadata.st_mode) and metadata.st_size <= maximum_bytes, "input_unsafe")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ClassificationError("input_invalid") from error


def load_probe_artifact(path: Path) -> dict[str, Any]:
    value = read_json(path, 1024 * 1024)
    require(
        isinstance(value, dict)
        and value.get("artifact_kind") == "ishikawa_t10_generation_reliability_diagnostic"
        and value.get("schema_version") == 1
        and value.get("case_id") == "R-006"
        and value.get("raw_content_retained") is False
        and isinstance(value.get("observations"), list)
        and len(value["observations"]) == 5,
        "probe_artifact_invalid",
    )
    return value


def load_failures(path: Path) -> list[dict[str, Any]]:
    require(path.is_absolute() and path.is_file() and not path.is_symlink(), "failure_log_unsafe")
    require(path.stat().st_size <= 1024 * 1024, "failure_log_unsafe")
    failures: list[dict[str, Any]] = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as error:
        raise ClassificationError("failure_log_invalid") from error
    for line in lines:
        require(len(line) <= 4096, "failure_record_too_large")
        try:
            value = json.loads(line)
        except json.JSONDecodeError as error:
            raise ClassificationError("failure_record_invalid") from error
        require(
            isinstance(value, dict)
            and set(value) == {
                "failure_family", "failure_ordinal", "reason_code", "schema", "turn_id"
            }
            and value["schema"] == "ishikawa.generation-failure-diagnostic.v1"
            and value["failure_family"] in _FAMILIES
            and type(value["failure_ordinal"]) is int
            and 1 <= value["failure_ordinal"] <= 2
            and isinstance(value["reason_code"], str)
            and _REASON.fullmatch(value["reason_code"]) is not None
            and isinstance(value["turn_id"], str)
            and _HEX.fullmatch(value["turn_id"]) is not None,
            "failure_record_invalid",
        )
        failures.append(value)
    return failures


def classify(probe_artifact: dict[str, Any], failures: list[dict[str, Any]]) -> dict[str, Any]:
    known_turns: set[str] = set()
    output_observations: list[dict[str, Any]] = []
    for observation in probe_artifact["observations"]:
        probe_id = observation.get("probe_id")
        require(
            isinstance(probe_id, str)
            and re.fullmatch(r"R-006-0[1-5]", probe_id) is not None
            and observation.get("status") in {"answered", "temporarily-unavailable"}
            and observation.get("classification") in {
                "answered_first_attempt", "answered_after_retry", "generation_failed_after_retry"
            },
            "probe_observation_invalid",
        )
        turn_id = digest_text(f"ishikawa-v1.2-diagnostic-turn:{probe_id}")
        known_turns.add(turn_id)
        matching = [item for item in failures if item["turn_id"] == turn_id]
        matching.sort(key=lambda item: item["failure_ordinal"])
        require(
            [item["failure_ordinal"] for item in matching]
            == list(range(1, len(matching) + 1)),
            "failure_ordinal_invalid",
        )
        expected_failures = {
            "answered_first_attempt": 0,
            "answered_after_retry": 1,
            "generation_failed_after_retry": 2,
        }[observation["classification"]]
        require(len(matching) == expected_failures, "failure_count_mismatch")
        output_observations.append(
            {
                "attempt_failures": [
                    {
                        "failure_family": item["failure_family"],
                        "failure_ordinal": item["failure_ordinal"],
                        "reason_code": item["reason_code"],
                    }
                    for item in matching
                ],
                "classification": observation["classification"],
                "probe_id": probe_id,
                "status": observation["status"],
            }
        )
    require(len(output_observations) == 5, "probe_count_invalid")
    require(all(item["turn_id"] in known_turns for item in failures), "unexpected_failure_identity")

    family_counts = Counter(
        failure["failure_family"]
        for observation in output_observations
        for failure in observation["attempt_failures"]
    )
    reason_counts = Counter(
        failure["reason_code"]
        for observation in output_observations
        for failure in observation["attempt_failures"]
    )
    active_families = {name for name, count in family_counts.items() if count}
    if not active_families:
        interpretation = "no_failure_reproduced"
    elif active_families == {"transport"}:
        interpretation = "transport_failure_observed"
    elif active_families == {"response_validation"}:
        interpretation = "response_validation_failure_observed"
    elif "unclassified" in active_families:
        interpretation = "unclassified_failure_observed"
    else:
        interpretation = "mixed_failure_families_observed"
    return {
        "artifact_kind": "ishikawa_generation_failure_reason_diagnostic",
        "observations": output_observations,
        "probe_artifact_sha256": hashlib.sha256(
            canonical_bytes(probe_artifact) + b"\n"
        ).hexdigest(),
        "raw_content_retained": False,
        "schema_version": 1,
        "summary": {
            "attempt_failure_count": sum(family_counts.values()),
            "failure_family_counts": {
                name: family_counts.get(name, 0) for name in sorted(_FAMILIES)
            },
            "interpretation": interpretation,
            "reason_code_counts": dict(sorted(reason_counts.items())),
        },
    }


def validate_artifact(value: Any) -> dict[str, Any]:
    require(
        isinstance(value, dict)
        and set(value) == {
            "artifact_kind", "observations", "probe_artifact_sha256",
            "raw_content_retained", "schema_version", "summary",
        }
        and value["artifact_kind"] == "ishikawa_generation_failure_reason_diagnostic"
        and value["schema_version"] == 1
        and value["raw_content_retained"] is False
        and isinstance(value["probe_artifact_sha256"], str)
        and _HEX.fullmatch(value["probe_artifact_sha256"]) is not None
        and isinstance(value["observations"], list)
        and len(value["observations"]) == 5
        and isinstance(value["summary"], dict),
        "artifact_invalid",
    )
    return value


def emit_summary(artifact: dict[str, Any]) -> None:
    summary = artifact["summary"]
    families = summary["failure_family_counts"]
    print(
        f"attempt_failures={summary['attempt_failure_count']};"
        f"transport={families['transport']};"
        f"response_validation={families['response_validation']};"
        f"unclassified={families['unclassified']}"
    )
    for reason, count in summary["reason_code_counts"].items():
        print(f"failure_reason={reason};count={count}")
    print(f"failure_interpretation={summary['interpretation']};raw_content_retained=false")


def run(arguments: argparse.Namespace) -> int:
    probe_path = Path(arguments.probe_artifact).resolve(strict=True)
    failure_path = Path(arguments.failure_log).resolve(strict=True)
    output = Path(arguments.output)
    require(output.is_absolute() and not output.exists() and not output.is_symlink(), "output_unsafe")
    probe_artifact = load_probe_artifact(probe_path)
    failures = load_failures(failure_path)
    artifact = validate_artifact(classify(probe_artifact, failures))
    payload = canonical_bytes(artifact) + b"\n"
    descriptor = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)
    emit_summary(artifact)
    print(f"diagnostic_artifact_sha256={hashlib.sha256(payload).hexdigest()};diagnostic_artifact_bytes={len(payload)}")
    print("generation_failure_reason_classification=pass")
    return 0


def validate(arguments: argparse.Namespace) -> int:
    artifact = validate_artifact(read_json(Path(arguments.artifact).resolve(strict=True), 1024 * 1024))
    emit_summary(artifact)
    print("generation_failure_reason_artifact=pass")
    return 0


def self_test() -> int:
    require(digest_text("x") == hashlib.sha256(b"x").hexdigest(), "self_test_digest_failed")
    observations = []
    classifications = (
        "answered_first_attempt",
        "answered_after_retry",
        "generation_failed_after_retry",
        "generation_failed_after_retry",
        "generation_failed_after_retry",
    )
    failures: list[dict[str, Any]] = []
    for index, classification in enumerate(classifications, start=1):
        probe_id = f"R-006-{index:02d}"
        observations.append(
            {
                "classification": classification,
                "probe_id": probe_id,
                "status": (
                    "temporarily-unavailable"
                    if classification == "generation_failed_after_retry"
                    else "answered"
                ),
            }
        )
        turn_id = digest_text(f"ishikawa-v1.2-diagnostic-turn:{probe_id}")
        failure_count = {
            "answered_first_attempt": 0,
            "answered_after_retry": 1,
            "generation_failed_after_retry": 2,
        }[classification]
        for ordinal in range(1, failure_count + 1):
            failures.append(
                {
                    "failure_family": "response_validation",
                    "failure_ordinal": ordinal,
                    "reason_code": "MODEL_OUTPUT_JSON_INVALID",
                    "schema": "ishikawa.generation-failure-diagnostic.v1",
                    "turn_id": turn_id,
                }
            )
    artifact = classify(
        {
            "artifact_kind": "ishikawa_t10_generation_reliability_diagnostic",
            "case_id": "R-006",
            "observations": observations,
            "raw_content_retained": False,
            "schema_version": 1,
            "summary": {},
        },
        failures,
    )
    require(
        artifact["summary"]["attempt_failure_count"] == 7
        and artifact["summary"]["failure_family_counts"]["response_validation"] == 7
        and artifact["summary"]["interpretation"]
        == "response_validation_failure_observed",
        "self_test_classification_failed",
    )
    print("generation_failure_reason_classifier_self_test=pass")
    return 0


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--run", action="store_true")
    mode.add_argument("--validate-artifact", action="store_true")
    mode.add_argument("--self-test", action="store_true")
    parser.add_argument("--probe-artifact")
    parser.add_argument("--failure-log")
    parser.add_argument("--output")
    parser.add_argument("--artifact")
    arguments = parser.parse_args()
    if arguments.run and not all((arguments.probe_artifact, arguments.failure_log, arguments.output)):
        raise ClassificationError("argument_missing")
    if arguments.validate_artifact and not arguments.artifact:
        raise ClassificationError("argument_missing")
    return arguments


def main() -> int:
    try:
        arguments = parse_arguments()
        if arguments.self_test:
            return self_test()
        if arguments.validate_artifact:
            return validate(arguments)
        return run(arguments)
    except ClassificationError as error:
        print(f"generation_failure_reason_classification=blocked;reason={error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("generation_failure_reason_classification=blocked;reason=interrupted", file=sys.stderr)
        return 130
    except Exception as error:
        print(
            f"generation_failure_reason_classification=blocked;reason=bounded_{type(error).__name__}",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
