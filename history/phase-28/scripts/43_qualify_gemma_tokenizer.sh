#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the exact installed Gemma tokenizer and measure accepted synthetic
#   evidence without reading credentials, calling the model, or changing the
#   managed service state. Retain one protected content-free measurement.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/43_qualify_gemma_tokenizer.sh --run

usage() {
  sed -n '3,11p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run                      Explicitly authorize target qualification.' \
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
readonly TARGET_SHELL="$SCRIPT_DIR/measure-generation-tokenizer"
readonly TARGET_PYTHON="$SCRIPT_DIR/measure_generation_tokenizer.py"
readonly LOCAL_EVALUATOR="$SCRIPT_DIR/evaluate_generation_tokenizer.py"
readonly BASE_TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly CHUNKS="$REPO_ROOT/local/artifacts/ishikawa/retrieval-gap-method-profile/structural_chunk_candidates_20261020T002645Z.json"
readonly CHUNK_SHA256='bc993ca0a417353f0d2313bcb2d1c94a1d526a513253139be71117bf88626bf3'
readonly ACCEPTED_FOUNDATION_REPORT="$REPO_ROOT/local/reports/ishikawa-evidence-reconstruction-foundation/evidence_reconstruction_foundation_20261020T014952Z_4Dqxc9.txt"
readonly ACCEPTED_FOUNDATION_REPORT_SHA256='894cad4301149a13d791993b5fbf749cb8caafd080c50b6308150eefb78335f3'
readonly DEFAULT_REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-generation-tokenizer"
readonly DEFAULT_ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/generation-tokenizer"

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
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] || {
    printf 'BLOCKED: identity file is unsafe.\n' >&2
    exit 2
  }
fi
for required in awk bash basename cat chmod cp date grep mkdir mktemp python3 rm scp sha256sum ssh stat tee timeout tr; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'BLOCKED: missing local command: %s\n' "$required" >&2
    exit 2
  }
done
for source in "$TARGET_SHELL" "$TARGET_PYTHON" "$LOCAL_EVALUATOR" "$BASE_TEST_RUNNER" "$CHUNKS" "$ACCEPTED_FOUNDATION_REPORT"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: required Script 43 input is missing or unsafe.\n' >&2
    exit 2
  }
done
[[ "$(sha256sum "$CHUNKS" | awk '{print $1}')" == "$CHUNK_SHA256" ]] || {
  printf 'BLOCKED: accepted chunk artifact checksum mismatch.\n' >&2
  exit 2
}
[[ "$(sha256sum "$ACCEPTED_FOUNDATION_REPORT" | awk '{print $1}')" == "$ACCEPTED_FOUNDATION_REPORT_SHA256" ]] || {
  printf 'BLOCKED: accepted reconstruction report checksum mismatch.\n' >&2
  exit 2
}
for fact in \
  'generation_tokenizer_qualification=pending;numeric_budget_calibration=pending' \
  'evidence_reconstruction_foundation=pass' \
  'local_tests=123;failures=0;errors=0'; do
  grep -Fxq "$fact" "$ACCEPTED_FOUNDATION_REPORT" || {
    printf 'BLOCKED: required accepted reconstruction fact is absent.\n' >&2
    exit 2
  }
done

bash -n "$TARGET_SHELL" "$BASE_TEST_RUNNER"
python3 -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$TARGET_PYTHON" "$LOCAL_EVALUATOR"
for neutral_source in "$TARGET_SHELL" "$TARGET_PYTHON"; do
  if grep -Eiq 'phase[-_ ]?[0-9]+|(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)|Danko|org[_ -]?lab|AgentDanko|repository' "$neutral_source"; then
    printf 'BLOCKED: development or environment jargon found in a neutral target source.\n' >&2
    exit 2
  fi
done

work_root="$(mktemp -d /tmp/ishikawa-script-43.XXXXXX)"
report_path=""
remote_root=""
remote_created=false
master_started=false
ssh_args=()
emit() {
  if [[ -n "$report_path" ]]; then printf '%s\n' "$1" | tee -a "$report_path"; else printf '%s\n' "$1"; fi
}
cleanup() {
  local status="$?" cleanup_code=0 close_code=0
  trap - EXIT INT TERM
  set +e
  if [[ "$remote_created" == true && "$master_started" == true ]]; then
    timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
      "rm -rf -- '$remote_root'" >/dev/null 2>&1 || cleanup_code=$?
    if (( cleanup_code == 0 )); then emit 'cleanup_remote_temporary_files=removed'; else emit "cleanup_remote_temporary_files=review_required;exit_code=$cleanup_code"; status=1; fi
  else
    emit 'cleanup_remote_temporary_files=not_required'
  fi
  if [[ "$master_started" == true ]]; then
    timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1 || close_code=$?
    emit "cleanup_ssh_master_exit_code=$close_code"
    (( close_code == 0 )) || status=1
  fi
  if [[ "$work_root" == /tmp/ishikawa-script-43.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

evaluator_self_test="$work_root/evaluator-self-test.txt"
python3 "$LOCAL_EVALUATOR" --self-test >"$evaluator_self_test"
grep -Fxq 'generation_tokenizer_evaluator_self_test=pass' "$evaluator_self_test" || {
  printf 'script_43_generation_tokenizer=blocked;reason=evaluator_self_test_failed\n' >&2
  exit 1
}

test_result="$work_root/tests.txt"
bash "$BASE_TEST_RUNNER" >"$test_result" 2>&1 || {
  cat "$test_result" >&2
  printf 'script_43_generation_tokenizer=blocked;reason=test_regression\n' >&2
  exit 1
}
grep -Fq 'Ran 123 tests' "$test_result" || { printf 'script_43_generation_tokenizer=blocked;reason=test_count_mismatch\n' >&2; exit 1; }
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || { printf 'script_43_generation_tokenizer=blocked;reason=test_pass_marker_absent\n' >&2; exit 1; }

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
shell_sha256="$(sha256sum "$TARGET_SHELL" | awk '{print $1}')"
measurer_sha256="$(sha256sum "$TARGET_PYTHON" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$LOCAL_EVALUATOR" | awk '{print $1}')"
payload_manifest="$work_root/payload.sha256"
printf '%s  %s\n' \
  "$shell_sha256" 'measure-generation-tokenizer' \
  "$measurer_sha256" 'measure_generation_tokenizer.py' \
  "$CHUNK_SHA256" 'synthetic-chunks.json' >"$payload_manifest"
payload_manifest_sha256="$(sha256sum "$payload_manifest" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_generation_tokenizer_qualification_source' \
    'target_contact=false;credential_read=false;model_call=false;service_state_change=false' \
    "script_sha256=$script_sha256;target_shell_sha256=$shell_sha256;measurer_sha256=$measurer_sha256" \
    "evaluator_sha256=$evaluator_sha256;payload_manifest_sha256=$payload_manifest_sha256" \
    "chunk_sha256=$CHUNK_SHA256;accepted_foundation_report_sha256=$ACCEPTED_FOUNDATION_REPORT_SHA256" \
    'local_tests=123;failures=0;errors=0' \
    'script_43_generation_tokenizer_source=pass'
  exit 0
fi

# Resolve only nonsecret SSH connection values. This file is parsed as data;
# it is never sourced or executed.
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
report_path="$(mktemp "$report_root/generation_tokenizer_${timestamp}_XXXXXX.txt")"
remote_root="/tmp/generation-tokenizer-$timestamp-$$"
emit 'purpose=qualify_installed_generation_tokenizer'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;target_shell_sha256=$shell_sha256;measurer_sha256=$measurer_sha256;evaluator_sha256=$evaluator_sha256"
emit "chunk_sha256=$CHUNK_SHA256;accepted_foundation_report_sha256=$ACCEPTED_FOUNDATION_REPORT_SHA256"
emit "payload_manifest_sha256=$payload_manifest_sha256;payload_members=3;synthetic_candidates=126"
emit 'authorized_actions=stage_checksum_bound_synthetic_input_inspect_installed_generation_profile_run_temporary_network_disabled_tokenizer_container_fetch_content_free_measurement_remove_target_temporary_files'
emit 'non_actions=no_package_or_configuration_change_no_database_contact_no_service_start_or_stop_no_credential_read_no_model_call_no_organizational_content_no_raw_text_retention'
emit "selected_target=$target;expected_hostname=$expected_hostname;identity_label=$(basename -- "$identity_file")"
emit 'operator_expectation=ssh_key_passphrase_up_to_once;target_sudo_password_up_to_once;api_key_prompt=none'
emit 'local_tests=123;failures=0;errors=0'

control_path="$work_root/ssh-control"
ssh_args=(-i "$identity_file" -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 -o ServerAliveInterval=30 -o ServerAliveCountMax=20 -o ControlMaster=auto -o "ControlPath=$control_path" -o ControlPersist=3600)
emit 'milestone=authentication;state=waiting_for_operator_if_prompted'
timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$target" >"$work_root/master.stdout" 2>"$work_root/master.stderr" || { emit 'script_43_generation_tokenizer=blocked;reason=ssh_master_start_failed'; exit 1; }
master_started=true
emit 'milestone=authentication;state=pass'
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" hostname >"$work_root/hostname.stdout" 2>"$work_root/hostname.stderr" || { emit 'script_43_generation_tokenizer=blocked;reason=hostname_probe_failed'; exit 1; }
[[ "$(tr -d '\r\n' <"$work_root/hostname.stdout")" == "$expected_hostname" ]] || { emit 'script_43_generation_tokenizer=blocked;reason=target_hostname_mismatch'; exit 1; }
emit "target_hostname=$expected_hostname"
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" >"$work_root/create.stdout" 2>"$work_root/create.stderr" || { emit 'script_43_generation_tokenizer=blocked;reason=remote_temporary_directory_not_created'; exit 1; }
remote_created=true
timeout --foreground 180 scp "${ssh_args[@]}" "$TARGET_SHELL" "$TARGET_PYTHON" "$CHUNKS" "$payload_manifest" "$target:$remote_root/" >"$work_root/scp.stdout" 2>"$work_root/scp.stderr" || { emit 'script_43_generation_tokenizer=blocked;reason=target_payload_copy_failed'; exit 1; }
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "cd '$remote_root' && mv '$(basename -- "$CHUNKS")' synthetic-chunks.json && sha256sum --check --strict payload.sha256" >"$work_root/hash.stdout" 2>"$work_root/hash.stderr" || { emit 'script_43_generation_tokenizer=blocked;reason=target_payload_hash_mismatch'; exit 1; }
emit 'milestone=target_payload_verification;state=pass'

emit 'milestone=generation_tokenizer_measurement;state=waiting_for_operator_sudo_if_prompted'
set +e
timeout --foreground 1200 ssh -tt "${ssh_args[@]}" "$target" \
  "cd '$remote_root' && umask 077 && sudo -p '[sudo] password for generation tokenizer qualification: ' bash ./measure-generation-tokenizer --input '$remote_root/synthetic-chunks.json' --expected-input-sha256 '$CHUNK_SHA256' --output '$remote_root/generation-tokenizer-measurement.json' > '$remote_root/qualification-result.txt' 2>&1" < /dev/tty
remote_code=$?
set -e
emit "remote_execution_exit_code=$remote_code;raw_output_retained=false"
fetched_result="$work_root/qualification-result.txt"
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/qualification-result.txt" "$fetched_result" >"$work_root/fetch-result.stdout" 2>"$work_root/fetch-result.stderr" || { emit 'script_43_generation_tokenizer=blocked;reason=result_fetch_failed'; exit 1; }
tr -d '\r' <"$fetched_result" >"$work_root/qualification-result.normalized"
fetched_result="$work_root/qualification-result.normalized"
output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] || ! [[ "$line" =~ ^\[generation-tokenizer\]\ [A-Za-z0-9_.:/=@+,-]+(\ [A-Za-z0-9_.:/=@+,-]+)*$ ]]; then output_contract=blocked; continue; fi
  emit "$line"
done <"$fetched_result"
emit "remote_output_contract=$output_contract"
pass_markers="$(grep -Fxc '[generation-tokenizer] result=PASS next=numeric_budget_review' "$fetched_result" || true)"
blocked_markers="$(grep -Fc '[generation-tokenizer] result=BLOCKED ' "$fetched_result" || true)"
emit "pass_markers=$pass_markers;blocked_markers=$blocked_markers"
if (( remote_code != 0 )) || [[ "$output_contract" != pass || "$pass_markers" != 1 || "$blocked_markers" != 0 ]]; then
  emit 'milestone=generation_tokenizer_measurement;state=blocked'
  emit "script_43_generation_tokenizer=blocked;local_report=$report_path;next_gate=review_content_free_result_before_any_retry"
  exit 1
fi
fetched_artifact="$work_root/generation-tokenizer-measurement.json"
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/generation-tokenizer-measurement.json" "$fetched_artifact" >"$work_root/fetch-artifact.stdout" 2>"$work_root/fetch-artifact.stderr" || { emit 'script_43_generation_tokenizer=blocked;reason=measurement_artifact_fetch_failed'; exit 1; }
emit 'milestone=generation_tokenizer_measurement;state=pass'

evaluation_result="$work_root/evaluation.txt"
set +e
python3 "$LOCAL_EVALUATOR" --artifact "$fetched_artifact" --expected-source-sha256 "$CHUNK_SHA256" >"$evaluation_result"
evaluation_code=$?
set -e
evaluation_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then evaluation_contract=blocked; continue; fi
  emit "$line"
done <"$evaluation_result"
evaluation_pass_markers="$(grep -Fxc 'generation_tokenizer_evaluation=pass' "$evaluation_result" || true)"
evaluation_blocked_markers="$(grep -Ec '^generation_tokenizer_evaluation=blocked;' "$evaluation_result" || true)"
emit "evaluation_exit_code=$evaluation_code;evaluation_output_contract=$evaluation_contract;evaluation_pass_markers=$evaluation_pass_markers;evaluation_blocked_markers=$evaluation_blocked_markers"
if (( evaluation_code != 0 )) || [[ "$evaluation_contract" != pass || "$evaluation_pass_markers" != 1 || "$evaluation_blocked_markers" != 0 ]]; then
  rejected_root="$artifact_root/rejected"
  mkdir -p -- "$rejected_root"
  rejected_path="$rejected_root/rejected_generation_tokenizer_measurement_${timestamp}.json"
  if [[ ! -e "$rejected_path" && ! -L "$rejected_path" ]]; then
    cp -- "$fetched_artifact" "$rejected_path"
    chmod 0600 "$rejected_path" 2>/dev/null || true
    emit "rejected_measurement_retained=$rejected_path;rejected_measurement_sha256=$(sha256sum "$rejected_path" | awk '{print $1}')"
  fi
  emit 'milestone=local_measurement_evaluation;state=blocked'
  emit "script_43_generation_tokenizer=blocked;local_report=$report_path;next_gate=review_content_free_evaluation_before_any_retry"
  exit 1
fi
emit 'milestone=local_measurement_evaluation;state=pass'

artifact_sha256="$(sha256sum "$fetched_artifact" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$fetched_artifact")"
artifact_path="$artifact_root/generation_tokenizer_measurement_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || { emit 'script_43_generation_tokenizer=blocked;reason=local_artifact_path_exists'; exit 1; }
cp -- "$fetched_artifact" "$artifact_path"
[[ "$(sha256sum "$artifact_path" | awk '{print $1}')" == "$artifact_sha256" ]] || { emit 'script_43_generation_tokenizer=blocked;reason=retained_artifact_identity_mismatch'; exit 1; }
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true
emit "accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$artifact_bytes"
emit "accepted_artifact=$artifact_path;accepted_checksum=$checksum_path"
emit 'numeric_budget_calibration=pending_review;configuration_changed=false;service_state_changed=false'
emit "script_43_generation_tokenizer=pass;local_report=$report_path;next_gate=review_and_freeze_numeric_context_budget"
