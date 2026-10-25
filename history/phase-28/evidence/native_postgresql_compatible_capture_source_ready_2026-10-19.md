# Native PostgreSQL Compatible Capture Source Ready

## Purpose

Script `10` creates the corrected Ubuntu 24.04 AMD64 native package bundle.
It starts from the checksum-accepted but compatibility-blocked Script `07`
bundle, removes only Ubuntu `postgresql-16` and `libllvm17t64`, and adds:

- signed PGDG `postgresql-16=16.15-1.pgdg24.04+2`, which provides
  `postgresql-16-jit-llvm (= 19)`; and
- Ubuntu `libllvm19=1:19.1.1-1ubuntu1~24.04.2`, which Script `09` found
  already installed at the exact candidate version on EmceeDanko.

The other seven package payloads remain byte-for-byte unchanged. The final
bundle is still nine packages.

## Bound inputs

- Script `07` bundle SHA-256:
  `d091792ace6a1f5b1ac76d686e2464f52e61240c47e44eaf74670eaef0dfbff5`;
- Script `09` report SHA-256:
  `25f3f939b05b71a3ac426edc5ad4adf1ce353ab438135731a031241e87115d54`;
- version-2 advisory decision SHA-256:
  `c4b90f6837c124f9851d5babeb0c605f03c249f7b181bd89247224d62054b471`;
- PGDG PostgreSQL payload SHA-256:
  `abe560fc574383f520753dfaef79ab24081cda488293d5c991a9f77ac98ef18f`;
- Ubuntu libllvm19 payload SHA-256:
  `a62f1074eb7aecf10e00fed9c7c967dc6c801fae444a40b8007e246320f5ee15`.

Script `10` SHA-256 is
`e1447a3e57baab60e0efa65ab0f95f70e166aba68b588d5152a86fc0eb200c56`.

## Local proof

`bash -n`, `--validate-only`, and `--plan-only` pass. The plan proof verifies:

- both accepted input hashes;
- the exact seven-coordinate pre-download advisory set;
- the Script `09` exact installed/candidate libllvm19 coordinate;
- the captured PGDG key fingerprint and InRelease signature;
- the signed PGDG package-index checksum; and
- the exact PostgreSQL server package, JIT-19 provide, libllvm19 dependency,
  size, path, and checksum.

No network access, target contact, package download, package installation,
database initialization, service mutation, or configuration mutation occurs
during the plan check.

## Operator command

From the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/10_capture_compatible_native_postgresql_bundle.sh
```

The execution is local to DankoSurface. It downloads exactly two reviewed
package payloads after all advisory and signed-metadata gates pass. It does not
contact EmceeDanko and does not authorize transfer or installation. The
returned report and bundle must be reviewed before the next preflight.
