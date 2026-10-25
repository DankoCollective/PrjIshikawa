from __future__ import annotations

import json
import unittest
from pathlib import Path

from ishikawa.api_contract import decode_chat_request, validate_api_profile
from ishikawa.canonical import canonical_json_bytes
from ishikawa.generation_transport import GenerationEndpoint, GenerationHTTPResponse
from ishikawa.query_resolution import (
    QueryResolutionResponseError,
    ResolvedSourceConstraint,
    build_query_resolution_request,
    deterministic_resolution,
    validate_query_resolution_content,
    validate_query_resolution_profile,
)
from ishikawa.query_resolution_transport import NativeQueryResolutionAdapter
from ishikawa.retrieval_service import (
    QueryResolutionUnavailable,
    RetrievalDependencyUnavailable,
)
from ishikawa.yaml_loader import load_restricted_yaml


def ident(character: str) -> str:
    return character * 64


class QueryResolutionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[1]
        cls.api_policy = validate_api_profile(
            load_restricted_yaml(root / "config/templates/api_profile.yaml", label="api")
        )
        cls.policy = validate_query_resolution_profile(
            load_restricted_yaml(
                root / "config/templates/query_resolution_profile.yaml",
                label="query resolution",
            )
        )
        cls.endpoint = GenerationEndpoint(
            "http://127.0.0.1:8000/v1/chat/completions"
        )

    def request(
        self,
        message: str = "What else does Source 1 say?",
        *,
        history: bool = True,
        references: int = 1,
    ):
        value = {
            "conversation_id": ident("a"),
            "filters": {
                "document_classes": ["policy_sop"],
                "document_keys": ["procedure.incident-reporting"],
            },
            "history": (
                [
                    {"content": "How are incidents reported?", "role": "user", "turn_id": ident("b")},
                    {"content": "The prior answer cited Source 1.", "role": "assistant", "turn_id": ident("c")},
                ]
                if history
                else []
            ),
            "message": message,
            "schema": "ishikawa.chat-request.v1",
            "source_references": [
                {
                    "citation_id": ident(("f", "a")[index]),
                    "source_id": ident(("d", "e")[index]),
                    "source_label": f"Source {index + 1}",
                }
                for index in range(references)
            ],
            "turn_id": ident("9"),
        }
        return decode_chat_request(canonical_json_bytes(value), self.api_policy)

    def constraints(self, request):
        return tuple(
            ResolvedSourceConstraint(
                item.source_id,
                item.source_label,
                "Incident Reporting Procedure" if index == 0 else "Records Regulation",
                item.citation_id,
            )
            for index, item in enumerate(request.source_references)
        )

    def model_request(self, request):
        return build_query_resolution_request(
            request=request,
            source_constraints=self.constraints(request),
            policy=self.policy,
        )

    def content(self, **changes):
        value = {
            "ambiguity": "none",
            "clarification": None,
            "referenced_source_labels": ["Source 1"],
            "resolved_query": "What additional incident reporting requirements apply?",
        }
        value.update(changes)
        return json.dumps(value, separators=(",", ":"))

    def completion(self, content: str):
        body = {
            "choices": [
                {
                    "finish_reason": "stop",
                    "index": 0,
                    "message": {"content": content, "reasoning": None, "role": "assistant"},
                }
            ],
            "created": 1,
            "id": "query-resolution",
            "model": self.policy.served_model,
            "object": "chat.completion",
            "usage": {"completion_tokens": 25, "prompt_tokens": 100, "total_tokens": 125},
        }
        return GenerationHTTPResponse(200, "application/json", canonical_json_bytes(body))

    def test_tracked_profile_freezes_publisher_settings_and_limits(self):
        self.assertEqual(self.policy.temperature, 1.0)
        self.assertEqual(self.policy.top_p, 0.95)
        self.assertEqual(self.policy.top_k, 64)
        self.assertEqual(self.policy.maximum_history_turns, 12)

    def test_direct_question_bypasses_model_and_preserves_filters(self):
        request = self.request("How are incidents reported?", history=False, references=0)
        result = deterministic_resolution(request, self.policy)
        self.assertIsNotNone(result)
        self.assertEqual(result.status, "resolved")
        self.assertEqual(result.original_query, result.resolved_query)
        self.assertEqual(result.filters, request.filters)
        self.assertFalse(result.used_model)

    def test_unresolved_explicit_source_label_requests_clarification_without_model(self):
        request = self.request("What does Source 2 say?", references=1)
        result = deterministic_resolution(request, self.policy)
        self.assertEqual(result.status, "needs_clarification")
        self.assertIsNone(result.resolved_query)
        self.assertIn("Source 2", result.clarification)
        self.assertFalse(result.used_model)

    def test_model_request_separates_instructions_payload_filters_and_trusted_source_map(self):
        request = self.request()
        model_request = self.model_request(request)
        payload = json.loads(model_request.body["messages"][1]["content"])
        self.assertIn("Do not answer", model_request.body["messages"][0]["content"])
        self.assertEqual(payload["required_referenced_source_labels"], ["Source 1"])
        self.assertEqual(payload["explicit_filters"], request.filters.canonical())
        self.assertEqual(
            payload["source_references"][0]["display_name"],
            "Incident Reporting Procedure",
        )
        self.assertFalse(model_request.body["stream"])
        response_format = model_request.body["response_format"]
        self.assertEqual(response_format["type"], "json_schema")
        self.assertEqual(
            response_format["json_schema"]["name"],
            "ishikawa_query_resolution",
        )
        schema = response_format["json_schema"]["schema"]
        self.assertTrue(response_format["json_schema"]["strict"])
        self.assertFalse(schema["additionalProperties"])
        self.assertEqual(
            schema["properties"]["referenced_source_labels"]["items"]["enum"],
            ["Source 1"],
        )

    def test_implicit_followup_with_multiple_prior_sources_forces_no_source_label(self):
        request = self.request(
            "A credential exposure.",
            references=2,
        )
        model_request = self.model_request(request)
        self.assertEqual(model_request.allowed_source_labels, ())
        label_schema = model_request.body["response_format"]["json_schema"][
            "schema"
        ]["properties"]["referenced_source_labels"]
        self.assertEqual(label_schema["maxItems"], 0)
        self.assertNotIn("enum", label_schema["items"])
        self.assertNotIn("uniqueItems", label_schema)

    def test_exact_four_turn_three_source_followup_uses_xgrammar_compatible_schema(self):
        value = {
            "conversation_id": ident("a"),
            "filters": {"document_classes": [], "document_keys": []},
            "history": [
                {
                    "content": "I need to report an IT security incident.",
                    "role": "user",
                    "turn_id": ident("b"),
                },
                {
                    "content": (
                        "The Security Event Reporting Procedure applies. The Incident "
                        "Reporting and Response Procedure and Incident Classification "
                        "Policy may also apply."
                    ),
                    "role": "assistant",
                    "turn_id": ident("c"),
                },
                {
                    "content": "What forms do I need to complete?",
                    "role": "user",
                    "turn_id": ident("4"),
                },
                {
                    "content": (
                        "Are you reporting suspected misuse, device loss, credential "
                        "exposure, or a controlled-materials incident?"
                    ),
                    "role": "assistant",
                    "turn_id": ident("5"),
                },
            ],
            "message": "A credential exposure.",
            "schema": "ishikawa.chat-request.v1",
            "source_references": [
                {
                    "citation_id": None,
                    "source_id": ident(character),
                    "source_label": f"Source {index}",
                }
                for index, character in enumerate(("d", "e", "f"), start=1)
            ],
            "turn_id": ident("9"),
        }
        request = decode_chat_request(canonical_json_bytes(value), self.api_policy)
        constraints = tuple(
            ResolvedSourceConstraint(
                item.source_id,
                item.source_label,
                (
                    "Security Event Reporting Procedure",
                    "Incident Reporting and Response Procedure",
                    "Incident Classification Policy",
                )[index],
                item.citation_id,
            )
            for index, item in enumerate(request.source_references)
        )
        model_request = build_query_resolution_request(
            request=request,
            source_constraints=constraints,
            policy=self.policy,
        )
        label_schema = model_request.body["response_format"]["json_schema"][
            "schema"
        ]["properties"]["referenced_source_labels"]
        payload = json.loads(model_request.body["messages"][1]["content"])
        self.assertEqual(model_request.allowed_source_labels, ())
        self.assertEqual(label_schema["maxItems"], 0)
        self.assertNotIn("uniqueItems", label_schema)
        self.assertEqual(
            payload["latest_prior_user_request"],
            "What forms do I need to complete?",
        )
        self.assertIn(
            "Preserve the prior user's requested task",
            model_request.body["messages"][0]["content"],
        )

        calls = []

        def exchange(prepared):
            calls.append(prepared)
            return self.completion(
                self.content(
                    referenced_source_labels=[],
                    resolved_query=(
                        "What forms are required for reporting a credential exposure "
                        "under the Security Event Reporting Procedure?"
                    ),
                )
            )

        names = {
            item.source_id: constraint.display_name
            for item, constraint in zip(request.source_references, constraints)
        }
        adapter = NativeQueryResolutionAdapter(
            self.endpoint,
            self.policy,
            lambda: "runtime-secret",
            lambda reference: names[reference.source_id],
            exchange,
            lambda _request, _policy: None,
        )
        result = adapter(request)
        self.assertEqual(result.status, "resolved")
        self.assertTrue(result.used_model)
        self.assertIn("forms", result.resolved_query.casefold())
        self.assertEqual(len(calls), 1)

    def test_clarification_answer_cannot_erase_prior_requested_task(self):
        value = {
            "conversation_id": ident("a"),
            "filters": {"document_classes": [], "document_keys": []},
            "history": [
                {"content": "What forms do I need to complete?", "role": "user", "turn_id": ident("4")},
                {"content": "Which incident type applies?", "role": "assistant", "turn_id": ident("5")},
            ],
            "message": "A credential exposure.",
            "schema": "ishikawa.chat-request.v1",
            "source_references": [],
            "turn_id": ident("9"),
        }
        request = decode_chat_request(canonical_json_bytes(value), self.api_policy)
        model_request = build_query_resolution_request(
            request=request,
            source_constraints=(),
            policy=self.policy,
        )
        result = validate_query_resolution_content(
            self.content(
                referenced_source_labels=[],
                resolved_query="How should a credential exposure be reported?",
            ),
            request,
            model_request,
            self.policy,
        )
        self.assertIn("What forms do I need to complete?", result.resolved_query)
        self.assertIn("credential exposure", result.resolved_query)

    def test_valid_followup_maps_label_to_exact_source_and_citation_identities(self):
        request = self.request()
        result = validate_query_resolution_content(
            self.content(), request, self.model_request(request), self.policy
        )
        self.assertEqual(result.status, "resolved")
        self.assertEqual(result.source_constraints[0].source_id, ident("d"))
        self.assertEqual(result.source_constraints[0].citation_id, ident("f"))
        self.assertEqual(result.filters, request.filters)
        self.assertTrue(result.used_model)

    def test_required_source_cannot_be_omitted_or_substituted(self):
        request = self.request(references=2)
        model_request = self.model_request(request)
        for labels in ([], ["Source 2"], ["Source 1", "Source 2"]):
            with self.subTest(labels=labels), self.assertRaises(QueryResolutionResponseError):
                validate_query_resolution_content(
                    self.content(referenced_source_labels=labels),
                    request,
                    model_request,
                    self.policy,
                )

    def test_literal_source_label_cannot_reach_retrieval_query(self):
        request = self.request()
        with self.assertRaises(QueryResolutionResponseError):
            validate_query_resolution_content(
                self.content(resolved_query="What else does source 1 say?"),
                request,
                self.model_request(request),
                self.policy,
            )

    def test_material_ambiguity_returns_only_a_clarification(self):
        request = self.request("What does that say?", references=2)
        result = validate_query_resolution_content(
            self.content(
                ambiguity="material",
                clarification="Which source do you mean?",
                referenced_source_labels=[],
                resolved_query=None,
            ),
            request,
            self.model_request(request),
            self.policy,
        )
        self.assertEqual(result.status, "needs_clarification")
        self.assertIsNone(result.resolved_query)

    def test_answer_and_unknown_fields_fail_closed(self):
        request = self.request()
        value = json.loads(self.content())
        value["answer"] = "Invented answer"
        with self.assertRaises(QueryResolutionResponseError):
            validate_query_resolution_content(
                json.dumps(value), request, self.model_request(request), self.policy
            )

    def test_native_adapter_calls_one_exchange_and_keeps_credential_out_of_body(self):
        request = self.request()
        calls = []

        def exchange(prepared):
            calls.append(prepared)
            return self.completion(self.content())

        adapter = NativeQueryResolutionAdapter(
            self.endpoint,
            self.policy,
            lambda: "runtime-secret",
            lambda _reference: "Incident Reporting Procedure",
            exchange,
        )
        result = adapter(request)
        self.assertEqual(result.status, "resolved")
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0].headers["Authorization"], "Bearer runtime-secret")
        self.assertNotIn(b"runtime-secret", calls[0].body)

    def test_direct_adapter_does_not_read_credentials_or_call_endpoint(self):
        request = self.request("How are incidents reported?", history=False, references=0)

        def forbidden():
            self.fail("credential provider must not be called")

        adapter = NativeQueryResolutionAdapter(
            self.endpoint,
            self.policy,
            forbidden,
            lambda _reference: self.fail("source resolver must not be called"),
            lambda _prepared: self.fail("endpoint must not be called"),
        )
        self.assertFalse(adapter(request).used_model)

    def test_transport_failure_maps_to_dependency_unavailable(self):
        adapter = NativeQueryResolutionAdapter(
            self.endpoint,
            self.policy,
            lambda: "runtime-secret",
            lambda _reference: "Incident Reporting Procedure",
            lambda _prepared: (_ for _ in ()).throw(OSError("private")),
        )
        with self.assertRaises(QueryResolutionUnavailable) as caught:
            adapter(self.request())
        self.assertIsInstance(caught.exception, RetrievalDependencyUnavailable)
        self.assertEqual(
            caught.exception.failure_stage,
            "query-resolution-transport-failed",
        )

    def test_invalid_model_response_has_distinct_observable_failure_stage(self):
        adapter = NativeQueryResolutionAdapter(
            self.endpoint,
            self.policy,
            lambda: "runtime-secret",
            lambda _reference: "Incident Reporting Procedure",
            lambda _prepared: self.completion('{"unexpected":true}'),
        )
        with self.assertRaises(QueryResolutionUnavailable) as caught:
            adapter(self.request())
        self.assertEqual(
            caught.exception.failure_stage,
            "query-resolution-response-invalid",
        )

    def test_invalid_http_response_has_distinct_observable_failure_stage(self):
        adapter = NativeQueryResolutionAdapter(
            self.endpoint,
            self.policy,
            lambda: "runtime-secret",
            lambda _reference: "Incident Reporting Procedure",
            lambda _prepared: GenerationHTTPResponse(
                400,
                "application/json",
                b'{"error":"unsupported structured-output schema"}',
            ),
        )
        with self.assertRaises(QueryResolutionUnavailable) as caught:
            adapter(self.request())
        self.assertEqual(
            caught.exception.failure_stage,
            "query-resolution-response-invalid",
        )


if __name__ == "__main__":
    unittest.main()
