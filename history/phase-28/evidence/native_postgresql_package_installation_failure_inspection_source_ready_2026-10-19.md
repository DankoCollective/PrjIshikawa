# Native PostgreSQL Package Installation Failure Inspection Source Ready — 2026-10-19

## Disposition

Script `13` and its neutral helper are source-ready for a read-only inspection
of the Script `12` apt exit `100`.

Source identities:

- `13_inspect_native_postgresql_installation_failure.sh`
  - SHA-256: `f94aa7171a8eeed67342f3d528a0ece9914ee897b2102a3b28adbd52c91b5c56`
- `inspect-native-database-package-installation-failure`
  - SHA-256: `2db0f537446a6212ffa0aee100ce3f7957981e72c9e68b0b2b095dc65d988cf8`
  - bytes: `10629`

The wrapper binds the exact blocked Script `12` receipt and accepted package
bundle. The helper reports:

- exact status, version, and architecture for all nine selected packages;
- dpkg audit line count, checksum, and bounded diagnostic lines;
- bounded apt terminal/history diagnostics and checksums;
- a no-download simulation of the six support packages;
- a read-only apt dependency check;
- temporary service-policy residue, automatic-cluster policy, PostgreSQL
  service state, cluster count, and port `5432` state.

It does not install or repair a package, initialize a database, change a
service or configuration, or access a package network.

Local validation passed:

```text
native_postgresql_package_installation_failure_inspection_source=pass
target_contact=false
package_install=false
target_mutation=false
```

Operator command:

```bash
bash ./phase-28-apisachi-tokuli/scripts/13_inspect_native_postgresql_installation_failure.sh
```

