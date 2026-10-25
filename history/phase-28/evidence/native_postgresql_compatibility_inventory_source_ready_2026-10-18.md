# Native PostgreSQL Compatibility Inventory Source Ready

## Purpose

Script `09` is the replacement gate after the native package compatibility
block. It streams a neutral read-only helper to EmceeDanko and records the
exact Ubuntu `libllvm19` candidate required to evaluate the signed PGDG
PostgreSQL 16 server that provides JIT virtual version `19`.

The helper performs no apt update, download, install, database action, service
action, configuration change, sudo operation, secret/content read, or target
file write.

## Bound Evidence

Script `09` binds:

- compatibility-blocked bundle SHA-256:
  `d091792ace6a1f5b1ac76d686e2464f52e61240c47e44eaf74670eaef0dfbff5`;
- second Script `08` report SHA-256:
  `a26280559850c154594a8ec4b32a6a57cdd8ed828749796cc9b337edca4842e4`;
- Ubuntu PostgreSQL server control evidence providing
  `postgresql-16-jit-llvm (= 17)`; and
- PGDG pgvector control evidence breaking
  `postgresql-16-jit-llvm (<< 19)`.

The target response must provide the exact `libllvm19` candidate version,
architecture, source, archive path, size, SHA-256, control-record hash,
relationship hash, apt-metadata age, and `/var` capacity. Raw package control
text and SSH errors are not retained.

## Local Validation

Syntax and `--validate-only` pass without target contact.

- Script `09` SHA-256:
  `ff16ba2601da152df8246700024dea734b6937b6bdfc9d86f357d979552e8c3a`;
- neutral helper SHA-256:
  `40324547594402038f796bcb10b37f5cb0298882e0ae130b6b097bddbb4a2967`.

The operator runs from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/09_run_native_postgresql_compatibility_inventory.sh
```

The returned exact coordinate must be reviewed with the signed PGDG
PostgreSQL server coordinate and pass the pre-download advisory gate before a
new package payload is downloaded or bundled.
