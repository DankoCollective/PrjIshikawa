# Native PostgreSQL Application Schema Migration Source Ready — 2026-10-19

## Disposition

Script `20`, its neutral target helper, and migration `0001` are source-ready
and bound to the accepted corrected Script `16` database-configuration
receipt.

Source identities:

- `20_apply_native_postgresql_application_schema.sh`
  - SHA-256: `e6aa08b31cccddf493b3868cead676d819afb6fac65edda7145b6b3e884c04bf`
- `apply-native-application-schema`
  - SHA-256: `24269f560125f70506693fd28f57d73d2d163847556a2822d5bed0202a1262fb`
  - bytes: `26945`
- `0001_initial_rag_catalog.sql`
  - SHA-256: `3e2f5e61bd8038bc29764024e21b8bec754fad8a282f89abaf6130e345d6380a`
  - bytes: `21098`
- `tests/test_initial_rag_catalog_migration.sh`
  - SHA-256: `f861351ac0d83a5f7c296202bf8c88821d9ed0806fd46bb1624c4497796109cc`
  - bytes: `12489`
- accepted Script `16` report
  - SHA-256: `6b8677bb13d66dcb0e55d2f2be6bbdfd8a7f03a9456faa6c3348ebd7e908711f`

The guarded migration:

- requires explicit `--migrate` authorization;
- re-verifies the accepted empty `rag_catalog` database, roles, pgvector
  extension, stopped native cluster, loopback configuration, and manual-start
  boundary;
- checksum-verifies the neutral helper and SQL file locally and again after
  temporary target staging;
- applies one plain-SQL transaction and rolls back the created schemas if
  post-transaction validation fails;
- creates `rag`, `rag_private`, and `rag_search`, all owned by `rag_owner`;
- creates 20 empty canonical/private tables and five active-only retrieval
  views;
- uses composite foreign keys to prevent cross-document or cross-artifact
  structure, chunk, citation, relationship-evidence, and publication links;
- projects the classification recorded by the active document version rather
  than a potentially newer catalog classification;
- creates native full-text storage and a GIN lexical index;
- creates a `vector(768)` column but deliberately defers HNSW/IVFFlat until
  retrieval calibration;
- gives `rag_retrieval` read-only access to the five active views and no base-
  table or write access;
- gives `rag_ingest` read access to 20 base tables and write access to 19,
  excluding the migration ledger from application writes;
- exposes no private artifact storage location through the retrieval views;
- writes one migration-ledger row and no corpus or embedding content;
- recognizes an already-applied migration only when its exact identifier,
  checksum, schema version, object counts, ownership, and privileges match;
- proves persistence by stopping PostgreSQL completely, restarting it,
  re-verifying the schema/ledger/privilege contract, and stopping it again;
- processes no application secret; and
- stops PostgreSQL and preserves the inactive, boot-disabled final state.

After the first target transaction blocked without a usable SQL diagnostic,
the canonical helper was corrected to emit only a bounded SQLSTATE, migration
line, failure class, diagnostic size, and diagnostic SHA-256 while deleting
the raw error. This diagnostic correction does not change migration `0001` or
its locally proven schema.

The second target run showed that the generic Bash `ERR` trap still
intercepted the nonzero `psql` status before classification. The current helper
uses an explicit conditional around `psql`; this control-flow correction also
does not change migration `0001` or its schema contract.

The third target run produced the bounded privilege diagnostic. Its diagnostic
byte count and SHA-256 exactly identify `psql` being unable to open the
operator-owned migration pathname below a mode-`0700` transfer directory after
the process changed to the `postgres` OS identity. The current helper keeps the
transfer directory private, has the root helper open the already hash-verified
file, and streams its bytes to `psql` over standard input. No target directory
permission is widened. This transport correction does not change migration
`0001`.

Because no target run had read or committed the SQL, the subsequent look-ahead
review strengthened migration `0001` before acceptance. It added only
declarative relational integrity and corrected active-version classification;
the three-schema, 20-table, five-view, role, search, and empty-content contract
is unchanged. No upgrade migration is required because the prior target
attempts never applied the earlier checksum.

Local validation passed with no target contact:

```text
native_postgresql_application_schema_migration_source=pass
target_contact=false
application_schema_migration=false
migration_id=0001_initial_rag_catalog
```

The SQL also executed successfully against a disposable local PostgreSQL
`16.15`/pgvector test cluster. Independent queries returned:

```text
tables=20
views=5
embedding_column=vector(768)
lexical_gin_indexes=1
vector_ann_indexes=0
migration_rows=1
retrieval_base_select=0
retrieval_view_select=5
ingestion_base_select=20
ingestion_writable_tables=19
restart_contract=3|20|5|1|0|5|19
retrieval_base_table_query_denied=true
cross_artifact_parent=pass
cross_artifact_chunk_mapping=pass
cross_version_citation=pass
cross_artifact_relationship_evidence=pass
relationship_kind_mismatch=pass
cross_document_publication_change=pass
active_version_class=regulation
exact_already_applied_detection=pass
```

That disposable cluster was stopped and removed. This local proof does not
claim the EmceeDanko migration has run; the target helper separately requires
the accepted pgvector `0.8.7` runtime.

Operator command from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/20_apply_native_postgresql_application_schema.sh --migrate
```
