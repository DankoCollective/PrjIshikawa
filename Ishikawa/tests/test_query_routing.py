from __future__ import annotations

import unittest
from pathlib import Path

from ishikawa.api_contract import decode_chat_request, validate_api_profile
from ishikawa.canonical import canonical_json_bytes
from ishikawa.query_routing import (
    KNOWN_DOCUMENT_ROUTING_IDENTITY,
    NativeKnownDocumentScopeRouter,
    department_follow_up,
    direct_department_reference,
    vague_document_subject,
)
from ishikawa.query_resolution import validate_query_resolution_profile
from ishikawa.retrieval_service import RetrievalDependencyUnavailable
from ishikawa.yaml_loader import load_restricted_yaml


def identity(character: str) -> str:
    return character * 64


class _Result:
    def __init__(self, *, one=None, rows=None):
        self.one = one
        self.rows = rows

    def fetchone(self):
        return self.one

    def fetchall(self):
        return self.rows


class _Connection:
    def __init__(self, rows, *, related_rows=()):
        self.rows = rows
        self.related_rows = related_rows
        self.calls = []
        self.rolled_back = False
        self.closed = False

    def execute(self, sql, parameters=()):
        self.calls.append((sql, parameters))
        if "known-document.boundary" in sql or "known-document-resolution.boundary" in sql:
            return _Result(one=("rag_retrieval", "on", "repeatable read"))
        if (
            "known-document.structured-identifier" in sql
            or "known-document.vague-subject" in sql
            or "known-document.explicit-name-or-key" in sql
            or "known-document.department-match" in sql
        ):
            return _Result(rows=self.rows)
        if "known-document.department-related" in sql:
            return _Result(rows=self.related_rows)
        return _Result()

    def rollback(self):
        self.rolled_back = True

    def close(self):
        self.closed = True


class KnownDocumentRoutingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[1]
        cls.api_policy = validate_api_profile(
            load_restricted_yaml(root / "config/templates/api_profile.yaml", label="api")
        )

    def request(self, message, *, classes=(), keys=(), history=(), references=()):
        return decode_chat_request(
            canonical_json_bytes(
                {
                    "conversation_id": identity("a"),
                    "filters": {
                        "document_classes": list(classes),
                        "document_keys": list(keys),
                    },
                    "history": list(history),
                    "message": message,
                    "schema": "ishikawa.chat-request.v1",
                    "source_references": list(references),
                    "turn_id": identity("b"),
                }
            ),
            self.api_policy,
        )

    def document(self, suffix="1"):
        return (
            identity(suffix),
            identity(chr(ord(suffix) + 1)),
            "policy.controlled-materials",
            "Controlled Materials Access Policy",
        )

    def test_routing_identity_and_vague_form_are_deterministic(self):
        self.assertEqual(len(KNOWN_DOCUMENT_ROUTING_IDENTITY), 64)
        self.assertEqual(
            vague_document_subject("What about the Controlled Materials Access policy?"),
            "Controlled Materials Access policy",
        )
        self.assertIsNone(vague_document_subject("Summarize the policy."))

    def test_known_identifier_bypasses_model_scope_and_closes_read_only_connection(self):
        connection = _Connection([self.document()])
        router = NativeKnownDocumentScopeRouter(lambda: connection)
        decision = router(self.request("What content appears on page 1 of 99 TST 2002?"))
        self.assertEqual(decision.decision, "allow")
        self.assertEqual(decision.reason_code, "known_document_reference")
        self.assertIsNone(decision.clarification)
        self.assertTrue(connection.rolled_back)
        self.assertTrue(connection.closed)
        sql = "\n".join(item[0] for item in connection.calls)
        self.assertIn("REPEATABLE READ READ ONLY", sql)
        self.assertIn("rag_search.active_chunks", sql)
        self.assertIn("rag_search.active_citations", sql)
        self.assertIn("document_control,policy_number", sql)
        self.assertIn("relevant_excerpt", sql)
        self.assertIn("policy number:", sql)
        self.assertNotIn("lower(btrim(ac.retrieval_text))", sql)

    def test_vague_unique_document_clarifies_without_relationship_expansion(self):
        connection = _Connection([self.document()])
        router = NativeKnownDocumentScopeRouter(lambda: connection)
        decision = router(self.request("What about the Controlled Materials Access policy?"))
        self.assertEqual(decision.decision, "needs_clarification")
        self.assertEqual(decision.reason_code, "vague_known_document")
        self.assertEqual(
            decision.clarification,
            "What would you like to know about Controlled Materials Access policy?",
        )
        sql = "\n".join(item[0] for item in connection.calls)
        self.assertIn("rag_search.active_documents", sql)
        self.assertIn("websearch_to_tsquery('english'", sql)
        self.assertNotIn("active_relationships", sql)

    def test_unique_explicit_title_allows_scope_and_constrains_query(self):
        connection = _Connection([self.document()])
        router = NativeKnownDocumentScopeRouter(lambda: connection)
        request = self.request("What is the Controlled Materials Access Policy?")
        decision = router(request)
        self.assertEqual(decision.decision, "allow")
        policy = validate_query_resolution_profile(
            load_restricted_yaml(
                Path(__file__).resolve().parents[1]
                / "config/templates/query_resolution_profile.yaml",
                label="query resolution",
            )
        )
        resolution = router.resolve_query(request, policy)
        self.assertEqual(resolution.status, "resolved")
        self.assertFalse(resolution.used_model)
        self.assertEqual(len(resolution.source_constraints), 1)
        self.assertEqual(resolution.source_constraints[0].source_id, self.document()[1])
        sql = "\n".join(item[0] for item in connection.calls)
        self.assertIn("known-document.explicit-name-or-key", sql)
        explicit_sql = next(
            statement
            for statement, _ in connection.calls
            if "known-document.explicit-name-or-key" in statement
        )
        self.assertNotIn("SELECT DISTINCT ad.document_id", explicit_sql)
        self.assertIn("ORDER BY length(ad.display_name) DESC", explicit_sql)

    def test_unknown_or_noncandidate_question_preserves_existing_model_scope_path(self):
        calls = []

        def factory():
            calls.append("database")
            return _Connection([])

        router = NativeKnownDocumentScopeRouter(factory)
        self.assertIsNone(router(self.request("How is access requested?")))
        self.assertEqual(calls, ["database"])
        self.assertIsNone(router(self.request("What about an unknown document?")))
        self.assertEqual(calls, ["database", "database"])

    def test_ambiguous_document_clarifies_and_filters_are_preserved_in_sql(self):
        connection = _Connection([self.document("1"), self.document("3")])
        router = NativeKnownDocumentScopeRouter(lambda: connection)
        decision = router(
            self.request(
                "What content appears on page 1 of 99 TST 2002?",
                classes=("policy_sop",),
                keys=("policy.controlled-materials",),
            )
        )
        self.assertEqual(decision.decision, "needs_clarification")
        self.assertEqual(decision.reason_code, "ambiguous_known_document")
        parameters = connection.calls[-1][1]
        self.assertEqual(parameters[:6], ("99 TST 2002",) * 6)
        self.assertEqual(parameters[-4:-2], (["policy_sop"], ["policy_sop"]))
        self.assertEqual(
            parameters[-2:],
            (["policy.controlled-materials"], ["policy.controlled-materials"]),
        )

    def test_database_failure_is_content_free_dependency_failure(self):
        router = NativeKnownDocumentScopeRouter(
            lambda: (_ for _ in ()).throw(OSError("private detail"))
        )
        with self.assertRaises(RetrievalDependencyUnavailable) as context:
            router(self.request("What content appears on page 1 of 99 TST 2002?"))
        self.assertEqual(str(context.exception), "known_document_lookup_failed")

    def test_exact_known_department_follow_up_bypasses_model_and_merges_question(self):
        history = (
            {
                "turn_id": identity("c"),
                "role": "user",
                "content": "There has been an incident concerning controlled materials.",
            },
            {
                "turn_id": identity("d"),
                "role": "assistant",
                "content": "Which department was involved?",
            },
        )
        request = self.request("IT", history=history)
        self.assertEqual(
            department_follow_up(request),
            ("There has been an incident concerning controlled materials.", "IT"),
        )
        row_one = (*self.document("1"), "Information Technology", identity("a"))
        row_two = (*self.document("3"), "Information Technology", identity("b"))
        connection = _Connection([row_one, row_two])
        router = NativeKnownDocumentScopeRouter(lambda: connection)
        decision = router(request)
        self.assertEqual(decision.decision, "allow")
        self.assertEqual(decision.reason_code, "known_department_follow_up")
        policy = validate_query_resolution_profile(
            load_restricted_yaml(
                Path(__file__).resolve().parents[1]
                / "config/templates/query_resolution_profile.yaml",
                label="query resolution",
            )
        )
        resolution = router.resolve_query(request, policy)
        self.assertEqual(resolution.status, "resolved")
        self.assertFalse(resolution.used_model)
        self.assertEqual(len(resolution.source_constraints), 2)
        self.assertEqual(
            resolution.resolved_query,
            "There has been an incident concerning controlled materials. "
            "Department: Information Technology.",
        )
        department_calls = [
            item for item in connection.calls
            if "known-document.department-match" in item[0]
        ]
        self.assertEqual(len(department_calls), 2)
        self.assertIn("retrieval_filters", department_calls[0][0])

    def test_declarative_answer_mentioning_department_is_not_a_department_prompt(self):
        history = (
            {
                "turn_id": identity("c"),
                "role": "user",
                "content": "I need to submit an access request.",
            },
            {
                "turn_id": identity("d"),
                "role": "assistant",
                "content": (
                    "Request missing facts such as the department, incident type, "
                    "or authority rather than guessing."
                ),
            },
        )
        request = self.request("Information Technology", history=history)
        self.assertIsNone(department_follow_up(request))

    def test_explicit_identifier_after_department_prose_routes_the_document(self):
        history = (
            {
                "turn_id": identity("c"),
                "role": "user",
                "content": "I am new and need to submit access requests.",
            },
            {
                "turn_id": identity("d"),
                "role": "assistant",
                "content": (
                    "Request missing facts such as the department, incident type, "
                    "or authority rather than guessing."
                ),
            },
        )
        request = self.request(
            "Tell me more about TST-9001",
            history=history,
            references=(
                {
                    "citation_id": None,
                    "source_id": identity("9"),
                    "source_label": "Source 1",
                },
            ),
        )
        connection = _Connection([self.document()])
        router = NativeKnownDocumentScopeRouter(lambda: connection)
        decision = router(request)
        self.assertEqual(decision.decision, "allow")
        self.assertEqual(decision.reason_code, "known_document_reference")
        policy = validate_query_resolution_profile(
            load_restricted_yaml(
                Path(__file__).resolve().parents[1]
                / "config/templates/query_resolution_profile.yaml",
                label="query resolution",
            )
        )
        resolution = router.resolve_query(request, policy)
        self.assertEqual(resolution.status, "resolved")
        self.assertFalse(resolution.used_model)
        self.assertEqual(len(resolution.source_constraints), 1)
        self.assertEqual(
            resolution.source_constraints[0].source_id,
            self.document()[1],
        )
        structured_calls = [
            item for item in connection.calls
            if "known-document.structured-identifier" in item[0]
        ]
        self.assertEqual(len(structured_calls), 2)

    def test_unknown_department_reply_preserves_existing_model_path(self):
        history = (
            {"turn_id": identity("c"), "role": "user", "content": "An incident occurred."},
            {
                "turn_id": identity("d"),
                "role": "assistant",
                "content": "Which dept. was involved?",
            },
        )
        connection = _Connection([])
        router = NativeKnownDocumentScopeRouter(lambda: connection)
        self.assertIsNone(router(self.request("Unknown Group", history=history)))

    def test_colliding_department_acronym_requires_clarification(self):
        history = (
            {"turn_id": identity("c"), "role": "user", "content": "An incident occurred."},
            {
                "turn_id": identity("d"),
                "role": "assistant",
                "content": "Which department was involved?",
            },
        )
        rows = [
            (*self.document("1"), "Information Technology", identity("a")),
            (*self.document("3"), "Internal Training", identity("b")),
        ]
        router = NativeKnownDocumentScopeRouter(lambda: _Connection(rows))
        decision = router(self.request("IT", history=history))
        self.assertEqual(decision.decision, "needs_clarification")
        self.assertEqual(decision.reason_code, "ambiguous_known_department")
        self.assertEqual(decision.clarification, "Which department do you mean by IT?")

    def test_direct_department_reference_is_general_and_bounded(self):
        self.assertEqual(
            direct_department_reference(
                "I just started in the Legal department; what should I know?"
            ),
            "Legal",
        )
        self.assertEqual(
            direct_department_reference(
                "I just started in the Legal department can you tell me what "
                "policies I need to be aware of?"
            ),
            "Legal",
        )
        self.assertEqual(
            direct_department_reference("I work with the Human Resources dept."),
            "Human Resources",
        )
        self.assertEqual(
            direct_department_reference("Department: Human Capital"),
            "Human Capital",
        )
        self.assertIsNone(direct_department_reference("Tell me about policy departments."))

    def test_direct_department_catalog_routes_owned_and_related_documents(self):
        direct_rows = [
            (*self.document("1"), "Legal and Compliance", identity("a")),
            (*self.document("3"), "Legal and Compliance", identity("b")),
        ]
        related_rows = [
            (
                identity("5"),
                identity("6"),
                "policy.records-retention",
                "Records Retention Policy",
                identity("c"),
            )
        ]
        connection = _Connection(direct_rows, related_rows=related_rows)
        router = NativeKnownDocumentScopeRouter(lambda: connection)
        request = self.request(
            "I just started in the Legal department; what policies do I need to be aware of?"
        )
        decision = router(request)
        self.assertEqual(decision.decision, "allow")
        self.assertEqual(decision.reason_code, "known_department_catalog")
        policy = validate_query_resolution_profile(
            load_restricted_yaml(
                Path(__file__).resolve().parents[1]
                / "config/templates/query_resolution_profile.yaml",
                label="query resolution",
            )
        )
        resolution = router.resolve_query(request, policy)
        self.assertEqual(resolution.status, "resolved")
        self.assertEqual(len(resolution.source_constraints), 3)
        self.assertTrue(
            all(
                item.citation_id is not None
                for item in resolution.source_constraints
            )
        )
        self.assertIn("govern Legal and Compliance", resolution.resolved_query)
        self.assertIn("authorized supporting roles", resolution.resolved_query)
        self.assertIn("related documents", resolution.resolved_query)
        self.assertNotIn("Records Retention Policy", resolution.resolved_query)
        self.assertLess(len(resolution.resolved_query), 160)
        sql = "\n".join(item[0] for item in connection.calls)
        self.assertIn("known-document.department-related", sql)
        self.assertEqual(sql.count("citation.structural_path ->> 0"), 4)
        self.assertEqual(sql.count("citation.relevant_excerpt"), 4)
        self.assertNotIn("citation.structural_path[1]", sql)

    def test_department_catalog_intent_survives_multiple_clarifications(self):
        history = (
            {
                "turn_id": identity("c"),
                "role": "user",
                "content": (
                    "I just started in the Legal department; "
                    "what policies do I need to be aware of?"
                ),
            },
            {
                "turn_id": identity("d"),
                "role": "assistant",
                "content": "Which legal topics should be included?",
            },
            {
                "turn_id": identity("e"),
                "role": "user",
                "content": "All of them.",
            },
            {
                "turn_id": identity("f"),
                "role": "assistant",
                "content": "Which areas should be emphasized?",
            },
        )
        rows = [
            (*self.document("1"), "Legal and Compliance", identity("a"))
        ]
        connection = _Connection(rows)
        router = NativeKnownDocumentScopeRouter(lambda: connection)
        request = self.request(
            "Data privacy, contract management, and ethics.",
            history=history,
            references=(
                {
                    "citation_id": None,
                    "source_id": identity("9"),
                    "source_label": "Source 1",
                },
            ),
        )
        policy = validate_query_resolution_profile(
            load_restricted_yaml(
                Path(__file__).resolve().parents[1]
                / "config/templates/query_resolution_profile.yaml",
                label="query resolution",
            )
        )
        resolution = router.resolve_query(request, policy)
        self.assertEqual(resolution.status, "resolved")
        self.assertEqual(
            resolution.resolved_query,
            "Which documents govern Legal and Compliance and authorized "
            "supporting roles, with related documents?",
        )
        self.assertNotIn("All of them.", resolution.resolved_query)
        self.assertNotIn("Data privacy", resolution.resolved_query)

    def test_unique_department_prefix_is_required(self):
        rows = [
            (*self.document("1"), "Human Capital", identity("a")),
            (*self.document("3"), "Human Resources", identity("b")),
        ]
        router = NativeKnownDocumentScopeRouter(lambda: _Connection(rows))
        decision = router(
            self.request(
                "I just started in the Human department; "
                "what documents should I read?"
            )
        )
        self.assertEqual(decision.decision, "needs_clarification")
        self.assertEqual(decision.reason_code, "ambiguous_known_department")

    def test_prior_answer_does_not_leak_department_into_new_task(self):
        history = (
            {
                "turn_id": identity("c"),
                "role": "user",
                "content": "I work in the Legal department.",
            },
            {
                "turn_id": identity("d"),
                "role": "assistant",
                "content": "The requested policy list is available.",
            },
        )
        self.assertIsNone(
            NativeKnownDocumentScopeRouter(lambda: _Connection([]))(
                self.request("What forms are required?", history=history)
            )
        )


if __name__ == "__main__":
    unittest.main()
