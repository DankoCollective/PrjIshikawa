# Native PostgreSQL Cluster Initialization Acceptance — 2026-10-19

## Disposition

The operator-executed Script `15` receipt is accepted.

Accepted report:

- `native_postgresql_cluster_initialization_20261019T142059Z_jfuzlm.txt`
- SHA-256:
  `4e94ef5299ee2980da0e3b5332259d97e900708412dbd81a5ebacb555aeb9a5c`

The receipt proves:

- exactly one native PostgreSQL cluster exists as `16/main`;
- its distribution-managed data directory is
  `/var/lib/postgresql/16/main`, owned by `postgres:postgres` with mode `0700`;
- the cluster uses UTF-8 and data-page checksums;
- local socket authentication is peer and host authentication is
  SCRAM-SHA-256;
- the configured address and port are `127.0.0.1:5432`;
- startup is manual, the cluster is shut down, port `5432` is free, and the
  PostgreSQL service remains inactive and boot-disabled;
- no application database, role, schema, pgvector extension instance, or
  secret was created; and
- remote temporary files and the reusable SSH control connection were cleaned
  up successfully.

The cluster-initialization gate is complete. A separately authorized
application-database configuration may temporarily start this cluster, create
the empty database and isolated roles, enable pgvector in that database, then
return the cluster to its stopped/manual-start state.

