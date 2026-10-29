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

## Mandatory v1.3.2 patch register

The following items are mandatory release scope for v1.3.2. Their detailed
requirements and qualification evidence are defined in the corresponding
sections of this record. None may be omitted, weakened, or deferred merely
because another item passes independently.

1. **Clarification continuity:** replace prose-only clarification inference
   with bounded typed state; preserve the accepted task across replies and safe
   misses; offer only corpus-supported choices; and eliminate clarification
   routes that terminate in generic out-of-scope or insufficient-evidence
   responses without an accurate boundary explanation.
2. **Actionable stage diagnostics:** distinguish safe operator-facing causes
   such as no approved matching document, unresolved exact reference, weak
   relevance, failed reconstruction, or failed citation validation instead of
   collapsing them into one generic result.
3. **Visible release identity:** derive and display the exact packaged/runtime
   v1.3.2 identity in the UI and prove equality during qualification and
   rollback.
4. **Citation-card completeness:** render the complete cited structural
   section in a bounded independently scrollable card with visible scrollbar
   affordance; keep complete-document reconstruction behind the separate
   `View full document` control; never silently clip returned citation text.
5. **External corpus source root:** provide one explicit validated source-root
   configuration used consistently by inventory, configuration generation,
   ingestion, diagnostics, updates, and cleanup without copying, flattening,
   symlinking, or bind-mounting the authoritative corpus into the application
   tree.
6. **Operator-declared classification:** retain operator authority over
   `class_id`; never delegate authoritative classification to Gemma or silently
   replace the declared class.
7. **Document-family recognition:** add configurable deterministic policy, SOP,
   and manual layout profiles above the existing structural normalizer,
   including header/footer identity, configured aliases, searchable metadata,
   citable prose, non-citable furniture, and safe generic fallback behavior.
8. **Nested structural hierarchy:** preserve numbered and lettered ancestry
   across page boundaries and qualify deeply nested reconstruction and
   citation behavior.
9. **Relationship handling:** resolve source-backed associated-document
   references against exact normalized catalog identifiers across eligible
   classes; retain absent or ambiguous targets as explicit diagnostics without
   false binding or rejecting otherwise valid body ingestion.
10. **Image-only and mixed-scan gate:** distinguish true blank pages from
    substantive raster-only pages; quarantine image-only and mixed-scan
    documents without partial publication; keep OCR out of scope unless
    separately approved and qualified.
11. **Unified document identity:** replace the conflicting configuration,
    relationship, Retrieval API, and artifact-pipeline document-key grammars
    with one shared implementation used by every consumer. Preserve official
    filenames and remove manually maintained secondary filename-like identity
    from the operator workflow.
12. **Production-grade CSV intake:** accept supported spreadsheet-generated
    UTF-8 CSV with or without BOM and with LF or CRLF; reject malformed input
    precisely; normalize benign leading and trailing horizontal whitespace in
    metadata cells while preserving internal filename/display-name whitespace;
    fail explicitly if normalization creates an ambiguity or collision; and
    provide a supported template/workflow that requires no terminal editing of
    hidden characters.
13. **Complete one-pass preflight:** inspect the entire metadata and source
    inventory, report every safe failure together with row, field, and exact
    rule, and exercise every downstream identity consumer before extraction,
    model access, embedding, or database mutation.
14. **Initial and incremental configuration:** deliberately support both
    initial and later ingestion configuration instead of relying on an
    undocumented empty-catalog-only publication path.
15. **Atomic configuration and ingestion boundaries:** publish generated
    catalog/manifest state atomically, prove interruption cleanup, and ensure
    rejected input creates no partial files, chunks, embeddings, document
    versions, relationships, or PostgreSQL mutation.
16. **Synthetic Corpus v4:** retain all accepted v3 documents, reach at least
    60 active documents, add deeper policies plus SOP and manual families,
    cover at least eight overlapping operational domains, and qualify positive
    and negative extraction, hierarchy, relationship, retrieval,
    reconstruction, and citation cases.
17. **Versioned update and rollback:** ship a separately versioned,
    checksum-bound v1.3.1-to-v1.3.2 attended update bundle that preserves target
    configuration, corpus, credentials, and PostgreSQL data by default and
    proves rollback to the exact accepted baseline.
18. **Consolidated acceptance:** run native tests, realistic operator-ingestion
    tests, the complete frontier gate, fresh-install/update lifecycle tests,
    and attended human UI review against the exact release bytes. Qualification
    must report all safe failures in one run rather than creating sequential
    first-blocker patch cycles.
19. **Canonical administration and installation state:** provide one stable
    administrative entry point at the canonical installed application, retain
    non-secret installation state durably, and report whether database schema
    initialization is required or installation is complete. No required
    post-install action may depend on remembering or searching for an extracted
    carry directory.
20. **Operator-owned database credentials:** remove Ishikawa-specific password
    length, maximum-length, composition, and cross-role distinctness rules.
    Require the credentials needed by PostgreSQL, accept them through a clear
    attended hidden prompt or approved secret provider, and leave password
    strength and lifecycle decisions to the operator or deployment authority.
21. **Capability-based native prerequisites:** keep target package origin and
    advisory qualification in deployment, but validate runtime dependencies
    through real capability canaries. Application code must not contain one-host
    package revision allowlists that contradict supported deployment targets.
22. **Versioned artifact-profile registry:** replace duplicated or hardcoded
    extraction, normalization, embedding, and packaging method identities with
    one validated registry consumed by production, qualification, and release
    tooling. A stale profile or digest must fail before expensive work.
23. **Self-contained release test inventory:** bind the exact discovered tests
    and deployment harnesses to the release artifact. Eliminate hidden or
    undiscovered test files, copied newer test trees paired with historical
    hardcoded counts, and release claims that cannot be reproduced from the
    carried bytes.
24. **Single-carry release invariant:** every cumulative correction accepted
    before release publication must be rolled into the application archive and
    rebound through the SBOM, source manifest, security review, receipt,
    package manifest, and outer checksum. A fresh deployment must require one
    outer archive and its adjacent checksum—not an archive plus hotfixes.
25. **Complete configuration-drift coverage:** lifecycle drift detection must
    include every runtime-affecting YAML/profile, installed service/container
    state, and generated endpoint consumer. Recovery must be bounded when the
    managed process exists but its local state marker is missing or damaged.
26. **Capacity-bound execution and actionable heartbeat:** derive extraction,
    document-stage, model, and batch bounds from a documented capacity model;
    expose active stage and elapsed time; and distinguish a slow operation from
    a failed or unavailable dependency without losing the originating reason.
27. **Active-path and supersession registry:** designate current, superseded,
    and historical installers, qualifiers, promotion scripts, validators, and
    package builders in one authoritative record. Superseded paths may remain
    as evidence but cannot be selected accidentally as release interfaces.
28. **Exact-artifact update and rollback:** update qualification must exercise
    pristine, partial, idempotent, unknown-byte refusal, forced post-publication
    failure, and exact rollback. An update may alter only its enumerated files
    and may not overwrite unrecognized target state.

Explicitly deferred work is not silently included in v1.3.2: multilingual
English/Spanish document variants remain post-v1.3.2, and detailed
administrative-form/W-4 behavior follows the policy, SOP, and manual family
work. The v1.3.1 Tech Demo's one-time canonical-key workaround and fixed source
directory do not close or waive any item above.

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

## Citation excerpt overflow and visibility

The accepted v1.3.1 UI scrolls the citation rail as one list. An expanded
citation card grows with its excerpt content and does not provide an
independent internal scrollbar. During attended review, the operator observed
that expanded text can extend below the currently visible part of the rail and
can therefore appear unavailable even though the outer citation list remains
scrollable.

Ishikawa v1.3.2 must give each long expanded citation card a bounded,
independently scrollable cited-section region with a persistent visible
scrollbar affordance. The card displays the complete cited structural section
when the API can return that section within its exact excerpt boundary; it is
not the full reconstructed document. `View full document` remains the separate
control for loading the complete reconstructed document. No returned citation
text may be silently clipped.

Qualification must prove that:

1. every excerpt rendered in an expanded citation remains reachable by
   keyboard, pointer, and touch interaction at supported desktop and narrow
   viewport sizes;
2. focus and scroll position remain understandable when a card is opened,
   closed, or followed by `View full document`;
3. any nested scrollbar has a visible affordance and does not trap keyboard
   or wheel scrolling; and
4. long citations, multiple expanded citations, rail resizing, and the final
   citation in the list do not hide text or controls.

This is a v1.3.2 usability item and does not reopen or gate the accepted
v1.3.1 carry baseline.

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

## External corpus source-root configuration

The accepted v1.3.1 installed workflow fixes the corpus source root to
`$HOME/Documents/Ishikawa/corpus/source`. For the org-lab v1.3.1 baseline, the
operator explicitly accepts this defect and will copy only approved PDF
sources into that installed directory so the carry can proceed without
changing the accepted application bytes.

This workaround does not close the defect. Ishikawa v1.3.2 must provide one
explicit, validated external source-root selection that is honored consistently
by configuration generation, catalog and manifest generation, ingestion,
inventory validation, diagnostics, update preservation, and removal/cleanup
boundaries. The configured source root must not require copying, moving,
flattening, symlinking, or bind-mounting an operator's authoritative corpus
into the application tree.

Qualification must prove both an external flat PDF directory and an external
nested PDF tree, reject symlinks and inventory mismatches, and preserve exact
relative `source_path` values from `corpus_metadata.csv` through the generated
manifest and ingestion receipt.

## Diagnostic follow-up

For any recurrence, retain the content-safe diagnostics for each turn,
especially stage trace, scope outcome, resolved query identity, lane counts,
relevance reason, sufficiency reason, and selected group order. The screenshot
proves the stage-level inconsistency but cannot distinguish the final
`insufficient-evidence` reason without those diagnostics.

## Operator-declared document classification

Ishikawa v1.3.2 retains operator authority over document classification.
`class_id` is declared in `corpus_metadata.csv` and validated against the
configured active document classes. Neither Gemma nor another model may assign,
replace, or silently infer the persisted document class during ingestion.

Deterministic document-family recognition may validate that a declared class is
compatible with observed header, footer, layout, and identifier evidence. It may
report a precise mismatch or request operator correction, but it must not change
the operator's declaration. Model-generated classification may not become an
ingestion dependency or authoritative persisted metadata.

## Document-family recognition and structural hierarchy

The accepted structural normalization and chunking architecture remains the
foundation for v1.3.2. The character-window prototype retained in
`local/python3.txt` is assessment material only and is not an implementation
candidate. The release must preserve layout-aware extraction, atomic structural
units, exact source provenance, authoritative token measurement, PostgreSQL
persistence, and citation reconstruction.

The missing boundary is deterministic document-family recognition above the
existing structural normalizer. v1.3.2 must add configurable, versioned family
profiles selected and validated using the operator-declared class. A family
profile defines accepted identity fields, label aliases, header and footer
geometry, identifier grammar, and the division between searchable metadata,
citable source prose, and non-citable page furniture.

The family layer must:

1. recognize manual cover-page identity and confirm the body title without
   treating either as arbitrary body prose;
2. recognize the SOP first-page control header and every-page SOP footer;
3. support configurable field-label aliases without hard-coding one document's
   content;
4. construct nested structural paths for numbered and lettered hierarchy such
   as `II -> A -> 1 -> b`;
5. retain every source span and its physical page while excluding confirmed
   furniture from citable body chunks;
6. prevent an unsupported or unrelated footer family from being rejected merely
   because it contains a common component such as `Page N of M`;
7. fail closed on conflicting identity, page inventory, or family evidence once
   a complete declared-family pattern has been established; and
8. leave the accepted retrieval ranking, generation packing, and citation proof
   boundaries unchanged unless separately qualified.

### Manual family evidence frozen for v1.3.2

The observed selectable-text manual has the following cover order:

1. organization name;
2. department name;
3. manual context/title, represented by `Remote Work Guidelines` in the
   observed example;
4. division;
5. logo image;
6. formal organization name; and
7. name of the top-ranking organization official.

The logo is non-text visual furniture. Organization, department, division, and
manual context are structured identity metadata. The official name is
attribution metadata and is not automatically a retrieval-ranking signal. The
manual context appears again only on page 2, where it confirms the body title;
it is not repeated on subsequent body pages.

The cover has no page-number footer. Page 2 begins the numbered body and is
reported as page 2. Every body page uses one stable footer containing a manual
identifier, `Page N of M`, and a date; only `N` changes. The observed identifier
grammar is `MAN <department-abbreviation> <number>`, represented by
`MAN ## _ ####` in the sanitized operator description, where the variable
middle component is the department abbreviation. The current example contains
no table of contents, appendices, structured tables, or diagrams; the profile
must not assume those elements are absent from every future manual.

The observed hierarchy includes lettered, numbered, and lower-letter levels.
The normalizer must retain their ancestry rather than flattening them to one
active heading. Red blocks in operator photographs are photograph-only
sanitization; the operator is not aware of redactions in the source corpus.
This fact does not waive ordinary source validation or authorize recovery of
visually obscured text.

### SOP family evidence frozen for v1.3.2

The observed selectable-text SOP has a large control header on page 1 only. Its
identity/control fields include document type, effective date, review date,
procedure title, procedure number, department, authorized approval, and final
approval. Every page carries an SOP footer containing the SOP identifier,
`Page N of M`, and `For <organization> Use Only` text.

The observed identifier grammar is `SOP <department-abbreviation> <number>`,
represented by `SOP ## _ ####` in the sanitized operator description, where the
variable middle component is the department abbreviation. The SOP profile must
preserve nested purpose, definitions, procedures, and procedure-step hierarchy.
Approval blocks are control/attribution metadata and are not automatically
citable operational instructions.

### Policy family evidence frozen for v1.3.2

The observed common selectable-text policy layout uses a large control header
on page 1 only. Subsequent pages retain the organization name in the page
header. Every page, including page 1, carries a stable footer containing the
organization/policy identity, the complete policy identifier, `Page N of M`,
and `For <organization> Use Only` plus a stable date. The page number is the
expected changing footer value.

The common first-page body hierarchy includes Purpose, Mission, Policy,
Definitions, and nested numbered definitions. The hierarchy can continue
across a physical page boundary. A later body page can begin with the
continuation of a preceding nested item before introducing another lettered
section. The normalizer must preserve the active ancestry across page breaks
and must not treat a new page as an implicit structural reset.

The policy identifier has a common conceptual composition of chapter,
department abbreviation, and policy number, but the operator has observed that
some identifiers may contain additional segments. v1.3.2 must not encode a
fixed three-segment grammar. Exact catalog identifiers and normalized visible
document identifiers remain authoritative; permissible separator and spacing
normalization must not erase or invent segments.

The three-row policy control table appears consistent in the reviewed sample.
The department label has at least `Dept` and `Department` variants, but those
are not asserted to be exhaustive. `Applicability/Class` commonly resembles
`<organization name> / <class value>`, but neither vocabulary nor grammar is
known to be closed. The value must therefore be retained as bounded opaque
source-backed metadata unless a separately qualified vocabulary is provided.

Policy numbering commonly uses Roman numeral, uppercase-letter, numeric, and
lowercase-letter levels, but the exact markers and depths are not guaranteed
across the corpus. Structural ancestry must use marker style, source order, and
layout evidence rather than one frozen policy outline.

The observed `Associated Document(s)` section is a citable lettered structural
section whose numbered children identify related policies or forms. Entries may
contain a full policy identifier and title, only an identifier, or visible
hyperlink text. Each list entry must remain citable source prose and may also
produce a deterministic relationship candidate. Relationship resolution must
prefer exact normalized catalog identifiers and visible source text; an
embedded URI alone is not authoritative document identity. An absent,
ambiguous, or inactive target must remain an explicit unresolved relationship
diagnostic and must not silently bind to another document or reject otherwise
valid body ingestion.

Approval is commonly represented by a signature image. An unlabeled stamped
date may also appear near the control area. Images and unlabeled stamps are not
automatically citable prose or authoritative effective/review metadata. Only a
recognized labeled field or another separately qualified rule may promote such
content into structured control metadata.

The operator has reviewed only a subset of hundreds of policies. Tables,
appendices, embedded forms, procedure steps, additional label aliases, and
other numbering styles remain possible. The common policy profile must not be
treated as an exhaustive corpus schema.

### Frozen document-family decisions

The operator approved and froze the following decisions for the Ishikawa
v1.3.2 backlog on 2026-10-28. They are requirements, not implementation
suggestions, and may be reopened only through an explicit later decision.

1. **Multiple profiles per declared class.** One operator-declared `class_id`
   may support several deterministic layout profiles. A complete layout
   signature selects a profile but does not change the operator's class.
2. **Generic fallback and conflict posture.** When no specialized profile
   matches, Ishikawa uses generic structural normalization and emits a precise
   diagnostic. When a complete recognized profile contains conflicting
   identity or page evidence, the document is quarantined.
3. **Configured aliases.** Header and footer field-label aliases are stored in
   versioned configuration. Matching normalizes case, spacing, and terminal
   punctuation only. Fuzzy label matching is prohibited.
4. **Identifier matching.** Ishikawa preserves the exact source identifier and
   resolves visible references using the longest exact normalized match against
   active catalog identifiers. A fixed identifier segment count is prohibited.
5. **Associated-document relationships.** One `associated_document`
   relationship is independent of target class. A target may be a policy, SOP,
   manual, form, or another approved class. An unresolved relationship remains
   an explicit diagnostic and may be reconsidered during a later ingestion when
   an eligible target becomes available; it never silently binds.
6. **Cross-page hierarchy.** Nested structural ancestry remains active across a
   physical page boundary. Starting a new page does not reset the current
   section.
7. **Synthetic Corpus v4 minimum and depth.** V4 contains at least 60 active
   documents: all 30 accepted v3 documents, 10 additional policies that deepen
   existing topics, 10 SOPs, and 10 manuals. It covers at least eight
   overlapping operational domains. Documents generally span 3--9 pages and
   form meaningful cross-document relationship networks. Negative malformed
   fixtures are a separate rejection set and do not count toward the 60 active
   documents.
8. **Structural diversity.** V4 includes representative tables, appendices,
   form references, page-spanning sections, identifier-only links,
   identifier-plus-title links, absent targets, and ambiguous targets.

### Tracked v1.3.2 implementation follow-up

The following work remains durable v1.3.2 follow-up. It does not reopen the
frozen document-family decisions:

1. define and validate the versioned family-profile YAML schema;
2. preserve accepted `policy_sop` compatibility while adding distinct active,
   operator-selectable `policy` and `manual` classes and using separate policy
   and SOP layout profiles;
3. select at least eight Synthetic Corpus v4 operational domains and define the
   deeper document and relationship plan;
4. build and freeze the v4 truth set plus retrieval, relationship,
   reconstruction, and citation acceptance gates;
5. determine whether unresolved relationship diagnostics require a PostgreSQL
   schema migration or can use the accepted relationship representation;
6. specify and qualify administrative-form behavior after SOP and manual work;
7. design and qualify the separately versioned v1.3.1-to-v1.3.2 update bundle,
   attended update harness, rollback path, and target acceptance receipt; and
8. qualify the exact changed application, configuration, persistence, corpus,
   and runtime boundaries before v1.3.2 acceptance.

### Post-v1.3.2 multilingual document variants

The operator discovered Spanish versions of some documents while preparing the
first bounded black-corpus ingestion and explicitly deferred multilingual
support until after v1.3.2. Ishikawa v1.3.2 and Synthetic Corpus v4 are
English-only. Spanish documents are not part of their ingestion, qualification,
or acceptance scope.

The accepted metadata surface does not currently declare document language,
translation identity, language preference, or a translation relationship. A
translated document may also repeat the same organizational identifier and
effective version as its English source. Ingesting both without an explicit
contract could create ambiguous exact-identifier routing, duplicate-version
semantics, unpredictable retrieval language, and unclear citation presentation.

Until this boundary is separately frozen and qualified, the first bounded
ingestion must contain one language variant per organizational document. Spanish
PDFs that are not part of the bounded run remain outside the configured source
root and outside its metadata inventory.

Any later multilingual release decision must define:

1. an authoritative language field and allowlisted language values;
2. whether a translation is a separate document, a language variant of one
   document version, or both through distinct logical and version identities;
3. a source-backed `translation_of` or equivalent relationship;
4. exact-identifier behavior when multiple language variants share an
   organizational identifier;
5. query-language detection and explicit operator language selection;
6. retrieval preference, fallback, and cross-language behavior;
7. answer and citation-display language guarantees;
8. embedding-model and tokenizer qualification for every supported language;
9. handling of translated titles, departments, section headings, forms, and
   relationship references; and
10. a separately versioned multilingual synthetic corpus containing paired
    language fixtures and truth cases.

### Mandatory v1.3.2 image-only and mixed-scan ingestion gate

The first bounded black-corpus run contains 57 English documents and may
include both selectable-text PDFs and image-only or partially scanned PDFs.
The operator explicitly accepted proceeding with that v1.3.1 ingestion rather
than manually screening every source. Its result is therefore an extraction
inventory and operational trial; it is not evidence that every visible source
page was completely captured.

This records a confirmed v1.3.1 implementation defect. The extraction stage
can report a page with no Poppler-extractable words as blank, normalization can
accept that page, and chunking can emit a derived `page_status` candidate. The
pipeline does not currently distinguish a genuinely blank page from a page
whose substantive content exists only as raster imagery. A mixed document can
also expose a selectable header or footer while leaving a scanned body
unavailable. This behavior does not satisfy the documented fail-closed posture
for image-only PDFs.

Ishikawa v1.3.2 must correct this boundary before acceptance:

1. OCR remains out of scope unless separately designed, approved, and
   qualified. Ishikawa must never silently invent or infer image text.
2. Extraction must inventory text and meaningful raster/image evidence per
   page so that a true blank page is distinguishable from an image-only page.
3. An entirely image-only document must be quarantined under a stable,
   content-free reason such as `ocr_required_image_only_document`.
4. A mixed document containing a substantive image-only page must fail closed
   as a whole under a stable reason such as `ocr_required_mixed_document`.
   Partial publication is prohibited.
5. A selectable header, footer, page number, stamp, or other page furniture
   must not allow a scanned substantive body to pass the gate.
6. Genuine blank pages remain supported and may retain the accepted derived
   page-status behavior only when the page contains neither extractable text
   nor meaningful raster content.
7. Quarantine diagnostics and ingestion receipts must identify affected page
   numbers without copying sensitive document text.
8. Qualification must include an all-image one-page PDF, an all-image
   multi-page PDF, a selectable-footer/scanned-body PDF, a mixed
   selectable-text/image-only PDF, a genuine blank page inside a valid text
   document, and a text page containing only an ordinary logo or decorative
   image.
9. Synthetic Corpus v4 must include the corresponding positive and negative
   extraction fixtures and prove that rejected inputs create no chunks,
   embeddings, document versions, or partial PostgreSQL publication.

The 57-document v1.3.1 trial does not waive this v1.3.2 requirement and does
not qualify OCR-dependent documents as successfully ingested source material.

## Synthetic Corpus v4

The accepted Synthetic Corpus v3 remains immutable historical qualification
evidence. A new versioned Synthetic Corpus v4 will carry forward the v3 policy
families and add representative SOP and manual families. Existing v3 policies
may be revised only through explicit v4 source identities and truth records;
v3 source bytes and receipts are not overwritten.

Synthetic Corpus v4 must include:

- multiple SOP documents with first-page control headers, stable repeated
  footers, nested definitions, and ordered procedure steps;
- multiple manuals with cover identity, page-2 body-title confirmation, stable
  manual footers, and nested list/section hierarchy;
- department and division variation plus multiple valid identifier values;
- positive questions for title, identifier, department, division, purpose,
  definition, procedure, and deeply nested section retrieval;
- policy questions for Purpose, Mission, Definitions, Process, associated
  documents, identifier-only references, and identifier-plus-title references;
- relationship graphs containing policies and forms, including intentionally
  absent and ambiguous targets that must remain unresolved without false binds;
- negative fixtures for partial, malformed, conflicting, and cross-family
  header/footer evidence;
- page-inventory cases covering an unnumbered cover followed by page 2;
- proof that page furniture is excluded from citable body prose but retained as
  source-backed identity/control evidence; and
- complete extraction, normalization, chunking, retrieval, reconstruction, and
  citation-display qualification before v4 is promoted.

Administrative-form and W-4-specific expansion is explicitly deferred until
the SOP and manual family work has been specified and qualified.

## Mandatory v1.3.2 canonical administration correction

Ishikawa v1.3.1 correctly separates the verified deployment control plane from
the installed runtime, but its operator handoff is incomplete. Application
apply can pass before PostgreSQL schema initialization, while the required
`deploy-ishikawa install-schema` action remains available only from the
extracted carry directory. An operator working from
`$HOME/Documents/Ishikawa` can therefore reasonably believe installation is
complete and later encounter missing database roles during ingestion. Requiring
the operator to remember or rediscover the extracted carry directory is not an
acceptable installed interface.

Ishikawa v1.3.2 must correct this boundary without weakening package
verification or requiring operator-assembled script chains:

1. Provide one documented, stable administrative entry point reachable from
   the canonical installed application. Its use must not depend on the current
   working directory or continued presence of the extracted carry directory.
2. Persist a bounded, non-secret installation-state record atomically. At
   minimum, distinguish `schema_initialization_required` from `complete` and
   retain the exact application/package identity governing that state.
3. Never present application apply as completed installation while schema
   initialization remains required. The apply result and installed
   administrative status must print the exact next canonical command.
4. Keep schema initialization a one-time, attended, separately evidenced stage
   requiring the approved ingestion and retrieval credentials. Do not run it
   on ordinary application launch and do not store those credentials in the
   state record.
5. Reuse the accepted schema installer behavior: create the owner and login
   roles, `rag_catalog`, pgvector, schema v5, and grants as one bounded stage.
   Do not require manual SQL or an operator-created glue wrapper.
6. Detect an already compatible initialized database and report it accurately;
   fail closed on conflicting or partially initialized state rather than
   claiming completion or destructively reinstalling it.
7. Prove fresh apply-to-schema handoff, deletion of the original extracted
   carry, interrupted schema initialization, safe retry, compatible established
   installation, conflicting state, and ordinary restart without reingestion
   or schema reinstallation.
8. Keep the current v1.3.1 workaround and its corrected playbook ordering as
   historical operational guidance only. It does not close this product defect.

## Mandatory v1.3.2 operator-owned credential correction

Ishikawa v1.3.1 imposes a private database-password policy that PostgreSQL does
not require: both role passwords must contain 16 to 256 characters, contain no
control characters, and differ from one another. The schema action does not
prompt for them; it silently reads two environment variables and collapses a
missing value and every policy violation into `database_credential_invalid`.
This is an operator-interface and policy-ownership defect.

Ishikawa v1.3.2 must correct this boundary:

1. Remove Ishikawa-specific minimum length, maximum length, composition, and
   cross-role distinctness enforcement. Requiring a supplied credential for a
   password-authenticated PostgreSQL role remains valid; credential strength
   and rotation are the operator's or deployment authority's responsibility.
2. The canonical attended administrative action must request every required
   credential with an explicit hidden prompt when an approved secret provider
   did not supply it. It must not wait silently for an undocumented environment
   variable.
3. Accept credentials without logging, retaining, hashing into reports, or
   placing them on command lines. Transport them only to the bounded consumer
   and clear process-local values after the stage.
4. Report safe, specific reasons such as `credential_missing` or
   `credential_transport_invalid`; do not report an Ishikawa password-strength
   judgment or collapse unrelated conditions into `database_credential_invalid`.
5. Qualify short operator-selected credentials, equal credentials for distinct
   roles, attended prompting, approved environment/secret-provider input,
   cancellation, retry, and proof that output and receipts contain no secret.
6. This correction applies to installation, ingestion, retrieval startup,
   updates, and recovery wherever Ishikawa currently revalidates database
   credential content.

## Mandatory v1.3.2 operator-ingestion contract correction

The first bounded black-corpus configuration exposed an operator-hostile and
internally inconsistent identity contract in v1.3.1. The operator prepared the
required four-column metadata inventory from official filenames using Excel.
Configuration creation rejected ordinary operator input one condition at a
time, while later subsystems enforce different document-key grammars. This is
an Ishikawa defect, not a black-corpus defect.

The confirmed v1.3.1 contradictions are:

1. the configuration creator and YAML validators accept only lowercase
   document keys but permit a leading digit, repeated separators, and trailing
   separators;
2. relationship processing requires a lowercase letter as the first character,
   so a numeric-leading key can pass configuration and fail during publication;
3. Retrieval API contracts reject repeated or trailing separators that the
   configuration creator accepts;
4. the artifact pipeline accepts uppercase identifier characters that the
   operator configuration path rejects;
5. the creator reports coarse reason codes without the row, field, rejected
   value, or governing rule; and
6. its retained self-test uses only a small lowercase LF fixture and therefore
   does not exercise realistic Excel CSV input, official filenames, numeric
   identifiers, or the complete configuration-to-relationship-to-retrieval
   path; and
7. the installed ingestion wrapper collapses distinguishable runtime
   dependency failures—including PostgreSQL not running, database or role
   absence, invalid `rag_ingest` credentials, schema mismatch, and insufficient
   privilege—into the non-actionable reason `runtime_failure`.

The v1.3.1 Tech Demo may use one explicitly accepted, one-time canonical-key
workaround in `corpus_metadata.csv`. Official source filenames and
`source_path` values remain unchanged. This workaround does not close or waive
the defect.

Ishikawa v1.3.2 must correct the complete boundary before acceptance:

1. Define one document-key contract in one shared implementation and use it in
   metadata creation, restricted-YAML validation, planning, persistence,
   relationship discovery, Retrieval API requests/responses, routing,
   document viewing, and artifact adaptation.
2. Preserve official filenames and operator-visible source identities exactly.
   The operator must not be required to rename source documents or manually
   maintain a second filename-like identity. If an internal identifier remains
   necessary, Ishikawa generates it deterministically and does not expose it as
   additional operator data entry.
3. Accept ordinary standards-compliant UTF-8 CSV created by supported office
   tools, including UTF-8 with or without BOM and LF or CRLF line endings.
   Reject malformed encodings explicitly. Normalize benign leading and
   trailing horizontal whitespace in individual metadata cells before field
   validation while preserving internal whitespace. Record that normalization
   occurred without exposing protected values, and fail closed with the exact
   row and field if normalization creates a duplicate, identity collision, or
   source-path ambiguity.
4. Validate the complete metadata file in one pass and report every discovered
   problem together. Each diagnostic identifies the CSV row, field, safe
   rejected value or value digest, and exact expected rule without exposing
   document content.
5. Preserve exact source-inventory equality and fail-closed publication, but
   distinguish missing files, unlisted files, non-PDF entries, symlinks,
   duplicates, and normalized-identity collisions in actionable diagnostics.
6. Support both initial and incremental operator configuration deliberately.
   Do not rely on an undocumented empty-catalog-only publication restriction.
7. Run every downstream identity consumer during preflight before document
   extraction, embedding, or PostgreSQL mutation. A key accepted by preflight
   cannot later be rejected by relationships, retrieval, or citation display.
8. Keep the operator-declared `class_id` contract. An active `policy` class is
   valid and must not be silently remapped to `policy_sop`.
9. Treat generated catalog and manifest publication as one atomic transaction,
   with no partial target files after failure or interruption.
10. Provide a documented metadata template and a supported creation workflow
    that does not require hand-editing hidden characters or manually deriving
    identifiers in a terminal editor.
11. Run deterministic ingestion-runtime preflights before planning or document
    processing and report separate safe reason codes for PostgreSQL service or
    connection failure, database absence, role absence, authentication failure,
    schema mismatch, and insufficient privilege. Never reduce these conditions
    to `runtime_failure`; do not expose credentials or protected corpus values.

The consolidated v1.3.2 gate must start from freshly copied official-style PDF
filenames and realistic spreadsheet-produced metadata. It must cover uppercase
and numeric organizational identifiers, spaces and punctuation in source
filenames, BOM/no-BOM, LF/CRLF, nested source paths, duplicate and collision
cases, initial publication, incremental publication, relationship discovery,
exact identifier routing, Retrieval API filtering, document reconstruction,
and citation display. It must also exercise inactive PostgreSQL, missing
database and role, incorrect ingestion credentials, schema mismatch, and
insufficient privilege and require the corresponding distinct safe reason for
each. The gate must collect all safe preflight failures in one run and prove
that rejected input performs no extraction, model call, embedding, database
mutation, or partial configuration publication.

## Mandatory v1.3.2 extraction-dependency contract correction

The first black-corpus publication exposed a host-specific Poppler revision
allowlist inside the application extractor. Tech correctly provided installed
Poppler tools from its qualified platform, but publication failed before
extraction because the application accepted only two Ubuntu 24.04 package
revision strings. Deployment inventory and application runtime validation had
therefore encoded contradictory platform contracts.

Ishikawa v1.3.2 must:

1. keep package origin, architecture, advisory, and prerequisite qualification
   in the deployment boundary rather than hardcoding host package revisions in
   the corpus extractor;
2. require `poppler-utils`, `pdfinfo`, and `pdftotext` to be installed and
   executable, record their exact identities, and require one coherent Poppler
   tool version without imposing a distribution-specific revision string;
3. run a real selectable-text PDF extraction and repeatability canary during
   deployment preflight, before corpus planning, embedding, or publication;
4. retain the existing per-document extraction, page-count, blank-page,
   repeatability, and fail-closed publication checks as the authoritative
   runtime proof;
5. report dependency provenance failure, missing tool, mixed tool versions,
   extraction failure, and repeatability failure as distinct safe reasons; and
6. qualify every supported target platform through the same end-to-end canary
   rather than expanding a source-code allowlist for each host release.

The first bounded v1.3.1 Tech hotfix changed only this extractor contract. It
was superseded before acceptance by the single cumulative black-corpus update
described in the v1.3.1 end-to-end audit. No standalone Poppler, header, or
footer archive is an accepted carry artifact.

## Mandatory v1.3.2 end-to-end ingestion and release correction

The cumulative v1.3.1 audit found additional cross-stage assumptions that must
not become permanent product contracts. Ishikawa v1.3.2 must:

1. size extraction retention from the actual document inventory and retain one
   authoritative extraction result plus repeatability evidence, rather than
   archiving two complete extraction trees per document;
2. derive document-stage and batch timeouts from a documented capacity model,
   expose the selected bounds in diagnostics, and test a full supported batch;
3. treat credentials as protected transport values and impose only
   externally-authorized password rules;
4. preserve safe, stage-specific ingestion failures through every wrapper
   instead of collapsing them to `runtime_failure`;
5. make specialized header and footer profiles opt-in on complete evidence,
   fall back to generic furniture normalization for incomplete or unknown
   profiles, remove only lines proven to be profile components, and continue
   to fail closed on complete conflicting identity evidence;
6. normalize recurring `Page N` and `Page N of M` furniture without treating
   either form as citable body prose;
7. bind the complete discovered test inventory into every release artifact and
   execute tests shipped with or checksum-bound to that artifact; a historical
   script must not copy a newer repository test tree and then require an old
   hardcoded module or test count;
8. identify active, superseded, and historical deployment paths explicitly.
   Superseded qualification, promotion, package, and hotfix paths must not be
   presented as current operator interfaces;
9. include every runtime-affecting YAML/profile in lifecycle drift detection
   and provide bounded state recovery when a managed service or container
   exists but its local state record is absent or damaged;
10. replace hardcoded artifact-method profile digests with one versioned,
    validated profile registry shared by production and qualification; and
11. qualify one changed document through extraction, normalization, chunking,
    embedding, atomic PostgreSQL publication, retrieval, reconstruction, and
    citation display using the exact installed bytes before release acceptance.

The v1.3.2 gate must prove these requirements in one consolidated run. A
successful source-tree unit suite, a historical receipt, or a focused hotfix
verifier is not sufficient on its own.

## Audit-residual disposition

The 2026-10-28 v1.3.1 end-to-end audit separated immediate release corrections
from permanent product work. The seven-file cumulative v1.3.1 correction fixes
only the bounded Poppler capability, extraction retention, timeout, credential
transport, generic header/footer fallback, page-furniture, and failed-stage
propagation defects needed for the Tech Demo. It does not close any permanent
item in this register.

The following audit findings therefore remain mandatory v1.3.2 scope and may
not be lost when the release is decomposed into implementation tasks:

- spreadsheet-safe metadata intake and all-error preflight;
- one document identity contract across every consumer;
- explicit external corpus source roots;
- OCR/mixed-scan detection and quarantine;
- policy, SOP, and manual family profiles plus nested hierarchy;
- clarification continuity and corpus-backed choices;
- independently scrollable complete cited sections;
- operator-owned credential policy;
- one canonical administrative interface and correct schema-before-ingestion
  ordering;
- capability-based dependency canaries and platform-neutral validation;
- one profile registry, complete configuration drift coverage, and precise
  stage diagnostics;
- self-contained discovered tests and whole-path release qualification;
- explicit current/superseded path selection;
- exact update/rollback proof; and
- one final carry archive with every accepted correction already incorporated.

Detailed administrative-form handling and multilingual English/Spanish
variants remain explicitly deferred beyond v1.3.2 unless separately approved.
