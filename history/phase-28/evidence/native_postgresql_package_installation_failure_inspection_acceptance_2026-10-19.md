# Native PostgreSQL Package Installation Failure Inspection Acceptance — 2026-10-19

## Disposition

Accept the operator-executed Script `13` report. The target is clean and no
package repair is required before a corrected installation retry.

Accepted report:

- `local/reports/native-postgresql-package-installation-failure-inspection/native_postgresql_package_installation_failure_inspection_20261019T140223Z_GT7c9X.txt`
- SHA-256: `b93f01052b13e46f290d161cf49955f4ea0960cc1be9063ac3790b631ccd3c76`

## Accepted facts

- only the previously accepted `libllvm19` package is installed;
- the other eight selected packages remain absent;
- no selected package is unpacked or left unconfigured;
- `dpkg --audit` returns zero lines;
- the support-package simulation passes with six installs and zero removals;
- the apt dependency check passes;
- no temporary service-start policy remains;
- PostgreSQL is inactive and not installed as a service;
- no cluster exists and port `5432` is free;
- the inspection made no target mutation or network download;
- temporary payload cleanup passed.

## Root cause and correction

The failed command combined local `.deb` path arguments with apt's
`--no-download` option. Apt documents that option as disabling package
acquisition and recommends it for packages already present in apt's download
cache. The transferred files were verified local inputs but were not apt-cache
payloads. Simulation did not exercise acquisition, while the real transaction
stopped before dpkg changed package state.

The corrected installer removes `--no-download` so apt may acquire the
explicit local file paths. It still prevents repository access by setting both
apt source locations to `/dev/null`, setting network proxies to a rejecting
loopback endpoint, and accepting only the exact checksum-bound local package
paths. This is local package acquisition, not an internet download.

