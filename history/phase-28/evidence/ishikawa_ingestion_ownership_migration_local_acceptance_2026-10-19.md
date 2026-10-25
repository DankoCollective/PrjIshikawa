# Ishikawa Ingestion-Ownership Migration Local Acceptance

## Disposition

The operator-confirmed local migration `0002` test is accepted on 2026-10-19.

The operator executed the underlying disposable test directly and confirmed
its required `ingestion_ownership_migration_test=pass` marker. The repository
should have exposed that gate through a numbered operator script. Canonical
Script `21` now checksum-binds and runs the exact helper and migration sources
used by the successful test. The accepted underlying helper SHA-256 is:

```text
ca9fb1300971c2330f030aba55794a0909448e214b0c74aeb3fe751ad81288c3
```

The operator does not need to repeat the accepted test merely because the
numbered wrapper was added afterward.

Canonical Script `21` was then executed locally and produced both the
underlying and wrapper pass markers. Its SHA-256 is:

```text
dc79b20b482f5f3bd119098851058829b658a1ccab8dff2116b19a979bd00981
```

## Canonical gate

Future executions use:

```bash
bash ./phase-28-apisachi-tokuli/scripts/21_test_ingestion_ownership_migration.sh
```

Its final wrapper marker is:

```text
script_21_ingestion_ownership_migration_test=pass
```

Script `21` is local-only and performs no target contact or mutation. The
future checksum-bound EmceeDanko application of migration `0002` is reserved
for Script `22`.
