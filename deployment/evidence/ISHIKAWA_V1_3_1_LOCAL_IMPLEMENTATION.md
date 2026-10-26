# Ishikawa v1.3.1 Local Implementation Evidence

## Scope

Date: 2026-10-26 America/Los_Angeles

This content-free record covers the local source implementation authorized by
frozen V13-79 through V13-90. No model endpoint, database,
credential, organizational corpus, or protected content was contacted.

The v1.3.1 source manifest contains 211 files and has SHA-256:

`fda594e21ee21c1be94ce5e173b227123c1893d4ac78f8edf5a27b501448d9fa`

## Passing executable gates

- Complete native suite: 486/486 tests passed with
  `ishikawa_local_validation_tests=PASS`.
- Application release-builder harness: deterministic success, repeat
  publication, supersession, complete checksums, Apache-2.0 packaging,
  application SBOM, source-manifest drift refusal, native failure, JavaScript
  failure, production-build failure, and terminology refusal passed.
- Generic runtime-image builder harness: success, repeat publication,
  supersession, checksum verification, build failure, image-boundary failure,
  terminology failure, combined installed-npm/Debian CycloneDX SBOM, combined
  license inventory, exact Node/npm/Yarn identity and license evidence,
  Docker manifest/tag/layer checks, OCI-config and canonical-history binding,
  build-receipt validation, native host/Docker architecture refusal, and
  CPU/Docker-storage capacity refusal passed.
- Script 07 wrapper harness: validation-only, transfer, native-host execution,
  artifact return, atomic publication, repeat supersession, nested build
  failure, returned-checksum refusal, host-identity refusal, current-handoff
  preservation, signal propagation, and remote cleanup passed.
- Script 08 wrapper harness: validation-only, exact runtime-image binding,
  checksum-bound application-source transfer, native application build,
  verified return, atomic publication, repeat supersession, nested build
  failure, nested source-validation failure with precise reason/detail
  propagation, local helper-validation failure propagation, runtime-image
  mismatch, returned checksum/receipt refusal, host-identity refusal, signal
  propagation, current-handoff preservation, and remote cleanup passed.
- Permanent stack lifecycle harness: clean start/status/stop, restart with a
  fresh build, production-build failure cleanup, build timeout cleanup,
  liveness failure cleanup, stale-container preflight, PostgreSQL failure
  cleanup, and occupied-port refusal passed.
- Carry-builder harness: separate-payload assembly, portable verification,
  repeat publication, supersession, application checksum refusal, runtime
  identity refusal, independent runtime archive/config/history/SBOM/license
  binding, carry inventory, and terminology refusal passed.
- Portable deployment-entrypoint harness: verification, read-only inventory,
  image/application/configuration/unit installation, custom-port
  configuration, clean role/database/pgvector/schema initialization,
  schema-failure cleanup, start/status/stop, replay refusal, guarded empty
  removal, post-mutation install cleanup, and non-final-carry refusal before
  mutation passed.
- The real read-only native-prerequisite inventory passed locally against the
  available Ubuntu/ARM64 host, produced a valid complete checksum manifest,
  made no network/package/service change, and retained neither the observed
  hostname nor operator account. Tech will run the same content-free contract
  with its frozen Ubuntu 26.04/AMD64 expectations.
- Release-boundary, Script 04 helper/wrapper, Script 05 helper/wrapper, and
  Script 06 target/wrapper regressions passed, including their existing
  failure, signal, cleanup, and preservation branches.
- Application, runtime-image, and carry builders passed their nonmutating
  source/decision validation modes.
- Shell parsing and Git whitespace validation passed.

## Boundary and remaining gates

The builder harnesses use deterministic command doubles to cover failure and
publication branches. Script 07's first real EmceeDanko execution completed
its native build, archive round trip, atomic publication, and cleanup paths.
Its content-free report has SHA-256
`ee1589f365adf61de9aa4d7a3d5c1ce70c163149c305619164ccb7e0fa329bd7`.
Post-run review rejected that handoff as final evidence because the receipt did
not yet bind the exported OCI config/history and omitted npm/Yarn from the
explicit runtime-tool license evidence. The bounded correction now records and
independently verifies those identities through the downstream portable carry
verifier. The first image is preserved only as superseded build evidence; it
is not a promotion input.

This record does not claim that the corrected generic AMD64 image or v1.3.1
application candidate has been scanned, requalified, accepted, or promoted.

Corrected Script 07 subsequently passed and is recorded in
`ISHIKAWA_V1_3_1_RUNTIME_IMAGE_BUILD.md`. The first attended Script 08
execution stopped before building because Script 01's target-side validation
failed. That attempt published no application
handoff and removed its private transfer. Its wrapper had suppressed the
nested reason; the bounded correction now aligns the target prerequisite
inventory with Script 01 and preserves the complete inner failure detail.
The full regression set passed after that correction. Script 08 must be rerun
to resolve or identify the exact target-side prerequisite.

The rerun identified `source_manifest_mismatch` even though the transferred
payload and every source file passed their checksums. The application builder
had left manifest ordering to the host collation locale. It now fixes
`LC_ALL=C` before source-manifest generation and every subsequent deterministic
assembly step. A command-double gate rejects any builder execution that does
not carry that locale into `sort`; the complete regression set passed after
the correction.

The remaining ordered gates are:

1. run Script 08 to build the exact v1.3.1 application candidate natively on
   EmceeDanko and verify its application
   SBOM, license record, deterministic archive, clean installation, and
   production web build;
2. complete the exact-image and exact-application advisory disposition from
   their recorded SBOMs;
3. requalify those exact bytes on EmceeDanko and obtain v1.3.1 human UI
   acceptance;
4. accept the read-only Tech inventory and resolve any required offline native
   prerequisite payload;
5. complete independent review and atomically promote the exact carry bytes to
   the stable handoff.

Current disposition:

`ishikawa_v1_3_1_local_implementation=pass;carry_ready=false`
