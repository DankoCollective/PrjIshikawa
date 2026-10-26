# Ishikawa Release Decisions

## Purpose

Record the frozen promotion of Ishikawa v1.3 from its Phase 28 development
workspace into a first-class repository and define the EmceeDanko deployment
journey.

## Current Status

Items V13-60 through V13-75 are frozen through the operator-approved release
journey and bounded corrections to that existing contract. Implementation must
preserve the accepted product behavior and qualification thresholds unless a
later numbered decision explicitly reopens them. Scripts 01-06 implement the
corpus-agnostic build, independent corpus export, read-only inventory,
side-by-side staging, disposable qualification, and attended deployment
sequence. Script 05 passed on EmceeDanko with 60/60 frontier cases and proved
cleanup. The active gate is attended v1.3 human UI validation on EmceeDanko.

## Decisions

### V13-60 — Feature and release freeze

Decision: Ishikawa v1.3 and synthetic corpus v3 are feature-complete and
locally frozen.

Status: Frozen.

Recommendation: Bind the exact source, clean 486-test and 60-question evidence,
corpus identity, and operator-attested human UI acceptance. Future behavioral
changes belong to a later release.

Reason/Evidence: The clean V13-59 gate passed 60/60 and the operator accepted
the local UI after minor smoke testing.

### V13-61 — First-class sibling repository

Decision: Create a sibling `PrjIshikawa` repository as Ishikawa's authoritative
home from v1.3 onward.

Status: Frozen.

Recommendation: Preserve the origin workspace without deletion and import an
exact checksum-bound product snapshot.

Reason/Evidence: Most Phase 28 implementation bytes were intentionally ignored
by the origin Git repository and therefore lacked durable source history.

### V13-62 — Provenance model

Decision: Use a checksum-bound import ledger rather than inventing Git history
for previously untracked files.

Status: Frozen.

Recommendation: Record the origin repository commit, paths, source manifest,
frontier artifact identity, and import time.

Reason/Evidence: Git cannot reconstruct commits for bytes it never tracked.

### V13-63 — Post-v1.3 optimization record

Decision: Preserve the former `scratch.txt` analysis as a durable roadmap
record that does not amend v1.3.

Status: Frozen.

Recommendation: Evaluate the backlog only in a later release with the complete
frontier and human-review gates.

Reason/Evidence: The record proposes routing, hydration, packing, generation,
and database optimizations that were not part of the accepted release.

### V13-64 — Repository and control-surface shape

Decision: Preserve the behavior of the existing agent control surface while
removing repository-specific names and paths from shared instructions.

Status: Frozen.

Recommendation: Keep shared standards repository-neutral. Regenerate context,
runbook, registries, and organization files for Ishikawa. Never copy keys,
credentials, personal configuration, or global tool state.

Reason/Evidence: The control behavior is reusable; the former repository's
phase inventory and paths are not.

### V13-65 — Local-resource migration

Decision: Copy, inventory, hash, and verify useful local resources without
deleting origin bytes.

Status: Frozen.

Recommendation: Track canonical source and sanitized evidence; keep raw reports
and captures ignored; regenerate derived chunks and embeddings; exclude secrets,
private corpus material, caches, and temporary databases.

Reason/Evidence: A blind local-tree copy would mix release inputs with raw or
regenerable state and violate the repository evidence boundary.

### V13-66 — Final deployment package

Decision: Rebuild the final v1.3 package from the imported frozen source under
the Coding Standard.

Status: Frozen.

Recommendation: Require native and web tests, deterministic assembly, complete
manifests, fresh-install verification, schema v5, separate corpus v3 transfer,
and atomic stable `-current` publication. Do not deploy earlier candidate
archives.

Reason/Evidence: Existing candidate receipts predate the final 486-test V13-59
source state.

### V13-67 — EmceeDanko qualification and deployment

Decision: Use the frozen attended inventory, disposable qualification,
deployment, human-verification, acceptance, and rollback sequence.

Status: Frozen.

Recommendation: Do not mutate EmceeDanko before inventory and disposable
qualification. Verify both transfers, ingest corpus v3 through the shipped
pipeline, run the complete frontier gate, prove cleanup, preserve the prior
installation, keep boot autostart disabled, and require human acceptance.

Reason/Evidence: This preserves the previous migration controls while adding
the target-side corpus, frontier, and human-experience gates required for v1.3.

### V13-68 — Corpus-agnostic release identity

Decision: Name and build the application as Ishikawa v1.3, independently of
every qualification or organizational corpus.

Status: Frozen.

Recommendation: Publish the application only under
`ishikawa-v1.3-current` with archive name `ishikawa-v1.3.tar.gz`. Export the
synthetic v3 fixture separately under `qualification-corpus-v3-current`.
Application validation, assembly, installation, and verification must not read,
count, package, or publish corpus files. Transfer the separate fixture to
EmceeDanko only for target-side chunking, ingestion, frontier qualification,
and human testing.

Reason/Evidence: Ishikawa is a corpus-agnostic product. The prior combined
builder mislabeled the release as a corpus/frontier artifact and coupled
application publication to one qualification fixture even though the packaged
application already contained zero source documents.

### V13-69 — Side-by-side EmceeDanko candidate and rollback preservation

Decision: Preserve the accepted v1.2 installation and its rollback tree while
staging v1.3 in a separate versioned location.

Status: Frozen.

Recommendation: Install or checksum-verify v1.3 only at
`~/Documents/Ishikawa-v1.3`. Retain the checksum-bound qualification corpus
outside the application tree. A rerun may reuse only byte-identical application
and corpus inputs; every mismatch fails closed. Do not stop, overwrite,
promote, or uninstall v1.2 during staging. Use a disposable database for v1.3
chunking, ingestion, and qualification. Stop v1.2 only for the later attended
production-port UI test, restart it on failure, and promote v1.3 only after
human acceptance.

Reason/Evidence: Script 02 found the active v1.2 root and its rollback tree
present, the v1.3 candidate path absent, and the v1.2 Retrieval API and web
ports active. Side-by-side staging preserves immediate rollback and prevents a
fresh installer from merging with accepted state. Executable regressions prove
fresh staging, exact reuse, application and corpus drift rejection, checksum
and readiness rejection, partial-failure cleanup, wrapper milestone ordering,
nested failure propagation, signal status 143, and temporary-transfer cleanup.

### V13-70 — Disposable EmceeDanko frontier qualification

Decision: Qualify the exact Script 04 candidate and independent corpus-v3 input
before stopping v1.2 or using the production ports.

Status: Frozen.

Recommendation: Reverify the staged candidate against the Script 01 payload,
copy it into a private workspace, use PostgreSQL port 65438 and Retrieval API
port 1385, run all 486 native tests against the private installed copy, ingest
all 30 synthetic documents through the shipped command, and
require all 60 frontier cases to return and cite their required evidence. Keep
the accepted database untouched. Delete credentials, the temporary API,
database, workspace, and transfer before publishing the synthetic-only result.

Reason/Evidence: The Script 05 regressions exercise the complete helper
lifecycle and the outer transport path. They prove candidate-drift rejection,
protected credential entry, disposable ingestion and API readiness, the exact
frontier contract, classified model/frontier failures, nested failure
propagation, atomic local publication, cleanup, and v1.2 preservation.

### V13-71 — Configurable private qualification listener

Decision: Keep `127.0.0.1:1384` as the packaged Retrieval API default while
allowing a deployment configuration to select another valid loopback TCP port.
Script 05 must set both the deployment profile and Retrieval API service
profile to its reserved private port `1385`. Credential prompts must be emitted
as complete lines before hidden input begins, and qualification tests must run
the packaged Retrieval API's real `--check-config` path.

Status: Frozen.

Recommendation: Keep the packaged default unchanged and permit only a
validated loopback listener override through the deployment and Retrieval API
profiles. Exercise the real packaged validator before target-side work.

Reason/Evidence: V13-70 reserves port `1385` so v1.3 can be qualified without
stopping v1.2 on `1384`. The prior service-profile validator nevertheless
hard-coded `1384`, making the frozen side-by-side configuration impossible,
while the qualification test double bypassed the real validator. This is a
bounded deployment correction: loopback binding, the default port, retrieval
behavior, corpus, schemas, UI, and accepted evidence remain unchanged.

### V13-72 — Explicit replacement of an unqualified side-by-side candidate

Decision: Script 04 may replace only `~/Documents/Ishikawa-v1.3`, and only
when the operator supplies `--replace-unqualified-candidate`. It must first
install and verify the new archive in a private sibling directory, move the old
candidate into a temporary rollback location, publish the new candidate with a
rename, restore the old candidate on any later failure, and preserve v1.2 and
its rollback tree throughout.

Status: Frozen.

Recommendation: Require the explicit replacement flag, stage and verify the
new candidate privately, publish it atomically, and restore the previous
unqualified candidate on failure without touching v1.2.

Reason/Evidence: The V13-71 correction changes the checksum-bound application
archive after an earlier, unqualified candidate was staged. Silent overwrite
would weaken V13-69, while requiring manual deletion would remove rollback and
repeatability guarantees. The explicit atomic path changes no accepted v1.2,
database, service, port, corpus, or boot state.

### V13-73 — One authoritative schema-v5 package identity

Decision: The application persistence contract, packaged `schema.sql`, schema
installer ledger entry, and disposable qualification database must use the
same SHA-256 identity for consolidated schema version 5.

Status: Frozen.

Recommendation: Bind the application constant to the checksum-verified schema
identity, prove that equality in the native suite, and have Script 05 compare
the staged application identity, packaged schema, and installed ledger before
embedding or publication. Fail immediately with an explicit contract reason
when any identity differs.

Reason/Evidence: The first EmceeDanko publication reached PostgreSQL only after
embedding all corpus-v3 candidates, then failed because the application still
expected an older schema-v5 hash while the installer correctly recorded the
current packaged schema hash. The corrected boundary passes all 486 native
tests and a real disposable PostgreSQL 16/pgvector verification as
`rag_ingest`. Retrieval behavior, corpus content, schema structure, and the
frontier acceptance metrics are unchanged.

### V13-74 — Exact corpus-v3 relationship inventory semantics

Decision: Qualify stored relationship records and distinct document
relationship pairs as separate corpus-v3 inventory identities.

Status: Frozen as a correction to the existing V13-70 corpus-v3 contract.

Recommendation: Require exactly 240 active relationship records and exactly 90
distinct `(source_document_id, target_identity)` pairs. Query, report, and test
both values independently before starting the temporary Retrieval API or the
60-question frontier gate.

Reason/Evidence: The accepted corpus-v3 promotion record contains 240 stored
relationship rows representing 90 distinct pairs. Script 05 initially labeled
`count(*)` as pair count and compared 240 to 90 after a correct ingestion. The
correction changes only the qualification metric definition; it does not alter
corpus bytes, ingestion, retrieval, relationships, application behavior, or an
accepted target installation.

### V13-75 — Reversible attended v1.3 deployment boundary

Decision: Perform EmceeDanko human UI validation from a package-local v1.3
runtime and a dedicated durable PostgreSQL 16 data cluster without overwriting
the accepted v1.2 installation, its database files, or its rollback tree.

Status: Frozen.

Recommendation: Script 06 must revalidate the exact Script 01 archive, staged
candidate, corpus-v3 input, and checksum-bound Script 05 evidence before target
mutation. Build and validate the dedicated cluster on private port `65438`
while v1.2 remains ready. Because the frozen application requires database
`rag_catalog` and roles `rag_owner`, `rag_ingest`, and `rag_retrieval`, isolate
the whole cluster rather than renaming those objects. Only at the immediate
launch boundary stop the v1.2 UI, Retrieval API, and host PostgreSQL cluster;
then start the dedicated v1.3 cluster on `5432`, the package-local API on
`8384`, and the distinct UI container on `3384`. Install or enable no v1.3
systemd unit. Keep all autostart disabled, preserve the durable v1.3 cluster on
rollback, and automatically stop v1.3 and restore the untouched v1.2 cluster,
API, and UI after any failed launch. Human acceptance and rollback must remain
explicit Script 06 actions; org-lab packaging remains a separate later action.

Reason/Evidence: The exact v1.3 configuration validator rejects alternate
database and role names, while sharing the accepted host cluster would weaken
the database-isolation guarantee. Whole-cluster isolation preserves the frozen
application and both durable database trees. Executable Script 06 regressions
cover exact local evidence revalidation, fresh build cleanup, model preflight
without mutation, partial-state rejection and preservation, unrelated-PID
protection, unsafe-runtime-path rejection and preservation,
schema/catalog/manifest validation, failed launch with automatic restoration,
restoration-failure reporting, durable reuse, attended launch, human
acceptance, explicit rollback, remote failure propagation, signal cleanup,
single-result output, and unchanged v1.2 and candidate boundaries without
contacting EmceeDanko.
