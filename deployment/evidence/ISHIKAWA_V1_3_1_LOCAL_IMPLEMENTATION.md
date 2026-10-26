# Ishikawa v1.3.1 Local Implementation Evidence

## Scope

Date: 2026-10-26 America/Los_Angeles

This content-free record covers the local source implementation authorized by
frozen V13-79 through V13-89. No deployment target, model endpoint, database,
credential, organizational corpus, or protected content was contacted.

The v1.3.1 source manifest contains 211 files and has SHA-256:

`5846e024edbc0db8c4b5b4ca2fa504af50015dce5a28eaeeb3378d1af30607de`

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
  license inventory, and build-receipt validation passed.
- Permanent stack lifecycle harness: clean start/status/stop, restart with a
  fresh build, production-build failure cleanup, build timeout cleanup,
  liveness failure cleanup, stale-container preflight, PostgreSQL failure
  cleanup, and occupied-port refusal passed.
- Carry-builder harness: separate-payload assembly, portable verification,
  repeat publication, supersession, application checksum refusal, runtime
  identity refusal, carry inventory, and terminology refusal passed.
- Portable deployment-entrypoint harness: verification, read-only inventory,
  image/application/configuration/unit installation, custom-port
  configuration, clean role/database/pgvector/schema initialization,
  schema-failure cleanup, start/status/stop, replay refusal, guarded empty
  removal, post-mutation install cleanup, and non-final-carry refusal before
  mutation passed.
- Release-boundary, Script 04 helper/wrapper, Script 05 helper/wrapper, and
  Script 06 target/wrapper regressions passed, including their existing
  failure, signal, cleanup, and preservation branches.
- Application, runtime-image, and carry builders passed their nonmutating
  source/decision validation modes.
- Shell parsing and Git whitespace validation passed.

## Boundary and remaining gates

The builder harnesses use deterministic command doubles to cover failure and
publication branches. They do not qualify real image bytes. This record does
not claim that the generic AMD64 image or v1.3.1 application candidate has
been built, scanned, requalified, accepted, or promoted.

The remaining ordered gates are:

1. build and export the exact generic Linux AMD64 runtime image;
2. inspect the exact combined SBOM, license inventory, build receipt, image
   identity, image history, and archive checksum and complete the fresh
   advisory scan;
3. build the exact v1.3.1 application candidate and verify its application
   SBOM, license record, deterministic archive, clean installation, and
   production web build;
4. requalify those exact bytes on EmceeDanko and obtain v1.3.1 human UI
   acceptance;
5. accept the read-only Tech inventory and resolve any required offline native
   prerequisite payload;
6. complete independent review and atomically promote the exact carry bytes to
   the stable handoff.

Current disposition:

`ishikawa_v1_3_1_local_implementation=pass;carry_ready=false`
