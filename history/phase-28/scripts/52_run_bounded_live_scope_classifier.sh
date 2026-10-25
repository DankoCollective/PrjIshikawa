#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Run one checksum-bound synthetic scope-classifier request against the
#   managed Gemma endpoint, validate it through the accepted application
#   boundary, and retain protected decision evidence plus a content-free report.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/52_run_bounded_live_scope_classifier.sh --run

usage() {
  sed -n '3,11p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run                      Explicitly authorize one live synthetic classification.' \
    '  --target USER@HOST         Approved SSH destination.' \
    '  --identity-file PATH       Function-specific SSH private key.' \
    '  --expected-hostname NAME   Exact target hostname.' \
    '  --report-root PATH         Absolute local content-free report directory.' \
    '  --artifact-root PATH       Absolute local protected-artifact directory.' \
    '  --validate-only            Validate local sources without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$ISHIKAWA_ROOT/application/python"
readonly TARGET_SHELL="$SCRIPT_DIR/run-scope-classifier"
readonly TARGET_PYTHON="$SCRIPT_DIR/run_scope_classifier.py"
readonly LOCAL_EVALUATOR="$SCRIPT_DIR/evaluate_live_scope_classifier.py"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly PROFILE="$ISHIKAWA_ROOT/config/templates/scope_profile.yaml"
readonly REQUEST="$REPO_ROOT/local/artifacts/ishikawa/scope-classifier/synthetic_scope_classifier_request_20261020T032432Z.json"
readonly REQUEST_SHA256='4ab77972b9765fe6a11147219f082da0085336f777ba2bd45877aadbe8d8e397'
readonly REQUEST_IDENTITY='367f87123a3c0eea177d609addd65e69806e50406d6a0f843ccb16365b2887b5'
readonly PROMPT_IDENTITY='2d84d6506f5c300c2291b5d8986b7fb8bebf4f816fcb7d44930884ec57a16676'
readonly POLICY_IDENTITY='810c88468fb039e4e132bd4b3f96d607a6459b4460b82cde57efe47e686c850e'
readonly ACCEPTED_MEASUREMENT="$REPO_ROOT/local/artifacts/ishikawa/scope-request-tokens/scope_request_token_measurement_20261020T033125Z.json"
readonly ACCEPTED_MEASUREMENT_SHA256='85e115e948cce5dd7f0ccf5193115513a1775b1257b8844e81a11f541ffda3be'
readonly ACCEPTED_MEASUREMENT_REPORT="$REPO_ROOT/local/reports/ishikawa-scope-request-tokens/scope_request_tokens_20261020T033125Z_QbJ8VI.txt"
readonly ACCEPTED_MEASUREMENT_REPORT_SHA256='24b937b9bb33f065e071f1e9d182a5db4f856bd6474dd468952099accc37ecd6'
readonly DEFAULT_REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-live-scope-classifier"
readonly DEFAULT_ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/live-scope-classifier"
readonly RUNTIME_FILES=(
  "$PYTHON_ROOT/ishikawa/__init__.py"
  "$PYTHON_ROOT/ishikawa/canonical.py"
  "$PYTHON_ROOT/ishikawa/errors.py"
  "$PYTHON_ROOT/ishikawa/reconstruction.py"
  "$PYTHON_ROOT/ishikawa/generation.py"
  "$PYTHON_ROOT/ishikawa/generation_transport.py"
  "$PYTHON_ROOT/ishikawa/scope.py"
  "$PYTHON_ROOT/ishikawa/scope_transport.py"
  "$PYTHON_ROOT/ishikawa/yaml_loader.py"
)

target=""
identity_file=""
expected_hostname=""
report_root="$DEFAULT_REPORT_ROOT"
artifact_root="$DEFAULT_ARTIFACT_ROOT"
run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --target) target="${2:-}"; shift 2 ;;
    --identity-file) identity_file="${2:-}"; shift 2 ;;
    --expected-hostname) expected_hostname="${2:-}"; shift 2 ;;
    --report-root) report_root="${2:-}"; shift 2 ;;
    --artifact-root) artifact_root="${2:-}"; shift 2 ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'ERROR: unsupported argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || { printf 'BLOCKED: choose exactly one of --run or --validate-only.\n' >&2; exit 2; }
for destination in "$report_root" "$artifact_root"; do
  [[ "$destination" == /* && ! -L "$destination" ]] || { printf 'BLOCKED: local output roots must be absolute and not symlinks.\n' >&2; exit 2; }
done
for required in awk bash basename chmod cp date grep mkdir mktemp python3 rm scp sha256sum ssh stat tee timeout tr; do
  command -v "$required" >/dev/null 2>&1 || { printf 'BLOCKED: missing local command: %s\n' "$required" >&2; exit 2; }
done
for source in "$TARGET_SHELL" "$TARGET_PYTHON" "$LOCAL_EVALUATOR" "$TEST_RUNNER" "$PROFILE" "$REQUEST" "$ACCEPTED_MEASUREMENT" "$ACCEPTED_MEASUREMENT_REPORT" "${RUNTIME_FILES[@]}"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || { printf 'BLOCKED: required Script 52 input is missing or unsafe.\n' >&2; exit 2; }
done
[[ "$(sha256sum "$REQUEST" | awk '{print $1}')" == "$REQUEST_SHA256" ]] || { printf 'BLOCKED: accepted scope request checksum mismatch.\n' >&2; exit 2; }
[[ "$(sha256sum "$ACCEPTED_MEASUREMENT" | awk '{print $1}')" == "$ACCEPTED_MEASUREMENT_SHA256" ]] || { printf 'BLOCKED: accepted scope measurement checksum mismatch.\n' >&2; exit 2; }
[[ "$(sha256sum "$ACCEPTED_MEASUREMENT_REPORT" | awk '{print $1}')" == "$ACCEPTED_MEASUREMENT_REPORT_SHA256" ]] || { printf 'BLOCKED: accepted Script 51 report checksum mismatch.\n' >&2; exit 2; }
for fact in \
  'prompt_tokens=526;scope_output_reserve=128;total_reserved_tokens=654;application_context_limit=32768;application_remaining_tokens=32114' \
  'system_role_template_compatibility=pass;exact_scope_request_budget_fit=pass' \
  'scope_request_token_evaluation=pass' \
  'script_51_scope_tokens=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_MEASUREMENT_REPORT" || { printf 'BLOCKED: required accepted Script 51 fact is absent.\n' >&2; exit 2; }
done

bash -n "$TARGET_SHELL" "$TEST_RUNNER"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$TARGET_PYTHON" "$LOCAL_EVALUATOR" "${RUNTIME_FILES[@]}"
for neutral_source in "$TARGET_SHELL" "$TARGET_PYTHON"; do
  if grep -Eiq 'phase[-_ ]?[0-9]+|(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)|Danko|org[_ -]?lab|AgentDanko|repository' "$neutral_source"; then
    printf 'BLOCKED: development or environment jargon found in a neutral target source.\n' >&2
    exit 2
  fi
done

work_root="$(mktemp -d /tmp/ishikawa-script-52.XXXXXX)"
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
  else
    emit 'cleanup_remote_temporary_files=not_required'
  fi
  if [[ "$master_started" == true ]]; then
    timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1 || close_code=$?
    emit "cleanup_ssh_master_exit_code=$close_code"
    (( close_code == 0 )) || status=1
  fi
  if [[ "$work_root" == /tmp/ishikawa-script-52.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
bash "$TEST_RUNNER" >"$test_result" 2>&1 || { cat "$test_result" >&2; printf 'script_52_live_scope=blocked;reason=test_regression\n' >&2; exit 1; }
grep -Fq 'Ran 172 tests' "$test_result" || { printf 'script_52_live_scope=blocked;reason=test_count_mismatch\n' >&2; exit 1; }
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || { printf 'script_52_live_scope=blocked;reason=test_pass_marker_absent\n' >&2; exit 1; }

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
shell_sha256="$(sha256sum "$TARGET_SHELL" | awk '{print $1}')"
runner_sha256="$(sha256sum "$TARGET_PYTHON" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$LOCAL_EVALUATOR" | awk '{print $1}')"
profile_sha256="$(sha256sum "$PROFILE" | awk '{print $1}')"
payload_manifest="$work_root/payload.sha256"
printf '%s  %s\n' "$shell_sha256" 'run-scope-classifier' "$runner_sha256" 'run_scope_classifier.py' "$REQUEST_SHA256" 'synthetic-request.json' "$profile_sha256" 'scope-profile.yaml' >"$payload_manifest"
for source in "${RUNTIME_FILES[@]}"; do printf '%s  runtime/%s\n' "$(sha256sum "$source" | awk '{print $1}')" "$(basename -- "$source")" >>"$payload_manifest"; done
payload_manifest_sha256="$(sha256sum "$payload_manifest" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_bounded_live_scope_classifier_source' \
    'target_contact=false;credential_read=false;model_call=false;service_state_change=false' \
    "script_sha256=$script_sha256;target_shell_sha256=$shell_sha256;runner_sha256=$runner_sha256;evaluator_sha256=$evaluator_sha256" \
    "payload_manifest_sha256=$payload_manifest_sha256;payload_members=13;request_sha256=$REQUEST_SHA256;profile_sha256=$profile_sha256" \
    "accepted_measurement_sha256=$ACCEPTED_MEASUREMENT_SHA256;accepted_measurement_report_sha256=$ACCEPTED_MEASUREMENT_REPORT_SHA256" \
    'local_tests=172;failures=0;errors=0' \
    'script_52_live_scope_source=pass'
  exit 0
fi

site_values_path="$REPO_ROOT/local/site_values.env"
if [[ -f "$site_values_path" && -z "$target" && -z "$identity_file" && -z "$expected_hostname" ]]; then
  selected_site_values=()
  mapfile -d '' -t selected_site_values < <(python3 -B - "$site_values_path" <<'PY'
import os,re,sys
wanted={"LOCAL_RUNTIME_USER","DANKO_00_SSH_ADDRESS","DANKO_00_RESERVED_LAN_IP","TARGET_RESERVED_LAN_IP","DANKO_00_TARGET","DANKO_00_SSH_KEY","DANKO_00_IDENTITY_FILE","DANKOSURFACE_TO_00DANKO_IDENTITY_FILE","DANKO_00_EXPECTED_HOSTNAME","TARGET_STABLE_LAN_NAME"}
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
resolved=values.get("DANKO_00_TARGET","") or (f"{user}@{address}" if address else "")
identity=values.get("DANKO_00_SSH_KEY") or values.get("DANKO_00_IDENTITY_FILE") or values.get("DANKOSURFACE_TO_00DANKO_IDENTITY_FILE","")
hostname=values.get("DANKO_00_EXPECTED_HOSTNAME") or values.get("TARGET_STABLE_LAN_NAME","")
for value in (resolved,identity,hostname):
    if "\n" in value or "\r" in value: raise SystemExit(1)
    sys.stdout.buffer.write(value.encode("utf-8")+b"\0")
PY
  )
  (( ${#selected_site_values[@]} == 3 )) || { printf 'BLOCKED: selected site-value parsing failed.\n' >&2; exit 2; }
  target="${selected_site_values[0]}"; identity_file="${selected_site_values[1]}"; expected_hostname="${selected_site_values[2]}"
fi
[[ "$target" =~ ^[A-Za-z_][A-Za-z0-9_-]*@[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || { printf 'BLOCKED: invalid or missing SSH target.\n' >&2; exit 2; }
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || { printf 'BLOCKED: invalid or missing expected hostname.\n' >&2; exit 2; }
[[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] || { printf 'BLOCKED: identity file is missing or unsafe.\n' >&2; exit 2; }

mkdir -p -- "$report_root" "$artifact_root"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_root/live_scope_classifier_${timestamp}_XXXXXX.txt")"
remote_root="/tmp/scope-classifier-$timestamp-$$"
emit 'purpose=run_one_bounded_live_synthetic_scope_classification'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;target_shell_sha256=$shell_sha256;runner_sha256=$runner_sha256;evaluator_sha256=$evaluator_sha256"
emit "request_sha256=$REQUEST_SHA256;profile_sha256=$profile_sha256;accepted_measurement_sha256=$ACCEPTED_MEASUREMENT_SHA256"
emit "payload_manifest_sha256=$payload_manifest_sha256;payload_members=13;synthetic_request=true"
emit 'authorized_actions=stage_checksum_bound_synthetic_scope_request_preserve_managed_service_state_prompt_operator_for_gemma_credential_call_loopback_generation_once_fetch_protected_validated_decision_remove_target_temporary_files'
emit 'non_actions=no_package_or_configuration_change_no_database_contact_no_organizational_content_no_stored_credential_read_no_credential_transfer_or_retention_no_raw_text_logging_no_retrieval_no_publication'
emit "selected_target=$target;expected_hostname=$expected_hostname;identity_label=$(basename -- "$identity_file")"
emit 'operator_expectation=ssh_key_passphrase_up_to_once;target_sudo_password_up_to_once;gemma_api_key_prompt=exactly_once'
emit 'local_tests=172;failures=0;errors=0'

control_path="$work_root/ssh-control"
ssh_args=(-i "$identity_file" -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 -o ServerAliveInterval=30 -o ServerAliveCountMax=20 -o ControlMaster=auto -o "ControlPath=$control_path" -o ControlPersist=3600)
emit 'milestone=authentication;state=waiting_for_operator_if_prompted'
timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$target" >/dev/null 2>&1 || { emit 'script_52_live_scope=blocked;reason=ssh_master_start_failed'; exit 1; }
master_started=true
emit 'milestone=authentication;state=pass'
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" hostname >"$work_root/hostname.txt" 2>/dev/null || { emit 'script_52_live_scope=blocked;reason=hostname_probe_failed'; exit 1; }
[[ "$(tr -d '\r\n' <"$work_root/hostname.txt")" == "$expected_hostname" ]] || { emit 'script_52_live_scope=blocked;reason=target_hostname_mismatch'; exit 1; }
emit "target_hostname=$expected_hostname"
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "test ! -e '$remote_root' && mkdir -m 0700 -p -- '$remote_root/runtime'" >/dev/null || { emit 'script_52_live_scope=blocked;reason=remote_temporary_directory_not_created'; exit 1; }
remote_created=true
timeout --foreground 180 scp "${ssh_args[@]}" "$TARGET_SHELL" "$TARGET_PYTHON" "$REQUEST" "$PROFILE" "$payload_manifest" "$target:$remote_root/" >/dev/null || { emit 'script_52_live_scope=blocked;reason=target_payload_copy_failed'; exit 1; }
timeout --foreground 180 scp "${ssh_args[@]}" "${RUNTIME_FILES[@]}" "$target:$remote_root/runtime/" >/dev/null || { emit 'script_52_live_scope=blocked;reason=target_runtime_copy_failed'; exit 1; }
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "cd '$remote_root' && mv '$(basename -- "$REQUEST")' synthetic-request.json && mv '$(basename -- "$PROFILE")' scope-profile.yaml && sha256sum --check --strict payload.sha256" >/dev/null || { emit 'script_52_live_scope=blocked;reason=target_payload_hash_mismatch'; exit 1; }
emit 'milestone=target_payload_verification;state=pass'

emit 'milestone=bounded_live_scope_classification;state=waiting_for_operator_credentials'
set +e
timeout --foreground 1800 ssh -tt "${ssh_args[@]}" "$target" \
  "cd '$remote_root' && umask 077 && sudo -p '[sudo] password for bounded scope classification: ' bash ./run-scope-classifier --input '$remote_root/synthetic-request.json' --expected-input-sha256 '$REQUEST_SHA256' --expected-request-identity '$REQUEST_IDENTITY' --expected-prompt-identity '$PROMPT_IDENTITY' --expected-policy-identity '$POLICY_IDENTITY' --profile '$remote_root/scope-profile.yaml' --expected-profile-sha256 '$profile_sha256' --output '$remote_root/validated-scope-result.json' --rejected-output '$remote_root/rejected-scope-response.bin' > '$remote_root/qualification-result.txt' 2>&1" < /dev/tty
remote_code=$?
set -e
emit "remote_execution_exit_code=$remote_code;raw_output_retained=false"
fetched_result="$work_root/qualification-result.txt"
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/qualification-result.txt" "$fetched_result" >/dev/null || { emit 'script_52_live_scope=blocked;reason=result_fetch_failed'; exit 1; }
tr -d '\r' <"$fetched_result" >"$work_root/qualification-result.normalized"
fetched_result="$work_root/qualification-result.normalized"
output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] || ! [[ "$line" =~ ^\[scope-classifier\]\ [A-Za-z0-9_.:/=@+,-]+(\ [A-Za-z0-9_.:/=@+,-]+)*$ ]]; then output_contract=blocked; continue; fi
  emit "$line"
done <"$fetched_result"
emit "remote_output_contract=$output_contract"
pass_markers="$(grep -Fxc '[scope-classifier] result=PASS next=local_scope_result_evaluation' "$fetched_result" || true)"
blocked_markers="$(grep -Fc '[scope-classifier] result=BLOCKED ' "$fetched_result" || true)"
credential_markers="$(grep -Fxc '[scope-classifier] credential_source=operator_attended_tty stored_credential_read=false' "$fetched_result" || true)"
cleanup_markers="$(grep -Ec '^\[scope-classifier\] cleanup=(pass|not_required) ' "$fetched_result" || true)"
emit "pass_markers=$pass_markers;blocked_markers=$blocked_markers;credential_markers=$credential_markers;cleanup_markers=$cleanup_markers"
if (( remote_code != 0 )) || [[ "$output_contract" != pass || "$pass_markers" != 1 || "$blocked_markers" != 0 || "$credential_markers" != 1 || "$cleanup_markers" != 1 ]]; then
  rejected_root="$artifact_root/rejected"
  rejected_path="$rejected_root/rejected_scope_response_${timestamp}.bin"
  if timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "test -f '$remote_root/rejected-scope-response.bin'" >/dev/null 2>&1; then
    mkdir -p -- "$rejected_root"
    if timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/rejected-scope-response.bin" "$rejected_path" >/dev/null 2>&1; then
      chmod 0600 "$rejected_path" 2>/dev/null || true
      emit "protected_rejected_response=$rejected_path;protected_rejected_response_sha256=$(sha256sum "$rejected_path" | awk '{print $1}')"
    else emit 'protected_rejected_response=fetch_failed'; fi
  else emit 'protected_rejected_response=not_created'; fi
  emit 'milestone=bounded_live_scope_classification;state=blocked'
  emit "script_52_live_scope=blocked;local_report=$report_path;next_gate=review_content_free_result_before_any_retry"
  exit 1
fi

fetched_artifact="$work_root/validated-scope-result.json"
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/validated-scope-result.json" "$fetched_artifact" >/dev/null || { emit 'script_52_live_scope=blocked;reason=validated_artifact_fetch_failed'; exit 1; }
chmod 0600 "$fetched_artifact" 2>/dev/null || true
evaluation_result="$work_root/evaluation.txt"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$LOCAL_EVALUATOR" \
  --artifact "$fetched_artifact" \
  --measurement "$ACCEPTED_MEASUREMENT" \
  --expected-measurement-sha256 "$ACCEPTED_MEASUREMENT_SHA256" \
  --expected-source-sha256 "$REQUEST_SHA256" \
  --expected-request-identity "$REQUEST_IDENTITY" \
  --expected-prompt-identity "$PROMPT_IDENTITY" \
  --expected-policy-identity "$POLICY_IDENTITY" >"$evaluation_result"
grep -Fxq 'live_scope_classifier_evaluation=pass' "$evaluation_result" || { emit 'script_52_live_scope=blocked;reason=local_evaluation_failed'; exit 1; }
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit 'milestone=bounded_live_scope_classification;state=pass'

artifact_sha256="$(sha256sum "$fetched_artifact" | awk '{print $1}')"
artifact_path="$artifact_root/live_scope_classifier_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || { emit 'script_52_live_scope=blocked;reason=local_artifact_path_exists'; exit 1; }
cp -- "$fetched_artifact" "$artifact_path"
[[ "$(sha256sum "$artifact_path" | awk '{print $1}')" == "$artifact_sha256" ]] || { emit 'script_52_live_scope=blocked;reason=retained_artifact_identity_mismatch'; exit 1; }
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$(stat -c '%s' "$artifact_path")"
emit "accepted_checksum=$checksum_path"
emit 'configuration_changed=false;database_changed=false;credential_retained=false;model_call=true;service_initial_state_restored=true'
emit "script_52_live_scope=pass;local_report=$report_path;next_gate=implement_separate_prompt_injection_gate"
