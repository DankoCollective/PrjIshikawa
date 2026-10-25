# Native PostgreSQL Application Schema Migration Acceptance — 2026-10-19

## Disposition

The operator-executed corrected Script `20` receipt is accepted.

Accepted report:

- `native_postgresql_application_schema_migration_20261019T162250Z_x2Llco.txt`
- SHA-256:
  `e0c29298a70775c69a628c05d2dffbe9821e1b0aab0c9da53e67f015eacfc658`

Accepted source identities recorded by the receipt:

- `20_apply_native_postgresql_application_schema.sh`:
  `e6aa08b31cccddf493b3868cead676d819afb6fac65edda7145b6b3e884c04bf`
- `apply-native-application-schema`:
  `24269f560125f70506693fd28f57d73d2d163847556a2822d5bed0202a1262fb`
- `0001_initial_rag_catalog.sql`:
  `3e2f5e61bd8038bc29764024e21b8bec754fad8a282f89abaf6130e345d6380a`

The receipt proves:

- PostgreSQL `16.15` and pgvector `0.8.7` matched the accepted native runtime;
- migration `0001_initial_rag_catalog` was applied, not merely observed as
  already present;
- the durable empty application schema contains three schemas, 20 base
  tables, five active-only retrieval views, and one migration-ledger row;
- the schema contains `vector(768)` storage and a lexical `tsvector` GIN index
  but deliberately contains no HNSW or IVFFlat index;
- `rag_retrieval` can select from all five retrieval views but from zero base
  tables and has no write privilege;
- `rag_ingest` can select all 20 base tables and write the intended 19
  application tables but cannot alter the migration ledger;
- no privilege was granted through `PUBLIC`, and retrieval cannot see the
  private storage location;
- no document, chunk, citation, relationship, embedding, or other corpus
  content was written;
- PostgreSQL was completely stopped and restarted, after which the migration,
  schema objects, and role privileges passed the same verification again;
- PostgreSQL was returned to the stopped, inactive, boot-disabled state with
  port `5432` free; and
- the bounded result contract, remote temporary-file cleanup, and SSH cleanup
  all passed.

This is durable application database configuration, not a disposable
preflight. It remains on EmceeDanko for the application. The PostgreSQL runtime
and initial schema gates are complete; no additional PostgreSQL repair script
is required.

The next implementation gate is the document-class registry, document catalog,
and ingestion-manifest schema/validation surface, followed by the incremental
ingestion writer. That work must use migration `0001` as accepted and must not
re-create the cluster, database, roles, extension, or initial schema.
