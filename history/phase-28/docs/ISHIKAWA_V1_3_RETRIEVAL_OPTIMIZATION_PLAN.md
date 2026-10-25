# Ishikawa v1.3 Retrieval Optimization Test Plan

## Status and boundary

This is a parallel observational test plan, not a corpus-v2 promotion or
ingestion gate. It does not change the frozen production retrieval profile,
authorize or block corpus-v2 promotion, or modify the evaluation truth.
Corpus-v2 promotion continues on its own qualification path. Corpus v1 and the
accepted v1.2 package remain immutable.

## Why optimization is timely

Corpus v2 now adds document-control metadata routing and compatible-sibling
assemblies. Script 164 improved body MRR@20 from `0.811825` to `0.870992`, kept
all 60 body cases within the top 20, and retained header MRR `1.000000`, but it
did not meet the strict `> 0.91` body target. Script 165 identified both
assembly/atomic self-competition and one scorer anomaly involving identical
evidence repeated on multiple pages.

## Test stages

1. Offline exploration replays the retained exact, lexical, and vector lane
   ranks. It searches only bounded RRF constants, lexical/vector weights,
   lane depths no greater than the captured depth of 20, and three explicit
   post-fusion diversification candidates.
2. Profile selection continues to use the strict document/page answer key.
   E-032 content equivalence is reported separately and cannot make a profile
   pass.
3. The current frozen T09 profile remains a required replay baseline. Every
   finalist records improved and regressed cases; aggregate MRR cannot conceal
   a regression list.
4. Offline results cannot promote a retrieval profile. Reviewed finalists must
   be freshly remeasured through Nomic and PostgreSQL with the same 60 body and
   eight header cases. This optional retrieval work does not delay corpus-v2
   promotion.
5. Live finalist testing will also measure query embedding, lexical search,
   vector search, fusion/diversification, and total retrieval latency over
   repeated warm runs, reporting median and p95 values.
6. Only a retrieval-profile finalist with strict body MRR@20 `> 0.91`, all 60 body cases in the
   top 20, all eight header cases in the top five, all eleven header evidence
   pairs in the top 20, and reviewed per-case regressions may be proposed for
   retrieval-profile freeze. These thresholds are not corpus-v2 promotion
   criteria. Answer-generation and full API regression remain later retrieval
   gates.

## Track separation

- Primary track: qualify and promote synthetic corpus v2.
- Parallel observational track: capture optimization metrics and maintain the
  reusable search/latency harness.
- A failed or incomplete optimization experiment never blocks corpus-v2
  promotion.
- Corpus-v2 promotion does not promote any experimental retrieval profile.

## Search matrix

- RRF constant: `10`, `20`, `40`, `60`, `80`, `100`
- Lexical weight: `1`, `2`, `3`, `4`, `5`, `6`, `8`
- Vector weight: `1`, `2`, `3`, `4`, `5`, `6`, `8`
- Exact weight and priority: unchanged at `1` with deterministic exact priority
- Lexical and vector depth: `10`, `15`, `20`
- Diversification: none, first-result source-unit overlap suppression,
  document/page cap two, and document/page cap one

The matrix contains 10,584 profiles. It uses already captured lane ranks and
therefore makes no database or model call. Any finalist that changes candidate
depth beyond 20 or candidate text requires a separate fresh retrieval test and
is outside this search.

## Scorer separation

The E-032 expected sentence exists byte-for-byte on every page of the synthetic
governance manual. Treating those pages as equivalent may be correct, but that
is an evaluation-contract decision rather than a retrieval optimization. The
offline search reports its effect diagnostically while selecting finalists
against the unchanged strict page truth.
