#!/usr/bin/env bash
# Qualify the V13-55 multi-turn resolution correction, its exact live canary,
# and the unchanged sixty-question corpus-v3 frontier gate in one execution.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/209_qualify_v13_55_multiturn_resolution.sh --validate-only
#   bash ./phase-28-apisachi-tokuli/scripts/209_qualify_v13_55_multiturn_resolution.sh --run

set -Eeuo pipefail
umask 077

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly INNER_GATE="$SCRIPT_DIR/201_ingest_and_qualify_isolated_synthetic_corpus_v3.sh"
readonly MULTITURN_EVALUATOR="$SCRIPT_DIR/evaluate_v1_3_multiturn_resolution.py"
readonly QUERY_RESOLUTION="$PYTHON_ROOT/ishikawa/query_resolution.py"
readonly QUERY_RESOLUTION_TRANSPORT="$PYTHON_ROOT/ishikawa/query_resolution_transport.py"
readonly RETRIEVAL_SERVICE="$PYTHON_ROOT/ishikawa/retrieval_service.py"
readonly NATIVE_ADAPTERS="$PYTHON_ROOT/ishikawa/native_adapters.py"
readonly POSTGRES_RETRIEVAL="$PYTHON_ROOT/ishikawa/postgres_retrieval.py"
readonly OBSERVABILITY="$PYTHON_ROOT/ishikawa/observability.py"
readonly QUERY_TEST="$PRODUCT_ROOT/tests/test_query_resolution.py"
readonly SERVICE_TEST="$PRODUCT_ROOT/tests/test_retrieval_service.py"
readonly NATIVE_ADAPTER_TEST="$PRODUCT_ROOT/tests/test_native_adapters.py"
readonly POSTGRES_RETRIEVAL_TEST="$PRODUCT_ROOT/tests/test_postgres_retrieval.py"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v13-55-multiturn-resolution"

readonly INNER_GATE_SHA256='0657e5917bd627847c669754285fb58612deac5f3b3ec98bdcea24d1cc9ed570'
readonly DECISIONS_SHA256='609b0d2de911b14df5857e76cb2003eeaf023a44f43d4f450f602abf349331b4'
readonly MULTITURN_EVALUATOR_SHA256='57a10ede37cfbf30453fe115650538e55c63d349f8a0057e180ce251a4755615'
readonly QUERY_RESOLUTION_SHA256='53f386208cd937913bf87bb9c5ff3748432eadec090d3fa6de8855004a8ccf65'
readonly QUERY_RESOLUTION_TRANSPORT_SHA256='64499eab4be3266a68ca2567bcccb5ff63be51a90a9abb5de2f9f4f51c50c6c8'
readonly RETRIEVAL_SERVICE_SHA256='bce22de6e0681bcee9ba29ff3e09f8a97eabf4274188af5189deb4f86292468e'
readonly NATIVE_ADAPTERS_SHA256='b2fe8b040a894bc7eefd8a163d4ad3228bc57c13c51dd3f0dbf2716deeb2d533'
readonly POSTGRES_RETRIEVAL_SHA256='900a813362ac25daa2b26faf22eee4cfa726f46cbdd48cc02ea234c922ff4311'
readonly OBSERVABILITY_SHA256='5b6b79ab274b93e806bb3d74f87e7dbc013d8f6c1b8a525e4b2e26a816919eff'
readonly QUERY_TEST_SHA256='0f4df28884be63dee231b87a31b68818d9ac33856dc49f78f61f46abf05cf92a'
readonly SERVICE_TEST_SHA256='2f22073e63fa307c76b52cd1f407fd885b4325e5710d4998a81425dd812e10b8'
readonly NATIVE_ADAPTER_TEST_SHA256='991a3534ed7bc8736a08e90745c65ed852c812aaca4cb0742e5b0ab5a5ca2234'
readonly POSTGRES_RETRIEVAL_TEST_SHA256='3913a976d4c42e8a417e8f3fd05a387fb155867dd1117c3e89b123dad511ea00'

mode="${1:-}"
if [[ "$#" -ne 1 || ( "$mode" != '--validate-only' && "$mode" != '--run' ) ]]; then
  printf '%s\n' \
    'FAILURE DETAIL' \
    'stage=argument_validation' \
    'reason=exactly_one_mode_required' \
    'detail=Script 209 requires exactly one mode: --validate-only or --run.' \
    'operator_action=Rerun Script 209 with exactly one supported mode.' \
    '' 'SCRIPT RESULT' \
    'script_209_v13_55_multiturn_resolution=blocked' >&2
  exit 2
fi

preflight_block() {
  printf '%s\n' \
    'FAILURE DETAIL' 'stage=preflight' "reason=$1" \
    'detail=A V13-55 source, regression test, evaluator, decision, or combined gate did not match its frozen identity.' \
    'operator_action=Correct the named preflight reason, then rerun this same Script 209 command.' \
    '' 'SCRIPT RESULT' \
    'script_209_v13_55_multiturn_resolution=blocked' >&2
  exit "${2:-1}"
}

for command_name in awk bash date grep mkdir mktemp python3 rm sed sha256sum tail tee; do
  command -v "$command_name" >/dev/null 2>&1 \
    || preflight_block "local_command_missing_${command_name}" 2
done

check_file() {
  local path="$1" expected="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] \
    || preflight_block "${label}_unsafe"
  [[ "$(sha256sum -- "$path" | awk '{print $1}')" == "$expected" ]] \
    || preflight_block "${label}_identity_changed"
}

check_file "$INNER_GATE" "$INNER_GATE_SHA256" inner_gate
check_file "$DECISIONS" "$DECISIONS_SHA256" decisions
check_file "$MULTITURN_EVALUATOR" "$MULTITURN_EVALUATOR_SHA256" multiturn_evaluator
check_file "$QUERY_RESOLUTION" "$QUERY_RESOLUTION_SHA256" query_resolution
check_file "$QUERY_RESOLUTION_TRANSPORT" "$QUERY_RESOLUTION_TRANSPORT_SHA256" query_resolution_transport
check_file "$RETRIEVAL_SERVICE" "$RETRIEVAL_SERVICE_SHA256" retrieval_service
check_file "$NATIVE_ADAPTERS" "$NATIVE_ADAPTERS_SHA256" native_adapters
check_file "$POSTGRES_RETRIEVAL" "$POSTGRES_RETRIEVAL_SHA256" postgres_retrieval
check_file "$OBSERVABILITY" "$OBSERVABILITY_SHA256" observability
check_file "$QUERY_TEST" "$QUERY_TEST_SHA256" query_resolution_test
check_file "$SERVICE_TEST" "$SERVICE_TEST_SHA256" retrieval_service_test
check_file "$NATIVE_ADAPTER_TEST" "$NATIVE_ADAPTER_TEST_SHA256" native_adapter_test
check_file "$POSTGRES_RETRIEVAL_TEST" "$POSTGRES_RETRIEVAL_TEST_SHA256" postgres_retrieval_test

grep -Eq '^\| `V13-55` \|.*\| FROZEN \|$' "$DECISIONS" \
  || preflight_block v13_55_not_frozen
grep -Fq 'require both cited `Security Event Reporting Procedure` (`99 TST 2043`) page-one applicability evidence and cited `Incident Intake Form` (`TST-9030`) page-one form evidence' \
  "$DECISIONS" \
  || preflight_block corrected_multiturn_canary_contract_absent
grep -Fq 'Page three of `99 TST 2043` remains independently required by frontier case `R-048`' \
  "$DECISIONS" \
  || preflight_block r048_page_three_contract_absent
grep -Fq '"name": "ishikawa_query_resolution"' "$QUERY_RESOLUTION" \
  || preflight_block strict_query_resolution_schema_absent
grep -Fq 'query-resolution-response-invalid' "$RETRIEVAL_SERVICE" \
  || preflight_block query_resolution_diagnostic_stage_absent
grep -Fq 'ports.generate_answer(request, resolution.resolved_query, evidence)' \
  "$RETRIEVAL_SERVICE" \
  || preflight_block resolved_query_not_used_for_generation
grep -Fq 'question=resolved_query' "$NATIVE_ADAPTERS" \
  || preflight_block generation_adapter_resolved_query_absent
grep -Fq 'resolved_query=resolution.resolved_query' "$POSTGRES_RETRIEVAL" \
  || preflight_block prompt_admission_resolved_query_absent
grep -Fq '"latest_prior_user_request": _latest_clarification_request(request)' \
  "$QUERY_RESOLUTION" \
  || preflight_block clarification_task_preservation_absent
awk '
  $0 == "current_stage=multiturn_resolution_canary" && multiturn == 0 { multiturn = NR }
  $0 == "current_stage=complete_api_gate" && complete == 0 { complete = NR }
  END { exit !(multiturn > 0 && complete > 0 && multiturn < complete) }
' "$INNER_GATE" || preflight_block multiturn_canary_not_fail_fast

bash -n "${BASH_SOURCE[0]}" "$INNER_GATE" \
  || preflight_block shell_syntax_invalid
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$MULTITURN_EVALUATOR" "$QUERY_RESOLUTION" "$QUERY_RESOLUTION_TRANSPORT" \
  "$RETRIEVAL_SERVICE" "$NATIVE_ADAPTERS" "$OBSERVABILITY" "$QUERY_TEST" \
  "$SERVICE_TEST" "$NATIVE_ADAPTER_TEST" "$POSTGRES_RETRIEVAL" \
  "$POSTGRES_RETRIEVAL_TEST" \
  || preflight_block python_syntax_invalid
PYTHONDONTWRITEBYTECODE=1 python3 -B "$MULTITURN_EVALUATOR" --self-test \
  | grep -Fxq 'v1_3_multiturn_resolution_evaluator_self_test=pass' \
  || preflight_block multiturn_evaluator_self_test_failed
targeted_output="$({
  PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B -m unittest \
    "$QUERY_TEST" "$SERVICE_TEST" "$NATIVE_ADAPTER_TEST" \
    "$POSTGRES_RETRIEVAL_TEST"
} 2>&1)" || {
  printf '%s\n' "$targeted_output" | tail -n 100 >&2
  preflight_block targeted_regression_failed
}

inner_validation="$({ bash "$INNER_GATE" --validate-frontier; } 2>&1)" \
  || {
    printf '%s\n' "$inner_validation" >&2
    preflight_block inner_gate_validation_failed
  }
for marker in \
  'qualification_profile=frontier_60' \
  'api_cases=60;responsive=60;nonresponsive=0;broad_navigation=0;required_evidence=60' \
  'one_execution=true;self_validating=true;multiturn_fail_fast_canary=true;r001_fail_fast_canary=true;generation_exchange_capture=true;runtime_flat_file_index=false' \
  'script_201_isolated_corpus_v3_api_qualification=ready'; do
  grep -Fxq "$marker" <<<"$inner_validation" \
    || preflight_block inner_gate_contract_invalid
done

script_sha256="$(sha256sum -- "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$mode" == '--validate-only' ]]; then
  printf '%s\n' \
    'purpose=validate_v13_55_multiturn_resolution_and_combined_frontier_gate' \
    "script_sha256=$script_sha256" \
    'native_targeted_tests=pass;strict_query_resolution_schema=true;failure_stage_diagnostics=true' \
    'frontier_cases=60;multiturn_followup_canary=1;retrieval_mrr_at_20=0.895450' \
    'database_contact=false;model_contact=false;credential_read=false;service_started=false;remote_contact=false' \
    '' 'SCRIPT RESULT' \
    'script_209_v13_55_multiturn_resolution=ready'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" || preflight_block report_root_creation_failed
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/v13_55_multiturn_resolution_${timestamp}_XXXXXX.txt")" \
  || preflight_block report_creation_failed
failure_reason=''
failure_stage=frontier_and_multiturn_qualification
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
block() { failure_reason="$1"; failure_stage="$2"; exit "${3:-1}"; }
cleanup() {
  local status="$?" result=pass
  trap - EXIT INT TERM
  if (( status != 0 )) || [[ -n "$failure_reason" ]]; then
    result=blocked
    emit 'FAILURE DETAIL'
    emit "stage=${failure_stage:-unclassified}"
    emit "reason=${failure_reason:-unexpected_exit_${status}}"
    emit 'detail=The combined native, sixty-question, multi-turn, lifecycle, or cleanup qualification failed at the named stage.'
    emit 'operator_action=Use the named reason and preceding nested failure detail, correct that condition, and rerun this same Script 209 command.'
  fi
  emit "local_report=$report_path"
  emit ''
  emit 'SCRIPT RESULT'
  emit "script_209_v13_55_multiturn_resolution=$result"
  exit "$status"
}
trap cleanup EXIT
trap 'block interrupted signal 130' INT
trap 'block interrupted signal 143' TERM

emit 'purpose=qualify_v13_55_multiturn_resolution_and_unchanged_sixty_question_frontier_gate'
emit "started_utc=$timestamp;script_sha256=$script_sha256"
emit 'authorized_actions=run_local_native_tests_start_private_disposable_postgresql_ingest_synthetic_corpus_v3_contact_loopback_nomic_and_gemma_run_sixty_frontier_questions_and_one_multiturn_canary_write_local_reports'
emit 'non_actions=no_accepted_database_change_no_black_corpus_access_no_remote_host_contact_no_package_or_release_change_no_service_install_or_autostart_no_runtime_flat_file_index'

inner_output="$(mktemp /tmp/ishikawa-script-209-frontier.XXXXXX)" \
  || block inner_output_creation_failed initialization
trap 'rm -f -- "$inner_output"; block interrupted signal 130' INT
set +e
bash "$INNER_GATE" --run-frontier 2>&1 \
  | tee "$inner_output" | tee -a "$report_path"
inner_status="${PIPESTATUS[0]}"
set -e
if (( inner_status != 0 )); then
  nested_reason="$(sed -n 's/^reason=\([A-Za-z0-9_.-]*\)$/\1/p' "$inner_output" | tail -n 1)"
  rm -f -- "$inner_output"
  block "inner_frontier_${nested_reason:-gate_failed}" frontier_and_multiturn_qualification
fi
for marker in \
  'priority_canary_set=pass;complete_gate_enabled=true' \
  'qualification=pass;corpus_v3_database=pass;frontier_60=pass;self_validation=pass' \
  'next_gate=local_human_ui_validation' \
  'script_201_isolated_corpus_v3_api_qualification=pass'; do
  grep -Fxq "$marker" "$inner_output" \
    || {
      rm -f -- "$inner_output"
      block inner_frontier_pass_marker_missing frontier_and_multiturn_qualification
    }
done
grep -Eq '^milestone=multiturn_resolution_canary;state=pass;multiturn_resolution=pass;status=answered;sources=[1-9][0-9]*;applicability_document=99_TST_2043;applicability_page=1;form_document=TST_9030;form_page=1;both_cited=true;request_id=[0-9a-f]{64}$' \
  "$inner_output" \
  || {
    rm -f -- "$inner_output"
    block multiturn_canary_pass_marker_missing frontier_and_multiturn_qualification
  }
native_count="$(sed -n 's/^milestone=native_regression;state=pass;tests=\([0-9][0-9]*\)$/\1/p' "$inner_output" | tail -n 1)"
[[ "$native_count" =~ ^[0-9]+$ && "$native_count" -ge 469 ]] \
  || {
    rm -f -- "$inner_output"
    block native_regression_count_invalid frontier_and_multiturn_qualification
  }
rm -f -- "$inner_output"

emit "qualification=pass;v13_55=pass;retrieval_mrr_at_20=0.895450;frontier_60=pass;multiturn_followup=pass;native_tests=$native_count;self_validation=pass"
emit 'next_gate=launch_corrected_local_human_ui_preview'
