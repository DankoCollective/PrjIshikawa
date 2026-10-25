# Ishikawa Ingestion-Ownership Migration Source Ready

## Disposition

`SOURCE READY` on 2026-10-19 for independent local execution. This record does
not claim that migration `0002` has been applied to EmceeDanko.

## Source identities

- accepted `0001_initial_rag_catalog.sql` SHA-256:
  `3e2f5e61bd8038bc29764024e21b8bec754fad8a282f89abaf6130e345d6380a`
- proposed `0002_align_ingestion_ownership.sql` SHA-256:
  `74b08adb8aac9828ac076744fedfd22619751326c911bf17f1fa8690e01345e4`
- `test_ingestion_ownership_migration.sh` SHA-256:
  `ca9fb1300971c2330f030aba55794a0909448e214b0c74aeb3fe751ad81288c3`

## Accepted local proof

The disposable PostgreSQL `16.15` proof passed:

- the accepted empty `0001` database survived a complete stop/start before
  upgrade to `0002`;
- a fresh database accepted ordered `0001 + 0002`;
- upgrade and fresh schemas produced the identical SHA-256 fingerprint
  `36c7affe53e1dd8164bff70b1ae42da018f45f813fe2b999f1cec062333de745`;
- both contained three schemas, 20 base tables, five active retrieval views,
  and two exact migration-ledger rows;
- document and source-version class columns were absent, while artifact-set
  class/provenance and quarantine remediation columns were present;
- a nonempty legacy `0001` catalog was rejected transactionally and retained
  its exact pre-migration structure;
- one source revision and method profile accepted distinct policy and
  regulation artifact sets;
- changing only the active artifact pointer changed the visible class from
  `regulation` to `policy`;
- duplicate semantic artifacts, run-provenance mismatch, missing quarantine
  subjects, and partial resolution state were rejected by named constraints;
- quarantine resolution required a different successful retry identity and
  the version-1 `successful_retry` code; and
- retrieval retained access to five views and zero base tables, while
  ingestion retained write access to 19 application tables and no migration-
  ledger write access.

The existing migration `0001` regression and the 52-test Ishikawa
configuration-validation suite also passed after `0002` was introduced.

## Safety boundary

The accepted target is known to contain the empty `0001` application catalog.
Migration `0002` requires that exact `0001` checksum and scans every `rag` and
`rag_private` base table other than the migration ledger. Any row blocks the
transaction. This prevents the migration from fabricating canonical registry
or catalog digests for data created under the superseded ownership model.

The proof uses only disposable local databases. It does not contact a target,
change the accepted EmceeDanko database, process corpus content, call a model,
or start a persistent service.

## Independent command

From the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/21_test_ingestion_ownership_migration.sh
```

The required final marker is:

```text
script_21_ingestion_ownership_migration_test=pass
```

The operator confirmed the checksum-identical underlying test before the
numbered wrapper was created. That run is accepted without repetition.
Script `21` is the canonical local-test command going forward; the
checksum-bound target mutation is reserved for Script `22`.
