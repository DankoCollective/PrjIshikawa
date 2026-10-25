"""Native model and query-embedding adapters for the retrieval service.

Endpoints and credential providers are deployment inputs. Each adapter
invocation is synchronous, nonstreaming, single-request, and bounded. The
retrieval-service orchestrator may invoke grounded generation once more after
one explicitly retryable failure; adapters do not retry internally.
Credentials are obtained only at call time and are never part of a request
body or retained result.
"""

from __future__ import annotations

import http.client
import json
import math
import ssl
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any, Mapping, NoReturn
from urllib.parse import urlsplit

from .api_contract import ApiChatRequest, ApiSourceReference
from .canonical import canonical_json_bytes, domain_digest
from .generation import ConversationTurn, GroundedEvidence, build_grounded_generation_request
from .generation_transport import (
    GenerationEndpoint,
    GenerationHTTPResponse,
    GenerationResponseError,
    GenerationTransportError,
    PreparedGenerationRequest,
    ValidatedGroundedAnswer,
    execute_generation_request,
    native_http_exchange,
)
from .reconstruction import ReconstructionPolicy
from .retrieval_service import (
    GroundedGenerationRetryableUnavailable,
    RetrievalDependencyUnavailable,
    RetrievalServiceContractError,
)
from .scope import (
    ScopeContractError,
    ScopeDecision,
    ScopePolicy,
    ScopeResponseError,
    ScopeSourceReference,
    build_scope_request,
)
from .scope_transport import execute_scope_request


NOMIC_MODEL = "nomic-ai/nomic-embed-text-v1.5"
QUERY_PREFIX = "search_query: "
EMBEDDING_DIMENSION = 768
ACCEPTED_EMBEDDING_SPACE_ID = (
    "fd970d304662357a07f7712639bdc0c70cc7e72b22f04c126acce57a6f9143a3"
)
_SUPPORTED_SCHEMES = frozenset({"http", "https"})


class EmbeddingTransportError(RuntimeError):
    """Stable content-free query-embedding transport failure."""

    def __init__(self, reason_code: str):
        self.reason_code = reason_code
        super().__init__(reason_code)


class EmbeddingResponseError(ValueError):
    """Stable content-free query-embedding response rejection."""

    def __init__(self, reason_code: str):
        self.reason_code = reason_code
        super().__init__(reason_code)


def _transport_text(value: Any, label: str, maximum: int) -> str:
    if (
        not isinstance(value, str)
        or not value.strip()
        or value != value.strip()
        or len(value) > maximum
        or "\x00" in value
        or "\r" in value
        or "\n" in value
    ):
        raise EmbeddingTransportError(f"{label}_invalid")
    return value


@dataclass(frozen=True, slots=True)
class EmbeddingEndpoint:
    url: str
    timeout_seconds: int = 120
    maximum_response_bytes: int = 1024 * 1024

    def __post_init__(self) -> None:
        _transport_text(self.url, "endpoint", 2048)
        parsed = urlsplit(self.url)
        if (
            parsed.scheme not in _SUPPORTED_SCHEMES
            or not parsed.hostname
            or parsed.username is not None
            or parsed.password is not None
            or parsed.query
            or parsed.fragment
            or parsed.path != "/v1/embeddings"
        ):
            raise EmbeddingTransportError("endpoint_invalid")
        try:
            port = parsed.port
        except ValueError as error:
            raise EmbeddingTransportError("endpoint_invalid") from error
        if port is not None and not 1 <= port <= 65535:
            raise EmbeddingTransportError("endpoint_invalid")
        if type(self.timeout_seconds) is not int or not 1 <= self.timeout_seconds <= 300:
            raise EmbeddingTransportError("timeout_invalid")
        if (
            type(self.maximum_response_bytes) is not int
            or not 65536 <= self.maximum_response_bytes <= 4 * 1024 * 1024
        ):
            raise EmbeddingTransportError("response_limit_invalid")

    @property
    def parsed(self):
        return urlsplit(self.url)


@dataclass(frozen=True, slots=True)
class QueryEmbeddingRequest:
    body: dict[str, Any]
    request_identity: str
    embedding_space_id: str

    def canonical_bytes(self) -> bytes:
        return canonical_json_bytes(self.body)


@dataclass(frozen=True, slots=True)
class PreparedEmbeddingRequest:
    scheme: str
    host: str
    port: int
    path: str
    headers: dict[str, str]
    body: bytes
    timeout_seconds: int
    maximum_response_bytes: int


@dataclass(frozen=True, slots=True)
class EmbeddingHTTPResponse:
    status: int
    content_type: str
    body: bytes


@dataclass(frozen=True, slots=True)
class ValidatedQueryEmbedding:
    vector: tuple[float, ...]
    prompt_tokens: int
    embedding_space_id: str
    request_identity: str


def build_query_embedding_request(query: str) -> QueryEmbeddingRequest:
    if (
        not isinstance(query, str)
        or not query.strip()
        or query != query.strip()
        or len(query) > 16384
        or "\x00" in query
    ):
        raise EmbeddingTransportError("query_invalid")
    body = {"input": QUERY_PREFIX + query, "model": NOMIC_MODEL}
    request_identity = domain_digest(
        "ishikawa.query-embedding-request.v1",
        {
            "body": body,
            "embedding_space_id": ACCEPTED_EMBEDDING_SPACE_ID,
            "singleton": True,
        },
    )
    return QueryEmbeddingRequest(body, request_identity, ACCEPTED_EMBEDDING_SPACE_ID)


def prepare_query_embedding_request(
    endpoint: EmbeddingEndpoint,
    request: QueryEmbeddingRequest,
    api_key: str,
) -> PreparedEmbeddingRequest:
    if not isinstance(endpoint, EmbeddingEndpoint) or not isinstance(
        request, QueryEmbeddingRequest
    ):
        raise EmbeddingTransportError("embedding_request_invalid")
    credential = _transport_text(api_key, "credential", 16384)
    parsed = endpoint.parsed
    return PreparedEmbeddingRequest(
        scheme=parsed.scheme,
        host=parsed.hostname or "",
        port=parsed.port or (443 if parsed.scheme == "https" else 80),
        path=parsed.path,
        headers={
            "Accept": "application/json",
            "Authorization": f"Bearer {credential}",
            "Content-Type": "application/json",
        },
        body=request.canonical_bytes(),
        timeout_seconds=endpoint.timeout_seconds,
        maximum_response_bytes=endpoint.maximum_response_bytes,
    )


def native_embedding_exchange(
    prepared: PreparedEmbeddingRequest,
    *,
    tls_context: ssl.SSLContext | None = None,
) -> EmbeddingHTTPResponse:
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
                prepared.host, prepared.port, timeout=prepared.timeout_seconds
            )
        connection.request("POST", prepared.path, body=prepared.body, headers=prepared.headers)
        response = connection.getresponse()
        body = response.read(prepared.maximum_response_bytes + 1)
        if len(body) > prepared.maximum_response_bytes:
            raise EmbeddingTransportError("response_too_large")
        return EmbeddingHTTPResponse(
            status=response.status,
            content_type=response.getheader("Content-Type", ""),
            body=body,
        )
    except EmbeddingTransportError:
        raise
    except (OSError, TimeoutError, http.client.HTTPException, ssl.SSLError) as error:
        raise EmbeddingTransportError("upstream_unavailable") from error
    finally:
        if connection is not None:
            connection.close()


def _reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise EmbeddingResponseError("embedding_json_duplicate_field")
        value[key] = item
    return value


def _reject_constant(_value: str) -> NoReturn:
    raise EmbeddingResponseError("embedding_json_nonfinite_number")


def _exact_mapping(
    value: Any,
    fields: frozenset[str],
    reason: str,
) -> Mapping[str, Any]:
    if not isinstance(value, Mapping) or set(value) != fields:
        raise EmbeddingResponseError(reason)
    return value


def _compatible_mapping(
    value: Any,
    required_fields: frozenset[str],
    optional_fields: frozenset[str],
    reason: str,
) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise EmbeddingResponseError(reason)
    fields = set(value)
    if not required_fields.issubset(fields) or not fields.issubset(
        required_fields | optional_fields
    ):
        raise EmbeddingResponseError(reason)
    return value


def _validate_embedding_compatibility_fields(document: Mapping[str, Any]) -> None:
    if "created" in document:
        created = document["created"]
        if type(created) is not int or created < 0:
            raise EmbeddingResponseError("embedding_schema_invalid")
    if "id" in document:
        identifier = document["id"]
        if (
            not isinstance(identifier, str)
            or not identifier
            or identifier != identifier.strip()
            or len(identifier) > 512
            or "\x00" in identifier
            or "\r" in identifier
            or "\n" in identifier
        ):
            raise EmbeddingResponseError("embedding_schema_invalid")


def _validate_embedding_usage_compatibility_fields(
    usage: Mapping[str, Any], prompt_tokens: int
) -> None:
    if "completion_tokens" in usage:
        completion_tokens = usage["completion_tokens"]
        if type(completion_tokens) is not int or completion_tokens != 0:
            raise EmbeddingResponseError("embedding_usage_invalid")
    if "prompt_tokens_details" not in usage:
        return
    details = usage["prompt_tokens_details"]
    if details is None or details == {}:
        return
    if (
        not isinstance(details, Mapping)
        or set(details) != {"cached_tokens"}
        or type(details["cached_tokens"]) is not int
        or not 0 <= details["cached_tokens"] <= prompt_tokens
    ):
        raise EmbeddingResponseError("embedding_usage_invalid")


def validate_query_embedding_response(
    response: EmbeddingHTTPResponse,
    request: QueryEmbeddingRequest,
) -> ValidatedQueryEmbedding:
    if not isinstance(response, EmbeddingHTTPResponse) or not isinstance(
        request, QueryEmbeddingRequest
    ):
        raise EmbeddingResponseError("embedding_response_invalid")
    if response.status != 200:
        raise EmbeddingResponseError("embedding_upstream_http_error")
    if response.content_type.split(";", 1)[0].strip().lower() != "application/json":
        raise EmbeddingResponseError("embedding_content_type_invalid")
    try:
        document = json.loads(
            response.body.decode("utf-8"),
            object_pairs_hook=_reject_duplicates,
            parse_constant=_reject_constant,
        )
    except EmbeddingResponseError:
        raise
    except (UnicodeError, json.JSONDecodeError) as error:
        raise EmbeddingResponseError("embedding_json_invalid") from error
    document = _compatible_mapping(
        document,
        frozenset({"data", "model", "object", "usage"}),
        frozenset({"created", "id"}),
        "embedding_schema_invalid",
    )
    _validate_embedding_compatibility_fields(document)
    if document["model"] != NOMIC_MODEL or document["object"] != "list":
        raise EmbeddingResponseError("embedding_schema_invalid")
    records = document["data"]
    if not isinstance(records, list) or len(records) != 1:
        raise EmbeddingResponseError("embedding_cardinality_invalid")
    record = _exact_mapping(
        records[0],
        frozenset({"embedding", "index", "object"}),
        "embedding_record_invalid",
    )
    vector = record["embedding"]
    if (
        record["index"] != 0
        or record["object"] != "embedding"
        or not isinstance(vector, list)
        or len(vector) != EMBEDDING_DIMENSION
        or any(
            not isinstance(item, (int, float))
            or isinstance(item, bool)
            or not math.isfinite(float(item))
            for item in vector
        )
    ):
        raise EmbeddingResponseError("embedding_vector_invalid")
    converted = tuple(float(item) for item in vector)
    if math.sqrt(sum(item * item for item in converted)) == 0.0:
        raise EmbeddingResponseError("embedding_vector_invalid")
    usage = _compatible_mapping(
        document["usage"],
        frozenset({"prompt_tokens", "total_tokens"}),
        frozenset({"completion_tokens", "prompt_tokens_details"}),
        "embedding_usage_invalid",
    )
    prompt_tokens = usage["prompt_tokens"]
    if (
        type(prompt_tokens) is not int
        or prompt_tokens < 1
        or type(usage["total_tokens"]) is not int
        or usage["total_tokens"] != prompt_tokens
        or prompt_tokens > 2048
    ):
        raise EmbeddingResponseError("embedding_usage_invalid")
    _validate_embedding_usage_compatibility_fields(usage, prompt_tokens)
    return ValidatedQueryEmbedding(
        converted,
        prompt_tokens,
        request.embedding_space_id,
        request.request_identity,
    )


EmbeddingExchange = Callable[[PreparedEmbeddingRequest], EmbeddingHTTPResponse]


def execute_query_embedding_request(
    endpoint: EmbeddingEndpoint,
    request: QueryEmbeddingRequest,
    api_key: str,
    *,
    exchange: EmbeddingExchange = native_embedding_exchange,
) -> ValidatedQueryEmbedding:
    prepared = prepare_query_embedding_request(endpoint, request, api_key)
    try:
        response = exchange(prepared)
    except EmbeddingTransportError:
        raise
    except Exception as error:
        raise EmbeddingTransportError("upstream_unavailable") from error
    return validate_query_embedding_response(response, request)


CredentialProvider = Callable[[], str]
SourceDisplayNameResolver = Callable[[ApiSourceReference], str]
GenerationExchange = Callable[[PreparedGenerationRequest], GenerationHTTPResponse]
KnownDocumentScopeRouter = Callable[[ApiChatRequest], ScopeDecision | None]


def _credential(provider: CredentialProvider) -> str:
    if not callable(provider):
        raise RetrievalServiceContractError("credential provider is invalid")
    try:
        value = provider()
    except Exception as error:
        raise RetrievalDependencyUnavailable() from error
    if not isinstance(value, str) or not value.strip():
        raise RetrievalDependencyUnavailable()
    return value


@dataclass(frozen=True, slots=True)
class NativeScopeAdapter:
    endpoint: GenerationEndpoint
    policy: ScopePolicy
    credential_provider: CredentialProvider
    source_display_name_resolver: SourceDisplayNameResolver
    exchange: GenerationExchange = native_http_exchange
    known_document_router: KnownDocumentScopeRouter | None = None

    def __call__(self, request: ApiChatRequest) -> ScopeDecision:
        if not isinstance(request, ApiChatRequest) or not callable(
            self.source_display_name_resolver
        ):
            raise RetrievalServiceContractError("scope adapter input is invalid")
        if self.known_document_router is not None:
            if not callable(self.known_document_router):
                raise RetrievalServiceContractError(
                    "known-document router is invalid"
                )
            routed = self.known_document_router(request)
            if routed is not None:
                if not isinstance(routed, ScopeDecision):
                    raise RetrievalServiceContractError(
                        "known-document route is invalid"
                    )
                return routed
        history = tuple(ConversationTurn(turn.role, turn.content) for turn in request.history)
        references = tuple(
            ScopeSourceReference(
                item.source_id,
                item.source_label,
                self.source_display_name_resolver(item),
            )
            for item in request.source_references
        )
        try:
            scope_request = build_scope_request(
                conversation_id=request.conversation_id,
                turn_id=request.turn_id,
                history=history,
                question=request.message,
                source_references=references,
                policy=self.policy,
            )
        except ScopeContractError as error:
            raise RetrievalServiceContractError("scope adapter contract failed") from error
        try:
            return execute_scope_request(
                self.endpoint,
                scope_request,
                self.policy,
                _credential(self.credential_provider),
                exchange=self.exchange,
            ).decision
        except (GenerationTransportError, GenerationResponseError, ScopeResponseError) as error:
            raise RetrievalDependencyUnavailable() from error


@dataclass(frozen=True, slots=True)
class NativeGenerationAdapter:
    endpoint: GenerationEndpoint
    policy: ReconstructionPolicy
    credential_provider: CredentialProvider
    exchange: GenerationExchange = native_http_exchange

    def __call__(
        self,
        request: ApiChatRequest,
        resolved_query: str,
        evidence: tuple[GroundedEvidence, ...],
    ) -> ValidatedGroundedAnswer:
        if (
            not isinstance(request, ApiChatRequest)
            or not isinstance(resolved_query, str)
            or not resolved_query.strip()
            or resolved_query != resolved_query.strip()
            or "\x00" in resolved_query
        ):
            raise RetrievalServiceContractError("generation adapter input is invalid")
        history = tuple(ConversationTurn(turn.role, turn.content) for turn in request.history)
        try:
            generation_request = build_grounded_generation_request(
                conversation_id=request.conversation_id,
                turn_id=request.turn_id,
                history=history,
                question=resolved_query,
                evidence=evidence,
                policy=self.policy,
            )
        except Exception as error:
            raise RetrievalServiceContractError("generation adapter contract failed") from error
        try:
            return execute_generation_request(
                self.endpoint,
                generation_request,
                _credential(self.credential_provider),
                exchange=self.exchange,
            )
        except GenerationTransportError as error:
            raise GroundedGenerationRetryableUnavailable(
                "generation-transport-failed"
            ) from error
        except GenerationResponseError as error:
            raise GroundedGenerationRetryableUnavailable(
                "generation-response-invalid"
            ) from error


@dataclass(frozen=True, slots=True)
class NativeQueryEmbeddingAdapter:
    endpoint: EmbeddingEndpoint
    credential_provider: CredentialProvider
    exchange: EmbeddingExchange = native_embedding_exchange

    def __call__(self, query: str) -> ValidatedQueryEmbedding:
        request = build_query_embedding_request(query)
        try:
            return execute_query_embedding_request(
                self.endpoint,
                request,
                _credential(self.credential_provider),
                exchange=self.exchange,
            )
        except (EmbeddingTransportError, EmbeddingResponseError) as error:
            raise RetrievalDependencyUnavailable() from error

