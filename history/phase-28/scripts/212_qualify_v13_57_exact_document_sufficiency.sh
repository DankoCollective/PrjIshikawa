#!/usr/bin/env bash
# Validate or run the consolidated V13-57 exact-document frontier gate.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/212_qualify_v13_57_exact_document_sufficiency.sh --validate-only
#   bash ./phase-28-apisachi-tokuli/scripts/212_qualify_v13_57_exact_document_sufficiency.sh --run

set -Eeuo pipefail
umask 077

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly INNER_GATE="$SCRIPT_DIR/201_ingest_and_qualify_isolated_synthetic_corpus_v3.sh"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_v1_3_catalog_routing.py"
readonly SUFFICIENCY="$PHASE_ROOT/Ishikawa/application/python/ishikawa/sufficiency.py"
readonly RETRIEVAL="$PHASE_ROOT/Ishikawa/application/python/ishikawa/postgres_retrieval.py"
readonly SERVICE="$PHASE_ROOT/Ishikawa/application/python/ishikawa/retrieval_service.py"
readonly PROFILE="$PHASE_ROOT/Ishikawa/config/templates/sufficiency_profile.yaml"
readonly SUFFICIENCY_TESTS="$PHASE_ROOT/Ishikawa/tests/test_sufficiency.py"
readonly RETRIEVAL_TESTS="$PHASE_ROOT/Ishikawa/tests/test_postgres_retrieval.py"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v13-57-exact-document-sufficiency"
readonly GEMMA_PRIMARY_HEALTH='http://127.0.0.1:18000/health'
readonly GEMMA_LEGACY_HEALTH='http://127.0.0.1:8000/health'
readonly NOMIC_PRIMARY_HEALTH='http://127.0.0.1:18001/health'
readonly NOMIC_LEGACY_HEALTH='http://127.0.0.1:8001/health'

readonly INNER_GATE_SHA256='e91f3d031165f868efe29a53a6147e4f5a84fd2e0891546b74f3716c1242c9a7'
readonly EVALUATOR_SHA256='7ab0f8352ef78245697d1f363cca70705d09afc1f7692043e09d49565536426f'
readonly SUFFICIENCY_SHA256='8edfaaea3d2898fb2bf4629c28708f2a7c65be272895083ae86331200d295934'
readonly RETRIEVAL_SHA256='8ba35725d146b40cfcdf1f6e0d724b74e4749faffa456c4833984ae72e2d3964'
readonly SERVICE_SHA256='bd07e24dc871f3ea7648efbb284cac15aab4384ad0f5947b70a46ce583af8531'
readonly PROFILE_SHA256='5ea2fa1010a64252165e47221e81b5467aa56bc644ae583ab4d967bbba175103'
readonly SUFFICIENCY_TESTS_SHA256='af7f759fb616fa886fdff9685b0eb054596a787bf54b09b584801d6678761be4'
readonly RETRIEVAL_TESTS_SHA256='0c439be06cc2bddce5ad48c3f0709f1a2f41c039bce79c30fba958c5ede1ff20'
readonly DECISIONS_SHA256='af06d8bf5b9a826ffdf8588d2333b229354594724f425ac0e195a14f29b70274'

mode="${1:-}"
report_path=''

result() {
  printf '\nSCRIPT RESULT\nscript_212_v13_57_exact_document_sufficiency=%s\n' "$1"
}

block() {
  local stage="$1" reason="$2" detail="$3" action="$4" payload
  payload="$(printf '%s\n' \
    'FAILURE DETAIL' \
    "stage=$stage" \
    "reason=$reason" \
    "detail=$detail" \
    "operator_action=$action")"
  printf '%s\n' "$payload" >&2
  if [[ -n "$report_path" && -f "$report_path" && ! -L "$report_path" ]]; then
    printf '%s\n' "$payload" >>"$report_path"
    result blocked >>"$report_path"
  fi
  result blocked >&2
  exit 1
}

if [[ "$#" -ne 1 || ( "$mode" != '--validate-only' && "$mode" != '--run' ) ]]; then
  block argument_validation exactly_one_supported_mode_required \
    'Script 212 requires exactly one of --validate-only or --run.' \
    'Rerun Script 212 with one supported mode.'
fi

check_file() {
  local path="$1" expected="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] \
    || block preflight "${label}_unsafe" \
      "The required ${label} file is missing, unreadable, or a symbolic link." \
      'Restore the expected repository file and rerun Script 212.'
  [[ "$(sha256sum -- "$path" | awk '{print $1}')" == "$expected" ]] \
    || block preflight "${label}_identity_changed" \
      "The required ${label} file changed after Script 212 was assembled." \
      'Review and deliberately rebind every changed source before qualification.'
}

for command_name in awk bash curl date grep mkdir mktemp python3 sed sha256sum tee; do
  command -v "$command_name" >/dev/null 2>&1 \
    || block preflight "local_command_missing_${command_name}" \
      "A required local command is unavailable: ${command_name}." \
      'Install or restore the named command, then rerun Script 212.'
done

check_file "$INNER_GATE" "$INNER_GATE_SHA256" inner_frontier_gate
check_file "$EVALUATOR" "$EVALUATOR_SHA256" exact_document_evaluator
check_file "$SUFFICIENCY" "$SUFFICIENCY_SHA256" sufficiency_implementation
check_file "$RETRIEVAL" "$RETRIEVAL_SHA256" retrieval_implementation
check_file "$SERVICE" "$SERVICE_SHA256" retrieval_service_contract
check_file "$PROFILE" "$PROFILE_SHA256" sufficiency_profile
check_file "$SUFFICIENCY_TESTS" "$SUFFICIENCY_TESTS_SHA256" sufficiency_tests
check_file "$RETRIEVAL_TESTS" "$RETRIEVAL_TESTS_SHA256" retrieval_tests
check_file "$DECISIONS" "$DECISIONS_SHA256" frozen_decisions
grep -Fq '| `V13-57` |' "$DECISIONS" \
  || block preflight v13_57_not_frozen \
    'The V13-57 frozen decision is absent.' \
    'Restore the frozen V13-57 decision and rerun Script 212.'
bash -n "${BASH_SOURCE[0]}" "$INNER_GATE" \
  || block preflight shell_syntax_invalid \
    'Script 212 or its consolidated inner frontier gate failed shell parsing.' \
    'Correct every reported shell error before qualification.'
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" --self-test \
  | grep -Fxq 'v1_3_catalog_routing_evaluator_self_test=pass' \
  || block preflight evaluator_self_test_failed \
    'The seven-case evaluator rejected its positive or negative controls.' \
    'Correct the evaluator contract before live qualification.'

if ! inner_validation="$(bash "$INNER_GATE" --validate-frontier 2>&1)"; then
  printf '%s\n' "$inner_validation" >&2
  block preflight inner_frontier_validation_failed \
    'The consolidated native, ingestion, canary, and frontier preflight did not pass.' \
    'Use the exact inner failure above, correct all reported conditions, and rerun Script 212.'
fi
grep -Fxq 'script_201_isolated_corpus_v3_api_qualification=ready' \
  <<<"$inner_validation" \
  || block preflight inner_frontier_ready_marker_missing \
    'The inner frontier preflight omitted its exact ready marker.' \
    'Do not run the live gate until the inner ready marker is restored.'

if [[ "$mode" == '--validate-only' ]]; then
  printf '%s\n' \
    'purpose=validate_v13_57_exact_document_sufficiency_and_complete_frontier_gate' \
    'exact_document_canaries=2;catalog_canaries=5;multiturn_canary=1;frontier_questions=60' \
    'native_regression=483/483;database_contact=false;model_contact=false;credential_read=false;remote_contact=false'
  result ready
  exit 0
fi

endpoint_ready() {
  local endpoint="$1" status
  status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
    --connect-timeout 2 --max-time 5 "$endpoint" 2>/dev/null || true)"
  [[ "$status" == '200' ]]
}

gemma_ready=false
nomic_ready=false
if endpoint_ready "$GEMMA_PRIMARY_HEALTH" \
  || endpoint_ready "$GEMMA_LEGACY_HEALTH"; then
  gemma_ready=true
fi
if endpoint_ready "$NOMIC_PRIMARY_HEALTH" \
  || endpoint_ready "$NOMIC_LEGACY_HEALTH"; then
  nomic_ready=true
fi
if [[ "$gemma_ready" != true && "$nomic_ready" != true ]]; then
  block readiness gemma_and_nomic_forwards_unavailable \
    'Gemma returned no HTTP 200 on ports 18000/8000, and Nomic returned no HTTP 200 on ports 18001/8001.' \
    'Start both documented 00Danko forwards, verify both local health endpoints, and rerun Script 212.'
elif [[ "$gemma_ready" != true ]]; then
  block readiness gemma_forward_unavailable \
    'Gemma returned no HTTP 200 on ports 18000 or 8000; Nomic is reachable.' \
    'Restore the Gemma forward, verify its local health endpoint, and rerun Script 212.'
elif [[ "$nomic_ready" != true ]]; then
  block readiness nomic_forward_unavailable \
    'Nomic returned no HTTP 200 on ports 18001 or 8001; Gemma is reachable.' \
    'Restore the Nomic forward, verify its local health endpoint, and rerun Script 212.'
fi

mkdir -p -- "$REPORT_ROOT" \
  || block report_setup report_root_creation_failed \
    'The local V13-57 report directory could not be created.' \
    'Correct local report-directory permissions and rerun Script 212.'
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/v13_57_exact_document_sufficiency_${timestamp}_XXXXXX.txt")" \
  || block report_setup report_creation_failed \
    'The local V13-57 report file could not be created.' \
    'Correct local report-directory permissions and rerun Script 212.'

printf '%s\n' \
  'purpose=qualify_v13_57_exact_document_sufficiency_and_complete_frontier_gate' \
  'execution=one_command;exact_document_canaries=2;catalog_canaries=5;multiturn_canary=1;frontier_questions=60' \
  'non_actions=no_black_corpus_no_remote_host_no_package_or_release_change_no_autostart' \
  | tee -a "$report_path"

set +e
bash "$INNER_GATE" --run-frontier 2>&1 | tee -a "$report_path"
inner_status="${PIPESTATUS[0]}"
set -e
if (( inner_status != 0 )); then
  inner_stage="$(sed -n 's/^stage=\([a-z0-9_]*\)$/\1/p' "$report_path" | tail -n 1)"
  inner_reason="$(sed -n 's/^reason=\([a-z0-9_]*\)$/\1/p' "$report_path" | tail -n 1)"
  inner_root="$(sed -n 's/^root_cause=\([a-z0-9_]*\)$/\1/p' "$report_path" | tail -n 1)"
  printf 'local_report=%s\n' "$report_path"
  block "${inner_stage:-inner_frontier_gate}" \
    "${inner_reason:-inner_frontier_gate_failed}" \
    "The consolidated gate failed;root_cause=${inner_root:-see_inner_failure_detail};exit_code=${inner_status}." \
    'Use the exact inner FAILURE DETAIL above, correct every reported condition, and rerun Script 212.'
fi

grep -Fxq 'script_201_isolated_corpus_v3_api_qualification=pass' "$report_path" \
  || block acceptance inner_frontier_pass_marker_missing \
    'The inner gate exited zero without its exact pass marker.' \
    'Treat this execution as unqualified and inspect the retained report.'
grep -Fxq 'qualification=pass;corpus_v3_database=pass;catalog_routing=7/7;multiturn_resolution=pass;frontier_60=pass;self_validation=pass' "$report_path" \
  || block acceptance consolidated_qualification_marker_missing \
    'One or more exact-document, catalog, multi-turn, corpus, or sixty-question gates did not report pass.' \
    'Treat this execution as unqualified and inspect the retained report.'

{
  printf '%s\n' \
    'qualification=pass;v13_57_exact_document=2/2;catalog_routing=7/7;multiturn_resolution=pass;frontier_60=pass' \
    'next_gate=local_human_ui_validation' \
    "local_report=$report_path"
  result pass
} | tee -a "$report_path"
