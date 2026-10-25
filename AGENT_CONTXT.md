# Agent Context

## Product

Ishikawa is a portable, operator-controlled organizational knowledge assistant.
It ingests approved documents into PostgreSQL, retrieves bounded evidence, uses
Gemma for inference, validates citations, and presents selectable reconstructed
source text. Nomic provides query and document embeddings.

## Current accepted posture

- Ishikawa v1.3 is feature-complete and locally frozen.
- Synthetic corpus v3 is the accepted qualification fixture.
- The clean local gate passed 486 native tests and 60/60 frontier cases.
- Human UI validation and minor smoke testing are operator-accepted.
- The active journey is final release assembly, EmceeDanko qualification,
  attended deployment, and target-side human verification.
- Org-lab migration is deferred until EmceeDanko acceptance.

## Boundaries

- Do not contact a remote host unless the operator explicitly directs that
  specific remote action in the current turn.
- Do not read, copy, or ingest the black corpus during synthetic qualification.
- Do not place credentials, private documents, prompts, responses, chunks,
  vectors, or database dumps in Git.
- Keep PostgreSQL as the runtime source of truth; do not create flat-file
  retrieval indexes.
- Keep boot autostart disabled unless separately approved.
- Preserve accepted prior installations and provide a proved rollback path.

## Authoritative files

- Danko Lab systems and services: `danko_lab.md`
- Shared Node/Next.js runtime image: `node_nextjs_runtime_image.md`
- Agent behavior: `AGENT_OPERATION.md` and `AGENT_PERSONA.md`
- Code and package rules: `CODING_STANDARD.md`
- Operator-run and remote rules: `LAB_RUN_PATH_STANDARD.md`
- SSH connection reuse: `SSH_CONNECTION_REUSE_STANDARD.md`
- Current decisions: `docs/decisions/ISHIKAWA_RELEASE_DECISIONS.md`
- Release freeze: `docs/releases/ISHIKAWA_V1_3_RELEASE_FREEZE.md`
- Execution order: `PROJECT_RUNBOOK.md`
- Accounts, services, commands, and permissions:
  `docs/operations/ISHIKAWA_V1_3_OPERATING_SURFACE.md`
- Document catalog, manifest, and ingestion procedure:
  `docs/operations/CORPUS_INGESTION_RUNBOOK.md`
- Current repository reconciliation evidence:
  `docs/releases/ISHIKAWA_V1_3_REPOSITORY_SWEEP.md`
