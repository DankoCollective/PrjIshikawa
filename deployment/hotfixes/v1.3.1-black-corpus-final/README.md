# Ishikawa v1.3.1 cumulative update

This directory builds and tests the single cumulative update accepted for the
Tech demonstration. It supersedes every earlier v1.3.1 Poppler, header, and
footer archive. Do not carry those earlier archives.

The final archive corrects the complete installed ingestion boundary exposed
by real-document ingestion evidence:

- Poppler package-set qualification and bounded extraction archives;
- policy header and footer fallback without deleting unrelated body prose;
- recurring `Page N of M` furniture normalization;
- a two-hour upper bound for a changed-document batch;
- credential transport without a product-imposed strength rule;
- safe propagation of the actual failed ingestion stage.

The update does not alter source PDFs, corpus metadata, PostgreSQL state,
retrieval ranking, model endpoints, service configuration, or credentials.

`build-final-update.sh` first runs the complete application suite and the
update lifecycle harness. Only then does it write one archive and adjacent
checksum beneath `local/artifacts/ishikawa-v1.3.1-cumulative-update-current/`.

The operator command is printed only by a successful build report. The update
is idempotent and accepts either pristine v1.3.1 or the earlier cumulative
three-file compatibility update already applied on Tech.
