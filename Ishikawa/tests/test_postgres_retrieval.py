from __future__ import annotations

import json
import unittest
from pathlib import Path
from unittest.mock import patch

from ishikawa.api_contract import decode_chat_request, validate_api_profile
from ishikawa.canonical import domain_digest
from ishikawa.method_profile import validate_retrieval_profile
from ishikawa.native_adapters import (
    ACCEPTED_EMBEDDING_SPACE_ID,
    ValidatedQueryEmbedding,
)
from ishikawa.postgres_retrieval import (
    NativePostgresRetrievalAdapter,
    _DocumentMetadata,
    _fit_exact_generation_context,
    reciprocal_rank_fusion as runtime_reciprocal_rank_fusion,
    requested_complete_section,
    requests_complete_procedure,
)
from ishikawa.query_resolution import (
    ResolvedRetrievalQuery,
    ResolvedSourceConstraint,
    validate_query_resolution_profile,
)
from ishikawa.reconstruction import (
    EvidenceCandidate,
    EvidenceCitation,
    assemble_evidence,
    validate_reconstruction_profile,
)
from ishikawa.relevance import validate_relevance_profile
from ishikawa.relationships import validate_relationship_registry
from ishikawa.retrieval import LaneCandidate
from ishikawa.retrieval_service import RetrievalServiceContractError
from ishikawa.sufficiency import validate_sufficiency_profile
from ishikawa.yaml_loader import load_restricted_yaml


def ident(character: str) -> str:
    return character * 64


class FakeConnection:
    def __init__(
        self,
        *,
        role: str = "rag_retrieval",
        omit_hydration: bool = False,
        relationship: bool = False,
        complete_inventory: bool = False,
        primary_projection_kind: str = "paragraph",
        question_lexemes: tuple[str, ...] = ("incident", "report", "requir"),
        evidence_lexemes: tuple[str, ...] = (
            "incident", "report", "requir", "prompt"
        ),
    ):
        self.role = role
        self.omit_hydration = omit_hydration
        self.relationship = relationship
        self.complete_inventory = complete_inventory
        self.primary_projection_kind = primary_projection_kind
        self.question_lexemes = question_lexemes
        self.evidence_lexemes = evidence_lexemes
        self.executions: list[tuple[str, tuple]] = []
        self.current = None
        self.rolled_back = False
        self.closed = False

    @property
    def candidate_row(self):
        return (ident("a"), ident("b"), ident("c"), "procedure.incident-reporting", 1.0)

    @property
    def retrieval_candidate_row(self):
        return (
            *self.candidate_row,
            "incident-reporting-page-two",
            [ident("a")],
            False,
            True,
            ["I. Reporting", "Initial report"],
        )

    def execute(self, sql, parameters=()):
        parameters = tuple(parameters)
        if sql.count("%s") != len(parameters):
            raise AssertionError(
                f"SQL bind count mismatch: {sql.count('%s')} placeholders, "
                f"{len(parameters)} parameters"
            )
        self.executions.append((sql, parameters))
        if "postgres-retrieval.boundary" in sql:
            self.current = (self.role, "on", "repeatable read")
        elif "retrieval.exact.document_version" in sql:
            self.current = [self.candidate_row]
        elif "retrieval.exact.citation" in sql:
            self.current = [self.candidate_row]
        elif "retrieval.exact.structured_term" in sql:
            self.current = [self.candidate_row]
        elif "retrieval.lexical" in sql:
            self.current = [
                (
                    ident("8"), ident("9"), ident("0"), "regulation.records", 0.7,
                    "records-page-one", [ident("8")], False, True,
                    ["Records", "Preservation"],
                )
            ] if [ident("0")] in parameters else [
                (*self.retrieval_candidate_row[:4], 0.8, *self.retrieval_candidate_row[5:])
            ]
        elif "retrieval.vector" in sql:
            self.current = [
                (
                    ident("8"), ident("9"), ident("0"), "regulation.records", 0.75,
                    "records-page-one", [ident("8")], False, True,
                    ["Records", "Preservation"],
                )
            ] if [ident("0")] in parameters else [
                (*self.retrieval_candidate_row[:4], 0.9, *self.retrieval_candidate_row[5:])
            ]
        elif "postgres-retrieval.relationship-one-hop" in sql:
            self.current = [
                (
                    ident("5"),
                    "explicit_reference.document",
                    ident("b"),
                    ident("9"),
                    ident("0"),
                    ident("e"),
                    ident("a"),
                    "Escalate under 99 TST 2003, Section I.",
                )
            ] if self.relationship else []
        elif "postgres-retrieval.relationship-locator" in sql:
            self.current = [
                (ident("8"), ident("9"), ident("0"), "regulation.records", 1.0)
            ]
        elif "postgres-retrieval.complete-procedure-inventory" in sql:
            target_version = parameters[0]
            if target_version == ident("0"):
                self.current = [
                    (ident("8"), ident("9"), ident("0"), "regulation.records", 1.0)
                ]
            else:
                self.current = [
                    self.candidate_row,
                    (ident("f"), ident("b"), ident("c"), "procedure.incident-reporting", 1.0),
                ] if self.complete_inventory else [self.candidate_row]
        elif "postgres-retrieval.document-identifiers" in sql:
            self.current = [
                (version_id, "Policy Number: 99 TST 2003.")
                for version_id in parameters[0]
            ]
        elif "postgres-retrieval.generation-citation-excerpts" in sql:
            excerpts = {
                ident("e"): "Incidents must be reported promptly to the duty officer.",
                ident("5"): "Notify the records coordinator after the initial report.",
                ident("2"): "The referenced regulation requires records preservation.",
            }
            self.current = [
                (citation_id, excerpts[citation_id])
                for citation_id in parameters[0]
            ]
        elif "postgres-retrieval.document-page-counts" in sql:
            self.current = [
                (version_id, 3 if version_id == ident("c") else 1)
                for version_id in parameters[0]
            ]
        elif "postgres-retrieval.structural-display-units" in sql:
            self.current = [
                (
                    4, self.primary_projection_kind, ident("e"),
                    "Incidents must be reported promptly to the duty officer.",
                    2, 2, ["I. Reporting", "Initial report"],
                ),
                *([
                    (
                        5, "procedure_step", ident("5"),
                        "Notify the records coordinator after the initial report.",
                        3, 3, ["I. Reporting", "Follow-up"],
                    ),
                    (
                        6, "paragraph", ident("3"),
                        "Retain the report according to the records schedule.",
                        4, 4, ["II. Records", "Retention"],
                    ),
                ] if self.complete_inventory else []),
            ]
        elif "postgres-retrieval.hydrate" in sql:
            requested = set(parameters[0])
            rows = [
                (
                    ident("a"), ident("b"), ident("c"),
                    "procedure.incident-reporting", "Incident Reporting Procedure",
                    "policy_sop", ident("d"),
                    "Document: Incident Reporting Procedure\n\n"
                    "Incidents must be reported promptly to the duty officer.",
                    self.primary_projection_kind, 4, ident("e"), 2, 2,
                    ["I. Reporting", "Initial report"],
                ),
                (
                    ident("f"), ident("b"), ident("c"),
                    "procedure.incident-reporting", "Incident Reporting Procedure",
                    "policy_sop", ident("4"),
                    "Notify the records coordinator after the initial report.",
                    "procedure_step", 5, ident("5"), 3, 3,
                    ["I. Reporting", "Follow-up"],
                ),
                (
                    ident("8"), ident("9"), ident("0"),
                    "regulation.records", "Records Regulation",
                    "policy_sop", ident("1"),
                    "The referenced regulation requires records preservation.",
                    "paragraph", 2, ident("2"), 1, 1,
                    ["Records", "Preservation"],
                ),
            ]
            self.current = [] if self.omit_hydration else [row for row in rows if row[0] in requested]
        elif "relevance.question-lexemes" in sql:
            self.current = (list(self.question_lexemes),)
        elif "relevance.citable-evidence-lexemes" in sql:
            self.current = [(ident("a"), list(self.evidence_lexemes))]
        else:
            self.current = []
        return self

    def fetchone(self):
        return self.current

    def fetchall(self):
        return self.current

    def rollback(self):
        self.rolled_back = True

    def close(self):
        self.closed = True


class PostgresRetrievalAdapterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[1]
        load = lambda name: load_restricted_yaml(
            root / f"config/templates/{name}.yaml", label=name
        )
        cls.api_policy = validate_api_profile(load("api_profile"))
        cls.resolution_policy = validate_query_resolution_profile(load("query_resolution_profile"))
        cls.retrieval_policy = validate_retrieval_profile(load("method_profile"))
        cls.reconstruction_policy = validate_reconstruction_profile(load("reconstruction_profile"))
        cls.relevance_policy = validate_relevance_profile(load("relevance_profile"))
        cls.sufficiency_policy = validate_sufficiency_profile(load("sufficiency_profile"))
        cls.relationship_registry = validate_relationship_registry(load("relationship_types"))

    def request(
        self,
        *,
        restrict_document: bool = True,
        message: str = "What else does Source 1 say?",
    ):
        return decode_chat_request(
            json.dumps(
                {
                    "schema": "ishikawa.chat-request.v1",
                    "conversation_id": ident("1"),
                    "turn_id": ident("4"),
                    "message": message,
                    "history": [
                        {"turn_id": ident("2"), "role": "user", "content": "How are incidents reported?"},
                        {"turn_id": ident("3"), "role": "assistant", "content": "The answer cited Source 1."},
                    ],
                    "source_references": [
                        {"source_id": ident("c"), "source_label": "Source 1", "citation_id": ident("e")}
                    ],
                    "filters": {
                        "document_classes": ["policy_sop"],
                        "document_keys": (
                            ["procedure.incident-reporting"] if restrict_document else []
                        ),
                    },
                }
            ).encode(),
            self.api_policy,
        )

    def resolution(self, request):
        source = ResolvedSourceConstraint(
            ident("c"), "Source 1", "Incident Reporting Procedure", ident("e")
        )
        return ResolvedRetrievalQuery(
            "resolved",
            request.message,
            "What additional incident reporting requirements apply?",
            (source,),
            request.filters,
            None,
            self.resolution_policy.digest,
            ident("6"),
            True,
        )

    def adapter(self, connection, embedded, prompt_counter=None):
        def embed(query):
            embedded.append(query)
            return ValidatedQueryEmbedding(
                tuple([0.01] * 768),
                12,
                ACCEPTED_EMBEDDING_SPACE_ID,
                ident("7"),
            )

        return NativePostgresRetrievalAdapter(
            lambda: connection,
            embed,
            lambda text: max(1, len(text.split())),
            prompt_counter
            or (
                lambda messages, _kwargs: max(
                    1,
                    sum(len(message["content"].split()) for message in messages),
                )
            ),
            self.retrieval_policy,
            self.reconstruction_policy,
            self.relevance_policy,
            self.sufficiency_policy,
            self.relationship_registry,
        )

    def test_complete_procedure_intent_is_conservative(self):
        self.assertTrue(requests_complete_procedure("Provide the complete procedure."))
        self.assertTrue(requests_complete_procedure("Show the procedure in its entirety."))
        self.assertFalse(requests_complete_procedure("What procedure applies?"))
        self.assertFalse(requests_complete_procedure("List the relevant steps."))
        self.assertEqual(requested_complete_section("Provde the complete Section 1."), 1)
        self.assertEqual(requested_complete_section("Return the entire section IV."), 4)
        self.assertIsNone(requested_complete_section("What is in section 1?"))

    def test_runs_three_lanes_with_resolved_query_and_returns_versioned_source(self):
        connection = FakeConnection()
        embedded: list[str] = []
        request = self.request()
        result = self.adapter(connection, embedded)(request, self.resolution(request))
        self.assertEqual(result.sufficiency.status, "sufficient")
        self.assertEqual(embedded, ["What additional incident reporting requirements apply?"])
        self.assertNotIn(request.message, embedded)
        self.assertEqual(result.sources[0].source_id, ident("c"))
        self.assertEqual(result.sources[0].source_label, "Source 1")
        self.assertEqual(result.sources[0].excerpts[0].citation_id, ident("e"))
        self.assertEqual(result.sources[0].page_count, 3)
        self.assertEqual(result.telemetry.nomic_query_tokens, 12)
        self.assertEqual(result.telemetry.prompt_target_tokens, 8192)
        self.assertEqual(
            tuple(name for name, _duration in result.telemetry.retrieval_stage_durations_ms),
            (
                "nomic",
                "lexical_sql",
                "vector_sql",
                "fusion",
                "reconstruction",
                "tokenization",
            ),
        )
        self.assertEqual(
            result.generation_evidence[0].excerpt,
            "Incidents must be reported promptly to the duty officer.",
        )
        sql = "\n".join(statement for statement, _ in connection.executions)
        self.assertIn("retrieval.exact.citation", sql)
        self.assertIn("retrieval.lexical", sql)
        self.assertIn("retrieval.vector", sql)
        self.assertIn("REPEATABLE READ READ ONLY", sql)
        self.assertNotIn("FROM rag.", sql)
        self.assertTrue(connection.rolled_back)
        self.assertTrue(connection.closed)

    def test_unique_explicit_document_identifier_reaches_generation_despite_generic_terms(self):
        question = (
            "Tell me more about TST-9050. What is the process and information "
            "should I have ready?"
        )
        request = self.request(message=question)
        resolution = ResolvedRetrievalQuery(
            "resolved",
            question,
            question,
            (
                ResolvedSourceConstraint(
                    ident("c"), "Source 1", "Access Authorization Form", None
                ),
            ),
            request.filters,
            None,
            self.resolution_policy.digest,
            ident("6"),
            False,
        )
        connection = FakeConnection(
            question_lexemes=("-9050", "inform", "process", "readi", "tst"),
            evidence_lexemes=("-9050", "tst"),
        )
        result = self.adapter(connection, [])(request, resolution)
        self.assertEqual(
            result.telemetry.relevance_reason_code,
            "CITABLE_EVIDENCE_SUPPORT_INSUFFICIENT",
        )
        self.assertEqual(
            (result.sufficiency.status, result.sufficiency.reason_code),
            ("sufficient", "EXACT_DOCUMENT_EVIDENCE_SUFFICIENT"),
        )
        self.assertTrue(result.generation_evidence)

    def test_generic_source_constraint_cannot_bypass_insufficient_relevance(self):
        question = (
            "Tell me more about TST-9050. What is the process and information "
            "should I have ready?"
        )
        request = self.request(message=question)
        resolution = ResolvedRetrievalQuery(
            "resolved",
            question,
            question,
            (
                ResolvedSourceConstraint(
                    ident("c"), "Source 1", "Access Authorization Form", ident("e")
                ),
            ),
            request.filters,
            None,
            self.resolution_policy.digest,
            ident("6"),
            True,
        )
        connection = FakeConnection(
            question_lexemes=("-9050", "inform", "process", "readi", "tst"),
            evidence_lexemes=("-9050", "tst"),
        )
        result = self.adapter(connection, [])(request, resolution)
        self.assertEqual(
            (result.sufficiency.status, result.sufficiency.reason_code),
            ("insufficient-evidence", "RELEVANCE_INSUFFICIENT"),
        )

    def test_generation_packing_caps_responsive_units_before_token_fitting(self):
        candidates = []
        citation_excerpts = {}
        metadata = {}
        document_identifiers = {}
        for index in range(8):
            document_id = domain_digest("test.document.v1", {"index": index})
            version_id = domain_digest("test.version.v1", {"index": index})
            chunk_id = domain_digest("test.chunk.v1", {"index": index})
            citation_id = domain_digest("test.citation.v1", {"index": index})
            excerpt = f"Responsive evidence unit {index}."
            candidates.append(
                EvidenceCandidate(
                    chunk_id=chunk_id,
                    retrieval_text_digest=domain_digest(
                        "ishikawa.retrieval-text.v1",
                        {"retrieval_text": excerpt},
                    ),
                    retrieval_text=excerpt,
                    projection_kind="paragraph",
                    ordinal=index,
                    retrieval_rank=index + 1,
                    origin="direct",
                    inclusion_reason="direct_retrieval",
                    citations=(
                        EvidenceCitation(
                            citation_id=citation_id,
                            document_id=document_id,
                            document_version_id=version_id,
                            document_key=f"policy.synthetic-{index}",
                            page_start=1,
                            page_end=1,
                            structural_path=("I. Purpose",),
                        ),
                    ),
                    retrieval_group_id=f"group-{index}",
                )
            )
            citation_excerpts[citation_id] = excerpt
            metadata[version_id] = _DocumentMetadata(
                f"Synthetic Policy {index}", "policy_sop"
            )
            document_identifiers[version_id] = f"99 TST {2000 + index}"
        package = assemble_evidence(
            tuple(candidates),
            policy=self.reconstruction_policy,
            token_counter=lambda text: max(1, len(text.split())),
            instruction_tokens=1,
            conversation_tokens=1,
        )
        fitted, evidence, prompt_tokens = _fit_exact_generation_context(
            package,
            request=self.request(),
            resolved_query="What additional incident reporting requirements apply?",
            policy=self.reconstruction_policy,
            text_token_counter=lambda text: max(1, len(text.split())),
            prompt_token_counter=lambda _messages, _kwargs: 100,
            exact_required_chunk_ids=frozenset(),
            relationship_coverage_required=False,
            prompt_target_tokens=8192,
            citation_excerpts=citation_excerpts,
            metadata=metadata,
            document_identifiers=document_identifiers,
        )
        self.assertEqual(prompt_tokens, 100)
        self.assertEqual(len(fitted.source_groups), 6)
        self.assertEqual(len(evidence), 6)
        self.assertEqual(
            sum(
                action.reason == "generation_responsive_group_limit"
                for action in fitted.omitted
            ),
            2,
        )

    def test_generation_packing_counts_the_resolved_query_not_the_short_turn(self):
        connection = FakeConnection()
        request = self.request(message="a credential exposure")
        resolution = ResolvedRetrievalQuery(
            "resolved",
            request.message,
            "What forms do I need to complete for reporting a credential exposure?",
            self.resolution(request).source_constraints,
            request.filters,
            None,
            self.resolution_policy.digest,
            ident("6"),
            True,
        )
        packed_questions: list[str] = []

        def prompt_count(messages, template):
            self.assertEqual(template, {"enable_thinking": False})
            payload = json.loads(messages[1]["content"])
            packed_questions.append(payload["question"])
            return 100

        result = self.adapter(connection, [], prompt_count)(request, resolution)
        self.assertEqual(result.sufficiency.status, "sufficient")
        self.assertEqual(
            packed_questions,
            ["What forms do I need to complete for reporting a credential exposure?"],
        )
        self.assertNotIn(request.message, packed_questions)

    def test_display_expands_the_selected_section_without_expanding_model_evidence(self):
        connection = FakeConnection(complete_inventory=True)
        request = self.request()
        result = self.adapter(connection, [])(request, self.resolution(request))
        self.assertEqual(len(result.generation_sources[0].excerpts), 1)
        self.assertEqual(len(result.sources[0].excerpts), 2)
        self.assertEqual(
            {item.structural_path[0] for item in result.sources[0].excerpts},
            {"I. Reporting"},
        )
        self.assertEqual(
            [item.excerpt for item in result.sources[0].excerpts],
            [
                "Incidents must be reported promptly to the duty officer.",
                "Notify the records coordinator after the initial report.",
            ],
        )
        self.assertTrue(result.sources[0].has_additional_sections)

    def test_display_expansion_preserves_nonexpanded_generation_citation(self):
        connection = FakeConnection(
            complete_inventory=True,
            primary_projection_kind="table_context",
        )
        request = self.request()
        result = self.adapter(connection, [])(request, self.resolution(request))
        self.assertEqual(result.sufficiency.status, "sufficient")
        generation_citations = {
            excerpt.citation_id
            for source in result.generation_sources
            for excerpt in source.excerpts
        }
        display_citations = {
            excerpt.citation_id
            for source in result.sources
            for excerpt in source.excerpts
        }
        self.assertLessEqual(generation_citations, display_citations)

    def test_direct_fusion_receives_the_frozen_v13_32_lane_weights(self):
        connection = FakeConnection()
        request = self.request()
        with patch(
            "ishikawa.postgres_retrieval.reciprocal_rank_fusion",
            wraps=runtime_reciprocal_rank_fusion,
        ) as fusion:
            self.adapter(connection, [])(request, self.resolution(request))
        self.assertEqual(fusion.call_count, 1)
        self.assertEqual(
            fusion.call_args.kwargs["lane_weights"],
            {"exact": 1, "lexical": 2, "vector": 4},
        )

    def test_ordinary_nonexact_query_enables_frozen_candidate_representation(self):
        connection = FakeConnection()
        request = self.request(restrict_document=False, message="How are incidents reported?")
        resolution = ResolvedRetrievalQuery(
            "resolved",
            request.message,
            request.message,
            (),
            request.filters,
            None,
            self.resolution_policy.digest,
            ident("6"),
            False,
        )
        result = self.adapter(connection, [])(request, resolution)
        self.assertEqual(result.sufficiency.status, "sufficient")
        lexical_call = next(
            call for call in connection.executions if "retrieval.lexical */" in call[0]
        )
        vector_call = next(
            call for call in connection.executions if "retrieval.vector */" in call[0]
        )
        self.assertEqual(lexical_call[1][2:4], (True, True))
        self.assertEqual(vector_call[1][2:4], (True, True))

    def test_declared_owner_page_route_replaces_weaker_term_lookup(self):
        connection = FakeConnection(relationship=True)
        request = self.request()
        resolution = ResolvedRetrievalQuery(
            "resolved",
            request.message,
            "What appears on page 2 of 99 TST 2005?",
            (),
            request.filters,
            None,
            self.resolution_policy.digest,
            ident("6"),
            True,
        )
        routed = LaneCandidate(
            ident("a"), ident("b"), ident("c"),
            "procedure.incident-reporting", "exact", 1, 1.0,
            exact_reason="document_page_match",
        )
        with (
            patch(
                "ishikawa.postgres_retrieval.exact_document_page_lookup",
                return_value=(routed,),
            ) as page_lookup,
            patch("ishikawa.postgres_retrieval.exact_term_lookup") as term_lookup,
        ):
            self.adapter(connection, [])(request, resolution)
        page_lookup.assert_called_once()
        term_lookup.assert_not_called()
        self.assertFalse(
            any(
                "postgres-retrieval.relationship-one-hop" in statement
                for statement, _parameters in connection.executions
            )
        )

    def test_missing_declared_owner_preserves_ordinary_term_lookup(self):
        connection = FakeConnection()
        request = self.request()
        resolution = ResolvedRetrievalQuery(
            "resolved",
            request.message,
            "What appears on page 2 of 99 TST 9999?",
            (),
            request.filters,
            None,
            self.resolution_policy.digest,
            ident("6"),
            True,
        )
        with (
            patch(
                "ishikawa.postgres_retrieval.exact_document_page_lookup",
                return_value=(),
            ) as page_lookup,
            patch(
                "ishikawa.postgres_retrieval.exact_term_lookup",
                return_value=(),
            ) as term_lookup,
        ):
            self.adapter(connection, [])(request, resolution)
        page_lookup.assert_called_once()
        term_lookup.assert_called_once()

    def test_filters_are_applied_before_candidates_and_rechecked_after_hydration(self):
        connection = FakeConnection()
        request = self.request()
        self.adapter(connection, [])(request, self.resolution(request))
        candidate_calls = [
            (sql, parameters)
            for sql, parameters in connection.executions
            if "retrieval.exact" in sql or "retrieval.lexical" in sql or "retrieval.vector" in sql
        ]
        for sql, parameters in candidate_calls:
            self.assertIn("ac.class_id = ANY", sql)
            self.assertIn("ac.document_key = ANY", sql)
            self.assertIn("ac.document_version_id = ANY", sql)
            self.assertIn(["policy_sop"], parameters)
            self.assertIn(["procedure.incident-reporting"], parameters)
            self.assertIn([ident("c")], parameters)

    def test_wrong_database_role_fails_closed_and_closes_connection(self):
        connection = FakeConnection(role="rag_owner")
        request = self.request()
        with self.assertRaisesRegex(RetrievalServiceContractError, "database boundary"):
            self.adapter(connection, [])(request, self.resolution(request))
        self.assertTrue(connection.rolled_back)
        self.assertTrue(connection.closed)

    def test_missing_hydrated_candidate_fails_closed(self):
        connection = FakeConnection(omit_hydration=True)
        request = self.request()
        with self.assertRaisesRegex(RetrievalServiceContractError, "hydration identity"):
            self.adapter(connection, [])(request, self.resolution(request))

    def test_one_hop_relationship_target_is_optional_for_ordinary_question(self):
        connection = FakeConnection(relationship=True)
        request = self.request(restrict_document=False)
        result = self.adapter(connection, [])(request, self.resolution(request))
        self.assertEqual(result.sufficiency.status, "sufficient")
        self.assertEqual({source.source_id for source in result.sources}, {ident("c"), ident("0")})
        sql = "\n".join(statement for statement, _ in connection.executions)
        self.assertIn("postgres-retrieval.relationship-one-hop", sql)
        self.assertIn("postgres-retrieval.relationship-locator", sql)
        related = [
            item for item in result.generation_evidence
            if item.origin == "relationship"
        ]
        self.assertTrue(related)
        self.assertTrue(all(not item.relationship_required for item in related))
        self.assertEqual({item.relationship_group_id for item in related}, {None})
        seeds = [
            item for item in result.generation_evidence
            if item.origin == "direct" and item.relationship_required
        ]
        self.assertEqual(seeds, [])
        exact = next(
            item for item in result.generation_evidence
            if item.citation_id == ident("e")
        )
        self.assertEqual(len(exact.required_group_ids), 1)

    def test_explicit_relationship_navigation_requires_seed_and_target_groups(self):
        connection = FakeConnection(relationship=True)
        request = self.request(
            restrict_document=False,
            message="What related documents does this policy reference?",
        )
        result = self.adapter(connection, [])(request, self.resolution(request))
        related = [
            item for item in result.generation_evidence
            if item.origin == "relationship"
        ]
        self.assertTrue(related)
        self.assertTrue(all(item.relationship_required for item in related))
        self.assertEqual(
            {item.relationship_group_id for item in related},
            {ident("5")},
        )
        seeds = [
            item for item in result.generation_evidence
            if item.origin == "direct" and item.relationship_required
        ]
        self.assertEqual({item.citation_id for item in seeds}, {ident("e")})

    def test_exact_prompt_budget_removes_lowest_ranked_optional_unit_whole(self):
        connection = FakeConnection(relationship=True)
        request = self.request(restrict_document=False)
        counts = []

        def prompt_count(messages, template):
            self.assertEqual(template, {"enable_thinking": False})
            payload = json.loads(messages[1]["content"])
            item_count = sum(
                len(group["items"]) for group in payload["evidence_groups"]
            )
            counts.append(item_count)
            return 31000 if item_count > 1 else 1000

        result = self.adapter(connection, [], prompt_count)(
            request, self.resolution(request)
        )
        self.assertEqual(result.sufficiency.status, "sufficient")
        self.assertEqual(
            [item.citation_id for item in result.generation_evidence],
            [ident("e")],
        )
        self.assertIn(2, counts)
        self.assertIn(1, counts)
        self.assertEqual(result.telemetry.context_tokens_used, 3048)

    def test_explicit_complete_procedure_loads_full_version_inventory(self):
        connection = FakeConnection(complete_inventory=True)
        request = self.request(message="Provide the complete procedure.")
        resolution = ResolvedRetrievalQuery(
            "resolved",
            request.message,
            "Provide the complete procedure.",
            self.resolution(request).source_constraints,
            request.filters,
            None,
            self.resolution_policy.digest,
            ident("6"),
            True,
        )
        result = self.adapter(connection, [])(request, resolution)
        self.assertEqual(result.sufficiency.status, "sufficient")
        self.assertEqual(len(result.sources), 1)
        self.assertEqual(len(result.sources[0].excerpts), 2)
        sql = "\n".join(statement for statement, _ in connection.executions)
        self.assertIn("postgres-retrieval.complete-procedure-inventory", sql)

    def test_unique_identifier_complete_procedure_accepts_any_citation_from_document(self):
        connection = FakeConnection(complete_inventory=True)
        question = "Does 99 TST 2003 require a form? Provide the complete procedure."
        request = self.request(message=question)
        resolution = ResolvedRetrievalQuery(
            "resolved",
            question,
            question,
            (
                ResolvedSourceConstraint(
                    ident("c"),
                    "Source 1",
                    "Incident Reporting Procedure",
                    None,
                ),
            ),
            request.filters,
            None,
            self.resolution_policy.digest,
            ident("6"),
            False,
        )
        result = self.adapter(connection, [])(request, resolution)
        self.assertEqual(result.sufficiency.status, "sufficient")
        self.assertEqual(
            [item.citation_id for item in result.generation_evidence],
            [ident("e"), ident("5")],
        )
        required_groups = {
            group_id
            for item in result.generation_evidence
            for group_id in item.required_group_ids
        }
        self.assertEqual(len(required_groups), 1)
        self.assertTrue(
            all(item.required_group_ids == tuple(required_groups)
                for item in result.generation_evidence)
        )

    def test_explicit_complete_section_reconstructs_the_numbered_subtree(self):
        connection = FakeConnection(complete_inventory=True)
        request = self.request(message="Provde the complete Section 1 of Source 1.")
        resolution = ResolvedRetrievalQuery(
            "resolved",
            request.message,
            "Provide the complete Section 1 of Source 1.",
            self.resolution(request).source_constraints,
            request.filters,
            None,
            self.resolution_policy.digest,
            ident("6"),
            True,
        )
        result = self.adapter(connection, [])(request, resolution)
        self.assertEqual(result.sufficiency.status, "sufficient")
        self.assertEqual(len(result.generation_sources[0].excerpts), 2)
        self.assertEqual(len(result.sources[0].excerpts), 2)
        self.assertEqual(result.sources[0].document_identifier, "99 TST 2003")


if __name__ == "__main__":
    unittest.main()
