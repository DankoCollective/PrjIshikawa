#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Bind the accepted Ishikawa v1.2 release to the existing neutral Ubuntu 26
#   native-prerequisite inventory kit.
#
# Mental model:
#   Reverify the accepted release and inventory-kit evidence, prove that the
#   v1 and v1.2 dependency contracts are identical, inspect the existing kit,
#   and retain one readiness receipt without rebuilding or contacting a target.
#
# Inputs or prerequisites:
#   Clean Script 140 evidence, the accepted v1 and v1.2 deployment archives,
#   and the checksum-bound inventory kit prepared by Script 110.
#
# Outputs or artifact lane:
#   One content-free v1.2 native-readiness receipt and local report. The exact
#   existing inventory archive remains the target-side input.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/141_bind_v1_2_native_prerequisite_inventory.sh --run

usage() {
  sed -n '3,22p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Bind and retain the v1.2 native-readiness receipt.' \
    '  --validate-only Validate the same inputs without retaining outputs.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"

readonly RELEASE_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.2-release/ishikawa_v1_2_acceptance_20261021T223500Z_LX9xEA.txt"
readonly RELEASE_RECEIPT="$REPO_ROOT/local/artifacts/ishikawa/v1.2-release/ishikawa_v1_2_acceptance_20261021T223500Z.json"
readonly RELEASE_RECEIPT_CHECKSUM="$RELEASE_RECEIPT.sha256"
readonly V1_ARCHIVE="$REPO_ROOT/local/artifacts/ishikawa/v1-deployment-package/ishikawa-v1-deployment-package-c848680051786b2b.tar.gz"
readonly V1_2_ARCHIVE="$REPO_ROOT/local/artifacts/ishikawa/v1.2-deployment-package/ishikawa-v1.2-deployment-package-6d4a2c169574f23b.tar.gz"

readonly INVENTORY_REPORT="$REPO_ROOT/local/reports/ishikawa-native-prerequisite-inventory-kit/native_prerequisite_inventory_kit_20261021T043024Z_C5dlhj.txt"
readonly INVENTORY_ARCHIVE="$REPO_ROOT/local/artifacts/ishikawa/native-prerequisite-inventory-kit/ishikawa-native-prerequisite-inventory-bbca7aa5c4325308.tar.gz"
readonly INVENTORY_ARCHIVE_CHECKSUM="$INVENTORY_ARCHIVE.sha256"
readonly INVENTORY_QUALIFICATION="$REPO_ROOT/local/artifacts/ishikawa/native-prerequisite-inventory-kit/native_prerequisite_inventory_kit_qualification_bbca7aa5c4325308.json"
readonly INVENTORY_QUALIFICATION_CHECKSUM="$INVENTORY_QUALIFICATION.sha256"

readonly RELEASE_REPORT_SHA256='def560368c5858709a5462cfc641ab4e03b6e4414eef82338628a7be93510693'
readonly RELEASE_RECEIPT_SHA256='bfe9c792d261a12ed7d12bf6c01c5fefcedc92864a5474557d190a0628132b9f'
readonly RELEASE_RECEIPT_CHECKSUM_SHA256='5d16272a7821e554a212d06c5514ef957f563b3f7f23f5ce6458063e3bbaba37'
readonly V1_ARCHIVE_SHA256='c848680051786b2b3c6ac454b3f007be1632d45215ddf9c8f1d4d04b924845b1'
readonly V1_2_ARCHIVE_SHA256='6d4a2c169574f23b6c707a9641f936c16d2948e170ff46a77fa246cf2e3d680d'
readonly INVENTORY_REPORT_SHA256='62288f5af045f91dc075234a0bba855c32488748529386451751c61f3fd91539'
readonly INVENTORY_ARCHIVE_SHA256='bbca7aa5c4325308427a2ca485924cbd2febbf39fa604b82d1c28abe0bdaf29f'
readonly INVENTORY_ARCHIVE_CHECKSUM_SHA256='2cbf6062c9de83e6064022051a226e8d41417f2687764b4b45bcb309c3a7369f'
readonly INVENTORY_QUALIFICATION_SHA256='a3e4f73d282ce591191788dde646ea76a436c40a00fa47185ab46a6470320306'
readonly INVENTORY_QUALIFICATION_CHECKSUM_SHA256='6c2d5e0913afae94446c56b0874d1c7ae566e394a8decb7c2e5043f1afe9acb2'

readonly V1_ROOT_NAME='ishikawa-v1-deployment-package'
readonly V1_2_ROOT_NAME='ishikawa-v1.2-deployment-package'
readonly INVENTORY_ROOT_NAME='ishikawa-native-prerequisite-inventory'
readonly FORBIDDEN_TRANSFER_PATTERN='phase[-_ ]*[0-9]|org[-_ ]*lab|danko|agent|repository|script[[:space:]_-]*[0-9]+|local/artifacts|/mnt/|\.git/'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.2-native-readiness"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v1.2-native-readiness"

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_141_v1_2_native_readiness=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_141_v1_2_native_readiness=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in awk bash basename chmod cmp date dirname find grep mkdir mktemp rm sed sha256sum tar tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_141_v1_2_native_readiness=blocked;reason=local_command_missing;command=%s\n' "$required" >&2
    exit 2
  }
done

readonly -a INPUTS=(
  "$RELEASE_REPORT" "$RELEASE_RECEIPT" "$RELEASE_RECEIPT_CHECKSUM"
  "$V1_ARCHIVE" "$V1_2_ARCHIVE"
  "$INVENTORY_REPORT" "$INVENTORY_ARCHIVE" "$INVENTORY_ARCHIVE_CHECKSUM"
  "$INVENTORY_QUALIFICATION" "$INVENTORY_QUALIFICATION_CHECKSUM"
)
for file in "${INPUTS[@]}"; do
  [[ -f "$file" && ! -L "$file" && -r "$file" ]] || {
    printf 'script_141_v1_2_native_readiness=blocked;reason=accepted_input_missing\n' >&2
    exit 2
  }
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_141_v1_2_native_readiness=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}

check_sha256 "$RELEASE_REPORT" "$RELEASE_REPORT_SHA256" release_report
check_sha256 "$RELEASE_RECEIPT" "$RELEASE_RECEIPT_SHA256" release_receipt
check_sha256 "$RELEASE_RECEIPT_CHECKSUM" "$RELEASE_RECEIPT_CHECKSUM_SHA256" release_receipt_checksum
check_sha256 "$V1_ARCHIVE" "$V1_ARCHIVE_SHA256" v1_archive
check_sha256 "$V1_2_ARCHIVE" "$V1_2_ARCHIVE_SHA256" v1_2_archive
check_sha256 "$INVENTORY_REPORT" "$INVENTORY_REPORT_SHA256" inventory_report
check_sha256 "$INVENTORY_ARCHIVE" "$INVENTORY_ARCHIVE_SHA256" inventory_archive
check_sha256 "$INVENTORY_ARCHIVE_CHECKSUM" "$INVENTORY_ARCHIVE_CHECKSUM_SHA256" inventory_archive_checksum
check_sha256 "$INVENTORY_QUALIFICATION" "$INVENTORY_QUALIFICATION_SHA256" inventory_qualification
check_sha256 "$INVENTORY_QUALIFICATION_CHECKSUM" "$INVENTORY_QUALIFICATION_CHECKSUM_SHA256" inventory_qualification_checksum

for sidecar in \
  "$RELEASE_RECEIPT_CHECKSUM" \
  "$INVENTORY_ARCHIVE_CHECKSUM" \
  "$INVENTORY_QUALIFICATION_CHECKSUM"; do
  (
    cd -- "$(dirname -- "$sidecar")"
    sha256sum --check --strict "$(basename -- "$sidecar")" >/dev/null
  ) || {
    printf 'script_141_v1_2_native_readiness=blocked;reason=accepted_checksum_failed\n' >&2
    exit 2
  }
done

for fact in \
  "script_sha256=" \
  "archive_sha256=$V1_2_ARCHIVE_SHA256;archive_bytes=201883" \
  'package_files=111;application_files=104;database_files=4;historical_mutation_files=0' \
  'predecessor_release=Ishikawa_v1.1;' \
  'native_prerequisite_packages_included=false' \
  'script_140_v1_2_acceptance=pass;next_gate=review_org_lab_deployment_readiness'; do
  grep -Fq "$fact" "$RELEASE_REPORT" || {
    printf 'script_141_v1_2_native_readiness=blocked;reason=release_evidence_contract_failed\n' >&2
    exit 2
  }
done
for fact in \
  "accepted_v1_archive_sha256=$V1_ARCHIVE_SHA256" \
  "archive_sha256=$INVENTORY_ARCHIVE_SHA256;archive_bytes=4173;package_files=3" \
  'deterministic_archive=true;internal_checksums=pass;transfer_jargon=false;credential_material=false' \
  'target_contact=false;network_contact=false;package_downloaded=false;package_installed=false;service_changed=false' \
  'script_110_native_prerequisite_inventory_kit=pass;next_gate=run_inventory_kit_on_ubuntu_26_application_host'; do
  grep -Fq "$fact" "$INVENTORY_REPORT" || {
    printf 'script_141_v1_2_native_readiness=blocked;reason=inventory_evidence_contract_failed\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}"
work_root="$(mktemp -d /tmp/ishikawa-script-141.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  [[ "$work_root" == /tmp/ishikawa-script-141.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p -- "$work_root/v1" "$work_root/v1.2" "$work_root/inventory"
tar -xzf "$V1_ARCHIVE" -C "$work_root/v1"
tar -xzf "$V1_2_ARCHIVE" -C "$work_root/v1.2"
tar -xzf "$INVENTORY_ARCHIVE" -C "$work_root/inventory"

readonly V1_ROOT="$work_root/v1/$V1_ROOT_NAME"
readonly V1_2_ROOT="$work_root/v1.2/$V1_2_ROOT_NAME"
readonly INVENTORY_ROOT="$work_root/inventory/$INVENTORY_ROOT_NAME"
for root in "$V1_ROOT" "$V1_2_ROOT" "$INVENTORY_ROOT"; do
  [[ -d "$root" && ! -L "$root" ]] || {
    printf 'script_141_v1_2_native_readiness=blocked;reason=archive_root_invalid\n' >&2
    exit 1
  }
done

bash "$V1_ROOT/verify-ishikawa-v1" >/dev/null
bash "$V1_2_ROOT/verify-ishikawa-v1.2" >/dev/null
(
  cd -- "$INVENTORY_ROOT"
  sha256sum --check --strict SHA256SUMS >/dev/null
)
[[ "$(find "$INVENTORY_ROOT" -type f | awk 'END {print NR+0}')" == 3 ]] || {
  printf 'script_141_v1_2_native_readiness=blocked;reason=inventory_file_count_mismatch\n' >&2
  exit 1
}
find "$INVENTORY_ROOT" -type l -print -quit | grep -q . && {
  printf 'script_141_v1_2_native_readiness=blocked;reason=inventory_symlink_found\n' >&2
  exit 1
}
if grep -ERiq -- "$FORBIDDEN_TRANSFER_PATTERN" "$INVENTORY_ROOT"; then
  printf 'script_141_v1_2_native_readiness=blocked;reason=inventory_transfer_jargon_found\n' >&2
  exit 1
fi
if grep -ERq -- 'BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY|Authorization:[[:space:]]*Bearer[[:space:]]+[^$]' "$INVENTORY_ROOT"; then
  printf 'script_141_v1_2_native_readiness=blocked;reason=inventory_credential_material_found\n' >&2
  exit 1
fi

readonly -a DEPENDENCY_CONTRACTS=(
  'application/payload/config/ingestion_dependencies.yaml'
  'application/payload/config/runtime_dependencies.yaml'
)
for relative_path in "${DEPENDENCY_CONTRACTS[@]}"; do
  [[ -f "$V1_ROOT/$relative_path" && ! -L "$V1_ROOT/$relative_path" ]] || {
    printf 'script_141_v1_2_native_readiness=blocked;reason=v1_dependency_contract_missing\n' >&2
    exit 1
  }
  [[ -f "$V1_2_ROOT/$relative_path" && ! -L "$V1_2_ROOT/$relative_path" ]] || {
    printf 'script_141_v1_2_native_readiness=blocked;reason=v1_2_dependency_contract_missing\n' >&2
    exit 1
  }
  cmp -s "$V1_ROOT/$relative_path" "$V1_2_ROOT/$relative_path" || {
    printf 'script_141_v1_2_native_readiness=blocked;reason=native_dependency_review_required\n' >&2
    exit 1
  }
done

inspector_path="$INVENTORY_ROOT/inspect-native-prerequisites"
[[ -x "$inspector_path" && ! -L "$inspector_path" ]] || {
  printf 'script_141_v1_2_native_readiness=blocked;reason=inventory_inspector_invalid\n' >&2
  exit 1
}
bash -n "$inspector_path"
bash "$inspector_path" --help >/dev/null
inspector_sha256="$(sha256sum "$inspector_path" | awk '{print $1}')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_ishikawa_v1_2_native_prerequisite_readiness' \
    "script_sha256=$script_sha256;release_archive_sha256=$V1_2_ARCHIVE_SHA256" \
    "inventory_archive_sha256=$INVENTORY_ARCHIVE_SHA256;inventory_inspector_sha256=$inspector_sha256;inventory_files=3" \
    'dependency_contracts_compared=2;dependency_contracts_unchanged=true;inventory_kit_reused=true' \
    'expected_os_version=26.04;expected_architecture=amd64;target_inventory_status=pending' \
    'target_contact=false;network_contact=false;package_downloaded=false;package_installed=false;package_rebuilt=false' \
    'script_141_v1_2_native_readiness_source=pass'
  exit 0
fi

umask 077
mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/ishikawa_v1_2_native_readiness_${timestamp}.json"
artifact_checksum="$artifact_path.sha256"
report_path="$(mktemp "$REPORT_ROOT/ishikawa_v1_2_native_readiness_${timestamp}_XXXXXX.txt")"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$artifact_checksum" && ! -L "$artifact_checksum" ]] || {
  printf 'script_141_v1_2_native_readiness=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
printf '{"dependency_contracts_compared":2,"dependency_contracts_unchanged":true,"expected_architecture":"amd64","expected_os_version":"26.04","inventory_archive_sha256":"%s","inventory_file_count":3,"inventory_inspector_sha256":"%s","inventory_kit_reused":true,"native_prerequisite_packages_included":false,"package_downloaded":false,"package_installed":false,"receipt_schema_version":1,"release_archive_sha256":"%s","release_name":"Ishikawa v1.2","target_inventory_status":"pending"}\n' \
  "$INVENTORY_ARCHIVE_SHA256" "$inspector_sha256" "$V1_2_ARCHIVE_SHA256" >"$artifact_path"
artifact_sha256="$(sha256sum "$artifact_path" | awk '{print $1}')"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$artifact_checksum"
(
  cd -- "$ARTIFACT_ROOT"
  sha256sum --check --strict "$(basename -- "$artifact_checksum")" >/dev/null
)

{
  printf 'purpose=bind_accepted_ishikawa_v1_2_to_neutral_native_prerequisite_inventory\n'
  printf 'started_utc=%s\n' "$timestamp"
  printf 'script_sha256=%s;release_report_sha256=%s;release_receipt_sha256=%s\n' "$script_sha256" "$RELEASE_REPORT_SHA256" "$RELEASE_RECEIPT_SHA256"
  printf 'release_archive_sha256=%s;release_name=Ishikawa_v1.2\n' "$V1_2_ARCHIVE_SHA256"
  printf 'inventory_archive=%s;inventory_archive_sha256=%s;inventory_files=3;inventory_inspector_sha256=%s\n' "$INVENTORY_ARCHIVE" "$INVENTORY_ARCHIVE_SHA256" "$inspector_sha256"
  printf 'dependency_contracts_compared=2;dependency_contracts_unchanged=true;inventory_kit_reused=true;package_rebuilt=false;package_duplicated=false\n'
  printf 'expected_os_version=26.04;expected_architecture=amd64;target_inventory_status=pending\n'
  printf 'target_contact=false;network_contact=false;package_downloaded=false;package_installed=false;service_changed=false;credential_read=false\n'
  printf 'accepted_artifact=%s;accepted_artifact_sha256=%s;accepted_checksum=%s\n' "$artifact_path" "$artifact_sha256" "$artifact_checksum"
  printf 'script_141_v1_2_native_readiness=pass;next_gate=run_neutral_inventory_kit_on_ubuntu_26_target\n'
} | tee "$report_path"
chmod 0600 "$report_path" "$artifact_path" "$artifact_checksum" 2>/dev/null || true
