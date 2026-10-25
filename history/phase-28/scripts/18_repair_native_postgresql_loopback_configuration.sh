#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Repair the single invalid unquoted PostgreSQL loopback setting identified
#   after Script 17, then validate the complete configuration while stopped.
#
# Execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/18_repair_native_postgresql_loopback_configuration.sh --repair

usage() {
  sed -n '3,9p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --repair                   Explicitly authorize the one-line configuration repair.' \
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
readonly TARGET_HELPER="$SCRIPT_DIR/repair-native-database-loopback-configuration"
readonly ACCEPTED_INSPECTION_REPORT="$REPO_ROOT/local/reports/native-postgresql-start-failure-inspection/native_postgresql_start_failure_inspection_20261019T143943Z_oQwgmp.txt"
readonly ACCEPTED_INSPECTION_REPORT_SHA256="f929766432d24472ad7ebc6c928bba14400ab075929c434d4e02f72390e23333"
readonly DEFAULT_REPORT_ROOT="$REPO_ROOT/local/reports/native-postgresql-loopback-configuration-repair"

target="${APPLICATION_HOST_TARGET:-DankoSurface_EmceeDanko}"
expected_hostname="${APPLICATION_HOST_EXPECTED_HOSTNAME:-EmceeDanko}"
expected_os_version="${APPLICATION_HOST_EXPECTED_OS_VERSION:-24.04}"
identity_file="${APPLICATION_HOST_IDENTITY_FILE:-}"
report_root="$DEFAULT_REPORT_ROOT"
repair_authorized=false
validate_only=false

while (( $# > 0 )); do
  case "$1" in
    --repair) repair_authorized=true; shift ;;
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
[[ -f "$ACCEPTED_INSPECTION_REPORT" && ! -L "$ACCEPTED_INSPECTION_REPORT" ]] || { printf 'BLOCKED: accepted Script 17 report is missing or unsafe.\n' >&2; exit 2; }
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

inspection_report_sha256="$(sha256sum "$ACCEPTED_INSPECTION_REPORT" | awk '{print $1}')"
[[ "$inspection_report_sha256" == "$ACCEPTED_INSPECTION_REPORT_SHA256" ]] || { printf 'BLOCKED: accepted Script 17 report checksum mismatch.\n' >&2; exit 2; }
for accepted_fact in \
  'remote_execution_exit_code=0;raw_stderr_retained=false' \
  'cluster_version=16;cluster_name=main;cluster_port=5432;cluster_status=down' \
  'cluster_start_policy=manual;listen_addresses=127.0.0.1;password_encryption=scram-sha-256' \
  'database_cluster_state=shut_down;data_page_checksum_version=1' \
  'configuration_probe_exit_code=1;configuration_probe_value=none;configuration_probe_stderr_sha256=3e3440c8ef84eaaa832f066079298385c9d54c9f5e368b9886b12eccbcda7f4e' \
  'postgresql_port_5432_listeners=0;available_var_kib=439741604;available_run_kib=3248068' \
  'cluster_log_tail_lines=4;cluster_log_tail_sha256=928e06495027355a86d51ebb2de63af82b910788f8bc1906a1a9186c9fabe5bb;cluster_log_error_class=configuration_error' \
  'native_database_start_failure_inspection=pass' \
  'cleanup_remote_temporary_files=removed' \
  'cleanup_ssh_master_exit_code=0'; do
  grep -Fxq "$accepted_fact" "$ACCEPTED_INSPECTION_REPORT" || { printf 'BLOCKED: required Script 17 inspection fact is absent.\n' >&2; exit 2; }
done
grep -Fq 'native_postgresql_start_failure_inspection_wrapper=pass;' "$ACCEPTED_INSPECTION_REPORT" || { printf 'BLOCKED: accepted Script 17 wrapper pass marker is absent.\n' >&2; exit 2; }

helper_sha256="$(sha256sum "$TARGET_HELPER" | awk '{print $1}')"
helper_bytes="$(wc -c <"$TARGET_HELPER" | tr -d ' ')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'native_postgresql_loopback_configuration_repair_source=pass' \
    'target_contact=false' \
    'configuration_change=false' \
    'identified_cause=unquoted_ipv4_listen_address_written_by_configuration_helper' \
    "script_sha256=$script_sha256" \
    "helper_sha256=$helper_sha256" \
    "helper_bytes=$helper_bytes" \
    "accepted_inspection_report_sha256=$inspection_report_sha256"
  exit 0
fi

[[ "$repair_authorized" == true ]] || { printf 'BLOCKED: loopback configuration repair requires the explicit --repair argument.\n' >&2; exit 2; }

mkdir -p -- "$report_root"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_root/native_postgresql_loopback_configuration_repair_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/native-postgresql-loopback-configuration-repair.XXXXXX)"
remote_root="/tmp/native-database-loopback-configuration-repair-$timestamp-$$"
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
  if [[ "$work_root" == /tmp/native-postgresql-loopback-configuration-repair.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

emit 'purpose=repair_invalid_native_postgresql_loopback_configuration'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;helper_sha256=$helper_sha256;helper_bytes=$helper_bytes"
emit "accepted_inspection_report_sha256=$inspection_report_sha256"
emit 'identified_cause=unquoted_ipv4_listen_address_written_by_configuration_helper'
emit 'authorized_actions=stage_verified_temporary_helper_replace_one_invalid_configuration_line_validate_complete_configuration_retrieve_bounded_result_remove_temporary_files'
emit 'non_actions=no_network_access_no_package_change_no_database_start_stop_restart_enable_disable_or_reset_no_database_query_or_object_change_no_secret_or_content_read'
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
    emit 'native_postgresql_loopback_configuration_repair_wrapper=blocked;reason=ssh_master_start_failed;raw_stderr_retained=false'
    exit 1
  }
master_started=true
emit 'milestone=authentication;state=pass'

timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" \
  >"$work_root/create.stdout" 2>"$work_root/create.stderr" || {
    emit 'native_postgresql_loopback_configuration_repair_wrapper=blocked;reason=remote_temporary_directory_not_created'
    exit 1
  }
remote_created=true

timeout --foreground 120 scp "${ssh_args[@]}" "$TARGET_HELPER" \
  "$target:$remote_root/" >"$work_root/scp.stdout" 2>"$work_root/scp.stderr" || {
    emit 'native_postgresql_loopback_configuration_repair_wrapper=blocked;reason=temporary_helper_copy_failed'
    exit 1
  }

timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && printf '%s  %s\n' '$helper_sha256' repair-native-database-loopback-configuration | sha256sum --check --strict -" \
  >"$work_root/hash.stdout" 2>"$work_root/hash.stderr" || {
    emit 'native_postgresql_loopback_configuration_repair_wrapper=blocked;reason=target_helper_hash_mismatch'
    exit 1
  }
emit 'milestone=target_helper_verification;state=pass'

emit 'milestone=loopback_configuration_repair;state=waiting_for_operator_sudo_if_prompted'
set +e
timeout --foreground 600 ssh -tt "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && sudo -p '[sudo] password for native database configuration repair: ' bash ./repair-native-database-loopback-configuration '$expected_hostname' '$expected_os_version' > native-database-loopback-configuration-repair.txt" \
  < /dev/tty
remote_code=$?
set -e
emit "remote_execution_exit_code=$remote_code;raw_stderr_retained=false"

fetched_result="$work_root/native-database-loopback-configuration-repair.txt"
if ! timeout --foreground 120 scp "${ssh_args[@]}" \
  "$target:$remote_root/native-database-loopback-configuration-repair.txt" "$fetched_result" \
  >"$work_root/fetch.stdout" 2>"$work_root/fetch.stderr"; then
  emit 'native_postgresql_loopback_configuration_repair_wrapper=blocked;reason=result_fetch_failed'
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

pass_markers="$(grep -Fxc 'native_database_loopback_configuration_repair=pass' "$fetched_result" || true)"
blocked_markers="$(grep -Ec '^native_database_loopback_configuration_repair=blocked;' "$fetched_result" || true)"
emit "repair_pass_markers=$pass_markers;repair_blocked_markers=$blocked_markers"

if (( remote_code == 0 )) && [[ "$output_contract" == pass && "$pass_markers" == 1 && "$blocked_markers" == 0 ]]; then
  emit 'milestone=loopback_configuration_repair;state=pass'
  emit "native_postgresql_loopback_configuration_repair_wrapper=pass;local_report=$report_path;next_gate=retry_application_database_configuration"
  exit 0
fi

emit 'milestone=loopback_configuration_repair;state=blocked'
emit "native_postgresql_loopback_configuration_repair_wrapper=blocked;local_report=$report_path;next_gate=review_repair_before_any_database_start_retry"
exit 1
