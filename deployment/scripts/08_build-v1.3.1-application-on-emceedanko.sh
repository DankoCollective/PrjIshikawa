#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Purpose:
#   Build and return the deterministic external Ishikawa v1.3.1 application
#   candidate on native AMD64 EmceeDanko against the exact Script 07 image.
#
# Usage:
#   bash ./deployment/scripts/08_build-v1.3.1-application-on-emceedanko.sh --validate-only
#   bash ./deployment/scripts/08_build-v1.3.1-application-on-emceedanko.sh --run

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
readonly target_helper="$repo_root/deployment/assets/build-v1.3.1-application-on-emceedanko"
readonly application_builder="$repo_root/deployment/scripts/01_build-ishikawa-release.sh"
readonly product_root="$repo_root/Ishikawa"
readonly runtime_root="$repo_root/local/artifacts/node-next-runtime-current"
readonly artifact_parent="$repo_root/local/artifacts"
readonly artifact_current="$artifact_parent/ishikawa-v1.3.1-candidate-current"
readonly default_report_root="$repo_root/local/reports/emceedanko-v1.3.1-application-build"
readonly frozen_hostname='EmceeDanko'
readonly frozen_os_version='24.04'
readonly image_reference='node-next-runtime:24.22.1-next16.4.3-react19.2.9-amd64'
readonly -a application_handoff_names=(
  ISHIKAWA_V1_3_1_SOURCE_SHA256SUMS
  SHA256SUMS
  application-license.json
  application-sbom.cdx.json
  ishikawa-v1.3.1.tar.gz
  ishikawa-v1.3.1.tar.gz.sha256
  release-receipt.json
)

target="${APPLICATION_HOST_TARGET:-DankoSurface_EmceeDanko}"
expected_hostname="${APPLICATION_HOST_EXPECTED_HOSTNAME:-EmceeDanko}"
expected_os_version="${APPLICATION_HOST_EXPECTED_OS_VERSION:-24.04}"
identity_file="${APPLICATION_HOST_IDENTITY_FILE:-}"
report_root="${ISHIKAWA_SCRIPT08_REPORT_ROOT:-$default_report_root}"
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
  printf '\nSCRIPT RESULT\nscript_08_v1_3_1_application_build=%s\n' "$1"
}

usage() {
  printf '%s\n' \
    'Usage: 08_build-v1.3.1-application-on-emceedanko.sh --validate-only' \
    '       08_build-v1.3.1-application-on-emceedanko.sh --run [--target SSH_ALIAS]' \
    '              [--identity-file ABSOLUTE_PATH] [--report-root ABSOLUTE_PATH]' \
    '              [--expected-hostname NAME] [--expected-os-version NN.NN]'
}

quiet_cleanup() {
  local status="$?"
  trap - ERR EXIT INT TERM
  set +e
  for pid_name in active_pid remote_pid stream_pid; do
    pid_value="${!pid_name}"
    if [[ -n "$pid_value" ]] && kill -0 "$pid_value" 2>/dev/null; then
      kill -TERM "$pid_value" 2>/dev/null || true
      wait "$pid_value" 2>/dev/null || true
    fi
  done
  if [[ "$remote_created" == true && "$master_started" == true ]]; then
    timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
      "rm -rf -- '$remote_root' && test ! -e '$remote_root'" >/dev/null 2>&1
  fi
  if [[ "$master_started" == true ]]; then
    timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1
  fi
  if [[ -n "$work_root" && "$work_root" == /tmp/ishikawa-script-08.* \
      && -d "$work_root" && ! -L "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  if [[ -n "$artifact_stage" \
      && "$artifact_stage" == "$artifact_parent"/.ishikawa-v1.3.1-candidate-current.* \
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
    "An unhandled command failed at Script 08 line ${line} with exit code ${status}." \
    'Review the retained report and correct the complete failing stage.' \
    "$status"
}
trap 'unexpected_error "$?" "$LINENO"' ERR
trap 'stage=interrupted; block signal_interrupt "Script 08 was interrupted." "Review the retained report and rerun the same command." 130' INT
trap 'stage=interrupted; block signal_termination "Script 08 received SIGTERM." "Review the retained report and rerun the same command." 143' TERM

if [[ "$mode" == --help || "$mode" == -h ]]; then
  usage
  exit 0
fi
while (( $# > 0 )); do
  case "$1" in
    --target) [[ $# -ge 2 ]] || block target_missing 'The SSH target value is missing.' 'Supply one SSH alias.'; target="$2"; shift 2 ;;
    --expected-hostname) [[ $# -ge 2 ]] || block hostname_missing 'The expected hostname is missing.' 'Supply the exact short hostname.'; expected_hostname="$2"; shift 2 ;;
    --expected-os-version) [[ $# -ge 2 ]] || block os_version_missing 'The expected Ubuntu version is missing.' 'Supply NN.NN.'; expected_os_version="$2"; shift 2 ;;
    --identity-file) [[ $# -ge 2 ]] || block identity_missing 'The SSH identity path is missing.' 'Supply an absolute identity path.'; identity_file="$2"; shift 2 ;;
    --report-root) [[ $# -ge 2 ]] || block report_root_missing 'The report-root value is missing.' 'Supply an absolute local directory.'; report_root="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) block argument_invalid "Unsupported argument: $1" 'Use --help and rerun.' ;;
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
    'Script 08 is frozen to EmceeDanko on Ubuntu 24.04.' \
    'Restore the frozen native build host or stop for an operator decision.'
[[ "$report_root" == /* && ! -L "$report_root" ]] \
  || block report_root_unsafe 'The report root must be an absolute non-symlink path.' 'Correct the report root.'
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] \
    || block identity_unsafe 'The selected SSH identity is not a readable regular file.' 'Correct the identity path or rely on SSH configuration.'
fi
for command_name in awk bash chmod cmp cp date find grep jq kill mkdir mkfifo \
  mktemp mv python3 rm scp sed sha256sum sleep sort ssh stat tar tee timeout tr; do
  command -v "$command_name" >/dev/null 2>&1 \
    || block "command_missing_${command_name}" \
      "Required local command unavailable: ${command_name}." \
      'Restore the named command and rerun.'
done

if [[ "$mode" == --run ]]; then
  stage='report_setup'
  mkdir -p -- "$report_root"
  report_probe="$(mktemp "$report_root/.script08-write-probe.XXXXXX")" \
    || block report_probe_failed 'The report directory is not writable.' 'Correct local report permissions.'
  rm -f -- "$report_probe"
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  report_path="$(mktemp "$report_root/application_build_${timestamp}_XXXXXX.txt")" \
    || block report_creation_failed 'The Script 08 report could not be created.' 'Correct local report permissions.'
  work_root="$(mktemp -d /tmp/ishikawa-script-08.XXXXXX)" \
    || block workspace_creation_failed 'The private local workspace could not be created.' 'Correct /tmp capacity or permissions.'
  emit() { printf '[%s] %s\n' "$2" "$1" | tee -a "$report_path"; }
  emit "report_path=$report_path;state=start" READINESS
  emit 'purpose=build_external_v1_3_1_application_natively_on_emceedanko' READINESS
  emit "target=$target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version;expected_architecture=amd64" READINESS
  emit 'authorized_actions=authenticate_transfer_native_tests_ephemeral_container_tests_application_assembly_fetch_publish_remove_private_transfer' READINESS
  emit 'non_actions=no_image_build_no_image_pull_no_database_contact_no_model_contact_no_service_change_no_listener_change_no_credential_read_no_corpus_contact_no_boot_change' READINESS
fi

stage='local_preflight'
for required_file in \
  "$target_helper" "$application_builder" "$repo_root/LICENSE" \
  "$repo_root/deployment/assets/README-v1.3.1.md" \
  "$repo_root/deployment/assets/verify-ishikawa-release" \
  "$repo_root/docs/decisions/ISHIKAWA_RELEASE_DECISIONS.md" \
  "$repo_root/docs/releases/ISHIKAWA_ORG_LAB_CARRY_READINESS_CHECKLIST.md" \
  "$repo_root/docs/releases/ISHIKAWA_V1_3_1_SOURCE_SHA256SUMS" \
  "$runtime_root/SHA256SUMS" "$runtime_root/node-next-runtime-amd64.tar" \
  "$runtime_root/node-next-runtime-amd64.tar.sha256" \
  "$runtime_root/image-identity.json" "$runtime_root/build-receipt.json"; do
  [[ -f "$required_file" && ! -L "$required_file" && -r "$required_file" ]] \
    || block required_file_unsafe \
      "A required Script 08 input is missing, unreadable, or a symbolic link: ${required_file}." \
      'Restore the canonical checksum-bound input and rerun.'
done
[[ -d "$product_root" && ! -L "$product_root" ]] \
  || block product_source_unsafe 'The canonical product directory is absent or unsafe.' 'Restore the frozen product source.'
find "$product_root" -type l -print -quit | grep -q . \
  && block product_source_symlink_found 'The product source contains a symbolic link.' 'Replace it with a reviewed regular file.'
bash -n "${BASH_SOURCE[0]}" "$target_helper" "$application_builder" \
  || block shell_syntax_invalid 'Script 08 or a transferred build command failed shell parsing.' 'Correct every parse error.'
trap - ERR
set +e
builder_validation="$(bash "$application_builder" --validate-only 2>&1)"
builder_validation_status="$?"
set -e
trap 'unexpected_error "$?" "$LINENO"' ERR
if (( builder_validation_status != 0 )); then
  printf '%s\n' "$builder_validation" >&2
  nested_reason="$(sed -n 's/^reason=\([a-z0-9_]*\)$/\1/p' \
    <<<"$builder_validation" | tail -n 1)"
  block "${nested_reason:-application_builder_validation_failed}" \
    "The application builder validation exited with status ${builder_validation_status}." \
    'Correct the complete nested validation detail before target contact.'
fi
grep -Fxq 'script_01_build_ishikawa_release=ready' <<<"$builder_validation" \
  || block application_builder_ready_marker_missing 'The application builder omitted its ready result.' 'Treat it as unvalidated.'
trap - ERR
set +e
helper_validation="$(ISHIKAWA_RUNTIME_HANDOFF_ROOT="$runtime_root" \
  bash "$target_helper" --validate-only 2>&1)"
helper_validation_status="$?"
set -e
trap 'unexpected_error "$?" "$LINENO"' ERR
if (( helper_validation_status != 0 )); then
  printf '%s\n' "$helper_validation" >&2
  nested_reason="$(sed -n 's/^reason=\([a-z0-9_]*\)$/\1/p' \
    <<<"$helper_validation" | tail -n 1)"
  block "${nested_reason:-target_helper_validation_failed}" \
    "The native application helper validation exited with status ${helper_validation_status}." \
    'Correct the complete nested helper detail before target contact.'
fi
grep -Fxq 'v1_3_1_application_build=ready' <<<"$helper_validation" \
  || block target_helper_ready_marker_missing 'The native helper omitted its ready result.' 'Treat it as unvalidated.'
(
  cd -- "$runtime_root"
  sha256sum --check --strict SHA256SUMS >/dev/null
  sha256sum --check --strict node-next-runtime-amd64.tar.sha256 >/dev/null
) || block runtime_handoff_checksum_failed \
  'The corrected Script 07 runtime handoff failed its checksum manifests.' \
  'Rerun corrected Script 07 before the application build.'

python3 -B - "$runtime_root" "$image_reference" <<'PY' \
  || block runtime_handoff_provenance_invalid \
    'The corrected Script 07 runtime archive and evidence are not mutually bound.' \
    'Rerun corrected Script 07 before the application build.'
import hashlib
import json
import re
import sys
import tarfile
from pathlib import Path

root = Path(sys.argv[1])
reference = sys.argv[2]
archive_path = root / "node-next-runtime-amd64.tar"
identity = json.loads((root / "image-identity.json").read_text(encoding="utf-8"))
receipt = json.loads((root / "build-receipt.json").read_text(encoding="utf-8"))

def file_digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()

def stream_digest(stream):
    value = hashlib.sha256()
    for block in iter(lambda: stream.read(1024 * 1024), b""):
        value.update(block)
    return value.hexdigest()

if identity.get("archive_sha256") != file_digest(archive_path):
    raise SystemExit(1)
if not re.fullmatch(r"sha256:[0-9a-f]{64}", identity.get("image_id", "")):
    raise SystemExit(1)
expected = {
    "application_in_image": False, "architecture": "amd64",
    "generated_next_in_image": False, "image_reference": reference,
    "next": "16.4.3", "node": "24.22.1", "npm": "11.19.1",
    "platform": "linux/amd64", "react": "19.2.9", "react_dom": "19.2.9",
    "schema": "node-next-runtime-image.v1", "yarn": "1.22.22",
}
if any(identity.get(key) != value for key, value in expected.items()):
    raise SystemExit(1)
with tarfile.open(archive_path, "r:") as archive:
    manifest_member = archive.extractfile("manifest.json")
    if manifest_member is None:
        raise SystemExit(1)
    manifest = json.load(manifest_member)
    if not isinstance(manifest, list) or len(manifest) != 1 or manifest[0].get("RepoTags") != [reference]:
        raise SystemExit(1)
    layers = manifest[0].get("Layers")
    if not isinstance(layers, list) or not layers:
        raise SystemExit(1)
    for layer_path in layers:
        match = re.fullmatch(r"blobs/sha256/([0-9a-f]{64})", layer_path or "")
        member = archive.extractfile(layer_path) if match else None
        if member is None or stream_digest(member) != match.group(1):
            raise SystemExit(1)
    config_path = manifest[0].get("Config")
    match = re.fullmatch(r"blobs/sha256/([0-9a-f]{64})", config_path or "")
    config_member = archive.extractfile(config_path) if match else None
    if config_member is None:
        raise SystemExit(1)
    config_bytes = config_member.read()
if hashlib.sha256(config_bytes).hexdigest() != match.group(1):
    raise SystemExit(1)
config = json.loads(config_bytes)
history = config.get("history")
if not isinstance(history, list) or not history:
    raise SystemExit(1)
history_digest = hashlib.sha256((json.dumps(history, sort_keys=True, separators=(",", ":")) + "\n").encode()).hexdigest()
if identity.get("config_digest") != f"sha256:{match.group(1)}" or identity.get("history_sha256") != history_digest:
    raise SystemExit(1)
if config.get("architecture") != "amd64" or config.get("os") != "linux":
    raise SystemExit(1)
if config.get("config", {}).get("WorkingDir") != "/opt/nextjs" or config.get("config", {}).get("Cmd") != ["next", "--help"]:
    raise SystemExit(1)
rootfs = config.get("rootfs")
if not isinstance(rootfs, dict) or rootfs.get("type") != "layers":
    raise SystemExit(1)
diff_ids = rootfs.get("diff_ids")
if not isinstance(diff_ids, list) or len(diff_ids) != len(layers):
    raise SystemExit(1)
if any(not re.fullmatch(r"sha256:[0-9a-f]{64}", item or "") for item in diff_ids):
    raise SystemExit(1)
config_text = config_bytes.decode("utf-8", errors="strict").lower()
for forbidden in ("ishikawa", "emceedanko", "dankosurface", "org_lab", "black_corpus"):
    if forbidden in config_text:
        raise SystemExit(1)
if receipt.get("schema") != "node-next-runtime-build-receipt.v1":
    raise SystemExit(1)
for field in ("image_id", "image_reference", "archive_sha256", "architecture", "platform", "config_digest", "history_sha256"):
    if receipt.get(field) != identity.get(field):
        raise SystemExit(1)
PY

runtime_image_id="$(jq -r '.image_id' "$runtime_root/image-identity.json")"
runtime_archive_sha256="$(sha256sum -- "$runtime_root/node-next-runtime-amd64.tar" | awk '{print $1}')"
helper_sha256="$(sha256sum -- "$target_helper" | awk '{print $1}')"
source_manifest_sha256="$(sha256sum -- "$repo_root/docs/releases/ISHIKAWA_V1_3_1_SOURCE_SHA256SUMS" | awk '{print $1}')"

if [[ "$mode" == --validate-only ]]; then
  printf '%s\n' \
    'purpose=validate_native_amd64_v1_3_1_application_build_on_emceedanko' \
    "helper_sha256=$helper_sha256;source_manifest_sha256=$source_manifest_sha256" \
    "runtime_archive_sha256=$runtime_archive_sha256;runtime_image_id=$runtime_image_id" \
    'target_contact=false;target_mutation=false;database_contact=false;model_contact=false;service_change=false'
  result ready
  exit 0
fi
emit "helper_sha256=$helper_sha256;source_manifest_sha256=$source_manifest_sha256;runtime_archive_sha256=$runtime_archive_sha256;runtime_image_id=$runtime_image_id" READINESS

stage='payload_assembly'
payload_root="$work_root/payload"
mkdir -p -- \
  "$payload_root/deployment/assets" "$payload_root/deployment/scripts" \
  "$payload_root/docs/decisions" "$payload_root/docs/releases" \
  "$payload_root/runtime-handoff"
cp -a -- "$product_root" "$payload_root/Ishikawa"
cp -- "$repo_root/LICENSE" "$payload_root/LICENSE"
cp -- "$target_helper" "$payload_root/deployment/assets/build-v1.3.1-application-on-emceedanko"
cp -- "$repo_root/deployment/assets/README-v1.3.1.md" \
  "$repo_root/deployment/assets/verify-ishikawa-release" "$payload_root/deployment/assets/"
cp -- "$application_builder" "$payload_root/deployment/scripts/01_build-ishikawa-release.sh"
cp -- "$repo_root/docs/decisions/ISHIKAWA_RELEASE_DECISIONS.md" "$payload_root/docs/decisions/"
cp -- "$repo_root/docs/releases/ISHIKAWA_ORG_LAB_CARRY_READINESS_CHECKLIST.md" \
  "$repo_root/docs/releases/ISHIKAWA_V1_3_1_SOURCE_SHA256SUMS" "$payload_root/docs/releases/"
cp -- "$runtime_root/image-identity.json" "$runtime_root/build-receipt.json" \
  "$payload_root/runtime-handoff/"
chmod 0755 \
  "$payload_root/deployment/assets/build-v1.3.1-application-on-emceedanko" \
  "$payload_root/deployment/assets/verify-ishikawa-release" \
  "$payload_root/deployment/scripts/01_build-ishikawa-release.sh"
find "$payload_root" -type l -print -quit | grep -q . \
  && block payload_symlink_found 'The application-build payload contains a symbolic link.' 'Do not transfer the payload.'
(
  cd -- "$payload_root"
  while IFS= read -r payload_path; do sha256sum -- "$payload_path"; done < <(
    find . -type f ! -path './SHA256SUMS' -printf '%P\n' | sort
  ) >SHA256SUMS
  sha256sum --check --strict SHA256SUMS >/dev/null
)
payload_archive="$work_root/script-08-application-build-payload.tar.gz"
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime='UTC 1970-01-01' \
  -czf "$payload_archive" -C "$work_root" payload
payload_sha256="$(sha256sum -- "$payload_archive" | awk '{print $1}')"
payload_bytes="$(stat -Lc %s -- "$payload_archive")"
emit "state=pass;payload_sha256=$payload_sha256;payload_files=$(find "$payload_root" -type f | awk 'END {print NR}');transfer_bytes=$payload_bytes" PAYLOAD

stage='authentication'
emit 'state=waiting_for_ssh_private_key_passphrase_if_prompted' AUTHENTICATION
control_path="/tmp/is08-${timestamp}-%C"
ssh_args=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 \
  -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto \
  -o "ControlPath=$control_path" -o ControlPersist=300)
[[ -z "$identity_file" ]] || ssh_args+=(-i "$identity_file" -o IdentitiesOnly=yes)
ssh -G "${ssh_args[@]}" "$target" >/dev/null \
  || block ssh_configuration_invalid 'OpenSSH rejected the bounded connection configuration.' 'Correct the SSH target or identity.'
timeout --foreground 120 ssh "${ssh_args[@]}" -Nf "$target" \
  || block ssh_master_start_failed 'SSH authentication or connection failed.' 'Correct SSH access and rerun Script 08.'
master_started=true
timeout --foreground 10 ssh "${ssh_args[@]}" -O check "$target" >/dev/null \
  || block ssh_master_check_failed 'The authenticated SSH control master was not ready.' 'Correct SSH access and rerun Script 08.'
emit 'state=pass;control_master=ready' AUTHENTICATION

stage='transfer_to_build_host'
remote_root="/tmp/ishikawa-application-build-${timestamp}-$$"
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" >/dev/null \
  || block remote_directory_failed 'The private EmceeDanko transfer directory could not be created.' 'Review target permissions and rerun.'
remote_created=true
emit 'state=start;payload=application_build_inputs_only' TRANSFER
timeout --foreground 300 scp "${ssh_args[@]}" "$payload_archive" "$target:$remote_root/" >/dev/null \
  || block transfer_failed 'The checksum-bound application-build payload failed to transfer.' 'Correct SSH transport and rerun.'
timeout --foreground 180 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && printf '%s  %s\n' '$payload_sha256' 'script-08-application-build-payload.tar.gz' | sha256sum --check --strict - >/dev/null && tar -xzf script-08-application-build-payload.tar.gz && cd payload && sha256sum --check --strict SHA256SUMS >/dev/null" \
  || block transferred_payload_invalid 'EmceeDanko rejected the transferred payload or its internal checksums.' 'Do not build; correct the transfer and rerun.'
emit 'state=pass;target_checksums=pass' TRANSFER

stage='native_application_build'
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
  "cd '$remote_root/payload' && bash ./deployment/assets/build-v1.3.1-application-on-emceedanko --run --expected-hostname '$expected_hostname' --expected-os-version '$expected_os_version'" \
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
  || block report_stream_failed 'The live Script 08 report stream failed.' 'Restore the report lane before rebuilding.'
if (( remote_status != 0 )); then
  [[ "$remote_status" != 124 ]] \
    || block native_build_timeout 'The native application build exceeded 30 minutes.' 'Review the retained stage output and EmceeDanko state.'
  nested_reason="$(tr -d '\r' <"$report_path" | sed -n 's/^reason=\([a-z0-9_]*\)$/\1/p' | tail -n 1)"
  block "${nested_reason:-native_application_build_failed}" \
    "The EmceeDanko application builder exited with status ${remote_status}." \
    'Correct the complete retained failure detail and rerun Script 08.' \
    "$remote_status"
fi
grep -Fq 'v1_3_1_application_build=pass' "$report_path" \
  || block native_build_result_missing 'The EmceeDanko helper omitted its standalone pass result.' 'Treat the build as unqualified.'
emit 'state=pass;runtime_image_unchanged=true' BUILD

stage='artifact_return'
remote_handoff="$remote_root/payload/local/artifacts/ishikawa-v1.3.1-candidate-current"
timeout --foreground 120 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_handoff' && sha256sum --check --strict SHA256SUMS >/dev/null && sha256sum --check --strict ishikawa-v1.3.1.tar.gz.sha256 >/dev/null" \
  || block remote_handoff_invalid 'The generated application handoff failed verification on EmceeDanko.' 'Do not fetch or publish it.'
mkdir -p -- "$artifact_parent"
artifact_stage="$artifact_parent/.ishikawa-v1.3.1-candidate-current.${timestamp}.$$"
[[ ! -e "$artifact_stage" && ! -L "$artifact_stage" ]] \
  || block local_stage_exists 'The selected local return stage already exists.' 'Inspect the local artifact lane and rerun.'
emit 'state=start;payload=verified_application_handoff' RETURN
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
trap - ERR
set +e
wait "$active_pid"
return_status="$?"
set -e
trap 'unexpected_error "$?" "$LINENO"' ERR
active_pid=''
(( return_status == 0 )) \
  || block artifact_fetch_failed 'The verified application handoff could not be fetched.' 'Correct transport and rerun Script 08.'
[[ -d "$artifact_stage" && ! -L "$artifact_stage" ]] \
  || block fetched_handoff_missing 'The fetched application handoff is absent or unsafe.' 'Treat the return transfer as failed.'
unsafe_entry="$(find "$artifact_stage" -mindepth 1 ! -type f -print -quit)"
[[ -z "$unsafe_entry" ]] \
  || block fetched_handoff_type_invalid 'The fetched handoff contains a non-regular entry.' 'Do not publish it.'
actual_names="$(find "$artifact_stage" -maxdepth 1 -type f -printf '%f\n' | sort)"
expected_names="$(printf '%s\n' "${application_handoff_names[@]}" | sort)"
[[ "$actual_names" == "$expected_names" ]] \
  || block fetched_handoff_inventory_invalid 'The fetched handoff file inventory differs from the canonical set.' 'Do not publish it.'
(
  cd -- "$artifact_stage"
  sha256sum --check --strict SHA256SUMS >/dev/null
  sha256sum --check --strict ishikawa-v1.3.1.tar.gz.sha256 >/dev/null
) || block fetched_handoff_checksum_failed 'The returned application handoff failed independent checksums.' 'Do not publish it.'
application_sha256="$(sha256sum -- "$artifact_stage/ishikawa-v1.3.1.tar.gz" | awk '{print $1}')"
jq -e --arg application_sha256 "$application_sha256" '
  .release == "Ishikawa v1.3.1 candidate"
  and .archive_sha256 == $application_sha256
  and .coding_standard == "pass"
  and .deterministic_archive == true
  and .fresh_install == "pass"
  and .human_ui_validation == "pending_exact_candidate_requalification"' \
  "$artifact_stage/release-receipt.json" >/dev/null \
  || block fetched_release_receipt_invalid 'The returned application receipt is invalid.' 'Do not publish it.'
python3 -B - "$artifact_stage/ishikawa-v1.3.1.tar.gz" "$work_root/extracted" <<'PY' \
  || block fetched_application_archive_invalid \
    'The returned application archive violates the portable path/type boundary.' \
    'Do not publish it.'
import sys
import tarfile
from pathlib import Path, PurePosixPath

archive_path = Path(sys.argv[1])
destination = Path(sys.argv[2])
with tarfile.open(archive_path, "r:gz") as archive:
    members = archive.getmembers()
    if not members:
        raise SystemExit(1)
    for member in members:
        path = PurePosixPath(member.name)
        if path.is_absolute() or ".." in path.parts or not path.parts or path.parts[0] != "ishikawa-v1.3.1":
            raise SystemExit(1)
        if not (member.isfile() or member.isdir()):
            raise SystemExit(1)
    destination.mkdir(mode=0o700)
    archive.extractall(destination, filter="data")
PY
bash "$work_root/extracted/ishikawa-v1.3.1/verify-ishikawa-release" >/dev/null \
  || block fetched_application_verification_failed 'The returned archive failed its bundled verifier.' 'Do not publish it.'
emit "state=pass;application_sha256=$application_sha256;transfer_bytes=$(stat -Lc %s -- "$artifact_stage/ishikawa-v1.3.1.tar.gz")" RETURN

stage='local_publication'
mkdir -p -- "$artifact_parent/superseded"
artifact_backup=''
if [[ -e "$artifact_current" || -L "$artifact_current" ]]; then
  [[ -d "$artifact_current" && ! -L "$artifact_current" ]] \
    || block current_handoff_unsafe 'The current application handoff is not a regular directory.' 'Inspect the local artifact lane.'
  artifact_backup="$artifact_parent/superseded/ishikawa-v1.3.1-candidate-current-${timestamp}-$$"
  [[ ! -e "$artifact_backup" && ! -L "$artifact_backup" ]] \
    || block superseded_handoff_exists 'The selected superseded path already exists.' 'Inspect the local artifact lane.'
  mv -- "$artifact_current" "$artifact_backup"
fi
if ! mv -- "$artifact_stage" "$artifact_current"; then
  [[ -z "$artifact_backup" ]] || mv -- "$artifact_backup" "$artifact_current"
  block local_publication_failed 'The verified application handoff could not be published atomically.' 'The prior handoff was restored; inspect local storage.'
fi
artifact_stage=''
(
  cd -- "$artifact_current"
  sha256sum --check --strict SHA256SUMS >/dev/null
) || block published_handoff_checksum_failed 'The published application handoff failed final verification.' 'Stop and inspect the local artifact lane.'
emit "state=pass;handoff=$artifact_current" PUBLISH

stage='remote_cleanup'
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "rm -rf -- '$remote_root' && test ! -e '$remote_root'" >/dev/null \
  || block remote_cleanup_failed 'The private EmceeDanko transfer directory was not removed.' 'Remove only the reported private transfer directory before continuing.'
remote_created=false
timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1 || true
master_started=false
emit 'state=pass;private_transfer_removed=true;runtime_image_unchanged=true' CLEANUP
emit "report_path=$report_path;application_sha256=$application_sha256;runtime_image_id=$runtime_image_id;next_gate=independent_application_review_and_exact_artifact_requalification" SUMMARY
result pass | tee -a "$report_path"
