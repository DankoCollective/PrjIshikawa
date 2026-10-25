Yes. Items 1–3 have ready-to-freeze recommendations. They establish a clean ownership boundary:

| File | Owns |
|---|---|
| `document_classes.yaml` | Which document classes are valid |
| `document_catalog.yaml` | Which logical documents exist and their lifecycle status |
| `ingestion_manifest.yaml` | Which documents this batch processes and their assigned classes |

Class does not belong in the catalog. Source paths do not belong in the catalog. Operator version labels are not required. Annotation 1

## Ready-to-freeze 1: Document-class registry

File:

```text
~/Documents/Ishikawa/config/document_classes.yaml
```

Recommended schema:

```yaml
schema_version: 1

classes:
  - class_id: policy_sop
    display_name: Policy or SOP
    status: active

  - class_id: administrative_form
    display_name: Administrative Form
    status: active

  - class_id: regulation
    display_name: Regulation
    status: active
```

Recommended rules:

- The root contains exactly `schema_version` and `classes`.
- `schema_version` must be integer `1`.
- `classes` must be a nonempty list.
- Each entry contains exactly:
  - `class_id`
  - `display_name`
  - `status`
- Unknown fields are rejected.
- `class_id` must match:

```text
^[a-z][a-z0-9._-]{0,127}$
```

- Class identifiers must be unique.
- Punctuation-equivalent class identifiers are rejected to prevent accidental variants.
- `display_name` must remain nonempty after trimming.
- `status` must be `active` or `retired`.
- New ingestion may use only an active class.
- Retiring a class prevents future assignment but does not automatically retire documents already assigned that class.
- Changing a display name does not require document reprocessing.
- Changing a `class_id` means adding a new class and retiring the old one; identifiers are not renamed in place.
- The registry does not contain extraction, classification, chunking, or prompt rules.
- The application converts the validated structure into canonical JSON and computes a domain-separated SHA-256 digest.
- That computed digest is the registry version. The operator does not manually maintain `registry_version`.

Database mapping:

```text
rag.document_classes
```

This is ready to freeze.

## Ready-to-freeze 2: Document catalog

File:

```text
~/Documents/Ishikawa/config/document_catalog.yaml
```

Recommended schema:

```yaml
schema_version: 1

documents:
  - document_key: policy.social-media
    display_name: Social Media Policy
    status: active

  - document_key: regulation.federal-records
    display_name: Federal Records Regulation
    status: active

  - document_key: procedure.incident-reporting
    display_name: Incident Reporting Procedure
    status: active
```

Recommended rules:

- The root contains exactly `schema_version` and `documents`.
- `schema_version` must be integer `1`.
- `documents` is a list and may be empty for a new installation.
- Each entry contains exactly:
  - `document_key`
  - `display_name`
  - `status`
- Unknown fields are rejected.
- `document_key` must match:

```text
^[a-z0-9][a-z0-9._-]{0,127}$
```

- Keys must be unique.
- Simple punctuation-equivalent keys are rejected. For example:

```text
policy.social-media
policy.socialmedia
policy_social_media
```

- `display_name` must remain nonempty after trimming.
- `status` must be `active` or `retired`.
- The catalog contains no source paths.
- The catalog contains no class assignment.
- The catalog contains no manually maintained document version.
- The catalog contains no extraction or chunking settings.
- Once registered, a document key cannot silently disappear or be renamed.
- Removing a previously registered key from the YAML is rejected.
- A display-name change is allowed and does not change document identity.
- A document becomes non-searchable only through the explicit retirement workflow.
- The complete validated catalog receives a canonical digest automatically; the operator does not maintain `catalog_version`.
- `document_id` is deterministically derived from the stable `document_key`.
- New source bytes under the same key create a new source revision without creating a new logical document.

Database mapping:

```text
rag.documents
```

The ingestion command validates the complete catalog and synchronizes permitted catalog metadata. Merely registering a new document does not make it searchable; it must still be ingested and published.

This is ready to freeze.

## Ready-to-freeze 3: Ingestion manifest

Location:

```text
~/Documents/Ishikawa/config/ingestion/pending/
```

Example filename:

```text
2026-10-19-policy-update.yaml
```

The filename is for operator convenience only and does not control identity.

Recommended schema:

```yaml
schema_version: 1

documents:
  - source_path: organization-wide/policies/social-media-policy-2027.pdf
    document_key: policy.social-media
    class_id: policy_sop

  - source_path: external/regulations/federal-records-regulation.pdf
    document_key: regulation.federal-records
    class_id: regulation

retirements:
  - document_key: procedure.legacy-travel-request
```

Recommended rules:

- The root contains exactly:
  - `schema_version`
  - `documents`
  - `retirements`
- `schema_version` must be integer `1`.
- `documents` and `retirements` are lists.
- Either list may be empty, but at least one must contain an entry.
- Every listed item is required. Version 1 has no optional-document flag.

Each `documents` entry contains exactly:

```text
source_path
document_key
class_id
```

Each `retirements` entry contains exactly:

```text
document_key
```

For ingestion entries:

- `document_key` must exist in the catalog.
- The catalog document must be active.
- `class_id` must exist and be active.
- `source_path` must be relative.
- Absolute paths are rejected.
- `..` path traversal is rejected.
- The resolved path must remain beneath the configured corpus source root.
- The source must be a regular file.
- The initial implementation accepts PDF only.
- A document key may appear only once in `documents`.
- A source path may appear only once.
- A document cannot appear in both `documents` and `retirements`.
- The same document cannot be assigned two classes in one batch.

For retirement entries:

- The key must exist in the catalog.
- Its catalog status must already be `retired`.
- No source path is supplied.
- No class is supplied.
- A missing manifest retirement entry means the catalog change is not published.
- Omitting a document entirely never retires it.

The manifest does not contain:

- An operator-created run ID.
- A document version label.
- Absolute deployment paths.
- Model credentials.
- PostgreSQL credentials.
- Endpoint secrets.
- Chunking rules.
- Extraction rules.
- Arbitrary metadata.
- Optional catch-all fields.

The application computes:

- Canonical manifest digest.
- Class-registry digest.
- Document-catalog digest.
- Source-file digest.
- Effective processing identities.

The absolute source root comes from:

```text
~/Documents/Ishikawa/config/deployment.yaml
```

Example:

```yaml
corpus_source_root: /home/operator/Documents/Ishikawa/corpus/source
```

That path remains private deployment configuration and is not client metadata.

This is ready to freeze.

## Common YAML safety rules

I recommend freezing these across all three files:

- UTF-8 only.
- Exactly one YAML document per file.
- Duplicate mapping keys rejected.
- Unknown fields rejected.
- Custom YAML tags rejected.
- Anchors and aliases rejected.
- Merge keys rejected.
- Scalars, lists, and mappings only.
- YAML is parsed with the reviewed Ubuntu-provided safe loader.
- Explicit Python validation enforces the small schemas; we do not add a JSON Schema framework or write a YAML parser.
- Canonical digests are computed after parsing and validation, so formatting and comments do not change identity.
- Secrets are forbidden in all three files.

## Resulting ownership model

```text
document_classes.yaml
└── class_id validity and lifecycle

document_catalog.yaml
└── stable logical document identity and lifecycle

ingestion_manifest.yaml
├── source path for this batch
├── existing document key
├── assigned class for this processing attempt
└── explicit retirement action
```

This ownership model gives migration `0002` a precise target:

- `rag.documents` owns identity, display name, and lifecycle—not class.
- `rag.document_versions` owns immutable source revision—not class.
- Candidate artifact/publication context owns assigned class.
- Active retrieval views expose the class belonging to the active artifact context.

## Work sequence after freezing 1–3

Once these three are frozen:

1. Add their exact schemas and sanitized examples under `Ishikawa/`.
2. Implement the restricted YAML-loading adapter.
3. Implement individual and cross-file validators.
4. Implement collision, path-containment, retirement, and quarantine tests.
5. Finalize migration `0002` from the validated ownership model.
6. Regression-test `0001 → 0002` and fresh `0001 + 0002` installation paths.
7. Build the incremental ingestion writer.

No target or operator command is needed for items 1–4. Migration `0002` will not receive an operator command until its SQL and regression tests pass locally.