# Ishikawa v1.3.1 Deployment Package Manifest

## Purpose

Define the complete minimal corrected file set assembled by Script 14. This is
the package-content contract, not a deployment-ready receipt. The generated
`PACKAGE_MANIFEST.json` supplies the exact mode, byte size, purpose, consumer,
and SHA-256 for every non-control payload/support file. It separately
classifies itself and `SHA256SUMS`, including their exact modes and consumers.
`SHA256SUMS` binds the generated manifest and every other package file; as the
checksum control file, it does not recursively checksum itself.

## Package state

The corrected package is assembled first under
`local/artifacts/ishikawa-deployment-v1.3.1-candidate-current/`. Its deployment
receipt is
`assembled_pending_target_inventory_and_independent_review`: exact-artifact
security review, corrected-image requalification, production promotion, and
human UI acceptance have passed. Approved destination inventory, any required
native-prerequisite capture, independent review, and stable-handoff
publication remain incomplete. The deployer refuses installation in this
candidate state.

Script 14 produces 26 files: 24 classified payload/support files and the two
control files `PACKAGE_MANIFEST.json` and `SHA256SUMS`. The accepted
review-pending assembly contains 168,530,714 file bytes, of which 168,522,433
are classified payload/support bytes. Its controlling identities are:

- package manifest SHA-256
  `db4f779c218cf541dad777abad7805b4e35d2b3b07c027918dcf5123ddc20b99`;
- package receipt SHA-256
  `49e4e2a6bd9ce916a0b66ff8d74abda8a3d061a3a140a1e2e9bbadd27f5a9ef4`;
- complete checksum manifest SHA-256
  `f231037bf039906b1c28c4f5b0da2c2be154c1e22a099a23824f52832a46e74c`;
  and
- assembly report SHA-256
  `962de5c675a4e97fc529db343c3df9dcf80d97dc8f6d241ba41e712628210f4d`.

The prior candidates are preserved only as historical evidence under
`local/artifacts/superseded/`; they are not deployable.

The candidate was assembled on mode-neutral transfer storage. The generated
manifest records `0755` for the three executable entrypoints and `0644` for
all other package files. The portable verifier validates those intended modes;
the installer materializes them on Tech's native Unix filesystem. Host
transfer-media modes are not release identity.

## Primary payloads

| Path | Purpose | Consumer | Frozen identity |
| --- | --- | --- | --- |
| `ishikawa-v1.3.1.tar.gz` | External corpus-agnostic application and canonical schema-v5 payload | Deployment entrypoint | `2dbf08b9e15fb4436e54ce492f2ad430129e794d33a1a45cdc6abf1a7b0b5f69` |
| `node-next-runtime-amd64.tar` | Corrected application-free Linux AMD64 Node/Next runtime image | Deployment entrypoint | `b92dd71eb155493d7e331e85c92566eee113ed4c8f0eda605c1c3dd951b836e1` |

Neither primary payload is nested in the other. No generated `.next` state is
carried.

## Complete 26-file contract

| Path | Purpose | Consumer |
| --- | --- | --- |
| `README.md` | Portable operator command sheet and boundaries | Operator |
| `SECURITY_REVIEW.md` | Exact-payload security disposition | Security reviewer and operator |
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

No carry-design decision is open. Script 14 accepts only the exact application,
corrected runtime, complete Script 12 qualification/acceptance/cleanup
receipts, complete Script 13 promotion/acceptance receipts, exact corrected
Trivy record, durable security disposition, and frozen V13-79 through V13-93.
It checks exact identities, lifecycle invariants, artifact and temporary
capacity, terminology, prohibited files, credential-shaped content, complete
checksums, classified intended modes, and portable verification before atomic
candidate publication. Every isolated package-assembly and portable
deployment lifecycle/refusal branch passes.

Assembly does not itself authorize travel or target mutation. Exact-artifact
security/advisory review is complete. Approved Tech read-only inventory, any
inventory-required offline native prerequisite payload, independent final
review, and stable-handoff promotion remain later work gates under the frozen
decisions.

The Tech inventory command selected loopback web `3384` and Retrieval API
`8384`. A post-inventory audit found that the first candidate still presented
the generic application defaults `3000` and `1384` in the portable deployment
command and operator sheet. No Tech installation occurred. The bounded carry
correction changes only portable support files: the entrypoint and direct
inventory helper now default to `3384`/`8384`, installation still accepts
explicit reviewed overrides, installation materializes the selected endpoints
in installed YAML and operator documents, all five selected ports reach the
install-time inventory, and lifecycle actions defer to installed YAML.
The accepted application and runtime-image archives remain byte-identical.
Default-port installation, explicit override, inventory, schema, lifecycle,
removal, failure cleanup, candidate refusal, carry assembly, and independent
checksum verification all pass.
