"""Fail-closed orchestration for the Ishikawa Retrieval API.

The module owns ordering and client-safe outcome mapping. External operations
remain explicit injected ports so local qualification cannot contact a model,
database, embedding endpoint, or network listener.
"""

from __future__ import annotations

import re
import time
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any, Mapping

from .api_contract import (
    ERRORS_BY_STATUS,
    ApiChatRequest,
    ApiChatResponse,
    ApiDiagnostics,
    ApiExcerpt,
    ApiSegment,
    ApiContextBudget,
    ApiError,
    ApiPolicy,
    ApiSourceGroup,
    attach_chat_diagnostics,
    build_chat_response,
)
from .canonical import domain_digest
from .generation import GroundedEvidence
from .generation_transport import ValidatedGroundedAnswer
from .injection import InjectionPolicy, UntrustedText, scan_untrusted_texts
from .query_resolution import ResolvedRetrievalQuery
from .scope import ScopeDecision
from .sufficiency import SufficiencyDecision


SERVICE_DISPLAY_NAME = "Ishikawa Retrieval API"
SERVICE_COMPONENT_ID = "ishikawa-retrieval-api"
SERVICE_PACKAGE_OWNER = "Ishikawa"
_DIGEST = re.compile(r"^[0-9a-f]{64}$")
_SUFFICIENCY_REASONS = {
    "sufficient": frozenset(
        {"EVIDENCE_SUFFICIENT", "EXACT_DOCUMENT_EVIDENCE_SUFFICIENT"}
    ),
    "insufficient-evidence": frozenset(
        {
            "NO_RETRIEVAL_CANDIDATES",
            "NO_AUTHORIZED_EVIDENCE",
            "EXACT_CONSTRAINT_UNSATISFIED",
            "RELATIONSHIP_COVERAGE_INCOMPLETE",
            "SOURCE_VERSION_CONFLICT",
            "NO_RECONSTRUCTABLE_EVIDENCE",
            "CITATION_SET_INVALID",
            "RELEVANCE_NOT_QUALIFIED",
            "RELEVANCE_INSUFFICIENT",
        }
    ),
    "context-limit": frozenset({"COMPLETE_STRUCTURE_INCOMPLETE", "CONTEXT_LIMIT"}),
    "temporarily-unavailable": frozenset({"RETRIEVAL_LANE_FAILURE"}),
}


class RetrievalServiceContractError(ValueError):
    """Raised when service configuration or a typed port result is invalid."""


class RetrievalDependencyUnavailable(RuntimeError):
    """Expected content-free signal that a required dependency is unavailable."""


class QueryResolutionUnavailable(RetrievalDependencyUnavailable):
    """Content-free query-resolution failure with an observable pipeline stage."""

    _FAILURE_STAGES = frozenset(
        {"query-resolution-response-invalid", "query-resolution-transport-failed"}
    )

    def __init__(self, failure_stage: str):
        if failure_stage not in self._FAILURE_STAGES:
            raise RetrievalServiceContractError(
                "query-resolution failure stage is invalid"
            )
        self.failure_stage = failure_stage
        super().__init__(failure_stage)


class GroundedGenerationRetryableUnavailable(RetrievalDependencyUnavailable):
    """Signal that one grounded-generation retry is permitted."""

    _FAILURE_STAGES = frozenset(
        {"generation-response-invalid", "generation-transport-failed"}
    )

    def __init__(self, failure_stage: str = "generation-response-invalid"):
        if failure_stage not in self._FAILURE_STAGES:
            raise RetrievalServiceContractError(
                "generation retry failure stage is invalid"
            )
        self.failure_stage = failure_stage
        super().__init__(failure_stage)


def _exact_mapping(value: Any, fields: frozenset[str], label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping) or set(value) != fields:
        raise RetrievalServiceContractError(f"{label} fields are invalid")
    return value


@dataclass(frozen=True, slots=True)
class RetrievalServicePolicy:
    display_name: str
    component_id: str
    package_owner: str
    implementation: str
    process_model: str
    lifecycle: str
    default_bind_address: str
    default_port: int
    allowed_client: str
    digest: str


def validate_retrieval_service_profile(value: Any) -> RetrievalServicePolicy:
    root = _exact_mapping(
        value,
        frozenset({"schema_version", "identity", "runtime", "network"}),
        "retrieval service profile",
    )
    if root["schema_version"] != 1 or type(root["schema_version"]) is not int:
        raise RetrievalServiceContractError("retrieval service profile version is invalid")
    identity = _exact_mapping(
        root["identity"],
        frozenset({"display_name", "component_id", "package_owner"}),
        "retrieval service identity",
    )
    runtime = _exact_mapping(
        root["runtime"],
        frozenset({"implementation", "process_model", "lifecycle"}),
        "retrieval service runtime",
    )
    network = _exact_mapping(
        root["network"],
        frozenset({"default_bind_address", "default_port", "allowed_client"}),
        "retrieval service network",
    )
    expected_identity = {
        "display_name": SERVICE_DISPLAY_NAME,
        "component_id": SERVICE_COMPONENT_ID,
        "package_owner": SERVICE_PACKAGE_OWNER,
    }
    expected_runtime = {
        "implementation": "native_python",
        "process_model": "separate_process",
        "lifecycle": "start_on_demand",
    }
    default_port = network["default_port"]
    expected_network = {
        "default_bind_address": "127.0.0.1",
        "default_port": default_port,
        "allowed_client": "ishikawa_nextjs_server",
    }
    if (
        dict(identity) != expected_identity
        or dict(runtime) != expected_runtime
        or network["default_bind_address"] != expected_network["default_bind_address"]
        or network["allowed_client"] != expected_network["allowed_client"]
        or type(default_port) is not int
        or not 1 <= default_port <= 65535
    ):
        raise RetrievalServiceContractError("retrieval service profile contract is invalid")
    canonical = {
        "identity": expected_identity,
        "network": expected_network,
        "runtime": expected_runtime,
        "schema_version": 1,
    }
    return RetrievalServicePolicy(
        **expected_identity,
        **expected_runtime,
        **expected_network,
        digest=domain_digest("ishikawa.retrieval-service-profile.v1", canonical),
    )


@dataclass(frozen=True, slots=True)
class RetrievedEvidence:
    """Client-safe evidence plus the authoritative deterministic gate result."""

    sufficiency: SufficiencyDecision
    sources: tuple[ApiSourceGroup, ...]
    telemetry: RetrievalOperationalTelemetry | None = None
    generation_sources: tuple[ApiSourceGroup, ...] | None = None
    generation_evidence: tuple[GroundedEvidence, ...] | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.sufficiency, SufficiencyDecision):
            raise RetrievalServiceContractError("retrieval sufficiency result is invalid")
        allowed_reasons = _SUFFICIENCY_REASONS.get(self.sufficiency.status)
        if allowed_reasons is None or self.sufficiency.reason_code not in allowed_reasons:
            raise RetrievalServiceContractError("retrieval sufficiency outcome is invalid")
        if not isinstance(self.sources, tuple) or any(
            not isinstance(source, ApiSourceGroup) for source in self.sources
        ):
            raise RetrievalServiceContractError("retrieval sources are invalid")
        if self.sufficiency.status == "sufficient" and not self.sources:
            raise RetrievalServiceContractError("sufficient evidence requires a source")
        if self.sufficiency.status != "sufficient" and self.sources:
            raise RetrievalServiceContractError("blocked evidence cannot expose sources")
        citation_ids = [
            excerpt.citation_id for source in self.sources for excerpt in source.excerpts
        ]
        if len(set(citation_ids)) != len(citation_ids):
            raise RetrievalServiceContractError("retrieval citations are not unique")
        if self.generation_sources is not None:
            if not self.generation_sources or any(
                not isinstance(source, ApiSourceGroup) for source in self.generation_sources
            ):
                raise RetrievalServiceContractError("generation sources are invalid")
            response_citations = set(citation_ids)
            generation_citations = {
                excerpt.citation_id
                for source in self.generation_sources
                for excerpt in source.excerpts
            }
            if not generation_citations or not generation_citations <= response_citations:
                raise RetrievalServiceContractError("generation citations are not displayable")
        if self.generation_evidence is not None:
            if not self.generation_evidence or any(
                not isinstance(item, GroundedEvidence)
                for item in self.generation_evidence
            ):
                raise RetrievalServiceContractError("generation evidence is invalid")
            evidence_citations = {
                item.citation_id for item in self.generation_evidence
            }
            source_citations = {
                excerpt.citation_id
                for source in (self.generation_sources or self.sources)
                for excerpt in source.excerpts
            }
            if len(evidence_citations) != len(self.generation_evidence):
                raise RetrievalServiceContractError(
                    "generation evidence citations are not unique"
                )
            if evidence_citations != source_citations:
                raise RetrievalServiceContractError(
                    "generation evidence does not match generation sources"
                )
        if self.telemetry is not None and not isinstance(
            self.telemetry, RetrievalOperationalTelemetry
        ):
            raise RetrievalServiceContractError("retrieval telemetry is invalid")


@dataclass(frozen=True, slots=True)
class RetrievalOperationalTelemetry:
    """Content-free bounded measurements returned by the retrieval port."""

    lane_states: tuple[tuple[str, str], ...]
    fused_candidate_count: int
    authorized_candidate_count: int
    reconstructed_unit_count: int
    citation_count: int
    prompt_token_count: int
    answer_token_reserve: int
    context_tokens_used: int
    context_token_limit: int
    nomic_query_tokens: int
    prompt_target_tokens: int = 0
    retrieval_stage_durations_ms: tuple[tuple[str, int], ...] = ()
    relevance_reason_code: str = ""
    sufficiency_reason_code: str = ""
    selected_group_order: tuple[str, ...] = ()

    def __post_init__(self) -> None:
        if (
            self.lane_states != tuple(self.lane_states)
            or tuple(name for name, _state in self.lane_states)
            != ("exact", "lexical", "vector")
            or any(
                state not in {"pass", "not_applicable", "failed"}
                for _name, state in self.lane_states
            )
        ):
            raise RetrievalServiceContractError("retrieval lane telemetry is invalid")
        counts = (
            self.fused_candidate_count,
            self.authorized_candidate_count,
            self.reconstructed_unit_count,
            self.citation_count,
            self.prompt_token_count,
            self.answer_token_reserve,
            self.context_tokens_used,
            self.context_token_limit,
            self.nomic_query_tokens,
            self.prompt_target_tokens,
        )
        if any(type(value) is not int or not 0 <= value <= 100000000 for value in counts):
            raise RetrievalServiceContractError("retrieval count telemetry is invalid")
        if (
            self.authorized_candidate_count > self.fused_candidate_count
            or self.context_token_limit < 1
            or self.context_tokens_used > self.context_token_limit
            or (
                self.prompt_target_tokens > 0
                and self.prompt_token_count > self.prompt_target_tokens
            )
            or (
                self.prompt_token_count > 0
                and self.context_tokens_used
                != self.prompt_token_count + self.answer_token_reserve
            )
        ):
            raise RetrievalServiceContractError("retrieval telemetry bounds are invalid")
        if self.retrieval_stage_durations_ms and (
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
            raise RetrievalServiceContractError(
                "retrieval stage timing telemetry is invalid"
            )
        decision_codes_absent = (
            self.relevance_reason_code == "" and self.sufficiency_reason_code == ""
        )
        decision_codes_valid = (
            isinstance(self.relevance_reason_code, str)
            and self.relevance_reason_code
            in {
                "CITABLE_EVIDENCE_SUPPORT_QUALIFIED",
                "CITABLE_EVIDENCE_SUPPORT_INSUFFICIENT",
            }
            and isinstance(self.sufficiency_reason_code, str)
            and self.sufficiency_reason_code
            in {
                reason
                for reasons in _SUFFICIENCY_REASONS.values()
                for reason in reasons
            }
        )
        if not (decision_codes_absent or decision_codes_valid):
            raise RetrievalServiceContractError(
                "retrieval decision telemetry is invalid"
            )
        if (
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
            raise RetrievalServiceContractError(
                "retrieval selected-group telemetry is invalid"
            )


ScopePort = Callable[[ApiChatRequest], ScopeDecision]
QueryResolutionPort = Callable[[ApiChatRequest], ResolvedRetrievalQuery]
RetrievalPort = Callable[[ApiChatRequest, ResolvedRetrievalQuery], RetrievedEvidence]
GenerationPort = Callable[
    [ApiChatRequest, str, tuple[GroundedEvidence, ...]], ValidatedGroundedAnswer
]


@dataclass(frozen=True, slots=True)
class RetrievalServicePorts:
    classify_scope: ScopePort
    resolve_query: QueryResolutionPort
    retrieve_evidence: RetrievalPort
    generate_answer: GenerationPort

    def __post_init__(self) -> None:
        if not all(
            callable(port)
            for port in (
                self.classify_scope,
                self.resolve_query,
                self.retrieve_evidence,
                self.generate_answer,
            )
        ):
            raise RetrievalServiceContractError("retrieval service port is invalid")


@dataclass(frozen=True, slots=True)
class RetrievalServiceExecution:
    response: ApiChatResponse
    stage_trace: tuple[str, ...]
    service_identity: str
    stage_durations_ms: tuple[tuple[str, int], ...] = ()
    retrieval_telemetry: RetrievalOperationalTelemetry | None = None


class _TimedStageTrace:
    """Record one low-cardinality stage sequence and monotonic elapsed time."""

    def __init__(self, clock_ns: Callable[[], int]):
        if not callable(clock_ns):
            raise RetrievalServiceContractError("stage clock is invalid")
        self.clock_ns = clock_ns
        self.names: list[str] = []
        self.durations: list[tuple[str, int]] = []
        self.previous_ns = clock_ns()
        if type(self.previous_ns) is not int or self.previous_ns < 0:
            raise RetrievalServiceContractError("stage clock is invalid")

    def append(self, stage: str) -> None:
        current_ns = self.clock_ns()
        if type(current_ns) is not int or current_ns < self.previous_ns:
            raise RetrievalServiceContractError("stage clock is invalid")
        elapsed_ms = min(86400000, (current_ns - self.previous_ns) // 1000000)
        self.names.append(stage)
        self.durations.append((stage, elapsed_ms))
        self.previous_ns = current_ns

    def extend(self, stages: tuple[str, ...]) -> None:
        for stage in stages:
            self.append(stage)

    def __iter__(self):
        return iter(self.names)


def _execution(
    response: ApiChatResponse,
    trace: _TimedStageTrace,
    service_identity: str,
    telemetry: RetrievalOperationalTelemetry | None = None,
    generated: ValidatedGroundedAnswer | None = None,
) -> RetrievalServiceExecution:
    durations_by_stage = dict(trace.durations)
    scope_ms = sum(
        duration
        for stage, duration in trace.durations
        if stage in {"scope-allowed", "scope-rejected", "scope-clarification"}
    )
    generation_ms = durations_by_stage.get("generation-completed", 0)
    if "generation-retry" in durations_by_stage:
        generation_ms += durations_by_stage["generation-retry"]
    generation_ms += sum(
        duration
        for stage, duration in trace.durations
        if stage in {"generation-response-invalid", "generation-transport-failed"}
    )
    context_used = None if telemetry is None else telemetry.context_tokens_used
    context_limit = None if telemetry is None else telemetry.context_token_limit
    diagnostics = ApiDiagnostics(
        api_processing_ms=sum(duration for _stage, duration in trace.durations),
        scope_ms=scope_ms,
        query_resolution_ms=durations_by_stage.get("query-resolved", 0),
        retrieval_ms=durations_by_stage.get("retrieval-completed", 0),
        generation_ms=generation_ms,
        response_build_ms=durations_by_stage.get("response-built", 0),
        lane_states=None if telemetry is None else telemetry.lane_states,
        fused_result_count=None if telemetry is None else telemetry.fused_candidate_count,
        authorized_result_count=None if telemetry is None else telemetry.authorized_candidate_count,
        reconstructed_result_count=None if telemetry is None else telemetry.reconstructed_unit_count,
        cited_result_count=None if telemetry is None else telemetry.citation_count,
        nomic_query_tokens=None if telemetry is None else telemetry.nomic_query_tokens,
        gemma_prompt_tokens=None if generated is None else generated.prompt_tokens,
        gemma_completion_tokens=None if generated is None else generated.completion_tokens,
        gemma_total_tokens=None if generated is None else generated.total_tokens,
        context_tokens_used=context_used,
        context_tokens_remaining=None
        if context_limit is None or context_used is None
        else context_limit - context_used,
        context_token_limit=context_limit,
        generation_retry="generation-retry" in tuple(trace),
        prompt_target_tokens=None
        if telemetry is None
        else telemetry.prompt_target_tokens,
        retrieval_stage_durations_ms=None
        if telemetry is None or not telemetry.retrieval_stage_durations_ms
        else telemetry.retrieval_stage_durations_ms,
        relevance_reason_code=None
        if telemetry is None or not telemetry.relevance_reason_code
        else telemetry.relevance_reason_code,
        sufficiency_reason_code=None
        if telemetry is None or not telemetry.sufficiency_reason_code
        else telemetry.sufficiency_reason_code,
        selected_group_order=None
        if telemetry is None or not telemetry.selected_group_order
        else telemetry.selected_group_order,
    )
    return RetrievalServiceExecution(
        attach_chat_diagnostics(response, diagnostics),
        tuple(trace),
        service_identity,
        tuple(trace.durations),
        telemetry,
    )


def _safe_error(
    request: ApiChatRequest,
    request_id: str,
    status: str,
    api_policy: ApiPolicy,
) -> ApiChatResponse:
    code, message = ERRORS_BY_STATUS[status]
    return build_chat_response(
        request=request,
        request_id=request_id,
        status=status,
        error=ApiError(code, message),
        policy=api_policy,
    )


def _evidence_from_sources(sources: tuple[ApiSourceGroup, ...]) -> tuple[GroundedEvidence, ...]:
    return tuple(
        GroundedEvidence(
            citation_id=excerpt.citation_id,
            source_label=source.source_label,
            excerpt=excerpt.excerpt,
            page_start=excerpt.page_start,
            page_end=excerpt.page_end,
            structural_path=excerpt.structural_path,
        )
        for source in sources
        for excerpt in source.excerpts
    )


def _context_budget(
    telemetry: RetrievalOperationalTelemetry | None,
) -> ApiContextBudget:
    if telemetry is None:
        raise RetrievalServiceContractError("answered response requires context telemetry")
    used = telemetry.context_tokens_used
    return ApiContextBudget(
        telemetry.context_token_limit,
        used,
        telemetry.context_token_limit - used,
    )


def _cited_display_sources(
    display_sources: tuple[ApiSourceGroup, ...],
    generation_sources: tuple[ApiSourceGroup, ...],
    segments: tuple[ApiSegment, ...],
) -> tuple[ApiSourceGroup, ...]:
    """Expose only complete structural roots anchored by validated segments."""

    cited = {citation_id for segment in segments for citation_id in segment.citation_ids}
    generation_by_citation = {
        excerpt.citation_id: (source.source_id, excerpt)
        for source in generation_sources
        for excerpt in source.excerpts
    }
    if not cited <= set(generation_by_citation):
        raise RetrievalServiceContractError("generated citation is not generation evidence")
    roots_by_source: dict[str, set[tuple[str, ...]]] = {}
    direct_by_source: dict[str, set[str]] = {}
    for citation_id in cited:
        source_id, excerpt = generation_by_citation[citation_id]
        direct_by_source.setdefault(source_id, set()).add(citation_id)
        if excerpt.structural_path:
            roots_by_source.setdefault(source_id, set()).add(
                (excerpt.structural_path[0],)
            )

    result: list[ApiSourceGroup] = []
    for source in display_sources:
        direct = direct_by_source.get(source.source_id, set())
        if not direct:
            continue
        roots = roots_by_source.get(source.source_id, set())
        excerpts: list[ApiExcerpt] = []
        seen: set[str] = set()
        for excerpt in source.excerpts:
            in_root = any(
                excerpt.structural_path[: len(root)] == root for root in roots
            )
            if excerpt.citation_id not in direct and not in_root:
                continue
            if excerpt.citation_id in seen:
                continue
            excerpts.append(excerpt)
            seen.add(excerpt.citation_id)
        if not direct <= seen:
            raise RetrievalServiceContractError("cited display evidence is incomplete")
        displayed_roots = {
            excerpt.structural_path[0]
            for excerpt in excerpts
            if excerpt.structural_path
        }
        all_roots = {
            excerpt.structural_path[0]
            for excerpt in source.excerpts
            if excerpt.structural_path
        }
        result.append(
            ApiSourceGroup(
                source.source_id,
                source.source_label,
                source.document_key,
                source.document_identifier,
                source.display_name,
                source.document_class,
                tuple(excerpts),
                source.page_count,
                source.has_additional_sections or bool(all_roots - displayed_roots),
            )
        )
    return tuple(result)


def _validate_scope_decision(value: Any) -> ScopeDecision:
    if not isinstance(value, ScopeDecision):
        raise RetrievalServiceContractError("scope port result is invalid")
    if value.decision == "allow" or value.decision == "out_of_scope":
        if value.clarification is not None:
            raise RetrievalServiceContractError("scope clarification is invalid")
    elif value.decision == "needs_clarification":
        if not isinstance(value.clarification, str) or not value.clarification.strip():
            raise RetrievalServiceContractError("scope clarification is invalid")
    else:
        raise RetrievalServiceContractError("scope decision is invalid")
    return value


def _orchestrate(
    *,
    request: ApiChatRequest,
    request_id: str,
    api_policy: ApiPolicy,
    injection_policy: InjectionPolicy,
    service_policy: RetrievalServicePolicy,
    ports: RetrievalServicePorts,
    trace: _TimedStageTrace,
) -> RetrievalServiceExecution:
    if (
        not isinstance(request, ApiChatRequest)
        or not isinstance(api_policy, ApiPolicy)
        or not isinstance(injection_policy, InjectionPolicy)
        or not isinstance(service_policy, RetrievalServicePolicy)
        or not isinstance(ports, RetrievalServicePorts)
        or _DIGEST.fullmatch(request_id or "") is None
    ):
        raise RetrievalServiceContractError("retrieval service input is invalid")
    trace.append("request-accepted")
    direct = scan_untrusted_texts(
        (
            UntrustedText("current_question", request.message),
            *(UntrustedText("conversation_history", turn.content) for turn in request.history),
        ),
        injection_policy,
    )
    if direct.status != "pass":
        trace.append("direct-injection-rejected")
        return _execution(
            _safe_error(request, request_id, "security-rejected", api_policy),
            trace,
            service_policy.digest,
        )
    trace.append("direct-injection-passed")

    scope = _validate_scope_decision(ports.classify_scope(request))
    if scope.decision == "needs_clarification":
        trace.append("scope-clarification")
        response = build_chat_response(
            request=request,
            request_id=request_id,
            status="clarification-required",
            clarification=scope.clarification,
            policy=api_policy,
        )
        return _execution(response, trace, service_policy.digest)
    if scope.decision == "out_of_scope":
        trace.append("scope-rejected")
        return _execution(
            _safe_error(request, request_id, "out-of-scope", api_policy),
            trace,
            service_policy.digest,
        )
    trace.append("scope-allowed")

    try:
        resolution = ports.resolve_query(request)
    except QueryResolutionUnavailable as error:
        trace.append(error.failure_stage)
        raise
    if not isinstance(resolution, ResolvedRetrievalQuery):
        raise RetrievalServiceContractError("query-resolution port result is invalid")
    if resolution.original_query != request.message or resolution.filters != request.filters:
        raise RetrievalServiceContractError("query resolution changed authoritative input")
    if resolution.status == "needs_clarification":
        trace.append("query-clarification")
        response = build_chat_response(
            request=request,
            request_id=request_id,
            status="clarification-required",
            clarification=resolution.clarification,
            policy=api_policy,
        )
        return _execution(response, trace, service_policy.digest)
    if resolution.status != "resolved" or resolution.resolved_query is None:
        raise RetrievalServiceContractError("query-resolution outcome is invalid")
    trace.append("query-resolved")

    retrieved = ports.retrieve_evidence(request, resolution)
    if not isinstance(retrieved, RetrievedEvidence):
        raise RetrievalServiceContractError("retrieval port result is invalid")
    trace.append("retrieval-completed")
    if retrieved.sufficiency.status != "sufficient":
        trace.append("sufficiency-blocked")
        return _execution(
            _safe_error(request, request_id, retrieved.sufficiency.status, api_policy),
            trace,
            service_policy.digest,
            retrieved.telemetry,
        )

    generation_sources = retrieved.generation_sources or retrieved.sources
    evidence = retrieved.generation_evidence or _evidence_from_sources(
        generation_sources
    )
    # Scan exactly the evidence that can influence Gemma. Display sources may
    # contain many additional paragraphs reconstructed solely for the operator;
    # scanning those display-only excerpts made response success depend on UI
    # expansion size and could exceed the bounded scanner field count. Grouping
    # the accepted model evidence by source preserves its full text while
    # keeping the scan boundary independent of internal chunk count.
    model_text_by_source: dict[str, list[str]] = {}
    for item in evidence:
        model_text_by_source.setdefault(item.source_label, []).append(item.excerpt)
    indirect = scan_untrusted_texts(
        tuple(
            UntrustedText("retrieved_content", "\n\n".join(excerpts))
            for _source_label, excerpts in sorted(model_text_by_source.items())
        ),
        injection_policy,
    )
    if indirect.status != "pass":
        trace.append("indirect-injection-rejected")
        return _execution(
            _safe_error(request, request_id, "security-rejected", api_policy),
            trace,
            service_policy.digest,
            retrieved.telemetry,
        )
    trace.extend(("indirect-injection-passed", "sufficiency-passed"))

    try:
        generated = ports.generate_answer(request, resolution.resolved_query, evidence)
    except GroundedGenerationRetryableUnavailable as error:
        # T10 permits one immediate retry only after grounded Gemma transport
        # or response validation fails. Retain completed retrieval telemetry if
        # that bounded retry also fails so diagnostics identify the true stage.
        trace.append(error.failure_stage)
        trace.append("generation-retry")
        try:
            generated = ports.generate_answer(request, resolution.resolved_query, evidence)
        except GroundedGenerationRetryableUnavailable as retry_error:
            trace.append(retry_error.failure_stage)
            trace.append("dependency-unavailable")
            return _execution(
                _safe_error(request, request_id, "temporarily-unavailable", api_policy),
                trace,
                service_policy.digest,
                retrieved.telemetry,
            )
        except RetrievalDependencyUnavailable:
            trace.append("dependency-unavailable")
            return _execution(
                _safe_error(request, request_id, "temporarily-unavailable", api_policy),
                trace,
                service_policy.digest,
                retrieved.telemetry,
            )
    except RetrievalDependencyUnavailable:
        trace.append("dependency-unavailable")
        return _execution(
            _safe_error(request, request_id, "temporarily-unavailable", api_policy),
            trace,
            service_policy.digest,
            retrieved.telemetry,
        )
    if not isinstance(generated, ValidatedGroundedAnswer) or not generated.segments:
        raise RetrievalServiceContractError("generation port result is invalid")
    if (
        retrieved.telemetry is not None
        and retrieved.telemetry.prompt_token_count > 0
        and generated.prompt_tokens != retrieved.telemetry.prompt_token_count
    ):
        raise RetrievalServiceContractError(
            "generation prompt token count changed after admission"
        )
    segments = tuple(
        ApiSegment(segment.text, segment.citation_ids)
        for segment in generated.segments
    )
    display_sources = _cited_display_sources(
        retrieved.sources,
        generation_sources,
        segments,
    )
    response = build_chat_response(
        request=request,
        request_id=request_id,
        status="answered",
        segments=segments,
        sources=display_sources,
        context_budget=_context_budget(retrieved.telemetry),
        policy=api_policy,
    )
    trace.extend(("generation-completed", "response-built"))
    return _execution(
        response,
        trace,
        service_policy.digest,
        retrieved.telemetry,
        generated,
    )


def orchestrate_chat(
    *,
    request: ApiChatRequest,
    request_id: str,
    api_policy: ApiPolicy,
    injection_policy: InjectionPolicy,
    service_policy: RetrievalServicePolicy,
    ports: RetrievalServicePorts,
    clock_ns: Callable[[], int] = time.monotonic_ns,
) -> RetrievalServiceExecution:
    """Run one accepted request and map all failures to fixed client envelopes."""

    trace = _TimedStageTrace(clock_ns)
    try:
        return _orchestrate(
            request=request,
            request_id=request_id,
            api_policy=api_policy,
            injection_policy=injection_policy,
            service_policy=service_policy,
            ports=ports,
            trace=trace,
        )
    except RetrievalDependencyUnavailable:
        response = _safe_error(request, request_id, "temporarily-unavailable", api_policy)
        trace.append("dependency-unavailable")
        return _execution(response, trace, service_policy.digest)
    except Exception:
        response = _safe_error(request, request_id, "internal-error", api_policy)
        trace.append("internal-failure")
        return _execution(response, trace, service_policy.digest)

