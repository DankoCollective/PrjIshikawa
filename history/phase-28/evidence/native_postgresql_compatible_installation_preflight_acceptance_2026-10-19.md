# Compatible Native PostgreSQL Installation Preflight Acceptance — 2026-10-19

## Disposition

Accept the operator-executed Script `11` preflight as the installation gate
for the checksum-bound Ubuntu 24.04 AMD64 PostgreSQL package bundle. The
preflight performed no installation or persistent target mutation.

Accepted report:

- `local/reports/native-postgresql-compatible-installation-preflight/native_postgresql_compatible_installation_preflight_20261019T134321Z_rMJPWP.txt`
- SHA-256: `e3dbfe5715de93de13f233a5bc34395d69690e7adfdfebffb5feaa24feea17ab`

Accepted bundle:

- `local/artifacts/native-postgresql-packages/native-postgresql-ubuntu24.04-amd64-pg16.15-pgvector0.8.7-compatible-20261019T132859Z.tar.gz`
- SHA-256: `147dd47979d002ac6a7beabafd1a048cf6aa8da8cb6c54993c83b0cb74ab9e05`

## Accepted facts

- the exact target was Ubuntu `24.04` AMD64;
- the bundle contained the exact nine reviewed package coordinates;
- PostgreSQL `16.15-1.pgdg24.04+2` provided JIT virtual version `19`;
- pgvector `0.8.7-1.pgdg24.04+1` accepted that JIT level;
- the exact reviewed `libllvm19` version was already installed;
- the other eight selected packages were absent;
- all nine license rows and seven advisory-review rows passed;
- no PostgreSQL cluster existed and port `5432` was free;
- the offline apt simulation selected exactly eight installs and zero
  removals;
- target temporary payloads and the SSH control session were removed.

## Installation boundary

The accepted preflight authorizes preparation and explicit operator execution
of the guarded offline package-installation command. It does not authorize
automatic database-cluster initialization, schema or role creation, a running
database service, or network package acquisition.

