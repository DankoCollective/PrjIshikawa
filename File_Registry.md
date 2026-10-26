# File Registry

| Path | Role | Git posture |
|---|---|---|
| `Initial_Assessment_Ishikawa.md` | Reviewer handoff with the current Ishikawa v1.3 assessment, risks, and forward plan | Tracked |
| `danko_lab.md` | Shared non-secret Danko Lab systems, addresses, hardware roles, installed services, ports, collisions, and operating reference | Tracked |
| `node_nextjs_runtime_image.md` | Product-neutral definition and exact application-free Linux AMD64 Node 24.22.1, Next.js 16.4.3, and React 19.2.9 runtime contract | Tracked |
| `Ishikawa/` | Canonical product source and tests | Tracked |
| `docs/operations/ISHIKAWA_V1_3_OPERATING_SURFACE.md` | Accounts, roles, services, commands, paths, and permission inventory | Tracked |
| `docs/operations/CORPUS_INGESTION_RUNBOOK.md` | Operator catalog, manifest, validation, publication, and verification guide | Tracked |
| `docs/releases/ISHIKAWA_V1_3_REPOSITORY_SWEEP.md` | Reviewed repository-wide agreement and validation record | Tracked |
| `docs/releases/ISHIKAWA_ORG_LAB_CARRY_READINESS_CHECKLIST.md` | Durable decision-review queue and checkable final deployment carry gates | Tracked |
| `deployment/evidence/ISHIKAWA_V1_3_EMCEEDANKO_QUALIFICATION.md` | Content-free EmceeDanko disposable qualification receipt | Tracked |
| `deployment/evidence/ISHIKAWA_V1_3_EMCEEDANKO_UI_ACCEPTANCE.md` | Content-free operator UI-acceptance receipt for the exact v1.3 baseline | Tracked |
| `deployment/evidence/ISHIKAWA_V1_3_1_LOCAL_IMPLEMENTATION.md` | Content-free v1.3.1 source implementation and executable local-gate receipt | Tracked |
| `qualification/corpus-v3/` | Synthetic qualification fixture | Tracked |
| `qualification/corpus-v3/document-keys.json` | Stable fixture document-key registry | Tracked |
| `deployment/scripts/01_build-ishikawa-release.sh` | Script 01: corpus-agnostic v1.3 release builder | Tracked |
| `deployment/scripts/02_inventory-emceedanko.sh` | Script 02: read-only EmceeDanko deployment inventory | Tracked |
| `deployment/scripts/03_export-qualification-corpus.sh` | Script 03: independent qualification-corpus exporter | Tracked |
| `deployment/scripts/04_stage-v1.3-candidate-on-emceedanko.sh` | Script 04: side-by-side EmceeDanko candidate staging | Tracked |
| `deployment/scripts/05_qualify-v1.3-on-emceedanko.sh` | Script 05: disposable EmceeDanko ingestion and 60-question frontier qualification | Tracked |
| `deployment/scripts/06_attended-v1.3-on-emceedanko.sh` | Script 06: reversible attended EmceeDanko v1.3 deployment, acceptance, and rollback | Tracked |
| `deployment/scripts/07_build-node-next-runtime-on-emceedanko.sh` | Script 07: checksum-bound native AMD64 runtime build on EmceeDanko and verified local publication | Tracked |
| `deployment/scripts/build-carry-candidate.sh` | Assemble and atomically publish the separate application/runtime portable deployment candidate | Tracked |
| `deployment/runtime-image/` | Application-free runtime Dockerfile, exact lock, and portable security/license records | Tracked |
| `deployment/carry/` | Portable verifier, consolidated deployment entrypoint, and operator command sheet | Tracked |
| `deployment/assets/stage-v1.3-candidate` | Bounded target-side Script 04 helper | Tracked |
| `deployment/assets/qualify-v1.3-candidate` | Bounded target-side Script 05 helper | Tracked |
| `deployment/assets/build-node-next-runtime` | Unnumbered native-host runtime-image builder invoked by Script 07 | Tracked |
| `deployment/tests/release-boundary.sh` | Application/corpus independence regression | Tracked |
| `deployment/tests/stage-candidate-helper.sh` | Script 04 fresh/reuse/mismatch regression | Tracked |
| `deployment/tests/stage-candidate-wrapper.sh` | Script 04 end-to-end wrapper regression | Tracked |
| `deployment/tests/qualify-candidate-helper.sh` | Script 05 disposable lifecycle, failure, cleanup, and preservation regression | Tracked |
| `deployment/tests/qualify-candidate-wrapper.sh` | Script 05 transfer, result, publication, and failure regression | Tracked |
| `deployment/tests/attended-v1.3-target.sh` | Script 06 isolated target lifecycle, failure restoration, acceptance, and rollback regression | Tracked |
| `deployment/tests/attended-v1.3-wrapper.sh` | Script 06 transport, reporting, failure propagation, signal, and result-contract regression | Tracked |
| `deployment/tests/runtime-image-builder.sh` | Runtime-image success, supersession, checksum, boundary, and failure regression | Tracked |
| `deployment/tests/native-runtime-build-wrapper.sh` | Script 07 transfer, native-build, artifact-return, refusal, preservation, and cleanup regression | Tracked |
| `deployment/tests/application-release-builder.sh` | Application build, deterministic publication, checksum, SBOM/license, and failure regression | Tracked |
| `deployment/tests/stack-lifecycle.sh` | Production stack build/start/restart/timeout/failure/cleanup regression | Tracked |
| `deployment/tests/carry-builder.sh` | Portable carry assembly, supersession, identity, checksum, and terminology regression | Tracked |
| `deployment/tests/deployment-entrypoint.sh` | Portable verify, install, configure, database, lifecycle, removal, and cleanup regression | Tracked |
| `qualification/frontier/` | Frozen 60-question gate | Tracked |
| `qualification/frontier/evaluate-frontier.py` | Exact 60-question target qualification evaluator | Tracked |
| `deployment/scripts/` | Active operator interfaces | Tracked |
| `deployment/assets/` | Package verifiers and bounded target helpers | Tracked |
| `deployment/evidence/` | Reviewed content-free summaries | Tracked |
| `history/phase-28/` | Historical development record | Tracked, not executable replay |
| `local/artifacts/` | Generated candidates and current handoffs | Ignored |
| `local/reports/` | Raw operator reports | Ignored |
| `local/imported-evidence/` | Raw origin evidence used during bootstrap | Ignored |
| `state/`, `corpus/source/` | Runtime state and organizational documents | Ignored |

Changes to repository-wide ignore behavior require updating this registry.
