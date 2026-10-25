# Native pgvector And PostgreSQL JIT Compatibility Block

## Result

The Script `08` preflight correctly prevented installation of the accepted
capture. Independent inspection of the captured package control records
identified a hard package relationship conflict:

- Ubuntu `postgresql-16=16.15-0ubuntu0.24.04.1` provides
  `postgresql-16-jit-llvm (= 17)`;
- PGDG `postgresql-16-pgvector=0.8.7-1.pgdg24.04+1` declares
  `Breaks: postgresql-16-jit-llvm (<< 19)`.

Those exact packages cannot be installed together. This explains apt exit
`100` without requiring raw target error retention. The incompatibility is in
the selected package metadata, not EmceeDanko state.

## Evidence

The second Script `08` report is:

- `native_postgresql_installation_preflight_20261019T040313Z_5w0ido.txt`;
- SHA-256:
  `a26280559850c154594a8ec4b32a6a57cdd8ed828749796cc9b337edca4842e4`.

It proves the expected EmceeDanko Ubuntu 24.04 AMD64 identity, accepted bundle
hash, successful temporary-payload verification, safe block, complete target
temporary cleanup, and SSH-master cleanup. Nothing was downloaded or
installed and no database, service, or configuration changed.

The same captured signed PGDG package index contains
`postgresql-16=16.15-1.pgdg24.04+2`, which provides
`postgresql-16-jit-llvm (= 19)` and depends on `libllvm19`. That is the minimum
server-side compatibility direction to investigate. It is not yet an accepted
replacement: the exact target `libllvm19` candidate and closure must first be
inventoried, then all changed source/version coordinates must pass the
pre-download advisory gate.

## Disposition

The Script `07` bundle remains a valid checksum-bound capture artifact but is
blocked from transfer or installation as a package set. Script `08` must not
be rerun against that bundle. The next action is a new read-only target
inventory for the exact `libllvm19` candidate needed by the compatible PGDG
PostgreSQL server; capture and installation remain unauthorized.
