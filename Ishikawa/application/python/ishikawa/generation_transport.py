"""Native HTTP transport and strict grounded-generation response validation.

The transport is deliberately small, synchronous, nonstreaming, and has no
retry behavior. Configuration supplies the endpoint while the caller supplies
the runtime credential. Model output remains untrusted until every envelope,
usage, segment, and citation check passes.
"""

from __future__ import annotations

import http.client
import json
import ssl
from dataclasses import dataclass
from typing import Any, Callable, Mapping, NoReturn
from urllib.parse import urlsplit

from .canonical import canonical_json_bytes
from .generation import GenerationRequest


_SUPPORTED_SCHEMES = frozenset({"http", "https"})
_TOP_LEVEL_FIELDS = frozenset(
    {
        "choices", "created", "ec_transfer_params", "id", "kv_transfer_params",
        "metrics", "model", "object", "prompt_logprobs", "prompt_text",
        "prompt_token_ids", "service_tier", "system_fingerprint", "usage",
    }
)
_CHOICE_FIELDS = frozenset(
    {
        "finish_reason", "index", "logprobs", "message", "routed_experts",
        "stop_reason", "token_ids",
    }
)
_MESSAGE_FIELDS = frozenset(
    {
        "annotations", "audio", "content", "function_call", "reasoning",
        "reasoning_content", "refusal", "role", "tool_calls",
    }
)
_USAGE_FIELDS = frozenset(
    {
        "completion_tokens", "completion_tokens_details", "prompt_tokens",
        "prompt_tokens_details", "total_tokens",
    }
)


class GenerationTransportError(RuntimeError):
    """Stable content-free transport failure."""

    def __init__(self, reason_code: str):
        self.reason_code = reason_code
        super().__init__(reason_code)


class GenerationResponseError(ValueError):
    """Stable content-free model-response rejection."""

    def __init__(self, reason_code: str):
        self.reason_code = reason_code
        super().__init__(reason_code)


def _text(value: Any, label: str, maximum: int) -> str:
    if not isinstance(value, str) or not value.strip() or value != value.strip():
        raise GenerationTransportError(f"{label}_invalid")
    if len(value) > maximum or "\x00" in value or "\r" in value or "\n" in value:
        raise GenerationTransportError(f"{label}_invalid")
    return value


@dataclass(frozen=True, slots=True)
class GenerationEndpoint:
    url: str
    timeout_seconds: int = 300
    maximum_response_bytes: int = 4 * 1024 * 1024

    def __post_init__(self) -> None:
        _text(self.url, "endpoint", 2048)
        parsed = urlsplit(self.url)
        if (
            parsed.scheme not in _SUPPORTED_SCHEMES
            or not parsed.hostname
            or parsed.username is not None
            or parsed.password is not None
            or parsed.query
            or parsed.fragment
            or parsed.path != "/v1/chat/completions"
        ):
            raise GenerationTransportError("endpoint_invalid")
        try:
            port = parsed.port
        except ValueError as error:
            raise GenerationTransportError("endpoint_invalid") from error
        if port is not None and not 1 <= port <= 65535:
            raise GenerationTransportError("endpoint_invalid")
        if type(self.timeout_seconds) is not int or not 1 <= self.timeout_seconds <= 900:
            raise GenerationTransportError("timeout_invalid")
        if type(self.maximum_response_bytes) is not int or not 1024 <= self.maximum_response_bytes <= 16 * 1024 * 1024:
            raise GenerationTransportError("response_limit_invalid")

    @property
    def parsed(self):
        return urlsplit(self.url)


@dataclass(frozen=True, slots=True)
class PreparedGenerationRequest:
    scheme: str
    host: str
    port: int
    path: str
    headers: dict[str, str]
    body: bytes
    timeout_seconds: int
    maximum_response_bytes: int


@dataclass(frozen=True, slots=True)
class GenerationHTTPResponse:
    status: int
    content_type: str
    body: bytes


@dataclass(frozen=True, slots=True)
class ValidatedChatCompletion:
    """Strictly validated common OpenAI-compatible chat-completion fields."""

    content: str
    finish_reason: str
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int


@dataclass(frozen=True, slots=True)
class GroundedSegment:
    text: str
    citation_ids: tuple[str, ...]


@dataclass(frozen=True, slots=True)
class ValidatedGroundedAnswer:
    answer: str
    segments: tuple[GroundedSegment, ...]
    finish_reason: str
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int


def prepare_generation_request(
    endpoint: GenerationEndpoint,
    request: GenerationRequest,
    api_key: str,
) -> PreparedGenerationRequest:
    if not isinstance(endpoint, GenerationEndpoint):
        raise GenerationTransportError("endpoint_invalid")
    if not isinstance(request, GenerationRequest):
        raise GenerationTransportError("generation_request_invalid")
    return prepare_chat_completion_request(endpoint, request.body, api_key)


def prepare_chat_completion_request(
    endpoint: GenerationEndpoint,
    body: Mapping[str, Any],
    api_key: str,
) -> PreparedGenerationRequest:
    """Prepare one canonical chat-completion POST for an accepted request body."""

    if not isinstance(endpoint, GenerationEndpoint):
        raise GenerationTransportError("endpoint_invalid")
    if not isinstance(body, Mapping):
        raise GenerationTransportError("generation_request_invalid")
    credential = _text(api_key, "credential", 16384)
    parsed = endpoint.parsed
    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    try:
        encoded_body = canonical_json_bytes(dict(body))
    except (TypeError, ValueError) as error:
        raise GenerationTransportError("generation_request_invalid") from error
    return PreparedGenerationRequest(
        scheme=parsed.scheme,
        host=parsed.hostname or "",
        port=port,
        path=parsed.path,
        headers={
            "Accept": "application/json",
            "Authorization": f"Bearer {credential}",
            "Content-Type": "application/json",
        },
        body=encoded_body,
        timeout_seconds=endpoint.timeout_seconds,
        maximum_response_bytes=endpoint.maximum_response_bytes,
    )


def native_http_exchange(
    prepared: PreparedGenerationRequest,
    *,
    tls_context: ssl.SSLContext | None = None,
) -> GenerationHTTPResponse:
    """Perform one direct POST without redirects or automatic retries."""

    connection: http.client.HTTPConnection | None = None
    try:
        if prepared.scheme == "https":
            connection = http.client.HTTPSConnection(
                prepared.host,
                prepared.port,
                timeout=prepared.timeout_seconds,
                context=tls_context,
            )
        else:
            connection = http.client.HTTPConnection(
                prepared.host,
                prepared.port,
                timeout=prepared.timeout_seconds,
            )
        connection.request("POST", prepared.path, body=prepared.body, headers=prepared.headers)
        response = connection.getresponse()
        body = response.read(prepared.maximum_response_bytes + 1)
        content_type = response.getheader("Content-Type", "")
        status = response.status
    except (OSError, TimeoutError, http.client.HTTPException, ssl.SSLError) as error:
        raise GenerationTransportError("UPSTREAM_UNAVAILABLE") from error
    finally:
        if connection is not None:
            try:
                connection.close()
            except OSError:
                pass
    if len(body) > prepared.maximum_response_bytes:
        raise GenerationTransportError("UPSTREAM_RESPONSE_TOO_LARGE")
    return GenerationHTTPResponse(status, content_type, body)


def execute_generation_request(
    endpoint: GenerationEndpoint,
    request: GenerationRequest,
    api_key: str,
    *,
    exchange: Callable[[PreparedGenerationRequest], GenerationHTTPResponse] = native_http_exchange,
) -> ValidatedGroundedAnswer:
    prepared = prepare_generation_request(endpoint, request, api_key)
    try:
        response = exchange(prepared)
    except GenerationTransportError:
        raise
    except Exception as error:
        raise GenerationTransportError("UPSTREAM_UNAVAILABLE") from error
    return validate_generation_response(response, request)


def _reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise GenerationResponseError("MODEL_JSON_DUPLICATE_FIELD")
        value[key] = item
    return value


def _reject_constant(_value: str) -> NoReturn:
    raise GenerationResponseError("MODEL_JSON_NONFINITE_NUMBER")


def _decode_json(data: bytes, reason: str) -> Any:
    try:
        text = data.decode("utf-8")
        return json.loads(
            text,
            object_pairs_hook=_reject_duplicates,
            parse_constant=_reject_constant,
        )
    except GenerationResponseError:
        raise
    except (UnicodeError, json.JSONDecodeError) as error:
        raise GenerationResponseError(reason) from error


def decode_model_json_content(content: str) -> Any:
    """Decode raw JSON or one isolated, lower-case ``json`` Markdown fence.

    The fence is a narrowly scoped compatibility allowance for instruction-
    tuned model output. Surrounding prose, whitespace outside the fence,
    multiple fences, and other fence labels remain invalid.
    """

    if not isinstance(content, str):
        raise GenerationResponseError("MODEL_OUTPUT_JSON_INVALID")
    if content.startswith("```json\n"):
        if not content.endswith("\n```") or content.count("```") != 2:
            raise GenerationResponseError("MODEL_OUTPUT_JSON_INVALID")
        content = content[len("```json\n") : -len("\n```")]
        if not content:
            raise GenerationResponseError("MODEL_OUTPUT_JSON_INVALID")
    elif "```" in content:
        raise GenerationResponseError("MODEL_OUTPUT_JSON_INVALID")
    return _decode_json(content.encode("utf-8"), "MODEL_OUTPUT_JSON_INVALID")


def _exact_fields(value: Any, required: frozenset[str], allowed: frozenset[str], reason: str) -> dict[str, Any]:
    if not isinstance(value, dict) or not required <= set(value) or not set(value) <= allowed:
        raise GenerationResponseError(reason)
    return value


def _nullable_fields(value: dict[str, Any], names: frozenset[str]) -> None:
    for name in names:
        if name in value and value[name] not in (None, [], ""):
            raise GenerationResponseError("MODEL_UNAUTHORIZED_OUTPUT_CHANNEL")


def validate_generation_response(
    response: GenerationHTTPResponse,
    request: GenerationRequest,
) -> ValidatedGroundedAnswer:
    completion = validate_chat_completion_response(
        response,
        expected_model=request.body["model"],
        maximum_completion_tokens=request.body["max_tokens"],
    )
    model_output = decode_model_json_content(completion.content)
    model_output = _exact_fields(
        model_output,
        frozenset({"segments"}),
        frozenset({"segments"}),
        "MODEL_OUTPUT_SCHEMA_INVALID",
    )
    segments = model_output["segments"]
    if not isinstance(segments, list) or not 1 <= len(segments) <= 64:
        raise GenerationResponseError("MODEL_OUTPUT_SCHEMA_INVALID")
    citation_by_alias = dict(request.citation_aliases)
    allowed = set(citation_by_alias)
    validated: list[GroundedSegment] = []
    for raw_segment in segments:
        raw_segment = _exact_fields(
            raw_segment,
            frozenset({"citation_ids", "text"}),
            frozenset({"citation_ids", "text"}),
            "MODEL_SEGMENT_SCHEMA_INVALID",
        )
        raw_text = raw_segment["text"]
        citation_ids = raw_segment["citation_ids"]
        if (
            not isinstance(raw_text, str)
            or not raw_text.strip()
            or len(raw_text) > 65536
            or not isinstance(citation_ids, list)
            or not citation_ids
            or len(set(citation_ids)) != len(citation_ids)
            or any(not isinstance(item, str) for item in citation_ids)
        ):
            raise GenerationResponseError("MODEL_SEGMENT_SCHEMA_INVALID")
        # A model-added boundary space has no semantic content and must not
        # turn an otherwise valid cited answer into a dependency failure.
        # Normalize only the two outer boundaries; internal prose is retained
        # byte-for-byte for the operator-facing answer.
        text = raw_text.strip()
        if not set(citation_ids) <= allowed:
            raise GenerationResponseError("MODEL_CITATION_NOT_ALLOWED")
        validated.append(
            GroundedSegment(
                text,
                tuple(citation_by_alias[citation_id] for citation_id in citation_ids),
            )
        )
    cited = {
        citation_id
        for segment in validated
        for citation_id in segment.citation_ids
    }
    if any(not cited.intersection(group) for group in request.required_citation_groups):
        raise GenerationResponseError("MODEL_REQUIRED_CITATION_GROUP_MISSING")
    grounded_answer = " ".join(item.text for item in validated)
    return ValidatedGroundedAnswer(
        grounded_answer,
        tuple(validated),
        completion.finish_reason,
        completion.prompt_tokens,
        completion.completion_tokens,
        completion.total_tokens,
    )


def validate_chat_completion_response(
    response: GenerationHTTPResponse,
    *,
    expected_model: str,
    maximum_completion_tokens: int,
) -> ValidatedChatCompletion:
    """Validate the common envelope without interpreting assistant content."""

    if not isinstance(response, GenerationHTTPResponse):
        raise GenerationResponseError("UPSTREAM_RESPONSE_INVALID")
    if response.status != 200:
        raise GenerationResponseError("UPSTREAM_HTTP_ERROR")
    media_type = response.content_type.split(";", 1)[0].strip().lower()
    if media_type != "application/json":
        raise GenerationResponseError("UPSTREAM_CONTENT_TYPE_INVALID")
    envelope = _decode_json(response.body, "UPSTREAM_JSON_INVALID")
    envelope = _exact_fields(
        envelope,
        frozenset({"choices", "created", "id", "model", "object", "usage"}),
        _TOP_LEVEL_FIELDS,
        "UPSTREAM_SCHEMA_INVALID",
    )
    if (
        envelope["object"] != "chat.completion"
        or envelope["model"] != expected_model
        or not isinstance(envelope["id"], str)
        or not envelope["id"]
        or type(envelope["created"]) is not int
        or envelope["created"] < 0
    ):
        raise GenerationResponseError("UPSTREAM_SCHEMA_INVALID")
    _nullable_fields(
        envelope,
        frozenset(
            {
                "ec_transfer_params", "kv_transfer_params", "metrics",
                "prompt_logprobs", "prompt_text", "prompt_token_ids",
            }
        ),
    )
    choices = envelope["choices"]
    if not isinstance(choices, list) or len(choices) != 1:
        raise GenerationResponseError("UPSTREAM_CHOICE_INVALID")
    choice = _exact_fields(
        choices[0], frozenset({"finish_reason", "index", "message"}), _CHOICE_FIELDS,
        "UPSTREAM_CHOICE_INVALID",
    )
    if choice["index"] != 0 or choice["finish_reason"] != "stop":
        raise GenerationResponseError("MODEL_COMPLETION_INCOMPLETE")
    _nullable_fields(choice, frozenset({"logprobs", "routed_experts", "token_ids"}))
    message = _exact_fields(
        choice["message"], frozenset({"content", "role"}), _MESSAGE_FIELDS,
        "UPSTREAM_MESSAGE_INVALID",
    )
    if message["role"] != "assistant" or not isinstance(message["content"], str):
        raise GenerationResponseError("UPSTREAM_MESSAGE_INVALID")
    _nullable_fields(
        message,
        frozenset(
            {
                "annotations", "audio", "function_call", "reasoning",
                "reasoning_content", "refusal", "tool_calls",
            }
        ),
    )
    usage = _exact_fields(
        envelope["usage"],
        frozenset({"completion_tokens", "prompt_tokens", "total_tokens"}),
        _USAGE_FIELDS,
        "UPSTREAM_USAGE_INVALID",
    )
    prompt_tokens = usage["prompt_tokens"]
    completion_tokens = usage["completion_tokens"]
    total_tokens = usage["total_tokens"]
    if (
        type(prompt_tokens) is not int
        or type(completion_tokens) is not int
        or type(total_tokens) is not int
        or prompt_tokens < 1
        or completion_tokens < 1
        or total_tokens != prompt_tokens + completion_tokens
        or completion_tokens > maximum_completion_tokens
    ):
        raise GenerationResponseError("UPSTREAM_USAGE_INVALID")
    return ValidatedChatCompletion(
        message["content"],
        choice["finish_reason"],
        prompt_tokens,
        completion_tokens,
        total_tokens,
    )
