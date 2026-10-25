"""Native transport and strict response validation for scope classification."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable

from .generation_transport import (
    GenerationEndpoint,
    GenerationHTTPResponse,
    GenerationTransportError,
    PreparedGenerationRequest,
    native_http_exchange,
    prepare_chat_completion_request,
    validate_chat_completion_response,
)
from .scope import ScopeDecision, ScopeRequest, validate_scope_content


@dataclass(frozen=True, slots=True)
class ValidatedScopeResult:
    decision: ScopeDecision
    finish_reason: str
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int


def prepare_scope_request(
    endpoint: GenerationEndpoint,
    request: ScopeRequest,
    api_key: str,
) -> PreparedGenerationRequest:
    if not isinstance(request, ScopeRequest):
        raise GenerationTransportError("scope_request_invalid")
    return prepare_chat_completion_request(endpoint, request.body, api_key)


def validate_scope_response(
    response: GenerationHTTPResponse,
    request: ScopeRequest,
    policy,
) -> ValidatedScopeResult:
    if not isinstance(request, ScopeRequest):
        raise GenerationTransportError("scope_request_invalid")
    completion = validate_chat_completion_response(
        response,
        expected_model=request.body["model"],
        maximum_completion_tokens=request.body["max_tokens"],
    )
    decision = validate_scope_content(completion.content, policy)
    return ValidatedScopeResult(
        decision,
        completion.finish_reason,
        completion.prompt_tokens,
        completion.completion_tokens,
        completion.total_tokens,
    )


def execute_scope_request(
    endpoint: GenerationEndpoint,
    request: ScopeRequest,
    policy,
    api_key: str,
    *,
    exchange: Callable[[PreparedGenerationRequest], GenerationHTTPResponse] = native_http_exchange,
) -> ValidatedScopeResult:
    prepared = prepare_scope_request(endpoint, request, api_key)
    try:
        response = exchange(prepared)
    except GenerationTransportError:
        raise
    except Exception as error:
        raise GenerationTransportError("UPSTREAM_UNAVAILABLE") from error
    return validate_scope_response(response, request, policy)
