# Native PostgreSQL Application Schema Migration Second-Run Block — 2026-10-19

## Disposition

The second operator-executed Script `20` run is blocked and is not accepted as
a completed migration.

Blocked report:

- `native_postgresql_application_schema_migration_20261019T160247Z_qIsMio.txt`
- SHA-256:
  `1c4154eb3e125113e0baa89c532d5ce7bc06c5e17801bf1edd6c7c39a8b198e1`

The receipt proves payload verification, PostgreSQL start/readiness, loopback-
only listening, nonzero migration execution, clean cluster-stop cleanup, and
complete temporary cleanup. No pass marker was emitted and the transactional
migration was not accepted.

The failure occurred at the guarded `psql` invocation before the classifier
could emit SQLSTATE. The generic Bash `ERR` trap intercepted the expected
nonzero status even though `errexit` was temporarily disabled. The corrected
canonical helper now executes `psql` as an explicit conditional, which keeps
fail-closed behavior while allowing the bounded diagnostic classifier to run.
The SQL migration is unchanged, and no separate repair script is introduced.
