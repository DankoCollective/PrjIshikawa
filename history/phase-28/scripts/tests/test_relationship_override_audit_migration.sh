#!/usr/bin/env bash
set -Eeuo pipefail

# Disposable local proof for migration 0004. It verifies the accepted
# 0001-through-0003 upgrade, override-audit constraints, privilege isolation,
# restart persistence, and rollback for both prerequisite guard failures.

readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
readonly MIGRATION_0001="$PHASE_ROOT/migrations/0001_initial_rag_catalog.sql"
readonly MIGRATION_0002="$PHASE_ROOT/migrations/0002_align_ingestion_ownership.sql"
readonly MIGRATION_0003="$PHASE_ROOT/migrations/0003_separate_special_token_count.sql"
readonly MIGRATION_0004="$PHASE_ROOT/migrations/0004_preserve_relationship_override_audit.sql"
readonly SHA_0001='3e2f5e61bd8038bc29764024e21b8bec754fad8a282f89abaf6130e345d6380a'
readonly SHA_0002='74b08adb8aac9828ac076744fedfd22619751326c911bf17f1fa8690e01345e4'
readonly SHA_0003='5e833d8ff556c0e6158daf0419b1013235a11e1a94f1f560206ba813e1fc3761'
readonly SHA_0004='5764f6e12a74b18747163c61ef3f314e8dff140a3586b298c62be616a1dc185f'
readonly POSTGRES_BIN=/usr/lib/postgresql/16/bin
readonly TEST_PORT=55444

for required in awk grep mkdir mktemp rm sha256sum; do
  command -v "$required" >/dev/null 2>&1 || { printf 'BLOCKED: missing local command: %s\n' "$required" >&2; exit 2; }
done
for binary in initdb pg_ctl psql; do
  [[ -x "$POSTGRES_BIN/$binary" ]] || { printf 'BLOCKED: missing PostgreSQL 16 binary: %s\n' "$binary" >&2; exit 2; }
done
for migration in "$MIGRATION_0001" "$MIGRATION_0002" "$MIGRATION_0003" "$MIGRATION_0004"; do
  [[ -f "$migration" && ! -L "$migration" && -r "$migration" ]] || { printf 'BLOCKED: migration input is missing or unsafe.\n' >&2; exit 2; }
done
[[ "$(sha256sum "$MIGRATION_0001" | awk '{print $1}')" == "$SHA_0001" ]] || { printf 'FAIL: 0001 identity mismatch.\n' >&2; exit 1; }
[[ "$(sha256sum "$MIGRATION_0002" | awk '{print $1}')" == "$SHA_0002" ]] || { printf 'FAIL: 0002 identity mismatch.\n' >&2; exit 1; }
[[ "$(sha256sum "$MIGRATION_0003" | awk '{print $1}')" == "$SHA_0003" ]] || { printf 'FAIL: 0003 identity mismatch.\n' >&2; exit 1; }
[[ "$(sha256sum "$MIGRATION_0004" | awk '{print $1}')" == "$SHA_0004" ]] || { printf 'FAIL: 0004 identity mismatch.\n' >&2; exit 1; }

work_root="$(mktemp -d /tmp/rag-relationship-audit-migration.XXXXXX)"
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
  if [[ "$work_root" == /tmp/rag-relationship-audit-migration.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
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
CREATE DATABASE rag_order_guard WITH OWNER rag_owner ENCODING 'UTF8' TEMPLATE template0;
CREATE DATABASE rag_override_guard WITH OWNER rag_owner ENCODING 'UTF8' TEMPLATE template0;
REVOKE ALL ON DATABASE rag_upgrade, rag_order_guard, rag_override_guard FROM PUBLIC;
GRANT CONNECT ON DATABASE rag_upgrade, rag_order_guard, rag_override_guard TO rag_ingest, rag_retrieval;
ALTER ROLE rag_retrieval SET default_transaction_read_only = on;
SQL
for database in rag_upgrade rag_order_guard rag_override_guard; do
  "${psql[@]}" --dbname="$database" --quiet --command='CREATE EXTENSION vector; REVOKE CREATE ON SCHEMA public FROM PUBLIC;'
done
apply_migration() {
  "${psql[@]}" --dbname="$1" --quiet \
    --set=owner_role=rag_owner --set=ingest_role=rag_ingest \
    --set=retrieval_role=rag_retrieval --set=migration_sha256="$3" <"$2"
}
for database in rag_upgrade rag_order_guard rag_override_guard; do
  apply_migration "$database" "$MIGRATION_0001" "$SHA_0001"
  apply_migration "$database" "$MIGRATION_0002" "$SHA_0002"
done
for database in rag_upgrade rag_override_guard; do
  apply_migration "$database" "$MIGRATION_0003" "$SHA_0003"
done

"${psql[@]}" --dbname=rag_override_guard --quiet <<'SQL'
SET session_replication_role = replica;
INSERT INTO rag.relationships (
  relationship_id, artifact_set_id, relationship_type, source_kind,
  source_identity, target_kind, target_identity, evidence_citation_id,
  detection_method, review_status, relationship_definition_version
) VALUES (
  repeat('1',64), repeat('2',64), 'references', 'document',
  repeat('3',64), 'external', 'legacy-target', repeat('4',64),
  'operator_override', 'accepted', 'legacy-v1'
);
RESET session_replication_role;
SQL

apply_migration rag_upgrade "$MIGRATION_0004" "$SHA_0004"

set +e
apply_migration rag_order_guard "$MIGRATION_0004" "$SHA_0004" >"$work_root/order.stdout" 2>"$work_root/order.stderr"
order_status=$?
apply_migration rag_override_guard "$MIGRATION_0004" "$SHA_0004" >"$work_root/override.stdout" 2>"$work_root/override.stderr"
override_status=$?
set -e
[[ "$order_status" -ne 0 ]] || { printf 'FAIL: wrong migration order unexpectedly passed.\n' >&2; exit 1; }
grep -Fq 'migration 0004 requires the accepted 0001 through 0003 migrations' "$work_root/order.stderr" || { printf 'FAIL: migration-order rejection reason mismatch.\n' >&2; exit 1; }
[[ "$override_status" -ne 0 ]] || { printf 'FAIL: legacy operator override unexpectedly passed.\n' >&2; exit 1; }
grep -Fq 'migration 0004 cannot invent audit provenance for existing operator overrides' "$work_root/override.stderr" || { printf 'FAIL: legacy-override rejection reason mismatch.\n' >&2; exit 1; }

ledger="$(${psql[@]} --dbname=rag_upgrade --tuples-only --no-align --quiet --command="SELECT string_agg(migration_id || '|' || migration_sha256 || '|' || schema_version, ';' ORDER BY schema_version) FROM rag.schema_migrations;")"
expected_ledger="0001_initial_rag_catalog|$SHA_0001|1;0002_align_ingestion_ownership|$SHA_0002|2;0003_separate_special_token_count|$SHA_0003|3;0004_preserve_relationship_override_audit|$SHA_0004|4"
[[ "$ledger" == "$expected_ledger" ]] || { printf 'FAIL: migration ledger mismatch.\n' >&2; exit 1; }
column_contract="$(${psql[@]} --dbname=rag_upgrade --tuples-only --no-align --quiet --command="SELECT string_agg(column_name || '|' || COALESCE(domain_name,data_type) || '|' || is_nullable || '|' || COALESCE(column_default,'none'), ';' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema='rag' AND table_name='relationships' AND column_name IN ('override_audit_identity','override_reason_code');")"
[[ "$column_contract" == 'override_audit_identity|sha256_hex|YES|none;override_reason_code|text|YES|none' ]] || { printf 'FAIL: override-audit column contract mismatch: %s\n' "$column_contract" >&2; exit 1; }
constraint_contract="$(${psql[@]} --dbname=rag_upgrade --tuples-only --no-align --quiet --command="SELECT regexp_replace(pg_get_constraintdef(oid,true),'[[:space:]]+',' ','g') FROM pg_constraint WHERE conrelid='rag.relationships'::regclass AND conname='relationships_override_audit_check';")"
[[ "$constraint_contract" == *deterministic* && "$constraint_contract" == *operator_override* && "$constraint_contract" == *override_audit_identity* && "$constraint_contract" == *override_reason_code* ]] || { printf 'FAIL: override-audit constraint mismatch.\n' >&2; exit 1; }

insert_relationship() {
  "${psql[@]}" --dbname=rag_upgrade --quiet --command="SET session_replication_role=replica; INSERT INTO rag.relationships (relationship_id,artifact_set_id,relationship_type,source_kind,source_identity,target_kind,target_identity,evidence_citation_id,detection_method,review_status,relationship_definition_version,override_audit_identity,override_reason_code) VALUES ($1); RESET session_replication_role;"
}
insert_relationship "repeat('1',64),repeat('2',64),'references','document',repeat('3',64),'external','deterministic-target',repeat('4',64),'deterministic','accepted','v1',NULL,NULL"
set +e
insert_relationship "repeat('5',64),repeat('2',64),'references','document',repeat('3',64),'external','invalid-deterministic',repeat('4',64),'deterministic','accepted','v1',repeat('6',64),'manual'" >"$work_root/invalid-deterministic.stdout" 2>"$work_root/invalid-deterministic.stderr"
invalid_deterministic_status=$?
insert_relationship "repeat('7',64),repeat('2',64),'references','document',repeat('3',64),'external','invalid-override',repeat('4',64),'operator_override','accepted','v1',NULL,NULL" >"$work_root/invalid-override.stdout" 2>"$work_root/invalid-override.stderr"
invalid_override_status=$?
set -e
[[ "$invalid_deterministic_status" -ne 0 && "$invalid_override_status" -ne 0 ]] || { printf 'FAIL: invalid override-audit shape passed.\n' >&2; exit 1; }
grep -Fq 'relationships_override_audit_check' "$work_root/invalid-deterministic.stderr" || { printf 'FAIL: deterministic constraint rejection mismatch.\n' >&2; exit 1; }
grep -Fq 'relationships_override_audit_check' "$work_root/invalid-override.stderr" || { printf 'FAIL: override constraint rejection mismatch.\n' >&2; exit 1; }
insert_relationship "repeat('8',64),repeat('2',64),'references','document',repeat('3',64),'external','valid-override',repeat('4',64),'operator_override','accepted','v1',repeat('9',64),'operator-confirmed-reference'"

[[ "$(${psql[@]} --dbname=rag_upgrade --tuples-only --no-align --quiet --command='SELECT count(*) FROM rag.relationships;')" == 2 ]] || { printf 'FAIL: accepted relationship-shape count mismatch.\n' >&2; exit 1; }
[[ "$(${psql[@]} --dbname=rag_upgrade --tuples-only --no-align --quiet --command="SELECT count(*) FROM pg_description d JOIN pg_class c ON c.oid=d.objoid JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum=d.objsubid WHERE n.nspname='rag' AND c.relname='relationships' AND a.attname IN ('override_audit_identity','override_reason_code') AND length(d.description)>0;")" == 2 ]] || { printf 'FAIL: override-audit column comments missing.\n' >&2; exit 1; }
privilege_contract="$(${psql[@]} --dbname=rag_upgrade --tuples-only --no-align --quiet --command="SELECT has_table_privilege('rag_retrieval','rag_search.active_relationships','SELECT') || '|' || has_table_privilege('rag_retrieval','rag.relationships','SELECT');")"
[[ "$privilege_contract" == 'true|false' ]] || { printf 'FAIL: retrieval privilege mismatch.\n' >&2; exit 1; }
order_rollback="$(${psql[@]} --dbname=rag_order_guard --tuples-only --no-align --quiet --command="SELECT (SELECT count(*) FROM rag.schema_migrations) || '|' || (SELECT count(*) FROM information_schema.columns WHERE table_schema='rag' AND table_name='relationships' AND column_name LIKE 'override_%');")"
[[ "$order_rollback" == '2|0' ]] || { printf 'FAIL: migration-order rejection did not roll back.\n' >&2; exit 1; }
override_rollback="$(${psql[@]} --dbname=rag_override_guard --tuples-only --no-align --quiet --command="SELECT (SELECT count(*) FROM rag.schema_migrations) || '|' || (SELECT count(*) FROM information_schema.columns WHERE table_schema='rag' AND table_name='relationships' AND column_name LIKE 'override_%');")"
[[ "$override_rollback" == '3|0' ]] || { printf 'FAIL: legacy-override rejection did not roll back.\n' >&2; exit 1; }

"$POSTGRES_BIN/pg_ctl" -D "$data_root" -m fast stop >/dev/null
cluster_started=false
"$POSTGRES_BIN/pg_ctl" -D "$data_root" -l "$log_path" -o "-k $socket_root -p $TEST_PORT -c listen_addresses=''" start >/dev/null
cluster_started=true
restart_contract="$(${psql[@]} --dbname=rag_upgrade --tuples-only --no-align --quiet --command="SELECT count(*) FROM rag.schema_migrations WHERE migration_id='0004_preserve_relationship_override_audit' AND migration_sha256='$SHA_0004' AND schema_version=4;")"
[[ "$restart_contract" == 1 ]] || { printf 'FAIL: migration did not persist across restart.\n' >&2; exit 1; }

printf '%s\n' \
  "migration_0004_sha256=$SHA_0004" \
  'schema_v3_upgrade=pass;wrong_order_rejected=true;legacy_override_rejected=true' \
  'override_audit_columns=audit_identity_reason_code;column_contract=pass;column_comments=2' \
  'relationship_override_constraint=deterministic_null_operator_required;constraint_contract=pass' \
  'retrieval_active_view_read=true;retrieval_base_table_read=false' \
  'restart_persistence=pass' \
  'relationship_override_audit_migration_test=pass'
