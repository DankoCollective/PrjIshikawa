# Ishikawa Corpus Ingestion Runbook

## Purpose and boundary

This is the operator-facing sequence for preparing a document catalog,
creating an ingestion manifest, validating a run, and publishing it through an
installed Ishikawa v1.3 application. It applies to a synthetic qualification
corpus or an approved organizational corpus. It does not authorize access to a
corpus, choose its documents, create database roles, or replace corpus-specific
acceptance testing.

The document catalog is the durable logical inventory and is not recreated for
every ordinary run. A pending ingestion manifest is a per-run batch containing
only additions, revisions, reprocessing requests, and retirements for that
run. Script 05 generates both only because each synthetic qualification uses a
new disposable database and private application copy. Script 06 likewise
generates both for the first isolated durable v1.3 cluster, then requires their
exact installed bytes on every attended reuse.

## Fresh-install entry gate

On a fresh installation, do not begin corpus preparation or ingestion after
application installation alone. The required packaged order is:

1. `deploy-ishikawa apply` passes and installs the application.
2. `deploy-ishikawa install-schema` passes and initializes the empty database,
   pgvector, schema v5, and the `rag_owner`, `rag_ingest`, and `rag_retrieval`
   roles.
3. Only then create or review corpus metadata, the document catalog, and the
   pending manifest; validate and publish ingestion afterward.

The retained database-stage result must be:

```text
SCRIPT RESULT
ishikawa_deployment_install_schema=pass
```

An `ishikawa_ingestion_config=ready` result proves only that the corpus
configuration was generated; it does not prove database initialization. Do
not compensate for a missing schema-stage result with manual SQL, an ad hoc
wrapper, or a newly invented orchestrator. Run the existing packaged action,
review its result, and continue this runbook. An established installation with
a separately proven compatible schema-v5 database does not rerun clean
initialization.

## 1. Confirm the installation and dependencies

Use the canonical Tech installation:

```bash
cd "$HOME/Documents/Ishikawa"
```

Before ingestion, confirm that PostgreSQL 16 with pgvector is available, the
schema-v5 database and roles have been installed with the fresh-install gate
above (or separately proven on an established installation), the configured
Nomic endpoint is reachable, and `scripts/ishikawa-ingest` is executable. Review
`config/deployment.yaml` and `config/ingestion_dependencies.yaml`; do not put
credentials in either file.

## 2. Stage approved source PDFs

Copy approved PDFs beneath `corpus/source/` using stable relative paths. For
example:

```text
corpus/source/organization-wide/policies/acceptable-use.pdf
corpus/source/department/legal/audit-evidence-guide.pdf
```

The manifest records paths relative to `corpus/source/`. Absolute paths,
parent traversal, symlinks, directories, and unsupported file types fail
closed. Preserve the approved source bytes; replacing bytes beneath an
existing logical key is a new source revision.

## 3. Review document classes

`config/document_classes.yaml` is the complete class registry. Add a class
only when the existing active classes do not apply. The exact shape is:

```yaml
schema_version: 1

classes:
  - class_id: policy_sop
    display_name: Policy or SOP
    status: active

  - class_id: administrative_form
    display_name: Administrative Form
    status: active
```

Class identifiers are stable. Retire an obsolete class by changing its status;
do not rename or reuse its identifier.

## 4. Create or update the document catalog

`config/document_catalog.yaml` is the complete durable list of logical
documents known to the installation. Start from the shipped example on an
empty installation, then add one entry for every logical document in the
initial corpus:

```yaml
schema_version: 1

documents:
  - document_key: policy.acceptable-use
    display_name: Acceptable Use Policy
    status: active

  - document_key: guide.audit-evidence
    display_name: Audit Evidence Guide
    status: active
```

Choose a stable `document_key` that identifies the logical document, not its
filename, date, or revision. A future revision keeps the same key. Never delete
or rename a previously published key. To retire a document, first change its
catalog status to `retired`, then include that key in a later manifest's
`retirements` list.

The catalog does not contain source paths, class assignments, chunk settings,
manual version numbers, or credentials. Ishikawa computes its canonical
identity after validation.

When migrating an established corpus, carry its already reviewed catalog as a
separate checksum-verified deployment input and install those exact bytes.
Do not regenerate a replacement catalog on the target merely because the
machine or lab changed. Generate a new catalog only for a genuinely new corpus
whose logical inventory has not previously been established.

## 5. Create the per-run ingestion manifest

Create one plain YAML file directly beneath `config/ingestion/pending/`, for
example `2026-10-25-initial-corpus.yaml`:

```yaml
schema_version: 1

documents:
  - source_path: organization-wide/policies/acceptable-use.pdf
    document_key: policy.acceptable-use
    class_id: policy_sop

  - source_path: department/legal/audit-evidence-guide.pdf
    document_key: guide.audit-evidence
    class_id: policy_sop

retirements: []
```

Each `document_key` must already exist as active in the catalog, and each
`class_id` must already exist as active in the class registry. The manifest is
incremental: later batches list only affected documents and explicit
retirements. It does not repeat the complete corpus unless the operator is
performing a deliberately reviewed full initial ingestion or full reprocess.

## 6. Validate without publication

Run validation with the ingestion database credential supplied only through a
protected environment value:

```bash
read -rsp 'PostgreSQL ingestion password: ' ISHIKAWA_POSTGRESQL_INGEST_PASSWORD
printf '\n'
export ISHIKAWA_POSTGRESQL_INGEST_PASSWORD
./scripts/ishikawa-ingest --validate-only --manifest 2026-10-25-initial-corpus.yaml
validation_status=$?
unset ISHIKAWA_POSTGRESQL_INGEST_PASSWORD
```

Require exit status zero and the standalone result
`ishikawa_ingestion=pass;exit_code=0`. Review the protected report under
`state/reports/ingestion/` before publication. A blocked or quarantined result
must be corrected with a new attempt; do not edit PostgreSQL rows or retained
artifacts to manufacture a pass.

## 7. Publish the same reviewed batch

After validation passes, use the same manifest bytes and supply the Nomic and
ingestion database credentials through hidden input or another approved
protected mechanism:

```bash
read -rsp 'Nomic API key: ' ISHIKAWA_NOMIC_API_KEY
printf '\n'
read -rsp 'PostgreSQL ingestion password: ' ISHIKAWA_POSTGRESQL_INGEST_PASSWORD
printf '\n'
export ISHIKAWA_NOMIC_API_KEY ISHIKAWA_POSTGRESQL_INGEST_PASSWORD
./scripts/ishikawa-ingest --publish --manifest 2026-10-25-initial-corpus.yaml
publish_status=$?
unset ISHIKAWA_NOMIC_API_KEY ISHIKAWA_POSTGRESQL_INGEST_PASSWORD
```

One manifest is one atomic publication boundary. If a required document fails
or is quarantined, none of that manifest's changes becomes searchable.
Identical accepted artifacts are reused by SHA-256 identity.

## 8. Verify and retain the run record

After a clean publish:

1. review the protected ingestion report and its manifest/catalog identities;
2. verify Retrieval API readiness against the active published corpus;
3. run a corpus-specific acceptance set with expected citations;
4. retain the reviewed manifest and content-free acceptance receipt according
   to the deployment evidence policy; and
5. move the manifest from `pending` only after review. Ishikawa v1.3 does not
   move it automatically.

Do not apply synthetic corpus-v3 document, page, chunk, relationship, or
frontier counts to an organizational corpus. Derive inventory checks from the
approved organizational catalog, the reviewed run, and PostgreSQL.

## Contract references

- Exact YAML keys and examples: `Ishikawa/docs/CONFIGURATION_CONTRACTS.md`
- Routine installed operation: `Ishikawa/docs/OPERATOR_GUIDE.md`
- Installed one-shot boundary: `Ishikawa/docs/INSTALLED_OPERATOR_INGESTION.md`
- Runtime dependency boundary: `Ishikawa/docs/OPERATOR_INGESTION_RUNTIME.md`
- Validation, quarantine, and atomicity:
  `Ishikawa/docs/VALIDATION_AND_QUARANTINE_CONTRACT.md`

