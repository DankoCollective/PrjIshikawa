#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Purpose:
#   Capture the read-only EmceeDanko posture required before v1.3 staging.
#
# Mental model:
#   Validate local controls, run one bounded helper over attended SSH, accept
#   only its content-free output contract, and retain the complete local report.
#
# Inputs or prerequisites:
#   Strict SSH host trust and operator access to the application-host identity.
#
# Outputs or artifact lane:
#   A timestamped ignored report under local/reports/emceedanko-inventory.
#
# Usage:
#   bash ./deployment/scripts/02_inventory-emceedanko.sh --run

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
readonly helper="$repo_root/deployment/assets/inspect-application-host"
readonly default_report_root="$repo_root/local/reports/emceedanko-inventory"

target="${APPLICATION_HOST_TARGET:-DankoSurface_EmceeDanko}"
expected_hostname="${APPLICATION_HOST_EXPECTED_HOSTNAME:-EmceeDanko}"
expected_os_version="${APPLICATION_HOST_EXPECTED_OS_VERSION:-24.04}"
identity_file="${APPLICATION_HOST_IDENTITY_FILE:-}"
report_root="$default_report_root"
mode="${1:-}"
if [[ "$mode" == --help || "$mode" == -h ]]; then
  mode=help
else
  shift || true
fi

result() { printf '\nSCRIPT RESULT\nscript_02_inventory_emceedanko=%s\n' "$1"; }
fail() {
  local reason="$1" detail="$2" action="$3"
  printf '%s\n' 'FAILURE DETAIL' "stage=${stage:-preflight}" "reason=$reason" \
    "detail=$detail" "operator_action=$action" >&2
  result blocked >&2
  exit 1
}
usage() {
  printf '%s\n' \
    'Usage: 02_inventory-emceedanko.sh --validate-only' \
    '       02_inventory-emceedanko.sh --run [--target SSH_ALIAS] [--identity-file ABSOLUTE_PATH]'
}

if [[ "$mode" == help ]]; then
  usage
  exit 0
fi

while (( $# > 0 )); do
  case "$1" in
    --target) [[ $# -ge 2 ]] || fail target_missing 'The target value is missing.' 'Supply one SSH alias.'; target="$2"; shift 2 ;;
    --expected-hostname) [[ $# -ge 2 ]] || fail hostname_missing 'The hostname value is missing.' 'Supply the expected short hostname.'; expected_hostname="$2"; shift 2 ;;
    --expected-os-version) [[ $# -ge 2 ]] || fail os_version_missing 'The OS version value is missing.' 'Supply the expected Ubuntu version.'; expected_os_version="$2"; shift 2 ;;
    --identity-file) [[ $# -ge 2 ]] || fail identity_missing 'The identity path is missing.' 'Supply an absolute identity path.'; identity_file="$2"; shift 2 ;;
    --report-root) [[ $# -ge 2 ]] || fail report_root_missing 'The report root is missing.' 'Supply an absolute local path.'; report_root="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) fail argument_invalid "Unsupported argument: $1" 'Use --help and rerun.' ;;
  esac
done
[[ "$mode" == --validate-only || "$mode" == --run ]] || fail mode_invalid 'Select exactly one execution mode.' 'Use --validate-only or --run.'
[[ "$target" =~ ^[A-Za-z0-9_@.:-]+$ ]] || fail target_invalid 'The SSH target is not bounded.' 'Use a configured SSH alias or USER@HOST.'
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || fail hostname_invalid 'The expected hostname is invalid.' 'Correct the hostname.'
[[ "$expected_os_version" =~ ^[0-9]{2}\.[0-9]{2}$ ]] || fail os_version_invalid 'The expected OS version is invalid.' 'Use NN.NN.'
[[ "$report_root" == /* && ! -L "$report_root" ]] || fail report_root_unsafe 'The report root must be an absolute non-symlink path.' 'Correct the report root.'
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] \
    || fail identity_unsafe 'The explicit identity file is unsafe.' 'Correct the identity path or rely on SSH configuration.'
fi
for command_name in awk bash date grep mkdir mktemp rm sha256sum ssh tee timeout wc; do
  command -v "$command_name" >/dev/null 2>&1 || fail "command_missing_$command_name" "Required command unavailable: $command_name" 'Install or restore the command.'
done
[[ -f "$helper" && ! -L "$helper" && -r "$helper" ]] || fail helper_unsafe 'The target helper is missing or unsafe.' 'Restore the tracked helper.'
bash -n "${BASH_SOURCE[0]}" "$helper" || fail shell_syntax_invalid 'A deployment script failed shell parsing.' 'Correct all parse errors.'
helper_sha256="$(sha256sum -- "$helper" | awk '{print $1}')"

if [[ "$mode" == --validate-only ]]; then
  printf '%s\n' \
    'purpose=validate_read_only_emceedanko_inventory' \
    "helper_sha256=$helper_sha256" \
    'target_contact=false;target_mutation=false;credential_read=false'
  result ready
  exit 0
fi

stage=report_setup
mkdir -p -- "$report_root"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_root/emceedanko_inventory_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-emceedanko-inventory.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  [[ "$work_root" == /tmp/ishikawa-emceedanko-inventory.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  exit "$status"
}
trap cleanup EXIT
trap 'stage=interrupted; fail signal_interrupt "The inventory was interrupted." "Review the report and rerun."' INT
trap 'stage=interrupted; fail signal_termination "The inventory was terminated." "Review the report and rerun."' TERM
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=read_only_emceedanko_ishikawa_inventory'
emit "helper_sha256=$helper_sha256;target=$target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version"
emit 'authorized_actions=read_bounded_host_runtime_application_service_port_and_postgresql_metadata'
emit 'non_actions=no_install_no_update_no_service_change_no_database_change_no_target_file_write_no_document_or_secret_read'

stage=remote_inventory
emit 'milestone=remote_inventory;state=start'
ssh_args=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 -o ServerAliveInterval=30 -o ServerAliveCountMax=3)
[[ -z "$identity_file" ]] || ssh_args+=(-i "$identity_file" -o IdentitiesOnly=yes)
set +e
timeout --foreground 180 ssh "${ssh_args[@]}" "$target" -- /bin/bash -s -- \
  "$expected_hostname" "$expected_os_version" <"$helper" >"$work_root/remote.stdout" 2>"$work_root/remote.stderr"
remote_status=$?
set -e
output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 1024 )) || [[ "$line" == *$'\t'* ]] \
      || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then
    output_contract=blocked
    continue
  fi
  emit "$line"
done <"$work_root/remote.stdout"
classification=none
if (( remote_status != 0 )); then
  classification=target_inventory_blocked
  grep -Eiq 'permission denied.*publickey' "$work_root/remote.stderr" && classification=public_key_authentication_rejected
  grep -Eiq 'host key verification failed|remote host identification has changed' "$work_root/remote.stderr" && classification=host_key_rejected
  grep -Eiq 'connection timed out|operation timed out' "$work_root/remote.stderr" && classification=connection_timeout
  grep -Eiq 'connection refused' "$work_root/remote.stderr" && classification=connection_refused
  grep -Eiq 'no route to host|network is unreachable' "$work_root/remote.stderr" && classification=network_unreachable
  grep -Eiq 'could not resolve hostname' "$work_root/remote.stderr" && classification=name_resolution_failed
  (( remote_status != 124 )) || classification=timeout
fi
emit "remote_exit_code=$remote_status;output_contract=$output_contract;transport_classification=$classification"
pass_markers="$(grep -Fxc 'ishikawa_application_host_inventory=pass' "$work_root/remote.stdout" || true)"
if (( remote_status != 0 )) || [[ "$output_contract" != pass || "$pass_markers" != 1 ]]; then
  emit 'milestone=remote_inventory;state=blocked'
  printf '%s\n' 'FAILURE DETAIL' 'stage=remote_inventory' "reason=$classification" \
    "detail=The read-only target inventory did not satisfy its bounded contract." \
    "operator_action=Review $report_path and correct every reported target or transport condition." | tee -a "$report_path" >&2
  result blocked | tee -a "$report_path" >&2
  exit 1
fi
emit 'milestone=remote_inventory;state=pass;target_mutation=false'
emit "local_report=$report_path;next_gate=review_inventory_and_freeze_database_and_rollback_decisions"
result pass | tee -a "$report_path"
