#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the native singleton Nomic query-embedding adapter and the native
#   Gemma scope and grounded-generation adapters without target contact.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/64_qualify_native_dependency_adapters.sh --run

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
readonly API_PROFILE="$ISHIKAWA_ROOT/config/templates/api_profile.yaml"
readonly SCOPE_PROFILE="$ISHIKAWA_ROOT/config/templates/scope_profile.yaml"
readonly RECONSTRUCTION_PROFILE="$ISHIKAWA_ROOT/config/templates/reconstruction_profile.yaml"
readonly MODULE="$PYTHON_ROOT/ishikawa/native_adapters.py"
readonly TESTS="$ISHIKAWA_ROOT/tests/test_native_adapters.py"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_native_dependency_adapters.py"
readonly CONTRACT="$ISHIKAWA_ROOT/docs/NATIVE_DEPENDENCY_ADAPTERS.md"
readonly ACCEPTED_SCRIPT_63_REPORT="$REPO_ROOT/local/reports/ishikawa-retrieval-api-orchestrator/retrieval_api_orchestrator_20261020T053943Z_gDRV4m.txt"
readonly ACCEPTED_SCRIPT_63_REPORT_SHA256='16ad6157bfcab69d2e17bf10c380bd0a097c44281f7021cc705ec155d4edcf05'
readonly ACCEPTED_SCRIPT_63_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/retrieval-api-orchestrator/retrieval_service_orchestrator_qualification_20261020T053943Z.json"
readonly ACCEPTED_SCRIPT_63_ARTIFACT_SHA256='f7d1fb32866ea199416aa77b4186e63e86bac58252c4f5b201e2146a79349007'
readonly ACCEPTED_SCRIPT_56_REPORT="$REPO_ROOT/local/reports/ishikawa-relevance-query-embedding/relevance_query_embedding_20261020T042140Z_knr636.txt"
readonly ACCEPTED_SCRIPT_56_REPORT_SHA256='e608b9e7be0969e25185e1de4467cde3e4617bb0caa145b37c924d5865044e23'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-native-dependency-adapters"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/native-dependency-adapters"

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
for source in \
  "$TEST_RUNNER" "$API_PROFILE" "$SCOPE_PROFILE" "$RECONSTRUCTION_PROFILE" \
  "$MODULE" "$TESTS" "$EVALUATOR" "$CONTRACT" \
  "$ACCEPTED_SCRIPT_63_REPORT" "$ACCEPTED_SCRIPT_63_ARTIFACT" \
  "$ACCEPTED_SCRIPT_56_REPORT"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: a required Script 64 input is missing or unsafe.\n' >&2
    exit 2
  }
done
[[ "$(sha256sum "$ACCEPTED_SCRIPT_63_REPORT" | awk '{print $1}')" == "$ACCEPTED_SCRIPT_63_REPORT_SHA256" ]] || {
  printf 'BLOCKED: accepted Script 63 report identity changed.\n' >&2
  exit 2
}
[[ "$(sha256sum "$ACCEPTED_SCRIPT_63_ARTIFACT" | awk '{print $1}')" == "$ACCEPTED_SCRIPT_63_ARTIFACT_SHA256" ]] || {
  printf 'BLOCKED: accepted Script 63 artifact identity changed.\n' >&2
  exit 2
}
[[ "$(sha256sum "$ACCEPTED_SCRIPT_56_REPORT" | awk '{print $1}')" == "$ACCEPTED_SCRIPT_56_REPORT_SHA256" ]] || {
  printf 'BLOCKED: accepted Nomic query-embedding report identity changed.\n' >&2
  exit 2
}
for fact in \
  'retrieval_service_orchestrator_qualification=pass' \
  'local_tests=223;failures=0;errors=0' \
  'script_63_retrieval_api_orchestrator=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_SCRIPT_63_REPORT" || {
    printf 'BLOCKED: an accepted Script 63 fact is absent.\n' >&2
    exit 2
  }
done
for fact in \
  'model_identity=pass tokenizer_identity=pass tokenizer_service_agreement=pass' \
  'embeddings=pass dimension=768' \
  'embedding_space_id=fd970d304662357a07f7712639bdc0c70cc7e72b22f04c126acce57a6f9143a3' \
  'script_56_relevance_query_embedding=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_SCRIPT_56_REPORT" || {
    printf 'BLOCKED: an accepted Nomic query-embedding fact is absent.\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$MODULE" "$TESTS" "$EVALUATOR"

work_root="$(mktemp -d /tmp/ishikawa-script-64.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-64.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  cat "$test_result" >&2
  printf 'script_64_native_dependency_adapters=blocked;reason=test_regression\n' >&2
  exit 1
}
grep -Fq 'Ran 233 tests' "$test_result" || {
  printf 'script_64_native_dependency_adapters=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_64_native_dependency_adapters=blocked;reason=test_pass_marker_absent\n' >&2
  exit 1
}

api_profile_sha256="$(sha256sum "$API_PROFILE" | awk '{print $1}')"
scope_profile_sha256="$(sha256sum "$SCOPE_PROFILE" | awk '{print $1}')"
reconstruction_profile_sha256="$(sha256sum "$RECONSTRUCTION_PROFILE" | awk '{print $1}')"
temporary_artifact="$work_root/native-dependency-adapter-qualification.json"
evaluation_result="$work_root/evaluation.txt"
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B "$EVALUATOR" \
  --api-profile "$API_PROFILE" --expected-api-profile-sha256 "$api_profile_sha256" \
  --scope-profile "$SCOPE_PROFILE" --expected-scope-profile-sha256 "$scope_profile_sha256" \
  --reconstruction-profile "$RECONSTRUCTION_PROFILE" --expected-reconstruction-profile-sha256 "$reconstruction_profile_sha256" \
  --output "$temporary_artifact" >"$evaluation_result"
for fact in \
  'query_embedding_model=nomic-ai/nomic-embed-text-v1.5;query_prefix=search_query: ;dimension=768;singleton=true' \
  'embedding_space_id=fd970d304662357a07f7712639bdc0c70cc7e72b22f04c126acce57a6f9143a3;vector_transform=none;distance=cosine' \
  'scope_adapter=native;generation_adapter=native;source_metadata_resolution=required' \
  'transport=standard_library_http;streaming=false;retry=false;runtime_credentials=true' \
  'network_contact=false;database_contact=false;model_call=false;credential_read=false' \
  'native_dependency_adapter_qualification=pass'; do
  grep -Fq "$fact" "$evaluation_result" || {
    cat "$evaluation_result" >&2
    printf 'script_64_native_dependency_adapters=blocked;reason=adapter_evaluation_failed\n' >&2
    exit 1
  }
done

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
module_sha256="$(sha256sum "$MODULE" | awk '{print $1}')"
tests_sha256="$(sha256sum "$TESTS" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
contract_sha256="$(sha256sum "$CONTRACT" | awk '{print $1}')"
artifact_sha256="$(sha256sum "$temporary_artifact" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$temporary_artifact")"
if [[ "$validate_only" == true ]]; then
  cat "$evaluation_result"
  printf '%s\n' \
    'purpose=validate_native_scope_generation_and_query_embedding_adapters' \
    'target_contact=false;network_access=false;database_contact=false;model_call=false;credential_read=false;listener_started=false' \
    "script_sha256=$script_sha256;module_sha256=$module_sha256;tests_sha256=$tests_sha256;evaluator_sha256=$evaluator_sha256" \
    "api_profile_sha256=$api_profile_sha256;scope_profile_sha256=$scope_profile_sha256;reconstruction_profile_sha256=$reconstruction_profile_sha256;contract_sha256=$contract_sha256" \
    "accepted_script_63_report_sha256=$ACCEPTED_SCRIPT_63_REPORT_SHA256;accepted_script_63_artifact_sha256=$ACCEPTED_SCRIPT_63_ARTIFACT_SHA256;accepted_script_56_report_sha256=$ACCEPTED_SCRIPT_56_REPORT_SHA256" \
    "qualification_artifact_sha256=$artifact_sha256;qualification_artifact_bytes=$artifact_bytes" \
    'local_tests=233;failures=0;errors=0' \
    'script_64_native_dependency_adapters_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/native_dependency_adapter_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  printf 'script_64_native_dependency_adapters=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
cp -- "$temporary_artifact" "$artifact_path"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true

report_path="$(mktemp "$REPORT_ROOT/native_dependency_adapters_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=qualify_native_scope_generation_and_query_embedding_adapters'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;module_sha256=$module_sha256;tests_sha256=$tests_sha256;evaluator_sha256=$evaluator_sha256"
emit "api_profile_sha256=$api_profile_sha256;scope_profile_sha256=$scope_profile_sha256;reconstruction_profile_sha256=$reconstruction_profile_sha256;contract_sha256=$contract_sha256"
emit "accepted_script_63_report_sha256=$ACCEPTED_SCRIPT_63_REPORT_SHA256;accepted_script_63_artifact_sha256=$ACCEPTED_SCRIPT_63_ARTIFACT_SHA256;accepted_script_56_report_sha256=$ACCEPTED_SCRIPT_56_REPORT_SHA256"
emit 'authorized_actions=read_checksum_bound_local_evidence_run_local_tests_qualify_native_dependency_adapters_retain_content_free_acceptance_evidence'
emit 'non_actions=no_target_contact_no_network_access_no_database_contact_no_model_call_no_credential_read_no_listener_start_no_schema_change'
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$artifact_bytes"
emit "accepted_checksum=$checksum_path;raw_content_retained=false"
emit 'local_tests=233;failures=0;errors=0'
emit "script_64_native_dependency_adapters=pass;local_report=$report_path;next_gate=implement_standalone_query_resolution"
chmod 0600 "$report_path" 2>/dev/null || true
