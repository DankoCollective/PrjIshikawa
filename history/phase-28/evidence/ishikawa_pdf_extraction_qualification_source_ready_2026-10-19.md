# Ishikawa PDF Extraction Qualification Source Ready

> Historical source-ready record. The operator capture and corrected local
> held-out evaluation are accepted in
> `ishikawa_pdf_extraction_qualification_acceptance_2026-10-19.md`.

## Status

Script `25` and its PDF extraction qualification payload were source-ready.
Local validation passed without contacting EmceeDanko. The first target
capture passed but its held-out evaluation blocked, so corrected end-to-end
acceptance was still pending at this historical checkpoint.

This is the first producer-pipeline gate after the accepted incremental writer.
It implements the frozen `G01` source-verification contract and the `G03`
Poppler-first qualification plan; it does not yet implement normalization,
structural units, chunking, embedding, or database writes.

## Bound inputs

The gate binds:

- the six immutable Synthetic Corpus V1 PDFs and their exact file identities;
- the original synthetic corpus manifest and high-level ground truth;
- a separate local held-out extraction profile for headings, ordered material,
  table cells, form label/value pairs, checkbox states, repeated furniture,
  page inventory, and the intentional blank page;
- the accepted EmceeDanko inventory proving Ubuntu `24.04`, `amd64`,
  `poppler-utils 24.02.0-1ubuntu9.10`, and Poppler tools `24.02.0`; and
- the exact target capture and local evaluator sources.

Exact source identities at source-ready validation were:

```text
05aac9312837c55348c426293bbb4accd234af99e821d6b12aecd80e2245b7cd  25_qualify_pdf_extraction_on_emceedanko.sh
989b1779ca71cdfa6bad915c12f33337693ddd75335c9920ef1427d8d51132d7  capture-pdf-extraction-observations.py
91c47082693a3c773c8944ad26d3d6d81a8193f4a927b2c87d5d6f427909da51  evaluate_pdf_extraction.py
456279482e50681c4c07cb41fbdff10f1ca8e9de458df4a99aa725f3ed94fd14  synthetic_pdf_sources.json
0b5a8bee82ab8ba3593393fe5d1a260e7755d5592e17908a3d4922b7cd7fe8f9  extraction_acceptance_truth.json
```

The accepted target inventory receipt is bound by SHA-256
`a02fd0767b5db8e9584abfd8e720bb6dd039552fa45e301001191f795e60f69b`.

## Qualification behavior

The target receives only the neutral capture program, the source-identity
manifest, and the six fully synthetic PDFs. It does **not** receive the
held-out structural truth or the evaluator.

The capture program:

1. verifies hostname, operating-system version, architecture, exact Poppler
   package, exact tool versions, and all source identities;
2. invokes `pdfinfo`, `pdftotext -layout`, and
   `pdftotext -bbox-layout` as argument vectors with no shell;
3. applies command time, address-space, output-size, file-descriptor, and CPU
   limits;
4. runs every extraction twice and rejects non-repeatable output;
5. records page and blank-page observations plus content-free timings and
   output digests; and
6. packages the raw synthetic Poppler outputs in a bounded archive.

The wrapper returns that archive to the local repository workspace and grades
it against the held-out truth. Acceptance requires all six documents and 27
pages, the one intentional blank page, exact token presence and physical
reading order, all 27 headings, all 40 ordered-phrase checks, 16 repeated-page
furniture checks, four table rows and 16 cells, eight form field/value pairs,
ten checkbox associations, exact output identities, and repeatability.

The detailed truth and detailed comparison remain local. The durable report
contains only content-free identities, counts, and pass/block markers. The raw
accepted artifact contains only the fully synthetic fixture outputs and is
stored under the ignored local artifact area for the next normalization work.

Target temporary files are removed on every wrapper exit. The gate does not
install packages, use sudo, start or change services, call a model, access
PostgreSQL, read organizational documents, process secrets, or transfer
held-out truth.

The first operator run blocked at bounding-box token/order grading after the
remote capture passed. The canonical source now evaluates physical line and
coordinate order rather than XHTML serialization order. It also persists the
verified synthetic capture before grading and creates a protected local
diagnostic on any block. The detailed first-run disposition is recorded in
`ishikawa_pdf_extraction_qualification_first_run_block_2026-10-19.md`.

## Local validation

The no-contact source gate passed:

```text
pdf_extraction_capture_self_test=pass
pdf_extraction_evaluator_self_test=pass
pdf_extraction_qualification_source=pass
target_contact=false;source_documents=6;source_pages=27;held_out_truth_transferred=false
payload_file_count=8
```

## Operator command

Run from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/25_qualify_pdf_extraction_on_emceedanko.sh --run
```

The command may prompt once for the SSH key passphrase. It does not request
sudo or an application secret. Only a returned
`pdf_extraction_qualification_wrapper=pass` accepts the extraction gate. A
successful run makes normalization and structural-unit implementation the
next gate; it does not accept later producer or retrieval stages.
