# Relevance Calibration Contract

## Purpose

The relevance profile prevents Ishikawa from treating the nearest available
vector as proof that the corpus answers a question. Calibration uses protected,
fully synthetic questions with known outcomes. It does not use Gemma confidence
and it does not change the frozen three-lane retrieval profile.

## Case boundaries

The first calibration set contains:

- six responsive questions already backed by the accepted held-out citation
  truth;
- three professional questions whose subjects are absent from the corpus; and
- three professional near-domain questions that reuse corpus language while
  asking for facts the corpus does not contain.

The existing cafeteria question is an out-of-scope case. The scope gate must
reject it before retrieval, so it is explicitly excluded from relevance
calibration. A scope rejection cannot be counted as proof that the relevance
gate works.

Responsive questions must exactly match the accepted held-out question and
citation truth. Nonresponsive cases have no required citation because no
corpus passage is authoritative for the requested fact. Their declared absence
terms are checked against the checksum-bound synthetic chunk set as a guard
against accidentally creating an obvious positive case.

## Calibration sequence

1. Qualify the protected case inventory and retain only content-free case
   digests in the qualification evidence.
2. Obtain Nomic embeddings for all twelve questions using the accepted query
   embedding contract. Submit exactly one question per embedding request,
   matching the live retrieval path, and compare a repeated singleton request
   against the existing `0.00001` numeric tolerance.
3. Run the frozen exact, lexical, vector, and RRF retrieval method against a
   disposable copy of the synthetic corpus database.
4. Compare responsive and nonresponsive retrieval signals locally.
5. Accept a simple deterministic rule only if it separates every mandatory
   case. Otherwise, add evidence or revise the method explicitly; do not choose
   a threshold that hides a failed case.
6. Freeze the resulting versioned relevance-profile identity and connect it to
   the evidence-sufficiency gate.

Script `55` performs only step 1. It makes no model call, network connection,
or database connection and does not choose a threshold.

Script `56` completed step 2 with twelve singleton requests and accepted the
checksum-bound 768-dimensional query vectors. Script `57` is the step-3
measurement gate. It transfers only synthetic questions and a stripped vector
payload to EmceeDanko; responsive/nonresponsive labels, required citations,
absence terms, and threshold logic remain local. The target helper:

- starts the existing boot-disabled PostgreSQL cluster;
- verifies the accepted empty application database without changing it;
- creates a disposable database with the accepted schema;
- loads the six-document synthetic corpus;
- runs exact, PostgreSQL lexical, pgvector cosine, and deterministic RRF
  retrieval with the frozen depths and settings;
- exports retrieval observations without calibration truth;
- drops the disposable database; and
- restores PostgreSQL to its stopped, disabled state.

The local evaluator then joins those observations to protected truth and
reports signal ranges and responsive citation coverage. Script `57` does not
select a relevance threshold, call Gemma or Nomic, publish a profile, or make
the accepted application database searchable. Its next gate is an explicit
review of signal separation.

The first Script `57` execution blocked before creating a disposable database
because its reused target helper still expected the former schema-v3 accepted
database ledger. The accepted database had already advanced to schema version
4 through Script `41`; the block therefore demonstrated a stale preflight, not
a database defect. Cleanup passed and PostgreSQL was stopped. Script `58`
binds that exact blocked receipt, requires the accepted migration `0004`
evidence, validates the accepted database at schema version 5, applies
migrations `0001` through `0004` only to the disposable database, and reruns
the otherwise unchanged Script `57` measurement. It accepts the result only
after verifying disposable-database removal and accepted-database non-mutation.

The first Script `58` execution passed the schema-v4 preflight and created the
disposable database, then blocked when the staged application package omitted
the now-required `method_profile.py` and `relationships.py` modules. Its
cleanup dropped the disposable database and stopped PostgreSQL. Script `58`
was repaired in place: its checksum-bound payload now carries all fifteen
required application modules, and local validation imports the staged
`persistence` and `retrieval` modules before any target contact. This retains
one correction gate instead of creating a chain of repair scripts.

The repaired Script `58` passed. It covered all 13 required responsive
citations, removed the disposable database, preserved the accepted database,
and restored PostgreSQL to stopped and disabled. The observation did not
justify a scalar threshold:

- responsive top-vector scores ranged from `0.706557508` to `0.802199967`;
- nonresponsive top-vector scores ranged from `0.558219569` to `0.742288472`;
- responsive top-fused scores ranged from `0.032018443` to `0.049180328`; and
- nonresponsive top-fused scores ranged from `0.016393443` to `0.032786885`.

Both score families overlap. The near-domain question about renewing a
permanent controlled-access exception retrieved genuinely related temporary-
exception passages. This demonstrates that retrieval similarity measures
topic proximity, not whether the corpus contains the requested answer. No
relevance profile is published from these scores alone.

## Frozen lexeme-support measurement

Raw vector and fused scores are not an accepted sufficiency threshold. The
next bounded measurement preserves the calibrated retrieval profile exactly:
exact lookup, PostgreSQL lexical retrieval, pgvector cosine retrieval, their
candidate depths, and RRF ranking do not change.

For each of the same twelve protected cases, PostgreSQL's native `english`
text-search configuration derives the normalized question lexemes. The
measurement compares those lexemes with the union of the already-stored
English lexical vectors for fused evidence at cumulative depths `1`, `3`,
`5`, `10`, and `20`. It records the supported and unsupported question
lexemes and their counts in the protected observation artifact. This uses the
same native lexical representation that already backs retrieval; it does not
add a parser, model, lane, reranker, or database migration.

Script `59` measures and reports those ranges locally against the protected
responsive/nonresponsive labels. It does not select or publish a threshold.
Gemma does not participate in the measurement and has no authority over the
sufficiency outcome. A later gate may freeze a deterministic rule only if the
evidence separates all mandatory cases; otherwise the correct result remains
`insufficient-evidence` pending a separately reviewed method change.

The operator-executed Script `59` passed operationally. It removed the
disposable database, preserved the accepted database, restored PostgreSQL to
stopped and disabled, and selected no threshold. Lexeme-support ranges did not
strictly separate at any tested fused depth:

- depth 1: responsive minimum `0.375000`, nonresponsive maximum `0.375000`;
- depth 3: responsive minimum `0.500000`, nonresponsive maximum `0.500000`;
- depth 5: responsive minimum `0.500000`, nonresponsive maximum `0.500000`;
- depth 10: responsive minimum `0.500000`, nonresponsive maximum `0.500000`;
  and
- depth 20: responsive minimum `0.500000`, nonresponsive maximum `0.625000`.

Therefore retrieval-text lexeme coverage is rejected as a standalone
sufficiency threshold. The observation also shows why: citable identity
context such as document display name, assigned class, and citation location
is outside the stored chunk lexical vector, while near-domain absent questions
can still share many words with related chunks. Any follow-on measurement must
be reviewed explicitly and may not silently reinterpret this failed result.

## Frozen citable-evidence correction

The bounded follow-on preserves the exact, lexical, vector, and RRF retrieval
lanes and their ranks. It expands only the measured support envelope to the
fields a returned citation can legitimately present:

- chunk retrieval text;
- document display name;
- assigned document class;
- citation structural path; and
- citation page number or range.

PostgreSQL's same native `english` configuration measures cumulative support
at fused depths `1`, `3`, `5`, `10`, and `20`. The prior retrieval-text-only
measurement remains in the protected observation, and each citable-envelope
support set must be a superset of it. Exact-reference routing is unchanged.
No private path, source filename, raw-score reinterpretation, new retrieval
lane, reranker, model decision, or database migration is introduced.

Script `60` reruns the same twelve cases and reports every range. A rule is
eligible for later review only if at least one fixed depth strictly separates
all six responsive cases from all six nonresponsive cases. The script does not
choose a threshold or publish the rule, even if separation is observed. Gemma
remains outside the authoritative sufficiency decision.

The operator-executed Script `60` passed operationally, removed its disposable
database, preserved the accepted database, and restored PostgreSQL to stopped
and disabled. The measured responsive minimum and nonresponsive maximum were:

- depth 1: `0.500000` and `0.375000`;
- depth 3: `0.600000` and `0.500000`;
- depth 5: `0.600000` and `0.500000`;
- depth 10: `0.600000` and `0.500000`; and
- depth 20: `0.600000` and `0.625000`.

Depths 1, 3, 5, and 10 therefore strictly separated this protected set. Depth
20 did not, demonstrating that additional lower-ranked evidence can introduce
unrelated term support. Script `60` correctly left the candidate unpublished
and selected no threshold. Choosing a fixed depth and exact comparison remains
an explicit freeze decision.

## Frozen runtime relevance profile

The operator froze the smallest multi-passage candidate that separated the
protected set: the first three results in final fused-rank order. Here,
`depth` means the count of ranked fused chunks whose citable fields contribute
to the support measurement. Depth `3` therefore measures ranks 1 through 3;
it does not rerun retrieval, change RRF, truncate reconstruction, or limit the
number of passages that may later be cited.

For each question, PostgreSQL's native `english` text-search configuration
derives normalized question lexemes and the union of lexemes in these five
citable fields for the top three fused chunks:

- chunk retrieval text;
- document display name;
- assigned class;
- citation structural path; and
- citation page number or range.

The deterministic application rule is:

```text
qualified when supported_count * 5 >= question_lexeme_count * 3
otherwise insufficient
```

This is an exact integer comparison for at least 60-percent support; no
floating-point threshold is used. The separately versioned relevance profile
owns depth `3`, the five citable fields, PostgreSQL `english`, and the `3/5`
boundary. The relevance decision is the only runtime input for relevance in
the evidence-sufficiency gate. Exact-reference constraints and every other
sufficiency check remain mandatory. Retrieval ranking is unchanged and Gemma
has no authority over this decision.

Script `61` is the local freeze gate. It binds the accepted Script `60`
receipt and observation, replays all twelve protected cases through the
runtime rule, and requires all six responsive cases to qualify and all six
nonresponsive cases to remain insufficient. It does not contact a target,
PostgreSQL, Nomic, or Gemma.

## Frozen query request cardinality

Script `56` originally exposed that the deployed Nomic runtime can produce a
small component-level difference when the same question is submitted alone
versus within a multi-question batch. Live Ishikawa retrieval embeds one user
question at a time. The frozen KISS correction therefore:

- submits each calibration question as a singleton request;
- repeats the first singleton under the unchanged `0.00001` determinism
  tolerance;
- records `embedding_request_batch_size: 1` in the protected embedding
  artifact; and
- does not weaken the tolerance or treat cross-batch equality as a runtime
  requirement.

This changes neither the model, tokenizer, prefix, vector dimension, stored
vector transform, cosine distance, database schema, nor retrieval profile.
