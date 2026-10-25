from __future__ import annotations

import json
import unittest
from pathlib import Path

from ishikawa.canonical import canonical_json_bytes, domain_digest
from ishikawa.generation import ConversationTurn, GroundedEvidence, build_grounded_generation_request
from ishikawa.generation_transport import (
    GenerationEndpoint,
    GenerationHTTPResponse,
    GenerationResponseError,
    GenerationTransportError,
    execute_generation_request,
    prepare_generation_request,
    validate_generation_response,
)
from ishikawa.reconstruction import validate_reconstruction_profile
from ishikawa.yaml_loader import load_restricted_yaml


def identity(label: str) -> str:
    return domain_digest("ishikawa.generation-transport-test.v1", label)


class GenerationTransportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[1]
        policy = validate_reconstruction_profile(
            load_restricted_yaml(root / "config/templates/reconstruction_profile.yaml", label="profile")
        )
        item = GroundedEvidence(
            citation_id=identity("citation"),
            source_label="Source 1",
            excerpt="The operator records the completed review.",
            page_start=2,
            page_end=2,
            structural_path=("II. Review",),
        )
        cls.request = build_grounded_generation_request(
            conversation_id=identity("conversation"),
            turn_id=identity("turn"),
            history=(
                ConversationTurn("user", "What is reviewed?"),
                ConversationTurn("assistant", "The prior cited answer identified the review."),
            ),
            question="What must the operator record?",
            evidence=(item,),
            policy=policy,
        )
        cls.endpoint = GenerationEndpoint("http://127.0.0.1:8000/v1/chat/completions")

    def response(self, *, content=None, finish_reason="stop", citation_id=None, **changes):
        citation_id = citation_id or self.request.citation_aliases[0][0]
        content = content or json.dumps(
            {
                "segments": [
                    {
                        "text": "The operator records the completed review.",
                        "citation_ids": [citation_id],
                    }
                ],
            },
            separators=(",", ":"),
        )
        value = {
            "id": "chatcmpl-synthetic",
            "object": "chat.completion",
            "created": 1,
            "model": self.request.body["model"],
            "choices": [
                {
                    "index": 0,
                    "message": {"role": "assistant", "content": content, "reasoning": None},
                    "finish_reason": finish_reason,
                }
            ],
            "usage": {"prompt_tokens": 100, "completion_tokens": 20, "total_tokens": 120},
        }
        value.update(changes)
        return GenerationHTTPResponse(200, "application/json; charset=utf-8", canonical_json_bytes(value))

    def assert_response_reason(self, response, reason):
        with self.assertRaises(GenerationResponseError) as caught:
            validate_generation_response(response, self.request)
        self.assertEqual(caught.exception.reason_code, reason)

    def test_endpoint_is_exact_and_configurable(self):
        endpoint = GenerationEndpoint("https://ai.example.invalid:8443/v1/chat/completions", 90, 8192)
        self.assertEqual((endpoint.parsed.scheme, endpoint.parsed.port), ("https", 8443))

    def test_endpoint_rejects_credentials_query_fragment_and_wrong_path(self):
        for url in (
            "http://user:secret@127.0.0.1:8000/v1/chat/completions",
            "http://127.0.0.1:8000/v1/chat/completions?debug=1",
            "http://127.0.0.1:8000/v1/chat/completions#fragment",
            "http://127.0.0.1:8000/chat",
        ):
            with self.subTest(url=url), self.assertRaises(GenerationTransportError):
                GenerationEndpoint(url)

    def test_prepared_request_keeps_credential_out_of_body(self):
        prepared = prepare_generation_request(self.endpoint, self.request, "runtime-secret")
        self.assertEqual(prepared.headers["Authorization"], "Bearer runtime-secret")
        self.assertNotIn(b"runtime-secret", prepared.body)
        self.assertEqual(prepared.path, "/v1/chat/completions")

    def test_execute_uses_injected_exchange_without_retry(self):
        calls = []

        def exchange(prepared):
            calls.append(prepared)
            return self.response()

        answer = execute_generation_request(
            self.endpoint, self.request, "runtime-secret", exchange=exchange
        )
        self.assertEqual(len(calls), 1)
        self.assertEqual(answer.total_tokens, 120)

    def test_valid_grounded_answer_passes(self):
        answer = validate_generation_response(self.response(), self.request)
        self.assertEqual(len(answer.segments), 1)
        self.assertEqual(answer.segments[0].citation_ids, self.request.allowed_citation_ids)

    def test_outer_segment_whitespace_is_normalized_without_changing_prose(self):
        content = json.dumps(
            {
                "segments": [
                    {
                        "text": "  The operator records the completed review. \n",
                        "citation_ids": [self.request.citation_aliases[0][0]],
                    }
                ]
            },
            separators=(",", ":"),
        )
        answer = validate_generation_response(
            self.response(content=content), self.request
        )
        self.assertEqual(
            answer.segments[0].text,
            "The operator records the completed review.",
        )

    def test_missing_required_relationship_citation_group_is_rejected(self):
        policy = validate_reconstruction_profile(
            load_restricted_yaml(
                Path(__file__).resolve().parents[1]
                / "config/templates/reconstruction_profile.yaml",
                label="profile",
            )
        )
        direct = GroundedEvidence(
            identity("direct-citation"), "Source 1", "Direct evidence.", 1, 1,
            ("I. Direct",),
        )
        related = GroundedEvidence(
            identity("related-citation"), "Source 2", "Referenced evidence.",
            2, 2, ("II. Referenced",), "relationship",
            "explicit_reference_one_hop", True, identity("relationship-group"),
        )
        request = build_grounded_generation_request(
            conversation_id=identity("coverage-conversation"),
            turn_id=identity("coverage-turn"),
            history=(),
            question="What applies?",
            evidence=(direct, related),
            policy=policy,
        )
        content = json.dumps(
            {"segments": [{"text": "Direct evidence.", "citation_ids": ["C1"]}]},
            separators=(",", ":"),
        )
        response = self.response(content=content)
        value = json.loads(response.body)
        value["model"] = request.body["model"]
        with self.assertRaises(GenerationResponseError) as caught:
            validate_generation_response(
                GenerationHTTPResponse(
                    200, "application/json", canonical_json_bytes(value)
                ),
                request,
            )
        self.assertEqual(
            caught.exception.reason_code,
            "MODEL_REQUIRED_CITATION_GROUP_MISSING",
        )

    def test_null_additive_vllm_fields_are_accepted(self):
        response = self.response(
            ec_transfer_params=None,
            kv_transfer_params=None,
            metrics=None,
            prompt_text=None,
        )
        value = json.loads(response.body)
        value["choices"][0]["routed_experts"] = None
        value["choices"][0]["message"]["annotations"] = None
        answer = validate_generation_response(
            GenerationHTTPResponse(200, "application/json", canonical_json_bytes(value)),
            self.request,
        )
        self.assertEqual(answer.finish_reason, "stop")

    def test_nonempty_private_vllm_fields_are_rejected(self):
        response = self.response(metrics={"private": 1})
        self.assert_response_reason(response, "MODEL_UNAUTHORIZED_OUTPUT_CHANNEL")

    def test_non_200_and_wrong_content_type_fail_closed(self):
        self.assert_response_reason(
            GenerationHTTPResponse(503, "application/json", b"{}"), "UPSTREAM_HTTP_ERROR"
        )
        self.assert_response_reason(
            GenerationHTTPResponse(200, "text/plain", b"{}"), "UPSTREAM_CONTENT_TYPE_INVALID"
        )

    def test_duplicate_json_field_is_rejected(self):
        body = b'{"id":"a","id":"b"}'
        self.assert_response_reason(
            GenerationHTTPResponse(200, "application/json", body),
            "MODEL_JSON_DUPLICATE_FIELD",
        )

    def test_wrong_model_is_rejected(self):
        self.assert_response_reason(self.response(model="different-model"), "UPSTREAM_SCHEMA_INVALID")

    def test_length_finish_is_rejected(self):
        self.assert_response_reason(self.response(finish_reason="length"), "MODEL_COMPLETION_INCOMPLETE")

    def test_reasoning_and_tool_output_are_rejected(self):
        response = self.response()
        value = json.loads(response.body)
        value["choices"][0]["message"]["reasoning"] = "private reasoning"
        self.assert_response_reason(
            GenerationHTTPResponse(200, "application/json", canonical_json_bytes(value)),
            "MODEL_UNAUTHORIZED_OUTPUT_CHANNEL",
        )

    def test_one_isolated_json_fence_is_accepted(self):
        raw = json.loads(self.response().body)
        raw["choices"][0]["message"]["content"] = (
            "```json\n" + raw["choices"][0]["message"]["content"] + "\n```"
        )
        answer = validate_generation_response(
            GenerationHTTPResponse(200, "application/json", canonical_json_bytes(raw)),
            self.request,
        )
        self.assertEqual(answer.answer, "The operator records the completed review.")

    def test_json_fence_with_surrounding_prose_is_rejected(self):
        raw = json.loads(self.response().body)
        content = raw["choices"][0]["message"]["content"]
        for wrapped in (
            f"Here is the answer:\n```json\n{content}\n```",
            f"```json\n{content}\n```\n",
            f"```JSON\n{content}\n```",
            f"```json\n{content}\n```\n```json\n{content}\n```",
        ):
            with self.subTest(content=wrapped):
                self.assert_response_reason(
                    self.response(content=wrapped), "MODEL_OUTPUT_JSON_INVALID"
                )

    def test_unknown_citation_is_rejected(self):
        self.assert_response_reason(
            self.response(citation_id="C999"), "MODEL_CITATION_NOT_ALLOWED"
        )

    def test_competing_answer_field_is_rejected(self):
        content = json.dumps(
            {
                "answer": "Uncited introduction. The operator records the completed review.",
                "segments": [
                    {
                        "text": "The operator records the completed review.",
                        "citation_ids": [self.request.citation_aliases[0][0]],
                    }
                ],
            },
            separators=(",", ":"),
        )
        self.assert_response_reason(
            self.response(content=content), "MODEL_OUTPUT_SCHEMA_INVALID"
        )

    def test_usage_must_balance_and_respect_answer_reserve(self):
        response = self.response()
        value = json.loads(response.body)
        value["usage"]["total_tokens"] = 121
        self.assert_response_reason(
            GenerationHTTPResponse(200, "application/json", canonical_json_bytes(value)),
            "UPSTREAM_USAGE_INVALID",
        )
        value["usage"] = {
            "prompt_tokens": 100,
            "completion_tokens": 2049,
            "total_tokens": 2149,
        }
        self.assert_response_reason(
            GenerationHTTPResponse(200, "application/json", canonical_json_bytes(value)),
            "UPSTREAM_USAGE_INVALID",
        )

    def test_unknown_response_field_is_rejected(self):
        self.assert_response_reason(self.response(private_path="/private"), "UPSTREAM_SCHEMA_INVALID")


if __name__ == "__main__":
    unittest.main()
