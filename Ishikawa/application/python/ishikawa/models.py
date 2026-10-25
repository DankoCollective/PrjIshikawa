"""Immutable logical models for the frozen Ishikawa v1 contracts."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True, slots=True)
class DocumentClass:
    class_id: str
    display_name: str
    status: str

    def canonical(self) -> dict[str, str]:
        return {
            "class_id": self.class_id,
            "display_name": self.display_name,
            "status": self.status,
        }


@dataclass(frozen=True, slots=True)
class ClassRegistry:
    schema_version: int
    classes: tuple[DocumentClass, ...]
    digest: str

    def by_id(self) -> dict[str, DocumentClass]:
        return {item.class_id: item for item in self.classes}


@dataclass(frozen=True, slots=True)
class CatalogDocument:
    document_key: str
    display_name: str
    status: str

    def canonical(self) -> dict[str, str]:
        return {
            "document_key": self.document_key,
            "display_name": self.display_name,
            "status": self.status,
        }


@dataclass(frozen=True, slots=True)
class DocumentCatalog:
    schema_version: int
    documents: tuple[CatalogDocument, ...]
    digest: str

    def by_key(self) -> dict[str, CatalogDocument]:
        return {item.document_key: item for item in self.documents}


@dataclass(frozen=True, slots=True)
class ManifestDocument:
    source_path: str
    document_key: str
    class_id: str

    def canonical(self) -> dict[str, str]:
        return {
            "source_path": self.source_path,
            "document_key": self.document_key,
            "class_id": self.class_id,
        }


@dataclass(frozen=True, slots=True)
class ManifestRetirement:
    document_key: str

    def canonical(self) -> dict[str, str]:
        return {"document_key": self.document_key}


@dataclass(frozen=True, slots=True)
class IngestionManifest:
    schema_version: int
    documents: tuple[ManifestDocument, ...]
    retirements: tuple[ManifestRetirement, ...]
    digest: str


@dataclass(frozen=True, slots=True)
class PublishedDocumentState:
    document_key: str
    source_digest: str
    class_id: str
    method_profile_id: str
    document_id: str | None = None
    document_version_id: str | None = None
    artifact_set_id: str | None = None


@dataclass(frozen=True, slots=True)
class ValidationIssue:
    outcome: str
    reason_code: str
    safe_message: str
    document_key: str | None = None
    manifest_entry_identity: str | None = None

    def public_dict(self) -> dict[str, Any]:
        result: dict[str, Any] = {
            "outcome": self.outcome,
            "reason_code": self.reason_code,
            "message": self.safe_message,
        }
        if self.document_key is not None:
            result["document_key"] = self.document_key
        if self.manifest_entry_identity is not None:
            result["manifest_entry_identity"] = self.manifest_entry_identity
        return result


@dataclass(frozen=True, slots=True)
class EntryPlan:
    entry_kind: str
    entry_index: int
    manifest_entry_identity: str
    document_key: str
    outcome: str
    reason_code: str
    action: str | None = None
    source_path: str | None = None
    source_digest: str | None = None

    def protected_dict(self) -> dict[str, Any]:
        result: dict[str, Any] = {
            "entry_kind": self.entry_kind,
            "entry_index": self.entry_index,
            "manifest_entry_identity": self.manifest_entry_identity,
            "document_key": self.document_key,
            "outcome": self.outcome,
            "reason_code": self.reason_code,
            "action": self.action,
        }
        if self.source_path is not None:
            result["relative_source_path"] = self.source_path
        if self.source_digest is not None:
            result["source_digest"] = self.source_digest
        return result


@dataclass(frozen=True, slots=True)
class ValidationPlan:
    schema_version: int
    validation_id: str
    validation_only: bool
    mutation_performed: bool
    overall_outcome: str
    registry_digest: str
    catalog_digest: str
    manifest_digest: str
    method_profile_id: str
    entries: tuple[EntryPlan, ...]
    issues: tuple[ValidationIssue, ...]

    def action_counts(self) -> dict[str, int]:
        counts = {name: 0 for name in ("add", "revise", "reprocess", "reuse", "retire")}
        for entry in self.entries:
            if entry.action in counts:
                counts[entry.action] += 1
        return counts
