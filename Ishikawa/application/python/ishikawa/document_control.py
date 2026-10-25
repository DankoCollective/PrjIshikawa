"""Deterministic extraction and routing helpers for document mastheads.

The accepted black-corpus first-page masthead contains a non-text logo,
organization name, document context, and a three-row control table.  This
module recognizes the six named table fields from labels and geometry rather
than relying on visible borders, preserves source labels and line identities,
and emits a small canonical metadata object.  The logo is intentionally not
interpreted.  Nothing here infers missing values or changes authorization.
"""

from __future__ import annotations

import re
import unicodedata
from collections.abc import Iterable, Sequence
from typing import Any


HEADER_SCHEMA_VERSION = 1
CANONICAL_FIELDS = (
    "effective_date",
    "policy_number",
    "applicability_class",
    "department",
    "review_date",
    "approval",
)
DISPLAY_LABELS = {
    "effective_date": "Effective Date",
    "policy_number": "Policy Number",
    "applicability_class": "Applicability/Class",
    "department": "Department",
    "review_date": "Date of Review",
    "approval": "Approval",
}
_LABEL_ALIASES = {
    "effective date": "effective_date",
    "policy number": "policy_number",
    "applicability class": "applicability_class",
    "department": "department",
    "dept": "department",
    "date of review": "review_date",
    "approval": "approval",
}
_LABEL_PREFIX = re.compile(
    r"^\s*(effective\s+date|policy\s+number|applicability\s*/\s*class|"
    r"department|dept\.?|date\s+of\s+review|approval)\s*:\s*(.*?)\s*$",
    re.IGNORECASE,
)
_WHITESPACE = re.compile(r"\s+")
_DEPARTMENT_TOKEN = re.compile(r"[A-Za-z0-9]+")


class DocumentControlError(ValueError):
    """Stable failure for malformed or conflicting header metadata."""


def _clean_text(value: str) -> str:
    return _WHITESPACE.sub(" ", unicodedata.normalize("NFC", value).strip())


def canonical_header_label(value: str) -> str | None:
    """Map one supported source label to its canonical field name."""

    if not isinstance(value, str):
        return None
    normalized = _clean_text(value).lower().rstrip(":").rstrip(".")
    normalized = _WHITESPACE.sub(" ", normalized.replace("/", " / "))
    normalized = normalized.replace(" / ", " ")
    return _LABEL_ALIASES.get(normalized)


def normalize_department_value(value: str) -> str:
    """Return a comparison form for an explicitly supplied department value."""

    if not isinstance(value, str):
        raise DocumentControlError("document_control_department_invalid")
    tokens = _DEPARTMENT_TOKEN.findall(unicodedata.normalize("NFKC", value).casefold())
    if not tokens:
        raise DocumentControlError("document_control_department_invalid")
    return " ".join(tokens)


def department_aliases(value: str) -> tuple[str, ...]:
    """Build conservative exact aliases, including a multiword acronym."""

    display = _clean_text(value)
    normalized = normalize_department_value(display)
    aliases = {display, normalized}
    tokens = normalized.split()
    if len(tokens) >= 2:
        acronym = "".join(token[0] for token in tokens if token)
        if len(acronym) >= 2:
            aliases.add(acronym.upper())
            aliases.add(acronym.lower())
    for parenthetical in re.findall(r"\(([^()]{2,32})\)", display):
        aliases.add(_clean_text(parenthetical))
        aliases.add(normalize_department_value(parenthetical))
    return tuple(sorted(aliases, key=lambda item: (item.casefold(), item)))


def _row_groups(lines: Iterable[Any], tolerance: float = 2.0) -> list[list[Any]]:
    groups: list[list[Any]] = []
    for line in sorted(lines, key=lambda item: (round(float(item.y_min), 2), float(item.x_min))):
        if groups and abs(float(groups[-1][0].y_center) - float(line.y_center)) <= tolerance:
            groups[-1].append(line)
        else:
            groups.append([line])
    for group in groups:
        group.sort(key=lambda item: float(item.x_min))
    return groups


def _parse_row(group: Sequence[Any]) -> dict[str, dict[str, Any]]:
    parsed: dict[str, dict[str, Any]] = {}
    index = 0
    while index < len(group):
        line = group[index]
        text = _clean_text(line.text)
        match = _LABEL_PREFIX.fullmatch(text)
        if match is None:
            index += 1
            continue
        canonical = canonical_header_label(match.group(1))
        if canonical is None:
            index += 1
            continue
        value = _clean_text(match.group(2)) if match.group(2) else ""
        line_ids = [line.line_id]
        if not value and index + 1 < len(group):
            candidate = group[index + 1]
            if _LABEL_PREFIX.fullmatch(_clean_text(candidate.text)) is None:
                value = _clean_text(candidate.text)
                line_ids.append(candidate.line_id)
                index += 1
        record = {
            "source_label": _clean_text(match.group(1)),
            "value": value or None,
            "line_ids": line_ids,
        }
        prior = parsed.get(canonical)
        if prior is not None and prior != record:
            raise DocumentControlError("document_control_header_field_conflict")
        parsed[canonical] = record
        index += 1
    return parsed


def _line_height(line: Any) -> float:
    value = getattr(line, "height", None)
    if isinstance(value, (int, float)) and value > 0:
        return float(value)
    y_max = getattr(line, "y_max", None)
    if isinstance(y_max, (int, float)):
        return max(1.0, float(y_max) - float(line.y_min))
    return 1.0


def _masthead_text(
    page: Any,
    *,
    table_line_ids: set[str],
    table_y_min: float,
) -> tuple[dict[str, Any] | None, dict[str, Any] | None, set[str]]:
    """Identify optional centered context and upper-right organization text."""

    width = getattr(page, "width", None)
    if not isinstance(width, (int, float)) or width <= 0:
        return None, None, set()
    candidates = [
        line
        for line in page.lines
        if line.line_id not in table_line_ids
        and float(line.y_center) < table_y_min
        and _LABEL_PREFIX.fullmatch(_clean_text(line.text)) is None
    ]
    centered = [
        line
        for line in candidates
        if float(line.x_min) < float(width) * 0.72
        and float(getattr(line, "x_max", line.x_min)) > float(width) * 0.28
    ]
    context_line = max(
        centered,
        key=lambda line: (_line_height(line), len(_clean_text(line.text))),
        default=None,
    )
    if context_line is None:
        return None, None, set()
    context = {
        "value": _clean_text(context_line.text),
        "page": int(page.number),
        "line_id": context_line.line_id,
    }
    organization_candidates = [
        line
        for line in candidates
        if line.line_id != context_line.line_id
        and float(line.y_center) < float(context_line.y_center)
        and float(line.x_min) >= float(width) * 0.55
    ]
    organization_line = min(
        organization_candidates,
        key=lambda line: (float(line.y_center), -float(line.x_min)),
        default=None,
    )
    organization = None
    line_ids = {context_line.line_id}
    if organization_line is not None:
        organization = {
            "value": _clean_text(organization_line.text),
            "page": int(page.number),
            "line_id": organization_line.line_id,
        }
        line_ids.add(organization_line.line_id)
    return context, organization, line_ids


def extract_document_control_header(pages: Sequence[Any]) -> dict[str, Any] | None:
    """Extract a complete first-page control masthead from parsed pages.

    A partial set is ignored because ordinary body prose can legitimately use
    labels such as ``Policy Number``.  Once any complete six-field header is
    found, every complete occurrence must agree on its non-empty values.  A
    repeated complete table remains supported for defensive compatibility,
    although the accepted layout places the masthead on the first page.
    """

    occurrences: list[dict[str, Any]] = []
    required = set(CANONICAL_FIELDS)
    for page in pages:
        groups = _row_groups(page.lines)
        candidates = [(group, _parse_row(group)) for group in groups]
        page_occurrence: dict[str, Any] | None = None
        for start in range(max(0, len(candidates) - 2)):
            window = candidates[start:start + 3]
            if len(window) != 3 or any(len(parsed) != 2 for _, parsed in window):
                continue
            gaps = [
                float(window[index + 1][0][0].y_center) - float(window[index][0][0].y_center)
                for index in range(2)
            ]
            if any(gap <= 0 or gap > 60 for gap in gaps):
                continue
            page_fields: dict[str, dict[str, Any]] = {}
            duplicate = False
            for _, parsed in window:
                for key, record in parsed.items():
                    if key in page_fields:
                        duplicate = True
                    page_fields[key] = record
            if duplicate or set(page_fields) != required:
                continue
            line_ids = sorted({line.line_id for group, _ in window for line in group})
            found = {
                "page": int(page.number),
                "fields": page_fields,
                "line_ids": line_ids,
                "table_y_min": min(float(line.y_center) for group, _ in window for line in group),
            }
            if page_occurrence is not None and page_occurrence != found:
                raise DocumentControlError("document_control_header_multiple_blocks")
            page_occurrence = found
        if page_occurrence is not None:
            occurrences.append(page_occurrence)
    if not occurrences:
        return None

    first_occurrence = min(occurrences, key=lambda item: item["page"])
    if first_occurrence["page"] != 1:
        return None
    first_page = next(page for page in pages if int(page.number) == first_occurrence["page"])
    document_context, organization_name, masthead_line_ids = _masthead_text(
        first_page,
        table_line_ids=set(first_occurrence["line_ids"]),
        table_y_min=float(first_occurrence["table_y_min"]),
    )
    for occurrence in occurrences:
        occurrence.pop("table_y_min", None)
    first_occurrence["line_ids"] = sorted(
        set(first_occurrence["line_ids"]) | masthead_line_ids
    )

    canonical_values: dict[str, str | None] = {}
    source_labels: dict[str, set[str]] = {key: set() for key in CANONICAL_FIELDS}
    for field in CANONICAL_FIELDS:
        values = {item["fields"][field]["value"] for item in occurrences}
        if len(values) != 1:
            raise DocumentControlError("document_control_header_repeat_conflict")
        canonical_values[field] = next(iter(values))
        source_labels[field].update(
            item["fields"][field]["source_label"] for item in occurrences
        )
    department = canonical_values["department"]
    if not isinstance(department, str) or not department:
        raise DocumentControlError("document_control_department_missing")

    result = {
        "schema_version": HEADER_SCHEMA_VERSION,
        "fields": {
            field: {
                "label": DISPLAY_LABELS[field],
                "source_labels": sorted(source_labels[field], key=str.casefold),
                "value": canonical_values[field],
            }
            for field in CANONICAL_FIELDS
        },
        "department_aliases": list(department_aliases(department)),
        "document_context": document_context,
        "organization_name": organization_name,
        "logo_handling": "non_text_visual_ignored",
        "page_numbers": [item["page"] for item in occurrences],
        "line_ids": sorted({line_id for item in occurrences for line_id in item["line_ids"]}),
        "occurrences": occurrences,
        "repeated": len(occurrences) > 1,
    }
    validate_document_control_header(result)
    return result


def validate_document_control_header(value: Any) -> dict[str, Any]:
    """Validate and return one canonical document-control header mapping."""

    if not isinstance(value, dict) or value.get("schema_version") != HEADER_SCHEMA_VERSION:
        raise DocumentControlError("document_control_header_invalid")
    fields = value.get("fields")
    if not isinstance(fields, dict) or set(fields) != set(CANONICAL_FIELDS):
        raise DocumentControlError("document_control_header_invalid")
    for field in CANONICAL_FIELDS:
        record = fields[field]
        if (
            not isinstance(record, dict)
            or record.get("label") != DISPLAY_LABELS[field]
            or not isinstance(record.get("source_labels"), list)
            or not record["source_labels"]
            or any(not isinstance(item, str) or not item for item in record["source_labels"])
            or (record.get("value") is not None and not isinstance(record["value"], str))
        ):
            raise DocumentControlError("document_control_header_invalid")
    aliases = value.get("department_aliases")
    pages = value.get("page_numbers")
    line_ids = value.get("line_ids")
    occurrences = value.get("occurrences")
    document_context = value.get("document_context")
    organization_name = value.get("organization_name")
    for record in (document_context, organization_name):
        if record is not None and (
            not isinstance(record, dict)
            or set(record) != {"value", "page", "line_id"}
            or not isinstance(record["value"], str)
            or not record["value"]
            or type(record["page"]) is not int
            or record["page"] < 1
            or not isinstance(record["line_id"], str)
            or not record["line_id"]
        ):
            raise DocumentControlError("document_control_header_invalid")
    if (
        not isinstance(aliases, list)
        or not aliases
        or any(not isinstance(item, str) or not item for item in aliases)
        or not isinstance(pages, list)
        or not pages
        or any(type(item) is not int or item < 1 for item in pages)
        or not isinstance(line_ids, list)
        or not line_ids
        or any(not isinstance(item, str) or not item for item in line_ids)
        or not isinstance(occurrences, list)
        or len(occurrences) != len(pages)
        or type(value.get("repeated")) is not bool
        or value.get("logo_handling") != "non_text_visual_ignored"
    ):
        raise DocumentControlError("document_control_header_invalid")
    return value


def header_retrieval_lines(value: dict[str, Any]) -> tuple[str, ...]:
    """Return bounded retrieval text for one validated header."""

    header = validate_document_control_header(value)
    lines = []
    if header["organization_name"] is not None:
        lines.append(f"Organization: {header['organization_name']['value']}")
    if header["document_context"] is not None:
        lines.append(f"Document Context: {header['document_context']['value']}")
    for field in CANONICAL_FIELDS:
        record = header["fields"][field]
        if record["value"]:
            lines.append(f"{record['label']}: {record['value']}")
    return tuple(lines)

