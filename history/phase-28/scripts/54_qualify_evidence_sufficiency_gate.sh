#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the fail-closed deterministic post-retrieval evidence-sufficiency
#   gate locally without inventing an uncalibrated relevance threshold.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/54_qualify_evidence_sufficiency_gate.sh --run

usage() {
  sed -n '3,10p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Run locally and retain content-free qualification evidence.' \
    '  --validate-only Validate sources and tests without retaining artifacts.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$ISHIKAWA_ROOT/application/python"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly PROFILE="$ISHIKAWA_ROOT/config/templates/sufficiency_profile.yaml"
readonly RECONSTRUCTION_PROFILE="$ISHIKAWA_ROOT/config/templates/reconstruction_profile.yaml"
readonly MODULE="$PYTHON_ROOT/ishikawa/sufficiency.py"
readonly TESTS="$ISHIKAWA_ROOT/tests/test_sufficiency.py"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_sufficiency_gate_contract.py"
readonly CONTRACT_DOC="$ISHIKAWA_ROOT/docs/SUFFICIENCY_GATE_CONTRACT.md"
readonly ACCEPTED_INJECTION_REPORT="$REPO_ROOT/local/reports/ishikawa-injection-gate/injection_gate_20261020T034715Z_ShsJJ1.txt"
readonly ACCEPTED_INJECTION_REPORT_SHA256='6d42d8477b736fc072f7df96389ccd94312223141ddad8299f63e2d525919207'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-sufficiency-gate"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/sufficiency-gate"

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
[[ "$run_authorized" != "$validate_only" ]] || { printf 'BLOCKED: choose exactly one of --run or --validate-only.\n' >&2; exit 2; }
for required in awk bash chmod cp date grep mkdir mktemp python3 rm sha256sum stat tee; do
  command -v "$required" >/dev/null 2>&1 || { printf 'BLOCKED: missing local command: %s\n' "$required" >&2; exit 2; }
done
for source in "$TEST_RUNNER" "$PROFILE" "$RECONSTRUCTION_PROFILE" "$MODULE" "$TESTS" "$EVALUATOR" "$CONTRACT_DOC" "$ACCEPTED_INJECTION_REPORT"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || { printf 'BLOCKED: required Script 54 input is missing or unsafe.\n' >&2; exit 2; }
done
[[ "$(sha256sum "$ACCEPTED_INJECTION_REPORT" | awk '{print $1}')" == "$ACCEPTED_INJECTION_REPORT_SHA256" ]] || { printf 'BLOCKED: accepted Script 53 report checksum mismatch.\n' >&2; exit 2; }
for fact in \
  'safe_cases=3;rejected_cases=7;reason_codes=7' \
  'current_question_scan=pass;conversation_history_scan=pass;retrieved_content_scan=pass' \
  'injection_gate_contract_qualification=pass' \
  'script_53_injection_gate=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_INJECTION_REPORT" || { printf 'BLOCKED: required accepted Script 53 fact is absent.\n' >&2; exit 2; }
done

bash -n "$TEST_RUNNER"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' "$MODULE" "$TESTS" "$EVALUATOR"

work_root="$(mktemp -d /tmp/ishikawa-script-54.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-54.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
bash "$TEST_RUNNER" >"$test_result" 2>&1 || { cat "$test_result" >&2; printf 'script_54_sufficiency_gate=blocked;reason=test_regression\n' >&2; exit 1; }
grep -Fq 'Ran 195 tests' "$test_result" || { printf 'script_54_sufficiency_gate=blocked;reason=test_count_mismatch\n' >&2; exit 1; }
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || { printf 'script_54_sufficiency_gate=blocked;reason=test_pass_marker_absent\n' >&2; exit 1; }

profile_sha256="$(sha256sum "$PROFILE" | awk '{print $1}')"
reconstruction_profile_sha256="$(sha256sum "$RECONSTRUCTION_PROFILE" | awk '{print $1}')"
temporary_artifact="$work_root/sufficiency-gate-qualification.json"
evaluation_result="$work_root/evaluation.txt"
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B "$EVALUATOR" \
  --profile "$PROFILE" --expected-profile-sha256 "$profile_sha256" \
  --reconstruction-profile "$RECONSTRUCTION_PROFILE" \
  --expected-reconstruction-profile-sha256 "$reconstruction_profile_sha256" \
  --output "$temporary_artifact" >"$evaluation_result"
for fact in \
  'cases=13;sufficient=1;temporarily_unavailable=1;insufficient_evidence=9;context_limit=2' \
  'lane_health=pass;candidate_presence=pass;authorization=pass;exact_constraint=pass;relationship_coverage=pass' \
  'source_conflict=pass;reconstruction=pass;citation_set=pass;complete_structure=pass;context_limit=pass' \
  'calibrated_relevance_required=true;candidate_presence_is_not_relevance=true;uncalibrated_relevance_fails_closed=true' \
  'model_call=false;network_contact=false;database_contact=false;raw_text_retained=false' \
  'sufficiency_gate_contract_qualification=pass'; do
  grep -Fxq "$fact" "$evaluation_result" || { cat "$evaluation_result" >&2; printf 'script_54_sufficiency_gate=blocked;reason=evaluation_failed\n' >&2; exit 1; }
done

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
module_sha256="$(sha256sum "$MODULE" | awk '{print $1}')"
tests_sha256="$(sha256sum "$TESTS" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
contract_sha256="$(sha256sum "$CONTRACT_DOC" | awk '{print $1}')"
artifact_sha256="$(sha256sum "$temporary_artifact" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$temporary_artifact")"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_evidence_sufficiency_gate_source' \
    'target_contact=false;network_access=false;database_contact=false;model_call=false;credential_read=false' \
    "script_sha256=$script_sha256;module_sha256=$module_sha256;tests_sha256=$tests_sha256;evaluator_sha256=$evaluator_sha256" \
    "profile_sha256=$profile_sha256;reconstruction_profile_sha256=$reconstruction_profile_sha256;contract_sha256=$contract_sha256" \
    "accepted_injection_report_sha256=$ACCEPTED_INJECTION_REPORT_SHA256;qualification_artifact_sha256=$artifact_sha256;qualification_artifact_bytes=$artifact_bytes" \
    'local_tests=195;failures=0;errors=0' \
    'script_54_sufficiency_gate_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/sufficiency_gate_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || { printf 'script_54_sufficiency_gate=blocked;reason=artifact_path_exists\n' >&2; exit 1; }
cp -- "$temporary_artifact" "$artifact_path"
[[ "$(sha256sum "$artifact_path" | awk '{print $1}')" == "$artifact_sha256" ]] || { printf 'script_54_sufficiency_gate=blocked;reason=retained_artifact_identity_mismatch\n' >&2; exit 1; }
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true

report_path="$(mktemp "$REPORT_ROOT/sufficiency_gate_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=qualify_fail_closed_post_retrieval_evidence_sufficiency_gate_locally'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;module_sha256=$module_sha256;tests_sha256=$tests_sha256;evaluator_sha256=$evaluator_sha256"
emit "profile_sha256=$profile_sha256;reconstruction_profile_sha256=$reconstruction_profile_sha256;contract_sha256=$contract_sha256"
emit "accepted_injection_report_sha256=$ACCEPTED_INJECTION_REPORT_SHA256"
emit 'authorized_actions=read_checksum_bound_synthetic_inputs_run_local_tests_retain_content_free_qualification_artifact_and_report'
emit 'non_actions=no_target_contact_no_network_access_no_database_contact_no_model_call_no_credential_read_no_live_retrieval_no_source_document_read_no_service_configuration_or_schema_change'
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$artifact_bytes"
emit "accepted_checksum=$checksum_path;raw_text_retained=false"
emit 'local_tests=195;failures=0;errors=0'
emit "script_54_sufficiency_gate=pass;local_report=$report_path;next_gate=calibrate_relevance_with_responsive_and_nonresponsive_cases"
