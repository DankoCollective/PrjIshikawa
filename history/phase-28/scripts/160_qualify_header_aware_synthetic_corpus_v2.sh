#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the frozen Ishikawa v1.3 document-control header contract and build
#   a separate deterministic synthetic corpus v2 candidate.
#
# Mental model:
#   Bind Script 159's clean diagnostic; generate corpus v2 twice without
#   touching corpus v1; prove byte-for-byte repeatability; run Poppler twice;
#   normalize the first-page masthead and six-field table; prove semantic-body exclusion, metadata
#   propagation, and department-aware routing contracts; then retain one
#   checksum-bound candidate for later embedding and retrieval evaluation.
#
# Inputs or prerequisites:
#   The accepted synthetic corpus v1 generator, the Script 159 report and
#   artifact, local Poppler 24.02.0, pypdf, Python 3.12, and the current
#   Ishikawa source. Ishikawa may be stopped or running; no port is used.
#
# Outputs or artifact lane:
#   One synthetic-only candidate directory under
#   local/artifacts/ishikawa/synthetic-corpus-v2 and one content-free report
#   under local/reports/ishikawa-synthetic-corpus-v2. No database, model,
#   service, remote host, credential, package, accepted corpus, or release is
#   read or changed.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/160_qualify_header_aware_synthetic_corpus_v2.sh --run

usage() {
  sed -n '3,32p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Run local tests, generate, extract, and retain corpus v2.' \
    '  --validate-only Validate bound inputs, syntax, and focused contracts only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly TEST_ROOT="$PRODUCT_ROOT/tests"
readonly TEST_RUNNER="$PRODUCT_ROOT/scripts/run-local-validation-tests.sh"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly V1_GENERATOR="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/generate_synthetic_corpus.py"
readonly GENERATOR="$PHASE_ROOT/reference/generate_synthetic_corpus_v2.py"
readonly CAPTURE="$SCRIPT_DIR/capture-pdf-extraction-observations.py"
readonly QUALIFIER="$SCRIPT_DIR/qualify_synthetic_corpus_v2.py"
readonly SCRIPT_159_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.3-answer-quality-trace/v1_3_incident_retrieval_quality_20261022T162807Z_c5lZJJ.txt"
readonly SCRIPT_159_REPORT_SHA256='7177f8039e17e4512f5c5bbff22657657f7fac38e42a9b8cfc5dd7d97deaa7ed'
readonly SCRIPT_159_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/v1.3-answer-quality-trace/v1_3_incident_retrieval_quality_20261022T162807Z_E1VOx9.json"
readonly SCRIPT_159_ARTIFACT_SHA256='e305dc67b15692edd93cba8e21152159f74e8bb3871ec6def0ac00bad8497e60'
readonly V1_GENERATOR_SHA256='1e17cacd16a9f0792262311816b2952fbd6707e96b5928c6af1139674c54c843'
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2"
readonly EXPECTED_NATIVE_TESTS=407
readonly EXPECTED_PIPELINE_TESTS=43
readonly EXPECTED_HOST='DankoSurface'
readonly EXPECTED_OS_VERSION='24.04'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      printf 'script_160_header_aware_synthetic_corpus_v2=blocked;reason=argument_invalid\n' >&2
      usage >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_160_header_aware_synthetic_corpus_v2=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for command_name in bash cmp date diff dirname dpkg-query find grep hostname mkdir \
  mktemp mv pdfinfo pdftotext python3 rm sed sha256sum sort stat tee; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'script_160_header_aware_synthetic_corpus_v2=blocked;reason=local_command_missing;command=%s\n' \
      "$command_name" >&2
    exit 2
  }
done

readonly -a REQUIRED_PATHS=(
  "$TEST_RUNNER" "$DECISIONS" "$V1_GENERATOR" "$GENERATOR" "$CAPTURE" "$QUALIFIER"
  "$SCRIPT_159_REPORT" "$SCRIPT_159_ARTIFACT"
  "$PYTHON_ROOT/ishikawa/document_control.py"
  "$PYTHON_ROOT/ishikawa/normalization.py"
  "$PYTHON_ROOT/ishikawa/chunking.py"
  "$PYTHON_ROOT/ishikawa/artifact_adapter.py"
  "$PYTHON_ROOT/ishikawa/query_routing.py"
  "$TEST_ROOT/test_document_control.py"
  "$TEST_ROOT/test_query_routing.py"
)
for required_path in "${REQUIRED_PATHS[@]}"; do
  [[ -f "$required_path" && ! -L "$required_path" && -r "$required_path" ]] || {
    printf 'script_160_header_aware_synthetic_corpus_v2=blocked;reason=required_input_unsafe\n' >&2
    exit 2
  }
done

[[ "$(sha256sum "$SCRIPT_159_REPORT" | sed 's/[[:space:]].*$//')" == "$SCRIPT_159_REPORT_SHA256" ]] || {
  printf 'script_160_header_aware_synthetic_corpus_v2=blocked;reason=script_159_report_identity_mismatch\n' >&2
  exit 1
}
[[ "$(sha256sum "$SCRIPT_159_ARTIFACT" | sed 's/[[:space:]].*$//')" == "$SCRIPT_159_ARTIFACT_SHA256" ]] || {
  printf 'script_160_header_aware_synthetic_corpus_v2=blocked;reason=script_159_artifact_identity_mismatch\n' >&2
  exit 1
}
grep -Fxq 'script_159_v1_3_incident_retrieval_quality=pass;next_gate=review_rank_and_sufficiency_evidence' \
  "$SCRIPT_159_REPORT" || {
  printf 'script_160_header_aware_synthetic_corpus_v2=blocked;reason=script_159_not_clean_pass\n' >&2
  exit 1
}
[[ "$(sha256sum "$V1_GENERATOR" | sed 's/[[:space:]].*$//')" == "$V1_GENERATOR_SHA256" ]] || {
  printf 'script_160_header_aware_synthetic_corpus_v2=blocked;reason=accepted_v1_generator_identity_mismatch\n' >&2
  exit 1
}

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER"
for python_source in "$GENERATOR" "$CAPTURE" "$QUALIFIER" \
  "$PYTHON_ROOT/ishikawa/document_control.py" \
  "$PYTHON_ROOT/ishikawa/normalization.py" \
  "$PYTHON_ROOT/ishikawa/chunking.py" \
  "$PYTHON_ROOT/ishikawa/artifact_adapter.py" \
  "$PYTHON_ROOT/ishikawa/query_routing.py"; do
  PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
    'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
    "$python_source"
done
grep -Fq '| `V13-22` ' "$DECISIONS"
grep -Fq '| `V13-23` ' "$DECISIONS"
grep -Fq '| `V13-24` ' "$DECISIONS"

focused_output="$({
  PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B -m unittest \
    "$TEST_ROOT/test_document_control.py" "$TEST_ROOT/test_query_routing.py"
} 2>&1)" || {
  printf '%s\n' "$focused_output" >&2
  printf 'script_160_header_aware_synthetic_corpus_v2=blocked;reason=focused_contract_tests_failed\n' >&2
  exit 1
}
grep -Fq 'Ran 15 tests' <<<"$focused_output" || {
  printf 'script_160_header_aware_synthetic_corpus_v2=blocked;reason=focused_test_count_mismatch\n' >&2
  exit 1
}

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | sed 's/[[:space:]].*$//')"
decision_sha256="$(sha256sum "$DECISIONS" | sed 's/[[:space:]].*$//')"
generator_sha256="$(sha256sum "$GENERATOR" | sed 's/[[:space:]].*$//')"
qualifier_sha256="$(sha256sum "$QUALIFIER" | sed 's/[[:space:]].*$//')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_header_aware_synthetic_corpus_v2' \
    "script_sha256=$script_sha256;decision_sha256=$decision_sha256" \
    "generator_sha256=$generator_sha256;qualifier_sha256=$qualifier_sha256" \
    'script_159_clean_pass=bound;accepted_corpus_v1=immutable;focused_tests=15' \
    'database_contact=false;model_contact=false;credential_read=false;service_changed=false;corpus_v1_changed=false;package_changed=false' \
    'script_160_header_aware_synthetic_corpus_v2=pass'
  exit 0
fi

report_path=''
work_root=''
artifact_path=''
failure_recorded=false

emit() {
  if [[ -n "$report_path" ]]; then
    printf '%s\n' "$1" | tee -a "$report_path"
  else
    printf '%s\n' "$1"
  fi
}

block() {
  failure_recorded=true
  emit "script_160_header_aware_synthetic_corpus_v2=blocked;reason=$1"
  exit 1
}

cleanup() {
  local initial_status="$?"
  trap - EXIT HUP INT TERM
  set +e
  if (( initial_status != 0 )) && [[ "$failure_recorded" != true ]]; then
    emit "script_160_header_aware_synthetic_corpus_v2=blocked;reason=unexpected_failure;exit_code=$initial_status"
  fi
  if [[ -n "$work_root" && "$work_root" == /tmp/ishikawa-synthetic-corpus-v2.* ]]; then
    rm -rf -- "$work_root"
  fi
  if [[ -n "$report_path" && -f "$report_path" ]]; then
    printf 'local_report=%s;local_report_sha256=%s\n' \
      "$report_path" "$(sha256sum "$report_path" | sed 's/[[:space:]].*$//')"
  fi
  exit "$initial_status"
}
trap cleanup EXIT HUP INT TERM

umask 077
mkdir -p -- "$ARTIFACT_ROOT" "$REPORT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/header_aware_synthetic_corpus_v2_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-synthetic-corpus-v2.XXXXXX)"
artifact_path="$ARTIFACT_ROOT/synthetic_corpus_v2_candidate_$timestamp"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" ]] || block artifact_path_exists

emit 'purpose=qualify_header_aware_synthetic_corpus_v2'
emit "started_utc=$timestamp;script_sha256=$script_sha256;decision_sha256=$decision_sha256"
emit "generator_sha256=$generator_sha256;qualifier_sha256=$qualifier_sha256"
emit "script_159_report_sha256=$SCRIPT_159_REPORT_SHA256;script_159_artifact_sha256=$SCRIPT_159_ARTIFACT_SHA256"
emit 'authorized_actions=run_local_tests_generate_fictional_pdf_corpus_twice_run_local_poppler_normalize_chunk_write_synthetic_candidate_and_content_free_report'
emit 'non_actions=no_database_contact_no_model_contact_no_credential_read_no_service_change_no_remote_contact_no_corpus_v1_change_no_package_change_no_accepted_release_change_no_black_corpus_access'

[[ "$(hostname -s)" == "$EXPECTED_HOST" ]] || block local_host_identity_mismatch
[[ "$(dpkg-query -W -f='${Version}' poppler-utils)" == '24.02.0-1ubuntu9.10' ]] \
  || block poppler_package_identity_mismatch
[[ "$(pdfinfo -v 2>&1 | sed -n '1s/.* //p')" == '24.02.0' ]] \
  || block pdfinfo_identity_mismatch
[[ "$(pdftotext -v 2>&1 | sed -n '1s/.* //p')" == '24.02.0' ]] \
  || block pdftotext_identity_mismatch
emit 'milestone=bound_inputs;state=pass;script_159=pass;corpus_v1=immutable;poppler=24.02.0'

native_output="$work_root/native-tests.txt"
emit 'milestone=native_tests;state=start'
set +e
bash "$TEST_RUNNER" >"$native_output" 2>&1
native_status=$?
set -e
(( native_status == 0 )) || block native_tests_failed
grep -Fq "Ran $EXPECTED_NATIVE_TESTS tests" "$native_output" || block native_test_count_mismatch
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$native_output" || block native_test_marker_absent
emit "milestone=native_tests;state=pass;tests=$EXPECTED_NATIVE_TESTS"

pipeline_output="$work_root/pipeline-tests.txt"
emit 'milestone=pipeline_tests;state=start'
set +e
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B -m unittest \
  "$TEST_ROOT/chunking_checks.py" \
  "$TEST_ROOT/normalization_checks.py" \
  "$TEST_ROOT/artifact_adapter_checks.py" \
  "$TEST_ROOT/embedding_qualification_checks.py" \
  >"$pipeline_output" 2>&1
pipeline_status=$?
set -e
(( pipeline_status == 0 )) || block pipeline_tests_failed
grep -Fq "Ran $EXPECTED_PIPELINE_TESTS tests" "$pipeline_output" \
  || block pipeline_test_count_mismatch
emit "milestone=pipeline_tests;state=pass;tests=$EXPECTED_PIPELINE_TESTS"

corpus_a="$work_root/corpus-a"
corpus_b="$work_root/corpus-b"
emit 'milestone=corpus_generation;state=start;repetitions=2'
python3 -B "$GENERATOR" --v1-generator "$V1_GENERATOR" --output-root "$corpus_a" \
  >"$work_root/generator-a.txt" 2>&1 || block corpus_generation_first_failed
python3 -B "$GENERATOR" --v1-generator "$V1_GENERATOR" --output-root "$corpus_b" \
  >"$work_root/generator-b.txt" 2>&1 || block corpus_generation_repeat_failed
grep -Fxq 'synthetic_corpus_v2_generation=pass;documents=6;pages=27;departments=4;mastheads=6;header_fields=6' \
  "$work_root/generator-a.txt" || block corpus_generation_marker_absent
diff -u \
  <(cd "$corpus_a" && find . -type f -print | LC_ALL=C sort) \
  <(cd "$corpus_b" && find . -type f -print | LC_ALL=C sort) \
  >/dev/null || block corpus_file_inventory_not_repeatable
while IFS= read -r relative_path; do
  cmp --silent "$corpus_a/$relative_path" "$corpus_b/$relative_path" \
    || block corpus_bytes_not_repeatable
done < <(cd "$corpus_a" && find . -type f -printf '%P\n' | LC_ALL=C sort)
emit 'milestone=corpus_generation;state=pass;documents=6;pages=27;departments=4;byte_repeatable=true'

capture_root="$work_root/extraction"
capture_archive="$work_root/extraction.tar"
emit 'milestone=pdf_extraction;state=start;repetitions=2'
python3 -B "$CAPTURE" \
  --archive "$capture_archive" \
  --expected-hostname "$EXPECTED_HOST" \
  --expected-os-version "$EXPECTED_OS_VERSION" \
  --input-dir "$corpus_a/source" \
  --output-dir "$capture_root" \
  --source-manifest "$corpus_a/source_manifest.json" \
  >"$work_root/capture.txt" 2>&1 || block pdf_extraction_failed
grep -Fxq 'pdf_extraction_capture=pass' "$work_root/capture.txt" || block pdf_extraction_marker_absent
grep -Fxq 'source_documents=6;source_pages=27;observed_blank_pages=0' "$work_root/capture.txt" \
  || block pdf_extraction_inventory_mismatch
emit 'milestone=pdf_extraction;state=pass;documents=6;pages=27;repeatable=true'

mkdir -p "$corpus_a/qualification"
qualifier_output="$corpus_a/qualification/result.txt"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$QUALIFIER" \
  --python-root "$PYTHON_ROOT" \
  --archive "$capture_archive" \
  --source-manifest "$corpus_a/source_manifest.json" \
  --truth "$corpus_a/evaluation/header_acceptance_truth.json" \
  --normalized-output "$corpus_a/qualification/normalized.json" \
  --chunks-output "$corpus_a/qualification/chunks.json" \
  >"$qualifier_output" 2>&1 || block header_aware_qualification_failed
grep -Fq 'header_aware_corpus_v2_qualification=pass;documents=6;departments=4;candidates=' \
  "$qualifier_output" || block header_aware_qualification_marker_absent
mv -- "$capture_archive" "$corpus_a/qualification/extraction.tar"
(
  cd "$corpus_a"
  find . -type f ! -name SHA256SUMS -printf '%P\n' | LC_ALL=C sort | while IFS= read -r relative_path; do
    printf '%s  %s\n' "$(sha256sum "$relative_path" | sed 's/[[:space:]].*$//')" "$relative_path"
  done >SHA256SUMS
)
checksum_manifest_sha256="$(sha256sum "$corpus_a/SHA256SUMS" | sed 's/[[:space:]].*$//')"
mv -- "$corpus_a" "$artifact_path"
emit "milestone=header_aware_qualification;state=pass;documents=6;departments=4;department_label_variants=3"
emit "artifact_path=$artifact_path;checksum_manifest_sha256=$checksum_manifest_sha256"
emit 'corpus_v1_changed=false;database_contact=false;model_contact=false;service_changed=false;package_changed=false'
emit 'script_160_header_aware_synthetic_corpus_v2=pass;next_gate=embed_and_measure_corpus_v2_retrieval_without_ingestion'
