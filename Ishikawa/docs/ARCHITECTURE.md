# Ishikawa As-Built Architecture

## System view

```text
Local browser
    |
    | HTTP 127.0.0.1:3000
    v
Next.js Chat UI in unchanged Node runtime container
    |
    | server-side HTTP 127.0.0.1:1384
    v
Native Ishikawa Retrieval API
    |                |                 |
    | read-only SQL  | HTTPS-compatible| HTTPS-compatible
    v                v                 v
Native PostgreSQL    Gemma endpoint    Nomic endpoint
127.0.0.1:5432       127.0.0.1:8000    127.0.0.1:8001
```

The browser knows only the Next.js origin. Next.js proxies chat requests to
the Retrieval API. The Retrieval API owns orchestration and calls PostgreSQL,
Gemma, and Nomic through configured server-side adapters.

Gemma and Nomic may physically run elsewhere. Their reachability, including
any operator-created forwarding, is outside Ishikawa. Ishikawa reads endpoint
URLs from YAML and fails readiness when they are unavailable.

## Ingestion view

```text
Operator configuration and PDFs
  |-- document_classes.yaml
  |-- document_catalog.yaml
  |-- config/ingestion/pending/BATCH.yaml
  `-- corpus/source/**/*.pdf
                 |
                 v
          ishikawa-ingest
                 |
                 | validate and plan affected documents
                 | extract with native Poppler tools
                 | normalize structural units
                 | create citable chunks
                 | measure and embed with Nomic
                 | validate complete candidates
                 v
      +--------------------------+
      |                          |
      v                          v
Protected host state       Native PostgreSQL
artifacts, reports,        catalog, publication,
work, quarantine           active search views
```

Ingestion is a one-shot native Python command, not a service. It processes
only documents listed in the selected manifest. One successful PostgreSQL
transaction makes that manifest's affected changes searchable. A failed or
quarantined batch leaves the previously active corpus unchanged.

## Runtime components

| Component | Form | Lifecycle | Default interface | Authority |
|---|---|---|---|---|
| PostgreSQL 16 with pgvector | native system service | on demand | `127.0.0.1:5432` | durable catalog and active search data |
| Ishikawa Retrieval API | native Python user service | on demand | `127.0.0.1:1384` | request validation and RAG orchestration |
| Ishikawa Chat UI | host-mounted Next.js source in one container | on demand | `127.0.0.1:3000` | browser experience and server-side proxy |
| Ingestion | native Python command | one shot | none | validated incremental publication |
| Gemma | deployment dependency | external | configured URL | scope, query resolution, and grounded generation |
| Nomic | deployment dependency | external | configured URL | document and singleton query embeddings |

None of the three application components starts at boot. The stack command
owns ordered start, readiness, status, rollback, and reverse-order stop.
The start order is PostgreSQL, then the Retrieval API, then the web container.

## Installed layout

```text
~/Documents/Ishikawa/
|-- application/
|   |-- python/ishikawa/       native application modules
|   `-- web/                   host-mounted Next.js source
|-- config/
|   |-- *.yaml                 product, deployment, and method profiles
|   `-- ingestion/
|       |-- pending/
|       |-- completed/
|       `-- rejected/
|-- corpus/source/             operator-managed PDFs
|-- docs/                      operating and design documentation
|-- scripts/                   installed operator commands
|-- systemd/                   final user unit definitions
`-- state/
    |-- artifacts/sha256/      accepted content-addressed artifacts
    |-- work/                  bounded ingestion workspaces
    |-- quarantine/            protected remediation evidence
    |-- reports/ingestion/     protected operator reports
    |-- logs/                  retrieval, metrics, and audit JSONL
    |-- run/                   owner-only sockets and lifecycle state
    `-- backups/               reserved protected backup output location
```

Live PostgreSQL files remain in the PostgreSQL-managed system location. They
are not stored beneath the application directory.

## PostgreSQL boundary

The final schema has three namespaces:

- `rag` owns catalog, ingestion, publication, structural, chunk, citation,
  embedding, relationship, and active-version records;
- `rag_private` owns artifact manifests, stage history, and quarantine; and
- `rag_search` exposes five security-barrier views for active documents,
  chunks, citations, embeddings, and relationships.

The `rag_ingest` role can perform the bounded publication workflow. The
`rag_retrieval` role receives only `SELECT` on `rag_search`. The Retrieval API
cannot ingest, publish, retire, or mutate documents.

## Retrieval and answer flow

```text
Versioned chat request
    |
    v
Schema and size validation
    |
    v
Direct-injection gate --> reject when unsafe
    |
    v
Deterministic known-document route
    |                    |
    |                    `--> clarify vague or ambiguous document request
    |
    `--> recognized identifier proceeds without model scope
    |
    v
Gemma scope decision for all other questions --> clarify or reject
    |
    v
Standalone query resolution when context requires it
    |
    +--> exact document/page lane
    +--> PostgreSQL English lexical lane
    `--> Nomic embedding + pgvector cosine lane
              |
              v
       deterministic RRF fusion
              |
              v
 structural-group collapse and representative-to-atomic expansion
              |
              v
 authorization, relationship, relevance, and sufficiency checks
              |
              v
 deterministic evidence reconstruction and exact token counting
              |
              v
 grounded Gemma generation
              |
              v
 strict segment/citation validation
              |
              v
 client-safe answer with grouped source excerpts
```

The exact lane retains only its best candidate. Lexical and vector lanes each
retain at most 20 candidates. Fusion uses exact/lexical/vector weights
`1/2/4` and reciprocal-rank constant 60, collapses ordinary non-exact results
to at most 20 structural groups, and expands selected scoring-only
representatives to authoritative atomic evidence. Exact-match priority remains
a separate deterministic boundary. A recognized self-declared document
identifier plus an unambiguous page can route directly to that active
document's cited page. Zero owners preserve ordinary retrieval; multiple
owners require clarification. There is no learned reranker.

Procedure reconstruction uses stored document-local sequence and structural
metadata. An explicitly requested complete procedure is returned completely
or receives a context-limit outcome; it is not silently clipped.

Grounded Gemma generation is constrained by an exact JSON Schema whose
citations are limited to the accepted evidence identifiers for that request.
The application validator remains authoritative. Gemma returns one ordered
sequence of citation-bearing segments; Ishikawa renders that sequence as
flowing prose without a competing answer field or duplicate claim list. One
retry is permitted only after a generation transport or invalid-response
failure.

## Trust and access model

Version 1 is a single-host, single-corpus application with no application
login or per-user permissions. Loopback is the access boundary. Anyone with
an allowed session on the host may attempt to use the application.

The deployment provides credentials through protected environment values.
Configuration stores only credential variable names. The UI never receives
database or model credentials. Gemma and Nomic receive no database or
document-store access.

## Observability

The Retrieval API writes protected local JSONL records:

- `retrieval.jsonl`: operational and permitted diagnostic events;
- `metrics.jsonl`: content-free bounded measurements; and
- `audit.jsonl`: logging-control and retention actions.

Default and debug profiles exclude document content. Verbose capture requires
an explicit reason, scope, and expiration and cannot survive service restart.
Default retention is 30 days for retrieval and metrics and 90 days for audit.

## Deployment boundary

The portable release contains the final application and final fresh-install
database schema. Native operating-system prerequisites, the Node runtime
image, source documents, credentials, active database contents, logs,
quarantine evidence, forwarding sessions, and model services are not embedded
in the release.
