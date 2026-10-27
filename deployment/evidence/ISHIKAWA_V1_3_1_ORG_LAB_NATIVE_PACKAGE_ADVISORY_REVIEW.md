# Ishikawa v1.3.1 Org-Lab Native-Package Advisory Review

## Current disposition

`direct_package_advisory_review=pass;exact_dependency_closure_review=pending_capture;deployment_scope=org_lab_only;danko_lab_installation=false`

Review date: 2026-10-26

The exact proposed PostgreSQL 16, libpq, pgvector, PostgreSQL common, and
Psycopg direct-package versions have no unresolved published action-required
advisory as of this review. This clears the versions for controlled package
capture on the org development workstation. It does not clear an as-yet
uncaptured transitive dependency closure.

## Environment and installation boundary

The capture is designed to take place from the org development station's copy
of this repository. Captured package bytes, their resolver plan, checksums,
licenses, and scan evidence will be staged with the Ishikawa carry material
there and later installed only on the org-lab Tech system.

These native packages are not downloaded, installed, or activated in
danko_lab. EmceeDanko's accepted Ishikawa v1.3.1 application, runtime image,
PostgreSQL installation, database, corpus, and services are unchanged by this
review. No Tech or EmceeDanko contact was performed while producing it.

## Direct-package boundary

The proposed direct set is:

| Package | Exact version | Architecture | Expected repository-index SHA-256 |
| --- | --- | --- | --- |
| `python3-psycopg` | `3.3.2-1build1` | `all` | `e03bef68d5c5456a801309fb330c2814007f265431f2ba97c0a046805731dc53` |
| `postgresql-common` | `293.pgdg26.04+1` | `all` | `4b830ea730e0de1f6d0c80cee8db3d540185765c933c9ad6537372101f6aae92` |
| `postgresql-client-common` | `293.pgdg26.04+1` | `all` | `d2ac3e8c35c774fa1e48dd6146b1a5937617496df23f46cf101183dcf51f60c4` |
| `libpq5` | `18.6-1.pgdg26.04+2` | `amd64` | `a56bfe4843ae432e7338d0139190397db69a343412e489ae637bfb39c2d6fc30` |
| `postgresql-client-16` | `16.15-1.pgdg26.04+2` | `amd64` | `52fd38615ce65bd9b0442a21e611986e0cc7b87e1143e2464668be17fcb77314` |
| `postgresql-16` | `16.15-1.pgdg26.04+2` | `amd64` | `029e7af139dafe488a1950531824d61b17d07990879380f459e79b0f15420512` |
| `postgresql-16-pgvector` | `0.8.7-1.pgdg26.04+1` | `amd64` | `9a853bba89e2811d0dfeda853ff94ca6d8e84f01a088327ba8b781d99bc083d7` |

The hashes above are expected values from the signed repository metadata or
the operator-supplied Tech inventory. They are not claims that those bytes
have been captured in danko_lab. The org development station must calculate
and compare local SHA-256 values after download.

`libpq5` version `18.6` is the current shared PostgreSQL client library. Its
presence does not install or select the PostgreSQL 18 database server. The
server and client program packages remain explicitly pinned to PostgreSQL
`16.15`.

## Advisory findings

### PostgreSQL server, client programs, and libpq

PostgreSQL's authoritative version-16 security table identifies `16.15` as
the fixed PostgreSQL 16 release for the latest published server and client
advisories, including the 2026 server memory-safety, authorization, logical
decoding, `pg_dump`, and `psql` findings. Older findings are fixed in earlier
16.x releases. The current table contains no known finding requiring a release
newer than `16.15`.

The selected `postgresql-16` and `postgresql-client-16` packages therefore
contain the published fixes through PostgreSQL `16.15`. The selected
`libpq5 18.6` is from the matching current upstream security release family
and includes the client-library fixes through `18.6`.

Disposition: **pass; no unresolved published action-required PostgreSQL core,
client-program, or libpq advisory for the selected versions.**

### pgvector

The selected pgvector `0.8.7` closes every currently published pgvector CVE
identified by the upstream changelog and Debian security tracker:

- `CVE-2026-3172`, parallel HNSW index-build buffer overflow, affects
  `0.6.0` through `0.8.1` and is fixed in `0.8.2`;
- `CVE-2026-18022`, 32-bit IVFFlat index-build integer wraparound, affects
  `0.8.5` and earlier and is fixed in `0.8.6`; and
- `CVE-2026-103484`, IVFFlat index-build out-of-bounds write and possible
  arbitrary code execution, affects `0.8.6` and earlier and is fixed in
  `0.8.7`.

The upstream GitHub advisory tab has no additional published advisory.

Disposition: **pass; all published pgvector CVEs are fixed in `0.8.7`, with
no additional published action-required finding.**

### postgresql-common and postgresql-client-common

Debian's source-package tracker lists only historical resolved issues for
`postgresql-common`; the newest listed affected thresholds predate package
version `293`. It lists no open issue for the selected current package family.

Disposition: **pass; no unresolved published action-required advisory for
`293.pgdg26.04+1`.**

### Psycopg

Ubuntu 26.04 publishes `python3-psycopg 3.3.2-1build1`. Psycopg's upstream
GitHub advisory tab and advisory API contain no published advisory. Later
upstream 3.3.x releases contain maintenance and correctness changes, but the
review found no published security advisory that marks `3.3.2` affected or
requires a later version.

Disposition: **pass for known published advisories; the Ubuntu package remains
subject to exact-byte and transitive-dependency scanning after capture.**

## Mandatory capture-time closure gate

The direct-version review does not substitute for scanning the actual files.
Before the package set can enter the final org-lab carry, the org development
station must:

1. verify the PGDG `InRelease` signature through APT's `Signed-By` key;
2. retain the download-only resolver plan and complete `.deb` file list;
3. compare every direct package with the expected SHA-256 above;
4. record SHA-256 for every transitive dependency selected by APT;
5. record package name, source, version, architecture, license, and repository
   provenance for the complete closure;
6. scan the exact closure using current advisory data;
7. disposition every reported record and stop on an unresolved
   action-required finding; and
8. prove offline installation and PostgreSQL 16/pgvector operation before
   final carry publication.

Until those steps pass, the correct state is:

`direct_versions=advisory_clear;captured_dependency_closure=not_yet_qualified`

## Authoritative sources

- PostgreSQL 16 security table:
  <https://www.postgresql.org/support/security/16/>
- PostgreSQL 16.15 release notes:
  <https://www.postgresql.org/docs/16/release-16-15.html>
- PostgreSQL Ubuntu/PGDG instructions:
  <https://www.postgresql.org/download/linux/ubuntu/>
- PostgreSQL `resolute-pgdg` signed distribution:
  <https://apt.postgresql.org/pub/repos/apt/dists/resolute-pgdg/>
- pgvector changelog:
  <https://github.com/pgvector/pgvector/blob/master/CHANGELOG.md>
- pgvector `CVE-2026-103484` upstream record:
  <https://github.com/pgvector/pgvector/issues/1036>
- pgvector `CVE-2026-18022` upstream record:
  <https://github.com/pgvector/pgvector/issues/1006>
- pgvector `CVE-2026-3172` upstream record:
  <https://github.com/pgvector/pgvector/issues/959>
- Debian pgvector tracker:
  <https://security-tracker.debian.org/tracker/source-package/pgvector>
- Debian postgresql-common tracker:
  <https://security-tracker.debian.org/tracker/source-package/postgresql-common>
- Psycopg upstream advisories:
  <https://github.com/psycopg/psycopg/security/advisories>
- Ubuntu 26.04 `python3-psycopg` package identity:
  <https://packages.ubuntu.com/resolute/python3-psycopg>

