# Ishikawa v1.3.1 Deployment Package Manifest

> **Superseded carry identity — do not deploy.** This record describes the
> pre-V13-92 candidate and is retained only as historical evidence. Its
> package receipt remains non-installable. A new package manifest must be
> generated after the corrected runtime passes Script 12 acceptance and the
> corrected production promotion gate.

## Purpose

Define the complete minimal file set assembled by Script 11. This is the
package-content contract, not a deployment-ready receipt. The generated
`PACKAGE_MANIFEST.json` supplies the exact mode, byte size, purpose, consumer,
and SHA-256 for every non-control payload/support file. It separately
classifies itself and `SHA256SUMS`, including their exact modes and consumers.
`SHA256SUMS` binds the generated manifest and every other package file; as the
checksum control file, it does not recursively checksum itself.

## Package state

The package is assembled first under
`local/artifacts/ishikawa-deployment-v1.3.1-candidate-current/`. Its deployment
receipt remains `assembled_pending_security_inventory_and_independent_review`
until exact-artifact security review, approved destination inventory, any
required native-prerequisite capture, independent review, and stable-handoff
publication are complete. The deployer refuses installation in that state.

The superseded Script 11 run assembled and independently verified that exact candidate on
2026-10-26. The directory contains 25 files and 173,989,414 bytes on its
current transfer filesystem. Its controlling identities are:

- `PACKAGE_MANIFEST.json` SHA-256
  `ade4973399b548467fe836b6c0d6a097ddec6741d14899a94f56186a36b123aa`;
- `deployment-package-receipt.json` SHA-256
  `89a8c3ca3d7f0d1f7877700a161a7e06518a5a9ad3ef70a23a97ad4c3616c5dc`;
- `SHA256SUMS` SHA-256
  `a5659c63339b82608b300e7c354dc60b777b5564a19eaf6b422f1d461f1b0d52`;
  and
- assembly report SHA-256
  `58b94197f57e531a44fcfab44964f26d605c9536daa06ee92bbbc204446fe77f`.

The candidate was assembled on mode-neutral transfer storage. The generated
manifest records `0755` for the three executable entrypoints and `0644` for
all other package files. The portable verifier validates those intended modes;
the installer materializes them on Tech's native Unix filesystem. Host
transfer-media modes are not release identity.

## Primary payloads

| Path | Purpose | Consumer | Frozen identity |
| --- | --- | --- | --- |
| `ishikawa-v1.3.1.tar.gz` | External corpus-agnostic application and canonical schema-v5 payload | Deployment entrypoint | `2dbf08b9e15fb4436e54ce492f2ad430129e794d33a1a45cdc6abf1a7b0b5f69` |
| `node-next-runtime-amd64.tar` | Application-free Linux AMD64 Node/Next runtime image | Deployment entrypoint | `af95820f63798b39c6538e3f9b5653d47b07aed1d81625e2382485ff559eff3f` |

Neither primary payload is nested in the other. No generated `.next` state is
carried.

## Complete 25-file contract

| Path | Purpose | Consumer |
| --- | --- | --- |
| `README.md` | Portable operator command sheet and boundaries | Operator |
| `deploy-ishikawa` | Consolidated inventory/install/schema/lifecycle/removal entrypoint | Operator |
| `verify-deployment` | Read-only complete package verifier | Operator |
| `inspect-native-prerequisites` | Read-only destination prerequisite inventory | Operator |
| `ishikawa-v1.3.1.tar.gz` | External application payload | Deployment entrypoint |
| `ishikawa-v1.3.1.tar.gz.sha256` | Standalone application checksum | Verifier |
| `ISHIKAWA_V1_3_1_SOURCE_SHA256SUMS` | Application source provenance | Release reviewer |
| `application-release.json` | Final application identity and exact-byte acceptance binding | Verifier and reviewer |
| `application-sbom.cdx.json` | Application software inventory | Security reviewer |
| `application-license.json` | Application license identity | Security reviewer |
| `node-next-runtime-amd64.tar` | Application-free runtime image | Deployment entrypoint |
| `node-next-runtime-amd64.tar.sha256` | Standalone runtime-image checksum | Verifier |
| `runtime-image-identity.json` | Image tag, ID, platform, config, and history identity | Verifier and deployer |
| `runtime-build-receipt.json` | Native image-build identity binding | Verifier and reviewer |
| `runtime-sbom.cdx.json` | Exact runtime software inventory | Security reviewer |
| `runtime-licenses.json` | Machine-readable runtime license inventory | Security reviewer |
| `runtime-Dockerfile` | Reproducible runtime-image source | Release reviewer |
| `runtime-package.json` | Direct JavaScript dependency declaration | Release reviewer |
| `runtime-package-lock.json` | Exact transitive JavaScript dependency lock | Release reviewer |
| `RUNTIME_README.md` | Generic runtime architecture and boundary | Operator and reviewer |
| `RUNTIME_SECURITY.md` | Named runtime advisory disposition and remaining review gate | Security reviewer |
| `RUNTIME_LICENSES.md` | Human-readable runtime license boundary | Security reviewer |
| `deployment-package-receipt.json` | Package identity, qualification, and review state | Verifier and operator |
| `PACKAGE_MANIFEST.json` | Classified path/type/mode/size/purpose/consumer/hash inventory | Operator and verifier |
| `SHA256SUMS` | Complete package checksum inventory | Operator and verifier |

## Explicit exclusions

The package contains no source documents, corpus catalog, ingestion manifest,
chunks, vectors, prompts, responses, model weights, database state, database
dump, credential, secret file, environment file, private key, generated
`.next`, loose dependency tree, virtual environment, cache, bytecode, raw
report, historical migration, repair chain, superseded payload, or target-host
identity. A native prerequisite bundle is absent unless the approved
destination inventory proves one is required and a later checksum-bound bundle
passes its separate capture and review gate.

## Assembly prerequisite and decision state

No carry-design decision was open at assembly. Script 11 accepted only the
checksum-bound Script 10 production-port acceptance receipt, checked exact
input identity, lifecycle receipts, artifact and temporary-filesystem
capacity, and all source prerequisites before creating its private package
stage. Its first real attempt exposed a transfer-filesystem `chmod` limitation;
the bounded portability correction made assembly mode-neutral while retaining
explicit target modes. The corrected real invocation and every isolated
lifecycle branch passed.

Assembly does not itself authorize travel or target mutation. Exact-artifact
security/advisory review, approved Tech read-only inventory, any inventory-
required offline native prerequisite payload, independent final review, and
stable-handoff promotion remain later work gates under the frozen decisions.
