# Native PostgreSQL Package Capture Acceptance

## Accepted Result

The operator-executed Script `06` package-capture transaction is accepted with
advisory review explicitly pending. The accepted report is:

- `native_postgresql_package_capture_20261019T032934Z_Cm6Y8c.txt`;
- SHA-256
  `c8ed749c36b721f155e81dfcd1f5583d121c8ce582037a0a325346386fe442b1`;
- 2,251 bytes and 24 lines; and
- terminal result
  `native_postgresql_package_capture=pass_with_advisory_sources_pending`.

Script `06` SHA-256 is
`3971b9d863cca3477a72cfa2360a0738779c0b26d73568dafb8ce228f82ad3ae`.
The neutral helper SHA-256 is
`8a728b1fcd8e2ad6b31a1fc5120fe3c5f69316700927382fa159714741096ca4`.

## Bundle

- File:
  `native-postgresql-ubuntu24.04-amd64-20261019T030940Z.tar.gz`.
- Size: 43,722,508 bytes.
- SHA-256:
  `7e6d63ac7f3606c871ed83ce8a9b0eb022444550483dc45cd79293e8dde0a470`.
- Sidecar verification: `PASS`.
- Archive members: 59.
- Unsafe absolute or parent-traversal members: zero.
- Internal checksums: 51 passed, zero failed.

The bundle contains nine target-required packages totaling 43,797,374 package
bytes. Their local hashes exactly equal the accepted apt-metadata hashes:

- `libjson-perl=4.10000-1`;
- `postgresql-client-common=257build1.1`;
- `postgresql-common=257build1.1`;
- `libllvm17t64=1:17.0.6-9ubuntu1`;
- `libpq5=16.15-0ubuntu0.24.04.1`;
- `postgresql-client-16=16.15-0ubuntu0.24.04.1`;
- `postgresql-16=16.15-0ubuntu0.24.04.1`;
- `postgresql-16-pgvector=0.6.0-1`; and
- `python3-psycopg=3.1.17-2`.

All nine packages have captured copyright material. The retained dependency
metadata records the complete 98-package graph while avoiding downloads of 89
dependencies already satisfied on EmceeDanko.

## Boundary And Next Gate

No package was installed, no PostgreSQL cluster was initialized, and no
service or configuration was changed. Advisory affectedness remains
`pending_review`; all three public advisory sources are deliberately deferred
to a separate review gate. The bundle records `install_authorized=false`.

Transfer and installation are not authorized by this acceptance. Review the
three advisory sources and package versions separately before preparing the
EmceeDanko carry-verification or guarded-install command.

This Ubuntu 24.04 AMD64 bundle is not an org-lab Ubuntu 26 package bundle. The
org target requires its own inventory, exact package selection, capture, and
review.
