# Ishikawa Chunking, Ingestion, and Retrieval Methods

## Method boundary

Ishikawa uses one general, versioned document-processing method for supported
PDFs. The operator assigns a registered class in the ingestion manifest. The
class becomes searchable metadata; it does not select an unrelated chunking
implementation.

If a document exposes an unsupported structural pattern, the safe result is
quarantine. The method is extended only after evidence shows what structure
must be represented.

## Extraction and normalization

The current implementation uses native Poppler tools to inventory pages and
extract text plus geometry. Accepted raw extraction remains immutable.

The deterministic normalizer then:

- orders physical lines and words from page geometry;
- applies Unicode NFC and stable whitespace rules;
- joins wrapped lines only when geometry and punctuation support it;
- preserves punctuation, identifiers, numbering, list markers, and checkbox
  state;
- separates recurring page furniture from semantic content; and
- anchors every normalized unit to pages, source spans, geometry, rules, and
  digests.

The supported structural units are headings, paragraphs, definitions, list
items, structured tables, form fields, checkbox groups, and page furniture.
Verified blank pages remain explicit observations and receive no invented
document content.

Image-only, encrypted, malformed, unsafe, or structurally unsupported inputs
fail closed under stable quarantine reasons. OCR is outside v1.

## Chunk construction

Chunks begin at the smallest useful semantic unit:

- one chunk for each paragraph, definition, or list item;
- one chunk for each form field or checkbox group;
- one table-context chunk; and
- one atomic chunk for each table row.

Table-row chunks preserve ordered header/value pairs, the table context, and
row-specific citation anchors. This supports questions about one row without
flattening the table into ambiguous prose.

Headings become explicit context and structural paths. They are not copied as
blind body overlap. Confirmed page furniture is excluded from retrieval
chunks. Body overlap and adjacent table-row expansion are zero in v1.

A verified blank page may create a deterministic `page_status` chunk stating
only that no extractable text was observed on that page. It does not claim
that the page has no visual content.

Every chunk retains canonical identities, content and context text, page
range, structural path, source units, citation anchors, labels, references,
document-local previous and next links, and exact token counts.

## Token measurement and embeddings

Nomic's exact tokenizer measures four stored buckets:

- content tokens;
- context tokens;
- prefix tokens; and
- tokenizer-added special tokens.

Their sum must equal the authoritative total embedding token count. Ishikawa
does not estimate this total from words or characters.

Nomic embeds the exact accepted retrieval input into 768 finite values. The
stored vector is tied to its embedding-space identity and submitted-input
digest. Changing embedded input requires affected chunks to be measured and
embedded again.

## Incremental ingestion

The operator maintains three inputs:

1. a class registry containing valid class identifiers;
2. a document catalog containing stable logical document keys; and
3. a batch manifest containing only affected documents and retirements.

Before production, ingestion checks the YAML contracts, cross-file
references, document keys, class assignments, path containment, file type,
source safety, retirement agreement, and current published state.

Each entry is planned as one of:

- `add`: no published version exists;
- `revise`: source bytes changed;
- `reprocess`: source bytes match but semantic processing inputs changed;
- `reuse`: accepted source and semantic inputs match; or
- `retire`: matching catalog and manifest declarations remove the active
  version from normal retrieval.

Only add, revise, and reprocess entries run the extraction-to-embedding
pipeline. Reuse avoids duplicate work. Retirement does not extract or embed.

All changes in one manifest publish in one PostgreSQL transaction. A failure
or quarantine blocks publication of the entire manifest but does not undo or
reprocess unrelated active documents. Operators can use one-document
manifests when they need independent publication boundaries.

## Retrieval preparation

The accepted chat request is bounded and schema-validated. Direct and
indirect prompt-injection checks reject instruction override, role
impersonation, prompt extraction, data exfiltration, system-access, and
obfuscation patterns. Scope classification runs for every accepted natural-
language turn except for the deliberately narrow deterministic routes below.

Before Gemma scope classification, application code checks only two forms
against the active read-only corpus:

- one recognized self-declared document identifier with an explicit page; and
- the explicit vague form `What about [document]?`.

A uniquely recognized identifier is already known to reference the active
corpus and proceeds without a Gemma scope call. For direct page routing, the
identifier must match one active document's citation excerpts using a bare
form identifier, `Form no.`, or `Policy Number:` self-declaration. No owner
preserves ordinary retrieval; multiple owners require clarification and never
guess. A uniquely recognized vague document request returns a clarification
asking what the operator wants to know. Vague-name recognition uses the exact
catalog display name or unique PostgreSQL English-lexeme support in one active
document; it does not guess from a model. It performs no generation or
relationship expansion. Unknown and ordinary questions continue through the
existing Gemma scope path unchanged.

A first-turn standalone question proceeds directly. A contextual follow-up
may be resolved into one standalone retrieval query. Code, not the model,
preserves explicit document filters and structured references to earlier
sources.

## Three retrieval lanes

One retrieval runs the applicable lanes and combines their ranked candidates:

1. **Exact lane.** An unambiguous document identifier plus page routes to
   page-anchored evidence.
2. **Lexical lane.** PostgreSQL's native `english` text-search configuration
   parses, removes stop words, and stems query terms. Strict matching runs
   first; native OR fallback runs only when strict search is empty.
3. **Vector lane.** Nomic embeds the standalone question once and pgvector
   ranks active chunks by cosine distance.

The exact lane retains only its best candidate; the lexical and vector lanes
each retain at most 20. Reciprocal-rank fusion uses exact/lexical/vector
weights `1/2/4` and constant 60. For ordinary non-exact retrieval, lexical and
vector search use retrieval-only section/page representatives plus the first
document-local atomic occurrence of duplicate content. Fusion retains at most
20 structural groups. Selected representatives then expand to their ordered
authoritative atomic members before hydration, relevance, citation, or Gemma
input. Exact-match priority remains separate from the weighted score.

One-hop relationship expansion may retrieve a directly referenced active
document only from a verified relationship attached to direct evidence. It
does not recurse and does not let a model invent relationships.

## Relevance and sufficiency

Retrieval rank alone does not authorize an answer. Ishikawa checks active
document state, filters, exact constraints, relationship coverage, citation
validity, structure completeness, and calibrated relevance.

For relevance, PostgreSQL derives question lexemes and measures support across
the top three fused evidence envelopes. The envelope contains chunk text,
document display name, assigned class, structural path, and citation page. At
least 60 percent of question lexemes must be supported. The comparison uses
integer arithmetic, ranking is unchanged, and Gemma has no authority over the
decision.

## Reconstruction and answers

Reconstruction removes exact duplicate chunk identities and text projections
without collapsing distinct excerpts from the same document. It groups
passages by document version, assigns stable `Source N` labels, retains all
nonconflicting citations, and normally selects no more than three passages
per document.

An explicit complete-procedure request follows stored structural and sequence
metadata to assemble the entire resolvable procedure. It is returned in full
or not at all when the context budget cannot hold it.

The exact Gemma tokenizer enforces the 32,768-token application budget. Gemma
receives only validated conversation, question, evidence, and citation
allowlist data. vLLM is asked to enforce an exact JSON Schema containing only
an ordered `segments` array. Every segment contains nonempty answer prose and
one or more citations restricted to the accepted evidence identifiers. That
structured output remains untrusted until application code validates the
complete sequence and every citation. Grounded generation retries exactly once only after a transport
or invalid-response failure and otherwise fails closed.

## Change consequences

- A class-label addition normally changes only configuration.
- A new structural pattern changes the chunk-method identity and requires
  affected artifacts and retrieval qualification to be regenerated.
- A retrieval depth, lexical, vector, fusion, weight, candidate-representation,
  duplicate-canonicalization, expansion, or reranker change
  creates a new retrieval-profile identity.
- A change to embedded input requires affected chunks to be re-embedded.
- A deployment URL, port, timeout, display name, or retention change does not
  by itself change document or retrieval semantics.
