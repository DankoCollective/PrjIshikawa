# Ishikawa incremental ingestion writer source ready

Date: 2026-10-19

## Outcome

Numbered Script `23` is ready for operator execution. Its exact local suite
passed before publication:

```text
Ran 64 tests
OK
ishikawa_local_validation_tests=PASS
script_23_incremental_ingestion_writer_test=pass
```

## Implemented boundary

The native Python writer:

- requires the exact accepted PostgreSQL migrations `0001 + 0002`;
- takes a validated plan and already-prepared structural units, chunks,
  citations, 768-dimensional embeddings, and embedding-space identity;
- rejects plan/configuration/prepared-artifact identity mismatches before
  opening a transaction;
- serializes writers with a transaction-scoped PostgreSQL advisory lock;
- rechecks current published state after acquiring that lock;
- uses parameterized SQL for all content and vector values;
- writes the document revision, class-bound artifact set, structures, chunks,
  citations, and embeddings as candidates;
- changes active pointers only in the same transaction that publishes the
  complete manifest batch;
- supports add, revise, reprocess, reuse-only skip, and explicit retirement;
- records valid quarantined attempts without creating a publication batch;
- links a later successful manifest entry to unresolved quarantine history;
  and
- rolls back the transaction when the schema, catalog, or live-state contract
  has changed.

The database driver is injected at runtime. The module uses the Psycopg 3
connection surface without importing or bundling Psycopg, preserving the
native-package boundary.

## Test boundary

Script `23` is local-only. It validates models and transaction orchestration
with synthetic fixtures and a deterministic recording connection. It does
not contact EmceeDanko, connect to PostgreSQL, read organizational documents,
call Nomic or Gemma, or mutate corpus state.

This is not yet target integration acceptance. The safely next gate after
Script `23` passes is a disposable PostgreSQL integration test using the
target-qualified native Psycopg package; it must roll back or remove all
synthetic test data and return PostgreSQL to its stopped state.

## Operator command

From the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/23_test_incremental_ingestion_writer.sh
```
