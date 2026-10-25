# Native PostgreSQL Package Capture Resume Repair

## Second Run Result

The second operator-executed Script `06` run successfully returned the complete
EmceeDanko AMD64 target metadata but did not reach the local package-download
stage or emit a final pass marker. Its local report is:

- `native_postgresql_package_capture_20261019T030940Z_3Qk0Qj.txt`;
- SHA-256
  `fb2a9d2c3f10cf28a5958c234b1ba43d02d04bd0388d49463d98390097a13851`;
- 1,038 bytes and 10 lines.

The immediate local exit cause was not retained by that script revision. It is
therefore not guessed. Independent review established these bounded facts:

- target metadata execution returned zero;
- the metadata closure contains 98 packages and 98 package URIs;
- all internal metadata checksums pass;
- the four accepted roots are unchanged;
- the package directory is empty;
- no transfer bundle or sidecar exists; and
- no package was downloaded, transferred, installed, or configured.

The complete dependency graph consists of four selected roots and 94
dependencies. However, EmceeDanko already has 89 of those dependencies. Its
apt simulation requires only nine package downloads totaling 43,797,374 bytes,
or 41.77 MiB.

## Resume Repair

Script `06` now supports `--resume-latest`. This mode selects the newest
incomplete target-specific capture, verifies every existing target-metadata
checksum, checks the Ubuntu/AMD64 platform, verifies resolved/URI counts, and
rechecks every accepted root before performing any download. It does not
repeat the SSH target query. Verified partial package downloads can be reused
only when their exact recorded size and SHA-256 match.

The download plan is derived from the target's recorded apt simulation. The
full 98-package graph remains available for audit, but only the nine packages
that apt would install on EmceeDanko are selected for the bundle.

The script also records an explicit report marker containing the exit code and
source line for any unexpected local failure after metadata acceptance.
`--resume-check-only` exercises the entire resume-validation path without
target contact or package download.

Current Script `06` SHA-256:

`3971b9d863cca3477a72cfa2360a0738779c0b26d73568dafb8ce228f82ad3ae`

The local resume check passed against the retained AMD64 metadata. A later
advisory-source outage repair superseded this specific check report while
preserving the same counts and no-network result:

- report `native_postgresql_package_capture_20261019T031913Z_V4N5f4.txt`;
- report SHA-256
  `b8f54e0a5d92835441594a09991665b3b22463021429b99de5ff6d12589e7ca6`;
- `resolved_package_count=98`;
- `package_uri_count=98`;
- `download_package_count=9`;
- `download_bytes=43797374`;
- `target_contact=false`; and
- `package_download=false`.

## Operator Resume Command

From the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/06_capture_native_postgresql_package_closure.sh \
  --resume-latest
```

This downloads and verifies the nine target-required Ubuntu packages on
DankoSurface and produces one checksum-bound transfer bundle. The packages do
not need to be downloaded manually, and package-download logic does not need
to run in org-lab. Transfer and installation remain unauthorized until the
completed bundle and advisory gate are reviewed.
