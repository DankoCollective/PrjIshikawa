# Ishikawa v1.3 Operating Surface

## Purpose

This inventory identifies the accounts, database roles, services, installed
commands, paths, listeners, and permissions that an Ishikawa v1.3 deployment
uses. It describes the shipped application without authorizing installation,
service enablement, database creation, or target contact.

## Canonical installation path

The accepted Tech installation path is:

```text
%h/Documents/Ishikawa
```

The packaged systemd user units contain that path. The application installer
can copy the application to another new absolute path, but the shipped units
must not be used unchanged at another location.

## Host and service accounts

Ishikawa creates no Linux user, group, service account, sudo rule, or login.
The three packaged systemd definitions are user units and run as the operator
who installs them. The application installer only creates the selected product
directory; it does not copy units into the user manager, enable them, or start
them.

PostgreSQL and Docker are host prerequisites. The stack command starts and
stops the existing `postgresql@16-main.service` through attended `sudo` and
runs the web container through the operator's Docker access. It does not create
or change the PostgreSQL operating-system account or Docker group membership.

## PostgreSQL version and roles

Database schema version `5` is Ishikawa's relational-layout contract. It is
recorded in `rag.schema_migrations` with the SHA-256 of the shipped
`schema.sql`. It is not PostgreSQL server version 5; the accepted server is
PostgreSQL 16 with pgvector.

The schema installer requires three distinct roles that already exist. Their
identifiers are operator-supplied through `--owner-role`, `--ingest-role`, and
`--retrieval-role`; the package does not hard-code their names or create roles
or credentials. Script 05 uses `rag_owner`, `rag_ingest`, and `rag_retrieval`
for its disposable qualification database. The functional roles are:

- The owner role owns the `rag`, `rag_private`, and `rag_search` schemas and
  all objects created in them. The application does not use this role during
  ordinary retrieval or ingestion.
- The ingestion role has schema usage on all three schemas, usage on the SHA-256
  domain, and `SELECT`, `INSERT`, `UPDATE`, and `DELETE` on ingestion tables in
  `rag` and `rag_private`. It cannot insert, update, or delete the schema
  migration ledger. It also has read access to `rag_search`.
- The retrieval role has usage and read-only `SELECT` access only on
  `rag_search`. The Retrieval API therefore cannot ingest, publish, retire, or
  mutate documents.

`PUBLIC` receives no schema, table, or sequence privileges from the package.
Role creation, login posture, password issuance, database ownership, and
credential delivery are deployment decisions outside the schema installer.

## Packaged systemd definitions

| Unit | Type and purpose | Start posture | Allowed writes |
|---|---|---|---|
| `ishikawa-retrieval-api.service` | User service running `scripts/ishikawa-retrieval-api --serve` | No `[Install]` section; cannot be boot-enabled through the unit | `state/logs` and `state/run` only |
| `ishikawa-observability-retention.service` | User oneshot running `scripts/ishikawa-observability-retention --apply` | Runs only when invoked or triggered by the timer | `state/logs` only |
| `ishikawa-observability-retention.timer` | Optional daily user timer | Enablement is a separate explicit operator decision | Starts the retention oneshot only |

The service definitions set `NoNewPrivileges=yes`, private temporary storage,
and a strict read-only system view. The Retrieval API additionally uses a
read-only home view except for its two declared write paths, an owner-only
umask, bounded start/stop timeouts, and restart-on-failure. It receives only
the names of the Gemma, Nomic, and PostgreSQL retrieval credential variables;
the unit files contain no credential values or environment file.

The web UI is not a systemd service. `scripts/ishikawa-stack` starts one
ephemeral `ishikawa-web` container with the installed source mounted read-only.
The ingestion workflow is a one-shot command, not a service.

## Installed commands

No command is copied into a global `PATH`. Commands remain beneath the
installation root:

- `scripts/ishikawa-stack start|status|stop` controls PostgreSQL, Retrieval
  API, and web UI in dependency order while preserving boot-disabled posture.
- `scripts/ishikawa-retrieval-api --check-config|--check-readiness|--serve`
  validates or runs the native API.
- `scripts/ishikawa-ingest --validate-only|--publish --manifest BATCH.yaml`
  validates or atomically publishes one reviewed ingestion batch.
- `scripts/ishikawa-produce-artifacts` is the ingestion pipeline's installed
  extraction, normalization, chunking, tokenization, and embedding helper.
- `scripts/ishikawa-log-control` inspects or changes bounded temporary verbose
  logging through an owner-only local socket.
- `scripts/ishikawa-observability-retention --check-config|--apply` validates
  or applies local telemetry retention.

The release bundle also contains two deployment commands. They remain in the
verified release bundle rather than being copied into the installed
application or a global `PATH`:

- `application/install-ishikawa` verifies and installs a new application tree;
  it does not merge with an existing installation.
- `database/install-schema` installs the checksum-bound schema into an empty
  selected database; it is not an upgrade tool.

## Network and credential boundary

The accepted default listeners are loopback-only: web `127.0.0.1:3000`,
Retrieval API `127.0.0.1:1384`, and PostgreSQL `127.0.0.1:5432`. Gemma and
Nomic endpoint locations are read from YAML and may be reached through
operator-managed forwarding. Ishikawa does not create those forwards.

Credentials are protected environment values, not YAML fields or package
content. The stack command imports only the three named Retrieval API values
into the user manager long enough to start the service, then removes the
manager copies. Ingestion reads its PostgreSQL and Nomic values only for the
one-shot run.

## Authoritative implementation files

- Units: `Ishikawa/packaging/systemd/`
- Stack behavior: `Ishikawa/scripts/ishikawa-stack`
- Database grants: `Ishikawa/packaging/database/schema.sql`
- Schema installer: `Ishikawa/packaging/database/install-schema`
- Installed service guide: `Ishikawa/docs/SERVICE_OPERATIONS.md`
- Installed stack guide: `Ishikawa/docs/STACK_CONTROL.md`

