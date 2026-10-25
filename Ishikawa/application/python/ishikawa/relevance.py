"""Frozen deterministic citable-evidence relevance decision.

The database performs only PostgreSQL ``english`` lexeme measurement. This
module owns the calibrated decision and its versioned profile identity. It
does not change retrieval rank and gives no model authority over sufficiency.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any, Mapping, Sequence

from .canonical import domain_digest
from .retrieval import FusedCandidate


EVIDENCE_FIELDS = (
    "chunk_retrieval_text",
    "document_display_name",
    "assigned_class",
    "citation_structural_path",
    "citation_page",
)
QUALIFIED = "qualified"
INSUFFICIENT = "insufficient"
HEX_IDENTITY = re.compile(r"^[0-9a-f]{64}$")


class RelevanceContractError(ValueError):
    """Raised when the frozen relevance contract is violated."""


@dataclass(frozen=True, slots=True)
class RelevancePolicy:
    digest: str
    fused_depth: int
    minimum_supported_numerator: int
    minimum_supported_denominator: int


@dataclass(frozen=True, slots=True)
class RelevanceMeasurement:
    question_lexemes: tuple[str, ...]
    supported_lexemes: tuple[str, ...]
    unsupported_lexemes: tuple[str, ...]
    fused_chunk_count: int

    def __post_init__(self) -> None:
        inventories = (
            self.question_lexemes,
            self.supported_lexemes,
            self.unsupported_lexemes,
        )
        if any(
            not isinstance(values, tuple)
            or values != tuple(sorted(set(values)))
            or any(not isinstance(item, str) or not item or item != item.strip() for item in values)
            for values in inventories
        ):
            raise RelevanceContractError("relevance lexeme inventory is invalid")
        if not self.question_lexemes:
            raise RelevanceContractError("question produced no measurable lexemes")
        question = set(self.question_lexemes)
        supported = set(self.supported_lexemes)
        unsupported = set(self.unsupported_lexemes)
        if supported & unsupported or supported | unsupported != question:
            raise RelevanceContractError("support lexemes do not partition the question")
        if type(self.fused_chunk_count) is not int or not 0 <= self.fused_chunk_count <= 3:
            raise RelevanceContractError("measured fused chunk count is invalid")


@dataclass(frozen=True, slots=True)
class RelevanceDecision:
    status: str
    reason_code: str
    profile_identity: str
    fused_depth: int
    fused_chunk_count: int
    supported_count: int
    question_lexeme_count: int

    def __post_init__(self) -> None:
        if self.status not in (QUALIFIED, INSUFFICIENT):
            raise RelevanceContractError("relevance decision status is invalid")
        expected_reason = (
            "CITABLE_EVIDENCE_SUPPORT_QUALIFIED"
            if self.status == QUALIFIED
            else "CITABLE_EVIDENCE_SUPPORT_INSUFFICIENT"
        )
        if self.reason_code != expected_reason:
            raise RelevanceContractError("relevance decision reason is invalid")
        if (
            not isinstance(self.profile_identity, str)
            or HEX_IDENTITY.fullmatch(self.profile_identity) is None
        ):
            raise RelevanceContractError("relevance profile identity is invalid")
        if self.fused_depth != 3 or not 0 <= self.fused_chunk_count <= self.fused_depth:
            raise RelevanceContractError("relevance decision depth is invalid")
        if (
            type(self.supported_count) is not int
            or type(self.question_lexeme_count) is not int
            or not 0 <= self.supported_count <= self.question_lexeme_count
            or self.question_lexeme_count < 1
        ):
            raise RelevanceContractError("relevance decision counts are invalid")


@dataclass(frozen=True, slots=True)
class ResponseEnvelopePlan:
    """Post-retrieval ordering and relevance decision for ordinary body queries.

    Each measured envelope represents one retrieved document.  It contains the
    document's most query-responsive structural result and, when it adds
    question coverage, one complementary structural result from that same
    document.  The complementary result may be the authoritative Purpose/Scope
    unit, but a more responsive operational section takes precedence.  The
    The rank-one V13-47 document remains the anchor.  Coverage chooses the
    structural results inside every document and orders only the remaining
    documents.  The plan changes neither the retrieval lanes nor their frozen
    V13-47 scores.
    """

    relevance_candidates: tuple[FusedCandidate, ...]
    ordered_candidates: tuple[FusedCandidate, ...]
    selected_group_order: tuple[str, ...]
    decision: RelevanceDecision

    def __post_init__(self) -> None:
        if not self.relevance_candidates or len(self.relevance_candidates) > 3:
            raise RelevanceContractError("response-envelope relevance depth is invalid")
        if not self.ordered_candidates:
            raise RelevanceContractError("response-envelope candidate order is empty")
        if any(
            not isinstance(candidate, FusedCandidate)
            for candidate in (*self.relevance_candidates, *self.ordered_candidates)
        ):
            raise RelevanceContractError("response-envelope candidates are invalid")
        if (
            not self.selected_group_order
            or len(self.selected_group_order) > 6
            or len(set(self.selected_group_order)) != len(self.selected_group_order)
            or any(not isinstance(value, str) or not value for value in self.selected_group_order)
        ):
            raise RelevanceContractError("response-envelope group order is invalid")
        if not isinstance(self.decision, RelevanceDecision):
            raise RelevanceContractError("response-envelope relevance decision is invalid")


def _exact_mapping(value: Any, keys: frozenset[str], label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping) or set(value) != keys:
        raise RelevanceContractError(f"{label} fields are invalid")
    return value


def validate_relevance_profile(value: Any) -> RelevancePolicy:
    """Validate the one accepted relevance profile and compute its identity."""

    root = _exact_mapping(
        value,
        frozenset({"schema_version", "measurement", "decision"}),
        "relevance profile",
    )
    if root["schema_version"] != 2 or type(root["schema_version"]) is not int:
        raise RelevanceContractError("relevance profile schema version is invalid")
    measurement = _exact_mapping(
        root["measurement"],
        frozenset({"text_search_config", "fused_depth", "evidence_fields", "evidence_order"}),
        "relevance measurement",
    )
    decision = _exact_mapping(
        root["decision"],
        frozenset(
            {
                "minimum_supported_numerator",
                "minimum_supported_denominator",
                "comparison",
                "qualified_status",
                "insufficient_status",
                "exact_reference_routing",
                "retrieval_ranking",
                "model_authority",
            }
        ),
        "relevance decision",
    )
    expected_measurement = {
        "text_search_config": "english",
        "fused_depth": 3,
        "evidence_fields": list(EVIDENCE_FIELDS),
        "evidence_order": "response_envelope_rank",
    }
    expected_decision = {
        "minimum_supported_numerator": 3,
        "minimum_supported_denominator": 5,
        "comparison": "greater_than_or_equal",
        "qualified_status": QUALIFIED,
        "insufficient_status": INSUFFICIENT,
        "exact_reference_routing": "preserved",
        "retrieval_ranking": "unchanged",
        "model_authority": False,
    }
    if dict(measurement) != expected_measurement or dict(decision) != expected_decision:
        raise RelevanceContractError("relevance profile contract is invalid")
    canonical = {
        "decision": dict(decision),
        "measurement": dict(measurement),
        "schema_version": 2,
    }
    return RelevancePolicy(
        digest=domain_digest("ishikawa.relevance-profile.v2", canonical),
        fused_depth=3,
        minimum_supported_numerator=3,
        minimum_supported_denominator=5,
    )


def evaluate_relevance(
    measurement: RelevanceMeasurement,
    policy: RelevancePolicy,
) -> RelevanceDecision:
    """Apply the exact frozen ``supported * 5 >= total * 3`` comparison."""

    if not isinstance(measurement, RelevanceMeasurement) or not isinstance(policy, RelevancePolicy):
        raise RelevanceContractError("relevance decision input is invalid")
    supported_count = len(measurement.supported_lexemes)
    question_count = len(measurement.question_lexemes)
    qualified = (
        supported_count * policy.minimum_supported_denominator
        >= question_count * policy.minimum_supported_numerator
    )
    status = QUALIFIED if qualified else INSUFFICIENT
    reason = (
        "CITABLE_EVIDENCE_SUPPORT_QUALIFIED"
        if qualified
        else "CITABLE_EVIDENCE_SUPPORT_INSUFFICIENT"
    )
    return RelevanceDecision(
        status=status,
        reason_code=reason,
        profile_identity=policy.digest,
        fused_depth=policy.fused_depth,
        fused_chunk_count=measurement.fused_chunk_count,
        supported_count=supported_count,
        question_lexeme_count=question_count,
    )


def measure_citable_evidence_relevance(
    connection: Any,
    question: str,
    fused: Sequence[FusedCandidate],
    policy: RelevancePolicy,
) -> RelevanceDecision:
    """Measure the frozen top-three citable envelope and decide relevance."""

    if not isinstance(question, str) or not question.strip() or question != question.strip():
        raise RelevanceContractError("relevance question must be trimmed and nonblank")
    if len(question) > 4096 or "\x00" in question:
        raise RelevanceContractError("relevance question exceeds its safe boundary")
    if not isinstance(policy, RelevancePolicy):
        raise RelevanceContractError("relevance policy is invalid")
    if any(not isinstance(candidate, FusedCandidate) for candidate in fused):
        raise RelevanceContractError("fused relevance candidates are invalid")
    selected = tuple(fused[: policy.fused_depth])
    chunk_ids = tuple(
        dict.fromkeys(
            chunk_id
            for candidate in selected
            for chunk_id in (
                candidate.authoritative_chunk_ids or (candidate.chunk_id,)
            )
        )
    )
    if len(set(chunk_ids)) != len(chunk_ids):
        raise RelevanceContractError("fused relevance candidates contain a duplicate")

    question_row = connection.execute(
        """/* ishikawa.relevance.question-lexemes */
        SELECT tsvector_to_array(to_tsvector('english'::regconfig, %s))
        """,
        (question,),
    ).fetchone()
    if question_row is None or not isinstance(question_row[0], list):
        raise RelevanceContractError("question lexeme measurement failed")
    question_lexemes = tuple(sorted(set(question_row[0])))

    evidence_lexemes: set[str] = set()
    if chunk_ids:
        rows = connection.execute(
            """/* ishikawa.relevance.citable-evidence-lexemes */
            SELECT
              ac.chunk_id,
              tsvector_to_array(
                ac.lexical_vector
                || to_tsvector(
                     'english'::regconfig,
                     concat_ws(
                       ' ',
                       ac.display_name,
                       translate(ac.class_id, '_.-', '   '),
                       (
                         SELECT string_agg(path.value, ' ' ORDER BY path.ordinality)
                         FROM jsonb_array_elements_text(ci.structural_path)
                           WITH ORDINALITY AS path(value, ordinality)
                       ),
                       'page ' || ci.page_start::text,
                       CASE
                         WHEN ci.page_end <> ci.page_start THEN 'page ' || ci.page_end::text
                         ELSE NULL
                       END
                     )
                   )
              )
            FROM rag_search.active_chunks ac
            JOIN rag_search.active_citations ci ON ci.chunk_id = ac.chunk_id
            WHERE ac.chunk_id = ANY(%s::text[])
            ORDER BY ac.chunk_id, ci.citation_id
            """,
            (list(chunk_ids),),
        ).fetchall()
        if {row[0] for row in rows} != set(chunk_ids):
            raise RelevanceContractError("citable evidence identity mismatch")
        for _, lexemes in rows:
            if not isinstance(lexemes, list):
                raise RelevanceContractError("citable evidence lexeme measurement failed")
            evidence_lexemes.update(lexemes)
    supported = tuple(sorted(set(question_lexemes) & evidence_lexemes))
    unsupported = tuple(sorted(set(question_lexemes) - evidence_lexemes))
    return evaluate_relevance(
        RelevanceMeasurement(
            question_lexemes=question_lexemes,
            supported_lexemes=supported,
            unsupported_lexemes=unsupported,
            fused_chunk_count=len(selected),
        ),
        policy,
    )


def _candidate_group(candidate: FusedCandidate) -> tuple[str, str]:
    return (
        candidate.document_version_id,
        candidate.retrieval_group_id or candidate.chunk_id,
    )


def _scope_candidates(
    connection: Any,
    document_version_ids: tuple[str, ...],
) -> dict[str, FusedCandidate]:
    """Load one bounded authoritative Purpose/Scope unit per retrieved document."""

    if not document_version_ids:
        return {}
    rows = connection.execute(
        """/* ishikawa.relevance.document-scope-units */
        WITH ranked_scope AS (
          SELECT
            ac.chunk_id,
            ac.document_id,
            ac.document_version_id,
            ac.document_key,
            ac.retrieval_group_id,
            ac.authoritative_chunk_ids,
            ac.structural_path,
            row_number() OVER (
              PARTITION BY ac.document_version_id
              ORDER BY
                cardinality(ac.authoritative_chunk_ids) DESC,
                ac.retrieval_scoring_only DESC,
                ac.chunk_id
            ) AS scope_rank
          FROM rag_search.active_retrieval_candidates ac
          WHERE ac.document_version_id = ANY(%s::text[])
            AND jsonb_array_length(ac.structural_path) > 0
            AND lower(ac.structural_path ->> 0)
                ~ '(^|[^a-z])(purpose|scope)([^a-z]|$)'
        )
        SELECT chunk_id, document_id, document_version_id, document_key,
               retrieval_group_id, authoritative_chunk_ids, structural_path
        FROM ranked_scope
        WHERE scope_rank = 1
        ORDER BY document_version_id, chunk_id
        """,
        (list(document_version_ids),),
    ).fetchall()
    scopes: dict[str, FusedCandidate] = {}
    for row in rows:
        if (
            len(row) != 7
            or row[2] in scopes
            or any(
                not isinstance(value, str) or HEX_IDENTITY.fullmatch(value) is None
                for value in row[:3]
            )
            or not isinstance(row[3], str)
            or not row[3].strip()
            or row[3] != row[3].strip()
            or not isinstance(row[4], str)
            or not row[4].strip()
            or row[4] != row[4].strip()
            or not isinstance(row[5], (list, tuple))
            or not isinstance(row[6], (list, tuple))
        ):
            raise RelevanceContractError("document scope unit result is invalid")
        authoritative = tuple(row[5])
        if (
            not authoritative
            or len(set(authoritative)) != len(authoritative)
            or any(
                not isinstance(value, str) or HEX_IDENTITY.fullmatch(value) is None
                for value in authoritative
            )
            or not row[6]
            or any(
                not isinstance(value, str) or not value.strip() or value != value.strip()
                for value in row[6]
            )
        ):
            raise RelevanceContractError("document scope unit has no authoritative evidence")
        scopes[row[2]] = FusedCandidate(
            chunk_id=row[0],
            document_id=row[1],
            document_version_id=row[2],
            document_key=row[3],
            fused_score=0.0,
            exact_priority=False,
            evidence=(),
            retrieval_group_id=row[4],
            authoritative_chunk_ids=authoritative,
            retrieval_scoring_only=False,
            structural_path=tuple(row[6]),
        )
    return scopes


def _lexeme_inventory(
    connection: Any,
    question: str,
    chunk_ids: tuple[str, ...],
) -> tuple[tuple[str, ...], dict[str, frozenset[str]]]:
    question_row = connection.execute(
        """/* ishikawa.relevance.question-lexemes */
        SELECT tsvector_to_array(to_tsvector('english'::regconfig, %s))
        """,
        (question,),
    ).fetchone()
    if question_row is None or not isinstance(question_row[0], list):
        raise RelevanceContractError("question lexeme measurement failed")
    question_lexemes = tuple(sorted(set(question_row[0])))
    if not question_lexemes:
        raise RelevanceContractError("question produced no measurable lexemes")

    rows = connection.execute(
        """/* ishikawa.relevance.citable-evidence-lexemes */
        SELECT
          ac.chunk_id,
          tsvector_to_array(
            ac.lexical_vector
            || to_tsvector(
                 'english'::regconfig,
                 concat_ws(
                   ' ',
                   ac.display_name,
                   translate(ac.class_id, '_.-', '   '),
                   (
                     SELECT string_agg(path.value, ' ' ORDER BY path.ordinality)
                     FROM jsonb_array_elements_text(ci.structural_path)
                       WITH ORDINALITY AS path(value, ordinality)
                   ),
                   'page ' || ci.page_start::text,
                   CASE
                     WHEN ci.page_end <> ci.page_start THEN 'page ' || ci.page_end::text
                     ELSE NULL
                   END
                 )
               )
          )
        FROM rag_search.active_chunks ac
        JOIN rag_search.active_citations ci ON ci.chunk_id = ac.chunk_id
        WHERE ac.chunk_id = ANY(%s::text[])
        ORDER BY ac.chunk_id, ci.citation_id
        """,
        (list(chunk_ids),),
    ).fetchall()
    if {row[0] for row in rows} != set(chunk_ids):
        raise RelevanceContractError("citable evidence identity mismatch")
    inventory: dict[str, set[str]] = {chunk_id: set() for chunk_id in chunk_ids}
    for chunk_id, lexemes in rows:
        if not isinstance(lexemes, list):
            raise RelevanceContractError("citable evidence lexeme measurement failed")
        inventory[chunk_id].update(lexemes)
    return question_lexemes, {
        chunk_id: frozenset(lexemes) for chunk_id, lexemes in inventory.items()
    }


def plan_citable_response_envelopes(
    connection: Any,
    question: str,
    candidates: Sequence[FusedCandidate],
    policy: RelevancePolicy,
) -> ResponseEnvelopePlan:
    """Build and rank bounded per-document response envelopes.

    Candidate generation and V13-47 scores are inputs, never modified.  The
    planner chooses one responsive structural result per retrieved document,
    pairs it with at most one complementary same-document result when that
    result adds question coverage, measures full-question coverage, and emits
    at most six groups for generation.  The earliest V13-47 document remains
    first; full-question coverage orders the remaining documents.  A retrieved
    operational section may be the companion instead of Purpose/Scope; this
    prevents a scope paragraph that repeats the question from displacing the
    actual steps or threshold.
    """

    if not isinstance(question, str) or not question.strip() or question != question.strip():
        raise RelevanceContractError("relevance question must be trimmed and nonblank")
    if len(question) > 4096 or "\x00" in question:
        raise RelevanceContractError("relevance question exceeds its safe boundary")
    if not isinstance(policy, RelevancePolicy):
        raise RelevanceContractError("relevance policy is invalid")
    pool = tuple(candidates[:20])
    if not pool or any(not isinstance(candidate, FusedCandidate) for candidate in pool):
        raise RelevanceContractError("response-envelope candidates are invalid")

    version_ids = tuple(dict.fromkeys(item.document_version_id for item in pool))
    scopes = _scope_candidates(connection, version_ids)
    all_chunk_ids = tuple(
        dict.fromkeys(
            chunk_id
            for candidate in (*pool, *scopes.values())
            for chunk_id in (candidate.authoritative_chunk_ids or (candidate.chunk_id,))
        )
    )
    question_lexemes, evidence_lexemes = _lexeme_inventory(
        connection, question, all_chunk_ids
    )
    question_set = set(question_lexemes)

    ranked_source = {id(candidate): rank for rank, candidate in enumerate(pool)}
    candidates_by_version: dict[str, list[FusedCandidate]] = {}
    for candidate in pool:
        candidates_by_version.setdefault(candidate.document_version_id, []).append(candidate)

    best_by_version: dict[
        str,
        tuple[int, int, FusedCandidate, FusedCandidate | None, tuple[str, ...]],
    ] = {}
    for version_id, document_candidates in candidates_by_version.items():
        unique_options: list[FusedCandidate] = []
        seen_option_groups: set[tuple[str, str]] = set()
        for option in (*document_candidates, scopes.get(version_id)):
            if option is None:
                continue
            group = _candidate_group(option)
            if group in seen_option_groups:
                continue
            seen_option_groups.add(group)
            unique_options.append(option)

        for candidate in document_candidates:
            candidate_ids = tuple(
                candidate.authoritative_chunk_ids or (candidate.chunk_id,)
            )
            candidate_supported = question_set & set().union(
                *(evidence_lexemes[chunk_id] for chunk_id in candidate_ids)
            )
            companion: FusedCandidate | None = None
            supported = set(candidate_supported)
            for option in unique_options:
                if _candidate_group(option) == _candidate_group(candidate):
                    continue
                option_ids = tuple(option.authoritative_chunk_ids or (option.chunk_id,))
                option_supported = question_set & set().union(
                    *(evidence_lexemes[chunk_id] for chunk_id in option_ids)
                )
                combined = candidate_supported | option_supported
                if not option_supported - candidate_supported:
                    continue
                if companion is None or (
                    -len(combined),
                    ranked_source.get(id(option), len(pool)),
                    option.chunk_id,
                ) < (
                    -len(supported),
                    ranked_source.get(id(companion), len(pool)),
                    companion.chunk_id,
                ):
                    companion = option
                    supported = combined

            rank = ranked_source[id(candidate)]
            proposal = (
                len(supported),
                rank,
                candidate,
                companion,
                tuple(sorted(supported)),
            )
            current = best_by_version.get(version_id)
            if current is None or (-proposal[0], proposal[1], proposal[2].chunk_id) < (
                -current[0], current[1], current[2].chunk_id
            ):
                best_by_version[version_id] = proposal

    # Envelope coverage selects the best structural pair *inside* a document.
    # Preserve only the already-qualified V13-47 rank-one document as the
    # cross-document anchor: this prevents a near-duplicate control from
    # displacing the best retrieval result.  Coverage orders the remaining
    # documents so a responsive scope/operation pair is not crowded out by
    # multiple generic high-ranked documents.
    document_rank = {
        version_id: min(ranked_source[id(candidate)] for candidate in items)
        for version_id, items in candidates_by_version.items()
    }
    anchor_version = min(document_rank, key=document_rank.__getitem__)
    ranked_envelopes = sorted(
        best_by_version.values(),
        key=lambda item: (
            0 if item[2].document_version_id == anchor_version else 1,
            0 if item[2].document_version_id == anchor_version else -item[0],
            document_rank[item[2].document_version_id],
            item[1],
            item[2].chunk_id,
        ),
    )
    selected_envelopes = ranked_envelopes[: policy.fused_depth]
    relevance_candidates: list[FusedCandidate] = []
    selected_group_order: list[str] = []
    selected_candidates: list[FusedCandidate] = []
    supported_union: set[str] = set()
    for _count, _rank, candidate, companion, supported in selected_envelopes:
        supported_union.update(supported)
        authoritative = tuple(candidate.authoritative_chunk_ids or (candidate.chunk_id,))
        if companion is not None:
            authoritative = tuple(
                dict.fromkeys(
                    (
                        *authoritative,
                        *(companion.authoritative_chunk_ids or (companion.chunk_id,)),
                    )
                )
            )
        relevance_candidates.append(
            FusedCandidate(
                chunk_id=authoritative[0],
                document_id=candidate.document_id,
                document_version_id=candidate.document_version_id,
                document_key=candidate.document_key,
                fused_score=candidate.fused_score,
                exact_priority=candidate.exact_priority,
                evidence=candidate.evidence,
                retrieval_group_id=candidate.retrieval_group_id,
                authoritative_chunk_ids=authoritative,
                retrieval_scoring_only=False,
                structural_path=candidate.structural_path,
            )
        )

    seen_groups: set[tuple[str, str]] = set()
    for _count, _rank, candidate, companion, _supported in ranked_envelopes:
        for item in (candidate, companion):
            if item is None:
                continue
            group = _candidate_group(item)
            if group in seen_groups:
                continue
            if len(selected_group_order) >= 6:
                continue
            seen_groups.add(group)
            selected_candidates.append(item)
            selected_group_order.append(f"{group[0]}:{group[1]}")

    for candidate in pool:
        group = _candidate_group(candidate)
        if group not in seen_groups:
            seen_groups.add(group)
            selected_candidates.append(candidate)

    supported = tuple(sorted(supported_union))
    unsupported = tuple(sorted(question_set - supported_union))
    decision = evaluate_relevance(
        RelevanceMeasurement(
            question_lexemes=question_lexemes,
            supported_lexemes=supported,
            unsupported_lexemes=unsupported,
            fused_chunk_count=len(relevance_candidates),
        ),
        policy,
    )
    return ResponseEnvelopePlan(
        tuple(relevance_candidates),
        tuple(selected_candidates),
        tuple(selected_group_order),
        decision,
    )
