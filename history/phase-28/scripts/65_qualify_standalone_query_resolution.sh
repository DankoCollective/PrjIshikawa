#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify standalone multi-turn query resolution, trusted structured source
#   mapping, clarification short-circuiting, and retrieval-service ordering.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/65_qualify_standalone_query_resolution.sh --run

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
readonly RESOLUTION_PROFILE="$ISHIKAWA_ROOT/config/templates/query_resolution_profile.yaml"
readonly RESOLUTION_MODULE="$PYTHON_ROOT/ishikawa/query_resolution.py"
readonly TRANSPORT_MODULE="$PYTHON_ROOT/ishikawa/query_resolution_transport.py"
readonly SERVICE_MODULE="$PYTHON_ROOT/ishikawa/retrieval_service.py"
readonly RESOLUTION_TESTS="$ISHIKAWA_ROOT/tests/test_query_resolution.py"
readonly SERVICE_TESTS="$ISHIKAWA_ROOT/tests/test_retrieval_service.py"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_query_resolution.py"
readonly CONTRACT="$ISHIKAWA_ROOT/docs/QUERY_RESOLUTION.md"
readonly ACCEPTED_SCRIPT_64_REPORT="$REPO_ROOT/local/reports/ishikawa-native-dependency-adapters/native_dependency_adapters_20261020T054728Z_cIS4DH.txt"
readonly ACCEPTED_SCRIPT_64_REPORT_SHA256='1f114185de2c9789b86dbaf3ccfb06cff5c3ef1ff13055dec259a461d4ab61ed'
readonly ACCEPTED_SCRIPT_64_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/native-dependency-adapters/native_dependency_adapter_qualification_20261020T054728Z.json"
readonly ACCEPTED_SCRIPT_64_ARTIFACT_SHA256='8c7793deb4233f3c709495618dde161444d584aa88e2d035467c674accb04dec'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-query-resolution"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/query-resolution"

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
  "$RESOLUTION_PROFILE" "$RESOLUTION_MODULE" "$TRANSPORT_MODULE" \
  "$SERVICE_MODULE" "$RESOLUTION_TESTS" "$SERVICE_TESTS" "$EVALUATOR" \
  "$CONTRACT" "$ACCEPTED_SCRIPT_64_REPORT" "$ACCEPTED_SCRIPT_64_ARTIFACT"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: a required Script 65 input is missing or unsafe.\n' >&2
    exit 2
  }
done
[[ "$(sha256sum "$ACCEPTED_SCRIPT_64_REPORT" | awk '{print $1}')" == "$ACCEPTED_SCRIPT_64_REPORT_SHA256" ]] || {
  printf 'BLOCKED: accepted Script 64 report identity changed.\n' >&2
  exit 2
}
[[ "$(sha256sum "$ACCEPTED_SCRIPT_64_ARTIFACT" | awk '{print $1}')" == "$ACCEPTED_SCRIPT_64_ARTIFACT_SHA256" ]] || {
  printf 'BLOCKED: accepted Script 64 artifact identity changed.\n' >&2
  exit 2
}
for fact in \
  'native_dependency_adapter_qualification=pass' \
  'local_tests=233;failures=0;errors=0' \
  'script_64_native_dependency_adapters=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_SCRIPT_64_REPORT" || {
    printf 'BLOCKED: an accepted Script 64 fact is absent.\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$RESOLUTION_MODULE" "$TRANSPORT_MODULE" "$SERVICE_MODULE" \
  "$RESOLUTION_TESTS" "$SERVICE_TESTS" "$EVALUATOR"

work_root="$(mktemp -d /tmp/ishikawa-script-65.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-65.* && -d "$work_root" ]]; then
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
  printf 'script_65_query_resolution=blocked;reason=test_regression\n' >&2
  exit 1
}
grep -Fq 'Ran 246 tests' "$test_result" || {
  printf 'script_65_query_resolution=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_65_query_resolution=blocked;reason=test_pass_marker_absent\n' >&2
  exit 1
}

api_profile_sha256="$(sha256sum "$API_PROFILE" | awk '{print $1}')"
injection_profile_sha256="$(sha256sum "$INJECTION_PROFILE" | awk '{print $1}')"
service_profile_sha256="$(sha256sum "$SERVICE_PROFILE" | awk '{print $1}')"
resolution_profile_sha256="$(sha256sum "$RESOLUTION_PROFILE" | awk '{print $1}')"
temporary_artifact="$work_root/query-resolution-qualification.json"
evaluation_result="$work_root/evaluation.txt"
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B "$EVALUATOR" \
  --api-profile "$API_PROFILE" --expected-api-profile-sha256 "$api_profile_sha256" \
  --injection-profile "$INJECTION_PROFILE" --expected-injection-profile-sha256 "$injection_profile_sha256" \
  --service-profile "$SERVICE_PROFILE" --expected-service-profile-sha256 "$service_profile_sha256" \
  --resolution-profile "$RESOLUTION_PROFILE" --expected-resolution-profile-sha256 "$resolution_profile_sha256" \
  --output "$temporary_artifact" >"$evaluation_result"
for fact in \
  'resolution=standalone_query;original_query_preserved=true;full_transcript_embedded=false' \
  'direct_question=model_bypass;contextual_followup=one_gemma_request;retry=false' \
  'source_labels=trusted_structured_map;literal_label_embedded=false;filters=code_owned' \
  'unresolved_source=clarification;retrieval_called=false;model_called=false' \
  'orchestration_order=direct_injection,scope,query_resolution,retrieval,indirect_injection,sufficiency,generation,response' \
  'network_contact=false;database_contact=false;model_call=false;credential_read=false' \
  'query_resolution_qualification=pass'; do
  grep -Fq "$fact" "$evaluation_result" || {
    cat "$evaluation_result" >&2
    printf 'script_65_query_resolution=blocked;reason=resolution_evaluation_failed\n' >&2
    exit 1
  }
done

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
resolution_module_sha256="$(sha256sum "$RESOLUTION_MODULE" | awk '{print $1}')"
transport_module_sha256="$(sha256sum "$TRANSPORT_MODULE" | awk '{print $1}')"
service_module_sha256="$(sha256sum "$SERVICE_MODULE" | awk '{print $1}')"
resolution_tests_sha256="$(sha256sum "$RESOLUTION_TESTS" | awk '{print $1}')"
service_tests_sha256="$(sha256sum "$SERVICE_TESTS" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
contract_sha256="$(sha256sum "$CONTRACT" | awk '{print $1}')"
artifact_sha256="$(sha256sum "$temporary_artifact" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$temporary_artifact")"
if [[ "$validate_only" == true ]]; then
  cat "$evaluation_result"
  printf '%s\n' \
    'purpose=validate_standalone_query_resolution_and_service_ordering' \
    'target_contact=false;network_access=false;database_contact=false;model_call=false;credential_read=false;listener_started=false' \
    "script_sha256=$script_sha256;resolution_module_sha256=$resolution_module_sha256;transport_module_sha256=$transport_module_sha256;service_module_sha256=$service_module_sha256" \
    "resolution_tests_sha256=$resolution_tests_sha256;service_tests_sha256=$service_tests_sha256;evaluator_sha256=$evaluator_sha256;contract_sha256=$contract_sha256" \
    "api_profile_sha256=$api_profile_sha256;injection_profile_sha256=$injection_profile_sha256;service_profile_sha256=$service_profile_sha256;resolution_profile_sha256=$resolution_profile_sha256" \
    "accepted_script_64_report_sha256=$ACCEPTED_SCRIPT_64_REPORT_SHA256;accepted_script_64_artifact_sha256=$ACCEPTED_SCRIPT_64_ARTIFACT_SHA256" \
    "qualification_artifact_sha256=$artifact_sha256;qualification_artifact_bytes=$artifact_bytes" \
    'local_tests=246;failures=0;errors=0' \
    'script_65_query_resolution_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/query_resolution_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  printf 'script_65_query_resolution=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
cp -- "$temporary_artifact" "$artifact_path"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true

report_path="$(mktemp "$REPORT_ROOT/query_resolution_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=qualify_standalone_query_resolution_and_service_ordering'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;resolution_module_sha256=$resolution_module_sha256;transport_module_sha256=$transport_module_sha256;service_module_sha256=$service_module_sha256"
emit "resolution_tests_sha256=$resolution_tests_sha256;service_tests_sha256=$service_tests_sha256;evaluator_sha256=$evaluator_sha256;contract_sha256=$contract_sha256"
emit "api_profile_sha256=$api_profile_sha256;injection_profile_sha256=$injection_profile_sha256;service_profile_sha256=$service_profile_sha256;resolution_profile_sha256=$resolution_profile_sha256"
emit "accepted_script_64_report_sha256=$ACCEPTED_SCRIPT_64_REPORT_SHA256;accepted_script_64_artifact_sha256=$ACCEPTED_SCRIPT_64_ARTIFACT_SHA256"
emit 'authorized_actions=read_checksum_bound_local_evidence_run_local_tests_qualify_query_resolution_and_service_ordering_retain_content_free_acceptance_evidence'
emit 'non_actions=no_target_contact_no_network_access_no_database_contact_no_model_call_no_credential_read_no_listener_start_no_schema_change'
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$artifact_bytes"
emit "accepted_checksum=$checksum_path;raw_content_retained=false"
emit 'local_tests=246;failures=0;errors=0'
emit "script_65_query_resolution=pass;local_report=$report_path;next_gate=implement_native_postgresql_retrieval_adapter"
chmod 0600 "$report_path" 2>/dev/null || true
