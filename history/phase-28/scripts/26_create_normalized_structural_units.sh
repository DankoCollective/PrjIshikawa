#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Create and locally qualify deterministic normalized structural units from
#   the accepted synthetic Poppler capture.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/26_create_normalized_structural_units.sh --run

usage() {
  sed -n '3,9p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run                 Run tests and retain the normalized artifact.' \
    '  --validate-only       Run all checks without retaining an artifact.' \
    '  --artifact-root PATH  Absolute local artifact directory.' \
    '  --report-root PATH    Absolute local content-free report directory.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$ISHIKAWA_ROOT/application/python"
readonly NORMALIZER="$PYTHON_ROOT/ishikawa/normalization.py"
readonly NORMALIZER_CLI="$SCRIPT_DIR/normalize-pdf-extraction.py"
readonly NORMALIZATION_TESTS="$ISHIKAWA_ROOT/tests/normalization_checks.py"
readonly BASE_TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly SOURCE_MANIFEST="$ISHIKAWA_ROOT/tests/fixtures/synthetic_pdf_sources.json"
readonly ACCEPTANCE_TRUTH="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/evaluation/extraction_acceptance_truth.json"
readonly CAPTURE_RECEIPT="$REPO_ROOT/local/reports/ishikawa-pdf-extraction-qualification/pdf_extraction_qualification_20261019T212440Z_xvlGSE.txt"
readonly ACCEPTANCE_RECEIPT="$REPO_ROOT/local/reports/ishikawa-pdf-extraction-qualification/pdf_extraction_local_acceptance_20261019T212922Z.txt"
readonly CAPTURE_ARCHIVE="$REPO_ROOT/local/artifacts/ishikawa/pdf-extraction-qualification/pdf_extraction_observations_20261019T212440Z.tar"
readonly CAPTURE_ARCHIVE_SHA256='072bff5e6d791fd1399f52dde8da8e3be1d53c30d4d7510d6de00ae01e3f6067'
readonly CAPTURE_RECEIPT_SHA256='b5725ccb83f8492b855280974598e49b3a33639d0c3fd8320ef4b23092644186'
readonly ACCEPTANCE_RECEIPT_SHA256='9ba0e112df80b0b56b49fbb068ef75eb03a3f5fd9949c0d3dace4c6f32a34eb5'
readonly SOURCE_MANIFEST_SHA256='456279482e50681c4c07cb41fbdff10f1ca8e9de458df4a99aa725f3ed94fd14'
readonly ACCEPTANCE_TRUTH_SHA256='f83fd0bc8e0a25cd6bad35c5377b72a921205e7dd50565641fb58b229c635b1b'
readonly NORMALIZER_SHA256='f1b23bb7825090935078257907a46675e1b942f7dde955055ebf21037c89ad5f'
readonly NORMALIZER_CLI_SHA256='8e9193492c69bee6a31afe3f7606ec2efd528f79d76feb4189d462e6b3c206ea'
readonly NORMALIZATION_TESTS_SHA256='b8221ab0ba9f92abcc5f0e2763c1a5bbc5d5f6ce1c4ec92c1a44c0ace1fd11c5'
readonly DEFAULT_ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/normalization"
readonly DEFAULT_REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-normalization"

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
  "$NORMALIZER" "$NORMALIZER_CLI" "$NORMALIZATION_TESTS" "$BASE_TEST_RUNNER" \
  "$SOURCE_MANIFEST" "$ACCEPTANCE_TRUTH" "$CAPTURE_RECEIPT" \
  "$ACCEPTANCE_RECEIPT" "$CAPTURE_ARCHIVE"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: required Script 26 input is missing or unsafe.\n' >&2
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
check_sha256 "$CAPTURE_ARCHIVE" "$CAPTURE_ARCHIVE_SHA256" 'accepted capture archive'
check_sha256 "$CAPTURE_RECEIPT" "$CAPTURE_RECEIPT_SHA256" 'target capture receipt'
check_sha256 "$ACCEPTANCE_RECEIPT" "$ACCEPTANCE_RECEIPT_SHA256" 'local acceptance receipt'
check_sha256 "$SOURCE_MANIFEST" "$SOURCE_MANIFEST_SHA256" 'source manifest'
check_sha256 "$ACCEPTANCE_TRUTH" "$ACCEPTANCE_TRUTH_SHA256" 'held-out acceptance truth'
check_sha256 "$NORMALIZER" "$NORMALIZER_SHA256" 'normalizer source'
check_sha256 "$NORMALIZER_CLI" "$NORMALIZER_CLI_SHA256" 'normalizer command source'
check_sha256 "$NORMALIZATION_TESTS" "$NORMALIZATION_TESTS_SHA256" 'normalization tests'

grep -Fxq 'pdf_extraction_qualification=pass;next_gate=implement_normalization_and_structural_units' "$ACCEPTANCE_RECEIPT" || {
  printf 'BLOCKED: accepted extraction routing fact is absent.\n' >&2
  exit 2
}
bash -n "$BASE_TEST_RUNNER"
python3 -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$NORMALIZER" "$NORMALIZER_CLI" "$NORMALIZATION_TESTS"

work_root="$(mktemp -d /tmp/ishikawa-script-26.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-26.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

base_result="$work_root/base-tests.txt"
set +e
bash "$BASE_TEST_RUNNER" >"$base_result" 2>&1
base_code=$?
set -e
if (( base_code != 0 )); then
  cat "$base_result" >&2
  printf 'script_26_normalization=blocked;reason=base_regression\n' >&2
  exit 1
fi
grep -Fq 'Ran 64 tests' "$base_result" || { printf 'script_26_normalization=blocked;reason=base_test_count_mismatch\n' >&2; exit 1; }
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$base_result" || { printf 'script_26_normalization=blocked;reason=base_pass_marker_absent\n' >&2; exit 1; }

normalization_test_result="$work_root/normalization-tests.txt"
set +e
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" \
  python3 "$NORMALIZATION_TESTS" -v >"$normalization_test_result" 2>&1
normalization_test_code=$?
set -e
if (( normalization_test_code != 0 )); then
  cat "$normalization_test_result" >&2
  printf 'script_26_normalization=blocked;reason=normalization_test_failure\n' >&2
  exit 1
fi
grep -Fq 'Ran 13 tests' "$normalization_test_result" || { printf 'script_26_normalization=blocked;reason=normalization_test_count_mismatch\n' >&2; exit 1; }
grep -Fxq 'OK' "$normalization_test_result" || { printf 'script_26_normalization=blocked;reason=normalization_pass_marker_absent\n' >&2; exit 1; }

first_artifact="$work_root/normalized-first.json"
second_artifact="$work_root/normalized-second.json"
first_result="$work_root/normalize-first.txt"
second_result="$work_root/normalize-second.txt"
python3 "$NORMALIZER_CLI" \
  --archive "$CAPTURE_ARCHIVE" \
  --expected-archive-sha256 "$CAPTURE_ARCHIVE_SHA256" \
  --output "$first_artifact" \
  --python-root "$PYTHON_ROOT" \
  --source-manifest "$SOURCE_MANIFEST" >"$first_result"
python3 "$NORMALIZER_CLI" \
  --archive "$CAPTURE_ARCHIVE" \
  --expected-archive-sha256 "$CAPTURE_ARCHIVE_SHA256" \
  --output "$second_artifact" \
  --python-root "$PYTHON_ROOT" \
  --source-manifest "$SOURCE_MANIFEST" >"$second_result"
cmp -s "$first_artifact" "$second_artifact" || { printf 'script_26_normalization=blocked;reason=nondeterministic_artifact\n' >&2; exit 1; }
cmp -s "$first_result" "$second_result" || { printf 'script_26_normalization=blocked;reason=nondeterministic_result\n' >&2; exit 1; }

for fact in \
  'purpose=normalize_pdf_extraction_and_create_structural_units' \
  'documents=6;pages=27;blank_pages=1' \
  'structural_units=230;headings=28;paragraphs=40;list_items=60;definitions=5' \
  'tables=1;form_fields=12;checkbox_groups=4;page_furniture=80' \
  'normalization_set_digest=86a31ba1ce7dea966273576553f09b244e7f3a3f9d4f7757812d04f9551f9e43' \
  'artifact_sha256=736d619ac5a7e10f768bdb8b8f3f117cb52231f8dc2f4d186d52d96c8bd41e28;artifact_bytes=172376' \
  'normalization=pass'; do
  grep -Fxq "$fact" "$first_result" || {
    printf 'script_26_normalization=blocked;reason=normalization_fact_mismatch\n' >&2
    exit 1
  }
done

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_normalization_and_structural_unit_source' \
    'target_contact=false;database_connection=false;model_call=false;retained_artifact=false' \
    "script_sha256=$script_sha256" \
    "normalizer_sha256=$NORMALIZER_SHA256;normalizer_cli_sha256=$NORMALIZER_CLI_SHA256" \
    "normalization_tests_sha256=$NORMALIZATION_TESTS_SHA256" \
    'base_tests=64;normalization_tests=13;failures=0;errors=0' \
    'deterministic_replays=2;artifact_match=true;result_match=true' \
    'script_26_normalization_source=pass'
  exit 0
fi

mkdir -p -- "$artifact_root" "$report_root"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$artifact_root/normalized_structural_units_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  printf 'script_26_normalization=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
cp -- "$first_artifact" "$artifact_path"
artifact_sha256="$(sha256sum "$artifact_path" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$artifact_path")"
[[ "$artifact_sha256" == '736d619ac5a7e10f768bdb8b8f3f117cb52231f8dc2f4d186d52d96c8bd41e28' && "$artifact_bytes" == '172376' ]] || {
  printf 'script_26_normalization=blocked;reason=retained_artifact_identity_mismatch\n' >&2
  exit 1
}
printf '%s  %s\n' "$artifact_sha256" "$(basename "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true

report_path="$(mktemp "$report_root/normalization_${timestamp}_XXXXXX.txt")"
{
  printf '%s\n' \
    'purpose=create_and_qualify_normalized_structural_units' \
    "completed_utc=$timestamp" \
    'target_contact=false;database_connection=false;model_call=false;organizational_content_processed=false' \
    "script_sha256=$script_sha256" \
    "normalizer_sha256=$NORMALIZER_SHA256;normalizer_cli_sha256=$NORMALIZER_CLI_SHA256" \
    "normalization_tests_sha256=$NORMALIZATION_TESTS_SHA256" \
    "source_archive_sha256=$CAPTURE_ARCHIVE_SHA256;source_manifest_sha256=$SOURCE_MANIFEST_SHA256" \
    "acceptance_truth_sha256=$ACCEPTANCE_TRUTH_SHA256" \
    'base_tests=64;normalization_tests=13;failures=0;errors=0' \
    'deterministic_replays=2;artifact_match=true;result_match=true' \
    'documents=6;pages=27;blank_pages=1' \
    'structural_units=230;headings=28;paragraphs=40;list_items=60;definitions=5' \
    'tables=1;form_fields=12;checkbox_groups=4;page_furniture=80' \
    'normalization_set_digest=86a31ba1ce7dea966273576553f09b244e7f3a3f9d4f7757812d04f9551f9e43' \
    "artifact_sha256=$artifact_sha256;artifact_bytes=$artifact_bytes" \
    "artifact=$artifact_path;checksum=$checksum_path" \
    'script_26_normalization=pass;next_gate=structure_aware_chunking_and_metadata'
} | tee "$report_path"
