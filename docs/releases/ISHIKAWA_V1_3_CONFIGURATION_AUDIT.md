# Ishikawa v1.3 YAML Configuration Audit

Date: 2026-10-24

## Result

The release carries every active YAML input used by the installed application.
Each installed YAML file is loaded through the restricted YAML loader and a
named validator before the relevant runtime is assembled. No supported
operator-configurable setting is bypassed by a second hidden runtime value.

This does not mean every YAML field is freely mutable in v1.3. The release has
two intentional configuration tiers:

1. Operator configuration accepts bounded changes without a new application
   release.
2. Qualified profiles are YAML-backed, canonically identified contracts whose
   v1.3 validators accept only the qualified topology or bounded values. A
   change outside that contract is a product change and requires qualification.

The second tier is fail-closed contract enforcement, not an ignored YAML file.
Removing those checks would reopen the frozen retrieval, security, API, and
citation behavior.

## Operator-configurable YAML

- `product.yaml`: display name, tagline, quick questions, footer notice, and
  formatted empty-chat content.
- `deployment.yaml`: bounded loopback web, Retrieval API, and PostgreSQL
  addresses and ports.
- `runtime_dependencies.yaml`: bounded Gemma, Nomic, and PostgreSQL connection
  locations and transport limits; secrets remain protected environment values.
- `ingestion_dependencies.yaml`: bounded Nomic and PostgreSQL ingestion
  locations and transport limits; secrets remain protected environment values.
- `logging_profile.yaml`: bounded profile, filenames, sizes, retention count,
  and temporary verbose duration.
- `document_classes.yaml`: accepted document classes.
- `document_catalog.yaml`: stable logical documents for the current ingestion.
- `config/ingestion/pending/*.yaml`: one generated or operator-prepared batch
  manifest per ingestion run.

## Qualified YAML profiles

- `api_profile.yaml`
- `injection_profile.yaml`
- `method_profile.yaml`
- `query_resolution_profile.yaml`
- `reconstruction_profile.yaml`
- `relationship_types.yaml`
- `relevance_profile.yaml`
- `retrieval_service_profile.yaml`
- `scope_profile.yaml`
- `sufficiency_profile.yaml`

These files are still read at runtime and contribute to canonical runtime
identity. Exact v1.3 values that define protocol, model behavior, retrieval
topology, evidence packing, sufficiency, and citation validation are
deliberately enforced in code. They cannot be changed as an unqualified local
tuning mechanism.

## Packaging boundary

Script 01 packages all 16 runtime/template YAML files, installs an empty active
`document_catalog.yaml`, and carries catalog and ingestion-manifest examples.
The application release remains corpus agnostic and contains no active
ingestion manifest or source document.

The corpus-v3 transfer contains source PDFs, corpus truth, document keys,
source checksums, and frontier cases. It does not contain a prebuilt
`document_catalog.yaml` or `ingestion_manifest.yaml`.

For each Script 05 qualification run on EmceeDanko, the checksum-bound target
generator:

1. verifies the 30 source records, document keys, source byte counts, and
   SHA-256 digests;
2. creates a fresh private `document_catalog.yaml` and pending ingestion
   manifest inside the disposable product copy;
3. validates both through Ishikawa's shipped restricted YAML loader and exact
   application schemas; and
4. deletes them with the disposable qualification workspace after the run.

PostgreSQL remains the runtime source of truth after publication. Generated
YAML is ingestion control input, never a retrieval index.
