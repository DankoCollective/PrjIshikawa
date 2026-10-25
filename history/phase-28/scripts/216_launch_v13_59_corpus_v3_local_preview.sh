#!/usr/bin/env bash
# Launch the exact V13-59 / corpus-v3 candidate that passed Script 215 for
# attended local browser review. The corpus is ingested into private disposable
# PostgreSQL; the accepted local database is never contacted or changed.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/216_launch_v13_59_corpus_v3_local_preview.sh --validate-only
#   bash ./phase-28-apisachi-tokuli/scripts/216_launch_v13_59_corpus_v3_local_preview.sh --run
#
# Keep the terminal attached. Press Ctrl+C once after review to stop the UI,
# Retrieval API, and disposable PostgreSQL and to verify final cleanup.

set -Eeuo pipefail
umask 077

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly PACKAGE_ROOT="$PYTHON_ROOT/ishikawa"
readonly WEB_ROOT="$PRODUCT_ROOT/application/web"
readonly CONFIG_ROOT="$PRODUCT_ROOT/config/templates"
readonly SCHEMA="$PRODUCT_ROOT/packaging/database/schema.sql"
readonly SERVICE_ENTRYPOINT="$PRODUCT_ROOT/scripts/ishikawa-retrieval-api"
readonly SCRIPT_201="$SCRIPT_DIR/201_ingest_and_qualify_isolated_synthetic_corpus_v3.sh"
readonly SCRIPT_215="$SCRIPT_DIR/215_qualify_v13_59_exact_document_citation_coverage.sh"
readonly SCRIPT_215_REPORT="$REPO_ROOT/local/reports/ishikawa-v13-59-exact-document-citation-coverage/v13_59_exact_document_citation_coverage_20261024T220322Z_xE29Db.txt"
readonly FRONTIER_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/v1.3-corpus-v3-frontier-gate/isolated_corpus_v3_api_20261024T220324Z_ylSbou.json"
readonly CANDIDATE="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v3/synthetic_corpus_v3_candidate_20261023T043639Z"
readonly NORMALIZED="$CANDIDATE/qualification/normalized.json"
readonly CORPUS_TRUTH="$CANDIDATE/evaluation/corpus_truth.json"
readonly BUNDLE_BUILDER="$SCRIPT_DIR/prepare_synthetic_corpus_v3_ingestion_bundle.py"
readonly CHUNK_BUILDER="$SCRIPT_DIR/create-structural-chunk-candidates.py"
readonly INGESTION_RUNNER="$SCRIPT_DIR/run_isolated_synthetic_v2_ingestion.py"
readonly DATABASE_QUALIFIER="$SCRIPT_DIR/qualify_isolated_synthetic_corpus_v3_database.py"
readonly PIPELINE_EXECUTABLE="$SCRIPT_DIR/ishikawa-produce-artifacts"
readonly PRODUCT_PROFILE="$CONFIG_ROOT/product.yaml"
readonly CHAT_CONTRACT="$WEB_ROOT/lib/chat-contract.mjs"
readonly CHAT_WORKSPACE="$WEB_ROOT/components/chat-workspace.js"
readonly CHAT_CONTRACT_TEST="$WEB_ROOT/tests/chat-contract.test.mjs"
readonly WEB_PACKAGE="$WEB_ROOT/package.json"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v13-59-corpus-v3-local-preview"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v13-59-corpus-v3-local-preview"

readonly SCRIPT_201_SHA256='2a0e54486be26ccb1211be981dfb4e9e9720745e1417f9f3f0e1748df8647dc6'
readonly SCRIPT_215_SHA256='c3baa5894c3abc2b0ae57cfcba32380b91c14c0ccf155d72f6a459a2567cc736'
readonly SCRIPT_215_REPORT_SHA256='1e7a4a4d93d9e7ceebc5e447dd86c12a436389f8a791e3895c93f90fbfbfbfe4'
readonly FRONTIER_ARTIFACT_SHA256='1ccb7d59ed67073213051d28cd6142ab445b616e34a6ef7eecb22b174b52d972'
readonly NORMALIZED_SHA256='1772584ecc02c86cc0bd96946318e608f576fd259676bc9851ab7c54bf766b02'
readonly CORPUS_TRUTH_SHA256='85f753ced3956e609b1fada2419888bae1099a308be3c905310765796c80f573'
readonly CHUNKS_SHA256='49a67ac067d06b6068878be6530ae4971bddb4a1f687545578bd1ef9254d19e4'
readonly SCHEMA_CONTRACT_SHA256='3b55d00880e6e09e401e282b7f62314fb635c6a859c23ad3e87c58aa23237e8b'
readonly PRODUCT_PROFILE_SHA256='b4189e48b1d2a8c91cce9846227e4e46a32f139b35f520fa66014de627f5ec43'
readonly CHAT_CONTRACT_SHA256='43bb2c0624594e91cc2aaf97f3b3f2d661037eea51c03c29b9128696fc629fd3'
readonly CHAT_WORKSPACE_SHA256='35b2b83bef4b72b227576afe772e8718e2e28283e070feb512fce4aadb66eb52'
readonly CHAT_CONTRACT_TEST_SHA256='469a86c51f065982c1285b81dd6a15918094576d2c9ec879905651a5962becac'
readonly WEB_PACKAGE_SHA256='cc53fbb830c2199923f68c98f31fae3659c10a6a64b55dfdf810b5c38a3bb505'

readonly INITDB='/usr/lib/postgresql/16/bin/initdb'
readonly PG_CTL='/usr/lib/postgresql/16/bin/pg_ctl'
readonly CREATEDB='/usr/lib/postgresql/16/bin/createdb'
readonly PSQL='/usr/lib/postgresql/16/bin/psql'
readonly POSTGRESQL_PORT=65438
readonly API_PORT=1384
readonly WEB_PORT=3000
readonly RETRIEVAL_BASE_URL="http://127.0.0.1:${API_PORT}"
readonly WEB_BASE_URL="http://127.0.0.1:${WEB_PORT}"
readonly GEMMA_BASE_URL='http://127.0.0.1:18000'
readonly NOMIC_BASE_URL='http://127.0.0.1:18001'
readonly WEB_CONTAINER='ishikawa-v1-3-v13-59-corpus-v3-preview'
readonly LAUNCH_LOCK='/tmp/ishikawa-script-216-v13-59.lock'

mode="${1:-}"
if [[ "$#" -ne 1 || ( "$mode" != '--validate-only' && "$mode" != '--run' ) ]]; then
  printf '%s\n' \
    'FAILURE DETAIL' \
    'stage=argument_validation' \
    'reason=exactly_one_mode_required' \
    'detail=Script 216 requires exactly one mode: --validate-only or --run.' \
    'operator_action=Rerun Script 216 with exactly one supported mode.' \
    '' 'SCRIPT RESULT' \
    'script_216_v13_59_corpus_v3_local_preview=blocked' >&2
  exit 2
fi

preflight_block() {
  printf '%s\n' \
    'FAILURE DETAIL' 'stage=preflight' "reason=$1" \
    'detail=A qualified source, corpus-v3 input, local prerequisite, or retained Script 215 proof did not match.' \
    'operator_action=Correct the named preflight reason, then rerun this same Script 216 command.' \
    '' 'SCRIPT RESULT' \
    'script_216_v13_59_corpus_v3_local_preview=blocked' >&2
  exit "${2:-1}"
}

for command_name in awk bash basename curl date env find flock grep hostname id install \
  kill mkdir mktemp python3 rm sed seq sha256sum sleep sort ss tail tee timeout \
  tar tr uname wc; do
  command -v "$command_name" >/dev/null 2>&1 \
    || preflight_block "local_command_missing_${command_name}" 2
done
if [[ "$mode" == '--run' ]]; then
  exec 9>"$LAUNCH_LOCK" || preflight_block preview_launch_lock_unavailable
  if ! flock -n 9; then
    printf '%s\n' \
      'FAILURE DETAIL' \
      'stage=concurrent_launch_guard' \
      'reason=preview_launcher_already_running' \
      'detail=Another Script 216 preview owns the singleton launch lock. Do not start a second preview.' \
      'operator_action=Return to the existing preview terminal. Stop it with Ctrl+C and wait for its standalone SCRIPT RESULT before launching again.' \
      '' 'SCRIPT RESULT' \
      'script_216_v13_59_corpus_v3_local_preview=blocked' >&2
    exit 1
  fi
fi
for executable in "$INITDB" "$PG_CTL" "$CREATEDB" "$PSQL"; do
  [[ -f "$executable" && ! -L "$executable" && -x "$executable" ]] \
    || preflight_block postgresql_16_binary_unsafe
done

check_file() {
  local path="$1" expected="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] \
    || preflight_block "${label}_unsafe"
  [[ "$(sha256sum -- "$path" | awk '{print $1}')" == "$expected" ]] \
    || preflight_block "${label}_identity_changed"
}

check_file "$SCRIPT_201" "$SCRIPT_201_SHA256" script_201
check_file "$SCRIPT_215" "$SCRIPT_215_SHA256" script_215
check_file "$SCRIPT_215_REPORT" "$SCRIPT_215_REPORT_SHA256" script_215_report
check_file "$FRONTIER_ARTIFACT" "$FRONTIER_ARTIFACT_SHA256" frontier_artifact
check_file "$NORMALIZED" "$NORMALIZED_SHA256" normalized_corpus_v3
check_file "$CORPUS_TRUTH" "$CORPUS_TRUTH_SHA256" corpus_v3_truth
check_file "$PRODUCT_PROFILE" "$PRODUCT_PROFILE_SHA256" product_profile
check_file "$CHAT_CONTRACT" "$CHAT_CONTRACT_SHA256" chat_contract
check_file "$CHAT_WORKSPACE" "$CHAT_WORKSPACE_SHA256" chat_workspace
check_file "$CHAT_CONTRACT_TEST" "$CHAT_CONTRACT_TEST_SHA256" chat_contract_test
check_file "$WEB_PACKAGE" "$WEB_PACKAGE_SHA256" web_package
[[ -d "$CANDIDATE" && ! -L "$CANDIDATE" ]] \
  || preflight_block corpus_v3_candidate_unsafe
(cd -- "$CANDIDATE" && sha256sum --quiet -c SHA256SUMS) \
  || preflight_block corpus_v3_candidate_checksum_failed

for marker in \
  'milestone=complete_api_gate;state=pass;complete_api_cases=60;expected_status_matches=60/60;required_evidence_returned=60/60;required_evidence_cited=60/60;dependency_failures=0;artifact_sha256=1ccb7d59ed67073213051d28cd6142ab445b616e34a6ef7eecb22b174b52d972' \
  'milestone=cleanup;state=pass;temporary_postgresql_removed=true;retrieval_api_stopped=true;generation_capture_proxy_stopped=true;ports_free=true' \
  'qualification=pass;corpus_v3_database=pass;catalog_routing=9/9;multiturn_resolution=pass;frontier_60=pass;self_validation=pass' \
  'qualification=pass;v13_59_exact_document_citation_coverage=pass;catalog_routing=9/9;multiturn_resolution=pass;frontier_60=pass' \
  'next_gate=local_human_ui_validation' \
  'script_215_v13_59_exact_document_citation_coverage=pass'; do
  grep -Fxq "$marker" "$SCRIPT_215_REPORT" \
    || preflight_block script_215_acceptance_incomplete
done
grep -Eq '^milestone=multiturn_resolution_canary;state=pass;multiturn_resolution=pass;status=answered;sources=[1-9][0-9]*;applicability_document=99_TST_2043;applicability_page=1;form_document=TST_9030;form_page=1;both_cited=true;request_id=[0-9a-f]{64}$' \
  "$SCRIPT_215_REPORT" \
  || preflight_block script_215_multiturn_acceptance_incomplete

PYTHONDONTWRITEBYTECODE=1 python3 -B - "$FRONTIER_ARTIFACT" <<'PY' \
  || preflight_block frontier_artifact_contract_invalid
import json
import pathlib
import sys

artifact = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
summary = artifact["summary"]
assert summary["acceptance_gate"] == "pass"
assert summary["case_count"] == 60
assert summary["expected_status_match_count"] == 60
assert summary["required_evidence_returned_count"] == 60
assert summary["required_evidence_cited_count"] == 60
assert summary["dependency_failure_count"] == 0
assert len(artifact["cases"]) == 60
assert all(item["response"]["schema"] == "ishikawa.chat-response.v5" for item in artifact["cases"])
PY

validation_output="$({ bash "$SCRIPT_215" --validate-only; } 2>&1)" \
  || {
    printf '%s\n' "$validation_output" >&2
    preflight_block current_v13_59_validation_failed
  }
for marker in \
  'catalog_canaries=9;multiturn_canary=1;frontier_questions=60' \
  'native_regression=486/486;database_contact=false;model_contact=false;credential_read=false;remote_contact=false' \
  'script_215_v13_59_exact_document_citation_coverage=ready'; do
  grep -Fxq "$marker" <<<"$validation_output" \
    || preflight_block current_v13_59_identity_mismatch
done

readonly -a REQUIRED_PATHS=(
  "$SCHEMA" "$SERVICE_ENTRYPOINT" "$BUNDLE_BUILDER" "$CHUNK_BUILDER"
  "$INGESTION_RUNNER" "$DATABASE_QUALIFIER" "$PIPELINE_EXECUTABLE"
  "$CONFIG_ROOT/deployment.yaml" "$CONFIG_ROOT/runtime_dependencies.yaml"
  "$CONFIG_ROOT/ingestion_dependencies.yaml" "$CONFIG_ROOT/relationship_types.yaml"
  "$CONFIG_ROOT/document_classes.yaml" "$CONFIG_ROOT/product.yaml"
  "$WEB_ROOT/app" "$WEB_ROOT/components" "$WEB_ROOT/lib" "$WEB_ROOT/public"
  "$WEB_ROOT/package.json" "$WEB_ROOT/next.config.mjs"
)
for required_path in "${REQUIRED_PATHS[@]}"; do
  [[ -e "$required_path" && ! -L "$required_path" && -r "$required_path" ]] \
    || preflight_block runtime_input_unsafe
done
[[ -x "$SERVICE_ENTRYPOINT" && -x "$PIPELINE_EXECUTABLE" ]] \
  || preflight_block runtime_executable_invalid

product_values="$({
  PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B - \
    "$CONFIG_ROOT/product.yaml" <<'PY'
import sys
from pathlib import Path
from ishikawa.product import validate_product_profile
from ishikawa.yaml_loader import load_restricted_yaml

profile = validate_product_profile(
    load_restricted_yaml(Path(sys.argv[1]), label="product profile")
)
print(profile.display_name)
print(profile.browser_configuration_base64())
PY
} 2>/dev/null)" || preflight_block product_profile_invalid
product_name="$(sed -n '1p' <<<"$product_values")"
product_ui_config_base64="$(sed -n '2p' <<<"$product_values")"
[[ -n "$product_name" && "$product_ui_config_base64" =~ ^[A-Za-z0-9_-]+=*$ ]] \
  || preflight_block product_payload_invalid

bash -n "${BASH_SOURCE[0]}" "$SCRIPT_201" "$SCRIPT_215" "$SERVICE_ENTRYPOINT" \
  || preflight_block shell_syntax_invalid
script_sha256="$(sha256sum -- "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$mode" == '--validate-only' ]]; then
  printf '%s\n' \
    'purpose=validate_v13_59_corpus_v3_local_human_ui_launcher' \
    "script_sha256=$script_sha256" \
    "script_215_report_sha256=$SCRIPT_215_REPORT_SHA256;frontier_artifact_sha256=$FRONTIER_ARTIFACT_SHA256" \
    'candidate=v13_59_and_corpus_v3;documents=30;pages=150;retrieval_candidates=943;frontier_cases=60/60' \
    'database=private_disposable;accepted_database_contact=false;runtime_flat_file_index=false' \
    'model_contact=false;credential_read=false;container_started=false;service_started=false' \
    '' 'SCRIPT RESULT' \
    'script_216_v13_59_corpus_v3_local_preview=ready'
  exit 0
fi

for command_name in docker dpkg sudo; do
  command -v "$command_name" >/dev/null 2>&1 \
    || preflight_block "local_command_missing_${command_name}" 2
done

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT" \
  || preflight_block local_output_root_creation_failed
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/v13_59_corpus_v3_local_preview_${timestamp}_XXXXXX.txt")" \
  || preflight_block report_creation_failed
work_root="$(mktemp -d /tmp/ishikawa-script-216.XXXXXX)" \
  || preflight_block workspace_creation_failed
diagnostic_bundle="$ARTIFACT_ROOT/v13_59_corpus_v3_local_preview_${timestamp}_diagnostics.tar.gz"
readonly MAIN_BASHPID="$BASHPID"

failure_stage=initialization
failure_reason=''
operator_stop=false
preview_ready=false
postgresql_started=false
service_pid=''
web_client_pid=''
active_pid=''
gemma_key=''
nomic_key=''
database_password='disposable-corpus-v3-preview-password'
docker_command=()

emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
block() {
  failure_reason="$1"
  failure_stage="$2"
  exit "${3:-1}"
}
record_unexpected_error() {
  local status="$1"
  if [[ "$BASHPID" == "$MAIN_BASHPID" && -z "$failure_reason" ]]; then
    failure_reason="${failure_stage}_unexpected_exit_${status}"
  fi
}
request_stop() {
  operator_stop=true
  emit 'milestone=local_preview;state=operator_stop_requested'
  exit 0
}
port_is_free() {
  ! ss -H -ltn "( sport = :$1 )" 2>/dev/null | grep -q .
}
process_is_running() {
  local pid="$1"
  [[ "$pid" =~ ^[0-9]+$ && -r "/proc/$pid/status" ]] || return 1
  ! grep -Eq '^State:[[:space:]]+[ZX]' "/proc/$pid/status"
}
attended_sudo_validate() {
  local purpose="$1"
  [[ -r /dev/tty && -w /dev/tty ]] || return 1
  printf 'Sudo authentication is required to %s. Enter the password at the prompt; input remains hidden.\n' \
    "$purpose" >/dev/tty
  sudo -v -p 'Sudo password for local Ishikawa preview: ' </dev/tty
}
wait_with_heartbeat() {
  local pid="$1" label="$2" output="$3" started next now lines=0 current
  started="$(date +%s)"; next=$(( started + 30 ))
  while kill -0 "$pid" 2>/dev/null; do
    if [[ -f "$output" ]]; then
      current="$(wc -l <"$output" | tr -d ' ')"
      if (( current > lines )); then
        sed -n "$(( lines + 1 )),${current}p" "$output" \
          | grep -E '^(ishikawa_ingestion=|actions=)' \
          | while IFS= read -r line; do emit "[$label] $line"; done || true
        lines="$current"
      fi
    fi
    now="$(date +%s)"
    if (( now >= next )); then
      emit "milestone=$label;state=running;elapsed_seconds=$(( now - started ))"
      next=$(( now + 30 ))
    fi
    sleep 5
  done
  if [[ -f "$output" ]]; then
    current="$(wc -l <"$output" | tr -d ' ')"
    if (( current > lines )); then
      sed -n "$(( lines + 1 )),${current}p" "$output" \
        | grep -E '^(ishikawa_ingestion=|actions=)' \
        | while IFS= read -r line; do emit "[$label] $line"; done || true
    fi
  fi
  if wait "$pid"; then return 0; else return "$?"; fi
}
cleanup() {
  local status="$?" result=blocked cleanup_failed=false ports_free=true diagnostic_sha256=''
  local container_observed=false postgresql_safe_to_remove=true
  local web_stopped=false retrieval_api_stopped=false temporary_postgresql_removed=false
  local -a diagnostic_members=()
  trap - ERR EXIT HUP INT TERM
  set +e
  if [[ "${#docker_command[@]}" -gt 0 ]]; then
    if [[ "${docker_command[0]}" == sudo ]] && ! sudo -n true >/dev/null 2>&1; then
      emit 'milestone=cleanup;state=awaiting_attended_sudo;purpose=stop_local_preview_container'
      attended_sudo_validate 'stop and remove the local preview container' \
        || cleanup_failed=true
    fi
    for _ in $(seq 1 40); do
      if "${docker_command[@]}" container inspect "$WEB_CONTAINER" >/dev/null 2>&1; then
        container_observed=true
        break
      fi
      process_is_running "$web_client_pid" || break
      sleep 0.25
    done
    if [[ "$container_observed" == true ]]; then
      "${docker_command[@]}" stop --time 10 "$WEB_CONTAINER" >/dev/null 2>&1 \
        || cleanup_failed=true
    fi
    if "${docker_command[@]}" container inspect "$WEB_CONTAINER" >/dev/null 2>&1; then
      "${docker_command[@]}" rm --force "$WEB_CONTAINER" >/dev/null 2>&1 \
        || cleanup_failed=true
    fi
  fi
  if [[ "$web_client_pid" =~ ^[0-9]+$ ]]; then
    for _ in $(seq 1 80); do
      process_is_running "$web_client_pid" || break
      sleep 0.25
    done
    if process_is_running "$web_client_pid"; then
      cleanup_failed=true
    else
      wait "$web_client_pid" 2>/dev/null || true
    fi
  fi
  for pid in "$active_pid" "$service_pid"; do
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null || true
      for _ in $(seq 1 40); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.25
      done
      if kill -0 "$pid" 2>/dev/null; then
        kill -KILL "$pid" 2>/dev/null || true
        cleanup_failed=true
      fi
      wait "$pid" 2>/dev/null || true
    fi
  done
  if [[ "$postgresql_started" == true && "$work_root" == /tmp/ishikawa-script-216.* ]]; then
    "$PG_CTL" -D "$work_root/postgresql" -m fast -w stop >/dev/null 2>&1 \
      || {
        cleanup_failed=true
        postgresql_safe_to_remove=false
      }
    if "$PG_CTL" -D "$work_root/postgresql" status >/dev/null 2>&1; then
      cleanup_failed=true
      postgresql_safe_to_remove=false
    fi
  fi
  unset ISHIKAWA_GEMMA_API_KEY ISHIKAWA_NOMIC_API_KEY \
    ISHIKAWA_POSTGRESQL_PASSWORD ISHIKAWA_POSTGRESQL_INGEST_PASSWORD
  gemma_key=''; nomic_key=''; database_password=''
  if (( status != 0 )) && [[ "$work_root" == /tmp/ishikawa-script-216.* && -d "$work_root" ]]; then
    for member in bundle.stdout chunks.stdout initdb.stdout initdb.stderr \
      pg-start.stdout pg-start.stderr postgresql.log roles.stdout roles.stderr \
      createdb.stdout createdb.stderr database-access.stdout database-access.stderr \
      extensions.stdout extensions.stderr schema.stdout schema.stderr \
      ingestion-validate.stdout ingestion-validate.stderr \
      ingestion-publish.stdout ingestion-publish.stderr \
      database-qualifier.stdout database-qualifier.stderr \
      check-config.stdout check-config.stderr service.stdout service.stderr \
      web.stdout web.stderr dependencies.json home.html; do
      [[ -f "$work_root/$member" && ! -L "$work_root/$member" ]] \
        && diagnostic_members+=("$member")
    done
    if (( ${#diagnostic_members[@]} > 0 )) \
      && tar -C "$work_root" -czf "$diagnostic_bundle" -- "${diagnostic_members[@]}"; then
      diagnostic_sha256="$(sha256sum -- "$diagnostic_bundle" | awk '{print $1}')"
      printf '%s  %s\n' "$diagnostic_sha256" "$(basename -- "$diagnostic_bundle")" \
        >"$diagnostic_bundle.sha256"
    fi
  fi
  if [[ "$postgresql_safe_to_remove" == true \
    && "$work_root" == /tmp/ishikawa-script-216.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  if [[ "$postgresql_safe_to_remove" == true ]]; then
    [[ ! -e "$work_root" ]] || cleanup_failed=true
  fi
  if port_is_free "$WEB_PORT"; then web_stopped=true; else ports_free=false; cleanup_failed=true; fi
  if port_is_free "$API_PORT"; then retrieval_api_stopped=true; else ports_free=false; cleanup_failed=true; fi
  if port_is_free "$POSTGRESQL_PORT" \
    && [[ "$postgresql_safe_to_remove" == true && ! -e "$work_root" ]]; then
    temporary_postgresql_removed=true
  else
    ports_free=false
    cleanup_failed=true
  fi
  if [[ "$cleanup_failed" == true ]]; then
    status=1
    [[ -n "$failure_reason" ]] || failure_reason=verified_final_state_incomplete
    failure_stage=cleanup
  fi
  if (( status == 0 )) && [[ "$preview_ready" == true && "$operator_stop" == true ]]; then
    result=pass
  elif (( status == 0 )); then
    status=1
    failure_reason=preview_ended_without_operator_stop
    failure_stage=supervision
  fi
  emit "milestone=cleanup;state=$([[ "$cleanup_failed" == false ]] && printf pass || printf blocked);web_stopped=$web_stopped;retrieval_api_stopped=$retrieval_api_stopped;temporary_postgresql_removed=$temporary_postgresql_removed;ports_free=$ports_free"
  if [[ "$result" == blocked ]]; then
    emit 'FAILURE DETAIL'
    emit "stage=${failure_stage:-unclassified}"
    emit "reason=${failure_reason:-unexpected_exit_${status}}"
    emit 'detail=The named local preview prerequisite, corpus-v3 ingestion, service, UI, supervision, or cleanup gate failed.'
    emit 'operator_action=Use the named stage and reason plus the immediately preceding retained log path; correct all reported conditions and rerun Script 216.'
  fi
  [[ -z "$diagnostic_sha256" ]] \
    || emit "diagnostic_bundle=$diagnostic_bundle;diagnostic_bundle_sha256=$diagnostic_sha256;credentials_retained=false"
  emit "local_report=$report_path"
  printf '\nSCRIPT RESULT\n' | tee -a "$report_path"
  printf 'script_216_v13_59_corpus_v3_local_preview=%s\n' "$result" | tee -a "$report_path"
  exit "$status"
}
trap 'record_unexpected_error $?' ERR
trap cleanup EXIT
trap request_stop HUP INT TERM

emit 'purpose=launch_script_215_qualified_v13_59_and_corpus_v3_for_local_human_ui_validation'
emit "started_utc=$timestamp;script_sha256=$script_sha256;script_215_report_sha256=$SCRIPT_215_REPORT_SHA256"
emit 'authorized_actions=inspect_local_prerequisites_read_attended_credentials_start_private_disposable_postgresql_ingest_synthetic_corpus_v3_start_temporary_retrieval_api_start_host_mounted_nextjs_ui_probe_loopback_readiness_supervise_and_clean_on_ctrl_c'
emit 'non_actions=no_accepted_database_contact_no_black_corpus_access_no_remote_host_contact_no_package_or_release_change_no_service_install_or_autostart_no_image_pull_no_runtime_flat_file_index_no_credential_retention'

failure_stage=host_and_container
actual_os_id="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"' | head -n 1)"
actual_os_version="$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"' | head -n 1)"
architecture="$(dpkg --print-architecture)"
[[ "$actual_os_id" == ubuntu && "$actual_os_version" == 24.04 ]] \
  || block local_os_identity_mismatch host_and_container 2
case "$architecture" in arm64|amd64) ;; *) block host_architecture_unsupported host_and_container 2 ;; esac
docker_command=(docker)
if ! docker info >/dev/null 2>&1; then
  emit 'milestone=container_access;state=awaiting_attended_sudo;purpose=start_local_preview_container'
  attended_sudo_validate 'start the local preview container' \
    || block sudo_authentication_failed host_and_container 2
  docker_command=(sudo docker)
  "${docker_command[@]}" info >/dev/null 2>&1 \
    || block container_runtime_unavailable host_and_container 2
fi
web_image="node-24-slim-nextjs-16-4-1:${architecture}"
"${docker_command[@]}" image inspect "$web_image" >/dev/null 2>&1 \
  || block required_local_image_missing host_and_container 2
[[ "$("${docker_command[@]}" image inspect "$web_image" --format '{{.Architecture}}')" == "$architecture" ]] \
  || block image_architecture_mismatch host_and_container 2
[[ -z "$("${docker_command[@]}" container ls --all --quiet --filter "name=^/${WEB_CONTAINER}$")" ]] \
  || block preview_container_name_in_use host_and_container
for reserved_port in "$WEB_PORT" "$API_PORT" "$POSTGRESQL_PORT"; do
  port_is_free "$reserved_port" || block "preview_port_${reserved_port}_in_use" host_and_container
done
emit "milestone=host_and_container;state=pass;os=ubuntu-${actual_os_version};architecture=${architecture};image=${web_image};image_pulled=false;ports=3000,1384,65438_free"

failure_stage=model_forwards
gemma_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
  --connect-timeout 5 --max-time 10 "$GEMMA_BASE_URL/health" 2>/dev/null || true)"
nomic_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
  --connect-timeout 5 --max-time 10 "$NOMIC_BASE_URL/health" 2>/dev/null || true)"
[[ "$gemma_status" == 200 ]] || block gemma_forward_unavailable_on_18000 model_forwards
[[ "$nomic_status" == 200 ]] || block nomic_forward_unavailable_on_18001 model_forwards
emit 'milestone=model_forwards;state=pass;gemma=127.0.0.1:18000;nomic=127.0.0.1:18001;managed_by_script=false'

read_secret() {
  local label="$1" destination="$2" minimum="$3" maximum="$4" value='' count=''
  [[ -r /dev/tty && -w /dev/tty ]] || block interactive_terminal_unavailable credentials
  IFS= read -r -s -p "$label: " value </dev/tty || block secret_entry_failed credentials
  printf '\n' >/dev/tty
  count="$(LC_ALL=C printf '%s' "$value" | wc -c | tr -d ' ')"
  [[ "$count" =~ ^[0-9]+$ ]] || block secret_format_invalid credentials
  (( count >= minimum && count <= maximum )) || block secret_format_invalid credentials
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || block secret_format_invalid credentials
  printf -v "$destination" '%s' "$value"
  value=''
}
failure_stage=credentials
read_secret 'Gemma API key' gemma_key 1 4096
read_secret 'Nomic API key' nomic_key 32 1024
emit 'milestone=credentials;state=accepted;values_logged=false;values_retained=false'

failure_stage=ephemeral_inputs
mkdir -m 0700 -- "$work_root/runtime-config" "$work_root/producer-work" \
  "$work_root/operator-reports" "$work_root/producer-artifacts" \
  "$work_root/socket" "$work_root/staged" \
  || block ephemeral_workspace_creation_failed ephemeral_inputs
PYTHONDONTWRITEBYTECODE=1 python3 -B "$BUNDLE_BUILDER" \
  --candidate "$CANDIDATE" --class-registry "$CONFIG_ROOT/document_classes.yaml" \
  --output "$work_root/promotion-bundle" >"$work_root/bundle.stdout" \
  || block ephemeral_bundle_assembly_failed ephemeral_inputs
grep -Fxq 'synthetic_corpus_v3_ingestion_bundle=pass;documents=30;pages=150;relationship_pairs=90' \
  "$work_root/bundle.stdout" || block ephemeral_bundle_marker_missing ephemeral_inputs
(cd -- "$work_root/promotion-bundle" && sha256sum --quiet -c SHA256SUMS) \
  || block ephemeral_bundle_checksum_failed ephemeral_inputs
bundle_receipt="$work_root/promotion-bundle/bundle-receipt.json"
bundle_receipt_sha256="$(sha256sum -- "$bundle_receipt" | awk '{print $1}')"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$CHUNK_BUILDER" \
  --input "$NORMALIZED" --expected-input-sha256 "$NORMALIZED_SHA256" \
  --output "$work_root/corpus-v3-v6-chunks.json" --python-root "$PYTHON_ROOT" \
  >"$work_root/chunks.stdout" || block chunk_regeneration_failed ephemeral_inputs
[[ "$(sha256sum -- "$work_root/corpus-v3-v6-chunks.json" | awk '{print $1}')" == "$CHUNKS_SHA256" ]] \
  || block regenerated_chunk_identity_mismatch ephemeral_inputs
emit 'milestone=ephemeral_inputs;state=pass;documents=30;pages=150;retrieval_candidates=943;runtime_flat_file_index=false'

failure_stage=temporary_postgresql
"$INITDB" -D "$work_root/postgresql" --username="$(id -un)" \
  --encoding=UTF8 --no-locale --auth=trust \
  >"$work_root/initdb.stdout" 2>"$work_root/initdb.stderr" \
  || block temporary_postgresql_initialization_failed temporary_postgresql
"$PG_CTL" -D "$work_root/postgresql" \
  -o "-k $work_root/socket -h 127.0.0.1 -p $POSTGRESQL_PORT -c fsync=off -c synchronous_commit=off -c full_page_writes=off" \
  -l "$work_root/postgresql.log" -w start \
  >"$work_root/pg-start.stdout" 2>"$work_root/pg-start.stderr" \
  || block temporary_postgresql_start_failed temporary_postgresql
postgresql_started=true
"$PSQL" -X -q -h "$work_root/socket" -p "$POSTGRESQL_PORT" -d postgres \
  -v ON_ERROR_STOP=1 >"$work_root/roles.stdout" 2>"$work_root/roles.stderr" <<'SQL' \
  || block temporary_role_creation_failed temporary_postgresql
CREATE ROLE rag_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
CREATE ROLE rag_ingest LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOREPLICATION NOBYPASSRLS;
CREATE ROLE rag_retrieval LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOREPLICATION NOBYPASSRLS;
SQL
"$CREATEDB" -h "$work_root/socket" -p "$POSTGRESQL_PORT" \
  --owner=rag_owner --encoding=UTF8 --template=template0 rag_catalog \
  >"$work_root/createdb.stdout" 2>"$work_root/createdb.stderr" \
  || block temporary_database_creation_failed temporary_postgresql
"$PSQL" -X -q -h "$work_root/socket" -p "$POSTGRESQL_PORT" -d postgres \
  -v ON_ERROR_STOP=1 >"$work_root/database-access.stdout" \
  2>"$work_root/database-access.stderr" <<'SQL' \
  || block temporary_database_access_configuration_failed temporary_postgresql
REVOKE ALL ON DATABASE rag_catalog FROM PUBLIC;
GRANT CONNECT ON DATABASE rag_catalog TO rag_ingest, rag_retrieval;
ALTER ROLE rag_retrieval IN DATABASE rag_catalog SET default_transaction_read_only = on;
SQL
"$PSQL" -X -q -h "$work_root/socket" -p "$POSTGRESQL_PORT" -d rag_catalog \
  -v ON_ERROR_STOP=1 >"$work_root/extensions.stdout" 2>"$work_root/extensions.stderr" <<'SQL' \
  || block temporary_database_extension_install_failed temporary_postgresql
CREATE EXTENSION vector;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
SQL
"$PSQL" -X -q -h "$work_root/socket" -p "$POSTGRESQL_PORT" -d rag_catalog \
  -v ON_ERROR_STOP=1 -v owner_role=rag_owner -v ingest_role=rag_ingest \
  -v retrieval_role=rag_retrieval -v schema_sha256="$SCHEMA_CONTRACT_SHA256" \
  <"$SCHEMA" >"$work_root/schema.stdout" 2>"$work_root/schema.stderr" \
  || block temporary_schema_install_failed temporary_postgresql
emit 'milestone=temporary_postgresql;state=pass;bind=127.0.0.1:65438;accepted_database_contact=false'

failure_stage=corpus_v3_ingestion
PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$CONFIG_ROOT/deployment.yaml" "$work_root/runtime-config/deployment.yaml" \
  "$POSTGRESQL_PORT" <<'PY' || block ingestion_runtime_config_generation_failed corpus_v3_ingestion
import pathlib
import sys
source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
old = "postgresql:\n  bind_host: 127.0.0.1\n  port: 5432\n"
new = f"postgresql:\n  bind_host: 127.0.0.1\n  port: {sys.argv[3]}\n"
assert source.count(old) == 1
pathlib.Path(sys.argv[2]).write_text(source.replace(old, new), encoding="utf-8")
PY
PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$CONFIG_ROOT/ingestion_dependencies.yaml" \
  "$work_root/runtime-config/ingestion_dependencies.yaml" "$NOMIC_BASE_URL" <<'PY' \
  || block ingestion_dependency_config_generation_failed corpus_v3_ingestion
import pathlib
import sys
source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
assert source.count("http://127.0.0.1:8001") == 2
pathlib.Path(sys.argv[2]).write_text(
    source.replace("http://127.0.0.1:8001", sys.argv[3]), encoding="utf-8"
)
PY
install -m 0644 -- "$CONFIG_ROOT/relationship_types.yaml" \
  "$work_root/runtime-config/relationship_types.yaml" \
  || block ingestion_relationship_config_install_failed corpus_v3_ingestion
runner_arguments=(
  --product-root "$PRODUCT_ROOT"
  --promotion-bundle "$work_root/promotion-bundle"
  --runtime-config-root "$work_root/runtime-config"
  --work-root "$work_root/producer-work"
  --report-root "$work_root/operator-reports"
  --artifact-root "$work_root/producer-artifacts"
  --pipeline-executable "$PIPELINE_EXECUTABLE"
)
emit 'milestone=corpus_v3_ingestion_validation;state=start;documents=30'
ISHIKAWA_NOMIC_API_KEY="$nomic_key" \
ISHIKAWA_POSTGRESQL_INGEST_PASSWORD="$database_password" \
PYTHONDONTWRITEBYTECODE=1 timeout --signal=TERM --kill-after=15s 3600s \
  python3 -B "$INGESTION_RUNNER" --mode validate-only "${runner_arguments[@]}" \
  >"$work_root/ingestion-validate.stdout" 2>"$work_root/ingestion-validate.stderr" &
active_pid="$!"
wait_with_heartbeat "$active_pid" corpus_v3_ingestion_validation "$work_root/ingestion-validate.stdout" \
  || block corpus_v3_ingestion_validation_failed corpus_v3_ingestion
active_pid=''
grep -Fxq 'actions=add:30,reprocess:0,retire:0,reuse:0,revise:0' \
  "$work_root/ingestion-validate.stdout" || block corpus_v3_ingestion_plan_invalid corpus_v3_ingestion
emit 'milestone=corpus_v3_ingestion_validation;state=pass;actions=add:30,reprocess:0,retire:0,reuse:0,revise:0'
emit 'milestone=corpus_v3_ingestion_publication;state=start;documents=30'
ISHIKAWA_NOMIC_API_KEY="$nomic_key" \
ISHIKAWA_POSTGRESQL_INGEST_PASSWORD="$database_password" \
PYTHONDONTWRITEBYTECODE=1 timeout --signal=TERM --kill-after=15s 3600s \
  python3 -B "$INGESTION_RUNNER" --mode publish "${runner_arguments[@]}" \
  >"$work_root/ingestion-publish.stdout" 2>"$work_root/ingestion-publish.stderr" &
active_pid="$!"
wait_with_heartbeat "$active_pid" corpus_v3_ingestion_publication "$work_root/ingestion-publish.stdout" \
  || block corpus_v3_ingestion_publication_failed corpus_v3_ingestion
active_pid=''
grep -Fxq 'ishikawa_ingestion=pass;exit_code=0' "$work_root/ingestion-publish.stdout" \
  || block corpus_v3_ingestion_marker_missing corpus_v3_ingestion

database_artifact="$work_root/corpus-v3-database.json"
ISHIKAWA_POSTGRESQL_PASSWORD="$database_password" PYTHONDONTWRITEBYTECODE=1 \
  python3 -B "$DATABASE_QUALIFIER" --run \
  --chunks "$work_root/corpus-v3-v6-chunks.json" \
  --expected-chunks-sha256 "$CHUNKS_SHA256" \
  --corpus-truth "$CORPUS_TRUTH" \
  --expected-corpus-truth-sha256 "$CORPUS_TRUTH_SHA256" \
  --bundle-receipt "$bundle_receipt" \
  --expected-bundle-receipt-sha256 "$bundle_receipt_sha256" \
  --postgresql-socket "$work_root/socket" --postgresql-port "$POSTGRESQL_PORT" \
  --output "$database_artifact" \
  >"$work_root/database-qualifier.stdout" 2>"$work_root/database-qualifier.stderr" \
  || block corpus_v3_database_qualification_failed corpus_v3_ingestion
grep -Eq '^isolated_synthetic_corpus_v3_database=pass;documents=30;pages=150;authoritative_chunks=786;retrieval_candidates=943;representatives=157;relationship_records=[0-9]+;relationship_pairs=90$' \
  "$work_root/database-qualifier.stdout" \
  || block database_qualification_marker_missing corpus_v3_ingestion
emit 'milestone=corpus_v3_ingestion;state=pass;documents=30;pages=150;authoritative_chunks=786;retrieval_candidates=943;representatives=157;relationship_pairs=90'

failure_stage=retrieval_api
installed_root="$work_root/staged/Ishikawa"
install -d -m 0755 -- "$installed_root/application/python/ishikawa" \
  "$installed_root/config" "$installed_root/scripts" \
  || block staged_product_install_failed retrieval_api
install -d -m 0700 -- "$installed_root/state/logs" "$installed_root/state/run" \
  || block staged_product_install_failed retrieval_api
while IFS= read -r source; do
  install -m 0644 -- "$source" \
    "$installed_root/application/python/ishikawa/$(basename -- "$source")" \
    || block staged_product_install_failed retrieval_api
done < <(find "$PACKAGE_ROOT" -maxdepth 1 -type f -name '*.py' -print | sort)
while IFS= read -r source; do
  install -m 0644 -- "$source" "$installed_root/config/$(basename -- "$source")" \
    || block staged_product_install_failed retrieval_api
done < <(find "$CONFIG_ROOT" -maxdepth 1 -type f -name '*.yaml' -print | sort)
install -m 0755 -- "$SERVICE_ENTRYPOINT" "$installed_root/scripts/ishikawa-retrieval-api" \
  || block staged_product_install_failed retrieval_api
PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$installed_root/config/deployment.yaml" "$POSTGRESQL_PORT" <<'PY' \
  || block staged_runtime_config_generation_failed retrieval_api
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
old = "postgresql:\n  bind_host: 127.0.0.1\n  port: 5432\n"
new = f"postgresql:\n  bind_host: 127.0.0.1\n  port: {sys.argv[2]}\n"
assert source.count(old) == 1
path.write_text(source.replace(old, new), encoding="utf-8")
PY
PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$installed_root/config/runtime_dependencies.yaml" "$GEMMA_BASE_URL" "$NOMIC_BASE_URL" <<'PY' \
  || block staged_dependency_config_generation_failed retrieval_api
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
assert source.count("http://127.0.0.1:8000") == 3
assert source.count("http://127.0.0.1:8001") == 2
path.write_text(
    source.replace("http://127.0.0.1:8000", sys.argv[2]).replace(
        "http://127.0.0.1:8001", sys.argv[3]
    ),
    encoding="utf-8",
)
PY
env -u ISHIKAWA_GEMMA_API_KEY -u ISHIKAWA_NOMIC_API_KEY \
  -u ISHIKAWA_POSTGRESQL_PASSWORD PYTHONDONTWRITEBYTECODE=1 \
  "$installed_root/scripts/ishikawa-retrieval-api" --check-config \
  >"$work_root/check-config.stdout" 2>"$work_root/check-config.stderr" \
  || block staged_configuration_invalid retrieval_api
ISHIKAWA_GEMMA_API_KEY="$gemma_key" \
ISHIKAWA_NOMIC_API_KEY="$nomic_key" \
ISHIKAWA_POSTGRESQL_PASSWORD="$database_password" \
PYTHONDONTWRITEBYTECODE=1 \
  "$installed_root/scripts/ishikawa-retrieval-api" --serve \
  >"$work_root/service.stdout" 2>"$work_root/service.stderr" &
service_pid="$!"
ready=false; ready_started="$(date +%s)"; ready_heartbeat=$(( ready_started + 30 ))
for _ in $(seq 1 300); do
  kill -0 "$service_pid" 2>/dev/null || break
  ready_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
    --connect-timeout 1 --max-time 5 "$RETRIEVAL_BASE_URL/ready" 2>/dev/null || true)"
  if [[ "$ready_status" == 200 ]]; then ready=true; break; fi
  now="$(date +%s)"
  if (( now >= ready_heartbeat )); then
    emit "milestone=retrieval_api;state=starting;elapsed_seconds=$(( now - ready_started ))"
    ready_heartbeat=$(( now + 30 ))
  fi
  sleep 1
done
[[ "$ready" == true ]] || block retrieval_api_not_ready retrieval_api
emit 'milestone=retrieval_api;state=pass;bind=127.0.0.1:1384;nomic_warmup=pass;corpus=synthetic-corpus-v3'

failure_stage=chat_ui
declare -a web_mounts=(
  --mount "type=bind,src=$WEB_ROOT/app,dst=/opt/nextjs/app,readonly"
  --mount "type=bind,src=$WEB_ROOT/components,dst=/opt/nextjs/components,readonly"
  --mount "type=bind,src=$WEB_ROOT/lib,dst=/opt/nextjs/lib,readonly"
  --mount "type=bind,src=$WEB_ROOT/public,dst=/opt/nextjs/public,readonly"
  --mount "type=bind,src=$WEB_ROOT/package.json,dst=/opt/nextjs/package.json,readonly"
  --mount "type=bind,src=$WEB_ROOT/next.config.mjs,dst=/opt/nextjs/next.config.mjs,readonly"
)
"${docker_command[@]}" run --rm --name "$WEB_CONTAINER" --network host \
  --security-opt no-new-privileges --cap-drop ALL \
  --env "ISHIKAWA_PRODUCT_DISPLAY_NAME=$product_name" \
  --env "ISHIKAWA_PRODUCT_UI_CONFIG_BASE64=$product_ui_config_base64" \
  --env "ISHIKAWA_RETRIEVAL_BASE_URL=$RETRIEVAL_BASE_URL" \
  "${web_mounts[@]}" "$web_image" \
  npm run dev -- --hostname 127.0.0.1 --port "$WEB_PORT" \
  >"$work_root/web.stdout" 2>"$work_root/web.stderr" &
web_client_pid="$!"
web_ready=false; web_ready_started="$(date +%s)"; web_ready_heartbeat=$(( web_ready_started + 15 ))
for _ in $(seq 1 180); do
  web_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
    --connect-timeout 1 --max-time 5 "$WEB_BASE_URL/api/ready" 2>/dev/null || true)"
  if [[ "$web_status" == 200 ]]; then web_ready=true; break; fi
  process_is_running "$web_client_pid" || break
  now="$(date +%s)"
  if (( now >= web_ready_heartbeat )); then
    emit "milestone=chat_ui;state=starting;elapsed_seconds=$(( now - web_ready_started ))"
    web_ready_heartbeat=$(( now + 15 ))
  fi
  sleep 1
done
[[ "$web_ready" == true ]] || block chat_ui_not_ready chat_ui
curl --fail --silent --show-error --connect-timeout 2 --max-time 15 \
  "$WEB_BASE_URL/" >"$work_root/home.html" || block chat_workspace_unavailable chat_ui
grep -Fq "$product_name" "$work_root/home.html" || block chat_workspace_contract_invalid chat_ui
grep -Fq 'Knowledge chat' "$work_root/home.html" || block chat_workspace_contract_invalid chat_ui
curl --fail --silent --show-error --connect-timeout 2 --max-time 10 \
  "$WEB_BASE_URL/api/dependencies" >"$work_root/dependencies.json" \
  || block dependency_indicator_unavailable chat_ui
PYTHONDONTWRITEBYTECODE=1 python3 -B - "$work_root/dependencies.json" <<'PY' \
  || block dependency_indicator_invalid chat_ui
import json
import pathlib
import sys
response = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert response == {
    "gemma": "available",
    "nomic": "available",
    "schema": "ishikawa.web-dependency-health.v1",
}
PY

gemma_key=''; nomic_key=''; database_password=''
unset ISHIKAWA_GEMMA_API_KEY ISHIKAWA_NOMIC_API_KEY \
  ISHIKAWA_POSTGRESQL_PASSWORD ISHIKAWA_POSTGRESQL_INGEST_PASSWORD
preview_ready=true
emit 'milestone=chat_ui;state=pass;bind=127.0.0.1:3000;gemma=available;nomic=available;candidate=v13_59;corpus=synthetic-corpus-v3;documents=30;hot_reload=true'
emit 'script_216_v13_59_corpus_v3_local_preview=ready;url=http://127.0.0.1:3000;stop=ctrl_c;next_gate=interactive_browser_review'
printf '%s\n' '' \
  'Ishikawa v1.3 with corpus v3 is ready at http://127.0.0.1:3000.' \
  'Leave this terminal open during testing. Press Ctrl+C once to stop and verify cleanup.'

failure_stage=supervision
while true; do
  kill -0 "$service_pid" 2>/dev/null || block retrieval_api_exited_unexpectedly supervision
  process_is_running "$web_client_pid" || block chat_ui_exited_unexpectedly supervision
  sleep 5
done

