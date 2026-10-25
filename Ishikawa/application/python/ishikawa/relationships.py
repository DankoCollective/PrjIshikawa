"""Deterministic relationship discovery and bounded one-hop traversal.

This module does not infer relationships with a model.  It resolves explicit
identifier text against a candidate-corpus identifier inventory, represents
unresolved observations without guessing, and keeps relationship-derived
retrieval provenance separate from lexical or vector evidence.
"""

from __future__ import annotations

import re
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass, replace
from typing import Any

from .canonical import domain_digest
from .errors import IshikawaValidationError


_IDENTIFIER = re.compile(r"^[a-z][a-z0-9._-]{0,127}$")
_DIGEST = re.compile(r"^[0-9a-f]{64}$")
_REFERENCE = re.compile(r"\b(?:[0-9]{2}\s+[A-Z][A-Z0-9]{2}\s+[0-9]{4}|[A-Z][A-Z0-9]{1,15}-[0-9]{4})\b")
_POLICY_DECLARATION = re.compile(
    rf"^Policy Number:\s*({_REFERENCE.pattern})(?:[.;]|$)", re.IGNORECASE
)
_FORM_DECLARATION = re.compile(
    rf"^(?:Form no\.\s*)?({_REFERENCE.pattern})$", re.IGNORECASE
)
_KINDS = frozenset({"document", "document_version", "structural_unit", "external"})
_STATUSES = frozenset({"active", "retired"})
_VERSION_BEHAVIORS = frozenset(
    {"resolve_active_version", "fixed_version", "fixed_external_identity"}
)
_ACCEPTED_TYPE_IDS = frozenset(
    {"explicit_reference.document", "explicit_reference.external", "supersedes"}
)


def _fail(reason: str, message: str) -> None:
    raise IshikawaValidationError("REJECTED", reason, message)


def _mapping(value: Any, label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping) or not all(isinstance(key, str) for key in value):
        _fail("RELATIONSHIP_SCHEMA_TYPE_INVALID", f"{label} must be a string-keyed mapping.")
    return value


def _exact_fields(value: Mapping[str, Any], fields: frozenset[str], label: str) -> None:
    missing = sorted(fields - set(value))
    unknown = sorted(set(value) - fields)
    if missing:
        _fail("RELATIONSHIP_SCHEMA_FIELD_MISSING", f"{label} is missing '{missing[0]}'.")
    if unknown:
        _fail("RELATIONSHIP_SCHEMA_FIELD_UNKNOWN", f"{label} contains '{unknown[0]}'.")


def _text(value: Any, label: str, *, identifier: bool = False) -> str:
    if not isinstance(value, str) or not value.strip() or value != value.strip():
        _fail("RELATIONSHIP_SCHEMA_VALUE_INVALID", f"{label} must be a trimmed nonblank string.")
    if identifier and _IDENTIFIER.fullmatch(value) is None:
        _fail("RELATIONSHIP_IDENTIFIER_INVALID", f"{label} has invalid identifier syntax.")
    return value


def _digest(value: str, label: str) -> str:
    if not isinstance(value, str) or _DIGEST.fullmatch(value) is None:
        raise ValueError(f"{label} must be a lowercase SHA-256 identity")
    return value


@dataclass(frozen=True, slots=True)
class RelationshipType:
    relationship_type: str
    display_name: str
    inverse_display_name: str
    source_kind: str
    target_kind: str
    target_version_behavior: str
    influences_retrieval: bool
    status: str

    def canonical(self) -> dict[str, Any]:
        return {
            "relationship_type": self.relationship_type,
            "display_name": self.display_name,
            "inverse_display_name": self.inverse_display_name,
            "source_kind": self.source_kind,
            "target_kind": self.target_kind,
            "target_version_behavior": self.target_version_behavior,
            "influences_retrieval": self.influences_retrieval,
            "status": self.status,
        }


@dataclass(frozen=True, slots=True)
class RelationshipRegistry:
    schema_version: int
    base_retrieval_profile_id: str
    maximum_hops: int
    direction: str
    traversable_types: tuple[str, ...]
    relationship_types: tuple[RelationshipType, ...]
    digest: str
    method_profile_id: str

    def by_id(self) -> dict[str, RelationshipType]:
        return {item.relationship_type: item for item in self.relationship_types}

    def canonical(self) -> dict[str, Any]:
        return {
            "schema_version": self.schema_version,
            "base_retrieval_profile_id": self.base_retrieval_profile_id,
            "traversal": {
                "maximum_hops": self.maximum_hops,
                "direction": self.direction,
                "relationship_types": list(self.traversable_types),
            },
            "relationship_types": [
                item.canonical()
                for item in sorted(self.relationship_types, key=lambda item: item.relationship_type)
            ],
        }


def validate_relationship_registry(value: Any) -> RelationshipRegistry:
    """Validate and canonically identify the qualified relationship registry."""

    root = _mapping(value, "relationship registry")
    _exact_fields(
        root,
        frozenset(
            {"schema_version", "base_retrieval_profile_id", "traversal", "relationship_types"}
        ),
        "relationship registry",
    )
    if type(root["schema_version"]) is not int or root["schema_version"] != 1:
        _fail("RELATIONSHIP_SCHEMA_VERSION_UNSUPPORTED", "relationship registry requires version 1.")
    base_profile = root["base_retrieval_profile_id"]
    if not isinstance(base_profile, str) or _DIGEST.fullmatch(base_profile) is None:
        _fail("RELATIONSHIP_PROFILE_IDENTITY_INVALID", "base profile must be a SHA-256 identity.")

    traversal = _mapping(root["traversal"], "relationship traversal")
    _exact_fields(
        traversal,
        frozenset({"maximum_hops", "direction", "relationship_types"}),
        "relationship traversal",
    )
    if type(traversal["maximum_hops"]) is not int or traversal["maximum_hops"] != 1:
        _fail("RELATIONSHIP_TRAVERSAL_UNSUPPORTED", "only one-hop traversal is qualified.")
    if traversal["direction"] != "outgoing":
        _fail("RELATIONSHIP_TRAVERSAL_UNSUPPORTED", "only outgoing traversal is qualified.")
    traversable = traversal["relationship_types"]
    if not isinstance(traversable, list) or traversable != ["explicit_reference.document"]:
        _fail(
            "RELATIONSHIP_TRAVERSAL_UNSUPPORTED",
            "only explicit document references may influence retrieval.",
        )

    raw_types = root["relationship_types"]
    if not isinstance(raw_types, list) or not raw_types:
        _fail("RELATIONSHIP_SCHEMA_TYPE_INVALID", "relationship types must be a nonempty list.")
    definitions: list[RelationshipType] = []
    fields = frozenset(
        {
            "relationship_type",
            "display_name",
            "inverse_display_name",
            "source_kind",
            "target_kind",
            "target_version_behavior",
            "influences_retrieval",
            "status",
        }
    )
    for index, raw in enumerate(raw_types):
        item = _mapping(raw, f"relationship type {index}")
        _exact_fields(item, fields, f"relationship type {index}")
        source_kind = _text(item["source_kind"], f"relationship type {index} source_kind")
        target_kind = _text(item["target_kind"], f"relationship type {index} target_kind")
        version_behavior = _text(
            item["target_version_behavior"], f"relationship type {index} target behavior"
        )
        status = _text(item["status"], f"relationship type {index} status")
        if source_kind not in _KINDS - {"document_version", "external"} or target_kind not in _KINDS:
            _fail("RELATIONSHIP_ENDPOINT_KIND_INVALID", "relationship endpoint kind is unsupported.")
        if version_behavior not in _VERSION_BEHAVIORS or status not in _STATUSES:
            _fail("RELATIONSHIP_SCHEMA_VALUE_INVALID", "relationship behavior or status is invalid.")
        if type(item["influences_retrieval"]) is not bool:
            _fail("RELATIONSHIP_SCHEMA_VALUE_INVALID", "influences_retrieval must be boolean.")
        definitions.append(
            RelationshipType(
                relationship_type=_text(
                    item["relationship_type"], f"relationship type {index} identity", identifier=True
                ),
                display_name=_text(item["display_name"], f"relationship type {index} display"),
                inverse_display_name=_text(
                    item["inverse_display_name"], f"relationship type {index} inverse display"
                ),
                source_kind=source_kind,
                target_kind=target_kind,
                target_version_behavior=version_behavior,
                influences_retrieval=item["influences_retrieval"],
                status=status,
            )
        )
    by_id = {item.relationship_type: item for item in definitions}
    if len(by_id) != len(definitions):
        _fail("RELATIONSHIP_IDENTIFIER_DUPLICATE", "relationship type identifiers must be unique.")
    if set(by_id) != _ACCEPTED_TYPE_IDS:
        _fail("RELATIONSHIP_TYPE_UNQUALIFIED", "the registry enables an unqualified relationship type.")
    expected = {
        "explicit_reference.document": ("structural_unit", "document", "resolve_active_version", True),
        "explicit_reference.external": ("structural_unit", "external", "fixed_external_identity", False),
        "supersedes": ("document", "document_version", "fixed_version", False),
    }
    for type_id, contract in expected.items():
        item = by_id[type_id]
        if (
            item.source_kind,
            item.target_kind,
            item.target_version_behavior,
            item.influences_retrieval,
        ) != contract or item.status != "active":
            _fail("RELATIONSHIP_TYPE_UNQUALIFIED", f"{type_id} differs from its qualified contract.")

    provisional = RelationshipRegistry(
        1,
        base_profile,
        1,
        "outgoing",
        tuple(traversable),
        tuple(definitions),
        "",
        "",
    )
    canonical = provisional.canonical()
    registry_digest = domain_digest("ishikawa.relationship-registry.v1", canonical)
    method_profile_id = domain_digest(
        "ishikawa.relationship-method-profile.v1",
        {"base_retrieval_profile_id": base_profile, "relationship_registry": canonical},
    )
    return replace(provisional, digest=registry_digest, method_profile_id=method_profile_id)


def normalize_reference(value: str) -> str:
    """Normalize identifier typography without changing identifier meaning."""

    if not isinstance(value, str):
        raise ValueError("reference must be text")
    normalized = " ".join(value.strip().upper().split())
    if _REFERENCE.fullmatch(normalized) is None:
        raise ValueError("reference has an unsupported explicit-identifier shape")
    return normalized


def extract_explicit_references(text: str) -> tuple[str, ...]:
    """Return unique identifier-shaped references physically present in text."""

    if not isinstance(text, str):
        raise ValueError("reference source must be text")
    ordered: list[str] = []
    seen: set[str] = set()
    for match in _REFERENCE.finditer(text.upper()):
        value = normalize_reference(match.group(0))
        if value not in seen:
            seen.add(value)
            ordered.append(value)
    return tuple(ordered)


def extract_declared_identifiers(texts: Iterable[str]) -> tuple[str, ...]:
    """Find conservative self-identifiers, not every reference in a document."""

    values: set[str] = set()
    for raw in texts:
        if not isinstance(raw, str):
            raise ValueError("declaration source must be text")
        for raw_line in raw.splitlines():
            text = raw_line.strip()
            for pattern in (_POLICY_DECLARATION, _FORM_DECLARATION):
                match = pattern.match(text)
                if match is not None:
                    values.add(normalize_reference(match.group(1)))
    return tuple(sorted(values))


def _is_retrieval_representative(chunk: Any) -> bool:
    """Identify derived multi-unit projections that cannot anchor an edge."""

    contextual_fields = getattr(chunk, "contextual_fields", {})
    if not isinstance(contextual_fields, Mapping):
        return False
    properties = contextual_fields.get("projection_properties", {})
    return (
        isinstance(properties, Mapping)
        and properties.get("retrieval_representative") is True
    )


@dataclass(frozen=True, slots=True)
class ReferenceOwner:
    reference_value: str
    document_key: str
    document_identity: str

    def __post_init__(self) -> None:
        object.__setattr__(self, "reference_value", normalize_reference(self.reference_value))
        if _IDENTIFIER.fullmatch(self.document_key) is None:
            raise ValueError("owner document key is invalid")
        _digest(self.document_identity, "owner document identity")


@dataclass(frozen=True, slots=True)
class ReferenceEvidence:
    source_document_key: str
    source_document_identity: str
    source_document_version_identity: str
    source_artifact_set_identity: str
    source_structural_unit_identity: str
    evidence_citation_identity: str
    reference_value: str
    page_start: int

    def __post_init__(self) -> None:
        if _IDENTIFIER.fullmatch(self.source_document_key) is None:
            raise ValueError("source document key is invalid")
        for label, value in (
            ("source document", self.source_document_identity),
            ("source document version", self.source_document_version_identity),
            ("source artifact set", self.source_artifact_set_identity),
            ("source structural unit", self.source_structural_unit_identity),
            ("evidence citation", self.evidence_citation_identity),
        ):
            _digest(value, label)
        object.__setattr__(self, "reference_value", normalize_reference(self.reference_value))
        if type(self.page_start) is not int or self.page_start < 1:
            raise ValueError("evidence page must be positive")

    @property
    def identity(self) -> str:
        return domain_digest(
            "ishikawa.reference-evidence.v1",
            {
                "source_structural_unit_identity": self.source_structural_unit_identity,
                "evidence_citation_identity": self.evidence_citation_identity,
                "reference_value": self.reference_value,
            },
        )


@dataclass(frozen=True, slots=True)
class RelationshipOverride:
    evidence_identity: str
    audit_identity: str
    reason_code: str
    target_document_key: str | None = None
    external_identity: str | None = None

    def __post_init__(self) -> None:
        _digest(self.evidence_identity, "override evidence")
        _digest(self.audit_identity, "override audit")
        if not self.reason_code or self.reason_code != self.reason_code.strip():
            raise ValueError("override reason must be a trimmed nonblank string")
        if (self.target_document_key is None) == (self.external_identity is None):
            raise ValueError("override must select exactly one document or external target")
        if self.target_document_key is not None and _IDENTIFIER.fullmatch(self.target_document_key) is None:
            raise ValueError("override document key is invalid")
        if self.external_identity is not None and (
            not self.external_identity.strip() or self.external_identity != self.external_identity.strip()
        ):
            raise ValueError("override external identity is invalid")


@dataclass(frozen=True, slots=True)
class RelationshipEdge:
    relationship_id: str
    relationship_type: str
    source_kind: str
    source_identity: str
    target_kind: str
    target_identity: str
    target_document_key: str | None
    evidence_citation_identity: str
    detection_method: str
    review_status: str
    relationship_definition_version: str
    source_artifact_set_identity: str
    override_audit_identity: str | None = None
    override_reason_code: str | None = None


@dataclass(frozen=True, slots=True)
class RelationshipObservation:
    evidence: ReferenceEvidence
    outcome: str
    reason_code: str
    edge: RelationshipEdge | None

    @property
    def requires_quarantine(self) -> bool:
        return self.outcome == "unresolved"


def _edge(
    evidence: ReferenceEvidence,
    registry: RelationshipRegistry,
    *,
    relationship_type: str,
    target_kind: str,
    target_identity: str,
    target_document_key: str | None,
    detection_method: str,
    review_status: str,
    override_audit_identity: str | None = None,
    override_reason_code: str | None = None,
) -> RelationshipEdge:
    definition = registry.by_id()[relationship_type]
    if definition.target_kind != target_kind:
        raise ValueError("relationship target kind conflicts with registry")
    relationship_id = domain_digest(
        "ishikawa.relationship.v1",
        {
            "relationship_type": relationship_type,
            "source_kind": "structural_unit",
            "source_identity": evidence.source_structural_unit_identity,
            "target_kind": target_kind,
            "target_identity": target_identity,
            "evidence_citation_identity": evidence.evidence_citation_identity,
            "relationship_definition_version": registry.digest,
        },
    )
    return RelationshipEdge(
        relationship_id,
        relationship_type,
        "structural_unit",
        evidence.source_structural_unit_identity,
        target_kind,
        target_identity,
        target_document_key,
        evidence.evidence_citation_identity,
        detection_method,
        review_status,
        registry.digest,
        evidence.source_artifact_set_identity,
        override_audit_identity,
        override_reason_code,
    )


def resolve_explicit_references(
    evidence: Sequence[ReferenceEvidence],
    owners: Sequence[ReferenceOwner],
    registry: RelationshipRegistry,
    *,
    overrides: Sequence[RelationshipOverride] = (),
) -> tuple[RelationshipObservation, ...]:
    """Resolve references exactly; ambiguity and absence remain unresolved."""

    owners_by_reference: dict[str, list[ReferenceOwner]] = {}
    owners_by_key: dict[str, ReferenceOwner] = {}
    for owner in owners:
        owners_by_reference.setdefault(owner.reference_value, []).append(owner)
        prior = owners_by_key.get(owner.document_key)
        if prior is not None and prior.document_identity != owner.document_identity:
            raise ValueError("one document key maps to conflicting identities")
        owners_by_key[owner.document_key] = owner
    overrides_by_evidence: dict[str, RelationshipOverride] = {}
    for override in overrides:
        if override.evidence_identity in overrides_by_evidence:
            raise ValueError("only one override may address an evidence observation")
        overrides_by_evidence[override.evidence_identity] = override

    observations: list[RelationshipObservation] = []
    seen_evidence: set[str] = set()
    for item in evidence:
        if item.identity in seen_evidence:
            raise ValueError("reference evidence identities must be unique")
        seen_evidence.add(item.identity)
        override = overrides_by_evidence.get(item.identity)
        if override is not None:
            if override.external_identity is not None:
                edge = _edge(
                    item,
                    registry,
                    relationship_type="explicit_reference.external",
                    target_kind="external",
                    target_identity=override.external_identity,
                    target_document_key=None,
                    detection_method="operator_override",
                    review_status="external",
                    override_audit_identity=override.audit_identity,
                    override_reason_code=override.reason_code,
                )
                observations.append(
                    RelationshipObservation(item, "external", "REFERENCE_OVERRIDE_EXTERNAL", edge)
                )
                continue
            target = owners_by_key.get(override.target_document_key or "")
            if target is None:
                observations.append(
                    RelationshipObservation(item, "unresolved", "REFERENCE_OVERRIDE_TARGET_UNKNOWN", None)
                )
                continue
            edge = _edge(
                item,
                registry,
                relationship_type="explicit_reference.document",
                target_kind="document",
                target_identity=target.document_identity,
                target_document_key=target.document_key,
                detection_method="operator_override",
                review_status="accepted",
                override_audit_identity=override.audit_identity,
                override_reason_code=override.reason_code,
            )
            observations.append(
                RelationshipObservation(item, "accepted", "REFERENCE_OVERRIDE_ACCEPTED", edge)
            )
            continue

        candidates = owners_by_reference.get(item.reference_value, [])
        if not candidates:
            observations.append(
                RelationshipObservation(item, "unresolved", "REFERENCE_TARGET_UNRESOLVED", None)
            )
        elif len(candidates) > 1:
            observations.append(
                RelationshipObservation(item, "unresolved", "REFERENCE_TARGET_AMBIGUOUS", None)
            )
        elif candidates[0].document_identity == item.source_document_identity:
            observations.append(
                RelationshipObservation(item, "ignored", "REFERENCE_SELF_DECLARATION", None)
            )
        else:
            target = candidates[0]
            edge = _edge(
                item,
                registry,
                relationship_type="explicit_reference.document",
                target_kind="document",
                target_identity=target.document_identity,
                target_document_key=target.document_key,
                detection_method="deterministic",
                review_status="accepted",
            )
            observations.append(
                RelationshipObservation(item, "accepted", "REFERENCE_RESOLVED", edge)
            )
    unused = set(overrides_by_evidence) - seen_evidence
    if unused:
        raise ValueError("an override does not match current reference evidence")
    return tuple(observations)


def build_supersedes_edge(
    *,
    document_identity: str,
    prior_document_version_identity: str,
    source_artifact_set_identity: str,
    evidence_citation_identity: str,
    registry: RelationshipRegistry,
) -> RelationshipEdge:
    """Build the fixed-version lifecycle edge for a published revision."""

    for label, value in (
        ("document", document_identity),
        ("prior document version", prior_document_version_identity),
        ("source artifact set", source_artifact_set_identity),
        ("evidence citation", evidence_citation_identity),
    ):
        _digest(value, label)
    relationship_id = domain_digest(
        "ishikawa.relationship.v1",
        {
            "relationship_type": "supersedes",
            "source_kind": "document",
            "source_identity": document_identity,
            "target_kind": "document_version",
            "target_identity": prior_document_version_identity,
            "evidence_citation_identity": evidence_citation_identity,
            "relationship_definition_version": registry.digest,
        },
    )
    return RelationshipEdge(
        relationship_id,
        "supersedes",
        "document",
        document_identity,
        "document_version",
        prior_document_version_identity,
        None,
        evidence_citation_identity,
        "deterministic",
        "accepted",
        registry.digest,
        source_artifact_set_identity,
    )


def discover_prepared_relationships(
    documents: Sequence[Any],
    *,
    method_profile_id: str,
    registry: RelationshipRegistry,
    additional_owners: Sequence[ReferenceOwner] = (),
    overrides: Sequence[RelationshipOverride] = (),
) -> tuple[RelationshipObservation, ...]:
    """Resolve explicit document references from writer-ready chunk evidence.

    Only identifiers declared by another candidate-corpus document enter the
    relationship workflow. Other identifier-shaped values remain available to
    exact retrieval but do not become graph edges.
    """

    _digest(method_profile_id, "chunk method profile")
    if not documents:
        return ()

    if any(not isinstance(item, ReferenceOwner) for item in additional_owners):
        raise ValueError("additional relationship owners are invalid")
    owners: list[ReferenceOwner] = list(additional_owners)
    identities: dict[str, tuple[str, str, str]] = {}
    for document in documents:
        document_id = domain_digest(
            "ishikawa.document.v1", {"document_key": document.document_key}
        )
        version_id = domain_digest(
            "ishikawa.document-version.v1",
            {"document_id": document_id, "source_digest": document.source_digest},
        )
        artifact_id = domain_digest(
            "ishikawa.document-artifact-set.v1",
            {
                "document_version_id": version_id,
                "method_profile_id": method_profile_id,
                "class_id": document.class_id,
            },
        )
        identities[document.document_key] = (document_id, version_id, artifact_id)
        for declaration in extract_declared_identifiers(
            chunk.relevant_excerpt
            for chunk in document.chunks
            if not chunk.authoritative_component_ordinals
        ):
            owners.append(ReferenceOwner(declaration, document.document_key, document_id))

    declared = {item.reference_value for item in owners}
    evidence: list[ReferenceEvidence] = []
    for document in documents:
        document_id, version_id, artifact_id = identities[document.document_key]
        units = {item.ordinal: item for item in document.structural_units}
        for chunk in document.chunks:
            if chunk.authoritative_component_ordinals or _is_retrieval_representative(chunk):
                continue
            references = tuple(
                item for item in extract_explicit_references(chunk.relevant_excerpt)
                if item in declared
            )
            if not references:
                continue
            if len(chunk.structural_unit_ordinals) != 1:
                raise ValueError(
                    "relationship evidence must map to exactly one structural unit"
                )
            unit = units[chunk.structural_unit_ordinals[0]]
            normalized_digest = domain_digest(
                "ishikawa.normalized-text.v1", unit.normalized_text
            )
            unit_id = domain_digest(
                "ishikawa.structural-unit.v1",
                {
                    "artifact_set_id": artifact_id,
                    "ordinal": unit.ordinal,
                    "digest": normalized_digest,
                },
            )
            retrieval_digest = domain_digest(
                "ishikawa.retrieval-text.v1", chunk.retrieval_text
            )
            chunk_id = domain_digest(
                "ishikawa.chunk.v1",
                {
                    "artifact_set_id": artifact_id,
                    "ordinal": chunk.ordinal,
                    "digest": retrieval_digest,
                },
            )
            citation_id = domain_digest(
                "ishikawa.citation.v1",
                {
                    "chunk_id": chunk_id,
                    "page_start": chunk.page_start,
                    "page_end": chunk.page_end,
                },
            )
            for reference in references:
                evidence.append(
                    ReferenceEvidence(
                        document.document_key,
                        document_id,
                        version_id,
                        artifact_id,
                        unit_id,
                        citation_id,
                        reference,
                        chunk.page_start,
                    )
                )
    return resolve_explicit_references(
        tuple(evidence), tuple(owners), registry, overrides=overrides
    )


@dataclass(frozen=True, slots=True)
class TraversalEdge:
    relationship_id: str
    relationship_type: str
    source_document_identity: str
    target_document_identity: str
    resolved_target_version_identity: str
    evidence_citation_identity: str

    def __post_init__(self) -> None:
        for label, value in (
            ("relationship", self.relationship_id),
            ("source document", self.source_document_identity),
            ("target document", self.target_document_identity),
            ("resolved target version", self.resolved_target_version_identity),
            ("evidence citation", self.evidence_citation_identity),
        ):
            _digest(value, label)


@dataclass(frozen=True, slots=True)
class RelationshipExpansion:
    seed_document_identity: str
    relationship_id: str
    relationship_type: str
    direction: str
    target_document_identity: str
    resolved_target_version_identity: str
    evidence_citation_identity: str
    inclusion_reason: str


def expand_one_hop(
    seed_document_identities: Sequence[str],
    edges: Sequence[TraversalEdge],
    *,
    allowed_document_identities: set[str],
    registry: RelationshipRegistry,
    maximum_results: int = 20,
    relationship_priorities: Mapping[str, int] | None = None,
) -> tuple[RelationshipExpansion, ...]:
    """Expand authorized direct seeds once, with cycle and target deduplication."""

    if type(maximum_results) is not int or not 1 <= maximum_results <= 100:
        raise ValueError("relationship expansion depth must be between 1 and 100")
    seeds: list[str] = []
    seen_seeds: set[str] = set()
    for seed in seed_document_identities:
        _digest(seed, "seed document")
        if seed in allowed_document_identities and seed not in seen_seeds:
            seen_seeds.add(seed)
            seeds.append(seed)
    allowed_types = set(registry.traversable_types)
    priorities = {} if relationship_priorities is None else dict(relationship_priorities)
    edge_ids = {edge.relationship_id for edge in edges}
    if (
        not set(priorities) <= edge_ids
        or any(type(value) is not int or value < 1 for value in priorities.values())
    ):
        raise ValueError("relationship expansion priorities are invalid")
    fallback_priority = maximum_results + len(edges) + 1
    ordered_edges = sorted(
        edges,
        key=lambda item: (
            priorities.get(item.relationship_id, fallback_priority),
            item.relationship_id,
            item.target_document_identity,
        ),
    )
    expansions: list[RelationshipExpansion] = []
    seen_targets: set[str] = set()
    seen_document_pairs: set[frozenset[str]] = set()
    seen_edges: set[str] = set()
    for seed in seeds:
        for edge in ordered_edges:
            document_pair = frozenset((seed, edge.target_document_identity))
            if (
                edge.relationship_id in seen_edges
                or edge.source_document_identity != seed
                or edge.relationship_type not in allowed_types
                or edge.target_document_identity not in allowed_document_identities
                or edge.target_document_identity == seed
                or edge.target_document_identity in seen_targets
                or document_pair in seen_document_pairs
            ):
                continue
            seen_edges.add(edge.relationship_id)
            seen_targets.add(edge.target_document_identity)
            seen_document_pairs.add(document_pair)
            expansions.append(
                RelationshipExpansion(
                    seed,
                    edge.relationship_id,
                    edge.relationship_type,
                    "outgoing",
                    edge.target_document_identity,
                    edge.resolved_target_version_identity,
                    edge.evidence_citation_identity,
                    "explicit_reference_one_hop",
                )
            )
            if len(expansions) == maximum_results:
                return tuple(expansions)
    return tuple(expansions)
