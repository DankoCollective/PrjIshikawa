#!/usr/bin/env python3
"""Behavioral verification for the bounded v1.3.1 footer fallback hotfix."""

from __future__ import annotations

from dataclasses import dataclass

from ishikawa.document_footer import DocumentFooterError, extract_document_footer


@dataclass(frozen=True)
class Line:
    line_id: str
    text: str
    x_min: float
    y_min: float


@dataclass(frozen=True)
class Page:
    number: int
    lines: tuple[Line, ...]
    width: float = 612.0
    height: float = 792.0

    @property
    def blank(self) -> bool:
        return not self.lines


def complete_page(page: int, total: int = 2, policy: str = "99 TST 2001") -> Page:
    return Page(page, (
        Line(f"p{page:04d}-l0000", "I. Body", 54.0, 120.0),
        Line(f"p{page:04d}-l0001", "SEO Policy", 54.0, 730.0),
        Line(f"p{page:04d}-l0002", policy, 116.0, 730.0),
        Line(f"p{page:04d}-l0003", f"Page {page} of {total}", 278.0, 738.0),
        Line(f"p{page:04d}-l0004", "For SEO Use Only", 445.0, 730.0),
    ))


partial = Page(1, (
    Line("p0001-l0000", "ORG Policy", 54.0, 730.0),
    Line("p0001-l0001", "08 HC 1234", 116.0, 730.0),
))
assert extract_document_footer((partial,)) is None

unrelated = Page(2, (
    Line("p0002-l0000", "II. Body", 54.0, 120.0),
    Line("p0002-l0001", "document-specific footer", 54.0, 730.0),
))
assert extract_document_footer((complete_page(1), unrelated)) is None

try:
    extract_document_footer((complete_page(1), complete_page(2, policy="99 TST 2002")))
except DocumentFooterError as error:
    assert str(error) == "document_footer_policy_conflict"
else:
    raise AssertionError("recognized conflicting footer did not fail closed")

print("footer_hotfix_verification=PASS")
