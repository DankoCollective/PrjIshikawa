#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the operator-ingestion control plane against injected local ports.
#   This gate does not contact a target, database, Nomic, or Gemma.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/76_qualify_operator_ingestion_command.sh --run

usage() {
  sed -n '3,10p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Run locally and retain content-free qualification evidence.' \
    '  --validate-only Validate sources and behavior without retaining evidence.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$ISHIKAWA_ROOT/application/python"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly MODULE="$PYTHON_ROOT/ishikawa/operator_ingestion.py"
readonly TESTS="$ISHIKAWA_ROOT/tests/test_operator_ingestion.py"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_operator_ingestion_command.py"
readonly VALIDATION_CONTRACT="$ISHIKAWA_ROOT/docs/VALIDATION_AND_QUARANTINE_CONTRACT.md"
readonly WRITER_CONTRACT="$ISHIKAWA_ROOT/docs/PIPELINE_WRITER_CONTRACT.md"
readonly ACCEPTED_SCRIPT_75_REPORT="$REPO_ROOT/local/reports/ishikawa-configured-live-runtime/configured_live_runtime_20261020T165151Z_OnxFHl.txt"
readonly ACCEPTED_SCRIPT_75_REPORT_SHA256='bc8ec1f4ef5b4221222fbe2ddf837eebf71e0e3fce9bf400f172557896da1980'
readonly ACCEPTED_SCRIPT_75_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/configured-live-runtime/configured_live_runtime_20261020T165151Z.json"
readonly ACCEPTED_SCRIPT_75_ARTIFACT_SHA256='36c3e880092cab03e179814a9efa6b4cb94b85c77778951002745d856d236376'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-operator-ingestion-command"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/operator-ingestion-command"

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'ERROR: unsupported argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'BLOCKED: choose exactly one of --run or --validate-only.\n' >&2
  exit 2
}
for required in awk bash chmod cp date grep mkdir mktemp python3 rm sed sha256sum stat tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'BLOCKED: missing local command: %s\n' "$required" >&2
    exit 2
  }
done
for source in \
  "$TEST_RUNNER" "$MODULE" "$TESTS" "$EVALUATOR" \
  "$VALIDATION_CONTRACT" "$WRITER_CONTRACT" \
  "$ACCEPTED_SCRIPT_75_REPORT" "$ACCEPTED_SCRIPT_75_ARTIFACT"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: a required Script 76 input is missing or unsafe.\n' >&2
    exit 2
  }
done
[[ "$(sha256sum "$ACCEPTED_SCRIPT_75_REPORT" | awk '{print $1}')" == "$ACCEPTED_SCRIPT_75_REPORT_SHA256" ]] || {
  printf 'BLOCKED: accepted Script 75 report identity changed.\n' >&2
  exit 2
}
[[ "$(sha256sum "$ACCEPTED_SCRIPT_75_ARTIFACT" | awk '{print $1}')" == "$ACCEPTED_SCRIPT_75_ARTIFACT_SHA256" ]] || {
  printf 'BLOCKED: accepted Script 75 artifact identity changed.\n' >&2
  exit 2
}
for fact in \
  'configured_live_runtime_qualification=pass' \
  'accepted_database_unchanged=true;accepted_database_rows=0;postgresql_restored_stopped_disabled=true' \
  'credentials_retained=false;raw_request_retained=false;raw_response_retained=false;vectors_retained=false' \
  'script_75_configured_live_runtime=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_SCRIPT_75_REPORT" || {
    printf 'BLOCKED: an accepted Script 75 fact is absent.\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$MODULE" "$TESTS" "$EVALUATOR"

work_root="$(mktemp -d /tmp/ishikawa-script-76.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-76.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  printf 'script_76_operator_ingestion_command=blocked;reason=test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$test_result" | awk '{print $1}')" "$(stat -c '%s' "$test_result")" >&2
  exit 1
}
grep -Fq 'Ran 279 tests' "$test_result" || {
  printf 'script_76_operator_ingestion_command=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_76_operator_ingestion_command=blocked;reason=test_pass_marker_absent\n' >&2
  exit 1
}

temporary_artifact="$work_root/operator-ingestion-command.json"
evaluation_result="$work_root/evaluation.txt"
evaluation_error="$work_root/evaluation-error.txt"
if ! PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B "$EVALUATOR" \
  --output "$temporary_artifact" >"$evaluation_result" 2>"$evaluation_error"; then
  printf 'script_76_operator_ingestion_command=blocked;reason=control_plane_evaluation_failed;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$evaluation_error" | awk '{print $1}')" "$(stat -c '%s' "$evaluation_error")" >&2
  exit 1
fi
for fact in \
  'operator_ingestion_scenarios=4;validate_only=pass;incremental_add=pass;reuse=pass;quarantine=pass' \
  'validate_only_dependencies=producer_0,writer_0;actual_add=producer_1,writer_1' \
  'unchanged_and_quarantine_document_production=0;atomic_writer_boundary=pass' \
  'reports=private_0600;absolute_source_paths_in_terminal=false' \
  'target_contact=false;database_contact=false;model_call=false;credential_read=false' \
  'operator_ingestion_command_qualification=pass'; do
  grep -Fqx "$fact" "$evaluation_result" || {
    printf 'script_76_operator_ingestion_command=blocked;reason=control_plane_contract_mismatch\n' >&2
    exit 1
  }
done

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
module_sha256="$(sha256sum "$MODULE" | awk '{print $1}')"
tests_sha256="$(sha256sum "$TESTS" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
validation_contract_sha256="$(sha256sum "$VALIDATION_CONTRACT" | awk '{print $1}')"
writer_contract_sha256="$(sha256sum "$WRITER_CONTRACT" | awk '{print $1}')"
artifact_sha256="$(sha256sum "$temporary_artifact" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$temporary_artifact")"

if [[ "$validate_only" == true ]]; then
  cat "$evaluation_result"
  printf '%s\n' \
    'purpose=validate_operator_ingestion_command_control_plane' \
    'target_contact=false;network_access=local_test_loopback_only;database_contact=false;model_call=false;credential_read=false' \
    "script_sha256=$script_sha256;module_sha256=$module_sha256;tests_sha256=$tests_sha256;evaluator_sha256=$evaluator_sha256" \
    "validation_contract_sha256=$validation_contract_sha256;writer_contract_sha256=$writer_contract_sha256" \
    "accepted_script_75_report_sha256=$ACCEPTED_SCRIPT_75_REPORT_SHA256;accepted_script_75_artifact_sha256=$ACCEPTED_SCRIPT_75_ARTIFACT_SHA256" \
    "qualification_artifact_sha256=$artifact_sha256;qualification_artifact_bytes=$artifact_bytes" \
    'local_tests=279;failures=0;errors=0' \
    'script_76_operator_ingestion_command_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/operator_ingestion_command_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  printf 'script_76_operator_ingestion_command=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
cp -- "$temporary_artifact" "$artifact_path"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true

report_path="$(mktemp "$REPORT_ROOT/operator_ingestion_command_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=qualify_operator_ingestion_command_control_plane'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;module_sha256=$module_sha256;tests_sha256=$tests_sha256;evaluator_sha256=$evaluator_sha256"
emit "validation_contract_sha256=$validation_contract_sha256;writer_contract_sha256=$writer_contract_sha256"
emit "accepted_script_75_report_sha256=$ACCEPTED_SCRIPT_75_REPORT_SHA256;accepted_script_75_artifact_sha256=$ACCEPTED_SCRIPT_75_ARTIFACT_SHA256"
emit 'authorized_actions=read_checksum_bound_local_evidence_run_local_tests_exercise_operator_ingestion_with_injected_non_networking_ports_retain_content_free_acceptance_evidence'
emit 'non_actions=no_target_contact_no_database_contact_no_model_call_no_credential_read_no_source_document_retention_no_schema_or_package_change'
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$artifact_bytes"
emit "accepted_checksum=$checksum_path;source_content_retained=false;absolute_source_paths_retained=false"
emit 'local_tests=279;failures=0;errors=0'
emit "script_76_operator_ingestion_command=pass;local_report=$report_path;next_gate=connect_operator_ingestion_to_native_producer_and_postgresql"
chmod 0600 "$report_path" 2>/dev/null || true
