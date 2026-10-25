#!/usr/bin/env bash
set -Eeuo pipefail

# Disposable local proof for migration 0003. It verifies the accepted empty
# 0001+0002 upgrade, exact token-column semantics, privileges, restart
# persistence, and rejection of a nonempty application catalog.

readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
readonly MIGRATION_0001="$PHASE_ROOT/migrations/0001_initial_rag_catalog.sql"
readonly MIGRATION_0002="$PHASE_ROOT/migrations/0002_align_ingestion_ownership.sql"
readonly MIGRATION_0003="$PHASE_ROOT/migrations/0003_separate_special_token_count.sql"
readonly SHA_0001='3e2f5e61bd8038bc29764024e21b8bec754fad8a282f89abaf6130e345d6380a'
readonly SHA_0002='74b08adb8aac9828ac076744fedfd22619751326c911bf17f1fa8690e01345e4'
readonly SHA_0003='5e833d8ff556c0e6158daf0419b1013235a11e1a94f1f560206ba813e1fc3761'
readonly POSTGRES_BIN=/usr/lib/postgresql/16/bin
readonly TEST_PORT=55443

for required in awk grep mkdir mktemp rm sha256sum; do
  command -v "$required" >/dev/null 2>&1 || { printf 'BLOCKED: missing local command: %s\n' "$required" >&2; exit 2; }
done
for binary in initdb pg_ctl psql; do
  [[ -x "$POSTGRES_BIN/$binary" ]] || { printf 'BLOCKED: missing PostgreSQL 16 binary: %s\n' "$binary" >&2; exit 2; }
done
for migration in "$MIGRATION_0001" "$MIGRATION_0002" "$MIGRATION_0003"; do
  [[ -f "$migration" && ! -L "$migration" && -r "$migration" ]] || { printf 'BLOCKED: migration input is missing or unsafe.\n' >&2; exit 2; }
done
[[ "$(sha256sum "$MIGRATION_0001" | awk '{print $1}')" == "$SHA_0001" ]] || { printf 'FAIL: 0001 identity mismatch.\n' >&2; exit 1; }
[[ "$(sha256sum "$MIGRATION_0002" | awk '{print $1}')" == "$SHA_0002" ]] || { printf 'FAIL: 0002 identity mismatch.\n' >&2; exit 1; }
[[ "$(sha256sum "$MIGRATION_0003" | awk '{print $1}')" == "$SHA_0003" ]] || { printf 'FAIL: 0003 identity mismatch.\n' >&2; exit 1; }

work_root="$(mktemp -d /tmp/rag-special-token-migration.XXXXXX)"
data_root="$work_root/data"
socket_root="$work_root/socket"
log_path="$work_root/postgresql.log"
mkdir -m 0700 "$socket_root"
cluster_started=false
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  set +e
  if [[ "$cluster_started" == true ]]; then "$POSTGRES_BIN/pg_ctl" -D "$data_root" -m fast stop >/dev/null 2>&1; fi
  if [[ "$work_root" == /tmp/rag-special-token-migration.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

"$POSTGRES_BIN/initdb" -D "$data_root" --no-locale --encoding=UTF8 --auth-local=trust --auth-host=reject >/dev/null
"$POSTGRES_BIN/pg_ctl" -D "$data_root" -l "$log_path" -o "-k $socket_root -p $TEST_PORT -c listen_addresses=''" start >/dev/null
cluster_started=true
psql=("$POSTGRES_BIN/psql" --no-psqlrc --set=ON_ERROR_STOP=1 --host="$socket_root" --port="$TEST_PORT")

"${psql[@]}" --dbname=postgres --quiet <<'SQL'
CREATE ROLE rag_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
CREATE ROLE rag_ingest LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOREPLICATION NOBYPASSRLS;
CREATE ROLE rag_retrieval LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOREPLICATION NOBYPASSRLS;
CREATE DATABASE rag_upgrade WITH OWNER rag_owner ENCODING 'UTF8' TEMPLATE template0;
CREATE DATABASE rag_nonempty WITH OWNER rag_owner ENCODING 'UTF8' TEMPLATE template0;
REVOKE ALL ON DATABASE rag_upgrade, rag_nonempty FROM PUBLIC;
GRANT CONNECT ON DATABASE rag_upgrade, rag_nonempty TO rag_ingest, rag_retrieval;
ALTER ROLE rag_retrieval SET default_transaction_read_only = on;
SQL
for database in rag_upgrade rag_nonempty; do
  "${psql[@]}" --dbname="$database" --quiet --command='CREATE EXTENSION vector; REVOKE CREATE ON SCHEMA public FROM PUBLIC;'
done
apply_migration() {
  "${psql[@]}" --dbname="$1" --quiet --set=owner_role=rag_owner --set=ingest_role=rag_ingest --set=retrieval_role=rag_retrieval --set=migration_sha256="$3" <"$2"
}
for database in rag_upgrade rag_nonempty; do
  apply_migration "$database" "$MIGRATION_0001" "$SHA_0001"
  apply_migration "$database" "$MIGRATION_0002" "$SHA_0002"
done
"${psql[@]}" --dbname=rag_nonempty --quiet --command="INSERT INTO rag.document_classes (class_id,display_name,registry_digest,status) VALUES ('policy','Policy',repeat('a',64),'active');"

apply_migration rag_upgrade "$MIGRATION_0003" "$SHA_0003"
set +e
apply_migration rag_nonempty "$MIGRATION_0003" "$SHA_0003" >"$work_root/nonempty.stdout" 2>"$work_root/nonempty.stderr"
nonempty_status=$?
set -e
[[ "$nonempty_status" -ne 0 ]] || { printf 'FAIL: nonempty catalog unexpectedly migrated.\n' >&2; exit 1; }
grep -Fq 'migration 0003 requires an empty application catalog' "$work_root/nonempty.stderr" || { printf 'FAIL: nonempty rejection reason mismatch.\n' >&2; exit 1; }

ledger="$(${psql[@]} --dbname=rag_upgrade --tuples-only --no-align --quiet --command="SELECT string_agg(migration_id || '|' || migration_sha256 || '|' || schema_version, ';' ORDER BY schema_version) FROM rag.schema_migrations;")"
expected_ledger="0001_initial_rag_catalog|$SHA_0001|1;0002_align_ingestion_ownership|$SHA_0002|2;0003_separate_special_token_count|$SHA_0003|3"
[[ "$ledger" == "$expected_ledger" ]] || { printf 'FAIL: migration ledger mismatch.\n' >&2; exit 1; }
column_contract="$(${psql[@]} --dbname=rag_upgrade --tuples-only --no-align --quiet --command="SELECT data_type || '|' || is_nullable || '|' || COALESCE(column_default,'none') FROM information_schema.columns WHERE table_schema='rag' AND table_name='chunks' AND column_name='special_token_count';")"
[[ "$column_contract" == 'integer|NO|none' ]] || { printf 'FAIL: special-token column mismatch: %s\n' "$column_contract" >&2; exit 1; }
constraint_contract="$(${psql[@]} --dbname=rag_upgrade --tuples-only --no-align --quiet --command="SELECT regexp_replace(pg_get_constraintdef(oid,true),'[[:space:]]+',' ','g') FROM pg_constraint WHERE conrelid='rag.chunks'::regclass AND conname='chunks_total_embedding_token_count_v2_check';")"
[[ "$constraint_contract" == *'content_token_count'* && "$constraint_contract" == *'context_token_count'* && "$constraint_contract" == *'prefix_token_count'* && "$constraint_contract" == *'special_token_count'* ]] || { printf 'FAIL: token-total constraint mismatch.\n' >&2; exit 1; }
view_contract="$(${psql[@]} --dbname=rag_upgrade --tuples-only --no-align --quiet --command="SELECT count(*) FROM information_schema.columns WHERE table_schema='rag_search' AND table_name='active_chunks' AND column_name='special_token_count';")"
[[ "$view_contract" == 1 ]] || { printf 'FAIL: active view special-token field missing.\n' >&2; exit 1; }
comment_contract="$(${psql[@]} --dbname=rag_upgrade --tuples-only --no-align --quiet --command="SELECT count(*) FROM pg_description d JOIN pg_class c ON c.oid=d.objoid JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum=d.objsubid WHERE n.nspname='rag' AND c.relname='chunks' AND a.attname IN ('content_token_count','context_token_count','prefix_token_count','special_token_count','total_embedding_token_count') AND length(d.description)>0;")"
[[ "$comment_contract" == 5 ]] || { printf 'FAIL: token-column definitions missing.\n' >&2; exit 1; }
privilege_contract="$(${psql[@]} --dbname=rag_upgrade --tuples-only --no-align --quiet --command="SELECT has_table_privilege('rag_retrieval','rag_search.active_chunks','SELECT') || '|' || has_table_privilege('rag_retrieval','rag.chunks','SELECT');")"
[[ "$privilege_contract" == 'true|false' ]] || { printf 'FAIL: retrieval privilege mismatch.\n' >&2; exit 1; }
nonempty_rollback="$(${psql[@]} --dbname=rag_nonempty --tuples-only --no-align --quiet --command="SELECT (SELECT count(*) FROM rag.schema_migrations) || '|' || (SELECT count(*) FROM information_schema.columns WHERE table_schema='rag' AND table_name='chunks' AND column_name='special_token_count');")"
[[ "$nonempty_rollback" == '2|0' ]] || { printf 'FAIL: rejected migration did not roll back.\n' >&2; exit 1; }

"$POSTGRES_BIN/pg_ctl" -D "$data_root" -m fast stop >/dev/null
cluster_started=false
"$POSTGRES_BIN/pg_ctl" -D "$data_root" -l "$log_path" -o "-k $socket_root -p $TEST_PORT -c listen_addresses=''" start >/dev/null
cluster_started=true
restart_contract="$(${psql[@]} --dbname=rag_upgrade --tuples-only --no-align --quiet --command="SELECT count(*) FROM rag.schema_migrations WHERE migration_id='0003_separate_special_token_count';")"
[[ "$restart_contract" == 1 ]] || { printf 'FAIL: migration did not persist across restart.\n' >&2; exit 1; }

printf '%s\n' \
  "migration_0003_sha256=$SHA_0003" \
  'empty_upgrade=pass;nonempty_catalog_rejected=true' \
  'token_buckets=content_context_prefix_special;exact_total_constraint=pass' \
  'active_view_special_token_count=present;column_comments=5' \
  'retrieval_active_view_read=true;retrieval_base_table_read=false' \
  'restart_persistence=pass' \
  'special_token_count_migration_test=pass'
