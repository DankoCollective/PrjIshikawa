from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from ishikawa.chunking import (
    ChunkingError,
    METHOD_PROFILE_ID,
    build_from_file,
    chunk_candidates_json_bytes,
)


NORMALIZED_SHA256 = "736d619ac5a7e10f768bdb8b8f3f117cb52231f8dc2f4d186d52d96c8bd41e28"
EXPECTED_SET_DIGEST = "7926fc6c4db4e065b3791ed67a69b33feefe8f6023109d07ad21ebdef93023f1"


class ChunkingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        test_file = Path(__file__).resolve()
        cls.ishikawa_root = test_file.parents[1]
        cls.repo_root = cls.ishikawa_root.parents[1]
        cls.normalized_path = (
            cls.repo_root
            / "local/artifacts/ishikawa/normalization"
            / "normalized_structural_units_20261019T214207Z.json"
        )
        cls.normalized = json.loads(cls.normalized_path.read_text(encoding="utf-8"))
        cls.artifact = build_from_file(
            cls.normalized_path,
            expected_normalized_sha256=NORMALIZED_SHA256,
        )
        cls.candidates = [
            candidate
            for document in cls.artifact["documents"]
            for candidate in document["candidates"]
        ]

    def test_candidate_construction_is_deterministic(self):
        repeated = build_from_file(
            self.normalized_path,
            expected_normalized_sha256=NORMALIZED_SHA256,
        )
        self.assertEqual(
            chunk_candidates_json_bytes(self.artifact),
            chunk_candidates_json_bytes(repeated),
        )
        self.assertEqual(self.artifact["chunk_candidate_set_digest"], EXPECTED_SET_DIGEST)
        self.assertEqual(self.artifact["method_profile_id"], METHOD_PROFILE_ID)

    def test_exact_normalized_identity_is_required(self):
        with self.assertRaisesRegex(ChunkingError, "normalized_artifact_identity_mismatch"):
            build_from_file(
                self.normalized_path,
                expected_normalized_sha256="0" * 64,
            )

    def test_symlink_input_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            link = Path(temporary) / "normalized.json"
            link.symlink_to(self.normalized_path)
            with self.assertRaisesRegex(ChunkingError, "unsafe_normalized_artifact"):
                build_from_file(link, expected_normalized_sha256=NORMALIZED_SHA256)

    def test_expected_candidate_inventory(self):
        self.assertEqual(len(self.artifact["documents"]), 6)
        self.assertEqual(len(self.candidates), 154)
        kinds: dict[str, int] = {}
        for candidate in self.candidates:
            kind = candidate["projection_kind"]
            kinds[kind] = kinds.get(kind, 0) + 1
        self.assertEqual(kinds, {
            "checkbox_group": 4,
            "definition": 5,
            "form_field": 12,
            "list_item": 60,
            "paragraph": 40,
            "page_status": 1,
            "table_context": 1,
            "table_row": 3,
            "section_page_representative": 28,
        })

    def test_semantic_units_are_covered_without_blind_body_overlap(self):
        ordinary_unit_ids = {
            unit["unit_id"]
            for document in self.normalized["documents"]
            for unit in document["units"]
            if unit["kind"] not in {"heading", "page_furniture", "table"}
        }
        candidate_ordinary_ids = [
            candidate["source_unit_ids"][0]
            for candidate in self.candidates
            if candidate["projection_kind"] not in {
                "page_status", "table_context", "table_row", "section_page_representative"
            }
        ]
        self.assertEqual(set(candidate_ordinary_ids), ordinary_unit_ids)
        self.assertEqual(len(candidate_ordinary_ids), len(set(candidate_ordinary_ids)))
        self.assertTrue(all(
            candidate["projection_properties"]["body_overlap_units"] == 0
            for candidate in self.candidates
        ))

    def test_verified_blank_page_has_one_derived_citable_status_candidate(self):
        candidates = [
            item for item in self.candidates if item["projection_kind"] == "page_status"
        ]
        self.assertEqual(len(candidates), 1)
        candidate = candidates[0]
        self.assertEqual(candidate["content_text"], "Page 1 contains no extractable text.")
        self.assertEqual(candidate["citation_anchor"]["page_start"], 1)
        self.assertEqual(candidate["citation_anchor"]["page_end"], 1)
        self.assertEqual(candidate["citation_anchor"]["anchor_kind"], "page_status")
        self.assertTrue(candidate["projection_properties"]["blank"])
        self.assertTrue(candidate["projection_properties"]["derived_evidence"])
        self.assertFalse(candidate["projection_properties"]["retrieval_scoring_only"])

    def test_section_page_representatives_are_scoring_only_and_atomic_backed(self):
        representatives = [
            item
            for item in self.candidates
            if item["projection_kind"] == "section_page_representative"
        ]
        atomic_ids = {
            item["chunk_id"]
            for item in self.candidates
            if item["projection_kind"] != "section_page_representative"
        }
        self.assertEqual(len(representatives), 28)
        self.assertEqual(
            sum(
                len(item["projection_properties"]["component_chunk_ids"])
                for item in representatives
            ),
            122,
        )
        for representative in representatives:
            properties = representative["projection_properties"]
            self.assertTrue(properties["retrieval_scoring_only"])
            self.assertTrue(properties["atomic_evidence_authoritative"])
            self.assertTrue(set(properties["component_chunk_ids"]) <= atomic_ids)
            identity = properties.get("retrieval_document_identity_context")
            if identity is not None:
                self.assertTrue(identity["included_in_retrieval_text"])
                self.assertTrue(
                    representative["retrieval_text"].startswith(
                        f"Document: {identity['document_context']}\n"
                        f"Document identifier: {identity['policy_number']}\n"
                    )
                )

    def test_headings_are_explicit_context_and_furniture_is_excluded(self):
        all_furniture_ids = {
            unit["unit_id"]
            for document in self.normalized["documents"]
            for unit in document["units"]
            if unit["kind"] == "page_furniture"
        }
        self.assertTrue(any(item["context_text"].startswith("Section: ") for item in self.candidates))
        self.assertTrue(all(
            all(unit_id not in all_furniture_ids for unit_id in candidate["source_unit_ids"])
            for candidate in self.candidates
        ))
        self.assertNotIn("heading", {item["projection_kind"] for item in self.candidates})
        self.assertNotIn("page_furniture", {item["projection_kind"] for item in self.candidates})

    def test_table_rows_are_atomic_with_headers_context_and_no_neighbors(self):
        table_candidates = [
            item for item in self.candidates if item["projection_kind"].startswith("table_")
        ]
        self.assertEqual([item["projection_kind"] for item in table_candidates], [
            "table_context", "table_row", "table_row", "table_row"
        ])
        rows = table_candidates[1:]
        self.assertEqual(
            [item["projection_properties"]["row_index"] for item in rows], [0, 1, 2]
        )
        for row in rows:
            self.assertEqual(row["projection_properties"]["row_expansion"], 0)
            self.assertIn("Columns: Condition | Decision | Evidence | Next step", row["context_text"])
            self.assertEqual(row["citation_anchor"]["anchor_kind"], "table_row")
            self.assertEqual(len(row["citation_anchor"]["source_spans"]), 4)
        self.assertIn("TST-9001", rows[1]["lexical_fields"]["references"])
        self.assertNotIn("TST-9001", rows[0]["lexical_fields"]["references"])

    def test_forms_keep_labels_values_and_checkbox_states_together(self):
        fields = [item for item in self.candidates if item["projection_kind"] == "form_field"]
        checkboxes = [
            item for item in self.candidates if item["projection_kind"] == "checkbox_group"
        ]
        self.assertEqual(len(fields), 12)
        self.assertEqual(len(checkboxes), 4)
        self.assertTrue(all(item["lexical_fields"]["labels"] for item in fields))
        request_type = next(item for item in checkboxes if "Request type:" in item["content_text"])
        self.assertEqual(request_type["lexical_fields"]["boolean_states"], [
            {"label": "Temporary", "selected": True},
            {"label": "Permanent", "selected": False},
        ])

    def test_sequence_links_are_bidirectional_and_document_local(self):
        for document in self.artifact["documents"]:
            candidates = document["candidates"]
            ids = {item["chunk_id"] for item in candidates}
            for index, candidate in enumerate(candidates):
                sequence = candidate["sequence"]
                expected_previous = candidates[index - 1]["chunk_id"] if index else None
                expected_next = candidates[index + 1]["chunk_id"] if index + 1 < len(candidates) else None
                self.assertEqual(sequence["previous_chunk_id"], expected_previous)
                self.assertEqual(sequence["next_chunk_id"], expected_next)
                self.assertTrue(sequence["previous_chunk_id"] is None or sequence["previous_chunk_id"] in ids)
                self.assertTrue(sequence["next_chunk_id"] is None or sequence["next_chunk_id"] in ids)

    def test_candidate_identities_and_anchors_are_complete_and_unique(self):
        ids = [item["chunk_id"] for item in self.candidates]
        self.assertEqual(len(ids), len(set(ids)))
        for candidate in self.candidates:
            self.assertRegex(candidate["chunk_id"], r"^[0-9a-f]{64}$")
            self.assertRegex(candidate["content_digest"], r"^[0-9a-f]{64}$")
            self.assertRegex(candidate["context_digest"], r"^[0-9a-f]{64}$")
            self.assertRegex(candidate["retrieval_text_digest"], r"^[0-9a-f]{64}$")
            self.assertTrue(candidate["citation_anchor"]["source_spans"])
            self.assertGreaterEqual(candidate["citation_anchor"]["page_start"], 1)

    def test_original_filenames_are_not_in_candidate_surface(self):
        payload = chunk_candidates_json_bytes(self.artifact).decode("utf-8")
        for document in self.normalized["documents"]:
            self.assertNotIn(document["filename"], payload)
        self.assertNotIn('"filename"', payload)

    def test_token_measurement_and_publication_fail_closed(self):
        self.assertEqual(
            self.artifact["token_measurement_status"],
            "pending_authoritative_nomic_measurement",
        )
        self.assertFalse(self.artifact["publication_eligible"])
        for candidate in self.candidates:
            self.assertEqual(
                candidate["token_accounting"]["status"],
                "pending_authoritative_nomic_measurement",
            )
            self.assertIsNone(candidate["token_accounting"]["total_embedding_input_tokens"])
            self.assertEqual(candidate["publication_eligibility"], {
                "eligible": False,
                "blockers": ["nomic_token_measurement_pending"],
            })


if __name__ == "__main__":
    unittest.main()
