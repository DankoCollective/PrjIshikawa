#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the isolated Ishikawa v1.1 known-document routing correction and
#   locate the stage boundaries of the two dependency failures retained in the
#   immutable v1 retrieval baseline.
#
# Mental model:
#   Reverify the Script 113 v1 checkpoint, run the complete local regression
#   suite, prove that the v1.1 case set changes only the vague-document
#   expectation, then copy one neutral read-only inspector to EmceeDanko. The
#   inspector reads existing content-free logs, returns one bounded diagnostic,
#   and is removed. No v1.1 code is installed in this gate.
#
# Inputs or prerequisites:
#   Clean Script 113 evidence, retained v1 baseline logs on EmceeDanko, and
#   strict SSH host trust. The Ishikawa stack may remain in its current state.
#   No sudo is required.
#
# Outputs or artifact lane:
#   One local content-free report and one checksum-bound request-stage
#   diagnostic. The accepted v1 package and target runtime remain unchanged.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/114_qualify_v1_1_query_routing_and_diagnose_baseline.sh --run

usage() {
  sed -n '3,27p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run                      Qualify source and inspect retained target logs.' \
    '  --target VALUE             SSH destination or configured SSH alias.' \
    '  --expected-hostname NAME   Exact target short hostname.' \
    '  --expected-os-version VER  Exact expected Ubuntu major.minor version.' \
    '  --identity-file PATH       Optional explicit SSH private key.' \
    '  --validate-only            Validate local source without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly PYTHON_ROOT="$ISHIKAWA_ROOT/application/python"
readonly TEST_ROOT="$ISHIKAWA_ROOT/tests"
readonly INSPECTOR="$SCRIPT_DIR/inspect-request-stage-history.py"
readonly V1_CASES="$PHASE_ROOT/reference/ishikawa-retrieval-tuning-cases-v1.json"
readonly V1_1_CASES="$PHASE_ROOT/reference/ishikawa-retrieval-tuning-cases-v1.1.json"
readonly CHECKPOINT_REPORT="$REPO_ROOT/local/reports/ishikawa-v1-fallback-checkpoint/ishikawa_v1_fallback_checkpoint_20261021T141824Z_E3vxWj.txt"
readonly CHECKPOINT_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/v1-fallback-checkpoint/ishikawa_v1_fallback_checkpoint_20261021T141824Z.json"
readonly CHECKPOINT_CHECKSUM="$CHECKPOINT_ARTIFACT.sha256"
readonly BASELINE_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/retrieval-tuning-baseline/retrieval_tuning_baseline_20261021T134742Z.json"
readonly CHECKPOINT_REPORT_SHA256='4c7a1bf51434d10bae2aabc9878fb5417a28aac034503f500a1b3ebbb5568a47'
readonly CHECKPOINT_ARTIFACT_SHA256='a9f2af44ef7368bb96c4e512168c7ecc9839f1f565bd47c3b5a717dc6386e736'
readonly CHECKPOINT_CHECKSUM_SHA256='7f4faa47aecc0672d40b77b95c5088a8c51145970a2fe792453afb60ae97a2f3'
readonly BASELINE_ARTIFACT_SHA256='caa13083d68a2f02eb0c6deb2851febd5c54cfaf448a14979badffa6b86867dd'
readonly V1_ARCHIVE_SHA256='c848680051786b2b3c6ac454b3f007be1632d45215ddf9c8f1d4d04b924845b1'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.1-query-routing"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v1.1-query-routing"
readonly -a ROUTING_SOURCES=(
  "$PYTHON_ROOT/ishikawa/query_routing.py"
  "$PYTHON_ROOT/ishikawa/native_adapters.py"
  "$PYTHON_ROOT/ishikawa/runtime.py"
  "$TEST_ROOT/test_query_routing.py"
  "$TEST_ROOT/test_native_adapters.py"
  "$TEST_ROOT/test_runtime.py"
)

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
    *) printf 'script_114_v1_1_query_routing=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_114_v1_1_query_routing=blocked;reason=mode_invalid\n' >&2
  exit 2
}
[[ "$target" =~ ^[A-Za-z0-9_@.:-]+$ ]] || {
  printf 'script_114_v1_1_query_routing=blocked;reason=target_invalid\n' >&2
  exit 2
}
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || {
  printf 'script_114_v1_1_query_routing=blocked;reason=expected_hostname_invalid\n' >&2
  exit 2
}
[[ "$expected_os_version" =~ ^[0-9]{2}\.[0-9]{2}$ ]] || {
  printf 'script_114_v1_1_query_routing=blocked;reason=expected_os_version_invalid\n' >&2
  exit 2
}
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] || {
    printf 'script_114_v1_1_query_routing=blocked;reason=identity_file_unsafe\n' >&2
    exit 2
  }
fi

for required_command in awk bash basename chmod date dirname grep mkdir mktemp python3 rm scp sed sha256sum sleep ssh stat tee timeout; do
  command -v "$required_command" >/dev/null 2>&1 || {
    printf 'script_114_v1_1_query_routing=blocked;reason=local_command_missing\n' >&2
    exit 2
  }
done

mkdir -p -- "$REPORT_ROOT"
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" ]] || {
  printf 'script_114_v1_1_query_routing=blocked;reason=report_directory_unsafe\n' >&2
  exit 2
}
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/v1_1_query_routing_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-script-114.XXXXXX)"
remote_root=''
remote_created=false
master_started=false
artifact_committed=false
artifact_path=''
checksum_path=''
ssh_args=()

emit() {
  printf '%s\n' "$1" | tee -a "$report_path"
}
run_with_heartbeat() {
  local stage="$1" started_at now elapsed next_heartbeat command_status
  shift
  started_at="$(date +%s)"
  next_heartbeat=20
  "$@" &
  local command_pid="$!"
  while kill -0 "$command_pid" 2>/dev/null; do
    sleep 1
    if kill -0 "$command_pid" 2>/dev/null; then
      now="$(date +%s)"
      elapsed="$((now - started_at))"
      if (( elapsed >= next_heartbeat )); then
        emit "milestone=$stage;state=running;elapsed_seconds=$elapsed"
        next_heartbeat="$((next_heartbeat + 20))"
      fi
    fi
  done
  wait "$command_pid"
  command_status="$?"
  return "$command_status"
}
block() {
  emit "script_114_v1_1_query_routing=blocked;reason=$1;local_report=$report_path"
  exit 1
}
cleanup() {
  local status="$?" remote_cleanup_code=0 master_close_code=0
  trap - EXIT INT TERM
  set +e
  if [[ "$remote_created" == true && "$master_started" == true ]]; then
    timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
      "rm -rf -- '$remote_root' && test ! -e '$remote_root'" >/dev/null 2>&1 || remote_cleanup_code=$?
    if (( remote_cleanup_code == 0 )); then
      emit 'cleanup_remote_temporary_files=removed'
    else
      emit "cleanup_remote_temporary_files=review_required;exit_code=$remote_cleanup_code"
      status=1
    fi
  fi
  if [[ "$master_started" == true ]]; then
    timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1 || master_close_code=$?
    emit "cleanup_ssh_master_exit_code=$master_close_code"
    (( master_close_code == 0 )) || status=1
  fi
  if [[ "$artifact_committed" != true ]]; then
    [[ "$artifact_path" == "$ARTIFACT_ROOT"/request_stage_diagnostics_*.json ]] && rm -f -- "$artifact_path"
    [[ "$checksum_path" == "$ARTIFACT_ROOT"/request_stage_diagnostics_*.json.sha256 ]] && rm -f -- "$checksum_path"
  fi
  [[ "$work_root" == /tmp/ishikawa-script-114.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  chmod 0600 "$report_path" 2>/dev/null || true
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

emit 'purpose=qualify_isolated_ishikawa_v1_1_query_routing_and_diagnose_retained_v1_failures'
emit "started_utc=$timestamp"
emit "local_report=$report_path"
emit "selected_target=$target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version"
emit 'authorized_actions=validate_local_v1_1_source_run_local_tests_read_existing_content_free_target_logs_return_content_free_diagnostic_remove_target_temporary_files'
emit 'non_actions=no_sudo_no_package_rebuild_no_install_no_stack_start_or_stop_no_configuration_change_no_database_write_no_service_change_no_model_call_no_port_forwarding_change_no_credential_read'
emit 'operator_expectation=ssh_key_passphrase_if_prompted;sudo_prompt=false;estimated_duration_minutes=1-3'

readonly -a REQUIRED_FILES=(
  "$TEST_RUNNER" "$INSPECTOR" "$V1_CASES" "$V1_1_CASES"
  "$CHECKPOINT_REPORT" "$CHECKPOINT_ARTIFACT" "$CHECKPOINT_CHECKSUM"
  "$BASELINE_ARTIFACT" "${ROUTING_SOURCES[@]}"
)
for required_file in "${REQUIRED_FILES[@]}"; do
  [[ -f "$required_file" && ! -L "$required_file" && -r "$required_file" ]] || block 'required_input_unsafe'
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || block "$3"'_identity_changed'
}
emit 'milestone=immutable_v1_checkpoint;state=start'
check_sha256 "$CHECKPOINT_REPORT" "$CHECKPOINT_REPORT_SHA256" checkpoint_report
check_sha256 "$CHECKPOINT_ARTIFACT" "$CHECKPOINT_ARTIFACT_SHA256" checkpoint_artifact
check_sha256 "$CHECKPOINT_CHECKSUM" "$CHECKPOINT_CHECKSUM_SHA256" checkpoint_checksum
check_sha256 "$BASELINE_ARTIFACT" "$BASELINE_ARTIFACT_SHA256" baseline_artifact
(
  cd -- "$(dirname -- "$CHECKPOINT_CHECKSUM")"
  sha256sum --check --strict "$(basename -- "$CHECKPOINT_CHECKSUM")" >/dev/null
) || block 'checkpoint_checksum_failed'
for checkpoint_fact in \
  'release_name=Ishikawa_v1;release_state=immutable;successor_release=Ishikawa_v1.1' \
  'package_rebuilt=false;package_duplicated=false;tuning_code_applied=false' \
  'script_113_v1_fallback_checkpoint=pass;'; do
  grep -Fq "$checkpoint_fact" "$CHECKPOINT_REPORT" || block 'checkpoint_contract_failed'
done
emit "milestone=immutable_v1_checkpoint;state=pass;v1_archive_sha256=$V1_ARCHIVE_SHA256;runtime_changed=false"

emit 'milestone=v1_1_source_contract;state=start'
bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(pathlib.Path(path).read_text(encoding="utf-8"), path, "exec") for path in sys.argv[1:]]' \
  "$INSPECTOR" "${ROUTING_SOURCES[@]}"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$INSPECTOR" --self-test \
  | grep -Fxq 'request_stage_history_self_test=pass' || block 'inspector_self_test_failed'

case_contract="$work_root/case-contract.txt"
PYTHONDONTWRITEBYTECODE=1 python3 -B - "$V1_CASES" "$V1_1_CASES" >"$case_contract" <<'PY'
import json
import pathlib
import sys

v1 = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
v1_1 = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
assert v1["artifact_kind"] == v1_1["artifact_kind"] == "ishikawa_retrieval_tuning_cases"
assert v1["schema_version"] == 1 and v1_1["schema_version"] == 2
assert v1["synthetic_content_only"] is True and v1_1["synthetic_content_only"] is True
assert len(v1["cases"]) == len(v1_1["cases"]) == 13
before = {item["case_id"]: item for item in v1["cases"]}
after = {item["case_id"]: item for item in v1_1["cases"]}
assert set(before) == set(after)
changes = []
for case_id in sorted(before):
    old = before[case_id]
    new = after[case_id]
    if old != new:
        changes.append((case_id, old, new))
assert len(changes) == 1 and changes[0][0] == "B-001"
old = changes[0][1]
new = changes[0][2]
assert old["expected_status"] == "answered"
assert new["expected_status"] == "clarification-required"
for key in ("case_id", "class", "question", "required_evidence"):
    assert old[key] == new[key]
print("v1_1_case_contract=pass;cases=13;changed_expectations=1;changed_case=B-001")
PY
grep -Fxq 'v1_1_case_contract=pass;cases=13;changed_expectations=1;changed_case=B-001' "$case_contract" \
  || block 'v1_1_case_contract_failed'

routing_identity="$({
  PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B - <<'PY'
from ishikawa.query_routing import KNOWN_DOCUMENT_ROUTING_IDENTITY
print(KNOWN_DOCUMENT_ROUTING_IDENTITY)
PY
} 2>/dev/null)"
[[ "$routing_identity" =~ ^[0-9a-f]{64}$ ]] || block 'routing_identity_invalid'
emit "milestone=v1_1_source_contract;state=pass;routing_identity=$routing_identity;cases=13;changed_case=B-001"

emit 'milestone=local_regression;state=start'
test_result="$work_root/local-tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  emit "local_test_diagnostic_sha256=$(sha256sum "$test_result" | awk '{print $1}');local_test_diagnostic_bytes=$(stat -c '%s' "$test_result")"
  block 'local_test_regression'
}
grep -Fq 'Ran 367 tests' "$test_result" || block 'local_test_count_mismatch'
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || block 'local_test_pass_marker_absent'
emit 'milestone=local_regression;state=pass;tests=367;failures=0;errors=0'

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
inspector_sha256="$(sha256sum "$INSPECTOR" | awk '{print $1}')"
v1_1_cases_sha256="$(sha256sum "$V1_1_CASES" | awk '{print $1}')"
source_manifest_sha256="$({ sha256sum "${ROUTING_SOURCES[@]}"; } | sha256sum | awk '{print $1}')"
request_id_file="$work_root/request-identities.txt"
PYTHONDONTWRITEBYTECODE=1 python3 -B - "$BASELINE_ARTIFACT" >"$request_id_file" <<'PY'
import json
import pathlib
import sys

artifact = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
selected = {}
for observation in artifact["cases"]:
    case_id = observation["case"]["case_id"]
    if case_id in {"R-001", "R-003"}:
        assert observation["metrics"]["status"] == "temporarily-unavailable"
        selected[case_id] = observation["response"]["request_id"]
assert set(selected) == {"R-001", "R-003"}
assert all(len(value) == 64 and set(value) <= set("0123456789abcdef") for value in selected.values())
for case_id in ("R-001", "R-003"):
    print(f"{case_id}={selected[case_id]}")
PY
mapfile -t request_identities <"$request_id_file"
[[ "${#request_identities[@]}" == 2 ]] || block 'baseline_request_identity_invalid'

if [[ "$validate_only" == true ]]; then
  emit "script_sha256=$script_sha256;inspector_sha256=$inspector_sha256;v1_1_case_file_sha256=$v1_1_cases_sha256;source_manifest_sha256=$source_manifest_sha256"
  emit 'target_contact=false;runtime_changed=false;database_changed=false;service_changed=false;model_contact=false;accepted_v1_changed=false'
  emit "script_114_v1_1_query_routing_source=pass;tests=367;next_gate=operator_run_read_only_diagnostic;local_report=$report_path"
  exit 0
fi

emit 'milestone=authentication;state=waiting_for_operator_if_prompted'
control_path="$work_root/cm-%C"
ssh_args=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto -o "ControlPath=$control_path" -o ControlPersist=900)
if [[ -n "$identity_file" ]]; then
  ssh_args+=(-i "$identity_file" -o IdentitiesOnly=yes)
fi
timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$target" >/dev/null 2>&1 || block 'ssh_master_start_failed'
master_started=true
emit 'milestone=authentication;state=pass'

remote_root="/tmp/ishikawa-request-diagnostics-$timestamp-$$"
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" >/dev/null \
  || block 'remote_temporary_directory_not_created'
remote_created=true

emit 'milestone=diagnostic_payload_transfer;state=start;files=1'
timeout --foreground 120 scp "${ssh_args[@]}" "$INSPECTOR" "$target:$remote_root/inspect-request-stage-history.py" >/dev/null \
  || block 'diagnostic_payload_transfer_failed'
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && printf '%s  %s\n' '$inspector_sha256' 'inspect-request-stage-history.py' | sha256sum --check --strict - >/dev/null" >/dev/null \
  || block 'transferred_inspector_checksum_failed'
emit "milestone=diagnostic_payload_transfer;state=pass;files=1;transferred_bytes=$(stat -c '%s' "$INSPECTOR")"

emit 'milestone=content_free_log_inspection;state=start'
set +e
run_with_heartbeat content_free_log_inspection timeout --foreground 180 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && umask 077 && PYTHONDONTWRITEBYTECODE=1 python3 -B ./inspect-request-stage-history.py --inspect --product-root \"\$HOME/Documents/Ishikawa\" --expected-hostname '$expected_hostname' --expected-os-version '$expected_os_version' --case '${request_identities[0]}' --case '${request_identities[1]}' --output '$remote_root/request-stage-diagnostics.json' > '$remote_root/inspection-result.txt' 2>&1"
remote_code=$?
set -e

inspection_result="$work_root/inspection-result.txt"
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/inspection-result.txt" "$inspection_result" >/dev/null \
  || block 'inspection_result_fetch_failed'
inspection_output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 512 )) || [[ "$line" == *$'\t'* ]] \
    || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then
    inspection_output_contract=blocked
  fi
done <"$inspection_result"
if (( remote_code != 0 )); then
  if [[ "$inspection_output_contract" == pass ]]; then
    while IFS= read -r line; do
      emit "$line"
    done <"$inspection_result"
  fi
  emit "inspection_result_sha256=$(sha256sum "$inspection_result" | awk '{print $1}');inspection_result_bytes=$(stat -c '%s' "$inspection_result");remote_exit_code=$remote_code"
  block 'content_free_log_inspection_failed'
fi
[[ "$inspection_output_contract" == pass ]] || block 'inspection_output_contract_failed'
grep -Fxq 'request_diagnostics=pass;cases=2;raw_content_retained=false' "$inspection_result" \
  || block 'inspection_pass_marker_absent'

fetched_diagnostic="$work_root/request-stage-diagnostics.json"
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/request-stage-diagnostics.json" "$fetched_diagnostic" >/dev/null \
  || block 'diagnostic_fetch_failed'
diagnostic_contract="$work_root/diagnostic-contract.txt"
PYTHONDONTWRITEBYTECODE=1 python3 -B - "$fetched_diagnostic" "$expected_hostname" "${request_identities[@]}" >"$diagnostic_contract" <<'PY'
import json
import pathlib
import sys

artifact = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
expected_hostname = sys.argv[2]
expected = dict(value.split("=", 1) for value in sys.argv[3:])
assert artifact["artifact_kind"] == "ishikawa_content_free_request_diagnostics"
assert artifact["schema_version"] == 1
assert artifact["raw_content_retained"] is False
assert artifact["target"]["hostname"] == expected_hostname
assert artifact["target"]["architecture"] == "x86_64"
assert len(artifact["cases"]) == 2
observed = {item["case_id"]: item for item in artifact["cases"]}
assert set(observed) == set(expected)
for case_id, item in observed.items():
    assert item["request_id"] == expected[case_id]
    assert item["http_status"] == 200
    assert item["outcome"] == "temporarily-unavailable"
    assert item["failure_boundary"] != "unresolved-stage"
    assert item["stage_trace"][-1] == "dependency-unavailable"
print("request_stage_diagnostic_contract=pass;cases=2;raw_content_retained=false")
PY
grep -Fxq 'request_stage_diagnostic_contract=pass;cases=2;raw_content_retained=false' "$diagnostic_contract" \
  || block 'diagnostic_contract_failed'
emit 'milestone=content_free_log_inspection;state=pass;cases=2;raw_content_retained=false'

mkdir -p -- "$ARTIFACT_ROOT"
[[ -d "$ARTIFACT_ROOT" && ! -L "$ARTIFACT_ROOT" ]] || block 'artifact_directory_unsafe'
artifact_path="$ARTIFACT_ROOT/request_stage_diagnostics_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] \
  || block 'artifact_path_exists'
cp -- "$fetched_diagnostic" "$artifact_path"
artifact_sha256="$(sha256sum "$artifact_path" | awk '{print $1}')"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true
(
  cd -- "$ARTIFACT_ROOT"
  sha256sum --check --strict "$(basename -- "$checksum_path")" >/dev/null
) || block 'retained_diagnostic_checksum_failed'
artifact_committed=true

while IFS= read -r line; do
  emit "$line"
done <"$inspection_result"

emit 'milestone=target_cleanup;state=start'
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "rm -rf -- '$remote_root' && test ! -e '$remote_root'" >/dev/null 2>&1 \
  || block 'remote_temporary_cleanup_failed'
remote_created=false
emit 'milestone=target_cleanup;state=pass;remote_temporary_files=removed'
timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1 \
  || block 'ssh_master_close_failed'
master_started=false
emit 'cleanup_ssh_master_exit_code=0'

emit "script_sha256=$script_sha256;inspector_sha256=$inspector_sha256;v1_1_case_file_sha256=$v1_1_cases_sha256;source_manifest_sha256=$source_manifest_sha256"
emit "checkpoint_artifact_sha256=$CHECKPOINT_ARTIFACT_SHA256;v1_archive_sha256=$V1_ARCHIVE_SHA256;routing_identity=$routing_identity"
emit "diagnostic_artifact=$artifact_path;diagnostic_artifact_sha256=$artifact_sha256;diagnostic_checksum=$checksum_path"
emit 'runtime_changed=false;database_changed=false;service_changed=false;model_contact=false;accepted_v1_changed=false'
emit "script_114_v1_1_query_routing=pass;tests=367;next_gate=assemble_and_install_v1_1_candidate;local_report=$report_path"
