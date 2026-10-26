# Ishikawa

`Ishikawa` is the proposed product, Chat UI, portable application package, and
host-directory name for the Phase 28 knowledge-assistant implementation.

The current product documentation entry points are:

- [`docs/OPERATOR_GUIDE.md`](docs/OPERATOR_GUIDE.md) for routine operation;
- [`docs/COMMAND_SHEET.md`](docs/COMMAND_SHEET.md) for compact commands;
- [`docs/APPLICATION_DEFINITION.md`](docs/APPLICATION_DEFINITION.md) for scope;
- [`docs/APPLICATION_DESIGN.md`](docs/APPLICATION_DESIGN.md) for design rules;
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the as-built system; and
- [`docs/PRODUCT_PRESENTATION_CONFIGURATION.md`](docs/PRODUCT_PRESENTATION_CONFIGURATION.md)
  for every `product.yaml` key, formatting token, and example; and
- [`docs/CHUNKING_INGESTION_RETRIEVAL.md`](docs/CHUNKING_INGESTION_RETRIEVAL.md)
  for the complete RAG method.

This directory contains the locally accepted configuration and planning slice,
the frozen and target-qualified incremental PostgreSQL writer, and the
accepted extraction, normalization, structural chunking, token-measurement,
and embedding pipeline. The writer takes
already-extracted, already-chunked, and already-embedded candidate records;
checks the exact schema-version-5 identity and current published state;
and performs quarantine, skip, publication, retirement, and remediation
linkage through one parameterized transaction. The normalization pipeline
consumes the accepted raw Poppler artifact and creates deterministic anchored
headings, paragraphs, definitions, list items, structured tables, form fields,
checkbox groups, and page furniture. The chunker creates deterministic,
citation-anchored paragraph, list, definition, table, form, and checkbox
candidates with zero blind body overlap. Exact Nomic token measurement and
embedding have passed. The exact, PostgreSQL lexical, and pgvector cosine
retrieval lanes plus deterministic RRF fusion are implemented, and the
amended held-out calibration passed Script `37`. The deterministic `G13`
relationship registry, resolver, and one-hop traversal passed Script `39`.
Atomic relationship persistence, audited-override storage, and read-only
one-hop query proof passed operator-executed Script `40`. Operator-executed
Script `41` applied the same schema-v4 migration to the accepted empty
application catalog. The deterministic evidence-reconstruction foundation,
deployed Gemma tokenizer identity, initial 32,768-token application budget,
deterministic grounded-generation request, and its exact 884-token offline
measurement are accepted through Script `46`. The native generation transport
and strict grounded-response validator are accepted through Script `47`.
Script `48` retained the first live response after a safe compatibility block;
the endpoint reported 885 prompt tokens. The frozen compatibility correction
passes 155 local tests, and Script `49` is source-ready to accept that retained
response without another model call. The retrieval API and web serving remain
separate work.

The versioned pre-retrieval scope-classifier profile, deterministic request
builder, typed prior-source references, three-decision output validator, and
scope-versus-injection boundary are accepted through Script `50`. Script `51`
accepted the exact request at 526 prompt tokens and 654 tokens including the
classifier response reserve. Script `52` accepted the native scope transport
and one bounded live synthetic classification. Script `53` accepted the
separate deterministic direct- and indirect-injection gate. The fail-closed
post-retrieval evidence-sufficiency gate is source-ready in Script `54`.

The proposed host root is:

```text
~/Documents/Ishikawa/
```

The durable proposed architecture, configuration responsibilities, ingestion
workflow, quarantine and retirement behavior, repository layout, and current
implementation boundary are recorded in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

The v1 document-class registry, document catalog, and incremental ingestion
manifest contracts were frozen by the operator on 2026-10-19. Their exact
contracts and sanitized templates are recorded in
[`docs/CONFIGURATION_CONTRACTS.md`](docs/CONFIGURATION_CONTRACTS.md) and
`config/templates/`.

The v1 cross-file validation, affected-document planning, operator reporting,
quarantine, remediation-linkage, source-symlink rejection, and atomic-batch
contract was frozen by the operator on 2026-10-19 and is recorded in
[`docs/VALIDATION_AND_QUARANTINE_CONTRACT.md`](docs/VALIDATION_AND_QUARANTINE_CONTRACT.md).

The schema-v3 pipeline-writer boundary and its accepted Script `31` evidence
are frozen in
[`docs/PIPELINE_WRITER_CONTRACT.md`](docs/PIPELINE_WRITER_CONTRACT.md).

The calibrated three-lane retrieval settings, separate chunk-method and
retrieval-profile identities, PostgreSQL lexical behavior, and change
consequences are frozen in
[`docs/RETRIEVAL_PROFILE.md`](docs/RETRIEVAL_PROFILE.md).

The immutable v1 and v1.2 packages retain their accepted retrieval profiles.
The v1.3 working source implements frozen decision `V13-32`: exact depth `1`,
lexical/vector/fused depths `20`, RRF constant `60`, exact/lexical/vector
weights `1/2/4`, retrieval-only section/page representatives, and
document-local duplicate canonicalization. Selected representatives expand to
ordered authoritative atomic evidence before hydration or model use. Complete
source regression, fresh 60-body/8-header retrieval qualification, the full
Retrieval API/Gemma gate, and deployment-candidate assembly remain required.

The deterministic explicit-reference registry, exact resolution, quarantine,
audited-exception, supersession, and one-hop traversal boundaries are recorded
in [`docs/RELATIONSHIP_CONTRACT.md`](docs/RELATIONSHIP_CONTRACT.md).

Document grouping, exact deduplication, citation preservation, procedure
reconstruction, diversity, atomic context assembly, and explicit context-limit
behavior are recorded in
[`docs/EVIDENCE_RECONSTRUCTION.md`](docs/EVIDENCE_RECONSTRUCTION.md).

Local implementation status:

1. restricted safe-YAML loader: implemented and locally tested;
2. four exact configuration validators, including the calibrated method
   profile: implemented and locally tested;
3. cross-file validation and all five affected-document planning actions:
   implemented and locally tested against an in-memory published-state
   boundary;
4. validation-only protected reporting, stable outcome/reason classification,
   source-symlink rejection, and atomic-batch blocking: implemented and
   locally tested;
5. migration `0002`: locally proven, applied on EmceeDanko, and accepted; and
6. incremental writer models and transaction orchestration: implemented and
   locally tested with synthetic prepared artifacts, then accepted through a
   disposable native-PostgreSQL/Psycopg integration on EmceeDanko; and
7. PDF extraction: accepted from EmceeDanko Poppler capture plus held-out local
   evaluation; normalization and structural-unit creation: accepted through
   Script `26`; and
8. structural chunk candidates and metadata: accepted through Script `27`;
9. exact Nomic token measurement and embedding: accepted for the amended 126
   candidates through Script `36`; and
10. exact, native PostgreSQL full-text, and pgvector cosine retrieval with
    deterministic RRF: accepted by Script `37` against all six held-out cases
    and all 13 required citations; and
11. calibrated retrieval-profile configuration and distinct identity:
    implemented and accepted by Script `38` with 90 tests and a retained local
    freeze receipt; and
12. deterministic relationship registry, exact reference resolution,
    ambiguity quarantine, exceptional overrides, supersession identity, and
    authorized one-hop traversal: implemented, locally passing 106 tests, and
    accepted by operator-executed Script `39`; and
13. schema-v4 audited-override columns plus atomic relationship writing and
    active-view traversal: accepted against a disposable native-PostgreSQL
    database through operator-executed Script `40`; and
14. migration `0004` application to the accepted empty `rag_catalog`:
    accepted through operator-executed Script `41`; and
15. deterministic evidence-reconstruction foundation: accepted through
    operator-executed Script `42`;
16. exact deployed Gemma tokenizer and chat-template identity: accepted
    through operator-executed Script `43` without a model call;
17. initial 32,768-token reconstruction budget and all limit boundaries:
    accepted through operator-executed Script `44`;
18. deterministic grounded-generation request builder: accepted through
    operator-executed Script `45`;
19. exact composed-request measurement: accepted through operator-executed
    Script `46` at 884 prompt tokens and 2,932 tokens including the answer
    reserve; and
20. configurable native-HTTP generation transport and strict grounded-response
    validation: accepted through operator-executed Script `47`; and
21. one bounded live synthetic grounded-generation observation: retained by
    Script `48` with its raw response protected after a compatibility block;
22. strict nullable-field, isolated-JSON-fence, and claims-derived-answer
    correction: frozen, implemented, and locally passing 155 tests; and
23. checksum-bound retained-response acceptance and stale-directory cleanup:
    accepted through Script `49`, with no second model call or model-key
    prompt; and
24. pre-retrieval scope-classifier profile, request builder, and strict
    `allow` / `needs_clarification` / `out_of_scope` decision validator:
    accepted through operator-executed Script `50`; and
25. exact accepted scope-classifier request measurement: accepted through
    operator-executed Script `51` at 526 prompt tokens and 654 total reserved
    tokens; and
26. native scope transport and one bounded live synthetic classifier
    qualification: accepted through operator-executed Script `52`; and
27. deterministic direct- and indirect-injection scanning across question,
    conversation, and retrieved-content origins: accepted through
    operator-executed Script `53`; and
28. fail-closed post-retrieval evidence sufficiency with mandatory calibrated
    relevance: implemented, locally passing 195 tests, and source-ready in
    Script `54`; and
29. protected relevance calibration: Script `55` accepted six responsive and
    six nonresponsive cases, Script `56` accepted twelve singleton Nomic query
    embeddings, and the first Script `57` execution safely exposed a stale
    schema-v3 preflight before database creation. Script `58` is source-ready
    with the accepted schema-v4 preflight, disposable schema-v4 correction,
    complete fifteen-module target package, and staged-package import proof.
    The repaired execution passed, covered all 13 responsive citations, and
    proved that raw vector and fused score ranges overlap; it transferred no
    calibration truth and selected no threshold. Its first
    target execution safely exposed and cleaned up the incomplete package,
    after which Script `58` was repaired in place. The resulting frozen
    correction keeps those retrieval lanes and RRF unchanged and adds only a
    protected PostgreSQL English-lexeme support measurement across fused
    depths 1, 3, 5, 10, and 20. Script `59` passed operationally, recorded
    supported and unsupported question lexemes, selected no threshold, and
    gave Gemma no sufficiency authority. No depth strictly separated the six
    responsive and six nonresponsive cases, so retrieval-text lexeme coverage
    is rejected as a standalone sufficiency threshold. The operator froze one
    bounded correction: measure the same fused results against the complete
    citable envelope of chunk text, document display name, assigned class,
    structural path, and citation page. Script `60` passed operationally and
    strictly separated the protected cases at depths 1, 3, 5, and 10. It did
    not separate them at depth 20, change retrieval rank or exact routing, give
    Gemma authority, select a threshold, or publish the candidate rule. The
    operator then froze depth `3` and an exact minimum support ratio of `3/5`.
    The versioned runtime relevance producer, PostgreSQL citable-envelope
    measurement, and typed sufficiency-gate integration are implemented and
    locally pass the 202-test suite. Operator-executed Script `61` bound and
    replayed the accepted Script `60` evidence without target or model contact,
    qualified all 12 protected cases, and accepted relevance-profile identity
    `2a29f2499029a6e6a8f56f199b91d1a32dbab280bb9a07d502423af838804c28`;
    and
30. versioned nonstreaming multi-turn chat request and client-safe response
    envelopes: implemented and locally passing the 212-test suite. Script `62`
    accepted all eight response statuses, citation
    allowlisting, source grouping, structured source follow-ups, bounded
    history and filters, and private-field exclusion without starting a
    service; and
31. the frozen **Ishikawa Retrieval API** identity, its ownership as a
    separately run native Python process inside the Ishikawa package, and its
    fail-closed orchestration order: implemented and locally passing the
    223-test suite. Script `63` accepted short-circuiting, safe error mapping,
    and claims-derived response construction without starting a listener or
    contacting a dependency; and
32. native standard-library HTTP boundary adapters for singleton Nomic query
    embedding and Gemma scope and grounded generation: implemented and locally
    passing the 233-test suite. Script `64` accepted these adapters against the
    accepted Nomic embedding-space and Script `63` service evidence without
    target, database, or model contact; and
33. standalone contextual-query resolution with code-owned filters, trusted
    structured source mapping, deterministic direct-query bypass, and
    clarification before retrieval: implemented and locally passing the
    246-test suite. Operator-executed Script `65` accepted this insertion into
    the retrieval-service order without target or model contact; and
34. the first concrete native read-only PostgreSQL retrieval port: implemented
    and accepted through Script `66`; relationship and complete-procedure
    retrieval are accepted through Script `67`; and the complete adapter
    passed against a disposable native PostgreSQL database on the application
    host through Script `68`; and
35. the bounded standard-library HTTP listener and strict deployment profile:
    implemented and accepted through operator-executed Script `69`; and
36. complete configuration-to-runtime assembly, including exact vLLM Gemma
    tokenization, protected environment providers, read-only PostgreSQL
    connection and source-resolution boundaries, every concrete dependency
    adapter, orchestration, and listener construction: implemented and locally
    passing the 270-test suite. Script `70` was accepted as a local-only
    qualification with no credential read or dependency contact; and
37. configured target runtime through the actual HTTP boundary: accepted by
    Scripts `71` through `75`, culminating in one professional question that
    ran scope, singleton embedding, read-only empty-catalog retrieval, and
    exact tokenization before returning `insufficient-evidence` without
    grounded generation; and
38. operator-ingestion control plane: implemented and locally passing the
    279-test suite. Script `76` proves validation-only isolation, changed-
    document-only production, reuse, quarantine, private reports, and the
    existing atomic-writer boundary with injected non-networking ports.

Run the complete local acceptance suite from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/Ishikawa/scripts/run-local-validation-tests.sh
```

The original accepted local run passed 52 tests with Python `3.12.3` and
PyYAML `6.0.1`. The suite now contains 279 tests, including the incremental
writer, calibrated retrieval profile, deterministic relationship and
reconstruction contracts, grounded-generation request builder, native
generation transport, and strict response validator. Migration
`0002` also passed its disposable local upgrade,
fresh-install, rollback, ownership, quarantine-linkage, and privilege tests.
Its independent command is:

```bash
bash ./phase-28-apisachi-tokuli/scripts/21_test_ingestion_ownership_migration.sh
```

The operator confirmed the checksum-identical underlying test before the
numbered wrapper was added, so Script `21` is accepted without a rerun.
Operator-executed Script `22` applied the migration on EmceeDanko. Script `23`
is the numbered local gate for the incremental writer:

```bash
bash ./phase-28-apisachi-tokuli/scripts/23_test_incremental_ingestion_writer.sh
```

Script `23` is local-only. It does not contact EmceeDanko or PostgreSQL and
does not read source documents beyond synthetic test fixtures. The
operator-executed Script `24` subsequently exercised that writer through
target-native Psycopg against a disposable database and passed add, reuse,
revise, reprocess, quarantine, remediation, rollback, retirement, active-view,
and retrieval-role checks. It removed the disposable database, preserved the
accepted `rag_catalog`, stopped PostgreSQL, and cleaned temporary target state.
No Script `24` rerun is required.

The accepted Script `24` proof is limited to persistence. Script `25` now also
accepts exact Ubuntu Poppler extraction for all six synthetic PDFs and 27
pages. Do not rerun Script `25` in the normal workflow.

Script `26` passed and its accepted normalized artifact is retained. Do not
rerun it in the normal workflow. Script `27` is the local structural
chunk-candidate gate:

```bash
bash ./phase-28-apisachi-tokuli/scripts/27_create_structural_chunk_candidates.sh --run
```

Normalization is recorded in
[`docs/NORMALIZATION_AND_STRUCTURAL_UNITS.md`](docs/NORMALIZATION_AND_STRUCTURAL_UNITS.md),
and candidate construction is recorded in
[`docs/STRUCTURAL_CHUNK_CANDIDATES.md`](docs/STRUCTURAL_CHUNK_CANDIDATES.md).
Script `27` does not call Nomic or publish data. Scripts `28` through `37`
subsequently qualified token accounting, embeddings, schema-v3 persistence,
the three retrieval lanes, fusion, and held-out calibration. Reconstruction,
the retrieval API, UI, portable installation, and the consolidated
fresh-install schema remain later gates.

Script `40` passed the disposable relationship-persistence proof without
changing the accepted `rag_catalog`. Script `41` then applied migration `0004`
to that still-empty accepted database and proved its exact four-record ledger,
audit-field constraints, retrieval isolation, restart persistence, and final
stopped state. Scripts `42` and `44` are local-only. Script `43` contacted the
approved target only to qualify the deployed tokenizer in an isolated,
network-disabled container and did not call Gemma. Script `45` accepted the
local grounded request structure and retained one protected synthetic request.
Script `46` measured that exact request with the accepted deployed tokenizer
without calling Gemma. Script `47` accepted local transport construction and
response validation without a network or model call. Script `48` made the
first bounded live call and retained its response after a safe compatibility
block. Script `49` revalidates that response without another model call and
performs the guarded cleanup left by Script `48`.
Script `50` accepts the local scope-classifier contract and retains its exact
synthetic request. Script `51` measures that checksum-bound request in the
same isolated, network-disabled tokenizer harness used by Script `46`.
Script `52` adds the native scope transport and performs one bounded live call
whose complete envelope and three-field decision are validated before the
protected result is accepted.
Script `53` qualifies the separate deterministic injection gate locally; it
does not call Gemma or contact a remote system.
Script `54` qualifies deterministic sufficiency outcomes locally and refuses
to treat candidate presence as proof of relevance.
Scripts `55` and `56` accepted the protected relevance case contract and its
singleton Nomic embeddings. Script `57` safely blocked on its stale schema-v3
preflight. Script `58` is the corrected disposable-PostgreSQL retrieval
observation gate and now locally proves its complete target import closure;
calibration labels and expected citations remain local. The repaired Script
`58` passed operationally, but its responsive and nonresponsive vector and
fused score ranges overlap, so no scalar relevance threshold is accepted.
Script `59` is the accepted follow-on measurement. It preserved retrieval
ranking and used native PostgreSQL English lexemes to measure question-term
support at fused depths 1, 3, 5, 10, and 20 without a model call. Its ranges
overlapped at every depth, so it selected no threshold and did not publish a
relevance profile. Script `60` is the accepted citable-envelope follow-on. It
exposed strictly separating rule candidates at depths 1, 3, 5, and 10 while
correctly leaving the depth and threshold selection for explicit review. The
frozen choice is depth `3` with the exact integer comparison
`supported_count * 5 >= question_lexeme_count * 3`. Script `61` locally
qualified that versioned runtime rule and its sufficiency-gate integration
against the accepted protected observations. Script `62` accepted the frozen
versioned chat API contract. Script `63` accepted the frozen Ishikawa
Retrieval API name, separate-process boundary, and local orchestration
contract. Script `64` accepted the native singleton query-embedding,
scope-classification, and grounded-generation adapters. Script `65` accepted
standalone contextual-query resolution and its position between scope
classification and retrieval. Scripts `66` through `69` accepted the native
PostgreSQL retrieval port, relationship and complete-procedure paths,
target-native complete adapter, and native loopback HTTP listener. Script `70`
is the next local gate for complete configuration-to-runtime assembly.

The exact scope-classifier boundary and its reason-code contract are recorded
in [`docs/SCOPE_CLASSIFIER_CONTRACT.md`](docs/SCOPE_CLASSIFIER_CONTRACT.md).
The versioned multi-turn chat request, client-safe response, source-group,
citation, status, and private-field boundaries are recorded in
[`docs/API_CONTRACT.md`](docs/API_CONTRACT.md).
The frozen service identity, ownership, lifecycle, orchestration order, and
short-circuit behavior are recorded in
[`docs/RETRIEVAL_API_SERVICE.md`](docs/RETRIEVAL_API_SERVICE.md).
The native query-embedding, scope, and generation adapter boundaries are
recorded in
[`docs/NATIVE_DEPENDENCY_ADAPTERS.md`](docs/NATIVE_DEPENDENCY_ADAPTERS.md).
The original/resolved-query boundary, structured source mapping, filter
ownership, and clarification behavior are recorded in
[`docs/QUERY_RESOLUTION.md`](docs/QUERY_RESOLUTION.md).
The read-only PostgreSQL boundary, resolved-query-only embedding path,
candidate filtering, hydration, and client source identity are recorded in
[`docs/POSTGRES_RETRIEVAL_ADAPTER.md`](docs/POSTGRES_RETRIEVAL_ADAPTER.md).

The current persistent-service implementation also includes the final native
Retrieval API entrypoint, complete readiness checks, classified JSONL logging,
operator logging control, content-free metrics, bounded retention, optional
retention timer, and a boot-disabled systemd user unit. The Chat UI source now
lives under `application/web/` and is documented in
[`docs/CHAT_UI.md`](docs/CHAT_UI.md). It uses the separate pinned Linux AMD64
Node 24/Next.js image with read-only host bind mounts, presents bounded multi-turn chat and
structured citations, and reaches retrieval only through its server-side
proxy. The final explicit `scripts/ishikawa-stack` command starts PostgreSQL,
the native Retrieval API, and the host-mounted web container in dependency
order, builds bounded ephemeral `.next` state, runs `next start`, requires
readiness between layers, and stops them in reverse order. Its
durable contract is recorded in
[`docs/STACK_CONTROL.md`](docs/STACK_CONTROL.md).
