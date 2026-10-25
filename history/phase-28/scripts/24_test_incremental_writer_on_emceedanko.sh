#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Prove the incremental writer with native Psycopg and a disposable
#   PostgreSQL database while leaving the accepted application DB untouched.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/24_test_incremental_writer_on_emceedanko.sh --run
#
# The target helper removes the synthetic database and stops PostgreSQL on
# success and failure. It never reads organizational documents or calls AI.

usage() {
  sed -n '3,13p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run                      Explicitly authorize the disposable test.' \
    '  --target VALUE             SSH destination or configured SSH alias.' \
    '  --expected-hostname NAME   Exact target short hostname.' \
    '  --expected-os-version VER  Exact expected Ubuntu major.minor version.' \
    '  --identity-file PATH       Optional explicit SSH private key.' \
    '  --report-root PATH         Absolute local result directory.' \
    '  --validate-only            Validate sources without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly TARGET_HELPER="$SCRIPT_DIR/test-incremental-writer-integration"
readonly TEST_RUNNER="$SCRIPT_DIR/test-incremental-writer-integration.py"
readonly PYTHON_ROOT="$PHASE_ROOT/Ishikawa/application/python/ishikawa"
readonly MIGRATION_0001="$PHASE_ROOT/migrations/0001_initial_rag_catalog.sql"
readonly MIGRATION_0002="$PHASE_ROOT/migrations/0002_align_ingestion_ownership.sql"
readonly ACCEPTED_TARGET_REPORT="$REPO_ROOT/local/reports/native-postgresql-ingestion-ownership-migration/native_postgresql_ingestion_ownership_migration_20261019T203028Z_JRDpdJ.txt"
readonly ACCEPTED_TARGET_REPORT_SHA256='4d5d065a9a941bb11948fdfb24f552b4961602a4b8c9936805e93fe1aa41ffa1'
readonly ACCEPTANCE_RECORD="$PHASE_ROOT/evidence/ishikawa_ingestion_ownership_migration_target_acceptance_2026-10-19.md"
readonly ACCEPTANCE_RECORD_SHA256='521013c39c88bd8f0733ea251aea38925cdb3791612471af06ef0d63baf4aeff'
readonly DEFAULT_REPORT_ROOT="$REPO_ROOT/local/reports/native-postgresql-incremental-writer-integration"

python_sources=(
  "$PYTHON_ROOT/__init__.py"
  "$PYTHON_ROOT/canonical.py"
  "$PYTHON_ROOT/errors.py"
  "$PYTHON_ROOT/models.py"
  "$PYTHON_ROOT/persistence.py"
  "$PYTHON_ROOT/persistence_models.py"
  "$PYTHON_ROOT/planner.py"
  "$PYTHON_ROOT/reasons.py"
  "$PYTHON_ROOT/reporting.py"
  "$PYTHON_ROOT/validators.py"
  "$PYTHON_ROOT/yaml_loader.py"
)

target="${APPLICATION_HOST_TARGET:-DankoSurface_EmceeDanko}"
expected_hostname="${APPLICATION_HOST_EXPECTED_HOSTNAME:-EmceeDanko}"
expected_os_version="${APPLICATION_HOST_EXPECTED_OS_VERSION:-24.04}"
identity_file="${APPLICATION_HOST_IDENTITY_FILE:-}"
report_root="$DEFAULT_REPORT_ROOT"
run_authorized=false
validate_only=false

while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
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
[[ "$report_root" == /* && ! -L "$report_root" ]] || { printf 'BLOCKED: --report-root must be absolute and not a symlink.\n' >&2; exit 2; }
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] || { printf 'BLOCKED: identity file is unsafe.\n' >&2; exit 2; }
fi
for source in "$TARGET_HELPER" "$TEST_RUNNER" "$MIGRATION_0001" "$MIGRATION_0002" "$ACCEPTED_TARGET_REPORT" "$ACCEPTANCE_RECORD" "${python_sources[@]}"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || { printf 'BLOCKED: required Script 24 source is missing or unsafe.\n' >&2; exit 2; }
done
for required in awk bash basename date grep mkdir mktemp rm scp sha256sum ssh tee timeout tr wc; do
  command -v "$required" >/dev/null 2>&1 || { printf 'BLOCKED: missing local command: %s\n' "$required" >&2; exit 2; }
done

bash -n "$TARGET_HELPER"
python3 -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' "$TEST_RUNNER" "${python_sources[@]}"
for neutral_source in "$TARGET_HELPER" "$TEST_RUNNER"; do
  if grep -Eiq 'phase[-_ ]?[0-9]+|(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)|Danko|org[_ -]?lab|Agent|repository' "$neutral_source"; then
    printf 'BLOCKED: development or environment jargon found in a neutral target source.\n' >&2
    exit 2
  fi
done

[[ "$(sha256sum "$ACCEPTED_TARGET_REPORT" | awk '{print $1}')" == "$ACCEPTED_TARGET_REPORT_SHA256" ]] || { printf 'BLOCKED: accepted target receipt checksum mismatch.\n' >&2; exit 2; }
[[ "$(sha256sum "$ACCEPTANCE_RECORD" | awk '{print $1}')" == "$ACCEPTANCE_RECORD_SHA256" ]] || { printf 'BLOCKED: migration acceptance record checksum mismatch.\n' >&2; exit 2; }
for accepted_fact in \
  'remote_execution_exit_code=0;raw_stderr_retained=false' \
  'migration_action=apply;restart_persistence_verification=pass' \
  'schema_count=3;table_count=20;active_search_view_count=5' \
  'migration_metadata_row_count=2;corpus_content_row_count=0' \
  'ingestion_ownership_migration=pass' \
  'required_fact_contract=pass;migration_action_markers=1' \
  'cleanup_remote_temporary_files=removed' \
  'cleanup_ssh_master_exit_code=0'; do
  grep -Fxq "$accepted_fact" "$ACCEPTED_TARGET_REPORT" || { printf 'BLOCKED: required accepted target fact is absent.\n' >&2; exit 2; }
done

work_root="$(mktemp -d /tmp/incremental-writer-script-24.XXXXXX)"
payload_manifest="$work_root/payload.sha256"
: >"$payload_manifest"
for source in "${python_sources[@]}"; do
  printf '%s  payload/ishikawa/%s\n' "$(sha256sum "$source" | awk '{print $1}')" "$(basename "$source")" >>"$payload_manifest"
done
printf '%s  %s\n' "$(sha256sum "$MIGRATION_0001" | awk '{print $1}')" '0001_initial_rag_catalog.sql' >>"$payload_manifest"
printf '%s  %s\n' "$(sha256sum "$MIGRATION_0002" | awk '{print $1}')" '0002_align_ingestion_ownership.sql' >>"$payload_manifest"
printf '%s  %s\n' "$(sha256sum "$TEST_RUNNER" | awk '{print $1}')" 'test-incremental-writer-integration.py' >>"$payload_manifest"
manifest_sha256="$(sha256sum "$payload_manifest" | awk '{print $1}')"
helper_sha256="$(sha256sum "$TARGET_HELPER" | awk '{print $1}')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'incremental_writer_target_integration_source=pass' \
    'target_contact=false;postgresql_connection=false;corpus_mutation=false' \
    "script_sha256=$script_sha256" \
    "helper_sha256=$helper_sha256" \
    "payload_manifest_sha256=$manifest_sha256" \
    "payload_file_count=$(wc -l <"$payload_manifest" | tr -d ' ')" \
    "accepted_target_report_sha256=$ACCEPTED_TARGET_REPORT_SHA256" \
    "acceptance_record_sha256=$ACCEPTANCE_RECORD_SHA256"
  rm -rf -- "$work_root"
  exit 0
fi

[[ "$run_authorized" == true ]] || { rm -rf -- "$work_root"; printf 'BLOCKED: Script 24 requires the explicit --run argument.\n' >&2; exit 2; }

mkdir -p -- "$report_root"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_root/native_postgresql_incremental_writer_integration_${timestamp}_XXXXXX.txt")"
remote_root="/tmp/incremental-writer-integration-$timestamp-$$"
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
  if [[ "$work_root" == /tmp/incremental-writer-script-24.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

emit 'purpose=run_disposable_incremental_writer_target_integration'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;helper_sha256=$helper_sha256;payload_manifest_sha256=$manifest_sha256"
emit "accepted_target_report_sha256=$ACCEPTED_TARGET_REPORT_SHA256;acceptance_record_sha256=$ACCEPTANCE_RECORD_SHA256"
emit 'authorized_actions=stage_verified_synthetic_test_payload_start_postgresql_create_disposable_database_apply_accepted_schema_run_writer_paths_drop_disposable_database_verify_accepted_database_stop_postgresql_remove_temporary_files'
emit 'non_actions=no_package_change_no_accepted_database_mutation_no_organizational_document_read_no_model_call_no_secret_processing_no_service_enablement'
emit "selected_target=$target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version"
emit 'operator_expectation=ssh_key_passphrase_up_to_once;target_sudo_password_may_be_prompted;no_application_secret_prompt'

control_path="$work_root/ssh-control"
ssh_args=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto -o "ControlPath=$control_path" -o ControlPersist=1800)
if [[ -n "$identity_file" ]]; then ssh_args+=(-i "$identity_file" -o IdentitiesOnly=yes); fi

emit 'milestone=authentication;state=waiting_for_operator_if_prompted'
timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$target" >"$work_root/master.stdout" 2>"$work_root/master.stderr" || { emit 'incremental_writer_target_integration_wrapper=blocked;reason=ssh_master_start_failed'; exit 1; }
master_started=true
emit 'milestone=authentication;state=pass'
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root' && mkdir -m 0700 -- '$remote_root/payload' '$remote_root/payload/ishikawa'" \
  >"$work_root/create.stdout" 2>"$work_root/create.stderr" || { emit 'incremental_writer_target_integration_wrapper=blocked;reason=remote_temporary_directory_not_created'; exit 1; }
remote_created=true

timeout --foreground 120 scp "${ssh_args[@]}" "$TARGET_HELPER" "$TEST_RUNNER" "$MIGRATION_0001" "$MIGRATION_0002" "$payload_manifest" "$target:$remote_root/" >"$work_root/scp-root.stdout" 2>"$work_root/scp-root.stderr" || { emit 'incremental_writer_target_integration_wrapper=blocked;reason=root_payload_copy_failed'; exit 1; }
timeout --foreground 120 scp "${ssh_args[@]}" "${python_sources[@]}" "$target:$remote_root/payload/ishikawa/" >"$work_root/scp-python.stdout" 2>"$work_root/scp-python.stderr" || { emit 'incremental_writer_target_integration_wrapper=blocked;reason=python_payload_copy_failed'; exit 1; }
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && printf '%s  %s\n%s  %s\n' '$helper_sha256' test-incremental-writer-integration '$manifest_sha256' payload.sha256 | sha256sum --check --strict -" \
  >"$work_root/hash.stdout" 2>"$work_root/hash.stderr" || { emit 'incremental_writer_target_integration_wrapper=blocked;reason=target_outer_payload_hash_mismatch'; exit 1; }
emit 'milestone=target_payload_verification;state=pass'

emit 'milestone=incremental_writer_integration;state=waiting_for_operator_sudo_if_prompted'
set +e
timeout --foreground 900 ssh -tt "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && sudo -p '[sudo] password for disposable writer integration: ' bash ./test-incremental-writer-integration '$expected_hostname' '$expected_os_version' rag_catalog rag_owner rag_ingest rag_retrieval '$remote_root' '$manifest_sha256' > incremental-writer-integration.txt" \
  < /dev/tty
remote_code=$?
set -e
emit "remote_execution_exit_code=$remote_code;raw_stderr_retained=false"

fetched_result="$work_root/incremental-writer-integration.txt"
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/incremental-writer-integration.txt" "$fetched_result" >"$work_root/fetch.stdout" 2>"$work_root/fetch.stderr" || { emit 'incremental_writer_target_integration_wrapper=blocked;reason=result_fetch_failed'; exit 1; }

output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then output_contract=blocked; continue; fi
  emit "$line"
done <"$fetched_result"
emit "remote_output_contract=$output_contract"

required_fact_contract=pass
for fact in \
  'purpose=test_incremental_writer_with_disposable_native_postgresql' \
  "host=$expected_hostname;os_version=$expected_os_version;architecture=amd64" \
  'postgresql_version=16.15;vector_default_version=0.8.7' \
  'temporary_database_created=true;accepted_schema_applied=true' \
  'synthetic_documents=3;organizational_documents=0' \
  'writer_actions=add_reuse_revise_reprocess_quarantine_remediate_retire' \
  'atomic_failure_rollback=pass' \
  'active_projection=document_1_chunk_1_citation_1_embedding_1' \
  'retrieval_role_active_view_read=pass;retrieval_role_base_table_read=denied' \
  'incremental_writer_postgresql_integration=pass' \
  'temporary_database_dropped=true;accepted_database_unchanged=true' \
  'cluster_status=down;postgresql_port_5432=free;postgresql_service_active=inactive;postgresql_service_enabled=disabled' \
  'incremental_writer_target_integration=pass'; do
  [[ "$(grep -Fxc "$fact" "$fetched_result" || true)" == 1 ]] || required_fact_contract=blocked
done
[[ "$(grep -Ec '^python_version=3\.12\.[0-9]+;psycopg_version=3\.1\.17$' "$fetched_result" || true)" == 1 ]] || required_fact_contract=blocked
pass_markers="$(grep -Fxc 'incremental_writer_target_integration=pass' "$fetched_result" || true)"
blocked_markers="$(grep -Ec '^incremental_writer_target_integration=blocked;' "$fetched_result" || true)"
emit "required_fact_contract=$required_fact_contract;pass_markers=$pass_markers;blocked_markers=$blocked_markers"

if (( remote_code == 0 )) && [[ "$output_contract" == pass && "$required_fact_contract" == pass && "$pass_markers" == 1 && "$blocked_markers" == 0 ]]; then
  emit 'milestone=incremental_writer_integration;state=pass'
  emit "incremental_writer_target_integration_wrapper=pass;local_report=$report_path;next_gate=freeze_fresh_install_schema_and_package_contract"
  exit 0
fi
emit 'milestone=incremental_writer_integration;state=blocked'
emit "incremental_writer_target_integration_wrapper=blocked;local_report=$report_path;next_gate=inspect_integration_result_before_any_retry"
exit 1
