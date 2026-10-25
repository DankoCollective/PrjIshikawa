#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Prepare the repository-free Ishikawa v1.2 native-inventory handoff.
#
# Mental model:
#   Bind the accepted Script 141 receipt, wrap the unchanged neutral inventory
#   kit with one neutral target command, build twice, verify exact contents,
#   and retain one hand-carried archive without contacting the target.
#
# Inputs or prerequisites:
#   Clean Script 141 evidence, its exact inventory kit, and reviewed neutral
#   handoff source files.
#
# Outputs or artifact lane:
#   One checksum-bound transport archive, qualification receipt, and report.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/142_prepare_v1_2_native_inventory_handoff.sh --run

usage() {
  sed -n '3,18p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Assemble and retain the neutral handoff.' \
    '  --validate-only Validate the same source without retaining outputs.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly SOURCE_ROOT="$PHASE_ROOT/Ishikawa/packaging/native-prerequisite-handoff"
readonly SOURCE_README="$SOURCE_ROOT/README.md"
readonly SOURCE_RUNNER="$SOURCE_ROOT/run-native-prerequisite-inventory"

readonly READINESS_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.2-native-readiness/ishikawa_v1_2_native_readiness_20261021T225510Z_uh6jsM.txt"
readonly READINESS_RECEIPT="$REPO_ROOT/local/artifacts/ishikawa/v1.2-native-readiness/ishikawa_v1_2_native_readiness_20261021T225510Z.json"
readonly READINESS_RECEIPT_CHECKSUM="$READINESS_RECEIPT.sha256"
readonly INVENTORY_ARCHIVE="$REPO_ROOT/local/artifacts/ishikawa/native-prerequisite-inventory-kit/ishikawa-native-prerequisite-inventory-bbca7aa5c4325308.tar.gz"

readonly READINESS_REPORT_SHA256='4147103c53df1b6b1c95d26364293794d43d7e23180e7e399c5e7f154618849a'
readonly READINESS_RECEIPT_SHA256='a971cd5a0133a28abb431c80f8d4dccdc064bb2304f0c31f4f37f9c550cc952f'
readonly READINESS_RECEIPT_CHECKSUM_SHA256='8d3d01b6894005eaa8e358653f66dd059ab5f0cfd046bf9317d00dc22547ff31'
readonly INVENTORY_ARCHIVE_SHA256='bbca7aa5c4325308427a2ca485924cbd2febbf39fa604b82d1c28abe0bdaf29f'
readonly RELEASE_ARCHIVE_SHA256='6d4a2c169574f23b6c707a9641f936c16d2948e170ff46a77fa246cf2e3d680d'

readonly HANDOFF_NAME='ishikawa-native-prerequisite-handoff'
readonly INNER_ARCHIVE_NAME='ishikawa-native-prerequisite-inventory.tar.gz'
readonly FORBIDDEN_PATTERN='phase[-_ ]*[0-9]|org[-_ ]*lab|danko|agent|repository|script[[:space:]_-]*[0-9]+|local/artifacts|/mnt/|\.git/'
readonly OUTPUT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v1.2-native-inventory-handoff"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.2-native-inventory-handoff"

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_142_native_inventory_handoff=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_142_native_inventory_handoff=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in awk bash basename chmod cmp cp date dirname find grep gzip install mkdir mktemp rm sed sha256sum sort stat tar tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_142_native_inventory_handoff=blocked;reason=local_command_missing;command=%s\n' "$required" >&2
    exit 2
  }
done
for file in \
  "$SOURCE_README" "$SOURCE_RUNNER" "$READINESS_REPORT" "$READINESS_RECEIPT" \
  "$READINESS_RECEIPT_CHECKSUM" "$INVENTORY_ARCHIVE"; do
  [[ -f "$file" && ! -L "$file" && -r "$file" ]] || {
    printf 'script_142_native_inventory_handoff=blocked;reason=required_input_missing\n' >&2
    exit 2
  }
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_142_native_inventory_handoff=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}
check_sha256 "$READINESS_REPORT" "$READINESS_REPORT_SHA256" readiness_report
check_sha256 "$READINESS_RECEIPT" "$READINESS_RECEIPT_SHA256" readiness_receipt
check_sha256 "$READINESS_RECEIPT_CHECKSUM" "$READINESS_RECEIPT_CHECKSUM_SHA256" readiness_receipt_checksum
check_sha256 "$INVENTORY_ARCHIVE" "$INVENTORY_ARCHIVE_SHA256" inventory_archive
(
  cd -- "$(dirname -- "$READINESS_RECEIPT_CHECKSUM")"
  sha256sum --check --strict "$(basename -- "$READINESS_RECEIPT_CHECKSUM")" >/dev/null
) || {
  printf 'script_142_native_inventory_handoff=blocked;reason=readiness_receipt_checksum_failed\n' >&2
  exit 2
}
for fact in \
  "release_archive_sha256=$RELEASE_ARCHIVE_SHA256;release_name=Ishikawa_v1.2" \
  "inventory_archive_sha256=$INVENTORY_ARCHIVE_SHA256" \
  'dependency_contracts_compared=2;dependency_contracts_unchanged=true;inventory_kit_reused=true' \
  'expected_os_version=26.04;expected_architecture=amd64;target_inventory_status=pending' \
  'script_141_v1_2_native_readiness=pass;next_gate=run_neutral_inventory_kit_on_ubuntu_26_target'; do
  grep -Fq "$fact" "$READINESS_REPORT" || {
    printf 'script_142_native_inventory_handoff=blocked;reason=readiness_evidence_contract_failed\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}" "$SOURCE_RUNNER"
bash "$SOURCE_RUNNER" --help >/dev/null
if grep -ERiq -- "$FORBIDDEN_PATTERN" "$SOURCE_ROOT"; then
  printf 'script_142_native_inventory_handoff=blocked;reason=transfer_jargon_found\n' >&2
  exit 2
fi
if grep -ERq -- 'BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY|Authorization:[[:space:]]*Bearer[[:space:]]+[^$]' "$SOURCE_ROOT"; then
  printf 'script_142_native_inventory_handoff=blocked;reason=credential_material_found\n' >&2
  exit 2
fi

work_root="$(mktemp -d /tmp/ishikawa-script-142.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  [[ "$work_root" == /tmp/ishikawa-script-142.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

assemble() {
  local destination="$1"
  local handoff_root="$destination/$HANDOFF_NAME"
  install -d -m 0755 -- "$handoff_root"
  install -m 0644 -- "$SOURCE_README" "$handoff_root/README.md"
  install -m 0755 -- "$SOURCE_RUNNER" "$handoff_root/run-native-prerequisite-inventory"
  cp -- "$INVENTORY_ARCHIVE" "$handoff_root/$INNER_ARCHIVE_NAME"
  printf '%s  %s\n' "$INVENTORY_ARCHIVE_SHA256" "$INNER_ARCHIVE_NAME" >"$handoff_root/$INNER_ARCHIVE_NAME.sha256"
  (
    cd -- "$handoff_root"
    sha256sum README.md run-native-prerequisite-inventory "$INNER_ARCHIVE_NAME" "$INNER_ARCHIVE_NAME.sha256" >SHA256SUMS
    sha256sum --check --strict SHA256SUMS >/dev/null
  )
}

mkdir -p -- "$work_root/build-a" "$work_root/build-b"
assemble "$work_root/build-a"
assemble "$work_root/build-b"
for root in "$work_root/build-a/$HANDOFF_NAME" "$work_root/build-b/$HANDOFF_NAME"; do
  [[ "$(find "$root" -type f | awk 'END {print NR+0}')" == 5 ]] || {
    printf 'script_142_native_inventory_handoff=blocked;reason=file_count_mismatch\n' >&2
    exit 1
  }
  find "$root" -type l -print -quit | grep -q . && {
    printf 'script_142_native_inventory_handoff=blocked;reason=symlink_found\n' >&2
    exit 1
  }
  (
    cd -- "$root"
    sha256sum --check --strict SHA256SUMS >/dev/null
  ) || {
    printf 'script_142_native_inventory_handoff=blocked;reason=handoff_checksum_failed\n' >&2
    exit 1
  }
  bash "$root/run-native-prerequisite-inventory" --validate-only >/dev/null || {
    printf 'script_142_native_inventory_handoff=blocked;reason=handoff_validation_failed\n' >&2
    exit 1
  }
done
cmp -s \
  <(cd -- "$work_root/build-a/$HANDOFF_NAME" && find . -type f -printf '%P\n' | sort | while IFS= read -r file; do sha256sum "$file"; done) \
  <(cd -- "$work_root/build-b/$HANDOFF_NAME" && find . -type f -printf '%P\n' | sort | while IFS= read -r file; do sha256sum "$file"; done) || {
  printf 'script_142_native_inventory_handoff=blocked;reason=handoff_not_reproducible\n' >&2
  exit 1
}

temporary_archive="$work_root/$HANDOFF_NAME.tar.gz"
tar --sort=name --format=posix --pax-option=delete=atime,delete=ctime \
  --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner \
  -C "$work_root/build-a" -cf - "$HANDOFF_NAME" | gzip -n >"$temporary_archive"
mkdir -p -- "$work_root/extracted"
tar -xzf "$temporary_archive" -C "$work_root/extracted"
(
  cd -- "$work_root/extracted/$HANDOFF_NAME"
  sha256sum --check --strict SHA256SUMS >/dev/null
  bash ./run-native-prerequisite-inventory --validate-only >/dev/null
) || {
  printf 'script_142_native_inventory_handoff=blocked;reason=extracted_handoff_validation_failed\n' >&2
  exit 1
}

archive_sha256="$(sha256sum "$temporary_archive" | awk '{print $1}')"
archive_bytes="$(stat -c '%s' "$temporary_archive")"
runner_sha256="$(sha256sum "$SOURCE_RUNNER" | awk '{print $1}')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_ishikawa_v1_2_native_inventory_handoff' \
    "script_sha256=$script_sha256;runner_sha256=$runner_sha256" \
    "release_archive_sha256=$RELEASE_ARCHIVE_SHA256;inventory_archive_sha256=$INVENTORY_ARCHIVE_SHA256" \
    "handoff_archive_sha256=$archive_sha256;handoff_archive_bytes=$archive_bytes;handoff_files=5" \
    'deterministic_archive=true;internal_checksums=pass;neutral_runner_validation=pass' \
    'target_contact=false;network_contact=false;package_downloaded=false;package_installed=false' \
    'script_142_native_inventory_handoff_source=pass'
  exit 0
fi

umask 077
mkdir -p -- "$OUTPUT_ROOT" "$REPORT_ROOT"
archive_name="$HANDOFF_NAME-${archive_sha256:0:16}.tar.gz"
archive_path="$OUTPUT_ROOT/$archive_name"
archive_checksum="$archive_path.sha256"
qualification_path="$OUTPUT_ROOT/native_inventory_handoff_qualification_${archive_sha256:0:16}.json"
qualification_checksum="$qualification_path.sha256"
for output in "$archive_path" "$archive_checksum" "$qualification_path" "$qualification_checksum"; do
  [[ ! -e "$output" && ! -L "$output" ]] || {
    printf 'script_142_native_inventory_handoff=blocked;reason=output_path_exists\n' >&2
    exit 1
  }
done
cp -- "$temporary_archive" "$archive_path"
printf '%s  %s\n' "$archive_sha256" "$archive_name" >"$archive_checksum"
printf '{"archive_bytes":%s,"archive_sha256":"%s","deterministic_archive":true,"expected_architecture":"amd64","expected_os_version":"26.04","handoff_file_count":5,"inventory_archive_sha256":"%s","network_contact":false,"neutral_runner_validation":"pass","package_downloaded":false,"package_installed":false,"receipt_schema_version":1,"release_archive_sha256":"%s","target_contact":false}\n' \
  "$archive_bytes" "$archive_sha256" "$INVENTORY_ARCHIVE_SHA256" "$RELEASE_ARCHIVE_SHA256" >"$qualification_path"
qualification_sha256="$(sha256sum "$qualification_path" | awk '{print $1}')"
printf '%s  %s\n' "$qualification_sha256" "$(basename -- "$qualification_path")" >"$qualification_checksum"
(
  cd -- "$OUTPUT_ROOT"
  sha256sum --check --strict "$(basename -- "$archive_checksum")" "$(basename -- "$qualification_checksum")" >/dev/null
)

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/native_inventory_handoff_${timestamp}_XXXXXX.txt")"
{
  printf 'purpose=prepare_repository_free_ishikawa_v1_2_native_inventory_handoff\n'
  printf 'started_utc=%s\n' "$timestamp"
  printf 'script_sha256=%s;runner_sha256=%s\n' "$script_sha256" "$runner_sha256"
  printf 'readiness_report_sha256=%s;readiness_receipt_sha256=%s\n' "$READINESS_REPORT_SHA256" "$READINESS_RECEIPT_SHA256"
  printf 'release_archive_sha256=%s;inventory_archive_sha256=%s\n' "$RELEASE_ARCHIVE_SHA256" "$INVENTORY_ARCHIVE_SHA256"
  printf 'archive=%s;archive_sha256=%s;archive_bytes=%s;handoff_files=5\n' "$archive_path" "$archive_sha256" "$archive_bytes"
  printf 'deterministic_archive=true;internal_checksums=pass;neutral_runner_validation=pass;transfer_jargon=false;credential_material=false\n'
  printf 'target_contact=false;network_contact=false;package_downloaded=false;package_installed=false;service_changed=false\n'
  printf 'accepted_artifact=%s;accepted_artifact_sha256=%s;accepted_checksum=%s\n' "$qualification_path" "$qualification_sha256" "$qualification_checksum"
  printf 'script_142_native_inventory_handoff=pass;next_gate=hand_carry_and_run_neutral_inventory_on_ubuntu_26_target\n'
} | tee "$report_path"
chmod 0600 "$report_path" "$qualification_path" "$qualification_checksum" 2>/dev/null || true

