# Native PostgreSQL Advisory Review Block

## Reviewed Input

The review used the accepted Script `06` report and bundle recorded in
`native_postgresql_package_capture_acceptance_2026-10-18.md`. The relevant
captured versions are:

- `postgresql-16=16.15-0ubuntu0.24.04.1`;
- `libpq5=16.15-0ubuntu0.24.04.1`;
- `postgresql-client-16=16.15-0ubuntu0.24.04.1`;
- `postgresql-16-pgvector=0.6.0-1`; and
- `python3-psycopg=3.1.17-2`.

This was a read-only public-advisory review. No package was transferred or
installed, no database was initialized, and no target service or
configuration was changed.

## Authoritative Findings

Canonical USN-8653-1 identifies
`postgresql-16=16.15-0ubuntu0.24.04.1` as the corrected PostgreSQL version for
Ubuntu 24.04 LTS. The captured PostgreSQL server, client, and `libpq5`
packages use that source version.

Canonical currently records two applicable pgvector findings:

1. CVE-2026-3172 affects pgvector `0.6.0` through `0.8.1`. A database user can
   trigger a buffer overflow during a parallel HNSW index build, potentially
   leaking data from other relations or crashing PostgreSQL. Canonical gives
   the issue CVSS 8.1 High and records Ubuntu 24.04 pgvector as `Needs
   evaluation`.
2. CVE-2026-103484 affects pgvector versions before `0.8.7`. An IVFFlat index
   build can write out of bounds and potentially allow arbitrary code
   execution. Canonical gives the issue CVSS 8.8 High and records Ubuntu 24.04
   pgvector as `Needs evaluation`.

The upstream pgvector changelog records the parallel-HNSW correction in
`0.8.2` and the IVFFlat correction in `0.8.7`. Therefore the captured Ubuntu
Noble package `postgresql-16-pgvector=0.6.0-1` is below both correction
versions.

Sources reviewed on 2026-10-18:

- <https://ubuntu.com/security/notices/USN-8653-1>
- <https://ubuntu.com/security/CVE-2026-3172>
- <https://ubuntu.com/security/CVE-2026-103484>
- <https://github.com/pgvector/pgvector/blob/master/CHANGELOG.md>

## Gate Result

The bundle is **not approved for transfer or installation**. PostgreSQL
16.15 itself matches Canonical's corrected Noble version, but the bundle as a
whole fails the advisory gate because its pgvector package is affected by two
current index-build vulnerabilities.

Review stopped at this material blocker. This record does not claim complete
clearance of Psycopg or every supporting package, because completing those
checks cannot make the current bundle installable.

The accepted capture remains immutable evidence of what Ubuntu Noble offered
at capture time. It must not be relabeled as an approved installation bundle.

## Next Decision

Do not make a risk exception for pgvector `0.6.0-1`. Select one of these
separate paths before producing a replacement bundle:

1. wait for an Ubuntu Noble pgvector security update at or beyond the version
   that corrects both findings; or
2. explicitly approve qualification and offline capture of pgvector `0.8.7`
   or later from a reviewed non-Noble source.

The second path expands the approved-source and build/package-capture surface.
It must not be introduced silently. The existing PostgreSQL 16.15 and Psycopg
selection can remain candidates, but all exact replacement-bundle versions
must receive a fresh advisory review before transfer or installation.
