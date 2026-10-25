\set ON_ERROR_STOP on

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';

CREATE SCHEMA rag AUTHORIZATION :"owner_role";
CREATE SCHEMA rag_private AUTHORIZATION :"owner_role";
CREATE SCHEMA rag_search AUTHORIZATION :"owner_role";

REVOKE ALL ON SCHEMA rag, rag_private, rag_search FROM PUBLIC;

SET LOCAL ROLE :"owner_role";

CREATE DOMAIN rag.sha256_hex AS text
  CHECK (VALUE ~ '^[0-9a-f]{64}$');

CREATE TABLE rag.schema_migrations (
  migration_id text PRIMARY KEY,
  migration_sha256 rag.sha256_hex NOT NULL,
  schema_version integer NOT NULL CHECK (schema_version > 0),
  applied_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE rag.document_classes (
  class_id text PRIMARY KEY CHECK (class_id ~ '^[a-z][a-z0-9._-]{0,127}$'),
  display_name text NOT NULL CHECK (length(btrim(display_name)) > 0),
  registry_version text NOT NULL CHECK (length(btrim(registry_version)) > 0),
  status text NOT NULL CHECK (status IN ('active', 'retired')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE rag.documents (
  document_id rag.sha256_hex PRIMARY KEY,
  document_key text NOT NULL UNIQUE
    CHECK (document_key ~ '^[a-z0-9][a-z0-9._-]{0,127}$'),
  class_id text NOT NULL REFERENCES rag.document_classes(class_id),
  display_name text NOT NULL CHECK (length(btrim(display_name)) > 0),
  catalog_version text NOT NULL CHECK (length(btrim(catalog_version)) > 0),
  status text NOT NULL CHECK (status IN ('active', 'retired')),
  client_metadata jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(client_metadata) = 'object'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE rag.ingestion_runs (
  ingestion_run_id rag.sha256_hex PRIMARY KEY,
  ingestion_manifest_digest rag.sha256_hex NOT NULL,
  schema_version integer NOT NULL CHECK (schema_version > 0),
  method_profile_id rag.sha256_hex NOT NULL,
  state text NOT NULL
    CHECK (state IN ('pending', 'running', 'succeeded', 'failed', 'quarantined', 'skipped')),
  outcome_code text,
  started_at timestamptz NOT NULL,
  finished_at timestamptz,
  CHECK (finished_at IS NULL OR finished_at >= started_at)
);

CREATE TABLE rag.publication_batches (
  publication_batch_id rag.sha256_hex PRIMARY KEY,
  ingestion_run_id rag.sha256_hex NOT NULL
    REFERENCES rag.ingestion_runs(ingestion_run_id),
  state text NOT NULL
    CHECK (state IN ('candidate', 'validated', 'published', 'rolled_back', 'failed')),
  validation_digest rag.sha256_hex,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  validated_at timestamptz,
  published_at timestamptz,
  rolled_back_at timestamptz
);

CREATE TABLE rag.document_versions (
  document_version_id rag.sha256_hex PRIMARY KEY,
  document_id rag.sha256_hex NOT NULL REFERENCES rag.documents(document_id),
  source_digest rag.sha256_hex NOT NULL,
  assigned_class_id text NOT NULL REFERENCES rag.document_classes(class_id),
  class_registry_version text NOT NULL CHECK (length(btrim(class_registry_version)) > 0),
  ingestion_manifest_digest rag.sha256_hex NOT NULL,
  source_format text NOT NULL CHECK (source_format = 'application/pdf'),
  language text,
  page_count integer NOT NULL CHECK (page_count > 0),
  created_by_run_id rag.sha256_hex NOT NULL
    REFERENCES rag.ingestion_runs(ingestion_run_id),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (document_id, source_digest),
  UNIQUE (document_version_id, document_id)
);

CREATE TABLE rag.document_artifact_sets (
  artifact_set_id rag.sha256_hex PRIMARY KEY,
  document_version_id rag.sha256_hex NOT NULL,
  document_id rag.sha256_hex NOT NULL,
  method_profile_id rag.sha256_hex NOT NULL,
  ingestion_run_id rag.sha256_hex NOT NULL
    REFERENCES rag.ingestion_runs(ingestion_run_id),
  processing_profiles jsonb NOT NULL CHECK (jsonb_typeof(processing_profiles) = 'array'),
  state text NOT NULL
    CHECK (state IN ('candidate', 'validated', 'quarantined', 'superseded')),
  validation_digest rag.sha256_hex,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (document_version_id, method_profile_id),
  UNIQUE (artifact_set_id, document_version_id),
  UNIQUE (artifact_set_id, document_id),
  FOREIGN KEY (document_version_id, document_id)
    REFERENCES rag.document_versions(document_version_id, document_id)
);

CREATE TABLE rag.structural_units (
  structural_unit_id rag.sha256_hex PRIMARY KEY,
  artifact_set_id rag.sha256_hex NOT NULL
    REFERENCES rag.document_artifact_sets(artifact_set_id),
  parent_unit_id rag.sha256_hex,
  structural_kind text NOT NULL CHECK (length(btrim(structural_kind)) > 0),
  ordinal bigint NOT NULL CHECK (ordinal >= 0),
  page_start integer NOT NULL CHECK (page_start > 0),
  page_end integer NOT NULL CHECK (page_end >= page_start),
  structural_path jsonb NOT NULL CHECK (jsonb_typeof(structural_path) = 'array'),
  source_anchor jsonb NOT NULL CHECK (jsonb_typeof(source_anchor) = 'object'),
  normalized_text text NOT NULL CHECK (length(normalized_text) > 0),
  normalized_digest rag.sha256_hex NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (artifact_set_id, ordinal),
  UNIQUE (structural_unit_id, artifact_set_id),
  FOREIGN KEY (parent_unit_id, artifact_set_id)
    REFERENCES rag.structural_units(structural_unit_id, artifact_set_id)
);

CREATE TABLE rag.chunks (
  chunk_id rag.sha256_hex PRIMARY KEY,
  artifact_set_id rag.sha256_hex NOT NULL
    REFERENCES rag.document_artifact_sets(artifact_set_id),
  method_profile_id rag.sha256_hex NOT NULL,
  projection_kind text NOT NULL CHECK (length(btrim(projection_kind)) > 0),
  ordinal bigint NOT NULL CHECK (ordinal >= 0),
  retrieval_text text NOT NULL CHECK (length(retrieval_text) > 0),
  retrieval_text_digest rag.sha256_hex NOT NULL,
  contextual_fields jsonb NOT NULL CHECK (jsonb_typeof(contextual_fields) = 'object'),
  retrieval_filters jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(retrieval_filters) = 'object'),
  client_metadata jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(client_metadata) = 'object'),
  content_token_count integer NOT NULL CHECK (content_token_count >= 0),
  context_token_count integer NOT NULL CHECK (context_token_count >= 0),
  prefix_token_count integer NOT NULL CHECK (prefix_token_count >= 0),
  total_embedding_token_count integer NOT NULL CHECK (total_embedding_token_count > 0),
  processing_profile text NOT NULL CHECK (length(btrim(processing_profile)) > 0),
  lexical_search_config regconfig NOT NULL,
  lexical_vector tsvector NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK (total_embedding_token_count =
    content_token_count + context_token_count + prefix_token_count),
  UNIQUE (artifact_set_id, ordinal),
  UNIQUE (chunk_id, artifact_set_id)
);

CREATE TABLE rag.chunk_structural_units (
  chunk_id rag.sha256_hex NOT NULL,
  structural_unit_id rag.sha256_hex NOT NULL,
  artifact_set_id rag.sha256_hex NOT NULL,
  unit_ordinal integer NOT NULL CHECK (unit_ordinal >= 0),
  PRIMARY KEY (chunk_id, unit_ordinal),
  UNIQUE (chunk_id, structural_unit_id),
  FOREIGN KEY (chunk_id, artifact_set_id)
    REFERENCES rag.chunks(chunk_id, artifact_set_id) ON DELETE CASCADE,
  FOREIGN KEY (structural_unit_id, artifact_set_id)
    REFERENCES rag.structural_units(structural_unit_id, artifact_set_id)
);

CREATE TABLE rag.citation_anchors (
  citation_id rag.sha256_hex PRIMARY KEY,
  chunk_id rag.sha256_hex NOT NULL,
  artifact_set_id rag.sha256_hex NOT NULL,
  document_version_id rag.sha256_hex NOT NULL,
  display_label text NOT NULL CHECK (length(btrim(display_label)) > 0),
  relevant_excerpt text NOT NULL CHECK (length(relevant_excerpt) > 0),
  page_start integer NOT NULL CHECK (page_start > 0),
  page_end integer NOT NULL CHECK (page_end >= page_start),
  structural_path jsonb NOT NULL CHECK (jsonb_typeof(structural_path) = 'array'),
  citation_anchor jsonb NOT NULL CHECK (jsonb_typeof(citation_anchor) = 'object'),
  client_metadata jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(client_metadata) = 'object'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (citation_id, artifact_set_id),
  FOREIGN KEY (chunk_id, artifact_set_id)
    REFERENCES rag.chunks(chunk_id, artifact_set_id) ON DELETE CASCADE,
  FOREIGN KEY (artifact_set_id, document_version_id)
    REFERENCES rag.document_artifact_sets(artifact_set_id, document_version_id)
);

CREATE TABLE rag.embedding_spaces (
  embedding_space_id rag.sha256_hex PRIMARY KEY,
  model_name text NOT NULL,
  model_revision text NOT NULL,
  model_digest rag.sha256_hex NOT NULL,
  tokenizer_digest rag.sha256_hex NOT NULL,
  pooling_method text NOT NULL,
  document_prefix text NOT NULL,
  query_prefix text NOT NULL,
  dimension integer NOT NULL CHECK (dimension = 768),
  maximum_input_tokens integer NOT NULL CHECK (maximum_input_tokens = 2048),
  vector_transform text NOT NULL CHECK (vector_transform = 'none'),
  distance_metric text NOT NULL CHECK (distance_metric = 'cosine'),
  status text NOT NULL CHECK (status IN ('candidate', 'active', 'retired')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE UNIQUE INDEX embedding_spaces_one_active_idx
  ON rag.embedding_spaces ((status)) WHERE status = 'active';

CREATE TABLE rag.chunk_embeddings (
  embedding_artifact_id rag.sha256_hex PRIMARY KEY,
  chunk_id rag.sha256_hex NOT NULL REFERENCES rag.chunks(chunk_id) ON DELETE CASCADE,
  embedding_space_id rag.sha256_hex NOT NULL
    REFERENCES rag.embedding_spaces(embedding_space_id),
  submitted_input_digest rag.sha256_hex NOT NULL,
  embedding vector(768) NOT NULL,
  normalized boolean NOT NULL,
  creation_run_id rag.sha256_hex NOT NULL
    REFERENCES rag.ingestion_runs(ingestion_run_id),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (chunk_id, embedding_space_id)
);

CREATE TABLE rag.relationship_types (
  relationship_type text PRIMARY KEY
    CHECK (relationship_type ~ '^[a-z][a-z0-9._-]{0,127}$'),
  source_kind text NOT NULL CHECK (source_kind IN ('document', 'structural_unit')),
  target_kind text NOT NULL
    CHECK (target_kind IN ('document', 'document_version', 'structural_unit', 'external')),
  inverse_display_name text,
  influences_retrieval boolean NOT NULL DEFAULT false,
  registry_version text NOT NULL CHECK (length(btrim(registry_version)) > 0),
  status text NOT NULL CHECK (status IN ('active', 'retired')),
  UNIQUE (relationship_type, source_kind, target_kind)
);

CREATE TABLE rag.relationships (
  relationship_id rag.sha256_hex PRIMARY KEY,
  artifact_set_id rag.sha256_hex NOT NULL
    REFERENCES rag.document_artifact_sets(artifact_set_id),
  relationship_type text NOT NULL,
  source_kind text NOT NULL CHECK (source_kind IN ('document', 'structural_unit')),
  source_identity rag.sha256_hex NOT NULL,
  target_kind text NOT NULL
    CHECK (target_kind IN ('document', 'document_version', 'structural_unit', 'external')),
  target_identity text NOT NULL CHECK (length(btrim(target_identity)) > 0),
  evidence_citation_id rag.sha256_hex NOT NULL,
  detection_method text NOT NULL CHECK (detection_method IN ('deterministic', 'operator_override')),
  review_status text NOT NULL CHECK (review_status IN ('accepted', 'external', 'unresolved')),
  relationship_definition_version text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (relationship_type, source_kind, target_kind)
    REFERENCES rag.relationship_types(relationship_type, source_kind, target_kind),
  FOREIGN KEY (evidence_citation_id, artifact_set_id)
    REFERENCES rag.citation_anchors(citation_id, artifact_set_id)
);

CREATE TABLE rag.publication_batch_changes (
  publication_batch_id rag.sha256_hex NOT NULL
    REFERENCES rag.publication_batches(publication_batch_id),
  document_id rag.sha256_hex NOT NULL REFERENCES rag.documents(document_id),
  change_kind text NOT NULL CHECK (change_kind IN ('add', 'revise', 'reprocess', 'retire')),
  prior_artifact_set_id rag.sha256_hex
    REFERENCES rag.document_artifact_sets(artifact_set_id),
  resulting_artifact_set_id rag.sha256_hex
    REFERENCES rag.document_artifact_sets(artifact_set_id),
  PRIMARY KEY (publication_batch_id, document_id),
  CHECK (
    (change_kind = 'add' AND prior_artifact_set_id IS NULL AND resulting_artifact_set_id IS NOT NULL)
    OR (change_kind IN ('revise', 'reprocess') AND prior_artifact_set_id IS NOT NULL
      AND resulting_artifact_set_id IS NOT NULL)
    OR (change_kind = 'retire' AND prior_artifact_set_id IS NOT NULL
      AND resulting_artifact_set_id IS NULL)
  ),
  FOREIGN KEY (prior_artifact_set_id, document_id)
    REFERENCES rag.document_artifact_sets(artifact_set_id, document_id),
  FOREIGN KEY (resulting_artifact_set_id, document_id)
    REFERENCES rag.document_artifact_sets(artifact_set_id, document_id)
);

CREATE TABLE rag.active_document_versions (
  document_id rag.sha256_hex PRIMARY KEY,
  document_version_id rag.sha256_hex NOT NULL,
  artifact_set_id rag.sha256_hex NOT NULL,
  publication_batch_id rag.sha256_hex NOT NULL
    REFERENCES rag.publication_batches(publication_batch_id),
  activated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (document_version_id, document_id)
    REFERENCES rag.document_versions(document_version_id, document_id),
  FOREIGN KEY (artifact_set_id, document_version_id)
    REFERENCES rag.document_artifact_sets(artifact_set_id, document_version_id)
);

CREATE TABLE rag_private.artifact_manifests (
  artifact_id rag.sha256_hex PRIMARY KEY,
  document_version_id rag.sha256_hex
    REFERENCES rag.document_versions(document_version_id),
  ingestion_run_id rag.sha256_hex NOT NULL
    REFERENCES rag.ingestion_runs(ingestion_run_id),
  artifact_kind text NOT NULL CHECK (length(btrim(artifact_kind)) > 0),
  artifact_digest rag.sha256_hex NOT NULL,
  byte_count bigint NOT NULL CHECK (byte_count >= 0),
  media_type text,
  storage_location text NOT NULL CHECK (length(storage_location) > 0),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (artifact_kind, artifact_digest)
);

CREATE TABLE rag_private.ingestion_stages (
  stage_record_id rag.sha256_hex PRIMARY KEY,
  ingestion_run_id rag.sha256_hex NOT NULL
    REFERENCES rag.ingestion_runs(ingestion_run_id),
  document_version_id rag.sha256_hex
    REFERENCES rag.document_versions(document_version_id),
  stage_name text NOT NULL
    CHECK (stage_name IN ('discover', 'fingerprint', 'validate_class', 'extract',
      'normalize', 'structure', 'chunk', 'embed', 'validate', 'publish')),
  state text NOT NULL
    CHECK (state IN ('pending', 'running', 'succeeded', 'failed', 'quarantined', 'skipped')),
  attempt integer NOT NULL CHECK (attempt > 0),
  input_identity rag.sha256_hex,
  output_identity rag.sha256_hex,
  outcome_code text,
  started_at timestamptz,
  finished_at timestamptz,
  CHECK (finished_at IS NULL OR started_at IS NULL OR finished_at >= started_at)
);

CREATE TABLE rag_private.quarantine_records (
  quarantine_id rag.sha256_hex PRIMARY KEY,
  ingestion_run_id rag.sha256_hex NOT NULL
    REFERENCES rag.ingestion_runs(ingestion_run_id),
  document_id rag.sha256_hex REFERENCES rag.documents(document_id),
  document_version_id rag.sha256_hex
    REFERENCES rag.document_versions(document_version_id),
  stage_name text NOT NULL,
  reason_code text NOT NULL CHECK (length(btrim(reason_code)) > 0),
  private_location text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  resolved_at timestamptz
);

CREATE INDEX document_versions_document_idx
  ON rag.document_versions (document_id, created_at);
CREATE INDEX artifact_sets_document_version_idx
  ON rag.document_artifact_sets (document_version_id, state);
CREATE INDEX structural_units_parent_idx
  ON rag.structural_units (artifact_set_id, parent_unit_id, ordinal);
CREATE INDEX chunks_artifact_set_idx
  ON rag.chunks (artifact_set_id, ordinal);
CREATE INDEX chunks_lexical_gin_idx
  ON rag.chunks USING gin (lexical_vector);
CREATE INDEX citations_chunk_idx
  ON rag.citation_anchors (chunk_id);
CREATE INDEX embeddings_space_chunk_idx
  ON rag.chunk_embeddings (embedding_space_id, chunk_id);
CREATE INDEX relationships_source_idx
  ON rag.relationships (source_kind, source_identity);
CREATE INDEX relationships_target_idx
  ON rag.relationships (target_kind, target_identity);
CREATE INDEX publication_changes_document_idx
  ON rag.publication_batch_changes (document_id, publication_batch_id);
CREATE INDEX artifact_manifests_document_idx
  ON rag_private.artifact_manifests (document_version_id, artifact_kind);
CREATE INDEX ingestion_stages_run_idx
  ON rag_private.ingestion_stages (ingestion_run_id, stage_name);
CREATE INDEX quarantine_run_idx
  ON rag_private.quarantine_records (ingestion_run_id, reason_code);

CREATE VIEW rag_search.active_documents WITH (security_barrier = true) AS
SELECT
  d.document_id::text AS document_id,
  d.document_key,
  d.display_name,
  dv.assigned_class_id AS class_id,
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
JOIN rag.document_classes dc ON dc.class_id = dv.assigned_class_id
JOIN rag.document_artifact_sets das ON das.artifact_set_id = adv.artifact_set_id
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

INSERT INTO rag.schema_migrations (
  migration_id,
  migration_sha256,
  schema_version
) VALUES (
  '0001_initial_rag_catalog',
  :'migration_sha256',
  1
);

COMMIT;
