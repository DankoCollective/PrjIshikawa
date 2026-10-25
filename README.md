# Ishikawa

Ishikawa is a locally operated knowledge assistant that retrieves authoritative
organizational documents from PostgreSQL, composes bounded evidence for Gemma,
and returns citation-bearing answers with reconstructable document views.

The repository begins with the frozen Ishikawa v1.3 release baseline imported
from the Phase 28 development workspace. The origin workspace remains preserved
as historical evidence; this repository is the authoritative product home from
v1.3 onward.

## Current release posture

- Product: Ishikawa v1.3
- Corpus qualification fixture: synthetic corpus v3, 30 documents and 150 pages
- Retrieval MRR@20: 0.895450
- Local frontier gate: 60/60
- Local native regression: 486 tests
- Local human UI review: accepted with minor smoke testing
- EmceeDanko deployment: pending attended qualification and human verification

Start with `PROJECT_RUNBOOK.md`. Product implementation is under `Ishikawa/`.
Historical Phase 28 materials are retained under `history/phase-28/` and are not
the active installation or replay interface.

`Ishikawa/README.md` is retained inside the frozen imported source manifest as
a chronological development ledger. It is not the current deployment status
or operator run path; this root README, `AGENT_CONTXT.md`, and
`PROJECT_RUNBOOK.md` are authoritative for those purposes.
