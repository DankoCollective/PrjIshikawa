# Native PostgreSQL Compatibility Inventory And Advisory Acceptance

## Script 09 result

The operator-executed Script `09` compatibility inventory passed. The accepted
bounded report is:

- `native_postgresql_compatibility_inventory_20261019T131350Z_UIXF4r.txt`;
- SHA-256:
  `25f3f939b05b71a3ac426edc5ad4adf1ce353ab438135731a031241e87115d54`;
- 2,329 bytes and 21 lines.

The report proves the expected EmceeDanko Ubuntu 24.04 AMD64 identity and
records `libllvm19=1:19.1.1-1ubuntu1~24.04.2`, source
`llvm-toolchain-19`, archive SHA-256
`a62f1074eb7aecf10e00fed9c7c967dc6c801fae444a40b8007e246320f5ee15`,
and archive size `28737618`. The same exact version is already installed and
is the apt candidate. No apt update, download, install, database action,
service/configuration change, sudo operation, secret/content read, or target
file write occurred.

## Advisory result

Canonical's current Noble query for `llvm-toolchain-19` returns four records:

- `CVE-2026-13574`: low priority, `needs-triage`; Canonical's priority reason
  is "CLI crash only";
- `CVE-2026-13573`: low priority, `needs-triage`; Canonical's priority reason
  is "CLI crash only";
- `CVE-2024-7883`: low priority, `needed`; it concerns Arm Cortex-M Security
  Extensions code generation and Canonical notes that Ubuntu's default build
  flags are not affected; and
- `CVE-2024-45056`: medium priority, `not-affected`; Canonical records this as
  a zksolc issue rather than an LLVM defect.

The exact dependency does have advisory records. It is accepted as
`accepted_not_applicable` for this bounded use, not represented as advisory-
free. This deployment is AMD64; PostgreSQL loads the LLVM runtime for trusted
JIT work; it does not compile Arm Cortex-M CMSE output, expose an LLVM command
line, or accept arbitrary LLVM bitcode from application requests. PostgreSQL
and the retrieval service remain loopback-bound and application roles will not
receive direct database administration or arbitrary-code privileges.

The reviewed query and records are:

- <https://ubuntu.com/security/cves.json?package=llvm-toolchain-19&version=noble>
- <https://ubuntu.com/security/CVE-2026-13574>
- <https://ubuntu.com/security/CVE-2026-13573>
- <https://ubuntu.com/security/CVE-2024-7883>
- <https://ubuntu.com/security/CVE-2024-45056>

## Compatible package decision set

`native-postgresql-advisory-review-v2.tsv` supersedes version 1 for the next
capture. It retains the accepted Ubuntu client/libpq coordinate, replaces only
the incompatible Ubuntu PostgreSQL server with signed PGDG
`postgresql-16=16.15-1.pgdg24.04+2`, replaces `libllvm17t64` with the exact
reviewed `libllvm19`, and retains reviewed pgvector `0.8.7` and Psycopg 3.

PostgreSQL's current security register identifies upstream `16.15` as the
fixed PostgreSQL 16 release through its 2026-08-13 security release. The
PGDG package's upstream version is exactly `16.15`; its repository revision
does not reduce that upstream version.

The next permitted action is a new local checksum-bound compatible package
capture. The Script `07` bundle remains blocked from transfer or installation,
and Script `08` must not be rerun against it.
