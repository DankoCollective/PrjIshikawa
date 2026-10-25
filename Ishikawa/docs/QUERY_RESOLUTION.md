# Standalone query resolution

Ishikawa preserves the user's original turn but sends retrieval a separate,
standalone query. The complete chat transcript is never sent to Nomic as the
embedding input.

## Runtime behavior

1. Direct-injection scanning remains the first gate. Fixed code then resolves
   an explicit structured identifier, full active-document display name, or
   catalog document key before Gemma scope classification. Exactly one match
   constrains retrieval to that active document version; multiple matches ask
   for clarification; no match preserves the ordinary corpus-wide path.
2. A uniquely recognized explicit document reference may bypass Gemma scope
   and query-resolution calls. A standalone first-turn question with no
   contextual source references is otherwise already its own retrieval query.
3. Ordinary situational questions remain corpus-wide; fixed code does not
   select a document merely because its content might be relevant.
4. A contextual turn is sent once to the approved direct Gemma endpoint with
   bounded conversation history, explicit filters, and trusted source display
   names resolved from structured source identities.
5. Gemma may only return a standalone query, selected allowlisted source
   labels, or a clarification request. It cannot answer, select new filters,
   invent a source, or make evidence authoritative.
6. Code maps an accepted source label back to its exact source and optional
   citation identities. The literal `Source N` label is prohibited from the
   resolved retrieval query.
7. The operator's explicit filters are copied by code and cannot be changed by
   the model.
8. A label named in the question must exist in the structured source map and
   must be returned exactly. An unresolved label receives a deterministic
   clarification without a model call or retrieval.
9. A material ambiguity receives `clarification-required`; no retrieval is
   attempted.
10. Only the resolved standalone query is eligible for lexical parsing and
   singleton Nomic query embedding. The original query, resolution identity,
   filters, and exact source constraints remain request-scoped provenance.
11. The original typed request also reaches reconstruction solely so its
    conversation can be counted against the frozen context budget. It is not
    an embedding input.

The resolver uses the publisher sampling settings already selected for Gemma:
temperature `1.0`, `top_p` `0.95`, and `top_k` `64`, with thinking disabled.
Its HTTP boundary is synchronous, nonstreaming, one request, and no automatic
retry. Credentials remain protected runtime inputs.

Script 65 qualifies this contract locally. It does not contact Gemma, Nomic,
PostgreSQL, or another network endpoint, and it does not claim the concrete
PostgreSQL retrieval adapter or the listener is complete.
