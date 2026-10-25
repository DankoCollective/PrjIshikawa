#!/usr/bin/env bash
# Qualify frozen V13-49 in one operator command.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/202_qualify_v13_49_exact_generation_boundary.sh --validate-only
#   bash ./phase-28-apisachi-tokuli/scripts/202_qualify_v13_49_exact_generation_boundary.sh --run

set -Eeuo pipefail
umask 077

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly WEB_ROOT="$PRODUCT_ROOT/application/web"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly PRODUCT_PROFILE="$PRODUCT_ROOT/config/templates/product.yaml"
readonly INNER_GATE="$SCRIPT_DIR/201_ingest_and_qualify_isolated_synthetic_corpus_v3.sh"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v13-49-exact-generation-boundary"

readonly RECONSTRUCTION="$PYTHON_ROOT/ishikawa/reconstruction.py"
readonly GENERATION="$PYTHON_ROOT/ishikawa/generation.py"
readonly GENERATION_TRANSPORT="$PYTHON_ROOT/ishikawa/generation_transport.py"
readonly TOKENIZATION="$PYTHON_ROOT/ishikawa/tokenization.py"
readonly POSTGRES_RETRIEVAL="$PYTHON_ROOT/ishikawa/postgres_retrieval.py"
readonly RETRIEVAL_SERVICE="$PYTHON_ROOT/ishikawa/retrieval_service.py"
readonly RUNTIME="$PYTHON_ROOT/ishikawa/runtime.py"
readonly RETRIEVAL="$PYTHON_ROOT/ishikawa/retrieval.py"
readonly METHOD_PROFILE="$PRODUCT_ROOT/config/templates/method_profile.yaml"
readonly RELATIONSHIP_REGISTRY="$PRODUCT_ROOT/config/templates/relationship_types.yaml"
readonly DATABASE_SCHEMA="$PRODUCT_ROOT/packaging/database/schema.sql"
readonly CHAT_WORKSPACE="$WEB_ROOT/components/chat-workspace.js"
readonly WEB_PACKAGE="$WEB_ROOT/package.json"
readonly CHAT_CONTRACT_TEST="$WEB_ROOT/tests/chat-contract.test.mjs"
readonly PRESENTATION_TEST="$WEB_ROOT/tests/presentation.test.mjs"
readonly RUNTIME_CONFIG_TEST="$WEB_ROOT/tests/runtime-config.test.mjs"

readonly RECONSTRUCTION_SHA256='9bf0dfcf6675ddaf1321a154071987f85992ed353bdba34fb6c5cd06bb44d9d0'
readonly GENERATION_SHA256='5c934d4d8a880d4c3b72fd440c7eb2af1279b535f1e90a8950aa52b75cdc40d3'
readonly GENERATION_TRANSPORT_SHA256='969753984403a6deed39c273cb9154a851fe30ebeb44080487afdb5d784741d9'
readonly TOKENIZATION_SHA256='6332b7adaacab494cce1ebf765c9445ca6ee2638a45ea8c88304a915de6b7be8'
readonly POSTGRES_RETRIEVAL_SHA256='65a81fbcbc0a41b76bf421ae3f391046420687e5c43105f345e6f2286370f619'
readonly RETRIEVAL_SERVICE_SHA256='7cfc21d659f9385fd0abcd555b93afbc258d7852857c0b441dae05a56e2e29aa'
readonly RUNTIME_SHA256='ba67dc5d6c2974ce00b37815137a38e9d516031abc9a14eb2b3229924f895ecc'
readonly RETRIEVAL_SHA256='a1b7a83543bb1d2bc99282606af6b4270cd120c945b37f6df215cc9a687665eb'
readonly METHOD_PROFILE_SHA256='6fd44f53b22a0a507d8c615a77c71ddc87f25e224dc51f2d3dcbeed1cabd61bf'
readonly RELATIONSHIP_REGISTRY_SHA256='64e2dcec8b786c506f87e7767a2fabd4b2f295e44d88722563a07a8d74d7a9b5'
readonly DATABASE_SCHEMA_SHA256='1fdbed2439fb5bfecaef5dd857f380661c298f8459d6cc2319114b78e5a09c5d'
readonly CHAT_WORKSPACE_SHA256='cfd507dc744c53511944c42e3d6c6b046425d4394d1d3229d3c95670acfdbc3d'
readonly WEB_PACKAGE_SHA256='cc53fbb830c2199923f68c98f31fae3659c10a6a64b55dfdf810b5c38a3bb505'
readonly CHAT_CONTRACT_TEST_SHA256='ba587ca82e6e97d2e8b0eaa9390ca6361b98b6ed0cd17c5f4944ba1e8013bcec'
readonly PRESENTATION_TEST_SHA256='d4e6b2503e95b161ddc23fca2c29fa615bc439387e008599abee7626abe95d95'
readonly RUNTIME_CONFIG_TEST_SHA256='a2ce153caa5178f05cb13e4d2c4c2009ad5210b6f2528cf26cbda2709c8e9d0b'
readonly INNER_GATE_SHA256='61df5b4e9852922b79244f33a663811ddbeb66e92bbbf351e86f482b05edfe88'

mode="${1:-}"
if [[ "$#" -ne 1 || ( "$mode" != '--validate-only' && "$mode" != '--run' ) ]]; then
  printf '%s\n' \
    'FAILURE DETAIL' \
    'stage=argument_validation' \
    'reason=exactly_one_mode_required' \
    'detail=Script 202 requires exactly one mode: --validate-only or --run.' \
    'operator_action=Rerun Script 202 with exactly one supported mode.' \
    '' \
    'SCRIPT RESULT' \
    'script_202_v13_49_exact_generation_boundary=blocked' >&2
  exit 2
fi

block_preflight() {
  printf '%s\n' \
    'FAILURE DETAIL' \
    'stage=preflight' \
    "reason=$1" \
    'detail=A frozen V13-49 source, local prerequisite, or self-test did not match.' \
    'operator_action=Correct the named preflight reason, then rerun this same Script 202 command.' \
    '' \
    'SCRIPT RESULT' \
    'script_202_v13_49_exact_generation_boundary=blocked' >&2
  exit "${2:-1}"
}

for command_name in awk bash date docker dpkg grep id kill mkdir mktemp python3 rm \
  sed sha256sum sleep stat sudo tee; do
  if [[ "$mode" == '--validate-only' && "$command_name" =~ ^(docker|dpkg|sudo)$ ]]; then
    continue
  fi
  command -v "$command_name" >/dev/null 2>&1 \
    || block_preflight "local_command_missing_${command_name}" 2
done

check_file() {
  local path="$1" expected="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] \
    || block_preflight "${label}_unsafe"
  [[ "$(sha256sum -- "$path" | awk '{print $1}')" == "$expected" ]] \
    || block_preflight "${label}_identity_changed"
}

check_file "$RECONSTRUCTION" "$RECONSTRUCTION_SHA256" reconstruction
check_file "$GENERATION" "$GENERATION_SHA256" generation
check_file "$GENERATION_TRANSPORT" "$GENERATION_TRANSPORT_SHA256" generation_transport
check_file "$TOKENIZATION" "$TOKENIZATION_SHA256" tokenization
check_file "$POSTGRES_RETRIEVAL" "$POSTGRES_RETRIEVAL_SHA256" postgres_retrieval
check_file "$RETRIEVAL_SERVICE" "$RETRIEVAL_SERVICE_SHA256" retrieval_service
check_file "$RUNTIME" "$RUNTIME_SHA256" runtime
check_file "$RETRIEVAL" "$RETRIEVAL_SHA256" frozen_retrieval
check_file "$METHOD_PROFILE" "$METHOD_PROFILE_SHA256" frozen_method_profile
check_file "$RELATIONSHIP_REGISTRY" "$RELATIONSHIP_REGISTRY_SHA256" frozen_relationship_registry
check_file "$DATABASE_SCHEMA" "$DATABASE_SCHEMA_SHA256" frozen_database_schema
check_file "$CHAT_WORKSPACE" "$CHAT_WORKSPACE_SHA256" chat_workspace
check_file "$WEB_PACKAGE" "$WEB_PACKAGE_SHA256" web_package
check_file "$CHAT_CONTRACT_TEST" "$CHAT_CONTRACT_TEST_SHA256" chat_contract_test
check_file "$PRESENTATION_TEST" "$PRESENTATION_TEST_SHA256" presentation_test
check_file "$RUNTIME_CONFIG_TEST" "$RUNTIME_CONFIG_TEST_SHA256" runtime_config_test
check_file "$INNER_GATE" "$INNER_GATE_SHA256" inner_gate
[[ -f "$DECISIONS" && ! -L "$DECISIONS" && -r "$DECISIONS" ]] \
  || block_preflight decisions_unsafe
[[ -f "$PRODUCT_PROFILE" && ! -L "$PRODUCT_PROFILE" && -r "$PRODUCT_PROFILE" ]] \
  || block_preflight product_profile_unsafe
grep -Eq '^\| `V13-49` \|.*\| FROZEN \|$' "$DECISIONS" \
  || block_preflight v13_49_not_frozen
grep -Fq 'def count_messages(' "$TOKENIZATION" \
  || block_preflight exact_chat_tokenizer_absent
grep -Fq 'generation prompt token count changed after admission' "$RETRIEVAL_SERVICE" \
  || block_preflight generation_admission_invariant_absent
grep -Fq 'Packed citations' "$CHAT_WORKSPACE" \
  || block_preflight packed_citations_label_absent
grep -Fq 'Cited results' "$PRESENTATION_TEST" \
  || block_preflight retired_diagnostic_label_test_absent
grep -Fq '"test": "node --test tests/chat-contract.test.mjs tests/presentation.test.mjs tests/runtime-config.test.mjs"' "$WEB_PACKAGE" \
  || block_preflight javascript_test_command_changed
javascript_test_declarations="$(
  grep -hEc '^test\(' \
    "$CHAT_CONTRACT_TEST" "$PRESENTATION_TEST" "$RUNTIME_CONFIG_TEST" \
    | awk '{ total += $1 } END { print total + 0 }'
)"
[[ "$javascript_test_declarations" == '17' ]] \
  || block_preflight javascript_test_inventory_changed

bash -n "${BASH_SOURCE[0]}" "$INNER_GATE" \
  || block_preflight shell_syntax_invalid
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$RECONSTRUCTION" "$GENERATION" "$GENERATION_TRANSPORT" "$TOKENIZATION" \
  "$POSTGRES_RETRIEVAL" "$RETRIEVAL_SERVICE" "$RUNTIME" \
  || block_preflight python_syntax_invalid

inner_validation="$({ bash "$INNER_GATE" --validate-only; } 2>&1)" \
  || {
    printf '%s\n' "$inner_validation" >&2
    block_preflight inner_gate_validation_failed
  }
grep -Fxq 'script_201_isolated_corpus_v3_api_qualification=ready' <<<"$inner_validation" \
  || block_preflight inner_gate_ready_marker_absent

script_sha256="$(sha256sum -- "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$mode" == '--validate-only' ]]; then
  printf '%s\n' \
    'purpose=validate_v13_49_exact_generation_boundary' \
    "script_sha256=$script_sha256" \
    'frozen_retrieval=body_mrr_at_20_0.895450;corpus=synthetic-corpus-v3;documents=30' \
    'qualification_order=web_tests_then_build_then_native_tests_then_r001_canary_then_remaining_12_cases' \
    'database_contact=false;model_contact=false;credential_read=false;service_started=false;corpus_changed=false' \
    '' \
    'SCRIPT RESULT' \
    'script_202_v13_49_exact_generation_boundary=ready'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" || block_preflight report_root_creation_failed
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/v13_49_exact_generation_boundary_${timestamp}_XXXXXX.txt")" \
  || block_preflight report_creation_failed
work_root="$(mktemp -d /tmp/ishikawa-script-202.XXXXXX)" \
  || block_preflight workspace_creation_failed
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
  [[ "$work_root" == /tmp/ishikawa-script-202.* && -d "$work_root" ]] \
    && rm -rf -- "$work_root"
  if (( status != 0 )) || [[ -n "$failure_reason" ]]; then
    result=blocked
    emit 'FAILURE DETAIL'
    emit "stage=${failure_stage:-unclassified}"
    emit "reason=${failure_reason:-unexpected_exit_${status}}"
    case "${failure_reason:-}" in
      docker_access_failed)
        emit 'detail=The local Docker daemon was not available after attended sudo authentication.'
        emit 'operator_action=Restore local Docker access and rerun Script 202.'
        ;;
      required_local_image_missing)
        emit "detail=The required architecture-matched local Node image was absent;image=${image:-not_resolved}."
        emit 'operator_action=Restore the already-approved local developer image; Script 202 will not pull one.'
        ;;
      javascript_tests_failed|next_build_failed)
        emit "detail=The local web ${failure_reason} check failed before any model or database contact."
        emit "operator_action=Inspect the retained content-free report and rerun Script 202 after correcting ${failure_reason}."
        ;;
      inner_gate_failed|inner_gate_pass_marker_absent)
        emit 'detail=The combined corpus-v3/R-001/full-API qualification did not pass. Its own FAILURE DETAIL above is authoritative.'
        emit 'operator_action=Use the nested stage, reason, detail, and operator_action above; do not infer from this wrapper label.'
        ;;
      *)
        emit 'detail=Script 202 stopped at the named bounded stage.'
        emit 'operator_action=Correct the named reason and rerun this same command.'
        ;;
    esac
  fi
  emit "local_report=$report_path"
  emit ''
  emit 'SCRIPT RESULT'
  emit "script_202_v13_49_exact_generation_boundary=$result"
  exit "$status"
}
trap cleanup EXIT
trap 'block interrupted INT 130' INT
trap 'block interrupted TERM 143' TERM

emit 'purpose=qualify_v13_49_exact_generation_boundary_and_corpus_v3_promotion_gate'
emit "started_utc=$timestamp;script_sha256=$script_sha256"
emit 'authorized_actions=run_network_isolated_web_tests_and_build_run_local_native_tests_start_disposable_postgresql_ingest_isolated_corpus_v3_contact_loopback_nomic_and_gemma_run_r001_then_remaining_cases_write_local_reports'
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
    tail -n 100 "$javascript_result" | tee -a "$report_path"
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
  tail -n 100 "$build_result" | tee -a "$report_path"
  block next_build_failed next_build
fi
emit 'milestone=next_build;state=pass'

failure_stage=combined_api_gate
emit 'milestone=combined_api_gate;state=start;order=native_tests_then_r001_canary_then_remaining_12_cases'
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
grep -Fxq 'next_gate=promote_corpus_v3_and_assemble_frontier_v1_3_candidate' "$inner_output" \
  || block inner_gate_pass_marker_absent combined_api_gate
emit 'milestone=combined_api_gate;state=pass;r001=pass;complete_api_cases=13/13'
emit 'qualification=pass;v13_49=pass;web=pass;corpus_v3_database=pass;complete_api=pass'
emit 'next_gate=promote_corpus_v3_and_assemble_frontier_v1_3_candidate'

