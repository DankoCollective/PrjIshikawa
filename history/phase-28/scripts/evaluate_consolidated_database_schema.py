#!/usr/bin/env python3
"""Validate the canonical fresh-install Ishikawa database schema.

Role:
    This local build helper proves that one final schema directly represents
    the accepted schema-version-4 target without carrying development
    mutation steps into the deployment package.

Mental model:
    Parse stable SQL declarations, reject historical mutation operations,
    require the exact final object inventory and frozen contract markers, and
    emit a deterministic content-free receipt. SQL execution is intentionally
    reserved for the next disposable-database qualification gate.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any


EXPECTED_TABLES = frozenset(
    {
        "rag.active_document_versions",
        "rag.chunk_embeddings",
        "rag.chunk_structural_units",
        "rag.chunks",
        "rag.citation_anchors",
        "rag.document_artifact_sets",
        "rag.document_classes",
        "rag.document_versions",
        "rag.documents",
        "rag.embedding_spaces",
        "rag.ingestion_runs",
        "rag.publication_batch_changes",
        "rag.publication_batches",
        "rag.relationship_types",
        "rag.relationships",
        "rag.schema_migrations",
        "rag.structural_units",
        "rag_private.artifact_manifests",
        "rag_private.ingestion_stages",
        "rag_private.quarantine_records",
    }
)
EXPECTED_VIEWS = frozenset(
    {
        "rag_search.active_chunks",
        "rag_search.active_citations",
        "rag_search.active_documents",
        "rag_search.active_embeddings",
        "rag_search.active_relationships",
    }
)
EXPECTED_INDEXES = frozenset(
    {
        "artifact_manifests_document_idx",
        "artifact_sets_document_version_idx",
        "chunks_artifact_set_idx",
        "chunks_lexical_gin_idx",
        "citations_chunk_idx",
        "document_versions_document_idx",
        "embedding_spaces_one_active_idx",
        "embeddings_space_chunk_idx",
        "ingestion_stages_run_idx",
        "publication_changes_document_idx",
        "quarantine_run_idx",
        "relationships_source_idx",
        "relationships_target_idx",
        "structural_units_parent_idx",
    }
)
FINAL_CONSTRAINTS = frozenset(
    {
        "chunks_total_embedding_token_count_v2_check",
        "document_classes_registry_version_check",
        "document_artifact_sets_run_provenance_fkey",
        "document_artifact_sets_semantic_inputs_key",
        "documents_catalog_version_check",
        "ingestion_runs_artifact_provenance_key",
        "quarantine_records_document_version_document_fkey",
        "quarantine_records_document_version_subject_check",
        "quarantine_records_resolution_v1_check",
        "quarantine_records_subject_check",
        "relationships_override_audit_check",
    }
)
TABLE_PATTERN = re.compile(r"^CREATE TABLE ([a-z_]+\.[a-z_]+) \($", re.MULTILINE)
VIEW_PATTERN = re.compile(
    r"^CREATE VIEW ([a-z_]+\.[a-z_]+) WITH \(security_barrier = true\) AS$",
    re.MULTILINE,
)
INDEX_PATTERN = re.compile(
    r"^CREATE (?:UNIQUE )?INDEX ([a-z_][a-z0-9_]*)$", re.MULTILINE
)
CONSTRAINT_PATTERN = re.compile(r"\bCONSTRAINT ([a-z_][a-z0-9_]*)\b")
FORBIDDEN_MUTATION_PATTERN = re.compile(
    r"^(?:ALTER|DROP|TRUNCATE)\s|^CREATE OR REPLACE\s|^DO\s+\$",
    re.IGNORECASE | re.MULTILINE,
)
HISTORICAL_IDENTITY_PATTERN = re.compile(
    r"000[1-4]_(?:initial|align|separate|preserve)", re.IGNORECASE
)


class SchemaError(ValueError):
    """A content-free canonical-schema validation finding."""


def parse_arguments() -> argparse.Namespace:
    """Return the exact local schema-evaluation inputs."""

    parser = argparse.ArgumentParser(
        description="Validate one consolidated Ishikawa fresh-install schema."
    )
    parser.add_argument("--schema", required=True)
    parser.add_argument("--output", required=True)
    return parser.parse_args()


def require_regular_file(path: Path, label: str) -> Path:
    """Resolve a required absolute non-symlink file or fail closed."""

    if not path.is_absolute() or path.is_symlink() or not path.is_file():
        raise SchemaError(f"{label}_unsafe")
    return path.resolve(strict=True)


def read_text(path: Path) -> str:
    """Read strict UTF-8 SQL and enforce common text hygiene."""

    try:
        content = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise SchemaError("schema_encoding_invalid") from error
    if "\x00" in content or "\r" in content or "\t" in content:
        raise SchemaError("schema_text_format_invalid")
    if any(line != line.rstrip() for line in content.splitlines()):
        raise SchemaError("schema_trailing_whitespace_found")
    if not content.endswith("\n"):
        raise SchemaError("schema_final_newline_missing")
    return content


def require_ordered(content: str, terms: tuple[str, ...], label: str) -> None:
    """Require stable contract terms to occur once in their final order."""

    cursor = 0
    for term in terms:
        position = content.find(term, cursor)
        if position < 0:
            raise SchemaError(f"{label}_invalid")
        cursor = position + len(term)


def validate_schema(content: str) -> dict[str, Any]:
    """Validate object inventory, final-state posture, and frozen contracts."""

    if content.count("BEGIN;") != 1 or content.count("COMMIT;") != 1:
        raise SchemaError("transaction_boundary_invalid")
    if FORBIDDEN_MUTATION_PATTERN.search(content):
        raise SchemaError("historical_mutation_operation_found")
    if HISTORICAL_IDENTITY_PATTERN.search(content):
        raise SchemaError("historical_schema_identity_found")
    if content.count("INSERT INTO rag.schema_migrations") != 1:
        raise SchemaError("baseline_identity_count_invalid")
    for marker in (
        "'ishikawa_consolidated_schema_v4'",
        ":'schema_sha256'",
        "CREATE DOMAIN rag.sha256_hex AS text",
        "embedding vector(768) NOT NULL",
        "maximum_input_tokens integer NOT NULL CHECK (maximum_input_tokens = 2048)",
        "GRANT SELECT ON ALL TABLES IN SCHEMA rag_search TO :\"retrieval_role\";",
        "REVOKE INSERT, UPDATE, DELETE ON rag.schema_migrations FROM :\"ingest_role\";",
    ):
        if marker not in content:
            raise SchemaError("final_contract_marker_missing")

    tables = frozenset(TABLE_PATTERN.findall(content))
    views = frozenset(VIEW_PATTERN.findall(content))
    indexes = frozenset(INDEX_PATTERN.findall(content))
    constraints = frozenset(CONSTRAINT_PATTERN.findall(content))
    if tables != EXPECTED_TABLES:
        raise SchemaError("table_inventory_invalid")
    if views != EXPECTED_VIEWS:
        raise SchemaError("view_inventory_invalid")
    if indexes != EXPECTED_INDEXES:
        raise SchemaError("index_inventory_invalid")
    if not FINAL_CONSTRAINTS.issubset(constraints):
        raise SchemaError("final_constraint_inventory_invalid")

    require_ordered(
        content,
        (
            "CREATE TABLE rag.ingestion_runs (",
            "finished_at timestamptz,",
            "class_registry_digest rag.sha256_hex NOT NULL,",
            "document_catalog_digest rag.sha256_hex NOT NULL,",
            "CREATE TABLE rag.publication_batches (",
        ),
        "ingestion_run_column_order",
    )
    require_ordered(
        content,
        (
            "CREATE TABLE rag.document_artifact_sets (",
            "created_at timestamptz NOT NULL DEFAULT clock_timestamp(),",
            "assigned_class_id text NOT NULL REFERENCES rag.document_classes(class_id),",
            "manifest_entry_identity rag.sha256_hex NOT NULL,",
            "CREATE TABLE rag.structural_units (",
        ),
        "artifact_set_column_order",
    )
    require_ordered(
        content,
        (
            "CREATE TABLE rag.chunks (",
            "created_at timestamptz NOT NULL DEFAULT clock_timestamp(),",
            "special_token_count integer NOT NULL CHECK (special_token_count >= 0),",
            "CONSTRAINT chunks_total_embedding_token_count_v2_check",
            "CREATE TABLE rag.chunk_structural_units (",
        ),
        "chunk_column_order",
    )
    require_ordered(
        content,
        (
            "CREATE TABLE rag.relationships (",
            "created_at timestamptz NOT NULL DEFAULT clock_timestamp(),",
            "override_audit_identity rag.sha256_hex,",
            "override_reason_code text,",
            "CONSTRAINT relationships_override_audit_check",
            "CREATE TABLE rag.publication_batch_changes (",
        ),
        "relationship_column_order",
    )
    require_ordered(
        content,
        (
            "CREATE TABLE rag_private.quarantine_records (",
            "resolved_at timestamptz,",
            "manifest_entry_identity rag.sha256_hex,",
            "resolved_by_run_id rag.sha256_hex",
            "resolution_code text,",
            "CONSTRAINT quarantine_records_document_version_document_fkey",
            "CREATE INDEX document_versions_document_idx",
        ),
        "quarantine_column_order",
    )
    return {
        "baseline_rows": 1,
        "historical_mutation_operations": 0,
        "index_count": len(indexes),
        "required_named_constraint_count": len(FINAL_CONSTRAINTS),
        "schema_version": 4,
        "sql_execution_performed": False,
        "table_count": len(tables),
        "view_count": len(views),
    }


def write_exclusive(path: Path, payload: dict[str, Any]) -> None:
    """Write one deterministic JSON receipt without replacing evidence."""

    if not path.is_absolute() or path.exists() or path.is_symlink() or not path.parent.is_dir():
        raise SchemaError("output_path_unsafe")
    encoded = json.dumps(
        payload,
        ensure_ascii=True,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8") + b"\n"
    with path.open("xb") as output_stream:
        output_stream.write(encoded)


def main() -> int:
    """Validate the schema and emit its content-free final-state receipt."""

    arguments = parse_arguments()
    try:
        schema_path = require_regular_file(Path(arguments.schema), "schema")
        content = read_text(schema_path)
        result = validate_schema(content)
        result.update(
            {
                "canonical_final_schema": True,
                "purpose": "consolidated_database_schema_validation",
                "receipt_schema_version": 1,
                "schema_sha256": hashlib.sha256(content.encode("utf-8")).hexdigest(),
            }
        )
        write_exclusive(Path(arguments.output), result)
    except SchemaError as error:
        print(f"consolidated_schema_validation=blocked;reason={error}", file=sys.stderr)
        return 1
    print(
        "consolidated_schema_validation=pass;"
        f"tables={result['table_count']};indexes={result['index_count']};"
        f"views={result['view_count']};schema_version={result['schema_version']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
