# Native PostgreSQL Start-Failure Inspection Source Ready — 2026-10-19

## Disposition

Script `17` and its neutral target helper are source-ready and bound to the
blocked Script `16` receipt.

Source identities:

- `17_inspect_native_postgresql_start_failure.sh`
  - SHA-256: `0f640466bc1feac9542a0ef77aeee5b6fcc845788de6f8fe6dbfe115d3c9ba96`
- `inspect-native-database-start-failure`
  - SHA-256: `c355270ecebfa8838a805149cfa8aef9497c0d4fc6a1ebf92fbfde0fb68491a1`
  - bytes: `11422`

The read-only inspection records:

- exact cluster identity and current cluster/service states;
- bounded systemd load, active, substate, result, exit-code, exit-status, and
  errno facts;
- start policy, listen address, password-encryption setting, and metadata for
  configuration, data, log, runtime, and PID paths;
- effective `postgres` access to the required directories;
- `pg_controldata` shutdown/checksum facts;
- a non-starting PostgreSQL configuration parse probe;
- listener and capacity facts; and
- hashes, line counts, and bounded classifications for the last 200 service
  journal and cluster-log lines.

It emits no raw logs and performs no network access, package change, service
start/stop/restart/enable/disable/reset, database query, database change, or
secret/content read.

Local validation passed:

```text
native_postgresql_start_failure_inspection_source=pass
target_contact=false
service_change=false
```

Operator command:

```bash
bash ./phase-28-apisachi-tokuli/scripts/17_inspect_native_postgresql_start_failure.sh
```

