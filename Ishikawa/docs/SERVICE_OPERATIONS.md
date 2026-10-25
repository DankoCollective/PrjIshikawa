# Ishikawa service operations

## Runtime boundary

The Retrieval API is a native Python process that listens on the configured
loopback address, which defaults to `127.0.0.1:1384`. It is reachable only by
other processes on the same host. The browser calls the Next.js server, and
the Next.js server calls the Retrieval API.

There is no application login, user account, role, or per-document permission
layer in this first single-host version. PostgreSQL independently limits the
API to the read-only `rag_retrieval` database role. Anyone who can run a local
process as an allowed host user may attempt to call the API, so non-loopback
exposure requires a separately reviewed authorization design.

## Retrieval API command

The installed command accepts only these modes:

```text
scripts/ishikawa-retrieval-api --check-config
scripts/ishikawa-retrieval-api --check-readiness
scripts/ishikawa-retrieval-api --serve
scripts/ishikawa-retrieval-api --help
```

`--check-config` validates runtime configuration without reading credentials,
opening a listener, or contacting PostgreSQL, Gemma, or Nomic.
`--check-readiness` reads the three protected runtime variables and checks the
configuration snapshot, protected storage, PostgreSQL corpus, Gemma health,
and Nomic health without opening a listener. It prints only `pass` or
`blocked` for those five named components. `--serve` runs the listener in the
foreground. `SIGINT` or `SIGTERM` causes bounded shutdown and cleanup.

The user service definition has no `[Install]` section and therefore cannot be
enabled at boot. It passes only the names of the three required protected
environment variables. Credential values are not stored in YAML or in the
package.

## Health and readiness

`GET /live` proves only that the listener responds. `GET /ready` verifies the
loaded configuration identities, protected state directories, read-only
PostgreSQL access with active searchable content, and configured Gemma and
Nomic health endpoints. The public response is content-free and reports only
`ready` or `not-ready`.

The stack command runs the content-free component readiness check before it
starts the Retrieval API. A blocked start therefore identifies whether the
failure is configuration, storage, PostgreSQL, Gemma health, or Nomic health.
The public HTTP response remains intentionally content-free.

## Logging control

The API writes protected JSON Lines files under `state/logs`:

- `retrieval.jsonl` for operational and permitted diagnostic events;
- `metrics.jsonl` for content-free measurements; and
- `audit.jsonl` for logging-control actions.

The default profile records operational fields. Debug may add allowlisted
content-free diagnostic fields. Verbose content capture is temporary,
explicit, reason-bound, and scoped to the service or one opaque request. It is
never persisted as the base profile.

The running API owns an owner-only Unix-domain control socket. The installed
control command accepts:

```text
scripts/ishikawa-log-control status
scripts/ishikawa-log-control disable
scripts/ishikawa-log-control enable --reason REASON_CODE --duration-seconds N --scope service
scripts/ishikawa-log-control enable --reason REASON_CODE --duration-seconds N --request-id OPAQUE_REQUEST_ID
```

Credentials, authorization headers, connection strings, private keys, raw
exceptions, database values, embedding vectors, and environment dumps are not
accepted log fields.

## Retention

The retention command validates the configured limits and can apply them to
the protected local log files:

```text
scripts/ishikawa-observability-retention --check-config
scripts/ishikawa-observability-retention --apply
```

The packaged user timer is optional and boot-disabled until an operator
explicitly installs and enables it. The complete application remains
operator-started through `scripts/ishikawa-stack`; no unit starts the
Retrieval API automatically.
