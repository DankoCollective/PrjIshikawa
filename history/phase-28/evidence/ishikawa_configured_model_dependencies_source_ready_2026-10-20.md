# Ishikawa Configured Model Dependencies Source Ready

Date: 2026-10-20

Operator-executed Script `73` accepted the EmceeDanko-to-model-host transport:
direct native-port access remained blocked, one temporary SSH tunnel carried
ports `8000` and `8001`, both forwarded health routes returned HTTP `200`, no
private key was transferred, and no API credential or model operation was
used. The qualification tunnel was stopped and its temporary state removed.

The operator then clarified and froze the runtime ownership boundary. Port
forwarding is not part of Ishikawa installation, configuration, startup, or
shutdown. The operator establishes forwarding before Ishikawa starts and
closes it after Ishikawa exits. Ishikawa owns only the endpoint URLs in YAML
and must fail closed when those endpoints are unavailable.

Script `74` implements the next bounded qualification under that boundary. It
requires pre-existing IPv4 loopback listeners at `127.0.0.1:8000` and
`127.0.0.1:8001`, loads the exact endpoint URLs from the checksum-bound runtime
configuration, prompts for Gemma and Nomic API keys only on the target
terminal, and exercises the production tokenization and query-embedding
adapters with synthetic inputs. Two tokenization calls must agree exactly; two
singleton embedding calls must agree within the frozen `1e-5` tolerance and
must return the frozen 768-dimensional embedding-space identity.

The gate makes no grounded-generation or PostgreSQL call. It retains no API
key, raw probe text, or vector. It does not start, change, or stop forwarding,
and acceptance requires both pre-existing listeners to remain present with
unchanged listener identities after qualification.

Local source validation passed all 270 tests, the staged package import, the
content-free evaluator self-test, accepted Script `73` evidence binding, and
the explicit operator-owned transport boundary. No target or model endpoint
was contacted during source validation.

The first run with operator-managed forwarding reached both local listeners
but blocked before producing an acceptance artifact because one configured
dependency was unavailable. The original content-free result collapsed the
tokenizer and embedding stages into one reason, which was insufficient for a
safe retry. The canonical Script `74` source now reports
`tokenization_dependency_unavailable` or
`embedding_dependency_unavailable` separately while preserving identical
scope and cleanup behavior. The corrected source again passed all 270 local
tests without target contact. No separate repair script was introduced.

A second run proved the Gemma tokenizer stage but again blocked in the Nomic
embedding stage. An independent `/health` request through the operator tunnel
returned HTTP `200`, so listener and service reachability are established.
Because the production adapter intentionally maps upstream details to one safe
dependency-unavailable error, the qualification wrapper now captures only the
non-content diagnostic boundary: transport reason, numeric HTTP status, or
stable response-validator reason. It never retains the response body, vector,
credential, or probe. This diagnostic correction again passed all 270 local
tests and remains in canonical Script `74`.

The next operator run again reached the embedding response boundary and
reported `embedding_schema_invalid`. A bounded manual request through the
same operator-managed tunnel and credential path then established the exact
response contract without retaining the credential, input text, or vector:
HTTP `200`, JSON content, one record, model
`nomic-ai/nomic-embed-text-v1.5`, dimension `768`, and `13` prompt tokens. The
response also carried vLLM compatibility fields `created` and `id` at the top
level and `completion_tokens` and `prompt_tokens_details` under `usage`.

The production validator now accepts only those additional field names. It
requires a bounded nonempty identifier, a nonnegative integer creation value,
zero completion tokens, and either absent, null, empty, or a bounded
`cached_tokens` prompt-token detail. It still rejects unknown fields and still
enforces the frozen model identity, singleton cardinality, 768 finite vector
values, nonzero vector norm, and exact prompt/total token relationship. The
compatibility fields are discarded rather than becoming authoritative
Ishikawa data. This is a correction to canonical Script `74`, not a new repair
script.
