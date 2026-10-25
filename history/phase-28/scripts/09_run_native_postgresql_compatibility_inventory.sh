#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Stream a neutral read-only helper to capture the exact libllvm19 candidate
#   required to evaluate a compatible native PostgreSQL/pgvector package set.
#
# Default execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/09_run_native_postgresql_compatibility_inventory.sh
#
# This script performs no apt update, download, installation, database action,
# service action, configuration change, sudo operation, or target-file write.

usage() {
  sed -n '3,14p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --target VALUE             SSH destination or configured SSH alias.' \
    '  --expected-hostname NAME   Exact target short hostname.' \
    '  --expected-os-version VER  Exact expected Ubuntu major.minor version.' \
    '  --identity-file PATH       Optional explicit SSH private key.' \
    '  --report-root PATH         Absolute local result directory.' \
    '  --validate-only            Validate source without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly TARGET_HELPER="$SCRIPT_DIR/inspect-native-database-compatibility"
readonly BLOCKED_BUNDLE="$REPO_ROOT/local/artifacts/native-postgresql-packages/native-postgresql-ubuntu24.04-amd64-pgvector0.8.7-20261019T035159Z.tar.gz"
readonly BLOCKED_BUNDLE_SHA256="d091792ace6a1f5b1ac76d686e2464f52e61240c47e44eaf74670eaef0dfbff5"
readonly SCRIPT08_REPORT="$REPO_ROOT/local/reports/native-postgresql-installation-preflight/native_postgresql_installation_preflight_20261019T040313Z_5w0ido.txt"
readonly SCRIPT08_REPORT_SHA256="a26280559850c154594a8ec4b32a6a57cdd8ed828749796cc9b337edca4842e4"
readonly DEFAULT_REPORT_ROOT="$REPO_ROOT/local/reports/native-postgresql-compatibility-inventory"

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
[[ -f "$TARGET_HELPER" && ! -L "$TARGET_HELPER" && -r "$TARGET_HELPER" ]] || { printf 'BLOCKED: neutral compatibility helper is missing or unsafe.\n' >&2; exit 2; }
[[ -f "$BLOCKED_BUNDLE" && ! -L "$BLOCKED_BUNDLE" ]] || { printf 'BLOCKED: compatibility-blocked bundle is missing or unsafe.\n' >&2; exit 2; }
[[ -f "$SCRIPT08_REPORT" && ! -L "$SCRIPT08_REPORT" ]] || { printf 'BLOCKED: reviewed Script 08 report is missing or unsafe.\n' >&2; exit 2; }
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] \
    || { printf 'BLOCKED: explicit identity file is missing, unreadable, non-absolute, or a symlink.\n' >&2; exit 2; }
fi

for required in awk bash date dpkg-deb grep mkdir mktemp rm sha256sum ssh tee timeout tr wc; do
  command -v "$required" >/dev/null 2>&1 || { printf 'BLOCKED: missing local command: %s\n' "$required" >&2; exit 2; }
done
bash -n "$TARGET_HELPER"
if grep -Eiq 'phase[-_ ]?[0-9]+|(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)|Danko|org[_ -]?lab|Agent|repository' "$TARGET_HELPER"; then
  printf 'BLOCKED: development or environment jargon found in neutral target helper.\n' >&2
  exit 2
fi

bundle_sha256="$(sha256sum "$BLOCKED_BUNDLE" | awk '{print $1}')"
report_sha256="$(sha256sum "$SCRIPT08_REPORT" | awk '{print $1}')"
[[ "$bundle_sha256" == "$BLOCKED_BUNDLE_SHA256" ]] || { printf 'BLOCKED: blocked bundle checksum mismatch.\n' >&2; exit 2; }
[[ "$report_sha256" == "$SCRIPT08_REPORT_SHA256" ]] || { printf 'BLOCKED: Script 08 report checksum mismatch.\n' >&2; exit 2; }

artifact_dir="${BLOCKED_BUNDLE%.tar.gz}"
server_deb="$artifact_dir/packages/postgresql-16_16.15-0ubuntu0.24.04.1_amd64.deb"
vector_deb="$artifact_dir/packages/postgresql-16-pgvector_0.8.7-1.pgdg24.04+1_amd64.deb"
[[ -f "$server_deb" && -f "$vector_deb" ]] || { printf 'BLOCKED: exact compatibility package controls are missing.\n' >&2; exit 2; }
[[ "$(dpkg-deb -f "$server_deb" Provides)" == *'postgresql-16-jit-llvm (= 17)'* ]] \
  || { printf 'BLOCKED: expected Ubuntu PostgreSQL JIT provider is absent.\n' >&2; exit 2; }
[[ "$(dpkg-deb -f "$vector_deb" Breaks)" == *'postgresql-16-jit-llvm (<< 19)'* ]] \
  || { printf 'BLOCKED: expected pgvector JIT compatibility boundary is absent.\n' >&2; exit 2; }

helper_sha256="$(sha256sum "$TARGET_HELPER" | awk '{print $1}')"
helper_bytes="$(wc -c <"$TARGET_HELPER" | tr -d ' ')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'native_postgresql_compatibility_inventory_source=pass' \
    'target_contact=false' \
    'package_download=false' \
    'package_install=false' \
    "script_sha256=$script_sha256" \
    "helper_sha256=$helper_sha256" \
    "helper_bytes=$helper_bytes" \
    "blocked_bundle_sha256=$bundle_sha256" \
    "script08_report_sha256=$report_sha256"
  exit 0
fi

mkdir -p -- "$report_root"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_root/native_postgresql_compatibility_inventory_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/native-postgresql-compatibility-inventory.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/native-postgresql-compatibility-inventory.* && -d "$work_root" ]]; then
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

emit 'purpose=inventory_native_postgresql_compatibility_without_mutation'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;helper_sha256=$helper_sha256;helper_bytes=$helper_bytes"
emit "blocked_bundle_sha256=$bundle_sha256;script08_report_sha256=$report_sha256"
emit 'compatibility_block=pgvector_requires_jit_19;captured_postgresql_provides_jit_17'
emit 'authorized_actions=read_host_os_apt_candidate_and_capacity_metadata'
emit 'non_actions=no_apt_update_no_network_download_no_package_install_no_database_initialization_no_service_or_configuration_change_no_secret_or_content_read_no_target_file_write'
emit "selected_target=$target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version"

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

emit 'milestone=remote_inventory;state=start'
set +e
timeout --foreground 180 ssh "${ssh_args[@]}" "$target" \
  -- /bin/bash -s -- "$expected_hostname" "$expected_os_version" \
  <"$TARGET_HELPER" >"$work_root/remote.stdout" 2>"$work_root/remote.stderr"
remote_code=$?
set -e

output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] \
      || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then
    output_contract=blocked
    continue
  fi
  emit "$line"
done <"$work_root/remote.stdout"
emit "remote_execution_exit_code=$remote_code;remote_output_contract=$output_contract"

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
  elif (( remote_code == 124 )); then
    classification=timeout
  fi
  emit "transport_classification=$classification;raw_stderr_retained=false"
fi

pass_markers="$(grep -Fxc 'native_database_compatibility_inventory=pass' "$work_root/remote.stdout" || true)"
blocked_markers="$(grep -Ec '^native_database_compatibility_inventory=blocked;' "$work_root/remote.stdout" || true)"
emit "inventory_pass_markers=$pass_markers;inventory_blocked_markers=$blocked_markers"

if (( remote_code == 0 )) && [[ "$output_contract" == pass && "$pass_markers" == 1 && "$blocked_markers" == 0 ]]; then
  emit 'milestone=remote_inventory;state=pass'
  emit "native_postgresql_compatibility_inventory_wrapper=pass;local_report=$report_path;next_gate=review_exact_compatible_package_coordinates_before_capture"
  exit 0
fi

emit 'milestone=remote_inventory;state=blocked'
emit "native_postgresql_compatibility_inventory_wrapper=blocked;local_report=$report_path;next_gate=review_inventory_block"
exit 1
