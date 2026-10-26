#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Purpose:
#   Promote the exact accepted v1.3.1 bytes into the active EmceeDanko runtime.
# Mental model:
#   Verify the immutable application, image, and complete Script 09 evidence;
#   transfer one private payload; run one attended target lifecycle action; and
#   atomically publish its content-free receipt locally.
# Inputs or prerequisites:
#   Completed Script 09 cleanup, strict SSH access, exact Script 07/08
#   handoffs, externally managed model tunnels, and attended secrets for run
#   or rollback.
# Outputs or artifact lane:
#   Reports under local/reports/emceedanko-v1.3.1-promotion and verified
#   lifecycle receipts under local/artifacts/emceedanko-v1.3.1-promotion-current.
# Usage:
#   bash ./deployment/scripts/10_promote-v1.3.1-on-emceedanko.sh --validate-only
#   bash ./deployment/scripts/10_promote-v1.3.1-on-emceedanko.sh --run
#   bash ./deployment/scripts/10_promote-v1.3.1-on-emceedanko.sh --accept
#   bash ./deployment/scripts/10_promote-v1.3.1-on-emceedanko.sh --rollback

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
readonly target_helper="$repo_root/deployment/assets/promote-v1.3.1-on-emceedanko"
readonly default_application_root="$repo_root/local/artifacts/ishikawa-v1.3.1-candidate-current"
readonly default_runtime_root="$repo_root/local/artifacts/node-next-runtime-current"
readonly default_script09_evidence="$repo_root/local/artifacts/emceedanko-v1.3.1-requalification-current"
readonly application_root="${ISHIKAWA_SCRIPT10_APPLICATION_ROOT:-$default_application_root}"
readonly runtime_root="${ISHIKAWA_SCRIPT10_RUNTIME_ROOT:-$default_runtime_root}"
readonly script09_evidence="${ISHIKAWA_SCRIPT10_SCRIPT09_EVIDENCE:-$default_script09_evidence}"
readonly default_artifact_parent="$repo_root/local/artifacts"
readonly artifact_parent="${ISHIKAWA_SCRIPT10_ARTIFACT_PARENT:-$default_artifact_parent}"
readonly artifact_current="$artifact_parent/emceedanko-v1.3.1-promotion-current"
readonly default_report_root="$repo_root/local/reports/emceedanko-v1.3.1-promotion"
readonly expected_application_sha256='2dbf08b9e15fb4436e54ce492f2ad430129e794d33a1a45cdc6abf1a7b0b5f69'
readonly expected_runtime_archive_sha256='af95820f63798b39c6538e3f9b5653d47b07aed1d81625e2382485ff559eff3f'
readonly expected_image_id='sha256:79f39435329920c9c834e55cf5e18528540220111ae2a35d779a86d0b539d298'

target="${APPLICATION_HOST_TARGET:-DankoSurface_EmceeDanko}"
expected_hostname="${APPLICATION_HOST_EXPECTED_HOSTNAME:-EmceeDanko}"
expected_os_version="${APPLICATION_HOST_EXPECTED_OS_VERSION:-24.04}"
identity_file="${APPLICATION_HOST_IDENTITY_FILE:-}"
report_root="${ISHIKAWA_SCRIPT10_REPORT_ROOT:-$default_report_root}"
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
declare -a ssh_args=()

usage() {
  printf '%s\n' \
    'Usage: 10_promote-v1.3.1-on-emceedanko.sh --validate-only' \
    '       10_promote-v1.3.1-on-emceedanko.sh {--run|--accept|--rollback}' \
    '         [--target SSH_ALIAS] [--identity-file ABSOLUTE_PATH]' \
    '         [--report-root ABSOLUTE_PATH]'
}

result() { printf '\nSCRIPT RESULT\nscript_10_v1_3_1_promotion=%s\n' "$1"; }

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

copy_flat_evidence() {
  local source_root="$1" destination_root="$2" source_path destination_path
  [[ -d "$source_root" && ! -L "$source_root" \
      && -d "$destination_root" && ! -L "$destination_root" \
      && -z "$(find "$source_root" -mindepth 1 -maxdepth 1 ! -type f -print -quit)" ]] \
    || return 1
  while IFS= read -r -d '' source_path; do
    destination_path="$destination_root/${source_path##*/}"
    [[ ! -e "$destination_path" && ! -L "$destination_path" ]] || return 1
    dd if="$source_path" of="$destination_path" bs=1M status=none || return 1
    cmp -- "$source_path" "$destination_path" >/dev/null || return 1
  done < <(find "$source_root" -mindepth 1 -maxdepth 1 -type f -print0 | sort -z)
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
  if [[ -n "$work_root" && "$work_root" == /tmp/ishikawa-script-10.* \
      && -d "$work_root" && ! -L "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  if [[ -n "$artifact_stage" \
      && "$artifact_stage" == "$artifact_parent"/.emceedanko-v1.3.1-promotion-current.* \
      && -d "$artifact_stage" && ! -L "$artifact_stage" ]]; then
    rm -rf -- "$artifact_stage"
  fi
  if [[ -n "$artifact_probe" \
      && "$artifact_probe" == "$artifact_parent"/.emceedanko-v1.3.1-promotion-probe.* \
      && -d "$artifact_probe" && ! -L "$artifact_probe" ]]; then
    rmdir -- "$artifact_probe" 2>/dev/null || true
  fi
  exit "$status"
}

unexpected_error() {
  local status="$1" line="$2"
  block unexpected_command_failure "Unhandled failure at Script 10 line $line with status $status." \
    'Review the complete retained report before retrying.' "$status"
}

trap cleanup EXIT
trap 'unexpected_error "$?" "$LINENO"' ERR
trap 'stage=interrupted; block signal_hangup "Script 10 received SIGHUP." "Review target restoration and rerun only after reconciliation." 129' HUP
trap 'stage=interrupted; block signal_interrupt "Script 10 was interrupted." "Review target restoration and rerun only after reconciliation." 130' INT
trap 'stage=interrupted; block signal_termination "Script 10 was terminated." "Review target restoration and rerun only after reconciliation." 143' TERM

while (( $# > 0 )); do
  case "$1" in
    --target) target="${2:-}"; shift 2 ;;
    --identity-file) identity_file="${2:-}"; shift 2 ;;
    --report-root) report_root="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) block argument_invalid "Unsupported argument: $1" 'Use --help.' 2 ;;
  esac
done
case "$mode" in --validate-only|--run|--accept|--rollback) ;; *) usage >&2; exit 2 ;; esac
[[ "$target" =~ ^[A-Za-z0-9_@.:-]+$ ]] || block target_invalid 'SSH target is not bounded.' 'Use one configured target.'
[[ "$expected_hostname" == EmceeDanko && "$expected_os_version" == 24.04 ]] \
  || block frozen_target_changed 'Script 10 is frozen to EmceeDanko Ubuntu 24.04 AMD64.' 'Restore frozen target facts.'
[[ "$report_root" == /* && ! -L "$report_root" \
    && "$artifact_parent" == /* && "$artifact_parent" != / && ! -L "$artifact_parent" ]] \
  || block local_path_unsafe 'Report or artifact parent is unsafe.' 'Use absolute non-symlink paths.'
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] \
    || block identity_unsafe 'SSH identity is not a readable regular file.' 'Correct the identity or use SSH configuration.'
fi
for required in awk bash cmp cp date dd find grep jq kill mkdir mkfifo mktemp mv python3 rm rmdir scp sha256sum sleep sort ssh stat tar tee timeout tr; do
  command -v "$required" >/dev/null 2>&1 || block "command_missing_${required}" "Required local command unavailable: $required." 'Restore the named prerequisite.'
done

stage='local_preflight'
for required_file in \
  "$target_helper" \
  "$application_root/ishikawa-v1.3.1.tar.gz" \
  "$application_root/ishikawa-v1.3.1.tar.gz.sha256" \
  "$application_root/SHA256SUMS" \
  "$runtime_root/image-identity.json" \
  "$runtime_root/SHA256SUMS" \
  "$script09_evidence/qualification-receipt.txt" \
  "$script09_evidence/acceptance-receipt.txt" \
  "$script09_evidence/cleanup-receipt.txt" \
  "$script09_evidence/SHA256SUMS"; do
  [[ -f "$required_file" && ! -L "$required_file" && -r "$required_file" ]] \
    || block required_input_unsafe "Required exact input missing or unsafe: $required_file" 'Complete Scripts 07 through 09 first.'
done
bash -n "${BASH_SOURCE[0]}" "$target_helper" \
  || block shell_syntax_invalid 'Script 10 or target helper failed shell parsing.' 'Correct the complete parse failure.'
grep -Fxq 'v1_3_1_promotion_helper=ready' < <(bash "$target_helper" --validate-only) \
  || block helper_validation_failed 'Promotion helper omitted its ready marker.' 'Correct the helper.'
(cd -- "$application_root" && sha256sum --check --strict SHA256SUMS >/dev/null \
  && sha256sum --check --strict ishikawa-v1.3.1.tar.gz.sha256 >/dev/null) \
  || block application_handoff_checksum_failed 'Script 08 handoff failed checksums.' 'Restore the exact handoff.'
(cd -- "$runtime_root" && sha256sum --check --strict SHA256SUMS >/dev/null) \
  || block runtime_handoff_checksum_failed 'Script 07 handoff failed checksums.' 'Restore the exact handoff.'
(cd -- "$script09_evidence" && sha256sum --check --strict SHA256SUMS >/dev/null) \
  || block script09_evidence_checksum_failed 'Script 09 evidence failed its manifest.' 'Do not promote unbound evidence.'
application_sha256="$(sha256sum -- "$application_root/ishikawa-v1.3.1.tar.gz" | awk '{print $1}')"
runtime_archive_sha256="$(jq -r '.archive_sha256' "$runtime_root/image-identity.json")"
image_id="$(jq -r '.image_id' "$runtime_root/image-identity.json")"
[[ "$application_sha256" == "$expected_application_sha256" \
    && "$runtime_archive_sha256" == "$expected_runtime_archive_sha256" \
    && "$image_id" == "$expected_image_id" ]] \
  || block exact_handoff_identity_mismatch 'Script 07/08 exact identity mismatch.' 'Restore exact handoffs.'
grep -Fxq "application_archive_sha256=$expected_application_sha256" "$script09_evidence/qualification-receipt.txt" \
  && grep -Fxq "runtime_archive_sha256=$expected_runtime_archive_sha256" "$script09_evidence/qualification-receipt.txt" \
  && grep -Fxq "image_id=$expected_image_id" "$script09_evidence/qualification-receipt.txt" \
  && grep -Fxq 'frontier_cases=60/60' "$script09_evidence/qualification-receipt.txt" \
  && grep -Fxq "application_archive_sha256=$expected_application_sha256" "$script09_evidence/acceptance-receipt.txt" \
  && grep -Fxq "runtime_archive_sha256=$expected_runtime_archive_sha256" "$script09_evidence/acceptance-receipt.txt" \
  && grep -Fxq "image_id=$expected_image_id" "$script09_evidence/acceptance-receipt.txt" \
  && grep -Fxq 'human_ui_acceptance=accepted' "$script09_evidence/acceptance-receipt.txt" \
  && grep -Fxq 'mode=cleanup' "$script09_evidence/cleanup-receipt.txt" \
  && grep -Fxq 'state=pass' "$script09_evidence/cleanup-receipt.txt" \
  && grep -Fxq 'detail=candidate_removed=true' "$script09_evidence/cleanup-receipt.txt" \
  && grep -Fxq "application_archive_sha256=$expected_application_sha256" "$script09_evidence/cleanup-receipt.txt" \
  && grep -Fxq "runtime_archive_sha256=$expected_runtime_archive_sha256" "$script09_evidence/cleanup-receipt.txt" \
  && grep -Fxq "image_id=$expected_image_id" "$script09_evidence/cleanup-receipt.txt" \
  || block script09_lifecycle_incomplete 'Script 09 cleanup or prior acceptance is incomplete.' 'Run Script 09 --cleanup and review its receipt.'
helper_sha256="$(sha256sum -- "$target_helper" | awk '{print $1}')"

if [[ "$mode" == --validate-only ]]; then
  printf '%s\n' \
    'purpose=validate_emceedanko_v1_3_1_promotion' \
    "application_archive_sha256=$application_sha256" \
    "runtime_archive_sha256=$runtime_archive_sha256" \
    "image_id=$image_id" \
    'script09_lifecycle=complete;target_contact=false;database_mutation=false;boot_autostart=false'
  result ready
  exit 0
fi

stage='report_setup'
mkdir -p -- "$report_root" "$artifact_parent" \
  || block local_output_parent_unwritable 'Local output parent could not be created.' 'Correct workspace permissions.'
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_root/promotion_${mode#--}_${timestamp}_XXXXXX.txt")" \
  || block report_creation_failed 'Script 10 report could not be created.' 'Correct report permissions.'
work_root="$(mktemp -d /tmp/ishikawa-script-10.XXXXXX)" \
  || block workspace_creation_failed 'Private local workspace could not be created.' 'Correct /tmp.'
emit() { printf '[%s] %s\n' "$2" "$1" | tee -a "$report_path"; }
emit "report_path=$report_path;state=start;mode=${mode#--}" READINESS
emit "application_archive_sha256=$application_sha256;runtime_archive_sha256=$runtime_archive_sha256;image_id=$image_id;helper_sha256=$helper_sha256" READINESS
emit 'database_mutation=false;schema_mutation=false;corpus_mutation=false;boot_autostart_change=false' BOUNDARY
artifact_probe="$artifact_parent/.emceedanko-v1.3.1-promotion-probe.${timestamp}.$$"
mkdir -- "$artifact_probe" || block artifact_parent_unwritable 'Local evidence lane is not writable.' 'Correct it before target contact.'
rmdir -- "$artifact_probe" || block artifact_probe_cleanup_failed 'Empty evidence probe could not be removed.' 'Inspect the artifact lane.'
artifact_probe=''
if [[ -e "$artifact_current" || -L "$artifact_current" ]]; then
  [[ -d "$artifact_current" && ! -L "$artifact_current" ]] \
    || block current_evidence_unsafe 'Current promotion evidence path is unsafe.' 'Inspect it before target contact.'
  (cd -- "$artifact_current" && sha256sum --check --strict SHA256SUMS >/dev/null) \
    || block current_evidence_checksum_failed 'Current promotion evidence failed checksums.' 'Inspect it before target contact.'
fi
emit 'state=pass;report_lane=writable;evidence_lane=writable' READINESS

stage='payload_assembly'
payload_root="$work_root/payload"
mkdir -m 0700 -- "$payload_root"
cp -- "$target_helper" "$payload_root/promote-v1.3.1-on-emceedanko"
cp -- "$application_root/ishikawa-v1.3.1.tar.gz" "$payload_root/"
cp -- "$runtime_root/image-identity.json" "$payload_root/"
cp -- "$script09_evidence/qualification-receipt.txt" \
  "$script09_evidence/acceptance-receipt.txt" \
  "$script09_evidence/cleanup-receipt.txt" "$payload_root/"
chmod 0755 "$payload_root/promote-v1.3.1-on-emceedanko"
(
  cd -- "$payload_root"
  while IFS= read -r name; do sha256sum -- "$name"; done < <(
    find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' | sort
  ) >SHA256SUMS
  sha256sum --check --strict SHA256SUMS >/dev/null
)
payload_archive="$work_root/script-10-payload.tar.gz"
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime='UTC 1970-01-01' \
  -czf "$payload_archive" -C "$work_root" payload
payload_sha256="$(sha256sum -- "$payload_archive" | awk '{print $1}')"
emit "state=pass;payload_sha256=$payload_sha256;transfer_bytes=$(stat -Lc %s -- "$payload_archive")" PAYLOAD

stage='authentication'
emit 'state=waiting_for_ssh_private_key_passphrase_if_prompted' AUTHENTICATION
control_path="/tmp/is10-${timestamp}-%C"
ssh_args=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 \
  -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto \
  -o "ControlPath=$control_path" -o ControlPersist=300)
[[ -z "$identity_file" ]] || ssh_args+=(-i "$identity_file" -o IdentitiesOnly=yes)
ssh -G "${ssh_args[@]}" "$target" >/dev/null \
  || block ssh_configuration_invalid 'OpenSSH rejected the target configuration.' 'Correct SSH configuration.'
timeout --foreground 120 ssh "${ssh_args[@]}" -Nf "$target" \
  || block ssh_master_start_failed 'SSH authentication failed.' 'Correct SSH access.'
master_started=true
timeout --foreground 10 ssh "${ssh_args[@]}" -O check "$target" >/dev/null \
  || block ssh_master_check_failed 'SSH control master was not ready.' 'Correct SSH access.'
emit 'state=pass;control_master=ready' AUTHENTICATION

stage='target_transfer'
remote_root="/tmp/ishikawa-promotion-${timestamp}-$$"
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" >/dev/null \
  || block remote_directory_failed 'Private target directory could not be created.' 'Review target permissions.'
remote_created=true
timeout --foreground 300 scp "${ssh_args[@]}" "$payload_archive" "$target:$remote_root/" >/dev/null \
  || block transfer_failed 'Script 10 payload transfer failed.' 'Correct SSH transport.'
timeout --foreground 180 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && printf '%s  %s\n' '$payload_sha256' script-10-payload.tar.gz | sha256sum --check --strict - >/dev/null && tar -xzf script-10-payload.tar.gz && cd payload && sha256sum --check --strict SHA256SUMS >/dev/null" \
  || block transferred_payload_invalid 'Target rejected payload checksums.' 'Correct transfer; no target action ran.'
emit 'state=pass;target_checksums=pass' TRANSFER

stage="target_${mode#--}"
emit "state=start;mode=${mode#--};interactive_prompts=$([[ "$mode" == --accept ]] && printf false || printf true)" TARGET
stream_path="$work_root/target.stream"
mkfifo -m 0600 -- "$stream_path"
tee -a "$report_path" <"$stream_path" &
stream_pid="$!"
tty_input=/dev/null
[[ -t 0 ]] && tty_input=/dev/tty
remote_timeout=1200
[[ "$mode" == --run ]] && remote_timeout=3600
timeout --foreground "$remote_timeout" ssh -tt "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root/payload' && bash ./promote-v1.3.1-on-emceedanko '$mode' --payload-root '$remote_root/payload' --result-path '$remote_root/payload/target-result.txt' --expected-hostname '$expected_hostname' --expected-os-version '$expected_os_version' --expected-architecture amd64 --expected-helper-sha256 '$helper_sha256'" \
  <"$tty_input" >"$stream_path" 2>&1 &
remote_pid="$!"
if wait "$remote_pid"; then remote_status=0; else remote_status="$?"; fi
remote_pid=''
if wait "$stream_pid"; then tee_status=0; else tee_status="$?"; fi
stream_pid=''
rm -f -- "$stream_path"
(( tee_status == 0 )) || block report_stream_failed 'Live target report stream failed.' 'Restore the local report lane.'
if (( remote_status != 0 )); then
  [[ "$remote_status" != 124 ]] || block target_action_timeout 'Target action exceeded its bounded timeout.' 'Review restoration and retained milestones.'
  nested_reason="$(tr -d '\r' <"$report_path" | sed -n 's/^reason=\([a-z0-9_]*\)$/\1/p' | tail -n 1)"
  block "${nested_reason:-target_action_failed}" "Target ${mode#--} exited with status $remote_status." 'Correct every retained failure detail before retrying.' "$remote_status"
fi
case "$mode" in
  --run) marker='v1_3_1_promotion=pass'; receipt_name='promotion-receipt.txt' ;;
  --accept) marker='v1_3_1_promotion_acceptance=pass'; receipt_name='acceptance-receipt.txt' ;;
  --rollback) marker='v1_3_1_promotion_rollback=pass'; receipt_name='rollback-receipt.txt' ;;
esac
grep -Fqx "$marker" < <(tr -d '\r' <"$report_path") \
  || block target_pass_marker_missing 'Target omitted exact pass marker.' 'Treat action as incomplete.'

stage='receipt_return'
timeout --foreground 60 scp "${ssh_args[@]}" "$target:$remote_root/payload/target-result.txt" "$work_root/$receipt_name" >/dev/null \
  || block receipt_fetch_failed 'Target receipt could not be returned.' 'Preserve target state and review.'
grep -Fxq "application_archive_sha256=$expected_application_sha256" "$work_root/$receipt_name" \
  && grep -Fxq "runtime_archive_sha256=$expected_runtime_archive_sha256" "$work_root/$receipt_name" \
  && grep -Fxq "image_id=$expected_image_id" "$work_root/$receipt_name" \
  && grep -Fxq 'database_mutated=false' "$work_root/$receipt_name" \
  && grep -Fxq 'schema_mutated=false' "$work_root/$receipt_name" \
  && grep -Fxq 'corpus_mutated=false' "$work_root/$receipt_name" \
  && grep -Fxq 'boot_autostart=false' "$work_root/$receipt_name" \
  || block returned_receipt_invalid 'Returned receipt omitted exact identity or safety invariant.' 'Do not publish it.'
case "$mode" in
  --run)
    grep -Fxq 'schema=ishikawa.emceedanko-v1.3.1-promotion.v1' "$work_root/$receipt_name" \
      && grep -Fxq 'human_ui_acceptance=pending' "$work_root/$receipt_name" \
      && grep -Fxq 'rollback_v1_3=available' "$work_root/$receipt_name" \
      && grep -Fxq 'database_state=moved_unchanged' "$work_root/$receipt_name" \
      || block returned_promotion_receipt_invalid 'Promotion receipt omitted an exact gate.' 'Do not publish it.' ;;
  --accept)
    grep -Fxq 'schema=ishikawa.emceedanko-v1.3.1-promotion-acceptance.v1' "$work_root/$receipt_name" \
      && grep -Fxq 'human_ui_acceptance=accepted' "$work_root/$receipt_name" \
      && grep -Fxq 'superseded_image_removed=true' "$work_root/$receipt_name" \
      || block returned_acceptance_receipt_invalid 'Acceptance receipt omitted final retirement proof.' 'Do not publish it.' ;;
  --rollback)
    grep -Fxq 'schema=ishikawa.emceedanko-v1.3.1-promotion-action.v1' "$work_root/$receipt_name" \
      && grep -Fxq 'mode=rollback' "$work_root/$receipt_name" \
      && grep -Fxq 'state=pass' "$work_root/$receipt_name" \
      && grep -Fxq 'detail=accepted_v1_3_restored=true' "$work_root/$receipt_name" \
      || block returned_rollback_receipt_invalid 'Rollback receipt omitted exact restoration proof.' 'Do not publish it.' ;;
esac

stage='local_evidence_publication'
artifact_stage="$artifact_parent/.emceedanko-v1.3.1-promotion-current.${timestamp}.$$"
mkdir -- "$artifact_stage" || block evidence_stage_creation_failed 'Evidence stage could not be created.' 'Correct the local artifact lane.'
if [[ -e "$artifact_current" || -L "$artifact_current" ]]; then
  [[ -d "$artifact_current" && ! -L "$artifact_current" ]] \
    || block current_evidence_unsafe 'Current evidence is unsafe.' 'Inspect it.'
  (cd -- "$artifact_current" && sha256sum --check --strict SHA256SUMS >/dev/null) \
    || block current_evidence_checksum_failed 'Current evidence failed checksums.' 'Inspect it.'
  if [[ "$mode" != --run ]]; then
    copy_flat_evidence "$artifact_current" "$artifact_stage" \
      || block current_evidence_copy_failed 'The current flat promotion evidence could not be copied and verified byte-for-byte.' 'Inspect the artifact lane.'
  fi
fi
if [[ "$mode" != --run && ! -f "$artifact_stage/promotion-receipt.txt" ]]; then
  block promotion_receipt_missing 'Acceptance or rollback requires the local promotion receipt.' 'Run Script 10 --run first.'
fi
rm -f -- "$artifact_stage/SHA256SUMS"
cp -- "$work_root/$receipt_name" "$artifact_stage/$receipt_name" \
  || block lifecycle_receipt_publication_failed 'Lifecycle receipt could not be staged.' 'Inspect local artifacts.'
(
  cd -- "$artifact_stage"
  while IFS= read -r name; do sha256sum -- "$name"; done < <(
    find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' | sort
  ) >SHA256SUMS
  sha256sum --check --strict SHA256SUMS >/dev/null
)
if [[ -e "$artifact_current" || -L "$artifact_current" ]]; then
  evidence_backup="$artifact_parent/.emceedanko-v1.3.1-promotion-previous.${timestamp}.$$"
  mv -- "$artifact_current" "$evidence_backup"
  if ! mv -- "$artifact_stage" "$artifact_current"; then
    mv -- "$evidence_backup" "$artifact_current"
    block evidence_publication_failed 'Prior evidence restored after publication failure.' 'Inspect local storage.'
  fi
  rm -rf -- "$evidence_backup"
else
  mv -- "$artifact_stage" "$artifact_current" || block evidence_publication_failed 'Evidence could not be published.' 'Inspect local storage.'
fi
artifact_stage=''
(cd -- "$artifact_current" && sha256sum --check --strict SHA256SUMS >/dev/null) \
  || block published_evidence_checksum_failed 'Published evidence failed verification.' 'Stop and inspect it.'
emit "state=pass;receipt=$receipt_name;evidence=$artifact_current" RETURN

stage='remote_cleanup'
timeout --foreground 120 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "rm -rf -- '$remote_root' && test ! -e '$remote_root'" >/dev/null \
  || block remote_cleanup_failed 'Private transfer directory was not removed.' 'Remove only the reported directory.'
remote_created=false
timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1 || true
master_started=false
emit 'state=pass;private_transfer_removed=true' CLEANUP

case "$mode" in
  --run)
    printf '%s\n' '' 'OPERATOR ACTION' \
      'Promoted UI on EmceeDanko: http://127.0.0.1:3384' \
      'After human UI review, accept with:' \
      '  bash ./deployment/scripts/10_promote-v1.3.1-on-emceedanko.sh --accept' \
      'To restore v1.3 before acceptance, use:' \
      '  bash ./deployment/scripts/10_promote-v1.3.1-on-emceedanko.sh --rollback' | tee -a "$report_path" ;;
esac
emit "state=pass;mode=${mode#--};report_path=$report_path" SUMMARY
result pass | tee -a "$report_path"
