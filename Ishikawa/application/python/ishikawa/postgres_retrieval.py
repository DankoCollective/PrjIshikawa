"""Native read-only PostgreSQL retrieval port for Ishikawa.

The port embeds only the resolved standalone query.  The original request is
accepted separately so the generation-context budget can count conversation
state without ever sending that state to the embedding endpoint.
"""

from __future__ import annotations

import re
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass, replace
from time import monotonic_ns
from typing import Any

from .api_contract import ApiChatRequest, ApiExcerpt, ApiSourceGroup
from .canonical import canonical_json_bytes, domain_digest
from .generation import (
    ConversationTurn,
    GroundedEvidence,
    build_grounded_generation_request,
    trusted_instruction_text,
)
from .method_profile import RetrievalProfile
from .native_adapters import ValidatedQueryEmbedding
from .query_resolution import ResolvedRetrievalQuery
from .reconstruction import (
    CompleteProcedureTarget,
    EvidenceCandidate,
    EvidenceCitation,
    EvidencePackage,
    ReconstructionAction,
    ReconstructionContractError,
    ReconstructionPolicy,
    assemble_evidence,
    reconstruct_complete_procedure,
    retain_evidence_selection_groups,
)
from .relationships import (
    RelationshipRegistry,
    TraversalEdge,
    expand_one_hop,
    extract_declared_identifiers,
)
from .relevance import (
    RelevanceContractError,
    RelevancePolicy,
    measure_citable_evidence_relevance,
    plan_citable_response_envelopes,
)
from .retrieval import (
    CandidateFilters,
    FusedCandidate,
    LaneCandidate,
    RetrievalContractError,
    balanced_document_shortlist,
    decomposed_candidate_pool,
    decompose_retrieval_query,
    exact_document_page_lookup,
    exact_lookup,
    exact_term_lookup,
    expand_authoritative_candidates,
    extract_explicit_page,
    extract_structured_terms,
    lexical_search,
    collapse_retrieval_groups,
    reciprocal_rank_fusion,
    score_calibrated_global_rerank,
    select_ranked_relevance_candidates,
    vector_search,
    uses_calibrated_body_route,
)
from .retrieval_service import (
    RetrievedEvidence,
    RetrievalDependencyUnavailable,
    RetrievalOperationalTelemetry,
    RetrievalServiceContractError,
)
from .sufficiency import (
    SufficiencyContractError,
    SufficiencyPolicy,
    SufficiencySignals,
    evaluate_evidence_sufficiency,
)


EXPECTED_RETRIEVAL_ROLE = "rag_retrieval"
_COMPLETE_PROCEDURE = re.compile(
    r"(?:\b(?:complete|entire|full|whole)\s+(?:the\s+)?procedure\b|"
    r"\bprocedure\s+(?:in\s+its\s+entirety|from\s+start\s+to\s+finish)\b)",
    re.IGNORECASE,
)
_COMPLETE_SECTION = re.compile(
    r"\b(?:complete|entire|full|whole)\s+(?:the\s+)?section\s+"
    r"(?P<section>[0-9]{1,3}|[IVXLCDM]{1,12})\b",
    re.IGNORECASE,
)
_STRUCTURAL_SECTION = re.compile(
    r"^(?:section\s+)?(?P<section>[0-9]{1,3}|[IVXLCDM]{1,12})(?:[.\s:—-]|$)",
    re.IGNORECASE,
)
_RELATIONSHIP_SECTION_LOCATOR = re.compile(
    r"\bsection\s+(?P<section>[0-9]{1,3}|[IVXLCDM]{1,12})\b",
    re.IGNORECASE,
)
_RELATIONSHIP_PAGE_LOCATOR = re.compile(
    r"\bpage\s+(?P<page>[1-9][0-9]{0,5})\b",
    re.IGNORECASE,
)
_RELATIONSHIP_NAVIGATION = re.compile(
    r"(?:\b(?:cross[- ]?references?|relationships?)\b|"
    r"\b(?:related|referenced|linked)\s+"
    r"(?:documents?|policies?|procedures?|forms?|records?|sources?)\b|"
    r"\b(?:documents?|policies?|procedures?|forms?|records?|sources?)\s+"
    r"(?:does|do|is|are|were|was)?\s*(?:this|it|the\s+\w+)?\s*"
    r"(?:references?|links?|relates?)\b)",
    re.IGNORECASE,
)


GenerationPromptTokenCounter = Callable[
    [Sequence[Mapping[str, str]], Mapping[str, Any]], int
]

_RETRIEVAL_TIMING_STAGES = (
    "nomic",
    "lexical_sql",
    "vector_sql",
    "fusion",
    "reconstruction",
    "tokenization",
)


class _RetrievalStageTimer:
    """Accumulate bounded, content-free timings inside the retrieval port."""

    def __init__(self, clock_ns: Callable[[], int]):
        if not callable(clock_ns):
            raise RetrievalServiceContractError("retrieval stage clock is invalid")
        self.clock_ns = clock_ns
        self.started_ns = clock_ns()
        if type(self.started_ns) is not int or self.started_ns < 0:
            raise RetrievalServiceContractError("retrieval stage clock is invalid")
        self.values_ns = {stage: 0 for stage in _RETRIEVAL_TIMING_STAGES}

    def measure(self, stage: str, operation: Callable[[], Any]) -> Any:
        if stage not in self.values_ns or not callable(operation):
            raise RetrievalServiceContractError("retrieval stage measurement is invalid")
        started = self.clock_ns()
        if type(started) is not int or started < self.started_ns:
            raise RetrievalServiceContractError("retrieval stage clock is invalid")
        try:
            return operation()
        finally:
            finished = self.clock_ns()
            if type(finished) is not int or finished < started:
                raise RetrievalServiceContractError("retrieval stage clock is invalid")
            self.values_ns[stage] += finished - started

    def finish(self) -> tuple[tuple[str, int], ...]:
        finished = self.clock_ns()
        if type(finished) is not int or finished < self.started_ns:
            raise RetrievalServiceContractError("retrieval stage clock is invalid")
        accounted = sum(
            duration
            for stage, duration in self.values_ns.items()
            if stage != "reconstruction"
        )
        self.values_ns["reconstruction"] = max(
            self.values_ns["reconstruction"],
            finished - self.started_ns - accounted,
        )
        return tuple(
            (stage, min(86400000, self.values_ns[stage] // 1000000))
            for stage in _RETRIEVAL_TIMING_STAGES
        )


@dataclass(frozen=True, slots=True)
class _DocumentMetadata:
    display_name: str
    document_class: str


@dataclass(frozen=True, slots=True)
class _StructuralDisplayUnit:
    """Keep operator-facing source text separate from retrieval-enriched text."""

    projection_kind: str
    excerpt: ApiExcerpt


def requests_complete_procedure(query: str) -> bool:
    """Recognize only explicit whole-procedure wording in a resolved query."""

    if not isinstance(query, str) or not query.strip() or query != query.strip():
        raise RetrievalServiceContractError("resolved query is invalid")
    return _COMPLETE_PROCEDURE.search(query) is not None


def requests_relationship_navigation(query: str) -> bool:
    """Recognize only an explicit request to navigate document relationships."""

    if not isinstance(query, str) or not query.strip() or query != query.strip():
        raise RetrievalServiceContractError("resolved query is invalid")
    return _RELATIONSHIP_NAVIGATION.search(query) is not None


def _roman_value(value: str) -> int | None:
    if value.isdigit():
        number = int(value)
        return number if 1 <= number <= 3999 else None
    values = {"I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1000}
    total = 0
    previous = 0
    for character in reversed(value.upper()):
        current = values.get(character)
        if current is None:
            return None
        total += -current if current < previous else current
        previous = max(previous, current)
    return total if 1 <= total <= 3999 else None


def requested_complete_section(query: str) -> int | None:
    """Return one explicit section ordinal without inferring vague intent."""

    if not isinstance(query, str) or not query.strip() or query != query.strip():
        raise RetrievalServiceContractError("resolved query is invalid")
    match = _COMPLETE_SECTION.search(query)
    return None if match is None else _roman_value(match.group("section"))


def _section_path(
    inventory: Sequence[EvidenceCandidate], section_ordinal: int
) -> tuple[str, ...] | None:
    roots: set[str] = set()
    for item in inventory:
        for citation in item.citations:
            if not citation.structural_path:
                continue
            root = citation.structural_path[0]
            match = _STRUCTURAL_SECTION.match(root)
            if match is not None and _roman_value(match.group("section")) == section_ordinal:
                roots.add(root)
    return (next(iter(roots)),) if len(roots) == 1 else None


def _token_count(counter: Callable[[str], int], text: str, label: str) -> int:
    try:
        value = counter(text)
    except Exception as error:
        raise RetrievalDependencyUnavailable(f"{label}_token_counter_failed") from error
    if type(value) is not int or value < 1:
        raise RetrievalServiceContractError(f"{label} token count is invalid")
    return value


def _conversation_payload(request: ApiChatRequest) -> str:
    return canonical_json_bytes(
        {
            "conversation": [turn.canonical() for turn in request.history],
            "conversation_id": request.conversation_id,
            "question": request.message,
            "schema": "ishikawa.reconstruction-conversation.v1",
            "turn_id": request.turn_id,
        }
    ).decode("utf-8")


def _merge_exact_candidates(candidates: Sequence[LaneCandidate]) -> tuple[LaneCandidate, ...]:
    by_chunk: dict[str, LaneCandidate] = {}
    for item in candidates:
        if item.lane != "exact":
            raise RetrievalContractError("exact candidate collection contains another lane")
        by_chunk.setdefault(item.chunk_id, item)
    return tuple(
        replace(item, rank=rank)
        for rank, item in enumerate(by_chunk.values(), start=1)
    )


def _hydrate_candidates(
    connection: Any,
    fused: Sequence[FusedCandidate],
    filters: CandidateFilters,
    *,
    origin: str = "direct",
    inclusion_reason: str = "direct_retrieval",
    relationship_provenance: dict[str, tuple[str, ...]] | None = None,
) -> tuple[tuple[EvidenceCandidate, ...], dict[str, _DocumentMetadata]]:
    """Read citable text for authorized fused candidates and recheck filters."""

    if not fused:
        return (), {}
    chunk_ids = [item.chunk_id for item in fused]
    rows = connection.execute(
        """/* ishikawa.postgres-retrieval.hydrate */
        SELECT
          ac.chunk_id, ac.document_id, ac.document_version_id, ac.document_key,
          ac.display_name, ac.class_id, ac.retrieval_text_digest,
          ac.retrieval_text, ac.projection_kind, ac.ordinal,
          ci.citation_id, ci.page_start, ci.page_end, ci.structural_path
        FROM rag_search.active_chunks ac
        JOIN rag_search.active_citations ci ON ci.chunk_id = ac.chunk_id
        WHERE ac.chunk_id = ANY(%s::text[])
        ORDER BY ac.chunk_id, ci.page_start, ci.page_end, ci.citation_id
        """,
        (chunk_ids,),
    ).fetchall()
    grouped: dict[str, list[Sequence[Any]]] = {}
    for row in rows:
        if not isinstance(row, Sequence) or len(row) != 14:
            raise RetrievalServiceContractError("retrieval hydration row is invalid")
        grouped.setdefault(row[0], []).append(row)
    if set(grouped) != set(chunk_ids):
        raise RetrievalServiceContractError("retrieval hydration identity mismatch")

    allowed_classes = set(filters.document_classes)
    allowed_keys = set(filters.document_keys)
    allowed_versions = set(filters.document_version_ids)
    candidates: list[EvidenceCandidate] = []
    metadata: dict[str, _DocumentMetadata] = {}
    for rank, fused_item in enumerate(fused, start=1):
        records = grouped[fused_item.chunk_id]
        first = records[0]
        identity = (first[1], first[2], first[3])
        if identity != (
            fused_item.document_id,
            fused_item.document_version_id,
            fused_item.document_key,
        ):
            raise RetrievalServiceContractError("retrieval hydration document mismatch")
        if allowed_classes and first[5] not in allowed_classes:
            raise RetrievalServiceContractError("retrieval class filter was not preserved")
        if allowed_keys and first[3] not in allowed_keys:
            raise RetrievalServiceContractError("retrieval document filter was not preserved")
        if allowed_versions and first[2] not in allowed_versions:
            raise RetrievalServiceContractError("retrieval source constraint was not preserved")
        if any(tuple(record[:10]) != tuple(first[:10]) for record in records):
            raise RetrievalServiceContractError("retrieval hydration metadata conflicts")
        if not isinstance(first[4], str) or not first[4].strip() or first[4] != first[4].strip():
            raise RetrievalServiceContractError("retrieval display name is invalid")
        current_metadata = _DocumentMetadata(first[4], first[5])
        existing_metadata = metadata.setdefault(first[2], current_metadata)
        if existing_metadata != current_metadata:
            raise RetrievalServiceContractError("document-version metadata conflicts")
        citations = tuple(
            EvidenceCitation(
                citation_id=record[10],
                document_id=record[1],
                document_version_id=record[2],
                document_key=record[3],
                page_start=record[11],
                page_end=record[12],
                structural_path=tuple(record[13]),
            )
            for record in records
        )
        candidates.append(
            EvidenceCandidate(
                chunk_id=first[0],
                retrieval_text_digest=first[6],
                retrieval_text=first[7],
                projection_kind=first[8],
                ordinal=first[9],
                retrieval_rank=rank,
                origin=origin,
                inclusion_reason=inclusion_reason,
                citations=citations,
                retrieval_group_id=fused_item.retrieval_group_id,
                relationship_provenance=(
                    ()
                    if relationship_provenance is None
                    else relationship_provenance.get(first[0], ())
                ),
            )
        )
    return tuple(candidates), metadata


def _merge_metadata(
    destination: dict[str, _DocumentMetadata],
    additions: dict[str, _DocumentMetadata],
) -> None:
    for version_id, value in additions.items():
        current = destination.setdefault(version_id, value)
        if current != value:
            raise RetrievalServiceContractError("document-version metadata conflicts")


def _load_complete_document_inventory(
    connection: Any,
    document_version_id: str,
    filters: CandidateFilters,
) -> tuple[tuple[EvidenceCandidate, ...], dict[str, _DocumentMetadata]]:
    """Load every active citable chunk for one exact document version."""

    scoped = CandidateFilters(
        document_classes=filters.document_classes,
        document_keys=filters.document_keys,
        document_version_ids=(document_version_id,),
    )
    rows = connection.execute(
        """/* ishikawa.postgres-retrieval.complete-procedure-inventory */
        SELECT ac.chunk_id, ac.document_id, ac.document_version_id,
               ac.document_key, 1.0::float8
        FROM rag_search.active_chunks ac
        WHERE ac.document_version_id = %s
          AND (cardinality(%s::text[]) = 0 OR ac.class_id = ANY(%s::text[]))
          AND (cardinality(%s::text[]) = 0 OR ac.document_key = ANY(%s::text[]))
        ORDER BY ac.ordinal, ac.chunk_id
        """,
        (
            document_version_id,
            list(scoped.document_classes),
            list(scoped.document_classes),
            list(scoped.document_keys),
            list(scoped.document_keys),
        ),
    ).fetchall()
    candidates = tuple(
        FusedCandidate(row[0], row[1], row[2], row[3], 1.0, True, ())
        for row in rows
    )
    return _hydrate_candidates(connection, candidates, scoped)


def _load_document_identifiers(
    connection: Any,
    document_version_ids: Sequence[str],
) -> dict[str, str | None]:
    """Resolve conservative self-declared identifiers for response display."""

    if not document_version_ids:
        return {}
    rows = connection.execute(
        """/* ishikawa.postgres-retrieval.document-identifiers */
        SELECT citation.document_version_id, citation.relevant_excerpt
        FROM rag_search.active_citations citation
        WHERE citation.document_version_id = ANY(%s::text[])
        ORDER BY citation.document_version_id, citation.page_start, citation.citation_id
        """,
        (list(document_version_ids),),
    ).fetchall()
    excerpts: dict[str, list[str]] = {version_id: [] for version_id in document_version_ids}
    for row in rows:
        if (
            not isinstance(row, Sequence)
            or isinstance(row, (str, bytes))
            or len(row) != 2
            or row[0] not in excerpts
            or not isinstance(row[1], str)
        ):
            raise RetrievalServiceContractError("document identifier row is invalid")
        excerpts[row[0]].append(row[1])
    result: dict[str, str | None] = {}
    for version_id, values in excerpts.items():
        declared = extract_declared_identifiers(values)
        result[version_id] = declared[0] if len(declared) == 1 else None
    return result


def _load_citation_excerpts(
    connection: Any,
    citation_ids: Sequence[str],
) -> dict[str, str]:
    """Load authoritative source prose for model evidence, never retrieval text."""

    if not citation_ids:
        return {}
    rows = connection.execute(
        """/* ishikawa.postgres-retrieval.generation-citation-excerpts */
        SELECT citation_id, relevant_excerpt
        FROM rag_search.active_citations
        WHERE citation_id = ANY(%s::text[])
        ORDER BY citation_id
        """,
        (list(citation_ids),),
    ).fetchall()
    excerpts: dict[str, str] = {}
    for row in rows:
        if (
            not isinstance(row, Sequence)
            or isinstance(row, (str, bytes))
            or len(row) != 2
            or row[0] not in citation_ids
            or not isinstance(row[1], str)
            or not row[1].strip()
            or row[1] != row[1].strip()
            or row[0] in excerpts
        ):
            raise RetrievalServiceContractError("generation citation excerpt row is invalid")
        excerpts[row[0]] = row[1]
    if set(excerpts) != set(citation_ids):
        raise RetrievalServiceContractError("generation citation excerpts are incomplete")
    return excerpts


def _load_document_page_counts(
    connection: Any,
    document_version_ids: Sequence[str],
) -> dict[str, int]:
    """Load authoritative total pages for every response document version."""

    if not document_version_ids:
        return {}
    rows = connection.execute(
        """/* ishikawa.postgres-retrieval.document-page-counts */
        SELECT document_version_id, page_count
        FROM rag_search.active_documents
        WHERE document_version_id = ANY(%s::text[])
        ORDER BY document_version_id
        """,
        (list(document_version_ids),),
    ).fetchall()
    result: dict[str, int] = {}
    for row in rows:
        if (
            not isinstance(row, Sequence)
            or isinstance(row, (str, bytes))
            or len(row) != 2
            or row[0] not in document_version_ids
            or type(row[1]) is not int
            or row[1] < 1
            or row[0] in result
        ):
            raise RetrievalServiceContractError("document page-count row is invalid")
        result[row[0]] = row[1]
    if set(result) != set(document_version_ids):
        raise RetrievalServiceContractError("document page-count set is incomplete")
    return result


def _relationship_locator_candidates(
    connection: Any,
    evidence_excerpt: str,
    target_document_version_id: str,
    filters: CandidateFilters,
    *,
    depth: int,
) -> tuple[LaneCandidate, ...]:
    """Route an explicit relationship section/page locator before semantics."""

    if not isinstance(evidence_excerpt, str) or not evidence_excerpt.strip():
        raise RetrievalServiceContractError("relationship evidence excerpt is invalid")
    if type(depth) is not int or not 1 <= depth <= 100:
        raise RetrievalServiceContractError("relationship locator depth is invalid")
    section_match = _RELATIONSHIP_SECTION_LOCATOR.search(evidence_excerpt)
    page_match = _RELATIONSHIP_PAGE_LOCATOR.search(evidence_excerpt)
    if section_match is not None:
        section = section_match.group("section").upper()
        locator_predicate = """
          AND EXISTS (
            SELECT 1
            FROM rag_search.active_citations locator_citation
            WHERE locator_citation.chunk_id = ac.chunk_id
              AND locator_citation.structural_path <> '[]'::jsonb
              AND (locator_citation.structural_path ->> 0) ~* %s
          )"""
        locator_parameters: tuple[Any, ...] = (
            rf"^(?:section[[:space:]]+)?{re.escape(section)}(?:[.[:space:]:—-]|$)",
        )
        reason = "relationship_section_locator"
    elif page_match is not None:
        page = int(page_match.group("page"))
        locator_predicate = """
          AND EXISTS (
            SELECT 1
            FROM rag_search.active_citations locator_citation
            WHERE locator_citation.chunk_id = ac.chunk_id
              AND %s BETWEEN locator_citation.page_start AND locator_citation.page_end
          )"""
        locator_parameters = (page,)
        reason = "relationship_page_locator"
    else:
        return ()
    rows = connection.execute(
        f"""/* ishikawa.postgres-retrieval.relationship-locator */
        SELECT ac.chunk_id, ac.document_id, ac.document_version_id,
               ac.document_key, 1.0::float8
        FROM rag_search.active_chunks ac
        WHERE ac.document_version_id = %s
          AND (cardinality(%s::text[]) = 0 OR ac.class_id = ANY(%s::text[]))
          AND (cardinality(%s::text[]) = 0 OR ac.document_key = ANY(%s::text[]))
          {locator_predicate}
        ORDER BY ac.ordinal, ac.chunk_id
        LIMIT %s
        """,
        (
            target_document_version_id,
            list(filters.document_classes),
            list(filters.document_classes),
            list(filters.document_keys),
            list(filters.document_keys),
            *locator_parameters,
            depth,
        ),
    ).fetchall()
    retrieval_group_id = domain_digest(
        "ishikawa.relationship-locator-group.v1",
        {
            "document_version_id": target_document_version_id,
            "locator_parameters": list(locator_parameters),
            "reason": reason,
        },
    )
    candidates: list[LaneCandidate] = []
    for rank, row in enumerate(rows, start=1):
        if (
            not isinstance(row, Sequence)
            or isinstance(row, (str, bytes))
            or len(row) != 5
        ):
            raise RetrievalServiceContractError("relationship locator row is invalid")
        candidates.append(
            LaneCandidate(
                chunk_id=row[0],
                document_id=row[1],
                document_version_id=row[2],
                document_key=row[3],
                lane="exact",
                rank=rank,
                raw_score=float(row[4]),
                exact_reason=reason,
                retrieval_group_id=retrieval_group_id,
            )
        )
    return tuple(candidates)


def _load_relationship_candidates(
    connection: Any,
    *,
    direct_fused: Sequence[FusedCandidate],
    query: str,
    query_embedding: ValidatedQueryEmbedding,
    filters: CandidateFilters,
    retrieval_policy: RetrievalProfile,
    relationship_registry: RelationshipRegistry,
    stage_timer: _RetrievalStageTimer,
) -> tuple[
    tuple[EvidenceCandidate, ...],
    dict[str, _DocumentMetadata],
    int,
    int,
]:
    """Expand reference edges anchored by direct chunks, then search each target."""

    if not direct_fused:
        return (), {}, 0, 0
    seed_chunk_ids = [item.chunk_id for item in direct_fused]
    seed_document_ids = tuple(dict.fromkeys(item.document_id for item in direct_fused))
    rows = connection.execute(
        """/* ishikawa.postgres-retrieval.relationship-one-hop */
        SELECT relationship.relationship_id, relationship.relationship_type,
               relationship.source_document_id, relationship.target_identity,
               target.document_version_id, relationship.evidence_citation_id,
               citation.chunk_id, citation.relevant_excerpt
        FROM rag_search.active_relationships relationship
        JOIN rag_search.active_citations citation
          ON citation.citation_id = relationship.evidence_citation_id
        JOIN rag_search.active_documents target
          ON target.document_id = relationship.target_identity
        WHERE citation.chunk_id = ANY(%s::text[])
          AND relationship.source_document_id = ANY(%s::text[])
          AND relationship.relationship_type = 'explicit_reference.document'
          AND relationship.influences_retrieval = true
          AND (cardinality(%s::text[]) = 0 OR target.class_id = ANY(%s::text[]))
          AND (cardinality(%s::text[]) = 0 OR target.document_key = ANY(%s::text[]))
        ORDER BY relationship.relationship_id, relationship.target_identity
        """,
        (
            seed_chunk_ids,
            list(seed_document_ids),
            list(filters.document_classes),
            list(filters.document_classes),
            list(filters.document_keys),
            list(filters.document_keys),
        ),
    ).fetchall()
    if any(
        not isinstance(row, Sequence)
        or isinstance(row, (str, bytes))
        or len(row) != 8
        for row in rows
    ):
        raise RetrievalServiceContractError("relationship traversal row is invalid")
    edges = tuple(TraversalEdge(*row[:6]) for row in rows)
    direct_rank_by_chunk = {
        item.chunk_id: rank for rank, item in enumerate(direct_fused, start=1)
    }
    evidence_rank_by_citation = {
        row[5]: direct_rank_by_chunk[row[6]]
        for row in rows
        if row[6] in direct_rank_by_chunk
    }
    evidence_excerpt_by_relationship = {row[0]: row[7] for row in rows}
    allowed = set(seed_document_ids) | {edge.target_document_identity for edge in edges}
    expansions = expand_one_hop(
        seed_document_ids,
        edges,
        allowed_document_identities=allowed,
        registry=relationship_registry,
        maximum_results=retrieval_policy.fused_candidate_depth,
        relationship_priorities={
            row[0]: direct_rank_by_chunk[row[6]]
            for row in rows
            if row[6] in direct_rank_by_chunk
        },
    )
    candidates: list[EvidenceCandidate] = []
    metadata: dict[str, _DocumentMetadata] = {}
    covered = 0
    for expansion in expansions:
        target_filters = CandidateFilters(
            document_classes=filters.document_classes,
            document_keys=filters.document_keys,
            document_version_ids=(expansion.resolved_target_version_identity,),
        )
        locator_candidates = _relationship_locator_candidates(
            connection,
            evidence_excerpt_by_relationship[expansion.relationship_id],
            expansion.resolved_target_version_identity,
            target_filters,
            depth=retrieval_policy.fused_candidate_depth,
        )
        if locator_candidates:
            related_fused = stage_timer.measure(
                "fusion",
                lambda: reciprocal_rank_fusion(
                    {"exact": locator_candidates},
                    rrf_constant=retrieval_policy.rrf_constant,
                    lane_weights={
                        "exact": retrieval_policy.exact_weight,
                        "lexical": retrieval_policy.lexical_weight,
                        "vector": retrieval_policy.vector_weight,
                    },
                ),
            )
            related_fused = collapse_retrieval_groups(related_fused)
        else:
            lexical = stage_timer.measure(
                "lexical_sql",
                lambda: lexical_search(
                    connection,
                    query,
                    depth=retrieval_policy.lexical_candidate_depth,
                    text_search_config=retrieval_policy.lexical_search_config,
                    filters=target_filters,
                    use_candidate_representation=(
                        retrieval_policy.section_page_representatives
                        and retrieval_policy.document_local_duplicate_canonicalization
                    ),
                ),
            )
            vector = stage_timer.measure(
                "vector_sql",
                lambda: vector_search(
                    connection,
                    query_embedding.vector,
                    query_embedding.embedding_space_id,
                    depth=retrieval_policy.vector_candidate_depth,
                    filters=target_filters,
                    use_candidate_representation=(
                        retrieval_policy.section_page_representatives
                        and retrieval_policy.document_local_duplicate_canonicalization
                    ),
                ),
            )
            related_fused = stage_timer.measure(
                "fusion",
                lambda: reciprocal_rank_fusion(
                    {"lexical": lexical, "vector": vector},
                    rrf_constant=retrieval_policy.rrf_constant,
                    lane_weights={
                        "exact": retrieval_policy.exact_weight,
                        "lexical": retrieval_policy.lexical_weight,
                        "vector": retrieval_policy.vector_weight,
                    },
                ),
            )
            if (
                retrieval_policy.section_page_representatives
                and retrieval_policy.document_local_duplicate_canonicalization
            ):
                related_fused = collapse_retrieval_groups(related_fused)
        related_fused = expand_authoritative_candidates(related_fused[:3])
        if not related_fused:
            continue
        provenance = (
            expansion.relationship_id,
            expansion.seed_document_identity,
            expansion.target_document_identity,
            expansion.resolved_target_version_identity,
            expansion.evidence_citation_identity,
        )
        hydrated, related_metadata = _hydrate_candidates(
            connection,
            related_fused,
            target_filters,
            origin="relationship",
            inclusion_reason=expansion.inclusion_reason,
            relationship_provenance={item.chunk_id: provenance for item in related_fused},
        )
        evidence_rank = evidence_rank_by_citation.get(
            expansion.evidence_citation_identity,
            len(direct_fused) + len(candidates) + 1,
        )
        candidates.extend(
            replace(item, retrieval_rank=evidence_rank + rank - 1)
            for rank, item in enumerate(hydrated, start=1)
        )
        _merge_metadata(metadata, related_metadata)
        covered += 1
    return tuple(candidates), metadata, len(expansions), covered


def _source_groups(
    package: EvidencePackage,
    metadata: dict[str, _DocumentMetadata],
    document_identifiers: dict[str, str | None],
    document_page_counts: dict[str, int],
    citation_excerpts: dict[str, str],
) -> tuple[ApiSourceGroup, ...]:
    passages = {item.passage_id: item for item in package.selected}
    sources: list[ApiSourceGroup] = []
    for group in package.source_groups:
        document_metadata = metadata.get(group.document_version_id)
        if document_metadata is None:
            raise RetrievalServiceContractError("source metadata is absent")
        allowed_citations = set(group.citation_ids)
        excerpts: list[ApiExcerpt] = []
        for passage_id in group.passage_ids:
            passage = passages.get(passage_id)
            if passage is None:
                raise RetrievalServiceContractError("source passage is absent")
            for citation in passage.citations:
                if citation.citation_id not in allowed_citations:
                    continue
                excerpts.append(
                    ApiExcerpt(
                        citation_id=citation.citation_id,
                        excerpt=citation_excerpts[citation.citation_id],
                        page_start=citation.page_start,
                        page_end=citation.page_end,
                        structural_path=citation.structural_path,
                    )
                )
        if {item.citation_id for item in excerpts} != allowed_citations:
            raise RetrievalServiceContractError("source citation set is incomplete")
        sources.append(
            ApiSourceGroup(
                source_id=group.document_version_id,
                source_label=group.source_label,
                document_key=group.document_key,
                document_identifier=document_identifiers.get(group.document_version_id),
                display_name=document_metadata.display_name,
                document_class=document_metadata.document_class,
                excerpts=tuple(excerpts),
                page_count=document_page_counts[group.document_version_id],
            )
        )
    return tuple(sources)


def _generation_evidence(
    package: EvidencePackage,
    *,
    exact_required_chunk_ids: frozenset[str] = frozenset(),
    exact_required_document_version_id: str | None = None,
    relationship_coverage_required: bool = False,
    citation_excerpts: dict[str, str] | None = None,
    metadata: dict[str, _DocumentMetadata] | None = None,
    document_identifiers: dict[str, str | None] | None = None,
) -> tuple[GroundedEvidence, ...]:
    """Project selected evidence and only mandate explicit user obligations."""

    if type(relationship_coverage_required) is not bool:
        raise RetrievalServiceContractError(
            "relationship coverage requirement is invalid"
        )

    citation_excerpts = citation_excerpts or {}
    metadata = metadata or {}
    document_identifiers = document_identifiers or {}
    labels_by_version = {
        group.document_version_id: group.source_label
        for group in package.source_groups
    }
    seed_group_by_citation = {
        passage.relationship_provenance[4]: domain_digest(
            "ishikawa.explicit-reference-seed-group.v1",
            {"citation_id": passage.relationship_provenance[4]},
        )
        for passage in package.selected
        if relationship_coverage_required
        and len(passage.relationship_provenance) >= 5
    }
    evidence: list[GroundedEvidence] = []
    for passage in package.selected:
        target_required = (
            relationship_coverage_required
            and bool(passage.relationship_provenance)
        )
        exact_chunk_group_id = (
            domain_digest(
                "ishikawa.exact-evidence-group.v1",
                {"chunk_id": passage.passage_id},
            )
            if passage.passage_id in exact_required_chunk_ids
            else None
        )
        for citation in passage.citations:
            source_label = labels_by_version.get(citation.document_version_id)
            if source_label is None:
                raise RetrievalServiceContractError(
                    "generation evidence source label is absent"
                )
            excerpt = citation_excerpts.get(citation.citation_id, passage.text)
            document_metadata = metadata.get(citation.document_version_id)
            seed_group_id = seed_group_by_citation.get(citation.citation_id)
            relationship_required = target_required or seed_group_id is not None
            relationship_group_id = (
                passage.relationship_provenance[0]
                if target_required
                else seed_group_id
            )
            exact_group_id = (
                domain_digest(
                    "ishikawa.exact-document-evidence-group.v1",
                    {"document_version_id": exact_required_document_version_id},
                )
                if exact_required_document_version_id is not None
                and citation.document_version_id
                == exact_required_document_version_id
                else exact_chunk_group_id
            )
            required_group_ids = tuple(
                group_id
                for group_id in (relationship_group_id, exact_group_id)
                if group_id is not None
            )
            evidence.append(
                GroundedEvidence(
                    citation_id=citation.citation_id,
                    source_label=source_label,
                    excerpt=excerpt,
                    page_start=citation.page_start,
                    page_end=citation.page_end,
                    structural_path=citation.structural_path,
                    origin=(
                        "relationship"
                        if passage.relationship_provenance
                        else "direct"
                    ),
                    inclusion_reason=passage.inclusion_reason,
                    relationship_required=relationship_required,
                    relationship_group_id=relationship_group_id,
                    required_group_ids=required_group_ids,
                    document_key=citation.document_key,
                    document_identifier=document_identifiers.get(
                        citation.document_version_id
                    ),
                    display_name=(
                        None if document_metadata is None else document_metadata.display_name
                    ),
                )
            )
    if len({item.citation_id for item in evidence}) != len(evidence):
        raise RetrievalServiceContractError(
            "generation evidence contains duplicate citations"
        )
    return tuple(evidence)


def _fit_exact_generation_context(
    package: EvidencePackage,
    *,
    request: ApiChatRequest,
    resolved_query: str,
    policy: ReconstructionPolicy,
    text_token_counter: Callable[[str], int],
    prompt_token_counter: GenerationPromptTokenCounter,
    exact_required_chunk_ids: frozenset[str],
    exact_required_document_version_id: str | None = None,
    relationship_coverage_required: bool,
    prompt_target_tokens: int,
    citation_excerpts: dict[str, str],
    metadata: dict[str, _DocumentMetadata],
    document_identifiers: dict[str, str | None],
) -> tuple[EvidencePackage, tuple[GroundedEvidence, ...], int]:
    """Admit the exact chat-template request, trimming optional units whole."""

    if package.status != "ok":
        return package, (), 0
    if (
        not isinstance(resolved_query, str)
        or not resolved_query.strip()
        or resolved_query != resolved_query.strip()
        or "\x00" in resolved_query
    ):
        raise RetrievalServiceContractError(
            "generation packing resolved query is invalid"
        )
    history = tuple(
        ConversationTurn(turn.role, turn.content) for turn in request.history
    )

    def projected(
        candidate: EvidencePackage,
    ) -> tuple[tuple[GroundedEvidence, ...], int]:
        evidence = _generation_evidence(
            candidate,
            exact_required_chunk_ids=exact_required_chunk_ids,
            exact_required_document_version_id=(
                exact_required_document_version_id
            ),
            relationship_coverage_required=relationship_coverage_required,
            citation_excerpts=citation_excerpts,
            metadata=metadata,
            document_identifiers=document_identifiers,
        )
        generation_request = build_grounded_generation_request(
            conversation_id=request.conversation_id,
            turn_id=request.turn_id,
            history=history,
            question=resolved_query,
            evidence=evidence,
            policy=policy,
        )
        try:
            prompt_tokens = prompt_token_counter(
                generation_request.body["messages"],
                generation_request.body["chat_template_kwargs"],
            )
        except RetrievalDependencyUnavailable:
            raise
        except Exception as error:
            raise RetrievalDependencyUnavailable(
                "generation_prompt_token_counter_failed"
            ) from error
        if type(prompt_tokens) is not int or prompt_tokens < 1:
            raise RetrievalServiceContractError(
                "generation prompt token count is invalid"
            )
        return evidence, prompt_tokens

    hard_prompt_limit = policy.total_context_tokens - policy.answer_token_reserve
    prompt_limit = hard_prompt_limit if package.complete_procedure else prompt_target_tokens
    if package.complete_procedure:
        evidence, prompt_tokens = projected(package)
        if prompt_tokens <= prompt_limit:
            return package, evidence, prompt_tokens
        blocked = replace(
            package,
            status="context-limit",
            reason_code="COMPLETE_PROCEDURE_CONTEXT_LIMIT",
            selected=(),
            omitted=(
                *package.omitted,
                *(
                    ReconstructionAction(
                        passage.passage_id,
                        "omitted",
                        "generation_prompt_budget_limit",
                    )
                    for passage in package.selected
                ),
            ),
            source_groups=(),
            evidence_tokens=0,
        )
        return blocked, (), 0

    group_order: list[tuple[str, str]] = []
    passages_by_group: dict[tuple[str, str], list[Any]] = {}
    for passage in package.selected:
        group = (
            passage.citations[0].document_version_id,
            passage.selection_group_id,
        )
        if group not in passages_by_group:
            group_order.append(group)
            passages_by_group[group] = []
        passages_by_group[group].append(passage)

    relationship_seed_citations = {
        passage.relationship_provenance[4]
        for passage in package.selected
        if relationship_coverage_required
        and len(passage.relationship_provenance) >= 5
    }
    mandatory_groups = frozenset(
        group
        for group, passages in passages_by_group.items()
        if any(
            passage.passage_id in exact_required_chunk_ids
            or (
                relationship_coverage_required
                and (
                    bool(passage.relationship_provenance)
                    or any(
                        citation.citation_id in relationship_seed_citations
                        for citation in passage.citations
                    )
                )
            )
            for passage in passages
        )
    )
    optional_groups = tuple(
        group for group in group_order if group not in mandatory_groups
    )

    # A compact serialization can make a broad package fit beneath the token
    # target without making that package responsive.  Bound optional structural
    # units first, preserving their fused-rank order and every mandatory exact
    # or explicit-relationship unit.  Token fitting below may reduce this
    # bounded package further, but may never add lower-ranked units back.
    responsive_optional_groups = optional_groups[
        : policy.generation_optional_group_limit
    ]
    responsive_retained = frozenset(
        (*mandatory_groups, *responsive_optional_groups)
    )
    responsive_package = retain_evidence_selection_groups(
        package,
        responsive_retained,
        token_counter=text_token_counter,
        omission_reason="generation_responsive_group_limit",
    )
    if responsive_package.status != "ok":
        return responsive_package, (), 0
    evidence, prompt_tokens = projected(responsive_package)
    if prompt_tokens <= prompt_limit:
        return responsive_package, evidence, prompt_tokens

    best: tuple[EvidencePackage, tuple[GroundedEvidence, ...], int] | None = None
    lower = 0
    upper = len(responsive_optional_groups)
    while lower <= upper:
        count = (lower + upper) // 2
        retained = frozenset(
            (*mandatory_groups, *responsive_optional_groups[:count])
        )
        if not retained:
            lower = count + 1
            continue
        candidate = retain_evidence_selection_groups(
            responsive_package,
            retained,
            token_counter=text_token_counter,
        )
        candidate_evidence, candidate_tokens = projected(candidate)
        if candidate_tokens <= prompt_limit:
            best = (candidate, candidate_evidence, candidate_tokens)
            lower = count + 1
        else:
            upper = count - 1
    if best is not None:
        return best
    blocked = retain_evidence_selection_groups(
        responsive_package,
        frozenset(),
        token_counter=text_token_counter,
    )
    return blocked, (), 0


def _expanded_display_sources(
    connection: Any,
    package: EvidencePackage,
    filters: CandidateFilters,
    generation_sources: tuple[ApiSourceGroup, ...],
) -> tuple[ApiSourceGroup, ...]:
    """Expand cited structural sections for display without changing model evidence."""

    selected_paths: dict[str, set[tuple[str, ...]]] = {}
    for passage in package.selected:
        for citation in passage.citations:
            if citation.structural_path:
                selected_paths.setdefault(citation.document_version_id, set()).add(
                    (citation.structural_path[0],)
                )

    expanded: list[ApiSourceGroup] = []
    for source in generation_sources:
        roots = selected_paths.get(source.source_id, set())
        if not roots:
            expanded.append(source)
            continue
        display_units = _load_structural_display_units(
            connection, source.source_id, filters
        )
        inventory_roots = {
            unit.excerpt.structural_path[0]
            for unit in display_units
            if unit.excerpt.structural_path
        }
        generation_excerpts = {
            excerpt.citation_id: excerpt for excerpt in source.excerpts
        }
        displayed_citations: set[str] = set()
        excerpts: list[ApiExcerpt] = []
        for display_unit in display_units:
            citation = display_unit.excerpt
            if not any(
                citation.structural_path[: len(root)] == root for root in roots
            ):
                continue
            if citation.citation_id in displayed_citations:
                continue
            if display_unit.projection_kind in {"page_status", "table_context"}:
                generation_excerpt = generation_excerpts.get(citation.citation_id)
                if generation_excerpt is None:
                    continue
                citation = generation_excerpt
            excerpts.append(citation)
            displayed_citations.add(citation.citation_id)

        # Display expansion is additive. Evidence accepted for generation must
        # never disappear merely because its projection is not independently
        # expanded or its structural path falls outside the selected roots.
        for generation_excerpt in source.excerpts:
            if generation_excerpt.citation_id not in displayed_citations:
                excerpts.append(generation_excerpt)
                displayed_citations.add(generation_excerpt.citation_id)
        # The API contract permits at most twenty excerpts per document. Never
        # present a silently truncated section; retain the qualified generation
        # evidence when a display expansion cannot fit the exact boundary.
        if not excerpts or len(excerpts) > 20:
            expanded.append(source)
            continue
        expanded.append(
            ApiSourceGroup(
                source_id=source.source_id,
                source_label=source.source_label,
                document_key=source.document_key,
                document_identifier=source.document_identifier,
                display_name=source.display_name,
                document_class=source.document_class,
                excerpts=tuple(excerpts),
                page_count=source.page_count,
                has_additional_sections=bool(
                    inventory_roots - {root[0] for root in roots}
                ),
            )
        )
    return tuple(expanded)


def _load_structural_display_units(
    connection: Any,
    document_version_id: str,
    filters: CandidateFilters,
) -> tuple[_StructuralDisplayUnit, ...]:
    """Load source excerpts without the prefixes added for retrieval quality."""

    rows = connection.execute(
        """/* ishikawa.postgres-retrieval.structural-display-units */
        SELECT ac.ordinal, ac.projection_kind, citation.citation_id,
               citation.relevant_excerpt, citation.page_start,
               citation.page_end, citation.structural_path
        FROM rag_search.active_chunks ac
        JOIN rag_search.active_citations citation ON citation.chunk_id = ac.chunk_id
        WHERE ac.document_version_id = %s
          AND (cardinality(%s::text[]) = 0 OR ac.class_id = ANY(%s::text[]))
          AND (cardinality(%s::text[]) = 0 OR ac.document_key = ANY(%s::text[]))
        ORDER BY ac.ordinal, citation.page_start, citation.page_end,
                 citation.citation_id
        """,
        (
            document_version_id,
            list(filters.document_classes),
            list(filters.document_classes),
            list(filters.document_keys),
            list(filters.document_keys),
        ),
    ).fetchall()
    units: list[_StructuralDisplayUnit] = []
    seen_citations: set[str] = set()
    for row in rows:
        if (
            not isinstance(row, Sequence)
            or isinstance(row, (str, bytes))
            or len(row) != 7
            or type(row[0]) is not int
            or not isinstance(row[1], str)
            or not row[1].strip()
        ):
            raise RetrievalServiceContractError("structural display row is invalid")
        citation = ApiExcerpt(
            citation_id=row[2],
            excerpt=row[3],
            page_start=row[4],
            page_end=row[5],
            structural_path=tuple(row[6]),
        )
        if citation.citation_id in seen_citations:
            continue
        seen_citations.add(citation.citation_id)
        units.append(_StructuralDisplayUnit(row[1], citation))
    if not units:
        raise RetrievalServiceContractError("structural display inventory is absent")
    return tuple(units)


@dataclass(frozen=True, slots=True)
class NativePostgresRetrievalAdapter:
    """Execute the qualified retrieval path in one read-only transaction."""

    connection_factory: Callable[[], Any]
    query_embedder: Callable[[str], ValidatedQueryEmbedding]
    generation_token_counter: Callable[[str], int]
    generation_prompt_token_counter: GenerationPromptTokenCounter
    retrieval_policy: RetrievalProfile
    reconstruction_policy: ReconstructionPolicy
    relevance_policy: RelevancePolicy
    sufficiency_policy: SufficiencyPolicy
    relationship_registry: RelationshipRegistry
    expected_database_role: str = EXPECTED_RETRIEVAL_ROLE
    clock_ns: Callable[[], int] = monotonic_ns

    def __post_init__(self) -> None:
        if not all(
            callable(item)
            for item in (
                self.connection_factory,
                self.query_embedder,
                self.generation_token_counter,
                self.generation_prompt_token_counter,
                self.clock_ns,
            )
        ):
            raise RetrievalServiceContractError("retrieval adapter port is invalid")
        if (
            not isinstance(self.retrieval_policy, RetrievalProfile)
            or not isinstance(self.reconstruction_policy, ReconstructionPolicy)
            or not isinstance(self.relevance_policy, RelevancePolicy)
            or not isinstance(self.sufficiency_policy, SufficiencyPolicy)
            or not isinstance(self.relationship_registry, RelationshipRegistry)
            or self.relationship_registry.base_retrieval_profile_id
            != self.retrieval_policy.digest
            or self.expected_database_role != EXPECTED_RETRIEVAL_ROLE
        ):
            raise RetrievalServiceContractError("retrieval adapter policy is invalid")

    def __call__(
        self,
        request: ApiChatRequest,
        resolution: ResolvedRetrievalQuery,
    ) -> RetrievedEvidence:
        if not isinstance(request, ApiChatRequest) or not isinstance(
            resolution, ResolvedRetrievalQuery
        ):
            raise RetrievalServiceContractError("retrieval adapter input is invalid")
        if (
            resolution.status != "resolved"
            or resolution.resolved_query is None
            or resolution.original_query != request.message
            or resolution.filters != request.filters
        ):
            raise RetrievalServiceContractError("retrieval resolution is inconsistent")

        stage_timer = _RetrievalStageTimer(self.clock_ns)
        try:
            embedding = stage_timer.measure(
                "nomic",
                lambda: self.query_embedder(resolution.resolved_query),
            )
        except RetrievalDependencyUnavailable:
            raise
        except Exception as error:
            raise RetrievalDependencyUnavailable("query_embedding_failed") from error
        if not isinstance(embedding, ValidatedQueryEmbedding):
            raise RetrievalServiceContractError("query embedding result is invalid")
        nomic_query_tokens = embedding.prompt_tokens

        version_ids = tuple(item.source_id for item in resolution.source_constraints)
        filters = CandidateFilters(
            document_classes=request.filters.document_classes,
            document_keys=request.filters.document_keys,
            document_version_ids=version_ids,
        )
        connection = None
        try:
            connection = self.connection_factory()
            connection.execute(
                """/* ishikawa.postgres-retrieval.begin */
                BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY
                """
            )
            boundary = connection.execute(
                """/* ishikawa.postgres-retrieval.boundary */
                SELECT current_user,
                       current_setting('transaction_read_only'),
                       current_setting('transaction_isolation')
                """
            ).fetchone()
            if boundary != (self.expected_database_role, "on", "repeatable read"):
                raise RetrievalServiceContractError("retrieval database boundary is invalid")

            exact_items: list[LaneCandidate] = []
            exact_requirements: list[bool] = []
            for source in resolution.source_constraints:
                source_matches = exact_lookup(
                    connection,
                    "citation_id" if source.citation_id is not None else "document_version_id",
                    source.citation_id or source.source_id,
                    depth=self.retrieval_policy.exact_candidate_depth,
                    filters=filters,
                )
                exact_items.extend(source_matches)
                exact_requirements.append(bool(source_matches))
            structured_terms = extract_structured_terms(resolution.resolved_query)
            explicit_page = extract_explicit_page(resolution.resolved_query)
            page_routed = False
            if explicit_page is not None and len(structured_terms) == 1:
                page_matches = exact_document_page_lookup(
                    connection,
                    structured_terms[0],
                    explicit_page,
                    depth=self.retrieval_policy.exact_candidate_depth,
                    filters=filters,
                )
                if page_matches:
                    exact_items.extend(page_matches)
                    exact_requirements.append(True)
                    page_routed = True
            if not page_routed:
                for term in structured_terms:
                    term_matches = exact_term_lookup(
                        connection,
                        term,
                        depth=self.retrieval_policy.exact_candidate_depth,
                        filters=filters,
                    )
                    exact_items.extend(term_matches)
                    exact_requirements.append(bool(term_matches))
            exact = _merge_exact_candidates(exact_items)
            exact_required_chunk_ids = frozenset(item.chunk_id for item in exact)
            unique_exact_document_constraint = (
                len(resolution.source_constraints) == 1
                and resolution.source_constraints[0].citation_id is None
                and len(structured_terms) == 1
                and bool(exact_requirements)
                and all(exact_requirements)
            )
            requested_section = requested_complete_section(request.message)
            complete_requested = (
                requests_complete_procedure(request.message)
                or requested_section is not None
            )
            advanced_body_route = uses_calibrated_body_route(
                resolution.resolved_query,
                page_routed=page_routed,
                complete_structure_requested=complete_requested,
            )
            use_candidate_representation = (
                self.retrieval_policy.section_page_representatives
                and self.retrieval_policy.document_local_duplicate_canonicalization
                and (not exact or not advanced_body_route)
            )
            lexical = stage_timer.measure(
                "lexical_sql",
                lambda: lexical_search(
                    connection,
                    resolution.resolved_query,
                    depth=self.retrieval_policy.lexical_candidate_depth,
                    text_search_config=self.retrieval_policy.lexical_search_config,
                    filters=filters,
                    use_candidate_representation=use_candidate_representation,
                ),
            )
            vector = stage_timer.measure(
                "vector_sql",
                lambda: vector_search(
                    connection,
                    embedding.vector,
                    embedding.embedding_space_id,
                    depth=self.retrieval_policy.vector_candidate_depth,
                    filters=filters,
                    use_candidate_representation=use_candidate_representation,
                ),
            )
            ranked_fused = stage_timer.measure(
                "fusion",
                lambda: reciprocal_rank_fusion(
                    {"exact": exact, "lexical": lexical, "vector": vector},
                    rrf_constant=self.retrieval_policy.rrf_constant,
                    lane_weights={
                        "exact": self.retrieval_policy.exact_weight,
                        "lexical": self.retrieval_policy.lexical_weight,
                        "vector": self.retrieval_policy.vector_weight,
                    },
                ),
            )
            if use_candidate_representation:
                ranked_fused = collapse_retrieval_groups(ranked_fused)
            if advanced_body_route and (exact or lexical or vector):
                facets = decompose_retrieval_query(resolution.resolved_query)
                shortlisted_documents = balanced_document_shortlist(
                    exact,
                    lexical,
                    vector,
                    depth_per_lane=self.retrieval_policy.document_shortlist_per_lane,
                )
                expanded_filters = CandidateFilters(
                    document_classes=filters.document_classes,
                    document_keys=shortlisted_documents,
                    document_version_ids=filters.document_version_ids,
                )
                facet_lanes: list[dict[str, tuple[LaneCandidate, ...]]] = []
                for facet in facets:
                    if facet == resolution.resolved_query:
                        facet_embedding = embedding
                    else:
                        try:
                            facet_embedding = stage_timer.measure(
                                "nomic", lambda: self.query_embedder(facet)
                            )
                        except RetrievalDependencyUnavailable:
                            raise
                        except Exception as error:
                            raise RetrievalDependencyUnavailable(
                                "query_embedding_failed"
                            ) from error
                        if not isinstance(facet_embedding, ValidatedQueryEmbedding):
                            raise RetrievalServiceContractError(
                                "query embedding result is invalid"
                            )
                        if facet_embedding.embedding_space_id != embedding.embedding_space_id:
                            raise RetrievalServiceContractError(
                                "facet embedding space is inconsistent"
                            )
                        nomic_query_tokens += facet_embedding.prompt_tokens
                    facet_lexical = stage_timer.measure(
                        "lexical_sql",
                        lambda: lexical_search(
                            connection,
                            facet,
                            depth=self.retrieval_policy.lexical_candidate_depth,
                            text_search_config=(
                                self.retrieval_policy.lexical_search_config
                            ),
                            filters=expanded_filters,
                            use_candidate_representation=use_candidate_representation,
                        ),
                    )
                    facet_vector = stage_timer.measure(
                        "vector_sql",
                        lambda: vector_search(
                            connection,
                            facet_embedding.vector,
                            facet_embedding.embedding_space_id,
                            depth=self.retrieval_policy.vector_candidate_depth,
                            filters=expanded_filters,
                            use_candidate_representation=use_candidate_representation,
                        ),
                    )
                    facet_lanes.append(
                        {"lexical": facet_lexical, "vector": facet_vector}
                    )
                ranked_fused = stage_timer.measure(
                    "fusion",
                    lambda: decomposed_candidate_pool(
                        ranked_fused,
                        facet_lanes,
                        rrf_constant=self.retrieval_policy.rrf_constant,
                        baseline_weight=self.retrieval_policy.expansion_baseline_weight,
                        best_facet_weight=self.retrieval_policy.expansion_best_facet_weight,
                        facet_coverage_weight=(
                            self.retrieval_policy.expansion_facet_coverage_weight
                        ),
                    ),
                )
                if use_candidate_representation:
                    ranked_fused = collapse_retrieval_groups(ranked_fused)
                ranked_fused = stage_timer.measure(
                    "fusion",
                    lambda: score_calibrated_global_rerank(
                        ranked_fused[: self.retrieval_policy.fused_candidate_depth],
                        lexical,
                        vector,
                        facet_lanes,
                        resolution.resolved_query,
                    ),
                )
            selected_group_order: tuple[str, ...] = ()
            if advanced_body_route and ranked_fused and not exact:
                response_envelopes = plan_citable_response_envelopes(
                    connection,
                    resolution.resolved_query,
                    ranked_fused[: self.retrieval_policy.fused_candidate_depth],
                    self.relevance_policy,
                )
                relevance_candidates = response_envelopes.relevance_candidates
                ranked_for_assembly = response_envelopes.ordered_candidates
                selected_group_order = response_envelopes.selected_group_order
                relevance = response_envelopes.decision
            else:
                relevance_candidates = select_ranked_relevance_candidates(
                    ranked_fused,
                    depth=self.relevance_policy.fused_depth,
                )
                ranked_for_assembly = ranked_fused[
                    : self.retrieval_policy.fused_candidate_depth
                ]
                relevance = measure_citable_evidence_relevance(
                    connection,
                    resolution.resolved_query,
                    relevance_candidates,
                    self.relevance_policy,
                )
            fused = expand_authoritative_candidates(ranked_for_assembly)
            hydrated, metadata = _hydrate_candidates(connection, fused, filters)
            relationship_candidates: tuple[EvidenceCandidate, ...] = ()
            relationship_required = 0
            relationship_covered = 0
            if not complete_requested and not page_routed:
                (
                    relationship_candidates,
                    relationship_metadata,
                    relationship_required,
                    relationship_covered,
                ) = _load_relationship_candidates(
                    connection,
                    direct_fused=fused,
                    query=resolution.resolved_query,
                    query_embedding=embedding,
                    filters=filters,
                    retrieval_policy=self.retrieval_policy,
                    relationship_registry=self.relationship_registry,
                    stage_timer=stage_timer,
                )
                _merge_metadata(metadata, relationship_metadata)
            def measured_text_token_counter(text: str) -> int:
                return stage_timer.measure(
                    "tokenization",
                    lambda: self.generation_token_counter(text),
                )

            def measured_prompt_token_counter(
                messages: Sequence[Mapping[str, str]],
                template_kwargs: Mapping[str, Any],
            ) -> int:
                return stage_timer.measure(
                    "tokenization",
                    lambda: self.generation_prompt_token_counter(
                        messages, template_kwargs
                    ),
                )

            instruction_tokens = _token_count(
                measured_text_token_counter,
                trusted_instruction_text(),
                "instruction",
            )
            conversation_tokens = _token_count(
                measured_text_token_counter,
                _conversation_payload(request),
                "conversation",
            )
            explicit_version = version_ids[0] if len(version_ids) == 1 else None
            relationship_navigation = requests_relationship_navigation(
                request.message
            ) or requests_relationship_navigation(resolution.resolved_query)
            direct_chunk_ids = {item.chunk_id for item in hydrated}
            reconstruction_candidates = hydrated + tuple(
                item
                for item in relationship_candidates
                if item.chunk_id not in direct_chunk_ids
            )
            complete_reconstructed = False
            if complete_requested:
                candidate_versions = {item.primary_version_id for item in hydrated}
                target_version = explicit_version
                if target_version is None and len(candidate_versions) == 1:
                    target_version = next(iter(candidate_versions))
                if target_version is not None:
                    inventory, inventory_metadata = _load_complete_document_inventory(
                        connection, target_version, filters
                    )
                    _merge_metadata(metadata, inventory_metadata)
                    if inventory:
                        target_path = (
                            ()
                            if requested_section is None
                            else _section_path(inventory, requested_section)
                        )
                        if target_path is not None:
                            reconstruction_candidates = reconstruct_complete_procedure(
                                CompleteProcedureTarget(target_version, target_path),
                                inventory,
                                inventory_complete=True,
                            )
                            complete_reconstructed = True
            package = assemble_evidence(
                reconstruction_candidates,
                policy=self.reconstruction_policy,
                token_counter=measured_text_token_counter,
                instruction_tokens=instruction_tokens,
                conversation_tokens=conversation_tokens,
                complete_procedure=complete_reconstructed,
                explicit_document_version_id=explicit_version,
                require_relationship_coverage=relationship_navigation,
            )
            versions_by_document: dict[str, set[str]] = {}
            for item in reconstruction_candidates:
                versions_by_document.setdefault(item.primary_document_id, set()).add(
                    item.primary_version_id
                )
            exact_required = bool(exact_requirements)

            def sufficiency_signals() -> SufficiencySignals:
                return SufficiencySignals(
                    lane_states=(
                        ("exact", "pass" if exact_required else "not_applicable"),
                        ("lexical", "pass"),
                        ("vector", "pass"),
                    ),
                    fused_candidate_count=max(
                        len(fused), len(reconstruction_candidates)
                    ),
                    authorized_candidate_count=len(reconstruction_candidates),
                    exact_constraint_required=exact_required,
                    exact_constraint_satisfied=(
                        all(exact_requirements) if exact_required else True
                    ),
                    unique_exact_document_constraint=(
                        unique_exact_document_constraint
                    ),
                    relationship_coverage_required=(
                        relationship_navigation and relationship_required > 0
                    ),
                    relationship_coverage_complete=(
                        not relationship_navigation
                        or relationship_required == relationship_covered
                    ),
                    source_version_conflict=any(
                        len(versions) > 1
                        for versions in versions_by_document.values()
                    ),
                    relevance_decision=relevance,
                    complete_structure_requested=complete_requested,
                )

            signals = sufficiency_signals()
            generation_evidence: tuple[GroundedEvidence, ...] = ()
            exact_prompt_tokens = 0
            selected_prompt_target = 0
            decision = evaluate_evidence_sufficiency(
                signals,
                package,
                self.sufficiency_policy,
            )
            if package.status == "ok":
                all_citation_ids = tuple(
                    citation.citation_id
                    for passage in package.selected
                    for citation in passage.citations
                )
                citation_excerpts = _load_citation_excerpts(
                    connection, all_citation_ids
                )
                all_version_ids = tuple(
                    dict.fromkeys(
                        group.document_version_id for group in package.source_groups
                    )
                )
                document_identifiers = _load_document_identifiers(
                    connection, all_version_ids
                )
                base_package = package
                targets = (
                    (self.reconstruction_policy.total_context_tokens
                     - self.reconstruction_policy.answer_token_reserve,)
                    if package.complete_procedure
                    else self.reconstruction_policy.generation_prompt_targets
                )
                for prompt_target in targets:
                    (
                        candidate_package,
                        candidate_evidence,
                        candidate_prompt_tokens,
                    ) = _fit_exact_generation_context(
                        base_package,
                        request=request,
                        resolved_query=resolution.resolved_query,
                        policy=self.reconstruction_policy,
                        text_token_counter=measured_text_token_counter,
                        prompt_token_counter=measured_prompt_token_counter,
                        exact_required_chunk_ids=exact_required_chunk_ids,
                        exact_required_document_version_id=(
                            version_ids[0]
                            if unique_exact_document_constraint
                            else None
                        ),
                        relationship_coverage_required=relationship_navigation,
                        prompt_target_tokens=prompt_target,
                        citation_excerpts=citation_excerpts,
                        metadata=metadata,
                        document_identifiers=document_identifiers,
                    )
                    candidate_decision = evaluate_evidence_sufficiency(
                        signals,
                        candidate_package,
                        self.sufficiency_policy,
                    )
                    package = candidate_package
                    generation_evidence = candidate_evidence
                    exact_prompt_tokens = candidate_prompt_tokens
                    selected_prompt_target = prompt_target
                    decision = candidate_decision
                    if candidate_decision.status == "sufficient":
                        break
            if decision.status == "sufficient":
                version_ids_for_response = tuple(
                    group.document_version_id for group in package.source_groups
                )
                if package.status != "ok":
                    raise RetrievalServiceContractError(
                        "sufficient evidence package is invalid"
                    )
                document_page_counts = _load_document_page_counts(
                    connection, version_ids_for_response
                )
                generation_sources = _source_groups(
                    package,
                    metadata,
                    document_identifiers,
                    document_page_counts,
                    citation_excerpts,
                )
                sources = _expanded_display_sources(
                    connection,
                    package,
                    filters,
                    generation_sources,
                )
            else:
                generation_sources = ()
                sources = ()
            retained_group_order: list[str] = []
            for passage in package.selected:
                group_identity = (
                    f"{passage.citations[0].document_version_id}:"
                    f"{passage.selection_group_id}"
                )
                if group_identity not in retained_group_order:
                    retained_group_order.append(group_identity)
            if retained_group_order:
                selected_group_order = tuple(retained_group_order[:6])
            telemetry = RetrievalOperationalTelemetry(
                signals.lane_states,
                signals.fused_candidate_count,
                signals.authorized_candidate_count,
                decision.evidence_passages,
                decision.citation_count,
                exact_prompt_tokens,
                package.answer_token_reserve,
                exact_prompt_tokens + package.answer_token_reserve
                if exact_prompt_tokens
                else package.instruction_tokens
                + package.conversation_tokens
                + package.evidence_tokens
                + package.answer_token_reserve,
                self.reconstruction_policy.total_context_tokens,
                nomic_query_tokens,
                selected_prompt_target,
                stage_timer.finish(),
                relevance.reason_code,
                decision.reason_code,
                selected_group_order,
            )
            return RetrievedEvidence(
                decision,
                sources,
                telemetry,
                generation_sources if decision.status == "sufficient" else None,
                generation_evidence
                if decision.status == "sufficient"
                else None,
            )
        except RetrievalDependencyUnavailable:
            raise
        except (
            RetrievalContractError,
            ReconstructionContractError,
            RelevanceContractError,
            SufficiencyContractError,
            RetrievalServiceContractError,
        ):
            raise
        except Exception as error:
            raise RetrievalDependencyUnavailable("postgres_retrieval_failed") from error
        finally:
            if connection is not None:
                try:
                    connection.rollback()
                except Exception:
                    pass
                try:
                    connection.close()
                except Exception:
                    pass
