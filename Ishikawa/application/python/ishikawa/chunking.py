"""Deterministic structure-aware retrieval chunk candidate construction.

This stage consumes only an accepted normalized structural-unit artifact.  It
does not estimate model tokens, call a model, connect to PostgreSQL, or mark a
candidate publishable.  The exact Nomic tokenizer gate follows this stage.
"""

from __future__ import annotations

import hashlib
import json
import copy
import re
from collections import defaultdict
from pathlib import Path
from typing import Any

from .canonical import canonical_json_bytes, domain_digest
from .document_control import (
    DocumentControlError,
    header_retrieval_lines,
    normalize_department_value,
    validate_document_control_header,
)


HEX_DIGEST = re.compile(r"^[0-9a-f]{64}$")
NUMBER = re.compile(r"\b\d+(?:\.\d+)?(?:%|[A-Za-z]+)?\b")
DOCUMENT_REFERENCE = re.compile(r"\b(?:[0-9]{2}\s+[A-Z]{3}\s+[0-9]{4}|TST-[0-9]{4})\b")
SEMANTIC_KINDS = frozenset({
    "paragraph",
    "definition",
    "list_item",
    "table",
    "form_field",
    "checkbox_group",
})
METHOD_PROFILE: dict[str, Any] = {
    "schema_version": 1,
    "name": "ishikawa-structural-chunk-candidates-v6",
    "boundary_rule": "smallest_canonical_structural_unit_v1",
    "body_overlap_units": 0,
    "compatible_sibling_assembly": "not_used",
    "section_page_representative": (
        "retrieval_only_same_document_version_parent_structural_unit_and_physical_page"
    ),
    "document_local_duplicate_canonicalization": "first_atomic_content_digest_in_source_order",
    "selected_group_expansion": "ordered_authoritative_atomic_members",
    "heading_behavior": "explicit_context_not_body_overlap",
    "page_furniture_behavior": "excluded_from_retrieval_candidates",
    "document_control_header_behavior": (
        "one_searchable_page_one_metadata_candidate_structured_filters_and_compact_"
        "authoritative_document_identity_context_on_body_retrieval_units"
    ),
    "document_identity_context": (
        "recognized_document_context_and_policy_number_only_retrieval_only_not_citation_text"
    ),
    "blank_page_behavior": "one_derived_page_status_candidate_per_verified_blank_page",
    "table_behavior": "one_context_projection_and_one_atomic_projection_per_row",
    "form_behavior": "one_atomic_projection_per_field_or_checkbox_group",
    "oversize_behavior": "block_pending_authoritative_token_measurement",
}
METHOD_PROFILE_ID = domain_digest("ishikawa.chunk-method-profile.v1", METHOD_PROFILE)
SCOPE_CONTEXT_MAX_CHARACTERS = 768
SCOPE_AWARE_METHOD_PROFILE: dict[str, Any] = {
    **METHOD_PROFILE,
    "name": "ishikawa-structural-chunk-candidates-v7-scope-aware-experiment",
    "document_control_header_behavior": (
        "one_searchable_page_one_metadata_candidate_structured_filters_and_bounded_"
        "authoritative_document_scope_context_on_body_retrieval_units"
    ),
    "document_identity_context": (
        "recognized_title_identifier_department_applicability_and_bounded_purpose_"
        "scope_source_excerpt_retrieval_only_not_citation_text"
    ),
    "document_scope_context": {
        "maximum_characters": SCOPE_CONTEXT_MAX_CHARACTERS,
        "source": "trusted_normalized_document_control_and_purpose_scope_units",
        "storage": "chunk_projection_properties_and_postgresql_retrieval_text",
        "displayable": False,
        "citable": False,
    },
}
SCOPE_AWARE_METHOD_PROFILE_ID = domain_digest(
    "ishikawa.chunk-method-profile.v1", SCOPE_AWARE_METHOD_PROFILE
)
DOCUMENT_SCOPE_AFFINITY_PROFILE: dict[str, Any] = {
    "schema_version": 1,
    "name": "ishikawa-document-scope-affinity-v1-experiment",
    "cardinality": "exactly_one_per_recognized_document_version",
    "source": "trusted_normalized_document_control_and_purpose_scope_units",
    "retrieval_role": "document_affinity_only",
    "body_representation": "accepted_v6_unchanged",
    "displayable": False,
    "citable": False,
    "generation_eligible": False,
    "authoritative_evidence": False,
    "maximum_scope_characters": SCOPE_CONTEXT_MAX_CHARACTERS,
    "persistence_if_qualified": "postgresql_retrieval_text_and_jsonb_metadata",
}
DOCUMENT_SCOPE_AFFINITY_PROFILE_ID = domain_digest(
    "ishikawa.document-scope-affinity-profile.v1",
    DOCUMENT_SCOPE_AFFINITY_PROFILE,
)


class ChunkingError(RuntimeError):
    """A stable failure from the chunk-candidate boundary."""


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _require_digest(value: Any, reason: str) -> str:
    if not isinstance(value, str) or HEX_DIGEST.fullmatch(value) is None:
        raise ChunkingError(reason)
    return value


def _load_normalized(path: Path, expected_sha256: str) -> dict[str, Any]:
    if not path.is_file() or path.is_symlink():
        raise ChunkingError("unsafe_normalized_artifact")
    _require_digest(expected_sha256, "invalid_expected_normalized_identity")
    if _sha256_file(path) != expected_sha256:
        raise ChunkingError("normalized_artifact_identity_mismatch")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ChunkingError("invalid_normalized_artifact") from exc
    if not isinstance(value, dict) or value.get("schema_version") != 1:
        raise ChunkingError("invalid_normalized_artifact")
    _require_digest(value.get("normalization_set_digest"), "invalid_normalization_set_identity")
    documents = value.get("documents")
    if not isinstance(documents, list) or not documents:
        raise ChunkingError("invalid_normalized_document_inventory")
    return value


def _document_identity(document: dict[str, Any]) -> tuple[str, str]:
    doc_ref = document.get("doc_id")
    if not isinstance(doc_ref, str) or not doc_ref:
        raise ChunkingError("invalid_normalized_document_identity")
    source_sha256 = _require_digest(
        document.get("source_sha256"), "invalid_normalized_source_identity"
    )
    document_id = domain_digest("ishikawa.synthetic-document.v1", {"document_ref": doc_ref})
    version_id = domain_digest(
        "ishikawa.document-version.v1",
        {"document_id": document_id, "source_sha256": source_sha256},
    )
    return document_id, version_id


def _document_identity_lines(validated: dict[str, Any] | None) -> list[str]:
    """Return bounded authoritative identity context for body retrieval units."""

    if validated is None:
        return []
    document_context = validated["document_context"]
    policy_number = validated["fields"]["policy_number"]["value"]
    lines: list[str] = []
    if document_context is not None:
        lines.append(f"Document: {document_context['value']}")
    if policy_number is not None:
        lines.append(f"Document identifier: {policy_number}")
    if not lines:
        raise ChunkingError("document_identity_context_missing")
    return lines


def _bounded_source_excerpt(texts: list[str]) -> str:
    value = " ".join(" ".join(item.split()) for item in texts if item.strip())
    if not value:
        raise ChunkingError("document_scope_context_missing")
    if len(value) <= SCOPE_CONTEXT_MAX_CHARACTERS:
        return value
    boundary = value.rfind(" ", 0, SCOPE_CONTEXT_MAX_CHARACTERS + 1)
    if boundary < SCOPE_CONTEXT_MAX_CHARACTERS // 2:
        boundary = SCOPE_CONTEXT_MAX_CHARACTERS
    return value[:boundary].rstrip()


def _document_scope_context(
    validated: dict[str, Any] | None,
    units: list[dict[str, Any]],
) -> dict[str, Any] | None:
    """Build bounded, source-backed retrieval context with explicit provenance."""

    if validated is None:
        return None
    scope_paths = [
        tuple(unit["structural_path"])
        for unit in units
        if unit["kind"] == "heading"
        and unit["structural_path"]
        and re.search(
            r"\b(?:purpose|scope)\b",
            unit["structural_path"][-1],
            flags=re.IGNORECASE,
        )
    ]
    if not scope_paths:
        raise ChunkingError("document_scope_heading_missing")
    selected_path = scope_paths[0]
    source_units = [
        unit
        for unit in units
        if unit["kind"] in SEMANTIC_KINDS
        and tuple(unit["structural_path"]) == selected_path
    ]
    if not source_units:
        raise ChunkingError("document_scope_units_missing")
    fields = validated["fields"]
    context = {
        "document_context": (
            validated["document_context"]["value"]
            if validated["document_context"] is not None else None
        ),
        "policy_number": fields["policy_number"]["value"],
        "department": fields["department"]["value"],
        "applicability_class": fields["applicability_class"]["value"],
        "purpose_scope_excerpt": _bounded_source_excerpt(
            [unit["text"] for unit in source_units]
        ),
        "purpose_scope_structural_path": list(selected_path),
        "purpose_scope_source_unit_ids": [unit["unit_id"] for unit in source_units],
        "maximum_characters": SCOPE_CONTEXT_MAX_CHARACTERS,
        "source": "trusted_normalized_document_control_and_purpose_scope_units",
        "included_in_retrieval_text": True,
        "displayable": False,
        "citable": False,
    }
    required = (
        "document_context", "policy_number", "department",
        "applicability_class", "purpose_scope_excerpt",
    )
    if any(not isinstance(context[field], str) or not context[field] for field in required):
        raise ChunkingError("document_scope_context_incomplete")
    return context


def _document_scope_lines(context: dict[str, Any] | None) -> list[str]:
    if context is None:
        return []
    return [
        f"Document: {context['document_context']}",
        f"Document identifier: {context['policy_number']}",
        f"Department: {context['department']}",
        f"Applicability/class: {context['applicability_class']}",
        f"Document scope: {context['purpose_scope_excerpt']}",
    ]


def _context_text(
    path: list[str],
    extra: list[str] | None = None,
    document_identity: list[str] | None = None,
) -> str:
    lines: list[str] = []
    lines.extend(item for item in (document_identity or []) if item)
    if path:
        lines.append(f"Section: {' > '.join(path)}")
    lines.extend(item for item in (extra or []) if item)
    return "\n".join(lines)


def _lexical_fields(
    content: str,
    references: list[str],
    *,
    labels: list[str] | None = None,
    boolean_states: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    return {
        "references": sorted(
            set(references) | {match.group(0) for match in DOCUMENT_REFERENCE.finditer(content)}
        ),
        "labels": list(labels or []),
        "numeric_values": NUMBER.findall(content),
        "boolean_states": list(boolean_states or []),
    }


def _citation(
    unit: dict[str, Any],
    *,
    anchor_kind: str,
    table_row_index: int | None = None,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "anchor_kind": anchor_kind,
        "page_start": unit["page_start"],
        "page_end": unit["page_end"],
        "structural_path": list(unit["structural_path"]),
        "source_spans": list(unit["source_spans"]),
        "source_unit_id": unit["unit_id"],
    }
    if table_row_index is not None:
        result["table_id"] = unit["unit_id"]
        result["row_index"] = table_row_index
    return result


def _candidate_base(
    *,
    document_id: str,
    document_version_id: str,
    unit: dict[str, Any],
    projection_kind: str,
    content_text: str,
    context_text: str,
    source_unit_ids: list[str],
    parent_unit_id: str | None,
    citation_anchor: dict[str, Any],
    lexical_fields: dict[str, Any],
    method_profile_id: str,
    projection_properties: dict[str, Any] | None = None,
) -> dict[str, Any]:
    retrieval_text = f"{context_text}\n\n{content_text}" if context_text else content_text
    context_digest = domain_digest(
        "ishikawa.chunk-context.v1",
        {"context_text": context_text, "structural_path": unit["structural_path"]},
    )
    retrieval_text_digest = domain_digest(
        "ishikawa.retrieval-text.v1", {"retrieval_text": retrieval_text}
    )
    identity_input = {
        "document_version_id": document_version_id,
        "method_profile_id": method_profile_id,
        "projection_kind": projection_kind,
        "source_unit_ids": source_unit_ids,
        "context_digest": context_digest,
        "retrieval_text_digest": retrieval_text_digest,
    }
    chunk_id = domain_digest("ishikawa.chunk.v1", identity_input)
    return {
        "schema_version": 1,
        "chunk_id": chunk_id,
        "document_id": document_id,
        "document_version_id": document_version_id,
        "method_profile_id": method_profile_id,
        "projection_kind": projection_kind,
        "source_unit_ids": source_unit_ids,
        "parent_unit_id": parent_unit_id,
        "content_text": content_text,
        "context_text": context_text,
        "retrieval_text": retrieval_text,
        "content_digest": domain_digest(
            "ishikawa.chunk-content.v1", {"content_text": content_text}
        ),
        "context_digest": context_digest,
        "retrieval_text_digest": retrieval_text_digest,
        "citation_anchor": citation_anchor,
        "lexical_fields": lexical_fields,
        "projection_properties": projection_properties or {},
        "sequence": {
            "previous_chunk_id": None,
            "next_chunk_id": None,
            "continuation_index": 0,
            "previous_continuation_id": None,
            "next_continuation_id": None,
        },
        "token_accounting": {
            "status": "pending_authoritative_nomic_measurement",
            "tokenizer_identity": None,
            "content_tokens": None,
            "context_tokens": None,
            "prefix_tokens": None,
            "total_embedding_input_tokens": None,
        },
        "publication_eligibility": {
            "eligible": False,
            "blockers": ["nomic_token_measurement_pending"],
        },
    }


def _ordinary_candidate(
    document_id: str,
    document_version_id: str,
    unit: dict[str, Any],
    parent_unit_id: str | None,
    document_identity: list[str],
    method_profile_id: str,
) -> dict[str, Any]:
    properties = unit.get("properties")
    if not isinstance(properties, dict):
        raise ChunkingError("invalid_structural_unit_properties")
    labels: list[str] = []
    states: list[dict[str, Any]] = []
    if unit["kind"] == "form_field":
        labels = [properties["label"]]
    elif unit["kind"] == "checkbox_group":
        labels = [properties["label"]]
        states = [
            {"label": option["label"], "selected": option["selected"]}
            for option in properties["options"]
        ]
    return _candidate_base(
        document_id=document_id,
        document_version_id=document_version_id,
        unit=unit,
        projection_kind=unit["kind"],
        content_text=unit["text"],
        context_text=_context_text(
            unit["structural_path"], document_identity=document_identity
        ),
        source_unit_ids=[unit["unit_id"]],
        parent_unit_id=parent_unit_id,
        citation_anchor=_citation(unit, anchor_kind=unit["kind"]),
        lexical_fields=_lexical_fields(
            unit["text"], unit["references"], labels=labels, boolean_states=states
        ),
        method_profile_id=method_profile_id,
        projection_properties={
            "body_overlap_units": 0,
            "source_kind": unit["kind"],
            "source_ordinal": unit["ordinal"],
        },
    )


def _blank_page_candidate(
    document_id: str,
    document_version_id: str,
    page: dict[str, Any],
    document_identity: list[str],
    method_profile_id: str,
) -> dict[str, Any]:
    """Create citable evidence for a verified blank page without inventing content."""

    page_number = page.get("page")
    width = page.get("width")
    height = page.get("height")
    if (
        type(page_number) is not int
        or page_number < 1
        or not isinstance(width, (int, float))
        or isinstance(width, bool)
        or not isinstance(height, (int, float))
        or isinstance(height, bool)
        or width <= 0
        or height <= 0
        or page.get("blank") is not True
    ):
        raise ChunkingError("invalid_blank_page_inventory")
    source_unit_id = domain_digest(
        "ishikawa.derived-page-status-unit.v1",
        {
            "document_version_id": document_version_id,
            "page": page_number,
            "blank": True,
            "width": float(width),
            "height": float(height),
        },
    )
    source_span = {
        "line_id": f"p{page_number:04d}-blank",
        "page": page_number,
        "word_start": 0,
        "word_end": 0,
        "bbox": [0.0, 0.0, float(width), float(height)],
    }
    unit = {
        "unit_id": source_unit_id,
        "page_start": page_number,
        "page_end": page_number,
        "structural_path": [],
        "source_spans": [source_span],
    }
    content = f"Page {page_number} contains no extractable text."
    return _candidate_base(
        document_id=document_id,
        document_version_id=document_version_id,
        unit=unit,
        projection_kind="page_status",
        content_text=content,
        context_text=_context_text(
            [], ["Verified page status: blank"], document_identity
        ),
        source_unit_ids=[source_unit_id],
        parent_unit_id=None,
        citation_anchor=_citation(unit, anchor_kind="page_status"),
        lexical_fields=_lexical_fields(content, []),
        method_profile_id=method_profile_id,
        projection_properties={
            "body_overlap_units": 0,
            "source_kind": "verified_page_inventory",
            "blank": True,
            "derived_evidence": True,
        },
    )


def _table_candidates(
    document_id: str,
    document_version_id: str,
    unit: dict[str, Any],
    parent_unit_id: str | None,
    document_identity: list[str],
    method_profile_id: str,
) -> list[dict[str, Any]]:
    properties = unit.get("properties")
    if not isinstance(properties, dict) or properties.get("authority") != "structured_table":
        raise ChunkingError("invalid_structured_table")
    headers = properties.get("headers")
    rows = properties.get("rows")
    if not isinstance(headers, list) or not headers or not isinstance(rows, list) or not rows:
        raise ChunkingError("invalid_structured_table")
    if any(not isinstance(item, str) or not item for item in headers):
        raise ChunkingError("invalid_structured_table")
    table_context = properties.get("context")
    if not isinstance(table_context, str):
        raise ChunkingError("invalid_structured_table")
    extra_context = [f"Table context: {table_context}" if table_context else ""]
    context_content = f"Columns: {' | '.join(headers)}"
    candidates = [
        _candidate_base(
            document_id=document_id,
            document_version_id=document_version_id,
            unit=unit,
            projection_kind="table_context",
            content_text=context_content,
            context_text=_context_text(
                unit["structural_path"], extra_context, document_identity
            ),
            source_unit_ids=[unit["unit_id"]],
            parent_unit_id=parent_unit_id,
            citation_anchor=_citation(unit, anchor_kind="table"),
            lexical_fields=_lexical_fields(
                f"{context_content}\n{table_context}", [], labels=headers
            ),
            method_profile_id=method_profile_id,
            projection_properties={
                "body_overlap_units": 0,
                "table_id": unit["unit_id"],
                "ordered_headers": headers,
                "row_expansion": 0,
            },
        )
    ]
    for expected_index, row in enumerate(rows):
        if not isinstance(row, dict) or row.get("row_index") != expected_index:
            raise ChunkingError("invalid_structured_table_row")
        cells = row.get("cells")
        if not isinstance(cells, list) or len(cells) != len(headers):
            raise ChunkingError("invalid_structured_table_row")
        pairs: list[str] = []
        row_spans: list[dict[str, Any]] = []
        for column_index, (header, cell) in enumerate(zip(headers, cells)):
            if (
                not isinstance(cell, dict)
                or cell.get("column_index") != column_index
                or cell.get("header") != header
                or not isinstance(cell.get("value"), str)
                or not isinstance(cell.get("source_span"), dict)
            ):
                raise ChunkingError("invalid_structured_table_row")
            pairs.append(f"{header}: {cell['value']}")
            row_spans.append(cell["source_span"])
        content = "\n".join(pairs)
        row_unit = dict(unit)
        row_unit["source_spans"] = row_spans
        row_unit["references"] = []
        candidates.append(_candidate_base(
            document_id=document_id,
            document_version_id=document_version_id,
            unit=row_unit,
            projection_kind="table_row",
            content_text=content,
            context_text=_context_text(
                unit["structural_path"],
                [
                    f"Table context: {table_context}" if table_context else "",
                    f"Columns: {' | '.join(headers)}",
                ],
                document_identity,
            ),
            source_unit_ids=[unit["unit_id"]],
            parent_unit_id=unit["unit_id"],
            citation_anchor=_citation(row_unit, anchor_kind="table_row", table_row_index=expected_index),
            lexical_fields=_lexical_fields(
                f"{content}\n{table_context}", [], labels=headers
            ),
            method_profile_id=method_profile_id,
            projection_properties={
                "body_overlap_units": 0,
                "table_id": unit["unit_id"],
                "row_index": expected_index,
                "ordered_headers": headers,
                "row_expansion": 0,
                "continuation": bool(row.get("continuation", False)),
            },
        ))
    return candidates


def _validate_unit(unit: Any, expected_ordinal: int) -> dict[str, Any]:
    if not isinstance(unit, dict) or unit.get("ordinal") != expected_ordinal:
        raise ChunkingError("invalid_structural_unit_order")
    if unit.get("kind") not in SEMANTIC_KINDS | {"heading", "page_furniture"}:
        raise ChunkingError("unsupported_structural_unit_kind")
    for field in ("unit_id", "input_digest", "output_digest"):
        _require_digest(unit.get(field), "invalid_structural_unit_identity")
    if not isinstance(unit.get("text"), str) or not unit["text"]:
        raise ChunkingError("invalid_structural_unit_text")
    if not isinstance(unit.get("structural_path"), list):
        raise ChunkingError("invalid_structural_path")
    if not isinstance(unit.get("source_spans"), list) or not unit["source_spans"]:
        raise ChunkingError("invalid_structural_unit_anchor")
    if not isinstance(unit.get("references"), list):
        raise ChunkingError("invalid_structural_unit_references")
    return unit


def _link_sequence(candidates: list[dict[str, Any]]) -> None:
    for index, candidate in enumerate(candidates):
        candidate["sequence"]["previous_chunk_id"] = (
            candidates[index - 1]["chunk_id"] if index > 0 else None
        )
        candidate["sequence"]["next_chunk_id"] = (
            candidates[index + 1]["chunk_id"] if index + 1 < len(candidates) else None
        )


def _ordered_unique(values: list[Any]) -> list[Any]:
    result: list[Any] = []
    for value in values:
        if value not in result:
            result.append(value)
    return result


def _merge_lexical_fields(group: list[dict[str, Any]]) -> dict[str, Any]:
    fields = [candidate["lexical_fields"] for candidate in group]
    controls = [field.get("document_control") for field in fields]
    aliases = [field.get("department_aliases") for field in fields]
    if not all(value == controls[0] for value in controls) or not all(
        value == aliases[0] for value in aliases
    ):
        raise ChunkingError("section_page_representative_metadata_conflict")
    return {
        "references": sorted(
            {value for field in fields for value in field.get("references", [])}
        ),
        "labels": _ordered_unique(
            [value for field in fields for value in field.get("labels", [])]
        ),
        "numeric_values": _ordered_unique(
            [value for field in fields for value in field.get("numeric_values", [])]
        ),
        "boolean_states": _ordered_unique(
            [value for field in fields for value in field.get("boolean_states", [])]
        ),
        "document_control": copy.deepcopy(controls[0]),
        "department_aliases": copy.deepcopy(aliases[0]),
    }


def _retrieval_group_id(candidate: dict[str, Any]) -> str:
    anchor = candidate["citation_anchor"]
    parent = candidate.get("parent_unit_id")
    if (
        candidate["projection_kind"] == "document_control_metadata"
        or not isinstance(parent, str)
        or anchor["page_start"] != anchor["page_end"]
    ):
        return candidate["chunk_id"]
    return domain_digest(
        "ishikawa.retrieval-group.v1",
        {
            "document_version_id": candidate["document_version_id"],
            "parent_unit_id": parent,
            "page": anchor["page_start"],
            "structural_path": anchor["structural_path"],
        },
    )


def _section_page_representative(group: list[dict[str, Any]]) -> dict[str, Any]:
    first = group[0]
    anchors = [candidate["citation_anchor"] for candidate in group]
    document_identity_contexts = [
        candidate["projection_properties"].get(
            "retrieval_document_identity_context"
        )
        for candidate in group
    ]
    document_control_headers = [
        candidate["projection_properties"].get("document_control_header")
        for candidate in group
    ]
    document_scope_contexts = [
        candidate["projection_properties"].get("retrieval_document_scope_context")
        for candidate in group
    ]
    if not (
        all(candidate["document_id"] == first["document_id"] for candidate in group)
        and all(
            candidate["document_version_id"] == first["document_version_id"]
            for candidate in group
        )
        and all(candidate["parent_unit_id"] == first["parent_unit_id"] for candidate in group)
        and all(candidate["retrieval_filters"] == first["retrieval_filters"] for candidate in group)
        and all(anchor["page_start"] == anchor["page_end"] for anchor in anchors)
        and len({anchor["page_start"] for anchor in anchors}) == 1
        and len({tuple(anchor["structural_path"]) for anchor in anchors}) == 1
        and all(
            value == document_identity_contexts[0]
            for value in document_identity_contexts
        )
        and all(value == document_control_headers[0] for value in document_control_headers)
        and all(value == document_scope_contexts[0] for value in document_scope_contexts)
        and all(candidate["method_profile_id"] == first["method_profile_id"] for candidate in group)
    ):
        raise ChunkingError("section_page_representative_boundary_mismatch")
    content = "\n\n".join(candidate["content_text"] for candidate in group)
    context = min(
        (candidate["context_text"] for candidate in group),
        key=lambda value: (len(value), value),
    )
    source_unit_ids = _ordered_unique(
        [unit for candidate in group for unit in candidate["source_unit_ids"]]
    )
    synthetic_unit = {
        "unit_id": source_unit_ids[0],
        "page_start": anchors[0]["page_start"],
        "page_end": anchors[0]["page_end"],
        "structural_path": copy.deepcopy(anchors[0]["structural_path"]),
        "source_spans": [
            copy.deepcopy(span)
            for anchor in anchors
            for span in anchor.get("source_spans", [])
        ],
    }
    representative_properties = {
        "body_overlap_units": 0,
        "source_kind": "section_page_representative",
        "component_chunk_ids": [candidate["chunk_id"] for candidate in group],
        "component_projection_kinds": [
            candidate["projection_kind"] for candidate in group
        ],
        "component_count": len(group),
        "assembly_rule": (
            "same_document_version_parent_structural_unit_and_physical_page_all_members"
        ),
        "retrieval_scoring_only": True,
        "atomic_evidence_authoritative": True,
    }
    if document_control_headers[0] is not None:
        representative_properties["document_control_header"] = copy.deepcopy(
            document_control_headers[0]
        )
    if document_identity_contexts[0] is not None:
        representative_properties["retrieval_document_identity_context"] = copy.deepcopy(
            document_identity_contexts[0]
        )
    if document_scope_contexts[0] is not None:
        representative_properties["retrieval_document_scope_context"] = copy.deepcopy(
            document_scope_contexts[0]
        )
    representative = _candidate_base(
        document_id=first["document_id"],
        document_version_id=first["document_version_id"],
        unit=synthetic_unit,
        projection_kind="section_page_representative",
        content_text=content,
        context_text=context,
        source_unit_ids=source_unit_ids,
        parent_unit_id=first["parent_unit_id"],
        citation_anchor={
            **_citation(synthetic_unit, anchor_kind="section_page_representative"),
            "component_source_unit_ids": source_unit_ids,
        },
        lexical_fields=_merge_lexical_fields(group),
        method_profile_id=first["method_profile_id"],
        projection_properties=representative_properties,
    )
    representative["retrieval_filters"] = copy.deepcopy(first["retrieval_filters"])
    return representative


def _add_retrieval_representations(
    atomic_candidates: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    groups: dict[tuple[Any, ...], list[dict[str, Any]]] = defaultdict(list)
    seen_content: set[str] = set()
    for candidate in atomic_candidates:
        properties = dict(candidate["projection_properties"])
        properties["retrieval_scoring_only"] = False
        properties["retrieval_group_id"] = _retrieval_group_id(candidate)
        if candidate["projection_kind"] == "document_control_metadata":
            properties["document_local_content_canonical"] = True
        else:
            digest = candidate["content_digest"]
            properties["document_local_content_canonical"] = digest not in seen_content
            seen_content.add(digest)
        candidate["projection_properties"] = properties
        anchor = candidate["citation_anchor"]
        if (
            candidate["projection_kind"] != "document_control_metadata"
            and isinstance(candidate.get("parent_unit_id"), str)
            and anchor["page_start"] == anchor["page_end"]
        ):
            groups[(
                candidate["parent_unit_id"],
                anchor["page_start"],
                tuple(anchor["structural_path"]),
            )].append(candidate)
    representatives = [_section_page_representative(group) for group in groups.values()]
    for representative in representatives:
        properties = dict(representative["projection_properties"])
        properties["retrieval_group_id"] = _retrieval_group_id(representative)
        properties["document_local_content_canonical"] = True
        representative["projection_properties"] = properties
    return atomic_candidates + representatives


def _document_control_filter(validated: dict[str, Any]) -> dict[str, Any]:
    department = validated["fields"]["department"]["value"]
    if not isinstance(department, str) or not department:
        raise ChunkingError("document_control_department_missing")
    try:
        department_normalized = normalize_department_value(department)
    except DocumentControlError as error:
        raise ChunkingError(str(error)) from error
    return {
        "applicability_class": validated["fields"]["applicability_class"]["value"],
        "department": department,
        "department_aliases": list(validated["department_aliases"]),
        "department_normalized": department_normalized,
        "document_context": (
            validated["document_context"]["value"]
            if validated["document_context"] is not None else None
        ),
        "organization_name": (
            validated["organization_name"]["value"]
            if validated["organization_name"] is not None else None
        ),
        "policy_number": validated["fields"]["policy_number"]["value"],
    }


def _attach_document_control_filters(
    candidate: dict[str, Any],
    validated: dict[str, Any] | None,
    document_scope_context: dict[str, Any] | None = None,
) -> dict[str, Any]:
    if validated is None:
        candidate["retrieval_filters"] = {}
        return candidate
    lexical = dict(candidate["lexical_fields"])
    lexical["document_control"] = {
        field: record["value"]
        for field, record in validated["fields"].items()
        if record["value"] is not None
    }
    lexical["department_aliases"] = list(validated["department_aliases"])
    candidate["lexical_fields"] = lexical
    properties = dict(candidate["projection_properties"])
    properties["document_control_header"] = {
        "page_numbers": list(validated["page_numbers"]),
        "repeated": validated["repeated"],
    }
    properties["retrieval_document_identity_context"] = {
        "document_context": (
            validated["document_context"]["value"]
            if validated["document_context"] is not None else None
        ),
        "policy_number": validated["fields"]["policy_number"]["value"],
        "source": "recognized_document_control_header",
        "included_in_retrieval_text": (
            candidate["projection_kind"] != "document_control_metadata"
        ),
    }
    if document_scope_context is not None:
        scope_context = copy.deepcopy(document_scope_context)
        scope_context["included_in_retrieval_text"] = (
            candidate["projection_kind"] != "document_control_metadata"
        )
        properties["retrieval_document_scope_context"] = scope_context
    candidate["projection_properties"] = properties
    candidate["retrieval_filters"] = {
        "document_control": _document_control_filter(validated)
    }
    return candidate


def _document_control_candidate(
    document_id: str,
    document_version_id: str,
    units: list[dict[str, Any]],
    validated: dict[str, Any],
    method_profile_id: str,
    document_scope_context: dict[str, Any] | None = None,
) -> dict[str, Any]:
    header_line_ids = set(validated["line_ids"])
    source_units = [
        unit for unit in units
        if unit.get("kind") == "page_furniture"
        and any(
            span.get("line_id") in header_line_ids
            for span in unit.get("source_spans", [])
            if isinstance(span, dict)
        )
    ]
    source_units.sort(key=lambda item: item["ordinal"])
    source_spans = [
        span
        for unit in source_units
        for span in unit["source_spans"]
        if span["line_id"] in header_line_ids
    ]
    if (
        not source_units
        or {span["line_id"] for span in source_spans} != header_line_ids
        or any(span["page"] != 1 for span in source_spans)
    ):
        raise ChunkingError("document_control_header_anchor_missing")
    source_unit_ids = [unit["unit_id"] for unit in source_units]
    synthetic_unit = {
        "unit_id": source_unit_ids[0],
        "page_start": 1,
        "page_end": 1,
        "structural_path": ["Document Control"],
        "source_spans": source_spans,
    }
    content = "\n".join(header_retrieval_lines(validated))
    candidate = _candidate_base(
        document_id=document_id,
        document_version_id=document_version_id,
        unit=synthetic_unit,
        projection_kind="document_control_metadata",
        content_text=content,
        context_text="Document control metadata",
        source_unit_ids=source_unit_ids,
        parent_unit_id=None,
        citation_anchor=_citation(
            synthetic_unit,
            anchor_kind="document_control_metadata",
        ),
        lexical_fields=_lexical_fields(content, []),
        method_profile_id=method_profile_id,
        projection_properties={
            "body_overlap_units": 0,
            "source_kind": "recognized_document_control_header",
            "header_page": 1,
            "retrieval_representative": True,
        },
    )
    return _attach_document_control_filters(
        candidate, validated, document_scope_context
    )


def _build_chunk_candidates(
    normalized: dict[str, Any],
    *,
    method_profile: dict[str, Any],
    method_profile_id: str,
    scope_aware: bool,
) -> dict[str, Any]:
    """Build one explicitly identified deterministic candidate representation."""

    if normalized.get("schema_version") != 1:
        raise ChunkingError("invalid_normalized_artifact")
    normalization_set_digest = _require_digest(
        normalized.get("normalization_set_digest"), "invalid_normalization_set_identity"
    )
    output_documents: list[dict[str, Any]] = []
    all_chunk_ids: set[str] = set()
    for document in normalized.get("documents", []):
        if not isinstance(document, dict):
            raise ChunkingError("invalid_normalized_document")
        document_id, document_version_id = _document_identity(document)
        raw_units = document.get("units")
        if not isinstance(raw_units, list):
            raise ChunkingError("invalid_structural_unit_inventory")
        units = [_validate_unit(unit, ordinal) for ordinal, unit in enumerate(raw_units)]
        pages = document.get("pages")
        blank_pages = document.get("blank_pages")
        if (
            not isinstance(pages, list)
            or not isinstance(blank_pages, list)
            or [item.get("page") for item in pages if isinstance(item, dict)]
            != list(range(1, len(pages) + 1))
            or [item["page"] for item in pages if item.get("blank") is True] != blank_pages
        ):
            raise ChunkingError("invalid_page_inventory")
        header = document.get("document_control_header")
        if header is not None and not isinstance(header, dict):
            raise ChunkingError("document_control_header_invalid")
        validated_header = None
        if header is not None:
            try:
                validated_header = validate_document_control_header(header)
            except DocumentControlError as error:
                raise ChunkingError(str(error)) from error
        scope_context = (
            _document_scope_context(validated_header, units) if scope_aware else None
        )
        document_identity = (
            _document_scope_lines(scope_context)
            if scope_aware else _document_identity_lines(validated_header)
        )
        heading_by_path: dict[tuple[str, ...], str] = {}
        candidates: list[dict[str, Any]] = [
            _blank_page_candidate(
                document_id,
                document_version_id,
                page,
                document_identity,
                method_profile_id,
            )
            for page in pages
            if page.get("blank") is True
        ]
        for unit in units:
            path = tuple(unit["structural_path"])
            if unit["kind"] == "heading":
                heading_by_path[path] = unit["unit_id"]
                continue
            if unit["kind"] == "page_furniture":
                continue
            parent_unit_id = heading_by_path.get(path)
            if unit["kind"] == "table":
                candidates.extend(_table_candidates(
                    document_id,
                    document_version_id,
                    unit,
                    parent_unit_id,
                    document_identity,
                    method_profile_id,
                ))
            else:
                candidates.append(_ordinary_candidate(
                    document_id,
                    document_version_id,
                    unit,
                    parent_unit_id,
                    document_identity,
                    method_profile_id,
                ))
        candidates = [
            _attach_document_control_filters(
                candidate, validated_header, scope_context
            )
            for candidate in candidates
        ]
        if validated_header is not None:
            candidates.insert(0, _document_control_candidate(
                document_id,
                document_version_id,
                units,
                validated_header,
                method_profile_id,
                scope_context,
            ))
        candidates = _add_retrieval_representations(candidates)
        _link_sequence(candidates)
        duplicate_ids = all_chunk_ids.intersection(item["chunk_id"] for item in candidates)
        if duplicate_ids:
            raise ChunkingError("duplicate_chunk_identity")
        all_chunk_ids.update(item["chunk_id"] for item in candidates)
        output_documents.append({
            "document_ref": document["doc_id"],
            "document_id": document_id,
            "document_version_id": document_version_id,
            "source_sha256": document["source_sha256"],
            "normalization_digest": document["normalization_digest"],
            "candidate_count": len(candidates),
            "candidates": candidates,
        })
    result: dict[str, Any] = {
        "schema_version": 1,
        "artifact_kind": "non_publishable_structural_chunk_candidates",
        "normalization_set_digest": normalization_set_digest,
        "method_profile": method_profile,
        "method_profile_id": method_profile_id,
        "token_measurement_status": "pending_authoritative_nomic_measurement",
        "publication_eligible": False,
        "documents": output_documents,
    }
    result["chunk_candidate_set_digest"] = domain_digest(
        "ishikawa.chunk-candidate-set.v1", result
    )
    return result


def build_chunk_candidates(normalized: dict[str, Any]) -> dict[str, Any]:
    """Build the accepted deterministic, non-publishable v6 representation."""

    return _build_chunk_candidates(
        normalized,
        method_profile=METHOD_PROFILE,
        method_profile_id=METHOD_PROFILE_ID,
        scope_aware=False,
    )


def build_scope_aware_chunk_candidates(normalized: dict[str, Any]) -> dict[str, Any]:
    """Build the isolated V13-42 scope-aware experimental representation."""

    return _build_chunk_candidates(
        normalized,
        method_profile=SCOPE_AWARE_METHOD_PROFILE,
        method_profile_id=SCOPE_AWARE_METHOD_PROFILE_ID,
        scope_aware=True,
    )


def build_document_scope_affinity_representations(
    normalized: dict[str, Any],
) -> dict[str, Any]:
    """Build one non-citable V13-43 document-affinity record per version."""

    if normalized.get("schema_version") != 1:
        raise ChunkingError("invalid_normalized_artifact")
    normalization_set_digest = _require_digest(
        normalized.get("normalization_set_digest"),
        "invalid_normalization_set_identity",
    )
    output_documents: list[dict[str, Any]] = []
    representation_ids: set[str] = set()
    for document in normalized.get("documents", []):
        if not isinstance(document, dict):
            raise ChunkingError("invalid_normalized_document")
        document_id, document_version_id = _document_identity(document)
        raw_units = document.get("units")
        if not isinstance(raw_units, list):
            raise ChunkingError("invalid_structural_unit_inventory")
        units = [_validate_unit(unit, ordinal) for ordinal, unit in enumerate(raw_units)]
        header = document.get("document_control_header")
        if not isinstance(header, dict):
            raise ChunkingError("document_control_header_missing")
        try:
            validated_header = validate_document_control_header(header)
        except DocumentControlError as error:
            raise ChunkingError(str(error)) from error
        scope_context = _document_scope_context(validated_header, units)
        if scope_context is None:
            raise ChunkingError("document_scope_context_missing")
        retrieval_text = "\n".join(_document_scope_lines(scope_context))
        retrieval_text_digest = domain_digest(
            "ishikawa.retrieval-text.v1", {"retrieval_text": retrieval_text}
        )
        identity_input = {
            "document_version_id": document_version_id,
            "profile_id": DOCUMENT_SCOPE_AFFINITY_PROFILE_ID,
            "retrieval_text_digest": retrieval_text_digest,
            "source_unit_ids": scope_context["purpose_scope_source_unit_ids"],
        }
        representation_id = domain_digest(
            "ishikawa.document-scope-affinity.v1", identity_input
        )
        if representation_id in representation_ids:
            raise ChunkingError("duplicate_document_scope_affinity_identity")
        representation_ids.add(representation_id)
        record = {
            "schema_version": 1,
            "representation_id": representation_id,
            "document_id": document_id,
            "document_version_id": document_version_id,
            "profile_id": DOCUMENT_SCOPE_AFFINITY_PROFILE_ID,
            "projection_kind": "document_scope_affinity",
            "retrieval_text": retrieval_text,
            "retrieval_text_digest": retrieval_text_digest,
            "retrieval_filters": {
                "document_control": _document_control_filter(validated_header)
            },
            "contextual_fields": {
                "retrieval_document_scope_context": {
                    **copy.deepcopy(scope_context),
                    "included_in_retrieval_text": True,
                },
                "document_control_line_ids": list(validated_header["line_ids"]),
                "displayable": False,
                "citable": False,
                "generation_eligible": False,
                "authoritative_evidence": False,
            },
        }
        output_documents.append({
            "document_ref": document["doc_id"],
            "document_id": document_id,
            "document_version_id": document_version_id,
            "source_sha256": document["source_sha256"],
            "representation": record,
        })
    if not output_documents:
        raise ChunkingError("document_scope_affinity_inventory_empty")
    result: dict[str, Any] = {
        "schema_version": 1,
        "artifact_kind": "non_publishable_document_scope_affinity_representations",
        "normalization_set_digest": normalization_set_digest,
        "profile": DOCUMENT_SCOPE_AFFINITY_PROFILE,
        "profile_id": DOCUMENT_SCOPE_AFFINITY_PROFILE_ID,
        "publication_eligible": False,
        "documents": output_documents,
    }
    result["representation_set_digest"] = domain_digest(
        "ishikawa.document-scope-affinity-set.v1", result
    )
    return result


def build_from_file(
    normalized_path: str | Path,
    *,
    expected_normalized_sha256: str,
) -> dict[str, Any]:
    normalized = _load_normalized(Path(normalized_path), expected_normalized_sha256)
    return build_chunk_candidates(normalized)


def chunk_candidates_json_bytes(value: dict[str, Any]) -> bytes:
    return canonical_json_bytes(value)
