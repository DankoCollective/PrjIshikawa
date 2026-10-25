#!/usr/bin/env python3
"""Exercise the live clarification-follow-up path missed by first-turn gates."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import urllib.error
import urllib.request
from typing import Any, Mapping, NoReturn


HEX = re.compile(r"^[0-9a-f]{64}$")
REQUEST_SCHEMA = "ishikawa.chat-request.v1"
RESPONSE_SCHEMA = "ishikawa.chat-response.v5"
APPLICABILITY_DOCUMENT = "Security Event Reporting Procedure"
APPLICABILITY_IDENTIFIER = "99 TST 2043"
APPLICABILITY_PAGE = 1
FORM_DOCUMENT = "Incident Intake Form"
FORM_IDENTIFIER = "TST-9030"
FORM_PAGE = 1


class CanaryError(ValueError):
    """Stable content-free canary rejection."""


def fail(reason: str) -> NoReturn:
    raise CanaryError(reason)


def identity(label: str) -> str:
    return hashlib.sha256(label.encode("utf-8")).hexdigest()


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, separators=(",", ":"), sort_keys=True
    ).encode("utf-8")


def build_request() -> dict[str, Any]:
    prior_answer = (
        "The Security Event Reporting Procedure (99 TST 2043) governs suspected "
        "misuse, device loss, credential exposure, or unsafe access. The Incident "
        "Reporting and Response Procedure (99 TST 2006) and Incident Classification "
        "Policy (99 TST 2030) may also apply."
    )
    return {
        "conversation_id": identity("v13-55-multiturn-conversation"),
        "filters": {"document_classes": [], "document_keys": []},
        "history": [
            {
                "content": "I need to report an IT security incident.",
                "role": "user",
                "turn_id": identity("v13-55-turn-1"),
            },
            {
                "content": prior_answer,
                "role": "assistant",
                "turn_id": identity("v13-55-turn-2"),
            },
            {
                "content": "What forms do I need to complete?",
                "role": "user",
                "turn_id": identity("v13-55-turn-3"),
            },
            {
                "content": (
                    "Are you reporting a suspected misuse, device loss, or credential "
                    "exposure, or are you reporting a controlled-materials incident?"
                ),
                "role": "assistant",
                "turn_id": identity("v13-55-turn-4"),
            },
        ],
        "message": "A credential exposure.",
        "schema": REQUEST_SCHEMA,
        "source_references": [
            {
                "citation_id": None,
                "source_id": "0bfa90a7c0b46d4e9e67ed3da0ad2179bd97cf8c9f95f6fdfeef974b04e9572c",
                "source_label": "Source 1",
            },
            {
                "citation_id": None,
                "source_id": "5a7a86e20f6da653bf547f881c744d6ac7f22bbb6c36d38e82a6bb34a6ea41b2",
                "source_label": "Source 2",
            },
            {
                "citation_id": None,
                "source_id": "34e55cceb89c95ce4afe472736263754884267381713e65969393f440606de5d",
                "source_label": "Source 3",
            },
        ],
        "turn_id": identity("v13-55-turn-5"),
    }


def post(endpoint: str, body: bytes) -> tuple[int, bytes]:
    request = urllib.request.Request(
        endpoint,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=600) as response:
            return response.status, response.read(16 * 1024 * 1024 + 1)
    except urllib.error.HTTPError as error:
        return error.code, error.read(16 * 1024 * 1024 + 1)
    except (OSError, TimeoutError) as error:
        raise CanaryError("api_transport_failed") from error


def evidence_citations(
    sources: list[Any],
    *,
    display_name: str,
    identifier: str,
    page: int,
    required_phrases: tuple[str, ...],
) -> set[str]:
    matching = [
        source
        for source in sources
        if isinstance(source, Mapping)
        and source.get("display_name") == display_name
        and source.get("document_identifier") == identifier
    ]
    if not matching:
        fail(f"{identifier.lower().replace(' ', '_').replace('-', '_')}_document_missing")
    citations = {
        excerpt.get("citation_id")
        for source in matching
        for excerpt in source.get("excerpts", [])
        if isinstance(excerpt, Mapping)
        and type(excerpt.get("page_start")) is int
        and type(excerpt.get("page_end")) is int
        and excerpt["page_start"] <= page <= excerpt["page_end"]
        and all(
            phrase in str(excerpt.get("excerpt", "")).lower()
            for phrase in required_phrases
        )
        and isinstance(excerpt.get("citation_id"), str)
    }
    return citations


def validate_response(status_code: int, body: bytes) -> dict[str, Any]:
    if status_code != 200 or not body or len(body) > 16 * 1024 * 1024:
        fail("api_http_response_invalid")
    try:
        value = json.loads(body.decode("utf-8", errors="strict"))
    except (UnicodeError, json.JSONDecodeError) as error:
        raise CanaryError("api_response_json_invalid") from error
    if not isinstance(value, Mapping) or value.get("schema") != RESPONSE_SCHEMA:
        fail("api_response_contract_invalid")
    if value.get("status") != "answered":
        status = value.get("status")
        if isinstance(status, str) and re.fullmatch(r"[a-z-]+", status):
            fail(f"unexpected_response_status_{status.replace('-', '_')}")
        fail("unexpected_response_status")
    sources = value.get("sources")
    segments = value.get("segments")
    if not isinstance(sources, list) or not isinstance(segments, list) or not segments:
        fail("answered_response_shape_invalid")
    applicability_citations = evidence_citations(
        sources,
        display_name=APPLICABILITY_DOCUMENT,
        identifier=APPLICABILITY_IDENTIFIER,
        page=APPLICABILITY_PAGE,
        required_phrases=("credential exposure",),
    )
    form_citations = evidence_citations(
        sources,
        display_name=FORM_DOCUMENT,
        identifier=FORM_IDENTIFIER,
        page=FORM_PAGE,
        required_phrases=("incident intake form", "initial reporting"),
    )
    used = {
        citation
        for segment in segments
        if isinstance(segment, Mapping)
        for citation in segment.get("citation_ids", [])
        if isinstance(citation, str)
    }
    if not applicability_citations:
        fail("security_event_applicability_evidence_missing")
    if not applicability_citations & used:
        fail("security_event_applicability_evidence_not_cited")
    if not form_citations:
        fail("incident_intake_form_evidence_missing")
    if not form_citations & used:
        fail("incident_intake_form_evidence_not_cited")
    request_id = value.get("request_id")
    if not isinstance(request_id, str) or HEX.fullmatch(request_id) is None:
        fail("response_request_identity_invalid")
    return {
        "cited_incident_intake_form": True,
        "cited_security_event_applicability": True,
        "request_id": request_id,
        "source_count": len(sources),
        "status": value["status"],
    }


def self_test() -> None:
    request = build_request()
    assert request["history"][-1]["role"] == "assistant"
    assert len(request["source_references"]) == 3
    assert all(HEX.fullmatch(item["source_id"]) for item in request["source_references"])
    applicability_citation = identity("v13-55-applicability-citation")
    form_citation = identity("v13-55-form-citation")
    response = {
        "schema": RESPONSE_SCHEMA,
        "status": "answered",
        "request_id": identity("v13-55-request"),
        "segments": [
            {
                "text": "The procedure applies to credential exposure.",
                "citation_ids": [applicability_citation],
            },
            {
                "text": "Complete the Incident Intake Form.",
                "citation_ids": [form_citation],
            },
        ],
        "sources": [
            {
                "display_name": APPLICABILITY_DOCUMENT,
                "document_identifier": APPLICABILITY_IDENTIFIER,
                "excerpts": [
                    {
                        "citation_id": applicability_citation,
                        "excerpt": "The procedure governs credential exposure.",
                        "page_start": APPLICABILITY_PAGE,
                        "page_end": APPLICABILITY_PAGE,
                    }
                ],
            },
            {
                "display_name": FORM_DOCUMENT,
                "document_identifier": FORM_IDENTIFIER,
                "excerpts": [
                    {
                        "citation_id": form_citation,
                        "excerpt": (
                            "Incident Intake Form governs initial reporting of a "
                            "suspected incident."
                        ),
                        "page_start": FORM_PAGE,
                        "page_end": FORM_PAGE,
                    }
                ],
            }
        ],
    }
    result = validate_response(200, canonical_bytes(response))
    assert result["cited_security_event_applicability"] is True
    assert result["cited_incident_intake_form"] is True
    for removed_citation, expected_reason in (
        (
            applicability_citation,
            "security_event_applicability_evidence_not_cited",
        ),
        (form_citation, "incident_intake_form_evidence_not_cited"),
    ):
        rejected = json.loads(canonical_bytes(response))
        for segment in rejected["segments"]:
            segment["citation_ids"] = [
                value
                for value in segment["citation_ids"]
                if value != removed_citation
            ]
        try:
            validate_response(200, canonical_bytes(rejected))
        except CanaryError as error:
            assert str(error) == expected_reason
        else:
            raise AssertionError(f"expected rejection: {expected_reason}")
    print("v1_3_multiturn_resolution_evaluator_self_test=pass")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--endpoint")
    arguments = parser.parse_args()
    if arguments.self_test == arguments.run:
        fail("exactly_one_mode_required")
    if arguments.self_test:
        self_test()
        return 0
    if not isinstance(arguments.endpoint, str) or not arguments.endpoint.startswith(
        "http://127.0.0.1:"
    ):
        fail("loopback_endpoint_required")
    request_body = canonical_bytes(build_request())
    status_code, response_body = post(arguments.endpoint, request_body)
    result = validate_response(status_code, response_body)
    print(
        "multiturn_resolution=pass;"
        f"status={result['status']};sources={result['source_count']};"
        "applicability_document=99_TST_2043;applicability_page=1;"
        "form_document=TST_9030;form_page=1;both_cited=true;"
        f"request_id={result['request_id']}"
    )
    print("v1_3_multiturn_resolution_evaluation=pass")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except CanaryError as error:
        print(
            f"v1_3_multiturn_resolution_evaluation=blocked;reason={error}",
            file=sys.stderr,
        )
        raise SystemExit(1)
