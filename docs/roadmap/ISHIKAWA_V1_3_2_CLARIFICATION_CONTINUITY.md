# Ishikawa v1.3.2 Clarification Continuity Investigation

## Purpose and release posture

This record preserves a functional defect discovered during operator testing
after acceptance of Ishikawa v1.3.1. It is scoped as candidate work for
v1.3.2. It does not amend the accepted v1.3.1 bytes, authorize an implementation,
or reopen the v1.3.1 org-lab carry.

The accepted v1.3.1 build may be carried and installed as the current baseline.
Any correction described here must receive its own version identity, tests,
qualification evidence, update bundle, and operator acceptance before it may
replace that baseline on Tech.

## Operator-observed failure

The observed conversation followed this pattern:

1. Ishikawa asked which IT software or system required administrative access.
2. The operator asked what types of software were available.
3. Ishikawa classified that contextual question as outside supported scope.
4. The operator restated the request as an organizational IT-access question.
5. Ishikawa asked the operator to choose among examples including
   infrastructure, application, or security tools.
6. The operator selected security tools.
7. Ishikawa returned `insufficient-evidence` without explaining that its own
   suggested category had not been proved against the corpus.

This is an unacceptable conversational dead end. If Ishikawa asks the operator
to select a category, a valid selection must remain bound to the original task
and must either continue through a supported evidence path or produce a precise,
useful explanation of the unsupported boundary.

## Confirmed implementation findings

### 1. Browser history is present

The web client serializes a bounded alternating conversation into every chat
request. The failure is not explained by the browser omitting earlier turns.

### 2. Scope executes before clarification-aware query resolution

The Retrieval API independently scope-classifies every new operator message.
An `out_of_scope` or scope-level `needs_clarification` decision returns before
query resolution or retrieval. Consequently, a short answer to Ishikawa's own
clarification can be rejected before the clarification-aware resolver has an
opportunity to reconstruct the original task.

### 3. Clarification is inferred from prose, not retained as typed state

The query resolver recognizes a clarification only from the immediately
preceding user/assistant pair and only when the assistant text ends in a
question mark. It may combine that prior task with the new answer, but this
logic runs only after scope permits the turn. An intervening error or unrelated
assistant message breaks the chain. No durable pending-clarification object
records the original accepted task, requested dimension, valid answer shape,
or evidence boundary.

### 4. Clarification suggestions are not corpus-proved

Both scope and query-resolution clarification can be produced before evidence
retrieval. Examples offered in a clarification therefore may be plausible model
language rather than categories derived from authoritative document metadata or
retrieved evidence. A later retrieval can correctly fail closed for a category
that Ishikawa itself suggested, creating the observed bait-and-switch behavior.

### 5. The final answer model is not the failing component

When deterministic sufficiency returns anything other than `sufficient`, the
service returns the safe error immediately. Answer-generation Gemma is not
called. The visible `Not enough evidence` result can represent multiple reasons,
including no candidates, no authorized evidence, an unsatisfied exact or
relationship constraint, no reconstructable evidence, an invalid citation set,
or insufficient relevance. The current operator message collapses those
distinct states into one generic result.

### 6. Existing tests do not prove the complete conversational promise

Component tests cover scope outcomes, clarification-only returns, immediate
clarification-task preservation, retrieval blocking, and sufficiency. They do
not prove the end-to-end invariant that a category offered by Ishikawa is
corpus-supported and that selecting it preserves the accepted task through
scope, resolution, retrieval, and evidence qualification.

## Root cause

Clarification is currently a message, not a state transition. Multiple model
and deterministic gates reconsider the next message independently. The system
has no enforced contract connecting:

- the original in-scope operator task;
- the question Ishikawa asked;
- the answer shapes Ishikawa invited;
- the corpus evidence that can support those answers; and
- the reconstructed query evaluated by retrieval and sufficiency.

This permits a clarification producer to offer a route that later gates cannot
honor.

## Required v1.3.2 behavior

The v1.3.2 design should satisfy all of these behavioral requirements without
weakening citation validation or evidence sufficiency:

1. Represent a pending clarification as typed, bounded state containing the
   original accepted task, clarification origin, requested dimension, and safe
   answer constraints.
2. Bind the next operator reply to that pending task before ordinary standalone
   scope classification. Evaluate the reconstructed task; do not treat the
   fragment as unrelated general knowledge.
3. Derive enumerated clarification choices from trusted PostgreSQL metadata or
   qualified retrieved evidence. Do not offer model-invented categories as if
   they are known corpus options.
4. If a corpus-backed enumeration is unavailable, ask an open clarification
   that does not imply a known catalog, or state that the available documents
   do not define such a catalog.
5. Preserve the original task across one or more valid clarification turns and
   across a safe, recoverable miss. Do not rely solely on the last message
   ending with `?`.
6. Keep fail-closed sufficiency. When evidence remains insufficient, distinguish
   the operator-facing boundary: no matching approved document, weak relevance,
   unresolved exact reference, or another safe actionable class. Never expose
   protected content or internal implementation detail.
7. Make equivalent first-turn and clarified requests route consistently.
8. Keep the application corpus-agnostic. Do not hard-code software names,
   security-tool taxonomies, departments, or synthetic-corpus values.

## UI release-version visibility

Ishikawa v1.3.2 must show its product version in a persistent, unobtrusive UI
location such as the application footer or an always-available About/status
surface. An operator must be able to confirm that the running browser UI is
`Ishikawa v1.3.2` without inspecting containers, files, logs, or network
responses.

The displayed value must come from the same release identity used by packaging
and runtime qualification. Do not maintain an independent UI-only version
literal that can drift from the installed release. The display must reveal no
hostname, account, path, environment name, commit history, or other deployment
detail.

Qualification must prove that:

1. the exact installed v1.3.2 bytes visibly display `Ishikawa v1.3.2`;
2. the packaged release identity, runtime identity, and displayed identity are
   equal, with a mismatch failing before acceptance;
3. a fresh production build and attended browser review both verify the value;
   and
4. the v1.3.1-to-v1.3.2 updater changes the displayed identity as part of the
   same atomic application update and restores the prior identity on rollback.

## Qualification requirements

Before acceptance, one consolidated v1.3.2 qualification path must:

1. Reproduce the exact observed conversation and prove there is no
   `out-of-scope` or generic dead end after a valid clarification reply.
2. Test both corpus-supported and deliberately unsupported offered categories.
3. Prove that every enumerated option came from trusted metadata or qualified
   evidence available in that request.
4. Test short replies, restated replies, multi-turn clarifications, intervening
   safe errors, and repeated equivalent questions.
5. Retain the original task when the reply is only a category such as
   `security tools`.
6. Prove the exact final sufficiency reason and selected evidence groups in
   retained, content-safe diagnostics.
7. Run all native tests, the complete frontier gate, fresh-install lifecycle
   tests, and attended human UI review against the exact release bytes.
8. Confirm that strict citation validation, corpus isolation, PostgreSQL-only
   authoritative state, and the accepted security boundaries remain unchanged.

## Update and Tech deployment boundary

Development and qualification should occur on DankoSurface. Updating an
accepted Tech installation should use a separately versioned, checksum-bound
update bundle and an attended update harness rather than ad hoc file copying.
The update contract should:

- require and verify the exact accepted v1.3.1 baseline identity;
- carry the v1.3.2 application delta or replacement archive and its complete
  manifest, checksums, SBOM/advisory disposition, and qualification receipt;
- carry a new generic runtime image only if reviewed runtime or dependency bytes
  changed;
- preserve target YAML configuration, corpus sources, catalogs, manifests,
  credentials, and PostgreSQL data by default;
- run a database migration only when an explicit, versioned migration is part
  of the release, and never re-ingest merely because the application restarts;
- stop the accepted service only at the bounded switchover point;
- verify configuration, schema compatibility, service readiness, retrieval,
  and a focused behavioral canary before acceptance;
- retain the prior exact application/runtime bytes and provide a tested rollback
  path; and
- emit one content-safe receipt identifying baseline, target, actions, tests,
  cleanup, and final state.

The concrete update format and harness remain a separate design/freeze item.
This investigation authorizes neither implementation nor target mutation.

## Diagnostic follow-up

For any recurrence, retain the content-safe diagnostics for each turn,
especially stage trace, scope outcome, resolved query identity, lane counts,
relevance reason, sufficiency reason, and selected group order. The screenshot
proves the stage-level inconsistency but cannot distinguish the final
`insufficient-evidence` reason without those diagnostics.
