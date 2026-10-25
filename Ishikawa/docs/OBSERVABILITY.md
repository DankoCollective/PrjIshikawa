# Ishikawa Local Observability Contract

## Runtime boundary

The Ishikawa Retrieval API writes versioned JSON Lines records under the
installed `state/logs` directory. It adds no external collector, logging
database, dashboard, or metrics service. The runtime validates
`logging_profile.yaml` during ordinary configuration assembly and includes its
digest in the complete runtime-policy identity.

The template selects `default` as the restart-safe base profile. `debug` is the
only other permitted persistent base profile. `verbose` cannot be selected in
YAML: it requires an explicit, in-memory activation with a reason code, a
service or opaque-request scope, a start time, and an expiration no later than
the configured maximum. Expiration, emergency stop, and process restart all
restore the configured base profile.

## Operator control

The running Retrieval API owns one local Unix-domain socket at
`state/run/logging-control.sock`. The `state/run` directory is mode `0700`,
the socket is mode `0600`, and Linux peer credentials must identify the same
operating-system user as the service. The channel has no TCP listener and
accepts only bounded, exact-schema JSON records. A preexisting socket path,
wrong owner, symlink, malformed record, duplicate field, unknown field, or
oversized record fails closed.

The repository-free installed command is:

```text
scripts/ishikawa-log-control status
scripts/ishikawa-log-control disable
scripts/ishikawa-log-control enable --reason REASON_CODE --duration-seconds N --scope service
scripts/ishikawa-log-control enable --reason REASON_CODE --duration-seconds N --request-id OPAQUE_REQUEST_ID
```

The command derives the socket from its installed product root; it accepts no
socket path, endpoint, credential, or configuration override. `enable`
requires a stable reason code, a positive duration no greater than the
configured maximum, and exactly one service or opaque-request scope. `status`
reports whether the base or any unexpired verbose activation is configured.
`disable` is the emergency stop. Every successful enable and disable remains
content-free audit evidence. Verbose state is never written to configuration
or a database and therefore cannot survive service restart.

## Classifications

Every record has schema `ishikawa.log-event.v1` and a classification list:

- `operational` contains timestamp, component, stage, stable event code,
  severity, outcome, duration, HTTP status, and optional opaque request ID;
- `diagnostic` may add only the implemented allowlist of content-free stage,
  lane, rank, retry, token-budget, and count fields; and
- `restricted-content` may add only the implemented allowlist of question,
  conversation, retrieval-query, excerpt, prompt, and answer fields during an
  active matching verbose session.

`default` writes only operational fields. `debug` adds diagnostic fields but
never restricted content. `verbose` adds explicitly classified restricted
content only for the active scope. Unknown classification fields, arbitrary
objects, invalid identities, malformed event codes, and unsafe numeric or
nesting bounds are rejected before serialization.

Credentials, authorization or cookie values, environment dumps, connection
strings, private keys, raw exceptions, filesystem paths, database bound
values, embedding vectors, complete HTTP headers, and other unclassified
objects have no accepted logging field. The listener passes only a typed
request outcome, status, duration, stage trace, and opaque request identity.
Question or response bodies are not passed to routine listener logging.

## Files and capacity

`retrieval.jsonl` and `audit.jsonl` are separate mode-`0600` regular files in a
mode-`0700` non-symlink directory. Filenames are validated basenames, and each
append uses `O_NOFOLLOW` where supported. JSON encoding prevents caller text
from creating additional records or fields.

Event size, active-file size, retained-file count, and maximum verbose duration
are explicit bounded configuration. Rotation retains only the configured
active file and numbered ancestors. Symlink or non-regular destinations fail
closed. Logging failures never alter an application safety decision; inability
to establish required logging during service start prevents that start.

## Correlation and audit

The same generated opaque request identity used by HTTP and orchestration is
written to the final request event. Debug logging may add the validated
orchestration stage trace under that identity. The identifier represents a
request, not a person, and contains no source, user, or organizational data.

Verbose enable and disable actions write separate content-free audit records.
The enable record preserves the declared reason code, scope type, bounded
duration, and an opaque request identity when request-scoped. Captured content
is never copied into the audit destination.

## Content-free operational metrics

The Retrieval API writes metric observations to `metrics.jsonl` in the same
protected `state/logs` directory. This is a local rotated JSONL file, not a
metrics server, HTTP route, collector, database, or dashboard. It uses the
same event-size, file-size, retained-file-count, regular-file, symlink, and
mode-`0600` protections as the operational log. Metrics remain content-free
under every logging profile, including `verbose`.

Each exact `ishikawa.metric-event.v1` record contains a metric name, counter or
observation type, integer value, unit, timestamp, opaque request identity, and
fixed low-cardinality labels. Request identity is a correlation field and is
never an aggregation label. Unknown metric names, unknown or user-controlled
labels, unsupported label values, negative or unbounded values, and malformed
stage sequences fail closed.

The first metrics surface records:

- request count and total request duration by fixed request category and
  outcome;
- completed pipeline-stage count and monotonic elapsed milliseconds since the
  preceding completed stage;
- exact, lexical, and vector lane state;
- fused and authorized candidate counts;
- reconstructed-unit and citation counts; and
- used and configured context-token counts.

The application response remains authoritative. Metrics are derived only from
the typed execution result after safety, scope, retrieval, reconstruction, and
response decisions are already made. A metrics write cannot change or bypass
those decisions. The listener contains telemetry failure and returns the
already-determined response under the first-slice degraded-observability rule;
required administrative audit remains fail closed separately.

Script `94` qualifies the configuration, classifications, profile filtering,
request correlation, protected files, rotation, bounded verbose activation,
automatic restoration, emergency stop, audit separation, record-forgery
resistance, and prohibited-field rejection locally. It contacts no target,
database, model, or credential.

Script `95` qualifies the owner-only local control channel, exact request and
response contracts, installed operator command, request and service scoping,
bounded activation, emergency disable, audit generation, socket cleanup, and
restart restoration. It contacts no target, database, model, or credential.

Script `96` qualifies the fixed metric registry, low-cardinality labels,
monotonic pipeline timing, retrieval measurements, protected local metric
records, prohibited-content exclusion, and installed short-circuit request
integration. It adds no metrics endpoint or external service.

## Retention and scheduling

The logging profile independently configures operational, metrics, and audit
retention in whole days. The supplied defaults are 30 days for operational
logs, 30 days for metrics, and 90 days for audit. Values are bounded from 1 to
3,650 days and are deployment settings; changing them does not change corpus
or retrieval semantics.

The repository-free installed command is:

```text
scripts/ishikawa-observability-retention --check-config
scripts/ishikawa-observability-retention --apply
```

`--apply` writes a content-free audit start record before deletion and a
completion record afterward. It locks the three configured telemetry families
against concurrent application writes, validates every matching active or
numbered rotated file before deleting anything, and removes only files whose
filesystem modification time has reached the configured age. Symlinks,
non-regular candidates, changed candidates, unknown configuration, and unsafe
directories block the run. Unrelated files are ignored. Output contains only
the result and per-family deletion counts; it exposes no filenames or content.

The optional user-level systemd service and timer run that command daily from
`~/Documents/Ishikawa`. The timer is independent of Retrieval API lifecycle:
it neither starts the API nor requires it to start at boot. Installation and
enablement of those units remain an explicit deployment action. The retention
command itself contacts no database, model endpoint, credential, corpus, or
network service.

Script `97` qualifies configuration bounds, protected cross-process locking,
all-or-block candidate validation, age-based deletion, content-free audit,
the repository-free installed command, and the daily native timer definition.
