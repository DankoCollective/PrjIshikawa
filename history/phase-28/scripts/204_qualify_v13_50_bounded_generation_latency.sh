#!/usr/bin/env bash
# Qualify frozen V13-50 and the corpus-v3 promotion gate in one execution.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/204_qualify_v13_50_bounded_generation_latency.sh --validate-only
#   bash ./phase-28-apisachi-tokuli/scripts/204_qualify_v13_50_bounded_generation_latency.sh --run

set -Eeuo pipefail
umask 077

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly WEB_ROOT="$PRODUCT_ROOT/application/web"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly RECONSTRUCTION_PROFILE="$PRODUCT_ROOT/config/templates/reconstruction_profile.yaml"
readonly PRODUCT_PROFILE="$PRODUCT_ROOT/config/templates/product.yaml"
readonly INNER_GATE="$SCRIPT_DIR/201_ingest_and_qualify_isolated_synthetic_corpus_v3.sh"
readonly API_EVALUATOR="$SCRIPT_DIR/evaluate_v1_3_complete_api.py"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v13-50-bounded-generation-latency"

readonly API_CONTRACT="$PYTHON_ROOT/ishikawa/api_contract.py"
readonly GENERATION="$PYTHON_ROOT/ishikawa/generation.py"
readonly GENERATION_TRANSPORT="$PYTHON_ROOT/ishikawa/generation_transport.py"
readonly POSTGRES_RETRIEVAL="$PYTHON_ROOT/ishikawa/postgres_retrieval.py"
readonly READINESS="$PYTHON_ROOT/ishikawa/readiness.py"
readonly RECONSTRUCTION="$PYTHON_ROOT/ishikawa/reconstruction.py"
readonly RETRIEVAL_SERVICE="$PYTHON_ROOT/ishikawa/retrieval_service.py"
readonly RUNTIME="$PYTHON_ROOT/ishikawa/runtime.py"
readonly CHAT_WORKSPACE="$WEB_ROOT/components/chat-workspace.js"
readonly CHAT_CONTRACT="$WEB_ROOT/lib/chat-contract.mjs"
readonly CHAT_CONTRACT_TEST="$WEB_ROOT/tests/chat-contract.test.mjs"
readonly PRESENTATION_TEST="$WEB_ROOT/tests/presentation.test.mjs"
readonly WEB_PACKAGE="$WEB_ROOT/package.json"

readonly API_CONTRACT_SHA256='c1bc77c5707e93a58f238b6d4a43481cff63338351d90c92c095dda40970cd95'
readonly GENERATION_SHA256='8e525629f7fa0f2b4b5279c55e65c5e9892b944b0eacf2fef03e1f14d1469787'
readonly GENERATION_TRANSPORT_SHA256='535e195c89cb7849988a9a6e17dbf97bd9de67e12f09ee73b79fc7e65560f69c'
readonly POSTGRES_RETRIEVAL_SHA256='97cf9fe0b1a7ade47a091c14a56c4577bd919f021c7b9d6b5f8497941a0eaad9'
readonly READINESS_SHA256='050566acb8bc868871513e0f2b273bf394042aba8fbe2b57af34caee6b1d7b62'
readonly RECONSTRUCTION_SHA256='6d1dee8f5fd798da9142a73efe477b9f1b14fabd95e8676da9e6f7034de58683'
readonly RETRIEVAL_SERVICE_SHA256='7cbbecc2f51f4fd424011923d451e175e0b89b9b5880542851ab253eddeb6c44'
readonly RUNTIME_SHA256='43ea745267dcc0d90bfa11ed986f1ba4679699cb7b2764192b552b30805d7915'
readonly RECONSTRUCTION_PROFILE_SHA256='718a959122647b3b9755053c9d4dcf070c9f600f40b20e9958e7bf36724fb849'
readonly CHAT_WORKSPACE_SHA256='e3e3e1eb1e3a6f65d1b0463cbb19e7316478d885f04bd390268384d173a02ecc'
readonly CHAT_CONTRACT_SHA256='4b969e17f808c5ec6585d3d833c670e4db30f9900bfaffd001a1b829fe8e3178'
readonly CHAT_CONTRACT_TEST_SHA256='8e75d0c702500ebd3f5627ae08d1e1aee997917c18a5273d4bed82d0334e61fc'
readonly PRESENTATION_TEST_SHA256='d4e6b2503e95b161ddc23fca2c29fa615bc439387e008599abee7626abe95d95'
readonly WEB_PACKAGE_SHA256='cc53fbb830c2199923f68c98f31fae3659c10a6a64b55dfdf810b5c38a3bb505'
readonly INNER_GATE_SHA256='6234ca2c88299a0ea265633f187f3db2858051ae7fb3efdc22d20099bda89c23'
readonly API_EVALUATOR_SHA256='924287b2621df7b757e6e85fae1679d42f2459f19e16e7d1bfdb4a8dc02004d1'
readonly DECISIONS_SHA256='49a77a0c595c8940bd9676137e90dec68d18d3f93a48e95639410111f4e23f4c'

mode="${1:-}"
if [[ "$#" -ne 1 || ( "$mode" != '--validate-only' && "$mode" != '--run' ) ]]; then
  printf '%s\n' \
    'FAILURE DETAIL' \
    'stage=argument_validation' \
    'reason=exactly_one_mode_required' \
    'detail=Script 204 requires exactly one mode: --validate-only or --run.' \
    'operator_action=Rerun Script 204 with exactly one supported mode.' \
    '' 'SCRIPT RESULT' \
    'script_204_v13_50_bounded_generation_latency=blocked' >&2
  exit 2
fi

preflight_block() {
  printf '%s\n' \
    'FAILURE DETAIL' 'stage=preflight' "reason=$1" \
    'detail=A frozen V13-50 source, local prerequisite, or self-test did not match.' \
    'operator_action=Correct the named preflight reason and rerun this same Script 204 command.' \
    '' 'SCRIPT RESULT' \
    'script_204_v13_50_bounded_generation_latency=blocked' >&2
  exit "${2:-1}"
}

for command_name in awk bash date docker dpkg grep id kill mkdir mktemp python3 \
  rm sed sha256sum sleep stat sudo tail tee; do
  if [[ "$mode" == '--validate-only' && "$command_name" =~ ^(docker|dpkg|sudo)$ ]]; then
    continue
  fi
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

check_file "$API_CONTRACT" "$API_CONTRACT_SHA256" api_contract
check_file "$GENERATION" "$GENERATION_SHA256" generation
check_file "$GENERATION_TRANSPORT" "$GENERATION_TRANSPORT_SHA256" generation_transport
check_file "$POSTGRES_RETRIEVAL" "$POSTGRES_RETRIEVAL_SHA256" postgres_retrieval
check_file "$READINESS" "$READINESS_SHA256" readiness
check_file "$RECONSTRUCTION" "$RECONSTRUCTION_SHA256" reconstruction
check_file "$RETRIEVAL_SERVICE" "$RETRIEVAL_SERVICE_SHA256" retrieval_service
check_file "$RUNTIME" "$RUNTIME_SHA256" runtime
check_file "$RECONSTRUCTION_PROFILE" "$RECONSTRUCTION_PROFILE_SHA256" reconstruction_profile
check_file "$CHAT_WORKSPACE" "$CHAT_WORKSPACE_SHA256" chat_workspace
check_file "$CHAT_CONTRACT" "$CHAT_CONTRACT_SHA256" chat_contract
check_file "$CHAT_CONTRACT_TEST" "$CHAT_CONTRACT_TEST_SHA256" chat_contract_test
check_file "$PRESENTATION_TEST" "$PRESENTATION_TEST_SHA256" presentation_test
check_file "$WEB_PACKAGE" "$WEB_PACKAGE_SHA256" web_package
check_file "$INNER_GATE" "$INNER_GATE_SHA256" inner_gate
check_file "$API_EVALUATOR" "$API_EVALUATOR_SHA256" api_evaluator
check_file "$DECISIONS" "$DECISIONS_SHA256" decisions
[[ -f "$PRODUCT_PROFILE" && ! -L "$PRODUCT_PROFILE" && -r "$PRODUCT_PROFILE" ]] \
  || preflight_block product_profile_unsafe

grep -Eq '^\| `V13-50` \|.*\| FROZEN \|$' "$DECISIONS" \
  || preflight_block v13_50_not_frozen
grep -Fq 'generation_prompt_targets' "$RECONSTRUCTION_PROFILE" \
  || preflight_block prompt_targets_absent
grep -Fq 'evidence_groups' "$GENERATION" \
  || preflight_block compact_generation_protocol_absent
grep -Fq 'WarmedNomicProbe' "$READINESS" \
  || preflight_block nomic_warmup_absent
grep -Fq 'retrieval_detail' "$CHAT_CONTRACT" \
  || preflight_block retrieval_diagnostics_contract_absent
grep -Fq 'Prompt target' "$CHAT_WORKSPACE" \
  || preflight_block prompt_target_diagnostic_absent

javascript_test_declarations="$(
  grep -hEc '^test\(' "$WEB_ROOT"/tests/*.test.mjs \
    | awk '{ total += $1 } END { print total + 0 }'
)"
[[ "$javascript_test_declarations" == '17' ]] \
  || preflight_block javascript_test_inventory_changed

bash -n "${BASH_SOURCE[0]}" "$INNER_GATE" \
  || preflight_block shell_syntax_invalid
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$API_CONTRACT" "$GENERATION" "$GENERATION_TRANSPORT" \
  "$POSTGRES_RETRIEVAL" "$READINESS" "$RECONSTRUCTION" \
  "$RETRIEVAL_SERVICE" "$RUNTIME" "$API_EVALUATOR" \
  || preflight_block python_syntax_invalid

PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B - \
  "$RECONSTRUCTION_PROFILE" <<'PY' \
  || preflight_block prompt_target_profile_invalid
import sys
from pathlib import Path
from ishikawa.reconstruction import validate_reconstruction_profile
from ishikawa.yaml_loader import load_restricted_yaml

profile = validate_reconstruction_profile(
    load_restricted_yaml(Path(sys.argv[1]), label="reconstruction profile")
)
assert profile.generation_prompt_targets == (8192, 12288, 16384)
assert profile.generation_optional_group_limit == 6
assert profile.answer_token_reserve == 2048
assert profile.total_context_tokens == 32768
PY

PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" \
  python3 -B "$API_EVALUATOR" --self-test \
  | grep -Fxq 'v1_3_complete_api_evaluator_self_test=pass' \
  || preflight_block api_evaluator_self_test_failed

inner_validation="$({ bash "$INNER_GATE" --validate-only; } 2>&1)" \
  || {
    printf '%s\n' "$inner_validation" >&2
    preflight_block inner_gate_validation_failed
  }
grep -Fxq 'script_201_isolated_corpus_v3_api_qualification=ready' \
  <<<"$inner_validation" \
  || preflight_block inner_gate_ready_marker_absent

script_sha256="$(sha256sum -- "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$mode" == '--validate-only' ]]; then
  printf '%s\n' \
    'purpose=validate_v13_50_bounded_generation_latency_gate' \
    "script_sha256=$script_sha256" \
    'prompt_targets=8192,12288,16384;answer_reserve=2048;context_limit=32768' \
    'qualification_order=web_tests_then_build_then_native_tests_then_r001_canary_then_remaining_12_cases_then_artifact_validation' \
    'database_contact=false;model_contact=false;credential_read=false;service_started=false;corpus_changed=false' \
    '' 'SCRIPT RESULT' \
    'script_204_v13_50_bounded_generation_latency=ready'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" || preflight_block report_root_creation_failed
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/v13_50_bounded_generation_latency_${timestamp}_XXXXXX.txt")" \
  || preflight_block report_creation_failed
work_root="$(mktemp -d /tmp/ishikawa-script-204.XXXXXX)" \
  || preflight_block workspace_creation_failed
build_pid=''
failure_reason=''
failure_stage='initialization'

emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
block() {
  failure_reason="$1"
  failure_stage="$2"
  exit "${3:-1}"
}
cleanup() {
  local status="$?" result=pass
  trap - EXIT INT TERM
  if [[ "$build_pid" =~ ^[0-9]+$ ]] && kill -0 "$build_pid" 2>/dev/null; then
    kill -TERM "$build_pid" 2>/dev/null || true
    wait "$build_pid" 2>/dev/null || true
  fi
  [[ "$work_root" == /tmp/ishikawa-script-204.* && -d "$work_root" ]] \
    && rm -rf -- "$work_root"
  if (( status != 0 )) || [[ -n "$failure_reason" ]]; then
    result=blocked
    emit 'FAILURE DETAIL'
    emit "stage=${failure_stage:-unclassified}"
    emit "reason=${failure_reason:-unexpected_exit_${status}}"
    case "${failure_reason:-}" in
      docker_access_failed)
        emit 'detail=The local Docker daemon was unavailable after attended sudo authentication.'
        emit 'operator_action=Restore Docker access and rerun Script 204.'
        ;;
      required_local_image_missing)
        emit "detail=The architecture-matched local Node image was absent;image=${image:-not_resolved}."
        emit 'operator_action=Restore the existing local developer image; Script 204 will not pull one.'
        ;;
      javascript_tests_failed|next_build_failed)
        emit 'detail=The network-isolated browser validation failed before database or model contact.'
        emit 'operator_action=Inspect the retained report output, correct the web failure, and rerun Script 204.'
        ;;
      inner_gate_failed|inner_gate_pass_marker_absent)
        emit 'detail=The nested native/corpus-v3/R-001/13-case gate failed; its preceding FAILURE DETAIL is authoritative.'
        emit 'operator_action=Use the nested stage and reason above, correct it, and rerun Script 204.'
        ;;
      qualification_artifact_invalid)
        emit 'detail=The live API run passed its older summary but failed a V13-50 prompt-target or retrieval-timing invariant.'
        emit 'operator_action=Inspect the retained API artifact path above before changing packing or readiness.'
        ;;
      *)
        emit 'detail=Script 204 stopped at the named bounded stage.'
        emit 'operator_action=Correct the named reason and rerun this same command.'
        ;;
    esac
  fi
  emit "local_report=$report_path"
  emit ''
  emit 'SCRIPT RESULT'
  emit "script_204_v13_50_bounded_generation_latency=$result"
  exit "$status"
}
trap cleanup EXIT
trap 'block interrupted signal 130' INT
trap 'block interrupted signal 143' TERM

emit 'purpose=qualify_v13_50_bounded_generation_latency_and_corpus_v3_promotion_gate'
emit "started_utc=$timestamp;script_sha256=$script_sha256"
emit 'authorized_actions=run_network_isolated_web_tests_and_build_run_local_native_tests_start_disposable_postgresql_ingest_isolated_corpus_v3_contact_loopback_nomic_and_gemma_run_r001_then_remaining_cases_validate_content_free_metrics_write_local_reports'
emit 'non_actions=no_accepted_database_change_no_black_corpus_access_no_remote_host_change_no_package_or_release_change_no_service_install_or_autostart_no_image_pull_no_runtime_flat_file_index'

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
while kill -0 "$build_pid" 2>/dev/null; do
  sleep 5
  kill -0 "$build_pid" 2>/dev/null && emit 'milestone=next_build;state=running'
done
set +e
wait "$build_pid"
build_status="$?"
set -e
build_pid=''
if (( build_status != 0 )); then
  tail -n 120 "$build_result" | tee -a "$report_path"
  block next_build_failed next_build
fi
emit 'milestone=next_build;state=pass'

failure_stage=combined_api_gate
emit 'milestone=combined_api_gate;state=start;order=native_tests_then_nomic_warm_readiness_then_r001_canary_then_remaining_12_cases'
inner_output="$work_root/inner-gate.txt"
set +e
bash "$INNER_GATE" --run 2>&1 | tee "$inner_output" | tee -a "$report_path"
inner_status="${PIPESTATUS[0]}"
set -e
(( inner_status == 0 )) || block inner_gate_failed combined_api_gate
grep -Fxq 'script_201_isolated_corpus_v3_api_qualification=pass' "$inner_output" \
  || block inner_gate_pass_marker_absent combined_api_gate
grep -Fxq 'qualification=pass;corpus_v3_database=pass;complete_api=pass;self_validation=pass' "$inner_output" \
  || block inner_gate_pass_marker_absent combined_api_gate

database_artifact="$(sed -n 's/^database_artifact=//p' "$inner_output" | tail -n 1)"
api_artifact="$(sed -n 's/^api_artifact=//p' "$inner_output" | tail -n 1)"
generation_capture_root="$(sed -n 's/^generation_capture_root=//p' "$inner_output" | tail -n 1)"
generation_capture_root="${generation_capture_root%%;*}"
for artifact in "$database_artifact" "$api_artifact"; do
  [[ "$artifact" == "$REPO_ROOT"/local/artifacts/ishikawa/* \
      && -f "$artifact" && ! -L "$artifact" && -r "$artifact" ]] \
    || block qualification_artifact_invalid artifact_validation
  [[ -f "$artifact.sha256" && ! -L "$artifact.sha256" ]] \
    || block qualification_artifact_invalid artifact_validation
  (cd -- "$(dirname -- "$artifact")" \
    && sha256sum --check --strict "$(basename -- "$artifact.sha256")" >/dev/null) \
    || block qualification_artifact_invalid artifact_validation
done
[[ "$generation_capture_root" == "$REPO_ROOT"/local/artifacts/ishikawa/* \
    && -d "$generation_capture_root" && ! -L "$generation_capture_root" ]] \
  || block qualification_artifact_invalid artifact_validation

failure_stage=artifact_validation
artifact_summary="$(PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$database_artifact" "$api_artifact" "$generation_capture_root" <<'PY'
import collections
import json
import sys
from pathlib import Path

database = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
api = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
capture_root = Path(sys.argv[3])
assert database["status"] == "pass"
assert database["corpus_identity"] == "synthetic-corpus-v3"
assert database["inventory"]["documents"] == 30
assert api["canary"] == {"abort_reason": None, "case_id": "R-001", "passed": True}
assert api["summary"]["acceptance_gate"] == "pass"
assert api["summary"]["case_count"] == 13
assert api["summary"]["contract_valid_count"] == 13
assert api["summary"]["dependency_failure_count"] == 0
assert len(api["cases"]) == 13

r001 = next(item for item in api["cases"] if item["case"]["case_id"] == "R-001")
r001_payloads = []
for request_path in sorted(capture_root.glob("attempt-*/request-body.json")):
    assert request_path.is_file() and not request_path.is_symlink()
    request = json.loads(request_path.read_text(encoding="utf-8"))
    payload = json.loads(request["messages"][1]["content"])
    if payload["question"] == r001["case"]["question"]:
        r001_payloads.append(payload)
assert r001_payloads
for payload in r001_payloads:
    groups = payload["evidence_groups"]
    assert groups
    identifiers = [
        group.get("document", {}).get("identifier") for group in groups
    ]
    assert identifiers[0] == "99 TST 2001"
    unique_identifiers = {value for value in identifiers if value is not None}
    item_count_by_identifier = collections.Counter()
    packed_citations = 0
    for group, identifier in zip(groups, identifiers):
        items = group["items"]
        assert items
        packed_citations += len(items)
        item_count_by_identifier[identifier] += len(items)
    # R-001 formerly packed 118 citation atoms from 12 sources.  The bounded
    # request must now be led by its applicable document and be materially
    # smaller; this gate inspects the exact serialized request sent to Gemma.
    assert len(unique_identifiers) <= 6
    assert packed_citations <= 48
    assert item_count_by_identifier["99 TST 2001"] == max(
        item_count_by_identifier.values()
    )

targets = collections.Counter()
answered = 0
detail_names = {
    "nomic", "lexical_sql", "vector_sql", "fusion", "reconstruction", "tokenization"
}
for observation in api["cases"]:
    response = observation["response"]
    assert observation["metrics"]["status"] == observation["case"]["expected_status"]
    if response["status"] != "answered":
        continue
    answered += 1
    diagnostics = response["diagnostics"]
    target = diagnostics["prompt_target_tokens"]
    assert target in {8192, 12288, 16384}
    assert response["context_budget"]["tokens_used"] <= target + 2048
    assert set(diagnostics["timings_ms"]["retrieval_detail"]) == detail_names
    assert all(
        isinstance(value, int) and value >= 0
        for value in diagnostics["timings_ms"]["retrieval_detail"].values()
    )
    targets[target] += 1
assert answered == 6
summary = ",".join(f"{target}:{targets[target]}" for target in sorted(targets))
print(
    f"answered_prompt_targets={summary};answered_cases={answered};"
    "retrieval_timing_stages=6;"
    f"r001_capture_attempts={len(r001_payloads)};"
    f"r001_packed_citations={packed_citations};"
    f"r001_packed_documents={len(unique_identifiers)}"
)
PY
)" || block qualification_artifact_invalid artifact_validation
emit "milestone=artifact_validation;state=pass;$artifact_summary"
emit "database_artifact=$database_artifact"
emit "api_artifact=$api_artifact"
emit 'qualification=pass;v13_50=pass;web=pass;corpus_v3_database=pass;complete_api=pass'
emit 'next_gate=promote_corpus_v3_and_assemble_frontier_v1_3_candidate'
