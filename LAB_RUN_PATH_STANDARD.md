# Lab Run Path Standard

## Purpose

This file standardizes the operator-run pattern already used across the lab scripts so future agents do not reinvent the control flow.

Use this standard for scripts that stage artifacts, copy temporary payloads to lab hosts, run remote checks or mutations, and write local reports for later review.

## Non-Negotiable Operator-Attended Remote Gate

Agents do not directly initiate SSH, SCP, rsync-over-SSH, tunnels, or remote
probes against lab hosts by default, including read-only commands. Existing
aliases, identity files, keys, previous successful connections, and tool-level
approval are not permission. Prepare a report-first command or script for the
operator to run and review its local report afterward.

Only a current-turn operator instruction to execute the specific remote action
can permit agent-initiated access, and it does not waive any accepted run-path,
credential-purpose, report, sudo, mutation, or evidence gate. Broad requests
to help, continue, inspect, or prepare work are not remote-access permission.
An unauthorized remote observation is unaccepted evidence and blocks any
dependent lane until an operator-run capture reproduces it.

## Canonical Run Path

1. Start from the repository root and print the purpose, operator context, expected directory, remote context, and guarded side effects.
2. Load `local/site_values.env` when present, while keeping tracked defaults non-secret and replayable.
3. Create a timestamped report under `local/reports/<workstream-or-lane>/`, prove the report directory is writable with an explicit create/remove probe, and only then redirect script output through `tee` before meaningful validation or mutation begins. A background or process-substitution `tee` failure must not allow the script to continue without its required report.
4. Validate local tools, expected SSH identity files, host/IP targets, artifact inputs, and any local report or artifact directories before remote work.
5. Print planned values and explicit non-actions before mutation. The report must make clear whether package install, service mutation, firewall mutation, certificate generation, trust-store change, private-key copy, secret read, raw PEM printing, request-body logging, or boot-autostart change is in scope.
6. For packages, wheels, source archives, containers, or equivalent artifacts: stage locally, capture and review advisory sources, determine affectedness for the selected version/package/build, record action-required status and mitigation/disposition, verify upstream checksums or record their absence, write local SHA-256 manifests, carry to the target, verify again on the target, then install or promote only from the verified carried artifact set.
7. For remote execution, create the remote payload locally as a temporary script, copy it to the target under `/tmp`, execute it with the declared SSH/sudo path, and remove the temporary remote payload through its own cleanup trap when practical.
8. Remote scripts must write a durable remote summary when they mutate target state. Use root-owned service or authority paths such as `/var/lib/<service-or-authority>/...`; do not rely on terminal scrollback as the only target-side record.
9. Local wrappers must record copy and remote execution results in the local report. When a copy or remote command fails, write a local blocked summary before exiting nonzero.
10. Promote only reviewed, redacted summaries into tracked evidence. Raw reports, raw logs, secrets, private keys, raw PEM bodies, private local paths, raw request bodies, prompts, responses, chunks, and vectors stay local-only unless explicitly reviewed and sanitized.

## Operator-Visible Milestone Stream

Report-first does not mean terminal-silent. Any operator-run wrapper with more
than one substantive stage or an expected runtime over 15 seconds must provide
a live, bounded, secret-safe milestone stream while preserving the detailed
local report.

- Print the report path and a start milestone before lengthy validation,
  transfer, build, install, or remote work begins.
- Use stable work-oriented tags and print stage start plus pass/block
  transitions. Include enough context to distinguish local validation,
  authentication wait, transfer, target execution, cleanup, publication, and
  final review without emitting raw protected output.
- Emit a heartbeat at least every 30 seconds during an otherwise quiet stage,
  including the current stage and elapsed time. Flush every milestone.
- When one operator wrapper calls another, stream or filter the child's safe
  milestone lines live. Do not redirect the entire nested run to a temporary
  file and remain silent until it exits.
- Display interactive SSH, sudo, or acknowledged secret-entry prompts on the
  operator's terminal. Never turn a prompt into a captured secret or hide it
  behind a silent pipe.
- End every run with one explicit `pass`, `review`, or `blocked` marker, local
  report path, cleanup outcome, and next gate. Signals and nested failures must
  propagate nonzero and must be written as blocked, never as exit `0`.
- Keep verbose child logs in the report when appropriate, but prove milestone
  visibility, ordering, buffering behavior, nested failure propagation, and
  interruption handling in the wrapper's executable regression.

Before providing the operator command, state an approximate duration, expected
prompt count/type, whether target contact or mutation is possible, and the
expected final marker.

## Data Transfer Stewardship

Network transfer is a limited operational resource. Artifact capture scripts must minimize repeated transfer as a correctness requirement, not merely as a performance improvement.

- Run all gates that do not require artifact payload bytes before bulk transfer. This includes identity, license, policy, source-host, target-platform, dependency-resolution, and advisory checks whenever their inputs are already available.
- Put material public downloads in an ignored, persistent staging directory keyed by exact artifact identity, version or revision, target platform, and relevant runtime variant. Do not use ephemeral `/tmp` storage as the only copy of a large download.
- Write and validate a non-secret staging identity record before reusing staged data. Refuse ambiguous, mismatched, symlinked, or unexpectedly structured staging rather than merging it.
- Download through temporary partial names where the protocol permits, resume interrupted transfers, verify expected size and upstream or frozen SHA-256 identity, and rename to the final staged filename only after validation.
- Reuse checksum-valid completed files and capture checkpoints on rerun. A metadata-parser defect, advisory decision, reporting failure, checksum pass, or later promotion failure must not force already validated public bytes across the network again.
- Never delete reusable public model, wheel, package, archive, container, or equivalent payload bytes from a generic `EXIT`, `ERR`, signal, or failure cleanup trap. On block, print the preserved staging path, its identity, and the exact rerun action.
- Remove persistent staging only after a complete destination has been promoted and independently checksum-verified, or after the operator explicitly rejects that staged identity. Do not silently delete a mismatched or superseded large artifact.
- A stable `<solution-name>-current/` directory is the operator transfer and handoff pointer. Never direct an operator to a dated candidate while leaving stale bytes in `-current`. A replacement is not published until the approved archive and verification files are atomically promoted into `-current`, its sidecar passes from that directory, and an independent hash matches the recorded identity. Preserve the displaced artifact under an explicit superseded name when retention is required.
- Avoid duplicate full-size copies solely for validation. Prefer read-only verification against the staged directory, same-filesystem atomic rename, or a documented copy strategy when a second copy is genuinely required.
- Keep sensitive cleanup separate. Plaintext secrets, private keys, raw protected configuration, private documents, prompts, responses, and other restricted temporary data still require prompt bounded cleanup under their governing security rules and must never be retained merely to save transfer time.
- Reports must state estimated or observed transfer bytes, reused bytes, newly transferred bytes, preserved staging location, and whether cleanup removed any payload bytes.

## SSH Connection Reuse

For scripts that run more than one SSH/SCP action against the same target, use the repo SSH connection reuse pattern in:

```text
SSH_CONNECTION_REUSE_STANDARD.md
```

That pattern uses OpenSSH ControlMaster/ControlPersist with a script-owned `/tmp` control path and cleanup trap so the operator enters the SSH key passphrase once per script instead of once per copy/run step.

This does not relax function-specific SSH key discipline, sudo prompts, artifact/advisory gates, mTLS requirements, OpenBao/WSO2 gates, or evidence boundaries.

Use the short `%C` hashed control socket form from `SSH_CONNECTION_REUSE_STANDARD.md`. Long control socket paths can make `ssh` or `scp` fail locally before the target host is touched.

## WSL Mount And Executable-Bit Discipline

This repository may live on a Windows-backed WSL mount such as `/mnt/g`. On that surface, Unix mode mutations can be noisy or unreliable. Do not use `chmod +x` on repo scripts as a validation step or routine fix. Prefer running repo scripts as `bash ./path/to/script.sh`.

When a temporary local or remote payload needs executable permissions, create it under a real Linux filesystem such as `/tmp` or on the target host and `chmod` that temporary payload there. When tracked executable-bit metadata truly needs to change, use git metadata intentionally, such as `git update-index --chmod=+x <path>`, and record the reason. Do not treat a local `chmod: Operation not permitted` warning on a Windows-backed repo path as a script failure unless the script requires direct execution from the filesystem.

## Sequencing Rules

Active scripts use ordered numeric names only when they are the current executable lane. Prepared but deferred work must be moved to a parked location or otherwise labeled outside the active sequence.

Do not let an interim tool become architecture by accident. Label disposable tools as disposable in the script purpose, guarded side effects, evidence, and decision docs.

When a script introduces a package or dependency, the artifact/advisory/replay lane must come before install. A convenience install can be documented as historical evidence, but it does not satisfy the durable replay standard until staged, hashed, carried, target-hashed, confirmed, and installed from local artifacts.

For off-the-shelf products, follow product-first proof sequencing. Do not force a supporting service into another product's bootstrap path before the target product has a vendor-supported first runtime proof. Supporting services include OpenBao, PostgreSQL, IdPs, CAs, artifact repositories, reverse proxies, observability stacks, and equivalent lab authorities. Store source-of-truth material in the selected authority when that posture is frozen, but integrate it into product runtime only through a later explicit integration/runtime-consumer decision and report boundary.

## Report Review Pattern

After the operator runs a script, the next agent should inspect the newest local report directly from `local/reports/...` instead of asking the operator to paste output.

Do not burn time on ad hoc SSH from the agent sandbox when the workflow already captured a local report or when the target requires interactive key/sudo entry. If the local report does not contain enough information, create a bounded probe or patch the next script so the operator-run path captures the missing non-secret evidence.

The reviewed evidence should capture:

- script name and execution timestamp
- local report path
- target host and role
- artifact directory or remote summary path when applicable
- pass/block result and any review count
- key versions, hashes, certificate fingerprints, service/listener posture, and validation statuses
- explicit non-actions and rollback path
- remaining gaps or next command
- transfer bytes, reused bytes, persistent staging/checkpoint state, and any payload deletion

For offline replay, avoid vague acceptance language such as "clear enough" or "looks fine." Use explicit reviewed terms: accepted, blocked, deferred, action required, mitigated, reused, created, unchanged, or superseded. Replay-facing evidence should name the exact inputs, outputs, host, script, report path, artifact path, object paths, hashes when available, side effects, non-actions, rerun behavior, and the next approved gate.

## Repair-To-Master Replay Rule

Repair scripts are allowed during live lab discovery, but they are not the desired offline replay interface. After a repair path is proved and accepted, fold the final learned state into later master/bootstrap scripts or runbooks so a bastion/offline replay applies the corrected account, path, ownership, mode, symlink, config, artifact, advisory, and validation posture directly.

Master replay scripts should avoid requiring the operator to replay the historical sequence of blocked attempts and repairs. They may reference the evidence that taught the final posture, but their implementation should create or verify the final accepted state idempotently: if an approved object already exists and matches the frozen posture, reuse it; if it is missing, create it; if it exists with unexpected drift, block for review.

After a retrospective folds repaired posture into a master script or ordered master-run script set, test that replay path directly. The replay test should prove the master path creates or verifies the final accepted state without depending on the historical blocked-run sequence.

Implementation objects created on target hosts should be meaningful outside this repo. Do not carry project, workstream, script, or agent labels into target systemd drop-ins, service names, runtime directories, authority paths, policies, database objects, certificate labels, transfer bundles, operator-facing artifacts, or config names unless the object is explicitly historical evidence material. Prefer stable service names such as `runtime-paths.conf` over project-specific or unexplained numeric names.

For new executable scripts and master replay recipes, prefer portable action/product names instead of workstream-title basenames. Existing historical names may remain when they are already part of the accepted evidence trail, but do not use those names as templates for deployed or replay-bundle artifacts.

## Security Discipline

Security advisory capture, review, mitigation, and action disposition are part of artifact acceptance. Capturing an advisory page is not a clearance. A report should distinguish advisory captured, reviewed, affected/not affected, action required, mitigated, deferred with explicit operator risk acceptance, or not applicable.

Do not install or promote a package, wheel, binary, source archive, container image, authority-service tool, or first-class dependency while an action-required security advisory remains unmitigated. Allowed dispositions are: upgrade/pin to a fixed version, apply a patch, disable or avoid the vulnerable feature, apply a compensating control with evidence, mark not affected with evidence, or record an explicit operator-approved deferral with reason, owner, and revisit trigger.

Use function-specific SSH identities. Do not reuse keys across unrelated tools, products, hosts, or functions.

Use certificate and application credentials only for their recorded purpose. A credential issued for Postman/operator validation must not be repurposed for agent-driven automation, package movement, service identity, or unrelated probes unless a later decision explicitly changes that credential's role and evidence boundary.

Never store or print raw secret values, private keys, CA private keys, bearer tokens, API keys, private local account identifiers, raw PEM bodies, raw request bodies, prompts, responses, chunks, vectors, or full environment dumps.
