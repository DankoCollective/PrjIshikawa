# Ishikawa Structural Chunk Candidates Source Ready

## Status

Script `27` is source-ready after a complete no-contact validation and a
temporary-output end-to-end smoke run. It consumes only the exact accepted
Script `26` artifact. Default artifact retention remains `NOT RUN` until the
operator executes the published Script `27` command.

## Bound input

```text
736d619ac5a7e10f768bdb8b8f3f117cb52231f8dc2f4d186d52d96c8bd41e28  normalized_structural_units_20261019T214207Z.json
ea56a45c16c5977322e6fdb5aa773a72214c54a3bb8b9a5032c82daa70d53db1  normalized artifact sidecar
3f2391cebef59f62a31a1433bcdf1d679593e7b844fda62545ada79b8b1e9fa4  accepted Script 26 receipt
```

## Source identities

```text
cc4914503c783e1a88906c562959d7096d0eba0e4988fbed43c8022c63eae0aa  27_create_structural_chunk_candidates.sh
d942351c52d00b31b69c491c4c0142dff4157a49cbbb1dbd58040b538674a87b  chunking.py
2c042acfabe608a5683d212403beac6215d385301562de059dc55bd77ed44a26  create-structural-chunk-candidates.py
fc855119be0653e6ed5e238e00f806d8ee584c9e4ca7867da49f4a344055de3f  chunking_checks.py
```

## Local proof

```text
target_contact=false;database_connection=false;model_call=false;retained_artifact=false
base_tests=64;normalization_tests=13;chunking_tests=12;failures=0;errors=0
deterministic_replays=2;artifact_match=true;result_match=true
documents=6;chunk_candidates=125;body_overlap_units=0
paragraphs=40;list_items=60;definitions=5
table_contexts=1;table_rows=3;form_fields=12;checkbox_groups=4
method_profile_id=13fd11355c7eee3b35faadea8e14c5df0787eb70578129377c836e55dff303e4
chunk_candidate_set_digest=348488b14d697eaca5a27042827f53abcd85b5852ec933baabeb6e5843c4a17a
token_measurement=pending_authoritative_nomic_measurement;publication_eligible=false
artifact_sha256=0b351ef579ff134a5fb1fb5f37843d5461a100f1fc2d803e278a9b20d3126548
artifact_bytes=277544
script_27_chunking_source=pass
```

The retained-output smoke artifact and report were created only under a
temporary directory, their sidecar returned `OK`, and the directory was
removed. No target, database, model, organizational content, or secret was
accessed.

## Operator command

From the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/27_create_structural_chunk_candidates.sh --run
```

Only
`script_27_chunking=pass;next_gate=nomic_token_measurement_and_embedding`
accepts this gate.
