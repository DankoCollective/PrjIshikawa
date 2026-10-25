# Native PostgreSQL Compatible Capture Acceptance

## Result

The operator-executed Script `10` capture passed. Independent review accepts
the new checksum-bound Ubuntu 24.04 AMD64 native package bundle as the sole
input for the next read-only installation preflight.

This acceptance does not authorize transfer for installation, package
installation, database initialization, service mutation, or configuration
mutation.

## Accepted report and bundle

Report:

- `native_postgresql_compatible_capture_20261019T132859Z_7kfLrY.txt`;
- SHA-256:
  `bdc45bce2858dc219bdc02e57a3419bfe0248743ac282ce75acfd7c4cfbcd7fc`.

Bundle:

- `native-postgresql-ubuntu24.04-amd64-pg16.15-pgvector0.8.7-compatible-20261019T132859Z.tar.gz`;
- size: `48425888` bytes;
- SHA-256:
  `147dd47979d002ac6a7beabafd1a048cf6aa8da8cb6c54993c83b0cb74ab9e05`.

The outer sidecar contains that same filename and digest.

## Independent verification

The following checks pass independently of Script `10`:

- safe archive paths with one bundle root;
- complete internal `SHA256SUMS` validation;
- exactly nine `.deb` payloads;
- exact package, version, and architecture tuples;
- nine package-register rows whose local and repository SHA-256 values match;
- nine present license records;
- seven exact accepted advisory coordinates;
- exact embedded advisory-file identity;
- removal of Ubuntu PostgreSQL server `16.15-0ubuntu0.24.04.1` and
  `libllvm17t64`;
- addition of PGDG PostgreSQL server `16.15-1.pgdg24.04+2` and Ubuntu
  `libllvm19=1:19.1.1-1ubuntu1~24.04.2`; and
- PostgreSQL provides `postgresql-16-jit-llvm (= 19)`, pgvector breaks only
  virtual versions below `19`, and the server depends on `libllvm19`.

The compatible nine-package set is:

- `libjson-perl=4.10000-1` (`all`);
- `libllvm19=1:19.1.1-1ubuntu1~24.04.2` (`amd64`);
- `libpq5=16.15-0ubuntu0.24.04.1` (`amd64`);
- `postgresql-16=16.15-1.pgdg24.04+2` (`amd64`);
- `postgresql-16-pgvector=0.8.7-1.pgdg24.04+1` (`amd64`);
- `postgresql-client-16=16.15-0ubuntu0.24.04.1` (`amd64`);
- `postgresql-client-common=257build1.1` (`all`);
- `postgresql-common=257build1.1` (`all`);
- `python3-psycopg=3.1.17-2` (`all`).

## Disposition

The Script `07` bundle remains blocked and Script `08` remains historical.
Only the accepted Script `10` bundle may enter the new compatible preflight.
The next action is operator-executed Script `11`, which stages the bundle only
in target temporary storage, verifies it, simulates installation without
downloads, retrieves a bounded report, and removes the temporary payload.
