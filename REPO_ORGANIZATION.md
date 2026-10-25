# Repository Organization

- `Ishikawa/` is the canonical product source, tests, configuration, packaging,
  and product documentation.
- `docs/decisions/` contains current Anderson-format decisions.
- `docs/releases/` contains release freezes and acceptance receipts.
- `docs/roadmap/` contains deferred work that does not amend a frozen release.
- `docs/history/` contains curated provenance narratives.
- `qualification/corpus-v3/` contains the synthetic source fixture, truth, and
  manifests used to reproduce qualification.
- `qualification/frontier/` contains the frozen frontier case set.
- `deployment/scripts/` contains the active consolidated build, qualification,
  deployment, acceptance, and rollback interfaces.
- `deployment/evidence/` contains sanitized, content-free accepted summaries.
- `deployment/assets/` contains release verifiers and bounded remote helpers;
  helpers must remain content-free and portable.
- `history/phase-28/` preserves development decisions, scripts, references, and
  evidence. It is historical and must not be used as the normal fresh-install
  path.
- `local/` is ignored and owns reports, raw captures, staging, credentials, and
  generated artifacts.

The root control surface is repository-neutral. Product-specific facts belong
in `AGENT_CONTXT.md`, this file, the runbook, registries, and product decisions.
