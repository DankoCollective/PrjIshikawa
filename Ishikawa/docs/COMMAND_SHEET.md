# Ishikawa Command Sheet

All commands assume the default installation root.

## Start the complete stack

Gemma and Nomic forwarding must already be active.

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

Expected final status:

```text
ishikawa_stack=status;state=ready;boot_enabled=false
```

## Status, health, and UI

```bash
cd "$HOME/Documents/Ishikawa"
./scripts/ishikawa-stack status
curl --fail --silent --show-error http://127.0.0.1:1384/live
curl --fail --silent --show-error http://127.0.0.1:1384/ready
curl --fail --silent --show-error http://127.0.0.1:3000/api/live
curl --fail --silent --show-error http://127.0.0.1:3000/api/ready
```

Open:

```text
http://127.0.0.1:3000
```

## Stop the complete stack

```bash
cd "$HOME/Documents/Ishikawa"
./scripts/ishikawa-stack stop
```

## Validate an ingestion batch

`BATCH.yaml` must already be directly under `config/ingestion/pending/`.

```bash
cd "$HOME/Documents/Ishikawa"
read -rsp 'PostgreSQL ingestion password: ' ISHIKAWA_POSTGRESQL_INGEST_PASSWORD
printf '\n'
export ISHIKAWA_POSTGRESQL_INGEST_PASSWORD
./scripts/ishikawa-ingest --validate-only --manifest BATCH.yaml
validation_status=$?
unset ISHIKAWA_POSTGRESQL_INGEST_PASSWORD
```

## Publish an ingestion batch

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

## Retrieval configuration check

This reads configuration but does not open listeners or contact dependencies.

```bash
cd "$HOME/Documents/Ishikawa"
./scripts/ishikawa-retrieval-api --check-config
```

## Retrieval readiness diagnostic

This requires PostgreSQL to be running, both configured model endpoints to be
reachable, and the three protected runtime variables to be exported. It emits
only `pass` or `blocked` for configuration, storage, PostgreSQL, Gemma, and
Nomic.

```bash
cd "$HOME/Documents/Ishikawa"
./scripts/ishikawa-retrieval-api --check-readiness
```

The stack start command runs this diagnostic automatically before it starts
the Retrieval API. A blocked component is therefore named in the startup
output without revealing credentials or application content.

## Logging controls

```bash
cd "$HOME/Documents/Ishikawa"
./scripts/ishikawa-log-control status
./scripts/ishikawa-log-control disable
```

Temporary service-scoped verbose logging:

```bash
./scripts/ishikawa-log-control enable \
  --reason approved_diagnostic \
  --duration-seconds 900 \
  --scope service
```

Temporary request-scoped verbose logging:

```bash
./scripts/ishikawa-log-control enable \
  --reason approved_diagnostic \
  --duration-seconds 900 \
  --request-id OPAQUE_REQUEST_ID
```

## Log retention

```bash
cd "$HOME/Documents/Ishikawa"
./scripts/ishikawa-observability-retention --check-config
./scripts/ishikawa-observability-retention --apply
```

## Retrieval service journal

```bash
journalctl --user --unit ishikawa-retrieval-api.service --since today
```

Do not paste credentials, authorization headers, document content, prompts,
or database values into support commands or retained terminal output.
