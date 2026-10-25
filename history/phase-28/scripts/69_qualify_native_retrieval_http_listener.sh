#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the bounded native Ishikawa Retrieval API HTTP listener on its
#   default loopback address with injected local application behavior.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/69_qualify_native_retrieval_http_listener.sh --run

usage() {
  sed -n '3,10p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Run locally and retain content-free qualification evidence.' \
    '  --validate-only Validate sources and listener behavior without retaining evidence.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$ISHIKAWA_ROOT/application/python"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly API_PROFILE="$ISHIKAWA_ROOT/config/templates/api_profile.yaml"
readonly SERVICE_PROFILE="$ISHIKAWA_ROOT/config/templates/retrieval_service_profile.yaml"
readonly DEPLOYMENT_PROFILE="$ISHIKAWA_ROOT/config/templates/deployment.yaml"
readonly DEPLOYMENT_MODULE="$PYTHON_ROOT/ishikawa/deployment.py"
readonly LISTENER_MODULE="$PYTHON_ROOT/ishikawa/http_listener.py"
readonly LISTENER_TESTS="$ISHIKAWA_ROOT/tests/test_http_listener.py"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_native_retrieval_http_listener.py"
readonly CONTRACT="$ISHIKAWA_ROOT/docs/RETRIEVAL_API_SERVICE.md"
readonly ACCEPTED_SCRIPT_68_REPORT="$REPO_ROOT/local/reports/ishikawa-complete-retrieval-adapter-target/complete_retrieval_adapter_target_20261020T141141Z_0RVRGT.txt"
readonly ACCEPTED_SCRIPT_68_REPORT_SHA256='67a52cbdc7c240741d58d156938f17589032c8e1e68b64262e18a3c44f133b03'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-native-http-listener"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/native-http-listener"

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'ERROR: unsupported argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'BLOCKED: choose exactly one of --run or --validate-only.\n' >&2
  exit 2
}
for required in awk bash chmod cp date grep mkdir mktemp python3 rm sed sha256sum stat tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'BLOCKED: missing local command: %s\n' "$required" >&2
    exit 2
  }
done
for source in \
  "$TEST_RUNNER" "$API_PROFILE" "$SERVICE_PROFILE" "$DEPLOYMENT_PROFILE" \
  "$DEPLOYMENT_MODULE" "$LISTENER_MODULE" "$LISTENER_TESTS" "$EVALUATOR" \
  "$CONTRACT" "$ACCEPTED_SCRIPT_68_REPORT"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: a required Script 69 input is missing or unsafe.\n' >&2
    exit 2
  }
done
[[ "$(sha256sum "$ACCEPTED_SCRIPT_68_REPORT" | awk '{print $1}')" == "$ACCEPTED_SCRIPT_68_REPORT_SHA256" ]] || {
  printf 'BLOCKED: accepted Script 68 report identity changed.\n' >&2
  exit 2
}
for fact in \
  'adapter_scenarios=2;relationship=pass;complete_procedure=pass' \
  'retrieval_role_active_view_read=pass;retrieval_role_base_table_read=denied' \
  'temporary_database_dropped=true;accepted_database_unchanged=true' \
  'complete_retrieval_adapter_target=pass' \
  'required_fact_contract=pass;pass_markers=1;blocked_markers=0' \
  'script_68_complete_retrieval_adapter_target=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_SCRIPT_68_REPORT" || {
    printf 'BLOCKED: an accepted Script 68 fact is absent.\n' >&2
    exit 2
  }
done

bash -n "$TEST_RUNNER"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$DEPLOYMENT_MODULE" "$LISTENER_MODULE" "$LISTENER_TESTS" "$EVALUATOR"

work_root="$(mktemp -d /tmp/ishikawa-script-69.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-69.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  printf 'script_69_native_http_listener=blocked;reason=test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$test_result" | awk '{print $1}')" "$(stat -c '%s' "$test_result")" >&2
  exit 1
}
grep -Fq 'Ran 261 tests' "$test_result" || {
  printf 'script_69_native_http_listener=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_69_native_http_listener=blocked;reason=test_pass_marker_absent\n' >&2
  exit 1
}

api_profile_sha256="$(sha256sum "$API_PROFILE" | awk '{print $1}')"
service_profile_sha256="$(sha256sum "$SERVICE_PROFILE" | awk '{print $1}')"
deployment_profile_sha256="$(sha256sum "$DEPLOYMENT_PROFILE" | awk '{print $1}')"
temporary_artifact="$work_root/native-http-listener-qualification.json"
evaluation_result="$work_root/evaluation.txt"
evaluation_error="$work_root/evaluation-error.txt"
if ! PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B "$EVALUATOR" \
  --api-profile "$API_PROFILE" --api-profile-sha256 "$api_profile_sha256" \
  --service-profile "$SERVICE_PROFILE" --service-profile-sha256 "$service_profile_sha256" \
  --deployment-profile "$DEPLOYMENT_PROFILE" --deployment-profile-sha256 "$deployment_profile_sha256" \
  --output "$temporary_artifact" >"$evaluation_result" 2>"$evaluation_error"; then
  printf 'script_69_native_http_listener=blocked;reason=listener_evaluation_failed;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$evaluation_error" | awk '{print $1}')" "$(stat -c '%s' "$evaluation_error")" >&2
  exit 1
fi
for fact in \
  'listener_endpoint=127.0.0.1:1384;method=POST;path=/v1/chat;streaming=false' \
  'transport_cases=4;accepted=1;method_rejected=1;path_rejected=1;body_rejected=1' \
  'application_http_status=200;application_status=insufficient-evidence' \
  'bounds=request_bytes_262144;concurrent_requests_8;read_timeout_seconds_30' \
  'headers=content_type,content_length,no_store,nosniff,connection_close;server_disclosure=false' \
  'request_correlation=opaque_server_generated;content_free_events=4;request_content_logged=false' \
  'listener_shutdown=pass;port_1384_after_test=free' \
  'target_contact=false;database_contact=false;model_call=false;credential_read=false' \
  'native_retrieval_http_listener_qualification=pass'; do
  grep -Fqx "$fact" "$evaluation_result" || {
    printf 'script_69_native_http_listener=blocked;reason=listener_contract_mismatch\n' >&2
    exit 1
  }
done

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
deployment_module_sha256="$(sha256sum "$DEPLOYMENT_MODULE" | awk '{print $1}')"
listener_module_sha256="$(sha256sum "$LISTENER_MODULE" | awk '{print $1}')"
tests_sha256="$(sha256sum "$LISTENER_TESTS" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
contract_sha256="$(sha256sum "$CONTRACT" | awk '{print $1}')"
artifact_sha256="$(sha256sum "$temporary_artifact" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$temporary_artifact")"
if [[ "$validate_only" == true ]]; then
  cat "$evaluation_result"
  printf '%s\n' \
    'purpose=validate_native_retrieval_http_listener' \
    'target_contact=false;network_access=loopback_only;database_contact=false;model_call=false;credential_read=false' \
    "script_sha256=$script_sha256;deployment_module_sha256=$deployment_module_sha256;listener_module_sha256=$listener_module_sha256;tests_sha256=$tests_sha256;evaluator_sha256=$evaluator_sha256" \
    "api_profile_sha256=$api_profile_sha256;service_profile_sha256=$service_profile_sha256;deployment_profile_sha256=$deployment_profile_sha256;contract_sha256=$contract_sha256" \
    "accepted_script_68_report_sha256=$ACCEPTED_SCRIPT_68_REPORT_SHA256" \
    "qualification_artifact_sha256=$artifact_sha256;qualification_artifact_bytes=$artifact_bytes" \
    'local_tests=261;failures=0;errors=0' \
    'script_69_native_http_listener_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/native_http_listener_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  printf 'script_69_native_http_listener=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
cp -- "$temporary_artifact" "$artifact_path"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true

report_path="$(mktemp "$REPORT_ROOT/native_http_listener_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=qualify_native_nonstreaming_loopback_retrieval_http_listener'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;deployment_module_sha256=$deployment_module_sha256;listener_module_sha256=$listener_module_sha256;tests_sha256=$tests_sha256;evaluator_sha256=$evaluator_sha256"
emit "api_profile_sha256=$api_profile_sha256;service_profile_sha256=$service_profile_sha256;deployment_profile_sha256=$deployment_profile_sha256;contract_sha256=$contract_sha256"
emit "accepted_script_68_report_sha256=$ACCEPTED_SCRIPT_68_REPORT_SHA256"
emit 'authorized_actions=read_checksum_bound_local_evidence_run_local_tests_bind_default_loopback_listener_send_bounded_synthetic_requests_stop_listener_retain_content_free_acceptance_evidence'
emit 'non_actions=no_target_contact_no_nonloopback_network_access_no_database_contact_no_model_call_no_credential_read_no_service_install_no_schema_change'
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$artifact_bytes"
emit "accepted_checksum=$checksum_path;raw_request_content_retained=false;raw_response_content_retained=false"
emit 'local_tests=261;failures=0;errors=0'
emit "script_69_native_http_listener=pass;local_report=$report_path;next_gate=assemble_configured_retrieval_service_runtime"
chmod 0600 "$report_path" 2>/dev/null || true
