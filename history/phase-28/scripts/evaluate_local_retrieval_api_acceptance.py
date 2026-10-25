#!/usr/bin/env python3
"""Evaluate Ishikawa's complete local Retrieval API over the v1.1 case set.

Role:
  Send each checksum-bound synthetic case through the live loopback API,
  validate the full response envelope with the accepted response-contract
  helper, and measure exact expected-status acceptance by case class.

Mental model:
  Ranking has already been qualified separately. This evaluator proves the
  orchestration above ranking: scope, abstention, clarification, sufficiency,
  grounded generation, citations, and dependency availability. It changes no
  database, configuration, service, model, or package state.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import platform
import re
import socket
import sys
import time
from pathlib import Path
from types import ModuleType
from typing import Any, Mapping, Sequence


ARTIFACT_KIND = "ishikawa_retrieval_api_acceptance"
EXPECTED_CASE_CLASSES = {
    "responsive": "answered",
    "nonresponsive": "insufficient-evidence",
    "broad-navigation": "clarification-required",
}
DEPENDENCY_FAILURE_STATUSES = frozenset({"temporarily-unavailable", "internal-error"})
CASE_ID = re.compile(r"^[A-Z][A-Z0-9-]{1,31}$")
HEX_IDENTITY = re.compile(r"^[0-9a-f]{64}$")


class AcceptanceError(ValueError):
    """Stable failure that never includes question, answer, or excerpt text."""


def main(arguments: Sequence[str] | None = None) -> int:
    """Select one validation mode and emit only bounded status metadata."""

    parser = argparse.ArgumentParser(allow_abbrev=False)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--run", action="store_true")
    mode.add_argument("--self-test", action="store_true")
    mode.add_argument("--validate-cases", action="store_true")
    mode.add_argument("--validate-artifact", action="store_true")
    parser.add_argument("--contract-helper", type=Path, required=True)
    parser.add_argument("--endpoint")
    parser.add_argument("--cases", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--artifact", type=Path)
    parser.add_argument("--expected-hostname")
    parser.add_argument("--expected-os-version")
    parser.add_argument("--expected-architecture")
    values = parser.parse_args(arguments)
    try:
        contract = _load_contract_helper(values.contract_helper)
        if values.self_test:
            _require_absent(
                values,
                "endpoint",
                "cases",
                "output",
                "artifact",
                "expected_hostname",
                "expected_os_version",
                "expected_architecture",
            )
            return _self_test(contract)
        if values.validate_cases:
            _require_present(values, "cases")
            _require_absent(
                values,
                "endpoint",
                "output",
                "artifact",
                "expected_hostname",
                "expected_os_version",
                "expected_architecture",
            )
            case_set = _load_case_set(values.cases)
            print(
                "retrieval_api_case_set=pass;schema_version=2;"
                f"cases={len(case_set['cases'])};responsive=6;"
                "nonresponsive=6;broad_navigation=1;required_evidence=13"
            )
            return 0
        if values.validate_artifact:
            _require_present(values, "artifact")
            _require_absent(
                values,
                "endpoint",
                "cases",
                "output",
                "expected_hostname",
                "expected_os_version",
                "expected_architecture",
            )
            artifact = _load_json(values.artifact, "artifact", require_private=True)
            summary = _validate_artifact(artifact, contract)
            print(_summary_marker("retrieval_api_artifact", summary))
            return 0
        _require_present(
            values,
            "endpoint",
            "cases",
            "output",
            "expected_hostname",
            "expected_os_version",
            "expected_architecture",
        )
        _require_absent(values, "artifact")
        return _run(
            contract=contract,
            endpoint=values.endpoint,
            cases_path=values.cases,
            output=values.output,
            expected_hostname=values.expected_hostname,
            expected_os_version=values.expected_os_version,
            expected_architecture=values.expected_architecture,
        )
    except AcceptanceError as error:
        print(f"local_retrieval_api_acceptance=blocked;reason={error}")
        return 1
    except Exception:
        print("local_retrieval_api_acceptance=blocked;reason=unexpected_failure")
        return 1


def _run(
    *,
    contract: ModuleType,
    endpoint: str,
    cases_path: Path,
    output: Path,
    expected_hostname: str,
    expected_os_version: str,
    expected_architecture: str,
) -> int:
    """Call the live API once per case and retain a private synthetic artifact."""

    endpoint = contract._loopback_chat_endpoint(endpoint)
    case_set = _load_case_set(cases_path)
    target = _validate_target(
        expected_hostname,
        expected_os_version,
        expected_architecture,
    )
    contract._validate_readiness(endpoint)

    observations: list[dict[str, Any]] = []
    for case in case_set["cases"]:
        case_id = case["case_id"]
        print(f"case_start={case_id}", flush=True)
        conversation_id, turn_id = _request_identities(case_id)
        request_value = contract._request(case["question"], conversation_id, turn_id)
        request_started_ns = time.monotonic_ns()
        response_value = contract._post_json(endpoint, request_value)
        elapsed_milliseconds = max(
            1,
            (time.monotonic_ns() - request_started_ns + 999_999) // 1_000_000,
        )
        metrics = contract._validate_response(
            response_value,
            conversation_id=conversation_id,
            turn_id=turn_id,
            required_evidence=case["required_evidence"],
        )
        metrics["elapsed_milliseconds"] = elapsed_milliseconds
        observations.append(
            {"case": case, "metrics": metrics, "response": response_value}
        )
        print(
            f"case_result={case_id};status={metrics['status']};"
            f"expected_status={case['expected_status']};"
            f"elapsed_milliseconds={elapsed_milliseconds};"
            f"sources={metrics['source_group_count']};"
            f"cited_sources={metrics['cited_source_group_count']}",
            flush=True,
        )

    summary = _summarize(observations)
    artifact = {
        "artifact_kind": ARTIFACT_KIND,
        "case_set_identity": _canonical_digest(case_set),
        "cases": observations,
        "endpoint": endpoint,
        "raw_synthetic_responses_retained": True,
        "schema_version": 1,
        "summary": summary,
        "synthetic_content_only": True,
        "target": target,
    }
    _validate_artifact(artifact, contract)
    contract._atomic_private_json(output, artifact)
    print(
        f"target_hostname={target['hostname']};os_id={target['os_id']};"
        f"os_version={target['os_version']};architecture={target['architecture']}"
    )
    print(_summary_marker("retrieval_api_acceptance", summary))
    print(
        f"full_api_gate={summary['acceptance_gate']};"
        f"responsive_answered={summary['responsive_answered_count']}/6;"
        f"nonresponsive_abstained={summary['nonresponsive_insufficient_count']}/6;"
        f"broad_clarification={summary['broad_clarification_count']}/1;"
        f"dependency_failures={summary['dependency_failure_count']}"
    )
    print(
        "raw_synthetic_content_retained=true;credential_values_retained=false;"
        "database_write=false;runtime_changed=false"
    )
    print("local_retrieval_api_acceptance=pass")
    return 0


def _load_contract_helper(path: Path) -> ModuleType:
    if not path.is_absolute() or not path.is_file() or path.is_symlink():
        raise AcceptanceError("contract_helper_path_invalid")
    specification = importlib.util.spec_from_file_location(
        "ishikawa_accepted_response_contract",
        path,
    )
    if specification is None or specification.loader is None:
        raise AcceptanceError("contract_helper_load_failed")
    module = importlib.util.module_from_spec(specification)
    sys.modules[specification.name] = module
    try:
        specification.loader.exec_module(module)
    except Exception:
        raise AcceptanceError("contract_helper_load_failed") from None
    for name in (
        "_atomic_private_json",
        "_loopback_chat_endpoint",
        "_post_json",
        "_request",
        "_validate_readiness",
        "_validate_response",
    ):
        if not callable(getattr(module, name, None)):
            raise AcceptanceError("contract_helper_interface_invalid")
    return module


def _load_case_set(path: Path) -> dict[str, Any]:
    return _normalize_case_set(_load_json(path, "case_set", require_private=False))


def _normalize_case_set(value: Any) -> dict[str, Any]:
    """Validate and canonicalize the complete in-memory tuning case set."""

    if (
        not isinstance(value, Mapping)
        or set(value) != {"artifact_kind", "cases", "schema_version", "synthetic_content_only"}
        or value["artifact_kind"] != "ishikawa_retrieval_tuning_cases"
        or value["schema_version"] != 2
        or value["synthetic_content_only"] is not True
        or not isinstance(value["cases"], list)
        or len(value["cases"]) != 13
    ):
        raise AcceptanceError("case_set_contract_invalid")

    normalized: list[dict[str, Any]] = []
    seen: set[str] = set()
    class_counts = {name: 0 for name in EXPECTED_CASE_CLASSES}
    for raw_case in value["cases"]:
        if not isinstance(raw_case, Mapping) or set(raw_case) != {
            "case_id",
            "class",
            "expected_status",
            "question",
            "required_evidence",
        }:
            raise AcceptanceError("case_fields_invalid")
        case_id = raw_case["case_id"]
        case_class = raw_case["class"]
        expected_status = raw_case["expected_status"]
        question = raw_case["question"]
        requirements = raw_case["required_evidence"]
        if (
            not isinstance(case_id, str)
            or CASE_ID.fullmatch(case_id) is None
            or case_id in seen
            or case_class not in EXPECTED_CASE_CLASSES
            or expected_status != EXPECTED_CASE_CLASSES[case_class]
            or not isinstance(question, str)
            or not question
            or question != question.strip()
            or len(question) > 16384
            or not isinstance(requirements, list)
            or len(requirements) > 20
        ):
            raise AcceptanceError("case_contract_invalid")
        seen.add(case_id)
        class_counts[case_class] += 1
        normalized_requirements: list[dict[str, Any]] = []
        requirement_identities: set[tuple[str, int]] = set()
        for raw_requirement in requirements:
            if not isinstance(raw_requirement, Mapping) or set(raw_requirement) != {
                "display_name",
                "page",
            }:
                raise AcceptanceError("case_evidence_invalid")
            display_name = raw_requirement["display_name"]
            page = raw_requirement["page"]
            identity = (display_name, page)
            if (
                not isinstance(display_name, str)
                or not display_name
                or display_name != display_name.strip()
                or len(display_name) > 512
                or type(page) is not int
                or page < 1
                or identity in requirement_identities
            ):
                raise AcceptanceError("case_evidence_invalid")
            requirement_identities.add(identity)
            normalized_requirements.append({"display_name": display_name, "page": page})
        normalized.append(
            {
                "case_id": case_id,
                "class": case_class,
                "expected_status": expected_status,
                "question": question,
                "required_evidence": normalized_requirements,
            }
        )
    if class_counts != {"responsive": 6, "nonresponsive": 6, "broad-navigation": 1}:
        raise AcceptanceError("case_class_counts_invalid")
    if sum(len(case["required_evidence"]) for case in normalized) != 13:
        raise AcceptanceError("case_evidence_count_invalid")
    return {
        "artifact_kind": "ishikawa_retrieval_tuning_cases",
        "cases": normalized,
        "schema_version": 2,
        "synthetic_content_only": True,
    }


def _summarize(observations: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    expected_status_matches = sum(
        observation["case"]["expected_status"] == observation["metrics"]["status"]
        for observation in observations
    )
    responsive_answered = sum(
        observation["case"]["class"] == "responsive"
        and observation["metrics"]["status"] == "answered"
        for observation in observations
    )
    nonresponsive_insufficient = sum(
        observation["case"]["class"] == "nonresponsive"
        and observation["metrics"]["status"] == "insufficient-evidence"
        for observation in observations
    )
    broad_clarification = sum(
        observation["case"]["class"] == "broad-navigation"
        and observation["metrics"]["status"] == "clarification-required"
        for observation in observations
    )
    dependency_failures = sum(
        observation["metrics"]["status"] in DEPENDENCY_FAILURE_STATUSES
        for observation in observations
    )
    gate = (
        "pass"
        if len(observations) == 13
        and expected_status_matches == 13
        and responsive_answered == 6
        and nonresponsive_insufficient == 6
        and broad_clarification == 1
        and dependency_failures == 0
        else "not_met"
    )
    metrics = [observation["metrics"] for observation in observations]
    return {
        "acceptance_gate": gate,
        "broad_clarification_count": broad_clarification,
        "case_count": len(observations),
        "contract_valid_count": len(observations),
        "dependency_failure_count": dependency_failures,
        "expected_status_match_count": expected_status_matches,
        "maximum_elapsed_milliseconds": max(metric["elapsed_milliseconds"] for metric in metrics),
        "nonresponsive_insufficient_count": nonresponsive_insufficient,
        "required_evidence_cited_count": sum(metric["required_evidence_cited_count"] for metric in metrics),
        "required_evidence_count": sum(metric["required_evidence_count"] for metric in metrics),
        "required_evidence_returned_count": sum(metric["required_evidence_returned_count"] for metric in metrics),
        "responsive_answered_count": responsive_answered,
        "total_elapsed_milliseconds": sum(metric["elapsed_milliseconds"] for metric in metrics),
    }


def _validate_artifact(value: Any, contract: ModuleType) -> Mapping[str, Any]:
    if not isinstance(value, Mapping) or set(value) != {
        "artifact_kind",
        "case_set_identity",
        "cases",
        "endpoint",
        "raw_synthetic_responses_retained",
        "schema_version",
        "summary",
        "synthetic_content_only",
        "target",
    }:
        raise AcceptanceError("artifact_fields_invalid")
    if (
        value["artifact_kind"] != ARTIFACT_KIND
        or value["schema_version"] != 1
        or value["synthetic_content_only"] is not True
        or value["raw_synthetic_responses_retained"] is not True
        or not isinstance(value["case_set_identity"], str)
        or HEX_IDENTITY.fullmatch(value["case_set_identity"]) is None
    ):
        raise AcceptanceError("artifact_contract_invalid")
    contract._loopback_chat_endpoint(value["endpoint"])
    target = value["target"]
    if (
        not isinstance(target, Mapping)
        or set(target) != {"architecture", "hostname", "os_id", "os_version"}
        or target["architecture"] not in {"amd64", "aarch64"}
        or target["os_id"] != "ubuntu"
        or not isinstance(target["hostname"], str)
        or re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]*", target["hostname"]) is None
        or not isinstance(target["os_version"], str)
        or re.fullmatch(r"[0-9]{2}\.[0-9]{2}", target["os_version"]) is None
    ):
        raise AcceptanceError("artifact_target_invalid")
    observations = value["cases"]
    if not isinstance(observations, list) or len(observations) != 13:
        raise AcceptanceError("artifact_cases_invalid")
    case_set = _load_case_set_value(
        {
            "artifact_kind": "ishikawa_retrieval_tuning_cases",
            "cases": [observation.get("case") for observation in observations],
            "schema_version": 2,
            "synthetic_content_only": True,
        }
    )
    if value["case_set_identity"] != _canonical_digest(case_set):
        raise AcceptanceError("artifact_case_set_identity_invalid")
    for observation, case in zip(observations, case_set["cases"], strict=True):
        if not isinstance(observation, Mapping) or set(observation) != {"case", "metrics", "response"}:
            raise AcceptanceError("artifact_case_invalid")
        conversation_id, turn_id = _request_identities(case["case_id"])
        expected_metrics = contract._validate_response(
            observation["response"],
            conversation_id=conversation_id,
            turn_id=turn_id,
            required_evidence=case["required_evidence"],
        )
        observed_metrics = observation["metrics"]
        if not isinstance(observed_metrics, Mapping):
            raise AcceptanceError("artifact_metrics_invalid")
        without_latency = dict(observed_metrics)
        elapsed = without_latency.pop("elapsed_milliseconds", None)
        if type(elapsed) is not int or not 1 <= elapsed <= 3_600_000 or without_latency != expected_metrics:
            raise AcceptanceError("artifact_metrics_invalid")
    expected_summary = _summarize(observations)
    if value["summary"] != expected_summary:
        raise AcceptanceError("artifact_summary_invalid")
    return expected_summary


def _load_case_set_value(value: Any) -> dict[str, Any]:
    """Run the same case validation for an in-memory artifact projection."""

    return _normalize_case_set(value)


def _validate_target(hostname: str, os_version: str, architecture: str) -> dict[str, str]:
    if (
        not isinstance(hostname, str)
        or re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]*", hostname) is None
        or re.fullmatch(r"[0-9]{2}\.[0-9]{2}", os_version or "") is None
        or architecture not in {"amd64", "aarch64"}
    ):
        raise AcceptanceError("target_expectation_invalid")
    actual_hostname = socket.gethostname().split(".", maxsplit=1)[0]
    os_release = _read_os_release()
    actual_architecture = platform.machine()
    actual_architecture = "amd64" if actual_architecture == "x86_64" else actual_architecture
    if (
        actual_hostname != hostname
        or os_release.get("ID") != "ubuntu"
        or os_release.get("VERSION_ID") != os_version
        or actual_architecture != architecture
    ):
        raise AcceptanceError("target_identity_mismatch")
    return {
        "architecture": architecture,
        "hostname": hostname,
        "os_id": "ubuntu",
        "os_version": os_version,
    }


def _read_os_release() -> dict[str, str]:
    try:
        lines = Path("/etc/os-release").read_text(encoding="utf-8", errors="strict").splitlines()
    except (OSError, UnicodeError):
        raise AcceptanceError("os_release_unreadable") from None
    values: dict[str, str] = {}
    for line in lines:
        if "=" in line:
            name, raw_value = line.split("=", maxsplit=1)
            values[name] = raw_value.strip().strip('"')
    return values


def _self_test(contract: ModuleType) -> int:
    """Exercise all three accepted statuses and complete artifact replay."""

    cases: list[dict[str, Any]] = []
    observations: list[dict[str, Any]] = []
    for case_index in range(1, 14):
        if case_index <= 6:
            case_id = f"R-{case_index:03d}"
            case_class = "responsive"
            expected_status = "answered"
            requirement_count = (3, 3, 2, 2, 2, 1)[case_index - 1]
            requirements = [
                {
                    "display_name": "Synthetic source" if item_index == 0 else f"Synthetic source {item_index + 1}",
                    "page": item_index + 1,
                }
                for item_index in range(requirement_count)
            ]
        elif case_index <= 12:
            case_id = f"N-{case_index - 6:03d}"
            case_class = "nonresponsive"
            expected_status = "insufficient-evidence"
            requirements = []
        else:
            case_id = "B-001"
            case_class = "broad-navigation"
            expected_status = "clarification-required"
            requirements = []
        case = {
            "case_id": case_id,
            "class": case_class,
            "expected_status": expected_status,
            "question": f"Synthetic question {case_id}?",
            "required_evidence": requirements,
        }
        conversation_id, turn_id = _request_identities(case_id)
        response = _synthetic_response(
            expected_status,
            conversation_id,
            turn_id,
            case_id,
        )
        metrics = contract._validate_response(
            response,
            conversation_id=conversation_id,
            turn_id=turn_id,
            required_evidence=requirements,
        )
        metrics["elapsed_milliseconds"] = case_index
        cases.append(case)
        observations.append({"case": case, "metrics": metrics, "response": response})
    case_set = {
        "artifact_kind": "ishikawa_retrieval_tuning_cases",
        "cases": cases,
        "schema_version": 2,
        "synthetic_content_only": True,
    }
    artifact = {
        "artifact_kind": ARTIFACT_KIND,
        "case_set_identity": _canonical_digest(case_set),
        "cases": observations,
        "endpoint": "http://127.0.0.1:1384/v1/chat",
        "raw_synthetic_responses_retained": True,
        "schema_version": 1,
        "summary": _summarize(observations),
        "synthetic_content_only": True,
        "target": {
            "architecture": "aarch64",
            "hostname": "SyntheticHost",
            "os_id": "ubuntu",
            "os_version": "24.04",
        },
    }
    summary = _validate_artifact(artifact, contract)
    if summary["acceptance_gate"] != "pass":
        raise AcceptanceError("self_test_gate_invalid")
    print("local_retrieval_api_acceptance_self_test=pass")
    return 0


def _synthetic_response(
    status: str,
    conversation_id: str,
    turn_id: str,
    case_id: str,
) -> dict[str, Any]:
    base = {
        "answer": None,
        "claims": [],
        "clarification": None,
        "conversation_id": conversation_id,
        "error": None,
        "request_id": _digest_text(f"request:{case_id}"),
        "schema": "ishikawa.chat-response.v1",
        "sources": [],
        "status": status,
        "turn_id": turn_id,
    }
    if status == "answered":
        citation_id = _digest_text(f"citation:{case_id}")
        base.update(
            {
                "answer": "Synthetic claim.",
                "claims": [{"citation_ids": [citation_id], "text": "Synthetic claim."}],
                "sources": [
                    {
                        "display_name": "Synthetic source",
                        "document_class": "policy_sop",
                        "excerpts": [
                            {
                                "anchor": None,
                                "citation_id": citation_id,
                                "excerpt": "Synthetic excerpt.",
                                "page_end": 1,
                                "page_start": 1,
                                "structural_path": [],
                            }
                        ],
                        "source_id": _digest_text(f"source:{case_id}"),
                        "source_label": "Source 1",
                    }
                ],
            }
        )
    elif status == "insufficient-evidence":
        base["error"] = {
            "code": "EVIDENCE_INSUFFICIENT",
            "message": "The available sources do not contain enough evidence to answer this question.",
        }
    else:
        base["clarification"] = "Please ask a specific question about this document."
    return base


def _summary_marker(name: str, summary: Mapping[str, Any]) -> str:
    return (
        f"{name}=pass;cases={summary['case_count']};"
        f"contract_valid={summary['contract_valid_count']};"
        f"expected_status_matches={summary['expected_status_match_count']};"
        f"required_evidence={summary['required_evidence_count']};"
        f"required_evidence_returned={summary['required_evidence_returned_count']};"
        f"required_evidence_cited={summary['required_evidence_cited_count']};"
        f"maximum_elapsed_milliseconds={summary['maximum_elapsed_milliseconds']};"
        f"total_elapsed_milliseconds={summary['total_elapsed_milliseconds']}"
    )


def _request_identities(case_id: str) -> tuple[str, str]:
    return (
        _digest_text(f"ishikawa-v1.1-acceptance-conversation:{case_id}"),
        _digest_text(f"ishikawa-v1.1-acceptance-turn:{case_id}"),
    )


def _canonical_digest(value: Any) -> str:
    encoded = json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def _digest_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _load_json(path: Path, label: str, *, require_private: bool) -> Any:
    if not path.is_absolute() or not path.is_file() or path.is_symlink():
        raise AcceptanceError(f"{label}_path_invalid")
    if require_private and path.stat().st_mode & 0o077:
        raise AcceptanceError(f"{label}_mode_invalid")
    try:
        return json.loads(path.read_text(encoding="utf-8", errors="strict"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        raise AcceptanceError(f"{label}_json_invalid") from None


def _require_present(values: argparse.Namespace, *names: str) -> None:
    if any(getattr(values, name) is None for name in names):
        raise AcceptanceError("required_argument_missing")


def _require_absent(values: argparse.Namespace, *names: str) -> None:
    if any(getattr(values, name) is not None for name in names):
        raise AcceptanceError("unexpected_argument_present")


if __name__ == "__main__":
    raise SystemExit(main())
