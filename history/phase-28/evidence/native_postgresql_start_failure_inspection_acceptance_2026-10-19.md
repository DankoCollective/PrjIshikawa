# Native PostgreSQL Start-Failure Inspection Acceptance — 2026-10-19

## Disposition

The operator-executed Script `17` inspection passed and is accepted.

Accepted report:

- `native_postgresql_start_failure_inspection_20261019T143943Z_oQwgmp.txt`
- SHA-256:
  `f929766432d24472ad7ebc6c928bba14400ab075929c434d4e02f72390e23333`

The receipt proves that PostgreSQL remained stopped, boot-disabled, manually
started, and without a port `5432` listener. Cluster control state is cleanly
shut down with data checksums enabled. Required configuration, data, log, and
runtime paths exist with usable ownership, permissions, and effective
`postgres` access. `/var` and `/run` capacity are sufficient. The non-starting
configuration probe failed, and both bounded journal and cluster-log evidence
classify the cause as `configuration_error`.

## Candidate cause reviewed after inspection

The accepted cluster has the configured value `127.0.0.1`. The exact captured
Ubuntu package `postgresql-client-common=257build1.1` has SHA-256
`696255bc15e9736edfcb8f7d0309deaf35d761233bd26e2db14d2ae8660a9602`.
Its `PgCommon::quote_conf_value` implementation treats any value matching
`^-?[\d.]+$` as numeric and leaves it unquoted. That source behavior made the
following serialization a reasonable candidate cause:

```text
listen_addresses = 127.0.0.1
```

PostgreSQL rejects that unquoted multi-dot value during configuration parsing.
However, the later accepted Script `18` receipt proved that the target's
configuration contents were already canonical and were unchanged when the
configuration parse passed. The package-source behavior therefore does not
prove the target's original failure cause, and the earlier exact-cause claim
is withdrawn.

The bounded validation action canonicalized the one setting as:

```text
listen_addresses = '127.0.0.1'
```

and validated the complete configuration with the PostgreSQL server binary
while the cluster remained stopped. Because the file checksum did not change,
a separate start/stop-only proof is required before any database work.
