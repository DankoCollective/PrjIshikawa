#!/usr/bin/env python3
"""Exercise deterministic department-catalog and document-identifier routing."""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import io
import json
import re
import sys
import urllib.error
import urllib.request
from typing import Any, Callable, Mapping, NoReturn, Sequence


HEX = re.compile(r"^[0-9a-f]{64}$")
REQUEST_SCHEMA = "ishikawa.chat-request.v1"
RESPONSE_SCHEMA = "ishikawa.chat-response.v5"
LEGAL_QUESTION = (
    "I just started in the Legal department can you tell me what policies "
    "I need to be aware of?"
)
LEGAL_IDENTIFIERS = (
    "99 TST 2022",
    "99 TST 2032",
    "TST-9020",
    "99 TST 2005",
    "99 TST 2020",
    "99 TST 2006",
    "99 TST 2031",
)
LEGAL_DEPARTMENT_IDENTIFIERS = frozenset(("99 TST 2022", "99 TST 2032"))
LEGAL_RELATED_IDENTIFIERS = frozenset(
    identifier
    for identifier in LEGAL_IDENTIFIERS
    if identifier not in LEGAL_DEPARTMENT_IDENTIFIERS
)
CONTROLLED_MATERIALS_IDENTIFIER = "99 TST 2001"
ACCESS_AUTHORIZATION_IDENTIFIER = "TST-9050"
ACCESS_AUTHORIZATION_QUESTION = (
    "Tell me more about TST-9050. What is the process and what information "
    "should I have ready?"
)
CONTROLLED_ACCESS_EXCEPTION_IDENTIFIER = "TST-9001"
CONTROLLED_ACCESS_EXCEPTION_QUESTION = "Tell me more about TST-9001"


class CanaryError(ValueError):
    """Stable content-free catalog-routing rejection."""


def fail(reason: str) -> NoReturn:
    raise CanaryError(reason)


def identity(label: str) -> str:
    return hashlib.sha256(label.encode("utf-8")).hexdigest()


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, separators=(",", ":"), sort_keys=True
    ).encode("utf-8")


def request_body(
    label: str,
    message: str,
    *,
    history: Sequence[Mapping[str, Any]] = (),
    source_references: Sequence[Mapping[str, Any]] = (),
) -> bytes:
    return canonical_bytes(
        {
            "conversation_id": identity(f"v13-56-{label}-conversation"),
            "filters": {"document_classes": [], "document_keys": []},
            "history": list(history),
            "message": message,
            "schema": REQUEST_SCHEMA,
            "source_references": list(source_references),
            "turn_id": identity(f"v13-56-{label}-turn"),
        }
    )


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


def decode_answer(
    status_code: int,
    body: bytes,
    label: str,
    *,
    emit_failure_observation: bool = True,
) -> dict[str, Any]:
    if status_code != 200 or not body or len(body) > 16 * 1024 * 1024:
        fail(f"{label}_http_response_invalid")
    try:
        value = json.loads(body.decode("utf-8", errors="strict"))
    except (UnicodeError, json.JSONDecodeError) as error:
        raise CanaryError(f"{label}_response_json_invalid") from error
    if not isinstance(value, dict) or value.get("schema") != RESPONSE_SCHEMA:
        fail(f"{label}_response_contract_invalid")
    if value.get("status") != "answered":
        status = value.get("status")
        diagnostics = value.get("diagnostics")
        if emit_failure_observation:
            safe_observation: dict[str, Any] = {"case": label, "status": status}
            if isinstance(diagnostics, Mapping):
                safe_observation["diagnostics"] = {
                    key: diagnostics.get(key)
                    for key in (
                        "lane_states",
                        "prompt_target_tokens",
                        "relevance_reason_code",
                        "result_counts",
                        "selected_group_order",
                        "sufficiency_reason_code",
                        "timings_ms",
                    )
                }
            print(
                "catalog_routing_failure_observation="
                + canonical_bytes(safe_observation).decode("utf-8"),
                file=sys.stderr,
            )
        diagnostic_reasons: list[str] = []
        if isinstance(diagnostics, Mapping):
            for key in ("relevance_reason_code", "sufficiency_reason_code"):
                reason = diagnostics.get(key)
                if isinstance(reason, str) and re.fullmatch(
                    r"[A-Z][A-Z0-9_]{0,95}", reason
                ):
                    diagnostic_reasons.append(reason.lower())
        diagnostic_suffix = (
            "_" + "_".join(diagnostic_reasons) if diagnostic_reasons else ""
        )
        if isinstance(status, str) and re.fullmatch(r"[a-z-]+", status):
            fail(
                f"{label}_unexpected_status_{status.replace('-', '_')}"
                f"{diagnostic_suffix}"
            )
        fail(f"{label}_unexpected_status")
    if not isinstance(value.get("segments"), list) or not value["segments"]:
        fail(f"{label}_segments_missing")
    if not isinstance(value.get("sources"), list) or not value["sources"]:
        fail(f"{label}_sources_missing")
    request_id = value.get("request_id")
    if not isinstance(request_id, str) or HEX.fullmatch(request_id) is None:
        fail(f"{label}_request_identity_invalid")
    return value


def cited_identifiers(response: Mapping[str, Any], label: str) -> set[str]:
    used = {
        citation
        for segment in response["segments"]
        if isinstance(segment, Mapping)
        for citation in segment.get("citation_ids", [])
        if isinstance(citation, str)
    }
    identifiers: set[str] = set()
    for source in response["sources"]:
        if not isinstance(source, Mapping):
            fail(f"{label}_source_contract_invalid")
        identifier = source.get("document_identifier")
        excerpts = source.get("excerpts")
        if not isinstance(identifier, str) or not isinstance(excerpts, list):
            fail(f"{label}_source_contract_invalid")
        citations = {
            excerpt.get("citation_id")
            for excerpt in excerpts
            if isinstance(excerpt, Mapping)
            and isinstance(excerpt.get("citation_id"), str)
        }
        if citations & used:
            identifiers.add(identifier)
    return identifiers


def require_identifiers(
    response: Mapping[str, Any], expected: Sequence[str], label: str
) -> None:
    returned = {
        source.get("document_identifier")
        for source in response["sources"]
        if isinstance(source, Mapping)
        and isinstance(source.get("document_identifier"), str)
    }
    cited = cited_identifiers(response, label)
    missing_returned = sorted(set(expected) - returned)
    if missing_returned:
        fail(f"{label}_required_documents_missing")
    missing_cited = sorted(set(expected) - cited)
    if missing_cited:
        fail(f"{label}_required_documents_not_cited")


def require_catalog_categories(response: Mapping[str, Any], label: str) -> None:
    citation_identifiers: dict[str, str] = {}
    for source in response["sources"]:
        if not isinstance(source, Mapping):
            fail(f"{label}_source_contract_invalid")
        identifier = source.get("document_identifier")
        excerpts = source.get("excerpts")
        if not isinstance(identifier, str) or not isinstance(excerpts, list):
            fail(f"{label}_source_contract_invalid")
        for excerpt in excerpts:
            if not isinstance(excerpt, Mapping):
                fail(f"{label}_source_contract_invalid")
            citation_id = excerpt.get("citation_id")
            if not isinstance(citation_id, str):
                fail(f"{label}_source_contract_invalid")
            citation_identifiers[citation_id] = identifier

    department_segment = False
    related_segment = False
    for segment in response["segments"]:
        if not isinstance(segment, Mapping):
            fail(f"{label}_segment_contract_invalid")
        text = segment.get("text")
        citations = segment.get("citation_ids")
        if not isinstance(text, str) or not isinstance(citations, list):
            fail(f"{label}_segment_contract_invalid")
        identifiers = {
            citation_identifiers[citation_id]
            for citation_id in citations
            if isinstance(citation_id, str) and citation_id in citation_identifiers
        }
        has_department = bool(identifiers & LEGAL_DEPARTMENT_IDENTIFIERS)
        has_related = bool(identifiers & LEGAL_RELATED_IDENTIFIERS)
        if has_department and not has_related and "legal" in text.lower():
            department_segment = True
        if has_related and not has_department:
            related_segment = True
    if not department_segment or not related_segment:
        fail(f"{label}_catalog_categories_missing")


def response_history(response: Mapping[str, Any], label: str) -> str:
    text = " ".join(
        str(segment.get("text", "")).strip()
        for segment in response["segments"]
        if isinstance(segment, Mapping) and str(segment.get("text", "")).strip()
    )
    if not text:
        fail(f"{label}_history_text_missing")
    return text


def require_access_authorization_content(
    response: Mapping[str, Any], label: str
) -> None:
    text = response_history(response, label).casefold()
    information_terms = {
        term
        for term in (
            "identity", "sponsor", "role", "system", "date", "approval",
            "owner", "expiration",
        )
        if term in text
    }
    process_terms = {
        term
        for term in (
            "submit", "intake", "validate", "review", "apply", "record",
            "approve",
        )
        if term in text
    }
    if len(information_terms) < 3:
        fail(f"{label}_required_information_incomplete")
    if len(process_terms) < 2:
        fail(f"{label}_process_incomplete")


def response_references(response: Mapping[str, Any], label: str) -> list[dict[str, Any]]:
    references: list[dict[str, Any]] = []
    for source in response["sources"]:
        if not isinstance(source, Mapping):
            fail(f"{label}_source_contract_invalid")
        source_id = source.get("source_id")
        source_label = source.get("source_label")
        if (
            not isinstance(source_id, str)
            or HEX.fullmatch(source_id) is None
            or not isinstance(source_label, str)
        ):
            fail(f"{label}_source_reference_invalid")
        references.append(
            {
                "citation_id": None,
                "source_id": source_id,
                "source_label": source_label,
            }
        )
    return references


def _capture_canary(
    failures: list[str],
    operation: Callable[[], Any],
) -> Any | None:
    """Retain one safe canary reason while allowing independent cases to run."""

    try:
        return operation()
    except CanaryError as error:
        reason = str(error)
        if reason not in failures:
            failures.append(reason)
            print(f"catalog_routing_canary_failure={reason}", file=sys.stderr)
        return None


def execute(
    endpoint: str,
    *,
    exchange: Callable[[str, bytes], tuple[int, bytes]] = post,
) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    failures: list[str] = []

    first_exchange = _capture_canary(
        failures,
        lambda: exchange(endpoint, request_body("legal-first", LEGAL_QUESTION)),
    )
    first = (
        None
        if first_exchange is None
        else _capture_canary(
            failures,
            lambda: decode_answer(*first_exchange, "legal_first_turn"),
        )
    )
    first_set: set[str] | None = None
    if first is not None:
        _capture_canary(
            failures,
            lambda: require_identifiers(first, LEGAL_IDENTIFIERS, "legal_first_turn"),
        )
        _capture_canary(
            failures,
            lambda: require_catalog_categories(first, "legal_first_turn"),
        )
        first_set = _capture_canary(
            failures,
            lambda: cited_identifiers(first, "legal_first_turn"),
        )
        results.append({"case": "legal_first_turn", "request_id": first["request_id"]})

    if first is None:
        _capture_canary(
            failures,
            lambda: fail("legal_repeated_turn_dependency_unavailable"),
        )
    else:
        history_text = _capture_canary(
            failures, lambda: response_history(first, "legal_first_turn")
        )
        references = _capture_canary(
            failures, lambda: response_references(first, "legal_first_turn")
        )
        repeated_history = (
            {
                "content": LEGAL_QUESTION,
                "role": "user",
                "turn_id": identity("v13-56-repeat-history-user"),
            },
            {
                "content": history_text or "Prior catalog answer unavailable.",
                "role": "assistant",
                "turn_id": identity("v13-56-repeat-history-assistant"),
            },
        )
        repeated_exchange = _capture_canary(
            failures,
            lambda: exchange(
                endpoint,
                request_body(
                    "legal-repeat",
                    LEGAL_QUESTION,
                    history=repeated_history,
                    source_references=references or (),
                ),
            ),
        )
        repeated = (
            None
            if repeated_exchange is None
            else _capture_canary(
                failures,
                lambda: decode_answer(*repeated_exchange, "legal_repeated_turn"),
            )
        )
        if repeated is not None:
            _capture_canary(
                failures,
                lambda: require_identifiers(
                    repeated, LEGAL_IDENTIFIERS, "legal_repeated_turn"
                ),
            )
            _capture_canary(
                failures,
                lambda: require_catalog_categories(repeated, "legal_repeated_turn"),
            )
            repeated_set = _capture_canary(
                failures,
                lambda: cited_identifiers(repeated, "legal_repeated_turn"),
            )
            if first_set is not None and repeated_set != first_set:
                _capture_canary(
                    failures,
                    lambda: fail("legal_repeat_document_set_changed"),
                )
            results.append(
                {"case": "legal_repeated_turn", "request_id": repeated["request_id"]}
            )

    clarification_history = (
        {
            "content": LEGAL_QUESTION,
            "role": "user",
            "turn_id": identity("v13-56-all-history-user-1"),
        },
        {
            "content": (
                "Could you specify which area of legal work or specific compliance "
                "topics you are interested in?"
            ),
            "role": "assistant",
            "turn_id": identity("v13-56-all-history-assistant-1"),
        },
        {
            "content": "No, I need to know all of them.",
            "role": "user",
            "turn_id": identity("v13-56-all-history-user-2"),
        },
        {
            "content": (
                "Do you mean general corporate policies, department procedures, "
                "or compliance frameworks?"
            ),
            "role": "assistant",
            "turn_id": identity("v13-56-all-history-assistant-2"),
        },
    )
    all_references = (
        ()
        if first is None
        else _capture_canary(
            failures, lambda: response_references(first, "legal_first_turn")
        )
        or ()
    )
    all_exchange = _capture_canary(
        failures,
        lambda: exchange(
            endpoint,
            request_body(
                "legal-all",
                "Data privacy, contract management, and ethics.",
                history=clarification_history,
                source_references=all_references,
            ),
        ),
    )
    all_response = (
        None
        if all_exchange is None
        else _capture_canary(
            failures,
            lambda: decode_answer(*all_exchange, "legal_all_followup"),
        )
    )
    if all_response is not None:
        _capture_canary(
            failures,
            lambda: require_identifiers(
                all_response, LEGAL_IDENTIFIERS, "legal_all_followup"
            ),
        )
        _capture_canary(
            failures,
            lambda: require_catalog_categories(all_response, "legal_all_followup"),
        )
        results.append(
            {"case": "legal_all_followup", "request_id": all_response["request_id"]}
        )

    identifier_question = (
        "Does 99 TST 2001 require a form? Can you provide the complete procedure?"
    )
    direct_exchange = _capture_canary(
        failures,
        lambda: exchange(
            endpoint, request_body("identifier-direct", identifier_question)
        ),
    )
    direct_identifier = (
        None
        if direct_exchange is None
        else _capture_canary(
            failures,
            lambda: decode_answer(*direct_exchange, "identifier_direct"),
        )
    )
    if direct_identifier is not None:
        _capture_canary(
            failures,
            lambda: require_identifiers(
                direct_identifier,
                (CONTROLLED_MATERIALS_IDENTIFIER,),
                "identifier_direct",
            ),
        )
        results.append(
            {"case": "identifier_direct", "request_id": direct_identifier["request_id"]}
        )

    typo_history = (
        {
            "content": "Foe 99 TST 2001 require a form?",
            "role": "user",
            "turn_id": identity("v13-56-typo-history-user"),
        },
        {
            "content": (
                "Could you clarify what 99 TST 2001 refers to or provide the "
                "relevant document name?"
            ),
            "role": "assistant",
            "turn_id": identity("v13-56-typo-history-assistant"),
        },
    )
    recovery_exchange = _capture_canary(
        failures,
        lambda: exchange(
            endpoint,
            request_body(
                "identifier-recovery",
                identifier_question,
                history=typo_history,
            ),
        ),
    )
    recovered = (
        None
        if recovery_exchange is None
        else _capture_canary(
            failures,
            lambda: decode_answer(*recovery_exchange, "identifier_recovery"),
        )
    )
    if recovered is not None:
        _capture_canary(
            failures,
            lambda: require_identifiers(
                recovered,
                (CONTROLLED_MATERIALS_IDENTIFIER,),
                "identifier_recovery",
            ),
        )
        results.append(
            {"case": "identifier_recovery", "request_id": recovered["request_id"]}
        )

    access_exchange = _capture_canary(
        failures,
        lambda: exchange(
            endpoint,
            request_body(
                "access-authorization-direct", ACCESS_AUTHORIZATION_QUESTION
            ),
        ),
    )
    access_direct = (
        None
        if access_exchange is None
        else _capture_canary(
            failures,
            lambda: decode_answer(
                *access_exchange, "access_authorization_direct"
            ),
        )
    )
    if access_direct is not None:
        _capture_canary(
            failures,
            lambda: require_identifiers(
                access_direct,
                (ACCESS_AUTHORIZATION_IDENTIFIER,),
                "access_authorization_direct",
            ),
        )
        _capture_canary(
            failures,
            lambda: require_access_authorization_content(
                access_direct, "access_authorization_direct"
            ),
        )
        results.append(
            {
                "case": "access_authorization_direct",
                "request_id": access_direct["request_id"],
            }
        )

    if access_direct is None:
        _capture_canary(
            failures,
            lambda: fail("access_authorization_followup_dependency_unavailable"),
        )
    else:
        access_history = (
            {
                "content": ACCESS_AUTHORIZATION_QUESTION,
                "role": "user",
                "turn_id": identity("v13-57-access-history-user"),
            },
            {
                "content": response_history(
                    access_direct, "access_authorization_direct"
                ),
                "role": "assistant",
                "turn_id": identity("v13-57-access-history-assistant"),
            },
        )
        access_followup_exchange = _capture_canary(
            failures,
            lambda: exchange(
                endpoint,
                request_body(
                    "access-authorization-followup",
                    (
                        "For TST-9050, summarize the process and the information "
                        "I should prepare."
                    ),
                    history=access_history,
                    source_references=response_references(
                        access_direct, "access_authorization_direct"
                    ),
                ),
            ),
        )
        access_followup = (
            None
            if access_followup_exchange is None
            else _capture_canary(
                failures,
                lambda: decode_answer(
                    *access_followup_exchange, "access_authorization_followup"
                ),
            )
        )
        if access_followup is not None:
            _capture_canary(
                failures,
                lambda: require_identifiers(
                    access_followup,
                    (ACCESS_AUTHORIZATION_IDENTIFIER,),
                    "access_authorization_followup",
                ),
            )
            _capture_canary(
                failures,
                lambda: require_access_authorization_content(
                    access_followup, "access_authorization_followup"
                ),
            )
            results.append(
                {
                    "case": "access_authorization_followup",
                    "request_id": access_followup["request_id"],
                }
            )

    exception_direct_exchange = _capture_canary(
        failures,
        lambda: exchange(
            endpoint,
            request_body(
                "controlled-access-exception-direct",
                CONTROLLED_ACCESS_EXCEPTION_QUESTION,
            ),
        ),
    )
    exception_direct = (
        None
        if exception_direct_exchange is None
        else _capture_canary(
            failures,
            lambda: decode_answer(
                *exception_direct_exchange, "controlled_access_exception_direct"
            ),
        )
    )
    if exception_direct is not None:
        _capture_canary(
            failures,
            lambda: require_identifiers(
                exception_direct,
                (CONTROLLED_ACCESS_EXCEPTION_IDENTIFIER,),
                "controlled_access_exception_direct",
            ),
        )
        results.append(
            {
                "case": "controlled_access_exception_direct",
                "request_id": exception_direct["request_id"],
            }
        )

    if exception_direct is None:
        _capture_canary(
            failures,
            lambda: fail("controlled_access_exception_followup_dependency_unavailable"),
        )
    else:
        # Reproduce the observed UI envelope exactly enough to prove that an
        # earlier declarative answer mentioning "department" cannot hijack a
        # later explicit document identifier as a department-name reply.
        exception_history = (
            {
                "content": "I am new and need to submit access requests. What should I do?",
                "role": "user",
                "turn_id": identity("v13-58-exception-history-user"),
            },
            {
                "content": (
                    "If facts regarding the request are ambiguous, request the "
                    "missing operational fact rather than guessing details such "
                    "as the department, incident type, or authority."
                ),
                "role": "assistant",
                "turn_id": identity("v13-58-exception-history-assistant"),
            },
        )
        exception_followup_exchange = _capture_canary(
            failures,
            lambda: exchange(
                endpoint,
                request_body(
                    "controlled-access-exception-followup",
                    CONTROLLED_ACCESS_EXCEPTION_QUESTION,
                    history=exception_history,
                    source_references=response_references(
                        exception_direct, "controlled_access_exception_direct"
                    ),
                ),
            ),
        )
        exception_followup = (
            None
            if exception_followup_exchange is None
            else _capture_canary(
                failures,
                lambda: decode_answer(
                    *exception_followup_exchange,
                    "controlled_access_exception_followup",
                ),
            )
        )
        if exception_followup is not None:
            _capture_canary(
                failures,
                lambda: require_identifiers(
                    exception_followup,
                    (CONTROLLED_ACCESS_EXCEPTION_IDENTIFIER,),
                    "controlled_access_exception_followup",
                ),
            )
            results.append(
                {
                    "case": "controlled_access_exception_followup",
                    "request_id": exception_followup["request_id"],
                }
            )
    if failures:
        fail(failures[0] if len(failures) == 1 else f"multiple_canary_failures_{len(failures)}")
    return results


def mock_response(identifiers: Sequence[str]) -> dict[str, Any]:
    sources = []
    segments = []
    for index, identifier in enumerate(identifiers, start=1):
        citation_id = identity(f"v13-56-mock-citation-{index}")
        sources.append(
            {
                "display_name": f"Document {index}",
                "document_identifier": identifier,
                "excerpts": [{"citation_id": citation_id}],
                "source_id": identity(f"v13-56-mock-source-{index}"),
                "source_label": f"Source {index}",
            }
        )
        segments.append(
            {
                "citation_ids": [citation_id],
                "text": (
                    "Legal and Compliance department document."
                    if identifier in LEGAL_DEPARTMENT_IDENTIFIERS
                    else (
                        "Submit identity, sponsor, role, systems, dates, and "
                        "approvals for intake, validation, review, and recording."
                        if identifier == ACCESS_AUTHORIZATION_IDENTIFIER
                        else "Related document."
                    )
                ),
            }
        )
    return {
        "request_id": identity("v13-56-mock-request"),
        "schema": RESPONSE_SCHEMA,
        "segments": segments,
        "sources": sources,
        "status": "answered",
    }


def self_test() -> None:
    response = mock_response(LEGAL_IDENTIFIERS)
    decoded = decode_answer(
        200,
        canonical_bytes(response),
        "self_test",
        emit_failure_observation=False,
    )
    require_identifiers(decoded, LEGAL_IDENTIFIERS, "self_test")
    require_catalog_categories(decoded, "self_test")
    references = response_references(decoded, "self_test")
    assert len(references) == len(LEGAL_IDENTIFIERS)
    assert all(item["citation_id"] is None for item in references)
    missing = json.loads(canonical_bytes(response))
    missing["sources"].pop()
    try:
        require_identifiers(missing, LEGAL_IDENTIFIERS, "self_test")
    except CanaryError as error:
        assert str(error) == "self_test_required_documents_missing"
    else:
        raise AssertionError("expected missing-document rejection")
    mixed = json.loads(canonical_bytes(response))
    mixed["segments"] = [
        {
            "citation_ids": [
                excerpt["citation_id"]
                for source in mixed["sources"]
                for excerpt in source["excerpts"]
            ],
            "text": "Legal and Compliance documents and other documents.",
        }
    ]
    try:
        require_catalog_categories(mixed, "self_test")
    except CanaryError as error:
        assert str(error) == "self_test_catalog_categories_missing"
    else:
        raise AssertionError("expected unseparated-catalog rejection")
    insufficient = {
        "diagnostics": {
            "relevance_reason_code": "CITABLE_EVIDENCE_SUPPORT_INSUFFICIENT",
            "sufficiency_reason_code": "RELEVANCE_INSUFFICIENT",
        },
        "request_id": identity("v13-56-mock-insufficient-request"),
        "schema": RESPONSE_SCHEMA,
        "segments": [],
        "sources": [],
        "status": "insufficient-evidence",
    }
    try:
        decode_answer(
            200,
            canonical_bytes(insufficient),
            "self_test",
            emit_failure_observation=False,
        )
    except CanaryError as error:
        assert str(error) == (
            "self_test_unexpected_status_insufficient_evidence_"
            "citable_evidence_support_insufficient_relevance_insufficient"
        )
    else:
        raise AssertionError("expected diagnostic status rejection")
    exchanges: list[str] = []

    def mock_exchange(_endpoint: str, body: bytes) -> tuple[int, bytes]:
        request = json.loads(body.decode("utf-8"))
        question = request["message"]
        exchanges.append(question)
        identifiers = (
            (CONTROLLED_MATERIALS_IDENTIFIER,)
            if CONTROLLED_MATERIALS_IDENTIFIER in question
            else (
                (CONTROLLED_ACCESS_EXCEPTION_IDENTIFIER,)
                if CONTROLLED_ACCESS_EXCEPTION_IDENTIFIER in question
                else (
                    (ACCESS_AUTHORIZATION_IDENTIFIER,)
                    if ACCESS_AUTHORIZATION_IDENTIFIER in question
                    else LEGAL_IDENTIFIERS
                )
            )
        )
        return 200, canonical_bytes(mock_response(identifiers))

    results = execute("http://127.0.0.1:1/v1/chat", exchange=mock_exchange)
    assert len(results) == 9
    assert len(exchanges) == 9

    failed_exchanges: list[str] = []

    def mixed_catalog_exchange(_endpoint: str, body: bytes) -> tuple[int, bytes]:
        request = json.loads(body.decode("utf-8"))
        question = request["message"]
        failed_exchanges.append(question)
        identifiers = (
            (CONTROLLED_MATERIALS_IDENTIFIER,)
            if CONTROLLED_MATERIALS_IDENTIFIER in question
            else (
                (CONTROLLED_ACCESS_EXCEPTION_IDENTIFIER,)
                if CONTROLLED_ACCESS_EXCEPTION_IDENTIFIER in question
                else (
                    (ACCESS_AUTHORIZATION_IDENTIFIER,)
                    if ACCESS_AUTHORIZATION_IDENTIFIER in question
                    else LEGAL_IDENTIFIERS
                )
            )
        )
        value = mock_response(identifiers)
        if identifiers == LEGAL_IDENTIFIERS:
            value["segments"] = [
                {
                    "citation_ids": [
                        excerpt["citation_id"]
                        for source in value["sources"]
                        for excerpt in source["excerpts"]
                    ],
                    "text": "Legal and Compliance documents and other documents.",
                }
            ]
        return 200, canonical_bytes(value)

    captured_failures = io.StringIO()
    try:
        with contextlib.redirect_stderr(captured_failures):
            execute(
                "http://127.0.0.1:1/v1/chat",
                exchange=mixed_catalog_exchange,
            )
    except CanaryError as error:
        assert str(error) == "multiple_canary_failures_3"
    else:
        raise AssertionError("expected aggregated catalog-canary rejection")
    assert len(failed_exchanges) == 9
    assert captured_failures.getvalue().count("catalog_routing_canary_failure=") == 3
    print("v1_3_catalog_routing_evaluator_self_test=pass")


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
    results = execute(arguments.endpoint)
    print(
        "catalog_routing=pass;cases=9/9;legal_first_turn=answered;"
        "legal_repeat_equivalent=true;legal_all_complete=true;"
        "identifier_direct=answered;identifier_recovery=answered;"
        "access_authorization_direct=answered;"
        "access_authorization_followup=answered;"
        "controlled_access_exception_direct=answered;"
        "controlled_access_exception_followup=answered;"
        f"request_ids={','.join(item['request_id'] for item in results)}"
    )
    print("v1_3_catalog_routing_evaluation=pass")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except CanaryError as error:
        print(
            f"v1_3_catalog_routing_evaluation=blocked;reason={error}",
            file=sys.stderr,
        )
        raise SystemExit(1)
