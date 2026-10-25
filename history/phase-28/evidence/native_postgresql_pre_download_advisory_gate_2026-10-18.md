# Native PostgreSQL Pre-Download Advisory Gate

## Correction To Capture Discipline

The operator correctly identified that advisory review belongs before package
payload download, not after it. The corrected order is now:

1. resolve exact package and source versions from signed metadata;
2. review every selected source/version and record a disposition;
3. block on any missing, pending, or applicable unresolved finding;
4. only then download package payloads;
5. verify repository signature, package hash, size, control fields, licenses,
   and bundle checksums; and
6. retain installation as a separate later gate.

The accepted Script `06` capture is historical evidence. Its pgvector package
failed the later advisory gate, and that bundle remains prohibited from
transfer or installation. Script `07` implements the corrected pre-download
order for the replacement capture.

## Reviewed Replacement Set

The final nine-package payload maps to six source packages. Every source and
exact version now has a recorded pre-download decision in
`../reference/native-postgresql-advisory-review-v1.tsv`:

- `libjson-perl=4.10000-1`: accepted; no applicable current Canonical finding
  identified;
- `postgresql-common=257build1.1`: accepted; Canonical's listed findings are
  historical and do not affect Noble;
- `llvm-toolchain-17=1:17.0.6-9ubuntu1`: accepted as not applicable for this
  AMD64 runtime; CVE-2024-7883 concerns Arm Cortex-M Security Extensions code
  generation;
- `postgresql-16=16.15-0ubuntu0.24.04.1`: accepted fixed by Canonical
  USN-8653-1; this source covers server, client, and `libpq5` payloads;
- `psycopg3=3.1.17-2`: accepted; no applicable current Canonical or upstream
  published security advisory identified; and
- `pgvector=0.8.7-1.pgdg24.04+1`: accepted fixed for CVE-2026-3172 and
  CVE-2026-103484.

The review was performed against current authoritative Canonical, PostgreSQL
project, pgvector upstream, and Psycopg upstream material on 2026-10-18. The
decision is scoped to Ubuntu 24.04 AMD64 and these exact coordinates. A version,
source, OS, or architecture change invalidates the gate.

## Alternate Source Qualification

The PostgreSQL Global Development Group maintains the official PostgreSQL Apt
repository and supports Ubuntu Noble on AMD64. Its signed Noble pool contains
the exact native package
`postgresql-16-pgvector=0.8.7-1.pgdg24.04+1`.

Script `07` does not configure that repository on any host. It locally:

- validates the six-source advisory decision set before package download;
- downloads the official PostgreSQL repository key and signed metadata;
- verifies key fingerprint
  `B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8`;
- verifies the `noble-pgdg` `InRelease` signature and signed package-index
  checksum;
- selects the exact reviewed AMD64 package record;
- only after those gates downloads that one replacement `.deb`;
- verifies its signed hash, size, package, version, architecture, source, and
  dependency contract;
- reuses the eight already verified Ubuntu packages and excludes pgvector
  `0.6.0-1`; and
- creates a new checksum-bound bundle with installation still unauthorized.

No compilation, additional container, target repository change, apt update,
target contact, package installation, database initialization, or service
mutation is authorized.

## Sources

- <https://www.postgresql.org/download/linux/ubuntu/>
- <https://wiki.postgresql.org/wiki/Apt>
- <https://apt.postgresql.org/pub/repos/apt/pool/main/p/pgvector/>
- <https://ubuntu.com/security/notices/USN-8653-1>
- <https://ubuntu.com/security/CVE-2024-7883>
- <https://ubuntu.com/security/CVE-2026-3172>
- <https://ubuntu.com/security/CVE-2026-103484>
- <https://github.com/pgvector/pgvector/blob/master/CHANGELOG.md>
- <https://www.psycopg.org/psycopg3/docs/news.html>

## Locally Proven Command Surface

Script syntax, `--validate-only`, and `--plan-only` passed locally. The plan
verified the accepted predecessor checksum, all six exact advisory decisions,
and the replacement pgvector coordinate without target contact or package
download.

- Script `07` SHA-256:
  `f1986642964779f57bba9a4f53c0c4e55751f2a27d9ec676637090cdfe7a4c9e`.
- Advisory decision-set SHA-256:
  `e8f22b80fcf39bb49736fb258d14be43244f107ceef0bd4baf85352fefca55e1`.

The first operator run subsequently blocked after this advisory gate and
before package download because the initial implementation selected an index
compression format not published by PGDG. The separate signed-index repair
record preserves that historical result and the corrected source identity.
The next operator action remains the default Script `07` capture command from
the repository root. Its output must be reviewed before transfer or
installation.
