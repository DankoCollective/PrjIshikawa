#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Rebuild and qualify the corrected synthetic corpus v2 candidate after the
#   first pre-ingestion measurement exposed header-text duplication and a
#   displaced first semantic page.
#
# Mental model:
#   Bind Script 161's intact not-met observation; preserve corpus v1; generate
#   corpus v2 twice; prove the masthead shares page 1 with semantic content;
#   extract twice; normalize and chunk twice; prove one searchable metadata
#   representative per document, structured metadata filters on every body
#   candidate, and no repeated header boilerplate in body retrieval text.
#
# Boundaries:
#   Local synthetic files only. No database, model, credential, service,
#   remote host, accepted release, package, corpus-v1, or black-corpus access.
#   The retained output is still a pre-ingestion candidate.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/162_rebuild_corrected_synthetic_corpus_v2.sh --run

usage() {
  sed -n '3,28p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Rebuild and retain the corrected corpus-v2 candidate.' \
    '  --validate-only Validate bound inputs and focused contracts only.'
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
readonly MEASURER="$SCRIPT_DIR/measure_synthetic_corpus_v2_without_ingestion.py"
readonly CHUNKING="$PYTHON_ROOT/ishikawa/chunking.py"
readonly DOCUMENT_CONTROL_TEST="$TEST_ROOT/test_document_control.py"
readonly CHUNKING_TEST="$TEST_ROOT/chunking_checks.py"
readonly PRIOR_REPORT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-preingestion/corpus_v2_preingestion_measurement_20261022T175448Z_tp6Xs5.txt"
readonly PRIOR_OBSERVATION="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-preingestion/corpus_v2_retrieval_observation_20261022T175448Z.json"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-corrected"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-corrected"
readonly EXPECTED_HOST='DankoSurface'
readonly EXPECTED_OS_VERSION='24.04'
readonly EXPECTED_NATIVE_TESTS=407
readonly EXPECTED_PIPELINE_TESTS=43
readonly EXPECTED_PAGES=26
readonly EXPECTED_CANDIDATES=139

readonly PRIOR_REPORT_SHA256='ab8c150b20d71924252d2ec7a7e78dccb550944c6aabd471414786631f94eb6e'
readonly PRIOR_OBSERVATION_SHA256='85b3cd471199cbe7edc4ed0318d7e2ba668c246db23eddc3cbc3a7b9c10ad137'
readonly V1_GENERATOR_SHA256='1e17cacd16a9f0792262311816b2952fbd6707e96b5928c6af1139674c54c843'
readonly GENERATOR_SHA256='69b38659941b0e623f895cdaa5cfe5d79f00514d28caec21f20f8745ee296484'
readonly CAPTURE_SHA256='a303e63d1a2329ddec39d563b5a7bdddea5bd7d720206544744876171a5371e2'
readonly QUALIFIER_SHA256='6b0e64b55039c573a4bbd16c2790fb3bca4bfa4650cb7c348c91832d14e54d4a'
readonly MEASURER_SHA256='eb9eb9f3adbf10ebd3679bdba5a0befb9b2d1ed48957ab00e2b0a88f313680af'
readonly CHUNKING_SHA256='91a9df32e81113f8ac0cd036579acf0a9a29c9c0e8e8517f3a00c212cb6a09b3'
readonly DECISIONS_SHA256='57b9f93183a4f56d074d42691faf6e80541988599675ce3284bcc2a9596cd907'
readonly DOCUMENT_CONTROL_TEST_SHA256='95ddff90cf5bf19bb1c5ec5176c9973f76b6e45d95d85b9e1da58a2a8f19b012'
readonly CHUNKING_TEST_SHA256='4b6a35cd21cd74152a8887810d0438128bb2fd1168458280808fed3e302e39ee'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      printf 'script_162_correct_synthetic_corpus_v2=blocked;reason=argument_invalid\n' >&2
      usage >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_162_correct_synthetic_corpus_v2=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for command_name in bash cmp date diff dirname dpkg-query find grep hostname \
  mkdir mktemp mv pdfinfo pdftotext python3 rm sed sha256sum sort stat tee; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'script_162_correct_synthetic_corpus_v2=blocked;reason=local_command_missing;command=%s\n' \
      "$command_name" >&2
    exit 2
  }
done

check_file() {
  local path="$1" expected_sha256="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] || {
    printf 'script_162_correct_synthetic_corpus_v2=blocked;reason=%s_unsafe\n' "$label" >&2
    exit 2
  }
  [[ "$(sha256sum "$path" | sed 's/[[:space:]].*$//')" == "$expected_sha256" ]] || {
    printf 'script_162_correct_synthetic_corpus_v2=blocked;reason=%s_identity_changed\n' "$label" >&2
    exit 2
  }
}

check_file "$PRIOR_REPORT" "$PRIOR_REPORT_SHA256" prior_measurement_report
check_file "$PRIOR_OBSERVATION" "$PRIOR_OBSERVATION_SHA256" prior_measurement_observation
check_file "$V1_GENERATOR" "$V1_GENERATOR_SHA256" accepted_v1_generator
check_file "$GENERATOR" "$GENERATOR_SHA256" corrected_v2_generator
check_file "$CAPTURE" "$CAPTURE_SHA256" extraction_capture
check_file "$QUALIFIER" "$QUALIFIER_SHA256" corrected_v2_qualifier
check_file "$MEASURER" "$MEASURER_SHA256" corrected_v2_measurer
check_file "$CHUNKING" "$CHUNKING_SHA256" corrected_chunking
check_file "$DECISIONS" "$DECISIONS_SHA256" frozen_decisions
check_file "$DOCUMENT_CONTROL_TEST" "$DOCUMENT_CONTROL_TEST_SHA256" document_control_test
check_file "$CHUNKING_TEST" "$CHUNKING_TEST_SHA256" chunking_test

grep -Fq 'preingestion_measurement_gate=not_met;strict_body_target=greater_than_0.91' \
  "$PRIOR_REPORT" || {
  printf 'script_162_correct_synthetic_corpus_v2=blocked;reason=prior_measurement_not_bound\n' >&2
  exit 1
}
grep -Fq 'milestone=retrieval_measurement;state=pass;' "$PRIOR_REPORT" || {
  printf 'script_162_correct_synthetic_corpus_v2=blocked;reason=prior_measurement_incomplete\n' >&2
  exit 1
}
python3 -B - "$PRIOR_OBSERVATION" <<'PY'
import json
import pathlib
import sys

value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert value["preingestion_measurement_gate"] == "not_met"
assert value["candidate_count"] == 134
assert value["body_metrics"]["mrr_at_20"] == "0.807798"
assert value["header_metrics"]["mrr_at_20"] == "0.546131"
assert value["database_write"] is False
assert value["accepted_v1_database_contact"] is False
assert value["gemma_contact"] is False
PY

for decision in V13-25 V13-26 V13-27; do
  grep -Fq "| \`$decision\` " "$DECISIONS" || {
    printf 'script_162_correct_synthetic_corpus_v2=blocked;reason=decision_not_frozen;decision=%s\n' \
      "$decision" >&2
    exit 1
  }
done

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER"
for python_source in "$GENERATOR" "$CAPTURE" "$QUALIFIER" "$MEASURER" \
  "$CHUNKING" "$DOCUMENT_CONTROL_TEST" "$CHUNKING_TEST"; do
  PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
    'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
    "$python_source"
done

focused_output="$({
  PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B -m unittest \
    "$DOCUMENT_CONTROL_TEST" "$CHUNKING_TEST"
} 2>&1)" || {
  printf '%s\n' "$focused_output" >&2
  printf 'script_162_correct_synthetic_corpus_v2=blocked;reason=focused_contract_tests_failed\n' >&2
  exit 1
}
grep -Fq 'Ran 18 tests' <<<"$focused_output" || {
  printf 'script_162_correct_synthetic_corpus_v2=blocked;reason=focused_test_count_mismatch\n' >&2
  exit 1
}

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | sed 's/[[:space:]].*$//')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_corrected_synthetic_corpus_v2_rebuild' \
    "script_sha256=$script_sha256;prior_observation_sha256=$PRIOR_OBSERVATION_SHA256" \
    "generator_sha256=$GENERATOR_SHA256;chunking_sha256=$CHUNKING_SHA256;qualifier_sha256=$QUALIFIER_SHA256" \
    'frozen_decisions=V13-25_V13-26_V13-27;focused_tests=18' \
    'accepted_v1_database_contact=false;database_write=false;model_contact=false;credential_read=false;service_changed=false;corpus_v1_changed=false;package_changed=false' \
    'script_162_correct_synthetic_corpus_v2=pass'
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
  emit "script_162_correct_synthetic_corpus_v2=blocked;reason=$1"
  exit 1
}

cleanup() {
  local initial_status="$?"
  trap - EXIT HUP INT TERM
  set +e
  if (( initial_status != 0 )) && [[ "$failure_recorded" != true ]]; then
    emit "script_162_correct_synthetic_corpus_v2=blocked;reason=unexpected_failure;exit_code=$initial_status"
  fi
  if [[ -n "$work_root" && "$work_root" == /tmp/ishikawa-script-162.* ]]; then
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
report_path="$(mktemp "$REPORT_ROOT/corrected_synthetic_corpus_v2_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-script-162.XXXXXX)"
artifact_path="$ARTIFACT_ROOT/synthetic_corpus_v2_corrected_candidate_$timestamp"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" ]] || block artifact_path_exists

emit 'purpose=rebuild_corrected_synthetic_corpus_v2'
emit "started_utc=$timestamp;script_sha256=$script_sha256;prior_observation_sha256=$PRIOR_OBSERVATION_SHA256"
emit "generator_sha256=$GENERATOR_SHA256;chunking_sha256=$CHUNKING_SHA256;qualifier_sha256=$QUALIFIER_SHA256"
emit 'authorized_actions=run_local_tests_generate_synthetic_pdfs_twice_run_local_poppler_normalize_chunk_twice_write_corrected_candidate_and_content_free_report'
emit 'non_actions=no_database_contact_no_model_contact_no_credential_read_no_service_change_no_remote_contact_no_corpus_v1_change_no_package_change_no_accepted_release_change_no_black_corpus_access'

[[ "$(hostname -s)" == "$EXPECTED_HOST" ]] || block local_host_identity_mismatch
[[ "$(sed -n 's/^VERSION_ID="\{0,1\}\([^" ]*\)"\{0,1\}$/\1/p' /etc/os-release)" == "$EXPECTED_OS_VERSION" ]] \
  || block local_os_version_mismatch
[[ "$(dpkg-query -W -f='${Version}' poppler-utils)" == '24.02.0-1ubuntu9.10' ]] \
  || block poppler_package_identity_mismatch
[[ "$(pdfinfo -v 2>&1 | sed -n '1s/.* //p')" == '24.02.0' ]] \
  || block pdfinfo_identity_mismatch
[[ "$(pdftotext -v 2>&1 | sed -n '1s/.* //p')" == '24.02.0' ]] \
  || block pdftotext_identity_mismatch
emit 'milestone=bound_inputs;state=pass;prior_gate=not_met;corpus_v1=immutable;poppler=24.02.0'

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
grep -Fxq \
  'synthetic_corpus_v2_generation=pass;documents=6;pages=26;departments=4;mastheads=6;header_fields=6' \
  "$work_root/generator-a.txt" || block corpus_generation_marker_absent
diff -u \
  <(cd "$corpus_a" && find . -type f -print | LC_ALL=C sort) \
  <(cd "$corpus_b" && find . -type f -print | LC_ALL=C sort) \
  >/dev/null || block corpus_file_inventory_not_repeatable
while IFS= read -r relative_path; do
  cmp --silent "$corpus_a/$relative_path" "$corpus_b/$relative_path" \
    || block corpus_bytes_not_repeatable
done < <(cd "$corpus_a" && find . -type f -printf '%P\n' | LC_ALL=C sort)
python3 -B - "$corpus_a/evaluation/header_acceptance_truth.json" <<'PY'
import json
import pathlib
import sys

truth = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert truth["first_semantic_body_page"] == 1
assert truth["leading_blank_page_policy"] == "removed_from_v2_before_masthead"
documents = {item["filename"]: item for item in truth["documents"]}
assert sum(item["pages"] for item in documents.values()) == 26
assert documents["OPS_17_CTL_2002_RevA.pdf"]["pages"] == 1
assert documents["OPS_17_CTL_2002_RevA.pdf"]["leading_blank_pages_removed"] == 1
assert sum(item["leading_blank_pages_removed"] for item in documents.values()) == 1
PY
emit 'milestone=corpus_generation;state=pass;documents=6;pages=26;departments=4;byte_repeatable=true;leading_blank_pages_removed=1'

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
grep -Fxq 'source_documents=6;source_pages=26;observed_blank_pages=0' "$work_root/capture.txt" \
  || block pdf_extraction_inventory_mismatch
emit 'milestone=pdf_extraction;state=pass;documents=6;pages=26;blank_pages=0;repeatable=true'

qualification_a="$work_root/qualification-a"
qualification_b="$work_root/qualification-b"
mkdir -p -- "$qualification_a" "$qualification_b"
emit 'milestone=metadata_and_chunk_qualification;state=start;repetitions=2'
for qualification_root in "$qualification_a" "$qualification_b"; do
  PYTHONDONTWRITEBYTECODE=1 python3 -B "$QUALIFIER" \
    --python-root "$PYTHON_ROOT" \
    --archive "$capture_archive" \
    --source-manifest "$corpus_a/source_manifest.json" \
    --truth "$corpus_a/evaluation/header_acceptance_truth.json" \
    --normalized-output "$qualification_root/normalized.json" \
    --chunks-output "$qualification_root/chunks.json" \
    >"$qualification_root/result.txt" 2>&1 \
    || block metadata_and_chunk_qualification_failed
done
cmp --silent "$qualification_a/normalized.json" "$qualification_b/normalized.json" \
  || block normalized_bytes_not_repeatable
cmp --silent "$qualification_a/chunks.json" "$qualification_b/chunks.json" \
  || block chunk_bytes_not_repeatable
grep -Fq \
  'header_aware_corpus_v2_qualification=pass;documents=6;departments=4;candidates=139;' \
  "$qualification_a/result.txt" || block qualification_marker_absent
python3 -B - "$qualification_a/normalized.json" "$qualification_a/chunks.json" <<'PY'
import json
import pathlib
import sys

normalized = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
chunks = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
assert sum(document["page_count"] for document in normalized["documents"]) == 26
assert all(document["blank_pages"] == [] for document in normalized["documents"])
assert all(
    any(unit["kind"] != "page_furniture" and unit["page_start"] == 1 for unit in document["units"])
    for document in normalized["documents"]
)
candidates = [candidate for document in chunks["documents"] for candidate in document["candidates"]]
assert len(candidates) == 139
metadata = [item for item in candidates if item["projection_kind"] == "document_control_metadata"]
assert len(metadata) == 6
assert all(item["citation_anchor"]["page_start"] == 1 for item in metadata)
assert all(item["projection_properties"]["retrieval_representative"] is True for item in metadata)
assert all(
    "document_control" in item["retrieval_filters"]
    for item in candidates
)
assert all(
    "Document control metadata" not in item["context_text"]
    for item in candidates
    if item["projection_kind"] != "document_control_metadata"
)
assert chunks["method_profile"]["name"] == "ishikawa-structural-chunk-candidates-v4"
PY

mkdir -p -- "$corpus_a/qualification"
mv -- "$qualification_a/normalized.json" "$corpus_a/qualification/normalized.json"
mv -- "$qualification_a/chunks.json" "$corpus_a/qualification/chunks.json"
mv -- "$qualification_a/result.txt" "$corpus_a/qualification/result.txt"
mv -- "$capture_archive" "$corpus_a/qualification/extraction.tar"
(
  cd "$corpus_a"
  find . -type f ! -name SHA256SUMS -printf '%P\n' | LC_ALL=C sort | while IFS= read -r relative_path; do
    printf '%s  %s\n' \
      "$(sha256sum "$relative_path" | sed 's/[[:space:]].*$//')" \
      "$relative_path"
  done >SHA256SUMS
)
candidate_file_count="$(sed -n '$=' "$corpus_a/SHA256SUMS")"
[[ "$candidate_file_count" == 13 ]] || block candidate_file_count_invalid
checksum_manifest_sha256="$(sha256sum "$corpus_a/SHA256SUMS" | sed 's/[[:space:]].*$//')"
chunks_sha256="$(sha256sum "$corpus_a/qualification/chunks.json" | sed 's/[[:space:]].*$//')"
normalized_sha256="$(sha256sum "$corpus_a/qualification/normalized.json" | sed 's/[[:space:]].*$//')"
mv -- "$corpus_a" "$artifact_path"

emit 'milestone=metadata_and_chunk_qualification;state=pass;documents=6;metadata_candidates=6;body_header_duplication=false;candidates=139;repeatable=true'
emit "artifact_path=$artifact_path;candidate_files=$candidate_file_count;checksum_manifest_sha256=$checksum_manifest_sha256"
emit "normalized_sha256=$normalized_sha256;chunks_sha256=$chunks_sha256"
emit 'corpus_v1_changed=false;database_contact=false;model_contact=false;credential_read=false;service_changed=false;package_changed=false;ingestion_performed=false'
emit 'script_162_correct_synthetic_corpus_v2=pass;next_gate=embed_and_remeasure_corrected_corpus_v2_without_ingestion'
