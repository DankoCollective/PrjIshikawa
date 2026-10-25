# Phase 28: Apisachi Tokuli

## Purpose

This phase owns the Apisachi Tokuli product and the decisions and artifacts for
its document classification, extraction, normalization, chunking, ingestion,
embedding, persistence, retrieval, reconstruction, citation, and abstention
method. It also owns the retrieval API contract and the integration of the
YAML-named browser product currently mocked as Knowledge Assistant.

Anderson assessments are design inputs. Phase 28 reviews, decides, implements,
and validates the resulting method; it does not treat Anderson-generated code
as accepted source.

## Current Status

The phase contains an approved Knowledge Assistant UI mockup, a frozen probe
baseline for evaluating the existing retrieval implementation, and the
adopted but implementation-incomplete Phase 28 RAG method baseline. The marked-
best black-corpus assessment is the primary requirements context and Synthetic
Corpus V1 is the safe held-out evaluation fixture. Decisions `D01` through
`D23` freeze the classification, extraction, normalization, chunking,
identity, embedding, ingestion, PostgreSQL persistence, relationship,
retrieval, reconstruction, response, scope, security, observability,
validation, API, configuration, and packaging boundaries.

The runtime portion of `D23` and `G20` was narrowly amended after the operator
clarified that Python and PostgreSQL/pgvector must run natively on the host.
The operator accepted configurable host networking, explicit configurable
Next.js loopback binding, and a configurable native retrieval URL, so the
top-level and gap decision lists are closed again. Remaining work is tracked
through the Gap and Implementation Ledger and covers concrete schemas, target tool and
model qualification, numeric calibration, implementation, packaging, and
execution evidence. `G01` freezes the source-verification acceptance contract
without claiming that extraction has run. The accepted KISS direction for
`G02` uses a small class registry and an ingestion manifest with an explicit
operator-assigned class, common extraction and structural chunking, and
quarantine evidence to justify only necessary extensions. Amended `D01`,
`D02`, `D10`, and `D13` freeze that classification correction. `G03` freezes a
Poppler-first native qualification plan while
retaining `NOT RUN` for target inventory and extraction evidence. `G04`
freezes the common conservative normalizer, and `G05` binds embedding
measurement to the tokenizer in the pinned Nomic Embed Text v1.5 snapshot,
with a 2048-token total ceiling and a 512-token starting target while keeping
counter and quality qualification `NOT RUN`. `G06` freezes deterministic
structural fallback and quarantine, while `G07` freezes compact JSON/JSONL
logical records and an explicit client-safe projection; their implementation
and qualification remain `NOT RUN`. `G08` freezes a human-maintained YAML
document catalog whose stable keys must be referenced by the ingestion
manifest, with unknown keys quarantined before chunking and immutable source
digests identifying revisions without a required version-label scheme. `G09`
freezes operator-invoked incremental ingestion: process only manifest-listed
new or changed documents, reuse unchanged artifacts, validate against the
active corpus, and publish only affected changes atomically with rollback;
implementation and
qualification remain `NOT RUN`. The gap review contains `G01` through `G20`.
`G01` through `G20` are frozen. Amended `G20` selects native host Python and
PostgreSQL/pgvector plus configurable host networking, web bind address/port,
and native retrieval URL. EmceeDanko native PostgreSQL, pgvector, and Psycopg
package qualification has passed; org-lab native-package qualification remains
unexecuted implementation evidence.
`G10` freezes the exact direct-vLLM embedding tuple and
fail-closed contract. The neutral,
action-oriented `verify-embedding-service` acceptance surface is implemented,
and the Danko technical compatibility run passed; org target qualification
remains `NOT RUN`. Only the two neutral acceptance
files may leave the repository; phase paths, gap identifiers, lab names, and
control documentation remain repository-local. Both
the Nomic and Gemma integrations call their OpenAI-compatible vLLM endpoints
directly; Dalton is not a Phase 28 dependency. `G11` freezes PostgreSQL as the
production catalog, pgvector for embeddings, native PostgreSQL full-text
search for lexical retrieval, transactional incremental publication,
rebuildable indexes, plain SQL migrations, and native backup/restore, with
SQLite limited to disposable prototypes. `G12` freezes exact structured,
native PostgreSQL full-text, and pgvector cosine retrieval lanes with
deterministic RRF. `G13` freezes the KISS explicit-reference relationship
contract. `G14` freezes deterministic evidence reconstruction, complete-
procedure handling, and explicit context-limit behavior. `G15` freezes the
versioned multi-turn retrieval API and excerpt-level citation contract. `G16`
requires an explicit Gemma scope decision for every valid natural-language
turn before retrieval and freezes separate injection, sufficiency, citation,
and abstention gates. `G17` freezes loopback-only retrieval at
`127.0.0.1:1384`, no application identity or per-user permissions, read-only
PostgreSQL retrieval, model isolation, runtime secret injection, retirement
propagation, and future-compatible identity and encryption fields. `G18`
freezes local classified JSONL logging, request correlation, stable failures,
health checks, and protected local audit without an external logging stack.
`G19` freezes one operator-run per-case validation surface, explains held-out
truth separation, and retains all implementation and qualification as
`NOT RUN`. Amended `G20` uses exactly one application container: the existing
Node 24/Next.js 16.4.1 image with bind-mounted host source. Retrieval and
one-shot corpus commands use native host Python, while PostgreSQL/pgvector is
installed and run natively with host-owned state. Python and PostgreSQL images
are excluded. The portable package keeps the Node image, native package
payloads or acquisition manifests, source, configuration, secrets, corpus,
database state, backups, and evidence as separate artifact classes. The
fresh-deployment package uses one consolidated final database schema and does
not carry the historical development migration or repair chain. Any future
upgrade of an already-installed supported release uses a separately
identified, operator-selected upgrade package.
Implementation notes must be maintained so the final package
accurately documents chunking, ingestion, each retrieval lane,
reconstruction, configuration, provenance, and failure behavior; incomplete
documentation blocks package and handoff acceptance. The Next.js
web/API and retrieval API are the two
persistent Phase 28 application services, but they install boot-disabled and
run only after explicit operator start. Extraction, chunking, ingestion,
validation, publication, and other corpus operations are one-shot executable
commands. The first package target is `linux/amd64`; EmceeDanko is the
transport and install/setup test bed, while org-lab integration remains
separate target proof.

No persistent application service, deployment, retrieval pipeline, or web UI
has been implemented or validated. Native PostgreSQL package installation,
cluster initialization, application database, migrations `0001 + 0002`, and
target-native incremental-writer proof have passed on EmceeDanko. Synthetic
PDF extraction and normalization are accepted; structural chunk-candidate
construction is source-ready but remains non-publishable pending exact Nomic
token measurement. The implemented command surfaces include the embedding verifier and
its report-first operator wrapper plus the neutral read-only application-host
inventory helper and report-first SSH wrapper. The inventory surface is
locally validated, and its operator-executed EmceeDanko OS/native-package run
passed. The separate operator-executed attended-sudo Script `03` also passed,
confirming Docker/Compose/Buildx, the existing AMD64 Node/Next.js image, and
the absence of the generic Python and PostgreSQL/pgvector images. Script `04`
later produced a technically valid three-image archive, but the operator did
not select Python or PostgreSQL containers. That archive is retained as
historical ignored evidence only and shall not be transferred or loaded.
Native Python dependency and PostgreSQL/pgvector package qualification is the
next runtime gate. The native PostgreSQL capture plan is implemented. The
operator-executed Script `05` inventory passed and selected exact PostgreSQL
16, pgvector, and Psycopg 3 roots. The first Script `06` run stopped safely
before download on an Ubuntu virtual-package dependency. The corrected helper
passed a 98-package local metadata replay. The second run returned a complete
98-package AMD64 dependency graph but stopped before local download. Its
retained metadata passed the new no-SSH resume validation, and the target apt
simulation selected only nine missing packages. The final Script `06` run
created and independently verified the checksum-bound Ubuntu 24.04 AMD64
bundle. Package capture is accepted, but the separate advisory review found
that its Noble pgvector `0.6.0-1` is affected by two current index-build
vulnerabilities, including an IVFFlat issue corrected upstream only in
`0.8.7`. The bundle is blocked from transfer and installation; replacement
capture requires a corrected Ubuntu package or an explicitly approved
alternate pgvector source. The operator approved the official signed PGDG
Noble package `0.8.7-1.pgdg24.04+1`. The capture discipline now requires all
exact source/version advisory decisions before package payload download, and
the complete six-source replacement set passed that gate. Script `07` is the
current local-only replacement-capture action. Its first execution safely
blocked after the advisory gate and before package download on an unavailable
PGDG index-compression assumption. Signed `Packages.gz` selection and bounded
download timeouts were then locally validated. The corrected operator rerun
and independent review passed, accepting the checksum-bound nine-package
PostgreSQL 16, pgvector `0.8.7`, and Psycopg 3 bundle as an installation input.
No target installation is yet authorized.
Script `08` is source-ready as the next read-only EmceeDanko gate. It transfers
the accepted bundle only to private temporary storage, validates it, simulates
the exact nine-package install with downloads disabled, returns a bounded
report, and cleans up without sudo or target mutation.
The first run safely blocked at apt simulation after payload verification and
then cleaned up. The helper was aligned to the earlier successful EmceeDanko
`apt-get -s` form and now emits bounded failure diagnostics; a corrected rerun
remains pending.
The second run also cleaned up without mutation but exposed `ERR`-trap
interception of apt exit `100`. The helper now captures that expected status
inside a conditional so the bounded diagnostic path can execute on rerun.
Independent package-control review then identified the underlying hard
conflict: PGDG pgvector requires JIT virtual version `19` or later, while the
captured Ubuntu PostgreSQL server provides `17`. The current bundle is blocked
from transfer/install, Script `08` shall not be rerun against it, and exact
target `libllvm19` inventory is the next gate.
Script `09` is source-ready for that streamed read-only inventory. It binds the
blocked bundle and Script-08 report, records the exact target candidate, and
does not update metadata, download packages, use sudo, or write a target file.
The operator-executed Script `09` passed and proved that the exact required
Ubuntu `libllvm19` is already installed. Its four current Canonical Noble
records were reviewed with a bounded AMD64 PostgreSQL-JIT non-applicability
decision. Script `10` then created the corrected nine-package bundle using
signed PGDG PostgreSQL `16.15` with JIT virtual version `19`, retained pgvector
`0.8.7`, and the exact Ubuntu LLVM runtime. Independent checks accepted the
outer and internal hashes, package identities, licenses, advisory set, and JIT
contract. Script `11` is source-ready as the new no-sudo, no-install target
preflight and supersedes the blocked Script `08` path.
The operator-executed Script `11` passed: the exact reviewed bundle simulated
eight installs and zero removals on EmceeDanko, with no cluster, listener, or
persistent temporary payload. Script `12` is source-ready as the explicitly
authorized offline native-package installation. It suppresses automatic
cluster creation and leaves PostgreSQL stopped and boot-disabled; database
initialization remains a separate reviewed gate.
The first Script `12` run stopped safely at support-package apt exit `100`
before the PostgreSQL server/pgvector stage. Script `13` is the next read-only
gate; it determines exact partial package state and returns bounded dpkg/apt
diagnostics before any repair or retry.
Script `13` passed and proved that no partial package state exists. The cause
was apt `--no-download` blocking acquisition of the explicit transferred local
files. Script `14` is the corrected retry: apt sources remain disabled,
network proxies reject connections, and only the exact local `.deb` paths are
accepted.
The operator-executed Script `14` retry passed. PostgreSQL `16.15`, pgvector
`0.8.7`, and Psycopg `3.1.17` are installed, while automatic cluster creation
is off and PostgreSQL remains clusterless, stopped, boot-disabled, and without
a listener. Script `15` is source-ready as the separate explicitly authorized
cluster initialization. It creates only the native `16/main` cluster with
UTF-8, data checksums, loopback/SCRAM configuration, and manual startup, then
leaves it stopped. Application database, role, schema, extension, secret, and
service-start configuration remain separate gates.
The operator-executed Script `15` passed and established that exact stopped
cluster. Script `16` is source-ready to create the configurable empty
`rag_catalog` database, non-login owner, isolated ingestion and retrieval
login roles, and pgvector extension. The role secrets are entered privately
and are neither retained nor reported. Both login roles initially receive
only database connection permission; application schema, tables, indexes,
content, and exact object-level grants remain reviewed SQL-migration work.
The first Script `16` run stopped before SQL because the PostgreSQL cluster
service failed to start. It created no application database, role, or
extension instance. Script `17` is source-ready as the separate read-only
systemd/configuration/filesystem/log inspection and does not retry the start.
Script `17` passed and isolated the failure to configuration parsing, with
storage, permissions, capacity, listener, and cluster state otherwise valid.
Script `18` proved the current canonical loopback setting and full
configuration parse while stopped. Because its before and after content hashes
are identical, the earlier unquoted-IPv4 exact-cause claim is withdrawn and a
start/stop-only proof is required before Script `16` is retried.
Script `19` is source-ready for that no-SQL proof. It starts the existing
cluster, requires Unix-socket readiness and one loopback listener, stops it,
and proves clean shutdown and unchanged boot-disabled state.
The operator-executed Script `19` passed. Scripts `17`–`19` are retained only
as historical troubleshooting evidence. Their configuration-parse,
start/readiness/listener, delayed-secret-prompt, bounded-failure, and cleanup
lessons are consolidated into corrected Scripts `15` and `16`; the normal
workflow does not replay the troubleshooting chain.
The corrected operator-executed Script `16` then passed. The accepted receipt
proves the empty UTF-8 `rag_catalog` database, non-login owner, separate
connect-only ingestion and retrieval roles, SCRAM-SHA-256 password storage,
retrieval read-only default, pgvector `0.8.7`, zero application relations,
secret non-retention, and a clean return to the stopped, boot-disabled state.
The next gate is the reviewed plain-SQL application schema and exact privilege
migration; no further runtime repair is required. Script `20`, its neutral
helper, and migration `0001` are now source-ready. Local validation and a
disposable PostgreSQL execution test passed with 20 empty base tables, five
active-only retrieval views, `vector(768)`, one lexical GIN index, no ANN
vector index, and the intended role boundary. The EmceeDanko migration remains
not accepted: the first target execution failed inside its transaction, then
stopped PostgreSQL and cleaned temporary state. Canonical Script `20` now
returns a bounded SQLSTATE, line, failure class, and diagnostic checksum on a
repeat failure without retaining raw SQL output. The same command is the next
gate. The second run exposed `ERR`-trap interception before that classifier;
the corrected helper now uses an explicit conditional around `psql` while the
SQL migration remains unchanged. The third run then proved that the
`postgres` OS identity could not traverse the private operator-owned transfer
directory to open the migration by pathname. The canonical helper now keeps
that directory private and streams the checksum-verified SQL over standard
input. Before it can report success, it also requires exact object and role
facts plus a complete PostgreSQL stop/start persistence recheck. Disposable
PostgreSQL `16.15` testing passed that full contract; the corrected same Script
`20` command was the target gate. Since none of the blocked target runs
committed the SQL, the pre-acceptance look-ahead review also added declarative
cross-document/cross-artifact integrity constraints and active-version class
projection to migration `0001`; the repeatable regression passes all six
negative integrity cases.
The corrected operator-executed Script `20` then passed and is accepted.
Migration `0001` was applied on EmceeDanko, and the empty three-schema,
20-table, five-view application catalog plus exact role boundary survived a
complete PostgreSQL stop/start. No corpus content or ANN vector index was
created. PostgreSQL returned to its stopped, inactive, boot-disabled state.
The native PostgreSQL runtime and initial schema are durable application
infrastructure, not disposable preflight state. The next implementation gate
is catalog/manifest validation and incremental ingestion; no further database
foundation repair is required.
Migration `0002` and its local disposable proof then passed, and the
operator-executed Script `22` applied and reverified that ownership alignment
on EmceeDanko. Script `23` subsequently passed all 64 local configuration,
planning, reporting, and atomic-writer tests. The operator-executed Script
`24` then used a separate disposable PostgreSQL database to exercise the
writer through native Psycopg, dropped that database on exit, proved the
accepted `rag_catalog` unchanged, and restored PostgreSQL to its stopped,
boot-disabled state. Add, reuse, revise, reprocess, quarantine, remediation,
forced rollback, retirement, and retrieval-role isolation all passed. This
accepts the incremental persistence writer, not the extractor, chunker,
embedding path, retrieval service, UI, or install package.

Scripts `25` through `28` have now accepted the first producer-pipeline
artifacts. Script `25` qualified native Poppler extraction of all six synthetic
PDFs against local held-out truth. Script `26` normalized those observations
into anchored structural units. Script `27` produced 125 deterministic
structure-aware candidates with zero blind overlap. Script `28` measured their
exact prefixed Nomic inputs at 10–57 tokens and returned 125 accepted,
unchanged 768-dimensional vectors.

Scripts `29` through `31` completed the writer gate. Script `29` first passed
the real producer artifacts through a disposable target-native database.
Review then identified that tokenizer-added special tokens needed their own
database column instead of being folded into the prefix bucket. Script `30`
applied migration `0003`, accepted schema version 3, and preserved the empty
`rag_catalog`. Script `31` repeated the complete six-document projection and
proved 230 structural units, 125 chunks, 125 citations, 125 embeddings, four
exact token buckets, unchanged-document reuse, retrieval-role isolation,
disposable-database cleanup, and accepted-database non-mutation. The validated
pipeline-writer contract is frozen under the existing `G09` and `G11`
decisions. Retrieval implementation is the next gate.

Packaging will consolidate the current schema into one fresh-install baseline
after the application schema stabilizes. A new org-lab installation will
create the final current tables directly instead of replaying the historical
EmceeDanko `0001` then `0002` development sequence; later upgrades to an
installed baseline will still use explicit forward migrations. EmceeDanko is
Ubuntu `24.04.5`, while the operator identifies org-lab Tech as Ubuntu `26`;
the architecture remains shared, but native package inventories and pins
remain target-specific.

See [Knowledge Assistant probe baseline](knowledge_assistant_probe_baseline.md).

The proposed product and Chat UI are named `Ishikawa`. The durable proposed
application architecture, host and repository layouts, configuration
responsibilities, retirement and quarantine workflows, ingestion writer, and
forward-migration boundary are recorded in
[`../Ishikawa/docs/ARCHITECTURE.md`](../Ishikawa/docs/ARCHITECTURE.md).

Retrieval implementation now reaches the accepted native HTTP boundary.
Operator-executed Scripts `62` through `69` accepted the multi-turn API,
orchestration, native model adapters, contextual query resolution, native
PostgreSQL retrieval, relationship and complete-procedure retrieval, the
target-native complete retrieval adapter, and the loopback listener. Script
`70` is source-ready to qualify the complete configuration-to-runtime assembly
locally, including the exact Gemma `/tokenize` counter, protected environment
providers, read-only PostgreSQL connection and source-name boundaries, and all
concrete adapters. It reads no credential and contacts no dependency.
See [Phase 28 RAG method baseline](PHASE_28_RAG_METHOD_BASELINE.md).
