#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Capture the live synthetic-corpus baseline needed to tune Ishikawa retrieval.
#
# Mental model:
#   Bind the accepted documentation gate, validate one neutral helper and one
#   fixed synthetic case set, transfer them through a single SSH connection,
#   query the already-running loopback Retrieval API, return the protected
#   responses and per-case latency, and remove all target-side transfer files.
#   and remove all target-side transfer files. This observes before changing.
#
# Inputs or prerequisites:
#   Clean Script 111 evidence, a ready Ishikawa stack on EmceeDanko, working
#   model port forwarding, and strict SSH host trust. No sudo is required.
#
# Outputs or artifact lane:
#   One content-free local report plus a checksum-bound, synthetic-only baseline
#   artifact containing the responses required for retrieval review.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/112_capture_ishikawa_retrieval_tuning_baseline.sh --run

usage() {
  sed -n '3,24p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run                      Capture the live retrieval baseline.' \
    '  --target VALUE             SSH destination or configured SSH alias.' \
    '  --expected-hostname NAME   Exact target short hostname.' \
    '  --expected-os-version VER  Exact expected Ubuntu major.minor version.' \
    '  --endpoint URL             Loopback Retrieval API chat endpoint.' \
    '  --identity-file PATH       Optional explicit SSH private key.' \
    '  --validate-only            Validate sources without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly BASELINE_HELPER="$SCRIPT_DIR/capture-ishikawa-retrieval-baseline.py"
readonly CASES="$PHASE_ROOT/reference/ishikawa-retrieval-tuning-cases-v1.json"
readonly ACCEPTED_REPORT="$REPO_ROOT/local/reports/ishikawa-product-documentation/product_documentation_20261021T044817Z_iO9MI5.txt"
readonly ACCEPTED_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/product-documentation/product_documentation_qualification_20261021T044817Z.json"
readonly ACCEPTED_CHECKSUM="$ACCEPTED_ARTIFACT.sha256"
readonly ACCEPTED_REPORT_SHA256='de780a70cbf12ab1c6d49cfeb20be53e4b9eeed66d71b9c8ad54cb05e7df497c'
readonly ACCEPTED_ARTIFACT_SHA256='ea948499863f40e3988fa6a808f1b556ce558eadc5a7ab93d49e19ad4262fdbd'
readonly ACCEPTED_CHECKSUM_SHA256='6f0232066454a76b2ec23c5e012c30ead28a5cd5a4e9bcea81e0ad630d220e20'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-retrieval-tuning-baseline"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/retrieval-tuning-baseline"

target="${APPLICATION_HOST_TARGET:-DankoSurface_EmceeDanko}"
expected_hostname="${APPLICATION_HOST_EXPECTED_HOSTNAME:-EmceeDanko}"
expected_os_version="${APPLICATION_HOST_EXPECTED_OS_VERSION:-24.04}"
endpoint="${ISHIKAWA_RETRIEVAL_ENDPOINT:-http://127.0.0.1:1384/v1/chat}"
identity_file="${APPLICATION_HOST_IDENTITY_FILE:-}"
run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --target) target="${2:-}"; shift 2 ;;
    --expected-hostname) expected_hostname="${2:-}"; shift 2 ;;
    --expected-os-version) expected_os_version="${2:-}"; shift 2 ;;
    --endpoint) endpoint="${2:-}"; shift 2 ;;
    --identity-file) identity_file="${2:-}"; shift 2 ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_112_retrieval_tuning_baseline=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_112_retrieval_tuning_baseline=blocked;reason=mode_invalid\n' >&2
  exit 2
}
[[ "$target" =~ ^[A-Za-z0-9_@.:-]+$ ]] || {
  printf 'script_112_retrieval_tuning_baseline=blocked;reason=target_invalid\n' >&2
  exit 2
}
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || {
  printf 'script_112_retrieval_tuning_baseline=blocked;reason=expected_hostname_invalid\n' >&2
  exit 2
}
[[ "$expected_os_version" =~ ^[0-9]{2}\.[0-9]{2}$ ]] || {
  printf 'script_112_retrieval_tuning_baseline=blocked;reason=expected_os_version_invalid\n' >&2
  exit 2
}
[[ "$endpoint" =~ ^http://127\.0\.0\.1:[0-9]{1,5}/v1/chat$ ]] || {
  printf 'script_112_retrieval_tuning_baseline=blocked;reason=endpoint_invalid\n' >&2
  exit 2
}
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] || {
    printf 'script_112_retrieval_tuning_baseline=blocked;reason=identity_file_unsafe\n' >&2
    exit 2
  }
fi

for required in awk bash basename chmod cp date dirname grep mkdir mktemp python3 rm scp sed sha256sum ssh stat tee timeout; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_112_retrieval_tuning_baseline=blocked;reason=local_command_missing\n' >&2
    exit 2
  }
done
readonly -a REQUIRED_FILES=(
  "$BASELINE_HELPER" "$CASES"
  "$ACCEPTED_REPORT" "$ACCEPTED_ARTIFACT" "$ACCEPTED_CHECKSUM"
)
for required_file in "${REQUIRED_FILES[@]}"; do
  [[ -f "$required_file" && ! -L "$required_file" && -r "$required_file" ]] || {
    printf 'script_112_retrieval_tuning_baseline=blocked;reason=required_input_unsafe\n' >&2
    exit 2
  }
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_112_retrieval_tuning_baseline=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}
check_sha256 "$ACCEPTED_REPORT" "$ACCEPTED_REPORT_SHA256" accepted_report
check_sha256 "$ACCEPTED_ARTIFACT" "$ACCEPTED_ARTIFACT_SHA256" accepted_artifact
check_sha256 "$ACCEPTED_CHECKSUM" "$ACCEPTED_CHECKSUM_SHA256" accepted_checksum
(
  cd -- "$(dirname -- "$ACCEPTED_CHECKSUM")"
  sha256sum --check --strict "$(basename -- "$ACCEPTED_CHECKSUM")" >/dev/null
) || {
  printf 'script_112_retrieval_tuning_baseline=blocked;reason=accepted_checksum_failed\n' >&2
  exit 2
}
for accepted_fact in \
  'documentation_files=6;command_contracts=5;configuration_contract=pass;method_contract=pass' \
  'portable_jargon=false;credential_material=false;native_tests=360;failures=0;errors=0' \
  'script_111_product_documentation=pass;'; do
  grep -Fq "$accepted_fact" "$ACCEPTED_REPORT" || {
    printf 'script_112_retrieval_tuning_baseline=blocked;reason=accepted_report_contract_failed\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
  "$BASELINE_HELPER"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$BASELINE_HELPER" --self-test \
  | grep -Fxq 'ishikawa_retrieval_tuning_baseline_self_test=pass' || {
  printf 'script_112_retrieval_tuning_baseline=blocked;reason=helper_self_test_failed\n' >&2
  exit 2
}
PYTHONDONTWRITEBYTECODE=1 python3 -B "$BASELINE_HELPER" \
  --validate-cases --cases "$CASES" \
  | grep -Fxq 'retrieval_tuning_cases=pass;cases=13;synthetic_content_only=true' || {
  printf 'script_112_retrieval_tuning_baseline=blocked;reason=case_set_validation_failed\n' >&2
  exit 2
}
if grep -Eiq 'phase[-_ ]?[0-9]+|Danko|org[_ -]?lab|Agent|repository|Script[[:space:]_-]*[0-9]+' "$BASELINE_HELPER" \
  || grep -Eq '(^|[^[:alnum:]])[GD][0-9]{2}([^[:alnum:]]|$)' "$BASELINE_HELPER"; then
  printf 'script_112_retrieval_tuning_baseline=blocked;reason=target_helper_jargon_found\n' >&2
  exit 2
fi

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
helper_sha256="$(sha256sum "$BASELINE_HELPER" | awk '{print $1}')"
cases_sha256="$(sha256sum "$CASES" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_ishikawa_retrieval_tuning_baseline_source' \
    "script_sha256=$script_sha256;target_helper_sha256=$helper_sha256;case_file_sha256=$cases_sha256" \
    "accepted_script_111_report_sha256=$ACCEPTED_REPORT_SHA256;accepted_script_111_artifact_sha256=$ACCEPTED_ARTIFACT_SHA256" \
    'case_count=13;helper_self_test=pass;case_set_validation=pass;synthetic_content_only=true' \
    'target_contact=false;model_contact=false;database_changed=false;service_changed=false' \
    'script_112_retrieval_tuning_baseline_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" && -d "$ARTIFACT_ROOT" && ! -L "$ARTIFACT_ROOT" ]] || {
  printf 'script_112_retrieval_tuning_baseline=blocked;reason=local_output_directory_unsafe\n' >&2
  exit 1
}
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/retrieval_tuning_baseline_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-script-112.XXXXXX)"
remote_root=''
remote_created=false
master_started=false
artifact_committed=false
artifact_path=''
checksum_path=''
ssh_args=()

emit() {
  printf '%s\n' "$1" | tee -a "$report_path"
}
block() {
  emit "script_112_retrieval_tuning_baseline=blocked;reason=$1;local_report=$report_path"
  exit 1
}
cleanup() {
  local status="$?" remote_cleanup_code=0 master_close_code=0
  trap - EXIT INT TERM
  set +e
  if [[ "$remote_created" == true && "$master_started" == true ]]; then
    timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
      "rm -rf -- '$remote_root' && test ! -e '$remote_root'" >/dev/null 2>&1 || remote_cleanup_code=$?
    if (( remote_cleanup_code == 0 )); then
      emit 'cleanup_remote_temporary_files=removed'
    else
      emit "cleanup_remote_temporary_files=review_required;exit_code=$remote_cleanup_code"
      status=1
    fi
  fi
  if [[ "$master_started" == true ]]; then
    timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1 || master_close_code=$?
    emit "cleanup_ssh_master_exit_code=$master_close_code"
    (( master_close_code == 0 )) || status=1
  fi
  if [[ "$artifact_committed" != true ]]; then
    [[ "$artifact_path" == "$ARTIFACT_ROOT"/retrieval_tuning_baseline_*.json ]] && rm -f -- "$artifact_path"
    [[ "$checksum_path" == "$ARTIFACT_ROOT"/retrieval_tuning_baseline_*.json.sha256 ]] && rm -f -- "$checksum_path"
  fi
  [[ "$work_root" == /tmp/ishikawa-script-112.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  chmod 0600 "$report_path" 2>/dev/null || true
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

emit 'purpose=capture_live_synthetic_retrieval_tuning_baseline'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;target_helper_sha256=$helper_sha256;case_file_sha256=$cases_sha256"
emit "accepted_script_111_report_sha256=$ACCEPTED_REPORT_SHA256;accepted_script_111_artifact_sha256=$ACCEPTED_ARTIFACT_SHA256"
emit "selected_target=$target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version;endpoint=$endpoint"
emit 'authorized_actions=authenticate_transfer_checksum_bound_synthetic_cases_query_ready_loopback_retrieval_api_retain_protected_synthetic_responses_and_latency_return_content_free_report_remove_transfer_directory'
emit 'non_actions=no_sudo_no_stack_start_or_stop_no_configuration_change_no_database_write_no_service_change_no_package_change_no_port_forwarding_change_no_credential_read'
emit 'operator_expectation=ssh_key_passphrase_if_prompted;sudo_prompt=false;estimated_duration_minutes=3-20'
emit 'milestone=authentication;state=waiting_for_operator_if_prompted'

control_path="$work_root/cm-%C"
ssh_args=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto -o "ControlPath=$control_path" -o ControlPersist=1800)
if [[ -n "$identity_file" ]]; then
  ssh_args+=(-i "$identity_file" -o IdentitiesOnly=yes)
fi
timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$target" >/dev/null 2>&1 || block 'ssh_master_start_failed'
master_started=true
emit 'milestone=authentication;state=pass'

remote_root="/tmp/ishikawa-retrieval-baseline-$timestamp-$$"
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" >/dev/null \
  || block 'remote_temporary_directory_not_created'
remote_created=true

emit 'milestone=baseline_payload_transfer;state=start'
timeout --foreground 120 scp "${ssh_args[@]}" "$BASELINE_HELPER" "$CASES" "$target:$remote_root/" >/dev/null \
  || block 'baseline_payload_transfer_failed'
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && printf '%s  %s\n%s  %s\n' '$helper_sha256' '$(basename -- "$BASELINE_HELPER")' '$cases_sha256' '$(basename -- "$CASES")' | sha256sum --check --strict - >/dev/null" >/dev/null \
  || block 'transferred_payload_checksum_failed'
emit 'milestone=baseline_payload_transfer;state=pass;files=2'

emit 'milestone=live_baseline_capture;state=start'
set +e
timeout --foreground 3600 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && umask 077 && PYTHONDONTWRITEBYTECODE=1 python3 -B './$(basename -- "$BASELINE_HELPER")' --capture --endpoint '$endpoint' --cases '$remote_root/$(basename -- "$CASES")' --output '$remote_root/retrieval-baseline.json' --expected-hostname '$expected_hostname' --expected-os-version '$expected_os_version' > qualification-result.txt 2>&1"
remote_code=$?
set -e

fetched_result="$work_root/qualification-result.txt"
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/qualification-result.txt" "$fetched_result" >/dev/null \
  || block 'result_fetch_failed'
output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] \
    || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then
    output_contract=blocked
    continue
  fi
  emit "$line"
done <"$fetched_result"
emit "remote_execution_exit_code=$remote_code;remote_output_contract=$output_contract"
(( remote_code == 0 )) || block 'live_baseline_capture_failed'
[[ "$output_contract" == pass ]] || block 'remote_output_contract_failed'
for fact in \
  "target_hostname=$expected_hostname;os_id=ubuntu;os_version=$expected_os_version;architecture=amd64" \
  'stack_readiness=pass;retrieval_http_status=200;retrieval_status=ready' \
  'raw_synthetic_content_retained=true;credential_values_retained=false;runtime_changed=false' \
  'ishikawa_retrieval_tuning_baseline=pass'; do
  grep -Fxq "$fact" "$fetched_result" || block 'remote_result_contract_failed'
done
grep -Eq '^retrieval_tuning_baseline=pass;cases=13;contract_valid=13;expected_status_matches=[0-9]+;answered=[0-9]+;nonanswered=[0-9]+;sources=[0-9]+;cited_sources=[0-9]+;unused_sources=[0-9]+;required_evidence=[0-9]+;required_evidence_cited=[0-9]+;maximum_elapsed_milliseconds=[0-9]+;total_elapsed_milliseconds=[0-9]+$' "$fetched_result" \
  || block 'baseline_summary_contract_failed'

fetched_artifact="$work_root/retrieval-baseline.json"
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/retrieval-baseline.json" "$fetched_artifact" >/dev/null \
  || block 'baseline_artifact_fetch_failed'
artifact_evaluation="$work_root/artifact-evaluation.txt"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$BASELINE_HELPER" \
  --validate-artifact --artifact "$fetched_artifact" >"$artifact_evaluation" \
  || block 'baseline_artifact_validation_failed'
grep -Eq '^retrieval_tuning_artifact=pass;cases=13;contract_valid=13;expected_status_matches=[0-9]+;answered=[0-9]+;nonanswered=[0-9]+;sources=[0-9]+;cited_sources=[0-9]+;unused_sources=[0-9]+;required_evidence=[0-9]+;required_evidence_cited=[0-9]+;maximum_elapsed_milliseconds=[0-9]+;total_elapsed_milliseconds=[0-9]+$' "$artifact_evaluation" \
  || block 'baseline_artifact_marker_invalid'
while IFS= read -r line; do emit "$line"; done <"$artifact_evaluation"

artifact_sha256="$(sha256sum "$fetched_artifact" | awk '{print $1}')"
artifact_path="$ARTIFACT_ROOT/retrieval_tuning_baseline_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] \
  || block 'artifact_path_exists'
cp -- "$fetched_artifact" "$artifact_path"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true
(
  cd -- "$ARTIFACT_ROOT"
  sha256sum --check --strict "$(basename -- "$checksum_path")" >/dev/null
) || block 'local_artifact_checksum_failed'
artifact_committed=true

emit 'milestone=live_baseline_capture;state=pass;runtime_changed=false;database_changed=false;service_changed=false'
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$(stat -c '%s' "$artifact_path");accepted_checksum=$checksum_path"
emit "script_112_retrieval_tuning_baseline=pass;local_report=$report_path;next_gate=review_baseline_and_freeze_first_retrieval_tuning_correction"
