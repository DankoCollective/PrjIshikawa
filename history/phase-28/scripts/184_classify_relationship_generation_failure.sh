#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Classify the two grounded-generation failures from the first Script 183
#   responsive case without repeating the remaining complete API gate.
#
# Mental model:
#   Run the unchanged Script 183 qualification under the existing content-free
#   generation observer. After the first turn with two failed permitted
#   attempts is identified, stop Script 183 through its normal signal cleanup,
#   validate the stable reason codes, and retain only that classification in a
#   local report. A turn whose retry succeeds does not end the diagnostic.
#
# Inputs or prerequisites:
#   The same forwarded loopback Gemma and Nomic services and interactive API
#   keys required by Script 183. Script 183 owns its disposable PostgreSQL
#   cluster, ingestion, service lifecycle, diagnostics, and verified cleanup.
#
# Outputs or artifact lane:
#   Writes one content-free report beneath
#   local/reports/ishikawa-v1.3-generation-failure-classification/.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/184_classify_relationship_generation_failure.sh --run

usage() {
  sed -n '3,24p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Classify the first responsive turn and stop.' \
    '  --validate-only Validate the local diagnostic contract only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly SCRIPT_183="$SCRIPT_DIR/183_qualify_relationship_complete_v1_3_api_and_gemma.sh"
readonly OBSERVER_DIR="$SCRIPT_DIR/generation_failure_diagnostic_hook"
readonly OBSERVER="$OBSERVER_DIR/sitecustomize.py"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.3-generation-failure-classification"
readonly SCRIPT_183_SHA256='6fbef6f679f3805d8917487aea09ccc15b074ad8fa956abf53175cd153e5424a'
readonly OBSERVER_SHA256='09a264c3ea55519ef67a97c96630c43f9a62046fb4cace77b8a55a493dd9d29f'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      printf 'reason=argument_invalid\n\nSCRIPT RESULT\nscript_184_generation_failure_classification=blocked\n' >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'reason=mode_invalid\n\nSCRIPT RESULT\nscript_184_generation_failure_classification=blocked\n' >&2
  exit 2
}

preflight_block() {
  printf 'reason=%s\n\nSCRIPT RESULT\nscript_184_generation_failure_classification=blocked\n' "$1" >&2
  exit "${2:-2}"
}

for command_name in bash chmod date env grep install kill mkdir mkfifo mktemp \
  python3 rm sed sha256sum sleep stat tail tee wc; do
  command -v "$command_name" >/dev/null 2>&1 \
    || preflight_block "local_command_missing_$command_name"
done
[[ -f "$SCRIPT_183" && ! -L "$SCRIPT_183" && -x "$SCRIPT_183" ]] \
  || preflight_block script_183_unsafe
[[ -f "$OBSERVER" && ! -L "$OBSERVER" && -r "$OBSERVER" ]] \
  || preflight_block generation_observer_unsafe
[[ "$(sha256sum "$SCRIPT_183" | sed 's/ .*//')" == "$SCRIPT_183_SHA256" ]] \
  || preflight_block script_183_identity_changed
[[ "$(sha256sum "$OBSERVER" | sed 's/ .*//')" == "$OBSERVER_SHA256" ]] \
  || preflight_block generation_observer_identity_changed
PYTHONDONTWRITEBYTECODE=1 python3 -B -m py_compile "$OBSERVER" \
  || preflight_block generation_observer_compile_failed 1

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | sed 's/ .*//')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_relationship_generation_failure_classifier' \
    "script_sha256=$script_sha256;script_183_sha256=$SCRIPT_183_SHA256;observer_sha256=$OBSERVER_SHA256" \
    'database_contact=false;model_contact=false;credential_read=false;service_started=false;accepted_state_changed=false' \
    '' \
    'SCRIPT RESULT' \
    'script_184_generation_failure_classification=pass'
  exit 0
fi

umask 077
mkdir -p -- "$REPORT_ROOT" || preflight_block report_root_creation_failed
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" ]] \
  || preflight_block report_root_unsafe
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/generation_failure_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-script-184.XXXXXX)"
failure_log="$work_root/generation-failures.jsonl"
nested_output="$work_root/script-183.output"
output_pipe="$work_root/script-183.pipe"
install -m 0600 /dev/null "$failure_log"
mkfifo -m 0600 "$output_pipe"

nested_pid=''
stream_pid=''
failure_reason=''
classification_complete=false
current_stage='runtime_initialization'
readonly MAIN_BASHPID="$BASHPID"

emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
block() { failure_reason="$1"; exit "${2:-1}"; }
record_unexpected_error() {
  local status="$1"
  if [[ "$BASHPID" == "$MAIN_BASHPID" && -z "$failure_reason" ]]; then
    failure_reason="${current_stage}_unexpected_exit_${status}"
  fi
}
cleanup() {
  local status="$?" result=blocked
  trap - ERR EXIT HUP INT TERM
  set +e
  if [[ "$nested_pid" =~ ^[0-9]+$ ]] && kill -0 "$nested_pid" 2>/dev/null; then
    kill -TERM "$nested_pid" 2>/dev/null || true
    wait "$nested_pid" 2>/dev/null || true
  fi
  if [[ "$stream_pid" =~ ^[0-9]+$ ]] && kill -0 "$stream_pid" 2>/dev/null; then
    kill -TERM "$stream_pid" 2>/dev/null || true
    wait "$stream_pid" 2>/dev/null || true
  fi
  [[ "$work_root" == /tmp/ishikawa-script-184.* && -d "$work_root" ]] \
    && rm -rf -- "$work_root"
  if (( status == 0 )) && [[ "$classification_complete" == true ]]; then
    result=pass
  else
    status=1
    [[ -n "$failure_reason" ]] || failure_reason="${current_stage}_unexpected_exit"
  fi
  emit "local_report=$report_path"
  {
    printf '\nSCRIPT RESULT\n'
    [[ "$result" == pass ]] || printf 'reason=%s\n' "$failure_reason"
    printf 'script_184_generation_failure_classification=%s\n' "$result"
  } | tee -a "$report_path"
  exit "$status"
}
trap 'record_unexpected_error $?' ERR
trap cleanup EXIT
trap 'failure_reason=interrupted_HUP; exit 129' HUP
trap 'failure_reason=interrupted_INT; exit 130' INT
trap 'failure_reason=interrupted_TERM; exit 143' TERM

emit 'purpose=classify_relationship_complete_generation_failure'
emit "started_utc=$timestamp;script_sha256=$script_sha256;script_183_sha256=$SCRIPT_183_SHA256;observer_sha256=$OBSERVER_SHA256"
emit 'authorized_actions=run_unchanged_script_183_with_content_free_failure_observer_stop_after_two_generation_attempts'
emit 'non_actions=no_application_change_no_corpus_change_no_truth_change_no_profile_change_no_accepted_database_contact_no_package_or_release_change_no_raw_prompt_response_chunk_vector_or_secret_retention'
emit 'milestone=observed_script_183;state=start;target=first_turn_with_two_failed_attempts'

current_stage=observed_script_183
tee "$nested_output" <"$output_pipe" &
stream_pid="$!"
env \
  PYTHONPATH="$OBSERVER_DIR" \
  ISHIKAWA_DIAGNOSTIC_FAILURE_LOG="$failure_log" \
  bash "$SCRIPT_183" --run >"$output_pipe" 2>&1 &
nested_pid="$!"

started_epoch="$(date +%s)"
next_heartbeat=$(( started_epoch + 30 ))
stop_requested=false
while kill -0 "$nested_pid" 2>/dev/null; do
  failure_count="$(wc -l <"$failure_log" | sed 's/[[:space:]]//g')"
  if grep -q '"failure_ordinal":2' "$failure_log"; then
    emit "milestone=observed_script_183;state=classified;observed_failures=$failure_count;requesting_verified_cleanup=true"
    kill -TERM "$nested_pid" 2>/dev/null || true
    stop_requested=true
    break
  fi
  now_epoch="$(date +%s)"
  if (( now_epoch >= next_heartbeat )); then
    emit "milestone=observed_script_183;state=running;elapsed_seconds=$(( now_epoch - started_epoch ));classified_attempts=$failure_count"
    next_heartbeat=$(( now_epoch + 30 ))
  fi
  sleep 1
done

if wait "$nested_pid"; then nested_status=0; else nested_status="$?"; fi
nested_pid=''
wait "$stream_pid" || block nested_output_stream_failed
stream_pid=''
[[ "$stop_requested" == true ]] || block nested_script_ended_before_two_failures
[[ "$nested_status" == 143 ]] || block nested_script_signal_status_invalid
grep -Fxq 'reason=interrupted_TERM' "$nested_output" \
  || block nested_script_interruption_marker_absent
grep -Fxq 'script_183_relationship_complete_v1_3_api_gemma=blocked' "$nested_output" \
  || block nested_script_result_marker_absent
grep -Fq 'milestone=cleanup;state=pass;' "$nested_output" \
  || block nested_script_cleanup_not_clean
nested_report="$(sed -n 's/^local_report=//p' "$nested_output" | tail -n 1)"
[[ -n "$nested_report" && "$nested_report" == "$REPO_ROOT"/local/reports/ishikawa-v1.3-complete-api-gemma/* \
   && -f "$nested_report" && ! -L "$nested_report" ]] \
  || block nested_report_invalid
nested_report_sha256="$(sha256sum "$nested_report" | sed 's/ .*//')"

classification="$({ PYTHONDONTWRITEBYTECODE=1 python3 -B - "$failure_log" <<'PY'
import json
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
lines = path.read_text(encoding="utf-8", errors="strict").splitlines()
assert 2 <= len(lines) <= 26
records = [json.loads(line) for line in lines]
expected_fields = {
    "failure_family",
    "failure_ordinal",
    "reason_code",
    "schema",
    "turn_id",
}
assert all(set(record) == expected_fields for record in records)
assert all(record["schema"] == "ishikawa.generation-failure-diagnostic.v1" for record in records)
assert all(re.fullmatch(r"[0-9a-f]{64}", record["turn_id"]) for record in records)
assert all(
    record["failure_family"] in {"response_validation", "transport", "unclassified"}
    for record in records
)
assert all(re.fullmatch(r"[A-Z][A-Z0-9_]{0,95}", record["reason_code"]) for record in records)
by_turn = {}
for record in records:
    by_turn.setdefault(record["turn_id"], []).append(record)
complete_turns = [
    turn_records
    for turn_records in by_turn.values()
    if [record["failure_ordinal"] for record in turn_records] == [1, 2]
]
assert complete_turns
classified = complete_turns[0]
families = ",".join(record["failure_family"] for record in classified)
reasons = ",".join(record["reason_code"] for record in classified)
print(f"failure_families={families};reason_codes={reasons};attempts=2")
PY
} 2>/dev/null)" || block failure_classification_invalid
[[ "$classification" =~ ^failure_families=[a-z_,]+\;reason_codes=[A-Z0-9_,]+\;attempts=2$ ]] \
  || block failure_classification_summary_invalid

emit 'milestone=observed_script_183;state=pass;target=first_turn_with_two_failed_attempts;attempts=2;cleanup=verified'
emit "$classification"
emit "nested_report=$nested_report;nested_report_sha256=$nested_report_sha256"
emit 'raw_prompt_retained=false;raw_response_retained=false;evidence_content_retained=false;credentials_retained=false'
emit 'next_gate=review_reason_codes_before_application_or_frozen_gate_change'
classification_complete=true
current_stage=complete
