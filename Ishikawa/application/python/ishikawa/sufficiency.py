"""Fail-closed deterministic post-retrieval evidence-sufficiency gate."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping

from .canonical import domain_digest
from .reconstruction import EvidencePackage
from .relevance import RelevanceDecision


_LANES = ("exact", "lexical", "vector")
_LANE_STATES = frozenset({"pass", "not_applicable", "failed"})
_REASONS = (
    "EVIDENCE_SUFFICIENT",
    "EXACT_DOCUMENT_EVIDENCE_SUFFICIENT",
    "RETRIEVAL_LANE_FAILURE",
    "NO_RETRIEVAL_CANDIDATES",
    "NO_AUTHORIZED_EVIDENCE",
    "EXACT_CONSTRAINT_UNSATISFIED",
    "RELATIONSHIP_COVERAGE_INCOMPLETE",
    "SOURCE_VERSION_CONFLICT",
    "NO_RECONSTRUCTABLE_EVIDENCE",
    "CITATION_SET_INVALID",
    "RELEVANCE_NOT_QUALIFIED",
    "RELEVANCE_INSUFFICIENT",
    "COMPLETE_STRUCTURE_INCOMPLETE",
    "CONTEXT_LIMIT",
)


class SufficiencyContractError(ValueError):
    """Raised when policy or evidence signals violate the contract."""


@dataclass(frozen=True, slots=True)
class SufficiencyPolicy:
    digest: str
    allow_unique_exact_document_relevance_override: bool


@dataclass(frozen=True, slots=True)
class SufficiencySignals:
    lane_states: tuple[tuple[str, str], ...]
    fused_candidate_count: int
    authorized_candidate_count: int
    exact_constraint_required: bool
    exact_constraint_satisfied: bool
    unique_exact_document_constraint: bool
    relationship_coverage_required: bool
    relationship_coverage_complete: bool
    source_version_conflict: bool
    relevance_decision: RelevanceDecision | None
    complete_structure_requested: bool

    def __post_init__(self) -> None:
        if (
            len(self.lane_states) != len(_LANES)
            or tuple(name for name, _ in self.lane_states) != _LANES
            or any(state not in _LANE_STATES for _, state in self.lane_states)
        ):
            raise SufficiencyContractError("retrieval lane states are invalid")
        if (
            type(self.fused_candidate_count) is not int
            or self.fused_candidate_count < 0
            or type(self.authorized_candidate_count) is not int
            or not 0 <= self.authorized_candidate_count <= self.fused_candidate_count
        ):
            raise SufficiencyContractError("candidate counts are invalid")
        flags = (
            self.exact_constraint_required,
            self.exact_constraint_satisfied,
            self.unique_exact_document_constraint,
            self.relationship_coverage_required,
            self.relationship_coverage_complete,
            self.source_version_conflict,
            self.complete_structure_requested,
        )
        if any(type(value) is not bool for value in flags):
            raise SufficiencyContractError("sufficiency flags are invalid")
        if self.unique_exact_document_constraint and not (
            self.exact_constraint_required and self.exact_constraint_satisfied
        ):
            raise SufficiencyContractError(
                "unique exact-document constraint is not satisfied"
            )
        if self.relevance_decision is not None and not isinstance(
            self.relevance_decision, RelevanceDecision
        ):
            raise SufficiencyContractError("relevance decision is invalid")


@dataclass(frozen=True, slots=True)
class SufficiencyDecision:
    status: str
    reason_code: str
    policy_identity: str
    evidence_passages: int
    citation_count: int
    relevance_profile_identity: str | None


def _exact_mapping(value: Any, keys: frozenset[str], label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping) or set(value) != keys:
        raise SufficiencyContractError(f"{label} fields are invalid")
    return value


def validate_sufficiency_profile(value: Any) -> SufficiencyPolicy:
    root = _exact_mapping(
        value,
        frozenset({"schema_version", "checks", "statuses", "reason_codes"}),
        "sufficiency profile",
    )
    if root["schema_version"] != 2 or type(root["schema_version"]) is not int:
        raise SufficiencyContractError("sufficiency profile schema version is invalid")
    checks = _exact_mapping(
        root["checks"],
        frozenset(
            {
                "required_semantic_lanes", "fail_closed_on_lane_error",
                "require_authorized_candidate", "require_exact_constraint_satisfaction",
                "require_relationship_coverage", "require_valid_citations",
                "require_calibrated_relevance", "source_conflict_status",
                "incomplete_structure_status",
                "allow_unique_exact_document_relevance_override",
            }
        ),
        "sufficiency checks",
    )
    statuses = _exact_mapping(
        root["statuses"],
        frozenset({"eligible", "unavailable", "inadequate", "over_budget"}),
        "sufficiency statuses",
    )
    expected_checks = {
        "required_semantic_lanes": ["lexical", "vector"],
        "fail_closed_on_lane_error": True,
        "require_authorized_candidate": True,
        "require_exact_constraint_satisfaction": True,
        "require_relationship_coverage": True,
        "require_valid_citations": True,
        "require_calibrated_relevance": True,
        "allow_unique_exact_document_relevance_override": True,
        "source_conflict_status": "insufficient-evidence",
        "incomplete_structure_status": "context-limit",
    }
    expected_statuses = {
        "eligible": "sufficient",
        "unavailable": "temporarily-unavailable",
        "inadequate": "insufficient-evidence",
        "over_budget": "context-limit",
    }
    if checks != expected_checks or statuses != expected_statuses or tuple(root["reason_codes"]) != _REASONS:
        raise SufficiencyContractError("sufficiency policy contract is invalid")
    canonical = {
        "checks": dict(checks),
        "reason_codes": list(_REASONS),
        "schema_version": 2,
        "statuses": dict(statuses),
    }
    return SufficiencyPolicy(
        domain_digest("ishikawa.sufficiency-profile.v2", canonical),
        checks["allow_unique_exact_document_relevance_override"],
    )


def _decision(
    policy: SufficiencyPolicy,
    status: str,
    reason: str,
    package: EvidencePackage,
    relevance_identity: str | None,
) -> SufficiencyDecision:
    citations = {citation.citation_id for passage in package.selected for citation in passage.citations}
    return SufficiencyDecision(
        status,
        reason,
        policy.digest,
        len(package.selected),
        len(citations),
        relevance_identity,
    )


def evaluate_evidence_sufficiency(
    signals: SufficiencySignals,
    package: EvidencePackage,
    policy: SufficiencyPolicy,
) -> SufficiencyDecision:
    if not isinstance(signals, SufficiencySignals) or not isinstance(package, EvidencePackage):
        raise SufficiencyContractError("sufficiency input is invalid")
    if not isinstance(policy, SufficiencyPolicy):
        raise SufficiencyContractError("sufficiency policy is invalid")
    lane_states = dict(signals.lane_states)
    if any(state == "failed" for state in lane_states.values()) or any(
        lane_states[name] != "pass" for name in ("lexical", "vector")
    ):
        return _decision(policy, "temporarily-unavailable", "RETRIEVAL_LANE_FAILURE", package, None)
    if package.status == "context-limit":
        return _decision(policy, "context-limit", "CONTEXT_LIMIT", package, None)
    if signals.complete_structure_requested and not package.complete_procedure:
        return _decision(policy, "context-limit", "COMPLETE_STRUCTURE_INCOMPLETE", package, None)
    if signals.fused_candidate_count == 0:
        return _decision(policy, "insufficient-evidence", "NO_RETRIEVAL_CANDIDATES", package, None)
    if signals.authorized_candidate_count == 0:
        return _decision(policy, "insufficient-evidence", "NO_AUTHORIZED_EVIDENCE", package, None)
    if signals.exact_constraint_required and not signals.exact_constraint_satisfied:
        return _decision(policy, "insufficient-evidence", "EXACT_CONSTRAINT_UNSATISFIED", package, None)
    if signals.relationship_coverage_required and not signals.relationship_coverage_complete:
        return _decision(policy, "insufficient-evidence", "RELATIONSHIP_COVERAGE_INCOMPLETE", package, None)
    if signals.source_version_conflict:
        return _decision(policy, "insufficient-evidence", "SOURCE_VERSION_CONFLICT", package, None)
    if package.status != "ok" or not package.selected:
        return _decision(policy, "insufficient-evidence", "NO_RECONSTRUCTABLE_EVIDENCE", package, None)
    selected_citations = {
        citation.citation_id for passage in package.selected for citation in passage.citations
    }
    grouped_citations = {citation for group in package.source_groups for citation in group.citation_ids}
    if not selected_citations or selected_citations != grouped_citations:
        return _decision(policy, "insufficient-evidence", "CITATION_SET_INVALID", package, None)
    if signals.relevance_decision is None:
        return _decision(policy, "insufficient-evidence", "RELEVANCE_NOT_QUALIFIED", package, None)
    if signals.relevance_decision.status == "insufficient":
        if (
            policy.allow_unique_exact_document_relevance_override
            and signals.unique_exact_document_constraint
        ):
            return _decision(
                policy,
                "sufficient",
                "EXACT_DOCUMENT_EVIDENCE_SUFFICIENT",
                package,
                signals.relevance_decision.profile_identity,
            )
        return _decision(
            policy,
            "insufficient-evidence",
            "RELEVANCE_INSUFFICIENT",
            package,
            signals.relevance_decision.profile_identity,
        )
    return _decision(
        policy,
        "sufficient",
        "EVIDENCE_SUFFICIENT",
        package,
        signals.relevance_decision.profile_identity,
    )
