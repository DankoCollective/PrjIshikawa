# Ishikawa Application Definition

## Product

Ishikawa is a locally hosted retrieval-augmented knowledge application. It
answers professional questions from an operator-approved PDF corpus and
returns page-anchored source excerpts with grounded answers.

The product display name is configuration. `Ishikawa` is the v1 default.

## Primary outcomes

Ishikawa must:

- accept explicitly cataloged and classified PDF documents;
- preserve stable logical document identity across revisions;
- extract and normalize useful document structure;
- create deterministic, citable retrieval chunks;
- publish only validated document changes;
- search exact references, lexical content, and vector similarity together;
- reject unsafe, out-of-scope, unsupported, or insufficient requests;
- generate answers only from validated cited evidence; and
- expose a simple local Chat UI and a separate local Retrieval API.

## Users and operators

An application user submits questions through the Chat UI and reviews answers
and cited excerpts.

An operator installs the application, maintains configuration and document
registries, prepares ingestion manifests, starts and stops the stack, reviews
reports and quarantine evidence, and manages local retention.

Version 1 does not identify individual application users.
There is no application login, role system, or per-user document authorization.
Anyone who can reach the loopback-bound service from an allowed host session
can use the complete active corpus.

## Functional boundary

Ishikawa owns:

- PDF validation, extraction, normalization, structural chunking, token
  measurement, and embedding orchestration;
- document, revision, publication, quarantine, and relationship records;
- exact, lexical, and vector retrieval plus deterministic fusion;
- scope, injection, sufficiency, relevance, reconstruction, citation, and
  grounded-generation enforcement;
- the Retrieval API and Chat UI contracts;
- protected local operational logs, metrics, and audit records; and
- explicit operator-started lifecycle control.

The deployment owns:

- the operating system and native packages;
- the PostgreSQL cluster and database roles;
- the architecture-matching Node runtime image;
- Gemma and Nomic serving;
- endpoint reachability or port forwarding;
- credential delivery; and
- host access, firewall, backup, and recovery policy.

## Runtime interfaces

The default v1 interfaces are:

| Interface | Default | Consumer |
|---|---:|---|
| Chat UI | `http://127.0.0.1:3000` | local browser |
| Retrieval API | `http://127.0.0.1:1384` | Next.js server |
| PostgreSQL | `127.0.0.1:5432` | ingestion and retrieval processes |
| Gemma | `127.0.0.1:8000` | Retrieval API |
| Nomic | `127.0.0.1:8001` | ingestion and Retrieval API |

The browser communicates only with Next.js. It never receives model,
database, or Retrieval API credentials.

## Content and data classes

The operator supplies:

- the document-class registry;
- the logical document catalog;
- incremental ingestion manifests; and
- source PDFs beneath the configured corpus root.

Ishikawa creates protected extracted and normalized artifacts, chunks,
embeddings, database records, reports, quarantine evidence, logs, metrics, and
audit records. Embeddings remain sensitive derived data even though they are
not raw source text.

## Supported first-version behavior

- PDF input only.
- Operator-assigned document classes.
- One stable document key per logical document.
- Incremental add, revise, reprocess, reuse, retire, and remediate behavior.
- Atomic publication per ingestion manifest.
- Structured paragraphs, lists, definitions, tables, form fields, checkbox
  groups, headings, references, page furniture, and verified blank pages.
- Exact-reference, PostgreSQL English full-text, and Nomic cosine retrieval.
- Deterministic reciprocal-rank fusion with no learned reranker.
- One-hop reviewed document relationships.
- Complete-procedure reconstruction when explicitly requested and resolvable.
- Nonstreaming, cited answers through one versioned chat endpoint.

## Explicit non-goals for version 1

- automatic content-based document classification;
- OCR for image-only PDFs;
- arbitrary office-document formats;
- recursive relationship traversal;
- model-authoritative retrieval, relevance, or citation decisions;
- application user accounts or per-user permissions;
- browser access to original-document open or download functions;
- LAN exposure by default;
- service startup at boot; and
- encryption-specific application behavior.

Encryption and verified identity can be added later without changing the
current requirement that secrets remain outside YAML and model access remain
separated from document and database access.

## Success conditions

The application is operational only when:

- all three runtime components are ready;
- an active searchable corpus exists;
- Gemma and Nomic health checks pass;
- retrieval uses only active, authorized database views;
- every displayed answer segment resolves to one or more included citations;
- stopping the stack returns every managed component to the stopped,
  boot-disabled posture.
