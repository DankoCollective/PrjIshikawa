# Installed Operator Ingestion

`ishikawa-ingest` is a one-shot operator command. It is not a service and does
not start or stop PostgreSQL, Nomic, port forwarding, or any other dependency.

The installed command derives every path from the product root containing the
executable. For an installation rooted at `~/Documents/Ishikawa`, it uses:

- `config/deployment.yaml` and `config/ingestion_dependencies.yaml` for runtime configuration;
- `config/document_classes.yaml` and `config/document_catalog.yaml` for operator registries;
- `config/ingestion/pending/` for selectable ingestion manifests;
- `corpus/source/` for source PDFs;
- `state/reports/ingestion/` for protected ingestion reports;
- `state/work/` for temporary producer workspaces;
- `state/artifacts/sha256/` for checksum-addressed accepted artifacts; and
- `scripts/ishikawa-produce-artifacts` for extraction through embedding.

The operator surface is deliberately limited:

```text
ishikawa-ingest --validate-only --manifest BATCH.yaml
ishikawa-ingest --publish --manifest BATCH.yaml
```

`BATCH.yaml` must be a plain filename already present directly under the
pending-manifest directory. Absolute paths, parent traversal, subdirectories,
path overrides, database options, endpoint options, and secret-bearing options
are rejected.

The command prints a content-safe `[INGEST]` start marker, a heartbeat at
least every 30 seconds while work is active, and a final pass or blocked
marker. Internal stage output remains protected because it may contain host
paths or dependency diagnostics; the heartbeat never contains document text,
credentials, model output, or raw exceptions. Interruption returns status 130
and is never reported as success.

Credentials are never stored in YAML or accepted as command arguments. The
configured runtime reads `ISHIKAWA_POSTGRESQL_INGEST_PASSWORD` only when it
opens PostgreSQL and reads `ISHIKAWA_NOMIC_API_KEY` only when changed documents
need the live Nomic stage.

Accepted normalized, chunk, and embedding artifacts are retained once under
their SHA-256 identity. Reusing identical artifacts is idempotent. An existing
object whose bytes do not match its filename fails closed and is never
overwritten.

The command does not automatically move a manifest from `pending` to
`completed` or `rejected`. Protected reports and the database publication
result remain authoritative for this first implementation; automated manifest
lifecycle movement requires a separate reviewed decision.
