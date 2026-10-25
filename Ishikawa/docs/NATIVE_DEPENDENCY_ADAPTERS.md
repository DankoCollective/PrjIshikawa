# Native dependency adapters

Ishikawa Retrieval API uses small native Python adapters at the boundaries to
Nomic and Gemma. They use Python's standard-library HTTP client; they are not
separate services and add no third-party HTTP client dependency.

## Accepted boundary

- Query embedding sends exactly one question per request to the configurable
  `/v1/embeddings` endpoint.
- The query is prefixed with `search_query: ` and uses
  `nomic-ai/nomic-embed-text-v1.5` in the accepted 768-dimensional embedding
  space.
- The embedding response may include vLLM's allowlisted compatibility fields
  `created`, `id`, `completion_tokens`, and `prompt_tokens_details`. Their
  shapes are validated, `completion_tokens` must be zero, and none of these
  non-authoritative fields is retained in the accepted embedding result.
- Scope classification sends the typed conversation history and resolves each
  prior source identifier to its trusted document display name before calling
  Gemma.
- Grounded generation sends the typed conversation history and the bounded,
  citable evidence selected by retrieval.
- Reconstruction token measurement sends one bounded text value to Gemma's
  configurable vLLM `/tokenize` endpoint with the exact served-model identity,
  special-token counting enabled, and token strings disabled. The returned
  count must equal the returned token-array length, and the reported model
  capacity must cover Ishikawa's 32,768-token application window.
- Scope and generation preserve the already accepted Gemma sampling and
  response-validation contracts.
- Each adapter invocation makes one synchronous, nonstreaming request and
  performs no internal retry. Under the v1.1 T10 amendment, the Retrieval API
  may invoke grounded generation one additional time only after its adapter
  classifies a Gemma transport or validated-response failure as retryable.
  Credentials and every non-generation dependency remain single-attempt.
- Endpoint URLs are deployment configuration. They cannot contain embedded
  credentials, query parameters, fragments, or an unexpected API path.
- A protected runtime credential provider supplies the credential for the
  authorization header at call time. Credentials are never stored in YAML,
  request bodies, adapter results, or qualification evidence.
- Malformed responses, unavailable dependencies, invalid credentials, and
  unexpected transport behavior fail closed as a dependency-unavailable
  outcome at the retrieval-service boundary.
- A grounded-generation retry is recorded as the content-free
  `generation-retry` pipeline stage. Debug logging additionally records
  `retry_state` without retaining model output or credentials. A second
  failure returns the same client-safe dependency-unavailable outcome.

## Deliberate boundaries

Script 64 qualifies the Nomic query-embedding adapter and the two Gemma
adapters without contacting a model, database, or network endpoint. It does
not claim that the PostgreSQL retrieval adapter, contextual follow-up query
resolution, relationship expansion, reconstruction, HTTP listener, or full
live service path is implemented. Those remain later gates.

Script `70` adds the exact vLLM tokenization adapter and the configuration-to-
runtime assembly. It loads all 12 profiles, wires concrete Gemma, Nomic,
PostgreSQL, source-resolution, orchestration, and listener-factory boundaries,
and proves a direct-injection request short-circuits without touching any
dependency. This is a local wiring qualification only. It does not claim that
the configured `/tokenize` endpoint has passed a live request; that is the next
separate gate.
