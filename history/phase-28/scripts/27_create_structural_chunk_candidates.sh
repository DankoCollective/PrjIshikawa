#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Create and locally qualify deterministic structural chunk candidates and
#   metadata from the accepted Script 26 normalized artifact.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/27_create_structural_chunk_candidates.sh --run

usage() {
  sed -n '3,9p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run                 Run tests and retain the chunk-candidate artifact.' \
    '  --validate-only       Run all checks without retaining an artifact.' \
    '  --artifact-root PATH  Absolute local artifact directory.' \
    '  --report-root PATH    Absolute local content-free report directory.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$ISHIKAWA_ROOT/application/python"
readonly CHUNKER="$PYTHON_ROOT/ishikawa/chunking.py"
readonly CHUNKER_CLI="$SCRIPT_DIR/create-structural-chunk-candidates.py"
readonly CHUNKING_TESTS="$ISHIKAWA_ROOT/tests/chunking_checks.py"
readonly NORMALIZATION_TESTS="$ISHIKAWA_ROOT/tests/normalization_checks.py"
readonly BASE_TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly NORMALIZED_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/normalization/normalized_structural_units_20261019T214207Z.json"
readonly NORMALIZED_SIDECAR="$NORMALIZED_ARTIFACT.sha256"
readonly NORMALIZATION_RECEIPT="$REPO_ROOT/local/reports/ishikawa-normalization/normalization_20261019T214207Z_Qcn1ok.txt"
readonly NORMALIZED_SHA256='736d619ac5a7e10f768bdb8b8f3f117cb52231f8dc2f4d186d52d96c8bd41e28'
readonly NORMALIZED_SIDECAR_SHA256='ea56a45c16c5977322e6fdb5aa773a72214c54a3bb8b9a5032c82daa70d53db1'
readonly NORMALIZATION_RECEIPT_SHA256='3f2391cebef59f62a31a1433bcdf1d679593e7b844fda62545ada79b8b1e9fa4'
readonly CHUNKER_SHA256='d942351c52d00b31b69c491c4c0142dff4157a49cbbb1dbd58040b538674a87b'
readonly CHUNKER_CLI_SHA256='2c042acfabe608a5683d212403beac6215d385301562de059dc55bd77ed44a26'
readonly CHUNKING_TESTS_SHA256='fc855119be0653e6ed5e238e00f806d8ee584c9e4ca7867da49f4a344055de3f'
readonly NORMALIZATION_TESTS_SHA256='b8221ab0ba9f92abcc5f0e2763c1a5bbc5d5f6ce1c4ec92c1a44c0ace1fd11c5'
readonly BASE_TEST_RUNNER_SHA256='092b2cb8e5254d1ca2b6e71a496bf76743004134848e249d5d7b9f37d9d62eb7'
readonly DEFAULT_ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/chunking"
readonly DEFAULT_REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-chunking"

run_authorized=false
validate_only=false
artifact_root="$DEFAULT_ARTIFACT_ROOT"
report_root="$DEFAULT_REPORT_ROOT"
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --artifact-root) artifact_root="${2:-}"; shift 2 ;;
    --report-root) report_root="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'ERROR: unsupported argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'BLOCKED: choose exactly one of --run or --validate-only.\n' >&2
  exit 2
}
for destination in "$artifact_root" "$report_root"; do
  [[ "$destination" == /* && ! -L "$destination" ]] || {
    printf 'BLOCKED: output roots must be absolute and not symlinks.\n' >&2
    exit 2
  }
done
for required in awk bash basename cat chmod cmp cp date grep mkdir mktemp python3 rm sed sha256sum stat tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'BLOCKED: missing local command: %s\n' "$required" >&2
    exit 2
  }
done
for source in \
  "$CHUNKER" "$CHUNKER_CLI" "$CHUNKING_TESTS" "$NORMALIZATION_TESTS" \
  "$BASE_TEST_RUNNER" "$NORMALIZED_ARTIFACT" "$NORMALIZED_SIDECAR" \
  "$NORMALIZATION_RECEIPT"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: required Script 27 input is missing or unsafe.\n' >&2
    exit 2
  }
done

check_sha256() {
  local path="$1" expected="$2" label="$3"
  [[ "$(sha256sum "$path" | awk '{print $1}')" == "$expected" ]] || {
    printf 'BLOCKED: %s checksum mismatch.\n' "$label" >&2
    exit 2
  }
}
check_sha256 "$NORMALIZED_ARTIFACT" "$NORMALIZED_SHA256" 'normalized artifact'
check_sha256 "$NORMALIZED_SIDECAR" "$NORMALIZED_SIDECAR_SHA256" 'normalized sidecar'
check_sha256 "$NORMALIZATION_RECEIPT" "$NORMALIZATION_RECEIPT_SHA256" 'normalization receipt'
check_sha256 "$CHUNKER" "$CHUNKER_SHA256" 'chunker source'
check_sha256 "$CHUNKER_CLI" "$CHUNKER_CLI_SHA256" 'chunker command source'
check_sha256 "$CHUNKING_TESTS" "$CHUNKING_TESTS_SHA256" 'chunking tests'
check_sha256 "$NORMALIZATION_TESTS" "$NORMALIZATION_TESTS_SHA256" 'normalization tests'
check_sha256 "$BASE_TEST_RUNNER" "$BASE_TEST_RUNNER_SHA256" 'base test runner'

grep -Fxq 'script_26_normalization=pass;next_gate=structure_aware_chunking_and_metadata' "$NORMALIZATION_RECEIPT" || {
  printf 'BLOCKED: accepted Script 26 routing fact is absent.\n' >&2
  exit 2
}
(
  cd -- "$(dirname -- "$NORMALIZED_ARTIFACT")"
  sha256sum -c -- "$(basename -- "$NORMALIZED_SIDECAR")" >/dev/null
)
bash -n "$BASE_TEST_RUNNER"
python3 -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$CHUNKER" "$CHUNKER_CLI" "$CHUNKING_TESTS" "$NORMALIZATION_TESTS"

work_root="$(mktemp -d /tmp/ishikawa-script-27.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-27.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

run_test_gate() {
  local result_path="$1" expected_count="$2" label="$3"
  shift 3
  set +e
  "$@" >"$result_path" 2>&1
  local status=$?
  set -e
  if (( status != 0 )); then
    cat "$result_path" >&2
    printf 'script_27_chunking=blocked;reason=%s_test_failure\n' "$label" >&2
    exit 1
  fi
  grep -Fq "Ran $expected_count tests" "$result_path" || {
    printf 'script_27_chunking=blocked;reason=%s_test_count_mismatch\n' "$label" >&2
    exit 1
  }
  grep -Fxq 'OK' "$result_path" || {
    printf 'script_27_chunking=blocked;reason=%s_pass_marker_absent\n' "$label" >&2
    exit 1
  }
}

base_result="$work_root/base-tests.txt"
set +e
bash "$BASE_TEST_RUNNER" >"$base_result" 2>&1
base_code=$?
set -e
if (( base_code != 0 )); then
  cat "$base_result" >&2
  printf 'script_27_chunking=blocked;reason=base_regression\n' >&2
  exit 1
fi
grep -Fq 'Ran 64 tests' "$base_result" || { printf 'script_27_chunking=blocked;reason=base_test_count_mismatch\n' >&2; exit 1; }
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$base_result" || { printf 'script_27_chunking=blocked;reason=base_pass_marker_absent\n' >&2; exit 1; }

run_test_gate "$work_root/normalization-tests.txt" 13 normalization \
  env PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 "$NORMALIZATION_TESTS" -v
run_test_gate "$work_root/chunking-tests.txt" 12 chunking \
  env PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 "$CHUNKING_TESTS" -v

first_artifact="$work_root/chunks-first.json"
second_artifact="$work_root/chunks-second.json"
first_result="$work_root/chunks-first.txt"
second_result="$work_root/chunks-second.txt"
python3 "$CHUNKER_CLI" \
  --input "$NORMALIZED_ARTIFACT" \
  --expected-input-sha256 "$NORMALIZED_SHA256" \
  --output "$first_artifact" \
  --python-root "$PYTHON_ROOT" >"$first_result"
python3 "$CHUNKER_CLI" \
  --input "$NORMALIZED_ARTIFACT" \
  --expected-input-sha256 "$NORMALIZED_SHA256" \
  --output "$second_artifact" \
  --python-root "$PYTHON_ROOT" >"$second_result"
cmp -s "$first_artifact" "$second_artifact" || { printf 'script_27_chunking=blocked;reason=nondeterministic_artifact\n' >&2; exit 1; }
cmp -s "$first_result" "$second_result" || { printf 'script_27_chunking=blocked;reason=nondeterministic_result\n' >&2; exit 1; }

for fact in \
  'purpose=create_structure_aware_chunk_candidates_and_metadata' \
  'documents=6;chunk_candidates=125;body_overlap_units=0' \
  'paragraphs=40;list_items=60;definitions=5' \
  'table_contexts=1;table_rows=3;form_fields=12;checkbox_groups=4' \
  'method_profile_id=13fd11355c7eee3b35faadea8e14c5df0787eb70578129377c836e55dff303e4' \
  'chunk_candidate_set_digest=348488b14d697eaca5a27042827f53abcd85b5852ec933baabeb6e5843c4a17a' \
  'artifact_sha256=0b351ef579ff134a5fb1fb5f37843d5461a100f1fc2d803e278a9b20d3126548;artifact_bytes=277544' \
  'token_measurement=pending_authoritative_nomic_measurement;publication_eligible=false' \
  'chunk_candidates=pass'; do
  grep -Fxq "$fact" "$first_result" || {
    printf 'script_27_chunking=blocked;reason=chunking_fact_mismatch\n' >&2
    exit 1
  }
done

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_structure_aware_chunk_candidate_source' \
    'target_contact=false;database_connection=false;model_call=false;retained_artifact=false' \
    "script_sha256=$script_sha256" \
    "chunker_sha256=$CHUNKER_SHA256;chunker_cli_sha256=$CHUNKER_CLI_SHA256" \
    "chunking_tests_sha256=$CHUNKING_TESTS_SHA256" \
    'base_tests=64;normalization_tests=13;chunking_tests=12;failures=0;errors=0' \
    'deterministic_replays=2;artifact_match=true;result_match=true' \
    'script_27_chunking_source=pass'
  exit 0
fi

mkdir -p -- "$artifact_root" "$report_root"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$artifact_root/structural_chunk_candidates_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  printf 'script_27_chunking=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
cp -- "$first_artifact" "$artifact_path"
artifact_sha256="$(sha256sum "$artifact_path" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$artifact_path")"
[[ "$artifact_sha256" == '0b351ef579ff134a5fb1fb5f37843d5461a100f1fc2d803e278a9b20d3126548' && "$artifact_bytes" == '277544' ]] || {
  printf 'script_27_chunking=blocked;reason=retained_artifact_identity_mismatch\n' >&2
  exit 1
}
printf '%s  %s\n' "$artifact_sha256" "$(basename "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true

report_path="$(mktemp "$report_root/chunking_${timestamp}_XXXXXX.txt")"
{
  printf '%s\n' \
    'purpose=create_and_qualify_structural_chunk_candidates_and_metadata' \
    "completed_utc=$timestamp" \
    'target_contact=false;database_connection=false;model_call=false;organizational_content_processed=false' \
    "script_sha256=$script_sha256" \
    "chunker_sha256=$CHUNKER_SHA256;chunker_cli_sha256=$CHUNKER_CLI_SHA256" \
    "chunking_tests_sha256=$CHUNKING_TESTS_SHA256" \
    "normalized_artifact_sha256=$NORMALIZED_SHA256;normalization_receipt_sha256=$NORMALIZATION_RECEIPT_SHA256" \
    'base_tests=64;normalization_tests=13;chunking_tests=12;failures=0;errors=0' \
    'deterministic_replays=2;artifact_match=true;result_match=true' \
    'documents=6;chunk_candidates=125;body_overlap_units=0' \
    'paragraphs=40;list_items=60;definitions=5' \
    'table_contexts=1;table_rows=3;form_fields=12;checkbox_groups=4' \
    'method_profile_id=13fd11355c7eee3b35faadea8e14c5df0787eb70578129377c836e55dff303e4' \
    'chunk_candidate_set_digest=348488b14d697eaca5a27042827f53abcd85b5852ec933baabeb6e5843c4a17a' \
    'token_measurement=pending_authoritative_nomic_measurement;publication_eligible=false' \
    "artifact_sha256=$artifact_sha256;artifact_bytes=$artifact_bytes" \
    "artifact=$artifact_path;checksum=$checksum_path" \
    'script_27_chunking=pass;next_gate=nomic_token_measurement_and_embedding'
} | tee "$report_path"
