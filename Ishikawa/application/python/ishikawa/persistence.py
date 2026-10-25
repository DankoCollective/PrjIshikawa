"""Atomic incremental PostgreSQL writer for the aligned Ishikawa schema.

The module uses the small DB-API surface exposed by Psycopg 3 but imports no
driver.  Runtime connection creation and credential injection belong to the
deployment entry point; tests can therefore exercise this writer without a
database package or secret.
"""

from __future__ import annotations

import json
from collections.abc import Mapping, Sequence
from typing import Any

from .canonical import domain_digest
from .models import (
    ClassRegistry,
    DocumentCatalog,
    IngestionManifest,
    PublishedDocumentState,
    ValidationPlan,
)
from .persistence_models import PreparedDocument, WriteResult
from .relationships import (
    RelationshipObservation,
    RelationshipRegistry,
)

CONSOLIDATED_SCHEMA_V5_SHA256 = (
    "3b55d00880e6e09e401e282b7f62314fb635c6a859c23ad3e87c58aa23237e8b"
)


class PersistenceContractError(RuntimeError):
    """Raised before commit when live state does not match the validated plan."""


def _json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, allow_nan=False, sort_keys=True, separators=(",", ":"))


def _one(connection: Any, sql: str, parameters: Sequence[Any] = ()) -> Any:
    row = connection.execute(sql, parameters).fetchone()
    if row is None:
        raise PersistenceContractError("required PostgreSQL result is absent")
    return row[0]


def _document_id(document_key: str) -> str:
    return domain_digest("ishikawa.document.v1", {"document_key": document_key})


def _document_version_id(document_id: str, source_digest: str) -> str:
    return domain_digest(
        "ishikawa.document-version.v1",
        {"document_id": document_id, "source_digest": source_digest},
    )


def _artifact_set_id(
    document_version_id: str, method_profile_id: str, class_id: str
) -> str:
    return domain_digest(
        "ishikawa.document-artifact-set.v1",
        {
            "document_version_id": document_version_id,
            "method_profile_id": method_profile_id,
            "class_id": class_id,
        },
    )


def _run_id(plan: ValidationPlan) -> str:
    return domain_digest(
        "ishikawa.ingestion-run.v1",
        {"validation_id": plan.validation_id, "database_schema_version": 5},
    )


def _batch_id(run_id: str) -> str:
    return domain_digest("ishikawa.publication-batch.v1", {"ingestion_run_id": run_id})


def _verify_schema(connection: Any) -> None:
    contract = _one(
        connection,
        """/* ishikawa.verify-schema */
        SELECT string_agg(migration_id || '|' || migration_sha256 || '|' || schema_version,
                          ';' ORDER BY schema_version)
        FROM rag.schema_migrations
        """,
    )
    expected = f"ishikawa_consolidated_schema_v5|{CONSOLIDATED_SCHEMA_V5_SHA256}|5"
    if contract != expected:
        raise PersistenceContractError(
            "PostgreSQL consolidated contract does not match schema version 5"
        )


def load_published_state(connection: Any) -> dict[str, PublishedDocumentState]:
    """Read only the active retrieval projection needed by the planner."""

    rows = connection.execute(
        """/* ishikawa.load-published-state */
        SELECT document_key, source_digest, class_id, method_profile_id,
               document_id, document_version_id, artifact_set_id
        FROM rag_search.active_documents
        ORDER BY document_key
        """
    ).fetchall()
    return {
        row[0]: PublishedDocumentState(
            document_key=row[0],
            source_digest=row[1],
            class_id=row[2],
            method_profile_id=row[3],
            document_id=row[4],
            document_version_id=row[5],
            artifact_set_id=row[6],
        )
        for row in rows
    }


def load_catalog_keys(connection: Any) -> set[str]:
    rows = connection.execute(
        """/* ishikawa.load-catalog-keys */
        SELECT document_key FROM rag.documents ORDER BY document_key
        """
    ).fetchall()
    return {row[0] for row in rows}


def _sync_reference_data(
    connection: Any, registry: ClassRegistry, catalog: DocumentCatalog
) -> None:
    persisted_keys = load_catalog_keys(connection)
    configured_keys = set(catalog.by_key())
    if persisted_keys - configured_keys:
        raise PersistenceContractError("a persisted document key is missing from the catalog")

    for item in registry.classes:
        connection.execute(
            """/* ishikawa.upsert-class */
            INSERT INTO rag.document_classes
              (class_id, display_name, registry_digest, status)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (class_id) DO UPDATE SET
              display_name = EXCLUDED.display_name,
              registry_digest = EXCLUDED.registry_digest,
              status = EXCLUDED.status
            """,
            (item.class_id, item.display_name, registry.digest, item.status),
        )
    for item in catalog.documents:
        connection.execute(
            """/* ishikawa.upsert-document */
            INSERT INTO rag.documents
              (document_id, document_key, display_name, catalog_digest, status)
            VALUES (%s, %s, %s, %s, %s)
            ON CONFLICT (document_key) DO UPDATE SET
              display_name = EXCLUDED.display_name,
              catalog_digest = EXCLUDED.catalog_digest,
              status = EXCLUDED.status,
              updated_at = clock_timestamp()
            WHERE rag.documents.document_id = EXCLUDED.document_id
            """,
            (_document_id(item.document_key), item.document_key, item.display_name, catalog.digest, item.status),
        )


def _validate_relationship_inputs(
    registry: RelationshipRegistry | None,
    observations: Sequence[RelationshipObservation],
) -> tuple[Any, ...]:
    if registry is None:
        if observations:
            raise PersistenceContractError("relationship observations require a relationship registry")
        return ()
    unresolved = [item for item in observations if item.requires_quarantine]
    if unresolved:
        raise PersistenceContractError("unresolved relationship observations cannot be published")
    edges = tuple(item.edge for item in observations if item.edge is not None)
    if len({edge.relationship_id for edge in edges}) != len(edges):
        raise PersistenceContractError("relationship edge identities must be unique")
    definitions = registry.by_id()
    for edge in edges:
        definition = definitions.get(edge.relationship_type)
        if definition is None or (
            definition.source_kind,
            definition.target_kind,
        ) != (edge.source_kind, edge.target_kind):
            raise PersistenceContractError("relationship edge conflicts with its registry definition")
        if edge.relationship_definition_version != registry.digest:
            raise PersistenceContractError("relationship edge registry identity mismatch")
        has_audit = edge.override_audit_identity is not None and edge.override_reason_code is not None
        if (edge.detection_method == "operator_override") != has_audit:
            raise PersistenceContractError("relationship override audit provenance is incomplete")
        if edge.detection_method == "deterministic" and (
            edge.override_audit_identity is not None or edge.override_reason_code is not None
        ):
            raise PersistenceContractError("deterministic relationships cannot carry override provenance")
    return edges


def _sync_relationship_types(
    connection: Any, registry: RelationshipRegistry
) -> None:
    for definition in registry.relationship_types:
        connection.execute(
            """/* ishikawa.upsert-relationship-type */
            INSERT INTO rag.relationship_types
              (relationship_type, source_kind, target_kind, inverse_display_name,
               influences_retrieval, registry_version, status)
            VALUES (%s,%s,%s,%s,%s,%s,%s)
            ON CONFLICT (relationship_type) DO UPDATE SET
              inverse_display_name=EXCLUDED.inverse_display_name,
              influences_retrieval=EXCLUDED.influences_retrieval,
              registry_version=EXCLUDED.registry_version,
              status=EXCLUDED.status
            WHERE rag.relationship_types.source_kind=EXCLUDED.source_kind
              AND rag.relationship_types.target_kind=EXCLUDED.target_kind
            """,
            (
                definition.relationship_type,
                definition.source_kind,
                definition.target_kind,
                definition.inverse_display_name,
                definition.influences_retrieval,
                registry.digest,
                definition.status,
            ),
        )
        persisted = connection.execute(
            """/* ishikawa.verify-relationship-type */
            SELECT source_kind, target_kind, registry_version
            FROM rag.relationship_types
            WHERE relationship_type=%s
            """,
            (definition.relationship_type,),
        ).fetchone()
        if persisted != (definition.source_kind, definition.target_kind, registry.digest):
            raise PersistenceContractError("persisted relationship type differs from the registry")


def _write_relationship_edges(
    connection: Any,
    edges: Sequence[Any],
    *,
    written_artifacts: set[str],
    written_units: set[str],
    written_citations: set[str],
    catalog_document_ids: set[str],
) -> None:
    for edge in edges:
        if edge.source_artifact_set_identity not in written_artifacts:
            raise PersistenceContractError("relationship source artifact is not part of this write")
        if edge.evidence_citation_identity not in written_citations:
            raise PersistenceContractError("relationship evidence citation is not part of this write")
        if edge.source_kind == "structural_unit" and edge.source_identity not in written_units:
            raise PersistenceContractError("relationship source structural unit is not part of this write")
        if edge.source_kind == "document" and edge.source_identity not in catalog_document_ids:
            raise PersistenceContractError("relationship source document is not in the catalog")
        if edge.target_kind == "document" and edge.target_identity not in catalog_document_ids:
            raise PersistenceContractError("relationship target document is not in the catalog")
        connection.execute(
            """/* ishikawa.insert-relationship */
            INSERT INTO rag.relationships
              (relationship_id, artifact_set_id, relationship_type,
               source_kind, source_identity, target_kind, target_identity,
               evidence_citation_id, detection_method, review_status,
               relationship_definition_version, override_audit_identity,
               override_reason_code)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """,
            (
                edge.relationship_id,
                edge.source_artifact_set_identity,
                edge.relationship_type,
                edge.source_kind,
                edge.source_identity,
                edge.target_kind,
                edge.target_identity,
                edge.evidence_citation_identity,
                edge.detection_method,
                edge.review_status,
                edge.relationship_definition_version,
                edge.override_audit_identity,
                edge.override_reason_code,
            ),
        )


def _expected_action(
    prior: PublishedDocumentState | None,
    source_digest: str,
    class_id: str,
    method_profile_id: str,
) -> str:
    if prior is None:
        return "add"
    if prior.source_digest != source_digest:
        return "revise"
    if prior.class_id != class_id or prior.method_profile_id != method_profile_id:
        return "reprocess"
    return "reuse"


def _verify_plan_against_live_state(
    plan: ValidationPlan,
    manifest: IngestionManifest,
    live: Mapping[str, PublishedDocumentState],
) -> None:
    documents = {item.document_key: item for item in manifest.documents}
    for entry in plan.entries:
        if entry.outcome != "PASS":
            continue
        if entry.action == "retire":
            if entry.document_key not in live:
                raise PersistenceContractError("planned retirement is no longer active")
            continue
        item = documents[entry.document_key]
        expected = _expected_action(
            live.get(entry.document_key),
            entry.source_digest or "",
            item.class_id,
            plan.method_profile_id,
        )
        if expected != entry.action:
            raise PersistenceContractError("live state changed after validation planning")


def _validate_inputs(
    registry: ClassRegistry,
    catalog: DocumentCatalog,
    manifest: IngestionManifest,
    plan: ValidationPlan,
    prepared_documents: Sequence[PreparedDocument],
) -> dict[str, PreparedDocument]:
    if (
        plan.registry_digest != registry.digest
        or plan.catalog_digest != catalog.digest
        or plan.manifest_digest != manifest.digest
    ):
        raise PersistenceContractError("plan identities do not match the supplied configuration")
    if plan.overall_outcome not in {"PASS", "QUARANTINED"}:
        raise PersistenceContractError("rejected, blocked, or failed plans cannot mutate PostgreSQL")

    prepared = {item.document_key: item for item in prepared_documents}
    if len(prepared) != len(prepared_documents):
        raise PersistenceContractError("prepared document keys must be unique")
    required = {
        entry.document_key
        for entry in plan.entries
        if entry.outcome == "PASS" and entry.action in {"add", "revise", "reprocess"}
    }
    if plan.overall_outcome == "QUARANTINED":
        required = set()
    if set(prepared) != required:
        raise PersistenceContractError("prepared documents do not match planned changed documents")

    manifest_documents = {item.document_key: item for item in manifest.documents}
    for key, item in prepared.items():
        manifest_item = manifest_documents[key]
        entry = next(entry for entry in plan.entries if entry.document_key == key)
        if item.class_id != manifest_item.class_id or item.source_digest != entry.source_digest:
            raise PersistenceContractError("prepared document identity does not match its plan")
    spaces = {item.embedding_space.identity for item in prepared.values()}
    if len(spaces) > 1:
        raise PersistenceContractError("one ingestion batch must use one embedding space")
    return prepared


def _insert_run(
    connection: Any,
    run_id: str,
    plan: ValidationPlan,
    state: str,
    outcome_code: str | None,
    *,
    finished: bool,
) -> None:
    connection.execute(
        """/* ishikawa.insert-run */
        INSERT INTO rag.ingestion_runs
          (ingestion_run_id, ingestion_manifest_digest, schema_version,
           method_profile_id, state, outcome_code, started_at, finished_at,
           class_registry_digest, document_catalog_digest)
        VALUES (%s, %s, 1, %s, %s, %s, statement_timestamp(),
                CASE WHEN %s THEN statement_timestamp() ELSE NULL END, %s, %s)
        """,
        (
            run_id,
            plan.manifest_digest,
            plan.method_profile_id,
            state,
            outcome_code,
            finished,
            plan.registry_digest,
            plan.catalog_digest,
        ),
    )


def _record_quarantine(
    connection: Any,
    run_id: str,
    catalog: DocumentCatalog,
    plan: ValidationPlan,
) -> int:
    catalog_keys = catalog.by_key()
    count = 0
    for entry in plan.entries:
        if entry.outcome != "QUARANTINED":
            continue
        document_id = _document_id(entry.document_key) if entry.document_key in catalog_keys else None
        quarantine_id = domain_digest(
            "ishikawa.quarantine.v1",
            {
                "ingestion_run_id": run_id,
                "manifest_entry_identity": entry.manifest_entry_identity,
                "reason_code": entry.reason_code,
            },
        )
        connection.execute(
            """/* ishikawa.insert-quarantine */
            INSERT INTO rag_private.quarantine_records
              (quarantine_id, ingestion_run_id, document_id, stage_name,
               reason_code, manifest_entry_identity)
            VALUES (%s, %s, %s, 'validate', %s, %s)
            """,
            (
                quarantine_id,
                run_id,
                document_id,
                entry.reason_code,
                entry.manifest_entry_identity,
            ),
        )
        count += 1
    return count


def _ensure_embedding_space(connection: Any, document: PreparedDocument) -> None:
    space = document.embedding_space
    active_identity = _one(
        connection,
        """/* ishikawa.active-embedding-space */
        SELECT COALESCE((SELECT embedding_space_id FROM rag.embedding_spaces
                         WHERE status = 'active'), '')
        """,
    )
    if active_identity not in {"", space.identity}:
        raise PersistenceContractError("active embedding space differs from the prepared artifacts")
    connection.execute(
        """/* ishikawa.upsert-embedding-space */
        INSERT INTO rag.embedding_spaces
          (embedding_space_id, model_name, model_revision, model_digest,
           tokenizer_digest, pooling_method, document_prefix, query_prefix,
           dimension, maximum_input_tokens, vector_transform, distance_metric, status)
        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,'active')
        ON CONFLICT (embedding_space_id) DO UPDATE SET status = 'active'
        """,
        (
            space.identity,
            space.model_name,
            space.model_revision,
            space.model_digest,
            space.tokenizer_digest,
            space.pooling_method,
            space.document_prefix,
            space.query_prefix,
            space.dimension,
            space.maximum_input_tokens,
            space.vector_transform,
            space.distance_metric,
        ),
    )


def _write_document_artifacts(
    connection: Any,
    run_id: str,
    plan: ValidationPlan,
    manifest_entry_identity: str,
    document: PreparedDocument,
) -> tuple[str, str, str, tuple[str, ...], tuple[str, ...]]:
    document_id = _document_id(document.document_key)
    version_id = _document_version_id(document_id, document.source_digest)
    artifact_id = _artifact_set_id(version_id, plan.method_profile_id, document.class_id)
    connection.execute(
        """/* ishikawa.insert-document-version */
        INSERT INTO rag.document_versions
          (document_version_id, document_id, source_digest, source_format,
           language, page_count, created_by_run_id)
        VALUES (%s,%s,%s,'application/pdf',%s,%s,%s)
        ON CONFLICT (document_id, source_digest) DO NOTHING
        """,
        (version_id, document_id, document.source_digest, document.language, document.page_count, run_id),
    )
    connection.execute(
        """/* ishikawa.insert-artifact-set */
        INSERT INTO rag.document_artifact_sets
          (artifact_set_id, document_version_id, document_id, method_profile_id,
           ingestion_run_id, processing_profiles, state, assigned_class_id,
           class_registry_digest, ingestion_manifest_digest, manifest_entry_identity)
        VALUES (%s,%s,%s,%s,%s,%s::jsonb,'candidate',%s,%s,%s,%s)
        """,
        (
            artifact_id,
            version_id,
            document_id,
            plan.method_profile_id,
            run_id,
            _json(list(document.processing_profiles)),
            document.class_id,
            plan.registry_digest,
            plan.manifest_digest,
            manifest_entry_identity,
        ),
    )

    unit_ids: dict[int, str] = {}
    for unit in document.structural_units:
        normalized_digest = domain_digest("ishikawa.normalized-text.v1", unit.normalized_text)
        unit_id = domain_digest(
            "ishikawa.structural-unit.v1",
            {"artifact_set_id": artifact_id, "ordinal": unit.ordinal, "digest": normalized_digest},
        )
        unit_ids[unit.ordinal] = unit_id
        connection.execute(
            """/* ishikawa.insert-structural-unit */
            INSERT INTO rag.structural_units
              (structural_unit_id, artifact_set_id, parent_unit_id,
               structural_kind, ordinal, page_start, page_end, structural_path,
               source_anchor, normalized_text, normalized_digest)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s::jsonb,%s::jsonb,%s,%s)
            """,
            (
                unit_id,
                artifact_id,
                unit_ids.get(unit.parent_ordinal),
                unit.structural_kind,
                unit.ordinal,
                unit.page_start,
                unit.page_end,
                _json(list(unit.structural_path)),
                _json(unit.source_anchor),
                unit.normalized_text,
                normalized_digest,
            ),
        )

    database_chunk_ids: dict[int, str] = {}
    for chunk in document.chunks:
        retrieval_digest = domain_digest("ishikawa.retrieval-text.v1", chunk.retrieval_text)
        database_chunk_ids[chunk.ordinal] = domain_digest(
            "ishikawa.chunk.v1",
            {"artifact_set_id": artifact_id, "ordinal": chunk.ordinal, "digest": retrieval_digest},
        )
    chunk_ids: list[str] = []
    citation_ids: list[str] = []
    for chunk in document.chunks:
        retrieval_digest = domain_digest("ishikawa.retrieval-text.v1", chunk.retrieval_text)
        chunk_id = database_chunk_ids[chunk.ordinal]
        chunk_ids.append(chunk_id)
        contextual_fields = dict(chunk.contextual_fields)
        contextual_fields["authoritative_chunk_ids"] = [
            database_chunk_ids[ordinal]
            for ordinal in chunk.authoritative_component_ordinals
        ] or [chunk_id]
        connection.execute(
            """/* ishikawa.insert-chunk */
            INSERT INTO rag.chunks
              (chunk_id, artifact_set_id, method_profile_id, projection_kind,
               ordinal, retrieval_text, retrieval_text_digest, contextual_fields,
               retrieval_filters, client_metadata, content_token_count,
               context_token_count, prefix_token_count, special_token_count,
               total_embedding_token_count,
               processing_profile, lexical_search_config, lexical_vector)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s::jsonb,%s::jsonb,%s::jsonb,
                    %s,%s,%s,%s,%s,%s,%s::regconfig,to_tsvector(%s::regconfig,%s))
            """,
            (
                chunk_id,
                artifact_id,
                plan.method_profile_id,
                chunk.projection_kind,
                chunk.ordinal,
                chunk.retrieval_text,
                retrieval_digest,
                _json(contextual_fields),
                _json(chunk.retrieval_filters),
                _json(chunk.client_metadata),
                chunk.content_token_count,
                chunk.context_token_count,
                chunk.prefix_token_count,
                chunk.special_token_count,
                chunk.total_embedding_token_count,
                chunk.processing_profile,
                chunk.lexical_search_config,
                chunk.lexical_search_config,
                chunk.retrieval_text,
            ),
        )
        for unit_ordinal, referenced in enumerate(chunk.structural_unit_ordinals):
            connection.execute(
                """/* ishikawa.link-chunk-structure */
                INSERT INTO rag.chunk_structural_units
                  (chunk_id, structural_unit_id, artifact_set_id, unit_ordinal)
                VALUES (%s,%s,%s,%s)
                """,
                (chunk_id, unit_ids[referenced], artifact_id, unit_ordinal),
            )
        citation_id = domain_digest(
            "ishikawa.citation.v1",
            {"chunk_id": chunk_id, "page_start": chunk.page_start, "page_end": chunk.page_end},
        )
        citation_ids.append(citation_id)
        connection.execute(
            """/* ishikawa.insert-citation */
            INSERT INTO rag.citation_anchors
              (citation_id, chunk_id, artifact_set_id, document_version_id,
               display_label, relevant_excerpt, page_start, page_end,
               structural_path, citation_anchor)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s::jsonb,%s::jsonb)
            """,
            (
                citation_id,
                chunk_id,
                artifact_id,
                version_id,
                f"{document.document_key} page {chunk.page_start}",
                chunk.relevant_excerpt,
                chunk.page_start,
                chunk.page_end,
                _json(list(chunk.structural_path)),
                _json(chunk.citation_anchor),
            ),
        )
        vector_text = "[" + ",".join(format(value, ".17g") for value in chunk.embedding) + "]"
        embedding_artifact_id = domain_digest(
            "ishikawa.chunk-embedding.v1",
            {"chunk_id": chunk_id, "embedding_space_id": document.embedding_space.identity},
        )
        connection.execute(
            """/* ishikawa.insert-embedding */
            INSERT INTO rag.chunk_embeddings
              (embedding_artifact_id, chunk_id, embedding_space_id,
               submitted_input_digest, embedding, normalized, creation_run_id)
            VALUES (%s,%s,%s,%s,%s::vector,false,%s)
            """,
            (
                embedding_artifact_id,
                chunk_id,
                document.embedding_space.identity,
                chunk.submitted_input_digest,
                vector_text,
                run_id,
            ),
        )

    validation_digest = domain_digest(
        "ishikawa.artifact-validation.v1",
        {"artifact_set_id": artifact_id, "unit_ids": list(unit_ids.values()), "chunk_ids": chunk_ids},
    )
    connection.execute(
        """/* ishikawa.validate-artifact-set */
        UPDATE rag.document_artifact_sets
        SET state='validated', validation_digest=%s
        WHERE artifact_set_id=%s AND state='candidate'
        """,
        (validation_digest, artifact_id),
    )
    return document_id, version_id, artifact_id, tuple(unit_ids.values()), tuple(citation_ids)


def write_incremental_plan(
    connection: Any,
    registry: ClassRegistry,
    catalog: DocumentCatalog,
    manifest: IngestionManifest,
    plan: ValidationPlan,
    prepared_documents: Sequence[PreparedDocument] = (),
    *,
    relationship_registry: RelationshipRegistry | None = None,
    relationship_observations: Sequence[RelationshipObservation] = (),
) -> WriteResult:
    """Persist one validated manifest as one atomic publication boundary."""

    prepared = _validate_inputs(registry, catalog, manifest, plan, prepared_documents)
    relationship_edges = _validate_relationship_inputs(
        relationship_registry, relationship_observations
    )
    run_id = _run_id(plan)
    batch_id: str | None = None
    published_count = retired_count = reused_count = quarantine_count = 0

    with connection.transaction():
        connection.execute(
            """/* ishikawa.lock-writer */
            SELECT pg_advisory_xact_lock(hashtextextended('ishikawa.incremental-writer.v1', 0))
            """
        )
        _verify_schema(connection)
        live = load_published_state(connection)
        _verify_plan_against_live_state(plan, manifest, live)
        _sync_reference_data(connection, registry, catalog)
        if relationship_registry is not None:
            _sync_relationship_types(connection, relationship_registry)

        if plan.overall_outcome == "QUARANTINED":
            _insert_run(connection, run_id, plan, "quarantined", "BATCH_QUARANTINED", finished=True)
            quarantine_count = _record_quarantine(connection, run_id, catalog, plan)
            if quarantine_count == 0:
                raise PersistenceContractError("quarantined plan has no quarantined entry")
            return WriteResult(run_id, None, "QUARANTINED", 0, 0, 0, quarantine_count)

        mutating_entries = [entry for entry in plan.entries if entry.action != "reuse"]
        if not mutating_entries:
            _insert_run(connection, run_id, plan, "skipped", "NO_CHANGES", finished=True)
            return WriteResult(run_id, None, "SKIPPED", 0, 0, len(plan.entries), 0)

        _insert_run(connection, run_id, plan, "running", None, finished=False)
        if prepared:
            _ensure_embedding_space(connection, next(iter(prepared.values())))
        batch_id = _batch_id(run_id)
        connection.execute(
            """/* ishikawa.insert-publication-batch */
            INSERT INTO rag.publication_batches
              (publication_batch_id, ingestion_run_id, state)
            VALUES (%s,%s,'candidate')
            """,
            (batch_id, run_id),
        )

        written: dict[
            str,
            tuple[str, str, str, tuple[str, ...], tuple[str, ...]],
        ] = {}
        for entry in plan.entries:
            if entry.action in {"add", "revise", "reprocess"}:
                written[entry.document_key] = _write_document_artifacts(
                    connection,
                    run_id,
                    plan,
                    entry.manifest_entry_identity,
                    prepared[entry.document_key],
                )

        if relationship_edges:
            _write_relationship_edges(
                connection,
                relationship_edges,
                written_artifacts={item[2] for item in written.values()},
                written_units={identity for item in written.values() for identity in item[3]},
                written_citations={identity for item in written.values() for identity in item[4]},
                catalog_document_ids={_document_id(item.document_key) for item in catalog.documents},
            )

        for entry in plan.entries:
            if entry.action == "reuse":
                reused_count += 1
                continue
            prior = live.get(entry.document_key)
            prior_artifact_id = prior.artifact_set_id if prior is not None else None
            document_id = _document_id(entry.document_key)
            if entry.action == "retire":
                connection.execute(
                    """/* ishikawa.insert-publication-change */
                    INSERT INTO rag.publication_batch_changes
                      (publication_batch_id, document_id, change_kind,
                       prior_artifact_set_id, resulting_artifact_set_id)
                    VALUES (%s,%s,'retire',%s,NULL)
                    """,
                    (batch_id, document_id, prior_artifact_id),
                )
                connection.execute(
                    """/* ishikawa.retire-active-document */
                    DELETE FROM rag.active_document_versions WHERE document_id=%s
                    """,
                    (document_id,),
                )
                retired_count += 1
                continue
            if entry.action in {"add", "revise", "reprocess"}:
                _, version_id, artifact_id, _, _ = written[entry.document_key]
                connection.execute(
                    """/* ishikawa.insert-publication-change */
                    INSERT INTO rag.publication_batch_changes
                      (publication_batch_id, document_id, change_kind,
                       prior_artifact_set_id, resulting_artifact_set_id)
                    VALUES (%s,%s,%s,%s,%s)
                    """,
                    (batch_id, document_id, entry.action, prior_artifact_id, artifact_id),
                )
                connection.execute(
                    """/* ishikawa.activate-document */
                    INSERT INTO rag.active_document_versions
                      (document_id, document_version_id, artifact_set_id, publication_batch_id)
                    VALUES (%s,%s,%s,%s)
                    ON CONFLICT (document_id) DO UPDATE SET
                      document_version_id=EXCLUDED.document_version_id,
                      artifact_set_id=EXCLUDED.artifact_set_id,
                      publication_batch_id=EXCLUDED.publication_batch_id,
                      activated_at=clock_timestamp()
                    """,
                    (document_id, version_id, artifact_id, batch_id),
                )
                published_count += 1

        validation_digest = domain_digest(
            "ishikawa.publication-validation.v1",
            {
                "publication_batch_id": batch_id,
                "validation_id": plan.validation_id,
                "actions": [
                    {"document_key": entry.document_key, "action": entry.action}
                    for entry in plan.entries
                ],
            },
        )
        connection.execute(
            """/* ishikawa.publish-batch */
            UPDATE rag.publication_batches
            SET state='published', validation_digest=%s,
                validated_at=clock_timestamp(), published_at=clock_timestamp()
            WHERE publication_batch_id=%s AND state='candidate'
            """,
            (validation_digest, batch_id),
        )
        connection.execute(
            """/* ishikawa.finish-run */
            UPDATE rag.ingestion_runs
            SET state='succeeded', outcome_code='PUBLISHED',
                finished_at=GREATEST(clock_timestamp(), started_at)
            WHERE ingestion_run_id=%s AND state='running'
            """,
            (run_id,),
        )
        for entry in plan.entries:
            if entry.outcome == "PASS":
                connection.execute(
                    """/* ishikawa.resolve-quarantine */
                    UPDATE rag_private.quarantine_records
                    SET resolved_at=GREATEST(clock_timestamp(), created_at),
                        resolved_by_run_id=%s,
                        resolution_code='successful_retry'
                    WHERE manifest_entry_identity=%s AND resolved_at IS NULL
                      AND ingestion_run_id<>%s
                    """,
                    (run_id, entry.manifest_entry_identity, run_id),
                )

    return WriteResult(
        run_id,
        batch_id,
        "PUBLISHED",
        published_count,
        retired_count,
        reused_count,
        quarantine_count,
    )
