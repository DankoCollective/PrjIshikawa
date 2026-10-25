# Ishikawa v1.3 Retrieval Profile

## Status

The accepted v1 and v1.2 releases remain preserved by their immutable
deployment packages. Operator decision `V13-47` promotes the qualified
score-calibrated retrieval candidate into the v1.3 application. Its unchanged
30-document corpus-v3 measurement produced body `MRR@20 = 0.895450`, body
coverage `120/120`, body top-five recall `117/120`, relationship and header
coverage `30/30` each, and header `MRR@20 = 1.000000`.

This is an implementation freeze, not release acceptance. Complete native and
web regression, implemented-source qualification, the complete Retrieval
API/Gemma gate, and a separately assembled deployment candidate remain
required.

The relevant identities are deliberately separate:

- frozen experimental candidate:
  `bf732e402004d70b0aa3318e179fe1a1e14d0bd4a70aaa2b4d71528088b7d518`;
- chunk-method profile:
  `d72a07f81eabc1f521ab1fd54f84289979365c6c71f8e3220a53b1e8c9a1c037`;
- v1.3 retrieval profile:
  `7c8f8f37ccce47cde1bdbb6cb43b321be14e54a11c8435e845ab7508c3dc8edb`.

The experimental identity binds the measured behavior and lane parameters.
The chunk-method identity describes candidate construction. The retrieval
profile identity describes how those candidates are searched, collapsed,
expanded, and fused. These identities must not be substituted for one another.

## Frozen settings

The authoritative human-maintainable representation is
`config/templates/method_profile.yaml`. The frozen settings are:

- resolve an unambiguous document identifier plus explicit page number through
  the exact lane;
- retain only the best exact candidate;
- use native PostgreSQL `english` full-text search;
- retain at most 20 lexical candidates;
- run the strict lexical query first, then use native PostgreSQL OR search only
  when strict search returns no candidates;
- use pgvector cosine distance and retain at most 20 vector candidates;
- fuse candidate identities with reciprocal-rank fusion;
- weight exact, lexical, and vector RRF contributions `1`, `2`, and `4`;
- use RRF constant 60 and retain at most 20 fused structural groups;
- use no learned reranker;
- allow retrieval-only section/page representatives for ordinary non-exact
  retrieval;
- retain only the first document-local atomic occurrence of duplicate content
  in that representation route; and
- expand each selected representative to its ordered authoritative atomic
  members before hydration, relevance measurement, citation, or Gemma input;
- for ordinary corpus-wide body questions only, split at most four literal
  clauses without adding terms and form a balanced top-five-per-lane document
  union;
- rerun the existing lexical and vector lanes inside that bounded union and
  form the complete-coverage pool with weights `2/1/1`; and
- rerank the top 20 with the frozen normalized raw-score configuration
  `raw_l1_v3_fc1_d1_h010`.

Under V13-39, every body retrieval unit produced from a recognized control
header also carries two compact authoritative context lines: the document
context/title and policy/document identifier. Those lines participate in
PostgreSQL lexical search and Nomic embeddings but never replace source prose
or become a citation excerpt. The complete header and footer remain excluded.
The canonical ingestion writer persists the retrieval text and its structured
identity provenance in `rag.chunks`; there is no runtime flat-file index.

Exact-reference routing continues to use authoritative atomic chunks. A
representative can influence rank, but it cannot become evidence or a
citation. Chunk boundaries, representative identities, and duplicate
canonicalization remain internal to retrieval.

The calibrated route uses structural paths exposed by the PostgreSQL retrieval
view. Paths influence ranking only. They are not shown as invented prose,
added to authoritative citations, or supplied to Gemma independently of the
selected source evidence. There is no runtime flat-file search index.

The application validates exact fields, types, ranges, supported algorithms,
and the referenced chunk-method identity. Canonical JSON plus a
domain-separated SHA-256 digest creates the retrieval-profile identity.
Secrets, endpoints, paths, and deployment-specific values do not belong in
this file.

## PostgreSQL lexical terms

The phrase `significant terms` means the lexemes PostgreSQL retains under its
`english` text-search configuration. It does not mean that Gemma, the operator,
or Ishikawa maintains a subjective important-word list.

PostgreSQL performs several deterministic steps:

1. Parse the query into word-like tokens.
2. Normalize case and punctuation according to its text-search parser.
3. Remove configured English stop words.
4. Apply the English dictionary stemmer, which may reduce grammatical forms
   to a shared internal lexeme.

For an ordinary query without an explicit web-search operator,
`websearch_to_tsquery` combines retained lexemes with `AND`. If strict search
returns no rows, Ishikawa extracts the same PostgreSQL-normalized lexemes and
combines them with `OR`. Every lexical candidate records either `strict` or
`or_fallback` provenance.

## Change consequences

A candidate depth, lexical behavior, distance, fusion, weighting, RRF,
representation, canonicalization, expansion, or reranker change creates a new
retrieval-profile identity and requires held-out retrieval requalification.

A chunk-construction change creates a new chunk-method identity and requires
affected candidates to be regenerated. When embedded input changes, those
candidates must also be remeasured and re-embedded before retrieval is
requalified.
