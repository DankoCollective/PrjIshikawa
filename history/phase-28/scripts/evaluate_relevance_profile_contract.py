#!/usr/bin/env python3
"""Replay protected observations through the frozen relevance profile."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
from pathlib import Path
from typing import Any, NoReturn

from ishikawa.canonical import canonical_json_bytes
from ishikawa.relevance import (
    RelevanceMeasurement,
    evaluate_relevance,
    validate_relevance_profile,
)
from ishikawa.yaml_loader import load_restricted_yaml


SOURCE_IDS = tuple(f"R-{number:03d}" for number in range(1, 7)) + tuple(
    f"N-{number:03d}" for number in range(1, 7)
)
TARGET_IDS = tuple(f"C-{number:03d}" for number in range(1, 13))
HEX = re.compile(r"^[0-9a-f]{64}$")


class EvaluationError(RuntimeError):
    pass


def fail(reason: str) -> NoReturn:
    raise EvaluationError(reason)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def require_identity(path: Path, expected: str, maximum: int) -> None:
    if (
        HEX.fullmatch(expected or "") is None
        or not path.is_file()
        or path.is_symlink()
        or path.stat().st_size > maximum
        or sha256_file(path) != expected
    ):
        fail("source_identity_mismatch")


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail("invalid_json")


def write_artifact(path: Path, value: dict[str, Any]) -> str:
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(canonical_json_bytes(value) + b"\n")
    except OSError:
        fail("artifact_write_failed")
    return sha256_file(path)


def evaluate(arguments: argparse.Namespace) -> dict[str, Any]:
    require_identity(arguments.profile, arguments.expected_profile_sha256, 64 * 1024)
    require_identity(arguments.cases, arguments.expected_cases_sha256, 1024 * 1024)
    require_identity(
        arguments.observations, arguments.expected_observations_sha256, 32 * 1024 * 1024
    )
    if arguments.output.exists() or arguments.output.is_symlink() or not arguments.output.parent.is_dir():
        fail("output_path_invalid")

    policy = validate_relevance_profile(
        load_restricted_yaml(arguments.profile, label="relevance profile")
    )
    cases_document = load_json(arguments.cases)
    observations = load_json(arguments.observations)
    cases = cases_document.get("cases") if isinstance(cases_document, dict) else None
    observed_cases = observations.get("cases") if isinstance(observations, dict) else None
    if (
        not isinstance(cases, list)
        or tuple(case.get("case_id") for case in cases) != SOURCE_IDS
        or not isinstance(observed_cases, list)
        or tuple(case.get("case_id") for case in observed_cases) != TARGET_IDS
    ):
        fail("case_inventory_invalid")
    digest_input = dict(observations)
    stored_digest = digest_input.pop("observation_set_digest", None)
    expected_digest = hashlib.sha256(
        b"ishikawa.relevance-retrieval-observations.v1\x00"
        + canonical_json_bytes(digest_input)
    ).hexdigest()
    if stored_digest != expected_digest:
        fail("observation_set_digest_invalid")

    outcomes: list[dict[str, Any]] = []
    responsive_qualified = 0
    nonresponsive_insufficient = 0
    for source, observed in zip(cases, observed_cases, strict=True):
        support = observed.get("citable_evidence_support")
        measurements = support.get("measurements") if isinstance(support, dict) else None
        if not isinstance(measurements, list):
            fail("support_measurement_invalid")
        depth_three = [item for item in measurements if item.get("depth") == 3]
        if len(depth_three) != 1:
            fail("depth_three_measurement_invalid")
        item = depth_three[0]
        if item.get("supported_count") != len(item.get("supported_lexemes", [])) or item.get(
            "unsupported_count"
        ) != len(item.get("unsupported_lexemes", [])):
            fail("support_count_invalid")
        measurement = RelevanceMeasurement(
            question_lexemes=tuple(support.get("question_lexemes", [])),
            supported_lexemes=tuple(item.get("supported_lexemes", [])),
            unsupported_lexemes=tuple(item.get("unsupported_lexemes", [])),
            fused_chunk_count=item.get("fused_chunk_count"),
        )
        decision = evaluate_relevance(measurement, policy)
        expected_status = "qualified" if source.get("class") == "responsive" else "insufficient"
        if decision.status != expected_status:
            fail("protected_case_misclassified")
        responsive_qualified += int(expected_status == "qualified")
        nonresponsive_insufficient += int(expected_status == "insufficient")
        outcomes.append(
            {
                "case_id": source["case_id"],
                "expected_status": expected_status,
                "observed_status": decision.status,
                "question_lexeme_count": decision.question_lexeme_count,
                "supported_count": decision.supported_count,
            }
        )

    artifact = {
        "case_count": len(outcomes),
        "fused_depth": policy.fused_depth,
        "minimum_supported_denominator": policy.minimum_supported_denominator,
        "minimum_supported_numerator": policy.minimum_supported_numerator,
        "model_authority": False,
        "observation_set_digest": stored_digest,
        "outcomes": outcomes,
        "profile_identity": policy.digest,
        "purpose": "frozen_relevance_profile_qualification",
        "raw_text_retained": False,
        "retrieval_ranking_changed": False,
        "schema_version": 1,
    }
    artifact_sha256 = write_artifact(arguments.output, artifact)
    return {
        "artifact_sha256": artifact_sha256,
        "policy": policy,
        "responsive_qualified": responsive_qualified,
        "nonresponsive_insufficient": nonresponsive_insufficient,
        "observation_set_digest": stored_digest,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--expected-profile-sha256", required=True)
    parser.add_argument("--cases", type=Path, required=True)
    parser.add_argument("--expected-cases-sha256", required=True)
    parser.add_argument("--observations", type=Path, required=True)
    parser.add_argument("--expected-observations-sha256", required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    try:
        summary = evaluate(arguments)
    except (EvaluationError, KeyError, TypeError, ValueError, OSError) as error:
        reason = str(error) if isinstance(error, EvaluationError) else "bounded_runtime_failure"
        print(f"relevance_profile_contract_qualification=blocked;reason={reason}")
        return 1
    policy = summary["policy"]
    print(
        f"relevance_profile_identity={policy.digest};fused_depth={policy.fused_depth};"
        "minimum_support_numerator=3;minimum_support_denominator=5"
    )
    print(
        f"cases=12;responsive_qualified={summary['responsive_qualified']};"
        f"nonresponsive_insufficient={summary['nonresponsive_insufficient']};misclassified=0"
    )
    print("comparison=supported_count_times_5_greater_than_or_equal_question_count_times_3")
    print("retrieval_ranking_changed=false;exact_reference_routing=preserved;model_authority=false")
    print(f"observation_set_digest={summary['observation_set_digest']}")
    print(f"qualification_artifact_sha256={summary['artifact_sha256']};raw_text_retained=false")
    print("relevance_profile_contract_qualification=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
