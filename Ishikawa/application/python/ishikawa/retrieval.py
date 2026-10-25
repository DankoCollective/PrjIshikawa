"""Read-only PostgreSQL retrieval lanes and deterministic rank fusion.

The module owns candidate retrieval only. It does not resolve conversations,
call a model, reconstruct evidence, or generate answers. All SQL reads the
active ``rag_search`` views so the retrieval database role never needs access
to ingestion tables.
"""

from __future__ import annotations

import math
import re
from dataclasses import dataclass, replace
from typing import Any, Iterable, Mapping, Sequence

from .method_profile import ACCEPTED_RETRIEVAL_PROFILE


LANES = ("exact", "lexical", "vector")
MAX_QUERY_FACETS = 4
MIN_QUERY_FACET_WORDS = 3
QUERY_CLAUSE_BOUNDARY = re.compile(
    r"\s*(?:;|\b(?:and|or)\b(?=\s+(?:what|when|where|who|why|how|which|whether|under)\b))\s*",
    re.IGNORECASE,
)
QUERY_WORD = re.compile(r"[A-Za-z0-9]+(?:[-'][A-Za-z0-9]+)*")
RERANK_WORD = re.compile(r"[a-z0-9]+")
RERANK_STOPWORDS = frozenset(
    {
        "a", "an", "and", "are", "be", "by", "do", "does", "for", "from",
        "how", "in", "is", "it", "its", "may", "must", "of", "on", "or",
        "should", "that", "the", "their", "this", "to", "under", "what",
        "when", "where", "which", "who", "why", "with",
    }
)
HEADER_CONTROL_TERMS = (
    re.compile(r"\bdepartment\b|\bdept\.?\b", re.IGNORECASE),
    re.compile(r"\bapplicability(?:\s*/\s*class)?\b", re.IGNORECASE),
    re.compile(r"\beffective\s+date\b", re.IGNORECASE),
    re.compile(r"\b(?:date\s+of\s+review|review\s+date)\b", re.IGNORECASE),
    re.compile(r"\bapproval\b", re.IGNORECASE),
    re.compile(r"\bpolicy\s+number\b", re.IGNORECASE),
)
RELATIONSHIP_QUERY = re.compile(
    r"\b(?:references?|referenced\s+(?:documents?|polic(?:y|ies)))\b",
    re.IGNORECASE,
)
STRUCTURED_TERM_PATTERNS = (
    re.compile(r"\b[A-Z][A-Z0-9]{1,15}-[A-Z0-9][A-Z0-9.-]{0,31}\b"),
    re.compile(r"\b[0-9]{2,6}\s+[A-Z][A-Z0-9]{1,15}\s+[0-9]{2,8}\b"),
)
PAGE_REFERENCE = re.compile(r"\bpage\s+([1-9][0-9]{0,5})\b", re.IGNORECASE)
CLASS_ID = re.compile(r"^[a-z][a-z0-9_]{1,63}$")
DOCUMENT_KEY = re.compile(r"^[a-z0-9]+(?:[._-][a-z0-9]+)*$")
SHA256_IDENTITY = re.compile(r"^[0-9a-f]{64}$")

# This predicate is the PostgreSQL form of the conservative self-declaration
# rules in relationships.extract_declared_identifiers.  The supplied reference
# has already passed STRUCTURED_TERM_PATTERNS, so it cannot introduce LIKE
# wildcards.  Citation whitespace is folded because PDF extraction may retain
# runs of spaces between a declaration label and its value.
DECLARED_IDENTIFIER_MATCH_SQL = """(
          declaration.declaration_text = lower(%s)
          OR declaration.declaration_text = lower('form no. ' || %s)
          OR declaration.declaration_text = lower('policy number: ' || %s)
          OR declaration.declaration_text LIKE lower('policy number: ' || %s || '.%%')
          OR declaration.declaration_text LIKE lower('policy number: ' || %s || ';%%')
        )"""


class RetrievalContractError(ValueError):
    """Raised when a retrieval request violates the frozen boundary."""


@dataclass(frozen=True, slots=True)
class CandidateFilters:
    """Code-owned restrictions applied before every lane returns candidates."""

    document_classes: tuple[str, ...] = ()
    document_keys: tuple[str, ...] = ()
    document_version_ids: tuple[str, ...] = ()

    def __post_init__(self) -> None:
        groups = (
            (self.document_classes, CLASS_ID, "document class"),
            (self.document_keys, DOCUMENT_KEY, "document key"),
            (self.document_version_ids, SHA256_IDENTITY, "document-version identity"),
        )
        for values, pattern, label in groups:
            if (
                not isinstance(values, tuple)
                or len(values) > 20
                or len(set(values)) != len(values)
                or any(not isinstance(value, str) or pattern.fullmatch(value) is None for value in values)
            ):
                raise RetrievalContractError(f"{label} filters are invalid")


def _filter_sql(alias: str, filters: CandidateFilters) -> tuple[str, tuple[Any, ...]]:
    if not isinstance(filters, CandidateFilters):
        raise RetrievalContractError("candidate filters are invalid")
    clauses: list[str] = []
    parameters: list[Any] = []
    if filters.document_classes:
        clauses.append(f"{alias}.class_id = ANY(%s::text[])")
        parameters.append(list(filters.document_classes))
    if filters.document_keys:
        clauses.append(f"{alias}.document_key = ANY(%s::text[])")
        parameters.append(list(filters.document_keys))
    if filters.document_version_ids:
        clauses.append(f"{alias}.document_version_id = ANY(%s::text[])")
        parameters.append(list(filters.document_version_ids))
    if not clauses:
        return "", ()
    return "\n          AND " + "\n          AND ".join(clauses), tuple(parameters)


@dataclass(frozen=True, slots=True)
class LaneCandidate:
    chunk_id: str
    document_id: str
    document_version_id: str
    document_key: str
    lane: str
    rank: int
    raw_score: float
    exact_reason: str | None = None
    retrieval_variant: str | None = None
    retrieval_group_id: str | None = None
    authoritative_chunk_ids: tuple[str, ...] = ()
    retrieval_scoring_only: bool = False
    document_local_content_canonical: bool = True
    structural_path: tuple[str, ...] = ()

    def __post_init__(self) -> None:
        if self.lane not in LANES:
            raise RetrievalContractError("candidate lane is unsupported")
        if self.rank < 1:
            raise RetrievalContractError("candidate rank must be positive")
        if self.lane == "exact" and not self.exact_reason:
            raise RetrievalContractError("exact candidates require a reason")
        if self.lane != "exact" and self.exact_reason is not None:
            raise RetrievalContractError("non-exact candidates cannot claim an exact reason")
        if self.lane == "lexical" and self.retrieval_variant not in ("strict", "or_fallback"):
            raise RetrievalContractError("lexical candidates require their retrieval variant")
        if self.lane != "lexical" and self.retrieval_variant is not None:
            raise RetrievalContractError("only lexical candidates may claim a retrieval variant")
        if self.retrieval_group_id is not None and (
            not isinstance(self.retrieval_group_id, str) or not self.retrieval_group_id
        ):
            raise RetrievalContractError("candidate retrieval group is invalid")
        if not self.authoritative_chunk_ids:
            object.__setattr__(self, "authoritative_chunk_ids", (self.chunk_id,))
        if (
            not isinstance(self.authoritative_chunk_ids, tuple)
            or len(set(self.authoritative_chunk_ids)) != len(self.authoritative_chunk_ids)
            or any(not isinstance(value, str) or not value for value in self.authoritative_chunk_ids)
        ):
            raise RetrievalContractError("candidate authoritative chunks are invalid")
        if self.retrieval_scoring_only and self.authoritative_chunk_ids == (self.chunk_id,):
            raise RetrievalContractError("a scoring-only candidate requires atomic evidence")
        if (
            not isinstance(self.structural_path, tuple)
            or any(not isinstance(item, str) or not item.strip() for item in self.structural_path)
        ):
            raise RetrievalContractError("candidate structural path is invalid")


@dataclass(frozen=True, slots=True)
class LaneEvidence:
    lane: str
    rank: int
    raw_score: float
    exact_reason: str | None
    retrieval_variant: str | None


@dataclass(frozen=True, slots=True)
class FusedCandidate:
    chunk_id: str
    document_id: str
    document_version_id: str
    document_key: str
    fused_score: float
    exact_priority: bool
    evidence: tuple[LaneEvidence, ...]
    retrieval_group_id: str | None = None
    authoritative_chunk_ids: tuple[str, ...] = ()
    retrieval_scoring_only: bool = False
    structural_path: tuple[str, ...] = ()


def _require_depth(depth: int) -> None:
    if type(depth) is not int or not 1 <= depth <= 100:
        raise RetrievalContractError("candidate depth must be between 1 and 100")


def _require_text(value: str, label: str, *, maximum: int = 4096) -> str:
    if not isinstance(value, str) or not value.strip() or value != value.strip():
        raise RetrievalContractError(f"{label} must be a trimmed nonblank string")
    if len(value) > maximum or "\x00" in value:
        raise RetrievalContractError(f"{label} exceeds its safe boundary")
    return value


def declared_identifier_parameters(reference: str) -> tuple[str, ...]:
    """Bind one validated reference to every self-declaration comparison."""

    value = _require_text(reference, "declared document reference", maximum=256)
    if not any(pattern.fullmatch(value) for pattern in STRUCTURED_TERM_PATTERNS):
        raise RetrievalContractError("document reference has an unsupported shape")
    return (value, value, value, value, value)


def _rows_to_candidates(
    rows: Sequence[Sequence[Any]],
    lane: str,
    exact_reason: str | None = None,
    retrieval_variant: str | None = None,
) -> tuple[LaneCandidate, ...]:
    candidates: list[LaneCandidate] = []
    for index, row in enumerate(rows, start=1):
        if len(row) not in {5, 10}:
            raise RetrievalContractError("retrieval lane row is invalid")
        candidates.append(
            LaneCandidate(
                chunk_id=row[0],
                document_id=row[1],
                document_version_id=row[2],
                document_key=row[3],
                lane=lane,
                rank=index,
                raw_score=float(row[4]),
                exact_reason=exact_reason,
                retrieval_variant=retrieval_variant,
                retrieval_group_id=None if len(row) == 5 else row[5],
                authoritative_chunk_ids=() if len(row) == 5 else tuple(row[6]),
                retrieval_scoring_only=False if len(row) == 5 else row[7],
                document_local_content_canonical=True if len(row) == 5 else row[8],
                structural_path=() if len(row) == 5 else tuple(row[9]),
            )
        )
    return tuple(candidates)


def decompose_retrieval_query(query: str) -> tuple[str, ...]:
    """Split a composite question into bounded literal clauses.

    The operation never introduces synonyms or inferred terms. An indivisible
    question remains one facet so the same within-document candidate expansion
    is available to short ordinary questions.
    """

    text = _require_text(query, "retrieval query")
    source = text[:-1] if text.endswith("?") else text
    clauses = [item.strip(" ,:.-") for item in QUERY_CLAUSE_BOUNDARY.split(source)]
    clauses = [
        item for item in clauses
        if len(QUERY_WORD.findall(item)) >= MIN_QUERY_FACET_WORDS
    ]
    unique: list[str] = []
    seen: set[str] = set()
    for clause in clauses:
        folded = clause.casefold()
        if folded not in seen:
            seen.add(folded)
            unique.append(clause)
    result = tuple(unique[:MAX_QUERY_FACETS]) if len(unique) > 1 else (text,)
    if not 1 <= len(result) <= MAX_QUERY_FACETS:
        raise RetrievalContractError("retrieval query decomposition is invalid")
    return result


def uses_calibrated_body_route(
    query: str, *, page_routed: bool, complete_structure_requested: bool
) -> bool:
    """Keep explicit metadata, relationship, page, and whole-structure routes stable."""

    text = _require_text(query, "retrieval route query")
    if type(page_routed) is not bool or type(complete_structure_requested) is not bool:
        raise RetrievalContractError("retrieval route flags are invalid")
    if page_routed or complete_structure_requested or RELATIONSHIP_QUERY.search(text):
        return False
    header_term_count = sum(pattern.search(text) is not None for pattern in HEADER_CONTROL_TERMS)
    return header_term_count < 2


def _unique_documents(
    candidates: Sequence[LaneCandidate], depth: int
) -> tuple[str, ...]:
    documents: list[str] = []
    for candidate in candidates:
        if candidate.document_key not in documents:
            documents.append(candidate.document_key)
        if len(documents) == depth:
            break
    return tuple(documents)


def balanced_document_shortlist(
    exact: Sequence[LaneCandidate],
    lexical: Sequence[LaneCandidate],
    vector: Sequence[LaneCandidate],
    *,
    depth_per_lane: int,
) -> tuple[str, ...]:
    """Union balanced primary-lane document ranks without chunk-count bias."""

    if type(depth_per_lane) is not int or not 1 <= depth_per_lane <= 10:
        raise RetrievalContractError("document shortlist depth is invalid")
    exact_documents = _unique_documents(exact, len(exact))
    lexical_documents = _unique_documents(lexical, depth_per_lane)
    vector_documents = _unique_documents(vector, depth_per_lane)
    ordered: list[str] = []
    for document_key in exact_documents:
        if document_key not in ordered:
            ordered.append(document_key)
    for index in range(depth_per_lane):
        for documents in (lexical_documents, vector_documents):
            if index < len(documents) and documents[index] not in ordered:
                ordered.append(documents[index])
    if not ordered or len(ordered) > depth_per_lane * 2 + len(exact_documents):
        raise RetrievalContractError("document shortlist is invalid")
    return tuple(ordered)


def exact_lookup(
    connection: Any,
    reference_kind: str,
    reference_value: str,
    *,
    depth: int = ACCEPTED_RETRIEVAL_PROFILE.exact_candidate_depth,
    filters: CandidateFilters = CandidateFilters(),
) -> tuple[LaneCandidate, ...]:
    """Resolve one verified canonical reference without semantic guessing."""

    _require_depth(depth)
    value = _require_text(reference_value, "exact reference", maximum=256)
    filter_sql, filter_parameters = _filter_sql("ac", filters)
    if reference_kind == "chunk_id":
        sql = f"""/* ishikawa.retrieval.exact.chunk */
            SELECT ac.chunk_id, ac.document_id, ac.document_version_id,
                   ac.document_key, 1.0::float8
            FROM rag_search.active_chunks ac
            WHERE ac.chunk_id = %s{filter_sql}
            ORDER BY ac.chunk_id
            LIMIT %s
        """
    elif reference_kind == "document_key":
        sql = f"""/* ishikawa.retrieval.exact.document */
            SELECT ac.chunk_id, ac.document_id, ac.document_version_id,
                   ac.document_key, 1.0::float8
            FROM rag_search.active_chunks ac
            WHERE ac.document_key = %s{filter_sql}
            ORDER BY ac.ordinal, ac.chunk_id
            LIMIT %s
        """
    elif reference_kind == "document_version_id":
        if SHA256_IDENTITY.fullmatch(value) is None:
            raise RetrievalContractError("document-version reference is invalid")
        sql = f"""/* ishikawa.retrieval.exact.document_version */
            SELECT ac.chunk_id, ac.document_id, ac.document_version_id,
                   ac.document_key, 1.0::float8
            FROM rag_search.active_chunks ac
            WHERE ac.document_version_id = %s{filter_sql}
            ORDER BY ac.ordinal, ac.chunk_id
            LIMIT %s
        """
    elif reference_kind == "citation_id":
        if SHA256_IDENTITY.fullmatch(value) is None:
            raise RetrievalContractError("citation reference is invalid")
        sql = f"""/* ishikawa.retrieval.exact.citation */
            SELECT ac.chunk_id, ac.document_id, ac.document_version_id,
                   ac.document_key, 1.0::float8
            FROM rag_search.active_citations ci
            JOIN rag_search.active_chunks ac ON ac.chunk_id = ci.chunk_id
            WHERE ci.citation_id = %s{filter_sql}
            ORDER BY ac.chunk_id
            LIMIT %s
        """
    else:
        raise RetrievalContractError("exact reference kind is unsupported")
    return _rows_to_candidates(
        connection.execute(sql, (value, *filter_parameters, depth)).fetchall(),
        "exact",
        f"{reference_kind}_match",
    )


def extract_structured_terms(query: str) -> tuple[str, ...]:
    """Extract conservative identifier-shaped terms without semantic guessing."""

    text = _require_text(query, "structured-term query")
    matches: list[tuple[int, str]] = []
    for pattern in STRUCTURED_TERM_PATTERNS:
        matches.extend((match.start(), match.group(0)) for match in pattern.finditer(text))
    ordered: list[str] = []
    seen: set[str] = set()
    for _, term in sorted(matches, key=lambda item: (item[0], item[1])):
        folded = term.casefold()
        if folded not in seen:
            seen.add(folded)
            ordered.append(term)
    return tuple(ordered)


def exact_term_lookup(
    connection: Any,
    term: str,
    *,
    depth: int = ACCEPTED_RETRIEVAL_PROFILE.exact_candidate_depth,
    filters: CandidateFilters = CandidateFilters(),
) -> tuple[LaneCandidate, ...]:
    """Resolve one extracted identifier exactly against active chunk content."""

    _require_depth(depth)
    value = _require_text(term, "exact structured term", maximum=256)
    if not any(pattern.fullmatch(value) for pattern in STRUCTURED_TERM_PATTERNS):
        raise RetrievalContractError("exact structured term has an unsupported shape")
    filter_sql, filter_parameters = _filter_sql("ac", filters)
    rows = connection.execute(
        f"""/* ishikawa.retrieval.exact.structured_term */
        SELECT ac.chunk_id, ac.document_id, ac.document_version_id, ac.document_key,
               1.0::float8 AS raw_score
        FROM rag_search.active_chunks ac
        WHERE position(lower(%s) in lower(ac.retrieval_text)) > 0{filter_sql}
        ORDER BY
          CASE WHEN lower(btrim(ac.retrieval_text)) = lower(%s) THEN 0 ELSE 1 END,
          ac.ordinal, ac.chunk_id
        LIMIT %s
        """,
        (value, *filter_parameters, value, depth),
    ).fetchall()
    return _rows_to_candidates(rows, "exact", "structured_term_match")


def extract_explicit_page(query: str) -> int | None:
    """Return one unambiguous explicit page number, otherwise no page route."""

    text = _require_text(query, "page-reference query")
    pages = {int(match.group(1)) for match in PAGE_REFERENCE.finditer(text)}
    return next(iter(pages)) if len(pages) == 1 else None


def exact_document_page_lookup(
    connection: Any,
    document_reference: str,
    page_number: int,
    *,
    depth: int = ACCEPTED_RETRIEVAL_PROFILE.exact_candidate_depth,
    filters: CandidateFilters = CandidateFilters(),
) -> tuple[LaneCandidate, ...]:
    """Resolve one primary document identifier plus page to citable evidence."""

    _require_depth(depth)
    reference = _require_text(document_reference, "document reference", maximum=256)
    if not any(pattern.fullmatch(reference) for pattern in STRUCTURED_TERM_PATTERNS):
        raise RetrievalContractError("document reference has an unsupported shape")
    if type(page_number) is not int or not 1 <= page_number <= 999999:
        raise RetrievalContractError("page number is outside the supported range")
    filter_sql, filter_parameters = _filter_sql("ac", filters)
    declaration_parameters = declared_identifier_parameters(reference)
    rows = connection.execute(
        f"""/* ishikawa.retrieval.exact.document_page */
        WITH declarations AS (
          SELECT citation.chunk_id,
                 lower(regexp_replace(
                   btrim(citation.relevant_excerpt), '[[:space:]]+', ' ', 'g'
                 )) AS declaration_text
          FROM rag_search.active_citations citation
        ), owner AS (
          SELECT DISTINCT ac.document_id
          FROM rag_search.active_chunks ac
          JOIN declarations declaration ON declaration.chunk_id = ac.chunk_id
          WHERE {DECLARED_IDENTIFIER_MATCH_SQL}{filter_sql}
        ), unique_owner AS (
          SELECT min(document_id) AS document_id
          FROM owner
          HAVING count(*) = 1
        )
        SELECT ac.chunk_id, ac.document_id, ac.document_version_id,
               ac.document_key, 1.0::float8 AS raw_score
        FROM rag_search.active_chunks ac
        JOIN rag_search.active_citations citation ON citation.chunk_id = ac.chunk_id
        JOIN unique_owner owner ON owner.document_id = ac.document_id
        WHERE citation.page_start <= %s AND citation.page_end >= %s{filter_sql}
        ORDER BY
          CASE WHEN ac.projection_kind = 'page_status' THEN 0 ELSE 1 END,
          ac.ordinal, ac.chunk_id
        LIMIT %s
        """,
        (
            *declaration_parameters,
            *filter_parameters,
            page_number,
            page_number,
            *filter_parameters,
            depth,
        ),
    ).fetchall()
    return _rows_to_candidates(rows, "exact", "document_page_match")


def lexical_search(
    connection: Any,
    query: str,
    *,
    depth: int = ACCEPTED_RETRIEVAL_PROFILE.lexical_candidate_depth,
    text_search_config: str = ACCEPTED_RETRIEVAL_PROFILE.lexical_search_config,
    filters: CandidateFilters = CandidateFilters(),
    use_candidate_representation: bool = False,
) -> tuple[LaneCandidate, ...]:
    """Run the native PostgreSQL full-text lane against active chunks."""

    _require_depth(depth)
    query = _require_text(query, "lexical query")
    if text_search_config != "english":
        raise RetrievalContractError("text search configuration is not accepted")
    if type(use_candidate_representation) is not bool:
        raise RetrievalContractError("candidate representation route is invalid")
    filter_sql, filter_parameters = _filter_sql("ac", filters)
    rows = connection.execute(
        f"""/* ishikawa.retrieval.lexical */
        WITH request AS (
          SELECT websearch_to_tsquery(%s::regconfig, %s) AS query
        )
        SELECT ac.chunk_id, ac.document_id, ac.document_version_id,
               ac.document_key,
               ts_rank_cd(ac.lexical_vector, request.query)::float8 AS raw_score,
               ac.retrieval_group_id, ac.authoritative_chunk_ids,
               ac.retrieval_scoring_only, ac.document_local_content_canonical,
               ac.structural_path
        FROM rag_search.active_retrieval_candidates ac
        CROSS JOIN request
        WHERE request.query <> ''::tsquery
          AND (NOT ac.retrieval_scoring_only OR %s)
          AND (NOT %s OR ac.retrieval_scoring_only OR ac.document_local_content_canonical)
          AND ac.lexical_vector @@ request.query{filter_sql}
        ORDER BY raw_score DESC, ac.chunk_id
        LIMIT %s
        """,
        (
            text_search_config,
            query,
            use_candidate_representation,
            use_candidate_representation,
            *filter_parameters,
            depth,
        ),
    ).fetchall()
    retrieval_variant = "strict"
    if not rows:
        retrieval_variant = "or_fallback"
        rows = connection.execute(
            f"""/* ishikawa.retrieval.lexical.or_fallback */
            WITH lexemes AS (
              SELECT string_agg(lexeme, ' OR ' ORDER BY lexeme) AS query_text
              FROM unnest(tsvector_to_array(to_tsvector(%s::regconfig, %s))) AS lexeme
            ), request AS (
              SELECT websearch_to_tsquery(
                %s::regconfig, COALESCE(query_text, '')
              ) AS query
              FROM lexemes
            )
            SELECT ac.chunk_id, ac.document_id, ac.document_version_id,
                   ac.document_key,
                   ts_rank_cd(ac.lexical_vector, request.query)::float8 AS raw_score,
                   ac.retrieval_group_id, ac.authoritative_chunk_ids,
                   ac.retrieval_scoring_only, ac.document_local_content_canonical,
                   ac.structural_path
            FROM rag_search.active_retrieval_candidates ac
            CROSS JOIN request
            WHERE request.query <> ''::tsquery
              AND (NOT ac.retrieval_scoring_only OR %s)
              AND (NOT %s OR ac.retrieval_scoring_only OR ac.document_local_content_canonical)
              AND ac.lexical_vector @@ request.query{filter_sql}
            ORDER BY raw_score DESC, ac.chunk_id
            LIMIT %s
            """,
            (
                text_search_config,
                query,
                text_search_config,
                use_candidate_representation,
                use_candidate_representation,
                *filter_parameters,
                depth,
            ),
        ).fetchall()
    return _rows_to_candidates(rows, "lexical", retrieval_variant=retrieval_variant)


def vector_search(
    connection: Any,
    query_embedding: Sequence[float],
    embedding_space_id: str,
    *,
    depth: int = ACCEPTED_RETRIEVAL_PROFILE.vector_candidate_depth,
    filters: CandidateFilters = CandidateFilters(),
    use_candidate_representation: bool = False,
) -> tuple[LaneCandidate, ...]:
    """Run exact pgvector cosine search in the single requested space."""

    _require_depth(depth)
    space = _require_text(embedding_space_id, "embedding space", maximum=64)
    if len(space) != 64 or any(character not in "0123456789abcdef" for character in space):
        raise RetrievalContractError("embedding space must be a SHA-256 identity")
    if len(query_embedding) != 768:
        raise RetrievalContractError("query embedding must contain 768 values")
    try:
        values = tuple(float(value) for value in query_embedding)
    except (TypeError, ValueError) as exc:
        raise RetrievalContractError("query embedding contains a non-numeric value") from exc
    if not all(math.isfinite(value) for value in values):
        raise RetrievalContractError("query embedding contains a non-finite value")
    if type(use_candidate_representation) is not bool:
        raise RetrievalContractError("candidate representation route is invalid")
    vector_literal = "[" + ",".join(format(value, ".17g") for value in values) + "]"
    filter_sql, filter_parameters = _filter_sql("ac", filters)
    rows = connection.execute(
        f"""/* ishikawa.retrieval.vector */
        SELECT ac.chunk_id, ac.document_id, ac.document_version_id,
               ac.document_key,
               (1.0 - (ae.embedding <=> %s::vector))::float8 AS raw_score,
               ac.retrieval_group_id, ac.authoritative_chunk_ids,
               ac.retrieval_scoring_only, ac.document_local_content_canonical,
               ac.structural_path
        FROM rag_search.active_retrieval_embeddings ae
        JOIN rag_search.active_retrieval_candidates ac ON ac.chunk_id = ae.chunk_id
        WHERE ae.embedding_space_id = %s
          AND (NOT ac.retrieval_scoring_only OR %s)
          AND (NOT %s OR ac.retrieval_scoring_only OR ac.document_local_content_canonical){filter_sql}
        ORDER BY ae.embedding <=> %s::vector, ac.chunk_id
        LIMIT %s
        """,
        (
            vector_literal,
            space,
            use_candidate_representation,
            use_candidate_representation,
            *filter_parameters,
            vector_literal,
            depth,
        ),
    ).fetchall()
    return _rows_to_candidates(rows, "vector")


def reciprocal_rank_fusion(
    candidates_by_lane: Mapping[str, Iterable[LaneCandidate]],
    *,
    rrf_constant: int = ACCEPTED_RETRIEVAL_PROFILE.rrf_constant,
    lane_weights: Mapping[str, int] | None = None,
) -> tuple[FusedCandidate, ...]:
    """Deduplicate by chunk identity and fuse weighted incomparable ranks."""

    if type(rrf_constant) is not int or not 1 <= rrf_constant <= 1000:
        raise RetrievalContractError("RRF constant must be between 1 and 1000")
    weights = (
        {
            "exact": ACCEPTED_RETRIEVAL_PROFILE.exact_weight,
            "lexical": ACCEPTED_RETRIEVAL_PROFILE.lexical_weight,
            "vector": ACCEPTED_RETRIEVAL_PROFILE.vector_weight,
        }
        if lane_weights is None
        else lane_weights
    )
    if (
        not isinstance(weights, Mapping)
        or set(weights) != set(LANES)
        or any(type(weight) is not int or not 1 <= weight <= 100 for weight in weights.values())
    ):
        raise RetrievalContractError("lane weights must provide bounded positive integers")
    unknown = set(candidates_by_lane) - set(LANES)
    if unknown:
        raise RetrievalContractError("fusion contains an unsupported lane")

    accumulated: dict[str, dict[str, Any]] = {}
    for lane in LANES:
        seen: set[str] = set()
        for candidate in candidates_by_lane.get(lane, ()):
            if candidate.lane != lane:
                raise RetrievalContractError("candidate is assigned to the wrong lane")
            if candidate.chunk_id in seen:
                raise RetrievalContractError("a lane returned a duplicate chunk")
            seen.add(candidate.chunk_id)
            state = accumulated.setdefault(
                candidate.chunk_id,
                {
                    "document_id": candidate.document_id,
                    "document_version_id": candidate.document_version_id,
                    "document_key": candidate.document_key,
                    "score": 0.0,
                    "evidence": [],
                    "retrieval_group_id": candidate.retrieval_group_id,
                    "authoritative_chunk_ids": candidate.authoritative_chunk_ids,
                    "retrieval_scoring_only": candidate.retrieval_scoring_only,
                    "structural_path": candidate.structural_path,
                },
            )
            identity = (state["document_id"], state["document_version_id"], state["document_key"])
            if identity != (candidate.document_id, candidate.document_version_id, candidate.document_key):
                raise RetrievalContractError("one chunk resolved to conflicting document identities")
            representation = (
                state["retrieval_group_id"],
                state["authoritative_chunk_ids"],
                state["retrieval_scoring_only"],
            )
            candidate_representation = (
                candidate.retrieval_group_id,
                candidate.authoritative_chunk_ids,
                candidate.retrieval_scoring_only,
            )
            if representation != candidate_representation:
                # Exact lookup reads authoritative active chunks. Lexical and
                # vector lookup read the richer candidate view, where the same
                # authoritative atom also carries its structural group id.
                # Those are compatible descriptions of one citable atom, not
                # a representation conflict. Preserve the richer group id so
                # later structural collapse remains deterministic.
                state_is_plain_atom = (
                    state["retrieval_group_id"] is None
                    and state["authoritative_chunk_ids"] == (candidate.chunk_id,)
                    and state["retrieval_scoring_only"] is False
                )
                candidate_is_plain_atom = (
                    candidate.retrieval_group_id is None
                    and candidate.authoritative_chunk_ids == (candidate.chunk_id,)
                    and candidate.retrieval_scoring_only is False
                )
                state_is_grouped_atom = (
                    state["retrieval_group_id"] is not None
                    and state["authoritative_chunk_ids"] == (candidate.chunk_id,)
                    and state["retrieval_scoring_only"] is False
                )
                candidate_is_grouped_atom = (
                    candidate.retrieval_group_id is not None
                    and candidate.authoritative_chunk_ids == (candidate.chunk_id,)
                    and candidate.retrieval_scoring_only is False
                )
                if state_is_plain_atom and candidate_is_grouped_atom:
                    state["retrieval_group_id"] = candidate.retrieval_group_id
                elif not (candidate_is_plain_atom and state_is_grouped_atom):
                    raise RetrievalContractError(
                        "one candidate resolved to conflicting representations"
                    )
            if state["structural_path"] and candidate.structural_path:
                if state["structural_path"] != candidate.structural_path:
                    raise RetrievalContractError(
                        "one candidate resolved to conflicting structural paths"
                    )
            elif candidate.structural_path:
                state["structural_path"] = candidate.structural_path
            # Weighting changes only the lane's RRF contribution. Exact-match
            # priority remains a separate deterministic sort boundary.
            state["score"] += weights[lane] / (rrf_constant + candidate.rank)
            state["evidence"].append(
                LaneEvidence(
                    lane,
                    candidate.rank,
                    candidate.raw_score,
                    candidate.exact_reason,
                    candidate.retrieval_variant,
                )
            )

    fused = [
        FusedCandidate(
            chunk_id=chunk_id,
            document_id=state["document_id"],
            document_version_id=state["document_version_id"],
            document_key=state["document_key"],
            fused_score=state["score"],
            exact_priority=any(item.lane == "exact" for item in state["evidence"]),
            evidence=tuple(state["evidence"]),
            retrieval_group_id=state["retrieval_group_id"],
            authoritative_chunk_ids=state["authoritative_chunk_ids"],
            retrieval_scoring_only=state["retrieval_scoring_only"],
            structural_path=state["structural_path"],
        )
        for chunk_id, state in accumulated.items()
    ]
    return tuple(
        sorted(
            fused,
            key=lambda item: (
                -int(item.exact_priority),
                -item.fused_score,
                min(evidence.rank for evidence in item.evidence),
                item.chunk_id,
            ),
        )
    )


def decomposed_candidate_pool(
    baseline: Sequence[FusedCandidate],
    facet_lanes: Sequence[Mapping[str, Sequence[LaneCandidate]]],
    *,
    rrf_constant: int,
    baseline_weight: int,
    best_facet_weight: int,
    facet_coverage_weight: int,
) -> tuple[FusedCandidate, ...]:
    """Expand a baseline with the best bounded literal-facet RRF signal."""

    if (
        not 1 <= len(facet_lanes) <= MAX_QUERY_FACETS
        or type(rrf_constant) is not int
        or not 1 <= rrf_constant <= 1000
        or baseline_weight != 2
        or best_facet_weight != 1
        or facet_coverage_weight != 1
    ):
        raise RetrievalContractError("decomposed candidate-pool settings are invalid")
    states: dict[str, dict[str, Any]] = {}
    for rank, candidate in enumerate(baseline, start=1):
        states[candidate.chunk_id] = {
            "candidate": candidate,
            "baseline_score": candidate.fused_score,
            "baseline_rank": rank,
            "facet_scores": {},
            "best_expansion_rank": 10**9,
        }
    for facet_index, lanes in enumerate(facet_lanes):
        if set(lanes) != {"lexical", "vector"}:
            raise RetrievalContractError("facet lane inventory is invalid")
        per_facet: dict[str, float] = {}
        for lane_name, lane_weight in (("lexical", 2), ("vector", 4)):
            seen: set[str] = set()
            for candidate in lanes[lane_name]:
                if candidate.lane != lane_name or candidate.chunk_id in seen:
                    raise RetrievalContractError("facet lane candidate is invalid")
                seen.add(candidate.chunk_id)
                state = states.setdefault(
                    candidate.chunk_id,
                    {
                        "candidate": FusedCandidate(
                            chunk_id=candidate.chunk_id,
                            document_id=candidate.document_id,
                            document_version_id=candidate.document_version_id,
                            document_key=candidate.document_key,
                            fused_score=0.0,
                            exact_priority=False,
                            evidence=(),
                            retrieval_group_id=candidate.retrieval_group_id,
                            authoritative_chunk_ids=candidate.authoritative_chunk_ids,
                            retrieval_scoring_only=candidate.retrieval_scoring_only,
                            structural_path=candidate.structural_path,
                        ),
                        "baseline_score": 0.0,
                        "baseline_rank": 10**9,
                        "facet_scores": {},
                        "best_expansion_rank": 10**9,
                    },
                )
                retained = state["candidate"]
                if (
                    retained.document_id,
                    retained.document_version_id,
                    retained.document_key,
                ) != (
                    candidate.document_id,
                    candidate.document_version_id,
                    candidate.document_key,
                ):
                    raise RetrievalContractError("facet candidate identity conflicts")
                contribution = lane_weight / (rrf_constant + candidate.rank)
                per_facet[candidate.chunk_id] = (
                    per_facet.get(candidate.chunk_id, 0.0) + contribution
                )
                state["best_expansion_rank"] = min(
                    state["best_expansion_rank"], candidate.rank
                )
        for chunk_id, score in per_facet.items():
            states[chunk_id]["facet_scores"][facet_index] = score

    result: list[FusedCandidate] = []
    facet_count = len(facet_lanes)
    for state in states.values():
        facet_scores = tuple(state["facet_scores"].values())
        best_facet = max(facet_scores, default=0.0)
        coverage = len(facet_scores) / ((rrf_constant + 1) * facet_count)
        candidate = state["candidate"]
        result.append(
            replace(
                candidate,
                fused_score=(
                    baseline_weight * state["baseline_score"]
                    + best_facet_weight * best_facet
                    + facet_coverage_weight * coverage
                ),
            )
        )
    return tuple(
        sorted(
            result,
            key=lambda item: (
                -int(item.exact_priority),
                -item.fused_score,
                states[item.chunk_id]["baseline_rank"],
                states[item.chunk_id]["best_expansion_rank"],
                item.chunk_id,
            ),
        )
    )


def _normalized(values: Mapping[str, float]) -> dict[str, float]:
    if not all(
        isinstance(key, str) and key and math.isfinite(float(value))
        for key, value in values.items()
    ):
        raise RetrievalContractError("reranking score normalization is invalid")
    if not values:
        return {}
    low = min(float(value) for value in values.values())
    high = max(float(value) for value in values.values())
    if high == low:
        return {key: 1.0 for key in values}
    return {
        key: (float(value) - low) / (high - low)
        for key, value in values.items()
    }


def _heading_overlap(query: str, structural_path: Sequence[str]) -> float:
    if not structural_path:
        return 0.0
    if any(not isinstance(item, str) or not item.strip() for item in structural_path):
        raise RetrievalContractError("reranking structural path is invalid")
    query_terms = {
        item for item in RERANK_WORD.findall(query.casefold())
        if len(item) > 1 and item not in RERANK_STOPWORDS
    }
    path_terms = {
        item for item in RERANK_WORD.findall(" ".join(structural_path).casefold())
        if len(item) > 1 and item not in RERANK_STOPWORDS
    }
    union = query_terms | path_terms
    return len(query_terms & path_terms) / len(union) if union else 0.0


def score_calibrated_global_rerank(
    pool: Sequence[FusedCandidate],
    primary_lexical: Sequence[LaneCandidate],
    primary_vector: Sequence[LaneCandidate],
    facet_lanes: Sequence[Mapping[str, Sequence[LaneCandidate]]],
    query: str,
) -> tuple[FusedCandidate, ...]:
    """Apply the qualified V13-46 raw-score calibration to one top-20 pool."""

    text = _require_text(query, "calibrated reranking query")
    if not pool or len(pool) > 20 or not 1 <= len(facet_lanes) <= MAX_QUERY_FACETS:
        raise RetrievalContractError("calibrated reranking candidate pool is invalid")
    pool_ids = {item.chunk_id for item in pool}
    if len(pool_ids) != len(pool):
        raise RetrievalContractError("calibrated reranking candidate pool is duplicated")

    baseline = _normalized({item.chunk_id: item.fused_score for item in pool})
    lexical = _normalized(
        {item.chunk_id: item.raw_score for item in primary_lexical if item.chunk_id in pool_ids}
    )
    vector = _normalized(
        {item.chunk_id: item.raw_score for item in primary_vector if item.chunk_id in pool_ids}
    )
    vector_coverage: dict[str, int] = {}
    for lanes in facet_lanes:
        if set(lanes) != {"lexical", "vector"}:
            raise RetrievalContractError("calibrated facet lane inventory is invalid")
        for item in lanes["vector"]:
            if item.chunk_id in pool_ids:
                vector_coverage[item.chunk_id] = vector_coverage.get(item.chunk_id, 0) + 1
    coverage = {
        chunk_id: count / len(facet_lanes)
        for chunk_id, count in vector_coverage.items()
    }
    document_scores: dict[str, float] = {}
    for item in primary_lexical:
        document_scores[item.document_key] = max(
            document_scores.get(item.document_key, -math.inf), item.raw_score
        )
    document_affinity = _normalized(document_scores)
    heading = _normalized(
        {item.chunk_id: _heading_overlap(text, item.structural_path) for item in pool}
    )
    source_rank = {item.chunk_id: rank for rank, item in enumerate(pool, start=1)}

    def score(item: FusedCandidate) -> float:
        return (
            lexical.get(item.chunk_id, 0.0)
            + 3.0 * vector.get(item.chunk_id, 0.0)
            + coverage.get(item.chunk_id, 0.0)
            + document_affinity.get(item.document_key, 0.0)
            + 0.10 * heading.get(item.chunk_id, 0.0)
        )

    ordered = sorted(
        pool,
        key=lambda item: (
            -score(item),
            -heading.get(item.chunk_id, 0.0),
            -baseline.get(item.chunk_id, 0.0),
            source_rank[item.chunk_id],
            item.chunk_id,
        ),
    )
    return tuple(replace(item, fused_score=score(item)) for item in ordered)


def collapse_retrieval_groups(
    candidates: Sequence[FusedCandidate],
) -> tuple[FusedCandidate, ...]:
    """Retain each highest-ranked group with its complete atomic envelope."""

    selected: list[FusedCandidate] = []
    seen: dict[str, tuple[tuple[str, str, str], int]] = {}
    for candidate in candidates:
        group = candidate.retrieval_group_id or candidate.chunk_id
        identity = (
            candidate.document_id,
            candidate.document_version_id,
            candidate.document_key,
        )
        existing = seen.get(group)
        if existing is not None and existing[0] != identity:
            raise RetrievalContractError(
                "one retrieval group resolved to conflicting document identities"
            )
        if existing is not None:
            selected_index = existing[1]
            retained = selected[selected_index]
            retained_ids = retained.authoritative_chunk_ids or (retained.chunk_id,)
            candidate_ids = candidate.authoritative_chunk_ids or (candidate.chunk_id,)
            if retained.retrieval_scoring_only and len(retained_ids) > 1:
                ordered_ids = retained_ids + tuple(
                    item for item in candidate_ids if item not in retained_ids
                )
            elif candidate.retrieval_scoring_only and len(candidate_ids) > 1:
                ordered_ids = candidate_ids + tuple(
                    item for item in retained_ids if item not in candidate_ids
                )
            else:
                ordered_ids = retained_ids + tuple(
                    item for item in candidate_ids if item not in retained_ids
                )
            selected[selected_index] = replace(
                retained,
                authoritative_chunk_ids=ordered_ids,
            )
            continue
        seen[group] = (identity, len(selected))
        selected.append(candidate)
    return tuple(selected)


def expand_authoritative_candidates(
    candidates: Sequence[FusedCandidate],
) -> tuple[FusedCandidate, ...]:
    """Replace retrieval-only representatives with ordered atomic evidence."""

    expanded: list[FusedCandidate] = []
    seen: set[str] = set()
    for candidate in candidates:
        authoritative = candidate.authoritative_chunk_ids or (candidate.chunk_id,)
        for chunk_id in authoritative:
            if chunk_id in seen:
                continue
            seen.add(chunk_id)
            expanded.append(
                FusedCandidate(
                    chunk_id=chunk_id,
                    document_id=candidate.document_id,
                    document_version_id=candidate.document_version_id,
                    document_key=candidate.document_key,
                    fused_score=candidate.fused_score,
                    exact_priority=candidate.exact_priority,
                    evidence=candidate.evidence,
                    retrieval_group_id=candidate.retrieval_group_id,
                    authoritative_chunk_ids=(chunk_id,),
                    retrieval_scoring_only=False,
                    structural_path=candidate.structural_path,
                )
            )
    return tuple(expanded)


def select_ranked_relevance_candidates(
    candidates: Sequence[FusedCandidate],
    *,
    depth: int,
) -> tuple[FusedCandidate, ...]:
    """Select the citable envelope from each ranked structural result.

    Retrieval-only section/page representatives may contain several atomic
    chunks. Expanding those chunks into the ranked list before taking the
    calibrated depth would let one structural result occupy all three result
    positions. Preserve three ranked structural results while carrying every
    citable atom in each result's authoritative envelope for measurement.
    """

    _require_depth(depth)
    selected: list[FusedCandidate] = []
    seen: set[str] = set()
    for candidate in candidates[:depth]:
        authoritative = candidate.authoritative_chunk_ids or (candidate.chunk_id,)
        chunk_id = authoritative[0]
        if chunk_id in seen:
            continue
        seen.add(chunk_id)
        selected.append(
            FusedCandidate(
                chunk_id=chunk_id,
                document_id=candidate.document_id,
                document_version_id=candidate.document_version_id,
                document_key=candidate.document_key,
                fused_score=candidate.fused_score,
                exact_priority=candidate.exact_priority,
                evidence=candidate.evidence,
                retrieval_group_id=candidate.retrieval_group_id,
                authoritative_chunk_ids=authoritative,
                retrieval_scoring_only=False,
            )
        )
    return tuple(selected)
