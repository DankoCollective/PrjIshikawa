# Ishikawa Release Decisions

## Purpose

Record the frozen promotion of Ishikawa v1.3 from its Phase 28 development
workspace into a first-class repository and define the EmceeDanko deployment
journey.

## Current Status

Items V13-60 through V13-67 are frozen by the operator on 2026-10-24.
Implementation must preserve the accepted product behavior and qualification
thresholds unless a later numbered decision explicitly reopens them.

## Decisions

### V13-60 — Feature and release freeze

Decision: Ishikawa v1.3 and synthetic corpus v3 are feature-complete and
locally frozen.

Status: FROZEN.

Recommendation: Bind the exact source, clean 486-test and 60-question evidence,
corpus identity, and operator-attested human UI acceptance. Future behavioral
changes belong to a later release.

Reason/Evidence: The clean V13-59 gate passed 60/60 and the operator accepted
the local UI after minor smoke testing.

### V13-61 — First-class sibling repository

Decision: Create a sibling `PrjIshikawa` repository as Ishikawa's authoritative
home from v1.3 onward.

Status: FROZEN.

Recommendation: Preserve the origin workspace without deletion and import an
exact checksum-bound product snapshot.

Reason/Evidence: Most Phase 28 implementation bytes were intentionally ignored
by the origin Git repository and therefore lacked durable source history.

### V13-62 — Provenance model

Decision: Use a checksum-bound import ledger rather than inventing Git history
for previously untracked files.

Status: FROZEN.

Recommendation: Record the origin repository commit, paths, source manifest,
frontier artifact identity, and import time.

Reason/Evidence: Git cannot reconstruct commits for bytes it never tracked.

### V13-63 — Post-v1.3 optimization record

Decision: Preserve the former `scratch.txt` analysis as a durable roadmap
record that does not amend v1.3.

Status: FROZEN.

Recommendation: Evaluate the backlog only in a later release with the complete
frontier and human-review gates.

Reason/Evidence: The record proposes routing, hydration, packing, generation,
and database optimizations that were not part of the accepted release.

### V13-64 — Repository and control-surface shape

Decision: Preserve the behavior of the existing agent control surface while
removing repository-specific names and paths from shared instructions.

Status: FROZEN.

Recommendation: Keep shared standards repository-neutral. Regenerate context,
runbook, registries, and organization files for Ishikawa. Never copy keys,
credentials, personal configuration, or global tool state.

Reason/Evidence: The control behavior is reusable; the former repository's
phase inventory and paths are not.

### V13-65 — Local-resource migration

Decision: Copy, inventory, hash, and verify useful local resources without
deleting origin bytes.

Status: FROZEN.

Recommendation: Track canonical source and sanitized evidence; keep raw reports
and captures ignored; regenerate derived chunks and embeddings; exclude secrets,
private corpus material, caches, and temporary databases.

Reason/Evidence: A blind local-tree copy would mix release inputs with raw or
regenerable state and violate the repository evidence boundary.

### V13-66 — Final deployment package

Decision: Rebuild the final v1.3 package from the imported frozen source under
the Coding Standard.

Status: FROZEN.

Recommendation: Require native and web tests, deterministic assembly, complete
manifests, fresh-install verification, schema v5, separate corpus v3 transfer,
and atomic stable `-current` publication. Do not deploy earlier candidate
archives.

Reason/Evidence: Existing candidate receipts predate the final 486-test V13-59
source state.

### V13-67 — EmceeDanko qualification and deployment

Decision: Use the frozen attended inventory, disposable qualification,
deployment, human-verification, acceptance, and rollback sequence.

Status: FROZEN.

Recommendation: Do not mutate EmceeDanko before inventory and disposable
qualification. Verify both transfers, ingest corpus v3 through the shipped
pipeline, run the complete frontier gate, prove cleanup, preserve the prior
installation, keep boot autostart disabled, and require human acceptance.

Reason/Evidence: This preserves the previous migration controls while adding
the target-side corpus, frontier, and human-experience gates required for v1.3.
