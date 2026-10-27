# Reference Directory

## Normative repository references

- Danko Lab operating reference: `danko_lab.md`
- Node/Next.js runtime image definition: `node_nextjs_runtime_image.md`
- Agent operation: `AGENT_OPERATION.md`
- Agent persona: `AGENT_PERSONA.md`
- Coding standard: `CODING_STANDARD.md`
- Operator run path: `LAB_RUN_PATH_STANDARD.md`
- SSH reuse: `SSH_CONNECTION_REUSE_STANDARD.md`
- Product context: `AGENT_CONTXT.md`
- Runbook: `PROJECT_RUNBOOK.md`
- Organization: `REPO_ORGANIZATION.md`

## Ishikawa references

- Architecture: `Ishikawa/docs/ARCHITECTURE.md`
- Chunking, ingestion, and retrieval: `Ishikawa/docs/CHUNKING_INGESTION_RETRIEVAL.md`
- Operator guide: `Ishikawa/docs/OPERATOR_GUIDE.md`
- Exact YAML contracts: `Ishikawa/docs/CONFIGURATION_CONTRACTS.md`
- Installed ingestion boundary: `Ishikawa/docs/INSTALLED_OPERATOR_INGESTION.md`
- Service operations: `Ishikawa/docs/SERVICE_OPERATIONS.md`
- Operating-surface inventory: `docs/operations/ISHIKAWA_V1_3_OPERATING_SURFACE.md`
- Corpus ingestion runbook: `docs/operations/CORPUS_INGESTION_RUNBOOK.md`
- Frozen decisions: `docs/decisions/ISHIKAWA_RELEASE_DECISIONS.md`
- v1.3 freeze: `docs/releases/ISHIKAWA_V1_3_RELEASE_FREEZE.md`
- Repository sweep: `docs/releases/ISHIKAWA_V1_3_REPOSITORY_SWEEP.md`
- Org-lab carry readiness checklist:
  `docs/releases/ISHIKAWA_ORG_LAB_CARRY_READINESS_CHECKLIST.md`
- EmceeDanko qualification receipt:
  `deployment/evidence/ISHIKAWA_V1_3_EMCEEDANKO_QUALIFICATION.md`
- Import ledger: `docs/releases/ISHIKAWA_V1_3_IMPORT_PROVENANCE.md`
- Future optimization backlog: `docs/roadmap/ISHIKAWA_POST_V1_3_OPTIMIZATION_BACKLOG.md`
- Phase 28 provenance: `docs/history/PHASE_28_TO_V1_3.md`

## Ishikawa security review sources

- Node.js October 2026 security releases:
  <https://nodejs.org/en/blog/vulnerability/october-2026-security-releases>
- Node.js 24.22.1 security release:
  <https://nodejs.org/en/blog/release/v24.22.1>
- React Server Components advisory GHSA-xqc2-xf4c-x3h3:
  <https://github.com/react/react/security/advisories/GHSA-xqc2-xf4c-x3h3>
- Next.js development-server advisory GHSA-39w2-rjm5-chcv:
  <https://github.com/vercel/next.js/security/advisories/GHSA-39w2-rjm5-chcv>

These sources require a fresh affectedness review at package time. Listing a
source here does not clear a dependency or substitute for a recorded advisory
disposition.

## PostgreSQL native-package sources

- PostgreSQL Apt Repository for Ubuntu:
  <https://www.postgresql.org/download/linux/ubuntu/>
- Signed Ubuntu 26.04 `resolute-pgdg` repository index:
  <https://apt.postgresql.org/pub/repos/apt/dists/resolute-pgdg/>
- PostgreSQL 16 package pool:
  <https://apt.postgresql.org/pub/repos/apt/pool/main/p/postgresql-16/>
- pgvector package pool:
  <https://apt.postgresql.org/pub/repos/apt/pool/main/p/pgvector/>
- PostgreSQL 16 security table:
  <https://www.postgresql.org/support/security/16/>
- PostgreSQL 16.15 release notes:
  <https://www.postgresql.org/docs/16/release-16-15.html>
- pgvector changelog:
  <https://github.com/pgvector/pgvector/blob/master/CHANGELOG.md>
- pgvector upstream vulnerability records:
  <https://github.com/pgvector/pgvector/issues/1036>,
  <https://github.com/pgvector/pgvector/issues/1006>, and
  <https://github.com/pgvector/pgvector/issues/959>
- Debian pgvector security tracker:
  <https://security-tracker.debian.org/tracker/source-package/pgvector>
- Debian postgresql-common security tracker:
  <https://security-tracker.debian.org/tracker/source-package/postgresql-common>
- Psycopg upstream advisory page:
  <https://github.com/psycopg/psycopg/security/advisories>
- Ubuntu 26.04 `python3-psycopg` package identity:
  <https://packages.ubuntu.com/resolute/python3-psycopg>

These references establish source availability only. The deployment still
requires a signature-verified, checksum-bound, complete offline dependency
closure and an offline installation proof before final carry publication.
