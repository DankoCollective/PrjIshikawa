# Frozen Pipeline-Writer Contract

## Status

The operator froze this contract on 2026-10-19 after Script `31` passed on
EmceeDanko. It is an implementation contract under the already-frozen `G09`
and `G11` decisions; it does not create another decision item.

Accepted evidence:

- PostgreSQL schema version: `3`;
- migration `0003_separate_special_token_count` SHA-256:
  `5e833d8ff556c0e6158daf0419b1013235a11e1a94f1f560206ba813e1fc3761`;
- Script `31` receipt SHA-256:
  `1c7a96b411746528ae0babb2bb83352f1873c2275a160f61af0ed59767fda9de`;
- accepted synthetic projection: 6 documents, 230 structural units, 125
  chunks, 125 citations, and 125 embeddings; and
- accepted embedding-space identity:
  `fd970d304662357a07f7712639bdc0c70cc7e72b22f04c126acce57a6f9143a3`.

## Boundary

The writer accepts only validated class-registry, document-catalog, ingestion-
manifest, plan, and prepared-document objects. Prepared documents contain
already-extracted, already-normalized, already-chunked, already-token-measured,
and already-embedded data. The writer never extracts PDFs, creates chunks,
calls Nomic, calls Gemma, or performs retrieval.

The ingestion manifest identifies the affected documents. The writer does not
reprocess the full corpus. An unchanged document is reused without extraction,
chunking, embedding, or database replacement.

## Publication

All changes from one accepted ingestion manifest are published in one
PostgreSQL transaction. Validation or write failure makes none of that batch
searchable. Publication changes only affected active-document pointers while
preserving immutable document-version and artifact identities.

The writer supports the frozen add, reuse, revise, reprocess, quarantine,
remediation, rollback, retirement, and active-projection behaviors. Script
`24` proved their target-native database lifecycle. Script `31` repeated the
real producer-artifact add and reuse path after schema version 3 corrected the
token-accounting representation.

## Token and embedding invariants

Each chunk stores four separate exact Nomic token counts:

- `content_token_count`;
- `context_token_count`;
- `prefix_token_count`; and
- `special_token_count`.

`total_embedding_token_count` must equal the sum of all four. The component
counts exclude tokenizer-added special tokens; the special-token column owns
those tokens explicitly. The authoritative total includes them.

Every persisted vector must match the recorded active embedding-space
identity and contain exactly 768 finite values. The writer stores the exact
submitted-input digest and does not transform the returned vector.

## Retrieval and authority boundary

Retrieval reads only active `rag_search` views through the read-only
`rag_retrieval` role. It cannot write base catalog tables, ingest documents,
publish batches, or change active-document pointers. Nomic and Gemma receive
no PostgreSQL or document-store access.

## Remaining qualification

The writer contract is frozen and accepted. The operator-ingestion control
plane is implemented and locally qualified in Script `76`; its concrete native
producer and PostgreSQL deployment adapters are not yet integrated. Remaining
work also includes interruption recovery, backup and restore, the consolidated
fresh-install schema, portable installation, and org-lab qualification. Those
items may reveal an implementation defect, but they are not reasons to
silently change this contract.
