#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Promote the accepted corrected v1.3.1 web runtime to production port 3384
# without replacing or restarting the external application, Retrieval API,
# PostgreSQL cluster, corpus-v3 state, or boot posture.

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
readonly target_helper="$repo_root/deployment/assets/promote-corrected-runtime-on-emceedanko"
readonly application_root="$repo_root/local/artifacts/ishikawa-v1.3.1-candidate-current"
readonly runtime_root="$repo_root/local/artifacts/node-next-runtime-current"
readonly baseline_evidence="$repo_root/local/artifacts/emceedanko-v1.3.1-promotion-current"
readonly script12_evidence="$repo_root/local/artifacts/emceedanko-v1.3.1-runtime-requalification-current"
readonly default_artifact_parent="$repo_root/local/artifacts"
readonly artifact_parent="${ISHIKAWA_SCRIPT13_ARTIFACT_PARENT:-$default_artifact_parent}"
readonly artifact_basename='emceedanko-v1.3.1-corrected-runtime-promotion-current'
readonly artifact_current="$artifact_parent/$artifact_basename"
readonly default_report_root="$repo_root/local/reports/emceedanko-v1.3.1-corrected-runtime-promotion"
readonly expected_application_sha256='2dbf08b9e15fb4436e54ce492f2ad430129e794d33a1a45cdc6abf1a7b0b5f69'
readonly previous_runtime_archive_sha256='af95820f63798b39c6538e3f9b5653d47b07aed1d81625e2382485ff559eff3f'
readonly previous_image_id='sha256:79f39435329920c9c834e55cf5e18528540220111ae2a35d779a86d0b539d298'
readonly corrected_runtime_archive_sha256='b92dd71eb155493d7e331e85c92566eee113ed4c8f0eda605c1c3dd951b836e1'
readonly corrected_image_id='sha256:6c93bcb5ed22de92420c4de4892eecdd08f1badc8b19e4d6f4488711f8f7a31a'
readonly promotion_receipt_rel='state/reports/runtime-promotion/emceedanko-v1.3.1-corrected-runtime-promotion.txt'

target="${APPLICATION_HOST_TARGET:-DankoSurface_EmceeDanko}"
expected_hostname="${APPLICATION_HOST_EXPECTED_HOSTNAME:-EmceeDanko}"
expected_os_version="${APPLICATION_HOST_EXPECTED_OS_VERSION:-24.04}"
identity_file="${APPLICATION_HOST_IDENTITY_FILE:-}"
report_root="${ISHIKAWA_SCRIPT13_REPORT_ROOT:-$default_report_root}"
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
recovered_promotion_receipt=''
previous_runtime_archive=''
declare -a ssh_args=()

usage() {
  printf '%s\n' \
    'Usage: 13_promote-v1.3.1-corrected-runtime-on-emceedanko.sh --validate-only' \
    '       13_promote-v1.3.1-corrected-runtime-on-emceedanko.sh {--run|--accept|--rollback}' \
    '         [--target SSH_ALIAS] [--identity-file ABSOLUTE_PATH]' \
    '         [--report-root ABSOLUTE_PATH]'
}

result() {
  printf '\nSCRIPT RESULT\nscript_13_v1_3_1_corrected_runtime_promotion=%s\n' "$1"
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
  if [[ -n "$work_root" && "$work_root" == /tmp/ishikawa-script-13.* \
      && -d "$work_root" && ! -L "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  if [[ -n "$artifact_stage" \
      && "$artifact_stage" == "$artifact_parent"/."$artifact_basename".* \
      && -d "$artifact_stage" && ! -L "$artifact_stage" ]]; then
    rm -rf -- "$artifact_stage"
  fi
  if [[ -n "$artifact_probe" \
      && "$artifact_probe" == "$artifact_parent"/.emceedanko-v1.3.1-corrected-runtime-promotion-probe.* \
      && -d "$artifact_probe" && ! -L "$artifact_probe" ]]; then
    rmdir -- "$artifact_probe" 2>/dev/null || true
  fi
  exit "$status"
}

unexpected_error() {
  local status="$1" line="$2"
  block unexpected_command_failure \
    "Unhandled failure at Script 13 line $line with status $status." \
    'Review the complete retained report before retrying.' "$status"
}

trap cleanup EXIT
trap 'unexpected_error "$?" "$LINENO"' ERR
trap 'stage=interrupted; block signal_hangup "Script 13 received SIGHUP." "Review target restoration before retrying." 129' HUP
trap 'stage=interrupted; block signal_interrupt "Script 13 was interrupted." "Review target restoration before retrying." 130' INT
trap 'stage=interrupted; block signal_termination "Script 13 was terminated." "Review target restoration before retrying." 143' TERM

promotion_receipt_valid() {
  local receipt="$1"
  [[ -f "$receipt" && ! -L "$receipt" ]] \
    && grep -Fxq 'schema=ishikawa.emceedanko-v1.3.1-runtime-promotion.v1' "$receipt" \
    && grep -Fxq "application_archive_sha256=$expected_application_sha256" "$receipt" \
    && grep -Fxq "previous_image_id=$previous_image_id" "$receipt" \
    && grep -Fxq "runtime_archive_sha256=$corrected_runtime_archive_sha256" "$receipt" \
    && grep -Fxq "image_id=$corrected_image_id" "$receipt" \
    && grep -Fxq 'production_build_start=pass' "$receipt" \
    && grep -Fxq 'human_ui_acceptance=pending' "$receipt" \
    && grep -Fxq 'previous_runtime_rollback=available' "$receipt" \
    && grep -Fxq 'application_mutated=false' "$receipt" \
    && grep -Fxq 'database_mutated=false' "$receipt" \
    && grep -Fxq 'boot_autostart=false' "$receipt"
}

resolve_previous_runtime_archive() {
  local candidate candidate_sha
  local -a matches=()
  while IFS= read -r -d '' candidate; do
    [[ -f "$candidate" && ! -L "$candidate" && -r "$candidate" ]] || continue
    candidate_sha="$(sha256sum -- "$candidate" | awk '{print $1}')"
    [[ "$candidate_sha" == "$previous_runtime_archive_sha256" ]] || continue
    matches+=("$candidate")
  done < <(find "$repo_root/local/artifacts/superseded" -mindepth 2 -maxdepth 2 \
    -type f -name node-next-runtime-amd64.tar -print0 2>/dev/null | sort -z)
  (( ${#matches[@]} >= 1 )) || return 1
  previous_runtime_archive="${matches[0]}"
}

while (( $# > 0 )); do
  case "$1" in
    --target) [[ $# -ge 2 ]] || block target_missing 'SSH target value is missing.' 'Supply one target.'; target="$2"; shift 2 ;;
    --identity-file) [[ $# -ge 2 ]] || block identity_missing 'SSH identity value is missing.' 'Supply one path.'; identity_file="$2"; shift 2 ;;
    --report-root) [[ $# -ge 2 ]] || block report_root_missing 'Report root value is missing.' 'Supply one path.'; report_root="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) block argument_invalid "Unsupported argument: $1" 'Use --help.' 2 ;;
  esac
done
case "$mode" in --validate-only|--run|--accept|--rollback) ;; *) usage >&2; exit 2 ;; esac
[[ "$target" =~ ^[A-Za-z0-9_@.:-]+$ ]] \
  || block target_invalid 'SSH target is not bounded.' 'Use one configured target.'
[[ "$expected_hostname" == EmceeDanko && "$expected_os_version" == 24.04 ]] \
  || block frozen_target_changed 'Script 13 is frozen to EmceeDanko Ubuntu 24.04 AMD64.' 'Restore frozen target facts.'
[[ "$report_root" == /* && ! -L "$report_root" \
    && "$artifact_parent" == /* && "$artifact_parent" != / && ! -L "$artifact_parent" ]] \
  || block local_path_unsafe 'Report or artifact parent is unsafe.' 'Use absolute non-symlink paths.'
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] \
    || block identity_unsafe 'SSH identity is not a readable regular file.' 'Correct the identity or use SSH configuration.'
fi
for required in awk bash cmp cp cut date dd find grep jq kill mkdir mkfifo mktemp mv python3 rm rmdir scp sha256sum sleep sort ssh stat tail tar tee timeout tr; do
  command -v "$required" >/dev/null 2>&1 \
    || block "command_missing_${required}" "Required local command unavailable: $required." 'Restore the named prerequisite.'
done

stage='local_preflight'
for required_file in \
  "$target_helper" \
  "$application_root/ishikawa-v1.3.1.tar.gz" \
  "$application_root/ishikawa-v1.3.1.tar.gz.sha256" \
  "$application_root/SHA256SUMS" \
  "$runtime_root/image-identity.json" \
  "$runtime_root/node-next-runtime-amd64.tar" \
  "$runtime_root/SHA256SUMS" \
  "$baseline_evidence/acceptance-receipt.txt" \
  "$baseline_evidence/SHA256SUMS" \
  "$script12_evidence/qualification-receipt.txt" \
  "$script12_evidence/acceptance-receipt.txt" \
  "$script12_evidence/cleanup-receipt.txt" \
  "$script12_evidence/SHA256SUMS"; do
  [[ -f "$required_file" && ! -L "$required_file" && -r "$required_file" ]] \
    || block required_input_unsafe "Required exact input missing or unsafe: $required_file" 'Complete corrected Scripts 07, 08, and 12 first.'
done
if [[ "$mode" != --accept ]]; then
  resolve_previous_runtime_archive \
    || block previous_runtime_archive_unresolved \
      'An exact accepted rollback image archive could not be resolved from the preserved handoffs.' \
      'Restore the checksum-bound superseded runtime handoff before promotion or rollback.'
fi
bash -n "${BASH_SOURCE[0]}" "$target_helper" \
  || block shell_syntax_invalid 'Script 13 or its target helper failed shell parsing.' 'Correct the complete parse failure.'
grep -Fxq 'v1_3_1_corrected_runtime_promotion_helper=ready' < <(bash "$target_helper" --validate-only) \
  || block helper_validation_failed 'Corrected-runtime promotion helper omitted its ready marker.' 'Correct the helper.'
(cd -- "$application_root" && sha256sum --check --strict SHA256SUMS >/dev/null \
  && sha256sum --check --strict ishikawa-v1.3.1.tar.gz.sha256 >/dev/null) \
  || block application_handoff_checksum_failed 'Script 08 application handoff failed checksums.' 'Restore the exact handoff.'
(cd -- "$runtime_root" && sha256sum --check --strict SHA256SUMS >/dev/null) \
  || block runtime_handoff_checksum_failed 'Corrected Script 07 runtime handoff failed checksums.' 'Restore the exact handoff.'
(cd -- "$baseline_evidence" && sha256sum --check --strict SHA256SUMS >/dev/null) \
  || block baseline_evidence_checksum_failed 'Script 10 acceptance evidence failed checksums.' 'Inspect the accepted production evidence.'
(cd -- "$script12_evidence" && sha256sum --check --strict SHA256SUMS >/dev/null) \
  || block script12_evidence_checksum_failed 'Script 12 lifecycle evidence failed checksums.' 'Do not promote unbound evidence.'
application_sha256="$(sha256sum -- "$application_root/ishikawa-v1.3.1.tar.gz" | awk '{print $1}')"
runtime_archive_sha256="$(jq -r '.archive_sha256' "$runtime_root/image-identity.json")"
image_id="$(jq -r '.image_id' "$runtime_root/image-identity.json")"
[[ "$application_sha256" == "$expected_application_sha256" \
    && "$runtime_archive_sha256" == "$corrected_runtime_archive_sha256" \
    && "$(sha256sum -- "$runtime_root/node-next-runtime-amd64.tar" | awk '{print $1}')" == "$corrected_runtime_archive_sha256" \
    && "$image_id" == "$corrected_image_id" ]] \
  || block exact_handoff_identity_mismatch 'Corrected Script 07/08 exact identity mismatch.' 'Restore the exact corrected handoffs.'
grep -Fxq "application_archive_sha256=$expected_application_sha256" "$baseline_evidence/acceptance-receipt.txt" \
  && grep -Fxq "runtime_archive_sha256=$previous_runtime_archive_sha256" "$baseline_evidence/acceptance-receipt.txt" \
  && grep -Fxq "image_id=$previous_image_id" "$baseline_evidence/acceptance-receipt.txt" \
  && grep -Fxq 'human_ui_acceptance=accepted' "$baseline_evidence/acceptance-receipt.txt" \
  || block baseline_acceptance_invalid 'Script 10 acceptance evidence does not bind the current production runtime.' 'Inspect the accepted baseline evidence.'
grep -Fxq "application_archive_sha256=$expected_application_sha256" "$script12_evidence/qualification-receipt.txt" \
  && grep -Fxq "runtime_archive_sha256=$corrected_runtime_archive_sha256" "$script12_evidence/qualification-receipt.txt" \
  && grep -Fxq "image_id=$corrected_image_id" "$script12_evidence/qualification-receipt.txt" \
  && grep -Fxq 'frontier_cases=60/60' "$script12_evidence/qualification-receipt.txt" \
  && grep -Fxq 'human_ui_acceptance=accepted' "$script12_evidence/acceptance-receipt.txt" \
  && grep -Fxq "image_id=$corrected_image_id" "$script12_evidence/acceptance-receipt.txt" \
  && grep -Fxq 'mode=cleanup' "$script12_evidence/cleanup-receipt.txt" \
  && grep -Fxq 'state=pass' "$script12_evidence/cleanup-receipt.txt" \
  && grep -Fxq 'detail=candidate_removed=true' "$script12_evidence/cleanup-receipt.txt" \
  && grep -Fxq "image_id=$corrected_image_id" "$script12_evidence/cleanup-receipt.txt" \
  || block script12_lifecycle_incomplete 'Script 12 cleanup or prior acceptance is incomplete.' 'Complete and review the Script 12 lifecycle.'
helper_sha256="$(sha256sum -- "$target_helper" | awk '{print $1}')"

if [[ "$mode" == --validate-only ]]; then
  printf '%s\n' \
    'purpose=validate_emceedanko_v1_3_1_corrected_runtime_promotion' \
    "application_archive_sha256=$application_sha256" \
    "previous_image_id=$previous_image_id" \
    "previous_runtime_archive=$previous_runtime_archive" \
    "runtime_archive_sha256=$runtime_archive_sha256" \
    "image_id=$image_id" \
    'script12_lifecycle=complete;target_contact=false;scope=web_runtime_only;database_mutation=false;boot_autostart=false'
  result ready
  exit 0
fi

stage='report_setup'
mkdir -p -- "$report_root" "$artifact_parent" \
  || block local_output_parent_unwritable 'Local output parent could not be created.' 'Correct workspace permissions.'
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_root/promotion_${mode#--}_${timestamp}_XXXXXX.txt")" \
  || block report_creation_failed 'Script 13 report could not be created.' 'Correct report permissions.'
work_root="$(mktemp -d /tmp/ishikawa-script-13.XXXXXX)" \
  || block workspace_creation_failed 'Private local workspace could not be created.' 'Correct /tmp.'
emit() { printf '[%s] %s\n' "$2" "$1" | tee -a "$report_path"; }
emit "report_path=$report_path;state=start;mode=${mode#--}" READINESS
emit "application_archive_sha256=$application_sha256;previous_image_id=$previous_image_id;runtime_archive_sha256=$runtime_archive_sha256;image_id=$image_id;helper_sha256=$helper_sha256" READINESS
emit 'application_mutation=false;retrieval_api_restart=false;postgresql_restart=false;database_mutation=false;schema_mutation=false;corpus_mutation=false;boot_autostart_change=false' BOUNDARY
artifact_probe="$artifact_parent/.emceedanko-v1.3.1-corrected-runtime-promotion-probe.${timestamp}.$$"
mkdir -- "$artifact_probe" \
  || block artifact_parent_unwritable 'Local evidence lane is not writable.' 'Correct it before target contact.'
rmdir -- "$artifact_probe" \
  || block artifact_probe_cleanup_failed 'Empty evidence probe could not be removed.' 'Inspect the artifact lane.'
artifact_probe=''
if [[ -e "$artifact_current" || -L "$artifact_current" ]]; then
  [[ -d "$artifact_current" && ! -L "$artifact_current" ]] \
    || block current_evidence_unsafe 'Current corrected-promotion evidence path is unsafe.' 'Inspect it before target contact.'
  (cd -- "$artifact_current" && sha256sum --check --strict SHA256SUMS >/dev/null) \
    || block current_evidence_checksum_failed 'Current corrected-promotion evidence failed checksums.' 'Inspect it before target contact.'
  if [[ "$mode" != --run && -f "$artifact_current/promotion-receipt.txt" ]]; then
    promotion_receipt_valid "$artifact_current/promotion-receipt.txt" \
      || block current_promotion_receipt_invalid 'Current corrected-promotion receipt is incomplete.' 'Inspect local evidence.'
  fi
fi
emit 'state=pass;report_lane=writable;evidence_lane=writable' READINESS

stage='payload_assembly'
payload_root="$work_root/payload"
extract_root="$work_root/application"
mkdir -m 0700 -- "$payload_root" "$extract_root"
tar -xzf "$application_root/ishikawa-v1.3.1.tar.gz" -C "$extract_root"
installed_source="$extract_root/ishikawa-v1.3.1/application/payload"
[[ -d "$installed_source/application/web" && -f "$installed_source/config/product.yaml" ]] \
  || block application_payload_layout_invalid 'The exact application archive omitted the installed web layout.' 'Restore Script 08 handoff.'
(
  cd -- "$installed_source"
  {
    find application/web/app application/web/components application/web/lib application/web/public -type f -print
    printf '%s\n' application/web/package.json application/web/next.config.mjs config/product.yaml
  } | sort >"$payload_root/web-layout-paths.txt"
  while IFS= read -r path; do sha256sum -- "$path"; done \
    <"$payload_root/web-layout-paths.txt" >"$payload_root/web-layout-SHA256SUMS"
  sha256sum --check --strict "$payload_root/web-layout-SHA256SUMS" >/dev/null
)
cp -- "$target_helper" "$payload_root/promote-corrected-runtime-on-emceedanko"
cp -- "$runtime_root/image-identity.json" "$payload_root/"
cp -- "$baseline_evidence/acceptance-receipt.txt" "$payload_root/baseline-acceptance-receipt.txt"
cp -- "$script12_evidence/qualification-receipt.txt" \
  "$script12_evidence/acceptance-receipt.txt" \
  "$script12_evidence/cleanup-receipt.txt" "$payload_root/"
chmod 0755 "$payload_root/promote-corrected-runtime-on-emceedanko"
(
  cd -- "$payload_root"
  while IFS= read -r name; do sha256sum -- "$name"; done < <(
    find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' | sort
  ) >SHA256SUMS
  sha256sum --check --strict SHA256SUMS >/dev/null
)
payload_archive="$work_root/script-13-payload.tar.gz"
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime='UTC 1970-01-01' \
  -czf "$payload_archive" -C "$work_root" payload
payload_sha256="$(sha256sum -- "$payload_archive" | awk '{print $1}')"
emit "state=pass;payload_sha256=$payload_sha256;transfer_bytes=$(stat -Lc %s -- "$payload_archive");installed_web_manifest=exact" PAYLOAD

stage='authentication'
emit 'state=waiting_for_ssh_private_key_passphrase_or_target_sudo_if_prompted' AUTHENTICATION
control_path="/tmp/is13-${timestamp}-%C"
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
remote_root="/tmp/ishikawa-runtime-promotion-${timestamp}-$$"
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" >/dev/null \
  || block remote_directory_failed 'Private target directory could not be created.' 'Review target permissions.'
remote_created=true
timeout --foreground 300 scp "${ssh_args[@]}" "$payload_archive" "$target:$remote_root/" >/dev/null \
  || block transfer_failed 'Script 13 payload transfer failed.' 'Correct SSH transport.'
timeout --foreground 180 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && printf '%s  %s\n' '$payload_sha256' script-13-payload.tar.gz | sha256sum --check --strict - >/dev/null && tar -xzf script-13-payload.tar.gz && cd payload && sha256sum --check --strict SHA256SUMS >/dev/null" \
  || block transferred_payload_invalid 'Target rejected payload checksums.' 'Correct transfer; no target action ran.'
if [[ "$mode" != --accept ]]; then
  stage='runtime_archive_transfer_preflight'
  previous_runtime_bytes="$(stat -Lc %s -- "$previous_runtime_archive")"
  corrected_runtime_bytes="$(stat -Lc %s -- "$runtime_root/node-next-runtime-amd64.tar")"
  required_transfer_bytes=$(( previous_runtime_bytes + corrected_runtime_bytes + 67108864 ))
  target_available_bytes="$(timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
    "df -PB1 '$remote_root' | awk 'NR == 2 {print \$4}'" 2>/dev/null || true)"
  [[ "$target_available_bytes" =~ ^[0-9]+$ && "$target_available_bytes" -ge "$required_transfer_bytes" ]] \
    || block target_transfer_capacity_insufficient \
      "Target temporary storage has ${target_available_bytes:-unknown} bytes available; ${required_transfer_bytes} bytes are required." \
      'Free bounded target temporary storage and rerun; production was not changed.'
  stage='runtime_archive_transfer'
  timeout --foreground 900 scp "${ssh_args[@]}" "$previous_runtime_archive" \
    "$target:$remote_root/payload/previous-node-next-runtime-amd64.tar" >/dev/null \
    || block previous_runtime_archive_transfer_failed 'The exact rollback image archive transfer failed.' 'Correct SSH transport and rerun; production was not changed.'
  timeout --foreground 900 scp "${ssh_args[@]}" "$runtime_root/node-next-runtime-amd64.tar" \
    "$target:$remote_root/payload/corrected-node-next-runtime-amd64.tar" >/dev/null \
    || block corrected_runtime_archive_transfer_failed 'The exact corrected image archive transfer failed.' 'Correct SSH transport and rerun; production was not changed.'
  timeout --foreground 300 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
    "cd '$remote_root/payload' && printf '%s  %s\n%s  %s\n' '$previous_runtime_archive_sha256' previous-node-next-runtime-amd64.tar '$corrected_runtime_archive_sha256' corrected-node-next-runtime-amd64.tar | sha256sum --check --strict - >/dev/null" \
    || block transferred_runtime_archive_invalid 'Target rejected an exact runtime archive checksum.' 'Correct transfer and rerun; production was not changed.'
  emit "state=pass;target_checksums=pass;runtime_archives=previous_and_corrected;transfer_bytes=$(( previous_runtime_bytes + corrected_runtime_bytes ))" TRANSFER
else
  emit 'state=pass;target_checksums=pass;runtime_archives=not_required_for_acceptance' TRANSFER
fi

if [[ "$mode" != --run && ! -f "$artifact_current/promotion-receipt.txt" ]]; then
  stage='promotion_receipt_recovery'
  recovered_promotion_receipt="$work_root/recovered-promotion-receipt.txt"
  timeout --foreground 60 scp "${ssh_args[@]}" \
    "$target:Documents/Ishikawa-v1.3.1/$promotion_receipt_rel" \
    "$recovered_promotion_receipt" >/dev/null \
    || block promotion_receipt_recovery_failed 'The durable target promotion receipt could not be recovered.' 'Preserve production state and inspect the target receipt.'
  promotion_receipt_valid "$recovered_promotion_receipt" \
    || block recovered_promotion_receipt_invalid 'The recovered target promotion receipt is incomplete.' 'Do not accept or roll back an unbound runtime.'
  emit 'state=pass;source=durable_target_runtime;content=promotion_receipt' RETURN
fi

stage="target_${mode#--}"
emit "state=start;mode=${mode#--};application_secret_prompts=false;database_secret_prompts=false" TARGET
stream_path="$work_root/target.stream"
mkfifo -m 0600 -- "$stream_path"
tee -a "$report_path" <"$stream_path" &
stream_pid="$!"
tty_input=/dev/null
[[ -t 0 ]] && tty_input=/dev/tty
timeout --foreground 2400 ssh -tt "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root/payload' && bash ./promote-corrected-runtime-on-emceedanko '$mode' --payload-root '$remote_root/payload' --result-path '$remote_root/payload/target-result.txt' --expected-hostname '$expected_hostname' --expected-os-version '$expected_os_version' --expected-architecture amd64 --expected-helper-sha256 '$helper_sha256'" \
  <"$tty_input" >"$stream_path" 2>&1 &
remote_pid="$!"
if wait "$remote_pid"; then remote_status=0; else remote_status="$?"; fi
remote_pid=''
if wait "$stream_pid"; then tee_status=0; else tee_status="$?"; fi
stream_pid=''
rm -f -- "$stream_path"
(( tee_status == 0 )) \
  || block report_stream_failed 'Live target report stream failed.' 'Restore the local report lane.'
if (( remote_status != 0 )); then
  [[ "$remote_status" != 124 ]] \
    || block target_action_timeout 'Target action exceeded its bounded timeout.' 'Review restoration and retained milestones.'
  nested_reason="$(tr -d '\r' <"$report_path" | sed -n 's/^reason=\([a-z0-9_]*\)$/\1/p' | tail -n 1)"
  block "${nested_reason:-target_action_failed}" \
    "Target ${mode#--} exited with status $remote_status." \
    'Correct every retained failure detail before retrying.' "$remote_status"
fi
case "$mode" in
  --run) marker='v1_3_1_corrected_runtime_promotion=pass'; receipt_name='promotion-receipt.txt' ;;
  --accept) marker='v1_3_1_corrected_runtime_promotion_acceptance=pass'; receipt_name='acceptance-receipt.txt' ;;
  --rollback) marker='v1_3_1_corrected_runtime_promotion_rollback=pass'; receipt_name='rollback-receipt.txt' ;;
esac
grep -Fqx "$marker" < <(tr -d '\r' <"$report_path") \
  || block target_pass_marker_missing 'Target omitted the exact pass marker.' 'Treat the action as incomplete.'

stage='receipt_return'
timeout --foreground 60 scp "${ssh_args[@]}" "$target:$remote_root/payload/target-result.txt" "$work_root/$receipt_name" >/dev/null \
  || block receipt_fetch_failed 'Target receipt could not be returned.' 'Preserve target state and review.'
grep -Fxq "application_archive_sha256=$expected_application_sha256" "$work_root/$receipt_name" \
  && grep -Fxq "runtime_archive_sha256=$corrected_runtime_archive_sha256" "$work_root/$receipt_name" \
  && grep -Fxq "image_id=$corrected_image_id" "$work_root/$receipt_name" \
  && grep -Fxq 'application_mutated=false' "$work_root/$receipt_name" \
  && grep -Fxq 'retrieval_api_restarted=false' "$work_root/$receipt_name" \
  && grep -Fxq 'postgresql_restarted=false' "$work_root/$receipt_name" \
  && grep -Fxq 'database_mutated=false' "$work_root/$receipt_name" \
  && grep -Fxq 'schema_mutated=false' "$work_root/$receipt_name" \
  && grep -Fxq 'corpus_mutated=false' "$work_root/$receipt_name" \
  && grep -Fxq 'boot_autostart=false' "$work_root/$receipt_name" \
  || block returned_receipt_invalid 'Returned receipt omitted exact identity or safety invariants.' 'Do not publish it.'
case "$mode" in
  --run)
    promotion_receipt_valid "$work_root/$receipt_name" \
      || block returned_promotion_receipt_invalid 'Promotion receipt omitted an exact production gate.' 'Do not publish it.' ;;
  --accept)
    grep -Fxq 'schema=ishikawa.emceedanko-v1.3.1-runtime-promotion-acceptance.v1' "$work_root/$receipt_name" \
      && grep -Fxq 'human_ui_acceptance=accepted' "$work_root/$receipt_name" \
      && grep -Fxq 'superseded_runtime_image_removed=true' "$work_root/$receipt_name" \
      || block returned_acceptance_receipt_invalid 'Acceptance receipt omitted final runtime retirement proof.' 'Do not publish it.' ;;
  --rollback)
    grep -Fxq 'schema=ishikawa.emceedanko-v1.3.1-runtime-promotion-action.v1' "$work_root/$receipt_name" \
      && grep -Fxq 'mode=rollback' "$work_root/$receipt_name" \
      && grep -Fxq 'state=pass' "$work_root/$receipt_name" \
      && grep -Fxq 'detail=previous_runtime_restored=true' "$work_root/$receipt_name" \
      || block returned_rollback_receipt_invalid 'Rollback receipt omitted exact restoration proof.' 'Do not publish it.' ;;
esac

stage='local_evidence_publication'
artifact_stage="$artifact_parent/.${artifact_basename}.${timestamp}.$$"
mkdir -- "$artifact_stage" \
  || block evidence_stage_creation_failed 'Evidence stage could not be created.' 'Correct the local artifact lane.'
if [[ -e "$artifact_current" || -L "$artifact_current" ]]; then
  [[ -d "$artifact_current" && ! -L "$artifact_current" ]] \
    || block current_evidence_unsafe 'Current evidence is unsafe.' 'Inspect it.'
  (cd -- "$artifact_current" && sha256sum --check --strict SHA256SUMS >/dev/null) \
    || block current_evidence_checksum_failed 'Current evidence failed checksums.' 'Inspect it.'
  if [[ "$mode" != --run ]]; then
    copy_flat_evidence "$artifact_current" "$artifact_stage" \
      || block current_evidence_copy_failed 'Current promotion evidence could not be copied and verified byte-for-byte.' 'Inspect the artifact lane.'
  fi
fi
if [[ -n "$recovered_promotion_receipt" ]]; then
  cp -- "$recovered_promotion_receipt" "$artifact_stage/promotion-receipt.txt" \
    || block recovered_promotion_publication_failed 'Recovered promotion receipt could not be staged.' 'Preserve target state and inspect local storage.'
fi
if [[ "$mode" != --run && ! -f "$artifact_stage/promotion-receipt.txt" ]]; then
  block promotion_receipt_missing 'Acceptance or rollback requires the exact promotion receipt.' 'Run Script 13 --run first.'
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
  evidence_backup="$artifact_parent/.emceedanko-v1.3.1-corrected-runtime-promotion-previous.${timestamp}.$$"
  mv -- "$artifact_current" "$evidence_backup"
  if ! mv -- "$artifact_stage" "$artifact_current"; then
    mv -- "$evidence_backup" "$artifact_current"
    block evidence_publication_failed 'Prior evidence restored after publication failure.' 'Inspect local storage.'
  fi
  rm -rf -- "$evidence_backup"
else
  mv -- "$artifact_stage" "$artifact_current" \
    || block evidence_publication_failed 'Evidence could not be published.' 'Inspect local storage.'
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
      'Corrected production UI on EmceeDanko: http://127.0.0.1:3384' \
      'After human UI review, accept with:' \
      '  bash ./deployment/scripts/13_promote-v1.3.1-corrected-runtime-on-emceedanko.sh --accept' \
      'To restore the previous runtime before acceptance, use:' \
      '  bash ./deployment/scripts/13_promote-v1.3.1-corrected-runtime-on-emceedanko.sh --rollback' \
      | tee -a "$report_path" ;;
esac
emit "state=pass;mode=${mode#--};report_path=$report_path" SUMMARY
result pass | tee -a "$report_path"
