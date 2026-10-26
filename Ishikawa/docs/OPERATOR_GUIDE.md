# Ishikawa Operator Guide

## Purpose

This guide covers routine operation of an installed Ishikawa v1 application.
The examples assume the default installation root:

```text
~/Documents/Ishikawa
```

Ishikawa is operator-started. Nothing in the application stack is enabled at
boot. Model forwarding is also an external operator action: the configured
Gemma and Nomic endpoints must already be reachable before Ishikawa starts.

## Runtime components

One lifecycle command controls the three long-running application components:

1. native PostgreSQL on `127.0.0.1:5432`;
2. the native Ishikawa Retrieval API on `127.0.0.1:1384`; and
3. the host-mounted Next.js Chat UI container on `127.0.0.1:3000`.

The ingestion command is a separate, one-shot workflow. It is not a service
and is not started by the lifecycle command.

## Before startup

Confirm all of the following:

- the installation exists at `~/Documents/Ishikawa`;
- the PostgreSQL cluster, Retrieval API, and web container are stopped;
- the exact `node-next-runtime:24.22.1-next16.4.3-react19.2.9-amd64` image is local;
- the Retrieval API user unit is installed;
- the configured Gemma endpoint on port `8000` is reachable;
- the configured Nomic endpoint on port `8001` is reachable; and
- the three runtime credentials are available to the operator.

Do not store credentials in YAML, command arguments, shell-history text, or
the corpus.

## Start Ishikawa

Run this block from the application host. The prompts do not echo the values.
The variables are removed from the current shell after the start attempt.

```bash
cd "$HOME/Documents/Ishikawa"

read -rsp 'Gemma API key: ' ISHIKAWA_GEMMA_API_KEY
printf '\n'
read -rsp 'Nomic API key: ' ISHIKAWA_NOMIC_API_KEY
printf '\n'
read -rsp 'PostgreSQL retrieval password: ' ISHIKAWA_POSTGRESQL_PASSWORD
printf '\n'

export ISHIKAWA_GEMMA_API_KEY
export ISHIKAWA_NOMIC_API_KEY
export ISHIKAWA_POSTGRESQL_PASSWORD

if ./scripts/ishikawa-stack start; then
  unset ISHIKAWA_GEMMA_API_KEY ISHIKAWA_NOMIC_API_KEY ISHIKAWA_POSTGRESQL_PASSWORD
  ./scripts/ishikawa-stack status
else
  start_status=$?
  unset ISHIKAWA_GEMMA_API_KEY ISHIKAWA_NOMIC_API_KEY ISHIKAWA_POSTGRESQL_PASSWORD
  false
fi
```

A clean start ends with:

```text
ishikawa_stack=start;state=ready;boot_enabled=false
ishikawa_stack=status;state=ready;boot_enabled=false
```

The command validates configuration, ports, exact image identity, service
posture, and required credentials before starting the stack. The web stage
mounts source read-only, builds into a bounded ephemeral `.next` tmpfs, emits
progress while building, and runs `next start`. It waits for readiness between
layers. A failed start removes its container and rolls back every component
started by that attempt.

## Use and verify the application

Open the Chat UI at:

```text
http://127.0.0.1:3000
```

The following checks are content-free:

```bash
cd "$HOME/Documents/Ishikawa"
./scripts/ishikawa-stack status
curl --fail --silent --show-error http://127.0.0.1:1384/live
curl --fail --silent --show-error http://127.0.0.1:1384/ready
curl --fail --silent --show-error http://127.0.0.1:3000/api/live
curl --fail --silent --show-error http://127.0.0.1:3000/api/ready
```

`/live` proves that a listener responds. `/ready` also proves that its required
dependencies and active searchable corpus are ready. A live but not-ready
service must not be treated as operational.

## Stop Ishikawa

```bash
cd "$HOME/Documents/Ishikawa"
./scripts/ishikawa-stack stop
```

A clean stop ends with:

```text
ishikawa_stack=stop;state=stopped;boot_enabled=false
```

The command stops and removes the web container, then stops the Retrieval API
and PostgreSQL in reverse order. Removing the container deletes generated web
build state, so every later start performs a fresh build. The command also
removes any named credential copies from the user service manager. Closing
model forwarding remains the operator's external action.

## Ingest documents

Prepare an initial protected-corpus ingestion run in this order:

1. Place supported PDF files beneath `corpus/source/`.
2. Add any approved class identifiers to `config/document_classes.yaml`.
3. Fill `config/corpus_metadata.csv` with one reviewed row per PDF.
4. Run the configuration creator in validation mode.
5. Publish the catalog and pending manifest only after that validation passes.
6. Validate the generated ingestion batch.
7. Review the terminal result and protected ingestion report.
8. Publish the same batch only after ingestion validation passes.

```bash
cd "$HOME/Documents/Ishikawa"
./scripts/ishikawa-create-ingestion-config \
  --validate-only \
  --metadata "$PWD/config/corpus_metadata.csv" \
  --manifest-name initial-corpus.yaml

./scripts/ishikawa-create-ingestion-config \
  --publish \
  --metadata "$PWD/config/corpus_metadata.csv" \
  --manifest-name initial-corpus.yaml
```

The metadata file and generated catalog/manifest stay inside the protected
environment. The command reports only document count and SHA-256 identities;
it does not print source paths, display names, or document content.

The manifest lists only affected documents and explicit retirements. It does
not restate the complete corpus. Source paths are relative to `corpus/source/`.
Source symlinks, absolute paths, and parent traversal are rejected.

Validation requires the ingestion PostgreSQL credential. Publication of new
or changed content also requires the Nomic credential and a reachable Nomic
endpoint. PostgreSQL must be running. The easiest operating posture is to run
ingestion while the Ishikawa stack is ready.

Validate a pending batch:

```bash
cd "$HOME/Documents/Ishikawa"
read -rsp 'PostgreSQL ingestion password: ' ISHIKAWA_POSTGRESQL_INGEST_PASSWORD
printf '\n'
export ISHIKAWA_POSTGRESQL_INGEST_PASSWORD
./scripts/ishikawa-ingest --validate-only --manifest BATCH.yaml
validation_status=$?
unset ISHIKAWA_POSTGRESQL_INGEST_PASSWORD
```

Publish a validated batch:

```bash
cd "$HOME/Documents/Ishikawa"
read -rsp 'Nomic API key: ' ISHIKAWA_NOMIC_API_KEY
printf '\n'
read -rsp 'PostgreSQL ingestion password: ' ISHIKAWA_POSTGRESQL_INGEST_PASSWORD
printf '\n'
export ISHIKAWA_NOMIC_API_KEY
export ISHIKAWA_POSTGRESQL_INGEST_PASSWORD
./scripts/ishikawa-ingest --publish --manifest BATCH.yaml
publish_status=$?
unset ISHIKAWA_NOMIC_API_KEY ISHIKAWA_POSTGRESQL_INGEST_PASSWORD
```

One manifest is one atomic publication boundary. Only listed additions,
revisions, reprocessing requests, and retirements are processed. Unchanged
documents are reused. If any required entry fails or is quarantined, none of
that manifest's changes becomes searchable.

The command does not automatically move manifests among `pending`,
`completed`, and `rejected`. The operator moves a manifest only after reviewing
the protected report and database outcome.

## Quarantine and remediation

A quarantined document is reported through a nonzero terminal result and a
stable reason code. An actual publication attempt also records content-free
quarantine state in PostgreSQL and bounded private evidence under
`state/quarantine/`. The original PDF is not moved or deleted.

For remediation:

1. read the protected report under `state/reports/ingestion/`;
2. identify the stable rejection or quarantine reason;
3. correct the source document, registry, catalog, or manifest as appropriate;
4. create a new ingestion attempt; and
5. validate before publishing again.

Do not edit database rows or retained artifacts to make a failed run appear
successful. A corrected run is linked to the immutable earlier history.

## Logs and retention

The Retrieval API writes protected JSON Lines files under `state/logs/`:

- `retrieval.jsonl` for operational and permitted diagnostic events;
- `metrics.jsonl` for content-free measurements; and
- `audit.jsonl` for logging-control actions.

Default retention is 30 days for retrieval logs, 30 days for metrics, and 90
days for audit records. Check or apply retention with:

```bash
cd "$HOME/Documents/Ishikawa"
./scripts/ishikawa-observability-retention --check-config
./scripts/ishikawa-observability-retention --apply
```

Verbose logging is temporary, explicit, reason-bound, and scoped. Check its
state with:

```bash
./scripts/ishikawa-log-control status
```

Disable it immediately when no longer needed:

```bash
./scripts/ishikawa-log-control disable
```

## Operating boundaries

- Do not expose ports `3000`, `1384`, or `5432` beyond loopback without a new
  reviewed access-control design.
- Do not put secrets in product configuration or documents.
- Do not call Gemma or Nomic directly from the browser.
- Do not grant the Retrieval API write access to PostgreSQL.
- Do not manually edit content-addressed artifacts.
- Do not treat `/live` as a substitute for `/ready`.
- Do not claim individual user identity; v1 has no application login or
  per-user permissions.
