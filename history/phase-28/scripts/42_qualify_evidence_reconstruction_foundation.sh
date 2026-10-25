#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify deterministic evidence reconstruction against the accepted
#   synthetic chunk artifact without target contact or production token limits.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/42_qualify_evidence_reconstruction_foundation.sh --run

usage() {
  sed -n '3,9p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run          Run the local qualification and retain a content-free report.' \
    '  --validate-only Validate source identities and tests without retaining a report.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$ISHIKAWA_ROOT/application/python"
readonly BASE_TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_evidence_reconstruction.py"
readonly RECONSTRUCTION_SOURCE="$PYTHON_ROOT/ishikawa/reconstruction.py"
readonly RECONSTRUCTION_TESTS="$ISHIKAWA_ROOT/tests/test_reconstruction.py"
readonly CHUNKS="$REPO_ROOT/local/artifacts/ishikawa/retrieval-gap-method-profile/structural_chunk_candidates_20261020T002645Z.json"
readonly CHUNK_SHA256='bc993ca0a417353f0d2313bcb2d1c94a1d526a513253139be71117bf88626bf3'
readonly ACCEPTED_MIGRATION_REPORT="$REPO_ROOT/local/reports/native-postgresql-relationship-override-audit-migration/relationship_override_audit_migration_20261020T014143Z_pEVwvS.txt"
readonly ACCEPTED_MIGRATION_REPORT_SHA256='448f4bc3c124dcc34e66c3429639722a515a2b888b5d2deeba2b49c1eb00a446'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-evidence-reconstruction-foundation"

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
[[ "$run_authorized" != "$validate_only" ]] || { printf 'BLOCKED: choose exactly one of --run or --validate-only.\n' >&2; exit 2; }
for required in awk bash date grep mkdir mktemp python3 rm sha256sum tee tr wc; do
  command -v "$required" >/dev/null 2>&1 || { printf 'BLOCKED: missing local command: %s\n' "$required" >&2; exit 2; }
done
for source in "$BASE_TEST_RUNNER" "$EVALUATOR" "$RECONSTRUCTION_SOURCE" "$RECONSTRUCTION_TESTS" "$CHUNKS" "$ACCEPTED_MIGRATION_REPORT"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || { printf 'BLOCKED: a required reconstruction input is missing or unsafe.\n' >&2; exit 2; }
done
[[ "$(sha256sum "$CHUNKS" | awk '{print $1}')" == "$CHUNK_SHA256" ]] || { printf 'BLOCKED: accepted chunk artifact checksum mismatch.\n' >&2; exit 2; }
[[ "$(sha256sum "$ACCEPTED_MIGRATION_REPORT" | awk '{print $1}')" == "$ACCEPTED_MIGRATION_REPORT_SHA256" ]] || { printf 'BLOCKED: accepted migration report checksum mismatch.\n' >&2; exit 2; }
for fact in \
  'relationship_override_audit_migration=pass' \
  'migration_metadata_row_count=4;corpus_content_row_count=0' \
  'required_fact_contract=pass;pass_markers=1;blocked_markers=0' \
  'cleanup_remote_temporary_files=removed' \
  'cleanup_ssh_master_exit_code=0'; do
  grep -Fxq "$fact" "$ACCEPTED_MIGRATION_REPORT" || { printf 'BLOCKED: accepted migration fact is absent.\n' >&2; exit 2; }
done
bash -n "$BASE_TEST_RUNNER"
python3 -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' "$EVALUATOR" "$RECONSTRUCTION_SOURCE" "$RECONSTRUCTION_TESTS"

work_root="$(mktemp -d /tmp/ishikawa-script-42.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-42.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
bash "$BASE_TEST_RUNNER" >"$test_result" 2>&1 || { cat "$test_result" >&2; printf 'script_42_evidence_reconstruction=blocked;reason=test_regression\n' >&2; exit 1; }
grep -Fq 'Ran 123 tests' "$test_result" || { printf 'script_42_evidence_reconstruction=blocked;reason=test_count_mismatch\n' >&2; exit 1; }
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || { printf 'script_42_evidence_reconstruction=blocked;reason=test_pass_marker_absent\n' >&2; exit 1; }

evaluation_result="$work_root/evaluation.txt"
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 "$EVALUATOR" \
  --chunks "$CHUNKS" --expected-sha256 "$CHUNK_SHA256" >"$evaluation_result"
grep -Fxq 'evidence_reconstruction_foundation=pass' "$evaluation_result" || { cat "$evaluation_result" >&2; printf 'script_42_evidence_reconstruction=blocked;reason=evaluation_failed\n' >&2; exit 1; }
grep -Fxq 'generation_tokenizer_qualification=pending;numeric_budget_calibration=pending' "$evaluation_result" || { printf 'script_42_evidence_reconstruction=blocked;reason=pending_boundary_absent\n' >&2; exit 1; }

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
source_sha256="$(sha256sum "$RECONSTRUCTION_SOURCE" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_evidence_reconstruction_foundation_source' \
    'target_contact=false;database_contact=false;model_call=false;artifact_mutation=false' \
    "script_sha256=$script_sha256;source_sha256=$source_sha256;evaluator_sha256=$evaluator_sha256" \
    "chunk_sha256=$CHUNK_SHA256;accepted_migration_report_sha256=$ACCEPTED_MIGRATION_REPORT_SHA256" \
    'local_tests=123;failures=0;errors=0' \
    'generation_tokenizer_qualification=pending;numeric_budget_calibration=pending' \
    'script_42_evidence_reconstruction_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/evidence_reconstruction_foundation_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=qualify_evidence_reconstruction_foundation_locally'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;source_sha256=$source_sha256;evaluator_sha256=$evaluator_sha256"
emit "chunk_sha256=$CHUNK_SHA256;accepted_migration_report_sha256=$ACCEPTED_MIGRATION_REPORT_SHA256"
emit 'authorized_actions=read_checksum_bound_synthetic_artifact_run_local_tests_retain_content_free_report'
emit 'non_actions=no_target_contact_no_database_contact_no_model_call_no_network_access_no_source_document_read_no_configuration_or_schema_change'
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit 'local_tests=123;failures=0;errors=0'
emit "script_42_evidence_reconstruction=pass;local_report=$report_path;next_gate=qualify_gemma_tokenizer_and_calibrate_context_budget"
