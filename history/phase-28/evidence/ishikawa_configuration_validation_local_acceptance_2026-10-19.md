# Ishikawa Configuration Validation Local Acceptance

## Result

`PASS` on 2026-10-19.

The first Ishikawa native Python implementation slice now provides:

- restricted single-document UTF-8 safe-YAML loading with duplicate-key,
  custom-tag, directive, anchor, alias, and merge rejection;
- exact v1 validators and canonical SHA-256 identities for the document-class
  registry, document catalog, and incremental ingestion manifest;
- cross-file class, catalog, retirement, source-path, regular-file, PDF-header,
  and prior-catalog continuity checks;
- deterministic `add`, `revise`, `reprocess`, `reuse`, and `retire` planning
  through an immutable in-memory published-state boundary;
- a versioned stable reason-code registry;
- validation-only quarantine classification and all-or-nothing batch blocking;
- protected mode-0600 text/JSON reports under a mode-0700 report directory;
  and
- bounded terminal output that excludes source paths and document contents.

## Accepted command

From the repository root:

```bash
bash ./phase-28-apisachi-tokuli/Ishikawa/scripts/run-local-validation-tests.sh
```

The command compiles every Ishikawa Python module and runs all local unit and
contract tests. Its final acceptance marker is:

```text
ishikawa_local_validation_tests=PASS
```

## Accepted execution

- Python: `3.12.3`
- PyYAML: `6.0.1`
- Tests: `52`
- Failures: `0`
- Errors: `0`
- Harness SHA-256:
  `092b2cb8e5254d1ca2b6e71a496bf76743004134848e249d5d7b9f37d9d62eb7`

Coverage includes tracked-template loading, positive and negative schema
fixtures, duplicate YAML keys, unknown fields, identifier syntax and
punctuation collisions, relative-path rules, missing and unsupported sources,
source symlinks, class and catalog references, retirement agreement, all five
planned actions, prior-catalog key removal, deterministic validation identity,
report permissions and redaction, no-mutation evidence, and a mixed batch in
which one quarantined entry blocks the whole batch.

## Safety and scope boundary

This was a local application-code test only. The harness did not contact a
remote system, connect to PostgreSQL, inspect organizational documents, call
Nomic or Gemma, change corpus state, or run migration `0002`.

This acceptance does not claim extraction, encrypted/image-only PDF
detection, structural quarantine, database quarantine records, remediation
linkage, publication, or target-native qualification. Those capabilities
remain downstream of reviewed migration `0002` and the incremental ingestion
writer.

The planner consumes published-document state through an immutable mapping.
That seam is deliberate: it lets migration `0002` define the correct
PostgreSQL ownership boundary before Psycopg reads or writes are implemented.
