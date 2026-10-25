# File Registry

| Path | Role | Git posture |
|---|---|---|
| `Ishikawa/` | Canonical product source and tests | Tracked |
| `qualification/corpus-v3/` | Synthetic qualification fixture | Tracked |
| `qualification/frontier/` | Frozen 60-question gate | Tracked |
| `deployment/scripts/` | Active operator interfaces | Tracked |
| `deployment/assets/` | Package verifiers and bounded target helpers | Tracked |
| `deployment/evidence/` | Reviewed content-free summaries | Tracked |
| `history/phase-28/` | Historical development record | Tracked, not executable replay |
| `local/artifacts/` | Generated candidates and current handoffs | Ignored |
| `local/reports/` | Raw operator reports | Ignored |
| `local/imported-evidence/` | Raw origin evidence used during bootstrap | Ignored |
| `state/`, `corpus/source/` | Runtime state and organizational documents | Ignored |

Changes to repository-wide ignore behavior require updating this registry.
