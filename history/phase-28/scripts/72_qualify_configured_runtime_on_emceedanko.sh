#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify configured Ishikawa runtime assembly and the temporary loopback
#   HTTP listener on the accepted application host without dependency contact.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/72_qualify_configured_runtime_on_emceedanko.sh --run

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
readonly TARGET_HELPER="$SCRIPT_DIR/qualify-application-host-runtime"
readonly TARGET_RUNNER="$SCRIPT_DIR/qualify_application_host_runtime.py"
readonly LOCAL_EVALUATOR="$SCRIPT_DIR/evaluate_application_host_runtime.py"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly ACCEPTED_SCRIPT_71_REPORT="$REPO_ROOT/local/reports/ishikawa-configured-tokenizer-endpoint/configured_tokenizer_endpoint_20261020T145212Z_VDiB05.txt"
readonly ACCEPTED_SCRIPT_71_REPORT_SHA256='c5723dcef56791c586ee2846ca09379da0f4f7832cb136a953baec8f76768ee2'
readonly ACCEPTED_SCRIPT_68_REPORT="$REPO_ROOT/local/reports/ishikawa-complete-retrieval-adapter-target/complete_retrieval_adapter_target_20261020T141141Z_0RVRGT.txt"
readonly ACCEPTED_SCRIPT_68_REPORT_SHA256='67a52cbdc7c240741d58d156938f17589032c8e1e68b64262e18a3c44f133b03'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-application-host-runtime"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/application-host-runtime"
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
for source in "$TARGET_HELPER" "$TARGET_RUNNER" "$LOCAL_EVALUATOR" "$TEST_RUNNER" "$ACCEPTED_SCRIPT_71_REPORT" "$ACCEPTED_SCRIPT_68_REPORT" "${PYTHON_SOURCES[@]}"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || { printf 'BLOCKED: a required Script 72 input is missing or unsafe.\n' >&2; exit 2; }
done
for name in "${CONFIG_FILES[@]}"; do
  [[ -f "$CONFIG_ROOT/$name" && ! -L "$CONFIG_ROOT/$name" && -r "$CONFIG_ROOT/$name" ]] || { printf 'BLOCKED: a required runtime profile is missing or unsafe.\n' >&2; exit 2; }
done
[[ "$(sha256sum "$ACCEPTED_SCRIPT_71_REPORT" | awk '{print $1}')" == "$ACCEPTED_SCRIPT_71_REPORT_SHA256" ]] || { printf 'BLOCKED: accepted Script 71 report identity changed.\n' >&2; exit 2; }
[[ "$(sha256sum "$ACCEPTED_SCRIPT_68_REPORT" | awk '{print $1}')" == "$ACCEPTED_SCRIPT_68_REPORT_SHA256" ]] || { printf 'BLOCKED: accepted Script 68 report identity changed.\n' >&2; exit 2; }
for fact in \
  'generation_tokenizer_endpoint_evaluation=pass' \
  'configuration_changed=false;service_initial_state_restored=true;credential_retained=false;model_generation_called=false;tokenization_calls=2' \
  'script_71_configured_tokenizer_endpoint=pass;' \
  'next_gate=qualify_configured_runtime_on_application_host'; do
  grep -Fq "$fact" "$ACCEPTED_SCRIPT_71_REPORT" || { printf 'BLOCKED: an accepted Script 71 fact is absent.\n' >&2; exit 2; }
done
for fact in \
  'host=EmceeDanko;os_version=24.04;architecture=amd64' \
  'python_version=3.12.3;psycopg_version=3.1.17' \
  'complete_retrieval_adapter_target_qualification=pass' \
  'accepted_database_unchanged=true' \
  'script_68_complete_retrieval_adapter_target=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_SCRIPT_68_REPORT" || { printf 'BLOCKED: an accepted application-host fact is absent.\n' >&2; exit 2; }
done

bash -n "$TARGET_HELPER" "$TEST_RUNNER"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' "$TARGET_RUNNER" "$LOCAL_EVALUATOR" "${PYTHON_SOURCES[@]}"
for neutral_source in "$TARGET_HELPER" "$TARGET_RUNNER"; do
  if grep -Eq '(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)' "$neutral_source" || grep -Eiq 'phase[-_ ]?[0-9]+|Danko|org[_ -]?lab|Agent|repository' "$neutral_source"; then
    printf 'BLOCKED: development or environment jargon found in a neutral target source.\n' >&2
    exit 2
  fi
done

work_root="$(mktemp -d /tmp/ishikawa-script-72.XXXXXX)"
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
  if [[ "$work_root" == /tmp/ishikawa-script-72.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

evaluator_self_test="$work_root/evaluator-self-test.txt"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$LOCAL_EVALUATOR" --self-test >"$evaluator_self_test"
grep -Fxq 'application_host_runtime_evaluator_self_test=pass' "$evaluator_self_test" || { printf 'script_72_application_host_runtime=blocked;reason=evaluator_self_test_failed\n' >&2; exit 1; }
test_result="$work_root/tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || { printf 'script_72_application_host_runtime=blocked;reason=test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s\n' "$(sha256sum "$test_result" | awk '{print $1}')" "$(stat -c '%s' "$test_result")" >&2; exit 1; }
grep -Fq 'Ran 270 tests' "$test_result" || { printf 'script_72_application_host_runtime=blocked;reason=test_count_mismatch\n' >&2; exit 1; }
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || { printf 'script_72_application_host_runtime=blocked;reason=test_pass_marker_absent\n' >&2; exit 1; }

for source in "${PYTHON_SOURCES[@]}"; do install -m 0600 "$source" "$stage_root/payload/ishikawa/$(basename "$source")"; done
for name in "${CONFIG_FILES[@]}"; do install -m 0600 "$CONFIG_ROOT/$name" "$stage_root/payload/config/$name"; done
install -m 0600 "$TARGET_HELPER" "$stage_root/qualify-application-host-runtime"
install -m 0600 "$TARGET_RUNNER" "$stage_root/qualify_application_host_runtime.py"
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$stage_root/payload" python3 -B -c 'import ishikawa.runtime, ishikawa.http_listener'
payload_manifest="$stage_root/payload.sha256"
: >"$payload_manifest"
for source in "$stage_root"/payload/ishikawa/*.py; do printf '%s  payload/ishikawa/%s\n' "$(sha256sum "$source" | awk '{print $1}')" "$(basename "$source")" >>"$payload_manifest"; done
for source in "$stage_root"/payload/config/*.yaml; do printf '%s  payload/config/%s\n' "$(sha256sum "$source" | awk '{print $1}')" "$(basename "$source")" >>"$payload_manifest"; done
printf '%s  %s\n' "$(sha256sum "$stage_root/qualify_application_host_runtime.py" | awk '{print $1}')" qualify_application_host_runtime.py >>"$payload_manifest"
manifest_sha256="$(sha256sum "$payload_manifest" | awk '{print $1}')"
manifest_entries="$(wc -l <"$payload_manifest" | tr -d ' ')"
helper_sha256="$(sha256sum "$TARGET_HELPER" | awk '{print $1}')"
runner_sha256="$(sha256sum "$TARGET_RUNNER" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$LOCAL_EVALUATOR" | awk '{print $1}')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_application_host_runtime_qualification_source' \
    'target_contact=false;listener_started=false;database_contact=false;model_call=false;credential_read=false' \
    "script_sha256=$script_sha256;helper_sha256=$helper_sha256;runner_sha256=$runner_sha256;evaluator_sha256=$evaluator_sha256" \
    "payload_manifest_sha256=$manifest_sha256;payload_file_count=$manifest_entries" \
    "accepted_script_71_report_sha256=$ACCEPTED_SCRIPT_71_REPORT_SHA256;accepted_script_68_report_sha256=$ACCEPTED_SCRIPT_68_REPORT_SHA256" \
    'local_tests=270;failures=0;errors=0;staged_package_import=pass' \
    'script_72_application_host_runtime_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/application_host_runtime_${timestamp}_XXXXXX.txt")"
remote_root="/tmp/application-host-runtime-$timestamp-$$"
emit 'purpose=qualify_configured_runtime_on_application_host'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;helper_sha256=$helper_sha256;runner_sha256=$runner_sha256;evaluator_sha256=$evaluator_sha256"
emit "payload_manifest_sha256=$manifest_sha256;payload_file_count=$manifest_entries"
emit "accepted_script_71_report_sha256=$ACCEPTED_SCRIPT_71_REPORT_SHA256;accepted_script_68_report_sha256=$ACCEPTED_SCRIPT_68_REPORT_SHA256"
emit 'authorized_actions=stage_checksum_bound_runtime_validate_application_host_bind_temporary_loopback_listener_send_one_synthetic_security_request_fetch_content_free_measurement_remove_target_temporary_files'
emit 'non_actions=no_sudo_no_package_or_service_change_no_database_contact_no_model_or_embedding_contact_no_credential_read_no_organizational_content'
emit "selected_target=$target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version"
emit 'operator_expectation=ssh_key_passphrase_up_to_once;sudo_prompt=none;application_secret_prompt=none'
emit 'local_tests=270;failures=0;errors=0'

control_path="$work_root/ssh-control"
ssh_args=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto -o "ControlPath=$control_path" -o ControlPersist=1800)
if [[ -n "$identity_file" ]]; then ssh_args+=(-i "$identity_file" -o IdentitiesOnly=yes); fi
emit 'milestone=authentication;state=waiting_for_operator_if_prompted'
timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$target" >/dev/null 2>&1 || { emit 'script_72_application_host_runtime=blocked;reason=ssh_master_start_failed'; exit 1; }
master_started=true
emit 'milestone=authentication;state=pass'
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root' && mkdir -m 0700 -- '$remote_root/payload' '$remote_root/payload/ishikawa' '$remote_root/payload/config'" >/dev/null || { emit 'script_72_application_host_runtime=blocked;reason=remote_temporary_directory_not_created'; exit 1; }
remote_created=true
timeout --foreground 180 scp "${ssh_args[@]}" "$stage_root/qualify-application-host-runtime" "$stage_root/qualify_application_host_runtime.py" "$stage_root/payload.sha256" "$target:$remote_root/" >/dev/null || { emit 'script_72_application_host_runtime=blocked;reason=root_payload_copy_failed'; exit 1; }
timeout --foreground 180 scp "${ssh_args[@]}" "$stage_root"/payload/ishikawa/*.py "$target:$remote_root/payload/ishikawa/" >/dev/null || { emit 'script_72_application_host_runtime=blocked;reason=python_payload_copy_failed'; exit 1; }
timeout --foreground 120 scp "${ssh_args[@]}" "$stage_root"/payload/config/*.yaml "$target:$remote_root/payload/config/" >/dev/null || { emit 'script_72_application_host_runtime=blocked;reason=config_payload_copy_failed'; exit 1; }
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "cd '$remote_root' && printf '%s  %s\n%s  %s\n' '$helper_sha256' qualify-application-host-runtime '$manifest_sha256' payload.sha256 | sha256sum --check --strict -" >/dev/null || { emit 'script_72_application_host_runtime=blocked;reason=target_outer_payload_hash_mismatch'; exit 1; }
emit 'milestone=target_payload_verification;state=pass'

emit 'milestone=application_host_runtime;state=start'
set +e
timeout --foreground 300 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "cd '$remote_root' && bash ./qualify-application-host-runtime '$expected_hostname' '$expected_os_version' '$remote_root' '$manifest_sha256' '$manifest_entries' > qualification-result.txt" </dev/null
remote_code=$?
set -e
emit "remote_execution_exit_code=$remote_code;raw_stderr_retained=false"
fetched_result="$work_root/qualification-result.txt"
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/qualification-result.txt" "$fetched_result" >/dev/null || { emit 'script_72_application_host_runtime=blocked;reason=result_fetch_failed'; exit 1; }
output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then output_contract=blocked; continue; fi
  emit "$line"
done <"$fetched_result"
emit "remote_output_contract=$output_contract"
pass_markers="$(grep -Fxc 'application_host_runtime_qualification=pass' "$fetched_result" || true)"
blocked_markers="$(grep -Ec '^application_host_runtime=blocked;' "$fetched_result" || true)"
if (( remote_code != 0 )) || [[ "$output_contract" != pass || "$pass_markers" != 1 || "$blocked_markers" != 0 ]]; then
  emit 'milestone=application_host_runtime;state=blocked'
  emit "script_72_application_host_runtime=blocked;local_report=$report_path;next_gate=review_content_free_result_before_any_retry"
  exit 1
fi

fetched_artifact="$work_root/application-host-runtime.json"
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/application-host-runtime.json" "$fetched_artifact" >/dev/null || { emit 'script_72_application_host_runtime=blocked;reason=artifact_fetch_failed'; exit 1; }
evaluation_result="$work_root/evaluation.txt"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$LOCAL_EVALUATOR" --artifact "$fetched_artifact" >"$evaluation_result"
grep -Fxq 'application_host_runtime_evaluation=pass' "$evaluation_result" || { emit 'script_72_application_host_runtime=blocked;reason=local_evaluation_failed'; exit 1; }
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit 'milestone=application_host_runtime;state=pass'

artifact_sha256="$(sha256sum "$fetched_artifact" | awk '{print $1}')"
artifact_path="$ARTIFACT_ROOT/application_host_runtime_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || { emit 'script_72_application_host_runtime=blocked;reason=artifact_path_exists'; exit 1; }
cp -- "$fetched_artifact" "$artifact_path"
[[ "$(sha256sum "$artifact_path" | awk '{print $1}')" == "$artifact_sha256" ]] || { emit 'script_72_application_host_runtime=blocked;reason=retained_artifact_identity_mismatch'; exit 1; }
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$(stat -c '%s' "$artifact_path")"
emit "accepted_checksum=$checksum_path"
emit 'target_changed=false;listener_stopped=true;credential_read=false;external_dependency_reachability=not_qualified'
emit "script_72_application_host_runtime=pass;local_report=$report_path;next_gate=define_application_host_external_model_transport"
