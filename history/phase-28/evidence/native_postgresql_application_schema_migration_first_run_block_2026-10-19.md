# Native PostgreSQL Application Schema Migration First-Run Block — 2026-10-19

## Disposition

The first operator-executed Script `20` run is blocked and is not accepted as
a completed migration.

Blocked report:

- `native_postgresql_application_schema_migration_20261019T160033Z_ThUqSQ.txt`
- SHA-256:
  `31c8699781bdd3341ec9f1420aae64febf9a79da1c9ed8b62132c1102fff3c14`

The receipt proves:

- the exact Script `20`, neutral helper, and migration `0001` payloads passed
  target checksum verification;
- the accepted native PostgreSQL cluster started, became ready, and listened
  only on `127.0.0.1:5432`;
- the SQL migration command returned nonzero and no migration pass marker was
  emitted;
- the migration was enclosed by `BEGIN`/`COMMIT` with `ON_ERROR_STOP`, so the
  failed session did not commit a partial migration;
- no document, chunk, citation, relationship, or embedding content was an
  authorized action;
- failure cleanup stopped the cluster successfully; and
- all temporary target files and the reusable SSH control connection were
  removed successfully.

The helper incorrectly discarded the SQL diagnostic needed to classify the
failure. The corrected canonical helper retains the diagnostic only in a
private temporary file, emits only its SQLSTATE, migration line number,
bounded failure class, size, and SHA-256, and deletes the raw diagnostic on
exit. The same Script `20` command is the next gate; no separate repair script
is introduced.
