"""Native one-request/no-retry transport for standalone query resolution."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable

from .generation_transport import (
    GenerationEndpoint,
    GenerationHTTPResponse,
    GenerationResponseError,
    GenerationTransportError,
    PreparedGenerationRequest,
    native_http_exchange,
    prepare_chat_completion_request,
    validate_chat_completion_response,
)
from .query_resolution import (
    QueryResolutionContractError,
    QueryResolutionPolicy,
    QueryResolutionRequest,
    QueryResolutionResponseError,
    ResolvedRetrievalQuery,
    ResolvedSourceConstraint,
    build_query_resolution_request,
    deterministic_resolution,
    validate_query_resolution_content,
)
from .api_contract import ApiChatRequest, ApiSourceReference
from .retrieval_service import (
    QueryResolutionUnavailable,
    RetrievalDependencyUnavailable,
    RetrievalServiceContractError,
)


@dataclass(frozen=True, slots=True)
class ValidatedQueryResolutionResult:
    resolution: ResolvedRetrievalQuery
    finish_reason: str
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int


CredentialProvider = Callable[[], str]
SourceDisplayNameResolver = Callable[[ApiSourceReference], str]
KnownDocumentResolver = Callable[
    [ApiChatRequest, QueryResolutionPolicy], ResolvedRetrievalQuery | None
]


def _runtime_credential(provider: CredentialProvider) -> str:
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
class NativeQueryResolutionAdapter:
    endpoint: GenerationEndpoint
    policy: QueryResolutionPolicy
    credential_provider: CredentialProvider
    source_display_name_resolver: SourceDisplayNameResolver
    exchange: Callable[[PreparedGenerationRequest], GenerationHTTPResponse] = native_http_exchange
    known_document_resolver: KnownDocumentResolver | None = None

    def __call__(self, request: ApiChatRequest) -> ResolvedRetrievalQuery:
        if not isinstance(request, ApiChatRequest) or not callable(
            self.source_display_name_resolver
        ):
            raise RetrievalServiceContractError("query-resolution adapter input is invalid")
        if self.known_document_resolver is not None:
            if not callable(self.known_document_resolver):
                raise RetrievalServiceContractError(
                    "known-document resolver is invalid"
                )
            direct = self.known_document_resolver(request, self.policy)
            if direct is not None:
                if not isinstance(direct, ResolvedRetrievalQuery):
                    raise RetrievalServiceContractError(
                        "known-document resolution is invalid"
                    )
                return direct
        direct = deterministic_resolution(request, self.policy)
        if direct is not None:
            return direct
        try:
            constraints = tuple(
                ResolvedSourceConstraint(
                    item.source_id,
                    item.source_label,
                    self.source_display_name_resolver(item),
                    item.citation_id,
                )
                for item in request.source_references
            )
            model_request = build_query_resolution_request(
                request=request,
                source_constraints=constraints,
                policy=self.policy,
            )
        except QueryResolutionContractError as error:
            raise RetrievalServiceContractError(
                "query-resolution adapter contract failed"
            ) from error
        try:
            return execute_query_resolution_request(
                self.endpoint,
                model_request,
                request,
                self.policy,
                _runtime_credential(self.credential_provider),
                exchange=self.exchange,
            ).resolution
        except GenerationTransportError as error:
            raise QueryResolutionUnavailable(
                "query-resolution-transport-failed"
            ) from error
        except (GenerationResponseError, QueryResolutionResponseError) as error:
            raise QueryResolutionUnavailable(
                "query-resolution-response-invalid"
            ) from error


def execute_query_resolution_request(
    endpoint: GenerationEndpoint,
    model_request: QueryResolutionRequest,
    api_request: ApiChatRequest,
    policy: QueryResolutionPolicy,
    api_key: str,
    *,
    exchange: Callable[[PreparedGenerationRequest], GenerationHTTPResponse] = native_http_exchange,
) -> ValidatedQueryResolutionResult:
    prepared = prepare_chat_completion_request(endpoint, model_request.body, api_key)
    try:
        response = exchange(prepared)
    except GenerationTransportError:
        raise
    except Exception as error:
        raise GenerationTransportError("UPSTREAM_UNAVAILABLE") from error
    completion = validate_chat_completion_response(
        response,
        expected_model=model_request.body["model"],
        maximum_completion_tokens=model_request.body["max_tokens"],
    )
    resolution = validate_query_resolution_content(
        completion.content, api_request, model_request, policy
    )
    return ValidatedQueryResolutionResult(
        resolution,
        completion.finish_reason,
        completion.prompt_tokens,
        completion.completion_tokens,
        completion.total_tokens,
    )
