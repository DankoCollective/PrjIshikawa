# Agent Operation

Reusable remote, deployment, decision, operator-script, and review procedures
live in the global agreement and skills selected by `AGENTS.md`. This file
contains only Ishikawa-specific operating requirements.

## Local authorities

- Read `danko_lab.md` before lab-specific planning or execution and verify its
  snapshot when current state matters.
- Read `local/Port_Forwarding.md` before proposing a service forward. Reuse its
  direct-tunnel convention and canonical aliases; do not invent a transit
  chain or one-off mapping.
- Read `node_nextjs_runtime_image.md` before selecting, changing, packaging, or
  using the shared Node/Next.js runtime image.
- Follow `LAB_RUN_PATH_STANDARD.md`, `PROJECT_RUNBOOK.md`, and the applicable
  operation or release record for operator-run, package, or remote work.
- Record runtime and product decisions in the authoritative list under
  `docs/decisions/`.

## Fresh-install database ordering

Application installation and database initialization are separate packaged
stages. On a fresh installation, do not direct an operator into catalog,
manifest, extraction, embedding, or publication work until retained evidence
contains:

```text
SCRIPT RESULT
ishikawa_deployment_install_schema=pass
```

If absent, the next stage is the packaged `deploy-ishikawa install-schema`
action. Do not ask the operator to hand-create roles, databases, extensions,
or schema objects. `ishikawa_ingestion_config=ready` does not satisfy this
gate.

## Ishikawa-specific boundaries

- Do not add connectivity, DNS, route, socket, ping, curl, or equivalent probes
  merely to prove an approved offline setting such as Docker `--network none`
  or empty APT sources. A live network probe requires explicit direction.
- Keep synthetic qualification separate from black-corpus access and evidence.
- PostgreSQL remains the runtime source of truth; do not create a flat-file
  retrieval index.
- Keep boot autostart disabled unless separately approved.
- `<solution-name>-current/` is the sole operator handoff. Dated or revision
  outputs remain candidates until exact accepted bytes and verification files
  are promoted and independently verified.

## Evidence boundary

Do not store credentials, private documents, prompts, responses, chunks,
vectors, database dumps, or unredacted private screenshots in Git. Review,
audit, and sweep work remains read-only unless repair is explicitly authorized
after findings are reported.
