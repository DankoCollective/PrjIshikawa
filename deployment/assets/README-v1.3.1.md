# Ishikawa v1.3.1 deployment candidate

This checksum-bound archive contains the corpus-agnostic Ishikawa v1.3.1
application and the canonical empty schema-version-5 database definition. It
does not contain organizational source documents, qualification corpus data,
credentials, model responses, operating-system packages, container images,
generated `.next` state, historical migrations, or repair programs.

The archive includes the Apache License 2.0 application license. The separate
application handoff also supplies an application SBOM and license-boundary
record; the generic runtime image has its own complete dependency SBOM and
license inventory.

The application remains external to its generic runtime image. The separate
Linux AMD64 image is loaded before deployment, and the installed stack mounts
the web source read-only. Every permanent web start creates a fresh bounded
`/opt/nextjs/.next` tmpfs, runs `next build`, verifies the build, and executes
`next start` in the same container. Stopping and removing the container removes
all generated web build state. Nothing is enabled at boot.

Verify this extracted candidate before using either installer:

```bash
bash ./verify-ishikawa-release
```

Install the canonical schema into an empty application database:

```bash
bash ./database/install-schema \
  --database rag_catalog \
  --owner-role rag_owner \
  --ingest-role rag_ingest \
  --retrieval-role rag_retrieval
```

Install the application into a new operator-owned directory:

```bash
bash ./application/install-ishikawa \
  --install-root "$HOME/Documents/Ishikawa"
```

The installers verify their complete component manifests and fail closed. The
application installer refuses to merge with an existing installation. It does
not start services, enable boot autostart, initialize PostgreSQL, ingest source
documents, contact model endpoints, or store credentials.

PostgreSQL 16 with pgvector, the reviewed native Python dependencies, the
separate exact AMD64 Node/Next image, model connectivity, and approved runtime
credentials remain deployment prerequisites.
