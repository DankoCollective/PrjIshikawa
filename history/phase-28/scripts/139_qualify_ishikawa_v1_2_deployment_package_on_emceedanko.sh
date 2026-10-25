#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the accepted consolidated Ishikawa v1.2 deployment package on
#   EmceeDanko without changing the active application or accepted corpus.
#
# Mental model:
#   Bind the local package evidence, verify it again, transfer only the archive
#   and neutral helper, exercise disposable application and database installs,
#   return content-free evidence, and remove all transferred temporary files.
#
# Inputs or prerequisites:
#   Clean Script 138 evidence, strict SSH host trust, attended sudo, and the
#   accepted EmceeDanko PostgreSQL 16, pgvector, roles, and application posture.
#
# Outputs or artifact lane:
#   Local content-free host-qualification evidence. The active application,
#   populated corpus, service enablement, model endpoints, and forwarding are
#   unchanged. The target transfer directory is removed before completion.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/139_qualify_ishikawa_v1_2_deployment_package_on_emceedanko.sh --run

usage() {
  sed -n '3,25p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run                      Execute disposable target qualification.' \
    '  --target VALUE             SSH destination or configured SSH alias.' \
    '  --expected-hostname NAME   Exact target short hostname.' \
    '  --expected-os-version VER  Exact expected Ubuntu major.minor version.' \
    '  --identity-file PATH       Optional explicit SSH private key.' \
    '  --validate-only            Validate sources without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly TARGET_HELPER="$SCRIPT_DIR/qualify-ishikawa-v1.2-deployment-package"
readonly CODING_STANDARD="$REPO_ROOT/CODING_STANDARD.md"
readonly CODING_STANDARD_EVALUATOR="$SCRIPT_DIR/evaluate_consolidated_build_coding_standard.py"
readonly ACCEPTED_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.2-deployment-package/v1_2_deployment_package_20261021T222527Z_vnc2BF.txt"
readonly ACCEPTED_ARCHIVE="$REPO_ROOT/local/artifacts/ishikawa/v1.2-deployment-package/ishikawa-v1.2-deployment-package-6d4a2c169574f23b.tar.gz"
readonly ACCEPTED_ARCHIVE_CHECKSUM="$ACCEPTED_ARCHIVE.sha256"
readonly ACCEPTED_QUALIFICATION="$REPO_ROOT/local/artifacts/ishikawa/v1.2-deployment-package/v1_2_deployment_package_qualification_6d4a2c169574f23b.json"
readonly ACCEPTED_QUALIFICATION_CHECKSUM="$ACCEPTED_QUALIFICATION.sha256"
readonly ACCEPTED_COMPLIANCE="$REPO_ROOT/local/artifacts/ishikawa/v1.2-deployment-package/v1_2_deployment_coding_standard_6d4a2c169574f23b.json"
readonly ACCEPTED_COMPLIANCE_CHECKSUM="$ACCEPTED_COMPLIANCE.sha256"

readonly TARGET_HELPER_SHA256='cee39c1040577a3b9b2f776af4824e612f7e52fc6fa286fa3c3c22263cede20e'
readonly ACCEPTED_REPORT_SHA256='1be962806a321ca1600a4cd3eb0faffbf93efe0a01ebec68bb6215411ef008df'
readonly ACCEPTED_ARCHIVE_SHA256='6d4a2c169574f23b6c707a9641f936c16d2948e170ff46a77fa246cf2e3d680d'
readonly ACCEPTED_ARCHIVE_CHECKSUM_SHA256='33d1bdf58eeddfece922a3f8dd63873c7f98437940a03b9e4d9d75e3a7cabeb9'
readonly ACCEPTED_QUALIFICATION_SHA256='695ca459a9182b1cc50ae8c86377c89ceedc0684da4f61986e91cde5360e929e'
readonly ACCEPTED_QUALIFICATION_CHECKSUM_SHA256='3721d0dd3d06e13bfd2ad4a8946bb7062b783efc8223be9c8a0e5567015ec6fa'
readonly ACCEPTED_COMPLIANCE_SHA256='50250ccbeff6ddaff2fcb19d4c61573b3098ec8a64cf9811b31b5a32798e83bd'
readonly ACCEPTED_COMPLIANCE_CHECKSUM_SHA256='4dbdca57dacca7f53e86e20d1ec0e250994e5353865901599c741af73894294a'
readonly FINAL_SCHEMA_SHA256='5cfd397152b726aedc97be84d8a06fc8f21cad6e1a11563e5e9dd3a1f026d568'
readonly CORRECTED_MODULE_SHA256='8e64799a02b6c6f6833e19c29c8157602f94647009d25d78bb1e9be083ebb029'
readonly RETRIEVAL_SERVICE_SHA256='b297358b691fdfaf987c89b9e5b5539f083545c22b2be7cbabd1cf1a08b9c6b1'
readonly METHOD_PROFILE_SHA256='0d329981f1259e5d5f8138350af538a08a3d70a704241b384da6714f3b17724c'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.2-host-qualification"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v1.2-host-qualification"

target="${APPLICATION_HOST_TARGET:-DankoSurface_EmceeDanko}"
expected_hostname="${APPLICATION_HOST_EXPECTED_HOSTNAME:-EmceeDanko}"
expected_os_version="${APPLICATION_HOST_EXPECTED_OS_VERSION:-24.04}"
accepted_database="${APPLICATION_DATABASE_NAME:-rag_catalog}"
owner_role="${APPLICATION_DATABASE_OWNER_ROLE:-rag_owner}"
ingest_role="${APPLICATION_DATABASE_INGEST_ROLE:-rag_ingest}"
retrieval_role="${APPLICATION_DATABASE_RETRIEVAL_ROLE:-rag_retrieval}"
identity_file="${APPLICATION_HOST_IDENTITY_FILE:-}"
run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --target) target="${2:-}"; shift 2 ;;
    --expected-hostname) expected_hostname="${2:-}"; shift 2 ;;
    --expected-os-version) expected_os_version="${2:-}"; shift 2 ;;
    --identity-file) identity_file="${2:-}"; shift 2 ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_139_v1_2_host_qualification=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_139_v1_2_host_qualification=blocked;reason=mode_invalid\n' >&2
  exit 2
}
[[ "$target" =~ ^[A-Za-z0-9_@.:-]+$ ]] || {
  printf 'script_139_v1_2_host_qualification=blocked;reason=target_invalid\n' >&2
  exit 2
}
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || {
  printf 'script_139_v1_2_host_qualification=blocked;reason=expected_hostname_invalid\n' >&2
  exit 2
}
[[ "$expected_os_version" =~ ^[0-9]{2}\.[0-9]{2}$ ]] || {
  printf 'script_139_v1_2_host_qualification=blocked;reason=expected_os_version_invalid\n' >&2
  exit 2
}
[[ "$accepted_database|$owner_role|$ingest_role|$retrieval_role" == 'rag_catalog|rag_owner|rag_ingest|rag_retrieval' ]] || {
  printf 'script_139_v1_2_host_qualification=blocked;reason=database_contract_invalid\n' >&2
  exit 2
}
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] || {
    printf 'script_139_v1_2_host_qualification=blocked;reason=identity_file_unsafe\n' >&2
    exit 2
  }
fi

for required in awk bash basename chmod cp date dirname grep mkdir mktemp mv python3 rm scp sed sha256sum ssh stat tar tee timeout; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_139_v1_2_host_qualification=blocked;reason=local_command_missing;command=%s\n' "$required" >&2
    exit 2
  }
done

readonly -a ACCEPTED_INPUTS=(
  "$TARGET_HELPER" "$CODING_STANDARD" "$CODING_STANDARD_EVALUATOR"
  "$ACCEPTED_REPORT" "$ACCEPTED_ARCHIVE" "$ACCEPTED_ARCHIVE_CHECKSUM"
  "$ACCEPTED_QUALIFICATION" "$ACCEPTED_QUALIFICATION_CHECKSUM"
  "$ACCEPTED_COMPLIANCE" "$ACCEPTED_COMPLIANCE_CHECKSUM"
)
for file in "${ACCEPTED_INPUTS[@]}"; do
  [[ -f "$file" && ! -L "$file" && -r "$file" ]] || {
    printf 'script_139_v1_2_host_qualification=blocked;reason=accepted_input_unsafe\n' >&2
    exit 2
  }
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_139_v1_2_host_qualification=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}

check_sha256 "$TARGET_HELPER" "$TARGET_HELPER_SHA256" target_helper
check_sha256 "$ACCEPTED_REPORT" "$ACCEPTED_REPORT_SHA256" accepted_report
check_sha256 "$ACCEPTED_ARCHIVE" "$ACCEPTED_ARCHIVE_SHA256" accepted_archive
check_sha256 "$ACCEPTED_ARCHIVE_CHECKSUM" "$ACCEPTED_ARCHIVE_CHECKSUM_SHA256" accepted_archive_checksum
check_sha256 "$ACCEPTED_QUALIFICATION" "$ACCEPTED_QUALIFICATION_SHA256" accepted_qualification
check_sha256 "$ACCEPTED_QUALIFICATION_CHECKSUM" "$ACCEPTED_QUALIFICATION_CHECKSUM_SHA256" accepted_qualification_checksum
check_sha256 "$ACCEPTED_COMPLIANCE" "$ACCEPTED_COMPLIANCE_SHA256" accepted_compliance
check_sha256 "$ACCEPTED_COMPLIANCE_CHECKSUM" "$ACCEPTED_COMPLIANCE_CHECKSUM_SHA256" accepted_compliance_checksum
for checksum in "$ACCEPTED_ARCHIVE_CHECKSUM" "$ACCEPTED_QUALIFICATION_CHECKSUM" "$ACCEPTED_COMPLIANCE_CHECKSUM"; do
  (
    cd -- "$(dirname -- "$checksum")"
    sha256sum --check --strict "$(basename -- "$checksum")" >/dev/null
  ) || {
    printf 'script_139_v1_2_host_qualification=blocked;reason=accepted_checksum_failed\n' >&2
    exit 2
  }
done
for fact in \
  "archive_sha256=$ACCEPTED_ARCHIVE_SHA256;archive_bytes=201883" \
  'package_files=111;application_files=104;database_files=4;python_modules=48;operator_documents=10' \
  'native_tests=381;failures=0;errors=0;internal_checksums=pass;deterministic_archive=true;fresh_application_install=pass' \
  'nonroot_package_readability=pass' \
  'final_schema=version_4;historical_mutation_files=0;repository_references=false;secret_material=false;source_documents_included=false' \
  'script_138_v1_2_deployment_package=pass;next_gate=qualify_fresh_v1_2_installation_on_emceedanko;'; do
  grep -Fq "$fact" "$ACCEPTED_REPORT" || {
    printf 'script_139_v1_2_host_qualification=blocked;reason=accepted_report_contract_invalid\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}" "$TARGET_HELPER"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
  "$CODING_STANDARD_EVALUATOR"
if grep -Eiq 'phase[-_ ]?[0-9]+|Danko|org[_ -]?lab|Agent|repository|Script[[:space:]_-]*[0-9]+' "$TARGET_HELPER" \
  || grep -Eq '(^|[^[:alnum:]])[GD][0-9]{2}([^[:alnum:]]|$)' "$TARGET_HELPER"; then
  printf 'script_139_v1_2_host_qualification=blocked;reason=target_helper_jargon_found\n' >&2
  exit 2
fi

work_root="$(mktemp -d /tmp/ishikawa-script-139.XXXXXX)"
report_path=''
remote_root=''
remote_created=false
master_started=false
artifact_committed=false
artifact_path=''
checksum_path=''
ssh_args=()
emit() {
  if [[ -n "$report_path" ]]; then printf '%s\n' "$1" | tee -a "$report_path"; else printf '%s\n' "$1"; fi
}
cleanup() {
  local status="$?" cleanup_code=0 close_code=0
  trap - EXIT INT TERM
  set +e
  if [[ "$remote_created" == true && "$master_started" == true ]]; then
    timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
      "rm -rf -- '$remote_root' && test ! -e '$remote_root'" >/dev/null 2>&1 || cleanup_code=$?
    if (( cleanup_code == 0 )); then emit 'cleanup_remote_temporary_files=removed'; else emit "cleanup_remote_temporary_files=review_required;exit_code=$cleanup_code"; status=1; fi
  fi
  if [[ "$master_started" == true ]]; then
    timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1 || close_code=$?
    emit "cleanup_ssh_master_exit_code=$close_code"
    (( close_code == 0 )) || status=1
  fi
  if [[ "$artifact_committed" != true ]]; then
    [[ "$artifact_path" == "$ARTIFACT_ROOT"/v1_2_host_qualification_*.json ]] && rm -f -- "$artifact_path"
    [[ "$checksum_path" == "$ARTIFACT_ROOT"/v1_2_host_qualification_*.json.sha256 ]] && rm -f -- "$checksum_path"
  fi
  [[ "$work_root" == /tmp/ishikawa-script-139.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p -- "$work_root/extracted"
tar -xzf "$ACCEPTED_ARCHIVE" -C "$work_root/extracted"
bundle_root="$work_root/extracted/ishikawa-v1.2-deployment-package"
[[ -d "$bundle_root" && ! -L "$bundle_root" ]] || {
  printf 'script_139_v1_2_host_qualification=blocked;reason=local_bundle_invalid\n' >&2
  exit 1
}
bash "$bundle_root/verify-ishikawa-v1.2" >/dev/null || {
  printf 'script_139_v1_2_host_qualification=blocked;reason=local_bundle_verification_failed\n' >&2
  exit 1
}
current_compliance="$work_root/current-coding-standard-compliance.json"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$CODING_STANDARD_EVALUATOR" \
  --bundle-root "$bundle_root" \
  --standard "$CODING_STANDARD" \
  --output "$current_compliance" >/dev/null || {
    printf 'script_139_v1_2_host_qualification=blocked;reason=current_coding_standard_noncompliance\n' >&2
    exit 1
  }
coding_standard_sha256="$(sha256sum "$CODING_STANDARD" | awk '{print $1}')"
coding_standard_receipt_sha256="$(sha256sum "$current_compliance" | awk '{print $1}')"
[[ "$coding_standard_receipt_sha256" == "$ACCEPTED_COMPLIANCE_SHA256" ]] || {
  printf 'script_139_v1_2_host_qualification=blocked;reason=coding_standard_receipt_identity_changed\n' >&2
  exit 1
}
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_ishikawa_v1_2_host_qualification_source' \
    "script_sha256=$script_sha256;target_helper_sha256=$TARGET_HELPER_SHA256" \
    "accepted_archive_sha256=$ACCEPTED_ARCHIVE_SHA256;accepted_report_sha256=$ACCEPTED_REPORT_SHA256" \
    "schema_sha256=$FINAL_SCHEMA_SHA256;retrieval_service_sha256=$RETRIEVAL_SERVICE_SHA256;method_profile_sha256=$METHOD_PROFILE_SHA256" \
    "coding_standard_sha256=$coding_standard_sha256;coding_standard_receipt_sha256=$coding_standard_receipt_sha256" \
    'package_files=111;application_files=104;database_files=4;current_coding_standard_compliance=pass;historical_mutation_files=0' \
    'target_contact=false;application_changed=false;database_changed=false;service_changed=false;model_contact=false' \
    'script_139_v1_2_host_qualification_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/v1_2_host_qualification_${timestamp}_XXXXXX.txt")"
remote_root="/tmp/ishikawa-v1.2-host-qualification-$timestamp-$$"
emit 'purpose=qualify_consolidated_ishikawa_v1_2_deployment_package_on_application_host'
emit "started_utc=$timestamp;script_sha256=$script_sha256;target_helper_sha256=$TARGET_HELPER_SHA256"
emit "accepted_archive_sha256=$ACCEPTED_ARCHIVE_SHA256;accepted_report_sha256=$ACCEPTED_REPORT_SHA256"
emit "schema_sha256=$FINAL_SCHEMA_SHA256;retrieval_service_sha256=$RETRIEVAL_SERVICE_SHA256;method_profile_sha256=$METHOD_PROFILE_SHA256"
emit "coding_standard_sha256=$coding_standard_sha256;coding_standard_receipt_sha256=$coding_standard_receipt_sha256"
emit 'authorized_actions=authenticate_transfer_verify_package_attended_sudo_disposable_application_install_disposable_database_install_compare_and_remove_return_content_free_evidence_remove_transfer_directory'
emit 'non_actions=no_active_application_change_no_accepted_database_write_no_service_enablement_no_model_call_no_credential_read_no_source_document_copy_no_port_forwarding_change'
emit "selected_target=$target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version;accepted_database=$accepted_database"
emit 'milestone=authentication;state=waiting_for_operator_if_prompted'

control_path="$work_root/ssh-control"
ssh_args=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto -o "ControlPath=$control_path" -o ControlPersist=1200)
if [[ -n "$identity_file" ]]; then ssh_args+=(-i "$identity_file" -o IdentitiesOnly=yes); fi
timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$target" >/dev/null 2>&1 || {
  emit 'script_139_v1_2_host_qualification=blocked;reason=ssh_master_start_failed'
  exit 1
}
master_started=true
emit 'milestone=authentication;state=pass'

timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" >/dev/null || {
    emit 'script_139_v1_2_host_qualification=blocked;reason=remote_temporary_directory_not_created'
    exit 1
  }
remote_created=true
emit 'milestone=package_transfer;state=start'
timeout --foreground 180 scp "${ssh_args[@]}" "$ACCEPTED_ARCHIVE" "$TARGET_HELPER" "$target:$remote_root/" >/dev/null || {
  emit 'script_139_v1_2_host_qualification=blocked;reason=package_transfer_failed'
  exit 1
}
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && printf '%s  %s\n%s  %s\n' '$ACCEPTED_ARCHIVE_SHA256' '$(basename -- "$ACCEPTED_ARCHIVE")' '$TARGET_HELPER_SHA256' '$(basename -- "$TARGET_HELPER")' | sha256sum --check --strict - >/dev/null" >/dev/null || {
    emit 'script_139_v1_2_host_qualification=blocked;reason=transferred_payload_checksum_failed'
    exit 1
  }
emit 'milestone=package_transfer;state=pass'

emit 'milestone=fresh_install_qualification;state=waiting_for_operator_sudo_if_prompted'
set +e
timeout --foreground 900 ssh -tt "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && sudo -p '[sudo] password for Ishikawa v1.2 qualification: ' bash './$(basename -- "$TARGET_HELPER")' '$expected_hostname' '$expected_os_version' '$remote_root/$(basename -- "$ACCEPTED_ARCHIVE")' '$ACCEPTED_ARCHIVE_SHA256' '$accepted_database' '$owner_role' '$ingest_role' '$retrieval_role' 'v1.2' > qualification-result.txt" < /dev/tty
remote_code=$?
set -e
emit "remote_execution_exit_code=$remote_code;raw_remote_output_retained=false"

fetched_result="$work_root/qualification-result.txt"
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/qualification-result.txt" "$fetched_result" >/dev/null || {
  emit 'script_139_v1_2_host_qualification=blocked;reason=result_fetch_failed'
  exit 1
}
output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then
    output_contract=blocked
    continue
  fi
  emit "$line"
done <"$fetched_result"
emit "remote_output_contract=$output_contract"
(( remote_code == 0 )) || {
  emit 'script_139_v1_2_host_qualification=blocked;reason=remote_qualification_failed'
  exit 1
}
[[ "$output_contract" == pass ]] || {
  emit 'script_139_v1_2_host_qualification=blocked;reason=remote_output_contract_failed'
  exit 1
}
for fact in \
  'release_version=v1.2' \
  "target_hostname=$expected_hostname;os_id=ubuntu;os_version=$expected_os_version;architecture=amd64" \
  "archive_sha256=$ACCEPTED_ARCHIVE_SHA256;archive_bytes=201883;package_checksums=pass" \
  'package_files=111;application_files=104;database_files=4;historical_mutation_files=0' \
  "schema_sha256=$FINAL_SCHEMA_SHA256;corrected_module_sha256=$CORRECTED_MODULE_SHA256" \
  "retrieval_service_sha256=$RETRIEVAL_SERVICE_SHA256;method_profile_sha256=$METHOD_PROFILE_SHA256" \
  'fresh_application_install=pass;installed_files=101;python_modules=48;unit_files=3;temporary_application_removed=true;active_application_changed=false' \
  'fresh_database_install=pass;schema_version=4;catalog_equivalence=exact;tables=20;views=5;explicit_indexes=14;required_named_constraints=11' \
  'baseline_identity=ishikawa_consolidated_schema_v4;baseline_rows=1;retrieval_privileges=pass' \
  'accepted_active_documents=6;accepted_active_pages=27;accepted_active_chunks=126;accepted_active_embeddings=126' \
  'accepted_database_unchanged=true;temporary_database_dropped=true' \
  'model_contact=false;credential_read=false;source_documents_copied=false;port_forwarding_changed=false' \
  'ishikawa_v1_2_host_qualification=pass'; do
  grep -Fq "$fact" "$fetched_result" || {
    emit 'script_139_v1_2_host_qualification=blocked;reason=remote_result_contract_failed'
    exit 1
  }
done
cluster_state_line="$(sed -n '/^cluster_final_status=.*;cluster_initial_state_restored=true;service_enablement_changed=false$/p' "$fetched_result")"
[[ -n "$cluster_state_line" ]] || {
  emit 'script_139_v1_2_host_qualification=blocked;reason=cluster_state_contract_failed'
  exit 1
}

artifact_path="$ARTIFACT_ROOT/v1_2_host_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  emit 'script_139_v1_2_host_qualification=blocked;reason=artifact_path_exists'
  exit 1
}
printf '{"accepted_active_documents":6,"accepted_archive_sha256":"%s","accepted_database_unchanged":true,"application_file_count":104,"architecture":"amd64","coding_standard_sha256":"%s","database_file_count":4,"fresh_application_install":true,"fresh_database_install":true,"historical_mutation_files":0,"method_profile_sha256":"%s","model_contact":false,"os_version":"%s","package_file_count":111,"persistent_service_configuration_changed":false,"receipt_schema_version":1,"release_name":"Ishikawa v1.2","retrieval_service_sha256":"%s","schema_sha256":"%s","schema_version":4,"target_hostname":"%s","temporary_application_removed":true,"temporary_database_dropped":true}\n' \
  "$ACCEPTED_ARCHIVE_SHA256" "$coding_standard_sha256" "$METHOD_PROFILE_SHA256" \
  "$expected_os_version" "$RETRIEVAL_SERVICE_SHA256" "$FINAL_SCHEMA_SHA256" "$expected_hostname" >"$artifact_path"
artifact_sha256="$(sha256sum "$artifact_path" | awk '{print $1}')"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true
(
  cd -- "$ARTIFACT_ROOT"
  sha256sum --check --strict "$(basename -- "$checksum_path")" >/dev/null
) || {
  emit 'script_139_v1_2_host_qualification=blocked;reason=local_artifact_checksum_failed'
  exit 1
}
artifact_committed=true
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_checksum=$checksum_path"
emit 'milestone=fresh_install_qualification;state=pass'
emit "script_139_v1_2_host_qualification=pass;next_gate=accept_ishikawa_v1_2_deployment_package;local_report=$report_path"
chmod 0600 "$report_path" 2>/dev/null || true
