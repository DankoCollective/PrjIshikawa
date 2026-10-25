# Native PostgreSQL Loopback Configuration Repair Source Ready — 2026-10-19

## Disposition

Script `18` and its neutral target helper are source-ready and bound to the
accepted Script `17` inspection receipt.

Source identities:

- `18_repair_native_postgresql_loopback_configuration.sh`
  - SHA-256: `580895b16e7271da5588528303e251b28baa0d1d33d12a0b37b4b6015a8c46e4`
- `repair-native-database-loopback-configuration`
  - SHA-256: `f2cbb7b518daed2418b386ef59d2ce446a5749f7fd0069df112998d7bc366f5a`
  - bytes: `9951`

The helper fails closed unless the exact stopped PostgreSQL `16/main` cluster,
manual-start policy, package versions, configuration identity, free listener,
clean shutdown state, exactly one active `listen_addresses` assignment, and
an effective value of exactly `127.0.0.1` are present. It creates a
same-directory candidate, rewrites only that assignment to the canonical
quoted IPv4 value, preserves a trailing comment when present, preserves
owner/group/mode, proves all non-target lines unchanged, validates the full
candidate configuration as `postgres`, atomically installs it, and repeats
validation against the final path.

It does not start, stop, restart, enable, disable, or reset PostgreSQL. It does
not query or change a database, process a secret, access the network, or change
a package. The cluster remains stopped and port `5432` remains free.

Local syntax, bounded-output, source-jargon, accepted-receipt, and no-target
validation passed:

```text
native_postgresql_loopback_configuration_repair_source=pass
target_contact=false
configuration_change=false
identified_cause=unquoted_ipv4_listen_address_written_by_configuration_helper
```

Operator command:

```bash
bash ./phase-28-apisachi-tokuli/scripts/18_repair_native_postgresql_loopback_configuration.sh --repair
```
