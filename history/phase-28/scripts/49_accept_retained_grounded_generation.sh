#!/usr/bin/env bash
set -Eeuo pipefail

# Revalidate one retained synthetic response under the corrected compatibility
# contract, then remove only its checksum-bound stale target directory.

usage() {
  cat <<'EOF'
Usage:
  49_accept_retained_grounded_generation.sh --validate-only
  49_accept_retained_grounded_generation.sh --run [--target USER@HOST] [--identity-file PATH] [--expected-hostname NAME]

--validate-only performs local source, test, and retained-response validation.
--run additionally writes protected acceptance evidence and performs the
guarded cleanup of the prior target-side temporary directory. It does not call
the model, read a model credential, or change service state.
EOF
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$ISHIKAWA_ROOT/application/python"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly REVALIDATOR="$SCRIPT_DIR/revalidate_retained_grounded_generation.py"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_live_grounded_generation.py"
readonly CLEANUP_HELPER="$SCRIPT_DIR/cleanup-grounded-generation-trial"
readonly REQUEST="$REPO_ROOT/local/artifacts/ishikawa/generation-request-builder/synthetic_grounded_generation_request_20261020T022552Z.json"
readonly REQUEST_SHA256='e381347fe151f1c04ed84021a4c5ae6b8198adfcc0e7b425cb7ad33f037ea7a4'
readonly REQUEST_IDENTITY='3527af8f300958b8331dec52769efdc80f14b047a99ba0056eabf3fb0813c354'
readonly PROMPT_IDENTITY='21f92ad48cecc9112e993d7a93d78065ab0066f9dd718707ad37b6f61854cd93'
readonly RETAINED_RESPONSE="$REPO_ROOT/local/artifacts/ishikawa/live-grounded-generation/rejected/rejected_generation_response_20261020T024948Z.bin"
readonly RETAINED_RESPONSE_SHA256='798ab49f4e8d50da90ebd1084561484232511df077ad3a80195f84bf65a0a871'
readonly SOURCE_REPORT="$REPO_ROOT/local/reports/ishikawa-live-grounded-generation/live_grounded_generation_20261020T024948Z_8VXqIO.txt"
readonly SOURCE_REPORT_SHA256='942fe22179054b54d549af67d91abd6e1c36ad2e89a594916ac5dcb0aa43ed71'
readonly SOURCE_STARTED_UTC='20261020T024948Z'
readonly SOURCE_PAYLOAD_SHA256='2c76729a1d3bc6e0c9b604594ad60919ef46ec650ba48a57fc7c29c5a97ae514'
readonly DEFAULT_REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-live-grounded-generation"
readonly DEFAULT_ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/live-grounded-generation/accepted"

target=''
identity_file=''
expected_hostname=''
report_root="$DEFAULT_REPORT_ROOT"
artifact_root="$DEFAULT_ARTIFACT_ROOT"
run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --target) target="${2:-}"; shift 2 ;;
    --identity-file) identity_file="${2:-}"; shift 2 ;;
    --expected-hostname) expected_hostname="${2:-}"; shift 2 ;;
    --report-root) report_root="${2:-}"; shift 2 ;;
    --artifact-root) artifact_root="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'BLOCKED: unsupported argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'BLOCKED: choose exactly one of --run or --validate-only.\n' >&2
  exit 2
}
for destination in "$report_root" "$artifact_root"; do
  [[ "$destination" == /* && ! -L "$destination" ]] || {
    printf 'BLOCKED: local output roots must be absolute and not symlinks.\n' >&2
    exit 2
  }
done
for command in awk bash basename chmod cp date grep mkdir mktemp python3 rm scp sha256sum ssh stat tee timeout tr; do
  command -v "$command" >/dev/null 2>&1 || {
    printf 'BLOCKED: missing local command: %s\n' "$command" >&2
    exit 2
  }
done
for source in "$TEST_RUNNER" "$REVALIDATOR" "$EVALUATOR" "$CLEANUP_HELPER" "$REQUEST" "$RETAINED_RESPONSE" "$SOURCE_REPORT"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: required Script 49 input is missing or unsafe.\n' >&2
    exit 2
  }
done
[[ "$(sha256sum "$REQUEST" | awk '{print $1}')" == "$REQUEST_SHA256" ]] || { printf 'BLOCKED: request checksum mismatch.\n' >&2; exit 2; }
[[ "$(sha256sum "$RETAINED_RESPONSE" | awk '{print $1}')" == "$RETAINED_RESPONSE_SHA256" ]] || { printf 'BLOCKED: retained response checksum mismatch.\n' >&2; exit 2; }
[[ "$(sha256sum "$SOURCE_REPORT" | awk '{print $1}')" == "$SOURCE_REPORT_SHA256" ]] || { printf 'BLOCKED: source report checksum mismatch.\n' >&2; exit 2; }
for fact in \
  "started_utc=$SOURCE_STARTED_UTC" \
  'remote_execution_exit_code=1;raw_output_retained=false' \
  '[grounded-generation] result=BLOCKED reason=UPSTREAM_SCHEMA_INVALID' \
  "protected_rejected_response_sha256=$RETAINED_RESPONSE_SHA256" \
  'cleanup_remote_temporary_files=review_required;exit_code=1'; do
  grep -Fq "$fact" "$SOURCE_REPORT" || { printf 'BLOCKED: required source-report fact is absent.\n' >&2; exit 2; }
done

bash -n "$CLEANUP_HELPER" "$TEST_RUNNER"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' "$REVALIDATOR" "$EVALUATOR"
if grep -Eiq 'phase[-_ ]?[0-9]+|(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)|Danko|org[_ -]?lab|AgentDanko|repository' "$CLEANUP_HELPER"; then
  printf 'BLOCKED: development or environment jargon found in neutral cleanup source.\n' >&2
  exit 2
fi

work_root="$(mktemp -d /tmp/ishikawa-script-49.XXXXXX)"
report_path=''
remote_stage=''
remote_stage_created=false
master_started=false
ssh_args=()
emit() {
  if [[ -n "$report_path" ]]; then printf '%s\n' "$1" | tee -a "$report_path"; else printf '%s\n' "$1"; fi
}
cleanup() {
  local status="$?" cleanup_code=0 close_code=0
  trap - EXIT INT TERM
  set +e
  if [[ "$remote_stage_created" == true && "$master_started" == true ]]; then
    timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "rm -rf -- '$remote_stage'" >/dev/null 2>&1 || cleanup_code=$?
    if (( cleanup_code == 0 )); then emit 'cleanup_remote_staging=removed'; else emit "cleanup_remote_staging=review_required;exit_code=$cleanup_code"; status=1; fi
  else
    emit 'cleanup_remote_staging=not_required'
  fi
  if [[ "$master_started" == true ]]; then
    timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1 || close_code=$?
    emit "cleanup_ssh_master_exit_code=$close_code"
    (( close_code == 0 )) || status=1
  fi
  if [[ "$work_root" == /tmp/ishikawa-script-49.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  cat "$test_result" >&2
  printf 'script_49_retained_generation=blocked;reason=test_regression\n' >&2
  exit 1
}
grep -Fq 'Ran 155 tests' "$test_result" || { printf 'script_49_retained_generation=blocked;reason=test_count_mismatch\n' >&2; exit 1; }
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || { printf 'script_49_retained_generation=blocked;reason=test_pass_marker_absent\n' >&2; exit 1; }

candidate_artifact="$work_root/validated-grounded-answer.json"
revalidation_result="$work_root/revalidation.txt"
PYTHONPATH="$PYTHON_ROOT" PYTHONDONTWRITEBYTECODE=1 python3 -B "$REVALIDATOR" \
  --request "$REQUEST" \
  --expected-request-sha256 "$REQUEST_SHA256" \
  --expected-request-identity "$REQUEST_IDENTITY" \
  --expected-prompt-identity "$PROMPT_IDENTITY" \
  --response "$RETAINED_RESPONSE" \
  --expected-response-sha256 "$RETAINED_RESPONSE_SHA256" \
  --output "$candidate_artifact" >"$revalidation_result"
grep -Fxq 'retained_generation_revalidation=pass;model_call=false;credential_read=false' "$revalidation_result" || {
  printf 'script_49_retained_generation=blocked;reason=revalidation_pass_marker_absent\n' >&2
  exit 1
}
evaluation_result="$work_root/evaluation.txt"
python3 -B "$EVALUATOR" \
  --artifact "$candidate_artifact" \
  --expected-source-sha256 "$REQUEST_SHA256" \
  --expected-request-identity "$REQUEST_IDENTITY" \
  --expected-prompt-identity "$PROMPT_IDENTITY" >"$evaluation_result"
grep -Fxq 'live_grounded_generation_evaluation=pass' "$evaluation_result" || {
  printf 'script_49_retained_generation=blocked;reason=evaluation_pass_marker_absent\n' >&2
  exit 1
}

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
revalidator_sha256="$(sha256sum "$REVALIDATOR" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
transport_sha256="$(sha256sum "$PYTHON_ROOT/ishikawa/generation_transport.py" | awk '{print $1}')"
cleanup_sha256="$(sha256sum "$CLEANUP_HELPER" | awk '{print $1}')"
candidate_sha256="$(sha256sum "$candidate_artifact" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_retained_grounded_generation_compatibility_correction' \
    'target_contact=false;model_call=false;credential_read=false;service_state_change=false' \
    "script_sha256=$script_sha256;revalidator_sha256=$revalidator_sha256;evaluator_sha256=$evaluator_sha256" \
    "runtime_transport_sha256=$transport_sha256;cleanup_helper_sha256=$cleanup_sha256" \
    "source_report_sha256=$SOURCE_REPORT_SHA256;retained_response_sha256=$RETAINED_RESPONSE_SHA256" \
    'local_tests=155;failures=0;errors=0' \
    'nullable_compatibility_fields=5;all_empty=pass;isolated_json_fence=pass;surrounding_prose=false' \
    'offline_prompt_tokens=884;live_prompt_tokens=885;prompt_token_delta=1' \
    "candidate_artifact_sha256=$candidate_sha256" \
    'script_49_retained_generation_source=pass'
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
  target="${selected_site_values[0]}"
  identity_file="${selected_site_values[1]}"
  expected_hostname="${selected_site_values[2]}"
fi
[[ "$target" =~ ^[A-Za-z_][A-Za-z0-9_-]*@[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || { printf 'BLOCKED: invalid or missing SSH target.\n' >&2; exit 2; }
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || { printf 'BLOCKED: invalid or missing expected hostname.\n' >&2; exit 2; }
[[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] || { printf 'BLOCKED: identity file is missing or unsafe.\n' >&2; exit 2; }

mkdir -p -- "$report_root" "$artifact_root"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_root/generation_compatibility_correction_${timestamp}_XXXXXX.txt")"
emit 'purpose=accept_retained_grounded_generation_compatibility_correction'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;revalidator_sha256=$revalidator_sha256;evaluator_sha256=$evaluator_sha256"
emit "runtime_transport_sha256=$transport_sha256;cleanup_helper_sha256=$cleanup_sha256"
emit "source_report_sha256=$SOURCE_REPORT_SHA256;retained_response_sha256=$RETAINED_RESPONSE_SHA256"
emit 'authorized_actions=revalidate_checksum_bound_retained_synthetic_response_write_protected_acceptance_evidence_remove_checksum_bound_stale_temporary_directory'
emit 'non_actions=no_model_call_no_model_credential_read_no_service_state_change_no_package_or_configuration_change_no_database_contact_no_organizational_content'
emit "selected_target=$target;expected_hostname=$expected_hostname;identity_label=$(basename -- "$identity_file")"
emit 'operator_expectation=ssh_key_passphrase_up_to_once;target_sudo_password_up_to_once;gemma_api_key_prompt=never'
emit 'local_tests=155;failures=0;errors=0'
while IFS= read -r line; do emit "$line"; done <"$revalidation_result"
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"

control_path="$work_root/ssh-control"
ssh_args=(-i "$identity_file" -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 -o ServerAliveInterval=30 -o ServerAliveCountMax=6 -o ControlMaster=auto -o "ControlPath=$control_path" -o ControlPersist=900)
emit 'milestone=authentication;state=waiting_for_operator_if_prompted'
timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$target" || { emit 'script_49_retained_generation=blocked;reason=ssh_master_start_failed'; exit 1; }
master_started=true
emit 'milestone=authentication;state=pass'
hostname_result="$work_root/hostname.txt"
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" hostname >"$hostname_result" 2>/dev/null || { emit 'script_49_retained_generation=blocked;reason=hostname_probe_failed'; exit 1; }
[[ "$(tr -d '\r\n' <"$hostname_result")" == "$expected_hostname" ]] || { emit 'script_49_retained_generation=blocked;reason=target_hostname_mismatch'; exit 1; }
emit "target_hostname=$expected_hostname"

remote_stage="/tmp/grounded-response-cleanup-$timestamp-$$"
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "test ! -e '$remote_stage' && mkdir -m 0700 -- '$remote_stage'" >/dev/null || { emit 'script_49_retained_generation=blocked;reason=remote_staging_not_created'; exit 1; }
remote_stage_created=true
timeout --foreground 120 scp "${ssh_args[@]}" "$CLEANUP_HELPER" "$target:$remote_stage/cleanup-grounded-generation-trial" >/dev/null || { emit 'script_49_retained_generation=blocked;reason=cleanup_helper_copy_failed'; exit 1; }
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "test \"\$(sha256sum '$remote_stage/cleanup-grounded-generation-trial' | awk '{print \$1}')\" = '$cleanup_sha256'" >/dev/null || { emit 'script_49_retained_generation=blocked;reason=cleanup_helper_identity_mismatch'; exit 1; }
emit 'milestone=guarded_remote_cleanup;state=waiting_for_operator_if_prompted'
set +e
timeout --foreground 300 ssh -tt "${ssh_args[@]}" "$target" \
  "sudo -p '[sudo] password for grounded-generation cleanup: ' bash '$remote_stage/cleanup-grounded-generation-trial' --started-utc '$SOURCE_STARTED_UTC' --expected-payload-sha256 '$SOURCE_PAYLOAD_SHA256' --expected-response-sha256 '$RETAINED_RESPONSE_SHA256'" \
  < /dev/tty 2>&1 | tee "$work_root/cleanup.raw"
cleanup_execution_code="${PIPESTATUS[0]}"
set -e
tr -d '\r' <"$work_root/cleanup.raw" >"$work_root/cleanup.txt"
cleanup_pass_markers="$(grep -Ec '^\[grounded-cleanup\] result=PASS removed=(true|false) already_absent=(true|false)( residue=[A-Za-z0-9_;=-]+)?$' "$work_root/cleanup.txt" || true)"
cleanup_blocked_markers="$(grep -Ec '^\[grounded-cleanup\] result=BLOCKED ' "$work_root/cleanup.txt" || true)"
emit "cleanup_execution_exit_code=$cleanup_execution_code;cleanup_pass_markers=$cleanup_pass_markers;cleanup_blocked_markers=$cleanup_blocked_markers"
if (( cleanup_execution_code != 0 )) || [[ "$cleanup_pass_markers" != 1 || "$cleanup_blocked_markers" != 0 ]]; then
  cleanup_blocked_marker="$(grep -E '^\[grounded-cleanup\] result=BLOCKED ' "$work_root/cleanup.txt" | head -n 1 || true)"
  [[ -z "$cleanup_blocked_marker" ]] || emit "$cleanup_blocked_marker"
  emit 'milestone=guarded_remote_cleanup;state=blocked'
  emit "script_49_retained_generation=blocked;local_report=$report_path"
  exit 1
fi
cleanup_marker="$(grep -E '^\[grounded-cleanup\] result=PASS ' "$work_root/cleanup.txt")"
emit "$cleanup_marker"
emit 'milestone=guarded_remote_cleanup;state=pass'

artifact_path="$artifact_root/live_grounded_generation_${SOURCE_STARTED_UTC}_accepted.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || { emit 'script_49_retained_generation=blocked;reason=accepted_artifact_path_exists'; exit 1; }
cp -- "$candidate_artifact" "$artifact_path"
[[ "$(sha256sum "$artifact_path" | awk '{print $1}')" == "$candidate_sha256" ]] || { emit 'script_49_retained_generation=blocked;reason=accepted_artifact_identity_mismatch'; exit 1; }
printf '%s  %s\n' "$candidate_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$candidate_sha256;accepted_artifact_bytes=$(stat -c '%s' "$artifact_path")"
emit "accepted_checksum=$checksum_path"
emit 'configuration_changed=false;database_changed=false;credential_retained=false;model_call=false;service_state_changed=false'
emit "script_49_retained_generation=pass;local_report=$report_path;next_gate=implement_scope_classifier"
