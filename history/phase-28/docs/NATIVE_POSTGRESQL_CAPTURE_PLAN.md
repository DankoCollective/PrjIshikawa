# Native PostgreSQL/pgvector Capture Plan

## Selected Runtime Boundary

PostgreSQL and pgvector run natively on the application host. They are not
Docker images. The existing Node 24/Next.js 16.4.1 image remains the only
application container.

Each operating-system and architecture tuple receives its own native package
capture. A package closure captured for Ubuntu 24.04 `amd64` is not assumed to
be valid for another Ubuntu release or architecture.

## Capture Sequence

1. **Read-only target inventory.** Query the target's existing apt metadata for
   its default PostgreSQL major, server/client/contrib packages, pgvector
   candidates, `libpq`, and the native Python PostgreSQL driver. Record exact
   candidate coordinates and hashes where apt exposes them. Do not update apt,
   download packages, install anything, initialize a cluster, or change a
   service.
2. **Package-root review.** Select the exact PostgreSQL major and matching
   pgvector package only from the inventory evidence. The expected roots are
   the versioned PostgreSQL server and client, matching pgvector, and the
   selected native Python driver. Meta-packages and contrib packages may be
   used for discovery but are not captured unless an implemented feature
   requires them. The captured closure records every resolved dependency.
3. **Pre-download advisory review.** Map every selected binary package to its
   exact source/version. Record the authoritative advisory disposition for
   every selected source before downloading any package payload. Missing,
   pending, applicable unresolved, version-mismatched, source-mismatched, or
   target-mismatched decisions block capture. Signed repository metadata and
   advisory material may be acquired to establish the decision; `.deb`
   payload download may not begin until the full decision set passes.
4. **Offline closure capture.** Download the exact reviewed target-architecture
   `.deb` files into the ignored local artifact lane. Verify every package
   against signed repository metadata. Record package coordinates, dependency
   edges, source identities, licenses, advisory decisions, manifests, and
   complete checksums.
5. **Target-side carry verification.** Transfer only the reviewed closure and
   its checksum manifests. Recompute checksums on the target and stop for
   review. Do not install during carry verification.
6. **Guarded native installation.** Use a separate explicit operator action.
   Prevent unintended service start, verify the exact installed versions,
   keep boot enablement off, and stop before database/schema/application
   configuration.
7. **Database configuration and proof.** Separately create the local cluster,
   enforce loopback-only access, create least-privilege roles, enable the
   matching `vector` extension, apply plain SQL migrations, and prove native
   backup/restore. These actions are not part of package capture.

If no compatible pgvector package exists in the target's current approved apt
metadata, inventory stops with a review item. It does not silently add a new
repository, download source, compile an extension, or substitute a container.
Those are separate choices requiring explicit review.

## First Inventory Gate

Script `05_run_native_postgresql_package_inventory.sh` streams the neutral
`inspect-native-postgresql-packages` helper to the selected target and writes
the bounded result to the local ignored report lane. The helper performs no
target write and no network access. The operator runs the wrapper and retains
all passphrase custody.

Default EmceeDanko execution from the repository root:

```bash
bash ./phase-28-apisachi-tokuli/scripts/05_run_native_postgresql_package_inventory.sh
```

The accepted EmceeDanko report selects these Ubuntu 24.04 AMD64 roots:

- `postgresql-16=16.15-0ubuntu0.24.04.1`;
- `postgresql-client-16=16.15-0ubuntu0.24.04.1`;
- `postgresql-16-pgvector=0.6.0-1`; and
- `python3-psycopg=3.1.17-2`.

`python3-psycopg` is the selected native driver for the new implementation.
`python3-psycopg2` was available but is not selected or captured because no
legacy Psycopg 2 compatibility requirement exists. The offline capture must
block if any selected candidate changes from this accepted inventory.

The first Script `06` execution stopped safely before download because
`postgresql-16-pgvector` names the virtual dependency
`postgresql-16-jit-llvm`, which the accepted `postgresql-16` package provides.
The corrected resolver selects exact apt candidate archive records and
concrete providers for virtual dependencies. A local Ubuntu 24.04 metadata
replay resolved 98 packages and 98 URIs without download or installation. The
target AMD64 capture must still be rerun and reviewed before transfer.

The retained target metadata now proves a graph of 98 packages: the four
selected roots and 94 dependencies. EmceeDanko already satisfies 89 records;
its apt simulation selects nine missing packages totaling 41.77 MiB. Script
`06` resumes the verified metadata locally with `--resume-latest`, downloads
those exact nine packages on DankoSurface, and creates one checksum-bound
bundle. Individual manual downloads and package acquisition inside org-lab are
not required.

The Script `06` capture passed its integrity and provenance checks but failed
the separate advisory gate. PostgreSQL `16.15-0ubuntu0.24.04.1` is Canonical's
corrected Noble version, while Noble pgvector `0.6.0-1` is affected by
CVE-2026-3172 and CVE-2026-103484. Transfer and installation remain blocked.
Do not reuse the accepted capture as an installation bundle.

The operator approved qualification of a reviewed alternate source. The
official signed PostgreSQL Apt repository provides the native Noble AMD64
package `postgresql-16-pgvector=0.8.7-1.pgdg24.04+1`. The complete six-source
replacement set passed the new pre-download advisory gate. Script `07` verifies
that gate, official key and repository metadata, then downloads only the one
reviewed replacement pgvector payload and reuses the eight already verified
Ubuntu packages. It does not configure PGDG on a host or contact a target.

Script `08` subsequently proved that this package set is not installable:
PGDG pgvector requires PostgreSQL's JIT virtual version `19`, while the Ubuntu
server package provides version `17`. Script `09` then proved that EmceeDanko
already has Ubuntu `libllvm19=1:19.1.1-1ubuntu1~24.04.2`. Canonical reports
four Noble advisory records for that source; all were reviewed, and the
dependency is accepted only for the scoped AMD64 PostgreSQL-JIT use described
in the evidence record. The next capture replaces the Ubuntu server and
`libllvm17t64` with signed PGDG PostgreSQL `16.15-1.pgdg24.04+2` and the exact
reviewed Ubuntu `libllvm19`; it retains the already reviewed client, libpq,
support, pgvector, and Psycopg packages.

Script `10` completed that capture and passed independent review. Its exact
nine-package bundle is the only accepted input to Script `11`. The new
preflight accounts for the exact `libllvm19` version already installed on
EmceeDanko, requires the other eight packages to remain absent, verifies the
JIT-19 relationship, and permits an apt simulation containing only those
eight pending packages plus an optional exact libllvm19 reinstall. It must
remove nothing and performs no installation.

The operator-executed Script `11` passed with exactly eight simulated installs,
zero removals, zero clusters, free port `5432`, complete review manifests, and
complete temporary cleanup. Script `12` is therefore the guarded installation
step. It requires explicit `--install` authorization, uses only the accepted
local package payloads with package sources disabled, suppresses automatic
cluster creation, prevents service start during package configuration, and
leaves PostgreSQL stopped and disabled. Database initialization remains a
separate later action after the installation receipt is reviewed.

The first Script `12` execution blocked at apt exit `100` during the support-
package transaction. It did not reach the PostgreSQL server or pgvector stage,
and temporary target cleanup passed. Because an apt transaction may partially
configure packages before returning failure, Script `13` performs a separate
read-only package, dpkg/apt, service, cluster, and listener inspection before
any corrected retry is designed.

Script `13` proved the target remained clean: only the pre-existing LLVM
runtime is installed, all other selected packages are absent, dpkg audit and
dependency checks pass, and PostgreSQL has no service, cluster, or listener.
The failed real transaction used apt `--no-download` with explicit transferred
file paths; simulation does not exercise that local-file acquisition boundary.
Script `14` removes that option while retaining `/dev/null` package sources,
rejecting loopback network proxies, exact local paths, checksum verification,
and the existing no-cluster/no-start safeguards.

The operator-executed Script `14` retry passed. All nine exact packages are
installed, the expected PostgreSQL `16.15`, pgvector `0.8.7`, and Psycopg
`3.1.17` runtimes are present, and PostgreSQL remains clusterless, stopped,
boot-disabled, and without a listener. Script `15` is the separate guarded
cluster-initialization gate. It creates only the distribution-managed
PostgreSQL `16/main` cluster, enables data checksums, applies local-only
loopback and SCRAM settings, and leaves the initialized cluster stopped with
manual startup. Application database, role, schema, extension, credential,
and service-start work remain later gates.

The operator-executed Script `15` passed and its receipt is accepted. Script
`16` is the next guarded gate. It uses configurable defaults of database
`rag_catalog`, non-login owner `rag_owner`, ingestion login `rag_ingest`, and
retrieval login `rag_retrieval`. It privately obtains the two login
passwords, temporarily starts the loopback-only cluster, creates the empty
database and roles, enables pgvector `0.8.7`, revokes public database access,
and grants the login roles only `CONNECT`. It then stops the cluster. The
application schema and exact ingestion/retrieval object privileges remain
plain-SQL migration work rather than being invented during bootstrap.

The first Script `16` execution blocked before SQL because the
`postgresql@16-main.service` start failed. No application database, role, or
extension instance was created, and temporary cleanup passed. Script `17` is
the next read-only gate. It inspects bounded systemd, configuration,
filesystem, control-data, listener, capacity, and classified log evidence
without retrying or changing the cluster service.

The operator-executed Script `17` passed and isolated the failure to server
configuration parsing. Port, storage, permissions, capacity, and cluster state
are valid. Review of the exact captured `postgresql-client-common=257build1.1`
source behavior showed that `pg_conftool` can treat a dotted IPv4 literal as a
number and leave it unquoted, making that a candidate cause rather than proof.
Script `18` is the bounded repair: it requires one active assignment with the
effective loopback value, canonicalizes only that assignment as
`listen_addresses = '127.0.0.1'`, preserves file identity, proves all other
lines unchanged, and validates the complete configuration while PostgreSQL
remains stopped. Script `16` may be retried only after the Script `18` receipt
passes review.

The first two Script `18` runs blocked before mutation because exact raw-line
matchers did not recognize the target's serialization. No configuration or
service state changed. The corrected KISS guard no longer guesses formatting:
it requires one active assignment and an effective value of exactly
`127.0.0.1`, rewrites only that assignment canonically, preserves a trailing
comment when present, proves every other line unchanged, and requires the
server binary to parse the complete candidate before installation.

The third Script `18` run passed, but its before and after configuration
content hashes are identical. It proves that the current canonical setting and
complete configuration parse successfully; it does not prove that this
setting caused the original start failure. The exact-cause claim is withdrawn.
A separate start/stop-only gate must prove current service operability before
Script `16` is retried.

Script `19` implements that gate. It binds the accepted Script `18` receipt,
starts only the existing cluster instance, proves Unix-socket readiness and a
single `127.0.0.1:5432` listener, then stops it and proves clean shutdown,
free port, and unchanged boot-disabled state. It executes no SQL, performs no
database query, processes no secret, and changes no database object.

The operator-executed Script `19` passed. That troubleshooting sequence is not
part of the final operator workflow. Its lessons are consolidated into the
canonical scripts: Script `15` writes and server-validates the quoted loopback
setting, while Script `16` performs full configuration parsing, start,
readiness, and loopback-listener checks before it asks for passwords or runs
SQL. Script `16` also returns bounded startup state and guarantees stop cleanup
on failure. It does not depend on Scripts `17`–`19` or their receipts.

The corrected operator-executed Script `16` then passed. The accepted receipt
proves the empty UTF-8 `rag_catalog` database, non-login `rag_owner`, separate
connect-only `rag_ingest` and `rag_retrieval` login roles, SCRAM-SHA-256
password storage, retrieval read-only default, and pgvector `0.8.7`. It also
proves zero application relations, no retained or emitted role secrets, and a
clean return to the stopped, boot-disabled state. Cluster and database
bootstrap are complete. The next gate is the reviewed plain-SQL application
schema and exact object-privilege migration; it must not recreate the accepted
cluster, database, roles, or extension.

Script `20` implements that gate. It binds the accepted Script `16` receipt,
stages one checksum-verified neutral helper and migration `0001`, starts the
existing cluster only for the transaction and validation, and restores the
stopped, boot-disabled state. The migration creates 20 empty catalog/private
tables and five active-only search views. Retrieval can select only those five
views; ingestion can read all 20 base tables and write 19, with the migration
ledger protected from application writes. Native full-text storage and its GIN
index are created now. The `vector(768)` column is created, but HNSW/IVFFlat is
deferred until retrieval calibration. No document, chunk, citation,
relationship, or embedding content is written.

The first target execution reached the migration transaction but returned a
SQL failure before commit. PostgreSQL then stopped cleanly and temporary files
were removed. The canonical helper was corrected to emit a content-free
SQLSTATE, migration line, bounded failure class, and diagnostic checksum while
deleting the raw error. The same Script `20` command remains the next gate;
there is no separate repair-script dependency.

The second execution exposed one remaining helper control-flow defect: the
generic Bash `ERR` trap ran before the intended classifier. The canonical
helper now evaluates `psql` in an explicit conditional so it can return the
bounded diagnostic on failure. Migration `0001` itself remains unchanged.

## Configuration Boundary

The service topology remains configurable through validated deployment YAML.
Defaults are:

```yaml
runtime:
  node_network_mode: host

web:
  bind_host: 127.0.0.1
  port: 3000
  retrieval_base_url: http://127.0.0.1:1384

retrieval:
  bind_host: 127.0.0.1
  port: 1384

postgresql:
  bind_host: 127.0.0.1
  port: 5432
```

These are deployment settings, not hard-coded application constants. A
non-loopback bind requires the separately reviewed external-exposure posture.
Secrets and database passwords never belong in this YAML.
