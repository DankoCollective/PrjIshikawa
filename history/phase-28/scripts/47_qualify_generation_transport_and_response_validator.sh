#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the local native-HTTP generation transport boundary and strict
#   grounded-response validator against the accepted synthetic request and
#   exact composed-token measurement. No network or model call is made.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/47_qualify_generation_transport_and_response_validator.sh --run

usage() {
  sed -n '3,11p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Run locally and retain a content-free report.' \
    '  --validate-only Validate sources and tests without retaining a report.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$ISHIKAWA_ROOT/application/python"
readonly BASE_TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly TRANSPORT="$PYTHON_ROOT/ishikawa/generation_transport.py"
readonly TRANSPORT_TESTS="$ISHIKAWA_ROOT/tests/test_generation_transport.py"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_generation_transport_and_response.py"
readonly CONTRACT_DOC="$ISHIKAWA_ROOT/docs/EVIDENCE_RECONSTRUCTION.md"
readonly BASELINE_DOC="$PHASE_ROOT/docs/PHASE_28_RAG_METHOD_BASELINE.md"
readonly REQUEST="$REPO_ROOT/local/artifacts/ishikawa/generation-request-builder/synthetic_grounded_generation_request_20261020T022552Z.json"
readonly REQUEST_SHA256='e381347fe151f1c04ed84021a4c5ae6b8198adfcc0e7b425cb7ad33f037ea7a4'
readonly MEASUREMENT="$REPO_ROOT/local/artifacts/ishikawa/composed-request-tokens/composed_request_token_measurement_20261020T023110Z.json"
readonly MEASUREMENT_SHA256='457402ef61ee1f6b64af33f4444b2b9b7258ca922ad22830a4afda6738967eee'
readonly ACCEPTED_MEASUREMENT_REPORT="$REPO_ROOT/local/reports/ishikawa-composed-request-tokens/composed_request_tokens_20261020T023110Z_phuZJ3.txt"
readonly ACCEPTED_MEASUREMENT_REPORT_SHA256='2764503f947286cdee94e783afd66fb342260cc2264871e73dcef72aa8e49d94'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-generation-transport"

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
for required in awk bash cat chmod date grep mkdir mktemp python3 rm sed sha256sum tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'BLOCKED: missing local command: %s\n' "$required" >&2
    exit 2
  }
done
for source in \
  "$BASE_TEST_RUNNER" "$TRANSPORT" "$TRANSPORT_TESTS" "$EVALUATOR" \
  "$CONTRACT_DOC" "$BASELINE_DOC" "$REQUEST" "$MEASUREMENT" \
  "$ACCEPTED_MEASUREMENT_REPORT"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: a required Script 47 input is missing or unsafe.\n' >&2
    exit 2
  }
done
[[ "$(sha256sum "$REQUEST" | awk '{print $1}')" == "$REQUEST_SHA256" ]] || {
  printf 'BLOCKED: accepted request checksum mismatch.\n' >&2
  exit 2
}
[[ "$(sha256sum "$MEASUREMENT" | awk '{print $1}')" == "$MEASUREMENT_SHA256" ]] || {
  printf 'BLOCKED: accepted measurement checksum mismatch.\n' >&2
  exit 2
}
[[ "$(sha256sum "$ACCEPTED_MEASUREMENT_REPORT" | awk '{print $1}')" == "$ACCEPTED_MEASUREMENT_REPORT_SHA256" ]] || {
  printf 'BLOCKED: accepted Script 46 report checksum mismatch.\n' >&2
  exit 2
}
for fact in \
  'prompt_tokens=884;answer_token_reserve=2048;total_reserved_tokens=2932;application_context_limit=32768;application_remaining_tokens=29836' \
  'system_role_template_compatibility=pass;exact_request_budget_fit=pass' \
  'model_called=false;credential_read=false;raw_text_retained=false'; do
  grep -Fxq "$fact" "$ACCEPTED_MEASUREMENT_REPORT" || {
    printf 'BLOCKED: required accepted Script 46 fact is absent.\n' >&2
    exit 2
  }
done

bash -n "$BASE_TEST_RUNNER"
python3 -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$TRANSPORT" "$TRANSPORT_TESTS" "$EVALUATOR"

work_root="$(mktemp -d /tmp/ishikawa-script-47.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-47.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
bash "$BASE_TEST_RUNNER" >"$test_result" 2>&1 || {
  cat "$test_result" >&2
  printf 'script_47_generation_transport=blocked;reason=test_regression\n' >&2
  exit 1
}
grep -Fq 'Ran 152 tests' "$test_result" || {
  printf 'script_47_generation_transport=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_47_generation_transport=blocked;reason=test_pass_marker_absent\n' >&2
  exit 1
}

evaluation_result="$work_root/evaluation.txt"
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 "$EVALUATOR" \
  --request "$REQUEST" \
  --expected-request-sha256 "$REQUEST_SHA256" \
  --measurement "$MEASUREMENT" \
  --expected-measurement-sha256 "$MEASUREMENT_SHA256" >"$evaluation_result"
for fact in \
  'configurable_endpoint=pass;native_standard_library_transport=pass;single_post_no_retry=pass' \
  'runtime_credential_header_only=pass;request_body_identity=pass' \
  'openai_vllm_envelope_validation=pass;usage_validation=pass;answer_reserve_enforced=pass' \
  'grounded_json_validation=pass;citation_allowlist_validation=pass;complete_claim_coverage=pass' \
  'failure_path_matrix=pass;cases=unknown_citation,incomplete_completion,unauthorized_channel,uncited_answer,invalid_usage' \
  'network_contact=false;model_call=false;database_contact=false;credential_read=false' \
  'generation_transport_response_qualification=pass'; do
  grep -Fxq "$fact" "$evaluation_result" || {
    cat "$evaluation_result" >&2
    printf 'script_47_generation_transport=blocked;reason=evaluation_failed\n' >&2
    exit 1
  }
done

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
transport_sha256="$(sha256sum "$TRANSPORT" | awk '{print $1}')"
tests_sha256="$(sha256sum "$TRANSPORT_TESTS" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
contract_sha256="$(sha256sum "$CONTRACT_DOC" | awk '{print $1}')"
baseline_sha256="$(sha256sum "$BASELINE_DOC" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_generation_transport_and_response_validator_source' \
    'target_contact=false;database_contact=false;model_call=false;network_access=false;credential_read=false' \
    "script_sha256=$script_sha256;transport_sha256=$transport_sha256;tests_sha256=$tests_sha256;evaluator_sha256=$evaluator_sha256" \
    "contract_sha256=$contract_sha256;baseline_sha256=$baseline_sha256" \
    "request_sha256=$REQUEST_SHA256;measurement_sha256=$MEASUREMENT_SHA256;accepted_measurement_report_sha256=$ACCEPTED_MEASUREMENT_REPORT_SHA256" \
    'local_tests=152;failures=0;errors=0' \
    'script_47_generation_transport_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/generation_transport_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=qualify_generation_transport_and_grounded_response_validator_locally'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;transport_sha256=$transport_sha256;tests_sha256=$tests_sha256;evaluator_sha256=$evaluator_sha256"
emit "contract_sha256=$contract_sha256;baseline_sha256=$baseline_sha256"
emit "request_sha256=$REQUEST_SHA256;measurement_sha256=$MEASUREMENT_SHA256;accepted_measurement_report_sha256=$ACCEPTED_MEASUREMENT_REPORT_SHA256"
emit 'authorized_actions=read_checksum_bound_synthetic_inputs_run_local_tests_retain_content_free_report'
emit 'non_actions=no_target_contact_no_database_contact_no_network_access_no_model_call_no_credential_read_no_source_document_read_no_service_configuration_or_schema_change'
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit 'local_tests=152;failures=0;errors=0'
emit "script_47_generation_transport=pass;local_report=$report_path;next_gate=run_bounded_live_grounded_generation"
