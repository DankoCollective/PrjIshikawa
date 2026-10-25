# Ishikawa Post-v1.3 Optimization Backlog

Status: Deferred. This record does not amend the frozen v1.3 release.

Origin SHA-256: `8d1265d78cf7ed9d108b10ae3d57aa3ed85a901dc721cec7c81d997ed1b184eb`

The evidence identity is recorded in the [v1.3 frontier freeze](../releases/ISHIKAWA_V1_3_FRONTIER_FREEZE.md).
Routing
Routing is now doing the right things: policy identifiers, document names, department aliases, catalog requests, and follow-up intent are handled before ordinary semantic retrieval.

There are two optimization opportunities:
1. Compute the deterministic route once per request.
   The same router is currently wired into both scope classification and query resolution at [runtime.py](../../Ishikawa/application/python/ishikawa/runtime.py). Scope routing and query resolution each open their own transaction and repeat document/department lookup; the second path is in [query_routing.py](../../Ishikawa/application/python/ishikawa/query_routing.py).
   A single immutable RoutePlan could supply both decisions. This would also guarantee that scope and resolution see precisely the same active publication state.
2. Batch or request-cache source-name resolution.
   Multi-turn requests can currently open separate database connections for individual prior source references. Resolve all source names in one query, or retain them in the request-scoped route plan.
These are modest latency improvements, but they simplify correctness as the corpus grows.
Retrieval
The lexical, vector, Nomic, and fusion lanes are already fast. I would not change weights, RRF, candidate depths, or ranking topology.

The major inefficiency occurs after ranking. The gate averaged:
- 194.6 authorized reconstruction candidates
- 31.6 passages retained in the final evidence package
Authorized candidate count and reconstruction-plus-tokenization time have a 0.90 correlation. Ishikawa expands and hydrates the entire ranked pool in [postgres_retrieval.py](../../Ishikawa/application/python/ishikawa/postgres_retrieval.py), even though generation admits only six optional groups.

I would optimize this by:
- Hydrating the six selected response-envelope groups first.
- Retaining a small ranked fallback queue in case a group fails citation, diversity, or context checks.
- Hydrating additional groups only when a fallback is actually needed.
- For ordinary questions, expanding only the three relationship groups eligible for generation.
- Preserving complete relationship traversal for explicit relationship-navigation questions.
- Filtering citation-display reconstruction by the selected structural roots in SQL instead of loading the entire document and filtering it in Python.
This should reduce retrieval by roughly 300–500 ms without changing ranking or answer quality. It must still pass the 60-question gate because it changes when candidates are expanded, even though it does not change their order.
Packing
Packing repeatedly calls the Gemma tokenizer while progressively growing and then trimming the evidence package. The cumulative recount occurs in [reconstruction.py](../../Ishikawa/application/python/ishikawa/reconstruction.py), followed by exact serialized-prompt checks in [postgres_retrieval.py](../../Ishikawa/application/python/ishikawa/postgres_retrieval.py).

A better bounded method would be:
- Use cached individual passage counts and conservative framing overhead for preliminary selection.
- Construct the final serialized request.
- Perform one authoritative exact chat-template token count.
- If it exceeds the target, remove the lowest optional group and count again.
The final exact count must remain; approximation should only eliminate unnecessary intermediate tokenizer calls.
Generation
Generation is the largest opportunity. Across the 60 cases, completion length and generation time had a 0.9989 correlation:
- Fixed generation overhead: approximately 457 ms
- Additional cost: approximately 37.4 ms per completion token
That means eliminating 50 unnecessary output tokens saves approximately 1.9 seconds.

The current request permits up to the full 2,048-token answer reserve in [generation.py](../../Ishikawa/application/python/ishikawa/generation.py). A later release should evaluate a dynamic output budget:
- Routine answer: 256 tokens
- Multi-document or catalog answer: 512 tokens
- Explicit complete procedure or exhaustive request: 1,024–2,048 tokens
Streaming could improve perceived latency, but dynamic answer sizing will reduce actual compute time. Either change needs the full frontier gate and human review.
Additional tables
I would add one logical routing structure before scaling to the black corpus:
1. rag.document_routing_facts
   One immutable row per artifact/document version containing trusted normalized metadata:
   - canonical policy/document identifier
   - normalized title
   - normalized department
   - applicability/class
   - preferred routing citation
   - artifact set and document-version identities
2. rag.document_routing_aliases
   Multiple indexed aliases per routing fact:
   - alias kind: department, title, identifier, abbreviation
   - normalized alias
   - artifact/document-version identity
This would replace the current per-chunk JSON extraction, alias-array expansion, citation regular expressions, and DISTINCT scans in [query_routing.py](../../Ishikawa/application/python/ishikawa/query_routing.py).

It should be:
- Generated during ingestion from trusted normalized header metadata.
- Stored only in PostgreSQL.
- Version-specific, not placed on the cross-version documents row.
- Published atomically with the artifact set.
- Exposed through a security-barrier active-routing view.
- Validated for duplicate canonical identifiers and ambiguous aliases.
A later release should also consider a composite citation index supporting document-version, structural-root, and page lookup. The current index set only indexes citations by chunk in [schema.sql](../../Ishikawa/packaging/database/schema.sql). Its exact columns should be chosen from EXPLAIN (ANALYZE, BUFFERS) against a black-corpus-sized database.

I would not add an HNSW vector index yet. The exact vector scan averages only 56 ms, and approximate indexing could affect the qualified MRR. Reconsider HNSW only when black-corpus measurements show vector SQL becoming material.

My priority order would therefore be:
1. Early bounded hydration and relationship expansion.
2. Fewer tokenizer calls.
3. Dynamic generation length.
4. Single-pass request routing and batched source resolution.
5. Add normalized routing-facts and routing-alias tables for black-corpus scale.
6. Consider citation and vector indexes only after black-corpus EXPLAIN evidence.
