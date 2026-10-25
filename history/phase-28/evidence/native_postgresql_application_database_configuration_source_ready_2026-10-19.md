# Native PostgreSQL Application Database Configuration Source Ready — 2026-10-19

## Disposition

Script `16` and its neutral target helper are source-ready and bound to the
accepted Script `15` cluster receipt.

Source identities:

- `16_configure_native_postgresql_application_database.sh`
  - SHA-256: `b00f170066e61a6a8b05e2a7a70c91f3721fa634df3fd9178f9eae4a43f519c0`
- `configure-native-application-database`
  - SHA-256: `9a165849673f11cccd6a57557aa418c4c343adf3edf7ea10e73c7ba066132b23`
  - bytes: `19731`

Default configurable identifiers are:

- database: `rag_catalog`;
- non-login owner: `rag_owner`;
- ingestion login: `rag_ingest`; and
- retrieval login: `rag_retrieval`.

The guarded configuration:

- requires explicit `--configure` authorization;
- re-verifies the exact stopped/manual-start PostgreSQL `16/main` cluster;
- requires the canonical quoted loopback setting and makes the PostgreSQL
  server parse the complete configuration before any start or password prompt;
- starts the cluster, proves readiness and the single loopback listener, and
  only then requests application-role passwords;
- privately prompts on the target TTY for nonempty ingestion and retrieval
  passwords and their confirmations without imposing a project-specific
  password length or complexity policy;
- never places either password in an argument, environment variable, result,
  repository file, target helper file, or retained temporary file;
- emits bounded systemd state if startup fails and stops any partially active
  cluster through failure cleanup;
- creates one empty UTF-8 database owned by the non-login owner role;
- creates separate unprivileged ingestion and retrieval login roles using
  SCRAM-SHA-256 password storage;
- revokes public database access and grants both login roles only `CONNECT`
  until reviewed migrations create the application schema and exact grants;
- adds a default read-only transaction safeguard to the retrieval role;
- enables pgvector `0.8.7` in the empty database;
- validates identities, attributes, privileges, extension version, empty
  application-relation state, and secret non-persistence;
- rolls back newly created objects if an incomplete configuration fails; and
- stops the cluster and preserves boot-disabled/manual-start operation.

Local validation passed:

```text
native_postgresql_application_database_configuration_source=pass
target_contact=false
application_database_configuration=false
database_name=rag_catalog
owner_role=rag_owner
ingest_role=rag_ingest
retrieval_role=rag_retrieval
```

Operator command:

```bash
bash ./phase-28-apisachi-tokuli/scripts/16_configure_native_postgresql_application_database.sh --configure
```

