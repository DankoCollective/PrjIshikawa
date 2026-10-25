#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Run the neutral embedding-service verifier on one approved remote model
#   host and return its content-free result in this script's local report.
#
# Control flow:
#   Validate the carried bundle locally, create the report first, reuse one
#   attended SSH connection, stage the verified bundle under target /tmp,
#   execute it through sudo, retrieve and validate the result, and remove the
#   target payload automatically.
#
# Side effects:
#   May temporarily start the managed Nomic service when it was initially
#   inactive. The target verifier restores that inactive state on exit. This
#   wrapper creates and removes one user-owned target /tmp directory. It does
#   not install packages, change configuration, alter boot state, copy a
#   credential, or retain prompts, responses, chunks, vectors, or API keys.
#
# Usage from the repository root when local/site_values.env defines the
# DANKO_00_* connection values:
#   bash ./phase-28-apisachi-tokuli/scripts/01_run_embedding_service_verification.sh
#
# Explicit portable usage:
#   bash ./01_run_embedding_service_verification.sh \
#     --target USER@HOST --identity-file /absolute/key/path \
#     --expected-hostname HOSTNAME \
#     --bundle /absolute/embedding-service-verification.tar.gz \
#     --checksum /absolute/embedding-service-verification.tar.gz.sha256 \
#     --report-root /absolute/local/result/directory

usage() {
  sed -n '3,34p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --target USER@HOST           Approved SSH destination.' \
    '  --identity-file PATH         Function-specific SSH private key.' \
    '  --expected-hostname NAME     Exact target hostname.' \
    '  --bundle PATH                Neutral verifier bundle.' \
    '  --checksum PATH              SHA-256 sidecar for the bundle.' \
    '  --report-root PATH           Local result directory; created by this script.' \
    '  --validate-only              Validate local inputs without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly BUNDLE_DEFAULT="$REPO_ROOT/local/artifacts/embedding-service-verification/embedding-service-verification.tar.gz"
readonly CHECKSUM_DEFAULT="$BUNDLE_DEFAULT.sha256"
readonly REPORT_ROOT_DEFAULT="$REPO_ROOT/local/reports/embedding-service-verification"

target=""
identity_file=""
expected_hostname=""
bundle="$BUNDLE_DEFAULT"
checksum="$CHECKSUM_DEFAULT"
report_root="$REPORT_ROOT_DEFAULT"
validate_only=false

while (( $# > 0 )); do
  case "$1" in
    --target) target="${2:-}"; shift 2 ;;
    --identity-file) identity_file="${2:-}"; shift 2 ;;
    --expected-hostname) expected_hostname="${2:-}"; shift 2 ;;
    --bundle) bundle="${2:-}"; shift 2 ;;
    --checksum) checksum="${2:-}"; shift 2 ;;
    --report-root) report_root="${2:-}"; shift 2 ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'ERROR: unsupported argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

report_path=""
work_root=""
remote_root=""
remote_root_created=false
master_owned=false
failure_count=0
ssh_args=()

emit() {
  printf '%s\n' "$1" | tee -a "$report_path"
}

block() {
  failure_count=$((failure_count + 1))
  emit "verification_block=$1"
}

classify_transport_failure() {
  local step="$1" exit_code="$2" stderr_path="$3"
  local classification="unclassified_transport_failure"
  if grep -Eiq 'host key verification failed|remote host identification has changed' "$stderr_path"; then
    classification="host_key_rejected"
  elif grep -Eiq 'permission denied.*publickey' "$stderr_path"; then
    classification="public_key_authentication_rejected"
  elif grep -Eiq 'connection timed out|operation timed out' "$stderr_path"; then
    classification="connection_timeout"
  elif grep -Eiq 'connection refused' "$stderr_path"; then
    classification="connection_refused"
  elif grep -Eiq 'no route to host|network is unreachable' "$stderr_path"; then
    classification="network_unreachable"
  elif grep -Eiq 'could not resolve hostname' "$stderr_path"; then
    classification="name_resolution_failed"
  elif (( exit_code == 124 )); then
    classification="timeout"
  fi
  emit "transport_step=$step;exit_code=$exit_code;classification=$classification;raw_stderr_retained=false"
}

cleanup() {
  local original_status="$?" cleanup_code=0 close_code=0 local_cleanup="not_required"
  trap - EXIT INT TERM
  set +e

  if [[ "$remote_root_created" == true && "$master_owned" == true ]]; then
    timeout --foreground 30 ssh "${ssh_args[@]}" "$target" \
      "rm -rf -- '$remote_root'" >/dev/null 2>&1 || cleanup_code=$?
    if (( cleanup_code == 0 )); then
      emit "cleanup_remote_payload=removed"
      remote_root_created=false
    else
      emit "cleanup_remote_payload=review_required;exit_code=$cleanup_code"
      original_status=1
    fi
  else
    emit "cleanup_remote_payload=not_required"
  fi

  if [[ "$master_owned" == true ]]; then
    timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" \
      >/dev/null 2>&1 || close_code=$?
    emit "cleanup_ssh_master_exit_code=$close_code"
    (( close_code == 0 )) || original_status=1
    master_owned=false
  else
    emit "cleanup_ssh_master=not_required"
  fi

  if [[ -n "$work_root" && "$work_root" == /tmp/embedding-verification-run.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
    local_cleanup="removed"
  fi
  emit "cleanup_local_temporary_work=$local_cleanup"

  if (( original_status == 0 && failure_count == 0 )); then
    emit "failure_count=0"
    emit "embedding_service_verification_wrapper=pass;local_report=$report_path;next_gate=review_local_report"
    exit 0
  fi
  (( failure_count > 0 )) || failure_count=1
  emit "failure_count=$failure_count"
  emit "embedding_service_verification_wrapper=blocked;local_report=$report_path;next_gate=review_local_report"
  exit 1
}

validate_bundle_members() {
  local archive="$1"
  python3 -B - "$archive" <<'PY'
import pathlib
import sys
import tarfile

archive = pathlib.Path(sys.argv[1])
expected = ["verify-embedding-service", "verify_embedding_service.py"]
with tarfile.open(archive, "r:gz") as stream:
    members = stream.getmembers()
if sorted(member.name for member in members) != sorted(expected):
    raise SystemExit(1)
if len(members) != len(expected) or len({member.name for member in members}) != len(expected):
    raise SystemExit(1)
for member in members:
    path = pathlib.PurePosixPath(member.name)
    if path.is_absolute() or ".." in path.parts or not member.isfile():
        raise SystemExit(1)
    if member.size <= 0 or member.size > 2 * 1024 * 1024:
        raise SystemExit(1)
PY
}

heartbeat() {
  local stage="$1" started_epoch="$2" current_epoch elapsed
  while sleep 30; do
    current_epoch="$(date +%s)"
    elapsed=$((current_epoch - started_epoch))
    emit "milestone=$stage;state=running;elapsed_seconds=$elapsed"
  done
}

main() {
  [[ "$report_root" == /* ]] \
    || { printf 'BLOCKED: --report-root must be an absolute local path.\n' >&2; return 2; }
  [[ ! -L "$report_root" ]] \
    || { printf 'BLOCKED: --report-root cannot be a symbolic link.\n' >&2; return 2; }

  local timestamp report_probe
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p -- "$report_root"
  report_probe="$(mktemp "$report_root/.embedding-verification-write-probe.XXXXXX")"
  printf 'probe\n' >"$report_probe"
  rm -f -- "$report_probe"
  report_path="$(mktemp "$report_root/embedding_service_verification_${timestamp}_XXXXXX.txt")"
  work_root="$(mktemp -d /tmp/embedding-verification-run.XXXXXX)"
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  emit "purpose=verify_remote_embedding_service_and_return_content_free_result"
  emit "started_utc=$timestamp"
  emit "local_report=$report_path"
  emit "milestone=local_validation;state=start"
  emit "authorized_actions=stage_and_remove_one_target_tmp_payload_read_runtime_and_artifact_identity_send_bounded_synthetic_embedding_requests_temporarily_start_and_restore_nomic_if_initially_inactive"
  emit "non_actions=no_package_install_no_configuration_change_no_boot_state_change_no_credential_copy_no_raw_prompt_response_chunk_vector_or_key_retention"
  emit "operator_expectation=approximately_3_to_15_minutes;ssh_key_passphrase_up_to_once;target_sudo_password_up_to_once;nomic_api_key_prompt=exactly_once;target_mutation=temporary_service_state_only_when_initially_inactive"

  local site_values_path="$REPO_ROOT/local/site_values.env"
  local -a selected_site_values=("" "" "" "")
  if [[ -f "$site_values_path" && -z "$target" && -z "$identity_file" && -z "$expected_hostname" ]]; then
    mapfile -d '' -t selected_site_values < <(python3 -B - "$site_values_path" <<'PY'
import os
import re
import sys

path = sys.argv[1]
wanted = {
    "LOCAL_RUNTIME_USER",
    "DANKO_00_SSH_ADDRESS",
    "DANKO_00_RESERVED_LAN_IP",
    "TARGET_RESERVED_LAN_IP",
    "DANKO_00_TARGET",
    "DANKO_00_SSH_KEY",
    "DANKO_00_IDENTITY_FILE",
    "DANKOSURFACE_TO_00DANKO_IDENTITY_FILE",
    "DANKO_00_EXPECTED_HOSTNAME",
    "TARGET_STABLE_LAN_NAME",
}
values = {}
assignment = re.compile(r"^([A-Z][A-Z0-9_]*)=(.*)$")
with open(path, "r", encoding="utf-8") as stream:
    for raw_line in stream:
        line = raw_line.rstrip("\n")
        match = assignment.fullmatch(line)
        if not match or match.group(1) not in wanted:
            continue
        key, value = match.groups()
        if key in values or "\x00" in value or "\r" in value:
            raise SystemExit(1)
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        if value.startswith("${HOME}/"):
            value = os.path.join(os.environ["HOME"], value[len("${HOME}/"):])
        elif value.startswith("$HOME/"):
            value = os.path.join(os.environ["HOME"], value[len("$HOME/"):])
        values[key] = value
user = values.get("LOCAL_RUNTIME_USER", "danko")
address = (
    values.get("DANKO_00_SSH_ADDRESS")
    or values.get("DANKO_00_RESERVED_LAN_IP")
    or values.get("TARGET_RESERVED_LAN_IP", "")
)
target = values.get("DANKO_00_TARGET", "")
identity = (
    values.get("DANKO_00_SSH_KEY")
    or values.get("DANKO_00_IDENTITY_FILE")
    or values.get("DANKOSURFACE_TO_00DANKO_IDENTITY_FILE", "")
)
hostname = (
    values.get("DANKO_00_EXPECTED_HOSTNAME")
    or values.get("TARGET_STABLE_LAN_NAME", "")
)
for value in (user, address, target, identity, hostname):
    if "\n" in value or "\r" in value:
        raise SystemExit(1)
resolved_target = target or (f"{user}@{address}" if address else "")
for value in (resolved_target, identity, hostname, "selected_nonsecret_fields_only"):
    sys.stdout.buffer.write(value.encode("utf-8") + b"\0")
PY
    )
    if (( ${#selected_site_values[@]} != 4 )); then
      block "selected_site_value_parsing_failed"
      return 1
    fi
    emit "local_site_values=selected_nonsecret_fields_only;values_printed=false"
  else
    emit "local_site_values=not_read_or_explicit_connection_arguments_used"
  fi
  target="${target:-${selected_site_values[0]:-}}"
  identity_file="${identity_file:-${selected_site_values[1]:-}}"
  expected_hostname="${expected_hostname:-${selected_site_values[2]:-}}"
  if [[ -z "$target" && -n "$inferred_address" ]]; then
    target="$inferred_user@$inferred_address"
  fi
  identity_file="${identity_file:-${DANKO_00_SSH_KEY:-${DANKO_00_IDENTITY_FILE:-${DANKOSURFACE_TO_00DANKO_IDENTITY_FILE:-}}}}"
  expected_hostname="${expected_hostname:-${DANKO_00_EXPECTED_HOSTNAME:-${TARGET_STABLE_LAN_NAME:-}}}"

  local required_command
  for required_command in bash basename cmp date grep mkdir mktemp python3 rm scp sha256sum ssh tar tee timeout tr wc; do
    command -v "$required_command" >/dev/null 2>&1 || block "local_tool_missing:$required_command"
  done
  [[ -f "$bundle" && ! -L "$bundle" && -r "$bundle" ]] \
    || block "bundle_missing_unreadable_or_symlinked"
  [[ -f "$checksum" && ! -L "$checksum" && -r "$checksum" ]] \
    || block "checksum_missing_unreadable_or_symlinked"
  if (( failure_count > 0 )); then return 1; fi

  local expected_hash checksum_name checksum_extra actual_hash bundle_bytes
  read -r expected_hash checksum_name checksum_extra <"$checksum" || true
  if [[ ! "$expected_hash" =~ ^[0-9a-f]{64}$ \
      || "$checksum_name" != "$(basename -- "$bundle")" \
      || -n "${checksum_extra:-}" ]]; then
    block "checksum_sidecar_format_or_name_invalid"
    return 1
  fi
  actual_hash="$(sha256sum "$bundle")"; actual_hash="${actual_hash%% *}"
  [[ "$actual_hash" == "$expected_hash" ]] || block "bundle_checksum_mismatch"
  validate_bundle_members "$bundle" || block "bundle_member_validation_failed"
  if (( failure_count > 0 )); then return 1; fi

  local extracted="$work_root/extracted" syntax_code=0 self_test_code=0
  mkdir -m 0700 -- "$extracted"
  tar -xzf "$bundle" --touch --no-same-owner --no-same-permissions -C "$extracted"
  bash -n "$extracted/verify-embedding-service" \
    >"$work_root/shell-syntax.stdout" 2>"$work_root/shell-syntax.stderr" || syntax_code=$?
  PYTHONDONTWRITEBYTECODE=1 python3 -B "$extracted/verify_embedding_service.py" --self-test \
    >"$work_root/self-test.stdout" 2>"$work_root/self-test.stderr" || self_test_code=$?
  emit "local_shell_syntax_exit_code=$syntax_code"
  emit "local_python_self_test_exit_code=$self_test_code"
  if (( syntax_code != 0 || self_test_code != 0 )); then
    block "local_bundle_source_validation_failed"
    return 1
  fi
  if grep -RIEq 'phase[-_ ]?[0-9]+|(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)|Danko|org[_ -]?lab|AgentDanko|systemd-creds|encrypted-credential' "$extracted"; then
    block "repository_or_lab_jargon_found_in_target_payload"
    return 1
  fi
  bundle_bytes="$(wc -c <"$bundle")"
  emit "bundle_sha256=$actual_hash;bundle_bytes=$bundle_bytes;payload_members=2;secret_bytes_transferred=0"
  emit "milestone=local_validation;state=pass"

  if [[ "$validate_only" == true ]]; then
    emit "target_contact=false"
    emit "milestone=validation_only;state=pass"
    return 0
  fi

  [[ "$target" =~ ^[A-Za-z_][A-Za-z0-9_-]*@[A-Za-z0-9][A-Za-z0-9.-]*$ ]] \
    || block "invalid_or_missing_target"
  [[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] \
    || block "invalid_or_missing_expected_hostname"
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] \
    || block "identity_file_missing_unreadable_nonabsolute_or_symlinked"
  if (( failure_count > 0 )); then return 1; fi

  remote_root="/tmp/embedding-service-verification-$timestamp-$$"
  ssh_args=(
    -i "$identity_file" -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes
    -o ConnectTimeout=10 -o ConnectionAttempts=1
    -o ServerAliveInterval=30 -o ServerAliveCountMax=20
    -o ControlMaster=auto -o ControlPath="/tmp/embed-verify-$timestamp-%C"
    -o ControlPersist=300
  )
  emit "selected_target=$target;expected_hostname=$expected_hostname;identity_label=$(basename -- "$identity_file")"
  emit "remote_payload_root=$remote_root;retention=removed_by_wrapper"
  emit "milestone=authentication;state=waiting_for_operator_if_prompted"

  local exit_code=0
  timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$target" \
    >"$work_root/master.stdout" 2>"$work_root/master.stderr" || exit_code=$?
  emit "ssh_master_start_exit_code=$exit_code"
  if (( exit_code != 0 )); then
    classify_transport_failure ssh_master_start "$exit_code" "$work_root/master.stderr"
    block "ssh_master_start_failed"
    return 1
  fi
  master_owned=true
  emit "milestone=authentication;state=pass"

  exit_code=0
  timeout --foreground 30 ssh "${ssh_args[@]}" "$target" hostname \
    >"$work_root/hostname.stdout" 2>"$work_root/hostname.stderr" || exit_code=$?
  emit "hostname_probe_exit_code=$exit_code"
  if (( exit_code != 0 )); then
    classify_transport_failure hostname_probe "$exit_code" "$work_root/hostname.stderr"
    block "hostname_probe_failed"
  elif [[ "$(tr -d '\r\n' <"$work_root/hostname.stdout")" != "$expected_hostname" ]]; then
    block "target_hostname_mismatch"
  else
    emit "target_hostname=$expected_hostname"
  fi
  if (( failure_count > 0 )); then return 1; fi

  emit "milestone=target_staging;state=start"
  exit_code=0
  timeout --foreground 30 ssh "${ssh_args[@]}" "$target" \
    "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" \
    >"$work_root/remote-root.stdout" 2>"$work_root/remote-root.stderr" || exit_code=$?
  emit "remote_payload_root_create_exit_code=$exit_code"
  if (( exit_code != 0 )); then
    classify_transport_failure remote_payload_root_create "$exit_code" "$work_root/remote-root.stderr"
    block "remote_payload_root_not_created_from_absent_state"
    return 1
  fi
  remote_root_created=true

  exit_code=0
  timeout --foreground 60 scp "${ssh_args[@]}" "$bundle" \
    "$target:$remote_root/embedding-service-verification.tar.gz" \
    >"$work_root/scp-stage.stdout" 2>"$work_root/scp-stage.stderr" || exit_code=$?
  emit "payload_copy_exit_code=$exit_code"
  if (( exit_code != 0 )); then
    classify_transport_failure payload_copy "$exit_code" "$work_root/scp-stage.stderr"
    block "payload_copy_failed"
    return 1
  fi

  exit_code=0
  timeout --foreground 30 ssh "${ssh_args[@]}" "$target" \
    "cd '$remote_root' && printf '%s  %s\\n' '$actual_hash' embedding-service-verification.tar.gz | sha256sum --check --strict - && tar -xzf embedding-service-verification.tar.gz --no-same-owner --no-same-permissions && test -f verify-embedding-service && test -f verify_embedding_service.py" \
    >"$work_root/target-prepare.stdout" 2>"$work_root/target-prepare.stderr" || exit_code=$?
  emit "target_payload_prepare_exit_code=$exit_code"
  if (( exit_code != 0 )); then
    classify_transport_failure target_payload_prepare "$exit_code" "$work_root/target-prepare.stderr"
    block "target_payload_hash_or_extraction_failed"
    return 1
  fi
  emit "target_payload_hash_verification=pass"
  emit "milestone=target_staging;state=pass;newly_transferred_bytes=$bundle_bytes"

  emit "milestone=target_verification;state=start"
  local heartbeat_pid="" started_epoch
  started_epoch="$(date +%s)"
  heartbeat target_verification "$started_epoch" &
  heartbeat_pid=$!
  set +e
  timeout --foreground 1800 ssh "${ssh_args[@]}" -tt "$target" \
    "cd '$remote_root' && umask 077 && bash -o pipefail -c 'sudo bash ./verify-embedding-service 2>&1 | tee ./verification-result.txt'" \
    2>"$work_root/remote.stderr" | tee "$work_root/remote.raw" -a "$report_path"
  local pipeline_status=("${PIPESTATUS[@]}")
  set -e
  kill "$heartbeat_pid" >/dev/null 2>&1 || true
  wait "$heartbeat_pid" >/dev/null 2>&1 || true
  exit_code="${pipeline_status[0]}"
  local tee_code="${pipeline_status[1]}" normalize_code=0
  tr -d '\r' <"$work_root/remote.raw" >"$work_root/remote.stdout" || normalize_code=$?
  emit "remote_execution_exit_code=$exit_code;normalizer_exit_code=$normalize_code;report_tee_exit_code=$tee_code"
  if (( normalize_code != 0 || tee_code != 0 )); then
    block "remote_output_or_report_capture_failed"
  fi

  local fetched_result="$work_root/verification-result.txt"
  local fetch_code=0
  timeout --foreground 60 scp "${ssh_args[@]}" \
    "$target:$remote_root/verification-result.txt" "$fetched_result" \
    >"$work_root/scp-fetch.stdout" 2>"$work_root/scp-fetch.stderr" || fetch_code=$?
  emit "result_fetch_exit_code=$fetch_code"
  if (( fetch_code != 0 )); then
    classify_transport_failure result_fetch "$fetch_code" "$work_root/scp-fetch.stderr"
    block "verification_result_fetch_failed"
  else
    tr -d '\r' <"$fetched_result" >"$work_root/verification-result.normalized"
    if grep -Evq '^\[embedding-verification\] [A-Za-z0-9_.:/=@+,-]+( [A-Za-z0-9_.:/=@+,-]+)*$' \
        "$work_root/verification-result.normalized"; then
      block "verification_result_contains_unstructured_output"
    fi
    local result_counts
    result_counts="$(awk '
      /\[embedding-verification\] result=PASS disposition=embedding_tuple_and_adapter_compatible / { pass++ }
      /\[embedding-verification\] result=BLOCKED / { blocked++ }
      /\[embedding-verification\] cleanup=(pass|not_required) / { cleanup++ }
      /\[embedding-verification\] credential_source=operator_attended_tty stored_credential_read=false/ { attended++ }
      END { printf "%d %d %d %d", pass+0, blocked+0, cleanup+0, attended+0 }
    ' "$work_root/verification-result.normalized")"
    local pass_count blocked_count cleanup_count attended_count
    read -r pass_count blocked_count cleanup_count attended_count <<<"$result_counts"
    emit "retrieved_result_pass_markers=$pass_count;blocked_markers=$blocked_count;cleanup_markers=$cleanup_count;operator_credential_markers=$attended_count"
    if (( pass_count != 1 || blocked_count != 0 || cleanup_count != 1 || attended_count != 1 )); then
      block "verification_result_acceptance_markers_invalid"
    fi
    local result_hash
    result_hash="$(sha256sum "$work_root/verification-result.normalized")"; result_hash="${result_hash%% *}"
    emit "retrieved_result_sha256=$result_hash;retained_in_local_report=true;standalone_result_retained=false"
  fi

  if (( exit_code != 0 )); then
    classify_transport_failure remote_execution "$exit_code" "$work_root/remote.stderr"
    block "remote_verification_failed"
  fi
  if (( failure_count > 0 )); then return 1; fi
  emit "milestone=target_verification;state=pass"
  emit "qualification_scope=exact_embedding_tuple_and_adapter_only;full_corpus_retrieval_qualification=not_run"
  return 0
}

main "$@"
