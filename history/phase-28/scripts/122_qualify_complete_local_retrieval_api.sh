#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the complete Ishikawa v1.1 Retrieval API against all 13 accepted
#   synthetic cases on DankoSurface.
#
# Mental model:
#   Stage the checksum-bound application in private temporary storage, inject
#   three operator-provided runtime credentials, start one loopback Retrieval
#   API, call it once per case, validate every response, then stop and remove
#   the temporary service. Ranking is not re-scored here; this gate proves
#   abstention, clarification, grounded generation, and dependency health.
#
# Inputs or prerequisites:
#   Clean Script 120, 121, and 123 receipts; local native PostgreSQL with the
#   accepted corpus; forwarded Gemma on 127.0.0.1:8000; forwarded Nomic on
#   127.0.0.1:8001; and the three runtime credentials. Script 123 proves the
#   frozen T10 bounded grounded-generation retry before this live gate runs.
#
# Outputs or artifact lane:
#   One content-free report and one private checksum-bound synthetic response
#   artifact. Database contents, configuration, services, models, and packages
#   are not changed.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/122_qualify_complete_local_retrieval_api.sh --run

usage() {
  sed -n '3,30p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run            Run the complete local Retrieval API qualification.' \
    '  --validate-only  Validate bound source and evaluator self-tests only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PACKAGE_ROOT="$PRODUCT_ROOT/application/python/ishikawa"
readonly CONFIG_ROOT="$PRODUCT_ROOT/config/templates"
readonly SERVICE_ENTRYPOINT="$PRODUCT_ROOT/scripts/ishikawa-retrieval-api"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_local_retrieval_api_acceptance.py"
readonly CONTRACT_HELPER="$SCRIPT_DIR/capture-ishikawa-retrieval-baseline.py"
readonly CASES="$PHASE_ROOT/reference/ishikawa-retrieval-tuning-cases-v1.1.json"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_1_TUNING_DECISIONS.md"
readonly SCRIPT_120_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.1-t09-implementation/t09_implementation_20261021T173849Z_SUwSNN.txt"
readonly SCRIPT_121_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.1-t09-live-ranking/t09_live_ranking_20261021T174917Z_Q69ZRa.txt"
readonly SCRIPT_121_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/v1.1-t09-live-ranking/t09_live_ranking_a2ff0c0ae76e1469ccded3bec36844a3aac1697c09260b09edc567877e57fb36.json"
readonly SCRIPT_121_CHECKSUM="$SCRIPT_121_ARTIFACT.sha256"
readonly SCRIPT_123_SOURCE="$SCRIPT_DIR/123_qualify_t10_grounded_generation_retry.sh"
readonly SCRIPT_123_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.1-t10-implementation/t10_implementation_20261021T183354Z_sw0TV0.txt"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.1-complete-api"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v1.1-complete-api"

readonly EVALUATOR_SHA256='de8a04ef7f70c51e4d4433ef225947f2005fd1341fc260b0aa53ca9806091a8a'
readonly CONTRACT_HELPER_SHA256='74ad3f7259d1bffa395ac52c2356dae83a708d98ecb7518b7cff2ca0c5d165de'
readonly CASES_SHA256='feb2303d8433461846974015078d88ca42593636c399fc90fcd9c2e67beab6f9'
readonly DECISIONS_SHA256='c6521704144132968a2b6b1a4a1c7136e5c3f5e30f41cbf67246247dbf5e81d5'
readonly SCRIPT_120_REPORT_SHA256='95ce7a833812160a8c13ada3fb69c7ce584590d5b99a3d08335972a7ecd79750'
readonly SCRIPT_121_REPORT_SHA256='55c6ee6931d478d9604c1f1872bea20965b4e02810ea579aceb4229e2e2d733e'
readonly SCRIPT_121_ARTIFACT_SHA256='20d09f02e028ef2189d680e6ac058acf332b59cf42338ff48059e9f897501d12'
readonly SCRIPT_121_CHECKSUM_SHA256='5f358605ac58624ce657b45dc20cbc7a7fa1b2ee5bd528c99c5aa78a18751611'
readonly SCRIPT_123_SOURCE_SHA256='c0694bfc9db679431c2ae01a729b29fc61ece93048aa32ca235dd1f022ccab43'
readonly SCRIPT_123_REPORT_SHA256='d96f9e5d9c117d02abc780ad5ea49b9fa3c39467020694967e342bc1b991bd7c'
readonly SOURCE_MANIFEST_SHA256='513b6347da72630bfe238dea609bf14359c4f621bd8d86be94641646661a9dec'
readonly SOURCE_FILE_COUNT='67'
readonly EXPECTED_RETRIEVAL_PROFILE_ID='ba4bac60b3f09f6be89db148d1df883748a2003f35a1cecfb6c74f53be74b865'
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
    *) printf 'script_122_complete_api=blocked;reason=argument_invalid\n' >&2; exit 2 ;;
  esac
done
[[ "$run_mode" != "$validate_mode" ]] || {
  printf 'script_122_complete_api=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in awk bash chmod cp curl date env find grep head hostname install kill mkdir mktemp mv pg_isready python3 rm sed seq sha256sum sleep sort ss stat tail tee tr uname wc; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_122_complete_api=blocked;reason=local_command_missing;command=%s\n' "$required" >&2
    exit 2
  }
done

check_file() {
  [[ -f "$1" && ! -L "$1" && -r "$1" ]] || {
    printf 'script_122_complete_api=blocked;reason=%s_unsafe\n' "$3" >&2
    exit 2
  }
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_122_complete_api=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}

check_file "$EVALUATOR" "$EVALUATOR_SHA256" evaluator
check_file "$CONTRACT_HELPER" "$CONTRACT_HELPER_SHA256" contract_helper
check_file "$CASES" "$CASES_SHA256" case_set
check_file "$DECISIONS" "$DECISIONS_SHA256" tuning_decisions
[[ -f "$SERVICE_ENTRYPOINT" && ! -L "$SERVICE_ENTRYPOINT" && -r "$SERVICE_ENTRYPOINT" ]] || {
  printf 'script_122_complete_api=blocked;reason=service_entrypoint_unsafe\n' >&2
  exit 2
}
check_file "$SCRIPT_120_REPORT" "$SCRIPT_120_REPORT_SHA256" script_120_report
check_file "$SCRIPT_121_REPORT" "$SCRIPT_121_REPORT_SHA256" script_121_report
check_file "$SCRIPT_121_ARTIFACT" "$SCRIPT_121_ARTIFACT_SHA256" script_121_artifact
check_file "$SCRIPT_121_CHECKSUM" "$SCRIPT_121_CHECKSUM_SHA256" script_121_checksum
check_file "$SCRIPT_123_SOURCE" "$SCRIPT_123_SOURCE_SHA256" script_123_source
check_file "$SCRIPT_123_REPORT" "$SCRIPT_123_REPORT_SHA256" script_123_report
(
  cd -- "$(dirname -- "$SCRIPT_121_ARTIFACT")"
  sha256sum -c "$(basename -- "$SCRIPT_121_CHECKSUM")" >/dev/null
) || {
  printf 'script_122_complete_api=blocked;reason=script_121_checksum_invalid\n' >&2
  exit 2
}

for fact in \
  'milestone=t09_contract;state=pass;retrieval_profile_id=ba4bac60b3f09f6be89db148d1df883748a2003f35a1cecfb6c74f53be74b865' \
  'milestone=native_tests;state=pass;tests=371;failures=0;errors=0' \
  'script_120_t09_implementation=pass;'; do
  grep -Fq "$fact" "$SCRIPT_120_REPORT" || {
    printf 'script_122_complete_api=blocked;reason=script_120_contract_invalid\n' >&2
    exit 2
  }
done
for fact in \
  '[SUMMARY] mrr_at_20=0.916667;responsive_top_five=6/6;required_evidence_at_20=13/13' \
  '[SUMMARY] ranking_gate=pass;nonresponsive_acceptance_measured=false;broad_navigation=clarification-required' \
  'script_121_t09_live_ranking=pass;ranking_gate=pass;'; do
  grep -Fq "$fact" "$SCRIPT_121_REPORT" || {
    printf 'script_122_complete_api=blocked;reason=script_121_contract_invalid\n' >&2
    exit 2
  }
done
grep -Eq '^\| `T09` \|.*\| FROZEN \|$' "$DECISIONS" || {
  printf 'script_122_complete_api=blocked;reason=t09_not_frozen\n' >&2
  exit 2
}
for fact in \
  '[RETRY] milestone=t10_contract;state=pass;maximum_generation_attempts=2;non_generation_retry=false;second_failure=temporarily-unavailable;retry_evidence=content_free' \
  '[REGRESSION] milestone=native_tests;state=pass;tests=376;failures=0;errors=0' \
  'script_123_t10_implementation=pass;next_gate=rerun_script_122_complete_api;'; do
  grep -Fq "$fact" "$SCRIPT_123_REPORT" || {
    printf 'script_122_complete_api=blocked;reason=script_123_contract_invalid\n' >&2
    exit 2
  }
done
grep -Eq '^\| `T10` \|.*\| FROZEN \|$' "$DECISIONS" || {
  printf 'script_122_complete_api=blocked;reason=t10_not_frozen\n' >&2
  exit 2
}

mapfile -t python_sources < <(find "$PACKAGE_ROOT" -maxdepth 1 -type f -name '*.py' -print | sort)
mapfile -t configuration_sources < <(find "$CONFIG_ROOT" -maxdepth 1 -type f -name '*.yaml' -print | sort)
(( ${#python_sources[@]} == 48 && ${#configuration_sources[@]} == 18 )) || {
  printf 'script_122_complete_api=blocked;reason=source_inventory_count_invalid\n' >&2
  exit 2
}
for source in "${python_sources[@]}" "${configuration_sources[@]}"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'script_122_complete_api=blocked;reason=source_inventory_unsafe\n' >&2
    exit 2
  }
done

umask 077
work_root="$(mktemp -d /tmp/ishikawa-script-122.XXXXXX)"
preflight_cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  [[ "$work_root" == /tmp/ishikawa-script-122.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  exit "$status"
}
trap preflight_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
source_manifest="$work_root/source.sha256"
for source in "${python_sources[@]}" "${configuration_sources[@]}" "$SERVICE_ENTRYPOINT"; do
  printf '%s  %s\n' \
    "$(sha256sum "$source" | awk '{print $1}')" \
    "${source#"$PRODUCT_ROOT"/}"
done >"$source_manifest"
[[ "$(wc -l <"$source_manifest" | tr -d ' ')" == "$SOURCE_FILE_COUNT" ]] || {
  printf 'script_122_complete_api=blocked;reason=source_manifest_count_invalid\n' >&2
  exit 2
}
[[ "$(sha256sum "$source_manifest" | awk '{print $1}')" == "$SOURCE_MANIFEST_SHA256" ]] || {
  printf 'script_122_complete_api=blocked;reason=source_manifest_identity_changed\n' >&2
  exit 2
}

bash -n "${BASH_SOURCE[0]}"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$EVALUATOR" "$CONTRACT_HELPER" "${python_sources[@]}"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" \
  --self-test \
  --contract-helper "$CONTRACT_HELPER" \
  | grep -Fxq 'local_retrieval_api_acceptance_self_test=pass' || {
    printf 'script_122_complete_api=blocked;reason=evaluator_self_test_failed\n' >&2
    exit 2
  }
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" \
  --validate-cases \
  --contract-helper "$CONTRACT_HELPER" \
  --cases "$CASES" \
  | grep -Fxq 'retrieval_api_case_set=pass;schema_version=2;cases=13;responsive=6;nonresponsive=6;broad_navigation=1;required_evidence=13' || {
    printf 'script_122_complete_api=blocked;reason=case_set_validation_failed\n' >&2
    exit 2
  }

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_mode" == true ]]; then
  printf '%s\n' \
    'purpose=validate_complete_local_retrieval_api_qualification' \
    "script_sha256=$script_sha256;evaluator_sha256=$EVALUATOR_SHA256;contract_helper_sha256=$CONTRACT_HELPER_SHA256" \
    "case_set_sha256=$CASES_SHA256;decision_list_sha256=$DECISIONS_SHA256;source_manifest_sha256=$SOURCE_MANIFEST_SHA256;source_files=$SOURCE_FILE_COUNT" \
    "script_120_report_sha256=$SCRIPT_120_REPORT_SHA256;script_121_report_sha256=$SCRIPT_121_REPORT_SHA256;script_121_artifact_sha256=$SCRIPT_121_ARTIFACT_SHA256" \
    "script_123_source_sha256=$SCRIPT_123_SOURCE_SHA256;script_123_report_sha256=$SCRIPT_123_REPORT_SHA256;t10_retry_contract=pass" \
    "retrieval_profile_id=$EXPECTED_RETRIEVAL_PROFILE_ID;cases=13;responsive=6;nonresponsive=6;broad_navigation=1" \
    'evaluator_self_test=pass;case_set_validation=pass;database_contact=false;model_contact=false;credential_read=false;listener_started=false' \
    'script_122_complete_api_source=pass'
  exit 0
fi

trap - EXIT INT TERM
gemma_key=''
nomic_key=''
database_password=''
service_pid=''
evaluator_pid=''
report_path=''

cleanup() {
  local status="$?"
  trap - EXIT INT TERM ERR
  gemma_key=''
  nomic_key=''
  database_password=''
  unset gemma_key nomic_key database_password ISHIKAWA_GEMMA_API_KEY ISHIKAWA_NOMIC_API_KEY ISHIKAWA_POSTGRESQL_PASSWORD
  if [[ "$evaluator_pid" =~ ^[0-9]+$ ]] && kill -0 "$evaluator_pid" 2>/dev/null; then
    kill -TERM "$evaluator_pid" 2>/dev/null || true
    wait "$evaluator_pid" 2>/dev/null || true
  fi
  if [[ "$service_pid" =~ ^[0-9]+$ ]] && kill -0 "$service_pid" 2>/dev/null; then
    kill -TERM "$service_pid" 2>/dev/null || true
    wait "$service_pid" 2>/dev/null || true
  fi
  [[ "$work_root" == /tmp/ishikawa-script-122.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  [[ -z "$report_path" ]] || chmod 0600 "$report_path" 2>/dev/null || true
  exit "$status"
}
trap cleanup EXIT

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" && -d "$ARTIFACT_ROOT" && ! -L "$ARTIFACT_ROOT" ]] || {
  printf 'script_122_complete_api=blocked;reason=output_directory_unsafe\n' >&2
  exit 1
}
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/complete_api_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
block() {
  emit "script_122_complete_api=blocked;reason=$1;local_report=$report_path"
  exit 1
}
unexpected_failure() {
  local status="$?"
  trap - ERR
  emit "script_122_complete_api=blocked;reason=unexpected_shell_failure;exit_code=$status;local_report=$report_path"
  exit "$status"
}
trap unexpected_failure ERR
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

emit 'purpose=qualify_complete_local_ishikawa_v1_1_retrieval_api'
emit "started_utc=$timestamp;script_sha256=$script_sha256;source_manifest_sha256=$SOURCE_MANIFEST_SHA256;source_files=$SOURCE_FILE_COUNT"
emit "script_120_report_sha256=$SCRIPT_120_REPORT_SHA256;script_121_report_sha256=$SCRIPT_121_REPORT_SHA256;script_121_artifact_sha256=$SCRIPT_121_ARTIFACT_SHA256"
emit "script_123_source_sha256=$SCRIPT_123_SOURCE_SHA256;script_123_report_sha256=$SCRIPT_123_REPORT_SHA256;t10_retry_contract=pass"
emit "retrieval_profile_id=$EXPECTED_RETRIEVAL_PROFILE_ID;endpoint=$API_ENDPOINT"
emit '[READINESS] milestone=local_dependencies;state=start'

actual_hostname="$(hostname -s)"
actual_os_id="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"' | head -n 1)"
actual_os_version="$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"' | head -n 1)"
actual_architecture="$(uname -m)"
[[ "$actual_hostname" == "$EXPECTED_HOSTNAME" \
    && "$actual_os_id" == ubuntu \
    && "$actual_os_version" == "$EXPECTED_OS_VERSION" \
    && "$actual_architecture" == "$EXPECTED_ARCHITECTURE" ]] \
  || block local_host_identity_mismatch
if ss -H -ltn '( sport = :1384 )' | grep -q .; then
  block port_1384_in_use
fi
postgresql_ready=false
pg_isready -q -h 127.0.0.1 -p 5432 -d rag_catalog -t 5 && postgresql_ready=true
gemma_status="$(curl --silent --output /dev/null --write-out '%{http_code}' --connect-timeout 5 --max-time 10 "$GEMMA_HEALTH_URL" 2>/dev/null)" || gemma_status=000
nomic_status="$(curl --silent --output /dev/null --write-out '%{http_code}' --connect-timeout 5 --max-time 10 "$NOMIC_HEALTH_URL" 2>/dev/null)" || nomic_status=000
emit "[READINESS] milestone=local_dependencies;state=observed;postgresql_ready=$postgresql_ready;gemma_http_status=$gemma_status;nomic_http_status=$nomic_status;port_1384_available=true"
[[ "$postgresql_ready" == true ]] || block local_postgresql_unavailable
[[ "$gemma_status" == 200 ]] || block gemma_health_unavailable
[[ "$nomic_status" == 200 ]] || block nomic_health_unavailable
emit '[READINESS] milestone=local_dependencies;state=pass'

read_secret 'Gemma API key' gemma_key
read_secret 'Nomic API key' nomic_key
read_secret 'rag_retrieval PostgreSQL password' database_password

installed_root="$work_root/Ishikawa"
install -d -m 0755 -- \
  "$installed_root/application/python/ishikawa" \
  "$installed_root/config" \
  "$installed_root/scripts"
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

emit '[SERVICE] milestone=temporary_retrieval_api;state=start'
service_output="$work_root/service.stdout"
service_error="$work_root/service.stderr"
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
readiness_started_epoch="$(date +%s)"
readiness_next_heartbeat=$(( readiness_started_epoch + 30 ))
for _attempt in $(seq 1 60); do
  if ! kill -0 "$service_pid" 2>/dev/null; then
    break
  fi
  ready_status="$(curl --silent --output /dev/null --write-out '%{http_code}' --connect-timeout 1 --max-time 5 http://127.0.0.1:1384/ready 2>/dev/null)" || ready_status=000
  if [[ "$ready_status" == 200 ]]; then
    ready=true
    break
  fi
  readiness_current_epoch="$(date +%s)"
  if (( readiness_current_epoch >= readiness_next_heartbeat )); then
    emit "[SERVICE] milestone=temporary_retrieval_api;state=starting;elapsed_seconds=$(( readiness_current_epoch - readiness_started_epoch ))"
    readiness_next_heartbeat=$(( readiness_current_epoch + 30 ))
  fi
  sleep 1
done
[[ "$ready" == true ]] || {
  emit "[SERVICE] milestone=temporary_retrieval_api;state=blocked;stdout_sha256=$(sha256sum "$service_output" | awk '{print $1}');stderr_sha256=$(sha256sum "$service_error" | awk '{print $1}');raw_output_retained=false"
  block temporary_service_not_ready
}
emit '[SERVICE] milestone=temporary_retrieval_api;state=pass;readiness=ready'

evaluator_output="$work_root/evaluator.stdout"
evaluator_error="$work_root/evaluator.stderr"
artifact_candidate="$work_root/complete-api.json"
emit '[API] milestone=complete_case_set;state=start;cases=13;responsive=6;nonresponsive=6;broad_navigation=1'
evaluation_started_epoch="$(date +%s)"
PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 python3 -B "$EVALUATOR" \
  --run \
  --contract-helper "$CONTRACT_HELPER" \
  --endpoint "$API_ENDPOINT" \
  --cases "$CASES" \
  --output "$artifact_candidate" \
  --expected-hostname "$EXPECTED_HOSTNAME" \
  --expected-os-version "$EXPECTED_OS_VERSION" \
  --expected-architecture "$EXPECTED_ARCHITECTURE" \
  >"$evaluator_output" 2>"$evaluator_error" &
evaluator_pid="$!"
reported_lines=0
next_heartbeat_epoch=$(( evaluation_started_epoch + 30 ))
while kill -0 "$evaluator_pid" 2>/dev/null; do
  current_lines="$(wc -l <"$evaluator_output" | tr -d ' ')"
  if (( current_lines > reported_lines )); then
    sed -n "$(( reported_lines + 1 )),${current_lines}p" "$evaluator_output" \
      | while IFS= read -r safe_line; do
          if [[ "$safe_line" =~ ^case_(start|result)=[A-Z0-9-]+($|\;) ]]; then
            emit "[API] $safe_line"
          fi
        done
    reported_lines="$current_lines"
  fi
  current_epoch="$(date +%s)"
  if (( current_epoch >= next_heartbeat_epoch )); then
    emit "[API] milestone=complete_case_set;state=running;elapsed_seconds=$(( current_epoch - evaluation_started_epoch ))"
    next_heartbeat_epoch=$(( current_epoch + 30 ))
  fi
  sleep 5
done
if wait "$evaluator_pid"; then
  evaluator_status=0
else
  evaluator_status=$?
fi
evaluator_pid=''
current_lines="$(wc -l <"$evaluator_output" | tr -d ' ')"
if (( current_lines > reported_lines )); then
  sed -n "$(( reported_lines + 1 )),${current_lines}p" "$evaluator_output" \
    | while IFS= read -r safe_line; do
        if [[ "$safe_line" =~ ^case_(start|result)=[A-Z0-9-]+($|\;) ]]; then
          emit "[API] $safe_line"
        fi
      done
fi
if (( evaluator_status != 0 )); then
  evaluator_reason="$(sed -nE 's/^local_retrieval_api_acceptance=blocked;reason=([A-Za-z0-9_]+)$/\1/p' "$evaluator_output" | tail -n 1)"
  [[ -n "$evaluator_reason" ]] || evaluator_reason=unclassified_evaluator_failure
  emit "[API] milestone=complete_case_set;state=blocked;reason=$evaluator_reason;stdout_sha256=$(sha256sum "$evaluator_output" | awk '{print $1}');stderr_sha256=$(sha256sum "$evaluator_error" | awk '{print $1}');raw_output_retained=false"
  block evaluator_failed
fi
grep -Fxq 'local_retrieval_api_acceptance=pass' "$evaluator_output" || block evaluator_pass_marker_absent
emit "[API] milestone=complete_case_set;state=pass;elapsed_seconds=$(( $(date +%s) - evaluation_started_epoch ))"

kill -TERM "$service_pid"
set +e
wait "$service_pid"
service_exit=$?
set -e
service_pid=''
(( service_exit == 0 )) || block temporary_service_exit_failed
for _attempt in $(seq 1 50); do
  if ! ss -H -ltn '( sport = :1384 )' | grep -q .; then
    break
  fi
  sleep 0.1
done
if ss -H -ltn '( sport = :1384 )' | grep -q .; then
  block temporary_service_listener_cleanup_failed
fi
[[ ! -e "$installed_root/state/run/logging-control.sock" ]] || block temporary_service_socket_cleanup_failed
grep -Fq 'ishikawa_retrieval_api=stopped;cleanup=complete' "$service_output" || block temporary_service_stop_marker_absent
emit '[SERVICE] milestone=temporary_retrieval_api;state=stopped;cleanup=complete'

artifact_validation="$work_root/artifact-validation.txt"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" \
  --validate-artifact \
  --contract-helper "$CONTRACT_HELPER" \
  --artifact "$artifact_candidate" >"$artifact_validation" \
  || block artifact_validation_failed
grep -Eq '^retrieval_api_artifact=pass;cases=13;contract_valid=13;expected_status_matches=[0-9]+;required_evidence=13;required_evidence_returned=[0-9]+;required_evidence_cited=[0-9]+;maximum_elapsed_milliseconds=[0-9]+;total_elapsed_milliseconds=[0-9]+$' "$artifact_validation" \
  || block artifact_validation_marker_invalid

summary_line="$(grep -E '^retrieval_api_acceptance=pass;cases=13;contract_valid=13;expected_status_matches=[0-9]+;required_evidence=13;required_evidence_returned=[0-9]+;required_evidence_cited=[0-9]+;maximum_elapsed_milliseconds=[0-9]+;total_elapsed_milliseconds=[0-9]+$' "$evaluator_output")" \
  || block evaluator_summary_invalid
gate_line="$(grep -E '^full_api_gate=(pass|not_met);responsive_answered=[0-9]+/6;nonresponsive_abstained=[0-9]+/6;broad_clarification=[0-9]+/1;dependency_failures=[0-9]+$' "$evaluator_output")" \
  || block evaluator_gate_invalid
full_api_gate="$(sed -nE 's/^full_api_gate=(pass|not_met);.*/\1/p' <<<"$gate_line")"

artifact_sha256="$(sha256sum "$artifact_candidate" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$artifact_candidate")"
artifact_path="$ARTIFACT_ROOT/complete_api_${artifact_sha256}.json"
checksum_path="$artifact_path.sha256"
artifact_reused=false
if [[ -e "$artifact_path" || -L "$artifact_path" || -e "$checksum_path" || -L "$checksum_path" ]]; then
  [[ -f "$artifact_path" && ! -L "$artifact_path" && -f "$checksum_path" && ! -L "$checksum_path" ]] \
    || block retained_artifact_path_unsafe
  (cd -- "$ARTIFACT_ROOT" && sha256sum -c "$(basename -- "$checksum_path")" >/dev/null) \
    || block retained_artifact_checksum_invalid
  [[ "$(sha256sum "$artifact_path" | awk '{print $1}')" == "$artifact_sha256" ]] \
    || block retained_artifact_identity_collision
  rm -f -- "$artifact_candidate"
  artifact_reused=true
else
  mv -- "$artifact_candidate" "$artifact_path"
  printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
fi
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true

if [[ "$full_api_gate" == pass ]]; then
  next_gate='assemble_and_qualify_final_v1_1_package'
else
  next_gate='review_complete_api_case_results_before_further_change'
fi
emit "[SUMMARY] $summary_line"
emit "[SUMMARY] $gate_line"
emit '[SUMMARY] database_write=false;temporary_service_stopped=true;configuration_changed=false;package_built=false;credentials_retained=false'
emit "[SUMMARY] accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$artifact_bytes;artifact_reused=$artifact_reused;checksum=$checksum_path;cleanup=complete"
emit "script_122_complete_api=pass;full_api_gate=$full_api_gate;next_gate=$next_gate;local_report=$report_path"
