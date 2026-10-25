#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the native read-only PostgreSQL retrieval port, resolved-query-only
#   embedding, code-owned filters, fusion, hydration, and evidence gating.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/66_qualify_native_postgresql_retrieval_adapter.sh --run

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
readonly RESOLUTION_PROFILE="$ISHIKAWA_ROOT/config/templates/query_resolution_profile.yaml"
readonly METHOD_PROFILE="$ISHIKAWA_ROOT/config/templates/method_profile.yaml"
readonly RECONSTRUCTION_PROFILE="$ISHIKAWA_ROOT/config/templates/reconstruction_profile.yaml"
readonly RELEVANCE_PROFILE="$ISHIKAWA_ROOT/config/templates/relevance_profile.yaml"
readonly SUFFICIENCY_PROFILE="$ISHIKAWA_ROOT/config/templates/sufficiency_profile.yaml"
readonly RELATIONSHIP_PROFILE="$ISHIKAWA_ROOT/config/templates/relationship_types.yaml"
readonly RETRIEVAL_MODULE="$PYTHON_ROOT/ishikawa/retrieval.py"
readonly ADAPTER_MODULE="$PYTHON_ROOT/ishikawa/postgres_retrieval.py"
readonly SERVICE_MODULE="$PYTHON_ROOT/ishikawa/retrieval_service.py"
readonly GENERATION_MODULE="$PYTHON_ROOT/ishikawa/generation.py"
readonly ADAPTER_TESTS="$ISHIKAWA_ROOT/tests/test_postgres_retrieval.py"
readonly SERVICE_TESTS="$ISHIKAWA_ROOT/tests/test_retrieval_service.py"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_postgres_retrieval_adapter.py"
readonly CONTRACT="$ISHIKAWA_ROOT/docs/POSTGRES_RETRIEVAL_ADAPTER.md"
readonly ACCEPTED_SCRIPT_65_REPORT="$REPO_ROOT/local/reports/ishikawa-query-resolution/query_resolution_20261020T055501Z_4XlAsO.txt"
readonly ACCEPTED_SCRIPT_65_REPORT_SHA256='1e87f767c7c06f1d501bc74233f01fb149fa4af80f50e196d0d4035b2736adab'
readonly ACCEPTED_SCRIPT_65_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/query-resolution/query_resolution_qualification_20261020T055501Z.json"
readonly ACCEPTED_SCRIPT_65_ARTIFACT_SHA256='543601d889429235e2462cde6bc2ef5a37417e8e073fe9bc0c6057062a5d2b45'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-postgresql-retrieval-adapter"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/postgresql-retrieval-adapter"

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
  "$TEST_RUNNER" "$API_PROFILE" "$RESOLUTION_PROFILE" "$METHOD_PROFILE" \
  "$RECONSTRUCTION_PROFILE" "$RELEVANCE_PROFILE" "$SUFFICIENCY_PROFILE" \
  "$RELATIONSHIP_PROFILE" \
  "$RETRIEVAL_MODULE" "$ADAPTER_MODULE" "$SERVICE_MODULE" "$GENERATION_MODULE" \
  "$ADAPTER_TESTS" "$SERVICE_TESTS" "$EVALUATOR" "$CONTRACT" \
  "$ACCEPTED_SCRIPT_65_REPORT" "$ACCEPTED_SCRIPT_65_ARTIFACT"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: a required Script 66 input is missing or unsafe.\n' >&2
    exit 2
  }
done
[[ "$(sha256sum "$ACCEPTED_SCRIPT_65_REPORT" | awk '{print $1}')" == "$ACCEPTED_SCRIPT_65_REPORT_SHA256" ]] || {
  printf 'BLOCKED: accepted Script 65 report identity changed.\n' >&2
  exit 2
}
[[ "$(sha256sum "$ACCEPTED_SCRIPT_65_ARTIFACT" | awk '{print $1}')" == "$ACCEPTED_SCRIPT_65_ARTIFACT_SHA256" ]] || {
  printf 'BLOCKED: accepted Script 65 artifact identity changed.\n' >&2
  exit 2
}
for fact in \
  'query_resolution_qualification=pass' \
  'local_tests=246;failures=0;errors=0' \
  'next_gate=implement_native_postgresql_retrieval_adapter'; do
  grep -Fq "$fact" "$ACCEPTED_SCRIPT_65_REPORT" || {
    printf 'BLOCKED: an accepted Script 65 fact is absent.\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$RETRIEVAL_MODULE" "$ADAPTER_MODULE" "$SERVICE_MODULE" "$GENERATION_MODULE" \
  "$ADAPTER_TESTS" "$SERVICE_TESTS" "$EVALUATOR"

work_root="$(mktemp -d /tmp/ishikawa-script-66.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-66.* && -d "$work_root" ]]; then
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
  printf 'script_66_postgresql_retrieval_adapter=blocked;reason=test_regression\n' >&2
  exit 1
}
grep -Fq 'Ran 250 tests' "$test_result" || {
  printf 'script_66_postgresql_retrieval_adapter=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_66_postgresql_retrieval_adapter=blocked;reason=test_pass_marker_absent\n' >&2
  exit 1
}

api_profile_sha256="$(sha256sum "$API_PROFILE" | awk '{print $1}')"
resolution_profile_sha256="$(sha256sum "$RESOLUTION_PROFILE" | awk '{print $1}')"
method_profile_sha256="$(sha256sum "$METHOD_PROFILE" | awk '{print $1}')"
reconstruction_profile_sha256="$(sha256sum "$RECONSTRUCTION_PROFILE" | awk '{print $1}')"
relevance_profile_sha256="$(sha256sum "$RELEVANCE_PROFILE" | awk '{print $1}')"
sufficiency_profile_sha256="$(sha256sum "$SUFFICIENCY_PROFILE" | awk '{print $1}')"
relationship_profile_sha256="$(sha256sum "$RELATIONSHIP_PROFILE" | awk '{print $1}')"
temporary_artifact="$work_root/postgresql-retrieval-adapter-qualification.json"
evaluation_result="$work_root/evaluation.txt"
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B "$EVALUATOR" \
  --api-profile "$API_PROFILE" --expected-api-profile-sha256 "$api_profile_sha256" \
  --resolution-profile "$RESOLUTION_PROFILE" --expected-resolution-profile-sha256 "$resolution_profile_sha256" \
  --method-profile "$METHOD_PROFILE" --expected-method-profile-sha256 "$method_profile_sha256" \
  --reconstruction-profile "$RECONSTRUCTION_PROFILE" --expected-reconstruction-profile-sha256 "$reconstruction_profile_sha256" \
  --relevance-profile "$RELEVANCE_PROFILE" --expected-relevance-profile-sha256 "$relevance_profile_sha256" \
  --sufficiency-profile "$SUFFICIENCY_PROFILE" --expected-sufficiency-profile-sha256 "$sufficiency_profile_sha256" \
  --relationship-profile "$RELATIONSHIP_PROFILE" --expected-relationship-profile-sha256 "$relationship_profile_sha256" \
  --output "$temporary_artifact" >"$evaluation_result"
for fact in \
  'retrieval_port=pass;database_role=rag_retrieval;transaction=repeatable_read_read_only;views=rag_search_only' \
  'query_embedding=resolved_query_only;full_transcript_embedded=false;singleton=true' \
  'candidate_lanes=exact,lexical,vector;fusion=reciprocal_rank_fusion;rrf_constant=60;fused_depth=20' \
  'filters=pre_candidate_and_post_hydration;source_identity=document_version' \
  'relevance=top3_citable_envelope;reconstruction=32k_budget;sufficiency=deterministic' \
  'relationship_expansion=deferred_to_next_gate;complete_procedure=deferred_to_next_gate' \
  'network_contact=false;database_contact=false;model_call=false;credential_read=false' \
  'postgres_retrieval_adapter_qualification=pass'; do
  grep -Fq "$fact" "$evaluation_result" || {
    cat "$evaluation_result" >&2
    printf 'script_66_postgresql_retrieval_adapter=blocked;reason=adapter_evaluation_failed\n' >&2
    exit 1
  }
done

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
retrieval_module_sha256="$(sha256sum "$RETRIEVAL_MODULE" | awk '{print $1}')"
adapter_module_sha256="$(sha256sum "$ADAPTER_MODULE" | awk '{print $1}')"
service_module_sha256="$(sha256sum "$SERVICE_MODULE" | awk '{print $1}')"
generation_module_sha256="$(sha256sum "$GENERATION_MODULE" | awk '{print $1}')"
adapter_tests_sha256="$(sha256sum "$ADAPTER_TESTS" | awk '{print $1}')"
service_tests_sha256="$(sha256sum "$SERVICE_TESTS" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
contract_sha256="$(sha256sum "$CONTRACT" | awk '{print $1}')"
artifact_sha256="$(sha256sum "$temporary_artifact" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$temporary_artifact")"
if [[ "$validate_only" == true ]]; then
  cat "$evaluation_result"
  printf '%s\n' \
    'purpose=validate_native_read_only_postgresql_retrieval_adapter' \
    'target_contact=false;network_access=false;database_contact=false;model_call=false;credential_read=false;listener_started=false' \
    "script_sha256=$script_sha256;retrieval_module_sha256=$retrieval_module_sha256;adapter_module_sha256=$adapter_module_sha256;service_module_sha256=$service_module_sha256;generation_module_sha256=$generation_module_sha256" \
    "adapter_tests_sha256=$adapter_tests_sha256;service_tests_sha256=$service_tests_sha256;evaluator_sha256=$evaluator_sha256;contract_sha256=$contract_sha256" \
    "api_profile_sha256=$api_profile_sha256;resolution_profile_sha256=$resolution_profile_sha256;method_profile_sha256=$method_profile_sha256" \
    "reconstruction_profile_sha256=$reconstruction_profile_sha256;relevance_profile_sha256=$relevance_profile_sha256;sufficiency_profile_sha256=$sufficiency_profile_sha256" \
    "accepted_script_65_report_sha256=$ACCEPTED_SCRIPT_65_REPORT_SHA256;accepted_script_65_artifact_sha256=$ACCEPTED_SCRIPT_65_ARTIFACT_SHA256" \
    "qualification_artifact_sha256=$artifact_sha256;qualification_artifact_bytes=$artifact_bytes" \
    'local_tests=250;failures=0;errors=0' \
    'script_66_postgresql_retrieval_adapter_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/postgresql_retrieval_adapter_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  printf 'script_66_postgresql_retrieval_adapter=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
cp -- "$temporary_artifact" "$artifact_path"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true

report_path="$(mktemp "$REPORT_ROOT/postgresql_retrieval_adapter_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=qualify_native_read_only_postgresql_retrieval_adapter'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;retrieval_module_sha256=$retrieval_module_sha256;adapter_module_sha256=$adapter_module_sha256;service_module_sha256=$service_module_sha256;generation_module_sha256=$generation_module_sha256"
emit "adapter_tests_sha256=$adapter_tests_sha256;service_tests_sha256=$service_tests_sha256;evaluator_sha256=$evaluator_sha256;contract_sha256=$contract_sha256"
emit "api_profile_sha256=$api_profile_sha256;resolution_profile_sha256=$resolution_profile_sha256;method_profile_sha256=$method_profile_sha256"
emit "reconstruction_profile_sha256=$reconstruction_profile_sha256;relevance_profile_sha256=$relevance_profile_sha256;sufficiency_profile_sha256=$sufficiency_profile_sha256"
emit "accepted_script_65_report_sha256=$ACCEPTED_SCRIPT_65_REPORT_SHA256;accepted_script_65_artifact_sha256=$ACCEPTED_SCRIPT_65_ARTIFACT_SHA256"
emit 'authorized_actions=read_checksum_bound_local_evidence_run_local_tests_qualify_postgresql_retrieval_adapter_retain_content_free_acceptance_evidence'
emit 'non_actions=no_target_contact_no_network_access_no_database_contact_no_model_call_no_credential_read_no_listener_start_no_schema_change'
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$artifact_bytes"
emit "accepted_checksum=$checksum_path;raw_content_retained=false"
emit 'local_tests=250;failures=0;errors=0'
emit "script_66_postgresql_retrieval_adapter=pass;local_report=$report_path;next_gate=implement_relationship_and_complete_procedure_retrieval_paths"
chmod 0600 "$report_path" 2>/dev/null || true
