#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the neutral changed-document pipeline executable without contacting
#   PostgreSQL, a model endpoint, or a target host.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/84_qualify_live_document_pipeline_executable.sh --run

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
readonly EVALUATOR="$SCRIPT_DIR/evaluate_live_document_pipeline_executable.py"
readonly PIPELINE_EXECUTABLE="$SCRIPT_DIR/ishikawa-produce-artifacts"
readonly PIPELINE_MODULE="$PYTHON_ROOT/ishikawa/artifact_pipeline.py"
readonly PIPELINE_TEST="$ISHIKAWA_ROOT/tests/test_artifact_pipeline.py"
readonly PIPELINE_CONTRACT="$ISHIKAWA_ROOT/docs/LIVE_DOCUMENT_PIPELINE_EXECUTABLE.md"
readonly CAPTURE="$SCRIPT_DIR/capture-pdf-extraction-observations.py"
readonly NORMALIZE="$SCRIPT_DIR/normalize-pdf-extraction.py"
readonly CHUNK="$SCRIPT_DIR/create-structural-chunk-candidates.py"
readonly EMBED="$SCRIPT_DIR/embed_document_candidates_via_endpoint.py"
readonly CONFIG_ROOT="$ISHIKAWA_ROOT/tests/fixtures/pipeline_writer"
readonly SOURCE_ROOT="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/anderson-upload"
readonly LIVE_ROOT="$REPO_ROOT/local/artifacts/ishikawa/live-document-stage/live_document_stage_20261020T183812Z"
readonly NORMALIZED="$LIVE_ROOT/normalized.json"
readonly CHUNKS="$LIVE_ROOT/chunks.json"
readonly EMBEDDINGS="$LIVE_ROOT/embeddings.json"
readonly NORMALIZED_SHA256='9a071580c320282b9e02f33737a0511ebf7b44900066d21d8fcb5ccbda1fa1bc'
readonly CHUNKS_SHA256='d6bcdd6de14b0e8bdb2c2676c29fe8d36f3eb9f459394f2de1d3eecd15b7ba88'
readonly EMBEDDINGS_SHA256='8b7387d88949f014660774df5c202f59d5bdebffe94240af5d4b6b59c05fde8e'
readonly ACCEPTED_SCRIPT_83_REPORT="$REPO_ROOT/local/reports/ishikawa-live-document-artifact-stage/live_document_artifact_stage_20261020T190359Z_V0gNw1.txt"
readonly ACCEPTED_SCRIPT_83_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/live-document-artifact-stage/live_document_artifact_stage_qualification_20261020T190359Z.json"
readonly ACCEPTED_SCRIPT_83_CHECKSUM="$ACCEPTED_SCRIPT_83_ARTIFACT.sha256"
readonly ACCEPTED_SCRIPT_83_REPORT_SHA256='c2e7764de1b5600b996973aa47e82668f549934cb06b5c1ffbe0f6b86a02df9c'
readonly ACCEPTED_SCRIPT_83_ARTIFACT_SHA256='0332122f2cc4b26db8490db1cd55088a4bd2853a644ede2ffa7149708fc09c8d'
readonly ACCEPTED_SCRIPT_83_CHECKSUM_SHA256='a83a9208f41ee71425cfb212d5e96b05ca34ad85a98827b30b85a14f2270aaac'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-live-document-pipeline-executable"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/live-document-pipeline-executable"

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
for required in awk bash chmod cp date find grep mkdir mktemp python3 rm sed sha256sum sort stat tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'BLOCKED: missing local command: %s\n' "$required" >&2
    exit 2
  }
done
mapfile -t python_sources < <(find "$PYTHON_ROOT/ishikawa" -maxdepth 1 -type f -name '*.py' -print | sort)
mapfile -t source_pdfs < <(find "$SOURCE_ROOT" -maxdepth 1 -type f -name '*.pdf' -print | sort)
for source in \
  "$TEST_RUNNER" "$EVALUATOR" "$PIPELINE_EXECUTABLE" "$PIPELINE_MODULE" "$PIPELINE_TEST" "$PIPELINE_CONTRACT" \
  "$CAPTURE" "$NORMALIZE" "$CHUNK" "$EMBED" \
  "$CONFIG_ROOT/document_classes.yaml" "$CONFIG_ROOT/document_catalog.yaml" "$CONFIG_ROOT/ingestion_manifest.yaml" \
  "$NORMALIZED" "$CHUNKS" "$EMBEDDINGS" \
  "$ACCEPTED_SCRIPT_83_REPORT" "$ACCEPTED_SCRIPT_83_ARTIFACT" "$ACCEPTED_SCRIPT_83_CHECKSUM" \
  "${python_sources[@]}" "${source_pdfs[@]}"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: a required Script 84 input is missing or unsafe.\n' >&2
    exit 2
  }
done
[[ -x "$PIPELINE_EXECUTABLE" ]] || { printf 'BLOCKED: pipeline executable is not executable.\n' >&2; exit 2; }
(( ${#source_pdfs[@]} == 6 )) || { printf 'BLOCKED: synthetic PDF inventory mismatch.\n' >&2; exit 2; }

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'BLOCKED: %s identity changed.\n' "$3" >&2
    exit 2
  }
}
check_sha256 "$NORMALIZED" "$NORMALIZED_SHA256" 'accepted normalized artifact'
check_sha256 "$CHUNKS" "$CHUNKS_SHA256" 'accepted chunk artifact'
check_sha256 "$EMBEDDINGS" "$EMBEDDINGS_SHA256" 'accepted embedding artifact'
check_sha256 "$ACCEPTED_SCRIPT_83_REPORT" "$ACCEPTED_SCRIPT_83_REPORT_SHA256" 'accepted Script 83 report'
check_sha256 "$ACCEPTED_SCRIPT_83_ARTIFACT" "$ACCEPTED_SCRIPT_83_ARTIFACT_SHA256" 'accepted Script 83 artifact'
check_sha256 "$ACCEPTED_SCRIPT_83_CHECKSUM" "$ACCEPTED_SCRIPT_83_CHECKSUM_SHA256" 'accepted Script 83 checksum'
(cd "$(dirname -- "$ACCEPTED_SCRIPT_83_ARTIFACT")" && sha256sum --check --strict "$(basename -- "$ACCEPTED_SCRIPT_83_CHECKSUM")" >/dev/null) || {
  printf 'BLOCKED: accepted Script 83 artifact failed checksum verification.\n' >&2
  exit 2
}
for fact in \
  'live_document_artifact_stage_qualification=pass' \
  'script_83_live_document_artifact_stage=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_SCRIPT_83_REPORT" || {
    printf 'BLOCKED: an accepted Script 83 fact is absent.\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$EVALUATOR" "$PIPELINE_EXECUTABLE" "$CAPTURE" "$NORMALIZE" "$CHUNK" "$EMBED" "$PIPELINE_TEST" "${python_sources[@]}"

work_root="$(mktemp -d /tmp/ishikawa-script-84.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-84.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  printf 'script_84_live_document_pipeline_executable=blocked;reason=test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$test_result" | awk '{print $1}')" "$(stat -c '%s' "$test_result")" >&2
  exit 1
}
grep -Fq 'Ran 310 tests' "$test_result" || {
  printf 'script_84_live_document_pipeline_executable=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_84_live_document_pipeline_executable=blocked;reason=test_pass_marker_absent\n' >&2
  exit 1
}

temporary_artifact="$work_root/live-document-pipeline-executable.json"
evaluation_result="$work_root/evaluation.txt"
evaluation_error="$work_root/evaluation-error.txt"
if ! PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B "$EVALUATOR" \
  --python-root "$PYTHON_ROOT" \
  --pipeline-executable "$PIPELINE_EXECUTABLE" \
  --capture "$CAPTURE" --normalize "$NORMALIZE" --chunk "$CHUNK" --embed "$EMBED" \
  --config-root "$CONFIG_ROOT" --source-root "$SOURCE_ROOT" \
  --normalized "$NORMALIZED" --normalized-sha256 "$NORMALIZED_SHA256" \
  --chunks "$CHUNKS" --chunks-sha256 "$CHUNKS_SHA256" \
  --embeddings "$EMBEDDINGS" --embeddings-sha256 "$EMBEDDINGS_SHA256" \
  --output "$temporary_artifact" >"$evaluation_result" 2>"$evaluation_error"; then
  printf 'script_84_live_document_pipeline_executable=blocked;reason=pipeline_evaluation_failed;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$evaluation_error" | awk '{print $1}')" "$(stat -c '%s' "$evaluation_error")" >&2
  exit 1
fi
for fact in \
  'pipeline_command=ishikawa-produce-artifacts;request_contract=pass;result_contract=pass' \
  'stage_order=extraction,normalization,chunking,embedding;stage_calls=4' \
  'requested_documents=6;staged_documents=6;whole_corpus_implicit=false' \
  'credential_stage_count=1;credential_in_arguments=false;credential_retained=false' \
  'temporary_source_workspace_cleanup=pass;artifact_checksum_binding=pass' \
  'target_contact=false;database_contact=false;model_call=false;source_content_retained=false;vectors_retained=false' \
  'live_document_pipeline_executable_qualification=pass'; do
  grep -Fqx "$fact" "$evaluation_result" || {
    printf 'script_84_live_document_pipeline_executable=blocked;reason=evaluation_contract_mismatch\n' >&2
    exit 1
  }
done

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
executable_sha256="$(sha256sum "$PIPELINE_EXECUTABLE" | awk '{print $1}')"
module_sha256="$(sha256sum "$PIPELINE_MODULE" | awk '{print $1}')"
test_sha256="$(sha256sum "$PIPELINE_TEST" | awk '{print $1}')"
contract_sha256="$(sha256sum "$PIPELINE_CONTRACT" | awk '{print $1}')"
capture_sha256="$(sha256sum "$CAPTURE" | awk '{print $1}')"
normalize_sha256="$(sha256sum "$NORMALIZE" | awk '{print $1}')"
chunk_sha256="$(sha256sum "$CHUNK" | awk '{print $1}')"
embed_sha256="$(sha256sum "$EMBED" | awk '{print $1}')"
artifact_sha256="$(sha256sum "$temporary_artifact" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$temporary_artifact")"

if [[ "$validate_only" == true ]]; then
  cat "$evaluation_result"
  printf '%s\n' \
    'purpose=validate_live_document_pipeline_executable' \
    'target_contact=false;database_contact=false;model_call=false;credential_value_retained=false' \
    "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256;executable_sha256=$executable_sha256;module_sha256=$module_sha256;test_sha256=$test_sha256" \
    "contract_sha256=$contract_sha256;capture_sha256=$capture_sha256;normalize_sha256=$normalize_sha256;chunk_sha256=$chunk_sha256;embed_sha256=$embed_sha256" \
    "accepted_script_83_report_sha256=$ACCEPTED_SCRIPT_83_REPORT_SHA256;accepted_script_83_artifact_sha256=$ACCEPTED_SCRIPT_83_ARTIFACT_SHA256" \
    "qualification_artifact_sha256=$artifact_sha256;qualification_artifact_bytes=$artifact_bytes" \
    'local_tests=310;failures=0;errors=0' \
    'script_84_live_document_pipeline_executable_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/live_document_pipeline_executable_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  printf 'script_84_live_document_pipeline_executable=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
cp -- "$temporary_artifact" "$artifact_path"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true

report_path="$(mktemp "$REPORT_ROOT/live_document_pipeline_executable_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=qualify_live_document_pipeline_executable'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256;executable_sha256=$executable_sha256;module_sha256=$module_sha256;test_sha256=$test_sha256"
emit "contract_sha256=$contract_sha256;capture_sha256=$capture_sha256;normalize_sha256=$normalize_sha256;chunk_sha256=$chunk_sha256;embed_sha256=$embed_sha256"
emit "accepted_script_83_report_sha256=$ACCEPTED_SCRIPT_83_REPORT_SHA256;accepted_script_83_artifact_sha256=$ACCEPTED_SCRIPT_83_ARTIFACT_SHA256"
emit 'authorized_actions=read_checksum_bound_synthetic_inputs_run_local_tests_exercise_dependency_injected_pipeline_executable_retain_content_free_evidence'
emit 'non_actions=no_target_contact_no_database_contact_no_model_call_no_live_credential_read_no_source_document_or_vector_retention_no_schema_package_service_or_corpus_change'
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$artifact_bytes"
emit "accepted_checksum=$checksum_path;source_content_retained=false;vectors_retained=false;credential_values_retained=false"
emit 'local_tests=310;failures=0;errors=0'
emit "script_84_live_document_pipeline_executable=pass;local_report=$report_path;next_gate=run_live_document_pipeline_executable_on_emceedanko"
chmod 0600 "$report_path" 2>/dev/null || true
