# File Registry

| Path | Role | Git posture |
|---|---|---|
| `danko_lab.md` | Shared non-secret Danko Lab systems, addresses, hardware roles, installed services, ports, collisions, and operating reference | Tracked |
| `Ishikawa/` | Canonical product source and tests | Tracked |
| `docs/operations/ISHIKAWA_V1_3_OPERATING_SURFACE.md` | Accounts, roles, services, commands, paths, and permission inventory | Tracked |
| `docs/operations/CORPUS_INGESTION_RUNBOOK.md` | Operator catalog, manifest, validation, publication, and verification guide | Tracked |
| `docs/releases/ISHIKAWA_V1_3_REPOSITORY_SWEEP.md` | Reviewed repository-wide agreement and validation record | Tracked |
| `deployment/evidence/ISHIKAWA_V1_3_EMCEEDANKO_QUALIFICATION.md` | Content-free EmceeDanko disposable qualification receipt | Tracked |
| `qualification/corpus-v3/` | Synthetic qualification fixture | Tracked |
| `qualification/corpus-v3/document-keys.json` | Stable fixture document-key registry | Tracked |
| `deployment/scripts/01_build-ishikawa-release.sh` | Script 01: corpus-agnostic v1.3 release builder | Tracked |
| `deployment/scripts/02_inventory-emceedanko.sh` | Script 02: read-only EmceeDanko deployment inventory | Tracked |
| `deployment/scripts/03_export-qualification-corpus.sh` | Script 03: independent qualification-corpus exporter | Tracked |
| `deployment/scripts/04_stage-v1.3-candidate-on-emceedanko.sh` | Script 04: side-by-side EmceeDanko candidate staging | Tracked |
| `deployment/scripts/05_qualify-v1.3-on-emceedanko.sh` | Script 05: disposable EmceeDanko ingestion and 60-question frontier qualification | Tracked |
| `deployment/assets/stage-v1.3-candidate` | Bounded target-side Script 04 helper | Tracked |
| `deployment/assets/qualify-v1.3-candidate` | Bounded target-side Script 05 helper | Tracked |
| `deployment/tests/release-boundary.sh` | Application/corpus independence regression | Tracked |
| `deployment/tests/stage-candidate-helper.sh` | Script 04 fresh/reuse/mismatch regression | Tracked |
| `deployment/tests/stage-candidate-wrapper.sh` | Script 04 end-to-end wrapper regression | Tracked |
| `deployment/tests/qualify-candidate-helper.sh` | Script 05 disposable lifecycle, failure, cleanup, and preservation regression | Tracked |
| `deployment/tests/qualify-candidate-wrapper.sh` | Script 05 transfer, result, publication, and failure regression | Tracked |
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
