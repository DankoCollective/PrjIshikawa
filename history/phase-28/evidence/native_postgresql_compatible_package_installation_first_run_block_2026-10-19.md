# Compatible Native PostgreSQL Package Installation First-Run Block — 2026-10-19

## Disposition

Script `12` did not pass. The guarded installer reached the first local support-
package transaction, and apt returned exit `100`. The PostgreSQL server and
pgvector transaction did not run.

Blocked report:

- `local/reports/native-postgresql-compatible-package-installation/native_postgresql_compatible_package_installation_20261019T135104Z_r7EYz6.txt`
- SHA-256: `3c2286267afb1b2028d3fa2f9b31b58fef736bb5815299b88f84727fcb0c8ebd`

Accepted facts:

- the exact Script `11` report and bundle hashes were verified;
- SSH authentication and target payload verification passed;
- the target remained Ubuntu `24.04` AMD64;
- the support-package apt action returned exit `100`;
- the installer stopped before automatic-cluster configuration and before the
  PostgreSQL server/pgvector transaction;
- the wrapper returned one blocked marker and no pass marker;
- temporary target payloads and the SSH control session were removed.

The apt stdout and stderr hashes were recorded, but their bounded diagnostic
content was not returned. Package installation can be non-atomic, so no claim
is made yet about which support packages, if any, reached configured state.
Do not rerun Script `12` until exact package and apt state is inspected.

## Next gate

Run the separate read-only Script `13` inspection. It reports the state of all
nine selected packages, dpkg audit state, bounded apt diagnostics, offline
simulation results, and PostgreSQL service/cluster/listener state. It performs
no installation or repair.

