# Native PostgreSQL Retrieval Adapter

## Boundary

The retrieval port receives two separate typed values:

- the original validated chat request, used only for deterministic context
  accounting; and
- the accepted standalone retrieval query, used for exact parsing, PostgreSQL
  full-text search, and the one singleton Nomic query embedding.

Conversation history and the original contextual wording are never sent to
Nomic. The operator's document-class and document-key filters remain
code-owned. A structured source reference is the active document-version
identity returned as `source_id`; an optional citation identity narrows the
exact lane further.

## Read-only database behavior

Each request opens one `REPEATABLE READ, READ ONLY` transaction. The stable
snapshot prevents an active publication from changing the candidate views
between lane execution and hydration. Before retrieval, the adapter verifies
that PostgreSQL reports all three boundary facts:

- `current_user = rag_retrieval`; and
- `transaction_read_only = on`; and
- `transaction_isolation = repeatable read`.

Every content query reads only the security-barrier views in `rag_search`.
The adapter neither reads nor writes the `rag` or `rag_private` base schemas.
The transaction is rolled back and the connection closed on every exit path.

## Candidate path

The adapter executes the frozen lanes for the same standalone query:

1. exact citation/document-version and conservative structured-identifier
   routing when applicable;
2. PostgreSQL `english` lexical search, with the frozen native OR fallback;
3. pgvector cosine search using the validated Nomic embedding space; and
4. reciprocal-rank fusion with exact/lexical/vector weights `1/2/4`, constant
   `60`, and a cap of `20` structural retrieval groups.

For ordinary non-exact retrieval, lexical and vector search use the frozen
candidate representation. It contains scoring-only section/page
representatives plus document-local canonical atomic chunks. After fusion,
Ishikawa retains only the highest-ranked candidate in each structural group.
It then expands every retained representative to its ordered authoritative
atomic members. Representatives never enter hydration, relevance measurement,
citation construction, sufficiency evaluation, or Gemma context. Exact routes
continue to use atomic candidates directly.

Class, document-key, and source-version restrictions are applied inside every
candidate query. They are checked again after hydration before raw chunk text
can enter reconstruction. Hydration reads the active chunk and its citations,
validates all fused identities, and rejects missing or conflicting records.

The fused evidence then passes through the accepted top-three citable-evidence
relevance rule, 32K reconstruction budget, diversity selection, citation
validation, and deterministic sufficiency gate. Only a sufficient package is
converted to client-safe source groups. Each response `source_id` is its active
document-version identity, allowing a later `Source N` turn to route back to
that exact cited version.

For client display, the adapter separately expands every selected top-level
structural path from the same active document version. The display projection
reads each citation's source `relevant_excerpt` in chunk ordinal order; it does
not expose the section and identity prefixes added to `retrieval_text` for
search and model context. After Gemma returns a validated response, Ishikawa
keeps only roots anchored by citations actually used in the response;
unrelated sections remain available through the reconstructed-document viewer.
This does not enlarge
Gemma's accepted evidence or its context budget. Expanded display text still
passes the retrieved-content injection gate. Expansion is additive: every
accepted generation citation remains in the display set, including selected
table-context and page-status projections that are not independently expanded.
The adapter never silently clips a section: when an expansion cannot fit the
exact twenty-excerpt API boundary, it returns only the already accepted
generation evidence.

An explicit `complete`, `full`, `entire`, or `whole Section N` request with one
resolved source uses Arabic/Roman ordinal matching against that version's
structural paths. Exactly one matching section is reconstructed as an ordered,
all-or-context-limit unit and supplied to Gemma. Missing or ambiguous paths
fail closed instead of selecting a section heuristically.

## Script 66 boundary

Script `66` validates the concrete SQL construction and retrieval-port
composition with an injected deterministic PostgreSQL connection, query
embedder, and token counter. It proves no network, database, model, credential,
or listener contact during local qualification.

Script `67` extends the adapter with the already-frozen one-hop relationship
and complete-procedure paths. Relationship expansion is limited to edges
anchored by directly retrieved chunks, and related evidence retains distinct
relationship provenance. Explicit complete-procedure requests load one exact
active document-version inventory and pass it to all-or-nothing reconstruction.
The direct lanes, ranking, read-only transaction, and `rag_search` boundary are
unchanged. See `RELATIONSHIP_AND_PROCEDURE_RETRIEVAL.md` for the complete path.
