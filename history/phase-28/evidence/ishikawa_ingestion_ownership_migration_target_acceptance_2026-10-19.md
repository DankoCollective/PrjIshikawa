# Ishikawa ingestion-ownership migration target acceptance

Date: 2026-10-19

## Outcome

Migration `0002_align_ingestion_ownership` was applied successfully to the
existing empty EmceeDanko `rag_catalog` database by operator-executed Script
`22`.

The database operation is accepted. It does not need to be rerun.

## Accepted target facts

- Target: `EmceeDanko`, Ubuntu `24.04`, `amd64`.
- PostgreSQL: `16.15`; pgvector: `0.8.7`.
- Required prior migration `0001_initial_rag_catalog` matched SHA-256
  `3e2f5e61bd8038bc29764024e21b8bec754fad8a282f89abaf6130e345d6380a`.
- Migration `0002_align_ingestion_ownership` matched SHA-256
  `74b08adb8aac9828ac076744fedfd22619751326c911bf17f1fa8690e01345e4`.
- The remote helper exited `0` and emitted exactly one
  `ingestion_ownership_migration=pass` marker and no blocked marker.
- The migration action was `apply`, followed by a successful complete
  PostgreSQL stop/start persistence check.
- The database retains three schemas, 20 base tables, and five active-search
  views.
- The migration ledger contains exactly the accepted `0001` and `0002`
  records.
- Classification ownership now belongs to the processed artifact set, and
  the same immutable source revision can be reprocessed under another class.
- Quarantine records support manifest-entry identity and explicit linkage to
  a successful retry.
- Retrieval retains access to five search views and no base tables or write
  operations. Ingestion retains the accepted 20-table read and 19-table write
  boundary and cannot change the migration ledger.
- The catalog still contains zero corpus rows. No document, chunk, citation,
  relationship, or embedding content was written.
- No ANN index was created.
- PostgreSQL was returned to the stopped, inactive, boot-disabled state.
- Temporary target files were removed and the SSH control session closed.

## Receipt

Local receipt:

`local/reports/native-postgresql-ingestion-ownership-migration/native_postgresql_ingestion_ownership_migration_20261019T203028Z_JRDpdJ.txt`

Receipt SHA-256:

`4d5d065a9a941bb11948fdfb24f552b4961602a4b8c9936805e93fe1aa41ffa1`

Executed source identities recorded in the receipt:

- Script `22`:
  `e6b27c89a3a81f715b0d944890bf94240a3fa2713471c82ce367da74565457a5`
- Neutral target helper:
  `ccde679467f0c19535a7cefd5c976f2ee0159183587cad1fb8838261e66201a5`

## Reporting-only defect and disposition

The target work and every required target fact passed, but the original local
wrapper ended with `remote_output_contract=blocked`. One successful helper
line used this malformed structured-output form:

`ownership_column_contract=legacy_absent_4;new_present_9;digest_domain_columns_2`

The second and third semicolon-delimited fields lacked their own `key=value`
names. The wrapper therefore omitted that line from its copied report and
correctly rejected the formatting contract. This occurred only after the
remote helper had applied the migration, repeated the full verification after
a PostgreSQL restart, stopped PostgreSQL, and emitted its pass marker. The
wrapper's independent required-fact check returned `pass`, proving the exact
verification line was present in the fetched result.

The canonical helper now emits:

`legacy_ownership_column_count=0;new_ownership_column_count=9;digest_domain_column_count=2`

The canonical wrapper expects that corrected form, and its no-target source
validation passes. This changes reporting only; it does not change migration
`0002` or require another target run.

## Next gate

Implement and locally validate the incremental ingestion writer against the
accepted `0001 + 0002` database contract. This is application implementation,
not another PostgreSQL foundation repair.
