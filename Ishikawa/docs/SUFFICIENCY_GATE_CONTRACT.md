# Evidence Sufficiency Gate Contract

## Purpose

The post-retrieval sufficiency gate decides whether accepted evidence is
eligible to reach grounded answer generation. It is deterministic application
code. Gemma cannot declare its own evidence sufficient and model confidence is
never an input.

## Hard checks

The gate fails closed when:

- a required retrieval lane fails;
- retrieval returns no fused candidates;
- authorization removes every candidate;
- an explicit identifier or page constraint is unresolved;
- required relationship coverage is incomplete;
- active source versions conflict;
- reconstruction produces no evidence;
- selected passages and source-group citations disagree;
- requested complete structure is incomplete;
- reconstruction exceeds a context boundary; or
- relevance has not been qualified by a calibrated relevance profile.

Lane failure returns `temporarily-unavailable`. Missing, unauthorized,
conflicting, incomplete, or irrelevant evidence returns
`insufficient-evidence`. Incomplete complete-structure requests and context
budget failures return `context-limit`. Only a complete pass returns the
internal `sufficient` result that permits grounded generation; it is not yet an
`answered` client response.

## Relevance boundary

Candidate presence is not proof of relevance because vector retrieval can
always return a nearest neighbor. The gate therefore requires the separate
versioned relevance decision produced by the frozen citable-evidence profile.
That profile measures PostgreSQL `english` lexeme support over the first three
fused results and requires at least three-fifths support using exact integer
arithmetic. Missing and `insufficient` decisions both fail closed. The
profile identity is retained for both positive and negative decisions.

The sufficiency gate cannot accept a caller-invented relevance status. It
accepts only the typed decision produced by the relevance module. Gemma,
candidate presence, and raw vector or RRF scores cannot declare relevance.

Script `54` is source-ready to qualify the 13 deterministic outcomes locally.
It does not query PostgreSQL, call a model, contact a remote system, or retain
evidence text.

Script `61` binds the later protected calibration evidence and qualifies the
frozen runtime relevance producer and its integration with this gate. It is
also local-only.
