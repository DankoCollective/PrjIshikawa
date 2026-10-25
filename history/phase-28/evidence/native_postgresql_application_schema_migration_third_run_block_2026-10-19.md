# Native PostgreSQL Application Schema Migration Third-Run Block — 2026-10-19

## Disposition

The third operator-executed Script `20` run is blocked and is not accepted as
a completed migration.

Blocked report:

- `native_postgresql_application_schema_migration_20261019T160714Z_0eBEKe.txt`
- SHA-256:
  `a661daab48b408ba7ed2abc937be53d0feded4f0845585bc76e87d0a5ed0e911`

The receipt proves the exact helper and migration payloads, PostgreSQL
`16.15`, pgvector `0.8.7`, database and role identities, cluster start,
readiness, single loopback listener, a classified privilege failure, clean
cluster stop, bounded output validation, target temporary-file removal, and
SSH cleanup. It contains no migration pass marker.

The bounded SQL diagnostic is 125 bytes with SHA-256
`071c7d7036f2695acb484eb44b8d7a0c7c5fab95c5ce5760f55dbcfcf4d2aa16`.
Those two values exactly match the deterministic `psql` error stating that it
could not open the checksum-verified migration pathname in the mode-`0700`
operator-owned temporary transfer directory after execution changed to the
`postgres` OS account. The database role grants and SQL definitions were not
the source of this failure; `psql` never read the migration.

The canonical helper now preserves the private transfer directory and streams
the reviewed migration over standard input: the root helper opens the file,
while `psql` continues to execute as the `postgres` OS account. No target
directory permission is widened, and migration `0001` is unchanged.

After isolating the transport failure, the pre-acceptance look-ahead review
strengthened the current migration `0001` with composite foreign keys that
reject cross-document and cross-artifact links and with active-version class
projection. The current migration identity is
`3e2f5e61bd8038bc29764024e21b8bec754fad8a282f89abaf6130e345d6380a`.
This is a pre-acceptance replacement, not an upgrade: the three prior target
runs never read and committed the historical SQL checksum.

The same correction adds two forward checks before another target run:

- an existing migration is accepted only when the exact migration identifier,
  checksum, schema version, object counts, ownership, and role privileges all
  match; and
- Script `20` must completely stop and restart PostgreSQL, then re-verify the
  `3|20|5|1|0|5|19` schema/ledger/privilege contract before it can pass.

A disposable local PostgreSQL `16.15` run passed the streamed migration, all
object and role checks, direct retrieval-view access, denial of retrieval base-
table access, and the complete post-restart persistence contract. The
expanded regression also passed six negative cross-document/cross-artifact
integrity cases, active-version classification, and exact already-applied
detection. The
disposable cluster was then stopped and removed. The target remains unchanged
except for the already accepted durable database and roles from Script `16`;
the failed transactional migration did not leave an accepted partial schema.

The only next command remains the corrected canonical Script `20` command.
