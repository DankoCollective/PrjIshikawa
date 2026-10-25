#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the repository-free operator ingestion commands and their fixed
#   installed Ishikawa host layout without contacting any external dependency.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/87_qualify_installed_operator_ingestion_entrypoint.sh --run

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
readonly PACKAGE_ROOT="$PYTHON_ROOT/ishikawa"
readonly TEST_ROOT="$ISHIKAWA_ROOT/tests"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly INGEST_ENTRYPOINT="$ISHIKAWA_ROOT/scripts/ishikawa-ingest"
readonly PIPELINE_ENTRYPOINT="$ISHIKAWA_ROOT/scripts/ishikawa-produce-artifacts"
readonly MODULE="$PACKAGE_ROOT/installed_ingestion.py"
readonly MODULE_TEST="$TEST_ROOT/test_installed_ingestion.py"
readonly CONTRACT="$ISHIKAWA_ROOT/docs/INSTALLED_OPERATOR_INGESTION.md"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_installed_operator_ingestion_entrypoint.py"
readonly CAPTURE="$SCRIPT_DIR/capture-pdf-extraction-observations.py"
readonly NORMALIZE="$SCRIPT_DIR/normalize-pdf-extraction.py"
readonly CHUNK="$SCRIPT_DIR/create-structural-chunk-candidates.py"
readonly EMBED="$SCRIPT_DIR/embed_document_candidates_via_endpoint.py"
readonly RUNTIME_CONFIG_ROOT="$ISHIKAWA_ROOT/config/templates"
readonly OPERATOR_CONFIG_ROOT="$ISHIKAWA_ROOT/tests/fixtures/pipeline_writer"
readonly ACCEPTED_SCRIPT_86_REPORT="$REPO_ROOT/local/reports/ishikawa-configured-live-ingestion-target/configured_live_ingestion_target_20261020T214358Z_bDobGE.txt"
readonly ACCEPTED_SCRIPT_86_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/configured-live-ingestion-target/configured_live_ingestion_target_qualification_20261020T214358Z.json"
readonly ACCEPTED_SCRIPT_86_CHECKSUM="$ACCEPTED_SCRIPT_86_ARTIFACT.sha256"
readonly ACCEPTED_SCRIPT_86_REPORT_SHA256='5051b3127c8ae9c91839bf783c08d3a1110810370eceab223dcf8b95d035005e'
readonly ACCEPTED_SCRIPT_86_ARTIFACT_SHA256='43c633597298c13c07d4b0a9207c08953677d41bda7227b046309ba6d915f4db'
readonly ACCEPTED_SCRIPT_86_CHECKSUM_SHA256='f4c5849b921037ebe215a19d210d8fe14665b6e752dee3f51e0a51ee4e100350'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-installed-ingestion-entrypoint"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/installed-ingestion-entrypoint"

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
for required in awk bash basename chmod cp date find grep mkdir mktemp python3 rm sed sha256sum sort stat tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'BLOCKED: missing local command: %s\n' "$required" >&2
    exit 2
  }
done
mapfile -t python_sources < <(find "$PACKAGE_ROOT" -maxdepth 1 -type f -name '*.py' -print | sort)
for source in \
  "$TEST_RUNNER" "$INGEST_ENTRYPOINT" "$PIPELINE_ENTRYPOINT" "$MODULE" "$MODULE_TEST" "$CONTRACT" "$EVALUATOR" \
  "$CAPTURE" "$NORMALIZE" "$CHUNK" "$EMBED" \
  "$RUNTIME_CONFIG_ROOT/deployment.yaml" "$RUNTIME_CONFIG_ROOT/ingestion_dependencies.yaml" \
  "$OPERATOR_CONFIG_ROOT/document_classes.yaml" "$OPERATOR_CONFIG_ROOT/document_catalog.yaml" "$OPERATOR_CONFIG_ROOT/ingestion_manifest.yaml" \
  "$ACCEPTED_SCRIPT_86_REPORT" "$ACCEPTED_SCRIPT_86_ARTIFACT" "$ACCEPTED_SCRIPT_86_CHECKSUM" \
  "${python_sources[@]}"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: a required Script 87 input is missing or unsafe.\n' >&2
    exit 2
  }
done
[[ -x "$INGEST_ENTRYPOINT" && -x "$PIPELINE_ENTRYPOINT" ]] || {
  printf 'BLOCKED: an installed entrypoint is not executable.\n' >&2
  exit 2
}

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'BLOCKED: %s identity changed.\n' "$3" >&2
    exit 2
  }
}
check_sha256 "$ACCEPTED_SCRIPT_86_REPORT" "$ACCEPTED_SCRIPT_86_REPORT_SHA256" 'accepted Script 86 report'
check_sha256 "$ACCEPTED_SCRIPT_86_ARTIFACT" "$ACCEPTED_SCRIPT_86_ARTIFACT_SHA256" 'accepted Script 86 artifact'
check_sha256 "$ACCEPTED_SCRIPT_86_CHECKSUM" "$ACCEPTED_SCRIPT_86_CHECKSUM_SHA256" 'accepted Script 86 checksum'
(cd "$(dirname -- "$ACCEPTED_SCRIPT_86_ARTIFACT")" && sha256sum --check --strict "$(basename -- "$ACCEPTED_SCRIPT_86_CHECKSUM")" >/dev/null) || {
  printf 'BLOCKED: accepted Script 86 artifact failed checksum verification.\n' >&2
  exit 2
}
for fact in \
  'configured_live_ingestion_qualification=pass' \
  'temporary_database_dropped=true;accepted_database_unchanged=true' \
  'configured_live_ingestion_target_evaluation=pass' \
  'cleanup_remote_temporary_files=removed' \
  'local_artifact_recovery=pass;basis=validated_exact_contract;live_rerun=false' \
  'script_86_configured_live_ingestion_target=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_SCRIPT_86_REPORT" || {
    printf 'BLOCKED: an accepted Script 86 fact is absent.\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$INGEST_ENTRYPOINT" "$PIPELINE_ENTRYPOINT" "$MODULE" "$MODULE_TEST" "$EVALUATOR" "${python_sources[@]}"
for neutral_source in "$INGEST_ENTRYPOINT" "$PIPELINE_ENTRYPOINT" "$MODULE"; do
  if grep -Eq '(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)' "$neutral_source" || grep -Eiq 'phase[-_ ]?[0-9]+|Danko|org[_ -]?lab|Agent|repository' "$neutral_source"; then
    printf 'BLOCKED: development or environment jargon found in an installed source.\n' >&2
    exit 2
  fi
done

work_root="$(mktemp -d /tmp/ishikawa-script-87.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-87.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  printf 'script_87_installed_ingestion_entrypoint=blocked;reason=test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$test_result" | awk '{print $1}')" "$(stat -c '%s' "$test_result")" >&2
  exit 1
}
grep -Fq 'Ran 316 tests' "$test_result" || {
  printf 'script_87_installed_ingestion_entrypoint=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_87_installed_ingestion_entrypoint=blocked;reason=test_pass_marker_absent\n' >&2
  exit 1
}

temporary_artifact="$work_root/installed-ingestion-entrypoint.json"
evaluation_result="$work_root/evaluation.txt"
evaluation_error="$work_root/evaluation-error.txt"
if ! PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B "$EVALUATOR" \
  --python-root "$PYTHON_ROOT" \
  --ingest-entrypoint "$INGEST_ENTRYPOINT" \
  --pipeline-entrypoint "$PIPELINE_ENTRYPOINT" \
  --runtime-config-root "$RUNTIME_CONFIG_ROOT" \
  --operator-config-root "$OPERATOR_CONFIG_ROOT" \
  --capture "$CAPTURE" --normalize "$NORMALIZE" --chunk "$CHUNK" --embed "$EMBED" \
  --output "$temporary_artifact" >"$evaluation_result" 2>"$evaluation_error"; then
  printf 'script_87_installed_ingestion_entrypoint=blocked;reason=entrypoint_evaluation_failed;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$evaluation_error" | awk '{print $1}')" "$(stat -c '%s' "$evaluation_error")" >&2
  exit 1
fi
for fact in \
  'command=ishikawa-ingest;pipeline_command=ishikawa-produce-artifacts' \
  'operator_modes=validate-only,publish;manifest_input=pending_filename_only' \
  'product_root=derived_from_executable;path_override_arguments=false;secret_arguments=false' \
  'runtime_assembly_calls=2;credential_reads=0;database_contact=false;model_call=false' \
  'content_addressed_artifacts=3;retention_idempotent=true;conflict_behavior=fail_closed' \
  'installed_operator_ingestion_entrypoint_qualification=pass'; do
  grep -Fqx "$fact" "$evaluation_result" || {
    printf 'script_87_installed_ingestion_entrypoint=blocked;reason=evaluation_contract_mismatch\n' >&2
    exit 1
  }
done

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
module_sha256="$(sha256sum "$MODULE" | awk '{print $1}')"
test_sha256="$(sha256sum "$MODULE_TEST" | awk '{print $1}')"
contract_sha256="$(sha256sum "$CONTRACT" | awk '{print $1}')"
ingest_sha256="$(sha256sum "$INGEST_ENTRYPOINT" | awk '{print $1}')"
pipeline_sha256="$(sha256sum "$PIPELINE_ENTRYPOINT" | awk '{print $1}')"
artifact_sha256="$(sha256sum "$temporary_artifact" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$temporary_artifact")"

if [[ "$validate_only" == true ]]; then
  cat "$evaluation_result"
  printf '%s\n' \
    'purpose=validate_installed_operator_ingestion_entrypoint' \
    'target_contact=false;database_contact=false;model_call=false;credential_read=false' \
    "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256;module_sha256=$module_sha256;test_sha256=$test_sha256" \
    "contract_sha256=$contract_sha256;ingest_entrypoint_sha256=$ingest_sha256;pipeline_entrypoint_sha256=$pipeline_sha256" \
    "accepted_script_86_report_sha256=$ACCEPTED_SCRIPT_86_REPORT_SHA256;accepted_script_86_artifact_sha256=$ACCEPTED_SCRIPT_86_ARTIFACT_SHA256" \
    "qualification_artifact_sha256=$artifact_sha256;qualification_artifact_bytes=$artifact_bytes" \
    'local_tests=316;failures=0;errors=0' \
    'script_87_installed_ingestion_entrypoint_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/installed_ingestion_entrypoint_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  printf 'script_87_installed_ingestion_entrypoint=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
cp -- "$temporary_artifact" "$artifact_path"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true
(cd "$ARTIFACT_ROOT" && sha256sum --check --strict "$(basename -- "$checksum_path")" >/dev/null) || {
  printf 'script_87_installed_ingestion_entrypoint=blocked;reason=artifact_checksum_verification_failed\n' >&2
  exit 1
}

report_path="$(mktemp "$REPORT_ROOT/installed_ingestion_entrypoint_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=qualify_installed_operator_ingestion_entrypoint'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256;module_sha256=$module_sha256;test_sha256=$test_sha256"
emit "contract_sha256=$contract_sha256;ingest_entrypoint_sha256=$ingest_sha256;pipeline_entrypoint_sha256=$pipeline_sha256"
emit "accepted_script_86_report_sha256=$ACCEPTED_SCRIPT_86_REPORT_SHA256;accepted_script_86_artifact_sha256=$ACCEPTED_SCRIPT_86_ARTIFACT_SHA256"
emit 'authorized_actions=read_checksum_bound_synthetic_inputs_run_local_tests_qualify_repository_free_installed_commands_retain_content_free_evidence'
emit 'non_actions=no_target_contact_no_database_contact_no_model_call_no_credential_read_no_source_document_or_vector_retention_no_schema_package_service_or_corpus_change'
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$artifact_bytes"
emit "accepted_checksum=$checksum_path;source_content_retained=false;vectors_retained=false;credential_values_retained=false"
emit 'local_tests=316;failures=0;errors=0'
emit "script_87_installed_ingestion_entrypoint=pass;local_report=$report_path;next_gate=assemble_portable_ishikawa_installation_package"
chmod 0600 "$report_path" 2>/dev/null || true
