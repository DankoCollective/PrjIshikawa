#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the portable, dependency-injected Ishikawa ingestion command
#   boundary without contacting a database, model endpoint, or target host.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/81_qualify_portable_operator_ingestion_entrypoint.sh --run

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
readonly EVALUATOR="$SCRIPT_DIR/evaluate_portable_operator_ingestion_entrypoint.py"
readonly COMMAND_MODULE="$PYTHON_ROOT/ishikawa/ingestion_command.py"
readonly COMMAND_TEST="$ISHIKAWA_ROOT/tests/test_ingestion_command.py"
readonly CONFIG_ROOT="$ISHIKAWA_ROOT/tests/fixtures/pipeline_writer"
readonly SOURCE_ROOT="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/anderson-upload"
readonly ACCEPTED_SCRIPT_80_REPORT="$REPO_ROOT/local/reports/ishikawa-live-producer-ingestion/live_producer_ingestion_20261020T184453Z_aAGIuk.txt"
readonly ACCEPTED_SCRIPT_80_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/live-producer-ingestion/live_producer_ingestion_qualification_20261020T184453Z.json"
readonly ACCEPTED_SCRIPT_80_CHECKSUM="$ACCEPTED_SCRIPT_80_ARTIFACT.sha256"
readonly ACCEPTED_SCRIPT_80_REPORT_SHA256='c2eb420ecd277d86f5b0baed6b18bd7d5bb67757f775c2a4629d66b3c720f11c'
readonly ACCEPTED_SCRIPT_80_ARTIFACT_SHA256='5dd75b1b8496118d731ce4d860adadd4f51e76cea675863d2cbfcc7fd314b1ea'
readonly ACCEPTED_SCRIPT_80_CHECKSUM_SHA256='458bb6770537986cfe3cdfcdae1b8f38cc5636b35df1aa1c2c926b64472d5cd0'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-portable-ingestion-entrypoint"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/portable-ingestion-entrypoint"

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
  "$TEST_RUNNER" "$EVALUATOR" "$COMMAND_MODULE" "$COMMAND_TEST" \
  "$CONFIG_ROOT/document_classes.yaml" "$CONFIG_ROOT/document_catalog.yaml" "$CONFIG_ROOT/ingestion_manifest.yaml" \
  "$ACCEPTED_SCRIPT_80_REPORT" "$ACCEPTED_SCRIPT_80_ARTIFACT" "$ACCEPTED_SCRIPT_80_CHECKSUM" \
  "${python_sources[@]}" "${source_pdfs[@]}"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: a required Script 81 input is missing or unsafe.\n' >&2
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
check_sha256 "$ACCEPTED_SCRIPT_80_REPORT" "$ACCEPTED_SCRIPT_80_REPORT_SHA256" 'accepted Script 80 report'
check_sha256 "$ACCEPTED_SCRIPT_80_ARTIFACT" "$ACCEPTED_SCRIPT_80_ARTIFACT_SHA256" 'accepted Script 80 artifact'
check_sha256 "$ACCEPTED_SCRIPT_80_CHECKSUM" "$ACCEPTED_SCRIPT_80_CHECKSUM_SHA256" 'accepted Script 80 checksum'
(cd "$(dirname -- "$ACCEPTED_SCRIPT_80_ARTIFACT")" && sha256sum --check --strict "$(basename -- "$ACCEPTED_SCRIPT_80_CHECKSUM")" >/dev/null) || {
  printf 'BLOCKED: accepted Script 80 artifact failed checksum verification.\n' >&2
  exit 2
}
for fact in \
  'live_producer_ingestion_connection_qualification=pass' \
  'script_80_live_producer_ingestion=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_SCRIPT_80_REPORT" || {
    printf 'BLOCKED: an accepted Script 80 fact is absent.\n' >&2
    exit 2
  }
done
grep -Fq '"prepared_documents":6' "$ACCEPTED_SCRIPT_80_ARTIFACT" || {
  printf 'BLOCKED: accepted Script 80 document count is absent.\n' >&2
  exit 2
}

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$EVALUATOR" "$COMMAND_TEST" "${python_sources[@]}"

work_root="$(mktemp -d /tmp/ishikawa-script-81.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-81.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  printf 'script_81_portable_ingestion_entrypoint=blocked;reason=test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$test_result" | awk '{print $1}')" "$(stat -c '%s' "$test_result")" >&2
  exit 1
}
grep -Fq 'Ran 293 tests' "$test_result" || {
  printf 'script_81_portable_ingestion_entrypoint=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_81_portable_ingestion_entrypoint=blocked;reason=test_pass_marker_absent\n' >&2
  exit 1
}

temporary_artifact="$work_root/portable-ingestion-entrypoint.json"
evaluation_result="$work_root/evaluation.txt"
evaluation_error="$work_root/evaluation-error.txt"
if ! PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B "$EVALUATOR" \
  --config-root "$CONFIG_ROOT" \
  --source-root "$SOURCE_ROOT" \
  --output "$temporary_artifact" >"$evaluation_result" 2>"$evaluation_error"; then
  printf 'script_81_portable_ingestion_entrypoint=blocked;reason=entrypoint_evaluation_failed;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$evaluation_error" | awk '{print $1}')" "$(stat -c '%s' "$evaluation_error")" >&2
  exit 1
fi
for fact in \
  'entrypoint_scenarios=5;validate_only=pass;publish=pass;missing_producer=pass;unknown_option=pass;runtime_failure=pass' \
  'validate_only_dependencies=producer_0,writer_0;publish_dependencies=producer_1,writer_1' \
  'connection_lifecycle=opened_3,closed_3;predependency_rejections=2' \
  'secrets_in_arguments=false;unexpected_details_exposed=false;source_paths_exposed=false' \
  'target_contact=false;database_contact=false;model_call=false;credential_read=false' \
  'portable_operator_ingestion_entrypoint_qualification=pass'; do
  grep -Fqx "$fact" "$evaluation_result" || {
    printf 'script_81_portable_ingestion_entrypoint=blocked;reason=evaluation_contract_mismatch\n' >&2
    exit 1
  }
done

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
command_sha256="$(sha256sum "$COMMAND_MODULE" | awk '{print $1}')"
command_test_sha256="$(sha256sum "$COMMAND_TEST" | awk '{print $1}')"
artifact_sha256="$(sha256sum "$temporary_artifact" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$temporary_artifact")"

if [[ "$validate_only" == true ]]; then
  cat "$evaluation_result"
  printf '%s\n' \
    'purpose=validate_portable_operator_ingestion_entrypoint' \
    'target_contact=false;database_contact=false;model_call=false;credential_read=false' \
    "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256" \
    "command_sha256=$command_sha256;command_test_sha256=$command_test_sha256" \
    "accepted_script_80_report_sha256=$ACCEPTED_SCRIPT_80_REPORT_SHA256;accepted_script_80_artifact_sha256=$ACCEPTED_SCRIPT_80_ARTIFACT_SHA256" \
    "qualification_artifact_sha256=$artifact_sha256;qualification_artifact_bytes=$artifact_bytes" \
    'local_tests=293;failures=0;errors=0' \
    'script_81_portable_ingestion_entrypoint_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/portable_ingestion_entrypoint_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  printf 'script_81_portable_ingestion_entrypoint=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
cp -- "$temporary_artifact" "$artifact_path"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true

report_path="$(mktemp "$REPORT_ROOT/portable_ingestion_entrypoint_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=qualify_portable_operator_ingestion_entrypoint'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256"
emit "command_sha256=$command_sha256;command_test_sha256=$command_test_sha256"
emit "accepted_script_80_report_sha256=$ACCEPTED_SCRIPT_80_REPORT_SHA256;accepted_script_80_artifact_sha256=$ACCEPTED_SCRIPT_80_ARTIFACT_SHA256"
emit 'authorized_actions=read_checksum_bound_synthetic_inputs_run_local_tests_exercise_dependency_injected_operator_command_retain_content_free_evidence'
emit 'non_actions=no_target_contact_no_database_contact_no_model_call_no_credential_read_no_source_document_retention_no_schema_package_service_or_corpus_change'
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$artifact_bytes"
emit "accepted_checksum=$checksum_path;source_content_retained=false;vectors_retained=false"
emit 'local_tests=293;failures=0;errors=0'
emit "script_81_portable_ingestion_entrypoint=pass;local_report=$report_path;next_gate=assemble_concrete_operator_ingestion_runtime"
chmod 0600 "$report_path" 2>/dev/null || true
