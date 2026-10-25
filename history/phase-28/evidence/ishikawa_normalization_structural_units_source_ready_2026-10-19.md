# Ishikawa Normalization and Structural Units Source Ready

## Status

Script `26` is source-ready after a complete no-contact validation and a
temporary-output end-to-end smoke run. It consumes the accepted Script `25`
synthetic extraction artifact and creates the first deterministic normalized
structural-unit artifact. Default artifact retention remains `NOT RUN` until
the operator executes the published Script `26` command.

## Bound accepted input

```text
072bff5e6d791fd1399f52dde8da8e3be1d53c30d4d7510d6de00ae01e3f6067  pdf_extraction_observations_20261019T212440Z.tar
b5725ccb83f8492b855280974598e49b3a33639d0c3fd8320ef4b23092644186  target capture receipt
9ba0e112df80b0b56b49fbb068ef75eb03a3f5fd9949c0d3dace4c6f32a34eb5  local extraction acceptance receipt
456279482e50681c4c07cb41fbdff10f1ca8e9de458df4a99aa725f3ed94fd14  synthetic_pdf_sources.json
f83fd0bc8e0a25cd6bad35c5377b72a921205e7dd50565641fb58b229c635b1b  extraction_acceptance_truth.json
```

## Source identities

```text
965df01eb9e2227191da445dd0c6724b233e72c59f79442e2f78c12634822138  26_create_normalized_structural_units.sh
f1b23bb7825090935078257907a46675e1b942f7dde955055ebf21037c89ad5f  normalization.py
8e9193492c69bee6a31afe3f7606ec2efd528f79d76feb4189d462e6b3c206ea  normalize-pdf-extraction.py
b8221ab0ba9f92abcc5f0e2763c1a5bbc5d5f6ce1c4ec92c1a44c0ace1fd11c5  normalization_checks.py
```

## Local proof

The no-contact source gate and temporary-output smoke run passed:

```text
target_contact=false;database_connection=false;model_call=false
base_tests=64;normalization_tests=13;failures=0;errors=0
deterministic_replays=2;artifact_match=true;result_match=true
documents=6;pages=27;blank_pages=1
structural_units=230;headings=28;paragraphs=40;list_items=60;definitions=5
tables=1;form_fields=12;checkbox_groups=4;page_furniture=80
normalization_set_digest=86a31ba1ce7dea966273576553f09b244e7f3a3f9d4f7757812d04f9551f9e43
artifact_sha256=736d619ac5a7e10f768bdb8b8f3f117cb52231f8dc2f4d186d52d96c8bd41e28
artifact_bytes=172376
script_26_normalization_source=pass
```

The smoke artifact and report were created only beneath a temporary local
directory and removed after validation. No remote host, PostgreSQL service,
model service, organizational document, or application secret was accessed.

The detailed normalization boundary and structural records are documented in
`Ishikawa/docs/NORMALIZATION_AND_STRUCTURAL_UNITS.md`.

## Operator command

From the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/26_create_normalized_structural_units.sh --run
```

The command is entirely local and requests no password. A pass retains the
normalized synthetic JSON artifact and checksum beneath the ignored local
artifact area. Only
`script_26_normalization=pass;next_gate=structure_aware_chunking_and_metadata`
accepts this gate.
