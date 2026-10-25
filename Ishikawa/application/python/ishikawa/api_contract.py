"""Versioned client-safe multi-turn chat request and response contract."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from typing import Any, Mapping, NoReturn, Sequence

from .canonical import canonical_json_bytes, domain_digest


REQUEST_SCHEMA = "ishikawa.chat-request.v1"
RESPONSE_SCHEMA = "ishikawa.chat-response.v5"
STATUSES = (
    "answered",
    "clarification-required",
    "insufficient-evidence",
    "out-of-scope",
    "security-rejected",
    "context-limit",
    "temporarily-unavailable",
    "internal-error",
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
ANCHOR_KINDS = frozenset({"table", "row", "form", "field", "procedure", "step"})
HEX = re.compile(r"^[0-9a-f]{64}$")
SOURCE_LABEL = re.compile(r"^Source [1-9][0-9]*$")
CLASS_ID = re.compile(r"^[a-z][a-z0-9_]{1,63}$")
DOCUMENT_KEY = re.compile(r"^[a-z0-9]+(?:[._-][a-z0-9]+)*$")
ERROR_CODE = re.compile(r"^[A-Z][A-Z0-9_]{2,63}$")


class ApiContractError(ValueError):
    """Stable client-envelope contract failure."""

    def __init__(self, reason_code: str):
        self.reason_code = reason_code
        super().__init__(reason_code)


def _exact_mapping(value: Any, fields: frozenset[str], reason: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping) or set(value) != fields:
        raise ApiContractError(reason)
    return value


def _text(value: Any, maximum: int, reason: str) -> str:
    if (
        not isinstance(value, str)
        or not value.strip()
        or value != value.strip()
        or len(value) > maximum
        or "\x00" in value
    ):
        raise ApiContractError(reason)
    return value


def _identity(value: Any, reason: str) -> str:
    if not isinstance(value, str) or HEX.fullmatch(value) is None:
        raise ApiContractError(reason)
    return value


def _positive_integer(value: Any, maximum: int, reason: str) -> int:
    if type(value) is not int or not 1 <= value <= maximum:
        raise ApiContractError(reason)
    return value


@dataclass(frozen=True, slots=True)
class ApiPolicy:
    maximum_request_bytes: int
    maximum_question_characters: int
    maximum_history_turns: int
    maximum_history_characters: int
    maximum_source_references: int
    maximum_filter_values: int
    maximum_sources: int
    maximum_excerpts_per_source: int
    maximum_segments: int
    digest: str


def validate_api_profile(value: Any) -> ApiPolicy:
    root = _exact_mapping(
        value,
        frozenset({"schema_version", "transport", "limits", "features", "statuses"}),
        "API_PROFILE_FIELDS_INVALID",
    )
    if root["schema_version"] != 1 or type(root["schema_version"]) is not int:
        raise ApiContractError("API_PROFILE_VERSION_INVALID")
    transport = _exact_mapping(
        root["transport"],
        frozenset({"chat_path", "document_path", "method", "media_type", "streaming"}),
        "API_TRANSPORT_FIELDS_INVALID",
    )
    limits = _exact_mapping(
        root["limits"],
        frozenset(
            {
                "maximum_request_bytes",
                "maximum_question_characters",
                "maximum_history_turns",
                "maximum_history_characters",
                "maximum_source_references",
                "maximum_filter_values",
                "maximum_sources",
                "maximum_excerpts_per_source",
                "maximum_segments",
            }
        ),
        "API_LIMIT_FIELDS_INVALID",
    )
    features = _exact_mapping(
        root["features"],
        frozenset(
            {
                "reconstructed_document_view",
                "original_pdf_open",
                "original_pdf_download",
            }
        ),
        "API_FEATURE_FIELDS_INVALID",
    )
    expected_transport = {
        "chat_path": "/v1/chat",
        "document_path": "/v1/document",
        "method": "POST",
        "media_type": "application/json",
        "streaming": False,
    }
    expected_limits = {
        "maximum_request_bytes": 262144,
        "maximum_question_characters": 16384,
        "maximum_history_turns": 12,
        "maximum_history_characters": 65536,
        "maximum_source_references": 20,
        "maximum_filter_values": 20,
        "maximum_sources": 20,
        "maximum_excerpts_per_source": 20,
        "maximum_segments": 64,
    }
    if (
        dict(transport) != expected_transport
        or dict(limits) != expected_limits
        or dict(features) != {
            "reconstructed_document_view": True,
            "original_pdf_open": False,
            "original_pdf_download": False,
        }
        or root["statuses"] != list(STATUSES)
    ):
        raise ApiContractError("API_PROFILE_CONTRACT_INVALID")
    canonical = {
        "features": dict(features),
        "limits": dict(limits),
        "schema_version": 1,
        "statuses": list(STATUSES),
        "transport": dict(transport),
    }
    return ApiPolicy(
        **expected_limits,
        digest=domain_digest("ishikawa.api-profile.v1", canonical),
    )


@dataclass(frozen=True, slots=True)
class ApiHistoryTurn:
    turn_id: str
    role: str
    content: str

    def __post_init__(self) -> None:
        _identity(self.turn_id, "REQUEST_HISTORY_TURN_ID_INVALID")
        if self.role not in ("user", "assistant"):
            raise ApiContractError("REQUEST_HISTORY_ROLE_INVALID")
        _text(self.content, 131072, "REQUEST_HISTORY_CONTENT_INVALID")

    def canonical(self) -> dict[str, str]:
        return {"content": self.content, "role": self.role, "turn_id": self.turn_id}


@dataclass(frozen=True, slots=True)
class ApiSourceReference:
    source_id: str
    source_label: str
    citation_id: str | None

    def __post_init__(self) -> None:
        _identity(self.source_id, "REQUEST_SOURCE_ID_INVALID")
        if not isinstance(self.source_label, str) or SOURCE_LABEL.fullmatch(self.source_label) is None:
            raise ApiContractError("REQUEST_SOURCE_LABEL_INVALID")
        if self.citation_id is not None:
            _identity(self.citation_id, "REQUEST_CITATION_ID_INVALID")

    def canonical(self) -> dict[str, Any]:
        return {
            "citation_id": self.citation_id,
            "source_id": self.source_id,
            "source_label": self.source_label,
        }


@dataclass(frozen=True, slots=True)
class ApiFilters:
    document_classes: tuple[str, ...]
    document_keys: tuple[str, ...]

    def canonical(self) -> dict[str, list[str]]:
        return {
            "document_classes": list(self.document_classes),
            "document_keys": list(self.document_keys),
        }


@dataclass(frozen=True, slots=True)
class ApiChatRequest:
    conversation_id: str
    turn_id: str
    message: str
    history: tuple[ApiHistoryTurn, ...]
    source_references: tuple[ApiSourceReference, ...]
    filters: ApiFilters
    envelope_identity: str

    def canonical(self) -> dict[str, Any]:
        return {
            "conversation_id": self.conversation_id,
            "filters": self.filters.canonical(),
            "history": [turn.canonical() for turn in self.history],
            "message": self.message,
            "schema": REQUEST_SCHEMA,
            "source_references": [reference.canonical() for reference in self.source_references],
            "turn_id": self.turn_id,
        }


def _reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ApiContractError("REQUEST_JSON_DUPLICATE_FIELD")
        result[key] = value
    return result


def _reject_constant(_value: str) -> NoReturn:
    raise ApiContractError("REQUEST_JSON_NONFINITE_NUMBER")


def decode_chat_request(body: bytes, policy: ApiPolicy) -> ApiChatRequest:
    if not isinstance(policy, ApiPolicy):
        raise ApiContractError("API_POLICY_INVALID")
    if not isinstance(body, bytes) or not body or len(body) > policy.maximum_request_bytes:
        raise ApiContractError("REQUEST_BODY_SIZE_INVALID")
    try:
        value = json.loads(
            body.decode("utf-8"),
            object_pairs_hook=_reject_duplicates,
            parse_constant=_reject_constant,
        )
    except ApiContractError:
        raise
    except (UnicodeError, json.JSONDecodeError) as error:
        raise ApiContractError("REQUEST_JSON_INVALID") from error
    return parse_chat_request(value, policy)


def _string_list(value: Any, pattern: re.Pattern[str], maximum: int, reason: str) -> tuple[str, ...]:
    if (
        not isinstance(value, list)
        or len(value) > maximum
        or any(not isinstance(item, str) or pattern.fullmatch(item) is None for item in value)
        or len(set(value)) != len(value)
    ):
        raise ApiContractError(reason)
    return tuple(value)


def parse_chat_request(value: Any, policy: ApiPolicy) -> ApiChatRequest:
    if not isinstance(policy, ApiPolicy):
        raise ApiContractError("API_POLICY_INVALID")
    root = _exact_mapping(
        value,
        frozenset(
            {
                "schema", "conversation_id", "turn_id", "message", "history",
                "source_references", "filters",
            }
        ),
        "REQUEST_FIELDS_INVALID",
    )
    if root["schema"] != REQUEST_SCHEMA:
        raise ApiContractError("REQUEST_SCHEMA_INVALID")
    conversation_id = _identity(root["conversation_id"], "REQUEST_CONVERSATION_ID_INVALID")
    turn_id = _identity(root["turn_id"], "REQUEST_TURN_ID_INVALID")
    message = _text(root["message"], policy.maximum_question_characters, "REQUEST_MESSAGE_INVALID")

    raw_history = root["history"]
    if not isinstance(raw_history, list) or len(raw_history) > policy.maximum_history_turns:
        raise ApiContractError("REQUEST_HISTORY_LIMIT")
    history: list[ApiHistoryTurn] = []
    expected_role = "user"
    for raw_turn in raw_history:
        item = _exact_mapping(
            raw_turn, frozenset({"turn_id", "role", "content"}), "REQUEST_HISTORY_FIELDS_INVALID"
        )
        turn = ApiHistoryTurn(item["turn_id"], item["role"], item["content"])
        if turn.role != expected_role:
            raise ApiContractError("REQUEST_HISTORY_ORDER_INVALID")
        expected_role = "assistant" if expected_role == "user" else "user"
        history.append(turn)
    if history and history[-1].role != "assistant":
        raise ApiContractError("REQUEST_HISTORY_ORDER_INVALID")
    history_ids = [item.turn_id for item in history]
    if len(set(history_ids)) != len(history_ids) or turn_id in history_ids:
        raise ApiContractError("REQUEST_TURN_ID_REUSED")
    if sum(len(item.content) for item in history) > policy.maximum_history_characters:
        raise ApiContractError("REQUEST_HISTORY_LIMIT")

    raw_references = root["source_references"]
    if not isinstance(raw_references, list) or len(raw_references) > policy.maximum_source_references:
        raise ApiContractError("REQUEST_SOURCE_REFERENCE_LIMIT")
    references: list[ApiSourceReference] = []
    for raw_reference in raw_references:
        item = _exact_mapping(
            raw_reference,
            frozenset({"source_id", "source_label", "citation_id"}),
            "REQUEST_SOURCE_REFERENCE_FIELDS_INVALID",
        )
        references.append(ApiSourceReference(item["source_id"], item["source_label"], item["citation_id"]))
    if (
        len({item.source_id for item in references}) != len(references)
        or len({item.source_label for item in references}) != len(references)
        or len({item.citation_id for item in references if item.citation_id is not None})
        != len([item for item in references if item.citation_id is not None])
    ):
        raise ApiContractError("REQUEST_SOURCE_REFERENCE_DUPLICATE")

    raw_filters = _exact_mapping(
        root["filters"],
        frozenset({"document_classes", "document_keys"}),
        "REQUEST_FILTER_FIELDS_INVALID",
    )
    filters = ApiFilters(
        _string_list(
            raw_filters["document_classes"], CLASS_ID, policy.maximum_filter_values,
            "REQUEST_CLASS_FILTER_INVALID",
        ),
        _string_list(
            raw_filters["document_keys"], DOCUMENT_KEY, policy.maximum_filter_values,
            "REQUEST_DOCUMENT_FILTER_INVALID",
        ),
    )
    canonical = {
        "conversation_id": conversation_id,
        "filters": filters.canonical(),
        "history": [item.canonical() for item in history],
        "message": message,
        "schema": REQUEST_SCHEMA,
        "source_references": [item.canonical() for item in references],
        "turn_id": turn_id,
    }
    if len(canonical_json_bytes(canonical)) > policy.maximum_request_bytes:
        raise ApiContractError("REQUEST_BODY_SIZE_INVALID")
    return ApiChatRequest(
        conversation_id,
        turn_id,
        message,
        tuple(history),
        tuple(references),
        filters,
        domain_digest("ishikawa.chat-request-envelope.v1", canonical),
    )


@dataclass(frozen=True, slots=True)
class ApiSegment:
    text: str
    citation_ids: tuple[str, ...]

    def __post_init__(self) -> None:
        _text(self.text, 65536, "RESPONSE_SEGMENT_TEXT_INVALID")
        if (
            not self.citation_ids
            or len(set(self.citation_ids)) != len(self.citation_ids)
            or any(not isinstance(item, str) or HEX.fullmatch(item) is None for item in self.citation_ids)
        ):
            raise ApiContractError("RESPONSE_SEGMENT_CITATIONS_INVALID")

    def canonical(self) -> dict[str, Any]:
        return {"citation_ids": list(self.citation_ids), "text": self.text}


@dataclass(frozen=True, slots=True)
class ApiExcerpt:
    citation_id: str
    excerpt: str
    page_start: int
    page_end: int
    structural_path: tuple[str, ...]
    anchor_kind: str | None = None
    anchor_label: str | None = None

    def __post_init__(self) -> None:
        _identity(self.citation_id, "RESPONSE_CITATION_ID_INVALID")
        _text(self.excerpt, 262144, "RESPONSE_EXCERPT_INVALID")
        if (
            type(self.page_start) is not int
            or type(self.page_end) is not int
            or self.page_start < 1
            or self.page_end < self.page_start
        ):
            raise ApiContractError("RESPONSE_PAGE_RANGE_INVALID")
        if any(
            not isinstance(item, str) or not item.strip() or item != item.strip()
            for item in self.structural_path
        ):
            raise ApiContractError("RESPONSE_STRUCTURAL_PATH_INVALID")
        if (self.anchor_kind is None) != (self.anchor_label is None):
            raise ApiContractError("RESPONSE_ANCHOR_INVALID")
        if self.anchor_kind is not None:
            if self.anchor_kind not in ANCHOR_KINDS:
                raise ApiContractError("RESPONSE_ANCHOR_INVALID")
            _text(self.anchor_label, 512, "RESPONSE_ANCHOR_INVALID")

    def canonical(self) -> dict[str, Any]:
        return {
            "anchor": None
            if self.anchor_kind is None
            else {"kind": self.anchor_kind, "label": self.anchor_label},
            "citation_id": self.citation_id,
            "excerpt": self.excerpt,
            "page_end": self.page_end,
            "page_start": self.page_start,
            "structural_path": list(self.structural_path),
        }


@dataclass(frozen=True, slots=True)
class ApiSourceGroup:
    source_id: str
    source_label: str
    document_key: str
    document_identifier: str | None
    display_name: str
    document_class: str
    excerpts: tuple[ApiExcerpt, ...]
    page_count: int
    has_additional_sections: bool = False

    def __post_init__(self) -> None:
        _identity(self.source_id, "RESPONSE_SOURCE_ID_INVALID")
        if not isinstance(self.source_label, str) or SOURCE_LABEL.fullmatch(self.source_label) is None:
            raise ApiContractError("RESPONSE_SOURCE_LABEL_INVALID")
        if not isinstance(self.document_key, str) or DOCUMENT_KEY.fullmatch(self.document_key) is None:
            raise ApiContractError("RESPONSE_DOCUMENT_KEY_INVALID")
        if self.document_identifier is not None:
            _text(self.document_identifier, 512, "RESPONSE_DOCUMENT_IDENTIFIER_INVALID")
        _text(self.display_name, 512, "RESPONSE_DISPLAY_NAME_INVALID")
        if not isinstance(self.document_class, str) or CLASS_ID.fullmatch(self.document_class) is None:
            raise ApiContractError("RESPONSE_DOCUMENT_CLASS_INVALID")
        if not self.excerpts or any(not isinstance(item, ApiExcerpt) for item in self.excerpts):
            raise ApiContractError("RESPONSE_EXCERPTS_INVALID")
        _positive_integer(self.page_count, 1000000, "RESPONSE_PAGE_COUNT_INVALID")
        if any(excerpt.page_end > self.page_count for excerpt in self.excerpts):
            raise ApiContractError("RESPONSE_PAGE_COUNT_INVALID")
        if type(self.has_additional_sections) is not bool:
            raise ApiContractError("RESPONSE_ADDITIONAL_SECTIONS_INVALID")

    def canonical(self) -> dict[str, Any]:
        return {
            "display_name": self.display_name,
            "document_class": self.document_class,
            "document_identifier": self.document_identifier,
            "document_key": self.document_key,
            "excerpts": [item.canonical() for item in self.excerpts],
            "has_additional_sections": self.has_additional_sections,
            "page_count": self.page_count,
            "source_id": self.source_id,
            "source_label": self.source_label,
        }


@dataclass(frozen=True, slots=True)
class ApiContextBudget:
    """Client-safe token-window use measured for the completed request."""

    token_limit: int
    tokens_used: int
    tokens_remaining: int

    def __post_init__(self) -> None:
        if (
            type(self.token_limit) is not int
            or type(self.tokens_used) is not int
            or type(self.tokens_remaining) is not int
            or self.token_limit < 1
            or not 0 <= self.tokens_used <= self.token_limit
            or self.tokens_remaining != self.token_limit - self.tokens_used
        ):
            raise ApiContractError("RESPONSE_CONTEXT_BUDGET_INVALID")

    def canonical(self) -> dict[str, int]:
        return {
            "token_limit": self.token_limit,
            "tokens_remaining": self.tokens_remaining,
            "tokens_used": self.tokens_used,
        }


@dataclass(frozen=True, slots=True)
class ApiError:
    code: str
    message: str

    def __post_init__(self) -> None:
        if not isinstance(self.code, str) or ERROR_CODE.fullmatch(self.code) is None:
            raise ApiContractError("RESPONSE_ERROR_CODE_INVALID")
        _text(self.message, 2048, "RESPONSE_ERROR_MESSAGE_INVALID")

    def canonical(self) -> dict[str, str]:
        return {"code": self.code, "message": self.message}


@dataclass(frozen=True, slots=True)
class ApiDiagnostics:
    """Bounded, content-free measurements safe for the developer UI."""

    api_processing_ms: int
    scope_ms: int
    query_resolution_ms: int
    retrieval_ms: int
    generation_ms: int
    response_build_ms: int
    lane_states: tuple[tuple[str, str], ...] | None
    fused_result_count: int | None
    authorized_result_count: int | None
    reconstructed_result_count: int | None
    cited_result_count: int | None
    nomic_query_tokens: int | None
    gemma_prompt_tokens: int | None
    gemma_completion_tokens: int | None
    gemma_total_tokens: int | None
    context_tokens_used: int | None
    context_tokens_remaining: int | None
    context_token_limit: int | None
    generation_retry: bool
    prompt_target_tokens: int | None = None
    retrieval_stage_durations_ms: tuple[tuple[str, int], ...] | None = None
    relevance_reason_code: str | None = None
    sufficiency_reason_code: str | None = None
    selected_group_order: tuple[str, ...] | None = None

    def __post_init__(self) -> None:
        durations = (
            self.api_processing_ms,
            self.scope_ms,
            self.query_resolution_ms,
            self.retrieval_ms,
            self.generation_ms,
            self.response_build_ms,
        )
        if any(type(value) is not int or not 0 <= value <= 86400000 for value in durations):
            raise ApiContractError("RESPONSE_DIAGNOSTIC_TIMING_INVALID")
        if self.lane_states is not None and (
            tuple(name for name, _state in self.lane_states)
            != ("exact", "lexical", "vector")
            or any(
                state not in {"pass", "not_applicable", "failed"}
                for _name, state in self.lane_states
            )
        ):
            raise ApiContractError("RESPONSE_DIAGNOSTIC_LANES_INVALID")
        counts = (
            self.fused_result_count,
            self.authorized_result_count,
            self.reconstructed_result_count,
            self.cited_result_count,
            self.nomic_query_tokens,
            self.context_tokens_used,
            self.context_tokens_remaining,
            self.context_token_limit,
            self.prompt_target_tokens,
        )
        if any(
            value is not None
            and (type(value) is not int or not 0 <= value <= 100000000)
            for value in counts
        ):
            raise ApiContractError("RESPONSE_DIAGNOSTIC_COUNT_INVALID")
        result_counts = (
            self.fused_result_count,
            self.authorized_result_count,
            self.reconstructed_result_count,
            self.cited_result_count,
        )
        if (self.lane_states is None) != all(value is None for value in result_counts):
            raise ApiContractError("RESPONSE_DIAGNOSTIC_RETRIEVAL_INVALID")
        if self.lane_states is not None and any(value is None for value in result_counts):
            raise ApiContractError("RESPONSE_DIAGNOSTIC_RETRIEVAL_INVALID")
        gemma_tokens = (
            self.gemma_prompt_tokens,
            self.gemma_completion_tokens,
            self.gemma_total_tokens,
        )
        if not (
            all(value is None for value in gemma_tokens)
            or (
                all(type(value) is int and value >= 1 for value in gemma_tokens)
                and self.gemma_total_tokens
                == self.gemma_prompt_tokens + self.gemma_completion_tokens
            )
        ):
            raise ApiContractError("RESPONSE_DIAGNOSTIC_GEMMA_TOKENS_INVALID")
        context = (
            self.context_tokens_used,
            self.context_tokens_remaining,
            self.context_token_limit,
        )
        if not (
            all(value is None for value in context)
            or (
                all(type(value) is int for value in context)
                and self.context_token_limit >= 1
                and self.context_tokens_used + self.context_tokens_remaining
                == self.context_token_limit
            )
        ):
            raise ApiContractError("RESPONSE_DIAGNOSTIC_CONTEXT_INVALID")
        if type(self.generation_retry) is not bool:
            raise ApiContractError("RESPONSE_DIAGNOSTIC_RETRY_INVALID")
        if self.retrieval_stage_durations_ms is not None and (
            tuple(name for name, _duration in self.retrieval_stage_durations_ms)
            != (
                "nomic",
                "lexical_sql",
                "vector_sql",
                "fusion",
                "reconstruction",
                "tokenization",
            )
            or any(
                type(duration) is not int or not 0 <= duration <= 86400000
                for _name, duration in self.retrieval_stage_durations_ms
            )
        ):
            raise ApiContractError("RESPONSE_DIAGNOSTIC_RETRIEVAL_TIMING_INVALID")
        reason_pattern = re.compile(r"^[A-Z][A-Z0-9_]{0,95}$")
        if any(
            value is not None
            and (not isinstance(value, str) or reason_pattern.fullmatch(value) is None)
            for value in (self.relevance_reason_code, self.sufficiency_reason_code)
        ):
            raise ApiContractError("RESPONSE_DIAGNOSTIC_REASON_INVALID")
        if self.selected_group_order is not None and (
            not isinstance(self.selected_group_order, tuple)
            or len(self.selected_group_order) > 6
            or len(set(self.selected_group_order)) != len(self.selected_group_order)
            or any(
                not isinstance(value, str)
                or not value
                or len(value) > 1024
                or "\x00" in value
                for value in self.selected_group_order
            )
        ):
            raise ApiContractError("RESPONSE_DIAGNOSTIC_GROUP_ORDER_INVALID")

    def canonical(self) -> dict[str, Any]:
        return {
            "api_processing_ms": self.api_processing_ms,
            "context_tokens": None
            if self.context_token_limit is None
            else {
                "limit": self.context_token_limit,
                "remaining": self.context_tokens_remaining,
                "used": self.context_tokens_used,
            },
            "gemma_tokens": None
            if self.gemma_total_tokens is None
            else {
                "completion": self.gemma_completion_tokens,
                "prompt": self.gemma_prompt_tokens,
                "total": self.gemma_total_tokens,
            },
            "generation_retry": self.generation_retry,
            "lane_states": None
            if self.lane_states is None
            else {name: state for name, state in self.lane_states},
            "nomic_query_tokens": self.nomic_query_tokens,
            "prompt_target_tokens": self.prompt_target_tokens,
            "relevance_reason_code": self.relevance_reason_code,
            "result_counts": None
            if self.fused_result_count is None
            else {
                "authorized": self.authorized_result_count,
                "cited": self.cited_result_count,
                "fused": self.fused_result_count,
                "reconstructed": self.reconstructed_result_count,
            },
            "selected_group_order": None
            if self.selected_group_order is None
            else list(self.selected_group_order),
            "sufficiency_reason_code": self.sufficiency_reason_code,
            "timings_ms": {
                "generation": self.generation_ms,
                "query_resolution": self.query_resolution_ms,
                "response_build": self.response_build_ms,
                "retrieval": self.retrieval_ms,
                "retrieval_detail": None
                if self.retrieval_stage_durations_ms is None
                else {
                    name: duration
                    for name, duration in self.retrieval_stage_durations_ms
                },
                "scope": self.scope_ms,
            },
        }


@dataclass(frozen=True, slots=True)
class ApiChatResponse:
    body: dict[str, Any]
    envelope_identity: str

    def canonical_bytes(self) -> bytes:
        return canonical_json_bytes(self.body)


def build_chat_response(
    *,
    request: ApiChatRequest,
    request_id: str,
    status: str,
    segments: Sequence[ApiSegment] = (),
    sources: Sequence[ApiSourceGroup] = (),
    clarification: str | None = None,
    error: ApiError | None = None,
    context_budget: ApiContextBudget | None = None,
    policy: ApiPolicy,
) -> ApiChatResponse:
    if not isinstance(request, ApiChatRequest) or not isinstance(policy, ApiPolicy):
        raise ApiContractError("RESPONSE_INPUT_INVALID")
    request_id = _identity(request_id, "RESPONSE_REQUEST_ID_INVALID")
    if status not in STATUSES:
        raise ApiContractError("RESPONSE_STATUS_INVALID")
    if len(segments) > policy.maximum_segments or any(not isinstance(item, ApiSegment) for item in segments):
        raise ApiContractError("RESPONSE_SEGMENTS_INVALID")
    if len(sources) > policy.maximum_sources or any(not isinstance(item, ApiSourceGroup) for item in sources):
        raise ApiContractError("RESPONSE_SOURCES_INVALID")
    if any(len(source.excerpts) > policy.maximum_excerpts_per_source for source in sources):
        raise ApiContractError("RESPONSE_EXCERPT_LIMIT")
    source_ids = [source.source_id for source in sources]
    source_labels = [source.source_label for source in sources]
    citations = [excerpt.citation_id for source in sources for excerpt in source.excerpts]
    if (
        len(set(source_ids)) != len(source_ids)
        or len(set(source_labels)) != len(source_labels)
        or len(set(citations)) != len(citations)
    ):
        raise ApiContractError("RESPONSE_SOURCE_DUPLICATE")

    if status == "answered":
        if not segments or not sources or clarification is not None or error is not None:
            raise ApiContractError("RESPONSE_STATUS_FIELDS_INVALID")
        cited = {citation for segment in segments for citation in segment.citation_ids}
        if not cited or not cited <= set(citations):
            raise ApiContractError("RESPONSE_CITATION_NOT_ALLOWED")
        if not isinstance(context_budget, ApiContextBudget):
            raise ApiContractError("RESPONSE_CONTEXT_BUDGET_INVALID")
    elif status == "clarification-required":
        _text(clarification, 2048, "RESPONSE_CLARIFICATION_INVALID")
        if segments or sources or error is not None:
            raise ApiContractError("RESPONSE_STATUS_FIELDS_INVALID")
    else:
        if segments or sources or clarification is not None or not isinstance(error, ApiError):
            raise ApiContractError("RESPONSE_STATUS_FIELDS_INVALID")
        if (error.code, error.message) != ERRORS_BY_STATUS[status]:
            raise ApiContractError("RESPONSE_ERROR_NOT_ALLOWLISTED")

    body = {
        "segments": [item.canonical() for item in segments],
        "clarification": clarification,
        "conversation_id": request.conversation_id,
        "context_budget": None if context_budget is None else context_budget.canonical(),
        "diagnostics": None,
        "error": None if error is None else error.canonical(),
        "request_id": request_id,
        "schema": RESPONSE_SCHEMA,
        "sources": [item.canonical() for item in sources],
        "status": status,
        "turn_id": request.turn_id,
    }
    return ApiChatResponse(
        body,
        domain_digest("ishikawa.chat-response-envelope.v4", body),
    )


def attach_chat_diagnostics(
    response: ApiChatResponse,
    diagnostics: ApiDiagnostics,
) -> ApiChatResponse:
    """Finalize one response with content-free metrics after orchestration."""

    if not isinstance(response, ApiChatResponse) or not isinstance(diagnostics, ApiDiagnostics):
        raise ApiContractError("RESPONSE_DIAGNOSTICS_INVALID")
    if response.body.get("schema") != RESPONSE_SCHEMA or response.body.get("diagnostics") is not None:
        raise ApiContractError("RESPONSE_DIAGNOSTICS_INVALID")
    body = dict(response.body)
    body["diagnostics"] = diagnostics.canonical()
    return ApiChatResponse(
        body,
        domain_digest("ishikawa.chat-response-envelope.v4", body),
    )
