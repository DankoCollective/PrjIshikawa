# Runtime security disposition

Review date: 2026-10-26

| Component | Selected identity | Disposition | Primary source |
| --- | --- | --- | --- |
| Node.js | 24.22.1 | Fixed security release on the supported Node 24 line | <https://nodejs.org/en/blog/release/v24.22.1> |
| Next.js | 16.4.3 | Current stable 16.4 patch; includes the 16.4.1 upstream-security fixes | <https://nextjs.org/blog/nextjs-security-update-october-14-2026> and <https://github.com/vercel/next.js/releases/tag/v16.4.3> |
| React | 19.2.9 | Fixed 19.2 release for GHSA-xqc2-xf4c-x3h3 | <https://github.com/react/react/security/advisories/GHSA-xqc2-xf4c-x3h3> |
| React DOM | 19.2.9 | Kept exactly aligned with React | <https://github.com/facebook/react/releases/tag/v19.2.9> |
| sharp | 0.35.5 | Exact lock resolution meets the Next.js security update's minimum fixed version | <https://nextjs.org/blog/nextjs-security-update-october-14-2026> |

The Dockerfile pins the official Linux AMD64
`node:24.22.1-bookworm-slim` manifest digest
`sha256:2dd9a4f758e173b65fee15388f7706af6fb01ef50cf7a2c0538711d67a6981ae`.
The dependency lock contains exact integrity values. The image build permits no
floating runtime dependency version.

This disposition covers the named action-required findings that triggered the
runtime refresh. A final promotion still requires a fresh complete scan of the
exact image and application artifacts.
