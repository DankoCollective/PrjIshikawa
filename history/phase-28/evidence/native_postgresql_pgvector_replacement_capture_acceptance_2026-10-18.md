# Native PostgreSQL pgvector Replacement Capture Acceptance

## Accepted Result

The corrected operator-executed Script `07` replacement capture passed.

- report:
  `native_postgresql_pgvector_replacement_20261019T035159Z_QGXMCN.txt`;
- report SHA-256:
  `1928d5322ecd311a99f6129041e4ae27a211dcef88bcb8e3b95e9ecd8b2669a4`;
- script SHA-256:
  `f1986642964779f57bba9a4f53c0c4e55751f2a27d9ec676637090cdfe7a4c9e`;
- advisory decision-set SHA-256:
  `e8f22b80fcf39bb49736fb258d14be43244f107ceef0bd4baf85352fefca55e1`;
- accepted predecessor bundle SHA-256:
  `7e6d63ac7f3606c871ed83ce8a9b0eb022444550483dc45cd79293e8dde0a470`;
- replacement bundle:
  `native-postgresql-ubuntu24.04-amd64-pgvector0.8.7-20261019T035159Z.tar.gz`;
- replacement bundle SHA-256:
  `d091792ace6a1f5b1ac76d686e2464f52e61240c47e44eaf74670eaef0dfbff5`.

The report ends with
`reviewed_pgvector_replacement_capture=pass`. The pre-download advisory gate
covered all six selected source/version coordinates before the replacement
package payload was downloaded.

## Independent Review

Independent local review established:

- the outer checksum sidecar passes;
- the archive has no absolute or parent-traversal member paths;
- all `38` internal `SHA256SUMS` entries pass;
- the bundle contains exactly nine package payloads and nine package-register
  rows;
- every repository checksum equals its captured local checksum;
- all package control records match their registered package, version, and
  architecture;
- all nine packages have captured copyright records;
- the obsolete pgvector `0.6.0-1` payload and register row are absent;
- exactly one pgvector replacement exists:
  `postgresql-16-pgvector=0.8.7-1.pgdg24.04+1` for AMD64;
- that replacement is `268880` bytes with SHA-256
  `da584c72f1d84203734a59a773eeb64e0b2b4245393c3fe8eb3013b96ac29daa`;
- the captured PGDG key fingerprint is
  `B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8`; and
- independent `gpgv` verification reports a good `InRelease` signature from
  `PostgreSQL Debian Repository` using that key.

The archive contains `45` members and identifies Ubuntu `24.04` AMD64 as its
target. It records no target contact, package installation, database
initialization, or service mutation.

## Disposition

The replacement capture was accepted as a checksum-bound artifact and entered
Script `08` preflight without installation authority. That preflight later
identified a hard JIT virtual-package conflict between the Ubuntu PostgreSQL
server and PGDG pgvector package. This record is therefore superseded only in
its installation-input disposition: the capture remains valid evidence but is
blocked from transfer or installation as a package set. The compatibility
block record owns the current disposition and next gate.
