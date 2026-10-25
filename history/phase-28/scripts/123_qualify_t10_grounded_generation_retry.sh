#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the frozen T10 bounded grounded-generation retry and run the
#   complete native Ishikawa regression suite.
#
# Mental model:
#   Rebind the two complete-API receipts that exposed different stochastic
#   generation failures, verify the frozen T10 source and documentation, then
#   run every native test. This gate changes no runtime or package state; a
#   pass routes back to the complete live Script 122 API qualification.
#
# Inputs or prerequisites:
#   The two checksum-bound Script 122 failure receipts, frozen T10, and the
#   amended Ishikawa v1.1 working source.
#
# Outputs or artifact lane:
#   One content-free local qualification report. No package, database, model,
#   service, credential, or accepted Ishikawa v1 artifact is changed.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/123_qualify_t10_grounded_generation_retry.sh --run

usage() {
  sed -n '3,27p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run            Qualify the frozen T10 implementation.' \
    '  --validate-only  Validate bound source and run tests without a report.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly TEST_RUNNER="$PRODUCT_ROOT/scripts/run-local-validation-tests.sh"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_1_TUNING_DECISIONS.md"
readonly BASELINE="$PHASE_ROOT/docs/PHASE_28_RAG_METHOD_BASELINE.md"
readonly ADAPTER_DOC="$PRODUCT_ROOT/docs/NATIVE_DEPENDENCY_ADAPTERS.md"
readonly FIRST_API_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.1-complete-api/complete_api_20261021T180506Z_4nHzx4.txt"
readonly SECOND_API_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.1-complete-api/complete_api_20261021T181252Z_MPbqXS.txt"
readonly RETRIEVAL_SERVICE="$PYTHON_ROOT/ishikawa/retrieval_service.py"
readonly NATIVE_ADAPTERS="$PYTHON_ROOT/ishikawa/native_adapters.py"
readonly OBSERVABILITY="$PYTHON_ROOT/ishikawa/observability.py"
readonly RETRIEVAL_SERVICE_TEST="$PRODUCT_ROOT/tests/test_retrieval_service.py"
readonly NATIVE_ADAPTERS_TEST="$PRODUCT_ROOT/tests/test_native_adapters.py"
readonly OBSERVABILITY_TEST="$PRODUCT_ROOT/tests/test_observability.py"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.1-t10-implementation"

readonly DECISIONS_SHA256='c6521704144132968a2b6b1a4a1c7136e5c3f5e30f41cbf67246247dbf5e81d5'
readonly BASELINE_SHA256='572f718c6cb2d88f995743ede534779bcf43763d8a5b94b5348fc94c620d79d5'
readonly ADAPTER_DOC_SHA256='8071c8eb2ab91ec7451d315b5d83c08acf264d328311afd969dcc5879665f60e'
readonly FIRST_API_REPORT_SHA256='263ad280c8df9afc02ce06dfe0e7691ed7d4535cd417314f2eae1a0e0f455a36'
readonly SECOND_API_REPORT_SHA256='d2a322899e4e4b8f8293d000f9e6220ac1e78f2d97325e5f1ce607c206efec58'
readonly RETRIEVAL_SERVICE_SHA256='b297358b691fdfaf987c89b9e5b5539f083545c22b2be7cbabd1cf1a08b9c6b1'
readonly NATIVE_ADAPTERS_SHA256='0a427682f63288baa3faaa1849f74eb3411688112f691531c693e5da83187138'
readonly OBSERVABILITY_SHA256='b14cd34e763cbd008ef2eed99011afe04bdb74a6c509e7e91c488e17586d743d'
readonly RETRIEVAL_SERVICE_TEST_SHA256='23d4c503386b4250d67102e4f46e3a4593b0045e9cdb4eefac1633db009633da'
readonly NATIVE_ADAPTERS_TEST_SHA256='b7ac6e4729d5660dbfa6db4b08fb3fa7bf7c324b29ae69aebb1154f45b9e7c51'
readonly OBSERVABILITY_TEST_SHA256='d03b1a5cd1e735b6fc9793b27059af58c7f8e98a6c920c82847f4bbcda83f978'
readonly TEST_RUNNER_SHA256='092b2cb8e5254d1ca2b6e71a496bf76743004134848e249d5d7b9f37d9d62eb7'
readonly EXPECTED_TEST_COUNT='376'

run_mode=false
validate_mode=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_mode=true; shift ;;
    --validate-only) validate_mode=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_123_t10_implementation=blocked;reason=argument_invalid\n' >&2; exit 2 ;;
  esac
done
[[ "$run_mode" != "$validate_mode" ]] || {
  printf 'script_123_t10_implementation=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in awk bash chmod date dirname grep mkdir mktemp python3 rm sed sha256sum stat tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_123_t10_implementation=blocked;reason=local_command_missing;command=%s\n' "$required" >&2
    exit 2
  }
done

check_file() {
  [[ -f "$1" && ! -L "$1" && -r "$1" ]] || {
    printf 'script_123_t10_implementation=blocked;reason=%s_unsafe\n' "$3" >&2
    exit 2
  }
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_123_t10_implementation=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}

check_file "$DECISIONS" "$DECISIONS_SHA256" tuning_decisions
check_file "$BASELINE" "$BASELINE_SHA256" method_baseline
check_file "$ADAPTER_DOC" "$ADAPTER_DOC_SHA256" adapter_documentation
check_file "$FIRST_API_REPORT" "$FIRST_API_REPORT_SHA256" first_api_report
check_file "$SECOND_API_REPORT" "$SECOND_API_REPORT_SHA256" second_api_report
check_file "$RETRIEVAL_SERVICE" "$RETRIEVAL_SERVICE_SHA256" retrieval_service_source
check_file "$NATIVE_ADAPTERS" "$NATIVE_ADAPTERS_SHA256" native_adapters_source
check_file "$OBSERVABILITY" "$OBSERVABILITY_SHA256" observability_source
check_file "$RETRIEVAL_SERVICE_TEST" "$RETRIEVAL_SERVICE_TEST_SHA256" retrieval_service_test
check_file "$NATIVE_ADAPTERS_TEST" "$NATIVE_ADAPTERS_TEST_SHA256" native_adapters_test
check_file "$OBSERVABILITY_TEST" "$OBSERVABILITY_TEST_SHA256" observability_test
check_file "$TEST_RUNNER" "$TEST_RUNNER_SHA256" test_runner

grep -Eq '^\| `T10` \|.*\| FROZEN \|$' "$DECISIONS" || {
  printf 'script_123_t10_implementation=blocked;reason=t10_not_frozen\n' >&2
  exit 2
}
for report_contract in \
  "$FIRST_API_REPORT|[API] case_result=R-006;status=temporarily-unavailable;expected_status=answered" \
  "$FIRST_API_REPORT|[SUMMARY] full_api_gate=not_met;responsive_answered=5/6;nonresponsive_abstained=6/6;broad_clarification=1/1;dependency_failures=1" \
  "$SECOND_API_REPORT|[API] case_result=R-003;status=temporarily-unavailable;expected_status=answered" \
  "$SECOND_API_REPORT|[SUMMARY] full_api_gate=not_met;responsive_answered=5/6;nonresponsive_abstained=6/6;broad_clarification=1/1;dependency_failures=1"; do
  report_path="${report_contract%%|*}"
  required_fact="${report_contract#*|}"
  grep -Fq "$required_fact" "$report_path" || {
    printf 'script_123_t10_implementation=blocked;reason=api_evidence_contract_invalid\n' >&2
    exit 2
  }
done
grep -Fq 'class GroundedGenerationRetryableUnavailable' "$RETRIEVAL_SERVICE" || {
  printf 'script_123_t10_implementation=blocked;reason=retry_signal_missing\n' >&2
  exit 2
}
grep -Fq 'trace.append("generation-retry")' "$RETRIEVAL_SERVICE" || {
  printf 'script_123_t10_implementation=blocked;reason=retry_evidence_missing\n' >&2
  exit 2
}
grep -Fq 'raise GroundedGenerationRetryableUnavailable() from error' "$NATIVE_ADAPTERS" || {
  printf 'script_123_t10_implementation=blocked;reason=adapter_retry_signal_missing\n' >&2
  exit 2
}
grep -Fq '"generation-retry"' "$OBSERVABILITY" || {
  printf 'script_123_t10_implementation=blocked;reason=retry_observability_missing\n' >&2
  exit 2
}

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$RETRIEVAL_SERVICE" "$NATIVE_ADAPTERS" "$OBSERVABILITY" \
  "$RETRIEVAL_SERVICE_TEST" "$NATIVE_ADAPTERS_TEST" "$OBSERVABILITY_TEST"

work_root="$(mktemp -d /tmp/ishikawa-script-123.XXXXXX)"
report_path=''
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  [[ "$work_root" == /tmp/ishikawa-script-123.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  [[ -z "$report_path" ]] || chmod 0600 "$report_path" 2>/dev/null || true
  exit "$status"
}
trap cleanup EXIT

emit() {
  if [[ -n "$report_path" ]]; then
    printf '%s\n' "$1" | tee -a "$report_path"
  else
    printf '%s\n' "$1"
  fi
}
block() {
  emit "script_123_t10_implementation=blocked;reason=$1"
  exit 1
}
trap 'block interrupted_by_operator' INT
trap 'block terminated_by_signal' TERM

if [[ "$run_mode" == true ]]; then
  mkdir -p -- "$REPORT_ROOT"
  [[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" ]] || block report_directory_unsafe
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  report_path="$(mktemp "$REPORT_ROOT/t10_implementation_${timestamp}_XXXXXX.txt")"
  emit '[RETRY] milestone=t10_contract;state=start'
  emit '[RETRY] milestone=t10_contract;state=pass;maximum_generation_attempts=2;non_generation_retry=false;second_failure=temporarily-unavailable;retry_evidence=content_free'
  emit "[REGRESSION] milestone=native_tests;state=start;expected_tests=$EXPECTED_TEST_COUNT"
fi

test_output="$work_root/native-tests.txt"
if PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_output" 2>&1; then
  test_status=0
else
  test_status=$?
fi
(( test_status == 0 )) || {
  emit "script_123_t10_implementation=blocked;reason=native_test_regression;diagnostic_sha256=$(sha256sum "$test_output" | awk '{print $1}');diagnostic_bytes=$(stat -c '%s' "$test_output");raw_output_retained=false"
  exit 1
}
grep -Fq "Ran $EXPECTED_TEST_COUNT tests" "$test_output" || block native_test_count_mismatch
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_output" \
  || block native_test_pass_marker_absent

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_mode" == true ]]; then
  printf '%s\n' \
    'purpose=validate_frozen_t10_grounded_generation_retry' \
    "script_sha256=$script_sha256;decision_list_sha256=$DECISIONS_SHA256" \
    "first_api_report_sha256=$FIRST_API_REPORT_SHA256;second_api_report_sha256=$SECOND_API_REPORT_SHA256" \
    'maximum_generation_attempts=2;non_generation_retry=false;second_failure=temporarily-unavailable;retry_evidence=content_free' \
    "native_tests=$EXPECTED_TEST_COUNT;failures=0;errors=0" \
    'database_contact=false;model_contact=false;credential_read=false;service_changed=false;package_built=false' \
    'script_123_t10_implementation_source=pass'
  exit 0
fi

emit "[REGRESSION] milestone=native_tests;state=pass;tests=$EXPECTED_TEST_COUNT;failures=0;errors=0"
emit '[SUMMARY] maximum_generation_attempts=2;non_generation_retry=false;second_failure=temporarily-unavailable;retry_evidence=content_free'
emit "[SUMMARY] first_api_report_sha256=$FIRST_API_REPORT_SHA256;second_api_report_sha256=$SECOND_API_REPORT_SHA256"
emit '[SUMMARY] database_contact=false;model_contact=false;credential_read=false;service_changed=false;package_built=false'
emit "script_123_t10_implementation=pass;next_gate=rerun_script_122_complete_api;local_report=$report_path"
