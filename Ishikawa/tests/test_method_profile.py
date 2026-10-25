from __future__ import annotations

import copy
import unittest
from pathlib import Path

from ishikawa.errors import IshikawaValidationError
from ishikawa.method_profile import (
    ACCEPTED_RETRIEVAL_PROFILE,
    ACCEPTED_RETRIEVAL_PROFILE_VALUE,
    validate_retrieval_profile,
)
from ishikawa.yaml_loader import load_restricted_yaml


class RetrievalProfileTests(unittest.TestCase):
    def assert_reason(self, value, reason: str) -> None:
        with self.assertRaises(IshikawaValidationError) as caught:
            validate_retrieval_profile(value)
        self.assertEqual(caught.exception.reason_code, reason)

    def test_tracked_template_is_the_accepted_profile(self) -> None:
        template = Path(__file__).resolve().parents[1] / "config" / "templates" / "method_profile.yaml"
        value = load_restricted_yaml(template, label="method profile")
        profile = validate_retrieval_profile(value)
        self.assertEqual(profile.canonical(), ACCEPTED_RETRIEVAL_PROFILE.canonical())
        self.assertEqual(profile.digest, ACCEPTED_RETRIEVAL_PROFILE.digest)

    def test_profile_identity_changes_with_candidate_depth(self) -> None:
        changed = copy.deepcopy(ACCEPTED_RETRIEVAL_PROFILE_VALUE)
        changed["retrieval"]["vector"]["candidate_depth"] = 19
        self.assertNotEqual(
            validate_retrieval_profile(changed).digest,
            ACCEPTED_RETRIEVAL_PROFILE.digest,
        )

    def test_unknown_field_is_rejected(self) -> None:
        changed = copy.deepcopy(ACCEPTED_RETRIEVAL_PROFILE_VALUE)
        changed["retrieval"]["vector"]["metric_alias"] = "cosine"
        self.assert_reason(changed, "METHOD_PROFILE_FIELD_UNKNOWN")

    def test_boolean_depth_is_rejected(self) -> None:
        changed = copy.deepcopy(ACCEPTED_RETRIEVAL_PROFILE_VALUE)
        changed["retrieval"]["exact"]["candidate_depth"] = True
        self.assert_reason(changed, "METHOD_PROFILE_VALUE_INVALID")

    def test_unqualified_search_config_is_rejected(self) -> None:
        changed = copy.deepcopy(ACCEPTED_RETRIEVAL_PROFILE_VALUE)
        changed["retrieval"]["lexical"]["search_config"] = "simple"
        self.assert_reason(changed, "METHOD_PROFILE_VALUE_UNSUPPORTED")

    def test_frozen_v13_47_settings_are_accepted(self) -> None:
        profile = validate_retrieval_profile(ACCEPTED_RETRIEVAL_PROFILE_VALUE)
        self.assertEqual(profile.schema_version, 3)
        self.assertEqual(profile.exact_candidate_depth, 1)
        self.assertEqual(
            (profile.exact_weight, profile.lexical_weight, profile.vector_weight),
            (1, 2, 4),
        )
        self.assertTrue(profile.section_page_representatives)
        self.assertTrue(profile.document_local_duplicate_canonicalization)
        self.assertEqual(
            profile.representative_evidence,
            "expand_to_ordered_atomic_members",
        )
        self.assertEqual(profile.document_shortlist_per_lane, 5)
        self.assertEqual(
            (
                profile.expansion_baseline_weight,
                profile.expansion_best_facet_weight,
                profile.expansion_facet_coverage_weight,
            ),
            (2, 1, 1),
        )

    def test_unqualified_lane_weights_are_rejected(self) -> None:
        changed = copy.deepcopy(ACCEPTED_RETRIEVAL_PROFILE_VALUE)
        changed["retrieval"]["fusion"]["lane_weights"]["vector"] = 2
        self.assert_reason(changed, "METHOD_PROFILE_VALUE_UNSUPPORTED")

    def test_learned_reranker_is_rejected(self) -> None:
        changed = copy.deepcopy(ACCEPTED_RETRIEVAL_PROFILE_VALUE)
        changed["retrieval"]["reranker"]["enabled"] = True
        self.assert_reason(changed, "METHOD_PROFILE_VALUE_UNSUPPORTED")

    def test_unqualified_calibration_weight_is_rejected(self) -> None:
        changed = copy.deepcopy(ACCEPTED_RETRIEVAL_PROFILE_VALUE)
        changed["retrieval"]["score_calibration"]["weights"]["original_vector"] = 2.0
        self.assert_reason(changed, "METHOD_PROFILE_VALUE_UNSUPPORTED")

    def test_observation_contract_preserves_chunk_profile_boundary(self) -> None:
        observation = ACCEPTED_RETRIEVAL_PROFILE.observation_contract()
        self.assertEqual(
            observation["method_profile_id"],
            ACCEPTED_RETRIEVAL_PROFILE.chunk_method_profile_id,
        )
        self.assertNotEqual(
            ACCEPTED_RETRIEVAL_PROFILE.digest,
            ACCEPTED_RETRIEVAL_PROFILE.chunk_method_profile_id,
        )


if __name__ == "__main__":
    unittest.main()
