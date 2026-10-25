#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Configure the empty native PostgreSQL application database, isolated
#   owner/ingestion/retrieval roles, and pgvector extension.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/16_configure_native_postgresql_application_database.sh --configure
#
# The target prompts privately for distinct ingestion and retrieval role
# passwords. No application schema, tables, indexes, or content are created.

usage() {
  sed -n '3,13p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --configure                Explicitly authorize application-database configuration.' \
    '  --target VALUE             SSH destination or configured SSH alias.' \
    '  --expected-hostname NAME   Exact target short hostname.' \
    '  --expected-os-version VER  Exact expected Ubuntu major.minor version.' \
    '  --identity-file PATH       Optional explicit SSH private key.' \
    '  --database-name NAME       Application database name (default: rag_catalog).' \
    '  --owner-role NAME          Non-login owner role (default: rag_owner).' \
    '  --ingest-role NAME         Ingestion login role (default: rag_ingest).' \
    '  --retrieval-role NAME      Read-only retrieval login role (default: rag_retrieval).' \
    '  --report-root PATH         Absolute local result directory.' \
    '  --validate-only            Validate accepted inputs without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly TARGET_HELPER="$SCRIPT_DIR/configure-native-application-database"
readonly ACCEPTED_CLUSTER_REPORT="$REPO_ROOT/local/reports/native-postgresql-cluster-initialization/native_postgresql_cluster_initialization_20261019T142059Z_jfuzlm.txt"
readonly ACCEPTED_CLUSTER_REPORT_SHA256="4e94ef5299ee2980da0e3b5332259d97e900708412dbd81a5ebacb555aeb9a5c"
readonly DEFAULT_REPORT_ROOT="$REPO_ROOT/local/reports/native-postgresql-application-database-configuration"

target="${APPLICATION_HOST_TARGET:-DankoSurface_EmceeDanko}"
expected_hostname="${APPLICATION_HOST_EXPECTED_HOSTNAME:-EmceeDanko}"
expected_os_version="${APPLICATION_HOST_EXPECTED_OS_VERSION:-24.04}"
identity_file="${APPLICATION_HOST_IDENTITY_FILE:-}"
database_name="${APPLICATION_DATABASE_NAME:-rag_catalog}"
owner_role="${APPLICATION_DATABASE_OWNER_ROLE:-rag_owner}"
ingest_role="${APPLICATION_DATABASE_INGEST_ROLE:-rag_ingest}"
retrieval_role="${APPLICATION_DATABASE_RETRIEVAL_ROLE:-rag_retrieval}"
report_root="$DEFAULT_REPORT_ROOT"
configure_authorized=false
validate_only=false

while (( $# > 0 )); do
  case "$1" in
    --configure) configure_authorized=true; shift ;;
    --target) target="${2:-}"; shift 2 ;;
    --expected-hostname) expected_hostname="${2:-}"; shift 2 ;;
    --expected-os-version) expected_os_version="${2:-}"; shift 2 ;;
    --identity-file) identity_file="${2:-}"; shift 2 ;;
    --database-name) database_name="${2:-}"; shift 2 ;;
    --owner-role) owner_role="${2:-}"; shift 2 ;;
    --ingest-role) ingest_role="${2:-}"; shift 2 ;;
    --retrieval-role) retrieval_role="${2:-}"; shift 2 ;;
    --report-root) report_root="${2:-}"; shift 2 ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'ERROR: unsupported argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$target" =~ ^[A-Za-z0-9_@.:-]+$ ]] || { printf 'BLOCKED: invalid SSH target or alias.\n' >&2; exit 2; }
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || { printf 'BLOCKED: invalid expected hostname.\n' >&2; exit 2; }
[[ "$expected_os_version" =~ ^[0-9]{2}\.[0-9]{2}$ ]] || { printf 'BLOCKED: invalid expected Ubuntu version.\n' >&2; exit 2; }
for identifier in "$database_name" "$owner_role" "$ingest_role" "$retrieval_role"; do
  [[ "$identifier" =~ ^[a-z][a-z0-9_]{0,62}$ ]] || { printf 'BLOCKED: invalid database or role identifier.\n' >&2; exit 2; }
done
[[ "$database_name" != "$owner_role" && "$database_name" != "$ingest_role" \
    && "$database_name" != "$retrieval_role" && "$owner_role" != "$ingest_role" \
    && "$owner_role" != "$retrieval_role" && "$ingest_role" != "$retrieval_role" ]] \
  || { printf 'BLOCKED: database and role identifiers must be distinct.\n' >&2; exit 2; }
[[ "$report_root" == /* && ! -L "$report_root" ]] || { printf 'BLOCKED: --report-root must be absolute and not a symlink.\n' >&2; exit 2; }
[[ -f "$TARGET_HELPER" && ! -L "$TARGET_HELPER" && -r "$TARGET_HELPER" ]] || { printf 'BLOCKED: neutral target helper is missing or unsafe.\n' >&2; exit 2; }
[[ -f "$ACCEPTED_CLUSTER_REPORT" && ! -L "$ACCEPTED_CLUSTER_REPORT" ]] || { printf 'BLOCKED: accepted Script 15 report is missing or unsafe.\n' >&2; exit 2; }
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

cluster_report_sha256="$(sha256sum "$ACCEPTED_CLUSTER_REPORT" | awk '{print $1}')"
[[ "$cluster_report_sha256" == "$ACCEPTED_CLUSTER_REPORT_SHA256" ]] || { printf 'BLOCKED: accepted Script 15 report checksum mismatch.\n' >&2; exit 2; }
for accepted_fact in \
  'cluster_version=16;cluster_name=main;cluster_port=5432;cluster_status=down' \
  'cluster_owner=postgres;cluster_data_directory=/var/lib/postgresql/16/main;cluster_log_file=/var/log/postgresql/postgresql-16-main.log' \
  'cluster_locale=C.utf8;cluster_encoding=UTF8;data_page_checksum_version=1;database_cluster_state=shut_down' \
  'cluster_start_policy=manual;listen_addresses=127.0.0.1;password_encryption=scram-sha-256' \
  'local_authentication=peer;host_authentication=scram-sha-256' \
  'application_database_created=false;application_role_created=false;application_schema_created=false;pgvector_extension_created=false;secret_created=false' \
  'native_database_cluster_initialization=pass' \
  'cleanup_remote_temporary_files=removed' \
  'cleanup_ssh_master_exit_code=0'; do
  grep -Fxq "$accepted_fact" "$ACCEPTED_CLUSTER_REPORT" || { printf 'BLOCKED: required Script 15 cluster fact is absent.\n' >&2; exit 2; }
done
grep -Fq 'native_postgresql_cluster_initialization_wrapper=pass;' "$ACCEPTED_CLUSTER_REPORT" || { printf 'BLOCKED: accepted Script 15 wrapper pass marker is absent.\n' >&2; exit 2; }

helper_sha256="$(sha256sum "$TARGET_HELPER" | awk '{print $1}')"
helper_bytes="$(wc -c <"$TARGET_HELPER" | tr -d ' ')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'native_postgresql_application_database_configuration_source=pass' \
    'target_contact=false' \
    'application_database_configuration=false' \
    "database_name=$database_name" \
    "owner_role=$owner_role" \
    "ingest_role=$ingest_role" \
    "retrieval_role=$retrieval_role" \
    "script_sha256=$script_sha256" \
    "helper_sha256=$helper_sha256" \
    "helper_bytes=$helper_bytes" \
    "accepted_cluster_report_sha256=$cluster_report_sha256"
  exit 0
fi

[[ "$configure_authorized" == true ]] || { printf 'BLOCKED: application-database configuration requires the explicit --configure argument.\n' >&2; exit 2; }

mkdir -p -- "$report_root"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_root/native_postgresql_application_database_configuration_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/native-postgresql-application-database-configuration.XXXXXX)"
remote_root="/tmp/native-application-database-configuration-$timestamp-$$"
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
  if [[ "$work_root" == /tmp/native-postgresql-application-database-configuration.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

emit 'purpose=configure_empty_native_postgresql_application_database_and_roles'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;helper_sha256=$helper_sha256;helper_bytes=$helper_bytes"
emit "accepted_cluster_report_sha256=$cluster_report_sha256"
emit "database_name=$database_name;owner_role=$owner_role;ingest_role=$ingest_role;retrieval_role=$retrieval_role"
emit 'authorized_actions=stage_verified_temporary_helper_prompt_for_two_role_secrets_start_existing_local_cluster_create_empty_application_database_create_isolated_roles_enable_vector_extension_verify_configuration_stop_cluster_retrieve_bounded_result_remove_temporary_files'
emit 'non_actions=no_network_access_no_package_change_no_application_schema_table_index_or_content_creation_no_secret_persistence_or_output_no_service_enablement'
emit "selected_target=$target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version"
emit 'operator_expectation=ssh_key_passphrase_up_to_once;target_sudo_password_may_be_prompted;two_nonempty_role_passwords_and_confirmations_required'

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
    emit 'native_postgresql_application_database_configuration_wrapper=blocked;reason=ssh_master_start_failed;raw_stderr_retained=false'
    exit 1
  }
master_started=true
emit 'milestone=authentication;state=pass'

timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" \
  >"$work_root/create.stdout" 2>"$work_root/create.stderr" || {
    emit 'native_postgresql_application_database_configuration_wrapper=blocked;reason=remote_temporary_directory_not_created'
    exit 1
  }
remote_created=true

timeout --foreground 120 scp "${ssh_args[@]}" "$TARGET_HELPER" \
  "$target:$remote_root/" >"$work_root/scp.stdout" 2>"$work_root/scp.stderr" || {
    emit 'native_postgresql_application_database_configuration_wrapper=blocked;reason=temporary_helper_copy_failed'
    exit 1
  }

timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && printf '%s  %s\n' '$helper_sha256' configure-native-application-database | sha256sum --check --strict -" \
  >"$work_root/hash.stdout" 2>"$work_root/hash.stderr" || {
    emit 'native_postgresql_application_database_configuration_wrapper=blocked;reason=target_helper_hash_mismatch'
    exit 1
  }
emit 'milestone=target_helper_verification;state=pass'

emit 'milestone=application_database_configuration;state=waiting_for_operator_sudo_and_role_secrets_if_prompted'
set +e
timeout --foreground 900 ssh -tt "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && sudo -p '[sudo] password for native application database configuration: ' bash ./configure-native-application-database '$expected_hostname' '$expected_os_version' '$database_name' '$owner_role' '$ingest_role' '$retrieval_role' > native-application-database-configuration.txt" \
  < /dev/tty
remote_code=$?
set -e
emit "remote_execution_exit_code=$remote_code;raw_stderr_retained=false"

fetched_result="$work_root/native-application-database-configuration.txt"
if ! timeout --foreground 120 scp "${ssh_args[@]}" \
  "$target:$remote_root/native-application-database-configuration.txt" "$fetched_result" \
  >"$work_root/fetch.stdout" 2>"$work_root/fetch.stderr"; then
  emit 'native_postgresql_application_database_configuration_wrapper=blocked;reason=result_fetch_failed'
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

pass_markers="$(grep -Fxc 'native_application_database_configuration=pass' "$fetched_result" || true)"
blocked_markers="$(grep -Ec '^native_application_database_configuration=blocked;' "$fetched_result" || true)"
emit "configuration_pass_markers=$pass_markers;configuration_blocked_markers=$blocked_markers"

if (( remote_code == 0 )) && [[ "$output_contract" == pass && "$pass_markers" == 1 && "$blocked_markers" == 0 ]]; then
  emit 'milestone=application_database_configuration;state=pass'
  emit "native_postgresql_application_database_configuration_wrapper=pass;local_report=$report_path;next_gate=review_database_configuration_before_sql_migration_implementation"
  exit 0
fi

emit 'milestone=application_database_configuration;state=blocked'
emit "native_postgresql_application_database_configuration_wrapper=blocked;local_report=$report_path;next_gate=inspect_database_configuration_before_any_retry"
exit 1
