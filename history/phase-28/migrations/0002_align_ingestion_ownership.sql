\set ON_ERROR_STOP on

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';
SET LOCAL ROLE :"owner_role";

DO $migration_guard$
DECLARE
  application_table regclass;
  contains_rows boolean;
BEGIN
  IF (SELECT count(*) FROM rag.schema_migrations) <> 1
     OR NOT EXISTS (
       SELECT 1
       FROM rag.schema_migrations
       WHERE migration_id = '0001_initial_rag_catalog'
         AND schema_version = 1
         AND migration_sha256 =
           '3e2f5e61bd8038bc29764024e21b8bec754fad8a282f89abaf6130e345d6380a'
     ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'migration 0002 requires the sole accepted 0001 migration';
  END IF;

  FOR application_table IN
    SELECT c.oid::regclass
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname IN ('rag', 'rag_private')
      AND c.relkind = 'r'
      AND c.oid <> 'rag.schema_migrations'::regclass
    ORDER BY n.nspname, c.relname
  LOOP
    EXECUTE format('SELECT EXISTS (SELECT 1 FROM %s)', application_table)
      INTO contains_rows;
    IF contains_rows THEN
      RAISE EXCEPTION USING
        ERRCODE = '55000',
        MESSAGE = 'migration 0002 requires an empty 0001 application catalog';
    END IF;
  END LOOP;
END
$migration_guard$;

DROP VIEW rag_search.active_relationships;
DROP VIEW rag_search.active_embeddings;
DROP VIEW rag_search.active_citations;
DROP VIEW rag_search.active_chunks;
DROP VIEW rag_search.active_documents;

ALTER TABLE rag.document_classes
  RENAME COLUMN registry_version TO registry_digest;
ALTER TABLE rag.document_classes
  ALTER COLUMN registry_digest TYPE rag.sha256_hex
    USING registry_digest::rag.sha256_hex;

ALTER TABLE rag.documents
  DROP COLUMN class_id;
ALTER TABLE rag.documents
  RENAME COLUMN catalog_version TO catalog_digest;
ALTER TABLE rag.documents
  ALTER COLUMN catalog_digest TYPE rag.sha256_hex
    USING catalog_digest::rag.sha256_hex;

ALTER TABLE rag.ingestion_runs
  ADD COLUMN class_registry_digest rag.sha256_hex NOT NULL,
  ADD COLUMN document_catalog_digest rag.sha256_hex NOT NULL;
ALTER TABLE rag.ingestion_runs
  ADD CONSTRAINT ingestion_runs_artifact_provenance_key
    UNIQUE (ingestion_run_id, ingestion_manifest_digest, class_registry_digest);

ALTER TABLE rag.document_versions
  DROP COLUMN assigned_class_id,
  DROP COLUMN class_registry_version,
  DROP COLUMN ingestion_manifest_digest;

DO $constraint_alignment$
DECLARE
  legacy_constraint name;
BEGIN
  SELECT con.conname
    INTO legacy_constraint
  FROM pg_constraint con
  WHERE con.conrelid = 'rag.document_artifact_sets'::regclass
    AND con.contype = 'u'
    AND pg_get_constraintdef(con.oid, true) =
      'UNIQUE (document_version_id, method_profile_id)';

  IF legacy_constraint IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'migration 0002 could not identify the legacy artifact uniqueness constraint';
  END IF;

  EXECUTE format(
    'ALTER TABLE rag.document_artifact_sets DROP CONSTRAINT %I',
    legacy_constraint
  );
END
$constraint_alignment$;

ALTER TABLE rag.document_artifact_sets
  DROP CONSTRAINT document_artifact_sets_ingestion_run_id_fkey,
  ADD COLUMN assigned_class_id text NOT NULL
    REFERENCES rag.document_classes(class_id),
  ADD COLUMN class_registry_digest rag.sha256_hex NOT NULL,
  ADD COLUMN ingestion_manifest_digest rag.sha256_hex NOT NULL,
  ADD COLUMN manifest_entry_identity rag.sha256_hex NOT NULL,
  ADD CONSTRAINT document_artifact_sets_semantic_inputs_key
    UNIQUE (document_version_id, method_profile_id, assigned_class_id),
  ADD CONSTRAINT document_artifact_sets_run_provenance_fkey
    FOREIGN KEY (
      ingestion_run_id,
      ingestion_manifest_digest,
      class_registry_digest
    ) REFERENCES rag.ingestion_runs (
      ingestion_run_id,
      ingestion_manifest_digest,
      class_registry_digest
    );

ALTER TABLE rag_private.quarantine_records
  DROP CONSTRAINT quarantine_records_document_version_id_fkey,
  ADD COLUMN manifest_entry_identity rag.sha256_hex,
  ADD COLUMN resolved_by_run_id rag.sha256_hex
    REFERENCES rag.ingestion_runs(ingestion_run_id),
  ADD COLUMN resolution_code text,
  ADD CONSTRAINT quarantine_records_document_version_document_fkey
    FOREIGN KEY (document_version_id, document_id)
    REFERENCES rag.document_versions(document_version_id, document_id),
  ADD CONSTRAINT quarantine_records_subject_check
    CHECK (document_id IS NOT NULL OR manifest_entry_identity IS NOT NULL),
  ADD CONSTRAINT quarantine_records_document_version_subject_check
    CHECK (document_version_id IS NULL OR document_id IS NOT NULL),
  ADD CONSTRAINT quarantine_records_resolution_v1_check
    CHECK (
      (
        resolved_at IS NULL
        AND resolved_by_run_id IS NULL
        AND resolution_code IS NULL
      )
      OR
      (
        resolved_at IS NOT NULL
        AND resolved_at >= created_at
        AND resolved_by_run_id IS NOT NULL
        AND resolved_by_run_id <> ingestion_run_id
        AND resolution_code = 'successful_retry'
      )
    );

CREATE VIEW rag_search.active_documents WITH (security_barrier = true) AS
SELECT
  d.document_id::text AS document_id,
  d.document_key,
  d.display_name,
  das.assigned_class_id AS class_id,
  dc.display_name AS class_display_name,
  dv.document_version_id::text AS document_version_id,
  dv.source_digest::text AS source_digest,
  dv.source_format,
  dv.language,
  dv.page_count,
  adv.artifact_set_id::text AS artifact_set_id,
  das.method_profile_id::text AS method_profile_id,
  adv.publication_batch_id::text AS publication_batch_id,
  d.client_metadata,
  adv.activated_at
FROM rag.active_document_versions adv
JOIN rag.documents d ON d.document_id = adv.document_id
JOIN rag.document_versions dv ON dv.document_version_id = adv.document_version_id
JOIN rag.document_artifact_sets das ON das.artifact_set_id = adv.artifact_set_id
JOIN rag.document_classes dc ON dc.class_id = das.assigned_class_id
WHERE d.status = 'active' AND das.state = 'validated';

CREATE VIEW rag_search.active_chunks WITH (security_barrier = true) AS
SELECT
  c.chunk_id::text AS chunk_id,
  ad.document_id,
  ad.document_key,
  ad.display_name,
  ad.class_id,
  ad.document_version_id,
  ad.artifact_set_id,
  ad.method_profile_id,
  c.projection_kind,
  c.ordinal,
  c.retrieval_text,
  c.retrieval_text_digest::text AS retrieval_text_digest,
  c.contextual_fields,
  c.retrieval_filters,
  c.client_metadata,
  c.content_token_count,
  c.context_token_count,
  c.prefix_token_count,
  c.total_embedding_token_count,
  c.processing_profile,
  c.lexical_search_config,
  c.lexical_vector
FROM rag_search.active_documents ad
JOIN rag.chunks c ON c.artifact_set_id::text = ad.artifact_set_id;

CREATE VIEW rag_search.active_citations WITH (security_barrier = true) AS
SELECT
  ca.citation_id::text AS citation_id,
  ac.chunk_id,
  ac.document_id,
  ac.document_key,
  ac.display_name,
  ac.document_version_id,
  ca.display_label,
  ca.relevant_excerpt,
  ca.page_start,
  ca.page_end,
  ca.structural_path,
  ca.citation_anchor,
  ca.client_metadata
FROM rag_search.active_chunks ac
JOIN rag.citation_anchors ca ON ca.chunk_id::text = ac.chunk_id;

CREATE VIEW rag_search.active_embeddings WITH (security_barrier = true) AS
SELECT
  ce.embedding_artifact_id::text AS embedding_artifact_id,
  ac.chunk_id,
  ac.document_id,
  ac.document_version_id,
  ce.embedding_space_id::text AS embedding_space_id,
  es.model_name,
  es.model_revision,
  es.dimension,
  es.distance_metric,
  ce.embedding
FROM rag_search.active_chunks ac
JOIN rag.chunk_embeddings ce ON ce.chunk_id::text = ac.chunk_id
JOIN rag.embedding_spaces es ON es.embedding_space_id = ce.embedding_space_id
WHERE es.status = 'active';

CREATE VIEW rag_search.active_relationships WITH (security_barrier = true) AS
SELECT
  r.relationship_id::text AS relationship_id,
  ad.document_id AS source_document_id,
  ad.document_version_id AS source_document_version_id,
  r.relationship_type,
  r.source_kind,
  r.source_identity::text AS source_identity,
  r.target_kind,
  r.target_identity,
  r.evidence_citation_id::text AS evidence_citation_id,
  r.detection_method,
  r.review_status,
  rt.influences_retrieval
FROM rag_search.active_documents ad
JOIN rag.relationships r ON r.artifact_set_id::text = ad.artifact_set_id
JOIN rag.relationship_types rt ON rt.relationship_type = r.relationship_type
WHERE r.review_status IN ('accepted', 'external');

INSERT INTO rag.schema_migrations (
  migration_id,
  migration_sha256,
  schema_version
) VALUES (
  '0002_align_ingestion_ownership',
  :'migration_sha256',
  2
);

RESET ROLE;

REVOKE ALL ON ALL TABLES IN SCHEMA rag, rag_private, rag_search FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA rag, rag_private, rag_search FROM PUBLIC;

GRANT USAGE ON SCHEMA rag, rag_private, rag_search TO :"ingest_role";
GRANT USAGE ON TYPE rag.sha256_hex TO :"ingest_role";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA rag, rag_private
  TO :"ingest_role";
REVOKE INSERT, UPDATE, DELETE ON rag.schema_migrations FROM :"ingest_role";
GRANT SELECT ON ALL TABLES IN SCHEMA rag_search TO :"ingest_role";

GRANT USAGE ON SCHEMA rag_search TO :"retrieval_role";
GRANT SELECT ON ALL TABLES IN SCHEMA rag_search TO :"retrieval_role";

COMMIT;
