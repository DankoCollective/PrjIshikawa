#!/usr/bin/env python3
"""Evaluate the frozen Ishikawa v1.3 sixty-question frontier boundary.

Purpose:
    Send the checksum-bound synthetic frontier cases to one loopback Ishikawa
    Retrieval API and require the complete response, evidence, citation, and
    diagnostic contract.
Mental model:
    Validate the case set, run R-001 and the selected priority canaries first,
    then run every remaining case and publish one synthetic-only JSON artifact.
Inputs or prerequisites:
    The tracked frontier case set, a ready loopback Retrieval API, and explicit
    expected target identity values.
Outputs or artifact lane:
    One exclusive synthetic-only qualification artifact and bounded terminal
    case milestones. No database, corpus, service, or credential is changed.
Usage:
    python3 evaluate-frontier.py --validate-cases --cases /absolute/cases.json
    python3 evaluate-frontier.py --run --cases /absolute/cases.json \\
      --endpoint http://127.0.0.1:1385/v1/chat --output /absolute/result.json \\
      --expected-hostname EmceeDanko --expected-os-version 24.04 \\
      --expected-architecture amd64
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Mapping, NoReturn, Sequence


HEX = re.compile(r"^[0-9a-f]{64}$")
CASE_ID = re.compile(r"^(?:R|N)-[0-9]{3}$|^B-001$")
SOURCE_LABEL = re.compile(r"^Source [1-9][0-9]*$")
CLASS_ID = re.compile(r"^[a-z][a-z0-9_]{1,63}$")
DOCUMENT_KEY = re.compile(r"^[a-z0-9]+(?:[._-][a-z0-9]+)*$")
REQUEST_SCHEMA = "ishikawa.chat-request.v1"
RESPONSE_SCHEMA = "ishikawa.chat-response.v5"
ARTIFACT_KIND = "ishikawa_v1_3_complete_api_qualification"
EXPECTED_CLASSES = {
    "responsive": "answered",
    "nonresponsive": "insufficient-evidence",
    "broad-navigation": "clarification-required",
}
ERRORS = {
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
DEPENDENCY_FAILURES = {"temporarily-unavailable", "internal-error"}


class EvaluationError(ValueError):
    """Stable failure for a contract or evaluation boundary."""


def fail(reason: str) -> NoReturn:
    raise EvaluationError(reason)


def exact(value: Any, fields: set[str], reason: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping) or set(value) != fields:
        fail(reason)
    return value


def text(value: Any, maximum: int, reason: str) -> str:
    if (
        not isinstance(value, str)
        or not value.strip()
        or value != value.strip()
        or len(value) > maximum
        or "\x00" in value
    ):
        fail(reason)
    return value


def identity(value: Any, reason: str) -> str:
    if not isinstance(value, str) or HEX.fullmatch(value) is None:
        fail(reason)
    return value


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, separators=(",", ":"), sort_keys=True
    ).encode("utf-8")


def digest(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def load_json(path: Path, label: str) -> Any:
    if not path.is_absolute() or not path.is_file() or path.is_symlink():
        fail(f"{label}_path_invalid")
    try:
        return json.loads(path.read_text(encoding="utf-8", errors="strict"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail(f"{label}_json_invalid")


def normalize_cases(value: Any) -> dict[str, Any]:
    base_fields = {
        "artifact_kind",
        "cases",
        "corpus_identity",
        "schema_version",
        "synthetic_content_only",
    }
    if not isinstance(value, Mapping):
        fail("case_set_fields_invalid")
    fields = set(value)
    if fields == base_fields:
        gate_profile = "complete_13"
    elif fields == base_fields | {"gate_profile"}:
        gate_profile = value.get("gate_profile")
        if gate_profile != "frontier_60":
            fail("case_set_gate_profile_invalid")
    else:
        fail("case_set_fields_invalid")
    root = exact(
        value,
        fields,
        "case_set_fields_invalid",
    )
    expected_case_count = 13 if gate_profile == "complete_13" else 60
    expected_counts = (
        {"responsive": 6, "nonresponsive": 6, "broad-navigation": 1}
        if gate_profile == "complete_13"
        else {"responsive": 60, "nonresponsive": 0, "broad-navigation": 0}
    )
    if (
        root["artifact_kind"] != "ishikawa_retrieval_api_cases"
        or root["corpus_identity"] not in {
            "synthetic-corpus-v2",
            "synthetic-corpus-v3",
        }
        or root["schema_version"] != 1
        or root["synthetic_content_only"] is not True
        or not isinstance(root["cases"], list)
        or len(root["cases"]) != expected_case_count
    ):
        fail("case_set_contract_invalid")
    cases: list[dict[str, Any]] = []
    seen: set[str] = set()
    counts = {name: 0 for name in EXPECTED_CLASSES}
    evidence_total = 0
    for raw in root["cases"]:
        case = exact(
            raw,
            {"case_id", "class", "expected_status", "question", "required_evidence"},
            "case_fields_invalid",
        )
        case_id = case["case_id"]
        case_class = case["class"]
        requirements = case["required_evidence"]
        if (
            not isinstance(case_id, str)
            or CASE_ID.fullmatch(case_id) is None
            or case_id in seen
            or case_class not in EXPECTED_CLASSES
            or case["expected_status"] != EXPECTED_CLASSES[case_class]
            or not isinstance(requirements, list)
            or len(requirements) > 20
        ):
            fail("case_contract_invalid")
        seen.add(case_id)
        counts[case_class] += 1
        normalized_requirements: list[dict[str, Any]] = []
        evidence_seen: set[tuple[str, int]] = set()
        for raw_requirement in requirements:
            requirement = exact(
                raw_requirement, {"display_name", "page"}, "case_evidence_invalid"
            )
            display_name = text(
                requirement["display_name"], 512, "case_evidence_invalid"
            )
            page = requirement["page"]
            item = (display_name, page)
            if type(page) is not int or page < 1 or item in evidence_seen:
                fail("case_evidence_invalid")
            evidence_seen.add(item)
            normalized_requirements.append(
                {"display_name": display_name, "page": page}
            )
        evidence_total += len(normalized_requirements)
        cases.append(
            {
                "case_id": case_id,
                "class": case_class,
                "expected_status": case["expected_status"],
                "question": text(case["question"], 16384, "case_question_invalid"),
                "required_evidence": normalized_requirements,
            }
        )
    if (
        counts != expected_counts
        or evidence_total < expected_counts["responsive"]
        or not cases
        or cases[0]["case_id"] != "R-001"
        or any(
            not case["required_evidence"]
            for case in cases
            if case["class"] == "responsive"
        )
    ):
        fail("case_class_inventory_invalid")
    normalized = {
        "artifact_kind": root["artifact_kind"],
        "cases": cases,
        "corpus_identity": root["corpus_identity"],
        "schema_version": 1,
        "synthetic_content_only": True,
    }
    if gate_profile == "frontier_60":
        normalized["gate_profile"] = gate_profile
    return normalized


def validate_diagnostics(value: Any) -> None:
    diagnostics = exact(
        value,
        {
            "api_processing_ms",
            "context_tokens",
            "gemma_tokens",
            "generation_retry",
            "lane_states",
            "nomic_query_tokens",
            "prompt_target_tokens",
            "relevance_reason_code",
            "result_counts",
            "selected_group_order",
            "sufficiency_reason_code",
            "timings_ms",
        },
        "response_diagnostics_invalid",
    )
    if (
        type(diagnostics["api_processing_ms"]) is not int
        or not 0 <= diagnostics["api_processing_ms"] <= 86_400_000
        or type(diagnostics["generation_retry"]) is not bool
    ):
        fail("response_diagnostics_invalid")
    timings = exact(
        diagnostics["timings_ms"],
        {"generation", "query_resolution", "response_build", "retrieval", "retrieval_detail", "scope"},
        "response_diagnostic_timings_invalid",
    )
    if any(
        type(item) is not int or not 0 <= item <= 86_400_000
        for name, item in timings.items()
        if name != "retrieval_detail"
    ):
        fail("response_diagnostic_timings_invalid")
    detail = timings["retrieval_detail"]
    if detail is not None:
        detail = exact(
            detail,
            {"nomic", "lexical_sql", "vector_sql", "fusion", "reconstruction", "tokenization"},
            "response_diagnostic_timings_invalid",
        )
        if any(
            type(item) is not int or not 0 <= item <= 86_400_000
            for item in detail.values()
        ):
            fail("response_diagnostic_timings_invalid")
    lanes = diagnostics["lane_states"]
    counts = diagnostics["result_counts"]
    if lanes is None:
        if counts is not None:
            fail("response_diagnostic_retrieval_invalid")
    else:
        lanes = exact(
            lanes, {"exact", "lexical", "vector"}, "response_diagnostic_lanes_invalid"
        )
        if any(item not in {"pass", "not_applicable", "failed"} for item in lanes.values()):
            fail("response_diagnostic_lanes_invalid")
        counts = exact(
            counts,
            {"authorized", "cited", "fused", "reconstructed"},
            "response_diagnostic_counts_invalid",
        )
        if any(type(item) is not int or not 0 <= item <= 100_000_000 for item in counts.values()):
            fail("response_diagnostic_counts_invalid")
    nomic = diagnostics["nomic_query_tokens"]
    if nomic is not None and (type(nomic) is not int or not 0 <= nomic <= 100_000_000):
        fail("response_diagnostic_nomic_invalid")
    prompt_target = diagnostics["prompt_target_tokens"]
    if prompt_target is not None and (
        type(prompt_target) is not int or not 0 <= prompt_target <= 100_000_000
    ):
        fail("response_diagnostic_prompt_target_invalid")
    for name in ("relevance_reason_code", "sufficiency_reason_code"):
        reason = diagnostics[name]
        if reason is not None and (
            not isinstance(reason, str)
            or re.fullmatch(r"[A-Z][A-Z0-9_]{0,95}", reason) is None
        ):
            fail("response_diagnostic_reason_invalid")
    group_order = diagnostics["selected_group_order"]
    if group_order is not None and (
        not isinstance(group_order, list)
        or len(group_order) > 6
        or len(set(group_order)) != len(group_order)
        or any(
            not isinstance(item, str) or not 1 <= len(item) <= 1024
            for item in group_order
        )
    ):
        fail("response_diagnostic_group_order_invalid")
    gemma = diagnostics["gemma_tokens"]
    if gemma is not None:
        gemma = exact(gemma, {"completion", "prompt", "total"}, "response_diagnostic_gemma_invalid")
        if (
            any(type(item) is not int or item < 1 for item in gemma.values())
            or gemma["total"] != gemma["prompt"] + gemma["completion"]
        ):
            fail("response_diagnostic_gemma_invalid")
    context = diagnostics["context_tokens"]
    if context is not None:
        context = exact(context, {"limit", "remaining", "used"}, "response_diagnostic_context_invalid")
        if (
            any(type(item) is not int for item in context.values())
            or context["limit"] < 1
            or context["used"] < 0
            or context["remaining"] < 0
            or context["used"] + context["remaining"] != context["limit"]
        ):
            fail("response_diagnostic_context_invalid")


def validate_response(
    value: Any,
    *,
    conversation_id: str,
    turn_id: str,
    required_evidence: Sequence[Mapping[str, Any]],
) -> dict[str, Any]:
    root = exact(
        value,
        {
            "clarification",
            "context_budget",
            "conversation_id",
            "diagnostics",
            "error",
            "request_id",
            "schema",
            "segments",
            "sources",
            "status",
            "turn_id",
        },
        "response_fields_invalid",
    )
    status = root["status"]
    if (
        root["schema"] != RESPONSE_SCHEMA
        or status not in {"answered", "clarification-required", *ERRORS}
        or root["conversation_id"] != conversation_id
        or root["turn_id"] != turn_id
    ):
        fail("response_identity_or_status_invalid")
    identity(root["request_id"], "response_request_id_invalid")
    validate_diagnostics(root["diagnostics"])
    segments = root["segments"]
    sources = root["sources"]
    citation_to_source: dict[str, str] = {}
    locations: list[tuple[str, int, int, str]] = []
    cited: set[str] = set()
    if status == "answered":
        if (
            root["clarification"] is not None
            or root["error"] is not None
            or not isinstance(segments, list)
            or not 1 <= len(segments) <= 64
            or not isinstance(sources, list)
            or not 1 <= len(sources) <= 20
        ):
            fail("response_answer_fields_invalid")
        budget = exact(
            root["context_budget"],
            {"token_limit", "tokens_remaining", "tokens_used"},
            "response_context_budget_invalid",
        )
        if (
            any(type(item) is not int for item in budget.values())
            or budget["token_limit"] < 1
            or budget["tokens_used"] < 0
            or budget["tokens_remaining"] < 0
            or budget["tokens_used"] + budget["tokens_remaining"] != budget["token_limit"]
        ):
            fail("response_context_budget_invalid")
        prompt_target = root["diagnostics"]["prompt_target_tokens"]
        if (
            prompt_target not in {8192, 12288, 16384}
            or budget["tokens_used"] > prompt_target + 2048
            or root["diagnostics"]["timings_ms"]["retrieval_detail"] is None
        ):
            fail("response_prompt_target_invalid")
        source_ids: set[str] = set()
        source_labels: set[str] = set()
        for raw_source in sources:
            source = exact(
                raw_source,
                {
                    "display_name",
                    "document_class",
                    "document_identifier",
                    "document_key",
                    "excerpts",
                    "has_additional_sections",
                    "page_count",
                    "source_id",
                    "source_label",
                },
                "response_source_invalid",
            )
            source_id = identity(source["source_id"], "response_source_id_invalid")
            label = source["source_label"]
            if (
                not isinstance(label, str)
                or SOURCE_LABEL.fullmatch(label) is None
                or source_id in source_ids
                or label in source_labels
                or not isinstance(source["document_key"], str)
                or DOCUMENT_KEY.fullmatch(source["document_key"]) is None
                or not isinstance(source["document_class"], str)
                or CLASS_ID.fullmatch(source["document_class"]) is None
                or type(source["has_additional_sections"]) is not bool
                or type(source["page_count"]) is not int
                or source["page_count"] < 1
            ):
                fail("response_source_invalid")
            if source["document_identifier"] is not None:
                text(source["document_identifier"], 512, "response_source_invalid")
            display_name = text(source["display_name"], 512, "response_source_invalid")
            source_ids.add(source_id)
            source_labels.add(label)
            excerpts = source["excerpts"]
            if not isinstance(excerpts, list) or not 1 <= len(excerpts) <= 20:
                fail("response_excerpts_invalid")
            for raw_excerpt in excerpts:
                excerpt = exact(
                    raw_excerpt,
                    {"anchor", "citation_id", "excerpt", "page_end", "page_start", "structural_path"},
                    "response_excerpt_invalid",
                )
                citation = identity(excerpt["citation_id"], "response_citation_invalid")
                if citation in citation_to_source:
                    fail("response_citation_duplicate")
                text(excerpt["excerpt"], 262144, "response_excerpt_invalid")
                if (
                    type(excerpt["page_start"]) is not int
                    or type(excerpt["page_end"]) is not int
                    or excerpt["page_start"] < 1
                    or excerpt["page_end"] < excerpt["page_start"]
                    or excerpt["page_end"] > source["page_count"]
                    or not isinstance(excerpt["structural_path"], list)
                    or any(not isinstance(item, str) or not item.strip() for item in excerpt["structural_path"])
                ):
                    fail("response_excerpt_location_invalid")
                anchor = excerpt["anchor"]
                if anchor is not None:
                    anchor = exact(anchor, {"kind", "label"}, "response_anchor_invalid")
                    if anchor["kind"] not in {"table", "row", "form", "field", "procedure", "step"}:
                        fail("response_anchor_invalid")
                    text(anchor["label"], 512, "response_anchor_invalid")
                citation_to_source[citation] = source_id
                locations.append(
                    (display_name, excerpt["page_start"], excerpt["page_end"], citation)
                )
        for raw_segment in segments:
            segment = exact(raw_segment, {"citation_ids", "text"}, "response_segment_invalid")
            text(segment["text"], 65536, "response_segment_invalid")
            citations = segment["citation_ids"]
            if (
                not isinstance(citations, list)
                or not citations
                or len(citations) != len(set(citations))
                or any(item not in citation_to_source for item in citations)
            ):
                fail("response_segment_citations_invalid")
            cited.update(citations)
    elif status == "clarification-required":
        text(root["clarification"], 2048, "response_clarification_invalid")
        if root["context_budget"] is not None or root["error"] is not None or segments != [] or sources != []:
            fail("response_status_fields_invalid")
    else:
        error = exact(root["error"], {"code", "message"}, "response_error_invalid")
        if (
            (error["code"], error["message"]) != ERRORS[status]
            or root["clarification"] is not None
            or root["context_budget"] is not None
            or segments != []
            or sources != []
        ):
            fail("response_status_fields_invalid")
    required_returned = 0
    required_cited = 0
    for requirement in required_evidence:
        matching = {
            citation
            for display_name, page_start, page_end, citation in locations
            if display_name == requirement["display_name"]
            and page_start <= requirement["page"] <= page_end
        }
        required_returned += bool(matching)
        required_cited += bool(matching & cited)
    return {
        "citation_count": len(citation_to_source),
        "cited_citation_count": len(cited),
        "contract_valid": True,
        "required_evidence_cited_count": required_cited,
        "required_evidence_count": len(required_evidence),
        "required_evidence_returned_count": required_returned,
        "segment_count": len(segments),
        "source_group_count": len(sources),
        "status": status,
    }


def request_payload(case: Mapping[str, Any]) -> tuple[dict[str, Any], str, str]:
    case_id = case["case_id"]
    conversation_id = digest(f"ishikawa-v1.3-acceptance-conversation:{case_id}")
    turn_id = digest(f"ishikawa-v1.3-acceptance-turn:{case_id}")
    return (
        {
            "conversation_id": conversation_id,
            "filters": {"document_classes": [], "document_keys": []},
            "history": [],
            "message": case["question"],
            "schema": REQUEST_SCHEMA,
            "source_references": [],
            "turn_id": turn_id,
        },
        conversation_id,
        turn_id,
    )


def post_json(endpoint: str, payload: Mapping[str, Any]) -> Any:
    parsed = urllib.parse.urlsplit(endpoint)
    if (
        parsed.scheme != "http"
        or parsed.hostname != "127.0.0.1"
        or parsed.path != "/v1/chat"
        or parsed.query
        or parsed.fragment
        or parsed.port is None
    ):
        fail("endpoint_invalid")
    request = urllib.request.Request(
        endpoint,
        data=canonical_bytes(payload),
        headers={"Accept": "application/json", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=600) as response:
            body = response.read(8 * 1024 * 1024 + 1)
            if response.status != 200 or response.headers.get_content_type() != "application/json":
                fail("chat_http_contract_invalid")
    except urllib.error.HTTPError as error:
        error.read(8 * 1024 * 1024 + 1)
        fail(f"chat_http_status_{error.code}")
    except (OSError, TimeoutError, urllib.error.URLError):
        fail("chat_exchange_failed")
    if not 1 <= len(body) <= 8 * 1024 * 1024:
        fail("chat_response_size_invalid")
    try:
        return json.loads(body.decode("utf-8", errors="strict"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        fail("chat_response_json_invalid")


def target(hostname: str, os_version: str, architecture: str) -> dict[str, str]:
    values: dict[str, str] = {}
    try:
        for line in Path("/etc/os-release").read_text(encoding="utf-8").splitlines():
            if "=" in line:
                name, raw = line.split("=", 1)
                values[name] = raw.strip().strip('"')
    except (OSError, UnicodeError):
        fail("target_os_unreadable")
    actual_architecture = platform.machine()
    actual_architecture = "amd64" if actual_architecture == "x86_64" else actual_architecture
    actual_hostname = socket.gethostname().split(".", 1)[0]
    if (
        actual_hostname != hostname
        or values.get("ID") != "ubuntu"
        or values.get("VERSION_ID") != os_version
        or actual_architecture != architecture
    ):
        fail("target_identity_mismatch")
    return {
        "architecture": architecture,
        "hostname": hostname,
        "os_id": "ubuntu",
        "os_version": os_version,
    }


def summarize(observations: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    metrics = [item["metrics"] for item in observations]
    expected = sum(
        item["case"]["expected_status"] == item["metrics"]["status"]
        for item in observations
    )
    returned = sum(item["required_evidence_returned_count"] for item in metrics)
    cited = sum(item["required_evidence_cited_count"] for item in metrics)
    dependency_failures = sum(item["status"] in DEPENDENCY_FAILURES for item in metrics)
    required = sum(item["required_evidence_count"] for item in metrics)
    expected_required = sum(
        item["case"]["class"] == "responsive" for item in observations
    )
    gate = (
        len(observations) in {13, 60}
        and expected == len(observations)
        and required >= expected_required
        and returned == required
        and cited == required
        and dependency_failures == 0
        and all(item["contract_valid"] is True for item in metrics)
    )
    return {
        "acceptance_gate": "pass" if gate else "not_met",
        "case_count": len(observations),
        "contract_valid_count": sum(item["contract_valid"] is True for item in metrics),
        "dependency_failure_count": dependency_failures,
        "expected_status_match_count": expected,
        "maximum_elapsed_milliseconds": max(item["elapsed_milliseconds"] for item in metrics),
        "required_evidence_cited_count": cited,
        "required_evidence_count": sum(item["required_evidence_count"] for item in metrics),
        "required_evidence_returned_count": returned,
        "total_elapsed_milliseconds": sum(item["elapsed_milliseconds"] for item in metrics),
    }


def write_exclusive(path: Path, payload: bytes) -> None:
    if (
        not path.is_absolute()
        or path.exists()
        or path.is_symlink()
        or not path.parent.is_dir()
        or path.parent.is_symlink()
    ):
        fail("output_path_invalid")
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)


def synthetic_response(
    status: str,
    conversation_id: str,
    turn_id: str,
    requirements: Sequence[Mapping[str, Any]],
) -> dict[str, Any]:
    diagnostics = {
        "api_processing_ms": 1,
        "context_tokens": None,
        "gemma_tokens": None,
        "generation_retry": False,
        "lane_states": None,
        "nomic_query_tokens": None,
        "prompt_target_tokens": None,
        "relevance_reason_code": None,
        "result_counts": None,
        "selected_group_order": None,
        "sufficiency_reason_code": None,
        "timings_ms": {"generation": 0, "query_resolution": 0, "response_build": 1, "retrieval": 0, "retrieval_detail": None, "scope": 0},
    }
    root: dict[str, Any] = {
        "clarification": None,
        "context_budget": None,
        "conversation_id": conversation_id,
        "diagnostics": diagnostics,
        "error": None,
        "request_id": digest("request:" + turn_id),
        "schema": RESPONSE_SCHEMA,
        "segments": [],
        "sources": [],
        "status": status,
        "turn_id": turn_id,
    }
    if status == "answered":
        segments = []
        sources = []
        for index, requirement in enumerate(requirements, 1):
            citation = digest(f"citation:{turn_id}:{index}")
            segments.append({"citation_ids": [citation], "text": f"Synthetic answer {index}."})
            sources.append(
                {
                    "display_name": requirement["display_name"],
                    "document_class": "policy_sop",
                    "document_identifier": f"99 TST {2000 + index}",
                    "document_key": f"policy.synthetic-{index}",
                    "excerpts": [{"anchor": None, "citation_id": citation, "excerpt": "Synthetic excerpt.", "page_end": requirement["page"], "page_start": requirement["page"], "structural_path": ["I. Synthetic"]}],
                    "has_additional_sections": False,
                    "page_count": requirement["page"],
                    "source_id": digest(f"source:{turn_id}:{index}"),
                    "source_label": f"Source {index}",
                }
            )
        root["segments"] = segments
        root["sources"] = sources
        root["context_budget"] = {"token_limit": 32768, "tokens_remaining": 32000, "tokens_used": 768}
        root["diagnostics"]["prompt_target_tokens"] = 8192
        root["diagnostics"]["timings_ms"]["retrieval_detail"] = {
            "nomic": 0,
            "lexical_sql": 0,
            "vector_sql": 0,
            "fusion": 0,
            "reconstruction": 0,
            "tokenization": 0,
        }
    elif status == "clarification-required":
        root["clarification"] = "Please clarify the requested policy detail."
    else:
        code, message = ERRORS[status]
        root["error"] = {"code": code, "message": message}
    return root


def self_test() -> int:
    observations = []
    for index in range(1, 14):
        if index <= 6:
            case_class, status = "responsive", "answered"
            count = (3, 3, 2, 2, 2, 1)[index - 1]
            requirements = [
                {"display_name": f"Synthetic source {item}", "page": item}
                for item in range(1, count + 1)
            ]
            case_id = f"R-{index:03d}"
        elif index <= 12:
            case_class, status, requirements = "nonresponsive", "insufficient-evidence", []
            case_id = f"N-{index - 6:03d}"
        else:
            case_class, status, requirements = "broad-navigation", "clarification-required", []
            case_id = "B-001"
        case = {"case_id": case_id, "class": case_class, "expected_status": status, "question": f"Question {case_id}?", "required_evidence": requirements}
        payload, conversation_id, turn_id = request_payload(case)
        assert payload["schema"] == REQUEST_SCHEMA
        metrics = validate_response(
            synthetic_response(status, conversation_id, turn_id, requirements),
            conversation_id=conversation_id,
            turn_id=turn_id,
            required_evidence=requirements,
        )
        metrics["elapsed_milliseconds"] = index
        observations.append({"case": case, "metrics": metrics})
    assert summarize(observations)["acceptance_gate"] == "pass"
    canary_case = observations[0]["case"]
    canary_metrics = dict(observations[0]["metrics"])
    assert canary_failure_reasons(canary_case, canary_metrics) == []
    canary_metrics.update(
        {
            "required_evidence_cited_count": 0,
            "required_evidence_returned_count": 0,
            "status": "temporarily-unavailable",
        }
    )
    assert canary_failure_reasons(canary_case, canary_metrics) == [
        "status_mismatch",
        "required_evidence_not_returned",
        "required_evidence_not_cited",
        "terminal_dependency_status",
    ]
    prioritized = prioritize_cases(
        tuple(item["case"] for item in observations),
        ("R-003", "N-002"),
    )
    assert [item["case_id"] for item in prioritized[:4]] == [
        "R-001",
        "R-003",
        "N-002",
        "R-002",
    ]
    print("v1_3_complete_api_evaluator_self_test=pass")
    return 0


def canary_failure_reasons(case: Mapping[str, Any], metrics: Mapping[str, Any]) -> list[str]:
    failures = []
    if metrics["status"] != case["expected_status"]:
        failures.append("status_mismatch")
    if metrics["required_evidence_returned_count"] != metrics["required_evidence_count"]:
        failures.append("required_evidence_not_returned")
    if metrics["required_evidence_cited_count"] != metrics["required_evidence_count"]:
        failures.append("required_evidence_not_cited")
    if metrics["status"] in DEPENDENCY_FAILURES:
        failures.append("terminal_dependency_status")
    return failures


def prioritize_cases(
    cases: Sequence[Mapping[str, Any]], priority_case_ids: Sequence[str]
) -> tuple[Mapping[str, Any], ...]:
    """Run R-001, requested canaries, then every remaining case exactly once."""

    requested = tuple(priority_case_ids)
    if len(set(requested)) != len(requested) or "R-001" in requested:
        fail("priority_case_ids_invalid")
    by_id = {case["case_id"]: case for case in cases}
    if any(case_id not in by_id for case_id in requested):
        fail("priority_case_ids_invalid")
    ordered_ids = ("R-001", *requested)
    return tuple(
        [by_id[case_id] for case_id in ordered_ids]
        + [case for case in cases if case["case_id"] not in ordered_ids]
    )


def execute(arguments: argparse.Namespace) -> int:
    case_set = normalize_cases(load_json(arguments.cases, "case_set"))
    observed_target = target(
        arguments.expected_hostname,
        arguments.expected_os_version,
        arguments.expected_architecture,
    )
    observations = []
    canary_passed = False
    canary_abort_reason = None
    priority_case_ids = tuple(arguments.priority_case_id)
    ordered_cases = prioritize_cases(case_set["cases"], priority_case_ids)
    priority_passed: list[str] = []
    priority_abort_case = None
    priority_abort_reason = None
    for case in ordered_cases:
        print(f"case_start={case['case_id']}", flush=True)
        payload, conversation_id, turn_id = request_payload(case)
        started = time.monotonic_ns()
        response = post_json(arguments.endpoint, payload)
        elapsed = max(1, (time.monotonic_ns() - started) // 1_000_000)
        metrics = validate_response(
            response,
            conversation_id=conversation_id,
            turn_id=turn_id,
            required_evidence=case["required_evidence"],
        )
        metrics["elapsed_milliseconds"] = elapsed
        observations.append({"case": case, "metrics": metrics, "response": response})
        print(
            f"case_result={case['case_id']};status={metrics['status']};"
            f"expected_status={case['expected_status']};"
            f"required_returned={metrics['required_evidence_returned_count']}/"
            f"{metrics['required_evidence_count']};"
            f"required_cited={metrics['required_evidence_cited_count']}/"
            f"{metrics['required_evidence_count']};elapsed_milliseconds={elapsed}",
            flush=True,
        )
        if case["case_id"] == "R-001":
            canary_failures = canary_failure_reasons(case, metrics)
            if canary_failures:
                canary_abort_reason = "_and_".join(canary_failures)
                print(
                    f"canary_abort=R-001;reason={canary_abort_reason};"
                    "remaining_cases_executed=false",
                    flush=True,
                )
                break
            canary_passed = True
            print("canary_result=R-001;state=pass;remaining_cases_enabled=true", flush=True)
        elif case["case_id"] in priority_case_ids:
            priority_failures = canary_failure_reasons(case, metrics)
            if priority_failures:
                priority_abort_case = case["case_id"]
                priority_abort_reason = "_and_".join(priority_failures)
                print(
                    f"priority_canary_abort={priority_abort_case};"
                    f"reason={priority_abort_reason};remaining_cases_executed=false",
                    flush=True,
                )
                break
            priority_passed.append(case["case_id"])
            print(
                f"priority_canary_result={case['case_id']};state=pass;"
                f"passed={len(priority_passed)}/{len(priority_case_ids)}",
                flush=True,
            )
            if len(priority_passed) == len(priority_case_ids):
                print(
                    "priority_canary_set=pass;complete_gate_enabled=true",
                    flush=True,
                )
    summary = summarize(observations)
    artifact = {
        "artifact_kind": ARTIFACT_KIND,
        "canary": {
            "abort_reason": canary_abort_reason,
            "case_id": "R-001",
            "passed": canary_passed,
        },
        "case_set_identity": hashlib.sha256(canonical_bytes(case_set)).hexdigest(),
        "cases": observations,
        "endpoint": arguments.endpoint,
        "execution_order": [case["case_id"] for case in ordered_cases],
        "priority_canary": {
            "abort_case": priority_abort_case,
            "abort_reason": priority_abort_reason,
            "passed_case_ids": priority_passed,
            "requested_case_ids": list(priority_case_ids),
        },
        "raw_synthetic_responses_retained": True,
        "schema_version": 1,
        "summary": summary,
        "synthetic_content_only": True,
        "target": observed_target,
    }
    payload = canonical_bytes(artifact) + b"\n"
    write_exclusive(arguments.output, payload)
    print(
        f"complete_api_cases={summary['case_count']};"
        f"expected_status_matches={summary['expected_status_match_count']}/"
        f"{summary['case_count']};"
        f"required_evidence_returned={summary['required_evidence_returned_count']}/"
        f"{summary['required_evidence_count']};"
        f"required_evidence_cited={summary['required_evidence_cited_count']}/"
        f"{summary['required_evidence_count']};"
        f"dependency_failures={summary['dependency_failure_count']}"
    )
    print(f"artifact_sha256={hashlib.sha256(payload).hexdigest()}")
    if not canary_passed:
        print(
            "v1_3_complete_api_evaluation=blocked;"
            f"reason=canary_failed_{canary_abort_reason or 'before_result'}"
        )
        return 1
    if priority_abort_case is not None:
        normalized_case = priority_abort_case.lower().replace("-", "_")
        print(
            "v1_3_complete_api_evaluation=blocked;"
            f"reason=priority_canary_failed_{normalized_case}_{priority_abort_reason}"
        )
        return 1
    if summary["acceptance_gate"] != "pass":
        print("v1_3_complete_api_evaluation=blocked;reason=acceptance_gate_not_met")
        return 1
    print("v1_3_complete_api_evaluation=pass")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--validate-cases", action="store_true")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--cases", type=Path)
    parser.add_argument("--endpoint", default="http://127.0.0.1:1384/v1/chat")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--expected-hostname", default="DankoSurface")
    parser.add_argument("--expected-os-version", default="24.04")
    parser.add_argument("--expected-architecture", default="aarch64")
    parser.add_argument("--priority-case-id", action="append", default=[])
    arguments = parser.parse_args()
    modes = sum((arguments.self_test, arguments.validate_cases, arguments.run))
    if modes != 1:
        fail("mode_invalid")
    if arguments.self_test:
        return self_test()
    if arguments.cases is None:
        fail("case_set_required")
    case_set = normalize_cases(load_json(arguments.cases, "case_set"))
    if arguments.validate_cases:
        counts = {
            name: sum(case["class"] == name for case in case_set["cases"])
            for name in EXPECTED_CLASSES
        }
        required_evidence = sum(
            len(case["required_evidence"]) for case in case_set["cases"]
        )
        print(
            "v1_3_complete_api_case_set=pass;"
            f"cases={len(case_set['cases'])};"
            f"responsive={counts['responsive']};"
            f"nonresponsive={counts['nonresponsive']};"
            f"broad_navigation={counts['broad-navigation']};"
            f"required_evidence={required_evidence};"
            f"identity={hashlib.sha256(canonical_bytes(case_set)).hexdigest()}"
        )
        return 0
    if arguments.output is None:
        fail("output_required")
    return execute(arguments)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except EvaluationError as error:
        print(f"v1_3_complete_api_evaluation=blocked;reason={error}")
        raise SystemExit(1)

