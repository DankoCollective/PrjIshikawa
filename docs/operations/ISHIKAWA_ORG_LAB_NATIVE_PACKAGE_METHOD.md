# Ishikawa Org-Lab Native Package Method

## Status and scope

This is the controlling durable method for capturing, qualifying, carrying,
and installing Ishikawa's native prerequisites on the org-lab Tech system.
It records the operator-approved execution posture as of 2026-10-27.

Target facts:

- Tech runs Ubuntu 26.04 `resolute` on AMD64.
- The internet-connected work laptop may run Ubuntu 24.04 `noble`; its local
  release and installed-package state do not select the Tech package set.
- PostgreSQL server and client remain version 16.
- pgvector remains the native PostgreSQL 16 extension.
- Package capture does not contact or mutate Tech.
- Package installation on Tech is attended and local-file-only.

This method does not authorize rebuilding either accepted Ishikawa v1.3.1
application or runtime-image archive.

## Controlling sequence

1. Use an isolated APT root on the internet-connected work laptop.
2. Load signed Ubuntu 26.04 `resolute` and PGDG `resolute-pgdg` AMD64 metadata
   into that isolated root. Do not modify or use the work laptop's normal APT
   source or package state for target resolution.
3. Resolve the complete AMD64 dependency closure from an empty target package
   state.
4. Download the exact pinned PostgreSQL 16, pgvector, Psycopg, and dependency
   packages without installing them on the work laptop.
5. Retain the signed repository indexes and PGDG signing-key identity with the
   capture evidence.
6. Generate the exact package manifest and SHA-256 records. Verify direct
   package bytes against their records in the signed repository metadata.
7. Prove installation from only the captured bytes in a disposable Ubuntu
   26.04 AMD64 environment. The proof must make network repositories
   unavailable to the APT transaction and validate PostgreSQL 16 and pgvector
   operation.
8. Add the qualified native-package shelf as a distinct component of the final
   Ishikawa carry without changing the accepted application or runtime-image
   bytes.
9. Transfer the final carry to Tech and install the native prerequisites from
   the carried absolute local `.deb` paths with empty APT source and list
   configuration.

## Transfer-verification decision

Origin-side repository-signature, repository-index, direct-package hash,
manifest, advisory, and offline-install qualification remain mandatory.

For this carry, the operator has waived a second per-file checksum comparison
between the work laptop and Tech. Successful transfer and extraction may
proceed directly to the local-only APT simulation and attended installation.
The checksum records remain in the shelf for provenance, later audit, and
troubleshooting, but repeating them on Tech is not an acceptance gate.

This waiver does not permit target-side package downloads, substitution of a
different package version, or installation from outside the qualified shelf.

## Direct package identities

The reviewed direct set is:

| Package | Version | Architecture |
| --- | --- | --- |
| `python3-psycopg` | `3.3.2-1build1` | `all` |
| `postgresql-common` | `293.pgdg26.04+1` | `all` |
| `postgresql-client-common` | `293.pgdg26.04+1` | `all` |
| `libpq5` | `18.6-1.pgdg26.04+2` | `amd64` |
| `postgresql-client-16` | `16.15-1.pgdg26.04+2` | `amd64` |
| `postgresql-16` | `16.15-1.pgdg26.04+2` | `amd64` |
| `postgresql-16-pgvector` | `0.8.7-1.pgdg26.04+1` | `amd64` |

The exact expected direct-package hashes and point-in-time advisory findings
remain in
`deployment/evidence/ISHIKAWA_V1_3_1_ORG_LAB_NATIVE_PACKAGE_ADVISORY_REVIEW.md`.
Transitive dependencies are selected and recorded by the isolated target APT
resolver; they are not guessed or copied from the work laptop's installed
state.

## Initial execution order

The first controlled capture may exercise the complete sequence with
`python3-psycopg` and its resolved dependency closure. After that lane passes,
resolve the full direct set together so APT selects one internally consistent,
deduplicated shelf. Do not create seven unrelated final shelves.

For this first-package exercise, the item 7 proof is a local-only installation
and Python import of Psycopg in disposable Ubuntu 26.04 AMD64. It validates the
capture and offline-install mechanics but does not satisfy the final
PostgreSQL 16/pgvector operational proof. That final proof occurs once against
the complete combined shelf.

The accepted operator interface for this capture is the single standalone
`deployment/carry/capture-native-prerequisites` file. It has no repository
runtime dependency and may be carried alone to the internet-connected work
laptop. Preserve its command output, signed metadata, downloaded packages,
and generated records until the final outer carry is accepted.

After capture, use the separate standalone
`deployment/carry/qualify-native-prerequisites` file on the work laptop. It
verifies the origin shelf and performs the item 7 local-file-only installation
and operation proof inside a disposable network-disabled Ubuntu 26.04 AMD64
container. Docker access may be direct or attended through its explicit
`--sudo-docker` option. When the option is omitted, the qualifier attempts
direct Docker access and automatically falls back to one attended sudo
validation if required. The qualification does not contact Tech.

## Stop conditions

Stop before transfer or installation if any of these occurs:

- an Ubuntu or PGDG repository signature does not validate;
- the PGDG signing-key fingerprint is not the reviewed identity;
- a pinned direct package is absent or its signed-index hash differs;
- the resolver cannot produce one complete closure;
- an unresolved action-required advisory is found in the captured closure;
- local-only offline installation or PostgreSQL 16/pgvector operation fails;
- the accepted Ishikawa application or runtime-image bytes would need to
  change; or
- Tech facts conflict with the frozen Ubuntu 26.04 AMD64 architecture.

## Established precedents

- `/mnt/g/dankorepos/prj00dankodeux/phase-21-org-lab/docs/ORG_LAB_LIGHTWEIGHT_TRANSFER_DISCIPLINE.md`
- `/mnt/g/dankorepos/prj00dankodeux/phase-21-org-lab/docs/ORG_LAB_CURL_8_22_0_CAPTURE_REVIEW.md`
- `/mnt/g/dankorepos/prj00dankodeux/phase-01-vllm-runtime/docs/ARM64_DEB_LOCAL_INSTALL_METHOD.md`

These precedents establish target-specific package capture on an external
internet-connected system, signed-metadata and package-hash qualification,
checksum-bound shelves, and target installation from carried local files with
network repositories disabled.
