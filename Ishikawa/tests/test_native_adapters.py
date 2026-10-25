from __future__ import annotations

import json
import math
import unittest
from pathlib import Path

from ishikawa.api_contract import decode_chat_request, validate_api_profile
from ishikawa.canonical import canonical_json_bytes
from ishikawa.generation import GroundedEvidence
from ishikawa.generation_transport import GenerationEndpoint, GenerationHTTPResponse
from ishikawa.native_adapters import (
    ACCEPTED_EMBEDDING_SPACE_ID,
    EMBEDDING_DIMENSION,
    NOMIC_MODEL,
    QUERY_PREFIX,
    EmbeddingEndpoint,
    EmbeddingHTTPResponse,
    EmbeddingResponseError,
    EmbeddingTransportError,
    NativeGenerationAdapter,
    NativeQueryEmbeddingAdapter,
    NativeScopeAdapter,
    build_query_embedding_request,
    execute_query_embedding_request,
    prepare_query_embedding_request,
    validate_query_embedding_response,
)
from ishikawa.reconstruction import validate_reconstruction_profile
from ishikawa.retrieval_service import (
    GroundedGenerationRetryableUnavailable,
    RetrievalDependencyUnavailable,
)
from ishikawa.scope import ScopeDecision, validate_scope_profile
from ishikawa.yaml_loader import load_restricted_yaml


def ident(character: str) -> str:
    return character * 64


class NativeAdapterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[1]
        cls.api_policy = validate_api_profile(
            load_restricted_yaml(root / "config/templates/api_profile.yaml", label="api")
        )
        cls.scope_policy = validate_scope_profile(
            load_restricted_yaml(root / "config/templates/scope_profile.yaml", label="scope")
        )
        cls.reconstruction_policy = validate_reconstruction_profile(
            load_restricted_yaml(
                root / "config/templates/reconstruction_profile.yaml", label="reconstruction"
            )
        )
        cls.embedding_endpoint = EmbeddingEndpoint(
            "http://127.0.0.1:8001/v1/embeddings"
        )
        cls.generation_endpoint = GenerationEndpoint(
            "http://127.0.0.1:8000/v1/chat/completions"
        )

    def request(self):
        return decode_chat_request(
            canonical_json_bytes(
                {
                    "conversation_id": ident("a"),
                    "filters": {"document_classes": [], "document_keys": []},
                    "history": [
                        {"content": "What is required?", "role": "user", "turn_id": ident("b")},
                        {"content": "The prior answer cited Source 1.", "role": "assistant", "turn_id": ident("c")},
                    ],
                    "message": "What else does Source 1 say?",
                    "schema": "ishikawa.chat-request.v1",
                    "source_references": [
                        {"citation_id": ident("f"), "source_id": ident("e"), "source_label": "Source 1"}
                    ],
                    "turn_id": ident("d"),
                }
            ),
            self.api_policy,
        )

    def embedding_response(self, **changes):
        value = {
            "data": [
                {"embedding": [1.0] * EMBEDDING_DIMENSION, "index": 0, "object": "embedding"}
            ],
            "model": NOMIC_MODEL,
            "object": "list",
            "usage": {"prompt_tokens": 12, "total_tokens": 12},
        }
        value.update(changes)
        return EmbeddingHTTPResponse(200, "application/json", canonical_json_bytes(value))

    def test_embedding_endpoint_is_configurable_and_exact(self):
        endpoint = EmbeddingEndpoint("https://ai.example.invalid:8443/v1/embeddings", 90, 131072)
        self.assertEqual(endpoint.parsed.hostname, "ai.example.invalid")
        self.assertEqual(endpoint.parsed.port, 8443)

    def test_embedding_endpoint_rejects_credentials_query_fragment_and_wrong_path(self):
        for url in (
            "http://user:secret@127.0.0.1:8001/v1/embeddings",
            "http://127.0.0.1:8001/v1/embeddings?debug=1",
            "http://127.0.0.1:8001/v1/embeddings#fragment",
            "http://127.0.0.1:8001/embeddings",
        ):
            with self.subTest(url=url), self.assertRaises(EmbeddingTransportError):
                EmbeddingEndpoint(url)

    def test_query_request_is_singleton_prefixed_and_credential_is_header_only(self):
        request = build_query_embedding_request("What is required?")
        prepared = prepare_query_embedding_request(
            self.embedding_endpoint, request, "runtime-secret"
        )
        self.assertEqual(request.body["input"], QUERY_PREFIX + "What is required?")
        self.assertIsInstance(request.body["input"], str)
        self.assertEqual(request.embedding_space_id, ACCEPTED_EMBEDDING_SPACE_ID)
        self.assertEqual(prepared.headers["Authorization"], "Bearer runtime-secret")
        self.assertNotIn(b"runtime-secret", prepared.body)

    def test_valid_single_query_embedding_response_passes(self):
        request = build_query_embedding_request("What is required?")
        responses = (
            self.embedding_response(),
            self.embedding_response(
                created=1,
                id="embd-qualification",
                usage={
                    "completion_tokens": 0,
                    "prompt_tokens": 12,
                    "prompt_tokens_details": None,
                    "total_tokens": 12,
                },
            ),
            self.embedding_response(
                created=1,
                id="embd-qualification",
                usage={
                    "completion_tokens": 0,
                    "prompt_tokens": 12,
                    "prompt_tokens_details": {"cached_tokens": 0},
                    "total_tokens": 12,
                },
            ),
        )
        for response in responses:
            with self.subTest():
                result = validate_query_embedding_response(response, request)
                self.assertEqual(len(result.vector), EMBEDDING_DIMENSION)
                self.assertEqual(result.prompt_tokens, 12)
                self.assertEqual(result.embedding_space_id, ACCEPTED_EMBEDDING_SPACE_ID)

    def test_embedding_envelope_model_and_cardinality_fail_closed(self):
        request = build_query_embedding_request("What is required?")
        for response in (
            EmbeddingHTTPResponse(503, "application/json", b"{}"),
            self.embedding_response(model="wrong"),
            self.embedding_response(data=[]),
        ):
            with self.subTest(), self.assertRaises(EmbeddingResponseError):
                validate_query_embedding_response(response, request)

    def test_embedding_vector_and_usage_fail_closed(self):
        request = build_query_embedding_request("What is required?")
        value = json.loads(self.embedding_response().body)
        value["data"][0]["embedding"][0] = math.nan
        bad_vector = EmbeddingHTTPResponse(200, "application/json", json.dumps(value).encode())
        bad_usage = self.embedding_response(usage={"prompt_tokens": 12, "total_tokens": 13})
        bad_completion_usage = self.embedding_response(
            usage={
                "completion_tokens": 1,
                "prompt_tokens": 12,
                "prompt_tokens_details": None,
                "total_tokens": 12,
            }
        )
        bad_prompt_details = self.embedding_response(
            usage={
                "completion_tokens": 0,
                "prompt_tokens": 12,
                "prompt_tokens_details": {"unrecognized": 0},
                "total_tokens": 12,
            }
        )
        bad_created = self.embedding_response(created=True)
        bad_identifier = self.embedding_response(id="")
        unknown_envelope = self.embedding_response(unrecognized=None)
        for response in (
            bad_vector,
            bad_usage,
            bad_completion_usage,
            bad_prompt_details,
            bad_created,
            bad_identifier,
            unknown_envelope,
        ):
            with self.subTest(), self.assertRaises(EmbeddingResponseError):
                validate_query_embedding_response(response, request)

    def test_query_embedding_executes_one_injected_exchange_without_retry(self):
        calls = []

        def exchange(prepared):
            calls.append(prepared)
            return self.embedding_response()

        result = execute_query_embedding_request(
            self.embedding_endpoint,
            build_query_embedding_request("What is required?"),
            "runtime-secret",
            exchange=exchange,
        )
        self.assertEqual(len(calls), 1)
        self.assertEqual(result.prompt_tokens, 12)

    def test_scope_adapter_builds_typed_history_and_resolved_source_metadata(self):
        calls = []

        def exchange(prepared):
            calls.append(json.loads(prepared.body))
            content = json.dumps(
                {"clarification": None, "decision": "allow", "reason_code": "prior_answer_or_source_followup"},
                separators=(",", ":"),
            )
            body = {
                "choices": [{"finish_reason": "stop", "index": 0, "message": {"content": content, "reasoning": None, "role": "assistant"}}],
                "created": 1,
                "id": "scope",
                "model": self.scope_policy.served_model,
                "object": "chat.completion",
                "usage": {"completion_tokens": 20, "prompt_tokens": 527, "total_tokens": 547},
            }
            return GenerationHTTPResponse(200, "application/json", canonical_json_bytes(body))

        adapter = NativeScopeAdapter(
            self.generation_endpoint,
            self.scope_policy,
            lambda: "runtime-secret",
            lambda _reference: "Incident Reporting Procedure",
            exchange,
        )
        decision = adapter(self.request())
        self.assertEqual(decision.decision, "allow")
        payload = json.loads(calls[0]["messages"][1]["content"])
        self.assertEqual(payload["source_references"][0]["display_name"], "Incident Reporting Procedure")

    def test_scope_adapter_uses_known_document_route_without_model_or_credential(self):
        calls = []

        def route(_request):
            calls.append("route")
            return ScopeDecision("allow", "known_document_reference", None)

        adapter = NativeScopeAdapter(
            self.generation_endpoint,
            self.scope_policy,
            lambda: self.fail("credential must not be read"),
            lambda _reference: self.fail("source resolver must not be called"),
            lambda _prepared: self.fail("model endpoint must not be called"),
            route,
        )
        decision = adapter(self.request())
        self.assertEqual(decision.decision, "allow")
        self.assertEqual(calls, ["route"])

    def test_generation_adapter_builds_grounded_request_and_validates_segments(self):
        calls = []
        evidence = GroundedEvidence(ident("f"), "Source 1", "Reports are submitted promptly.", 2, 2, ("Reporting",))

        def exchange(prepared):
            calls.append(json.loads(prepared.body))
            content = json.dumps(
                {"segments": [{"citation_ids": ["C1"], "text": "Reports are submitted promptly."}]},
                separators=(",", ":"),
            )
            body = {
                "choices": [{"finish_reason": "stop", "index": 0, "message": {"content": content, "reasoning": None, "role": "assistant"}}],
                "created": 1,
                "id": "generation",
                "model": self.reconstruction_policy.tokenizer_model,
                "object": "chat.completion",
                "usage": {"completion_tokens": 20, "prompt_tokens": 100, "total_tokens": 120},
            }
            return GenerationHTTPResponse(200, "application/json", canonical_json_bytes(body))

        adapter = NativeGenerationAdapter(
            self.generation_endpoint,
            self.reconstruction_policy,
            lambda: "runtime-secret",
            exchange,
        )
        result = adapter(
            self.request(),
            "What forms are required for a credential exposure?",
            (evidence,),
        )
        self.assertEqual(result.segments[0].citation_ids, (ident("f"),))
        self.assertEqual(len(calls), 1)
        payload = json.loads(calls[0]["messages"][1]["content"])
        self.assertEqual(
            payload["question"],
            "What forms are required for a credential exposure?",
        )

    def test_generation_adapter_marks_transport_failure_as_retryable(self):
        evidence = GroundedEvidence(
            ident("f"),
            "Source 1",
            "Reports are submitted promptly.",
            2,
            2,
            ("Reporting",),
        )
        adapter = NativeGenerationAdapter(
            self.generation_endpoint,
            self.reconstruction_policy,
            lambda: "runtime-secret",
            lambda _prepared: (_ for _ in ()).throw(OSError("private")),
        )
        with self.assertRaises(GroundedGenerationRetryableUnavailable) as caught:
            adapter(self.request(), "How are incidents reported?", (evidence,))
        self.assertEqual(caught.exception.failure_stage, "generation-transport-failed")

    def test_generation_adapter_marks_invalid_model_response_as_retryable(self):
        evidence = GroundedEvidence(
            ident("f"),
            "Source 1",
            "Reports are submitted promptly.",
            2,
            2,
            ("Reporting",),
        )
        body = {
            "choices": [
                {
                    "finish_reason": "length",
                    "index": 0,
                    "message": {
                        "content": '{"segments":[]}',
                        "reasoning": None,
                        "role": "assistant",
                    },
                }
            ],
            "created": 1,
            "id": "generation",
            "model": self.reconstruction_policy.tokenizer_model,
            "object": "chat.completion",
            "usage": {
                "completion_tokens": 20,
                "prompt_tokens": 100,
                "total_tokens": 120,
            },
        }
        adapter = NativeGenerationAdapter(
            self.generation_endpoint,
            self.reconstruction_policy,
            lambda: "runtime-secret",
            lambda _prepared: GenerationHTTPResponse(
                200, "application/json", canonical_json_bytes(body)
            ),
        )
        with self.assertRaises(GroundedGenerationRetryableUnavailable) as caught:
            adapter(self.request(), "How are incidents reported?", (evidence,))
        self.assertEqual(caught.exception.failure_stage, "generation-response-invalid")

    def test_missing_credentials_and_transport_failures_become_dependency_unavailable(self):
        adapter = NativeQueryEmbeddingAdapter(
            self.embedding_endpoint,
            lambda: "",
            lambda _prepared: self.embedding_response(),
        )
        with self.assertRaises(RetrievalDependencyUnavailable):
            adapter("What is required?")

        adapter = NativeQueryEmbeddingAdapter(
            self.embedding_endpoint,
            lambda: "runtime-secret",
            lambda _prepared: (_ for _ in ()).throw(OSError("private")),
        )
        with self.assertRaises(RetrievalDependencyUnavailable):
            adapter("What is required?")


if __name__ == "__main__":
    unittest.main()

