"""Cross-file validation and affected-document planning for Ishikawa v1."""

from __future__ import annotations

import os
import re
from pathlib import Path
from typing import Iterable, Mapping

from .canonical import domain_digest, file_sha256
from .errors import IshikawaValidationError
from .models import (
    ClassRegistry,
    DocumentCatalog,
    EntryPlan,
    IngestionManifest,
    ManifestDocument,
    ManifestRetirement,
    PublishedDocumentState,
    ValidationIssue,
    ValidationPlan,
)

_SHA256 = re.compile(r"^[0-9a-f]{64}$")
_OUTCOME_PRIORITY = {"PASS": 0, "QUARANTINED": 1, "REJECTED": 2, "BLOCKED": 3, "FAILED": 4}


def _entry_identity(kind: str, entry: ManifestDocument | ManifestRetirement) -> str:
    return domain_digest(
        "ishikawa.manifest-entry.v1",
        {"entry_kind": kind, "entry": entry.canonical()},
    )


def _entry_problem(
    *,
    kind: str,
    index: int,
    identity: str,
    document_key: str,
    outcome: str,
    reason_code: str,
    source_path: str | None = None,
) -> EntryPlan:
    return EntryPlan(
        entry_kind=kind,
        entry_index=index,
        manifest_entry_identity=identity,
        document_key=document_key,
        outcome=outcome,
        reason_code=reason_code,
        source_path=source_path,
    )


def _source_file(
    root: Path,
    item: ManifestDocument,
    *,
    index: int,
    identity: str,
) -> tuple[Path | None, EntryPlan | None]:
    candidate = root.joinpath(*item.source_path.split("/"))

    # Reject a symlink at any existing component beneath the source root. This
    # prevents a safe-looking manifest path from changing targets over time.
    cursor = root
    for part in item.source_path.split("/"):
        cursor = cursor / part
        if cursor.is_symlink():
            return None, _entry_problem(
                kind="document",
                index=index,
                identity=identity,
                document_key=item.document_key,
                outcome="REJECTED",
                reason_code="SOURCE_PATH_SYMLINK",
                source_path=item.source_path,
            )

    try:
        resolved = candidate.resolve(strict=True)
    except OSError:
        return None, _entry_problem(
            kind="document",
            index=index,
            identity=identity,
            document_key=item.document_key,
            outcome="REJECTED",
            reason_code="SOURCE_FILE_UNAVAILABLE",
            source_path=item.source_path,
        )

    try:
        resolved.relative_to(root)
    except ValueError:
        return None, _entry_problem(
            kind="document",
            index=index,
            identity=identity,
            document_key=item.document_key,
            outcome="REJECTED",
            reason_code="SOURCE_PATH_OUTSIDE_ROOT",
            source_path=item.source_path,
        )

    if not resolved.is_file():
        return None, _entry_problem(
            kind="document",
            index=index,
            identity=identity,
            document_key=item.document_key,
            outcome="REJECTED",
            reason_code="SOURCE_NOT_REGULAR_FILE",
            source_path=item.source_path,
        )

    try:
        with resolved.open("rb") as source:
            signature = source.read(5)
    except OSError:
        return None, _entry_problem(
            kind="document",
            index=index,
            identity=identity,
            document_key=item.document_key,
            outcome="REJECTED",
            reason_code="SOURCE_FILE_UNREADABLE",
            source_path=item.source_path,
        )
    if signature != b"%PDF-":
        return None, _entry_problem(
            kind="document",
            index=index,
            identity=identity,
            document_key=item.document_key,
            outcome="QUARANTINED",
            reason_code="UNSUPPORTED_PDF",
            source_path=item.source_path,
        )
    return resolved, None


def _plan_document(
    item: ManifestDocument,
    *,
    index: int,
    root: Path,
    classes: Mapping[str, object],
    catalog: Mapping[str, object],
    published: Mapping[str, PublishedDocumentState],
    method_profile_id: str,
) -> EntryPlan:
    identity = _entry_identity("document", item)
    catalog_item = catalog.get(item.document_key)
    if catalog_item is None:
        return _entry_problem(
            kind="document",
            index=index,
            identity=identity,
            document_key=item.document_key,
            outcome="QUARANTINED",
            reason_code="UNKNOWN_DOCUMENT_KEY",
            source_path=item.source_path,
        )
    if getattr(catalog_item, "status") != "active":
        return _entry_problem(
            kind="document",
            index=index,
            identity=identity,
            document_key=item.document_key,
            outcome="REJECTED",
            reason_code="CATALOG_DOCUMENT_RETIRED",
            source_path=item.source_path,
        )

    class_item = classes.get(item.class_id)
    if class_item is None:
        return _entry_problem(
            kind="document",
            index=index,
            identity=identity,
            document_key=item.document_key,
            outcome="REJECTED",
            reason_code="UNKNOWN_CLASS_ID",
            source_path=item.source_path,
        )
    if getattr(class_item, "status") != "active":
        return _entry_problem(
            kind="document",
            index=index,
            identity=identity,
            document_key=item.document_key,
            outcome="REJECTED",
            reason_code="CLASS_RETIRED",
            source_path=item.source_path,
        )

    source, problem = _source_file(root, item, index=index, identity=identity)
    if problem is not None:
        return problem
    assert source is not None
    source_digest = file_sha256(os.fspath(source))
    prior = published.get(item.document_key)
    if prior is None:
        action = "add"
    elif prior.source_digest != source_digest:
        action = "revise"
    elif prior.class_id != item.class_id or prior.method_profile_id != method_profile_id:
        action = "reprocess"
    else:
        action = "reuse"

    return EntryPlan(
        entry_kind="document",
        entry_index=index,
        manifest_entry_identity=identity,
        document_key=item.document_key,
        outcome="PASS",
        reason_code="VALID",
        action=action,
        source_path=item.source_path,
        source_digest=source_digest,
    )


def _plan_retirement(
    item: ManifestRetirement,
    *,
    index: int,
    catalog: Mapping[str, object],
    published: Mapping[str, PublishedDocumentState],
) -> EntryPlan:
    identity = _entry_identity("retirement", item)
    catalog_item = catalog.get(item.document_key)
    if catalog_item is None:
        return _entry_problem(
            kind="retirement",
            index=index,
            identity=identity,
            document_key=item.document_key,
            outcome="QUARANTINED",
            reason_code="UNKNOWN_DOCUMENT_KEY",
        )
    if getattr(catalog_item, "status") != "retired":
        return _entry_problem(
            kind="retirement",
            index=index,
            identity=identity,
            document_key=item.document_key,
            outcome="REJECTED",
            reason_code="RETIREMENT_STATUS_MISMATCH",
        )
    if item.document_key not in published:
        return _entry_problem(
            kind="retirement",
            index=index,
            identity=identity,
            document_key=item.document_key,
            outcome="REJECTED",
            reason_code="RETIREMENT_NOT_PUBLISHED",
        )
    return EntryPlan(
        entry_kind="retirement",
        entry_index=index,
        manifest_entry_identity=identity,
        document_key=item.document_key,
        outcome="PASS",
        reason_code="VALID",
        action="retire",
    )


def _overall(entries: Iterable[EntryPlan], issues: Iterable[ValidationIssue]) -> str:
    outcomes = [entry.outcome for entry in entries]
    outcomes.extend(issue.outcome for issue in issues)
    return max(outcomes or ["PASS"], key=lambda item: _OUTCOME_PRIORITY[item])


def plan_ingestion(
    registry: ClassRegistry,
    catalog: DocumentCatalog,
    manifest: IngestionManifest,
    *,
    source_root: str | Path,
    method_profile_id: str,
    published_state: Mapping[str, PublishedDocumentState] | None = None,
    prior_catalog_keys: Iterable[str] | None = None,
) -> ValidationPlan:
    """Validate references and plan changes without mutating external state."""

    if _SHA256.fullmatch(method_profile_id) is None:
        raise IshikawaValidationError(
            "REJECTED",
            "METHOD_PROFILE_ID_INVALID",
            "The method profile identity must be a lowercase SHA-256 digest.",
        )

    root_path = Path(source_root)
    try:
        root = root_path.resolve(strict=True)
    except OSError as exc:
        raise IshikawaValidationError(
            "REJECTED", "SOURCE_ROOT_UNAVAILABLE", "The configured corpus source root is unavailable."
        ) from exc
    if not root.is_dir():
        raise IshikawaValidationError(
            "REJECTED", "SOURCE_ROOT_NOT_DIRECTORY", "The configured corpus source root is not a directory."
        )

    current = published_state or {}
    class_by_id = registry.by_id()
    catalog_by_key = catalog.by_key()
    issues: list[ValidationIssue] = []
    if prior_catalog_keys is not None:
        removed = sorted(set(prior_catalog_keys) - set(catalog_by_key))
        for document_key in removed:
            issues.append(
                ValidationIssue(
                    outcome="REJECTED",
                    reason_code="CATALOG_KEY_REMOVED",
                    safe_message="A previously registered document key is missing from the catalog.",
                    document_key=document_key,
                )
            )

    entries: list[EntryPlan] = []
    for index, item in enumerate(manifest.documents):
        entries.append(
            _plan_document(
                item,
                index=index,
                root=root,
                classes=class_by_id,
                catalog=catalog_by_key,
                published=current,
                method_profile_id=method_profile_id,
            )
        )
    for index, item in enumerate(manifest.retirements):
        entries.append(
            _plan_retirement(
                item,
                index=index,
                catalog=catalog_by_key,
                published=current,
            )
        )

    overall = _overall(entries, issues)
    validation_id = domain_digest(
        "ishikawa.validation-plan.v1",
        {
            "registry_digest": registry.digest,
            "catalog_digest": catalog.digest,
            "manifest_digest": manifest.digest,
            "method_profile_id": method_profile_id,
            "entries": [entry.protected_dict() for entry in entries],
            "issues": [issue.public_dict() for issue in issues],
        },
    )
    return ValidationPlan(
        schema_version=1,
        validation_id=validation_id,
        validation_only=True,
        mutation_performed=False,
        overall_outcome=overall,
        registry_digest=registry.digest,
        catalog_digest=catalog.digest,
        manifest_digest=manifest.digest,
        method_profile_id=method_profile_id,
        entries=tuple(entries),
        issues=tuple(issues),
    )
