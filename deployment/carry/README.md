# Ishikawa v1.3.1 portable deployment

This directory carries two independent primary payloads: the external
Ishikawa application archive and an application-free Linux AMD64 Node/Next
runtime-image archive. The application is never baked into the image.
`PACKAGE_MANIFEST.json` records the purpose, consumer, mode, byte size, and
SHA-256 of every payload/support file and classifies its two control files;
`SHA256SUMS` binds the package manifest and every other carried file.
The recorded modes are the required target Unix modes. Transfer media that do
not preserve Unix permission bits are supported: the verifier checks the
classified intended modes, and installation materializes them on the native
target filesystem.

The assembly lane publishes these files first as a local package candidate.
`deployment-package-receipt.json` must say `deployment_ready` before install or
schema initialization is permitted. Exact-artifact security review is complete;
approved destination inventory, independent review, and stable-handoff
publication are separate remaining gates. Renaming or copying an assembled
candidate does not satisfy them.

`SECURITY_REVIEW.md` records the completed exact-payload vulnerability
disposition. The assembled candidate remains non-installable until destination
inventory, independent review, and stable-handoff publication are complete.

## Requirements and boundaries

The destination must be Ubuntu 26.04 AMD64 with Docker, PostgreSQL 16,
pgvector, Python 3, PyYAML, psycopg, and Poppler already available. The
`rag_catalog` database and the `rag_owner`, `rag_ingest`, and `rag_retrieval`
roles must be absent before clean database initialization. Native packages are
reused only after the supplied inventory confirms compatibility; this directory
contains no speculative operating-system package bundle.

Installation creates `$HOME/Documents/Ishikawa`, loads the exact local runtime
image when it is absent, and installs three systemd user-unit files. It does
not download packages, change a database, ingest a document, store a
credential, contact a model, start a service, enable a unit,
enable PostgreSQL at boot, or enable user lingering. Allow about five minutes
for verification, inventory, image load, application installation, and
configuration; storage speed dominates image-load time.

## Verify and inventory

Start with the read-only verifier:

```bash
bash ./verify-deployment
```

Capture the destination's read-only prerequisite inventory before installing:

```bash
bash ./deploy-ishikawa inventory \
  --postgresql-port 5432 \
  --retrieval-port 8384 \
  --web-port 3384 \
  --gemma-port 8000 \
  --nomic-port 8001 \
  --use-sudo-inspection \
  --output-dir /tmp/ishikawa-native-prerequisite-inventory
```

The inventory normally completes in one to three minutes. With
`--use-sudo-inspection` it prompts once for attended sudo authorization and
uses that authorization only for read-only Docker and, when the selected
PostgreSQL cluster is already online, catalog inspection. It does not start
the cluster. If the protected
corpus root is already known, add `--protected-source-root /absolute/path`;
the evidence records only whether the root is usable, never its path or file
names. The inventory checks all five selected listeners, package/runtime
availability, apt/dpkg health, PostgreSQL cluster posture, existing Ishikawa
paths and units, operator/user-manager posture, and bounded capacity in one
pass. It finishes with:

```text
SCRIPT RESULT
ishikawa_native_prerequisite_inventory=pass
```

After the inventory is reviewed, install the image, application, and
boot-disabled user units:

```bash
bash ./deploy-ishikawa install
```

The installation root is always `$HOME/Documents/Ishikawa`. The selected Tech
loopback ports are web `3384`, Retrieval API `8384`, PostgreSQL `5432`, Gemma
`8000`, and Nomic `8001`. Supply explicit port options to `inventory` and
`install` when the reviewed destination topology differs. Installation writes
the selected endpoints into the installed YAML and operator documents so the
installed command sheet cannot direct the operator to the archive's generic
source defaults.

The install command completes every preflight before loading the image or
creating the application root. It prints bounded stage markers and ends with:

```text
SCRIPT RESULT
ishikawa_deployment_install=pass
```

An existing application root, unit file, conflicting image tag, wrong host,
missing prerequisite, boot-enabled PostgreSQL cluster, enabled user lingering,
or non-final carry receipt blocks before mutation. If a later install step
fails, the command removes only the image, application root, and unit files
that attempt created. It never changes the database during installation.

## Database and protected corpus

After application installation, obtain distinct ingestion and retrieval
passwords through the approved secret-delivery path. A shell can accept them
without terminal echo:

```bash
read -rsp 'Ingestion database password: ' ISHIKAWA_POSTGRESQL_INGEST_PASSWORD
printf '\n'
read -rsp 'Retrieval database password: ' ISHIKAWA_POSTGRESQL_PASSWORD
printf '\n'
export ISHIKAWA_POSTGRESQL_INGEST_PASSWORD ISHIKAWA_POSTGRESQL_PASSWORD
bash ./deploy-ishikawa install-schema
```

If inventory selected a nondefault PostgreSQL listener, pass the same
`--postgresql-port PORT` used during installation.

The command requires an empty target identity, creates the no-login owner and
two login roles, creates `rag_catalog`, activates pgvector, and installs the
canonical schema v5. It starts the boot-disabled PostgreSQL cluster only when
needed and returns it to its prior stopped state. On failure it removes only
the roles and database marked as created by that attempt. It never writes a
password to the package, command line, report, or output.

Inside the protected environment, place approved PDFs under the installed
`corpus/source` tree and fill `config/corpus_metadata.csv` with the required
document keys, display names, and approved classes. Then run:

```bash
cd "$HOME/Documents/Ishikawa"
scripts/ishikawa-create-ingestion-config --validate-only \
  --metadata config/corpus_metadata.csv
scripts/ishikawa-create-ingestion-config --publish \
  --metadata config/corpus_metadata.csv
```

Review the generated catalog and pending manifest before running the installed
ingestion command. Every document, page, chunk, relationship, and embedding
count must come from those protected inputs and the resulting database. The
carry contains no source document, catalog, ingestion manifest, credential,
database content, or generated web build state.

## Start, status, logs, and stop

Start the application only after the model forwards and the four required
credential environment variables are present:

```bash
bash ./deploy-ishikawa start
bash ./deploy-ishikawa status
```

Stop it with:

```bash
bash ./deploy-ishikawa stop
```

Nothing is enabled at boot. The web container mounts the installed application
read-only, creates a bounded temporary `.next`, runs `next build`, and then
executes `next start`. Removing the container removes the generated build.

The Retrieval API writes bounded logs beneath
`$HOME/Documents/Ishikawa/state/logs`. Inspect application state with the
installed `scripts/ishikawa-log-control status` and stack state with
`bash ./deploy-ishikawa status`. Do not copy content-bearing logs or reports
out of the protected environment.

If start fails, the installed stack removes the web container, stops only the
Retrieval API and PostgreSQL cluster it started, clears imported secret values,
and removes its owned state marker. Correct the reported condition and rerun.
No automatic backup or restore proof is part of this demo.

## Empty-installation removal

After stopping the stack, a never-ingested installation can be removed with:

```bash
bash ./deploy-ishikawa remove --confirm-empty-installation
```

Removal refuses when source documents, ingestion records, runtime files, an
active unit, or an enabled unit is present. It removes the application and its
three user-unit files but deliberately retains the database and generic runtime
image. Database deletion and content-bearing cleanup require a separately
reviewed operator action.
