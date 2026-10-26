# Ishikawa v1.3.1 Local Implementation Evidence

## Scope

Date: 2026-10-26 America/Los_Angeles

This content-free record covers the local source implementation authorized by
frozen V13-79 through V13-91. No model endpoint, database,
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

Script 08 subsequently passed and is recorded in
`ISHIKAWA_V1_3_1_APPLICATION_BUILD.md`. The exact external application archive
is SHA-256
`2dbf08b9e15fb4436e54ce492f2ad430129e794d33a1a45cdc6abf1a7b0b5f69`.

Numbered Script 09 now supplies the previously missing operator-facing
exact-byte production requalification gate. Its isolated target and wrapper
harnesses cover run, human acceptance, cleanup, returned evidence,
database-inventory mismatch, production-web failure, frontier failure,
automatic candidate cleanup, and preservation of accepted v1.3.
After Script 09 implementation, the complete 486-test native suite and all 16
deployment harnesses passed together, including the pre-existing release,
staging, qualification, attended-runtime, image-build, application-build,
production-stack, carry, and portable-deployment branches.

The first operator Script 09 run stopped in preflight with
`accepted_v1_3_baseline_not_ready`; it installed or launched no v1.3.1 object
and changed neither accepted v1.3 nor its database. The content-free report is
SHA-256
`65d03f14ab13e35aef607761430d98d65fe8a1f03c0158816eadf0a62626cc72`.
The operator's forward used EmceeDanko local ports `8000`/`8001`, while frozen
V13-76 and the canonical EmceeDanko forwarding wrapper assign the v1.3 model
listeners to `18000`/`18001`. Script 09 now defaults to those frozen v1.3
ports, reports individual accepted-install/API/UI/PostgreSQL preflight states,
and preserves the target's exact failure reason through the outer wrapper.
The expanded target and wrapper harnesses pass the corrected default-route,
component-diagnostic, nested-failure, complete lifecycle, and cleanup paths.

The next operator Script 09 run completed every target qualification gate:
the accepted v1.3 baseline remained ready, the exact generic image matched,
the read-only corpus-v3 database reported 30 documents and 150 pages, model
and API readiness passed, both fresh production web builds passed, and all
60 frontier cases passed. The candidate remained ready on loopback ports
`3385`/`8385`, and accepted v1.3 and its database remained unchanged. The
content-free local report is SHA-256
`b1843c8ef566b4fd33c731d2d113d1d49bd4155087c4748cb77040c1f3d8ed25`.

The outer wrapper then blocked while creating its ignored local evidence
stage because `mkdir -m` attempted a POSIX mode update on the Windows-backed
WSL repository mount. This was a local receipt-publication defect after the
successful target gate, not a candidate failure. The correction preflights
both local output lanes before target work, avoids POSIX-mode preservation for
content-free ignored evidence on that mount, validates each lifecycle receipt
more narrowly, starts a rerun's evidence set without stale acceptance or
cleanup receipts, and recovers the exact durable target qualification receipt
before acceptance or cleanup when local publication was interrupted. No
application, image, database, listener, service, credential, or boot posture
changed. Executable wrapper coverage now includes WSL-mode refusal and both
acceptance and cleanup receipt-recovery paths.

After this correction, all 486 native tests and all 16 then-current deployment harnesses
passed together, including every Script 09 run, acceptance, cleanup,
publication, receipt-recovery, failure-propagation, and checksum branch.

The operator then completed human review and accepted the exact running
v1.3.1 candidate. Script 09 `--accept` recovered and revalidated the durable
qualification receipt before recording acceptance, published both receipts
under one verified local checksum manifest, removed its private transfer, and
left candidate cleanup pending. Exact evidence identities are:

- acceptance report SHA-256:
  `dbc518a584465fa922db52b3ebf43c4f148aad6bd6ffb40c340b1159dbd34b19`;
- qualification receipt SHA-256:
  `c8bd662c1ac3fe7c70f819609266e47aacc0d8b054ad8f65fd495c74fe4e5ed5`;
- acceptance receipt SHA-256:
  `afbbf3225e8eebe64be60f7a379abdc22794663f90ce4aceae06d2194c500d40`;
- accepted application archive SHA-256:
  `2dbf08b9e15fb4436e54ce492f2ad430129e794d33a1a45cdc6abf1a7b0b5f69`;
- accepted runtime archive SHA-256:
  `af95820f63798b39c6538e3f9b5653d47b07aed1d81625e2382485ff559eff3f`;
  and
- accepted image ID:
  `sha256:79f39435329920c9c834e55cf5e18528540220111ae2a35d779a86d0b539d298`.

The acceptance receipt records production build/start pass, 60/60 frontier
cases, explicit human acceptance, disabled boot autostart, and no mutation of
accepted v1.3 or its database. The local `SHA256SUMS` verified both receipts.

The first Script 09 cleanup invocation then passed on EmceeDanko: it removed
the isolated qualification root and container, freed ports `3385`/`8385`, and
revalidated accepted v1.3. Local evidence publication subsequently blocked
because GNU `cp --no-preserve=mode,ownership` still attempted `chmod` on the
Windows-backed WSL repository mount. The target cleanup result was not
published by that invocation. The bounded correction copies only the flat
content-free evidence files, compares every destination byte-for-byte, and
then regenerates and verifies `SHA256SUMS`; it never copies POSIX metadata.
The same latent later-lifecycle publication path was corrected in Script 10
before promotion. Both wrapper lifecycle suites and an end-to-end publication
exercise on the actual Windows-backed artifact lane pass after the correction.

The idempotent Script 09 cleanup rerun then passed and atomically published all
three lifecycle receipts. The cleanup report SHA-256 is
`145b28e6a9107b364b85b157db9d0d19e44cf54cfd84b226899094410ba4b40e`;
the cleanup receipt SHA-256 is
`4f902861ea4b8c65976f8ca32cf8e1cb06245140454068159bccc84762cf7b8d`;
and the final evidence-manifest SHA-256 is
`538b7af657941916189ff420214b8d5adacb4f1cb620ee4ae6b5e0693f6e2263`.
The verified result records candidate removal, free qualification ports,
accepted v1.3 readiness, disabled boot autostart, and no accepted-database or
accepted-application mutation.

Frozen V13-91 authorizes one attended EmceeDanko promotion lifecycle after
Script 09 cleanup. Numbered Script 10 now binds the exact Script 07 image,
Script 08 application, and all three Script 09 lifecycle receipts before any
target contact. Its target helper stages and checks v1.3.1 while accepted v1.3
remains ready; at the immediate switch boundary it stops v1.3, moves the
stopped durable corpus-v3 state without schema, corpus, or role mutation, and
starts the package-local v1.3.1 PostgreSQL, Retrieval API, and production UI
on `5432`/`8384`/`3384`. A failed launch automatically reconstructs the v1.3
runtime. Explicit rollback remains available until human acceptance; final
acceptance proves the promoted runtime and consumer inventory before removing
the superseded v1.3 root and old image. Historical v1.2 files and database are
not modified.

The isolated Script 10 target and wrapper harnesses cover complete promotion,
acceptance, explicit rollback, failed-launch automatic restoration, database
inventory refusal, old-image consumer refusal, exact-evidence validation,
WSL-safe publication, returned-receipt refusal, nested target failure, signal
propagation, and remote cleanup. Together with the pre-existing suite, all 18
deployment harnesses pass. Script 09 cleanup is complete.

Script 10 `--run` then passed. It verified the exact application, image, and
complete Script 09 lifecycle; checked accepted v1.3, corpus-v3, model routes,
ports, and disabled boot posture before the switch; stopped v1.3 only at the
switch boundary; moved the stopped durable database state unchanged; and
started v1.3.1 on `5432`/`8384`/`3384`. The promoted inventory remains 30
documents, 150 pages, 786 authoritative chunks, 943 retrieval candidates, 157
retrieval-scoring-only candidates, 943 embeddings, 240 relationship records,
and 90 relationship pairs. The receipt records no database, schema, or corpus
mutation and leaves the exact v1.3 rollback available pending production-port
human UI acceptance. Exact evidence identities are:

- promotion report SHA-256:
  `79a1e36d6d5a6e434f380906d09015e610f6661455f1c5acd503bc1b67899d32`;
- promotion receipt SHA-256:
  `e7d5d267cf8f9916f2d003f3b8ec184d3e829512b728a912b0162d4cbf6dfe32`;
  and
- promotion evidence-manifest SHA-256:
  `ad5cb98188ed972b96bba9324e0a57006c66d8c4c47047b8c8185b48705643ce`.

The first production-port acceptance action correctly blocked before retiring
v1.3 because a container still referenced the superseded runtime image. It
published no acceptance receipt and left the v1.3 rollback root and image in
place. The acceptance helper now reconciles three exact, named Ishikawa
containers when their inspected image ID is the exact superseded image:
`ishikawa-v1.3-web`, historical `ishikawa-web`, and the disposable
`ishikawa-v1.2-web-preflight`. It also removes stopped containers only after
proving that same exact image identity; this covers non-operational development
containers that otherwise prevent Docker image retirement. Files and databases
are not changed. Any remaining running consumer still blocks and reports its
container name, running state, and image identity. The complete target
lifecycle and transport-wrapper harnesses passed after this correction,
including expected named and stopped consumer cleanup, running unknown-consumer
refusal, acceptance replay, rollback, failed-launch automatic restoration,
returned-receipt refusal, signal handling, and remote cleanup.

The corrected Script 10 `--accept` action then passed. It removed one stopped
container after proving it referenced the exact superseded image, proved no
consumer remained, removed the superseded v1.3 rollback root and image, and
returned the checksum-bound production-port acceptance receipt. The receipt
records `human_ui_acceptance=accepted`, `production_runtime=pass`, `60/60`
frontier cases, and no database, schema, corpus, or boot-autostart mutation.
Exact acceptance evidence identities are:

- acceptance report SHA-256:
  `876b7ee893fc3162bf6c766146fade860cb6deaca80e231d7223eee78ef0af43`;
- acceptance receipt SHA-256:
  `f7e781478502b7defb8aea323f6c47ff82ce62a0fb1138cf9016c9e1a32bbc2f`;
  and
- complete promotion-lifecycle manifest SHA-256:
  `9fa08e0b47ae264d6d29382bbe6407a7bcdd1e0a61c2964d3592efa573b662f2`.

Numbered Script 11 now implements the frozen small-footprint deployment-package
assembly boundary. It requires the exact Script 07/08 handoffs and the complete
Script 09 and Script 10 lifecycle evidence before copying any payload. It
generates the final application release record, a classified 25-file package
manifest, a package-state receipt, and one complete checksum manifest; invokes
the portable verifier from the assembled directory; and publishes atomically
only to the local candidate lane. The generated receipt remains
`assembled_pending_security_inventory_and_independent_review`, and the
deployer refuses mutation until a later reviewed promotion changes that state
to `deployment_ready`.

The Script 11 harness passed success, rerun, supersession, acceptance-gate,
artifact/tmp capacity, payload-copy failure, generated-record failure, cleanup,
checksum, image-provenance, image-identity, classified-manifest,
portable-verification, and package-terminology branches. Every unexpected
failure now emits actionable detail and the standalone Script 11 result. The
complete portable deployment-entrypoint harness also proved review-state
correlation, candidate
refusal before mutation, clean installation, schema, lifecycle, failure
cleanup, and guarded removal. All earlier deployment lifecycle harnesses passed
after the change. Fresh scans of the real application archive, portable carry
sources, and runtime handoff found no prohibited repository, workstream,
agent, local-path, or test-host terminology. A fresh complete native run passed
486/486 tests.

The real Script 11 run then exposed that the Windows-backed transfer filesystem
cannot honor `chmod` even though it can safely store the package bytes. Script
11 was corrected to use mode-neutral candidate storage, record the required
Unix modes in `PACKAGE_MANIFEST.json`, validate that classification, and leave
mode materialization to the native Tech installer. A dedicated chmod-hostile
storage branch and every prior carry/deployment lifecycle branch pass after
that correction. The corrected real invocation published and independently
verified the 25-file, 173,989,414-byte candidate. Exact evidence identities
are:

- assembly report SHA-256:
  `58b94197f57e531a44fcfab44964f26d605c9536daa06ee92bbbc204446fe77f`;
- package-manifest SHA-256:
  `ade4973399b548467fe836b6c0d6a097ddec6741d14899a94f56186a36b123aa`;
- package-receipt SHA-256:
  `89a8c3ca3d7f0d1f7877700a161a7e06518a5a9ad3ef70a23a97ad4c3616c5dc`;
  and
- complete checksum-manifest SHA-256:
  `a5659c63339b82608b300e7c354dc60b777b5564a19eaf6b422f1d461f1b0d52`.

The mandatory post-assembly exact-image scan subsequently opened an advisory
decision. V13-92 resolved that decision by selecting a corrected,
package-manager-free runtime. The prior candidate remains intact and
non-installable as historical evidence; it is not a carry candidate. See
`deployment/evidence/ISHIKAWA_V1_3_1_SECURITY_REVIEW.md`.

The remaining ordered gates are:

1. run and accept Script 12 against the exact corrected runtime, then clean up
   only its isolated qualification candidate;
2. promote the accepted corrected runtime on EmceeDanko and reassemble the
   carry from its new exact lifecycle evidence;
3. accept the read-only Tech inventory and resolve any required offline native
   prerequisite payload;
4. complete independent review and atomically promote the exact carry bytes to
   the stable handoff.

Current disposition:

`ishikawa_v1_3_1_local_implementation=pass;carry_ready=false`
