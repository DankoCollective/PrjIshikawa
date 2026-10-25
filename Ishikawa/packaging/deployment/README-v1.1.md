# Ishikawa v1.1 deployment candidate

This is one complete Ishikawa v1.1 application-and-database deployment
candidate. It contains the final application payload and the final fresh-install
database schema. It contains no schema ancestors, migrations, repair programs,
source documents, credentials, model responses, operating-system packages, or
container images.

Ishikawa v1.1 adds deterministic known-document routing before scope
classification. An exact catalog display name or a unique PostgreSQL English
lexeme match can bind a question to one document. A vague request about that
document returns a document-scoped clarification instead of expanding across
related documents.

The accepted retrieval profile uses exact-reference depth `1`, lexical and
vector depth `20`, fused depth `20`, reciprocal-rank-fusion constant `60`, and
exact/lexical/vector lane weights `1/1/4`. It uses no learned reranker. Grounded
Gemma generation may retry exactly once after a transport or validated-response
failure; unrelated dependency, security, scope, retrieval, and evidence
failures are never retried. A second generation failure remains temporarily
unavailable. The database schema and model interfaces remain unchanged.

Before installation, provide the approved native dependencies, PostgreSQL 16
with pgvector, an empty application database with its three roles, the
architecture-matching Node 24/Next.js image, and any required model endpoint
connectivity. Those deployment-specific prerequisites remain external because
they differ by operating-system release and machine architecture.

First verify the complete candidate:

```bash
bash ./verify-ishikawa-v1.1
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
  --install-root "$HOME/Documents/Ishikawa-v1.1-candidate"
```

Both component installers verify their own manifests and fail closed. The
database installer creates the complete empty version-4 schema in one
transaction. The application installer publishes a new directory atomically
and refuses to merge with an existing installation. Services remain stopped
and boot-disabled after installation.

