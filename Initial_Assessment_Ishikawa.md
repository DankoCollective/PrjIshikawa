# Initial Assessment — Ishikawa v1.3

Date: 2026-10-25

## Purpose

This document is a technical handoff to the agent who previously developed
Ishikawa. It summarizes the current release and deployment posture, assesses
the attended EmceeDanko deployment design, identifies the most important
review questions, and proposes the next controlled steps.

This is an assessment and plan, not an acceptance receipt. No EmceeDanko
connection was made while preparing this work, no target deployment was run,
and no org-lab package was assembled.

## Executive assessment

Ishikawa v1.3 is technically mature and ready for expert review before its
attended EmceeDanko launch. The product boundary is coherent: the application
release is corpus-agnostic, PostgreSQL remains the runtime source of truth,
corpus v3 is a separate synthetic qualification fixture, credentials remain
outside tracked configuration, and boot autostart remains disabled.

The exact v1.3 candidate has already passed the disposable EmceeDanko gate:

- 486 native tests passed;
- corpus v3 published as 30 documents and 150 pages;
- the qualified database contained 786 authoritative chunks, 943 retrieval
  candidates, 157 scoring-only candidates, 943 embeddings, 240 relationship
  records, and 90 distinct relationship pairs;
- all 60 frontier cases passed, returned their required evidence, and cited
  their required evidence; and
- the disposable PostgreSQL cluster, API, credentials, workspace, transfer,
  and reserved listeners were removed afterward.

The remaining release gate is not another synthetic qualification. It is the
attended launch of the exact qualified candidate, human UI review, and an
explicit acceptance or rollback decision.

## Bound identities

The attended deployment is bound to these already-qualified inputs:

- Ishikawa v1.3 archive SHA-256:
  `53da57b745fb4c8be6335896d05bdb6f63f2de3494862b99acca09e156863f3c`
- qualification-corpus-v3 archive SHA-256:
  `9e4eadfe43dfd875e9d639119fe933dadfb409b63d28f68c22247441e09581fd`
- retained Script 05 report SHA-256:
  `854240b564148f38853b183852ca98ac12d38ef3a57bb6ed513116270d7a98c0`
- Script 05 receipt SHA-256:
  `8672b7e804d4b5028e7e898f67aa91a32588cd48748bd3283b773332e606759f`
- Script 05 target-result SHA-256:
  `0f2ed136458ca34d2c5eecb9f37ad04a5c411f1b8b7d0e543ef14362fcc7f6e5`
- frontier-result SHA-256:
  `3cdf7dc4bed4bef9935148f7604d5499342c5ae2b54c9be13594b9ab10caeb49`
- accepted AMD64 web-image identity:
  `sha256:368f4381b61bf90ad27aa5a9dd4c10e1de0b4b4666006911e1b6cb4aafcfb8a6`

Script 06 fails closed if those local handoffs or their required evidence
contracts differ.

## Current target posture

The expected EmceeDanko state before Script 06 is:

- the qualified v1.3 candidate is staged at
  `~/Documents/Ishikawa-v1.3`;
- accepted v1.2 remains at `~/Documents/Ishikawa`;
- the accepted rollback tree remains at
  `~/Documents/Ishikawa-before-v1.2`;
- the accepted v1.2 database files remain untouched;
- Script 05's disposable database and Retrieval API are absent;
- the v1.2 API, UI, and PostgreSQL cluster are active but boot-disabled; and
- ports `3384`, `8384`, and private build port `65438` are free.

The attended v1.3 UI uses `3384`, its Retrieval API uses `8384`, and v1.3 does
not bind `1384`. Accepted v1.2 owns `1384` before switchover. After v1.2 stops,
the port must remain unoccupied and reserved for v1.2 rollback throughout the
attended gate. Anderson is not installed or running on EmceeDanko and has no
availability requirement in this gate; Script 06 does not coordinate it.

## Architectural assessment

### Application and corpus boundary

The repository now consistently treats Ishikawa v1.3 as the application and
corpus v3 as a separate qualification input. Script 06 does not alter the
frozen candidate. It creates the catalog and ingestion manifest in a private
installed runtime using the existing reviewed generator, then validates both
with the shipped application validators.

This is the correct direction. It avoids coupling a portable application
release to one synthetic fixture and preserves the eventual org-lab boundary,
where the black corpus must carry its own reviewed catalog, manifest, counts,
and acceptance expectations.

### PostgreSQL isolation

The frozen application requires database `rag_catalog` and roles `rag_owner`,
`rag_ingest`, and `rag_retrieval`. Renaming those objects for side-by-side use
would require changing the exact qualified application configuration contract.

Script 06 therefore isolates the entire PostgreSQL data cluster:

1. While v1.2 remains available, initialize the v1.3 PostgreSQL 16 cluster in
   `~/Documents/Ishikawa-v1.3-attended/state/postgresql`.
2. Build and validate it on private loopback port `65438`.
3. Install the exact schema-v5 package, create the canonical roles/database,
   generate the corpus-v3 catalog and manifest, publish corpus v3, and verify
   the complete qualified inventory.
4. Stop the private validation listener.
5. Only at the immediate attended switchover, stop the v1.2 UI, API, and host
   PostgreSQL unit.
6. Start the isolated v1.3 cluster on canonical port `5432`, then start the
   package-local API on `8384` and the distinct UI container on `3384`.

This preserves both durable database trees and avoids any SQL operation against
the accepted v1.2 cluster. Stopping and restarting the v1.2 host unit changes
runtime availability only; it does not merge, upgrade, or overwrite its data.

### Attended service arrangement

The packaged systemd unit and `scripts/ishikawa-stack` assume the canonical
`~/Documents/Ishikawa` path and therefore are intentionally not used for this
candidate test. Script 06 instead starts:

- PostgreSQL through the private cluster's PostgreSQL 16 `pg_ctl`;
- the Retrieval API directly from the package-local attended runtime as a
  detached `setsid` process; and
- a distinct ephemeral Docker container named `ishikawa-v1.3-web` with
  restart policy `no`.

No v1.3 unit is installed or enabled. This is appropriate for a reversible,
attended gate, but it is deliberately not a final unattended production
service arrangement. The Retrieval API is not a transient systemd user
service and neither it nor the private PostgreSQL cluster has an automatic
restart supervisor. The operator must therefore remain responsible for the
attended runtime until acceptance or rollback is complete.

## Script 06 assessment

The consolidated operator interface is:

```text
deployment/scripts/06_attended-v1.3-on-emceedanko.sh
```

Its public modes are:

- `--validate-only`: revalidate all local identities and assemble the exact
  payload without target contact;
- `--run`: perform target preflight, create or revalidate durable v1.3 state,
  switch from v1.2, and launch the attended UI;
- `--accept`: verify the running attended boundary and atomically record human
  UI acceptance; and
- `--rollback`: stop v1.3, restart the untouched v1.2 PostgreSQL cluster, API,
  and UI, and preserve the durable v1.3 cluster for review or an exact retry.

Notable safety properties include:

- exact Script 01, Script 05, candidate, corpus, schema, and web-image identity
  checks;
- complete target identity, PostgreSQL 16/pgvector, capacity, configuration,
  model, container, port, v1.2 readiness, and rollback-credential preflight
  before deployment mutation;
- candidate checksum and file-mode parity;
- installed-runtime parity outside explicitly approved configuration, corpus,
  and state surfaces;
- hidden credential input with no tracked or report persistence;
- rejection and preservation of partial or symlinked attended state;
- refusal to terminate a PID unless its command line belongs to the exact
  attended Retrieval API;
- preservation rather than deletion if PostgreSQL cannot be proved stopped;
- automatic v1.2 restoration after every failure following the switchover;
- atomic human-acceptance receipt publication;
- boot-autostart verification before and after launch/restoration;
- precise stage, reason, detail, and operator-action failure fields; and
- one outer `SCRIPT RESULT` marker per public invocation.

## Validation completed

The following local validations passed without contacting EmceeDanko:

- Script 06 exact-evidence `--validate-only` gate;
- complete Script 06 target lifecycle regression, including:
  - model failure before mutation;
  - fresh-ingestion failure and cluster cleanup;
  - partial-state and unsafe-path rejection with preservation;
  - installed-layout and real configuration/catalog/manifest validation;
  - failed web launch with automatic v1.2 restoration;
  - failed automatic restoration reporting;
  - pre-switchover durable-reuse failure cleanup;
  - durable reuse and successful launch;
  - unrelated-PID protection;
  - human acceptance; and
  - explicit rollback;
- Script 06 wrapper regression for transfer, result parsing, launch, accept,
  rollback, precise remote failure propagation, SIGTERM cleanup, UI/operator
  command output, temporary-transfer removal, and the single-result contract;
- all 486 native tests;
- existing release-boundary, Script 04 helper/wrapper, and Script 05
  helper/wrapper regressions;
- Script 01 decision and release validation through V13-75;
- syntax validation of all 27 active shell scripts;
- syntax compilation of 106 active Python files without writing bytecode;
- 152 Markdown files checked for local-link integrity; and
- whitespace, diff, and high-confidence credential-pattern checks.

The previous developer independently reran both Script 06 regressions during
review. The isolated target lifecycle regression and the wrapper regression
both passed. Shell syntax validation and `git diff --check` also passed.

## Previous developer review findings

The deployment architecture is approved for an attended EmceeDanko gate. The
whole-cluster isolation is justified by the frozen `rag_catalog`, `rag_owner`,
`rag_ingest`, and `rag_retrieval` identities; the application/corpus boundary,
switchover ordering, rollback implementation, relationship metrics, and
separate org-lab packaging gate are coherent.

One operator-facing issue required reconciliation before the live run:
documentation assigned port `1384` to Anderson even though Anderson is not
installed or running on EmceeDanko. Script 06 restores and proves v1.2 through
`http://127.0.0.1:1384/ready` after any failed launch and during explicit
rollback. The corrected contract therefore identifies `1384` solely as the
v1.2 runtime and rollback port and keeps it unoccupied after switchover until a
later explicit promotion or retirement decision removes that dependency.

The model forwards are also a runtime dependency, not merely a launch
preflight. The Gemma and Nomic forwards must remain active from Script 06
startup through human UI review and the final acceptance or rollback action.
Script 06 proves them before switchover, but it does not supervise or recreate
them if an operator-managed tunnel later closes.

`--accept` records the human decision but does not install a permanent v1.3
service, enable boot autostart, replace `~/Documents/Ishikawa`, retire v1.2, or
release `1384`. After acceptance, v1.3 remains an attended, unsupervised
runtime until the separately reviewed promotion action.

Finally, the assessment, Script 06, and its two regressions appeared as
untracked files during this review while the registry labeled them tracked.
The new agent must reconcile the complete worktree and make the reviewed state
durable before treating this handoff as repository evidence. This is release
hygiene, not an application or corpus requalification requirement.

## Review requested from the previous developer

The previous Ishikawa developer should focus review on these questions:

1. Confirm that database `rag_catalog` and roles `rag_owner`, `rag_ingest`, and
   `rag_retrieval` are intentionally frozen runtime identities for v1.3.
2. Confirm that the qualified corpus-v3 inventory constants remain the correct
   post-publication contract, especially 240 relationship records versus 90
   distinct relationship pairs.
3. Confirm that direct package-local API execution is behaviorally equivalent
   to the packaged user unit for an attended gate once the same three protected
   environment credentials are supplied.
4. Review the PostgreSQL switchover ordering: v1.2 UI, API, and host cluster
   stop immediately before the isolated cluster takes port `5432`.
5. Review the rollback proof, particularly the real v1.2 readiness check after
   its untouched cluster and service are restarted.
6. Confirm that the UI/API choices `3384` and `8384` avoid all current Danko Lab
   ownership conflicts, that v1.3 never consumes `1384`, and that `1384`
   remains available for v1.2 rollback throughout the attended gate without
   any Anderson coordination requirement.
7. Review the intended local-trust boundary for the private PostgreSQL Unix
   socket: the attended root and socket directory are owner-only, while TCP
   role authentication uses SCRAM passwords.
8. Review the human UI checklist below and add any product-specific workflows
   that were important during the original v1.3 development acceptance.

## Known remaining risk

The primary remaining uncertainty is environmental, not a known source defect:
Script 06 has not yet run against the live EmceeDanko state. The first attended
run must prove that the actual systemd, Docker, PostgreSQL, model-forward, disk,
and credential posture still matches the retained inventory and qualification
evidence.

Other operational considerations are intentional:

- the v1.3 API and private PostgreSQL cluster are attended processes without a
  boot-enabled supervisor;
- the operator-managed Gemma and Nomic forwards must remain active through
  launch, UI review, and the final acceptance or rollback action;
- port `1384` must remain unoccupied after switchover for the v1.2 rollback
  path; Anderson is absent and is not part of the gate;
- an exact reuse requires the same v1.3 ingestion and retrieval passwords used
  when the durable cluster was first created;
- a failed restoration is reported as blocked and requires the operator to
  remain attended; and
- acceptance does not promote v1.3 into `~/Documents/Ishikawa`, delete v1.2,
  assemble an org-lab package, install a supervisor, or release `1384`.

## Plan for moving forward

### 1. Complete developer review

Have the previous developer review this assessment, V13-75, Script 06, and its
two regression scripts. Resolve any objection that changes the deployment
boundary before target execution. Behavioral application changes must not be
folded silently into this v1.3 deployment; they require a separately reviewed
release decision and requalification.

### 2. Re-run the non-contact gate

From the repository root:

```bash
bash ./deployment/scripts/06_attended-v1.3-on-emceedanko.sh --validate-only
```

Require the final marker:

```text
script_06_attended_v1_3_on_emceedanko=ready
```

### 3. Run the attended deployment

Prepare the Gemma key, Nomic key, accepted v1.2 retrieval password, and new or
previously established v1.3 ingestion/retrieval passwords. Then run:

```bash
bash ./deployment/scripts/06_attended-v1.3-on-emceedanko.sh --run
```

A fresh database build is expected to take roughly 15–30 minutes; exact reuse
is expected to take roughly five minutes. Keep the terminal attended through
the final result. Require:

```text
script_06_attended_v1_3_on_emceedanko=pass
```

The script prints the UI address, SSH port-forwarding command, acceptance
command, and rollback command only after a passing launch.

### 4. Perform human UI acceptance

At minimum, verify:

- the UI loads on the printed `3384` forwarding path;
- an ordinary policy question returns a grounded answer with valid citations;
- an exact-document or identifier question selects the intended source;
- citation selection opens the correct reconstructed document view;
- pagination or continuation preserves document/version identity;
- a supported follow-up resolves against prior conversational context;
- an insufficient-evidence question abstains or clarifies safely;
- malformed or unavailable dependency behavior remains content-safe;
- the Gemma and Nomic forwards remain active;
- port `1384` remains unoccupied after switchover for v1.2 rollback, with no
  Anderson runtime present or required;
  and
- the UI identifies Ishikawa v1.3 and uses only ports `3384` and `8384` for
  this attended gate.

Record observations outside Git if they contain prompts, responses, document
text, credentials, or other sensitive content.

### 5. Accept or roll back explicitly

If the UI is accepted, run the exact `--accept` command printed by Script 06.
If any acceptance criterion fails, run the exact `--rollback` command instead.
Do not manually mix components from the two runtime states.

Acceptance records the human decision but deliberately leaves the attended
v1.3 runtime boot-disabled and unsupervised. Keep the model forwards active and
keep `1384` free until the later promotion decision establishes the permanent
runtime or explicitly retires the v1.2 rollback path.

Rollback should leave v1.2 ready and preserve the v1.3 attended root and
database for diagnosis. A later retry must pass the full preflight and exact
durable-reuse checks again.

### 6. Retain a content-free acceptance summary

After human acceptance, review the target receipt and local Script 06 report.
Promote only a checksum-bound, content-free summary into tracked evidence. Do
not commit credentials, prompts, responses, source documents, chunks, vectors,
database dumps, or raw operational logs.

### 7. Begin the next release action separately

Only after EmceeDanko human UI acceptance should the project design and execute
the org-lab carry package. That later work must preserve the application/corpus
separation and use the reviewed org-lab catalog, manifest, corpus-derived
counts, and acceptance gates. Synthetic corpus-v3 cardinalities must not be
treated as portable black-corpus acceptance constants.

Canonical replacement of `~/Documents/Ishikawa`, retirement of v1.2, or a
permanent v1.3 service arrangement also require an explicit later plan. Script
06 does not authorize those actions.

## Current recommendation

The previous developer confirms the frozen database identities, whole-cluster
isolation, switchover ordering, rollback implementation, application/corpus
boundary, and UI/API ports for the attended gate. Before target execution, the
new agent must reconcile the `1384` documentation and worktree durability
findings above and confirm agreement in this document or the corresponding
review record. No product, retrieval, corpus, or database requalification is
required for those corrections.

After that reconciliation, rerun `--validate-only` and proceed with the Script
06 attended run. The live EmceeDanko execution and human UI decision are the
remaining conditions before any org-lab packaging or permanent promotion.

## Handoff agreement status

Previous developer position: conditionally approved. No application, corpus,
retrieval, ranking, packing, or database requalification is required. Approval
becomes unconditional when the new agent:

1. confirms that `1384` remains reserved for v1.2 runtime and rollback, while
   Anderson is absent and outside the attended gate;
2. reconciles the conflicting `danko_lab.md` wording and the Script 06 result
   label without changing runtime behavior, then reruns the two Script 06
   regressions and `--validate-only`; and
3. reconciles the worktree so this assessment, Script 06, its tests, and the
   associated documentation are genuinely durable and consistently registered.

## New-agent and operator agreement

Operator position: confirmed on 2026-10-25.

New-agent position: agreed, with the following clarification of the `1384`
starting point supplied by the operator:

1. Anderson is not installed or running on EmceeDanko. There is no live
   Anderson process, service, or availability requirement to preserve on that
   host during the Ishikawa attended gate.
2. Before the attended switchover, accepted Ishikawa v1.2 occupies `1384`.
3. After v1.2 stops and v1.3 starts on `8384`, port `1384` must remain unused
   and available for automatic or explicit v1.2 rollback. This is a rollback
   requirement, not an Anderson-availability requirement.
4. Anderson may remain unavailable for any duration. Script 06 does not need
   to start, stop, preserve, or otherwise coordinate Anderson.
5. Gemma and Nomic remain runtime dependencies and their operator-managed
   forwards must remain active through launch, human UI review, and the final
   acceptance or rollback action.
6. The reviewed assessment, Script 06, regression tests, and associated
   documentation must be made durable and consistently registered before live
   EmceeDanko execution.

This clarification supersedes statements in the preceding review that describe
Anderson as a live EmceeDanko workload or make its availability part of the
Ishikawa gate. It does not change the required v1.2 rollback behavior: `1384`
must be free after switchover so v1.2 can be restored if needed.

All three parties accepted this starting point on 2026-10-25, and the operator
authorized the bounded reconciliation. Work is limited to reconciling the
`1384` documentation and Script 06 result labels, rerunning the affected
regressions and validation-only gate, and making the reviewed worktree durable.

## Bounded reconciliation result

The authorized reconciliation completed on 2026-10-25 without changing
Ishikawa application, corpus, retrieval, ranking, packing, database, service,
or rollback behavior.

- `danko_lab.md` now records that Anderson is absent from EmceeDanko and that
  `1384` belongs to the accepted v1.2 runtime and rollback path.
- Script 06 now emits
  `port_1384_purpose=v1_2_runtime_and_rollback` in both validation-only output
  and target result records. It no longer emits an Anderson ownership label.
- The target lifecycle regression asserts the corrected result in launch,
  acceptance, and rollback modes. The wrapper regression asserts it in the
  transferred target result and validation-only output.
- The complete Script 06 target lifecycle regression passed, including all
  modeled preflight, mutation, restoration, acceptance, and rollback branches.
- The complete Script 06 wrapper regression passed, including launch,
  acceptance, rollback, remote failure, interruption, cleanup, and standalone
  result behavior.
- Script 06 `--validate-only` passed with target contact, database contact,
  service mutation, and credential reads all reported false. Its standalone
  result was `script_06_attended_v1_3_on_emceedanko=ready`.

The three conditional handoff items are satisfied. The remaining gate is the
operator-attended EmceeDanko Script 06 run and human UI acceptance; org-lab
packaging remains unauthorized until that acceptance passes.
