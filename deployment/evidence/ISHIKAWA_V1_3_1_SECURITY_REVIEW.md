# Ishikawa v1.3.1 Exact-Artifact Security Review

## Current disposition

`corrected_runtime_scan=pass;production_requalification_and_acceptance=pass;production_promotion_and_acceptance=pass;remaining_gate=carry_reassembly_and_final_review`

The operator selected the smaller-runtime correction. Corrected Script 07
completed on EmceeDanko and this review covers its exact returned archive. The
previous assembled candidate remains carry-blocked. Script 13 subsequently
promoted and accepted the corrected runtime and retired the pre-correction
image after proving it had no container consumers.

## Exact scan boundary

- Runtime archive SHA-256:
  `b92dd71eb155493d7e331e85c92566eee113ed4c8f0eda605c1c3dd951b836e1`.
- Runtime image ID:
  `sha256:6c93bcb5ed22de92420c4de4892eecdd08f1badc8b19e4d6f4488711f8f7a31a`.
- Runtime OCI config digest:
  `sha256:ccbae1b68ecf82121ce76080793cb7febdf1d6df1653995db02fc2f83233228f`.
- Scanner: Trivy `0.76.1`, downloaded from the immutable upstream release and
  verified against its published SHA-256. Linux ARM64 scanner archive SHA-256:
  `e174dff2a6dba5e3ae41f8d0537a6324405bd08132497340304c6b20e0f16a1f`.
- Vulnerability database updated at `2026-10-26T19:14:50Z`, with next update
  `2026-10-27T19:14:50Z`.
- Corrected ignored raw scan report:
  `local/reports/ishikawa-v1.3.1-security-review/runtime-vulnerabilities-trivy-0.76.1-corrected-20261026.json`,
  SHA-256
  `ce251960fdc20726a73fa49cc4f417761ee90c392592a3a5d7eeb6dae540971c`.
- Ignored database metadata SHA-256:
  `b5c8fec7f35a2c46bc7634ddff82fd2921f8d0f7b8525d7690a2f0537e3b555a`.

The scan detected Debian 12.15 with 88 installed operating-system packages and
the exact JavaScript filesystem. It emitted 228 package/finding instances,
representing 99 distinct type/advisory pairs. The Node/JavaScript result has
zero findings. No reported record has an available fixed version. The prior
scan and its checksum remain historical evidence of the superseded image.

## Findings that require a posture

The final image contains Node.js `24.22.1`, Next.js `16.4.3`, React/React DOM
`19.2.9`, sharp `0.35.5`, and tzdata `2026e-0+deb12u1`. It contains no npm,
Yarn, Corepack, or their dependency trees. The corrected build deletes the
base-bundled package managers before dependency installation, uses only the
checksum-pinned npm `11.21.1` CLI by absolute path, deletes that build tool,
and flattens the final filesystem. Its SBOM and license inventory record npm as
an absent build tool, not a runtime component.

The scanner's one critical record is `CVE-2023-45853` against `zlib1g`.
Debian's authoritative tracker marks Bookworm's source record ignored because
the vulnerable MiniZip code is not built into the affected binary packages.
It is not an action-required binary finding for this image.

The remaining critical/high output is 57 operating-system package instances
covering twelve distinct CVEs. Bookworm supplies no fixed version for any of
them. Their exact dispositions are:

- `CVE-2023-45853`: Debian marks the zlib Bookworm record ignored because the
  vulnerable MiniZip code is not built into the binary package.
- `CVE-2025-69720`: applies to the `infocmp` command; Ishikawa never invokes it.
- `CVE-2026-16742`: applies to `systemd-homed`; that service is absent from the
  container execution path.
- `CVE-2026-41992`: requires crafted LZW/LZH processing by the `gzip` command;
  Ishikawa does not invoke gzip at runtime.
- `CVE-2026-53613`, `CVE-2026-76642`, `CVE-2026-78409`, and `CVE-2026-78410`:
  require privileged mount or fstab operations; the web container drops all
  capabilities, sets `no-new-privileges`, and performs no mounts.
- `CVE-2026-53615`: requires probing crafted partition metadata; Ishikawa does
  not inspect block devices or disk images.
- `CVE-2026-54369`: requires privileged pathname ACL operations; Ishikawa does
  not invoke them and runs non-root with all capabilities dropped.
- `CVE-2026-78408`: requires privileged `nsenter --join-cgroup`; Ishikawa does
  not invoke nsenter and has no required privilege.
- `CVE-2026-9538`: requires Perl Archive::Tar processing of a crafted archive;
  Ishikawa does not invoke Perl or Archive::Tar at runtime.

The runtime additionally has no Docker socket, no host-home mount, read-only
application source and container root, and only a bounded writable `.next`
tmpfs. The findings are not reachable through Ishikawa's execution path.

Moving from Bookworm slim to Trixie slim remains rejected: the same-day control
scan retained 43 critical/high operating-system instances and would change the
selected base without closing the privileged-code findings.

## Corrected production requalification

Script 12 bound the unchanged application to this exact corrected runtime on
EmceeDanko, passed two fresh production build/start containers, passed all
60/60 frontier cases, recorded attended UI acceptance, and removed only the
isolated candidate. The accepted production application, Retrieval API,
PostgreSQL cluster, corpus, and boot posture remained unchanged. Exact retained
evidence SHA-256 identities are:

- qualification report:
  `da9a45651e76967b092c08acfd0c01518f3c2ec5808d039456608fe00abae4fa`;
- qualification receipt:
  `8849dd9f3544fe113b7db0c6e883b56b1470a7a4735251c0c88829814a382f2b`;
- acceptance report:
  `4b04fe5d675141a850caac854275fa89b05d76b18711aa4ff1b04896898df279`;
- acceptance receipt:
  `2659beb4420e2a67e19919f5766ef10fd66a82eb21be14757a8e72b22df50b10`;
- cleanup report:
  `d2d6673382681de424d93fcff12f174affbd02ea5f9444585abd1b9b1979053c`;
- cleanup receipt:
  `4e458ab6d6103d9a9b384876aa7a8c94bb63c9fa74d5fcae6878a499cf86c2ff`;
  and
- complete Script 12 evidence manifest:
  `1c19a9a1941acf2682fa7424c3056f254adf2f2dd76c555495f538760b8e7ec6`.

## Corrected production promotion

Script 13 promoted the same exact corrected image to production port `3384`
without replacing or restarting the application, Retrieval API, PostgreSQL, or
corpus. Human UI acceptance passed, and the superseded runtime image was
removed only after its consumer set was empty. The returned acceptance receipt
SHA-256 is
`abe406f6e55faa07ac922eca735732d890069553d7df2b9cf355bfc8438bb0f3`;
the complete Script 13 evidence manifest verifies locally.

## Remaining gate

The corrected artifact closes the action-required runtime-tool and timezone
findings without changing the external-application architecture. Production
promotion and attended acceptance are complete. The exact carry must now be
reassembled from the corrected archive and Script 12/13 evidence, then pass
destination inventory, independent review, and stable-handoff publication.

## Primary sources

- Node.js 24.22.1 security release:
  <https://nodejs.org/en/blog/release/v24.22.1>
- Next.js upstream security update:
  <https://nextjs.org/blog/nextjs-security-update-october-14-2026>
- React Server Components advisory:
  <https://github.com/react/react/security/advisories/GHSA-xqc2-xf4c-x3h3>
- npm 11.21.1 dependency update:
  <https://github.com/npm/cli/releases/tag/v11.21.1>
- Debian `CVE-2023-45853` disposition:
  <https://security-tracker.debian.org/tracker/CVE-2023-45853>
- Debian Bookworm `util-linux` status:
  <https://security-tracker.debian.org/tracker/source-package/util-linux>
- Trivy 0.76.1 release:
  <https://github.com/aquasecurity/trivy/releases/tag/v0.76.1>
