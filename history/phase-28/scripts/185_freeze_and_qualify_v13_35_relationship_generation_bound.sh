#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Bind the operator's V13-35 freeze to the bounded relationship-generation
#   implementation and qualify the complete local Python application surface.
#
# Boundaries:
#   Local source, frozen decision record, and retained content-free Script 184
#   classification only. No model, database, credential, corpus, truth,
#   retrieval profile, package, release, remote host, or org-lab contact.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/185_freeze_and_qualify_v13_35_relationship_generation_bound.sh --run

usage() {
  sed -n '3,15p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Execute targeted and complete local qualification.' \
    '  --validate-only Validate frozen inputs and script structure only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly TEST_ROOT="$PRODUCT_ROOT/tests"
readonly RECONSTRUCTION="$PYTHON_ROOT/ishikawa/reconstruction.py"
readonly RECONSTRUCTION_TEST="$TEST_ROOT/test_reconstruction.py"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly TEST_RUNNER="$PRODUCT_ROOT/scripts/run-local-validation-tests.sh"
readonly SCRIPT_184_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.3-generation-failure-classification/generation_failure_20261023T034836Z_YcAoss.txt"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.3-v13-35-relationship-generation-bound"

readonly RECONSTRUCTION_SHA256='76d90d1c1daea43e056c47e9421cb5a03e23fb2eed516f409172e7c64d2cc5df'
readonly RECONSTRUCTION_TEST_SHA256='851875736396fb2868896fcec8028c5912587d9614a43c5d906fe960696c0b31'
readonly DECISIONS_SHA256='17de80710bdc8f842a8853c0510deba8623ae922419b3e0c2398a698d48646e0'
readonly TEST_RUNNER_SHA256='092b2cb8e5254d1ca2b6e71a496bf76743004134848e249d5d7b9f37d9d62eb7'
readonly SCRIPT_184_REPORT_SHA256='a6fe9d7947e2b5afe594c82e9392ed7bdd490f64df069606d079a2f5d318b40d'
readonly EXPECTED_NATIVE_TESTS=438
readonly EXPECTED_RELATIONSHIP_GROUP_LIMIT=3

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      printf 'reason=argument_invalid\n\nSCRIPT RESULT\nscript_185_v13_35_relationship_generation_bound=blocked\n' >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'reason=mode_invalid\n\nSCRIPT RESULT\nscript_185_v13_35_relationship_generation_bound=blocked\n' >&2
  exit 2
}

preflight_block() {
  printf 'reason=%s\n\nSCRIPT RESULT\nscript_185_v13_35_relationship_generation_bound=blocked\n' "$1" >&2
  exit "${2:-2}"
}

for command_name in awk bash date grep mkdir mktemp python3 rm sed sha256sum \
  tail tee timeout; do
  command -v "$command_name" >/dev/null 2>&1 \
    || preflight_block "local_command_missing_$command_name"
done

check_file() {
  local path="$1" expected="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] \
    || preflight_block "${label}_unsafe"
  [[ "$(sha256sum "$path" | awk '{print $1}')" == "$expected" ]] \
    || preflight_block "${label}_identity_changed"
}

check_file "$RECONSTRUCTION" "$RECONSTRUCTION_SHA256" reconstruction
check_file "$RECONSTRUCTION_TEST" "$RECONSTRUCTION_TEST_SHA256" reconstruction_test
check_file "$DECISIONS" "$DECISIONS_SHA256" decisions
check_file "$TEST_RUNNER" "$TEST_RUNNER_SHA256" test_runner
check_file "$SCRIPT_184_REPORT" "$SCRIPT_184_REPORT_SHA256" script_184_report
[[ -x "$TEST_RUNNER" ]] || preflight_block test_runner_not_executable

grep -Eq '^\| `V13-35` \|.*at most the three highest-ranked query-responsive relationship identities.*\| FROZEN \|$' \
  "$DECISIONS" || preflight_block v13_35_freeze_record_invalid 1
grep -Fxq 'failure_families=response_validation,response_validation;reason_codes=MODEL_COMPLETION_INCOMPLETE,MODEL_REQUIRED_CITATION_GROUP_MISSING;attempts=2' \
  "$SCRIPT_184_REPORT" || preflight_block script_184_classification_invalid 1
grep -Fxq 'script_184_generation_failure_classification=pass' \
  "$SCRIPT_184_REPORT" || preflight_block script_184_not_clean 1
grep -Fxq 'milestone=observed_script_183;state=pass;target=first_turn_with_two_failed_attempts;attempts=2;cleanup=verified' \
  "$SCRIPT_184_REPORT" || preflight_block script_184_cleanup_not_verified 1

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$RECONSTRUCTION" "$RECONSTRUCTION_TEST"
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B - <<'PY'
from ishikawa import reconstruction

assert reconstruction._MAX_GENERATION_RELATIONSHIP_GROUPS == 3
PY

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_v13_35_relationship_generation_bound' \
    "script_sha256=$script_sha256;decision=V13-35;relationship_group_limit=$EXPECTED_RELATIONSHIP_GROUP_LIMIT" \
    "reconstruction_sha256=$RECONSTRUCTION_SHA256;reconstruction_test_sha256=$RECONSTRUCTION_TEST_SHA256" \
    "script_184_report_sha256=$SCRIPT_184_REPORT_SHA256;expected_native_tests=$EXPECTED_NATIVE_TESTS" \
    'database_contact=false;model_contact=false;credential_read=false;corpus_changed=false;truth_changed=false;retrieval_profile_changed=false;package_changed=false;release_changed=false' \
    '' \
    'SCRIPT RESULT' \
    'script_185_v13_35_relationship_generation_bound=pass'
  exit 0
fi

umask 077
mkdir -p -- "$REPORT_ROOT" || preflight_block report_root_creation_failed
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" && -w "$REPORT_ROOT" ]] \
  || preflight_block report_root_unsafe
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/v13_35_relationship_generation_bound_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-script-185.XXXXXX)"
failure_reason=''
qualification_complete=false
current_stage='runtime_initialization'
readonly MAIN_BASHPID="$BASHPID"

emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
block() { failure_reason="$1"; exit "${2:-1}"; }
record_unexpected_error() {
  local status="$1"
  if [[ "$BASHPID" == "$MAIN_BASHPID" && -z "$failure_reason" ]]; then
    failure_reason="${current_stage}_unexpected_exit_${status}"
  fi
}
cleanup() {
  local status="$?" result=blocked
  trap - ERR EXIT HUP INT TERM
  set +e
  [[ "$work_root" == /tmp/ishikawa-script-185.* && -d "$work_root" ]] \
    && rm -rf -- "$work_root"
  if (( status == 0 )) && [[ "$qualification_complete" == true ]]; then
    result=pass
  else
    status=1
    [[ -n "$failure_reason" ]] || failure_reason="${current_stage}_unexpected_exit"
  fi
  emit "local_report=$report_path"
  {
    printf '\nSCRIPT RESULT\n'
    [[ "$result" == pass ]] || printf 'reason=%s\n' "$failure_reason"
    printf 'script_185_v13_35_relationship_generation_bound=%s\n' "$result"
  } | tee -a "$report_path"
  exit "$status"
}
trap 'record_unexpected_error $?' ERR
trap cleanup EXIT
trap 'failure_reason=interrupted_HUP; exit 129' HUP
trap 'failure_reason=interrupted_INT; exit 130' INT
trap 'failure_reason=interrupted_TERM; exit 143' TERM

emit 'purpose=freeze_and_qualify_v13_35_relationship_generation_bound'
emit "started_utc=$timestamp;script_sha256=$script_sha256;decision=V13-35"
emit "relationship_group_limit=$EXPECTED_RELATIONSHIP_GROUP_LIMIT;reconstruction_sha256=$RECONSTRUCTION_SHA256;reconstruction_test_sha256=$RECONSTRUCTION_TEST_SHA256"
emit "script_184_report_sha256=$SCRIPT_184_REPORT_SHA256;expected_native_tests=$EXPECTED_NATIVE_TESTS"
emit 'authorized_actions=inspect_frozen_decision_and_content_free_prior_diagnostic_run_targeted_relationship_tests_run_complete_local_native_regression_write_content_free_local_report'
emit 'non_actions=no_database_contact_no_model_contact_no_credential_read_no_corpus_truth_or_retrieval_profile_change_no_package_or_release_change_no_remote_host_no_service_change_no_org_lab_change'

current_stage=targeted_relationship_tests
targeted_output="$work_root/targeted-tests.txt"
if ! (
  cd -- "$PRODUCT_ROOT"
  PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" \
    timeout --signal=TERM --kill-after=5s 60s python3 -B -m unittest -v \
    tests.test_reconstruction.BudgetAndGroupingTests.test_generation_admits_only_three_highest_ranked_relationship_groups \
    tests.test_reconstruction.BudgetAndGroupingTests.test_excluded_relationship_route_does_not_remove_same_direct_atom \
    tests.test_reconstruction.BudgetAndGroupingTests.test_relationship_limit_counts_identities_not_structural_atoms
) >"$targeted_output" 2>&1; then
  tail -n 120 "$targeted_output" | tee -a "$report_path" >&2
  block targeted_relationship_tests_failed
fi
grep -Eq '^Ran 3 tests in [0-9.]+s$' "$targeted_output" \
  || block targeted_relationship_test_count_invalid
grep -Fxq 'OK' "$targeted_output" || block targeted_relationship_tests_not_clean
emit 'milestone=targeted_relationship_tests;state=pass;tests=3;admitted_groups=3;identity_not_atom_counting=true;direct_duplicate_preserved=true'

current_stage=native_regression
native_output="$work_root/native-tests.txt"
if ! timeout --signal=TERM --kill-after=10s 180s "$TEST_RUNNER" \
  >"$native_output" 2>&1; then
  tail -n 160 "$native_output" | tee -a "$report_path" >&2
  block native_regression_failed
fi
grep -Eq "^Ran ${EXPECTED_NATIVE_TESTS} tests in [0-9.]+s$" "$native_output" \
  || block native_test_count_invalid
grep -Fxq 'OK' "$native_output" || block native_regression_not_clean
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$native_output" \
  || block native_result_marker_absent
emit "milestone=native_regression;state=pass;tests=$EXPECTED_NATIVE_TESTS"
emit 'retrieval_traversal_changed=false;retrieval_ranking_changed=false;published_relationships_changed=false;answer_token_reserve_changed=false;citation_validator_changed=false'
emit 'generation_selection=top_three_relationship_identities_by_seed_fused_rank;admitted_seed_target_coverage=required;excluded_direct_duplicate=preserved'
emit 'next_gate=unchanged_complete_13_case_api_and_gemma_qualification'
qualification_complete=true
current_stage=complete
