#!/usr/bin/env bash
# Qualify frozen V13-52 response envelopes and the complete local frontier gate.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/206_qualify_v13_52_response_envelopes_and_frontier.sh --validate-only
#   bash ./phase-28-apisachi-tokuli/scripts/206_qualify_v13_52_response_envelopes_and_frontier.sh --run

set -Eeuo pipefail
umask 077

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly WEB_ROOT="$PRODUCT_ROOT/application/web"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly FRONTIER_CASES="$PHASE_ROOT/reference/ishikawa-v1.3-corpus-v3-frontier-cases.json"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_v1_3_complete_api.py"
readonly INNER_GATE="$SCRIPT_DIR/201_ingest_and_qualify_isolated_synthetic_corpus_v3.sh"
readonly RELEVANCE="$PYTHON_ROOT/ishikawa/relevance.py"
readonly POSTGRES_RETRIEVAL="$PYTHON_ROOT/ishikawa/postgres_retrieval.py"
readonly RETRIEVAL_SERVICE="$PYTHON_ROOT/ishikawa/retrieval_service.py"
readonly API_CONTRACT="$PYTHON_ROOT/ishikawa/api_contract.py"
readonly RELEVANCE_PROFILE="$PRODUCT_ROOT/config/templates/relevance_profile.yaml"
readonly PRODUCT_PROFILE="$PRODUCT_ROOT/config/templates/product.yaml"
readonly CHAT_CONTRACT="$WEB_ROOT/lib/chat-contract.mjs"
readonly CHAT_WORKSPACE="$WEB_ROOT/components/chat-workspace.js"
readonly CHAT_CONTRACT_TEST="$WEB_ROOT/tests/chat-contract.test.mjs"
readonly WEB_PACKAGE="$WEB_ROOT/package.json"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v13-52-response-envelopes-frontier"

readonly INNER_GATE_SHA256='a26f0afb039cf984bca7fcb1650f49ee81244ed60da003172093c547a13578f2'
readonly EVALUATOR_SHA256='854d8a560b087a643d83719d0ba7db734487d62153626a79cf279a312df3c829'
readonly DECISIONS_SHA256='b5944c633bfec2020e4d5ca1b532e1b0c17a3d913c7d34a4f93869b9f2980b79'
readonly FRONTIER_CASES_SHA256='2ba5f61518ca17b0eaa26f024abe35418b050f9bd8d5b3e1677062c9d7a626a3'
readonly RELEVANCE_SHA256='63216446cccc5dcd6c147f781790d2da572a0bf0cb3fcac737a20fae656b6156'
readonly POSTGRES_RETRIEVAL_SHA256='2cae12b5debb7a71b59c89c58db360cb3cfb9165655052811f2dca61fb3195eb'
readonly RETRIEVAL_SERVICE_SHA256='383575a235d01fc633bd39c448bc5e38439e49ace059469e5d69eeb765a2e6bf'
readonly API_CONTRACT_SHA256='93417e260c6048de3314c7fd8989f9b7543defbf16928d4b9c6620be039aa74e'
readonly RELEVANCE_PROFILE_SHA256='51d56b97ae79d4a219e0af6929a2612c5b8a321a0178af46ccda70618b7e7672'
readonly PRODUCT_PROFILE_SHA256='b4189e48b1d2a8c91cce9846227e4e46a32f139b35f520fa66014de627f5ec43'
readonly CHAT_CONTRACT_SHA256='43bb2c0624594e91cc2aaf97f3b3f2d661037eea51c03c29b9128696fc629fd3'
readonly CHAT_WORKSPACE_SHA256='35b2b83bef4b72b227576afe772e8718e2e28283e070feb512fce4aadb66eb52'
readonly CHAT_CONTRACT_TEST_SHA256='469a86c51f065982c1285b81dd6a15918094576d2c9ec879905651a5962becac'
readonly WEB_PACKAGE_SHA256='cc53fbb830c2199923f68c98f31fae3659c10a6a64b55dfdf810b5c38a3bb505'

mode="${1:-}"
if [[ "$#" -ne 1 || ( "$mode" != '--validate-only' && "$mode" != '--run' ) ]]; then
  printf '%s\n' \
    'FAILURE DETAIL' \
    'stage=argument_validation' \
    'reason=exactly_one_mode_required' \
    'detail=Script 206 requires exactly one mode: --validate-only or --run.' \
    'operator_action=Rerun Script 206 with exactly one supported mode.' \
    '' 'SCRIPT RESULT' \
    'script_206_v13_52_response_envelopes_frontier=blocked' >&2
  exit 2
fi

preflight_block() {
  printf '%s\n' \
    'FAILURE DETAIL' 'stage=preflight' "reason=$1" \
    'detail=A frozen V13-52 source, local prerequisite, or self-test did not match.' \
    'operator_action=Correct the named preflight reason, then rerun this same Script 206 command.' \
    '' 'SCRIPT RESULT' \
    'script_206_v13_52_response_envelopes_frontier=blocked' >&2
  exit "${2:-1}"
}

for command_name in awk bash date grep mkdir mktemp python3 rm sed sha256sum \
  sleep sort tail tee; do
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
check_file "$EVALUATOR" "$EVALUATOR_SHA256" evaluator
check_file "$DECISIONS" "$DECISIONS_SHA256" decisions
check_file "$FRONTIER_CASES" "$FRONTIER_CASES_SHA256" frontier_cases
check_file "$RELEVANCE" "$RELEVANCE_SHA256" relevance
check_file "$POSTGRES_RETRIEVAL" "$POSTGRES_RETRIEVAL_SHA256" postgres_retrieval
check_file "$RETRIEVAL_SERVICE" "$RETRIEVAL_SERVICE_SHA256" retrieval_service
check_file "$API_CONTRACT" "$API_CONTRACT_SHA256" api_contract
check_file "$RELEVANCE_PROFILE" "$RELEVANCE_PROFILE_SHA256" relevance_profile
check_file "$PRODUCT_PROFILE" "$PRODUCT_PROFILE_SHA256" product_profile
check_file "$CHAT_CONTRACT" "$CHAT_CONTRACT_SHA256" chat_contract
check_file "$CHAT_WORKSPACE" "$CHAT_WORKSPACE_SHA256" chat_workspace
check_file "$CHAT_CONTRACT_TEST" "$CHAT_CONTRACT_TEST_SHA256" chat_contract_test
check_file "$WEB_PACKAGE" "$WEB_PACKAGE_SHA256" web_package

grep -Eq '^\| `V13-52` \|.*\| FROZEN \|$' "$DECISIONS" \
  || preflight_block v13_52_not_frozen
grep -Fq 'class ResponseEnvelopePlan' "$RELEVANCE" \
  || preflight_block response_envelope_plan_absent
grep -Fq 'plan_citable_response_envelopes' "$POSTGRES_RETRIEVAL" \
  || preflight_block response_envelope_runtime_absent
grep -Fq 'ishikawa.chat-response.v5' "$API_CONTRACT" \
  || preflight_block response_v5_api_contract_absent
grep -Fq 'ishikawa.chat-response.v5' "$CHAT_CONTRACT" \
  || preflight_block response_v5_browser_contract_absent

bash -n "${BASH_SOURCE[0]}" "$INNER_GATE" \
  || preflight_block shell_syntax_invalid
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$EVALUATOR" "$RELEVANCE" "$POSTGRES_RETRIEVAL" \
  "$RETRIEVAL_SERVICE" "$API_CONTRACT" \
  || preflight_block python_syntax_invalid
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" --self-test \
  | grep -Fxq 'v1_3_complete_api_evaluator_self_test=pass' \
  || preflight_block evaluator_self_test_failed
case_validation="$(PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" \
  --validate-cases --cases "$FRONTIER_CASES" 2>&1)" \
  || preflight_block frontier_case_validation_failed
grep -Eq '^v1_3_complete_api_case_set=pass;cases=60;responsive=60;nonresponsive=0;broad_navigation=0;required_evidence=60;identity=[0-9a-f]{64}$' \
  <<<"$case_validation" || preflight_block frontier_case_contract_invalid

inner_validation="$({ bash "$INNER_GATE" --validate-frontier; } 2>&1)" \
  || {
    printf '%s\n' "$inner_validation" >&2
    preflight_block inner_gate_validation_failed
  }
for fact in \
  'qualification_profile=frontier_60' \
  'api_cases=60;responsive=60;nonresponsive=0;broad_navigation=0;required_evidence=60' \
  'script_201_isolated_corpus_v3_api_qualification=ready'; do
  grep -Fxq "$fact" <<<"$inner_validation" \
    || preflight_block inner_gate_contract_invalid
done

javascript_test_declarations="$(
  grep -hEc '^test\(' "$WEB_ROOT"/tests/*.test.mjs \
    | awk '{ total += $1 } END { print total + 0 }'
)"
[[ "$javascript_test_declarations" == '17' ]] \
  || preflight_block javascript_test_inventory_changed

script_sha256="$(sha256sum -- "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$mode" == '--validate-only' ]]; then
  printf '%s\n' \
    'purpose=validate_v13_52_response_envelopes_and_sixty_question_frontier_workflow' \
    "script_sha256=$script_sha256" \
    'retrieval_mrr_at_20=0.895450;retrieval_ranking=v13_47_unchanged;frontier_cases=60' \
    'priority_canaries=R-001,R-012,R-016,R-036,R-048,R-052,R-054' \
    'next_gate_on_pass=local_human_ui_validation' \
    'database_contact=false;model_contact=false;credential_read=false;service_started=false;remote_contact=false' \
    '' 'SCRIPT RESULT' \
    'script_206_v13_52_response_envelopes_frontier=ready'
  exit 0
fi

for command_name in docker dpkg sudo; do
  command -v "$command_name" >/dev/null 2>&1 \
    || preflight_block "local_command_missing_${command_name}" 2
done

work_root="$(mktemp -d /tmp/ishikawa-script-206.XXXXXX)" \
  || preflight_block workspace_creation_failed
report_path=''
failure_reason=''
failure_stage=initialization
emit() {
  if [[ -n "$report_path" ]]; then
    printf '%s\n' "$1" | tee -a "$report_path"
  else
    printf '%s\n' "$1"
  fi
}
block() {
  failure_reason="$1"
  failure_stage="$2"
  exit "${3:-1}"
}
cleanup() {
  local status="$?" result=pass
  trap - EXIT INT TERM
  [[ "$work_root" == /tmp/ishikawa-script-206.* && -d "$work_root" ]] \
    && rm -rf -- "$work_root"
  if (( status != 0 )) || [[ -n "$failure_reason" ]]; then
    result=blocked
    emit 'FAILURE DETAIL'
    emit "stage=${failure_stage:-unclassified}"
    emit "reason=${failure_reason:-unexpected_exit_${status}}"
    emit 'detail=The named V13-52 browser, canary, frontier, artifact, lifecycle, or cleanup gate failed.'
    emit 'operator_action=Use the named reason and preceding nested failure detail; correct that condition and rerun this same Script 206 command.'
  fi
  [[ -z "$report_path" ]] || emit "local_report=$report_path"
  emit ''
  emit 'SCRIPT RESULT'
  emit "script_206_v13_52_response_envelopes_frontier=$result"
  exit "$status"
}
trap cleanup EXIT
trap 'block interrupted signal 130' INT
trap 'block interrupted signal 143' TERM

mkdir -p -- "$REPORT_ROOT" || block report_root_creation_failed initialization
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/v13_52_response_envelopes_frontier_${timestamp}_XXXXXX.txt")" \
  || block report_creation_failed initialization

emit 'purpose=qualify_v13_52_response_envelopes_and_complete_local_frontier_gate'
emit "started_utc=$timestamp;script_sha256=$script_sha256"
emit 'authorized_actions=run_network_isolated_web_tests_and_build_run_local_native_tests_start_private_disposable_postgresql_ingest_synthetic_corpus_v3_contact_loopback_nomic_and_gemma_run_priority_canaries_then_all_sixty_cases_write_local_reports'
emit 'non_actions=no_accepted_database_change_no_black_corpus_access_no_remote_host_contact_no_package_or_release_change_no_service_install_or_autostart_no_image_pull_no_runtime_flat_file_index'

failure_stage=container_access
docker_command=(docker)
if ! docker info >/dev/null 2>&1; then
  emit 'milestone=container_access;state=awaiting_attended_sudo'
  sudo -v || block sudo_authentication_failed container_access 2
  docker_command=(sudo docker)
  "${docker_command[@]}" info >/dev/null 2>&1 \
    || block docker_access_failed container_access 2
fi
architecture="$(dpkg --print-architecture)"
case "$architecture" in arm64|amd64) ;; *) block host_architecture_unsupported container_access 2 ;; esac
image="node-24-slim-nextjs-16-4-1:$architecture"
"${docker_command[@]}" image inspect "$image" >/dev/null 2>&1 \
  || block required_local_image_missing container_access 2
[[ "$("${docker_command[@]}" image inspect "$image" --format '{{.Architecture}}')" == "$architecture" ]] \
  || block image_architecture_mismatch container_access 2
emit "milestone=container_access;state=pass;image=$image;image_pull=false"

declare -a web_mounts=(
  --mount "type=bind,src=$WEB_ROOT/app,dst=/opt/nextjs/app,readonly"
  --mount "type=bind,src=$WEB_ROOT/components,dst=/opt/nextjs/components,readonly"
  --mount "type=bind,src=$WEB_ROOT/lib,dst=/opt/nextjs/lib,readonly"
  --mount "type=bind,src=$WEB_ROOT/public,dst=/opt/nextjs/public,readonly"
  --mount "type=bind,src=$WEB_ROOT/tests,dst=/opt/nextjs/tests,readonly"
  --mount "type=bind,src=$WEB_ROOT/package.json,dst=/opt/nextjs/package.json,readonly"
  --mount "type=bind,src=$WEB_ROOT/next.config.mjs,dst=/opt/nextjs/next.config.mjs,readonly"
)

failure_stage=javascript_tests
emit 'milestone=javascript_tests;state=start'
javascript_result="$work_root/javascript-tests.txt"
"${docker_command[@]}" run --rm --network none "${web_mounts[@]}" \
  "$image" npm test >"$javascript_result" 2>&1 \
  || {
    tail -n 120 "$javascript_result" | tee -a "$report_path"
    block javascript_tests_failed javascript_tests
  }
emit "milestone=javascript_tests;state=pass;tests=$javascript_test_declarations"

product_ui_config_base64="$(
  PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B - \
    "$PRODUCT_PROFILE" <<'PY'
import sys
from pathlib import Path
from ishikawa.product import validate_product_profile
from ishikawa.yaml_loader import load_restricted_yaml

profile = validate_product_profile(
    load_restricted_yaml(Path(sys.argv[1]), label="product profile")
)
print(profile.browser_configuration_base64())
PY
)" || block product_profile_invalid next_build
[[ "$product_ui_config_base64" =~ ^[A-Za-z0-9_-]+=*$ ]] \
  || block product_payload_invalid next_build

failure_stage=next_build
emit 'milestone=next_build;state=start'
build_result="$work_root/next-build.txt"
"${docker_command[@]}" run --rm --network none \
  -e ISHIKAWA_PRODUCT_DISPLAY_NAME=Ishikawa \
  -e "ISHIKAWA_PRODUCT_UI_CONFIG_BASE64=$product_ui_config_base64" \
  -e ISHIKAWA_RETRIEVAL_BASE_URL=http://127.0.0.1:1384 \
  "${web_mounts[@]}" "$image" npm run build >"$build_result" 2>&1 &
build_pid="$!"
build_started="$(date +%s)"
build_heartbeat=$(( build_started + 30 ))
while kill -0 "$build_pid" 2>/dev/null; do
  sleep 5
  now="$(date +%s)"
  if (( now >= build_heartbeat )); then
    emit "milestone=next_build;state=running;elapsed_seconds=$(( now - build_started ))"
    build_heartbeat=$(( now + 30 ))
  fi
done
set +e
wait "$build_pid"
build_status="$?"
set -e
if (( build_status != 0 )); then
  tail -n 120 "$build_result" | tee -a "$report_path"
  block next_build_failed next_build
fi
emit 'milestone=next_build;state=pass'

failure_stage=frontier_qualification
emit 'milestone=frontier_qualification;state=start;order=R-001_then_R-012_R-016_R-036_R-048_R-052_R-054_then_remaining_53'
inner_output="$work_root/frontier-gate.txt"
set +e
bash "$INNER_GATE" --run-frontier 2>&1 \
  | tee "$inner_output" | tee -a "$report_path"
inner_status="${PIPESTATUS[0]}"
set -e
(( inner_status == 0 )) \
  || {
    nested_reason="$(sed -n 's/^reason=\([A-Za-z0-9_.-]*\)$/\1/p' "$inner_output" | tail -n 1)"
    block "inner_frontier_${nested_reason:-gate_failed}" frontier_qualification
  }
for fact in \
  'milestone=native_regression;state=pass;tests=464' \
  'priority_canary_set=pass;complete_gate_enabled=true' \
  'qualification=pass;corpus_v3_database=pass;frontier_60=pass;self_validation=pass' \
  'next_gate=local_human_ui_validation' \
  'script_201_isolated_corpus_v3_api_qualification=pass'; do
  grep -Fxq "$fact" "$inner_output" \
    || block inner_frontier_pass_marker_missing frontier_qualification
done

api_artifact="$(sed -n 's/^api_artifact=//p' "$inner_output" | tail -n 1)"
[[ "$api_artifact" == "$REPO_ROOT"/local/artifacts/ishikawa/* \
    && -f "$api_artifact" && ! -L "$api_artifact" && -r "$api_artifact" \
    && -f "$api_artifact.sha256" && ! -L "$api_artifact.sha256" ]] \
  || block api_artifact_invalid artifact_validation
(cd -- "$(dirname -- "$api_artifact")" \
  && sha256sum --check --strict "$(basename -- "$api_artifact.sha256")" >/dev/null) \
  || block api_artifact_checksum_failed artifact_validation

failure_stage=artifact_validation
artifact_summary="$(PYTHONDONTWRITEBYTECODE=1 python3 -B - "$api_artifact" <<'PY'
import json
import pathlib
import sys

artifact = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
priority = ["R-012", "R-016", "R-036", "R-048", "R-052", "R-054"]
assert artifact["canary"] == {"abort_reason": None, "case_id": "R-001", "passed": True}
assert artifact["execution_order"][:7] == ["R-001", *priority]
assert len(artifact["execution_order"]) == len(set(artifact["execution_order"])) == 60
assert artifact["priority_canary"] == {
    "abort_case": None,
    "abort_reason": None,
    "passed_case_ids": priority,
    "requested_case_ids": priority,
}
summary = artifact["summary"]
assert summary["acceptance_gate"] == "pass"
assert summary["case_count"] == 60
assert summary["expected_status_match_count"] == 60
assert summary["required_evidence_returned_count"] == 60
assert summary["required_evidence_cited_count"] == 60
assert summary["dependency_failure_count"] == 0
assert len(artifact["cases"]) == 60
for observation in artifact["cases"]:
    response = observation["response"]
    assert response["schema"] == "ishikawa.chat-response.v5"
    diagnostics = response["diagnostics"]
    assert diagnostics["relevance_reason_code"] == "CITABLE_EVIDENCE_SUPPORT_QUALIFIED"
    assert diagnostics["sufficiency_reason_code"] == "EVIDENCE_SUFFICIENT"
    groups = diagnostics["selected_group_order"]
    assert isinstance(groups, list) and 1 <= len(groups) <= 6
    assert len(groups) == len(set(groups))
print(
    "frontier_cases=60;expected_status_matches=60/60;"
    "required_evidence_returned=60/60;required_evidence_cited=60/60;"
    "priority_canaries=6/6;diagnostic_contract=v5"
)
PY
)" || block api_artifact_contract_invalid artifact_validation
emit "milestone=artifact_validation;state=pass;$artifact_summary"
emit 'qualification=pass;v13_52=pass;retrieval_mrr_at_20=0.895450;frontier_60=pass;browser_tests=pass;next_build=pass;native_tests=464;self_validation=pass'
emit 'next_gate=local_human_ui_validation'
