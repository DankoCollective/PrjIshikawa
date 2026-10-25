#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Accept the exact host-qualified Ishikawa v1.2 deployment package.
#
# Mental model:
#   Bind the package assembly and host-qualification evidence, reverify the
#   unchanged archive against the current Coding Standard, and retain one
#   release-acceptance receipt without rebuilding or duplicating the package.
#
# Inputs or prerequisites:
#   Clean Script 138 and Script 139 evidence and the exact qualified archive.
#
# Outputs:
#   One content-free acceptance receipt, checksum, and local report. No target,
#   database, container, service, model endpoint, or credential is contacted.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/140_accept_ishikawa_v1_2_deployment_package.sh --run

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
readonly ASSEMBLY_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.2-deployment-package/v1_2_deployment_package_20261021T222527Z_vnc2BF.txt"
readonly HOST_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.2-host-qualification/v1_2_host_qualification_20261021T223110Z_nDAMKg.txt"
readonly ARCHIVE="$REPO_ROOT/local/artifacts/ishikawa/v1.2-deployment-package/ishikawa-v1.2-deployment-package-6d4a2c169574f23b.tar.gz"
readonly ARCHIVE_CHECKSUM="$ARCHIVE.sha256"
readonly PACKAGE_QUALIFICATION="$REPO_ROOT/local/artifacts/ishikawa/v1.2-deployment-package/v1_2_deployment_package_qualification_6d4a2c169574f23b.json"
readonly PACKAGE_QUALIFICATION_CHECKSUM="$PACKAGE_QUALIFICATION.sha256"
readonly PACKAGE_COMPLIANCE="$REPO_ROOT/local/artifacts/ishikawa/v1.2-deployment-package/v1_2_deployment_coding_standard_6d4a2c169574f23b.json"
readonly PACKAGE_COMPLIANCE_CHECKSUM="$PACKAGE_COMPLIANCE.sha256"
readonly HOST_QUALIFICATION="$REPO_ROOT/local/artifacts/ishikawa/v1.2-host-qualification/v1_2_host_qualification_20261021T223110Z.json"
readonly HOST_QUALIFICATION_CHECKSUM="$HOST_QUALIFICATION.sha256"

readonly ASSEMBLY_REPORT_SHA256='1be962806a321ca1600a4cd3eb0faffbf93efe0a01ebec68bb6215411ef008df'
readonly HOST_REPORT_SHA256='6f38ea19e272a5091e7ff30a2c45e97bc4e578b865532b8aa31f4d106e2cd577'
readonly ARCHIVE_SHA256='6d4a2c169574f23b6c707a9641f936c16d2948e170ff46a77fa246cf2e3d680d'
readonly ARCHIVE_CHECKSUM_SHA256='33d1bdf58eeddfece922a3f8dd63873c7f98437940a03b9e4d9d75e3a7cabeb9'
readonly PACKAGE_QUALIFICATION_SHA256='695ca459a9182b1cc50ae8c86377c89ceedc0684da4f61986e91cde5360e929e'
readonly PACKAGE_QUALIFICATION_CHECKSUM_SHA256='3721d0dd3d06e13bfd2ad4a8946bb7062b783efc8223be9c8a0e5567015ec6fa'
readonly PACKAGE_COMPLIANCE_SHA256='50250ccbeff6ddaff2fcb19d4c61573b3098ec8a64cf9811b31b5a32798e83bd'
readonly PACKAGE_COMPLIANCE_CHECKSUM_SHA256='4dbdca57dacca7f53e86e20d1ec0e250994e5353865901599c741af73894294a'
readonly HOST_QUALIFICATION_SHA256='888aff2c1abee2be97320e5ecb752eae2d6deaa08877dc3f770e76f45ce43d45'
readonly HOST_QUALIFICATION_CHECKSUM_SHA256='3278157b1f47553771068325de70c85df27ec1df5cdeaf8a8b82ec765dd78a92'
readonly FINAL_SCHEMA_SHA256='5cfd397152b726aedc97be84d8a06fc8f21cad6e1a11563e5e9dd3a1f026d568'
readonly CORRECTED_MODULE_SHA256='8e64799a02b6c6f6833e19c29c8157602f94647009d25d78bb1e9be083ebb029'
readonly RETRIEVAL_SERVICE_SHA256='b297358b691fdfaf987c89b9e5b5539f083545c22b2be7cbabd1cf1a08b9c6b1'
readonly METHOD_PROFILE_SHA256='0d329981f1259e5d5f8138350af538a08a3d70a704241b384da6714f3b17724c'
readonly QUERY_ROUTING_SHA256='15e832bf973ea11edccbe0e593546c2d1656dfc39e871870d3c5b58f1e6eaebb'
readonly GENERATION_SHA256='b72aa72b9c89c5f8aea1efe3ce6e6d47d63aa395efd70223f4737abdae10d11f'
readonly PREDECESSOR_ARCHIVE_SHA256='e5e11c6054b1163868bc21d3b267d804894de0e936c1c1d28c6f506680746e25'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.2-release"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v1.2-release"

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_140_v1_2_acceptance=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_140_v1_2_acceptance=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in awk bash basename date dirname grep mkdir mktemp python3 rm sed sha256sum stat tar tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_140_v1_2_acceptance=blocked;reason=local_command_missing;command=%s\n' "$required" >&2
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
    printf 'script_140_v1_2_acceptance=blocked;reason=accepted_input_missing\n' >&2
    exit 2
  }
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_140_v1_2_acceptance=blocked;reason=%s_identity_changed\n' "$3" >&2
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
    printf 'script_140_v1_2_acceptance=blocked;reason=accepted_checksum_failed\n' >&2
    exit 2
  }
done

for fact in \
  'v1_1_predecessor_report_sha256=' \
  "v1_1_predecessor_archive_sha256=$PREDECESSOR_ARCHIVE_SHA256;predecessor_unchanged=true" \
  'document_page_routing=bound;structured_generation=bound' \
  'native_tests=381;failures=0;errors=0;internal_checksums=pass;deterministic_archive=true;fresh_application_install=pass;nonroot_package_readability=pass' \
  'final_schema=version_4;historical_mutation_files=0;repository_references=false;secret_material=false;source_documents_included=false' \
  'script_138_v1_2_deployment_package=pass;next_gate=qualify_fresh_v1_2_installation_on_emceedanko;'; do
  grep -Fq "$fact" "$ASSEMBLY_REPORT" || {
    printf 'script_140_v1_2_acceptance=blocked;reason=assembly_evidence_contract_failed\n' >&2
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
  'ishikawa_v1_2_host_qualification=pass' \
  'script_139_v1_2_host_qualification=pass;next_gate=accept_ishikawa_v1_2_deployment_package;' \
  'cleanup_remote_temporary_files=removed' \
  'cleanup_ssh_master_exit_code=0'; do
  grep -Fq "$fact" "$HOST_REPORT" || {
    printf 'script_140_v1_2_acceptance=blocked;reason=host_evidence_contract_failed\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
  "$CODING_STANDARD_EVALUATOR"

work_root="$(mktemp -d /tmp/ishikawa-script-140.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  [[ "$work_root" == /tmp/ishikawa-script-140.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p -- "$work_root/extracted"
tar -xzf "$ARCHIVE" -C "$work_root/extracted"
bundle_root="$work_root/extracted/ishikawa-v1.2-deployment-package"
[[ -d "$bundle_root" && ! -L "$bundle_root" ]] || {
  printf 'script_140_v1_2_acceptance=blocked;reason=bundle_root_invalid\n' >&2
  exit 1
}
bash "$bundle_root/verify-ishikawa-v1.2" >/dev/null || {
  printf 'script_140_v1_2_acceptance=blocked;reason=package_verification_failed\n' >&2
  exit 1
}
current_compliance="$work_root/current-coding-standard-compliance.json"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$CODING_STANDARD_EVALUATOR" \
  --bundle-root "$bundle_root" \
  --standard "$CODING_STANDARD" \
  --output "$current_compliance" >/dev/null || {
    printf 'script_140_v1_2_acceptance=blocked;reason=current_coding_standard_noncompliance\n' >&2
    exit 1
  }
coding_standard_sha256="$(sha256sum "$CODING_STANDARD" | awk '{print $1}')"
current_compliance_sha256="$(sha256sum "$current_compliance" | awk '{print $1}')"
[[ "$current_compliance_sha256" == "$PACKAGE_COMPLIANCE_SHA256" ]] || {
  printf 'script_140_v1_2_acceptance=blocked;reason=compliance_identity_changed\n' >&2
  exit 1
}
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
archive_bytes="$(stat -c '%s' "$ARCHIVE")"
[[ "$archive_bytes" == 201883 ]] || {
  printf 'script_140_v1_2_acceptance=blocked;reason=archive_size_changed\n' >&2
  exit 1
}

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_ishikawa_v1_2_release_acceptance' \
    "script_sha256=$script_sha256;archive_sha256=$ARCHIVE_SHA256;archive_bytes=$archive_bytes" \
    "assembly_report_sha256=$ASSEMBLY_REPORT_SHA256;host_report_sha256=$HOST_REPORT_SHA256" \
    "schema_sha256=$FINAL_SCHEMA_SHA256;corrected_module_sha256=$CORRECTED_MODULE_SHA256" \
    "retrieval_service_sha256=$RETRIEVAL_SERVICE_SHA256;method_profile_sha256=$METHOD_PROFILE_SHA256" \
    "query_routing_sha256=$QUERY_ROUTING_SHA256;generation_sha256=$GENERATION_SHA256" \
    "coding_standard_sha256=$coding_standard_sha256;coding_standard_receipt_sha256=$current_compliance_sha256" \
    'package_files=111;application_files=104;database_files=4;host_qualification=pass' \
    "predecessor_archive_sha256=$PREDECESSOR_ARCHIVE_SHA256;predecessor_unchanged=true;package_rebuilt=false;package_duplicated=false;target_contact=false" \
    'script_140_v1_2_acceptance_source=pass'
  exit 0
fi

umask 077
mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/ishikawa_v1_2_acceptance_${timestamp}.json"
artifact_checksum="$artifact_path.sha256"
report_path="$(mktemp "$REPORT_ROOT/ishikawa_v1_2_acceptance_${timestamp}_XXXXXX.txt")"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$artifact_checksum" && ! -L "$artifact_checksum" ]] || {
  printf 'script_140_v1_2_acceptance=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
printf '{"application_file_count":104,"archive_bytes":%s,"archive_sha256":"%s","coding_standard_compliant":true,"coding_standard_sha256":"%s","database_file_count":4,"deployment_payload_portable":true,"document_page_routing_qualified":true,"generation_sha256":"%s","historical_mutation_files":0,"host_qualification":"pass","host_qualification_architecture":"amd64","host_qualification_os_version":"24.04","method_profile_sha256":"%s","native_prerequisite_packages_included":false,"org_target_qualification":"pending","package_file_count":111,"package_rebuilt":false,"predecessor_archive_sha256":"%s","predecessor_release":"Ishikawa v1.1","query_routing_sha256":"%s","receipt_schema_version":1,"release_name":"Ishikawa v1.2","retrieval_service_sha256":"%s","schema_version":4,"structured_generation_qualified":true}\n' \
  "$archive_bytes" "$ARCHIVE_SHA256" "$coding_standard_sha256" "$GENERATION_SHA256" \
  "$METHOD_PROFILE_SHA256" "$PREDECESSOR_ARCHIVE_SHA256" "$QUERY_ROUTING_SHA256" \
  "$RETRIEVAL_SERVICE_SHA256" >"$artifact_path"
artifact_sha256="$(sha256sum "$artifact_path" | awk '{print $1}')"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$artifact_checksum"
(
  cd -- "$ARTIFACT_ROOT"
  sha256sum --check --strict "$(basename -- "$artifact_checksum")" >/dev/null
) || {
  printf 'script_140_v1_2_acceptance=blocked;reason=artifact_checksum_failed\n' >&2
  exit 1
}
{
  printf 'purpose=accept_exact_ishikawa_v1_2_deployment_package\n'
  printf 'started_utc=%s\n' "$timestamp"
  printf 'script_sha256=%s;archive_sha256=%s;archive_bytes=%s\n' "$script_sha256" "$ARCHIVE_SHA256" "$archive_bytes"
  printf 'assembly_report_sha256=%s;host_report_sha256=%s;host_qualification=pass\n' "$ASSEMBLY_REPORT_SHA256" "$HOST_REPORT_SHA256"
  printf 'schema_sha256=%s;schema_version=4;corrected_module_sha256=%s\n' "$FINAL_SCHEMA_SHA256" "$CORRECTED_MODULE_SHA256"
  printf 'retrieval_service_sha256=%s;method_profile_sha256=%s\n' "$RETRIEVAL_SERVICE_SHA256" "$METHOD_PROFILE_SHA256"
  printf 'query_routing_sha256=%s;generation_sha256=%s;document_page_routing=qualified;structured_generation=qualified\n' "$QUERY_ROUTING_SHA256" "$GENERATION_SHA256"
  printf 'package_files=111;application_files=104;database_files=4;historical_mutation_files=0\n'
  printf 'coding_standard_sha256=%s;coding_standard_receipt_sha256=%s;coding_standard_compliant=true\n' "$coding_standard_sha256" "$current_compliance_sha256"
  printf 'predecessor_release=Ishikawa_v1.1;predecessor_archive_sha256=%s;predecessor_unchanged=true;package_rebuilt=false;package_duplicated=false;deployment_payload_portable=true;native_prerequisite_packages_included=false\n' "$PREDECESSOR_ARCHIVE_SHA256"
  printf 'target_contact=false;database_changed=false;service_changed=false;model_contact=false;credential_read=false\n'
  printf 'accepted_artifact=%s;accepted_artifact_sha256=%s;accepted_checksum=%s\n' "$artifact_path" "$artifact_sha256" "$artifact_checksum"
  printf 'script_140_v1_2_acceptance=pass;next_gate=review_org_lab_deployment_readiness\n'
} | tee "$report_path"
