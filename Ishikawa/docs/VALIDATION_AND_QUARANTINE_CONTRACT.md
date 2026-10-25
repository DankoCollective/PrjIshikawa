# Ishikawa Frozen Validation and Quarantine Contract v1

## Status

The cross-file validation, affected-document planning, validation-only
operator reporting, source-symlink rejection, stable quarantine
classification, and atomic-batch blocking behavior were frozen by the
operator on 2026-10-19. Migration `0002` is accepted, and the incremental
writer's quarantine, skip, publication, retirement, live-state guard,
parameterization, and remediation-linkage paths are locally implemented and
tested. The operator-ingestion control plane is now implemented and locally
passes 279 tests: validation-only cannot call its producer or writer; actual
runs produce only add, revise, and reprocess entries; reuse and retirement
skip document production; quarantine reaches the writer with no prepared
document; and rejected plans reach neither dependency. Concrete native
producer and PostgreSQL deployment adapters remain the next integration gate.

This contract consumes the frozen v1 document-class registry, document
catalog, and incremental ingestion manifest contracts. It does not change the
accepted PostgreSQL migration `0001` and does not authorize migration `0002`.

## Single ingestion surface

One native Python ingestion executable will perform:

1. restricted safe-YAML loading;
2. individual file-schema validation;
3. cross-file reference validation;
4. source-path and PDF validation;
5. PostgreSQL comparison and affected-document planning; and
6. protected operator-report generation.

The same executable exposes `--validate-only`. That mode performs every
available validation and planning step but does not:

- create or change PostgreSQL records;
- create PostgreSQL quarantine records;
- extract, normalize, structure, or chunk documents;
- call Nomic or Gemma; or
- publish corpus changes.

It may write only the protected local validation reports defined below.

## Planned actions

Every valid manifest entry receives exactly one planned action:

- `add`: the cataloged document has no published version;
- `revise`: the document key has an active version with different source
  bytes;
- `reprocess`: the source bytes match but class or other semantic processing
  inputs changed;
- `reuse`: the source and all semantic inputs match accepted artifacts; or
- `retire`: matching catalog and manifest retirement declarations request
  removal from active retrieval.

Planning never makes a candidate searchable.

## Stable outcomes

The overall run and each applicable entry use one of these stable outcomes:

- `PASS`: configuration and proposed actions are valid;
- `REJECTED`: operator configuration, references, or paths are invalid;
- `QUARANTINED`: a source cannot be processed safely;
- `BLOCKED`: a required dependency or runtime authority is unavailable; or
- `FAILED`: an unexpected implementation failure occurred.

The initial classification includes:

| Condition | Outcome and stable reason |
|---|---|
| Invalid YAML or schema | `REJECTED` |
| Unknown or retired assigned class | `REJECTED` |
| Duplicate document key, source path, or conflicting action | `REJECTED` |
| Previously registered catalog key removed or renamed | `REJECTED` |
| Catalog and manifest retirement declarations disagree | `REJECTED` |
| Absolute source path or traversal component | `REJECTED` |
| Source-file symlink | `REJECTED` |
| Unknown document key | `QUARANTINED / UNKNOWN_DOCUMENT_KEY` |
| Encrypted PDF | `QUARANTINED / ENCRYPTED_PDF` |
| Image-only PDF | `QUARANTINED / IMAGE_ONLY_PDF` |
| Unsafe or unsupported required structure | `QUARANTINED / UNSUPPORTED_STRUCTURE` |
| Required PostgreSQL, Poppler, or YAML capability unavailable | `BLOCKED` |

The reason-code registry will be explicit and versioned. Code does not invent
free-form reason codes at runtime.

## Path boundary

Manifest source paths are relative to the configured corpus root. Validation
rejects absolute paths, parent traversal, non-regular files, unsupported
formats, and source-file symlinks. Version 1 rejects symlinks even if their
current resolved targets appear to remain within the corpus root. This avoids
time-dependent link-target behavior and keeps the containment proof simple.

## Protected reports

Every validation or ingestion attempt writes:

```text
state/reports/<run-or-validation-identity>.txt
state/reports/<run-or-validation-identity>.json
```

The bounded terminal summary and text report contain:

- overall outcome;
- registry, catalog, and manifest digests;
- counts by planned action;
- affected document key or manifest-entry identity;
- planned action;
- entry outcome and stable reason code; and
- protected report location.

Terminal output and routine logs do not contain absolute source paths,
document contents, raw exceptions, credentials, vectors, database connection
strings, or unreviewed model/service output. The protected JSON report may
contain relative source paths needed for remediation but never credentials or
document contents.

## Validation-only quarantine behavior

`--validate-only` reports the stable `QUARANTINED` entry outcome together with
`validation_only: true` and `mutation_performed: false`. It does not modify
PostgreSQL or write quarantine artifacts. It proves planning and validation
only.

## Actual-run quarantine behavior

During a real ingestion attempt:

- a valid ingestion-run record is created;
- the failed or unsafe stage is recorded;
- the quarantine record is created;
- bounded private evidence is written beneath
  `state/quarantine/<ingestion-run-id>/<document-or-entry-identity>/`;
- the operator receives a nonzero final result and stable reason code; and
- no change from the batch is published.

The original source document is never deleted or moved by quarantine.

An input too malformed to establish a trustworthy ingestion run or manifest
entry receives a local rejected-validation report rather than a fabricated
database document/quarantine identity.

## Remediation linkage

Quarantine history is immutable. A corrected attempt creates a new run and
does not edit the failed run to claim success. Migration `0002` shall provide
content-free linkage sufficient to record:

- `manifest_entry_identity` for cases without an authoritative document ID;
- `resolved_by_run_id` identifying the successful remediation run; and
- `resolution_code` from a versioned allowlist.

Successful remediation may set the prior record's resolution fields while
retaining its original reason, stage, evidence, and creation time.

## Atomic batch publication

Processing may continue after an entry fails or is quarantined so the operator
receives a complete report. Successful work remains candidate-only. The
manifest is the atomic publication unit:

- no candidate change from the batch becomes searchable unless every required
  entry passes;
- the previously active corpus remains unchanged on failure or quarantine;
- successful candidate artifacts may be reused by a corrected retry when all
  semantic inputs match; and
- operators use smaller manifests, including one document per manifest, when
  they require independent publication boundaries.

Partial publication within one manifest is excluded from v1.

## Implementation and qualification boundary

The implementation must include positive and negative fixtures for all three
YAML contracts, duplicate-key and unknown-field handling, punctuation
collisions, path traversal, symlinks, missing/unsupported files, cross-file
references, retirement agreement, all five planned actions, report redaction,
quarantine classification, remediation linkage inputs, and atomic batch
blocking.

The accepted local validation command is:

```bash
bash ./phase-28-apisachi-tokuli/Ishikawa/scripts/run-local-validation-tests.sh
```

The original slice passed 52 tests with Python `3.12.3` and PyYAML `6.0.1` on
2026-10-19. The complete suite now passes 279 tests. Script `76` separately
qualifies the control-plane routing with injected, non-networking ports. It
does not contact a target or PostgreSQL server, call a model, read a
credential, or mutate corpus state. Concrete native producer, native
PostgreSQL, target, and package integration remain later work.
