from __future__ import annotations

import json
import unittest
from pathlib import Path

from ishikawa.api_contract import (
    ERRORS_BY_STATUS,
    STATUSES,
    ApiSegment,
    ApiContextBudget,
    ApiContractError,
    ApiError,
    ApiExcerpt,
    ApiSourceGroup,
    build_chat_response,
    decode_chat_request,
    validate_api_profile,
)
from ishikawa.yaml_loader import load_restricted_yaml


def identity(character: str) -> str:
    return character * 64


class ApiContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[1]
        cls.raw_profile = load_restricted_yaml(
            root / "config/templates/api_profile.yaml", label="API profile"
        )
        cls.policy = validate_api_profile(cls.raw_profile)

    def request_value(self):
        return {
            "schema": "ishikawa.chat-request.v1",
            "conversation_id": identity("a"),
            "turn_id": identity("d"),
            "message": "What else does Source 1 say about reporting?",
            "history": [
                {"turn_id": identity("b"), "role": "user", "content": "How are incidents reported?"},
                {"turn_id": identity("c"), "role": "assistant", "content": "Report them promptly."},
            ],
            "source_references": [
                {
                    "source_id": identity("e"),
                    "source_label": "Source 1",
                    "citation_id": identity("f"),
                }
            ],
            "filters": {"document_classes": ["policy_sop"], "document_keys": []},
        }

    def request(self):
        body = json.dumps(self.request_value(), separators=(",", ":")).encode()
        return decode_chat_request(body, self.policy)

    def source(self):
        excerpt = ApiExcerpt(
            identity("f"), "Reports are submitted promptly.", 2, 2,
            ("Incident Reporting", "Submission"), "step", "Step 2",
        )
        return ApiSourceGroup(
            identity("e"), "Source 1", "procedure.incident-reporting",
            "99 TST 2003", "Incident Reporting Procedure", "policy_sop", (excerpt,), 3,
        )

    def test_profile_freezes_versioned_nonstreaming_boundary(self):
        self.assertEqual(len(self.policy.digest), 64)
        self.assertEqual(self.policy.maximum_history_turns, 12)
        self.assertEqual(self.policy.maximum_segments, 64)
        self.assertEqual(STATUSES[0], "answered")

    def test_valid_multiturn_request_preserves_history_and_source_reference(self):
        request = self.request()
        self.assertEqual(len(request.history), 2)
        self.assertEqual(request.source_references[0].source_label, "Source 1")
        self.assertEqual(request.filters.document_classes, ("policy_sop",))
        self.assertEqual(len(request.envelope_identity), 64)

    def test_duplicate_json_field_is_rejected(self):
        body = b'{"schema":"ishikawa.chat-request.v1","schema":"duplicate"}'
        with self.assertRaisesRegex(ApiContractError, "REQUEST_JSON_DUPLICATE_FIELD"):
            decode_chat_request(body, self.policy)

    def test_history_must_alternate_end_with_assistant_and_use_unique_turns(self):
        value = self.request_value()
        value["history"] = value["history"][:1]
        with self.assertRaisesRegex(ApiContractError, "REQUEST_HISTORY_ORDER_INVALID"):
            decode_chat_request(json.dumps(value).encode(), self.policy)
        value = self.request_value()
        value["turn_id"] = identity("b")
        with self.assertRaisesRegex(ApiContractError, "REQUEST_TURN_ID_REUSED"):
            decode_chat_request(json.dumps(value).encode(), self.policy)

    def test_unknown_request_field_and_unallowlisted_filter_are_rejected(self):
        value = self.request_value()
        value["method_profile_id"] = identity("1")
        with self.assertRaisesRegex(ApiContractError, "REQUEST_FIELDS_INVALID"):
            decode_chat_request(json.dumps(value).encode(), self.policy)
        value = self.request_value()
        value["filters"]["scope"] = "private"
        with self.assertRaisesRegex(ApiContractError, "REQUEST_FILTER_FIELDS_INVALID"):
            decode_chat_request(json.dumps(value).encode(), self.policy)

    def test_answered_response_is_segment_derived_and_citation_allowlisted(self):
        segment = ApiSegment("Reports are submitted promptly.", (identity("f"),))
        result = build_chat_response(
            request=self.request(), request_id=identity("1"), status="answered",
            segments=(segment,), sources=(self.source(),),
            context_budget=ApiContextBudget(32768, 8192, 24576), policy=self.policy,
        )
        self.assertNotIn("answer", result.body)
        self.assertEqual(result.body["segments"][0]["text"], segment.text)
        self.assertEqual(result.body["sources"][0]["source_label"], "Source 1")
        self.assertEqual(result.body["sources"][0]["page_count"], 3)
        self.assertIsNone(result.body["diagnostics"])
        self.assertNotIn("filesystem_path", result.canonical_bytes().decode())
        self.assertNotIn("raw_score", result.canonical_bytes().decode())

    def test_answer_cannot_use_unknown_citation_or_model_prose(self):
        segment = ApiSegment("Reports are submitted promptly.", (identity("9"),))
        with self.assertRaisesRegex(ApiContractError, "RESPONSE_CITATION_NOT_ALLOWED"):
            build_chat_response(
                request=self.request(), request_id=identity("1"), status="answered",
                segments=(segment,), sources=(self.source(),),
                context_budget=ApiContextBudget(32768, 8192, 24576), policy=self.policy,
            )

    def test_clarification_has_no_answer_source_or_error(self):
        response = build_chat_response(
            request=self.request(), request_id=identity("1"),
            status="clarification-required", clarification="Which policy do you mean?",
            policy=self.policy,
        )
        self.assertNotIn("answer", response.body)
        self.assertEqual(response.body["sources"], [])
        self.assertIsNone(response.body["error"])

    def test_every_failure_status_requires_only_safe_error(self):
        for status in STATUSES[2:]:
            with self.subTest(status=status):
                code, message = ERRORS_BY_STATUS[status]
                response = build_chat_response(
                    request=self.request(), request_id=identity("1"), status=status,
                    error=ApiError(code, message),
                    policy=self.policy,
                )
                self.assertEqual(response.body["status"], status)
                self.assertEqual(response.body["segments"], [])

    def test_open_download_and_streaming_cannot_enter_envelopes(self):
        value = self.request_value()
        value["open_document"] = True
        with self.assertRaisesRegex(ApiContractError, "REQUEST_FIELDS_INVALID"):
            decode_chat_request(json.dumps(value).encode(), self.policy)


if __name__ == "__main__":
    unittest.main()
