#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the frozen KISS relationship contract locally against separate
#   held-out synthetic truth. This script performs no database or remote work.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/39_qualify_relationship_contract.sh --run

usage() {
  sed -n '3,9p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run             Run the local relationship gate and retain a report.' \
    '  --validate-only   Validate code and evidence without retaining a report.' \
    '  --report-root P   Absolute local content-free report directory.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$ISHIKAWA_ROOT/application/python"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly QUALIFIER="$ISHIKAWA_ROOT/scripts/qualify-relationships.py"
readonly REGISTRY="$ISHIKAWA_ROOT/config/templates/relationship_types.yaml"
readonly MANIFEST="$ISHIKAWA_ROOT/tests/fixtures/pipeline_writer/ingestion_manifest.yaml"
readonly SOURCE_ROOT="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/anderson-upload"
readonly CHUNKS="$REPO_ROOT/local/artifacts/ishikawa/retrieval-gap-method-profile/structural_chunk_candidates_20261020T002645Z.json"
readonly TRUTH="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/evaluation/ground_truth.json"
readonly CHUNKS_SHA256='bc993ca0a417353f0d2313bcb2d1c94a1d526a513253139be71117bf88626bf3'
readonly TRUTH_SHA256='85e4bcf8e4d07bd786c8d2566957a4e75555084e5f3b11e58dd96af9af7c2ec8'
readonly DEFAULT_REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-relationship-contract"

run_authorized=false
validate_only=false
report_root="$DEFAULT_REPORT_ROOT"
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --report-root) report_root="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'ERROR: unsupported argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'BLOCKED: choose exactly one of --run or --validate-only.\n' >&2
  exit 2
}
[[ "$report_root" == /* && ! -L "$report_root" ]] || {
  printf 'BLOCKED: report root must be absolute and not a symlink.\n' >&2
  exit 2
}
for required in bash cat chmod date grep mkdir mktemp python3 rm sed sha256sum tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'BLOCKED: missing local command: %s\n' "$required" >&2
    exit 2
  }
done
for source in "$TEST_RUNNER" "$QUALIFIER" "$REGISTRY" "$MANIFEST" "$CHUNKS" "$TRUTH"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: a required Script 39 input is missing or unsafe.\n' >&2
    exit 2
  }
done
[[ -d "$SOURCE_ROOT" && ! -L "$SOURCE_ROOT" ]] || {
  printf 'BLOCKED: the synthetic source root is missing or unsafe.\n' >&2
  exit 2
}
[[ "$(sha256sum "$CHUNKS" | sed 's/ .*//')" == "$CHUNKS_SHA256" ]] || {
  printf 'BLOCKED: accepted chunk artifact checksum mismatch.\n' >&2
  exit 2
}
[[ "$(sha256sum "$TRUTH" | sed 's/ .*//')" == "$TRUTH_SHA256" ]] || {
  printf 'BLOCKED: held-out relationship truth checksum mismatch.\n' >&2
  exit 2
}

work_root="$(mktemp -d /tmp/ishikawa-script-39.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-39.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
test_result="$work_root/tests.txt"
qualification_result="$work_root/qualification.txt"

bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  cat "$test_result" >&2
  printf 'script_39_relationship_contract=blocked;reason=local_regression\n' >&2
  exit 1
}
grep -Fq 'Ran 106 tests' "$test_result" || {
  printf 'script_39_relationship_contract=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}

PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 "$QUALIFIER" \
  --registry "$REGISTRY" \
  --manifest "$MANIFEST" \
  --source-root "$SOURCE_ROOT" \
  --chunks "$CHUNKS" \
  --chunks-sha256 "$CHUNKS_SHA256" \
  --truth "$TRUTH" \
  --truth-sha256 "$TRUTH_SHA256" \
  >"$qualification_result"
grep -Fxq 'relationship_contract_qualification=pass' "$qualification_result" || {
  printf 'script_39_relationship_contract=blocked;reason=relationship_qualification\n' >&2
  exit 1
}
grep -Fxq 'unresolved_references=0' "$qualification_result" || {
  printf 'script_39_relationship_contract=blocked;reason=unresolved_reference\n' >&2
  exit 1
}
grep -Fxq 'held_out_relationships=5' "$qualification_result" || {
  printf 'script_39_relationship_contract=blocked;reason=truth_inventory\n' >&2
  exit 1
}
grep -Fxq 'held_out_relationships_covered=5' "$qualification_result" || {
  printf 'script_39_relationship_contract=blocked;reason=truth_coverage\n' >&2
  exit 1
}
grep -Fxq 'held_out_traversals_covered=5' "$qualification_result" || {
  printf 'script_39_relationship_contract=blocked;reason=traversal_coverage\n' >&2
  exit 1
}

if [[ "$validate_only" == true ]]; then
  cat "$qualification_result"
  printf 'script_39_relationship_contract_source=pass;tests=106;retained_report=false\n'
  exit 0
fi

umask 077
mkdir -p -- "$report_root"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_root/relationship_contract_${timestamp}_XXXXXX.txt")"
{
  printf 'purpose=qualify_deterministic_relationship_contract\n'
  printf 'started_utc=%s\n' "$timestamp"
  printf 'authorized_actions=read_local_synthetic_artifacts_hash_local_sources_validate_registry_run_local_tests_compare_separate_held_out_truth_write_content_free_local_report\n'
  printf 'non_actions=no_remote_access_no_model_call_no_database_access_no_package_change_no_secret_processing_no_source_text_output_no_operator_relationship_manifest\n'
  printf 'local_tests=pass;tests=106\n'
  cat "$qualification_result"
  printf 'script_39_relationship_contract=pass;next_gate=persist_and_query_relationships_in_disposable_target_database\n'
} | tee "$report_path"
chmod 600 "$report_path"
printf 'local_report=%s\n' "$report_path"
