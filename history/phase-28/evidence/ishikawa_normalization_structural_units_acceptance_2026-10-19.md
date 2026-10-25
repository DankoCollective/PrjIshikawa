# Ishikawa Normalization and Structural Units Acceptance

## Accepted result

The operator executed Script `26` on 2026-10-19. The retained receipt reports:

```text
target_contact=false;database_connection=false;model_call=false;organizational_content_processed=false
base_tests=64;normalization_tests=13;failures=0;errors=0
deterministic_replays=2;artifact_match=true;result_match=true
documents=6;pages=27;blank_pages=1
structural_units=230;headings=28;paragraphs=40;list_items=60;definitions=5
tables=1;form_fields=12;checkbox_groups=4;page_furniture=80
normalization_set_digest=86a31ba1ce7dea966273576553f09b244e7f3a3f9d4f7757812d04f9551f9e43
script_26_normalization=pass;next_gate=structure_aware_chunking_and_metadata
```

## Retained identities

```text
3f2391cebef59f62a31a1433bcdf1d679593e7b844fda62545ada79b8b1e9fa4  normalization_20261019T214207Z_Qcn1ok.txt
736d619ac5a7e10f768bdb8b8f3f117cb52231f8dc2f4d186d52d96c8bd41e28  normalized_structural_units_20261019T214207Z.json
ea56a45c16c5977322e6fdb5aa773a72214c54a3bb8b9a5032c82daa70d53db1  normalized_structural_units_20261019T214207Z.json.sha256
```

The artifact is `172376` bytes. Its sidecar was independently checked from
the artifact directory and returned `OK`. JSON inspection confirmed schema
version `1`, six documents, and the receipt's normalization-set digest.

## Boundary

This accepts normalization and structural-unit construction for the held-out
synthetic corpus. It does not accept retrieval chunks, Nomic token counts,
embeddings, database writes, or publication. Script `27` may consume only the
exact retained normalized-artifact identity above.
