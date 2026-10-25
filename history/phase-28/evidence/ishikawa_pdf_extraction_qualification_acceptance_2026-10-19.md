# Ishikawa PDF Extraction Qualification Acceptance

## Accepted result

Script `25` PDF extraction qualification is accepted. The accepted result is
composed from the operator-executed target-capture receipt and a local
held-out evaluation of that exact retained, checksum-verified synthetic
archive. The target was not rerun during local recovery.

Target receipt:

```text
local/reports/ishikawa-pdf-extraction-qualification/pdf_extraction_qualification_20261019T212440Z_xvlGSE.txt
sha256=b5725ccb83f8492b855280974598e49b3a33639d0c3fd8320ef4b23092644186
bytes=2460
```

Retained synthetic observation archive:

```text
local/artifacts/ishikawa/pdf-extraction-qualification/pdf_extraction_observations_20261019T212440Z.tar
sha256=072bff5e6d791fd1399f52dde8da8e3be1d53c30d4d7510d6de00ae01e3f6067
bytes=604160
```

Local acceptance receipt:

```text
local/reports/ishikawa-pdf-extraction-qualification/pdf_extraction_local_acceptance_20261019T212922Z.txt
sha256=9ba0e112df80b0b56b49fbb068ef75eb03a3f5fd9949c0d3dace4c6f32a34eb5
bytes=1190
```

## Proven target facts

The operator-executed capture proves:

- EmceeDanko, Ubuntu `24.04`, and `amd64`;
- `poppler-utils 24.02.0-1ubuntu9.10`, `pdfinfo 24.02.0`, and
  `pdftotext 24.02.0`;
- six exact synthetic source PDFs and 27 pages;
- one intentional blank page;
- two identical extractions of every document;
- zero document failures;
- a checksum-matching returned archive; and
- complete target-temporary-file and SSH-master cleanup.

No package, database, service, model, organizational-content, or secret
operation occurred.

## Held-out acceptance

The corrected local evaluator accepted the retained archive with:

```text
source_documents=6;source_pages=27;intentional_blank_pages=1
token_oracle_pages=27;layout_token_mismatch_pages=0;bbox_token_mismatch_pages=0
heading_checks=27;ordered_phrase_checks=40;repeated_furniture_page_checks=16
table_row_checks=4;table_cell_checks=16
form_field_pair_checks=8;checkbox_checks=10
pdf_extraction_evaluation=pass
```

The accepted evaluator and corrected detailed truth identities are:

```text
94e6f259f3fca252a97a9633a06b3e4563ad4b04813b109c389bdc97c92ea5c6  evaluate_pdf_extraction.py
f83fd0bc8e0a25cd6bad35c5377b72a921205e7dd50565641fb58b229c635b1b  extraction_acceptance_truth.json
```

The truth correction added the two commas present in every source page to
the ordered sentence prefixes `document ID,` and `metadata is absent,`. The
evaluator correction makes repeated table-cell text resolve in table order
instead of selecting an earlier same-word occurrence elsewhere on the page.
Neither correction changes or weakens the exact page-token oracle.

## Wrapper correction

The operator run retained the archive but ended before local grading because
`install -m 0600` could not complete its mode operation on the Windows-mounted
repository. The canonical same-numbered wrapper now copies the fully synthetic
artifact, verifies its checksum after the copy, and treats Unix mode setting
as best effort for that synthetic-only local output. Its no-contact source
gate passes with:

```text
25308baf54f605799961811e9a9c57e686a91bb92c77a5f0b5bbcc65790161d6  25_qualify_pdf_extraction_on_emceedanko.sh
989b1779ca71cdfa6bad915c12f33337693ddd75335c9920ef1427d8d51132d7  capture-pdf-extraction-observations.py
94e6f259f3fca252a97a9633a06b3e4563ad4b04813b109c389bdc97c92ea5c6  evaluate_pdf_extraction.py
```

Do not rerun Script `25` in the normal workflow. PDF extraction is accepted.
The next gate is normalization and structural-unit creation from the accepted
synthetic Poppler artifact.
