#!/usr/bin/env python3
"""Focused verifier for the cumulative v1.3.1 black-corpus hotfix."""

from __future__ import annotations

from dataclasses import dataclass

from ishikawa.document_control import (
    DocumentControlError,
    extract_document_control_header,
)
from ishikawa.document_footer import DocumentFooterError, extract_document_footer


@dataclass(frozen=True)
class Line:
    line_id: str
    text: str
    x_min: float
    y_min: float
    font_height: float = 10.0

    @property
    def x_max(self) -> float:
        return self.x_min + max(10.0, len(self.text) * self.font_height * 0.55)

    @property
    def y_max(self) -> float:
        return self.y_min + self.font_height

    @property
    def height(self) -> float:
        return self.font_height

    @property
    def y_center(self) -> float:
        return self.y_min + self.font_height / 2.0


@dataclass(frozen=True)
class Page:
    number: int
    lines: tuple[Line, ...]
    width: float = 612.0
    height: float = 792.0

    @property
    def blank(self) -> bool:
        return not self.lines


def header_page(page: int, department: str | None) -> Page:
    rows = (
        (("Effective Date:", "2099-01-01"), ("Policy Number:", "99 TST 2001")),
        (("Applicability/Class:", "All Operations"), ("Department:", department)),
        (("Date of Review:", "2099-06-30"), ("Approval:", "Board Alpha")),
    )
    lines = [
        Line(f"p{page:04d}-l0000", "Synthetic Example Organization", 430, 20, 8),
        Line(f"p{page:04d}-l0001", "Controlled Materials Access", 205, 70, 20),
    ]
    for row_index, row in enumerate(rows):
        y = 140.0 + row_index * 20.0
        for cell_index, (label, value) in enumerate(row):
            x = 40.0 + cell_index * 280.0
            lines.append(Line(f"p{page:04d}-l{len(lines):04d}", label, x, y))
            if value is not None:
                lines.append(
                    Line(f"p{page:04d}-l{len(lines):04d}", value, x + 105.0, y)
                )
    return Page(page, tuple(lines))


def footer_page(
    page: int,
    *,
    total: int = 2,
    right_organization: str = "SEO",
) -> Page:
    return Page(
        page,
        (
            Line(f"p{page:04d}-l0000", "I. Body", 54.0, 120.0),
            Line(f"p{page:04d}-l0001", "SEO Policy", 54.0, 730.0),
            Line(f"p{page:04d}-l0002", "99 TST 2001", 116.0, 730.0),
            Line(f"p{page:04d}-l0003", f"Page {page} of {total}", 278.0, 738.0),
            Line(
                f"p{page:04d}-l0004",
                f"For {right_organization} Use Only",
                445.0,
                730.0,
            ),
        ),
    )


def require_raises(error_type, reason: str, function) -> None:
    try:
        function()
    except error_type as error:
        if str(error) != reason:
            raise AssertionError(f"unexpected failure reason: {error}") from error
    else:
        raise AssertionError(f"expected failure was not raised: {reason}")


def main() -> int:
    complete_header = extract_document_control_header((
        header_page(1, "Information Technology"),
    ))
    if complete_header is None:
        raise AssertionError("complete header was not recognized")
    if extract_document_control_header((header_page(1, None),)) is not None:
        raise AssertionError("empty department did not use generic fallback")
    require_raises(
        DocumentControlError,
        "document_control_header_repeat_conflict",
        lambda: extract_document_control_header((
            header_page(1, "Information Technology"),
            header_page(2, "Facilities"),
        )),
    )

    complete_footer = extract_document_footer((footer_page(1), footer_page(2)))
    if complete_footer is None:
        raise AssertionError("complete footer was not recognized")
    partial_page = Page(
        2,
        (
            Line("p0002-l0000", "II. Body", 54.0, 120.0),
            Line("p0002-l0001", "Page 2 of 2", 278.0, 738.0),
        ),
    )
    if extract_document_footer((footer_page(1), partial_page)) is not None:
        raise AssertionError("partial footer did not use generic fallback")
    require_raises(
        DocumentFooterError,
        "document_footer_organization_conflict",
        lambda: extract_document_footer((
            footer_page(1),
            footer_page(2, right_organization="ALT"),
        )),
    )
    print("black_corpus_compatibility_verification=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
