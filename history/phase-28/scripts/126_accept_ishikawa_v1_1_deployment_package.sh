#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Accept the exact host-qualified Ishikawa v1.1 deployment package.
#
# Mental model:
#   Bind the package assembly and host-qualification evidence, reverify the
#   unchanged archive against the current Coding Standard, and retain one
#   release-acceptance receipt without rebuilding or duplicating the package.
#
# Inputs or prerequisites:
#   Clean Script 124 and Script 125 evidence and the exact qualified archive.
#
# Outputs:
#   One content-free acceptance receipt, checksum, and local report. No target,
#   database, container, service, model endpoint, or credential is contacted.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/126_accept_ishikawa_v1_1_deployment_package.sh --run

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
readonly ASSEMBLY_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.1-deployment-package/v1_1_deployment_package_20261021T191326Z_1mjM3f.txt"
readonly HOST_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.1-host-qualification/v1_1_host_qualification_20261021T191621Z_vc3c9w.txt"
readonly ARCHIVE="$REPO_ROOT/local/artifacts/ishikawa/v1.1-deployment-package/ishikawa-v1.1-deployment-package-e5e11c6054b11638.tar.gz"
readonly ARCHIVE_CHECKSUM="$ARCHIVE.sha256"
readonly PACKAGE_QUALIFICATION="$REPO_ROOT/local/artifacts/ishikawa/v1.1-deployment-package/v1_1_deployment_package_qualification_e5e11c6054b11638.json"
readonly PACKAGE_QUALIFICATION_CHECKSUM="$PACKAGE_QUALIFICATION.sha256"
readonly PACKAGE_COMPLIANCE="$REPO_ROOT/local/artifacts/ishikawa/v1.1-deployment-package/v1_1_deployment_coding_standard_e5e11c6054b11638.json"
readonly PACKAGE_COMPLIANCE_CHECKSUM="$PACKAGE_COMPLIANCE.sha256"
readonly HOST_QUALIFICATION="$REPO_ROOT/local/artifacts/ishikawa/v1.1-host-qualification/v1_1_host_qualification_20261021T191621Z.json"
readonly HOST_QUALIFICATION_CHECKSUM="$HOST_QUALIFICATION.sha256"

readonly ASSEMBLY_REPORT_SHA256='80fefdf0c525a915ad2e4937891ee30aacafe9d0d14a327d9e084555a1d9302c'
readonly HOST_REPORT_SHA256='7b7f246b120d7800de50e95c86605423895e55c18c4808ada9eb0bc5f59daed6'
readonly ARCHIVE_SHA256='e5e11c6054b1163868bc21d3b267d804894de0e936c1c1d28c6f506680746e25'
readonly ARCHIVE_CHECKSUM_SHA256='a471b772635d62cb0d1ae6220ad90e9d0973e82d54e833cd1d09bfbc362d7e9e'
readonly PACKAGE_QUALIFICATION_SHA256='e991471a4687da1a4d7966079f99c49bb0ffc609c04e0ab1407fe085aaf76ab7'
readonly PACKAGE_QUALIFICATION_CHECKSUM_SHA256='e1e8f6c5c24a4db6ebea4abe09845495795bb40e25d220f0a752c38fa4546ccc'
readonly PACKAGE_COMPLIANCE_SHA256='50250ccbeff6ddaff2fcb19d4c61573b3098ec8a64cf9811b31b5a32798e83bd'
readonly PACKAGE_COMPLIANCE_CHECKSUM_SHA256='8cbf3297262a03e3fc17ef9397b8834005cd9d610f03e4145f0af0849189f3b6'
readonly HOST_QUALIFICATION_SHA256='af48b4923fc1df47fede56f4ffdbe39ee6520b6f48f0ab2dffdb3f8b7fcbf8f7'
readonly HOST_QUALIFICATION_CHECKSUM_SHA256='81f3accdc96cb4c17a74b8b2bafa24d1d073f842bc110d17e8fb8167ca5b78dc'
readonly FINAL_SCHEMA_SHA256='5cfd397152b726aedc97be84d8a06fc8f21cad6e1a11563e5e9dd3a1f026d568'
readonly CORRECTED_MODULE_SHA256='8e64799a02b6c6f6833e19c29c8157602f94647009d25d78bb1e9be083ebb029'
readonly RETRIEVAL_SERVICE_SHA256='b297358b691fdfaf987c89b9e5b5539f083545c22b2be7cbabd1cf1a08b9c6b1'
readonly METHOD_PROFILE_SHA256='0d329981f1259e5d5f8138350af538a08a3d70a704241b384da6714f3b17724c'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.1-release"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v1.1-release"

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_126_v1_1_acceptance=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_126_v1_1_acceptance=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in awk bash basename date dirname grep mkdir mktemp python3 rm sed sha256sum stat tar tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_126_v1_1_acceptance=blocked;reason=local_command_missing;command=%s\n' "$required" >&2
    exit 2
  }
done

readonly -a INPUTS=(
  "$CODING_STANDARD" "$CODING_STANDARD_EVALUATOR"
  "$ASSEMBLY_REPORT" "$HOST_REPORT" "$ARCHIVE" "$ARCHIVE_CHECKSUM"
  "$PACKAGE_QUALIFICATION" "$PACKAGE_QUALIFICATION_CHECKSUM"
  "$PACKAGE_COMPLIANCE" "$PACKAGE_COMPLIANCE_CHECKSUM"
  "$HOST_QUALIFICATION" "$HOST_QUALIFICATION_CHECKSUM"
)
for file in "${INPUTS[@]}"; do
  [[ -f "$file" && ! -L "$file" && -r "$file" ]] || {
    printf 'script_126_v1_1_acceptance=blocked;reason=accepted_input_missing\n' >&2
    exit 2
  }
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_126_v1_1_acceptance=blocked;reason=%s_identity_changed\n' "$3" >&2
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
  (
    cd -- "$(dirname -- "$sidecar")"
    sha256sum --check --strict "$(basename -- "$sidecar")" >/dev/null
  ) || {
    printf 'script_126_v1_1_acceptance=blocked;reason=accepted_checksum_failed\n' >&2
    exit 2
  }
done

for fact in \
  'v1_fallback_report_sha256=' \
  'fallback_unchanged=true' \
  'native_tests=376;failures=0;errors=0;internal_checksums=pass;deterministic_archive=true;fresh_application_install=pass;nonroot_package_readability=pass' \
  'final_schema=version_4;historical_mutation_files=0;repository_references=false;secret_material=false;source_documents_included=false' \
  'script_124_v1_1_deployment_package=pass;next_gate=qualify_fresh_v1_1_installation_on_emceedanko;'; do
  grep -Fq "$fact" "$ASSEMBLY_REPORT" || {
    printf 'script_126_v1_1_acceptance=blocked;reason=assembly_evidence_contract_failed\n' >&2
    exit 2
  }
done
for fact in \
  'fresh_application_install=pass;installed_files=101;python_modules=48;unit_files=3;temporary_application_removed=true;active_application_changed=false' \
  'fresh_database_install=pass;schema_version=4;catalog_equivalence=exact;tables=20;views=5;explicit_indexes=14;required_named_constraints=11' \
  'accepted_active_documents=6;accepted_active_pages=27;accepted_active_chunks=126;accepted_active_embeddings=126' \
  'accepted_database_unchanged=true;temporary_database_dropped=true' \
  'cluster_final_status=online;cluster_initial_state_restored=true;service_enablement_changed=false' \
  'model_contact=false;credential_read=false;source_documents_copied=false;port_forwarding_changed=false' \
  'ishikawa_v1_1_host_qualification=pass' \
  'script_125_v1_1_host_qualification=pass;next_gate=accept_ishikawa_v1_1_deployment_package;'; do
  grep -Fq "$fact" "$HOST_REPORT" || {
    printf 'script_126_v1_1_acceptance=blocked;reason=host_evidence_contract_failed\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
  "$CODING_STANDARD_EVALUATOR"

work_root="$(mktemp -d /tmp/ishikawa-script-126.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  [[ "$work_root" == /tmp/ishikawa-script-126.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p -- "$work_root/extracted"
tar -xzf "$ARCHIVE" -C "$work_root/extracted"
bundle_root="$work_root/extracted/ishikawa-v1.1-deployment-package"
[[ -d "$bundle_root" && ! -L "$bundle_root" ]] || {
  printf 'script_126_v1_1_acceptance=blocked;reason=bundle_root_invalid\n' >&2
  exit 1
}
bash "$bundle_root/verify-ishikawa-v1.1" >/dev/null || {
  printf 'script_126_v1_1_acceptance=blocked;reason=package_verification_failed\n' >&2
  exit 1
}
current_compliance="$work_root/current-coding-standard-compliance.json"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$CODING_STANDARD_EVALUATOR" \
  --bundle-root "$bundle_root" \
  --standard "$CODING_STANDARD" \
  --output "$current_compliance" >/dev/null || {
    printf 'script_126_v1_1_acceptance=blocked;reason=current_coding_standard_noncompliance\n' >&2
    exit 1
  }
coding_standard_sha256="$(sha256sum "$CODING_STANDARD" | awk '{print $1}')"
current_compliance_sha256="$(sha256sum "$current_compliance" | awk '{print $1}')"
[[ "$current_compliance_sha256" == "$PACKAGE_COMPLIANCE_SHA256" ]] || {
  printf 'script_126_v1_1_acceptance=blocked;reason=compliance_identity_changed\n' >&2
  exit 1
}
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
archive_bytes="$(stat -c '%s' "$ARCHIVE")"
[[ "$archive_bytes" == 200193 ]] || {
  printf 'script_126_v1_1_acceptance=blocked;reason=archive_size_changed\n' >&2
  exit 1
}

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_ishikawa_v1_1_release_acceptance' \
    "script_sha256=$script_sha256;archive_sha256=$ARCHIVE_SHA256;archive_bytes=$archive_bytes" \
    "assembly_report_sha256=$ASSEMBLY_REPORT_SHA256;host_report_sha256=$HOST_REPORT_SHA256" \
    "schema_sha256=$FINAL_SCHEMA_SHA256;corrected_module_sha256=$CORRECTED_MODULE_SHA256" \
    "retrieval_service_sha256=$RETRIEVAL_SERVICE_SHA256;method_profile_sha256=$METHOD_PROFILE_SHA256" \
    "coding_standard_sha256=$coding_standard_sha256;coding_standard_receipt_sha256=$current_compliance_sha256" \
    'package_files=111;application_files=104;database_files=4;host_qualification=pass' \
    'v1_fallback_unchanged=true;package_rebuilt=false;package_duplicated=false;target_contact=false' \
    'script_126_v1_1_acceptance_source=pass'
  exit 0
fi

umask 077
mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/ishikawa_v1_1_acceptance_${timestamp}.json"
artifact_checksum="$artifact_path.sha256"
report_path="$(mktemp "$REPORT_ROOT/ishikawa_v1_1_acceptance_${timestamp}_XXXXXX.txt")"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$artifact_checksum" && ! -L "$artifact_checksum" ]] || {
  printf 'script_126_v1_1_acceptance=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
printf '{"application_file_count":104,"archive_bytes":%s,"archive_sha256":"%s","coding_standard_compliant":true,"coding_standard_sha256":"%s","database_file_count":4,"deployment_payload_portable":true,"historical_mutation_files":0,"host_qualification":"pass","host_qualification_architecture":"amd64","host_qualification_os_version":"24.04","method_profile_sha256":"%s","native_prerequisite_packages_included":false,"org_target_qualification":"pending","package_file_count":111,"package_rebuilt":false,"receipt_schema_version":1,"release_name":"Ishikawa v1.1","retrieval_service_sha256":"%s","schema_version":4,"v1_fallback_unchanged":true}\n' \
  "$archive_bytes" "$ARCHIVE_SHA256" "$coding_standard_sha256" "$METHOD_PROFILE_SHA256" "$RETRIEVAL_SERVICE_SHA256" >"$artifact_path"
artifact_sha256="$(sha256sum "$artifact_path" | awk '{print $1}')"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$artifact_checksum"
(
  cd -- "$ARTIFACT_ROOT"
  sha256sum --check --strict "$(basename -- "$artifact_checksum")" >/dev/null
) || {
  printf 'script_126_v1_1_acceptance=blocked;reason=artifact_checksum_failed\n' >&2
  exit 1
}
{
  printf 'purpose=accept_exact_ishikawa_v1_1_deployment_package\n'
  printf 'started_utc=%s\n' "$timestamp"
  printf 'script_sha256=%s;archive_sha256=%s;archive_bytes=%s\n' "$script_sha256" "$ARCHIVE_SHA256" "$archive_bytes"
  printf 'assembly_report_sha256=%s;host_report_sha256=%s;host_qualification=pass\n' "$ASSEMBLY_REPORT_SHA256" "$HOST_REPORT_SHA256"
  printf 'schema_sha256=%s;schema_version=4;corrected_module_sha256=%s\n' "$FINAL_SCHEMA_SHA256" "$CORRECTED_MODULE_SHA256"
  printf 'retrieval_service_sha256=%s;method_profile_sha256=%s\n' "$RETRIEVAL_SERVICE_SHA256" "$METHOD_PROFILE_SHA256"
  printf 'package_files=111;application_files=104;database_files=4;historical_mutation_files=0\n'
  printf 'coding_standard_sha256=%s;coding_standard_receipt_sha256=%s;coding_standard_compliant=true\n' "$coding_standard_sha256" "$current_compliance_sha256"
  printf 'v1_fallback_unchanged=true;package_rebuilt=false;package_duplicated=false;deployment_payload_portable=true;native_prerequisite_packages_included=false\n'
  printf 'target_contact=false;database_changed=false;service_changed=false;model_contact=false;credential_read=false\n'
  printf 'accepted_artifact=%s;accepted_artifact_sha256=%s;accepted_checksum=%s\n' "$artifact_path" "$artifact_sha256" "$artifact_checksum"
  printf 'script_126_v1_1_acceptance=pass;next_gate=review_extended_evaluation_candidate_before_org_promotion\n'
} | tee "$report_path"
