#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the frozen Ishikawa Retrieval API identity, separate-process
#   boundary, fail-closed gate ordering, and client-safe outcome mapping.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/63_qualify_ishikawa_retrieval_api_orchestrator.sh --run

usage() {
  sed -n '3,10p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Run locally and retain content-free qualification evidence.' \
    '  --validate-only Validate sources and behavior without retaining evidence.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$ISHIKAWA_ROOT/application/python"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly API_PROFILE="$ISHIKAWA_ROOT/config/templates/api_profile.yaml"
readonly INJECTION_PROFILE="$ISHIKAWA_ROOT/config/templates/injection_profile.yaml"
readonly SERVICE_PROFILE="$ISHIKAWA_ROOT/config/templates/retrieval_service_profile.yaml"
readonly MODULE="$PYTHON_ROOT/ishikawa/retrieval_service.py"
readonly TESTS="$ISHIKAWA_ROOT/tests/test_retrieval_service.py"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_retrieval_service_orchestrator.py"
readonly CONTRACT="$ISHIKAWA_ROOT/docs/RETRIEVAL_API_SERVICE.md"
readonly ACCEPTED_SCRIPT_62_REPORT="$REPO_ROOT/local/reports/ishikawa-api-contract/api_contract_20261020T052824Z_luiwo0.txt"
readonly ACCEPTED_SCRIPT_62_REPORT_SHA256='ca536e1b335602e1172ae4b3f595f235e6f3462e24e36498811aca07e6fc2d9c'
readonly ACCEPTED_SCRIPT_62_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/api-contract/api_contract_qualification_20261020T052824Z.json"
readonly ACCEPTED_SCRIPT_62_ARTIFACT_SHA256='2ad345604131b7bce1b8a3900e9d9864b22e86203e8758569d11d40b133df06b'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-retrieval-api-orchestrator"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/retrieval-api-orchestrator"

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
  "$TEST_RUNNER" "$API_PROFILE" "$INJECTION_PROFILE" "$SERVICE_PROFILE" \
  "$MODULE" "$TESTS" "$EVALUATOR" "$CONTRACT" \
  "$ACCEPTED_SCRIPT_62_REPORT" "$ACCEPTED_SCRIPT_62_ARTIFACT"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: a required Script 63 input is missing or unsafe.\n' >&2
    exit 2
  }
done
[[ "$(sha256sum "$ACCEPTED_SCRIPT_62_REPORT" | awk '{print $1}')" == "$ACCEPTED_SCRIPT_62_REPORT_SHA256" ]] || {
  printf 'BLOCKED: accepted Script 62 report identity changed.\n' >&2
  exit 2
}
[[ "$(sha256sum "$ACCEPTED_SCRIPT_62_ARTIFACT" | awk '{print $1}')" == "$ACCEPTED_SCRIPT_62_ARTIFACT_SHA256" ]] || {
  printf 'BLOCKED: accepted Script 62 artifact identity changed.\n' >&2
  exit 2
}
for fact in \
  'api_contract_qualification=pass' \
  'local_tests=212;failures=0;errors=0' \
  'script_62_api_contract=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_SCRIPT_62_REPORT" || {
    printf 'BLOCKED: an accepted Script 62 fact is absent.\n' >&2
    exit 2
  }
done

bash -n "$TEST_RUNNER"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$MODULE" "$TESTS" "$EVALUATOR"

work_root="$(mktemp -d /tmp/ishikawa-script-63.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-63.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  cat "$test_result" >&2
  printf 'script_63_retrieval_api_orchestrator=blocked;reason=test_regression\n' >&2
  exit 1
}
grep -Fq 'Ran 223 tests' "$test_result" || {
  printf 'script_63_retrieval_api_orchestrator=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_63_retrieval_api_orchestrator=blocked;reason=test_pass_marker_absent\n' >&2
  exit 1
}

api_profile_sha256="$(sha256sum "$API_PROFILE" | awk '{print $1}')"
injection_profile_sha256="$(sha256sum "$INJECTION_PROFILE" | awk '{print $1}')"
service_profile_sha256="$(sha256sum "$SERVICE_PROFILE" | awk '{print $1}')"
temporary_artifact="$work_root/retrieval-service-orchestrator-qualification.json"
evaluation_result="$work_root/evaluation.txt"
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B "$EVALUATOR" \
  --api-profile "$API_PROFILE" --expected-api-profile-sha256 "$api_profile_sha256" \
  --injection-profile "$INJECTION_PROFILE" --expected-injection-profile-sha256 "$injection_profile_sha256" \
  --service-profile "$SERVICE_PROFILE" --expected-service-profile-sha256 "$service_profile_sha256" \
  --output "$temporary_artifact" >"$evaluation_result"
for fact in \
  'service_name=Ishikawa Retrieval API;package_owner=Ishikawa;process_model=separate_process;lifecycle=start_on_demand' \
  'network_default=127.0.0.1:1384;allowed_client=ishikawa_nextjs_server;listener_started=false' \
  'orchestration_order=direct_injection,scope,retrieval,indirect_injection,sufficiency,generation,response' \
  'safe_errors=temporarily_unavailable,internal_error;exception_text_exposed=false' \
  'network_contact=false;database_contact=false;model_call=false;credential_read=false' \
  'retrieval_service_orchestrator_qualification=pass'; do
  grep -Fq "$fact" "$evaluation_result" || {
    cat "$evaluation_result" >&2
    printf 'script_63_retrieval_api_orchestrator=blocked;reason=orchestrator_evaluation_failed\n' >&2
    exit 1
  }
done

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
module_sha256="$(sha256sum "$MODULE" | awk '{print $1}')"
tests_sha256="$(sha256sum "$TESTS" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
contract_sha256="$(sha256sum "$CONTRACT" | awk '{print $1}')"
artifact_sha256="$(sha256sum "$temporary_artifact" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$temporary_artifact")"
if [[ "$validate_only" == true ]]; then
  cat "$evaluation_result"
  printf '%s\n' \
    'purpose=validate_ishikawa_retrieval_api_orchestrator' \
    'target_contact=false;network_access=false;database_contact=false;model_call=false;credential_read=false;listener_started=false' \
    "script_sha256=$script_sha256;module_sha256=$module_sha256;tests_sha256=$tests_sha256;evaluator_sha256=$evaluator_sha256" \
    "api_profile_sha256=$api_profile_sha256;injection_profile_sha256=$injection_profile_sha256;service_profile_sha256=$service_profile_sha256;contract_sha256=$contract_sha256" \
    "accepted_script_62_report_sha256=$ACCEPTED_SCRIPT_62_REPORT_SHA256;accepted_script_62_artifact_sha256=$ACCEPTED_SCRIPT_62_ARTIFACT_SHA256" \
    "qualification_artifact_sha256=$artifact_sha256;qualification_artifact_bytes=$artifact_bytes" \
    'local_tests=223;failures=0;errors=0' \
    'script_63_retrieval_api_orchestrator_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/retrieval_service_orchestrator_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  printf 'script_63_retrieval_api_orchestrator=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
cp -- "$temporary_artifact" "$artifact_path"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true

report_path="$(mktemp "$REPORT_ROOT/retrieval_api_orchestrator_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=qualify_ishikawa_retrieval_api_identity_and_orchestration'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;module_sha256=$module_sha256;tests_sha256=$tests_sha256;evaluator_sha256=$evaluator_sha256"
emit "api_profile_sha256=$api_profile_sha256;injection_profile_sha256=$injection_profile_sha256;service_profile_sha256=$service_profile_sha256;contract_sha256=$contract_sha256"
emit "accepted_script_62_report_sha256=$ACCEPTED_SCRIPT_62_REPORT_SHA256;accepted_script_62_artifact_sha256=$ACCEPTED_SCRIPT_62_ARTIFACT_SHA256"
emit 'authorized_actions=read_checksum_bound_local_evidence_run_local_tests_qualify_service_identity_and_orchestration_retain_content_free_acceptance_evidence'
emit 'non_actions=no_target_contact_no_network_access_no_database_contact_no_model_call_no_credential_read_no_listener_start_no_schema_change'
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$artifact_bytes"
emit "accepted_checksum=$checksum_path;raw_content_retained=false"
emit 'local_tests=223;failures=0;errors=0'
emit "script_63_retrieval_api_orchestrator=pass;local_report=$report_path;next_gate=implement_native_retrieval_adapters"
chmod 0600 "$report_path" 2>/dev/null || true

