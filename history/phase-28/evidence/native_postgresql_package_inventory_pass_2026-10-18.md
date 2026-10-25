# Native PostgreSQL Package Inventory Pass

## Result

Accepted the operator-executed Script `05` read-only package inventory. The
target is ready for exact native package-root capture. The run performed no apt
update, network download, package installation, database initialization,
service or configuration mutation, content read, secret read, or target-file
write.

## Evidence

- Local ignored report:
  `local/reports/native-postgresql-package-inventory/native_postgresql_package_inventory_20261019T024846Z_kAkcIe.txt`
- Report SHA-256:
  `d0bb756ac6b90be0be44660d5f649ba89b593bc6350577237d8a371b28459943`
- Report size: `7,838` bytes and `65` lines.
- Script `05` SHA-256:
  `1bbb1b4b18593b41f8ffff36859b6ea05d835117c0efd555586bda58a72d4f87`.
- Neutral helper SHA-256:
  `11168c5d8342e4d894c71ff5680d21765c6271c7609cdb1f6e626b7ded03de71`
- Remote execution exit code: `0`.
- Output contract: `pass`.
- Failure count: `0`.
- Readiness issue count: `0`.
- Capture readiness: `ready_for_package_root_review`.

## Accepted Target Facts

- Ubuntu `24.04` on `x86_64`/`amd64`.
- PostgreSQL default major: `16`.
- PostgreSQL service: inactive and not found.
- TCP `5432`: not listening.
- PostgreSQL clusters: `0`.
- Installed vector extension controls: `0`.
- Available `/var` capacity at inventory: `439,918,772 KiB`.

## Selected Capture Roots

- `postgresql-16=16.15-0ubuntu0.24.04.1`, candidate SHA-256
  `d60ae76fb862cd4cca7bfdcdcdcc271c5e1d75f6b7915305ce2d962735a4b666`.
- `postgresql-client-16=16.15-0ubuntu0.24.04.1`, candidate SHA-256
  `4796f72e1a7270ad8c17b1ecb025cd453f692b42c10aaf89f6b476da61761eac`.
- `postgresql-16-pgvector=0.6.0-1`, candidate SHA-256
  `38a62e892ba162570125ee5ba3041a79a50ee272c68c79817dee22f7a3b5817e`.
- `python3-psycopg=3.1.17-2`, candidate SHA-256
  `19f35b5e21532b91969b9924ad58df799e240fd5e6882875c6ff750a5a812831`.

Psycopg 3 is selected for the new implementation. The available
`python3-psycopg2` candidate is not selected because no legacy Psycopg 2
compatibility requirement exists.

## Next Gate

Prepare an operator-run local capture that obtains the complete exact AMD64
`.deb` closure from the target's apt metadata, verifies every package against
that metadata, extracts package/license manifests, captures advisory sources,
and emits a checksum-bound offline bundle. Capture does not authorize install.
