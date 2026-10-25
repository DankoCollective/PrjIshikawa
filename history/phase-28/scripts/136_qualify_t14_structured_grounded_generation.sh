#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify frozen T14 schema-constrained grounded generation before the
#   complete Ishikawa v1.2 Retrieval API gate is rerun.
#
# Mental model:
#   Bind the Script 135 response-validation evidence and exact T14 source, run
#   every native test, stage one temporary loopback Retrieval API, and submit
#   R-006 five times. Every request must answer with its required citation and
#   no generation retry or dependency failure.
#
# Inputs or prerequisites:
#   Local PostgreSQL, forwarded Gemma on 127.0.0.1:8000, forwarded Nomic on
#   127.0.0.1:8001, and the three runtime credentials.
#
# Outputs:
#   One content-free report and reliability artifact. No question, answer,
#   prompt, excerpt, model response, vector, credential, or exception text is
#   retained. No database, accepted release, or package is changed.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/136_qualify_t14_structured_grounded_generation.sh --run

usage() {
  sed -n '3,29p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run            Run native regression and five live R-006 probes.' \
    '  --validate-only  Validate bound inputs and run native tests only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PACKAGE_ROOT="$PRODUCT_ROOT/application/python/ishikawa"
readonly CONFIG_ROOT="$PRODUCT_ROOT/config/templates"
readonly TEST_ROOT="$PRODUCT_ROOT/tests"
readonly TEST_RUNNER="$PRODUCT_ROOT/scripts/run-local-validation-tests.sh"
readonly SERVICE_ENTRYPOINT="$PRODUCT_ROOT/scripts/ishikawa-retrieval-api"
readonly GENERATION_SOURCE="$PACKAGE_ROOT/generation.py"
readonly GENERATION_TEST="$TEST_ROOT/test_generation.py"
readonly DIAGNOSTIC="$SCRIPT_DIR/diagnose_t10_generation_reliability.py"
readonly HOOK_DIR="$SCRIPT_DIR/generation_failure_diagnostic_hook"
readonly HOOK="$HOOK_DIR/sitecustomize.py"
readonly CLASSIFIER="$SCRIPT_DIR/classify_generation_failure_reasons.py"
readonly CONTRACT_HELPER="$SCRIPT_DIR/capture-ishikawa-retrieval-baseline.py"
readonly CASES="$PHASE_ROOT/reference/ishikawa-retrieval-tuning-cases-v1.1.json"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_1_TUNING_DECISIONS.md"
readonly SCRIPT_135="$SCRIPT_DIR/135_classify_v1_2_generation_failures.sh"
readonly SCRIPT_135_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.2-generation-failure-reasons/generation_failure_reasons_20261021T212559Z_hFk7Xh.txt"
readonly SCRIPT_135_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/v1.2-generation-failure-reasons/generation_failure_reasons_20261021T212559Z.json"
readonly SCRIPT_135_CHECKSUM="$SCRIPT_135_ARTIFACT.sha256"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.2-t14-structured-generation"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v1.2-t14-structured-generation"

readonly DECISIONS_SHA256='0e52824e85656967659a875989529bffa9b43de53436259d1cee1d47d5aa4a29'
readonly GENERATION_SOURCE_SHA256='b72aa72b9c89c5f8aea1efe3ce6e6d47d63aa395efd70223f4737abdae10d11f'
readonly GENERATION_TEST_SHA256='b2435366b50f13cad99f086b1d3126dbe943747dbf259787cadff04f92d82344'
readonly TEST_RUNNER_SHA256='092b2cb8e5254d1ca2b6e71a496bf76743004134848e249d5d7b9f37d9d62eb7'
readonly DIAGNOSTIC_SHA256='160a3bb0eeae856cdba8cce1467995ac8ce4d18e91e2de1b816405b0024da4f1'
readonly HOOK_SHA256='09a264c3ea55519ef67a97c96630c43f9a62046fb4cace77b8a55a493dd9d29f'
readonly CLASSIFIER_SHA256='e8e38ae31eb7cdbe1fbc34a95d51dedf0f2a5c1fe6fd85223e51eada04d1e4ba'
readonly CONTRACT_HELPER_SHA256='74ad3f7259d1bffa395ac52c2356dae83a708d98ecb7518b7cff2ca0c5d165de'
readonly CASES_SHA256='feb2303d8433461846974015078d88ca42593636c399fc90fcd9c2e67beab6f9'
readonly SCRIPT_135_SHA256='7853a9a6d06f106f2568f131e5ae363b627f6a216cfdc1fbaeb6b28d6a31e0c6'
readonly SCRIPT_135_REPORT_SHA256='721b3c5450a4c93014542ed907864b25a41dc3b6ac91a5ddf8aa2f0a224212ac'
readonly SCRIPT_135_ARTIFACT_SHA256='ba7f65156bcc4aaba246aa3d4fe4882473fae46c82dc6badb260dd3fc0f966d7'
readonly SCRIPT_135_CHECKSUM_SHA256='c3689cd515f4e67379f202363f01292aea70e370f77a9ff302741c1fdf7c246a'
readonly SOURCE_MANIFEST_SHA256='324aff3117ba823a5e1e52f33060d89d27c90441d3b1e080ea0cda28b3b67556'
readonly SOURCE_FILE_COUNT='67'
readonly EXPECTED_TEST_COUNT='381'
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
    *) printf 'script_136_t14_structured_generation=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_mode" != "$validate_mode" ]] || {
  printf 'script_136_t14_structured_generation=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in awk bash basename chmod curl date env find grep head hostname install kill mkdir mktemp mv pg_isready python3 rm sed seq sha256sum sleep sort ss stat tail tee tr uname wc; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_136_t14_structured_generation=blocked;reason=local_command_missing;command=%s\n' "$required" >&2
    exit 2
  }
done

check_file() {
  [[ -f "$1" && ! -L "$1" && -r "$1" ]] || {
    printf 'script_136_t14_structured_generation=blocked;reason=%s_unsafe\n' "$3" >&2
    exit 2
  }
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_136_t14_structured_generation=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}

check_file "$DECISIONS" "$DECISIONS_SHA256" tuning_decisions
check_file "$GENERATION_SOURCE" "$GENERATION_SOURCE_SHA256" generation_source
check_file "$GENERATION_TEST" "$GENERATION_TEST_SHA256" generation_test
check_file "$TEST_RUNNER" "$TEST_RUNNER_SHA256" test_runner
check_file "$DIAGNOSTIC" "$DIAGNOSTIC_SHA256" diagnostic
check_file "$HOOK" "$HOOK_SHA256" diagnostic_hook
check_file "$CLASSIFIER" "$CLASSIFIER_SHA256" failure_classifier
check_file "$CONTRACT_HELPER" "$CONTRACT_HELPER_SHA256" contract_helper
check_file "$CASES" "$CASES_SHA256" case_set
check_file "$SCRIPT_135" "$SCRIPT_135_SHA256" script_135
check_file "$SCRIPT_135_REPORT" "$SCRIPT_135_REPORT_SHA256" script_135_report
check_file "$SCRIPT_135_ARTIFACT" "$SCRIPT_135_ARTIFACT_SHA256" script_135_artifact
check_file "$SCRIPT_135_CHECKSUM" "$SCRIPT_135_CHECKSUM_SHA256" script_135_checksum
check_file "$SERVICE_ENTRYPOINT" "$(sha256sum "$SERVICE_ENTRYPOINT" | awk '{print $1}')" service_entrypoint

(
  cd -- "$(dirname -- "$SCRIPT_135_CHECKSUM")"
  sha256sum --check --strict "$(basename -- "$SCRIPT_135_CHECKSUM")" >/dev/null
) || {
  printf 'script_136_t14_structured_generation=blocked;reason=script_135_checksum_invalid\n' >&2
  exit 2
}
for fact in \
  'attempt_failures=8;transport=0;response_validation=8;unclassified=0' \
  'failure_reason=MODEL_OUTPUT_JSON_INVALID;count=1' \
  'failure_reason=MODEL_OUTPUT_SCHEMA_INVALID;count=7' \
  'failure_interpretation=response_validation_failure_observed;raw_content_retained=false' \
  'script_135_generation_failure_classification=pass;'; do
  grep -Fq "$fact" "$SCRIPT_135_REPORT" || {
    printf 'script_136_t14_structured_generation=blocked;reason=script_135_evidence_invalid\n' >&2
    exit 2
  }
done
for decision in T10 T12 T13 T14; do
  grep -Eq "^\\| \`$decision\` \\|.*\\| FROZEN \\|$" "$DECISIONS" || {
    printf 'script_136_t14_structured_generation=blocked;reason=%s_not_frozen\n' "${decision,,}" >&2
    exit 2
  }
done
grep -Fq '"response_format": _grounded_response_format(citation_ids)' "$GENERATION_SOURCE" || {
  printf 'script_136_t14_structured_generation=blocked;reason=response_format_not_bound\n' >&2
  exit 2
}
grep -Fq '"strict": True' "$GENERATION_SOURCE" || {
  printf 'script_136_t14_structured_generation=blocked;reason=strict_json_schema_not_bound\n' >&2
  exit 2
}

mapfile -t python_sources < <(find "$PACKAGE_ROOT" -maxdepth 1 -type f -name '*.py' -print | sort)
mapfile -t configuration_sources < <(find "$CONFIG_ROOT" -maxdepth 1 -type f -name '*.yaml' -print | sort)
(( ${#python_sources[@]} == 48 && ${#configuration_sources[@]} == 18 )) || {
  printf 'script_136_t14_structured_generation=blocked;reason=source_inventory_count_invalid\n' >&2
  exit 2
}
for source in "${python_sources[@]}" "${configuration_sources[@]}" "$SERVICE_ENTRYPOINT"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'script_136_t14_structured_generation=blocked;reason=source_inventory_unsafe\n' >&2
    exit 2
  }
done

umask 077
work_root="$(mktemp -d /tmp/ishikawa-script-136.XXXXXX)"
report_path=''
artifact_path=''
checksum_path=''
artifact_created=false
artifact_committed=false
gemma_key=''
nomic_key=''
database_password=''
service_pid=''
diagnostic_pid=''

cleanup() {
  local status="$?"
  trap - EXIT INT TERM ERR
  gemma_key=''
  nomic_key=''
  database_password=''
  unset gemma_key nomic_key database_password ISHIKAWA_GEMMA_API_KEY ISHIKAWA_NOMIC_API_KEY ISHIKAWA_POSTGRESQL_PASSWORD
  unset ISHIKAWA_DIAGNOSTIC_FAILURE_LOG PYTHONPATH
  if [[ "$diagnostic_pid" =~ ^[0-9]+$ ]] && kill -0 "$diagnostic_pid" 2>/dev/null; then
    kill -TERM "$diagnostic_pid" 2>/dev/null || true
    wait "$diagnostic_pid" 2>/dev/null || true
  fi
  if [[ "$service_pid" =~ ^[0-9]+$ ]] && kill -0 "$service_pid" 2>/dev/null; then
    kill -TERM "$service_pid" 2>/dev/null || true
    wait "$service_pid" 2>/dev/null || true
  fi
  if [[ "$artifact_created" == true && "$artifact_committed" != true ]]; then
    [[ "$artifact_path" == "$ARTIFACT_ROOT"/r006_structured_generation_*.json ]] && rm -f -- "$artifact_path"
    [[ "$checksum_path" == "$ARTIFACT_ROOT"/r006_structured_generation_*.json.sha256 ]] && rm -f -- "$checksum_path"
  fi
  [[ "$work_root" == /tmp/ishikawa-script-136.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  [[ -z "$report_path" ]] || chmod 0600 "$report_path" 2>/dev/null || true
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

source_manifest="$work_root/source.sha256"
for source in "${python_sources[@]}" "${configuration_sources[@]}" "$SERVICE_ENTRYPOINT"; do
  printf '%s  %s\n' "$(sha256sum "$source" | awk '{print $1}')" "${source#"$PRODUCT_ROOT"/}"
done >"$source_manifest"
[[ "$(wc -l <"$source_manifest" | tr -d ' ')" == "$SOURCE_FILE_COUNT" ]] || {
  printf 'script_136_t14_structured_generation=blocked;reason=source_manifest_count_invalid\n' >&2
  exit 2
}
[[ "$(sha256sum "$source_manifest" | awk '{print $1}')" == "$SOURCE_MANIFEST_SHA256" ]] || {
  printf 'script_136_t14_structured_generation=blocked;reason=source_manifest_identity_changed\n' >&2
  exit 2
}

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$DIAGNOSTIC" "$HOOK" "$CLASSIFIER" "$CONTRACT_HELPER" "$GENERATION_TEST" "${python_sources[@]}"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$DIAGNOSTIC" --self-test \
  | grep -Fxq 't10_generation_reliability_diagnostic_self_test=pass' || {
    printf 'script_136_t14_structured_generation=blocked;reason=diagnostic_self_test_failed\n' >&2
    exit 2
  }
PYTHONDONTWRITEBYTECODE=1 python3 -B "$CLASSIFIER" --self-test \
  | grep -Fxq 'generation_failure_reason_classifier_self_test=pass' || {
    printf 'script_136_t14_structured_generation=blocked;reason=classifier_self_test_failed\n' >&2
    exit 2
  }

test_output="$work_root/native-tests.txt"
if PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_output" 2>&1; then
  test_status=0
else
  test_status=$?
fi
(( test_status == 0 )) || {
  printf 'script_136_t14_structured_generation=blocked;reason=native_test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s;raw_output_retained=false\n' \
    "$(sha256sum "$test_output" | awk '{print $1}')" "$(stat -c '%s' "$test_output")" >&2
  exit 1
}
grep -Fq "Ran $EXPECTED_TEST_COUNT tests" "$test_output" || {
  printf 'script_136_t14_structured_generation=blocked;reason=native_test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_output" || {
  printf 'script_136_t14_structured_generation=blocked;reason=native_test_pass_marker_absent\n' >&2
  exit 1
}

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_mode" == true ]]; then
  printf '%s\n' \
    'purpose=validate_frozen_t14_structured_grounded_generation' \
    "script_sha256=$script_sha256;decision_list_sha256=$DECISIONS_SHA256;source_manifest_sha256=$SOURCE_MANIFEST_SHA256" \
    "script_135_report_sha256=$SCRIPT_135_REPORT_SHA256;script_135_artifact_sha256=$SCRIPT_135_ARTIFACT_SHA256" \
    "native_tests=$EXPECTED_TEST_COUNT;failures=0;errors=0" \
    'response_format=json_schema;strict=true;citation_allowlist=per_request;authoritative_validator=retained' \
    'maximum_generation_attempts=2;sampling_settings=unchanged;live_probe_count=5' \
    'database_contact=false;model_contact=false;credential_read=false;listener_started=false;package_built=false' \
    'script_136_t14_structured_generation_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" && -d "$ARTIFACT_ROOT" && ! -L "$ARTIFACT_ROOT" ]] || {
  printf 'script_136_t14_structured_generation=blocked;reason=output_directory_unsafe\n' >&2
  exit 1
}
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/t14_structured_generation_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
block() { emit "script_136_t14_structured_generation=blocked;reason=$1;local_report=$report_path"; exit 1; }
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

emit 'purpose=qualify_frozen_t14_structured_grounded_generation'
emit "started_utc=$timestamp;script_sha256=$script_sha256;source_manifest_sha256=$SOURCE_MANIFEST_SHA256;source_files=$SOURCE_FILE_COUNT"
emit "script_135_report_sha256=$SCRIPT_135_REPORT_SHA256;script_135_artifact_sha256=$SCRIPT_135_ARTIFACT_SHA256"
emit "milestone=native_tests;state=pass;tests=$EXPECTED_TEST_COUNT;failures=0;errors=0"
emit 'authorized_actions=start_temporary_loopback_api_submit_r006_five_times_verify_required_citation_retain_content_free_qualification'
emit 'non_actions=no_database_write_no_sampling_or_retry_change_no_package_build_no_accepted_release_change_no_raw_content_or_secret_retention'

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
failure_log="$work_root/generation-failures.jsonl"
install -m 0600 /dev/null "$failure_log"
emit 'milestone=temporary_api;state=start'
ISHIKAWA_GEMMA_API_KEY="$gemma_key" \
ISHIKAWA_NOMIC_API_KEY="$nomic_key" \
ISHIKAWA_POSTGRESQL_PASSWORD="$database_password" \
ISHIKAWA_DIAGNOSTIC_FAILURE_LOG="$failure_log" \
PYTHONPATH="$HOOK_DIR" \
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

diagnostic_candidate="$work_root/r006-structured-generation.json"
diagnostic_output="$work_root/diagnostic.stdout"
diagnostic_error="$work_root/diagnostic.stderr"
emit 'milestone=r006_structured_generation_probe;state=start;probes=5'
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
    emit "milestone=r006_structured_generation_probe;state=running;elapsed_seconds=$(( current_epoch - started_epoch ))"
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
expected_summary='probe_count=5;answered=5;temporarily_unavailable=0;generation_retried=0;generation_failed_after_retry=0;other_dependency_failures=0;internal_errors=0'
observed_summary="$(grep -E '^probe_count=5;answered=[0-5];temporarily_unavailable=[0-5];generation_retried=[0-5];generation_failed_after_retry=[0-5];other_dependency_failures=[0-5];internal_errors=[0-5]$' "$diagnostic_output" | tail -n 1)"
[[ -n "$observed_summary" ]] || block diagnostic_summary_invalid
observed_interpretation="$(grep -E '^diagnostic_interpretation=[a-z_]+;raw_content_retained=false$' "$diagnostic_output" | tail -n 1)"
[[ -n "$observed_interpretation" ]] || block diagnostic_interpretation_invalid
while IFS= read -r line; do
  [[ "$line" =~ ^probe_result= ]] && emit "$line"
done <"$diagnostic_output"
emit "$observed_summary"
emit "$observed_interpretation"

failure_classification="$work_root/generation-failure-reasons.json"
classifier_output="$work_root/classifier.stdout"
classifier_error="$work_root/classifier.stderr"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$CLASSIFIER" \
  --run \
  --probe-artifact "$diagnostic_candidate" \
  --failure-log "$failure_log" \
  --output "$failure_classification" \
  >"$classifier_output" 2>"$classifier_error" || {
    reason="$(sed -nE 's/^generation_failure_reason_classification=blocked;reason=([A-Za-z0-9_]+)$/\1/p' "$classifier_error" | tail -n 1)"
    [[ -n "$reason" ]] || reason=unclassified_classifier_failure
    block "$reason"
  }
grep -Fxq 'generation_failure_reason_classification=pass' "$classifier_output" \
  || block classifier_pass_marker_absent
while IFS= read -r line; do
  if [[ "$line" =~ ^attempt_failures= || "$line" =~ ^failure_reason= || "$line" =~ ^failure_interpretation= ]]; then
    emit "$line"
  fi
done <"$classifier_output"

grep -Fxq "$expected_summary" "$diagnostic_output" || block structured_generation_reliability_gate_not_met
grep -Fxq 'diagnostic_interpretation=no_failure_reproduced;raw_content_retained=false' "$diagnostic_output" \
  || block structured_generation_interpretation_invalid
grep -Fxq 'attempt_failures=0;transport=0;response_validation=0;unclassified=0' "$classifier_output" \
  || block structured_generation_failure_attempt_observed
grep -Fxq 'failure_interpretation=no_failure_reproduced;raw_content_retained=false' "$classifier_output" \
  || block structured_generation_failure_interpretation_invalid
[[ "$(grep -Ec '^probe_result=R-006-0[1-5];status=answered;elapsed_milliseconds=[1-9][0-9]*$' "$diagnostic_output")" == 5 ]] \
  || block answered_probe_set_invalid
emit 'milestone=r006_structured_generation_probe;state=pass;probes=5;answered=5;retries=0;dependency_failures=0'

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
grep -Fxq 't10_generation_reliability_artifact=pass;probes=5;answered=5;temporarily_unavailable=0;interpretation=no_failure_reproduced' "$artifact_validation" \
  || block artifact_validation_marker_invalid

artifact_path="$ARTIFACT_ROOT/r006_structured_generation_${timestamp}.json"
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
emit "$expected_summary"
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$artifact_bytes;checksum=$checksum_path"
emit 'database_write=false;sampling_changed=false;retry_policy_changed=false;package_built=false;accepted_v1_1_changed=false;raw_content_retained=false;credentials_retained=false'
emit "script_136_t14_structured_generation=pass;next_gate=script_137_complete_v1_2_api;local_report=$report_path"
