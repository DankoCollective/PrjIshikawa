#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Install and qualify the accepted final-state Ishikawa application package
#   on EmceeDanko, returning content-free evidence to the repository.
#
# Mental model:
#   Requalify the closed archive against the current coding standard, open one
#   reusable SSH connection, transfer the archive and a neutral temporary
#   verifier, install to ~/Documents/Ishikawa, fetch the bounded result, and
#   remove only the target transfer directory.
#
# Inputs or prerequisites:
#   The accepted Script 88 archive and receipt, current coding standard,
#   strict SSH host trust, and an Ubuntu 24.04 AMD64 EmceeDanko target.
#
# Outputs:
#   A persistent ~/Documents/Ishikawa application directory plus local
#   content-free qualification evidence. No database, service, model,
#   credential, source-document, or port-forwarding state is changed.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/89_install_and_qualify_ishikawa_application_on_emceedanko.sh --run

usage() {
  sed -n '3,24p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run                      Install and qualify on the selected target.' \
    '  --target VALUE             SSH destination or configured SSH alias.' \
    '  --expected-hostname NAME   Exact target short hostname.' \
    '  --expected-os-version VER  Exact expected Ubuntu major.minor version.' \
    '  --identity-file PATH       Optional explicit SSH private key.' \
    '  --validate-only            Validate sources without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly TARGET_HELPER="$SCRIPT_DIR/install-and-qualify-ishikawa-application"
readonly CODING_STANDARD="$REPO_ROOT/CODING_STANDARD.md"
readonly CODING_STANDARD_EVALUATOR="$SCRIPT_DIR/evaluate_consolidated_build_coding_standard.py"
readonly ACCEPTED_REPORT="$REPO_ROOT/local/reports/ishikawa-application-package/application_package_20261020T220722Z_pbNxr7.txt"
readonly ACCEPTED_ARCHIVE="$REPO_ROOT/local/artifacts/ishikawa/application-package/ishikawa-application-package-868c976a4be11fdd.tar.gz"
readonly ACCEPTED_ARCHIVE_CHECKSUM="$ACCEPTED_ARCHIVE.sha256"
readonly ACCEPTED_QUALIFICATION="$REPO_ROOT/local/artifacts/ishikawa/application-package/ishikawa_application_package_qualification_868c976a4be11fdd.json"
readonly ACCEPTED_QUALIFICATION_CHECKSUM="$ACCEPTED_QUALIFICATION.sha256"
readonly ACCEPTED_REPORT_SHA256='8dcafd2b2fcb0fb578ef0f6bb287713ce1917933459e21ae921e410b7fbeb2de'
readonly ACCEPTED_ARCHIVE_SHA256='868c976a4be11fdd0e48722d44e53e4795a8efb3915dfb2eee94230a4f23bc4b'
readonly ACCEPTED_ARCHIVE_CHECKSUM_SHA256='2f3d65b35082006d45e6696e8c72d6dd722965b07dc6ea7f0d323cd762394320'
readonly ACCEPTED_QUALIFICATION_SHA256='d75cdd1aac55b090b1ed407849dc92ff79b333251f92ffc58e306307b3ea91cd'
readonly ACCEPTED_QUALIFICATION_CHECKSUM_SHA256='8e86446be53547f277e2f6abcf60d6e3b99fdc7ee30ee79c5ecdada2e4657209'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-application-installation"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/application-installation"

target="${APPLICATION_HOST_TARGET:-DankoSurface_EmceeDanko}"
expected_hostname="${APPLICATION_HOST_EXPECTED_HOSTNAME:-EmceeDanko}"
expected_os_version="${APPLICATION_HOST_EXPECTED_OS_VERSION:-24.04}"
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
    *) printf 'ERROR: unsupported argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$run_authorized" != "$validate_only" ]] || { printf 'script_89_application_installation=blocked;reason=mode_invalid\n' >&2; exit 2; }
[[ "$target" =~ ^[A-Za-z0-9_@.:-]+$ ]] || { printf 'script_89_application_installation=blocked;reason=target_invalid\n' >&2; exit 2; }
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || { printf 'script_89_application_installation=blocked;reason=expected_hostname_invalid\n' >&2; exit 2; }
[[ "$expected_os_version" =~ ^[0-9]{2}\.[0-9]{2}$ ]] || { printf 'script_89_application_installation=blocked;reason=expected_os_version_invalid\n' >&2; exit 2; }
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] || { printf 'script_89_application_installation=blocked;reason=identity_file_unsafe\n' >&2; exit 2; }
fi
for required in awk bash basename chmod cp date dirname grep mkdir mktemp mv python3 rm scp sed sha256sum ssh stat tar tee timeout; do
  command -v "$required" >/dev/null 2>&1 || { printf 'script_89_application_installation=blocked;reason=local_command_missing\n' >&2; exit 2; }
done
for required_file in \
  "$TARGET_HELPER" "$CODING_STANDARD" "$CODING_STANDARD_EVALUATOR" \
  "$ACCEPTED_REPORT" "$ACCEPTED_ARCHIVE" "$ACCEPTED_ARCHIVE_CHECKSUM" \
  "$ACCEPTED_QUALIFICATION" "$ACCEPTED_QUALIFICATION_CHECKSUM"; do
  [[ -f "$required_file" && ! -L "$required_file" && -r "$required_file" ]] || { printf 'script_89_application_installation=blocked;reason=accepted_input_missing\n' >&2; exit 2; }
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || { printf 'script_89_application_installation=blocked;reason=%s_identity_changed\n' "$3" >&2; exit 2; }
}
check_sha256 "$ACCEPTED_REPORT" "$ACCEPTED_REPORT_SHA256" 'accepted_report'
check_sha256 "$ACCEPTED_ARCHIVE" "$ACCEPTED_ARCHIVE_SHA256" 'accepted_archive'
check_sha256 "$ACCEPTED_ARCHIVE_CHECKSUM" "$ACCEPTED_ARCHIVE_CHECKSUM_SHA256" 'accepted_archive_checksum'
check_sha256 "$ACCEPTED_QUALIFICATION" "$ACCEPTED_QUALIFICATION_SHA256" 'accepted_qualification'
check_sha256 "$ACCEPTED_QUALIFICATION_CHECKSUM" "$ACCEPTED_QUALIFICATION_CHECKSUM_SHA256" 'accepted_qualification_checksum'
(
  cd -- "$(dirname -- "$ACCEPTED_ARCHIVE")"
  sha256sum --check --strict "$(basename -- "$ACCEPTED_ARCHIVE_CHECKSUM")" >/dev/null
) || { printf 'script_89_application_installation=blocked;reason=accepted_archive_checksum_failed\n' >&2; exit 2; }
(
  cd -- "$(dirname -- "$ACCEPTED_QUALIFICATION")"
  sha256sum --check --strict "$(basename -- "$ACCEPTED_QUALIFICATION_CHECKSUM")" >/dev/null
) || { printf 'script_89_application_installation=blocked;reason=accepted_qualification_checksum_failed\n' >&2; exit 2; }
for fact in \
  'coding_standard_compliant=true;coding_standard_findings=0' \
  'deterministic_archive=true;internal_checksums=pass;fresh_installation=pass' \
  'local_tests=319;failures=0;errors=0' \
  'script_88_application_package=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_REPORT" || { printf 'script_89_application_installation=blocked;reason=accepted_report_contract_failed\n' >&2; exit 2; }
done

bash -n "${BASH_SOURCE[0]}" "$TARGET_HELPER"
python3 -B -c 'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' "$CODING_STANDARD_EVALUATOR"
if grep -Eiq 'phase[-_ ]?[0-9]+|Danko|org[_ -]?lab|Agent|repository|Script[[:space:]_-]*[0-9]+' "$TARGET_HELPER"; then
  printf 'script_89_application_installation=blocked;reason=target_helper_jargon_found\n' >&2
  exit 2
fi

work_root="$(mktemp -d /tmp/ishikawa-script-89.XXXXXX)"
report_path=''
remote_root=''
remote_created=false
master_started=false
local_artifact_committed=false
artifact_path=''
checksum_path=''
ssh_args=()
emit() {
  if [[ -n "$report_path" ]]; then
    printf '%s\n' "$1" | tee -a "$report_path"
  else
    printf '%s\n' "$1"
  fi
}
cleanup() {
  local status="$?" cleanup_code=0 close_code=0
  trap - EXIT INT TERM
  set +e
  if [[ "$remote_created" == true && "$master_started" == true ]]; then
    timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "rm -rf -- '$remote_root' && test ! -e '$remote_root'" >/dev/null 2>&1 || cleanup_code=$?
    if (( cleanup_code == 0 )); then emit 'cleanup_remote_temporary_files=removed'; else emit "cleanup_remote_temporary_files=review_required;exit_code=$cleanup_code"; status=1; fi
  fi
  if [[ "$master_started" == true ]]; then
    timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1 || close_code=$?
    emit "cleanup_ssh_master_exit_code=$close_code"
    (( close_code == 0 )) || status=1
  fi
  if [[ "$local_artifact_committed" != true ]]; then
    [[ "$artifact_path" == "$ARTIFACT_ROOT"/application_installation_qualification_*.json ]] && rm -f -- "$artifact_path"
    [[ "$checksum_path" == "$ARTIFACT_ROOT"/application_installation_qualification_*.json.sha256 ]] && rm -f -- "$checksum_path"
  fi
  if [[ "$work_root" == /tmp/ishikawa-script-89.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p -- "$work_root/extracted"
tar -xzf "$ACCEPTED_ARCHIVE" -C "$work_root/extracted"
bundle_root="$work_root/extracted/ishikawa-application-package"
[[ -d "$bundle_root" && ! -L "$bundle_root" ]] || { printf 'script_89_application_installation=blocked;reason=local_bundle_invalid\n' >&2; exit 1; }
current_compliance="$work_root/current-coding-standard-compliance.json"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$CODING_STANDARD_EVALUATOR" \
  --bundle-root "$bundle_root" \
  --standard "$CODING_STANDARD" \
  --output "$current_compliance" >/dev/null || { printf 'script_89_application_installation=blocked;reason=current_coding_standard_noncompliance\n' >&2; exit 1; }
coding_standard_sha256="$(sha256sum "$CODING_STANDARD" | awk '{print $1}')"
coding_standard_receipt_sha256="$(sha256sum "$current_compliance" | awk '{print $1}')"
helper_sha256="$(sha256sum "$TARGET_HELPER" | awk '{print $1}')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_ishikawa_application_target_installation_source' \
    "script_sha256=$script_sha256;target_helper_sha256=$helper_sha256" \
    "accepted_archive_sha256=$ACCEPTED_ARCHIVE_SHA256;accepted_report_sha256=$ACCEPTED_REPORT_SHA256" \
    "coding_standard_sha256=$coding_standard_sha256;coding_standard_receipt_sha256=$coding_standard_receipt_sha256" \
    'current_coding_standard_compliance=pass;historical_migration_or_mutation_files=0' \
    'target_contact=false;installation_changed=false;database_changed=false;service_changed=false;model_contact=false' \
    'script_89_application_installation_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/application_installation_${timestamp}_XXXXXX.txt")"
remote_root="/tmp/ishikawa-application-install-$timestamp-$$"
emit 'purpose=install_and_qualify_ishikawa_application_package'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;target_helper_sha256=$helper_sha256"
emit "accepted_archive_sha256=$ACCEPTED_ARCHIVE_SHA256;accepted_report_sha256=$ACCEPTED_REPORT_SHA256"
emit "coding_standard_sha256=$coding_standard_sha256;coding_standard_receipt_sha256=$coding_standard_receipt_sha256"
emit 'current_coding_standard_compliance=pass;historical_migration_or_mutation_files=0'
emit 'authorized_actions=authenticate_transfer_checksum_bound_package_verify_target_install_new_or_reuse_exact_application_directory_qualify_installed_application_return_content_free_evidence_remove_transfer_directory'
emit 'non_actions=no_sudo_no_package_install_no_database_or_service_change_no_model_call_no_credential_read_no_source_document_copy_no_port_forwarding_change_no_existing_installation_overwrite'
emit "selected_target=$target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version;install_root=HOME/Documents/Ishikawa"
emit 'milestone=authentication;state=waiting_for_operator_if_prompted'

control_path="$work_root/ssh-control"
ssh_args=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto -o "ControlPath=$control_path" -o ControlPersist=900)
if [[ -n "$identity_file" ]]; then ssh_args+=(-i "$identity_file" -o IdentitiesOnly=yes); fi
timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$target" >/dev/null 2>&1 || { emit 'script_89_application_installation=blocked;reason=ssh_master_start_failed'; exit 1; }
master_started=true
emit 'milestone=authentication;state=pass'

timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" >/dev/null || { emit 'script_89_application_installation=blocked;reason=remote_temporary_directory_not_created'; exit 1; }
remote_created=true
emit 'milestone=package_transfer;state=start'
timeout --foreground 180 scp "${ssh_args[@]}" "$ACCEPTED_ARCHIVE" "$TARGET_HELPER" "$target:$remote_root/" >/dev/null || { emit 'script_89_application_installation=blocked;reason=package_transfer_failed'; exit 1; }
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "cd '$remote_root' && printf '%s  %s\n%s  %s\n' '$ACCEPTED_ARCHIVE_SHA256' '$(basename -- "$ACCEPTED_ARCHIVE")' '$helper_sha256' '$(basename -- "$TARGET_HELPER")' | sha256sum --check --strict - >/dev/null" >/dev/null || { emit 'script_89_application_installation=blocked;reason=transferred_payload_checksum_failed'; exit 1; }
emit 'milestone=package_transfer;state=pass'

emit 'milestone=application_installation;state=start'
set +e
timeout --foreground 300 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && bash './$(basename -- "$TARGET_HELPER")' '$expected_hostname' '$expected_os_version' '$remote_root/$(basename -- "$ACCEPTED_ARCHIVE")' '$ACCEPTED_ARCHIVE_SHA256' '$remote_root/qualification-result.txt'" >/dev/null 2>&1
remote_code=$?
set -e
emit "remote_execution_exit_code=$remote_code;raw_remote_output_retained=false"

fetched_result="$work_root/qualification-result.txt"
timeout --foreground 60 scp "${ssh_args[@]}" "$target:$remote_root/qualification-result.txt" "$fetched_result" >/dev/null || { emit 'script_89_application_installation=blocked;reason=result_fetch_failed'; exit 1; }
output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then
    output_contract=blocked
    continue
  fi
  emit "$line"
done <"$fetched_result"
emit "remote_output_contract=$output_contract"
(( remote_code == 0 )) || { emit 'script_89_application_installation=blocked;reason=remote_qualification_failed'; exit 1; }
[[ "$output_contract" == pass ]] || { emit 'script_89_application_installation=blocked;reason=remote_output_contract_failed'; exit 1; }
for fact in \
  "target_hostname=$expected_hostname;os_id=ubuntu;os_version=$expected_os_version;architecture=amd64" \
  "archive_sha256=$ACCEPTED_ARCHIVE_SHA256;package_checksums=pass" \
  'existing_installation_overwritten=false' \
  'installed_python_modules=42;installed_sql_files=0;historical_mutation_files=0' \
  'product_display_name=Ishikawa;document_classes=3;catalog_documents=0' \
  'native_runtime_dependencies=pass;python_minimum=3.12' \
  'database_changed=false;service_changed=false;model_contact=false;credential_read=false;source_documents_copied=false' \
  'ishikawa_application_install_qualification=pass'; do
  grep -Fq "$fact" "$fetched_result" || { emit 'script_89_application_installation=blocked;reason=remote_result_contract_failed'; exit 1; }
done

installed_file_count="$(sed -n 's/^installed_file_count=\([0-9][0-9]*\);.*/\1/p' "$fetched_result")"
[[ "$installed_file_count" =~ ^[0-9]+$ ]] || { emit 'script_89_application_installation=blocked;reason=installed_file_count_invalid'; exit 1; }
installation_action="$(sed -n 's/^installation_action=\([a-z_][a-z_]*\);.*/\1/p' "$fetched_result")"
[[ "$installation_action" == 'installed_new' || "$installation_action" == 'reused_exact' ]] || { emit 'script_89_application_installation=blocked;reason=installation_action_invalid'; exit 1; }
artifact_path="$ARTIFACT_ROOT/application_installation_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || { emit 'script_89_application_installation=blocked;reason=artifact_path_exists'; exit 1; }
printf '{"architecture":"amd64","archive_sha256":"%s","coding_standard_sha256":"%s","database_changed":false,"historical_mutation_files":0,"installation_action":"%s","installed_file_count":%s,"installed_python_modules":42,"model_contact":false,"os_version":"%s","product_display_name":"Ishikawa","schema_version":1,"service_changed":false,"source_documents_copied":false,"target_hostname":"%s"}\n' \
  "$ACCEPTED_ARCHIVE_SHA256" "$coding_standard_sha256" "$installation_action" "$installed_file_count" "$expected_os_version" "$expected_hostname" >"$artifact_path"
artifact_sha256="$(sha256sum "$artifact_path" | awk '{print $1}')"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true
(
  cd -- "$ARTIFACT_ROOT"
  sha256sum --check --strict "$(basename -- "$checksum_path")" >/dev/null
) || { emit 'script_89_application_installation=blocked;reason=local_artifact_checksum_failed'; exit 1; }
local_artifact_committed=true
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_checksum=$checksum_path"
emit 'milestone=application_installation;state=pass'
emit "script_89_application_installation=pass;local_report=$report_path;next_gate=assemble_final_database_schema_package"
chmod 0600 "$report_path" 2>/dev/null || true

