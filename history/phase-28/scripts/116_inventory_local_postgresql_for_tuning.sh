#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Determine the exact local PostgreSQL state that blocked the Ishikawa v1.1
#   tuning preflight before any schema install, ingestion, or database copy.
#
# Mental model:
#   Bind the blocked preflight receipt, inspect PostgreSQL as its local operating
#   system administrator, count only database objects and active corpus records,
#   and name the smallest safe next gate. If this command starts the manually
#   managed cluster for inspection, it restores the cluster to stopped on exit.
#
# Inputs or prerequisites:
#   The accepted blocked Script 115 report, PostgreSQL 16 main cluster, and an
#   attended local sudo authorization. No PostgreSQL password is requested.
#
# Outputs or artifact lane:
#   One content-free local inventory report. No document text, vector, password,
#   schema, role, corpus, service configuration, or package is changed.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/116_inventory_local_postgresql_for_tuning.sh --run

usage() {
  sed -n '3,27p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run                    Run the attended read-only local inventory.' \
    '  --validate-only          Validate source and bound evidence only.' \
    '  --expected-hostname NAME Exact expected local short hostname.' \
    '  --expected-os-version V  Exact expected Ubuntu major.minor version.' \
    '  --expected-architecture A Exact expected machine architecture.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly DECISION_LIST="$PHASE_ROOT/docs/ISHIKAWA_V1_1_TUNING_DECISIONS.md"
readonly SCRIPT_115_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.1-local-tuning-preflight/local_tuning_preflight_20261021T152829Z_TjgozF.txt"
readonly SCRIPT_115_REPORT_SHA256='b11867b1c86500f18dad4918fe60b2c75eeaf2c012ff1fd076e6db1adfb3e839'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.1-local-database-inventory"
readonly CLUSTER_VERSION='16'
readonly CLUSTER_NAME='main'
readonly DATABASE_NAME='rag_catalog'
readonly OWNER_ROLE='rag_owner'
readonly INGEST_ROLE='rag_ingest'
readonly RETRIEVAL_ROLE='rag_retrieval'

expected_hostname="${ISHIKAWA_TUNING_EXPECTED_HOSTNAME:-DankoSurface}"
expected_os_version="${ISHIKAWA_TUNING_EXPECTED_OS_VERSION:-24.04}"
expected_architecture="${ISHIKAWA_TUNING_EXPECTED_ARCHITECTURE:-aarch64}"
run_authorized=false
validate_only=false

while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --expected-hostname) expected_hostname="${2:-}"; shift 2 ;;
    --expected-os-version) expected_os_version="${2:-}"; shift 2 ;;
    --expected-architecture) expected_architecture="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_116_local_database_inventory=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_116_local_database_inventory=blocked;reason=mode_invalid\n' >&2
  exit 2
}
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || {
  printf 'script_116_local_database_inventory=blocked;reason=expected_hostname_invalid\n' >&2
  exit 2
}
[[ "$expected_os_version" =~ ^[0-9]{2}\.[0-9]{2}$ ]] || {
  printf 'script_116_local_database_inventory=blocked;reason=expected_os_version_invalid\n' >&2
  exit 2
}
[[ "$expected_architecture" =~ ^[A-Za-z0-9_-]+$ ]] || {
  printf 'script_116_local_database_inventory=blocked;reason=expected_architecture_invalid\n' >&2
  exit 2
}

for required in awk bash chmod date grep hostname mkdir mktemp pg_ctlcluster pg_isready pg_lsclusters psql rm sed sha256sum stat sudo tee uname; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_116_local_database_inventory=blocked;reason=local_command_missing;command=%s\n' "$required" >&2
    exit 2
  }
done
for required_file in "$DECISION_LIST" "$SCRIPT_115_REPORT"; do
  [[ -f "$required_file" && ! -L "$required_file" && -r "$required_file" ]] || {
    printf 'script_116_local_database_inventory=blocked;reason=required_input_unsafe\n' >&2
    exit 2
  }
done

[[ "$(sha256sum "$SCRIPT_115_REPORT" | awk '{print $1}')" == "$SCRIPT_115_REPORT_SHA256" ]] || {
  printf 'script_116_local_database_inventory=blocked;reason=script_115_report_identity_changed\n' >&2
  exit 2
}
grep -Fxq 'script_115_local_tuning_preflight=blocked;reason=local_postgresql_inventory_failed' "$SCRIPT_115_REPORT" || {
  printf 'script_116_local_database_inventory=blocked;reason=script_115_blocker_not_bound\n' >&2
  exit 2
}
grep -Fq '| `T08` |' "$DECISION_LIST" || {
  printf 'script_116_local_database_inventory=blocked;reason=tuning_decision_list_incomplete\n' >&2
  exit 2
}
grep -Fq '| OPEN |' "$DECISION_LIST" || {
  printf 'script_116_local_database_inventory=blocked;reason=local_corpus_decision_not_open\n' >&2
  exit 2
}

bash -n "${BASH_SOURCE[0]}"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
decision_list_sha256="$(sha256sum "$DECISION_LIST" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_local_postgresql_inventory_source' \
    "script_sha256=$script_sha256;decision_list_sha256=$decision_list_sha256;script_115_report_sha256=$SCRIPT_115_REPORT_SHA256" \
    'tuning_decision=T08;decision_state=open' \
    'sudo_used=false;database_contact=false;database_changed=false;service_changed=false;remote_contact=false;model_contact=false' \
    'script_116_local_database_inventory_source=pass'
  exit 0
fi

work_root="$(mktemp -d /tmp/ishikawa-script-116.XXXXXX)"
report_path=''
cluster_started_by_script=false
cluster_restored=false

emit() {
  if [[ -n "$report_path" ]]; then
    printf '%s\n' "$1" | tee -a "$report_path"
  else
    printf '%s\n' "$1"
  fi
}

cleanup() {
  local status="$?" stop_code=0
  trap - EXIT INT TERM
  set +e
  if [[ "$cluster_started_by_script" == true ]]; then
    sudo -n pg_ctlcluster "$CLUSTER_VERSION" "$CLUSTER_NAME" stop >/dev/null 2>&1 || stop_code=$?
    if (( stop_code == 0 )); then
      cluster_restored=true
      emit 'cleanup_local_cluster=restored_stopped'
    else
      emit "cleanup_local_cluster=review_required;exit_code=$stop_code"
      status=1
    fi
  else
    emit 'cleanup_local_cluster=not_required'
  fi
  [[ "$work_root" == /tmp/ishikawa-script-116.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  [[ -z "$report_path" ]] || chmod 0600 "$report_path" 2>/dev/null || true
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

block() {
  emit "script_116_local_database_inventory=blocked;reason=$1"
  exit 1
}

mkdir -p -- "$REPORT_ROOT"
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" ]] || block 'report_directory_unsafe'
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/local_database_inventory_${timestamp}_XXXXXX.txt")"
emit 'purpose=inventory_local_postgresql_before_tuning_corpus_establishment'
emit "started_utc=$timestamp;local_report=$report_path"
emit "script_sha256=$script_sha256;decision_list_sha256=$decision_list_sha256;script_115_report_sha256=$SCRIPT_115_REPORT_SHA256"
emit 'authorized_actions=attended_local_sudo_temporarily_start_postgresql_if_stopped_read_catalog_and_active_row_counts_restore_initial_stopped_state_retain_content_free_report'
emit 'non_actions=no_remote_access_no_model_contact_no_password_read_no_document_or_vector_read_no_role_database_schema_or_corpus_write_no_service_configuration_change_no_package_build'
emit 'operator_expectation=local_sudo_password_may_be_prompted;postgresql_password_prompt=false;estimated_duration_minutes=1'

actual_hostname="$(hostname -s)"
actual_architecture="$(uname -m)"
actual_os="$(. /etc/os-release && printf '%s|%s' "$ID" "$VERSION_ID")"
[[ "$actual_hostname" == "$expected_hostname" ]] || block 'hostname_mismatch'
[[ "$actual_os" == "ubuntu|$expected_os_version" ]] || block 'os_identity_mismatch'
[[ "$actual_architecture" == "$expected_architecture" ]] || block 'architecture_mismatch'
emit "milestone=local_host_identity;state=pass;hostname=$actual_hostname;os_id=ubuntu;os_version=$expected_os_version;architecture=$actual_architecture"

cluster_line="$(pg_lsclusters --no-header | awk -v version="$CLUSTER_VERSION" -v name="$CLUSTER_NAME" '$1 == version && $2 == name {print; found=1} END {if (!found) exit 1}')" \
  || block 'postgresql_cluster_missing'
read -r cluster_version cluster_name cluster_port cluster_status _ <<<"$cluster_line"
[[ "$cluster_version|$cluster_name|$cluster_port" == "$CLUSTER_VERSION|$CLUSTER_NAME|5432" ]] \
  || block 'postgresql_cluster_identity_mismatch'
[[ "$cluster_status" == online || "$cluster_status" == down ]] || block 'postgresql_cluster_status_invalid'
emit "milestone=local_cluster_discovery;state=pass;cluster=$cluster_version/$cluster_name;port=$cluster_port;initial_status=$cluster_status"

emit 'milestone=local_sudo;state=waiting_for_operator_if_prompted'
sudo -v || block 'sudo_authorization_failed'
emit 'milestone=local_sudo;state=pass'

if [[ "$cluster_status" == down ]]; then
  sudo -n pg_ctlcluster "$CLUSTER_VERSION" "$CLUSTER_NAME" start \
    >"$work_root/cluster-start.stdout" 2>"$work_root/cluster-start.stderr" \
    || block 'postgresql_temporary_start_failed'
  cluster_started_by_script=true
  for _ in 1 2 3 4 5; do
    if pg_isready -q -h 127.0.0.1 -p 5432 -d postgres -t 2; then break; fi
  done
  pg_isready -q -h 127.0.0.1 -p 5432 -d postgres -t 5 || block 'postgresql_not_ready_after_start'
  emit 'milestone=local_cluster_runtime;state=pass;action=temporarily_started;restore_on_exit=true'
else
  pg_isready -q -h 127.0.0.1 -p 5432 -d postgres -t 5 || block 'postgresql_online_but_unready'
  emit 'milestone=local_cluster_runtime;state=pass;action=reused_online;restore_on_exit=false'
fi

set +e
admin_inventory="$(sudo -n -u postgres psql \
  -X -q -A -t \
  -d postgres \
  -v ON_ERROR_STOP=1 \
  -c "SELECT concat_ws('|',
        current_setting('server_version_num'),
        current_setting('port'),
        EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$OWNER_ROLE'),
        COALESCE((SELECT rolcanlogin FROM pg_roles WHERE rolname = '$OWNER_ROLE'), false),
        EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$INGEST_ROLE'),
        COALESCE((SELECT rolcanlogin FROM pg_roles WHERE rolname = '$INGEST_ROLE'), false),
        EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$RETRIEVAL_ROLE'),
        COALESCE((SELECT rolcanlogin FROM pg_roles WHERE rolname = '$RETRIEVAL_ROLE'), false),
        EXISTS (SELECT 1 FROM pg_database WHERE datname = '$DATABASE_NAME'));" \
  2>"$work_root/admin-inventory.stderr")"
admin_status=$?
set -e
(( admin_status == 0 )) || block 'postgresql_admin_inventory_failed'

IFS='|' read -r server_version_num server_port owner_exists owner_login ingest_exists ingest_login retrieval_exists retrieval_login database_exists <<<"$admin_inventory"
[[ "$server_version_num" =~ ^16[0-9]{4}$ && "$server_port" == 5432 ]] || block 'postgresql_runtime_identity_mismatch'
for boolean_value in "$owner_exists" "$owner_login" "$ingest_exists" "$ingest_login" "$retrieval_exists" "$retrieval_login" "$database_exists"; do
  [[ "$boolean_value" == t || "$boolean_value" == f ]] || block 'postgresql_admin_inventory_invalid'
done
emit "milestone=application_identity_inventory;state=pass;database_exists=$database_exists;owner_role_exists=$owner_exists;owner_login=$owner_login;ingest_role_exists=$ingest_exists;ingest_login=$ingest_login;retrieval_role_exists=$retrieval_exists;retrieval_login=$retrieval_login"

if [[ "$database_exists" == f ]]; then
  if [[ "$owner_exists|$ingest_exists|$retrieval_exists" == 'f|f|f' ]]; then
    local_state='application_database_and_roles_absent'
    next_gate='bootstrap_local_roles_database_and_final_schema_then_ingest_synthetic_corpus'
  else
    local_state='partial_application_identity_state'
    next_gate='review_partial_local_roles_before_any_mutation'
  fi
  emit "local_database_state=$local_state;next_gate=$next_gate"
  emit "script_116_local_database_inventory=pass;local_state=$local_state;next_gate=$next_gate;local_report=$report_path"
  exit 0
fi

set +e
object_inventory="$(sudo -n -u postgres psql \
  -X -q -A -t \
  -d "$DATABASE_NAME" \
  -v ON_ERROR_STOP=1 \
  -c "SELECT concat_ws('|',
        EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'vector'),
        to_regclass('rag.schema_migrations') IS NOT NULL,
        to_regclass('rag_search.active_documents') IS NOT NULL,
        to_regclass('rag_search.active_chunks') IS NOT NULL,
        to_regclass('rag_search.active_citations') IS NOT NULL,
        to_regclass('rag_search.active_embeddings') IS NOT NULL,
        (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname IN ('rag', 'rag_private', 'rag_search')
            AND c.relkind IN ('r', 'p', 'v', 'm', 'S')));" \
  2>"$work_root/object-inventory.stderr")"
object_status=$?
set -e
(( object_status == 0 )) || block 'postgresql_object_inventory_failed'

IFS='|' read -r vector_exists ledger_exists active_documents_exists active_chunks_exists active_citations_exists active_embeddings_exists application_object_count <<<"$object_inventory"
for boolean_value in "$vector_exists" "$ledger_exists" "$active_documents_exists" "$active_chunks_exists" "$active_citations_exists" "$active_embeddings_exists"; do
  [[ "$boolean_value" == t || "$boolean_value" == f ]] || block 'postgresql_object_inventory_invalid'
done
[[ "$application_object_count" =~ ^[0-9]+$ ]] || block 'postgresql_object_count_invalid'
emit "milestone=application_object_inventory;state=pass;vector_extension=$vector_exists;schema_ledger=$ledger_exists;active_documents_view=$active_documents_exists;active_chunks_view=$active_chunks_exists;active_citations_view=$active_citations_exists;active_embeddings_view=$active_embeddings_exists;application_objects=$application_object_count"

expected_objects="$vector_exists|$ledger_exists|$active_documents_exists|$active_chunks_exists|$active_citations_exists|$active_embeddings_exists"
if [[ "$expected_objects" != 't|t|t|t|t|t' ]]; then
  if (( application_object_count == 0 )); then
    local_state='empty_application_database'
    next_gate='install_final_schema_then_ingest_synthetic_corpus'
  else
    local_state='partial_application_schema_state'
    next_gate='review_partial_local_schema_before_any_mutation'
  fi
  emit "local_database_state=$local_state;next_gate=$next_gate"
  emit "script_116_local_database_inventory=pass;local_state=$local_state;next_gate=$next_gate;local_report=$report_path"
  exit 0
fi

set +e
corpus_inventory="$(sudo -n -u postgres psql \
  -X -q -A -t \
  -d "$DATABASE_NAME" \
  -v ON_ERROR_STOP=1 \
  -c "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
      SELECT concat_ws('|',
        (SELECT coalesce(max(schema_version), 0) FROM rag.schema_migrations),
        (SELECT count(*) FROM rag_search.active_documents),
        (SELECT coalesce(sum(page_count), 0) FROM rag_search.active_documents),
        (SELECT count(*) FROM rag_search.active_chunks),
        (SELECT count(*) FROM rag_search.active_citations),
        (SELECT count(*) FROM rag_search.active_embeddings));
      ROLLBACK;" \
  2>"$work_root/corpus-inventory.stderr")"
corpus_status=$?
set -e
(( corpus_status == 0 )) || block 'postgresql_corpus_inventory_failed'

IFS='|' read -r schema_version documents pages chunks citations embeddings <<<"$corpus_inventory"
for count_value in "$schema_version" "$documents" "$pages" "$chunks" "$citations" "$embeddings"; do
  [[ "$count_value" =~ ^[0-9]+$ ]] || block 'postgresql_corpus_count_invalid'
done
emit "milestone=active_corpus_inventory;state=pass;schema_version=$schema_version;documents=$documents;pages=$pages;chunks=$chunks;citations=$citations;embeddings=$embeddings;transaction=repeatable_read_read_only"

if [[ "$schema_version|$documents|$pages|$chunks|$citations|$embeddings" == '4|6|27|126|126|126' ]]; then
  local_state='accepted_synthetic_corpus_present'
  if [[ "$owner_exists|$owner_login|$ingest_exists|$ingest_login|$retrieval_exists|$retrieval_login" == 't|f|t|t|t|t' ]]; then
    next_gate='verify_retrieval_credential_then_rerun_script_115'
  else
    next_gate='review_application_role_contract_before_tuning'
  fi
elif [[ "$documents|$pages|$chunks|$citations|$embeddings" == '0|0|0|0|0' && "$schema_version" == 4 ]]; then
  local_state='final_schema_present_synthetic_corpus_absent'
  next_gate='ingest_checksum_bound_synthetic_corpus_locally'
else
  local_state='noncanonical_local_corpus_inventory'
  next_gate='review_local_corpus_state_before_any_mutation'
fi

emit "local_database_state=$local_state;next_gate=$next_gate"
emit "script_116_local_database_inventory=pass;local_state=$local_state;next_gate=$next_gate;local_report=$report_path"
