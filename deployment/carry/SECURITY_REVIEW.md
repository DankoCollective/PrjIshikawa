# Ishikawa v1.3.1 security review

Review date: 2026-10-26

This review applies only to these exact deployment payloads:

- application archive SHA-256
  `2dbf08b9e15fb4436e54ce492f2ad430129e794d33a1a45cdc6abf1a7b0b5f69`;
- runtime archive SHA-256
  `b92dd71eb155493d7e331e85c92566eee113ed4c8f0eda605c1c3dd951b836e1`;
- runtime image ID
  `sha256:6c93bcb5ed22de92420c4de4892eecdd08f1badc8b19e4d6f4488711f8f7a31a`;
  and
- runtime OCI configuration digest
  `sha256:ccbae1b68ecf82121ce76080793cb7febdf1d6df1653995db02fc2f83233228f`.

Trivy 0.76.1 scanned the exact runtime archive using its vulnerability database
updated at 2026-10-26T19:14:50Z. The JavaScript result contained zero
findings. No reported operating-system record had an available fixed package
version. The runtime contains Node.js 24.22.1, Next.js 16.4.3, React and React
DOM 19.2.9, sharp 0.35.5, and tzdata 2026e-0+deb12u1. It contains no npm,
Yarn, Corepack, or their dependency trees.

The critical zlib record CVE-2023-45853 is not present in the shipped binary
path: Debian marks the Bookworm source record ignored because the affected
MiniZip code is not built into the binary package. The remaining critical and
high records require commands or privileged operations that this application
does not execute: `infocmp`, `systemd-homed`, crafted gzip processing,
mount/fstab operations, block-device inspection, privileged ACL operations,
`nsenter --join-cgroup`, or Perl Archive::Tar processing.

The web container runs as a non-root numeric identity with a read-only root and
read-only application mounts, `no-new-privileges`, all Linux capabilities
dropped, no Docker socket, no home-directory mount, and one bounded writable
`.next` tmpfs. These controls make the reported privileged or unused-command
paths unreachable through Ishikawa's runtime contract.

The exact corrected image passed two fresh production build/start executions,
60/60 frontier cases, model and database dependency checks, attended UI
acceptance, and production promotion. The superseded runtime image was removed
after its container-consumer set was proved empty.

Disposition: the named action-required JavaScript/runtime-tool findings are
fixed, the remaining scanner records have documented non-reachable or
distribution dispositions, and no unresolved action-required finding remains
for the exact payload identities above.
