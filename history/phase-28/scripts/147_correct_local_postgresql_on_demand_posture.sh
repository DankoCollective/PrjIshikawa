#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Correct the DankoSurface PostgreSQL cluster to the already-frozen on-demand
#   startup posture exposed by the blocked Script 146 preview gate.
#
# Mental model:
#   Bind the exact clean Script 146 policy block and accepted local corpus,
#   run one checksum-bound neutral helper with attended sudo, stream only its
#   content-free markers, then independently prove manual startup, disabled
#   boot links, a stopped cluster, and a free database port.
#
# Inputs or prerequisites:
#   The exact blocked Script 146 receipt, accepted local synthetic-corpus
#   receipt, stopped PostgreSQL 16/main cluster, and attended local sudo.
#
# Outputs or artifact lane:
#   One content-free report under
#   local/reports/ishikawa-v1.3-local-postgresql-on-demand. The only persistent
#   mutation is the approved PostgreSQL startup posture; no database data,
#   package, model, container, credential, forwarding, or remote host is used.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/147_correct_local_postgresql_on_demand_posture.sh --run

usage() {
  sed -n '3,28p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Apply and prove the local on-demand startup posture.' \
    '  --validate-only Validate exact inputs and shell structure without sudo.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly HELPER="$SCRIPT_DIR/set-native-database-on-demand-start"
readonly SCRIPT_146="$SCRIPT_DIR/146_launch_local_v1_3_preview.sh"
readonly SCRIPT_146_SHA256='8700d908f82f4285194cfba054fa0c481741ccb83cdfc0d5417e97979f89ab19'
readonly BLOCKED_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.3-local-preview/local_v1_3_preview_20261022T002921Z_JkP6hs.txt"
readonly BLOCKED_REPORT_SHA256='9d28a618e307f4e67934a73da51c44bf0037017809c06997b7c23bf5ec470b77'
readonly CORPUS_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.1-local-tuning-corpus/local_tuning_corpus_20261021T165048Z_QfXYrD.txt"
readonly CORPUS_REPORT_SHA256='5fab929e8e2cf838adc35d7c41d2dea5ed02f9670c9254ddf7f794c8e759ddff'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.3-local-postgresql-on-demand"
readonly START_POLICY_PATH='/etc/postgresql/16/main/start.conf'
readonly MANUAL_POLICY_SHA256='f0f5f2f0a2df8a53a51e2ecdac3f6ad271d30f1ca3f852f9da84cab7887b6d03'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_147_postgresql_on_demand=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_147_postgresql_on_demand=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required_command in \
  awk bash cat date dirname dpkg grep head hostname mkdir mktemp pg_isready \
  pg_lsclusters rm sed sha256sum sudo systemctl tee tr uname; do
  command -v "$required_command" >/dev/null 2>&1 || {
    printf 'script_147_postgresql_on_demand=blocked;reason=local_command_missing;command=%s\n' \
      "$required_command" >&2
    exit 2
  }
done
for required_file in "$HELPER" "$SCRIPT_146" "$BLOCKED_REPORT" "$CORPUS_REPORT"; do
  [[ -f "$required_file" && ! -L "$required_file" && -r "$required_file" ]] || {
    printf 'script_147_postgresql_on_demand=blocked;reason=required_input_unsafe\n' >&2
    exit 2
  }
done
bash -n "${BASH_SOURCE[0]}" "$HELPER" "$SCRIPT_146"
[[ "$(sha256sum "$SCRIPT_146" | awk '{print $1}')" == "$SCRIPT_146_SHA256" ]] || {
  printf 'script_147_postgresql_on_demand=blocked;reason=script_146_identity_mismatch\n' >&2
  exit 1
}
[[ "$(sha256sum "$BLOCKED_REPORT" | awk '{print $1}')" == "$BLOCKED_REPORT_SHA256" ]] || {
  printf 'script_147_postgresql_on_demand=blocked;reason=script_146_report_checksum_mismatch\n' >&2
  exit 1
}
grep -Fxq 'script_146_local_v1_3_preview=blocked;reason=postgresql_cluster_boot_enabled' \
  "$BLOCKED_REPORT" || {
    printf 'script_147_postgresql_on_demand=blocked;reason=script_146_block_not_bound\n' >&2
    exit 1
  }
grep -Fxq 'cleanup=complete;temporary_runtime_removed=true;credential_variables_cleared=true' \
  "$BLOCKED_REPORT" || {
    printf 'script_147_postgresql_on_demand=blocked;reason=script_146_cleanup_not_proven\n' >&2
    exit 1
  }
[[ "$(sha256sum "$CORPUS_REPORT" | awk '{print $1}')" == "$CORPUS_REPORT_SHA256" ]] || {
  printf 'script_147_postgresql_on_demand=blocked;reason=corpus_report_checksum_mismatch\n' >&2
  exit 1
}
grep -Fq 'script_117_local_tuning_corpus=pass;' "$CORPUS_REPORT" || {
  printf 'script_147_postgresql_on_demand=blocked;reason=corpus_not_accepted\n' >&2
  exit 1
}

helper_sha256="$(sha256sum "$HELPER" | awk '{print $1}')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_local_postgresql_on_demand_correction' \
    "script_sha256=$script_sha256;helper_sha256=$helper_sha256;script_146_sha256=$SCRIPT_146_SHA256" \
    "blocked_report_sha256=$BLOCKED_REPORT_SHA256;corpus_report_sha256=$CORPUS_REPORT_SHA256" \
    'sudo_used=false;database_contact=false;database_changed=false;service_changed=false;remote_contact=false' \
    'script_147_postgresql_on_demand=pass'
  exit 0
fi

report_path=''
work_root=''
failure_recorded=false

emit() {
  if [[ -n "$report_path" ]]; then
    printf '%s\n' "$1" | tee -a "$report_path"
  else
    printf '%s\n' "$1"
  fi
}

block() {
  failure_recorded=true
  emit "script_147_postgresql_on_demand=blocked;reason=$1"
  exit 1
}

cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  set +e
  if (( status != 0 )) && [[ "$failure_recorded" != true ]]; then
    emit "script_147_postgresql_on_demand=blocked;reason=unexpected_shell_failure;exit_code=$status"
  fi
  if [[ -n "$work_root" && "$work_root" == /tmp/ishikawa-script-147.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  emit 'cleanup=complete;temporary_files_removed=true'
  if [[ -n "$report_path" && -f "$report_path" ]]; then
    printf 'local_report=%s;local_report_sha256=%s\n' \
      "$report_path" "$(sha256sum "$report_path" | awk '{print $1}')"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

umask 077
mkdir -p -- "$REPORT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/postgresql_on_demand_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-script-147.XXXXXX)"
helper_output="$work_root/helper.txt"

emit 'purpose=correct_local_postgresql_on_demand_posture'
emit "started_utc=$timestamp;script_sha256=$script_sha256;helper_sha256=$helper_sha256"
emit "script_146_sha256=$SCRIPT_146_SHA256;blocked_report_sha256=$BLOCKED_REPORT_SHA256;corpus_report_sha256=$CORPUS_REPORT_SHA256"
emit 'authorized_actions=attended_local_sudo_change_postgresql_16_main_start_policy_auto_to_manual_disable_postgresql_boot_units_reload_systemd_validate_stopped_state_retain_content_free_report'
emit 'non_actions=no_database_start_no_database_connection_no_database_read_or_write_no_package_or_container_change_no_model_or_remote_contact_no_credential_access'

actual_hostname="$(hostname -s)"
actual_os_id="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"' | head -n 1)"
actual_os_version="$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"' | head -n 1)"
actual_architecture="$(dpkg --print-architecture)"
[[ "$actual_hostname|$actual_os_id|$actual_os_version|$actual_architecture" \
    == 'DankoSurface|ubuntu|24.04|arm64' ]] || block local_host_identity_mismatch
cluster_line="$(pg_lsclusters --no-header | awk '$1 == 16 && $2 == "main" {print; found=1} END {if (!found) exit 1}')" \
  || block postgresql_cluster_missing
read -r _ _ _ cluster_status _ _ _ <<<"$cluster_line"
[[ "$cluster_status" == down ]] || block postgresql_cluster_must_be_stopped
pg_isready --quiet --host 127.0.0.1 --port 5432 --timeout 2 && block postgresql_listener_unexpected
emit 'milestone=pre_mutation_posture;state=pass;cluster=16/main;cluster_state=down;port_5432=free'

emit 'milestone=attended_privilege;state=awaiting_operator_if_prompted'
set +e
sudo -p '[sudo] password for PostgreSQL on-demand correction: ' \
  bash "$HELPER" DankoSurface 24.04 arm64 | tee "$helper_output"
helper_status="${PIPESTATUS[0]}"
set -e
(( helper_status == 0 )) || block helper_execution_failed

while IFS= read -r helper_line; do
  (( ${#helper_line} <= 2048 )) || block helper_output_contract_invalid
  [[ "$helper_line" != *$'\t'* && "$helper_line" != *$'\r'* ]] \
    || block helper_output_contract_invalid
done <"$helper_output"
grep -Fxq 'native_database_on_demand_start=pass' "$helper_output" \
  || block helper_pass_marker_absent
cat "$helper_output" >>"$report_path"

[[ -f "$START_POLICY_PATH" && ! -L "$START_POLICY_PATH" ]] || block final_start_policy_unsafe
[[ "$(sha256sum "$START_POLICY_PATH" | awk '{print $1}')" == "$MANUAL_POLICY_SHA256" ]] \
  || block final_start_policy_identity_mismatch
[[ "$(awk '!/^[[:space:]]*(#|$)/ {print $1; count++} END {if (count != 1) exit 1}' "$START_POLICY_PATH")" == manual ]] \
  || block final_start_policy_value_mismatch
meta_enablement="$(systemctl is-enabled postgresql.service 2>/dev/null || true)"
cluster_enablement="$(systemctl is-enabled postgresql@16-main.service 2>/dev/null || true)"
[[ "$meta_enablement" != enabled && "$meta_enablement" != enabled-runtime ]] \
  || block final_meta_unit_boot_enabled
[[ "$cluster_enablement" != enabled && "$cluster_enablement" != enabled-runtime ]] \
  || block final_cluster_unit_boot_enabled
cluster_line="$(pg_lsclusters --no-header | awk '$1 == 16 && $2 == "main" {print; found=1} END {if (!found) exit 1}')" \
  || block final_postgresql_cluster_missing
read -r _ _ _ cluster_status _ _ _ <<<"$cluster_line"
[[ "$cluster_status" == down ]] || block final_postgresql_cluster_not_stopped
pg_isready --quiet --host 127.0.0.1 --port 5432 --timeout 2 && block final_postgresql_listener_unexpected

emit "milestone=post_mutation_posture;state=pass;start_policy=manual;meta_unit_enablement=${meta_enablement:-unknown};cluster_unit_enablement=${cluster_enablement:-unknown};cluster_state=down;port_5432=free"
emit 'database_changed=false;service_started=false;package_changed=false;credential_access=false;remote_contact=false'
emit 'script_147_postgresql_on_demand=pass;next_gate=rerun_script_146_local_v1_3_preview'

