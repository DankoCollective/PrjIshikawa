#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Run the complete local Ishikawa validation and incremental-writer suite.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/23_test_incremental_ingestion_writer.sh
#
# This command does not contact a remote system, connect to PostgreSQL, read
# organizational documents, call a model service, or mutate corpus state.

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly WRITER="$ISHIKAWA_ROOT/application/python/ishikawa/persistence.py"
readonly WRITER_MODELS="$ISHIKAWA_ROOT/application/python/ishikawa/persistence_models.py"
readonly WRITER_TESTS="$ISHIKAWA_ROOT/tests/test_persistence.py"
readonly MIGRATION_0002="$PHASE_ROOT/migrations/0002_align_ingestion_ownership.sql"

for required in bash grep mktemp rm sha256sum tee wc; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'BLOCKED: missing local command: %s\n' "$required" >&2
    exit 2
  }
done
for source in "$TEST_RUNNER" "$WRITER" "$WRITER_MODELS" "$WRITER_TESTS" "$MIGRATION_0002"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: required Script 23 source is missing or unsafe.\n' >&2
    exit 2
  }
done

bash -n "$TEST_RUNNER"
python3 -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$WRITER" "$WRITER_MODELS" "$WRITER_TESTS"

for marker in \
  'with connection.transaction():' \
  "SELECT pg_advisory_xact_lock" \
  '0002_align_ingestion_ownership' \
  'INSERT INTO rag.ingestion_runs' \
  'INSERT INTO rag.document_artifact_sets' \
  'INSERT INTO rag.structural_units' \
  'INSERT INTO rag.chunks' \
  'INSERT INTO rag.citation_anchors' \
  'INSERT INTO rag.chunk_embeddings' \
  'INSERT INTO rag.active_document_versions' \
  "resolution_code='successful_retry'"; do
  grep -Fq "$marker" "$WRITER" || {
    printf 'BLOCKED: required incremental-writer marker is absent.\n' >&2
    exit 2
  }
done

work_root="$(mktemp -d /tmp/ishikawa-script-23.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-23.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

result="$work_root/test-result.txt"
set +e
bash "$TEST_RUNNER" 2>&1 | tee "$result"
test_status=${PIPESTATUS[0]}
set -e
(( test_status == 0 )) || {
  printf 'script_23_incremental_ingestion_writer_test=blocked;reason=test_failure\n' >&2
  exit 1
}

grep -Fq 'Ran 64 tests' "$result" || {
  printf 'script_23_incremental_ingestion_writer_test=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'OK' "$result" || {
  printf 'script_23_incremental_ingestion_writer_test=blocked;reason=unittest_pass_marker_absent\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$result" || {
  printf 'script_23_incremental_ingestion_writer_test=blocked;reason=suite_pass_marker_absent\n' >&2
  exit 1
}

printf '%s\n' \
  'purpose=test_incremental_ingestion_writer_locally' \
  'target_contact=false;postgresql_connection=false;corpus_mutation=false' \
  'validated_behaviors=configuration_and_planning_atomic_writer_quarantine_reuse_retirement_parameterization_schema_guard_and_live_state_guard' \
  "writer_sha256=$(sha256sum "$WRITER" | awk '{print $1}')" \
  "writer_models_sha256=$(sha256sum "$WRITER_MODELS" | awk '{print $1}')" \
  "writer_tests_sha256=$(sha256sum "$WRITER_TESTS" | awk '{print $1}')" \
  "migration_0002_sha256=$(sha256sum "$MIGRATION_0002" | awk '{print $1}')" \
  'test_count=64;failures=0;errors=0' \
  'script_23_incremental_ingestion_writer_test=pass'
