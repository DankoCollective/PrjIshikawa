\set ON_ERROR_STOP on

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';
SET LOCAL ROLE :"owner_role";

DO $migration_guard$
BEGIN
  IF (SELECT count(*) FROM rag.schema_migrations) <> 3
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
     )
     OR NOT EXISTS (
       SELECT 1 FROM rag.schema_migrations
       WHERE migration_id = '0003_separate_special_token_count'
         AND schema_version = 3
         AND migration_sha256 =
           '5e833d8ff556c0e6158daf0419b1013235a11e1a94f1f560206ba813e1fc3761'
     ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'migration 0004 requires the accepted 0001 through 0003 migrations';
  END IF;

  IF EXISTS (
    SELECT 1 FROM rag.relationships
    WHERE detection_method = 'operator_override'
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'migration 0004 cannot invent audit provenance for existing operator overrides';
  END IF;
END
$migration_guard$;

ALTER TABLE rag.relationships
  ADD COLUMN override_audit_identity rag.sha256_hex,
  ADD COLUMN override_reason_code text;

ALTER TABLE rag.relationships
  ADD CONSTRAINT relationships_override_audit_check
    CHECK (
      (detection_method = 'deterministic'
        AND override_audit_identity IS NULL
        AND override_reason_code IS NULL)
      OR
      (detection_method = 'operator_override'
        AND override_audit_identity IS NOT NULL
        AND override_reason_code IS NOT NULL
        AND length(btrim(override_reason_code)) > 0)
    );

COMMENT ON COLUMN rag.relationships.override_audit_identity IS
  'Immutable content-free audit identity required for an operator-resolved relationship.';
COMMENT ON COLUMN rag.relationships.override_reason_code IS
  'Stable content-free reason code required for an operator-resolved relationship.';

INSERT INTO rag.schema_migrations (
  migration_id,
  migration_sha256,
  schema_version
) VALUES (
  '0004_preserve_relationship_override_audit',
  :'migration_sha256',
  4
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
