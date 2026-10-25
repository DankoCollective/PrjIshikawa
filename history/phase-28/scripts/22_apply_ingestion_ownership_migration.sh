#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Apply the reviewed ingestion-ownership migration to the existing empty
#   native PostgreSQL application catalog.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/22_apply_ingestion_ownership_migration.sh --migrate
#
# This requires the accepted 0001 database state. It does not ingest content,
# change roles or passwords, install packages, or enable PostgreSQL at boot.

usage() {
  sed -n '3,13p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --migrate                  Explicitly authorize migration 0002.' \
    '  --target VALUE             SSH destination or configured SSH alias.' \
    '  --expected-hostname NAME   Exact target short hostname.' \
    '  --expected-os-version VER  Exact expected Ubuntu major.minor version.' \
    '  --identity-file PATH       Optional explicit SSH private key.' \
    '  --report-root PATH         Absolute local result directory.' \
    '  --validate-only            Validate accepted inputs without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly TARGET_HELPER="$SCRIPT_DIR/apply-ingestion-ownership-migration"
readonly PRIOR_MIGRATION_FILE="$PHASE_ROOT/migrations/0001_initial_rag_catalog.sql"
readonly MIGRATION_FILE="$PHASE_ROOT/migrations/0002_align_ingestion_ownership.sql"
readonly PRIOR_MIGRATION_SHA256='3e2f5e61bd8038bc29764024e21b8bec754fad8a282f89abaf6130e345d6380a'
readonly ACCEPTED_SCHEMA_REPORT="$REPO_ROOT/local/reports/native-postgresql-application-schema-migration/native_postgresql_application_schema_migration_20261019T162250Z_x2Llco.txt"
readonly ACCEPTED_SCHEMA_REPORT_SHA256='e0c29298a70775c69a628c05d2dffbe9821e1b0aab0c9da53e67f015eacfc658'
readonly DEFAULT_REPORT_ROOT="$REPO_ROOT/local/reports/native-postgresql-ingestion-ownership-migration"

target="${APPLICATION_HOST_TARGET:-DankoSurface_EmceeDanko}"
expected_hostname="${APPLICATION_HOST_EXPECTED_HOSTNAME:-EmceeDanko}"
expected_os_version="${APPLICATION_HOST_EXPECTED_OS_VERSION:-24.04}"
database_name="${APPLICATION_DATABASE_NAME:-rag_catalog}"
owner_role="${APPLICATION_DATABASE_OWNER_ROLE:-rag_owner}"
ingest_role="${APPLICATION_DATABASE_INGEST_ROLE:-rag_ingest}"
retrieval_role="${APPLICATION_DATABASE_RETRIEVAL_ROLE:-rag_retrieval}"
identity_file="${APPLICATION_HOST_IDENTITY_FILE:-}"
report_root="$DEFAULT_REPORT_ROOT"
migrate_authorized=false
validate_only=false

while (( $# > 0 )); do
  case "$1" in
    --migrate) migrate_authorized=true; shift ;;
    --target) target="${2:-}"; shift 2 ;;
    --expected-hostname) expected_hostname="${2:-}"; shift 2 ;;
    --expected-os-version) expected_os_version="${2:-}"; shift 2 ;;
    --identity-file) identity_file="${2:-}"; shift 2 ;;
    --report-root) report_root="${2:-}"; shift 2 ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'ERROR: unsupported argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$target" =~ ^[A-Za-z0-9_@.:-]+$ ]] || { printf 'BLOCKED: invalid SSH target or alias.\n' >&2; exit 2; }
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || { printf 'BLOCKED: invalid expected hostname.\n' >&2; exit 2; }
[[ "$expected_os_version" =~ ^[0-9]{2}\.[0-9]{2}$ ]] || { printf 'BLOCKED: invalid expected Ubuntu version.\n' >&2; exit 2; }
[[ "$database_name|$owner_role|$ingest_role|$retrieval_role" == 'rag_catalog|rag_owner|rag_ingest|rag_retrieval' ]] \
  || { printf 'BLOCKED: database identifiers do not match the accepted database.\n' >&2; exit 2; }
[[ "$report_root" == /* && ! -L "$report_root" ]] || { printf 'BLOCKED: --report-root must be absolute and not a symlink.\n' >&2; exit 2; }
for source_file in "$TARGET_HELPER" "$PRIOR_MIGRATION_FILE" "$MIGRATION_FILE" "$ACCEPTED_SCHEMA_REPORT"; do
  [[ -f "$source_file" && ! -L "$source_file" && -r "$source_file" ]] \
    || { printf 'BLOCKED: a required accepted source is missing or unsafe.\n' >&2; exit 2; }
done
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] \
    || { printf 'BLOCKED: explicit identity file is missing, unreadable, non-absolute, or a symlink.\n' >&2; exit 2; }
fi
for required in awk bash date grep mkdir mktemp rm scp sha256sum ssh tee timeout tr wc; do
  command -v "$required" >/dev/null 2>&1 || { printf 'BLOCKED: missing local command: %s\n' "$required" >&2; exit 2; }
done

bash -n "$TARGET_HELPER"
for neutral_source in "$TARGET_HELPER" "$MIGRATION_FILE"; do
  if grep -Eiq 'phase[-_ ]?[0-9]+|(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)|Danko|org[_ -]?lab|Agent|repository' "$neutral_source"; then
    printf 'BLOCKED: development or environment jargon found in a neutral target source.\n' >&2
    exit 2
  fi
done

prior_migration_sha256="$(sha256sum "$PRIOR_MIGRATION_FILE" | awk '{print $1}')"
[[ "$prior_migration_sha256" == "$PRIOR_MIGRATION_SHA256" ]] || { printf 'BLOCKED: accepted 0001 migration checksum mismatch.\n' >&2; exit 2; }
schema_report_sha256="$(sha256sum "$ACCEPTED_SCHEMA_REPORT" | awk '{print $1}')"
[[ "$schema_report_sha256" == "$ACCEPTED_SCHEMA_REPORT_SHA256" ]] || { printf 'BLOCKED: accepted Script 20 report checksum mismatch.\n' >&2; exit 2; }
for accepted_fact in \
  "migration_record=0001_initial_rag_catalog;schema_version=1;migration_sha256=$PRIOR_MIGRATION_SHA256" \
  'schema_count=3;table_count=20;active_search_view_count=5' \
  'retrieval_base_table_select_count=0;retrieval_active_view_select_count=5;retrieval_write_count=0' \
  'ingestion_base_table_select_count=20;ingestion_writable_table_count=19;schema_migration_write=false' \
  'migration_metadata_row_count=1;corpus_content_row_count=0' \
  'cluster_status=down;postgresql_port_5432=free;postgresql_service_active=inactive;postgresql_service_enabled=disabled' \
  'native_application_schema_migration=pass' \
  'cleanup_remote_temporary_files=removed' \
  'cleanup_ssh_master_exit_code=0'; do
  grep -Fxq "$accepted_fact" "$ACCEPTED_SCHEMA_REPORT" || { printf 'BLOCKED: required accepted Script 20 fact is absent.\n' >&2; exit 2; }
done
grep -Fq 'native_postgresql_application_schema_migration_wrapper=pass;' "$ACCEPTED_SCHEMA_REPORT" \
  || { printf 'BLOCKED: accepted Script 20 wrapper pass marker is absent.\n' >&2; exit 2; }

for required_sql_marker in \
  'BEGIN;' \
  "migration_id = '0001_initial_rag_catalog'" \
  'migration 0002 requires an empty 0001 application catalog' \
  'ADD COLUMN assigned_class_id text NOT NULL' \
  'ADD COLUMN manifest_entry_identity rag.sha256_hex NOT NULL' \
  'ADD CONSTRAINT quarantine_records_resolution_v1_check' \
  'das.assigned_class_id AS class_id' \
  "'0002_align_ingestion_ownership'" \
  'COMMIT;'; do
  grep -Fq "$required_sql_marker" "$MIGRATION_FILE" || { printf 'BLOCKED: required 0002 SQL marker is absent.\n' >&2; exit 2; }
done

helper_sha256="$(sha256sum "$TARGET_HELPER" | awk '{print $1}')"
helper_bytes="$(wc -c <"$TARGET_HELPER" | tr -d ' ')"
migration_sha256="$(sha256sum "$MIGRATION_FILE" | awk '{print $1}')"
migration_bytes="$(wc -c <"$MIGRATION_FILE" | tr -d ' ')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'ingestion_ownership_migration_source=pass' \
    'target_contact=false' \
    'migration_executed=false' \
    'migration_id=0002_align_ingestion_ownership' \
    "script_sha256=$script_sha256" \
    "helper_sha256=$helper_sha256" \
    "helper_bytes=$helper_bytes" \
    "migration_sha256=$migration_sha256" \
    "migration_bytes=$migration_bytes" \
    "prior_migration_sha256=$prior_migration_sha256" \
    "accepted_schema_report_sha256=$schema_report_sha256"
  exit 0
fi

[[ "$migrate_authorized" == true ]] || { printf 'BLOCKED: migration 0002 requires the explicit --migrate argument.\n' >&2; exit 2; }

mkdir -p -- "$report_root"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_root/native_postgresql_ingestion_ownership_migration_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/native-postgresql-ingestion-ownership-migration.XXXXXX)"
remote_root="/tmp/ingestion-ownership-migration-$timestamp-$$"
remote_created=false
master_started=false
ssh_args=()

emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
cleanup() {
  local status="$?" cleanup_code=0 close_code=0
  trap - EXIT INT TERM
  set +e
  if [[ "$remote_created" == true && "$master_started" == true ]]; then
    timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "rm -rf -- '$remote_root'" >/dev/null 2>&1 || cleanup_code=$?
    if (( cleanup_code == 0 )); then emit 'cleanup_remote_temporary_files=removed'; else emit "cleanup_remote_temporary_files=review_required;exit_code=$cleanup_code"; status=1; fi
  else
    emit 'cleanup_remote_temporary_files=not_required'
  fi
  if [[ "$master_started" == true ]]; then
    timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1 || close_code=$?
    emit "cleanup_ssh_master_exit_code=$close_code"
    (( close_code == 0 )) || status=1
  fi
  if [[ "$work_root" == /tmp/native-postgresql-ingestion-ownership-migration.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

emit 'purpose=apply_native_postgresql_ingestion_ownership_migration'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;helper_sha256=$helper_sha256;helper_bytes=$helper_bytes"
emit "migration_id=0002_align_ingestion_ownership;migration_sha256=$migration_sha256;migration_bytes=$migration_bytes"
emit "accepted_schema_report_sha256=$schema_report_sha256;prior_migration_sha256=$prior_migration_sha256"
emit 'authorized_actions=stage_verified_temporary_helper_and_sql_start_existing_local_cluster_verify_empty_prior_schema_apply_or_verify_migration_verify_schema_and_privileges_stop_restart_verify_persistence_stop_cluster_retrieve_bounded_result_remove_temporary_files'
emit 'non_actions=no_network_access_no_package_change_no_database_or_role_change_no_document_or_embedding_content_no_vector_ann_index_no_secret_processing_no_service_enablement'
emit "selected_target=$target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version"
emit 'operator_expectation=ssh_key_passphrase_up_to_once;target_sudo_password_may_be_prompted;no_application_secret_prompt'

control_path="$work_root/ssh-control"
ssh_args=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto -o "ControlPath=$control_path" -o ControlPersist=1800)
if [[ -n "$identity_file" ]]; then ssh_args+=(-i "$identity_file" -o IdentitiesOnly=yes); fi

emit 'milestone=authentication;state=waiting_for_operator_if_prompted'
timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$target" >"$work_root/master.stdout" 2>"$work_root/master.stderr" || {
  emit 'native_postgresql_ingestion_ownership_migration_wrapper=blocked;reason=ssh_master_start_failed;raw_stderr_retained=false'; exit 1;
}
master_started=true
emit 'milestone=authentication;state=pass'

timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" >"$work_root/create.stdout" 2>"$work_root/create.stderr" || {
  emit 'native_postgresql_ingestion_ownership_migration_wrapper=blocked;reason=remote_temporary_directory_not_created'; exit 1;
}
remote_created=true
timeout --foreground 120 scp "${ssh_args[@]}" "$TARGET_HELPER" "$MIGRATION_FILE" "$target:$remote_root/" >"$work_root/scp.stdout" 2>"$work_root/scp.stderr" || {
  emit 'native_postgresql_ingestion_ownership_migration_wrapper=blocked;reason=temporary_payload_copy_failed'; exit 1;
}
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && printf '%s  %s\n%s  %s\n' '$helper_sha256' apply-ingestion-ownership-migration '$migration_sha256' 0002_align_ingestion_ownership.sql | sha256sum --check --strict -" \
  >"$work_root/hash.stdout" 2>"$work_root/hash.stderr" || {
    emit 'native_postgresql_ingestion_ownership_migration_wrapper=blocked;reason=target_payload_hash_mismatch'; exit 1;
  }
emit 'milestone=target_payload_verification;state=pass'

emit 'milestone=ingestion_ownership_migration;state=waiting_for_operator_sudo_if_prompted'
set +e
timeout --foreground 900 ssh -tt "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && sudo -p '[sudo] password for ingestion ownership migration: ' bash ./apply-ingestion-ownership-migration '$expected_hostname' '$expected_os_version' '$database_name' '$owner_role' '$ingest_role' '$retrieval_role' '$remote_root/0002_align_ingestion_ownership.sql' '$migration_sha256' '$prior_migration_sha256' > ingestion-ownership-migration.txt" \
  < /dev/tty
remote_code=$?
set -e
emit "remote_execution_exit_code=$remote_code;raw_stderr_retained=false"

fetched_result="$work_root/ingestion-ownership-migration.txt"
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/ingestion-ownership-migration.txt" "$fetched_result" >"$work_root/fetch.stdout" 2>"$work_root/fetch.stderr" || {
  emit 'native_postgresql_ingestion_ownership_migration_wrapper=blocked;reason=result_fetch_failed'; exit 1;
}

output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then
    output_contract=blocked
    continue
  fi
  emit "$line"
done <"$fetched_result"
emit "remote_output_contract=$output_contract"

pass_markers="$(grep -Fxc 'ingestion_ownership_migration=pass' "$fetched_result" || true)"
blocked_markers="$(grep -Ec '^ingestion_ownership_migration=blocked;' "$fetched_result" || true)"
required_fact_contract=pass
for required_fact in \
  'purpose=apply_ingestion_ownership_migration' \
  "host=$expected_hostname;os_version=$expected_os_version;architecture=amd64" \
  'postgresql_version=16.15;vector_default_version=0.8.7' \
  "migration_id=0002_align_ingestion_ownership;migration_sha256=$migration_sha256;migration_bytes=$migration_bytes" \
  "required_prior_migration=0001_initial_rag_catalog;required_prior_migration_sha256=$prior_migration_sha256" \
  'cluster_start=pass;readiness=pass;listener_address=127.0.0.1;listener_port=5432' \
  "prior_migration_record=0001_initial_rag_catalog;schema_version=1;migration_sha256=$prior_migration_sha256" \
  "migration_record=0002_align_ingestion_ownership;schema_version=2;migration_sha256=$migration_sha256" \
  'schema_count=3;table_count=20;active_search_view_count=5' \
  'document_class_owner=artifact_set;source_revision_reclassification=true' \
  'legacy_ownership_column_count=0;new_ownership_column_count=9;digest_domain_column_count=2' \
  'quarantine_retry_contract=manifest_identity_and_successful_retry_linkage' \
  'retrieval_base_table_select_count=0;retrieval_active_view_select_count=5;retrieval_write_count=0' \
  'ingestion_base_table_select_count=20;ingestion_writable_table_count=19;schema_migration_write=false' \
  'migration_metadata_row_count=2;corpus_content_row_count=0' \
  'cluster_status=down;postgresql_port_5432=free;postgresql_service_active=inactive;postgresql_service_enabled=disabled' \
  'ingestion_ownership_migration=pass'; do
  [[ "$(grep -Fxc "$required_fact" "$fetched_result" || true)" == 1 ]] || required_fact_contract=blocked
done
migration_action_count="$(grep -Ec '^migration_action=(apply|verify_existing);restart_persistence_verification=pass$' "$fetched_result" || true)"
[[ "$migration_action_count" == 1 ]] || required_fact_contract=blocked
emit "migration_pass_markers=$pass_markers;migration_blocked_markers=$blocked_markers"
emit "required_fact_contract=$required_fact_contract;migration_action_markers=$migration_action_count"

if (( remote_code == 0 )) && [[ "$output_contract" == pass && "$required_fact_contract" == pass && "$pass_markers" == 1 && "$blocked_markers" == 0 ]]; then
  emit 'milestone=ingestion_ownership_migration;state=pass'
  emit "native_postgresql_ingestion_ownership_migration_wrapper=pass;local_report=$report_path;next_gate=implement_incremental_ingestion_writer"
  exit 0
fi

emit 'milestone=ingestion_ownership_migration;state=blocked'
emit "native_postgresql_ingestion_ownership_migration_wrapper=blocked;local_report=$report_path;next_gate=inspect_migration_result_before_any_retry"
exit 1
