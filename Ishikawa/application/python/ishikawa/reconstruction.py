"""Deterministic evidence reconstruction and fail-closed context assembly.

The module begins after retrieval and relationship traversal. It never searches,
calls a model, estimates tokens, or writes persistence state. A caller supplies
an authoritative generation-token counter and a versioned budget policy.
"""

from __future__ import annotations

import re
from collections.abc import Callable, Iterable, Sequence
from dataclasses import dataclass, replace
from typing import Any

from .canonical import domain_digest


_DIGEST = re.compile(r"^[0-9a-f]{64}$")
_ORIGINS = frozenset({"direct", "relationship"})
_STATUSES = frozenset({"ok", "no-evidence", "context-limit"})
_PROFILE_FIELDS = frozenset({"schema_version", "generation", "budget", "diversity"})
_MAX_GENERATION_RELATIONSHIP_GROUPS = 3


class ReconstructionContractError(ValueError):
    """Raised when evidence or a context policy violates the frozen boundary."""


def _profile_mapping(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or not all(isinstance(key, str) for key in value):
        raise ReconstructionContractError(f"{label} must be a string-keyed mapping")
    return value


def _profile_fields(value: dict[str, Any], expected: frozenset[str], label: str) -> None:
    missing = sorted(expected - set(value))
    unknown = sorted(set(value) - expected)
    if missing:
        raise ReconstructionContractError(f"{label} is missing {missing[0]}")
    if unknown:
        raise ReconstructionContractError(f"{label} contains unknown field {unknown[0]}")


def _digest(value: str, label: str) -> str:
    if not isinstance(value, str) or _DIGEST.fullmatch(value) is None:
        raise ReconstructionContractError(f"{label} must be a lowercase SHA-256 identity")
    return value


def _text(value: str, label: str, maximum: int = 65536) -> str:
    if not isinstance(value, str) or not value.strip() or value != value.strip():
        raise ReconstructionContractError(f"{label} must be trimmed nonblank text")
    if len(value) > maximum or "\x00" in value:
        raise ReconstructionContractError(f"{label} exceeds its safe boundary")
    return value


@dataclass(frozen=True, slots=True)
class ReconstructionPolicy:
    """Versioned Tier-2 settings awaiting target tokenizer calibration."""

    tokenizer_model: str
    tokenizer_identity: str
    temperature: float
    top_p: float
    top_k: int
    total_context_tokens: int
    instruction_token_limit: int
    conversation_token_limit: int
    evidence_token_limit: int
    answer_token_reserve: int
    generation_prompt_targets: tuple[int, ...]
    generation_optional_group_limit: int
    normal_per_document_limit: int
    explicit_document_limit: int
    digest: str = ""

    def __post_init__(self) -> None:
        _text(self.tokenizer_model, "tokenizer model", maximum=256)
        _digest(self.tokenizer_identity, "tokenizer identity")
        if type(self.temperature) not in (int, float) or float(self.temperature) != 1.0:
            raise ReconstructionContractError("generation temperature must be 1.0")
        if type(self.top_p) not in (int, float) or float(self.top_p) != 0.95:
            raise ReconstructionContractError("generation top_p must be 0.95")
        if type(self.top_k) is not int or self.top_k != 64:
            raise ReconstructionContractError("generation top_k must be 64")
        numeric = (
            self.total_context_tokens,
            self.instruction_token_limit,
            self.conversation_token_limit,
            self.evidence_token_limit,
            self.answer_token_reserve,
            self.generation_optional_group_limit,
            self.normal_per_document_limit,
            self.explicit_document_limit,
        )
        if any(type(value) is not int or value < 1 for value in numeric):
            raise ReconstructionContractError("reconstruction limits must be positive integers")
        if (
            self.instruction_token_limit
            + self.conversation_token_limit
            + self.evidence_token_limit
            + self.answer_token_reserve
            > self.total_context_tokens
        ):
            raise ReconstructionContractError("budget partitions exceed total context")
        if self.explicit_document_limit < self.normal_per_document_limit:
            raise ReconstructionContractError("explicit-document diversity cannot be more restrictive")
        if (
            not isinstance(self.generation_prompt_targets, tuple)
            or not self.generation_prompt_targets
            or any(type(value) is not int or value < 1 for value in self.generation_prompt_targets)
            or tuple(sorted(set(self.generation_prompt_targets)))
            != self.generation_prompt_targets
            or self.generation_prompt_targets[-1]
            > self.total_context_tokens - self.answer_token_reserve
        ):
            raise ReconstructionContractError("generation prompt targets are invalid")
        canonical = self.canonical()
        expected = domain_digest("ishikawa.reconstruction-policy.v1", canonical)
        if self.digest and self.digest != expected:
            raise ReconstructionContractError("reconstruction policy identity mismatch")
        object.__setattr__(self, "digest", expected)

    def canonical(self) -> dict[str, Any]:
        return {
            "schema_version": 2,
            "sampling": {
                "temperature": float(self.temperature),
                "top_k": self.top_k,
                "top_p": float(self.top_p),
            },
            "tokenizer": {
                "model": self.tokenizer_model,
                "identity": self.tokenizer_identity,
                "count_mode": "with_special_tokens",
            },
            "budget": {
                "total_context_tokens": self.total_context_tokens,
                "instruction_token_limit": self.instruction_token_limit,
                "conversation_token_limit": self.conversation_token_limit,
                "evidence_token_limit": self.evidence_token_limit,
                "answer_token_reserve": self.answer_token_reserve,
                "generation_prompt_targets": list(self.generation_prompt_targets),
            },
            "diversity": {
                "generation_optional_group_limit": self.generation_optional_group_limit,
                "normal_per_document_limit": self.normal_per_document_limit,
                "explicit_document_limit": self.explicit_document_limit,
            },
        }


def validate_reconstruction_profile(value: Any) -> ReconstructionPolicy:
    """Validate the qualified generation-context YAML profile."""

    root = _profile_mapping(value, "reconstruction profile")
    _profile_fields(root, _PROFILE_FIELDS, "reconstruction profile")
    if root["schema_version"] != 2 or type(root["schema_version"]) is not int:
        raise ReconstructionContractError("reconstruction profile requires schema version 2")
    generation = _profile_mapping(root["generation"], "generation settings")
    budget = _profile_mapping(root["budget"], "budget settings")
    diversity = _profile_mapping(root["diversity"], "diversity settings")
    _profile_fields(
        generation,
        frozenset(
            {
                "served_model",
                "tokenizer_identity",
                "chat_template_sha256",
                "enable_thinking",
                "temperature",
                "top_p",
                "top_k",
                "qualified_service_maximum_tokens",
            }
        ),
        "generation settings",
    )
    _profile_fields(
        budget,
        frozenset(
            {
                "total_context_tokens",
                "instruction_token_limit",
                "conversation_token_limit",
                "evidence_token_limit",
                "answer_token_reserve",
                "generation_prompt_targets",
            }
        ),
        "budget settings",
    )
    _profile_fields(
        diversity,
        frozenset(
            {
                "generation_optional_group_limit",
                "normal_per_document_limit",
                "explicit_document_limit",
            }
        ),
        "diversity settings",
    )
    served_model = _text(generation["served_model"], "served model", maximum=256)
    tokenizer_identity = _digest(generation["tokenizer_identity"], "tokenizer identity")
    _digest(generation["chat_template_sha256"], "chat-template identity")
    if generation["enable_thinking"] is not False:
        raise ReconstructionContractError("thinking-enabled generation is not qualified")
    temperature = generation["temperature"]
    top_p = generation["top_p"]
    top_k = generation["top_k"]
    if type(temperature) not in (int, float) or float(temperature) != 1.0:
        raise ReconstructionContractError("generation temperature must be 1.0")
    if type(top_p) not in (int, float) or float(top_p) != 0.95:
        raise ReconstructionContractError("generation top_p must be 0.95")
    if type(top_k) is not int or top_k != 64:
        raise ReconstructionContractError("generation top_k must be 64")
    service_maximum = generation["qualified_service_maximum_tokens"]
    if type(service_maximum) is not int or service_maximum < 1:
        raise ReconstructionContractError("qualified service maximum must be a positive integer")
    numeric_names = (
        "total_context_tokens",
        "instruction_token_limit",
        "conversation_token_limit",
        "evidence_token_limit",
        "answer_token_reserve",
    )
    numeric = {name: budget[name] for name in numeric_names}
    if any(type(item) is not int or item < 1 for item in numeric.values()):
        raise ReconstructionContractError("budget settings must be positive integers")
    if numeric["total_context_tokens"] > service_maximum:
        raise ReconstructionContractError("application context exceeds qualified service maximum")
    if sum(numeric[name] for name in numeric_names[1:]) != numeric["total_context_tokens"]:
        raise ReconstructionContractError("budget partitions must exactly equal total context")
    raw_targets = budget["generation_prompt_targets"]
    if (
        not isinstance(raw_targets, list)
        or not raw_targets
        or any(type(value) is not int or value < 1 for value in raw_targets)
    ):
        raise ReconstructionContractError("generation prompt targets are invalid")
    return ReconstructionPolicy(
        tokenizer_model=served_model,
        tokenizer_identity=tokenizer_identity,
        temperature=float(temperature),
        top_p=float(top_p),
        top_k=top_k,
        total_context_tokens=numeric["total_context_tokens"],
        instruction_token_limit=numeric["instruction_token_limit"],
        conversation_token_limit=numeric["conversation_token_limit"],
        evidence_token_limit=numeric["evidence_token_limit"],
        answer_token_reserve=numeric["answer_token_reserve"],
        generation_prompt_targets=tuple(raw_targets),
        generation_optional_group_limit=diversity[
            "generation_optional_group_limit"
        ],
        normal_per_document_limit=diversity["normal_per_document_limit"],
        explicit_document_limit=diversity["explicit_document_limit"],
    )


@dataclass(frozen=True, slots=True)
class EvidenceCitation:
    citation_id: str
    document_id: str
    document_version_id: str
    document_key: str
    page_start: int
    page_end: int
    structural_path: tuple[str, ...]

    def __post_init__(self) -> None:
        for label, value in (
            ("citation identity", self.citation_id),
            ("document identity", self.document_id),
            ("document-version identity", self.document_version_id),
        ):
            _digest(value, label)
        _text(self.document_key, "document key", maximum=256)
        if self.page_start < 1 or self.page_end < self.page_start:
            raise ReconstructionContractError("citation page range is invalid")
        if any(not isinstance(item, str) or not item for item in self.structural_path):
            raise ReconstructionContractError("citation structural path is invalid")


@dataclass(frozen=True, slots=True)
class EvidenceCandidate:
    chunk_id: str
    retrieval_text_digest: str
    retrieval_text: str
    projection_kind: str
    ordinal: int
    retrieval_rank: int
    origin: str
    inclusion_reason: str
    citations: tuple[EvidenceCitation, ...]
    retrieval_group_id: str | None = None
    relationship_provenance: tuple[str, ...] = ()

    def __post_init__(self) -> None:
        _digest(self.chunk_id, "chunk identity")
        _digest(self.retrieval_text_digest, "retrieval-text identity")
        _text(self.retrieval_text, "retrieval text")
        _text(self.projection_kind, "projection kind", maximum=128)
        _text(self.inclusion_reason, "inclusion reason", maximum=256)
        if self.ordinal < 0 or self.retrieval_rank < 1:
            raise ReconstructionContractError("candidate ordinal or rank is invalid")
        if self.origin not in _ORIGINS:
            raise ReconstructionContractError("candidate origin is unsupported")
        if self.retrieval_group_id is not None:
            _text(self.retrieval_group_id, "candidate retrieval group", maximum=512)
        if not self.citations:
            raise ReconstructionContractError("candidate requires at least one citation")
        if len({item.citation_id for item in self.citations}) != len(self.citations):
            raise ReconstructionContractError("candidate contains duplicate citations")
        if self.origin == "relationship" and not self.relationship_provenance:
            raise ReconstructionContractError("relationship evidence requires provenance")
        if self.origin == "direct" and self.relationship_provenance:
            raise ReconstructionContractError("direct evidence cannot claim relationship provenance")

    @property
    def primary_version_id(self) -> str:
        return self.citations[0].document_version_id

    @property
    def primary_document_id(self) -> str:
        return self.citations[0].document_id


@dataclass(frozen=True, slots=True)
class CompleteProcedureTarget:
    """One document or structural subtree that must be reconstructed whole."""
    document_version_id: str
    structural_path: tuple[str, ...]

    def __post_init__(self) -> None:
        _digest(self.document_version_id, "procedure document-version identity")
        if any(not isinstance(item, str) or not item for item in self.structural_path):
            raise ReconstructionContractError("procedure structural path is invalid")


@dataclass(frozen=True, slots=True)
class ReconstructionAction:
    candidate_id: str
    action: str
    reason: str
    canonical_candidate_id: str | None = None


@dataclass(frozen=True, slots=True)
class SourceGroup:
    source_label: str
    document_id: str
    document_version_id: str
    document_key: str
    passage_ids: tuple[str, ...]
    citation_ids: tuple[str, ...]


@dataclass(frozen=True, slots=True)
class ReconstructedPassage:
    passage_id: str
    selection_group_id: str
    text: str
    token_count: int
    projection_kind: str
    source_ordinal: int
    inclusion_reason: str
    citations: tuple[EvidenceCitation, ...]
    relationship_provenance: tuple[str, ...]

    def __post_init__(self) -> None:
        _digest(self.passage_id, "passage identity")
        _text(self.selection_group_id, "selection group", maximum=512)


@dataclass(frozen=True, slots=True)
class EvidencePackage:
    status: str
    reason_code: str
    policy_identity: str
    selected: tuple[ReconstructedPassage, ...]
    omitted: tuple[ReconstructionAction, ...]
    actions: tuple[ReconstructionAction, ...]
    source_groups: tuple[SourceGroup, ...]
    instruction_tokens: int
    conversation_tokens: int
    evidence_tokens: int
    answer_token_reserve: int
    complete_procedure: bool

    def __post_init__(self) -> None:
        if self.status not in _STATUSES:
            raise ReconstructionContractError("evidence-package status is unsupported")


def _sort_key(item: EvidenceCandidate) -> tuple[int, int, str]:
    return (item.retrieval_rank, 0 if item.origin == "direct" else 1, item.chunk_id)


def _merge_citations(*groups: Iterable[EvidenceCitation]) -> tuple[EvidenceCitation, ...]:
    by_id: dict[str, EvidenceCitation] = {}
    for group in groups:
        for citation in group:
            existing = by_id.setdefault(citation.citation_id, citation)
            if existing != citation:
                raise ReconstructionContractError("one citation identity has conflicting anchors")
    return tuple(sorted(by_id.values(), key=lambda item: (item.document_version_id, item.page_start, item.citation_id)))


def deduplicate_candidates(
    candidates: Sequence[EvidenceCandidate],
) -> tuple[tuple[EvidenceCandidate, ...], tuple[ReconstructionAction, ...]]:
    """Remove only exact chunk/projection duplicates and retain every citation."""

    by_chunk: dict[str, EvidenceCandidate] = {}
    actions: list[ReconstructionAction] = []
    for item in sorted(candidates, key=_sort_key):
        current = by_chunk.get(item.chunk_id)
        if current is None:
            by_chunk[item.chunk_id] = item
            continue
        if current.retrieval_text_digest != item.retrieval_text_digest:
            raise ReconstructionContractError("one chunk identity has conflicting retrieval text")
        merged_provenance = _merge_relationship_provenance(current, item)
        by_chunk[item.chunk_id] = replace(
            current,
            citations=_merge_citations(current.citations, item.citations),
            retrieval_group_id=_merge_retrieval_group_ids(current, item),
            origin="relationship" if merged_provenance else "direct",
            inclusion_reason=(
                current.inclusion_reason
                if current.relationship_provenance
                else item.inclusion_reason
            ),
            relationship_provenance=merged_provenance,
        )
        actions.append(ReconstructionAction(item.chunk_id, "deduplicated", "exact_chunk_identity", current.chunk_id))

    by_projection: dict[str, EvidenceCandidate] = {}
    for item in sorted(by_chunk.values(), key=_sort_key):
        current = by_projection.get(item.retrieval_text_digest)
        if current is None:
            by_projection[item.retrieval_text_digest] = item
            continue
        if current.retrieval_text != item.retrieval_text:
            raise ReconstructionContractError("one retrieval-text identity has conflicting text")
        merged_provenance = _merge_relationship_provenance(current, item)
        by_projection[item.retrieval_text_digest] = replace(
            current,
            citations=_merge_citations(current.citations, item.citations),
            retrieval_group_id=_merge_retrieval_group_ids(current, item),
            origin="relationship" if merged_provenance else "direct",
            inclusion_reason=(
                current.inclusion_reason
                if current.relationship_provenance
                else item.inclusion_reason
            ),
            relationship_provenance=merged_provenance,
        )
        actions.append(ReconstructionAction(item.chunk_id, "deduplicated", "exact_retrieval_projection", current.chunk_id))
    return tuple(sorted(by_projection.values(), key=_sort_key)), tuple(actions)


def _merge_retrieval_group_ids(
    first: EvidenceCandidate,
    second: EvidenceCandidate,
) -> str | None:
    """Preserve one compatible retrieval-selection group across deduplication."""

    if first.retrieval_group_id == second.retrieval_group_id:
        return first.retrieval_group_id
    if first.retrieval_group_id is None:
        return second.retrieval_group_id
    if second.retrieval_group_id is None:
        return first.retrieval_group_id
    # One authoritative atom can arrive through both its directly ranked
    # structural representative and a relationship locator. Keep the direct
    # selection group; relationship coverage is carried separately by the
    # provenance record. Equal projections from distinct structural groups
    # cannot safely claim either complete group after projection deduplication.
    if first.origin == "direct" and second.origin == "relationship":
        return first.retrieval_group_id
    if second.origin == "direct" and first.origin == "relationship":
        return second.retrieval_group_id
    return None


def _merge_relationship_provenance(
    first: EvidenceCandidate,
    second: EvidenceCandidate,
) -> tuple[str, ...]:
    """Retain one intact, priority-ordered relationship audit record."""

    if not first.relationship_provenance:
        return second.relationship_provenance
    if not second.relationship_provenance:
        return first.relationship_provenance
    if first.relationship_provenance == second.relationship_provenance:
        return first.relationship_provenance
    # Candidates are merged in retrieval-priority order. A target document is
    # expanded at most once, but retain the earlier complete record if a
    # duplicate route is nevertheless observed. Never sort the record fields:
    # element zero is the relationship identity used for citation coverage.
    return first.relationship_provenance


def reconstruct_complete_procedure(
    target: CompleteProcedureTarget,
    document_inventory: Sequence[EvidenceCandidate],
    *,
    inventory_complete: bool,
) -> tuple[EvidenceCandidate, ...]:
    """Assemble one complete structural subtree from verified inventory."""

    if not inventory_complete:
        raise ReconstructionContractError("complete procedure requires complete document inventory")
    if not document_inventory:
        raise ReconstructionContractError("complete procedure inventory is empty")
    if any(item.primary_version_id != target.document_version_id for item in document_inventory):
        raise ReconstructionContractError("procedure inventory spans document versions")
    eligible = []
    for item in document_inventory:
        path = item.citations[0].structural_path
        if target.structural_path and path[: len(target.structural_path)] != target.structural_path:
            continue
        if item.projection_kind in {"page_status", "table_context"}:
            continue
        eligible.append(replace(item, retrieval_rank=1, inclusion_reason="complete_procedure"))
    if not eligible:
        raise ReconstructionContractError("complete procedure target has no structural units")
    if len({item.ordinal for item in eligible}) != len(eligible):
        raise ReconstructionContractError("procedure inventory has duplicate source ordinals")
    return tuple(sorted(eligible, key=lambda item: (item.ordinal, item.chunk_id)))


def _count(counter: Callable[[str], int], text: str) -> int:
    value = counter(text)
    if type(value) is not int or value < 1:
        raise ReconstructionContractError("token counter returned an invalid count")
    return value


def _passage(item: EvidenceCandidate, token_count: int) -> ReconstructedPassage:
    return ReconstructedPassage(
        passage_id=item.chunk_id,
        selection_group_id=item.retrieval_group_id or item.chunk_id,
        text=item.retrieval_text,
        token_count=token_count,
        projection_kind=item.projection_kind,
        source_ordinal=item.ordinal,
        inclusion_reason=item.inclusion_reason,
        citations=item.citations,
        relationship_provenance=item.relationship_provenance,
    )


def _source_groups(passages: Sequence[ReconstructedPassage]) -> tuple[SourceGroup, ...]:
    versions: dict[str, dict[str, Any]] = {}
    for passage_rank, passage in enumerate(passages):
        for citation in passage.citations:
            state = versions.setdefault(
                citation.document_version_id,
                {
                    "rank": passage_rank,
                    "document_id": citation.document_id,
                    "document_key": citation.document_key,
                    "passages": [],
                    "citations": [],
                },
            )
            state["rank"] = min(state["rank"], passage_rank)
            if passage.passage_id not in state["passages"]:
                state["passages"].append(passage.passage_id)
            if citation.citation_id not in state["citations"]:
                state["citations"].append(citation.citation_id)
    ordered = sorted(versions.items(), key=lambda item: (item[1]["rank"], item[0]))
    return tuple(
        SourceGroup(
            source_label=f"Source {index}",
            document_id=state["document_id"],
            document_version_id=version_id,
            document_key=state["document_key"],
            passage_ids=tuple(state["passages"]),
            citation_ids=tuple(state["citations"]),
        )
        for index, (version_id, state) in enumerate(ordered, start=1)
    )


def assemble_evidence(
    candidates: Sequence[EvidenceCandidate],
    *,
    policy: ReconstructionPolicy,
    token_counter: Callable[[str], int],
    instruction_tokens: int,
    conversation_tokens: int,
    complete_procedure: bool = False,
    explicit_document_version_id: str | None = None,
    require_relationship_coverage: bool = False,
) -> EvidencePackage:
    """Select atomic evidence deterministically without silent truncation."""

    if type(instruction_tokens) is not int or instruction_tokens < 0:
        raise ReconstructionContractError("instruction token count is invalid")
    if type(conversation_tokens) is not int or conversation_tokens < 0:
        raise ReconstructionContractError("conversation token count is invalid")
    if explicit_document_version_id is not None:
        _digest(explicit_document_version_id, "explicit document-version identity")
    if type(require_relationship_coverage) is not bool:
        raise ReconstructionContractError("relationship coverage flag is invalid")
    if instruction_tokens > policy.instruction_token_limit:
        return EvidencePackage("context-limit", "INSTRUCTION_CONTEXT_LIMIT", policy.digest, (), (), (), (), instruction_tokens, conversation_tokens, 0, policy.answer_token_reserve, complete_procedure)
    if conversation_tokens > policy.conversation_token_limit:
        return EvidencePackage("context-limit", "CONVERSATION_CONTEXT_LIMIT", policy.digest, (), (), (), (), instruction_tokens, conversation_tokens, 0, policy.answer_token_reserve, complete_procedure)

    # Relationship traversal remains complete, but generation must not turn
    # every edge reached from the direct top twenty into a mandatory answer
    # obligation. A relationship candidate inherits the fused rank of its
    # direct seed, so the minimum candidate rank is the deterministic pair
    # rank. Admit only the three highest-ranked relationship identities before
    # deduplication. Filtering first is important: if the same authoritative
    # atom also arrived directly, its direct route must remain eligible even
    # when its relationship route is outside this bounded generation set.
    relationship_ranks: dict[str, int] = {}
    for item in candidates:
        if item.origin != "relationship":
            continue
        relationship_id = item.relationship_provenance[0]
        relationship_ranks[relationship_id] = min(
            relationship_ranks.get(relationship_id, item.retrieval_rank),
            item.retrieval_rank,
        )
    admitted_relationships = frozenset(
        relationship_id
        for relationship_id, _rank in sorted(
            relationship_ranks.items(), key=lambda value: (value[1], value[0])
        )[:_MAX_GENERATION_RELATIONSHIP_GROUPS]
    )
    bounded_candidates: list[EvidenceCandidate] = []
    relationship_actions: list[ReconstructionAction] = []
    for item in candidates:
        if (
            item.origin == "relationship"
            and item.relationship_provenance[0] not in admitted_relationships
        ):
            relationship_actions.append(
                ReconstructionAction(
                    item.chunk_id,
                    "omitted",
                    "relationship_generation_group_limit",
                )
            )
            continue
        bounded_candidates.append(item)

    deduplicated, deduplication_actions = deduplicate_candidates(bounded_candidates)
    actions = (*relationship_actions, *deduplication_actions)
    if not deduplicated:
        return EvidencePackage("no-evidence", "NO_RECONSTRUCTABLE_EVIDENCE", policy.digest, (), (), actions, (), instruction_tokens, conversation_tokens, 0, policy.answer_token_reserve, complete_procedure)
    available = min(
        policy.evidence_token_limit,
        policy.total_context_tokens - instruction_tokens - conversation_tokens - policy.answer_token_reserve,
    )
    if available < 1:
        omitted = tuple(ReconstructionAction(item.chunk_id, "omitted", "evidence_budget_unavailable") for item in deduplicated)
        return EvidencePackage("context-limit", "EVIDENCE_CONTEXT_LIMIT", policy.digest, (), omitted, actions, (), instruction_tokens, conversation_tokens, 0, policy.answer_token_reserve, complete_procedure)

    if complete_procedure:
        deduplicated = tuple(
            sorted(deduplicated, key=lambda item: (item.primary_version_id, item.ordinal, item.chunk_id))
        )
        joined = "\n\n".join(item.retrieval_text for item in deduplicated)
        required = _count(token_counter, joined)
        if required > available:
            omitted = tuple(ReconstructionAction(item.chunk_id, "omitted", "complete_unit_exceeds_budget") for item in deduplicated)
            return EvidencePackage("context-limit", "COMPLETE_PROCEDURE_CONTEXT_LIMIT", policy.digest, (), omitted, actions, (), instruction_tokens, conversation_tokens, 0, policy.answer_token_reserve, True)
        passages = tuple(_passage(item, _count(token_counter, item.retrieval_text)) for item in deduplicated)
        return EvidencePackage("ok", "EVIDENCE_RECONSTRUCTED", policy.digest, passages, (), actions, _source_groups(passages), instruction_tokens, conversation_tokens, required, policy.answer_token_reserve, True)

    # A retrieval-only structural representative ranks one section/page unit,
    # then expands to its authoritative atoms before citation or generation.
    # Apply diversity and budget decisions to that complete unit. Counting its
    # atoms independently lets one winning page consume every document slot
    # and silently starves a second responsive page.
    selection_units: list[tuple[EvidenceCandidate, ...]] = []
    units_by_key: dict[tuple[str, str], int] = {}
    for item in deduplicated:
        unit_key = (
            item.primary_version_id,
            item.retrieval_group_id or item.chunk_id,
        )
        unit_index = units_by_key.get(unit_key)
        if unit_index is None:
            units_by_key[unit_key] = len(selection_units)
            selection_units.append((item,))
        else:
            selection_units[unit_index] = (*selection_units[unit_index], item)

    # An explicit relationship-navigation question reserves both sides of a
    # discovered reference. For an ordinary question, direct query-responsive
    # units come first and relationship expansions remain optional context.
    relationship_seed_citations = {
        item.relationship_provenance[4]
        for item in deduplicated
        if len(item.relationship_provenance) >= 5
    }

    def selection_priority(unit: tuple[EvidenceCandidate, ...]) -> int:
        target = any(item.relationship_provenance for item in unit)
        seed = any(
            citation.citation_id in relationship_seed_citations
            for item in unit
            for citation in item.citations
        )
        if require_relationship_coverage:
            return 0 if target else 1 if seed else 2
        return 1 if target else 0

    selection_units.sort(
        key=lambda unit: (
            selection_priority(unit),
            min(item.retrieval_rank for item in unit),
            unit[0].primary_version_id,
            unit[0].retrieval_group_id or unit[0].chunk_id,
        )
    )

    selected_items: list[EvidenceCandidate] = []
    omitted: list[ReconstructionAction] = []
    document_counts: dict[str, int] = {}
    document_citations: dict[str, set[str]] = {}
    evidence_tokens = 0
    for unit in selection_units:
        version_id = unit[0].primary_version_id
        limit = policy.explicit_document_limit if version_id == explicit_document_version_id else policy.normal_per_document_limit
        if document_counts.get(version_id, 0) >= limit:
            omitted.extend(
                ReconstructionAction(item.chunk_id, "omitted", "document_diversity_limit")
                for item in unit
            )
            continue
        additions_by_version: dict[str, set[str]] = {}
        for item in unit:
            for citation in item.citations:
                additions_by_version.setdefault(citation.document_version_id, set()).add(
                    citation.citation_id
                )
        if any(
            len(document_citations.get(cited_version, set()) | additions) > 20
            for cited_version, additions in additions_by_version.items()
        ):
            omitted.extend(
                ReconstructionAction(item.chunk_id, "omitted", "source_excerpt_limit")
                for item in unit
            )
            continue
        proposed = "\n\n".join(
            candidate.retrieval_text for candidate in (*selected_items, *unit)
        )
        proposed_tokens = _count(token_counter, proposed)
        if proposed_tokens > available:
            omitted.extend(
                ReconstructionAction(item.chunk_id, "omitted", "evidence_budget_limit")
                for item in unit
            )
            continue
        selected_items.extend(unit)
        document_counts[version_id] = document_counts.get(version_id, 0) + 1
        for cited_version, additions in additions_by_version.items():
            document_citations.setdefault(cited_version, set()).update(additions)
        evidence_tokens = proposed_tokens
    if not selected_items:
        return EvidencePackage("context-limit", "EVIDENCE_CONTEXT_LIMIT", policy.digest, (), tuple(omitted), actions, (), instruction_tokens, conversation_tokens, 0, policy.answer_token_reserve, False)
    passages = tuple(_passage(item, _count(token_counter, item.retrieval_text)) for item in selected_items)
    return EvidencePackage("ok", "EVIDENCE_RECONSTRUCTED", policy.digest, passages, tuple(omitted), actions, _source_groups(passages), instruction_tokens, conversation_tokens, evidence_tokens, policy.answer_token_reserve, False)


def retain_evidence_selection_groups(
    package: EvidencePackage,
    retained_groups: frozenset[tuple[str, str]],
    *,
    token_counter: Callable[[str], int],
    omission_reason: str = "generation_prompt_budget_limit",
) -> EvidencePackage:
    """Retain complete structural selection units and rebuild package metadata.

    Exact chat-template admission may discover overhead that is invisible when
    source prose is counted alone. This helper removes only complete units; it
    never clips an authoritative passage or leaves source/citation metadata
    inconsistent with the model evidence.
    """

    if not isinstance(package, EvidencePackage) or package.status != "ok":
        raise ReconstructionContractError("only an accepted evidence package can be trimmed")
    if not isinstance(retained_groups, frozenset) or any(
        not isinstance(group, tuple)
        or len(group) != 2
        or not all(isinstance(value, str) and value for value in group)
        for group in retained_groups
    ):
        raise ReconstructionContractError("retained selection groups are invalid")
    _text(omission_reason, "omission reason", maximum=256)
    selected: list[ReconstructedPassage] = []
    removed: list[ReconstructionAction] = []
    for passage in package.selected:
        version_id = passage.citations[0].document_version_id
        if (version_id, passage.selection_group_id) in retained_groups:
            selected.append(passage)
        else:
            removed.append(
                ReconstructionAction(passage.passage_id, "omitted", omission_reason)
            )
    if package.complete_procedure and len(selected) != len(package.selected):
        raise ReconstructionContractError("complete procedure evidence cannot be trimmed")
    if not selected:
        return replace(
            package,
            status="context-limit",
            reason_code="GENERATION_PROMPT_CONTEXT_LIMIT",
            selected=(),
            omitted=(*package.omitted, *removed),
            source_groups=(),
            evidence_tokens=0,
        )
    joined = "\n\n".join(item.text for item in selected)
    return replace(
        package,
        selected=tuple(selected),
        omitted=(*package.omitted, *removed),
        source_groups=_source_groups(selected),
        evidence_tokens=_count(token_counter, joined),
    )
