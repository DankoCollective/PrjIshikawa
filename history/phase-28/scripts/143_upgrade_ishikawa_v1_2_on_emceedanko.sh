#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Promote the accepted Ishikawa v1.2 application onto EmceeDanko after the
#   operator has stopped the existing managed stack.
#
# Mental model:
#   Reverify the accepted release and Coding Standard receipt, authenticate
#   once, transfer only the release and neutral upgrade helper, preserve the
#   existing operator configuration/corpus/state, activate v1.2 with rollback,
#   return bounded evidence, and remove the transfer directory.
#
# Inputs or prerequisites:
#   Clean Script 140 acceptance evidence, strict SSH host trust, and a clean
#   `ishikawa-stack stop` on the target. Model forwarding is not required.
#
# Outputs or artifact lane:
#   Active v1.2 application and preserved pre-v1.2 rollback tree on the target,
#   plus local content-free evidence. PostgreSQL and all services remain
#   stopped. The database schema and accepted corpus rows are unchanged.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/143_upgrade_ishikawa_v1_2_on_emceedanko.sh --run

usage() {
  sed -n '3,24p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run                      Upgrade the selected stopped target.' \
    '  --target VALUE             SSH destination or configured SSH alias.' \
    '  --expected-hostname NAME   Exact target short hostname.' \
    '  --expected-os-version VER  Exact expected Ubuntu major.minor version.' \
    '  --identity-file PATH       Optional explicit SSH private key.' \
    '  --validate-only            Validate sources without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly TARGET_HELPER="$SCRIPT_DIR/install-ishikawa-v1.2-upgrade"
readonly CODING_STANDARD="$REPO_ROOT/CODING_STANDARD.md"
readonly CODING_STANDARD_EVALUATOR="$SCRIPT_DIR/evaluate_consolidated_build_coding_standard.py"
readonly ACCEPTED_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.2-release/ishikawa_v1_2_acceptance_20261021T223500Z_LX9xEA.txt"
readonly ACCEPTED_RECEIPT="$REPO_ROOT/local/artifacts/ishikawa/v1.2-release/ishikawa_v1_2_acceptance_20261021T223500Z.json"
readonly ACCEPTED_RECEIPT_CHECKSUM="$ACCEPTED_RECEIPT.sha256"
readonly ACCEPTED_ARCHIVE="$REPO_ROOT/local/artifacts/ishikawa/v1.2-deployment-package/ishikawa-v1.2-deployment-package-6d4a2c169574f23b.tar.gz"
readonly ACCEPTED_ARCHIVE_CHECKSUM="$ACCEPTED_ARCHIVE.sha256"
readonly ACCEPTED_COMPLIANCE="$REPO_ROOT/local/artifacts/ishikawa/v1.2-deployment-package/v1_2_deployment_coding_standard_6d4a2c169574f23b.json"
readonly ACCEPTED_COMPLIANCE_CHECKSUM="$ACCEPTED_COMPLIANCE.sha256"

readonly ACCEPTED_REPORT_SHA256='def560368c5858709a5462cfc641ab4e03b6e4414eef82338628a7be93510693'
readonly ACCEPTED_RECEIPT_SHA256='bfe9c792d261a12ed7d12bf6c01c5fefcedc92864a5474557d190a0628132b9f'
readonly ACCEPTED_RECEIPT_CHECKSUM_SHA256='5d16272a7821e554a212d06c5514ef957f563b3f7f23f5ce6458063e3bbaba37'
readonly ACCEPTED_ARCHIVE_SHA256='6d4a2c169574f23b6c707a9641f936c16d2948e170ff46a77fa246cf2e3d680d'
readonly ACCEPTED_ARCHIVE_CHECKSUM_SHA256='33d1bdf58eeddfece922a3f8dd63873c7f98437940a03b9e4d9d75e3a7cabeb9'
readonly ACCEPTED_COMPLIANCE_SHA256='50250ccbeff6ddaff2fcb19d4c61573b3098ec8a64cf9811b31b5a32798e83bd'
readonly ACCEPTED_COMPLIANCE_CHECKSUM_SHA256='4dbdca57dacca7f53e86e20d1ec0e250994e5353865901599c741af73894294a'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.2-upgrade"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v1.2-upgrade"

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
    *) printf 'script_143_v1_2_upgrade=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_143_v1_2_upgrade=blocked;reason=mode_invalid\n' >&2
  exit 2
}
[[ "$target" =~ ^[A-Za-z0-9_@.:-]+$ ]] || { printf 'script_143_v1_2_upgrade=blocked;reason=target_invalid\n' >&2; exit 2; }
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || { printf 'script_143_v1_2_upgrade=blocked;reason=expected_hostname_invalid\n' >&2; exit 2; }
[[ "$expected_os_version" =~ ^[0-9]{2}\.[0-9]{2}$ ]] || { printf 'script_143_v1_2_upgrade=blocked;reason=expected_os_version_invalid\n' >&2; exit 2; }
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] || {
    printf 'script_143_v1_2_upgrade=blocked;reason=identity_file_unsafe\n' >&2
    exit 2
  }
fi

for required in awk bash basename date dirname grep mkdir mktemp python3 rm scp sed sha256sum ssh stat tar tee timeout; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_143_v1_2_upgrade=blocked;reason=local_command_missing;command=%s\n' "$required" >&2
    exit 2
  }
done
readonly -a ACCEPTED_INPUTS=(
  "$TARGET_HELPER" "$CODING_STANDARD" "$CODING_STANDARD_EVALUATOR"
  "$ACCEPTED_REPORT" "$ACCEPTED_RECEIPT" "$ACCEPTED_RECEIPT_CHECKSUM"
  "$ACCEPTED_ARCHIVE" "$ACCEPTED_ARCHIVE_CHECKSUM"
  "$ACCEPTED_COMPLIANCE" "$ACCEPTED_COMPLIANCE_CHECKSUM"
)
for accepted_input in "${ACCEPTED_INPUTS[@]}"; do
  [[ -f "$accepted_input" && ! -L "$accepted_input" && -r "$accepted_input" ]] || {
    printf 'script_143_v1_2_upgrade=blocked;reason=accepted_input_missing\n' >&2
    exit 2
  }
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_143_v1_2_upgrade=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}
check_sha256 "$ACCEPTED_REPORT" "$ACCEPTED_REPORT_SHA256" accepted_report
check_sha256 "$ACCEPTED_RECEIPT" "$ACCEPTED_RECEIPT_SHA256" accepted_receipt
check_sha256 "$ACCEPTED_RECEIPT_CHECKSUM" "$ACCEPTED_RECEIPT_CHECKSUM_SHA256" accepted_receipt_checksum
check_sha256 "$ACCEPTED_ARCHIVE" "$ACCEPTED_ARCHIVE_SHA256" accepted_archive
check_sha256 "$ACCEPTED_ARCHIVE_CHECKSUM" "$ACCEPTED_ARCHIVE_CHECKSUM_SHA256" accepted_archive_checksum
check_sha256 "$ACCEPTED_COMPLIANCE" "$ACCEPTED_COMPLIANCE_SHA256" accepted_compliance
check_sha256 "$ACCEPTED_COMPLIANCE_CHECKSUM" "$ACCEPTED_COMPLIANCE_CHECKSUM_SHA256" accepted_compliance_checksum
for checksum_file in "$ACCEPTED_RECEIPT_CHECKSUM" "$ACCEPTED_ARCHIVE_CHECKSUM" "$ACCEPTED_COMPLIANCE_CHECKSUM"; do
  (cd -- "$(dirname -- "$checksum_file")" && sha256sum --check --strict "$(basename -- "$checksum_file")" >/dev/null) || {
    printf 'script_143_v1_2_upgrade=blocked;reason=accepted_checksum_failed\n' >&2
    exit 2
  }
done
for accepted_fact in \
  'purpose=accept_exact_ishikawa_v1_2_deployment_package' \
  'host_qualification=pass' \
  'package_files=111;application_files=104;database_files=4;historical_mutation_files=0' \
  'coding_standard_compliant=true' \
  'script_140_v1_2_acceptance=pass;'; do
  grep -Fq "$accepted_fact" "$ACCEPTED_REPORT" || {
    printf 'script_143_v1_2_upgrade=blocked;reason=accepted_report_contract_failed\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}" "$TARGET_HELPER"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
  "$CODING_STANDARD_EVALUATOR"
if grep -Eiq 'phase[-_ ]?[0-9]+|Danko|org[_ -]?lab|Agent|repository|Script[[:space:]_-]*[0-9]+' "$TARGET_HELPER" \
  || grep -Eq '(^|[^[:alnum:]])[GD][0-9]{2}([^[:alnum:]]|$)' "$TARGET_HELPER"; then
  printf 'script_143_v1_2_upgrade=blocked;reason=target_helper_jargon_found\n' >&2
  exit 2
fi

work_root="$(mktemp -d /tmp/ishikawa-script-143.XXXXXX)"
mkdir -p -- "$work_root/extracted"
tar -xzf "$ACCEPTED_ARCHIVE" -C "$work_root/extracted"
bundle_root="$work_root/extracted/ishikawa-v1.2-deployment-package"
[[ -d "$bundle_root" && ! -L "$bundle_root" ]] || {
  printf 'script_143_v1_2_upgrade=blocked;reason=local_bundle_invalid\n' >&2
  exit 1
}
bash "$bundle_root/verify-ishikawa-v1.2" >/dev/null || {
  printf 'script_143_v1_2_upgrade=blocked;reason=local_bundle_verification_failed\n' >&2
  exit 1
}
current_compliance="$work_root/current-coding-standard-compliance.json"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$CODING_STANDARD_EVALUATOR" \
  --bundle-root "$bundle_root" \
  --standard "$CODING_STANDARD" \
  --output "$current_compliance" >/dev/null || {
  printf 'script_143_v1_2_upgrade=blocked;reason=current_coding_standard_noncompliance\n' >&2
  exit 1
}
current_compliance_sha256="$(sha256sum "$current_compliance" | awk '{print $1}')"
[[ "$current_compliance_sha256" == "$ACCEPTED_COMPLIANCE_SHA256" ]] || {
  printf 'script_143_v1_2_upgrade=blocked;reason=coding_standard_receipt_identity_changed\n' >&2
  exit 1
}
helper_sha256="$(sha256sum "$TARGET_HELPER" | awk '{print $1}')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  rm -rf -- "$work_root"
  printf '%s\n' \
    'purpose=validate_ishikawa_v1_2_upgrade_source' \
    "script_sha256=$script_sha256;target_helper_sha256=$helper_sha256" \
    "accepted_archive_sha256=$ACCEPTED_ARCHIVE_SHA256;accepted_receipt_sha256=$ACCEPTED_RECEIPT_SHA256" \
    "coding_standard_receipt_sha256=$current_compliance_sha256;coding_standard_compliant=true" \
    'package_files=111;historical_mutation_files=0;target_contact=false;application_changed=false;database_changed=false;service_changed=false' \
    'script_143_v1_2_upgrade_source=pass'
  exit 0
fi

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
    [[ "$artifact_path" == "$ARTIFACT_ROOT"/v1_2_upgrade_*.json ]] && rm -f -- "$artifact_path"
    [[ "$checksum_path" == "$ARTIFACT_ROOT"/v1_2_upgrade_*.json.sha256 ]] && rm -f -- "$checksum_path"
  fi
  [[ "$work_root" == /tmp/ishikawa-script-143.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/v1_2_upgrade_${timestamp}_XXXXXX.txt")"
remote_root="/tmp/ishikawa-v1.2-upgrade-$timestamp-$$"
emit '[VERIFY] purpose=upgrade_accepted_ishikawa_v1_2_application'
emit "[VERIFY] accepted_archive_sha256=$ACCEPTED_ARCHIVE_SHA256;accepted_receipt_sha256=$ACCEPTED_RECEIPT_SHA256"
emit "[VERIFY] coding_standard_receipt_sha256=$current_compliance_sha256;coding_standard_compliant=true"
emit '[VERIFY] state=pass;database_schema_change=false;service_start=false'
emit "[TRANSFER] target=$target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version;state=waiting_for_operator_if_prompted"

control_path="$work_root/ssh-control"
ssh_args=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto -o "ControlPath=$control_path" -o ControlPersist=900)
if [[ -n "$identity_file" ]]; then ssh_args+=(-i "$identity_file" -o IdentitiesOnly=yes); fi
timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$target" >/dev/null 2>&1 || {
  emit '[TRANSFER] state=blocked;reason=ssh_master_start_failed'
  exit 1
}
master_started=true
emit '[TRANSFER] authentication=pass'

timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" >/dev/null || {
  emit '[TRANSFER] state=blocked;reason=remote_temporary_directory_not_created'
  exit 1
}
remote_created=true
timeout --foreground 180 scp "${ssh_args[@]}" "$ACCEPTED_ARCHIVE" "$TARGET_HELPER" "$target:$remote_root/" >/dev/null || {
  emit '[TRANSFER] state=blocked;reason=payload_transfer_failed'
  exit 1
}
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && printf '%s  %s\n%s  %s\n' '$ACCEPTED_ARCHIVE_SHA256' '$(basename -- "$ACCEPTED_ARCHIVE")' '$helper_sha256' '$(basename -- "$TARGET_HELPER")' | sha256sum --check --strict - >/dev/null" >/dev/null || {
  emit '[TRANSFER] state=blocked;reason=transferred_payload_checksum_failed'
  exit 1
}
emit '[TRANSFER] state=pass'

emit '[UPGRADE] state=start;services_expected=stopped'
set +e
timeout --foreground 600 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && bash './$(basename -- "$TARGET_HELPER")' '$expected_hostname' '$expected_os_version' '$remote_root/$(basename -- "$ACCEPTED_ARCHIVE")' '$ACCEPTED_ARCHIVE_SHA256' '$remote_root/upgrade-result.txt'" \
  >/dev/null 2>&1
remote_code=$?
set -e
emit "[UPGRADE] remote_execution_exit_code=$remote_code;raw_remote_output_retained=false"

fetched_result="$work_root/upgrade-result.txt"
timeout --foreground 60 scp "${ssh_args[@]}" "$target:$remote_root/upgrade-result.txt" "$fetched_result" >/dev/null || {
  emit '[UPGRADE] state=blocked;reason=result_fetch_failed'
  exit 1
}
output_contract=pass
while IFS= read -r result_line; do
  if (( ${#result_line} > 2048 )) || [[ "$result_line" == *$'\t'* ]] || \
    ! [[ "$result_line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then
    output_contract=blocked
    continue
  fi
  emit "[UPGRADE] $result_line"
done <"$fetched_result"
(( remote_code == 0 )) || { emit '[UPGRADE] state=blocked;reason=remote_upgrade_failed'; exit 1; }
[[ "$output_contract" == pass ]] || { emit '[UPGRADE] state=blocked;reason=remote_output_contract_failed'; exit 1; }
for required_fact in \
  "target_hostname=$expected_hostname;os_id=ubuntu;os_version=$expected_os_version;architecture=amd64" \
  "release_version=v1.2;archive_sha256=$ACCEPTED_ARCHIVE_SHA256;package_checksums=pass" \
  'operator_configuration=preserved;corpus=preserved;state=preserved;' \
  'schema_version=4;database_changed=false;services_started=false;boot_enabled=false' \
  'user_units=3;unit_identity=exact;model_contact=false;credential_read=false;port_forwarding_changed=false' \
  'ishikawa_v1_2_upgrade=pass'; do
  grep -Fq "$required_fact" "$fetched_result" || {
    emit '[UPGRADE] state=blocked;reason=remote_result_contract_failed'
    exit 1
  }
done
upgrade_action="$(sed -n 's/^upgrade_action=\([a-z_][a-z_]*\);.*/\1/p' "$fetched_result")"
[[ "$upgrade_action" == promoted_new || "$upgrade_action" == reused_exact ]] || {
  emit '[UPGRADE] state=blocked;reason=upgrade_action_invalid'
  exit 1
}

artifact_path="$ARTIFACT_ROOT/v1_2_upgrade_${timestamp}.json"
checksum_path="$artifact_path.sha256"
printf '{"accepted_archive_sha256":"%s","accepted_receipt_sha256":"%s","coding_standard_compliant":true,"database_changed":false,"operator_configuration_preserved":true,"release_name":"Ishikawa v1.2","rollback_tree_preserved":true,"schema_version":4,"services_started":false,"target_architecture":"amd64","target_hostname":"%s","target_os_version":"%s","upgrade_action":"%s"}\n' \
  "$ACCEPTED_ARCHIVE_SHA256" "$ACCEPTED_RECEIPT_SHA256" "$expected_hostname" "$expected_os_version" "$upgrade_action" >"$artifact_path"
artifact_sha256="$(sha256sum "$artifact_path" | awk '{print $1}')"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
(cd -- "$ARTIFACT_ROOT" && sha256sum --check --strict "$(basename -- "$checksum_path")" >/dev/null) || {
  emit '[UPGRADE] state=blocked;reason=local_artifact_checksum_failed'
  exit 1
}
artifact_committed=true
emit '[UPGRADE] state=pass;release=v1.2;services=stopped;rollback=preserved'
emit "[SUMMARY] artifact=$artifact_path;artifact_sha256=$artifact_sha256;report=$report_path"
emit '[SUMMARY] script_143_v1_2_upgrade=pass;next_gate=start_and_test_ishikawa_v1_2'
