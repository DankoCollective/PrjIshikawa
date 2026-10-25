#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Accept the exact host-qualified Ishikawa v1 deployment package.
#
# Mental model:
#   Bind the package assembly and host-qualification evidence, reverify the
#   unchanged archive against the current coding standard, and retain one
#   release-acceptance receipt without rebuilding or duplicating the package.
#
# Inputs or prerequisites:
#   Clean Script 107 and Script 108 evidence and the exact accepted archive.
#
# Outputs:
#   One content-free acceptance receipt, checksum, and local report. No target,
#   database, container, service, model endpoint, or credential is contacted.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/109_accept_ishikawa_v1_deployment_package.sh --run

usage() {
  sed -n '3,20p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Accept and retain the exact qualified package identity.' \
    '  --validate-only Validate the same evidence without retaining outputs.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly CODING_STANDARD="$REPO_ROOT/CODING_STANDARD.md"
readonly CODING_STANDARD_EVALUATOR="$SCRIPT_DIR/evaluate_consolidated_build_coding_standard.py"
readonly ASSEMBLY_REPORT="$REPO_ROOT/local/reports/ishikawa-v1-deployment-package/v1_deployment_package_20261021T041419Z_Z7Ee6M.txt"
readonly HOST_REPORT="$REPO_ROOT/local/reports/ishikawa-v1-host-qualification/v1_host_qualification_20261021T042235Z_K3xhVm.txt"
readonly ARCHIVE="$REPO_ROOT/local/artifacts/ishikawa/v1-deployment-package/ishikawa-v1-deployment-package-c848680051786b2b.tar.gz"
readonly ARCHIVE_CHECKSUM="$ARCHIVE.sha256"
readonly PACKAGE_QUALIFICATION="$REPO_ROOT/local/artifacts/ishikawa/v1-deployment-package/v1_deployment_package_qualification_c848680051786b2b.json"
readonly PACKAGE_QUALIFICATION_CHECKSUM="$PACKAGE_QUALIFICATION.sha256"
readonly PACKAGE_COMPLIANCE="$REPO_ROOT/local/artifacts/ishikawa/v1-deployment-package/v1_deployment_coding_standard_c848680051786b2b.json"
readonly PACKAGE_COMPLIANCE_CHECKSUM="$PACKAGE_COMPLIANCE.sha256"
readonly HOST_QUALIFICATION="$REPO_ROOT/local/artifacts/ishikawa/v1-host-qualification/v1_host_qualification_20261021T042235Z.json"
readonly HOST_QUALIFICATION_CHECKSUM="$HOST_QUALIFICATION.sha256"
readonly ASSEMBLY_REPORT_SHA256='3e35a03c828ed912690d905fd81fad64d5f9df5e55ad4012e09571834f041098'
readonly HOST_REPORT_SHA256='dcde2cbd5063bdaa229684639a7fda7c8537f7d1bb7b5f8eff32e280793183c8'
readonly ARCHIVE_SHA256='c848680051786b2b3c6ac454b3f007be1632d45215ddf9c8f1d4d04b924845b1'
readonly ARCHIVE_CHECKSUM_SHA256='25313c7065cfa038ba63f51deb29585e763aae0561c672057c28c86c5fe57550'
readonly PACKAGE_QUALIFICATION_SHA256='9ef16edcd3fe41d9102013a68c95ec2ec292126a3de2317934bb4cf5bf69b07f'
readonly PACKAGE_QUALIFICATION_CHECKSUM_SHA256='ecc9fadd9f1df7cdce0a135c2551a619031ae01f52bbb4d516531373daf58fa6'
readonly PACKAGE_COMPLIANCE_SHA256='98ad7de04146d77514e93e8d50746699d0b13dd42d6b22b0834ba519fc23a92c'
readonly PACKAGE_COMPLIANCE_CHECKSUM_SHA256='b1af5ca048ee6cec0ef9c38b4dd0312cb065fd74060570298f6d0ee6672a9415'
readonly HOST_QUALIFICATION_SHA256='c19ad805ee1435410a94d33e0abd2db347425433d59b2e2a833b159a3ac1abd7'
readonly HOST_QUALIFICATION_CHECKSUM_SHA256='34b7cc6bcdf4cd9a0fbe90386273f57e28ec3359065cf1a5fa9281a682398e0a'
readonly FINAL_SCHEMA_SHA256='5cfd397152b726aedc97be84d8a06fc8f21cad6e1a11563e5e9dd3a1f026d568'
readonly CORRECTED_MODULE_SHA256='8e64799a02b6c6f6833e19c29c8157602f94647009d25d78bb1e9be083ebb029'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1-release"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v1-release"

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_109_v1_acceptance=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || { printf 'script_109_v1_acceptance=blocked;reason=mode_invalid\n' >&2; exit 2; }

for required in awk bash basename chmod cp date dirname grep mkdir mktemp mv python3 rm sed sha256sum stat tar tee; do
  command -v "$required" >/dev/null 2>&1 || { printf 'script_109_v1_acceptance=blocked;reason=local_command_missing\n' >&2; exit 2; }
done
readonly -a INPUTS=(
  "$CODING_STANDARD" "$CODING_STANDARD_EVALUATOR"
  "$ASSEMBLY_REPORT" "$HOST_REPORT" "$ARCHIVE" "$ARCHIVE_CHECKSUM"
  "$PACKAGE_QUALIFICATION" "$PACKAGE_QUALIFICATION_CHECKSUM"
  "$PACKAGE_COMPLIANCE" "$PACKAGE_COMPLIANCE_CHECKSUM"
  "$HOST_QUALIFICATION" "$HOST_QUALIFICATION_CHECKSUM"
)
for file in "${INPUTS[@]}"; do
  [[ -f "$file" && ! -L "$file" && -r "$file" ]] || { printf 'script_109_v1_acceptance=blocked;reason=accepted_input_missing\n' >&2; exit 2; }
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_109_v1_acceptance=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}
check_sha256 "$ASSEMBLY_REPORT" "$ASSEMBLY_REPORT_SHA256" assembly_report
check_sha256 "$HOST_REPORT" "$HOST_REPORT_SHA256" host_report
check_sha256 "$ARCHIVE" "$ARCHIVE_SHA256" archive
check_sha256 "$ARCHIVE_CHECKSUM" "$ARCHIVE_CHECKSUM_SHA256" archive_checksum
check_sha256 "$PACKAGE_QUALIFICATION" "$PACKAGE_QUALIFICATION_SHA256" package_qualification
check_sha256 "$PACKAGE_QUALIFICATION_CHECKSUM" "$PACKAGE_QUALIFICATION_CHECKSUM_SHA256" package_qualification_checksum
check_sha256 "$PACKAGE_COMPLIANCE" "$PACKAGE_COMPLIANCE_SHA256" package_compliance
check_sha256 "$PACKAGE_COMPLIANCE_CHECKSUM" "$PACKAGE_COMPLIANCE_CHECKSUM_SHA256" package_compliance_checksum
check_sha256 "$HOST_QUALIFICATION" "$HOST_QUALIFICATION_SHA256" host_qualification
check_sha256 "$HOST_QUALIFICATION_CHECKSUM" "$HOST_QUALIFICATION_CHECKSUM_SHA256" host_qualification_checksum
for sidecar in "$ARCHIVE_CHECKSUM" "$PACKAGE_QUALIFICATION_CHECKSUM" "$PACKAGE_COMPLIANCE_CHECKSUM" "$HOST_QUALIFICATION_CHECKSUM"; do
  (cd -- "$(dirname -- "$sidecar")" && sha256sum --check --strict "$(basename -- "$sidecar")" >/dev/null) || { printf 'script_109_v1_acceptance=blocked;reason=accepted_checksum_failed\n' >&2; exit 2; }
done

for fact in \
  'script_107_v1_deployment_package=pass;next_gate=qualify_fresh_v1_installation_on_application_host' \
  'runtime_proof=pass;deterministic_archive=true;fresh_application_install=pass;historical_mutation_files=0'; do
  grep -Fq "$fact" "$ASSEMBLY_REPORT" || { printf 'script_109_v1_acceptance=blocked;reason=assembly_evidence_contract_failed\n' >&2; exit 2; }
done
for fact in \
  'fresh_application_install=pass;installed_files=94;python_modules=47;unit_files=3;temporary_application_removed=true;active_application_changed=false' \
  'fresh_database_install=pass;schema_version=4;catalog_equivalence=exact;tables=20;views=5;explicit_indexes=14;required_named_constraints=11' \
  'accepted_active_documents=6;accepted_active_pages=27;accepted_active_chunks=126;accepted_active_embeddings=126' \
  'accepted_database_unchanged=true;temporary_database_dropped=true' \
  'cluster_final_status=down;cluster_initial_state_restored=true;service_enablement_changed=false' \
  'ishikawa_v1_host_qualification=pass' \
  'script_108_v1_host_qualification=pass;'; do
  grep -Fq "$fact" "$HOST_REPORT" || { printf 'script_109_v1_acceptance=blocked;reason=host_evidence_contract_failed\n' >&2; exit 2; }
done

bash -n "${BASH_SOURCE[0]}"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c 'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' "$CODING_STANDARD_EVALUATOR"
work_root="$(mktemp -d /tmp/ishikawa-script-109.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  [[ "$work_root" == /tmp/ishikawa-script-109.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p -- "$work_root/extracted"
tar -xzf "$ARCHIVE" -C "$work_root/extracted"
bundle_root="$work_root/extracted/ishikawa-v1-deployment-package"
[[ -d "$bundle_root" && ! -L "$bundle_root" ]] || { printf 'script_109_v1_acceptance=blocked;reason=bundle_root_invalid\n' >&2; exit 1; }
bash "$bundle_root/verify-ishikawa-v1" >/dev/null || { printf 'script_109_v1_acceptance=blocked;reason=package_verification_failed\n' >&2; exit 1; }
current_compliance="$work_root/current-coding-standard-compliance.json"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$CODING_STANDARD_EVALUATOR" \
  --bundle-root "$bundle_root" \
  --standard "$CODING_STANDARD" \
  --output "$current_compliance" >/dev/null || { printf 'script_109_v1_acceptance=blocked;reason=current_coding_standard_noncompliance\n' >&2; exit 1; }
coding_standard_sha256="$(sha256sum "$CODING_STANDARD" | awk '{print $1}')"
current_compliance_sha256="$(sha256sum "$current_compliance" | awk '{print $1}')"
[[ "$current_compliance_sha256" == "$PACKAGE_COMPLIANCE_SHA256" ]] || { printf 'script_109_v1_acceptance=blocked;reason=compliance_identity_changed\n' >&2; exit 1; }
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
archive_bytes="$(stat -c '%s' "$ARCHIVE")"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_ishikawa_v1_release_acceptance' \
    "script_sha256=$script_sha256;archive_sha256=$ARCHIVE_SHA256;archive_bytes=$archive_bytes" \
    "assembly_report_sha256=$ASSEMBLY_REPORT_SHA256;host_report_sha256=$HOST_REPORT_SHA256" \
    "schema_sha256=$FINAL_SCHEMA_SHA256;corrected_module_sha256=$CORRECTED_MODULE_SHA256" \
    "coding_standard_sha256=$coding_standard_sha256;coding_standard_receipt_sha256=$current_compliance_sha256" \
    'package_files=104;application_files=97;database_files=4;host_qualification=pass' \
    'package_rebuilt=false;package_duplicated=false;target_contact=false' \
    'script_109_v1_acceptance_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/ishikawa_v1_acceptance_${timestamp}.json"
artifact_checksum="$artifact_path.sha256"
report_path="$(mktemp "$REPORT_ROOT/ishikawa_v1_acceptance_${timestamp}_XXXXXX.txt")"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$artifact_checksum" && ! -L "$artifact_checksum" ]] || { printf 'script_109_v1_acceptance=blocked;reason=artifact_path_exists\n' >&2; exit 1; }
printf '{"application_file_count":97,"archive_bytes":%s,"archive_sha256":"%s","coding_standard_compliant":true,"coding_standard_sha256":"%s","database_file_count":4,"deployment_payload_portable":true,"historical_mutation_files":0,"host_qualification":"pass","host_qualification_architecture":"amd64","host_qualification_os_version":"24.04","native_prerequisite_packages_included":false,"org_target_qualification":"pending","package_file_count":104,"package_rebuilt":false,"receipt_schema_version":1,"release_name":"Ishikawa v1","schema_version":4}\n' \
  "$archive_bytes" "$ARCHIVE_SHA256" "$coding_standard_sha256" >"$artifact_path"
artifact_sha256="$(sha256sum "$artifact_path" | awk '{print $1}')"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$artifact_checksum"
chmod 0600 "$artifact_path" "$artifact_checksum" 2>/dev/null || true
(cd -- "$ARTIFACT_ROOT" && sha256sum --check --strict "$(basename -- "$artifact_checksum")" >/dev/null) || { printf 'script_109_v1_acceptance=blocked;reason=artifact_checksum_failed\n' >&2; exit 1; }
{
  printf 'purpose=accept_exact_ishikawa_v1_deployment_package\n'
  printf 'started_utc=%s\n' "$timestamp"
  printf 'script_sha256=%s;archive_sha256=%s;archive_bytes=%s\n' "$script_sha256" "$ARCHIVE_SHA256" "$archive_bytes"
  printf 'assembly_report_sha256=%s;host_report_sha256=%s;host_qualification=pass\n' "$ASSEMBLY_REPORT_SHA256" "$HOST_REPORT_SHA256"
  printf 'schema_sha256=%s;schema_version=4;corrected_module_sha256=%s\n' "$FINAL_SCHEMA_SHA256" "$CORRECTED_MODULE_SHA256"
  printf 'package_files=104;application_files=97;database_files=4;historical_mutation_files=0\n'
  printf 'coding_standard_sha256=%s;coding_standard_receipt_sha256=%s;coding_standard_compliant=true\n' "$coding_standard_sha256" "$current_compliance_sha256"
  printf 'package_rebuilt=false;package_duplicated=false;deployment_payload_portable=true;native_prerequisite_packages_included=false\n'
  printf 'target_contact=false;database_changed=false;service_changed=false;model_contact=false\n'
  printf 'accepted_artifact=%s;accepted_artifact_sha256=%s;accepted_checksum=%s\n' "$artifact_path" "$artifact_sha256" "$artifact_checksum"
  printf 'script_109_v1_acceptance=pass;next_gate=qualify_ubuntu_26_native_prerequisites_before_org_install\n'
} | tee "$report_path"
chmod 0600 "$report_path" 2>/dev/null || true
