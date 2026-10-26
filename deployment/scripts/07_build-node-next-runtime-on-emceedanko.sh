#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Purpose:
#   Build the generic Linux AMD64 Node/Next runtime natively on EmceeDanko and
#   return its checksum-bound handoff to the local artifact lane.
#
# Mental model:
#   Validate the frozen local inputs, transfer only those inputs over one
#   attended strict-trust SSH session, run the unnumbered builder on the native
#   AMD64 host, verify the returned handoff independently, publish it locally,
#   and remove only the private remote transfer directory.
#
# Inputs or prerequisites:
#   Strict SSH trust for EmceeDanko, an attended operator SSH identity, native
#   Ubuntu 24.04 AMD64 Docker with buildx, at least 2 CPUs, 4 GiB available
#   memory, 1 GiB /tmp, 2 GiB build-workspace, and 5 GiB Docker capacity, plus
#   outbound Docker Hub and npm-registry access during the build.
#
# Outputs or artifact lane:
#   local/artifacts/node-next-runtime-current and a content-free report under
#   local/reports/emceedanko-node-next-runtime-build. The exact image remains
#   loaded on EmceeDanko for v1.3.1 qualification. No application, database,
#   service, listener, credential, corpus, or boot state is changed.
#
# Usage:
#   bash ./deployment/scripts/07_build-node-next-runtime-on-emceedanko.sh --validate-only
#   bash ./deployment/scripts/07_build-node-next-runtime-on-emceedanko.sh --run

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
readonly target_helper="$repo_root/deployment/assets/build-node-next-runtime"
readonly source_root="$repo_root/deployment/runtime-image"
readonly decision_record="$repo_root/docs/decisions/ISHIKAWA_RELEASE_DECISIONS.md"
readonly artifact_parent="$repo_root/local/artifacts"
readonly artifact_current="$artifact_parent/node-next-runtime-current"
readonly default_report_root="$repo_root/local/reports/emceedanko-node-next-runtime-build"
readonly frozen_hostname='EmceeDanko'
readonly frozen_os_version='24.04'
readonly -a source_names=(Dockerfile LICENSES.md README.md SECURITY.md package-lock.json package.json)
readonly -a handoff_names=(
  Dockerfile
  LICENSES.md
  README.md
  SECURITY.md
  build-receipt.json
  image-identity.json
  licenses.json
  node-next-runtime-amd64.tar
  node-next-runtime-amd64.tar.sha256
  package-lock.json
  package.json
  sbom.cdx.json
  SHA256SUMS
)

target="${APPLICATION_HOST_TARGET:-DankoSurface_EmceeDanko}"
expected_hostname="${APPLICATION_HOST_EXPECTED_HOSTNAME:-EmceeDanko}"
expected_os_version="${APPLICATION_HOST_EXPECTED_OS_VERSION:-24.04}"
identity_file="${APPLICATION_HOST_IDENTITY_FILE:-}"
report_root="${ISHIKAWA_SCRIPT07_REPORT_ROOT:-$default_report_root}"
mode="${1:-}"
shift || true
stage='argument_validation'
report_path=''
work_root=''
artifact_stage=''
remote_root=''
master_started=false
remote_created=false
ssh_args=()
active_pid=''
remote_pid=''
stream_pid=''

result() {
  printf '\nSCRIPT RESULT\nscript_07_node_next_runtime_build=%s\n' "$1"
}

usage() {
  printf '%s\n' \
    'Usage: 07_build-node-next-runtime-on-emceedanko.sh --validate-only' \
    '       07_build-node-next-runtime-on-emceedanko.sh --run [--target SSH_ALIAS]' \
    '              [--identity-file ABSOLUTE_PATH] [--report-root ABSOLUTE_PATH]' \
    '              [--expected-hostname NAME] [--expected-os-version NN.NN]'
}

quiet_cleanup() {
  local status="$?"
  trap - ERR EXIT INT TERM
  set +e
  if [[ -n "$active_pid" ]] && kill -0 "$active_pid" 2>/dev/null; then
    kill -TERM "$active_pid" 2>/dev/null || true
    wait "$active_pid" 2>/dev/null || true
  fi
  if [[ -n "$remote_pid" ]] && kill -0 "$remote_pid" 2>/dev/null; then
    kill -TERM "$remote_pid" 2>/dev/null || true
    wait "$remote_pid" 2>/dev/null || true
  fi
  if [[ -n "$stream_pid" ]] && kill -0 "$stream_pid" 2>/dev/null; then
    kill -TERM "$stream_pid" 2>/dev/null || true
    wait "$stream_pid" 2>/dev/null || true
  fi
  if [[ "$remote_created" == true && "$master_started" == true ]]; then
    timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
      "rm -rf -- '$remote_root' && test ! -e '$remote_root'" >/dev/null 2>&1
  fi
  if [[ "$master_started" == true ]]; then
    timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1
  fi
  if [[ -n "$work_root" && "$work_root" == /tmp/ishikawa-script-07.* \
      && -d "$work_root" && ! -L "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  if [[ -n "$artifact_stage" \
      && "$artifact_stage" == "$artifact_parent"/.node-next-runtime-current.* \
      && -d "$artifact_stage" && ! -L "$artifact_stage" ]]; then
    rm -rf -- "$artifact_stage"
  fi
  exit "$status"
}
trap quiet_cleanup EXIT

block() {
  local reason="$1" detail="$2" action="$3" status="${4:-1}" payload
  trap - ERR
  payload="$(printf '%s\n' \
    'FAILURE DETAIL' \
    "stage=$stage" \
    "reason=$reason" \
    "detail=$detail" \
    "operator_action=$action")"
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
    "An unhandled command failed at Script 07 line ${line} with exit code ${status}." \
    'Review the retained report and correct the complete failing stage.' \
    "$status"
}
trap 'unexpected_error "$?" "$LINENO"' ERR
trap 'stage=interrupted; block signal_interrupt "Script 07 was interrupted." "Review the retained report and rerun the same command." 130' INT
trap 'stage=interrupted; block signal_termination "Script 07 received SIGTERM." "Review the retained report and rerun the same command." 143' TERM

if [[ "$mode" == --help || "$mode" == -h ]]; then
  usage
  exit 0
fi
while (( $# > 0 )); do
  case "$1" in
    --target)
      [[ $# -ge 2 ]] || block target_missing 'The SSH target value is missing.' 'Supply one SSH alias.'
      target="$2"
      shift 2
      ;;
    --expected-hostname)
      [[ $# -ge 2 ]] || block hostname_missing 'The expected hostname is missing.' 'Supply the exact short hostname.'
      expected_hostname="$2"
      shift 2
      ;;
    --expected-os-version)
      [[ $# -ge 2 ]] || block os_version_missing 'The expected OS version is missing.' 'Supply NN.NN.'
      expected_os_version="$2"
      shift 2
      ;;
    --identity-file)
      [[ $# -ge 2 ]] || block identity_missing 'The SSH identity path is missing.' 'Supply an absolute identity path.'
      identity_file="$2"
      shift 2
      ;;
    --report-root)
      [[ $# -ge 2 ]] || block report_root_missing 'The report-root value is missing.' 'Supply an absolute local directory.'
      report_root="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      block argument_invalid "Unsupported argument: $1" 'Use --help and rerun.'
      ;;
  esac
done

[[ "$mode" == --validate-only || "$mode" == --run ]] \
  || block mode_invalid 'Select exactly one execution mode.' 'Use --validate-only or --run.'
[[ "$target" =~ ^[A-Za-z0-9_@.:-]+$ ]] \
  || block target_invalid 'The SSH target is not bounded.' 'Use a configured SSH alias or USER@HOST.'
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] \
  || block hostname_invalid 'The expected hostname is invalid.' 'Correct the short hostname.'
[[ "$expected_os_version" =~ ^[0-9]{2}\.[0-9]{2}$ ]] \
  || block os_version_invalid 'The expected Ubuntu version is invalid.' 'Use NN.NN.'
[[ "$expected_hostname" == "$frozen_hostname" && "$expected_os_version" == "$frozen_os_version" ]] \
  || block frozen_build_host_changed \
    'Script 07 is frozen to EmceeDanko on Ubuntu 24.04.' \
    'Restore the frozen build-host identity or stop for a new operator decision.'
[[ "$report_root" == /* && ! -L "$report_root" ]] \
  || block report_root_unsafe 'The report root must be an absolute non-symlink path.' 'Correct the report root.'
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" \
      && -r "$identity_file" ]] \
    || block identity_unsafe 'The selected SSH identity is not a readable regular file.' 'Correct the identity path or rely on SSH configuration.'
fi
for command_name in awk bash chmod cp date find grep jq kill mkdir mkfifo \
  mktemp mv rm scp sed sha256sum sleep sort ssh stat tar tee timeout tr; do
  command -v "$command_name" >/dev/null 2>&1 \
    || block "command_missing_${command_name}" \
      "Required local command unavailable: ${command_name}." \
      'Restore the named command and rerun.'
done
if [[ "$mode" == --run ]]; then
  stage='report_setup'
  mkdir -p -- "$report_root"
  report_probe="$(mktemp "$report_root/.script07-write-probe.XXXXXX")" \
    || block report_probe_failed 'The report directory is not writable.' 'Correct local report permissions.'
  rm -f -- "$report_probe"
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  report_path="$(mktemp "$report_root/runtime_image_${timestamp}_XXXXXX.txt")" \
    || block report_creation_failed 'The Script 07 report could not be created.' 'Correct local report permissions.'
  work_root="$(mktemp -d /tmp/ishikawa-script-07.XXXXXX)" \
    || block workspace_creation_failed 'The private local workspace could not be created.' 'Correct /tmp capacity or permissions.'
  emit() { printf '[%s] %s\n' "$2" "$1" | tee -a "$report_path"; }
  emit "report_path=$report_path;state=start" READINESS
  emit 'purpose=build_generic_linux_amd64_node_next_runtime_natively_on_emceedanko' READINESS
  emit "target=$target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version;expected_architecture=amd64" READINESS
  emit 'authorized_actions=authenticate_transfer_native_image_build_export_verify_fetch_publish_remove_private_transfer' READINESS
  emit 'non_actions=no_application_change_no_database_contact_no_service_change_no_listener_change_no_credential_read_no_corpus_contact_no_boot_change' READINESS
fi
for required_file in "$target_helper" "$decision_record"; do
  [[ -f "$required_file" && ! -L "$required_file" && -r "$required_file" ]] \
    || block required_file_unsafe \
      "A required Script 07 input is missing, unreadable, or a symbolic link: ${required_file}." \
      'Restore the canonical tracked input and rerun.'
done
for source_name in "${source_names[@]}"; do
  source_path="$source_root/$source_name"
  [[ -f "$source_path" && ! -L "$source_path" && -r "$source_path" ]] \
    || block runtime_source_unsafe \
      "A required runtime-image source is missing, unreadable, or a symbolic link: ${source_name}." \
      'Restore the canonical runtime-image source and rerun.'
done
find "$source_root" -type l -print -quit | grep -q . \
  && block runtime_source_symlink_found \
    'The runtime-image source contains a symbolic link.' \
    'Replace it with a reviewed regular file.'
bash -n "${BASH_SOURCE[0]}" "$target_helper" \
  || block shell_syntax_invalid 'Script 07 or its target helper failed shell parsing.' 'Correct every parse error.'
helper_validation="$(bash "$target_helper" --validate-only 2>&1)" \
  || block target_helper_validation_failed \
    'The native runtime builder failed its non-contact source/decision validation.' \
    'Correct the complete helper validation result before target contact.'
grep -Fxq 'node_next_runtime_build=ready' <<<"$helper_validation" \
  || block target_helper_ready_marker_missing \
    'The native runtime builder omitted its ready result.' \
    'Treat the helper as unvalidated.'
helper_sha256="$(sha256sum -- "$target_helper" | awk '{print $1}')"
lock_sha256="$(sha256sum -- "$source_root/package-lock.json" | awk '{print $1}')"

if [[ "$mode" == --validate-only ]]; then
  printf '%s\n' \
    'purpose=validate_native_amd64_runtime_build_on_emceedanko' \
    "helper_sha256=$helper_sha256;lock_sha256=$lock_sha256" \
    'build_host=EmceeDanko;os=ubuntu_24.04;architecture=amd64;emulation=false' \
    'target_contact=false;target_mutation=false;application_contact=false;database_contact=false;service_change=false'
  result ready
  exit 0
fi

emit "helper_sha256=$helper_sha256;lock_sha256=$lock_sha256" READINESS

stage='payload_assembly'
payload_root="$work_root/payload"
mkdir -p -- \
  "$payload_root/deployment/assets" \
  "$payload_root/deployment/runtime-image" \
  "$payload_root/docs/decisions"
cp -- "$target_helper" "$payload_root/deployment/assets/build-node-next-runtime"
for source_name in "${source_names[@]}"; do
  cp -- "$source_root/$source_name" "$payload_root/deployment/runtime-image/$source_name"
done
cp -- "$decision_record" "$payload_root/docs/decisions/ISHIKAWA_RELEASE_DECISIONS.md"
chmod 0755 "$payload_root/deployment/assets/build-node-next-runtime"
chmod 0644 "$payload_root/deployment/runtime-image/"* \
  "$payload_root/docs/decisions/ISHIKAWA_RELEASE_DECISIONS.md"
(
  cd -- "$payload_root"
  while IFS= read -r payload_path; do
    sha256sum -- "$payload_path"
  done < <(find . -type f ! -name SHA256SUMS -printf '%P\n' | sort)
) >"$payload_root/SHA256SUMS"
(
  cd -- "$payload_root"
  sha256sum --check --strict SHA256SUMS >/dev/null
)
payload_archive="$work_root/script-07-runtime-build-payload.tar.gz"
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime='UTC 1970-01-01' \
  -czf "$payload_archive" -C "$work_root" payload
payload_sha256="$(sha256sum -- "$payload_archive" | awk '{print $1}')"
payload_bytes="$(stat -Lc %s -- "$payload_archive")"
emit "state=pass;payload_sha256=$payload_sha256;payload_files=$(find "$payload_root" -type f | awk 'END {print NR}');transfer_bytes=$payload_bytes;reused_transfer_bytes=0" PAYLOAD

stage='authentication'
emit 'state=waiting_for_ssh_private_key_passphrase_if_prompted' AUTHENTICATION
control_path="/tmp/is07-${timestamp}-%C"
ssh_args=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 \
  -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto \
  -o "ControlPath=$control_path" -o ControlPersist=300)
[[ -z "$identity_file" ]] || ssh_args+=(-i "$identity_file" -o IdentitiesOnly=yes)
ssh -G "${ssh_args[@]}" "$target" >/dev/null \
  || block ssh_configuration_invalid 'OpenSSH rejected the bounded connection configuration.' 'Correct the SSH target or identity.'
timeout --foreground 120 ssh "${ssh_args[@]}" -Nf "$target" \
  || block ssh_master_start_failed 'SSH authentication or connection failed.' 'Correct SSH access and rerun Script 07.'
master_started=true
timeout --foreground 10 ssh "${ssh_args[@]}" -O check "$target" >/dev/null \
  || block ssh_master_check_failed 'The authenticated SSH control master was not ready.' 'Correct SSH access and rerun Script 07.'
emit 'state=pass;control_master=ready' AUTHENTICATION

stage='transfer_to_build_host'
remote_root="/tmp/ishikawa-runtime-build-${timestamp}-$$"
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" >/dev/null \
  || block remote_directory_failed 'The private EmceeDanko transfer directory could not be created.' 'Review target permissions and rerun.'
remote_created=true
emit 'state=start;payload=runtime_build_inputs_only' TRANSFER
timeout --foreground 180 scp "${ssh_args[@]}" "$payload_archive" "$target:$remote_root/" >/dev/null \
  || block transfer_failed 'The checksum-bound runtime build payload failed to transfer.' 'Correct SSH transport and rerun.'
timeout --foreground 120 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && printf '%s  %s\n' '$payload_sha256' 'script-07-runtime-build-payload.tar.gz' | sha256sum --check --strict - >/dev/null && tar -xzf script-07-runtime-build-payload.tar.gz && cd payload && sha256sum --check --strict SHA256SUMS >/dev/null" \
  || block transferred_payload_invalid 'EmceeDanko rejected the transferred payload or its internal checksums.' 'Do not build; correct the transfer and rerun.'
emit 'state=pass;target_checksums=pass' TRANSFER

stage='native_runtime_build'
emit 'state=start;architecture=native_amd64;sudo_prompt_may_follow=true' BUILD
stream_path="$work_root/native-build.stream"
mkfifo -m 0600 -- "$stream_path"
tee -a "$report_path" <"$stream_path" &
stream_pid="$!"
tty_input=/dev/null
[[ -t 0 ]] && tty_input=/dev/tty
trap - ERR
set +e
timeout --foreground 1800 ssh -tt "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root/payload' && bash ./deployment/assets/build-node-next-runtime --run --expected-hostname '$expected_hostname' --expected-os-version '$expected_os_version'" \
  <"$tty_input" >"$stream_path" 2>&1 &
remote_pid="$!"
wait "$remote_pid"
remote_status="$?"
remote_pid=''
wait "$stream_pid"
tee_status="$?"
stream_pid=''
rm -f -- "$stream_path"
set -e
trap 'unexpected_error "$?" "$LINENO"' ERR
(( tee_status == 0 )) \
  || block report_stream_failed 'The live Script 07 report stream failed.' 'Restore the report lane before rebuilding.'
if (( remote_status != 0 )); then
  [[ "$remote_status" != 124 ]] \
    || block native_build_timeout 'The native runtime build exceeded 30 minutes.' 'Review the retained stage output and EmceeDanko Docker state.'
  nested_reason="$(tr -d '\r' <"$report_path" | sed -n 's/^reason=\([a-z0-9_]*\)$/\1/p' | tail -n 1)"
  block "${nested_reason:-native_runtime_build_failed}" \
    "The EmceeDanko runtime builder exited with status ${remote_status}." \
    'Correct the complete retained failure detail and rerun Script 07.' \
    "$remote_status"
fi
grep -Fq 'node_next_runtime_build=pass' "$report_path" \
  || block native_build_result_missing 'The EmceeDanko builder omitted its standalone pass result.' 'Treat the build as unqualified.'
emit 'state=pass;image_retained_on_emceedanko=true' BUILD

stage='artifact_return'
remote_handoff="$remote_root/payload/local/artifacts/node-next-runtime-current"
timeout --foreground 120 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_handoff' && sha256sum --check --strict SHA256SUMS >/dev/null" \
  || block remote_handoff_invalid 'The generated handoff failed verification on EmceeDanko.' 'Do not fetch or publish it.'
mkdir -p -- "$artifact_parent"
artifact_stage="$artifact_parent/.node-next-runtime-current.${timestamp}.$$"
[[ ! -e "$artifact_stage" && ! -L "$artifact_stage" ]] \
  || block local_stage_exists 'The selected local return stage already exists.' 'Inspect the local artifact lane and rerun.'
emit 'state=start;payload=verified_runtime_handoff' RETURN
timeout --foreground 600 scp -r "${ssh_args[@]}" "$target:$remote_handoff" "$artifact_stage" >/dev/null &
active_pid="$!"
return_started="$(date +%s)"
next_return_heartbeat=30
while kill -0 "$active_pid" 2>/dev/null; do
  sleep 1
  return_elapsed="$(( $(date +%s) - return_started ))"
  if (( return_elapsed >= next_return_heartbeat )); then
    emit "state=running;elapsed_seconds=$return_elapsed" RETURN
    next_return_heartbeat=$((next_return_heartbeat + 30))
  fi
done
set +e
wait "$active_pid"
return_status="$?"
set -e
active_pid=''
(( return_status == 0 )) \
  || block artifact_fetch_failed 'The verified runtime handoff could not be fetched.' 'Correct transport and rerun Script 07.'
fetched_handoff="$artifact_stage"
[[ -d "$fetched_handoff" && ! -L "$fetched_handoff" ]] \
  || block fetched_handoff_missing 'The fetched runtime handoff directory is absent or unsafe.' 'Treat the return transfer as failed.'
unsafe_entry="$(find "$fetched_handoff" -mindepth 1 ! -type f -print -quit)"
[[ -z "$unsafe_entry" ]] \
  || block fetched_handoff_type_invalid 'The fetched handoff contains a non-regular entry.' 'Do not publish the returned handoff.'
actual_names="$(find "$fetched_handoff" -maxdepth 1 -type f -printf '%f\n' | sort)"
expected_names="$(printf '%s\n' "${handoff_names[@]}" | sort)"
[[ "$actual_names" == "$expected_names" ]] \
  || block fetched_handoff_inventory_invalid 'The fetched handoff file inventory differs from the frozen set.' 'Do not publish the returned handoff.'
(
  cd -- "$fetched_handoff"
  sha256sum --check --strict SHA256SUMS >/dev/null
  sha256sum --check --strict node-next-runtime-amd64.tar.sha256 >/dev/null
) || block fetched_handoff_checksum_failed 'The returned handoff failed independent local checksum verification.' 'Do not publish it.'
archive_sha256="$(sha256sum -- "$fetched_handoff/node-next-runtime-amd64.tar" | awk '{print $1}')"
image_id="$(jq -r '.image_id' "$fetched_handoff/image-identity.json")"
jq -e --arg archive_sha256 "$archive_sha256" --arg image_id "$image_id" \
  '.schema == "node-next-runtime-image.v1"
   and .architecture == "amd64"
   and .platform == "linux/amd64"
   and .application_in_image == false
   and .generated_next_in_image == false
   and .archive_sha256 == $archive_sha256
   and .image_id == $image_id' \
  "$fetched_handoff/image-identity.json" >/dev/null \
  || block fetched_identity_invalid 'The returned image-identity record is invalid.' 'Do not publish it.'
jq -e --arg archive_sha256 "$archive_sha256" --arg image_id "$image_id" \
  '.schema == "node-next-runtime-build-receipt.v1"
   and .architecture == "amd64"
   and .platform == "linux/amd64"
   and .application_in_image == false
   and .generated_next_in_image == false
   and .archive_sha256 == $archive_sha256
   and .image_id == $image_id' \
  "$fetched_handoff/build-receipt.json" >/dev/null \
  || block fetched_build_receipt_invalid 'The returned build receipt is invalid.' 'Do not publish it.'
returned_bytes="$(stat -Lc %s -- "$fetched_handoff/node-next-runtime-amd64.tar")"
emit "state=pass;archive_sha256=$archive_sha256;image_id=$image_id;transfer_bytes=$returned_bytes;reused_transfer_bytes=0" RETURN

stage='local_publication'
mkdir -p -- "$artifact_parent" "$artifact_parent/superseded"
artifact_backup=''
if [[ -e "$artifact_current" || -L "$artifact_current" ]]; then
  [[ -d "$artifact_current" && ! -L "$artifact_current" ]] \
    || block current_handoff_unsafe 'The current runtime handoff is not a regular directory.' 'Inspect the local artifact lane.'
  artifact_backup="$artifact_parent/superseded/node-next-runtime-current-${timestamp}-$$"
  [[ ! -e "$artifact_backup" && ! -L "$artifact_backup" ]] \
    || block superseded_handoff_exists 'The selected superseded path already exists.' 'Inspect the local artifact lane.'
  mv -- "$artifact_current" "$artifact_backup"
fi
if ! mv -- "$artifact_stage" "$artifact_current"; then
  [[ -z "$artifact_backup" ]] || mv -- "$artifact_backup" "$artifact_current"
  block local_publication_failed 'The verified handoff could not be published atomically.' 'The prior current handoff was restored; inspect local storage.'
fi
artifact_stage=''
(
  cd -- "$artifact_current"
  sha256sum --check --strict SHA256SUMS >/dev/null
) || block published_handoff_checksum_failed 'The published local handoff failed final checksum verification.' 'Stop and inspect the local artifact lane.'
emit "state=pass;handoff=$artifact_current" PUBLISH

stage='remote_cleanup'
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "rm -rf -- '$remote_root' && test ! -e '$remote_root'" >/dev/null \
  || block remote_cleanup_failed 'The private EmceeDanko transfer directory was not removed.' 'Remove only the reported private transfer directory before continuing.'
remote_created=false
timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1 || true
master_started=false
emit 'state=pass;private_transfer_removed=true;built_image_retained=true' CLEANUP
emit "report_path=$report_path;archive_sha256=$archive_sha256;next_gate=build_v1_3_1_application_candidate" SUMMARY
result pass | tee -a "$report_path"
