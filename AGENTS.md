# Codex Project Entry Point

## Always load

Read `AGENT_CONTXT.md` first. It contains current product state, boundaries,
and the authoritative-file map. Read only the additional local authorities
that apply to the task.

Repository-specific facts, frozen decisions, paths, identities, and exceptions
override repo-agnostic defaults when they are more specific. Report an exact
conflict instead of silently choosing one rule.

## Task routes

- Product discussion or status: use `AGENT_CONTXT.md` and the current decision,
  release, or runbook authority it names.
- Code, scripts, tests, generators, or validators: use the `coding-standard`
  skill and read `CODING_STANDARD.md`.
- Multi-stage operator commands: also use `operator-script-standard` and read
  `AGENT_OPERATION.md` plus the applicable runbook.
- Package, installer, update, rollback, ingestion release, or promotion work:
  also use `deployment-qualification` and the exact release/package records.
- Danko Lab access, transfer, or service work: also use
  `danko-lab-operations`, `danko_lab.md`, `LAB_RUN_PATH_STANDARD.md`, and the
  applicable forwarding or connection standard.
- Decisions: use `decision-record` and the current Ishikawa decision authority.
- Focused or holistic agreement review: use `repo-sweep`; review remains
  read-only unless repair is explicitly authorized after the sweep.
- Read `AGENT_PERSONA.md` for broad planning and operator-facing writing.

## Boundaries

Preserve unrelated worktree changes. Do not contact a remote host unless the
operator authorizes that exact action in the current turn. Review authority
does not imply repair, publication, credential access, corpus access, database
mutation, or service mutation.
