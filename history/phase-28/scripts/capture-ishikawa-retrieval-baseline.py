#!/usr/bin/env python3
"""Capture a protected, synthetic-only Ishikawa retrieval tuning baseline.

Role:
  Send a bounded case set through the already-running loopback Chat UI, validate
  every response envelope, and retain the synthetic responses plus derived
  source-use measurements. The helper changes no configuration, service, or
  database state; ordinary request and model telemetry may be appended by the
  running application.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import socket
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Mapping, Sequence


REQUEST_SCHEMA = "ishikawa.chat-request.v1"
RESPONSE_SCHEMA = "ishikawa.chat-response.v1"
ARTIFACT_KIND = "ishikawa_retrieval_tuning_baseline"
HEX_IDENTITY = re.compile(r"^[0-9a-f]{64}$")
CASE_ID = re.compile(r"^[A-Z][A-Z0-9-]{1,31}$")
SOURCE_LABEL = re.compile(r"^Source [1-9][0-9]*$")
CLASS_ID = re.compile(r"^[a-z][a-z0-9_]{1,63}$")
EXPECTED_RESPONSE_FIELDS = frozenset(
    {
        "answer",
        "claims",
        "clarification",
        "conversation_id",
        "error",
        "request_id",
        "schema",
        "sources",
        "status",
        "turn_id",
    }
)
ERRORS_BY_STATUS = {
    "insufficient-evidence": (
        "EVIDENCE_INSUFFICIENT",
        "The available sources do not contain enough evidence to answer this question.",
    ),
    "out-of-scope": (
        "QUESTION_OUT_OF_SCOPE",
        "This question is outside the supported professional scope.",
    ),
    "security-rejected": (
        "REQUEST_SECURITY_REJECTED",
        "The request could not be processed safely.",
    ),
    "context-limit": (
        "CONTEXT_LIMIT_REACHED",
        "The requested context exceeds the configured limit.",
    ),
    "temporarily-unavailable": (
        "DEPENDENCY_UNAVAILABLE",
        "A required service is temporarily unavailable.",
    ),
    "internal-error": (
        "INTERNAL_ERROR",
        "The request could not be completed.",
    ),
}
EXPECTED_STATUSES = frozenset({"answered", "insufficient-evidence"})
CASE_CLASSES = frozenset({"responsive", "nonresponsive", "broad-navigation"})
ANCHOR_KINDS = frozenset({"table", "row", "form", "field", "procedure", "step"})


class BaselineError(ValueError):
    """Stable failure that excludes question, answer, and excerpt content."""


def main(arguments: Sequence[str] | None = None) -> int:
    """Validate inputs, capture the live baseline, or revalidate an artifact."""

    parser = argparse.ArgumentParser(allow_abbrev=False)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--capture", action="store_true")
    mode.add_argument("--self-test", action="store_true")
    mode.add_argument("--validate-cases", action="store_true")
    mode.add_argument("--validate-artifact", action="store_true")
    parser.add_argument("--endpoint")
    parser.add_argument("--cases", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--artifact", type=Path)
    parser.add_argument("--expected-hostname")
    parser.add_argument("--expected-os-version")
    values = parser.parse_args(arguments)
    try:
        if values.self_test:
            _require_absent(values, "endpoint", "cases", "output", "artifact", "expected_hostname", "expected_os_version")
            return _self_test()
        if values.validate_cases:
            _require_present(values, "cases")
            _require_absent(values, "endpoint", "output", "artifact", "expected_hostname", "expected_os_version")
            case_set = _load_case_set(values.cases)
            print(f"retrieval_tuning_cases=pass;cases={len(case_set['cases'])};synthetic_content_only=true")
            return 0
        if values.validate_artifact:
            _require_present(values, "artifact")
            _require_absent(values, "endpoint", "cases", "output", "expected_hostname", "expected_os_version")
            artifact = _load_private_json(values.artifact, "artifact")
            summary = _validate_baseline_artifact(artifact)
            print(_summary_marker("retrieval_tuning_artifact", summary))
            return 0
        _require_present(values, "endpoint", "cases", "output", "expected_hostname", "expected_os_version")
        _require_absent(values, "artifact")
        return _capture(
            endpoint=values.endpoint,
            cases_path=values.cases,
            output=values.output,
            expected_hostname=values.expected_hostname,
            expected_os_version=values.expected_os_version,
        )
    except BaselineError as error:
        print(f"ishikawa_retrieval_tuning_baseline=blocked;reason={error}")
        return 1
    except Exception:
        print("ishikawa_retrieval_tuning_baseline=blocked;reason=unexpected_failure")
        return 1


def _capture(
    *,
    endpoint: str,
    cases_path: Path,
    output: Path,
    expected_hostname: str,
    expected_os_version: str,
) -> int:
    endpoint = _loopback_chat_endpoint(endpoint)
    case_set = _load_case_set(cases_path)
    target = _validate_target(expected_hostname, expected_os_version)
    _validate_readiness(endpoint)

    observations: list[dict[str, Any]] = []
    for case in case_set["cases"]:
        print(f"case_start={case['case_id']}")
        conversation_id = _digest_text(f"ishikawa-baseline-conversation:{case['case_id']}")
        turn_id = _digest_text(f"ishikawa-baseline-turn:{case['case_id']}")
        request_value = _request(case["question"], conversation_id, turn_id)
        request_started_ns = time.monotonic_ns()
        response_value = _post_json(endpoint, request_value)
        elapsed_milliseconds = max(
            1,
            (time.monotonic_ns() - request_started_ns + 999_999) // 1_000_000,
        )
        metrics = _validate_response(
            response_value,
            conversation_id=conversation_id,
            turn_id=turn_id,
            required_evidence=case["required_evidence"],
        )
        metrics["elapsed_milliseconds"] = elapsed_milliseconds
        observations.append(
            {
                "case": case,
                "metrics": metrics,
                "response": response_value,
            }
        )
        print(
            f"case_result={case['case_id']};status={metrics['status']};"
            f"elapsed_milliseconds={elapsed_milliseconds};sources={metrics['source_group_count']};"
            f"cited_sources={metrics['cited_source_group_count']};"
            f"unused_sources={metrics['unused_source_group_count']}"
        )

    summary = _summarize(observations)
    artifact = {
        "artifact_kind": ARTIFACT_KIND,
        "case_set_sha256": _canonical_digest(case_set),
        "cases": observations,
        "endpoint": endpoint,
        "raw_synthetic_responses_retained": True,
        "schema_version": 1,
        "summary": summary,
        "synthetic_content_only": True,
        "target": target,
    }
    _validate_baseline_artifact(artifact)
    _atomic_private_json(output, artifact)
    print(
        "target_hostname="
        f"{target['hostname']};os_id={target['os_id']};os_version={target['os_version']};"
        f"architecture={target['architecture']}"
    )
    print("stack_readiness=pass;retrieval_http_status=200;retrieval_status=ready")
    print(_summary_marker("retrieval_tuning_baseline", summary))
    print("raw_synthetic_content_retained=true;credential_values_retained=false;runtime_changed=false")
    print("ishikawa_retrieval_tuning_baseline=pass")
    return 0


def _summary_marker(name: str, summary: Mapping[str, Any]) -> str:
    return (
        f"{name}=pass;cases={summary['case_count']};contract_valid={summary['contract_valid_count']};"
        f"expected_status_matches={summary['expected_status_match_count']};answered={summary['answered_count']};"
        f"nonanswered={summary['nonanswered_count']};sources={summary['source_group_count']};"
        f"cited_sources={summary['cited_source_group_count']};unused_sources={summary['unused_source_group_count']};"
        f"required_evidence={summary['required_evidence_count']};"
        f"required_evidence_cited={summary['required_evidence_cited_count']};"
        f"maximum_elapsed_milliseconds={summary['maximum_elapsed_milliseconds']};"
        f"total_elapsed_milliseconds={summary['total_elapsed_milliseconds']}"
    )


def _validate_readiness(endpoint: str) -> None:
    parsed = urllib.parse.urlsplit(endpoint)
    readiness_url = urllib.parse.urlunsplit((parsed.scheme, parsed.netloc, "/ready", "", ""))
    request = urllib.request.Request(
        readiness_url,
        headers={"Accept": "application/json"},
        method="GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            response_bytes = response.read(65537)
            status = response.status
            content_type = response.headers.get_content_type()
    except (OSError, TimeoutError, urllib.error.URLError):
        raise BaselineError("stack_not_ready") from None
    if status != 200 or content_type != "application/json" or len(response_bytes) > 65536:
        raise BaselineError("stack_not_ready")
    try:
        value = json.loads(response_bytes.decode("utf-8", errors="strict"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise BaselineError("stack_readiness_invalid") from None
    if value != {"schema": "ishikawa.health.v1", "status": "ready"}:
        raise BaselineError("stack_not_ready")


def _post_json(endpoint: str, value: Mapping[str, Any]) -> Any:
    body = json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode("utf-8")
    request = urllib.request.Request(
        endpoint,
        data=body,
        headers={"Accept": "application/json", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            status = response.status
            response_bytes = response.read(4 * 1024 * 1024 + 1)
            content_type = response.headers.get_content_type()
    except urllib.error.HTTPError as error:
        error.read(4 * 1024 * 1024 + 1)
        raise BaselineError(f"chat_http_status_{error.code}") from None
    except (OSError, TimeoutError, urllib.error.URLError):
        raise BaselineError("chat_exchange_failed") from None
    if status != 200 or content_type != "application/json":
        raise BaselineError("chat_http_contract_invalid")
    if not 1 <= len(response_bytes) <= 4 * 1024 * 1024:
        raise BaselineError("chat_response_size_invalid")
    try:
        return json.loads(response_bytes.decode("utf-8", errors="strict"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise BaselineError("chat_response_json_invalid") from None


def _request(question: str, conversation_id: str, turn_id: str) -> dict[str, Any]:
    return {
        "conversation_id": conversation_id,
        "filters": {"document_classes": [], "document_keys": []},
        "history": [],
        "message": question,
        "schema": REQUEST_SCHEMA,
        "source_references": [],
        "turn_id": turn_id,
    }


def _validate_response(
    value: Any,
    *,
    conversation_id: str,
    turn_id: str,
    required_evidence: Sequence[Mapping[str, Any]],
) -> dict[str, Any]:
    root = _exact_mapping(value, EXPECTED_RESPONSE_FIELDS, "response_fields_invalid")
    status = root["status"]
    if (
        root["schema"] != RESPONSE_SCHEMA
        or status not in {
            "answered",
            "clarification-required",
            "insufficient-evidence",
            "out-of-scope",
            "security-rejected",
            "context-limit",
            "temporarily-unavailable",
            "internal-error",
        }
        or root["conversation_id"] != conversation_id
        or root["turn_id"] != turn_id
    ):
        raise BaselineError("response_identity_or_status_invalid")
    _identity(root["request_id"], "response_request_id_invalid")

    source_count = 0
    excerpt_count = 0
    citation_count = 0
    claim_count = 0
    cited_citations: set[str] = set()
    citation_to_source: dict[str, str] = {}
    evidence_locations: list[tuple[str, int, int, str]] = []
    if status == "answered":
        answer = _bounded_text(root["answer"], 131072, "response_answer_invalid")
        if root["clarification"] is not None or root["error"] is not None:
            raise BaselineError("response_answer_fields_invalid")
        sources = root["sources"]
        claims = root["claims"]
        if not isinstance(sources, list) or not 1 <= len(sources) <= 20:
            raise BaselineError("response_sources_invalid")
        if not isinstance(claims, list) or not 1 <= len(claims) <= 64:
            raise BaselineError("response_claims_invalid")
        source_ids: set[str] = set()
        source_labels: set[str] = set()
        all_citations: set[str] = set()
        for source_value in sources:
            source = _exact_mapping(
                source_value,
                frozenset({"display_name", "document_class", "excerpts", "source_id", "source_label"}),
                "response_source_invalid",
            )
            source_id = _identity(source["source_id"], "response_source_id_invalid")
            source_label = source["source_label"]
            if not isinstance(source_label, str) or SOURCE_LABEL.fullmatch(source_label) is None:
                raise BaselineError("response_source_label_invalid")
            if source_id in source_ids or source_label in source_labels:
                raise BaselineError("response_source_duplicate")
            source_ids.add(source_id)
            source_labels.add(source_label)
            display_name = _bounded_text(source["display_name"], 512, "response_display_name_invalid")
            document_class = source["document_class"]
            if not isinstance(document_class, str) or CLASS_ID.fullmatch(document_class) is None:
                raise BaselineError("response_document_class_invalid")
            excerpts = source["excerpts"]
            if not isinstance(excerpts, list) or not 1 <= len(excerpts) <= 20:
                raise BaselineError("response_excerpts_invalid")
            for excerpt_value in excerpts:
                excerpt = _validate_excerpt(excerpt_value, all_citations)
                citation_id = excerpt["citation_id"]
                citation_to_source[citation_id] = source_id
                evidence_locations.append(
                    (display_name, excerpt["page_start"], excerpt["page_end"], citation_id)
                )
                excerpt_count += 1
        claim_texts: list[str] = []
        for claim_value in claims:
            claim = _exact_mapping(
                claim_value,
                frozenset({"citation_ids", "text"}),
                "response_claim_invalid",
            )
            claim_texts.append(_bounded_text(claim["text"], 65536, "response_claim_invalid"))
            claim_citations = claim["citation_ids"]
            if (
                not isinstance(claim_citations, list)
                or not claim_citations
                or len(set(claim_citations)) != len(claim_citations)
                or any(citation_id not in all_citations for citation_id in claim_citations)
            ):
                raise BaselineError("response_claim_citations_invalid")
            cited_citations.update(claim_citations)
        if answer != " ".join(claim_texts):
            raise BaselineError("response_answer_not_claim_derived")
        source_count = len(source_ids)
        citation_count = len(all_citations)
        claim_count = len(claims)
    elif status == "clarification-required":
        _bounded_text(root["clarification"], 2048, "response_clarification_invalid")
        if (
            root["answer"] is not None
            or root["error"] is not None
            or root["claims"] != []
            or root["sources"] != []
        ):
            raise BaselineError("response_status_fields_invalid")
    else:
        error = _exact_mapping(root["error"], frozenset({"code", "message"}), "response_error_invalid")
        if status not in ERRORS_BY_STATUS or (error["code"], error["message"]) != ERRORS_BY_STATUS[status]:
            raise BaselineError("response_error_invalid")
        if (
            root["answer"] is not None
            or root["clarification"] is not None
            or root["claims"] != []
            or root["sources"] != []
        ):
            raise BaselineError("response_status_fields_invalid")

    cited_source_ids = {citation_to_source[citation_id] for citation_id in cited_citations}
    required_returned = 0
    required_cited = 0
    for requirement in required_evidence:
        matching_citations = {
            citation_id
            for display_name, page_start, page_end, citation_id in evidence_locations
            if display_name == requirement["display_name"]
            and page_start <= requirement["page"] <= page_end
        }
        required_returned += bool(matching_citations)
        required_cited += bool(matching_citations & cited_citations)
    return {
        "citation_count": citation_count,
        "cited_citation_count": len(cited_citations),
        "cited_source_group_count": len(cited_source_ids),
        "claim_count": claim_count,
        "contract_valid": True,
        "excerpt_count": excerpt_count,
        "required_evidence_cited_count": required_cited,
        "required_evidence_count": len(required_evidence),
        "required_evidence_returned_count": required_returned,
        "source_group_count": source_count,
        "status": status,
        "unused_source_group_count": source_count - len(cited_source_ids),
    }


def _validate_excerpt(value: Any, citation_ids: set[str]) -> Mapping[str, Any]:
    excerpt = _exact_mapping(
        value,
        frozenset({"anchor", "citation_id", "excerpt", "page_end", "page_start", "structural_path"}),
        "response_excerpt_invalid",
    )
    citation_id = _identity(excerpt["citation_id"], "response_citation_id_invalid")
    if citation_id in citation_ids:
        raise BaselineError("response_citation_duplicate")
    citation_ids.add(citation_id)
    _bounded_text(excerpt["excerpt"], 262144, "response_excerpt_invalid")
    if (
        type(excerpt["page_start"]) is not int
        or type(excerpt["page_end"]) is not int
        or excerpt["page_start"] < 1
        or excerpt["page_end"] < excerpt["page_start"]
        or not isinstance(excerpt["structural_path"], list)
        or any(not isinstance(item, str) or not item.strip() for item in excerpt["structural_path"])
    ):
        raise BaselineError("response_excerpt_location_invalid")
    anchor = excerpt["anchor"]
    if anchor is not None:
        anchor = _exact_mapping(anchor, frozenset({"kind", "label"}), "response_anchor_invalid")
        if anchor["kind"] not in ANCHOR_KINDS:
            raise BaselineError("response_anchor_invalid")
        _bounded_text(anchor["label"], 512, "response_anchor_invalid")
    return excerpt


def _summarize(observations: Sequence[Mapping[str, Any]]) -> dict[str, int]:
    metrics = [observation["metrics"] for observation in observations]
    expected_matches = sum(
        observation["case"]["expected_status"] == observation["metrics"]["status"]
        for observation in observations
    )
    return {
        "answered_count": sum(metric["status"] == "answered" for metric in metrics),
        "case_count": len(observations),
        "citation_count": sum(metric["citation_count"] for metric in metrics),
        "cited_source_group_count": sum(metric["cited_source_group_count"] for metric in metrics),
        "contract_valid_count": sum(metric["contract_valid"] is True for metric in metrics),
        "expected_status_match_count": expected_matches,
        "maximum_elapsed_milliseconds": max(
            metric["elapsed_milliseconds"] for metric in metrics
        ),
        "nonanswered_count": sum(metric["status"] != "answered" for metric in metrics),
        "required_evidence_cited_count": sum(metric["required_evidence_cited_count"] for metric in metrics),
        "required_evidence_count": sum(metric["required_evidence_count"] for metric in metrics),
        "required_evidence_returned_count": sum(metric["required_evidence_returned_count"] for metric in metrics),
        "source_group_count": sum(metric["source_group_count"] for metric in metrics),
        "total_elapsed_milliseconds": sum(
            metric["elapsed_milliseconds"] for metric in metrics
        ),
        "unused_source_group_count": sum(metric["unused_source_group_count"] for metric in metrics),
    }


def _validate_baseline_artifact(value: Any) -> Mapping[str, Any]:
    artifact = _exact_mapping(
        value,
        frozenset(
            {
                "artifact_kind",
                "case_set_sha256",
                "cases",
                "endpoint",
                "raw_synthetic_responses_retained",
                "schema_version",
                "summary",
                "synthetic_content_only",
                "target",
            }
        ),
        "artifact_fields_invalid",
    )
    if (
        artifact["artifact_kind"] != ARTIFACT_KIND
        or artifact["schema_version"] != 1
        or artifact["synthetic_content_only"] is not True
        or artifact["raw_synthetic_responses_retained"] is not True
    ):
        raise BaselineError("artifact_contract_invalid")
    _identity(artifact["case_set_sha256"], "artifact_case_set_identity_invalid")
    _loopback_chat_endpoint(artifact["endpoint"])
    target = _exact_mapping(
        artifact["target"],
        frozenset({"architecture", "hostname", "os_id", "os_version"}),
        "artifact_target_invalid",
    )
    if (
        target["os_id"] != "ubuntu"
        or target["architecture"] != "amd64"
        or not isinstance(target["hostname"], str)
        or re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]*", target["hostname"]) is None
        or not isinstance(target["os_version"], str)
        or re.fullmatch(r"[0-9]{2}\.[0-9]{2}", target["os_version"]) is None
    ):
        raise BaselineError("artifact_target_invalid")
    cases = artifact["cases"]
    if not isinstance(cases, list) or not 1 <= len(cases) <= 64:
        raise BaselineError("artifact_cases_invalid")
    normalized_cases = _normalize_cases(
        [
            _exact_mapping(
                observation,
                frozenset({"case", "metrics", "response"}),
                "artifact_case_invalid",
            )["case"]
            for observation in cases
        ]
    )
    normalized_case_set = {
        "artifact_kind": "ishikawa_retrieval_tuning_cases",
        "cases": normalized_cases,
        "schema_version": 1,
        "synthetic_content_only": True,
    }
    if artifact["case_set_sha256"] != _canonical_digest(normalized_case_set):
        raise BaselineError("artifact_case_set_identity_invalid")
    for observation, case in zip(cases, normalized_cases, strict=True):
        _exact_mapping(observation, frozenset({"case", "metrics", "response"}), "artifact_case_invalid")
        if observation["case"] != case:
            raise BaselineError("artifact_case_not_canonical")
        expected_metrics = _validate_response(
            observation["response"],
            conversation_id=_digest_text(f"ishikawa-baseline-conversation:{case['case_id']}"),
            turn_id=_digest_text(f"ishikawa-baseline-turn:{case['case_id']}"),
            required_evidence=case["required_evidence"],
        )
        observed_metrics = observation["metrics"]
        if not isinstance(observed_metrics, Mapping):
            raise BaselineError("artifact_metrics_invalid")
        observed_without_latency = dict(observed_metrics)
        elapsed_milliseconds = observed_without_latency.pop("elapsed_milliseconds", None)
        if (
            type(elapsed_milliseconds) is not int
            or not 1 <= elapsed_milliseconds <= 3_600_000
            or observed_without_latency != expected_metrics
        ):
            raise BaselineError("artifact_metrics_invalid")
    expected_summary = _summarize(cases)
    if artifact["summary"] != expected_summary:
        raise BaselineError("artifact_summary_invalid")
    if expected_summary["case_count"] != expected_summary["contract_valid_count"]:
        raise BaselineError("artifact_contract_validation_incomplete")
    return expected_summary


def _load_case_set(path: Path) -> dict[str, Any]:
    value = _load_private_json(path, "case_set", require_private=False)
    root = _exact_mapping(
        value,
        frozenset({"artifact_kind", "cases", "schema_version", "synthetic_content_only"}),
        "case_set_fields_invalid",
    )
    if (
        root["artifact_kind"] != "ishikawa_retrieval_tuning_cases"
        or root["schema_version"] != 1
        or root["synthetic_content_only"] is not True
    ):
        raise BaselineError("case_set_contract_invalid")
    cases = root["cases"]
    if not isinstance(cases, list) or not 1 <= len(cases) <= 64:
        raise BaselineError("case_set_cases_invalid")
    normalized = _normalize_cases(cases)
    return {
        "artifact_kind": root["artifact_kind"],
        "cases": normalized,
        "schema_version": 1,
        "synthetic_content_only": True,
    }


def _normalize_cases(cases: Sequence[Any]) -> list[dict[str, Any]]:
    """Validate and canonicalize the human-reviewed tuning cases."""

    normalized: list[dict[str, Any]] = []
    case_ids: set[str] = set()
    for value in cases:
        case = _exact_mapping(
            value,
            frozenset({"case_id", "class", "expected_status", "question", "required_evidence"}),
            "case_fields_invalid",
        )
        case_id = case["case_id"]
        if not isinstance(case_id, str) or CASE_ID.fullmatch(case_id) is None or case_id in case_ids:
            raise BaselineError("case_identity_invalid")
        case_ids.add(case_id)
        if case["class"] not in CASE_CLASSES or case["expected_status"] not in EXPECTED_STATUSES:
            raise BaselineError("case_class_or_status_invalid")
        question = _bounded_text(case["question"], 16384, "case_question_invalid")
        raw_requirements = case["required_evidence"]
        if not isinstance(raw_requirements, list) or len(raw_requirements) > 20:
            raise BaselineError("case_required_evidence_invalid")
        requirements: list[dict[str, Any]] = []
        requirement_identities: set[tuple[str, int]] = set()
        for raw_requirement in raw_requirements:
            requirement = _exact_mapping(
                raw_requirement,
                frozenset({"display_name", "page"}),
                "case_required_evidence_invalid",
            )
            display_name = _bounded_text(
                requirement["display_name"], 512, "case_required_evidence_invalid"
            )
            page = requirement["page"]
            identity = (display_name, page)
            if type(page) is not int or page < 1 or identity in requirement_identities:
                raise BaselineError("case_required_evidence_invalid")
            requirement_identities.add(identity)
            requirements.append({"display_name": display_name, "page": page})
        normalized.append(
            {
                "case_id": case_id,
                "class": case["class"],
                "expected_status": case["expected_status"],
                "question": question,
                "required_evidence": requirements,
            }
        )
    return normalized


def _validate_target(expected_hostname: str, expected_os_version: str) -> dict[str, str]:
    if (
        not isinstance(expected_hostname, str)
        or re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]*", expected_hostname) is None
        or re.fullmatch(r"[0-9]{2}\.[0-9]{2}", expected_os_version or "") is None
    ):
        raise BaselineError("target_expectation_invalid")
    hostname = socket.gethostname().split(".", maxsplit=1)[0]
    os_release = _read_os_release()
    architecture = platform.machine()
    architecture = "amd64" if architecture == "x86_64" else architecture
    if (
        hostname != expected_hostname
        or os_release.get("ID") != "ubuntu"
        or os_release.get("VERSION_ID") != expected_os_version
        or architecture != "amd64"
    ):
        raise BaselineError("target_identity_mismatch")
    return {
        "architecture": architecture,
        "hostname": hostname,
        "os_id": "ubuntu",
        "os_version": expected_os_version,
    }


def _read_os_release() -> dict[str, str]:
    try:
        lines = Path("/etc/os-release").read_text(encoding="utf-8", errors="strict").splitlines()
    except (OSError, UnicodeError):
        raise BaselineError("os_release_unreadable") from None
    values: dict[str, str] = {}
    for line in lines:
        if "=" not in line:
            continue
        name, raw_value = line.split("=", maxsplit=1)
        values[name] = raw_value.strip().strip('"')
    return values


def _loopback_chat_endpoint(value: Any) -> str:
    if not isinstance(value, str):
        raise BaselineError("endpoint_invalid")
    parsed = urllib.parse.urlsplit(value)
    try:
        port = parsed.port
    except ValueError:
        raise BaselineError("endpoint_invalid") from None
    if (
        parsed.scheme != "http"
        or parsed.hostname != "127.0.0.1"
        or port is None
        or not 1 <= port <= 65535
        or parsed.path != "/v1/chat"
        or parsed.query
        or parsed.fragment
        or parsed.username is not None
        or parsed.password is not None
    ):
        raise BaselineError("endpoint_invalid")
    return value


def _self_test() -> int:
    conversation_id = "1" * 64
    turn_id = "2" * 64
    citation_id = "3" * 64
    answered = {
        "answer": "Synthetic claim.",
        "claims": [{"citation_ids": [citation_id], "text": "Synthetic claim."}],
        "clarification": None,
        "conversation_id": conversation_id,
        "error": None,
        "request_id": "4" * 64,
        "schema": RESPONSE_SCHEMA,
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
                "source_id": "5" * 64,
                "source_label": "Source 1",
            }
        ],
        "status": "answered",
        "turn_id": turn_id,
    }
    metrics = _validate_response(
        answered,
        conversation_id=conversation_id,
        turn_id=turn_id,
        required_evidence=({"display_name": "Synthetic source", "page": 1},),
    )
    metrics["elapsed_milliseconds"] = 10
    if (
        metrics["source_group_count"] != 1
        or metrics["cited_source_group_count"] != 1
        or metrics["unused_source_group_count"] != 0
        or metrics["required_evidence_cited_count"] != 1
    ):
        raise BaselineError("self_test_answered_metrics_invalid")
    insufficient = {
        "answer": None,
        "claims": [],
        "clarification": None,
        "conversation_id": conversation_id,
        "error": {
            "code": "EVIDENCE_INSUFFICIENT",
            "message": "The available sources do not contain enough evidence to answer this question.",
        },
        "request_id": "6" * 64,
        "schema": RESPONSE_SCHEMA,
        "sources": [],
        "status": "insufficient-evidence",
        "turn_id": turn_id,
    }
    empty_metrics = _validate_response(
        insufficient,
        conversation_id=conversation_id,
        turn_id=turn_id,
        required_evidence=(),
    )
    empty_metrics["elapsed_milliseconds"] = 20
    if empty_metrics["status"] != "insufficient-evidence" or empty_metrics["source_group_count"] != 0:
        raise BaselineError("self_test_insufficient_metrics_invalid")
    cases = [
        {
            "case_id": "R-TEST",
            "class": "responsive",
            "expected_status": "answered",
            "question": "Synthetic answered question?",
            "required_evidence": [{"display_name": "Synthetic source", "page": 1}],
        },
        {
            "case_id": "N-TEST",
            "class": "nonresponsive",
            "expected_status": "insufficient-evidence",
            "question": "Synthetic insufficient question?",
            "required_evidence": [],
        },
    ]
    answered_artifact = dict(answered)
    answered_artifact["conversation_id"] = _digest_text(
        "ishikawa-baseline-conversation:R-TEST"
    )
    answered_artifact["turn_id"] = _digest_text("ishikawa-baseline-turn:R-TEST")
    insufficient_artifact = dict(insufficient)
    insufficient_artifact["conversation_id"] = _digest_text(
        "ishikawa-baseline-conversation:N-TEST"
    )
    insufficient_artifact["turn_id"] = _digest_text("ishikawa-baseline-turn:N-TEST")
    observations = [
        {"case": cases[0], "metrics": metrics, "response": answered_artifact},
        {"case": cases[1], "metrics": empty_metrics, "response": insufficient_artifact},
    ]
    case_set = {
        "artifact_kind": "ishikawa_retrieval_tuning_cases",
        "cases": cases,
        "schema_version": 1,
        "synthetic_content_only": True,
    }
    artifact = {
        "artifact_kind": ARTIFACT_KIND,
        "case_set_sha256": _canonical_digest(case_set),
        "cases": observations,
        "endpoint": "http://127.0.0.1:1384/v1/chat",
        "raw_synthetic_responses_retained": True,
        "schema_version": 1,
        "summary": _summarize(observations),
        "synthetic_content_only": True,
        "target": {
            "architecture": "amd64",
            "hostname": "SyntheticHost",
            "os_id": "ubuntu",
            "os_version": "24.04",
        },
    }
    validated_summary = _validate_baseline_artifact(artifact)
    if validated_summary["case_count"] != 2 or validated_summary["contract_valid_count"] != 2:
        raise BaselineError("self_test_artifact_invalid")
    print("ishikawa_retrieval_tuning_baseline_self_test=pass")
    return 0


def _load_private_json(path: Path, label: str, *, require_private: bool = True) -> Any:
    if not isinstance(path, Path) or not path.is_absolute() or not path.is_file() or path.is_symlink():
        raise BaselineError(f"{label}_path_invalid")
    if require_private and path.stat().st_mode & 0o077:
        raise BaselineError(f"{label}_mode_invalid")
    try:
        return json.loads(path.read_text(encoding="utf-8", errors="strict"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        raise BaselineError(f"{label}_json_invalid") from None


def _atomic_private_json(path: Path, value: Mapping[str, Any]) -> None:
    if not path.is_absolute() or path.exists() or path.is_symlink():
        raise BaselineError("output_path_invalid")
    if not path.parent.is_dir() or path.parent.is_symlink():
        raise BaselineError("output_parent_invalid")
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            json.dump(value, output, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
        os.chmod(path, 0o600)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def _exact_mapping(value: Any, fields: frozenset[str], reason: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping) or set(value) != fields:
        raise BaselineError(reason)
    return value


def _identity(value: Any, reason: str) -> str:
    if not isinstance(value, str) or HEX_IDENTITY.fullmatch(value) is None:
        raise BaselineError(reason)
    return value


def _bounded_text(value: Any, maximum: int, reason: str) -> str:
    if (
        not isinstance(value, str)
        or not value
        or value != value.strip()
        or len(value) > maximum
        or "\x00" in value
    ):
        raise BaselineError(reason)
    return value


def _canonical_digest(value: Any) -> str:
    encoded = json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _digest_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _require_present(values: argparse.Namespace, *names: str) -> None:
    if any(getattr(values, name) is None for name in names):
        raise BaselineError("arguments_invalid")


def _require_absent(values: argparse.Namespace, *names: str) -> None:
    if any(getattr(values, name) is not None for name in names):
        raise BaselineError("arguments_invalid")


if __name__ == "__main__":
    raise SystemExit(main())
