#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify configuration-to-runtime assembly for the Ishikawa Retrieval API
#   without reading credentials or contacting PostgreSQL, Gemma, or Nomic.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/70_qualify_configured_retrieval_service_runtime.sh --run

usage() {
  sed -n '3,10p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Run locally and retain content-free qualification evidence.' \
    '  --validate-only Validate sources and runtime assembly without retaining evidence.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$ISHIKAWA_ROOT/application/python"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly CONFIG_ROOT="$ISHIKAWA_ROOT/config/templates"
readonly RUNTIME_MODULE="$PYTHON_ROOT/ishikawa/runtime.py"
readonly TOKENIZATION_MODULE="$PYTHON_ROOT/ishikawa/tokenization.py"
readonly RUNTIME_TESTS="$ISHIKAWA_ROOT/tests/test_runtime.py"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_configured_retrieval_runtime.py"
readonly CONTRACT="$ISHIKAWA_ROOT/docs/RETRIEVAL_API_SERVICE.md"
readonly ADAPTER_CONTRACT="$ISHIKAWA_ROOT/docs/NATIVE_DEPENDENCY_ADAPTERS.md"
readonly ACCEPTED_SCRIPT_69_REPORT="$REPO_ROOT/local/reports/ishikawa-native-http-listener/native_http_listener_20261020T142526Z_oyc62q.txt"
readonly ACCEPTED_SCRIPT_69_REPORT_SHA256='50eaa02bd2e1abe17c25de52ee8c3e32424cad3cd1c55aacf41e8b5cc5686846'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-configured-runtime"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/configured-runtime"

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

readonly CONFIG_FILES=(
  api_profile.yaml deployment.yaml injection_profile.yaml method_profile.yaml
  query_resolution_profile.yaml reconstruction_profile.yaml relationship_types.yaml
  relevance_profile.yaml retrieval_service_profile.yaml runtime_dependencies.yaml
  scope_profile.yaml sufficiency_profile.yaml
)
for source in \
  "$TEST_RUNNER" "$RUNTIME_MODULE" "$TOKENIZATION_MODULE" "$RUNTIME_TESTS" \
  "$EVALUATOR" "$CONTRACT" "$ADAPTER_CONTRACT" "$ACCEPTED_SCRIPT_69_REPORT"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: a required Script 70 input is missing or unsafe.\n' >&2
    exit 2
  }
done
for filename in "${CONFIG_FILES[@]}"; do
  source="$CONFIG_ROOT/$filename"
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: a required runtime profile is missing or unsafe.\n' >&2
    exit 2
  }
done
[[ "$(sha256sum "$ACCEPTED_SCRIPT_69_REPORT" | awk '{print $1}')" == "$ACCEPTED_SCRIPT_69_REPORT_SHA256" ]] || {
  printf 'BLOCKED: accepted Script 69 report identity changed.\n' >&2
  exit 2
}
for fact in \
  'listener_endpoint=127.0.0.1:1384;method=POST;path=/v1/chat;streaming=false' \
  'listener_shutdown=pass;port_1384_after_test=free' \
  'native_retrieval_http_listener_qualification=pass' \
  'script_69_native_http_listener=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_SCRIPT_69_REPORT" || {
    printf 'BLOCKED: an accepted Script 69 fact is absent.\n' >&2
    exit 2
  }
done

bash -n "$TEST_RUNNER"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$RUNTIME_MODULE" "$TOKENIZATION_MODULE" "$RUNTIME_TESTS" "$EVALUATOR"

work_root="$(mktemp -d /tmp/ishikawa-script-70.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-70.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  printf 'script_70_configured_runtime=blocked;reason=test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$test_result" | awk '{print $1}')" "$(stat -c '%s' "$test_result")" >&2
  exit 1
}
grep -Fq 'Ran 270 tests' "$test_result" || {
  printf 'script_70_configured_runtime=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_70_configured_runtime=blocked;reason=test_pass_marker_absent\n' >&2
  exit 1
}

temporary_artifact="$work_root/configured-runtime-qualification.json"
evaluation_result="$work_root/evaluation.txt"
evaluation_error="$work_root/evaluation-error.txt"
if ! PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B "$EVALUATOR" \
  --config-root "$CONFIG_ROOT" --output "$temporary_artifact" \
  >"$evaluation_result" 2>"$evaluation_error"; then
  printf 'script_70_configured_runtime=blocked;reason=runtime_evaluation_failed;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$evaluation_error" | awk '{print $1}')" "$(stat -c '%s' "$evaluation_error")" >&2
  exit 1
fi
for fact in \
  'runtime_components=gemma_scope,gemma_query_resolution,nomic_query_embedding,postgresql_retrieval,gemma_tokenization,gemma_grounded_generation' \
  'routes=retrieval_/v1/chat;generation_/v1/chat/completions;tokenization_/tokenize;embedding_/v1/embeddings' \
  'postgresql=rag_catalog;role=rag_retrieval;transaction=repeatable_read_read_only;source_lookup=active_views' \
  'secret_boundary=environment_names_only;credential_values_read=false;credentials_in_yaml=false' \
  'direct_injection_short_circuit=pass;dependency_calls=0;result=security-rejected' \
  'listener_factory=configured;listener_started=false;target_contact=false;database_contact=false;model_call=false' \
  'configured_retrieval_runtime_qualification=pass'; do
  grep -Fqx "$fact" "$evaluation_result" || {
    printf 'script_70_configured_runtime=blocked;reason=runtime_contract_mismatch\n' >&2
    exit 1
  }
done

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
runtime_module_sha256="$(sha256sum "$RUNTIME_MODULE" | awk '{print $1}')"
tokenization_module_sha256="$(sha256sum "$TOKENIZATION_MODULE" | awk '{print $1}')"
tests_sha256="$(sha256sum "$RUNTIME_TESTS" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
contract_sha256="$(sha256sum "$CONTRACT" | awk '{print $1}')"
adapter_contract_sha256="$(sha256sum "$ADAPTER_CONTRACT" | awk '{print $1}')"
configuration_manifest="$work_root/configuration-sha256.txt"
for filename in "${CONFIG_FILES[@]}"; do
  printf '%s  %s\n' "$(sha256sum "$CONFIG_ROOT/$filename" | awk '{print $1}')" "$filename"
done >"$configuration_manifest"
configuration_manifest_sha256="$(sha256sum "$configuration_manifest" | awk '{print $1}')"
artifact_sha256="$(sha256sum "$temporary_artifact" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$temporary_artifact")"

if [[ "$validate_only" == true ]]; then
  cat "$evaluation_result"
  printf '%s\n' \
    'purpose=validate_configured_retrieval_service_runtime' \
    'target_contact=false;network_access=loopback_test_only;database_contact=false;model_call=false;credential_read=false' \
    "script_sha256=$script_sha256;runtime_module_sha256=$runtime_module_sha256;tokenization_module_sha256=$tokenization_module_sha256;tests_sha256=$tests_sha256;evaluator_sha256=$evaluator_sha256" \
    "configuration_manifest_sha256=$configuration_manifest_sha256;contract_sha256=$contract_sha256;adapter_contract_sha256=$adapter_contract_sha256" \
    "accepted_script_69_report_sha256=$ACCEPTED_SCRIPT_69_REPORT_SHA256" \
    "qualification_artifact_sha256=$artifact_sha256;qualification_artifact_bytes=$artifact_bytes" \
    'local_tests=270;failures=0;errors=0' \
    'script_70_configured_runtime_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/configured_runtime_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  printf 'script_70_configured_runtime=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
cp -- "$temporary_artifact" "$artifact_path"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true

report_path="$(mktemp "$REPORT_ROOT/configured_runtime_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=qualify_configuration_to_retrieval_service_runtime_assembly'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;runtime_module_sha256=$runtime_module_sha256;tokenization_module_sha256=$tokenization_module_sha256;tests_sha256=$tests_sha256;evaluator_sha256=$evaluator_sha256"
emit "configuration_manifest_sha256=$configuration_manifest_sha256;contract_sha256=$contract_sha256;adapter_contract_sha256=$adapter_contract_sha256"
emit "accepted_script_69_report_sha256=$ACCEPTED_SCRIPT_69_REPORT_SHA256"
emit 'authorized_actions=read_checksum_bound_local_evidence_run_local_tests_bind_temporary_loopback_test_listeners_validate_configuration_assemble_runtime_with_injected_dependencies_retain_content_free_acceptance_evidence'
emit 'non_actions=no_target_contact_no_nonloopback_network_access_no_database_contact_no_model_call_no_credential_read_no_service_start_no_package_or_schema_change'
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$artifact_bytes"
emit "accepted_checksum=$checksum_path;configuration_values_retained=false;secret_values_retained=false"
emit 'local_tests=270;failures=0;errors=0'
emit "script_70_configured_runtime=pass;local_report=$report_path;next_gate=qualify_configured_generation_tokenizer_endpoint"
chmod 0600 "$report_path" 2>/dev/null || true
