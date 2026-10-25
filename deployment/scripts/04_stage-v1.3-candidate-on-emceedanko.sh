#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Purpose:
#   Carry and stage the exact Ishikawa v1.3 application plus its independent
#   qualification corpus on EmceeDanko without replacing active v1.2.
#
# Mental model:
#   Verify both current handoffs and the reviewed Script 02 inventory, reuse one
#   attended SSH connection, verify transferred bytes again, invoke a bounded
#   target helper, fetch its result, and remove only the temporary transfer.
#   A rerun reuses an exact candidate and fails closed on any drift.
#
# Inputs or prerequisites:
#   Completed Scripts 01-03, the latest accepted Script 02 inventory, strict SSH
#   host trust, and operator access to the application-host SSH identity.
#
# Outputs or artifact lane:
#   A local report under local/reports/emceedanko-v1.3-candidate-stage, a
#   versioned candidate at ~/Documents/Ishikawa-v1.3, and a separate staged
#   qualification input. No database, service, listener, or boot state changes.
#
# Usage:
#   bash ./deployment/scripts/04_stage-v1.3-candidate-on-emceedanko.sh --run

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
readonly application_handoff="$repo_root/local/artifacts/ishikawa-v1.3-current"
readonly corpus_handoff="$repo_root/local/artifacts/qualification-corpus-v3-current"
readonly application_archive="$application_handoff/ishikawa-v1.3.tar.gz"
readonly application_sidecar="$application_archive.sha256"
readonly corpus_archive="$corpus_handoff/qualification-corpus-v3.tar.gz"
readonly corpus_sidecar="$corpus_archive.sha256"
readonly target_helper="$repo_root/deployment/assets/stage-v1.3-candidate"
readonly inventory_root="$repo_root/local/reports/emceedanko-inventory"
readonly default_report_root="$repo_root/local/reports/emceedanko-v1.3-candidate-stage"

target="${APPLICATION_HOST_TARGET:-DankoSurface_EmceeDanko}"
expected_hostname="${APPLICATION_HOST_EXPECTED_HOSTNAME:-EmceeDanko}"
expected_os_version="${APPLICATION_HOST_EXPECTED_OS_VERSION:-24.04}"
identity_file="${APPLICATION_HOST_IDENTITY_FILE:-}"
report_root="${ISHIKAWA_SCRIPT04_REPORT_ROOT:-$default_report_root}"
inventory_report_override="${ISHIKAWA_SCRIPT04_INVENTORY_REPORT:-}"
replace_unqualified_candidate=false
replace_qualification_inputs=false
mode="${1:-}"
shift || true
stage='argument_validation'
report_path=''
work_root=''
remote_root=''
master_started=false
remote_created=false
ssh_args=()
remote_pid=''

result() { printf '\nSCRIPT RESULT\nscript_04_stage_v1_3_candidate_on_emceedanko=%s\n' "$1"; }
usage() {
  printf '%s\n' \
    'Usage: 04_stage-v1.3-candidate-on-emceedanko.sh --validate-only' \
    '       04_stage-v1.3-candidate-on-emceedanko.sh --run [--target SSH_ALIAS] [--identity-file ABSOLUTE_PATH]' \
    '              [--report-root ABSOLUTE_PATH] [--inventory-report ABSOLUTE_PATH]' \
    '              [--replace-unqualified-candidate] [--replace-qualification-inputs]'
}
quiet_cleanup() {
  local status="$?"
  trap - ERR EXIT INT TERM
  set +e
  if [[ -n "$remote_pid" ]] && kill -0 "$remote_pid" 2>/dev/null; then
    kill -TERM -- "-$remote_pid" 2>/dev/null || kill -TERM "$remote_pid" 2>/dev/null || true
    for _attempt in {1..50}; do
      kill -0 "$remote_pid" 2>/dev/null || break
      sleep 0.1
    done
    if kill -0 "$remote_pid" 2>/dev/null; then
      kill -KILL -- "-$remote_pid" 2>/dev/null || kill -KILL "$remote_pid" 2>/dev/null || true
    fi
    wait "$remote_pid" 2>/dev/null || true
  fi
  if [[ "$remote_created" == true && "$master_started" == true ]]; then
    timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
      "rm -rf -- '$remote_root' && test ! -e '$remote_root'" >/dev/null 2>&1
  fi
  if [[ "$master_started" == true ]]; then
    timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1
  fi
  [[ -z "$work_root" || "$work_root" != /tmp/ishikawa-script-04.* || ! -d "$work_root" ]] \
    || rm -rf -- "$work_root"
  exit "$status"
}
trap quiet_cleanup EXIT
trap 'stage=interrupted; block signal_interrupt "Candidate staging was interrupted." "Review the report and rerun Script 04." 130' INT
trap 'stage=interrupted; block signal_termination "Candidate staging received SIGTERM." "Review the report and rerun Script 04." 143' TERM

block() {
  local reason="$1" detail="$2" action="$3" payload
  local status="${4:-1}"
  trap - ERR
  payload="$(printf '%s\n' 'FAILURE DETAIL' "stage=$stage" "reason=$reason" \
    "detail=$detail" "operator_action=$action")"
  printf '%s\n' "$payload" >&2
  if [[ -n "$report_path" && -f "$report_path" && ! -L "$report_path" ]]; then
    printf '%s\n' "$payload" >>"$report_path"
    result blocked >>"$report_path"
  fi
  result blocked >&2
  exit "$status"
}
unexpected_error() {
  local status="$1" line="$2"
  trap - ERR
  block unexpected_command_failure \
    "An unhandled command failed at Script 04 line ${line} with exit code ${status}." \
    'Review the retained report; correct the complete failing stage before rerunning.' \
    "$status"
}
trap 'unexpected_error "$?" "$LINENO"' ERR

if [[ "$mode" == --help || "$mode" == -h ]]; then usage; exit 0; fi
while (( $# > 0 )); do
  case "$1" in
    --target) [[ $# -ge 2 ]] || block target_missing 'The target value is missing.' 'Supply one SSH alias.'; target="$2"; shift 2 ;;
    --expected-hostname) [[ $# -ge 2 ]] || block hostname_missing 'The hostname value is missing.' 'Supply the expected short hostname.'; expected_hostname="$2"; shift 2 ;;
    --expected-os-version) [[ $# -ge 2 ]] || block os_version_missing 'The OS version value is missing.' 'Supply NN.NN.'; expected_os_version="$2"; shift 2 ;;
    --identity-file) [[ $# -ge 2 ]] || block identity_missing 'The identity path is missing.' 'Supply an absolute identity path.'; identity_file="$2"; shift 2 ;;
    --report-root) [[ $# -ge 2 ]] || block report_root_missing 'The report path is missing.' 'Supply an absolute report directory.'; report_root="$2"; shift 2 ;;
    --inventory-report) [[ $# -ge 2 ]] || block inventory_report_missing 'The inventory path is missing.' 'Supply an absolute Script 02 report path.'; inventory_report_override="$2"; shift 2 ;;
    --replace-unqualified-candidate) replace_unqualified_candidate=true; shift ;;
    --replace-qualification-inputs) replace_qualification_inputs=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) block argument_invalid "Unsupported argument: $1" 'Use --help and rerun.' ;;
  esac
done
[[ "$mode" == --validate-only || "$mode" == --run ]] \
  || block mode_invalid 'Select exactly one execution mode.' 'Use --validate-only or --run.'
[[ "$target" =~ ^[A-Za-z0-9_@.:-]+$ ]] || block target_invalid 'The SSH target is not bounded.' 'Use a configured alias or USER@HOST.'
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || block hostname_invalid 'The expected hostname is invalid.' 'Correct it.'
[[ "$expected_os_version" =~ ^[0-9]{2}\.[0-9]{2}$ ]] || block os_version_invalid 'The expected OS version is invalid.' 'Use NN.NN.'
[[ "$report_root" == /* && ! -L "$report_root" ]] || block report_root_unsafe 'The report root must be an absolute non-symlink path.' 'Correct the report root.'
if [[ -n "$inventory_report_override" ]]; then
  [[ "$inventory_report_override" == /* && -f "$inventory_report_override" && ! -L "$inventory_report_override" && -r "$inventory_report_override" ]] \
    || block inventory_report_unsafe 'The explicit inventory report is missing or unsafe.' 'Supply one completed Script 02 report.'
fi
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] \
    || block identity_unsafe 'The explicit identity file is unsafe.' 'Correct the identity path or use SSH configuration.'
fi
for command_name in awk basename bash date find grep kill mkdir mktemp rm scp sha256sum sleep sort ssh stat tar tee timeout; do
  command -v "$command_name" >/dev/null 2>&1 \
    || block "command_missing_${command_name}" "Required local command unavailable: ${command_name}." 'Restore it and rerun.'
done
for file in "$application_archive" "$application_sidecar" "$corpus_archive" \
  "$corpus_sidecar" "$target_helper"; do
  [[ -f "$file" && ! -L "$file" && -r "$file" ]] \
    || block required_file_unsafe "Required input missing or unsafe: ${file}." 'Restore the qualified handoff and rerun.'
done
bash -n "${BASH_SOURCE[0]}" "$target_helper" \
  || block shell_syntax_invalid 'Script 04 or its target helper failed shell parsing.' 'Correct every parse error before staging.'

if [[ "$mode" == --run ]]; then
  stage='report_setup'
  mkdir -p -- "$report_root"
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  report_path="$(mktemp "$report_root/stage_v1_3_candidate_${timestamp}_XXXXXX.txt")"
  emit() {
    local message="$1" tag="${2:-READINESS}"
    printf '[%s] %s\n' "$tag" "$message" | tee -a "$report_path"
  }
  emit "report_path=$report_path;state=start" READINESS
  emit 'purpose=stage_checksum_bound_ishikawa_v1_3_candidate_side_by_side_on_emceedanko' READINESS
  emit 'state=start;gate=local_handoff_and_inventory_verification' READINESS
fi

(cd -- "$application_handoff" && sha256sum --check --strict "$(basename -- "$application_sidecar")" >/dev/null) \
  || block application_sidecar_failed 'The application handoff checksum failed.' 'Rebuild with Script 01.'
(cd -- "$corpus_handoff" && sha256sum --check --strict "$(basename -- "$corpus_sidecar")" >/dev/null) \
  || block corpus_sidecar_failed 'The corpus handoff checksum failed.' 'Re-export with Script 03.'
application_sha256="$(sha256sum -- "$application_archive" | awk '{print $1}')"
corpus_sha256="$(sha256sum -- "$corpus_archive" | awk '{print $1}')"
helper_sha256="$(sha256sum -- "$target_helper" | awk '{print $1}')"

stage='local_package_verification'
work_root="$(mktemp -d /tmp/ishikawa-script-04.XXXXXX)"
mkdir -p -- "$work_root/application" "$work_root/corpus"
tar -xzf "$application_archive" -C "$work_root/application"
bash "$work_root/application/ishikawa-v1.3/verify-ishikawa-release" >/dev/null \
  || block local_application_verification_failed 'The application archive failed its bundled verifier.' 'Rebuild with Script 01.'
tar -xzf "$corpus_archive" -C "$work_root/corpus"
(cd -- "$work_root/corpus/qualification-corpus-v3" && sha256sum --check --strict SHA256SUMS >/dev/null) \
  || block local_corpus_verification_failed 'The corpus archive failed its internal verifier.' 'Re-export with Script 03.'
latest_inventory="$inventory_report_override"
if [[ -z "$latest_inventory" ]]; then
  latest_inventory="$(find "$inventory_root" -maxdepth 1 -type f -name 'emceedanko_inventory_*.txt' -printf '%T@ %p\n' \
    | sort -nr | awk 'NR==1{sub(/^[^ ]+ /,""); print}')"
fi
[[ -n "$latest_inventory" && -f "$latest_inventory" && ! -L "$latest_inventory" ]] \
  || block inventory_report_missing 'No completed Script 02 inventory report exists.' 'Run Script 02 before Script 04.'
for fact in \
  'hostname_match=true' \
  'active_application_root=present' \
  'prior_rollback_root=present' \
  'unit_retrieval_api_load=loaded;unit_retrieval_api_active=active;unit_retrieval_api_enabled=static' \
  'tcp_port_3000_listening=true' \
  'tcp_port_1384_listening=true' \
  'ishikawa_application_host_inventory=pass' \
  'script_02_inventory_emceedanko=pass'; do
  grep -Fxq "$fact" "$latest_inventory" \
    || block inventory_contract_invalid "Script 02 report lacks required fact: ${fact}." 'Rerun Script 02 and review target posture.'
done
grep -Eq '^v1_3_candidate_root=(absent|present)$' "$latest_inventory" \
  || block inventory_contract_invalid 'Script 02 report lacks a bounded v1.3 candidate-path state.' 'Rerun Script 02 and review target posture.'
inventory_sha256="$(sha256sum -- "$latest_inventory" | awk '{print $1}')"
if [[ "$mode" == --run ]]; then
  emit 'state=pass;gate=local_handoff_and_inventory_verification' READINESS
fi

if [[ "$mode" == --validate-only ]]; then
  printf '%s\n' \
    'purpose=validate_side_by_side_v1_3_candidate_stage' \
    "application_archive_sha256=$application_sha256;corpus_archive_sha256=$corpus_sha256;helper_sha256=$helper_sha256" \
    "inventory_report_sha256=$inventory_sha256;active_v1_2_required=true;candidate_path=absent_exact_reuse_or_explicit_unqualified_replacement;replace_unqualified_candidate=$replace_unqualified_candidate;replace_qualification_inputs=$replace_qualification_inputs" \
    'target_contact=false;application_changed=false;database_changed=false;service_changed=false;boot_autostart_changed=false'
  result ready
  exit 0
fi

emit "inventory_report_sha256=$inventory_sha256" READINESS
emit "application_archive_sha256=$application_sha256;corpus_archive_sha256=$corpus_sha256;helper_sha256=$helper_sha256" READINESS
emit "authorized_actions=authenticate_transfer_verify_install_reuse_or_explicitly_replace_unqualified_side_by_side_candidate_stage_independent_corpus_input_remove_temporary_transfer;replace_unqualified_candidate=$replace_unqualified_candidate;replace_qualification_inputs=$replace_qualification_inputs" READINESS
emit 'non_actions=no_active_v1_2_change_no_rollback_tree_change_no_database_change_no_service_change_no_port_change_no_model_contact_no_boot_autostart_change' READINESS
emit "transfer_bytes_application=$(stat -Lc %s -- "$application_archive");transfer_bytes_corpus=$(stat -Lc %s -- "$corpus_archive");reused_transfer_bytes=0" READINESS

stage='authentication'
emit 'state=waiting_for_operator_if_prompted' AUTHENTICATION
control_path="/tmp/is04-${timestamp}-%C"
ssh_args=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 \
  -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto \
  -o "ControlPath=$control_path" -o ControlPersist=300)
[[ -z "$identity_file" ]] || ssh_args+=(-i "$identity_file" -o IdentitiesOnly=yes)
ssh -G "${ssh_args[@]}" "$target" >/dev/null \
  || block ssh_configuration_invalid 'OpenSSH rejected the bounded connection configuration.' 'Correct the SSH target or identity and rerun.'
timeout --foreground 120 ssh "${ssh_args[@]}" -Nf "$target" \
  || block ssh_master_start_failed 'SSH authentication or connection failed.' 'Correct SSH access and rerun Script 04.'
master_started=true
timeout --foreground 10 ssh "${ssh_args[@]}" -O check "$target" >/dev/null \
  || block ssh_master_check_failed 'The authenticated SSH control master was not ready.' 'Correct SSH access and rerun Script 04.'
emit 'state=pass;control_master=ready' AUTHENTICATION

stage='transfer'
remote_root="/tmp/ishikawa-v1.3-stage-${timestamp}-$$"
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" >/dev/null \
  || block remote_directory_failed 'The private target transfer directory could not be created.' 'Review target permissions and rerun.'
remote_created=true
emit 'state=start' TRANSFER
timeout --foreground 180 scp "${ssh_args[@]}" "$application_archive" "$corpus_archive" "$target_helper" "$target:$remote_root/" >/dev/null \
  || block transfer_failed 'One or more checksum-bound inputs failed to transfer.' 'Correct transport and rerun.'
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && printf '%s  %s\n%s  %s\n%s  %s\n' '$application_sha256' 'ishikawa-v1.3.tar.gz' '$corpus_sha256' 'qualification-corpus-v3.tar.gz' '$helper_sha256' 'stage-v1.3-candidate' | sha256sum --check --strict - >/dev/null" \
  || block transferred_checksum_failed 'Target-side transfer verification failed.' 'Do not install; inspect transport and rerun.'
emit 'state=pass;target_checksums=pass' TRANSFER

stage='candidate_stage'
emit 'state=start;active_v1_2_preserved=true' CANDIDATE
timeout 300 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && bash ./stage-v1.3-candidate '$expected_hostname' '$expected_os_version' '$remote_root/ishikawa-v1.3.tar.gz' '$application_sha256' '$remote_root/qualification-corpus-v3.tar.gz' '$corpus_sha256' '$remote_root/stage-result.txt' '$replace_unqualified_candidate' '$replace_qualification_inputs'" \
  >"$work_root/remote-stage.stdout" 2>"$work_root/remote-stage.stderr" &
remote_pid=$!
candidate_started="$(date +%s)"
next_heartbeat=30
while kill -0 "$remote_pid" 2>/dev/null; do
  sleep 5
  elapsed="$(( $(date +%s) - candidate_started ))"
  if (( elapsed >= next_heartbeat )); then
    emit "state=running;elapsed_seconds=$elapsed" CANDIDATE
    next_heartbeat=$((next_heartbeat + 30))
  fi
done
if wait "$remote_pid"; then
  remote_status=0
else
  remote_status="$?"
fi
remote_pid=''
fetched_result="$work_root/stage-result.txt"
timeout --foreground 60 scp "${ssh_args[@]}" "$target:$remote_root/stage-result.txt" "$fetched_result" >/dev/null \
  || block result_fetch_failed 'The target result could not be fetched.' 'Inspect the retained report and target staging state.'
output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] \
      || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then
    output_contract=blocked
    continue
  fi
  emit "$line" CANDIDATE
done <"$fetched_result"
emit "remote_exit_code=$remote_status;remote_output_contract=$output_contract" CANDIDATE
(( remote_status == 0 )) || block remote_candidate_stage_failed 'The target helper rejected or could not complete the candidate stage.' 'Use the preceding reason and correct every target condition before rerunning.'
[[ "$output_contract" == pass ]] || block remote_output_contract_failed 'Target output violated the bounded content-free contract.' 'Inspect the fetched result locally before proceeding.'
for fact in \
  "target_hostname=$expected_hostname;os_id=ubuntu;os_version=$expected_os_version;architecture=amd64" \
  'candidate_root=HOME/Documents/Ishikawa-v1.3;qualification_inputs_root=HOME/Documents/Ishikawa-v1.3-qualification-inputs' \
  'active_v1_2_preserved=true;rollback_tree_preserved=true;active_service_unchanged=true;ports_3000_1384_unchanged=true' \
  'database_changed=false;service_changed=false;boot_autostart_changed=false;model_contact=false;credential_read=false' \
  'ishikawa_v1_3_candidate_stage=pass'; do
  grep -Fxq "$fact" "$fetched_result" \
    || block target_result_contract_failed "Target result lacks required fact: ${fact}." 'Do not proceed to database qualification.'
done
grep -Eq "^application_archive_sha256=$application_sha256;application_verification=pass;candidate_action=(installed_new|reused_exact|replaced_unqualified)$" "$fetched_result" \
  || block application_action_invalid 'The candidate action was not a bounded install, exact reuse, or explicit unqualified replacement.' 'Inspect the target candidate path.'
grep -Eq "^corpus_archive_sha256=$corpus_sha256;corpus_verification=pass;corpus_action=(staged_new|reused_exact|replaced_unqualified)$" "$fetched_result" \
  || block corpus_action_invalid 'The corpus action was not a bounded stage, exact reuse, or explicit unqualified replacement.' 'Inspect the target qualification-input path.'
emit 'state=pass;active_v1_2_preserved=true;database_changed=false' CANDIDATE

stage='cleanup'
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "rm -rf -- '$remote_root' && test ! -e '$remote_root'" >/dev/null \
  || block remote_cleanup_failed 'The temporary transfer directory was not removed.' 'Remove only the reported temporary directory before proceeding.'
remote_created=false
timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1 \
  || block ssh_master_cleanup_failed 'The SSH control master did not close cleanly.' 'Close the bounded control socket before proceeding.'
master_started=false
emit 'state=pass;temporary_transfer_removed=true;payload_bytes_deleted=true' CLEANUP
emit "local_report=$report_path;next_gate=script_05_disposable_database_chunk_ingest_and_frontier_qualification" SUMMARY
result pass | tee -a "$report_path"
