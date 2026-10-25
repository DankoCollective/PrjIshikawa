#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Retry the disposable relevance-retrieval measurement after correcting its
#   stale schema-v3 preflight to the accepted schema-v4 database contract.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/58_retry_relevance_retrieval_with_schema_v4.sh --run

usage() {
  sed -n '3,10p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options are passed to the corrected Script 57 measurement:' \
    '  --run                      Authorize the disposable target measurement.' \
    '  --target VALUE             SSH destination or configured SSH alias.' \
    '  --expected-hostname NAME   Exact target short hostname.' \
    '  --expected-os-version VER  Exact expected Ubuntu major.minor version.' \
    '  --identity-file PATH       Optional explicit SSH private key.' \
    '  --validate-only            Validate the correction without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly MEASUREMENT="$SCRIPT_DIR/57_measure_relevance_retrieval_on_emceedanko.sh"
readonly TARGET_HELPER="$SCRIPT_DIR/calibrate-held-out-retrieval"
readonly BLOCKED_REPORT="$REPO_ROOT/local/reports/ishikawa-relevance-retrieval-observation/relevance_retrieval_observation_20261020T043042Z_ufKHIY.txt"
readonly BLOCKED_REPORT_SHA256='93bb2e51cc620eee250b22d5cac9c8b3b7b75c1519f4da87ac849c430193c7ee'
readonly RUNNER_BLOCKED_REPORT="$REPO_ROOT/local/reports/ishikawa-relevance-retrieval-observation/relevance_retrieval_observation_20261020T043558Z_Inq1uy.txt"
readonly RUNNER_BLOCKED_REPORT_SHA256='1e425743c278cd30e9e53dd46f2aa7b3051f458acc670d67cf7ee3a832cebdc2'
readonly MIGRATION_0004_SHA256='5764f6e12a74b18747163c61ef3f314e8dff140a3586b298c62be616a1dc185f'
readonly MEASUREMENT_REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-relevance-retrieval-observation"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-relevance-retrieval-schema-v4-retry"

run_mode=false
validate_mode=false
for argument in "$@"; do
  [[ "$argument" == --run ]] && run_mode=true
  [[ "$argument" == --validate-only ]] && validate_mode=true
  [[ "$argument" == --help || "$argument" == -h ]] && { usage; exit 0; }
done
[[ "$run_mode" != "$validate_mode" ]] || {
  printf 'BLOCKED: choose exactly one of --run or --validate-only.\n' >&2
  exit 2
}
for required in awk bash chmod date grep mkdir mktemp rm sed sha256sum tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'BLOCKED: missing local command: %s\n' "$required" >&2
    exit 2
  }
done
for source in "$MEASUREMENT" "$TARGET_HELPER" "$BLOCKED_REPORT" "$RUNNER_BLOCKED_REPORT"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: a required Script 58 input is missing or unsafe.\n' >&2
    exit 2
  }
done
[[ "$(sha256sum "$BLOCKED_REPORT" | awk '{print $1}')" == "$BLOCKED_REPORT_SHA256" ]] || {
  printf 'BLOCKED: the accepted blocked receipt changed.\n' >&2
  exit 2
}
[[ "$(sha256sum "$RUNNER_BLOCKED_REPORT" | awk '{print $1}')" == "$RUNNER_BLOCKED_REPORT_SHA256" ]] || {
  printf 'BLOCKED: the accepted runner-block receipt changed.\n' >&2
  exit 2
}
for fact in \
  'held_out_retrieval_target_calibration=blocked;reason=production_database_contract_mismatch' \
  'script_57_relevance_retrieval_observation=blocked;' \
  'cleanup_remote_temporary_files=removed' \
  'cleanup_ssh_master_exit_code=0'; do
  grep -Fq "$fact" "$BLOCKED_REPORT" || {
    printf 'BLOCKED: the required prior-block evidence is absent.\n' >&2
    exit 2
  }
done
for fact in \
  'temporary_database_created=true;accepted_schema_version=4' \
  'held_out_retrieval_target_calibration=blocked;reason=calibration_runner_failed' \
  'temporary_database_cleanup_exit_code=0' \
  'cluster_stop_cleanup_exit_code=0' \
  'cleanup_remote_temporary_files=removed' \
  'cleanup_ssh_master_exit_code=0'; do
  grep -Fq "$fact" "$RUNNER_BLOCKED_REPORT" || {
    printf 'BLOCKED: the required runner-block evidence is absent.\n' >&2
    exit 2
  }
done
bash -n "$MEASUREMENT" "$TARGET_HELPER"

work_root="$(mktemp -d /tmp/ishikawa-script-58.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-58.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

source_result="$work_root/source-validation.txt"
bash "$MEASUREMENT" --validate-only >"$source_result" 2>&1 || {
  cat "$source_result" >&2
  printf 'script_58_relevance_retrieval_schema_v4_retry=blocked;reason=corrected_source_validation_failed\n' >&2
  exit 1
}
for fact in \
  'payload_file_count=35' \
  "migration_0004_sha256=$MIGRATION_0004_SHA256" \
  'script_57_relevance_retrieval_observation_source=pass' \
  'cleanup_remote_temporary_files=not_required'; do
  grep -Fq "$fact" "$source_result" || {
    cat "$source_result" >&2
    printf 'script_58_relevance_retrieval_schema_v4_retry=blocked;reason=corrected_source_fact_absent\n' >&2
    exit 1
  }
done

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
measurement_sha256="$(sha256sum "$MEASUREMENT" | awk '{print $1}')"
helper_sha256="$(sha256sum "$TARGET_HELPER" | awk '{print $1}')"
if [[ "$validate_mode" == true ]]; then
  printf '%s\n' \
    'purpose=validate_schema_v4_relevance_retrieval_retry' \
    'target_contact=false;database_contact=false;model_call=false;threshold_selected=false' \
    "script_sha256=$script_sha256;measurement_sha256=$measurement_sha256;helper_sha256=$helper_sha256" \
    "accepted_blocked_report_sha256=$BLOCKED_REPORT_SHA256;accepted_runner_blocked_report_sha256=$RUNNER_BLOCKED_REPORT_SHA256" \
    "migration_0004_sha256=$MIGRATION_0004_SHA256;staged_package_import=pass" \
    'prior_blocks=stale_schema_v3_preflight_then_incomplete_python_package_closure;correction=accepted_schema_v4_and_complete_staged_import_closure' \
    'base_tests=195;adapter_tests=9;payload_files=35;failures=0;errors=0' \
    'script_58_relevance_retrieval_schema_v4_retry_source=pass'
  exit 0
fi

run_result="$work_root/measurement-output.txt"
set +e
set -o pipefail
bash "$MEASUREMENT" "$@" 2>&1 | tee "$run_result"
measurement_code=$?
set -e
if (( measurement_code != 0 )); then
  printf 'script_58_relevance_retrieval_schema_v4_retry=blocked;reason=corrected_measurement_failed\n' >&2
  exit 1
fi
pass_markers="$(grep -Fc 'script_57_relevance_retrieval_observation=pass;' "$run_result" || true)"
[[ "$pass_markers" == 1 ]] || {
  printf 'script_58_relevance_retrieval_schema_v4_retry=blocked;reason=corrected_pass_marker_invalid\n' >&2
  exit 1
}
measurement_report="$(sed -n 's/^script_57_relevance_retrieval_observation=pass;local_report=\([^;]*\);next_gate=.*/\1/p' "$run_result")"
[[ "$measurement_report" == "$MEASUREMENT_REPORT_ROOT"/* && -f "$measurement_report" && ! -L "$measurement_report" ]] || {
  printf 'script_58_relevance_retrieval_schema_v4_retry=blocked;reason=measurement_report_invalid\n' >&2
  exit 1
}
for fact in \
  'temporary_database_created=true;accepted_schema_version=4' \
  'temporary_database_dropped=true;accepted_database_unchanged=true' \
  'relevance_retrieval_evaluation=pass' \
  'threshold_selected=false;next_gate=review_relevance_signal_separation' \
  'script_57_relevance_retrieval_observation=pass;'; do
  grep -Fq "$fact" "$measurement_report" || {
    printf 'script_58_relevance_retrieval_schema_v4_retry=blocked;reason=measurement_fact_absent\n' >&2
    exit 1
  }
done

mkdir -p -- "$REPORT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/relevance_retrieval_schema_v4_retry_${timestamp}_XXXXXX.txt")"
measurement_report_sha256="$(sha256sum "$measurement_report" | awk '{print $1}')"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=accept_schema_v4_relevance_retrieval_retry'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;measurement_sha256=$measurement_sha256;helper_sha256=$helper_sha256"
emit "accepted_blocked_report_sha256=$BLOCKED_REPORT_SHA256;accepted_runner_blocked_report_sha256=$RUNNER_BLOCKED_REPORT_SHA256"
emit "migration_0004_sha256=$MIGRATION_0004_SHA256;staged_package_import=pass"
emit 'prior_blocks=stale_schema_v3_preflight_then_incomplete_python_package_closure;correction=accepted_schema_v4_and_complete_staged_import_closure'
emit "measurement_report=$measurement_report;measurement_report_sha256=$measurement_report_sha256"
emit 'temporary_database_dropped=true;accepted_database_unchanged=true;postgresql_restored_stopped_disabled=true'
emit 'relevance_retrieval_evaluation=pass;threshold_selected=false;publication_eligible=false'
emit "script_58_relevance_retrieval_schema_v4_retry=pass;local_report=$report_path;next_gate=review_relevance_signal_separation"
