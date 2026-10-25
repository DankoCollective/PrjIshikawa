#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Promote the qualified Ishikawa candidate on EmceeDanko into the canonical
#   application path while retaining the prior exact installation for rollback.
#
# Mental model:
#   Bind accepted candidate evidence, transfer the exact old and new packages
#   plus a neutral promoter, require Ishikawa's managed service and state to be
#   stopped, perform an atomic rollback-protected promotion, and return only
#   bounded evidence.
#
# Inputs or prerequisites:
#   Accepted candidate evidence, both checksum-bound application archives,
#   strict SSH trust, and the unchanged old and candidate target directories.
#
# Outputs:
#   Canonical Ishikawa application, preserved pre-v1 rollback directory, final
#   user units, and local evidence. No service, database, or model is started.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/103_promote_ishikawa_application_candidate.sh --run

usage() {
  sed -n '3,21p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run                      Promote on the selected target.' \
    '  --target VALUE             SSH destination or configured SSH alias.' \
    '  --expected-hostname NAME   Exact target short hostname.' \
    '  --expected-os-version VER  Exact expected Ubuntu major.minor version.' \
    '  --identity-file PATH       Optional explicit SSH private key.' \
    '  --validate-only            Validate sources without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly TARGET_HELPER="$SCRIPT_DIR/promote-ishikawa-application-candidate"
readonly ACCEPTED_REPORT="$REPO_ROOT/local/reports/ishikawa-final-application-candidate/final_application_candidate_20261021T024321Z_Pgd6ky.txt"
readonly ACCEPTED_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/final-application-candidate/final_application_candidate_qualification_20261021T024321Z.json"
readonly ACCEPTED_CHECKSUM="$ACCEPTED_ARTIFACT.sha256"
readonly OLD_ARCHIVE="$REPO_ROOT/local/artifacts/ishikawa/application-package/ishikawa-application-package-868c976a4be11fdd.tar.gz"
readonly OLD_ARCHIVE_CHECKSUM="$OLD_ARCHIVE.sha256"
readonly NEW_ARCHIVE="$REPO_ROOT/local/artifacts/ishikawa/final-application-package/ishikawa-application-package-9a0129180866f3f1.tar.gz"
readonly NEW_ARCHIVE_CHECKSUM="$NEW_ARCHIVE.sha256"
readonly ACCEPTED_REPORT_SHA256='9f5378c3d695eb1a41a918248fb408cb1a41eaef53db73996add165113e3ac5b'
readonly ACCEPTED_ARTIFACT_SHA256='1fd5db55559157de8372747123726d807ac0fcb471a5919eb7e99216534bddda'
readonly ACCEPTED_CHECKSUM_SHA256='ec3454d61c86b5663ce5fec9cd08dc62c9d7fcb3d1760af59c8a43fe5ae82ad6'
readonly OLD_ARCHIVE_SHA256='868c976a4be11fdd0e48722d44e53e4795a8efb3915dfb2eee94230a4f23bc4b'
readonly OLD_ARCHIVE_CHECKSUM_SHA256='2f3d65b35082006d45e6696e8c72d6dd722965b07dc6ea7f0d323cd762394320'
readonly NEW_ARCHIVE_SHA256='9a0129180866f3f12125eeda756b747b501eecb915819a154527b71fac6fe374'
readonly NEW_ARCHIVE_CHECKSUM_SHA256='74c8d4e65066569b548b1761c1f01d1cb0bba9dba3a77a853b940a993951e80c'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-application-promotion"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/application-promotion"

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
    *) printf 'script_103_application_promotion=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$run_authorized" != "$validate_only" ]] || { printf 'script_103_application_promotion=blocked;reason=mode_invalid\n' >&2; exit 2; }
[[ "$target" =~ ^[A-Za-z0-9_@.:-]+$ ]] || { printf 'script_103_application_promotion=blocked;reason=target_invalid\n' >&2; exit 2; }
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || { printf 'script_103_application_promotion=blocked;reason=expected_hostname_invalid\n' >&2; exit 2; }
[[ "$expected_os_version" =~ ^[0-9]{2}\.[0-9]{2}$ ]] || { printf 'script_103_application_promotion=blocked;reason=expected_os_version_invalid\n' >&2; exit 2; }
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] || {
    printf 'script_103_application_promotion=blocked;reason=identity_file_unsafe\n' >&2
    exit 2
  }
fi

for required in awk bash basename chmod cp date grep mkdir mktemp rm scp sed sha256sum ssh stat tee timeout; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_103_application_promotion=blocked;reason=local_command_missing\n' >&2
    exit 2
  }
done
for required_file in \
  "$TARGET_HELPER" "$ACCEPTED_REPORT" "$ACCEPTED_ARTIFACT" "$ACCEPTED_CHECKSUM" \
  "$OLD_ARCHIVE" "$OLD_ARCHIVE_CHECKSUM" "$NEW_ARCHIVE" "$NEW_ARCHIVE_CHECKSUM"; do
  [[ -f "$required_file" && ! -L "$required_file" && -r "$required_file" ]] || {
    printf 'script_103_application_promotion=blocked;reason=required_input_unsafe\n' >&2
    exit 2
  }
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_103_application_promotion=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}
check_sha256 "$ACCEPTED_REPORT" "$ACCEPTED_REPORT_SHA256" 'accepted_report'
check_sha256 "$ACCEPTED_ARTIFACT" "$ACCEPTED_ARTIFACT_SHA256" 'accepted_artifact'
check_sha256 "$ACCEPTED_CHECKSUM" "$ACCEPTED_CHECKSUM_SHA256" 'accepted_checksum'
check_sha256 "$OLD_ARCHIVE" "$OLD_ARCHIVE_SHA256" 'old_archive'
check_sha256 "$OLD_ARCHIVE_CHECKSUM" "$OLD_ARCHIVE_CHECKSUM_SHA256" 'old_archive_checksum'
check_sha256 "$NEW_ARCHIVE" "$NEW_ARCHIVE_SHA256" 'new_archive'
check_sha256 "$NEW_ARCHIVE_CHECKSUM" "$NEW_ARCHIVE_CHECKSUM_SHA256" 'new_archive_checksum'
for checksum in "$ACCEPTED_CHECKSUM" "$OLD_ARCHIVE_CHECKSUM" "$NEW_ARCHIVE_CHECKSUM"; do
  (cd -- "$(dirname -- "$checksum")" && sha256sum --check --strict "$(basename -- "$checksum")" >/dev/null) || {
    printf 'script_103_application_promotion=blocked;reason=accepted_checksum_failed\n' >&2
    exit 2
  }
done
for fact in \
  'ishikawa_candidate_install_qualification=pass' \
  'remote_output_contract=pass' \
  'script_102_final_application_candidate=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_REPORT" || {
    printf 'script_103_application_promotion=blocked;reason=accepted_report_contract_failed\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}" "$TARGET_HELPER"
if grep -Eiq 'phase[-_ ]?[0-9]+|Danko|org[_ -]?lab|Agent|repository|Script[[:space:]_-]*[0-9]+' "$TARGET_HELPER"; then
  printf 'script_103_application_promotion=blocked;reason=target_helper_jargon_found\n' >&2
  exit 2
fi

work_root="$(mktemp -d /tmp/ishikawa-script-103.XXXXXX)"
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
    [[ "$artifact_path" == "$ARTIFACT_ROOT"/application_promotion_qualification_*.json ]] && rm -f -- "$artifact_path"
    [[ "$checksum_path" == "$ARTIFACT_ROOT"/application_promotion_qualification_*.json.sha256 ]] && rm -f -- "$checksum_path"
  fi
  if [[ "$work_root" == /tmp/ishikawa-script-103.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

helper_sha256="$(sha256sum "$TARGET_HELPER" | awk '{print $1}')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_ishikawa_application_candidate_promotion_source' \
    "script_sha256=$script_sha256;target_helper_sha256=$helper_sha256" \
    "accepted_script_102_report_sha256=$ACCEPTED_REPORT_SHA256;accepted_script_102_artifact_sha256=$ACCEPTED_ARTIFACT_SHA256" \
    "old_archive_sha256=$OLD_ARCHIVE_SHA256;new_archive_sha256=$NEW_ARCHIVE_SHA256" \
    'target_contact=false;active_installation_changed=false;service_changed=false;database_changed=false;model_contact=false' \
    'script_103_application_promotion_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/application_promotion_${timestamp}_XXXXXX.txt")"
remote_root="/tmp/ishikawa-application-promotion-$timestamp-$$"
emit 'purpose=promote_ishikawa_application_candidate'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;target_helper_sha256=$helper_sha256"
emit "accepted_script_102_report_sha256=$ACCEPTED_REPORT_SHA256;accepted_script_102_artifact_sha256=$ACCEPTED_ARTIFACT_SHA256"
emit "old_archive_sha256=$OLD_ARCHIVE_SHA256;new_archive_sha256=$NEW_ARCHIVE_SHA256"
emit 'authorized_actions=authenticate_transfer_exact_archives_verify_stopped_stack_preserve_old_installation_promote_candidate_install_exact_user_units_reload_user_manager_return_content_free_evidence_remove_transfer_directory'
emit 'non_actions=no_sudo_no_package_install_no_deletion_no_service_start_no_boot_enable_no_database_container_model_credential_source_document_or_port_forwarding_change'
emit "selected_target=$target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version"
emit 'milestone=authentication;state=waiting_for_operator_if_prompted'

control_path="$work_root/ssh-control"
ssh_args=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto -o "ControlPath=$control_path" -o ControlPersist=900)
if [[ -n "$identity_file" ]]; then ssh_args+=(-i "$identity_file" -o IdentitiesOnly=yes); fi
timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$target" >/dev/null 2>&1 || { emit 'script_103_application_promotion=blocked;reason=ssh_master_start_failed'; exit 1; }
master_started=true
emit 'milestone=authentication;state=pass'
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" >/dev/null || { emit 'script_103_application_promotion=blocked;reason=remote_temporary_directory_not_created'; exit 1; }
remote_created=true

emit 'milestone=payload_transfer;state=start'
timeout --foreground 180 scp "${ssh_args[@]}" "$OLD_ARCHIVE" "$NEW_ARCHIVE" "$TARGET_HELPER" "$target:$remote_root/" >/dev/null || { emit 'script_103_application_promotion=blocked;reason=payload_transfer_failed'; exit 1; }
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && printf '%s  %s\n%s  %s\n%s  %s\n' '$OLD_ARCHIVE_SHA256' '$(basename -- "$OLD_ARCHIVE")' '$NEW_ARCHIVE_SHA256' '$(basename -- "$NEW_ARCHIVE")' '$helper_sha256' '$(basename -- "$TARGET_HELPER")' | sha256sum --check --strict - >/dev/null" >/dev/null || { emit 'script_103_application_promotion=blocked;reason=transferred_payload_checksum_failed'; exit 1; }
emit 'milestone=payload_transfer;state=pass'

emit 'milestone=application_promotion;state=start'
set +e
timeout --foreground 300 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && bash './$(basename -- "$TARGET_HELPER")' '$expected_hostname' '$expected_os_version' '$remote_root/$(basename -- "$OLD_ARCHIVE")' '$OLD_ARCHIVE_SHA256' '$remote_root/$(basename -- "$NEW_ARCHIVE")' '$NEW_ARCHIVE_SHA256' '$remote_root/qualification-result.txt'" \
  >/dev/null 2>&1
remote_code=$?
set -e
emit "remote_execution_exit_code=$remote_code;raw_remote_output_retained=false"
fetched_result="$work_root/qualification-result.txt"
timeout --foreground 60 scp "${ssh_args[@]}" "$target:$remote_root/qualification-result.txt" "$fetched_result" >/dev/null || { emit 'script_103_application_promotion=blocked;reason=result_fetch_failed'; exit 1; }
output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then
    output_contract=blocked
    continue
  fi
  emit "$line"
done <"$fetched_result"
emit "remote_output_contract=$output_contract"
(( remote_code == 0 )) || { emit 'script_103_application_promotion=blocked;reason=remote_promotion_failed'; exit 1; }
[[ "$output_contract" == pass ]] || { emit 'script_103_application_promotion=blocked;reason=remote_output_contract_failed'; exit 1; }
for fact in \
  "target_hostname=$expected_hostname;os_id=ubuntu;os_version=$expected_os_version;architecture=amd64" \
  "old_archive_sha256=$OLD_ARCHIVE_SHA256;new_archive_sha256=$NEW_ARCHIVE_SHA256;package_checksums=pass" \
  'active_root=HOME/Documents/Ishikawa;rollback_root=HOME/Documents/Ishikawa-pre-v1' \
  'active_payload_files=94;rollback_preserved=true;candidate_consumed=true' \
  'user_units=3;unit_identity=exact;services_started=false;boot_enabled=false' \
  'database_changed=false;container_changed=false;model_contact=false;credential_read=false;source_documents_changed=false' \
  'ishikawa_candidate_promotion=pass'; do
  grep -Fq "$fact" "$fetched_result" || { emit 'script_103_application_promotion=blocked;reason=remote_result_contract_failed'; exit 1; }
done
promotion_action="$(sed -n 's/^promotion_action=\([a-z_][a-z_]*\);.*/\1/p' "$fetched_result")"
[[ "$promotion_action" == promoted_new || "$promotion_action" == reused_exact ]] || { emit 'script_103_application_promotion=blocked;reason=promotion_action_invalid'; exit 1; }

artifact_path="$ARTIFACT_ROOT/application_promotion_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || { emit 'script_103_application_promotion=blocked;reason=artifact_path_exists'; exit 1; }
printf '{"active_payload_files":94,"boot_enabled":false,"database_changed":false,"model_contact":false,"new_archive_sha256":"%s","old_archive_sha256":"%s","promotion_action":"%s","receipt_schema_version":1,"rollback_preserved":true,"services_started":false,"source_documents_changed":false,"target_hostname":"%s","unit_count":3}\n' \
  "$NEW_ARCHIVE_SHA256" "$OLD_ARCHIVE_SHA256" "$promotion_action" "$expected_hostname" >"$artifact_path"
artifact_sha256="$(sha256sum "$artifact_path" | awk '{print $1}')"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true
(cd -- "$ARTIFACT_ROOT" && sha256sum --check --strict "$(basename -- "$checksum_path")" >/dev/null) || { emit 'script_103_application_promotion=blocked;reason=local_artifact_checksum_failed'; exit 1; }
artifact_committed=true
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_checksum=$checksum_path"
emit 'milestone=application_promotion;state=pass'
emit "script_103_application_promotion=pass;local_report=$report_path;next_gate=run_first_end_to_end_ishikawa_test"
chmod 0600 "$report_path" 2>/dev/null || true
