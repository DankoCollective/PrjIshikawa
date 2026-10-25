# Native PostgreSQL Compatible Installation Preflight Source Ready

## Purpose

Script `11` is the read-only target gate for the accepted compatible Script
`10` bundle. It stages only a neutral helper and the checksum-bound bundle in
private target `/tmp`, verifies both, simulates the exact offline install,
retrieves a bounded report, and removes all target temporary files.

The preflight does not use sudo and performs no apt update, network package
download, package installation, database initialization, service mutation,
configuration mutation, secret/content read, or persistent target write.

## Bound inputs and identities

- accepted Script `10` report SHA-256:
  `bdc45bce2858dc219bdc02e57a3419bfe0248743ac282ce75acfd7c4cfbcd7fc`;
- accepted bundle SHA-256:
  `147dd47979d002ac6a7beabafd1a048cf6aa8da8cb6c54993c83b0cb74ab9e05`;
- Script `11` SHA-256:
  `530c4aa8ef96e11f1a26ad5a95e4dd7e45c2a1b9784e6226614e522c9fe480ac`;
- neutral helper SHA-256:
  `e7b9d07b828a3a6948e96c20cd8f91fe6c15071d15466d5b76d0a0696d1caf59`;
- neutral helper size: `12759` bytes.

## Exact state contract

The helper requires:

- Ubuntu 24.04 AMD64 on the expected host;
- the accepted nine package tuples and all internal checksums;
- seven accepted advisory rows and nine present license rows;
- PostgreSQL JIT virtual version `19` and the matching pgvector constraint;
- existing `libllvm19=1:19.1.1-1ubuntu1~24.04.2` exactly;
- the other eight selected packages not yet installed;
- no PostgreSQL cluster or active service;
- free loopback port 5432; and
- at least 2 GiB free under `/var`.

The apt simulation must install the eight pending packages, may optionally
show the exact existing libllvm19 as a reinstall, must select no package
outside the nine-package set, and must remove nothing.

## Local validation and command

Both shell files pass syntax validation. The wrapper's `--validate-only`
check passes without target contact, and the neutral helper contains no phase,
decision-ID, lab, agent, or repository terminology.

The operator runs from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/11_preflight_compatible_native_postgresql_installation.sh
```

The returned report must be reviewed before any installation is authorized.
