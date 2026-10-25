# Ishikawa Frozen Configuration Contracts v1

The separate product-presentation schema is documented completely in
[`PRODUCT_PRESENTATION_CONFIGURATION.md`](PRODUCT_PRESENTATION_CONFIGURATION.md).
It uses `schema_version: 2`; the v1 statements below apply to the data,
ingestion, logging, dependency, and deployment contracts described here.

## Status

The document-class registry, document catalog, and incremental ingestion
manifest contracts were frozen by the operator on 2026-10-19. Their
restricted loader, exact validators, canonical identities, and cross-file
planning logic were implemented and passed the local 52-test acceptance suite
on 2026-10-19. Target-native package qualification and PostgreSQL integration
remain separate work.

## Common YAML contract

All three inputs:

- are UTF-8, single-document YAML;
- require integer `schema_version: 1`;
- reject duplicate mapping keys and unknown fields;
- reject custom tags, anchors, aliases, and merge keys;
- permit only mappings, lists, and scalar values required by the schema;
- contain no credentials, endpoint secrets, or arbitrary metadata;
- are parsed with a reviewed Ubuntu-provided safe YAML loader; and
- are converted to a versioned canonical JSON representation after validation
  for domain-separated SHA-256 identity.

Comments, whitespace, key order, and YAML formatting do not change the
canonical identity. The operator does not maintain registry, catalog,
manifest, document-version, or run identity labels manually.

## 1. Document-class registry

Path:

```text
~/Documents/Ishikawa/config/document_classes.yaml
```

Exact root fields:

- `schema_version`: required integer, exactly `1`;
- `classes`: required nonempty list.

Exact class fields:

- `class_id`: required string matching
  `^[a-z][a-z0-9._-]{0,127}$`;
- `display_name`: required nonblank string;
- `status`: required enum `active` or `retired`.

Class identifiers must be exact-unique and punctuation-equivalent identifiers
are rejected. New or reprocessed documents may use only active classes.
Retiring a class prevents new assignment but does not retire documents already
using it. A display-name change does not require document reprocessing. A
class identifier is never renamed in place; a replacement class is added and
the prior class is retired.

The registry does not contain classifier signals, confidence, patterns,
chunking settings, extraction rules, or model prompts. Adding an ordinary
class label is configuration-only. Validated classes map to
`rag.document_classes`. The computed registry digest is the stored registry
identity.

Frozen template:

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

## 2. Document catalog

Path:

```text
~/Documents/Ishikawa/config/document_catalog.yaml
```

Exact root fields:

- `schema_version`: required integer, exactly `1`;
- `documents`: required list; it may be empty on a new installation.

Exact document fields:

- `document_key`: required string matching
  `^[a-z0-9][a-z0-9._-]{0,127}$`;
- `display_name`: required nonblank string;
- `status`: required enum `active` or `retired`.

Keys must be exact-unique. Simple punctuation- and spacing-equivalent keys are
also rejected so accidental variants cannot create separate logical
documents. A registered key cannot silently disappear, be renamed, or be
reused for another logical document. A display-name change does not change
identity.

The catalog contains no source path, assigned class, manual document version,
chunking setting, or extraction setting. The stable key deterministically
derives the internal `document_id`; changing source bytes under that key
creates a source revision, not a new logical document. Catalog records map to
`rag.documents`, and the computed catalog digest is the catalog identity.

Frozen template:

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

## 3. Incremental ingestion manifest

Pending-manifest directory:

```text
~/Documents/Ishikawa/config/ingestion/pending/
```

The filename is an operator convenience and does not control identity.

Exact root fields:

- `schema_version`: required integer, exactly `1`;
- `documents`: required list;
- `retirements`: required list.

Either list may be empty, but at least one must contain an entry. Every entry
is required; v1 has no optional-document flag.

Exact ingestion-document fields:

- `source_path`: required relative path;
- `document_key`: required catalog key;
- `class_id`: required active registry class.

Exact retirement fields:

- `document_key`: required catalog key.

An ingestion document must reference an active catalog document and active
class. Its source path must be relative, must not contain traversal, must
resolve beneath the deployment's configured corpus source root, and must
resolve to one regular supported PDF. Document keys and source paths may each
appear only once. A key cannot appear in both `documents` and `retirements` or
receive two class assignments in one batch.

A retirement key must exist and already have catalog status `retired`. A
retirement supplies no path and no class. Retirement becomes searchable state
only when the matching manifest action is successfully published; omission
never retires a document.

The manifest contains no operator-created run ID, manual document version,
absolute deployment path, credential, arbitrary metadata, chunking rule, or
extraction rule. The application computes the canonical manifest digest and
binds it to the validated registry, catalog, method profile, and source-byte
identities.

Frozen template:

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

## Frozen ownership boundary

```text
document_classes.yaml
└── valid class identifiers and class lifecycle

document_catalog.yaml
└── stable logical document identity, display name, and lifecycle

ingestion_manifest.yaml
├── source path for this batch
├── existing document key
├── assigned class for this processing attempt
└── explicit retirement action
```

This boundary is authoritative input to cross-file validation and forward
migration `0002`. The accepted migration `0001` is not rewritten.

## Local logging profile

Path:

```text
~/Documents/Ishikawa/config/logging_profile.yaml
```

The exact v1 fields are:

- `schema_version`: integer, exactly `1`;
- `base_profile`: `default` or `debug`; persistent `verbose` is rejected;
- `operational_filename` and `audit_filename`: distinct safe `.jsonl`
  basenames under the installed protected log directory;
- `maximum_event_bytes` and `maximum_file_bytes`: bounded native-write and
  rotation limits;
- `retained_file_count`: bounded number of active plus rotated files; and
- `maximum_verbose_seconds`: maximum duration of one restart-local verbose
  activation.

The complete runtime identity includes the canonical profile digest. Unknown
fields or profile values fail configuration assembly. The YAML contains no
content-capture switch, arbitrary path, credential, header, database value, or
model setting. Exact field classifications and temporary verbose behavior are
defined in `OBSERVABILITY.md`.

## Runtime dependency profile

Path:

```text
~/Documents/Ishikawa/config/runtime_dependencies.yaml
```

This Tier-3 profile supplies only deployment locations and bounded transport
settings:

- Gemma chat-completion, tokenization, and health endpoint URLs;
- Nomic embedding and health endpoint URLs;
- transport timeouts and response limits;
- the fixed native PostgreSQL database and read-only role; and
- the names of the three protected runtime environment values.

The fixed environment names are `ISHIKAWA_GEMMA_API_KEY`,
`ISHIKAWA_NOMIC_API_KEY`, and `ISHIKAWA_POSTGRESQL_PASSWORD`. Their values are
never YAML fields and are not read while configuration is validated or the
runtime is assembled. Endpoints reject embedded credentials, query strings,
fragments, and paths outside their exact qualified API routes. Each health
endpoint uses exact path `/health` and must share the scheme, host, and port of
its corresponding Gemma or Nomic application endpoint.

The profile has its own canonical identity. Changing a location or timeout
changes the deployment identity but not the chunk, embedding-space, or
retrieval-method identities.
