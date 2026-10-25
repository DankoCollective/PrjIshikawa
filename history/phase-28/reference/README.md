# Phase 28 Apisachi Tokuli References

`native-postgresql-advisory-review-v1.tsv` is the exact Ubuntu 24.04 AMD64
pre-download advisory decision set for the reviewed native PostgreSQL
replacement bundle. It covers all six selected source/version coordinates,
including the scoped AMD64 non-applicability decision for the Arm Cortex-M
LLVM finding and the fixed pgvector `0.8.7` coordinate. Any source, version,
OS, or architecture change requires a new reviewed decision set.

`native-postgresql-advisory-review-v2.tsv` supersedes version 1 for the
compatible PostgreSQL/JIT capture. It covers seven exact source/version/origin
coordinates: retained Ubuntu client and support packages, PGDG PostgreSQL
server `16.15`, PGDG pgvector `0.8.7`, native Psycopg 3, and Ubuntu
`libllvm19`. Its LLVM acceptance is explicitly scoped to the AMD64 PostgreSQL
JIT runtime and does not claim that the source has no advisories.

`generate_synthetic_corpus_v3.py` creates the separate 30-document,
150-page fictional v3 fixture. It preserves the six v2 document identities as
semantic anchors, adds 24 documents across eleven departments, applies the v2
first-page masthead, and adds the accepted repeated-footer geometry to every
page. It produces evaluation truth and explicit-reference relationships but
never reads source-corpus content or mutates corpus v1 or v2.

`generate_synthetic_corpus_v3_retrieval_truth.py` derives an evaluation-only
MRR fixture from the checksum-bound v3 design truth. It creates 180 unique
questions: 120 body cases covering pages 1 through 4 of every document, 30
relationship/reference cases covering page 5, and 30 document-control header
cases. The fixture covers all 150 document/page pairs. It is excluded from
corpus ingestion and generation context and is not a black-corpus artifact.
