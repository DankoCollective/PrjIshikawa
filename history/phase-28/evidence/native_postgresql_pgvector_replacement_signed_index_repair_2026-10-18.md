# Native PostgreSQL pgvector Replacement Signed-Index Repair

## First Operator Run

The first operator-executed Script `07` run completed with a safe block, not a
capture pass. The retained report is:

- report: `native_postgresql_pgvector_replacement_20261019T034745Z_pF6Zih.txt`;
- report SHA-256:
  `9316bb7d0481d674f322e33afe8c0b1087ff64f9aa7ea11fa51a42e7ce096891`;
- executed script SHA-256:
  `bfc6f78a835ee96bafdf4e3c8ac99c84bdfcca928ac143dc34cfbff3b81527d9`;
- advisory decision-set SHA-256:
  `e8f22b80fcf39bb49736fb258d14be43244f107ceef0bd4baf85352fefca55e1`.

The complete six-source pre-download advisory gate passed. The script then
stopped at the signed repository-metadata stage before downloading the
pgvector package payload. It produced no replacement bundle, contacted no
target, installed nothing, and changed no database or service.

## Diagnosis And Repair

The script expected `main/binary-amd64/Packages.xz`. The signed PGDG Noble
`InRelease` publishes `Packages`, `Packages.gz`, and `Packages.bz2`, but not an
XZ index. The empty lookup caused Bash `read` to trigger the generic error trap
before the intended explicit missing-index result.

Script `07` now:

- selects the signed SHA-256 and size for `Packages.gz`;
- downloads and verifies that exact signed index;
- expands it with `gzip`;
- reports an explicit `pgdg_packages_index_not_signed` block if the signed
  coordinate is absent; and
- applies bounded connect and total timeouts to every public download.

The package selection, advisory decisions, replacement coordinate, accepted
Script `06` source bundle, target/non-action boundaries, and installation
prohibition did not change.

## Local Validation

Syntax, `--validate-only`, and `--plan-only` passed after repair. Both modes
performed no target contact or package download.

- corrected Script `07` SHA-256:
  `f1986642964779f57bba9a4f53c0c4e55751f2a27d9ec676637090cdfe7a4c9e`;
- accepted source-bundle SHA-256:
  `7e6d63ac7f3606c871ed83ce8a9b0eb022444550483dc45cd79293e8dde0a470`.

The next gate is one operator rerun of the default Script `07` command. Its
new report and replacement bundle require review before transfer or
installation.
