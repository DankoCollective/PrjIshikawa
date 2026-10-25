# Structural Chunk Candidates and Metadata

## Boundary

This stage converts an accepted normalized structural-unit artifact into
deterministic retrieval chunk candidates. It uses the Python standard library
and performs no model call, database connection, target contact, or file-name
classification.

The output is deliberately **not publishable**. Exact Nomic token measurement
and embedding are the following gate. Character or word estimates do not
stand in for the approved Nomic tokenizer.

## Candidate construction

The current candidate method starts with the smallest canonical semantic unit:

- one candidate per paragraph, definition, or list item;
- one candidate per form field or checkbox group, preserving label, value,
  option, and Boolean state;
- one table-context candidate containing the ordered headers and available
  table context; and
- one atomic candidate per table row containing every ordered header/value
  pair, the table context, and the row's own source spans.

Headings become explicit `Section:` context. They are not body chunks and are
not copied through blind overlap. Confirmed page furniture is excluded from
retrieval candidates while remaining in the accepted normalized evidence.
Adjacent table-row expansion is zero. Compatible sibling assembly and every
over-size decision are deferred until exact Nomic counts are available.

When normalization recognizes a document-control header, each body retrieval
unit receives only the header's document context/title and policy/document
identifier as compact authoritative context. Organization, department,
applicability, dates, approval, logo, footer, and other page furniture are not
repeated in body lexical or embedding text. Original body content and citation
excerpts remain unchanged. The ingestion writer stores the resulting retrieval
text, structured identity provenance, filters, token accounting, and embedding
in PostgreSQL; the running product does not use a flat-file metadata sidecar.

The v1.3 method also creates one retrieval-only representative for each
eligible document-version, parent-section, and physical-page group. A
representative contains all ordered atomic members of that group. Within a
document, only the first atomic occurrence of duplicate content remains
eligible beside representatives during ordinary non-exact retrieval. These
rules reduce rank competition between fragments and duplicates.

Representatives are scoring aids, not evidence. Each carries the identities of
its authoritative atomic members. Retrieval collapses a fused result to one
candidate per structural group and expands selected representatives back to
those ordered atoms before hydration, relevance measurement, citation, or
Gemma input. Exact-reference routes continue to use atomic chunks.

The frozen retrieval-gap amendment adds one derived candidate for every page
that the accepted extraction inventory explicitly verifies as blank. Its
projection kind is `page_status`, its statement is limited to the absence of
extractable text, and its citation anchor spans that page. It is not a claim
about visual content and does not invent text. A nonblank page never receives
this derived candidate.

## Metadata and identity

Every candidate carries:

- deterministic document, document-version, method-profile, chunk, content,
  context, and retrieval-text identities;
- projection kind and ordered source structural-unit identities;
- explicit content text, context text, and the resulting retrieval text;
- page range, structural path, source spans, and kind-specific citation
  anchors;
- exact lexical fields for references, labels, numbers, and checkbox states;
- previous/next document-local chunk links plus reserved continuation fields;
- parent heading or table identity when applicable; and
- separate token-accounting fields for content, context, prefix, and total.

Retrieval representatives additionally carry a structural retrieval-group
identity, ordered atomic component identities, an explicit scoring-only flag,
and the document-local canonicalization state. Atomic chunks carry the same
group identity so fusion can collapse the group deterministically.

Original filenames are excluded from this candidate surface. They remain
server-only provenance in earlier protected artifacts. Candidate text never
contains an internal source path.

The v1.3 method profile identity is:

```text
d72a07f81eabc1f521ab1fd54f84289979365c6c71f8e3220a53b1e8c9a1c037
```

Changing a boundary, context, table, form, overlap, or projection rule changes
that method profile and requires regeneration and retrieval requalification.

## Fail-closed token boundary

Every candidate currently records:

```text
token status: pending_authoritative_nomic_measurement
publication eligible: false
publication blocker: nomic_token_measurement_pending
```

The embedding stage must use the exact approved tokenizer and revision to measure the
canonical content, added context, document prefix, and complete submitted
input. It must enforce the proven input ceiling and deterministic over-size
rules before any candidate can become eligible for embedding or publication.

## Qualified synthetic expectations

The original accepted six-document fixture remains a regression input. Under
the v1.3 chunk method it deterministically produces 154 total candidates: 126
authoritative atomic candidates and 28 retrieval-only representatives.

The promoted synthetic corpus v2 normalized input deterministically produces:

```text
chunk_candidates=168
authoritative_atomic_candidates=139
section_page_representatives=29
document_control_metadata=6
paragraphs=48
list_items=60
definitions=5
table_contexts=1
table_rows=3
form_fields=12
checkbox_groups=4
body_overlap_units=0
chunk_candidate_set_digest=ceac33ebca6ca890a78ac53aa112bc8e9780e5252c7fe172b0e8182d848c9f42
```

The regression suite covers deterministic replay, exact input identity,
candidate inventory, semantic-unit coverage, zero blind overlap,
heading/furniture behavior, atomic tables and forms, sequence links, unique
identities, citation anchors, filename exclusion, document-control metadata,
representative membership and boundaries, duplicate canonicalization, and
fail-closed token/publication state. Candidate construction alone remains
non-publishable until exact token measurement and embedding complete.
