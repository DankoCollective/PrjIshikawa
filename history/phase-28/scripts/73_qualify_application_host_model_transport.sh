#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify one temporary SSH connection from the application host carrying
#   the two loopback-only model-service forwards.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/73_qualify_application_host_model_transport.sh --run

usage() {
  sed -n '3,10p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run                         Authorize bounded target qualification.' \
    '  --application-target VALUE    Application-host SSH destination or alias.' \
    '  --application-identity PATH   Optional application-host SSH key.' \
    '  --model-target USER@HOST      Model-host SSH destination.' \
    '  --model-identity PATH         Local key loaded into an ephemeral forwarded agent.' \
    '  --expected-hostname NAME      Exact application-host short hostname.' \
    '  --expected-os-version VER     Exact expected Ubuntu major.minor version.' \
    '  --validate-only               Validate sources without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly TARGET_HELPER="$SCRIPT_DIR/qualify-model-transport"
readonly TARGET_RUNNER="$SCRIPT_DIR/qualify_model_transport.py"
readonly LOCAL_EVALUATOR="$SCRIPT_DIR/evaluate_model_transport.py"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly RUNTIME_CONFIG="$ISHIKAWA_ROOT/config/templates/runtime_dependencies.yaml"
readonly ACCEPTED_SCRIPT_72_REPORT="$REPO_ROOT/local/reports/ishikawa-application-host-runtime/application_host_runtime_20261020T145923Z_ejaJMJ.txt"
readonly ACCEPTED_SCRIPT_72_REPORT_SHA256='d3c6cd0b81a93a576ddc8ec8974fc6d02d2d31affc35574a59040e59b347a477'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-model-transport"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/model-transport"

application_target="${APPLICATION_HOST_TARGET:-DankoSurface_EmceeDanko}"
application_identity="${APPLICATION_HOST_IDENTITY_FILE:-}"
model_target="${MODEL_HOST_TARGET:-}"
model_identity="${MODEL_HOST_IDENTITY_FILE:-}"
expected_hostname="${APPLICATION_HOST_EXPECTED_HOSTNAME:-EmceeDanko}"
expected_os_version="${APPLICATION_HOST_EXPECTED_OS_VERSION:-24.04}"
run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --application-target) application_target="${2:-}"; shift 2 ;;
    --application-identity) application_identity="${2:-}"; shift 2 ;;
    --model-target) model_target="${2:-}"; shift 2 ;;
    --model-identity) model_identity="${2:-}"; shift 2 ;;
    --expected-hostname) expected_hostname="${2:-}"; shift 2 ;;
    --expected-os-version) expected_os_version="${2:-}"; shift 2 ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'ERROR: unsupported argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || { printf 'BLOCKED: choose exactly one of --run or --validate-only.\n' >&2; exit 2; }
[[ "$application_target" =~ ^[A-Za-z0-9_@.:-]+$ ]] || { printf 'BLOCKED: invalid application-host SSH target or alias.\n' >&2; exit 2; }
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || { printf 'BLOCKED: invalid expected hostname.\n' >&2; exit 2; }
[[ "$expected_os_version" =~ ^[0-9]{2}\.[0-9]{2}$ ]] || { printf 'BLOCKED: invalid expected Ubuntu version.\n' >&2; exit 2; }
if [[ -n "$application_identity" ]]; then
  [[ "$application_identity" == /* && -f "$application_identity" && ! -L "$application_identity" && -r "$application_identity" ]] || { printf 'BLOCKED: application-host identity is unsafe.\n' >&2; exit 2; }
fi
for required in awk bash chmod cp date grep mkdir mktemp python3 rm scp sed sha256sum ssh ssh-add ssh-agent ssh-keygen stat tee timeout tr wc; do
  command -v "$required" >/dev/null 2>&1 || { printf 'BLOCKED: missing local command: %s\n' "$required" >&2; exit 2; }
done
for source in "$TARGET_HELPER" "$TARGET_RUNNER" "$LOCAL_EVALUATOR" "$TEST_RUNNER" "$RUNTIME_CONFIG" "$ACCEPTED_SCRIPT_72_REPORT"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || { printf 'BLOCKED: a required Script 73 input is missing or unsafe.\n' >&2; exit 2; }
done
[[ "$(sha256sum "$ACCEPTED_SCRIPT_72_REPORT" | awk '{print $1}')" == "$ACCEPTED_SCRIPT_72_REPORT_SHA256" ]] || { printf 'BLOCKED: accepted Script 72 report identity changed.\n' >&2; exit 2; }
for fact in \
  'application_host_runtime_evaluation=pass' \
  'external_dependency_reachability=not_qualified' \
  'target_changed=false;listener_stopped=true;credential_read=false;external_dependency_reachability=not_qualified' \
  'script_72_application_host_runtime=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_SCRIPT_72_REPORT" || { printf 'BLOCKED: an accepted Script 72 fact is absent.\n' >&2; exit 2; }
done
for fact in \
  '  chat_endpoint_url: http://127.0.0.1:8000/v1/chat/completions' \
  '  tokenization_endpoint_url: http://127.0.0.1:8000/tokenize' \
  '  embedding_endpoint_url: http://127.0.0.1:8001/v1/embeddings'; do
  grep -Fxq "$fact" "$RUNTIME_CONFIG" || { printf 'BLOCKED: frozen loopback endpoint configuration changed.\n' >&2; exit 2; }
done

bash -n "$TARGET_HELPER" "$TEST_RUNNER"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' "$TARGET_RUNNER" "$LOCAL_EVALUATOR"
for neutral_source in "$TARGET_HELPER" "$TARGET_RUNNER"; do
  if grep -Eq '(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)' "$neutral_source" || grep -Eiq 'phase[-_ ]?[0-9]+|Danko|org[_ -]?lab|repository|Dalton' "$neutral_source"; then
    printf 'BLOCKED: development or environment jargon found in a neutral target source.\n' >&2
    exit 2
  fi
done

work_root="$(mktemp -d /tmp/ishikawa-script-73.XXXXXX)"
report_path=""
remote_root=""
remote_created=false
master_started=false
agent_started=false
ssh_args=()
emit() { if [[ -n "$report_path" ]]; then printf '%s\n' "$1" | tee -a "$report_path"; else printf '%s\n' "$1"; fi; }
cleanup() {
  local status="$?" cleanup_code=0 close_code=0
  trap - EXIT INT TERM
  set +e
  if [[ "$remote_created" == true && "$master_started" == true ]]; then
    timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$application_target" "rm -rf -- '$remote_root'" >/dev/null 2>&1 || cleanup_code=$?
    if (( cleanup_code == 0 )); then emit 'cleanup_remote_temporary_files=removed'; else emit "cleanup_remote_temporary_files=review_required;exit_code=$cleanup_code"; status=1; fi
  else emit 'cleanup_remote_temporary_files=not_required'; fi
  if [[ "$master_started" == true ]]; then
    timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$application_target" >/dev/null 2>&1 || close_code=$?
    emit "cleanup_ssh_master_exit_code=$close_code"
    (( close_code == 0 )) || status=1
  fi
  if [[ "$agent_started" == true ]]; then
    ssh-agent -k >/dev/null 2>&1 || status=1
    emit 'cleanup_ephemeral_ssh_agent=removed'
  fi
  if [[ "$work_root" == /tmp/ishikawa-script-73.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

evaluator_self_test="$work_root/evaluator-self-test.txt"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$LOCAL_EVALUATOR" --self-test >"$evaluator_self_test"
grep -Fxq 'model_transport_evaluator_self_test=pass' "$evaluator_self_test" || { printf 'script_73_model_transport=blocked;reason=evaluator_self_test_failed\n' >&2; exit 1; }
test_result="$work_root/tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || { printf 'script_73_model_transport=blocked;reason=test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s\n' "$(sha256sum "$test_result" | awk '{print $1}')" "$(stat -c '%s' "$test_result")" >&2; exit 1; }
grep -Fq 'Ran 270 tests' "$test_result" || { printf 'script_73_model_transport=blocked;reason=test_count_mismatch\n' >&2; exit 1; }
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || { printf 'script_73_model_transport=blocked;reason=test_pass_marker_absent\n' >&2; exit 1; }

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
helper_sha256="$(sha256sum "$TARGET_HELPER" | awk '{print $1}')"
runner_sha256="$(sha256sum "$TARGET_RUNNER" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$LOCAL_EVALUATOR" | awk '{print $1}')"
runtime_config_sha256="$(sha256sum "$RUNTIME_CONFIG" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_application_host_model_transport_source' \
    'target_contact=false;ssh_agent_started=false;tunnel_started=false;model_health_call=false;credential_read=false' \
    "script_sha256=$script_sha256;helper_sha256=$helper_sha256;runner_sha256=$runner_sha256;evaluator_sha256=$evaluator_sha256" \
    "runtime_config_sha256=$runtime_config_sha256;accepted_script_72_report_sha256=$ACCEPTED_SCRIPT_72_REPORT_SHA256" \
    'local_tests=270;failures=0;errors=0' \
    'script_73_model_transport_source=pass'
  exit 0
fi

site_values_path="$REPO_ROOT/local/site_values.env"
if [[ -f "$site_values_path" && ( -z "$model_target" || -z "$model_identity" ) ]]; then
  selected_site_values=()
  mapfile -d '' -t selected_site_values < <(python3 -B - "$site_values_path" <<'PY'
import os,re,sys
wanted={"LOCAL_RUNTIME_USER","DANKO_00_SSH_ADDRESS","DANKO_00_RESERVED_LAN_IP","TARGET_RESERVED_LAN_IP","DANKO_00_TARGET","DANKO_00_SSH_KEY","DANKO_00_IDENTITY_FILE","DANKOSURFACE_TO_00DANKO_IDENTITY_FILE"}
values={}; assignment=re.compile(r"^([A-Z][A-Z0-9_]*)=(.*)$")
with open(sys.argv[1],"r",encoding="utf-8") as stream:
    for raw in stream:
        match=assignment.fullmatch(raw.rstrip("\n"))
        if not match or match.group(1) not in wanted: continue
        key,value=match.groups()
        if key in values or "\x00" in value or "\r" in value: raise SystemExit(1)
        if len(value)>=2 and value[0]==value[-1] and value[0] in "\"'": value=value[1:-1]
        if value.startswith("${HOME}/"): value=os.path.join(os.environ["HOME"],value[len("${HOME}/"):])
        elif value.startswith("$HOME/"): value=os.path.join(os.environ["HOME"],value[len("$HOME/"):])
        values[key]=value
user=values.get("LOCAL_RUNTIME_USER","danko")
address=values.get("DANKO_00_SSH_ADDRESS") or values.get("DANKO_00_RESERVED_LAN_IP") or values.get("TARGET_RESERVED_LAN_IP","")
target=values.get("DANKO_00_TARGET","") or (f"{user}@{address}" if address else "")
identity=values.get("DANKO_00_SSH_KEY") or values.get("DANKO_00_IDENTITY_FILE") or values.get("DANKOSURFACE_TO_00DANKO_IDENTITY_FILE","")
for value in (target,identity):
    if "\n" in value or "\r" in value: raise SystemExit(1)
    sys.stdout.buffer.write(value.encode("utf-8")+b"\0")
PY
  )
  (( ${#selected_site_values[@]} == 2 )) || { printf 'BLOCKED: selected site-value parsing failed.\n' >&2; exit 2; }
  [[ -n "$model_target" ]] || model_target="${selected_site_values[0]}"
  [[ -n "$model_identity" ]] || model_identity="${selected_site_values[1]}"
fi
[[ "$model_target" =~ ^[a-z_][a-z0-9_-]{0,31}@[A-Za-z0-9][A-Za-z0-9.-]{0,252}$ ]] || { printf 'BLOCKED: invalid or missing model-host SSH target.\n' >&2; exit 2; }
[[ "$model_identity" == /* && -f "$model_identity" && ! -L "$model_identity" && -r "$model_identity" ]] || { printf 'BLOCKED: model-host identity is missing or unsafe.\n' >&2; exit 2; }
model_host="${model_target##*@}"
known_hosts_source="${ISHIKAWA_KNOWN_HOSTS_FILE:-${HOME}/.ssh/known_hosts}"
[[ "$known_hosts_source" == /* && -f "$known_hosts_source" && ! -L "$known_hosts_source" && -r "$known_hosts_source" ]] || { printf 'BLOCKED: local known-hosts file is missing or unsafe.\n' >&2; exit 2; }
known_hosts_stage="$work_root/known_hosts"
ssh-keygen -F "$model_host" -f "$known_hosts_source" 2>/dev/null | awk '!/^#/ && NF' >"$known_hosts_stage"
[[ -s "$known_hosts_stage" ]] || { printf 'BLOCKED: no previously trusted model-host key was found.\n' >&2; exit 2; }
chmod 0600 "$known_hosts_stage"

payload_manifest="$work_root/payload.sha256"
printf '%s  %s\n%s  %s\n' \
  "$runner_sha256" qualify_model_transport.py \
  "$(sha256sum "$known_hosts_stage" | awk '{print $1}')" known_hosts >"$payload_manifest"
manifest_sha256="$(sha256sum "$payload_manifest" | awk '{print $1}')"
manifest_entries=2

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/model_transport_${timestamp}_XXXXXX.txt")"
remote_root="/tmp/application-model-transport-$timestamp-$$"
emit 'purpose=qualify_application_host_model_transport'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;helper_sha256=$helper_sha256;runner_sha256=$runner_sha256;evaluator_sha256=$evaluator_sha256"
emit "payload_manifest_sha256=$manifest_sha256;payload_file_count=$manifest_entries;runtime_config_sha256=$runtime_config_sha256"
emit "accepted_script_72_report_sha256=$ACCEPTED_SCRIPT_72_REPORT_SHA256"
emit 'authorized_actions=start_isolated_local_ssh_agent_load_operator_selected_model_identity_forward_agent_to_application_host_stage_checksum_bound_public_material_start_one_temporary_two_port_tunnel_check_health_stop_tunnel_fetch_content_free_measurement_remove_temporary_state'
emit 'non_actions=no_private_key_transfer_or_retention_no_sudo_no_package_service_firewall_or_configuration_change_no_api_credential_read_no_inference_embedding_or_tokenization_call_no_organizational_content'
emit "selected_application_target=$application_target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version;selected_model_host=$model_host;model_identity_label=$(basename -- "$model_identity")"
emit 'operator_expectation=application_host_key_passphrase_up_to_once;model_host_key_passphrase_up_to_once;sudo_prompt=none;api_key_prompt=none'
emit 'local_tests=270;failures=0;errors=0'

agent_output="$(ssh-agent -s)"
SSH_AUTH_SOCK="$(printf '%s\n' "$agent_output" | sed -n 's/^SSH_AUTH_SOCK=\([^;]*\);.*/\1/p')"
SSH_AGENT_PID="$(printf '%s\n' "$agent_output" | sed -n 's/^SSH_AGENT_PID=\([0-9][0-9]*\);.*/\1/p')"
[[ -n "$SSH_AUTH_SOCK" && -S "$SSH_AUTH_SOCK" && "$SSH_AGENT_PID" =~ ^[0-9]+$ ]] || { emit 'script_73_model_transport=blocked;reason=ephemeral_agent_start_failed'; exit 1; }
export SSH_AUTH_SOCK SSH_AGENT_PID
agent_started=true

control_path="$work_root/ssh-control"
ssh_args=(-A -o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto -o "ControlPath=$control_path" -o ControlPersist=1800)
if [[ -n "$application_identity" ]]; then ssh_args+=(-i "$application_identity" -o IdentitiesOnly=yes); fi
emit 'milestone=application_host_authentication;state=waiting_for_operator_if_prompted'
timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$application_target" >/dev/null 2>&1 || { emit 'script_73_model_transport=blocked;reason=application_host_ssh_master_start_failed'; exit 1; }
master_started=true
emit 'milestone=application_host_authentication;state=pass'

emit 'milestone=model_identity_unlock;state=waiting_for_operator_if_prompted'
ssh-add -q "$model_identity" || { emit 'script_73_model_transport=blocked;reason=model_identity_load_failed'; exit 1; }
emit 'milestone=model_identity_unlock;state=pass'

timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$application_target" "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" >/dev/null || { emit 'script_73_model_transport=blocked;reason=remote_temporary_directory_not_created'; exit 1; }
remote_created=true
timeout --foreground 180 scp "${ssh_args[@]}" "$TARGET_HELPER" "$TARGET_RUNNER" "$payload_manifest" "$known_hosts_stage" "$application_target:$remote_root/" >/dev/null || { emit 'script_73_model_transport=blocked;reason=target_payload_copy_failed'; exit 1; }
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$application_target" "cd '$remote_root' && printf '%s  %s\n%s  %s\n' '$helper_sha256' qualify-model-transport '$manifest_sha256' payload.sha256 | sha256sum --check --strict -" >/dev/null || { emit 'script_73_model_transport=blocked;reason=target_payload_hash_mismatch'; exit 1; }
emit 'milestone=target_payload_verification;state=pass'

emit 'milestone=model_transport;state=start'
set +e
timeout --foreground 180 ssh "${ssh_args[@]}" -o BatchMode=yes "$application_target" "cd '$remote_root' && bash ./qualify-model-transport '$expected_hostname' '$expected_os_version' '$remote_root' '$manifest_sha256' '$manifest_entries' '$model_target' '$model_host' > qualification-result.txt" </dev/null
remote_code=$?
set -e
emit "remote_execution_exit_code=$remote_code;raw_stderr_retained=false"
fetched_result="$work_root/qualification-result.txt"
timeout --foreground 120 scp "${ssh_args[@]}" "$application_target:$remote_root/qualification-result.txt" "$fetched_result" >/dev/null || { emit 'script_73_model_transport=blocked;reason=result_fetch_failed'; exit 1; }
output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then output_contract=blocked; continue; fi
  emit "$line"
done <"$fetched_result"
emit "remote_output_contract=$output_contract"
pass_markers="$(grep -Fxc 'model_transport_qualification=pass' "$fetched_result" || true)"
blocked_markers="$(grep -Ec '^(model_transport|application_host_model_transport)=blocked;' "$fetched_result" || true)"
if (( remote_code != 0 )) || [[ "$output_contract" != pass || "$pass_markers" != 1 || "$blocked_markers" != 0 ]]; then
  emit 'milestone=model_transport;state=blocked'
  emit "script_73_model_transport=blocked;local_report=$report_path;next_gate=review_content_free_result_before_any_retry"
  exit 1
fi

fetched_artifact="$work_root/model-transport.json"
timeout --foreground 120 scp "${ssh_args[@]}" "$application_target:$remote_root/model-transport.json" "$fetched_artifact" >/dev/null || { emit 'script_73_model_transport=blocked;reason=artifact_fetch_failed'; exit 1; }
evaluation_result="$work_root/evaluation.txt"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$LOCAL_EVALUATOR" --artifact "$fetched_artifact" >"$evaluation_result"
grep -Fxq 'model_transport_evaluation=pass' "$evaluation_result" || { emit 'script_73_model_transport=blocked;reason=local_evaluation_failed'; exit 1; }
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit 'milestone=model_transport;state=pass'

artifact_sha256="$(sha256sum "$fetched_artifact" | awk '{print $1}')"
artifact_path="$ARTIFACT_ROOT/model_transport_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || { emit 'script_73_model_transport=blocked;reason=artifact_path_exists'; exit 1; }
cp -- "$fetched_artifact" "$artifact_path"
[[ "$(sha256sum "$artifact_path" | awk '{print $1}')" == "$artifact_sha256" ]] || { emit 'script_73_model_transport=blocked;reason=retained_artifact_identity_mismatch'; exit 1; }
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$(stat -c '%s' "$artifact_path")"
emit "accepted_checksum=$checksum_path"
emit 'target_changed=false;tunnel_stopped=true;private_key_transferred=false;api_credentials_read=false;model_calls=0'
emit "script_73_model_transport=pass;local_report=$report_path;next_gate=qualify_configured_live_dependency_adapters_from_application_host"
