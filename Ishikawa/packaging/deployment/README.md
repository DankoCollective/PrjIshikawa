# Ishikawa v1 deployment package

This is the single Ishikawa v1 application-and-database deployment package.
It contains the final application payload and the final fresh-install database
schema. It contains no schema ancestors, migrations, repair programs, source
documents, credentials, model responses, operating-system packages, or
container images.

The packaged application includes the accepted PostgreSQL transaction-boundary
correction. Ingestion planning uses an autocommit connection, while publication
continues to use its explicit atomic transaction.

Before installation, provide the approved native dependencies, PostgreSQL 16
with pgvector, an empty application database with its three roles, the
architecture-matching Node 24/Next.js image, and any required model endpoint
connectivity. Those deployment-specific prerequisites remain external because
they differ by operating-system release and machine architecture.

First verify the complete package:

```bash
bash ./verify-ishikawa-v1
```

Install the final schema into an existing empty database:

```bash
bash ./database/install-schema \
  --database ishikawa \
  --owner-role ishikawa_owner \
  --ingest-role rag_ingest \
  --retrieval-role rag_retrieval
```

Install the application into a new host directory:

```bash
bash ./application/install-ishikawa \
  --install-root "$HOME/Documents/Ishikawa"
```

Both component installers verify their own manifests and fail closed. The
database installer creates the complete empty version-4 schema in one
transaction. The application installer publishes a new directory atomically
and refuses to merge with an existing installation. Services remain stopped
and boot-disabled after installation.

