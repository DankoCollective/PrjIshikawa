"""Read-only reconstructed-document contract and PostgreSQL adapter."""

from __future__ import annotations

import json
import re
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from typing import Any, NoReturn

from .canonical import canonical_json_bytes
from .relationships import extract_declared_identifiers
from .retrieval_service import (
    RetrievalDependencyUnavailable,
    RetrievalServiceContractError,
)


DOCUMENT_REQUEST_SCHEMA = "ishikawa.document-view-request.v1"
DOCUMENT_RESPONSE_SCHEMA = "ishikawa.document-view-response.v2"
EXPECTED_RETRIEVAL_ROLE = "rag_retrieval"
_HEX = re.compile(r"^[0-9a-f]{64}$")
_KINDS = frozenset(
    {
        "paragraph",
        "list_item",
        "procedure_step",
        "table",
        "table_context",
        "form",
        "form_field",
        "page_status",
    }
)


class DocumentViewContractError(ValueError):
    """Stable reconstructed-document request or response rejection."""


class DocumentViewNotAvailable(LookupError):
    """The requested exact active document version is unavailable."""


def _reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DocumentViewContractError("DOCUMENT_REQUEST_DUPLICATE_FIELD")
        result[key] = value
    return result


def _reject_constant(_value: str) -> NoReturn:
    raise DocumentViewContractError("DOCUMENT_REQUEST_NONFINITE_NUMBER")


@dataclass(frozen=True, slots=True)
class DocumentViewRequest:
    source_id: str
    section_offset: int
    section_limit: int


def decode_document_view_request(body: bytes) -> DocumentViewRequest:
    if not isinstance(body, bytes) or not body or len(body) > 4096:
        raise DocumentViewContractError("DOCUMENT_REQUEST_SIZE_INVALID")
    try:
        value = json.loads(
            body.decode("utf-8"),
            object_pairs_hook=_reject_duplicates,
            parse_constant=_reject_constant,
        )
    except DocumentViewContractError:
        raise
    except (UnicodeError, json.JSONDecodeError) as error:
        raise DocumentViewContractError("DOCUMENT_REQUEST_JSON_INVALID") from error
    if not isinstance(value, Mapping) or set(value) != {
        "schema", "source_id", "section_limit", "section_offset"
    }:
        raise DocumentViewContractError("DOCUMENT_REQUEST_FIELDS_INVALID")
    source_id = value["source_id"]
    offset = value["section_offset"]
    limit = value["section_limit"]
    if (
        value["schema"] != DOCUMENT_REQUEST_SCHEMA
        or not isinstance(source_id, str)
        or _HEX.fullmatch(source_id) is None
        or type(offset) is not int
        or not 0 <= offset <= 100000
        or type(limit) is not int
        or not 1 <= limit <= 10
    ):
        raise DocumentViewContractError("DOCUMENT_REQUEST_INVALID")
    return DocumentViewRequest(source_id, offset, limit)


def _unit_kind(projection_kind: str) -> str:
    if projection_kind in _KINDS:
        return projection_kind
    if "table" in projection_kind:
        return "table"
    if "form" in projection_kind:
        return "form"
    if "list" in projection_kind:
        return "list_item"
    if "step" in projection_kind or "procedure" in projection_kind:
        return "procedure_step"
    return "paragraph"


@dataclass(frozen=True, slots=True)
class NativePostgresDocumentReader:
    """Load exact active document versions without model or write access."""

    connection_factory: Callable[[], Any]
    expected_database_role: str = EXPECTED_RETRIEVAL_ROLE

    def __call__(self, request: DocumentViewRequest) -> bytes:
        if not isinstance(request, DocumentViewRequest):
            raise DocumentViewContractError("DOCUMENT_REQUEST_INVALID")
        connection = None
        try:
            connection = self.connection_factory()
            connection.execute(
                """/* ishikawa.document-view.begin */
                BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY
                """
            )
            boundary = connection.execute(
                """/* ishikawa.document-view.boundary */
                SELECT current_user,
                       current_setting('transaction_read_only'),
                       current_setting('transaction_isolation')
                """
            ).fetchone()
            if boundary != (self.expected_database_role, "on", "repeatable read"):
                raise RetrievalServiceContractError(
                    "document-view database boundary is invalid"
                )
            rows = connection.execute(
                """/* ishikawa.document-view.active-version */
                SELECT DISTINCT ON (ac.chunk_id)
                       ac.chunk_id, ac.document_version_id, ac.document_key,
                       ac.display_name, ac.class_id, ad.page_count,
                       ac.projection_kind, ac.ordinal, ac.retrieval_text,
                       citation.page_start, citation.page_end,
                       citation.structural_path, citation.relevant_excerpt
                FROM rag_search.active_chunks ac
                JOIN rag_search.active_documents ad
                  ON ad.document_version_id = ac.document_version_id
                JOIN rag_search.active_citations citation
                  ON citation.chunk_id = ac.chunk_id
                WHERE ac.document_version_id = %s
                ORDER BY ac.chunk_id, citation.page_start, citation.citation_id
                """,
                (request.source_id,),
            ).fetchall()
            if not rows:
                raise DocumentViewNotAvailable("DOCUMENT_VERSION_NOT_ACTIVE")
            if any(
                not isinstance(row, Sequence)
                or isinstance(row, (str, bytes))
                or len(row) != 13
                for row in rows
            ):
                raise RetrievalServiceContractError("document-view row is invalid")
            rows = sorted(rows, key=lambda row: (row[7], row[0]))
            first = rows[0]
            if any(tuple(row[1:6]) != tuple(first[1:6]) for row in rows):
                raise RetrievalServiceContractError(
                    "document-view identity is inconsistent"
                )

            sections: list[dict[str, Any]] = []
            section_by_heading: dict[str, dict[str, Any]] = {}
            declared_text: list[str] = []
            for row in rows:
                path = tuple(row[11])
                if any(
                    not isinstance(item, str) or not item.strip()
                    for item in path
                ):
                    raise RetrievalServiceContractError(
                        "document-view structural path is invalid"
                    )
                heading = path[0] if path else "Document content"
                section = section_by_heading.get(heading)
                if section is None:
                    section = {
                        "heading": heading,
                        "ordinal": len(sections),
                        "units": [],
                    }
                    sections.append(section)
                    section_by_heading[heading] = section
                section["units"].append(
                    {
                        "kind": _unit_kind(row[6]),
                        "page_end": row[10],
                        "page_start": row[9],
                        "structural_path": list(path),
                        "text": row[12],
                    }
                )
                if isinstance(row[12], str):
                    declared_text.append(row[12])

            selected = sections[
                request.section_offset:
                request.section_offset + request.section_limit
            ]
            if not selected and request.section_offset != len(sections):
                raise DocumentViewContractError("DOCUMENT_SECTION_OFFSET_INVALID")
            next_offset = request.section_offset + len(selected)
            declared = extract_declared_identifiers(declared_text)
            response = {
                "complete": next_offset >= len(sections),
                "next_section_offset": (
                    None if next_offset >= len(sections) else next_offset
                ),
                "schema": DOCUMENT_RESPONSE_SCHEMA,
                "sections": selected,
                "source": {
                    "display_name": first[3],
                    "document_class": first[4],
                    "document_identifier": declared[0] if len(declared) == 1 else None,
                    "document_key": first[2],
                    "page_count": first[5],
                    "source_id": first[1],
                },
                "total_sections": len(sections),
            }
            return canonical_json_bytes(response)
        except (
            DocumentViewContractError,
            DocumentViewNotAvailable,
            RetrievalDependencyUnavailable,
            RetrievalServiceContractError,
        ):
            raise
        except Exception as error:
            raise RetrievalDependencyUnavailable(
                "document_view_lookup_failed"
            ) from error
        finally:
            if connection is not None:
                try:
                    connection.rollback()
                except Exception:
                    pass
                try:
                    connection.close()
                except Exception:
                    pass
