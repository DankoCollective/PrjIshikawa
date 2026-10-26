#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Purpose:
#   Exercise Script 06's local wrapper, transport, reporting, result parsing,
#   cleanup, and public modes without connecting to EmceeDanko.
#
# Mental model:
#   Keep every real local artifact/evidence check, replace only ssh/scp with a
#   filesystem-backed target double, and prove pass, remote failure, accept,
#   rollback, and signal-result behavior.
#
# Inputs or prerequisites:
#   The exact current Script 01 and Script 05 local handoffs.
#
# Outputs or artifact lane:
#   Temporary /tmp files only; no target contact or repository mutation.
#
# Usage:
#   bash ./deployment/tests/attended-v1.3-wrapper.sh

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
readonly orchestrator="$repo_root/deployment/scripts/06_attended-v1.3-on-emceedanko.sh"

last_output=''
test_root=''

fail() {
  [[ -z "$last_output" || ! -f "$last_output" ]] || tail -n 200 "$last_output" >&2 || true
  printf '\nSCRIPT RESULT\nattended_v1_3_wrapper_test=blocked;reason=%s\n' "$1" >&2
  exit 1
}

[[ -f "$orchestrator" && ! -L "$orchestrator" ]] || fail orchestrator_unsafe
for command_name in bash cp find grep mktemp script sed tar; do
  command -v "$command_name" >/dev/null 2>&1 || fail "command_missing_${command_name}"
done
bash -n "$orchestrator" || fail orchestrator_syntax_invalid

test_root="$(mktemp -d /tmp/ishikawa-attended-wrapper-test.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  [[ "$test_root" == /tmp/ishikawa-attended-wrapper-test.* && -d "$test_root" ]] \
    && rm -rf -- "$test_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p -- "$test_root/bin" "$test_root/remote" "$test_root/reports" "$test_root/state"

write_command() {
  local name="$1" body="$2"
  printf '#!/usr/bin/env bash\nset -Eeuo pipefail\n%s\n' "$body" >"$test_root/bin/$name"
  chmod 0700 "$test_root/bin/$name"
}

write_command ssh '
for argument in "$@"; do
  [[ "$argument" == -G ]] && exit 0
  [[ "$argument" == -Nf ]] && exit 0
done
for ((index=1; index<=$#; index++)); do
  if [[ "${!index}" == -O ]]; then
    next=$((index + 1)); [[ "${!next}" == check || "${!next}" == exit ]] && exit 0
  fi
done
command_text="${!#}"
remote_root="$(sed -n "s/^[^\x27]*\x27\(\/tmp\/ishikawa-v1.3-attended-[^\x27]*\)\x27.*/\1/p" <<<"$command_text" | head -n 1)"
remote_root="${remote_root%%/payload*}"
[[ -n "$remote_root" ]] || exit 2
mapped="$ISHIKAWA_WRAPPER_REMOTE/$(basename -- "$remote_root")"
if [[ "$command_text" == *"mkdir -m 0700"* ]]; then
  [[ ! -e "$mapped" ]] || exit 1
  mkdir -m 0700 -- "$mapped"
  exit 0
fi
if [[ "$command_text" == *"rm -rf --"* ]]; then
  rm -rf -- "$mapped"
  [[ ! -e "$mapped" ]]
  exit
fi
if [[ "$command_text" == *"tar -xzf script-06-payload.tar.gz"* ]]; then
  tar -xzf "$mapped/script-06-payload.tar.gz" -C "$mapped"
  (cd -- "$mapped/payload" && sha256sum --check --strict SHA256SUMS >/dev/null)
  exit
fi
if [[ "$command_text" == *"ISHIKAWA_SCRIPT06_INTERNAL=1"* ]]; then
  result="$mapped/payload/target-result.txt"
  mode=launch
  [[ "$command_text" == *"--target-accept"* ]] && mode=accept
  [[ "$command_text" == *"--target-rollback"* ]] && mode=rollback
  waiver=false
  [[ "$command_text" != *"--waive-v1-2-rollback"* ]] || waiver=true
  common() {
    printf "%s\n" \
      "target_hostname=EmceeDanko;os_id=ubuntu;os_version=24.04;architecture=amd64" \
      "application_archive_sha256=53da57b745fb4c8be6335896d05bdb6f63f2de3494862b99acca09e156863f3c;script_05_report_sha256=854240b564148f38853b183852ca98ac12d38ef3a57bb6ed513116270d7a98c0" \
      "database=rag_catalog;postgresql_port=5432;postgresql_cluster=isolated_durable;schema_version=5;ui_port=3384;retrieval_api_port=8384;port_1384_purpose=v1_2_runtime_and_rollback" \
      "candidate_mutated=false;v1_2_database_mutated=false;rollback_tree_mutated=false;boot_autostart_changed=false"
  }
  if [[ "$ISHIKAWA_WRAPPER_SCENARIO" == remote_failure ]]; then
    {
      common
      printf "%s\n" \
        "$([[ "$waiver" == true ]] && printf "v1_2_rollback_guarantee=waived;automatic_v1_2_restoration=false;v1_2_files_and_database_preserved=true" || printf "v1_2_rollback_guarantee=verified;automatic_v1_2_restoration=true;v1_2_files_and_database_preserved=true")" \
        "v1_2_restored=true;cleanup=pass" \
        "FAILURE DETAIL" \
        "stage=v1_3_attended_launch" \
        "reason=test_remote_launch_failure" \
        "detail=The target double rejected the attended web launch." \
        "operator_action=Review the retained target report." \
        "ishikawa_v1_3_emceedanko_attended_launch=blocked"
    } >"$result"
    printf "%s\n" "[ROLLBACK] state=pass;v1_2_retrieval=ready;v1_2_web=ready"
    exit 17
  fi
  if [[ "$ISHIKAWA_WRAPPER_SCENARIO" == interrupt ]]; then
    printf "%s\n" "$mapped" >"$ISHIKAWA_WRAPPER_STATE/action-root"
    kill -TERM "$PPID"
    sleep 0.2
    exit 143
  fi
  {
    common
    printf "%s\n" "v1_2_restored=false;cleanup=pass"
    case "$mode" in
      launch)
        printf "%s\n" \
          "$([[ "$waiver" == true ]] && printf "v1_2_rollback_guarantee=waived;automatic_v1_2_restoration=false;v1_2_files_and_database_preserved=true" || printf "v1_2_rollback_guarantee=verified;automatic_v1_2_restoration=true;v1_2_files_and_database_preserved=true")" \
          "durable_v1_3_database=ready;documents=30;pages=150;authoritative_chunks=786;retrieval_candidates=943;embeddings=943;relationship_records=240;relationship_pairs=90" \
          "attended_runtime=ready;ui=http://127.0.0.1:3384;retrieval_api=http://127.0.0.1:8384;v1_2_stopped=true" \
          "ishikawa_v1_3_emceedanko_attended_launch=pass" ;;
      accept)
        printf "%s\n" \
          "human_ui_acceptance=accepted;org_lab_packaging_gate=authorized_for_separate_later_action" \
          "ishikawa_v1_3_emceedanko_human_ui_acceptance=pass" ;;
      rollback)
        printf "%s\n" \
          "attended_runtime=stopped;v1_2_restored=true;durable_v1_3_database=preserved" \
          "ishikawa_v1_3_emceedanko_attended_rollback=pass" ;;
    esac
  } >"$result"
  printf "%s\n" "[SUMMARY] state=pass;mode=$mode"
  exit 0
fi
exit 2'

write_command scp '
source_path="${@: -2:1}"; destination="${@: -1}"
if [[ "$destination" == *:* ]]; then
  remote_path="${destination#*:}"
  remote_root="${remote_path%/}"
  mapped="$ISHIKAWA_WRAPPER_REMOTE/$(basename -- "$remote_root")"
  cp -- "$source_path" "$mapped/"
else
  remote_path="${source_path#*:}"
  remote_root="${remote_path%%/payload/*}"
  mapped="$ISHIKAWA_WRAPPER_REMOTE/$(basename -- "$remote_root")"
  cp -- "$mapped/payload/target-result.txt" "$destination"
fi'

run_public() {
  local name="$1" public_mode="$2" scenario="$3"
  local output="$test_root/${name}.stdout" command
  shift 3
  last_output="$output"
  command="bash '$orchestrator' '$public_mode' --target TestTarget --report-root '$test_root/reports'"
  for argument in "$@"; do
    [[ "$argument" == --waive-v1-2-rollback ]] || fail invalid_wrapper_test_argument
    command+=" '$argument'"
  done
  set +e
  PATH="$test_root/bin:$PATH" \
    ISHIKAWA_WRAPPER_REMOTE="$test_root/remote" \
    ISHIKAWA_WRAPPER_STATE="$test_root/state" \
    ISHIKAWA_WRAPPER_SCENARIO="$scenario" \
      script -qefc "$command" /dev/null 2>&1 | tr -d '\r' >"$output"
  public_status="${PIPESTATUS[0]}"
  set -e
}

assert_single_result() {
  local output="$1" state="$2"
  [[ "$(grep -c '^SCRIPT RESULT$' "$output")" == 1 ]] || fail result_heading_count_invalid
  [[ "$(grep -c "^script_06_attended_v1_3_on_emceedanko=${state}$" "$output")" == 1 ]] \
    || fail result_marker_count_invalid
}

run_public launch-success --run success
(( public_status == 0 )) || fail launch_wrapper_failed
assert_single_result "$last_output" pass
grep -Fq '[SUMMARY] target_ui_address=http://127.0.0.1:3384' "$last_output" || fail ui_address_missing
grep -Fq 'acceptance_command=bash ./deployment/scripts/06_attended-v1.3-on-emceedanko.sh --accept --target TestTarget' "$last_output" || fail acceptance_command_missing
grep -Fq 'rollback_command=bash ./deployment/scripts/06_attended-v1.3-on-emceedanko.sh --rollback --target TestTarget' "$last_output" || fail rollback_command_missing
[[ -z "$(find "$test_root/remote" -mindepth 1 -print -quit)" ]] || fail launch_remote_cleanup_failed

run_public waived-launch-success --run success --waive-v1-2-rollback
(( public_status == 0 )) || fail waived_launch_wrapper_failed
assert_single_result "$last_output" pass
grep -Fq 'recovery_posture=v1_2_rollback_guarantee_waived;automatic_v1_2_restoration=false;v1_2_files_and_database_preserved=true' "$last_output" \
  || fail waived_recovery_posture_missing
grep -Fq 'prompts=ssh_then_attended_sudo_then_four_hidden_v1_3_runtime_credentials' "$last_output" \
  || fail waived_prompt_contract_missing
grep -Fq 'conditional_rollback_command=bash ./deployment/scripts/06_attended-v1.3-on-emceedanko.sh --rollback --target TestTarget' "$last_output" \
  || fail conditional_rollback_command_missing
grep -Fq 'conditional_rollback_requires=v1_2_postgresql_password_and_model_forwards_on_8000_8001' "$last_output" \
  || fail conditional_rollback_requirements_missing
! grep -Fq '[SUMMARY] rollback_command=' "$last_output" \
  || fail unconditional_rollback_command_present
[[ -z "$(find "$test_root/remote" -mindepth 1 -print -quit)" ]] \
  || fail waived_launch_remote_cleanup_failed

run_public launch-failure --run remote_failure
(( public_status == 17 )) || fail remote_failure_status_invalid
assert_single_result "$last_output" blocked
grep -Fxq 'reason=test_remote_launch_failure' "$last_output" || fail remote_failure_reason_missing
grep -Fxq 'detail=The target double rejected the attended web launch.' "$last_output" || fail remote_failure_detail_missing
[[ -z "$(find "$test_root/remote" -mindepth 1 -print -quit)" ]] || fail failed_launch_remote_cleanup_failed

run_public accept-success --accept success
(( public_status == 0 )) || fail accept_wrapper_failed
assert_single_result "$last_output" pass
grep -Fq '[ACCEPT] state=pass;action=accept;target_result=pass' "$last_output" || fail accept_milestone_missing

run_public invalid-accept-waiver --accept success --waive-v1-2-rollback
(( public_status == 2 )) || fail invalid_accept_waiver_status
assert_single_result "$last_output" blocked
grep -Fxq 'reason=rollback_waiver_mode_invalid' "$last_output" \
  || fail invalid_accept_waiver_reason_missing

run_public rollback-success --rollback success
(( public_status == 0 )) || fail rollback_wrapper_failed
assert_single_result "$last_output" pass
grep -Fq '[ROLLBACK] state=pass;action=rollback;target_result=pass' "$last_output" || fail rollback_milestone_missing

run_public interrupted-launch --run interrupt
(( public_status == 143 )) || fail interrupt_status_invalid
assert_single_result "$last_output" blocked
grep -Fxq 'reason=signal_termination' "$last_output" || fail interrupt_reason_missing
[[ -z "$(find "$test_root/remote" -mindepth 1 -print -quit)" ]] || fail interrupt_remote_cleanup_failed

validate_output="$test_root/validate.stdout"
last_output="$validate_output"
PATH="$test_root/bin:$PATH" bash "$orchestrator" --validate-only >"$validate_output"
assert_single_result "$validate_output" ready
grep -Fxq 'target_contact=false;database_contact=false;service_changed=false;credential_read=false' "$validate_output" \
  || fail validate_only_boundary_missing
grep -Fxq 'selected_ports=ui:3384,retrieval_api:8384;port_1384_purpose=v1_2_runtime_and_rollback' "$validate_output" \
  || fail validate_only_port_purpose_missing

printf '%s\n' \
  'local_evidence_revalidation=pass;payload_assembly=pass;transfer_verification=pass;temporary_remote_cleanup=pass' \
  'launch_wrapper=pass;rollback_waiver_wrapper=pass;waiver_mode_restriction=pass;remote_failure_propagation=pass;accept_wrapper=pass;rollback_wrapper=pass;validate_only=pass' \
  'signal_cleanup=pass;single_result_contract=pass;ui_and_operator_commands=pass'
printf '\nSCRIPT RESULT\nattended_v1_3_wrapper_test=pass\n'
