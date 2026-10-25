#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Apply the reviewed relationship override-audit migration to the empty
#   native PostgreSQL application catalog on EmceeDanko.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/41_apply_relationship_override_audit_migration.sh --migrate

usage() {
  sed -n '3,9p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --migrate                  Explicitly authorize migration 0004.' \
    '  --target VALUE             SSH destination or configured SSH alias.' \
    '  --expected-hostname NAME   Exact target short hostname.' \
    '  --expected-os-version VER  Exact expected Ubuntu major.minor version.' \
    '  --identity-file PATH       Optional explicit SSH private key.' \
    '  --report-root PATH         Absolute local result directory.' \
    '  --validate-only            Validate all inputs without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly TARGET_HELPER="$SCRIPT_DIR/apply-relationship-override-audit-migration"
readonly LOCAL_MIGRATION_TEST="$SCRIPT_DIR/tests/test_relationship_override_audit_migration.sh"
readonly BASE_TEST_RUNNER="$PHASE_ROOT/Ishikawa/scripts/run-local-validation-tests.sh"
readonly MIGRATION_0001="$PHASE_ROOT/migrations/0001_initial_rag_catalog.sql"
readonly MIGRATION_0002="$PHASE_ROOT/migrations/0002_align_ingestion_ownership.sql"
readonly MIGRATION_0003="$PHASE_ROOT/migrations/0003_separate_special_token_count.sql"
readonly MIGRATION_0004="$PHASE_ROOT/migrations/0004_preserve_relationship_override_audit.sql"
readonly SHA_0001='3e2f5e61bd8038bc29764024e21b8bec754fad8a282f89abaf6130e345d6380a'
readonly SHA_0002='74b08adb8aac9828ac076744fedfd22619751326c911bf17f1fa8690e01345e4'
readonly SHA_0003='5e833d8ff556c0e6158daf0419b1013235a11e1a94f1f560206ba813e1fc3761'
readonly SHA_0004='5764f6e12a74b18747163c61ef3f314e8dff140a3586b298c62be616a1dc185f'
readonly ACCEPTED_RELATIONSHIP_REPORT="$REPO_ROOT/local/reports/ishikawa-relationship-persistence-integration/relationship_persistence_integration_20261020T013440Z_8UJmz0.txt"
readonly ACCEPTED_RELATIONSHIP_REPORT_SHA256='437344403fec686984160e707f35973eee4d4a22674988f250c8c2b2955ae7d1'
readonly DEFAULT_REPORT_ROOT="$REPO_ROOT/local/reports/native-postgresql-relationship-override-audit-migration"

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

[[ "$migrate_authorized" != "$validate_only" ]] || { printf 'BLOCKED: choose exactly one of --migrate or --validate-only.\n' >&2; exit 2; }
[[ "$target" =~ ^[A-Za-z0-9_@.:-]+$ ]] || { printf 'BLOCKED: invalid SSH target or alias.\n' >&2; exit 2; }
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || { printf 'BLOCKED: invalid expected hostname.\n' >&2; exit 2; }
[[ "$expected_os_version" =~ ^[0-9]{2}\.[0-9]{2}$ ]] || { printf 'BLOCKED: invalid expected Ubuntu version.\n' >&2; exit 2; }
[[ "$database_name|$owner_role|$ingest_role|$retrieval_role" == 'rag_catalog|rag_owner|rag_ingest|rag_retrieval' ]] || { printf 'BLOCKED: database identifiers do not match the accepted database.\n' >&2; exit 2; }
[[ "$report_root" == /* && ! -L "$report_root" ]] || { printf 'BLOCKED: report root must be absolute and not a symlink.\n' >&2; exit 2; }
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] || { printf 'BLOCKED: identity file is unsafe.\n' >&2; exit 2; }
fi
for required in awk bash cat date grep mkdir mktemp rm scp sed sha256sum ssh tee timeout tr wc; do
  command -v "$required" >/dev/null 2>&1 || { printf 'BLOCKED: missing local command: %s\n' "$required" >&2; exit 2; }
done
for source in "$TARGET_HELPER" "$LOCAL_MIGRATION_TEST" "$BASE_TEST_RUNNER" "$MIGRATION_0001" "$MIGRATION_0002" "$MIGRATION_0003" "$MIGRATION_0004" "$ACCEPTED_RELATIONSHIP_REPORT"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || { printf 'BLOCKED: a required migration input is missing or unsafe.\n' >&2; exit 2; }
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || { printf 'BLOCKED: %s checksum mismatch.\n' "$3" >&2; exit 2; }
}
check_sha256 "$MIGRATION_0001" "$SHA_0001" 'migration 0001'
check_sha256 "$MIGRATION_0002" "$SHA_0002" 'migration 0002'
check_sha256 "$MIGRATION_0003" "$SHA_0003" 'migration 0003'
check_sha256 "$MIGRATION_0004" "$SHA_0004" 'migration 0004'
check_sha256 "$ACCEPTED_RELATIONSHIP_REPORT" "$ACCEPTED_RELATIONSHIP_REPORT_SHA256" 'accepted relationship-persistence report'
for fact in \
  'relationship_persistence_target_integration=pass' \
  'temporary_database_dropped=true;accepted_database_unchanged=true' \
  'override_audit_columns=present;deterministic_rows_with_override_data=0' \
  'required_fact_contract=pass;pass_markers=1;blocked_markers=0' \
  'cleanup_remote_temporary_files=removed' \
  'cleanup_ssh_master_exit_code=0'; do
  grep -Fxq "$fact" "$ACCEPTED_RELATIONSHIP_REPORT" || { printf 'BLOCKED: required accepted relationship-persistence fact is absent.\n' >&2; exit 2; }
done
for marker in \
  'migration 0004 requires the accepted 0001 through 0003 migrations' \
  'migration 0004 cannot invent audit provenance for existing operator overrides' \
  'ADD COLUMN override_audit_identity rag.sha256_hex' \
  'ADD COLUMN override_reason_code text' \
  'relationships_override_audit_check' \
  "'0004_preserve_relationship_override_audit'" \
  'COMMIT;'; do
  grep -Fq "$marker" "$MIGRATION_0004" || { printf 'BLOCKED: required migration SQL marker is absent.\n' >&2; exit 2; }
done
bash -n "$TARGET_HELPER" "$LOCAL_MIGRATION_TEST" "$BASE_TEST_RUNNER"
for neutral_source in "$TARGET_HELPER" "$MIGRATION_0004"; do
  if grep -Eiq 'phase[-_ ]?[0-9]+|(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)|Danko|org[_ -]?lab|Agent|repository' "$neutral_source"; then
    printf 'BLOCKED: development or environment jargon found in a neutral target source.\n' >&2
    exit 2
  fi
done

work_root="$(mktemp -d /tmp/ishikawa-script-41.XXXXXX)"
report_path=''
remote_root=''
remote_created=false
master_started=false
ssh_args=()
emit() { if [[ -n "$report_path" ]]; then printf '%s\n' "$1" | tee -a "$report_path"; else printf '%s\n' "$1"; fi; }
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
  if [[ "$work_root" == /tmp/ishikawa-script-41.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

base_result="$work_root/base-tests.txt"
bash "$BASE_TEST_RUNNER" >"$base_result" 2>&1 || { cat "$base_result" >&2; printf 'script_41_relationship_override_audit_migration=blocked;reason=base_regression\n' >&2; exit 1; }
grep -Fq 'Ran 106 tests' "$base_result" || { printf 'script_41_relationship_override_audit_migration=blocked;reason=base_test_count_mismatch\n' >&2; exit 1; }
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$base_result" || { printf 'script_41_relationship_override_audit_migration=blocked;reason=base_pass_marker_absent\n' >&2; exit 1; }
migration_test_result="$work_root/migration-tests.txt"
bash "$LOCAL_MIGRATION_TEST" >"$migration_test_result" 2>&1 || { cat "$migration_test_result" >&2; printf 'script_41_relationship_override_audit_migration=blocked;reason=migration_regression\n' >&2; exit 1; }
grep -Fxq 'relationship_override_audit_migration_test=pass' "$migration_test_result" || { printf 'script_41_relationship_override_audit_migration=blocked;reason=migration_pass_marker_absent\n' >&2; exit 1; }

helper_sha256="$(sha256sum "$TARGET_HELPER" | awk '{print $1}')"
helper_bytes="$(wc -c <"$TARGET_HELPER" | tr -d ' ')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_relationship_override_audit_migration_source' \
    'target_contact=false;migration_executed=false' \
    "script_sha256=$script_sha256;helper_sha256=$helper_sha256;helper_bytes=$helper_bytes" \
    "migration_0004_sha256=$SHA_0004;accepted_relationship_report_sha256=$ACCEPTED_RELATIONSHIP_REPORT_SHA256" \
    'base_tests=106;migration_tests=pass;failures=0;errors=0' \
    'script_41_relationship_override_audit_migration_source=pass'
  exit 0
fi

mkdir -p -- "$report_root"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_root/relationship_override_audit_migration_${timestamp}_XXXXXX.txt")"
remote_root="/tmp/relationship-override-audit-migration-$timestamp-$$"
emit 'purpose=apply_native_postgresql_relationship_override_audit_migration'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;helper_sha256=$helper_sha256;helper_bytes=$helper_bytes"
emit "migration_id=0004_preserve_relationship_override_audit;migration_sha256=$SHA_0004"
emit "accepted_relationship_report_sha256=$ACCEPTED_RELATIONSHIP_REPORT_SHA256"
emit 'authorized_actions=stage_verified_helper_and_sql_start_existing_local_cluster_verify_empty_prior_schema_apply_or_verify_migration_verify_schema_permissions_and_restart_persistence_stop_cluster_retrieve_bounded_result_remove_temporary_files'
emit 'non_actions=no_package_change_no_database_or_role_change_no_document_or_embedding_content_no_secret_processing_no_service_enablement'
emit "selected_target=$target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version"
emit 'operator_expectation=ssh_key_passphrase_up_to_once;target_sudo_password_may_be_prompted;no_application_secret_prompt'

control_path="$work_root/ssh-control"
ssh_args=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto -o "ControlPath=$control_path" -o ControlPersist=1800)
if [[ -n "$identity_file" ]]; then ssh_args+=(-i "$identity_file" -o IdentitiesOnly=yes); fi
emit 'milestone=authentication;state=waiting_for_operator_if_prompted'
timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$target" >"$work_root/master.stdout" 2>"$work_root/master.stderr" || { emit 'script_41_relationship_override_audit_migration=blocked;reason=ssh_master_start_failed'; exit 1; }
master_started=true
emit 'milestone=authentication;state=pass'
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" >"$work_root/create.stdout" 2>"$work_root/create.stderr" || { emit 'script_41_relationship_override_audit_migration=blocked;reason=remote_temporary_directory_not_created'; exit 1; }
remote_created=true
timeout --foreground 120 scp "${ssh_args[@]}" "$TARGET_HELPER" "$MIGRATION_0004" "$target:$remote_root/" >"$work_root/scp.stdout" 2>"$work_root/scp.stderr" || { emit 'script_41_relationship_override_audit_migration=blocked;reason=temporary_payload_copy_failed'; exit 1; }
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "cd '$remote_root' && printf '%s  %s\n%s  %s\n' '$helper_sha256' apply-relationship-override-audit-migration '$SHA_0004' 0004_preserve_relationship_override_audit.sql | sha256sum --check --strict -" >"$work_root/hash.stdout" 2>"$work_root/hash.stderr" || { emit 'script_41_relationship_override_audit_migration=blocked;reason=target_payload_hash_mismatch'; exit 1; }
emit 'milestone=target_payload_verification;state=pass'

emit 'milestone=relationship_override_audit_migration;state=waiting_for_operator_sudo_if_prompted'
set +e
timeout --foreground 900 ssh -tt "${ssh_args[@]}" -o BatchMode=yes "$target" "cd '$remote_root' && sudo -p '[sudo] password for relationship-audit migration: ' bash ./apply-relationship-override-audit-migration '$expected_hostname' '$expected_os_version' '$database_name' '$owner_role' '$ingest_role' '$retrieval_role' '$remote_root/0004_preserve_relationship_override_audit.sql' '$SHA_0004' '$SHA_0001' '$SHA_0002' '$SHA_0003' > relationship-override-audit-migration.txt" < /dev/tty
remote_code=$?
set -e
emit "remote_execution_exit_code=$remote_code;raw_stderr_retained=false"
fetched_result="$work_root/relationship-override-audit-migration.txt"
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/relationship-override-audit-migration.txt" "$fetched_result" >"$work_root/fetch.stdout" 2>"$work_root/fetch.stderr" || { emit 'script_41_relationship_override_audit_migration=blocked;reason=result_fetch_failed'; exit 1; }

output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then output_contract=blocked; continue; fi
  emit "$line"
done <"$fetched_result"
emit "remote_output_contract=$output_contract"
required_fact_contract=pass
for fact in \
  'purpose=apply_relationship_override_audit_migration' \
  "host=$expected_hostname;os_version=$expected_os_version;architecture=amd64" \
  'postgresql_version=16.15;vector_default_version=0.8.7' \
  "migration_id=0004_preserve_relationship_override_audit;migration_sha256=$SHA_0004;migration_bytes=$(wc -c <"$MIGRATION_0004" | tr -d ' ')" \
  "migration_record=0004_preserve_relationship_override_audit;schema_version=4;migration_sha256=$SHA_0004" \
  'override_audit_columns=audit_identity_reason_code;column_contract=pass;column_comments=2' \
  'relationship_override_constraint=deterministic_null_operator_required;constraint_contract=pass' \
  'retrieval_active_view_read=true;retrieval_base_table_read=false' \
  'migration_metadata_row_count=4;corpus_content_row_count=0' \
  'cluster_status=down;postgresql_port_5432=free;postgresql_service_active=inactive;postgresql_service_enabled=disabled' \
  'relationship_override_audit_migration=pass'; do
  [[ "$(grep -Fxc "$fact" "$fetched_result" || true)" == 1 ]] || required_fact_contract=blocked
done
[[ "$(grep -Ec '^prior_migration_count=3;migration_action=(apply|verify_existing);restart_persistence=pass$' "$fetched_result" || true)" == 1 ]] || required_fact_contract=blocked
pass_markers="$(grep -Fxc 'relationship_override_audit_migration=pass' "$fetched_result" || true)"
blocked_markers="$(grep -Ec '^relationship_override_audit_migration=blocked;' "$fetched_result" || true)"
emit "required_fact_contract=$required_fact_contract;pass_markers=$pass_markers;blocked_markers=$blocked_markers"
if (( remote_code == 0 )) && [[ "$output_contract" == pass && "$required_fact_contract" == pass && "$pass_markers" == 1 && "$blocked_markers" == 0 ]]; then
  emit 'milestone=relationship_override_audit_migration;state=pass'
  emit "script_41_relationship_override_audit_migration=pass;local_report=$report_path;next_gate=implement_procedure_reconstruction"
  exit 0
fi
emit 'milestone=relationship_override_audit_migration;state=blocked'
emit "script_41_relationship_override_audit_migration=blocked;local_report=$report_path;next_gate=inspect_migration_result_before_any_retry"
exit 1
