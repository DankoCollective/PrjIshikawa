#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Promote the qualified corrected application candidate into the active
#   Ishikawa runtime without replacing operator-owned or application state.
#
# Mental model:
#   Bind the accepted candidate and both complete packages, prove locally that
#   their payloads differ in exactly one immutable module, send only manifests
#   and a neutral promoter, then return content-free qualification evidence.
#
# Inputs or prerequisites:
#   Clean corrected-package and candidate evidence, strict SSH trust, and a
#   stopped EmceeDanko Ishikawa installation.
#
# Outputs or artifact lane:
#   A corrected active immutable runtime, a retained exact sibling candidate,
#   and content-free evidence. Database and operator state are preserved.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/105_promote_corrected_ishikawa_runtime_candidate.sh --run

usage() {
  sed -n '3,25p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run                      Promote the qualified runtime correction.' \
    '  --target VALUE             SSH destination or configured SSH alias.' \
    '  --expected-hostname NAME   Exact target short hostname.' \
    '  --expected-os-version VER  Exact expected Ubuntu major.minor version.' \
    '  --identity-file PATH       Optional explicit SSH private key.' \
    '  --validate-only            Validate sources without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly TARGET_HELPER="$SCRIPT_DIR/promote-ishikawa-runtime-candidate"
readonly ACCEPTED_REPORT="$REPO_ROOT/local/reports/ishikawa-final-application-candidate/final_application_candidate_20261021T035336Z_9DTNha.txt"
readonly ACCEPTED_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/final-application-candidate/final_application_candidate_qualification_20261021T035336Z.json"
readonly ACCEPTED_CHECKSUM="$ACCEPTED_ARTIFACT.sha256"
readonly OLD_ARCHIVE="$REPO_ROOT/local/artifacts/ishikawa/final-application-package/ishikawa-application-package-9a0129180866f3f1.tar.gz"
readonly OLD_ARCHIVE_CHECKSUM="$OLD_ARCHIVE.sha256"
readonly NEW_ARCHIVE="$REPO_ROOT/local/artifacts/ishikawa/final-application-package/ishikawa-application-package-bb3eb2c33e6380d0.tar.gz"
readonly NEW_ARCHIVE_CHECKSUM="$NEW_ARCHIVE.sha256"
readonly ACCEPTED_REPORT_SHA256='fc96880a2f1ea900bf14e7747bb842a0a0c115d940d359d5dd5c10cfe0d35844'
readonly ACCEPTED_ARTIFACT_SHA256='a0a571e9291f5e54fe576733bc46d60cf6bf601a13920751d26d1070563892f7'
readonly ACCEPTED_CHECKSUM_SHA256='6466d51a49e66eba2a37c8ad72b0e5abfaa38668a397184f09b5bc3fce0b2575'
readonly OLD_ARCHIVE_SHA256='9a0129180866f3f12125eeda756b747b501eecb915819a154527b71fac6fe374'
readonly OLD_ARCHIVE_CHECKSUM_SHA256='74c8d4e65066569b548b1761c1f01d1cb0bba9dba3a77a853b940a993951e80c'
readonly NEW_ARCHIVE_SHA256='bb3eb2c33e6380d04e32fa474a7592260604d2ccef0c3cdb9181db116965e1b0'
readonly NEW_ARCHIVE_CHECKSUM_SHA256='8c50398e4f2f8c3088016a748c528da92031dcd3673b70aae3f86cb754e8c898'
readonly RELATIVE_MODULE='application/python/ishikawa/ingestion_runtime.py'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-runtime-candidate-promotion"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/runtime-candidate-promotion"

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
    *) printf 'script_105_runtime_candidate_promotion=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || { printf 'script_105_runtime_candidate_promotion=blocked;reason=mode_invalid\n' >&2; exit 2; }
[[ "$target" =~ ^[A-Za-z0-9_@.:-]+$ ]] || { printf 'script_105_runtime_candidate_promotion=blocked;reason=target_invalid\n' >&2; exit 2; }
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || { printf 'script_105_runtime_candidate_promotion=blocked;reason=expected_hostname_invalid\n' >&2; exit 2; }
[[ "$expected_os_version" =~ ^[0-9]{2}\.[0-9]{2}$ ]] || { printf 'script_105_runtime_candidate_promotion=blocked;reason=expected_os_version_invalid\n' >&2; exit 2; }
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] || {
    printf 'script_105_runtime_candidate_promotion=blocked;reason=identity_file_unsafe\n' >&2
    exit 2
  }
fi

for required in awk bash basename chmod cp date dirname find grep mkdir mktemp mv python3 rm scp sed sha256sum ssh stat tar tee timeout; do
  command -v "$required" >/dev/null 2>&1 || { printf 'script_105_runtime_candidate_promotion=blocked;reason=local_command_missing\n' >&2; exit 2; }
done
for file in "$TARGET_HELPER" "$ACCEPTED_REPORT" "$ACCEPTED_ARTIFACT" "$ACCEPTED_CHECKSUM" "$OLD_ARCHIVE" "$OLD_ARCHIVE_CHECKSUM" "$NEW_ARCHIVE" "$NEW_ARCHIVE_CHECKSUM"; do
  [[ -f "$file" && ! -L "$file" && -r "$file" ]] || { printf 'script_105_runtime_candidate_promotion=blocked;reason=required_input_unsafe\n' >&2; exit 2; }
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_105_runtime_candidate_promotion=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}
check_sha256 "$ACCEPTED_REPORT" "$ACCEPTED_REPORT_SHA256" accepted_report
check_sha256 "$ACCEPTED_ARTIFACT" "$ACCEPTED_ARTIFACT_SHA256" accepted_artifact
check_sha256 "$ACCEPTED_CHECKSUM" "$ACCEPTED_CHECKSUM_SHA256" accepted_checksum
check_sha256 "$OLD_ARCHIVE" "$OLD_ARCHIVE_SHA256" old_archive
check_sha256 "$OLD_ARCHIVE_CHECKSUM" "$OLD_ARCHIVE_CHECKSUM_SHA256" old_archive_checksum
check_sha256 "$NEW_ARCHIVE" "$NEW_ARCHIVE_SHA256" new_archive
check_sha256 "$NEW_ARCHIVE_CHECKSUM" "$NEW_ARCHIVE_CHECKSUM_SHA256" new_archive_checksum
for checksum in "$ACCEPTED_CHECKSUM" "$OLD_ARCHIVE_CHECKSUM" "$NEW_ARCHIVE_CHECKSUM"; do
  (cd -- "$(dirname -- "$checksum")" && sha256sum --check --strict "$(basename -- "$checksum")" >/dev/null) \
    || { printf 'script_105_runtime_candidate_promotion=blocked;reason=accepted_checksum_failed\n' >&2; exit 2; }
done
for fact in \
  'ishikawa_candidate_install_qualification=pass' \
  "archive_sha256=$NEW_ARCHIVE_SHA256;package_checksums=pass;bundle_files=97;payload_files=94" \
  'active_installation_overwritten=false' \
  'database_changed=false;service_changed=false;model_contact=false;credential_read=false;source_documents_copied=false' \
  'script_102_final_application_candidate=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_REPORT" || { printf 'script_105_runtime_candidate_promotion=blocked;reason=accepted_report_contract_failed\n' >&2; exit 2; }
done

bash -n "${BASH_SOURCE[0]}" "$TARGET_HELPER"
if grep -Eiq 'phase[-_ ]?[0-9]+|Danko|org[_ -]?lab|Agent|repository|Script[[:space:]_-]*[0-9]+' "$TARGET_HELPER"; then
  printf 'script_105_runtime_candidate_promotion=blocked;reason=target_helper_jargon_found\n' >&2
  exit 2
fi

work_root="$(mktemp -d /tmp/ishikawa-script-105.XXXXXX)"
report_path=''
remote_root=''
remote_created=false
master_started=false
artifact_committed=false
artifact_path=''
checksum_path=''
ssh_args=()
cleanup() {
  local status="$?" cleanup_code=0 close_code=0
  trap - EXIT INT TERM
  set +e
  if [[ "$remote_created" == true && "$master_started" == true ]]; then
    timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
      "rm -rf -- '$remote_root' && test ! -e '$remote_root'" >/dev/null 2>&1 || cleanup_code=$?
    [[ "$cleanup_code" == 0 ]] && emit 'cleanup_remote_temporary_files=removed' || { emit "cleanup_remote_temporary_files=review_required;exit_code=$cleanup_code"; status=1; }
  fi
  if [[ "$master_started" == true ]]; then
    timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1 || close_code=$?
    emit "cleanup_ssh_master_exit_code=$close_code"
    (( close_code == 0 )) || status=1
  fi
  if [[ "$artifact_committed" != true ]]; then
    [[ "$artifact_path" == "$ARTIFACT_ROOT"/runtime_candidate_promotion_*.json ]] && rm -f -- "$artifact_path"
    [[ "$checksum_path" == "$ARTIFACT_ROOT"/runtime_candidate_promotion_*.json.sha256 ]] && rm -f -- "$checksum_path"
  fi
  [[ "$work_root" == /tmp/ishikawa-script-105.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  [[ -z "$report_path" ]] || chmod 0600 "$report_path" 2>/dev/null || true
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p -- "$work_root/old" "$work_root/new"
tar -xzf "$OLD_ARCHIVE" -C "$work_root/old"
tar -xzf "$NEW_ARCHIVE" -C "$work_root/new"
readonly old_payload="$work_root/old/ishikawa-application-package/payload"
readonly new_payload="$work_root/new/ishikawa-application-package/payload"
for root in "$old_payload" "$new_payload"; do
  [[ -d "$root" && ! -L "$root" ]] || { printf 'script_105_runtime_candidate_promotion=blocked;reason=payload_missing\n' >&2; exit 2; }
done
old_full_manifest="$work_root/old-payload.sha256"
new_full_manifest="$work_root/new-payload.sha256"
old_manifest="$work_root/old-immutable.sha256"
new_manifest="$work_root/new-immutable.sha256"
(
  cd -- "$old_payload"
  find application config docs scripts systemd -type f -printf '%p\n' | sort | while IFS= read -r file; do sha256sum "$file"; done
) >"$old_full_manifest"
(
  cd -- "$new_payload"
  find application config docs scripts systemd -type f -printf '%p\n' | sort | while IFS= read -r file; do sha256sum "$file"; done
) >"$new_full_manifest"
awk '$2 ~ /^(application|docs|scripts|systemd)\//' "$old_full_manifest" >"$old_manifest"
awk '$2 ~ /^(application|docs|scripts|systemd)\//' "$new_full_manifest" >"$new_manifest"

PYTHONDONTWRITEBYTECODE=1 python3 -B - "$old_full_manifest" "$new_full_manifest" "$RELATIVE_MODULE" <<'PY' \
  || { printf 'script_105_runtime_candidate_promotion=blocked;reason=package_delta_invalid\n' >&2; exit 2; }
from pathlib import Path
import sys

def read(path):
    result = {}
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        digest, name = line.split("  ", 1)
        result[name] = digest
    return result

old = read(sys.argv[1])
new = read(sys.argv[2])
if set(old) != set(new):
    raise SystemExit(1)
changed = [name for name in sorted(old) if old[name] != new[name]]
if changed != [sys.argv[3]]:
    raise SystemExit(1)
PY

readonly old_module_sha256="$(sha256sum "$old_payload/$RELATIVE_MODULE" | awk '{print $1}')"
readonly new_module_sha256="$(sha256sum "$new_payload/$RELATIVE_MODULE" | awk '{print $1}')"
readonly old_manifest_sha256="$(sha256sum "$old_manifest" | awk '{print $1}')"
readonly new_manifest_sha256="$(sha256sum "$new_manifest" | awk '{print $1}')"
readonly full_manifest_sha256="$(sha256sum "$new_full_manifest" | awk '{print $1}')"
readonly immutable_file_count="$(awk 'END {print NR+0}' "$new_manifest")"
readonly candidate_file_count="$(awk 'END {print NR+0}' "$new_full_manifest")"
[[ "$candidate_file_count" == 94 ]] || { printf 'script_105_runtime_candidate_promotion=blocked;reason=payload_file_count_invalid\n' >&2; exit 2; }

helper_sha256="$(sha256sum "$TARGET_HELPER" | awk '{print $1}')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_state_preserving_runtime_candidate_promotion' \
    "script_sha256=$script_sha256;target_helper_sha256=$helper_sha256" \
    "accepted_candidate_report_sha256=$ACCEPTED_REPORT_SHA256;accepted_candidate_artifact_sha256=$ACCEPTED_ARTIFACT_SHA256" \
    "old_archive_sha256=$OLD_ARCHIVE_SHA256;new_archive_sha256=$NEW_ARCHIVE_SHA256" \
    "package_delta=$RELATIVE_MODULE;old_module_sha256=$old_module_sha256;new_module_sha256=$new_module_sha256" \
    "immutable_file_count=$immutable_file_count;candidate_file_count=$candidate_file_count;package_delta_count=1" \
    'target_contact=false;active_installation_changed=false;database_changed=false;service_changed=false;model_contact=false' \
    'script_105_runtime_candidate_promotion_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/runtime_candidate_promotion_${timestamp}_XXXXXX.txt")"
emit() { if [[ -n "$report_path" ]]; then printf '%s\n' "$1" | tee -a "$report_path"; else printf '%s\n' "$1"; fi; }
block() { emit "script_105_runtime_candidate_promotion=blocked;reason=$1"; exit 1; }
emit 'purpose=promote_corrected_ishikawa_runtime_candidate'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;target_helper_sha256=$helper_sha256"
emit "accepted_candidate_report_sha256=$ACCEPTED_REPORT_SHA256;accepted_candidate_artifact_sha256=$ACCEPTED_ARTIFACT_SHA256"
emit "old_archive_sha256=$OLD_ARCHIVE_SHA256;new_archive_sha256=$NEW_ARCHIVE_SHA256"
emit "package_delta=$RELATIVE_MODULE;old_module_sha256=$old_module_sha256;new_module_sha256=$new_module_sha256"
emit "immutable_file_count=$immutable_file_count;candidate_file_count=$candidate_file_count;package_delta_count=1"
emit 'authorized_actions=authenticate_transfer_checksum_manifests_verify_stopped_state_verify_exact_candidate_and_active_immutable_files_atomically_promote_one_corrected_module_return_content_free_evidence_remove_transfer_directory'
emit 'non_actions=no_sudo_no_package_install_no_database_service_container_model_credential_corpus_configuration_state_or_port_forwarding_change_no_candidate_removal'
emit "selected_target=$target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version"

control_path="$work_root/cm-%C"
ssh_args=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto -o "ControlPath=$control_path" -o ControlPersist=900)
[[ -z "$identity_file" ]] || ssh_args+=(-i "$identity_file" -o IdentitiesOnly=yes)
emit 'milestone=authentication;state=waiting_for_operator_if_prompted'
timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$target" >/dev/null 2>&1 || block 'ssh_master_start_failed'
master_started=true
emit 'milestone=authentication;state=pass'
remote_root="/tmp/ishikawa-runtime-candidate-$timestamp-$$"
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" >/dev/null || block 'remote_temporary_directory_not_created'
remote_created=true

emit 'milestone=promotion_payload;state=start'
timeout --foreground 120 scp "${ssh_args[@]}" "$TARGET_HELPER" "$old_manifest" "$new_manifest" "$new_full_manifest" "$target:$remote_root/" >/dev/null \
  || block 'payload_transfer_failed'
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && printf '%s  promote-ishikawa-runtime-candidate\n%s  old-immutable.sha256\n%s  new-immutable.sha256\n%s  new-payload.sha256\n' '$helper_sha256' '$old_manifest_sha256' '$new_manifest_sha256' '$full_manifest_sha256' | sha256sum --check --strict - >/dev/null && chmod 0700 promote-ishikawa-runtime-candidate" >/dev/null \
  || block 'target_payload_verification_failed'
emit 'milestone=promotion_payload;state=pass'

set +e
timeout --foreground 300 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && bash ./promote-ishikawa-runtime-candidate '$expected_hostname' '$expected_os_version' '$remote_root' '$old_manifest_sha256' '$new_manifest_sha256' '$full_manifest_sha256' '$old_module_sha256' '$new_module_sha256' '$remote_root/qualification-result.txt' >/dev/null 2>&1"
remote_code=$?
set -e
emit "remote_execution_exit_code=$remote_code;raw_remote_output_retained=false"
fetched_result="$work_root/qualification-result.txt"
timeout --foreground 60 scp "${ssh_args[@]}" "$target:$remote_root/qualification-result.txt" "$fetched_result" >/dev/null || block 'result_fetch_failed'
output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then
    output_contract=blocked
    continue
  fi
  emit "$line"
done <"$fetched_result"
emit "remote_output_contract=$output_contract"
(( remote_code == 0 )) || block 'remote_promotion_failed'
[[ "$output_contract" == pass ]] || block 'remote_output_contract_failed'
for fact in \
  "target_hostname=$expected_hostname;os_id=ubuntu;os_version=$expected_os_version;architecture=amd64" \
  "module_identity=$new_module_sha256;connection_autocommit=true;atomic_writer_boundary=explicit_transaction" \
  'operator_configuration=preserved;corpus=preserved;application_state=preserved;candidate_retained=true' \
  'database_changed=false;service_changed=false;container_changed=false;model_contact=false;credential_read=false;port_forwarding_changed=false' \
  'ishikawa_runtime_candidate_promotion=pass'; do
  grep -Fqx "$fact" "$fetched_result" || block 'remote_result_contract_failed'
done
grep -Eq "^promotion_action=(promoted_corrected_module|reused_exact_corrected_module);immutable_files=$immutable_file_count;candidate_files=$candidate_file_count$" "$fetched_result" \
  || block 'remote_result_contract_failed'
grep -Eq '^runtime_cache_files=[0-9]+;runtime_cache_classification=generated_cpython312_bytecode$' "$fetched_result" \
  || block 'remote_result_contract_failed'

artifact_path="$ARTIFACT_ROOT/runtime_candidate_promotion_${timestamp}.json"
checksum_path="$artifact_path.sha256"
printf '{"active_module_sha256":"%s","candidate_retained":true,"configuration_preserved":true,"corpus_preserved":true,"database_changed":false,"model_contact":false,"new_archive_sha256":"%s","old_archive_sha256":"%s","package_delta_count":1,"receipt_schema_version":1,"service_changed":false,"state_preserved":true,"target_hostname":"%s"}\n' \
  "$new_module_sha256" "$NEW_ARCHIVE_SHA256" "$OLD_ARCHIVE_SHA256" "$expected_hostname" >"$artifact_path"
artifact_sha256="$(sha256sum "$artifact_path" | awk '{print $1}')"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true
(cd -- "$ARTIFACT_ROOT" && sha256sum --check --strict "$(basename -- "$checksum_path")" >/dev/null) || block 'local_artifact_checksum_failed'
artifact_committed=true
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_checksum=$checksum_path"
emit 'milestone=runtime_candidate_promotion;state=pass'
emit "script_105_runtime_candidate_promotion=pass;local_report=$report_path;next_gate=rerun_first_end_to_end_ishikawa_proof"
