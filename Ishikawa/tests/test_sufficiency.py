from __future__ import annotations

import unittest
from dataclasses import replace
from pathlib import Path

from ishikawa.canonical import domain_digest
from ishikawa.reconstruction import (
    EvidenceCandidate,
    EvidenceCitation,
    assemble_evidence,
    validate_reconstruction_profile,
)
from ishikawa.relevance import RelevanceDecision
from ishikawa.sufficiency import (
    SufficiencyContractError,
    SufficiencySignals,
    evaluate_evidence_sufficiency,
    validate_sufficiency_profile,
)
from ishikawa.yaml_loader import load_restricted_yaml


def identity(label: str) -> str:
    return domain_digest("ishikawa.sufficiency-test.v1", label)


class SufficiencyGateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[1]
        cls.policy = validate_sufficiency_profile(
            load_restricted_yaml(root / "config/templates/sufficiency_profile.yaml", label="sufficiency profile")
        )
        reconstruction_policy = validate_reconstruction_profile(
            load_restricted_yaml(root / "config/templates/reconstruction_profile.yaml", label="reconstruction profile")
        )
        citation = EvidenceCitation(
            identity("citation"), identity("document"), identity("version"),
            "procedure.synthetic", 1, 1, ("Reporting",),
        )
        candidate = EvidenceCandidate(
            identity("chunk"), identity("text"), "A report is due within one day.",
            "paragraph", 1, 1, "direct", "fused_retrieval", (citation,),
        )
        cls.package = assemble_evidence(
            (candidate,), policy=reconstruction_policy, token_counter=lambda text: len(text.split()),
            instruction_tokens=100, conversation_tokens=100,
        )
        cls.relevance_identity = identity("relevance-profile")
        cls.qualified_relevance = RelevanceDecision(
            "qualified", "CITABLE_EVIDENCE_SUPPORT_QUALIFIED",
            cls.relevance_identity, 3, 3, 3, 5,
        )
        cls.insufficient_relevance = RelevanceDecision(
            "insufficient", "CITABLE_EVIDENCE_SUPPORT_INSUFFICIENT",
            cls.relevance_identity, 3, 3, 2, 5,
        )

    def signals(self, **changes):
        values = {
            "lane_states": (("exact", "not_applicable"), ("lexical", "pass"), ("vector", "pass")),
            "fused_candidate_count": 1,
            "authorized_candidate_count": 1,
            "exact_constraint_required": False,
            "exact_constraint_satisfied": False,
            "unique_exact_document_constraint": False,
            "relationship_coverage_required": False,
            "relationship_coverage_complete": False,
            "source_version_conflict": False,
            "relevance_decision": self.qualified_relevance,
            "complete_structure_requested": False,
        }
        values.update(changes)
        return SufficiencySignals(**values)

    def decide(self, **changes):
        return evaluate_evidence_sufficiency(self.signals(**changes), self.package, self.policy)

    def test_complete_valid_evidence_is_eligible(self):
        result = self.decide()
        self.assertEqual((result.status, result.reason_code), ("sufficient", "EVIDENCE_SUFFICIENT"))
        self.assertEqual((result.evidence_passages, result.citation_count), (1, 1))

    def test_lane_failure_is_temporarily_unavailable(self):
        result = self.decide(lane_states=(("exact", "not_applicable"), ("lexical", "pass"), ("vector", "failed")))
        self.assertEqual((result.status, result.reason_code), ("temporarily-unavailable", "RETRIEVAL_LANE_FAILURE"))

    def test_no_candidates_and_authorization_filter_fail_closed(self):
        result = self.decide(fused_candidate_count=0, authorized_candidate_count=0)
        self.assertEqual(result.reason_code, "NO_RETRIEVAL_CANDIDATES")
        result = self.decide(authorized_candidate_count=0)
        self.assertEqual(result.reason_code, "NO_AUTHORIZED_EVIDENCE")

    def test_exact_and_relationship_constraints_are_required_when_requested(self):
        result = self.decide(exact_constraint_required=True)
        self.assertEqual(result.reason_code, "EXACT_CONSTRAINT_UNSATISFIED")
        result = self.decide(relationship_coverage_required=True)
        self.assertEqual(result.reason_code, "RELATIONSHIP_COVERAGE_INCOMPLETE")

    def test_source_version_conflict_abstains(self):
        result = self.decide(source_version_conflict=True)
        self.assertEqual((result.status, result.reason_code), ("insufficient-evidence", "SOURCE_VERSION_CONFLICT"))

    def test_relevance_must_be_calibrated_and_positive(self):
        result = self.decide(relevance_decision=None)
        self.assertEqual(result.reason_code, "RELEVANCE_NOT_QUALIFIED")
        result = self.decide(relevance_decision=self.insufficient_relevance)
        self.assertEqual(result.reason_code, "RELEVANCE_INSUFFICIENT")
        self.assertEqual(result.relevance_profile_identity, self.relevance_identity)

    def test_unique_exact_document_may_override_generic_lexical_relevance(self):
        result = self.decide(
            exact_constraint_required=True,
            exact_constraint_satisfied=True,
            unique_exact_document_constraint=True,
            relevance_decision=self.insufficient_relevance,
        )
        self.assertEqual(
            (result.status, result.reason_code),
            ("sufficient", "EXACT_DOCUMENT_EVIDENCE_SUFFICIENT"),
        )
        self.assertEqual(result.relevance_profile_identity, self.relevance_identity)

    def test_exact_document_override_requires_a_satisfied_exact_constraint(self):
        with self.assertRaises(SufficiencyContractError):
            self.signals(unique_exact_document_constraint=True)
        with self.assertRaises(SufficiencyContractError):
            self.signals(
                exact_constraint_required=True,
                unique_exact_document_constraint=True,
            )

    def test_context_limit_is_preserved(self):
        package = replace(self.package, status="context-limit", reason_code="EVIDENCE_CONTEXT_LIMIT")
        result = evaluate_evidence_sufficiency(self.signals(), package, self.policy)
        self.assertEqual((result.status, result.reason_code), ("context-limit", "CONTEXT_LIMIT"))

    def test_complete_structure_requires_complete_package(self):
        result = self.decide(complete_structure_requested=True)
        self.assertEqual(result.reason_code, "COMPLETE_STRUCTURE_INCOMPLETE")

    def test_citation_set_must_match_source_groups(self):
        package = replace(self.package, source_groups=())
        result = evaluate_evidence_sufficiency(self.signals(), package, self.policy)
        self.assertEqual(result.reason_code, "CITATION_SET_INVALID")

    def test_signal_contract_rejects_unowned_relevance_status(self):
        with self.assertRaises(SufficiencyContractError):
            self.signals(relevance_decision="qualified")

    def test_profile_rejects_candidate_presence_as_relevance_rule(self):
        raw = {
            "schema_version": 2,
            "checks": {
                "required_semantic_lanes": ["lexical", "vector"],
                "fail_closed_on_lane_error": True,
                "require_authorized_candidate": True,
                "require_exact_constraint_satisfaction": True,
                "require_relationship_coverage": True,
                "require_valid_citations": True,
                "require_calibrated_relevance": False,
                "allow_unique_exact_document_relevance_override": True,
                "source_conflict_status": "insufficient-evidence",
                "incomplete_structure_status": "context-limit",
            },
            "statuses": {
                "eligible": "sufficient", "unavailable": "temporarily-unavailable",
                "inadequate": "insufficient-evidence", "over_budget": "context-limit",
            },
            "reason_codes": list(self.policy_reason_codes()),
        }
        with self.assertRaises(SufficiencyContractError):
            validate_sufficiency_profile(raw)

    @staticmethod
    def policy_reason_codes():
        return (
            "EVIDENCE_SUFFICIENT", "EXACT_DOCUMENT_EVIDENCE_SUFFICIENT",
            "RETRIEVAL_LANE_FAILURE", "NO_RETRIEVAL_CANDIDATES",
            "NO_AUTHORIZED_EVIDENCE", "EXACT_CONSTRAINT_UNSATISFIED",
            "RELATIONSHIP_COVERAGE_INCOMPLETE", "SOURCE_VERSION_CONFLICT",
            "NO_RECONSTRUCTABLE_EVIDENCE", "CITATION_SET_INVALID",
            "RELEVANCE_NOT_QUALIFIED", "RELEVANCE_INSUFFICIENT",
            "COMPLETE_STRUCTURE_INCOMPLETE", "CONTEXT_LIMIT",
        )


if __name__ == "__main__":
    unittest.main()
