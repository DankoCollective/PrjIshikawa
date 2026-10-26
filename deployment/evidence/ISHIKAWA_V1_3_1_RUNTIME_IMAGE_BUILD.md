# Ishikawa v1.3.1 Runtime Image Build Evidence

## Result

Date: 2026-10-26 America/Los_Angeles

Corrected Script 07 completed on the frozen native Ubuntu 24.04 AMD64
EmceeDanko build host. The application-free runtime image was built, verified,
exported, independently verified after return, and atomically published to the
local candidate artifact lane. The private remote transfer directory was
removed. No application, database, model, service, listener, credential,
corpus, or boot state was changed.

`script_07_node_next_runtime_build=pass`

## Exact identities

- Image reference:
  `node-next-runtime:24.22.1-next16.4.3-react19.2.9-amd64`
- Engine image ID:
  `sha256:6c93bcb5ed22de92420c4de4892eecdd08f1badc8b19e4d6f4488711f8f7a31a`
- Exported OCI config digest:
  `sha256:ccbae1b68ecf82121ce76080793cb7febdf1d6df1653995db02fc2f83233228f`
- Canonical image-history SHA-256:
  `8a7adf8696e71217bdc3d3c1191e8865f2ba6a33b7534b2aab309c4eb7f496ca`
- Runtime archive SHA-256:
  `b92dd71eb155493d7e331e85c92566eee113ed4c8f0eda605c1c3dd951b836e1`
- Runtime archive size: `168046592` bytes
- Pinned base manifest:
  `sha256:2dd9a4f758e173b65fee15388f7706af6fb01ef50cf7a2c0538711d67a6981ae`
- Exact npm lock SHA-256:
  `9496ebf54d27c63794f5f1680197692ba0424bd323fb9f22f0fcacb2545aae5a`
- Script 07 helper SHA-256:
  `c5ad2d096a26c9f5c70670cba4ae3c5d060102f089236d6597bce770b3dd8b00`
- Content-free retained report SHA-256:
  `7d9f63eb38120d3b5d7f87f684d33ee7706af5e7f56b868838364807b84d09c6`

## Verified boundary

The returned archive has the exact frozen tag, checksum-addressed image
layers, one checksum-addressed config, Linux AMD64 platform identity,
`/opt/nextjs` working directory, and the expected generic command. Its config
and history contain no application source, generated `.next` output,
repository/workstream/test-host terminology, or secret-bearing assignment.
Docker loaded the exported archive and resolved the expected engine image ID.

The in-image runtime probes passed for Node.js `24.22.1`, Next.js `16.4.3`,
React `19.2.9`, React DOM `19.2.9`, and tzdata `2026e-0+deb12u1`. The base image's
npm/Yarn/Corepack copies were removed before installation; only the
checksum-pinned npm `11.21.1` CLI performed the build, and it was removed before
filesystem flattening. The image contains no package manager, Ishikawa
application, configuration, corpus, credential, database, target state, or
generated web build.

## SBOM and licenses

The CycloneDX 1.5 SBOM contains 111 components: 22 installed JavaScript
dependencies, 88 installed Debian packages, and Node.js as the sole explicitly
recorded runtime tool. The runtime-tool license record is:

- Node.js `24.22.1`, `MIT`, license SHA-256
  `5888dbb9a1d2b18f2c3e6c5f6af1b39de658372b402a0577b002777f14c62ace`

The license evidence separately records checksum-pinned npm `11.21.1` as an
absent build tool and records that the base-bundled package managers were not
executed.

All 22 JavaScript dependency records declare a license. The complete handoff
manifest, archive sidecar, identity, build receipt, SBOM digest, license-record
digest, config digest, history digest, layer digests, and exact versions agree.

## Remaining gates

This evidence and the exact-artifact security review close the native
runtime-image build/export and advisory-disposition gates. They do not claim
application rebinding, production-mode requalification, human UI acceptance,
Tech inventory, protected-corpus execution, or stable carry promotion.

Because DankoSurface is ARM64 without AMD64 emulation, the application
builder's AMD64 JavaScript and production-build checks cannot run there.
Script 08 therefore carries the checksum-bound external application sources
to the same native AMD64 host, verifies the retained image ID, runs the
unchanged application builder, and returns only its verified application
handoff. This is a build-host correction only; it does not change the frozen
external-application/runtime-image deployment architecture.
