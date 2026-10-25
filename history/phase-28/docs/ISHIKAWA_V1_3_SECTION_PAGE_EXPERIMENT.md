# Ishikawa v1.3 Section/Page Candidate Experiment

## Status

This document specifies one bounded, synthetic-only retrieval experiment. It
does not change the published synthetic corpus v2, the production corpus, the
accepted retrieval profile, the evaluation truth, or an Ishikawa package.

## Evidence

The accepted published atomic baseline is body MRR@20 `0.873056`, with 58 of
60 cases in the top five and all 60 in the top twenty. Header MRR is
`1.000000`, all eight header cases are in the top five, and all 11 required
header evidence pairs are in the top twenty.

Script 170 searched 10,584 bounded RRF, lane-weight, lane-depth, and
post-fusion-diversification profiles. No profile exceeded the strict `0.91`
body MRR target. Its best observation reached `0.882103`, improved three body
cases, and regressed two.

Script 171 found 12 body cases below rank one. Nine contain at least one
higher-ranked result from the correct document but wrong page. Seven contain
at least one higher-ranked result from another document. Lexical retrieval
leads four cases, vector retrieval leads six, and two are tied. The exact lane
is not relevant in these 12 ordinary body questions.

## Fixed Controls

The experiment must preserve:

- exact lane depth `1`;
- lexical lane depth `20`;
- vector lane depth `20`;
- fused depth `20`;
- RRF constant `60`;
- lane weights exact `1`, lexical `1`, and vector `4`;
- no learned reranker;
- existing explicit-title, identifier, page, header, and department routing;
- the 60-case corpus-v2 body truth and eight-case header truth unchanged.

No result from this experiment is a production-profile promotion.

## Derived Retrieval Units

The experiment may derive one `section_page_representative` for each unique
active `(document version, parent structural unit, physical page)` group.
Only non-metadata atomic candidates with a parent structural unit participate.
The representative contains the section heading once followed by member text
in stable source order. It retains all member source-unit identities and the
single physical page. It is used only for retrieval scoring; accepted atomic
records remain the authoritative evidence and citation units.

The current candidate contains 29 eligible section/page groups covering 123
of 133 non-metadata atomic candidates. The remaining ten unparented atoms stay
available as atomic candidates. Therefore, the experiment can add no more than
29 derived representatives and can expose no more than 168 retrieval
candidates before result collapse.

Every derived representative must pass exact Nomic tokenization and the
existing embedding ceiling. A representative that exceeds the ceiling blocks
the experiment; it is not silently truncated or split.

## Duplicate Canonicalization

Within one document version, atomic candidates with the same content digest
form one duplicate-evidence group. Ranking selects the earliest source-order
occurrence as the canonical representative. Every occurrence remains mapped
for provenance, reconstruction, and citation; no stored atom is deleted or
rewritten.

The accepted candidate contains three duplicate-evidence groups, 24 member
occurrences, and 21 repeated occurrences beyond the canonical copies. This
step specifically tests query-independent suppression of repeated boilerplate
without using evaluation answers as retrieval hints.

## Four Frozen Variants

The next measurement must compare exactly four variants:

1. `atomic_baseline`: the accepted published atomic representation.
2. `atomic_duplicate_canonical`: baseline plus document-local duplicate
   canonicalization.
3. `section_page`: atomic candidates plus the bounded section/page
   representatives.
4. `section_page_duplicate_canonical`: section/page representatives plus
   document-local duplicate canonicalization.

For section/page variants, fusion first uses the frozen profile. Results then
collapse by `(document version, parent structural unit, physical page)`,
retaining the highest fused score and deterministic identity tie-break. A
selected representative expands back to its ordered atomic members before
evidence authorization, reconstruction, citation validation, or generation.
Metadata candidates and explicit exact routes do not enter this body-result
collapse.

## Measurement and Acceptance

The next execution must use fresh Nomic embeddings for derived
representatives and fresh PostgreSQL lexical ranking in a private disposable
cluster. Gemma is not called. It must capture candidate counts, exact token
counts, per-lane ranks, fused ranks, per-case deltas, MRR@20, top-five and
top-twenty coverage, duplicate suppression counts, and warm latency
distributions for each variant.

The accepted atomic baseline must replay exactly before any variant is
interpreted. A variant is eligible for later review only when:

- body MRR@20 is strictly greater than `0.91`;
- all 60 body cases contain required evidence in the top twenty;
- header MRR remains `1.000000`;
- all eight header cases remain in the top five;
- all 11 header evidence pairs remain in the top twenty; and
- candidate construction, ranking, and result collapse are deterministic.

Top-five coverage, all rank regressions, candidate growth, Nomic token cost,
and warm latency are mandatory diagnostics. They are not additional pass
criteria. An eligible observation still requires a separate review and freeze
before any source, database, package, or production profile changes.

## Prohibited Actions

The experiment must not access the black corpus, mutate either PostgreSQL
corpus, modify either truth file, call Gemma, change the frozen retrieval
profile, install a service, alter autostart, rebuild a deployment package, or
promote a candidate automatically.
