# AGENT OPERATION

## LIVE LAB REMOTE-ACCESS GATE — OPERATOR ATTENTION REQUIRED

The agent must not initiate SSH, SCP, rsync-over-SSH, an SSH tunnel, or any
other remote command or probe against a lab host merely because a host alias,
identity file, key, credential, or tool approval is available. Read-only
remote access is still remote execution. Discovering an existing alias or key
does not authorize its use.

Default to an operator-run, report-producing script or command. The operator
must remain in control of authentication and sudo prompts, and the agent must
review the resulting local report. General requests such as "help me build
this," "continue," "inspect," or "prepare the next command" do not authorize
the agent to connect. Sandbox/tool escalation approval is not operator
authorization and does not override this gate.

The agent may initiate a lab connection only when the operator explicitly
directs the agent in the current turn to execute the specific remote action
and that action follows the accepted run path. When an established
operator-run/report path exists, use it instead. If target data is missing,
prepare or repair the bounded operator-facing capture path; do not substitute
ad hoc agent SSH.

If this gate is violated, stop all remote activity, disclose the exact access,
mark derived observations and artifacts unaccepted, block the dependent lane,
and require a fresh operator-run capture before reuse. Read-only intent, lack
of target mutation, or successful cleanup does not reduce the violation.

## Operating Rules

- Read the relevant local docs before changing procedure or evidence.
- Follow `CODING_STANDARD.md` for script and code file style.
- Follow `LAB_RUN_PATH_STANDARD.md` for lab script sequencing, local report write-back, remote payload handling, artifact/advisory verification, and reviewed evidence promotion.
- Treat a stable `<solution-name>-current/` artifact directory as the sole operator handoff source, not as a decorative alias. A replacement build is incomplete until the approved archive and verification files are atomically promoted there and independently checksum-verified. Dated or revision-named outputs are candidates only and must never be reported or transferred as current; preserve displaced bytes under an explicit superseded name.
- Treat security advisories as implementation gates, not paperwork. For first-class packages, wheels, binaries, source archives, containers, authority-service tools, and dependencies, capture advisory sources, review affectedness, record mitigation or non-applicability, and do not proceed to install/promote with an unmitigated action-required advisory unless the operator explicitly accepts and records the risk.
- For off-the-shelf products, prove the vendor-supported minimal runtime before hardening or custom integration. Do not force one approved service into another product's bootstrap path before first runtime proof; supporting services such as OpenBao, PostgreSQL, an IdP, CA, artifact repository, reverse proxy, or observability stack require explicit later integration/runtime-consumer decisions.
- Do not attempt ad hoc SSH to lab hosts from the agent sandbox when the established run path already writes local reports or when interactive key/sudo prompts are required. Review `local/reports/...` first. If more target data is needed, prepare a focused script or command for the operator to run so the output writes back through the controlled report path.
- When using an external URL for planning, decisions, or procedure, add or update its entry in `Reference_Directory.md`.
- Keep execution notes separate from reusable procedure.
- Use placeholders in tracked docs for local-only values.
- Do not store secrets, tokens, private/personal account identifiers, raw vector dumps, or screenshots with private values.
- Prefer small, targeted changes over broad rewrites.
- When a runtime choice changes, record the decision in the repository's authoritative decision list under `docs/decisions/`.

## Decision List Format And Freeze Gate

Every durable decision list must use the repository's Anderson-style
structure unless the operator explicitly requests a different artifact:

```text
# <Subject> Decision List

## Purpose

State what the list governs and what it does not authorize.

## Current Status

Use narrative prose to reconcile the list's history, the status of its
numbered items, the selected posture, and the exact next gate.

## Decisions

1. Item Name

   Decision: Decide the specific question being frozen or discussed.

   Status: Ready to freeze / Frozen / Open / Deferred / Blocked.

   Recommendation: State the recommended posture or action.

   Reason/Evidence: Explain why, citing repository evidence, script results,
   operator input, or reviewed source material.
```

The following rules are binding:

1. Number every recommendation or decision, even when the list contains only
   one item. Use that number when requesting approval and recording a freeze.
2. Give every numbered item exactly one `Decision`, `Status`, singular
   `Recommendation`, and `Reason/Evidence` field in that order. Do not replace
   those fields with a table, summary prose, or unlabeled bullets.
3. Use only `Ready to freeze`, `Frozen`, `Open`, `Deferred`, or `Blocked` as
   item status classes. Qualifying text, including the operator direction or
   date, may follow a frozen status.
4. Use `Ready to freeze` only when the recommendation is concrete enough to
   approve without more discovery. If evidence or an operator choice is
   missing, use `Open`, `Deferred`, or `Blocked` and identify the missing gate
   in `Reason/Evidence`.
5. Write `Current Status` as an Anderson-style narrative that agrees with the
   numbered items. Do not use a second categorized item list that makes the
   reader reconcile two competing representations of status.
6. Keep working order, source registries, action history, and free-standing
   commentary out of the decision list. Put facts needed to judge an item in
   its `Reason/Evidence`; keep detailed history and execution evidence in the
   appropriate evidence or runbook artifact.
7. When the operator freezes an item, update that item's `Status` and the
   list's `Current Status` in the same pass. A separate evidence record does
   not substitute for updating the authoritative decision list.
8. Freezing a planning or read-only-inventory decision does not authorize a
   live connection or mutation unless the item explicitly says so. Continue
   to enforce the remote-access and protected-control-surface gates in this
   file.

## New Workstream Ignore And Sensitive-Artifact Gate

Creating or registering a new root workstream or component directory requires
an explicit `.gitignore` review before source, evidence, or operator tooling is
added. Do not ignore the workstream directory itself; durable docs, scripts, and reviewed,
redacted evidence must remain visible to Git. Instead:

1. Inventory the new workstream's expected local reports, raw evidence, temporary
   output, captures, credentials, receipts, generated packages, caches, and
   other sensitive or machine-specific artifacts.
2. Prefer repository-wide ignore rules that safely protect the same artifact
   class in every workstream. Add a workstream-specific rule only when it has a
   genuinely unique local-only surface, and document why it is narrower.
3. Prove representative paths beneath the new workstream with
   `git check-ignore -v`, including `local/`, `evidence/raw/`, `out/`, and each
   workstream-specific private-artifact path.
4. Run `git ls-files -ci --exclude-standard` after every ignore change. A
   tracked file newly hidden by an ignore rule is a review blocker; never use
   an ignore rule to conceal an already tracked artifact or unresolved leak.
5. Before the workstream's first commit or push, scan its staged/tracked content for
   credentials, private keys, tokens, secret-bearing environment values,
   private local paths, raw protected content, and sensitive generated files.
   Record only redacted findings and non-secret hashes.
6. Update `File_Registry.md` when the repository-wide ignore contract or a
   durable workstream-specific exception changes.

## Operator-Visible Progress And Milestone Gate

An operator-facing command must not appear hung while it performs expected
work. This applies to local builds and validations as well as remote scripts.
It also applies when a parent wrapper invokes another script: redirecting all
child output to a report until the child exits is not an acceptable operator
surface.

For every operator-facing command that has more than one substantive stage or
may reasonably run longer than 15 seconds:

1. Before handing off the command, state its approximate duration, whether it
   can prompt for SSH/sudo/secret input, whether it contacts a target, and the
   expected terminal result marker.
2. Open and validate the report path first, then immediately print a bounded,
   non-secret start milestone identifying the current stage.
3. Print a start and pass/block milestone for each material boundary, including
   readiness, input verification, transfer, extraction, dependency setup,
   tests, build, publication, remote execution, cleanup, and final proof when
   those stages exist. Use meaningful stable tags such as `[READINESS]`,
   `[BUILD]`, `[TEST]`, `[TRANSFER]`, `[PUBLISH]`, and `[SUMMARY]`.
4. If one stage can otherwise remain silent for more than 30 seconds, emit a
   bounded heartbeat at intervals no greater than 30 seconds. Include the
   stage and elapsed time, not raw child output or protected content.
5. A parent wrapper must stream or safely project the child's milestone lines
   as they occur. It may retain verbose output in the local report, but it must
   not suppress all visible progress until completion.
6. Flush progress output promptly so buffering through `tee`, `awk`, Python,
   SSH, or another pipeline does not defeat visibility. A logging or progress
   projection failure must either block or be explicitly reported; it must not
   manufacture a pass.
7. On success, review, block, interruption, or signal, print and record one
   unambiguous terminal result, report path, cleanup status, and next gate.
   Preserve conventional nonzero signal status such as `130` for `SIGINT` and
   `143` for `SIGTERM`; never let an interrupted run appear successful.
8. Keep milestone output secret-safe. Never print credentials, tokens,
   passphrases, private paths, prompts/responses, raw vectors, full environment
   dumps, or secret-bearing command lines merely to show activity.
9. Add executable wrapper coverage for milestone visibility and ordering,
   terminal pass/block behavior, nested-command failure propagation, signal
   status, and unchanged-state behavior after interruption. Comments or static
   string checks alone are insufficient when the control flow can be tested.

During agent-executed work, provide a concise commentary update before a
long-running tool call, at each meaningful transition, and at least once every
60 seconds while work continues. Do not leave the operator to infer activity
from an unchanged terminal or report file.

## Protected Control-Surface Change Gate

Existing launchers, systemd units and drop-ins, installed operator commands,
service wrappers, credentials, listeners, and shared runtime paths are protected
control surfaces. A trial, proof, maintenance window, checksum, backup, or
rollback path does not authorize replacing or extending them.

Before writing, packaging, recommending, or instructing any change to a
protected control surface:

Every recommendation or decision presented to the operator must have an
explicit item number, even when only one recommendation or option exists.
Use that number when requesting approval and when recording the frozen
decision so the approved scope cannot be confused with surrounding prose.

1. Identify every exact target path and every existing service or operator that
   consumes it.
2. Add the installation, persistence, and cleanup shape as an explicit open
   item in the owning decision list.
3. Discuss alternatives with the operator, including package-local execution,
   transient `/run` staging, persistent installation, and no-change options.
4. Disclose which files and commands will be created, replaced, or removed;
   whether an existing service will execute changed code; how long the change
   persists; and what cleanup or rollback leaves behind.
5. Obtain explicit operator approval and freeze that decision before providing
   a mutating command. General instructions such as "continue," "implement the
   trial," or approval of a broader plan do not authorize an undisclosed
   control-surface design.

For one-time trials, default to a single package-local orchestrator and
transient state unless the operator explicitly freezes a persistent-install
design. Reversibility, containment, idempotence, a protected backup, and an
available rollback are safety properties; none substitutes for authorization.

If an unapproved control-surface mutation has already occurred, stop before the
next mutation, disclose the exact current state and consumers, and present
continue-in-place, restore, and redesign options. Do not recommend or execute a
rollback as an automatic reaction; rollback is another operator decision.

## Approved-Contract Correction Boundary

Once the operator has approved and frozen a design, ordinary implementation
corrections that make its scripts satisfy that exact contract do not require a
new approval for every patch. Diagnose, patch, run the required isolated
regressions, update durable evidence, and present the corrected result as one
coherent batch when all of the following remain true:

- the approved targets, outcome, persistence, security posture, recovery
  posture, and mutation boundary do not change;
- no additional live-host execution or mutation is performed;
- the correction does not introduce a new service, credential, listener,
  installed command, dependency, control-surface replacement, destructive
  operation, or operator burden; and
- the correction is covered by executable tests for the observed failure and
  adjacent failure paths.

Stop for a numbered operator decision when a proposed correction changes any
approved scope or posture, requires a new live/destructive action, chooses
between materially different recovery outcomes, or creates a new protected
control surface. Group related implementation fixes and their validation
instead of requesting approval patch by patch. If the boundary is genuinely
ambiguous, explain the exact ambiguity and discuss it before acting.

## Executable Trial Validation Gate

Shell/Python syntax checks, decoded-secret scanner self-tests, source checksums,
and literal or structural invariants are static checks. They do not prove that
an orchestrator can create its state, cross each runtime transition, clean up,
export evidence, repair an earlier installation, or roll back safely.

Before describing a new or changed trial build as validated, current,
transfer-ready, installable, repair-capable, or rollback-capable:

1. Exercise the complete changed orchestration in an isolated executable
   harness with controlled substitutes for target services and tools.
2. Cover the happy path and failure paths before and after every mutation that
   changes cleanup responsibility or persistent/transient state.
3. Exercise file and directory creation semantics, shell-to-embedded-language
   parsing, exact containment cause, baseline restoration, evidence
   correlation, secret-scan positive/negative cases, atomic publication, and
   published checksums wherever those behaviors exist.
4. For a package that can encounter an earlier installed revision, separately
   exercise clean install, same-version replay, supported upgrade/repair, and
   rollback from every accepted installed state. A backup file is not proof
   that the rollback workflow works.
5. Preserve the test command, scenario coverage, and result in the owning
   decision/evidence record. Keep raw output outside Git when it may contain
   target-specific or sensitive material.
6. If a required executable scenario has no harness or has not passed, label
   it `UNPROVEN` or `BLOCKED`; do not substitute static validation language.
7. State separately what still requires live-target proof. Passing isolated
   mocks never establishes actual target service, container, journal, timeout,
   or rollback behavior.

These gates apply before publication into a stable `-current` handoff. A later
failure may require a new build, but it does not permit silently changing the
approved installation or execution posture as a recovery shortcut.

## Evidence Rules

- Summarize useful evidence instead of dumping full output.
- Preserve only the proof needed for a decision, blocker, or validation claim.
- Keep raw logs in local-only storage unless explicitly reviewed and redacted.
