from __future__ import annotations

import unittest
from dataclasses import replace
from pathlib import Path

from ishikawa.relevance import (
    RelevanceContractError,
    RelevanceMeasurement,
    evaluate_relevance,
    measure_citable_evidence_relevance,
    plan_citable_response_envelopes,
    validate_relevance_profile,
)
from ishikawa.retrieval import FusedCandidate
from ishikawa.yaml_loader import load_restricted_yaml


class RecordingConnection:
    def __init__(self, responses):
        self.responses = list(responses)
        self.executions = []

    def execute(self, sql, parameters):
        self.executions.append((sql, parameters))
        self.current = self.responses.pop(0)
        return self

    def fetchone(self):
        return self.current

    def fetchall(self):
        return self.current


def fused(label: str) -> FusedCandidate:
    return FusedCandidate(label * 64, "d" * 64, "v" * 64, f"policy.{label}", 0.1, False, ())


class RelevanceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[1]
        cls.raw_profile = load_restricted_yaml(
            root / "config/templates/relevance_profile.yaml", label="relevance profile"
        )
        cls.policy = validate_relevance_profile(cls.raw_profile)

    def measurement(self, supported, unsupported):
        question = tuple(sorted((*supported, *unsupported)))
        return RelevanceMeasurement(
            question, tuple(sorted(supported)), tuple(sorted(unsupported)), 3
        )

    def test_profile_has_stable_frozen_boundary(self):
        self.assertEqual(self.policy.fused_depth, 3)
        self.assertEqual(
            (self.policy.minimum_supported_numerator, self.policy.minimum_supported_denominator),
            (3, 5),
        )
        self.assertEqual(len(self.policy.digest), 64)

    def test_exact_sixty_percent_qualifies_without_floating_point(self):
        result = evaluate_relevance(self.measurement(("a", "b", "c"), ("d", "e")), self.policy)
        self.assertEqual(result.status, "qualified")
        self.assertEqual((result.supported_count, result.question_lexeme_count), (3, 5))

    def test_below_sixty_percent_is_insufficient(self):
        result = evaluate_relevance(self.measurement(("a", "b"), ("c", "d")), self.policy)
        self.assertEqual(result.status, "insufficient")

    def test_measurement_requires_exact_question_partition(self):
        with self.assertRaises(RelevanceContractError):
            RelevanceMeasurement(("a", "b"), ("a",), (), 1)

    def test_profile_rejects_unfrozen_depth(self):
        changed = dict(self.raw_profile)
        changed["measurement"] = dict(changed["measurement"])
        changed["measurement"]["fused_depth"] = 5
        with self.assertRaises(RelevanceContractError):
            validate_relevance_profile(changed)

    def test_database_measurement_uses_only_top_three_fused_chunks(self):
        question = ["approv", "polici", "request", "social", "use"]
        connection = RecordingConnection(
            [
                (question,),
                [
                    ("a" * 64, ["approv", "polici"]),
                    ("b" * 64, ["request"]),
                    ("c" * 64, ["social"]),
                ],
            ]
        )
        result = measure_citable_evidence_relevance(
            connection,
            "How is social media use approved?",
            (fused("a"), fused("b"), fused("c"), fused("e")),
            self.policy,
        )
        self.assertEqual(result.status, "qualified")
        self.assertEqual(result.fused_chunk_count, 3)
        self.assertEqual(
            connection.executions[1][1],
            (["a" * 64, "b" * 64, "c" * 64],),
        )
        self.assertIn("display_name", connection.executions[1][0])
        self.assertIn("structural_path", connection.executions[1][0])

    def test_database_measurement_fails_closed_on_missing_citation_identity(self):
        connection = RecordingConnection([(["polici"],), []])
        with self.assertRaisesRegex(RelevanceContractError, "identity mismatch"):
            measure_citable_evidence_relevance(
                connection, "policy", (fused("a"),), self.policy
            )

    def test_database_measurement_unions_atoms_inside_three_ranked_envelopes(self):
        question = ["control", "decis", "request"]
        connection = RecordingConnection(
            [
                (question,),
                [
                    ("a" * 64, ["request"]),
                    ("b" * 64, ["control"]),
                    ("c" * 64, ["decis"]),
                    ("d" * 64, []),
                ],
            ]
        )
        first = replace(
            fused("a"),
            authoritative_chunk_ids=("a" * 64, "b" * 64),
        )
        second = replace(
            fused("c"),
            authoritative_chunk_ids=("c" * 64, "d" * 64),
        )
        result = measure_citable_evidence_relevance(
            connection,
            "Which request controls and decision apply?",
            (first, second),
            self.policy,
        )
        self.assertEqual(result.status, "qualified")
        self.assertEqual(result.fused_chunk_count, 2)
        self.assertEqual(
            connection.executions[1][1],
            (["a" * 64, "b" * 64, "c" * 64, "d" * 64],),
        )

    def test_response_envelopes_pair_scope_and_rank_one_result_per_document(self):
        first = replace(
            fused("a"),
            document_id="1" * 64,
            document_version_id="2" * 64,
            document_key="policy.first",
            retrieval_group_id="first-operation",
            authoritative_chunk_ids=("a" * 64,),
        )
        weaker_same_document = replace(
            first,
            chunk_id="b" * 64,
            retrieval_group_id="first-generic",
            authoritative_chunk_ids=("b" * 64,),
        )
        second = replace(
            fused("c"),
            document_id="3" * 64,
            document_version_id="4" * 64,
            document_key="policy.second",
            retrieval_group_id="second-operation",
            authoritative_chunk_ids=("c" * 64,),
        )
        connection = RecordingConnection(
            [
                [
                    (
                        "d" * 64,
                        "1" * 64,
                        "2" * 64,
                        "policy.first",
                        "first-scope",
                        ["d" * 64],
                        ["I. Purpose and Scope"],
                    ),
                    (
                        "e" * 64,
                        "3" * 64,
                        "4" * 64,
                        "policy.second",
                        "second-scope",
                        ["e" * 64],
                        ["I. Purpose and Scope"],
                    ),
                ],
                (["access", "incident", "report", "time"],),
                [
                    ("a" * 64, ["incident", "report"]),
                    ("b" * 64, ["incident"]),
                    ("c" * 64, ["report"]),
                    ("d" * 64, ["access", "time"]),
                    ("e" * 64, ["access"]),
                ],
            ]
        )
        plan = plan_citable_response_envelopes(
            connection,
            "How is incident access reported in time?",
            (weaker_same_document, second, first),
            self.policy,
        )
        self.assertEqual(plan.decision.status, "qualified")
        self.assertEqual(len(plan.relevance_candidates), 2)
        self.assertEqual(
            plan.relevance_candidates[0].authoritative_chunk_ids,
            ("a" * 64, "d" * 64),
        )
        self.assertEqual(
            plan.selected_group_order,
            (
                f"{'2' * 64}:first-operation",
                f"{'2' * 64}:first-scope",
                f"{'4' * 64}:second-operation",
                f"{'4' * 64}:second-scope",
            ),
        )
        self.assertIn("document-scope-units", connection.executions[0][0])

    def test_response_envelope_prefers_complementary_operational_section_over_scope(self):
        form_identity = replace(
            fused("a"),
            document_id="1" * 64,
            document_version_id="2" * 64,
            document_key="form.incident-intake",
            retrieval_group_id="form-identity",
            authoritative_chunk_ids=("a" * 64,),
            structural_path=("I. Instructions and Record Identity",),
        )
        form_controls = replace(
            form_identity,
            chunk_id="b" * 64,
            retrieval_group_id="form-controls",
            authoritative_chunk_ids=("b" * 64,),
            structural_path=("III. Risk and Control Selection",),
        )
        unrelated = replace(
            fused("c"),
            document_id="3" * 64,
            document_version_id="4" * 64,
            document_key="policy.unrelated",
            retrieval_group_id="unrelated-controls",
            authoritative_chunk_ids=("c" * 64,),
        )
        question = [
            "control",
            "incomplet",
            "initi",
            "report",
            "step",
            "suspect",
        ]
        connection = RecordingConnection(
            [
                [
                    (
                        "d" * 64,
                        "1" * 64,
                        "2" * 64,
                        "form.incident-intake",
                        "form-scope",
                        ["d" * 64],
                        ["II. Requester, Scope, and Dates"],
                    )
                ],
                (question,),
                [
                    ("a" * 64, ["initi", "report", "suspect"]),
                    ("b" * 64, ["control", "incomplet", "step"]),
                    ("c" * 64, ["control", "report"]),
                    ("d" * 64, ["report"]),
                ],
            ]
        )
        plan = plan_citable_response_envelopes(
            connection,
            "What steps apply to initial reporting of a suspected incident when control is incomplete?",
            (form_identity, unrelated, form_controls),
            self.policy,
        )
        self.assertEqual(plan.decision.status, "qualified")
        self.assertEqual(
            plan.relevance_candidates[0].authoritative_chunk_ids,
            ("a" * 64, "b" * 64),
        )
        self.assertEqual(
            plan.selected_group_order[:2],
            (
                f"{'2' * 64}:form-identity",
                f"{'2' * 64}:form-controls",
            ),
        )

    def test_response_envelopes_preserve_qualified_document_order_over_generic_coverage(self):
        decision_form = replace(
            fused("a"),
            document_id="1" * 64,
            document_version_id="2" * 64,
            document_key="form.decision-record",
            retrieval_group_id="decision-controls",
            authoritative_chunk_ids=("a" * 64,),
            structural_path=("III. Risk and Control Selection",),
        )
        exception_review = replace(
            fused("b"),
            document_id="3" * 64,
            document_version_id="4" * 64,
            document_key="policy.exception-review",
            retrieval_group_id="exception-controls",
            authoritative_chunk_ids=("b" * 64,),
            structural_path=("III. Required Controls",),
        )
        connection = RecordingConnection(
            [
                [],
                (["control", "decis", "incomplet", "oper", "polici", "record"],),
                [
                    ("a" * 64, ["decis", "incomplet", "oper", "polici", "record"]),
                    (
                        "b" * 64,
                        ["control", "decis", "incomplet", "oper", "polici", "record"],
                    ),
                ],
            ]
        )
        plan = plan_citable_response_envelopes(
            connection,
            "What control applies to an incomplete operational policy decision record?",
            (decision_form, exception_review),
            self.policy,
        )
        self.assertEqual(plan.decision.status, "qualified")
        self.assertEqual(
            plan.selected_group_order,
            (
                f"{'2' * 64}:decision-controls",
                f"{'4' * 64}:exception-controls",
            ),
        )

    def test_response_envelopes_anchor_rank_one_then_order_remaining_by_coverage(self):
        anchor = replace(
            fused("a"),
            document_id="1" * 64,
            document_version_id="2" * 64,
            document_key="procedure.material-handling",
            retrieval_group_id="handling-controls",
            authoritative_chunk_ids=("a" * 64,),
        )
        generic = replace(
            fused("b"),
            document_id="3" * 64,
            document_version_id="4" * 64,
            document_key="policy.incident-classification",
            retrieval_group_id="classification-controls",
            authoritative_chunk_ids=("b" * 64,),
        )
        responsive = replace(
            fused("c"),
            document_id="5" * 64,
            document_version_id="6" * 64,
            document_key="procedure.incident-response",
            retrieval_group_id="response-controls",
            authoritative_chunk_ids=("c" * 64,),
        )
        connection = RecordingConnection(
            [
                [],
                (["control", "incident", "incomplet", "material", "step"],),
                [
                    ("a" * 64, ["control", "material", "step"]),
                    ("b" * 64, ["incident"]),
                    ("c" * 64, ["control", "incident", "incomplet", "step"]),
                ],
            ]
        )
        plan = plan_citable_response_envelopes(
            connection,
            "What control steps apply to a materials incident, and when is it incomplete?",
            (anchor, generic, responsive),
            self.policy,
        )
        self.assertEqual(plan.decision.status, "qualified")
        self.assertEqual(
            plan.selected_group_order,
            (
                f"{'2' * 64}:handling-controls",
                f"{'6' * 64}:response-controls",
                f"{'4' * 64}:classification-controls",
            ),
        )


if __name__ == "__main__":
    unittest.main()
