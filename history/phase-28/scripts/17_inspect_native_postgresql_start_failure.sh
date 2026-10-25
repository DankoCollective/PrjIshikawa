#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Inspect the Script 16 PostgreSQL cluster-start failure without retrying the
#   start or changing package, cluster, database, or service state.
#
# Execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/17_inspect_native_postgresql_start_failure.sh

usage() {
  sed -n '3,9p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
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
readonly TARGET_HELPER="$SCRIPT_DIR/inspect-native-database-start-failure"
readonly FAILED_CONFIGURATION_REPORT="$REPO_ROOT/local/reports/native-postgresql-application-database-configuration/native_postgresql_application_database_configuration_20261019T143429Z_05Q6uO.txt"
readonly FAILED_CONFIGURATION_REPORT_SHA256="86c791d8f414c566bbb6b0a0c7261dc30b3cfb4611eaad2fc9eec881fe92ede8"
readonly DEFAULT_REPORT_ROOT="$REPO_ROOT/local/reports/native-postgresql-start-failure-inspection"

target="${APPLICATION_HOST_TARGET:-DankoSurface_EmceeDanko}"
expected_hostname="${APPLICATION_HOST_EXPECTED_HOSTNAME:-EmceeDanko}"
expected_os_version="${APPLICATION_HOST_EXPECTED_OS_VERSION:-24.04}"
identity_file="${APPLICATION_HOST_IDENTITY_FILE:-}"
report_root="$DEFAULT_REPORT_ROOT"
validate_only=false

while (( $# > 0 )); do
  case "$1" in
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
[[ -f "$TARGET_HELPER" && ! -L "$TARGET_HELPER" && -r "$TARGET_HELPER" ]] || { printf 'BLOCKED: neutral target helper is missing or unsafe.\n' >&2; exit 2; }
[[ -f "$FAILED_CONFIGURATION_REPORT" && ! -L "$FAILED_CONFIGURATION_REPORT" ]] || { printf 'BLOCKED: failed Script 16 report is missing or unsafe.\n' >&2; exit 2; }
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] \
    || { printf 'BLOCKED: explicit identity file is missing, unreadable, non-absolute, or a symlink.\n' >&2; exit 2; }
fi

for required in awk bash date grep mkdir mktemp rm scp sha256sum ssh tee timeout tr wc; do
  command -v "$required" >/dev/null 2>&1 || { printf 'BLOCKED: missing local command: %s\n' "$required" >&2; exit 2; }
done

bash -n "$TARGET_HELPER"
if grep -Eiq 'phase[-_ ]?[0-9]+|(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)|Danko|org[_ -]?lab|Agent|repository' "$TARGET_HELPER"; then
  printf 'BLOCKED: development or environment jargon found in neutral target helper.\n' >&2
  exit 2
fi

failed_report_sha256="$(sha256sum "$FAILED_CONFIGURATION_REPORT" | awk '{print $1}')"
[[ "$failed_report_sha256" == "$FAILED_CONFIGURATION_REPORT_SHA256" ]] || { printf 'BLOCKED: failed Script 16 report checksum mismatch.\n' >&2; exit 2; }
for failed_fact in \
  'remote_execution_exit_code=1;raw_stderr_retained=false' \
  'native_application_database_configuration=blocked;reason=postgresql_cluster_start_failed' \
  'configuration_pass_markers=0;configuration_blocked_markers=1' \
  'milestone=application_database_configuration;state=blocked' \
  'cleanup_remote_temporary_files=removed' \
  'cleanup_ssh_master_exit_code=0'; do
  grep -Fxq "$failed_fact" "$FAILED_CONFIGURATION_REPORT" || { printf 'BLOCKED: required Script 16 failure fact is absent.\n' >&2; exit 2; }
done

helper_sha256="$(sha256sum "$TARGET_HELPER" | awk '{print $1}')"
helper_bytes="$(wc -c <"$TARGET_HELPER" | tr -d ' ')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'native_postgresql_start_failure_inspection_source=pass' \
    'target_contact=false' \
    'service_change=false' \
    "script_sha256=$script_sha256" \
    "helper_sha256=$helper_sha256" \
    "helper_bytes=$helper_bytes" \
    "failed_configuration_report_sha256=$failed_report_sha256"
  exit 0
fi

mkdir -p -- "$report_root"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_root/native_postgresql_start_failure_inspection_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/native-postgresql-start-failure-inspection.XXXXXX)"
remote_root="/tmp/native-database-start-failure-inspection-$timestamp-$$"
remote_created=false
master_started=false
ssh_args=()

emit() {
  printf '%s\n' "$1" | tee -a "$report_path"
}

cleanup() {
  local status="$?" cleanup_code=0 close_code=0
  trap - EXIT INT TERM
  set +e
  if [[ "$remote_created" == true && "$master_started" == true ]]; then
    timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
      "rm -rf -- '$remote_root'" >/dev/null 2>&1 || cleanup_code=$?
    if (( cleanup_code == 0 )); then
      emit 'cleanup_remote_temporary_files=removed'
    else
      emit "cleanup_remote_temporary_files=review_required;exit_code=$cleanup_code"
      status=1
    fi
  else
    emit 'cleanup_remote_temporary_files=not_required'
  fi
  if [[ "$master_started" == true ]]; then
    timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1 || close_code=$?
    emit "cleanup_ssh_master_exit_code=$close_code"
    (( close_code == 0 )) || status=1
  fi
  if [[ "$work_root" == /tmp/native-postgresql-start-failure-inspection.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

emit 'purpose=inspect_native_postgresql_cluster_start_failure_read_only'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;helper_sha256=$helper_sha256;helper_bytes=$helper_bytes"
emit "failed_configuration_report_sha256=$failed_report_sha256"
emit 'authorized_actions=stage_verified_temporary_helper_read_cluster_configuration_service_log_and_capacity_metadata_retrieve_bounded_result_remove_temporary_files'
emit 'non_actions=no_network_access_no_package_change_no_cluster_start_stop_restart_enable_disable_or_reset_no_database_query_or_change_no_secret_or_content_read'
emit "selected_target=$target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version"
emit 'operator_expectation=ssh_key_passphrase_up_to_once;target_sudo_password_may_be_prompted'

control_path="$work_root/ssh-control"
ssh_args=(
  -o StrictHostKeyChecking=yes
  -o ConnectTimeout=10
  -o ConnectionAttempts=1
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=3
  -o ControlMaster=auto
  -o "ControlPath=$control_path"
  -o ControlPersist=1800
)
if [[ -n "$identity_file" ]]; then
  ssh_args+=( -i "$identity_file" -o IdentitiesOnly=yes )
fi

emit 'milestone=authentication;state=waiting_for_operator_if_prompted'
timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$target" \
  >"$work_root/master.stdout" 2>"$work_root/master.stderr" || {
    emit 'native_postgresql_start_failure_inspection_wrapper=blocked;reason=ssh_master_start_failed;raw_stderr_retained=false'
    exit 1
  }
master_started=true
emit 'milestone=authentication;state=pass'

timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" \
  >"$work_root/create.stdout" 2>"$work_root/create.stderr" || {
    emit 'native_postgresql_start_failure_inspection_wrapper=blocked;reason=remote_temporary_directory_not_created'
    exit 1
  }
remote_created=true

timeout --foreground 120 scp "${ssh_args[@]}" "$TARGET_HELPER" \
  "$target:$remote_root/" >"$work_root/scp.stdout" 2>"$work_root/scp.stderr" || {
    emit 'native_postgresql_start_failure_inspection_wrapper=blocked;reason=temporary_helper_copy_failed'
    exit 1
  }

timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && printf '%s  %s\n' '$helper_sha256' inspect-native-database-start-failure | sha256sum --check --strict -" \
  >"$work_root/hash.stdout" 2>"$work_root/hash.stderr" || {
    emit 'native_postgresql_start_failure_inspection_wrapper=blocked;reason=target_helper_hash_mismatch'
    exit 1
  }
emit 'milestone=target_helper_verification;state=pass'

emit 'milestone=start_failure_inspection;state=waiting_for_operator_sudo_if_prompted'
set +e
timeout --foreground 600 ssh -tt "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && sudo -p '[sudo] password for native database start-failure inspection: ' bash ./inspect-native-database-start-failure '$expected_hostname' '$expected_os_version' > native-database-start-failure-inspection.txt" \
  < /dev/tty
remote_code=$?
set -e
emit "remote_execution_exit_code=$remote_code;raw_stderr_retained=false"

fetched_result="$work_root/native-database-start-failure-inspection.txt"
if ! timeout --foreground 120 scp "${ssh_args[@]}" \
  "$target:$remote_root/native-database-start-failure-inspection.txt" "$fetched_result" \
  >"$work_root/fetch.stdout" 2>"$work_root/fetch.stderr"; then
  emit 'native_postgresql_start_failure_inspection_wrapper=blocked;reason=result_fetch_failed'
  exit 1
fi

output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] \
      || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then
    output_contract=blocked
    continue
  fi
  emit "$line"
done <"$fetched_result"
emit "remote_output_contract=$output_contract"

pass_markers="$(grep -Fxc 'native_database_start_failure_inspection=pass' "$fetched_result" || true)"
blocked_markers="$(grep -Ec '^native_database_start_failure_inspection=blocked;' "$fetched_result" || true)"
emit "inspection_pass_markers=$pass_markers;inspection_blocked_markers=$blocked_markers"

if (( remote_code == 0 )) && [[ "$output_contract" == pass && "$pass_markers" == 1 && "$blocked_markers" == 0 ]]; then
  emit 'milestone=start_failure_inspection;state=pass'
  emit "native_postgresql_start_failure_inspection_wrapper=pass;local_report=$report_path;next_gate=review_cause_before_any_start_retry"
  exit 0
fi

emit 'milestone=start_failure_inspection;state=blocked'
emit "native_postgresql_start_failure_inspection_wrapper=blocked;local_report=$report_path;next_gate=review_incomplete_inspection_before_any_retry"
exit 1
