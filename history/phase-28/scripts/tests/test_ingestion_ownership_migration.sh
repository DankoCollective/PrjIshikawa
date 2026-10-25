#!/usr/bin/env bash
set -Eeuo pipefail

# Disposable local proof for migration 0002. It proves an empty accepted 0001
# upgrade, a fresh 0001+0002 install, safe rejection of nonempty legacy state,
# post-0002 ownership semantics, privileges, and schema equivalence. It never
# contacts a target and removes its temporary cluster on every exit path.

readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
readonly MIGRATION_0001="$PHASE_ROOT/migrations/0001_initial_rag_catalog.sql"
readonly MIGRATION_0002="$PHASE_ROOT/migrations/0002_align_ingestion_ownership.sql"
readonly SHA_0001="$(sha256sum "$MIGRATION_0001" | awk '{print $1}')"
readonly SHA_0002="$(sha256sum "$MIGRATION_0002" | awk '{print $1}')"
readonly POSTGRES_BIN=/usr/lib/postgresql/16/bin
readonly TEST_PORT=55441

for required in awk grep mkdir mktemp rm sha256sum sort; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'BLOCKED: missing local command: %s\n' "$required" >&2
    exit 2
  }
done
for binary in initdb pg_ctl psql; do
  [[ -x "$POSTGRES_BIN/$binary" ]] || {
    printf 'BLOCKED: missing PostgreSQL 16 binary: %s\n' "$binary" >&2
    exit 2
  }
done
for migration in "$MIGRATION_0001" "$MIGRATION_0002"; do
  [[ -f "$migration" && ! -L "$migration" && -r "$migration" ]] || {
    printf 'BLOCKED: migration is missing or unsafe.\n' >&2
    exit 2
  }
done

work_root="$(mktemp -d /tmp/rag-ownership-migration.XXXXXX)"
data_root="$work_root/data"
socket_root="$work_root/socket"
log_path="$work_root/postgresql.log"
mkdir -m 0700 "$socket_root"
cluster_started=false

cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  set +e
  if [[ "$cluster_started" == true ]]; then
    "$POSTGRES_BIN/pg_ctl" -D "$data_root" -m fast stop >/dev/null 2>&1
  fi
  if [[ "$work_root" == /tmp/rag-ownership-migration.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

"$POSTGRES_BIN/initdb" -D "$data_root" --no-locale --encoding=UTF8 \
  --auth-local=trust --auth-host=reject >/dev/null
"$POSTGRES_BIN/pg_ctl" -D "$data_root" -l "$log_path" \
  -o "-k $socket_root -p $TEST_PORT -c listen_addresses=''" start >/dev/null
cluster_started=true

psql=(
  "$POSTGRES_BIN/psql"
  --no-psqlrc
  --set=ON_ERROR_STOP=1
  --host="$socket_root"
  --port="$TEST_PORT"
)

"${psql[@]}" --dbname=postgres --quiet <<'SQL'
CREATE ROLE rag_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
CREATE ROLE rag_ingest LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOREPLICATION NOBYPASSRLS;
CREATE ROLE rag_retrieval LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOREPLICATION NOBYPASSRLS;
CREATE DATABASE rag_upgrade WITH OWNER rag_owner ENCODING 'UTF8' TEMPLATE template0;
CREATE DATABASE rag_fresh WITH OWNER rag_owner ENCODING 'UTF8' TEMPLATE template0;
CREATE DATABASE rag_legacy_nonempty WITH OWNER rag_owner ENCODING 'UTF8' TEMPLATE template0;
REVOKE ALL ON DATABASE rag_upgrade, rag_fresh, rag_legacy_nonempty FROM PUBLIC;
GRANT CONNECT ON DATABASE rag_upgrade, rag_fresh, rag_legacy_nonempty TO rag_ingest, rag_retrieval;
ALTER ROLE rag_retrieval SET default_transaction_read_only = on;
SQL

for database in rag_upgrade rag_fresh rag_legacy_nonempty; do
  "${psql[@]}" --dbname="$database" --quiet <<'SQL'
CREATE EXTENSION vector;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
SQL
done

apply_migration() {
  local database="$1" migration="$2" migration_sha256="$3"
  "${psql[@]}" --dbname="$database" --quiet \
    --set=owner_role=rag_owner \
    --set=ingest_role=rag_ingest \
    --set=retrieval_role=rag_retrieval \
    --set=migration_sha256="$migration_sha256" \
    <"$migration"
}

# Upgrade path: establish durable 0001, restart, then apply 0002.
apply_migration rag_upgrade "$MIGRATION_0001" "$SHA_0001"
"$POSTGRES_BIN/pg_ctl" -D "$data_root" -m fast stop >/dev/null
cluster_started=false
"$POSTGRES_BIN/pg_ctl" -D "$data_root" -l "$log_path" \
  -o "-k $socket_root -p $TEST_PORT -c listen_addresses=''" start >/dev/null
cluster_started=true
apply_migration rag_upgrade "$MIGRATION_0002" "$SHA_0002"

# Fresh-install path: apply the ordered migrations without an intermediate
# application lifecycle.
apply_migration rag_fresh "$MIGRATION_0001" "$SHA_0001"
apply_migration rag_fresh "$MIGRATION_0002" "$SHA_0002"

# Safety path: a legacy 0001 database containing application rows must not be
# rewritten with invented registry/catalog identities.
apply_migration rag_legacy_nonempty "$MIGRATION_0001" "$SHA_0001"
"${psql[@]}" --dbname=rag_legacy_nonempty --quiet <<'SQL'
INSERT INTO rag.document_classes (class_id, display_name, registry_version, status)
VALUES ('policy', 'Policy', 'legacy-version', 'active');
SQL
set +e
apply_migration rag_legacy_nonempty "$MIGRATION_0002" "$SHA_0002" \
  >"$work_root/legacy.stdout" 2>"$work_root/legacy.stderr"
legacy_status=$?
set -e
[[ "$legacy_status" -ne 0 ]] || {
  printf 'FAIL: nonempty legacy catalog unexpectedly migrated.\n' >&2
  exit 1
}
grep -Fq 'migration 0002 requires an empty 0001 application catalog' \
  "$work_root/legacy.stderr" || {
    printf 'FAIL: nonempty legacy rejection was not classified correctly.\n' >&2
    exit 1
  }
legacy_contract="$("${psql[@]}" --dbname=rag_legacy_nonempty --tuples-only --no-align \
  --command="SELECT (SELECT count(*) FROM rag.schema_migrations) || '|' || (SELECT count(*) FROM information_schema.columns WHERE table_schema='rag' AND table_name='documents' AND column_name='class_id');")"
[[ "$legacy_contract" == '1|1' ]] || {
  printf 'FAIL: rejected legacy migration did not roll back cleanly: %s\n' "$legacy_contract" >&2
  exit 1
}

schema_fingerprint() {
  local database="$1"
  "${psql[@]}" --dbname="$database" --tuples-only --no-align --quiet <<'SQL' \
    | sort | sha256sum | awk '{print $1}'
SELECT 'column|' || table_schema || '|' || table_name || '|' || ordinal_position || '|' ||
       column_name || '|' || data_type || '|' || udt_schema || '|' || udt_name || '|' ||
       is_nullable || '|' || COALESCE(column_default, '')
FROM information_schema.columns
WHERE table_schema IN ('rag', 'rag_private', 'rag_search')
UNION ALL
SELECT 'constraint|' || n.nspname || '|' || c.relname || '|' || con.conname || '|' ||
       pg_get_constraintdef(con.oid, true)
FROM pg_constraint con
JOIN pg_class c ON c.oid = con.conrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname IN ('rag', 'rag_private')
UNION ALL
SELECT 'index|' || schemaname || '|' || tablename || '|' || indexname || '|' || indexdef
FROM pg_indexes
WHERE schemaname IN ('rag', 'rag_private')
UNION ALL
SELECT 'view|' || schemaname || '|' || viewname || '|' || definition
FROM pg_views
WHERE schemaname = 'rag_search'
UNION ALL
SELECT 'grant|' || table_schema || '|' || table_name || '|' || grantee || '|' || privilege_type
FROM information_schema.role_table_grants
WHERE table_schema IN ('rag', 'rag_private', 'rag_search');
SQL
}

upgrade_fingerprint="$(schema_fingerprint rag_upgrade)"
fresh_fingerprint="$(schema_fingerprint rag_fresh)"
[[ "$upgrade_fingerprint" == "$fresh_fingerprint" ]] || {
  printf 'FAIL: upgrade and fresh schema fingerprints differ.\n' >&2
  exit 1
}

contract_query="SELECT
  (SELECT count(*) FROM pg_namespace WHERE nspname IN ('rag','rag_private','rag_search')) || '|' ||
  (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('rag','rag_private') AND c.relkind='r') || '|' ||
  (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='rag_search' AND c.relkind='v') || '|' ||
  (SELECT count(*) FROM rag.schema_migrations WHERE migration_id IN ('0001_initial_rag_catalog','0002_align_ingestion_ownership')) || '|' ||
  (SELECT count(*) FROM information_schema.columns WHERE table_schema='rag' AND table_name='documents' AND column_name='class_id') || '|' ||
  (SELECT count(*) FROM information_schema.columns WHERE table_schema='rag' AND table_name='document_versions' AND column_name IN ('assigned_class_id','class_registry_version','ingestion_manifest_digest')) || '|' ||
  (SELECT count(*) FROM information_schema.columns WHERE table_schema='rag' AND table_name='document_artifact_sets' AND column_name IN ('assigned_class_id','class_registry_digest','ingestion_manifest_digest','manifest_entry_identity')) || '|' ||
  (SELECT count(*) FROM information_schema.columns WHERE table_schema='rag_private' AND table_name='quarantine_records' AND column_name IN ('manifest_entry_identity','resolved_by_run_id','resolution_code'));"

upgrade_contract="$("${psql[@]}" --dbname=rag_upgrade --tuples-only --no-align \
  --command="$contract_query")"
fresh_contract="$("${psql[@]}" --dbname=rag_fresh --tuples-only --no-align \
  --command="$contract_query")"
[[ "$upgrade_contract" == '3|20|5|2|0|0|4|3' ]] || {
  printf 'FAIL: upgraded schema contract mismatch: %s\n' "$upgrade_contract" >&2
  exit 1
}
[[ "$fresh_contract" == "$upgrade_contract" ]] || {
  printf 'FAIL: fresh schema contract mismatch: %s\n' "$fresh_contract" >&2
  exit 1
}

# Populate only synthetic post-0002 records. Two validated artifact sets share
# one immutable source revision and method profile but carry different classes.
"${psql[@]}" --dbname=rag_upgrade --quiet <<'SQL'
INSERT INTO rag.document_classes (class_id, display_name, registry_digest, status)
VALUES
  ('policy', 'Policy', repeat('a',64), 'active'),
  ('regulation', 'Regulation', repeat('a',64), 'active');
INSERT INTO rag.documents (document_id, document_key, display_name, catalog_digest, status)
VALUES (repeat('1',64), 'document.alpha', 'Document Alpha', repeat('b',64), 'active');
INSERT INTO rag.ingestion_runs (
  ingestion_run_id, ingestion_manifest_digest, schema_version,
  method_profile_id, state, started_at, finished_at,
  class_registry_digest, document_catalog_digest
) VALUES
  (repeat('2',64), repeat('c',64), 1, repeat('d',64), 'succeeded',
    clock_timestamp(), clock_timestamp(), repeat('a',64), repeat('b',64)),
  (repeat('8',64), repeat('e',64), 1, repeat('d',64), 'quarantined',
    clock_timestamp(), clock_timestamp(), repeat('a',64), repeat('b',64)),
  (repeat('9',64), repeat('f',64), 1, repeat('d',64), 'succeeded',
    clock_timestamp(), clock_timestamp(), repeat('a',64), repeat('b',64));
INSERT INTO rag.document_versions (
  document_version_id, document_id, source_digest, source_format, page_count,
  created_by_run_id
) VALUES (
  repeat('3',64), repeat('1',64), repeat('f',64), 'application/pdf', 1,
  repeat('2',64)
);
INSERT INTO rag.document_artifact_sets (
  artifact_set_id, document_version_id, document_id, method_profile_id,
  ingestion_run_id, processing_profiles, state, validation_digest,
  assigned_class_id, class_registry_digest, ingestion_manifest_digest,
  manifest_entry_identity
) VALUES
  (repeat('4',64), repeat('3',64), repeat('1',64), repeat('d',64),
    repeat('2',64), '[]', 'validated', repeat('4',64),
    'policy', repeat('a',64), repeat('c',64), repeat('0',64)),
  (repeat('5',64), repeat('3',64), repeat('1',64), repeat('d',64),
    repeat('2',64), '[]', 'validated', repeat('5',64),
    'regulation', repeat('a',64), repeat('c',64), repeat('7',64));
INSERT INTO rag.publication_batches (
  publication_batch_id, ingestion_run_id, state, validation_digest,
  validated_at, published_at
) VALUES
  (repeat('6',64), repeat('2',64), 'published', repeat('6',64),
    clock_timestamp(), clock_timestamp()),
  (repeat('7',64), repeat('2',64), 'published', repeat('7',64),
    clock_timestamp(), clock_timestamp());
INSERT INTO rag.active_document_versions (
  document_id, document_version_id, artifact_set_id, publication_batch_id
) VALUES (repeat('1',64), repeat('3',64), repeat('5',64), repeat('7',64));
INSERT INTO rag_private.quarantine_records (
  quarantine_id, ingestion_run_id, stage_name, reason_code,
  manifest_entry_identity
) VALUES (
  repeat('a',64), repeat('8',64), 'validate', 'UNKNOWN_DOCUMENT_KEY',
  repeat('e',64)
);
UPDATE rag_private.quarantine_records
SET resolved_at = clock_timestamp(),
    resolved_by_run_id = repeat('9',64),
    resolution_code = 'successful_retry'
WHERE quarantine_id = repeat('a',64);
SQL

active_class="$("${psql[@]}" --dbname=rag_upgrade --tuples-only --no-align \
  --command="SELECT class_id FROM rag_search.active_documents WHERE document_key='document.alpha';")"
[[ "$active_class" == regulation ]] || {
  printf 'FAIL: active view did not use artifact-set class.\n' >&2
  exit 1
}
"${psql[@]}" --dbname=rag_upgrade --quiet \
  --command="UPDATE rag.active_document_versions SET artifact_set_id=repeat('4',64), publication_batch_id=repeat('6',64) WHERE document_id=repeat('1',64);"
reclassified_active_class="$("${psql[@]}" --dbname=rag_upgrade --tuples-only --no-align \
  --command="SELECT class_id FROM rag_search.active_documents WHERE document_key='document.alpha';")"
[[ "$reclassified_active_class" == policy ]] || {
  printf 'FAIL: active view did not follow the selected artifact-set class.\n' >&2
  exit 1
}

expect_constraint_failure() {
  local label="$1" expected="$2" sql="$3" error_path status
  error_path="$work_root/$label.err"
  set +e
  "${psql[@]}" --dbname=rag_upgrade --quiet --command="$sql" \
    >/dev/null 2>"$error_path"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || {
    printf 'FAIL: %s unexpectedly succeeded.\n' "$label" >&2
    exit 1
  }
  grep -Fq "$expected" "$error_path" || {
    printf 'FAIL: %s did not fail through the expected constraint.\n' "$label" >&2
    exit 1
  }
  printf '%s=pass\n' "$label"
}

expect_constraint_failure duplicate_semantic_artifact \
  'document_artifact_sets_semantic_inputs_key' \
  "INSERT INTO rag.document_artifact_sets (artifact_set_id,document_version_id,document_id,method_profile_id,ingestion_run_id,processing_profiles,state,validation_digest,assigned_class_id,class_registry_digest,ingestion_manifest_digest,manifest_entry_identity) VALUES (repeat('6',64),repeat('3',64),repeat('1',64),repeat('d',64),repeat('2',64),'[]','validated',repeat('6',64),'policy',repeat('a',64),repeat('c',64),repeat('6',64));"
expect_constraint_failure artifact_run_provenance_mismatch \
  'document_artifact_sets_run_provenance_fkey' \
  "INSERT INTO rag.document_artifact_sets (artifact_set_id,document_version_id,document_id,method_profile_id,ingestion_run_id,processing_profiles,state,validation_digest,assigned_class_id,class_registry_digest,ingestion_manifest_digest,manifest_entry_identity) VALUES (repeat('6',64),repeat('3',64),repeat('1',64),repeat('e',64),repeat('2',64),'[]','validated',repeat('6',64),'policy',repeat('b',64),repeat('c',64),repeat('6',64));"
expect_constraint_failure quarantine_subject_required \
  'quarantine_records_subject_check' \
  "INSERT INTO rag_private.quarantine_records (quarantine_id,ingestion_run_id,stage_name,reason_code) VALUES (repeat('b',64),repeat('8',64),'validate','UNKNOWN_DOCUMENT_KEY');"
expect_constraint_failure quarantine_resolution_atomic \
  'quarantine_records_resolution_v1_check' \
  "INSERT INTO rag_private.quarantine_records (quarantine_id,ingestion_run_id,stage_name,reason_code,manifest_entry_identity,resolved_at) VALUES (repeat('b',64),repeat('8',64),'validate','UNKNOWN_DOCUMENT_KEY',repeat('e',64),clock_timestamp());"

retrieval_contract="$("${psql[@]}" --dbname=rag_upgrade --tuples-only --no-align \
  --command="SELECT (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('rag','rag_private') AND c.relkind='r' AND has_table_privilege('rag_retrieval',c.oid,'SELECT')) || '|' || (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='rag_search' AND c.relkind='v' AND has_table_privilege('rag_retrieval',c.oid,'SELECT')) || '|' || (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('rag','rag_private') AND c.relkind='r' AND has_table_privilege('rag_ingest',c.oid,'INSERT') AND has_table_privilege('rag_ingest',c.oid,'UPDATE') AND has_table_privilege('rag_ingest',c.oid,'DELETE'));"
)"
[[ "$retrieval_contract" == '0|5|19' ]] || {
  printf 'FAIL: role privilege contract mismatch: %s\n' "$retrieval_contract" >&2
  exit 1
}

"${psql[@]}" --dbname=rag_upgrade --username=rag_retrieval --quiet \
  --command='SELECT count(*) FROM rag_search.active_documents;' >/dev/null
set +e
"${psql[@]}" --dbname=rag_upgrade --username=rag_retrieval --quiet \
  --command='SELECT count(*) FROM rag.document_artifact_sets;' \
  >/dev/null 2>"$work_root/retrieval-denial.err"
retrieval_status=$?
set -e
[[ "$retrieval_status" -ne 0 ]]
grep -Fq 'permission denied' "$work_root/retrieval-denial.err"

resolution_contract="$("${psql[@]}" --dbname=rag_upgrade --tuples-only --no-align \
  --command="SELECT resolution_code || '|' || (resolved_by_run_id=repeat('9',64))::text || '|' || (resolved_at IS NOT NULL)::text FROM rag_private.quarantine_records WHERE quarantine_id=repeat('a',64);")"
[[ "$resolution_contract" == 'successful_retry|true|true' ]] || {
  printf 'FAIL: quarantine remediation linkage mismatch: %s\n' "$resolution_contract" >&2
  exit 1
}

printf '%s\n' \
  "migration_0001_sha256=$SHA_0001" \
  "migration_0002_sha256=$SHA_0002" \
  "upgrade_schema_fingerprint=$upgrade_fingerprint" \
  "fresh_schema_fingerprint=$fresh_fingerprint" \
  "upgrade_contract=$upgrade_contract" \
  "fresh_contract=$fresh_contract" \
  'nonempty_legacy_catalog_rejected=true' \
  "active_artifact_class_initial=$active_class" \
  "active_artifact_class_after_pointer_change=$reclassified_active_class" \
  "retrieval_privilege_contract=$retrieval_contract" \
  "quarantine_resolution_contract=$resolution_contract" \
  'ingestion_ownership_migration_test=pass'
