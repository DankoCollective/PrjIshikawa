#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the explicit lifecycle command for the complete Ishikawa stack.
#
# Mental model:
#   Inspect final sources, run every native test, and exercise start, status,
#   stop, missing-secret rejection, and failed-start rollback in a disposable
#   installed tree with deterministic local command adapters.
#
# Inputs or prerequisites:
#   Current Ishikawa sources, final configuration templates, the stack-control
#   contract, CODING_STANDARD.md, Python 3.12, and PyYAML.
#
# Outputs:
#   Content-free local qualification evidence. No real service, database,
#   container, image, credential, model endpoint, forwarding session, corpus,
#   or host port is contacted or changed.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/100_qualify_explicit_stack_control.sh --run

usage() {
  sed -n '3,21p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Run locally and retain content-free evidence.' \
    '  --validate-only Run the same local proof without retaining evidence.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly STACK_COMMAND="$ISHIKAWA_ROOT/scripts/ishikawa-stack"
readonly STACK_CONTRACT="$ISHIKAWA_ROOT/docs/STACK_CONTROL.md"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_explicit_stack_control.py"
readonly CODING_STANDARD="$REPO_ROOT/CODING_STANDARD.md"
readonly ACCEPTED_REPORT="$REPO_ROOT/local/reports/ishikawa-nextjs-chat-ui/nextjs_chat_ui_20261021T015840Z_rPvOfz.txt"
readonly ACCEPTED_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/nextjs-chat-ui/nextjs_chat_ui_qualification_20261021T015840Z.json"
readonly ACCEPTED_CHECKSUM="$ACCEPTED_ARTIFACT.sha256"
readonly ACCEPTED_REPORT_SHA256='66a6ebe256296d4c8102681027a9297297302e1b472fafe66ab381ae37158da3'
readonly ACCEPTED_ARTIFACT_SHA256='a42228271096864be11126ad6de610ba6c57c087bd9776eff07c75e245912037'
readonly ACCEPTED_CHECKSUM_SHA256='5c344466e3f8fa3e18fff0b8923450ee4f31b377efbe661c7baa36662009b7c0'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-explicit-stack-control"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/explicit-stack-control"

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_100_explicit_stack_control=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_100_explicit_stack_control=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in bash chmod cp date grep mkdir mktemp python3 rm sed sha256sum stat tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_100_explicit_stack_control=blocked;reason=local_command_missing\n' >&2
    exit 2
  }
done
for required_file in \
  "$STACK_COMMAND" "$STACK_CONTRACT" "$TEST_RUNNER" "$EVALUATOR" \
  "$CODING_STANDARD" "$ACCEPTED_REPORT" "$ACCEPTED_ARTIFACT" \
  "$ACCEPTED_CHECKSUM"; do
  [[ -f "$required_file" && ! -L "$required_file" && -r "$required_file" ]] || {
    printf 'script_100_explicit_stack_control=blocked;reason=required_input_unsafe\n' >&2
    exit 2
  }
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_100_explicit_stack_control=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}
check_sha256 "$ACCEPTED_REPORT" "$ACCEPTED_REPORT_SHA256" 'accepted_report'
check_sha256 "$ACCEPTED_ARTIFACT" "$ACCEPTED_ARTIFACT_SHA256" 'accepted_artifact'
check_sha256 "$ACCEPTED_CHECKSUM" "$ACCEPTED_CHECKSUM_SHA256" 'accepted_checksum'
(
  cd -- "$(dirname -- "$ACCEPTED_ARTIFACT")"
  sha256sum --check --strict "$(basename -- "$ACCEPTED_CHECKSUM")" >/dev/null
) || { printf 'script_100_explicit_stack_control=blocked;reason=accepted_checksum_failed\n' >&2; exit 2; }
for fact in \
  'nextjs_chat_ui_qualification=pass' \
  'native_tests=360;javascript_tests=8;next_build=pass' \
  'http_proof=liveness:pass,readiness:pass,page:pass,chat_proxy:pass;temporary_cleanup=pass' \
  'script_99_nextjs_chat_ui=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_REPORT" || {
    printf 'script_100_explicit_stack_control=blocked;reason=accepted_report_contract_failed\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}" "$STACK_COMMAND" "$TEST_RUNNER"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$EVALUATOR"
for portable_source in "$STACK_COMMAND" "$STACK_CONTRACT"; do
  if grep -Eiq 'phase[-_ ]?[0-9]+|(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)|Danko|org[_ -]?lab|Agent|repository|Script[[:space:]_-]*[0-9]+' "$portable_source"; then
    printf 'script_100_explicit_stack_control=blocked;reason=installed_source_jargon_found\n' >&2
    exit 2
  fi
done

work_root="$(mktemp -d /tmp/ishikawa-script-100.XXXXXX)"
artifact_committed=false
artifact_path=''
checksum_path=''
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$artifact_committed" != true ]]; then
    [[ "$artifact_path" == "$ARTIFACT_ROOT"/explicit_stack_control_qualification_*.json ]] && rm -f -- "$artifact_path"
    [[ "$checksum_path" == "$ARTIFACT_ROOT"/explicit_stack_control_qualification_*.json.sha256 ]] && rm -f -- "$checksum_path"
  fi
  if [[ "$work_root" == /tmp/ishikawa-script-100.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/native-tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  printf 'script_100_explicit_stack_control=blocked;reason=test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$test_result" | awk '{print $1}')" "$(stat -c '%s' "$test_result")" >&2
  exit 1
}
grep -Fq 'Ran 360 tests' "$test_result" || {
  printf 'script_100_explicit_stack_control=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_100_explicit_stack_control=blocked;reason=test_pass_marker_absent\n' >&2
  exit 1
}

qualification="$work_root/qualification.json"
evaluation="$work_root/evaluation.txt"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" \
  --command "$STACK_COMMAND" \
  --contract "$STACK_CONTRACT" \
  --exercise-root "$ISHIKAWA_ROOT" \
  --output "$qualification" >"$evaluation" || {
  printf 'script_100_explicit_stack_control=blocked;reason=stack_control_evaluation_failed\n' >&2
  exit 1
}
for fact in \
  'actions=start,status,stop;boot_enabled=false' \
  'start_order=postgresql,retrieval,web;readiness_between=true' \
  'stop_order=web,retrieval,postgresql' \
  'forwarding_owned=false;image_changed=false;configuration_changed=false' \
  'credential_values=environment-only,not-printed,not-stored' \
  'rollback=required;managed_state=owner-only' \
  'lifecycle=start-ready-status-stop-stopped;rollback=pass;missing_credential=blocked' \
  'explicit_stack_control_qualification=pass'; do
  grep -Fqx "$fact" "$evaluation" || {
    printf 'script_100_explicit_stack_control=blocked;reason=evaluation_contract_mismatch\n' >&2
    exit 1
  }
done

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'local_tests=360;failures=0;errors=0' \
    'lifecycle=start-ready-status-stop-stopped;rollback=pass;credential_disclosure=false' \
    'script_100_explicit_stack_control_source=pass'
  exit 0
fi

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
command_sha256="$(sha256sum "$STACK_COMMAND" | awk '{print $1}')"
contract_sha256="$(sha256sum "$STACK_CONTRACT" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
qualification_sha256="$(sha256sum "$qualification" | awk '{print $1}')"
qualification_bytes="$(stat -c '%s' "$qualification")"
mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/explicit_stack_control_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  printf 'script_100_explicit_stack_control=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
cp -- "$qualification" "$artifact_path"
printf '%s  %s\n' "$qualification_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true
(
  cd -- "$ARTIFACT_ROOT"
  sha256sum --check --strict "$(basename -- "$checksum_path")" >/dev/null
) || { printf 'script_100_explicit_stack_control=blocked;reason=retained_checksum_failed\n' >&2; exit 1; }
artifact_committed=true

report_path="$(mktemp "$REPORT_ROOT/explicit_stack_control_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=qualify_explicit_stack_control'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256"
emit "stack_command_sha256=$command_sha256;stack_contract_sha256=$contract_sha256"
emit "accepted_script_99_report_sha256=$ACCEPTED_REPORT_SHA256;accepted_script_99_artifact_sha256=$ACCEPTED_ARTIFACT_SHA256"
emit 'authorized_actions=read_sources_run_native_tests_run_disposable_command_adapter_lifecycle_retain_content_free_evidence'
emit 'non_actions=no_service_database_container_image_credential_model_forwarding_corpus_or_host_port_contact_or_change'
while IFS= read -r line; do emit "$line"; done <"$evaluation"
emit 'local_tests=360;failures=0;errors=0'
emit 'credential_disclosure=false;target_contact=false;service_changed=false;database_changed=false;image_changed=false'
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$qualification_sha256;accepted_artifact_bytes=$qualification_bytes;accepted_checksum=$checksum_path"
emit "script_100_explicit_stack_control=pass;local_report=$report_path;next_gate=refresh_final_state_application_package"
chmod 0600 "$report_path" 2>/dev/null || true
