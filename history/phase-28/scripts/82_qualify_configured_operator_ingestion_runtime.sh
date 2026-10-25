#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify configuration-to-runtime assembly for operator-invoked ingestion
#   without contacting PostgreSQL, Nomic, or a target host.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/82_qualify_configured_operator_ingestion_runtime.sh --run

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
readonly EVALUATOR="$SCRIPT_DIR/evaluate_configured_ingestion_runtime.py"
readonly RUNTIME_MODULE="$PYTHON_ROOT/ishikawa/ingestion_runtime.py"
readonly RUNTIME_TEST="$ISHIKAWA_ROOT/tests/test_ingestion_runtime.py"
readonly RUNTIME_CONTRACT="$ISHIKAWA_ROOT/docs/OPERATOR_INGESTION_RUNTIME.md"
readonly RUNTIME_CONFIG_ROOT="$ISHIKAWA_ROOT/config/templates"
readonly DEPENDENCY_PROFILE="$RUNTIME_CONFIG_ROOT/ingestion_dependencies.yaml"
readonly DEPLOYMENT_PROFILE="$RUNTIME_CONFIG_ROOT/deployment.yaml"
readonly OPERATOR_CONFIG_ROOT="$ISHIKAWA_ROOT/tests/fixtures/pipeline_writer"
readonly SOURCE_ROOT="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/anderson-upload"
readonly ACCEPTED_SCRIPT_81_REPORT="$REPO_ROOT/local/reports/ishikawa-portable-ingestion-entrypoint/portable_ingestion_entrypoint_20261020T185149Z_ff9hty.txt"
readonly ACCEPTED_SCRIPT_81_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/portable-ingestion-entrypoint/portable_ingestion_entrypoint_qualification_20261020T185149Z.json"
readonly ACCEPTED_SCRIPT_81_CHECKSUM="$ACCEPTED_SCRIPT_81_ARTIFACT.sha256"
readonly ACCEPTED_SCRIPT_81_REPORT_SHA256='b48e043233e7d1f06130fee77b44093e784b6d70443ab9ca14676ec8fea09b2f'
readonly ACCEPTED_SCRIPT_81_ARTIFACT_SHA256='521c8566ac32d465b70823f80710cd0cfc9660e9b5e14a365f4939b769e6f8c5'
readonly ACCEPTED_SCRIPT_81_CHECKSUM_SHA256='023003754177209b3f4428b6293ce557555a77105762ee80fc2caaa888e1d2b1'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-configured-ingestion-runtime"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/configured-ingestion-runtime"

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
  "$TEST_RUNNER" "$EVALUATOR" "$RUNTIME_MODULE" "$RUNTIME_TEST" "$RUNTIME_CONTRACT" \
  "$DEPENDENCY_PROFILE" "$DEPLOYMENT_PROFILE" \
  "$OPERATOR_CONFIG_ROOT/document_classes.yaml" "$OPERATOR_CONFIG_ROOT/document_catalog.yaml" "$OPERATOR_CONFIG_ROOT/ingestion_manifest.yaml" \
  "$ACCEPTED_SCRIPT_81_REPORT" "$ACCEPTED_SCRIPT_81_ARTIFACT" "$ACCEPTED_SCRIPT_81_CHECKSUM" \
  "${python_sources[@]}" "${source_pdfs[@]}"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: a required Script 82 input is missing or unsafe.\n' >&2
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
check_sha256 "$ACCEPTED_SCRIPT_81_REPORT" "$ACCEPTED_SCRIPT_81_REPORT_SHA256" 'accepted Script 81 report'
check_sha256 "$ACCEPTED_SCRIPT_81_ARTIFACT" "$ACCEPTED_SCRIPT_81_ARTIFACT_SHA256" 'accepted Script 81 artifact'
check_sha256 "$ACCEPTED_SCRIPT_81_CHECKSUM" "$ACCEPTED_SCRIPT_81_CHECKSUM_SHA256" 'accepted Script 81 checksum'
(cd "$(dirname -- "$ACCEPTED_SCRIPT_81_ARTIFACT")" && sha256sum --check --strict "$(basename -- "$ACCEPTED_SCRIPT_81_CHECKSUM")" >/dev/null) || {
  printf 'BLOCKED: accepted Script 81 artifact failed checksum verification.\n' >&2
  exit 2
}
for fact in \
  'portable_operator_ingestion_entrypoint_qualification=pass' \
  'script_81_portable_ingestion_entrypoint=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_SCRIPT_81_REPORT" || {
    printf 'BLOCKED: an accepted Script 81 fact is absent.\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$EVALUATOR" "$RUNTIME_TEST" "${python_sources[@]}"

work_root="$(mktemp -d /tmp/ishikawa-script-82.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-82.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  printf 'script_82_configured_ingestion_runtime=blocked;reason=test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$test_result" | awk '{print $1}')" "$(stat -c '%s' "$test_result")" >&2
  exit 1
}
grep -Fq 'Ran 299 tests' "$test_result" || {
  printf 'script_82_configured_ingestion_runtime=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_82_configured_ingestion_runtime=blocked;reason=test_pass_marker_absent\n' >&2
  exit 1
}

temporary_artifact="$work_root/configured-ingestion-runtime.json"
evaluation_result="$work_root/evaluation.txt"
evaluation_error="$work_root/evaluation-error.txt"
if ! PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B "$EVALUATOR" \
  --runtime-config-root "$RUNTIME_CONFIG_ROOT" \
  --operator-config-root "$OPERATOR_CONFIG_ROOT" \
  --source-root "$SOURCE_ROOT" \
  --output "$temporary_artifact" >"$evaluation_result" 2>"$evaluation_error"; then
  printf 'script_82_configured_ingestion_runtime=blocked;reason=runtime_evaluation_failed;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$evaluation_error" | awk '{print $1}')" "$(stat -c '%s' "$evaluation_error")" >&2
  exit 1
fi
for fact in \
  'runtime_components=fixed_operator_paths,native_psycopg_ingest,protected_nomic_provider,native_document_producer,incremental_writer' \
  'postgresql=rag_catalog;role=rag_ingest;application_name=ishikawa-ingestion;read_only=false' \
  'nomic=embedding_/v1/embeddings,tokenization_/tokenize;batch_size=16' \
  'assembly=pass;dependency_calls=0;credential_reads=0;documents_processed=0' \
  'validation_only=pass;database_connections=1;database_credential_reads=1;nomic_credential_reads=0;artifact_stage_calls=0;artifact_retention_calls=0' \
  'operator_paths=fixed;source_paths_exposed=false;credentials_in_yaml=false' \
  'target_contact=false;database_contact=false;model_call=false;source_content_retained=false' \
  'configured_operator_ingestion_runtime_qualification=pass'; do
  grep -Fqx "$fact" "$evaluation_result" || {
    printf 'script_82_configured_ingestion_runtime=blocked;reason=evaluation_contract_mismatch\n' >&2
    exit 1
  }
done

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
runtime_sha256="$(sha256sum "$RUNTIME_MODULE" | awk '{print $1}')"
runtime_test_sha256="$(sha256sum "$RUNTIME_TEST" | awk '{print $1}')"
runtime_contract_sha256="$(sha256sum "$RUNTIME_CONTRACT" | awk '{print $1}')"
dependency_profile_sha256="$(sha256sum "$DEPENDENCY_PROFILE" | awk '{print $1}')"
deployment_profile_sha256="$(sha256sum "$DEPLOYMENT_PROFILE" | awk '{print $1}')"
artifact_sha256="$(sha256sum "$temporary_artifact" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$temporary_artifact")"

if [[ "$validate_only" == true ]]; then
  cat "$evaluation_result"
  printf '%s\n' \
    'purpose=validate_configured_operator_ingestion_runtime' \
    'target_contact=false;database_contact=false;model_call=false;credential_value_retained=false' \
    "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256;runtime_sha256=$runtime_sha256;runtime_test_sha256=$runtime_test_sha256" \
    "runtime_contract_sha256=$runtime_contract_sha256;dependency_profile_sha256=$dependency_profile_sha256;deployment_profile_sha256=$deployment_profile_sha256" \
    "accepted_script_81_report_sha256=$ACCEPTED_SCRIPT_81_REPORT_SHA256;accepted_script_81_artifact_sha256=$ACCEPTED_SCRIPT_81_ARTIFACT_SHA256" \
    "qualification_artifact_sha256=$artifact_sha256;qualification_artifact_bytes=$artifact_bytes" \
    'local_tests=299;failures=0;errors=0' \
    'script_82_configured_ingestion_runtime_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/configured_ingestion_runtime_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  printf 'script_82_configured_ingestion_runtime=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
cp -- "$temporary_artifact" "$artifact_path"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true

report_path="$(mktemp "$REPORT_ROOT/configured_ingestion_runtime_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=qualify_configured_operator_ingestion_runtime'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256;runtime_sha256=$runtime_sha256;runtime_test_sha256=$runtime_test_sha256"
emit "runtime_contract_sha256=$runtime_contract_sha256;dependency_profile_sha256=$dependency_profile_sha256;deployment_profile_sha256=$deployment_profile_sha256"
emit "accepted_script_81_report_sha256=$ACCEPTED_SCRIPT_81_REPORT_SHA256;accepted_script_81_artifact_sha256=$ACCEPTED_SCRIPT_81_ARTIFACT_SHA256"
emit 'authorized_actions=read_checksum_bound_synthetic_inputs_run_local_tests_assemble_configured_ingestion_runtime_execute_injected_validation_only_retain_content_free_evidence'
emit 'non_actions=no_target_contact_no_database_contact_no_model_call_no_live_credential_read_no_document_processing_no_artifact_retention_no_schema_package_service_or_corpus_change'
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$artifact_bytes"
emit "accepted_checksum=$checksum_path;source_content_retained=false;vectors_retained=false;credential_values_retained=false"
emit 'local_tests=299;failures=0;errors=0'
emit "script_82_configured_ingestion_runtime=pass;local_report=$report_path;next_gate=implement_concrete_live_document_artifact_stage"
chmod 0600 "$report_path" 2>/dev/null || true
