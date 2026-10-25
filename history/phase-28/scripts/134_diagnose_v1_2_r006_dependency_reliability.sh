#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Diagnose the isolated R-006 dependency failure from Script 133 without
#   changing Ishikawa's retry policy, source, database, services, or packages.
#
# Mental model:
#   Stage the exact v1.2 candidate, start one temporary loopback API, submit
#   only R-006 five times, and retain content-free stage traces that show
#   first-attempt success, retry recovery, failure after retry, or another
#   dependency boundary.
#
# Inputs or prerequisites:
#   The clean-but-not-promoted Script 133 observation, local PostgreSQL,
#   forwarded Gemma on 127.0.0.1:8000, forwarded Nomic on 127.0.0.1:8001,
#   and the three runtime credentials.
#
# Outputs:
#   One content-free report and diagnostic artifact. No raw question, answer,
#   excerpt, prompt, vector, credential, or model response is retained.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/134_diagnose_v1_2_r006_dependency_reliability.sh --run

usage() {
  sed -n '3,27p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run            Run five bounded R-006 diagnostic probes.' \
    '  --validate-only  Validate bound inputs and helper self-test only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PACKAGE_ROOT="$PRODUCT_ROOT/application/python/ishikawa"
readonly CONFIG_ROOT="$PRODUCT_ROOT/config/templates"
readonly SERVICE_ENTRYPOINT="$PRODUCT_ROOT/scripts/ishikawa-retrieval-api"
readonly DIAGNOSTIC="$SCRIPT_DIR/diagnose_t10_generation_reliability.py"
readonly CONTRACT_HELPER="$SCRIPT_DIR/capture-ishikawa-retrieval-baseline.py"
readonly CASES="$PHASE_ROOT/reference/ishikawa-retrieval-tuning-cases-v1.1.json"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_1_TUNING_DECISIONS.md"
readonly SCRIPT_133_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.2-complete-api/complete_api_20261021T205427Z_LbLapN.txt"
readonly SCRIPT_133_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/v1.2-complete-api/complete_api_82446a37ded1b2acb963c76842504101d5f01b7122a0f40d39c5a71c2585786d.json"
readonly SCRIPT_133_CHECKSUM="$SCRIPT_133_ARTIFACT.sha256"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.2-t10-reliability-diagnostic"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v1.2-t10-reliability-diagnostic"

readonly DIAGNOSTIC_SHA256='160a3bb0eeae856cdba8cce1467995ac8ce4d18e91e2de1b816405b0024da4f1'
readonly CONTRACT_HELPER_SHA256='74ad3f7259d1bffa395ac52c2356dae83a708d98ecb7518b7cff2ca0c5d165de'
readonly CASES_SHA256='feb2303d8433461846974015078d88ca42593636c399fc90fcd9c2e67beab6f9'
readonly DECISIONS_SHA256='5eb902509ce604891fb54fee30f447179a8b0c38f6cff480018eceb45dc5c6eb'
readonly SCRIPT_133_REPORT_SHA256='fb3b8af4ebeca372297ae337610ecb9b4dac342244c11b6b69f5c7ecadc849da'
readonly SCRIPT_133_ARTIFACT_SHA256='82446a37ded1b2acb963c76842504101d5f01b7122a0f40d39c5a71c2585786d'
readonly SCRIPT_133_CHECKSUM_SHA256='1b24770cfd5b89dceeb36299517df1c4a1a1441f1f6fe16c88e3840490b5c5b0'
readonly SOURCE_MANIFEST_SHA256='4f2ac14234ee9bcd2ffe00fccf9048bf3ca125bf5c0de5d4ebd5bda391bdbcd6'
readonly SOURCE_FILE_COUNT='67'
readonly EXPECTED_HOSTNAME='DankoSurface'
readonly EXPECTED_OS_VERSION='24.04'
readonly EXPECTED_ARCHITECTURE='aarch64'
readonly API_ENDPOINT='http://127.0.0.1:1384/v1/chat'
readonly GEMMA_HEALTH_URL='http://127.0.0.1:8000/health'
readonly NOMIC_HEALTH_URL='http://127.0.0.1:8001/health'

run_mode=false
validate_mode=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_mode=true; shift ;;
    --validate-only) validate_mode=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_134_r006_diagnostic=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_mode" != "$validate_mode" ]] || {
  printf 'script_134_r006_diagnostic=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in awk bash basename chmod curl date env find grep head hostname install kill mkdir mktemp mv pg_isready python3 rm sed seq sha256sum sleep sort ss stat tail tee tr uname wc; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_134_r006_diagnostic=blocked;reason=local_command_missing;command=%s\n' "$required" >&2
    exit 2
  }
done

check_file() {
  [[ -f "$1" && ! -L "$1" && -r "$1" ]] || {
    printf 'script_134_r006_diagnostic=blocked;reason=%s_unsafe\n' "$3" >&2
    exit 2
  }
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_134_r006_diagnostic=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}

check_file "$DIAGNOSTIC" "$DIAGNOSTIC_SHA256" diagnostic
check_file "$CONTRACT_HELPER" "$CONTRACT_HELPER_SHA256" contract_helper
check_file "$CASES" "$CASES_SHA256" case_set
check_file "$DECISIONS" "$DECISIONS_SHA256" tuning_decisions
check_file "$SCRIPT_133_REPORT" "$SCRIPT_133_REPORT_SHA256" script_133_report
check_file "$SCRIPT_133_ARTIFACT" "$SCRIPT_133_ARTIFACT_SHA256" script_133_artifact
check_file "$SCRIPT_133_CHECKSUM" "$SCRIPT_133_CHECKSUM_SHA256" script_133_checksum
[[ -f "$SERVICE_ENTRYPOINT" && ! -L "$SERVICE_ENTRYPOINT" && -r "$SERVICE_ENTRYPOINT" ]] || {
  printf 'script_134_r006_diagnostic=blocked;reason=service_entrypoint_unsafe\n' >&2
  exit 2
}
(
  cd -- "$(dirname -- "$SCRIPT_133_CHECKSUM")"
  sha256sum --check --strict "$(basename -- "$SCRIPT_133_CHECKSUM")" >/dev/null
) || {
  printf 'script_134_r006_diagnostic=blocked;reason=script_133_checksum_invalid\n' >&2
  exit 2
}
for fact in \
  '[SUMMARY] retrieval_api_acceptance=pass;cases=13;contract_valid=13;expected_status_matches=12;required_evidence=13;required_evidence_returned=11;required_evidence_cited=7;' \
  '[SUMMARY] full_api_gate=not_met;responsive_answered=5/6;nonresponsive_abstained=6/6;broad_clarification=1/1;dependency_failures=1' \
  'script_133_v1_2_complete_api=pass;full_api_gate=not_met;next_gate=review_v1_2_complete_api_case_results_before_further_change;'; do
  grep -Fq "$fact" "$SCRIPT_133_REPORT" || {
    printf 'script_134_r006_diagnostic=blocked;reason=script_133_contract_invalid\n' >&2
    exit 2
  }
done
for decision in T10 T12 T13; do
  grep -Eq "^\\| \`$decision\` \\|.*\\| FROZEN \\|$" "$DECISIONS" || {
    printf 'script_134_r006_diagnostic=blocked;reason=%s_not_frozen\n' "${decision,,}" >&2
    exit 2
  }
done

mapfile -t python_sources < <(find "$PACKAGE_ROOT" -maxdepth 1 -type f -name '*.py' -print | sort)
mapfile -t configuration_sources < <(find "$CONFIG_ROOT" -maxdepth 1 -type f -name '*.yaml' -print | sort)
(( ${#python_sources[@]} == 48 && ${#configuration_sources[@]} == 18 )) || {
  printf 'script_134_r006_diagnostic=blocked;reason=source_inventory_count_invalid\n' >&2
  exit 2
}
for source in "${python_sources[@]}" "${configuration_sources[@]}" "$SERVICE_ENTRYPOINT"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'script_134_r006_diagnostic=blocked;reason=source_inventory_unsafe\n' >&2
    exit 2
  }
done

umask 077
work_root="$(mktemp -d /tmp/ishikawa-script-134.XXXXXX)"
preflight_cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  [[ "$work_root" == /tmp/ishikawa-script-134.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  exit "$status"
}
trap preflight_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
source_manifest="$work_root/source.sha256"
for source in "${python_sources[@]}" "${configuration_sources[@]}" "$SERVICE_ENTRYPOINT"; do
  printf '%s  %s\n' "$(sha256sum "$source" | awk '{print $1}')" "${source#"$PRODUCT_ROOT"/}"
done >"$source_manifest"
[[ "$(wc -l <"$source_manifest" | tr -d ' ')" == "$SOURCE_FILE_COUNT" ]] || {
  printf 'script_134_r006_diagnostic=blocked;reason=source_manifest_count_invalid\n' >&2
  exit 2
}
[[ "$(sha256sum "$source_manifest" | awk '{print $1}')" == "$SOURCE_MANIFEST_SHA256" ]] || {
  printf 'script_134_r006_diagnostic=blocked;reason=source_manifest_identity_changed\n' >&2
  exit 2
}

bash -n "${BASH_SOURCE[0]}"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$DIAGNOSTIC" "$CONTRACT_HELPER" "${python_sources[@]}"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$DIAGNOSTIC" --self-test \
  | grep -Fxq 't10_generation_reliability_diagnostic_self_test=pass' || {
    printf 'script_134_r006_diagnostic=blocked;reason=diagnostic_self_test_failed\n' >&2
    exit 2
  }

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_mode" == true ]]; then
  printf '%s\n' \
    'purpose=validate_v1_2_r006_dependency_reliability_diagnostic' \
    "script_sha256=$script_sha256;diagnostic_sha256=$DIAGNOSTIC_SHA256;contract_helper_sha256=$CONTRACT_HELPER_SHA256" \
    "script_133_report_sha256=$SCRIPT_133_REPORT_SHA256;script_133_artifact_sha256=$SCRIPT_133_ARTIFACT_SHA256" \
    "decision_list_sha256=$DECISIONS_SHA256;source_manifest_sha256=$SOURCE_MANIFEST_SHA256;source_files=$SOURCE_FILE_COUNT" \
    'case=R-006;probe_count=5;raw_content_retained=false;policy_changed=false' \
    'diagnostic_self_test=pass;database_contact=false;model_contact=false;credential_read=false;listener_started=false' \
    'script_134_r006_diagnostic_source=pass'
  exit 0
fi

trap - EXIT INT TERM
gemma_key=''
nomic_key=''
database_password=''
service_pid=''
diagnostic_pid=''
report_path=''
artifact_committed=false
artifact_created=false
artifact_path=''
checksum_path=''

cleanup() {
  local status="$?"
  trap - EXIT INT TERM ERR
  gemma_key=''
  nomic_key=''
  database_password=''
  unset gemma_key nomic_key database_password ISHIKAWA_GEMMA_API_KEY ISHIKAWA_NOMIC_API_KEY ISHIKAWA_POSTGRESQL_PASSWORD
  if [[ "$diagnostic_pid" =~ ^[0-9]+$ ]] && kill -0 "$diagnostic_pid" 2>/dev/null; then
    kill -TERM "$diagnostic_pid" 2>/dev/null || true
    wait "$diagnostic_pid" 2>/dev/null || true
  fi
  if [[ "$service_pid" =~ ^[0-9]+$ ]] && kill -0 "$service_pid" 2>/dev/null; then
    kill -TERM "$service_pid" 2>/dev/null || true
    wait "$service_pid" 2>/dev/null || true
  fi
  if [[ "$artifact_created" == true && "$artifact_committed" != true ]]; then
    [[ "$artifact_path" == "$ARTIFACT_ROOT"/r006_reliability_*.json ]] && rm -f -- "$artifact_path"
    [[ "$checksum_path" == "$ARTIFACT_ROOT"/r006_reliability_*.json.sha256 ]] && rm -f -- "$checksum_path"
  fi
  [[ "$work_root" == /tmp/ishikawa-script-134.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  [[ -z "$report_path" ]] || chmod 0600 "$report_path" 2>/dev/null || true
  exit "$status"
}
trap cleanup EXIT

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" && -d "$ARTIFACT_ROOT" && ! -L "$ARTIFACT_ROOT" ]] || {
  printf 'script_134_r006_diagnostic=blocked;reason=output_directory_unsafe\n' >&2
  exit 1
}
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/r006_reliability_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
block() { emit "script_134_r006_diagnostic=blocked;reason=$1;local_report=$report_path"; exit 1; }
trap 'block interrupted_by_operator' INT
trap 'block terminated_by_signal' TERM

read_secret() {
  local label="$1" output_name="$2" value=''
  printf '%s (input hidden): ' "$label" >/dev/tty
  IFS= read -r -s value </dev/tty || block secret_input_failed
  printf '\n' >/dev/tty
  (( ${#value} >= 1 && ${#value} <= 4096 )) || block secret_length_invalid
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || block secret_character_invalid
  printf -v "$output_name" '%s' "$value"
  value=''
}

emit 'purpose=diagnose_v1_2_r006_dependency_reliability'
emit "started_utc=$timestamp;script_sha256=$script_sha256;diagnostic_sha256=$DIAGNOSTIC_SHA256"
emit "script_133_report_sha256=$SCRIPT_133_REPORT_SHA256;script_133_artifact_sha256=$SCRIPT_133_ARTIFACT_SHA256;source_manifest_sha256=$SOURCE_MANIFEST_SHA256"
emit 'authorized_actions=start_temporary_loopback_api_submit_r006_five_times_read_temporary_content_free_logs_retain_content_free_diagnostic'
emit 'non_actions=no_policy_or_source_change_no_database_write_no_package_build_no_accepted_release_change_no_raw_content_or_secret_retention'

actual_hostname="$(hostname -s)"
actual_os_id="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"' | head -n 1)"
actual_os_version="$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"' | head -n 1)"
actual_architecture="$(uname -m)"
[[ "$actual_hostname" == "$EXPECTED_HOSTNAME" \
    && "$actual_os_id" == ubuntu \
    && "$actual_os_version" == "$EXPECTED_OS_VERSION" \
    && "$actual_architecture" == "$EXPECTED_ARCHITECTURE" ]] || block local_host_identity_mismatch
ss -H -ltn '( sport = :1384 )' | grep -q . && block port_1384_in_use
pg_isready -q -h 127.0.0.1 -p 5432 -d rag_catalog -t 5 || block local_postgresql_unavailable
gemma_status="$(curl --silent --output /dev/null --write-out '%{http_code}' --connect-timeout 5 --max-time 10 "$GEMMA_HEALTH_URL" 2>/dev/null)" || gemma_status=000
nomic_status="$(curl --silent --output /dev/null --write-out '%{http_code}' --connect-timeout 5 --max-time 10 "$NOMIC_HEALTH_URL" 2>/dev/null)" || nomic_status=000
emit "milestone=live_prerequisites;state=observed;postgresql_ready=true;gemma_http_status=$gemma_status;nomic_http_status=$nomic_status;port_1384_available=true"
[[ "$gemma_status" == 200 ]] || block gemma_health_unavailable
[[ "$nomic_status" == 200 ]] || block nomic_health_unavailable

read_secret 'Gemma API key' gemma_key
read_secret 'Nomic API key' nomic_key
read_secret 'rag_retrieval PostgreSQL password' database_password

installed_root="$work_root/Ishikawa"
install -d -m 0755 -- "$installed_root/application/python/ishikawa" "$installed_root/config" "$installed_root/scripts"
install -d -m 0700 -- "$installed_root/state/logs" "$installed_root/state/run"
for source in "${python_sources[@]}"; do
  install -m 0644 -- "$source" "$installed_root/application/python/ishikawa/$(basename -- "$source")"
done
for source in "${configuration_sources[@]}"; do
  install -m 0644 -- "$source" "$installed_root/config/$(basename -- "$source")"
done
install -m 0755 -- "$SERVICE_ENTRYPOINT" "$installed_root/scripts/ishikawa-retrieval-api"

check_output="$work_root/check-config.txt"
env -u ISHIKAWA_GEMMA_API_KEY -u ISHIKAWA_NOMIC_API_KEY -u ISHIKAWA_POSTGRESQL_PASSWORD \
  PYTHONDONTWRITEBYTECODE=1 "$installed_root/scripts/ishikawa-retrieval-api" --check-config >"$check_output"
grep -Eq '^ishikawa_retrieval_api_configuration=pass;policy_digest=[0-9a-f]{64};credential_read=false;dependency_contact=false$' "$check_output" \
  || block staged_configuration_invalid

service_output="$work_root/service.stdout"
service_error="$work_root/service.stderr"
emit 'milestone=temporary_api;state=start'
ISHIKAWA_GEMMA_API_KEY="$gemma_key" \
ISHIKAWA_NOMIC_API_KEY="$nomic_key" \
ISHIKAWA_POSTGRESQL_PASSWORD="$database_password" \
PYTHONDONTWRITEBYTECODE=1 \
  "$installed_root/scripts/ishikawa-retrieval-api" --serve >"$service_output" 2>"$service_error" &
service_pid="$!"
gemma_key=''
nomic_key=''
database_password=''
unset gemma_key nomic_key database_password
ready=false
for _attempt in $(seq 1 60); do
  kill -0 "$service_pid" 2>/dev/null || break
  ready_status="$(curl --silent --output /dev/null --write-out '%{http_code}' --connect-timeout 1 --max-time 5 http://127.0.0.1:1384/ready 2>/dev/null)" || ready_status=000
  if [[ "$ready_status" == 200 ]]; then ready=true; break; fi
  sleep 1
done
[[ "$ready" == true ]] || block temporary_service_not_ready
emit 'milestone=temporary_api;state=pass;readiness=ready'

diagnostic_candidate="$work_root/r006-reliability.json"
diagnostic_output="$work_root/diagnostic.stdout"
diagnostic_error="$work_root/diagnostic.stderr"
emit 'milestone=r006_reliability_probe;state=start;probes=5'
started_epoch="$(date +%s)"
PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 python3 -B "$DIAGNOSTIC" \
  --run \
  --contract-helper "$CONTRACT_HELPER" \
  --cases "$CASES" \
  --product-root "$installed_root" \
  --endpoint "$API_ENDPOINT" \
  --output "$diagnostic_candidate" \
  >"$diagnostic_output" 2>"$diagnostic_error" &
diagnostic_pid="$!"
next_heartbeat_epoch=$(( started_epoch + 30 ))
while kill -0 "$diagnostic_pid" 2>/dev/null; do
  sleep 5
  current_epoch="$(date +%s)"
  if (( current_epoch >= next_heartbeat_epoch )) && kill -0 "$diagnostic_pid" 2>/dev/null; then
    emit "milestone=r006_reliability_probe;state=running;elapsed_seconds=$(( current_epoch - started_epoch ))"
    next_heartbeat_epoch=$(( current_epoch + 30 ))
  fi
done
if wait "$diagnostic_pid"; then diagnostic_status=0; else diagnostic_status=$?; fi
diagnostic_pid=''
if (( diagnostic_status != 0 )); then
  reason="$(sed -nE 's/^t10_generation_reliability_diagnostic=blocked;reason=([A-Za-z0-9_]+)$/\1/p' "$diagnostic_error" | tail -n 1)"
  [[ -n "$reason" ]] || reason=unclassified_diagnostic_failure
  block "$reason"
fi
grep -Fxq 't10_generation_reliability_diagnostic=pass' "$diagnostic_output" || block diagnostic_pass_marker_absent
probe_summary="$(grep -E '^probe_count=5;answered=[0-5];temporarily_unavailable=[0-5];generation_retried=[0-5];generation_failed_after_retry=[0-5];other_dependency_failures=[0-5];internal_errors=[0-5]$' "$diagnostic_output")" \
  || block diagnostic_summary_invalid
interpretation_line="$(grep -E '^diagnostic_interpretation=[a-z_]+;raw_content_retained=false$' "$diagnostic_output")" \
  || block diagnostic_interpretation_invalid
emit 'milestone=r006_reliability_probe;state=pass;probes=5'
while IFS= read -r line; do
  [[ "$line" =~ ^probe_result= ]] && emit "$line"
done <"$diagnostic_output"
emit "$probe_summary"
emit "$interpretation_line"

kill -TERM "$service_pid"
set +e
wait "$service_pid"
service_exit=$?
set -e
service_pid=''
(( service_exit == 0 )) || block temporary_service_exit_failed
for _attempt in $(seq 1 50); do
  if ! ss -H -ltn '( sport = :1384 )' | grep -q .; then break; fi
  sleep 0.1
done
ss -H -ltn '( sport = :1384 )' | grep -q . && block temporary_service_listener_cleanup_failed
emit 'milestone=temporary_api;state=stopped;cleanup=complete'

artifact_validation="$work_root/artifact-validation.txt"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$DIAGNOSTIC" --validate-artifact --artifact "$diagnostic_candidate" \
  >"$artifact_validation" || block artifact_validation_failed
grep -Eq '^t10_generation_reliability_artifact=pass;probes=5;answered=[0-5];temporarily_unavailable=[0-5];interpretation=[a-z_]+$' "$artifact_validation" \
  || block artifact_validation_marker_invalid

artifact_path="$ARTIFACT_ROOT/r006_reliability_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] \
  || block artifact_path_exists
mv -- "$diagnostic_candidate" "$artifact_path"
artifact_created=true
artifact_sha256="$(sha256sum "$artifact_path" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$artifact_path")"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
(
  cd -- "$ARTIFACT_ROOT"
  sha256sum --check --strict "$(basename -- "$checksum_path")" >/dev/null
) || block artifact_checksum_failed
artifact_committed=true
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$artifact_bytes;checksum=$checksum_path"
emit 'database_write=false;policy_changed=false;package_built=false;accepted_v1_1_changed=false;raw_content_retained=false;credentials_retained=false'
emit "script_134_r006_diagnostic=pass;next_gate=review_t10_reliability_diagnostic_before_any_policy_or_package_change;local_report=$report_path"
