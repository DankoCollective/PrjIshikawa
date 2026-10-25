# Native PostgreSQL Application Database Configuration Acceptance — 2026-10-19

## Disposition

The operator-executed corrected Script `16` receipt is accepted.

Accepted report:

- `native_postgresql_application_database_configuration_20261019T154305Z_XauvNL.txt`
- SHA-256:
  `6b8677bb13d66dcb0e55d2f2be6bbdfd8a7f03a9456faa6c3348ebd7e908711f`

Accepted source identities recorded by the receipt:

- `16_configure_native_postgresql_application_database.sh`:
  `b00f170066e61a6a8b05e2a7a70c91f3721fa634df3fd9178f9eae4a43f519c0`
- `configure-native-application-database`:
  `9a165849673f11cccd6a57557aa418c4c343adf3edf7ea10e73c7ba066132b23`

The receipt proves:

- the complete PostgreSQL configuration parsed before secret entry or SQL;
- the native `16/main` cluster started, became ready, and listened only on
  `127.0.0.1:5432`;
- empty UTF-8 database `rag_catalog` exists with non-login owner `rag_owner`;
- separate unprivileged login roles `rag_ingest` and `rag_retrieval` exist;
- role passwords use PostgreSQL SCRAM-SHA-256 storage and were neither retained
  nor emitted by the helper;
- public database access is revoked and both login roles currently have only
  `CONNECT` at the database level;
- `rag_retrieval` defaults transactions to read-only;
- pgvector `0.8.7` is enabled in `rag_catalog`;
- the application relation count is zero and no application schema, table,
  index, or content was created;
- PostgreSQL was stopped after verification, port `5432` is free, and the
  service remains inactive and disabled at boot; and
- remote temporary files and the reusable SSH control connection were cleaned
  up successfully.

The database-bootstrap gate is complete. Scripts `17`–`19` remain historical
troubleshooting evidence and are not part of the normal workflow. The next
gate is the reviewed, plain-SQL application schema and privilege migration; it
must not re-create the cluster, database, roles, or extension.
