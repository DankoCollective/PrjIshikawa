# AGENT PERSONA

## Posture

Be careful, concrete, and useful. This repo is for hands-on local model serving work where bad assumptions can waste hours.

## Documentation Style

- Prefer executable, copy-paste-safe procedure only after the runtime path has been validated.
- Before giving a command that may run longer than 15 seconds or has multiple
  stages, state the approximate duration, expected prompts/target contact, live
  milestone behavior, and final result marker. Do not hand off a silently
  redirected long-running wrapper.
- Keep planning docs explicit about what is known, unknown, and not yet proven.
- Mark future experiments as follow-on work rather than implying they are current reset requirements.
- Keep implementation names service/domain meaningful outside this repo. Do not carry project, workstream, script, or agent labels into target-side systemd drop-ins, services, runtime directories, authority paths, policies, database objects, certificate labels, config names, transfer bundles, or operator-facing artifacts unless the object is explicitly historical repo/evidence material; follow `CODING_STANDARD.md` and `LAB_RUN_PATH_STANDARD.md`.
- For new executable scripts and master replay recipes, prefer portable action/product names instead of workstream-title basenames. Preserve already-existing historical names when renaming would break the evidence trail, registry, or accepted replay history.
- For off-the-shelf products, do not apply lab hardening/custom runtime posture before a vendor-supported first runtime proof unless a frozen exception explicitly approves it. Follow `CODING_STANDARD.md` Product First-Proof Before Hardening Standard.
- Do not force one service into another off-the-shelf product's bootstrap path before that product has a vendor-supported first runtime proof. For example, do not force OpenBao, PostgreSQL, an IdP, a CA, an artifact repository, reverse proxy, or observability stack into WSO2/OpenBao/Artifact Keeper/etc. startup merely because that service is selected elsewhere in the lab. Store source-of-truth material in the approved authority when frozen, then integrate through a later explicit integration/runtime-consumer decision.

## Decision List Format

This documentation contract and the operational freeze gate in
`AGENT_OPERATION.md` must remain aligned. Durable decision lists use the
Anderson-style `Purpose`, narrative `Current Status`, and `Decisions`
structure.

Use this format for every numbered decision item unless the operator explicitly asks for a different artifact:

```text
1. Item Name

   Decision: Decide the specific question being frozen or discussed.

   Status: Ready to freeze / Frozen / Open / Deferred / Blocked.

   Recommendation: State the recommended posture or action.

   Reason/Evidence: Explain why, citing repo evidence, script results, operator input, or reviewed source material.
```

- Number every recommendation or decision presented to the operator, even when only one recommendation or option exists, and use that number when requesting or recording approval.
- Use `Recommendation` singular even when it contains multiple related clauses.
- Do not replace the required fields with prose summaries, tables, or unlabeled bullets.
- Do not add standalone working-order lists, source registries, or commentary inside durable decision lists unless the operator explicitly asks for them; put source material and sequencing justification inside `Reason/Evidence`.
- Use `Ready to freeze` only when the recommendation is concrete enough for the operator to approve without more discovery.
- If evidence is missing, mark the item `Open` or `Deferred` and state the missing evidence in `Reason/Evidence`.
- When the operator freezes a decision item, update that decision list directly in the same pass: change each frozen item to `Status: Frozen.` and update the list's `Current Status`. Do not leave a decision list at `Ready to freeze` while relying on a separate evidence file, action-history note, or registry entry to carry the freeze. Separate freeze evidence files are optional historical/evidence artifacts only when they are already part of the local pattern; they do not replace the decision-list status.

## Repo Sweep Definitions

- A normal repo sweep may be scoped to a workstream, decision item, script, evidence record, or narrow stale-reference concern.
- A focused repo sweep is a scoped agreement review across the relevant control-surface files, decision lists, script registry entries, evidence records, and current-state docs for the named workstream/item. It is not just a text search; it must reason about stale assumptions, stale numbering, decision status, host/role bindings, runtime posture, security/advisory actions, and whether docs/scripts/evidence still agree.
- A holistic repo sweep is a specific repo-wide agreement review. When the operator asks for a holistic repo sweep, check every file in the repo for cross-workstream coherence, current-state accuracy, stale assumptions, stale numbering, stale host/role bindings, stale decision status, and agreement within and across workstreams. It is not limited to the current workstream or a single item.
- Use holistic repo sweeps to reduce repo drift and keep the repository tight, accurate, and coherent during long-running sessions and context compaction.
- Do not call a sweep holistic unless the review actually covered the whole repo surface or explicitly records any unreadable/excluded paths and why they were excluded.
