# Native PostgreSQL Package Capture Virtual-Dependency Block

## Result

The first operator-executed Script `06` run stopped safely during target apt
metadata resolution. It did not download a package, install anything,
initialize PostgreSQL, or change a target service or configuration. The
blocked local report is:

- `native_postgresql_package_capture_20261019T025921Z_6tepFk.txt`;
- SHA-256
  `92cf4f1e3bed3f29ea0b5e74494275d6967b6a93f40818199703ea89a8a9e01c`;
- 1,273 bytes and 11 lines; and
- terminal result `dependency_closure_incomplete`.

No package artifact or transfer bundle was created.

## Cause

Ubuntu's `postgresql-16-pgvector` package depends on the virtual package
`postgresql-16-jit-llvm (>= 17)`. The concrete accepted
`postgresql-16=16.15-0ubuntu0.24.04.1` package provides that virtual package.
The first helper required every dependency name to have its own archive and
therefore rejected the valid virtual dependency instead of selecting its
concrete provider.

The review also found that `apt-cache show --no-all-versions` can select an
already-installed dpkg status stanza without archive filename, size, or hash
metadata. That behavior is unsuitable for an offline closure.

## Repair And Local Proof

The neutral helper now:

- resolves each concrete package through its exact apt candidate version;
- resolves virtual dependencies through apt's `Reverse Provides` metadata,
  preferring an already-approved root provider;
- reports bounded unresolved-dependency coordinates on a future block; and
- accepts an explicit expected architecture while Script `06` remains pinned
  to target `amd64`.

The corrected helper completed a no-download, no-install closure-resolution
replay against the local Ubuntu 24.04 apt metadata: four roots, 98 resolved
packages, 98 package URIs, and zero unresolved dependency rows. This replay
used the local ARM64 archive metadata only to exercise the resolver; the
operator rerun remains necessary to capture the accepted target AMD64 closure.

Corrected identities at that gate:

- `06_capture_native_postgresql_package_closure.sh` SHA-256:
  `21ac9840cb293a3f0490ce7e17058cc74644608a60e1a980a5109e7489d25c53`;
- `collect-native-postgresql-package-metadata` SHA-256:
  `8a728b1fcd8e2ad6b31a1fc5120fe3c5f69316700927382fa159714741096ca4`.

Shell syntax, `--validate-only`, `--plan-only`, and repository diff checks pass.
The accepted four roots and Script `05` inventory are unchanged. Transfer and
installation remain unauthorized.

The later local-resume repair supersedes the Script `06` identity recorded at
this gate without changing the accepted roots or helper identity.

## Rerun Gate

From the repository root, the operator may rerun the same command:

```bash
bash ./phase-28-apisachi-tokuli/scripts/06_capture_native_postgresql_package_closure.sh
```

Stop after the command and review the new report and checksum-bound bundle
before any transfer or installation.
