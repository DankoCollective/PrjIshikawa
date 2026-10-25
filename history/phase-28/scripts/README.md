# Phase 28 Apisachi Tokuli Scripts

## Classified retrieval-service logging

Script `94` is the local-only qualification gate for the frozen classified
logging foundation:

```bash
bash ./phase-28-apisachi-tokuli/scripts/94_qualify_classified_structured_logging.sh --run
```

It binds to the accepted Script `93` readiness evidence, runs all 341 local
application tests, and exercises temporary synthetic logs only. It proves the
exact `default`, `debug`, and bounded `verbose` profiles; typed operational,
diagnostic, and restricted-content fields; one opaque request identity;
protected mode-`0600` JSONL files; separate content-free audit; bounded
rotation; verbose expiration and emergency stop; JSON record integrity; and
prohibited-field/canary exclusion. It contacts no target, database, model, or
credential and leaves no persistent runtime log.

The installed configuration keeps `default` as its base. YAML may select
`default` or `debug`, but cannot persistently select `verbose`. The next gate
after an accepted Script `94` result is the local operator control surface for
explicit verbose enable/disable; that surface must use the already-qualified
bounded in-memory activation rather than add a permanent verbose setting.

## Accepted schema-v3 pipeline writer

Scripts `29` through `31` connected the accepted extraction, normalization,
chunking, token-measurement, and embedding artifacts to the incremental writer.
Script `30` corrected the database representation so tokenizer-added special
tokens have their own exact column. Script `31` then passed all six synthetic
documents through schema version 3 in a disposable EmceeDanko database and
proved four-bucket accounting, active projections, unchanged-document reuse,
read-only retrieval access, cleanup, and accepted-catalog non-mutation.

The writer contract is frozen in
`Ishikawa/docs/PIPELINE_WRITER_CONTRACT.md`. Do not rerun Scripts `29`, `30`, or
`31` in the normal workflow. The next numbered gate begins retrieval
implementation against disposable synthetic data.

## Three-lane retrieval foundation

Script `32` passed against a disposable EmceeDanko database and is accepted.
It proved verified exact-reference lookup, PostgreSQL full-text retrieval,
pgvector cosine retrieval, deterministic reciprocal-rank fusion, canonical
chunk deduplication with lane provenance, retrieval-role isolation, complete
cleanup, and non-mutation of the accepted database. Do not rerun Script `32`
in the normal workflow.

The normal natural-language path runs the lexical and vector lanes and fuses
their ranked candidates. The exact lane participates when the request carries
a verified document, chunk, citation, or prior-source reference. A chunk found
by multiple lanes becomes one fused candidate with all contributing lanes
recorded; distinct relevant chunks from the same document are not discarded.

## Held-out retrieval-query embeddings

Script `33` embeds the six retrieval-eligible held-out synthetic questions
with Nomic's `search_query: ` prefix. It deliberately excludes the one case
marked for abstention; the later topic gate, not retrieval calibration, owns
that decision. The protected returned artifact records exact token accounting,
unmodified 768-dimensional vectors, the accepted document embedding-space
identity, query-prefix provenance, and content digests without logging raw
questions or vectors.

Run from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/33_embed_held_out_retrieval_queries.sh --run
```

The command may prompt for the SSH-key passphrase, target sudo password, and
Nomic API key. It does not connect to PostgreSQL, publish data, install
packages, change configuration, or process organizational content. A pass
routes to held-out retrieval calibration in a disposable database.

The operator-executed Script `33` produced and locally validated six query
embeddings for `Q-001` through `Q-005` and `Q-007`; `Q-006` remained excluded
as the expected-abstention case. Token counts were 14 through 20, all vectors
were finite and 768-dimensional, repeat delta was zero, and the query artifact
used the accepted document embedding-space identity. The artifact is accepted
and does not need to be regenerated.

The post-success removal of the target staging directory reported failure.
Review identified a root-owned Python bytecode cache as the cause. The
canonical target helper now disables bytecode writes before importing its
shared runtime and also sets `PYTHONDONTWRITEBYTECODE=1` at invocation. This
housekeeping correction does not change the accepted vectors or calibration
contract. A stale fully synthetic staging directory may remain on the target;
its removal is housekeeping and does not block the disposable-database
calibration gate.

## Held-out retrieval calibration

Script `34` runs the frozen initial retrieval profile—candidate depth 20 for
each eligible lane and fused output, PostgreSQL `english` full-text search,
pgvector cosine distance, and RRF constant 60—against the six accepted query
embeddings in a disposable EmceeDanko database. Conservative structured-term
recognition makes the exact lane eligible only for identifier-shaped terms.

Only the synthetic questions and measured vectors reach the target. Required
citations remain local and are applied by the local evaluator after the
content-free ranked observation artifact returns. Every case reports its own
status, coverage, first relevant rank, reciprocal rank, participating-lane
counts, and the aggregate promotion result. A completed measurement is
retained even when the initial profile is not promotion-eligible, so observed
gaps can be corrected without hiding the evidence.

Run from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/34_calibrate_held_out_retrieval_on_emceedanko.sh --run
```

The command may prompt for the SSH-key passphrase and target sudo password. It
does not call a model, transfer held-out expected citations, install packages,
change configuration, or mutate the accepted database. It drops its
disposable database, restores PostgreSQL to its stopped boot-disabled state,
and removes its target staging directory.

The operator-executed Script `34` completed the target measurement and proved
accepted-database non-mutation and cleanup, but local grading correctly
blocked before accepting the observation artifact. The database uses its own
canonical chunk identities, while the held-out citation map uses the upstream
producer chunk identities. The first observation contract returned database
identities without the existing `producer_chunk_id` mapping and therefore
could not be graded safely.

Script `35` is the corrected calibration gate. It reruns the same disposable
measurement and frozen retrieval profile, verifies a complete one-to-one map
between the 125 database and producer chunk identities, and returns producer
identities for local citation grading. It does not change the retrieval
method, accepted schema, embeddings, expected citations, or application
database.

Run from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/35_calibrate_held_out_retrieval_on_emceedanko.sh --run
```

A Script `35` pass accepts the measurement artifact. Its
`profile_promotion_eligible` result then determines whether the next gate is
profile freeze or closure of observed retrieval gaps. Script `36` must not be
selected until that result is reviewed.

The operator-executed Script `35` accepted the measurement but did not promote
the initial profile: five of six retrieval cases and 12 of 13 required
citations passed. The intentional blank page had no citable chunk, and strict
PostgreSQL full-text search returned no candidates for the held-out wording.
Those observations freeze one bounded correction under `G12`:

- represent each verified blank page as deterministic `page_status` evidence
  with a page citation and no invented source content;
- let exact lookup resolve an explicit document identifier plus page number;
- run strict PostgreSQL full-text search first and use native OR search only
  when the strict query returns no candidates; and
- assign a new method-profile identity and requalify it without a database
  migration.

Script `36` generates that amended 126-candidate set twice, proves its
deterministic identity, reruns the local regression gates, measures and embeds
all candidates through the authoritative Nomic service, locally validates the
returned artifact, and retains both the generated chunk artifact and measured
embedding artifact with checksum sidecars.

Run from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/36_qualify_retrieval_gap_method_profile.sh --run
```

The command may prompt for the SSH-key passphrase, target sudo password, and
Nomic API key. It does not connect to PostgreSQL, publish data, process
organizational content, install packages, or change target configuration. A
pass routes to Script `37`, which must recalibrate the amended profile in a
disposable EmceeDanko database.

The operator-executed Script `36` passed. It qualified all 126 candidates,
including one `page_status` candidate, with exact Nomic token counts of 10
through 57 and 768-dimensional unmodified vectors. Both retained artifacts
and sidecars passed local verification, and target cleanup succeeded.

Script `37` now loads those amended artifacts into a disposable database,
proves the exact document-plus-page route, records whether strict or OR
lexical retrieval produced each lexical result, reruns vector retrieval and
RRF, and grades the same held-out truth locally. The accepted database is
read-only evidence and must remain unchanged.

Run from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/37_recalibrate_retrieval_gap_profile_on_emceedanko.sh --run
```

The command may prompt for the SSH-key passphrase and target sudo password. It
does not call a model, transfer held-out expected citations, install packages,
change configuration, or mutate the accepted database. It removes the
disposable database, restores PostgreSQL to its stopped boot-disabled state,
and removes its target staging directory.

The operator-executed Script `37` passed all six held-out cases, covered all
13 required citations, observed the native PostgreSQL OR fallback, proved
retrieval-role isolation, removed the disposable database, and left the
accepted database unchanged. Do not rerun Script `37` in the normal workflow.

The operator then froze the calibrated settings. Script `38` is a local-only
gate that proves the deployable `method_profile.yaml`, application defaults,
distinct retrieval-profile identity, 90-test regression suite, and exact
accepted Script `37` receipt agree:

```bash
bash ./phase-28-apisachi-tokuli/scripts/38_freeze_calibrated_retrieval_profile.sh --run
```

Script `38` makes no remote connection, model call, database connection,
package change, or source-document read. It retains one content-free local
report. A pass routes to implementation of the already-frozen `G13`
relationship contract.

The operator-executed Script `38` passed all 90 tests and accepted retrieval-
profile identity
`33102734a29ea8170cffcfa7cdff6feae66d4663d09d7bca86c04a6419f77ad7`
against the exact retained Script `37` evidence. Do not rerun Script `38` in
the normal workflow. The next numbered gate implements and locally validates
the frozen relationship contract.

## Deterministic relationship contract

Script `39` is a local-only implementation and qualification gate for the
already-frozen `G13` contract:

```bash
bash ./phase-28-apisachi-tokuli/scripts/39_qualify_relationship_contract.sh --run
```

It runs 106 local tests, validates the relationship registry, separately
identifies corpus document declarations, distinguishes record-instance
identifiers from document references, resolves unambiguous explicit references,
and proves ambiguity quarantine, audited external/document overrides,
fixed-version supersession, authorization, cycle protection, target
deduplication, and one-hop provenance. It then compares the implementation to
separate held-out synthetic truth and requires all five expected relationships
and traversals.

Script `39` makes no remote connection, model call, database connection,
package change, or source-text output. It creates no routine operator
relationship manifest. A pass retains one content-free local report and routes
to relationship persistence and read-only retrieval in a disposable target
database.

The operator-executed Script `39` passed all 106 tests, found 27 deterministic
internal edges and 17 self declarations with no unresolved references, and
covered all five held-out relationships and one-hop traversals. Do not rerun
Script `39` in the normal workflow.

Script `40` proves the next boundary on EmceeDanko:

```bash
bash ./phase-28-apisachi-tokuli/scripts/40_test_relationship_persistence_on_emceedanko.sh --run
```

It applies schema migration `0004` only to a disposable database, preserving
the audit identity and reason required for an operator override. It loads the
accepted synthetic pipeline artifacts, discovers and atomically writes the 27
qualified internal relationships, verifies the active read-only relationship
view and all five held-out one-hop traversals, and proves that the retrieval
role cannot read the base relationship table. It then drops the disposable
database, proves the accepted `rag_catalog` is unchanged at schema version 3,
stops PostgreSQL, and removes the target staging directory. A pass routes to a
separate reviewed application of migration `0004` to the still-empty accepted
database.

## Nomic chunk measurement and embedding

Script `28` checksum-binds the accepted Script `27` candidate artifact and the
accepted Nomic compatibility receipt. It locally reruns 64 base, 13
normalization, 12 chunking, and 8 embedding-contract tests before making any
target contact. It then stages only two neutral helpers plus the 125 fully
synthetic candidates on the configured Nomic host.

Run from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/28_qualify_nomic_chunk_embeddings.sh --run
```

The operator may be prompted for the SSH-key passphrase, target sudo password,
and Nomic API key. The API key is read from the attended terminal and piped
directly to the verifier; it is not transferred as a file, placed in YAML or
the environment, or retained. The target helper measures the exact prefixed
embedding input with the pinned tokenizer, enforces the 2,048-token ceiling,
calls the loopback `/v1/embeddings` endpoint, verifies the 768-dimensional
unchanged vectors and repeat tolerance, and restores the initial Nomic service
state. The wrapper retrieves the protected synthetic artifact, validates every
record locally, writes a checksum sidecar and content-free receipt, and removes
the target temporary directory.

Script `28` does not connect to PostgreSQL, publish chunks, process
organizational content, install packages, change configuration, or bake source
into an image. A pass routes to connecting the measured embedding artifacts to
the accepted incremental writer.

The operator-executed Script `28` passed and is accepted. All 125 candidate
inputs measured between 10 and 57 Nomic tokens, so all were below both the
initial 512-token target and the 2,048-token model ceiling. The returned 768-
dimensional vectors were finite, unmodified, and repeatable within the frozen
`1e-5` tolerance; the local evaluator independently accepted every identity,
token record, vector, and digest. The API key was operator-entered and not
retained, the initially active service remained active, and the target payload
was removed. Do not rerun Script `28` in the normal workflow. The next gate is
pipeline-writer integration; publication remains blocked until that passes.

## Structural chunk candidates

Script `26` has passed and retained the accepted normalized structural-unit
artifact. Script `27` consumes only that exact artifact, runs the 64 base, 13
normalization, and 12 chunking checks, performs two deterministic candidate
replays, and retains one checksum-bound local candidate artifact:

```bash
bash ./phase-28-apisachi-tokuli/scripts/27_create_structural_chunk_candidates.sh --run
```

The command is entirely local and requests no password. It creates 125
structure-aware candidates with explicit citation, lexical, table, form, and
sequence metadata and zero blind body overlap. It does not contact Nomic,
connect to PostgreSQL, or make candidates searchable. Every candidate remains
blocked with `nomic_token_measurement_pending`; Script `28` owns exact Nomic
token measurement and embedding.

## Embedding-service verification

`verify_embedding_service.py` is a target-local, standard-library verifier for
the accepted Nomic embedding tuple. It validates the pinned model and tokenizer
digests, mean-token pooling, license, live container arguments and image
identity, vLLM version, model advertisement, 768-dimensional finite outputs,
`1e-5` single/repeat/batch tolerance, tokenizer-count agreement, task prefixes,
cosine discrimination, and bounded failure cases. It emits no prompts,
responses, vectors, credentials, raw service errors, repository terminology,
or development-lab identity. It cannot read the installed service credential;
the operator supplies the Nomic API key through one silent attended prompt,
and the key reaches the verifier only through an anonymous standard-input
pipe.

`verify-embedding-service` preserves the initial Nomic service state. If the
service is inactive it uses the installed `start-vllm nomic` surface, runs the
verifier, and stops Nomic during cleanup. If Nomic is already active, it leaves
the service active.

Run both local source checks before packaging or transfer:

```bash
python3 -m py_compile \
  phase-28-apisachi-tokuli/scripts/verify_embedding_service.py

python3 \
  phase-28-apisachi-tokuli/scripts/verify_embedding_service.py \
  --self-test

bash -n \
  phase-28-apisachi-tokuli/scripts/verify-embedding-service
```

`01_run_embedding_service_verification.sh` is the first active Phase 28
operator script and the report-first wrapper for this check. It has no earlier
Phase 28 script prerequisite. It creates its timestamped ignored report
itself, validates the bundle, opens one reusable attended SSH connection,
stages the neutral bundle under target `/tmp`, verifies its SHA-256 on the
target, runs the target entry point through `sudo`, retrieves and validates the
content-free result, and removes the target payload automatically. It does not
require the operator to create a target or result directory.

When `local/site_values.env` contains the accepted target address, runtime
user, identity-file, and stable-hostname values, run from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/01_run_embedding_service_verification.sh
```

For another control workstation or target, supply `--target`,
`--identity-file`, `--expected-hostname`, `--bundle`, `--checksum`, and an
absolute `--report-root`. The report root is local to the workstation running
the wrapper. This permits the org control workstation to use an operator-owned
temporary result directory without placing repository or phase terminology on
the model host.

Only `verify-embedding-service`, `verify_embedding_service.py`, and their
neutral archive name reach the target. Do not transfer this README, the
operator wrapper, its repository path, or its local report.

The target requires its installed Docker, Python 3, systemd tooling, accepted
Nomic model tree, operator-provided Nomic API key, and managed
`start-vllm`/`stop-vllm` commands. Full corpus retrieval qualification is a
separate activity; this verifier accepts only the exact embedding tuple and
adapter behavior.

## Application-host inventory

`inspect-application-host` is a neutral, read-only target helper. It records
bounded Ubuntu/architecture, capacity, native package, Python, Poppler,
PostgreSQL-client, Docker/Compose, relevant local image, and planned-port
facts. It does not update package metadata, contact a registry, install
anything, prompt for sudo, read application content or secrets, alter a
service, or write a target file. If Docker is inaccessible to the SSH user and
also unavailable through noninteractive sudo, it records that readiness issue
rather than requesting a credential.

`02_run_application_host_inventory.sh` streams that helper over SSH, so no
payload or result directory is created on the target. It creates the local
report itself, validates every returned line, classifies transport failures
without retaining raw SSH errors, and removes its local temporary work. Its
defaults select the configured EmceeDanko SSH alias and hostname. Run:

```bash
bash ./phase-28-apisachi-tokuli/scripts/02_run_application_host_inventory.sh
```

The SSH client may request the operator's key passphrase. For the org control
workstation, use the same wrapper with explicit `--target`,
`--expected-hostname`, `--expected-os-version`, optional `--identity-file`,
and an absolute operator-owned `--report-root`. The OS argument accepts an
exact major/minor such as `24.04` or a major prefix such as `26`; the report
still records the target's exact `VERSION_ID`. Only the neutral helper stream
reaches the target; the numbered wrapper and repository paths remain local.

If Script `02` records that Docker daemon access requires sudo, run the
separate attended Script `03`:

```bash
bash ./phase-28-apisachi-tokuli/scripts/03_run_container_runtime_inventory.sh
```

`inspect-container-runtime` reads Docker engine, Compose, Buildx, capacity,
container-count, volume-count, planned-port, and allowlisted runtime-image
metadata. It never lists arbitrary image or container names and performs no
pull, build, load, run, stop, removal, or configuration change. Script `03`
stages that neutral helper in a unique target `/tmp` directory, verifies its
hash, runs it through attended sudo, retrieves and validates the result, and
automatically removes the target directory. The operator—not Codex—executes
all remote wrappers and enters all SSH or sudo passphrases. Codex is limited to
writing and locally validating these scripts and reviewing returned local
reports. Script `03` connects its attended sudo step directly to `/dev/tty`,
so the password prompt is visible while prompt output remains outside the
retained report.

## Historical application runtime image capture — do not rerun or transfer

`04_capture_application_runtime_images.sh` is a local-workstation acquisition
and packaging gate. It does not use SSH or contact EmceeDanko or org-lab. It
requires the already accepted `node-24-slim-nextjs-16-4-1:amd64` image, pulls
only the exact public `linux/amd64` Python `3.12.15` slim/Trixie and
PostgreSQL 17/pgvector `0.8.7` Bookworm candidates, validates their platform
and embedded version facts, and records their full registry digests and image
IDs. All inspect and save operations explicitly select `linux/amd64`, even on
an ARM64 workstation. The Node platform-image ID must match the exact image
already accepted on EmceeDanko. Archive-config digests are separate image
identities and are recorded independently rather than compared to the
platform-image ID. The script then writes all three unchanged images into one
Docker-save tar with a plain manifest and SHA-256 set under the ignored local
artifact tree.

If an exact referenced AMD64 image is already present locally, Script `04`
reuses it without registry contact. A pull occurs only when that required
platform/reference is absent. In particular, rerunning after a blocked save or
inspection does not redownload successfully acquired images.

Validate the definition without Docker or network access:

```bash
bash ./phase-28-apisachi-tokuli/scripts/04_capture_application_runtime_images.sh \
  --validate-only
```

The operator runs the acquisition from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/04_capture_application_runtime_images.sh
```

If direct Docker access is unavailable, the script visibly prompts through
`/dev/tty` for local sudo authentication and does not retain the credential.
The script never builds or runs a container and never changes the accepted
Node/Next.js image. Pulling the two missing images and writing the ignored
capture are its only persistent mutations. Transfer and load testing are a
separate operator-run gate after review of the capture report.

The operator subsequently clarified that Python and PostgreSQL/pgvector must
run natively on the host. Script `04` and its accepted archive are therefore
retained for historical traceability only. Do not rerun the script, transfer
the archive, or load it on a target. The existing Node/Next.js image remains
the only selected application image.

## Native PostgreSQL package inventory

`inspect-native-postgresql-packages` is a neutral read-only helper for the
first native PostgreSQL/pgvector capture gate. It records bounded host,
architecture, apt-metadata age, storage, exact PostgreSQL server/client/contrib
candidate, matching pgvector candidate, `libpq`, native Python driver,
service, cluster-count, vector-control-count, and port facts. It performs no
apt update, network access, package download, package installation, database
initialization, service mutation, configuration mutation, content read,
secret read, or persistent target write.

`05_run_native_postgresql_package_inventory.sh` streams that helper over SSH
and writes the validated bounded response into the ignored local report lane.
It does not copy a numbered script or repository terminology to the target.
The operator retains SSH passphrase custody. Validate locally without target
contact:

```bash
bash ./phase-28-apisachi-tokuli/scripts/05_run_native_postgresql_package_inventory.sh \
  --validate-only
```

Run the default EmceeDanko inventory from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/05_run_native_postgresql_package_inventory.sh
```

Review the report before writing the offline `.deb` closure capture. Do not
guess the PostgreSQL major or pgvector package, add a package repository, or
install anything from this inventory step.

The accepted Script `05` report selected PostgreSQL `16.15`, pgvector `0.6.0`,
and Psycopg 3 `3.1.17` for the Ubuntu 24.04 AMD64 capture. Script
`06_capture_native_postgresql_package_closure.sh` consumes that accepted report
and blocks if any selected candidate changes. It streams the neutral
`collect-native-postgresql-package-metadata` helper to the target, where the
helper resolves the complete dependency closure from existing apt metadata and
streams a checksum-bound metadata archive back. Target temporary state is
removed automatically; the target performs no apt update, network download,
install, database initialization, service mutation, or configuration change.

Script `06` then downloads only the exact target AMD64 Ubuntu `.deb` files on
the local workstation, verifies their apt-metadata hashes and sizes, performs
inert package/file/license inspection, captures public Ubuntu advisory pages,
writes manifests and complete checksums, and creates one offline transfer
bundle. Advisory affectedness remains `pending_review`, so capture does not
authorize transfer or installation.

The first operator run stopped before download because the target metadata
expressed the pgvector JIT dependency as the virtual package
`postgresql-16-jit-llvm`, provided by the already-selected `postgresql-16`
root. The corrected helper resolves exact candidate archive records and apt
virtual-package providers. A local Ubuntu 24.04 metadata replay resolved 98
packages and 98 package URIs with no unresolved rows. The accepted roots did
not change; rerun the same Script `06` command.

Validate the accepted root plan without target or network contact:

```bash
bash ./phase-28-apisachi-tokuli/scripts/06_capture_native_postgresql_package_closure.sh \
  --plan-only
```

Run the capture from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/06_capture_native_postgresql_package_closure.sh
```

If a run already returned complete verified target metadata but stopped before
creating the bundle, resume without repeating SSH metadata collection:

```bash
bash ./phase-28-apisachi-tokuli/scripts/06_capture_native_postgresql_package_closure.sh \
  --resume-latest
```

Resume mode verifies the retained platform, roots, counts, and every metadata
checksum before downloading. The complete dependency graph contains 98
packages, but EmceeDanko's captured apt simulation requires only nine missing
packages totaling 41.77 MiB. Script `06` downloads those nine packages on
DankoSurface and creates one checksum-bound bundle; operators do not manually
download the individual packages or run this acquisition inside org-lab.

The accepted Script `06` result contains nine apt-matched packages in the
checksum-bound Ubuntu 24.04 AMD64 bundle. Its outer sidecar, 51 internal
checksums, nine license records, and safe archive paths passed independent
review. Its later advisory review failed because Noble pgvector `0.6.0-1` is
affected by two current index-build vulnerabilities. That bundle shall not be
transferred or installed, and Script `06` is retained as historical capture
evidence rather than the current acquisition path.

## Reviewed pgvector replacement capture

The corrected capture discipline requires a complete exact-source advisory
decision set before any package payload download. Script
`07_capture_reviewed_pgvector_replacement_bundle.sh` enforces the reviewed
Ubuntu 24.04 AMD64 six-source decision file, verifies the accepted Script `06`
bundle checksum, and then verifies the official PostgreSQL Apt signing key,
signed `noble-pgdg` metadata, and exact
`postgresql-16-pgvector=0.8.7-1.pgdg24.04+1` record. Only after the advisory and
signed-metadata gates pass does it download that one replacement `.deb`.

The script excludes the blocked pgvector `0.6.0-1`, reuses the eight already
verified Ubuntu packages, captures the PGDG provenance and advisory decisions,
and writes a new checksum-bound bundle. It is local-only: no SSH, target
repository change, apt update, compilation, install, database initialization,
or service mutation occurs. Installation remains unauthorized until the new
capture is reviewed.

The first operator run passed the advisory gate and then stopped before
package download because PGDG Noble does not publish the initially assumed
`Packages.xz` index. The corrected script verifies the signed `Packages.gz`
coordinate instead, emits an explicit missing-index block, and bounds every
public download with connect and total timeouts. The corrected operator rerun
passed and its nine-package replacement bundle was independently accepted.
The command below is retained as the reproducible capture surface; do not
rerun it for the accepted artifact unless replacement capture is explicitly
required.

Validate the source and exact plan without package download:

```bash
bash ./phase-28-apisachi-tokuli/scripts/07_capture_reviewed_pgvector_replacement_bundle.sh \
  --plan-only
```

Run the reviewed replacement capture from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/07_capture_reviewed_pgvector_replacement_bundle.sh
```

## Native PostgreSQL installation preflight

The accepted Script `07` bundle is bound to the read-only Script `08`
installation preflight. Script `08` creates one attended SSH master, stages
only the neutral `preflight-native-database-installation` helper and accepted
bundle in a private target `/tmp` directory, verifies both hashes, runs an
offline apt simulation, retrieves a bounded report, and removes all target
temporary files. It requests no sudo password.

The preflight requires the exact Ubuntu 24.04 AMD64 host, nine package tuples,
bundle checksums, license rows, absent prior selected packages, free port 5432,
no existing cluster, sufficient `/var` capacity, and a download-disabled apt
plan that installs exactly the nine accepted packages and removes none. It
performs no apt update, network package download, install, database
initialization, or service/configuration change.

The first operator run safely blocked at apt simulation and removed all
temporary target files. The helper now uses the same `apt-get -s` form that
previously passed on EmceeDanko; simulation mode itself performs no download
or installation. Future failures return a bounded diagnostic class and output
hashes without retaining raw apt text. Rerun the same command below.

The next rerun exposed a helper control-flow defect: apt returned `100`, but
the generic `ERR` trap ran before the bounded classifier. Running the
simulation as an explicit conditional now preserves fail-closed behavior
while allowing its status classification to complete. No target state changed
in either blocked run.

Do not rerun Script `08` against the current bundle. Package-control review
found that PGDG pgvector `0.8.7` breaks JIT virtual versions below `19`, while
the captured Ubuntu PostgreSQL server provides version `17`. The bundle is
blocked from transfer and installation. The next gate inventories the exact
target `libllvm19` candidate required to evaluate the compatible PGDG
PostgreSQL 16 server package.

Validate locally without target contact:

```bash
bash ./phase-28-apisachi-tokuli/scripts/08_preflight_native_postgresql_installation.sh \
  --validate-only
```

Historical operator preflight command—currently blocked for this bundle:

```bash
bash ./phase-28-apisachi-tokuli/scripts/08_preflight_native_postgresql_installation.sh
```

Review the returned report before authorizing installation.

## Native PostgreSQL compatibility inventory

Script `09` replaces the blocked Script `08` rerun. It first proves the exact
JIT package-control conflict locally, then streams the neutral
`inspect-native-database-compatibility` helper to EmceeDanko. The helper reads
only the exact Ubuntu `libllvm19` candidate and bounded apt/capacity facts. It
writes no target file and performs no apt update, download, install, database,
service, configuration, or sudo operation.

Run from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/09_run_native_postgresql_compatibility_inventory.sh
```

Review the returned exact target coordinate before changing the advisory
decision set or downloading a replacement package.

The accepted Script `09` report records that exact `libllvm19` as both
installed and candidate on EmceeDanko. Canonical's four Noble records were
reviewed and accepted only for the bounded AMD64 PostgreSQL-JIT use. Script
`10_capture_compatible_native_postgresql_bundle.sh` enforces that new seven-
coordinate advisory set, re-verifies the captured signed PGDG metadata, and
downloads exactly two reviewed payloads: PGDG PostgreSQL 16.15 with JIT
virtual version `19`, and Ubuntu `libllvm19`. It replaces the incompatible
Ubuntu server and `libllvm17t64` while retaining the other seven verified
packages. It is local-only and does not install anything.

Validate all local inputs and the exact package plan without network access:

```bash
bash ./phase-28-apisachi-tokuli/scripts/10_capture_compatible_native_postgresql_bundle.sh \
  --plan-only
```

Run the compatible capture from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/10_capture_compatible_native_postgresql_bundle.sh
```

## Compatible native PostgreSQL installation preflight

The accepted Script `10` bundle is bound to Script `11`. Script `11` stages
only the neutral `preflight-compatible-native-database-installation` helper
and accepted bundle in private target `/tmp`, verifies their hashes, performs
an offline apt simulation, retrieves a bounded result, and removes all target
temporary files. It neither uses sudo nor installs anything.

The helper requires the exact Ubuntu 24.04 AMD64 host and exact nine-package
bundle. It verifies PostgreSQL's JIT-19 provide, pgvector's JIT constraint,
all internal checksums, seven accepted advisory rows, nine license rows, free
port 5432, no cluster, and adequate `/var` capacity. It explicitly requires
the already observed `libllvm19` version to be installed and requires the
other eight packages to be absent. The simulated plan may therefore contain
eight packages, or nine if apt elects to reinstall the same exact LLVM
payload; it may contain no other package and remove nothing.

Validate locally without target contact:

```bash
bash ./phase-28-apisachi-tokuli/scripts/11_preflight_compatible_native_postgresql_installation.sh \
  --validate-only
```

Run from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/11_preflight_compatible_native_postgresql_installation.sh
```

Review the returned report before authorizing installation.

## Compatible native PostgreSQL package installation

The accepted Script `11` receipt is bound to Script `12`. Script `12` requires
the explicit `--install` argument, stages the exact accepted bundle and the
neutral installer in private target temporary storage, verifies their hashes,
and requests sudo only for the package installation.

The installer disables all apt package sources and downloads. It installs the
six support/client packages first, records `create_main_cluster = false`, then
installs PostgreSQL and pgvector. A temporary service-start policy prevents
package post-install actions from starting PostgreSQL. The helper disables the
service at boot, requires zero clusters and a free port `5432`, validates all
nine package versions and the PostgreSQL, `psql`, pgvector, and Psycopg
runtimes, returns a bounded result, and removes temporary files.

Validate the source without target contact or installation:

```bash
bash ./phase-28-apisachi-tokuli/scripts/12_install_compatible_native_postgresql_packages.sh \
  --validate-only
```

Run the explicitly authorized installation from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/12_install_compatible_native_postgresql_packages.sh --install
```

Review the returned receipt before initializing or configuring a database.

The first Script `12` execution stopped at support-package apt exit `100`.
The server and pgvector stage did not run, and temporary cleanup passed. Do not
rerun Script `12` until the exact possibly partial package state is known.

Run the bounded read-only inspection from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/13_inspect_native_postgresql_installation_failure.sh
```

Script `13` returns exact status for the nine selected packages, bounded
dpkg/apt diagnostics, an offline support-package simulation, dependency-check
status, and service/cluster/listener facts. It does not install or repair a
package or change database/service state.

The accepted Script `13` result proved that the first installation changed no
selected package: only the pre-existing LLVM runtime is installed, the other
eight packages are absent, dpkg audit is clean, and PostgreSQL has no service,
cluster, or listener. The failure came from using apt `--no-download` with
explicit transferred package paths; that option is for packages already in
apt's download cache and prevented the real local-file acquisition step.

Script `14` is the corrected retry. It removes only that conflicting option.
Apt repository sources remain disabled, all network proxies point to a
rejecting loopback endpoint, and only the exact transferred local `.deb` paths
are supplied.

Run the corrected retry from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/14_retry_compatible_native_postgresql_package_installation.sh --install
```

The accepted Script `14` receipt proves that all nine exact packages are
installed while PostgreSQL remains clusterless, stopped, boot-disabled, and
without a listener.

## Native PostgreSQL cluster initialization

Script `15` binds that accepted receipt and requires explicit `--initialize`
authorization. It stages only the neutral
`initialize-native-database-cluster` helper, verifies its checksum, requests
attended sudo, retrieves a bounded result, and removes the temporary target
payload.

The helper re-verifies the package/runtime and clean-state contracts, creates
the distribution-managed PostgreSQL `16/main` cluster, enables data-page
checksums, configures UTF-8, peer local authentication, SCRAM-SHA-256 host
authentication, and `127.0.0.1:5432`, then requires the cluster to remain
stopped with manual startup and the PostgreSQL service disabled at boot. It
does not start PostgreSQL or create an application database, role, schema,
extension, credential, or secret.

Validate locally without target contact or initialization:

```bash
bash ./phase-28-apisachi-tokuli/scripts/15_initialize_native_postgresql_cluster.sh \
  --validate-only
```

Run the explicitly authorized initialization from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/15_initialize_native_postgresql_cluster.sh --initialize
```

The accepted Script `15` receipt proves that the exact `16/main` cluster is
initialized with the required local-only settings and remains stopped.

## Native PostgreSQL application database configuration

Script `16` binds that receipt and requires explicit `--configure`
authorization. Its configurable defaults are database `rag_catalog`,
non-login owner `rag_owner`, ingestion login `rag_ingest`, and retrieval login
`rag_retrieval`.

The neutral helper privately prompts on the target TTY for nonempty role
passwords and confirmations. It does not impose a project-specific password
length or complexity policy, and it does not store or emit those secrets. The
operator must retain them in an approved password manager for later protected
runtime configuration.

The helper temporarily starts the existing loopback-only cluster, creates the
empty database and isolated roles, enables pgvector `0.8.7`, revokes public
database access, gives both login roles only `CONNECT`, verifies the result,
and stops the cluster. The retrieval role also defaults transactions to read
only. No application schema, table, index, or content is created; reviewed SQL
migrations will define those objects and grant their exact privileges.

Validate locally without target contact or configuration:

```bash
bash ./phase-28-apisachi-tokuli/scripts/16_configure_native_postgresql_application_database.sh \
  --validate-only
```

Run from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/16_configure_native_postgresql_application_database.sh --configure
```

The first Script `16` run blocked before SQL because the existing
`postgresql@16-main.service` instance did not start. It created no application
database, role, extension instance, schema, table, index, or content. Do not
rerun Script `16` until the start failure is understood.

Run the bounded read-only inspection:

```bash
bash ./phase-28-apisachi-tokuli/scripts/17_inspect_native_postgresql_start_failure.sh
```

Script `17` returns exact cluster and systemd state, a non-starting
configuration probe, relevant path ownership and access facts, control-data,
listener and capacity facts, and hashes plus bounded classifications for the
last service-journal and cluster-log lines. It does not start, stop, restart,
enable, disable, or reset PostgreSQL and performs no database query or change.

The accepted Script `17` report isolates the fault to configuration parsing,
and exact package-source review identifies invalid IPv4 serialization as the
repair target. Script `18` binds that report and requires explicit `--repair`
authorization. Its neutral helper requires exactly one active
`listen_addresses` assignment and an effective value of `127.0.0.1`, changes
only that assignment to the canonical quoted PostgreSQL string form,
preserves a trailing comment when present and the file owner/group/mode, and
validates the complete candidate and installed configuration while the
cluster stays down.

Validate locally without target contact or configuration change:

```bash
bash ./phase-28-apisachi-tokuli/scripts/18_repair_native_postgresql_loopback_configuration.sh \
  --validate-only
```

Run the explicitly authorized repair from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/18_repair_native_postgresql_loopback_configuration.sh --repair
```

Review the returned receipt before retrying Script `16`.

The accepted Script `18` receipt proves that the current configuration parses,
but its identical before and after content hashes do not establish the cause
of the earlier service-start failure. Script `19` is therefore a separate
start/stop-only gate. It starts the existing cluster, proves local readiness
and the single loopback listener, stops it cleanly, and returns the final
service state without executing SQL or processing a password.

Validate locally without target contact or a service change:

```bash
bash ./phase-28-apisachi-tokuli/scripts/19_prove_native_postgresql_start_stop.sh \
  --validate-only
```

Run the explicitly authorized proof from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/19_prove_native_postgresql_start_stop.sh --prove
```

Review the returned receipt before preparing the application-database retry.

The operator-executed Script `19` passed, but Scripts `17`–`19` are historical
troubleshooting artifacts rather than required installation steps. Their
lessons are consolidated into the canonical workflow. Script `15` now writes
and server-validates the canonical quoted loopback setting. Script `16` now
parses the complete configuration, starts PostgreSQL, proves readiness and the
single loopback listener, and only then asks for passwords and configures the
database. It also returns bounded start-failure state and stops a partially
active cluster during cleanup.

The one canonical application-database command is:

```bash
bash ./phase-28-apisachi-tokuli/scripts/16_configure_native_postgresql_application_database.sh --configure
```

The failed historical attempt retained no role password, so the operator must
enter the selected ingestion and retrieval passwords and confirmations when
the corrected Script `16` reaches that stage.

The corrected operator-executed Script `16` passed. The accepted result proves
the empty `rag_catalog` database and isolated roles, pgvector `0.8.7`, zero
application relations, no retained or emitted secrets, clean shutdown, and an
inactive boot-disabled PostgreSQL service. Do not rerun Scripts `16`–`19` for
the normal workflow. The next implementation gate is a reviewed plain-SQL
application schema and privilege migration; no command for that gate is
published until its SQL, rollback, validation, and report contract are ready.

## Native PostgreSQL application schema migration

Script `20` binds the accepted corrected Script `16` receipt and requires the
explicit `--migrate` argument. It stages the neutral
`apply-native-application-schema` helper and checksum-bound migration `0001`,
starts the accepted cluster temporarily, applies one transaction, verifies
object ownership, empty-catalog state, vector and lexical types/indexes, and
the exact ingestion/retrieval privilege split, then stops PostgreSQL again.

Migration `0001` creates 20 empty base tables across `rag` and `rag_private`
plus five active-only views in `rag_search`. It writes only the migration
ledger row. It creates the `vector(768)` column and lexical GIN index but no
HNSW/IVFFlat index and no corpus content.

Validate locally without target contact:

```bash
bash ./phase-28-apisachi-tokuli/scripts/20_apply_native_postgresql_application_schema.sh \
  --validate-only
```

Run the explicitly authorized migration from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/20_apply_native_postgresql_application_schema.sh --migrate
```

Review the returned receipt before implementing the document catalog and
ingestion writer against the new schema.

The first operator run reached PostgreSQL but the SQL transaction failed. It
did not emit a pass marker, the uncommitted transaction was discarded, and
cleanup returned the cluster to its stopped state. The helper now captures the
raw SQL diagnostic only in private temporary storage, emits a bounded
SQLSTATE, migration line, failure class, byte count, and checksum, and removes
the raw diagnostic. Rerun the same Script `20` command; no separate repair
script is part of the workflow.

The second run exposed `ERR`-trap interception of the expected nonzero `psql`
status before that classifier could execute. The canonical helper now runs
`psql` as an explicit conditional, preserving the failure status while
allowing the bounded classifier to complete. The SQL migration is unchanged.

The third run classified the actual failure: the `postgres` OS identity could
not traverse the operator-owned mode-`0700` transfer directory to open the SQL
file by pathname. The corrected helper does not widen that directory. Root
opens the already checksum-verified migration and streams it to `psql` over
standard input. The same canonical helper now recognizes only an exact
already-applied migration and requires a complete PostgreSQL stop/start plus
post-restart schema, migration-ledger, and role-privilege verification before
reporting success. Disposable PostgreSQL `16.15` testing passed the complete
initial and post-restart contract.

Because none of the blocked target runs read and committed the SQL, the same
pre-acceptance review also strengthened migration `0001` with ordinary
composite foreign keys. They prevent cross-document or cross-artifact parent,
chunk, citation, relationship-evidence, and publication links. The active
document view now takes its class from the active document version. The
repeatable disposable regression proves those six rejection paths, the exact
role boundary, already-applied detection, and restart persistence.

The corrected operator-executed Script `20` then passed and is accepted.
Migration `0001` was applied on EmceeDanko and survived a complete PostgreSQL
stop/start with all schema, migration-ledger, and role-privilege checks
repeated successfully. The accepted database now durably contains three
schemas, 20 empty base tables, five active retrieval views, `vector(768)`, and
the lexical GIN index; it contains no corpus rows and no ANN vector index.
PostgreSQL was returned to the stopped, inactive, boot-disabled state. Do not
rerun Script `20` in the normal workflow. The next implementation work consumes
this schema through catalog/manifest validation and the incremental ingestion
writer; it does not rebuild the PostgreSQL foundation.

## Ishikawa ingestion-ownership migration local proof

Migration `0002_align_ingestion_ownership.sql` aligns the accepted empty
`0001` schema with the frozen Ishikawa ownership model. Before any target
mutation is prepared, run its disposable local proof from the repository
root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/21_test_ingestion_ownership_migration.sh
```

This test creates only temporary local PostgreSQL clusters/databases. It tests
the restarted `0001 → 0002` upgrade path, fresh `0001 + 0002` path, exact
schema equivalence, nonempty-legacy rejection, artifact-owned class behavior,
quarantine remediation linkage, and the unchanged ingestion/retrieval role
boundary. It removes the temporary cluster on every exit path and does not
contact EmceeDanko.

The accepted marker is:

```text
script_21_ingestion_ownership_migration_test=pass
```

The operator confirmed the checksum-identical underlying test before the
numbered wrapper was added. That result is accepted and does not need to be
rerun. Script `21` is now the canonical future command for this gate.

## Ishikawa ingestion-ownership target migration

Script `22` is the next operator command. It checksum-binds the accepted
Script `20` receipt, migrations `0001` and `0002`, and the neutral target
helper. The helper requires the exact empty `0001` state, applies or verifies
only `0002`, repeats the schema and privilege checks after a full PostgreSQL
stop/start, and returns PostgreSQL to its stopped, boot-disabled state.

Validate its sources without target contact:

```bash
bash ./phase-28-apisachi-tokuli/scripts/22_apply_ingestion_ownership_migration.sh \
  --validate-only
```

Run the target migration from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/22_apply_ingestion_ownership_migration.sh --migrate
```

It does not reinstall PostgreSQL, repeat migration `0001`, ingest documents,
change roles or passwords, create an ANN index, or enable services at boot.

The operator-executed Script `22` target helper applied migration `0002` and
passed its complete post-restart database contract. The original wrapper then
rejected one malformed structured-output line after the successful target
operation. The canonical source now emits three proper `key=value` fields.
The target migration is accepted through the evidence review; do not rerun
Script `22` in the normal workflow. The next numbered work is local
implementation and testing of the incremental ingestion writer.

## Ishikawa incremental writer proofs

Script `23` is the local, driver-neutral regression suite for the incremental
writer. The operator-executed suite passed all 64 tests. It does not connect
to PostgreSQL or a remote host and does not mutate corpus state. Do not rerun
it as a prerequisite for Script `24`; its accepted result is already bound by
the Script `24` source review.

Script `24` is the disposable target-native integration proof. It transfers
only checksum-bound application source, the two accepted schema inputs, and a
synthetic runner to EmceeDanko. The neutral helper temporarily starts the
boot-disabled native PostgreSQL cluster, verifies that the accepted
`rag_catalog` remains empty and at schema version 2, creates a separate
`ishikawa_writer_test` database, and exercises add, reuse, revise, reprocess,
quarantine, remediation, rollback, retirement, active retrieval views, and
retrieval-role isolation. It then drops the test database, proves
`rag_catalog` is unchanged, stops PostgreSQL, and removes temporary files.

Run from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/24_test_incremental_writer_on_emceedanko.sh --run
```

This command may prompt for the SSH key passphrase and target sudo password.
It does not request or use an application database credential, read
organizational documents, call a model, install packages, enable a service,
or mutate the accepted application database.

The operator-executed Script `24` passed and is accepted. The native writer
completed every synthetic lifecycle action, the forced PostgreSQL failure
rolled back atomically, the retrieval role could read active views but not
base tables, the disposable database was removed, and the accepted
`rag_catalog` remained unchanged. PostgreSQL returned to its stopped,
inactive, boot-disabled state, and all remote temporary files were removed.
Do not rerun Script `24` in the normal workflow. This accepts the persistence
writer boundary only; extraction, structural chunking, embedding submission,
retrieval, API, UI, and full portable installation remain separate work.

The consolidated fresh-install schema remains required for the portable
package, but it is deliberately deferred until the application schema is
stable. Producing it now would create needless rework. The current next gate
is the producer pipeline, beginning with extraction qualification.

## Ishikawa PDF extraction qualification

Script `25` qualifies the frozen Poppler-first extraction candidate against
all six PDFs and 27 pages in Synthetic Corpus V1. It binds the accepted
EmceeDanko Poppler inventory, exact source identities, the original synthetic
manifest and ground truth, a separate held-out structural acceptance profile,
the neutral target capture program, and the local evaluator.

The target receives only the capture program, source-identity manifest, and
six fully synthetic PDFs. It does not receive the evaluator or held-out truth.
The capture program runs `pdfinfo`, `pdftotext -layout`, and
`pdftotext -bbox-layout` twice with bounded resources and no shell, rejects
non-repeatable results, and returns a raw synthetic observation archive. The
wrapper grades that archive locally for page inventory, the intentional blank
page, token preservation and reading order, headings, ordered material,
repeated furniture, table geometry, form field/value geometry, checkbox
associations, output identities, and repeatability.

Validate the sources without target contact:

```bash
bash ./phase-28-apisachi-tokuli/scripts/25_qualify_pdf_extraction_on_emceedanko.sh \
  --validate-only
```

Run the target qualification from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/25_qualify_pdf_extraction_on_emceedanko.sh --run
```

The command may prompt once for the SSH key passphrase. It does not use sudo,
install packages, change services, call a model, access PostgreSQL, read
organizational documents, or transfer the held-out truth. It creates its own
local content-free report and, on acceptance, retains the raw fully synthetic
Poppler archive under the ignored local artifact area. It always removes its
target temporary directory. A pass routes next to normalization and
structural-unit implementation.

The first operator run completed the target capture but blocked during local
held-out evaluation. The second operator run again passed capture and retained
the checksum-verified archive, then stopped at a Windows-mounted-filesystem
mode operation before local grading. Review corrected physical bounding-box
ordering, repeated table-cell lookup, and two punctuation omissions in the
held-out synthetic truth. The retained second-run archive then passed every
local held-out check without another target run.

Script `25` is accepted. Do not rerun it in the normal workflow. The canonical
same-numbered wrapper now copies the synthetic archive without making Unix mode
emulation an acceptance dependency and verifies the retained copy's checksum.
The next numbered gate is normalization and structural-unit creation from the
accepted synthetic Poppler artifact.

## Ishikawa normalization and structural units

Script `26` is entirely local. It checksum-binds the accepted Script `25`
archive and receipts, reruns the existing 64-test application suite, runs 13
held-out normalization tests, creates the normalized artifact twice, and
requires byte-identical artifacts and result facts before retaining anything.

Run from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/26_create_normalized_structural_units.sh --run
```

It contacts no remote system, database, or model service and requests no
password. It retains one fully synthetic canonical JSON artifact and checksum
under the ignored local artifact area. Acceptance requires
`script_26_normalization=pass;next_gate=structure_aware_chunking_and_metadata`.

## Ishikawa native PostgreSQL retrieval adapter

Operator-executed Script `65` accepted standalone contextual-query resolution.
Script `66` is the next local-only qualification gate:

```bash
bash ./phase-28-apisachi-tokuli/scripts/66_qualify_native_postgresql_retrieval_adapter.sh --run
```

It binds the accepted Script `65` receipt, runs the complete 250-test suite,
and qualifies the native read-only retrieval port with deterministic injected
dependencies. It proves that only the resolved standalone query is embedded;
the original request is used only for conversation-token accounting. It also
proves exact, lexical, and vector execution, equal-weight RRF, pre-candidate
filters, post-hydration filter checks, citable-evidence relevance,
reconstruction, and sufficiency.

Script `66` contacts no target, network endpoint, PostgreSQL database, or model;
reads no credential; starts no listener; and makes no schema change. One-hop
relationship loading and explicit complete-procedure reconstruction remain
the next implementation gate.

## Ishikawa configured retrieval runtime

Operator-executed Script `69` accepted the bounded native loopback listener.
Script `70` is the next local-only gate:

```bash
bash ./phase-28-apisachi-tokuli/scripts/70_qualify_configured_retrieval_service_runtime.sh --run
```

It checksum-binds the accepted Script `69` receipt, runs all 270 local tests,
validates the 12 configuration profiles, and assembles the concrete Gemma,
Nomic, PostgreSQL, source-resolution, orchestration, and listener-factory
boundaries. The exact Gemma token counter uses the configured vLLM `/tokenize`
route with special-token counting enabled.

Script `70` uses injected dependency functions and proves that configuration
assembly and a direct-injection short circuit read no credential and contact no
target, PostgreSQL database, embedding endpoint, or generation endpoint. It
does not start the service. A pass routes next to a separately bounded live
qualification of the configured generation-tokenizer endpoint.

## Ishikawa configured generation-tokenizer endpoint

Operator-executed Script `70` accepted the configured runtime assembly. Script
`71` is the next bounded target gate:

```bash
bash ./phase-28-apisachi-tokuli/scripts/71_qualify_configured_generation_tokenizer_endpoint.sh --run
```

It checksum-binds the accepted Script `70` receipt and exact installed Gemma
tokenizer qualification, runs all 270 local tests, transfers neutral runtime
sources into a target temporary directory, and uses the real Ishikawa native
token-counter adapter for two identical synthetic requests to the configured
loopback `/tokenize` endpoint. Equal validated counts prove repeatability for
the evidence-budget dependency.

The command may prompt once each for the SSH key passphrase, target sudo
password, and Gemma API key. The API key is entered through the attended target
terminal and is never read from a stored file, transferred from the local
host, written to an artifact, or retained. The qualifier preserves the managed
Gemma service's initial state, performs no generation, database, embedding, or
organizational-content operation, retains only a content-free local
measurement, and removes the target temporary directory.

Operator-executed Script `71` passed. The configured `/tokenize` endpoint
returned the same exact count for both synthetic requests, the response
contract and 204,800-token minimum passed, no generation occurred, the API key
was not retained, and the initially active Gemma service was left active.

## Ishikawa configured application-host runtime

Script `72` is the next bounded EmceeDanko gate:

```bash
bash ./phase-28-apisachi-tokuli/scripts/72_qualify_configured_runtime_on_emceedanko.sh --run
```

It checksum-binds accepted Scripts `68` and `71`, runs all 270 local tests,
stages the exact Python package and 12 runtime profiles in a target temporary
directory, verifies AMD64 Ubuntu 24.04, Python 3.12, and PyYAML 6.0.1, then
temporarily binds the configured native listener to `127.0.0.1:1384`. One
synthetic injection request must return the fixed `security-rejected`
application response without reading a secret or contacting PostgreSQL,
Gemma, Nomic, or the tokenization endpoint. The listener must stop and release
port 1384 before acceptance.

This is an application-host runtime compatibility proof, not a live chat or
external-service reachability test. It makes no installation, package,
database, service, or configuration change and requires no sudo or application
secret. It may prompt only for the SSH key passphrase. A pass routes next to
the still-explicit application-host-to-model-service transport decision.

Operator-executed Script `72` passed. EmceeDanko assembled the exact runtime,
temporarily bound `127.0.0.1:1384`, returned the fixed `security-rejected`
response for the synthetic injection request, made zero dependency calls and
environment reads, released the listener, and removed its temporary payload.
The retained content-free artifact and checksum passed local evaluation.

The operator froze the KISS transport boundary: Ishikawa owns only configured
endpoint URLs; the EmceeDanko prototype uses one operator-started SSH
connection carrying both loopback forwards; the existing runtime endpoint
configuration remains unchanged; Dalton, native-vLLM LAN exposure, firewall
changes, and another Ishikawa service are excluded; and org-lab may supply its
approved direct model-host endpoints through deployment configuration.

Script `73` is the bounded transport qualification:

```bash
bash ./phase-28-apisachi-tokuli/scripts/73_qualify_application_host_model_transport.sh --run
```

It checksum-binds accepted Script `72`, runs all 270 local tests, creates an
isolated local SSH agent, loads the operator-selected model-host identity, and
forwards that agent through the existing application-host SSH connection. No
private key is copied. From the application host, one temporary SSH process
forwards local ports `8000` and `8001` to the model host's loopback services.
The qualifier requires direct LAN access to both native ports to remain
blocked, requires HTTP `200` from both tunneled `/health` routes, stops the
tunnel, verifies both local ports are released, and removes all temporary
target state.

The command may prompt for the application-host and model-host SSH-key
passphrases. It does not request vLLM API keys, invoke inference, embedding, or
tokenization, use organizational content, run sudo, or modify packages,
services, firewalls, model configuration, or Ishikawa configuration.

Operator-executed Script `73` passed. Direct access to the native model ports
remained blocked, both forwarded `/health` endpoints returned HTTP `200`, no
private key was copied, no API credential or content was read, and the bounded
qualification tunnel was stopped and removed.

That proof does not make forwarding part of Ishikawa. The deployment boundary
is now explicit: the operator establishes ports `8000` and `8001` before
starting or qualifying Ishikawa and closes them after exit. Ishikawa stores
only the endpoint URLs in YAML, never starts or stops the forwarding process,
and fails closed when a configured dependency is unreachable.

Script `74` is the configured live dependency qualification:

```bash
bash ./phase-28-apisachi-tokuli/scripts/74_qualify_configured_model_dependencies_on_emceedanko.sh --run
```

Run it only after the operator-managed forwarding is active on EmceeDanko. It
checksum-binds accepted Script `73`, runs all 270 local tests, stages the exact
runtime modules plus `runtime_dependencies.yaml` and
`reconstruction_profile.yaml`, and requires loopback listeners at
`127.0.0.1:8000` and `127.0.0.1:8001`. It prompts on the EmceeDanko terminal
for the Gemma and Nomic API keys, then makes two deterministic synthetic
tokenizer calls and two singleton synthetic embedding calls through the exact
production adapters. It retains no key, probe text, or vector and makes no
generation or database call.

The script does not create, alter, or close forwarding. Acceptance requires
both listeners to remain present with the same listener identities after the
calls. The operator closes forwarding separately after Ishikawa or the
qualification exits.

Operator-executed Script `74` passed. The configured Gemma tokenizer returned
the same 11-token count twice, and the configured Nomic endpoint returned the
same validated 768-dimensional singleton embedding twice with a maximum delta
of zero. The accepted artifact retains no credential, probe text, or vector,
and the operator-managed forwarding remained unchanged.

Script `75` is the configured live-runtime gate:

```bash
bash ./phase-28-apisachi-tokuli/scripts/75_qualify_configured_live_runtime_on_emceedanko.sh --run
```

Run it while the same operator-managed forwarding remains active. It binds the
accepted Script `74` evidence, runs all 270 local tests, stages the exact
runtime and 12 profiles, starts the existing boot-disabled PostgreSQL cluster,
and verifies that the accepted schema-v4 `rag_catalog` is still empty. It then
prompts on the target terminal for the Gemma key, Nomic key, and existing
`rag_retrieval` password.

One synthetic professional question traverses the real loopback HTTP listener,
Gemma scope classification, deterministic direct-query resolution, singleton
Nomic embedding, read-only PostgreSQL retrieval, and exact Gemma tokenization.
Because the accepted catalog is intentionally empty, the required result is
HTTP `200` with application status `insufficient-evidence`; grounded generation
must not run. Acceptance also requires the catalog to remain unchanged, the
retrieval listener to stop, PostgreSQL to return to its stopped/disabled state,
and both external forwarding listeners to remain unchanged. No raw request,
response, vector, or credential is retained.

Operator-executed Script `75` passed. It returned HTTP `200` with application
status `insufficient-evidence`; scope ran once, singleton embedding ran once,
the read-only retrieval connection opened once, tokenization ran twice, and
grounded generation did not run. The accepted database remained empty and
unchanged, the listener stopped, PostgreSQL returned to stopped/disabled, and
operator-owned forwarding remained unchanged.

## Ishikawa operator-ingestion command

Script `76` is the next local-only implementation gate:

```bash
bash ./phase-28-apisachi-tokuli/scripts/76_qualify_operator_ingestion_command.sh --run
```

It checksum-binds accepted Script `75`, runs all 279 tests, and qualifies the
operator-ingestion control plane with injected non-networking database,
producer, and writer ports. It proves that validation-only never calls the
producer or writer; add processes only the changed document; reuse and
retirement do not process documents; quarantine reaches the writer without a
prepared document; rejected plans reach neither dependency; and protected
reports remain mode `0600` with no absolute source path in terminal output.

Script `76` contacts no target, PostgreSQL server, Nomic endpoint, or Gemma
endpoint, reads no credential, and changes no package, schema, service, or
corpus. A pass routes to concrete native producer and PostgreSQL adapter
integration.

Operator-executed Script `76` passed. Script `77` then accepted the same
control plane and atomic writer against disposable native PostgreSQL on
EmceeDanko. It published six synthetic documents and 126 chunks, proved reuse
and quarantine behavior, dropped the disposable database, and left the empty
accepted database unchanged.

Script `78` accepted `NativeDocumentProducer` as the bounded changed-document
production contract. Script `79` accepted the live Poppler, normalization,
structural-chunking, and Nomic document-embedding stage on EmceeDanko. Its six
synthetic documents produced 230 normalized source units, 126 chunks, and 126
768-dimensional embeddings. Held-out extraction and semantic comparison
passed, the seven accepted artifacts are checksum-bound, and neither a
credential nor organizational content was retained.

Script `80` connects those already-accepted surfaces without repeating model
or PostgreSQL work:

```bash
bash ./phase-28-apisachi-tokuli/scripts/80_qualify_live_producer_ingestion_connection.sh --run
```

It binds the accepted Script `78` and Script `79` receipts and live artifacts,
runs all 287 local tests, and executes one empty-corpus operator plan through
`NativeDocumentProducer`, the strict artifact adapter, and an observed writer
handoff. Acceptance requires exactly six prepared documents, 27 pages, 231
writer-ready structural units, 126 chunks, one embedding space, one producer
call, one retention call, one writer call, protected reports, and producer
workspace cleanup. Validation-only must call neither producer nor writer.

Script `80` is local-only. It contacts no target, database, or model endpoint,
reads no credential, and retains no document text or vector. A pass routes to
the portable operator-ingestion entrypoint.

Script `81` qualifies that portable operator-ingestion command boundary:

```bash
bash ./phase-28-apisachi-tokuli/scripts/81_qualify_portable_operator_ingestion_entrypoint.sh --run
```

It checksum-binds the accepted Script `80` receipt and artifact, runs all 293
local tests, and exercises five dependency-injected command scenarios. The
only accepted modes are `--validate-only` and `--publish`. Validation-only
must call neither the document producer nor the writer. Publication must call
each exactly once. Missing production dependencies and unknown arguments,
including attempted secret-bearing arguments, must fail before opening a
database connection. Every opened connection must close on success or
failure, and unexpected dependency details, source paths, credentials, source
content, and vectors must not enter terminal output or retained evidence.

Script `81` is local-only. It contacts no target, PostgreSQL server, or model
endpoint, reads no credential, and changes no schema, package, service, or
corpus. A pass accepts the portable command boundary and routes next to
assembling its concrete protected-environment, Psycopg, and live document
producer runtime dependencies.

Script `82` qualifies that configured runtime assembly:

```bash
bash ./phase-28-apisachi-tokuli/scripts/82_qualify_configured_operator_ingestion_runtime.sh --run
```

It checksum-binds accepted Script `81`, runs all 299 local tests, validates
the separate ingestion dependency profile, and assembles fixed operator paths,
the lazy native Psycopg `rag_ingest` connection, protected Nomic and database
credential providers, `NativeDocumentProducer`, and the incremental writer.
Assembly must read no credential and contact no dependency. An injected
validation-only execution may read only the synthetic database credential,
must use `rag_ingest`, and must close its planning connection; it may not read
the Nomic credential, process documents, retain artifacts, or call the writer.

Script `82` is local-only. It contacts no target, PostgreSQL server, or model
endpoint and changes no schema, package, service, or corpus. A pass routes to
implementation of the concrete live document artifact stage; that stage is
not silently claimed by runtime assembly.

Script `83` qualifies the live document artifact-stage process boundary:

```bash
bash ./phase-28-apisachi-tokuli/scripts/83_qualify_live_document_artifact_stage.sh --run
```

It checksum-binds accepted Scripts `79` and `82`, runs all 304 local tests,
and passes the six-document accepted live artifacts through the exact process
adapter, `NativeDocumentProducer`, and strict artifact adapter. The adapter
submits only planner-selected documents, invokes one absolute executable
without a shell, passes the Nomic credential only on standard input, and
requires a bounded result that checksum-binds normalized, chunk, and embedding
artifacts to the validation, manifest, method profile, and model identities.

Script `83` contacts no target, database, or model and retains no source text,
vector, or credential. A pass accepts the process boundary, not the pipeline
executable behind it. Building that neutral, repository-free installed
executable is the next gate.

Script `84` qualifies the neutral live document pipeline executable:

```bash
bash ./phase-28-apisachi-tokuli/scripts/84_qualify_live_document_pipeline_executable.sh --run
```

It checksum-binds accepted Script `83`, runs all 310 local tests, and exercises
`ishikawa-produce-artifacts` through dependency-injected stage processes. The
executable validates the planner request, stages only the requested
checksum-bound PDFs, runs extraction, normalization, structural chunking, and
embedding in fixed order, scopes the credential to embedding, removes its
temporary source workspace, and returns the exact checksum-bound result
contract accepted by Script `83`.

Script `84` contacts no target, database, or model and retains no source text,
vector, or credential. A pass accepts the executable implementation and routes
next to native execution of that exact command on EmceeDanko.

Scripts `85` through `87` completed the live installed-ingestion boundary.
Script `85` proved the exact pipeline executable with live Nomic against the
six synthetic documents on EmceeDanko. Script `86` connected that pipeline to
the configured ingestion runtime and a disposable native PostgreSQL database,
then proved the accepted database unchanged. Script `87` qualified the final
repository-free `ishikawa-ingest` and `ishikawa-produce-artifacts` installed
commands, including bounded progress, interruption, and content-addressed
artifact retention.

Script `88` assembled the application-only package:

```bash
bash ./phase-28-apisachi-tokuli/scripts/88_assemble_portable_ishikawa_application_package.sh --run
```

The accepted deterministic archive contains 70 final application files and 42
Python modules. It contains no corpus, credential, database state, schema
migration, service mutation, model response, or repository reference. All 319
local tests, internal checksums, a fresh temporary install, and the package
coding-standard evaluation passed.

Script `89` installs that closed archive on EmceeDanko:

```bash
bash ./phase-28-apisachi-tokuli/scripts/89_install_and_qualify_ishikawa_application_on_emceedanko.sh --run
```

Before target contact it re-evaluates the archive against the current
`Deployable Package Final-State Standard`. It then uses one reusable strict
SSH connection, verifies Ubuntu 24.04 AMD64 and the native dependencies,
installs only into a previously absent `~/Documents/Ishikawa`, validates the
installed configuration and 42 Python modules, returns content-free evidence,
and removes the temporary transfer directory. It uses no sudo and does not
contact or change PostgreSQL, model endpoints, credentials, services, source
documents, or operator-managed port forwarding. A pass routes to assembly of
the single consolidated fresh-install database schema.

Script `90` assembles that final database schema package locally:

```bash
bash ./phase-28-apisachi-tokuli/scripts/90_assemble_consolidated_database_schema_package.sh --run
```

It checksum-binds the accepted Script `89` result and the four exact schema
ancestors retained as development evidence. It then validates one canonical
version-4 `schema.sql`, packages only that final schema with its fresh-install
command, operator explanation, and checksum inventory, and proves the archive
is reproducible and compliant with the current coding standard. The package
contains 20 final tables, 14 indexes, 5 read-only retrieval views, and one
consolidated baseline identity; it contains no historical migration, patch, or
repair file.

Script `90` is local-only. It applies both the four accepted ancestors and the
consolidated schema to separate throw-away local PostgreSQL databases and
requires their normalized final catalogs to match exactly. It contacts no
remote target, reads no credential, and changes no persistent database or
service. A pass routes to package execution and host-posture qualification in
a disposable EmceeDanko database before fresh deployment.

Script `91` qualifies that exact package on EmceeDanko:

```bash
bash ./phase-28-apisachi-tokuli/scripts/91_qualify_database_schema_package_on_emceedanko.sh --run
```

It rechecks the closed archive against the current coding standard, transfers
only the archive and neutral verifier, and uses the packaged `install-schema`
command against a new disposable database. Acceptance requires PostgreSQL
16.15 with pgvector 0.8.7, exact catalog equivalence with the accepted
schema-version-4 database, the consolidated baseline identity, frozen ingest
and retrieval privileges, restart persistence, disposable-database removal,
and an unchanged accepted empty database.

The existing cluster must begin stopped, manual, loopback-only, and disabled
at boot. Script `91` returns it to that posture and removes its target transfer
directory. It installs no package, changes no role, reads no credential,
contacts no model, and processes no source document or embedding.

Scripts `92` and `93` complete the native Retrieval API health boundary.
Script `92` qualifies the final installed foreground command, loopback
liveness, fail-closed readiness, graceful termination, and listener cleanup.
Script `93` proves that readiness requires the validated configuration,
protected storage, an active read-only corpus, Gemma health, and Nomic health,
while the public response remains content-free.

Scripts `94` through `97` complete the first local observability boundary.
They qualify classified structured JSONL logging, the owner-only logging
control socket, low-cardinality operational metrics, and bounded retention.
The frozen retention defaults are 30 days for retrieval/operational logs, 30
days for metrics logs, and 90 days for audit logs. Script `97` also validates
the optional daily user timer without installing or enabling it.

Script `98` qualifies the boot-disabled native Retrieval API service unit:

```bash
bash ./phase-28-apisachi-tokuli/scripts/98_qualify_native_retrieval_service_lifecycle.sh --run
```

It runs all 360 native tests, validates the final systemd user unit, stages the
exact installed foreground command in temporary storage, proves loopback
liveness and graceful `SIGTERM`, and verifies listener and control-socket
cleanup. It does not install or enable the unit and contacts no database,
model, credential, corpus, or target.

Script `99` qualifies the host-mounted Next.js Chat UI:

```bash
bash ./phase-28-apisachi-tokuli/scripts/99_qualify_host_mounted_nextjs_chat_ui.sh --run
```

It checksum-binds accepted Script `98`, reruns all 360 native tests, and uses
the already-local architecture-matching
`node-24-slim-nextjs-16-4-1` image. It runs eight JavaScript contract tests,
builds Next.js 16.4.1, then starts one temporary local container and a safe
local Retrieval API fixture. Acceptance requires the page, web liveness,
dependency-aware readiness, and server-side `/api/v1/chat` proxy to pass.

The browser never receives the native Retrieval API location or any
credential. The visible transcript may remain longer, while each request is
bounded to the newest 12 prior turns, 65,536 history characters, and 20
structured source references. Source cards show validated excerpts and page
anchors; open and download remain disabled. The command does not pull, build,
retag, or alter the runtime image and removes every temporary process and
container. A pass routes next to one explicit start/status/stop stack command.

Script `100` qualifies the explicit Ishikawa stack-control command:

```bash
bash ./phase-28-apisachi-tokuli/scripts/100_qualify_explicit_stack_control.sh --run
```

It reruns all 360 native tests, inspects the final portable command and durable
contract, and uses deterministic local command adapters in a disposable
installed tree. Acceptance proves PostgreSQL → Retrieval API → web startup,
readiness between layers, ready and stopped status, reverse-order shutdown,
missing-credential rejection, credential non-disclosure, and failed-start
rollback. It does not contact or change a real service, database, container,
image, credential, model endpoint, forwarding session, corpus, or host port.

Script `101` assembles the refreshed final-state Ishikawa application package:

```bash
bash ./phase-28-apisachi-tokuli/scripts/101_assemble_final_ishikawa_application_package.sh --run
```

It checksum-binds the accepted Script `100` result, reruns all 360 native
tests, and packages the current Python application, host-mounted Next.js
source, runtime YAML, operator commands, final systemd definitions, and
portable operating documentation. It deliberately excludes tests, corpus
content, credentials, historical migrations, mutation or repair helpers, and
repository-specific names from the deployable payload.

The command assembles the package twice, requires byte-identical inventories,
checks every packaged file against the coding standard, verifies internal
checksums after extraction, and performs one fresh disposable installation.
The installed Retrieval API and retention configuration must validate without
contacting PostgreSQL, Gemma, Nomic, Docker, or a remote target. A pass routes
next to installation and qualification of this refreshed package on
EmceeDanko.

Script `102` installs that exact refreshed package as a non-destructive
candidate on EmceeDanko:

```bash
bash ./phase-28-apisachi-tokuli/scripts/102_install_final_application_candidate_on_emceedanko.sh --run
```

It rechecks the closed archive against the current coding standard, transfers
only the archive and a neutral verifier, and installs or exactly reuses
`~/Documents/Ishikawa-v1-candidate`. It validates all 94 installed payload
files: 47 Python modules, 11 web files, 19 configuration files, 10 commands,
4 operating documents, and 3 systemd definitions.

The existing `~/Documents/Ishikawa` installation is not overwritten, read, or
changed. The gate uses no sudo, starts no service, reads no credential, and
contacts no database, model endpoint, container, source document, or port
forward. A pass routes to a separately reviewed candidate promotion and
end-to-end Ishikawa test.

Script `103` promotes the exact qualified candidate into the canonical path:

```bash
bash ./phase-28-apisachi-tokuli/scripts/103_promote_ishikawa_application_candidate.sh --run
```

It checksum-binds both the old and final application archives and requires the
installed old and candidate trees to match those payloads exactly. With the
stack stopped, it renames the old installation to
`~/Documents/Ishikawa-pre-v1`, renames the candidate to
`~/Documents/Ishikawa`, and installs the three exact user systemd definitions.

The promotion is rollback-protected, deletes nothing, starts no service, and
enables nothing at boot. Any changed old installation, conflicting unit,
managed Ishikawa service or state, or post-promotion mismatch blocks and
restores the prior directory arrangement. An unrelated process using a future
application port does not block file promotion; port availability is enforced
by the end-to-end startup gate. A pass routes to the first complete end-to-end
Ishikawa test.

Scripts `104` through `106` prove the complete installed runtime. Script `104`
publishes or exactly reuses the six-document synthetic corpus, starts the
explicit stack, sends one cited chat request through Next.js, the Retrieval
API, PostgreSQL, Nomic, and Gemma, then stops the stack. Scripts `105` and `106`
bind the accepted transaction-boundary correction into the installed runtime
and repeat that full proof without losing the populated corpus. The accepted
result contains 6 active documents, 27 pages, 126 chunks, 126 citations, and
126 embeddings; its answer and citation closure pass, and the stack finishes
stopped and boot-disabled.

Script `107` assembles the single final Ishikawa v1 deployment package:

```bash
bash ./phase-28-apisachi-tokuli/scripts/107_assemble_ishikawa_v1_deployment_package.sh --run
```

It expands only the accepted corrected application package and accepted final
database-schema package, adds one neutral outer verifier, and emits a
deterministic checksum-bound archive. The 104-file package contains 97
application-component files and 4 database-component files plus its outer
README, verifier, and checksum manifest. It contains no corpus, credential,
operating-system package, container image, historical migration, repair,
mutation, patch, or development-specific reference.

Script `108` qualifies that exact consolidated package on EmceeDanko:

```bash
bash ./phase-28-apisachi-tokuli/scripts/108_qualify_ishikawa_v1_deployment_package_on_emceedanko.sh --run
```

It performs a fresh temporary application installation and installs the final
schema into a disposable PostgreSQL database. It requires exact catalog
equivalence with the accepted schema, validates final object and privilege
contracts, and compares the populated accepted corpus before and after. It
then removes the temporary application and database and restores the initial
PostgreSQL running state. The active application, accepted database, model
endpoints, credentials, source documents, service enablement, and operator
port forwarding are not changed.

Script `109` accepts the exact host-qualified archive as Ishikawa v1:

```bash
bash ./phase-28-apisachi-tokuli/scripts/109_accept_ishikawa_v1_deployment_package.sh --run
```

It binds the assembly and EmceeDanko host-qualification evidence, reverifies
the unchanged archive and current coding standard, and writes one durable
acceptance receipt. It does not rebuild or duplicate the deployment archive
and contacts no target or runtime dependency. The portable application and
schema package is accepted at this gate; Ubuntu 26 native prerequisite capture
and target qualification remain separate work before installation in org-lab.

Script `110` prepares the neutral Ubuntu 26 prerequisite-inventory kit:

```bash
bash ./phase-28-apisachi-tokuli/scripts/110_prepare_ubuntu26_native_prerequisite_inventory.sh --run
```

It binds the accepted Ishikawa v1 release and packages only a README, a neutral
read-only inventory command, and their checksum manifest. The kit contains no
phase numbering, repository terminology, environment name, credential, or
package payload. It contacts no target or network and performs no download or
installation. Its later target-side run records Ubuntu, AMD64, Python,
Poppler, PostgreSQL, pgvector, Psycopg, Docker, Node-image, package-candidate,
package-health, port, service-state, and storage facts into an operator-chosen
temporary directory for return and cleanup.

Script `111` qualifies the portable Ishikawa product documentation:

```bash
bash ./phase-28-apisachi-tokuli/scripts/111_qualify_ishikawa_product_documentation.sh --run
```

It binds the accepted Script `110` evidence, reruns all 360 native tests, and
checks six documents against the actual installed commands, YAML profiles,
ports, roles, retrieval settings, context budget, and retention settings. The
qualified set contains the operator guide, command sheet, application
definition, application design, as-built architecture, and complete chunking,
ingestion, and retrieval method.

The documents contain no target-specific name, phase or script reference,
credential material, or repository path and are suitable for a refreshed
portable package. This gate does not rebuild or modify the already accepted
v1 archive, contact a target, or change a runtime component. A pass routes to
one deliberate package refresh that adds the qualified documents.

Script `112` captures the unchanged live v1 retrieval baseline against the
fixed 13-case synthetic set:

```bash
bash ./phase-28-apisachi-tokuli/scripts/112_capture_ishikawa_retrieval_tuning_baseline.sh --run
```

It is an observation gate, not a release mutation. It makes no package,
configuration, database, service, forwarding, or credential change. The
accepted run retained all contract-valid synthetic responses and measured the
current answer, abstention, evidence, source-use, and latency behavior.

Before retrieval tuning, Script `113` freezes the exact accepted deployment
archive and the accepted Script `112` observation as the immutable Ishikawa
v1 fallback checkpoint:

```bash
bash ./phase-28-apisachi-tokuli/scripts/113_freeze_ishikawa_v1_fallback_checkpoint.sh --run
```

The checkpoint does not rebuild or duplicate the 104-file v1 package. It
reverifies that existing archive and records only its exact hash, the Script
109 release-receipt hash, and the Script 112 baseline hash. A pass closes v1
against tuning changes. All subsequent retrieval-tuning implementation and
qualification belongs to Ishikawa v1.1; rollback uses the unchanged accepted
v1 deployment archive.

Script `114` qualifies the isolated v1.1 known-document routing correction
and diagnoses the two dependency failures retained in the v1 baseline:

```bash
bash ./phase-28-apisachi-tokuli/scripts/114_qualify_v1_1_query_routing_and_diagnose_baseline.sh --run
```

It first rebinds the immutable Script `113` checkpoint, runs all 367 native
tests, and proves that the v1.1 synthetic case set changes only the expected
result for the deliberately vague document question. It then transfers one
neutral inspector to a private temporary directory on EmceeDanko and reads
only existing content-free retrieval and metric logs for the two baseline
request identities. The returned artifact records stage names, the last
completed stage, and the dependency-failure boundary; it contains no
question, answer, prompt, excerpt, chunk, vector, credential, or document
content.

This is a read-only qualification gate. It does not rebuild or install a
package, alter the accepted v1 archive, start or stop the stack, write the
database, call Gemma or Nomic, change forwarding, or modify target
configuration. Target temporary files are removed before completion. A pass
routes to deliberate assembly and installation of a separate v1.1 candidate.

Script `115` qualifies the local Ishikawa v1.1 tuning prerequisites:

```bash
bash ./phase-28-apisachi-tokuli/scripts/115_qualify_local_retrieval_tuning_preflight.sh --run
```

It binds the clean Script `114` routing qualification, immutable v1 archive,
and frozen `T01` through `T07` tuning decisions, then runs all 367 native tests.
On DankoSurface it verifies the exact Ubuntu/ARM64 host identity, HTTP `200`
from the operator-forwarded Gemma and Nomic health endpoints, and the exact
six-document active synthetic corpus through `rag_retrieval` in a repeatable-
read, read-only PostgreSQL transaction.

The script prompts only for the local PostgreSQL retrieval password when it is
not already supplied through the protected environment. It does not request a
Gemma or Nomic key because it makes no inference or embedding request. It uses
no sudo, contacts no remote host, changes no forwarding, reads no corpus text or
vector, writes no database or service state, and builds no package. A pass
routes to implementation and measurement of the local read-only MRR evaluator;
the v1.1 deployment build remains deferred until tuning acceptance.

Script `116` inventories the local native PostgreSQL tuning posture when the
Script `115` corpus prerequisite is absent:

```bash
bash ./phase-28-apisachi-tokuli/scripts/116_inventory_local_postgresql_for_tuning.sh --run
```

It uses attended local sudo only to read protected PostgreSQL identities and
configuration. It records whether the Ishikawa database and roles are absent,
partial, or present without creating, removing, or changing them.

Script `117` establishes the checksum-bound six-document tuning corpus from
the canonical final schema and synthetic source PDFs:

```bash
bash ./phase-28-apisachi-tokuli/scripts/117_establish_local_synthetic_tuning_corpus.sh --run
```

It reuses the exact reviewed native PostgreSQL, pgvector, Psycopg, and Poppler
dependencies; creates the local application roles and database; runs the real
ARM64 extraction, normalization, chunking, and Nomic embedding pipeline; and
publishes only after validation. The accepted inventory is 6 documents, 27
pages, 126 chunks, 126 citations, and 126 embeddings. Failure before
acceptance rolls back database objects created by the run.

Script `118` measures the frozen retrieval profile locally:

```bash
bash ./phase-28-apisachi-tokuli/scripts/118_measure_local_retrieval_ranking_baseline.sh --run
```

It uses the read-only retrieval role and forwarded Nomic to run the exact,
PostgreSQL lexical, and cosine-vector lanes for the fixed synthetic tuning
questions, applies the accepted reciprocal-rank fusion, and records MRR@20,
top-five coverage, and required-evidence recall. The retained artifact contains
only ranks, stable identities, synthetic display names, and citation pages; it
contains no credentials, query vectors, source text, or question text. Gemma,
Next.js, database writes, and package assembly remain outside this gate.

The accepted Script `118` run measured `MRR@20 = 0.690476`, responsive
top-five coverage `5/6`, and complete required-evidence recall `13/13`. The
measurement passed, but the frozen ranking gate did not. Its recorded next
gate is the bounded parameter search:

```bash
bash ./phase-28-apisachi-tokuli/scripts/119_search_local_retrieval_parameters.sh --run
```

Script `119` is entirely offline. It checksum-binds the Script `118` receipt
and ranking artifact, then replays the retained top-20 exact, lexical, and
vector lane ranks across 43,120 finite combinations of candidate depths,
primitive integer lane weights, and RRF constants. It retains qualifying
profiles and one recommendation selected by the documented KISS rule. It does
not contact PostgreSQL, Nomic, or Gemma; read a credential, question, vector,
or source text; change `method_profile.yaml`; run the application; or build a
package. The recommendation requires operator review and an explicit freeze
before any application configuration or code changes.

The operator froze the Script `119` recommendation as tuning decision `T09`.
Script `120` qualifies its exact implementation:

```bash
bash ./phase-28-apisachi-tokuli/scripts/120_qualify_frozen_t09_retrieval_profile.sh --run
```

It binds the accepted parameter-search receipt and artifact, the frozen T09
decision, the versioned profile and relationship configuration, the weighted
RRF runtime, its PostgreSQL adapter wiring, and the ranking evaluator. It
requires exact depth `1`; lexical, vector, and fused depths `20`; RRF constant
`60`; exact/lexical/vector weights `1/1/4`; no learned reranker; and retrieval-
profile identity
`ba4bac60b3f09f6be89db148d1df883748a2003f35a1cecfb6c74f53be74b865`.

The gate runs the evaluator self-test and all 371 native tests. It contacts no
database or model, reads no credential, changes no service, and builds no
package. Passing Script `120` proves source and regression coherence only.
The next gate remeasures all 13 cases using local read-only PostgreSQL and the
operator-forwarded Nomic endpoint; later gates separately prove nonresponsive
abstention and the complete Retrieval API with Gemma.

The accepted Script `120` run reproduced the frozen T09 profile identity and
passed all 371 native tests with zero failures or errors. Script `121` now
collects fresh live ranking evidence:

```bash
bash ./phase-28-apisachi-tokuli/scripts/121_remeasure_live_t09_retrieval_ranking.sh --run
```

It checks the accepted local six-document corpus receipt and Script `120`
receipt, verifies local PostgreSQL and forwarded Nomic, and then runs the
complete 13-case tuning set. Twelve cases receive singleton Nomic embeddings;
the broad-navigation case is routed deterministically to clarification. The
script requires the exact T09 profile identity and settings, uses a repeatable-
read read-only PostgreSQL transaction, and retains a checksum-bound artifact
without question text, query vectors, source text, or credentials. Gemma is
not used by this ranking gate. If the ranking thresholds pass, the next gate
qualifies all six nonresponsive abstentions and the complete Retrieval API.

The accepted Script `121` run passed live ranking at `MRR@20 = 0.916667`,
responsive top-five coverage `6/6`, and required-evidence recall `13/13`.
Script `122` qualifies the remaining complete API behavior:

```bash
bash ./phase-28-apisachi-tokuli/scripts/122_qualify_complete_local_retrieval_api.sh --run
```

It prompts once each for the Gemma key, Nomic key, and local `rag_retrieval`
PostgreSQL password. The script stages the bound v1.1 source in private
temporary storage, starts one loopback API on `127.0.0.1:1384`, and submits all
13 cases. It requires six answered responsive cases, six
`insufficient-evidence` abstentions, one clarification, all 13 expected
statuses, and no dependency failures. The temporary API is stopped and removed
afterward. The database remains read-only, no configuration or existing
service is changed, and no package is built. A private checksum-bound artifact
retains only synthetic questions and responses for review.

Two complete Script `122` runs with valid dependencies each produced one
different responsive `temporarily-unavailable` outcome. The first affected
`R-006`; the second affected `R-003`. T10 rejects rerunning until a favorable
stochastic sample appears and instead refreezes one bounded grounded-
generation retry. Script `123` qualifies that implementation locally:

```bash
bash ./phase-28-apisachi-tokuli/scripts/123_qualify_t10_grounded_generation_retry.sh --run
```

It checksum-binds both content-free failure receipts, frozen T10, the amended
orchestration, generation adapter, observability implementation, documentation,
and tests. It proves exactly one retry after a grounded Gemma transport or
validated-response failure, no retry for other dependency failures, fail-closed
behavior after the second attempt, and content-free retry evidence. It runs
all 376 native tests without contacting PostgreSQL, Gemma, Nomic, or any
external network endpoint. Ephemeral loopback and Unix sockets are exercised
only by native listener tests. A pass routes back to the complete Script `122`
API gate; package assembly remains blocked until that gate passes all 13 cases.

The accepted rerun of Script `122` passed all 13 cases with zero dependency
failures. Script `124` assembles the consolidated final-state v1.1 package:

```bash
bash ./phase-28-apisachi-tokuli/scripts/124_assemble_ishikawa_v1_1_deployment_package.sh --run
```

It preserves the immutable v1 fallback, binds the exact complete-API receipt,
runs all 376 native tests, builds the application and final version-4 database
schema twice, and requires byte-identical file inventories. It then checks the
Coding Standard, verifies the archive, and exercises a disposable fresh local
application installation. The package contains 48 Python modules and ten
operator/design documents, but no migrations, repair programs, source
documents, credentials, model output, operating-system packages, or container
images. It contacts no target, database, model endpoint, or credential.

Script `125` qualifies that exact consolidated archive on EmceeDanko:

```bash
bash ./phase-28-apisachi-tokuli/scripts/125_qualify_ishikawa_v1_1_deployment_package_on_emceedanko.sh --run
```

It revalidates the package locally, transfers only the accepted archive and a
neutral helper into a private temporary target directory, then requests
attended sudo. The helper installs and removes a disposable application,
creates and removes a disposable database, proves exact schema equivalence,
and confirms the populated accepted database is unchanged. It restores the
initial PostgreSQL cluster state, does not contact models or credentials, does
not alter the active application, and removes the target transfer directory.

The operator-executed Script `125` passed. It proved disposable fresh
application and database installation on EmceeDanko, exact version-4 schema
equivalence, and no change to the populated accepted corpus or active
application. Script `126` is the local-only release-acceptance gate:

```bash
bash ./phase-28-apisachi-tokuli/scripts/126_accept_ishikawa_v1_1_deployment_package.sh --run
```

It binds the exact Script `124` assembly and Script `125` host-qualification
evidence, reverifies the unchanged archive and current Coding Standard, and
retains one content-free Ishikawa v1.1 acceptance receipt. It does not rebuild
or duplicate the package, alter the immutable v1 fallback, or contact a target,
database, service, model endpoint, or credential.

The operator-executed Script `126` passed and accepted archive SHA-256
`e5e11c6054b1163868bc21d3b267d804894de0e936c1c1d28c6f506680746e25`
as Ishikawa v1.1. The deployment archive remains the single consolidated
Ishikawa payload; native operating-system prerequisites and the accepted Node
image remain separately managed deployment prerequisites.

The operator froze the extended evaluation as T11 with an automated MRR gate
and no manual answer review. Script `127` measures it locally:

```bash
bash ./phase-28-apisachi-tokuli/scripts/127_measure_extended_retrieval_mrr_gate.sh --run
```

It binds the accepted v1.1 release, accepted local six-document corpus, frozen
T09 profile, frozen 60-case relevance set, and evaluator. It requests 60
singleton Nomic embeddings and reads PostgreSQL in one repeatable-read,
read-only transaction. It does not call Gemma, generate answers, alter the
database or accepted package, or retain questions, source text, vectors, or
credentials. A valid measurement is retained whether the promotion threshold
passes or is not met.

Script `127` passed as a measurement at `MRR@20 = 0.852173`, with relevant
evidence in the top 20 for all 60 cases and in the top five for 56 cases. The
operator subsequently raised the promotion target to strict `MRR@20 > 0.91`.
The retained ranks therefore remain valid evidence, but promotion is not met.
Script `128` reclassifies and summarizes that exact observation locally without
calling Nomic again or changing the accepted profile or package.

```bash
bash ./phase-28-apisachi-tokuli/scripts/128_reclassify_extended_mrr_strict_target.sh --run
```

It checksum-binds the exact Script `127` report, observation, 60-case set,
amended T11 decision, and gate definition; recomputes MRR from the retained
first-relevant ranks using exact rational arithmetic; and records that the
strict target is not met. It contacts no database, model endpoint, target, or
credential and makes no retrieval or package change. A pass authorizes the
next evidence step: capture per-lane rankings and compare bounded retrieval
profile candidates against the same 60 relevance targets.

Script `128` passed and recorded that the strict production-promotion target
is not met. Script `129` captures reusable top-20 lane rankings:

```bash
bash ./phase-28-apisachi-tokuli/scripts/129_capture_extended_retrieval_lane_rankings.sh --run
```

It requests one singleton Nomic embedding for each of the same 60 synthetic
questions and reads the accepted local corpus through one repeatable-read,
read-only PostgreSQL transaction. It captures the exact, lexical, and vector
rankings to depth 20 and first proves that the released profile reproduces the
Script `127` ranks and `MRR@20 = 0.852173`. The retained artifact contains only
case and chunk identities, lane ranks, and relevance booleans. It excludes
questions, vectors, source text, credentials, and generated content. It does
not call Gemma or change the database, retrieval profile, accepted package, or
production candidate. A pass enables an offline bounded parameter search.

The corrected operator execution of Script `129` passed, reproduced
`MRR@20 = 0.852173`, and retained top-20 rankings for all three lanes. Script
`130` searches bounded fusion profiles against that immutable observation:

```bash
bash ./phase-28-apisachi-tokuli/scripts/130_search_extended_retrieval_profile_candidates.sh --run
```

It evaluates 43,120 combinations of exact, lexical, and vector depths, RRF
constants, and primitive lane weights. The strict production target remains
`MRR@20 > 0.91`, with top-five and top-twenty coverage recorded only as
diagnostics. The script reports both the smallest qualifying change and the
highest-MRR candidate, if any, but does not alter or freeze the method profile.
It runs locally from the content-free Script `129` artifact and contacts no
database, model, credential, service, or target. Runtime is expected to be a
few minutes, with periodic progress markers.

Script `130` passed, but none of its 43,120 bounded profile candidates met the
strict `MRR@20 > 0.91` target; the best candidate reached `0.853168`. Review of
the retained ranks isolated five explicit page questions for `99 TST 2005`.
The operator froze the narrow correction as T12. Script `131` qualifies it:

```bash
bash ./phase-28-apisachi-tokuli/scripts/131_qualify_t12_declared_identifier_page_routing.sh --run
```

It runs all 379 native tests, then uses the local `rag_retrieval` role in one
repeatable-read, read-only transaction. It proves that the existing
`Policy Number:` citation self-declaration resolves one active owner and routes
pages 2, 3, 5, 8, and 11 directly. It also proves that an unknown declaration
returns no page route, while native tests cover ordinary fallback and ambiguous
owner clarification.

The script recomputes the retained-rank counterfactual as exactly `6619/7200`,
displayed as `0.919306`. That is diagnostic evidence, not a promotion result;
the next gate must freshly rerun all 60 questions. Script `131` prompts only
for the local PostgreSQL retrieval password. It does not call Nomic or Gemma,
write PostgreSQL, change the T09 profile, build a package, modify a service, or
change operator forwarding.

The operator-executed Script `131` passed: all 379 native tests passed, all
five declared-identifier page routes resolved the unique active owner, and the
unknown-owner case preserved ordinary retrieval. Script `132` performs the
required fresh measurement:

```bash
bash ./phase-28-apisachi-tokuli/scripts/132_measure_t12_extended_retrieval_mrr_gate.sh --run
```

It requests 60 new singleton Nomic embeddings and reads the accepted local
corpus in one repeatable-read, read-only PostgreSQL transaction. The five T12
page cases must each place relevant evidence at rank one. The authoritative
gate is strict `MRR@20 > 0.91`; exactly `0.91` does not pass. The script does
not call Gemma, write PostgreSQL, alter the method profile, rebuild a package,
or retain questions, source text, vectors, or credentials. A passing ranking
gate proceeds to complete Retrieval API qualification before any package
refresh.

The operator-executed Script `132` passed at `MRR@20 = 0.919306`, with all 60
cases in the top 20, 59 in the top five, and each of the five T12 page cases at
rank one. T13 establishes the changed source as the Ishikawa v1.2 candidate;
the accepted v1.1 archive remains immutable. Script `133` runs the complete API
regression before v1.2 package assembly:

```bash
bash ./phase-28-apisachi-tokuli/scripts/133_qualify_ishikawa_v1_2_candidate_retrieval_api.sh --run
```

It privately stages the exact 67-file v1.2 candidate application surface,
starts a temporary loopback Retrieval API, and runs the accepted 13 cases:
six grounded-answer cases, six abstention cases, and one clarification case.
It prompts for the Gemma key, Nomic key, and local PostgreSQL retrieval
password. It retains only the synthetic response artifact and content-free
report, stops and removes the temporary service, writes no database data, and
does not change the accepted v1.1 package. A full pass authorizes consolidated
v1.2 final-state package assembly.

Script `133` completed, but its release gate was not met. Twelve cases matched;
`R-006` returned the valid fail-closed `temporarily-unavailable` response, so
the result was five of six responsive answers, six of six abstentions, one of
one clarification, and one dependency failure. The temporary service was
removed and no package was built. Script `134` isolates the reliability issue:

```bash
bash ./phase-28-apisachi-tokuli/scripts/134_diagnose_v1_2_r006_dependency_reliability.sh --run
```

It stages the same 67-file candidate, submits only `R-006` five times, and
classifies each content-free stage trace as first-attempt success, retry
recovery, failure after retry, or a different dependency boundary. It prompts
for the three runtime credentials and requires both forwarded model endpoints.
It retains no questions, answers, excerpts, prompts, vectors, model responses,
or credentials. The result must be reviewed before changing T10 or assembling
the v1.2 package.

The corrected operator-executed Script `134` passed its diagnostic contract,
but only two of five requests answered. Three requests exhausted T10's single
retry and failed closed after grounded generation; all earlier retrieval and
security stages passed. The trace cannot distinguish transport failure from a
strictly rejected model response. Script `135` captures that missing fact:

```bash
bash ./phase-28-apisachi-tokuli/scripts/135_classify_v1_2_generation_failures.sh --run
```

It runs five fresh Script `134` probes with a temporary observer attached only
to the staged Retrieval API. The observer records the generation attempt
number, failure family, and stable reason code. It never retains prompts,
responses, questions, excerpts, credentials, vectors, raw exceptions, or
source content. It changes no application source, policy, database state,
accepted release, or deployment package. The resulting evidence determines
whether the next correction belongs to transport handling, response
validation, or retry policy.

Script `135` classified all eight observed failed generation attempts as
strict response-validation failures rather than transport failures. The
operator froze T14: grounded generation now supplies vLLM with an exact JSON
Schema while Ishikawa's independent strict validator remains authoritative.
Script `136` qualifies that correction:

```bash
bash ./phase-28-apisachi-tokuli/scripts/136_qualify_t14_structured_grounded_generation.sh --run
```

It checksum-binds the Script `135` evidence, frozen T14 decision, and exact
67-file v1.2 candidate source. It first runs all 381 native tests, then starts
one temporary loopback Retrieval API and submits `R-006` five times. A pass
requires five answered responses, the required citation in every response,
zero generation retries, and zero dependency failures. It prompts for the
Gemma key, Nomic key, and local PostgreSQL retrieval password. It writes no
database data, changes no accepted release or package, and retains no raw
question, answer, prompt, excerpt, model response, vector, credential, or
exception text. A pass authorizes the complete 13-case v1.2 API gate.

The accepted Script `136` run passed all 381 native tests and all five live
`R-006` probes with the required citation, zero retries, and zero dependency
failures. Script `137` runs the complete T14-qualified API gate:

```bash
bash ./phase-28-apisachi-tokuli/scripts/137_qualify_t14_complete_v1_2_retrieval_api.sh --run
```

It binds the exact accepted Script `136` receipt, strict Script `132` MRR
receipt, frozen T10/T12/T13/T14 decisions, 13-case set, evaluator, and 67-file
source manifest. It starts a temporary loopback Retrieval API and exercises six
grounded answers, six abstentions, and one clarification before removing the
service. It prompts for the Gemma key, Nomic key, and local PostgreSQL
retrieval password. No database, installed service, accepted v1.1 release, or
package is changed. A full gate pass authorizes consolidated v1.2 package
assembly.

The accepted Script `137` run passed the complete gate: all six responsive
cases answered, all six nonresponsive cases abstained, the broad request
required clarification, all 13 response contracts and expected statuses
matched, and no dependency failed. Script `138` creates the consolidated v1.2
candidate:

```bash
bash ./phase-28-apisachi-tokuli/scripts/138_assemble_ishikawa_v1_2_deployment_package.sh --run
```

It binds the exact Script `137` evidence and accepted v1.1 predecessor, runs
all 381 native tests, assembles the application and final version-4 database
schema twice, and proves the two results are identical. It verifies internal
checksums, non-root readability, the repository Coding Standard, absence of
historical mutation files, development references, secrets, and source
documents, and performs a fresh temporary application install. It then retains
one checksum-bound v1.2 archive plus qualification and Coding Standard
receipts. The script is local-only: it contacts no target, database, model, or
credential and changes no running service or accepted predecessor.

The operator-executed Script `138` passed and retained the exact consolidated
v1.2 archive plus checksum-bound qualification and Coding Standard receipts.
Script `139` qualifies that unchanged archive on EmceeDanko:

```bash
bash ./phase-28-apisachi-tokuli/scripts/139_qualify_ishikawa_v1_2_deployment_package_on_emceedanko.sh --run
```

It opens one attended SSH control session, transfers only the checksum-bound
archive and repository-free qualification helper into a private temporary
directory, and requests attended `sudo` on the target. It verifies the package,
installs and removes one disposable application, installs and removes the final
schema in one disposable database, compares that catalog with the accepted
database, proves the accepted six-document corpus is unchanged, restores the
initial PostgreSQL cluster state, fetches content-free evidence, and removes
all transferred temporary files. It does not replace the active application,
write the accepted database, enable a service, contact a model, read a model
credential, copy source documents, or alter port forwarding.

The operator-executed Script `139` passed: the disposable application and
database installs succeeded on EmceeDanko, the installed catalog matched the
accepted database, the six-document corpus remained unchanged, the initial
PostgreSQL state was restored, and all transferred temporary files were
removed. Script `140` accepts the exact qualified v1.2 archive:

```bash
bash ./phase-28-apisachi-tokuli/scripts/140_accept_ishikawa_v1_2_deployment_package.sh --run
```

It re-verifies every retained checksum, the v1.2 package verifier, and current
Coding Standard compliance, then records one checksum-bound release receipt.
It does not rebuild or duplicate the archive, contact EmceeDanko, access a
database or model, read credentials, or change any service. The accepted v1.1
archive remains the unchanged predecessor.

Script `141` binds that accepted v1.2 release to the existing neutral Ubuntu
26 native-prerequisite inventory kit:

```bash
bash ./phase-28-apisachi-tokuli/scripts/141_bind_v1_2_native_prerequisite_inventory.sh --run
```

It re-verifies the exact release and kit evidence, extracts and verifies both
the v1 and v1.2 packages, and requires their ingestion and runtime dependency
contracts to remain byte-identical. It also rechecks the three-file inventory
kit for internal checksums, symlinks, credentials, and transfer-side repository
jargon. A pass reuses the existing kit unchanged and records that the Ubuntu
`26.04` AMD64 target inventory is still pending. It does not rebuild or copy a
package, contact a target or network, download or install a native package,
read a credential, or change a service. The next gate is the operator-run
neutral inventory on the org-lab application host.

Script `142` prepares the hand-carried execution bundle for that inventory:

```bash
bash ./phase-28-apisachi-tokuli/scripts/142_prepare_v1_2_native_inventory_handoff.sh --run
```

It binds the accepted Script `141` receipt and unchanged three-file inventory
kit, then adds one repository-free target runner and neutral README. It builds
the five-file handoff twice, requires identical inventories, verifies the
outer and inner checksum manifests, and runs the target runner's no-contact
validation mode from the extracted archive. The bundle contacts no target or
network and downloads, installs, or changes nothing. On the Ubuntu `26.04`
AMD64 host, its neutral runner performs the read-only inventory and leaves one
result archive plus checksum under `/tmp` for hand return and later cleanup.

Org-lab inventory is intentionally deferred while the accepted v1.2 release is
tested on EmceeDanko. Script `143` performs the separate supported-host upgrade:

```bash
bash ./phase-28-apisachi-tokuli/scripts/143_upgrade_ishikawa_v1_2_on_emceedanko.sh --run
```

Run the installed `ishikawa-stack stop` command first. Script `143` binds the
exact Script `140` acceptance receipt, archive, and zero-finding Coding Standard
receipt; transfers only that archive and a product-named helper; and requires
PostgreSQL, the Retrieval API, the retention timer, and the managed stack state
to be stopped. It installs v1.2 into a sibling directory, preserves the current
product/deployment/class/catalog configuration, ingestion records, corpus, and
state, then promotes the candidate and installs the exact boot-disabled user
units. The complete prior tree remains at
`~/Documents/Ishikawa-before-v1.2` for rollback. The database schema and rows,
model forwarding, credentials, and service state are unchanged; v1.2 remains
stopped until the operator starts it with the installed stack command.

The first upgraded v1.2 start exposed only the coarse
`retrieval_readiness_failed` marker. The operator froze T15 so future startup
failures identify the blocked readiness component without exposing private
details or changing the public `/ready` response. Script `144` qualifies that
local correction:

```bash
bash ./phase-28-apisachi-tokuli/scripts/144_qualify_t15_startup_readiness_diagnostics.sh --run
```

It binds the exact T15 decision and changed source, runs all 385 native tests,
and revalidates the portable operator documentation. The corrected stack runs
a content-free preflight before the Retrieval API starts and reports `pass` or
`blocked` independently for configuration, storage, PostgreSQL, Gemma health,
and Nomic health. It repeats the same diagnostic if runtime readiness later
fails. The public health response remains only `ready` or `not-ready`. This
local-only gate contacts no target, database, or model; reads no credential;
and changes no service, package, database, accepted v1.2 release, or running
EmceeDanko installation.

Post-v1.2 retrieval and workspace corrections are isolated as the local v1.3
candidate. Script `145` qualifies that source before any local live launch:

```bash
bash ./phase-28-apisachi-tokuli/scripts/145_qualify_local_v1_3_workspace_source.sh --run
```

It preserves the accepted v1.2 release, runs all 388 native tests, then uses
the already-present architecture-matched Node 24 / Next.js image to run 12
JavaScript contract and presentation tests plus one production build. It never
pulls or changes the image. The v1.3 candidate adds stable document identifiers,
expanded inspection citations, explicit complete-section reconstruction,
chat-level source-label continuity, session chats, context-budget and dependency
status surfaces, and an Anderson-aligned light/dark three-region presentation.
It contacts no database, model, remote target, or running service and creates
no deployment package. A pass authorizes the separate local live-launch gate.

Script `146` is that local live-launch gate:

```bash
bash ./phase-28-apisachi-tokuli/scripts/146_launch_local_v1_3_preview.sh --run
```

It binds the exact accepted Script `145` source receipt and accepted local
six-document corpus receipt. On DankoSurface it requires the operator-managed
Gemma and Nomic forwards already listening on ports `8000` and `8001`, reuses
the existing ARM64 Node 24 / Next.js image without pulling or changing it,
starts native PostgreSQL only if it is stopped, stages the Retrieval API in a
private `/tmp` directory, and runs the working UI source through read-only bind
mounts. The `public` mount is explicit so the qualified theme bootstrap asset
is part of the live preview. The terminal remains the preview supervisor while
Next.js provides UI hot reload. Pressing Ctrl+C stops both preview processes,
stops PostgreSQL only when Script `146` started it, removes temporary runtime
files, clears shell credential variables, and retains one content-free local
report. It does not install or package v1.3, create model forwards, write the
database, contact a remote host, or change the accepted v1.2 release.

The first DankoSurface Script `146` runs stopped before startup because the
local corpus bootstrap had left PostgreSQL `16/main` at the Ubuntu default
`start.conf=auto` posture. That contradicts the already-frozen on-demand
service posture; it is an implementation gap, not a new design decision.
Script `147` applies the bounded correction:

```bash
bash ./phase-28-apisachi-tokuli/scripts/147_correct_local_postgresql_on_demand_posture.sh --run
```

It binds the exact clean Script `146` block and accepted local-corpus receipt,
requires the cluster to be stopped and port `5432` free, then uses one
checksum-bound neutral helper with attended sudo. The helper changes only the
known PostgreSQL startup policy from `auto` to `manual`, disables generic and
cluster boot links, reloads systemd, and proves the database never started. It
preserves a rollback copy until every final check passes. It never connects to
or changes the database, accesses a credential, installs a package, starts a
container, calls a model, creates forwarding, or contacts a remote host. A
pass routes back to the unchanged Script `146` live-preview gate.

The second operator-executed Script `147` run proved that the local PostgreSQL
cluster was still running, and browser inspection showed the earlier Danko
Next.js POC still owned port `3000`. Script `148` stops only those verified
local runtime prerequisites:

```bash
bash ./phase-28-apisachi-tokuli/scripts/148_stop_local_poc_and_postgresql.sh --run
```

It binds the exact second Script `147` block, requires port `1384` to be free,
and identifies the POC using its loopback page, the exact existing ARM64 Node
image, and a sole matching running container. Before stopping PostgreSQL it
requires zero other PostgreSQL client sessions. It then stops the POC container
and PostgreSQL `16/main`, proves ports `3000`, `1384`, and `5432` are free, and
retains only a content-free local receipt. It explicitly removes no container
or image, although Docker may apply the POC container's existing automatic-
removal policy when it stops. It changes no database content or boot policy,
reads no application credential, and contacts no model or remote host. A pass
returns to Script `147`, which can then safely change PostgreSQL to the frozen
on-demand startup posture.

After Scripts `147` and `148` established that clean on-demand posture, three
Script `146` attempts reached PostgreSQL but stopped at the same coarse
`local_corpus_inventory_failed` marker. The corrected Script `146` keeps the
application and retrieval design unchanged while closing the surrounding
launcher gaps together. It now binds all 83 staged application, UI, public,
configuration, and entrypoint files; proves the retrieval role, login, schema
usage, active-view grants, and accepted `6/27/126/126/126` corpus counts with a
read-only administrator preflight; validates the operator-entered PostgreSQL
credential before requesting either model credential; and records content-free
failure families for database, Retrieval API, and Next.js startup failures.
Readiness component status is also retained in the report. The next action is
to rerun the same Script `146` command; Script `147` and Script `148` are not
repeated.

The first live v1.3 question exposed a citation-integrity defect in display
expansion: selected table-context or page-status generation evidence could be
omitted from the expanded display set, causing the Retrieval API to fail
closed before grounded generation. The same review also removed the duplicate
aggregate dependency status from the header, the left-rail Session overview,
and the visible `CONTENT-FREE` label above Model connections. Script `149`
qualifies the bounded correction before another live preview:

```bash
bash ./phase-28-apisachi-tokuli/scripts/149_qualify_v1_3_citation_and_ui_correction.sh --run
```

It proves display expansion is additive and every accepted generation
citation remains displayable, including table-context and page-status
evidence. It runs all 389 native tests, 12 JavaScript contract/presentation
tests, and one network-disabled production Next.js build with the existing
architecture-matched local image. It binds all 83 runtime candidate files and
the updated frozen v1.3 decision wording. It contacts no database, model,
remote host, or running service; reads no credential; pulls no image; and
changes no accepted release or package. A pass authorizes a separately bound
corrected local v1.3 live-launch gate.

Script `150` is the corrected local v1.3 live-launch gate:

```bash
bash ./phase-28-apisachi-tokuli/scripts/150_launch_corrected_local_v1_3_preview.sh --run
```

It binds the exact passing Script `149` report, the current 83-file candidate
identity, and the accepted local six-document corpus receipt. It retains the
full prerequisite, database-role, corpus-inventory, configuration, readiness,
port, model-forward, container, and cleanup checks from the previously proven
preview launcher. It prompts privately for the PostgreSQL retrieval password
and the Gemma and Nomic API keys, stages only the native Retrieval API under a
private temporary directory, and host-mounts the qualified web source into the
unchanged local Node image. The terminal remains attached while the preview is
available on `127.0.0.1:3000`; Ctrl+C stops the preview, removes temporary
runtime state, clears credential variables, and stops PostgreSQL only when the
script started it. It creates no forwarding, pulls no image, writes no corpus
data, contacts no remote host directly, and creates no deployment package.

The operator froze v1.3 decisions `V13-12` through `V13-18` after the first
interactive citation review. Script `151` qualifies their implementation:

```bash
bash ./phase-28-apisachi-tokuli/scripts/151_qualify_v1_3_structured_citations_and_document_view.sh --run
```

It proves unique explicit title/key/identifier routing while ordinary
situational questions remain corpus-wide; replaces the competing answer/claim
shape with one ordered sequence of citation-bearing segments; limits initial
citation display to complete cited structural roots; renders continuous
selectable source text without visible chunk boundaries; scopes the citation
rail to the selected turn; and qualifies progressive read-only reconstruction
of the exact active document version. Reconstructed bodies remain outside both
Gemma context and browser `sessionStorage`, and original PDFs remain disabled.
It also qualifies preview cleanup by verified final container, process, port,
credential-variable, PostgreSQL, and private-storage state rather than child
exit codes. The script runs all 396 native tests, 14 JavaScript tests, and a
network-disabled production Next.js build against the existing local image.
It contacts no database, model, remote host, or running service; reads no
credential; pulls no image; and changes no accepted release or deployment
package. If the one known retained preview directory exists, it is removed
only after the script proves no associated runtime remains.

Script `152` launches that qualified candidate locally for interactive review:

```bash
bash ./phase-28-apisachi-tokuli/scripts/152_launch_qualified_local_v1_3_preview.sh --run
```

Its first explicit-title request exposed an invalid PostgreSQL combination of
`SELECT DISTINCT` and an unselected length-based ordering expression. Script
`153` qualifies the narrow query correction while retaining longest-title-first
routing, all frozen v1.3 behavior, 396 native tests, 14 JavaScript tests, and a
network-disabled production build:

```bash
bash ./phase-28-apisachi-tokuli/scripts/153_qualify_v1_3_title_routing_sql_correction.sh --run
```

Script `154` launches the exact Script `153` candidate using the same private,
operator-attended local preview boundary:

```bash
bash ./phase-28-apisachi-tokuli/scripts/154_launch_sql_corrected_local_v1_3_preview.sh --run
```

That preview exposed two presentation defects and one proxy defect: citation
cards used retrieval-enriched text rather than source excerpts, the full-
document action sat below overflowing citation text, and the web proxy aborted
healthy Retrieval API work at exactly 30 seconds while reporting the service
as unavailable. Script `155` qualifies the combined implementation correction:

```bash
bash ./phase-28-apisachi-tokuli/scripts/155_qualify_v1_3_citation_rail_and_proxy_corrections.sh --run
```

It proves source-excerpt structural display without changing Gemma evidence,
places the document-view action before cited text, removes the Current Chat
Request context card and Selected turn label, updates the requested operator
copy, and distinguishes an outer request timeout from an unavailable API. It
runs all 396 native tests, 15 JavaScript tests, and a network-disabled
production build. It contacts no database, model, service, or remote host;
reads no credential; pulls no image; and changes no accepted release or
deployment package.

Script `156` launches that exact corrected candidate for interactive local
review:

```bash
bash ./phase-28-apisachi-tokuli/scripts/156_launch_corrected_local_v1_3_preview.sh --run
```

It retains the private, attended, host-local preview boundary used by the
earlier launchers. It requires the existing Gemma and Nomic forwards, starts
native PostgreSQL only when needed, stages the Retrieval API under `/tmp`, and
uses the already-present architecture-matched Node image. Ctrl+C stops and
verifies every component before temporary state and credential variables are
cleared. It does not install, package, ingest, or change the accepted release.

After the operator accepted additional presentation and diagnostic decisions,
Script `157` qualifies the resulting v1.3 source:

```bash
bash ./phase-28-apisachi-tokuli/scripts/157_qualify_v1_3_product_presentation_and_diagnostics.sh --run
```

It validates configurable product presentation, restricted formatted empty-chat
content, citation page metadata, operator wording, and turn-scoped developer
diagnostics. The header-aware candidate extends that suite to 407 native tests;
the script still runs 17 JavaScript tests and one
network-disabled production Next.js build. It contacts no model, database,
service, or remote target and changes no package or accepted release.

Script `158` launches the exact Script `157` candidate for the current local
interactive test cycle:

```bash
bash ./phase-28-apisachi-tokuli/scripts/158_launch_product_configured_local_v1_3_preview.sh --run
```

It keeps the terminal attached as supervisor, requires the accepted local
six-document corpus and operator-managed model forwards, and prompts privately
for the three runtime credentials. Candidate runtime state exists only in a
private `/tmp` directory. Ctrl+C stops the preview, verifies ports and child
state, clears credential variables, and removes that directory.

After Script `207` qualifies V13-54 and all sixty corpus-v3 frontier cases,
Script `208` launches that exact source and the thirty-document corpus v3 in a
private attended preview:

```bash
bash ./phase-28-apisachi-tokuli/scripts/208_launch_v13_54_corpus_v3_local_preview.sh --run
```

It verifies the retained Script `207` report and frontier artifact, rebuilds
the exact corpus-v3 ingestion bundle, ingests it into disposable PostgreSQL on
port `65438`, and starts the Retrieval API and host-mounted UI on loopback ports
`1384` and `3000`. It never contacts the accepted local database, installs no
service, changes no autostart setting, and removes the database and preview
runtime after Ctrl+C. Gemma and Nomic must already be forwarded on ports
`18000` and `18001`.

The observed controlled-materials incident question returned insufficient
evidence even though retrieval telemetry reported twenty fused candidates and
fifteen reconstructed units. Script `159` diagnoses that exact boundary before
any retrieval, sufficiency, or corpus design is changed:

```bash
bash ./phase-28-apisachi-tokuli/scripts/159_trace_v1_3_incident_retrieval_quality.sh --run
```

Run it in a second terminal while Script `158`, PostgreSQL, and the existing
Gemma/Nomic forwards remain available. It replays the synthetic first-turn
question through the unchanged retrieval adapter; records exact, lexical,
vector, fused, and relationship results; measures the frozen top-three lexeme
inventory; identifies the first ranks of the controlled-materials policy and
incident procedure; and retains the exact deterministic sufficiency reason.
It calls Nomic once and uses only Gemma's tokenizer—never Gemma scope, query
resolution, or answer generation. Its database transaction is repeatable-read
and read-only. The private-lane JSON artifact retains no credentials, embedding
vectors, source text, or model response bodies, and the companion report is
content-free. The result is evidence for a later answer-quality decision; the
script itself changes no gate, corpus, source, service, or package.

Script `159` proved that the controlled-materials policy ranked first and the
incident procedure ranked fourth; the frozen top-three relevance check, not a
failure to retrieve either document, stopped the request. Before changing that
gate, decisions `V13-22` through `V13-24` freeze a separately testable metadata
path. Script `160` qualifies it and builds synthetic corpus v2:

```bash
bash ./phase-28-apisachi-tokuli/scripts/160_qualify_header_aware_synthetic_corpus_v2.sh --run
```

It recognizes the first-page masthead as a non-text logo, organization name,
document context/title, and the complete Effective Date, Policy Number,
Applicability/Class, Department, Date of Review, and Approval control table.
The table is identified from labels and geometry rather than requiring intact
borders, so sanitized cell edges do not prevent recognition. It
normalizes `Department`, `Dept`, and `Dept.` labels; fails closed on conflicting
repeated headers; excludes header rows from semantic body chunks; and carries
the bounded canonical fields into retrieval context and structured filters.
An exact corpus-known department reply to an immediately preceding department
clarification is merged with the prior question and constrains retrieval to
all matching authorized active documents. This routing is not an authorization
decision, and unknown replies preserve the existing model-resolution path.

The script leaves synthetic corpus v1 byte-for-byte untouched. It generates
corpus v2 twice, proves identical file inventories and bytes, runs repeatable
Poppler extraction across all six documents and 27 pages, qualifies normalized
first-page mastheads and 134 structural candidates, and reruns all 407 native
tests. It also
reruns the 43 normalization, chunking, embedding-qualification, and artifact-
adapter pipeline regression checks. One
checksum-bound synthetic-only v2 candidate is retained locally for the next
embedding and retrieval-measurement gate. It does not ingest the candidate,
contact PostgreSQL or either model, start or stop a service, read a credential,
change a deployment package, or modify an accepted release.

After Script `160` passes, Script `161` embeds and measures that exact retained
corpus-v2 candidate without ingesting or publishing it:

```bash
bash ./phase-28-apisachi-tokuli/scripts/161_embed_and_measure_synthetic_corpus_v2_without_ingestion.sh --run
```

It uses the existing operator-managed Nomic forward for 134 document-candidate
embeddings and 68 query embeddings. PostgreSQL English lexical ranking runs in
a private temporary PostgreSQL 16 cluster under `/tmp`, with no TCP listener
and no corpus tables. Exact, lexical, and vector results are fused with the
frozen T09 profile and measured over the established 60-question MRR set plus
eight header and department cases. The temporary cluster is stopped and removed
on exit. The accepted v1 database is never contacted, corpus v2 remains
unpublished, and no question text, query vector, source text, credential, or
Gemma response is retained. A clean script execution records either a passing
pre-ingestion quality gate or a bounded rank-review gate; neither result
authorizes ingestion by itself.

Script `161` measured the first candidate but did not qualify it: body MRR@20
was `0.807798`, header MRR@20 was `0.546131`, and required header evidence was
only `8/11`. The measurement also exposed two representation defects. The
complete document-control header was repeated in every body candidate's
lexical and embedding text, allowing one document's chunks to crowd out other
documents, and the inherited blank first page of `99 TST 2002` displaced its
first semantic content to page 2. Decisions `V13-25` through `V13-27` freeze
the correction. Script `162` rebuilds and qualifies it without ingestion:

```bash
bash ./phase-28-apisachi-tokuli/scripts/162_rebuild_corrected_synthetic_corpus_v2.sh --run
```

The corrected representation retains document-control values as structured
filters and provenance on every body candidate but removes repeated header
boilerplate from body retrieval text. It emits exactly one searchable,
page-one `document_control_metadata` representative for each document. The
v2-only layout removes the single inherited leading blank page before adding
the masthead, so every document's first semantic content begins below its
masthead on physical page 1. Corpus v1 remains immutable.

Script `162` binds the intact Script `161` observation, reruns all 407 native
tests and 43 pipeline tests, generates the corrected corpus twice, verifies
byte repeatability, performs repeatable extraction across six documents and
26 nonblank pages, and normalizes/chunks the result twice. Its retained
candidate contains 139 candidates: six metadata representatives plus 133
body or structured candidates. It proves that every candidate retains the
structured control filter, only the six representatives contain the bounded
searchable header block, and each document has semantic evidence on page 1.
It contacts no database or model, reads no credential, changes no service or
package, and does not authorize corpus-v2 ingestion. The next gate is a fresh
Nomic embedding and retrieval measurement of this corrected candidate.

After Script `162` passes, Script `163` performs that isolated measurement:

```bash
bash ./phase-28-apisachi-tokuli/scripts/163_embed_and_remeasure_corrected_synthetic_corpus_v2.sh --run
```

It checksum-binds the exact 139-candidate output, calls only the existing
loopback Nomic service, and evaluates the same 60 body plus eight header and
department cases. PostgreSQL lexical ranking runs in a private temporary
cluster with no TCP listener, corpus tables, or accepted-database contact.
The temporary cluster is removed after the result is retained. The script
reports the body and header metrics and either a passing or not-met
pre-ingestion gate; it never ingests or publishes corpus v2 and does not call
Gemma.

Script `163` executed safely but did not meet the promotion gate. Header MRR
reached `1.000000`, with all eight header cases in the top five and all eleven
required header evidence pairs in the top twenty. Reported body MRR was
`0.811825`. Three body misses were stale evaluator expectations: corpus v2 had
deliberately removed the leading blank page from `99 TST 2002`, moving its
matrix from physical page 2 to physical page 1. The measurement also exposed
ordinary body queries competing with document-control metadata candidates and
multi-item sections being ranked only as isolated atoms.

Decisions `V13-28` and `V13-29` define the isolated correction and experiment.
The v2 body truth file is only a scorer answer key. It differs from the v1
60-case fixture in exactly E-010, E-011, and E-012, where page 2 becomes page
1. It is never ingested, sent to Gemma, used as a retrieval hint, or applied to
the black corpus. The v2 generator also updates the two synthetic cross-
references and the displaced matrix footer so the documents and answer key do
not contradict each other. Corpus v1 remains byte-for-byte unchanged.

Script `164` builds and measures the candidate:

```bash
bash ./phase-28-apisachi-tokuli/scripts/164_measure_v2_metadata_routing_and_sibling_assembly.sh --run
```

It deterministically regenerates and extracts corpus v2 twice, proves that no
stale page-2 matrix reference remains, normalizes and creates the 139 atomic
candidates twice, and adds 24 non-destructive compatible-sibling assemblies.
An assembly contains at most eight adjacent paragraph, definition, or list
items from one parent section and one physical page. Atomic candidates and
source-unit identities remain available for citation reconstruction. Exact
Nomic tokenization must keep every candidate within the embedding ceiling.

During this experiment, the six `document_control_metadata` candidates remain
available to exact routing and explicit header or department questions but are
excluded from ordinary body lexical and vector lanes. The frozen T09 depths,
weights, RRF constant, and no-reranker posture remain unchanged. Script `164`
uses only the existing loopback Nomic endpoint and a private temporary
PostgreSQL cluster, then reports the strict body MRR and header gates. It does
not ingest corpus v2, contact Gemma or the accepted database, access the black
corpus, or change the production retrieval profile. Even a passing result
requires a separate review before retrieval-profile promotion. Corpus-v2
promotion remains independently qualified and is not gated by this result.

Script `164` executed safely and retained a valid candidate, but the strict
retrieval-profile measurement was not met. Body MRR@20 improved from `0.811825` to
`0.870992`; 58 of 60 body questions placed relevant evidence in the top five,
all 60 placed it in the top twenty, and header MRR remained `1.000000`. Corpus
v2 remains un-ingested for its independent promotion workflow, and the
production retrieval profile remains unchanged.

Script `165` is the next local-only review gate:

```bash
bash ./phase-28-apisachi-tokuli/scripts/165_review_v2_candidate_rank_failures.sh --run
```

It checksum-binds Script `164`'s report, candidate, and observation, compares
the ranks with Script `163`, and retains a synthetic-only review of all body
cases below rank one. The review distinguishes assembly/atomic self-competition
from a page-scoring anomaly in E-032, where the exact expected sentence occurs
on multiple physical pages. It also measures page-only diversification as a
counterfactual without changing the scorer or retrieval method. It contacts no
database or model, reads no credential, accesses no black corpus, and changes
no truth file, corpus, service, package, or production profile.

Beginning with Script `165`, terminal script results are visually separated at
the end of the output and printed alone:

```text
SCRIPT RESULT
script_165_v2_rank_failure_review=pass
```

Script `165` passed. Optimization measurement now continues as a parallel,
observational track while corpus-v2 promotion remains the primary independent
track. Script `166` performs the first bounded offline search:

```bash
bash ./phase-28-apisachi-tokuli/scripts/166_search_v2_retrieval_optimizations.sh --run
```

It evaluates 10,584 combinations of captured-depth RRF constants, lexical and
vector weights, lexical and vector depths, and explicit post-fusion
diversification modes. Selection uses the unchanged strict document/page
truth. The E-032 identical-evidence interpretation is reported only as a
diagnostic and cannot make a candidate pass. The current Script `164` profile
must replay at MRR `0.870992`, so the search cannot silently change its
baseline.

This stage uses cached synthetic lane ranks and makes no database or model
call. It retains up to 25 finalists with per-case improvement and regression
lists. No offline result changes retrieval or authorizes retrieval-profile
promotion. Its result cannot block or redirect corpus-v2 promotion. Reviewed
retrieval finalists would require fresh Nomic/PostgreSQL measurement plus
repeated warm latency measurement before any retrieval-profile freeze. The
complete test policy, track separation, and matrix are recorded in
`docs/ISHIKAWA_V1_3_RETRIEVAL_OPTIMIZATION_PLAN.md`.

Script `166` passed its bounded search. No strict retrieval-profile candidate
met the optimization threshold, no profile changed, and the result explicitly
left corpus-v2 promotion unblocked. Script `167` returns to the primary corpus
track and qualifies the corrected atomic candidate for isolated ingestion:

```bash
bash ./phase-28-apisachi-tokuli/scripts/167_qualify_synthetic_corpus_v2_promotion.sh --run
```

It binds the byte-repeatable Script `162` candidate and independently verifies
its six synthetic documents, 26 pages, six normalized control headers, four
departments, 139 atomic candidates, first-page semantic content, structured
metadata propagation, and exclusion of header boilerplate from ordinary body
retrieval text. It retains an immutable promotion bundle containing the source
PDFs, operator catalog and ingestion manifest, and qualification evidence.
Evaluation truth is isolated under an evidence-only path.

The bundle deliberately excludes Script `164`'s compatible-sibling assemblies
and every Script `166` optimization finalist. It does not contact PostgreSQL,
Nomic, or Gemma; ingest a document; mutate corpus v1; change a retrieval
profile; or modify an accepted package or release. A clean result qualifies
the exact bundle for the next independent gate: publication into a separately
named synthetic-corpus-v2 database.

Script `167` passed and retained the qualified bundle. Script `168` publishes
that exact bundle without modifying the accepted corpus-v1 database:

```bash
bash ./phase-28-apisachi-tokuli/scripts/168_publish_synthetic_corpus_v2_isolated.sh --run
```

The accepted application contract deliberately fixes the database name as
`rag_catalog`. To preserve that contract while providing physical isolation,
Script `168` creates a separate PostgreSQL 16 cluster named `ishikawa-v2` on
loopback port `5433`. The cluster uses manual start policy, owns its own
`rag_owner`, `rag_ingest`, and `rag_retrieval` roles, and contains its own
`rag_catalog` database. Cluster `16/main` on port `5432` remains corpus v1.

The script checksum-binds the 51-file application source tree, runs all 408
native tests, snapshots corpus v1, installs the canonical final schema in the
isolated cluster, and runs the real source ingestion pipeline against the six
qualified v2 PDFs. It verifies six documents, 26 pages, 139 chunks, 139
citations, 139 embeddings, six document-control metadata candidates, and four
departments. The corpus-v1 comparison covers the active document, chunk,
citation, embedding, and relationship identities rather than only document
counts.

Before acceptance it also proves the exact schema migration, publication
batch, method profile, embedding space, one-to-one chunk/citation/embedding
coverage, citation page bounds, absence of unresolved quarantine records,
loopback-only listener, manual-start policy, and retrieval-role read-only
posture. The three derived artifacts are semantically checked, retained by
their content identities, copied through a destination-filesystem staging
directory, and verified with a non-self-referential checksum manifest before
the publication receipt is accepted. The forwarded Nomic endpoint is used for
tokenization and embeddings; Gemma is not called.

Script `168` does not use or promote Script `164` sibling assemblies or Script
`166` optimization results. It does not change the retrieval profile,
application package, accepted release, black corpus, or service-autostart
posture. If a new isolated cluster fails before acceptance, only that cluster
is removed. An unexpected pre-existing `16/ishikawa-v2` cluster blocks for
review instead of being overwritten or deleted. A clean result is printed as:

```text
SCRIPT RESULT
script_168_isolated_synthetic_corpus_v2_publication=pass
```

After Script `168` passes, Script `169` qualifies the published corpus through
the live, read-only PostgreSQL retrieval lanes:

```bash
bash ./phase-28-apisachi-tokuli/scripts/169_qualify_isolated_synthetic_corpus_v2_retrieval.sh --run
```

It checksum-binds the accepted Script `168` publication, verifies the retained
derived artifacts, confirms that cluster `16/ishikawa-v2` remains online on
port `5433` with manual start policy, and reads it only as `rag_retrieval` in a
repeatable-read, read-only transaction. It runs all 60 corpus-v2 body cases and
eight header/department cases through fresh Nomic query embeddings and the
frozen exact, PostgreSQL lexical, pgvector cosine, and weighted-RRF lanes.

The gate proves that the 139 database chunk projections match the exact
checksum-retained chunk artifact produced by Script `168`. Producer chunk IDs
are joined through the publication adapter's retained
`client_metadata.producer_chunk_id`; the gate independently verifies each
database chunk ID derived from its published artifact-set ID, ordinal, and
retrieval-text digest. Live ranking is then measured with those database chunk
IDs. It records the live body MRR and compares it with the pre-ingestion atomic baseline of MRR@20
`0.811825`, `54/60` cases in the top five, and `57/60` in the top twenty. That
comparison is observational and cannot block corpus promotion. The strict
header gate remains MRR@20 `1.000000`, all eight cases in the top five, and all
`11/11` required evidence pairs in the top twenty.

The script does not write either database, contact corpus v1 or Gemma, access
the black corpus, or promote a retrieval profile. If the manual-start v2
cluster is initially down, the script starts it with attended authorization
and restores it to down on exit; an initially online cluster remains online. A
clean pass returns the workflow to bounded retrieval optimization review.

The accepted Script `169` run measured the published atomic projection at body
MRR@20 `0.873056`, with `58/60` body cases in the top five and all `60/60` in
the top twenty. The strict header gate remained MRR@20 `1.000000`, `8/8` in the
top five, and `11/11` required evidence pairs in the top twenty.

Script `170` returns to the separate observational optimization track using
those accepted live lane ranks:

```bash
bash ./phase-28-apisachi-tokuli/scripts/170_search_published_v2_live_lane_optimizations.sh --run
```

It reconstructs and verifies the 139 producer-to-publication chunk identities,
replays the bounded 10,584-profile matrix locally, and retains 25 finalists.
It does not start PostgreSQL, call Nomic or Gemma, read credentials, change the
published corpus, or promote a retrieval profile. The prior 163-candidate
sibling-assembly experiment is not treated as the published corpus. If no
profile reaches the strict body MRR target above `0.91`, the next gate is a
rank-failure and candidate-representation review rather than live promotion.

The accepted Script `170` run evaluated all 10,584 bounded profiles. None met
the strict gate. The best observation reached body MRR@20 `0.882103`, improved
three body cases, regressed two, preserved perfect header metrics, and did not
authorize profile promotion. Script `171` performs the required content-free
rank-failure review:

```bash
bash ./phase-28-apisachi-tokuli/scripts/171_review_published_v2_atomic_rank_failures.sh --run
```

It binds the accepted Script `169` lane capture and Script `170` optimization
artifact, verifies that the current replay ranks are identical, and reviews
every body case below rank one. It records lane-first-relevant positions,
single-document versus corpus-wide scope, same-document/wrong-page pressure,
cross-document pressure, and whether the best bounded profile improved,
regressed, or left each case unchanged. It retains case identities and
document/page targets but no question text, source text, vectors, prompts, or
model responses.

The review contacts no database or model, reads no credential, accesses no
black corpus, and changes no corpus, truth, service, package, or production
profile. It cannot authorize a new candidate. A clean result narrows the next
design gate to a bounded section/page-aware candidate experiment while the
published corpus and frozen profile remain unchanged.

Script `171` passed and found 12 body cases below rank one. Nine exhibit
same-document/wrong-page pressure, seven exhibit cross-document pressure, and
the lexical and vector lanes lead different cases. Script `172` freezes the
bounded experiment before another model or database call:

```bash
bash ./phase-28-apisachi-tokuli/scripts/172_design_bounded_section_page_candidate_experiment.sh --run
```

It verifies the accepted rank review, 139-candidate published source
projection, and unchanged 60 body plus eight header truth cases. It defines
exactly four variants: the atomic baseline, document-local duplicate
canonicalization, section/page representatives, and their combination. The
candidate has 29 eligible section/page groups and three duplicate-evidence
groups containing 24 occurrences, of which 21 are repetitions beyond the
canonical occurrence. Every stored atom and citation remains authoritative;
the experiment can add at most 29 retrieval-only representatives and cannot
exceed 168 pre-collapse candidates.

The frozen T09 depths, weights, RRF constant, and no-reranker posture remain
unchanged. The design requires exact Nomic token qualification, fresh private
PostgreSQL lexical measurement, deterministic collapse and expansion, all
existing body/header gates, and warm latency diagnostics. Script `172`
contacts no service and changes no corpus, truth, package, or profile. Its
manifest only authorizes the separate bounded measurement gate described in
`docs/ISHIKAWA_V1_3_SECTION_PAGE_EXPERIMENT.md`.

After Script `172` passes, Script `173` executes that bounded measurement:

```bash
bash ./phase-28-apisachi-tokuli/scripts/173_measure_bounded_section_page_candidate_experiment.sh --run
```

It deterministically builds 29 retrieval-only section/page representatives,
measures their exact Nomic tokens and embeddings, and compares all four frozen
variants across the 60 body and eight header cases. It reconstructs the exact
published atomic chunk identities before ranking so the accepted `0.873056`
baseline—including deterministic tie breaks—must replay byte-for-contract.
Lexical work runs in a private Unix-socket PostgreSQL cluster; Gemma and the
accepted databases are not contacted.

Every variant is replayed twice, with content-free case ranks compared for
determinism. The retained observation reports body/header metrics and warm
retrieval latency diagnostics. Passing this script does not promote a
candidate: even a variant above the strict `0.91` MRR gate proceeds only to a
review-before-freeze gate. Corpus v1, published corpus v2, truth files,
packages, services, and the production retrieval profile remain unchanged.

Frozen decision `V13-31` lowers the synthetic-corpus-v2 optimization baseline
gate to MRR@20 `>= 0.89` while retaining complete body and header evidence
coverage. Script `174` applies that decision to the retained Script `173`
evidence and records `section_page_duplicate_canonical`, at MRR@20 `0.903333`,
as the immutable optimization baseline:

```bash
bash ./phase-28-apisachi-tokuli/scripts/174_promote_frozen_synthetic_corpus_v2_retrieval_baseline.sh --run
```

This is an evidence-only promotion. It does not modify the published corpus,
production retrieval profile, accepted application release, or deployment
package.

After Script `174` passes, Script `175` searches bounded retrieval parameters
against that exact checksum-bound baseline:

```bash
bash ./phase-28-apisachi-tokuli/scripts/175_search_frozen_synthetic_corpus_v2_retrieval_optimizations.sh --run
```

It embeds the fixed 68 questions once, captures the exact, lexical, and vector
lanes once, proves that the promoted `0.903333` baseline replays exactly, and
then evaluates 2,646 RRF constant, lexical/vector weight, and lane-depth
profiles offline. It retains the best 25 observations and deterministically
replays the leading finalist. The result is observational: it cannot promote
a finalist or change the production retrieval profile. A later review and
qualification gate is required before any profile freeze.

Script `176` performs that content-free finalist review:

```bash
bash ./phase-28-apisachi-tokuli/scripts/176_review_frozen_v2_retrieval_optimization_finalists.sh --run
```

It validates the complete Script `175` search, records the `0.012500` absolute
MRR improvement and the absence of case regressions, and selects the
minimum-delta finalist for live qualification: lexical weight `2` with exact
weight `1`, vector weight `4`, RRF constant `60`, and both semantic lane
depths `20`. The selected profile changes only the lexical weight. Script
`176` also freezes neither that profile nor the production configuration; it
defines five repeated warm live measurements as the next qualification gate.

Script `177` executes that live qualification:

```bash
bash ./phase-28-apisachi-tokuli/scripts/177_qualify_selected_v2_retrieval_finalist_live.sh --run
```

It performs one warm-up followed by five measured runs. Every run freshly
embeds all 68 fixed questions through the forwarded Nomic endpoint and freshly
executes the PostgreSQL lexical lane in a private Unix-socket cluster. The
promoted baseline and selected candidate are fused from the same per-run lanes.
The gate requires the baseline MRR `0.903333`, candidate MRR `0.915833`, full
body and header coverage, the same two improved cases, zero regressed cases,
and identical ranks across all measured runs. Median and p95 query-embedding,
lane, fusion, and total-retrieval latency are retained. A pass authorizes only
the final review before freeze; it still does not modify the production
profile.

Script `178` performs that final content-free review:

```bash
bash ./phase-28-apisachi-tokuli/scripts/178_review_live_v2_retrieval_finalist_before_freeze.sh --run
```

It binds the five-run Script `177` evidence, confirms deterministic ranking,
complete body/header coverage, zero case regressions, and no observed latency
regression, then assigns one stable identity to the complete candidate:
section/page representatives, document-local duplicate canonicalization, and
the `1/2/4` exact/lexical/vector weight profile at depth `20` and RRF constant
`60`. Its latency sample is diagnostic rather than an SLA. A clean result says
only that the candidate is ready for an explicit operator freeze decision; it
does not freeze, implement, or promote the candidate.

Script `179` binds the operator's V13-32 freeze to that reviewed candidate and
qualifies its application implementation:

```bash
bash ./phase-28-apisachi-tokuli/scripts/179_freeze_and_qualify_v13_32_application_implementation.sh --run
```

It proves that the implemented section/page representatives are semantically
identical to the Script `178` candidate, runs 414 native and 24 supplemental
tests, applies schema version 5 to a disposable Unix-socket-only PostgreSQL
cluster, runs 17 JavaScript tests, and performs an offline Next.js build with
the existing architecture-matched image. It does not contact models or the
accepted database, read credentials, modify either synthetic corpus, assemble
a package, or promote a release. The final `SCRIPT RESULT` marker is printed
on its own line. A pass authorizes a fresh 60-body and 8-header retrieval gate
from the implemented source.

After Script `179` passes, Script `180` runs that fresh implemented-source
retrieval gate:

```bash
bash ./phase-28-apisachi-tokuli/scripts/180_qualify_implemented_v13_32_retrieval.sh --run
```

It deterministically rebuilds all 139 atomic candidates and 29 retrieval-only
section/page representatives with the application chunker, freshly embeds all
168 candidates and all 68 fixed questions through the existing loopback Nomic
service, and exercises the application RRF, group-collapse, and authoritative
atomic-expansion functions. PostgreSQL lexical ranking runs in a disposable
Unix-socket-only cluster. MRR and top-rank coverage are measured at the
collapsed structural-selection boundary, where the retrieval order is decided.
Expansion into ordered atomic evidence is then qualified separately; atomic
positions are retained as a diagnostic and are not treated as a second ranking
operation. The gate requires body `MRR@20 >= 0.89`, all 60 body cases and
evidence pairs in the accepted selection ranks, complete 8-case and 11-evidence
header gates, and all 71 required evidence pairs after authoritative expansion.
It does not call Gemma, contact the accepted database, or change a corpus, truth
set, profile, package, or release. A pass authorizes the complete Retrieval
API/Gemma evaluation. If the gate is missed, the safe metric summary and
content-free failed observation are retained so the regression can be diagnosed
without repeating a blind run.

Script `181` runs the complete thirteen-case Retrieval API/Gemma gate against
one disposable PostgreSQL 16 ingestion of the frozen synthetic corpus v2:

```bash
bash ./phase-28-apisachi-tokuli/scripts/181_qualify_v1_3_complete_retrieval_api_and_gemma.sh --run
```

It requires all six responsive questions, all six abstention questions, and
the broad-navigation clarification case to return their exact expected status.
All thirteen required document/page pairs must be returned and cited. The
V13-34 correction treats each ranked section/page envelope as one diversity
unit while preserving every authoritative atom, groups explicit relationship
locators the same way, chooses a duplicate target reference from the
highest-ranked direct evidence, and validates selected explicit-reference
target coverage in Gemma's citation-bearing response. Relationship provenance
remains an intact audit record when direct and locator routes meet, located
target units receive a diversity slot before ordinary units from that document,
and an explicit document/page route remains scoped to the requested page. The
existing one-retry and fail-closed boundaries remain. Failure retains the fully
synthetic response observation and content-free diagnostics; cleanup always
stops the API, removes the disposable cluster, and verifies both temporary
ports are free. A pass is required before deployment-candidate assembly.

Script `182` reruns that gate after the bounded post-ranking corrections
identified by Script `181`:

```bash
bash ./phase-28-apisachi-tokuli/scripts/182_qualify_corrected_v1_3_complete_retrieval_api_and_gemma.sh --run
```

It first runs all 429 native tests. The live gate then uses the same frozen
synthetic corpus v2, thirteen cases, truth, retrieval profile, lane depths,
weights, RRF constant, and acceptance thresholds as Script `181`. The corrected
boundary scans only evidence supplied to Gemma, reserves and requires citations
for both the referring evidence and each located explicit-reference target,
keeps explicit-page answers concise, and records whether a failed generation
was rejected model output or a transport failure. It still uses only the
forwarded loopback models and a disposable PostgreSQL cluster, retains
synthetic-only diagnostics on failure, performs verified cleanup, and leaves
accepted releases and deployment packages unchanged. A pass authorizes v1.3
deployment-candidate assembly; a block retains enough content-free stage detail
to diagnose the exact remaining integration layer without reopening retrieval
ranking by default.

Script `183` reruns the same complete gate after correcting the configured
ingestion and exact-record evidence boundaries exposed by Script `182`:

```bash
bash ./phase-28-apisachi-tokuli/scripts/183_qualify_relationship_complete_v1_3_api_and_gemma.sh --run
```

It runs all 435 native tests, ingests the unchanged synthetic corpus v2 into a
disposable PostgreSQL cluster, and proves that the real configured-ingestion
path publishes the accepted explicit-reference graph. Before starting the API,
it requires active edges from 99 TST 2001 to Form TST-9001 and 99 TST 2002 and
from the incident procedure to the governance manual. The thirteen-case live
gate also requires exact identifier evidence to remain citation-bearing when a
record identifier and requested fields occur on different pages. Corpus bytes,
truth, retrieval weights, depths, RRF, MRR threshold, accepted databases,
packages, releases, and org-lab state remain unchanged. A pass authorizes v1.3
deployment-candidate assembly; a block retains the synthetic observation and
content-free diagnostics for the next bounded correction.

Script `184` classifies the first responsive turn whose two permitted
generation attempts both fail without repeating the remainder of the complete
gate:

```bash
bash ./phase-28-apisachi-tokuli/scripts/184_classify_relationship_generation_failure.sh --run
```

It runs the unchanged Script `183` under the existing content-free generation
observer, stops Script `183` through its verified cleanup immediately after
one turn records both failed attempts, and reports only their stable failure
families and reason codes. A retry that succeeds does not end the diagnostic.
It does not retain prompts, model output,
chunks, vectors, or credentials and does not change the application, frozen
corpus, retrieval profile, truth, package, or release. The classification is a
diagnostic gate only; its result determines whether the next correction stays
inside the frozen implementation boundary or requires an operator decision.

Script `185` binds the operator's V13-35 freeze to the bounded
relationship-generation implementation:

```bash
bash ./phase-28-apisachi-tokuli/scripts/185_freeze_and_qualify_v13_35_relationship_generation_bound.sh --run
```

It verifies Script `184`'s two content-free failure classifications, proves
that only the three highest-ranked relationship identities enter generation,
and proves that the limit counts relationship identities rather than their
structural atoms. It also proves that excluding a relationship route cannot
remove the same atom's independently retrieved direct route. It then runs all
438 native tests. The script does not call Gemma or Nomic, contact PostgreSQL,
read credentials, change either synthetic corpus or truth set, alter retrieval
ranking, assemble a package, or promote a release. Its final `SCRIPT RESULT`
is printed on its own line. A pass authorizes the unchanged complete
thirteen-case API/Gemma qualification as the next gate.

Script `186` runs that unchanged thirteen-case Retrieval API/Gemma gate after
the V13-35 implementation passes local qualification:

```bash
bash ./phase-28-apisachi-tokuli/scripts/186_qualify_v13_35_complete_retrieval_api_and_gemma.sh --run
```

It runs all 438 native tests, ingests the unchanged six-document, 26-page
synthetic corpus v2 through the real configured pipeline into a disposable
PostgreSQL 16 cluster, and verifies the published relationship graph before
starting a temporary Retrieval API. The live gate requires the expected status
for all six responsive, six nonresponsive, and one broad-navigation case, plus
all thirteen required document/page pairs returned and cited. It uses the
existing forwarded loopback Gemma and Nomic services and does not change an
accepted database, corpus, truth set, retrieval profile, package, release, or
org-lab state. Synthetic observations and content-free diagnostics are retained
on failure; cleanup stops the API, removes the disposable cluster, and verifies
both temporary ports are free. Its final `SCRIPT RESULT` is printed on its own
line. A pass authorizes v1.3 deployment-candidate assembly.

Script `186` is retained only as a reproducible six-document v2-pilot gate.
V13-36 supersedes it as a frontier-promotion gate; do not use it to promote the
intentionally thin v2 pilot.

Script `187` freezes V13-36 through V13-38 and generates the expanded synthetic
corpus v3 candidate:

```bash
bash ./phase-28-apisachi-tokuli/scripts/187_freeze_generate_and_qualify_synthetic_corpus_v3.sh --run
```

It generates the corpus twice and requires byte-identical output: 30 documents,
150 semantic pages, six v2 semantic anchors, 24 new documents, 11 fictional
departments, 90 explicit-reference relationships, and seven form/checklist
documents with tables. Every document uses the accepted v2 first-page masthead.
Every page uses the observed footer pattern with fictional organization
abbreviation, policy number, `Page N of M`, use-only statement, and bounded
dates. The qualifier runs Poppler extraction, normalizes all 30 headers and 30
footers, proves footer policy/page consistency, creates 943 structural chunk
candidates, and proves that no footer text enters semantic retrieval content.
The script does not call a model, contact a database, mutate corpus v1 or v2,
change retrieval parameters, or assemble a release. Its final `SCRIPT RESULT`
is printed on its own line. A pass authorizes v3 truth construction and
pre-ingestion retrieval measurement.

Script `188` builds the v3 retrieval truth and records the first pre-ingestion
measurement of the unchanged frozen v1.3 retrieval implementation:

```bash
bash ./phase-28-apisachi-tokuli/scripts/188_build_v3_truth_and_measure_preingestion_retrieval.sh --run
```

It verifies the exact Script `187` report and 40-file candidate inventory,
builds 180 evaluation-only cases covering all 30 documents and all 150 pages,
freshly embeds all 943 atomic and retrieval-only structural candidates through
the existing loopback Nomic service, and embeds all 180 questions. Native
PostgreSQL lexical ranking runs in a private temporary Unix-socket-only cluster
with no corpus tables. The evaluator uses the frozen exact/lexical/vector RRF
weights, section/page representative collapse, and authoritative atomic
expansion. This is an observational baseline: low MRR is retained for review
and does not masquerade as a script failure or automatically tune retrieval.
The script does not ingest or publish corpus v3, call Gemma, contact an accepted
database, access the black corpus, change a retrieval profile, or promote a
release. Its final `SCRIPT RESULT` is printed on its own line. A pass authorizes
review of the v3 metrics before isolated ingestion.

The first Script `188` execution completed and retained its measurement but
then encountered a DrvFS permission-operation failure while applying `chmod`
to the retained files. The wrapper now treats that unsupported metadata change
as non-fatal; the already-retained embeddings and observation do not need to be
recomputed.

Script `189` recovers that completed measurement and performs a local,
content-free rank-failure review:

```bash
bash ./phase-28-apisachi-tokuli/scripts/189_recover_and_review_v3_preingestion_measurement.sh --run
```

It validates the retained Script `188` truth, embeddings, and observation,
classifies the post-measurement wrapper failure, measures results by expected
page, detects evaluation-only scope mismatches, and quantifies cross-document
template duplication and missing later-page document identity context. It does
not rerun Nomic, contact PostgreSQL or Gemma, mutate a corpus, tune retrieval,
or change a frozen profile. The final `SCRIPT RESULT` is printed on its own
line. The review determines whether isolated ingestion may proceed or whether
the frozen chunk-representation boundary requires discussion.

Frozen V13-39 applies the measured correction to the production chunking path,
including future black-corpus ingestion. Script `190` rebuilds the unchanged
30-document corpus-v3 candidate with compact authoritative document title and
identifier context on every body retrieval unit, freshly embeds all candidates,
and reruns all 180 retrieval cases:

```bash
bash ./phase-28-apisachi-tokuli/scripts/190_qualify_v13_39_postgresql_document_identity_context.sh --run
```

The gate requires body `MRR@20 >= 0.89`, complete body, relationship, header,
and authoritative-expansion coverage, header MRR `1.0`, and correction of the
generic-context evaluator scope error. It reports every gate result before
deciding, rather than stopping at the first miss. If qualification is blocked,
the checksum-bound chunks, embeddings, and observation are retained under a
clearly named `blocked_<timestamp>` diagnostic directory so the completed
measurement can be reviewed without another model call. It runs 443 native
tests first. On DrvFS, that synthetic-only diagnostic directory inherits the
workspace mount permissions because post-create POSIX mode changes are not
supported; credentials are never retained. The
runtime representation remains PostgreSQL-native: retrieval text, structured
identity provenance, filters, token accounting, and embeddings are written by
the canonical ingestion writer to `rag.chunks` and `rag.chunk_embeddings`.
Retained JSON from Script `190` is qualification evidence for the next isolated
ingestion gate; it is not a runtime index or product datastore. Script `190`
does not ingest corpus v3, call Gemma, contact an accepted database, access the
black corpus, change retrieval parameters, or assemble a release. Its final
`SCRIPT RESULT` is printed on its own line.

Script `196` measures the frozen V13-44 candidate-generation and reranking
experiment after V13-43 proved that additive document-affinity weights could
not introduce a missing passage:

```bash
bash ./phase-28-apisachi-tokuli/scripts/196_measure_v13_44_decomposed_passage_reranking.sh --run
```

It verifies the exact Script `195` report and observation, runs the complete
native regression suite, rebuilds the unchanged accepted-v6 943-candidate
inventory, and evaluates all 180 checksum-bound corpus-v3 cases. For body
questions only, it creates at most four literal query clauses, forms balanced
top-three or top-five document unions from the accepted primary lanes, makes
all permitted accepted-v6 passages inside those documents eligible, and tests
five predeclared deterministic final-reranking configurations. Relationship
and header cases remain on the accepted baseline path. Qualification still
requires body `MRR@20 >= 0.89`, body `120/120`, relationship `30/30`, header
`30/30` with header MRR `1.0`, and authoritative expansion `180/180`.

The experiment uses loopback Nomic and a private Unix-socket-only PostgreSQL
cluster. It retains metric and rank evidence but no question text, decomposed
query text, vectors, source text, credentials, or runtime flat-file index. It
does not ingest corpus v3, contact Gemma or an accepted database, access the
black corpus, change a production profile, or promote a package or release.
The final `SCRIPT RESULT` is printed on its own line. A qualifying candidate
still requires a separate freeze and application qualification.

Script `197` checks the required Nomic loopback forward before running the
native suite or rebuilding candidates. A missing listener is reported as
`nomic_forward_not_listening` with the exact endpoint and operator action.
Failure diagnostics are stage-specific and limited to their final 200 lines,
so a later failure does not dump the successful 444-test transcript over the
standalone `SCRIPT RESULT`.

Script `198` reviews the exact clean, nonqualifying Script `197` observation:

```bash
bash ./phase-28-apisachi-tokuli/scripts/198_review_v13_45_hierarchical_failures.sh --run
```

It classifies every body-case movement by document-shortlist inclusion,
section emission, relevant document rank, final rank, and relevant section
position inside its document. The review retains case identities and aggregate
metrics but no question text, source text, vectors, or structural-path text.
It contacts no model, database, service, or remote host and changes no corpus,
retrieval profile, application, package, or release. Its purpose is to
distinguish an execution defect from a failed frozen ranking topology before
any new candidate-generation or cross-document ordering decision is proposed.

Script `197` measures the frozen V13-45 hierarchical document/section ranking
experiment after V13-44 restored complete coverage but remained below the
frozen MRR gate:

```bash
bash ./phase-28-apisachi-tokuli/scripts/197_measure_v13_45_hierarchical_document_section_ranking.sh --run
```

It verifies the exact Script `196` observation, runs the complete native test
suite, rebuilds the unchanged accepted-v6 943-candidate inventory, and
evaluates all 180 checksum-bound corpus-v3 cases. Body retrieval deduplicates
the existing primary lexical/vector results into document ranks, compares five
predeclared top-eight/top-sixteen document configurations, ranks each selected
document's section/page representatives using literal query facets against
both structured heading/path and passage signals, and emits every document's
best section before its lower-ranked sections. Selected representatives still
expand only to authoritative atomic evidence. Relationship and header cases
remain on the accepted baseline path.

Heading/path views are ephemeral retrieval signals derived from existing
structured candidate metadata. They are not source evidence, citations,
Gemma context, or a runtime flat-file index. The experiment uses loopback
Nomic and private Unix-socket-only PostgreSQL, preserves the `0.89` MRR and all
coverage gates, and makes no ingestion, accepted-database, production-profile,
package, release, black-corpus, or org-lab change. The final `SCRIPT RESULT` is
printed on its own line. A qualifying candidate still requires a separate
freeze and application qualification.

Script `199` measures the frozen V13-46 score-calibrated global reranking
experiment:

```bash
bash ./phase-28-apisachi-tokuli/scripts/199_measure_v13_46_score_calibrated_global_reranking.sh --run
```

It rejects V13-45's strict document round-robin and preserves V13-44's
complete-coverage top-20 candidate pool. It evaluates exactly five
predeclared global-ordering configurations using query-local normalized raw
lexical/vector scores, retained RRF score, literal-facet coverage, trusted
structured heading/path overlap, and bounded document affinity. Relationship
and header ordering remain unchanged, and every candidate must still satisfy
body `MRR@20 >= 0.89`, body `120/120`, relationship `30/30`, header `30/30`
with header MRR `1.0`, and authoritative expansion `180/180`.

The evaluator reuses the exact checksum-bound Script `196` observation rather
than repeating identical Nomic and temporary-PostgreSQL work. It runs the full
native regression suite, rebuilds the accepted-v6 candidate inventory only in
memory to verify identity and obtain trusted structural paths, and retains no
question text, source text, structural-path text, vectors, credentials, or
runtime flat-file index. It contacts no model, database, service, or remote
host and makes no corpus, ingestion, accepted-database, production-profile,
package, release, black-corpus, or org-lab change. The final `SCRIPT RESULT` is
printed on its own line. A qualifying candidate requires a separate freeze,
application implementation, and qualification before promotion.

Script `202` qualifies the frozen V13-49 generation boundary and the corpus-v3
promotion gate in one operator command:

```bash
bash ./phase-28-apisachi-tokuli/scripts/202_qualify_v13_49_exact_generation_boundary.sh --run
```

It first runs the network-isolated browser tests and Next.js production build.
It then invokes the combined isolated gate, which runs the complete native
suite, publishes the unchanged 30-document corpus v3 into disposable
PostgreSQL, makes R-001 the fail-fast live Gemma canary, and continues through
the remaining twelve API cases only after that canary passes. The same command
retains the synthetic generation exchange, validates all artifacts, and emits
the corpus-promotion next gate.

V13-49 preserves the accepted `0.895450` body MRR and retrieval topology. It
makes automatically discovered relationship evidence optional for ordinary
questions, retains strict obligations for explicit references, budgets the
exact serialized no-thinking chat-template request through vLLM `/tokenize`,
removes only whole lowest-ranked optional structural units when necessary,
and preserves the 2,048-token answer reserve. The command does not alter an
accepted database, black corpus, remote host, package, release, or service.
Its final `SCRIPT RESULT` is printed on its own line with the detailed nested
failure reason retained immediately above it when blocked.

Script `203` consumes the exact passing Script `202` evidence, promotes the
checksum-bound 30-document corpus v3 as the frontier synthetic qualification
fixture, and assembles the Ishikawa v1.3 frontier deployment candidate in one
execution:

```bash
bash ./phase-28-apisachi-tokuli/scripts/203_promote_corpus_v3_and_assemble_v1_3_frontier_candidate.sh --run
```

It revalidates the corpus, database, R-001 canary, and complete 13-case API
artifacts; runs all 460 native tests; produces two byte-identical package
trees; enforces the coding standard; verifies a fresh application install and
schema-version-5 installer; creates a deterministic archive; and validates
every retained checksum. The corpus remains a synthetic qualification fixture
and is not included in the deployment archive. The command contacts no model,
database, target host, or remote service and does not accept or deploy the
candidate. Its standalone final result authorizes fresh v1.3 host
qualification on EmceeDanko.

Script `204` qualifies the frozen V13-50 bounded-generation and latency
changes against the unchanged corpus-v3 promotion gate:

```bash
bash ./phase-28-apisachi-tokuli/scripts/204_qualify_v13_50_bounded_generation_latency.sh --run
```

It runs the network-isolated browser tests and Next.js production build, then
executes the complete native suite, disposable PostgreSQL corpus-v3 ingest,
Nomic-warmed readiness, R-001 fail-fast canary, and all thirteen live API/Gemma
cases. The same execution validates that every answered case selected one of
the 8,192-, 12,288-, or 16,384-token prompt targets, stayed within that target
plus the 2,048-token answer reserve, and returned the six allowlisted retrieval
timings. It inspects the exact captured R-001 model request and requires the
applicable `99 TST 2001` evidence to lead a package containing no more than six
documents and 48 citation atoms. Ordinary generation admits no more than six
optional structural units before exact token fitting. It also validates the
compact request-local citation protocol and
authoritative PostgreSQL excerpt boundary through native regression and the
live answer/citation gate. The command does not change retrieval ranking,
corpus bytes, an accepted database, black corpus, package, release, service
installation, or autostart state. Its final `SCRIPT RESULT` is printed on its
own line, and any block includes the actionable nested failure immediately
above it.

Script `206` qualifies the frozen V13-52 response-envelope boundary and the
complete local sixty-question frontier gate in one execution:

```bash
bash ./phase-28-apisachi-tokuli/scripts/206_qualify_v13_52_response_envelopes_and_frontier.sh --run
```

It first runs all 17 browser contract tests and a network-isolated Next.js
production build. It then invokes the combined isolated corpus-v3 workflow,
which runs all 464 native tests, regenerates and ingests the unchanged
30-document fixture into private disposable PostgreSQL, and contacts only the
operator-forwarded loopback Nomic and Gemma services. The live answer order is
R-001, then the six previously failed frontier cases R-012, R-016, R-036,
R-048, R-052, and R-054. Any canary failure stops the remaining questions;
six clean canaries automatically enable all remaining cases in the same run.

The final artifact must prove 60/60 response statuses, contracts, required
evidence returns, and required evidence citations with zero dependency
failures. Every response must use `ishikawa.chat-response.v5` and retain the
deterministic relevance reason, final sufficiency reason, and bounded actual
selection-group order. The workflow preserves V13-47 retrieval ranking and
its measured body MRR@20 of 0.895450; response envelopes are a post-retrieval
sufficiency and generation-ordering boundary. Each document envelope may pair
its highest-coverage result with one same-document complementary section; an
operational section that adds question coverage takes precedence over a
generic scope section. It creates no flat-file runtime
index, contacts no remote host, changes no accepted database, package,
release, service, or autostart state, and prints the final `SCRIPT RESULT` on
its own line. A pass routes directly to local human UI validation.

Script `207` qualifies the bounded V13-54 rank-one anchor correction and
reruns the complete local frontier gate:

```bash
bash ./phase-28-apisachi-tokuli/scripts/207_qualify_v13_53_document_order_and_frontier.sh --run
```

Script `206` proved that 59 of 60 questions passed and that R-028 already had
the required `Decision Record Form` page 3 at V13-47 rank one and inside the
Gemma request. The envelope planner nevertheless promoted the rank-two
`Controlled Access Exception Review` because its near-duplicate generic
control prose covered one more query lexeme. The first V13-53 Script `207` run
fixed R-028 but exposed that preserving every V13-47 document position crowded
the responsive `Incident Reporting and Response Procedure` companion out of
R-012's six-group package. V13-54 preserves only the V13-47 rank-one document
as the anchor, then orders remaining document envelopes by full-question
coverage. This keeps `Decision Record Form` first for R-028 while restoring
the incident-response operational/scope pair for R-012. Native regressions
cover both sides of the tradeoff. R-028 and R-012 run first after R-001,
followed by all prior canaries and then every remaining frontier question in
the same execution.

The command runs 17 browser contract tests, a network-isolated Next.js build,
all 466 native tests, fresh generation and ingestion of the unchanged
30-document corpus v3 into private disposable PostgreSQL, the eight-question
fail-fast sequence, and the complete 60-question live Gemma gate. It requires
60/60 status, contract, returned-evidence, and cited-evidence results and
validates cleanup before printing its standalone `SCRIPT RESULT`. It does not
change corpus bytes, truth, chunking, ingestion, embeddings, V13-47 retrieval
ranking or MRR, accepted databases, the black corpus, packages, releases,
EmceeDanko, org-lab, service installation, or autostart. A pass routes directly
to local human UI validation.
