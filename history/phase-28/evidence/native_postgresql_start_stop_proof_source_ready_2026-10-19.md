# Native PostgreSQL Start/Stop Proof Source Ready — 2026-10-19

## Disposition

Script `19` and its neutral target helper are source-ready and bound to the
accepted Script `18` configuration-validation receipt.

Source identities:

- `19_prove_native_postgresql_start_stop.sh`
  - SHA-256: `3c17961629b6bc9a07038d6bf88cbba7ff9e857cdc5ec33ece89ab2e971124ed`
- `prove-native-database-start-stop`
  - SHA-256: `a869a6b6ad9f999727d83372a6d3ec41435f500a6f55c15c996e3292f5697d2e`
  - bytes: `9098`

The helper requires the exact stopped PostgreSQL `16/main` cluster, canonical
loopback setting, successful full-configuration parse, manual-start policy,
boot-disabled services, free port, and clean shutdown state. It starts only
the cluster instance, waits for readiness through the local Unix socket,
requires one TCP listener at `127.0.0.1:5432`, stops the instance, and proves
the final clean shutdown, free port, and disabled service state.

It executes no SQL, performs no database query, processes no secret, and
changes no package, configuration, database object, application content, or
boot enablement. Its failure cleanup stops the cluster if a partial proof
leaves the instance active.

Local syntax, accepted-receipt, bounded-output, source-jargon, and no-target
validation passed:

```text
native_postgresql_start_stop_proof_source=pass
target_contact=false
service_change=false
sql_execution=false
```

Operator command:

```bash
bash ./phase-28-apisachi-tokuli/scripts/19_prove_native_postgresql_start_stop.sh --prove
```
