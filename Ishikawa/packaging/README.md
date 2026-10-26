# Ishikawa application package

This package installs the current Ishikawa application sources and operator
ingestion commands into one host directory. It does not install operating
system packages, initialize PostgreSQL, apply database migrations, start a
service, contact a model endpoint, or copy organizational documents.

Install into a new directory owned by the current operator:

```bash
bash ./install-ishikawa --install-root "$HOME/Documents/Ishikawa"
```

The installer verifies every packaged file before it creates the installation.
It refuses an existing destination so it cannot overwrite operator
configuration, source documents, reports, artifacts, or other state.

After installation, review the YAML files under `config/`, place source PDFs
under `corpus/source/`, and place a reviewed ingestion manifest directly under
`config/ingestion/pending/`. Credentials remain runtime environment values;
they are not stored in this package or in YAML.

The current installed operator commands are:

```text
scripts/ishikawa-create-ingestion-config --validate-only --metadata METADATA.csv
scripts/ishikawa-create-ingestion-config --publish --metadata METADATA.csv
scripts/ishikawa-ingest --validate-only --manifest BATCH.yaml
scripts/ishikawa-ingest --publish --manifest BATCH.yaml
scripts/ishikawa-retrieval-api --check-config
scripts/ishikawa-retrieval-api --check-readiness
scripts/ishikawa-retrieval-api --serve
scripts/ishikawa-log-control status
scripts/ishikawa-observability-retention --check-config
scripts/ishikawa-observability-retention --apply
```

The configuration-creation command is the content-side intake boundary. An
authorized operator fills the installed header-only `config/corpus_metadata.csv`
inside the protected environment. The command requires that metadata to cover
the exact PDF inventory under `corpus/source`, validates class and identifier
contracts, and creates the catalog plus one pending ingestion manifest. Its
terminal output contains only counts and hashes.

The logging-control command works only while the Retrieval API is running and
uses the owner-only local socket under `state/run`. It opens no network port.
Operational logs, content-free metrics, and audit events are separate rotated
JSONL files under the protected `state/logs` directory.

The optional user-level systemd retention service and daily timer are packaged
as final deployment definitions. They invoke the installed retention command
under `~/Documents/Ishikawa`; they do not start the Retrieval API. Installing
and enabling those units is a separate explicit deployment action.

The native Retrieval API unit is also a final user-level systemd definition.
It has no `[Install]` section and therefore remains boot-disabled. It is
started and stopped only by explicit operator commands, passes only the three
named runtime-secret environment variables, restarts after failure, and uses
the installed foreground command's graceful `SIGTERM` cleanup.

The host-mounted Next.js source and explicit `ishikawa-stack` lifecycle command
are included. The exact generic Linux AMD64 Node 24/Next.js image remains a
separate external prerequisite; the application source is never baked into it.
Each permanent web start mounts the source read-only, creates a bounded
ephemeral `.next` tmpfs, runs `next build`, and executes `next start` in that
same container. Stopping the stack removes the container and its generated
build state, so every restart performs a fresh build.

This application package assumes the required native dependencies, the final
PostgreSQL schema, the architecture-matching web image, and any required model
port forwarding already exist on the target host. Installing user systemd unit
files is an explicit deployment action. Nothing in this package is enabled at
boot.
