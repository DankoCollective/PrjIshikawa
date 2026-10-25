#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Stop the verified DankoSurface Next.js POC and the local PostgreSQL cluster
#   that are preventing the Ishikawa v1.3 preview prerequisites from closing.
#
# Mental model:
#   Bind the exact second Script 147 stopped-cluster block, identify the POC by
#   its loopback page, image, and sole running container, prove no Retrieval API
#   or PostgreSQL client session is active, stop only those two runtimes, and
#   prove ports 3000, 1384, and 5432 are free. Do not remove images or data.
#
# Inputs or prerequisites:
#   DankoSurface on Ubuntu 24.04 ARM64, the exact blocked Script 147 receipt,
#   the old POC if port 3000 is occupied, and attended local sudo.
#
# Outputs or artifact lane:
#   One content-free report under local/reports/ishikawa-v1.3-local-runtime-stop.
#   The POC container and PostgreSQL 16/main may be stopped. Docker may apply
#   the container's existing automatic-removal policy after stop. No image,
#   database data, package, model, credential, or remote host is changed.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/148_stop_local_poc_and_postgresql.sh --run

usage() {
  sed -n '4,25p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Stop the verified local POC and PostgreSQL runtime.' \
    '  --validate-only Validate frozen inputs and shell structure only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly SCRIPT_147="$SCRIPT_DIR/147_correct_local_postgresql_on_demand_posture.sh"
readonly SCRIPT_147_SHA256='07062c0032cba8e174b012f538a8afaec830ac14cc4c7fcf088a6623dce795dc'
readonly BLOCKED_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.3-local-postgresql-on-demand/postgresql_on_demand_20261022T003541Z_Q0qqED.txt"
readonly BLOCKED_REPORT_SHA256='a2c7b1953ffed47fd3ab365f7e710fe17a4ac0569c2ee6cd940c8ec6f982aca4'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.3-local-runtime-stop"
readonly POSTGRESQL_UNIT='postgresql@16-main.service'
readonly POC_IMAGE='node-24-slim-nextjs-16-4-1:arm64'
readonly POC_PAGE_URL='http://127.0.0.1:3000/'
readonly POC_HEADING='Danko Next.js POC'
readonly POC_DESCRIPTION='Next.js 16.4.1 is running from the ARM64 developer image.'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      printf 'script_148_local_runtime_stop=blocked;reason=argument_invalid\n' >&2
      usage >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_148_local_runtime_stop=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required_command in \
  awk bash curl date dirname docker dpkg grep head hostname mapfile mkdir mktemp \
  pg_isready pg_lsclusters psql python3 rm rmdir sed sha256sum sleep stat sudo \
  systemctl tee tr; do
  command -v "$required_command" >/dev/null 2>&1 || {
    printf 'script_148_local_runtime_stop=blocked;reason=local_command_missing;command=%s\n' \
      "$required_command" >&2
    exit 2
  }
done
for required_file in "$SCRIPT_147" "$BLOCKED_REPORT"; do
  [[ -f "$required_file" && ! -L "$required_file" && -r "$required_file" ]] || {
    printf 'script_148_local_runtime_stop=blocked;reason=required_input_unsafe\n' >&2
    exit 2
  }
done
bash -n "${BASH_SOURCE[0]}" "$SCRIPT_147"
[[ "$(sha256sum "$SCRIPT_147" | awk '{print $1}')" == "$SCRIPT_147_SHA256" ]] || {
  printf 'script_148_local_runtime_stop=blocked;reason=script_147_identity_mismatch\n' >&2
  exit 1
}
[[ "$(sha256sum "$BLOCKED_REPORT" | awk '{print $1}')" == "$BLOCKED_REPORT_SHA256" ]] || {
  printf 'script_148_local_runtime_stop=blocked;reason=script_147_report_checksum_mismatch\n' >&2
  exit 1
}
grep -Fxq 'script_147_postgresql_on_demand=blocked;reason=postgresql_cluster_must_be_stopped' \
  "$BLOCKED_REPORT" || {
    printf 'script_148_local_runtime_stop=blocked;reason=script_147_block_not_bound\n' >&2
    exit 1
  }
grep -Fxq 'cleanup=complete;temporary_files_removed=true' "$BLOCKED_REPORT" || {
  printf 'script_148_local_runtime_stop=blocked;reason=script_147_cleanup_not_proven\n' >&2
  exit 1
}

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_local_poc_and_postgresql_stop' \
    "script_sha256=$script_sha256;script_147_sha256=$SCRIPT_147_SHA256;blocked_report_sha256=$BLOCKED_REPORT_SHA256" \
    'sudo_used=false;container_contact=false;database_contact=false;service_changed=false;remote_contact=false' \
    'script_148_local_runtime_stop=pass'
  exit 0
fi

report_path=''
work_root=''
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
  emit "script_148_local_runtime_stop=blocked;reason=$1"
  exit 1
}

port_is_free() {
  PYTHONDONTWRITEBYTECODE=1 python3 -B - "$1" <<'PY'
import socket
import sys

port_number = int(sys.argv[1])
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener_probe:
    listener_probe.bind(("127.0.0.1", port_number))
PY
}

cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  set +e
  if (( status != 0 )) && [[ "$failure_recorded" != true ]]; then
    emit "script_148_local_runtime_stop=blocked;reason=unexpected_shell_failure;exit_code=$status"
  fi
  if [[ -n "$work_root" && "$work_root" == /tmp/ishikawa-script-148.* && -d "$work_root" ]]; then
    rm -f -- "$work_root/poc-page.html"
    rmdir -- "$work_root" 2>/dev/null || true
  fi
  emit 'cleanup=complete;temporary_files_removed=true'
  if [[ -n "$report_path" && -f "$report_path" ]]; then
    printf 'local_report=%s;local_report_sha256=%s\n' \
      "$report_path" "$(sha256sum "$report_path" | awk '{print $1}')"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

umask 077
mkdir -p -- "$REPORT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/local_runtime_stop_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-script-148.XXXXXX)"
poc_page_path="$work_root/poc-page.html"

emit 'purpose=stop_verified_local_poc_and_postgresql'
emit "started_utc=$timestamp;script_sha256=$script_sha256;script_147_sha256=$SCRIPT_147_SHA256;blocked_report_sha256=$BLOCKED_REPORT_SHA256"
emit 'authorized_actions=inspect_local_runtime_verify_and_stop_exact_nextjs_poc_allow_existing_docker_auto_remove_policy_verify_zero_postgresql_client_sessions_stop_postgresql_16_main_prove_loopback_ports_free_retain_content_free_report'
emit 'non_actions=no_explicit_container_removal_no_image_change_no_database_content_read_or_write_no_package_change_no_model_or_remote_contact_no_credential_access_no_boot_policy_change'

actual_hostname="$(hostname -s)"
actual_os_id="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"' | head -n 1)"
actual_os_version="$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"' | head -n 1)"
actual_architecture="$(dpkg --print-architecture)"
[[ "$actual_hostname|$actual_os_id|$actual_os_version|$actual_architecture" \
    == 'DankoSurface|ubuntu|24.04|arm64' ]] || block local_host_identity_mismatch
emit 'milestone=local_host_identity;state=pass;hostname=DankoSurface;os_version=24.04;architecture=arm64'

if ! port_is_free 1384; then
  block retrieval_port_in_use_stop_ishikawa_before_cleanup
fi
emit 'milestone=retrieval_port;state=pass;port=1384;listener=absent'

emit 'milestone=attended_privilege;state=awaiting_operator_if_prompted'
sudo -v || block privilege_authorization_failed
if ! docker info >/dev/null 2>&1; then
  docker_command=(sudo docker)
  "${docker_command[@]}" info >/dev/null 2>&1 || block container_runtime_unavailable
fi
[[ "$("${docker_command[@]}" image inspect "$POC_IMAGE" --format '{{.Architecture}}' 2>/dev/null)" == arm64 ]] \
  || block poc_image_identity_mismatch

poc_stopped=false
poc_container_name='none'
poc_auto_remove='not_applicable'
if ! port_is_free 3000; then
  curl --silent --show-error --fail --connect-timeout 3 --max-time 10 \
    "$POC_PAGE_URL" --output "$poc_page_path" || block port_3000_owner_not_http_poc
  grep -Fq "$POC_HEADING" "$poc_page_path" || block port_3000_page_identity_mismatch
  grep -Fq "$POC_DESCRIPTION" "$poc_page_path" || block port_3000_page_identity_mismatch

  mapfile -t poc_container_ids < <(
    "${docker_command[@]}" container ls --quiet --filter "ancestor=$POC_IMAGE"
  )
  (( ${#poc_container_ids[@]} == 1 )) || block poc_container_identity_ambiguous
  poc_container_id="${poc_container_ids[0]}"
  [[ "$poc_container_id" =~ ^[0-9a-f]{12,64}$ ]] || block poc_container_id_invalid
  poc_container_image="$(
    "${docker_command[@]}" container inspect --format '{{.Config.Image}}' "$poc_container_id"
  )"
  [[ "$poc_container_image" == "$POC_IMAGE" ]] || block poc_container_image_mismatch
  poc_container_name="$(
    "${docker_command[@]}" container inspect --format '{{.Name}}' "$poc_container_id" | sed 's#^/##'
  )"
  [[ "$poc_container_name" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$ ]] \
    || block poc_container_name_invalid
  poc_auto_remove="$(
    "${docker_command[@]}" container inspect --format '{{.HostConfig.AutoRemove}}' "$poc_container_id"
  )"
  [[ "$poc_auto_remove" == true || "$poc_auto_remove" == false ]] \
    || block poc_container_auto_remove_state_invalid

  emit "milestone=nextjs_poc_identity;state=pass;container=$poc_container_name;image=$POC_IMAGE;page_identity=pass;auto_remove=$poc_auto_remove"
  "${docker_command[@]}" container stop --time 10 "$poc_container_id" >/dev/null \
    || block poc_container_stop_failed
  poc_stopped=true
  for (( port_attempt = 0; port_attempt < 20; port_attempt += 1 )); do
    port_is_free 3000 && break
    sleep 0.5
  done
  port_is_free 3000 || block web_port_remained_in_use_after_poc_stop
else
  emit 'milestone=nextjs_poc_identity;state=not_running;web_port=3000'
fi
emit "milestone=nextjs_poc_stop;state=pass;stopped=$poc_stopped;container=$poc_container_name;auto_remove=$poc_auto_remove;web_port_3000=free"

cluster_line="$(pg_lsclusters --no-header | awk '$1 == 16 && $2 == "main" {print; found=1} END {if (!found) exit 1}')" \
  || block postgresql_cluster_missing
read -r cluster_version cluster_name cluster_port cluster_status _ <<<"$cluster_line"
[[ "$cluster_version|$cluster_name|$cluster_port" == '16|main|5432' ]] \
  || block postgresql_cluster_identity_mismatch

postgresql_stopped=false
if [[ "$cluster_status" == online ]]; then
  active_client_count="$(
    sudo -u postgres psql -X -q -A -t -d postgres -v ON_ERROR_STOP=1 \
      -c "SELECT count(*) FROM pg_stat_activity WHERE pid <> pg_backend_pid() AND backend_type = 'client backend';"
  )" || block postgresql_session_inventory_failed
  [[ "$active_client_count" =~ ^[0-9]+$ ]] || block postgresql_session_inventory_invalid
  (( active_client_count == 0 )) || block postgresql_active_client_sessions_present
  emit 'milestone=postgresql_client_sessions;state=pass;active_clients=0'
  sudo systemctl stop "$POSTGRESQL_UNIT" >/dev/null || block postgresql_stop_failed
  postgresql_stopped=true
elif [[ "$cluster_status" != down ]]; then
  block postgresql_cluster_state_unrecognized
else
  emit 'milestone=postgresql_client_sessions;state=not_applicable;cluster_state=down'
fi

cluster_line="$(pg_lsclusters --no-header | awk '$1 == 16 && $2 == "main" {print; found=1} END {if (!found) exit 1}')" \
  || block final_postgresql_cluster_missing
read -r _ _ _ final_cluster_status _ <<<"$cluster_line"
[[ "$final_cluster_status" == down ]] || block postgresql_cluster_remained_running
pg_isready --quiet --host 127.0.0.1 --port 5432 --timeout 2 \
  && block postgresql_listener_remained_available
port_is_free 3000 || block final_web_port_in_use
port_is_free 1384 || block final_retrieval_port_in_use

emit "milestone=postgresql_stop;state=pass;stopped=$postgresql_stopped;cluster_state=down;port_5432=free"
emit "database_changed=false;container_explicitly_removed=false;container_auto_remove=$poc_auto_remove;image_changed=false;package_changed=false;credential_access=false;remote_contact=false"
emit 'script_148_local_runtime_stop=pass;next_gate=rerun_script_147_postgresql_on_demand_correction'
