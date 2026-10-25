# Relationship and Complete-Procedure Retrieval

## One-hop relationship path

Relationship expansion begins only after the direct exact, lexical, and vector
lanes have been fused. The adapter considers only accepted
`explicit_reference.document` edges whose evidence citation belongs to one of
those directly retrieved chunks. This prevents an unrelated reference
elsewhere in the same document from expanding the request.

The database resolves every logical target to its active document version in
the same repeatable-read snapshot. Document-class and document-key filters are
applied to the target before it is returned and are checked again during chunk
hydration. The qualified relationship registry permits one outgoing hop and a
maximum of 20 distinct targets.

For each accepted target, the existing resolved query and existing singleton
query embedding run through lexical and vector retrieval scoped to that exact
active target version. The frozen lexical/vector RRF weights `1/4` select at
most three target passages.
Those passages are marked `origin=relationship`; they retain the seed document,
edge, target document, resolved target version, and relationship-evidence
citation identities. They never claim a direct similarity origin.

If a traversed target cannot provide citable evidence, deterministic
relationship coverage fails and the request does not proceed to generation.
There is no recursive traversal and no model-selected relationship.

## Complete-procedure path

The complete-procedure path is used only when the accepted standalone query
contains explicit wording such as `complete procedure`, `entire procedure`,
`whole procedure`, `full procedure`, `procedure in its entirety`, or
`procedure from start to finish`. Ordinary procedure questions remain normal
passage retrieval.

The target must resolve to exactly one active document-version identity,
normally through a structured conversation source reference. The adapter then
loads every citable chunk for that exact version from `rag_search`, checks the
same class and document filters, removes nonsemantic page-status and table-
context projections, and orders the remaining units by canonical source
ordinal.

The complete procedure is one atomic evidence unit for budgeting. It is
returned in full or the deterministic sufficiency gate returns a context-limit
outcome. It is never silently clipped, summarized, or presented as complete
when its inventory is unavailable or ambiguous.

## Runtime and security boundary

Both paths execute inside the adapter's existing `REPEATABLE READ, READ ONLY`
transaction as database role `rag_retrieval`. Every query reads only
security-barrier views in `rag_search`. Neither path writes PostgreSQL, reads a
base schema, adds a model call, creates a network listener, or changes the
three direct retrieval lanes and their frozen ranking.

