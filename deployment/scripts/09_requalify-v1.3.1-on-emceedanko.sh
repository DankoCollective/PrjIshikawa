#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Purpose:
#   Run the attended exact-byte Ishikawa v1.3.1 production requalification on
#   EmceeDanko, record human UI acceptance, and clean the isolated candidate.
# Mental model:
#   Verify immutable local handoffs, transfer one private checksum-bound payload,
#   run exactly one target lifecycle action, return its content-free receipt,
#   and publish that receipt atomically without relying on WSL file modes.
# Inputs or prerequisites:
#   Exact Script 07/08 handoffs, strict SSH access, externally managed model
#   tunnels on EmceeDanko, and attended secrets for --run.
# Outputs or artifact lane:
#   A local report and a checksum-bound qualification/acceptance/cleanup receipt
#   set under local/artifacts; the --run candidate remains isolated on the target.
#
# Usage:
#   bash ./deployment/scripts/09_requalify-v1.3.1-on-emceedanko.sh --validate-only
#   bash ./deployment/scripts/09_requalify-v1.3.1-on-emceedanko.sh --run
#   bash ./deployment/scripts/09_requalify-v1.3.1-on-emceedanko.sh --accept
#   bash ./deployment/scripts/09_requalify-v1.3.1-on-emceedanko.sh --cleanup

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
readonly target_helper="$repo_root/deployment/assets/requalify-v1.3.1-on-emceedanko"
readonly application_root="$repo_root/local/artifacts/ishikawa-v1.3.1-candidate-current"
readonly runtime_root="$repo_root/local/artifacts/node-next-runtime-current"
readonly evaluator="$repo_root/qualification/frontier/evaluate-frontier.py"
readonly frontier_cases="$repo_root/qualification/frontier/frontier-cases.json"
readonly default_artifact_parent="$repo_root/local/artifacts"
readonly artifact_parent="${ISHIKAWA_SCRIPT09_ARTIFACT_PARENT:-$default_artifact_parent}"
readonly artifact_current="$artifact_parent/emceedanko-v1.3.1-requalification-current"
readonly default_report_root="$repo_root/local/reports/emceedanko-v1.3.1-requalification"
readonly expected_application_sha256='2dbf08b9e15fb4436e54ce492f2ad430129e794d33a1a45cdc6abf1a7b0b5f69'
readonly expected_runtime_archive_sha256='af95820f63798b39c6538e3f9b5653d47b07aed1d81625e2382485ff559eff3f'
readonly expected_image_id='sha256:79f39435329920c9c834e55cf5e18528540220111ae2a35d779a86d0b539d298'

target="${APPLICATION_HOST_TARGET:-DankoSurface_EmceeDanko}"
expected_hostname="${APPLICATION_HOST_EXPECTED_HOSTNAME:-EmceeDanko}"
expected_os_version="${APPLICATION_HOST_EXPECTED_OS_VERSION:-24.04}"
identity_file="${APPLICATION_HOST_IDENTITY_FILE:-}"
gemma_base_url="${ISHIKAWA_GEMMA_BASE_URL:-http://127.0.0.1:18000}"
nomic_base_url="${ISHIKAWA_NOMIC_BASE_URL:-http://127.0.0.1:18001}"
report_root="${ISHIKAWA_SCRIPT09_REPORT_ROOT:-$default_report_root}"
mode="${1:-}"
shift || true
stage='argument_validation'
report_path=''
work_root=''
remote_root=''
remote_created=false
master_started=false
remote_pid=''
stream_pid=''
artifact_stage=''
artifact_probe=''
recovered_qualification_receipt=''
ssh_args=()

usage() {
  printf '%s\n' \
    'Usage: 09_requalify-v1.3.1-on-emceedanko.sh --validate-only' \
    '       09_requalify-v1.3.1-on-emceedanko.sh {--run|--accept|--cleanup}' \
    '              [--target SSH_ALIAS] [--identity-file ABSOLUTE_PATH]' \
    '              [--report-root ABSOLUTE_PATH]' \
    '              [--gemma-base-url http://127.0.0.1:PORT]' \
    '              [--nomic-base-url http://127.0.0.1:PORT]'
}

result() {
  printf '\nSCRIPT RESULT\nscript_09_v1_3_1_requalification=%s\n' "$1"
}

block() {
  local reason="$1" detail="$2" action="$3" status="${4:-1}" payload
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

cleanup() {
  local status="$?"
  trap - ERR EXIT INT TERM
  set +e
  if [[ -n "$remote_pid" ]] && kill -0 "$remote_pid" 2>/dev/null; then
    kill -TERM -- "-$remote_pid" 2>/dev/null || kill -TERM "$remote_pid" 2>/dev/null || true
    wait "$remote_pid" 2>/dev/null || true
  fi
  if [[ -n "$stream_pid" ]] && kill -0 "$stream_pid" 2>/dev/null; then
    kill -TERM "$stream_pid" 2>/dev/null || true
    wait "$stream_pid" 2>/dev/null || true
  fi
  if [[ "$remote_created" == true && "$master_started" == true ]]; then
    timeout --foreground 120 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
      "rm -rf -- '$remote_root' && test ! -e '$remote_root'" >/dev/null 2>&1
  fi
  if [[ "$master_started" == true ]]; then
    timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1
  fi
  if [[ -n "$work_root" && "$work_root" == /tmp/ishikawa-script-09.* \
      && -d "$work_root" && ! -L "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  if [[ -n "$artifact_stage" \
      && "$artifact_stage" == "$artifact_parent"/.emceedanko-v1.3.1-requalification-current.* \
      && -d "$artifact_stage" && ! -L "$artifact_stage" ]]; then
    rm -rf -- "$artifact_stage"
  fi
  if [[ -n "$artifact_probe" \
      && "$artifact_probe" == "$artifact_parent"/.emceedanko-v1.3.1-publication-probe.* \
      && -d "$artifact_probe" && ! -L "$artifact_probe" ]]; then
    rmdir -- "$artifact_probe" 2>/dev/null || true
  fi
  exit "$status"
}

unexpected_error() {
  local status="$1" line="$2"
  block unexpected_command_failure \
    "An unhandled command failed at Script 09 line ${line} with exit code ${status}." \
    'Review the retained report and correct the complete failing stage.' "$status"
}

trap cleanup EXIT
trap 'unexpected_error "$?" "$LINENO"' ERR
trap 'stage=interrupted; block signal_hangup "Script 09 received SIGHUP." "Review target cleanup state and rerun the appropriate mode." 129' HUP
trap 'stage=interrupted; block signal_interrupt "Script 09 was interrupted." "Review target cleanup state and rerun the appropriate mode." 130' INT
trap 'stage=interrupted; block signal_termination "Script 09 received SIGTERM." "Review target cleanup state and rerun the appropriate mode." 143' TERM

validate_loopback_url() {
  python3 -B - "$1" <<'PY'
import sys
from urllib.parse import urlsplit
value = urlsplit(sys.argv[1])
if (
    value.scheme != "http" or value.hostname != "127.0.0.1" or value.port is None
    or value.path not in {"", "/"} or value.query or value.fragment
    or value.username is not None or value.password is not None
):
    raise SystemExit(1)
PY
}

qualification_receipt_valid() {
  local receipt_path="$1"
  [[ -f "$receipt_path" && ! -L "$receipt_path" ]] \
    && grep -Fxq 'schema=ishikawa.emceedanko-v1.3.1-qualification.v1' "$receipt_path" \
    && grep -Fxq "application_archive_sha256=$expected_application_sha256" "$receipt_path" \
    && grep -Fxq "runtime_archive_sha256=$expected_runtime_archive_sha256" "$receipt_path" \
    && grep -Fxq "image_id=$expected_image_id" "$receipt_path" \
    && grep -Fxq 'production_build_start=pass' "$receipt_path" \
    && grep -Fxq 'fresh_container_rebuild=pass' "$receipt_path" \
    && grep -Fxq 'frontier_cases=60/60' "$receipt_path" \
    && grep -Fxq 'accepted_v1_3_mutated=false' "$receipt_path" \
    && grep -Fxq 'accepted_database_mutated=false' "$receipt_path" \
    && grep -Fxq 'boot_autostart=false' "$receipt_path" \
    && grep -Fxq 'human_ui_acceptance=pending' "$receipt_path"
}

if [[ "$mode" == --help || "$mode" == -h ]]; then usage; exit 0; fi
while (( $# > 0 )); do
  case "$1" in
    --target) [[ $# -ge 2 ]] || block target_missing 'The SSH target value is missing.' 'Supply one SSH alias.'; target="$2"; shift 2 ;;
    --identity-file) [[ $# -ge 2 ]] || block identity_missing 'The SSH identity value is missing.' 'Supply one absolute file path.'; identity_file="$2"; shift 2 ;;
    --report-root) [[ $# -ge 2 ]] || block report_root_missing 'The report root is missing.' 'Supply one absolute directory.'; report_root="$2"; shift 2 ;;
    --gemma-base-url) [[ $# -ge 2 ]] || block gemma_url_missing 'The Gemma URL is missing.' 'Supply bounded loopback HTTP.'; gemma_base_url="$2"; shift 2 ;;
    --nomic-base-url) [[ $# -ge 2 ]] || block nomic_url_missing 'The Nomic URL is missing.' 'Supply bounded loopback HTTP.'; nomic_base_url="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) block argument_invalid "Unsupported argument: $1" 'Use --help and rerun.' 2 ;;
  esac
done
case "$mode" in --validate-only|--run|--accept|--cleanup) ;; *) block mode_invalid 'Select exactly one supported mode.' 'Use --validate-only, --run, --accept, or --cleanup.' 2 ;; esac
[[ "$target" =~ ^[A-Za-z0-9_@.:-]+$ ]] || block target_invalid 'The SSH target is not bounded.' 'Use a configured alias or USER@HOST.'
[[ "$expected_hostname" == EmceeDanko && "$expected_os_version" == 24.04 ]] \
  || block frozen_target_changed 'Script 09 is frozen to EmceeDanko Ubuntu 24.04 AMD64.' 'Restore the frozen target facts.'
[[ "$report_root" == /* && ! -L "$report_root" ]] || block report_root_unsafe 'The report root must be an absolute non-symlink path.' 'Correct the report root.'
[[ "$artifact_parent" == /* && "$artifact_parent" != / && ! -L "$artifact_parent" ]] \
  || block artifact_parent_unsafe 'The evidence artifact parent must be an absolute non-symlink directory path.' 'Correct the artifact parent.'
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] \
    || block identity_unsafe 'The SSH identity is not a readable regular file.' 'Correct the identity or rely on SSH configuration.'
fi
validate_loopback_url "$gemma_base_url" || block gemma_url_invalid 'The Gemma URL is outside loopback HTTP.' 'Correct the model forward URL.'
validate_loopback_url "$nomic_base_url" || block nomic_url_invalid 'The Nomic URL is outside loopback HTTP.' 'Correct the model forward URL.'
for command_name in awk bash chmod cp date find grep jq kill mkdir mkfifo mktemp mv python3 rm rmdir scp sha256sum sleep sort ssh stat tar tee timeout tr; do
  command -v "$command_name" >/dev/null 2>&1 \
    || block "command_missing_${command_name}" "Required local command unavailable: ${command_name}." 'Restore the named command and rerun.'
done

stage='local_preflight'
for required_file in \
  "$target_helper" \
  "$application_root/SHA256SUMS" \
  "$application_root/ishikawa-v1.3.1.tar.gz" \
  "$application_root/ishikawa-v1.3.1.tar.gz.sha256" \
  "$application_root/release-receipt.json" \
  "$runtime_root/SHA256SUMS" \
  "$runtime_root/node-next-runtime-amd64.tar" \
  "$runtime_root/node-next-runtime-amd64.tar.sha256" \
  "$runtime_root/image-identity.json" \
  "$evaluator" "$frontier_cases"; do
  [[ -f "$required_file" && ! -L "$required_file" && -r "$required_file" ]] \
    || block required_input_unsafe "A required exact input is missing or unsafe: ${required_file}." 'Restore Script 07, Script 08, or the frozen frontier input.'
done
bash -n "${BASH_SOURCE[0]}" "$target_helper" \
  || block shell_syntax_invalid 'Script 09 or its target helper failed shell parsing.' 'Correct the complete parse failure.'
helper_validation="$(bash "$target_helper" --validate-only)" \
  || block helper_validation_failed 'The target helper rejected its local contract.' 'Correct the helper before target contact.'
grep -Fxq 'v1_3_1_requalification_helper=ready' <<<"$helper_validation" \
  || block helper_ready_marker_missing 'The helper omitted its exact ready marker.' 'Treat the helper as unvalidated.'
(
  cd -- "$application_root"
  sha256sum --check --strict SHA256SUMS >/dev/null
  sha256sum --check --strict ishikawa-v1.3.1.tar.gz.sha256 >/dev/null
) || block application_handoff_checksum_failed 'The Script 08 application handoff failed its checksums.' 'Rerun Script 08.'
(
  cd -- "$runtime_root"
  sha256sum --check --strict SHA256SUMS >/dev/null
  sha256sum --check --strict node-next-runtime-amd64.tar.sha256 >/dev/null
) || block runtime_handoff_checksum_failed 'The Script 07 runtime handoff failed its checksums.' 'Rerun Script 07.'
application_sha256="$(sha256sum -- "$application_root/ishikawa-v1.3.1.tar.gz" | awk '{print $1}')"
runtime_archive_sha256="$(sha256sum -- "$runtime_root/node-next-runtime-amd64.tar" | awk '{print $1}')"
runtime_image_id="$(jq -r '.image_id' "$runtime_root/image-identity.json")"
[[ "$application_sha256" == "$expected_application_sha256" \
    && "$runtime_archive_sha256" == "$expected_runtime_archive_sha256" \
    && "$runtime_image_id" == "$expected_image_id" ]] \
  || block exact_handoff_identity_mismatch 'The current Script 07 or Script 08 handoff is not the qualified exact identity.' 'Restore the exact published candidate handoffs.'
jq -e --arg archive "$expected_application_sha256" '
  .archive_sha256 == $archive and .release == "Ishikawa v1.3.1 candidate"
  and .deterministic_archive == true and .fresh_install == "pass"
  and .coding_standard == "pass"
  and .human_ui_validation == "pending_exact_candidate_requalification"' \
  "$application_root/release-receipt.json" >/dev/null \
  || block application_receipt_invalid 'The application receipt is not the pending exact candidate.' 'Restore the Script 08 handoff.'
helper_sha256="$(sha256sum -- "$target_helper" | awk '{print $1}')"

if [[ "$mode" == --validate-only ]]; then
  printf '%s\n' \
    'purpose=validate_exact_v1_3_1_production_requalification' \
    "application_archive_sha256=$application_sha256" \
    "runtime_archive_sha256=$runtime_archive_sha256" \
    "image_id=$runtime_image_id" \
    'accepted_v1_3_mutation=false;accepted_database_mutation=false;target_contact=false'
  result ready
  exit 0
fi

stage='report_setup'
mkdir -p -- "$report_root" "$artifact_parent" \
  || block local_output_parent_unwritable 'A local report or artifact parent could not be created.' 'Correct the local workspace permissions and rerun.'
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_root/requalification_${mode#--}_${timestamp}_XXXXXX.txt")" \
  || block report_creation_failed 'The Script 09 report could not be created.' 'Correct local report permissions.'
work_root="$(mktemp -d /tmp/ishikawa-script-09.XXXXXX)" \
  || block workspace_creation_failed 'The private local workspace could not be created.' 'Correct /tmp permissions or capacity.'
emit() { printf '[%s] %s\n' "$2" "$1" | tee -a "$report_path"; }
emit "report_path=$report_path;state=start;mode=${mode#--}" READINESS
emit "application_archive_sha256=$application_sha256;runtime_archive_sha256=$runtime_archive_sha256;image_id=$runtime_image_id;helper_sha256=$helper_sha256" READINESS
emit 'accepted_v1_3_mutation=false;accepted_database_mutation=false;boot_autostart_change=false' BOUNDARY
artifact_probe="$artifact_parent/.emceedanko-v1.3.1-publication-probe.${timestamp}.$$"
mkdir -- "$artifact_probe" \
  || block artifact_parent_unwritable 'The local evidence lane cannot create a staging directory.' 'Correct the local artifact directory permissions before target work.'
rmdir -- "$artifact_probe" \
  || block artifact_probe_cleanup_failed 'The empty local evidence probe could not be removed.' 'Remove only the reported empty probe and inspect the artifact lane.'
artifact_probe=''
emit 'state=pass;report_lane=writable;evidence_lane=writable;wsl_mode_metadata_required=false' READINESS
if [[ -e "$artifact_current" || -L "$artifact_current" ]]; then
  [[ -d "$artifact_current" && ! -L "$artifact_current" ]] \
    || block current_evidence_unsafe 'The current requalification evidence path is unsafe.' 'Inspect the local artifact lane before target work.'
  (cd -- "$artifact_current" && sha256sum --check --strict SHA256SUMS >/dev/null) \
    || block current_evidence_checksum_failed 'The current requalification evidence failed its checksum manifest.' 'Inspect it before any later lifecycle action.'
  if [[ "$mode" != --run && -f "$artifact_current/qualification-receipt.txt" ]]; then
    qualification_receipt_valid "$artifact_current/qualification-receipt.txt" \
      || block current_qualification_receipt_invalid 'The current qualification receipt does not match the exact production gate.' 'Inspect the local evidence before a target lifecycle action.'
  fi
fi

stage='payload_assembly'
payload_root="$work_root/payload"
mkdir -m 0700 -- "$payload_root"
cp -- "$target_helper" "$payload_root/requalify-v1.3.1-on-emceedanko"
cp -- "$application_root/ishikawa-v1.3.1.tar.gz" "$payload_root/"
cp -- "$runtime_root/image-identity.json" "$payload_root/"
cp -- "$evaluator" "$payload_root/evaluate-frontier.py"
cp -- "$frontier_cases" "$payload_root/frontier-cases.json"
chmod 0755 "$payload_root/requalify-v1.3.1-on-emceedanko" "$payload_root/evaluate-frontier.py"
(
  cd -- "$payload_root"
  while IFS= read -r name; do sha256sum -- "$name"; done < <(
    find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' | sort
  ) >SHA256SUMS
  sha256sum --check --strict SHA256SUMS >/dev/null
)
payload_archive="$work_root/script-09-payload.tar.gz"
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime='UTC 1970-01-01' \
  -czf "$payload_archive" -C "$work_root" payload
payload_sha256="$(sha256sum -- "$payload_archive" | awk '{print $1}')"
emit "state=pass;payload_sha256=$payload_sha256;transfer_bytes=$(stat -Lc %s -- "$payload_archive")" PAYLOAD

stage='authentication'
emit 'state=waiting_for_ssh_private_key_passphrase_if_prompted' AUTHENTICATION
control_path="/tmp/is09-${timestamp}-%C"
ssh_args=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 \
  -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto \
  -o "ControlPath=$control_path" -o ControlPersist=300)
[[ -z "$identity_file" ]] || ssh_args+=(-i "$identity_file" -o IdentitiesOnly=yes)
ssh -G "${ssh_args[@]}" "$target" >/dev/null \
  || block ssh_configuration_invalid 'OpenSSH rejected the bounded target configuration.' 'Correct the SSH alias or identity.'
timeout --foreground 120 ssh "${ssh_args[@]}" -Nf "$target" \
  || block ssh_master_start_failed 'SSH authentication or connection failed.' 'Correct SSH access and rerun Script 09.'
master_started=true
timeout --foreground 10 ssh "${ssh_args[@]}" -O check "$target" >/dev/null \
  || block ssh_master_check_failed 'The authenticated SSH control master was not ready.' 'Correct SSH access.'
emit 'state=pass;control_master=ready' AUTHENTICATION

stage='target_transfer'
remote_root="/tmp/ishikawa-requalification-${timestamp}-$$"
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" >/dev/null \
  || block remote_directory_failed 'The private target transfer directory could not be created.' 'Review EmceeDanko permissions.'
remote_created=true
timeout --foreground 300 scp "${ssh_args[@]}" "$payload_archive" "$target:$remote_root/" >/dev/null \
  || block transfer_failed 'The checksum-bound Script 09 payload failed to transfer.' 'Correct SSH transport and rerun.'
timeout --foreground 180 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && printf '%s  %s\n' '$payload_sha256' 'script-09-payload.tar.gz' | sha256sum --check --strict - >/dev/null && tar -xzf script-09-payload.tar.gz && cd payload && sha256sum --check --strict SHA256SUMS >/dev/null" \
  || block transferred_payload_invalid 'EmceeDanko rejected the payload archive or its internal checksums.' 'Correct the transfer; no candidate action was run.'
emit 'state=pass;target_checksums=pass' TRANSFER

if [[ "$mode" != --run && ! -f "$artifact_current/qualification-receipt.txt" ]]; then
  stage='qualification_receipt_recovery'
  recovered_qualification_receipt="$work_root/recovered-qualification-receipt.txt"
  timeout --foreground 60 scp "${ssh_args[@]}" \
    "$target:Documents/Ishikawa-v1.3.1-qualification/state/reports/qualification/emceedanko-v1.3.1-qualification.txt" \
    "$recovered_qualification_receipt" >/dev/null \
    || block qualification_receipt_recovery_failed 'The durable target qualification receipt could not be recovered before the requested lifecycle action.' 'Keep the candidate unchanged and inspect its qualification state.'
  qualification_receipt_valid "$recovered_qualification_receipt" \
    || block recovered_qualification_receipt_invalid 'The recovered target qualification receipt did not match the exact qualified candidate.' 'Do not accept or clean up an unbound candidate.'
  emit 'state=pass;source=durable_target_candidate;content=qualification_receipt' RETURN
fi

stage="target_${mode#--}"
emit "state=start;mode=${mode#--};interactive_prompts=$([[ "$mode" == --run ]] && printf true || printf false)" TARGET
stream_path="$work_root/target.stream"
mkfifo -m 0600 -- "$stream_path"
tee -a "$report_path" <"$stream_path" &
stream_pid="$!"
tty_input=/dev/null
[[ -t 0 ]] && tty_input=/dev/tty
remote_timeout=900
[[ "$mode" == --run ]] && remote_timeout=9000
timeout --foreground "$remote_timeout" ssh -tt "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root/payload' && bash ./requalify-v1.3.1-on-emceedanko '$mode' --payload-root '$remote_root/payload' --result-path '$remote_root/payload/target-result.txt' --expected-hostname '$expected_hostname' --expected-os-version '$expected_os_version' --expected-architecture amd64 --gemma-base-url '$gemma_base_url' --nomic-base-url '$nomic_base_url' --expected-helper-sha256 '$helper_sha256'" \
  <"$tty_input" >"$stream_path" 2>&1 &
remote_pid="$!"
if wait "$remote_pid"; then remote_status=0; else remote_status="$?"; fi
remote_pid=''
if wait "$stream_pid"; then tee_status=0; else tee_status="$?"; fi
stream_pid=''
rm -f -- "$stream_path"
(( tee_status == 0 )) || block report_stream_failed 'The live Script 09 report stream failed.' 'Restore the local report lane.'
if (( remote_status != 0 )); then
  [[ "$remote_status" != 124 ]] || block target_action_timeout "The ${mode#--} action exceeded its bounded timeout." 'Review the retained target milestones and cleanup state.'
  nested_reason="$(tr -d '\r' <"$report_path" | sed -n 's/^reason=\([a-z0-9_]*\)$/\1/p' | tail -n 1)"
  block "${nested_reason:-target_action_failed}" "The target ${mode#--} action exited with status ${remote_status}." 'Correct all retained failure details before retrying.' "$remote_status"
fi
case "$mode" in
  --run) marker='v1_3_1_requalification=pass'; receipt_name='qualification-receipt.txt' ;;
  --accept) marker='v1_3_1_requalification_acceptance=pass'; receipt_name='acceptance-receipt.txt' ;;
  --cleanup) marker='v1_3_1_requalification_cleanup=pass'; receipt_name='cleanup-receipt.txt' ;;
esac
grep -Fqx "$marker" < <(tr -d '\r' <"$report_path") \
  || block target_pass_marker_missing 'The target action exited without its exact pass marker.' 'Treat the action as incomplete.'

stage='receipt_return'
timeout --foreground 60 scp "${ssh_args[@]}" "$target:$remote_root/payload/target-result.txt" "$work_root/$receipt_name" >/dev/null \
  || block receipt_fetch_failed 'The content-free target receipt could not be returned.' 'Preserve target state and retry the same mode only after review.'
grep -Fxq "application_archive_sha256=$expected_application_sha256" "$work_root/$receipt_name" \
  && grep -Fxq "runtime_archive_sha256=$expected_runtime_archive_sha256" "$work_root/$receipt_name" \
  && grep -Fxq "image_id=$expected_image_id" "$work_root/$receipt_name" \
  && grep -Fxq 'accepted_v1_3_mutated=false' "$work_root/$receipt_name" \
  && grep -Fxq 'accepted_database_mutated=false' "$work_root/$receipt_name" \
  && grep -Fxq 'boot_autostart=false' "$work_root/$receipt_name" \
  || block returned_receipt_invalid 'The returned target receipt omitted an exact identity or safety invariant.' 'Do not publish the receipt.'
case "$mode" in
  --run)
    qualification_receipt_valid "$work_root/$receipt_name" \
      || block returned_qualification_receipt_invalid 'The returned qualification receipt omitted an exact production gate.' 'Do not publish the qualification evidence.'
    ;;
  --accept)
    grep -Fxq 'schema=ishikawa.emceedanko-v1.3.1-acceptance.v1' "$work_root/$receipt_name" \
      && grep -Fxq 'human_ui_acceptance=accepted' "$work_root/$receipt_name" \
      && grep -Fxq 'production_build_start=pass' "$work_root/$receipt_name" \
      && grep -Fxq 'frontier_cases=60/60' "$work_root/$receipt_name" \
      || block returned_acceptance_receipt_invalid 'The returned acceptance receipt omitted an exact human or production gate.' 'Do not publish acceptance.'
    ;;
  --cleanup)
    grep -Fxq 'schema=ishikawa.emceedanko-v1.3.1-action.v1' "$work_root/$receipt_name" \
      && grep -Fxq 'mode=cleanup' "$work_root/$receipt_name" \
      && grep -Fxq 'state=pass' "$work_root/$receipt_name" \
      && grep -Fxq 'detail=candidate_removed=true' "$work_root/$receipt_name" \
      || block returned_cleanup_receipt_invalid 'The returned cleanup receipt omitted the exact successful removal state.' 'Do not publish cleanup.'
    ;;
esac

stage='local_evidence_publication'
artifact_stage="$artifact_parent/.emceedanko-v1.3.1-requalification-current.${timestamp}.$$"
mkdir -- "$artifact_stage" \
  || block evidence_stage_creation_failed 'The local evidence staging directory could not be created.' 'Correct the local artifact lane; the target result remains durable.'
if [[ -e "$artifact_current" || -L "$artifact_current" ]]; then
  [[ -d "$artifact_current" && ! -L "$artifact_current" ]] \
    || block current_evidence_unsafe 'The current requalification evidence path is unsafe.' 'Inspect the local artifact lane.'
  (cd -- "$artifact_current" && sha256sum --check --strict SHA256SUMS >/dev/null) \
    || block current_evidence_checksum_failed 'The current requalification evidence failed its checksum manifest.' 'Inspect it before adding a later lifecycle receipt.'
  if [[ "$mode" != --run ]]; then
    cp -R --no-preserve=mode,ownership -- "$artifact_current/." "$artifact_stage/" \
      || block current_evidence_copy_failed 'The current evidence could not be copied without POSIX-mode preservation.' 'Inspect the local artifact lane before retrying.'
  fi
fi
if [[ -n "$recovered_qualification_receipt" ]]; then
  cp -- "$recovered_qualification_receipt" "$artifact_stage/qualification-receipt.txt" \
    || block recovered_qualification_publication_failed 'The recovered qualification receipt could not be staged locally.' 'Preserve the target candidate and inspect the local artifact lane.'
fi
if [[ "$mode" != --run && ! -f "$artifact_stage/qualification-receipt.txt" ]]; then
  block qualification_receipt_missing 'Acceptance or cleanup cannot publish without the exact qualification receipt.' 'Run Script 09 --run and preserve its returned receipt first.'
fi
if [[ "$mode" == --accept && -e "$artifact_stage/acceptance-receipt.txt" ]]; then
  block acceptance_receipt_exists 'The current evidence already contains acceptance.' 'Review it rather than replacing it.'
fi
rm -f -- "$artifact_stage/SHA256SUMS"
cp -- "$work_root/$receipt_name" "$artifact_stage/$receipt_name" \
  || block lifecycle_receipt_publication_failed 'The returned lifecycle receipt could not be staged locally.' 'Preserve target state and inspect the local artifact lane.'
(
  cd -- "$artifact_stage"
  while IFS= read -r name; do sha256sum -- "$name"; done < <(
    find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' | sort
  ) >SHA256SUMS
  sha256sum --check --strict SHA256SUMS >/dev/null
)
if [[ -e "$artifact_current" || -L "$artifact_current" ]]; then
  evidence_backup="$artifact_parent/.emceedanko-v1.3.1-requalification-previous.${timestamp}.$$"
  mv -- "$artifact_current" "$evidence_backup"
  if ! mv -- "$artifact_stage" "$artifact_current"; then
    mv -- "$evidence_backup" "$artifact_current"
    block evidence_publication_failed 'The prior evidence was restored after atomic publication failed.' 'Inspect local storage.'
  fi
  rm -rf -- "$evidence_backup"
else
  mv -- "$artifact_stage" "$artifact_current" \
    || block evidence_publication_failed 'The returned evidence could not be published.' 'Inspect local storage.'
fi
artifact_stage=''
(cd -- "$artifact_current" && sha256sum --check --strict SHA256SUMS >/dev/null) \
  || block published_evidence_checksum_failed 'The published evidence failed final checksum verification.' 'Stop and inspect the local artifact lane.'
emit "state=pass;receipt=$receipt_name;evidence=$artifact_current" RETURN

stage='remote_cleanup'
timeout --foreground 120 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "rm -rf -- '$remote_root' && test ! -e '$remote_root'" >/dev/null \
  || block remote_cleanup_failed 'The private Script 09 transfer directory was not removed.' 'Remove only the reported private transfer directory.'
remote_created=false
timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1 || true
master_started=false
emit 'state=pass;private_transfer_removed=true' CLEANUP

case "$mode" in
  --run)
    printf '%s\n' \
      '' \
      'OPERATOR ACTION' \
      'UI address after forwarding: http://127.0.0.1:3385' \
      "Forward in a second terminal: ssh -N -T -L 127.0.0.1:3385:127.0.0.1:3385 $target" \
      'After human UI review, accept with:' \
      '  bash ./deployment/scripts/09_requalify-v1.3.1-on-emceedanko.sh --accept' \
      'To remove the isolated candidate without acceptance, use:' \
      '  bash ./deployment/scripts/09_requalify-v1.3.1-on-emceedanko.sh --cleanup' \
      | tee -a "$report_path"
    ;;
  --accept)
    printf '%s\n' \
      '' \
      'OPERATOR ACTION' \
      'Remove the accepted isolated qualification runtime with:' \
      '  bash ./deployment/scripts/09_requalify-v1.3.1-on-emceedanko.sh --cleanup' \
      | tee -a "$report_path"
    ;;
esac
emit "state=pass;mode=${mode#--};report_path=$report_path" SUMMARY
result pass | tee -a "$report_path"
