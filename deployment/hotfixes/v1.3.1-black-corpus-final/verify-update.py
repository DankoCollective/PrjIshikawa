#!/usr/bin/env python3
"""Focused proof for the cumulative Ishikawa v1.3.1 update."""

from __future__ import annotations

from dataclasses import dataclass

from ishikawa.artifact_pipeline import PIPELINE_TIMEOUT_SECONDS, _credential_is_valid
from ishikawa.document_control import DocumentControlError, extract_document_control_header
from ishikawa.document_footer import DocumentFooterError, extract_document_footer
from ishikawa.ingestion_command import _safe_runtime_reason
from ishikawa.live_document_stage import LiveDocumentStageError, NativeLiveDocumentArtifactStage
from ishikawa.normalization import (
    SourceLine,
    SourcePage,
    SourceWord,
    _furniture_signatures,
    _line_furniture_signature,
)


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
                lines.append(Line(f"p{page:04d}-l{len(lines):04d}", value, x + 105.0, y))
    return Page(page, tuple(lines))


def footer_page(page: int, *, total: int = 2, right_org: str = "SEO") -> Page:
    return Page(
        page,
        (
            Line(f"p{page:04d}-l0000", "A valid body line near the margin", 54.0, 680.0),
            Line(f"p{page:04d}-l0001", "SEO Policy", 54.0, 730.0),
            Line(f"p{page:04d}-l0002", "99 TST 2001", 116.0, 730.0),
            Line(f"p{page:04d}-l0003", f"Page {page} of {total}", 278.0, 738.0),
            Line(f"p{page:04d}-l0004", f"For {right_org} Use Only", 445.0, 730.0),
        ),
    )


def source_line(page: int, text: str) -> SourceLine:
    words = tuple(
        SourceWord(word, 10.0 + index * 20.0, 740.0, 25.0 + index * 20.0, 750.0)
        for index, word in enumerate(text.split())
    )
    return SourceLine(page, 0, words, 10.0, 740.0, 500.0, 750.0)


def require_raises(error_type, reason: str, function) -> None:
    try:
        function()
    except error_type as error:
        if str(error) != reason:
            raise AssertionError(f"unexpected failure reason: {error}") from error
    else:
        raise AssertionError(f"expected failure was not raised: {reason}")


def main() -> int:
    complete_header = extract_document_control_header((header_page(1, "IT"),))
    if complete_header is None:
        raise AssertionError("complete header was not recognized")
    if extract_document_control_header((header_page(1, None),)) is not None:
        raise AssertionError("empty department did not use generic fallback")
    require_raises(
        DocumentControlError,
        "document_control_header_repeat_conflict",
        lambda: extract_document_control_header((header_page(1, "IT"), header_page(2, "HR"))),
    )

    first, second = footer_page(1), footer_page(2)
    footer = extract_document_footer((first, second))
    if footer is None:
        raise AssertionError("complete footer was not recognized")
    body_ids = {"p0001-l0000", "p0002-l0000"}
    if body_ids & set(footer["line_ids"]):
        raise AssertionError("footer recognition removed unrelated margin prose")
    partial = Page(2, (Line("p0002-l0000", "Page 2 of 2", 278.0, 738.0),))
    if extract_document_footer((first, partial)) is not None:
        raise AssertionError("partial footer did not use generic fallback")
    if extract_document_footer((first, Page(2, ()))) is not None:
        raise AssertionError("blank page did not use generic fallback")
    require_raises(
        DocumentFooterError,
        "document_footer_organization_conflict",
        lambda: extract_document_footer((first, footer_page(2, right_org="ALT"))),
    )

    page_lines = tuple(source_line(page, f"Page {page} of 3") for page in (1, 2, 3))
    pages = tuple(
        SourcePage(page, 612.0, 792.0, (line,))
        for page, line in enumerate(page_lines, start=1)
    )
    signatures = _furniture_signatures(pages)
    if len(signatures) != 1 or _line_furniture_signature(page_lines[0]) not in signatures:
        raise AssertionError("Page N of M furniture did not normalize consistently")

    if PIPELINE_TIMEOUT_SECONDS != 7200:
        raise AssertionError("pipeline timeout is not the audited two-hour bound")
    if NativeLiveDocumentArtifactStage.__dataclass_fields__["timeout_seconds"].default != 7200:
        raise AssertionError("live stage timeout is not the audited two-hour bound")
    if not _credential_is_valid(bytearray(b"x")):
        raise AssertionError("credential transport still imposes a strength rule")
    if _credential_is_valid(bytearray()) or _credential_is_valid(bytearray(b"x\n")):
        raise AssertionError("credential transport accepted an absent or multiline value")

    error = LiveDocumentStageError("stage_process_normalization_document_footer_incomplete")
    expected = "live_document_stage_stage_process_normalization_document_footer_incomplete"
    if _safe_runtime_reason(error) != expected:
        raise AssertionError("installed ingestion hid the failed stage")

    print("ishikawa_v1_3_1_cumulative_update_verification=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
