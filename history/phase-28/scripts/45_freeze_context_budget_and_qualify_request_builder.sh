#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Freeze the Script 44 context budget in the durable contract and qualify
#   the deterministic grounded-generation request builder locally. Retain one
#   protected synthetic request for later exact tokenizer composition testing.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/45_freeze_context_budget_and_qualify_request_builder.sh --run

usage() {
  sed -n '3,11p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Run locally and retain the report and synthetic request.' \
    '  --validate-only Validate sources and tests without retaining artifacts.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$ISHIKAWA_ROOT/application/python"
readonly BASE_TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly PROFILE="$ISHIKAWA_ROOT/config/templates/reconstruction_profile.yaml"
readonly BUILDER="$PYTHON_ROOT/ishikawa/generation.py"
readonly BUILDER_TESTS="$ISHIKAWA_ROOT/tests/test_generation.py"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_generation_request_builder.py"
readonly CONTRACT_DOC="$ISHIKAWA_ROOT/docs/EVIDENCE_RECONSTRUCTION.md"
readonly BASELINE_DOC="$PHASE_ROOT/docs/PHASE_28_RAG_METHOD_BASELINE.md"
readonly CHUNKS="$REPO_ROOT/local/artifacts/ishikawa/retrieval-gap-method-profile/structural_chunk_candidates_20261020T002645Z.json"
readonly CHUNKS_SHA256='bc993ca0a417353f0d2313bcb2d1c94a1d526a513253139be71117bf88626bf3'
readonly ACCEPTED_BUDGET_REPORT="$REPO_ROOT/local/reports/ishikawa-context-budget/context_budget_20261020T021729Z_VirPgS.txt"
readonly ACCEPTED_BUDGET_REPORT_SHA256='1593c9baeabb13df1162b4d8cd67a933f2f9cdf9d5f245327319f1ed11d33500'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-generation-request-builder"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/generation-request-builder"

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
for required in awk bash cat chmod cp date grep mkdir mktemp python3 rm sha256sum stat tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'BLOCKED: missing local command: %s\n' "$required" >&2
    exit 2
  }
done
for source in \
  "$BASE_TEST_RUNNER" "$PROFILE" "$BUILDER" "$BUILDER_TESTS" "$EVALUATOR" \
  "$CONTRACT_DOC" "$BASELINE_DOC" "$CHUNKS" "$ACCEPTED_BUDGET_REPORT"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: a required Script 45 input is missing or unsafe.\n' >&2
    exit 2
  }
done
[[ "$(sha256sum "$CHUNKS" | awk '{print $1}')" == "$CHUNKS_SHA256" ]] || {
  printf 'BLOCKED: accepted chunk artifact checksum mismatch.\n' >&2
  exit 2
}
[[ "$(sha256sum "$ACCEPTED_BUDGET_REPORT" | awk '{print $1}')" == "$ACCEPTED_BUDGET_REPORT_SHA256" ]] || {
  printf 'BLOCKED: accepted context-budget report checksum mismatch.\n' >&2
  exit 2
}
for fact in \
  'reconstruction_policy_id=dd63ff812f8b482d95d25d1a15b2dbdb1aef750f65e17823ed02eeb3c03bb1c9' \
  'total_context_tokens=32768;instruction_token_limit=2048;conversation_token_limit=12288;evidence_token_limit=16384;answer_token_reserve=2048' \
  'instruction_boundary=pass;conversation_boundary=pass;evidence_boundary=pass' \
  'complete_procedure_fit=pass;complete_procedure_context_limit=pass' \
  'numeric_context_budget_qualification=pass' \
  'local_tests=127;failures=0;errors=0'; do
  grep -Fxq "$fact" "$ACCEPTED_BUDGET_REPORT" || {
    printf 'BLOCKED: required accepted context-budget fact is absent.\n' >&2
    exit 2
  }
done

bash -n "$BASE_TEST_RUNNER"
python3 -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$BUILDER" "$BUILDER_TESTS" "$EVALUATOR"

work_root="$(mktemp -d /tmp/ishikawa-script-45.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-45.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
bash "$BASE_TEST_RUNNER" >"$test_result" 2>&1 || {
  cat "$test_result" >&2
  printf 'script_45_request_builder=blocked;reason=test_regression\n' >&2
  exit 1
}
grep -Fq 'Ran 137 tests' "$test_result" || {
  printf 'script_45_request_builder=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_45_request_builder=blocked;reason=test_pass_marker_absent\n' >&2
  exit 1
}

profile_sha256="$(sha256sum "$PROFILE" | awk '{print $1}')"
temporary_artifact="$work_root/synthetic-grounded-generation-request.json"
evaluation_result="$work_root/evaluation.txt"
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 "$EVALUATOR" \
  --profile "$PROFILE" \
  --expected-profile-sha256 "$profile_sha256" \
  --chunks "$CHUNKS" \
  --expected-chunks-sha256 "$CHUNKS_SHA256" \
  --output "$temporary_artifact" >"$evaluation_result"
for fact in \
  'generation_request_builder_qualification=pass' \
  'trusted_instruction_boundary=pass;untrusted_json_payload_boundary=pass' \
  'conversation_preservation=pass;citation_allowlist=pass;deterministic_serialization=pass' \
  'model_call=false;endpoint_present=false;credential_present=false;organizational_content=false' \
  'exact_composed_token_measurement=pending_deployed_tokenizer'; do
  grep -Fxq "$fact" "$evaluation_result" || {
    cat "$evaluation_result" >&2
    printf 'script_45_request_builder=blocked;reason=evaluation_failed\n' >&2
    exit 1
  }
done

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
builder_sha256="$(sha256sum "$BUILDER" | awk '{print $1}')"
tests_sha256="$(sha256sum "$BUILDER_TESTS" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
contract_sha256="$(sha256sum "$CONTRACT_DOC" | awk '{print $1}')"
baseline_sha256="$(sha256sum "$BASELINE_DOC" | awk '{print $1}')"
artifact_sha256="$(sha256sum "$temporary_artifact" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$temporary_artifact")"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_context_budget_freeze_and_generation_request_builder_source' \
    'target_contact=false;database_contact=false;model_call=false;network_access=false' \
    "script_sha256=$script_sha256;builder_sha256=$builder_sha256;tests_sha256=$tests_sha256;evaluator_sha256=$evaluator_sha256" \
    "profile_sha256=$profile_sha256;contract_sha256=$contract_sha256;baseline_sha256=$baseline_sha256" \
    "chunk_sha256=$CHUNKS_SHA256;accepted_budget_report_sha256=$ACCEPTED_BUDGET_REPORT_SHA256" \
    "synthetic_request_sha256=$artifact_sha256;synthetic_request_bytes=$artifact_bytes" \
    'local_tests=137;failures=0;errors=0' \
    'script_45_request_builder_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/synthetic_grounded_generation_request_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  printf 'script_45_request_builder=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
cp -- "$temporary_artifact" "$artifact_path"
[[ "$(sha256sum "$artifact_path" | awk '{print $1}')" == "$artifact_sha256" ]] || {
  printf 'script_45_request_builder=blocked;reason=retained_artifact_identity_mismatch\n' >&2
  exit 1
}
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true

report_path="$(mktemp "$REPORT_ROOT/generation_request_builder_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=freeze_context_budget_and_qualify_generation_request_builder_locally'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;builder_sha256=$builder_sha256;tests_sha256=$tests_sha256;evaluator_sha256=$evaluator_sha256"
emit "profile_sha256=$profile_sha256;contract_sha256=$contract_sha256;baseline_sha256=$baseline_sha256"
emit "chunk_sha256=$CHUNKS_SHA256;accepted_budget_report_sha256=$ACCEPTED_BUDGET_REPORT_SHA256"
emit 'authorized_actions=read_checksum_bound_synthetic_inputs_run_local_tests_retain_protected_synthetic_request_and_content_free_report'
emit 'non_actions=no_target_contact_no_database_contact_no_network_access_no_model_call_no_source_document_read_no_service_configuration_or_schema_change'
emit 'context_budget_status=frozen;total_context_tokens=32768;qualified_service_maximum_tokens=204800'
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit "accepted_synthetic_request=$artifact_path;accepted_synthetic_request_sha256=$artifact_sha256;accepted_synthetic_request_bytes=$artifact_bytes"
emit "accepted_synthetic_checksum=$checksum_path;protected_synthetic_artifact=true;raw_text_in_routine_report=false"
emit 'local_tests=137;failures=0;errors=0'
emit "script_45_request_builder=pass;local_report=$report_path;next_gate=measure_composed_request_with_deployed_tokenizer"
