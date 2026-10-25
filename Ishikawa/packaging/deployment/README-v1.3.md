# Ishikawa v1.3 deployment candidate

This archive is a checksum-bound Ishikawa v1.3 application-and-database
candidate. It contains the current application payload and the complete empty
schema-version-5 database target. It does not contain organizational source
documents, the synthetic qualification corpus, credentials, model responses,
operating-system packages, container images, migrations, or repair programs.

The candidate provides the three-pane knowledge-chat workspace, configurable
product presentation, turn-scoped citations, reconstructed selectable document
views, client-safe developer diagnostics, structured document-control metadata,
and the qualified V13-47 retrieval topology. Model requests use the V13-50
bounded compact-evidence protocol, exact chat-template token targets, and a
six-optional-structural-unit generation bound with a 2,048-token answer
reserve. Readiness warms the Nomic query path once, and the
developer panel separates retrieval into content-free stage timings.

The separately promoted 30-document synthetic corpus v3 is a qualification
fixture only. Its documents and evaluation truth are not deployment payloads
and are never installed by this archive.

Verify the extracted candidate before using either installer:

```bash
bash ./verify-ishikawa-v1.3
```

Install the complete schema into an empty application database:

```bash
bash ./database/install-schema \
  --database ishikawa \
  --owner-role ishikawa_owner \
  --ingest-role rag_ingest \
  --retrieval-role rag_retrieval
```

Install the application into a new directory:

```bash
bash ./application/install-ishikawa \
  --install-root "$HOME/Documents/Ishikawa-v1.3-candidate"
```

Both installers verify their component manifests and fail closed. The
application installer refuses to merge with an existing installation. It does
not start services or enable anything at boot. PostgreSQL 16 with pgvector,
the approved native dependencies, the architecture-matching Node 24/Next.js
image, and model connectivity remain deployment prerequisites.
