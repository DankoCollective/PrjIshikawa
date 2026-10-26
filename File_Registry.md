# File Registry

| Path | Role | Git posture |
|---|---|---|
| `Initial_Assessment_Ishikawa.md` | Reviewer handoff with the current Ishikawa v1.3 assessment, risks, and forward plan | Tracked |
| `danko_lab.md` | Shared non-secret Danko Lab systems, addresses, hardware roles, installed services, ports, collisions, and operating reference | Tracked |
| `local/Port_Forwarding.md` | Canonical local operator reference for direct `00Danko` service forwarding to DankoSurface or EmceeDanko | Ignored |
| `node_nextjs_runtime_image.md` | Product-neutral definition and exact application-free Linux AMD64 Node 24.22.1, Next.js 16.4.3, and React 19.2.9 runtime contract | Tracked |
| `Ishikawa/` | Canonical product source and tests | Tracked |
| `docs/operations/ISHIKAWA_V1_3_OPERATING_SURFACE.md` | Accounts, roles, services, commands, paths, and permission inventory | Tracked |
| `docs/operations/CORPUS_INGESTION_RUNBOOK.md` | Operator catalog, manifest, validation, publication, and verification guide | Tracked |
| `docs/releases/ISHIKAWA_V1_3_REPOSITORY_SWEEP.md` | Reviewed repository-wide agreement and validation record | Tracked |
| `docs/releases/ISHIKAWA_ORG_LAB_CARRY_READINESS_CHECKLIST.md` | Durable decision-review queue and checkable final deployment carry gates | Tracked |
| `docs/releases/ISHIKAWA_V1_3_1_DEPLOYMENT_PACKAGE_MANIFEST.md` | Classified 25-file v1.3.1 deployment-package manifest contract and exclusion boundary | Tracked |
| `docs/roadmap/ISHIKAWA_V1_3_2_CLARIFICATION_CONTINUITY.md` | v1.3.2 investigation and qualification boundary for clarification continuity, visible UI release identity, and citation-excerpt overflow | Tracked |
| `deployment/evidence/ISHIKAWA_V1_3_EMCEEDANKO_QUALIFICATION.md` | Content-free EmceeDanko disposable qualification receipt | Tracked |
| `deployment/evidence/ISHIKAWA_V1_3_EMCEEDANKO_UI_ACCEPTANCE.md` | Content-free operator UI-acceptance receipt for the exact v1.3 baseline | Tracked |
| `deployment/evidence/ISHIKAWA_V1_3_1_LOCAL_IMPLEMENTATION.md` | Content-free v1.3.1 source implementation and executable local-gate receipt | Tracked |
| `deployment/evidence/ISHIKAWA_V1_3_1_SECURITY_REVIEW.md` | Content-free exact-image scan result, open advisory dispositions, and runtime-remediation decision boundary | Tracked |
| `qualification/corpus-v3/` | Synthetic qualification fixture | Tracked |
| `qualification/corpus-v3/document-keys.json` | Stable fixture document-key registry | Tracked |
| `deployment/scripts/01_build-ishikawa-release.sh` | Script 01: corpus-agnostic v1.3 release builder | Tracked |
| `deployment/scripts/02_inventory-emceedanko.sh` | Script 02: read-only EmceeDanko deployment inventory | Tracked |
| `deployment/scripts/03_export-qualification-corpus.sh` | Script 03: independent qualification-corpus exporter | Tracked |
| `deployment/scripts/04_stage-v1.3-candidate-on-emceedanko.sh` | Script 04: side-by-side EmceeDanko candidate staging | Tracked |
| `deployment/scripts/05_qualify-v1.3-on-emceedanko.sh` | Script 05: disposable EmceeDanko ingestion and 60-question frontier qualification | Tracked |
| `deployment/scripts/06_attended-v1.3-on-emceedanko.sh` | Script 06: reversible attended EmceeDanko v1.3 deployment, acceptance, and rollback | Tracked |
| `deployment/scripts/07_build-node-next-runtime-on-emceedanko.sh` | Script 07: checksum-bound native AMD64 runtime build on EmceeDanko and verified local publication | Tracked |
| `deployment/scripts/08_build-v1.3.1-application-on-emceedanko.sh` | Script 08: exact v1.3.1 external-application build and verified local publication | Tracked |
| `deployment/scripts/09_requalify-v1.3.1-on-emceedanko.sh` | Script 09: exact-byte production-runtime requalification, acceptance, and cleanup | Tracked |
| `deployment/scripts/10_promote-v1.3.1-on-emceedanko.sh` | Script 10: attended v1.3.1 production-port promotion, acceptance, and rollback | Tracked |
| `deployment/scripts/11_assemble-ishikawa-v1.3.1-deployment-package.sh` | Script 11: assemble and atomically publish the classified application/runtime deployment-package candidate | Tracked |
| `deployment/scripts/12_requalify-v1.3.1-corrected-runtime-on-emceedanko.sh` | Script 12: side-by-side production/frontier requalification and acceptance of the corrected runtime with unchanged v1.3.1 application | Tracked |
| `deployment/runtime-image/` | Application-free runtime Dockerfile, exact lock, and portable security/license records | Tracked |
| `deployment/carry/` | Portable verifier, consolidated deployment entrypoint, and operator command sheet | Tracked |
| `deployment/assets/stage-v1.3-candidate` | Bounded target-side Script 04 helper | Tracked |
| `deployment/assets/qualify-v1.3-candidate` | Bounded target-side Script 05 helper | Tracked |
| `deployment/assets/build-node-next-runtime` | Unnumbered native-host runtime-image builder invoked by Script 07 | Tracked |
| `deployment/assets/requalify-v1.3.1-on-emceedanko` | Bounded target-side shared Script 09/12 production requalification helper | Tracked |
| `deployment/assets/promote-v1.3.1-on-emceedanko` | Bounded target-side Script 10 promotion, acceptance, and rollback helper | Tracked |
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
| `deployment/tests/v1.3.1-requalification-target.sh` | Script 12 target corrected-runtime, acceptance, cleanup, and failure regression | Tracked |
| `deployment/tests/v1.3.1-requalification-wrapper.sh` | Script 12 transport, evidence, refusal, recovery, publication, and cleanup regression | Tracked |
| `deployment/tests/v1.3.1-promotion-target.sh` | Script 10 target promotion, expected-consumer cleanup, unknown-consumer refusal, acceptance, rollback, and restoration regression | Tracked |
| `deployment/tests/v1.3.1-promotion-wrapper.sh` | Script 10 transport, evidence publication, refusal, signal, and cleanup regression | Tracked |
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
