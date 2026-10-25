# Native PostgreSQL Package Capture Ready

## Result

Script `06` and its neutral metadata helper were locally validated and made
ready for operator execution. The first operator run later stopped safely on
a virtual-package resolver defect. The corrected current sources are ready for
a same-command rerun. No package was downloaded or installed by the blocked
run.

## Source Identities

- `06_capture_native_postgresql_package_closure.sh` SHA-256:
  `3971b9d863cca3477a72cfa2360a0738779c0b26d73568dafb8ce228f82ad3ae`.
- `collect-native-postgresql-package-metadata` SHA-256:
  `8a728b1fcd8e2ad6b31a1fc5120fe3c5f69316700927382fa159714741096ca4`.
- Accepted inventory report SHA-256:
  `d0bb756ac6b90be0be44660d5f649ba89b593bc6350577237d8a371b28459943`.

## Validated Root Plan

- `postgresql-16=16.15-0ubuntu0.24.04.1`.
- `postgresql-client-16=16.15-0ubuntu0.24.04.1`.
- `postgresql-16-pgvector=0.6.0-1`.
- `python3-psycopg=3.1.17-2`.

The source syntax check, no-target `--validate-only` check, and accepted-report
`--plan-only` check passed. The helper blocks candidate drift, unresolved
dependency metadata, incomplete package URIs, OS/architecture mismatch, and
missing apt hashes.

After the first run identified Ubuntu's virtual `postgresql-16-jit-llvm`
dependency, the resolver was corrected to select the concrete
`postgresql-16` provider. A local Ubuntu 24.04 no-download replay resolved 98
packages and 98 package URIs with zero unresolved rows. The separate block and
repair record retains the first report identity and exact non-actions.

## Execution Boundary

The target performs read-only apt metadata resolution and writes only unique
temporary metadata state that the helper removes automatically. The target
does not update apt, download or install packages, initialize PostgreSQL,
change a service, change configuration, or expose protected content.

The local workstation downloads the exact target AMD64 Ubuntu package closure,
verifies SHA-256 and size, extracts inert package/file/license metadata,
captures public Ubuntu advisory sources, and creates a checksum-bound offline
bundle. Installation remains unauthorized until the captured advisories and
bundle are separately reviewed.

## Operator Command

From the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/06_capture_native_postgresql_package_closure.sh
```
