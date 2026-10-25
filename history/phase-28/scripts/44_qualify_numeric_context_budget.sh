#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify Ishikawa's provisional 32,768-token application budget against the
#   accepted Gemma tokenizer measurement. This is a local-only test: it does
#   not contact a target, call a model, or change the 204,800-token service.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/44_qualify_numeric_context_budget.sh --run

usage() {
  sed -n '3,11p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Run the local qualification and retain a content-free report.' \
    '  --validate-only Validate sources and tests without retaining a report.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$ISHIKAWA_ROOT/application/python"
readonly BASE_TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly PROFILE_VALIDATOR="$ISHIKAWA_ROOT/scripts/validate-reconstruction-profile.py"
readonly PROFILE="$ISHIKAWA_ROOT/config/templates/reconstruction_profile.yaml"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_context_budget.py"
readonly RECONSTRUCTION_SOURCE="$PYTHON_ROOT/ishikawa/reconstruction.py"
readonly RECONSTRUCTION_TESTS="$ISHIKAWA_ROOT/tests/test_reconstruction.py"
readonly CHUNKS="$REPO_ROOT/local/artifacts/ishikawa/retrieval-gap-method-profile/structural_chunk_candidates_20261020T002645Z.json"
readonly CHUNKS_SHA256='bc993ca0a417353f0d2313bcb2d1c94a1d526a513253139be71117bf88626bf3'
readonly MEASUREMENT="$REPO_ROOT/local/artifacts/ishikawa/generation-tokenizer/generation_tokenizer_measurement_20261020T021143Z.json"
readonly MEASUREMENT_SHA256='72c9ba0e86b97389ec4bb2f34075456fb56210bc6bb543fa6e666987b7a5a9f1'
readonly ACCEPTED_TOKENIZER_REPORT="$REPO_ROOT/local/reports/ishikawa-generation-tokenizer/generation_tokenizer_20261020T021143Z_zb45mj.txt"
readonly ACCEPTED_TOKENIZER_REPORT_SHA256='6152e77ca8147c2b36f3cee762bfc4f6367b3fa6d15a2d4290b9fd488877ee6a'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-context-budget"

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
for required in awk bash cat date grep mkdir mktemp python3 rm sha256sum tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'BLOCKED: missing local command: %s\n' "$required" >&2
    exit 2
  }
done
for source in \
  "$BASE_TEST_RUNNER" "$PROFILE_VALIDATOR" "$PROFILE" "$EVALUATOR" \
  "$RECONSTRUCTION_SOURCE" "$RECONSTRUCTION_TESTS" "$CHUNKS" \
  "$MEASUREMENT" "$ACCEPTED_TOKENIZER_REPORT"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: a required Script 44 input is missing or unsafe.\n' >&2
    exit 2
  }
done
[[ "$(sha256sum "$CHUNKS" | awk '{print $1}')" == "$CHUNKS_SHA256" ]] || {
  printf 'BLOCKED: accepted chunk artifact checksum mismatch.\n' >&2
  exit 2
}
[[ "$(sha256sum "$MEASUREMENT" | awk '{print $1}')" == "$MEASUREMENT_SHA256" ]] || {
  printf 'BLOCKED: accepted tokenizer measurement checksum mismatch.\n' >&2
  exit 2
}
[[ "$(sha256sum "$ACCEPTED_TOKENIZER_REPORT" | awk '{print $1}')" == "$ACCEPTED_TOKENIZER_REPORT_SHA256" ]] || {
  printf 'BLOCKED: accepted tokenizer report checksum mismatch.\n' >&2
  exit 2
}
for fact in \
  'generation_tokenizer_evaluation=pass' \
  'numeric_budget_calibration=pending_review;configuration_changed=false;service_state_changed=false' \
  'cleanup_remote_temporary_files=removed' \
  'cleanup_ssh_master_exit_code=0'; do
  grep -Fxq "$fact" "$ACCEPTED_TOKENIZER_REPORT" || {
    printf 'BLOCKED: required accepted tokenizer fact is absent.\n' >&2
    exit 2
  }
done

bash -n "$BASE_TEST_RUNNER"
python3 -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$PROFILE_VALIDATOR" "$EVALUATOR" "$RECONSTRUCTION_SOURCE" "$RECONSTRUCTION_TESTS"

work_root="$(mktemp -d /tmp/ishikawa-script-44.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-44.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
bash "$BASE_TEST_RUNNER" >"$test_result" 2>&1 || {
  cat "$test_result" >&2
  printf 'script_44_context_budget=blocked;reason=test_regression\n' >&2
  exit 1
}
grep -Fq 'Ran 127 tests' "$test_result" || {
  printf 'script_44_context_budget=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_44_context_budget=blocked;reason=test_pass_marker_absent\n' >&2
  exit 1
}

profile_sha256="$(sha256sum "$PROFILE" | awk '{print $1}')"
profile_result="$work_root/profile.txt"
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 "$PROFILE_VALIDATOR" \
  --profile "$PROFILE" >"$profile_result"
grep -Fxq 'reconstruction_profile_validation=pass' "$profile_result" || {
  cat "$profile_result" >&2
  printf 'script_44_context_budget=blocked;reason=profile_validation_failed\n' >&2
  exit 1
}

evaluation_result="$work_root/evaluation.txt"
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 "$EVALUATOR" \
  --profile "$PROFILE" \
  --expected-profile-sha256 "$profile_sha256" \
  --measurement "$MEASUREMENT" \
  --expected-measurement-sha256 "$MEASUREMENT_SHA256" \
  --chunks "$CHUNKS" \
  --expected-chunks-sha256 "$CHUNKS_SHA256" >"$evaluation_result"
for fact in \
  'numeric_context_budget_qualification=pass' \
  'instruction_boundary=pass;conversation_boundary=pass;evidence_boundary=pass' \
  'complete_procedure_fit=pass;complete_procedure_context_limit=pass' \
  'full_prompt_composition_qualification=pending_request_builder' \
  'latency_and_answer_quality_qualification=pending_model_integration'; do
  grep -Fxq "$fact" "$evaluation_result" || {
    cat "$evaluation_result" >&2
    printf 'script_44_context_budget=blocked;reason=evaluation_failed\n' >&2
    exit 1
  }
done

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
source_sha256="$(sha256sum "$RECONSTRUCTION_SOURCE" | awk '{print $1}')"
tests_sha256="$(sha256sum "$RECONSTRUCTION_TESTS" | awk '{print $1}')"
validator_sha256="$(sha256sum "$PROFILE_VALIDATOR" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_numeric_context_budget_qualification_source' \
    'target_contact=false;database_contact=false;model_call=false;service_state_change=false' \
    "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256;source_sha256=$source_sha256" \
    "tests_sha256=$tests_sha256;validator_sha256=$validator_sha256;profile_sha256=$profile_sha256" \
    "measurement_sha256=$MEASUREMENT_SHA256;chunk_sha256=$CHUNKS_SHA256;accepted_tokenizer_report_sha256=$ACCEPTED_TOKENIZER_REPORT_SHA256" \
    'local_tests=127;failures=0;errors=0' \
    'script_44_context_budget_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/context_budget_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=qualify_numeric_generation_context_budget_locally'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256;source_sha256=$source_sha256"
emit "tests_sha256=$tests_sha256;validator_sha256=$validator_sha256;profile_sha256=$profile_sha256"
emit "measurement_sha256=$MEASUREMENT_SHA256;chunk_sha256=$CHUNKS_SHA256;accepted_tokenizer_report_sha256=$ACCEPTED_TOKENIZER_REPORT_SHA256"
emit 'authorized_actions=read_checksum_bound_synthetic_measurement_validate_context_profile_run_local_tests_retain_content_free_report'
emit 'non_actions=no_target_contact_no_database_contact_no_network_access_no_model_call_no_source_document_read_no_service_configuration_or_schema_change'
while IFS= read -r line; do emit "$line"; done <"$profile_result"
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit 'local_tests=127;failures=0;errors=0'
emit "script_44_context_budget=pass;local_report=$report_path;next_gate=review_and_freeze_qualified_context_budget"
