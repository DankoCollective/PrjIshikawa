# Runtime security disposition

Review date: 2026-10-26

| Component | Selected identity | Disposition | Primary source |
| --- | --- | --- | --- |
| Node.js | 24.22.1 | Fixed security release on the supported Node 24 line | <https://nodejs.org/en/blog/release/v24.22.1> |
| npm | 11.21.1 | SHA-256-pinned build tool; absent from the flattened final runtime | Official registry archive digest, build-stage version, and final-filesystem absence probes |
| Base-bundled npm/Yarn | not executed | Removed before filesystem flattening | Dockerfile execution path and final-filesystem absence probes |
| tzdata | 2026e-0+deb12u1 | Exact Bookworm timezone-data refresh | Debian package identity and final-image probe |
| Next.js | 16.4.3 | Current stable 16.4 patch; includes the 16.4.1 upstream-security fixes | <https://nextjs.org/blog/nextjs-security-update-october-14-2026> and <https://github.com/vercel/next.js/releases/tag/v16.4.3> |
| React | 19.2.9 | Fixed 19.2 release for GHSA-xqc2-xf4c-x3h3 | <https://github.com/react/react/security/advisories/GHSA-xqc2-xf4c-x3h3> |
| React DOM | 19.2.9 | Kept exactly aligned with React | <https://github.com/facebook/react/releases/tag/v19.2.9> |
| sharp | 0.35.5 | Exact lock resolution meets the Next.js security update's minimum fixed version | <https://nextjs.org/blog/nextjs-security-update-october-14-2026> |

The Dockerfile pins the official Linux AMD64
`node:24.22.1-bookworm-slim` manifest digest
`sha256:2dd9a4f758e173b65fee15388f7706af6fb01ef50cf7a2c0538711d67a6981ae`.
The dependency lock contains exact integrity values. The image build permits no
floating runtime dependency version. The fixed build-only npm archive is
checksum-pinned; neither base-bundled package manager is executed. The final
filesystem contains Node and the locked application-independent runtime
dependencies but no npm, Yarn, Corepack, or their nested dependency trees.

This disposition covers the named action-required findings that triggered the
runtime refresh. A final promotion still requires a fresh complete scan of the
exact image and application artifacts.

The currently accepted pre-correction image, its local archive, and any base or
builder-cache records are not evidence of the corrected runtime. They remain
carry-blocked during construction so a failed build cannot erase the last
operational baseline. After the corrected image passes exact-artifact scanning,
production requalification, and attended acceptance, cleanup must prove removal
of the superseded application image and archive from the carry lane. Any
build-cache cleanup must target only the build records proved to belong to this
image; a broad Docker prune is prohibited.
