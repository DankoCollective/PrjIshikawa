# Ishikawa extended retrieval MRR gate

Status: **FROZEN — SCRIPT 127 MEASUREMENT ACCEPTED; STRICT TARGET NOT MET**

## Purpose

Ishikawa v1.1 must pass one broader automated retrieval measurement before
promotion to the org target. This gate tests the accepted six-document
synthetic corpus without changing the accepted retrieval profile or package.

## Frozen case set

The gate contains 60 answerable retrieval questions with immutable synthetic
document/page relevance targets:

- eight questions for Synthetic Operations Control 2001;
- four questions for Synthetic Operations Control 2002, including its blank
  page and decision matrix;
- ten questions for Synthetic Schedule 2003;
- eight questions for the Synthetic TST-9001 Form;
- twenty-two questions for the Synthetic Governance Manual; and
- eight questions for the Synthetic Incident Reporting Procedure.

The checksum-bound case set is
`reference/ishikawa-extended-retrieval-mrr-cases-v1.1.json`. Every case has at
least one relevant document/page target. Questions, expected answer prose, and
human semantic judgments are not retained in the run artifact.

## Frozen metric and threshold

The only promotion metric is `MRR@20`, averaged across all 60 cases. For each
case, the first fused result matching any declared document/page target
contributes:

- rank 1: `1`;
- rank 2: `1/2`;
- rank 3: `1/3`;
- and no relevant result in the top 20: `0`.

The gate passes only when `MRR@20 > 0.91`. The comparison uses an exact
rational value rather than rounded display text, so exactly `0.91` does not
pass. Top-five and top-twenty coverage are recorded as diagnostics but do not
change the decision.

The prior 13-case tuning gate used the same `MRR@20 >= 0.85` target and
measured `0.916667`, which is the average reciprocal rank over its six
responsive retrieval cases. Its six abstention cases and one clarification
case had no relevant retrieval target and therefore were correctly excluded
from MRR.

Script `127` produced a valid 60-case observation at `MRR@20 = 0.852173`:
all 60 cases had relevant evidence within the top 20 and 56 did so within the
top five. Its first-relevant-rank distribution was 48 at rank 1, one at rank 2,
six at rank 3, and one each at ranks 5, 7, 8, 10, and 16. That observation
passed the original `0.85` threshold but does not meet the later strict
`> 0.91` target. Script `128` reclassifies the retained ranks without making
another model request.

## Execution boundary

Script `127` runs the accepted exact, PostgreSQL lexical, and pgvector cosine
lanes with frozen reciprocal-rank fusion against local read-only PostgreSQL.
It requests one Nomic embedding per question. It does not call Gemma, generate
answers, ask an operator to review answers, write the database, or change the
accepted v1.1 package.

The retained content-free observation includes case identities, question
digests, first-relevant ranks, reciprocal ranks, aggregate MRR, profile and
corpus identities, and the pass/not-met result. It excludes question text,
source text, vectors, credentials, and generated content.

Out-of-corpus, ambiguity, prompt-injection, and generation behavior remain
covered by their already-accepted API and security gates. They are not mixed
into MRR because they intentionally have no relevant document/page result.
