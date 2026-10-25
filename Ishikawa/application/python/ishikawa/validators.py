"""Exact-schema validators for Ishikawa's frozen v1 YAML contracts."""

from __future__ import annotations

import re
from collections.abc import Mapping
from pathlib import PurePosixPath
from typing import Any

from .canonical import domain_digest
from .errors import IshikawaValidationError
from .models import (
    CatalogDocument,
    ClassRegistry,
    DocumentCatalog,
    DocumentClass,
    IngestionManifest,
    ManifestDocument,
    ManifestRetirement,
)

_CLASS_ID = re.compile(r"^[a-z][a-z0-9._-]{0,127}$")
_DOCUMENT_KEY = re.compile(r"^[a-z0-9][a-z0-9._-]{0,127}$")
_STATUS = frozenset({"active", "retired"})


def _fail(reason_code: str, message: str) -> None:
    raise IshikawaValidationError("REJECTED", reason_code, message)


def _mapping(value: Any, *, label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        _fail("SCHEMA_TYPE_INVALID", f"{label} must be a mapping.")
    if not all(isinstance(key, str) for key in value):
        _fail("SCHEMA_FIELD_INVALID", f"{label} contains a non-string field name.")
    return value


def _exact_fields(
    value: Mapping[str, Any], *, required: frozenset[str], label: str
) -> None:
    keys = frozenset(value)
    missing = sorted(required - keys)
    unknown = sorted(keys - required)
    if missing:
        _fail("SCHEMA_FIELD_MISSING", f"{label} is missing required field '{missing[0]}'.")
    if unknown:
        _fail("SCHEMA_FIELD_UNKNOWN", f"{label} contains unknown field '{unknown[0]}'.")


def _schema_version(value: Any, *, label: str) -> int:
    if type(value) is not int or value != 1:  # bool is intentionally not an integer here
        _fail("SCHEMA_VERSION_UNSUPPORTED", f"{label} requires integer schema_version 1.")
    return value


def _list(value: Any, *, label: str, nonempty: bool = False) -> list[Any]:
    if not isinstance(value, list):
        _fail("SCHEMA_TYPE_INVALID", f"{label} must be a list.")
    if nonempty and not value:
        _fail("SCHEMA_LIST_EMPTY", f"{label} must not be empty.")
    return value


def _string(value: Any, *, label: str, pattern: re.Pattern[str] | None = None) -> str:
    if not isinstance(value, str) or not value.strip():
        _fail("SCHEMA_VALUE_INVALID", f"{label} must be a nonblank string.")
    if value != value.strip():
        _fail("SCHEMA_VALUE_INVALID", f"{label} must not contain leading or trailing whitespace.")
    if pattern is not None and pattern.fullmatch(value) is None:
        _fail("IDENTIFIER_INVALID", f"{label} does not match the frozen identifier syntax.")
    return value


def _status(value: Any, *, label: str) -> str:
    status = _string(value, label=label)
    if status not in _STATUS:
        _fail("STATUS_INVALID", f"{label} must be active or retired.")
    return status


def _punctuation_key(value: str) -> str:
    return re.sub(r"[._-]+", "", value)


def _assert_unique_identifiers(values: list[str], *, label: str) -> None:
    exact: set[str] = set()
    equivalent: dict[str, str] = {}
    for value in values:
        if value in exact:
            _fail("IDENTIFIER_DUPLICATE", f"{label} contains duplicate identifier '{value}'.")
        exact.add(value)
        normalized = _punctuation_key(value)
        prior = equivalent.get(normalized)
        if prior is not None and prior != value:
            _fail(
                "IDENTIFIER_PUNCTUATION_COLLISION",
                f"{label} contains punctuation-equivalent identifiers '{prior}' and '{value}'.",
            )
        equivalent[normalized] = value


def _canonical_registry(classes: list[DocumentClass]) -> dict[str, Any]:
    return {
        "schema_version": 1,
        "classes": [item.canonical() for item in sorted(classes, key=lambda item: item.class_id)],
    }


def _canonical_catalog(documents: list[CatalogDocument]) -> dict[str, Any]:
    return {
        "schema_version": 1,
        "documents": [
            item.canonical() for item in sorted(documents, key=lambda item: item.document_key)
        ],
    }


def _canonical_manifest(
    documents: list[ManifestDocument], retirements: list[ManifestRetirement]
) -> dict[str, Any]:
    return {
        "schema_version": 1,
        "documents": [
            item.canonical()
            for item in sorted(documents, key=lambda item: (item.document_key, item.source_path))
        ],
        "retirements": [
            item.canonical() for item in sorted(retirements, key=lambda item: item.document_key)
        ],
    }


def validate_class_registry(value: Any) -> ClassRegistry:
    """Validate and canonically identify ``document_classes.yaml``."""

    root = _mapping(value, label="document-class registry")
    _exact_fields(root, required=frozenset({"schema_version", "classes"}), label="document-class registry")
    version = _schema_version(root["schema_version"], label="document-class registry")
    raw_classes = _list(root["classes"], label="document-class registry classes", nonempty=True)

    classes: list[DocumentClass] = []
    for index, raw in enumerate(raw_classes):
        item = _mapping(raw, label=f"class entry {index}")
        _exact_fields(
            item,
            required=frozenset({"class_id", "display_name", "status"}),
            label=f"class entry {index}",
        )
        classes.append(
            DocumentClass(
                class_id=_string(item["class_id"], label=f"class entry {index} class_id", pattern=_CLASS_ID),
                display_name=_string(item["display_name"], label=f"class entry {index} display_name"),
                status=_status(item["status"], label=f"class entry {index} status"),
            )
        )

    _assert_unique_identifiers([item.class_id for item in classes], label="class registry")
    canonical = _canonical_registry(classes)
    return ClassRegistry(version, tuple(classes), domain_digest("ishikawa.document-classes.v1", canonical))


def validate_document_catalog(value: Any) -> DocumentCatalog:
    """Validate and canonically identify ``document_catalog.yaml``."""

    root = _mapping(value, label="document catalog")
    _exact_fields(root, required=frozenset({"schema_version", "documents"}), label="document catalog")
    version = _schema_version(root["schema_version"], label="document catalog")
    raw_documents = _list(root["documents"], label="document catalog documents")

    documents: list[CatalogDocument] = []
    for index, raw in enumerate(raw_documents):
        item = _mapping(raw, label=f"catalog entry {index}")
        _exact_fields(
            item,
            required=frozenset({"document_key", "display_name", "status"}),
            label=f"catalog entry {index}",
        )
        documents.append(
            CatalogDocument(
                document_key=_string(
                    item["document_key"],
                    label=f"catalog entry {index} document_key",
                    pattern=_DOCUMENT_KEY,
                ),
                display_name=_string(item["display_name"], label=f"catalog entry {index} display_name"),
                status=_status(item["status"], label=f"catalog entry {index} status"),
            )
        )

    _assert_unique_identifiers([item.document_key for item in documents], label="document catalog")
    canonical = _canonical_catalog(documents)
    return DocumentCatalog(version, tuple(documents), domain_digest("ishikawa.document-catalog.v1", canonical))


def _validate_relative_pdf_path(value: Any, *, label: str) -> str:
    source_path = _string(value, label=label)
    if "\\" in source_path:
        _fail("SOURCE_PATH_INVALID", f"{label} must use forward slashes.")
    parsed = PurePosixPath(source_path)
    if parsed.is_absolute():
        _fail("SOURCE_PATH_ABSOLUTE", f"{label} must be relative.")
    parts = source_path.split("/")
    if any(part in {"", ".", ".."} for part in parts):
        _fail("SOURCE_PATH_TRAVERSAL", f"{label} contains an unsafe path component.")
    if parsed.suffix.lower() != ".pdf":
        _fail("SOURCE_FORMAT_UNSUPPORTED", f"{label} must name a PDF file.")
    return source_path


def validate_ingestion_manifest(value: Any) -> IngestionManifest:
    """Validate and canonically identify one incremental ingestion manifest."""

    root = _mapping(value, label="ingestion manifest")
    _exact_fields(
        root,
        required=frozenset({"schema_version", "documents", "retirements"}),
        label="ingestion manifest",
    )
    version = _schema_version(root["schema_version"], label="ingestion manifest")
    raw_documents = _list(root["documents"], label="ingestion manifest documents")
    raw_retirements = _list(root["retirements"], label="ingestion manifest retirements")
    if not raw_documents and not raw_retirements:
        _fail("MANIFEST_EMPTY", "The ingestion manifest must contain at least one action.")

    documents: list[ManifestDocument] = []
    for index, raw in enumerate(raw_documents):
        item = _mapping(raw, label=f"manifest document {index}")
        _exact_fields(
            item,
            required=frozenset({"source_path", "document_key", "class_id"}),
            label=f"manifest document {index}",
        )
        documents.append(
            ManifestDocument(
                source_path=_validate_relative_pdf_path(
                    item["source_path"], label=f"manifest document {index} source_path"
                ),
                document_key=_string(
                    item["document_key"],
                    label=f"manifest document {index} document_key",
                    pattern=_DOCUMENT_KEY,
                ),
                class_id=_string(
                    item["class_id"],
                    label=f"manifest document {index} class_id",
                    pattern=_CLASS_ID,
                ),
            )
        )

    retirements: list[ManifestRetirement] = []
    for index, raw in enumerate(raw_retirements):
        item = _mapping(raw, label=f"manifest retirement {index}")
        _exact_fields(
            item,
            required=frozenset({"document_key"}),
            label=f"manifest retirement {index}",
        )
        retirements.append(
            ManifestRetirement(
                document_key=_string(
                    item["document_key"],
                    label=f"manifest retirement {index} document_key",
                    pattern=_DOCUMENT_KEY,
                )
            )
        )

    document_keys = [item.document_key for item in documents]
    source_paths = [item.source_path for item in documents]
    retirement_keys = [item.document_key for item in retirements]
    if len(document_keys) != len(set(document_keys)):
        _fail("MANIFEST_DOCUMENT_KEY_DUPLICATE", "A document key appears more than once in manifest documents.")
    if len(source_paths) != len(set(source_paths)):
        _fail("MANIFEST_SOURCE_PATH_DUPLICATE", "A source path appears more than once in manifest documents.")
    if len(retirement_keys) != len(set(retirement_keys)):
        _fail("MANIFEST_RETIREMENT_DUPLICATE", "A document key appears more than once in retirements.")
    conflicts = sorted(set(document_keys) & set(retirement_keys))
    if conflicts:
        _fail("MANIFEST_ACTION_CONFLICT", f"Document key '{conflicts[0]}' has conflicting manifest actions.")

    canonical = _canonical_manifest(documents, retirements)
    return IngestionManifest(
        version,
        tuple(documents),
        tuple(retirements),
        domain_digest("ishikawa.ingestion-manifest.v1", canonical),
    )
