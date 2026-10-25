#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Stream the neutral read-only application-host inventory to one approved
#   target and retain its bounded result in a local report.
#
# Default Danko usage from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/02_run_application_host_inventory.sh
#
# Portable usage for another environment:
#   bash ./02_run_application_host_inventory.sh \
#     --target USER@HOST_OR_SSH_ALIAS \
#     --expected-hostname HOSTNAME \
#     --expected-os-version VERSION \
#     --identity-file /absolute/key/path \
#     --report-root /absolute/local/result/directory

usage() {
  sed -n '3,17p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --target VALUE             SSH destination or configured SSH alias.' \
    '  --expected-hostname NAME   Exact target short hostname.' \
    '  --expected-os-version VER  Expected Ubuntu major or major.minor version.' \
    '  --identity-file PATH       Optional explicit SSH private key.' \
    '  --report-root PATH         Absolute local result directory.' \
    '  --validate-only            Validate source without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly TARGET_HELPER="$SCRIPT_DIR/inspect-application-host"
readonly DEFAULT_REPORT_ROOT="$REPO_ROOT/local/reports/application-host-inventory"

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

[[ "$report_root" == /* ]] || { printf 'BLOCKED: --report-root must be absolute.\n' >&2; exit 2; }
[[ ! -L "$report_root" ]] || { printf 'BLOCKED: --report-root cannot be a symbolic link.\n' >&2; exit 2; }
[[ -f "$TARGET_HELPER" && ! -L "$TARGET_HELPER" && -r "$TARGET_HELPER" ]] \
  || { printf 'BLOCKED: neutral inventory helper is missing or unsafe.\n' >&2; exit 2; }
[[ "$target" =~ ^[A-Za-z0-9_@.:-]+$ ]] \
  || { printf 'BLOCKED: invalid SSH target or alias.\n' >&2; exit 2; }
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] \
  || { printf 'BLOCKED: invalid expected hostname.\n' >&2; exit 2; }
[[ "$expected_os_version" =~ ^[0-9]{2}(\.[0-9]{2})?$ ]] \
  || { printf 'BLOCKED: invalid expected Ubuntu version.\n' >&2; exit 2; }
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] \
    || { printf 'BLOCKED: explicit identity file is missing, unreadable, non-absolute, or a symlink.\n' >&2; exit 2; }
fi

for required in awk bash date grep mkdir mktemp python3 sha256sum ssh tee timeout tr wc; do
  command -v "$required" >/dev/null 2>&1 \
    || { printf 'BLOCKED: missing local command: %s\n' "$required" >&2; exit 2; }
done

bash -n "$TARGET_HELPER"
if grep -Eiq 'phase[-_ ]?[0-9]+|(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)|Danko|org[_ -]?lab|Agent|repository' "$TARGET_HELPER"; then
  printf 'BLOCKED: repository or environment jargon found in neutral target helper.\n' >&2
  exit 2
fi

helper_sha256="$(sha256sum "$TARGET_HELPER" | awk '{print $1}')"
helper_bytes="$(wc -c <"$TARGET_HELPER" | tr -d ' ')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'application_host_inventory_wrapper=pass' \
    'target_contact=false' \
    "helper_sha256=$helper_sha256" \
    "helper_bytes=$helper_bytes"
  exit 0
fi

mkdir -p -- "$report_root"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_root/application_host_inventory_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/application-host-inventory.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/application-host-inventory.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

emit() {
  printf '%s\n' "$1" | tee -a "$report_path"
}

emit 'purpose=inventory_application_host_without_mutation'
emit "started_utc=$timestamp"
emit "helper_sha256=$helper_sha256;helper_bytes=$helper_bytes"
emit 'authorized_actions=read_host_package_runtime_image_port_and_capacity_metadata'
emit 'non_actions=no_install_no_update_no_service_change_no_network_download_no_secret_or_content_read_no_target_file_write'
emit "selected_target=$target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version"
emit 'milestone=remote_inventory;state=start'

ssh_args=(
  -o StrictHostKeyChecking=yes
  -o ConnectTimeout=10
  -o ConnectionAttempts=1
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=3
)
if [[ -n "$identity_file" ]]; then
  ssh_args+=( -i "$identity_file" -o IdentitiesOnly=yes )
fi

set +e
timeout --foreground 180 ssh "${ssh_args[@]}" "$target" \
  -- /bin/bash -s -- "$expected_hostname" "$expected_os_version" \
  <"$TARGET_HELPER" >"$work_root/remote.stdout" 2>"$work_root/remote.stderr"
remote_code=$?
set -e

output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 768 )) || [[ "$line" == *$'\t'* ]] \
      || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then
    output_contract=blocked
    continue
  fi
  emit "$line"
done <"$work_root/remote.stdout"

emit "remote_execution_exit_code=$remote_code"
emit "remote_output_contract=$output_contract"

if (( remote_code != 0 )); then
  classification=target_inventory_blocked
  if grep -Eiq 'permission denied.*publickey' "$work_root/remote.stderr"; then
    classification=public_key_authentication_rejected
  elif grep -Eiq 'host key verification failed|remote host identification has changed' "$work_root/remote.stderr"; then
    classification=host_key_rejected
  elif grep -Eiq 'connection timed out|operation timed out' "$work_root/remote.stderr"; then
    classification=connection_timeout
  elif grep -Eiq 'connection refused' "$work_root/remote.stderr"; then
    classification=connection_refused
  elif grep -Eiq 'no route to host|network is unreachable' "$work_root/remote.stderr"; then
    classification=network_unreachable
  elif grep -Eiq 'could not resolve hostname' "$work_root/remote.stderr"; then
    classification=name_resolution_failed
  elif grep -Eiq 'passphrase|askpass|/dev/tty' "$work_root/remote.stderr"; then
    classification=attended_identity_unlock_required
  elif (( remote_code == 124 )); then
    classification=timeout
  fi
  emit "transport_classification=$classification;raw_stderr_retained=false"
fi

pass_markers="$(grep -Fxc 'application_host_inventory=pass' "$work_root/remote.stdout" || true)"
blocked_markers="$(grep -Fxc 'application_host_inventory=blocked' "$work_root/remote.stdout" || true)"
emit "inventory_pass_markers=$pass_markers;inventory_blocked_markers=$blocked_markers"

if (( remote_code == 0 )) && [[ "$output_contract" == pass && "$pass_markers" == 1 && "$blocked_markers" == 0 ]]; then
  emit 'milestone=remote_inventory;state=pass'
  emit "application_host_inventory_wrapper=pass;local_report=$report_path;next_gate=review_inventory_before_artifact_selection"
  exit 0
fi

emit 'milestone=remote_inventory;state=blocked'
emit "application_host_inventory_wrapper=blocked;local_report=$report_path;next_gate=review_transport_or_inventory_block"
exit 1
