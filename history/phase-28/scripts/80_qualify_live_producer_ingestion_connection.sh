#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Connect the accepted live document-stage artifacts to NativeDocumentProducer
#   and the operator-ingestion control plane without repeating model or database work.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/80_qualify_live_producer_ingestion_connection.sh --run

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
readonly EVALUATOR="$SCRIPT_DIR/evaluate_live_producer_ingestion_connection.py"
readonly CONFIG_ROOT="$ISHIKAWA_ROOT/tests/fixtures/pipeline_writer"
readonly SOURCE_ROOT="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/anderson-upload"
readonly LIVE_ROOT="$REPO_ROOT/local/artifacts/ishikawa/live-document-stage/live_document_stage_20261020T183812Z"
readonly NORMALIZED="$LIVE_ROOT/normalized.json"
readonly CHUNKS="$LIVE_ROOT/chunks.json"
readonly EMBEDDINGS="$LIVE_ROOT/embeddings.json"
readonly QUALIFICATION="$LIVE_ROOT/qualification.json"
readonly CHECKSUMS="$LIVE_ROOT/SHA256SUMS"
readonly ACCEPTED_SCRIPT_78_REPORT="$REPO_ROOT/local/reports/ishikawa-document-producer-contract/document_producer_contract_20261020T175807Z_Gy3Erz.txt"
readonly ACCEPTED_SCRIPT_79_REPORT="$REPO_ROOT/local/reports/ishikawa-live-document-stage/live_document_stage_20261020T183812Z_bMtAh3.txt"
readonly ACCEPTED_SCRIPT_78_REPORT_SHA256='101d55be24551858ad95627cac3a793d81d14ce1b626c6d4265a7f68c1065a09'
readonly ACCEPTED_SCRIPT_79_REPORT_SHA256='3208975b7087e770c9558230faa3747edbc6290da2ab80e1ac2793d0c12b1507'
readonly NORMALIZED_SHA256='9a071580c320282b9e02f33737a0511ebf7b44900066d21d8fcb5ccbda1fa1bc'
readonly CHUNKS_SHA256='d6bcdd6de14b0e8bdb2c2676c29fe8d36f3eb9f459394f2de1d3eecd15b7ba88'
readonly EMBEDDINGS_SHA256='8b7387d88949f014660774df5c202f59d5bdebffe94240af5d4b6b59c05fde8e'
readonly QUALIFICATION_SHA256='b1f4420ea9bc3f7a04b991a0f2c58442bb13d9c9b529bec9d358762541736e1b'
readonly CHECKSUMS_SHA256='c2caa534af3974df7a8e6aacf24ffc4dc2c9352d79abbf4e2d24feba4a205085'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-live-producer-ingestion"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/live-producer-ingestion"

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
for required in awk bash chmod cp date grep mkdir mktemp python3 rm sed sha256sum stat tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'BLOCKED: missing local command: %s\n' "$required" >&2
    exit 2
  }
done
mapfile -t python_sources < <(find "$PYTHON_ROOT/ishikawa" -maxdepth 1 -type f -name '*.py' -print | sort)
mapfile -t source_pdfs < <(find "$SOURCE_ROOT" -maxdepth 1 -type f -name '*.pdf' -print | sort)
for source in \
  "$TEST_RUNNER" "$EVALUATOR" \
  "$CONFIG_ROOT/document_classes.yaml" "$CONFIG_ROOT/document_catalog.yaml" "$CONFIG_ROOT/ingestion_manifest.yaml" \
  "$NORMALIZED" "$CHUNKS" "$EMBEDDINGS" "$QUALIFICATION" "$CHECKSUMS" \
  "$ACCEPTED_SCRIPT_78_REPORT" "$ACCEPTED_SCRIPT_79_REPORT" \
  "${python_sources[@]}" "${source_pdfs[@]}"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: a required Script 80 input is missing or unsafe.\n' >&2
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
check_sha256 "$ACCEPTED_SCRIPT_78_REPORT" "$ACCEPTED_SCRIPT_78_REPORT_SHA256" 'accepted Script 78 report'
check_sha256 "$ACCEPTED_SCRIPT_79_REPORT" "$ACCEPTED_SCRIPT_79_REPORT_SHA256" 'accepted Script 79 report'
check_sha256 "$NORMALIZED" "$NORMALIZED_SHA256" 'accepted live normalized artifact'
check_sha256 "$CHUNKS" "$CHUNKS_SHA256" 'accepted live chunk artifact'
check_sha256 "$EMBEDDINGS" "$EMBEDDINGS_SHA256" 'accepted live embedding artifact'
check_sha256 "$QUALIFICATION" "$QUALIFICATION_SHA256" 'accepted live qualification artifact'
check_sha256 "$CHECKSUMS" "$CHECKSUMS_SHA256" 'accepted live checksum manifest'
(cd "$LIVE_ROOT" && sha256sum --check --strict SHA256SUMS >/dev/null) || {
  printf 'BLOCKED: accepted Script 79 artifact set failed checksum verification.\n' >&2
  exit 2
}
for fact in \
  'document_producer_contract_qualification=pass' \
  'script_78_document_producer_contract=pass;' ; do
  grep -Fq "$fact" "$ACCEPTED_SCRIPT_78_REPORT" || {
    printf 'BLOCKED: an accepted Script 78 fact is absent.\n' >&2
    exit 2
  }
done
for fact in \
  'live_document_stage_evaluation=pass' \
  'milestone=local_held_out_evaluation;state=pass' \
  'script_79_live_document_stage=pass;' ; do
  grep -Fq "$fact" "$ACCEPTED_SCRIPT_79_REPORT" || {
    printf 'BLOCKED: an accepted Script 79 fact is absent.\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$EVALUATOR" "${python_sources[@]}"

work_root="$(mktemp -d /tmp/ishikawa-script-80.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-80.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  printf 'script_80_live_producer_ingestion=blocked;reason=test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$test_result" | awk '{print $1}')" "$(stat -c '%s' "$test_result")" >&2
  exit 1
}
grep -Fq 'Ran 287 tests' "$test_result" || {
  printf 'script_80_live_producer_ingestion=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_80_live_producer_ingestion=blocked;reason=test_pass_marker_absent\n' >&2
  exit 1
}

temporary_artifact="$work_root/live-producer-ingestion.json"
evaluation_result="$work_root/evaluation.txt"
evaluation_error="$work_root/evaluation-error.txt"
if ! PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B "$EVALUATOR" \
  --config-root "$CONFIG_ROOT" \
  --source-root "$SOURCE_ROOT" \
  --normalized "$NORMALIZED" --normalized-sha256 "$NORMALIZED_SHA256" \
  --chunks "$CHUNKS" --chunks-sha256 "$CHUNKS_SHA256" \
  --embeddings "$EMBEDDINGS" --embeddings-sha256 "$EMBEDDINGS_SHA256" \
  --output "$temporary_artifact" >"$evaluation_result" 2>"$evaluation_error"; then
  printf 'script_80_live_producer_ingestion=blocked;reason=connection_evaluation_failed;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$evaluation_error" | awk '{print $1}')" "$(stat -c '%s' "$evaluation_error")" >&2
  exit 1
fi
for fact in \
  'validation_only=pass;producer_calls=0;writer_calls=0' \
  'publication=pass;producer_calls=1;artifact_retention_calls=1;writer_handoff_calls=1' \
  'prepared_documents=6;pages=27;structural_units=231;chunks=126;embedding_dimension=768' \
  'workspace_cleanup=pass;protected_reports=pass;source_paths_disclosed=false' \
  'target_contact=false;database_contact=false;model_call=false;credential_read=false' \
  'live_producer_ingestion_connection_qualification=pass'; do
  grep -Fqx "$fact" "$evaluation_result" || {
    printf 'script_80_live_producer_ingestion=blocked;reason=evaluation_contract_mismatch\n' >&2
    exit 1
  }
done

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
artifact_sha256="$(sha256sum "$temporary_artifact" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$temporary_artifact")"

if [[ "$validate_only" == true ]]; then
  cat "$evaluation_result"
  printf '%s\n' \
    'purpose=validate_live_producer_ingestion_connection' \
    'target_contact=false;database_contact=false;model_call=false;credential_read=false' \
    "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256" \
    "accepted_script_78_report_sha256=$ACCEPTED_SCRIPT_78_REPORT_SHA256;accepted_script_79_report_sha256=$ACCEPTED_SCRIPT_79_REPORT_SHA256" \
    "accepted_normalized_sha256=$NORMALIZED_SHA256;accepted_chunks_sha256=$CHUNKS_SHA256;accepted_embeddings_sha256=$EMBEDDINGS_SHA256" \
    "qualification_artifact_sha256=$artifact_sha256;qualification_artifact_bytes=$artifact_bytes" \
    'local_tests=287;failures=0;errors=0' \
    'script_80_live_producer_ingestion_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/live_producer_ingestion_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  printf 'script_80_live_producer_ingestion=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
cp -- "$temporary_artifact" "$artifact_path"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true

report_path="$(mktemp "$REPORT_ROOT/live_producer_ingestion_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=qualify_live_document_stage_to_operator_ingestion_connection'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256"
emit "accepted_script_78_report_sha256=$ACCEPTED_SCRIPT_78_REPORT_SHA256;accepted_script_79_report_sha256=$ACCEPTED_SCRIPT_79_REPORT_SHA256"
emit "accepted_normalized_sha256=$NORMALIZED_SHA256;accepted_chunks_sha256=$CHUNKS_SHA256;accepted_embeddings_sha256=$EMBEDDINGS_SHA256"
emit 'authorized_actions=read_checksum_bound_synthetic_evidence_run_local_tests_connect_accepted_live_artifacts_to_native_document_producer_and_operator_ingestion_retain_content_free_evidence'
emit 'non_actions=no_target_contact_no_database_contact_no_model_call_no_credential_read_no_source_document_retention_no_schema_package_or_service_change'
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$artifact_bytes"
emit "accepted_checksum=$checksum_path;source_content_retained=false;vectors_retained=false"
emit 'local_tests=287;failures=0;errors=0'
emit "script_80_live_producer_ingestion=pass;local_report=$report_path;next_gate=implement_portable_operator_ingestion_entrypoint"
chmod 0600 "$report_path" 2>/dev/null || true
