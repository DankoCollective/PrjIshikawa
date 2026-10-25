#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the protected responsive and nonresponsive synthetic question set
#   locally before any embedding or retrieval calibration is attempted.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/55_qualify_relevance_calibration_cases.sh --run

usage() {
  sed -n '3,10p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Run locally and retain content-free qualification evidence.' \
    '  --validate-only Validate sources without retaining artifacts.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_relevance_case_contract.py"
readonly CONTRACT_DOC="$ISHIKAWA_ROOT/docs/RELEVANCE_CALIBRATION_CONTRACT.md"
readonly CASES="$REPO_ROOT/local/artifacts/ishikawa/relevance-calibration-input/relevance_cases_v1.json"
readonly TRUTH="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/evaluation/retrieval_cases.json"
readonly CHUNKS="$REPO_ROOT/local/artifacts/ishikawa/retrieval-gap-method-profile/structural_chunk_candidates_20261020T002645Z.json"
readonly ACCEPTED_SUFFICIENCY_REPORT="$REPO_ROOT/local/reports/ishikawa-sufficiency-gate/sufficiency_gate_20261020T035552Z_BseBuL.txt"
readonly CASES_SHA256='2fa6a20fc77f1faa25d141838b50ad0e95e2467035a0193d7f94451202cd94da'
readonly TRUTH_SHA256='cf3d058a67eb00de3f5f4d644a46dc3bdc3172d636f68b2dee520a734c13f240'
readonly CHUNKS_SHA256='bc993ca0a417353f0d2313bcb2d1c94a1d526a513253139be71117bf88626bf3'
readonly ACCEPTED_SUFFICIENCY_REPORT_SHA256='4537f734a8a231478da585307bc4ec1f1d2929bbd490bf07d4021114dee4ec2c'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-relevance-case-contract"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/relevance-case-contract"

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
for required in awk bash chmod cp date grep mkdir mktemp python3 rm sha256sum stat tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'BLOCKED: missing local command: %s\n' "$required" >&2
    exit 2
  }
done
for source in "$TEST_RUNNER" "$EVALUATOR" "$CONTRACT_DOC" "$CASES" "$TRUTH" "$CHUNKS" "$ACCEPTED_SUFFICIENCY_REPORT"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: required Script 55 input is missing or unsafe.\n' >&2
    exit 2
  }
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'BLOCKED: %s checksum mismatch.\n' "$3" >&2
    exit 2
  }
}
check_sha256 "$CASES" "$CASES_SHA256" 'protected relevance cases'
check_sha256 "$TRUTH" "$TRUTH_SHA256" 'accepted held-out retrieval truth'
check_sha256 "$CHUNKS" "$CHUNKS_SHA256" 'accepted synthetic chunk set'
check_sha256 "$ACCEPTED_SUFFICIENCY_REPORT" "$ACCEPTED_SUFFICIENCY_REPORT_SHA256" 'accepted Script 54 report'
for fact in \
  'calibrated_relevance_required=true;candidate_presence_is_not_relevance=true;uncalibrated_relevance_fails_closed=true' \
  'sufficiency_gate_contract_qualification=pass' \
  'script_54_sufficiency_gate=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_SUFFICIENCY_REPORT" || {
    printf 'BLOCKED: required accepted Script 54 fact is absent.\n' >&2
    exit 2
  }
done

bash -n "$TEST_RUNNER"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' "$EVALUATOR"
python3 -B "$EVALUATOR" --self-test >/dev/null

work_root="$(mktemp -d /tmp/ishikawa-script-55.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-55.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  cat "$test_result" >&2
  printf 'script_55_relevance_case_contract=blocked;reason=test_regression\n' >&2
  exit 1
}
grep -Fq 'Ran 195 tests' "$test_result" || {
  printf 'script_55_relevance_case_contract=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_55_relevance_case_contract=blocked;reason=test_pass_marker_absent\n' >&2
  exit 1
}

temporary_artifact="$work_root/relevance-case-contract.json"
evaluation_result="$work_root/evaluation.txt"
python3 -B "$EVALUATOR" \
  --cases "$CASES" --expected-cases-sha256 "$CASES_SHA256" \
  --truth "$TRUTH" --expected-truth-sha256 "$TRUTH_SHA256" \
  --chunks "$CHUNKS" --expected-chunks-sha256 "$CHUNKS_SHA256" \
  --output "$temporary_artifact" >"$evaluation_result"
for fact in \
  'cases=12;responsive=6;nonresponsive=6;near_domain_nonresponsive=3' \
  'scope_excluded=1;absence_terms_checked=6;responsive_truth_match=pass' \
  'threshold_selected=false;model_call=false;network_contact=false;database_contact=false' \
  'relevance_case_contract_qualification=pass'; do
  grep -Fxq "$fact" "$evaluation_result" || {
    cat "$evaluation_result" >&2
    printf 'script_55_relevance_case_contract=blocked;reason=evaluation_failed\n' >&2
    exit 1
  }
done

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
contract_sha256="$(sha256sum "$CONTRACT_DOC" | awk '{print $1}')"
artifact_sha256="$(sha256sum "$temporary_artifact" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$temporary_artifact")"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_relevance_calibration_case_contract_source' \
    'target_contact=false;network_access=false;database_contact=false;model_call=false;credential_read=false' \
    "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256;contract_sha256=$contract_sha256" \
    "case_set_sha256=$CASES_SHA256;truth_sha256=$TRUTH_SHA256;chunk_set_sha256=$CHUNKS_SHA256" \
    "accepted_sufficiency_report_sha256=$ACCEPTED_SUFFICIENCY_REPORT_SHA256;qualification_artifact_sha256=$artifact_sha256;qualification_artifact_bytes=$artifact_bytes" \
    'local_tests=195;responsive=6;nonresponsive=6;scope_excluded=1;failures=0;errors=0' \
    'script_55_relevance_case_contract_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/relevance_case_contract_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  printf 'script_55_relevance_case_contract=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
cp -- "$temporary_artifact" "$artifact_path"
check_sha256 "$artifact_path" "$artifact_sha256" 'retained relevance case qualification artifact'
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true

report_path="$(mktemp "$REPORT_ROOT/relevance_case_contract_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=qualify_responsive_and_nonresponsive_relevance_calibration_cases_locally'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256;contract_sha256=$contract_sha256"
emit "case_set_sha256=$CASES_SHA256;truth_sha256=$TRUTH_SHA256;chunk_set_sha256=$CHUNKS_SHA256"
emit "accepted_sufficiency_report_sha256=$ACCEPTED_SUFFICIENCY_REPORT_SHA256"
emit 'authorized_actions=read_checksum_bound_synthetic_inputs_run_local_tests_retain_content_free_case_digests_and_report'
emit 'non_actions=no_target_contact_no_network_access_no_database_contact_no_model_call_no_credential_read_no_threshold_selection_no_runtime_profile_change_no_source_document_read'
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$artifact_bytes"
emit "accepted_checksum=$checksum_path;raw_question_text_retained=false"
emit 'local_tests=195;failures=0;errors=0'
emit "script_55_relevance_case_contract=pass;local_report=$report_path;next_gate=embed_qualified_relevance_questions_with_nomic"
