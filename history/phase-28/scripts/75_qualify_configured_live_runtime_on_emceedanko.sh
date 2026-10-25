#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify one configured Ishikawa HTTP request through live model,
#   embedding, tokenization, and read-only PostgreSQL dependencies.
#
# Explicit execution from the repository root, after forwarding ports:
#   bash ./phase-28-apisachi-tokuli/scripts/75_qualify_configured_live_runtime_on_emceedanko.sh --run

usage() {
  sed -n '3,9p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run                      Authorize the bounded target qualification.' \
    '  --target VALUE             SSH destination or configured SSH alias.' \
    '  --expected-hostname NAME   Exact target short hostname.' \
    '  --expected-os-version VER  Exact expected Ubuntu major.minor version.' \
    '  --identity-file PATH       Optional explicit SSH private key.' \
    '  --validate-only            Validate all sources without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$ISHIKAWA_ROOT/application/python/ishikawa"
readonly CONFIG_ROOT="$ISHIKAWA_ROOT/config/templates"
readonly TARGET_HELPER="$SCRIPT_DIR/qualify-configured-live-runtime"
readonly TARGET_RUNNER="$SCRIPT_DIR/qualify_configured_live_runtime.py"
readonly LOCAL_EVALUATOR="$SCRIPT_DIR/evaluate_configured_live_runtime.py"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly ACCEPTED_SCRIPT_74_REPORT="$REPO_ROOT/local/reports/ishikawa-configured-model-dependencies/configured_model_dependencies_20261020T163502Z_G2t0ym.txt"
readonly ACCEPTED_SCRIPT_74_REPORT_SHA256='374c87ad6888aee8120c996dfc307cefccb6baf684bb125c2a1fd9ec667e70e3'
readonly ACCEPTED_SCRIPT_74_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/configured-model-dependencies/configured_model_dependencies_20261020T163502Z.json"
readonly ACCEPTED_SCRIPT_74_ARTIFACT_SHA256='eadca5dc1a3e15c9ba0eeebf5edc8a8891d6a861853596872cb9eb7b4504b044'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-configured-live-runtime"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/configured-live-runtime"
readonly CONFIG_FILES=(
  api_profile.yaml deployment.yaml injection_profile.yaml method_profile.yaml
  query_resolution_profile.yaml reconstruction_profile.yaml relationship_types.yaml
  relevance_profile.yaml retrieval_service_profile.yaml runtime_dependencies.yaml
  scope_profile.yaml sufficiency_profile.yaml
)

mapfile -t PYTHON_SOURCES < <(find "$PYTHON_ROOT" -maxdepth 1 -type f -name '*.py' -print | sort)
target="${APPLICATION_HOST_TARGET:-DankoSurface_EmceeDanko}"
expected_hostname="${APPLICATION_HOST_EXPECTED_HOSTNAME:-EmceeDanko}"
expected_os_version="${APPLICATION_HOST_EXPECTED_OS_VERSION:-24.04}"
identity_file="${APPLICATION_HOST_IDENTITY_FILE:-}"
run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --target) target="${2:-}"; shift 2 ;;
    --expected-hostname) expected_hostname="${2:-}"; shift 2 ;;
    --expected-os-version) expected_os_version="${2:-}"; shift 2 ;;
    --identity-file) identity_file="${2:-}"; shift 2 ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'ERROR: unsupported argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || { printf 'BLOCKED: choose exactly one of --run or --validate-only.\n' >&2; exit 2; }
[[ "$target" =~ ^[A-Za-z0-9_@.:-]+$ ]] || { printf 'BLOCKED: invalid SSH target or alias.\n' >&2; exit 2; }
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || { printf 'BLOCKED: invalid expected hostname.\n' >&2; exit 2; }
[[ "$expected_os_version" =~ ^[0-9]{2}\.[0-9]{2}$ ]] || { printf 'BLOCKED: invalid expected Ubuntu version.\n' >&2; exit 2; }
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] || { printf 'BLOCKED: identity file is unsafe.\n' >&2; exit 2; }
fi
for required in awk bash basename chmod cp date find grep install mkdir mktemp python3 rm scp sha256sum sort ssh stat tee timeout tr wc; do
  command -v "$required" >/dev/null 2>&1 || { printf 'BLOCKED: missing local command: %s\n' "$required" >&2; exit 2; }
done
(( ${#PYTHON_SOURCES[@]} > 0 )) || { printf 'BLOCKED: no Python runtime sources were found.\n' >&2; exit 2; }
for source in "$TARGET_HELPER" "$TARGET_RUNNER" "$LOCAL_EVALUATOR" "$TEST_RUNNER" "$ACCEPTED_SCRIPT_74_REPORT" "$ACCEPTED_SCRIPT_74_ARTIFACT" "${PYTHON_SOURCES[@]}"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || { printf 'BLOCKED: a required Script 75 input is missing or unsafe.\n' >&2; exit 2; }
done
for name in "${CONFIG_FILES[@]}"; do
  [[ -f "$CONFIG_ROOT/$name" && ! -L "$CONFIG_ROOT/$name" && -r "$CONFIG_ROOT/$name" ]] || { printf 'BLOCKED: a required runtime profile is missing or unsafe.\n' >&2; exit 2; }
done
[[ "$(sha256sum "$ACCEPTED_SCRIPT_74_REPORT" | awk '{print $1}')" == "$ACCEPTED_SCRIPT_74_REPORT_SHA256" ]] || { printf 'BLOCKED: accepted Script 74 report identity changed.\n' >&2; exit 2; }
[[ "$(sha256sum "$ACCEPTED_SCRIPT_74_ARTIFACT" | awk '{print $1}')" == "$ACCEPTED_SCRIPT_74_ARTIFACT_SHA256" ]] || { printf 'BLOCKED: accepted Script 74 artifact identity changed.\n' >&2; exit 2; }
for fact in \
  'configured_model_dependency_evaluation=pass' \
  'tokenization_adapter=pass;embedding_adapter=pass;generation_called=false' \
  'target_changed=false;forwarding_changed=false;operator_forward_ports_after_test=listening;credentials_retained=false;generation_calls=0;tokenization_calls=2;embedding_calls=2' \
  'script_74_configured_model_dependencies=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_SCRIPT_74_REPORT" || { printf 'BLOCKED: an accepted Script 74 fact is absent.\n' >&2; exit 2; }
done

bash -n "$TARGET_HELPER" "$TEST_RUNNER"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' "$TARGET_RUNNER" "$LOCAL_EVALUATOR" "${PYTHON_SOURCES[@]}"
for neutral_source in "$TARGET_HELPER" "$TARGET_RUNNER"; do
  if grep -Eq '(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)' "$neutral_source" || grep -Eiq 'phase[-_ ]?[0-9]+|Danko|org[_ -]?lab|Agent|repository' "$neutral_source"; then
    printf 'BLOCKED: development or environment jargon found in a neutral target source.\n' >&2
    exit 2
  fi
done

work_root="$(mktemp -d /tmp/ishikawa-script-75.XXXXXX)"
stage_root="$work_root/stage"
mkdir -m 0700 -p -- "$stage_root/payload/ishikawa" "$stage_root/payload/config"
report_path=""
remote_root=""
remote_created=false
master_started=false
ssh_args=()
emit() { if [[ -n "$report_path" ]]; then printf '%s\n' "$1" | tee -a "$report_path"; else printf '%s\n' "$1"; fi; }
cleanup() {
  local status="$?" cleanup_code=0 close_code=0
  trap - EXIT INT TERM
  set +e
  if [[ "$remote_created" == true && "$master_started" == true ]]; then
    timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "rm -rf -- '$remote_root'" >/dev/null 2>&1 || cleanup_code=$?
    if (( cleanup_code == 0 )); then emit 'cleanup_remote_temporary_files=removed'; else emit "cleanup_remote_temporary_files=review_required;exit_code=$cleanup_code"; status=1; fi
  else emit 'cleanup_remote_temporary_files=not_required'; fi
  if [[ "$master_started" == true ]]; then
    timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1 || close_code=$?
    emit "cleanup_ssh_master_exit_code=$close_code"
    (( close_code == 0 )) || status=1
  fi
  if [[ "$work_root" == /tmp/ishikawa-script-75.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

evaluator_self_test="$work_root/evaluator-self-test.txt"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$LOCAL_EVALUATOR" --self-test >"$evaluator_self_test"
grep -Fxq 'configured_live_runtime_evaluator_self_test=pass' "$evaluator_self_test" || { printf 'script_75_configured_live_runtime=blocked;reason=evaluator_self_test_failed\n' >&2; exit 1; }
observer_self_test="$work_root/observer-self-test.txt"
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT/.." python3 -B "$TARGET_RUNNER" --self-test-observer >"$observer_self_test"
grep -Fxq 'configured_executor_observer_self_test=pass' "$observer_self_test" || { printf 'script_75_configured_live_runtime=blocked;reason=executor_observer_self_test_failed\n' >&2; exit 1; }
test_result="$work_root/tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || { printf 'script_75_configured_live_runtime=blocked;reason=test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s\n' "$(sha256sum "$test_result" | awk '{print $1}')" "$(stat -c '%s' "$test_result")" >&2; exit 1; }
grep -Fq 'Ran 270 tests' "$test_result" || { printf 'script_75_configured_live_runtime=blocked;reason=test_count_mismatch\n' >&2; exit 1; }
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || { printf 'script_75_configured_live_runtime=blocked;reason=test_pass_marker_absent\n' >&2; exit 1; }

for source in "${PYTHON_SOURCES[@]}"; do install -m 0600 "$source" "$stage_root/payload/ishikawa/$(basename "$source")"; done
for name in "${CONFIG_FILES[@]}"; do install -m 0600 "$CONFIG_ROOT/$name" "$stage_root/payload/config/$name"; done
install -m 0600 "$TARGET_HELPER" "$stage_root/qualify-configured-live-runtime"
install -m 0600 "$TARGET_RUNNER" "$stage_root/qualify_configured_live_runtime.py"
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$stage_root/payload" python3 -B -c 'import ishikawa.runtime, ishikawa.http_listener'
payload_manifest="$stage_root/payload.sha256"
: >"$payload_manifest"
for source in "$stage_root"/payload/ishikawa/*.py; do printf '%s  payload/ishikawa/%s\n' "$(sha256sum "$source" | awk '{print $1}')" "$(basename "$source")" >>"$payload_manifest"; done
for source in "$stage_root"/payload/config/*.yaml; do printf '%s  payload/config/%s\n' "$(sha256sum "$source" | awk '{print $1}')" "$(basename "$source")" >>"$payload_manifest"; done
printf '%s  %s\n' "$(sha256sum "$stage_root/qualify_configured_live_runtime.py" | awk '{print $1}')" qualify_configured_live_runtime.py >>"$payload_manifest"
manifest_sha256="$(sha256sum "$payload_manifest" | awk '{print $1}')"
manifest_entries="$(wc -l <"$payload_manifest" | tr -d ' ')"
helper_sha256="$(sha256sum "$TARGET_HELPER" | awk '{print $1}')"
runner_sha256="$(sha256sum "$TARGET_RUNNER" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$LOCAL_EVALUATOR" | awk '{print $1}')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_configured_live_runtime_qualification_source' \
    'target_contact=false;listener_started=false;database_contact=false;model_call=false;credential_read=false' \
    "script_sha256=$script_sha256;helper_sha256=$helper_sha256;runner_sha256=$runner_sha256;evaluator_sha256=$evaluator_sha256" \
    "payload_manifest_sha256=$manifest_sha256;payload_file_count=$manifest_entries" \
    "accepted_script_74_report_sha256=$ACCEPTED_SCRIPT_74_REPORT_SHA256;accepted_script_74_artifact_sha256=$ACCEPTED_SCRIPT_74_ARTIFACT_SHA256" \
    'local_tests=270;failures=0;errors=0;staged_package_import=pass' \
    'script_75_configured_live_runtime_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/configured_live_runtime_${timestamp}_XXXXXX.txt")"
remote_root="/tmp/configured-live-runtime-$timestamp-$$"
emit 'purpose=qualify_configured_live_runtime_against_empty_catalog'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;helper_sha256=$helper_sha256;runner_sha256=$runner_sha256;evaluator_sha256=$evaluator_sha256"
emit "payload_manifest_sha256=$manifest_sha256;payload_file_count=$manifest_entries"
emit "accepted_script_74_report_sha256=$ACCEPTED_SCRIPT_74_REPORT_SHA256;accepted_script_74_artifact_sha256=$ACCEPTED_SCRIPT_74_ARTIFACT_SHA256"
emit 'authorized_actions=stage_checksum_bound_runtime_start_existing_postgresql_verify_empty_accepted_database_prompt_for_three_runtime_credentials_bind_temporary_loopback_listener_send_one_synthetic_professional_question_call_configured_dependencies_stop_listener_verify_database_unchanged_stop_postgresql_remove_target_temporary_files'
emit 'non_actions=no_forward_start_stop_or_change_no_package_firewall_schema_or_data_change_no_organizational_content_no_grounded_generation_no_secret_or_raw_content_retention'
emit "selected_target=$target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version"
emit 'operator_expectation=ssh_key_passphrase_up_to_once;target_sudo_password_may_be_prompted;gemma_key_once;nomic_key_once;retrieval_database_password_once;script_leaves_forwarding_running=true'
emit 'local_tests=270;failures=0;errors=0'

control_path="$work_root/ssh-control"
ssh_args=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto -o "ControlPath=$control_path" -o ControlPersist=1800)
if [[ -n "$identity_file" ]]; then ssh_args+=(-i "$identity_file" -o IdentitiesOnly=yes); fi
emit 'milestone=authentication;state=waiting_for_operator_if_prompted'
timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$target" >/dev/null 2>&1 || { emit 'script_75_configured_live_runtime=blocked;reason=ssh_master_start_failed'; exit 1; }
master_started=true
emit 'milestone=authentication;state=pass'
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root' && mkdir -m 0700 -- '$remote_root/payload' '$remote_root/payload/ishikawa' '$remote_root/payload/config'" >/dev/null || { emit 'script_75_configured_live_runtime=blocked;reason=remote_temporary_directory_not_created'; exit 1; }
remote_created=true
timeout --foreground 180 scp "${ssh_args[@]}" "$stage_root/qualify-configured-live-runtime" "$stage_root/qualify_configured_live_runtime.py" "$stage_root/payload.sha256" "$target:$remote_root/" >/dev/null || { emit 'script_75_configured_live_runtime=blocked;reason=root_payload_copy_failed'; exit 1; }
timeout --foreground 180 scp "${ssh_args[@]}" "$stage_root"/payload/ishikawa/*.py "$target:$remote_root/payload/ishikawa/" >/dev/null || { emit 'script_75_configured_live_runtime=blocked;reason=python_payload_copy_failed'; exit 1; }
timeout --foreground 120 scp "${ssh_args[@]}" "$stage_root"/payload/config/*.yaml "$target:$remote_root/payload/config/" >/dev/null || { emit 'script_75_configured_live_runtime=blocked;reason=config_payload_copy_failed'; exit 1; }
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "cd '$remote_root' && printf '%s  %s\n%s  %s\n' '$helper_sha256' qualify-configured-live-runtime '$manifest_sha256' payload.sha256 | sha256sum --check --strict -" >/dev/null || { emit 'script_75_configured_live_runtime=blocked;reason=target_outer_payload_hash_mismatch'; exit 1; }
emit 'milestone=target_payload_verification;state=pass'

emit 'milestone=configured_live_runtime;state=waiting_for_operator_sudo_and_credentials'
set +e
timeout --foreground 900 ssh "${ssh_args[@]}" -tt "$target" "cd '$remote_root' && sudo -p '[sudo] password for configured live runtime qualification: ' bash ./qualify-configured-live-runtime '$expected_hostname' '$expected_os_version' '$remote_root' '$manifest_sha256' '$manifest_entries' > qualification-result.txt" </dev/tty
remote_code=$?
set -e
emit "remote_execution_exit_code=$remote_code;raw_stderr_retained=false"
fetched_result="$work_root/qualification-result.txt"
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/qualification-result.txt" "$fetched_result" >/dev/null || { emit 'script_75_configured_live_runtime=blocked;reason=result_fetch_failed'; exit 1; }
output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then output_contract=blocked; continue; fi
  emit "$line"
done <"$fetched_result"
emit "remote_output_contract=$output_contract"
pass_markers="$(grep -Fxc 'configured_live_runtime_target=pass' "$fetched_result" || true)"
blocked_markers="$(grep -Ec '^configured_live_runtime=blocked;' "$fetched_result" || true)"
if (( remote_code != 0 )) || [[ "$output_contract" != pass || "$pass_markers" != 1 || "$blocked_markers" != 0 ]]; then
  emit 'milestone=configured_live_runtime;state=blocked'
  emit "script_75_configured_live_runtime=blocked;local_report=$report_path;next_gate=review_content_free_result_before_any_retry"
  exit 1
fi

fetched_artifact="$work_root/configured-live-runtime.json"
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/configured-live-runtime.json" "$fetched_artifact" >/dev/null || { emit 'script_75_configured_live_runtime=blocked;reason=artifact_fetch_failed'; exit 1; }
evaluation_result="$work_root/evaluation.txt"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$LOCAL_EVALUATOR" --artifact "$fetched_artifact" >"$evaluation_result"
grep -Fxq 'configured_live_runtime_evaluation=pass' "$evaluation_result" || { emit 'script_75_configured_live_runtime=blocked;reason=local_evaluation_failed'; exit 1; }
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit 'milestone=configured_live_runtime;state=pass'

artifact_sha256="$(sha256sum "$fetched_artifact" | awk '{print $1}')"
artifact_path="$ARTIFACT_ROOT/configured_live_runtime_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || { emit 'script_75_configured_live_runtime=blocked;reason=artifact_path_exists'; exit 1; }
cp -- "$fetched_artifact" "$artifact_path"
[[ "$(sha256sum "$artifact_path" | awk '{print $1}')" == "$artifact_sha256" ]] || { emit 'script_75_configured_live_runtime=blocked;reason=retained_artifact_identity_mismatch'; exit 1; }
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$(stat -c '%s' "$artifact_path")"
emit "accepted_checksum=$checksum_path"
emit 'accepted_database_unchanged=true;accepted_database_rows=0;postgresql_restored_stopped_disabled=true;retrieval_listener_stopped=true;forwarding_changed=false'
emit "script_75_configured_live_runtime=pass;local_report=$report_path;next_gate=implement_operator_ingestion_command"
