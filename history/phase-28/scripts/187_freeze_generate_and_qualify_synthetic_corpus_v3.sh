#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Bind V13-36 through V13-38, generate the separate 30-document synthetic
#   corpus v3 twice, and qualify its header, footer, extraction, normalization,
#   and chunking contracts without database or model contact.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/187_freeze_generate_and_qualify_synthetic_corpus_v3.sh --run

usage() {
  sed -n '3,12p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Generate and qualify the checksum-bound v3 candidate.' \
    '  --validate-only Validate frozen inputs, syntax, and focused contracts.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly TEST_RUNNER="$PRODUCT_ROOT/scripts/run-local-validation-tests.sh"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly V1_GENERATOR="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/generate_synthetic_corpus.py"
readonly V2_GENERATOR="$PHASE_ROOT/reference/generate_synthetic_corpus_v2.py"
readonly V3_GENERATOR="$PHASE_ROOT/reference/generate_synthetic_corpus_v3.py"
readonly V3_QUALIFIER="$SCRIPT_DIR/qualify_synthetic_corpus_v3.py"
readonly CAPTURE="$SCRIPT_DIR/capture-pdf-extraction-observations.py"
readonly NORMALIZE="$SCRIPT_DIR/normalize-pdf-extraction.py"
readonly CHUNK="$SCRIPT_DIR/create-structural-chunk-candidates.py"
readonly FOOTER_MODULE="$PYTHON_ROOT/ishikawa/document_footer.py"
readonly NORMALIZATION_MODULE="$PYTHON_ROOT/ishikawa/normalization.py"
readonly FOOTER_TEST="$PRODUCT_ROOT/tests/test_document_footer.py"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v3"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v3"

readonly DECISIONS_SHA256='e719b4351d7cb2e0957f36e56d9394deaa360b423ebe14cd786218826b197e6e'
readonly V1_GENERATOR_SHA256='1e17cacd16a9f0792262311816b2952fbd6707e96b5928c6af1139674c54c843'
readonly V2_GENERATOR_SHA256='749d38f40690c0affb3916ad9a5d7b29d614a5bd22fc1497dd003275647b0696'
readonly V3_GENERATOR_SHA256='fe5a0e6ccbeea6508063cc1e371a89be7dc578d24ce9f25482b36ac6aed5ba4a'
readonly V3_QUALIFIER_SHA256='f5d385da4f4cebc27fbd97d9777f35f9e482ace6afd76422ec1ec9a45dae4498'
readonly CAPTURE_SHA256='a303e63d1a2329ddec39d563b5a7bdddea5bd7d720206544744876171a5371e2'
readonly NORMALIZE_SHA256='8e9193492c69bee6a31afe3f7606ec2efd528f79d76feb4189d462e6b3c206ea'
readonly CHUNK_SHA256='2c042acfabe608a5683d212403beac6215d385301562de059dc55bd77ed44a26'
readonly FOOTER_MODULE_SHA256='113350e53490e6984f4f05289be6f5d2bfb463f172f064ba94eee96db8825c58'
readonly NORMALIZATION_MODULE_SHA256='1635eec4bf63b183e9eb6fc12eb0561f38863d055519f0f976ebb24730f6aedd'
readonly FOOTER_TEST_SHA256='ce30090c93db4517f53a65c99e65339cbf4ebbd8988c2d856746cf4209a65170'
readonly EXPECTED_NATIVE_TESTS=442
readonly EXPECTED_HOSTNAME='DankoSurface'
readonly EXPECTED_OS_VERSION='24.04'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      printf 'reason=argument_invalid\n\nSCRIPT RESULT\nscript_187_synthetic_corpus_v3=blocked\n' >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'reason=mode_invalid\n\nSCRIPT RESULT\nscript_187_synthetic_corpus_v3=blocked\n' >&2
  exit 2
}

preflight_block() {
  printf 'reason=%s\n\nSCRIPT RESULT\nscript_187_synthetic_corpus_v3=blocked\n' "$1" >&2
  exit "${2:-2}"
}

for command_name in awk bash cmp date dirname find grep hostname mkdir mktemp \
  mv python3 rm sed sha256sum sort tee wc; do
  command -v "$command_name" >/dev/null 2>&1 \
    || preflight_block "local_command_missing_$command_name"
done

check_file() {
  local path="$1" expected="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] \
    || preflight_block "${label}_unsafe"
  [[ "$(sha256sum "$path" | awk '{print $1}')" == "$expected" ]] \
    || preflight_block "${label}_identity_changed"
}

check_file "$DECISIONS" "$DECISIONS_SHA256" decisions
check_file "$V1_GENERATOR" "$V1_GENERATOR_SHA256" v1_generator
check_file "$V2_GENERATOR" "$V2_GENERATOR_SHA256" v2_generator
check_file "$V3_GENERATOR" "$V3_GENERATOR_SHA256" v3_generator
check_file "$V3_QUALIFIER" "$V3_QUALIFIER_SHA256" v3_qualifier
check_file "$CAPTURE" "$CAPTURE_SHA256" extraction_capture
check_file "$NORMALIZE" "$NORMALIZE_SHA256" normalization_entrypoint
check_file "$CHUNK" "$CHUNK_SHA256" chunk_entrypoint
check_file "$FOOTER_MODULE" "$FOOTER_MODULE_SHA256" footer_module
check_file "$NORMALIZATION_MODULE" "$NORMALIZATION_MODULE_SHA256" normalization_module
check_file "$FOOTER_TEST" "$FOOTER_TEST_SHA256" footer_test
[[ -x "$TEST_RUNNER" ]] || preflight_block test_runner_not_executable

for decision in V13-36 V13-37 V13-38; do
  grep -Eq "^\| \`$decision\` \|.*\| FROZEN \|$" "$DECISIONS" \
    || preflight_block "${decision,,}_freeze_record_invalid" 1
done
grep -Fq 'containing exactly 30 active documents and at least 150 semantic pages' "$DECISIONS" \
  || preflight_block v13_36_scale_contract_invalid 1
grep -Fq 'exclude all footer text from semantic chunks, lexical/vector content' "$DECISIONS" \
  || preflight_block v13_37_footer_contract_invalid 1
grep -Fq 'Do not redesign atomic chunking, structural section/page representatives, RRF lanes, or incremental ingestion' "$DECISIONS" \
  || preflight_block v13_38_architecture_contract_invalid 1

PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$V3_GENERATOR" "$V3_QUALIFIER" "$CAPTURE" "$NORMALIZE" "$CHUNK" \
  "$FOOTER_MODULE" "$NORMALIZATION_MODULE" "$FOOTER_TEST"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c 'import pypdf' \
  || preflight_block pypdf_unavailable

focused_stdout="$(mktemp /tmp/ishikawa-script-187-focused.XXXXXX)"
focused_stderr="${focused_stdout}.stderr"
cleanup_focused() { rm -f -- "$focused_stdout" "$focused_stderr"; }
trap cleanup_focused EXIT
PYTHONPATH="$PYTHON_ROOT" PYTHONDONTWRITEBYTECODE=1 \
  python3 -B -m unittest "$FOOTER_TEST" >"$focused_stdout" 2>"$focused_stderr" \
  || preflight_block focused_footer_tests_failed 1
grep -Eq '^Ran 4 tests in [0-9.]+s$' "$focused_stderr" \
  || preflight_block focused_footer_test_count_invalid 1
cleanup_focused
trap - EXIT

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_synthetic_corpus_v3_generation_and_qualification' \
    "script_sha256=$script_sha256;decisions_sha256=$DECISIONS_SHA256;generator_sha256=$V3_GENERATOR_SHA256" \
    'target_documents=30;target_pages=150;v2_anchors=6;new_documents=24;minimum_departments=10' \
    'footer_scope=every_page;footer_semantic_retrieval=false;chunking_redesign=false;ingestion_redesign=false' \
    'database_contact=false;model_contact=false;credential_read=false;corpus_v1_changed=false;corpus_v2_changed=false' \
    '' \
    'SCRIPT RESULT' \
    'script_187_synthetic_corpus_v3=pass'
  exit 0
fi

umask 077
mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT" || preflight_block local_output_root_creation_failed
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/synthetic_corpus_v3_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-script-187.XXXXXX)"
artifact_path="$ARTIFACT_ROOT/synthetic_corpus_v3_candidate_$timestamp"
failure_reason=''
current_stage='runtime_initialization'
readonly MAIN_BASHPID="$BASHPID"

emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
block() { failure_reason="$1"; exit "${2:-1}"; }
record_unexpected_error() {
  local status="$1"
  if [[ "$BASHPID" == "$MAIN_BASHPID" && -z "$failure_reason" ]]; then
    failure_reason="${current_stage}_unexpected_exit_${status}"
  fi
}
cleanup() {
  local status="$?" result=blocked
  trap - ERR EXIT HUP INT TERM
  set +e
  [[ "$work_root" == /tmp/ishikawa-script-187.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  (( status == 0 )) && result=pass
  if (( status != 0 )) && [[ -z "$failure_reason" ]]; then
    failure_reason="${current_stage}_unexpected_exit_${status}"
  fi
  emit "local_report=$report_path"
  printf '\nSCRIPT RESULT\n' | tee -a "$report_path"
  [[ "$result" == pass ]] || printf 'reason=%s\n' "$failure_reason" | tee -a "$report_path"
  printf 'script_187_synthetic_corpus_v3=%s\n' "$result" | tee -a "$report_path"
  exit "$status"
}
trap 'record_unexpected_error $?' ERR
trap cleanup EXIT
trap 'failure_reason=interrupted_hup; exit 129' HUP
trap 'failure_reason=interrupted_int; exit 130' INT
trap 'failure_reason=interrupted_term; exit 143' TERM

emit 'purpose=freeze_generate_and_qualify_synthetic_corpus_v3'
emit "started_utc=$timestamp;script_sha256=$script_sha256;decisions_sha256=$DECISIONS_SHA256"
emit 'authorized_actions=run_local_tests_generate_fictional_pdfs_twice_capture_poppler_extraction_normalize_chunk_write_local_v3_candidate_and_content_free_report'
emit 'non_actions=no_database_contact_no_model_contact_no_credentials_no_corpus_v1_or_v2_mutation_no_black_corpus_no_retrieval_parameter_change_no_package_or_release_change_no_remote_host_no_service_change'

current_stage=native_regression
"$TEST_RUNNER" >"$work_root/native.stdout" 2>"$work_root/native.stderr" \
  || block native_regression_failed
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$work_root/native.stdout" \
  || block native_regression_marker_absent
grep -Eq "^Ran ${EXPECTED_NATIVE_TESTS} tests in [0-9.]+s$" "$work_root/native.stderr" \
  || block native_regression_count_invalid
emit "milestone=native_regression;state=pass;tests=$EXPECTED_NATIVE_TESTS"

current_stage=corpus_generation
for variant in a b; do
  PYTHONDONTWRITEBYTECODE=1 python3 -B "$V3_GENERATOR" \
    --v1-generator "$V1_GENERATOR" --v2-generator "$V2_GENERATOR" \
    --output-root "$work_root/corpus-$variant" \
    >"$work_root/generate-$variant.stdout" 2>"$work_root/generate-$variant.stderr" \
    || block "corpus_generation_${variant}_failed"
  grep -Fxq 'synthetic_corpus_v3_generation=pass;documents=30;pages=150;v2_anchors=6;new_documents=24;departments=11;relationships=90' \
    "$work_root/generate-$variant.stdout" || block "corpus_generation_${variant}_contract_invalid"
  PYTHONDONTWRITEBYTECODE=1 python3 -B "$V3_QUALIFIER" \
    --corpus-root "$work_root/corpus-$variant" \
    >"$work_root/qualify-$variant.stdout" 2>"$work_root/qualify-$variant.stderr" \
    || block "static_qualification_${variant}_failed"
  grep -Fxq 'synthetic_corpus_v3_qualification=pass;documents=30;pages=150;v2_anchors=6;new_documents=24;departments=11;relationships=90;unique_pages=150;structured_documents=7' \
    "$work_root/qualify-$variant.stdout" || block "static_qualification_${variant}_contract_invalid"
done
mapfile -t generated_files < <(cd "$work_root/corpus-a" && find . -type f -printf '%P\n' | sort)
mapfile -t repeated_files < <(cd "$work_root/corpus-b" && find . -type f -printf '%P\n' | sort)
[[ "${generated_files[*]}" == "${repeated_files[*]}" ]] || block corpus_file_inventory_not_repeatable
for relative in "${generated_files[@]}"; do
  cmp --silent "$work_root/corpus-a/$relative" "$work_root/corpus-b/$relative" \
    || block corpus_bytes_not_repeatable
done
emit 'milestone=corpus_generation;state=pass;documents=30;pages=150;v2_anchors=6;new_documents=24;departments=11;relationships=90;byte_repeatable=true'

current_stage=pdf_extraction
PYTHONDONTWRITEBYTECODE=1 python3 -B "$CAPTURE" \
  --archive "$work_root/extraction.tar" \
  --expected-hostname "$EXPECTED_HOSTNAME" --expected-os-version "$EXPECTED_OS_VERSION" \
  --input-dir "$work_root/corpus-a/source" --output-dir "$work_root/extraction" \
  --source-manifest "$work_root/corpus-a/source_manifest.json" \
  >"$work_root/capture.stdout" 2>"$work_root/capture.stderr" \
  || block pdf_extraction_failed
grep -Fxq 'source_documents=30;source_pages=150;observed_blank_pages=0' "$work_root/capture.stdout" \
  || block pdf_extraction_inventory_invalid
grep -Fxq 'pdf_extraction_capture=pass' "$work_root/capture.stdout" \
  || block pdf_extraction_marker_absent
emit 'milestone=pdf_extraction;state=pass;documents=30;pages=150;blank_pages=0;repeatability=true'

current_stage=normalization
archive_sha256="$(sha256sum "$work_root/extraction.tar" | awk '{print $1}')"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$NORMALIZE" \
  --archive "$work_root/extraction.tar" --expected-archive-sha256 "$archive_sha256" \
  --output "$work_root/normalized.json" --python-root "$PYTHON_ROOT" \
  --source-manifest "$work_root/corpus-a/source_manifest.json" \
  >"$work_root/normalize.stdout" 2>"$work_root/normalize.stderr" \
  || block normalization_failed
grep -Fxq 'normalization=pass' "$work_root/normalize.stdout" || block normalization_marker_absent

current_stage=chunking
normalized_sha256="$(sha256sum "$work_root/normalized.json" | awk '{print $1}')"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$CHUNK" \
  --input "$work_root/normalized.json" --expected-input-sha256 "$normalized_sha256" \
  --output "$work_root/chunks.json" --python-root "$PYTHON_ROOT" \
  >"$work_root/chunk.stdout" 2>"$work_root/chunk.stderr" \
  || block chunking_failed
grep -Fxq 'chunk_candidates=pass' "$work_root/chunk.stdout" || block chunking_marker_absent
PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$work_root/normalized.json" "$work_root/chunks.json" <<'PY'
import json
import pathlib
import sys

normalized = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
chunks = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
documents = normalized["documents"]
assert len(documents) == 30
assert all("document_control_header" in item for item in documents)
assert all("document_control_footer" in item for item in documents)
assert sum(len(item["document_control_footer"]["line_ids"]) for item in documents) == 750
for item in documents:
    assert item["document_control_header"]["fields"]["policy_number"]["value"] == item["document_control_footer"]["policy_number"]
    footer_ids = set(item["document_control_footer"]["line_ids"])
    furniture_ids = {
        span["line_id"]
        for unit in item["units"]
        if unit["kind"] == "page_furniture"
        for span in unit["source_spans"]
    }
    assert footer_ids <= furniture_ids
all_candidates = [candidate for item in chunks["documents"] for candidate in item["candidates"]]
assert len(chunks["documents"]) == 30
assert len(all_candidates) == 943
assert sum(candidate["projection_kind"] == "document_control_metadata" for candidate in all_candidates) == 30
for candidate in all_candidates:
    semantic = "\n".join(str(candidate.get(key, "")) for key in ("content_text", "context_text", "retrieval_text"))
    assert "SEO Policy" not in semantic
    assert "For SEO Use Only" not in semantic
    assert not any(f"Page {page} of 5" in semantic for page in range(1, 6))
PY
emit 'milestone=normalization_and_chunking;state=pass;headers=30;footers=30;footer_lines=750;footer_semantic_leak=false;chunk_candidates=943;metadata_candidates=30'

current_stage=artifact_retention
mkdir -p -- "$work_root/corpus-a/qualification"
mv -- "$work_root/extraction.tar" "$work_root/corpus-a/qualification/extraction.tar"
mv -- "$work_root/normalized.json" "$work_root/corpus-a/qualification/normalized.json"
mv -- "$work_root/chunks.json" "$work_root/corpus-a/qualification/chunks.json"
mv -- "$work_root/capture.stdout" "$work_root/corpus-a/qualification/capture.txt"
mv -- "$work_root/normalize.stdout" "$work_root/corpus-a/qualification/normalize.txt"
mv -- "$work_root/chunk.stdout" "$work_root/corpus-a/qualification/chunk.txt"
(
  cd "$work_root/corpus-a"
  find . -type f ! -name SHA256SUMS -printf '%P\n' | sort | while IFS= read -r relative; do
    printf '%s  %s\n' "$(sha256sum "$relative" | awk '{print $1}')" "$relative"
  done >SHA256SUMS
)
checksum_manifest_sha256="$(sha256sum "$work_root/corpus-a/SHA256SUMS" | awk '{print $1}')"
[[ ! -e "$artifact_path" ]] || block artifact_destination_exists
mv -- "$work_root/corpus-a" "$artifact_path"
emit "artifact_path=$artifact_path;checksum_manifest_sha256=$checksum_manifest_sha256"
emit 'corpus_v1_changed=false;corpus_v2_changed=false;database_contact=false;model_contact=false;retrieval_parameters_changed=false;package_changed=false;release_changed=false'
emit 'next_gate=build_v3_retrieval_truth_and_preingestion_measurement'
current_stage=complete
