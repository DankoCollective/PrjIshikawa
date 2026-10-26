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
  `sha256:79f39435329920c9c834e55cf5e18528540220111ae2a35d779a86d0b539d298`
- Exported OCI config digest:
  `sha256:c7f3a6fd6b6a0792c189bc54a311a95ac04807e0e764d7014dbeaea601423e90`
- Canonical image-history SHA-256:
  `8ec77bbec6e5271d2ed045479b5c2d924eef3391b6c2fd6ebf0f91c843c78fa1`
- Runtime archive SHA-256:
  `af95820f63798b39c6538e3f9b5653d47b07aed1d81625e2382485ff559eff3f`
- Runtime archive size: `173526528` bytes
- Pinned base manifest:
  `sha256:2dd9a4f758e173b65fee15388f7706af6fb01ef50cf7a2c0538711d67a6981ae`
- Exact npm lock SHA-256:
  `9496ebf54d27c63794f5f1680197692ba0424bd323fb9f22f0fcacb2545aae5a`
- Script 07 helper SHA-256:
  `c940fd5ce48d4d91b47c97293c5e95b7dd2fbd3c3a168adf23ec57b92dc0b407`
- Content-free retained report SHA-256:
  `9dae703b36c830a6509fd3d0253fa746b49cc848fb25b9416e7ba91d522f4e30`

## Verified boundary

The returned archive has the exact frozen tag, eight checksum-addressed image
layers, one checksum-addressed config, Linux AMD64 platform identity,
`/opt/nextjs` working directory, and the expected generic command. Its config
and history contain no application source, generated `.next` output,
repository/workstream/test-host terminology, or secret-bearing assignment.
Docker loaded the exported archive and resolved the expected engine image ID.

The in-image runtime probes passed for Node.js `24.22.1`, npm `11.19.1`, Yarn
`1.22.22`, Next.js `16.4.3`, React `19.2.9`, and React DOM `19.2.9`. The image
contains no Ishikawa application, configuration, corpus, credential, database,
target state, or generated web build.

## SBOM and licenses

The CycloneDX 1.5 SBOM contains 113 components: 22 installed JavaScript
dependencies, 88 installed Debian packages, and the three explicitly recorded
runtime tools. The runtime-tool license records are:

- Node.js `24.22.1`, `MIT`, license SHA-256
  `5888dbb9a1d2b18f2c3e6c5f6af1b39de658372b402a0577b002777f14c62ace`
- npm `11.19.1`, `Artistic-2.0`, license SHA-256
  `7610d223851f421d315df5e77974f1c68a04b97e02060e5bbbcf13d95e3ca257`
- Yarn `1.22.22`, `BSD-2-Clause`, license SHA-256
  `ae09761b5d27e237571245437653b483bbb85de3cc64b802e8ef47d03aabec1e`

All 22 JavaScript dependency records declare a license. The complete handoff
manifest, archive sidecar, identity, build receipt, SBOM digest, license-record
digest, config digest, history digest, layer digests, and exact versions agree.

## Remaining gates

This evidence closes the native runtime-image build/export gate. It does not
claim complete advisory disposition, application-candidate construction,
production-mode requalification, human UI acceptance, Tech inventory,
protected-corpus execution, or stable carry promotion.

Because DankoSurface is ARM64 without AMD64 emulation, the application
builder's AMD64 JavaScript and production-build checks cannot run there.
Script 08 therefore carries the checksum-bound external application sources
to the same native AMD64 host, verifies the retained image ID, runs the
unchanged application builder, and returns only its verified application
handoff. This is a build-host correction only; it does not change the frozen
external-application/runtime-image deployment architecture.
