#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the accepted final-state Ishikawa database schema package in a
#   disposable native PostgreSQL database on EmceeDanko.
#
# Mental model:
#   Requalify the closed archive locally, open one reusable SSH connection,
#   transfer the archive and neutral verifier, execute the packaged installer
#   under bounded sudo, fetch content-free evidence, and remove transfer files.
#
# Inputs or prerequisites:
#   The accepted Script 90 archive and receipts, current coding standard,
#   strict SSH trust, and the accepted EmceeDanko PostgreSQL host posture.
#
# Outputs:
#   Local content-free qualification evidence. The accepted database remains
#   unchanged; the disposable database and target transfer files are removed.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/91_qualify_database_schema_package_on_emceedanko.sh --run

usage() {
  sed -n '3,22p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run                      Execute the disposable target qualification.' \
    '  --target VALUE             SSH destination or configured SSH alias.' \
    '  --expected-hostname NAME   Exact target short hostname.' \
    '  --expected-os-version VER  Exact expected Ubuntu major.minor version.' \
    '  --identity-file PATH       Optional explicit SSH private key.' \
    '  --validate-only            Validate sources without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly TARGET_HELPER="$SCRIPT_DIR/qualify-database-schema-package"
readonly CODING_STANDARD="$REPO_ROOT/CODING_STANDARD.md"
readonly CODING_STANDARD_EVALUATOR="$SCRIPT_DIR/evaluate_consolidated_build_coding_standard.py"
readonly ACCEPTED_REPORT="$REPO_ROOT/local/reports/ishikawa-database-schema-package/database_schema_package_20261020T234525Z_a5oixA.txt"
readonly ACCEPTED_ARCHIVE="$REPO_ROOT/local/artifacts/ishikawa/database-schema-package/ishikawa-database-schema-package-0402fdff8f886129.tar.gz"
readonly ACCEPTED_ARCHIVE_CHECKSUM="$ACCEPTED_ARCHIVE.sha256"
readonly ACCEPTED_QUALIFICATION="$REPO_ROOT/local/artifacts/ishikawa/database-schema-package/database_schema_package_qualification_0402fdff8f886129.json"
readonly ACCEPTED_QUALIFICATION_CHECKSUM="$ACCEPTED_QUALIFICATION.sha256"
readonly ACCEPTED_SCHEMA_VALIDATION="$REPO_ROOT/local/artifacts/ishikawa/database-schema-package/database_schema_validation_0402fdff8f886129.json"
readonly ACCEPTED_SCHEMA_VALIDATION_CHECKSUM="$ACCEPTED_SCHEMA_VALIDATION.sha256"
readonly ACCEPTED_CODING_STANDARD="$REPO_ROOT/local/artifacts/ishikawa/database-schema-package/database_schema_coding_standard_0402fdff8f886129.json"
readonly ACCEPTED_CODING_STANDARD_CHECKSUM="$ACCEPTED_CODING_STANDARD.sha256"
readonly ACCEPTED_REPORT_SHA256='5d29f559b13d308ce97ee6e9dc20a375cb4c9bddddbba208717fbb90df414f4e'
readonly ACCEPTED_ARCHIVE_SHA256='0402fdff8f886129ffc6cdc688250c7e196e843b01b180a324ae7864ceeba710'
readonly ACCEPTED_ARCHIVE_CHECKSUM_SHA256='777d0baf8887a355e65a68bded2fcc00f93c04eabe46dd54ef2f7d6d31c4aa9a'
readonly ACCEPTED_QUALIFICATION_SHA256='1b140330c1ff3176671e2b6b9a3dea0d7ad9b60e1cfee053e0e5d7f98bba07f0'
readonly ACCEPTED_QUALIFICATION_CHECKSUM_SHA256='e14126efa55599c1e4b1c394fd36dc9dccf012c9f611178928e6b731f0d9c756'
readonly ACCEPTED_SCHEMA_VALIDATION_SHA256='023f699ec2dc73d40d2f45caff7c171eec55d630ef82f9bdbbef05e3c8c3aa58'
readonly ACCEPTED_SCHEMA_VALIDATION_CHECKSUM_SHA256='418bda2233b87cdf0aa50a29dde231b28af9b6eff8d447574e5106cc52fb0451'
readonly ACCEPTED_CODING_STANDARD_SHA256='a98362a9bbd841555368081211b9ddea7ad833f0dd651c715606a2d142cb1c85'
readonly ACCEPTED_CODING_STANDARD_CHECKSUM_SHA256='b3debfb56a468b670a6ab31518fac7eaf75a6d4a5aad2a8ae48d7cf40f6be0c5'
readonly SCHEMA_SHA256='5cfd397152b726aedc97be84d8a06fc8f21cad6e1a11563e5e9dd3a1f026d568'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-database-schema-qualification"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/database-schema-qualification"

target="${APPLICATION_HOST_TARGET:-DankoSurface_EmceeDanko}"
expected_hostname="${APPLICATION_HOST_EXPECTED_HOSTNAME:-EmceeDanko}"
expected_os_version="${APPLICATION_HOST_EXPECTED_OS_VERSION:-24.04}"
accepted_database="${APPLICATION_DATABASE_NAME:-rag_catalog}"
owner_role="${APPLICATION_DATABASE_OWNER_ROLE:-rag_owner}"
ingest_role="${APPLICATION_DATABASE_INGEST_ROLE:-rag_ingest}"
retrieval_role="${APPLICATION_DATABASE_RETRIEVAL_ROLE:-rag_retrieval}"
identity_file="${APPLICATION_HOST_IDENTITY_FILE:-}"
run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --target) target="${2:-}"; shift 2 ;;
    --expected-hostname) expected_hostname="${2:-}"; shift 2 ;;
    --expected-os-version) expected_os_version="${2:-}"; shift 2 ;;
    --identity-file) identity_file="${2:-}"; shift 2 ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_91_database_schema_qualification=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$run_authorized" != "$validate_only" ]] || { printf 'script_91_database_schema_qualification=blocked;reason=mode_invalid\n' >&2; exit 2; }
[[ "$target" =~ ^[A-Za-z0-9_@.:-]+$ ]] || { printf 'script_91_database_schema_qualification=blocked;reason=target_invalid\n' >&2; exit 2; }
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || { printf 'script_91_database_schema_qualification=blocked;reason=expected_hostname_invalid\n' >&2; exit 2; }
[[ "$expected_os_version" =~ ^[0-9]{2}\.[0-9]{2}$ ]] || { printf 'script_91_database_schema_qualification=blocked;reason=expected_os_version_invalid\n' >&2; exit 2; }
[[ "$accepted_database|$owner_role|$ingest_role|$retrieval_role" == 'rag_catalog|rag_owner|rag_ingest|rag_retrieval' ]] || { printf 'script_91_database_schema_qualification=blocked;reason=database_contract_invalid\n' >&2; exit 2; }
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] || { printf 'script_91_database_schema_qualification=blocked;reason=identity_file_unsafe\n' >&2; exit 2; }
fi
for required in awk bash basename chmod cp date dirname grep mkdir mktemp mv python3 rm scp sed sha256sum ssh stat tar tee timeout; do
  command -v "$required" >/dev/null 2>&1 || { printf 'script_91_database_schema_qualification=blocked;reason=local_command_missing\n' >&2; exit 2; }
done
for required_file in \
  "$TARGET_HELPER" "$CODING_STANDARD" "$CODING_STANDARD_EVALUATOR" \
  "$ACCEPTED_REPORT" "$ACCEPTED_ARCHIVE" "$ACCEPTED_ARCHIVE_CHECKSUM" \
  "$ACCEPTED_QUALIFICATION" "$ACCEPTED_QUALIFICATION_CHECKSUM" \
  "$ACCEPTED_SCHEMA_VALIDATION" "$ACCEPTED_SCHEMA_VALIDATION_CHECKSUM" \
  "$ACCEPTED_CODING_STANDARD" "$ACCEPTED_CODING_STANDARD_CHECKSUM"; do
  [[ -f "$required_file" && ! -L "$required_file" && -r "$required_file" ]] || { printf 'script_91_database_schema_qualification=blocked;reason=accepted_input_missing\n' >&2; exit 2; }
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_91_database_schema_qualification=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}
check_sha256 "$ACCEPTED_REPORT" "$ACCEPTED_REPORT_SHA256" 'accepted_report'
check_sha256 "$ACCEPTED_ARCHIVE" "$ACCEPTED_ARCHIVE_SHA256" 'accepted_archive'
check_sha256 "$ACCEPTED_ARCHIVE_CHECKSUM" "$ACCEPTED_ARCHIVE_CHECKSUM_SHA256" 'accepted_archive_checksum'
check_sha256 "$ACCEPTED_QUALIFICATION" "$ACCEPTED_QUALIFICATION_SHA256" 'accepted_qualification'
check_sha256 "$ACCEPTED_QUALIFICATION_CHECKSUM" "$ACCEPTED_QUALIFICATION_CHECKSUM_SHA256" 'accepted_qualification_checksum'
check_sha256 "$ACCEPTED_SCHEMA_VALIDATION" "$ACCEPTED_SCHEMA_VALIDATION_SHA256" 'accepted_schema_validation'
check_sha256 "$ACCEPTED_SCHEMA_VALIDATION_CHECKSUM" "$ACCEPTED_SCHEMA_VALIDATION_CHECKSUM_SHA256" 'accepted_schema_validation_checksum'
check_sha256 "$ACCEPTED_CODING_STANDARD" "$ACCEPTED_CODING_STANDARD_SHA256" 'accepted_coding_standard'
check_sha256 "$ACCEPTED_CODING_STANDARD_CHECKSUM" "$ACCEPTED_CODING_STANDARD_CHECKSUM_SHA256" 'accepted_coding_standard_checksum'
for sidecar in "$ACCEPTED_ARCHIVE_CHECKSUM" "$ACCEPTED_QUALIFICATION_CHECKSUM" "$ACCEPTED_SCHEMA_VALIDATION_CHECKSUM" "$ACCEPTED_CODING_STANDARD_CHECKSUM"; do
  (
    cd -- "$(dirname -- "$sidecar")"
    sha256sum --check --strict "$(basename -- "$sidecar")" >/dev/null
  ) || { printf 'script_91_database_schema_qualification=blocked;reason=accepted_checksum_failed\n' >&2; exit 2; }
done
for fact in \
  "schema_sha256=$SCHEMA_SHA256;schema_bytes=24965;schema_version=4" \
  'catalog_equivalence=exact;ancestor_ledger_rows=4;consolidated_ledger_rows=1' \
  'coding_standard_compliant=true;coding_standard_findings=0;historical_mutation_files=0' \
  'target_contact=false;local_disposable_database=true;sql_execution_performed=true;persistent_database_changed=false;service_changed=false;model_contact=false' \
  'script_90_database_schema_package=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_REPORT" || { printf 'script_91_database_schema_qualification=blocked;reason=accepted_report_contract_failed\n' >&2; exit 2; }
done

bash -n "${BASH_SOURCE[0]}" "$TARGET_HELPER"
python3 -B -c 'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' "$CODING_STANDARD_EVALUATOR"
if grep -Eiq 'phase[-_ ]?[0-9]+|(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)|Danko|org[_ -]?lab|Agent|repository|Script[[:space:]_-]*[0-9]+' "$TARGET_HELPER"; then
  printf 'script_91_database_schema_qualification=blocked;reason=target_helper_jargon_found\n' >&2
  exit 2
fi

work_root="$(mktemp -d /tmp/ishikawa-script-91.XXXXXX)"
report_path=''
remote_root=''
remote_created=false
master_started=false
artifact_committed=false
artifact_path=''
checksum_path=''
ssh_args=()
emit() {
  if [[ -n "$report_path" ]]; then
    printf '%s\n' "$1" | tee -a "$report_path"
  else
    printf '%s\n' "$1"
  fi
}
cleanup() {
  local status="$?" cleanup_code=0 close_code=0
  trap - EXIT INT TERM
  set +e
  if [[ "$remote_created" == true && "$master_started" == true ]]; then
    timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "rm -rf -- '$remote_root' && test ! -e '$remote_root'" >/dev/null 2>&1 || cleanup_code=$?
    if (( cleanup_code == 0 )); then emit 'cleanup_remote_temporary_files=removed'; else emit "cleanup_remote_temporary_files=review_required;exit_code=$cleanup_code"; status=1; fi
  fi
  if [[ "$master_started" == true ]]; then
    timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1 || close_code=$?
    emit "cleanup_ssh_master_exit_code=$close_code"
    (( close_code == 0 )) || status=1
  fi
  if [[ "$artifact_committed" != true ]]; then
    [[ "$artifact_path" == "$ARTIFACT_ROOT"/database_schema_qualification_*.json ]] && rm -f -- "$artifact_path"
    [[ "$checksum_path" == "$ARTIFACT_ROOT"/database_schema_qualification_*.json.sha256 ]] && rm -f -- "$checksum_path"
  fi
  if [[ "$work_root" == /tmp/ishikawa-script-91.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p -- "$work_root/extracted"
tar -xzf "$ACCEPTED_ARCHIVE" -C "$work_root/extracted"
bundle_root="$work_root/extracted/ishikawa-database-schema-package"
[[ -d "$bundle_root" && ! -L "$bundle_root" ]] || { printf 'script_91_database_schema_qualification=blocked;reason=local_bundle_invalid\n' >&2; exit 1; }
current_compliance="$work_root/current-coding-standard.json"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$CODING_STANDARD_EVALUATOR" \
  --bundle-root "$bundle_root" \
  --standard "$CODING_STANDARD" \
  --output "$current_compliance" >/dev/null || { printf 'script_91_database_schema_qualification=blocked;reason=current_coding_standard_noncompliance\n' >&2; exit 1; }
coding_standard_sha256="$(sha256sum "$CODING_STANDARD" | awk '{print $1}')"
coding_standard_receipt_sha256="$(sha256sum "$current_compliance" | awk '{print $1}')"
helper_sha256="$(sha256sum "$TARGET_HELPER" | awk '{print $1}')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_database_schema_package_target_qualification_source' \
    "script_sha256=$script_sha256;target_helper_sha256=$helper_sha256" \
    "accepted_archive_sha256=$ACCEPTED_ARCHIVE_SHA256;accepted_report_sha256=$ACCEPTED_REPORT_SHA256;schema_sha256=$SCHEMA_SHA256" \
    "coding_standard_sha256=$coding_standard_sha256;coding_standard_receipt_sha256=$coding_standard_receipt_sha256" \
    'current_coding_standard_compliance=pass;historical_mutation_files=0' \
    'target_contact=false;database_changed=false;service_changed=false' \
    'script_91_database_schema_qualification_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/database_schema_qualification_${timestamp}_XXXXXX.txt")"
remote_root="/tmp/ishikawa-database-schema-qualification-$timestamp-$$"
emit 'purpose=qualify_database_schema_package_on_application_host'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;target_helper_sha256=$helper_sha256"
emit "accepted_archive_sha256=$ACCEPTED_ARCHIVE_SHA256;accepted_report_sha256=$ACCEPTED_REPORT_SHA256;schema_sha256=$SCHEMA_SHA256"
emit "coding_standard_sha256=$coding_standard_sha256;coding_standard_receipt_sha256=$coding_standard_receipt_sha256"
emit 'current_coding_standard_compliance=pass;historical_mutation_files=0'
emit 'authorized_actions=authenticate_transfer_checksum_bound_archive_verify_host_start_manual_cluster_snapshot_accepted_database_create_install_verify_restart_and_drop_disposable_database_stop_cluster_return_content_free_evidence_remove_transfer_directory'
emit 'non_actions=no_package_or_role_change_no_accepted_database_mutation_no_model_call_no_credential_read_no_source_document_copy_no_port_forwarding_change_no_service_enablement'
emit "selected_target=$target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version;accepted_database=$accepted_database"
emit 'milestone=authentication;state=waiting_for_operator_if_prompted'

control_path="$work_root/ssh-control"
ssh_args=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto -o "ControlPath=$control_path" -o ControlPersist=1200)
if [[ -n "$identity_file" ]]; then ssh_args+=(-i "$identity_file" -o IdentitiesOnly=yes); fi
timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$target" >/dev/null 2>&1 || { emit 'script_91_database_schema_qualification=blocked;reason=ssh_master_start_failed'; exit 1; }
master_started=true
emit 'milestone=authentication;state=pass'

timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" >/dev/null || { emit 'script_91_database_schema_qualification=blocked;reason=remote_temporary_directory_not_created'; exit 1; }
remote_created=true
emit 'milestone=package_transfer;state=start'
timeout --foreground 180 scp "${ssh_args[@]}" "$ACCEPTED_ARCHIVE" "$TARGET_HELPER" "$target:$remote_root/" >/dev/null || { emit 'script_91_database_schema_qualification=blocked;reason=package_transfer_failed'; exit 1; }
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "cd '$remote_root' && printf '%s  %s\n%s  %s\n' '$ACCEPTED_ARCHIVE_SHA256' '$(basename -- "$ACCEPTED_ARCHIVE")' '$helper_sha256' '$(basename -- "$TARGET_HELPER")' | sha256sum --check --strict - >/dev/null" >/dev/null || { emit 'script_91_database_schema_qualification=blocked;reason=transferred_payload_checksum_failed'; exit 1; }
emit 'milestone=package_transfer;state=pass'

emit 'milestone=database_schema_qualification;state=waiting_for_operator_sudo_if_prompted'
set +e
timeout --foreground 900 ssh -tt "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && sudo -p '[sudo] password for database schema qualification: ' bash './$(basename -- "$TARGET_HELPER")' '$expected_hostname' '$expected_os_version' '$remote_root/$(basename -- "$ACCEPTED_ARCHIVE")' '$ACCEPTED_ARCHIVE_SHA256' '$accepted_database' '$owner_role' '$ingest_role' '$retrieval_role' > database-schema-qualification.txt" < /dev/tty
remote_code=$?
set -e
emit "remote_execution_exit_code=$remote_code;raw_remote_output_retained=false"

fetched_result="$work_root/database-schema-qualification.txt"
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/database-schema-qualification.txt" "$fetched_result" >/dev/null || { emit 'script_91_database_schema_qualification=blocked;reason=result_fetch_failed'; exit 1; }
output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then
    output_contract=blocked
    continue
  fi
  emit "$line"
done <"$fetched_result"
emit "remote_output_contract=$output_contract"

required_fact_contract=pass
for fact in \
  'purpose=qualify_final_database_schema_package' \
  "host=$expected_hostname;os_version=$expected_os_version;architecture=amd64" \
  'postgresql_version=16.15;vector_default_version=0.8.7' \
  "archive_sha256=$ACCEPTED_ARCHIVE_SHA256;archive_bytes=6783;package_checksums=pass" \
  "package_file_count=4;historical_mutation_files=0;schema_sha256=$SCHEMA_SHA256" \
  'cluster_start=pass;readiness=pass;listener_address=127.0.0.1;listener_port=5432' \
  'temporary_database_created=true;accepted_schema_version=4;packaged_schema_version=4' \
  'catalog_equivalence=exact;tables=20;views=5;explicit_indexes=14;required_named_constraints=11' \
  'baseline_identity=ishikawa_consolidated_schema_v4;baseline_rows=1;restart_persistence=pass' \
  'retrieval_view_select=true;retrieval_base_table_select=false;ingest_write=true;schema_ledger_write=false' \
  'temporary_database_dropped=true;accepted_database_unchanged=true' \
  'cluster_status=down;postgresql_port_5432=free;postgresql_service_active=inactive;postgresql_service_enabled=disabled' \
  'database_schema_package_qualification=pass' \
  'cleanup_private_work_exit_code=0'; do
  [[ "$(grep -Fxc "$fact" "$fetched_result" || true)" == 1 ]] || required_fact_contract=blocked
done
[[ "$(grep -Ec '^accepted_schema_sha256=[0-9a-f]{64};accepted_ledger_rows=4;accepted_content_rows=0$' "$fetched_result" || true)" == 1 ]] || required_fact_contract=blocked
pass_markers="$(grep -Fxc 'database_schema_package_qualification=pass' "$fetched_result" || true)"
blocked_markers="$(grep -Ec '^database_schema_package_qualification=blocked;' "$fetched_result" || true)"
emit "required_fact_contract=$required_fact_contract;pass_markers=$pass_markers;blocked_markers=$blocked_markers"
if (( remote_code != 0 )) || [[ "$output_contract" != pass || "$required_fact_contract" != pass || "$pass_markers" != 1 || "$blocked_markers" != 0 ]]; then
  emit 'milestone=database_schema_qualification;state=blocked'
  emit "script_91_database_schema_qualification=blocked;local_report=$report_path;next_gate=inspect_qualification_result_before_any_retry"
  exit 1
fi

accepted_schema_sha256="$(sed -n 's/^accepted_schema_sha256=\([0-9a-f]\{64\}\);.*/\1/p' "$fetched_result")"
artifact_path="$ARTIFACT_ROOT/database_schema_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || { emit 'script_91_database_schema_qualification=blocked;reason=artifact_path_exists'; exit 1; }
printf '{"accepted_database_unchanged":true,"accepted_schema_sha256":"%s","archive_sha256":"%s","catalog_equivalence":"exact","disposable_database_dropped":true,"historical_mutation_files":0,"package_schema_sha256":"%s","package_schema_version":4,"postgresql_version":"16.15","receipt_schema_version":1,"target_hostname":"%s","vector_version":"0.8.7"}\n' \
  "$accepted_schema_sha256" "$ACCEPTED_ARCHIVE_SHA256" "$SCHEMA_SHA256" "$expected_hostname" >"$artifact_path"
artifact_sha256="$(sha256sum "$artifact_path" | awk '{print $1}')"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
(
  cd -- "$ARTIFACT_ROOT"
  sha256sum --check --strict "$(basename -- "$checksum_path")" >/dev/null
) || { emit 'script_91_database_schema_qualification=blocked;reason=retained_artifact_checksum_failed'; exit 1; }
artifact_committed=true
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_checksum=$checksum_path"
emit 'milestone=database_schema_qualification;state=pass'
emit "script_91_database_schema_qualification=pass;local_report=$report_path;next_gate=review_remaining_portable_installation_surface"
chmod 0600 "$report_path" 2>/dev/null || true
