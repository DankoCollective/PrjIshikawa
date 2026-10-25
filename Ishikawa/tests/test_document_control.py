from __future__ import annotations

import json
import unittest
from dataclasses import dataclass

from ishikawa.chunking import (
    METHOD_PROFILE_ID,
    DOCUMENT_SCOPE_AFFINITY_PROFILE_ID,
    SCOPE_AWARE_METHOD_PROFILE_ID,
    SCOPE_CONTEXT_MAX_CHARACTERS,
    build_chunk_candidates,
    build_document_scope_affinity_representations,
    build_scope_aware_chunk_candidates,
)
from ishikawa.document_control import (
    DocumentControlError,
    canonical_header_label,
    department_aliases,
    extract_document_control_header,
    header_retrieval_lines,
    validate_document_control_header,
)


@dataclass(frozen=True)
class _Line:
    line_id: str
    text: str
    x_min: float
    y_min: float
    font_height: float = 10.0

    @property
    def x_max(self):
        return self.x_min + max(10.0, len(self.text) * self.font_height * 0.55)

    @property
    def y_max(self):
        return self.y_min + self.font_height

    @property
    def height(self):
        return self.font_height

    @property
    def y_center(self):
        return self.y_min + 5.0


@dataclass(frozen=True)
class _Page:
    number: int
    lines: tuple[_Line, ...]
    width: float = 612.0


def _header_page(page: int, label: str, department: str) -> _Page:
    rows = (
        (("Effective Date:", "2099-01-01"), ("Policy Number:", "99 TST 2001")),
        (("Applicability/Class:", "All Operations"), (label, department)),
        (("Date of Review:", "2099-06-30"), ("Approval:", "Board Alpha")),
    )
    lines = [
        _Line(f"p{page:04d}-l0000", "Synthetic Example Organization", 430, 20, 8),
        _Line(f"p{page:04d}-l0001", "Controlled Materials Access", 205, 70, 20),
    ]
    for row_index, row in enumerate(rows):
        y = 140.0 + row_index * 20.0
        for cell_index, (field, value) in enumerate(row):
            x = 40.0 + cell_index * 280.0
            lines.append(_Line(f"p{page:04d}-l{len(lines):04d}", field, x, y))
            lines.append(_Line(f"p{page:04d}-l{len(lines):04d}", value, x + 105.0, y))
    lines.append(_Line(f"p{page:04d}-l{len(lines):04d}", "Policy Number: body prose", 40, 260))
    return _Page(page, tuple(lines))


def _unit():
    return {
        "unit_id": "1" * 64,
        "input_digest": "2" * 64,
        "output_digest": "3" * 64,
        "ordinal": 0,
        "kind": "paragraph",
        "page_start": 1,
        "page_end": 1,
        "structural_path": ["I. Purpose"],
        "text": "Report a controlled-materials incident immediately.",
        "source_spans": [{
            "line_id": "p0001-l0014",
            "page": 1,
            "word_start": 0,
            "word_end": 5,
            "bbox": [40.0, 180.0, 500.0, 190.0],
        }],
        "rules": ["fixture"],
        "properties": {},
        "references": [],
    }


def _header_units(header):
    return [
        {
            "unit_id": f"{index + 7:064x}",
            "input_digest": f"{index + 40:064x}",
            "output_digest": f"{index + 80:064x}",
            "ordinal": index,
            "kind": "page_furniture",
            "page_start": 1,
            "page_end": 1,
            "structural_path": [],
            "text": line_id,
            "source_spans": [{
                "line_id": line_id,
                "page": 1,
                "word_start": 0,
                "word_end": 1,
                "bbox": [40.0, 20.0 + index * 10.0, 500.0, 28.0 + index * 10.0],
            }],
            "rules": ["fixture"],
            "properties": {},
            "references": [],
        }
        for index, line_id in enumerate(header["line_ids"])
    ]


class DocumentControlTests(unittest.TestCase):
    def test_supported_labels_and_department_aliases_are_canonical(self):
        self.assertEqual(canonical_header_label("Department:"), "department")
        self.assertEqual(canonical_header_label("Dept:"), "department")
        self.assertEqual(canonical_header_label("Dept.:") , "department")
        self.assertIn("IT", department_aliases("Information Technology"))

    def test_repeated_header_variants_preserve_provenance_and_normalize(self):
        header = extract_document_control_header((
            _header_page(1, "Dept.:", "Information Technology"),
            _header_page(2, "Department:", "Information Technology"),
        ))
        self.assertIsNotNone(header)
        self.assertTrue(header["repeated"])
        self.assertEqual(header["page_numbers"], [1, 2])
        self.assertEqual(
            header["fields"]["department"]["source_labels"],
            ["Department", "Dept."],
        )
        self.assertIn("Department: Information Technology", header_retrieval_lines(header))
        self.assertEqual(header["document_context"]["value"], "Controlled Materials Access")
        self.assertEqual(header["organization_name"]["value"], "Synthetic Example Organization")
        self.assertEqual(header["logo_handling"], "non_text_visual_ignored")
        self.assertIn("Organization: Synthetic Example Organization", header_retrieval_lines(header))
        self.assertIn("Document Context: Controlled Materials Access", header_retrieval_lines(header))
        self.assertNotIn("p0001-l0014", header["line_ids"])

    def test_canonical_json_field_order_remains_valid(self):
        header = extract_document_control_header((
            _header_page(1, "Dept.:", "Information Technology"),
        ))
        canonical_round_trip = json.loads(json.dumps(header, sort_keys=True))

        self.assertEqual(
            validate_document_control_header(canonical_round_trip),
            canonical_round_trip,
        )
        self.assertIn(
            "Department: Information Technology",
            header_retrieval_lines(canonical_round_trip),
        )

    def test_conflicting_repeated_header_fails_closed(self):
        with self.assertRaisesRegex(
            DocumentControlError, "document_control_header_repeat_conflict"
        ):
            extract_document_control_header((
                _header_page(1, "Dept:", "Information Technology"),
                _header_page(2, "Department:", "Facilities"),
            ))

    def test_partial_body_labels_do_not_become_a_header(self):
        page = _Page(1, (_Line("p0001-l0000", "Policy Number: 99 TST 2001", 40, 40),))
        self.assertIsNone(extract_document_control_header((page,)))
        self.assertIsNone(extract_document_control_header((
            _Page(1, (_Line("p0001-l0000", "I. Purpose", 40, 40),)),
            _header_page(2, "Department:", "Information Technology"),
        )))

    def test_one_header_candidate_and_body_filters_avoid_metadata_duplication(self):
        header = extract_document_control_header((
            _header_page(1, "Dept.:", "Information Technology"),
        ))
        normalized = {
            "schema_version": 1,
            "normalization_set_digest": "4" * 64,
            "documents": [{
                "doc_id": "SYN-V2-001",
                "source_sha256": "5" * 64,
                "normalization_digest": "6" * 64,
                "pages": [{"page": 1, "width": 612.0, "height": 792.0, "blank": False}],
                "blank_pages": [],
                "units": [
                    *(
                        unit | {"ordinal": index}
                        for index, unit in enumerate(_header_units(header))
                    ),
                    _unit() | {"ordinal": len(_header_units(header))},
                ],
                "document_control_header": header,
            }],
        }
        result = build_chunk_candidates(normalized)
        candidates = result["documents"][0]["candidates"]
        self.assertEqual(len(candidates), 2)
        metadata, candidate = candidates
        self.assertEqual(metadata["projection_kind"], "document_control_metadata")
        self.assertEqual(metadata["citation_anchor"]["page_start"], 1)
        self.assertEqual(metadata["citation_anchor"]["page_end"], 1)
        self.assertEqual(
            {span["line_id"] for span in metadata["citation_anchor"]["source_spans"]},
            set(header["line_ids"]),
        )
        self.assertIn("Department: Information Technology", metadata["retrieval_text"])
        self.assertEqual(
            candidate["content_text"],
            "Report a controlled-materials incident immediately.",
        )
        self.assertEqual(
            candidate["context_text"],
            "Document: Controlled Materials Access\n"
            "Document identifier: 99 TST 2001\n"
            "Section: I. Purpose",
        )
        self.assertNotIn("Document control metadata", candidate["context_text"])
        self.assertIn("Document: Controlled Materials Access", candidate["retrieval_text"])
        self.assertIn("Document identifier: 99 TST 2001", candidate["retrieval_text"])
        self.assertNotIn("Department: Information Technology", candidate["retrieval_text"])
        self.assertNotIn("Synthetic Example Organization", candidate["retrieval_text"])
        self.assertNotIn("Effective Date", candidate["retrieval_text"])
        control_filter = candidate["retrieval_filters"]["document_control"]
        self.assertEqual(control_filter["department_normalized"], "information technology")
        self.assertEqual(control_filter["document_context"], "Controlled Materials Access")
        self.assertEqual(control_filter["organization_name"], "Synthetic Example Organization")
        self.assertIn("IT", control_filter["department_aliases"])
        identity_context = candidate["projection_properties"][
            "retrieval_document_identity_context"
        ]
        self.assertEqual(identity_context["document_context"], "Controlled Materials Access")
        self.assertEqual(identity_context["policy_number"], "99 TST 2001")
        self.assertTrue(identity_context["included_in_retrieval_text"])
        self.assertFalse(
            metadata["projection_properties"][
                "retrieval_document_identity_context"
            ]["included_in_retrieval_text"]
        )
        self.assertEqual(
            metadata["retrieval_filters"]["document_control"],
            control_filter,
        )

        heading = {
            "unit_id": "a" * 64,
            "input_digest": "b" * 64,
            "output_digest": "c" * 64,
            "ordinal": 0,
            "kind": "heading",
            "page_start": 1,
            "page_end": 1,
            "structural_path": ["I. Purpose"],
            "text": "I. Purpose",
            "source_spans": [{
                "line_id": "p0001-l0015",
                "page": 1,
                "word_start": 0,
                "word_end": 2,
                "bbox": [40.0, 200.0, 200.0, 215.0],
            }],
            "rules": ["fixture"],
            "properties": {},
            "references": [],
        }
        second_body = _unit() | {
            "unit_id": "d" * 64,
            "input_digest": "e" * 64,
            "output_digest": "f" * 64,
            "text": "Escalate the incident to the responsible department.",
            "source_spans": [{
                "line_id": "p0001-l0016",
                "page": 1,
                "word_start": 0,
                "word_end": 7,
                "bbox": [40.0, 220.0, 500.0, 230.0],
            }],
        }
        representative_units = [
            *_header_units(header),
            heading,
            _unit(),
            second_body,
        ]
        representative_normalized = json.loads(json.dumps(normalized))
        representative_normalized["documents"][0]["units"] = [
            unit | {"ordinal": index}
            for index, unit in enumerate(representative_units)
        ]
        representative_candidates = build_chunk_candidates(
            representative_normalized
        )["documents"][0]["candidates"]
        representative = next(
            item
            for item in representative_candidates
            if item["projection_kind"] == "section_page_representative"
        )
        representative_identity = representative["projection_properties"][
            "retrieval_document_identity_context"
        ]
        self.assertEqual(representative_identity, identity_context)
        self.assertEqual(
            representative["projection_properties"]["document_control_header"],
            candidate["projection_properties"]["document_control_header"],
        )
        self.assertTrue(
            representative["retrieval_text"].startswith(
                "Document: Controlled Materials Access\n"
                "Document identifier: 99 TST 2001\n"
            )
        )

    def test_scope_aware_context_is_bounded_source_backed_and_retrieval_only(self):
        header = extract_document_control_header((
            _header_page(1, "Dept.:", "Information Technology"),
        ))
        heading = {
            "unit_id": "a" * 64,
            "input_digest": "b" * 64,
            "output_digest": "c" * 64,
            "ordinal": 0,
            "kind": "heading",
            "page_start": 1,
            "page_end": 1,
            "structural_path": ["I. Purpose and Scope"],
            "text": "I. Purpose and Scope",
            "source_spans": [{
                "line_id": "p0001-l0015",
                "page": 1,
                "word_start": 0,
                "word_end": 4,
                "bbox": [40.0, 200.0, 240.0, 215.0],
            }],
            "rules": ["fixture"],
            "properties": {},
            "references": [],
        }
        purpose = _unit() | {
            "unit_id": "d" * 64,
            "input_digest": "e" * 64,
            "output_digest": "f" * 64,
            "structural_path": ["I. Purpose and Scope"],
            "text": "Controls apply to controlled materials incidents and approved access.",
        }
        later = _unit() | {
            "unit_id": "7" * 64,
            "input_digest": "8" * 64,
            "output_digest": "9" * 64,
            "structural_path": ["II. Responsibilities"],
            "text": "This unrelated section must not enter the scope excerpt.",
        }
        units = [*_header_units(header), heading, purpose, later]
        normalized = {
            "schema_version": 1,
            "normalization_set_digest": "4" * 64,
            "documents": [{
                "doc_id": "SYN-V3-001",
                "source_sha256": "5" * 64,
                "normalization_digest": "6" * 64,
                "pages": [{"page": 1, "width": 612.0, "height": 792.0, "blank": False}],
                "blank_pages": [],
                "units": [unit | {"ordinal": index} for index, unit in enumerate(units)],
                "document_control_header": header,
            }],
        }

        accepted = build_chunk_candidates(normalized)
        scope_aware = build_scope_aware_chunk_candidates(normalized)
        self.assertEqual(accepted["method_profile_id"], METHOD_PROFILE_ID)
        self.assertEqual(scope_aware["method_profile_id"], SCOPE_AWARE_METHOD_PROFILE_ID)
        self.assertNotEqual(METHOD_PROFILE_ID, SCOPE_AWARE_METHOD_PROFILE_ID)
        accepted_body = next(
            item for item in accepted["documents"][0]["candidates"]
            if item["projection_kind"] == "paragraph"
        )
        scope_body = next(
            item for item in scope_aware["documents"][0]["candidates"]
            if item["projection_kind"] == "paragraph"
        )
        self.assertNotIn("retrieval_document_scope_context", accepted_body["projection_properties"])
        scope = scope_body["projection_properties"]["retrieval_document_scope_context"]
        self.assertEqual(scope["department"], "Information Technology")
        self.assertEqual(scope["applicability_class"], "All Operations")
        self.assertEqual(scope["purpose_scope_structural_path"], ["I. Purpose and Scope"])
        self.assertEqual(scope["purpose_scope_source_unit_ids"], ["d" * 64])
        self.assertLessEqual(len(scope["purpose_scope_excerpt"]), SCOPE_CONTEXT_MAX_CHARACTERS)
        self.assertFalse(scope["displayable"])
        self.assertFalse(scope["citable"])
        self.assertTrue(scope["included_in_retrieval_text"])
        self.assertIn("Department: Information Technology", scope_body["context_text"])
        self.assertIn("Applicability/class: All Operations", scope_body["context_text"])
        self.assertIn("Document scope: Controls apply", scope_body["context_text"])
        self.assertNotIn("unrelated section", scope_body["context_text"].casefold())
        self.assertNotIn("Effective Date", scope_body["context_text"])
        self.assertNotIn("Approval", scope_body["context_text"])
        metadata = scope_aware["documents"][0]["candidates"][0]
        self.assertFalse(
            metadata["projection_properties"]["retrieval_document_scope_context"]
            ["included_in_retrieval_text"]
        )
        self.assertNotIn("Document scope:", metadata["retrieval_text"])

        affinity = build_document_scope_affinity_representations(normalized)
        self.assertEqual(affinity["profile_id"], DOCUMENT_SCOPE_AFFINITY_PROFILE_ID)
        self.assertFalse(affinity["publication_eligible"])
        self.assertEqual(len(affinity["documents"]), 1)
        scope_record = affinity["documents"][0]["representation"]
        self.assertEqual(scope_record["projection_kind"], "document_scope_affinity")
        self.assertIn("Document scope: Controls apply", scope_record["retrieval_text"])
        self.assertNotIn("unrelated section", scope_record["retrieval_text"].casefold())
        self.assertNotIn("Effective Date", scope_record["retrieval_text"])
        self.assertNotIn("Approval", scope_record["retrieval_text"])
        self.assertFalse(scope_record["contextual_fields"]["displayable"])
        self.assertFalse(scope_record["contextual_fields"]["citable"])
        self.assertFalse(scope_record["contextual_fields"]["generation_eligible"])
        self.assertFalse(scope_record["contextual_fields"]["authoritative_evidence"])


if __name__ == "__main__":
    unittest.main()
