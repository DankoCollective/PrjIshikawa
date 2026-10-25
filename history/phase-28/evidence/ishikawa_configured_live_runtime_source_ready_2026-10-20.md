# Ishikawa Configured Live Runtime Source Ready

Date: 2026-10-20

Operator-executed Script `74` is accepted. Its retained report is
`configured_model_dependencies_20261020T163502Z_G2t0ym.txt` with SHA-256
`374c87ad6888aee8120c996dfc307cefccb6baf684bb125c2a1fd9ec667e70e3`.
Its content-free artifact has SHA-256
`eadca5dc1a3e15c9ba0eeebf5edc8a8891d6a861853596872cb9eb7b4504b044`.
The configured tokenizer passed twice at 11 tokens. The configured singleton
embedding passed twice at 768 dimensions with a maximum repeat delta of zero.
No credential, raw probe text, or vector was retained, and operator-owned
forwarding remained unchanged.

The first operator-executed Script `75` reached the configured runtime but
blocked with `runtime_response_contract_invalid`. Its retained content-free
receipt is `configured_live_runtime_20261020T164431Z_ddWsU5.txt`. Cleanup and
state protection succeeded: the empty accepted database was unchanged,
PostgreSQL returned to stopped, port `1384` was released, forwarding remained
operator-owned, and no raw content, vector, or credential was retained. The
original runner reduced all response-contract differences to one reason and
therefore did not retain enough safe evidence to determine which boundary
differed.

The bounded diagnostic rerun is retained as
`configured_live_runtime_20261020T164909Z_4eO9WL.txt`. It observed HTTP `500`,
the fixed transport error, and zero scope, embedding, database, tokenization,
or generation calls. This isolated late-bound self-recursion in the
qualification observer: its closure resolved the replaced executor instead of
the original configured executor. The runner now captures that callable before
replacement and has a local self-test proving exactly one call and one trace
observation. No production runtime module, frozen method setting, database, or
remote service changed.

Corrected Script `75` is source-ready as the same bounded integration gate. It binds
those exact Script `74` identities, stages the complete Python runtime and all
12 validated profiles, and uses only the already-established loopback model
forwarding. It starts the existing boot-disabled PostgreSQL cluster, verifies
the accepted schema-v4 `rag_catalog` is empty, and prompts privately on the
target terminal for the Gemma key, Nomic key, and existing `rag_retrieval`
password.

One synthetic professional question is submitted through the real
`127.0.0.1:1384/v1/chat` boundary. The bounded expected path is:

1. direct-injection scan passes;
2. Gemma scope classification allows the professional question;
3. the no-history/no-source question resolves deterministically;
4. Nomic produces one singleton query embedding;
5. the `rag_retrieval` role performs one read-only database transaction;
6. Gemma performs two exact tokenization calls for instruction and
   conversation accounting; and
7. the empty catalog produces the fixed `insufficient-evidence` response,
   without grounded generation.

The target helper verifies the accepted database before and after the request,
stops PostgreSQL, verifies port `1384` is released, and verifies both external
forwarding listener identities remain unchanged. It retains no credential,
request, response, or vector. The corrected gate uses a more explicit
professional operating-procedure question. A blocked run now emits only
allowlisted HTTP status, application status, error code, trace category, event
category, and dependency-call counts. The local source gate passed all 270
tests, the staged package import, evaluator self-test, accepted Script `74`
bindings, and shell/Python validation without target, database, or model
contact.

Validated source identities:

- wrapper:
  `b9d75a6f8cb15ba7f7b7ca03ba35fe5d596704bbcd4b8dea256719aa9be6bfa6`
- neutral target helper:
  `91b7b48249ae60af48a34b89077ce67fc7cce6d03c876de282f1e5fd284ef1f1`
- target runner:
  `1b298d5118ee370fa21cb784fb971375ee2fed4ec03e2740bd9dccf150d35d33`
- local evaluator:
  `de1dd259b653a837c224d43cb2ca908bab4b1a6e04f5a33e7e87cf77009a8795`
- staged payload manifest:
  `065a32df445bd15adf9f91f1d67d8cb2c3fd4b59854fecfe7995150b84cd4707`

The corrected operator-executed Script `75` subsequently passed. Its retained
report is `configured_live_runtime_20261020T165151Z_OnxFHl.txt` with SHA-256
`bc8ec1f4ef5b4221222fbe2ddf837eebf71e0e3fce9bf400f172557896da1980`.
Its content-free artifact has SHA-256
`36c3e880092cab03e179814a9efa6b4cb94b85c77778951002745d856d236376`.
The request returned HTTP `200` with `insufficient-evidence`; scope ran once,
query resolution was deterministic, Nomic ran once, PostgreSQL opened one
read-only retrieval connection, Gemma tokenization ran twice, and grounded
generation did not run. The accepted database remained empty and unchanged,
the retrieval listener stopped, PostgreSQL returned to stopped/disabled,
operator-owned forwarding remained unchanged, and no credential, raw request,
raw response, or vector was retained. The next gate is the operator-ingestion
command.
