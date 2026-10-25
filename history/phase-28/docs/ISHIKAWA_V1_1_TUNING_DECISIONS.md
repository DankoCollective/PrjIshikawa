# Ishikawa Retrieval-Tuning Decision List

## Purpose

This list is the durable authority for Ishikawa v1.1 retrieval tuning. It
keeps tuning decisions separate from the closed Phase 28 design and gap lists
while preserving those decisions unless an item below explicitly narrows or
reopens one.

The accepted Ishikawa v1 deployment archive remains immutable and is the
fallback release. No tuning run may overwrite it or its acceptance evidence.

## Decision Status

| ID | Decision | State |
|---|---|---|
| `T01` | Resolve recognized document identifiers and the narrow `What about [document]?` form with deterministic application code and read-only PostgreSQL matching before Gemma scope classification. A handled route invokes neither Gemma nor its credential provider. An unhandled route continues through the existing Gemma scope path. | FROZEN |
| `T02` | Tune from the working source on DankoSurface against local native PostgreSQL. The operator forwards Gemma and Nomic from the model host before each run and removes forwarding afterward. Ishikawa owns only the configured loopback endpoint URLs. Next.js and deployment-package assembly are excluded from the iterative ranking loop. | FROZEN |
| `T03` | Use the checksum-bound 13-case synthetic set. Compute authoritative `MRR@20` over responsive cases `R-001` through `R-006`. A relevant hit is the first fused chunk whose document display name and cited page match one required-evidence expectation. Measure required-evidence recall separately over all 13 per-case expectations, representing 12 unique document/page pairs, so one early relevant result cannot conceal missing evidence. | FROZEN |
| `T04` | Accept a candidate only when `MRR@20` is at least `0.85`, every responsive case has relevant evidence within its top five fused results, all 13 per-case required-evidence expectations occur within the top 20, all six nonresponsive cases abstain, `B-001` requests clarification, the full API run matches all 13 expected statuses, and there are no dependency failures. | FROZEN |
| `T05` | Separate deterministic ranking measurement from generative acceptance. The ranking loop uses PostgreSQL, Nomic, and fixed case questions without Next.js or grounded generation. Gemma participates later in the full Retrieval API acceptance run, including scope, query resolution where required, token measurement, and grounded generation. Gemma does not decide whether the ranking gate passed. | FROZEN |
| `T06` | Explore candidate lane depths, lane weights, and RRF constants without rewriting the accepted method profile on every trial. Each trial records its exact parameters and result identity. Only the winning candidate may replace the tracked method profile, receive a new profile identity, and enter complete regression and API qualification. Chunking, ingestion, stored embeddings, and the database schema remain unchanged during this tuning. | FROZEN |
| `T07` | Defer the v1.1 deployment build until the local tuning and full API gates pass. The previously prepared but unexecuted package gate is not an accepted artifact. After acceptance, assemble, qualify, and retain one final v1.1 package under a new identity while preserving v1 unchanged. | FROZEN |
| `T08` | Establish the DankoSurface tuning corpus from the canonical final-state schema and the checksum-bound six-document synthetic inputs instead of copying the EmceeDanko database. The accepted local inventory is six documents, 27 pages, 126 chunks, 126 citations, and 126 embeddings; PostgreSQL remains native, local, and read-only to retrieval. | FROZEN |
| `T09` | Adopt Script `119` candidate `a767efb74a690f4ded16b1aed5f4d2c0b880a40dfc4b22e653be366e616f4eda`: exact depth `1`; lexical, vector, and fused depths `20`; RRF constant `60`; exact/lexical/vector weights `1/1/4`; and no learned reranker. All other retrieval settings remain unchanged. Exact priority remains a separate deterministic boundary. This is a profile selection, not general-performance acceptance; it must pass native regression, a fresh live 13-case ranking run, nonresponsive abstention, and the complete Retrieval API gate before v1.1 packaging. | FROZEN |
| `T10` | Narrowly reopen and refreeze the G15 no-retry boundary: after the grounded-generation adapter reports a Gemma transport or validated-response failure, the Retrieval API may immediately retry grounded generation exactly once with the same accepted request and evidence. No retry applies to retrieval, database access, credentials, security rejection, insufficient evidence, scope, query resolution, token measurement, or embedding. A second failure remains `temporarily-unavailable`. The approved Gemma sampling settings remain unchanged. The content-free stage trace and debug logging record whether the retry occurred. | FROZEN |
| `T11` | Require a 60-case automated retrieval-only gate before org-target promotion. Every case has at least one immutable synthetic document/page relevance target. Compute `MRR@20` across all 60 cases and require an exact value strictly greater than `0.91`; exactly `0.91` does not pass, and top-five/top-twenty coverage are diagnostics only. Do not perform manual answer review, call Gemma, or mix abstention, ambiguity, injection, or generation cases into MRR. Script `127` produced a valid `0.852173` observation under the accepted T09 profile, so the strict promotion target is not met. Script `128` must reclassify that retained observation without another model request before any evidence-driven tuning work. | FROZEN; STRICT TARGET AMENDED AFTER SCRIPT 127 |
| `T12` | When a question contains exactly one recognized structured document identifier and one unambiguous page number, resolve the identifier against active citation excerpts using the existing conservative self-declaration forms: a bare form identifier, `Form no.`, or `Policy Number:`. Exactly one active owner routes directly to that owner's cited page before ordinary rank fusion. No owner preserves ordinary retrieval. Multiple active owners require clarification and never guess. This changes neither the schema, stored embeddings, model calls, nor operator configuration. | FROZEN |
| `T13` | Treat the post-v1.1 T12 retrieval behavior as the Ishikawa v1.2 candidate. The accepted v1.1 archive remains immutable and available for fallback. A v1.2 release requires the fresh strict 60-case MRR gate, complete 13-case Retrieval API regression, consolidated final-state package assembly, disposable host qualification, and explicit release acceptance under new identities. Do not mutate or relabel the accepted v1.1 package. | FROZEN |
| `T14` | Constrain grounded Gemma generation with vLLM's native `response_format` JSON Schema. The schema permits exactly `answer` and `claims`, disallows extra fields, requires nonempty answer, claims, claim text, and citation lists, and restricts citation identifiers to the accepted evidence allowlist for that request. Ishikawa's existing strict response validator remains the authoritative trust boundary. T10's one retry and the approved temperature `1.0`, top-p `0.95`, and top-k `64` remain unchanged. Qualification requires repeated `R-006` probes before the complete 13-case gate. | FROZEN |
| `T15` | Preserve the public Retrieval API `/ready` response as only `ready` or `not-ready`, but make operator-start failures actionable. Before starting the Retrieval API, the stack runs one local content-free readiness inspection that reports `pass` or `blocked` independently for configuration, protected storage, PostgreSQL, Gemma health, and Nomic health. If runtime readiness later fails, the stack repeats that inspection before rollback. Diagnostics never include credentials, paths, endpoint bodies, database values, document content, or raw exceptions. This changes no retrieval, ranking, embedding, corpus, database, or model behavior and does not mutate the accepted v1.2 release. | FROZEN |

## Ordered Evidence Gates

1. Verify the working source, local host identity, forwarded health endpoints,
   and exact active synthetic corpus inventory.
2. Implement and self-test a read-only ranking evaluator that records each
   lane and the fused order without retaining vectors, credentials, or source
   text.
3. Measure the accepted profile to establish the local `MRR@20` and evidence-
   recall baseline.
4. Run bounded parameter candidates from temporary in-memory profiles and
   compare them against the frozen acceptance gates.
5. Freeze the winning profile and rerun the complete native regression suite.
6. Run the 13 cases through the complete Retrieval API with Gemma and Nomic.
7. Assemble and qualify the final v1.1 deployment package once.

## Current Execution Status

- Gates 1 and 2 are complete through accepted Scripts `115`, `117`, and `118`.
- Gate 3 measured the frozen profile at `MRR@20 = 0.690476`, responsive
  top-five coverage `5/6`, and required-evidence recall `13/13`. Script `118`
  passed as a measurement, but the ranking gate was not met.
- Gate 4 passed through Script `119`: 43,120 bounded candidates were replayed,
  978 met the ranking gate, and the deterministic KISS selector recommended
  the same candidate as both the highest-quality and smallest-change result.
  The operator froze that candidate as `T09`.
- Gate 5 passed through Script `120`: the frozen T09 profile identity was
  reproduced and all 371 native tests passed with zero failures or errors.
- Gate 6 ranking passed through Script `121`: fresh live retrieval measured
  `MRR@20 = 0.916667`, responsive top-five coverage `6/6`, required-evidence
  recall `13/13`, and deterministic clarification for `B-001`.
- Two complete Script `122` runs with valid dependencies each returned one
  different responsive case as `temporarily-unavailable`: first `R-006`, then
  `R-003`. Both runs passed all six nonresponsive abstentions and `B-001`.
  Repeating until a stochastic run happened to pass was rejected as an
  acceptance strategy. T10 therefore refreezes a single grounded-generation
  retry; its implementation and regression gate is Script `123`.
- Gate 6 passed through the accepted amended Script `122` run: all 13 cases
  returned their expected statuses with no dependency failure.
- Gate 7 assembly and host qualification passed through Scripts `124` and
  `125`. The exact package contains the consolidated final-state application
  and version-4 database schema, passed 376 native tests, and passed disposable
  fresh installation on EmceeDanko without changing the accepted corpus or
  active application. Script `126` then accepted exact archive SHA-256
  `e5e11c6054b1163868bc21d3b267d804894de0e936c1c1d28c6f506680746e25`
  as Ishikawa v1.1 without rebuilding or duplicating it. Gate 7 is complete.
- The operator froze T11 after release acceptance. Script `127` is the
  mandatory automated 60-case pre-org promotion gate. Script `127` measured
  `MRR@20 = 0.852173`, with relevant evidence in the top 20 for all 60 cases.
  The operator then amended the target to strict `MRR@20 > 0.91`. Script `128`
  reclassifies the retained observation without another Nomic request; the
  accepted package and retrieval profile remain unchanged.
- Script `130` exhausted 43,120 bounded depth, weight, and RRF candidates.
  None met strict `MRR@20 > 0.91`; the best reached `0.853168`. Review of the
  retained ranks identified five explicit `99 TST 2005` page questions whose
  active policy self-declaration was present in citation evidence but was not
  recognized by the old exact-equality owner lookup. T12 freezes that narrow
  deterministic routing correction. It leaves T09 ranking parameters intact
  and requires native regression plus a fresh 60-case measurement before any
  promotion claim.
- Script `131` passed the T12 implementation gate: all 379 native tests passed;
  the active `Policy Number: 99 TST 2005` self-declaration resolved exactly one
  owner and routed pages 2, 3, 5, 8, and 11; an unknown declaration preserved
  ordinary retrieval. Its retained-rank projection was exactly `6619/7200`,
  displayed as `0.919306`. That projection is diagnostic only. Script `132`
  must request fresh singleton Nomic embeddings for all 60 questions, perform
  live read-only retrieval, and apply the strict `MRR@20 > 0.91` gate before
  T12 can support any promotion claim.
- Script `132` passed the fresh strict gate at `MRR@20 = 0.919306`. Relevant
  evidence appeared within the top 20 for all 60 cases and within the top five
  for 59 cases; all five T12 direct-page cases placed the required evidence at
  rank one. T13 therefore names the changed source as the Ishikawa v1.2
  candidate. Script `133` must rerun the complete 13-case Retrieval API gate
  against that exact source before v1.2 package assembly.
- Script `133` completed a contract-valid 13-case run, but the release gate
  was not met: `R-006` returned `temporarily-unavailable` after about five
  seconds, while the other 12 cases matched their expected statuses. The
  retained response intentionally exposes only the generic fail-closed
  dependency error, and the temporary service logs were removed. Script `134`
  therefore performs a five-request, `R-006`-only reliability diagnostic and
  retains content-free stage traces before any retry-policy or package change.
- Script `134` passed its bounded diagnostic, but the reliability target did
  not: two of five identical `R-006` requests answered on the first attempt,
  while three exhausted T10's permitted retry and returned `temporarily-
  unavailable`. All three failures occurred at grounded generation after
  retrieval and sufficiency passed; no database, retrieval, security, scope,
  query-resolution, or internal failure was observed. The existing trace does
  not distinguish transport failure from strict model-response rejection.
  Script `135` therefore observes only stable generation failure family and
  reason codes during five fresh probes. It changes no application source,
  policy, database state, accepted release, or package, and it retains no raw
  prompt, response, question, evidence, credential, vector, or exception text.
- Script `135` passed and classified all eight failed generation attempts as
  strict response-validation failures: seven `MODEL_OUTPUT_SCHEMA_INVALID`
  and one `MODEL_OUTPUT_JSON_INVALID`. It observed no transport or
  unclassified failure. T14 therefore adds a native JSON Schema constraint to
  grounded generation only; it does not relax validation or expand retry.
  Script `136` runs the complete native regression suite and five repeated
  `R-006` probes against the exact T14 source. A clean pass requires all five
  requests to answer with the required citation and no retry or dependency
  failure before the complete 13-case gate is rerun.
- The accepted Script `136` run passed: all 381 native tests passed, all five
  repeated `R-006` requests answered with the required evidence, and no retry,
  transport failure, response-validation failure, or other dependency failure
  occurred. Its temporary service was removed and no database or package was
  changed. Script `137` now runs the complete 13-case Retrieval API gate
  against that exact T14-qualified source before v1.2 package assembly.
- Scripts `137` through `143` completed the v1.2 API gate, consolidated
  final-state package, disposable EmceeDanko qualification, release
  acceptance, prerequisite binding, and stopped application upgrade. The
  upgraded v1.2 stack subsequently reached `state=ready`. Its first start
  attempt exposed only the coarse `retrieval_readiness_failed` marker even
  though readiness has five independently testable components. The operator
  froze T15 so later startup failures identify the blocked component without
  weakening the public health boundary or changing retrieval behavior.

## Metric Interpretation

`MRR@20` is a development ranking metric for this small synthetic set, not a
claim of general performance. Required-evidence recall and per-case top-five
coverage are co-equal acceptance checks. Later review against the black corpus
or CFR material requires a distinct held-out case set before any broader
quality claim.
