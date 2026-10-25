#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Launch the Script 153-qualified Ishikawa v1.3 candidate on DankoSurface for
#   interactive browser review without installing or packaging the candidate.
#
# Mental model:
#   Bind the accepted Script 153 qualification receipt, require the operator's existing
#   Gemma and Nomic loopback forwards, start native PostgreSQL only when needed,
#   prove the complete staged-source and database contracts, stage the Retrieval
#   API privately under /tmp, and run the working Next.js source from the existing
#   architecture-matched image. Keep this terminal attached as the preview
#   supervisor; Ctrl+C stops the preview and removes temporary state. UI source
#   edits remain eligible for Next.js hot reload.
#
# Inputs or prerequisites:
#   DankoSurface on Ubuntu 24.04 ARM64, the accepted local six-document corpus,
#   existing Gemma/Nomic forwards on ports 8000/8001, the local Node 24 image,
#   and three operator-entered runtime credentials. This script never creates
#   port forwards and never reads credentials from command-line arguments.
#
# Outputs or artifact lane:
#   One content-free report under local/reports/ishikawa-v1.3-sql-corrected-local-preview.
#   Candidate runtime files and logs exist only in a private /tmp directory and
#   are removed at shutdown. No image is pulled or changed, no remote host is
#   contacted, and no deployment package or accepted release is changed.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/154_launch_sql_corrected_local_v1_3_preview.sh --run
#   Press Ctrl+C after browser testing to stop and clean up the preview.

usage() {
  sed -n '3,32p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Launch and supervise the local v1.3 preview.' \
    '  --validate-only Validate frozen inputs and script structure only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_SOURCE_ROOT="$PRODUCT_ROOT/application/python/ishikawa"
readonly WEB_ROOT="$PRODUCT_ROOT/application/web"
readonly CONFIG_TEMPLATE_ROOT="$PRODUCT_ROOT/config/templates"
readonly SERVICE_ENTRYPOINT="$PRODUCT_ROOT/scripts/ishikawa-retrieval-api"
readonly SCRIPT_153="$SCRIPT_DIR/153_qualify_v1_3_title_routing_sql_correction.sh"
readonly SCRIPT_153_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.3-title-routing-sql-correction/v1_3_title_routing_sql_correction_20261022T032214Z_ZtNfXY.txt"
readonly SCRIPT_153_REPORT_SHA256='d7ee8535e27d7734832e0b5b34a1409bbd0499d5c6eec57cb85e070200f5bd07'
readonly SCRIPT_153_SHA256='1d23403474c9ca8c94c3609e15672d4e485f02b6c369ad246f1cfa65a0cde3e4'
readonly DECISION_SHA256='1f3bd36859700e3697ca9753916f452f0b9ff609129cabfc9e515a5e5593aad3'
readonly FULL_CANDIDATE_MANIFEST_SHA256='57ce185b4987c15fa382806154355545f0a0b49033a59ddeb5bf451acaf9a038'
readonly FULL_CANDIDATE_FILE_COUNT=85
readonly CORPUS_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.1-local-tuning-corpus/local_tuning_corpus_20261021T165048Z_QfXYrD.txt"
readonly CORPUS_REPORT_SHA256='5fab929e8e2cf838adc35d7c41d2dea5ed02f9670c9254ddf7f794c8e759ddff'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.3-sql-corrected-local-preview"
readonly POSTGRESQL_UNIT='postgresql@16-main.service'
readonly WEB_CONTAINER='ishikawa-v1-3-sql-corrected-preview'
readonly GEMMA_HEALTH_URL='http://127.0.0.1:8000/health'
readonly NOMIC_HEALTH_URL='http://127.0.0.1:8001/health'
readonly RETRIEVAL_BASE_URL='http://127.0.0.1:1384'
readonly WEB_BASE_URL='http://127.0.0.1:3000'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_154_sql_corrected_local_v1_3_preview=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_154_sql_corrected_local_v1_3_preview=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required_command in \
  awk basename bash chmod curl date dirname docker dpkg env find grep head hostname \
  install kill mapfile mkdir mktemp pg_isready pg_lsclusters psql python3 rm sed \
  sha256sum sleep sort stat sudo systemctl tail tee tr uname; do
  command -v "$required_command" >/dev/null 2>&1 || {
    printf 'script_154_sql_corrected_local_v1_3_preview=blocked;reason=local_command_missing;command=%s\n' \
      "$required_command" >&2
    exit 2
  }
done

readonly -a REQUIRED_PATHS=(
  "$SCRIPT_153"
  "$SCRIPT_153_REPORT"
  "$CORPUS_REPORT"
  "$SERVICE_ENTRYPOINT"
  "$PYTHON_SOURCE_ROOT/__init__.py"
  "$CONFIG_TEMPLATE_ROOT/product.yaml"
  "$CONFIG_TEMPLATE_ROOT/deployment.yaml"
  "$CONFIG_TEMPLATE_ROOT/runtime_dependencies.yaml"
  "$WEB_ROOT/app"
  "$WEB_ROOT/components"
  "$WEB_ROOT/lib"
  "$WEB_ROOT/public"
  "$WEB_ROOT/package.json"
  "$WEB_ROOT/next.config.mjs"
)
for required_path in "${REQUIRED_PATHS[@]}"; do
  [[ -e "$required_path" && ! -L "$required_path" && -r "$required_path" ]] || {
    printf 'script_154_sql_corrected_local_v1_3_preview=blocked;reason=required_input_unsafe\n' >&2
    exit 2
  }
done

[[ "$(sha256sum "$SCRIPT_153_REPORT" | awk '{print $1}')" == "$SCRIPT_153_REPORT_SHA256" ]] || {
  printf 'script_154_sql_corrected_local_v1_3_preview=blocked;reason=script_153_receipt_checksum_mismatch\n' >&2
  exit 1
}
grep -Fq \
  "script_sha256=$SCRIPT_153_SHA256;decision_sha256=$DECISION_SHA256" \
  "$SCRIPT_153_REPORT" || {
    printf 'script_154_sql_corrected_local_v1_3_preview=blocked;reason=script_153_identity_mismatch\n' >&2
    exit 1
  }
grep -Fxq \
  "candidate_manifest_sha256=$FULL_CANDIDATE_MANIFEST_SHA256;candidate_files=$FULL_CANDIDATE_FILE_COUNT" \
  "$SCRIPT_153_REPORT" || {
    printf 'script_154_sql_corrected_local_v1_3_preview=blocked;reason=script_153_candidate_identity_mismatch\n' >&2
    exit 1
  }
grep -Fq 'script_153_v1_3_title_routing_sql_correction=pass;next_gate=launch_sql_corrected_local_v1_3_preview;' \
  "$SCRIPT_153_REPORT" || {
    printf 'script_154_sql_corrected_local_v1_3_preview=blocked;reason=script_153_not_accepted\n' >&2
    exit 1
  }
grep -Fxq \
  'explicit_title_sql=pass;select_distinct=false;longest_title_first=true;frozen_behavior_changed=false' \
  "$SCRIPT_153_REPORT" || {
    printf 'script_154_sql_corrected_local_v1_3_preview=blocked;reason=script_153_sql_correction_not_accepted\n' >&2
    exit 1
  }
[[ "$(sha256sum "$CORPUS_REPORT" | awk '{print $1}')" == "$CORPUS_REPORT_SHA256" ]] || {
  printf 'script_154_sql_corrected_local_v1_3_preview=blocked;reason=local_corpus_receipt_checksum_mismatch\n' >&2
  exit 1
}
grep -Fq 'script_117_local_tuning_corpus=pass;' "$CORPUS_REPORT" || {
  printf 'script_154_sql_corrected_local_v1_3_preview=blocked;reason=local_corpus_not_accepted\n' >&2
  exit 1
}

validation_output="$({ bash "$SCRIPT_153" --validate-only; } 2>&1)" || {
  printf 'script_154_sql_corrected_local_v1_3_preview=blocked;reason=current_sql_corrected_v1_3_source_validation_failed\n' >&2
  exit 1
}
grep -Fxq \
  "script_sha256=$SCRIPT_153_SHA256;decision_sha256=$DECISION_SHA256" \
  <<<"$validation_output" || {
    printf 'script_154_sql_corrected_local_v1_3_preview=blocked;reason=current_sql_corrected_v1_3_source_identity_mismatch\n' >&2
    exit 1
  }
grep -Fxq \
  "candidate_manifest_sha256=$FULL_CANDIDATE_MANIFEST_SHA256;candidate_files=$FULL_CANDIDATE_FILE_COUNT" \
  <<<"$validation_output" || {
    printf 'script_154_sql_corrected_local_v1_3_preview=blocked;reason=current_sql_corrected_v1_3_candidate_identity_mismatch\n' >&2
    exit 1
  }
grep -Fxq 'script_153_v1_3_title_routing_sql_correction=pass' <<<"$validation_output" || {
  printf 'script_154_sql_corrected_local_v1_3_preview=blocked;reason=current_sql_corrected_v1_3_source_not_valid\n' >&2
  exit 1
}

mapfile -t full_candidate_files < <(
  {
    find \
      "$PYTHON_SOURCE_ROOT" \
      "$WEB_ROOT/app" \
      "$WEB_ROOT/components" \
      "$WEB_ROOT/lib" \
      "$WEB_ROOT/public" \
      "$WEB_ROOT/tests" \
      "$CONFIG_TEMPLATE_ROOT" \
      -type f -print
    printf '%s\n' \
      "$WEB_ROOT/package.json" \
      "$WEB_ROOT/next.config.mjs" \
      "$SERVICE_ENTRYPOINT"
  } | LC_ALL=C sort
)
(( ${#full_candidate_files[@]} == FULL_CANDIDATE_FILE_COUNT )) || {
  printf 'script_154_sql_corrected_local_v1_3_preview=blocked;reason=full_candidate_file_count_mismatch\n' >&2
  exit 1
}
for candidate_file in "${full_candidate_files[@]}"; do
  [[ -f "$candidate_file" && ! -L "$candidate_file" && -r "$candidate_file" ]] || {
    printf 'script_154_sql_corrected_local_v1_3_preview=blocked;reason=full_candidate_file_unsafe\n' >&2
    exit 1
  }
done
full_candidate_manifest_sha256="$({
  for candidate_file in "${full_candidate_files[@]}"; do
    candidate_relative_path="${candidate_file#"$PRODUCT_ROOT/"}"
    printf '%s  %s\n' \
      "$(sha256sum "$candidate_file" | awk '{print $1}')" \
      "$candidate_relative_path"
  done
} | sha256sum | awk '{print $1}')"
[[ "$full_candidate_manifest_sha256" == "$FULL_CANDIDATE_MANIFEST_SHA256" ]] || {
  printf 'script_154_sql_corrected_local_v1_3_preview=blocked;reason=full_candidate_identity_mismatch\n' >&2
  exit 1
}
bash -n "${BASH_SOURCE[0]}" "$SCRIPT_153" "$SERVICE_ENTRYPOINT"

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_sql_corrected_local_v1_3_preview_launcher' \
    "script_sha256=$script_sha256;script_153_report_sha256=$SCRIPT_153_REPORT_SHA256;decision_sha256=$DECISION_SHA256" \
    "full_candidate_manifest_sha256=$full_candidate_manifest_sha256;full_candidate_files=$FULL_CANDIDATE_FILE_COUNT" \
    "local_corpus_report_sha256=$CORPUS_REPORT_SHA256" \
    'target_contact=false;database_contact=false;model_contact=false;container_started=false;service_changed=false;package_changed=false' \
    'script_154_sql_corrected_local_v1_3_preview=pass'
  exit 0
fi

report_path=''
work_root=''
installed_root=''
service_pid=''
web_client_pid=''
postgresql_started=false
service_started=false
web_started=false
preview_ready=false
operator_stop=false
cleanup_started=false
failure_recorded=false
declare -a docker_command=(docker)

emit() {
  if [[ -n "$report_path" ]]; then
    printf '%s\n' "$1" | tee -a "$report_path"
  else
    printf '%s\n' "$1"
  fi
}

block() {
  failure_recorded=true
  emit "script_154_sql_corrected_local_v1_3_preview=blocked;reason=$1"
  exit 1
}

classify_postgresql_failure() {
  local diagnostic_path="$1"
  if grep -Fqi 'password authentication failed' "$diagnostic_path"; then
    printf 'authentication_failed\n'
  elif grep -Fqi 'no password supplied' "$diagnostic_path"; then
    printf 'authentication_missing\n'
  elif grep -Fqi 'no pg_hba.conf entry' "$diagnostic_path"; then
    printf 'client_auth_policy_rejected\n'
  elif grep -Eqi 'permission denied|must be owner' "$diagnostic_path"; then
    printf 'retrieval_permission_denied\n'
  elif grep -Eqi 'relation .* does not exist|column .* does not exist|database .* does not exist' "$diagnostic_path"; then
    printf 'database_schema_contract_failed\n'
  elif grep -Eqi 'connection refused|could not connect|timeout expired|server closed the connection' "$diagnostic_path"; then
    printf 'database_connectivity_failed\n'
  else
    printf 'unclassified_database_error\n'
  fi
}

classify_retrieval_start_failure() {
  local standard_output_path="$1"
  local standard_error_path="$2"
  local reason
  reason="$(sed -nE \
    's/^ishikawa_retrieval_api=blocked;reason=([a-z][a-z0-9_]{0,127})$/\1/p' \
    "$standard_output_path" | tail -n 1)"
  if [[ -n "$reason" ]]; then
    printf '%s\n' "$reason"
  elif grep -Eqi 'address already in use|EADDRINUSE' "$standard_error_path"; then
    printf 'listener_port_race\n'
  else
    printf 'unclassified_retrieval_start_failure\n'
  fi
}

classify_web_start_failure() {
  local standard_output_path="$1"
  local standard_error_path="$2"
  if grep -Eqi 'address already in use|EADDRINUSE' \
      "$standard_output_path" "$standard_error_path"; then
    printf 'web_port_race\n'
  elif grep -Eqi 'unknown option|unknown argument' \
      "$standard_output_path" "$standard_error_path"; then
    printf 'nextjs_command_invalid\n'
  elif grep -Eqi 'cannot find module|MODULE_NOT_FOUND' \
      "$standard_output_path" "$standard_error_path"; then
    printf 'nextjs_dependency_missing\n'
  elif grep -Eqi 'permission denied|EACCES|EROFS' \
      "$standard_output_path" "$standard_error_path"; then
    printf 'web_filesystem_access_failed\n'
  else
    printf 'unclassified_web_start_failure\n'
  fi
}

refresh_sudo_for_cleanup() {
  sudo -n true >/dev/null 2>&1 && return 0
  printf 'milestone=cleanup_privilege;state=awaiting_attended_sudo\n'
  sudo -v
}

port_is_free() {
  PYTHONDONTWRITEBYTECODE=1 python3 -B - "$1" <<'PY'
import socket
import sys

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
    probe.bind(("127.0.0.1", int(sys.argv[1])))
PY
}

cleanup() {
  local initial_status="$?"
  local cleanup_failed=false
  local child_status=0
  local container_state='absent'
  local container_probe_ready=true
  local inspect_container="$web_started"
  local retrieval_state='stopped'
  local postgresql_state='not_started_by_preview'
  local ports_state='free'
  local storage_state='removed'
  local credentials_state='cleared'
  if [[ "$cleanup_started" == true ]]; then
    exit "$initial_status"
  fi
  cleanup_started=true
  trap - EXIT HUP INT TERM
  set +e

  if (( initial_status != 0 )) && [[ "$failure_recorded" != true ]]; then
    emit "script_154_sql_corrected_local_v1_3_preview=blocked;reason=unexpected_shell_failure;exit_code=$initial_status"
  fi

  if [[ "$inspect_container" == true && "${docker_command[0]}" == sudo ]]; then
    if ! refresh_sudo_for_cleanup; then
      container_probe_ready=false
      cleanup_failed=true
    fi
  fi
  if [[ "$web_started" == true ]]; then
    "${docker_command[@]}" stop --time 10 "$WEB_CONTAINER" >/dev/null 2>&1 || true
    if [[ -n "$web_client_pid" ]]; then
      wait "$web_client_pid" >/dev/null 2>&1
      child_status="$?"
      emit "cleanup_component=web_client;observed_exit_code=$child_status;authoritative=false"
    fi
    web_started=false
  fi
  if [[ "$inspect_container" != true ]]; then
    container_state='absent'
  elif [[ "$container_probe_ready" != true ]]; then
    container_state='unverified'
  elif "${docker_command[@]}" container inspect "$WEB_CONTAINER" >/dev/null 2>&1; then
    container_state='present'
    cleanup_failed=true
  fi
  emit "cleanup_component=web_container;state=$container_state"

  if [[ "$service_started" == true && -n "$service_pid" ]]; then
    if kill -0 "$service_pid" 2>/dev/null; then
      kill -TERM "$service_pid" 2>/dev/null || cleanup_failed=true
    fi
    wait "$service_pid" >/dev/null 2>&1
    child_status="$?"
    emit "cleanup_component=retrieval_child;observed_exit_code=$child_status;authoritative=false"
    service_started=false
  fi
  if [[ -n "$service_pid" ]] && kill -0 "$service_pid" 2>/dev/null; then
    retrieval_state='running'
    cleanup_failed=true
  fi
  emit "cleanup_component=retrieval_api;state=$retrieval_state"

  if [[ "$postgresql_started" == true ]]; then
    if refresh_sudo_for_cleanup; then
      sudo systemctl stop "$POSTGRESQL_UNIT" >/dev/null || cleanup_failed=true
    else
      cleanup_failed=true
    fi
    postgresql_started=false
    postgresql_state="$(systemctl is-active "$POSTGRESQL_UNIT" 2>/dev/null || true)"
    if [[ "$postgresql_state" == active || "$postgresql_state" == activating ]]; then
      cleanup_failed=true
    fi
  fi
  emit "cleanup_component=postgresql;state=${postgresql_state:-unknown}"

  if ! port_is_free 3000 >/dev/null 2>&1 || ! port_is_free 1384 >/dev/null 2>&1; then
    ports_state='occupied'
    cleanup_failed=true
  fi
  emit "cleanup_component=loopback_ports;state=$ports_state;ports=3000,1384"

  if [[ -n "$work_root" && "$work_root" == /tmp/ishikawa-v1-3-sql-corrected-preview.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root" || cleanup_failed=true
  fi
  if [[ -n "$work_root" && -e "$work_root" ]]; then
    storage_state='retained'
    cleanup_failed=true
  fi
  emit "cleanup_component=private_temporary_storage;state=$storage_state"

  unset ISHIKAWA_GEMMA_API_KEY ISHIKAWA_NOMIC_API_KEY ISHIKAWA_POSTGRESQL_PASSWORD
  if [[ -v ISHIKAWA_GEMMA_API_KEY || -v ISHIKAWA_NOMIC_API_KEY || -v ISHIKAWA_POSTGRESQL_PASSWORD ]]; then
    credentials_state='retained'
    cleanup_failed=true
  fi
  emit "cleanup_component=credential_variables;state=$credentials_state"
  if [[ "$cleanup_failed" == true ]]; then
    emit 'cleanup=blocked;reason=verified_final_state_incomplete;review_required=true'
    initial_status=1
  else
    emit 'cleanup=complete;verified_final_state=true;temporary_runtime_removed=true;credential_variables_cleared=true'
  fi
  if [[ "$preview_ready" == true && "$operator_stop" == true && "$initial_status" == 0 ]]; then
    emit 'script_154_sql_corrected_local_v1_3_preview=pass;state=stopped_by_operator;next_gate=review_local_v1_3_behavior'
  fi
  if [[ -n "$report_path" && -f "$report_path" ]]; then
    printf 'local_report=%s;local_report_sha256=%s\n' \
      "$report_path" "$(sha256sum "$report_path" | awk '{print $1}')"
  fi
  exit "$initial_status"
}

request_stop() {
  operator_stop=true
  emit 'milestone=local_preview;state=operator_stop_requested'
  exit 0
}

trap cleanup EXIT
trap request_stop HUP INT TERM

umask 077
mkdir -p -- "$REPORT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/sql_corrected_local_v1_3_preview_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-v1-3-sql-corrected-preview.XXXXXX)"
chmod 0700 "$work_root"

emit 'purpose=launch_sql_corrected_local_ishikawa_v1_3_preview'
emit "started_utc=$timestamp;script_sha256=$script_sha256;script_153_report_sha256=$SCRIPT_153_REPORT_SHA256;decision_sha256=$DECISION_SHA256"
emit "full_candidate_manifest_sha256=$full_candidate_manifest_sha256;full_candidate_files=$FULL_CANDIDATE_FILE_COUNT"
emit "local_corpus_report_sha256=$CORPUS_REPORT_SHA256;database=rag_catalog;documents_expected=6;pages_expected=27;chunks_expected=126"
emit 'authorized_actions=inspect_local_prerequisites_start_native_postgresql_if_stopped_stage_private_temporary_candidate_start_foreground_retrieval_api_start_host_mounted_nextjs_preview_probe_loopback_readiness_retain_content_free_report_clean_on_exit'
emit 'non_actions=no_remote_contact_no_port_forward_creation_no_image_pull_or_change_no_database_write_no_ingestion_no_package_build_or_install_no_accepted_release_change_no_service_enablement_no_secret_retention'

actual_hostname="$(hostname -s)"
actual_os_id="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"' | head -n 1)"
actual_os_version="$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"' | head -n 1)"
actual_architecture="$(uname -m)"
package_architecture="$(dpkg --print-architecture)"
[[ "$actual_hostname" == DankoSurface \
    && "$actual_os_id" == ubuntu \
    && "$actual_os_version" == 24.04 \
    && "$actual_architecture" == aarch64 \
    && "$package_architecture" == arm64 ]] || block local_host_identity_mismatch
emit 'milestone=local_host_identity;state=pass;hostname=DankoSurface;os_version=24.04;architecture=arm64'

cluster_line="$(pg_lsclusters --no-header | awk '$1 == 16 && $2 == "main" {print; found=1} END {if (!found) exit 1}')" \
  || block postgresql_cluster_missing
read -r cluster_version cluster_name cluster_port _cluster_status _ <<<"$cluster_line"
[[ "$cluster_version|$cluster_name|$cluster_port" == '16|main|5432' ]] \
  || block postgresql_cluster_identity_mismatch
readonly postgresql_start_policy_path='/etc/postgresql/16/main/start.conf'
[[ -f "$postgresql_start_policy_path" && ! -L "$postgresql_start_policy_path" && -r "$postgresql_start_policy_path" ]] \
  || block postgresql_start_policy_unsafe
postgresql_start_policy="$(awk '!/^[[:space:]]*(#|$)/ {print $1; exit}' "$postgresql_start_policy_path")"
[[ "$postgresql_start_policy" == manual ]] || block postgresql_cluster_boot_enabled
postgresql_cluster_enablement="$(systemctl is-enabled "$POSTGRESQL_UNIT" 2>/dev/null || true)"
case "$postgresql_cluster_enablement" in
  enabled|enabled-runtime) block postgresql_cluster_unit_boot_enabled ;;
  masked) block postgresql_cluster_unit_masked ;;
esac
postgresql_meta_enablement="$(systemctl is-enabled postgresql.service 2>/dev/null || true)"
emit "milestone=postgresql_boot_posture;state=pass;cluster_start_policy=manual;cluster_unit_enablement=${postgresql_cluster_enablement:-unknown};meta_unit_enablement=${postgresql_meta_enablement:-unknown}"

if ! docker info >/dev/null 2>&1; then
  emit 'milestone=container_access;state=awaiting_attended_sudo'
  sudo -v || block privilege_authorization_failed
  docker_command=(sudo docker)
  "${docker_command[@]}" info >/dev/null 2>&1 || block container_runtime_unavailable
fi
readonly web_image='node-24-slim-nextjs-16-4-1:arm64'
"${docker_command[@]}" image inspect "$web_image" >/dev/null 2>&1 || block required_local_image_missing
[[ "$("${docker_command[@]}" image inspect "$web_image" --format '{{.Architecture}}')" == arm64 ]] \
  || block image_architecture_mismatch
[[ -z "$("${docker_command[@]}" container ls --all --quiet --filter "name=^/${WEB_CONTAINER}$")" ]] \
  || block preview_container_name_in_use
emit "milestone=container_image;state=pass;image=$web_image;image_pulled=false;image_changed=false"

for local_port in 1384 3000; do
  PYTHONDONTWRITEBYTECODE=1 python3 -B - "$local_port" <<'PY' || block configured_port_in_use
import socket
import sys

port = int(sys.argv[1])
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
    probe.bind(("127.0.0.1", port))
PY
done
emit 'milestone=preview_ports;state=pass;retrieval_port=1384;web_port=3000'

gemma_status="$(curl --silent --output /dev/null --write-out '%{http_code}' --connect-timeout 5 --max-time 10 "$GEMMA_HEALTH_URL" 2>/dev/null || true)"
nomic_status="$(curl --silent --output /dev/null --write-out '%{http_code}' --connect-timeout 5 --max-time 10 "$NOMIC_HEALTH_URL" 2>/dev/null || true)"
emit "milestone=operator_managed_model_forwards;state=observed;gemma_http_status=${gemma_status:-000};nomic_http_status=${nomic_status:-000}"
[[ "$gemma_status" == 200 ]] || block gemma_forward_unavailable
[[ "$nomic_status" == 200 ]] || block nomic_forward_unavailable
emit 'milestone=operator_managed_model_forwards;state=pass;managed_by_ishikawa=false'

if [[ "$(systemctl is-active "$POSTGRESQL_UNIT" 2>/dev/null || true)" != active ]]; then
  emit 'milestone=local_postgresql;state=awaiting_attended_sudo'
  sudo -v || block privilege_authorization_failed
  sudo systemctl start "$POSTGRESQL_UNIT" >/dev/null || block postgresql_start_failed
  postgresql_started=true
fi
postgresql_ready=false
for (( postgresql_attempt = 0; postgresql_attempt < 40; postgresql_attempt += 1 )); do
  if pg_isready --quiet --host 127.0.0.1 --port 5432 --dbname rag_catalog --timeout 2; then
    postgresql_ready=true
    break
  fi
  sleep 0.5
done
[[ "$postgresql_ready" == true ]] || block postgresql_readiness_failed
emit "milestone=local_postgresql;state=pass;started_by_script=$postgresql_started;boot_enabled=false"

admin_inventory_error="$work_root/postgresql-admin-inventory.stderr"
set +e
admin_inventory="$(sudo -u postgres psql \
  -X -q -A -t \
  -d rag_catalog \
  -v ON_ERROR_STOP=1 \
  -c "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
      WITH retrieval_role AS (
        SELECT oid, rolcanlogin
        FROM pg_roles
        WHERE rolname = 'rag_retrieval'
      )
      SELECT concat_ws('|',
        EXISTS (SELECT 1 FROM retrieval_role),
        COALESCE((SELECT rolcanlogin FROM retrieval_role), false),
        COALESCE((SELECT has_schema_privilege(oid, 'rag_search', 'USAGE')
          FROM retrieval_role), false),
        COALESCE((SELECT
          has_table_privilege(oid, 'rag_search.active_documents', 'SELECT')
            AND has_table_privilege(oid, 'rag_search.active_chunks', 'SELECT')
            AND has_table_privilege(oid, 'rag_search.active_citations', 'SELECT')
            AND has_table_privilege(oid, 'rag_search.active_embeddings', 'SELECT')
          FROM retrieval_role), false),
        (SELECT count(*) FROM rag_search.active_documents),
        (SELECT coalesce(sum(page_count), 0) FROM rag_search.active_documents),
        (SELECT count(*) FROM rag_search.active_chunks),
        (SELECT count(*) FROM rag_search.active_citations),
        (SELECT count(*) FROM rag_search.active_embeddings));
      ROLLBACK;" 2>"$admin_inventory_error")"
admin_inventory_status="$?"
set -e
if (( admin_inventory_status != 0 )); then
  admin_failure_family="$(classify_postgresql_failure "$admin_inventory_error")"
  emit "milestone=local_corpus_admin_preflight;state=blocked;failure_family=$admin_failure_family;stderr_sha256=$(sha256sum "$admin_inventory_error" | awk '{print $1}');stderr_bytes=$(stat -c '%s' "$admin_inventory_error");raw_output_retained=false"
  block "local_corpus_admin_preflight_$admin_failure_family"
fi
if [[ "$admin_inventory" != 't|t|t|t|6|27|126|126|126' ]]; then
  if [[ "$admin_inventory" =~ ^[tf]\|[tf]\|[tf]\|[tf]\|[0-9]+\|[0-9]+\|[0-9]+\|[0-9]+\|[0-9]+$ ]]; then
    IFS='|' read -r role_exists role_login schema_usage view_select \
      observed_documents observed_pages observed_chunks observed_citations observed_embeddings \
      <<<"$admin_inventory"
    emit "milestone=local_corpus_admin_preflight;state=blocked;failure_family=contract_mismatch;retrieval_role_exists=$role_exists;login=$role_login;schema_usage=$schema_usage;view_select=$view_select;documents=$observed_documents;pages=$observed_pages;chunks=$observed_chunks;citations=$observed_citations;embeddings=$observed_embeddings"
  else
    emit 'milestone=local_corpus_admin_preflight;state=blocked;failure_family=output_contract_invalid'
  fi
  block local_corpus_admin_preflight_mismatch
fi
emit 'milestone=local_corpus_admin_preflight;state=pass;retrieval_role_exists=true;login=true;schema_usage=true;view_select=true;documents=6;pages=27;chunks=126;citations=126;embeddings=126;transaction=repeatable_read_read_only'

read_secret() {
  local prompt_label="$1"
  local destination_name="$2"
  local secret_value=''
  [[ -r /dev/tty && -w /dev/tty ]] || block interactive_terminal_unavailable
  IFS= read -r -s -p "$prompt_label: " secret_value </dev/tty || block secret_entry_failed
  printf '\n' >/dev/tty
  [[ -n "$secret_value" && ${#secret_value} -le 16384 \
      && "$secret_value" != *$'\n'* && "$secret_value" != *$'\r'* ]] \
    || block secret_value_invalid
  printf -v "$destination_name" '%s' "$secret_value"
  secret_value=''
}

read_secret 'DankoSurface local rag_retrieval PostgreSQL password' ISHIKAWA_POSTGRESQL_PASSWORD
emit 'milestone=postgresql_runtime_credential;state=accepted;credential_value_retained=false'

set +e
corpus_inventory="$({
  PGPASSWORD="$ISHIKAWA_POSTGRESQL_PASSWORD" psql \
    -X -q -A -t \
    -h 127.0.0.1 \
    -p 5432 \
    -U rag_retrieval \
    -d rag_catalog \
    -v ON_ERROR_STOP=1 \
    -c "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
        SELECT concat_ws('|',
          current_user,
          current_database(),
          (SELECT count(*) FROM rag_search.active_documents),
          (SELECT coalesce(sum(page_count), 0) FROM rag_search.active_documents),
          (SELECT count(*) FROM rag_search.active_chunks),
          (SELECT count(*) FROM rag_search.active_citations),
          (SELECT count(*) FROM rag_search.active_embeddings));
        ROLLBACK;"
} 2>"$work_root/postgresql-inventory.stderr")"
corpus_inventory_status="$?"
set -e
if (( corpus_inventory_status != 0 )); then
  postgresql_failure_family="$(classify_postgresql_failure "$work_root/postgresql-inventory.stderr")"
  emit "milestone=local_corpus_inventory;state=blocked;failure_family=$postgresql_failure_family;exit_code=$corpus_inventory_status;stderr_sha256=$(sha256sum "$work_root/postgresql-inventory.stderr" | awk '{print $1}');stderr_bytes=$(stat -c '%s' "$work_root/postgresql-inventory.stderr");raw_output_retained=false"
  block "local_corpus_inventory_$postgresql_failure_family"
fi
if [[ "$corpus_inventory" != 'rag_retrieval|rag_catalog|6|27|126|126|126' ]]; then
  if [[ "$corpus_inventory" =~ ^rag_retrieval\|rag_catalog\|[0-9]+\|[0-9]+\|[0-9]+\|[0-9]+\|[0-9]+$ ]]; then
    IFS='|' read -r _ _ observed_documents observed_pages observed_chunks observed_citations observed_embeddings \
      <<<"$corpus_inventory"
    emit "milestone=local_corpus_inventory;state=blocked;failure_family=inventory_mismatch;documents=$observed_documents;pages=$observed_pages;chunks=$observed_chunks;citations=$observed_citations;embeddings=$observed_embeddings"
  else
    emit 'milestone=local_corpus_inventory;state=blocked;failure_family=output_contract_invalid'
  fi
  block local_corpus_inventory_mismatch
fi
emit 'milestone=local_corpus_inventory;state=pass;role=rag_retrieval;database=rag_catalog;documents=6;pages=27;chunks=126;citations=126;embeddings=126;transaction=repeatable_read_read_only'

read_secret 'Gemma API key' ISHIKAWA_GEMMA_API_KEY
read_secret 'Nomic API key' ISHIKAWA_NOMIC_API_KEY
export ISHIKAWA_GEMMA_API_KEY ISHIKAWA_NOMIC_API_KEY ISHIKAWA_POSTGRESQL_PASSWORD
emit 'milestone=runtime_credentials;state=accepted;credential_values_retained=false'

installed_root="$work_root/Ishikawa"
install -d -m 0755 \
  "$installed_root/application/python/ishikawa" \
  "$installed_root/config" \
  "$installed_root/scripts"
install -d -m 0700 "$installed_root/state/logs" "$installed_root/state/run"
for python_source in "$PYTHON_SOURCE_ROOT"/*.py; do
  [[ -f "$python_source" && ! -L "$python_source" ]] || block python_source_unsafe
  install -m 0644 "$python_source" \
    "$installed_root/application/python/ishikawa/$(basename -- "$python_source")"
done
for configuration_source in "$CONFIG_TEMPLATE_ROOT"/*.yaml; do
  [[ -f "$configuration_source" && ! -L "$configuration_source" ]] || block configuration_source_unsafe
  install -m 0644 "$configuration_source" \
    "$installed_root/config/$(basename -- "$configuration_source")"
done
install -m 0755 "$SERVICE_ENTRYPOINT" "$installed_root/scripts/ishikawa-retrieval-api"

configuration_output="$work_root/configuration.stdout"
configuration_error="$work_root/configuration.stderr"
set +e
env -u ISHIKAWA_GEMMA_API_KEY -u ISHIKAWA_NOMIC_API_KEY -u ISHIKAWA_POSTGRESQL_PASSWORD \
  PYTHONDONTWRITEBYTECODE=1 \
  "$installed_root/scripts/ishikawa-retrieval-api" --check-config \
  >"$configuration_output" 2>"$configuration_error"
configuration_status="$?"
set -e
if (( configuration_status != 0 )); then
  configuration_failure_family="$(classify_retrieval_start_failure \
    "$configuration_output" "$configuration_error")"
  emit "milestone=staged_configuration;state=blocked;failure_family=$configuration_failure_family;stdout_sha256=$(sha256sum "$configuration_output" | awk '{print $1}');stderr_sha256=$(sha256sum "$configuration_error" | awk '{print $1}');raw_output_retained=false"
  block staged_configuration_invalid
fi
if ! grep -Eq '^ishikawa_retrieval_api_configuration=pass;policy_digest=[0-9a-f]{64};credential_read=false;dependency_contact=false$' \
    "$configuration_output"; then
  emit "milestone=staged_configuration;state=blocked;failure_family=output_contract_invalid;stdout_sha256=$(sha256sum "$configuration_output" | awk '{print $1}');stderr_sha256=$(sha256sum "$configuration_error" | awk '{print $1}');raw_output_retained=false"
  block staged_configuration_invalid
fi
emit 'milestone=staged_configuration;state=pass;credential_read=false;dependency_contact=false'

readiness_output="$work_root/readiness.stdout"
readiness_error="$work_root/readiness.stderr"
set +e
PYTHONDONTWRITEBYTECODE=1 \
  "$installed_root/scripts/ishikawa-retrieval-api" --check-readiness \
  >"$readiness_output" 2>"$readiness_error"
readiness_status="$?"
set -e
if (( readiness_status != 0 )); then
  readiness_marker="$(grep -E '^ishikawa_retrieval_api_readiness=(pass|blocked);configuration=(pass|blocked);storage=(pass|blocked);postgresql=(pass|blocked);gemma=(pass|blocked);nomic=(pass|blocked)$' \
    "$readiness_output" | tail -n 1 || true)"
  readiness_failure_family="$(classify_retrieval_start_failure \
    "$readiness_output" "$readiness_error")"
  if [[ -n "$readiness_marker" ]]; then
    emit "milestone=retrieval_readiness_preflight;state=blocked;failure_family=$readiness_failure_family;component_marker=$readiness_marker;stdout_sha256=$(sha256sum "$readiness_output" | awk '{print $1}');stderr_sha256=$(sha256sum "$readiness_error" | awk '{print $1}');raw_output_retained=false"
  else
    emit "milestone=retrieval_readiness_preflight;state=blocked;failure_family=$readiness_failure_family;component_marker=invalid_or_absent;stdout_sha256=$(sha256sum "$readiness_output" | awk '{print $1}');stderr_sha256=$(sha256sum "$readiness_error" | awk '{print $1}');raw_output_retained=false"
  fi
  block retrieval_readiness_preflight_failed
fi
if ! grep -Fxq 'ishikawa_retrieval_api_readiness=pass;configuration=pass;storage=pass;postgresql=pass;gemma=pass;nomic=pass' \
    "$readiness_output"; then
  emit "milestone=retrieval_readiness_preflight;state=blocked;failure_family=output_contract_invalid;stdout_sha256=$(sha256sum "$readiness_output" | awk '{print $1}');stderr_sha256=$(sha256sum "$readiness_error" | awk '{print $1}');raw_output_retained=false"
  block retrieval_readiness_preflight_invalid
fi
emit 'milestone=retrieval_readiness_preflight;state=pass;configuration=pass;storage=pass;postgresql=pass;gemma=pass;nomic=pass'

service_output="$work_root/retrieval.stdout"
service_error="$work_root/retrieval.stderr"
PYTHONDONTWRITEBYTECODE=1 \
  "$installed_root/scripts/ishikawa-retrieval-api" --serve \
  >"$service_output" 2>"$service_error" &
service_pid="$!"
service_started=true
ISHIKAWA_GEMMA_API_KEY=''
ISHIKAWA_NOMIC_API_KEY=''
ISHIKAWA_POSTGRESQL_PASSWORD=''
unset ISHIKAWA_GEMMA_API_KEY ISHIKAWA_NOMIC_API_KEY ISHIKAWA_POSTGRESQL_PASSWORD

retrieval_ready=false
for (( retrieval_attempt = 0; retrieval_attempt < 120; retrieval_attempt += 1 )); do
  kill -0 "$service_pid" 2>/dev/null || break
  retrieval_status="$(curl --silent --output /dev/null --write-out '%{http_code}' --connect-timeout 1 --max-time 3 "$RETRIEVAL_BASE_URL/ready" 2>/dev/null || true)"
  if [[ "$retrieval_status" == 200 ]]; then
    retrieval_ready=true
    break
  fi
  sleep 0.5
done
if [[ "$retrieval_ready" != true ]]; then
  retrieval_failure_family="$(classify_retrieval_start_failure "$service_output" "$service_error")"
  emit "milestone=retrieval_api;state=blocked;failure_family=$retrieval_failure_family;stdout_sha256=$(sha256sum "$service_output" | awk '{print $1}');stderr_sha256=$(sha256sum "$service_error" | awk '{print $1}');raw_output_retained=false"
  block retrieval_api_not_ready
fi
emit 'milestone=retrieval_api;state=pass;bind=127.0.0.1:1384;temporary_stage=true'

declare -a web_mounts=(
  --mount "type=bind,src=$WEB_ROOT/app,dst=/opt/nextjs/app,readonly"
  --mount "type=bind,src=$WEB_ROOT/components,dst=/opt/nextjs/components,readonly"
  --mount "type=bind,src=$WEB_ROOT/lib,dst=/opt/nextjs/lib,readonly"
  --mount "type=bind,src=$WEB_ROOT/public,dst=/opt/nextjs/public,readonly"
  --mount "type=bind,src=$WEB_ROOT/package.json,dst=/opt/nextjs/package.json,readonly"
  --mount "type=bind,src=$WEB_ROOT/next.config.mjs,dst=/opt/nextjs/next.config.mjs,readonly"
)
web_output="$work_root/web.stdout"
web_error="$work_root/web.stderr"
if [[ "${docker_command[0]}" == sudo ]]; then
  emit 'milestone=container_start;state=awaiting_attended_sudo_if_required'
  sudo -v || block privilege_authorization_failed
fi
"${docker_command[@]}" run --rm \
  --name "$WEB_CONTAINER" \
  --network host \
  --security-opt no-new-privileges \
  --cap-drop ALL \
  --env ISHIKAWA_PRODUCT_DISPLAY_NAME=Ishikawa \
  --env "ISHIKAWA_RETRIEVAL_BASE_URL=$RETRIEVAL_BASE_URL" \
  "${web_mounts[@]}" \
  "$web_image" npm run dev -- --hostname 127.0.0.1 --port 3000 \
  >"$web_output" 2>"$web_error" &
web_client_pid="$!"
web_started=true

web_ready=false
for (( web_attempt = 0; web_attempt < 160; web_attempt += 1 )); do
  kill -0 "$web_client_pid" 2>/dev/null || break
  web_status="$(curl --silent --output /dev/null --write-out '%{http_code}' --connect-timeout 1 --max-time 3 "$WEB_BASE_URL/api/ready" 2>/dev/null || true)"
  if [[ "$web_status" == 200 ]]; then
    web_ready=true
    break
  fi
  sleep 0.5
done
if [[ "$web_ready" != true ]]; then
  web_failure_family="$(classify_web_start_failure "$web_output" "$web_error")"
  emit "milestone=chat_ui;state=blocked;failure_family=$web_failure_family;stdout_sha256=$(sha256sum "$web_output" | awk '{print $1}');stderr_sha256=$(sha256sum "$web_error" | awk '{print $1}');raw_output_retained=false"
  block chat_ui_not_ready
fi

home_response="$work_root/home.html"
curl --fail --silent --show-error --connect-timeout 2 --max-time 15 \
  "$WEB_BASE_URL/" >"$home_response" || block chat_workspace_unavailable
grep -Fq 'Ishikawa' "$home_response" || block chat_workspace_contract_invalid
grep -Fq 'Knowledge chat' "$home_response" || block chat_workspace_contract_invalid
theme_status="$(curl --silent --output /dev/null --write-out '%{http_code}' --connect-timeout 2 --max-time 5 "$WEB_BASE_URL/theme-init.js" 2>/dev/null || true)"
[[ "$theme_status" == 200 ]] || block theme_asset_unavailable
dependency_response="$work_root/dependencies.json"
curl --fail --silent --show-error --connect-timeout 2 --max-time 10 \
  "$WEB_BASE_URL/api/dependencies" >"$dependency_response" || block dependency_indicator_unavailable
PYTHONDONTWRITEBYTECODE=1 python3 -B - "$dependency_response" <<'PY' \
  || block dependency_indicator_invalid
import json
import sys
from pathlib import Path

response = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
expected = {
    "gemma": "available",
    "nomic": "available",
    "schema": "ishikawa.web-dependency-health.v1",
}
if response != expected:
    raise SystemExit(1)
PY
emit 'milestone=chat_ui;state=pass;bind=127.0.0.1:3000;theme_asset=pass;gemma=available;nomic=available;hot_reload=true'

preview_ready=true
emit 'script_154_sql_corrected_local_v1_3_preview=ready;url=http://127.0.0.1:3000;stop=ctrl_c;next_gate=interactive_browser_review'
printf '%s\n' \
  '' \
  'Ishikawa v1.3 is ready at http://127.0.0.1:3000.' \
  'Leave this terminal open during testing. Press Ctrl+C once to stop and clean up.'

while true; do
  kill -0 "$service_pid" 2>/dev/null || block retrieval_api_exited_unexpectedly
  kill -0 "$web_client_pid" 2>/dev/null || block chat_ui_exited_unexpectedly
  sleep 5
done

