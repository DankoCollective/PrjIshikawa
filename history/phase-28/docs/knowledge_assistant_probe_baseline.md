# Knowledge Assistant Probe Baseline

## Status

Frozen as the evidence-gathering baseline for the next Phase 28 work session.
This document does not freeze an implementation architecture that has not yet
been validated against the existing code and API contracts.

## Product Target

The Knowledge Assistant is a simple multi-turn professional and organizational
chat interface. It must preserve conversation context sufficiently for users to
ask follow-up questions about prior answers and cited sources.

The accepted question categories are:

- organizational policy;
- applicable regulation;
- code of conduct;
- operating procedures;
- professional questions related to organizational work; and
- follow-ups about previously returned answers or sources.

The pre-retrieval decision contract is `allow`, `deny`, or
`needs_clarification`. An ambiguous professional question should request
clarification rather than being denied automatically.

The source-details panel is in the primary target and displays the retrieved
chunk plus available document metadata. Opening or downloading an original
document is a stretch target.

## Candidate Service Boundaries

The required capabilities do not determine the final internal API topology.
The evidence review must consider at least these arrangements:

1. The existing retrieval-workflow API and a direct-Gemma API remain sibling
   services used by the Knowledge Assistant server.
2. The retrieval-workflow API calls a new endpoint provided by the existing
   direct-Gemma API, leaving the Knowledge Assistant with one retrieval-facing
   integration.
3. The required direct-Gemma operations are incorporated into the retrieval
   API when that produces the smallest coherent service boundary.

The stable boundary is that the browser communicates only with the Knowledge
Assistant server. The browser must not call vLLM or an internal API directly.
Endpoint locations and related runtime settings belong in configuration rather
than the user interface.

Candidate direct-Gemma operations are:

- pre-retrieval question-scope classification;
- rewriting contextual follow-ups as standalone retrieval queries;
- resolving references such as `Source 1`;
- summarizing older conversation history;
- generating concise chat titles; and
- answering permitted professional questions that do not require retrieval.

These operations are accepted product capabilities, but their ownership,
deployment, and request flow are not final until the existing API behavior is
inspected.

## Frozen Probe Order

Review sanitized evidence in this order:

1. Retrieval API request and response contracts.
2. SQLite schema.
3. Chunking boundaries, overlap, identifiers, and recorded metadata.
4. Ingestion mapping between documents and chunks.
5. Embedding model, dimensions, normalization, and query construction.
6. Retrieval scoring, limits, filtering, and reranking.
7. Existing direct-vLLM request construction.

## Explicitly Unresolved

Do not assume or freeze any of the following before the probe is complete:

- token-usage fields in API responses;
- the application context-token limit;
- support for conversation history in the existing API;
- document names, paths, types, scope, page numbers, or stable document IDs in
  stored metadata;
- document-filtered retrieval;
- a SQLite metadata migration;
- conversational query-rewrite mechanics; or
- original-document open or download endpoints.

The current corpus was ingested from a single directory. No document type or
scope metadata may be inferred from a directory hierarchy without evidence in
the database or ingestion records.

## Sanitization Boundary

Evidence supplied for review must exclude credentials, tokens, certificates,
private hostnames, organization identifiers, document contents, sensitive test
fixtures, private paths, and logs containing those values. Preserve contract
field names, data types, control flow, and schema relationships wherever they
are not sensitive.
