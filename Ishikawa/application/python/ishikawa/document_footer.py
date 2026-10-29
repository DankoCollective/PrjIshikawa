"""Deterministic recognition of the repeated document-control footer."""

from __future__ import annotations

import re
import unicodedata
from collections.abc import Sequence
from typing import Any


FOOTER_SCHEMA_VERSION = 1
_WHITESPACE = re.compile(r"\s+")
_LEFT_ORG = re.compile(r"\b([A-Z][A-Z0-9-]{1,15})\s+Policy\b")
_RIGHT_ORG = re.compile(r"\bFor\s+([A-Z][A-Z0-9-]{1,15})\s+Use\s+Only\b", re.IGNORECASE)
_PAGE = re.compile(r"\bPage\s+(\d+)\s+of\s+(\d+)\b", re.IGNORECASE)
_POLICY = re.compile(r"\b(?:[0-9]{2}\s+[A-Z]{3}\s+[0-9]{4}|TST-[0-9]{4})\b")
_DATE = re.compile(r"\b(?:20|21)[0-9]{2}[-/][01]?[0-9][-/][0-3]?[0-9]\b")


class DocumentFooterError(ValueError):
    """Stable failure for malformed or conflicting footer metadata."""


def _clean(value: str) -> str:
    return _WHITESPACE.sub(" ", unicodedata.normalize("NFC", value).strip())


def extract_document_footer(pages: Sequence[Any]) -> dict[str, Any] | None:
    """Recognize a complete footer on every nonblank page when one is proven.

    The recognized shape is intentionally narrow: left organization
    abbreviation plus ``Policy``, one supported policy identifier, ``Page N of
    M``, and a right-side ``For ORG Use Only`` statement in the bottom margin.
    A partial or document-specific footer is left to the generic recurring-
    furniture normalizer instead of being treated as malformed content.
    """

    eligible = [page for page in pages if not getattr(page, "blank", False)]
    if not eligible:
        return None
    occurrences: list[dict[str, Any]] = []
    for page in eligible:
        height = float(getattr(page, "height", 0.0))
        if height <= 0:
            raise DocumentFooterError("document_footer_geometry_invalid")
        margin = [
            line for line in page.lines
            if float(getattr(line, "y_min", 0.0)) >= height * 0.82
        ]
        combined = _clean(" ".join(line.text for line in sorted(
            margin, key=lambda item: (float(item.y_min), float(item.x_min))
        )))
        left = _LEFT_ORG.search(combined)
        right = _RIGHT_ORG.search(combined)
        page_match = _PAGE.search(combined)
        policies = sorted(set(_POLICY.findall(combined)))
        recognized_parts = sum(value is not None for value in (left, right, page_match)) + bool(policies)
        if recognized_parts == 0:
            continue
        if left is None or right is None or page_match is None or len(policies) != 1:
            continue
        occurrences.append({
            "page": int(page.number),
            "page_number": int(page_match.group(1)),
            "page_count": int(page_match.group(2)),
            "organization_abbreviation_left": left.group(1).upper(),
            "organization_abbreviation_right": right.group(1).upper(),
            "policy_number": policies[0],
            "dates": sorted(set(_DATE.findall(combined))),
            "line_ids": sorted(line.line_id for line in margin),
        })
    if not occurrences:
        return None
    if len(occurrences) != len(eligible):
        return None

    organizations = {
        (item["organization_abbreviation_left"], item["organization_abbreviation_right"])
        for item in occurrences
    }
    policy_numbers = {item["policy_number"] for item in occurrences}
    totals = {item["page_count"] for item in occurrences}
    if len(organizations) != 1 or any(left != right for left, right in organizations):
        raise DocumentFooterError("document_footer_organization_conflict")
    if len(policy_numbers) != 1:
        raise DocumentFooterError("document_footer_policy_conflict")
    if totals != {len(pages)}:
        raise DocumentFooterError("document_footer_page_count_conflict")
    if any(item["page"] != item["page_number"] for item in occurrences):
        raise DocumentFooterError("document_footer_page_number_conflict")
    organization = next(iter(organizations))[0]
    result = {
        "schema_version": FOOTER_SCHEMA_VERSION,
        "organization_abbreviation": organization,
        "policy_number": next(iter(policy_numbers)),
        "page_count": next(iter(totals)),
        "page_numbers": [item["page"] for item in occurrences],
        "line_ids": sorted({line_id for item in occurrences for line_id in item["line_ids"]}),
        "occurrences": occurrences,
        "semantic_retrieval": False,
    }
    validate_document_footer(result)
    return result


def validate_document_footer(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict) or value.get("schema_version") != FOOTER_SCHEMA_VERSION:
        raise DocumentFooterError("document_footer_invalid")
    if set(value) != {
        "schema_version", "organization_abbreviation", "policy_number", "page_count",
        "page_numbers", "line_ids", "occurrences", "semantic_retrieval",
    }:
        raise DocumentFooterError("document_footer_invalid")
    page_count = value.get("page_count")
    page_numbers = value.get("page_numbers")
    occurrences = value.get("occurrences")
    line_ids = value.get("line_ids")
    if (
        not isinstance(value.get("organization_abbreviation"), str)
        or not value["organization_abbreviation"]
        or not isinstance(value.get("policy_number"), str)
        or not value["policy_number"]
        or type(page_count) is not int
        or page_count < 1
        or page_numbers != list(range(1, page_count + 1))
        or not isinstance(occurrences, list)
        or len(occurrences) != page_count
        or not isinstance(line_ids, list)
        or not line_ids
        or any(not isinstance(item, str) or not item for item in line_ids)
        or value.get("semantic_retrieval") is not False
    ):
        raise DocumentFooterError("document_footer_invalid")
    return value
