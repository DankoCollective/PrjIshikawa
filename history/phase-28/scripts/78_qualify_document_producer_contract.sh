#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the concrete changed-document production boundary before its
#   Poppler and Nomic deployment adapters are exercised on the target host.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/78_qualify_document_producer_contract.sh --run

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
readonly MODULE="$PYTHON_ROOT/ishikawa/document_producer.py"
readonly TESTS="$ISHIKAWA_ROOT/tests/test_document_producer.py"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_document_producer_contract.py"
readonly ACCEPTED_SCRIPT_77_REPORT="$REPO_ROOT/local/reports/ishikawa-operator-ingestion-target/operator_ingestion_target_20261020T174913Z_5uPHvn.txt"
readonly ACCEPTED_SCRIPT_77_REPORT_SHA256='7f6b9b4b1cc154a0c0b046124424ec3a12eb95d7a275280ac08371a369700ef4'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-document-producer-contract"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/document-producer-contract"

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
for source in "$TEST_RUNNER" "$MODULE" "$TESTS" "$EVALUATOR" "$ACCEPTED_SCRIPT_77_REPORT"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: a required Script 78 input is missing or unsafe.\n' >&2
    exit 2
  }
done
[[ "$(sha256sum "$ACCEPTED_SCRIPT_77_REPORT" | awk '{print $1}')" == "$ACCEPTED_SCRIPT_77_REPORT_SHA256" ]] || {
  printf 'BLOCKED: accepted Script 77 report identity changed.\n' >&2
  exit 2
}
for fact in \
  'operator_ingestion_target_qualification=pass' \
  'temporary_database_dropped=true;accepted_database_unchanged=true' \
  'cluster_status=down;postgresql_port_5432=free;postgresql_service_active=inactive;postgresql_service_enabled=disabled' \
  'script_77_operator_ingestion_target=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_SCRIPT_77_REPORT" || {
    printf 'BLOCKED: an accepted Script 77 fact is absent.\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$MODULE" "$TESTS" "$EVALUATOR"

work_root="$(mktemp -d /tmp/ishikawa-script-78.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-78.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  printf 'script_78_document_producer_contract=blocked;reason=test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$test_result" | awk '{print $1}')" "$(stat -c '%s' "$test_result")" >&2
  exit 1
}
grep -Fq 'Ran 287 tests' "$test_result" || {
  printf 'script_78_document_producer_contract=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_78_document_producer_contract=blocked;reason=test_pass_marker_absent\n' >&2
  exit 1
}

temporary_artifact="$work_root/document-producer-contract.json"
evaluation_result="$work_root/evaluation.txt"
evaluation_error="$work_root/evaluation-error.txt"
if ! PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B "$EVALUATOR" \
  --output "$temporary_artifact" >"$evaluation_result" 2>"$evaluation_error"; then
  printf 'script_78_document_producer_contract=blocked;reason=producer_evaluation_failed;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$evaluation_error" | awk '{print $1}')" "$(stat -c '%s' "$evaluation_error")" >&2
  exit 1
fi
for fact in \
  'producer_scenarios=3;success=pass;method_profile_rejection=pass;empty_batch_rejection=pass' \
  'changed_documents_only=true;artifact_stage_calls=1;prepared_coverage=exact' \
  'artifact_identity=required;workspace=bounded_0700;cleanup=pass' \
  'retention=after_validation_only;failure_retention=false' \
  'target_contact=false;database_contact=false;model_call=false;credential_read=false' \
  'document_producer_contract_qualification=pass'; do
  grep -Fqx "$fact" "$evaluation_result" || {
    printf 'script_78_document_producer_contract=blocked;reason=evaluation_contract_mismatch\n' >&2
    exit 1
  }
done

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
module_sha256="$(sha256sum "$MODULE" | awk '{print $1}')"
tests_sha256="$(sha256sum "$TESTS" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
artifact_sha256="$(sha256sum "$temporary_artifact" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$temporary_artifact")"

if [[ "$validate_only" == true ]]; then
  cat "$evaluation_result"
  printf '%s\n' \
    'purpose=validate_document_producer_contract' \
    'target_contact=false;network_access=local_test_loopback_only;database_contact=false;model_call=false;credential_read=false' \
    "script_sha256=$script_sha256;module_sha256=$module_sha256;tests_sha256=$tests_sha256;evaluator_sha256=$evaluator_sha256" \
    "accepted_script_77_report_sha256=$ACCEPTED_SCRIPT_77_REPORT_SHA256" \
    "qualification_artifact_sha256=$artifact_sha256;qualification_artifact_bytes=$artifact_bytes" \
    'local_tests=287;failures=0;errors=0' \
    'script_78_document_producer_contract_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/document_producer_contract_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  printf 'script_78_document_producer_contract=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
cp -- "$temporary_artifact" "$artifact_path"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true

report_path="$(mktemp "$REPORT_ROOT/document_producer_contract_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=qualify_document_producer_contract'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;module_sha256=$module_sha256;tests_sha256=$tests_sha256;evaluator_sha256=$evaluator_sha256"
emit "accepted_script_77_report_sha256=$ACCEPTED_SCRIPT_77_REPORT_SHA256"
emit 'authorized_actions=read_checksum_bound_local_evidence_run_local_tests_exercise_document_producer_with_injected_non_networking_stage_retain_content_free_acceptance_evidence'
emit 'non_actions=no_target_contact_no_database_contact_no_model_call_no_credential_read_no_source_document_retention_no_package_or_schema_change'
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$artifact_bytes"
emit "accepted_checksum=$checksum_path;source_content_retained=false;absolute_source_paths_retained=false"
emit 'local_tests=287;failures=0;errors=0'
emit "script_78_document_producer_contract=pass;local_report=$report_path;next_gate=implement_and_qualify_live_poppler_nomic_stage"
chmod 0600 "$report_path" 2>/dev/null || true
