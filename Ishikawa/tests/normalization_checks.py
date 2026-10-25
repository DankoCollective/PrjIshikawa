from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from ishikawa.normalization import (
    NormalizationError,
    normalize_extraction_archive,
    normalized_json_bytes,
)


ARCHIVE_SHA256 = "072bff5e6d791fd1399f52dde8da8e3be1d53c30d4d7510d6de00ae01e3f6067"


class NormalizationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        test_file = Path(__file__).resolve()
        cls.ishikawa_root = test_file.parents[1]
        cls.phase_root = cls.ishikawa_root.parent
        cls.repo_root = cls.phase_root.parent
        cls.archive = (
            cls.repo_root
            / "local/artifacts/ishikawa/pdf-extraction-qualification"
            / "pdf_extraction_observations_20261019T212440Z.tar"
        )
        cls.source_manifest = cls.ishikawa_root / "tests/fixtures/synthetic_pdf_sources.json"
        cls.acceptance_truth_path = (
            cls.repo_root
            / "local/artifacts/org_lab/synthetic_corpus_v1/evaluation"
            / "extraction_acceptance_truth.json"
        )
        cls.acceptance_truth = json.loads(cls.acceptance_truth_path.read_text(encoding="utf-8"))
        cls.normalized = normalize_extraction_archive(
            cls.archive,
            cls.source_manifest,
            expected_archive_sha256=ARCHIVE_SHA256,
        )
        cls.documents = {item["filename"]: item for item in cls.normalized["documents"]}

    def test_normalization_is_deterministic(self):
        repeated = normalize_extraction_archive(
            self.archive,
            self.source_manifest,
            expected_archive_sha256=ARCHIVE_SHA256,
        )
        self.assertEqual(normalized_json_bytes(repeated), normalized_json_bytes(self.normalized))
        self.assertEqual(
            self.normalized["normalization_set_digest"],
            "86a31ba1ce7dea966273576553f09b244e7f3a3f9d4f7757812d04f9551f9e43",
        )

    def test_exact_archive_identity_is_required(self):
        with self.assertRaisesRegex(NormalizationError, "extraction_archive_identity_mismatch"):
            normalize_extraction_archive(
                self.archive,
                self.source_manifest,
                expected_archive_sha256="0" * 64,
            )

    def test_symlink_archive_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            link = Path(temporary) / "capture.tar"
            link.symlink_to(self.archive)
            with self.assertRaisesRegex(NormalizationError, "unsafe_extraction_archive"):
                normalize_extraction_archive(
                    link,
                    self.source_manifest,
                    expected_archive_sha256=ARCHIVE_SHA256,
                )

    def test_document_and_page_inventory_matches_held_out_truth(self):
        self.assertEqual(set(self.documents), {item["filename"] for item in self.acceptance_truth["documents"]})
        for expected in self.acceptance_truth["documents"]:
            document = self.documents[expected["filename"]]
            self.assertEqual(document["page_count"], expected["pages"])
            self.assertEqual(document["blank_pages"], expected["blank_pages"])

    def test_all_required_headings_become_structural_units(self):
        for expected in self.acceptance_truth["documents"]:
            headings = {
                unit["text"]
                for unit in self.documents[expected["filename"]]["units"]
                if unit["kind"] == "heading"
            }
            for required in expected["headings"]:
                self.assertIn(required["text"], headings)

    def test_table_authority_preserves_headers_and_atomic_rows(self):
        expected = self.acceptance_truth["table_checks"][0]
        units = [
            unit
            for unit in self.documents[expected["filename"]]["units"]
            if unit["kind"] == "table"
        ]
        self.assertEqual(len(units), 1)
        table = units[0]["properties"]
        self.assertEqual(table["authority"], "structured_table")
        self.assertEqual(table["headers"], expected["rows"][0])
        observed_rows = [[cell["value"] for cell in row["cells"]] for row in table["rows"]]
        self.assertEqual(observed_rows, expected["rows"][1:])
        self.assertTrue(all(len(row["cells"]) == len(table["headers"]) for row in table["rows"]))

    def test_form_fields_preserve_label_value_associations(self):
        expected = self.acceptance_truth["form_checks"]
        fields = {
            (unit["page_start"], unit["properties"]["label"], unit["properties"]["value"])
            for unit in self.documents[expected["filename"]]["units"]
            if unit["kind"] == "form_field"
        }
        for pair in expected["field_value_pairs"]:
            self.assertIn((pair["page"], pair["label"], pair["value"]), fields)

    def test_checkbox_states_preserve_labels(self):
        expected = self.acceptance_truth["form_checks"]
        options = set()
        for unit in self.documents[expected["filename"]]["units"]:
            if unit["kind"] != "checkbox_group":
                continue
            for option in unit["properties"]["options"]:
                options.add((unit["page_start"], option["label"], option["selected"]))
        for checkbox in expected["checkboxes"]:
            self.assertIn(
                (checkbox["page"], checkbox["label"], checkbox["marker"] == "[X]"),
                options,
            )

    def test_wrapped_lines_join_without_changing_visible_hyphens(self):
        all_text = [
            unit["text"]
            for document in self.normalized["documents"]
            for unit in document["units"]
            if unit["kind"] != "page_furniture"
        ]
        self.assertIn(
            "1. Preserve document ID, policy ID, section path, page number, version, and source checksum.",
            all_text,
        )
        self.assertTrue(any("time-bounded access" in text for text in all_text))

    def test_inline_procedure_steps_are_split_in_source_order(self):
        document = self.documents["SOP_42_IR_2006.pdf"]
        page_one = [
            unit["text"]
            for unit in document["units"]
            if unit["kind"] == "list_item" and unit["page_start"] == 1
        ]
        self.assertEqual(
            page_one,
            [
                "1. Assign event ID EVT-0001.",
                "2. Record detection time.",
                "3. Identify affected request IDs.",
            ],
        )
        page_four = [
            unit["text"]
            for unit in document["units"]
            if unit["kind"] == "list_item" and unit["page_start"] == 4
        ]
        self.assertEqual([text.split()[0] for text in page_four], ["1.", "2.", "3.", "4."])

    def test_furniture_is_retained_but_separate_from_semantic_units(self):
        manual = self.documents["Governance_Manual_2005_Revision_3.pdf"]
        furniture = [unit for unit in manual["units"] if unit["kind"] == "page_furniture"]
        semantic = [unit for unit in manual["units"] if unit["kind"] != "page_furniture"]
        self.assertEqual(len(furniture), 33)
        self.assertFalse(any("CONTROLLED COPY" in unit["text"] for unit in semantic))
        one_eligible_page = self.documents["OPS_17_CTL_2002_RevA.pdf"]
        self.assertNotIn("page_furniture", one_eligible_page["unit_kind_counts"])

    def test_units_are_anchored_hashed_and_cover_each_document_once(self):
        for document in self.normalized["documents"]:
            self.assertRegex(document["normalization_digest"], r"^[0-9a-f]{64}$")
            self.assertEqual(
                [unit["ordinal"] for unit in document["units"]],
                list(range(len(document["units"]))),
            )
            for unit in document["units"]:
                self.assertRegex(unit["unit_id"], r"^[0-9a-f]{64}$")
                self.assertRegex(unit["input_digest"], r"^[0-9a-f]{64}$")
                self.assertRegex(unit["output_digest"], r"^[0-9a-f]{64}$")
                self.assertTrue(unit["source_spans"])

    def test_document_references_are_extracted_deterministically(self):
        policy = self.documents["31_SCH_2003.pdf"]
        self.assertEqual(
            policy["references"],
            ["99 TST 2001", "99 TST 2002", "99 TST 2003", "99 TST 2005", "TST-9001"],
        )


if __name__ == "__main__":
    unittest.main()
