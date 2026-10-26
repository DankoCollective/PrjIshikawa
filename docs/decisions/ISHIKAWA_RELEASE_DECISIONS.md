# Ishikawa Release Decisions

## Purpose

Record the frozen promotion of Ishikawa v1.3 from its Phase 28 development
workspace into a first-class repository, the EmceeDanko deployment journey,
and the final org-lab carry posture.

## Current Status

Items V13-60 through V13-78 are frozen through the operator-approved release,
qualified EmceeDanko deployment, rollback-waived integrated proof, and human
UI acceptance. On 2026-10-26 the operator froze V13-79 through V13-81 and
V13-83 through V13-89 for the final org-lab carry. These decisions select a
v1.3.1 security/runtime correction, patched Node 24 and Next.js 16 dependency
lines, production Next.js operation, a canonical least-privilege target
layout, demo PostgreSQL without backup/restore proof, portable model
configuration, protected in-lab black-corpus catalog/manifest creation, a
minimal carry set, exact-byte requalification, and inventory-driven native
prerequisites. V13-82 remains open only to confirm the minimal AMD64 Docker
image archive handoff. The post-freeze consistency review also found that
V13-83's new dedicated service identity conflicts with the previously accepted
Tech `%h/Documents/Ishikawa` and user-unit posture. The operator must confirm
that replacement or amend V13-83 before implementation. Exact fixed dependency
pins and target inventory values are implementation evidence, not additional
architecture decisions unless they conflict with a frozen posture. No
black-corpus access, target contact, service or database mutation, credential
handling, or package promotion is authorized by these planning decisions
alone.

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

### V13-76 — Explicit waiver of the v1.2 rollback guarantee

Decision: Script 06 may expose a separately named, explicit operator flag that
launches the already-qualified v1.3 candidate without
requiring v1.2 model routes, its PostgreSQL retrieval password, real v1.2
readiness, or automatic v1.2 restoration after a failed switchover.

Status: Frozen by operator direction on 2026-10-25.

Recommendation: Add `--waive-v1-2-rollback` only to Script 06 `--run`, retain
the current reversible behavior as the default, continue preserving the v1.2
installation, database files, and rollback tree on disk, and require only the
v1.3 Gemma/Nomic forwards on EmceeDanko loopback ports `18000` and `18001` for
the waived run. The flag must skip the v1.2 password prompt and readiness gate,
stop any present v1.2 UI, API, and host PostgreSQL processes only at the
immediate switchover, and start the same isolated corpus-v3 v1.3 runtime on
`3384`, `8384`, and `5432`. If launch fails after switchover, Script 06 must
stop v1.3, preserve both database trees and installations, leave v1.2 stopped,
and report that automatic recovery was deliberately waived. It must not delete,
overwrite, promote, install a service, enable autostart, or package for org-lab.

Reason/Evidence: The exact v1.3 model probes pass through `18000`/`18001`, but
the frozen v1.2 recovery proof additionally depends on its configured
`8000`/`8001` routes and remembered database password. The operator stated
that proving v1.3 with corpus v3 is now more important than retaining a ready
v1.2 rollback and directed that v1.2 preservation must not gate v1.3
installation, configuration, or testing. Keeping the existing default avoids
silently weakening V13-75, while an explicit flag makes the reduced recovery
posture unmistakable and replay-safe. The implementation changes
`deployment/scripts/06_attended-v1.3-on-emceedanko.sh`, its executable target
and wrapper regressions under `deployment/tests/`, and the Script 06 procedure
in `PROJECT_RUNBOOK.md`; target-side execution remains package-local and the
transferred orchestrator remains temporary. Alternatives are to retain the
current four-forward/password-dependent rollback guarantee, or destructively
retire v1.2 before v1.3 acceptance; the latter is not recommended because it
provides no benefit to the v1.3 proof. Executable regressions prove the default
reversible path remains intact, inactive v1.2 does not gate the waiver, no
v1.2 password is requested or readiness contact made, a failed waived launch
stops v1.3 without attempting v1.2 restoration, the durable v1.3 database can
be reused for an exact retry, and explicit later rollback remains conditional
on restoring the v1.2 dependencies.

### V13-77 — Explicit attended web identity and rollback recreation proof

Decision: Keep the exact staged v1.3 source private and unchanged, run only
the attended v1.3 web process as the numeric UID and primary GID of the
deployment account with `HOME=/tmp`, and keep generated `.next` state in the
bounded disposable tmpfs. When automatic v1.2 rollback is promised, Script 06
must also prove before any durable v1.3 database work or switchover that a
separately named disposable v1.2 UI can be freshly created from the preserved
launcher, exact image, and source tree on temporary port `3394`, can serve its
liveness, readiness, home, and static-asset surfaces, and can be completely
removed. The explicit V13-76 waiver skips only the v1.2 recreation proof.

Status: Frozen by operator direction on 2026-10-25.

Recommendation: Do not chmod, chown, copy over, or otherwise normalize the
qualified candidate. Preserve its exact file modes and read-only bind mounts,
retain `no-new-privileges` and `--cap-drop ALL`, and supply the deployment
account identity only to the direct v1.3 Next.js path. Leave the accepted v1.2
launcher unchanged. Treat a failed disposable v1.2 recreation as a default-
path rollback blocker while the currently running v1.2 remains untouched;
the operator may correct that old runtime or explicitly select V13-76.

Reason/Evidence: The failing EmceeDanko pre-switchover container reached
Next.js readiness and then received `EACCES` opening
`/opt/nextjs/next.config.mjs`. The staged file was mode `0600`, owned by
`1000:1000`; the accepted image declared no `USER`. Under the exact
`no-new-privileges` and capability-drop boundary, the image-default identity
could not import the read-only bind-mounted file, while the same container
with `--user 1000:1000 --env HOME=/tmp` imported it successfully. This proves
an identity mismatch rather than npm, Next.js, or candidate corruption. Full
target lifecycle regressions enforce the v1.3 identity, unchanged v1.2 launch
arguments, v1.2 recreation success and failure cleanup, waiver non-contact,
pre-switchover preservation, automatic restoration, acceptance, rollback,
candidate immutability, and one standalone result contract.

### V13-78 — Integrated v1.3 proof before rollback-waived switchover

Decision: With the explicit V13-76 waiver, do not modify, refresh, requalify,
or test v1.2. Before Script 06 issues any v1.2 stop command, it must run the
durable corpus-v3 database on private port `65438`, the package-local v1.3
Retrieval API on `8384`, and the exact v1.3 UI container on `3384`, and prove
the integrated database, corpus inventory, Gemma, Nomic, API, proxy, home, and
static-asset readiness chain. Only after that proof passes may Script 06 stop
any present v1.2 UI, API, and host PostgreSQL runtime. Because the frozen final
runtime requires PostgreSQL port `5432`, Script 06 must then stop only the
proven v1.3 processes, validate the configuration transition from `65438` to
`5432`, and relaunch the same durable v1.3 runtime on `5432`/`8384`/`3384` for
human validation. A later v1.3 failure does not require v1.2 restoration.

Status: Frozen by operator direction on 2026-10-25.

Recommendation: Preserve v1.2 files and database temporarily as historical
recovery material, but do not make them an acceptance dependency and do not
run the default-path disposable v1.2 recreation proof under the waiver. Keep
v1.3 autostart disabled, retain the v1.3-only `.next` tmpfs and deployment-user
identity, and keep org-lab packaging blocked until human UI acceptance.

Reason/Evidence: Component-level database/model checks plus a standalone UI
proof did not demonstrate the complete v1.3 request path before v1.2 was
stopped. The revised executable lifecycle starts the complete v1.3 stack while
leaving v1.2 untouched, verifies API and UI readiness on their final ports,
checks that readiness again across the v1.2 stop boundary, and makes the
unavoidable PostgreSQL port transition explicit. A forced pre-switchover API
failure proves cleanup of v1.3 private state while the active v1.2 UI, API, and
PostgreSQL runtime remain unchanged. The complete regression matrix also
proves waived retry, post-switchover failure cleanup without v1.2 restoration,
final launch, acceptance, explicit conditional rollback, candidate
immutability, and the standalone result contract.

### V13-79 — Patch-release identity for the final carry

Decision: Publish the security and production-runtime correction as Ishikawa
v1.3.1 and preserve the accepted v1.3 application identity and evidence.

Status: Frozen by operator direction on 2026-10-26.

Recommendation: Use a new patch identity for every changed application,
dependency, image, or production-runtime byte and retain v1.3 as the historical
EmceeDanko acceptance baseline.

Reason/Evidence: The accepted v1.3 archive and attended runtime are
checksum-bound. Security dependency updates and replacing `next dev` with a
production runtime change executed bytes and must not silently replace that
accepted identity.

### V13-80 — Patched and pinned dependency lines

Decision: Keep the final runtime on supported Node 24 and Next.js 16 lines,
resolve currently fixed patch versions through package-time advisory review,
and pin the exact Node.js, Next.js, React, React DOM, package-manager,
operating-system base, and transitive dependency set before assembly.

Status: Frozen by operator direction on 2026-10-26.

Recommendation: Use the newest reviewed fixed patch set within the frozen
Node 24 and Next.js 16 lines, retain exact lock data, and permit no floating
tag or target-side dependency download.

Reason/Evidence: The accepted image contains Node.js `24.22.0`, Next.js
`16.4.1`, React `19.2.0`, and React DOM `19.2.0`. The registered Node and React
security sources require a fixed reviewed set before promotion. Exact resolved
pins are implementation evidence under this decision; another operator choice
is required only if qualification forces a change away from Node 24 or Next.js
16.

### V13-81 — Production Next.js runtime

Decision: Use `next build` plus `next start`, read-only runtime source, and
checksum-bound production build output created by the exact reviewed image.

Status: Frozen by operator direction on 2026-10-26.

Recommendation: Remove `next dev` from the permanent deployment and qualify
build, start, readiness, proxies, static assets, restart, stop, cleanup, and
bounded writable state against the final package.

Reason/Evidence: The attended EmceeDanko proof intentionally used a
development server and disposable `.next` state. That proves the application
experience but not a permanent production-mode build/start lifecycle.

### V13-82 — Minimal AMD64 image handoff

Decision: Decide the minimum exact web-container image file and identity record
that Tech needs to load and run the frozen production web runtime in org-lab
without rebuilding it or downloading a substitute.

Status: Open.

Recommendation: Carry one Linux AMD64 Docker image archive containing the
already-built production Ishikawa web app, its SHA-256 and image identity, and
the Dockerfile/lockfile that produced it. Tech verifies the archive and runs
`docker load`; Tech does not use a registry, rebuild the image, or download
dependencies. Do not build or carry ARM64 for this deployment.

Reason/Evidence: A Docker tag is only a name. The tested image bytes must be
exported to a file to travel to Tech. SBOM, license, and advisory evidence are
already required by V13-80 and the package checklist and do not create a
second image design.

### V13-83 — Canonical least-privilege target layout

Decision: Use one stable product layout with function-based target names, one
dedicated least-privilege service identity, explicit loopback listeners, the
minimum service set, and boot-disabled first proof. Resolve exact target values
through package defaults and read-only preflight before mutation.

Status: Frozen by operator direction on 2026-10-26.

Recommendation: Keep application, configuration, state, credential injection,
and logging responsibilities in their canonical final locations; install no
development, candidate, script-numbered, test-host, or repository-named target
objects.

Reason/Evidence: The EmceeDanko attended layout is a package-local validation
arrangement, and the historical packaged unit assumes a home-directory path.
Neither is an appropriate permanent target layout. Exact ports and paths are
preflight values unless inventory reveals a conflict with this posture.

### V13-84 — Demo PostgreSQL without backup/restore proof

Decision: Use PostgreSQL 16 with pgvector, schema v5, and the qualified
least-privilege database roles for the demo. Backup and restore proof are
explicitly outside demo acceptance scope.

Status: Frozen by operator direction on 2026-10-26.

Recommendation: Install the one canonical `schema.sql`, keep database state
outside the carry package, and prove clean creation, ingestion, retrieval,
restart, and bounded removal without adding a backup/restore exercise.

Reason/Evidence: Schema v5 and the database roles passed EmceeDanko
qualification. The operator classified the org-lab installation as a demo and
explicitly waived backup/restore proof. Capacity, ownership, and collision
inventory remain required preflight facts.

### V13-85 — Portable model and credential configuration

Decision: Supply Gemma and Nomic endpoint and credential values only through
approved runtime configuration and secret injection, with explicit failure and
log-redaction behavior and no test-host values embedded in package bytes.

Status: Frozen by operator direction on 2026-10-26.

Recommendation: Keep endpoint, network, and credential values external to the
package and reject missing or invalid values without exposing them in output,
logs, commands, or retained evidence.

Reason/Evidence: EmceeDanko used operator-created forwards and hidden inputs.
Those were validation mechanics and must not become Tech configuration or
package content.

### V13-86 — Protected black-corpus materialization

Decision: Keep the agent and portable package unable to access `black_corpus`.
Create its document catalog and ingestion manifest inside org-lab through an
authorized content-side operation and derive every corpus metric from those
exact inputs and the resulting PostgreSQL state.

Status: Frozen by operator direction on 2026-10-26.

Recommendation: Carry only content-blind catalog/manifest creation and
validation tooling plus empty templates. Keep the generated catalog, manifest,
source documents, content-bearing reports, chunks, vectors, prompts, and
responses inside the protected environment. Do not reuse corpus-v3 counts.

Reason/Evidence: The operator stated that the agent will not have black-corpus
access and that catalogs and manifests must be created for that corpus. The
synthetic corpus proves the application but cannot define organizational
document, page, chunk, relationship, embedding, or acceptance counts.

### V13-87 — Minimal canonical carry set

Decision: Carry the smallest authoritative final file set needed to install,
configure, run, verify, and remove Ishikawa from a clean supported baseline,
plus only inventory-required offline prerequisites.

Status: Frozen by operator direction on 2026-10-26.

Recommendation: Include one final application artifact, one final AMD64 web
image archive after V13-82 is resolved, one consolidated deployment entrypoint,
one verifier, one operator command sheet, and their required identity, SBOM,
license, advisory, and checksum records. Keep corpus material separate.

Reason/Evidence: The deployable-package standard forbids repair chains,
superseded files, duplicated payloads, unclassified content, and repository
history in the normal fresh-install lane.

### V13-88 — Exact-byte requalification and stable promotion

Decision: Repeat every affected local, clean-install, installed-layout,
EmceeDanko, production-runtime, failure, cleanup, and human gate against the
exact final bytes before atomic stable-handoff promotion.

Status: Frozen by operator direction on 2026-10-26.

Recommendation: Treat prior v1.3 evidence as the behavioral baseline, not as
proof for changed v1.3.1 bytes. Publish only after final package and image
checks pass and preserve displaced handoff bytes under an explicit superseded
identity.

Reason/Evidence: The security refresh, production web lifecycle, image bytes,
and final deployment entrypoint are new. Syntax checks or the old attended
runtime cannot establish their install, run, failure, cleanup, or human
behavior.

### V13-89 — Inventory-driven native prerequisites

Decision: Inventory Tech's PostgreSQL, pgvector, Python, PyYAML, psycopg, and
other native prerequisites; reuse exact compatible installed packages or carry
a separately checksummed complete offline prerequisite set.

Status: Frozen by operator direction on 2026-10-26.

Recommendation: Run the approved read-only prerequisite inventory before bulk
capture. If compatible packages are absent, stage the exact Linux AMD64
packages and transitive dependencies locally, review them, and install only
from the verified carried set.

Reason/Evidence: The application archive intentionally excludes
operating-system packages, and EmceeDanko already supplied its prerequisites.
That does not prove Tech has compatible bytes or authorize live target package
downloads.
