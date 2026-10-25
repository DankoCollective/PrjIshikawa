#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Stage one neutral read-only Docker inventory helper, run it through
#   attended sudo, retrieve its result, and remove all target temporary files.
#
# Default Danko usage from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/03_run_container_runtime_inventory.sh
#
# The operator may be prompted once for the SSH key passphrase and once for the
# target sudo password. Neither credential is read, copied, or retained by the
# script.

usage() {
  sed -n '3,15p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --target VALUE             SSH destination or configured SSH alias.' \
    '  --expected-hostname NAME   Exact target short hostname.' \
    '  --identity-file PATH       Optional explicit SSH private key.' \
    '  --report-root PATH         Absolute local result directory.' \
    '  --validate-only            Validate source without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly TARGET_HELPER="$SCRIPT_DIR/inspect-container-runtime"
readonly DEFAULT_REPORT_ROOT="$REPO_ROOT/local/reports/container-runtime-inventory"

target="${APPLICATION_HOST_TARGET:-DankoSurface_EmceeDanko}"
expected_hostname="${APPLICATION_HOST_EXPECTED_HOSTNAME:-EmceeDanko}"
identity_file="${APPLICATION_HOST_IDENTITY_FILE:-}"
report_root="$DEFAULT_REPORT_ROOT"
validate_only=false

while (( $# > 0 )); do
  case "$1" in
    --target) target="${2:-}"; shift 2 ;;
    --expected-hostname) expected_hostname="${2:-}"; shift 2 ;;
    --identity-file) identity_file="${2:-}"; shift 2 ;;
    --report-root) report_root="${2:-}"; shift 2 ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'ERROR: unsupported argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$report_root" == /* ]] || { printf 'BLOCKED: --report-root must be absolute.\n' >&2; exit 2; }
[[ ! -L "$report_root" ]] || { printf 'BLOCKED: --report-root cannot be a symbolic link.\n' >&2; exit 2; }
[[ -f "$TARGET_HELPER" && ! -L "$TARGET_HELPER" && -r "$TARGET_HELPER" ]] \
  || { printf 'BLOCKED: neutral Docker inventory helper is missing or unsafe.\n' >&2; exit 2; }
[[ "$target" =~ ^[A-Za-z0-9_@.:-]+$ ]] \
  || { printf 'BLOCKED: invalid SSH target or alias.\n' >&2; exit 2; }
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] \
  || { printf 'BLOCKED: invalid expected hostname.\n' >&2; exit 2; }
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] \
    || { printf 'BLOCKED: explicit identity file is missing, unreadable, non-absolute, or a symlink.\n' >&2; exit 2; }
fi

for required in awk bash date grep mkdir mktemp rm scp sha256sum ssh tee timeout tr wc; do
  command -v "$required" >/dev/null 2>&1 \
    || { printf 'BLOCKED: missing local command: %s\n' "$required" >&2; exit 2; }
done

bash -n "$TARGET_HELPER"
if grep -Eiq 'phase[-_ ]?[0-9]+|(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)|Danko|org[_ -]?lab|Agent|repository' "$TARGET_HELPER"; then
  printf 'BLOCKED: repository or environment jargon found in neutral target helper.\n' >&2
  exit 2
fi

helper_sha256="$(sha256sum "$TARGET_HELPER" | awk '{print $1}')"
helper_bytes="$(wc -c <"$TARGET_HELPER" | tr -d ' ')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'container_runtime_inventory_wrapper=pass' \
    'target_contact=false' \
    "helper_sha256=$helper_sha256" \
    "helper_bytes=$helper_bytes"
  exit 0
fi

mkdir -p -- "$report_root"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_root/container_runtime_inventory_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/container-runtime-inventory.XXXXXX)"
remote_root="/tmp/container-runtime-inventory-$timestamp-$$"
remote_created=false
master_started=false
ssh_args=()

emit() {
  printf '%s\n' "$1" | tee -a "$report_path"
}

cleanup() {
  local status="$?" cleanup_code=0 close_code=0
  trap - EXIT INT TERM
  set +e
  if [[ "$remote_created" == true && "$master_started" == true ]]; then
    timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
      "rm -rf -- '$remote_root'" >/dev/null 2>&1 || cleanup_code=$?
    if (( cleanup_code == 0 )); then
      emit 'cleanup_remote_temporary_files=removed'
    else
      emit "cleanup_remote_temporary_files=review_required;exit_code=$cleanup_code"
      status=1
    fi
  else
    emit 'cleanup_remote_temporary_files=not_required'
  fi
  if [[ "$master_started" == true ]]; then
    timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1 || close_code=$?
    emit "cleanup_ssh_master_exit_code=$close_code"
    (( close_code == 0 )) || status=1
  fi
  if [[ "$work_root" == /tmp/container-runtime-inventory.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

emit 'purpose=inventory_container_runtime_without_mutation'
emit "started_utc=$timestamp"
emit "helper_sha256=$helper_sha256;helper_bytes=$helper_bytes"
emit 'authorized_actions=stage_verified_temporary_helper_read_docker_runtime_and_allowlisted_image_metadata_remove_temporary_files'
emit 'non_actions=no_pull_no_build_no_load_no_run_no_stop_no_remove_no_configuration_change_no_secret_or_content_read'
emit "selected_target=$target;expected_hostname=$expected_hostname"
emit 'operator_expectation=ssh_key_passphrase_up_to_once;target_sudo_password_up_to_once'

control_path="$work_root/ssh-control"
ssh_args=(
  -o StrictHostKeyChecking=yes
  -o ConnectTimeout=10
  -o ConnectionAttempts=1
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=3
  -o ControlMaster=auto
  -o "ControlPath=$control_path"
  -o ControlPersist=300
)
if [[ -n "$identity_file" ]]; then
  ssh_args+=( -i "$identity_file" -o IdentitiesOnly=yes )
fi

emit 'milestone=authentication;state=waiting_for_operator_if_prompted'
timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$target" \
  >"$work_root/master.stdout" 2>"$work_root/master.stderr" || {
    emit 'container_runtime_inventory_wrapper=blocked;reason=ssh_master_start_failed;raw_stderr_retained=false'
    exit 1
  }
master_started=true
emit 'milestone=authentication;state=pass'

timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" \
  >"$work_root/create.stdout" 2>"$work_root/create.stderr" || {
    emit 'container_runtime_inventory_wrapper=blocked;reason=remote_temporary_directory_not_created'
    exit 1
  }
remote_created=true

timeout --foreground 60 scp "${ssh_args[@]}" "$TARGET_HELPER" \
  "$target:$remote_root/inspect-container-runtime" \
  >"$work_root/scp.stdout" 2>"$work_root/scp.stderr" || {
    emit 'container_runtime_inventory_wrapper=blocked;reason=helper_copy_failed'
    exit 1
  }

timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && printf '%s  %s\n' '$helper_sha256' inspect-container-runtime | sha256sum --check --strict -" \
  >"$work_root/hash.stdout" 2>"$work_root/hash.stderr" || {
    emit 'container_runtime_inventory_wrapper=blocked;reason=target_helper_hash_mismatch'
    exit 1
  }
emit 'milestone=target_helper_verification;state=pass'

emit 'milestone=attended_sudo_inventory;state=waiting_for_operator_if_prompted'
if [[ ! -r /dev/tty || ! -w /dev/tty ]]; then
  emit 'container_runtime_inventory_wrapper=blocked;reason=attended_terminal_unavailable'
  exit 1
fi
set +e
timeout --foreground 300 ssh "${ssh_args[@]}" -tt "$target" \
  "cd '$remote_root' && : > container-runtime-result.txt && sudo -p 'Target sudo password: ' bash ./inspect-container-runtime '$expected_hostname' > container-runtime-result.txt" \
  </dev/tty >/dev/tty 2>/dev/tty
remote_code=$?
set -e
emit "remote_execution_exit_code=$remote_code"
if (( remote_code != 0 )); then
  emit 'container_runtime_inventory_wrapper=blocked;reason=target_inventory_or_sudo_failed;raw_prompt_output_retained=false'
  exit 1
fi

fetched_result="$work_root/container-runtime-result.txt"
timeout --foreground 60 scp "${ssh_args[@]}" \
  "$target:$remote_root/container-runtime-result.txt" "$fetched_result" \
  >"$work_root/fetch.stdout" 2>"$work_root/fetch.stderr" || {
    emit 'container_runtime_inventory_wrapper=blocked;reason=result_fetch_failed'
    exit 1
  }

output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 768 )) || [[ "$line" == *$'\t'* ]] \
      || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then
    output_contract=blocked
    continue
  fi
  emit "$line"
done <"$fetched_result"
emit "remote_output_contract=$output_contract"

pass_markers="$(grep -Fxc 'container_runtime_inventory=pass' "$fetched_result" || true)"
blocked_markers="$(grep -Fxc 'container_runtime_inventory=blocked' "$fetched_result" || true)"
emit "inventory_pass_markers=$pass_markers;inventory_blocked_markers=$blocked_markers"
if [[ "$output_contract" == pass && "$pass_markers" == 1 && "$blocked_markers" == 0 ]]; then
  emit 'milestone=attended_sudo_inventory;state=pass'
  emit "container_runtime_inventory_wrapper=pass;local_report=$report_path;next_gate=review_runtime_images_before_artifact_selection"
  exit 0
fi

emit 'milestone=attended_sudo_inventory;state=blocked'
emit "container_runtime_inventory_wrapper=blocked;local_report=$report_path;next_gate=review_inventory_output"
exit 1
