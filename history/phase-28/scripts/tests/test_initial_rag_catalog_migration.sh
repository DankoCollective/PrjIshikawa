#!/usr/bin/env bash
set -Eeuo pipefail

# Local disposable PostgreSQL proof for migration 0001. This test never
# contacts a target and removes its temporary cluster on every exit path.

readonly TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$TEST_DIR/../.." && pwd -P)"
readonly MIGRATION_PATH="$PHASE_ROOT/migrations/0001_initial_rag_catalog.sql"
readonly MIGRATION_SHA256="$(sha256sum "$MIGRATION_PATH" | awk '{print $1}')"
readonly POSTGRES_BIN=/usr/lib/postgresql/16/bin

for required in awk grep mkdir mktemp rm sed sha256sum; do
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
[[ -f "$MIGRATION_PATH" && ! -L "$MIGRATION_PATH" ]] || {
  printf 'BLOCKED: migration is missing or unsafe.\n' >&2
  exit 2
}

work_root="$(mktemp -d /tmp/rag-schema-integrity.XXXXXX)"
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
  if [[ "$work_root" == /tmp/rag-schema-integrity.* && -d "$work_root" ]]; then
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
  -o "-k $socket_root -p 55439 -c listen_addresses=''" start >/dev/null
cluster_started=true

psql=(
  "$POSTGRES_BIN/psql"
  --no-psqlrc
  --set=ON_ERROR_STOP=1
  --host="$socket_root"
  --port=55439
)

"${psql[@]}" --dbname=postgres --quiet <<'SQL'
CREATE ROLE rag_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
CREATE ROLE rag_ingest LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOREPLICATION NOBYPASSRLS;
CREATE ROLE rag_retrieval LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOREPLICATION NOBYPASSRLS;
CREATE DATABASE rag_catalog WITH OWNER rag_owner ENCODING 'UTF8' TEMPLATE template0;
REVOKE ALL ON DATABASE rag_catalog FROM PUBLIC;
GRANT CONNECT ON DATABASE rag_catalog TO rag_ingest, rag_retrieval;
ALTER ROLE rag_retrieval IN DATABASE rag_catalog SET default_transaction_read_only = on;
SQL

"${psql[@]}" --dbname=rag_catalog --quiet <<'SQL'
CREATE EXTENSION vector;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
SQL

"${psql[@]}" --dbname=rag_catalog --quiet \
  --set=owner_role=rag_owner \
  --set=ingest_role=rag_ingest \
  --set=retrieval_role=rag_retrieval \
  --set=migration_sha256="$MIGRATION_SHA256" \
  <"$MIGRATION_PATH"

"${psql[@]}" --dbname=rag_catalog --quiet <<'SQL'
INSERT INTO rag.document_classes (class_id, display_name, registry_version, status)
VALUES ('policy','Policy','1','active'), ('regulation','Regulation','1','active');
INSERT INTO rag.documents (document_id, document_key, class_id, display_name, catalog_version, status)
VALUES
  (repeat('a',64),'doc-one','policy','Document One','1','active'),
  (repeat('b',64),'doc-two','policy','Document Two','1','active');
INSERT INTO rag.ingestion_runs (ingestion_run_id, ingestion_manifest_digest, schema_version, method_profile_id, state, started_at, finished_at)
VALUES (repeat('c',64),repeat('d',64),1,repeat('1',64),'succeeded',clock_timestamp(),clock_timestamp());
INSERT INTO rag.document_versions (document_version_id, document_id, source_digest, assigned_class_id, class_registry_version, ingestion_manifest_digest, source_format, page_count, created_by_run_id)
VALUES
  (repeat('e',64),repeat('a',64),repeat('0',64),'regulation','1',repeat('d',64),'application/pdf',1,repeat('c',64)),
  (repeat('f',64),repeat('b',64),repeat('9',64),'policy','1',repeat('d',64),'application/pdf',1,repeat('c',64));
INSERT INTO rag.document_artifact_sets (artifact_set_id, document_version_id, document_id, method_profile_id, ingestion_run_id, processing_profiles, state, validation_digest)
VALUES
  (repeat('2',64),repeat('e',64),repeat('a',64),repeat('1',64),repeat('c',64),'[]','validated',repeat('a',64)),
  (repeat('3',64),repeat('f',64),repeat('b',64),repeat('1',64),repeat('c',64),'[]','validated',repeat('b',64));
INSERT INTO rag.structural_units (structural_unit_id, artifact_set_id, structural_kind, ordinal, page_start, page_end, structural_path, source_anchor, normalized_text, normalized_digest)
VALUES
  (repeat('4',64),repeat('2',64),'section',0,1,1,'[]','{}','One',repeat('4',64)),
  (repeat('5',64),repeat('3',64),'section',0,1,1,'[]','{}','Two',repeat('5',64));
INSERT INTO rag.chunks (chunk_id, artifact_set_id, method_profile_id, projection_kind, ordinal, retrieval_text, retrieval_text_digest, contextual_fields, content_token_count, context_token_count, prefix_token_count, total_embedding_token_count, processing_profile, lexical_search_config, lexical_vector)
VALUES
  (repeat('6',64),repeat('2',64),repeat('1',64),'narrative',0,'One',repeat('6',64),'{}',1,0,0,1,'default','english',to_tsvector('english','One')),
  (repeat('7',64),repeat('3',64),repeat('1',64),'narrative',0,'Two',repeat('7',64),'{}',1,0,0,1,'default','english',to_tsvector('english','Two'));
INSERT INTO rag.citation_anchors (citation_id, chunk_id, artifact_set_id, document_version_id, display_label, relevant_excerpt, page_start, page_end, structural_path, citation_anchor)
VALUES (repeat('8',64),repeat('6',64),repeat('2',64),repeat('e',64),'Source 1','One',1,1,'[]','{}');
INSERT INTO rag.relationship_types (relationship_type, source_kind, target_kind, influences_retrieval, registry_version, status)
VALUES ('references','document','external',false,'1','active');
INSERT INTO rag.publication_batches (publication_batch_id, ingestion_run_id, state, validation_digest, validated_at, published_at)
VALUES (repeat('9',64),repeat('c',64),'published',repeat('8',64),clock_timestamp(),clock_timestamp());
INSERT INTO rag.active_document_versions (document_id, document_version_id, artifact_set_id, publication_batch_id)
VALUES (repeat('a',64),repeat('e',64),repeat('2',64),repeat('9',64));
SQL

expect_foreign_key_failure() {
  local label="$1" sql="$2" error_path status
  error_path="$work_root/$label.err"
  set +e
  "${psql[@]}" --dbname=rag_catalog --quiet --command="$sql" \
    >/dev/null 2>"$error_path"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || {
    printf 'FAIL: %s unexpectedly succeeded.\n' "$label" >&2
    exit 1
  }
  grep -Fq 'violates foreign key constraint' "$error_path" || {
    printf 'FAIL: %s did not fail through a foreign key.\n' "$label" >&2
    exit 1
  }
  printf '%s=pass\n' "$label"
}

expect_foreign_key_failure cross_artifact_parent \
  "INSERT INTO rag.structural_units (structural_unit_id,artifact_set_id,parent_unit_id,structural_kind,ordinal,page_start,page_end,structural_path,source_anchor,normalized_text,normalized_digest) VALUES (repeat('0',64),repeat('2',64),repeat('5',64),'paragraph',1,1,1,'[]','{}','bad',repeat('0',64));"
expect_foreign_key_failure cross_artifact_chunk_mapping \
  "INSERT INTO rag.chunk_structural_units (chunk_id,structural_unit_id,artifact_set_id,unit_ordinal) VALUES (repeat('6',64),repeat('5',64),repeat('2',64),0);"
expect_foreign_key_failure cross_version_citation \
  "INSERT INTO rag.citation_anchors (citation_id,chunk_id,artifact_set_id,document_version_id,display_label,relevant_excerpt,page_start,page_end,structural_path,citation_anchor) VALUES (repeat('0',64),repeat('6',64),repeat('2',64),repeat('f',64),'bad','bad',1,1,'[]','{}');"
expect_foreign_key_failure cross_artifact_relationship_evidence \
  "INSERT INTO rag.relationships (relationship_id,artifact_set_id,relationship_type,source_kind,source_identity,target_kind,target_identity,evidence_citation_id,detection_method,review_status,relationship_definition_version) VALUES (repeat('0',64),repeat('3',64),'references','document',repeat('b',64),'external','outside',repeat('8',64),'deterministic','external','1');"
expect_foreign_key_failure relationship_kind_mismatch \
  "INSERT INTO rag.relationships (relationship_id,artifact_set_id,relationship_type,source_kind,source_identity,target_kind,target_identity,evidence_citation_id,detection_method,review_status,relationship_definition_version) VALUES (repeat('0',64),repeat('2',64),'references','document',repeat('a',64),'document',repeat('b',64),repeat('8',64),'deterministic','accepted','1');"
expect_foreign_key_failure cross_document_publication_change \
  "INSERT INTO rag.publication_batch_changes (publication_batch_id,document_id,change_kind,resulting_artifact_set_id) VALUES (repeat('9',64),repeat('a',64),'add',repeat('3',64));"

active_class="$("${psql[@]}" --dbname=rag_catalog --tuples-only --no-align \
  --command="SELECT class_id FROM rag_search.active_documents WHERE document_key='doc-one';")"
[[ "$active_class" == regulation ]] || {
  printf 'FAIL: active view did not use the active document version class.\n' >&2
  exit 1
}

contract_query="SELECT
  (SELECT count(*) FROM pg_namespace WHERE nspname IN ('rag','rag_private','rag_search')) || '|' ||
  (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('rag','rag_private') AND c.relkind='r') || '|' ||
  (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='rag_search' AND c.relkind='v') || '|' ||
  (SELECT count(*) FROM rag.schema_migrations WHERE migration_id='0001_initial_rag_catalog' AND migration_sha256='$MIGRATION_SHA256' AND schema_version=1) || '|' ||
  (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('rag','rag_private') AND c.relkind='r' AND has_table_privilege('rag_retrieval',c.oid,'SELECT')) || '|' ||
  (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='rag_search' AND c.relkind='v' AND has_table_privilege('rag_retrieval',c.oid,'SELECT')) || '|' ||
  (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('rag','rag_private') AND c.relkind='r' AND has_table_privilege('rag_ingest',c.oid,'INSERT') AND has_table_privilege('rag_ingest',c.oid,'UPDATE') AND has_table_privilege('rag_ingest',c.oid,'DELETE'));"

initial_contract="$("${psql[@]}" --dbname=rag_catalog --tuples-only --no-align \
  --command="$contract_query")"
[[ "$initial_contract" == '3|20|5|1|0|5|19' ]] || {
  printf 'FAIL: initial schema contract mismatch: %s\n' "$initial_contract" >&2
  exit 1
}

"${psql[@]}" --dbname=rag_catalog --username=rag_retrieval --quiet \
  --command='SELECT count(*) FROM rag_search.active_chunks;' >/dev/null
set +e
"${psql[@]}" --dbname=rag_catalog --username=rag_retrieval --quiet \
  --command='SELECT count(*) FROM rag.chunks;' \
  >/dev/null 2>"$work_root/retrieval-denial.err"
retrieval_status=$?
set -e
[[ "$retrieval_status" -ne 0 ]]
grep -Fq 'permission denied' "$work_root/retrieval-denial.err"

"$POSTGRES_BIN/pg_ctl" -D "$data_root" -m fast stop >/dev/null
cluster_started=false
"$POSTGRES_BIN/pg_ctl" -D "$data_root" -l "$log_path" \
  -o "-k $socket_root -p 55439 -c listen_addresses=''" start >/dev/null
cluster_started=true

restart_contract="$("${psql[@]}" --dbname=rag_catalog --tuples-only --no-align \
  --command="$contract_query")"
[[ "$restart_contract" == '3|20|5|1|0|5|19' ]] || {
  printf 'FAIL: post-restart schema contract mismatch: %s\n' "$restart_contract" >&2
  exit 1
}

ledger_relation="$("${psql[@]}" --dbname=rag_catalog --tuples-only --no-align \
  --command="SELECT COALESCE(to_regclass('rag.schema_migrations')::text, 'absent');")"
ledger_contract="$("${psql[@]}" --dbname=rag_catalog --tuples-only --no-align \
  --command="SELECT migration_id || '|' || migration_sha256 || '|' || schema_version FROM rag.schema_migrations;")"
[[ "$ledger_relation" == rag.schema_migrations ]]
[[ "$ledger_contract" == "0001_initial_rag_catalog|$MIGRATION_SHA256|1" ]]

printf '%s\n' \
  "migration_sha256=$MIGRATION_SHA256" \
  "initial_contract=$initial_contract" \
  "restart_contract=$restart_contract" \
  "active_version_class=$active_class" \
  'retrieval_base_table_denied=true' \
  'exact_already_applied_detection=pass' \
  'initial_rag_catalog_migration_test=pass'
