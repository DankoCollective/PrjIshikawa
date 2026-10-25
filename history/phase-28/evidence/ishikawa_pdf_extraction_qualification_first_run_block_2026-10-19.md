# Ishikawa PDF Extraction Qualification First-Run Block

## Result

The first operator-executed Script `25` run completed its remote work safely
but did **not** accept PDF extraction. The durable content-free receipt is:

```text
local/reports/ishikawa-pdf-extraction-qualification/pdf_extraction_qualification_20261019T212118Z_BRpq2y.txt
sha256=056b6bb13bf1bf47a30959442f34df03b85dc7ef888415be895782cb3de73323
bytes=3037
```

The exact executed source identities were:

```text
script_sha256=45d860ac332abe0ec2039fbea3911b88cbcf6257e0523a02ea01a171073ca08e
capture_sha256=989b1779ca71cdfa6bad915c12f33337693ddd75335c9920ef1427d8d51132d7
evaluator_sha256=ba03a7d6eaa932c78e146050eb41fb9a66c1bc9525e1aad33d270687b9e8c658
```

## Proven facts

The run proved:

- target identity `EmceeDanko`, Ubuntu `24.04`, and `amd64`;
- exact `poppler-utils 24.02.0-1ubuntu9.10`, `pdfinfo 24.02.0`, and
  `pdftotext 24.02.0`;
- checksum verification of the neutral payload and all six synthetic PDFs;
- capture of six documents and 27 pages with the one expected blank page;
- successful repeat extraction with zero document failures;
- returned archive identity
  `dc6f928f68e2859d0d5f26c027d2c6a5cc26f6243db4b4fdfdfdfccee2f4e2de`
  and size `604160` bytes; and
- complete target temporary-file and SSH-master cleanup.

The local held-out evaluator then returned:

```text
pdf_extraction_evaluation=blocked;reason=bbox_token_or_order_mismatch
```

Therefore `G01` and `G03` remain unaccepted. No normalization, chunking,
embedding, ingestion, database, service, package, or organizational-content
mutation occurred.

## Wrapper and evaluator defect

The executed wrapper removed its local work directory after the held-out
block and had not yet persisted the checksum-verified synthetic archive. The
target cleanup also correctly removed its temporary copy. That behavior left
the content-free reason but discarded the detailed evidence needed to
distinguish an extraction discrepancy from an evaluator-ordering discrepancy.
This was a wrapper defect.

Source review also found that the original evaluator flattened bounding-box
words in XHTML serialization order and treated that serialization as reading
order. The frozen requirement is physical reading order derived from line and
coordinate geometry. The observed block alone does not prove which order was
responsible because the first-run archive was not retained.

The canonical same-numbered Script `25` is corrected to:

- canonicalize bounding-box lines by physical top-to-bottom and same-row
  left-to-right coordinates before token/order comparison;
- retain the checksum-verified synthetic archive and checksum **before**
  held-out evaluation;
- write a protected local mismatch diagnostic containing the synthetic
  document, page, mismatch index, counts, and bounded token previews; and
- keep only the diagnostic identity and size in the content-free report.

The corrected no-contact source gate passes with:

```text
script_sha256=05aac9312837c55348c426293bbb4accd234af99e821d6b12aecd80e2245b7cd
capture_sha256=989b1779ca71cdfa6bad915c12f33337693ddd75335c9920ef1427d8d51132d7
evaluator_sha256=91c47082693a3c773c8944ad26d3d6d81a8193f4a927b2c87d5d6f427909da51
pdf_extraction_qualification_source=pass
target_contact=false;source_documents=6;source_pages=27;held_out_truth_transferred=false
```

Because the first-run archive no longer exists, one same-script rerun is
required. Any future held-out block will retain enough protected local
evidence for diagnosis without another remote capture.

## Corrected rerun command

From the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/25_qualify_pdf_extraction_on_emceedanko.sh --run
```
