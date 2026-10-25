#!/usr/bin/env python3
"""Evaluate captured synthetic PDF extraction without exposing held-out truth."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import tarfile
import tempfile
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Iterable


MAX_ARCHIVE_BYTES = 128 * 1024 * 1024
TEXT_COMMAND = re.compile(
    rb"BT\s+/[A-Za-z0-9]+\s+[0-9.]+\s+Tf\s+1\s+0\s+0\s+1\s+"
    rb"(?P<x>-?[0-9.]+)\s+(?P<y>-?[0-9.]+)\s+Tm\s+"
    rb"\((?P<text>(?:\\.|[^\\)])*)\)\s+Tj\s+ET"
)
STREAM = re.compile(rb"stream\r?\n(?P<body>.*?)\r?\nendstream", re.DOTALL)


class EvaluationError(RuntimeError):
    """A content-safe acceptance failure."""

    def __init__(self, reason: str, details: dict[str, Any] | None = None) -> None:
        super().__init__(reason)
        self.details = details or {}


@dataclass(frozen=True)
class Word:
    text: str
    x_min: float
    y_min: float
    x_max: float
    y_max: float

    @property
    def x_center(self) -> float:
        return (self.x_min + self.x_max) / 2

    @property
    def y_center(self) -> float:
        return (self.y_min + self.y_max) / 2


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_json(path: Path, reason: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise EvaluationError(reason) from exc
    if not isinstance(value, dict):
        raise EvaluationError(reason)
    return value


def load_archive(path: Path) -> dict[str, bytes]:
    if not path.is_file() or path.is_symlink() or path.stat().st_size > MAX_ARCHIVE_BYTES:
        raise EvaluationError("unsafe_capture_archive")
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
                    raise EvaluationError("unsafe_capture_archive_member")
                if member.isfile():
                    if member.size > MAX_ARCHIVE_BYTES:
                        raise EvaluationError("unsafe_capture_archive_member")
                    if pure.as_posix() in members:
                        raise EvaluationError("duplicate_capture_archive_member")
                    handle = archive.extractfile(member)
                    if handle is None:
                        raise EvaluationError("invalid_capture_archive")
                    members[pure.as_posix()] = handle.read()
    except (OSError, tarfile.TarError) as exc:
        raise EvaluationError("invalid_capture_archive") from exc
    if "observations.json" not in members:
        raise EvaluationError("missing_capture_observations")
    return members


def parse_observations(data: bytes) -> dict[str, Any]:
    try:
        value = json.loads(data.decode("utf-8", "strict"))
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise EvaluationError("invalid_capture_observations") from exc
    if not isinstance(value, dict):
        raise EvaluationError("invalid_capture_observations")
    return value


def safe_stem(filename: str) -> str:
    value = re.sub(r"[^A-Za-z0-9_.-]+", "_", filename)
    return value[:-4] if value.lower().endswith(".pdf") else value


def pdf_unescape(data: bytes) -> str:
    output = bytearray()
    index = 0
    escapes = {
        ord("n"): ord("\n"),
        ord("r"): ord("\r"),
        ord("t"): ord("\t"),
        ord("b"): ord("\b"),
        ord("f"): ord("\f"),
        ord("("): ord("("),
        ord(")"): ord(")"),
        ord("\\"): ord("\\"),
    }
    while index < len(data):
        value = data[index]
        if value != ord("\\"):
            output.append(value)
            index += 1
            continue
        index += 1
        if index >= len(data):
            output.append(ord("\\"))
            break
        value = data[index]
        if value in escapes:
            output.append(escapes[value])
            index += 1
            continue
        if 48 <= value <= 55:
            digits = bytearray([value])
            index += 1
            while index < len(data) and len(digits) < 3 and 48 <= data[index] <= 55:
                digits.append(data[index])
                index += 1
            output.append(int(bytes(digits), 8))
            continue
        if value == ord("\r"):
            index += 1
            if index < len(data) and data[index] == ord("\n"):
                index += 1
            continue
        if value == ord("\n"):
            index += 1
            continue
        output.append(value)
        index += 1
    return output.decode("latin-1")


def expected_pdf_pages(pdf: Path, page_count: int, blank_pages: set[int]) -> list[list[str]]:
    try:
        data = pdf.read_bytes()
    except OSError as exc:
        raise EvaluationError("source_pdf_unavailable") from exc
    nonblank_pages: list[list[str]] = []
    for stream_match in STREAM.finditer(data):
        commands: list[tuple[float, float, int, str]] = []
        body = stream_match.group("body")
        for index, match in enumerate(TEXT_COMMAND.finditer(body)):
            commands.append((
                float(match.group("x")),
                float(match.group("y")),
                index,
                pdf_unescape(match.group("text")),
            ))
        if commands:
            commands.sort(key=lambda item: (-item[1], item[0], item[2]))
            nonblank_pages.append([token for item in commands for token in item[3].split()])
    expected_nonblank = page_count - len(blank_pages)
    if len(nonblank_pages) != expected_nonblank:
        raise EvaluationError("source_pdf_oracle_page_mismatch")
    pages: list[list[str]] = []
    nonblank_index = 0
    for page_number in range(1, page_count + 1):
        if page_number in blank_pages:
            pages.append([])
        else:
            pages.append(nonblank_pages[nonblank_index])
            nonblank_index += 1
    return pages


def parse_layout_pages(data: bytes, expected_pages: int) -> list[list[str]]:
    try:
        parts = data.decode("utf-8", "strict").split("\f")
    except UnicodeError as exc:
        raise EvaluationError("invalid_layout_output") from exc
    if len(parts) == expected_pages + 1 and not parts[-1].strip():
        parts.pop()
    return [part.split() for part in parts]


def parse_bbox_pages(data: bytes) -> list[list[Word]]:
    try:
        root = ET.fromstring(data)
    except ET.ParseError as exc:
        raise EvaluationError("invalid_bbox_output") from exc
    pages: list[list[Word]] = []
    for page in (item for item in root.iter() if item.tag.rsplit("}", 1)[-1] == "page"):
        def parse_word(item: ET.Element) -> Word | None:
            text = "".join(item.itertext()).strip()
            if not text:
                return None
            try:
                word = Word(
                    text=text,
                    x_min=float(item.attrib["xMin"]),
                    y_min=float(item.attrib["yMin"]),
                    x_max=float(item.attrib["xMax"]),
                    y_max=float(item.attrib["yMax"]),
                )
            except (KeyError, ValueError) as exc:
                raise EvaluationError("invalid_bbox_geometry") from exc
            if not all(math.isfinite(value) for value in (word.x_min, word.y_min, word.x_max, word.y_max)):
                raise EvaluationError("invalid_bbox_geometry")
            return word

        lines: list[tuple[float, float, list[Word]]] = []
        for line in (item for item in page.iter() if item.tag.rsplit("}", 1)[-1] == "line"):
            line_words = [
                word
                for word in (parse_word(item) for item in line.iter() if item.tag.rsplit("}", 1)[-1] == "word")
                if word is not None
            ]
            if not line_words:
                continue
            line_words.sort(key=lambda word: (word.x_min, word.x_max))
            try:
                y_position = float(line.attrib.get("yMin", min(word.y_min for word in line_words)))
                x_position = float(line.attrib.get("xMin", min(word.x_min for word in line_words)))
            except ValueError as exc:
                raise EvaluationError("invalid_bbox_geometry") from exc
            lines.append((y_position, x_position, line_words))
        if lines:
            # XHTML serialization order is not a reading-order contract.
            # Canonicalize physical lines top-to-bottom and same-row cells
            # left-to-right before comparing against source truth.
            lines.sort(key=lambda item: (round(item[0], 2), item[1]))
            pages.append([word for _, _, line_words in lines for word in line_words])
        else:
            words = [
                word
                for word in (parse_word(item) for item in page.iter() if item.tag.rsplit("}", 1)[-1] == "word")
                if word is not None
            ]
            words.sort(key=lambda word: (round(word.y_min, 2), word.x_min))
            pages.append(words)
    return pages


def mismatch_details(
    *,
    filename: str,
    page: int,
    expected: list[str],
    actual: list[str],
) -> dict[str, Any]:
    limit = min(len(expected), len(actual))
    mismatch_index = next((index for index in range(limit) if expected[index] != actual[index]), limit)
    start = max(0, mismatch_index - 4)
    end = mismatch_index + 5
    return {
        "actual_count": len(actual),
        "actual_preview": actual[start:end],
        "expected_count": len(expected),
        "expected_preview": expected[start:end],
        "filename": filename,
        "mismatch_index": mismatch_index,
        "page": page,
    }


def write_diagnostic(path_value: str, reason: str, details: dict[str, Any]) -> None:
    path = Path(path_value)
    if not path.is_absolute() or path.exists() or path.is_symlink() or not path.parent.is_dir() or path.parent.is_symlink():
        raise EvaluationError("unsafe_diagnostic_output")
    content = {
        "details": details,
        "reason": reason,
        "schema_version": 1,
        "status": "blocked",
    }
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(content, handle, indent=2, sort_keys=True)
            handle.write("\n")
    except BaseException:
        path.unlink(missing_ok=True)
        raise


def phrase_span(words: list[Word], phrase: str, start: int = 0) -> tuple[int, int]:
    tokens = phrase.split()
    values = [word.text for word in words]
    for index in range(start, len(values) - len(tokens) + 1):
        if values[index:index + len(tokens)] == tokens:
            return index, index + len(tokens)
    raise EvaluationError("required_structure_missing")


def phrase_geometry(words: list[Word], phrase: str) -> tuple[float, float, float, float]:
    start, end = phrase_span(words, phrase)
    return span_geometry(words[start:end])


def span_geometry(selected: list[Word]) -> tuple[float, float, float, float]:
    return (
        min(item.x_min for item in selected),
        sum(item.y_center for item in selected) / len(selected),
        max(item.x_max for item in selected),
        max(item.y_max for item in selected) - min(item.y_min for item in selected),
    )


def ensure_sequence(words: list[Word], phrases: Iterable[str]) -> int:
    cursor = 0
    count = 0
    for phrase in phrases:
        start, end = phrase_span(words, phrase, cursor)
        if start < cursor:
            raise EvaluationError("ordered_structure_mismatch")
        cursor = end
        count += 1
    return count


def validate_inputs(
    source_dir: Path,
    source_manifest: dict[str, Any],
    general_truth: dict[str, Any],
    detailed_truth: dict[str, Any],
) -> tuple[list[dict[str, Any]], dict[str, dict[str, Any]]]:
    if (
        source_manifest.get("schema_version") != 1
        or source_manifest.get("fixture_status") != "fully_synthetic_no_source_text"
        or general_truth.get("schema_version") != 1
        or general_truth.get("fixture_status") != "fully_synthetic_no_source_text"
        or detailed_truth.get("schema_version") != 1
    ):
        raise EvaluationError("invalid_acceptance_input")
    source_files = source_manifest.get("files")
    general_documents = general_truth.get("documents")
    detailed_documents = detailed_truth.get("documents")
    if not all(isinstance(value, list) and len(value) == 6 for value in (source_files, general_documents, detailed_documents)):
        raise EvaluationError("invalid_acceptance_input")
    general_by_name = {item.get("filename"): item for item in general_documents if isinstance(item, dict)}
    detailed_by_name = {item.get("filename"): item for item in detailed_documents if isinstance(item, dict)}
    if len(general_by_name) != 6 or set(general_by_name) != set(detailed_by_name):
        raise EvaluationError("acceptance_truth_mismatch")
    validated: list[dict[str, Any]] = []
    for item in source_files:
        if not isinstance(item, dict):
            raise EvaluationError("invalid_source_manifest")
        filename = item.get("filename")
        if filename not in general_by_name or item.get("doc_id") != general_by_name[filename].get("doc_id"):
            raise EvaluationError("acceptance_truth_mismatch")
        if (
            general_by_name[filename].get("pages") != detailed_by_name[filename].get("pages")
            or general_by_name[filename].get("blank_pages") != detailed_by_name[filename].get("blank_pages")
        ):
            raise EvaluationError("acceptance_truth_mismatch")
        source = source_dir / str(filename)
        if not source.is_file() or source.is_symlink():
            raise EvaluationError("source_pdf_unavailable")
        if source.stat().st_size != item.get("bytes") or sha256_file(source) != item.get("sha256"):
            raise EvaluationError("source_pdf_identity_mismatch")
        validated.append(item)
    return validated, detailed_by_name


def evaluate(arguments: argparse.Namespace) -> dict[str, int]:
    input_paths = [
        Path(arguments.source_dir),
        Path(arguments.source_manifest),
        Path(arguments.ground_truth),
        Path(arguments.acceptance_truth),
        Path(arguments.archive),
    ]
    for path in input_paths:
        if path.is_symlink():
            raise EvaluationError("unsafe_acceptance_input")
    source_dir, source_manifest_path, general_truth_path, detailed_truth_path, archive_path = (
        path.resolve(strict=True) for path in input_paths
    )
    source_manifest = load_json(source_manifest_path, "invalid_source_manifest")
    general_truth = load_json(general_truth_path, "invalid_ground_truth")
    detailed_truth = load_json(detailed_truth_path, "invalid_acceptance_truth")
    source_files, detailed_by_name = validate_inputs(source_dir, source_manifest, general_truth, detailed_truth)
    archive = load_archive(archive_path)
    expected_archive_files = {"observations.json"}
    for source_entry in source_files:
        stem = safe_stem(source_entry["filename"])
        for directory in (f"raw/{stem}", f"raw/{stem}.repeat"):
            for leaf in ("bbox.html", "bbox.stderr", "layout.txt", "layout.stderr", "pdfinfo.txt", "pdfinfo.stderr"):
                expected_archive_files.add(f"{directory}/{leaf}")
    if set(archive) != expected_archive_files:
        raise EvaluationError("capture_archive_file_set_mismatch")
    observations = parse_observations(archive["observations.json"])
    if (
        observations.get("schema_version") != 1
        or observations.get("fixture_status") != "fully_synthetic_no_source_text"
        or observations.get("source_manifest_sha256") != sha256_file(source_manifest_path)
        or observations.get("poppler_package_version")
        not in {"24.02.0-1ubuntu9.10", "24.02.0-1ubuntu9.11"}
        or observations.get("pdfinfo_version") != "24.02.0"
        or observations.get("pdftotext_version") != "24.02.0"
        or observations.get("summary") != {"blank_pages": 1, "documents": 6, "pages": 27, "repeatability": "pass"}
    ):
        raise EvaluationError("capture_observation_contract_mismatch")
    observed_documents = observations.get("documents")
    if not isinstance(observed_documents, list) or len(observed_documents) != 6:
        raise EvaluationError("capture_observation_contract_mismatch")
    observed_by_name = {item.get("filename"): item for item in observed_documents if isinstance(item, dict)}
    if len(observed_by_name) != 6:
        raise EvaluationError("capture_observation_contract_mismatch")

    bbox_by_name: dict[str, list[list[Word]]] = {}
    counters = {
        "bbox_token_pages": 0,
        "checkboxes": 0,
        "documents": 0,
        "field_pairs": 0,
        "headings": 0,
        "layout_token_pages": 0,
        "ordered_phrases": 0,
        "pages": 0,
        "repeated_pages": 0,
        "table_cells": 0,
        "table_rows": 0,
    }
    for source_entry in source_files:
        filename = source_entry["filename"]
        detail = detailed_by_name[filename]
        observed = observed_by_name.get(filename)
        if not isinstance(observed, dict):
            raise EvaluationError("missing_document_observation")
        if (
            observed.get("doc_id") != source_entry["doc_id"]
            or observed.get("source_sha256") != source_entry["sha256"]
            or observed.get("source_bytes") != source_entry["bytes"]
            or observed.get("pdfinfo", {}).get("pages") != detail["pages"]
        ):
            raise EvaluationError("document_observation_identity_mismatch")
        stem = safe_stem(filename)
        layout_name = f"raw/{stem}/layout.txt"
        bbox_name = f"raw/{stem}/bbox.html"
        repeat_layout_name = f"raw/{stem}.repeat/layout.txt"
        repeat_bbox_name = f"raw/{stem}.repeat/bbox.html"
        for name in (layout_name, bbox_name, repeat_layout_name, repeat_bbox_name):
            if name not in archive:
                raise EvaluationError("missing_capture_artifact")
        output_map = {
            "bbox": (bbox_name, repeat_bbox_name),
            "bbox_stderr": (f"raw/{stem}/bbox.stderr", f"raw/{stem}.repeat/bbox.stderr"),
            "layout": (layout_name, repeat_layout_name),
            "layout_stderr": (f"raw/{stem}/layout.stderr", f"raw/{stem}.repeat/layout.stderr"),
            "pdfinfo": (f"raw/{stem}/pdfinfo.txt", f"raw/{stem}.repeat/pdfinfo.txt"),
            "pdfinfo_stderr": (f"raw/{stem}/pdfinfo.stderr", f"raw/{stem}.repeat/pdfinfo.stderr"),
        }
        recorded_outputs = observed.get("outputs")
        if not isinstance(recorded_outputs, dict) or set(recorded_outputs) != set(output_map):
            raise EvaluationError("capture_output_identity_mismatch")
        for output_name, names in output_map.items():
            actual_hashes = [hashlib.sha256(archive[name]).hexdigest() for name in names]
            if len(set(actual_hashes)) != 1 or recorded_outputs[output_name] != actual_hashes[0]:
                raise EvaluationError("capture_output_identity_mismatch")
        if archive[layout_name] != archive[repeat_layout_name] or archive[bbox_name] != archive[repeat_bbox_name]:
            raise EvaluationError("nonrepeatable_capture_artifact")
        layout_pages = parse_layout_pages(archive[layout_name], int(detail["pages"]))
        bbox_pages = parse_bbox_pages(archive[bbox_name])
        expected_pages = expected_pdf_pages(
            source_dir / filename,
            int(detail["pages"]),
            set(detail["blank_pages"]),
        )
        if len(layout_pages) != len(expected_pages) or len(bbox_pages) != len(expected_pages):
            raise EvaluationError("extraction_page_count_mismatch")
        page_observations = observed.get("page_observations")
        if not isinstance(page_observations, list) or len(page_observations) != len(expected_pages):
            raise EvaluationError("capture_observation_contract_mismatch")
        for page_index, expected_tokens in enumerate(expected_pages):
            layout_tokens = layout_pages[page_index]
            bbox_tokens = [word.text for word in bbox_pages[page_index]]
            if layout_tokens != expected_tokens:
                raise EvaluationError(
                    "layout_token_or_order_mismatch",
                    mismatch_details(
                        filename=filename,
                        page=page_index + 1,
                        expected=expected_tokens,
                        actual=layout_tokens,
                    ),
                )
            if bbox_tokens != expected_tokens:
                raise EvaluationError(
                    "bbox_token_or_order_mismatch",
                    mismatch_details(
                        filename=filename,
                        page=page_index + 1,
                        expected=expected_tokens,
                        actual=bbox_tokens,
                    ),
                )
            expected_blank = page_index + 1 in set(detail["blank_pages"])
            observation = page_observations[page_index]
            if observation.get("page") != page_index + 1 or observation.get("blank") is not expected_blank:
                raise EvaluationError("blank_page_observation_mismatch")
            counters["layout_token_pages"] += 1
            counters["bbox_token_pages"] += 1
            counters["pages"] += 1
        bbox_by_name[filename] = bbox_pages
        counters["documents"] += 1
        for heading in detail["headings"]:
            phrase_span(bbox_pages[int(heading["page"]) - 1], heading["text"])
            counters["headings"] += 1

    for table_index, table in enumerate(detailed_truth.get("table_checks", [])):
        words = bbox_by_name[table["filename"]][int(table["page"]) - 1]
        prior_y = -math.inf
        cursor = 0
        for row_index, row in enumerate(table["rows"]):
            geometries = []
            for cell_index, cell in enumerate(row):
                try:
                    start, end = phrase_span(words, cell, cursor)
                except EvaluationError as exc:
                    raise EvaluationError(
                        "table_geometry_mismatch",
                        {"cell_index": cell_index, "row_index": row_index, "table_index": table_index},
                    ) from exc
                geometries.append(span_geometry(words[start:end]))
                cursor = end
            y_values = [item[1] for item in geometries]
            x_values = [item[0] for item in geometries]
            if max(y_values) - min(y_values) > 2.0 or x_values != sorted(x_values) or min(y_values) <= prior_y:
                raise EvaluationError(
                    "table_geometry_mismatch",
                    {"row_index": row_index, "table_index": table_index},
                )
            prior_y = min(y_values)
            counters["table_rows"] += 1
            counters["table_cells"] += len(row)

    form = detailed_truth.get("form_checks", {})
    form_pages = bbox_by_name.get(form.get("filename"), [])
    for pair in form.get("field_value_pairs", []):
        words = form_pages[int(pair["page"]) - 1]
        label = phrase_geometry(words, pair["label"])
        value = phrase_geometry(words, pair["value"])
        if abs(label[1] - value[1]) > 2.0 or value[0] <= label[2]:
            raise EvaluationError("form_field_geometry_mismatch")
        counters["field_pairs"] += 1
    for checkbox in form.get("checkboxes", []):
        words = form_pages[int(checkbox["page"]) - 1]
        marker_tokens = checkbox["marker"].split()
        label_tokens = checkbox["label"].split()
        start, end = phrase_span(words, f"{checkbox['marker']} {checkbox['label']}")
        selected = words[start:end]
        marker_words = selected[:len(marker_tokens)]
        label_words = selected[len(marker_tokens):len(marker_tokens) + len(label_tokens)]
        marker_y = sum(item.y_center for item in marker_words) / len(marker_words)
        label_y = sum(item.y_center for item in label_words) / len(label_words)
        if abs(marker_y - label_y) > 2.0 or min(item.x_min for item in label_words) <= max(item.x_max for item in marker_words):
            raise EvaluationError("checkbox_geometry_mismatch")
        counters["checkboxes"] += 1

    for item in detailed_truth.get("repeated_furniture", []):
        y_values: list[float] = []
        start, end = item["page_range"]
        for page_number in range(int(start), int(end) + 1):
            geometry = phrase_geometry(bbox_by_name[item["filename"]][page_number - 1], item["text"])
            y_values.append(geometry[1])
            counters["repeated_pages"] += 1
        if max(y_values) - min(y_values) > 1.0:
            raise EvaluationError("repeated_furniture_geometry_mismatch")

    for item in detailed_truth.get("ordered_structure_checks", []):
        if "page" in item:
            counters["ordered_phrases"] += ensure_sequence(
                bbox_by_name[item["filename"]][int(item["page"]) - 1], item["phrases"]
            )
        else:
            start, end = item["page_range"]
            for page_number in range(int(start), int(end) + 1):
                counters["ordered_phrases"] += ensure_sequence(
                    bbox_by_name[item["filename"]][page_number - 1], item["prefixes"]
                )
    return counters


def self_test() -> int:
    escaped = rb"A\(B\) C\\D\040E"
    if pdf_unescape(escaped) != "A(B) C\\D E":
        return 1
    pdf = b"stream\nBT /F1 10 Tf 1 0 0 1 200.0 500.0 Tm (second) Tj ET\nBT /F1 10 Tf 1 0 0 1 50.0 500.0 Tm (first) Tj ET\nendstream"
    descriptor, temporary_name = tempfile.mkstemp(prefix="pdf-extraction-evaluator-", suffix=".pdf")
    temporary = Path(temporary_name)
    try:
        os.write(descriptor, pdf)
        os.close(descriptor)
        descriptor = -1
        if expected_pdf_pages(temporary, 2, {1}) != [[], ["first", "second"]]:
            return 1
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        temporary.unlink(missing_ok=True)
    xml = b'''<doc><page><line xMin="1" yMin="20"><word xMin="1" yMin="20" xMax="2" yMax="21">two</word></line><line xMin="1" yMin="10"><word xMin="1" yMin="10" xMax="2" yMax="11">one</word></line></page></doc>'''
    words = parse_bbox_pages(xml)[0]
    if phrase_span(words, "one two") != (0, 2):
        return 1
    table_words = [
        Word("Review", 1, 1, 2, 2),
        Word("Condition", 1, 10, 2, 11),
        Word("Decision", 3, 10, 4, 11),
        Word("Exception", 1, 20, 2, 21),
        Word("Review", 3, 20, 4, 21),
    ]
    cursor = 0
    final_geometry: tuple[float, float, float, float] | None = None
    for phrase in ("Condition", "Decision", "Exception", "Review"):
        start, cursor = phrase_span(table_words, phrase, cursor)
        final_geometry = span_geometry(table_words[start:cursor])
    if final_geometry != (3, 20.5, 4, 1):
        return 1
    print("pdf_extraction_evaluator_self_test=pass")
    return 0


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--acceptance-truth")
    parser.add_argument("--archive")
    parser.add_argument("--ground-truth")
    parser.add_argument("--diagnostic-output")
    parser.add_argument("--source-dir")
    parser.add_argument("--source-manifest")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--validate-fixtures", action="store_true")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    if arguments.self_test:
        return self_test()
    if arguments.validate_fixtures:
        required = (
            arguments.acceptance_truth,
            arguments.ground_truth,
            arguments.source_dir,
            arguments.source_manifest,
        )
        if not all(required):
            raise EvaluationError("missing_required_argument")
        raw_paths = [
            Path(arguments.source_dir),
            Path(arguments.source_manifest),
            Path(arguments.ground_truth),
            Path(arguments.acceptance_truth),
        ]
        if any(path.is_symlink() for path in raw_paths):
            raise EvaluationError("unsafe_acceptance_input")
        source_dir, source_manifest_path, ground_truth_path, acceptance_truth_path = (
            path.resolve(strict=True) for path in raw_paths
        )
        source_manifest = load_json(source_manifest_path, "invalid_source_manifest")
        general_truth = load_json(ground_truth_path, "invalid_ground_truth")
        detailed_truth = load_json(acceptance_truth_path, "invalid_acceptance_truth")
        sources, details = validate_inputs(source_dir, source_manifest, general_truth, detailed_truth)
        page_count = sum(int(details[item["filename"]]["pages"]) for item in sources)
        for item in sources:
            detail = details[item["filename"]]
            expected_pdf_pages(
                source_dir / item["filename"],
                int(detail["pages"]),
                set(detail["blank_pages"]),
            )
        print(f"synthetic_pdf_fixture_validation=pass;documents={len(sources)};pages={page_count}")
        return 0
    required = (
        arguments.acceptance_truth,
        arguments.archive,
        arguments.ground_truth,
        arguments.source_dir,
        arguments.source_manifest,
    )
    if not all(required):
        raise EvaluationError("missing_required_argument")
    try:
        counters = evaluate(arguments)
    except EvaluationError as exc:
        if arguments.diagnostic_output:
            write_diagnostic(arguments.diagnostic_output, str(exc), exc.details)
        raise
    print("purpose=evaluate_synthetic_pdf_extraction")
    print(f"source_documents={counters['documents']};source_pages={counters['pages']};intentional_blank_pages=1")
    print(f"token_oracle_pages={counters['pages']};layout_token_mismatch_pages=0;bbox_token_mismatch_pages=0")
    print(f"heading_checks={counters['headings']};ordered_phrase_checks={counters['ordered_phrases']};repeated_furniture_page_checks={counters['repeated_pages']}")
    print(f"table_row_checks={counters['table_rows']};table_cell_checks={counters['table_cells']}")
    print(f"form_field_pair_checks={counters['field_pairs']};checkbox_checks={counters['checkboxes']}")
    print("pdf_extraction_evaluation=pass")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except EvaluationError as exc:
        print(f"pdf_extraction_evaluation=blocked;reason={exc}")
        raise SystemExit(1)
    except (OSError, ValueError) as exc:
        print(f"pdf_extraction_evaluation=blocked;reason=bounded_runtime_failure;error_type={type(exc).__name__}")
        raise SystemExit(1)
