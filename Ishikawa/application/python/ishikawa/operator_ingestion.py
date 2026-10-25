"""Operator-facing orchestration for one incremental ingestion manifest.

This module owns control flow, not document processing.  It loads and
validates the three operator YAML files, compares them with published state,
writes protected reports, asks one injected producer for only the documents
that require work, and hands the result to the accepted atomic writer.

Concrete PostgreSQL connection creation, extraction, chunking, embedding, and
credential acquisition remain deployment adapters.  Keeping those boundaries
injected makes ``--validate-only`` incapable of accidentally invoking a
producer or writer and lets the orchestration be tested without services.
"""

from __future__ import annotations

from collections.abc import Callable, Sequence
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any

from .models import (
    ClassRegistry,
    DocumentCatalog,
    IngestionManifest,
    ValidationPlan,
)
from .persistence import load_catalog_keys, load_published_state, write_incremental_plan
from .persistence_models import PreparedDocument, WriteResult
from .planner import plan_ingestion
from .relationships import (
    ReferenceOwner,
    RelationshipRegistry,
    discover_prepared_relationships,
    extract_declared_identifiers,
)
from .reporting import render_terminal_summary, write_protected_reports
from .validators import (
    validate_class_registry,
    validate_document_catalog,
    validate_ingestion_manifest,
)
from .yaml_loader import load_restricted_yaml


class OperatorIngestionContractError(RuntimeError):
    """A stable failure at the orchestration dependency boundary."""


@dataclass(frozen=True, slots=True)
class OperatorIngestionPaths:
    """Paths needed for one invocation of the operator ingestion command."""

    class_registry: Path
    document_catalog: Path
    ingestion_manifest: Path
    source_root: Path
    report_root: Path


@dataclass(frozen=True, slots=True)
class DocumentProductionRequest:
    """One document that the accepted planner says must be produced."""

    action: str
    document_key: str
    class_id: str
    relative_source_path: str
    source_digest: str


@dataclass(frozen=True, slots=True)
class ProductionBatch:
    """Bounded input to the extraction/chunking/embedding producer."""

    validation_id: str
    method_profile_id: str
    source_root: Path
    documents: tuple[DocumentProductionRequest, ...]


@dataclass(frozen=True, slots=True)
class OperatorIngestionResult:
    """Content-safe result returned to an eventual command-line adapter."""

    plan: ValidationPlan
    text_report: Path
    json_report: Path
    write_result: WriteResult | None
    terminal_summary: str
    exit_code: int


PreparedDocumentProducer = Callable[[ProductionBatch], Sequence[PreparedDocument]]
IncrementalWriter = Callable[..., WriteResult]


def _active_reference_owners(
    connection: Any,
    *,
    excluded_document_keys: frozenset[str],
) -> tuple[ReferenceOwner, ...]:
    """Load conservative declarations from reusable active documents.

    Changed documents supply their declarations from their newly prepared
    artifacts. Active declarations are needed only for unchanged targets, so
    exclude every newly prepared key and avoid resolving against a superseded
    version of that same document.
    """

    rows = connection.execute(
        """/* ishikawa.load-active-reference-owners */
        SELECT document_key, document_id, relevant_excerpt
        FROM rag_search.active_citations
        WHERE cardinality(%s::text[]) = 0
           OR document_key <> ALL(%s::text[])
        ORDER BY document_key, citation_id
        """,
        (list(excluded_document_keys), list(excluded_document_keys)),
    ).fetchall()
    excerpts: dict[tuple[str, str], list[str]] = {}
    for row in rows:
        if (
            not isinstance(row, Sequence)
            or isinstance(row, (str, bytes))
            or len(row) != 3
            or not isinstance(row[0], str)
            or not isinstance(row[1], str)
            or not isinstance(row[2], str)
        ):
            raise OperatorIngestionContractError("active_reference_owner_row_invalid")
        excerpts.setdefault((row[0], row[1]), []).append(row[2])
    return tuple(
        ReferenceOwner(reference, document_key, document_id)
        for (document_key, document_id), values in sorted(excerpts.items())
        for reference in extract_declared_identifiers(values)
    )


def load_operator_configuration(
    paths: OperatorIngestionPaths,
) -> tuple[ClassRegistry, DocumentCatalog, IngestionManifest]:
    """Load the three exact, restricted operator configuration files."""

    registry = validate_class_registry(
        load_restricted_yaml(paths.class_registry, label="document-class registry")
    )
    catalog = validate_document_catalog(
        load_restricted_yaml(paths.document_catalog, label="document catalog")
    )
    manifest = validate_ingestion_manifest(
        load_restricted_yaml(paths.ingestion_manifest, label="ingestion manifest")
    )
    return registry, catalog, manifest


def _production_batch(
    plan: ValidationPlan,
    manifest: IngestionManifest,
    source_root: Path,
) -> ProductionBatch:
    configured = {item.document_key: item for item in manifest.documents}
    requests: list[DocumentProductionRequest] = []
    for entry in plan.entries:
        if entry.outcome != "PASS" or entry.action not in {"add", "revise", "reprocess"}:
            continue
        item = configured[entry.document_key]
        if entry.source_digest is None:
            raise OperatorIngestionContractError("planned_document_source_digest_absent")
        requests.append(
            DocumentProductionRequest(
                action=entry.action,
                document_key=entry.document_key,
                class_id=item.class_id,
                relative_source_path=item.source_path,
                source_digest=entry.source_digest,
            )
        )
    return ProductionBatch(
        validation_id=plan.validation_id,
        method_profile_id=plan.method_profile_id,
        source_root=source_root.resolve(strict=True),
        documents=tuple(requests),
    )


def _reported_result(
    plan: ValidationPlan,
    report_root: Path,
    *,
    write_result: WriteResult | None,
    exit_code: int,
) -> OperatorIngestionResult:
    text_path, json_path = write_protected_reports(plan, report_root)
    return OperatorIngestionResult(
        plan=plan,
        text_report=text_path,
        json_report=json_path,
        write_result=write_result,
        terminal_summary=render_terminal_summary(plan, report_root),
        exit_code=exit_code,
    )


def run_operator_ingestion(
    *,
    paths: OperatorIngestionPaths,
    method_profile_id: str,
    connection: Any,
    validate_only: bool,
    producer: PreparedDocumentProducer | None = None,
    writer: IncrementalWriter = write_incremental_plan,
    relationship_registry: RelationshipRegistry | None = None,
) -> OperatorIngestionResult:
    """Plan or execute one atomic incremental ingestion manifest.

    Validation-only mode reads the live catalog projection so its plan is
    accurate, but it never invokes the producer or writer.  An actual run
    produces only ``add``, ``revise``, and ``reprocess`` entries.  ``reuse``
    and ``retire`` never invoke document processing.  A quarantined plan is
    handed directly to the writer with no prepared documents so the accepted
    database quarantine record can be created without publishing the batch.
    Rejected plans never invoke either dependency.
    """

    registry, catalog, manifest = load_operator_configuration(paths)
    published = load_published_state(connection)
    prior_catalog_keys = load_catalog_keys(connection)
    planned = plan_ingestion(
        registry,
        catalog,
        manifest,
        source_root=paths.source_root,
        method_profile_id=method_profile_id,
        published_state=published,
        prior_catalog_keys=prior_catalog_keys,
    )

    if validate_only:
        return _reported_result(
            planned,
            paths.report_root,
            write_result=None,
            exit_code=0 if planned.overall_outcome == "PASS" else 1,
        )

    executable = replace(planned, validation_only=False)
    if executable.overall_outcome not in {"PASS", "QUARANTINED"}:
        return _reported_result(
            executable,
            paths.report_root,
            write_result=None,
            exit_code=2,
        )

    batch = _production_batch(executable, manifest, paths.source_root)
    prepared: Sequence[PreparedDocument] = ()
    if executable.overall_outcome == "PASS" and batch.documents:
        if producer is None:
            raise OperatorIngestionContractError("prepared_document_producer_required")
        prepared = tuple(producer(batch))
    if relationship_registry is None:
        write_result = writer(
            connection,
            registry,
            catalog,
            manifest,
            executable,
            prepared,
        )
    else:
        prepared_keys = frozenset(item.document_key for item in prepared)
        active_owners = _active_reference_owners(
            connection,
            excluded_document_keys=prepared_keys,
        )
        observations = discover_prepared_relationships(
            prepared,
            method_profile_id=method_profile_id,
            registry=relationship_registry,
            additional_owners=active_owners,
        )
        write_result = writer(
            connection,
            registry,
            catalog,
            manifest,
            executable,
            prepared,
            relationship_registry=relationship_registry,
            relationship_observations=observations,
        )
    mutated = write_result.outcome in {"PUBLISHED", "QUARANTINED"}
    completed = replace(executable, mutation_performed=mutated)
    exit_code = 0 if write_result.outcome in {"PUBLISHED", "SKIPPED"} else 1
    return _reported_result(
        completed,
        paths.report_root,
        write_result=write_result,
        exit_code=exit_code,
    )
