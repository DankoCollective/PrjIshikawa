# Native PostgreSQL Installation Preflight Source Ready

## Purpose

Script `08` is the next operator-controlled gate after acceptance of the
native PostgreSQL replacement bundle. It copies only a neutral helper and the
accepted checksum-bound bundle to an explicit private target `/tmp` directory,
verifies both payloads, runs a read-only offline installation simulation,
retrieves a bounded result, and removes the temporary target directory.

It does not use sudo and does not update apt metadata, download a package,
install a package, initialize a database, start or enable a service, change a
configuration, or read application content or secrets.

## Frozen Inputs

- accepted Script `07` report SHA-256:
  `1928d5322ecd311a99f6129041e4ae27a211dcef88bcb8e3b95e9ecd8b2669a4`;
- accepted bundle SHA-256:
  `d091792ace6a1f5b1ac76d686e2464f52e61240c47e44eaf74670eaef0dfbff5`;
- accepted target: EmceeDanko, Ubuntu `24.04`, AMD64;
- expected package count: nine;
- expected pgvector package:
  `postgresql-16-pgvector=0.8.7-1.pgdg24.04+1` AMD64.

## Preflight Contract

The neutral helper requires:

- exact hostname, Ubuntu version, and AMD64 architecture;
- exact outer and all internal bundle checksums;
- safe archive paths and one bundle root;
- exact capture-summary invariants;
- exact nine package/version/architecture tuples;
- matching package-register hashes;
- nine present license records;
- no selected package already installed;
- no PostgreSQL cluster, active PostgreSQL service, or listener on port 5432;
- at least 2 GiB free under `/var`; and
- an `apt-get --simulate --no-download --no-install-recommends` result that
  installs exactly the nine accepted packages and removes none.

The helper emits only bounded facts. Raw apt output and SSH stderr are not
retained. The target sees neutral filenames and no phase, decision-list, or
development-environment terminology.

## Local Proof

Syntax and `--validate-only` pass. Validation binds the accepted report and
bundle without target contact or package installation.

- Script `08` SHA-256:
  `f51aae05eaa67a2c11827e174f1020e6bebbdd40cefd5fd2fb966e58ae48f755`;
- neutral helper SHA-256:
  `04b12332fd3eb06450cd79446e48e9d654e71e45dd3377a8c710e09e54c2bc84`.

These hashes must be refreshed after any source change. The operator runs the
default command from the repository root and may be prompted once for the SSH
key passphrase. No target sudo password is requested.

```bash
bash ./phase-28-apisachi-tokuli/scripts/08_preflight_native_postgresql_installation.sh
```

The resulting report must be reviewed before any native package installation
is authorized.

Subsequent execution identified a hard JIT virtual-package conflict in the
accepted bundle. Script `08` must not be rerun against that package set. This
source-ready record is retained as historical preflight evidence; the separate
compatibility block owns the current no-transfer/no-install disposition.
