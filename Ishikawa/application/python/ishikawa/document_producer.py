"""Fail-closed boundary for producing writer-ready changed documents.

The operator-ingestion command decides *which* documents require work.  This
module owns the next boundary: one protected workspace, one exact production
stage, strict artifact identities, conversion to ``PreparedDocument`` values,
and retention of accepted producer evidence.  Poppler and Nomic remain
concrete deployment adapters behind ``artifact_stage``; this module never
silently substitutes estimated tokens, placeholder vectors, or stale files.
"""

from __future__ import annotations

import tempfile
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path

from .artifact_adapter import load_prepared_documents
from .canonical import domain_digest, file_sha256
from .chunking import METHOD_PROFILE_ID
from .models import IngestionManifest, ManifestDocument
from .operator_ingestion import ProductionBatch
from .persistence_models import PreparedDocument

MAX_DOCUMENTS_PER_BATCH = 256


class DocumentProducerContractError(RuntimeError):
    """Stable content-free failure at the document-production boundary."""


@dataclass(frozen=True, slots=True)
class ProducerArtifactBundle:
    """Checksum-bound outputs from extraction through Nomic embedding."""

    normalized_path: Path
    normalized_sha256: str
    chunk_path: Path
    chunk_sha256: str
    embedding_path: Path
    embedding_sha256: str


ArtifactStage = Callable[
    [ProductionBatch, IngestionManifest, Path], ProducerArtifactBundle
]
ArtifactRetainer = Callable[[ProducerArtifactBundle], None]
ArtifactAdapter = Callable[..., Sequence[PreparedDocument]]


def _fail(reason: str) -> None:
    raise DocumentProducerContractError(reason)


def _subset_manifest(
    configured_manifest: IngestionManifest,
    batch: ProductionBatch,
) -> IngestionManifest:
    configured = {item.document_key: item for item in configured_manifest.documents}
    selected: list[ManifestDocument] = []
    for request in batch.documents:
        item = configured.get(request.document_key)
        if item is None:
            _fail("production_document_absent_from_manifest")
        if (
            item.class_id != request.class_id
            or item.source_path != request.relative_source_path
        ):
            _fail("production_request_differs_from_manifest")
        selected.append(item)
    canonical = {
        "schema_version": 1,
        "documents": [item.canonical() for item in selected],
        "retirements": [],
    }
    return IngestionManifest(
        schema_version=1,
        documents=tuple(selected),
        retirements=(),
        digest=domain_digest("ishikawa.ingestion-manifest.v1", canonical),
    )


def _validate_batch(batch: ProductionBatch, manifest: IngestionManifest) -> IngestionManifest:
    if not isinstance(batch, ProductionBatch):
        _fail("production_batch_invalid")
    if batch.method_profile_id != METHOD_PROFILE_ID:
        _fail("production_method_profile_mismatch")
    if not 1 <= len(batch.documents) <= MAX_DOCUMENTS_PER_BATCH:
        _fail("production_batch_size_invalid")
    if len({item.document_key for item in batch.documents}) != len(batch.documents):
        _fail("production_document_key_duplicate")
    if len({item.relative_source_path for item in batch.documents}) != len(batch.documents):
        _fail("production_source_path_duplicate")
    if any(item.action not in {"add", "revise", "reprocess"} for item in batch.documents):
        _fail("production_action_invalid")

    root = batch.source_root
    if not root.is_absolute() or root.is_symlink() or not root.is_dir():
        _fail("production_source_root_unsafe")
    resolved_root = root.resolve(strict=True)
    for request in batch.documents:
        source = root.joinpath(*request.relative_source_path.split("/"))
        if source.is_symlink() or not source.is_file():
            _fail("production_source_unsafe")
        try:
            resolved = source.resolve(strict=True)
            resolved.relative_to(resolved_root)
        except (OSError, ValueError):
            _fail("production_source_unsafe")
        if file_sha256(str(resolved)) != request.source_digest:
            _fail("production_source_identity_mismatch")
    return _subset_manifest(manifest, batch)


def _validate_bundle(bundle: ProducerArtifactBundle, workspace: Path) -> None:
    if not isinstance(bundle, ProducerArtifactBundle):
        _fail("producer_artifact_bundle_invalid")
    resolved_workspace = workspace.resolve(strict=True)
    entries = (
        (bundle.normalized_path, bundle.normalized_sha256),
        (bundle.chunk_path, bundle.chunk_sha256),
        (bundle.embedding_path, bundle.embedding_sha256),
    )
    if len({path for path, _ in entries}) != len(entries):
        _fail("producer_artifact_path_duplicate")
    for path, expected_sha256 in entries:
        if path.is_symlink() or not path.is_file():
            _fail("producer_artifact_unsafe")
        try:
            path.resolve(strict=True).relative_to(resolved_workspace)
        except (OSError, ValueError):
            _fail("producer_artifact_outside_workspace")
        if (
            len(expected_sha256) != 64
            or any(character not in "0123456789abcdef" for character in expected_sha256)
            or file_sha256(str(path)) != expected_sha256
        ):
            _fail("producer_artifact_identity_mismatch")


@dataclass(frozen=True, slots=True)
class NativeDocumentProducer:
    """Produce exactly the changed documents requested by ingestion planning."""

    manifest: IngestionManifest
    work_root: Path
    artifact_stage: ArtifactStage
    artifact_retainer: ArtifactRetainer
    artifact_adapter: ArtifactAdapter = load_prepared_documents

    def __post_init__(self) -> None:
        if not isinstance(self.manifest, IngestionManifest):
            _fail("producer_manifest_invalid")
        if (
            not self.work_root.is_absolute()
            or self.work_root.is_symlink()
            or not self.work_root.is_dir()
        ):
            _fail("producer_work_root_unsafe")
        if not all(
            callable(item)
            for item in (self.artifact_stage, self.artifact_retainer, self.artifact_adapter)
        ):
            _fail("producer_dependency_invalid")

    def __call__(self, batch: ProductionBatch) -> tuple[PreparedDocument, ...]:
        subset = _validate_batch(batch, self.manifest)
        workspace_parent = self.work_root.resolve(strict=True)
        with tempfile.TemporaryDirectory(
            prefix="document-production-", dir=workspace_parent
        ) as temporary:
            workspace = Path(temporary)
            workspace.chmod(0o700)
            bundle = self.artifact_stage(batch, subset, workspace)
            _validate_bundle(bundle, workspace)
            prepared = tuple(
                self.artifact_adapter(
                    normalized_path=bundle.normalized_path,
                    normalized_sha256=bundle.normalized_sha256,
                    chunk_path=bundle.chunk_path,
                    chunk_sha256=bundle.chunk_sha256,
                    embedding_path=bundle.embedding_path,
                    embedding_sha256=bundle.embedding_sha256,
                    manifest=subset,
                    source_root=batch.source_root,
                )
            )
            requested = {
                item.document_key: (item.class_id, item.source_digest)
                for item in batch.documents
            }
            observed = {
                item.document_key: (item.class_id, item.source_digest)
                for item in prepared
            }
            if len(observed) != len(prepared) or observed != requested:
                _fail("prepared_document_coverage_mismatch")
            self.artifact_retainer(bundle)
            return tuple(sorted(prepared, key=lambda item: item.document_key))
