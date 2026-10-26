# Ishikawa Org-Lab Carry Readiness Checklist

## File contract

- Role: durable review and completion checklist for the final Ishikawa carry
  package
- Prepared: 2026-10-25 America/Los_Angeles
- Morning review target: 2026-10-26
- Earliest carry target: afternoon or evening 2026-10-26
- Current disposition: **NOT CARRY-READY**
- Decision authority: `docs/decisions/ISHIKAWA_RELEASE_DECISIONS.md`
- Governing standards: `AGENT_OPERATION.md`, `CODING_STANDARD.md`, and
  `LAB_RUN_PATH_STANDARD.md`

This file is a readiness ledger and structured decision record. On 2026-10-26
the operator froze `CARRY-D01`, `CARRY-D02`, `CARRY-D03`, and `CARRY-D05`
through `CARRY-D11`, with the demo and black-corpus qualifications recorded in
those items. `CARRY-D04` remains open. The matching authoritative decisions
are in `docs/decisions/ISHIKAWA_RELEASE_DECISIONS.md`.

## Current review boundary

Freezing these decisions authorizes their bounded local implementation after
`CARRY-D04` is resolved. It does not itself authorize target contact,
black-corpus access, service or database mutation, credential handling, or
package promotion. Leave the accepted attended v1.3 runtime on EmceeDanko
unchanged until an operator-facing qualification action is separately
authorized.

The desired carry time is a target, not a reason to waive a mandatory gate. If
any blocking item below remains incomplete, the package does not travel.

## How to check an item

- `[x]` means the stated evidence was inspected and is named beside the item.
- `[ ]` means incomplete, even if work has begun.
- Every future check must add the evidence path or artifact SHA-256, reviewer,
  and review time. A conversation, terminal scrollback, tag, or filename alone
  is not evidence.
- A section passes only when every item marked **MUST** is checked.
- An exception requires a numbered, frozen decision. Do not silently mark an
  exception as passed.
- Raw reports, credentials, private documents, prompts, responses, chunks, and
  vectors remain outside Git and outside the carry package.

## Proven starting point

- [x] **BASE-01 — EmceeDanko human acceptance.** The operator accepted the
  attended v1.3 UI. Evidence: ignored local acceptance report
  `local/reports/emceedanko-v1.3-attended-ui/attended_v1_3_accept_20261026T024200Z_MPsWtM.txt`,
  SHA-256
  `b53c4d2cebad76bfdb98d68e25303a3addc79e610c84cfb6e1d3be0946977f6a`.
- [x] **BASE-02 — Exact attended launch.** The accepted runtime passed the
  database, corpus-v3, model, Retrieval API, UI, proxy, home, and static-asset
  gates on ports `5432`, `8384`, and `3384`. Evidence: ignored local launch
  report
  `local/reports/emceedanko-v1.3-attended-ui/attended_v1_3_run_20261026T023311Z_K0R2ZB.txt`,
  SHA-256
  `56c493cfdf5124eea86d7c99d7152129fbbdbf9617f7fa1c1a1dd4bf72a6da6e`.
- [x] **BASE-03 — Accepted application identity.** The application archive is
  `ishikawa-v1.3.tar.gz`, SHA-256
  `53da57b745fb4c8be6335896d05bdb6f63f2de3494862b99acca09e156863f3c`.
  It is 272,499 bytes with 145 archive entries. This is an accepted baseline,
  not yet a final org-lab deployment package.
- [x] **BASE-04 — Release quality baseline.** Script 05 recorded 486 native
  tests passing, 30 synthetic documents, 150 pages, 60/60 frontier cases, and
  complete cleanup. Evidence:
  `deployment/evidence/ISHIKAWA_V1_3_EMCEEDANKO_QUALIFICATION.md`.
- [x] **BASE-05 — Data boundary.** The accepted application archive contains
  no source corpus, prebuilt retrieval index, credentials, or model weights.
  Corpus-v3 remains a qualification fixture and is not an org-lab input.
- [x] **BASE-06 — Startup boundary.** The accepted attended deployment did not
  install or enable a v1.3 boot service. Boot autostart remains disabled.
- [x] **BASE-07 — Preliminary archive hygiene.** A fresh extraction found no
  symlinks and no `.pyc`, cache, editor-backup, or log files. One historical
  origin-workspace literal remains inside the shipped verifier's rejection
  rule; `NAME-04` keeps that finding open.

## Blocking findings at preparation time

These findings prevent a carry-ready declaration today:

- **BLOCK-01 — Runtime security refresh.** The accepted image contains Node.js
  `24.22.0`, while `24.22.1` is a later Node 24 security release. The exact
  Node, Next.js, React, React DOM, operating-system, and transitive dependency
  set requires a fresh affectedness review and action-required dispositions.
- **BLOCK-02 — React affectedness.** The application pins React `19.2.0`, and
  the current React Server Components advisory lists that line as affected and
  `19.2.9` as a fixed version for the named RSC packages. The final dependency
  graph must prove applicability and use a fixed set; assumption is not an
  acceptable disposition.
- **BLOCK-03 — Development web server.** EmceeDanko acceptance used `next dev`.
  The final deployment needs a separately qualified production-mode
  `next build` and `next start` design. The published Next.js development-server
  advisory is an additional reason not to make `next dev` permanent.
- **BLOCK-04 — Runtime-image reproducibility.** The accepted runtime image has
  no retained authoritative Dockerfile, exact base-image identity, dedicated
  lockfile, complete SBOM/license record, build report, or standalone
  checksum-bound AMD64 export.
- **BLOCK-05 — Stale handoff pointer.** `local/artifacts/ishikawa-current/`
  currently contains a superseded frontier archive with SHA-256
  `89358b285598385b6da5f53985a9004ef287361d919c74f44e87c05da9896436`.
  It must not be promoted or carried.
- **BLOCK-06 — Package terminology.** The accepted application archive's
  verifier contains the literal historical origin path name
  `phase-28-apisachi-tokuli` as a rejection pattern. Even though it is guard
  logic rather than an installed object name, its disposition must be explicit
  under the requested no-jargon package standard.
- **BLOCK-07 — Target facts.** Org-lab architecture, capacity, existing ports,
  PostgreSQL/pgvector posture, container runtime, service-account posture,
  model routes, credential authority, and corpus source have not yet been
  accepted through the controlled inventory path.
- **BLOCK-08 — Final bundle absent.** No final installer/orchestrator, runtime
  image archive, SBOM, advisory disposition, license inventory, carry manifest,
  removal path, or stable carry handoff has been built and qualified.
- **BLOCK-09 — Native prerequisites unresolved.** The accepted application
  assumes approved host Python/native dependencies, including PyYAML and
  psycopg. Org-lab has not yet proved exact compatible packages are present,
  and no reviewed offline prerequisite set has been selected or captured.

## Carry decisions

The following items use the required decision-list shape. Ten are frozen by
operator direction on 2026-10-26. `CARRY-D04` is the sole open package-design
item. A post-freeze consistency review also found that `CARRY-D05`, as written,
would replace the previously accepted Tech home-directory/user-unit design;
that conflict requires operator reconciliation before implementation. Exact
target facts remain preflight inputs rather than new architecture decisions
unless inventory conflicts with a frozen posture.

### CARRY-D01 — Release identity after security/runtime changes

Decision: Publish the security and production-runtime correction as Ishikawa
v1.3.1 and preserve the accepted v1.3 identity and evidence.

Status: Frozen by operator direction on 2026-10-26.

Recommendation: Publish the corrected, requalified result as Ishikawa v1.3.1
and preserve the accepted v1.3 application and evidence as its historical
baseline.

Reason/Evidence: Dependency and permanent-runtime changes alter checksum-bound
release bytes and the executed web posture. A patch identity prevents silent
replacement of the already accepted v1.3 artifact.

### CARRY-D02 — Final dependency set

Decision: Keep the final runtime on the supported Node 24 and Next.js 16 lines,
resolve currently fixed patch versions through the package-time advisory
review, and pin the exact Node.js, Next.js, React, React DOM, package-manager,
operating-system base, and transitive dependency set before assembly.

Status: Frozen by operator direction on 2026-10-26.

Recommendation: Remain on the supported Node 24 and Next.js 16 lines, select
currently fixed patch versions after a fresh advisory review, pin every direct
and transitive byte through a retained lockfile, and permit no floating tag or
target-side download.

Reason/Evidence: The accepted image uses Node.js `24.22.0`, Next.js `16.4.1`,
React `19.2.0`, and React DOM `19.2.0`. Current Node and React security sources
require action before promotion, and the present image is not reproducible.
Exact resolved pins are implementation evidence under this frozen rule; they
require another operator decision only if qualification forces a change away
from the frozen Node 24 or Next.js 16 lines.

### CARRY-D03 — Permanent web runtime

Decision: Use `next build` plus `next start`, read-only runtime source, and
checksum-bound production build output created by the exact reviewed image.

Status: Frozen by operator direction on 2026-10-26.

Recommendation: Use `next build` plus `next start`, keep application source
read-only at runtime, and package or persist only checksum-bound build output
created by the exact reviewed image. Do not use `next dev` in the permanent
deployment.

Reason/Evidence: The attended proof intentionally used a development runtime
and disposable `.next` tmpfs. Production build-output persistence and restart
behavior have not been qualified.

### CARRY-D04 — Carryable AMD64 web image

Decision: Decide the minimum exact web-container image file and identity record
that Tech needs in order to load and run the frozen production web runtime in
org-lab without rebuilding it or downloading a substitute.

Status: Open.

Recommendation: Carry one Linux AMD64 Docker image archive containing the
already-built production Ishikawa web app, its SHA-256 and image identity, and
the Dockerfile/lockfile that produced it. Tech verifies the archive and runs
`docker load`; Tech does not use a registry, rebuild the image, or download
dependencies. Do not build or carry ARM64 for this deployment.

Reason/Evidence: This is the practical purpose of item 4. A Docker tag is only
a name and cannot be carried by itself. The actual image archive is required
so the tested bytes can be copied to Tech and loaded offline. The broader SBOM,
license, and advisory records are already mandatory under `SEC-01` through
`SEC-04`; they do not require a second image design.

### CARRY-D05 — Canonical target layout and service posture

Decision: Use one stable product layout with function-based target names, one
dedicated least-privilege service identity, explicit loopback listeners, the
minimum service set, and boot-disabled first proof. Resolve exact target values
through the package defaults and preflight inventory before mutation.

Status: Frozen by operator direction on 2026-10-26.

Recommendation: Use one stable product layout with function-based names, one
dedicated least-privilege service identity, explicit loopback listeners, and
the minimum service set. Keep autostart disabled for first proof and decide
enablement only after the installed runtime is accepted.

Reason/Evidence: The EmceeDanko attended layout is package-local and the
packaged historical unit assumes a home-directory installation. Neither is an
approved permanent org-lab topology.

### CARRY-D06 — PostgreSQL ownership and recovery

Decision: Use PostgreSQL 16 with pgvector, schema v5, and the qualified
least-privilege database roles for a demo deployment. Backup and restore proof
are explicitly outside this demo's acceptance scope.

Status: Frozen by operator direction on 2026-10-26.

Recommendation: Preserve schema-v5 names and least-privilege roles, install
from the one canonical `schema.sql`, and keep the corpus database separate
from the package. Prove clean creation, ingestion, retrieval, restart, and
bounded removal; do not add a backup/restore exercise to this demo.

Reason/Evidence: Schema v5 and the application roles are qualified. The
operator explicitly classified this as a demo and waived backup/restore proof
on 2026-10-26. Target cluster ownership, capacity, and collision checks remain
read-only preflight facts, not a recovery-design gate.

### CARRY-D07 — Model routes and credential consumption

Decision: Supply Gemma and Nomic endpoint and credential values only through
approved runtime configuration and secret injection, with explicit failure and
log-redaction behavior and no test-host values embedded in package bytes.

Status: Frozen by operator direction on 2026-10-26.

Recommendation: Supply endpoint names and credentials only through approved
runtime configuration and secret injection, with no EmceeDanko port-forward,
account, home-path, or credential value embedded in package bytes.

Reason/Evidence: The attended proof used operator-created local forwards and
hidden inputs. Those are validation mechanics, not a portable service design.

### CARRY-D08 — Organizational corpus intake

Decision: Keep the agent and portable carry package unable to access
`black_corpus`. Create the black-corpus document catalog and ingestion manifest
inside org-lab through an authorized content-side operation, and derive every
corpus metric from those exact inputs and the resulting PostgreSQL state.

Status: Frozen by operator direction on 2026-10-26.

Recommendation: Carry only content-blind catalog/manifest creation and
validation tooling plus empty templates. An authorized org-lab operator runs
that tooling against `black_corpus`; the resulting catalog and manifest stay
inside the protected environment. Derive document, page, chunk, relationship,
embedding, and acceptance counts from that run and PostgreSQL. Do not reuse
corpus-v3 constants.

Reason/Evidence: Corpus v3 proves the application but contains synthetic data.
The operator stated on 2026-10-26 that the agent will not have black-corpus
access and that its catalogs and manifests must be created for that corpus.
Neither black-corpus content nor content-bearing evidence is authorized for
repository or carry-package access.

### CARRY-D09 — Final carry contents

Decision: Carry the smallest authoritative final file set needed to install,
configure, run, verify, and remove Ishikawa from a clean supported baseline,
plus only inventory-required offline prerequisites.

Status: Frozen by operator direction on 2026-10-26.

Recommendation: Carry one final application artifact, one final AMD64 runtime
image archive, one consolidated deployment entrypoint, one verifier, one
operator README/command sheet, and their identity, SBOM, license, advisory,
and checksum records. Add a separately controlled native-prerequisite bundle
only if `CARRY-D11` and target inventory prove it is needed. Keep corpus inputs
in their separately controlled lane.

Reason/Evidence: The coding standard forbids repair chains, superseded files,
unclassified content, duplicate payloads, and repository history in a fresh
deployment package.

### CARRY-D10 — Qualification, promotion, and supersession

Decision: Repeat every affected local, clean-install, installed-layout,
EmceeDanko, production-runtime, failure, cleanup, and human gate against the
exact final bytes before atomic stable-handoff promotion.

Status: Frozen by operator direction on 2026-10-26.

Recommendation: Repeat all affected first-party, package, installed-layout,
production-runtime, failure, cleanup, and human UI gates against the exact
final bytes; publish them atomically to a single stable carry handoff only
after every gate passes; preserve displaced bytes under an explicit
superseded identity.

Reason/Evidence: The v1.3 evidence proves the accepted v1.3 bytes and attended
development runtime. It cannot automatically qualify changed dependencies,
production build output, image bytes, installer behavior, or target topology.

### CARRY-D11 — Native prerequisite supply

Decision: Inventory the final target's PostgreSQL, pgvector, Python, PyYAML,
psycopg, and other native prerequisites; reuse exact compatible installed
packages or carry a separately checksummed complete offline prerequisite set.

Status: Frozen by operator direction on 2026-10-26.

Recommendation: Run the approved read-only prerequisite inventory first; reuse
only exact compatible target packages with recorded identity and advisory
disposition, and otherwise capture the complete exact AMD64 package and
transitive dependency set into a separately checksummed offline bundle before
installation.

Reason/Evidence: The application archive intentionally excludes
operating-system packages, and the accepted EmceeDanko host already supplied
them. That does not prove org-lab has compatible bytes or permit the target to
download replacements during deployment.

## Post-freeze discussion items

- **RECON-01 — Unfrozen image handoff.** `CARRY-D04`/V13-82 is the only
  unfrozen package-design decision. Its reduced scope is one already-built
  Linux AMD64 Ishikawa web image archive that Tech verifies and loads offline,
  plus the checksum and build identity needed to prove it is the tested image.
- **RECON-02 — Tech layout conflict.** `CARRY-D05`/V13-83 currently selects a
  dedicated service identity and new canonical layout. The existing accepted
  Tech contract instead uses `%h/Documents/Ishikawa`, packaged user units, and
  the installing operator account; Ishikawa creates no Linux user or group.
  Confirming the new service-account posture would require package, unit,
  permission, install, and removal changes. Amending D05 to the existing Tech
  contract is the smaller path.
- **RECON-03 — Implementation evidence, not new decisions.** Exact fixed patch
  versions under D02; exact Tech ports, capacity, and prerequisite versions;
  and the protected `black_corpus` source path are values resolved by local
  build evidence or operator-run preflight. They require a new decision only
  if they conflict with a frozen posture.
- **RECON-04 — Later autostart choice.** D05 keeps first proof boot-disabled.
  Whether to enable startup after Tech acceptance is deliberately deferred and
  does not block assembling or carrying the package.

## Mandatory package checklist

### 1. Release and evidence reconciliation

- [ ] **REL-01 — MUST.** Freeze every accepted `CARRY-Dxx` posture in the
  authoritative release decision list. Evidence: ___; reviewer/date: ___.
- [ ] **REL-02 — MUST.** Reconcile the release freeze, decision-list current
  status, repository sweep, runbook, runtime definition, and qualification
  receipt with the accepted UI state and selected release identity. Evidence:
  ___; reviewer/date: ___.
- [ ] **REL-03 — MUST.** Preserve a tracked, content-free human-acceptance
  receipt bound to the exact accepted launch and acceptance report hashes.
  Evidence: ___; reviewer/date: ___.
- [ ] **REL-04 — MUST.** State whether the accepted v1.3 artifact is retained,
  superseded, or reused; never silently overwrite its identity. Evidence: ___;
  reviewer/date: ___.

### 2. Small footprint and classified contents

- [ ] **SIZE-01 — MUST.** Produce a complete final file inventory with path,
  type, mode, byte size, purpose, installer consumer, and SHA-256. Every file
  has an install, configure, run, verify, recover, remove, license, advisory,
  or operator purpose. Evidence: ___; reviewer/date: ___.
- [ ] **SIZE-02 — MUST.** Carry no exploded duplicate of an included archive,
  no repeated container layers outside the selected image archive, and no
  duplicate source/config/schema copy without a documented consumer. Evidence:
  ___; reviewer/date: ___.
- [ ] **SIZE-03 — MUST.** Exclude loose `node_modules`, `.next`, virtual
  environments, caches, bytecode, logs, raw reports, editor files, temporary
  files, test output, source documents, vectors, database dumps, model weights,
  OS package caches, credentials, private keys, tokens, and environment files
  from the application archive and carry directory. The single final web image
  may contain only its exact pinned production runtime dependencies and
  checksum-bound production build output under D02 through D04. Evidence: ___;
  reviewer/date: ___.
- [ ] **SIZE-04 — MUST.** Include first-party tests only if the final verifier
  executes them from the installed layout; otherwise keep full regression
  sources outside the fresh-deployment payload. Evidence: ___; reviewer/date:
  ___.
- [ ] **SIZE-05 — MUST.** Record compressed bytes, uncompressed bytes, file
  count, container archive bytes, and total carry bytes. Explain every material
  increase over the 272,499-byte accepted application baseline. Evidence: ___;
  reviewer/date: ___.
- [ ] **SIZE-06 — MUST.** Extract to a clean directory and prove there are no
  sockets, devices, FIFOs, hard-link surprises, symlinks, absolute paths, `..`
  traversal, duplicate normalized paths, or files outside the single archive
  root. Evidence: ___; reviewer/date: ___.

### 3. Consolidated canonical final targets

- [ ] **PATH-01 — MUST.** Select one canonical application root, one
  configuration root, one state root, one credential-injection boundary, and
  one logging destination. No same-purpose alternate path is installed.
  Evidence: ___; reviewer/date: ___.
- [ ] **PATH-02 — MUST.** Use one canonical schema-v5 `schema.sql` for fresh
  creation. Historical migrations, repair SQL, probes, and mutation chains are
  excluded from the fresh-install lane. Evidence: ___; reviewer/date: ___.
- [ ] **PATH-03 — MUST.** Consolidate each coherent responsibility into its
  final authoritative file. Do not ship `new`, `old`, `final`, `fixed`,
  `candidate`, `copy`, numeric-repair, or backup variants beside a canonical
  target. Evidence: ___; reviewer/date: ___.
- [ ] **PATH-04 — MUST.** Materialize final patched source, configuration,
  build output, image, and schema before packaging. The installer does not
  replay development fixes to construct the intended baseline. Evidence: ___;
  reviewer/date: ___.
- [ ] **PATH-05 — MUST.** Keep upgrade or recovery deltas outside the clean
  baseline unless the operator explicitly selects a separately tested upgrade
  mode. Evidence: ___; reviewer/date: ___.
- [ ] **PATH-06 — MUST.** Make every manifest path archive-relative and every
  runtime path derive from the frozen canonical roots. No repository root,
  Windows drive, WSL mount, developer home, or test-host path is embedded.
  Evidence: ___; reviewer/date: ___.
- [ ] **PATH-07 — MUST.** Prove clean install, same-version replay, removal,
  interrupted install cleanup, and drift refusal against the exact packaged
  layout. Evidence: ___; reviewer/date: ___.

### 4. Portable product terminology

- [ ] **NAME-01 — MUST.** Installed directories, files, commands, systemd
  units/drop-ins, containers, database objects, policies, config keys,
  certificate labels, reports, and operator surfaces use only stable product
  and function names. Evidence: ___; reviewer/date: ___.
- [ ] **NAME-02 — MUST.** No deployed object name contains repository,
  workstream, phase, script number, agent, test-host, attended-run, candidate,
  or developer-account terminology. Evidence: ___; reviewer/date: ___.
- [ ] **NAME-03 — MUST.** Scan filenames, archive paths, text payloads,
  templates, comments, help, examples, and generated configuration for local
  roots and terms including `Prj`, `phase-`, `Script 0`, `Codex`, `agent`,
  `EmceeDanko`, and `DankoSurface`. Review findings; do not hide them through a
  broad allowlist. Evidence: ___; reviewer/date: ___.
- [ ] **NAME-04 — MUST.** Remove or explicitly disposition the current
  verifier's `phase-28-apisachi-tokuli` rejection literal. The preferred
  posture is to keep the forbidden-term scanner in the local pre-publication
  gate rather than carrying repository history merely to reject it. Evidence:
  ___; reviewer/date: ___.
- [ ] **NAME-05 — MUST.** Repository evidence may name scripts and test hosts
  for traceability, but those names are absent from the fresh-deployment
  payload and all installed objects. Evidence: ___; reviewer/date: ___.

### 5. Security, provenance, licenses, and secrets

- [ ] **SEC-01 — MUST.** Freeze exact dependency versions and produce a fresh
  complete dependency graph for Python, JavaScript, container base, and
  operating-system packages. Evidence: ___; reviewer/date: ___.
- [ ] **SEC-02 — MUST.** Capture authoritative advisory sources and record each
  finding as fixed, not affected with evidence, mitigated with evidence, or an
  explicitly frozen operator deferral. No unresolved action-required finding
  remains. Evidence: ___; reviewer/date: ___.
- [ ] **SEC-03 — MUST.** Resolve the Node.js `24.22.0` security-release gap and
  React `19.2.0` RSC affectedness before promotion. Evidence: ___;
  reviewer/date: ___.
- [ ] **SEC-04 — MUST.** Generate and review an SBOM and license inventory for
  the exact application and image bytes. Record any notice/source-offer
  obligations and include only the required deliverables. Evidence: ___;
  reviewer/date: ___.
- [ ] **SEC-05 — MUST.** Scan tracked source, staged bundle, extracted bundle,
  image configuration/history, and generated manifests for secrets, private
  paths, credentials, tokens, keys, protected content, and full environment
  values. Evidence contains only redacted findings and hashes. Evidence: ___;
  reviewer/date: ___.
- [ ] **SEC-06 — MUST.** Run with least privilege, read-only source/config
  where possible, `no-new-privileges`, dropped capabilities, bounded writable
  state, explicit network bindings, and no Docker socket or home-directory
  mount. Evidence: ___; reviewer/date: ___.
- [ ] **SEC-07 — MUST.** Credentials are absent from the carry package and are
  obtained only through the frozen target authority/injection path. Prove
  redaction, restart, missing-secret, invalid-secret, and rotation behavior.
  Evidence: ___; reviewer/date: ___.

Authoritative security sources queued for review are registered in
`Reference_Directory.md`; they do not themselves constitute an affectedness
disposition.

### 6. Reproducible artifacts and stable handoff

- [ ] **BUILD-01 — MUST.** Retain the Dockerfile, exact base-image digest,
  package manifests, exact lockfiles, build command, build environment,
  normalized archive rules, and source revision for every final artifact.
  Evidence: ___; reviewer/date: ___.
- [ ] **BUILD-02 — MUST.** Build the application package twice from a clean
  checkout and compare byte-for-byte identities, or document and eliminate
  every nondeterministic field before acceptance. Evidence: ___;
  reviewer/date: ___.
- [ ] **BUILD-03 — MUST.** Build/export the final Linux AMD64 image, record its
  image ID/config digest/platform, and verify the standalone archive after a
  clean load. Evidence: ___; reviewer/date: ___.
- [ ] **BUILD-04 — MUST.** Verify every sidecar against the artifact from the
  final directory and independently recompute every SHA-256. Evidence: ___;
  reviewer/date: ___.
- [ ] **BUILD-05 — MUST.** Publish atomically to one stable
  `ishikawa-deployment-current/` handoff only after all gates pass. Do not use
  the stale `ishikawa-current/` frontier contents and do not direct the
  operator to a dated candidate. Evidence: ___; reviewer/date: ___.
- [ ] **BUILD-06 — MUST.** Preserve replaced current bytes under an explicit
  superseded identity when retention is required, then prove that the stable
  pointer contains only the newly accepted set. Evidence: ___; reviewer/date:
  ___.

### 7. Executable qualification

- [ ] **TEST-01 — MUST.** Run the complete native and web suites against the
  final source and dependency set. Record exact counts without treating old
  counts as proof for changed bytes. Evidence: ___; reviewer/date: ___.
- [ ] **TEST-02 — MUST.** Run package verification, clean extraction,
  fresh-install, installed-layout parity, canonical schema installation,
  configuration validation, and checksum verification against exact final
  bytes. Evidence: ___; reviewer/date: ___.
- [ ] **TEST-03 — MUST.** Prove the final production web workflow end to end:
  build, start, liveness, readiness, home, static assets, Retrieval API proxy,
  restart, stop, cleanup, and bounded writable-state behavior. Evidence: ___;
  reviewer/date: ___.
- [ ] **TEST-04 — MUST.** Exercise clean install, same-version replay,
  interrupted install, failure before and after each mutation boundary,
  cleanup, drift refusal, removal, and the frozen recovery/rollback posture.
  Evidence: ___; reviewer/date: ___.
- [ ] **TEST-05 — MUST.** Repeat every EmceeDanko gate affected by changed
  application, dependency, image, runtime, installer, or service bytes. Obtain
  human UI acceptance of the exact final candidate. Evidence: ___;
  reviewer/date: ___.
- [ ] **TEST-06 — MUST.** Prove all long operator commands expose milestones,
  bounded heartbeats, prompt warnings, one terminal result, report path,
  cleanup state, signal propagation, and actionable failure detail. Evidence:
  ___; reviewer/date: ___.
- [ ] **TEST-07 — MUST.** Perform a fresh package jargon/path scan and a fresh
  secret/content scan after all other edits, not before them. Evidence: ___;
  reviewer/date: ___.

### 8. Org-lab inventory and corpus boundary

- [ ] **LAB-01 — MUST.** Approve an operator-run, report-producing read-only
  inventory before any target mutation. Do not substitute ad hoc agent SSH.
  Evidence: ___; reviewer/date: ___.
- [ ] **LAB-02 — MUST.** Verify target hostname/role, Linux/AMD64 identity,
  capacity, container runtime, PostgreSQL 16, pgvector, native dependencies,
  current services, canonical paths, users/groups, permissions, listeners,
  firewall posture, and boot state. Evidence: ___; reviewer/date: ___.
- [ ] **LAB-03 — MUST.** Resolve UI, Retrieval API, PostgreSQL, Gemma, and Nomic
  ports from target facts. Do not carry EmceeDanko's port-forward assumptions
  as org-lab constants. Evidence: ___; reviewer/date: ___.
- [ ] **LAB-04 — MUST.** Verify the final image archive and application archive
  on the target before load/extract and install only from those verified local
  bytes. The target performs no replacement download. Evidence: ___;
  reviewer/date: ___.
- [ ] **LAB-05 — MUST.** Approve the organizational document catalog and
  ingestion manifest separately; checksum them; validate source-document
  containment; and derive document/page/chunk/relationship/embedding counts
  from the exact run. Evidence: ___; reviewer/date: ___.
- [ ] **LAB-06 — MUST.** Keep source documents, prompts, responses, chunks,
  vectors, credentials, and database contents out of the application carry
  package and tracked evidence. Evidence: ___; reviewer/date: ___.
- [ ] **LAB-07 — MUST.** Define first-proof non-actions, rollback/recovery,
  autostart, firewall, backup, and cleanup posture before mutation. Evidence:
  ___; reviewer/date: ___.

### 9. Final carry set and authorization

- [ ] **FINAL-01 — MUST.** The final directory contains only the frozen carry
  set: application artifact, runtime image archive, deployment entrypoint,
  verifier, operator documentation, identity/receipt records, SBOM/license and
  advisory records, one complete SHA-256 manifest, and any separately frozen
  prerequisite artifact required by target inventory. Evidence: ___;
  reviewer/date: ___.
- [ ] **FINAL-02 — MUST.** A clean machine or clean isolated harness verifies
  the carry directory without relying on repository-relative files, network
  downloads, unrecorded tools, or developer state. Evidence: ___;
  reviewer/date: ___.
- [ ] **FINAL-03 — MUST.** Record exact filename, purpose, byte size, and
  SHA-256 for every carried file, plus total bytes and destination-media
  capacity. Evidence: ___; reviewer/date: ___.
- [ ] **FINAL-04 — MUST.** The operator README states prerequisites, duration,
  prompts, ports, mutations, non-actions, install, verify, start, stop, status,
  log, recovery, removal, and expected final markers using portable names.
  Evidence: ___; reviewer/date: ___.
- [ ] **FINAL-05 — MUST.** A second review independently verifies hashes,
  contents, no-jargon scan, secret scan, advisories, licenses, executable test
  results, stable handoff, and absence of stale/superseded bytes. Evidence:
  ___; reviewer/date: ___.
- [ ] **FINAL-06 — MUST.** Record one content-free `carry_ready=pass` receipt
  bound to the complete manifest, reviewer, date, release identity, and exact
  handoff path. Until then the disposition remains `NOT CARRY-READY`.
  Evidence: ___; reviewer/date: ___.

## Planned 2026-10-26 work sequence

### Morning review

1. Resolve `CARRY-D04` and the `CARRY-D05` Tech-layout conflict.
2. Reconcile any resulting decision amendment in the authoritative list.
3. Reconcile release documentation and create the content-free human
   acceptance receipt.
4. Front-load org-lab inventory, license, advisory, platform, and dependency
   gates before any large image work.

### Build and qualification lane

1. Implement only the frozen release/runtime/package design.
2. Produce canonical final source, schema, configuration, image, and
   deployment artifacts rather than a repair chain.
3. Run all local, package, installed-layout, production-runtime, failure,
   cleanup, and reproducibility gates.
4. Repeat affected EmceeDanko qualification and exact-candidate human UI
   acceptance.

### Afternoon/evening carry gate

1. Assemble the smallest final carry set.
2. Publish it atomically to the stable handoff and verify every hash again.
3. Complete the independent review and `FINAL-06` receipt.
4. Carry only if every **MUST** item is checked. Otherwise preserve the
   validated staging bytes, report the first unresolved gate and all known
   downstream blockers, and continue on the next safe work window.

## Final status

`carry_ready=blocked;reason=image_handoff_and_tech_layout_reconciliation_pending`
