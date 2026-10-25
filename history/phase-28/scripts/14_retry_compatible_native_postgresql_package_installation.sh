#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Retry the compatible native PostgreSQL package installation after the
#   accepted read-only inspection proved that no partial install remains.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/14_retry_compatible_native_postgresql_package_installation.sh --install
#
# The retry uses transferred local package files with package sources disabled.
# It does not initialize a database or leave PostgreSQL running at boot.

usage() {
  sed -n '3,13p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --install                  Explicitly authorize the corrected package installation.' \
    '  --target VALUE             SSH destination or configured SSH alias.' \
    '  --expected-hostname NAME   Exact target short hostname.' \
    '  --expected-os-version VER  Exact expected Ubuntu major.minor version.' \
    '  --identity-file PATH       Optional explicit SSH private key.' \
    '  --bundle PATH              Accepted compatible bundle.' \
    '  --report-root PATH         Absolute local result directory.' \
    '  --validate-only            Validate accepted inputs without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly TARGET_HELPER="$SCRIPT_DIR/install-compatible-native-database-packages"
readonly ACCEPTED_INSPECTION_REPORT="$REPO_ROOT/local/reports/native-postgresql-package-installation-failure-inspection/native_postgresql_package_installation_failure_inspection_20261019T140223Z_GT7c9X.txt"
readonly ACCEPTED_INSPECTION_REPORT_SHA256="b93f01052b13e46f290d161cf49955f4ea0960cc1be9063ac3790b631ccd3c76"
readonly DEFAULT_BUNDLE="$REPO_ROOT/local/artifacts/native-postgresql-packages/native-postgresql-ubuntu24.04-amd64-pg16.15-pgvector0.8.7-compatible-20261019T132859Z.tar.gz"
readonly ACCEPTED_BUNDLE_SHA256="147dd47979d002ac6a7beabafd1a048cf6aa8da8cb6c54993c83b0cb74ab9e05"
readonly DEFAULT_REPORT_ROOT="$REPO_ROOT/local/reports/native-postgresql-compatible-package-installation-retry"

target="${APPLICATION_HOST_TARGET:-DankoSurface_EmceeDanko}"
expected_hostname="${APPLICATION_HOST_EXPECTED_HOSTNAME:-EmceeDanko}"
expected_os_version="${APPLICATION_HOST_EXPECTED_OS_VERSION:-24.04}"
identity_file="${APPLICATION_HOST_IDENTITY_FILE:-}"
bundle="$DEFAULT_BUNDLE"
report_root="$DEFAULT_REPORT_ROOT"
install_authorized=false
validate_only=false

while (( $# > 0 )); do
  case "$1" in
    --install) install_authorized=true; shift ;;
    --target) target="${2:-}"; shift 2 ;;
    --expected-hostname) expected_hostname="${2:-}"; shift 2 ;;
    --expected-os-version) expected_os_version="${2:-}"; shift 2 ;;
    --identity-file) identity_file="${2:-}"; shift 2 ;;
    --bundle) bundle="${2:-}"; shift 2 ;;
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
[[ -f "$ACCEPTED_INSPECTION_REPORT" && ! -L "$ACCEPTED_INSPECTION_REPORT" ]] || { printf 'BLOCKED: accepted Script 13 report is missing or unsafe.\n' >&2; exit 2; }
[[ -f "$bundle" && ! -L "$bundle" && -r "$bundle" ]] || { printf 'BLOCKED: accepted compatible bundle is missing or unsafe.\n' >&2; exit 2; }
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] \
    || { printf 'BLOCKED: explicit identity file is missing, unreadable, non-absolute, or a symlink.\n' >&2; exit 2; }
fi

for required in awk bash basename date grep mkdir mktemp rm scp sha256sum ssh tee timeout tr wc; do
  command -v "$required" >/dev/null 2>&1 || { printf 'BLOCKED: missing local command: %s\n' "$required" >&2; exit 2; }
done

bash -n "$TARGET_HELPER"
if grep -Eiq 'phase[-_ ]?[0-9]+|(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)|Danko|org[_ -]?lab|Agent|repository' "$TARGET_HELPER"; then
  printf 'BLOCKED: development or environment jargon found in neutral target helper.\n' >&2
  exit 2
fi

inspection_sha256="$(sha256sum "$ACCEPTED_INSPECTION_REPORT" | awk '{print $1}')"
[[ "$inspection_sha256" == "$ACCEPTED_INSPECTION_REPORT_SHA256" ]] || { printf 'BLOCKED: accepted Script 13 report checksum mismatch.\n' >&2; exit 2; }
for accepted_fact in \
  'exact_installed_count=1;absent_count=8;nonconfigured_count=0' \
  'dpkg_audit_lines=0;dpkg_audit_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855' \
  'support_simulation_exit_code=0;install_count=6;remove_count=0' \
  'automatic_cluster_creation=unavailable;postgresql_clusters=0;postgresql_port_5432=free' \
  'native_database_package_installation_failure_inspection=pass'; do
  grep -Fxq "$accepted_fact" "$ACCEPTED_INSPECTION_REPORT" || { printf 'BLOCKED: required Script 13 clean-state fact is absent.\n' >&2; exit 2; }
done
grep -Fq 'native_postgresql_package_installation_failure_inspection_wrapper=pass;' "$ACCEPTED_INSPECTION_REPORT" || { printf 'BLOCKED: accepted Script 13 wrapper pass marker is absent.\n' >&2; exit 2; }

bundle_sha256="$(sha256sum "$bundle" | awk '{print $1}')"
[[ "$bundle_sha256" == "$ACCEPTED_BUNDLE_SHA256" ]] || { printf 'BLOCKED: accepted compatible bundle checksum mismatch.\n' >&2; exit 2; }
bundle_name="$(basename "$bundle")"
[[ "$bundle_name" =~ ^[A-Za-z0-9._+-]+\.tar\.gz$ ]] || { printf 'BLOCKED: unsafe bundle basename.\n' >&2; exit 2; }

helper_sha256="$(sha256sum "$TARGET_HELPER" | awk '{print $1}')"
helper_bytes="$(wc -c <"$TARGET_HELPER" | tr -d ' ')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'compatible_native_postgresql_package_installation_retry_source=pass' \
    'target_contact=false' \
    'package_install=false' \
    "script_sha256=$script_sha256" \
    "helper_sha256=$helper_sha256" \
    "helper_bytes=$helper_bytes" \
    "accepted_inspection_report_sha256=$inspection_sha256" \
    "accepted_bundle_sha256=$bundle_sha256"
  exit 0
fi

[[ "$install_authorized" == true ]] || { printf 'BLOCKED: corrected package installation requires the explicit --install argument.\n' >&2; exit 2; }

mkdir -p -- "$report_root"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_root/native_postgresql_compatible_package_installation_retry_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/native-postgresql-compatible-package-installation-retry.XXXXXX)"
remote_root="/tmp/native-database-compatible-package-installation-retry-$timestamp-$$"
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
  if [[ "$work_root" == /tmp/native-postgresql-compatible-package-installation-retry.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

emit 'purpose=retry_verified_compatible_native_postgresql_package_installation_offline'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;helper_sha256=$helper_sha256;helper_bytes=$helper_bytes"
emit "accepted_inspection_report_sha256=$inspection_sha256;accepted_bundle_sha256=$bundle_sha256"
emit 'authorized_actions=stage_verified_temporary_bundle_and_helper_install_exact_native_packages_from_local_files_disable_automatic_cluster_creation_keep_postgresql_stopped_and_disabled_validate_runtime_retrieve_bounded_result_remove_temporary_files'
emit 'non_actions=no_network_package_source_no_database_initialization_no_database_schema_or_role_creation_no_secret_or_content_read'
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
    emit 'compatible_native_postgresql_package_installation_retry_wrapper=blocked;reason=ssh_master_start_failed;raw_stderr_retained=false'
    exit 1
  }
master_started=true
emit 'milestone=authentication;state=pass'

timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" \
  >"$work_root/create.stdout" 2>"$work_root/create.stderr" || {
    emit 'compatible_native_postgresql_package_installation_retry_wrapper=blocked;reason=remote_temporary_directory_not_created'
    exit 1
  }
remote_created=true

timeout --foreground 600 scp "${ssh_args[@]}" "$TARGET_HELPER" "$bundle" \
  "$target:$remote_root/" >"$work_root/scp.stdout" 2>"$work_root/scp.stderr" || {
    emit 'compatible_native_postgresql_package_installation_retry_wrapper=blocked;reason=temporary_payload_copy_failed'
    exit 1
  }

timeout --foreground 120 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && printf '%s  %s\n%s  %s\n' '$helper_sha256' install-compatible-native-database-packages '$bundle_sha256' '$bundle_name' | sha256sum --check --strict -" \
  >"$work_root/hash.stdout" 2>"$work_root/hash.stderr" || {
    emit 'compatible_native_postgresql_package_installation_retry_wrapper=blocked;reason=target_payload_hash_mismatch'
    exit 1
  }
emit 'milestone=target_payload_verification;state=pass'

emit 'milestone=corrected_local_package_installation;state=waiting_for_operator_sudo_if_prompted'
set +e
timeout --foreground 1800 ssh -tt "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && sudo -p '[sudo] password for corrected native database package installation: ' bash ./install-compatible-native-database-packages '$expected_hostname' '$expected_os_version' '$bundle_name' '$bundle_sha256' > native-database-compatible-package-installation-retry.txt" \
  < /dev/tty
remote_code=$?
set -e
emit "remote_execution_exit_code=$remote_code;raw_stderr_retained=false"

fetched_result="$work_root/native-database-compatible-package-installation-retry.txt"
if ! timeout --foreground 120 scp "${ssh_args[@]}" \
  "$target:$remote_root/native-database-compatible-package-installation-retry.txt" "$fetched_result" \
  >"$work_root/fetch.stdout" 2>"$work_root/fetch.stderr"; then
  emit 'compatible_native_postgresql_package_installation_retry_wrapper=blocked;reason=result_fetch_failed'
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

pass_markers="$(grep -Fxc 'native_database_compatible_package_installation=pass' "$fetched_result" || true)"
blocked_markers="$(grep -Ec '^native_database_compatible_package_installation=blocked;' "$fetched_result" || true)"
emit "installation_pass_markers=$pass_markers;installation_blocked_markers=$blocked_markers"

if (( remote_code == 0 )) && [[ "$output_contract" == pass && "$pass_markers" == 1 && "$blocked_markers" == 0 ]]; then
  emit 'milestone=corrected_local_package_installation;state=pass'
  emit "compatible_native_postgresql_package_installation_retry_wrapper=pass;local_report=$report_path;next_gate=review_installation_before_database_initialization"
  exit 0
fi

emit 'milestone=corrected_local_package_installation;state=blocked'
emit "compatible_native_postgresql_package_installation_retry_wrapper=blocked;local_report=$report_path;next_gate=review_installation_state_before_any_retry"
exit 1
