# Evidence Reconstruction Contract and Implementation

## Boundary

Reconstruction begins after direct three-lane fusion and separately marked
one-hop relationship traversal. It does not search, embed, classify, call
Gemma, or write PostgreSQL. The caller supplies authorized evidence records,
complete document inventory when requesting a complete procedure, an
authoritative generation-token counter, and a versioned budget policy.

The implementation is in `application/python/ishikawa/reconstruction.py`.
Script `42` qualifies the deterministic foundation locally against the
checksum-bound 126-candidate synthetic artifact. Script `43` subsequently
qualified the exact deployed Gemma tokenizer, and Script `44` accepted the
initial numeric application budget without changing the deployed service.

## Evidence behavior

The implementation:

- removes exact duplicate chunk identities;
- removes exact duplicate retrieval-text projections;
- preserves every nonconflicting citation when duplicates are consolidated;
- retains distinct relevant excerpts from the same document;
- preserves whether evidence came directly from retrieval or from an
  authorized one-hop relationship and retains relationship provenance;
- groups selected passages by document version;
- assigns stable `Source 1`, `Source 2`, and subsequent labels in strongest-
  evidence order; and
- permits one source group to contain multiple passage and citation
  identities.

Normal context assembly observes the configured per-document diversity limit.
An explicit document-version request uses a separately configured higher
limit. Neither behavior removes a passage merely because another passage came
from the same document.

## Complete procedures

A complete-procedure request must provide a verified complete inventory for
one document version. Reconstruction selects the requested canonical
structural path, or the whole procedural document when the path is empty, and
orders its semantic units by stored source ordinal. It excludes derived blank-
page status and duplicate table-context projections from procedure bodies.
Similarity search is not used to rediscover procedure steps.

The complete procedure is atomic for budgeting. If its assembled text does
not fit, the result is `context-limit` with reason
`COMPLETE_PROCEDURE_CONTEXT_LIMIT`; no partial procedure is returned while
claiming completeness.

## Token and context behavior

The reconstruction policy carries the pinned tokenizer identity, total
context, instruction limit, conversation limit, evidence limit, reserved
answer tokens, and both diversity limits. Canonical policy content produces a
stable method identity.

The accepted initial application context is 32,768 tokens, partitioned as:

- 2,048 instruction tokens;
- 12,288 accepted-conversation tokens;
- 16,384 retrieved-evidence tokens; and
- 2,048 reserved answer tokens.

The deployed Gemma service remains configured for 204,800 tokens. The smaller
application limit is deliberate and is enforced independently. The original
zero-temperature reconstruction-policy identity accepted by Scripts `43`
through `49` was
`dd63ff812f8b482d95d25d1a15b2dbdb1aef750f65e17823ed02eeb3c03bb1c9`.
After the operator selected Gemma's publisher sampling profile, the candidate
policy identity became
`2c1e0ebdc9f626eaecfc3f52913642e0cfa7597ec2c922061a1766014a53d5cf`.
The original evidence remains historical; the candidate identity requires a
new numbered qualification before deployment acceptance.

The implementation never estimates tokens. It requires a supplied counter and
rejects invalid results. It never clips an atomic passage. A passage that does
not fit is omitted with an explicit budget reason. Instruction,
conversation, evidence, and complete-procedure overruns return explicit
`context-limit` results. Conversation history is not silently dropped or
summarized.

For an ordinary answer, the exact serialized model request is evaluated
against 8,192-, 12,288-, and 16,384-token prompt targets in that order. The
first package that passes the unchanged deterministic sufficiency gate is
used. The 30,720-token hard prompt ceiling remains a safety boundary, not a
packing target. Explicit complete-section and complete-procedure requests may
use that hard ceiling because completeness is part of the operator request.
Before token fitting, ordinary generation retains at most the six
highest-ranked optional structural units plus every mandatory exact or
operator-requested relationship unit. This relevance bound applies even when
compact serialization would allow a much broader package to fit beneath 8,192
tokens. Units are retained whole and in fused-rank order.

Retrieval-enriched identity prefixes remain retrieval signals. Model evidence
uses the authoritative citation excerpt stored in PostgreSQL. The generation
payload assigns request-local aliases such as `C1`, groups repeated source,
document, page, and structural-path metadata once, and maps every returned
alias back to its authoritative citation identity before validation. Citation
display is independent: after answer validation, the API reconstructs the
complete cited structural section from PostgreSQL for the operator.

## Script 42 boundary

Script `42`:

- verifies the accepted schema-v4 migration receipt and synthetic chunk
  artifact identities;
- runs all 123 local tests;
- reconstructs the 15-unit synthetic procedure and its 3-unit triage section
  in source order;
- proves exact deduplication, citation preservation, source grouping,
  diversity, relationship provenance, atomic passage handling, and all-or-
  limit complete-procedure behavior; and
- retains only a content-free local report.

It performs no SSH, database contact, network access, model call, source-PDF
read, schema change, or application-data mutation.

## Scripts 43 and 44

Operator-executed Script `43` bound the reconstruction method to the exact
deployed `GemmaTokenizer`, model snapshot, chat-template identity, and
thinking-disabled setting. It measured all 126 accepted synthetic candidates,
the complete 15-unit procedure, and its 3-unit triage section without calling
the model or retaining raw text in routine evidence.

Operator-executed Script `44` then qualified the 32,768-token allocation,
proved instruction, conversation, evidence, and complete-procedure boundaries,
and ran all 127 then-current local tests. Full composed-request measurement,
latency, and answer quality were deliberately not claimed by that script.

## Grounded generation request builder

`application/python/ishikawa/generation.py` constructs a deterministic request
body but has no transport or model-call capability. It keeps the trusted fixed
instruction in a system message and serializes accepted conversation, current
question, evidence excerpts, and the exact citation allowlist as one canonical
JSON user payload. Prompt-shaped text remains data inside that payload. The
request fixes thinking off, streaming off, publisher sampling defaults
(`temperature` `1.0`, `top_p` `0.95`, and `top_k` `64`), and maximum
answer tokens to the accepted 2,048-token reserve. It contains no endpoint or
credential.

Operator-executed Script `45` accepted this builder and retained one protected
synthetic request artifact. Operator-executed Script `46` measured that exact
request with the accepted deployed tokenizer: 884 prompt tokens plus the
2,048-token answer reserve use 2,932 of the 32,768-token application limit,
leaving 29,836 tokens. Script `46` did not call Gemma or read a credential.

## Generation transport and grounded-response validation

`application/python/ishikawa/generation_transport.py` keeps the first transport
boundary deliberately small. Deployment supplies an exact configurable
`/v1/chat/completions` URL, timeout, and response-size limit. The caller
supplies the runtime credential; it is placed only in the Authorization header
and never in the JSON request body. The native Python transport performs one
synchronous POST without redirects or automatic retries.

An HTTP result remains untrusted until fixed application logic validates the
status, media type, OpenAI-compatible response envelope, exact served-model
identity, single completed choice, absence of reasoning or tool channels, and
internally balanced usage counts within the 2,048-token answer reserve. The
assistant content must be either one raw JSON object or exactly one isolated
lower-case `json` Markdown fence containing that object. Whitespace or prose
outside the fence, additional fences, and other fence labels are rejected. The
object contains only one ordered `segments` array. Every segment must contain
nonempty answer prose and one or more citation identities from the request
allowlist. Fixed application logic validates the complete sequence and then
displays it as flowing prose; no competing model answer field exists.
Malformed, incomplete, oversized,
unauthorized, or ungrounded model output fails closed with a stable
content-free reason code.

The observed vLLM compatibility envelope may include `ec_transfer_params`,
`metrics`, and `prompt_text` at the top level, `routed_experts` on the choice,
and `annotations` on the message. These fields are accepted only when null or
empty. Populated private, reasoning, tool, or compatibility channels remain
rejected.

Operator-executed Script `47` accepted the original transport and validator
locally against 152 tests. The frozen compatibility correction now passes 155
local tests. It used only the accepted synthetic request and content-free
token measurement; it did not contact a target, read a runtime credential, or
call Gemma.

Script `48` made the first bounded live synthetic generation call. The target
returned a complete response, and the strict pre-correction validator retained
it as protected rejection evidence rather than exposing it. Review proved that
Gemma returned one isolated JSON fence and that five previously unknown vLLM
compatibility fields were null. The endpoint reported 885 prompt tokens versus
the offline tokenizer's 884; each count is retained in its own measurement
domain, and the live endpoint count governs actual endpoint usage.

Script `49` revalidates that checksum-bound retained response under the frozen
correction without another Gemma call or credential read, runs the held-out
answer and citation checks, writes protected normalized evidence, and removes
only the checksum-bound stale target directory left by Script `48`. The target
runner now disables Python bytecode creation so this ownership mismatch does
not recur.

## Publisher sampling profile

The operator selected the Gemma publisher profile for every Ishikawa Gemma
request: `temperature: 1.0`, `top_p: 0.95`, and `top_k: 64`. These values are
explicit fields in both versioned YAML profiles, validated by application
code, included in request bodies, and therefore included in request and policy
identities. They apply to grounded answer generation and scope
classification. Thinking remains disabled. This deliberately replaces the
earlier zero-temperature candidate and must be requalified before the new
identities are treated as deployment evidence.
