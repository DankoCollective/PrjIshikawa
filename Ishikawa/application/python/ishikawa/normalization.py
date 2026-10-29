"""Deterministic normalization of accepted Poppler bounding-box evidence.

The raw Poppler archive remains the evidence layer.  This module creates a
traceable canonical layer without guessing through ambiguous geometry.  It
uses only the Python standard library and never invokes an external command.
"""

from __future__ import annotations

import hashlib
import json
import math
import re
import statistics
import tarfile
import unicodedata
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Iterable

from .canonical import canonical_json_bytes, domain_digest
from .document_control import DocumentControlError, extract_document_control_header
from .document_footer import DocumentFooterError, extract_document_footer


MAX_ARCHIVE_BYTES = 128 * 1024 * 1024
ROW_TOLERANCE = 2.0
TABLE_COLUMN_TOLERANCE = 18.0
ROMAN_HEADING = re.compile(r"^[IVXLCDM]+\.\s+\S")
LIST_MARKER = re.compile(r"^(?:[0-9]+|[A-Za-z])\.$")
CHECKBOX = re.compile(r"^\[\s*([Xx]?)\s*\]\s+(.+)$")
DOCUMENT_REFERENCE = re.compile(r"\b(?:[0-9]{2}\s+[A-Z]{3}\s+[0-9]{4}|TST-[0-9]{4})\b")


class NormalizationError(RuntimeError):
    """A stable normalization failure safe for operator-facing classification."""


@dataclass(frozen=True, slots=True)
class SourceWord:
    text: str
    x_min: float
    y_min: float
    x_max: float
    y_max: float


@dataclass(frozen=True, slots=True)
class SourceLine:
    page: int
    ordinal: int
    words: tuple[SourceWord, ...]
    x_min: float
    y_min: float
    x_max: float
    y_max: float

    @property
    def line_id(self) -> str:
        return f"p{self.page:04d}-l{self.ordinal:04d}"

    @property
    def text(self) -> str:
        return unicodedata.normalize("NFC", " ".join(word.text for word in self.words))

    @property
    def height(self) -> float:
        return self.y_max - self.y_min

    @property
    def y_center(self) -> float:
        return (self.y_min + self.y_max) / 2


@dataclass(frozen=True, slots=True)
class SourcePage:
    number: int
    width: float
    height: float
    lines: tuple[SourceLine, ...]

    @property
    def blank(self) -> bool:
        return not self.lines


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _safe_stem(filename: str) -> str:
    value = re.sub(r"[^A-Za-z0-9_.-]+", "_", filename)
    return value[:-4] if value.lower().endswith(".pdf") else value


def _load_json_bytes(value: bytes, reason: str) -> dict[str, Any]:
    try:
        result = json.loads(value.decode("utf-8", "strict"))
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise NormalizationError(reason) from exc
    if not isinstance(result, dict):
        raise NormalizationError(reason)
    return result


def _load_json_file(path: Path, reason: str) -> dict[str, Any]:
    if not path.is_file() or path.is_symlink():
        raise NormalizationError(reason)
    try:
        return _load_json_bytes(path.read_bytes(), reason)
    except OSError as exc:
        raise NormalizationError(reason) from exc


def _load_archive(path: Path) -> dict[str, bytes]:
    if not path.is_file() or path.is_symlink() or path.stat().st_size > MAX_ARCHIVE_BYTES:
        raise NormalizationError("unsafe_extraction_archive")
    members: dict[str, bytes] = {}
    try:
        with tarfile.open(path, "r:") as archive:
            for member in archive.getmembers():
                pure = PurePosixPath(member.name)
                if (
                    member.name.startswith("/")
                    or ".." in pure.parts
                    or member.issym()
                    or member.islnk()
                    or member.isdev()
                    or not (member.isfile() or member.isdir())
                ):
                    raise NormalizationError("unsafe_extraction_archive_member")
                if not member.isfile():
                    continue
                if member.size > MAX_ARCHIVE_BYTES or pure.as_posix() in members:
                    raise NormalizationError("unsafe_extraction_archive_member")
                handle = archive.extractfile(member)
                if handle is None:
                    raise NormalizationError("invalid_extraction_archive")
                members[pure.as_posix()] = handle.read()
    except (OSError, tarfile.TarError) as exc:
        raise NormalizationError("invalid_extraction_archive") from exc
    if "observations.json" not in members:
        raise NormalizationError("missing_extraction_observations")
    return members


def _local_name(element: ET.Element) -> str:
    return element.tag.rsplit("}", 1)[-1]


def _finite_float(value: str | None) -> float:
    try:
        result = float(value or "")
    except ValueError as exc:
        raise NormalizationError("invalid_bbox_geometry") from exc
    if not math.isfinite(result):
        raise NormalizationError("invalid_bbox_geometry")
    return result


def _parse_bbox(data: bytes) -> tuple[SourcePage, ...]:
    if b"<!ENTITY" in data.upper():
        raise NormalizationError("unsafe_bbox_xml")
    try:
        root = ET.fromstring(data)
    except ET.ParseError as exc:
        raise NormalizationError("invalid_bbox_xml") from exc
    pages: list[SourcePage] = []
    for page_number, page_element in enumerate(
        (item for item in root.iter() if _local_name(item) == "page"), start=1
    ):
        width = _finite_float(page_element.attrib.get("width"))
        height = _finite_float(page_element.attrib.get("height"))
        provisional: list[tuple[float, float, tuple[SourceWord, ...]]] = []
        for line_element in (item for item in page_element.iter() if _local_name(item) == "line"):
            words: list[SourceWord] = []
            for word_element in (item for item in line_element.iter() if _local_name(item) == "word"):
                text = unicodedata.normalize("NFC", "".join(word_element.itertext()).strip())
                if not text:
                    continue
                word = SourceWord(
                    text=text,
                    x_min=_finite_float(word_element.attrib.get("xMin")),
                    y_min=_finite_float(word_element.attrib.get("yMin")),
                    x_max=_finite_float(word_element.attrib.get("xMax")),
                    y_max=_finite_float(word_element.attrib.get("yMax")),
                )
                if word.x_max < word.x_min or word.y_max < word.y_min:
                    raise NormalizationError("invalid_bbox_geometry")
                words.append(word)
            if not words:
                continue
            words.sort(key=lambda item: (item.x_min, item.x_max))
            provisional.append((
                _finite_float(line_element.attrib.get("yMin")),
                _finite_float(line_element.attrib.get("xMin")),
                tuple(words),
            ))
        provisional.sort(key=lambda item: (round(item[0], 2), item[1]))
        lines = tuple(
            SourceLine(
                page=page_number,
                ordinal=index,
                words=words,
                x_min=min(word.x_min for word in words),
                y_min=min(word.y_min for word in words),
                x_max=max(word.x_max for word in words),
                y_max=max(word.y_max for word in words),
            )
            for index, (_, _, words) in enumerate(provisional)
        )
        pages.append(SourcePage(page_number, width, height, lines))
    if not pages:
        raise NormalizationError("bbox_page_inventory_missing")
    return tuple(pages)


def _line_span(line: SourceLine, start: int = 0, end: int | None = None) -> dict[str, Any]:
    stop = len(line.words) if end is None else end
    if start < 0 or stop <= start or stop > len(line.words):
        raise NormalizationError("invalid_source_span")
    selected = line.words[start:stop]
    return {
        "line_id": line.line_id,
        "page": line.page,
        "word_start": start,
        "word_end": stop,
        "bbox": [
            min(word.x_min for word in selected),
            min(word.y_min for word in selected),
            max(word.x_max for word in selected),
            max(word.y_max for word in selected),
        ],
    }


def _row_groups(lines: Iterable[SourceLine]) -> list[list[SourceLine]]:
    groups: list[list[SourceLine]] = []
    for line in sorted(lines, key=lambda item: (round(item.y_min, 2), item.x_min)):
        if groups and abs(groups[-1][0].y_center - line.y_center) <= ROW_TOLERANCE:
            groups[-1].append(line)
        else:
            groups.append([line])
    for group in groups:
        group.sort(key=lambda item: item.x_min)
    return groups


def _furniture_signatures(pages: tuple[SourcePage, ...]) -> set[str]:
    eligible = [page for page in pages if not page.blank]
    threshold = max(2, math.ceil(len(eligible) * 0.5))
    occurrences: dict[str, set[int]] = {}
    for page in eligible:
        for line in page.lines:
            in_margin = line.y_min <= page.height * 0.15 or line.y_max >= page.height * 0.85
            if not in_margin:
                continue
            normalized = _normalized_furniture_text(line.text)
            band = round(line.y_center / 4)
            signature = f"{band}:{normalized}"
            occurrences.setdefault(signature, set()).add(page.number)
    return {signature for signature, page_numbers in occurrences.items() if len(page_numbers) >= threshold}


def _line_furniture_signature(line: SourceLine) -> str:
    normalized = _normalized_furniture_text(line.text)
    return f"{round(line.y_center / 4)}:{normalized}"


def _normalized_furniture_text(text: str) -> str:
    """Normalize changing page counters without changing surrounding text."""

    with_total = re.sub(
        r"(?i)(\bpage\s+)\d+(\s+of\s+)\d+\s*$",
        r"\1{page}\2{pages}",
        text,
    )
    return re.sub(r"(?i)(\bpage\s+)\d+\s*$", r"\1{page}", with_total)


def _detect_tables(page: SourcePage, excluded: set[str]) -> list[list[list[SourceLine]]]:
    candidates = [group for group in _row_groups(line for line in page.lines if line.line_id not in excluded) if len(group) >= 3]
    tables: list[list[list[SourceLine]]] = []
    index = 0
    while index < len(candidates):
        run = [candidates[index]]
        expected_x = [line.x_min for line in candidates[index]]
        cursor = index + 1
        while cursor < len(candidates):
            group = candidates[cursor]
            prior_y = run[-1][0].y_center
            positions = [line.x_min for line in group]
            compatible = (
                len(positions) == len(expected_x)
                and group[0].y_center - prior_y <= 80
                and all(abs(left - right) <= TABLE_COLUMN_TOLERANCE for left, right in zip(positions, expected_x))
            )
            if not compatible:
                break
            run.append(group)
            cursor += 1
        if len(run) >= 3:
            tables.append(run)
            index = cursor
        else:
            index += 1
    return tables


def _heading_text(line: SourceLine, body_height: float) -> str | None:
    text = line.text
    typographic = line.height >= body_height * 1.18 and len(line.words) <= 12
    if ROMAN_HEADING.match(text) and typographic:
        return text
    if line.words and LIST_MARKER.match(line.words[0].text):
        return None
    if not typographic or text.endswith(":"):
        return None
    if " | " in text:
        suffix = text.rsplit(" | ", 1)[-1].strip()
        return suffix or text
    return text


def _checkbox_value(text: str) -> tuple[bool, str] | None:
    match = CHECKBOX.match(text)
    if match is None:
        return None
    return match.group(1).upper() == "X", match.group(2)


def _references(text: str) -> list[str]:
    return sorted(set(match.group(0) for match in DOCUMENT_REFERENCE.finditer(text)))


def _new_unit(
    *,
    kind: str,
    text: str,
    structural_path: tuple[str, ...],
    spans: list[dict[str, Any]],
    rules: list[str],
    properties: dict[str, Any] | None = None,
) -> dict[str, Any]:
    pages = sorted({int(span["page"]) for span in spans})
    if not pages:
        raise NormalizationError("unit_without_source_span")
    normalized_text = unicodedata.normalize("NFC", text.strip())
    if not normalized_text:
        raise NormalizationError("empty_normalized_unit")
    record: dict[str, Any] = {
        "kind": kind,
        "page_start": pages[0],
        "page_end": pages[-1],
        "structural_path": list(structural_path),
        "text": normalized_text,
        "source_spans": spans,
        "rules": rules,
        "properties": properties or {},
        "references": _references(normalized_text),
    }
    record["input_digest"] = domain_digest(
        "ishikawa.normalization-input.v1",
        {"source_spans": spans, "source_text": text},
    )
    record["output_digest"] = domain_digest(
        "ishikawa.normalization-output.v1",
        {"kind": kind, "text": normalized_text, "properties": record["properties"]},
    )
    record["unit_id"] = domain_digest("ishikawa.normalized-unit.v1", record)
    return record


def _table_unit(
    rows: list[list[SourceLine]],
    structural_path: tuple[str, ...],
    context: str,
) -> dict[str, Any]:
    header_lines = rows[0]
    headers = [line.text for line in header_lines]
    data_rows: list[dict[str, Any]] = []
    for row_index, row in enumerate(rows[1:]):
        cells = []
        for column_index, line in enumerate(row):
            cells.append({
                "column_index": column_index,
                "header": headers[column_index],
                "value": line.text,
                "row_span": 1,
                "column_span": 1,
                "source_span": _line_span(line),
            })
        data_rows.append({"row_index": row_index, "continuation": False, "cells": cells})
    spans = [_line_span(line) for row in rows for line in row]
    projection_lines = [" | ".join(headers)] + [
        " | ".join(cell["value"] for cell in row["cells"]) for row in data_rows
    ]
    properties = {
        "authority": "structured_table",
        "context": context,
        "headers": headers,
        "rows": data_rows,
        "continued_from_previous_page": False,
        "continues_on_next_page": False,
    }
    return _new_unit(
        kind="table",
        text="\n".join(projection_lines),
        structural_path=structural_path,
        spans=spans,
        rules=["physical_line_order_v1", "structured_table_geometry_v1", "unicode_nfc_v1"],
        properties=properties,
    )


def _form_units(
    page: SourcePage,
    excluded: set[str],
    path_by_line: dict[str, tuple[str, ...]],
) -> tuple[list[dict[str, Any]], set[str]]:
    available = [line for line in page.lines if line.line_id not in excluded]
    labels = [line for line in available if line.text.endswith(":") and len(line.words) <= 5]
    checkbox_lines = [line for line in available if _checkbox_value(line.text) is not None]
    if len(labels) < 2 and len(checkbox_lines) < 2:
        return [], set()
    groups = _row_groups(available)
    group_by_line = {line.line_id: group for group in groups for line in group}
    assigned: set[str] = set()
    units: list[dict[str, Any]] = []
    for label in sorted(labels, key=lambda item: (item.y_min, item.x_min)):
        if label.line_id in assigned:
            continue
        row = group_by_line[label.line_id]
        later_labels = [line for line in row if line.text.endswith(":") and line.x_min > label.x_min]
        x_limit = min((line.x_min for line in later_labels), default=math.inf)
        values = [
            line for line in row
            if line.x_min > label.x_max and line.x_min < x_limit and not line.text.endswith(":")
        ]
        choices = [(line, _checkbox_value(line.text)) for line in values]
        choices = [(line, value) for line, value in choices if value is not None]
        structural_path = path_by_line.get(label.line_id, ())
        if choices:
            spans = [_line_span(label)] + [_line_span(line) for line, _ in choices]
            options = [
                {"label": value[1], "selected": value[0], "source_span": _line_span(line)}
                for line, value in choices
            ]
            text = label.text + " " + " ".join(
                f"{'[X]' if option['selected'] else '[ ]'} {option['label']}" for option in options
            )
            units.append(_new_unit(
                kind="checkbox_group",
                text=text,
                structural_path=structural_path,
                spans=spans,
                rules=["physical_line_order_v1", "form_checkbox_geometry_v1", "unicode_nfc_v1"],
                properties={"authority": "structured_form", "label": label.text, "options": options},
            ))
            assigned.update(span["line_id"] for span in spans)
            continue
        if values:
            selected_values = values
        else:
            selected_values = []
            prior_y = label.y_center
            for candidate in available:
                if candidate.y_center <= label.y_center or candidate.line_id in assigned:
                    continue
                if candidate.text.endswith(":") or _checkbox_value(candidate.text) is not None:
                    break
                gap = candidate.y_center - prior_y
                if not selected_values and gap > 65:
                    break
                if selected_values and gap > 22:
                    break
                selected_values.append(candidate)
                prior_y = candidate.y_center
        if not selected_values:
            continue
        spans = [_line_span(label)] + [_line_span(line) for line in selected_values]
        value_text = " ".join(line.text for line in selected_values)
        units.append(_new_unit(
            kind="form_field",
            text=f"{label.text} {value_text}",
            structural_path=structural_path,
            spans=spans,
            rules=["physical_line_order_v1", "form_label_value_geometry_v1", "wrapped_line_join_v1", "unicode_nfc_v1"],
            properties={"authority": "structured_form", "label": label.text, "value": value_text},
        ))
        assigned.update(span["line_id"] for span in spans)
    return units, assigned


def _list_segments(line: SourceLine) -> list[tuple[int, int, str, str]]:
    markers = [
        index
        for index, word in enumerate(line.words)
        if (
            LIST_MARKER.match(word.text)
            and index + 1 < len(line.words)
            and (index == 0 or line.words[index - 1].text.lower().rstrip(":") not in {"page", "section"})
        )
    ]
    if not markers or markers[0] != 0:
        return []
    segments: list[tuple[int, int, str, str]] = []
    for offset, start in enumerate(markers):
        end = markers[offset + 1] if offset + 1 < len(markers) else len(line.words)
        if end - start < 2:
            return []
        text = " ".join(word.text for word in line.words[start:end])
        segments.append((start, end, line.words[start].text, text))
    return segments


def _general_units(
    page: SourcePage,
    excluded: set[str],
    heading_by_line: dict[str, str],
    path_by_line: dict[str, tuple[str, ...]],
    body_height: float,
) -> list[dict[str, Any]]:
    units: list[dict[str, Any]] = []
    pending: dict[str, Any] | None = None

    def flush() -> None:
        nonlocal pending
        if pending is not None:
            units.append(_new_unit(**pending))
            pending = None

    for line in page.lines:
        if line.line_id in excluded:
            continue
        path = path_by_line.get(line.line_id, ())
        heading = heading_by_line.get(line.line_id)
        if heading is not None:
            flush()
            units.append(_new_unit(
                kind="heading",
                text=heading,
                structural_path=path,
                spans=[_line_span(line)],
                rules=["physical_line_order_v1", "heading_typography_or_numbering_v1", "unicode_nfc_v1"],
                properties={"source_line_text": line.text},
            ))
            continue
        segments = _list_segments(line)
        if segments:
            flush()
            for segment_index, (start, end, marker, text) in enumerate(segments):
                body = text[len(marker):].strip()
                kind = (
                    "definition"
                    if marker[0].isalpha() and re.match(r"^[A-Za-z].+\.\s+\S", body)
                    else "list_item"
                )
                candidate = {
                    "kind": kind,
                    "text": text,
                    "structural_path": path,
                    "spans": [_line_span(line, start, end)],
                    "rules": ["physical_line_order_v1", "inline_list_marker_split_v1", "unicode_nfc_v1"],
                    "properties": {"marker": marker},
                }
                if segment_index + 1 < len(segments):
                    units.append(_new_unit(**candidate))
                else:
                    pending = candidate
            continue
        kind = "definition" if " means " in line.text else "paragraph"
        if pending is not None:
            prior_span = pending["spans"][-1]
            prior_line_id = prior_span["line_id"]
            prior_line = next(item for item in page.lines if item.line_id == prior_line_id)
            gap = line.y_min - prior_line.y_max
            prior_text = pending["text"]
            wrapped = (
                (pending["kind"] == kind or pending["kind"] in {"definition", "list_item"})
                and pending["structural_path"] == path
                and gap <= body_height * 1.8
                and not re.search(r"[.!?:;]$", prior_text)
            )
            if wrapped:
                pending["text"] = f"{prior_text} {line.text}"
                pending["spans"].append(_line_span(line))
                if "wrapped_line_join_v1" not in pending["rules"]:
                    pending["rules"].append("wrapped_line_join_v1")
                continue
            flush()
        pending = {
            "kind": kind,
            "text": line.text,
            "structural_path": path,
            "spans": [_line_span(line)],
            "rules": ["physical_line_order_v1", "unicode_nfc_v1"],
            "properties": {},
        }
    flush()
    return units


def _coverage_tokens(pages: tuple[SourcePage, ...]) -> set[tuple[str, int]]:
    return {(line.line_id, index) for page in pages for line in page.lines for index in range(len(line.words))}


def _unit_coverage(units: list[dict[str, Any]]) -> list[tuple[str, int]]:
    covered: list[tuple[str, int]] = []
    for unit in units:
        for span in unit["source_spans"]:
            covered.extend((span["line_id"], index) for index in range(span["word_start"], span["word_end"]))
    return covered


def _normalize_document(
    filename: str,
    manifest_entry: dict[str, Any],
    observation: dict[str, Any],
    bbox_data: bytes,
) -> dict[str, Any]:
    pages = _parse_bbox(bbox_data)
    if len(pages) != observation.get("pdfinfo", {}).get("pages"):
        raise NormalizationError("page_inventory_mismatch")
    try:
        document_control_header = extract_document_control_header(pages)
    except DocumentControlError as error:
        raise NormalizationError(str(error)) from error
    try:
        document_control_footer = extract_document_footer(pages)
    except DocumentFooterError as error:
        raise NormalizationError(str(error)) from error
    if document_control_header is not None and document_control_footer is not None:
        header_policy_number = document_control_header["fields"]["policy_number"]["value"]
        if header_policy_number != document_control_footer["policy_number"]:
            raise NormalizationError("document_header_footer_policy_conflict")
    furniture_signatures = _furniture_signatures(pages)
    furniture_ids = {
        line.line_id
        for page in pages
        for line in page.lines
        if _line_furniture_signature(line) in furniture_signatures
    }
    if document_control_header is not None:
        furniture_ids.update(document_control_header["line_ids"])
    if document_control_footer is not None:
        furniture_ids.update(document_control_footer["line_ids"])
    table_rows_by_page: dict[int, list[list[list[SourceLine]]]] = {}
    table_line_ids: set[str] = set()
    for page in pages:
        tables = _detect_tables(page, furniture_ids)
        table_rows_by_page[page.number] = tables
        table_line_ids.update(line.line_id for table in tables for row in table for line in row)

    all_heights = [
        line.height
        for page in pages
        for line in page.lines
        if line.line_id not in furniture_ids and line.line_id not in table_line_ids
    ]
    body_height = statistics.median(all_heights) if all_heights else 1.0

    heading_by_line: dict[str, str] = {}
    for page in pages:
        for line in page.lines:
            if line.line_id in furniture_ids or line.line_id in table_line_ids:
                continue
            heading = _heading_text(line, body_height)
            if heading is not None:
                heading_by_line[line.line_id] = heading

    path_by_line: dict[str, tuple[str, ...]] = {}
    current_path: tuple[str, ...] = ()
    for page in pages:
        for line in page.lines:
            heading = heading_by_line.get(line.line_id)
            if heading is not None:
                current_path = (heading,)
            path_by_line[line.line_id] = current_path

    units: list[dict[str, Any]] = []
    for page in pages:
        excluded = set()
        for line in page.lines:
            if line.line_id in furniture_ids:
                units.append(_new_unit(
                    kind="page_furniture",
                    text=line.text,
                    structural_path=path_by_line.get(line.line_id, ()),
                    spans=[_line_span(line)],
                    rules=["physical_line_order_v1", "geometry_recurrence_furniture_v1", "unicode_nfc_v1"],
                    properties={"signature": _line_furniture_signature(line)},
                ))
                excluded.add(line.line_id)
        for table in table_rows_by_page[page.number]:
            first_line = table[0][0]
            preceding = [
                line for line in page.lines
                if line.y_center < first_line.y_center and line.line_id not in furniture_ids
            ]
            context = preceding[-1].text if preceding else ""
            units.append(_table_unit(table, path_by_line.get(first_line.line_id, ()), context))
            excluded.update(line.line_id for row in table for line in row)
        form_units, form_ids = _form_units(
            page,
            excluded | set(heading_by_line),
            path_by_line,
        )
        units.extend(form_units)
        excluded.update(form_ids)
        units.extend(_general_units(page, excluded, heading_by_line, path_by_line, body_height))

    units.sort(key=lambda unit: (
        unit["page_start"],
        unit["source_spans"][0]["bbox"][1],
        unit["source_spans"][0]["bbox"][0],
        unit["kind"],
    ))
    for ordinal, unit in enumerate(units):
        unit["ordinal"] = ordinal

    expected_coverage = _coverage_tokens(pages)
    actual_coverage = _unit_coverage(units)
    if len(actual_coverage) != len(set(actual_coverage)):
        raise NormalizationError("overlapping_normalized_source_spans")
    if set(actual_coverage) != expected_coverage:
        raise NormalizationError("incomplete_normalized_source_coverage")

    references = sorted({reference for unit in units for reference in unit["references"]})
    kind_counts: dict[str, int] = {}
    for unit in units:
        kind_counts[unit["kind"]] = kind_counts.get(unit["kind"], 0) + 1
    document = {
        "doc_id": manifest_entry["doc_id"],
        "filename": filename,
        "source_sha256": manifest_entry["sha256"],
        "source_bytes": manifest_entry["bytes"],
        "bbox_sha256": _sha256_bytes(bbox_data),
        "page_count": len(pages),
        "blank_pages": [page.number for page in pages if page.blank],
        "pages": [
            {"page": page.number, "width": page.width, "height": page.height, "blank": page.blank}
            for page in pages
        ],
        "units": units,
        "unit_kind_counts": dict(sorted(kind_counts.items())),
        "references": references,
    }
    if document_control_header is not None:
        document["document_control_header"] = document_control_header
    if document_control_footer is not None:
        document["document_control_footer"] = document_control_footer
    document["normalization_digest"] = domain_digest("ishikawa.normalized-document.v1", document)
    return document


def normalize_extraction_archive(
    archive_path: str | Path,
    source_manifest_path: str | Path,
    *,
    expected_archive_sha256: str,
) -> dict[str, Any]:
    """Normalize one accepted manifest-bound extraction archive deterministically."""

    archive_file = Path(archive_path)
    manifest_file = Path(source_manifest_path)
    if len(expected_archive_sha256) != 64 or any(
        character not in "0123456789abcdef" for character in expected_archive_sha256
    ):
        raise NormalizationError("invalid_expected_archive_identity")
    if _sha256_file(archive_file) != expected_archive_sha256:
        raise NormalizationError("extraction_archive_identity_mismatch")
    manifest = _load_json_file(manifest_file, "invalid_source_manifest")
    files = manifest.get("files")
    if manifest.get("schema_version") != 1 or not isinstance(files, list) or not files:
        raise NormalizationError("invalid_source_manifest")
    archive = _load_archive(archive_file)
    observations = _load_json_bytes(archive["observations.json"], "invalid_extraction_observations")
    observed_documents = observations.get("documents")
    if observations.get("schema_version") != 1 or not isinstance(observed_documents, list):
        raise NormalizationError("invalid_extraction_observations")
    observed_by_name = {
        item.get("filename"): item for item in observed_documents if isinstance(item, dict)
    }
    documents: list[dict[str, Any]] = []
    for entry in files:
        if not isinstance(entry, dict) or not isinstance(entry.get("filename"), str):
            raise NormalizationError("invalid_source_manifest")
        filename = entry["filename"]
        observation = observed_by_name.get(filename)
        if not isinstance(observation, dict):
            raise NormalizationError("missing_document_observation")
        member = f"raw/{_safe_stem(filename)}/bbox.html"
        bbox_data = archive.get(member)
        if bbox_data is None:
            raise NormalizationError("missing_bbox_evidence")
        if observation.get("outputs", {}).get("bbox") != _sha256_bytes(bbox_data):
            raise NormalizationError("bbox_evidence_identity_mismatch")
        documents.append(_normalize_document(filename, entry, observation, bbox_data))
    result = {
        "schema_version": 1,
        "method": "ishikawa-poppler-normalization-v1",
        "source_archive_sha256": expected_archive_sha256,
        "source_manifest_sha256": _sha256_file(manifest_file),
        "transform_rules": [
            "physical_line_order_v1",
            "unicode_nfc_v1",
            "geometry_recurrence_furniture_v1",
            "heading_typography_or_numbering_v1",
            "wrapped_line_join_v1",
            "inline_list_marker_split_v1",
            "structured_table_geometry_v1",
            "form_label_value_geometry_v1",
            "form_checkbox_geometry_v1",
        ],
        "documents": documents,
    }
    result["normalization_set_digest"] = domain_digest("ishikawa.normalization-set.v1", result)
    return result


def normalized_json_bytes(value: dict[str, Any]) -> bytes:
    """Return the canonical UTF-8 JSON artifact with one trailing newline."""

    return canonical_json_bytes(value) + b"\n"
