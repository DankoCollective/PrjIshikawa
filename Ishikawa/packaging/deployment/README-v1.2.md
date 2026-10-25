# Ishikawa v1.2 deployment candidate

This is one complete Ishikawa v1.2 application-and-database deployment
candidate. It contains the final application payload and the final fresh-install
database schema. It contains no schema ancestors, migrations, repair programs,
source documents, credentials, model responses, operating-system packages, or
container images.

Ishikawa v1.2 retains deterministic known-document clarification and the
accepted three-lane retrieval profile. When a question contains exactly one
recognized self-declared document identifier and one unambiguous page number,
application code resolves the active document owner and routes directly to its
cited page. No owner preserves ordinary retrieval; multiple owners require
clarification and never guess.

The accepted retrieval profile uses exact-reference depth `1`, lexical and
vector depth `20`, fused depth `20`, reciprocal-rank-fusion constant `60`, and
exact/lexical/vector lane weights `1/1/4`. It uses no learned reranker.

Grounded Gemma generation uses vLLM's native JSON Schema response constraint.
The schema permits only the expected answer and claim fields and restricts
citation identifiers to the accepted evidence for that request. Ishikawa's
strict response validator remains authoritative. Generation may retry exactly
once after a transport or invalid-response failure; other failures are not
retried. The database schema and embedding space remain unchanged.

Before installation, provide the approved native dependencies, PostgreSQL 16
with pgvector, an empty application database with its three roles, the
architecture-matching Node 24/Next.js image, and any required model endpoint
connectivity. Those deployment-specific prerequisites remain external because
they differ by operating-system release and machine architecture.

First verify the complete candidate:

```bash
bash ./verify-ishikawa-v1.2
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
  --install-root "$HOME/Documents/Ishikawa-v1.2-candidate"
```

Both component installers verify their own manifests and fail closed. The
database installer creates the complete empty version-4 schema in one
transaction. The application installer publishes a new directory atomically
and refuses to merge with an existing installation. Services remain stopped
and boot-disabled after installation.
