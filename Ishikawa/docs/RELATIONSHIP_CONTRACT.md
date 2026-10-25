# Deterministic Relationship Contract

## Status and scope

The operator froze `G13` as a KISS relationship contract. Operator-executed
Script `39` accepted the local implementation against separate held-out
synthetic truth. Operator-executed Script `40` accepted the disposable target
persistence proof. Script `41` applies the proven schema-v4 change to the
accepted empty application catalog.

The first slice supports only these relationship families:

- an explicit reference from one structural unit to a logical corpus
  document;
- an explicit reference that an audited exception marks as external; and
- a logical document superseding one fixed prior document version.

Gemma does not discover edges. Routine ingestion does not require an operator
relationship manifest. A relationship type, endpoint behavior, or traversal
change creates a new relationship-method-profile identity and requires
relationship regeneration and retrieval requalification.

## Registry

`config/templates/relationship_types.yaml` is the human-maintainable registry.
It is bound to the already-frozen calibrated retrieval-profile identity. The
validated registry defines canonical types and display names, allowed endpoint
kinds, target-version behavior, retrieval influence, and outgoing one-hop
traversal.

The sole traversable type is `explicit_reference.document`. External
observations are the non-traversable `explicit_reference.external` subtype of
the same explicit-reference family. `supersedes` is also non-traversable;
retrieval must not use it to expose an inactive prior version.

Canonical JSON plus domain-separated SHA-256 produces both a registry identity
and a relationship-method-profile identity. Secrets, endpoints, paths, and
deployment settings are excluded.

## Detection and resolution

The common chunker retains identifier-shaped lexical fields for exact search.
Not every identifier is a document relationship. Request, review, event, and
other record-instance identifiers remain searchable but do not become graph
edges merely because they look like identifiers.

Relationship discovery therefore uses two deterministic passes:

1. Find conservative document self-declarations, such as a policy-number
   declaration or a standalone form number, across the candidate corpus.
2. Treat physically present identifier text as a document-reference candidate
   only when at least one candidate document declares the same identifier.

Resolution is exact after case and whitespace normalization:

- one different owner produces an accepted document edge;
- the source document's own declaration is ignored rather than made a self
  edge;
- multiple owners are unresolved and quarantine the affected document;
- a selected relationship candidate with no owner is unresolved and
  quarantined; and
- no target is selected by fuzzy text, vector similarity, or model judgment.

An audited exceptional override may bind one exact evidence identity to one
known catalog document or mark it external. The override must be reevaluated
through a new candidate ingestion. An unused, duplicate, or unknown-target
override fails closed.

The current synthetic fixture contains three identifier observations that are
record-instance IDs rather than declared document IDs. The qualification gate
counts them but does not create relationships from them.

## Identity and provenance

Every edge identity binds the relationship type, typed directed endpoints,
source evidence citation, and relationship-registry identity. Every accepted
relationship retains source artifact-set identity, detection method, review
status, and target behavior.

A logical document target resolves to the active authorized document version
at request time. A supersedes target remains the exact prior version and never
silently repoints.

## Retrieval traversal

Traversal occurs after direct exact/lexical/vector fusion. It is outgoing and
limited to one hop. The implementation:

- removes unauthorized seeds before traversal;
- admits only allowlisted relationship types;
- removes unauthorized targets before returning provenance;
- does not revisit seed or already-returned endpoints;
- deduplicates repeated edges and target documents; and
- records seed, edge, direction, resolved target version, evidence citation,
  and `explicit_reference_one_hop` inclusion reason.

Relationship-derived evidence never claims a lexical, vector, or exact-search
score. Reconstruction and final context selection remain `G14` work.

## Script 39 through 41 boundaries

Script `39` runs the complete 106-test local suite. It checksum-binds the
accepted 126-candidate synthetic chunk artifact and separate held-out
relationship truth, validates six document declarations and deterministic
resolution, and requires zero unresolved synthetic document references plus
all five held-out relationships and traversals.

It performs no SSH, model call, database access, package change, secret
processing, operator relationship-manifest processing, or source-text output.
It retains only a content-free protected report. The operator-executed run
passed with 27 accepted internal edges, 17 ignored self declarations, zero
unresolved references, and all five held-out traversals covered.

Script `40` adds only the two schema-v4 fields required to preserve the audit
identity and reason for an exceptional operator override. Its target proof
applies schema version 5 to a disposable database, writes the accepted
synthetic documents and relationships atomically, verifies the read-only
active relationship view and one-hop traversal, then drops the disposable
database. It must prove the accepted schema-v3 `rag_catalog` is unchanged and
return PostgreSQL to its stopped, inactive, boot-disabled state. The
operator-executed run passed with 27 persisted active relationships, all five
held-out relationship and traversal cases covered, no unresolved references,
the temporary database removed, and the accepted database unchanged.

Script `41` is the separate migration gate for the accepted empty database.
Before target contact, it reruns the 106-test application suite and a
disposable migration test that proves ordered schema-v3 upgrade, rollback for
wrong migration order, refusal to invent provenance for a legacy unaudited
operator override, field constraints, retrieval-role isolation, and restart
persistence. On the target it may apply only the checksum-pinned migration
`0004`, verifies the exact four-record migration ledger and zero application
content, then returns PostgreSQL to its stopped, inactive, boot-disabled
state. It does not install packages, change roles or databases, ingest
documents, or call a model. The operator-executed run passed, applied migration
`0004`, retained zero application-content rows, and returned PostgreSQL and
the temporary target state to their accepted conditions.
