#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Purpose:
#   Prepare and launch the exact qualified Ishikawa v1.3 candidate for attended
#   human UI review on EmceeDanko without overwriting v1.2 or its database.
#
# Mental model:
#   Revalidate the frozen release and Script 05 evidence locally, transfer one
#   checksum-bound copy of this script plus final-schema inputs, and perform all
#   target preflights while v1.2 is still ready by default. Build or revalidate
#   an isolated durable v1.3 database and attended runtime copy, then stop v1.2
#   immediately before starting a package-local v1.3 API process and distinct
#   web container. The default failed-launch path restores verified v1.2. The
#   explicit V13-76 waiver skips that readiness and restoration guarantee while
#   preserving both installations and database trees on disk. Separate accept
#   and rollback modes close the attended gate without installing or enabling a
#   new user unit.
#
# Inputs or prerequisites:
#   The exact Script 01 archive, exact Script 05 report/current artifact, staged
#   candidate and corpus-v3 input, PostgreSQL 16/pgvector, the accepted AMD64
#   Node image, model forwards, attended SSH/sudo, and hidden runtime secrets.
#
# Outputs or artifact lane:
#   A local report under local/reports/emceedanko-v1.3-attended-ui. On target,
#   launch creates only ~/Documents/Ishikawa-v1.3-attended, including one
#   isolated durable PostgreSQL 16 data cluster, one package-local API process,
#   and one ishikawa-v1.3-web container. Boot autostart and canonical v1.2
#   files/database stay unchanged.
#
# Usage:
#   bash ./deployment/scripts/06_attended-v1.3-on-emceedanko.sh --validate-only
#   bash ./deployment/scripts/06_attended-v1.3-on-emceedanko.sh --run
#   bash ./deployment/scripts/06_attended-v1.3-on-emceedanko.sh --run --waive-v1-2-rollback
#   bash ./deployment/scripts/06_attended-v1.3-on-emceedanko.sh --accept
#   bash ./deployment/scripts/06_attended-v1.3-on-emceedanko.sh --rollback

readonly expected_application_sha256='53da57b745fb4c8be6335896d05bdb6f63f2de3494862b99acca09e156863f3c'
readonly expected_corpus_sha256='9e4eadfe43dfd875e9d639119fe933dadfb409b63d28f68c22247441e09581fd'
readonly expected_script05_report_sha256='854240b564148f38853b183852ca98ac12d38ef3a57bb6ed513116270d7a98c0'
readonly expected_script05_receipt_sha256='8672b7e804d4b5028e7e898f67aa91a32588cd48748bd3283b773332e606759f'
readonly expected_script05_result_sha256='0f2ed136458ca34d2c5eecb9f37ad04a5c411f1b8b7d0e543ef14362fcc7f6e5'
readonly expected_frontier_sha256='3cdf7dc4bed4bef9935148f7604d5499342c5ae2b54c9be13594b9ab10caeb49'
readonly expected_web_image_id='sha256:368f4381b61bf90ad27aa5a9dd4c10e1de0b4b4666006911e1b6cb4aafcfb8a6'
readonly candidate_root="$HOME/Documents/Ishikawa-v1.3"
readonly corpus_input_root="$HOME/Documents/Ishikawa-v1.3-qualification-inputs"
readonly active_v1_2_root="$HOME/Documents/Ishikawa"
readonly rollback_v1_2_root="$HOME/Documents/Ishikawa-before-v1.2"
readonly runtime_root="$HOME/Documents/Ishikawa-v1.3-attended"
readonly database_name='rag_catalog'
readonly owner_role='rag_owner'
readonly ingest_role='rag_ingest'
readonly retrieval_role='rag_retrieval'
readonly private_postgresql_port=65438
readonly v1_2_unit='ishikawa-retrieval-api.service'
readonly v1_2_container='ishikawa-web'
readonly v1_3_container='ishikawa-v1.3-web'
readonly ui_port=3384
readonly retrieval_port=8384
readonly manifest_name='qualification-corpus-v3.yaml'

mode="${1:-}"
shift || true

validate_loopback_url() {
  PYTHONDONTWRITEBYTECODE=1 python3 -B - "$1" <<'PY'
import sys
import urllib.parse
value = urllib.parse.urlsplit(sys.argv[1])
if (
    value.scheme != "http" or value.hostname != "127.0.0.1" or value.port is None
    or value.path not in {"", "/"} or value.query or value.fragment
    or value.username is not None or value.password is not None
):
    raise SystemExit(1)
PY
}

if [[ "$mode" == --self-test ]]; then
  [[ "$#" -eq 0 ]] || exit 2
  validate_loopback_url 'http://127.0.0.1:8000'
  ! validate_loopback_url 'https://example.invalid:8000'
  [[ "$database_name" =~ ^[a-z_][a-z0-9_]{0,62}$ ]]
  [[ "$owner_role" != "$ingest_role" && "$owner_role" != "$retrieval_role" ]]
  printf '%s\n' 'attended_v1_3_orchestrator_self_test=pass'
  exit 0
fi

target_internal=false
case "$mode" in
  --target-launch|--target-accept|--target-rollback) target_internal=true ;;
esac

if [[ "$target_internal" == true ]]; then
  [[ "${ISHIKAWA_SCRIPT06_INTERNAL:-}" == 1 ]] || {
    printf '%s\n' 'attended_v1_3_target=blocked;reason=internal_mode_unauthorized' >&2
    exit 2
  }
else
  readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
  readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
  readonly application_archive="$repo_root/local/artifacts/ishikawa-v1.3-current/ishikawa-v1.3.tar.gz"
  readonly application_sidecar="$application_archive.sha256"
  readonly qualification_artifact="$repo_root/local/artifacts/emceedanko-v1.3-frontier-qualification-current"
  readonly script05_report_root="$repo_root/local/reports/emceedanko-v1.3-frontier-qualification"
  readonly generator_source="$repo_root/deployment/assets/create-corpus-v3-ingestion-config.py"
  readonly default_report_root="$repo_root/local/reports/emceedanko-v1.3-attended-ui"
fi

target_stage='argument_validation'
target_reason=''
target_detail=''
target_action=''
target_result_path=''
target_complete=false
target_state='blocked'
target_cleanup_failed=false
target_v1_2_stopped=false
target_v1_2_restored=false
target_durable_committed=false
target_runtime_stage=''
target_corpus_stage=''
target_private_pg_started=false
target_pg_initdb=''
target_pg_ctl=''
target_pg_createdb=''
target_pg_psql=''
target_pg_isready=''
target_pg_config=''
target_database_action=''
target_acceptance_stage=''
target_api_pid=''
target_web_container_state='unknown'
target_web_exit_code='unknown'
target_web_oom_killed='unknown'
target_web_live_status='000'
target_web_ready_status='000'
target_web_api_status='000'
target_web_root_cause='unreported_failure'
target_web_log_sha256='none'
target_web_log_bytes='0'
target_gemma_key=''
target_nomic_key=''
target_v1_2_database_password=''
target_v1_3_ingest_password=''
target_v1_3_retrieval_password=''
target_waive_v1_2_rollback=false
target_payload_root=''
target_expected_hostname='EmceeDanko'
target_expected_os_version='24.04'
target_expected_architecture='amd64'
target_gemma_base_url='http://127.0.0.1:8000'
target_nomic_base_url='http://127.0.0.1:8001'
target_docker=()

target_emit() {
  local tag="$1" message="$2"
  printf '[%s] %s\n' "$tag" "$message"
}

target_v1_2_rollback_posture() {
  if [[ "$target_waive_v1_2_rollback" == true ]]; then
    printf waived
  else
    printf verified
  fi
}

target_fail() {
  target_reason="$1"
  target_detail="$2"
  target_action="$3"
  exit "${4:-1}"
}

target_read_secret() {
  local label="$1" destination="$2" minimum="$3" maximum="$4" value='' bytes=''
  [[ -r /dev/tty && -w /dev/tty ]] \
    || target_fail interactive_terminal_unavailable \
      'A controlling terminal is required for protected credential entry.' \
      'Run Script 06 from an interactive terminal.'
  printf '\n[INPUT REQUIRED] %s\n' "$label" >/dev/tty
  printf '[INPUT MODE] Hidden input is active. Paste or type the value, then press Enter.\n' >/dev/tty
  IFS= read -r -s value </dev/tty \
    || target_fail secret_entry_failed 'Protected credential input failed.' \
      'Rerun Script 06 from an interactive terminal.'
  bytes="$(LC_ALL=C printf '%s' "$value" | wc -c | tr -d ' ')"
  [[ "$bytes" =~ ^[0-9]+$ ]] \
    || target_fail credential_length_invalid "The ${label} length could not be validated." \
      'Re-enter the complete credential.'
  (( bytes >= minimum && bytes <= maximum )) \
    || target_fail credential_length_invalid \
      "The ${label} must be between ${minimum} and ${maximum} bytes." \
      'Re-enter the complete credential.'
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] \
    || target_fail credential_line_break "The ${label} contains a line break." \
      'Re-enter the credential without a line break.'
  printf -v "$destination" '%s' "$value"
  value=''
  printf '[INPUT ACCEPTED] %s received.\n' "$label" >/dev/tty
}

target_http_ready() {
  local url="$1"
  [[ "$(target_http_status "$url")" == 200 ]]
}

target_http_status() {
  local url="$1" status='000'
  status="$(curl -sS -o /dev/null -w '%{http_code}' \
    --connect-timeout 1 --max-time 5 "$url" 2>/dev/null || true)"
  [[ "$status" =~ ^[0-9]{3}$ ]] || status='000'
  printf '%s' "$status"
}

target_port_listening() {
  local port="$1" listeners
  listeners="$(ss -H -ltn "( sport = :${port} )" 2>/dev/null)" \
    || target_fail listener_inventory_failed \
      "Listener inventory failed for TCP port ${port}." \
      'Restore bounded ss listener inspection before Script 06.'
  [[ -n "$listeners" ]]
}

target_wait_http() {
  local url="$1" attempts="$2" label="$3" attempt=0 started next now
  started="$(date +%s)"
  next=$(( started + 25 ))
  for (( attempt = 0; attempt < attempts; attempt += 1 )); do
    target_http_ready "$url" && return 0
    now="$(date +%s)"
    if (( now >= next )); then
      target_emit "$label" "state=starting;elapsed_seconds=$(( now - started ))"
      next=$(( now + 25 ))
    fi
    sleep 1
  done
  return 1
}

target_safe_root_cause() {
  local path candidate=''
  for path in "$@"; do
    [[ -f "$path" && ! -L "$path" ]] || continue
    candidate="$(sed -nE \
      -e 's/^ishikawa_ingestion=blocked;reason=([a-z][a-z0-9_]{0,127})$/\1/p' \
      -e 's/^ishikawa_ingest=blocked;reason=([a-z][a-z0-9_]{0,127})$/\1/p' \
      -e 's/^ishikawa_retrieval_api=blocked;reason=([a-z][a-z0-9_]{0,127})$/\1/p' \
      -e 's/^\[INGEST\] state=blocked;exit_code=[0-9]+;reason=([a-z][a-z0-9_]{0,127})$/\1/p' \
      "$path" | tail -n 1)"
    [[ -z "$candidate" ]] || break
  done
  printf '%s' "${candidate:-unreported_failure}"
}

target_container_running() {
  local name="$1"
  [[ "$("${target_docker[@]}" inspect --format '{{.State.Running}}' "$name" 2>/dev/null || true)" == true ]]
}

target_container_exists() {
  local name="$1"
  "${target_docker[@]}" inspect "$name" >/dev/null 2>&1
}

target_capture_web_diagnostic() {
  local container_name="$1" state='' log_path=''
  target_web_container_state='missing'
  target_web_exit_code='unknown'
  target_web_oom_killed='unknown'
  target_web_root_cause='unreported_failure'
  target_web_log_sha256='none'
  target_web_log_bytes='0'
  if target_container_exists "$container_name"; then
    state="$("${target_docker[@]}" inspect \
      --format '{{.State.Running}};{{.State.ExitCode}};{{.State.OOMKilled}}' \
      "$container_name" 2>/dev/null || true)"
    IFS=';' read -r target_web_container_state target_web_exit_code \
      target_web_oom_killed <<<"$state"
    [[ "$target_web_container_state" == true || "$target_web_container_state" == false ]] \
      || target_web_container_state='unknown'
    [[ "$target_web_exit_code" =~ ^[0-9]+$ ]] || target_web_exit_code='unknown'
    [[ "$target_web_oom_killed" == true || "$target_web_oom_killed" == false ]] \
      || target_web_oom_killed='unknown'
    log_path="$runtime_root/state/logs/attended-web.log"
    if [[ -d "$runtime_root/state/logs" && ! -L "$runtime_root/state/logs" \
        && ( ( ! -e "$log_path" && ! -L "$log_path" ) \
          || ( -f "$log_path" && ! -L "$log_path" ) ) ]] \
        && : >"$log_path" && chmod 0600 "$log_path"; then
      timeout 10 "${target_docker[@]}" logs --tail 400 "$container_name" \
        >"$log_path" 2>&1 || true
      if [[ -f "$log_path" && ! -L "$log_path" ]]; then
        target_web_log_sha256="$(sha256sum "$log_path" | awk '{print $1}')"
        target_web_log_bytes="$(wc -c <"$log_path" | tr -d ' ')"
        if grep -Eqi 'EADDRINUSE|address already in use' "$log_path"; then
          target_web_root_cause='web_port_in_use'
        elif grep -Eqi 'ERR_MODULE_NOT_FOUND|Module not found|Cannot find module' "$log_path"; then
          target_web_root_cause='web_module_missing'
        elif grep -Eqi 'EACCES|permission denied' "$log_path"; then
          target_web_root_cause='web_permission_denied'
        elif grep -Eqi 'Failed to compile|Build Error' "$log_path"; then
          target_web_root_cause='web_route_compile_failed'
        elif grep -Eqi 'unknown option|Unknown or unexpected option' "$log_path"; then
          target_web_root_cause='web_launch_option_invalid'
        fi
      fi
    else
      target_web_root_cause='web_diagnostic_log_path_unsafe'
    fi
  fi
  if [[ "$target_web_root_cause" == unreported_failure ]]; then
    if [[ "$target_web_oom_killed" == true ]]; then
      target_web_root_cause='web_container_oom'
    elif [[ "$target_web_container_state" == missing ]]; then
      target_web_root_cause='web_container_missing'
    elif [[ "$target_web_container_state" == false ]]; then
      target_web_root_cause='web_container_exited'
    elif [[ "$target_web_live_status" != 200 ]]; then
      target_web_root_cause='web_liveness_unavailable'
    elif [[ "$target_web_ready_status" == 503 && "$target_web_api_status" == 200 ]]; then
      target_web_root_cause='web_proxy_readiness_failed'
    elif [[ "$target_web_api_status" != 200 ]]; then
      target_web_root_cause='retrieval_api_readiness_lost'
    else
      target_web_root_cause='web_readiness_unavailable'
    fi
  fi
}

target_wait_web() {
  local attempts="$1" attempt=0 started next now consecutive_proxy_failures=0
  target_web_live_status='000'
  target_web_ready_status='000'
  target_web_api_status='000'
  started="$(date +%s)"
  next=$(( started + 25 ))
  for (( attempt = 0; attempt < attempts; attempt += 1 )); do
    target_container_running "$v1_3_container" || return 1
    target_web_live_status="$(target_http_status 'http://127.0.0.1:3384/api/live')"
    target_web_ready_status="$(target_http_status 'http://127.0.0.1:3384/api/ready')"
    [[ "$target_web_ready_status" == 200 ]] && return 0
    if [[ "$target_web_live_status" == 200 && "$target_web_ready_status" == 503 ]]; then
      target_web_api_status="$(target_http_status 'http://127.0.0.1:8384/ready')"
      if [[ "$target_web_api_status" == 200 ]]; then
        consecutive_proxy_failures=$(( consecutive_proxy_failures + 1 ))
        (( consecutive_proxy_failures < 5 )) || return 1
      else
        consecutive_proxy_failures=0
      fi
    else
      consecutive_proxy_failures=0
    fi
    now="$(date +%s)"
    if (( now >= next )); then
      target_emit WEB \
        "state=starting;elapsed_seconds=$(( now - started ));container=running;liveness_http=${target_web_live_status};readiness_http=${target_web_ready_status}"
      next=$(( now + 25 ))
    fi
    sleep 1
  done
  target_web_api_status="$(target_http_status 'http://127.0.0.1:8384/ready')"
  return 1
}

target_pid_is_attended_api() {
  local pid="$1" command_line=''
  [[ "$pid" =~ ^[0-9]+$ && -r "/proc/$pid/cmdline" ]] || return 1
  command_line="$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)"
  [[ "$command_line" == *"$runtime_root/scripts/ishikawa-retrieval-api"* \
      && "$command_line" == *'--serve'* ]]
}

target_stop_v1_3() {
  local pid='' remove_pid_file=true restore_errexit=false
  [[ "$-" == *e* ]] && restore_errexit=true
  set +e
  if ((${#target_docker[@]} > 0)) && target_container_exists "$v1_3_container"; then
    if target_container_running "$v1_3_container"; then
      "${target_docker[@]}" stop --time 20 "$v1_3_container" >/dev/null 2>&1 \
        || target_cleanup_failed=true
    fi
    if target_container_exists "$v1_3_container"; then
      "${target_docker[@]}" rm --force "$v1_3_container" >/dev/null 2>&1 \
        || target_cleanup_failed=true
    fi
    ! target_container_exists "$v1_3_container" || target_cleanup_failed=true
  fi
  if [[ -e "$runtime_root" || -L "$runtime_root" ]]; then
    if [[ ! -d "$runtime_root" || -L "$runtime_root" \
        || -n "$(find "$runtime_root" -type l -print -quit 2>/dev/null)" ]]; then
      target_cleanup_failed=true
      [[ -n "$target_reason" ]] || target_reason='attended_runtime_control_path_unsafe'
      [[ -n "$target_detail" ]] \
        || target_detail='The attended runtime root or one of its control paths is not a regular, symlink-free directory tree.'
      [[ -n "$target_action" ]] \
        || target_action='Preserve the unsafe path for review; do not terminate a PID or PostgreSQL cluster through it.'
      target_private_pg_started=false
      [[ "$restore_errexit" == false ]] || set -e
      return 0
    fi
  fi
  if [[ -f "$runtime_root/state/run/attended-v1.3.pid" \
      && ! -L "$runtime_root/state/run/attended-v1.3.pid" ]]; then
    IFS= read -r pid <"$runtime_root/state/run/attended-v1.3.pid" || pid=''
  fi
  [[ -n "$target_api_pid" ]] && pid="$target_api_pid"
  if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
    if target_pid_is_attended_api "$pid"; then
      kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
      for _attempt in {1..80}; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.25
      done
      if kill -0 "$pid" 2>/dev/null; then
        kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
        target_cleanup_failed=true
      fi
    else
      target_cleanup_failed=true
      remove_pid_file=false
      [[ -n "$target_reason" ]] || target_reason='attended_api_pid_identity_mismatch'
      [[ -n "$target_detail" ]] \
        || target_detail='The attended PID file identifies a live process outside the exact v1.3 runtime.'
      [[ -n "$target_action" ]] \
        || target_action='Do not terminate the unrelated process; inspect the preserved PID file and reconcile attended state explicitly.'
    fi
  fi
  [[ "$remove_pid_file" == false ]] \
    || rm -f -- "$runtime_root/state/run/attended-v1.3.pid" 2>/dev/null \
    || target_cleanup_failed=true
  if [[ "$remove_pid_file" == true \
      && ( -e "$runtime_root/state/run/attended-v1.3.pid" \
        || -L "$runtime_root/state/run/attended-v1.3.pid" ) ]]; then
    target_cleanup_failed=true
  fi
  target_api_pid=''
  if [[ -n "$target_pg_ctl" && -d "$runtime_root/state/postgresql/data" ]] \
      && "$target_pg_ctl" -D "$runtime_root/state/postgresql/data" status >/dev/null 2>&1; then
    "$target_pg_ctl" -D "$runtime_root/state/postgresql/data" -m fast -w stop >/dev/null 2>&1 \
      || target_cleanup_failed=true
  fi
  target_private_pg_started=false
  [[ "$restore_errexit" == false ]] || set -e
}

target_web_values() {
  local product_root="$1"
  PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$product_root/application/python" \
    python3 -B - "$product_root/config/product.yaml" \
      "$product_root/config/deployment.yaml" <<'PY'
import sys
from pathlib import Path
from ishikawa.deployment import validate_deployment_profile
from ishikawa.product import validate_product_profile
from ishikawa.yaml_loader import load_restricted_yaml
product = validate_product_profile(load_restricted_yaml(Path(sys.argv[1]), label="product profile"))
deployment = validate_deployment_profile(load_restricted_yaml(Path(sys.argv[2]), label="deployment profile"))
print(product.display_name)
print(product.browser_configuration_base64())
print(deployment.web.bind_host)
print(deployment.web.port)
print(deployment.web.retrieval_base_url)
PY
}

target_start_web() {
  local product_root="$1" container_name="$2" retain_on_exit="${3:-false}"
  local direct_next="${4:-false}" values=''
  local -a parsed=() mounts=() lifecycle=(--rm) web_command=()
  [[ "$retain_on_exit" == true ]] && lifecycle=()
  values="$(target_web_values "$product_root")" || return 1
  mapfile -t parsed <<<"$values"
  (( ${#parsed[@]} == 5 )) || return 1
  mounts=(
    --mount "type=bind,src=$product_root/application/web/app,dst=/opt/nextjs/app,readonly"
    --mount "type=bind,src=$product_root/application/web/components,dst=/opt/nextjs/components,readonly"
    --mount "type=bind,src=$product_root/application/web/lib,dst=/opt/nextjs/lib,readonly"
    --mount "type=bind,src=$product_root/application/web/public,dst=/opt/nextjs/public,readonly"
    --mount "type=bind,src=$product_root/application/web/package.json,dst=/opt/nextjs/package.json,readonly"
    --mount "type=bind,src=$product_root/application/web/next.config.mjs,dst=/opt/nextjs/next.config.mjs,readonly"
  )
  if [[ "$direct_next" == true ]]; then
    web_command=(next dev --hostname "${parsed[2]}" --port "${parsed[3]}")
  else
    web_command=(npm run dev -- --hostname "${parsed[2]}" --port "${parsed[3]}")
  fi
  "${target_docker[@]}" run --detach "${lifecycle[@]}" \
    --name "$container_name" --network host --restart no \
    --security-opt no-new-privileges --cap-drop ALL \
    --env "ISHIKAWA_PRODUCT_DISPLAY_NAME=${parsed[0]}" \
    --env "ISHIKAWA_PRODUCT_UI_CONFIG_BASE64=${parsed[1]}" \
    --env "ISHIKAWA_RETRIEVAL_BASE_URL=${parsed[4]}" \
    "${mounts[@]}" "node-24-slim-nextjs-16-4-1:amd64" \
    "${web_command[@]}" >/dev/null
}

target_restore_v1_2() {
  local readiness=''
  target_emit ROLLBACK 'state=start;target=v1.2'
  if [[ "$(systemctl is-active postgresql@16-main.service 2>/dev/null || true)" != active ]]; then
    sudo systemctl start postgresql@16-main.service >/dev/null 2>&1 || return 1
  fi
  for _attempt in {1..80}; do
    "$target_pg_isready" --quiet --host 127.0.0.1 --port 5432 && break
    sleep 0.25
  done
  "$target_pg_isready" --quiet --host 127.0.0.1 --port 5432 || return 1
  export ISHIKAWA_GEMMA_API_KEY="$target_gemma_key"
  export ISHIKAWA_NOMIC_API_KEY="$target_nomic_key"
  export ISHIKAWA_POSTGRESQL_PASSWORD="$target_v1_2_database_password"
  systemctl --user import-environment ISHIKAWA_GEMMA_API_KEY \
    ISHIKAWA_NOMIC_API_KEY ISHIKAWA_POSTGRESQL_PASSWORD >/dev/null 2>&1 \
    || return 1
  systemctl --user start "$v1_2_unit" >/dev/null 2>&1 || {
    systemctl --user unset-environment ISHIKAWA_GEMMA_API_KEY \
      ISHIKAWA_NOMIC_API_KEY ISHIKAWA_POSTGRESQL_PASSWORD >/dev/null 2>&1 || true
    return 1
  }
  systemctl --user unset-environment ISHIKAWA_GEMMA_API_KEY \
    ISHIKAWA_NOMIC_API_KEY ISHIKAWA_POSTGRESQL_PASSWORD >/dev/null 2>&1 || return 1
  unset ISHIKAWA_GEMMA_API_KEY ISHIKAWA_NOMIC_API_KEY ISHIKAWA_POSTGRESQL_PASSWORD
  target_wait_http 'http://127.0.0.1:1384/ready' 120 ROLLBACK || return 1
  if ! target_container_running "$v1_2_container"; then
    target_start_web "$active_v1_2_root" "$v1_2_container" || return 1
  fi
  target_wait_http 'http://127.0.0.1:3000/api/ready' 160 ROLLBACK || return 1
  readiness="$(
    ISHIKAWA_GEMMA_API_KEY="$target_gemma_key" \
    ISHIKAWA_NOMIC_API_KEY="$target_nomic_key" \
    ISHIKAWA_POSTGRESQL_PASSWORD="$target_v1_2_database_password" \
    PYTHONDONTWRITEBYTECODE=1 \
      "$active_v1_2_root/scripts/ishikawa-retrieval-api" --check-readiness
  )" || return 1
  grep -Fxq 'ishikawa_retrieval_api_readiness=pass;configuration=pass;storage=pass;postgresql=pass;gemma=pass;nomic=pass' \
    <<<"$readiness" || return 1
  [[ "$(systemctl --user is-enabled "$v1_2_unit" 2>/dev/null || true)" != enabled \
      && "$(systemctl is-enabled postgresql.service 2>/dev/null || true)" != enabled \
      && "$(systemctl is-enabled postgresql@16-main.service 2>/dev/null || true)" != enabled ]] \
    || return 1
  target_v1_2_restored=true
  target_v1_2_stopped=false
  target_emit ROLLBACK 'state=pass;v1_2_retrieval=ready;v1_2_web=ready;accepted_database=unchanged'
}

target_drop_fresh_state() {
  local restore_errexit=false safe_to_remove=true
  [[ "$-" == *e* ]] && restore_errexit=true
  set +e
  if [[ -n "$target_runtime_stage" \
      && ( -e "$target_runtime_stage" || -L "$target_runtime_stage" ) ]]; then
    if [[ "$target_runtime_stage" == "$HOME/Documents/.ishikawa-v1.3-attended."* \
        && -d "$target_runtime_stage" && ! -L "$target_runtime_stage" \
        && -z "$(find "$target_runtime_stage" -type l -print -quit 2>/dev/null)" ]]; then
      if [[ -d "$target_runtime_stage/state/postgresql/data" ]]; then
        if [[ -z "$target_pg_ctl" ]]; then
          safe_to_remove=false
        elif "$target_pg_ctl" -D "$target_runtime_stage/state/postgresql/data" status >/dev/null 2>&1; then
          "$target_pg_ctl" -D "$target_runtime_stage/state/postgresql/data" \
            -m immediate -w stop >/dev/null 2>&1 || safe_to_remove=false
        fi
        if [[ "$safe_to_remove" == true ]] \
            && "$target_pg_ctl" -D "$target_runtime_stage/state/postgresql/data" status >/dev/null 2>&1; then
          safe_to_remove=false
        fi
      fi
      if [[ "$safe_to_remove" == true ]]; then
        rm -rf -- "$target_runtime_stage" || target_cleanup_failed=true
        [[ ! -e "$target_runtime_stage" && ! -L "$target_runtime_stage" ]] \
          || target_cleanup_failed=true
      else
        target_cleanup_failed=true
      fi
    else
      target_cleanup_failed=true
    fi
  fi
  [[ "$restore_errexit" == false ]] || set -e
}

target_write_result() {
  local state="$1"
  [[ -n "$target_result_path" && "$target_result_path" == "$target_payload_root/"* ]] || return 0
  {
    printf 'target_hostname=%s;os_id=ubuntu;os_version=%s;architecture=amd64\n' \
      "$target_expected_hostname" "$target_expected_os_version"
    printf 'application_archive_sha256=%s;script_05_report_sha256=%s\n' \
      "$expected_application_sha256" "$expected_script05_report_sha256"
    printf 'database=%s;postgresql_port=5432;postgresql_cluster=isolated_durable;schema_version=5;ui_port=%s;retrieval_api_port=%s;port_1384_purpose=v1_2_runtime_and_rollback\n' \
      "$database_name" "$ui_port" "$retrieval_port"
    printf 'candidate_mutated=false;v1_2_database_mutated=false;rollback_tree_mutated=false;boot_autostart_changed=false\n'
    if [[ "$mode" == --target-launch ]]; then
      if [[ "$target_waive_v1_2_rollback" == true ]]; then
        printf 'v1_2_rollback_guarantee=waived;automatic_v1_2_restoration=false;v1_2_files_and_database_preserved=true\n'
      else
        printf 'v1_2_rollback_guarantee=verified;automatic_v1_2_restoration=true;v1_2_files_and_database_preserved=true\n'
      fi
    fi
    printf 'v1_2_restored=%s;cleanup=%s\n' \
      "$target_v1_2_restored" \
      "$([[ "$target_cleanup_failed" == false ]] && printf pass || printf blocked)"
    if [[ "$state" == pass ]]; then
      case "$mode" in
        --target-launch)
          printf 'durable_v1_3_database=ready;documents=30;pages=150;authoritative_chunks=786;retrieval_candidates=943;embeddings=943;relationship_records=240;relationship_pairs=90\n'
          printf 'attended_runtime=ready;ui=http://127.0.0.1:3384;retrieval_api=http://127.0.0.1:8384;v1_2_stopped=true\n'
          printf 'ishikawa_v1_3_emceedanko_attended_launch=pass\n'
          ;;
        --target-accept)
          printf 'human_ui_acceptance=accepted;org_lab_packaging_gate=authorized_for_separate_later_action\n'
          printf 'ishikawa_v1_3_emceedanko_human_ui_acceptance=pass\n'
          ;;
        --target-rollback)
          printf 'attended_runtime=stopped;v1_2_restored=true;durable_v1_3_database=preserved\n'
          printf 'ishikawa_v1_3_emceedanko_attended_rollback=pass\n'
          ;;
      esac
    else
      printf '%s\n' 'FAILURE DETAIL' "stage=$target_stage" \
        "reason=${target_reason:-unclassified_failure}" \
        "detail=${target_detail:-The attended target action stopped without a classified detail.}" \
        "operator_action=${target_action:-Review the named stage before rerunning Script 06.}"
      case "$mode" in
        --target-launch) printf 'ishikawa_v1_3_emceedanko_attended_launch=blocked\n' ;;
        --target-accept) printf 'ishikawa_v1_3_emceedanko_human_ui_acceptance=blocked\n' ;;
        --target-rollback) printf 'ishikawa_v1_3_emceedanko_attended_rollback=blocked\n' ;;
      esac
    fi
  } >"$target_result_path"
}

target_exit() {
  local status="$?"
  trap - ERR EXIT HUP INT TERM
  set +e
  if [[ "$target_complete" != true ]]; then
    if [[ "$mode" == --target-launch && "$target_v1_2_stopped" == true ]]; then
      target_stop_v1_3
      if [[ "$target_waive_v1_2_rollback" == true ]]; then
        target_detail="${target_detail:-The v1.3 launch failed.} Automatic v1.2 restoration was deliberately waived; v1.2 remains stopped and both database trees are preserved."
        target_action='Correct the reported v1.3 dependency and rerun Script 06 with the same waiver. Restore v1.2 only after its password and model routes are available.'
      elif ! target_restore_v1_2; then
        target_cleanup_failed=true
        target_detail="${target_detail:-The v1.3 launch failed.} Automatic v1.2 restoration also failed."
        target_action='Keep the session attended; inspect ports 3000, 1384, 3384, and 8384, then run Script 06 --rollback after correcting the reported dependency.'
      fi
    elif [[ "$mode" == --target-launch && "$target_private_pg_started" == true ]]; then
      target_stop_v1_3
    fi
    [[ "$target_durable_committed" == true ]] || target_drop_fresh_state
  fi
  if [[ -n "$target_corpus_stage" && -d "$target_corpus_stage" ]]; then
    if [[ "$target_corpus_stage" == /tmp/ishikawa-v1.3-corpus.* \
        && ! -L "$target_corpus_stage" ]]; then
      rm -rf -- "$target_corpus_stage" || target_cleanup_failed=true
      [[ ! -e "$target_corpus_stage" && ! -L "$target_corpus_stage" ]] \
        || target_cleanup_failed=true
    else
      target_cleanup_failed=true
    fi
  fi
  if [[ -n "$target_acceptance_stage" \
      && ( -e "$target_acceptance_stage" || -L "$target_acceptance_stage" ) ]]; then
    if [[ "$target_acceptance_stage" == "$runtime_root/state/reports/acceptance/.emceedanko-v1.3-human-ui."* \
        && -f "$target_acceptance_stage" && ! -L "$target_acceptance_stage" ]]; then
      rm -f -- "$target_acceptance_stage" || target_cleanup_failed=true
      [[ ! -e "$target_acceptance_stage" && ! -L "$target_acceptance_stage" ]] \
        || target_cleanup_failed=true
    else
      target_cleanup_failed=true
    fi
  fi
  unset ISHIKAWA_GEMMA_API_KEY ISHIKAWA_NOMIC_API_KEY \
    ISHIKAWA_POSTGRESQL_PASSWORD ISHIKAWA_POSTGRESQL_INGEST_PASSWORD
  if [[ "$target_payload_root" == /* && "$target_payload_root" != / \
      && -d "$target_payload_root" && ! -L "$target_payload_root" ]]; then
    rm -f -- "$target_payload_root/.postgresql-admin-password" 2>/dev/null \
      || target_cleanup_failed=true
    [[ ! -e "$target_payload_root/.postgresql-admin-password" \
        && ! -L "$target_payload_root/.postgresql-admin-password" ]] \
      || target_cleanup_failed=true
  fi
  target_gemma_key=''; target_nomic_key=''; target_v1_2_database_password=''
  target_v1_3_ingest_password=''; target_v1_3_retrieval_password=''
  if [[ "$target_cleanup_failed" == true ]]; then
    target_state='blocked'
    status=1
    [[ -n "$target_reason" ]] || target_reason='cleanup_or_restoration_failed'
    target_detail="${target_detail:-The target action failed.} Cleanup or restoration did not complete its exact proof."
    target_action="${target_action:-Review the named target stage.} Keep the session attended and reconcile the reported cleanup boundary before rerunning Script 06."
  elif [[ "$target_complete" == true && "$status" -eq 0 ]]; then
    target_state='pass'
  fi
  target_write_result "$target_state"
  if [[ "$target_state" == blocked ]]; then
    printf '%s\n' 'FAILURE DETAIL' "stage=$target_stage" \
      "reason=${target_reason:-unclassified_failure}" \
      "detail=${target_detail:-The attended target action stopped without a classified detail.}" \
      "operator_action=${target_action:-Review the named stage before rerunning Script 06.}"
  fi
  [[ "$target_state" == pass ]] && exit 0
  [[ "$status" -ne 0 ]] && exit "$status"
  exit 1
}

target_unexpected_error() {
  local status="$1" line="$2"
  trap - ERR
  [[ -n "$target_reason" ]] || {
    target_reason='unexpected_command_failure'
    target_detail="An unhandled target command failed at Script 06 line ${line} with exit code ${status}."
    target_action='Review the complete failure stage and correct it before rerunning Script 06.'
  }
  exit "$status"
}

target_parse_arguments() {
  while (( $# > 0 )); do
    case "$1" in
      --expected-hostname) target_expected_hostname="${2:-}"; shift 2 ;;
      --expected-os-version) target_expected_os_version="${2:-}"; shift 2 ;;
      --expected-architecture) target_expected_architecture="${2:-}"; shift 2 ;;
      --payload-root) target_payload_root="${2:-}"; shift 2 ;;
      --result-path) target_result_path="${2:-}"; shift 2 ;;
      --gemma-base-url) target_gemma_base_url="${2:-}"; shift 2 ;;
      --nomic-base-url) target_nomic_base_url="${2:-}"; shift 2 ;;
      --waive-v1-2-rollback) target_waive_v1_2_rollback=true; shift ;;
      *) target_fail argument_invalid "Unsupported internal target argument: $1." \
          'Invoke target actions only through the Script 06 wrapper.' 2 ;;
    esac
  done
  [[ "$target_expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ \
      && "$target_expected_os_version" =~ ^[0-9]{2}\.[0-9]{2}$ \
      && "$target_expected_architecture" == amd64 ]] \
    || target_fail target_expectation_invalid 'The expected target identity is invalid.' \
      'Correct the Script 06 target parameters.' 2
  [[ "$target_payload_root" == /* && -d "$target_payload_root" \
      && ! -L "$target_payload_root" \
      && "$target_result_path" == "$target_payload_root/"* \
      && ! -e "$target_result_path" && ! -L "$target_result_path" ]] \
    || target_fail target_path_invalid 'The target payload or result path is unsafe.' \
      'Invoke the target action through a fresh Script 06 transfer.' 2
  validate_loopback_url "$target_gemma_base_url" \
    || target_fail gemma_url_invalid 'Gemma must use a bounded loopback HTTP base URL.' \
      'Correct --gemma-base-url.' 2
  validate_loopback_url "$target_nomic_base_url" \
    || target_fail nomic_url_invalid 'Nomic must use a bounded loopback HTTP base URL.' \
      'Correct --nomic-base-url.' 2
  [[ "$target_waive_v1_2_rollback" == false || "$mode" == --target-launch ]] \
    || target_fail rollback_waiver_mode_invalid \
      'The v1.2 rollback waiver is valid only for the attended launch action.' \
      'Use the waiver only with Script 06 --run.' 2
}

target_prepare_docker() {
  if docker info >/dev/null 2>&1; then
    target_docker=(docker)
  else
    sudo -v >/dev/null \
      || target_fail privilege_authorization_failed 'Attended sudo authorization failed.' \
        'Correct sudo access and rerun Script 06.'
    target_docker=(sudo docker)
    "${target_docker[@]}" info >/dev/null 2>&1 \
      || target_fail container_runtime_unavailable 'Docker is unavailable through the attended privilege path.' \
        'Restore the accepted Docker runtime before rerunning Script 06.'
  fi
}

target_resolve_pg_binary() {
  local name="$1" destination="$2" candidate resolved
  candidate="$(type -P -- "$name" 2>/dev/null || true)"
  if [[ -n "$candidate" ]]; then
    resolved="$(readlink -f -- "$candidate" 2>/dev/null || true)"
    [[ -n "$resolved" && -f "$resolved" && -x "$resolved" ]] || candidate=''
  fi
  if [[ -z "$candidate" && -x "/usr/lib/postgresql/16/bin/$name" ]]; then
    candidate="/usr/lib/postgresql/16/bin/$name"
  fi
  [[ -n "$candidate" && "$candidate" == /* && -x "$candidate" ]] || return 1
  printf -v "$destination" '%s' "$candidate"
}

target_require_pg_binary() {
  local name="$1" destination="$2"
  target_resolve_pg_binary "$name" "$destination" \
    || target_fail "postgresql_binary_missing_${name}" \
      "Required PostgreSQL 16 command is unavailable: ${name}." \
      'Restore the accepted PostgreSQL 16 runtime before Script 06.'
}

target_verify_postgresql_toolchain() {
  local name variable binary version sharedir
  for name in initdb pg_ctl createdb psql pg_isready pg_config; do
    case "$name" in
      initdb) variable=target_pg_initdb ;;
      pg_ctl) variable=target_pg_ctl ;;
      createdb) variable=target_pg_createdb ;;
      psql) variable=target_pg_psql ;;
      pg_isready) variable=target_pg_isready ;;
      pg_config) variable=target_pg_config ;;
    esac
    target_require_pg_binary "$name" "$variable"
    binary="${!variable}"
    version="$("$binary" --version 2>/dev/null || true)"
    [[ "$version" =~ PostgreSQL\)?[[:space:]]16([.][0-9]+)?([[:space:]]|$) ]] \
      || target_fail postgresql_toolchain_version_mismatch \
        "Expected PostgreSQL 16 ${name}; observed ${version:-unreadable}." \
        'Restore the accepted PostgreSQL 16 client and server toolchain before Script 06.'
  done
  sharedir="$("$target_pg_config" --sharedir 2>/dev/null || true)"
  [[ "$sharedir" == /* && -r "$sharedir/extension/vector.control" \
      && ! -L "$sharedir/extension/vector.control" ]] \
    || target_fail pgvector_extension_unavailable \
      'The PostgreSQL 16 toolchain does not expose a safe pgvector extension control file.' \
      'Restore the accepted PostgreSQL 16 pgvector package before Script 06.'
  target_emit DATABASE 'state=preflight_pass;postgresql=16;pgvector=available;cluster_plan=isolated_durable'
}

target_verify_identity_and_payload() {
  local actual_hostname actual_architecture os_id='' os_version='' key value
  actual_hostname="$(hostname -s)"
  actual_architecture="$(dpkg --print-architecture)"
  while IFS='=' read -r key value; do
    value="${value%\"}"; value="${value#\"}"
    case "$key" in ID) os_id="$value" ;; VERSION_ID) os_version="$value" ;; esac
  done </etc/os-release
  [[ "$actual_hostname" == "$target_expected_hostname" && "$os_id" == ubuntu \
      && "$os_version" == "$target_expected_os_version" \
      && "$actual_architecture" == "$target_expected_architecture" ]] \
    || target_fail target_identity_mismatch \
      "Expected ${target_expected_hostname}/Ubuntu ${target_expected_os_version}/amd64; observed ${actual_hostname}/${os_id} ${os_version}/${actual_architecture}." \
      'Use the reviewed EmceeDanko target.'
  (cd -- "$target_payload_root" && sha256sum --check --strict SHA256SUMS >/dev/null) \
    || target_fail payload_checksum_failed 'The Script 06 target payload failed checksum verification.' \
      'Repeat the transfer from the exact local repository.'
  target_emit READINESS 'state=pass;target_identity=EmceeDanko/Ubuntu_24.04/amd64;payload_checksum=pass'
}

target_verify_candidate() {
  local candidate_checksum_output candidate_mismatch_paths candidate_mode_mismatches
  for path in "$candidate_root" "$corpus_input_root" "$active_v1_2_root" "$rollback_v1_2_root"; do
    [[ -d "$path" && ! -L "$path" ]] \
      || target_fail required_installation_unsafe "Required installation path is missing or unsafe: ${path}." \
        'Restore the Script 04 side-by-side boundary before Script 06.'
  done
  if ! candidate_checksum_output="$(cd -- "$candidate_root" \
      && sha256sum --check --strict --quiet \
        "$target_payload_root/candidate-SHA256SUMS" 2>&1)"; then
    candidate_mismatch_paths="$(printf '%s\n' "$candidate_checksum_output" \
      | awk '/: FAILED/ && count < 10 {sub(/: FAILED.*/, ""); if (count++) printf ","; printf "%s", $0} END {if (count) printf "\n"}')"
    [[ -n "$candidate_mismatch_paths" ]] || candidate_mismatch_paths='unclassified'
    target_fail staged_candidate_checksum_failed \
      "The staged v1.3 candidate no longer matches the exact Script 01 application. Mismatch paths: ${candidate_mismatch_paths}." \
      'Restage the exact qualified candidate with Script 04.'
  fi
  PYTHONDONTWRITEBYTECODE=1 python3 -B - \
    "$candidate_root" "$target_payload_root/candidate-SHA256SUMS" <<'PY' \
    || target_fail staged_candidate_inventory_failed \
      'The staged v1.3 candidate has an unexpected file or symbolic link.' \
      'Restage the exact qualified candidate with Script 04.'
import pathlib
import sys
root = pathlib.Path(sys.argv[1]).resolve(strict=True)
manifest = pathlib.Path(sys.argv[2]).resolve(strict=True)
expected = {line.partition("  ")[2] for line in manifest.read_text(encoding="utf-8").splitlines()}
actual = {item.relative_to(root).as_posix() for item in root.rglob("*") if item.is_file()}
if not expected or expected != actual or any(item.is_symlink() for item in root.rglob("*")):
    raise SystemExit(1)
PY
  if ! candidate_mode_mismatches="$(PYTHONDONTWRITEBYTECODE=1 python3 -B - \
      "$target_payload_root/candidate-MODES" "$candidate_root" <<'PY'
import pathlib
import stat
import sys

manifest = pathlib.Path(sys.argv[1]).resolve(strict=True)
root = pathlib.Path(sys.argv[2]).resolve(strict=True)
expected = {}
for line in manifest.read_text(encoding="utf-8").splitlines():
    mode, separator, name = line.partition(" ")
    if not separator or not mode.isdigit() or not name or name in expected:
        raise SystemExit(1)
    expected[name] = mode
actual = {
    item.relative_to(root).as_posix(): f"{stat.S_IMODE(item.stat().st_mode):o}"
    for item in root.rglob("*")
    if item.is_file()
}
differences = []
for name in sorted(set(expected) | set(actual)):
    if expected.get(name) != actual.get(name):
        differences.append(
            f"{name}:expected={expected.get(name, 'missing')},actual={actual.get(name, 'missing')}"
        )
if differences:
    print(",".join(differences[:10]))
    raise SystemExit(1)
PY
)"; then
    [[ -n "$candidate_mode_mismatches" ]] || candidate_mode_mismatches='unclassified'
    target_fail staged_candidate_mode_mismatch \
      "The staged v1.3 candidate file modes differ from the exact release payload. Mode mismatches: ${candidate_mode_mismatches}." \
      'Restage the exact qualified candidate with Script 04.'
  fi
  (cd -- "$corpus_input_root" \
    && sha256sum --check --strict qualification-corpus-v3.tar.gz.sha256 >/dev/null \
    && [[ "$(sha256sum qualification-corpus-v3.tar.gz | awk '{print $1}')" == "$expected_corpus_sha256" ]]) \
    || target_fail staged_corpus_checksum_failed \
      'The staged corpus-v3 input no longer matches the qualified transfer.' \
      'Restage the exact corpus-v3 input with Script 04.'
  target_emit CANDIDATE 'state=pass;application=exact;installed_layout=exact;candidate_mutated=false;corpus_v3=exact'
}

target_check_capacity() {
  local path available_kib
  [[ -d "$HOME/Documents" && ! -L "$HOME/Documents" && -w "$HOME/Documents" \
      && -d /tmp && ! -L /tmp && -w /tmp ]] \
    || target_fail deployment_filesystem_unsafe \
      'The durable Documents root or temporary filesystem is missing, linked, or not writable.' \
      'Restore the accepted target filesystem boundary before Script 06.'
  for path in "$HOME/Documents" /tmp; do
    available_kib="$(df -Pk -- "$path" 2>/dev/null | awk 'END {print $4}')"
    [[ "$available_kib" =~ ^[0-9]+$ && "$available_kib" -ge 1048576 ]] \
      || target_fail deployment_capacity_insufficient \
        "At least 1 GiB must remain available on ${path}; observed ${available_kib:-unknown} KiB." \
        'Free bounded capacity without changing the accepted v1.2 installation or database.'
  done
  target_emit READINESS 'state=pass;durable_and_temporary_capacity_minimum=1_GiB;deployment_roots=writable'
}

target_check_boot_and_ports() {
  [[ "$(systemctl --user is-enabled "$v1_2_unit" 2>/dev/null || true)" != enabled ]] \
    || target_fail v1_2_retrieval_boot_enabled 'The accepted v1.2 Retrieval API is unexpectedly enabled at boot.' \
      'Restore the accepted boot-disabled posture before Script 06.'
  [[ "$(systemctl is-enabled postgresql.service 2>/dev/null || true)" != enabled \
      && "$(systemctl is-enabled postgresql@16-main.service 2>/dev/null || true)" != enabled ]] \
    || target_fail postgresql_boot_enabled 'PostgreSQL is unexpectedly enabled at boot.' \
      'Restore the accepted boot-disabled posture before Script 06.'
  ! target_container_exists "$v1_3_container" \
    || target_fail stale_v1_3_container_found \
      'A container already owns the reserved attended v1.3 container name.' \
      'Inspect and explicitly reconcile the stale attended container before Script 06.'
  if [[ "$target_waive_v1_2_rollback" == false ]]; then
    [[ "$(systemctl --user is-active "$v1_2_unit" 2>/dev/null || true)" == active ]] \
      || target_fail v1_2_retrieval_not_active 'The accepted v1.2 Retrieval API is not active.' \
        'Restore accepted v1.2 before launching the attended candidate.'
    [[ "$(systemctl is-active postgresql@16-main.service 2>/dev/null || true)" == active ]] \
      || target_fail postgresql_not_active 'The accepted PostgreSQL 16 cluster is not active.' \
        'Restore accepted v1.2 before launching the attended candidate.'
    target_container_running "$v1_2_container" \
      || target_fail v1_2_web_not_active 'The accepted v1.2 web container is not active.' \
        'Restore accepted v1.2 before launching the attended candidate.'
    for port in 3000 1384 5432; do
      target_port_listening "$port" \
        || target_fail "v1_2_port_${port}_missing" "Required accepted listener ${port} is absent." \
          'Restore accepted v1.2 before launching the attended candidate.'
    done
  elif [[ "$(systemctl is-active postgresql@16-main.service 2>/dev/null || true)" != active ]]; then
    ! target_port_listening 5432 \
      || target_fail canonical_postgresql_port_in_use \
        'Port 5432 is occupied by a process outside the stopped host PostgreSQL unit.' \
        'Identify the unexpected listener before running the rollback-waived launch.'
  fi
  for port in "$ui_port" "$retrieval_port" "$private_postgresql_port"; do
    ! target_port_listening "$port" \
      || target_fail attended_port_in_use \
        "Reserved attended TCP port ${port} is occupied before startup." \
        'Identify the listener owner; stop only stale attended v1.3 state, then rerun.'
  done
  systemctl --user cat 'ishikawa-v1.3-retrieval-api.service' >/dev/null 2>&1 \
    && target_fail persistent_v1_3_unit_found \
      'A persistent v1.3 user unit already exists; Script 06 uses package-local execution only.' \
      'Review and remove or explicitly reconcile the unapproved unit before rerunning.'
  if [[ "$target_waive_v1_2_rollback" == true ]]; then
    target_emit READINESS 'state=pass;v1_2_rollback=waived;v1_2_runtime=not_required;ports_3384_8384_65438=free;port_5432=host_postgresql_or_free;boot_autostart=false'
  else
    target_emit READINESS 'state=pass;v1_2=ready;ports_3000_1384_5432=present;ports_3384_8384_65438=free;boot_autostart=false'
  fi
}

target_probe_models() {
  local gemma_status nomic_status
  gemma_status="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 \
    "$target_gemma_base_url/health" 2>/dev/null || true)"
  nomic_status="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 \
    "$target_nomic_base_url/health" 2>/dev/null || true)"
  [[ "$gemma_status" == 200 && "$nomic_status" == 200 ]] \
    || target_fail model_health_unavailable \
      "Gemma health=${gemma_status:-unreachable}; Nomic health=${nomic_status:-unreachable}." \
      'Restore both loopback model forwards before Script 06.'
  printf '%s' "$target_gemma_key" | PYTHONDONTWRITEBYTECODE=1 python3 -B \
    /dev/fd/3 "$target_gemma_base_url/v1/models" 3<<'PY' \
    || target_fail gemma_authenticated_probe_failed \
      'Gemma rejected the protected credential or models response contract.' \
      'Correct the Gemma key/forward before rerunning Script 06.'
import json, sys, urllib.request
key = sys.stdin.buffer.read(4097).decode("utf-8")
request = urllib.request.Request(sys.argv[1], headers={"Authorization": "Bearer " + key})
with urllib.request.urlopen(request, timeout=30) as response:
    body = response.read(1048577)
if response.status != 200 or not isinstance(json.loads(body).get("data"), list):
    raise SystemExit(1)
PY
  printf '%s' "$target_nomic_key" | PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH="$candidate_root/application/python" python3 -B /dev/fd/3 \
    "$target_nomic_base_url" 3<<'PY' \
    || target_fail nomic_authenticated_probe_failed \
      'Nomic rejected the protected credential, embedding, or tokenization contract.' \
      'Correct the Nomic key/forward before rerunning Script 06.'
import sys
from ishikawa.native_adapters import EmbeddingEndpoint, build_query_embedding_request, execute_query_embedding_request
from ishikawa.tokenization import TokenizationEndpoint, native_tokenization_exchange, prepare_tokenization_request, validate_tokenization_response
base = sys.argv[1]
key = sys.stdin.buffer.read(1025).decode("utf-8")
execute_query_embedding_request(EmbeddingEndpoint(base + "/v1/embeddings", 30, 1048576), build_query_embedding_request("Ishikawa attended readiness"), key)
prepared = prepare_tokenization_request(TokenizationEndpoint(base + "/tokenize", 30, 1048576), model="nomic-ai/nomic-embed-text-v1.5", prompt="search_document: Ishikawa attended readiness", api_key=key)
validate_tokenization_response(native_tokenization_exchange(prepared), minimum_model_length=2048)
PY
  target_emit MODEL 'state=pass;gemma_authenticated=true;nomic_embedding=true;nomic_tokenization=true'
}

target_validate_v1_2_restore_credentials() {
  local readiness='' readiness_marker='unavailable' readiness_status=0
  if readiness="$(
    ISHIKAWA_GEMMA_API_KEY="$target_gemma_key" \
    ISHIKAWA_NOMIC_API_KEY="$target_nomic_key" \
    ISHIKAWA_POSTGRESQL_PASSWORD="$target_v1_2_database_password" \
    PYTHONDONTWRITEBYTECODE=1 \
      "$active_v1_2_root/scripts/ishikawa-retrieval-api" --check-readiness
  )"; then
    readiness_status=0
  else
    readiness_status="$?"
  fi
  if (( readiness_status != 0 )); then
    if [[ "$readiness" =~ ^ishikawa_retrieval_api_readiness=blocked\;configuration=(pass|blocked)\;storage=(pass|blocked)\;postgresql=(pass|blocked)\;gemma=(pass|blocked)\;nomic=(pass|blocked)$ ]]; then
      readiness_marker="$readiness"
    fi
    target_fail v1_2_restore_preflight_failed \
      "The v1.2 real readiness path failed;readiness_marker=${readiness_marker}." \
      'Restore the configured v1.2 Gemma/Nomic forwards or correct its PostgreSQL retrieval password according to the blocked component before switchover.'
  fi
  grep -Fxq 'ishikawa_retrieval_api_readiness=pass;configuration=pass;storage=pass;postgresql=pass;gemma=pass;nomic=pass' \
    <<<"$readiness" \
    || target_fail v1_2_restore_marker_invalid \
      'The v1.2 readiness command omitted its exact all-pass marker.' \
      'Do not stop v1.2; correct its dependency or configuration state.'
  target_emit ROLLBACK 'state=preflight_pass;v1_2_restart_credentials=verified'
}

target_database_state() {
  local runtime_present=false receipt_present=false data_present=false
  [[ ! -e "$runtime_root" && ! -L "$runtime_root" ]] || runtime_present=true
  [[ -f "$runtime_root/state/deployment/emceedanko-v1.3-attended.json" \
      && ! -L "$runtime_root/state/deployment/emceedanko-v1.3-attended.json" ]] \
    && receipt_present=true
  [[ -f "$runtime_root/state/postgresql/data/PG_VERSION" \
      && ! -L "$runtime_root/state/postgresql/data/PG_VERSION" ]] \
    && data_present=true
  if [[ "$runtime_present" == false ]]; then
    target_database_action='fresh'
    return 0
  fi
  [[ -d "$runtime_root" && ! -L "$runtime_root" \
      && -z "$(find "$runtime_root" -type l -print -quit 2>/dev/null)" ]] \
    || target_fail durable_runtime_control_path_unsafe \
      'The existing attended runtime root or one of its paths is not a safe, symlink-free directory tree.' \
      'Preserve and review the existing attended path; do not reuse or delete it through Script 06.'
  if [[ "$runtime_present" == true && "$receipt_present" == true \
      && "$data_present" == true ]]; then
    [[ ! -e "$runtime_root/state/run/attended-v1.3.pid" \
        && ! -L "$runtime_root/state/run/attended-v1.3.pid" ]] \
      || target_fail stale_attended_pid_file_found \
        'The durable runtime contains a stale or active attended API PID file.' \
        'Reconcile the prior attended process through Script 06 --rollback before reuse.'
    ! "$target_pg_ctl" -D "$runtime_root/state/postgresql/data" status >/dev/null 2>&1 \
      || target_fail attended_postgresql_already_running \
        'The durable v1.3 PostgreSQL cluster is already running during v1.2 preflight.' \
        'Reconcile the prior attended cluster through Script 06 --rollback before reuse.'
    target_database_action='reuse'
    return 0
  fi
  target_fail partial_v1_3_state_found \
    "Observed runtime_present=${runtime_present};receipt_present=${receipt_present};postgresql_data_present=${data_present}." \
    'Do not merge partial state. Review the exact v1.3 objects and choose an explicit cleanup or recovery action.'
}

target_configure_runtime() {
  local root="$1" selected_port="$2"
  PYTHONDONTWRITEBYTECODE=1 python3 -B - \
    "$root/config/deployment.yaml" "$root/config/runtime_dependencies.yaml" \
    "$root/config/ingestion_dependencies.yaml" "$root/config/retrieval_service_profile.yaml" \
    "$selected_port" "$target_gemma_base_url" "$target_nomic_base_url" <<'PY'
from pathlib import Path
import sys, yaml
deployment_path, runtime_path, ingestion_path, service_path = map(Path, sys.argv[1:5])
postgresql_port, gemma, nomic = sys.argv[5:8]
deployment = yaml.safe_load(deployment_path.read_text(encoding="utf-8"))
deployment["web"]["port"] = 3384
deployment["web"]["retrieval_base_url"] = "http://127.0.0.1:8384"
deployment["retrieval"]["port"] = 8384
deployment["postgresql"]["port"] = int(postgresql_port)
deployment_path.write_text(yaml.safe_dump(deployment, sort_keys=False), encoding="utf-8")
runtime = yaml.safe_load(runtime_path.read_text(encoding="utf-8"))
runtime["gemma"]["chat_endpoint_url"] = gemma + "/v1/chat/completions"
runtime["gemma"]["tokenization_endpoint_url"] = gemma + "/tokenize"
runtime["gemma"]["health_endpoint_url"] = gemma + "/health"
runtime["nomic"]["embedding_endpoint_url"] = nomic + "/v1/embeddings"
runtime["nomic"]["health_endpoint_url"] = nomic + "/health"
runtime["postgresql"]["database_name"] = "rag_catalog"
runtime["postgresql"]["database_user"] = "rag_retrieval"
runtime_path.write_text(yaml.safe_dump(runtime, sort_keys=False), encoding="utf-8")
ingestion = yaml.safe_load(ingestion_path.read_text(encoding="utf-8"))
ingestion["nomic"]["embedding_endpoint_url"] = nomic + "/v1/embeddings"
ingestion["nomic"]["tokenization_endpoint_url"] = nomic + "/tokenize"
ingestion["postgresql"]["database_name"] = "rag_catalog"
ingestion["postgresql"]["database_user"] = "rag_ingest"
ingestion_path.write_text(yaml.safe_dump(ingestion, sort_keys=False), encoding="utf-8")
service = yaml.safe_load(service_path.read_text(encoding="utf-8"))
service["network"]["default_port"] = 8384
service_path.write_text(yaml.safe_dump(service, sort_keys=False), encoding="utf-8")
PY
}

target_validate_runtime_parity() {
  local root="$1" corpus_root="$2"
  PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$root/application/python" python3 -B - \
    "$candidate_root" "$root" "$target_payload_root/candidate-SHA256SUMS" \
    "$corpus_root" "$manifest_name" <<'PY'
import hashlib
import pathlib
import stat
import sys

from ishikawa.validators import validate_document_catalog, validate_ingestion_manifest
from ishikawa.yaml_loader import load_restricted_yaml

candidate, runtime, manifest_path, corpus = (
    pathlib.Path(value).resolve(strict=True) for value in sys.argv[1:5]
)
manifest_name = sys.argv[5]
expected = {
    line.partition("  ")[2]
    for line in manifest_path.read_text(encoding="utf-8").splitlines()
}
def fail(reason: str) -> None:
    print(f"installed_layout_parity=blocked;reason={reason}", file=sys.stderr)
    raise SystemExit(1)

mutable = {
    "config/deployment.yaml",
    "config/document_catalog.yaml",
    "config/ingestion_dependencies.yaml",
    "config/retrieval_service_profile.yaml",
    "config/runtime_dependencies.yaml",
}
for relative in expected - mutable:
    source = candidate / relative
    installed = runtime / relative
    if (
        not installed.is_file()
        or installed.is_symlink()
        or hashlib.sha256(source.read_bytes()).digest()
        != hashlib.sha256(installed.read_bytes()).digest()
        or stat.S_IMODE(source.stat().st_mode) != stat.S_IMODE(installed.stat().st_mode)
    ):
        fail(f"candidate_file_mismatch:{relative}")
allowed_addition = f"config/ingestion/pending/{manifest_name}"
for item in runtime.rglob("*"):
    if item.is_symlink():
        fail(f"runtime_symlink:{item.relative_to(runtime).as_posix()}")
    if not item.is_file():
        continue
    relative = item.relative_to(runtime).as_posix()
    if relative in expected or relative == allowed_addition:
        continue
    if relative.startswith("state/") or relative.startswith("corpus/source/"):
        continue
    fail(f"unexpected_runtime_file:{relative}")
source_files = sorted((corpus / "source").glob("*.pdf"))
runtime_files = sorted((runtime / "corpus" / "source").glob("*.pdf"))
if len(source_files) != 30 or [item.name for item in source_files] != [item.name for item in runtime_files]:
    fail("corpus_source_inventory_mismatch")
for source, installed in zip(source_files, runtime_files, strict=True):
    if hashlib.sha256(source.read_bytes()).digest() != hashlib.sha256(installed.read_bytes()).digest():
        fail(f"corpus_source_digest_mismatch:{source.name}")
validate_document_catalog(
    load_restricted_yaml(runtime / "config" / "document_catalog.yaml", label="attended catalog")
)
validate_ingestion_manifest(
    load_restricted_yaml(
        runtime / "config" / "ingestion" / "pending" / manifest_name,
        label="attended manifest",
    )
)
PY
}

target_validate_database_counts() {
  local root="$1" port="$2" observed expected='30;150;786;943;157;943;240;90'
  observed="$("$target_pg_psql" -X -A -t -q \
    -h "$root/state/postgresql/socket" -p "$port" -v ON_ERROR_STOP=1 \
    -d "$database_name" <<'SQL'
SELECT
  (SELECT count(*) FROM rag_search.active_documents)::text || ';' ||
  (SELECT sum(page_count) FROM rag_search.active_documents)::text || ';' ||
  (SELECT count(*) FROM rag_search.active_chunks)::text || ';' ||
  (SELECT count(*) FROM rag_search.active_retrieval_candidates)::text || ';' ||
  (SELECT count(*) FROM rag_search.active_retrieval_candidates WHERE retrieval_scoring_only)::text || ';' ||
  (SELECT count(*) FROM rag_search.active_retrieval_embeddings)::text || ';' ||
  (SELECT count(*) FROM rag_search.active_relationships)::text || ';' ||
  (SELECT count(*) FROM (SELECT DISTINCT source_document_id, target_identity FROM rag_search.active_relationships) AS pairs)::text;
SQL
)" || target_fail database_inventory_failed 'The durable v1.3 corpus inventory query failed.' \
    'Inspect only the isolated v1.3 database before rerunning Script 06.'
  [[ "$observed" == "$expected" ]] \
    || target_fail database_inventory_mismatch \
      "Expected ${expected}; observed ${observed:-none}." \
      'Do not launch the UI; review the isolated v1.3 ingestion state.'
}

target_verify_schema_identity() {
  local root="$1" port="$2" packaged application installed expected
  packaged="$(sha256sum "$target_payload_root/database/schema.sql" | awk '{print $1}')"
  application="$(PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$root/application/python" \
    python3 -B -c 'from ishikawa.persistence import CONSOLIDATED_SCHEMA_V5_SHA256; print(CONSOLIDATED_SCHEMA_V5_SHA256)')" \
    || target_fail application_schema_identity_unreadable \
      'The v1.3 application schema identity could not be loaded.' \
      'Restore the exact candidate before launch.'
  installed="$("$target_pg_psql" -X -A -t -q \
    -h "$root/state/postgresql/socket" -p "$port" -v ON_ERROR_STOP=1 \
    -d "$database_name" -c "SELECT string_agg(migration_id || '|' || migration_sha256 || '|' || schema_version, ';' ORDER BY schema_version) FROM rag.schema_migrations;")" \
    || target_fail installed_schema_identity_unreadable \
      'The v1.3 schema ledger could not be read.' \
      'Inspect the isolated v1.3 database.'
  expected="ishikawa_consolidated_schema_v5|${packaged}|5"
  [[ "$application" == "$packaged" && "$installed" == "$expected" ]] \
    || target_fail schema_identity_mismatch \
      "application=${application:-missing};packaged=${packaged};installed=${installed:-missing}." \
      'Do not launch v1.3; restore the exact release/schema identity.'
}

target_authenticate_v1_3_roles() {
  local port="$1"
  PGPASSWORD="$target_v1_3_ingest_password" "$target_pg_psql" -X -A -t -q -v ON_ERROR_STOP=1 \
    -h 127.0.0.1 -p "$port" -U "$ingest_role" -d "$database_name" -c 'SELECT 1;' \
    | grep -Fxq 1 \
    || target_fail v1_3_ingest_credential_failed \
      'The entered v1.3 ingestion password does not authenticate to the isolated database.' \
      'Re-enter the password originally used to create the durable v1.3 role.'
  PGPASSWORD="$target_v1_3_retrieval_password" "$target_pg_psql" -X -A -t -q -v ON_ERROR_STOP=1 \
    -h 127.0.0.1 -p "$port" -U "$retrieval_role" -d "$database_name" -c 'SELECT 1;' \
    | grep -Fxq 1 \
    || target_fail v1_3_retrieval_credential_failed \
      'The entered v1.3 retrieval password does not authenticate to the isolated database.' \
      'Re-enter the password originally used to create the durable v1.3 role.'
}

target_create_database_and_runtime() {
  local escaped_ingest escaped_retrieval schema_marker config_marker admin_password_file
  local corpus_root postgresql_root
  target_stage='durable_database_creation'
  target_runtime_stage="$(mktemp -d "$HOME/Documents/.ishikawa-v1.3-attended.XXXXXX")"
  cp -a -- "$candidate_root/." "$target_runtime_stage/"
  target_corpus_stage="$(mktemp -d /tmp/ishikawa-v1.3-corpus.XXXXXX)"
  tar -xzf "$corpus_input_root/qualification-corpus-v3.tar.gz" -C "$target_corpus_stage"
  corpus_root="$target_corpus_stage/qualification-corpus-v3"
  [[ -d "$corpus_root" && ! -L "$corpus_root" ]] \
    || target_fail corpus_layout_invalid 'The extracted corpus-v3 root is unsafe.' \
      'Restage the exact Script 03 corpus input.'
  (cd -- "$corpus_root" && sha256sum --check --strict SHA256SUMS >/dev/null) \
    || target_fail corpus_internal_checksum_failed 'Extracted corpus-v3 files failed verification.' \
      'Restage the exact Script 03 corpus input.'
  find "$corpus_root" -type l -print -quit | grep -q . \
    && target_fail corpus_symlink_found 'The corpus-v3 archive contains a symbolic link.' \
      'Re-export the reviewed qualification corpus.'
  cp -- "$corpus_root"/source/*.pdf "$target_runtime_stage/corpus/source/"
  rm -- "$target_runtime_stage/config/document_catalog.yaml"
  PYTHONDONTWRITEBYTECODE=1 python3 -B "$target_payload_root/create-corpus-v3-ingestion-config.py" \
    --corpus-root "$corpus_root" --source-root "$target_runtime_stage/corpus/source" \
    --config-root "$target_runtime_stage/config" --manifest-name "$manifest_name" \
    >"$target_payload_root/config-generation.stdout" \
    || target_fail ingestion_configuration_generation_failed \
      'The exact corpus-v3 catalog and manifest could not be generated.' \
      'Review the checksum-bound corpus metadata before database creation.'
  grep -Eq '^corpus_v3_ingestion_config=pass;documents=30;catalog_sha256=[0-9a-f]{64};manifest_sha256=[0-9a-f]{64};source_manifest_sha256=[0-9a-f]{64};created_on_target=true$' \
    "$target_payload_root/config-generation.stdout" \
    || target_fail ingestion_configuration_marker_invalid \
      'The catalog/manifest generator omitted its exact pass marker.' \
      'Restore the reviewed generator before database creation.'
  postgresql_root="$target_runtime_stage/state/postgresql"
  mkdir -m 0700 -p -- "$postgresql_root/data" "$postgresql_root/socket"
  admin_password_file="$target_payload_root/.postgresql-admin-password"
  PYTHONDONTWRITEBYTECODE=1 python3 -B -c 'import secrets; print(secrets.token_urlsafe(48))' \
    >"$admin_password_file"
  chmod 0600 "$admin_password_file"
  "$target_pg_initdb" -D "$postgresql_root/data" --username="$(id -un)" \
    --encoding=UTF8 --no-locale --auth-local=trust --auth-host=scram-sha-256 \
    --pwfile="$admin_password_file" \
    >"$target_payload_root/initdb.stdout" 2>"$target_payload_root/initdb.stderr" \
    || target_fail private_postgresql_initialization_failed \
      'The isolated durable PostgreSQL 16 cluster could not be initialized.' \
      'Inspect PostgreSQL capacity and the protected initialization log.'
  rm -f -- "$admin_password_file"
  "$target_pg_ctl" -D "$postgresql_root/data" \
    -o "-k $postgresql_root/socket -h 127.0.0.1 -p $private_postgresql_port" \
    -l "$postgresql_root/postgresql.log" -w start \
    >"$target_payload_root/pg-start.stdout" 2>"$target_payload_root/pg-start.stderr" \
    || target_fail private_postgresql_start_failed \
      'The isolated durable PostgreSQL cluster did not start on private port 65438.' \
      'Verify that port 65438 is free and inspect the protected cluster log.'
  target_private_pg_started=true
  escaped_ingest="${target_v1_3_ingest_password//\'/\'\'}"
  escaped_retrieval="${target_v1_3_retrieval_password//\'/\'\'}"
  printf '%s\n' \
    'BEGIN;' \
    "CREATE ROLE $owner_role NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;" \
    "CREATE ROLE $ingest_role LOGIN PASSWORD '$escaped_ingest' NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOREPLICATION NOBYPASSRLS;" \
    "CREATE ROLE $retrieval_role LOGIN PASSWORD '$escaped_retrieval' NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOREPLICATION NOBYPASSRLS;" \
    'COMMIT;' \
    | "$target_pg_psql" -X -q -h "$postgresql_root/socket" \
        -p "$private_postgresql_port" -v ON_ERROR_STOP=1 -d postgres >/dev/null \
    || target_fail v1_3_role_creation_failed 'The isolated v1.3 roles could not be created.' \
      'Inspect role collisions and PostgreSQL authority before rerunning.'
  "$target_pg_createdb" -h "$postgresql_root/socket" -p "$private_postgresql_port" \
    --owner="$owner_role" --encoding=UTF8 --template=template0 "$database_name" \
    || target_fail v1_3_database_creation_failed 'The isolated v1.3 database could not be created.' \
      'Inspect PostgreSQL authority and capacity before rerunning.'
  if ! "$target_pg_psql" -X -q -h "$postgresql_root/socket" \
    -p "$private_postgresql_port" -v ON_ERROR_STOP=1 -d "$database_name" <<'SQL'
CREATE EXTENSION vector;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
SQL
  then
    target_fail pgvector_extension_creation_failed \
      'The isolated v1.3 database could not install the required vector extension.' \
      'Inspect the accepted PostgreSQL 16 pgvector package before rerunning.'
  fi
  chmod 0755 "$target_payload_root" "$target_payload_root/database"
  chmod 0755 "$target_payload_root/database/install-schema"
  chmod 0644 "$target_payload_root/database/schema.sql" "$target_payload_root/database/SHA256SUMS"
  schema_marker="$(PGHOST="$postgresql_root/socket" PGPORT="$private_postgresql_port" \
    bash "$target_payload_root/database/install-schema" \
      --database "$database_name" --owner-role "$owner_role" \
      --ingest-role "$ingest_role" --retrieval-role "$retrieval_role")" \
    || target_fail schema_install_failed 'The exact schema-v5 installer failed in the isolated database.' \
      'Inspect the final schema package and PostgreSQL prerequisites.'
  grep -Eq '^ishikawa_schema_install=pass;schema_version=5;schema_sha256=[0-9a-f]{64}$' \
    <<<"$schema_marker" \
    || target_fail schema_install_marker_invalid 'The schema installer omitted its exact pass marker.' \
      'Restore the exact Script 01 database payload.'
  target_configure_runtime "$target_runtime_stage" "$private_postgresql_port"
  target_validate_runtime_parity "$target_runtime_stage" "$corpus_root" \
    || target_fail installed_runtime_parity_failed \
      'The attended runtime differs from the exact candidate outside the approved configuration, corpus, and state surfaces.' \
      'Do not create or launch a divergent attended installation.'
  config_marker="$(env -u ISHIKAWA_GEMMA_API_KEY -u ISHIKAWA_NOMIC_API_KEY \
    -u ISHIKAWA_POSTGRESQL_PASSWORD PYTHONDONTWRITEBYTECODE=1 \
    "$target_runtime_stage/scripts/ishikawa-retrieval-api" --check-config)" \
    || target_fail configured_runtime_invalid 'The real v1.3 configuration validator rejected the attended profile.' \
      'Correct ports 3384/8384 and the isolated database profile.'
  grep -Eq '^ishikawa_retrieval_api_configuration=pass;policy_digest=[0-9a-f]{64};credential_read=false;dependency_contact=false$' \
    <<<"$config_marker" \
    || target_fail configured_runtime_marker_invalid 'The real configuration validator omitted its exact marker.' \
      'Treat the attended profile as blocked.'
  target_stage='corpus_v3_ingestion'
  target_emit INGEST 'state=start;mode=validate-only;documents=30'
  ISHIKAWA_NOMIC_API_KEY="$target_nomic_key" \
  ISHIKAWA_POSTGRESQL_INGEST_PASSWORD="$target_v1_3_ingest_password" \
  PYTHONDONTWRITEBYTECODE=1 \
    timeout --signal=TERM --kill-after=30s 3600s \
    "$target_runtime_stage/scripts/ishikawa-ingest" --validate-only --manifest "$manifest_name" \
    >"$target_payload_root/ingest-validate.stdout" \
    2>"$target_payload_root/ingest-validate.stderr" \
    || target_fail ingestion_validation_failed \
      "The real ingestion command rejected the fresh corpus-v3 plan;root_cause=$(target_safe_root_cause "$target_payload_root/ingest-validate.stdout" "$target_payload_root/ingest-validate.stderr")." \
      'Review the protected target ingestion report before rerunning.'
  grep -Fxq 'actions=add:30,reprocess:0,retire:0,reuse:0,revise:0' \
    "$target_payload_root/ingest-validate.stdout" \
    || target_fail ingestion_plan_invalid 'The initial v1.3 plan was not exactly thirty additions.' \
      'Do not publish; inspect only the isolated build database.'
  target_emit INGEST 'state=start;mode=publish;documents=30'
  ISHIKAWA_NOMIC_API_KEY="$target_nomic_key" \
  ISHIKAWA_POSTGRESQL_INGEST_PASSWORD="$target_v1_3_ingest_password" \
  PYTHONDONTWRITEBYTECODE=1 \
    timeout --signal=TERM --kill-after=30s 7200s \
    "$target_runtime_stage/scripts/ishikawa-ingest" --publish --manifest "$manifest_name" \
    >"$target_payload_root/ingest-publish.stdout" \
    2>"$target_payload_root/ingest-publish.stderr" \
    || target_fail ingestion_publication_failed \
      "The real corpus-v3 publication failed in the isolated v1.3 database;root_cause=$(target_safe_root_cause "$target_payload_root/ingest-publish.stdout" "$target_payload_root/ingest-publish.stderr")." \
      'Review the protected target ingestion report and named dependency.'
  grep -Fxq 'ishikawa_ingestion=pass;exit_code=0' "$target_payload_root/ingest-publish.stdout" \
    || target_fail ingestion_publication_marker_invalid \
      'The ingestion command exited without its exact pass marker.' \
      'Treat the isolated database build as failed.'
  target_validate_database_counts "$target_runtime_stage" "$private_postgresql_port"
  target_verify_schema_identity "$target_runtime_stage" "$private_postgresql_port"
  target_authenticate_v1_3_roles "$private_postgresql_port"
  "$target_pg_ctl" -D "$postgresql_root/data" -m fast -w stop >/dev/null \
    || target_fail private_postgresql_stop_failed \
      'The newly built isolated PostgreSQL cluster did not stop after validation.' \
      'Inspect only the v1.3 private cluster before rerunning.'
  target_private_pg_started=false
  target_configure_runtime "$target_runtime_stage" 5432
  config_marker="$(env -u ISHIKAWA_GEMMA_API_KEY -u ISHIKAWA_NOMIC_API_KEY \
    -u ISHIKAWA_POSTGRESQL_PASSWORD PYTHONDONTWRITEBYTECODE=1 \
    "$target_runtime_stage/scripts/ishikawa-retrieval-api" --check-config)" \
    || target_fail final_runtime_configuration_invalid \
      'The final port-5432 attended configuration failed its real validator.' \
      'Do not commit or launch the attended runtime.'
  grep -Eq '^ishikawa_retrieval_api_configuration=pass;policy_digest=[0-9a-f]{64};credential_read=false;dependency_contact=false$' \
    <<<"$config_marker" \
    || target_fail final_runtime_configuration_marker_invalid \
      'The final attended configuration omitted its exact validation marker.' \
      'Treat the attended runtime build as failed.'
  mkdir -m 0700 -p -- "$target_runtime_stage/state/deployment"
  PYTHONDONTWRITEBYTECODE=1 python3 -B - \
    "$target_runtime_stage/state/deployment/emceedanko-v1.3-attended.json" \
    "$expected_application_sha256" "$expected_script05_report_sha256" \
    "$(sha256sum "$target_payload_root/database/schema.sql" | awk '{print $1}')" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
record = {
    "application_archive_sha256": sys.argv[2],
    "boot_autostart": False,
    "corpus_identity": "synthetic-corpus-v3",
    "database_name": "rag_catalog",
    "documents": 30,
    "postgresql_cluster": "isolated_durable",
    "postgresql_private_validation_port": 65438,
    "postgresql_runtime_port": 5432,
    "relationship_pairs": 90,
    "relationship_records": 240,
    "retrieval_api_port": 8384,
    "schema_sha256": sys.argv[4],
    "schema_version": 5,
    "script_05_report_sha256": sys.argv[3],
    "ui_port": 3384,
}
path.write_text(json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
path.chmod(0o600)
PY
  mv -- "$target_runtime_stage" "$runtime_root"
  target_runtime_stage=''
  target_durable_committed=true
  target_emit DATABASE 'state=pass;action=created;scope=isolated_durable_cluster;private_validation_port=65438;runtime_port=5432;schema=5;documents=30;pages=150;relationships=240/90'
}

target_reuse_database_and_runtime() {
  local config_marker corpus_root
  target_stage='durable_database_revalidation'
  PYTHONDONTWRITEBYTECODE=1 python3 -B - \
    "$runtime_root/state/deployment/emceedanko-v1.3-attended.json" \
    "$(sha256sum "$target_payload_root/database/schema.sql" | awk '{print $1}')" <<'PY' \
    || target_fail durable_receipt_invalid \
      'The existing v1.3 attended receipt does not match the frozen deployment contract.' \
      'Review the isolated runtime/database; do not merge or overwrite it.'
import json, pathlib, sys
record = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
expected = {
    "application_archive_sha256": "53da57b745fb4c8be6335896d05bdb6f63f2de3494862b99acca09e156863f3c",
    "boot_autostart": False,
    "corpus_identity": "synthetic-corpus-v3",
    "database_name": "rag_catalog",
    "documents": 30,
    "postgresql_cluster": "isolated_durable",
    "postgresql_private_validation_port": 65438,
    "postgresql_runtime_port": 5432,
    "relationship_pairs": 90,
    "relationship_records": 240,
    "retrieval_api_port": 8384,
    "schema_sha256": sys.argv[2],
    "schema_version": 5,
    "script_05_report_sha256": "854240b564148f38853b183852ca98ac12d38ef3a57bb6ed513116270d7a98c0",
    "ui_port": 3384,
}
for key, value in expected.items():
    if record.get(key) != value:
        raise SystemExit(1)
PY
  find "$runtime_root" -type l -print -quit | grep -q . \
    && target_fail durable_runtime_symlink_found \
      'The existing v1.3 attended runtime contains a symbolic link.' \
      'Review the isolated runtime before reuse.'
  target_corpus_stage="$(mktemp -d /tmp/ishikawa-v1.3-corpus.XXXXXX)"
  tar -xzf "$corpus_input_root/qualification-corpus-v3.tar.gz" -C "$target_corpus_stage" \
    || target_fail corpus_extraction_failed \
      'The exact staged corpus could not be extracted for runtime parity.' \
      'Restage the Script 03 corpus input.'
  corpus_root="$target_corpus_stage/qualification-corpus-v3"
  [[ -d "$corpus_root" && ! -L "$corpus_root" ]] \
    || target_fail corpus_layout_invalid 'The extracted corpus-v3 root is unsafe.' \
      'Restage the Script 03 corpus input.'
  (cd -- "$corpus_root" && sha256sum --check --strict SHA256SUMS >/dev/null) \
    || target_fail corpus_internal_checksum_failed \
      'The extracted corpus-v3 input failed internal verification.' \
      'Restage the exact Script 03 corpus input.'
  find "$corpus_root" -type l -print -quit | grep -q . \
    && target_fail corpus_symlink_found 'The corpus-v3 archive contains a symbolic link.' \
      'Re-export the reviewed qualification corpus.'
  target_validate_runtime_parity "$runtime_root" "$corpus_root" \
    || target_fail reused_runtime_parity_failed \
      'The durable attended runtime differs from the exact candidate or corpus outside approved mutable surfaces.' \
      'Do not overwrite or launch the divergent runtime; review it explicitly.'
  mkdir -m 0700 -p -- "$runtime_root/state/postgresql/socket"
  "$target_pg_ctl" -D "$runtime_root/state/postgresql/data" \
    -o "-k $runtime_root/state/postgresql/socket -h 127.0.0.1 -p $private_postgresql_port" \
    -l "$runtime_root/state/postgresql/postgresql.log" -w start \
    >"$target_payload_root/pg-reuse-start.stdout" 2>"$target_payload_root/pg-reuse-start.stderr" \
    || target_fail reused_private_postgresql_start_failed \
      'The durable v1.3 PostgreSQL cluster did not start on private validation port 65438.' \
      'Inspect only the v1.3 private cluster log and port ownership.'
  target_private_pg_started=true
  target_validate_database_counts "$runtime_root" "$private_postgresql_port"
  target_verify_schema_identity "$runtime_root" "$private_postgresql_port"
  target_authenticate_v1_3_roles "$private_postgresql_port"
  config_marker="$(env -u ISHIKAWA_GEMMA_API_KEY -u ISHIKAWA_NOMIC_API_KEY \
    -u ISHIKAWA_POSTGRESQL_PASSWORD PYTHONDONTWRITEBYTECODE=1 \
    "$runtime_root/scripts/ishikawa-retrieval-api" --check-config)" \
    || target_fail reused_runtime_configuration_invalid \
      'The existing v1.3 attended runtime failed its real configuration validator.' \
      'Review the isolated runtime; do not overwrite it.'
  grep -Eq '^ishikawa_retrieval_api_configuration=pass;policy_digest=[0-9a-f]{64};credential_read=false;dependency_contact=false$' \
    <<<"$config_marker" \
    || target_fail reused_runtime_configuration_marker_invalid \
      'The existing runtime omitted its exact configuration pass marker.' \
      'Review the isolated runtime before reuse.'
  "$target_pg_ctl" -D "$runtime_root/state/postgresql/data" -m fast -w stop >/dev/null \
    || target_fail reused_private_postgresql_stop_failed \
      'The durable v1.3 PostgreSQL validation cluster did not stop cleanly.' \
      'Inspect only the v1.3 private cluster before switchover.'
  target_private_pg_started=false
  target_durable_committed=true
  target_emit DATABASE 'state=pass;action=reused_exact;scope=isolated_durable_cluster;private_validation_port=65438;runtime_port=5432;schema=5;documents=30;pages=150;relationships=240/90'
}

target_prelaunch_readiness() {
  local readiness
  readiness="$(
    ISHIKAWA_GEMMA_API_KEY="$target_gemma_key" \
    ISHIKAWA_NOMIC_API_KEY="$target_nomic_key" \
    ISHIKAWA_POSTGRESQL_PASSWORD="$target_v1_3_retrieval_password" \
    PYTHONDONTWRITEBYTECODE=1 \
      "$runtime_root/scripts/ishikawa-retrieval-api" --check-readiness
  )" || target_fail v1_3_readiness_preflight_failed \
    'The real v1.3 readiness path rejected configuration, storage, database, Gemma, or Nomic.' \
    'Allow automatic v1.2 restoration and correct the named dependency before retrying.'
  grep -Fxq 'ishikawa_retrieval_api_readiness=pass;configuration=pass;storage=pass;postgresql=pass;gemma=pass;nomic=pass' \
    <<<"$readiness" \
    || target_fail v1_3_readiness_marker_invalid \
      'The v1.3 readiness command omitted its exact all-pass marker.' \
      'Allow automatic v1.2 restoration and review the attended runtime.'
  target_emit READINESS 'state=pass;v1_3_configuration=pass;storage=pass;postgresql=pass;gemma=pass;nomic=pass'
}

target_start_private_postgresql_runtime() {
  local data_root="$runtime_root/state/postgresql/data"
  local socket_root="$runtime_root/state/postgresql/socket"
  target_stage='v1_3_postgresql_start'
  mkdir -m 0700 -p -- "$socket_root"
  "$target_pg_ctl" -D "$data_root" \
    -o "-k $socket_root -h 127.0.0.1 -p 5432" \
    -l "$runtime_root/state/postgresql/postgresql.log" -w start \
    >"$target_payload_root/pg-runtime-start.stdout" \
    2>"$target_payload_root/pg-runtime-start.stderr" \
    || target_fail v1_3_postgresql_start_failed \
      'The isolated durable v1.3 PostgreSQL cluster did not start on canonical port 5432.' \
      'Allow automatic v1.2 restoration and inspect only the protected v1.3 cluster log.'
  target_private_pg_started=true
  "$target_pg_isready" --quiet --host 127.0.0.1 --port 5432 \
    || target_fail v1_3_postgresql_readiness_failed \
      'The isolated durable v1.3 PostgreSQL cluster did not become ready on port 5432.' \
      'Allow automatic v1.2 restoration and inspect only the v1.3 private cluster.'
  target_emit DATABASE 'state=pass;cluster=isolated_durable;bind=127.0.0.1:5432;v1_2_cluster=stopped'
}

target_stop_v1_2_for_switch() {
  target_stage='v1_2_attended_stop'
  target_emit SWITCH 'state=start;action=stop_v1_2;next=start_v1_3'
  target_v1_2_stopped=true
  target_container_running "$v1_2_container" \
    && "${target_docker[@]}" stop --time 20 "$v1_2_container" >/dev/null \
    || true
  if [[ "$target_waive_v1_2_rollback" == true ]]; then
    systemctl --user stop "$v1_2_unit" >/dev/null 2>&1 \
      || [[ "$(systemctl --user is-active "$v1_2_unit" 2>/dev/null || true)" != active ]] \
      || target_fail v1_2_retrieval_stop_failed \
        'An active v1.2 Retrieval API could not be stopped for attended switchover.' \
        'Inspect the active user unit before retrying the rollback-waived launch.'
    sudo systemctl stop postgresql@16-main.service >/dev/null 2>&1 \
      || [[ "$(systemctl is-active postgresql@16-main.service 2>/dev/null || true)" != active ]] \
      || target_fail v1_2_postgresql_stop_failed \
        'An active host PostgreSQL cluster could not be stopped for the isolated-cluster switchover.' \
        'Inspect the active PostgreSQL unit before retrying the rollback-waived launch.'
  else
    systemctl --user stop "$v1_2_unit" >/dev/null \
      || target_fail v1_2_retrieval_stop_failed \
        'The accepted v1.2 Retrieval API did not stop for attended switchover.' \
        'Keep v1.2 in service and inspect the user unit before retrying.'
    sudo systemctl stop postgresql@16-main.service >/dev/null \
      || target_fail v1_2_postgresql_stop_failed \
        'The accepted v1.2 PostgreSQL cluster did not stop for the isolated-cluster switchover.' \
        'Allow automatic restoration and inspect the host PostgreSQL unit.'
  fi
  if [[ "$(systemctl --user is-active "$v1_2_unit" 2>/dev/null || true)" == active ]] \
      || target_container_running "$v1_2_container"; then
    target_fail v1_2_stop_unconfirmed \
      'One accepted v1.2 application component remained active.' \
      'Allow automatic restoration, inspect the component, and retry only after v1.2 is ready.'
  fi
  [[ "$(systemctl is-active postgresql@16-main.service 2>/dev/null || true)" != active ]] \
    || target_fail v1_2_postgresql_stop_unconfirmed \
      'The accepted v1.2 PostgreSQL unit remained active at switchover.' \
      'Allow automatic restoration and inspect the host PostgreSQL unit.'
  local -a required_free_ports=(5432 "$ui_port" "$retrieval_port")
  if [[ "$target_waive_v1_2_rollback" == false ]]; then
    required_free_ports=(3000 1384 "${required_free_ports[@]}")
  fi
  for port in "${required_free_ports[@]}"; do
    ! target_port_listening "$port" \
      || target_fail switchover_port_not_free \
        "Port ${port} remained occupied at the launch boundary." \
        'Allow automatic v1.2 restoration and identify the exact listener owner.'
  done
  target_emit SWITCH "state=pass;v1_2_stopped=true;v1_2_postgresql_stopped=true;accepted_database_files_untouched=true;launch_boundary=immediate;v1_2_rollback_guarantee=$(target_v1_2_rollback_posture)"
}

target_launch_v1_3() {
  local pid_file="$runtime_root/state/run/attended-v1.3.pid"
  target_stage='v1_3_attended_launch'
  rm -f -- "$pid_file"
  export ISHIKAWA_GEMMA_API_KEY="$target_gemma_key"
  export ISHIKAWA_NOMIC_API_KEY="$target_nomic_key"
  export ISHIKAWA_POSTGRESQL_PASSWORD="$target_v1_3_retrieval_password"
  setsid bash -c '
    set -Eeuo pipefail
    umask 077
    printf "%s\n" "$$" >"$1"
    shift
    exec "$@"
  ' bash "$pid_file" env PYTHONDONTWRITEBYTECODE=1 \
    "$runtime_root/scripts/ishikawa-retrieval-api" --serve \
    </dev/null >>"$runtime_root/state/logs/attended-retrieval.stdout" \
    2>>"$runtime_root/state/logs/attended-retrieval.stderr" &
  target_api_pid="$!"
  unset ISHIKAWA_GEMMA_API_KEY ISHIKAWA_NOMIC_API_KEY ISHIKAWA_POSTGRESQL_PASSWORD
  for _attempt in {1..40}; do
    [[ -s "$pid_file" ]] && break
    kill -0 "$target_api_pid" 2>/dev/null || break
    sleep 0.25
  done
  [[ -s "$pid_file" ]] \
    || target_fail v1_3_api_pid_missing \
      'The package-local v1.3 Retrieval API did not publish its PID.' \
      'Allow automatic v1.2 restoration and inspect the protected v1.3 log.'
  IFS= read -r target_api_pid <"$pid_file"
  [[ "$target_api_pid" =~ ^[0-9]+$ && -d "/proc/$target_api_pid" ]] \
    || target_fail v1_3_api_process_missing \
      'The package-local v1.3 Retrieval API exited during startup.' \
      'Allow automatic v1.2 restoration and inspect the protected v1.3 log.'
  target_wait_http 'http://127.0.0.1:8384/ready' 180 API \
    || target_fail v1_3_api_not_ready \
      "The package-local v1.3 Retrieval API did not become ready on port 8384;root_cause=$(target_safe_root_cause "$runtime_root/state/logs/attended-retrieval.stdout" "$runtime_root/state/logs/attended-retrieval.stderr")." \
      'Allow automatic v1.2 restoration and inspect its content-free readiness marker.'
  target_emit API 'state=pass;bind=127.0.0.1:8384;execution=package_local;autostart=false'
  target_start_web "$runtime_root" "$v1_3_container" true true \
    || target_fail v1_3_web_start_failed \
      'The distinct attended v1.3 web container failed to start.' \
      'Allow automatic v1.2 restoration and inspect bounded container state.'
  if ! target_wait_web 200; then
    target_capture_web_diagnostic "$v1_3_container"
    target_fail v1_3_web_not_ready \
      "The attended v1.3 UI did not become ready on port 3384;root_cause=${target_web_root_cause};container_running=${target_web_container_state};container_exit_code=${target_web_exit_code};container_oom_killed=${target_web_oom_killed};web_live_http=${target_web_live_status};web_ready_http=${target_web_ready_status};api_ready_http=${target_web_api_status};protected_log_sha256=${target_web_log_sha256};protected_log_bytes=${target_web_log_bytes}." \
      'Allow automatic v1.2 restoration and inspect the protected attended web log only if the content-safe detail is insufficient.'
  fi
  [[ "$(systemctl --user is-enabled "$v1_2_unit" 2>/dev/null || true)" != enabled \
      && "$(systemctl is-enabled postgresql.service 2>/dev/null || true)" != enabled \
      && "$(systemctl is-enabled postgresql@16-main.service 2>/dev/null || true)" != enabled ]] \
    || target_fail boot_posture_changed \
      'Boot autostart changed during attended launch.' \
      'Allow automatic v1.2 restoration and restore the boot-disabled posture.'
  ! systemctl --user cat 'ishikawa-v1.3-retrieval-api.service' >/dev/null 2>&1 \
    || target_fail persistent_v1_3_unit_appeared \
      'A persistent v1.3 user unit appeared during the attended launch.' \
      'Allow automatic v1.2 restoration and reconcile the unapproved unit.'
  target_emit WEB 'state=pass;ui=http://127.0.0.1:3384;retrieval_proxy=ready;container=ishikawa-v1.3-web'
}

target_launch_main() {
  local image_id web_runtime_version
  target_stage='preflight'
  for command_name in awk bash chmod cp curl date df docker dpkg find grep hostname id kill mkdir mktemp mv pg_isready psql python3 readlink rm sed setsid sha256sum sleep ss sudo systemctl tar timeout tr wc; do
    command -v "$command_name" >/dev/null 2>&1 \
      || target_fail "command_missing_${command_name}" "Required target command is unavailable: ${command_name}." \
        'Restore the accepted EmceeDanko prerequisite before Script 06.'
  done
  target_verify_identity_and_payload
  sudo -v >/dev/null \
    || target_fail privilege_authorization_failed 'Attended sudo authorization failed.' \
      'Correct sudo access before Script 06.'
  target_prepare_docker
  target_verify_postgresql_toolchain
  target_verify_candidate
  target_check_capacity
  target_check_boot_and_ports
  image_id="$("${target_docker[@]}" image inspect 'node-24-slim-nextjs-16-4-1:amd64' --format '{{.Id}}' 2>/dev/null || true)"
  [[ "$image_id" == "$expected_web_image_id" \
      && "$("${target_docker[@]}" image inspect 'node-24-slim-nextjs-16-4-1:amd64' --format '{{.Architecture}}' 2>/dev/null || true)" == amd64 ]] \
    || target_fail web_image_identity_mismatch \
      "Expected ${expected_web_image_id}; observed ${image_id:-missing}." \
      'Restore the exact accepted AMD64 Node 24/Next.js 16.4.1 image.'
  web_runtime_version="$("${target_docker[@]}" run --rm --network none \
    'node-24-slim-nextjs-16-4-1:amd64' next --version 2>/dev/null || true)"
  [[ "$web_runtime_version" =~ ^Next\.js[[:space:]]v?16\.4\.1$ ]] \
    || target_fail web_runtime_command_invalid \
      "The exact image did not expose the required direct Next.js 16.4.1 command; observed ${web_runtime_version:-missing}." \
      'Restore the accepted image before entering credentials or changing target state.'
  target_emit IMAGE 'state=pass;image=node-24-slim-nextjs-16-4-1:amd64;identity=exact;next_command=direct;next_version=16.4.1'
  target_read_secret 'Gemma API key' target_gemma_key 1 4096
  target_read_secret 'Nomic API key' target_nomic_key 32 1024
  if [[ "$target_waive_v1_2_rollback" == false ]]; then
    target_read_secret 'v1.2 PostgreSQL retrieval password (rollback only)' target_v1_2_database_password 1 4096
  fi
  target_read_secret 'v1.3 PostgreSQL ingestion password' target_v1_3_ingest_password 16 4096
  target_read_secret 'v1.3 PostgreSQL retrieval password' target_v1_3_retrieval_password 16 4096
  target_probe_models
  if [[ "$target_waive_v1_2_rollback" == true ]]; then
    target_emit READINESS 'state=pass;v1_2_rollback=waived;v1_2_password_read=false;v1_2_readiness_contact=false'
  else
    target_validate_v1_2_restore_credentials
  fi
  target_database_state
  case "$target_database_action" in
    fresh) target_create_database_and_runtime ;;
    reuse) target_reuse_database_and_runtime ;;
    *) target_fail database_state_invalid 'The v1.3 database state classifier returned an invalid value.' \
        'Review Script 06 before target mutation.' ;;
  esac
  target_stop_v1_2_for_switch
  target_start_private_postgresql_runtime
  target_prelaunch_readiness
  target_launch_v1_3
  target_stage='complete'
  target_complete=true
  target_emit SUMMARY "state=pass;v1_3=ready;v1_2=stopped;database=isolated_durable;boot_autostart=false;v1_2_rollback_guarantee=$(target_v1_2_rollback_posture);next_gate=human_ui_accept_or_rollback"
}

target_accept_main() {
  local acceptance_root acceptance_file timestamp pid
  target_stage='acceptance_preflight'
  for command_name in chmod curl date docker dpkg find grep hostname kill ln mkdir mktemp python3 readlink rm sha256sum ss sudo systemctl; do
    command -v "$command_name" >/dev/null 2>&1 \
      || target_fail "command_missing_${command_name}" "Required target command is unavailable: ${command_name}." \
        'Restore the accepted target prerequisite.'
  done
  target_verify_identity_and_payload
  target_prepare_docker
  target_require_pg_binary pg_ctl target_pg_ctl
  [[ -d "$runtime_root" && ! -L "$runtime_root" \
      && -z "$(find "$runtime_root" -type l -print -quit 2>/dev/null)" \
      && -f "$runtime_root/state/run/attended-v1.3.pid" \
      && ! -L "$runtime_root/state/run/attended-v1.3.pid" ]] \
    || target_fail attended_runtime_missing 'The attended v1.3 runtime is not present.' \
      'Run Script 06 --run before recording human acceptance.'
  IFS= read -r pid <"$runtime_root/state/run/attended-v1.3.pid" || pid=''
  [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null \
    && target_pid_is_attended_api "$pid" \
    || target_fail attended_api_not_running 'The attended v1.3 API process is not running.' \
      'Run Script 06 --rollback or relaunch before acceptance.'
  target_container_running "$v1_3_container" \
    || target_fail attended_web_not_running 'The attended v1.3 web container is not running.' \
      'Run Script 06 --rollback or relaunch before acceptance.'
  target_http_ready 'http://127.0.0.1:8384/ready' \
    && target_http_ready 'http://127.0.0.1:3384/api/ready' \
    || target_fail attended_runtime_not_ready 'The attended v1.3 API or UI is not ready.' \
      'Do not accept; run Script 06 --rollback or correct and relaunch.'
  "$target_pg_ctl" -D "$runtime_root/state/postgresql/data" status >/dev/null 2>&1 \
    || target_fail attended_postgresql_not_running \
      'The isolated durable v1.3 PostgreSQL cluster is not running.' \
      'Do not accept; run Script 06 --rollback or correct and relaunch.'
  [[ "$(systemctl --user is-active "$v1_2_unit" 2>/dev/null || true)" != active \
      && "$(systemctl is-active postgresql@16-main.service 2>/dev/null || true)" != active \
      && "$(systemctl --user is-enabled "$v1_2_unit" 2>/dev/null || true)" != enabled ]] \
    || target_fail acceptance_runtime_boundary_invalid \
      'v1.2 is active or its boot posture changed during v1.3 acceptance.' \
      'Do not record acceptance; reconcile the application boundary.'
  acceptance_root="$runtime_root/state/reports/acceptance"
  mkdir -m 0700 -p -- "$acceptance_root"
  acceptance_file="$acceptance_root/emceedanko-v1.3-human-ui.txt"
  [[ ! -e "$acceptance_file" && ! -L "$acceptance_file" ]] \
    || target_fail acceptance_already_recorded \
      'A human UI acceptance receipt already exists.' \
      'Review the existing receipt instead of replacing it.'
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  target_acceptance_stage="$(mktemp "$acceptance_root/.emceedanko-v1.3-human-ui.XXXXXX")"
  {
    printf 'accepted_at_utc=%s\n' "$timestamp"
    printf 'application=Ishikawa_v1.3\n'
    printf 'application_archive_sha256=%s\n' "$expected_application_sha256"
    printf 'script_05_report_sha256=%s\n' "$expected_script05_report_sha256"
    printf 'human_ui_acceptance=accepted\n'
    printf 'ui_port=3384;retrieval_api_port=8384;boot_autostart=false\n'
    printf 'v1_2_preserved=true;v1_2_database_mutated=false\n'
  } >"$target_acceptance_stage"
  chmod 0600 "$target_acceptance_stage"
  ln -- "$target_acceptance_stage" "$acceptance_file" \
    || target_fail acceptance_publication_race \
      'The human UI acceptance destination appeared during atomic publication.' \
      'Review the preserved acceptance path instead of replacing it.'
  rm -- "$target_acceptance_stage" \
    || target_fail acceptance_stage_cleanup_failed \
      'The accepted receipt was published but its private staging link remained.' \
      'Preserve the accepted receipt and remove only the reported private staging link.'
  target_acceptance_stage=''
  target_stage='complete'
  target_complete=true
  target_emit SUMMARY 'state=pass;human_ui_acceptance=accepted;org_lab_packaging=separate_next_action'
}

target_rollback_main() {
  target_stage='rollback_preflight'
  for command_name in bash curl docker dpkg env find grep hostname kill pg_isready python3 readlink rm sha256sum sleep ss sudo systemctl tr; do
    command -v "$command_name" >/dev/null 2>&1 \
      || target_fail "command_missing_${command_name}" "Required target command is unavailable: ${command_name}." \
        'Restore the accepted target prerequisite.'
  done
  target_verify_identity_and_payload
  target_prepare_docker
  target_require_pg_binary pg_ctl target_pg_ctl
  target_require_pg_binary pg_isready target_pg_isready
  if [[ "$(systemctl --user is-active "$v1_2_unit" 2>/dev/null || true)" == active ]] \
      && [[ "$(systemctl is-active postgresql@16-main.service 2>/dev/null || true)" == active ]] \
      && target_container_running "$v1_2_container" \
      && target_http_ready 'http://127.0.0.1:1384/ready' \
      && target_http_ready 'http://127.0.0.1:3000/api/ready'; then
    target_v1_2_restored=true
    target_stop_v1_3
    target_stage='complete'
    target_complete=true
    target_emit SUMMARY 'state=pass;rollback_action=reused_ready_v1_2;durable_v1_3_database=preserved'
    return 0
  fi
  target_read_secret 'Gemma API key' target_gemma_key 1 4096
  target_read_secret 'Nomic API key' target_nomic_key 32 1024
  target_read_secret 'v1.2 PostgreSQL retrieval password' target_v1_2_database_password 1 4096
  target_stage='rollback_execution'
  target_stop_v1_3
  target_v1_2_stopped=true
  target_restore_v1_2 \
    || target_fail v1_2_restoration_failed \
      'The explicit rollback could not restore the accepted v1.2 API and UI.' \
      'Keep the session attended and inspect ports 3000/1384 plus the v1.2 user unit.'
  target_stage='complete'
  target_complete=true
  target_emit SUMMARY 'state=pass;rollback_action=restored_v1_2;durable_v1_3_database=preserved'
}

if [[ "$target_internal" == true ]]; then
  trap 'target_unexpected_error "$?" "$LINENO"' ERR
  trap target_exit EXIT
  trap 'target_stage=interrupted; target_fail signal_hangup "Target action received SIGHUP." "Review cleanup/restoration and rerun Script 06." 129' HUP
  trap 'target_stage=interrupted; target_fail signal_interrupt "Target action was interrupted." "Review cleanup/restoration and rerun Script 06." 130' INT
  trap 'target_stage=interrupted; target_fail signal_termination "Target action received SIGTERM." "Review cleanup/restoration and rerun Script 06." 143' TERM
  target_parse_arguments "$@"
  case "$mode" in
    --target-launch) target_launch_main ;;
    --target-accept) target_accept_main ;;
    --target-rollback) target_rollback_main ;;
  esac
  exit 0
fi

target="${APPLICATION_HOST_TARGET:-DankoSurface_EmceeDanko}"
expected_hostname="${APPLICATION_HOST_EXPECTED_HOSTNAME:-EmceeDanko}"
expected_os_version="${APPLICATION_HOST_EXPECTED_OS_VERSION:-24.04}"
identity_file="${APPLICATION_HOST_IDENTITY_FILE:-}"
gemma_base_url="${ISHIKAWA_GEMMA_BASE_URL:-http://127.0.0.1:8000}"
nomic_base_url="${ISHIKAWA_NOMIC_BASE_URL:-http://127.0.0.1:8001}"
waive_v1_2_rollback=false
report_root="${ISHIKAWA_SCRIPT06_REPORT_ROOT:-$default_report_root}"
script05_report_override="${ISHIKAWA_SCRIPT06_SCRIPT05_REPORT:-}"
stage='argument_validation'
report_path=''
work_root=''
remote_root=''
remote_created=false
master_started=false
remote_pid=''
result_emitted=false
ssh_args=()

usage() {
  sed -n '3,35p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --target SSH_ALIAS              Override the configured SSH destination.' \
    '  --identity-file ABSOLUTE_PATH   Use one explicit SSH identity.' \
    '  --report-root ABSOLUTE_PATH     Override the ignored local report lane.' \
    '  --script-05-report ABSOLUTE_PATH Bind one exact retained Script 05 report.' \
    '  --gemma-base-url LOOPBACK_URL   Override the target Gemma forward.' \
    '  --nomic-base-url LOOPBACK_URL   Override the target Nomic forward.' \
    '  --waive-v1-2-rollback           With --run only, skip the v1.2 readiness and automatic-restoration guarantee.'
}

result() {
  local value="$1"
  [[ "$result_emitted" == false ]] || return 0
  result_emitted=true
  printf '\nSCRIPT RESULT\nscript_06_attended_v1_3_on_emceedanko=%s\n' "$value"
}

block() {
  local reason="$1" detail="$2" action="$3" status="${4:-1}" payload
  trap - ERR
  payload="$(printf '%s\n' 'FAILURE DETAIL' "stage=$stage" "reason=$reason" \
    "detail=$detail" "operator_action=$action")"
  printf '%s\n' "$payload" >&2
  if [[ -n "$report_path" && -f "$report_path" && ! -L "$report_path" ]]; then
    printf '%s\n' "$payload" >>"$report_path"
    result blocked | tee -a "$report_path" >&2
  else
    result blocked >&2
  fi
  exit "$status"
}

unexpected_error() {
  local status="$1" line="$2"
  trap - ERR
  block unexpected_command_failure \
    "An unhandled command failed at Script 06 line ${line} with exit code ${status}." \
    'Review the complete retained report and correct the named stage before rerunning Script 06.' \
    "$status"
}

cleanup() {
  local status="$?"
  trap - ERR EXIT HUP INT TERM
  set +e
  if [[ -n "$remote_pid" ]] && kill -0 "$remote_pid" 2>/dev/null; then
    kill -TERM -- "-$remote_pid" 2>/dev/null || kill -TERM "$remote_pid" 2>/dev/null || true
    wait "$remote_pid" 2>/dev/null || true
  fi
  if [[ "$remote_created" == true && "$master_started" == true ]]; then
    timeout --foreground 120 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
      "rm -rf -- '$remote_root' && test ! -e '$remote_root'" >/dev/null 2>&1 || true
  fi
  if [[ "$master_started" == true ]]; then
    timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1 || true
  fi
  [[ -z "$work_root" || "$work_root" != /tmp/ishikawa-script-06.* || ! -d "$work_root" ]] \
    || rm -rf -- "$work_root"
  exit "$status"
}

trap cleanup EXIT
trap 'stage=interrupted; block signal_hangup "Script 06 received SIGHUP." "Review cleanup and rerun the selected Script 06 action." 129' HUP
trap 'stage=interrupted; block signal_interrupt "Script 06 was interrupted." "Review cleanup and rerun the selected Script 06 action." 130' INT
trap 'stage=interrupted; block signal_termination "Script 06 received SIGTERM." "Review cleanup and rerun the selected Script 06 action." 143' TERM
trap 'unexpected_error "$?" "$LINENO"' ERR

if [[ "$mode" == --help || "$mode" == -h ]]; then usage; exit 0; fi
while (( $# > 0 )); do
  case "$1" in
    --target) [[ $# -ge 2 ]] || block target_missing 'The target value is missing.' 'Supply one SSH alias.' 2; target="$2"; shift 2 ;;
    --expected-hostname) [[ $# -ge 2 ]] || block hostname_missing 'The hostname value is missing.' 'Supply the expected short hostname.' 2; expected_hostname="$2"; shift 2 ;;
    --expected-os-version) [[ $# -ge 2 ]] || block os_version_missing 'The OS version value is missing.' 'Supply NN.NN.' 2; expected_os_version="$2"; shift 2 ;;
    --identity-file) [[ $# -ge 2 ]] || block identity_missing 'The identity path is missing.' 'Supply an absolute identity path.' 2; identity_file="$2"; shift 2 ;;
    --report-root) [[ $# -ge 2 ]] || block report_root_missing 'The report root is missing.' 'Supply an absolute report directory.' 2; report_root="$2"; shift 2 ;;
    --script-05-report) [[ $# -ge 2 ]] || block script05_report_missing 'The Script 05 report path is missing.' 'Supply the exact retained report.' 2; script05_report_override="$2"; shift 2 ;;
    --gemma-base-url) [[ $# -ge 2 ]] || block gemma_url_missing 'The Gemma URL is missing.' 'Supply a bounded loopback URL.' 2; gemma_base_url="$2"; shift 2 ;;
    --nomic-base-url) [[ $# -ge 2 ]] || block nomic_url_missing 'The Nomic URL is missing.' 'Supply a bounded loopback URL.' 2; nomic_base_url="$2"; shift 2 ;;
    --waive-v1-2-rollback) waive_v1_2_rollback=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) block argument_invalid "Unsupported argument: $1" 'Use --help and rerun.' 2 ;;
  esac
done
[[ "$mode" == --validate-only || "$mode" == --run || "$mode" == --accept || "$mode" == --rollback ]] \
  || block mode_invalid 'Select exactly one public Script 06 mode.' \
    'Use --validate-only, --run, --accept, or --rollback.' 2
[[ "$waive_v1_2_rollback" == false || "$mode" == --run ]] \
  || block rollback_waiver_mode_invalid \
    'The v1.2 rollback waiver is valid only with Script 06 --run.' \
    'Remove the waiver or select --run.' 2
[[ "$target" =~ ^[A-Za-z0-9_@.:-]+$ ]] \
  || block target_invalid 'The SSH target is not bounded.' 'Use a configured alias or USER@HOST.' 2
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ \
    && "$expected_os_version" =~ ^[0-9]{2}\.[0-9]{2}$ ]] \
  || block target_expectation_invalid 'The expected target identity is invalid.' \
    'Correct the expected hostname and OS version.' 2
[[ "$report_root" == /* && ! -L "$report_root" ]] \
  || block report_root_unsafe 'The report root must be an absolute non-symlink path.' \
    'Correct --report-root.' 2
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] \
    || block identity_unsafe 'The SSH identity is missing or unsafe.' \
      'Correct the identity path or use SSH configuration.' 2
fi
if [[ -n "$script05_report_override" ]]; then
  [[ "$script05_report_override" == /* && -f "$script05_report_override" \
      && ! -L "$script05_report_override" && -r "$script05_report_override" ]] \
    || block script05_report_unsafe 'The explicit Script 05 report is missing or unsafe.' \
      'Supply the exact retained passing report.' 2
fi
validate_loopback_url "$gemma_base_url" \
  || block gemma_url_invalid 'Gemma must use a bounded IPv4 loopback HTTP base URL.' \
    'Correct --gemma-base-url.' 2
validate_loopback_url "$nomic_base_url" \
  || block nomic_url_invalid 'Nomic must use a bounded IPv4 loopback HTTP base URL.' \
    'Correct --nomic-base-url.' 2

stage='local_preflight'
for command_name in awk bash chmod cp date find grep gzip mkdir mktemp mv python3 rm scp sed sha256sum sort ssh tar tee timeout tr wc; do
  command -v "$command_name" >/dev/null 2>&1 \
    || block "command_missing_${command_name}" "Required local command unavailable: ${command_name}." \
      'Restore it before Script 06.'
done
for path in "$application_archive" "$application_sidecar" "$generator_source" \
  "$qualification_artifact/SHA256SUMS" "$qualification_artifact/receipt.json" \
  "$qualification_artifact/target-result.txt" "$qualification_artifact/frontier-result.json"; do
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] \
    || block local_input_unsafe "Required Script 06 input is missing or unsafe: ${path}." \
      'Restore the exact Script 01 and Script 05 handoffs.'
done
(cd -- "$(dirname -- "$application_archive")" \
  && sha256sum --check --strict "$(basename -- "$application_sidecar")" >/dev/null) \
  || block application_sidecar_failed 'The Script 01 application sidecar failed.' \
    'Rebuild the exact v1.3 handoff before Script 06.'
[[ "$(sha256sum "$application_archive" | awk '{print $1}')" == "$expected_application_sha256" ]] \
  || block application_identity_mismatch 'The current Script 01 archive is not the exact qualified application.' \
    'Restore archive 53da57...f3c before Script 06.'
(cd -- "$qualification_artifact" && sha256sum --check --strict SHA256SUMS >/dev/null) \
  || block script05_artifact_checksum_failed 'The current Script 05 artifact failed checksum verification.' \
    'Restore the exact accepted Script 05 current artifact.'
[[ "$(sha256sum "$qualification_artifact/receipt.json" | awk '{print $1}')" == "$expected_script05_receipt_sha256" \
    && "$(sha256sum "$qualification_artifact/target-result.txt" | awk '{print $1}')" == "$expected_script05_result_sha256" \
    && "$(sha256sum "$qualification_artifact/frontier-result.json" | awk '{print $1}')" == "$expected_frontier_sha256" ]] \
  || block script05_artifact_identity_mismatch \
    'The Script 05 receipt, target result, or frontier artifact identity changed.' \
    'Restore the exact accepted current artifact before Script 06.'
for fact in \
  'active_v1_2_preserved=true;accepted_database_contact=false;candidate_mutated=false;boot_autostart_changed=false' \
  'cleanup=pass;temporary_postgresql_removed=true;temporary_api_stopped=true;qualification_ports_free=true' \
  'native_qualification=pass;tests=486' \
  'corpus_v3_ingestion=pass;documents=30;pages=150;authoritative_chunks=786;retrieval_candidates=943;retrieval_scoring_only=157;embeddings=943;relationship_records=240;relationship_pairs=90' \
  'frontier_qualification=pass;cases=60/60;required_evidence_returned=60/60;required_evidence_cited=60/60;dependency_failures=0' \
  'ishikawa_v1_3_emceedanko_disposable_qualification=pass'; do
  grep -Fxq "$fact" "$qualification_artifact/target-result.txt" \
    || block script05_result_contract_invalid "Script 05 target result lacks: ${fact}." \
      'Restore or rerun the exact Script 05 qualification before deployment.'
done
script05_report="$script05_report_override"
if [[ -z "$script05_report" ]]; then
  while IFS= read -r candidate_report; do
    if [[ "$(sha256sum "$candidate_report" | awk '{print $1}')" == "$expected_script05_report_sha256" ]]; then
      script05_report="$candidate_report"
      break
    fi
  done < <(find "$script05_report_root" -maxdepth 1 -type f -name 'qualify_v1_3_*.txt' -print | sort)
fi
[[ -n "$script05_report" && "$(sha256sum "$script05_report" | awk '{print $1}')" == "$expected_script05_report_sha256" ]] \
  || block script05_report_identity_mismatch \
    'The exact accepted Script 05 report (854240...8c0) was not found.' \
    'Restore the retained passing report before Script 06.'
for fact in \
  '[NATIVE] state=pass;tests=486' \
  '[DATABASE] state=pass;documents=30;pages=150;authoritative_chunks=786;retrieval_candidates=943;retrieval_scoring_only=157;embeddings=943;relationship_records=240;relationship_pairs=90' \
  '[FRONTIER] state=pass;cases=60/60;artifact_sha256=3cdf7dc4bed4bef9935148f7604d5499342c5ae2b54c9be13594b9ab10caeb49' \
  'script_05_qualify_v1_3_on_emceedanko=pass'; do
  grep -Fq "$fact" "$script05_report" \
    || block script05_report_contract_invalid "The exact Script 05 report lacks: ${fact}." \
      'Treat target deployment as blocked.'
done
bash -n "${BASH_SOURCE[0]}" \
  || block script_syntax_invalid 'Script 06 failed shell parsing.' 'Correct Script 06 before target contact.'
bash "${BASH_SOURCE[0]}" --self-test \
  | grep -Fxq 'attended_v1_3_orchestrator_self_test=pass' \
  || block script_self_test_failed 'Script 06 failed its local self-test.' \
    'Correct Script 06 before target contact.'
PYTHONDONTWRITEBYTECODE=1 python3 -B "$generator_source" --self-test \
  | grep -Fxq 'corpus_v3_ingestion_config_self_test=pass' \
  || block generator_self_test_failed 'The corpus-v3 configuration generator failed its self-test.' \
    'Correct it before target contact.'

work_root="$(mktemp -d /tmp/ishikawa-script-06.XXXXXX)"
mkdir -p -- "$work_root/extracted" "$work_root/payload/database" "$work_root/payload/evidence"
tar -xzf "$application_archive" -C "$work_root/extracted"
release_root="$work_root/extracted/ishikawa-v1.3"
[[ -d "$release_root" && ! -L "$release_root" ]] \
  || block release_layout_invalid 'The exact application archive has an invalid root.' \
    'Restore the Script 01 handoff.'
bash "$release_root/verify-ishikawa-release" \
  | grep -Fxq 'ishikawa_release_verification=pass;release=v1.3;schema=5;native_tests=486;javascript_tests=17;frontier_cases=60;source_documents=0;boot_autostart=false' \
  || block release_verification_failed 'The exact release verifier did not pass.' \
    'Rebuild Script 01 before Script 06.'
awk '$2 ~ /^payload\// {sub(/^payload\//, "", $2); print $1 "  " $2}' \
  "$release_root/application/SHA256SUMS" >"$work_root/payload/candidate-SHA256SUMS"
(cd -- "$release_root/application/payload" \
  && find . -type f -printf '%m %P\n' | sort) >"$work_root/payload/candidate-MODES"
cp -- "${BASH_SOURCE[0]}" "$work_root/payload/attended-v1.3-on-emceedanko"
cp -- "$generator_source" "$work_root/payload/create-corpus-v3-ingestion-config.py"
for file in README.md install-schema schema.sql SHA256SUMS; do
  cp -- "$release_root/database/$file" "$work_root/payload/database/$file"
done
cp -- "$qualification_artifact/SHA256SUMS" "$qualification_artifact/receipt.json" \
  "$qualification_artifact/target-result.txt" "$qualification_artifact/frontier-result.json" \
  "$work_root/payload/evidence/"
(cd -- "$work_root/payload" \
  && find . -type f ! -name SHA256SUMS ! -path './database/SHA256SUMS' \
      ! -path './evidence/SHA256SUMS' -printf '%P\n' | sort \
  | while IFS= read -r file; do sha256sum -- "$file"; done >SHA256SUMS)
(cd -- "$work_root/payload" && sha256sum --check --strict SHA256SUMS >/dev/null \
  && cd database && sha256sum --check --strict SHA256SUMS >/dev/null \
  && cd ../evidence && sha256sum --check --strict SHA256SUMS >/dev/null) \
  || block payload_assembly_failed 'The consolidated Script 06 payload failed checksum verification.' \
    'Correct local assembly before target contact.'
tar --sort=name --format=posix --mtime='UTC 2026-10-25' --owner=0 --group=0 --numeric-owner \
  --pax-option=delete=atime,delete=ctime -C "$work_root" -cf - payload \
  | gzip -n >"$work_root/script-06-payload.tar.gz"
payload_sha256="$(sha256sum "$work_root/script-06-payload.tar.gz" | awk '{print $1}')"

if [[ "$mode" == --validate-only ]]; then
  printf '%s\n' \
    'purpose=validate_emceedanko_attended_v1_3_deployment' \
    "application_archive_sha256=$expected_application_sha256" \
    "script_05_report_sha256=$expected_script05_report_sha256" \
    "script_06_payload_sha256=$payload_sha256" \
    'target_contact=false;database_contact=false;service_changed=false;credential_read=false' \
    'selected_ports=ui:3384,retrieval_api:8384;port_1384_purpose=v1_2_runtime_and_rollback' \
    'service_arrangement=isolated_durable_postgresql_cluster_plus_package_local_api_process_and_distinct_ephemeral_web_container;private_database_validation_port=65438;runtime_postgresql_port=5432;boot_autostart=false'
  result ready
  exit 0
fi

stage='report_setup'
mkdir -p -- "$report_root"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_root/attended_v1_3_${mode#--}_${timestamp}_XXXXXX.txt")"
emit() {
  local message="$1" tag="${2:-READINESS}"
  printf '[%s] %s\n' "$tag" "$message" | tee -a "$report_path"
}
emit "report_path=$report_path;state=start;action=${mode#--}" READINESS
emit "application_archive_sha256=$expected_application_sha256;script_05_report_sha256=$expected_script05_report_sha256;payload_sha256=$payload_sha256" READINESS
if [[ "$mode" == --run ]]; then
  if [[ "$waive_v1_2_rollback" == true ]]; then
    emit 'authorized_actions=authenticate_transfer_verify_create_or_reuse_isolated_durable_v1_3_postgresql_cluster_schema_and_corpus_build_attended_runtime_stop_any_present_v1_2_application_and_host_postgresql_start_v1_3_postgresql_on_5432_start_v1_3_on_3384_8384' READINESS
    emit 'recovery_posture=v1_2_rollback_guarantee_waived;automatic_v1_2_restoration=false;v1_2_files_and_database_preserved=true' READINESS
    emit 'non_actions=no_v1_2_file_or_database_deletion_no_rollback_tree_change_no_canonical_unit_replacement_no_boot_autostart_no_candidate_mutation_no_org_lab_packaging' READINESS
    emit 'expected_duration=fresh_approximately_15_to_30_minutes_reuse_approximately_5_minutes;prompts=ssh_then_attended_sudo_then_four_hidden_v1_3_runtime_credentials;heartbeat_max_seconds=25' READINESS
  else
    emit 'authorized_actions=authenticate_transfer_verify_create_or_reuse_isolated_durable_v1_3_postgresql_cluster_schema_and_corpus_build_attended_runtime_stop_v1_2_application_and_host_postgresql_start_v1_3_postgresql_on_5432_start_v1_3_on_3384_8384_restore_v1_2_on_failed_launch' READINESS
    emit 'non_actions=no_v1_2_file_or_database_change_no_rollback_tree_change_no_canonical_unit_replacement_no_boot_autostart_no_candidate_mutation_no_org_lab_packaging' READINESS
    emit 'expected_duration=fresh_approximately_15_to_30_minutes_reuse_approximately_5_minutes;prompts=ssh_then_attended_sudo_then_five_hidden_credentials;heartbeat_max_seconds=25' READINESS
  fi
elif [[ "$mode" == --accept ]]; then
  emit 'authorized_actions=verify_running_attended_v1_3_and_record_explicit_human_ui_acceptance' READINESS
  emit 'non_actions=no_promotion_no_org_lab_packaging_no_service_restart_no_database_change_no_boot_autostart' READINESS
  emit 'expected_duration=approximately_1_to_2_minutes;prompts=ssh_and_possible_attended_sudo_for_docker_access' READINESS
else
  emit 'authorized_actions=verify_target_stop_attended_v1_3_restore_accepted_v1_2_preserve_isolated_v1_3_database' READINESS
  emit 'non_actions=no_v1_2_database_change_no_v1_3_database_deletion_no_candidate_change_no_boot_autostart' READINESS
  emit 'expected_duration=approximately_2_to_5_minutes;prompts=ssh_then_possible_sudo_then_three_hidden_v1_2_runtime_credentials' READINESS
fi

stage='authentication'
emit 'state=waiting_for_ssh_private_key_passphrase_if_prompted' AUTHENTICATION
control_path="/tmp/is06-${timestamp}-%C"
ssh_args=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 \
  -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto \
  -o "ControlPath=$control_path" -o ControlPersist=300)
[[ -z "$identity_file" ]] || ssh_args+=(-i "$identity_file" -o IdentitiesOnly=yes)
ssh -G "${ssh_args[@]}" "$target" >/dev/null \
  || block ssh_configuration_invalid 'OpenSSH rejected the bounded connection configuration.' \
    'Correct the target or identity and rerun Script 06.'
timeout --foreground 120 ssh "${ssh_args[@]}" -Nf "$target" \
  || block ssh_master_start_failed 'SSH authentication or connection failed.' \
    'Correct SSH access and rerun Script 06.'
master_started=true
timeout --foreground 10 ssh "${ssh_args[@]}" -O check "$target" >/dev/null \
  || block ssh_master_check_failed 'The SSH control master was not ready.' \
    'Correct SSH access and rerun Script 06.'
emit 'state=pass;control_master=ready' AUTHENTICATION

stage='transfer'
remote_root="/tmp/ishikawa-v1.3-attended-${timestamp}-$$"
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" >/dev/null \
  || block remote_directory_failed 'The private target transfer directory could not be created.' \
    'Review target permissions and rerun Script 06.'
remote_created=true
emit 'state=start;payload=consolidated_script_06' TRANSFER
timeout --foreground 180 scp "${ssh_args[@]}" "$work_root/script-06-payload.tar.gz" \
  "$target:$remote_root/" >/dev/null \
  || block transfer_failed 'The checksum-bound Script 06 payload failed to transfer.' \
    'Correct transport and rerun Script 06.'
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && printf '%s  %s\n' '$payload_sha256' 'script-06-payload.tar.gz' | sha256sum --check --strict - >/dev/null && tar -xzf script-06-payload.tar.gz && cd payload && sha256sum --check --strict SHA256SUMS >/dev/null && cd database && sha256sum --check --strict SHA256SUMS >/dev/null && cd ../evidence && sha256sum --check --strict SHA256SUMS >/dev/null" \
  || block transferred_payload_invalid 'Target-side Script 06 payload verification failed.' \
    'Do not mutate target state; correct the transfer.'
emit 'state=pass;target_checksum=pass' TRANSFER

case "$mode" in
  --run) internal_mode='--target-launch'; expected_contract='ishikawa_v1_3_emceedanko_attended_launch=pass'; stage_tag='LAUNCH' ;;
  --accept) internal_mode='--target-accept'; expected_contract='ishikawa_v1_3_emceedanko_human_ui_acceptance=pass'; stage_tag='ACCEPT' ;;
  --rollback) internal_mode='--target-rollback'; expected_contract='ishikawa_v1_3_emceedanko_attended_rollback=pass'; stage_tag='ROLLBACK' ;;
esac
target_waiver_option=''
[[ "$waive_v1_2_rollback" == false ]] || target_waiver_option=' --waive-v1-2-rollback'
stage='target_action'
emit "state=start;action=${mode#--};target_prompts_visible=true" "$stage_tag"
trap - ERR
set +e
ssh -tt "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root/payload' && ISHIKAWA_SCRIPT06_INTERNAL=1 bash ./attended-v1.3-on-emceedanko '$internal_mode' --expected-hostname '$expected_hostname' --expected-os-version '$expected_os_version' --expected-architecture amd64 --payload-root '$remote_root/payload' --result-path '$remote_root/payload/target-result.txt' --gemma-base-url '$gemma_base_url' --nomic-base-url '$nomic_base_url'$target_waiver_option" \
  </dev/tty 2>&1 | tee -a "$report_path"
pipeline_status=("${PIPESTATUS[@]}")
remote_status="${pipeline_status[0]}"
tee_status="${pipeline_status[1]}"
set -e
trap 'unexpected_error "$?" "$LINENO"' ERR
(( tee_status == 0 )) \
  || block report_stream_failed 'The live report stream failed.' \
    'Do not accept the target action; restore the report lane and rerun.'

stage='result_fetch'
timeout --foreground 60 scp "${ssh_args[@]}" \
  "$target:$remote_root/payload/target-result.txt" "$work_root/target-result.txt" >/dev/null \
  || block target_result_fetch_failed 'The content-safe target result could not be fetched.' \
    'Review the streamed target output and target state before rerunning.'
tee -a "$report_path" <"$work_root/target-result.txt" >/dev/null
if (( remote_status != 0 )); then
  target_reason="$(sed -n 's/^reason=\([a-z0-9_]*\)$/\1/p' "$work_root/target-result.txt" | tail -n 1)"
  target_stage="$(sed -n 's/^stage=\([a-z0-9_]*\)$/\1/p' "$work_root/target-result.txt" | tail -n 1)"
  target_detail="$(sed -n 's/^detail=\(.*\)$/\1/p' "$work_root/target-result.txt" | tail -n 1)"
  target_action="$(sed -n 's/^operator_action=\(.*\)$/\1/p' "$work_root/target-result.txt" | tail -n 1)"
  stage="target_${target_stage:-action}"
  block "${target_reason:-remote_action_failed}" \
    "${target_detail:-The target action exited with status ${remote_status}.}" \
    "${target_action:-Review the retained target stage before rerunning Script 06.}" \
    "$remote_status"
fi
grep -Fxq "$expected_contract" "$work_root/target-result.txt" \
  || block target_result_contract_invalid \
    "The target result lacks required fact: ${expected_contract}." \
    'Treat the action as blocked and inspect the retained report.'
for fact in \
  'application_archive_sha256=53da57b745fb4c8be6335896d05bdb6f63f2de3494862b99acca09e156863f3c;script_05_report_sha256=854240b564148f38853b183852ca98ac12d38ef3a57bb6ed513116270d7a98c0' \
  'database=rag_catalog;postgresql_port=5432;postgresql_cluster=isolated_durable;schema_version=5;ui_port=3384;retrieval_api_port=8384;port_1384_purpose=v1_2_runtime_and_rollback' \
  'candidate_mutated=false;v1_2_database_mutated=false;rollback_tree_mutated=false;boot_autostart_changed=false'; do
  grep -Fxq "$fact" "$work_root/target-result.txt" \
    || block target_result_boundary_invalid "The target result lacks safety fact: ${fact}." \
      'Treat the action as blocked and inspect target state.'
done
if [[ "$mode" == --run ]]; then
  if [[ "$waive_v1_2_rollback" == true ]]; then
    grep -Fxq 'v1_2_rollback_guarantee=waived;automatic_v1_2_restoration=false;v1_2_files_and_database_preserved=true' "$work_root/target-result.txt" \
      || block target_result_recovery_posture_invalid \
        'The target result did not attest the selected v1.2 rollback waiver.' \
        'Treat the launch as blocked and inspect target state.'
  else
    grep -Fxq 'v1_2_rollback_guarantee=verified;automatic_v1_2_restoration=true;v1_2_files_and_database_preserved=true' "$work_root/target-result.txt" \
      || block target_result_recovery_posture_invalid \
        'The target result did not attest the default v1.2 rollback guarantee.' \
        'Treat the launch as blocked and inspect target state.'
  fi
fi
emit "state=pass;action=${mode#--};target_result=pass" "$stage_tag"

stage='remote_cleanup'
emit 'state=start' CLEANUP
timeout --foreground 120 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "rm -rf -- '$remote_root' && test ! -e '$remote_root'" >/dev/null \
  || block remote_cleanup_failed 'The temporary Script 06 transfer could not be removed.' \
    'Inspect only the exact reported /tmp transfer path.'
remote_created=false
emit 'state=pass;temporary_transfer_removed=true;payload_bytes_deleted=true' CLEANUP

stage='complete'
if [[ "$mode" == --run ]]; then
  emit 'target_ui_address=http://127.0.0.1:3384' SUMMARY
  emit "ui_forward_command=ssh -N -L 3384:127.0.0.1:3384 $target" SUMMARY
  emit "acceptance_command=bash ./deployment/scripts/06_attended-v1.3-on-emceedanko.sh --accept --target $target" SUMMARY
  if [[ "$waive_v1_2_rollback" == true ]]; then
    emit 'recovery_posture=v1_2_rollback_guarantee_waived;automatic_v1_2_restoration=false;v1_2_files_and_database_preserved=true' SUMMARY
    emit "conditional_rollback_command=bash ./deployment/scripts/06_attended-v1.3-on-emceedanko.sh --rollback --target $target" SUMMARY
    emit 'conditional_rollback_requires=v1_2_postgresql_password_and_model_forwards_on_8000_8001' SUMMARY
  else
    emit "rollback_command=bash ./deployment/scripts/06_attended-v1.3-on-emceedanko.sh --rollback --target $target" SUMMARY
  fi
  emit 'next_gate=attended_human_ui_review;org_lab_packaging=false' SUMMARY
elif [[ "$mode" == --accept ]]; then
  emit 'human_ui_acceptance=accepted;next_gate=review_receipt_before_separate_org_lab_packaging' SUMMARY
else
  emit 'rollback=pass;v1_2=ready;v1_3_database=preserved;next_gate=review_human_ui_findings' SUMMARY
fi
result pass | tee -a "$report_path"
