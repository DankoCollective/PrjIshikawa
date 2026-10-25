from __future__ import annotations

import json
import unittest
from pathlib import Path

from ishikawa.canonical import canonical_json_bytes, domain_digest
from ishikawa.generation import ConversationTurn
from ishikawa.generation_transport import (
    GenerationEndpoint,
    GenerationHTTPResponse,
    GenerationResponseError,
)
from ishikawa.scope import ScopeResponseError, ScopeSourceReference, build_scope_request, validate_scope_profile
from ishikawa.scope_transport import execute_scope_request, prepare_scope_request, validate_scope_response
from ishikawa.yaml_loader import load_restricted_yaml


def identity(label: str) -> str:
    return domain_digest("ishikawa.scope-transport-test.v1", label)


class ScopeTransportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[1]
        cls.policy = validate_scope_profile(
            load_restricted_yaml(root / "config/templates/scope_profile.yaml", label="scope profile")
        )
        cls.request = build_scope_request(
            conversation_id=identity("conversation"),
            turn_id=identity("turn"),
            history=(
                ConversationTurn("user", "What is the deadline?"),
                ConversationTurn("assistant", "The prior cited answer identified it."),
            ),
            question="What else does Source 1 say?",
            source_references=(
                ScopeSourceReference(identity("source"), "Source 1", "Synthetic Procedure"),
            ),
            policy=cls.policy,
        )
        cls.endpoint = GenerationEndpoint("http://127.0.0.1:8000/v1/chat/completions")

    def response(self, *, content=None, finish_reason="stop", **changes):
        content = content or json.dumps(
            {
                "clarification": None,
                "decision": "allow",
                "reason_code": "prior_answer_or_source_followup",
            },
            separators=(",", ":"),
        )
        value = {
            "id": "chatcmpl-synthetic-scope",
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
            "usage": {"prompt_tokens": 527, "completion_tokens": 20, "total_tokens": 547},
        }
        value.update(changes)
        return GenerationHTTPResponse(200, "application/json", canonical_json_bytes(value))

    def test_prepared_request_keeps_credential_out_of_body(self):
        prepared = prepare_scope_request(self.endpoint, self.request, "runtime-secret")
        self.assertEqual(prepared.headers["Authorization"], "Bearer runtime-secret")
        self.assertNotIn(b"runtime-secret", prepared.body)
        self.assertEqual(prepared.body, self.request.canonical_bytes())

    def test_valid_scope_result_passes(self):
        result = validate_scope_response(self.response(), self.request, self.policy)
        self.assertEqual(result.decision.decision, "allow")
        self.assertEqual(result.decision.reason_code, "prior_answer_or_source_followup")
        self.assertEqual(result.total_tokens, 547)

    def test_execute_calls_exchange_once(self):
        calls = []

        def exchange(prepared):
            calls.append(prepared)
            return self.response()

        result = execute_scope_request(
            self.endpoint, self.request, self.policy, "runtime-secret", exchange=exchange
        )
        self.assertEqual(len(calls), 1)
        self.assertEqual(result.finish_reason, "stop")

    def test_envelope_and_usage_fail_closed(self):
        with self.assertRaises(GenerationResponseError):
            validate_scope_response(self.response(finish_reason="length"), self.request, self.policy)
        response = self.response()
        value = json.loads(response.body)
        value["usage"]["completion_tokens"] = 129
        value["usage"]["total_tokens"] = value["usage"]["prompt_tokens"] + 129
        with self.assertRaises(GenerationResponseError):
            validate_scope_response(
                GenerationHTTPResponse(200, "application/json", canonical_json_bytes(value)),
                self.request,
                self.policy,
            )

    def test_scope_decision_and_reason_fail_closed(self):
        content = '{"clarification":null,"decision":"allow","reason_code":"personal_or_recreational"}'
        with self.assertRaises(ScopeResponseError):
            validate_scope_response(self.response(content=content), self.request, self.policy)

    def test_nonempty_reasoning_channel_is_rejected(self):
        response = self.response()
        value = json.loads(response.body)
        value["choices"][0]["message"]["reasoning"] = "private"
        with self.assertRaises(GenerationResponseError):
            validate_scope_response(
                GenerationHTTPResponse(200, "application/json", canonical_json_bytes(value)),
                self.request,
                self.policy,
            )


if __name__ == "__main__":
    unittest.main()
