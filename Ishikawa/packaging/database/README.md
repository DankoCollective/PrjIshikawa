# Ishikawa Database Schema Package

This package creates the complete empty Ishikawa PostgreSQL schema at version
5 from a clean application database. It is a fresh-install package, not an
upgrade package. It contains only the canonical final schema, its installer,
this operator explanation, and the checksum manifest generated during package
assembly.

Prerequisites are PostgreSQL 16, the pgvector extension package, an existing
empty database, the existing schema-owner, ingestion, and retrieval roles, and
an operator connection authorized to create schemas owned by those roles. The
database password, when required, must be supplied through the approved runtime
environment; it is never accepted as a command argument or stored here.

Run from the extracted package directory:

```bash
bash ./install-schema \
  --database ishikawa \
  --owner-role ishikawa_owner \
  --ingest-role rag_ingest \
  --retrieval-role rag_retrieval
```

The command validates package checksums, derives the schema identity from
`schema.sql`, and applies the entire schema in one transaction. It fails closed
when the target is not a clean supported baseline. Do not use this package to
modify an existing Ishikawa database; any future supported upgrade belongs in a
separate, explicitly selected upgrade package.
