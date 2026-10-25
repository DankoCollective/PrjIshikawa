"""Deterministic routing for recognized document and department references.

The router verifies identifier, title, and department references against
read-only active PostgreSQL views before model scope.  Exact catalog intent is
preserved across bounded clarification turns; unrelated questions remain on
the existing Gemma scope-classification path.
"""

from __future__ import annotations

import re
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from typing import Any

from .api_contract import ApiChatRequest
from .canonical import domain_digest
from .document_control import DocumentControlError, normalize_department_value
from .retrieval import (
    DECLARED_IDENTIFIER_MATCH_SQL,
    declared_identifier_parameters,
    extract_structured_terms,
)
from .retrieval_service import (
    RetrievalDependencyUnavailable,
    RetrievalServiceContractError,
)
from .query_resolution import (
    QueryResolutionPolicy,
    ResolvedRetrievalQuery,
    ResolvedSourceConstraint,
)
from .scope import ScopeDecision


EXPECTED_RETRIEVAL_ROLE = "rag_retrieval"
_VAGUE_DOCUMENT = re.compile(
    r"^what\s+about\s+(?:the\s+)?(?P<subject>[^?!.]{2,512})[?!.]?$",
    re.IGNORECASE,
)
_DEPARTMENT_PROMPT = re.compile(r"\b(?:department|dept\.?)\b", re.IGNORECASE)
_DEPARTMENT_REPLY = re.compile(r"^(?:(?:department|dept\.?)\s*:\s*)?(.{1,128})$", re.IGNORECASE)
_DIRECT_DEPARTMENT = (
    re.compile(
        r"\b(?:started|work(?:ing)?|joined|serve|serving)\s+"
        r"(?:in|with|for)\s+(?:the\s+)?"
        r"(?P<department>[A-Za-z][A-Za-z0-9&'./ -]{0,63}?)\s+"
        r"(?:department|dept\.?)\b",
        re.IGNORECASE,
    ),
    re.compile(
        r"\b(?:department|dept\.?)\s*(?:of|:|-)\s*"
        r"(?P<department>[A-Za-z][A-Za-z0-9&'./ -]{0,63}?)"
        r"(?=\s*(?:[?,.;]|$|\b(?:and|but|can|could|do|does|what|which|who|how)\b))",
        re.IGNORECASE,
    ),
    re.compile(
        r"\b(?P<department>[A-Z][A-Za-z0-9'.-]*"
        r"(?:\s+(?:(?:and|&)\s+)?[A-Z][A-Za-z0-9'.-]*){0,3})\s+"
        r"(?:department|dept\.?)\b"
    ),
)
_CATALOG_REQUEST = re.compile(
    r"\b(?:all|every(?:thing)?|policies|procedures|documents|standards|guides|forms)\b"
    r"|\b(?:need|needs|needed)\s+to\s+(?:know|be\s+aware)\b",
    re.IGNORECASE,
)
_EXHAUSTIVE_REQUEST = re.compile(
    r"\b(?:all|every(?:thing)?|complete|entire)\b",
    re.IGNORECASE,
)
KNOWN_DOCUMENT_ROUTING_IDENTITY = domain_digest(
    "ishikawa.known-document-routing.v1.6",
    {
        "ambiguous_match": "clarify",
        "declared_identifier_source": (
            "trusted_document_control_metadata_then_active_citation_excerpt"
        ),
        "declared_identifier_forms": (
            "bare_identifier",
            "form_number",
            "policy_number",
        ),
        "explicit_identifier_before_model_scope": True,
        "explicit_page_before_model_scope": True,
        "explicit_unique_display_name_or_key": "constrain_retrieval",
        "relationship_expansion_for_vague_question": False,
        "vague_document_match": "unique_postgresql_english_lexeme_support",
        "unique_vague_document": "clarify",
        "direct_department_reference": (
            "resolve_exact_alias_or_unique_catalog_prefix_before_model_scope"
        ),
        "department_catalog_request": (
            "constrain_owned_and_directly_related_active_documents"
        ),
        "department_catalog_query": (
            "concise_semantic_query_with_membership_in_exact_constraints"
        ),
        "known_department_follow_up": (
            "preserve_clarification_chain_and_constrain_matching_documents"
        ),
        "department_authorization_effect": "none",
    },
)


@dataclass(frozen=True, slots=True)
class _ActiveDocument:
    document_id: str
    document_version_id: str
    document_key: str
    display_name: str

    @classmethod
    def from_row(cls, row: Sequence[Any]) -> _ActiveDocument:
        if (
            not isinstance(row, Sequence)
            or isinstance(row, (str, bytes))
            or len(row) != 4
            or any(not isinstance(value, str) or not value.strip() for value in row)
        ):
            raise RetrievalServiceContractError("known-document row is invalid")
        return cls(*row)


@dataclass(frozen=True, slots=True)
class _DepartmentDocument:
    document: _ActiveDocument
    department: str
    routing_citation_id: str

    @classmethod
    def from_row(cls, row: Sequence[Any]) -> _DepartmentDocument:
        if (
            not isinstance(row, Sequence)
            or isinstance(row, (str, bytes))
            or len(row) != 6
            or any(not isinstance(value, str) or not value.strip() for value in row)
        ):
            raise RetrievalServiceContractError("known-department row is invalid")
        return cls(_ActiveDocument.from_row(row[:4]), row[4], row[5])


@dataclass(frozen=True, slots=True)
class _CatalogDocument:
    document: _ActiveDocument
    routing_citation_id: str

    @classmethod
    def from_row(cls, row: Sequence[Any]) -> _CatalogDocument:
        if (
            not isinstance(row, Sequence)
            or isinstance(row, (str, bytes))
            or len(row) != 5
            or any(not isinstance(value, str) or not value.strip() for value in row)
        ):
            raise RetrievalServiceContractError("known-department catalog row is invalid")
        return cls(_ActiveDocument.from_row(row[:4]), row[4])


@dataclass(frozen=True, slots=True)
class _DepartmentRequest:
    original_request: str
    department_reference: str
    user_details: tuple[str, ...]
    catalog_requested: bool


def vague_document_subject(question: str) -> str | None:
    """Return the subject of one deliberately narrow vague-document form."""

    if not isinstance(question, str) or not question.strip() or question != question.strip():
        raise RetrievalServiceContractError("known-document question is invalid")
    match = _VAGUE_DOCUMENT.fullmatch(question)
    if match is None:
        return None
    subject = " ".join(match.group("subject").split())
    return subject if subject else None


def direct_department_reference(question: str) -> str | None:
    """Return one explicit department phrase from a complete user question."""

    if not isinstance(question, str) or not question.strip() or question != question.strip():
        raise RetrievalServiceContractError("known-department question is invalid")
    for pattern in _DIRECT_DEPARTMENT:
        match = pattern.search(question)
        if match is None:
            continue
        reference = " ".join(match.group("department").split()).strip(" .,-")
        if reference:
            try:
                normalize_department_value(reference)
            except DocumentControlError:
                return None
            return reference
    return None


def _department_request(request: ApiChatRequest) -> _DepartmentRequest | None:
    """Preserve one department-scoped task across consecutive clarifications."""

    direct = direct_department_reference(request.message)
    if direct is not None:
        return _DepartmentRequest(
            request.message,
            direct,
            (request.message,),
            bool(_CATALOG_REQUEST.search(request.message)),
        )
    if not request.history:
        return None

    # Carry department intent only through an uninterrupted clarification chain.
    # A prior declarative answer ends the chain and cannot silently constrain a
    # later question.
    collected_users: list[str] = [request.message]
    catalog_requested = bool(_EXHAUSTIVE_REQUEST.search(request.message))
    for turn in reversed(request.history):
        if turn.role == "assistant":
            if "?" not in turn.content:
                return None
            continue
        collected_users.append(turn.content)
        catalog_requested = catalog_requested or bool(
            _CATALOG_REQUEST.search(turn.content)
            or _EXHAUSTIVE_REQUEST.search(turn.content)
        )
        reference = direct_department_reference(turn.content)
        if reference is not None:
            details = tuple(reversed(collected_users))
            return _DepartmentRequest(
                turn.content,
                reference,
                details,
                catalog_requested,
            )
    return None


def department_follow_up(request: ApiChatRequest) -> tuple[str, str] | None:
    """Return prior question and exact department reply for one clarification turn."""

    if not isinstance(request, ApiChatRequest) or len(request.history) < 2:
        return None
    # A recognized document identifier always belongs to document routing.
    # It must not be reinterpreted as a free-form department reply merely
    # because a previous answer happened to mention the word "department".
    if extract_structured_terms(request.message):
        return None
    prior_user = request.history[-2]
    prior_assistant = request.history[-1]
    if (
        prior_user.role != "user"
        or prior_assistant.role != "assistant"
        or not prior_assistant.content.rstrip().endswith("?")
        or _DEPARTMENT_PROMPT.search(prior_assistant.content) is None
    ):
        return None
    match = _DEPARTMENT_REPLY.fullmatch(request.message)
    if match is None:
        return None
    reply = " ".join(match.group(1).split())
    try:
        normalize_department_value(reply)
    except DocumentControlError:
        return None
    return prior_user.content, reply


def _clarification(subject: str, *, ambiguous: bool) -> str:
    if ambiguous:
        return f"Which document do you mean by {subject}?"
    return f"What would you like to know about {subject}?"


def _departments_are_ambiguous(documents: Sequence[_DepartmentDocument]) -> bool:
    return len({normalize_department_value(item.department) for item in documents}) > 1


@dataclass(frozen=True, slots=True)
class NativeKnownDocumentScopeRouter:
    """Resolve only known active-document references before model scope."""

    connection_factory: Callable[[], Any]
    expected_database_role: str = EXPECTED_RETRIEVAL_ROLE

    def __post_init__(self) -> None:
        if not callable(self.connection_factory) or self.expected_database_role != EXPECTED_RETRIEVAL_ROLE:
            raise RetrievalServiceContractError("known-document router dependency is invalid")

    def _query(
        self,
        connection: Any,
        request: ApiChatRequest,
        *,
        structured_term: str | None,
        vague_subject: str | None,
        explicit_question: str | None,
    ) -> tuple[_ActiveDocument, ...]:
        if sum(
            value is not None
            for value in (structured_term, vague_subject, explicit_question)
        ) != 1:
            raise RetrievalServiceContractError("known-document lookup kind is invalid")
        if structured_term is not None:
            declaration_parameters = declared_identifier_parameters(structured_term)
            normalized_identifier = " ".join(structured_term.split())
            rows = connection.execute(
                f"""/* ishikawa.known-document.structured-identifier */
                WITH declarations AS (
                  SELECT citation.chunk_id,
                         lower(regexp_replace(
                           btrim(citation.relevant_excerpt),
                           '[[:space:]]+', ' ', 'g'
                         )) AS declaration_text
                  FROM rag_search.active_citations citation
                )
                SELECT DISTINCT ac.document_id, ac.document_version_id,
                       ac.document_key, ac.display_name
                FROM rag_search.active_chunks ac
                LEFT JOIN declarations declaration ON declaration.chunk_id = ac.chunk_id
                WHERE (
                    lower(regexp_replace(
                        btrim(COALESCE(
                            ac.retrieval_filters #>> '{{document_control,policy_number}}',
                            ''
                        )),
                        '[[:space:]]+', ' ', 'g'
                    )) = lower(%s)
                    OR {DECLARED_IDENTIFIER_MATCH_SQL}
                  )
                  AND (cardinality(%s::text[]) = 0 OR ac.class_id = ANY(%s::text[]))
                  AND (cardinality(%s::text[]) = 0 OR ac.document_key = ANY(%s::text[]))
                ORDER BY ac.document_id, ac.document_version_id
                LIMIT 3
                """,
                (
                    normalized_identifier,
                    *declaration_parameters,
                    list(request.filters.document_classes),
                    list(request.filters.document_classes),
                    list(request.filters.document_keys),
                    list(request.filters.document_keys),
                ),
            ).fetchall()
        elif vague_subject is not None:
            rows = connection.execute(
                """/* ishikawa.known-document.vague-subject */
                SELECT DISTINCT ad.document_id, ad.document_version_id,
                       ad.document_key, ad.display_name
                FROM rag_search.active_documents ad
                WHERE (
                    lower(ad.display_name) = lower(%s)
                    OR to_tsvector('english', ad.display_name)
                       @@ websearch_to_tsquery('english', %s)
                    OR EXISTS (
                        SELECT 1
                        FROM rag_search.active_chunks ac
                        WHERE ac.document_version_id = ad.document_version_id
                          AND ac.lexical_vector
                              @@ websearch_to_tsquery('english', %s)
                    )
                  )
                  AND (cardinality(%s::text[]) = 0 OR ad.class_id = ANY(%s::text[]))
                  AND (cardinality(%s::text[]) = 0 OR ad.document_key = ANY(%s::text[]))
                ORDER BY ad.document_id, ad.document_version_id
                LIMIT 3
                """,
                (
                    vague_subject,
                    vague_subject,
                    vague_subject,
                    list(request.filters.document_classes),
                    list(request.filters.document_classes),
                    list(request.filters.document_keys),
                    list(request.filters.document_keys),
                ),
            ).fetchall()
        else:
            rows = connection.execute(
                """/* ishikawa.known-document.explicit-name-or-key */
                SELECT ad.document_id, ad.document_version_id,
                       ad.document_key, ad.display_name
                FROM rag_search.active_documents ad
                WHERE (
                    position(lower(ad.display_name) in lower(%s)) > 0
                    OR position(lower(ad.document_key) in lower(%s)) > 0
                  )
                  AND (cardinality(%s::text[]) = 0 OR ad.class_id = ANY(%s::text[]))
                  AND (cardinality(%s::text[]) = 0 OR ad.document_key = ANY(%s::text[]))
                ORDER BY length(ad.display_name) DESC,
                         ad.document_id, ad.document_version_id
                LIMIT 3
                """,
                (
                    explicit_question,
                    explicit_question,
                    list(request.filters.document_classes),
                    list(request.filters.document_classes),
                    list(request.filters.document_keys),
                    list(request.filters.document_keys),
                ),
            ).fetchall()
        if not isinstance(rows, Sequence) or isinstance(rows, (str, bytes)):
            raise RetrievalServiceContractError("known-document rows are invalid")
        documents = tuple(_ActiveDocument.from_row(row) for row in rows)
        identities = {(item.document_id, item.document_version_id) for item in documents}
        if len(identities) != len(documents):
            raise RetrievalServiceContractError("known-document rows are duplicated")
        return documents

    def _query_department(
        self,
        connection: Any,
        request: ApiChatRequest,
        reply: str,
    ) -> tuple[_DepartmentDocument, ...]:
        normalized = normalize_department_value(reply)
        rows = connection.execute(
            """/* ishikawa.known-document.department-match */
            SELECT DISTINCT ac.document_id, ac.document_version_id,
                   ac.document_key, ac.display_name,
                   ac.retrieval_filters #>> '{document_control,department}' AS department,
                   routing.citation_id
            FROM rag_search.active_chunks ac
            JOIN LATERAL (
                SELECT citation.citation_id
                FROM rag_search.active_citations citation
                WHERE citation.document_version_id = ac.document_version_id
                ORDER BY
                    CASE
                        WHEN lower(citation.structural_path ->> 0) LIKE '%%purpose%%'
                        THEN 0 ELSE 1
                    END,
                    CASE
                        WHEN lower(citation.relevant_excerpt)
                             ~ '(^|[^a-z])governs?([^a-z]|$)'
                        THEN 0 ELSE 1
                    END,
                    citation.page_start,
                    citation.citation_id
                LIMIT 1
            ) routing ON true
            WHERE (
                ac.retrieval_filters #>> '{document_control,department_normalized}' = %s
                OR ac.retrieval_filters #>> '{document_control,department_normalized}'
                   LIKE %s
                OR EXISTS (
                    SELECT 1
                    FROM jsonb_array_elements_text(
                        COALESCE(
                            ac.retrieval_filters #> '{document_control,department_aliases}',
                            '[]'::jsonb
                        )
                    ) AS alias(value)
                    WHERE lower(btrim(alias.value)) = lower(%s)
                )
              )
              AND (cardinality(%s::text[]) = 0 OR ac.class_id = ANY(%s::text[]))
              AND (cardinality(%s::text[]) = 0 OR ac.document_key = ANY(%s::text[]))
            ORDER BY ac.document_id, ac.document_version_id
            LIMIT 21
            """,
            (
                normalized,
                normalized + " %",
                reply,
                list(request.filters.document_classes),
                list(request.filters.document_classes),
                list(request.filters.document_keys),
                list(request.filters.document_keys),
            ),
        ).fetchall()
        if not isinstance(rows, Sequence) or isinstance(rows, (str, bytes)):
            raise RetrievalServiceContractError("known-department rows are invalid")
        documents = tuple(_DepartmentDocument.from_row(row) for row in rows)
        identities = {
            (item.document.document_id, item.document.document_version_id)
            for item in documents
        }
        if len(identities) != len(documents):
            raise RetrievalServiceContractError("known-department rows are duplicated")
        return documents

    def _query_related_documents(
        self,
        connection: Any,
        request: ApiChatRequest,
        department_documents: Sequence[_DepartmentDocument],
    ) -> tuple[_CatalogDocument, ...]:
        """Return unique active one-hop targets for an exhaustive catalog request."""

        source_document_ids = tuple(
            dict.fromkeys(item.document.document_id for item in department_documents)
        )
        if not source_document_ids:
            return ()
        rows = connection.execute(
            """/* ishikawa.known-document.department-related */
            SELECT DISTINCT target.document_id, target.document_version_id,
                   target.document_key, target.display_name, routing.citation_id
            FROM rag_search.active_relationships relationship
            JOIN rag_search.active_documents target
              ON target.document_id = relationship.target_identity
            JOIN LATERAL (
                SELECT citation.citation_id
                FROM rag_search.active_citations citation
                WHERE citation.document_version_id = target.document_version_id
                ORDER BY
                    CASE
                        WHEN lower(citation.structural_path ->> 0) LIKE '%%purpose%%'
                        THEN 0 ELSE 1
                    END,
                    CASE
                        WHEN lower(citation.relevant_excerpt)
                             ~ '(^|[^a-z])governs?([^a-z]|$)'
                        THEN 0 ELSE 1
                    END,
                    citation.page_start,
                    citation.citation_id
                LIMIT 1
            ) routing ON true
            WHERE relationship.source_document_id = ANY(%s::text[])
              AND relationship.relationship_type = 'explicit_reference.document'
              AND relationship.influences_retrieval = true
              AND (cardinality(%s::text[]) = 0 OR target.class_id = ANY(%s::text[]))
              AND (cardinality(%s::text[]) = 0 OR target.document_key = ANY(%s::text[]))
            ORDER BY target.document_id, target.document_version_id
            LIMIT 21
            """,
            (
                list(source_document_ids),
                list(request.filters.document_classes),
                list(request.filters.document_classes),
                list(request.filters.document_keys),
                list(request.filters.document_keys),
            ),
        ).fetchall()
        if not isinstance(rows, Sequence) or isinstance(rows, (str, bytes)):
            raise RetrievalServiceContractError("known-department relationship rows are invalid")
        direct_versions = {
            item.document.document_version_id for item in department_documents
        }
        related = tuple(
            item
            for item in (_CatalogDocument.from_row(row) for row in rows)
            if item.document.document_version_id not in direct_versions
        )
        identities = {
            (item.document.document_id, item.document.document_version_id)
            for item in related
        }
        if len(identities) != len(related):
            raise RetrievalServiceContractError(
                "known-department relationship rows are duplicated"
            )
        return related

    def _department_route_documents(
        self,
        connection: Any,
        request: ApiChatRequest,
        department_request: _DepartmentRequest,
    ) -> tuple[tuple[_DepartmentDocument, ...], tuple[_CatalogDocument, ...]]:
        direct = self._query_department(
            connection, request, department_request.department_reference
        )
        related = (
            self._query_related_documents(connection, request, direct)
            if (
                direct
                and not _departments_are_ambiguous(direct)
                and department_request.catalog_requested
            )
            else ()
        )
        return direct, related

    def __call__(self, request: ApiChatRequest) -> ScopeDecision | None:
        if not isinstance(request, ApiChatRequest):
            raise RetrievalServiceContractError("known-document router input is invalid")
        terms = extract_structured_terms(request.message)
        subject = vague_document_subject(request.message)
        # Explicit document identifiers outrank conversational department
        # carry-over. This keeps a cited identifier deterministic even when a
        # prior answer contains department-related prose.
        department_request = None if terms else _department_request(request)
        department_reply = None if terms else department_follow_up(request)
        if len(terms) > 1:
            return None

        connection = None
        try:
            connection = self.connection_factory()
            connection.execute(
                """/* ishikawa.known-document.begin */
                BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY
                """
            )
            boundary = connection.execute(
                """/* ishikawa.known-document.boundary */
                SELECT current_user,
                       current_setting('transaction_read_only'),
                       current_setting('transaction_isolation')
                """
            ).fetchone()
            if boundary != (self.expected_database_role, "on", "repeatable read"):
                raise RetrievalServiceContractError(
                    "known-document database boundary is invalid"
                )
            if department_request is not None:
                department_documents, related_documents = (
                    self._department_route_documents(
                        connection, request, department_request
                    )
                )
                if not department_documents:
                    return None
                if _departments_are_ambiguous(department_documents):
                    return ScopeDecision(
                        "needs_clarification",
                        "ambiguous_known_department",
                        "Which department do you mean by "
                        f"{department_request.department_reference}?",
                    )
                if len(department_documents) + len(related_documents) > 20:
                    return ScopeDecision(
                        "needs_clarification",
                        "department_document_limit",
                        "Which area or document type should be included for that department?",
                    )
                return ScopeDecision(
                    "allow",
                    (
                        "known_department_catalog"
                        if department_request.catalog_requested
                        else "known_department_reference"
                    ),
                    None,
                )
            if department_reply is not None:
                department_documents = self._query_department(
                    connection, request, department_reply[1]
                )
                if not department_documents:
                    return None
                if _departments_are_ambiguous(department_documents):
                    return ScopeDecision(
                        "needs_clarification",
                        "ambiguous_known_department",
                        f"Which department do you mean by {department_reply[1]}?",
                    )
                if len(department_documents) > 20:
                    return ScopeDecision(
                        "needs_clarification",
                        "department_document_limit",
                        "Which policy or procedure should be used for that department?",
                    )
                return ScopeDecision("allow", "known_department_follow_up", None)
            documents = self._query(
                connection,
                request,
                structured_term=(terms[0] if len(terms) == 1 else None),
                vague_subject=(None if len(terms) == 1 else subject),
                explicit_question=(
                    request.message
                    if len(terms) == 0 and subject is None
                    else None
                ),
            )
            if not documents:
                return None
            label = (
                terms[0]
                if len(terms) == 1
                else subject or documents[0].display_name
            )
            if label is None:
                raise RetrievalServiceContractError("known-document label is invalid")
            if len(documents) != 1:
                return ScopeDecision(
                    "needs_clarification",
                    "ambiguous_known_document",
                    _clarification(label, ambiguous=True),
                )
            if subject is not None:
                return ScopeDecision(
                    "needs_clarification",
                    "vague_known_document",
                    _clarification(subject, ambiguous=False),
                )
            return ScopeDecision("allow", "known_document_reference", None)
        except (RetrievalDependencyUnavailable, RetrievalServiceContractError):
            raise
        except Exception as error:
            raise RetrievalDependencyUnavailable(
                "known_document_lookup_failed"
            ) from error
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

    def resolve_query(
        self,
        request: ApiChatRequest,
        policy: QueryResolutionPolicy,
    ) -> ResolvedRetrievalQuery | None:
        """Constrain one explicit active-document reference before model resolution."""

        if not isinstance(request, ApiChatRequest) or not isinstance(
            policy, QueryResolutionPolicy
        ):
            raise RetrievalServiceContractError("known-document resolution input is invalid")
        terms = extract_structured_terms(request.message)
        subject = vague_document_subject(request.message)
        department_request = None if terms else _department_request(request)
        department_reply = None if terms else department_follow_up(request)
        if len(terms) > 1 or subject is not None:
            return None

        connection = None
        try:
            connection = self.connection_factory()
            connection.execute(
                """/* ishikawa.known-document-resolution.begin */
                BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY
                """
            )
            boundary = connection.execute(
                """/* ishikawa.known-document-resolution.boundary */
                SELECT current_user,
                       current_setting('transaction_read_only'),
                       current_setting('transaction_isolation')
                """
            ).fetchone()
            if boundary != (self.expected_database_role, "on", "repeatable read"):
                raise RetrievalServiceContractError(
                    "known-document database boundary is invalid"
                )
            if department_request is not None:
                department_documents, related_documents = (
                    self._department_route_documents(
                        connection, request, department_request
                    )
                )
                if not department_documents:
                    return None
                if _departments_are_ambiguous(department_documents):
                    clarification = (
                        "Which department do you mean by "
                        f"{department_request.department_reference}?"
                    )
                    reason = "ambiguous_known_department"
                    identity = domain_digest(
                        "ishikawa.query-resolution.v1",
                        {
                            "clarification": clarification,
                            "filters": request.filters.canonical(),
                            "original_query": request.message,
                            "reason": reason,
                            "status": "needs_clarification",
                        },
                    )
                    return ResolvedRetrievalQuery(
                        "needs_clarification", request.message, None, (),
                        request.filters, clarification, policy.digest, identity, False,
                    )
                selected_documents = tuple(
                    _CatalogDocument(item.document, item.routing_citation_id)
                    for item in department_documents
                ) + related_documents
                if len(selected_documents) > policy.maximum_source_references:
                    clarification = (
                        "Which area or document type should be included for that department?"
                    )
                    reason = "department_document_limit"
                    identity = domain_digest(
                        "ishikawa.query-resolution.v1",
                        {
                            "clarification": clarification,
                            "filters": request.filters.canonical(),
                            "original_query": request.message,
                            "reason": reason,
                            "status": "needs_clarification",
                        },
                    )
                    return ResolvedRetrievalQuery(
                        "needs_clarification", request.message, None, (),
                        request.filters, clarification, policy.digest, identity, False,
                    )
                department = department_documents[0].department
                if department_request.catalog_requested:
                    # The exact source constraints below are the authoritative
                    # exhaustive catalog.  Do not repeat every display name or
                    # clarification turn in the semantic query: those trusted
                    # obligations are still mandatory, while copying them into
                    # the question dilutes the frozen citable-relevance
                    # measurement with router-generated lexemes.  The original
                    # conversation remains available to generation, including
                    # any operator-supplied topic details.
                    resolved_query = (
                        f"Which documents govern {department} and authorized "
                        "supporting roles, with related documents?"
                    )
                    reason = "known_department_catalog"
                else:
                    details = " ".join(
                        dict.fromkeys(department_request.user_details)
                    )
                    resolved_query = f"{details} Department: {department}."
                    reason = "known_department_reference"
                constraints = tuple(
                    ResolvedSourceConstraint(
                        document.document.document_version_id,
                        f"Source {index}",
                        document.document.display_name,
                        document.routing_citation_id,
                    )
                    for index, document in enumerate(selected_documents, start=1)
                )
                identity = domain_digest(
                    "ishikawa.query-resolution.v1",
                    {
                        "filters": request.filters.canonical(),
                        "original_query": request.message,
                        "reason": reason,
                        "resolved_query": resolved_query,
                        "source_constraints": [
                            item.canonical() for item in constraints
                        ],
                        "status": "resolved",
                    },
                )
                return ResolvedRetrievalQuery(
                    "resolved", request.message, resolved_query, constraints,
                    request.filters, None, policy.digest, identity, False,
                )
            if department_reply is not None:
                department_documents = self._query_department(
                    connection, request, department_reply[1]
                )
                if not department_documents:
                    return None
                if _departments_are_ambiguous(department_documents):
                    clarification = f"Which department do you mean by {department_reply[1]}?"
                    identity = domain_digest(
                        "ishikawa.query-resolution.v1",
                        {
                            "clarification": clarification,
                            "filters": request.filters.canonical(),
                            "original_query": request.message,
                            "reason": "ambiguous_known_department",
                            "status": "needs_clarification",
                        },
                    )
                    return ResolvedRetrievalQuery(
                        "needs_clarification", request.message, None, (), request.filters,
                        clarification, policy.digest, identity, False,
                    )
                if len(department_documents) > policy.maximum_source_references:
                    clarification = "Which policy or procedure should be used for that department?"
                    identity = domain_digest(
                        "ishikawa.query-resolution.v1",
                        {
                            "clarification": clarification,
                            "filters": request.filters.canonical(),
                            "original_query": request.message,
                            "reason": "department_document_limit",
                            "status": "needs_clarification",
                        },
                    )
                    return ResolvedRetrievalQuery(
                        "needs_clarification", request.message, None, (), request.filters,
                        clarification, policy.digest, identity, False,
                    )
                resolved_query = (
                    f"{department_reply[0]} Department: "
                    f"{department_documents[0].department}."
                )
                constraints = tuple(
                    ResolvedSourceConstraint(
                        item.document.document_version_id,
                        f"Source {index}",
                        item.document.display_name,
                        item.routing_citation_id,
                    )
                    for index, item in enumerate(department_documents, start=1)
                )
                identity = domain_digest(
                    "ishikawa.query-resolution.v1",
                    {
                        "filters": request.filters.canonical(),
                        "original_query": request.message,
                        "reason": "known_department_follow_up",
                        "resolved_query": resolved_query,
                        "source_constraints": [item.canonical() for item in constraints],
                        "status": "resolved",
                    },
                )
                return ResolvedRetrievalQuery(
                    "resolved", request.message, resolved_query, constraints,
                    request.filters, None, policy.digest, identity, False,
                )
            documents = self._query(
                connection,
                request,
                structured_term=(terms[0] if len(terms) == 1 else None),
                vague_subject=None,
                explicit_question=(request.message if not terms else None),
            )
            if not documents:
                return None
            reason = "explicit_document_reference"
            if len(documents) != 1:
                label = terms[0] if terms else "that document reference"
                clarification = _clarification(label, ambiguous=True)
                identity = domain_digest(
                    "ishikawa.query-resolution.v1",
                    {
                        "clarification": clarification,
                        "filters": request.filters.canonical(),
                        "original_query": request.message,
                        "reason": reason,
                        "status": "needs_clarification",
                    },
                )
                return ResolvedRetrievalQuery(
                    "needs_clarification", request.message, None, (), request.filters,
                    clarification, policy.digest, identity, False,
                )
            document = documents[0]
            constraint = ResolvedSourceConstraint(
                document.document_version_id,
                "Source 1",
                document.display_name,
                None,
            )
            identity = domain_digest(
                "ishikawa.query-resolution.v1",
                {
                    "filters": request.filters.canonical(),
                    "original_query": request.message,
                    "reason": reason,
                    "resolved_query": request.message,
                    "source_constraints": [constraint.canonical()],
                    "status": "resolved",
                },
            )
            return ResolvedRetrievalQuery(
                "resolved", request.message, request.message, (constraint,),
                request.filters, None, policy.digest, identity, False,
            )
        except (RetrievalDependencyUnavailable, RetrievalServiceContractError):
            raise
        except Exception as error:
            raise RetrievalDependencyUnavailable(
                "known_document_lookup_failed"
            ) from error
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
