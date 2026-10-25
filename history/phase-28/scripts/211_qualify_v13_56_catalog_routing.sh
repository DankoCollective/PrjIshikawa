#!/usr/bin/env bash
# Validate or run the consolidated V13-56 catalog-routing frontier gate.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/211_qualify_v13_56_catalog_routing.sh --validate-only
#   bash ./phase-28-apisachi-tokuli/scripts/211_qualify_v13_56_catalog_routing.sh --run

set -Eeuo pipefail
umask 077

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly INNER_GATE="$SCRIPT_DIR/201_ingest_and_qualify_isolated_synthetic_corpus_v3.sh"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_v1_3_catalog_routing.py"
readonly ROUTER="$PHASE_ROOT/Ishikawa/application/python/ishikawa/query_routing.py"
readonly ROUTER_TESTS="$PHASE_ROOT/Ishikawa/tests/test_query_routing.py"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v13-56-catalog-routing"
readonly GEMMA_PRIMARY_HEALTH='http://127.0.0.1:18000/health'
readonly GEMMA_LEGACY_HEALTH='http://127.0.0.1:8000/health'
readonly NOMIC_PRIMARY_HEALTH='http://127.0.0.1:18001/health'
readonly NOMIC_LEGACY_HEALTH='http://127.0.0.1:8001/health'

readonly INNER_GATE_SHA256='c13e37e4e3604a94714fe506a5ab907991b0393c90241d89a0d27035e3a8962e'
readonly EVALUATOR_SHA256='37145563d959aa3869e4c66d0f7d307db95c36acdafc4bf3a08064c986b2044d'
readonly ROUTER_SHA256='2431e3213464cd963afb7c1da0758703b3b6eb4d0e9790d00655c095188e0e44'
readonly ROUTER_TESTS_SHA256='a31cf9ffb047544b795780328c7d9e650cdf73286f0fad0a01fcc57cff8cc5ea'
readonly DECISIONS_SHA256='783ff03bf28236b43bbf83b9c345815bad8b3627d974d4e55675a5de3878ae74'

mode="${1:-}"
report_path=''
if [[ "$#" -ne 1 || ( "$mode" != '--validate-only' && "$mode" != '--run' ) ]]; then
  printf '%s\n' \
    'FAILURE DETAIL' \
    'stage=argument_validation' \
    'reason=exactly_one_supported_mode_required' \
    'detail=Script 211 requires exactly one of --validate-only or --run.' \
    'operator_action=Rerun Script 211 with one supported mode.' \
    '' \
    'SCRIPT RESULT' \
    'script_211_v13_56_catalog_routing_qualification=blocked' >&2
  exit 2
fi

block() {
  local stage="$1" reason="$2" detail="$3" action="$4"
  local payload
  payload="$(printf '%s\n' \
    'FAILURE DETAIL' \
    "stage=$stage" \
    "reason=$reason" \
    "detail=$detail" \
    "operator_action=$action" \
    '' \
    'SCRIPT RESULT' \
    'script_211_v13_56_catalog_routing_qualification=blocked')"
  printf '%s\n' "$payload" >&2
  if [[ -n "$report_path" && -f "$report_path" && ! -L "$report_path" ]]; then
    printf '%s\n' "$payload" >>"$report_path"
  fi
  exit 1
}

check_file() {
  local path="$1" expected="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] \
    || block preflight "${label}_unsafe" \
      "The required ${label} file is missing, unreadable, or a symbolic link." \
      'Restore the expected repository file and rerun this same command.'
  [[ "$(sha256sum -- "$path" | awk '{print $1}')" == "$expected" ]] \
    || block preflight "${label}_identity_changed" \
      "The required ${label} file changed after Script 211 was assembled." \
      'Review and deliberately rebind the changed source before qualification.'
}

for command_name in awk bash curl date grep mkdir mktemp python3 sha256sum tee; do
  command -v "$command_name" >/dev/null 2>&1 \
    || block preflight "local_command_missing_${command_name}" \
      "A required local command is unavailable: ${command_name}." \
      'Install or restore the named local command, then rerun this same command.'
done
check_file "$INNER_GATE" "$INNER_GATE_SHA256" inner_frontier_gate
check_file "$EVALUATOR" "$EVALUATOR_SHA256" catalog_routing_evaluator
check_file "$ROUTER" "$ROUTER_SHA256" catalog_router
check_file "$ROUTER_TESTS" "$ROUTER_TESTS_SHA256" catalog_router_tests
check_file "$DECISIONS" "$DECISIONS_SHA256" frozen_decisions
grep -Fq '| `V13-56` |' "$DECISIONS" \
  || block preflight v13_56_not_frozen \
    'The V13-56 frozen decision is absent.' \
    'Restore the frozen V13-56 decision and rerun this same command.'
bash -n "${BASH_SOURCE[0]}" "$INNER_GATE" \
  || block preflight shell_syntax_invalid \
    'The Script 211 or inner frontier shell source failed parsing.' \
    'Correct the named shell source before qualification.'
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" --self-test \
  | grep -Fxq 'v1_3_catalog_routing_evaluator_self_test=pass' \
  || block preflight evaluator_self_test_failed \
    'The catalog-routing evaluator rejected its internal positive or negative control.' \
    'Correct the evaluator contract before live qualification.'

endpoint_ready() {
  local endpoint="$1" status
  status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
    --connect-timeout 2 --max-time 5 "$endpoint" 2>/dev/null || true)"
  [[ "$status" == '200' ]]
}

if [[ "$mode" == '--validate-only' ]]; then
  if ! inner_validation="$(bash "$INNER_GATE" --validate-frontier 2>&1)"; then
    printf '%s\n' "$inner_validation" >&2
    block preflight inner_frontier_validation_failed \
      'The consolidated inner frontier preflight did not pass.' \
      'Run the same Script 211 command and use its printed inner blocker.'
  fi
  grep -Fxq 'script_201_isolated_corpus_v3_api_qualification=ready' \
    <<<"$inner_validation" \
    || block preflight inner_frontier_ready_marker_missing \
      'The inner frontier preflight omitted its exact ready marker.' \
      'Do not run the live gate until the inner marker is restored.'
  printf '%s\n' \
    'purpose=validate_v13_56_catalog_routing_and_complete_frontier_gate' \
    'catalog_routing_canaries=5;multiturn_canary=1;frontier_questions=60' \
    'database_contact=false;model_contact=false;credential_read=false;remote_contact=false' \
    '' \
    'SCRIPT RESULT' \
    'script_211_v13_56_catalog_routing_qualification=ready'
  exit 0
fi

# Check every operator-owned model dependency before the expensive native test,
# disposable-database, ingestion, and frontier sequence begins. This reports all
# absent forwards in one attempt and keeps Script 211 as the rerun entry point.
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
    'Start the documented 00Danko Gemma and Nomic SSH forwards, verify both local /health endpoints, then rerun Script 211.'
elif [[ "$gemma_ready" != true ]]; then
  block readiness gemma_forward_unavailable \
    'Gemma returned no HTTP 200 on ports 18000 or 8000; Nomic is reachable.' \
    'Restore the Gemma SSH forward, verify http://127.0.0.1:18000/health, then rerun Script 211.'
elif [[ "$nomic_ready" != true ]]; then
  block readiness nomic_forward_unavailable \
    'Nomic returned no HTTP 200 on ports 18001 or 8001; Gemma is reachable.' \
    'Restore the Nomic SSH forward, verify http://127.0.0.1:18001/health, then rerun Script 211.'
fi

mkdir -p -- "$REPORT_ROOT" \
  || block report_setup report_root_creation_failed \
    'The local V13-56 report directory could not be created.' \
    'Correct local report-directory permissions and rerun this same command.'
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/v13_56_catalog_routing_${timestamp}_XXXXXX.txt")" \
  || block report_setup report_creation_failed \
    'The local V13-56 report file could not be created.' \
    'Correct local report-directory permissions and rerun this same command.'

printf '%s\n' \
  'purpose=qualify_v13_56_catalog_routing_and_complete_frontier_gate' \
  'execution=one_command;catalog_routing_canaries=5;multiturn_canary=1;frontier_questions=60' \
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
    "The consolidated frontier gate failed;root_cause=${inner_root:-see_inner_failure_detail};exit_code=${inner_status}." \
    'Use the exact inner FAILURE DETAIL immediately above, correct every reported condition, then rerun Script 211.'
fi

grep -Fxq 'script_201_isolated_corpus_v3_api_qualification=pass' "$report_path" \
  || block acceptance inner_frontier_pass_marker_missing \
    'The inner gate exited zero without its exact pass marker.' \
    'Treat this execution as unqualified and inspect the retained local report.'
grep -Fxq 'qualification=pass;corpus_v3_database=pass;catalog_routing=5/5;multiturn_resolution=pass;frontier_60=pass;self_validation=pass' "$report_path" \
  || block acceptance consolidated_qualification_marker_missing \
    'One or more required catalog, multi-turn, corpus, or sixty-question gates did not report pass.' \
    'Treat this execution as unqualified and inspect the retained local report.'

{
  printf '%s\n' \
    'qualification=pass;v13_56_catalog_routing=5/5;multiturn_resolution=pass;frontier_60=pass' \
    'next_gate=local_human_ui_validation' \
    "local_report=$report_path"
  printf '\nSCRIPT RESULT\n'
  printf 'script_211_v13_56_catalog_routing_qualification=pass\n'
} | tee -a "$report_path"
