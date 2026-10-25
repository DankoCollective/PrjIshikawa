# Application Database Migrations

This directory contains ordered, plain-SQL migrations for the native
PostgreSQL application database. Migrations are reviewed and checksum-bound
inputs; operators do not paste them into an interactive SQL session.

`0001_initial_rag_catalog.sql` creates the first empty application schema:

- `rag` contains canonical catalog, ingestion, publication, structural,
  citation, relationship, lexical, and vector records;
- `rag_private` contains server-only artifact locations, stage state, and
  quarantine records; and
- `rag_search` exposes five active-only retrieval views without source paths
  or private operational fields.

The migration creates the fixed `vector(768)` storage column required by the
accepted embedding contract and a native full-text GIN index. It deliberately
does not create HNSW or IVFFlat indexes; that derived-index choice remains a
later calibrated retrieval decision. It inserts only its migration-ledger row
and writes no document, chunk, citation, relationship, or embedding content.

Composite foreign keys keep parent structure, chunk projections, citations,
relationship evidence, and publication changes within the same document and
artifact set. The active search projection uses the classification recorded
with the active document version so rollback cannot expose a newer catalog
classification for an older active revision.

Run this migration only through Script `20`, which verifies the accepted
database, payload checksums, object ownership, role privileges, empty-catalog
state, exact already-applied identity, stop/start persistence, and the final
stopped/boot-disabled service state.

The operator-executed EmceeDanko Script `20` run on 2026-10-19 applied this
migration and passed the complete post-restart contract. The resulting empty
schema is durable application state and is the accepted foundation for catalog
and ingestion implementation.

`0002_align_ingestion_ownership.sql` is the forward-only alignment between
that accepted empty foundation and the frozen Ishikawa configuration model.
It:

- removes class ownership from logical documents and immutable source
  revisions;
- stores the assigned class, class-registry digest, manifest digest, and
  manifest-entry identity with each processed artifact set;
- stores registry and catalog digests with each ingestion run;
- permits one immutable source revision and method profile to produce distinct
  artifact sets when the operator assigns different classes;
- makes `rag_search.active_documents` obtain the visible class from the active
  artifact set;
- adds content-free quarantine subject and successful-remediation linkage;
  and
- preserves the existing 20-table, five-view, ingestion-role, retrieval-role,
  lexical-index, vector-storage, and no-ANN-index boundaries.

The migration requires the exact accepted `0001` identity and an empty
application catalog. That is the proven EmceeDanko state. If any pre-`0002`
application row exists, the transaction fails without changing the schema;
the migration never invents registry or catalog digests for legacy content.

The disposable local proof covers an empty `0001 → 0002` upgrade with an
intermediate PostgreSQL restart, a fresh ordered `0001 + 0002` installation,
transactional rejection of nonempty legacy state, identical schema
fingerprints, reclassification through artifact-set selection, provenance
constraints, quarantine remediation linkage, and unchanged role isolation:

```bash
bash ./phase-28-apisachi-tokuli/scripts/21_test_ingestion_ownership_migration.sh
```

The canonical result ends with
`script_21_ingestion_ownership_migration_test=pass`. The operator had already
confirmed the checksum-identical underlying test before Script `21` restored
the repository's numbering convention; no rerun is required for that accepted
result.

Apply `0002` to the accepted empty EmceeDanko catalog only through Script
`22`:

```bash
bash ./phase-28-apisachi-tokuli/scripts/22_apply_ingestion_ownership_migration.sh --migrate
```

Script `22` first binds the accepted Script `20` receipt and exact `0001`
checksum. Its neutral helper then verifies the live empty `0001` state before
performing the transaction and repeats the complete ownership, column,
constraint, privilege, persistence, and final stopped-state checks.

The operator-executed Script `22` helper applied `0002` successfully on
EmceeDanko and passed the complete post-restart contract. A local
structured-output formatting defect caused the wrapper to report blocked only
after the successful target operation; the corrected source and acceptance
rationale are recorded in the target-acceptance evidence. Migration `0002` is
accepted and must not be rerun in the normal workflow.

`0003_separate_special_token_count.sql` separates tokenizer-added special
tokens from content, structural-context, and configured-prefix tokens while
preserving the exact total submitted to Nomic. It is accepted on the empty
EmceeDanko application catalog through Script `30` and the four-bucket writer
proof in Script `31`.

`0004_preserve_relationship_override_audit.sql` adds the audit identity and
stable reason code required by the frozen exceptional-override relationship
contract. Deterministic edges must keep both fields null; an operator override
must provide both. The migration refuses to invent provenance for any existing
operator-override row. Script `40` applies it only to a disposable database and
proves relationship persistence and traversal while leaving the accepted
schema-v3 database unchanged. Applying `0004` to that still-empty accepted
database requires a separate numbered migration gate after Script `40`
passes.
