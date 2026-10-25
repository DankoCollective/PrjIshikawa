#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Prepare the neutral read-only Ishikawa native-prerequisite inventory kit.
#
# Mental model:
#   Bind the accepted v1 release, package only the final neutral inventory
#   files, prove deterministic checksums and naming-boundary compliance, and
#   retain one transport archive without contacting any target.
#
# Inputs or prerequisites:
#   Clean Script 109 evidence and the reviewed inventory-kit source files.
#
# Outputs:
#   One checksum-bound transport archive, qualification receipt, and report.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/110_prepare_ubuntu26_native_prerequisite_inventory.sh --run

usage() {
  sed -n '3,18p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Assemble and retain the inventory kit.' \
    '  --validate-only Validate the same source without retaining outputs.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly SOURCE_ROOT="$PHASE_ROOT/Ishikawa/packaging/native-prerequisite-inventory"
readonly SOURCE_README="$SOURCE_ROOT/README.md"
readonly SOURCE_INSPECTOR="$SOURCE_ROOT/inspect-native-prerequisites"
readonly ACCEPTED_REPORT="$REPO_ROOT/local/reports/ishikawa-v1-release/ishikawa_v1_acceptance_20261021T042530Z_XLvaNG.txt"
readonly ACCEPTED_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/v1-release/ishikawa_v1_acceptance_20261021T042530Z.json"
readonly ACCEPTED_CHECKSUM="$ACCEPTED_ARTIFACT.sha256"
readonly ACCEPTED_REPORT_SHA256='c46b415edda072227bcce88f523565160268317e1608a8861e5598203305bf2c'
readonly ACCEPTED_ARTIFACT_SHA256='efb372190d179f3bcf32cec5a7f0d4acc725046ac4e1e253c26d7c4db3dcedf7'
readonly ACCEPTED_CHECKSUM_SHA256='b342afdd95916c1046af17546ae33e1f1881ae5963c0701fc7dbcfb0bbc3802b'
readonly ACCEPTED_V1_ARCHIVE_SHA256='c848680051786b2b3c6ac454b3f007be1632d45215ddf9c8f1d4d04b924845b1'
readonly KIT_NAME='ishikawa-native-prerequisite-inventory'
readonly OUTPUT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/native-prerequisite-inventory-kit"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-native-prerequisite-inventory-kit"
readonly FORBIDDEN_PATTERN='phase[-_ ]*[0-9]|org[-_ ]*lab|danko|agent|repository|script[[:space:]_-]*[0-9]+|local/artifacts|/mnt/|\.git/'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_110_native_prerequisite_inventory_kit=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || { printf 'script_110_native_prerequisite_inventory_kit=blocked;reason=mode_invalid\n' >&2; exit 2; }

for required in awk bash chmod cmp cp date find grep gzip install mkdir mktemp rm sed sha256sum sort stat tar tee; do
  command -v "$required" >/dev/null 2>&1 || { printf 'script_110_native_prerequisite_inventory_kit=blocked;reason=local_command_missing\n' >&2; exit 2; }
done
for file in "$SOURCE_README" "$SOURCE_INSPECTOR" "$ACCEPTED_REPORT" "$ACCEPTED_ARTIFACT" "$ACCEPTED_CHECKSUM"; do
  [[ -f "$file" && ! -L "$file" && -r "$file" ]] || { printf 'script_110_native_prerequisite_inventory_kit=blocked;reason=required_input_missing\n' >&2; exit 2; }
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_110_native_prerequisite_inventory_kit=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}
check_sha256 "$ACCEPTED_REPORT" "$ACCEPTED_REPORT_SHA256" accepted_report
check_sha256 "$ACCEPTED_ARTIFACT" "$ACCEPTED_ARTIFACT_SHA256" accepted_artifact
check_sha256 "$ACCEPTED_CHECKSUM" "$ACCEPTED_CHECKSUM_SHA256" accepted_checksum
(cd -- "$(dirname -- "$ACCEPTED_CHECKSUM")" && sha256sum --check --strict "$(basename -- "$ACCEPTED_CHECKSUM")" >/dev/null) || { printf 'script_110_native_prerequisite_inventory_kit=blocked;reason=accepted_checksum_failed\n' >&2; exit 2; }
for fact in \
  "script_sha256=23d7074915bb43fd19c8e30cd6c747140e2fed84950d834fcd482719095f2c04;archive_sha256=$ACCEPTED_V1_ARCHIVE_SHA256;archive_bytes=183236" \
  'host_qualification=pass' \
  'package_rebuilt=false;package_duplicated=false;deployment_payload_portable=true;native_prerequisite_packages_included=false' \
  'script_109_v1_acceptance=pass;next_gate=qualify_ubuntu_26_native_prerequisites_before_org_install'; do
  grep -Fq "$fact" "$ACCEPTED_REPORT" || { printf 'script_110_native_prerequisite_inventory_kit=blocked;reason=accepted_report_contract_failed\n' >&2; exit 2; }
done

bash -n "${BASH_SOURCE[0]}" "$SOURCE_INSPECTOR"
bash "$SOURCE_INSPECTOR" --help >/dev/null
if grep -ERiq -- "$FORBIDDEN_PATTERN" "$SOURCE_ROOT"; then
  printf 'script_110_native_prerequisite_inventory_kit=blocked;reason=transfer_jargon_found\n' >&2
  exit 2
fi
if grep -ERq -- 'BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY|Authorization:[[:space:]]*Bearer[[:space:]]+[^$]' "$SOURCE_ROOT"; then
  printf 'script_110_native_prerequisite_inventory_kit=blocked;reason=credential_material_found\n' >&2
  exit 2
fi

work_root="$(mktemp -d /tmp/ishikawa-script-110.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  [[ "$work_root" == /tmp/ishikawa-script-110.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

assemble() {
  local destination="$1" kit_root="$1/$KIT_NAME"
  install -d -m 0755 -- "$kit_root"
  install -m 0644 -- "$SOURCE_README" "$kit_root/README.md"
  install -m 0755 -- "$SOURCE_INSPECTOR" "$kit_root/inspect-native-prerequisites"
  (
    cd -- "$kit_root"
    sha256sum README.md inspect-native-prerequisites >SHA256SUMS
    sha256sum --check --strict SHA256SUMS >/dev/null
  )
}

mkdir -p -- "$work_root/build-a" "$work_root/build-b"
assemble "$work_root/build-a"
assemble "$work_root/build-b"
for root in "$work_root/build-a/$KIT_NAME" "$work_root/build-b/$KIT_NAME"; do
  [[ "$(find "$root" -type f | awk 'END {print NR+0}')" == 3 ]] || { printf 'script_110_native_prerequisite_inventory_kit=blocked;reason=file_count_mismatch\n' >&2; exit 1; }
  find "$root" -type l -print -quit | grep -q . && { printf 'script_110_native_prerequisite_inventory_kit=blocked;reason=symlink_found\n' >&2; exit 1; }
  (cd -- "$root" && sha256sum --check --strict SHA256SUMS >/dev/null) || { printf 'script_110_native_prerequisite_inventory_kit=blocked;reason=kit_checksum_failed\n' >&2; exit 1; }
done
cmp -s \
  <(cd -- "$work_root/build-a/$KIT_NAME" && find . -type f -printf '%P\n' | sort | while IFS= read -r file; do sha256sum "$file"; done) \
  <(cd -- "$work_root/build-b/$KIT_NAME" && find . -type f -printf '%P\n' | sort | while IFS= read -r file; do sha256sum "$file"; done) || { printf 'script_110_native_prerequisite_inventory_kit=blocked;reason=kit_not_reproducible\n' >&2; exit 1; }

temporary_archive="$work_root/$KIT_NAME.tar.gz"
tar --sort=name --format=posix --pax-option=delete=atime,delete=ctime --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner -C "$work_root/build-a" -cf - "$KIT_NAME" | gzip -n >"$temporary_archive"
mkdir -p -- "$work_root/extracted"
tar -xzf "$temporary_archive" -C "$work_root/extracted"
(cd -- "$work_root/extracted/$KIT_NAME" && sha256sum --check --strict SHA256SUMS >/dev/null) || { printf 'script_110_native_prerequisite_inventory_kit=blocked;reason=extracted_kit_verification_failed\n' >&2; exit 1; }
archive_sha256="$(sha256sum "$temporary_archive" | awk '{print $1}')"
archive_bytes="$(stat -c '%s' "$temporary_archive")"
inspector_sha256="$(sha256sum "$SOURCE_INSPECTOR" | awk '{print $1}')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_native_prerequisite_inventory_kit' \
    "script_sha256=$script_sha256;inspector_sha256=$inspector_sha256" \
    "accepted_v1_archive_sha256=$ACCEPTED_V1_ARCHIVE_SHA256;accepted_report_sha256=$ACCEPTED_REPORT_SHA256" \
    "inventory_archive_sha256=$archive_sha256;inventory_archive_bytes=$archive_bytes;package_files=3" \
    'deterministic_archive=true;internal_checksums=pass;transfer_jargon=false;credential_material=false' \
    'target_contact=false;network_contact=false;package_downloaded=false;package_installed=false' \
    'script_110_native_prerequisite_inventory_kit_source=pass'
  exit 0
fi

mkdir -p -- "$OUTPUT_ROOT" "$REPORT_ROOT"
archive_name="$KIT_NAME-${archive_sha256:0:16}.tar.gz"
archive_path="$OUTPUT_ROOT/$archive_name"
checksum_path="$archive_path.sha256"
qualification_path="$OUTPUT_ROOT/native_prerequisite_inventory_kit_qualification_${archive_sha256:0:16}.json"
qualification_checksum="$qualification_path.sha256"
[[ ! -e "$archive_path" && ! -L "$archive_path" && ! -e "$checksum_path" && ! -L "$checksum_path" && ! -e "$qualification_path" && ! -L "$qualification_path" && ! -e "$qualification_checksum" && ! -L "$qualification_checksum" ]] || { printf 'script_110_native_prerequisite_inventory_kit=blocked;reason=output_path_exists\n' >&2; exit 1; }
cp -- "$temporary_archive" "$archive_path"
printf '%s  %s\n' "$archive_sha256" "$archive_name" >"$checksum_path"
printf '{"accepted_v1_archive_sha256":"%s","archive_bytes":%s,"archive_sha256":"%s","deterministic_archive":true,"internal_checksums":"pass","network_contact":false,"package_file_count":3,"package_installed":false,"receipt_schema_version":1,"target_contact":false,"transfer_jargon":false}\n' "$ACCEPTED_V1_ARCHIVE_SHA256" "$archive_bytes" "$archive_sha256" >"$qualification_path"
qualification_sha256="$(sha256sum "$qualification_path" | awk '{print $1}')"
printf '%s  %s\n' "$qualification_sha256" "$(basename -- "$qualification_path")" >"$qualification_checksum"
(cd -- "$OUTPUT_ROOT" && sha256sum --check --strict "$(basename -- "$checksum_path")" "$(basename -- "$qualification_checksum")" >/dev/null)
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/native_prerequisite_inventory_kit_${timestamp}_XXXXXX.txt")"
{
  printf 'purpose=prepare_neutral_ubuntu26_native_prerequisite_inventory_kit\n'
  printf 'started_utc=%s\n' "$timestamp"
  printf 'script_sha256=%s;inspector_sha256=%s\n' "$script_sha256" "$inspector_sha256"
  printf 'accepted_v1_archive_sha256=%s;accepted_report_sha256=%s\n' "$ACCEPTED_V1_ARCHIVE_SHA256" "$ACCEPTED_REPORT_SHA256"
  printf 'archive=%s;archive_sha256=%s;archive_bytes=%s;package_files=3\n' "$archive_path" "$archive_sha256" "$archive_bytes"
  printf 'deterministic_archive=true;internal_checksums=pass;transfer_jargon=false;credential_material=false\n'
  printf 'target_contact=false;network_contact=false;package_downloaded=false;package_installed=false;service_changed=false\n'
  printf 'accepted_artifact=%s;accepted_artifact_sha256=%s;accepted_checksum=%s\n' "$qualification_path" "$qualification_sha256" "$qualification_checksum"
  printf 'script_110_native_prerequisite_inventory_kit=pass;next_gate=run_inventory_kit_on_ubuntu_26_application_host\n'
} | tee "$report_path"
chmod 0600 "$report_path" "$qualification_path" "$qualification_checksum" 2>/dev/null || true
