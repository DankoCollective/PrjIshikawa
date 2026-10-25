# Phase 28 Chunking, Ingestion, and Retrieval Method Baseline

Date: 2026-10-18
Last updated: 2026-10-18

## Purpose

Establish the reviewed Anderson assessments as inputs to the Phase 28-owned
chunking, ingestion, and retrieval method. This record preserves what is
useful in those assessments, corrects known reconciliation errors, separates
evidence from recommendations, and records the decisions still required
before implementation.

Phase 28 owns the method decisions, implementation artifacts, retrieval API
contract, and Knowledge Assistant integration. Anderson supplies assessment
evidence and proposed designs; it is not the implementation authority.

## Status

**ADOPTED BASELINE; METHOD DESIGN INCOMPLETE; VALIDATION NOT RUN.**

The operator selected the Anderson assessment and synthetic corpus as Phase
28 inputs on 2026-10-18. The baseline fixes the corpus facts and general design
direction below. It does not accept generated implementation code, claim that
ingestion or retrieval has run, or freeze every proposed default.

The retained private black-corpus marker identifies its second Anderson
assessment as the best current requirements-and-design reference and rejects
its generated source as an implementation baseline. A separate later
synthetic-corpus response reported `artifact_plan_scope_coverage_invalid`; its
candidate was truncated, its review repaired the assessment through section
10, and its requested follow-on implementation plan was never delivered.

## Evidence and Provenance

The baseline was reconstructed from these local Phase 24 materials:

- request `bbea6e0b-f4b5-446f-96f3-a59af518855f` candidate and reviewed repair
  under `phase-24-anderson/Review/`;
- the associated synthetic-corpus forensic session beginning with the
  operator-authored synthetic-corpus README;
- the ignored local synthetic fixture set under
  `phase-24-anderson/syntheics/`;
- the ignored canonical synthetic package under
  `local/artifacts/org_lab/synthetic_corpus_v1/`, including its manifest,
  generation validation, held-out ground truth, and retrieval cases; and
- `phase-24-anderson/templates/corpus-assessment/README.md`, which defines the
  stronger assessment, disclosure, interface, failure, and validation
  requirements that the short reviewed output did not fully satisfy.

The separate CFR assessment sessions are not the authority for this baseline.
The private or ignored source material remains outside Git. Phase 28 promotes
only reviewed, neutral, content-free conclusions from those inputs.

## Authority and Evaluation Relationship

Phase 28 shall use the inputs in this order:

1. **Primary requirements context:** the marked-best black-corpus Anderson
   assessment. It describes the real corpus structure and relationships in
   sanitized form.
2. **Safe implementation and evaluation fixture:** Synthetic Corpus V1. It
   intentionally mirrors the sanitized topology without source-corpus text and
   supplies held-out structural truth, relationships, retrieval cases, and an
   abstention case.
3. **Secondary design critique:** the later Anderson assessment of the
   synthetic PDFs. Its finer structural distinctions and proposed chunk sizes
   are hypotheses to test, not replacements for the primary taxonomy or held-
   out truth.
4. **Rejected implementation input:** generated source from either handoff.
   It may reveal requirements and risks, but Phase 28 shall not copy or treat
   it as validated code.

The black-corpus assessment therefore answers what the method must preserve.
The synthetic package supplies safe, repeatable evidence for determining
whether Phase 28 preserved it.

## Local Black-Box Input Review

The ignored local `org_lab/black_box` area contains two Anderson generated-
output handoffs and a retention marker. That marker identifies the second
assessment as the best current requirements-and-design reference and states
that its generated source is not accepted as an implementation baseline. Its
recorded handoff-manifest SHA-256 is
`02242e23c10198b3e5cce451d373a95c5e8dc84e1bb663a759148f581384890c`.

The handoff is useful as private input for these design concerns:

- the real corpus evidence supports two primary document classes,
  policy/procedure and administrative form, reinforcing the need for an
  extensible class registry and structure-aware processing;
- source layout, page anchors, hierarchy, form associations, and cross-
  document identifiers must survive processing;
- document, chunk, provenance, version, and citation contracts must be
  explicit;
- ingestion needs staged failure handling, quarantine, and atomic publication;
- retrieval should evaluate lexical plus vector candidates, fusion,
  reconstruction, citations, filtering, and abstention; and
- validation must cover extraction, boundaries, relationships, citations,
  retrieval quality, and failure recovery.

The generated implementation is rejected as reusable source because static
review found material conflicts with the Phase 28 baseline:

- extraction is simulated with hard-coded sample results rather than reading
  and verifying source files;
- classes and metadata are hard-coded to two corpus-specific shapes instead
  of using an extensible registry;
- normalization contains simulated hierarchy, values, and unknown fallbacks;
- chunk and document identities are not defined by a stable, versioned
  derivation contract;
- embedding includes mock and external-provider paths rather than the target
  local embedding contract;
- persistence is process-local memory, so ingestion and a later query process
  do not share an authoritative index;
- the validation methods contain empty test bodies marked `NOT_RUN`;
- operator paths and query content are written to logs despite the content-
  free observability requirement;
- at least one operator entry point contains an obvious invalid method call;
  and
- dependency, retention, encryption, threshold, and production-store choices
  are asserted without Phase 28 decisions or execution evidence.

Neither handoff shall be copied into tracked source. Phase 28 may reuse its
neutral requirements, component boundaries, risks, and test obligations only
after reconciling them with this baseline and target-environment evidence.

## Corrected Corpus Reconciliation

**EVIDENCE:** Synthetic Corpus V1 contains six PDF documents and 27 pages. Its
generator manifest and held-out ground truth define five policy/SOP documents
and one administrative form. One policy/SOP fixture has an intentionally blank
first page. The package's generation check recorded the expected page counts
and blank-page result using `pypdf 6.16.2`; that proves fixture generation, not
the future Phase 28 extraction path.

| Neutral document | Primary document class | Structural test profile | Pages |
|---|---|---|---:|
| `SYN-001` | Policy/SOP | Hierarchy and cross-document references | 3 |
| `SYN-002` | Policy/SOP | Blank page and decision-table geometry | 2 |
| `SYN-003` | Policy/SOP | Repeated page furniture and semantic boundaries | 5 |
| `SYN-004` | Administrative form | Spatial fields, checkbox state, and multi-page continuity | 2 |
| `SYN-005` | Policy/SOP | Long three-level hierarchy and repeated page furniture | 11 |
| `SYN-006` | Policy/SOP | Ordered procedure, conditional branch, and list preservation | 4 |

**CORRECTION:** The marked-best black-corpus assessment and the canonical
synthetic ground truth agree on two primary document classes. The later
synthetic assessment's Policy, Matrix, Form, Manual, and Procedure labels are
useful processing-profile proposals, not the authoritative document taxonomy.
Phase 28 must separately model document classification and structural
processing behavior.

**PHASE 28 VALIDATION NOT RUN:** Table geometry, form layout, reading order,
page anchors, and Phase 28 Poppler extraction still require comparison with
the synthetic ground truth. An empty extracted page in an arbitrary source
must remain unknown until source or fixture evidence establishes why it is
empty.

## Adopted Method Direction

The following is the durable starting direction. It may be refined by explicit
decision, but an implementation must not silently discard it.

1. **Common structure-aware processing.** One generic fixed-size splitter is
   insufficient for hierarchy, tables, forms, long documents, and procedures.
   The general method recognizes implemented common structures independently
   of the operator-assigned document class.
2. **Preserved relationships.** Cross-document definition, decision,
   governance, and record relationships must survive ingestion and be
   addressable during retrieval.
3. **Atomic structural units.** Definition blocks, matrix rows, form
   field-value units, governance/control blocks, and procedural steps are
   candidate non-splittable units.
4. **Reconstructable context.** Chunks must retain the hierarchy, headers,
   labels, sequence, or breadcrumbs needed to interpret an atomic unit.
5. **Stable provenance.** Every retrievable unit must map deterministically to
   a source document, source location, document class, processing profile,
   document version, and ingestion version.
6. **Class- and profile-aware retrieval.** Retrieval must support metadata filters,
   relationship-aware expansion, neighboring context, citations, and
   abstention.
7. **Hybrid retrieval candidate.** Lexical and vector retrieval with the
   frozen rank-based fusion contract is the baseline design direction; exact
   package versions and numeric parameters require qualification under the gap
   ledger.
8. **Fail-closed ingestion.** Invalid or incomplete documents and chunks must
   not be partially published into the active corpus.
9. **Content-free operations.** Routine errors, metrics, and tracked evidence
   must not expose corpus content or organizational identifiers.
10. **Evidence before claims.** All extraction, ingestion, retrieval, security,
    and quality results begin as `NOT RUN` until supported by captured
    execution evidence.

## Frozen Decisions

### D01: Authoritative Operator-Assigned Classification

For the first implementation, the operator assigns exactly one document class
to each source in the ingestion manifest. The assigned class must exist in the
versioned class registry. A missing or invalid assignment fails manifest
validation before document processing; the method shall not guess or silently
default a class.

The operator assignment is authoritative. Automatic content-based
classification is not required. A future classifier may offer a suggestion,
but it cannot replace the assigned class, control publication, or become part
of the accepted method without a separate reviewed amendment.

The same source bytes, class registry, ingestion manifest, and method version
shall produce the same assignment result. This preserves deterministic
processing without requiring a classification engine.

### D02: Simple Class Registry and Ingestion Manifest

The versioned class registry is a small allowlist of document-class entries.
Each entry contains a stable neutral `class_id`, display name, and status. The
initial registry contains Policy/SOP and Administrative Form. An operator may
add a class such as Regulation by adding one valid registry entry and then
using that `class_id` in the ingestion manifest.

The versioned ingestion manifest declares each source-document path and its
assigned `class_id`. It may also carry separately schema-approved document
identity or display metadata, but it does not define detection algorithms,
rule weights, confidence states, metadata extractors, or custom chunking
behavior. The validator rejects missing paths, duplicate declarations,
unknown classes, unsupported source formats, and incompatible schema
versions.

All supported PDFs use the common extraction and structure-aware chunking
method. Adding an ordinary class label is a configuration change and does not
require code. A code and test change is required only when quarantine evidence
shows that the common method needs a new structural behavior, metadata field,
or reference format. Changing an existing document's assigned class requires
reprocessing that affected document into a candidate corpus; unrelated
documents are not reprocessed solely because another class was added.

### D03: Native-First, Minimal-Dependency Implementation

Implementation shall prefer, in order:

1. the language standard library;
2. mature tools or libraries already supplied and supported by the target
   operating-system distribution;
3. an already approved and pinned project dependency; and
4. a new dependency only when a documented requirement cannot be met safely
   and correctly by the first three choices.

For example, an available distribution-provided Poppler utility is preferred
for PDF text and page-metadata extraction over adding a Python PDF package
solely to duplicate that capability. Availability alone is not proof of
fitness: unsupported visual structure, image-only content, malformed input,
or security/resource limits must produce an explicit fallback, source-review,
or quarantine result rather than a false success.

Every new dependency requires a recorded purpose, rejected native
alternative, version/source, license and advisory review, offline packaging
plan, failure boundary, and validation evidence.

### D04: Supportability and Clarity

The implementation shall favor small explicit components, typed or validated
data contracts, direct control flow, and stable content-free failures over
framework or abstraction depth. Comments shall explain invariants, safety
boundaries, non-obvious transforms, and reasons for decisions instead of
restating syntax. Operator documentation shall explain inputs, outputs,
configuration, examples, recovery, and validation in language support staff
can follow without reconstructing the code.

### D05: PDF Extraction Capability Boundary

The first vertical slice shall accept PDF sources only. Phase 28 shall define
a stable extraction adapter and select the smallest native-first toolchain that
proves it can satisfy the adapter against the held-out synthetic truth.
Poppler is a known available candidate on org-lab Tech; it is not mandated.

The selected extractor and exact version are part of the versioned method
profile. A tool or version change requires extraction requalification and, if
its normalized output changes, candidate reingestion before promotion.

Every accepted extraction shall produce or preserve:

- immutable source bytes and source SHA-256;
- exact extractor/tool identity and version;
- declared and observed document/page inventory;
- page-anchored raw text, including explicit empty-page observations;
- layout-aware structural observations sufficient to test reading order,
  tables, forms, fields, checkboxes, hierarchy, and citations;
- raw extractor outputs before normalization; and
- content-free execution status, timing, warning, and failure categories.

An external tool shall be invoked without a shell and with explicit arguments,
bounded input and output size, timeout, temporary storage, and cleanup.
Malformed, encrypted, unreadable, or resource-limit-exceeding inputs shall be
quarantined. Image-only pages are unsupported and require source review in the
first vertical slice; OCR is not added without evidence of a requirement.

Table and form geometry are required validation cases. If the selected
extractor cannot preserve the associations required by held-out truth, Phase
28 shall block publication and evaluate the smallest reviewed fallback under
decision `D03`. It shall not silently flatten or index structurally ambiguous
material.

### D06: Structured Tables with Row-Level Retrieval

Every accepted table shall have a canonical structured record containing
stable table, row, column, and cell identities; document and page anchors;
table context; ordered headers; raw cell values; row and column spans;
continuation state; and available source geometry. The structured record, not
a flattened paragraph or generated summary, is the normalized authority.

A complete decision or data row is the minimum independently returned table
result. Individual cells may contribute exact lexical match evidence, but
shall not be returned without their row, ordered headers, table context, and
source anchors. A condition/action row shall remain together so retrieval
cannot separate a condition from its associated outcome.

Phase 28 shall derive deterministic retrieval projections from the canonical
record:

- one table-context projection containing its neutral identity, containing
  section, caption when available, and ordered headers;
- one row projection containing header-value pairs plus table context; and
- exact lexical fields for identifiers, labels, numeric values, and boolean
  states.

Table retrieval shall combine exact lexical and semantic vector candidates
under the later hybrid-retrieval and fusion decision. When a row matches,
reconstruction shall include its headers and containing table context. The
default adjacent-row expansion is zero. Neighboring rows are added only when
an explicit continuation relationship or query intent requires them;
comparison questions retrieve relevant rows directly rather than receiving
incidental neighbors.

Rows remain atomic when they fit the accepted bound. An over-size row may be
divided only at a deterministic nested-list or paragraph boundary that does
not separate associated conditions, values, or outcomes. Every part shall
repeat the required headers and context and share the original row identity
plus ordered continuation identities. If no safe boundary exists, the row may
remain over the target up to the hard safety ceiling; a row beyond that
ceiling blocks publication for source review rather than being arbitrarily
split or dropped.

Every returned row shall cite its document, page or pages, table, and row. A
multi-page table retains one table identity with explicit page and row
continuations. Repeated headers may be normalized as table structure but must
remain traceable to their source occurrences. Ambiguous headers, merged cells,
row or column associations, or page continuations block publication for that
table until source review or an accepted override resolves them.

### D07: Lossless Raw Layer and Traceable Normalized Layer

Immutable source bytes and raw extractor output are the evidence layer.
Normalized content never replaces either one. Phase 28 shall create a
deterministic canonical layer for chunking and retrieval in which every unit
retains its document, page, source span or geometry, structural path, and
transformation provenance back to the raw evidence.

Only versioned deterministic transforms are permitted. The method shall record
the method-profile identity, ordered rule identifiers, input and output
digests, warnings, and affected source spans for every transformed unit.
Normalization shall use Unicode NFC, consistent line endings, recognized
encoding, and non-semantic whitespace handling. It shall preserve meaningful
case, punctuation, identifiers, numbers, units, checkbox states, and list or
step markers. Compatibility normalization is prohibited for the canonical
authority; search-specific folded forms may exist as separate derived lexical
fields.

Wrapped lines may be joined only when layout evidence places them in the same
paragraph. Paragraph, list, heading, page, and structural boundaries remain
explicit. In the first vertical slice, dehyphenation is limited to a soft
hyphen or an extractor-provided marker that explicitly identifies a layout
break. An ordinary visible hyphen remains unchanged even at a line boundary.
The raw spelling and applicable rule provenance are always retained.

Repeated page furniture shall be detected using both comparable page position
and recurrence across eligible pages. Text similarity alone is insufficient.
Every source occurrence remains in raw evidence, while confirmed furniture is
represented as structure and omitted from ordinary semantic chunk text. The
recurrence threshold is a Tier 2 method-profile value that must be qualified
against held-out truth before activation; it is not claimed as calibrated by
this decision.

Exact duplicate material outside confirmed page furniture remains in the
canonical record at every source occurrence. It shall not be removed merely
because its text repeats. Retrieval may collapse equivalent result display
while preserving all distinct citations. Any future ingestion-time boilerplate
suppression requires an explicit structural or registry rule and new
validation evidence.

Tables and forms shall not be flattened into the general text path. They use
their structured authorities and may expose deterministic text projections
for retrieval. Conflicting reading order, undecodable text, unexplained
duplicates, or transforms that cannot retain source anchors prevent the
affected unit from publication until resolved; normalization shall not guess.

### D08: Structure-First, Token-Measured Chunk Contract

Structural meaning determines candidate chunk boundaries. Token counts
enforce model and operational limits; they shall not replace headings,
paragraphs, lists, steps, definitions, form fields, or table rows as boundary
evidence.

The authoritative tokenizer for stored retrieval chunks shall be the exact
tokenizer and revision paired with the active embedding model. Its identity is
part of the Tier 2 method profile and every ingestion record. Measurement
shall cover the exact text submitted for embedding, including document or
query prefixes, breadcrumbs, headings, repeated table headers, field labels,
and other reconstruction context. The method shall store separate counts for
canonical content, added context, prefixes, and total embedding input.

The hard maximum shall not exceed the embedding model's proven input limit
after reserving an explicit safety margin for required wrappers. Target sizes
are per-profile Tier 2 settings below that maximum. Character, word, or
unrelated-tokenizer counts may be retained as diagnostics, but shall not
enforce the authoritative limit.

Generation-context budgeting is separate retrieval-time work measured with
the exact tokenizer paired with the active generation model. An embedding
token count shall not be treated as a generation token count.

A tokenizer or tokenizer-revision change creates a new method-profile
identity and requires candidate remeasurement. If a stored boundary,
projection, or accepted maximum changes, affected content must be reingested
and retrieval requalified before promotion. The assessment's proposed 64-,
128-, and 512-token values remain evaluation hypotheses until boundary
preservation and retrieval quality are measured against held-out cases.

Material exceeding a hard maximum follows a profile-specific deterministic
fallback under the boundary decision. It shall never be truncated or silently
dropped to satisfy a token count.

### D09: Deterministic Structural Boundaries without Blind Overlap

Chunk construction begins with the smallest canonical structural units
identified by the active processing profile. Compatible sibling units may be
assembled in source order toward the profile target only when doing so neither
exceeds the hard maximum nor crosses a prohibited semantic boundary. A target
is an optimization goal, not permission to split an atomic unit, combine
unrelated material, drop a short meaningful unit, or pad it with unrelated
text.

Blind sliding-window body-text overlap is zero by default. Breadcrumbs,
labels, table headers, and other repeated reconstruction context are explicit
contextual fields counted under `D08`, not accidental duplicated body text.
Stable previous, next, parent, child, and continuation links represent
sequence and neighborhood. Retrieval-time reconstruction may follow those
links under a later context-budget decision.

The deterministic over-size fallback is profile-specific:

- narrative policy or manual content: section, subsection, paragraph, then
  sentence, with the complete heading path retained on every part;
- procedures: complete step, explicit substep, list item or paragraph, then
  sentence, with procedure identity, step number, applicable conditions and
  warnings, and ordered continuation identity retained;
- definitions: keep term and definition together when possible, otherwise
  split only at explicit paragraphs or enumerated clauses and repeat the term
  and parent context;
- forms: keep label, value, state, and form context together, otherwise split
  an over-size value only at explicit paragraph or list boundaries while
  repeating label and field identity; and
- tables: use the row-specific fallback frozen in `D06`.

If the smallest safe semantic unit still exceeds the hard maximum, or no
deterministic safe boundary exists, the unit is blocked from publication for
source review or a reviewed profile extension. It shall never be truncated,
token-sliced, or silently omitted. Every split preserves source spans and
ordered continuation identities. A semantic unit may span source pages, but
every contributing page and span remains citable.

A boundary-rule, overlap, or reconstruction-context change creates a new
method-profile identity and requires affected content to be reingested and
retrieval requalified before promotion. A future deliberate body-text overlap
exception requires profile-specific evidence, review, and validation; it is
not an ordinary tuning switch.

### D10: Versioned Canonical Records with Public/Private Separation

Phase 28 shall define independent versioned records for source document,
document version, structural unit, retrieval chunk, citation anchor,
relationship edge, ingestion run, and publication batch. Database tables and API
payloads may implement these logical records but shall not define or silently
change their meaning.

A source-document record represents the durable logical document. A
document-version record represents exact immutable source bytes and their
extraction, normalization, class-assignment, and method-profile provenance. A
structural-unit record represents canonical headings, paragraphs,
definitions, steps, lists, forms, tables, rows, or fields with parent and
ordering relationships plus source spans. A chunk references one or more
structural units and stores its exact retrieval projection, contextual fields,
token accounting, processing profile, and publication state.

A citation anchor resolves a result to document version, page or pages,
structural path, and the applicable table/row, form/field, step, or source
span. It shall support a client-safe source label and relevant excerpt without
exposing a filesystem path.

Metadata is divided into three explicit surfaces:

- retrieval content and allowlisted filter fields used by lexical or vector
  search;
- client-safe display and citation fields permitted in the retrieval API; and
- server-only operational fields such as filesystem and quarantine locations,
  internal object keys, tool diagnostics, and authorization references.

Original filenames and source paths are server-only by default. They shall not
be copied into clients, logs, embeddings, or metrics merely because they are
available. An operator supplies or explicitly approves a neutral display name.
Future open/download behavior resolves a citation through an authorized server
endpoint and never returns the underlying source path.

Required core metadata includes schema version, stable record identity,
document and version identity, assigned class, class-registry version,
ingestion-manifest identity, processing profiles, method-profile identity,
source-digest reference, source format, language when known, page and source-
span anchors, ordinal and structural path, timestamps, ingestion-run and
publication-batch identity, and publication status. Content-bearing values
remain outside routine logs and metrics.

Operator metadata uses a versioned namespaced schema with an explicit
allowlist for retrieval filters and client display. Unknown, malformed, or
conflicting required metadata blocks candidate publication instead of being
silently discarded or copied into embeddings. Schemas identify required,
optional, nullable, and repeated fields; validate references and enumerations;
and reject incompatible versions. When absence is permitted it has an
explicit reason rather than an invented value.

Stored content, derived projections, metadata, and relationships retain
separate digests and provenance. A display-only change need not force
re-embedding. A change to embedded text, retrieval filters, structural
meaning, or citation anchors requires affected candidate artifacts to be
regenerated and requalified.

### D11: Content-Bound Identities with Explicit Document Lineage

Phase 28 shall use SHA-256 over a versioned canonical serialization with a
record-type domain separator for deterministic internal identities. Full
digests are stored internally; shortened labels are display conveniences only.

A durable logical `document_id` comes from an operator-controlled stable
document key in the versioned document catalog and is referenced by the
ingestion manifest. This is a neutral permanent identifier for the logical
document across revisions, such as
`policy.travel-expense`, not its filename, path, title, or modification time.
The key identifies the continuing document; its changing source bytes identify
each version.

When no valid cataloged document key is supplied, Phase 28 may create a
provisional identity bound to the source digest only for discovery and
quarantine evidence. That source cannot proceed to chunking or publication.
The system shall not infer revision lineage from similar filenames, paths,
titles, or content.

The identity derivations are:

- `document_version_id`: logical document identity plus exact immutable source
  digest;
- structural-unit identity: document-version identity, canonical structural
  kind and source anchor, normalized-content digest, and structural ordinal;
- chunk identity: document-version and method-profile identities, projection
  kind, ordered structural-unit identities, contextual-field digest, and exact
  retrieval-text digest;
- embedding-artifact identity: chunk identity plus embedding model, revision,
  tokenizer, prefixes, normalization settings, and submitted-input digest;
- citation identity: document version plus exact citation anchor;
- relationship identity: typed directed endpoints, evidence anchor, and
  relationship-definition version; and
- publication-batch identity: the ingestion-manifest digest, affected
  document-version identities, and applicable schema and method-profile
  identities.

Reingesting identical bytes under the same logical document reuses the
document-version identity and records a new ingestion observation rather than
inventing a version. Duplicate bytes discovered more than once are processed
once per logical document version while retaining content-free discovery
observations. Identical bytes assigned to two explicit logical document keys
remain two logical documents but may share immutable source storage.

A revised source creates candidate document-version, structural-unit, chunk,
citation, relationship, lexical, and embedding artifacts for that document
only. Publication atomically marks the selected version active and its
predecessor superseded; rollback restores the prior active document version.
Published artifacts are never mutated in place.

Deletion creates an auditable tombstone in a publication batch that removes
the document's searchable and retrievable artifacts according to the later
retention policy. Validation must prove no active index or citation points to
removed content. Audit metadata may remain only as permitted by that policy.

An identity-input or canonical-serialization change requires a new schema or
method-profile version, explicit migration analysis, candidate regeneration,
and referential-integrity validation before promotion.

### D12: Pinned, Isolated, Fail-Closed Embedding Space

The Tier 2 method profile shall identify the exact embedding model, immutable
model revision or artifact digest, tokenizer and revision, dimension, pooling
behavior, vector normalization, document and query prefixes, maximum input,
numeric precision, runtime or provider, distance metric, and license. A model
name alone is insufficient.

Production ingestion and retrieval shall use the approved local target service
or packaged local artifact. Corpus and query content shall never fall back to
an external embedding provider. Only retrieval projections authorized by
`D10` may be embedded; private paths, unapproved operator metadata, raw tool
diagnostics, and client-prohibited fields are excluded.

Document and query embeddings shall use one compatible model tuple and their
explicitly defined prefixes. One vector index contains exactly one embedding
space: one complete model tuple, dimension, normalization rule, and distance
metric. A candidate replacement index may coexist during migration, but
vectors from different spaces shall never be searched or fused as directly
comparable values. The active corpus has one searchable embedding space.

The embedding adapter shall fail closed on dimension mismatch, missing or
extra results, non-finite values, empty vectors, invalid normalization,
timeout, unavailable model identity, or request/response identity mismatch.
A failed batch publishes no partial embedding artifacts. Batching,
concurrency, and retries are Tier 3 settings bounded by the same semantic
contract. Single-item and batched results shall agree within a recorded
numeric tolerance, and retries use embedding-artifact identity for idempotency.

Each embedding artifact records its identity, model tuple, exact input digest,
dimension, normalization status, creation run, and content-free outcome.
Vectors and source text shall not appear in routine logs or tracked evidence.

Qualification shall cover model loading, tokenizer agreement, prefixes, input
limits, dimension and finite-value checks, repeat and batch tolerance, failure
paths, and retrieval performance against held-out cases. Successful vector
creation alone is not retrieval-quality evidence. A model-tuple, prefix,
pooling, normalization, precision, or distance-metric change creates a new
embedding space and method-profile identity. Only that method-wide change
requires Phase 28 to build and qualify a complete replacement index before
publication; the active index is never left partially migrated.

An ordinary document revision under the same frozen model tuple does not
requalify or rebuild every unchanged embedding artifact. It creates and
validates embeddings for the changed document version, reuses compatible
unchanged artifacts, and qualifies only the affected publication batch.
Changing an embedding or upstream semantic input that can alter projections
or boundaries requires regeneration and requalification of every affected
artifact; changing the embedding-space tuple requires a complete candidate
embedding space.

### D13: Incremental Validated Publication

Every ingestion begins from a versioned manifest containing only the new or
changed documents in that operator-requested batch. The document catalog
remains the authority for all known documents. An empty batch, unreadable
required input, path-containment failure, unknown document key or class, or
incompatible configuration fails before processing.

The per-document stages are discover, fingerprint, validate class assignment,
extract, normalize, structure, chunk, embed, and validate. The method processes
only documents listed in the batch. It reuses matching immutable artifacts and
does not extract, chunk, embed, copy, or otherwise rebuild an unchanged
document. Retirement is an explicit catalog status change and is never inferred
from a missing manifest line.

Each stage records `pending`, `running`, `succeeded`, `failed`, `quarantined`,
or `skipped`; input and output identities; start and finish time; attempt; and
a stable content-free outcome code. A stale `running` state after a crash must
be reconciled before retry. A retry reuses a successful output only when its
exact inputs, implementation and schema versions, tool identity, and method
profile match.

Processing may continue after a batch document fails or is quarantined to
produce a complete report, but no change from that batch becomes searchable
unless every required item passes. Validation checks the affected documents
and their compatibility with the currently searchable corpus: schema and
reference validity, source and derived digests, citation resolution, expected
lexical and vector artifacts, embedding compatibility, and absence of dangling
active references.

After validation, one PostgreSQL transaction publishes only the batch's
additions, revisions, or explicit retirements. Readers observe either the
previous active document versions or the complete validated change; they never
observe a half-published batch. A publication record retains the prior active
version identities so the batch can be rolled back atomically. Unchanged
documents remain active and untouched.

Only a method-wide change that affects stored meaning—such as a new embedding
space, normalization rule, chunk-identity rule, or generally applicable
chunking behavior—requires reprocessing every affected document. Temporary
work uses a private bounded workspace with guaranteed cleanup. Quarantine and
failure evidence follow the access and retention policy and expose only
content-free identifiers in ordinary operations.

### D14: PostgreSQL Catalog Authority with Incremental Publication

PostgreSQL is the production target and transactional authority for the
logical records frozen in `D10`, identity and lineage, ingestion state,
publication batches, active document versions, citations, relationships, and
artifact manifests. PostgreSQL and every required extension, including the
selected vector capability, are non-native dependencies that must be
version-pinned, acquired for offline installation, integrity-verified, license
and advisory reviewed, and captured with their complete dependency set.

SQLite may be used for rapid local prototyping only. A SQLite prototype shall
be explicitly labeled non-production, implement the canonical record and
publication contracts rather than define them, and provide no production
persistence, concurrency, security, vector-performance, backup, or recovery
claim. Its schema and behavior must remain migration-testable against the
PostgreSQL target.

Immutable source bytes, raw extraction evidence, canonical structures, and
derived retrieval projections are stored as content-addressed artifacts with
digests recorded in the PostgreSQL catalog. Unchanged artifacts are referenced
and reused rather than copied into each publication batch. Storage location is
a server-only implementation detail.

Lexical and vector indexes are derived search accelerators, not authorities.
Every indexed entry maps to a catalog chunk identity and, for vectors, an
embedding-artifact identity. Either index must be rebuildable from the
accepted catalog and immutable artifacts. The production vector target is a
reviewed PostgreSQL-compatible vector extension and index method; its exact
package, version, operator class, distance metric, and index parameters are
selected and qualified with the embedding and retrieval evidence rather than
assumed from PostgreSQL alone.

A publication-batch record binds the ingestion manifest, affected document
versions, artifact digests, schemas, method profile, embedding-space tuple,
validation result, prior active-version mapping, and resulting active-version
mapping. An ordinary batch never contains or rebuilds unrelated documents.

Before publication, validation checks catalog constraints and foreign
references, affected artifact existence and digests, expected lexical and
vector mappings, vector dimensions and model tuple, citation resolution, and
compatibility with the active corpus. A mismatch blocks the entire batch.
Publication updates only affected active-document-version mappings in one
transaction under `D13`.

One writer owns an affected document candidate at a time. Readers use only
active validated document versions. Connection pooling, caching, memory
mapping, and other deployment choices may not weaken isolation or identity
checks. In-process memory is never the sole authority; caches are disposable
and keyed by document version, method profile, and artifact identity.

Backup and restore cover the required PostgreSQL state, publication history,
and every referenced artifact. A restored corpus must pass digest, reference,
compatibility, and smoke validation before service use.

PostgreSQL supplies useful transactional, role, and access-control mechanisms,
but selection of PostgreSQL does not itself prove encryption or complete
security. TLS, credential authority, database roles, host and network policy,
backup protection, storage encryption, optional field-level encryption, key
management, audit, and deletion enforcement remain explicit `D20` decisions
and validation obligations.

Replacing a persistence implementation without changing canonical records,
retrieval semantics, or the embedding space requires migration equivalence and
restore evidence but not document reingestion. A migration that changes stored
meaning, filtering, ranking inputs, or vector compatibility requires affected
artifact regeneration and retrieval requalification.

### D15: Evidence-Anchored, Version-Aware Relationship Graph

Relationships are typed directed edges between canonical document or
structural-unit identities, never display names, filenames, or derived chunks.
Every accepted edge records its versioned relationship type, source and
target, source-document version, evidence citation anchor, detection method,
deterministic or review status, creation run, and publication-batch identity.

Relationship types come from an extensible allowlisted registry. The first
vertical slice enables only explicit-reference and supersedes relationships
supported by deterministic source evidence. Each type declares allowed
endpoint kinds, direction, inverse display, version behavior, and whether it
may influence retrieval. Additional types require a concrete corpus need,
fixtures, and retrieval validation before activation.

Ingestion automatically detects explicit references and resolves their
identifiers against the candidate catalog; routine ingestion requires no
operator-authored relationship manifest. An unambiguous match creates the edge
automatically. An ambiguous required internal reference is stored as an
unresolved observation and quarantines the affected document rather than being
guessed. A clearly external reference may remain a cited external observation
when the registry identifies it as outside corpus scope.

An operator manifest is an optional audited override for a quarantined
exception, not a routine relationship-definition requirement. It may identify
the intended target or explicitly classify a reference as external, and takes
effect only through a new candidate run and promotion. There is no model-
assisted edge discovery or relationship-review workflow in the first vertical
slice.

Relationships distinguish fixed document-version targets from logical-
document targets. A logical target resolves to the active authorized version
at query time and records that resolution in retrieval provenance. A fixed-
version edge never silently repoints. Updating either endpoint causes candidate
edge reevaluation; source-version promotion does not carry stale evidence
forward without validation.

Retrieval starts with direct lexical and vector candidates. Traversal is
allowlisted by relationship type, defaults to one hop, and does not recursively
expand the graph. Authorization and metadata filters apply before and after
traversal, so an edge cannot reveal an unauthorized target's identity, title,
excerpt, or existence.

Every relationship-derived result records the seed result, traversed edge,
direction, resolved target version, evidence citation, and inclusion reason.
Relationship evidence shall not masquerade as vector similarity. Cycles may
exist in source material but are detected and deduplicated during traversal;
an edge or endpoint is not revisited within one request.

A registry, edge-extraction, or traversal-policy change creates a new method-
profile identity and requires affected edge regeneration and retrieval
requalification before promotion.

### D16: Resolved Query with Exact, Lexical, and Vector RRF

The original user turn is preserved. The retrieval core receives a resolved
standalone retrieval query, explicit authorized filters, and structured
citation or source constraints. It shall not embed the complete chat
transcript as an undifferentiated query.

An approved conversational resolver may use the local direct Gemma path to
rewrite a follow-up into a standalone query, but it shall not answer the
question, introduce facts, or silently broaden scope. It returns the resolved
query, referenced citation identities, applied filters, and ambiguity status.
A material unresolved ambiguity requests clarification instead of searching.
References such as `Source 1` resolve through the conversation's structured
source map to citation or document identities; the literal label is not
embedded and expected to retrieve a document.

Authorization and allowlisted metadata filters apply before candidate
generation where supported and are verified again afterward. Query processing
may create separate lexical and embedding forms while retaining request-scoped
provenance for the original and resolved forms.

The retrieval method runs three eligible candidate lanes:

- exact lookup for identifiers, citations, document keys, table fields,
  numeric values, and other structured exact terms;
- PostgreSQL full-text lexical retrieval for terminology and rare-token
  matches; and
- vector retrieval in the single active embedding space for semantic
  similarity.

Candidate depths, lexical configuration, vector search parameters, and lane
eligibility are Tier 2 method-profile values. A lane failure fails the request
unless the profile explicitly marks it optional and its degraded behavior has
been validated; degradation is never silent.

Candidates are deduplicated by canonical chunk identity while preserving each
lane's raw score, rank, match evidence, and exact model, index, and release
identity. This removes the same chunk returned by multiple lanes; it does not
remove distinct chunks or citation anchors from the same document. Document-
level grouping and evidence consolidation are governed by `D17`.

Eligible lanes are combined using deterministic reciprocal-rank fusion (RRF),
because lexical and vector scores use incomparable scales. The method profile
records the RRF constant, any reviewed lane weights, tie-breaking, and
candidate depths. Exact authoritative matches may use a separate deterministic
priority rule when the reason is returned.

The first vertical slice uses no learned reranker. `D15` relationship traversal
occurs only after direct candidate fusion so relationship-derived results
remain distinguishable from search matches. `D17` controls expansion and the
final context budget.

Candidate provenance is retained even when later abstention rejects the result
set: query-resolution status, participating lanes, per-lane ranks and scores,
fused rank and score, exact-match reason, filters, release identity, and any
relationship reason.

A change to query resolution, lexical parsing, candidate depth, vector search
parameters, lane weights, RRF, exact priority, or reranking creates a new
method-profile identity and requires retrieval requalification. It does not
require document reingestion unless stored projections or embedding inputs
change.

### D17: Document-Grouped Evidence with Explicit Context Budget

Reconstruction begins with the ranked direct candidates from `D16` and
separately marked relationship-derived candidates from `D15`. Their search and
relationship provenance is preserved throughout reconstruction.

Exact duplicate chunk identities and exact duplicate retrieval-text
projections are removed. When equivalent text has distinct valid source
anchors, one evidence passage retains all supporting citations. Continuations
and overlapping source spans from the same structural unit may be consolidated
only when their order and anchors prove they form one passage; text similarity
alone is insufficient.

Selected evidence is grouped by document version for display and source
reference. Multiple relevant passages from one document become one source
group containing multiple excerpts and citation anchors, not duplicate
documents. Distinct relevant passages from that document remain eligible. A
Tier 2 per-document diversity limit may prevent one broad document from
crowding out all others, but is bypassed or raised for an explicit single-
document or citation-constrained follow-up.

Reconstruction adds only context required to interpret a selected passage:
heading path, definition term, procedure and step identity, table headers,
form label, and explicit continuation. Previous, next, and relationship links
are followed only when the query and structural profile require them.

For a normal procedure match, retrieval returns the selected step or steps plus
the procedure identity, heading path, applicable prerequisites, conditions,
warnings, and required continuations. It does not automatically place the
entire procedure into generation context. When the resolved query explicitly
requests the complete procedure, reconstruction follows the canonical parent
procedure, ordered child-step, substep, and continuation links to assemble all
procedure units in source order; it does not depend on similarity search to
rediscover every step. If the complete atomic procedure cannot fit the
generation budget, the service returns an explicit context-limit result rather
than presenting a truncated procedure as complete.

Document groups are ordered by their strongest selected evidence rank. Within
a group, passages are ordered by relevance for presentation while retaining
source-order metadata. A stable conversation source label maps to one document
version, and every passage retains its own citation identity.

The generation-context budget is measured with the active generation
tokenizer and partitioned among system and policy instructions, accepted
conversation history, retrieved evidence, and reserved answer tokens. The
configured budget is deliberately lower than the model's advertised maximum
until target performance and latency are measured.

Evidence is added in deterministic priority order without truncating an atomic
passage. If the next passage does not fit, it is omitted with a recorded budget
reason or replaced by a smaller independently valid structural unit. Source
text is never clipped mid-unit to fill remaining tokens.

The first vertical slice shall not silently summarize or discard older
conversation turns. If accepted conversation plus minimum evidence and answer
reserve exceeds the configured budget, the service returns an explicit
conversation-limit status and asks the user to begin a new conversation.

The final evidence package records selected and omitted candidate identities,
grouping and deduplication actions, reconstruction links, token counts by
budget partition, ordering, source labels, and every citation. Content-bearing
context remains outside routine logs. A grouping, deduplication, diversity,
expansion, ordering, or budget-allocation change creates a new method-profile
identity and requires retrieval requalification but not document reingestion
unless stored projections change.

### D18: Versioned Chat Response with Claim-Level Citations

The versioned request contains conversation identity, turn identity, user
message, optional structured source or citation references, and allowlisted
filters. The server, not the client, resolves the active corpus state and
method profile.

The versioned response envelope contains request and turn identity, response
status, assistant message when applicable, source groups, citations,
capability flags, release identity, and a content-free diagnostic reference.
Internal paths, credentials, raw tool diagnostics, and private metadata never
enter the response.

Response status explicitly distinguishes answered, clarification-required,
insufficient-evidence, out-of-scope, security-rejected, context-limit,
temporarily-unavailable, and internal-error outcomes. A context-limit response
includes a safe reason such as conversation-history or requested-evidence
size. `D19` governs the policy for choosing among these statuses.

Each source group has a conversation-stable opaque identity and label such as
`Source 1`, client-safe display metadata, document-version identity, and one
or more selected excerpts. Multiple excerpts from one document remain one
source group. Each excerpt contains an opaque citation identity, exact client-
approved excerpt text, page or page range when available, structural path, and
applicable table/row, form/field, or procedure/step anchor. It does not expose
internal chunk text, source path, or an unapproved filename.

Assistant claims requiring retrieved evidence cite one or more excerpt-level
citation identities, not only a document-level source label. The UI may render
the friendlier source label while retaining the exact mapping. A citation may
refer only to an excerpt present in the response or the explicitly retained
conversation source map.

The answer generator receives an allowlist of valid citation identities and
shall not invent identifiers. Response validation rejects or withholds an
answer containing an unknown, unauthorized, unresolved, or mismatched
citation.

Retrieval scores, internal ranks, model diagnostics, and traversal details
remain server-side by default. The client may receive a neutral inclusion
reason or relationship label, but raw implementation details require a
separate authorized diagnostic contract.

Open-document and download-document are optional capability flags and opaque
server-issued actions. They are disabled in the first vertical slice, never
expose a filesystem path, and require `D20` authorization and audit enforcement
before activation.

Errors use stable content-free codes and safe corrective text. They do not
return partial private evidence, stack traces, source paths, prompts, or
internal topology. Streaming is not required for the first vertical slice; a
future streaming transport must preserve the authoritative final envelope and
citation validation.

Contract changes are versioned. Additive optional fields may remain
compatible; changes to identities, statuses, citation meaning, required
fields, or authorization behavior require a new contract version and
integration validation.

### D19: Explicit Scope, Injection Resistance, Sufficiency, and Abstention

Before retrieval, Phase 28 shall validate request shape, size, conversation
references, authorization, and security policy. Topic scope and prompt-
injection risk are separate checks: a question about an allowed organizational
topic may still attempt to override instructions, extract protected context,
alter authorization, or misuse downstream components.

The narrow allowed scope is organizational policy, applicable regulation,
code of conduct, operating procedures, professional organizational work, and
follow-ups about previously returned answers or sources. The approved local
Gemma path may classify scope only through a constrained structured response
of `allow`, `needs_clarification`, or `out_of_scope` plus an allowlisted reason
code. It shall not answer during classification. Deterministic rules handle
empty input, size and encoding limits, explicit source references, and cases
not requiring model judgment. An ambiguous potentially professional question
returns clarification-required rather than being denied.

Direct user input, conversation history, and every retrieved document or
excerpt are untrusted data. The orchestration layer shall keep trusted system
policy, user data, and retrieved content in distinct typed fields with explicit
delimiters and instructions that retrieved content is evidence, never command
authority. Document text such as `ignore previous instructions`, apparent
system messages, hidden or control characters, encoded instructions, or tool
requests cannot modify the system policy, authorization filters, source
constraints, endpoints, or executable behavior.

Input and retrieved-evidence scanners shall detect known direct and indirect
injection indicators, obfuscation, invisible characters, instruction-role
impersonation, prompt-extraction requests, and data-exfiltration attempts.
Detection can reject or quarantine suspicious input, but pattern matching or a
guard model is never treated as complete prevention. Source approval and
digests establish provenance and integrity, not proof that document content is
safe.

The first vertical slice gives Gemma no shell, filesystem, database-write,
network, document-open, download, or other tool authority. Model output is
untrusted data. Fixed application code performs retrieval, authorization,
filtering, citation validation, and response construction through parameterized
interfaces and strict schemas. A classifier or resolver response that fails
schema, enumeration, or policy validation fails closed.

An identified injection attempt returns security-rejected with a stable safe
reason and no prompt, system-policy, private evidence, or detection details.
Uncertain security classification fails closed or requests clarification under
the configured rule; it does not weaken authorization or continue silently.

For a safe allowed question, evidence sufficiency is evaluated after `D16` and
`D17`. Signals include candidate presence, calibrated rank and score behavior,
exact-constraint satisfaction, required relationship or sequence coverage,
source/version conflicts, authorization filtering, citation validity, and
context-budget completeness. Sufficiency shall not depend on Gemma claiming
confidence; Tier 2 thresholds and rules are calibrated against held-out
responsive and non-responsive cases.

Absent or inadequate evidence returns insufficient-evidence with an allowlisted
reason. The first vertical slice shall not fall back to an uncited general-
model answer. Conflicting authoritative sources may be reported as a cited
conflict only when evidence is complete enough to explain it. Otherwise the
service requests clarification or abstains.

A request for a complete procedure, table, or bounded structure is answerable
only when reconstruction proves completeness. A context limit or missing unit
prevents a completeness claim. Answer generation receives only accepted
conversation context and validated evidence. Post-generation validation
enforces output schema, citation allowlists, citation coverage, safe rendering,
and prohibited-data boundaries before returning answered status.

Routine telemetry records only content-free scope, security, sufficiency, and
final-status reason codes plus policy/profile versions and a diagnostic
reference. Questions, evidence, answers, prompts, and detector details are not
logged routinely.

Changes to scope categories, classifier or resolver prompt/model, injection
controls, reason rules, sufficiency thresholds, conflict handling, or citation
coverage create a new method-profile identity and require adversarial, safety,
and retrieval requalification. Gemma shall never override a deterministic
security, authorization, completeness, citation, or insufficiency failure.

This layered boundary follows [OWASP LLM01:2025](https://genai.owasp.org/llmrisk/llm01-prompt-injection/)
and the [OWASP RAG Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/RAG_Security_Cheat_Sheet.html):
direct and indirect prompt injection remain possible, retrieved content is
untrusted data, model privileges must be constrained, and structured output
must be validated. It does not claim prompt injection can be eliminated by a
single filter or system prompt.

### D20: Local Least Privilege with No Model Agency

The first vertical slice has no application login, individual identity,
roles, or per-user document permissions. The retrieval API binds by default
to `127.0.0.1:1384`; anyone able to use the local host can search the complete
active corpus. The bind host and port are deployment settings, but non-loopback
exposure is not part of the first implementation.

The application does not claim to know which individual submitted a request.
It uses an opaque request identity for correlation only. User messages, model
output, client fields, and retrieved documents can never supply a trusted
identity or role.

Retrieval uses a read-only PostgreSQL identity and cannot write corpus state.
The operator-invoked ingestion workflow owns incremental processing,
validation, publication, retirement, and rollback. Model-serving identities
cannot query PostgreSQL or artifact storage directly.

Canonical records preserve an optional future authorization reference at the
document-version level so verified identity and document permissions can be
added later without changing chunk or citation identities. The first slice
does not enforce or claim that future multi-user capability.

Gemma has no shell, filesystem, database, network, URL-fetch, upload,
document-open, download, or administrative tool authority in the first
vertical slice. Fixed application code performs approved actions and treats
all model output as untrusted input to strict schema and policy validation.

The implementation shall use parameterized database interfaces, shell-free
process invocation, canonical path containment, bounded resource use, and
allowlisted service destinations. Default-deny network egress applies wherever
the deployment supports it. Credentials and keys come from a protected secret
authority or environment injection, not source, ordinary YAML, prompts,
images, logs, or corpus metadata.

Authenticated encryption in transport and encryption at rest are desired
hardening capabilities, not automatic gates for the initial production
decision. Their enabled/disabled state, protected scope, and residual risk
must be explicit in deployment evidence. An unencrypted deployment is limited
to an approved trusted network and storage boundary and may not claim
protection against network or storage compromise. If organizational policy or
the deployment boundary requires encryption, that requirement becomes a
mandatory gate.

The architecture shall preserve a clear path to add TLS for application,
model, and PostgreSQL traffic and approved at-rest protection for PostgreSQL,
artifacts, quarantine, candidates, and backups without changing canonical
records or retrieval semantics. Optional field-level encryption requires a
specific threat model, key authority, and searchable-field impact analysis.
PostgreSQL selection alone is not encryption evidence.

Versioned retention applies to source versions, candidates, quarantine,
conversations, diagnostic evidence, audit events, and backups. Temporary or
rejected content expires by default. Deletion and access revocation use a
validated publication batch and propagate to catalog records, indexes,
artifacts, caches, citations, and relationships. Backup expiration follows policy;
content-free tombstones remain only when required.

Open-document and download-document are unimplemented stretch capabilities,
not part of the first vertical slice. Future activation requires a separately
reviewed access rule, an opaque short-lived action, safe content disposition,
audit, rate limiting, and no storage-path disclosure.

Security-relevant events use content-free identities: listener configuration
and startup, read-only database enforcement, ingestion and publication,
manifest validation, quarantine, retirement, key or configuration changes,
injection rejection, and administrative actions. Audit readers cannot recover
questions, answers, excerpts, prompts, secrets, or private source paths.

Security validation includes direct and indirect prompt injection, poisoned
and hidden document instructions, encoding and Unicode obfuscation, prompt
extraction, exfiltration, SQL and command injection, path traversal, database
write attempts through retrieval, citation fabrication, rate and resource
abuse, backup and restore, retirement, and compromised service-role scenarios.

A role, authorization, retention, encryption, tool-capability, secret,
network, or audit-policy change requires security review and targeted
requalification before deployment. Encryption enablement alone does not
require document reingestion when stored meaning and identities are unchanged.

### D21: Classified, Correlated, and Reviewable Operations

Phase 28 shall expose exactly three allowlisted application logging profiles:
`default`, `debug`, and `verbose`. `default` is the production-normal profile.
`debug` adds structured diagnostic detail without content. `verbose` is a
protected, explicitly enabled content-review profile. An unknown profile
prevents startup rather than silently selecting a broader profile.

The profiles use four data classifications:

- **operational:** timestamps, component and stage, stable event or failure
  code, severity, outcome, duration, safe counts, health state, and opaque
  correlation, publication-batch, method-profile, and artifact identities;
- **diagnostic:** configuration versions and digests, dependency state,
  selected rule and branch identifiers, retrieval-lane state, candidate
  counts and opaque candidate identities, ranks and scores, budget accounting,
  retry state, exception type, and reviewed stack location;
- **restricted content:** questions, accepted conversation history,
  standalone retrieval queries, retrieved chunk or excerpt content, neutral
  document display fields, assembled model prompts, generated answers, model
  parameters, token identifiers, and validation details; and
- **prohibited secrets:** API keys, Authorization and cookie values,
  passwords, credentials, private keys, encryption material, unrelated
  environment values, database connection secrets, raw filesystem paths,
  embedding vectors, and any field not classified for capture.

`default` records operational fields only. `debug` records operational and
diagnostic fields, including sanitized exception type and reviewed stack
location, but not restricted content. `verbose` may additionally record the
explicitly classified restricted-content fields supported by the exact
implementation. Prohibited secrets are never valid log content at any level.
Raw exceptions, complete HTTP headers, environment dumps, database bound
values, and arbitrary object serialization are prohibited because their
contents have not been classified.

Verbose capture is disabled by default and is not an ordinary permanent
production setting. Enabling it requires an explicit local operator action,
declared reason, bounded duration, selected service or request scope, approved
protected destination, restrictive access, capacity and rotation limits,
retention and deletion time, and an audit event that contains no captured
content. It automatically returns to the prior profile at expiration or
restart unless a separately reviewed deployment setting says otherwise. An
emergency stop shall disable verbose capture without requiring service
replacement.

Every structured event uses a versioned schema and may contain timestamp,
component and stage, stable event or failure code, severity, outcome,
duration, fields permitted by the active profile, and opaque request, turn,
ingestion-run, publication-batch, artifact, and diagnostic identities. Opaque identities
shall not encode content, user names, source names, paths, or organizational
identifiers. User-controlled and retrieved strings are encoded as data so they
cannot forge record boundaries or fields.

One caller-supplied or generated request identity shall correlate the API,
scope and injection checks, query resolution, exact, lexical, and vector
lanes, fusion, reconstruction, Gemma generation, validation, and persistence.
The application shall propagate that identity to vLLM when the qualified
interface supports it while retaining service-specific child identities. It
shall not assume independently generated client, application, and vLLM
identities match.

The stable failure-code registry records each failed operation, expected
condition, safe observed category, retryability, operator correction, and
external response mapping. Client errors expose only the safe code and opaque
diagnostic reference. A failure code is stable across wording changes and
does not embed content.

Unauthenticated liveness is separate from authenticated or network-restricted
readiness and diagnostics. Liveness states only whether the process responds.
Readiness verifies the active corpus publication state and required database, embedding,
generation, storage, and configuration dependencies without revealing
topology, model paths, credentials, or private configuration.

Content-free metrics include request outcomes under `D18`, stage latency,
exact/lexical/vector lane health, candidate and reconstructed-unit counts,
context-budget utilization, scope and injection rejections, clarification and
abstention, citation-validation failures, ingestion and quarantine states,
publication and rollback, dependency failures, and bounded resource saturation.
High-cardinality or content-derived metric labels are prohibited. Alert
thresholds, scrape locations, telemetry retention, and dashboard routing are
Tier 3 deployment settings within safe limits and do not alter retrieval
semantics.

Security and administrative audit is logically separate from operational and
content-review telemetry. Audit access, integrity, retention, and export
follow `D20`; ordinary log readers do not thereby gain audit or verbose-log
access. Each telemetry class and profile has explicit destination, access,
retention, rotation, capacity, and deletion rules. Time sources and units are
consistent enough to reconstruct stage order and latency.

Failure of optional telemetry shall not bypass scope, authorization,
retrieval, citation, or safety decisions. Ordinary requests may continue only
under a declared degraded-observability policy. An administrative or security
action whose audit evidence is mandatory fails closed when that evidence
cannot be durably recorded.

The exact application and dependency logging surfaces must be inventoried and
tested; a requested field that the deployed component does not natively expose
is recorded as unavailable rather than guessed. Validation shall prove each
profile's included and excluded classifications, secret exclusion, correlation,
bounded verbose activation and automatic restoration, capacity behavior,
retention and deletion, access control, malformed-record resistance, failure
codes, and readiness behavior. A protected sample export may be produced for
review, scanned for prohibited secrets, checksummed, retained for a declared
period, and then deleted; it is not a permanent parallel content store.

Changing event wording, destinations, retention, dashboards, or alert
thresholds does not require corpus reingestion when method semantics and
stored records are unchanged. Changing a failure rule, readiness gate, or
logging behavior that affects publication or response behavior requires
targeted requalification.

## Assessment Defaults Retained as Proposals

These values came from the assessment. They are test hypotheses, not frozen
requirements or proven optima.

| Processing profile | Proposed chunk target | Proposed maximum | Atomic material | Proposed reconstruction |
|---|---|---:|---|---|
| Policy | Section or subsection | 512 tokens | Definition block | Parent-section breadcrumbs |
| Matrix | Row | 128 tokens | Complete row | Table header and table identity |
| Form | Field-value unit | 64 tokens | Label, value, and source anchor | Form identity and field context |
| Manual | Governance/control block | 512 tokens | Metadata plus control statement | Section path and stable identity |
| Procedure | Step or action | 128 tokens | Complete numbered step | Sequence identity and adjacent context |

Before adopting these values, the method must define the tokenizer, treatment
of over-size atomic units, overlap semantics, breadcrumb accounting, and the
measurements used to compare alternatives.

## Configuration Governance Proposal

Configuration should be split into three tiers. Treating every value as
ordinary YAML would allow unsafe drift; hard-coding every value would make the
method unnecessarily difficult to deploy and tune.

- **Tier 1 answers what must always remain true.** These are correctness and
  security guardrails enforced by code and schemas.
- **Tier 2 answers how this corpus method behaves.** These are versioned,
  reviewable choices whose changes can require class reassignment,
  reingestion, or retrieval requalification.
- **Tier 3 answers where and with what operational limits it runs.** These can
  vary by environment without changing the meaning of stored corpus data.

### Tier 1: Enforced Invariants

These are proposed as code- and schema-enforced behavior, not routine operator
configuration:

- source files are read-only inputs and receive a content digest;
- document, version, structural-unit, and chunk identities are deterministic;
- source provenance and citation anchors are mandatory on every chunk;
- atomic units are not silently split or dropped;
- ingestion is idempotent and publishes only validated incremental changes;
- embedding model identity and vector dimension must match the active index;
- retries cannot duplicate active documents or chunks;
- failures cannot leak content into logs, metrics, or tracked evidence;
- every published batch has an explicit rollback boundary; and
- unsupported or insufficient retrieval can abstain rather than fabricate.

Changing an invariant requires a reviewed design change, migration analysis,
and revalidation.

### Tier 2: Versioned Method Profile

These values should be declarative and reviewable, but a change creates a new
method-profile identity and may require reingestion or retrieval
requalification:

- class-registry and ingestion-manifest schemas;
- tokenizer and chunk measurement unit;
- per-structural-profile target, maximum, overlap, and over-size fallback;
- normalization and breadcrumb rules;
- embedding model, revision, dimension, and query/document prefixes;
- lexical/vector candidate counts, fusion algorithm, fusion constants, and
  reranking behavior;
- metadata filters, relationship traversal, neighboring-context expansion,
  deduplication, and context budget; and
- retrieval sufficiency and abstention thresholds.

The method profile may be represented in YAML after its schema, validation,
versioning, and secret-exclusion rules are decided.

### Tier 3: Deployment Configuration

These values should vary by environment without changing method semantics:

- service endpoints and bind addresses;
- database connection locations and index or collection names;
- concurrency, batch sizes, retry limits, and timeouts within safe bounds;
- temporary, quarantine, candidate, and active storage locations;
- content-free log level and metrics endpoint; and
- feature availability where it does not change stored-data semantics.

Credentials, tokens, and private keys must come from a secret authority or
protected environment injection, not a committed YAML file.

## Gap and Implementation Ledger

The bounded method and gap lists originally closed at `D23` and `G20`. The
operator subsequently clarified that “application and database on the host”
means native host Python and native host PostgreSQL/pgvector, not host-mounted
source and data executed by additional Python and database containers. That
clarification reopened only the runtime portions of `D23` and `G20`. The
operator then accepted configurable host networking for the sole Node
container, configurable explicit loopback binding for Next.js, and a
configurable native retrieval URL. The corrected native-host boundary is
recorded below, and both bounded lists are closed again. Target-native package
qualification remains implementation evidence, not an open design decision.

| ID | Area | Gap to close | Required decision or evidence | State |
|---|---|---|---|---|
| `G01` | Source verification | Synthetic generation truth exists, and Phase 28 must accept extraction against it while preserving explicit blank pages. | Script `25` proved all six documents, 27 pages, one intentional blank page, repeatability, physical reading order, hierarchy, tables, forms, procedure order, punctuation, and source anchors against held-out truth. | FROZEN ACCEPTANCE CONTRACT; SCRIPT 25 EXTRACTION ACCEPTED |
| `G02` | Operator-assigned class | Amended `D01`, `D02`, `D10`, and `D13` freeze a small class registry plus an ingestion manifest that assigns each document path to one valid class. Generic extraction and structural chunking are class-independent. | The exact v1 class-registry, document-catalog, and ingestion-manifest YAML contracts and sanitized templates are frozen under `Ishikawa`. The restricted loader, exact validators, canonical identities, cross-file validation, stable reason registry, and protected validation-only reports passed local acceptance. The target-native writer proof persisted assigned class at artifact-set scope and passed actual quarantine plus successful-remediation linkage. Extraction-level class inheritance remains pipeline work. | FROZEN V1 YAML CONTRACTS; LOCAL CONFIGURATION AND TARGET-NATIVE PERSISTENCE INTEGRATION ACCEPTED; EXTRACTION PIPELINE NOT RUN |
| `G03` | Extraction | The Poppler-first native extraction qualification plan is frozen. | The accepted Script `25` target capture and corrected local evaluator prove exact Poppler identity, bounded repeat capture, all six documents, 27 pages, one blank page, structures, and anchors against held-out truth. | FROZEN QUALIFICATION PLAN; SCRIPT 25 ACCEPTED |
| `G04` | Normalization | The common standard-library normalization rules and conservative repeated-furniture rule are frozen. | Script `26` passed 64 base plus 13 normalization tests, deterministic replay, exact source anchoring, structural extraction, table/form handling, and retained one checksum-bound normalized artifact. | FROZEN CONTRACT; SCRIPT 26 NORMALIZATION ACCEPTED |
| `G05` | Chunk measurement | Nomic Embed Text v1.5 and the tokenizer from its pinned snapshot are the embedding measurement authority; Gemma uses its own separate tokenizer for grounded-inference context. The common 512-token target is an initial qualification hypothesis, and total Nomic input may never exceed the validated 2048-token service ceiling. | Script `28` bound the pinned tokenizer digest, measured every exact prefixed input, and proved tokenizer/service agreement. Script `36` repeated that proof for the amended 126-candidate set, including one derived blank-page-status candidate; every input measured 10–57 tokens, below both 512 and 2048. Script `37` then accepted the amended retrieval calibration. | FROZEN NOMIC MEASUREMENT CONTRACT; AMENDED EXACT SYNTHETIC TOKEN MEASUREMENT AND RETRIEVAL CALIBRATION ACCEPTED |
| `G06` | Boundary fallback | The structural-type fallback order, 512-token target behavior, 2048-token total Nomic ceiling, continuation context, zero blind overlap, no-drop rule, and quarantine boundary are frozen. | Script `27` accepted smallest-unit structural candidates, table rows, forms, sequence metadata, and zero overlap. Script `28` proved every current synthetic candidate is already below the 512-token target. No current case exercises sibling assembly, oversize fallback, continuation splitting, or token-limit quarantine; those paths remain held-out implementation work. | FROZEN CONTRACT; CURRENT STRUCTURAL CANDIDATES AND TOKEN CEILINGS ACCEPTED; OVERSIZE FALLBACK CASES NOT RUN |
| `G07` | Metadata contract | Compact versioned JSON/JSONL logical records, explicit validation, required provenance, references, and private/client-safe separation are frozen. | Script `27` implements deterministic chunk-candidate identity, citation, lexical, structure, sequence, token-placeholder, and private-filename-exclusion fields. The complete eight-record schema and client-source projection remain. | FROZEN JSON CONTRACT; CHUNK-CANDIDATE METADATA SOURCE READY; COMPLETE RECORD SET NOT IMPLEMENTED |
| `G08` | Identity/versioning | A versioned YAML document catalog is the authority for stable document keys; the ingestion manifest must reference an existing key, unknown keys are quarantined before chunking, and source digests identify revisions without requiring an operator version-label scheme. Content-bound derivations, duplicate handling, supersession, rollback, and tombstones remain frozen. | The exact v1 catalog and manifest fields, exclusions, key syntax, collision rules, relative-path boundary, dual-confirmation retirement, and computed digest ownership are frozen. Their validators, canonical identities, source hashing, collision handling, unknown-key classification, retirement agreement, and deterministic planning passed locally. The target-native writer proof passed revision supersession, class reprocessing, atomic rollback, explicit retirement, quarantine linkage, and accepted referential constraints. Complete cross-component derived-data deletion propagation remains implementation work. | FROZEN V1 IDENTITY CONTRACT; LOCAL VALIDATION AND TARGET-NATIVE DATABASE LIFECYCLE ACCEPTED; CROSS-COMPONENT PROPAGATION NOT RUN |
| `G09` | Ingestion state | The operator manifest is an incremental batch containing only new or changed documents; retirement is an explicit catalog status. Process only the listed documents, reuse unchanged artifacts, validate the batch against the active corpus, and publish only the affected additions, revisions, or retirements atomically. | The safe-load, cross-file validation, five-action planning, symlink rejection, protected reporting, quarantine/remediation linkage, and all-or-nothing behavior are frozen. The parameterized PostgreSQL state adapter and writer passed 64 local tests, then target-native synthetic lifecycle checks. Script `31` additionally passed the real six-document producer artifacts through schema version 3 and proved add, unchanged-document reuse, atomic active projection, cleanup, and accepted-database non-mutation. Full operator corpus-command integration, interruption recovery, and retry UX remain. | FROZEN V1 VALIDATION, QUARANTINE, AND INCREMENTAL STATE CONTRACT; SCHEMA-V3 TARGET-NATIVE WRITER ACCEPTED; COMPLETE CORPUS COMMAND NOT IMPLEMENTED |
| `G10` | Embedding | The exact Nomic model and tokenizer tuple, mean-token pooling, prefixes, 768-vector dimension, 2048-token ceiling, unchanged vector storage, cosine comparison, `1e-5` cosine-distance repeat/batch tolerance (minimum cosine similarity `0.99999`), direct OpenAI-compatible vLLM interface, configuration boundary, new-space triggers, and fail-closed behavior are frozen. Raw maximum coordinate delta is retained as a diagnostic, not used as the authoritative stability gate. Dalton and external fallback are excluded. | The neutral technical verifier passed, and Script `28` embedded all 125 original synthetic chunk candidates through the same direct vLLM path. Exact tuple, prefix, four-bucket token accounting, finite unchanged vectors, identities, and `5.96046448e-08` repeat delta passed. Script `31` persisted all 125 vectors and exact input identities through schema version 3. Script `36` qualified the amended 126-candidate embedding set without changing the embedding-space identity, and Script `37` accepted retrieval over that set. Script `79` applies the frozen numeric limit in the same cosine-distance space used by retrieval and reports raw coordinate delta separately. Org-target qualification remains. | FROZEN CONTRACT; DANKO AMENDED SYNTHETIC EMBEDDING, SCHEMA-V3 WRITER, AND RETRIEVAL PATH ACCEPTED; SCRIPT 79 COSINE-ALIGNED LIVE QUALIFICATION READY; ORG TARGET QUALIFICATION NOT RUN |
| `G11` | Persistence | PostgreSQL is the production catalog authority; pgvector stores embeddings; native PostgreSQL full-text search provides the lexical lane; immutable artifacts are reused; publication changes only affected active document versions in one transaction; SQLite is disposable-prototype-only; exact package versions follow target inventory. | Native PostgreSQL `16.15`, pgvector `0.8.7`, and Psycopg `3.1.17` are qualified on EmceeDanko. The empty accepted `rag_catalog`, exact roles, migrations `0001 + 0002 + 0003`, schema version 3, four exact token buckets, active views, and restart persistence passed. Script `31` persisted and queried the real 6-document, 230-unit, 125-chunk, 125-citation, and 125-embedding projection in a disposable database, proved read-only retrieval access, removed the disposable database, and left the accepted catalog unchanged. Remaining persistence work is the consolidated fresh-install baseline, calibrated rebuildable ANN index, backup/restore, complete corpus-command integration, and cross-component qualification. | FROZEN SCHEMA-V3 PIPELINE-WRITER CONTRACT; NATIVE RUNTIME AND REAL PRODUCER-ARTIFACT WRITER PATH ACCEPTED; REMAINING OPERATIONAL QUALIFICATION NOT RUN |
| `G12` | Retrieval | Resolve contextual turns into standalone queries without embedding the full chat transcript; resolve structured source references directly; retrieve through exact structured lookup, native PostgreSQL full-text search, and pgvector cosine lanes; deduplicate by canonical chunk identity; fuse deterministically with RRF; preserve provenance; and omit a learned reranker from the first slice. The frozen calibration correction adds citable derived blank-page status, exact document-plus-page resolution, and strict-then-OR native PostgreSQL lexical behavior. | Scripts `32` through `35` implemented the three lanes, fusion, identity mapping, and first held-out calibration. That accepted observation passed five of six cases and 12 of 13 citations and did not promote the profile. Script `36` qualified all 126 amended Nomic embeddings under chunk-method identity `5797961aee919aa73bbd99d6cc188084d57d22839a1d4cff0febc2e73e17b4b0`. Script `37` passed all six held-out cases, covered all 13 required citations, exercised the lexical OR fallback, proved read-only retrieval access, removed its disposable database, and left the accepted database unchanged. The operator froze calibrated retrieval-profile identity `33102734a29ea8170cffcfa7cdff6feae66d4663d09d7bca86c04a6419f77ad7`. Script `38` then passed 90 local tests and proved the validated YAML, application defaults, identity separation, and accepted calibration evidence agree. Native singleton query embedding passed Script `64`. Standalone contextual-query resolution, exact structured source mapping, code-owned filters, direct-query bypass, and clarification-before-retrieval now pass 246 local tests; Script `65` is their local qualification gate. | FROZEN CALIBRATED THREE-LANE RETRIEVAL PROFILE; AMENDED NOMIC PROFILE, HELD-OUT RETRIEVAL CALIBRATION, AND SCRIPT 38 FREEZE RECEIPT ACCEPTED; SCRIPT 64 ADAPTERS ACCEPTED; SCRIPT 65 SOURCE-READY |
| `G13` | Relationships | Store typed directed edges between canonical identities; automatically detect only allowlisted explicit-reference and supersedes relationships; quarantine ambiguous required internal references; retain external observations; permit only audited exception overrides; traverse at most one hop after direct fusion; and apply authorization before and after traversal. Routine relationship manifests and model-assisted discovery are excluded. | The Script `39` source implements the versioned registry, exact self-declaration inventory, explicit-reference resolution, ambiguity/unresolved quarantine classification, audited internal/external overrides, fixed-version supersession identity, and authorized one-hop traversal with cycle/target deduplication and full provenance. Script `67` connects the accepted active-relationship view to the native retrieval adapter: only edges whose evidence citation belongs to a directly retrieved chunk may expand, target filters apply before and after traversal, the active target version is resolved in the same read-only snapshot, and target passages retain seed/edge/target/version/citation provenance. | FROZEN KISS RELATIONSHIP CONTRACT; IMPLEMENTED IN NATIVE RETRIEVAL ADAPTER; SCRIPT 67 LOCAL QUALIFICATION READY |
| `G14` | Reconstruction | Group evidence by document version; remove only true duplicate chunks; retain distinct relevant excerpts from the same document; add only required structural context; reconstruct complete procedures deterministically from stored structure; use a conservative Gemma-tokenizer budget; never silently truncate, summarize conversation, or claim completeness when the complete unit does not fit. | Script `42` accepted deterministic reconstruction, provenance, grouping, diversity, atomic budgeting, and explicit `context-limit` behavior. Script `43` qualified the exact deployed Gemma tokenizer without a model call. Script `44` accepted a 32,768-token application limit partitioned into 2,048 instruction, 12,288 conversation, 16,384 evidence, and 2,048 reserved-answer tokens while leaving the Gemma service configured for 204,800. Script `45` accepted deterministic grounded-request construction. Script `46` measured the exact request at 884 prompt tokens and 2,932 tokens with its answer reserve. Script `67` connects explicit complete-procedure intent to one exact active-version inventory and all-or-nothing source-order assembly. | FROZEN AND QUALIFIED EVIDENCE-RECONSTRUCTION AND REQUEST-COMPOSITION CONTRACT; COMPLETE-PROCEDURE ADAPTER PATH IMPLEMENTED; SCRIPT 67 LOCAL QUALIFICATION READY |
| `G15` | Response contract | Use a versioned JSON multi-turn request/response envelope with explicit statuses, stable conversation and turn identities, structured source references, one source group per document version, multiple excerpt-level citations, strict citation validation, safe errors, and private-field exclusion. Open and download are disabled stretch capabilities; streaming is not required initially. Model content may be raw JSON or one isolated lower-case `json` fence with no surrounding prose. Validated cited claims, not redundant answer prose, are authoritative. Observed compatibility fields are accepted only when null or empty. The service is named **Ishikawa Retrieval API** and is a separately run native Python process inside the Ishikawa package for v1, not an independent product. Each native adapter invocation remains one request with no internal retry. The v1.1 T10 amendment permits the service to invoke grounded generation exactly one additional time only after its adapter reports a Gemma transport or validated-response failure; every other failure remains single-attempt and fail-closed. | Script `47` accepted native one-request/no-retry generation transport, runtime-secret isolation, strict response-envelope and usage validation, citation allowlisting, and complete cited-claim coverage through 152 local tests. Script `48` safely retained the first complete live synthetic response after the pre-correction validator rejected five null vLLM compatibility fields and Gemma's isolated JSON fence. The frozen correction passes 155 local tests and revalidates the retained response, all three claims, all three citations, and the held-out answer. Offline prompt measurement is 884 tokens; vLLM reported 885 live prompt tokens. Script `49` accepted the corrected retained response without another model call. Script `62` accepted the versioned multi-turn chat request and client-safe response envelopes through 212 local tests. Script `63` accepted the service identity and fail-closed orchestration through 223 local tests. Script `64` accepted native Nomic query-embedding and Gemma scope and grounded-generation adapters through 233 local tests. Query resolution and its clarification short-circuit now pass 246 local tests. Two v1.1 Script `122` runs later produced different single-case grounded-generation dependency failures, so T10 rejected pass-by-rerun and added one bounded service-layer retry. The amended source passes 376 local tests; Script `123` is its checksum-bound operator qualification gate. | FROZEN ISHIKAWA RETRIEVAL API CONTRACT; NARROWLY REOPENED AND REFROZEN BY T10; SCRIPT 123 SOURCE-READY |
| `G16` | Scope, injection, and abstention | Reject mechanically invalid requests first; require Gemma to classify every syntactically valid natural-language turn as `allow`, `needs_clarification`, or `out_of_scope` before retrieval; keep scope and injection controls separate; treat all user, conversation, and document content as untrusted; give models no tool authority; and answer only when deterministic evidence and citation checks pass. | Scripts `50`-`52` accepted the versioned scope contract, exact deployed-tokenizer budget, native transport, and one bounded live synthetic source-follow-up classification. Script `53` accepted deterministic injection scanning for seven high-signal reason classes across current questions, history, and retrieved content. A fail-closed sufficiency gate now enforces lane health, candidate and authorization presence, exact and relationship constraints, conflict, reconstruction, citation, completeness, context, and mandatory separately calibrated relevance; its relevance producer and typed sufficiency integration now pass 202 local tests. Scripts `55` and `56` accepted six responsive and six nonresponsive protected cases plus their singleton Nomic embeddings. Script `58` passed the corrected schema-v4 disposable retrieval observation and showed that responsive and nonresponsive raw vector and fused scores overlap, so no raw-score threshold is accepted. Script `59` passed the frozen PostgreSQL English-lexeme measurement, but its coverage ranges overlapped at all five depths, so retrieval-text lexeme coverage is also rejected alone. Script `60` then passed the complete citable-envelope measurement without changing retrieval, transferring truth, selecting a threshold, or giving Gemma authority. Depths 1, 3, 5, and 10 strictly separated the protected set; depth 20 did not. The operator froze depth `3` and exact three-fifths support. Operator-executed Script `61` passed the local protected replay and accepted relevance-profile identity `2a29f2499029a6e6a8f56f199b91d1a32dbab280bb9a07d502423af838804c28`. Broader held-out scope and adversarial end-to-end qualification remain. | FROZEN SCOPE, INJECTION, AND ABSTENTION CONTRACT; DEPTH-3, 60-PERCENT CITABLE-EVIDENCE RELEVANCE PROFILE FROZEN; SCRIPT 61 ACCEPTED |
| `G17` | Security/lifecycle | The first slice has no application login, individual identity, roles, or per-user document permissions. The retrieval API binds to configurable loopback, default `127.0.0.1:1384`; anyone able to use that host can search the complete active corpus. Retrieval has read-only PostgreSQL access; Gemma and Nomic have no database or document-store access; secrets use protected runtime injection; retirement propagates through derived data; open/download remains stretch work; and future identity and encryption remain possible. | Implement and qualify loopback-only binding, read-only retrieval credentials, model isolation, protected environment injection, incremental retirement propagation, content-free request correlation without user-identity claims, security tests, and preserved future authorization/encryption interfaces. | FROZEN KISS LOCAL-ACCESS SECURITY AND LIFECYCLE CONTRACT; IMPLEMENTATION AND QUALIFICATION NOT RUN |
| `G18` | Observability | Use local structured JSONL logging with `default`, `debug`, and explicitly bounded `verbose` profiles; one request identity across the web, retrieval, model, and validation path; stable failure codes; separate liveness and readiness; protected content-free audit; and no external logging or metrics service in the first slice. Secrets, vectors, raw environment values, connection strings, and private paths are prohibited at every level. | Operator-executed Scripts `94` through `97` accepted classified protected logging, owner-only verbose control, separate content-free operational metrics, and explicit 30-day operational, 30-day metrics, and 90-day audit retention through 356 tests. The accepted retention command uses protected cross-process locks, all-or-block candidate validation, content-free audit, and an optional daily native user timer. T10 adds a content-free `generation-retry` stage metric and debug `retry_state`; neither contains model output or credentials. Deployment-target integration remains subsequent work. | FROZEN KISS LOCAL OBSERVABILITY CONTRACT; SCRIPTS 94 THROUGH 97 ACCEPTED; T10 RETRY EVIDENCE SOURCE-READY; DEPLOYMENT-TARGET INTEGRATION NOT RUN |
| `G19` | Validation | Provide one operator-run per-case validation surface using standard Python and shell capabilities where practical. Every case reports `NOT RUN`, `PASS`, `FAIL`, or `BLOCKED`; synthetic expected results remain separate from implementation inputs; private evidence stays outside Git; performance is measured on target without invented thresholds. | Configuration, migrations, writer lifecycle, extraction, normalization, structural chunking, exact token measurement, embedding, schema-v3 producer-to-writer integration, all three retrieval lanes, RRF fusion, and amended held-out retrieval calibration now have numbered, checksum-bound evidence through Script `37`. Relationships, reconstruction, conversation, scope/injection/abstention, logging, backup/restore, portable install, and org-lab integration remain. | FROZEN KISS VALIDATION CONTRACT; PRODUCER PIPELINE THROUGH CALIBRATED THREE-LANE RETRIEVAL ACCEPTED; COMPLETE HARNESS NOT RUN |
| `G20` | Operator/API boundary | Use only the existing Node 24/Next.js 16.4.1 container for the bind-mounted web source. Run retrieval and one-shot corpus commands with the host's native Python. Install and run PostgreSQL/pgvector natively with host-owned database state. Do not use Python or PostgreSQL containers. Keep all application source on the host and install services boot-disabled for explicit operator start. Run the Node container with configurable host networking, bind Next.js through configurable values that default to `127.0.0.1:3000`, and configure its native retrieval URL with a default of `http://127.0.0.1:1384`. | EmceeDanko native PostgreSQL/pgvector/Psycopg qualification, installation, cluster/database bootstrap, current schema, and target-native incremental writer proof have passed. Script `98` implements and locally validates the final boot-disabled native Retrieval API user unit, exact installed foreground command, named environment boundary, failure-only restart, bounded graceful `SIGTERM`, loopback liveness, and listener/socket cleanup through 360 tests. Operator execution remains required. The containerized web service, combined stack command, refreshed portable package, deployment-target lifecycle, and org-lab qualification remain. | FROZEN AMENDED KISS NATIVE-HOST RUNTIME AND PORTABLE-PACKAGE CONTRACT; EMCEEDANKO DATABASE FOUNDATION AND WRITER ACCEPTED; SCRIPT 98 NATIVE RETRIEVAL LIFECYCLE SOURCE READY; WEB, STACK, PACKAGE, AND TARGET QUALIFICATION REMAIN; PRIOR PYTHON/PGVECTOR IMAGE CAPTURE NOT SELECTED |

### Implementation status through accepted Script 75

The detailed frozen decisions above remain unchanged. Later implementation
evidence supersedes earlier “not run” and “source-ready” wording in the table:

- Scripts `62` through `69` accepted the versioned multi-turn API,
  fail-closed orchestration, native Gemma and Nomic adapters, contextual query
  resolution, native read-only PostgreSQL retrieval, relationship and complete-
  procedure retrieval, the complete adapter against disposable target-native
  PostgreSQL, and the bounded loopback HTTP listener.
- Operator-executed Script `70` accepted the complete local configuration-to-
  runtime assembly gate. It adds the exact vLLM Gemma `/tokenize` boundary, protected
  environment providers, fixed `rag_retrieval` connection settings, active-
  view source-name resolution, all concrete dependency adapters, orchestration,
  and listener construction.
- Script `70` uses injected dependencies. It reads no credential, contacts no
  target, PostgreSQL database, or model endpoint, and does not start the
  service. Script `71` now implements the separate bounded live compatibility
  gate: two identical synthetic calls through the real native token-counter
  adapter must return the same schema-validated count. It prompts the operator
  for the Gemma credential on the target terminal, retains no prompt or
  credential, and preserves the managed service's initial state. The operator-
  executed gate passed with two identical 11-token results.
- Operator-executed Script `72` accepted that same configured runtime on the
  AMD64 application host. EmceeDanko assembled all 12 profiles, temporarily
  exercised `127.0.0.1:1384`, returned the fixed `security-rejected` response,
  made zero environment reads and dependency calls, released the port, and
  removed the temporary payload. External model-service reachability remains
  unqualified. Because Gemma and Nomic remain loopback-only on the model host,
  the application-host-to-model-host transport had to be frozen before a live
  application-host dependency test could be prepared.
- The operator froze that transport boundary after Script `72`. Ishikawa owns
  only configured endpoint URLs. The EmceeDanko prototype uses one operator-
  started SSH connection carrying local `8000` and `8001` directly to the
  model host's loopback vLLM services, leaving the existing runtime profile
  unchanged. Dalton, native-vLLM LAN exposure, firewall changes, and another
  Ishikawa service are excluded. Org-lab may instead supply its approved
  direct model-host endpoints through deployment configuration. Operator-
  executed Script `73` passed: direct native-port access remained blocked,
  both forwarded health routes returned HTTP `200`, no private key was copied,
  no API credential or content was read, and its bounded qualification tunnel
  was stopped and removed.
- The accepted transport proof does not assign forwarding lifecycle to
  Ishikawa. The operator establishes ports `8000` and `8001` before startup and
  closes them after exit. Ishikawa reads endpoint URLs from YAML and expects
  them to be reachable. Operator-executed Script `74` accepted the configured
  tokenizer and singleton embedding adapters through already-active forwarding:
  tokenization repeated at 11 tokens and the 768-dimensional embedding repeated
  with a maximum delta of zero. It did not start, change, or stop forwarding.
- The first Script `75` execution reached the configured HTTP runtime but
  blocked at its expected response contract. The empty accepted database was
  unchanged, PostgreSQL returned to stopped, port `1384` was released, and no
  raw content, vector, or credential was retained. The original runner did not
  preserve enough content-free distinctions to locate the mismatch.
- Corrected Script `75` is source-ready for one configured HTTP request through live
  Gemma scope classification, deterministic direct-query resolution, singleton
  Nomic embedding, read-only PostgreSQL retrieval, and Gemma tokenization. The
  accepted catalog remains intentionally empty, so the required result is
  `insufficient-evidence` and grounded generation must not run. Acceptance also
  requires an unchanged catalog, stopped PostgreSQL, released port `1384`, and
  unchanged operator-owned forwarding. If it blocks, the retained evidence now
  identifies only allowlisted response, trace, event, and dependency-call
  categories; it still retains no request, response, credential, or vector.
- The bounded diagnostic rerun returned HTTP `500` before any dependency call
  and identified self-recursion in Script `75`'s executor-observation wrapper.
  The qualification runner now captures the configured executor before
  replacement and proves the observer calls it exactly once. No application
  runtime module, frozen contract, database, or remote service was changed.
- The corrected operator-executed Script `75` passed. It returned HTTP `200`
  with `insufficient-evidence`; scope ran once, query resolution remained
  deterministic, singleton Nomic embedding ran once, PostgreSQL opened one
  read-only retrieval connection, Gemma tokenization ran twice, and grounded
  generation did not run. The database remained empty and unchanged, the
  listener stopped, PostgreSQL returned to stopped/disabled, and operator-
  owned forwarding remained unchanged.
- Script `76` is source-ready as the local operator-ingestion control-plane
  gate. Its 279-test suite and four focused scenarios prove validation-only
  isolation, production of changed documents only, reuse without production,
  quarantine without production, protected reports, and handoff to the
  already-accepted atomic writer. Concrete native producer and PostgreSQL
  deployment adapters are the next integration boundary.
- Operator-executed Scripts `94` through `97` accepted classified local
  logging, protected rotation, audit separation, owner-only bounded verbose
  control, separate protected content-free metrics, explicit retention,
  protected writer/retention locking, content-free retention audit, and the
  optional daily native user timer. Script `98` is source-ready for the
  boot-disabled native Retrieval API lifecycle.
- The Next.js UI, explicit native service start command, observability,
  portable installation, lifecycle operations, and org-target qualification
  remain later work.

### G01: Frozen Source-Verification Acceptance Contract

Before an extractor is accepted, protected held-out truth shall identify the
expected page inventory, intentional blank pages, reading order, hierarchy,
tables, form fields and values, ordered procedure material, repeated page
furniture, and source anchors needed to grade the six-document, 27-page
Synthetic Corpus V1 fixture.

The selected extractor shall then be run against every fixture document and
page. Acceptance requires correct document and page counts, preservation of
the known intentional blank page, and no silent invention, loss, or
reordering of required text or structure. Every discrepancy shall be recorded
explicitly. Detailed diffs remain protected; tracked evidence remains
content-free. This freezes the test contract, not a successful result. The
first Script `25` target capture passed but its original XHTML-order evaluator
blocked. The corrected physical-coordinate evaluator passed no-contact source
validation; Phase 28 extraction remains unaccepted until the same-script rerun
passes.

### G02: Frozen KISS Class-Assignment Contract

The operator shall maintain two small, versioned YAML inputs:

1. a class registry containing valid class identifiers and display names; and
2. an ingestion manifest assigning each source-document path to exactly one
   valid class.

The initial registry includes Policy/SOP and Administrative Form. An operator
may add a class such as Regulation to the registry and then assign that class
to documents in the ingestion manifest. Adding an ordinary organizational
label does not require a new classifier, metadata extractor, or chunker.

Before processing, the ingestion command shall verify that the source exists,
the assigned class exists in the registry, the source format is supported,
and the unchanged source is not being duplicated unintentionally. A missing
or unknown class fails validation. The operator-provided assignment is the
authoritative class for the first implementation; automatic content-based
class selection is deferred and shall not be required for ingestion.

All supported PDFs use the common extraction and structure-aware chunking
path. The method shall recognize implemented common structural patterns such
as headings, sections, paragraphs, lists, procedures, definitions, tables,
forms, and identifiable document references. Chunks inherit the assigned
class, document identity and version, page or source location, heading path,
structural type, detected references, and method version.

Quarantine is the observation path for a supported source whose required
structure cannot be handled safely. Evidence from quarantine determines
whether the general extractor, metadata handling, reference recognition, or
chunker needs a reviewed extension. Adding a class alone remains a
configuration change; code and tests change only when evidence identifies a
new structural behavior, metadata requirement, or reference format.

This contract supersedes the earlier proposed rule-weight, confidence-state,
class-specific-extractor, and class-specific-chunker model. Amended `D01`,
`D02`, `D10`, and `D13` now carry the authoritative operator assignment,
simple registry and manifest, stored provenance, and validation-stage rules.
No additional top-level `D` item is required.

### G03: Frozen Poppler-First Extraction Qualification Plan

The first qualification candidate is the operating-system-distributed
`poppler-utils` package. The initial adapter shall invoke:

- `pdfinfo` for validity, encryption status, page inventory, dimensions, and
  available document metadata;
- `pdftotext -layout` for page-separated raw text; and
- `pdftotext -bbox-layout` for page, block, line, word, and coordinate
  observations.

A small Python standard-library adapter shall invoke each command with an
argument vector and `shell=False`, enforce time and resource bounds, parse the
bounding-box XML/XHTML with the standard library, and preserve source and raw
outputs before normalization. For each source it shall retain the immutable
PDF, source SHA-256, `pdfinfo` output, layout text, bounding-box output, and a
content-free extraction manifest containing tool version, arguments, output
digests, observed pages, empty-page observations, warnings, timing, and
result status.

The adapter is common to all operator-assigned document classes. Extraction
collects page-anchored text and geometry; later common structural processing
uses those observations to recognize headings, lists, procedures, tables,
forms, and references.

Acceptance requires the `G01` comparison across all six synthetic documents
and 27 pages, including the intentional blank page, reading order, heading and
list positions, table geometry, form label/value and checkbox relationships,
stable anchors, and repeat output. An encrypted, malformed, image-only,
resource-limit-exceeding, or structurally ambiguous source is quarantined.
OCR is outside the first vertical slice.

If this candidate cannot preserve required structure, the first fallback to
evaluate is the smallest applicable capability from the same package, such as
`pdftohtml -xml`. A different library or package is considered only when
recorded evidence shows the native-first candidate set is insufficient under
`D03`. No fallback is added preemptively.

This freezes the selection and evaluation order, not an extraction pass. The
accepted target inventory identifies Poppler tools `24.02.0` and Ubuntu
package revisions `poppler-utils 24.02.0-1ubuntu9.10` and
`24.02.0-1ubuntu9.11`. The latter is a bounded distribution patch revision:
the live 30-document repeatability capture produced the same 943 structural
candidate records as the frozen corpus-v3 representation; only package and
archive provenance digests changed. Downstream publication continues to
require exact candidate identity and text. The first target capture passed its
inventory, page, blank-page, repeatability, and cleanup contracts, then the
original local grader blocked on bounding-box ordering. Corrected Script `25`
is source-ready; the acceptance result remains blocked pending its same-command
rerun.

### G04: Frozen Common Normalization Contract

One small Python standard-library normalizer shall serve every operator-
assigned document class. The immutable PDF and all raw Poppler outputs remain
unchanged. Canonical text uses Unicode NFC, LF line endings, and only non-
semantic whitespace normalization. Wrapped lines are joined only when source
geometry places them in the same paragraph. Visible hyphens remain; only an
explicit soft hyphen or extractor-identified layout hyphenation may be
removed.

The canonical layer preserves headings, paragraphs, lists, step numbers,
identifiers, punctuation, values, checkbox states, pages, coordinates, and
source anchors. Tables and forms remain structured and are not flattened into
ordinary paragraphs. Every transform records its rule identity and source
span. Uncertain reading order or unsafe structural association quarantines the
affected source instead of being guessed.

Repeated page furniture is confirmed only when the same normalized text
appears at a consistent top or bottom page position on at least three nonblank
pages and on a majority of eligible pages. Confirmed furniture remains in raw
evidence and a structural record but is omitted from ordinary embedding text.
If any condition is unmet, the text is retained. The exact page-band and
coordinate tolerance are Tier 2 values that must be qualified against the
synthetic fixture before activation.

This freezes normalization behavior, not an implementation or successful
qualification result. Both remain `NOT RUN`.

### G05: Frozen Nomic Token-Measurement Contract

Embedding chunks and embedding queries use
`nomic-ai/nomic-embed-text-v1.5` at the accepted immutable snapshot revision
`e9b6763023c676ca8431644204f50c2b100d9aab`. The authoritative embedding
tokenizer is the `tokenizer.json` carried by that same snapshot. It is not a
separately selected generic tokenizer and is not Gemma's tokenizer. The exact
tokenizer artifact digest shall be recorded in the method profile and proved
against the deployed Nomic service before ingestion.

The accepted Nomic service posture has vector dimension 768 and an effective
maximum model length of 2048 tokens. The complete Nomic input, including the
`search_document:` or `search_query:` prefix, headings, breadcrumbs, labels,
repeated table headers, and other added context, must fit within that 2048-
token ceiling. The method counts and records canonical content, added context,
prefix, and total input separately. It fails closed before submission rather
than relying on service-side truncation.

The common initial qualification target is 512 total Nomic tokens. This is a
target, not a forced size: short meaningful structures are not padded, and
complete table rows, form fields, definitions, procedure steps, and other
atomic structures remain intact when safe. No document-class-specific target,
blind overlap, token-only split, truncation, or silent loss is introduced.
Over-target or over-ceiling material follows the structural fallback and
quarantine rules under `G06`.

Gemma grounded inference is a separate token domain. Retrieval-time prompt,
conversation, evidence, and generation budgets shall use the exact tokenizer
from the deployed Gemma snapshot; a Nomic token count shall never be treated
as a Gemma token count.

The model roles, pinned Nomic revision, Nomic tokenizer authority, 2048-token
total ceiling, and 512-token starting target are frozen. Scripts `28`, `36`,
and `37` accepted the Nomic tokenizer, embedding, and retrieval behavior.
Scripts `43` and `44` separately accepted the exact Gemma tokenizer identity
and the initial Gemma context budget. Those two token domains remain distinct.

### G06: Frozen Structural Fallback Contract

One deterministic fallback algorithm serves every operator-assigned document
class. It begins with natural structural units and may assemble compatible
adjacent units toward the 512-token target without crossing a semantic
boundary. A complete atomic unit may remain above the target when its total
Nomic input fits within the 2048-token ceiling.

An over-ceiling unit is divided only at the next safe internal boundary:

- narrative: subsection, paragraph, then sentence;
- procedure: substep, list item, paragraph, then sentence;
- definition: paragraph, then enumerated clause;
- table row: nested list or paragraph without separating associated headers,
  conditions, or values; and
- form field: paragraph or list inside the value without separating its
  label, value, state, or form identity.

Every split part retains its full heading path, original structural-unit
identity, applicable step number, term, field label or table headers, exact
source pages and spans, part number and count, and ordered previous/next
continuation identities. This permits complete procedures and other divided
units to be reconstructed in source order.

Blind body-text overlap, token-only splitting, truncation, omission,
reordering, and unrelated padding are prohibited. If no safe part including
its required repeated context fits within 2048 total Nomic tokens, the source
is quarantined for review or a reviewed structural extension. This freezes
the contract; implementation and qualification remain `NOT RUN`.

### G07: Frozen Compact Logical Metadata Contract

Machine-produced canonical interchange uses versioned JSON objects and JSONL
collections because Python supports them directly. Human-edited class-registry
and ingestion-manifest configuration remains YAML. The serialization format
does not define database tables; PostgreSQL under `G11` shall store the same
logical records.

The eight logical record types are `source_document`, `document_version`,
`structural_unit`, `chunk`, `citation`, `relationship`, `ingestion_run`, and
`publication_batch`. Every record has a small common envelope containing
`schema_version`, `record_type`, `record_id`, `method_profile_id`, and the
applicable `ingestion_run_id`.

At minimum, a chunk records its identity, document and version identities,
operator-assigned class, structural type, ordered structural-unit identities,
heading path, page and source spans, continuation identities and part counts,
the separate Nomic content/context/prefix/total token counts, exact embedding
projection, and publication state. It must resolve to its document version,
structural units, and citation anchors.

The server-private record may contain source paths, raw artifact references,
digests, internal diagnostics, and authorization references. The retrieval
API constructs a separate explicit client-safe source projection containing
only approved fields such as display name, assigned class, page, heading path,
relevant excerpt, and citation identifier. It never serializes a database row
or private record directly.

Schemas use explicit required, optional, nullable, repeated, and enumerated
fields. Unknown fields, invalid types, unknown references, unresolved required
values, and incompatible schema versions fail validation. Optional absence is
represented explicitly, and no unrestricted catch-all metadata dictionary is
permitted. Exact identity derivation remains `G08`; physical PostgreSQL schema
and indexes remain `G11`. This freezes the logical contract; schemas,
validators, and qualification remain `NOT RUN`.

### G08: Frozen Catalog-Controlled Document Identity Contract

Phase 28 shall use three small, human-maintained YAML inputs with distinct
purposes:

- `document_classes.yaml` defines the allowed document classes;
- `document_catalog.yaml` registers stable logical document keys and their
  display names and status; and
- `ingestion_manifest.yaml` associates each source path with one existing
  document key and one allowed assigned class.

The operator reviews and edits these YAML files directly. No document-catalog
command interface is required for the first implementation. The document key
is registered once in `document_catalog.yaml` and is reused for every revision
of that logical document.

Ingestion preflight shall validate the complete catalog and manifest before
chunking. Catalog keys must be unique. The validator shall also reject simple
punctuation- and spacing-equivalent key collisions so values such as
`policy.social-media`, `policy.socialmedia`, and `policy_social_media` cannot
silently become separate logical documents. This comparison detects a
collision but does not automatically rename or merge either entry.

Every ingestion entry must reference a key already present in the document
catalog. An unknown key is quarantined with the stable reason
`UNKNOWN_DOCUMENT_KEY`; the chunker is not invoked for that source, and a
required quarantined source blocks candidate promotion. Ingestion never
creates a document key implicitly. The provisional digest-bound identity
permitted by `D11` is limited to discovery and quarantine evidence and cannot
enter the searchable corpus.

No organizational version-label scheme is required. A document revision is
identified internally by its stable logical document identity plus the exact
immutable source SHA-256 digest. Identical bytes under the same key reuse the
same document-version identity. Changed bytes under that same key create a new
candidate document version. A human-readable effective date or version label
may be added later as explicitly defined optional display metadata, but it
shall not control identity or lineage.

The remaining content-bound identity, duplicate, supersession, rollback,
deletion-tombstone, and referential-integrity requirements remain as frozen in
`D11`. This freezes the KISS identity workflow; schemas, validators, and
qualification remain `NOT RUN`.

### G09: Frozen Operator-Invoked Incremental State Machine

Ingestion is an operator-invoked executable workflow. Its manifest is an
incremental batch containing only new or changed document paths, their
existing catalog keys, and their assigned classes. Retirement is an explicit
status change in `document_catalog.yaml`; omission from an ingestion manifest
never retires a document. The workflow leaves no listener or daemon behind.

Preflight validates the complete catalog and the batch manifest before
processing. For each listed document, the stages are discover, fingerprint,
validate class assignment, extract, normalize, structure, chunk, embed, and
validate. Each stage records `pending`, `running`, `succeeded`, `failed`,
`quarantined`, or `skipped` plus exact input and output identities,
implementation and tool versions, attempt, timing, and a stable content-free
result code.

Only documents listed in the batch are considered for processing. A listed
source whose digest and all semantic inputs match an accepted document version
is reused and recorded as unchanged. Other active documents are not extracted,
chunked, embedded, copied, or rebuilt.

Processing may continue after a batch document fails or is quarantined so the
operator receives a complete report, but no change from that batch becomes
searchable when a required item fails. A stale `running` stage after a crash is
reconciled before retry. Repeated identical input never duplicates logical
documents, versions, chunks, citations, lexical records, or vectors.

Validation proves the affected document artifacts are complete and compatible
with the active corpus: schema and reference validity, source and derived
digests, citation resolution, Nomic compatibility, expected artifact counts,
and required gates. After validation, one PostgreSQL transaction publishes
only the batch's additions, revisions, or explicit retirements. Unchanged
documents remain untouched. The publication record preserves prior active
document versions for atomic rollback.

Prototype run state may use the frozen JSON records. PostgreSQL becomes the
production state and catalog authority under `G11` without changing this
workflow. This freezes the incremental state machine; implementation and
qualification remain `NOT RUN`.

### G10: Frozen Direct-vLLM Embedding Contract

The embedding adapter calls the local OpenAI-compatible Nomic vLLM
`/v1/embeddings` interface directly. Dalton, another convenience wrapper, and
external-provider fallback are excluded. The endpoint base URL, credential
reference, timeout, retry limit, and batch size are validated deployment
settings; they do not alter embedding-space identity.

The embedding-space identity is fixed to:

- model `nomic-ai/nomic-embed-text-v1.5`;
- immutable revision `e9b6763023c676ca8431644204f50c2b100d9aab`;
- model digest
  `9e7d262b1fe5ea350782829496efa831901b77486bbde1cea54a4c822d010d5c`;
- tokenizer digest
  `d241a60d5e8f04cc1b2b3e9ef7a4921b27bf526d9f6050ab90f9267a1f9e5c66`;
- mean-token pooling, `search_document:` and `search_query:` prefixes, 768
  dimensions, and a 2048-token total-input ceiling;
- no application-side vector transform, cosine comparison, and maximum repeat
  and single-versus-batch cosine-distance drift of `1e-5`, equivalent to a
  minimum cosine similarity of `0.99999`.

Qualification also records the maximum change in any individual vector
coordinate. That value is diagnostic only; it is not the authoritative gate
because retrieval ranks vectors by cosine distance rather than by the largest
single-coordinate difference.

The adapter fails closed on an unavailable or incorrect model identity,
artifact or tokenizer mismatch, empty or over-limit input, silent truncation,
timeout, malformed response, missing or extra vector, wrong dimension,
non-finite value, or numeric-tolerance violation. A failed batch publishes no
partial result. A change to the model, revision, artifact, tokenizer, pooling,
prefixes, dimension, input ceiling, transformation, or comparison metric
creates a new embedding space and requires a separately qualified candidate
index.

The repository supplies the action-named `verify-embedding-service` and
`verify_embedding_service.py` acceptance files. Only those neutral basenames
and their neutral emitted schema may leave the repository; repository paths,
phase and gap identifiers, lab names, and control documentation do not. This
freezes the complete contract. The Danko technical compatibility run passed.
The first wrapper's stored-credential access was rejected and removed without
changing the technical tests or results; the retained wrapper requires an
operator-entered key. Org target qualification remains `NOT RUN`.

### G11: Frozen KISS Incremental PostgreSQL Persistence Contract

PostgreSQL is the production runtime catalog authority. The same PostgreSQL
deployment uses pgvector for embeddings and native PostgreSQL full-text search
for the lexical retrieval lane. The first implementation does not add a
separate vector database, search engine, or persistence service. SQLite is
permitted only for disposable rapid prototypes and is not a release,
migration, or production authority.

Immutable content-addressed artifacts preserve source and derived records.
Unchanged artifacts are reused. PostgreSQL records ingestion runs,
publication batches, and the active document version for each logical
document. Vector and lexical indexes are derived and rebuildable from the
immutable artifacts and catalog records.

Publication changes only the document versions affected by a validated batch
in one PostgreSQL transaction. Readers observe the prior active versions or
the complete validated change, never a partial mixture. Rollback restores the
prior active versions recorded for that batch. No ordinary document addition,
revision, or retirement rebuilds unrelated documents.

Schema changes use plain versioned SQL migrations and native PostgreSQL
operator tooling. Backup and restore use native PostgreSQL tools, and a
successful restore exercise is required before production acceptance. Exact
PostgreSQL and pgvector versions are selected and pinned only after target
package inventory; package availability does not reopen this architecture.
This freezes the incremental persistence contract. EmceeDanko package
qualification, installation, database bootstrap, and initial migration `0001`
have passed. Catalog/manifest validation, ingestion/publication, retrieval,
backup/restore, and integrated qualification remain implementation work.

### G12: Frozen Three-Lane Retrieval Contract

Each conversational turn retains the operator's original message. A
deterministic resolver produces a standalone retrieval query from the bounded
conversation context, but the full chat transcript is never embedded as the
query. Structured references such as `Source 1` resolve through retained
citation and document identities rather than semantic guessing.

Eligible queries use three independently traceable retrieval lanes:

1. exact structured lookup for known document keys, identifiers, citations,
   procedure steps, table anchors, and other canonical fields;
2. native PostgreSQL full-text search for lexical matching; and
3. pgvector cosine search over the frozen Nomic embedding space.

Candidates are deduplicated only by canonical chunk identity. Multiple
distinct chunks from the same document remain eligible and may later be
grouped for presentation. Reciprocal rank fusion combines lexical and vector
ranks deterministically because their native scores are not directly
comparable. A verified exact identifier or citation match may receive a
separate deterministic priority. The first slice uses equal lane weights and
no learned reranker.

Candidate depths, the RRF constant, PostgreSQL text-search configuration,
vector search parameters, and exact-priority rules are versioned Tier 2
method-profile settings. Initial values must be calibrated against held-out
synthetic retrieval cases before promotion. A required lane failure fails the
request unless a specific degraded mode has been configured and separately
validated; degradation is never silent.

The retrieval record preserves the original and resolved query, structured
references, lane eligibility, per-lane ranks and scores, exact-match reason,
filters, active corpus publication state, method profile, model and index identities, chunk
deduplication, and fusion result. Relationship traversal occurs only after
direct fusion. A material retrieval change creates a new method profile and
requires retrieval requalification; it does not require reingestion unless
stored projections or embedding inputs change. Implementation, calibration,
and qualification remain `NOT RUN`.

The first held-out calibration implemented by Scripts `32` through `35`
exposed two concrete gaps. The intentional blank page had no citable retrieval
projection, and strict PostgreSQL full-text search returned no candidates for
the held-out natural-language wording. The following bounded correction is
frozen:

1. A page that the accepted extraction inventory verifies as blank produces
   one deterministic derived `page_status` retrieval candidate. Its statement
   is limited to the verified absence of extractable text, its provenance
   identifies it as derived evidence, and its citation anchors the exact page.
   It never invents document content.
2. The exact lane may resolve one unambiguous explicit document identifier
   plus one explicit page number directly to the active page citation,
   preferring `page_status` evidence for a verified blank page.
3. The lexical lane runs strict native PostgreSQL full-text search first. Only
   when it returns no candidates does the same lane run a native PostgreSQL OR
   fallback over the normalized query lexemes. The fallback is recorded in
   lane provenance and does not replace vector retrieval or RRF.
4. These changes create a new versioned method-profile identity and require
   Nomic measurement, embedding, and retrieval requalification. They require
   no database migration because the accepted schema already represents the
   projection, citation, vector, and provenance fields.

The phrase `method profile` covers two related boundaries here; they must not
be confused with a user profile, model profile, or PostgreSQL role. The
`method_profile_id` carried by the chunks is specifically the canonical hash
of the chunk-construction rules. Adding the derived `page_status` candidate
changed those rules and therefore changed chunk identities and embedded
inputs. The new chunk-method identity prevents artifacts produced by the old
and amended chunk rules from being silently mixed. Script `37` separately
records the complete calibrated retrieval-settings envelope: exact
document-page routing, lexical strict-then-OR behavior, candidate depths,
cosine distance, RRF constant and weights, and reranker exclusion. The
accepted schema already stores chunk-method provenance, so the amended
candidate set required regeneration and requalification rather than a
database migration. The frozen boundary names both explicitly: chunk-method
identity `5797961aee919aa73bbd99d6cc188084d57d22839a1d4cff0febc2e73e17b4b0`
and calibrated retrieval-profile identity
`33102734a29ea8170cffcfa7cdff6feae66d4663d09d7bca86c04a6419f77ad7`.

The strict lexical query uses PostgreSQL `websearch_to_tsquery` with the
accepted `english` text-search configuration. PostgreSQL, not Gemma or an
operator-maintained word list, parses the query, removes configured stop
words, and normalizes the remaining content words into lexemes. For an
ordinary query with no explicit web-search operator, the retained lexemes are
combined with `AND`. If that strict query returns no candidates, Ishikawa
constructs a second native PostgreSQL query that combines the same retained
lexemes with `OR`. Candidate provenance records whether `strict` or
`or_fallback` produced the lexical results. The earlier shorthand
`significant terms` means these PostgreSQL-retained lexemes.

Local implementation and regression validation passed. Script `36` then
qualified all 126 candidates through the authoritative Nomic service,
including the single citable `page_status` candidate. Exact token measurement,
unchanged 768-dimensional vectors, local artifact validation, checksums, and
target cleanup passed. Script `37` completed the disposable-database
recalibration: six of six held-out cases passed, all 13 required citations
were covered, the lexical OR fallback was observed, and the profile was found
promotion-eligible. The disposable database was removed, the accepted
database was unchanged, and the retained observation sidecar verified.
The operator then froze the calibrated settings: exact, lexical, vector, and
fused depths of 20; PostgreSQL `english` strict-then-OR lexical behavior;
cosine vector distance; equal unit lane weights; RRF constant 60; and no
learned reranker. The validated `method_profile.yaml`, distinct retrieval-
profile identity, application defaults, and 90-test local suite passed Script
`38`. The retained content-free receipt closes the calibrated-profile freeze;
`G13` relationship implementation is the next gate.

### G13: Frozen KISS Relationship Contract

Relationships are typed directed edges between canonical document, version,
section, table, procedure, or chunk identities. The first slice supports only
allowlisted explicit-reference and `supersedes` relationship types. Ingestion
detects references present in extracted content and resolves them against the
catalog automatically; operators do not maintain routine relationship
manifests.

An edge is published only when the target resolves unambiguously. An
ambiguous required internal reference is retained as an unresolved
observation and quarantines the affected document. A clearly external
reference is retained as an external observation and does not invent an
internal target. An audited operator override is allowed only as an exception
for a quarantined case and must pass through a new candidate run and normal
promotion. Model-generated or model-suggested relationship discovery is not
part of the first slice.

Resolution distinguishes a fixed version target from a logical document
target and reevaluates logical targets when document versions change.
Retrieval may traverse one relationship hop only after direct three-lane
fusion. Authorization and metadata filters apply before traversal and again
before response construction; a relationship must not reveal the existence,
title, or content of an unauthorized target. Cycle protection and canonical
identity deduplication are mandatory.

Every relationship-derived result records its direct-retrieval seed, edge
type and direction, resolved target, source citation, and inclusion reason.
Changes to recognition or resolution regenerate affected edges and require
relationship retrieval requalification. Implementation and qualification
remain `NOT RUN`.

### G14: Frozen Evidence-Reconstruction Contract

Reconstruction begins with the fused direct chunks from `G12` and separately
identified relationship-derived chunks from `G13`. It removes only exact
canonical chunk duplicates and exact duplicate retrieval projections while
preserving every valid citation anchor. Distinct relevant chunks from the
same document remain available. Evidence is grouped by document version so a
single displayed source may contain multiple excerpts.

The method adds only the structural context required to interpret a selected
chunk, including its heading path, applicable definition, table headers, form
label, procedure identity, prerequisites, conditions, warnings, and linked
continuations. A normal procedure question returns the matching steps and the
context necessary to interpret them. A request for the complete procedure
reconstructs it from canonical parent, ordered-step, substep, and continuation
links; similarity search is not used to rediscover all of its parts.

The evidence package uses the pinned Gemma tokenizer for generation-context
measurement and begins with a deliberately conservative limit rather than the
full deployed context window. Numeric evidence, conversation, instruction,
and answer budgets and per-document diversity limits are versioned Tier 2
method-profile settings calibrated against held-out cases. An explicit
single-source request may use a separately qualified diversity rule.

No atomic structural unit is truncated mid-unit. If a requested complete
procedure or other indivisible unit cannot fit, the response is
`context-limit`; it must not return a partial unit while claiming
completeness. Conversation history is neither silently discarded nor silently
summarized. If accepted conversation context cannot fit under the configured
policy, the response is also `context-limit`.

The accepted initial application budget is 32,768 tokens: 2,048 for trusted
instructions, 12,288 for accepted conversation, 16,384 for evidence, and
2,048 reserved for the answer. The deployed Gemma service remains configured
for 204,800 tokens. The smaller application limit is intentional and may be
revised only through a new versioned profile and requalification. Scripts `43`
and `44` qualified the exact deployed tokenizer identity and every numeric
boundary without calling the model.

The reconstruction record preserves selected and omitted candidates,
document grouping, expansion links, ordering, token accounting, citation
anchors, and the reason each unit was included. A reconstruction-rule or
budget change creates a new method profile and requires retrieval
requalification; it does not require reingestion unless a stored projection
changes. Reconstruction implementation, tokenizer qualification, numeric
budget, grounded-request construction, and exact composed-request measurement
are accepted through Script `46`. The accepted synthetic request is 884 prompt
tokens; with the 2,048-token answer reserve it uses 2,932 of the 32,768-token
application limit and leaves 29,836 tokens. Latency and live grounded-answer
quality remain later gates.

### G15: Frozen Retrieval-API Contract

The retrieval API uses a versioned JSON request and response envelope for
multi-turn chat. A request carries a conversation identity, turn identity,
current user message, optional structured references to previously returned
sources or citations, and allowlisted filters. The server resolves the active
active corpus publication state and method profile; clients do not choose private internal
identities.

The response status is one of `answered`, `clarification-required`,
`insufficient-evidence`, `out-of-scope`, `security-rejected`,
`context-limit`, `temporarily-unavailable`, or `internal-error`. One source
group represents one document version and contains a stable opaque identity,
its conversation-stable `Source N` label, safe display metadata, and one or
more excerpts.

Each excerpt contains an opaque citation identity, the approved exact excerpt,
page or source range, structural path, and a table, row, form, field,
procedure, or step anchor when applicable. Answer claims cite those excerpt
identities. Response validation rejects or withholds any unknown, mismatched,
or unauthorized citation.

Filesystem paths, private metadata, raw retrieval scores and ranks, prompts,
credentials, internal topology, and stack traces are never client fields.
Errors use stable content-free codes and safe corrective text. Open-document
and download-document are disabled stretch capabilities in the first slice.
Streaming is not required initially. Additive optional fields may remain
compatible, but a material change to identities, statuses, citation meaning,
required fields, or authorization behavior requires a new API version.

The exact `ishikawa.chat-request.v1` and `ishikawa.chat-response.v1`
envelopes, limits, eight statuses, structured prior-source references,
allowlisted filters, claims-derived answers, citation checks, source groups,
safe error mapping, and private-field exclusions are now implemented. They
pass 212 local tests and are source-ready in Script `62`. Native HTTP
listening and end-to-end retrieval-service orchestration remain `NOT RUN`.

The later frozen v1.3 decisions `V13-13` through `V13-17` preserve that trust
boundary. V13-13 first versioned the changed answer contract as
`ishikawa.chat-response.v3`; frozen V13-19 subsequently versions the current
client response as `ishikawa.chat-response.v4` to carry strict content-free
turn diagnostics without changing those answer and citation semantics.
An answered response now contains one ordered sequence of coherent
citation-bearing segments, with no competing answer field or duplicate claim
list. The browser initially displays only complete structural roots anchored
by citations actually used in those segments. `POST /v1/document` separately
reconstructs selectable text for one exact active document version through a
read-only repeatable-read transaction. Viewed document bodies are not sent to
Gemma, retained in browser `sessionStorage`, or served as original PDFs.

### G16: Frozen Scope, Injection, and Abstention Contract

Fixed application code first performs mechanical request validation: JSON and
schema validity, required fields, size and encoding limits, conversation and
source-reference shape, and applicable authorization. A request that fails
these checks is not a valid question and is rejected without a model call.

Every syntactically valid natural-language user turn, including a follow-up
about a prior answer or `Source N`, must then receive an explicit scope
classification from the configured local Gemma endpoint before retrieval.
The classifier receives the current turn plus only the bounded accepted
conversation context and structured source references needed to understand
it. It returns a strict structured result of `allow`,
`needs_clarification`, or `out_of_scope` with an allowlisted reason code; it
does not answer the question. Only `allow` reaches the retrieval workflow.

The allowed scope is organizational policy, applicable regulation, code of
conduct, operating procedures, professional organizational work, and
follow-ups about previously returned answers or sources. Ambiguous potentially
professional questions return `needs_clarification` rather than being guessed
or automatically denied.

Scope classification and prompt-injection defense are independent gates. An
in-scope question can still be malicious. User input, accepted conversation
history, and every retrieved document or excerpt are untrusted data.
Retrieved text is evidence and cannot change system policy, authorization,
source filters, endpoints, prompts, or executable behavior. Direct-input and
retrieved-content controls may reject suspicious instructions, role
impersonation, obfuscation, prompt extraction, or exfiltration attempts.

Gemma has no shell, filesystem, database-write, network, or other tool
authority. All model outputs are untrusted and must pass strict schema and
policy validation. A malformed classifier or resolver result fails closed.

After retrieval and reconstruction, fixed application logic evaluates
evidence sufficiency using candidate presence, calibrated retrieval behavior,
required structure and relationship coverage, source conflicts,
authorization, context completeness, and citation validity. Gemma's claimed
confidence is not a sufficiency signal. Inadequate evidence returns
`insufficient-evidence`; incomplete requested structures return
`context-limit`; identified injection returns `security-rejected`. The first
slice never falls back to an uncited general-model answer.

The frozen relevance profile measures PostgreSQL `english` lexeme support
over the citable envelope of the top three fused chunks. It returns
`qualified` only when `supported_count * 5 >= question_lexeme_count * 3`;
otherwise it returns `insufficient`. The comparison uses integer arithmetic,
preserves exact-reference constraints and retrieval ranking, and gives Gemma
no decision authority. The profile and typed sufficiency integration pass 202
local tests. Operator-executed Script `61` bound and replayed the accepted
Script `60` protected observation, classified all 12 protected cases correctly,
and accepted profile identity
`2a29f2499029a6e6a8f56f199b91d1a32dbab280bb9a07d502423af838804c28`.

The request record preserves content-free gate outcomes, reason codes, and
policy and method-profile versions. Scope rules, classifier prompts or model,
injection controls, sufficiency thresholds, conflict behavior, and citation
coverage are versioned method-profile settings and require adversarial and
retrieval requalification when changed. Retrieval-API integration and broader
adversarial end-to-end qualification remain `NOT RUN`.

### G17: Frozen KISS Local-Access Security and Lifecycle Contract

The first implementation has no application login, individual user identity,
roles, or per-user document permissions. The retrieval API binds to
`127.0.0.1:1384` by default, and only a browser or process on that host can
connect. Host and port remain deployment-YAML settings; non-loopback exposure
is outside the first implementation. Anyone able to use the local host while
the service is running can search the complete active corpus.

The application records an opaque request identity for correlation but does
not claim to know which person submitted a request. Retrieval uses a read-only
PostgreSQL credential and cannot ingest, publish, retire, roll back, or alter
corpus data. The operator-invoked ingestion workflow owns those changes.
Gemma and Nomic have no direct PostgreSQL or document-storage access.

Secrets are supplied at runtime through protected environment injection or a
restrictively permissioned environment file. They are never stored in source,
ordinary YAML, container images, prompts, logs, or corpus metadata.

An explicit retirement propagates through active chunks, embeddings, lexical
entries, citations, relationships, and caches according to retention policy.
Open-document and download-document remain unimplemented stretch work under
`G15`, not an active `G17` feature.

Canonical records preserve optional future document-version authorization
references so verified identity and per-document permissions can be added
later. Transport and at-rest encryption remain planned hardening unless policy
makes them mandatory. Implementation and qualification remain `NOT RUN`.

### G18: Frozen KISS Local Observability Contract

The first implementation writes versioned structured JSONL events locally and
does not add an external logging database, collector, metrics service, or
dashboard. It exposes exactly three logging profiles:

- `default` records safe operational status, timing, counts, component,
  request identity, and stable outcome or failure code;
- `debug` adds content-free processing decisions, retrieval-lane counts and
  ranks, token-budget accounting, retry state, and sanitized exception type;
  and
- `verbose` may add only explicitly classified questions, excerpts, prompts,
  and answers for a bounded protected troubleshooting session.

Secrets, credentials, authorization values, vectors, raw environment values,
database connection strings, private source paths, and unclassified object or
exception dumps are prohibited at every profile. Verbose capture requires an
explicit local operator action, a declared duration and scope, a protected
destination, and automatic return to the prior profile at expiration or
restart.

One opaque request identity correlates the Next.js API, retrieval API, Gemma
scope decision, exact/lexical/vector lanes, fusion, reconstruction, Gemma
answer generation, citation validation, and final response. It identifies a
request, not a person. Stable failure codes carry safe retry and operator
guidance without exposing private content.

The services expose simple `/live` and `/ready` endpoints. Liveness reports
only that the process responds. Readiness checks required configuration,
PostgreSQL, Nomic, Gemma, active corpus state, and storage without exposing
topology or secrets. Security and corpus-change events use a separate
protected local audit JSONL destination. Rotation and retention are deployment
settings.

Operator-executed Scripts `94` through `97` accepted classified protected
JSONL logging, the owner-only local verbose-control surface, separate
content-free operational metrics, and retention scheduling through 356 tests.
Retention uses bounded per-family settings, cross-process file locks,
all-or-block candidate validation, audited deletion, an installed command, and
an optional daily systemd user timer. It does not start the Retrieval API or
contact a database, model, credential, corpus, or external telemetry service.
Deployment-target observability integration remains.

### G19: Frozen KISS Validation Contract

Phase 28 provides one operator-run validation command and uses standard Python
and shell capabilities where practical. It does not add a validation service.
Every individual case begins `NOT RUN` and ends `PASS`, `FAIL`, or `BLOCKED`
with a content-free evidence reference. A missing or stale result never becomes
an inferred pass, and aggregates never hide a failed required case.

The Synthetic Corpus V1 expected results are held-out truth: the known correct
page inventory, structures, chunks, references, retrieval evidence, and
expected answers used to grade the implementation. “Held out” means those
answers remain separate from implementation code, prompts, and tuning inputs
so the method cannot be written to reproduce the answer sheet. They may remain
in an ignored or otherwise protected local evaluation location; this does not
mean the synthetic content is an organizational secret.

The command validates configuration and document keys; extraction and
normalization; structural chunks, tables, procedures, and citations;
incremental ingestion and unchanged-artifact reuse; PostgreSQL, pgvector, and
lexical indexing; all three retrieval lanes and RRF; relationships and
reconstruction; multi-turn source references; Gemma scope classification;
injection rejection, abstention, and citation enforcement; logging-profile
inclusions and exclusions; rollback, retirement, backup, and restore; and
portable installation and startup.

Performance is measured on the actual target in warm and cold conditions
without inventing an unsupported latency or throughput requirement. Private
corpus evidence remains outside Git; tracked results contain only safe status,
versions, checksums, and evidence references. Portable installation is proved
first on EmceeDanko and then through the required org-lab integration cases.
Implementation and qualification remain `NOT RUN`.

### G20: Frozen Amended Native-Host Runtime and Portable-Package Contract

Application and corpus-processing source remains in ordinary host directories.
Only the browser application uses Docker: the existing unchanged Node
24/Next.js 16.4.1 developer image runs the bind-mounted Next.js source. The
retrieval API and every one-shot extraction, chunking, ingestion, validation,
publication, and recovery command use native host Python. PostgreSQL and
pgvector are installed and run natively on the host. Python and PostgreSQL
containers are explicitly excluded.

The native Python implementation uses the target's supported `/usr/bin/python3`
and prefers distribution-provided libraries. It does not modify the system
Python environment with untracked packages. A dedicated host virtual
environment is allowed only for reviewed dependencies unavailable as suitable
distribution packages, and its exact offline inputs, hashes, licenses, and
rebuild procedure become package artifacts. EmceeDanko already has Python
`3.12.3`, PyYAML, and Poppler; its remaining Python application dependencies
have not been selected or installed.

Native PostgreSQL owns its distro-managed host data directory, tables,
indexes, transaction state, and metadata. pgvector is installed as a native
PostgreSQL extension. The database listens only on host loopback, retrieval
uses a dedicated least-privilege database role, and neither the browser nor
the Node container receives database credentials. Operators do not edit or
selectively copy internal database files. Source documents, source code,
quarantine, exports, and logical/physical backups use separate declared host
locations. Native package versions, database-major compatibility, install
behavior, backup/restore, and upgrade behavior require target evidence.

The Next.js container remains the sole application container. Its network mode,
bind address, port, and native retrieval URL are Tier 3 deployment settings.
Defaults are host networking, explicit Next.js binding to
`127.0.0.1:3000`, and retrieval URL `http://127.0.0.1:1384`. Native retrieval
separately defaults to `127.0.0.1:1384`. These defaults allow the Next.js
server to call the native host service while keeping both listeners
loopback-only. Configuration validation rejects a non-loopback bind unless the
deployment explicitly enables the already-frozen external-exposure exception
under `G17`.

The native retrieval service, native PostgreSQL service, and single Next.js
container are installed boot-disabled and start only through an explicit
operator command. The operator start path brings up PostgreSQL, retrieval, and
then Next.js after readiness checks; stop occurs in reverse order. Corpus
processing remains an explicit one-shot command and leaves no listener,
watcher, scheduler, or worker behind.

The fresh-deployment package contains the accepted Node/Next.js image, host
application source, target-native package payloads or exact acquisition
manifests, reviewed Python dependency material when required, versioned
configuration, one consolidated final database schema, boot-disabled native
service units, checksums, dependency/license inventory, validation, and
operator documentation. It contains no development migration or repair chain,
Python image, PostgreSQL image, corpus, database state, secrets, org-specific
endpoints, or private evidence. Forward migrations for an already-installed
supported release belong to a separate, explicitly selected upgrade package.

The earlier Script `04` capture of Python and PostgreSQL/pgvector images is a
valid historical artifact but is not selected for deployment and shall not be
transferred or loaded. It is retained only until the operator chooses whether
to delete the ignored local artifact. The existing Node image on EmceeDanko
remains accepted and does not need transfer.

Host distribution versions now directly affect native package selection. The
accepted Danko application host is Ubuntu `24.04.5`; the operator identifies
org-lab Tech as Ubuntu `26`. Application contracts remain shared, but native
Python, PostgreSQL, pgvector, and supporting package identities must be
inventoried and qualified separately. Ubuntu Noble packages shall not be
assumed valid for Tech.

### Frozen Implementation Documentation Obligation

Implementation notes shall be maintained while code and schemas are built.
Before portable-package and handoff acceptance, operator and developer
documentation must explain the complete, actual implementation of:

- source catalog, class registry, ingestion manifest, extraction, and
  normalization;
- structural chunk types, boundaries, token measurement, continuations,
  procedures, tables, forms, references, provenance, and reconstruction;
- incremental ingestion preflight, changed-document processing, validation,
  quarantine, unchanged-artifact reuse, atomic publication, rollback,
  revision, retirement, and recovery;
- persistence schemas, migrations, publication-batch identities, active
  document-version mappings, indexes, backup, and restore;
- query resolution and each retrieval lane separately, including inputs,
  indexes, matching behavior, configuration, outputs, failure handling,
  chunk deduplication, RRF, exact-match priority, relationship traversal,
  reconstruction, context budgeting, and citations; and
- configuration tiers and defaults, commands and examples, stable failure
  codes, troubleshooting, security boundaries, and which changes require
  reingestion, re-embedding, or retrieval requalification.

The final documentation may be completed after implementation so it describes
the code that actually exists, but missing or inaccurate documentation blocks
portable-package and handoff acceptance under `G20` and its validation under
`G19`. This cross-cutting obligation does not add another gap item.

## Ordered Discussion and Specification Sequence

Implement and qualify the frozen contracts in this dependency order. Work that
does not depend on pending target evidence may proceed in parallel:

1. **Evidence and class assignment (`G01`-`G02`).** Preserve the frozen source
   verification contract and implement the frozen small class registry,
   ingestion manifest, and assignment-validation contract.
2. **Canonical source model (`G03`-`G04`).** Define raw extraction,
   normalization, and transform provenance.
3. **Chunk contract (`G05`-`G06`).** Define measurement, class boundaries,
   over-size behavior, overlap, and reconstruction links.
4. **Identity and metadata (`G07`-`G08`).** Freeze public schemas before
   selecting persistence or writing ingestion logic.
5. **Embedding contract (`G10`).** Bind the exact deployed model tuple and its
   fail-closed dimension checks.
6. **Ingestion and persistence (`G09`, `G11`).** Define the state machine,
   authorities, atomic publication, rollback, and deletion behavior.
7. **Retrieval and reconstruction (`G12`-`G16`).** Specify candidates, fusion,
   edges, expansion, response evidence, and abstention.
8. **Security and operations (`G17`-`G18`).** Define enforcement, lifecycle,
   content-free telemetry, and stable failures.
9. **Validation (`G19`).** Turn every contract into a measurable synthetic
   test and acceptance threshold; retain `NOT RUN` until executed.
10. **Implementation and handoff (`G20`).** Produce an ordered artifact plan,
    operator entry points, and a retrieval contract that Phase 28 can consume.

Each discussion should end with one updated decision row, alternatives
considered, the selected rule, configuration tier, required tests, and whether
existing stored data must be regenerated.

## Current Decision Roadmap

The current method roadmap contains 23 major decisions. `D01` through `D23`
are frozen, including the accepted configurable native-host runtime amendment
to `D23`. The next work is target-native package inventory, implementation
specification, and evidence-producing execution rather than another top-level
method decision.

The roadmap may be amended if implementation evidence reveals a missing
decision or allows two decisions to merge, but it is the current bounded plan,
not an open-ended numbering exercise.

## Final Frozen Decisions

Decision `D21` freezes classified operational visibility and bounded content
review. Decisions `D22` and `D23` freeze the evidence required for acceptance
and the deployable operator, service, configuration, and package boundary.

### D22: Per-Case Evidence Gates with No Inferred Passes

1. Every validation begins `NOT RUN` and ends `PASS`, `FAIL`, or `BLOCKED` with
   an evidence reference. Missing, truncated, stale, or incompatible evidence
   never becomes an inferred pass.
2. Keep Synthetic Corpus V1 and its held-out structural and retrieval truth
   outside implementation inputs. Implementers may know the public contract
   and fixture types, but code and prompts shall not contain held-out expected
   answers, identifiers, ranks, or excerpts.
3. Pin the source, fixture, schema, method profile, model tuples, software
   versions, configuration digests, publication batches, commands, timestamps, and
   environment identity in a machine-readable validation manifest.
4. Extraction and normalization gates shall account for all six documents and
   27 pages, the intentional blank page, required reading order, hierarchy,
   tables, form fields and states, procedures, raw-to-canonical provenance,
   and every quarantine case. Silent loss, invented content, or an unresolved
   required structure is a failure.
5. Chunk gates shall prove deterministic identities, exact tokenizer counts,
   hard-limit compliance or explicit quarantine, atomic-unit preservation,
   complete source coverage, valid anchors, ordered continuation and hierarchy
   links, and repeat-run equivalence.
6. Ingestion and persistence gates shall prove incremental processing,
   unchanged-artifact reuse, idempotency, crash recovery, retry behavior,
   failed-batch isolation, referential integrity, all-or-nothing publication,
   rollback, backup and restore, explicit retirement, and agreement between
   active document mappings and searchable indexes.
7. Retrieval evaluation shall report each held-out case before aggregates.
   Exact-reference cases must satisfy their exact constraints; semantic,
   relationship, table, and procedure cases must return their required
   evidence within the accepted reconstruction budget; the negative case must
   abstain. Report lane candidates, fused ranks, recall at configured depth,
   reciprocal rank, citation precision and coverage, deduplication, and final
   status without tuning on the held-out answers.
8. Conversation tests shall cover standalone rewrites, source references,
   bounded history, clarification, explicit complete-procedure requests,
   context exhaustion, and refusal to summarize history silently.
9. Security gates shall all pass: loopback-only binding, read-only retrieval
   database access, model isolation, direct and indirect prompt injection,
   poisoned sources, output-schema escape, exfiltration, SQL and command
   injection, path traversal, resource limits, secret handling, and every
   `D21` logging-profile inclusion and exclusion rule.
10. Performance and capacity are measured on the target environment with warm
    and cold conditions, concurrency, corpus size, stage latency, memory,
    storage, and failure recovery recorded. Initial measurements establish a
    baseline; production latency and throughput gates require an explicit
    service objective rather than an invented threshold.
11. Portable-package validation shall prove deterministic manifest and
    checksum verification, architecture rejection, offline image loading,
    preflight, fresh install, configuration validation, database migration,
    supervised on-demand startup, bounded in-activation restart, clean stop,
    boot-disabled posture, health and readiness of the Next.js and retrieval
    API services, smoke interaction, and repeated-install behavior.
    It shall also prove that each corpus-processing command runs only when
    invoked, exits with a stable result, leaves no listener or daemon behind,
    and cannot publish an invalid or partial batch. Upgrade, rollback, removal, and
    restoration are mandatory cases. EmceeDanko is the first `linux/amd64`
    transport and installation test bed; its pass does not substitute for
    org-lab network, dependency, policy, or integration proof.
12. A release passes only when every mandatory per-case correctness, security,
    integrity, and recovery gate passes and all approved performance gates pass.
    Aggregate averages cannot hide a failed mandatory case. Exceptions require
    a recorded owner, scope, risk, expiration, and approval and cannot waive a
    Tier 1 invariant.
13. Validation output contains no private corpus content in tracked artifacts.
    Protected evidence may remain in its approved location with a checksum and
    content-free manifest reference. Regression reruns compare like-for-like
    identities, and changed inputs invalidate only the evidence they affect.

The seven held-out retrieval cases are mandatory acceptance cases for the
first vertical slice, not sufficient production-quality evidence by
themselves. Adversarial, authorization, failure, package, and representative
workload cases are required before a production-readiness claim. Encryption
is an acceptance gate only when enabled, selected by deployment policy, or
required by organizational policy under `D20`.

### D23: Configurable Product and Portable Service Package

The browser-facing product name is a required Tier 3 deployment value in the
versioned YAML configuration, represented as `product.display_name`. The
current mockup may use `Knowledge Assistant`, but that phrase is not a fixed
product identity. The configured name drives approved UI titles, headings,
accessible labels, and client-safe metadata. It shall not alter package names,
routes, database schemas, internal identities, authorization rules, prompts,
retrieval behavior, or corpus artifacts. A display-name change requires
configuration validation and service reload or restart, not rebuilding the
image or reingesting the corpus.

Phase 28 has two persistent application services. The Next.js web/API service
uses the existing Node 24/Next.js 16.4.1 runtime image with bind-mounted host
source. It calls the versioned retrieval API service, which runs as a native
host Python process and owns retrieval orchestration and its PostgreSQL,
embedding, and Gemma integrations. PostgreSQL/pgvector also runs natively on
the host as an infrastructure dependency. No Python or PostgreSQL container is
used, and Phase 28 application source is not baked into the Node image. The
browser shall not connect
directly to the retrieval API, PostgreSQL, the embedding service, retrieval
internals, or Gemma and shall not hold their credentials. The first public
Next.js application surface includes versioned chat, liveness, and readiness
contracts. Retrieval diagnostics remain loopback-only and are not exposed by
the browser-facing API.

Both application services are long-running and supervised once an operator
explicitly starts them: Next.js as the single application container and
retrieval as a native host service. Native PostgreSQL is their persistent
infrastructure dependency. All three are installed boot-disabled in the first
vertical slice, have explicit health/readiness and graceful shutdown behavior,
and remain stopped after installation or host reboot until the operator runs
the package start command. Their container or process identities, ports,
dependencies, boot state, and restart state are declared and verified by the
portable package. A healthy Next.js process is not ready when its required
retrieval API is unavailable; retrieval readiness applies the dependency rules
frozen in `D21`.

Inside the retrieval API, document retrieval and direct Gemma access remain
separate logical adapters with independent configured endpoints, timeouts,
identities, health state, and failure codes. Their upstream implementations
may remain sibling services or expose endpoints through one existing backend;
that upstream topology is Tier 3 deployment configuration. It shall not change
the Next.js-to-retrieval contract, `D18` response envelope, authorization
policy, or validation obligations.

The first vertical slice integrates directly with the OpenAI-compatible vLLM
interfaces deployed in org-lab: Nomic through `/v1/embeddings` and Gemma
through `/v1/chat/completions`, using separately configured base URLs, served
model names, credentials, timeouts, and health checks. Dalton and other
environment-specific convenience wrappers are not runtime, packaging, or
acceptance dependencies. Danko Lab qualification shall use these same direct
vLLM interfaces even if an optional local wrapper is available there.

Phase 28 inherits the org-lab Naming Boundary in
`phase-21-org-lab/docs/README.md`. Repository control records may retain phase
and gap identifiers, but no org-lab transfer bundle, target path, executable,
service artifact, configuration file, report, or operator-facing runtime
surface may expose phase numbers, script numbers, agent labels, lab names, or
repository jargon.

Extraction, normalization, chunking, embedding submission, ingestion, and
corpus lifecycle operations are executable, operator-invoked commands, not
continuously running services in the first vertical slice. They start only on
explicit invocation, operate on the manifest-listed incremental batch or requested action,
produce evidence and a stable exit status, and terminate without leaving a
listener, watcher, scheduler, worker, or retry daemon. They may share reviewed
Python libraries with the retrieval API without sharing its long-running
lifecycle.

This offline local-operator command surface shall cover at least configuration
validation, source inventory, extraction, chunking, incremental ingestion,
batch validation, atomic publication, rollback, status, quarantine inspection,
retirement, backup, and restore verification. Commands shall be
idempotent where applicable, provide preflight or dry-run for consequential
actions, use stable `D21` failures, and never silently ingest, migrate, or
publish during ordinary service startup.

Versioned YAML contains only schema-validated Tier 2 method settings and Tier
3 deployment settings. `product.display_name` and service endpoint locations
are Tier 3. Secrets, credentials, tokens, and private keys are supplied through
the protected deployment secret mechanism, not YAML. Unknown fields,
duplicate keys, unresolved references, unsafe values, and incompatible schema
versions fail validation. The effective redacted configuration and its digest
are available to preflight and evidence commands.

Phase 28 shall produce an installable, portable, offline-capable application
package rather than only a source handoff. Each package targets and declares
one operating-system and architecture tuple; the first target is
`linux/amd64`. A package shall not be labeled multi-architecture unless every
included image and binary has been built and validated for every declared
architecture.

The portable package contains, as applicable:

- the exact existing Node 24/Next.js 16.4.1 image, without Phase 28 service
  source baked into it;
- host-resident Next.js, retrieval API, and corpus-command source, with only
  the Next.js source bind-mounted into the Node container;
- the Node image identity, platform metadata, and load instructions;
- target-native Python, PostgreSQL, pgvector, and supporting package payloads
  or exact acquisition manifests;
- installer, preflight, configuration validator, final-schema installation,
  corpus-processing, service-control, smoke-test, rollback, and removal
  commands;
- versioned schemas, example configuration without secrets, and service-unit
  definitions for native retrieval and PostgreSQL plus the container
  definition for Next.js;
- pinned application dependencies, licenses, advisory disposition, and
  software-bill-of-materials or equivalent dependency inventory;
- one consolidated fresh-install database schema and compatibility
  requirements;
- tests, content-free validation manifests, operator and recovery procedures;
  and
- SHA-256 manifests covering every transported artifact and the package
  itself.

For a fresh target installation, the package contains one reviewed,
consolidated schema baseline that creates the current tables, views,
constraints, indexes, grants, and schema-version record directly. A fresh
org-lab installation does not replay EmceeDanko's historical development
sequence of migration `0001` followed by corrective migration `0002`.
Consolidation does not eliminate schema control: the installed baseline has a
stable identity, installation verifies it exactly, and any later change to an
already-installed database requires a new forward migration with its own
rollback and validation contract.

That final-state rule applies to every deployment artifact and object, not
only the database. If development reaches an accepted file, binary, image,
configuration, service definition, or policy object by patching or repairing
an ancestor, the fresh-deployment package carries the validated final result
and its identity. It does not carry the ancestor plus the mutation chain as
the installation recipe. Ancestry and transformation recipes remain source or
audit evidence outside the fresh-install payload; separately selected upgrade
packages may contain bounded deltas for already-installed supported releases.

The Node image, native package payloads, application source, site
configuration, secrets, corpus source documents, PostgreSQL state, backups,
and validation evidence remain separable artifact classes. Native PostgreSQL
uses its distro-managed host data directory; that directory is
PostgreSQL-owned internal state, not a location for source documents or
operator-edited table files. The portable application package shall not
silently include a corpus, credentials, environment-specific addresses,
database state, or private evidence. External Gemma and embedding services are
declared prerequisites and endpoints unless an explicitly different package
profile includes them.

Installation begins with read-only preflight of architecture, operating
system, Docker and Compose capability, storage, ports, existing state,
configuration, checksums, image platforms, and external dependency
reachability where available. Mutation requires an explicit install action.
The installer records what it changed, preserves a rollback boundary, refuses
unknown conflicting state, and verifies the installed identities before
startup. Installation does not imply service start or boot enablement. A
separate explicit operator command starts or stops the two application
services. Removal is scoped and preserves or deletes data only according to
an explicit operator choice and `D20` retention policy.

Current repository evidence records EmceeDanko as `amd64` and the org-lab
App/API host as `amd64`; the org-lab Dell model host is `arm64/aarch64`.
Therefore EmceeDanko is the first portability test bed for the `linux/amd64`
application package and its single Node image, while the model services remain external
configured dependencies. EmceeDanko can prove transport, checksum, preflight,
installation, setup, the persistent-service lifecycle, one-shot corpus-command
behavior, upgrade, rollback, and removal. It cannot prove org-lab-specific
networking, credentials, policy, model-service compatibility, capacity, or
production readiness; those require a second target-side validation on the
org-lab App/API host.

The final deliverable includes the portable fresh-deployment package plus its
source, build recipe, consolidated schema, API contract, commands, tests,
checksums, dependency inventory, validation manifest, install and recovery
procedures, and explicit `NOT RUN` results for any target proof not yet
executed. Historical development migrations remain repository evidence only;
future forward migrations, if needed for an already-installed supported
release, ship through a separate upgrade package and never through the base
fresh-install path. D23
freezes the two persistent application services, one-shot corpus command
boundary, sole Node-container/native-host runtime split, and configurable
host-network/loopback transport while leaving the existing upstream
retrieval/Gemma implementation topology configurable.

## Explicit Non-Claims

- No corpus source has been visually verified by this document.
- No extractor, normalizer, chunker, embedding path, database, index,
  retrieval method, or API is implemented or selected here.
- The proposed chunk sizes and hybrid-retrieval design have not been measured.
- No security, privacy, operational, or production acceptance is claimed.
- No generated implementation from the reviewed session is adopted.
- The configured product UI must consume a stable Phase 28 retrieval response
  contract; it does not need to wait for optional document-open or download
  capabilities.

## Ishikawa v1 fallback and v1.1 tuning boundary

The exact host-qualified deployment archive accepted by Script `109`, together
with the unchanged live retrieval behavior captured by Script `112`, is the
Ishikawa v1 fallback boundary. Script `113` verifies and checksum-binds those
existing artifacts without rebuilding or duplicating the package. Once that
checkpoint passes, v1 is immutable for retrieval tuning and remains the
operator-selectable fallback.

The first tuning work belongs exclusively to Ishikawa v1.1. Its frozen scope
is deliberately bounded:

- resolve recognized document identifiers and explicit page references
  deterministically before Gemma scope classification;
- return a document-scoped clarification for a vague request that identifies
  a document but asks no specific question;
- do not expand such vague requests across related documents;
- retain the existing exact, PostgreSQL lexical, and cosine-vector lanes,
  their RRF settings, and the current timeout until remeasurement; and
- diagnose the two baseline dependency failures using content-free classified
  logs before selecting any further correction.

No v1.1 tuning source or package may overwrite the accepted v1 archive or its
release and fallback receipts. A future v1.1 deployment package is assembled,
qualified, and accepted under a distinct identity only after the tuning
qualification passes.

The subsequent local ranking workflow and its acceptance thresholds are
governed by `ISHIKAWA_V1_1_TUNING_DECISIONS.md`. That separate list freezes
decisions `T01` through `T12`, keeps Gemma outside the authoritative ranking
gate, and defers deployment-package assembly until local ranking and complete
Retrieval API acceptance pass.

The local six-document tuning corpus is accepted through Script `117`. Script
`118` then retained the content-free top-20 lane rankings and measured the
frozen profile at `MRR@20 = 0.690476`, responsive top-five coverage `5/6`, and
required-evidence recall `13/13`. The measurement passed while the ranking
gate did not. Script `119` then replayed only those accepted lane rankings
across a finite parameter grid, retained qualifying candidates, and made no
method-profile, database, model, service, or package change. Its recommendation
required explicit review and freeze.

Script `119` passed its offline search over 43,120 candidates. Of those, 978
met the ranking gate. The deterministic KISS rule selected candidate
`a767efb74a690f4ded16b1aed5f4d2c0b880a40dfc4b22e653be366e616f4eda`
as both the highest-quality and smallest-change recommendation. The operator
froze it as tuning decision `T09`: exact depth `1`; lexical, vector, and fused
depths `20`; RRF constant `60`; exact/lexical/vector weights `1/1/4`; and no
learned reranker. The resulting retrieval-profile identity is
`ba4bac60b3f09f6be89db148d1df883748a2003f35a1cecfb6c74f53be74b865`.
This does not alter chunking, stored embeddings, or the database schema.
Script `120` passed the implementation and complete native regression gate:
the T09 profile identity reproduced exactly and all 371 native tests passed
with zero failures or errors. Script `121` performs a fresh live ranking run
over all 13 cases against local read-only PostgreSQL and forwarded Nomic. It
measures `MRR@20`, responsive top-five coverage, and all 13 required-evidence
expectations. Nonresponsive abstention and complete Retrieval API behavior
remain a separate subsequent gate because ranking alone cannot prove them.

Script `121` passed that fresh live ranking gate at `MRR@20 = 0.916667`,
responsive top-five coverage `6/6`, and required-evidence recall `13/13`.
Script `122` is the separate complete API gate. It stages the checksum-bound
working source in private temporary storage, starts one loopback Retrieval API,
runs all 13 cases through the real PostgreSQL, Nomic, and Gemma orchestration,
then stops and removes the temporary service. Acceptance requires six answered
responsive cases, six `insufficient-evidence` abstentions, one deterministic
clarification, all 13 exact expected statuses, and zero dependency failures.
It does not write the database or build a deployment package.

## Ishikawa v1.2 native-prerequisite readiness

Script `140` accepts the exact host-qualified Ishikawa v1.2 deployment archive
without rebuilding it. Native operating-system prerequisites remain outside
that portable application-and-schema archive and must be qualified separately
on the Ubuntu `26.04` AMD64 application host.

The v1.2 package preserves the exact v1 ingestion-dependency and runtime-
dependency YAML contracts. Script `141` proves that equivalence and binds the
accepted v1.2 identity to the already-built neutral three-file prerequisite
inventory kit. The kit is reused byte-for-byte; it is not rebuilt or renamed
for v1.2 and contains no repository, environment, phase, or script language.

This binding is local review evidence only. It does not claim that the org-lab
host is ready. The next required evidence is an operator-run, read-only target
inventory covering Ubuntu and architecture identity, native Python/YAML/
Psycopg, Poppler, PostgreSQL/pgvector/libpq, Docker, the accepted Node image,
package health and candidates, planned listeners, service state, and storage.
Package advisories and provenance must be reviewed after that inventory and
before any target-specific package payload is downloaded.

Because no accepted SSH route from the development workstation to the org-lab
application host is part of this deployment contract, the inventory uses a
hand-carried neutral bundle. Script `142` prepares that bundle locally without
target contact. Its target command verifies the carried bytes, uses a private
temporary work directory, runs the read-only inspector, emits one checksum-
bound result archive and sidecar under `/tmp`, and removes its working files.
Repository numbering remains outside the target bundle.

The subsequent 60-case gate measured `MRR@20 = 0.852173`, and an exhaustive
bounded replay found no depth, weight, or RRF-only candidate above the strict
`0.91` target. T12 therefore makes one evidence-backed routing correction: a
single structured identifier plus an unambiguous page may resolve against the
active document's own citation declaration (`Policy Number:`, `Form no.`, or a
bare form identifier). One owner routes directly to that cited page; no owner
preserves ordinary retrieval; multiple owners require clarification. The T09
lane settings remain unchanged. This correction requires no schema change,
re-embedding, model request, or new operator configuration. Script `131`
qualifies native regression and the active read-only corpus before a fresh
60-case measurement is allowed.
