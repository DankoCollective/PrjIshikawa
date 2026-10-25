# Ishikawa Application Design

## Design goals

The v1 design favors a small number of understandable components, native host
capabilities where practical, explicit configuration, deterministic safety
decisions, and evidence that an operator can inspect.

Application source remains on the host. The only application container is the
unchanged Node 24/Next.js runtime image with read-only bind mounts. Python and
PostgreSQL run natively. Chunking and ingestion are one-shot commands rather
than always-running services.

## Configuration model

Configuration has three roles:

1. Enforced invariants define safety and identity rules the operator cannot
   weaken through ordinary deployment configuration.
2. Versioned method profiles define semantic behavior such as chunking,
   retrieval, reconstruction, scope, injection, and sufficiency. A material
   method change creates a new identity and requires appropriate
   requalification.
3. Deployment settings define environment-specific values such as loopback
   ports, endpoint URLs, timeouts, concurrency, product display name, and log
   retention.

Restricted YAML loaders reject duplicate fields, unknown fields, unsafe
types, aliases, and malformed values. Secrets are named in configuration but
their values come only from protected runtime environment variables.

## Document ownership model

`document_classes.yaml` is a simple allowlist. It defines class identifiers,
display names, and active or retired status. It does not define classifiers,
prompts, regular expressions, or class-specific chunking.

`document_catalog.yaml` defines stable logical document keys across revisions.
The key does not encode a version. Source-byte digests identify revisions.

An ingestion manifest assigns one registered class to each affected document
and lists only additions, revisions, reprocessing requests, or explicit
retirements. The manifest is the atomic publication boundary.

## Processing design

All supported PDFs use one general structural processor. The processor
extracts geometry and text, normalizes semantic units, and creates citable
chunk projections. A class label is metadata inherited by the resulting
records; it does not choose an entirely different chunker.

The processor changes only when quarantine evidence demonstrates a new
structural behavior, metadata requirement, or reference form that the current
method cannot represent safely.

Tables remain structured. Each table produces a context projection and atomic
row projections with ordered header/value pairs, source spans, and citation
anchors. This makes a matching row retrievable without discarding the table's
meaning.

## Publication design

Ingestion validates configuration and source boundaries before producing
artifacts. Only affected documents are extracted, chunked, measured, and
embedded. Identical accepted artifacts are reused by SHA-256 identity.

One PostgreSQL transaction publishes a valid manifest. Failure or quarantine
publishes none of that manifest's changes. Existing active documents remain
searchable. Historical identities and quarantine history remain immutable;
remediation creates a linked later run.

## Retrieval design

Every eligible question uses three retrieval lanes:

- exact routing for an unambiguous document identifier plus page;
- PostgreSQL English full-text search, strict first and native OR fallback
  only when strict search is empty; and
- Nomic query embedding with pgvector cosine search.

The exact-reference lane retains only its best candidate. The lexical and
vector lanes each retain at most 20 candidates. Reciprocal-rank fusion uses
exact/lexical/vector weights `1/2/4` with constant 60 and retains at most 20
structural groups. Ordinary non-exact retrieval may rank scoring-only
section/page representatives while suppressing later document-local duplicate
atomic content. A selected representative expands to its ordered atomic
members before it can become evidence. Exact-match priority remains a separate
deterministic boundary. There is no learned reranker.

The top three fused results form the deterministic relevance envelope. At
least three fifths of the question's PostgreSQL English lexemes must be
supported by citable fields. This check does not change ranking and Gemma has
no authority over it.

## Conversation and generation design

The request boundary accepts at most 12 prior turns and preserves structured
references to previously returned sources. A contextual question may be
resolved into one standalone retrieval query, but code preserves explicit
filters and source identities.

Ishikawa adds narrow code-owned pre-scope routes. A structured identifier
verified against the active corpus proceeds without asking Gemma to decide
whether the known corpus reference is in scope. When one question contains
exactly one recognized self-declared document identifier and one unambiguous
page number, application code resolves the identifier against active citation
excerpts and retrieves that document's cited page directly. Supported
self-declarations are a bare form identifier, `Form no.`, and
`Policy Number:`. No owner preserves ordinary retrieval; multiple owners
require clarification and never guess.

The explicit vague form `What about [document]?` returns a document-scoped
clarification when an exact catalog name or unique PostgreSQL English-lexeme
match identifies one active document. It does not expand relationships.
Ordinary, ambiguous, and unknown questions retain a bounded clarification or
the existing Gemma scope-classification path as appropriate.

The application enforces a 32,768-token context budget:

- 2,048 instruction tokens;
- 12,288 conversation tokens;
- 16,384 evidence tokens; and
- 2,048 reserved answer tokens.

The exact Gemma tokenizer counts the composed request. The application never
substitutes a word-count estimate. Grounded generation uses temperature
`1.0`, top-p `0.95`, and top-k `64`, with thinking and streaming disabled.

Grounded generation asks vLLM to enforce an exact JSON Schema containing only
an ordered `segments` array. Every segment requires nonempty prose and one or
more citation identifiers drawn from the accepted evidence allowlist.
Application code remains the authoritative trust boundary: it validates the
complete sequence and citation allowlist, then displays that same sequence as
flowing prose. There is no redundant model answer field. A transport or
invalid-response failure may retry grounded generation exactly once; a second
failure remains temporarily unavailable.

## Safety design

Direct and indirect prompt-injection checks operate on the user request,
conversation, and retrieved content. Scope classification runs before
retrieval. Deterministic sufficiency and citation checks run before and after
generation. Unsafe or incomplete requests fail closed with a bounded status.

Gemma and Nomic have no direct database or document-store access. Retrieval
uses a read-only PostgreSQL role and security-barrier views. Ingestion uses a
separate write-capable role. All default listeners are loopback-only.

## Lifecycle design

The explicit stack command starts PostgreSQL, then the Retrieval API, then the
web container, waiting for readiness at each boundary. Stop proceeds in
reverse. Startup is on demand, not at boot. External model forwarding must
exist before start and remains outside the application lifecycle.

## Packaging design

A deployable package contains only final target files: application source,
configuration templates, final database schema, operator commands, service
definitions, documentation, installers, verification, and checksums. It does
not ship historical migrations, repair helpers, development evidence, source
documents, secrets, live database state, logs, model responses, or cached
embeddings.
