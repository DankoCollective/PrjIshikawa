#!/usr/bin/env bash
# Validate or run the consolidated V13-59 exact-document citation gate.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/215_qualify_v13_59_exact_document_citation_coverage.sh --validate-only
#   bash ./phase-28-apisachi-tokuli/scripts/215_qualify_v13_59_exact_document_citation_coverage.sh --run

set -Eeuo pipefail
umask 077

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly INNER_GATE="$SCRIPT_DIR/201_ingest_and_qualify_isolated_synthetic_corpus_v3.sh"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_v1_3_catalog_routing.py"
readonly QUERY_ROUTING="$PHASE_ROOT/Ishikawa/application/python/ishikawa/query_routing.py"
readonly QUERY_ROUTING_TESTS="$PHASE_ROOT/Ishikawa/tests/test_query_routing.py"
readonly POSTGRES_RETRIEVAL="$PHASE_ROOT/Ishikawa/application/python/ishikawa/postgres_retrieval.py"
readonly POSTGRES_RETRIEVAL_TESTS="$PHASE_ROOT/Ishikawa/tests/test_postgres_retrieval.py"
readonly GENERATION="$PHASE_ROOT/Ishikawa/application/python/ishikawa/generation.py"
readonly GENERATION_TRANSPORT="$PHASE_ROOT/Ishikawa/application/python/ishikawa/generation_transport.py"
readonly GENERATION_TESTS="$PHASE_ROOT/Ishikawa/tests/test_generation.py"
readonly GENERATION_TRANSPORT_TESTS="$PHASE_ROOT/Ishikawa/tests/test_generation_transport.py"
readonly SUFFICIENCY="$PHASE_ROOT/Ishikawa/application/python/ishikawa/sufficiency.py"
readonly RETRIEVAL_SERVICE="$PHASE_ROOT/Ishikawa/application/python/ishikawa/retrieval_service.py"
readonly PROFILE="$PHASE_ROOT/Ishikawa/config/templates/sufficiency_profile.yaml"
readonly SUFFICIENCY_TESTS="$PHASE_ROOT/Ishikawa/tests/test_sufficiency.py"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v13-59-exact-document-citation-coverage"
readonly GEMMA_PRIMARY_HEALTH='http://127.0.0.1:18000/health'
readonly GEMMA_LEGACY_HEALTH='http://127.0.0.1:8000/health'
readonly NOMIC_PRIMARY_HEALTH='http://127.0.0.1:18001/health'
readonly NOMIC_LEGACY_HEALTH='http://127.0.0.1:8001/health'

readonly INNER_GATE_SHA256='2a0e54486be26ccb1211be981dfb4e9e9720745e1417f9f3f0e1748df8647dc6'
readonly EVALUATOR_SHA256='eef7b37a401b69ea29d57c7f9719ed00ab6c093fdad9f0b1c7e46cf20bb3507e'
readonly QUERY_ROUTING_SHA256='b682569fcb5b3c93bd4b782be1106754ccdc0668664f46691b8a88d94c0c0de4'
readonly QUERY_ROUTING_TESTS_SHA256='359ac8b5be3cd77ed46017f5aca6e620904d8da25f01221acde7a16ee75910e1'
readonly POSTGRES_RETRIEVAL_SHA256='98778a3740dc6f500a8c2c11609a36d184d2f40e8a774feb14ff20b605a52e3d'
readonly POSTGRES_RETRIEVAL_TESTS_SHA256='4bf4a88bb8419708233b0c20773550b46bf7c63d06365a20127f19686dc057b3'
readonly GENERATION_SHA256='8e525629f7fa0f2b4b5279c55e65c5e9892b944b0eacf2fef03e1f14d1469787'
readonly GENERATION_TRANSPORT_SHA256='535e195c89cb7849988a9a6e17dbf97bd9de67e12f09ee73b79fc7e65560f69c'
readonly GENERATION_TESTS_SHA256='bde0e3dadf0027bca4cc6b2a613034426abf2418d2fdadc70536a1a8c82a147a'
readonly GENERATION_TRANSPORT_TESTS_SHA256='e480e1b4bf3168ba9385fbcec3e207aeaf941ecafd5854780f28a2ea09ce39a4'
readonly SUFFICIENCY_SHA256='8edfaaea3d2898fb2bf4629c28708f2a7c65be272895083ae86331200d295934'
readonly RETRIEVAL_SERVICE_SHA256='bd07e24dc871f3ea7648efbb284cac15aab4384ad0f5947b70a46ce583af8531'
readonly PROFILE_SHA256='5ea2fa1010a64252165e47221e81b5467aa56bc644ae583ab4d967bbba175103'
readonly SUFFICIENCY_TESTS_SHA256='af7f759fb616fa886fdff9685b0eb054596a787bf54b09b584801d6678761be4'
readonly DECISIONS_SHA256='02e796dbf2327d506de440ef27a9436388598385411bd61f2087319e37fa091f'

mode="${1:-}"
report_path=''

result() {
  printf '\nSCRIPT RESULT\nscript_215_v13_59_exact_document_citation_coverage=%s\n' "$1"
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
    'Script 215 requires exactly one of --validate-only or --run.' \
    'Rerun Script 215 with one supported mode.'
fi

check_file() {
  local path="$1" expected="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] \
    || block preflight "${label}_unsafe" \
      "The required ${label} file is missing, unreadable, or a symbolic link." \
      'Restore the expected repository file and rerun Script 215.'
  [[ "$(sha256sum -- "$path" | awk '{print $1}')" == "$expected" ]] \
    || block preflight "${label}_identity_changed" \
      "The required ${label} file changed after Script 215 was assembled." \
      'Review and deliberately rebind every changed source before qualification.'
}

for command_name in awk bash curl date grep mkdir mktemp python3 sed sha256sum tee; do
  command -v "$command_name" >/dev/null 2>&1 \
    || block preflight "local_command_missing_${command_name}" \
      "A required local command is unavailable: ${command_name}." \
      'Install or restore the named command, then rerun Script 215.'
done

check_file "$INNER_GATE" "$INNER_GATE_SHA256" inner_frontier_gate
check_file "$EVALUATOR" "$EVALUATOR_SHA256" catalog_routing_evaluator
check_file "$QUERY_ROUTING" "$QUERY_ROUTING_SHA256" query_routing_implementation
check_file "$QUERY_ROUTING_TESTS" "$QUERY_ROUTING_TESTS_SHA256" query_routing_tests
check_file "$POSTGRES_RETRIEVAL" "$POSTGRES_RETRIEVAL_SHA256" postgres_retrieval_implementation
check_file "$POSTGRES_RETRIEVAL_TESTS" "$POSTGRES_RETRIEVAL_TESTS_SHA256" postgres_retrieval_tests
check_file "$GENERATION" "$GENERATION_SHA256" generation_contract
check_file "$GENERATION_TRANSPORT" "$GENERATION_TRANSPORT_SHA256" generation_transport
check_file "$GENERATION_TESTS" "$GENERATION_TESTS_SHA256" generation_tests
check_file "$GENERATION_TRANSPORT_TESTS" "$GENERATION_TRANSPORT_TESTS_SHA256" generation_transport_tests
check_file "$SUFFICIENCY" "$SUFFICIENCY_SHA256" sufficiency_implementation
check_file "$RETRIEVAL_SERVICE" "$RETRIEVAL_SERVICE_SHA256" retrieval_service_contract
check_file "$PROFILE" "$PROFILE_SHA256" sufficiency_profile
check_file "$SUFFICIENCY_TESTS" "$SUFFICIENCY_TESTS_SHA256" sufficiency_tests
check_file "$DECISIONS" "$DECISIONS_SHA256" frozen_decisions
grep -Fq '| `V13-59` |' "$DECISIONS" \
  || block preflight v13_59_not_frozen \
    'The V13-59 frozen decision is absent.' \
    'Restore the frozen V13-59 decision and rerun Script 215.'
bash -n "${BASH_SOURCE[0]}" "$INNER_GATE" \
  || block preflight shell_syntax_invalid \
    'Script 215 or its consolidated inner frontier gate failed shell parsing.' \
    'Correct every reported shell error before qualification.'
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" --self-test \
  | grep -Fxq 'v1_3_catalog_routing_evaluator_self_test=pass' \
  || block preflight evaluator_self_test_failed \
    'The nine-case catalog evaluator rejected its positive or negative controls.' \
    'Correct the evaluator contract before live qualification.'

if ! inner_validation="$(bash "$INNER_GATE" --validate-frontier 2>&1)"; then
  printf '%s\n' "$inner_validation" >&2
  block preflight inner_frontier_validation_failed \
    'The consolidated native, ingestion, canary, and frontier preflight did not pass.' \
    'Use the exact inner failure above, correct all reported conditions, and rerun Script 215.'
fi
grep -Fxq 'script_201_isolated_corpus_v3_api_qualification=ready' \
  <<<"$inner_validation" \
  || block preflight inner_frontier_ready_marker_missing \
    'The inner frontier preflight omitted its exact ready marker.' \
    'Do not run the live gate until the inner ready marker is restored.'

if [[ "$mode" == '--validate-only' ]]; then
  printf '%s\n' \
    'purpose=validate_v13_59_exact_document_citation_coverage_and_complete_frontier_gate' \
    'catalog_canaries=9;multiturn_canary=1;frontier_questions=60' \
    'native_regression=486/486;database_contact=false;model_contact=false;credential_read=false;remote_contact=false'
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
    'Start both documented 00Danko forwards, verify both local health endpoints, and rerun Script 215.'
elif [[ "$gemma_ready" != true ]]; then
  block readiness gemma_forward_unavailable \
    'Gemma returned no HTTP 200 on ports 18000 or 8000; Nomic is reachable.' \
    'Restore the Gemma forward, verify its local health endpoint, and rerun Script 215.'
elif [[ "$nomic_ready" != true ]]; then
  block readiness nomic_forward_unavailable \
    'Nomic returned no HTTP 200 on ports 18001 or 8001; Gemma is reachable.' \
    'Restore the Nomic forward, verify its local health endpoint, and rerun Script 215.'
fi

mkdir -p -- "$REPORT_ROOT" \
  || block report_setup report_root_creation_failed \
    'The local V13-59 report directory could not be created.' \
    'Correct local report-directory permissions and rerun Script 215.'
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/v13_59_exact_document_citation_coverage_${timestamp}_XXXXXX.txt")" \
  || block report_setup report_creation_failed \
    'The local V13-59 report file could not be created.' \
    'Correct local report-directory permissions and rerun Script 215.'

printf '%s\n' \
  'purpose=qualify_v13_59_exact_document_citation_coverage_and_complete_frontier_gate' \
  'execution=one_command;catalog_canaries=9;multiturn_canary=1;frontier_questions=60' \
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
    'Use the exact inner FAILURE DETAIL above, correct every reported condition, and rerun Script 215.'
fi

grep -Fxq 'script_201_isolated_corpus_v3_api_qualification=pass' "$report_path" \
  || block acceptance inner_frontier_pass_marker_missing \
    'The inner gate exited zero without its exact pass marker.' \
    'Treat this execution as unqualified and inspect the retained report.'
grep -Fxq 'qualification=pass;corpus_v3_database=pass;catalog_routing=9/9;multiturn_resolution=pass;frontier_60=pass;self_validation=pass' "$report_path" \
  || block acceptance consolidated_qualification_marker_missing \
    'One or more catalog, multi-turn, corpus, or sixty-question gates did not report pass.' \
    'Treat this execution as unqualified and inspect the retained report.'

{
  printf '%s\n' \
    'qualification=pass;v13_59_exact_document_citation_coverage=pass;catalog_routing=9/9;multiturn_resolution=pass;frontier_60=pass' \
    'next_gate=local_human_ui_validation' \
    "local_report=$report_path"
  result pass
} | tee -a "$report_path"
