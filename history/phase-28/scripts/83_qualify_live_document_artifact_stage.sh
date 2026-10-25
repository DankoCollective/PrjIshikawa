#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the concrete no-shell process boundary between incremental
#   ingestion and an installed live document pipeline executable.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/83_qualify_live_document_artifact_stage.sh --run

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
readonly EVALUATOR="$SCRIPT_DIR/evaluate_live_document_artifact_stage.py"
readonly STAGE_MODULE="$PYTHON_ROOT/ishikawa/live_document_stage.py"
readonly STAGE_TEST="$ISHIKAWA_ROOT/tests/test_live_document_stage.py"
readonly STAGE_CONTRACT="$ISHIKAWA_ROOT/docs/LIVE_DOCUMENT_ARTIFACT_STAGE.md"
readonly RUNTIME_CONFIG_ROOT="$ISHIKAWA_ROOT/config/templates"
readonly OPERATOR_CONFIG_ROOT="$ISHIKAWA_ROOT/tests/fixtures/pipeline_writer"
readonly SOURCE_ROOT="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/anderson-upload"
readonly LIVE_ROOT="$REPO_ROOT/local/artifacts/ishikawa/live-document-stage/live_document_stage_20261020T183812Z"
readonly NORMALIZED="$LIVE_ROOT/normalized.json"
readonly CHUNKS="$LIVE_ROOT/chunks.json"
readonly EMBEDDINGS="$LIVE_ROOT/embeddings.json"
readonly LIVE_CHECKSUMS="$LIVE_ROOT/SHA256SUMS"
readonly NORMALIZED_SHA256='9a071580c320282b9e02f33737a0511ebf7b44900066d21d8fcb5ccbda1fa1bc'
readonly CHUNKS_SHA256='d6bcdd6de14b0e8bdb2c2676c29fe8d36f3eb9f459394f2de1d3eecd15b7ba88'
readonly EMBEDDINGS_SHA256='8b7387d88949f014660774df5c202f59d5bdebffe94240af5d4b6b59c05fde8e'
readonly LIVE_CHECKSUMS_SHA256='c2caa534af3974df7a8e6aacf24ffc4dc2c9352d79abbf4e2d24feba4a205085'
readonly ACCEPTED_SCRIPT_79_REPORT="$REPO_ROOT/local/reports/ishikawa-live-document-stage/live_document_stage_20261020T183812Z_bMtAh3.txt"
readonly ACCEPTED_SCRIPT_79_REPORT_SHA256='3208975b7087e770c9558230faa3747edbc6290da2ab80e1ac2793d0c12b1507'
readonly ACCEPTED_SCRIPT_82_REPORT="$REPO_ROOT/local/reports/ishikawa-configured-ingestion-runtime/configured_ingestion_runtime_20261020T185806Z_EzlZ0E.txt"
readonly ACCEPTED_SCRIPT_82_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/configured-ingestion-runtime/configured_ingestion_runtime_qualification_20261020T185806Z.json"
readonly ACCEPTED_SCRIPT_82_CHECKSUM="$ACCEPTED_SCRIPT_82_ARTIFACT.sha256"
readonly ACCEPTED_SCRIPT_82_REPORT_SHA256='ab45ae2629b3f2ddc9bf2c936c42689ddd54c4d711d4e115599cdcf61f329e4b'
readonly ACCEPTED_SCRIPT_82_ARTIFACT_SHA256='f635c760d81c0bb9adf01337b985079e51c785ceb95cda3889890adf5ebfe90f'
readonly ACCEPTED_SCRIPT_82_CHECKSUM_SHA256='6fa6c5b9e9420788984f22bbd9b64873a75721ca83fb41341115a2da625538ea'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-live-document-artifact-stage"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/live-document-artifact-stage"

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
  "$TEST_RUNNER" "$EVALUATOR" "$STAGE_MODULE" "$STAGE_TEST" "$STAGE_CONTRACT" \
  "$RUNTIME_CONFIG_ROOT/ingestion_dependencies.yaml" \
  "$OPERATOR_CONFIG_ROOT/document_classes.yaml" "$OPERATOR_CONFIG_ROOT/document_catalog.yaml" "$OPERATOR_CONFIG_ROOT/ingestion_manifest.yaml" \
  "$NORMALIZED" "$CHUNKS" "$EMBEDDINGS" "$LIVE_CHECKSUMS" \
  "$ACCEPTED_SCRIPT_79_REPORT" "$ACCEPTED_SCRIPT_82_REPORT" "$ACCEPTED_SCRIPT_82_ARTIFACT" "$ACCEPTED_SCRIPT_82_CHECKSUM" \
  "${python_sources[@]}" "${source_pdfs[@]}"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: a required Script 83 input is missing or unsafe.\n' >&2
    exit 2
  }
done
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
check_sha256 "$LIVE_CHECKSUMS" "$LIVE_CHECKSUMS_SHA256" 'accepted live checksum manifest'
check_sha256 "$ACCEPTED_SCRIPT_79_REPORT" "$ACCEPTED_SCRIPT_79_REPORT_SHA256" 'accepted Script 79 report'
check_sha256 "$ACCEPTED_SCRIPT_82_REPORT" "$ACCEPTED_SCRIPT_82_REPORT_SHA256" 'accepted Script 82 report'
check_sha256 "$ACCEPTED_SCRIPT_82_ARTIFACT" "$ACCEPTED_SCRIPT_82_ARTIFACT_SHA256" 'accepted Script 82 artifact'
check_sha256 "$ACCEPTED_SCRIPT_82_CHECKSUM" "$ACCEPTED_SCRIPT_82_CHECKSUM_SHA256" 'accepted Script 82 checksum'
(cd "$LIVE_ROOT" && sha256sum --check --strict SHA256SUMS >/dev/null) || {
  printf 'BLOCKED: accepted live artifact set failed checksum verification.\n' >&2
  exit 2
}
(cd "$(dirname -- "$ACCEPTED_SCRIPT_82_ARTIFACT")" && sha256sum --check --strict "$(basename -- "$ACCEPTED_SCRIPT_82_CHECKSUM")" >/dev/null) || {
  printf 'BLOCKED: accepted Script 82 artifact failed checksum verification.\n' >&2
  exit 2
}
for fact in \
  'live_document_stage_evaluation=pass' \
  'script_79_live_document_stage=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_SCRIPT_79_REPORT" || {
    printf 'BLOCKED: an accepted Script 79 fact is absent.\n' >&2
    exit 2
  }
done
for fact in \
  'configured_operator_ingestion_runtime_qualification=pass' \
  'script_82_configured_ingestion_runtime=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_SCRIPT_82_REPORT" || {
    printf 'BLOCKED: an accepted Script 82 fact is absent.\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$EVALUATOR" "$STAGE_TEST" "${python_sources[@]}"

work_root="$(mktemp -d /tmp/ishikawa-script-83.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-83.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  printf 'script_83_live_document_artifact_stage=blocked;reason=test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$test_result" | awk '{print $1}')" "$(stat -c '%s' "$test_result")" >&2
  exit 1
}
grep -Fq 'Ran 304 tests' "$test_result" || {
  printf 'script_83_live_document_artifact_stage=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_83_live_document_artifact_stage=blocked;reason=test_pass_marker_absent\n' >&2
  exit 1
}

temporary_artifact="$work_root/live-document-artifact-stage.json"
evaluation_result="$work_root/evaluation.txt"
evaluation_error="$work_root/evaluation-error.txt"
if ! PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B "$EVALUATOR" \
  --runtime-config-root "$RUNTIME_CONFIG_ROOT" \
  --operator-config-root "$OPERATOR_CONFIG_ROOT" \
  --source-root "$SOURCE_ROOT" \
  --normalized "$NORMALIZED" --normalized-sha256 "$NORMALIZED_SHA256" \
  --chunks "$CHUNKS" --chunks-sha256 "$CHUNKS_SHA256" \
  --embeddings "$EMBEDDINGS" --embeddings-sha256 "$EMBEDDINGS_SHA256" \
  --output "$temporary_artifact" >"$evaluation_result" 2>"$evaluation_error"; then
  printf 'script_83_live_document_artifact_stage=blocked;reason=stage_evaluation_failed;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$evaluation_error" | awk '{print $1}')" "$(stat -c '%s' "$evaluation_error")" >&2
  exit 1
fi
for fact in \
  'stage_process_calls=1;requested_documents=6;whole_corpus_implicit=false' \
  'credential_transport=stdin;credential_in_arguments=false;credential_in_request=false' \
  'artifacts=normalized,chunks,embeddings;checksum_binding=pass;result_contract=pass' \
  'prepared_documents=6;pages=27;structural_units=231;chunks=126' \
  'artifact_retention_calls=1;producer_workspace_cleanup=pass' \
  'target_contact=false;database_contact=false;model_call=false;source_content_retained=false;vectors_retained=false' \
  'live_document_artifact_stage_qualification=pass'; do
  grep -Fqx "$fact" "$evaluation_result" || {
    printf 'script_83_live_document_artifact_stage=blocked;reason=evaluation_contract_mismatch\n' >&2
    exit 1
  }
done

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
stage_module_sha256="$(sha256sum "$STAGE_MODULE" | awk '{print $1}')"
stage_test_sha256="$(sha256sum "$STAGE_TEST" | awk '{print $1}')"
stage_contract_sha256="$(sha256sum "$STAGE_CONTRACT" | awk '{print $1}')"
artifact_sha256="$(sha256sum "$temporary_artifact" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$temporary_artifact")"

if [[ "$validate_only" == true ]]; then
  cat "$evaluation_result"
  printf '%s\n' \
    'purpose=validate_live_document_artifact_stage' \
    'target_contact=false;database_contact=false;model_call=false;credential_value_retained=false' \
    "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256;stage_module_sha256=$stage_module_sha256;stage_test_sha256=$stage_test_sha256" \
    "stage_contract_sha256=$stage_contract_sha256;accepted_script_79_report_sha256=$ACCEPTED_SCRIPT_79_REPORT_SHA256;accepted_script_82_report_sha256=$ACCEPTED_SCRIPT_82_REPORT_SHA256" \
    "accepted_normalized_sha256=$NORMALIZED_SHA256;accepted_chunks_sha256=$CHUNKS_SHA256;accepted_embeddings_sha256=$EMBEDDINGS_SHA256" \
    "qualification_artifact_sha256=$artifact_sha256;qualification_artifact_bytes=$artifact_bytes" \
    'local_tests=304;failures=0;errors=0' \
    'script_83_live_document_artifact_stage_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/live_document_artifact_stage_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  printf 'script_83_live_document_artifact_stage=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
cp -- "$temporary_artifact" "$artifact_path"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true

report_path="$(mktemp "$REPORT_ROOT/live_document_artifact_stage_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=qualify_live_document_artifact_stage_process_boundary'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256;stage_module_sha256=$stage_module_sha256;stage_test_sha256=$stage_test_sha256"
emit "stage_contract_sha256=$stage_contract_sha256;accepted_script_79_report_sha256=$ACCEPTED_SCRIPT_79_REPORT_SHA256;accepted_script_82_report_sha256=$ACCEPTED_SCRIPT_82_REPORT_SHA256"
emit "accepted_normalized_sha256=$NORMALIZED_SHA256;accepted_chunks_sha256=$CHUNKS_SHA256;accepted_embeddings_sha256=$EMBEDDINGS_SHA256"
emit 'authorized_actions=read_checksum_bound_synthetic_inputs_run_local_tests_exercise_no_shell_live_stage_boundary_adapt_accepted_artifacts_retain_content_free_evidence'
emit 'non_actions=no_target_contact_no_database_contact_no_model_call_no_live_credential_read_no_source_document_or_vector_retention_no_schema_package_service_or_corpus_change'
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$artifact_bytes"
emit "accepted_checksum=$checksum_path;source_content_retained=false;vectors_retained=false;credential_values_retained=false"
emit 'local_tests=304;failures=0;errors=0'
emit "script_83_live_document_artifact_stage=pass;local_report=$report_path;next_gate=implement_live_document_pipeline_executable"
chmod 0600 "$report_path" 2>/dev/null || true
