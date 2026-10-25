"""Portable command boundary for one Ishikawa operator-ingestion run."""

from __future__ import annotations

import argparse
import re
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any, TextIO

from .document_producer import METHOD_PROFILE_ID
from .operator_ingestion import (
    IncrementalWriter,
    OperatorIngestionPaths,
    PreparedDocumentProducer,
    run_operator_ingestion,
)
from .persistence import write_incremental_plan
from .relationships import RelationshipRegistry


class IngestionCommandContractError(ValueError):
    """Stable, content-free command-boundary failure."""


_STABLE_RUNTIME_FAILURES = {
    ("ishikawa.artifact_adapter", "ArtifactAdapterError"): "artifact_adapter",
    ("ishikawa.document_producer", "DocumentProducerContractError"): "document_producer",
    ("ishikawa.installed_ingestion", "InstalledIngestionError"): "artifact_retention",
    ("ishikawa.live_document_stage", "LiveDocumentStageError"): "live_document_stage",
    ("ishikawa.operator_ingestion", "OperatorIngestionContractError"): "operator_ingestion",
}
_STABLE_RUNTIME_MESSAGES = {
    (
        "ishikawa.persistence",
        "PersistenceContractError",
        "required PostgreSQL result is absent",
    ): "persistence_required_postgresql_result_absent",
    (
        "ishikawa.persistence",
        "PersistenceContractError",
        "PostgreSQL consolidated contract does not match schema version 5",
    ): "persistence_schema_contract_mismatch",
    (
        "ishikawa.persistence",
        "PersistenceContractError",
        "a persisted document key is missing from the catalog",
    ): "persistence_catalog_document_missing",
    (
        "ishikawa.persistence",
        "PersistenceContractError",
        "relationship observations require a relationship registry",
    ): "persistence_relationship_registry_required",
    (
        "ishikawa.persistence",
        "PersistenceContractError",
        "unresolved relationship observations cannot be published",
    ): "persistence_relationship_observation_unresolved",
    (
        "ishikawa.persistence",
        "PersistenceContractError",
        "relationship edge identities must be unique",
    ): "persistence_relationship_edge_identity_duplicate",
    (
        "ishikawa.persistence",
        "PersistenceContractError",
        "relationship edge conflicts with its registry definition",
    ): "persistence_relationship_registry_conflict",
    (
        "ishikawa.persistence",
        "PersistenceContractError",
        "relationship edge registry identity mismatch",
    ): "persistence_relationship_registry_identity_mismatch",
    (
        "ishikawa.persistence",
        "PersistenceContractError",
        "relationship override audit provenance is incomplete",
    ): "persistence_relationship_override_provenance_incomplete",
    (
        "ishikawa.persistence",
        "PersistenceContractError",
        "deterministic relationships cannot carry override provenance",
    ): "persistence_deterministic_relationship_override_present",
    (
        "ishikawa.persistence",
        "PersistenceContractError",
        "persisted relationship type differs from the registry",
    ): "persistence_relationship_type_mismatch",
    (
        "ishikawa.persistence",
        "PersistenceContractError",
        "relationship source artifact is not part of this write",
    ): "persistence_relationship_source_artifact_absent",
    (
        "ishikawa.persistence",
        "PersistenceContractError",
        "relationship evidence citation is not part of this write",
    ): "persistence_relationship_evidence_citation_absent",
    (
        "ishikawa.persistence",
        "PersistenceContractError",
        "relationship source structural unit is not part of this write",
    ): "persistence_relationship_structural_unit_absent",
    (
        "ishikawa.persistence",
        "PersistenceContractError",
        "relationship source document is not in the catalog",
    ): "persistence_relationship_source_document_absent",
    (
        "ishikawa.persistence",
        "PersistenceContractError",
        "relationship target document is not in the catalog",
    ): "persistence_relationship_target_document_absent",
    (
        "ishikawa.persistence",
        "PersistenceContractError",
        "planned retirement is no longer active",
    ): "persistence_planned_retirement_inactive",
    (
        "ishikawa.persistence",
        "PersistenceContractError",
        "live state changed after validation planning",
    ): "persistence_live_state_changed",
    (
        "ishikawa.persistence",
        "PersistenceContractError",
        "plan identities do not match the supplied configuration",
    ): "persistence_plan_identity_mismatch",
    (
        "ishikawa.persistence",
        "PersistenceContractError",
        "rejected, blocked, or failed plans cannot mutate PostgreSQL",
    ): "persistence_plan_not_publishable",
    (
        "ishikawa.persistence",
        "PersistenceContractError",
        "prepared document keys must be unique",
    ): "persistence_prepared_document_key_duplicate",
    (
        "ishikawa.persistence",
        "PersistenceContractError",
        "prepared documents do not match planned changed documents",
    ): "persistence_prepared_document_set_mismatch",
    (
        "ishikawa.persistence",
        "PersistenceContractError",
        "prepared document identity does not match its plan",
    ): "persistence_prepared_document_identity_mismatch",
    (
        "ishikawa.persistence",
        "PersistenceContractError",
        "one ingestion batch must use one embedding space",
    ): "persistence_embedding_space_not_unique",
    (
        "ishikawa.persistence",
        "PersistenceContractError",
        "active embedding space differs from the prepared artifacts",
    ): "persistence_active_embedding_space_mismatch",
    (
        "ishikawa.persistence",
        "PersistenceContractError",
        "quarantined plan has no quarantined entry",
    ): "persistence_quarantined_entry_absent",
}
_STABLE_REASON = re.compile(r"[a-z][a-z0-9_]{0,127}")
_STABLE_POSTGRESQL_FAILURES = {
    "08001": "postgresql_connection_establishment_failure",
    "08003": "postgresql_connection_absent",
    "08006": "postgresql_connection_failure",
    "23502": "postgresql_not_null_violation",
    "23503": "postgresql_foreign_key_violation",
    "23505": "postgresql_unique_violation",
    "23514": "postgresql_check_violation",
    "40001": "postgresql_serialization_failure",
    "40P01": "postgresql_deadlock_detected",
    "42501": "postgresql_insufficient_privilege",
    "42703": "postgresql_undefined_column",
    "42P01": "postgresql_undefined_table",
    "53300": "postgresql_too_many_connections",
    "57P01": "postgresql_admin_shutdown",
}


def _safe_runtime_reason(error: Exception) -> str:
    """Expose only allowlisted exception classes carrying stable reason codes."""

    message_reason = _STABLE_RUNTIME_MESSAGES.get(
        (error.__class__.__module__, error.__class__.__name__, str(error))
    )
    if message_reason is not None:
        return message_reason
    sqlstate = getattr(error, "sqlstate", None)
    if isinstance(sqlstate, str) and sqlstate in _STABLE_POSTGRESQL_FAILURES:
        return _STABLE_POSTGRESQL_FAILURES[sqlstate]
    prefix = _STABLE_RUNTIME_FAILURES.get(
        (error.__class__.__module__, error.__class__.__name__)
    )
    reason = str(error)
    if prefix is not None and _STABLE_REASON.fullmatch(reason) is not None:
        return f"{prefix}_{reason}"
    return "runtime_failure"


class _Parser(argparse.ArgumentParser):
    def error(self, _message: str) -> None:
        raise IngestionCommandContractError("arguments_invalid")


@dataclass(frozen=True, slots=True)
class IngestionCommandPorts:
    """Deployment-owned dependencies supplied to the portable command."""

    connection_factory: Callable[[], Any]
    producer: PreparedDocumentProducer | None
    writer: IncrementalWriter = write_incremental_plan
    relationship_registry: RelationshipRegistry | None = None

    def __post_init__(self) -> None:
        if not callable(self.connection_factory) or not callable(self.writer):
            raise IngestionCommandContractError("dependency_port_invalid")
        if self.producer is not None and not callable(self.producer):
            raise IngestionCommandContractError("dependency_port_invalid")
        if (
            self.relationship_registry is not None
            and not isinstance(self.relationship_registry, RelationshipRegistry)
        ):
            raise IngestionCommandContractError("dependency_port_invalid")


@dataclass(frozen=True, slots=True)
class _Arguments:
    paths: OperatorIngestionPaths
    validate_only: bool


def _parser() -> _Parser:
    parser = _Parser(add_help=False, allow_abbrev=False, prog="ishikawa-ingest")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--validate-only", action="store_true")
    mode.add_argument("--publish", action="store_true")
    parser.add_argument("--class-registry", required=True)
    parser.add_argument("--document-catalog", required=True)
    parser.add_argument("--ingestion-manifest", required=True)
    parser.add_argument("--source-root", required=True)
    parser.add_argument("--report-root", required=True)
    return parser


def _absolute_path(value: str, label: str, *, kind: str) -> Path:
    path = Path(value)
    if not path.is_absolute() or path.is_symlink():
        raise IngestionCommandContractError(f"{label}_unsafe")
    if kind == "file" and not path.is_file():
        raise IngestionCommandContractError(f"{label}_unsafe")
    if kind == "directory" and not path.is_dir():
        raise IngestionCommandContractError(f"{label}_unsafe")
    if kind == "report":
        parent = path.parent
        if path.exists() and not path.is_dir():
            raise IngestionCommandContractError(f"{label}_unsafe")
        if not parent.is_dir() or parent.is_symlink():
            raise IngestionCommandContractError(f"{label}_unsafe")
    return path


def parse_ingestion_arguments(values: Sequence[str]) -> _Arguments:
    """Parse only paths and mode; secrets and implementation controls are excluded."""

    if not isinstance(values, Sequence) or isinstance(values, (str, bytes)):
        raise IngestionCommandContractError("arguments_invalid")
    try:
        parsed = _parser().parse_args(list(values))
    except (argparse.ArgumentError, TypeError) as error:
        raise IngestionCommandContractError("arguments_invalid") from error
    paths = OperatorIngestionPaths(
        _absolute_path(parsed.class_registry, "class_registry", kind="file"),
        _absolute_path(parsed.document_catalog, "document_catalog", kind="file"),
        _absolute_path(parsed.ingestion_manifest, "ingestion_manifest", kind="file"),
        _absolute_path(parsed.source_root, "source_root", kind="directory"),
        _absolute_path(parsed.report_root, "report_root", kind="report"),
    )
    return _Arguments(paths, bool(parsed.validate_only))


def execute_ingestion_command(
    values: Sequence[str],
    *,
    ports: IngestionCommandPorts,
    output: TextIO,
) -> int:
    """Execute one command with bounded output and guaranteed connection cleanup."""

    connection = None
    try:
        arguments = parse_ingestion_arguments(values)
        if not arguments.validate_only and ports.producer is None:
            raise IngestionCommandContractError("producer_required_for_publish")
        connection = ports.connection_factory()
        if connection is None or not callable(getattr(connection, "close", None)):
            raise IngestionCommandContractError("database_connection_invalid")
        result = run_operator_ingestion(
            paths=arguments.paths,
            method_profile_id=METHOD_PROFILE_ID,
            connection=connection,
            validate_only=arguments.validate_only,
            producer=ports.producer,
            writer=ports.writer,
            relationship_registry=ports.relationship_registry,
        )
        output.write(result.terminal_summary + "\n")
        output.write(
            "ishikawa_ingestion="
            + ("pass" if result.exit_code == 0 else "blocked")
            + f";exit_code={result.exit_code}\n"
        )
        return result.exit_code
    except IngestionCommandContractError as error:
        output.write(f"ishikawa_ingestion=blocked;reason={error}\n")
        return 2
    except Exception as error:
        output.write(f"ishikawa_ingestion=blocked;reason={_safe_runtime_reason(error)}\n")
        return 1
    finally:
        if connection is not None:
            try:
                connection.close()
            except Exception:
                pass
