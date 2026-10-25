# Ishikawa Retrieval API Service Contract

## Identity and ownership

The frozen service name is **Ishikawa Retrieval API**. It is a separately run
native Python process inside the Ishikawa package for v1. It is not a separate
product, repository, installation, or independently branded backend.

The service starts on demand. Its default listener is `127.0.0.1:1384`, with
the bind address and port remaining deployment configuration. The Ishikawa
Next.js server is its intended client; browsers do not call it directly.

## Orchestration order

One already decoded and validated chat request follows this fail-closed order:

1. scan the current question and bounded conversation for direct injection;
2. obtain the validated Gemma scope decision;
3. stop on clarification or an out-of-scope decision;
4. call the retrieval boundary with the original typed request for context
   accounting and the standalone query for retrieval; that boundary owns query
   embedding, the three frozen retrieval lanes, fusion, reconstruction,
   relevance, and sufficiency;
5. stop on insufficient evidence, a context limit, or dependency failure;
6. scan the exact retrieved excerpts for indirect injection;
7. pass only accepted cited excerpts to grounded generation;
8. accept only validated citation-bearing segments; and
9. build the client-safe `ishikawa.chat-response.v5` envelope, including only
   the allowlisted content-free diagnostic fields.

Direct injection, scope rejection, clarification, insufficient evidence,
context limits, and indirect injection all stop downstream work. An expected
dependency outage returns the fixed `temporarily-unavailable` envelope. Any
unexpected internal failure returns the fixed `internal-error` envelope;
exception text is never a client field.

## Script 63 boundary

Script `63` qualifies the service name, ownership, process boundary, ordering,
short-circuit rules, safe error mapping, and answered-response construction
with injected local test ports. It starts no HTTP listener, contacts no
database or model endpoint, and reads no credentials. Concrete retrieval and
model adapters plus the native HTTP listener remain subsequent gates.

Script `66` adds the first concrete native PostgreSQL retrieval port. Its
read-only database and resolved-query boundaries are defined in
`POSTGRES_RETRIEVAL_ADAPTER.md`. Script `68` proves the complete adapter with
relationship expansion and complete-procedure reconstruction in a disposable
target database.

## Native HTTP listener

The listener uses only Python's standard library. It exposes two nonstreaming
application routes with exact `Content-Type: application/json`:

- `POST /v1/chat` for the versioned conversation contract; and
- `POST /v1/document` for progressive reconstruction of the exact active
  document-version identity returned by a citation.

A successfully decoded chat request always returns HTTP `200`; the versioned
application's `status` field remains the authority for answered,
clarification, insufficiency, scope, security, context, dependency, and
internal outcomes. The document route uses a separate strict request/response
schema, a read-only repeatable-read transaction, and fails closed when the
exact version is not active. It does not call Gemma or expose original PDFs.

Two content-free operational routes are separate from that application route:
`GET /live` reports only that the listener responds, while `GET /ready`
returns HTTP `200` only when its configured readiness probe returns exactly
true. A missing, false, malformed, or failed readiness probe returns HTTP
`503` and the fixed `not-ready` state without dependency or exception detail.

Malformed transport requests use a separate fixed
`ishikawa.transport-error.v1` envelope and an appropriate HTTP failure status.
They never reach orchestration and never expose exception text. The listener:

- accepts only an explicit `Content-Length` within the API request limit;
- rejects transfer encoding and `Expect` handling;
- returns fixed errors for unsupported methods, paths, media types, malformed
  bodies, saturation, and unexpected listener failures;
- emits `no-store`, `nosniff`, exact length, JSON media type, and connection
  close headers;
- suppresses the standard Python server-identification and access log;
- generates one opaque request identity for correlation;
- permits only loopback peers and loopback bind addresses;
- bounds concurrent active requests and request-body read time through the
  validated deployment profile; and
- stops cleanly without leaving a listener behind.

The v1 deployment template defaults to `127.0.0.1:1384`, eight concurrent
active requests, and a 30-second request-body read timeout. These are
deployment limits, not retrieval-method semantics. Non-loopback exposure is
rejected by the first implementation and requires a separately reviewed
security posture.

Script `69` qualifies the real loopback HTTP exchange with injected local
application behavior. It contacts no target, database, model endpoint, or
credential and retains no request or response content.

## Installed foreground command

`scripts/ishikawa-retrieval-api` is the repository-free native service
entrypoint. It derives the product and configuration roots from its installed
location and accepts only `--check-config`, `--serve`, or `--help`. It accepts
no credential, endpoint, or path override argument.

`--check-config` loads and validates the complete configured runtime without
reading credentials, contacting dependencies, or opening a listener.
`--serve` runs the loopback listener in the foreground so an external service
supervisor owns restart policy. SIGINT or SIGTERM causes bounded shutdown and
listener cleanup. The command emits only content-free lifecycle markers and
hides exception details.

Script `92` qualifies this entrypoint, the health-route boundary, and local
cleanup without contacting a target, database, model, or credential.

## Concrete readiness

The configured readiness probe checks all five required component groups on
each request and returns one boolean to the HTTP layer:

1. every required runtime YAML file remains a regular non-symlink file with
   the same SHA-256 identity loaded at service startup;
2. the installed state, log, and runtime-control directories remain
   non-symlink directories with read, write, and traversal access;
3. PostgreSQL accepts the protected `rag_retrieval` credential, enforces a
   read-only transaction, and exposes at least one active searchable chunk;
4. the configured Gemma `/health` endpoint returns HTTP `200`; and
5. the configured Nomic `/health` endpoint returns HTTP `200`, followed by one
   validated singleton query embedding on the first successful readiness
   check in the process.

Gemma and Nomic health URLs are explicit deployment configuration and must
share the scheme, host, and port of their corresponding application endpoint.
Health credentials are passed only in an Authorization header. Readiness reads
credentials lazily when `/ready` is requested; runtime assembly and
`--check-config` still read no credential and contact no dependency.
The Nomic embedding warmup is performed once per Retrieval API process and is
not retained. Later readiness checks continue to verify Nomic health without
repeating the warmup.

Every component is inspected so internal diagnostics can later report all
failed categories in one pass. The public endpoint remains content-free: any
missing credential, changed configuration, unsafe storage, unavailable
dependency, wrong database role or transaction mode, or empty active corpus
becomes only HTTP `503` with `{"schema":"ishikawa.health.v1","status":"not-ready"}`.
Exception text, endpoints, paths, model identities, credentials, and component
states are never returned to the client.

Script `93` qualifies this concrete readiness composition locally with injected
dependency ports. It performs no target, database, or model contact and retains
no credential, response body, source content, or vector.

## Classified local logging

The foreground service assembles the validated local observability boundary
before it opens the listener. Service lifecycle and final HTTP outcomes are
written as versioned JSONL to protected local storage. The same opaque request
identity correlates the listener result with the existing orchestration path;
debug logging may add the content-free stage trace. Routine request or response
content, headers, exceptions, credentials, paths, database values, and vectors
are never listener-log inputs.

The exact field classifications, profile behavior, rotation, bounded verbose
activation, and audit separation are defined in `OBSERVABILITY.md`. Script `94`
qualifies that boundary locally without contacting a runtime dependency.

The foreground service also owns a protected local Unix-domain logging-control
socket for its lifetime. It starts the socket before reporting the service as
started and removes it during every normal shutdown path. The installed
`ishikawa-log-control` command can query status, enable one bounded service or
request scope, or disable verbose capture without changing YAML or restarting
the service. Script `95` qualifies this surface locally.

The service emits content-free request, stage, retrieval-lane, candidate,
reconstruction, citation, and context-budget observations to the protected
local `metrics.jsonl` destination. Pipeline stages use monotonic elapsed time;
wall-clock UTC remains only the event timestamp. All aggregation labels are
fixed low-cardinality values, while the opaque request identity remains a
non-label correlation field. No metrics HTTP route or external telemetry
service is created. The exact record contract is defined in `OBSERVABILITY.md`
and qualified by Script `96`.

## Configured runtime assembly

`runtime_dependencies.yaml` contains deployment locations and fixed protected-
environment variable names, never credential values. The runtime assembler
loads and validates all accepted API, service, security, scope, query-
resolution, retrieval, relationship, reconstruction, relevance, sufficiency,
deployment, and dependency profiles before it creates any dependency client.

The assembled runtime uses:

- one protected Gemma credential for scope, query resolution, exact
  tokenization, and grounded generation;
- one protected Nomic credential for singleton query embedding;
- one protected PostgreSQL password for the fixed `rag_retrieval` role;
- keyword PostgreSQL connection parameters with read-only session protection;
- active read-only views for trusted source-display-name resolution; and
- the already qualified listener factory and orchestration order.

Assembly reads no credential and starts no listener. Credentials are read only
when the corresponding dependency is actually invoked. Script `70` qualifies
this wiring locally with injected dependency failures and a direct-injection
short circuit. Live tokenization and complete live-request qualification remain
separate later gates.

## Configured live-runtime qualification

Script `74` accepts the exact configured tokenization and singleton embedding
adapters from the application host. Script `75` is the next bounded integration
gate. It sends one synthetic professional question through `POST /v1/chat`
while the accepted `rag_catalog` remains intentionally empty.

The expected execution trace is request acceptance, direct-injection pass,
scope allow, deterministic query resolution, retrieval completion, and
sufficiency block. Exactly one scope call, one singleton embedding call, one
read-only PostgreSQL connection, and two exact-tokenization calls are allowed.
The required client result is HTTP `200` with `insufficient-evidence`; grounded
generation must not run because there is no evidence to cite.

This gate neither publishes synthetic data nor substitutes a disposable
database for deployment configuration. It proves the real credential,
listener, model, embedding, tokenization, and read-only empty-catalog boundaries
without changing the accepted catalog. The wrapper restores PostgreSQL to its
boot-disabled stopped state, releases port `1384`, and leaves operator-owned
model forwarding unchanged.

The first operator execution blocked at the expected response contract. Its
safe cleanup guarantees passed, but the original runner retained only the
generic mismatch and therefore could not distinguish a valid alternate scope
outcome from a later dependency or response-envelope mismatch. The corrected
Script `75` keeps the same authority and target. It uses a more explicit
professional operating-procedure question and, only on failure, returns
allowlisted status, trace, event, and dependency-call categories without
retaining the question, response, credential, or vector.

That diagnostic rerun returned HTTP `500` with zero scope, embedding,
database, tokenization, and generation calls. Review identified late-bound
self-recursion in the qualification observer: after replacing the runtime's
executor, the observer resolved the replacement instead of the captured
configured executor. The corrected runner captures the configured callable
first and validates that behavior with a local observer self-test. Production
runtime modules and frozen contracts did not change.

## Native service lifecycle

The final native user service runs the existing foreground command from
`~/Documents/Ishikawa` under systemd supervision. It is deliberately not
enableable: the unit contains no `[Install]` section, so installation or host
reboot cannot make the Retrieval API start automatically. The operator starts
and stops it explicitly after PostgreSQL and required endpoint forwarding are
available.

Only the named `ISHIKAWA_GEMMA_API_KEY`, `ISHIKAWA_NOMIC_API_KEY`, and
`ISHIKAWA_POSTGRESQL_PASSWORD` values may pass from the user manager
environment. The unit contains no credential values or environment file. The
eventual stack-start command must import those values without printing them,
start the service, and immediately remove the manager copies after the process
receives its environment. That orchestration remains separate until the
Next.js service exists.

The Retrieval API restarts only after failure, never after a clean operator
stop. `SIGTERM` invokes the already-qualified graceful path, which stops the
HTTP listener, removes the logging-control socket, records content-free
lifecycle events, and exits. Startup, stop, and restart intervals are bounded.
The service is restricted to read the installed product and write only its
protected `state/logs` and `state/run` directories. Script `98` qualifies the
unit definition, boot-disabled posture, exact environment-name boundary,
temporary foreground start, liveness, `SIGTERM` cleanup, and listener/socket
release without installing the unit or contacting dependencies.

The complete application lifecycle is owned by `scripts/ishikawa-stack` and
documented in `STACK_CONTROL.md`. That command preserves explicit on-demand
startup, readiness ordering, reverse-order shutdown, and the boot-disabled
posture.

