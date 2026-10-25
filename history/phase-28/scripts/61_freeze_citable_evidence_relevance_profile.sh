#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Freeze and locally qualify the depth-three, sixty-percent citable-evidence
#   relevance profile against the accepted Script 60 observations.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/61_freeze_citable_evidence_relevance_profile.sh --run

usage() {
  sed -n '3,10p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Run locally and retain content-free acceptance evidence.' \
    '  --validate-only Validate sources and protected replay without retaining evidence.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$ISHIKAWA_ROOT/application/python"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly PROFILE="$ISHIKAWA_ROOT/config/templates/relevance_profile.yaml"
readonly MODULE="$PYTHON_ROOT/ishikawa/relevance.py"
readonly SUFFICIENCY_MODULE="$PYTHON_ROOT/ishikawa/sufficiency.py"
readonly TESTS="$ISHIKAWA_ROOT/tests/test_relevance.py"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_relevance_profile_contract.py"
readonly CONTRACT="$ISHIKAWA_ROOT/docs/RELEVANCE_CALIBRATION_CONTRACT.md"
readonly CASES="$REPO_ROOT/local/artifacts/ishikawa/relevance-calibration-input/relevance_cases_v1.json"
readonly CASES_SHA256='2fa6a20fc77f1faa25d141838b50ad0e95e2467035a0193d7f94451202cd94da'
readonly OBSERVATIONS="$REPO_ROOT/local/artifacts/ishikawa/relevance-retrieval-observations/relevance_retrieval_observations_20261020T050843Z.json"
readonly OBSERVATIONS_SHA256='e7a2481034abd86ef79bb02ff9c59065825bd88dc4971304b3bfd7613b7f4110'
readonly ACCEPTED_SCRIPT_60_REPORT="$REPO_ROOT/local/reports/ishikawa-citable-evidence-support/citable_evidence_support_20261020T050925Z_1AAOvP.txt"
readonly ACCEPTED_SCRIPT_60_REPORT_SHA256='93d7dceafd0e55fb1583af42178d04ea476485bb901a63e1489674489e311224'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-relevance-profile-freeze"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/relevance-profile-freeze"

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
  "$TEST_RUNNER" "$PROFILE" "$MODULE" "$SUFFICIENCY_MODULE" "$TESTS" \
  "$EVALUATOR" "$CONTRACT" "$CASES" "$OBSERVATIONS" "$ACCEPTED_SCRIPT_60_REPORT"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: a required Script 61 input is missing or unsafe.\n' >&2
    exit 2
  }
done
[[ "$(sha256sum "$CASES" | awk '{print $1}')" == "$CASES_SHA256" ]] || {
  printf 'BLOCKED: protected relevance-case identity changed.\n' >&2
  exit 2
}
[[ "$(sha256sum "$OBSERVATIONS" | awk '{print $1}')" == "$OBSERVATIONS_SHA256" ]] || {
  printf 'BLOCKED: accepted observation identity changed.\n' >&2
  exit 2
}
[[ "$(sha256sum "$ACCEPTED_SCRIPT_60_REPORT" | awk '{print $1}')" == "$ACCEPTED_SCRIPT_60_REPORT_SHA256" ]] || {
  printf 'BLOCKED: accepted Script 60 report identity changed.\n' >&2
  exit 2
}
for fact in \
  'depth_3_responsive_min=0.600000;responsive_max=0.833333;nonresponsive_min=0.142857;nonresponsive_max=0.500000;strict_separation=true' \
  'strictly_separating_depths=1,3,5,10;rule_candidate_eligible=true;threshold_selected=false' \
  'retrieval_profile_unchanged=true;exact_reference_routing=preserved;threshold_selected=false;model_authority=false;publication_eligible=false' \
  'temporary_database_dropped=true;accepted_database_unchanged=true;postgresql_restored_stopped_disabled=true' \
  'script_60_citable_evidence_support=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_SCRIPT_60_REPORT" || {
    printf 'BLOCKED: an accepted Script 60 fact is absent.\n' >&2
    exit 2
  }
done

bash -n "$TEST_RUNNER"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$MODULE" "$SUFFICIENCY_MODULE" "$TESTS" "$EVALUATOR"

work_root="$(mktemp -d /tmp/ishikawa-script-61.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-61.* && -d "$work_root" ]]; then
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
  printf 'script_61_relevance_profile_freeze=blocked;reason=test_regression\n' >&2
  exit 1
}
grep -Fq 'Ran 202 tests' "$test_result" || {
  printf 'script_61_relevance_profile_freeze=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_61_relevance_profile_freeze=blocked;reason=test_pass_marker_absent\n' >&2
  exit 1
}

profile_sha256="$(sha256sum "$PROFILE" | awk '{print $1}')"
temporary_artifact="$work_root/relevance-profile-qualification.json"
evaluation_result="$work_root/evaluation.txt"
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B "$EVALUATOR" \
  --profile "$PROFILE" --expected-profile-sha256 "$profile_sha256" \
  --cases "$CASES" --expected-cases-sha256 "$CASES_SHA256" \
  --observations "$OBSERVATIONS" --expected-observations-sha256 "$OBSERVATIONS_SHA256" \
  --output "$temporary_artifact" >"$evaluation_result"
for fact in \
  'fused_depth=3;minimum_support_numerator=3;minimum_support_denominator=5' \
  'cases=12;responsive_qualified=6;nonresponsive_insufficient=6;misclassified=0' \
  'comparison=supported_count_times_5_greater_than_or_equal_question_count_times_3' \
  'retrieval_ranking_changed=false;exact_reference_routing=preserved;model_authority=false' \
  'relevance_profile_contract_qualification=pass'; do
  grep -Fq "$fact" "$evaluation_result" || {
    cat "$evaluation_result" >&2
    printf 'script_61_relevance_profile_freeze=blocked;reason=protected_replay_failed\n' >&2
    exit 1
  }
done

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
module_sha256="$(sha256sum "$MODULE" | awk '{print $1}')"
sufficiency_module_sha256="$(sha256sum "$SUFFICIENCY_MODULE" | awk '{print $1}')"
tests_sha256="$(sha256sum "$TESTS" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
contract_sha256="$(sha256sum "$CONTRACT" | awk '{print $1}')"
artifact_sha256="$(sha256sum "$temporary_artifact" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$temporary_artifact")"
if [[ "$validate_only" == true ]]; then
  cat "$evaluation_result"
  printf '%s\n' \
    'purpose=validate_frozen_citable_evidence_relevance_profile' \
    'target_contact=false;network_access=false;database_contact=false;model_call=false;credential_read=false' \
    "script_sha256=$script_sha256;module_sha256=$module_sha256;sufficiency_module_sha256=$sufficiency_module_sha256;tests_sha256=$tests_sha256;evaluator_sha256=$evaluator_sha256" \
    "profile_sha256=$profile_sha256;contract_sha256=$contract_sha256;qualification_artifact_sha256=$artifact_sha256;qualification_artifact_bytes=$artifact_bytes" \
    "accepted_script_60_report_sha256=$ACCEPTED_SCRIPT_60_REPORT_SHA256;accepted_observations_sha256=$OBSERVATIONS_SHA256" \
    'local_tests=202;failures=0;errors=0' \
    'script_61_relevance_profile_freeze_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/relevance_profile_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  printf 'script_61_relevance_profile_freeze=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
cp -- "$temporary_artifact" "$artifact_path"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true

report_path="$(mktemp "$REPORT_ROOT/relevance_profile_freeze_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=freeze_depth_three_sixty_percent_citable_evidence_relevance_profile'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;module_sha256=$module_sha256;sufficiency_module_sha256=$sufficiency_module_sha256;tests_sha256=$tests_sha256;evaluator_sha256=$evaluator_sha256"
emit "profile_sha256=$profile_sha256;contract_sha256=$contract_sha256"
emit "accepted_script_60_report_sha256=$ACCEPTED_SCRIPT_60_REPORT_SHA256;accepted_observations_sha256=$OBSERVATIONS_SHA256"
emit 'authorized_actions=read_checksum_bound_local_evidence_run_local_tests_replay_protected_observations_retain_content_free_acceptance_evidence'
emit 'non_actions=no_target_contact_no_network_access_no_database_contact_no_model_call_no_credential_read_no_retrieval_change_no_schema_change'
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$artifact_bytes"
emit "accepted_checksum=$checksum_path;raw_text_retained=false"
emit 'local_tests=202;failures=0;errors=0'
emit "script_61_relevance_profile_freeze=pass;local_report=$report_path;next_gate=implement_retrieval_api_contract"
chmod 0600 "$report_path" 2>/dev/null || true
