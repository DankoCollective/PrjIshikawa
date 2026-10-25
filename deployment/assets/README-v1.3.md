# Ishikawa v1.3 frontier deployment package

This archive contains the frozen Ishikawa v1.3 application payload and the
complete empty PostgreSQL schema-version-5 target. It does not contain
organizational source documents, credentials, model responses, operating-system
packages, container images, historical migrations, or development repairs.

The synthetic corpus v3 qualification fixture is carried in a separate,
checksum-bound archive. Verify this package before installation:

```bash
bash ./verify-ishikawa-release
```

Install the application into a new path:

```bash
bash ./application/install-ishikawa --install-root /absolute/new/path
```

Install the schema only into an empty selected database after the database
decision and roles are approved:

```bash
bash ./database/install-schema \
  --database ishikawa \
  --owner-role ishikawa_owner \
  --ingest-role rag_ingest \
  --retrieval-role rag_retrieval
```

Neither installer starts services or enables boot autostart. PostgreSQL 16 with
pgvector, the approved native dependencies, an architecture-matching
`node-24-slim-nextjs-16-4-1` image, and model connectivity are prerequisites.
