#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Initialize the installed native PostgreSQL 16 cluster with local-only,
#   manual-start settings while leaving it stopped and boot-disabled.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/15_initialize_native_postgresql_cluster.sh --initialize
#
# This does not create the application database, roles, schema, extension,
# credentials, or start the PostgreSQL service.

usage() {
  sed -n '3,14p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --initialize               Explicitly authorize native cluster initialization.' \
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
readonly TARGET_HELPER="$SCRIPT_DIR/initialize-native-database-cluster"
readonly ACCEPTED_INSTALLATION_REPORT="$REPO_ROOT/local/reports/native-postgresql-compatible-package-installation-retry/native_postgresql_compatible_package_installation_retry_20261019T140848Z_yThBU6.txt"
readonly ACCEPTED_INSTALLATION_REPORT_SHA256="1b6c608eee754b0fe466a378bbf5836279e8bcee888b790d6c55652f1467245a"
readonly DEFAULT_REPORT_ROOT="$REPO_ROOT/local/reports/native-postgresql-cluster-initialization"

target="${APPLICATION_HOST_TARGET:-DankoSurface_EmceeDanko}"
expected_hostname="${APPLICATION_HOST_EXPECTED_HOSTNAME:-EmceeDanko}"
expected_os_version="${APPLICATION_HOST_EXPECTED_OS_VERSION:-24.04}"
identity_file="${APPLICATION_HOST_IDENTITY_FILE:-}"
report_root="$DEFAULT_REPORT_ROOT"
initialize_authorized=false
validate_only=false

while (( $# > 0 )); do
  case "$1" in
    --initialize) initialize_authorized=true; shift ;;
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
[[ -f "$ACCEPTED_INSTALLATION_REPORT" && ! -L "$ACCEPTED_INSTALLATION_REPORT" ]] || { printf 'BLOCKED: accepted Script 14 report is missing or unsafe.\n' >&2; exit 2; }
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

installation_sha256="$(sha256sum "$ACCEPTED_INSTALLATION_REPORT" | awk '{print $1}')"
[[ "$installation_sha256" == "$ACCEPTED_INSTALLATION_REPORT_SHA256" ]] || { printf 'BLOCKED: accepted Script 14 report checksum mismatch.\n' >&2; exit 2; }
for accepted_fact in \
  'internal_checksum_count=39;reviewed_package_count=9;installed_package_count=9' \
  'postgresql_version=16.15;psql_version=16.15;pgvector_version=0.8.7;psycopg_version=3.1.17' \
  'automatic_cluster_creation=off;postgresql_clusters=0;postgresql_port_5432=free' \
  'postgresql_service_active=inactive;postgresql_service_enabled=disabled;network_download=disabled' \
  'database_initialization=false;database_schema_or_role_creation=false' \
  'native_database_compatible_package_installation=pass' \
  'cleanup_remote_temporary_files=removed' \
  'cleanup_ssh_master_exit_code=0'; do
  grep -Fxq "$accepted_fact" "$ACCEPTED_INSTALLATION_REPORT" || { printf 'BLOCKED: required Script 14 installation fact is absent.\n' >&2; exit 2; }
done
grep -Fq 'compatible_native_postgresql_package_installation_retry_wrapper=pass;' "$ACCEPTED_INSTALLATION_REPORT" || { printf 'BLOCKED: accepted Script 14 wrapper pass marker is absent.\n' >&2; exit 2; }

helper_sha256="$(sha256sum "$TARGET_HELPER" | awk '{print $1}')"
helper_bytes="$(wc -c <"$TARGET_HELPER" | tr -d ' ')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'native_postgresql_cluster_initialization_source=pass' \
    'target_contact=false' \
    'database_cluster_initialization=false' \
    "script_sha256=$script_sha256" \
    "helper_sha256=$helper_sha256" \
    "helper_bytes=$helper_bytes" \
    "accepted_installation_report_sha256=$installation_sha256"
  exit 0
fi

[[ "$initialize_authorized" == true ]] || { printf 'BLOCKED: database cluster initialization requires the explicit --initialize argument.\n' >&2; exit 2; }

mkdir -p -- "$report_root"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_root/native_postgresql_cluster_initialization_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/native-postgresql-cluster-initialization.XXXXXX)"
remote_root="/tmp/native-database-cluster-initialization-$timestamp-$$"
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
  if [[ "$work_root" == /tmp/native-postgresql-cluster-initialization.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

emit 'purpose=initialize_native_postgresql_cluster_stopped_and_boot_disabled'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;helper_sha256=$helper_sha256;helper_bytes=$helper_bytes"
emit "accepted_installation_report_sha256=$installation_sha256"
emit 'authorized_actions=stage_verified_temporary_helper_initialize_postgresql_16_main_cluster_enable_data_checksums_set_loopback_binding_set_manual_start_validate_stopped_cluster_retrieve_bounded_result_remove_temporary_files'
emit 'non_actions=no_network_access_no_package_change_no_database_start_no_application_database_role_schema_extension_or_secret_creation'
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
    emit 'native_postgresql_cluster_initialization_wrapper=blocked;reason=ssh_master_start_failed;raw_stderr_retained=false'
    exit 1
  }
master_started=true
emit 'milestone=authentication;state=pass'

timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" \
  >"$work_root/create.stdout" 2>"$work_root/create.stderr" || {
    emit 'native_postgresql_cluster_initialization_wrapper=blocked;reason=remote_temporary_directory_not_created'
    exit 1
  }
remote_created=true

timeout --foreground 120 scp "${ssh_args[@]}" "$TARGET_HELPER" \
  "$target:$remote_root/" >"$work_root/scp.stdout" 2>"$work_root/scp.stderr" || {
    emit 'native_postgresql_cluster_initialization_wrapper=blocked;reason=temporary_helper_copy_failed'
    exit 1
  }

timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && printf '%s  %s\n' '$helper_sha256' initialize-native-database-cluster | sha256sum --check --strict -" \
  >"$work_root/hash.stdout" 2>"$work_root/hash.stderr" || {
    emit 'native_postgresql_cluster_initialization_wrapper=blocked;reason=target_helper_hash_mismatch'
    exit 1
  }
emit 'milestone=target_helper_verification;state=pass'

emit 'milestone=database_cluster_initialization;state=waiting_for_operator_sudo_if_prompted'
set +e
timeout --foreground 600 ssh -tt "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && sudo -p '[sudo] password for native database cluster initialization: ' bash ./initialize-native-database-cluster '$expected_hostname' '$expected_os_version' > native-database-cluster-initialization.txt" \
  < /dev/tty
remote_code=$?
set -e
emit "remote_execution_exit_code=$remote_code;raw_stderr_retained=false"

fetched_result="$work_root/native-database-cluster-initialization.txt"
if ! timeout --foreground 120 scp "${ssh_args[@]}" \
  "$target:$remote_root/native-database-cluster-initialization.txt" "$fetched_result" \
  >"$work_root/fetch.stdout" 2>"$work_root/fetch.stderr"; then
  emit 'native_postgresql_cluster_initialization_wrapper=blocked;reason=result_fetch_failed'
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

pass_markers="$(grep -Fxc 'native_database_cluster_initialization=pass' "$fetched_result" || true)"
blocked_markers="$(grep -Ec '^native_database_cluster_initialization=blocked;' "$fetched_result" || true)"
emit "initialization_pass_markers=$pass_markers;initialization_blocked_markers=$blocked_markers"

if (( remote_code == 0 )) && [[ "$output_contract" == pass && "$pass_markers" == 1 && "$blocked_markers" == 0 ]]; then
  emit 'milestone=database_cluster_initialization;state=pass'
  emit "native_postgresql_cluster_initialization_wrapper=pass;local_report=$report_path;next_gate=review_cluster_before_application_database_configuration"
  exit 0
fi

emit 'milestone=database_cluster_initialization;state=blocked'
emit "native_postgresql_cluster_initialization_wrapper=blocked;local_report=$report_path;next_gate=inspect_cluster_state_before_any_retry"
exit 1
