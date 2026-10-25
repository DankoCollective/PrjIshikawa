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
  IF (SELECT count(*) FROM rag.schema_migrations) <> 2
     OR NOT EXISTS (
       SELECT 1 FROM rag.schema_migrations
       WHERE migration_id = '0001_initial_rag_catalog'
         AND schema_version = 1
         AND migration_sha256 =
           '3e2f5e61bd8038bc29764024e21b8bec754fad8a282f89abaf6130e345d6380a'
     )
     OR NOT EXISTS (
       SELECT 1 FROM rag.schema_migrations
       WHERE migration_id = '0002_align_ingestion_ownership'
         AND schema_version = 2
         AND migration_sha256 =
           '74b08adb8aac9828ac076744fedfd22619751326c911bf17f1fa8690e01345e4'
     ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'migration 0003 requires the accepted 0001 and 0002 migrations';
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
        MESSAGE = 'migration 0003 requires an empty application catalog';
    END IF;
  END LOOP;
END
$migration_guard$;

ALTER TABLE rag.chunks
  ADD COLUMN special_token_count integer NOT NULL
    CHECK (special_token_count >= 0);

DO $replace_total_constraint$
DECLARE
  prior_constraint name;
BEGIN
  SELECT con.conname
    INTO prior_constraint
  FROM pg_constraint con
  WHERE con.conrelid = 'rag.chunks'::regclass
    AND con.contype = 'c'
    AND pg_get_constraintdef(con.oid, true) LIKE
      '%total_embedding_token_count%content_token_count%context_token_count%prefix_token_count%';

  IF prior_constraint IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'migration 0003 could not identify the prior token-total constraint';
  END IF;

  EXECUTE format('ALTER TABLE rag.chunks DROP CONSTRAINT %I', prior_constraint);
END
$replace_total_constraint$;

ALTER TABLE rag.chunks
  ADD CONSTRAINT chunks_total_embedding_token_count_v2_check
    CHECK (
      total_embedding_token_count =
        content_token_count + context_token_count +
        prefix_token_count + special_token_count
    );

COMMENT ON COLUMN rag.chunks.content_token_count IS
  'Tokens contributed by chunk content, excluding tokenizer-added special tokens.';
COMMENT ON COLUMN rag.chunks.context_token_count IS
  'Tokens contributed by structural context, excluding tokenizer-added special tokens.';
COMMENT ON COLUMN rag.chunks.prefix_token_count IS
  'Tokens contributed by the configured embedding task prefix, excluding tokenizer-added special tokens.';
COMMENT ON COLUMN rag.chunks.special_token_count IS
  'Tokenizer-added boundary or control tokens included in the submitted embedding input total.';
COMMENT ON COLUMN rag.chunks.total_embedding_token_count IS
  'Exact authoritative tokenizer total including content, context, configured prefix, and special tokens.';

CREATE OR REPLACE VIEW rag_search.active_chunks
WITH (security_barrier = true) AS
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
  c.lexical_vector,
  c.special_token_count
FROM rag_search.active_documents ad
JOIN rag.chunks c ON c.artifact_set_id::text = ad.artifact_set_id;

INSERT INTO rag.schema_migrations (
  migration_id,
  migration_sha256,
  schema_version
) VALUES (
  '0003_separate_special_token_count',
  :'migration_sha256',
  3
);

RESET ROLE;

REVOKE ALL ON ALL TABLES IN SCHEMA rag, rag_private, rag_search FROM PUBLIC;
GRANT USAGE ON SCHEMA rag, rag_private, rag_search TO :"ingest_role";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA rag, rag_private
  TO :"ingest_role";
REVOKE INSERT, UPDATE, DELETE ON rag.schema_migrations FROM :"ingest_role";
GRANT SELECT ON ALL TABLES IN SCHEMA rag_search TO :"ingest_role";
GRANT USAGE ON SCHEMA rag_search TO :"retrieval_role";
GRANT SELECT ON ALL TABLES IN SCHEMA rag_search TO :"retrieval_role";

COMMIT;
