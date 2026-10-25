#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the versioned pre-retrieval scope-classifier profile, deterministic
#   request builder, and strict three-decision output validator locally.
#   No network, database, credential, or model access is used.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/50_qualify_scope_classifier_contract.sh --run

usage() {
  sed -n '3,11p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Run locally and retain a protected request and report.' \
    '  --validate-only Validate sources and tests without retaining artifacts.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$ISHIKAWA_ROOT/application/python"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly PROFILE="$ISHIKAWA_ROOT/config/templates/scope_profile.yaml"
readonly SCOPE_MODULE="$PYTHON_ROOT/ishikawa/scope.py"
readonly TRANSPORT_MODULE="$PYTHON_ROOT/ishikawa/generation_transport.py"
readonly TESTS="$ISHIKAWA_ROOT/tests/test_scope.py"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_scope_classifier_contract.py"
readonly CONTRACT_DOC="$ISHIKAWA_ROOT/docs/SCOPE_CLASSIFIER_CONTRACT.md"
readonly BASELINE_DOC="$PHASE_ROOT/docs/PHASE_28_RAG_METHOD_BASELINE.md"
readonly ACCEPTED_GENERATION_REPORT="$REPO_ROOT/local/reports/ishikawa-live-grounded-generation/generation_compatibility_correction_20261020T030918Z_GzEH1z.txt"
readonly ACCEPTED_GENERATION_REPORT_SHA256='5cf44bbd419ab9602e4118a6121dff2e06a6bf2c5f2f8391e8dccf6c491fd8c9'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-scope-classifier"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/scope-classifier"

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
  command -v "$required" >/dev/null 2>&1 || { printf 'BLOCKED: missing local command: %s\n' "$required" >&2; exit 2; }
done
for source in "$TEST_RUNNER" "$PROFILE" "$SCOPE_MODULE" "$TRANSPORT_MODULE" "$TESTS" "$EVALUATOR" "$CONTRACT_DOC" "$BASELINE_DOC" "$ACCEPTED_GENERATION_REPORT"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || { printf 'BLOCKED: a required Script 50 input is missing or unsafe.\n' >&2; exit 2; }
done
[[ "$(sha256sum "$ACCEPTED_GENERATION_REPORT" | awk '{print $1}')" == "$ACCEPTED_GENERATION_REPORT_SHA256" ]] || {
  printf 'BLOCKED: accepted Script 49 report checksum mismatch.\n' >&2
  exit 2
}
for fact in \
  'retained_generation_revalidation=pass;model_call=false;credential_read=false' \
  'strict_response_validation=pass;held_out_answer_content=pass;held_out_citation_coverage=pass' \
  'script_49_retained_generation=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_GENERATION_REPORT" || { printf 'BLOCKED: required accepted Script 49 fact is absent.\n' >&2; exit 2; }
done

bash -n "$TEST_RUNNER"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' "$SCOPE_MODULE" "$TRANSPORT_MODULE" "$TESTS" "$EVALUATOR"

work_root="$(mktemp -d /tmp/ishikawa-script-50.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-50.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
bash "$TEST_RUNNER" >"$test_result" 2>&1 || { cat "$test_result" >&2; printf 'script_50_scope_classifier=blocked;reason=test_regression\n' >&2; exit 1; }
grep -Fq 'Ran 166 tests' "$test_result" || { printf 'script_50_scope_classifier=blocked;reason=test_count_mismatch\n' >&2; exit 1; }
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || { printf 'script_50_scope_classifier=blocked;reason=test_pass_marker_absent\n' >&2; exit 1; }

profile_sha256="$(sha256sum "$PROFILE" | awk '{print $1}')"
temporary_artifact="$work_root/synthetic-scope-classifier-request.json"
evaluation_result="$work_root/evaluation.txt"
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B "$EVALUATOR" \
  --profile "$PROFILE" \
  --expected-profile-sha256 "$profile_sha256" \
  --output "$temporary_artifact" >"$evaluation_result"
for fact in \
  'decisions=3;reason_codes=11;max_output_tokens=128' \
  'trusted_instruction_boundary=pass;untrusted_json_payload_boundary=pass;structured_source_followup=pass' \
  'allow_needs_clarification_out_of_scope_validation=pass;reason_decision_binding=pass;clarification_semantics=pass' \
  'isolated_json_fence=pass;surrounding_prose_rejection=pass;answer_field_rejection=pass' \
  'scope_only=true;injection_gate_separate=true;retrieval_reached=false' \
  'network_contact=false;model_call=false;database_contact=false;credential_read=false' \
  'scope_classifier_contract_qualification=pass'; do
  grep -Fxq "$fact" "$evaluation_result" || { cat "$evaluation_result" >&2; printf 'script_50_scope_classifier=blocked;reason=evaluation_failed\n' >&2; exit 1; }
done

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
scope_sha256="$(sha256sum "$SCOPE_MODULE" | awk '{print $1}')"
transport_sha256="$(sha256sum "$TRANSPORT_MODULE" | awk '{print $1}')"
tests_sha256="$(sha256sum "$TESTS" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
contract_sha256="$(sha256sum "$CONTRACT_DOC" | awk '{print $1}')"
baseline_sha256="$(sha256sum "$BASELINE_DOC" | awk '{print $1}')"
artifact_sha256="$(sha256sum "$temporary_artifact" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$temporary_artifact")"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_scope_classifier_contract_source' \
    'target_contact=false;network_access=false;database_contact=false;model_call=false;credential_read=false' \
    "script_sha256=$script_sha256;scope_sha256=$scope_sha256;transport_sha256=$transport_sha256;tests_sha256=$tests_sha256;evaluator_sha256=$evaluator_sha256" \
    "profile_sha256=$profile_sha256;contract_sha256=$contract_sha256;baseline_sha256=$baseline_sha256" \
    "accepted_generation_report_sha256=$ACCEPTED_GENERATION_REPORT_SHA256" \
    "synthetic_scope_request_sha256=$artifact_sha256;synthetic_scope_request_bytes=$artifact_bytes" \
    'local_tests=166;failures=0;errors=0' \
    'script_50_scope_classifier_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/synthetic_scope_classifier_request_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || { printf 'script_50_scope_classifier=blocked;reason=artifact_path_exists\n' >&2; exit 1; }
cp -- "$temporary_artifact" "$artifact_path"
[[ "$(sha256sum "$artifact_path" | awk '{print $1}')" == "$artifact_sha256" ]] || { printf 'script_50_scope_classifier=blocked;reason=retained_artifact_identity_mismatch\n' >&2; exit 1; }
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true

report_path="$(mktemp "$REPORT_ROOT/scope_classifier_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=qualify_pre_retrieval_scope_classifier_contract_locally'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;scope_sha256=$scope_sha256;transport_sha256=$transport_sha256;tests_sha256=$tests_sha256;evaluator_sha256=$evaluator_sha256"
emit "profile_sha256=$profile_sha256;contract_sha256=$contract_sha256;baseline_sha256=$baseline_sha256"
emit "accepted_generation_report_sha256=$ACCEPTED_GENERATION_REPORT_SHA256"
emit 'authorized_actions=read_checksum_bound_synthetic_inputs_run_local_tests_retain_protected_synthetic_scope_request_and_content_free_report'
emit 'non_actions=no_target_contact_no_network_access_no_database_contact_no_model_call_no_credential_read_no_retrieval_no_source_document_read_no_service_configuration_or_schema_change'
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit "accepted_synthetic_scope_request=$artifact_path;accepted_synthetic_scope_request_sha256=$artifact_sha256;accepted_synthetic_scope_request_bytes=$artifact_bytes"
emit "accepted_synthetic_scope_checksum=$checksum_path;protected_synthetic_artifact=true;raw_text_in_routine_report=false"
emit 'local_tests=166;failures=0;errors=0'
emit "script_50_scope_classifier=pass;local_report=$report_path;next_gate=measure_scope_request_with_deployed_tokenizer"
