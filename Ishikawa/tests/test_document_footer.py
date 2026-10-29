from __future__ import annotations

import unittest
from dataclasses import dataclass

from ishikawa.document_footer import (
    DocumentFooterError,
    extract_document_footer,
    validate_document_footer,
)


@dataclass(frozen=True)
class _Line:
    line_id: str
    text: str
    x_min: float
    y_min: float


@dataclass(frozen=True)
class _Page:
    number: int
    lines: tuple[_Line, ...]
    width: float = 612.0
    height: float = 792.0

    @property
    def blank(self):
        return not self.lines


def _page(page: int, total: int = 3, policy: str = "99 TST 2001", right: str = "SEO") -> _Page:
    return _Page(page, (
        _Line(f"p{page:04d}-l0000", "I. Body", 54.0, 120.0),
        _Line(f"p{page:04d}-l0001", "SEO Policy", 54.0, 730.0),
        _Line(f"p{page:04d}-l0002", policy, 116.0, 730.0),
        _Line(f"p{page:04d}-l0003", f"Page {page} of {total}", 278.0, 738.0),
        _Line(f"p{page:04d}-l0004", f"For {right} Use Only", 445.0, 730.0),
        _Line(f"p{page:04d}-l0005", "2099-01-01; 2099-06-15", 445.0, 746.0),
    ))


class DocumentFooterTests(unittest.TestCase):
    def test_complete_footer_is_structured_and_nonsemantic(self):
        footer = extract_document_footer((_page(1), _page(2), _page(3)))
        self.assertIsNotNone(footer)
        self.assertEqual(footer["organization_abbreviation"], "SEO")
        self.assertEqual(footer["policy_number"], "99 TST 2001")
        self.assertEqual(footer["page_count"], 3)
        self.assertEqual(footer["page_numbers"], [1, 2, 3])
        self.assertFalse(footer["semantic_retrieval"])
        self.assertEqual(validate_document_footer(footer), footer)
        self.assertNotIn("p0001-l0000", footer["line_ids"])

    def test_page_number_or_total_conflict_fails_closed(self):
        with self.assertRaisesRegex(DocumentFooterError, "document_footer_page_count_conflict"):
            extract_document_footer((_page(1), _page(2, total=4), _page(3)))
        wrong_page = _page(3)
        wrong_lines = tuple(
            _Line(line.line_id, line.text.replace("Page 3 of 3", "Page 2 of 3"), line.x_min, line.y_min)
            for line in wrong_page.lines
        )
        with self.assertRaisesRegex(DocumentFooterError, "document_footer_page_number_conflict"):
            extract_document_footer((_page(1), _page(2), _Page(3, wrong_lines)))

    def test_organization_or_policy_conflict_fails_closed(self):
        with self.assertRaisesRegex(DocumentFooterError, "document_footer_organization_conflict"):
            extract_document_footer((_page(1), _page(2, right="ALT"), _page(3)))
        with self.assertRaisesRegex(DocumentFooterError, "document_footer_policy_conflict"):
            extract_document_footer((_page(1), _page(2, policy="99 TST 2002"), _page(3)))

    def test_partial_footer_uses_generic_fallback_and_unrelated_margin_is_ignored(self):
        unrelated = _Page(1, (
            _Line("p0001-l0000", "I. Body", 54.0, 120.0),
            _Line("p0001-l0001", "ordinary note", 54.0, 730.0),
        ))
        self.assertIsNone(extract_document_footer((unrelated,)))
        partial = _Page(1, (
            _Line("p0001-l0000", "SEO Policy", 54.0, 730.0),
            _Line("p0001-l0001", "99 TST 2001", 116.0, 730.0),
        ))
        self.assertIsNone(extract_document_footer((partial,)))

        # A document-specific or incompletely extracted footer on only one
        # page is not a proven control-footer profile. Preserve it for the
        # generic recurring-furniture path instead of blocking normalization.
        self.assertIsNone(extract_document_footer((_page(1, total=2), unrelated)))

    def test_complete_footer_removes_only_proven_component_lines(self):
        page = _page(1, total=1)
        unrelated = _Line("p0001-l0099", "Approval instructions remain authoritative.", 54.0, 754.0)
        footer = extract_document_footer((_Page(1, page.lines + (unrelated,)),))
        self.assertIsNotNone(footer)
        self.assertNotIn(unrelated.line_id, footer["line_ids"])
        self.assertIn("p0001-l0003", footer["line_ids"])

    def test_blank_page_disables_specialized_profile_without_failure(self):
        blank = _Page(2, ())
        self.assertIsNone(extract_document_footer((_page(1, total=2), blank)))


if __name__ == "__main__":
    unittest.main()
