#!/usr/bin/env bash
# Ingest corpus v3 into disposable PostgreSQL and qualify the complete v1.3 API.
#
# This is one execute/measure/analyze/self-validate gate. It does not modify an
# accepted database, corpus candidate, package, release, service, or remote host.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/201_ingest_and_qualify_isolated_synthetic_corpus_v3.sh --validate-only
#   bash ./phase-28-apisachi-tokuli/scripts/201_ingest_and_qualify_isolated_synthetic_corpus_v3.sh --run
#   bash ./phase-28-apisachi-tokuli/scripts/201_ingest_and_qualify_isolated_synthetic_corpus_v3.sh --validate-frontier
#   bash ./phase-28-apisachi-tokuli/scripts/201_ingest_and_qualify_isolated_synthetic_corpus_v3.sh --run-frontier

set -Eeuo pipefail
umask 077

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly PACKAGE_ROOT="$PYTHON_ROOT/ishikawa"
readonly CONFIG_ROOT="$PRODUCT_ROOT/config/templates"
readonly SCHEMA="$PRODUCT_ROOT/packaging/database/schema.sql"
readonly SERVICE_ENTRYPOINT="$PRODUCT_ROOT/scripts/ishikawa-retrieval-api"
readonly TEST_RUNNER="$PRODUCT_ROOT/scripts/run-local-validation-tests.sh"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly BUNDLE_BUILDER="$SCRIPT_DIR/prepare_synthetic_corpus_v3_ingestion_bundle.py"
readonly CAPTURE_ADAPTER="$SCRIPT_DIR/capture-pdf-extraction-observations.py"
readonly CHUNK_BUILDER="$SCRIPT_DIR/create-structural-chunk-candidates.py"
readonly EMBED_ADAPTER="$SCRIPT_DIR/embed_document_candidates_via_endpoint.py"
readonly INGESTION_RUNNER="$SCRIPT_DIR/run_isolated_synthetic_v2_ingestion.py"
readonly DATABASE_QUALIFIER="$SCRIPT_DIR/qualify_isolated_synthetic_corpus_v3_database.py"
readonly API_EVALUATOR="$SCRIPT_DIR/evaluate_v1_3_complete_api.py"
readonly MULTITURN_EVALUATOR="$SCRIPT_DIR/evaluate_v1_3_multiturn_resolution.py"
readonly CATALOG_ROUTING_EVALUATOR="$SCRIPT_DIR/evaluate_v1_3_catalog_routing.py"
readonly GENERATION_CAPTURE_PROXY="$SCRIPT_DIR/capture_v1_3_generation_exchange.py"
readonly COMPLETE_API_CASES="$PHASE_ROOT/reference/ishikawa-retrieval-api-cases-v1.3-corpus-v3.json"
readonly FRONTIER_API_CASES="$PHASE_ROOT/reference/ishikawa-v1.3-corpus-v3-frontier-cases.json"
readonly PIPELINE_EXECUTABLE="$SCRIPT_DIR/ishikawa-produce-artifacts"
readonly ARTIFACT_PIPELINE="$PACKAGE_ROOT/artifact_pipeline.py"
readonly INGESTION_COMMAND="$PACKAGE_ROOT/ingestion_command.py"
readonly PERSISTENCE="$PACKAGE_ROOT/persistence.py"
readonly CANDIDATE="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v3/synthetic_corpus_v3_candidate_20261023T043639Z"
readonly NORMALIZED="$CANDIDATE/qualification/normalized.json"
readonly CORPUS_TRUTH="$CANDIDATE/evaluation/corpus_truth.json"
readonly SCRIPT_200_REPORT="$REPO_ROOT/local/reports/ishikawa-v13-47-application-ranking/v13_47_application_ranking_20261023T150718Z_eveUYR.txt"
readonly SCRIPT_200_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/v13-47-application-ranking/v13_47_application_ranking_20261023T150718Z.json"
readonly COMPLETE_REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v13-48-isolated-corpus-v3-api"
readonly COMPLETE_ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v13-48-isolated-corpus-v3-api"
readonly FRONTIER_REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.3-corpus-v3-frontier-gate"
readonly FRONTIER_ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v1.3-corpus-v3-frontier-gate"

readonly INITDB='/usr/lib/postgresql/16/bin/initdb'
readonly PG_CTL='/usr/lib/postgresql/16/bin/pg_ctl'
readonly CREATEDB='/usr/lib/postgresql/16/bin/createdb'
readonly PSQL='/usr/lib/postgresql/16/bin/psql'
readonly TEMPORARY_POSTGRESQL_PORT=65438
readonly API_PORT=1384
readonly API_ENDPOINT="http://127.0.0.1:${API_PORT}/v1/chat"
readonly GENERATION_CAPTURE_PROXY_PORT=18002
readonly GENERATION_CAPTURE_PROXY_BASE_URL="http://127.0.0.1:${GENERATION_CAPTURE_PROXY_PORT}"
readonly GEMMA_PRIMARY_BASE_URL='http://127.0.0.1:18000'
readonly GEMMA_LEGACY_BASE_URL='http://127.0.0.1:8000'
readonly NOMIC_PRIMARY_BASE_URL='http://127.0.0.1:18001'
readonly NOMIC_LEGACY_BASE_URL='http://127.0.0.1:8001'
readonly EXPECTED_HOSTNAME='DankoSurface'
readonly EXPECTED_OS_VERSION='24.04'
readonly EXPECTED_ARCHITECTURE='aarch64'

readonly CANDIDATE_MANIFEST_SHA256='3220c5ae7fd16c37086511893c63c4784b9adf10635e40c79332b4a7b4c79fce'
readonly NORMALIZED_SHA256='1772584ecc02c86cc0bd96946318e608f576fd259676bc9851ab7c54bf766b02'
readonly CORPUS_TRUTH_SHA256='85f753ced3956e609b1fada2419888bae1099a308be3c905310765796c80f573'
readonly CHUNKS_SHA256='49a67ac067d06b6068878be6530ae4971bddb4a1f687545578bd1ef9254d19e4'
readonly SCHEMA_FILE_SHA256='1fdbed2439fb5bfecaef5dd857f380661c298f8459d6cc2319114b78e5a09c5d'
readonly SCHEMA_CONTRACT_SHA256='3b55d00880e6e09e401e282b7f62314fb635c6a859c23ad3e87c58aa23237e8b'
readonly BUNDLE_BUILDER_SHA256='fb2a1c73cdbf1869929b9e754904622675bffa540da05ffd93e1160905280879'
readonly CAPTURE_ADAPTER_SHA256='2d0cd7552ce76bc5bc4f8a26902b25dab62daf52e58ae2a3bfdffee9e7165356'
readonly CHUNK_BUILDER_SHA256='2c042acfabe608a5683d212403beac6215d385301562de059dc55bd77ed44a26'
readonly EMBED_ADAPTER_SHA256='f1a050a178dcd232f2be9afa34b30cbdd2f0a919b511d5be7a9e9f458a9db6df'
readonly INGESTION_RUNNER_SHA256='147b415d09f76d869d8da75a5ef07f9525fa54d7a6d034ab3d1829ca51687591'
readonly DATABASE_QUALIFIER_SHA256='2434f5181a13887b8434b01592cd64e9de0ba799da4bf7a47a5f5bb287fe1f69'
readonly API_EVALUATOR_SHA256='854d8a560b087a643d83719d0ba7db734487d62153626a79cf279a312df3c829'
readonly MULTITURN_EVALUATOR_SHA256='57a10ede37cfbf30453fe115650538e55c63d349f8a0057e180ce251a4755615'
readonly CATALOG_ROUTING_EVALUATOR_SHA256='eef7b37a401b69ea29d57c7f9719ed00ab6c093fdad9f0b1c7e46cf20bb3507e'
readonly GENERATION_CAPTURE_PROXY_SHA256='2b57a3b840c8ede4d0abe403f7e6de738c5f5a3be27aebf891a416c6ec61157b'
readonly COMPLETE_API_CASES_SHA256='8fc97f17b6940d235a136926026d586ebaa9f907731c45c7d3a5edc107adfae4'
readonly FRONTIER_API_CASES_SHA256='2ba5f61518ca17b0eaa26f024abe35418b050f9bd8d5b3e1677062c9d7a626a3'
readonly PIPELINE_EXECUTABLE_SHA256='0faa5c65fbf8af454040158813308fb239ec70535bd956c3ffbc0523f5904b94'
readonly ARTIFACT_PIPELINE_SHA256='03825cf81ca9debf7fda49e421429a09ff4f963316603cbbded73222b9463b66'
readonly INGESTION_COMMAND_SHA256='868861de72f851d62c80153fe11f4872da582a7869e2ab13b1db3d43bee4083c'
readonly PERSISTENCE_SHA256='5909f0ab4a86a8cf2ee7ed133dde0506b27e83096fa33372b728c0f38fbb7cf0'
readonly SCRIPT_200_REPORT_SHA256='b5945bab4cc3ce24147645ce8cdb4109878d92fccf8d3977eef1d2f1b232dbed'
readonly SCRIPT_200_ARTIFACT_SHA256='377d4231659db4afa92f3d7c3dd86b4a8af50c7cf02e68ff380cfdbe3bbff3b8'

usage() {
  sed -n '2,10p' "${BASH_SOURCE[0]}"
}

mode="${1:-}"
if [[ "$#" -ne 1 ]]; then
  printf 'FAILURE DETAIL\nstage=argument_validation\nreason=exactly_one_mode_required\ndetail=Script 201 requires exactly one supported mode.\noperator_action=Rerun Script 201 with one of --validate-only, --run, --validate-frontier, or --run-frontier.\n\nSCRIPT RESULT\nscript_201_isolated_corpus_v3_api_qualification=blocked\n' >&2
  exit 2
fi
case "$mode" in
  --validate-only|--run)
    qualification_profile=complete_13
    API_CASES="$COMPLETE_API_CASES"
    API_CASES_SHA256="$COMPLETE_API_CASES_SHA256"
    EXPECTED_CASES=13
    EXPECTED_RESPONSIVE=6
    EXPECTED_NONRESPONSIVE=6
    EXPECTED_BROAD_NAVIGATION=1
    EXPECTED_REQUIRED_EVIDENCE=6
    REPORT_ROOT="$COMPLETE_REPORT_ROOT"
    ARTIFACT_ROOT="$COMPLETE_ARTIFACT_ROOT"
    ;;
  --validate-frontier|--run-frontier)
    qualification_profile=frontier_60
    API_CASES="$FRONTIER_API_CASES"
    API_CASES_SHA256="$FRONTIER_API_CASES_SHA256"
    EXPECTED_CASES=60
    EXPECTED_RESPONSIVE=60
    EXPECTED_NONRESPONSIVE=0
    EXPECTED_BROAD_NAVIGATION=0
    EXPECTED_REQUIRED_EVIDENCE=60
    REPORT_ROOT="$FRONTIER_REPORT_ROOT"
    ARTIFACT_ROOT="$FRONTIER_ARTIFACT_ROOT"
    ;;
  *)
    printf 'FAILURE DETAIL\nstage=argument_validation\nreason=unsupported_mode\ndetail=Script 201 received an unsupported mode.\noperator_action=Rerun Script 201 with one of --validate-only, --run, --validate-frontier, or --run-frontier.\n\nSCRIPT RESULT\nscript_201_isolated_corpus_v3_api_qualification=blocked\n' >&2
    exit 2
    ;;
esac
readonly qualification_profile API_CASES API_CASES_SHA256 EXPECTED_CASES
readonly EXPECTED_RESPONSIVE EXPECTED_NONRESPONSIVE
readonly EXPECTED_BROAD_NAVIGATION EXPECTED_REQUIRED_EVIDENCE
readonly REPORT_ROOT ARTIFACT_ROOT
printf 'preflight=running;script=201;checks=frozen_inputs_and_self_tests\n'

preflight_block() {
  printf 'FAILURE DETAIL\nstage=preflight\nreason=%s\ndetail=The local qualification preflight rejected a required command, file identity, or frozen contract.\noperator_action=Use the reason above to restore the named prerequisite, then rerun this same command.\n\nSCRIPT RESULT\nscript_201_isolated_corpus_v3_api_qualification=blocked\n' "$1" >&2
  exit "${2:-1}"
}

for command_name in awk bash basename curl date env find grep head hostname id \
  install kill mkdir mktemp python3 rm sed seq sha256sum sleep sort ss tail tar \
  tee timeout tr uname wc; do
  command -v "$command_name" >/dev/null 2>&1 \
    || preflight_block "local_command_missing_${command_name}"
done
for executable in "$INITDB" "$PG_CTL" "$CREATEDB" "$PSQL"; do
  [[ -f "$executable" && ! -L "$executable" && -x "$executable" ]] \
    || preflight_block postgresql_16_binary_unsafe
done

check_file() {
  local path="$1" expected="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] \
    || preflight_block "${label}_unsafe"
  [[ "$(sha256sum -- "$path" | awk '{print $1}')" == "$expected" ]] \
    || preflight_block "${label}_identity_changed"
}

check_file "$CANDIDATE/SHA256SUMS" "$CANDIDATE_MANIFEST_SHA256" candidate_manifest
check_file "$NORMALIZED" "$NORMALIZED_SHA256" normalized_corpus
check_file "$CORPUS_TRUTH" "$CORPUS_TRUTH_SHA256" corpus_truth
check_file "$SCHEMA" "$SCHEMA_FILE_SHA256" schema
check_file "$BUNDLE_BUILDER" "$BUNDLE_BUILDER_SHA256" bundle_builder
check_file "$CAPTURE_ADAPTER" "$CAPTURE_ADAPTER_SHA256" capture_adapter
check_file "$CHUNK_BUILDER" "$CHUNK_BUILDER_SHA256" chunk_builder
check_file "$EMBED_ADAPTER" "$EMBED_ADAPTER_SHA256" embed_adapter
check_file "$INGESTION_RUNNER" "$INGESTION_RUNNER_SHA256" ingestion_runner
check_file "$DATABASE_QUALIFIER" "$DATABASE_QUALIFIER_SHA256" database_qualifier
check_file "$API_EVALUATOR" "$API_EVALUATOR_SHA256" api_evaluator
check_file "$MULTITURN_EVALUATOR" "$MULTITURN_EVALUATOR_SHA256" multiturn_evaluator
check_file "$CATALOG_ROUTING_EVALUATOR" "$CATALOG_ROUTING_EVALUATOR_SHA256" catalog_routing_evaluator
check_file "$GENERATION_CAPTURE_PROXY" "$GENERATION_CAPTURE_PROXY_SHA256" generation_capture_proxy
check_file "$API_CASES" "$API_CASES_SHA256" api_cases
check_file "$PIPELINE_EXECUTABLE" "$PIPELINE_EXECUTABLE_SHA256" pipeline_executable
check_file "$ARTIFACT_PIPELINE" "$ARTIFACT_PIPELINE_SHA256" artifact_pipeline
check_file "$INGESTION_COMMAND" "$INGESTION_COMMAND_SHA256" ingestion_command
check_file "$PERSISTENCE" "$PERSISTENCE_SHA256" persistence
check_file "$SCRIPT_200_REPORT" "$SCRIPT_200_REPORT_SHA256" script_200_report
check_file "$SCRIPT_200_ARTIFACT" "$SCRIPT_200_ARTIFACT_SHA256" script_200_artifact
[[ -d "$CANDIDATE" && ! -L "$CANDIDATE" ]] \
  || preflight_block candidate_directory_unsafe
[[ -x "$PIPELINE_EXECUTABLE" && -x "$SERVICE_ENTRYPOINT" && -x "$TEST_RUNNER" ]] \
  || preflight_block executable_input_invalid
(cd -- "$CANDIDATE" && sha256sum --quiet -c SHA256SUMS) \
  || preflight_block candidate_checksum_validation_failed

grep -Fq '| `V13-47` |' "$DECISIONS" || preflight_block v13_47_not_frozen
grep -Fq '| `V13-48` |' "$DECISIONS" || preflight_block v13_48_not_frozen
grep -Fq '| `V13-49` |' "$DECISIONS" || preflight_block v13_49_not_frozen
grep -Fq '| `V13-50` |' "$DECISIONS" || preflight_block v13_50_not_frozen
grep -Fq '| `V13-52` |' "$DECISIONS" || preflight_block v13_52_not_frozen
grep -Fq '| `V13-53` |' "$DECISIONS" || preflight_block v13_53_not_frozen
grep -Fq '| `V13-54` |' "$DECISIONS" || preflight_block v13_54_not_frozen
grep -Fq '| `V13-55` |' "$DECISIONS" || preflight_block v13_55_not_frozen
grep -Fq '| `V13-56` |' "$DECISIONS" || preflight_block v13_56_not_frozen
grep -Fq '| `V13-57` |' "$DECISIONS" || preflight_block v13_57_not_frozen
grep -Fxq 'script_200_v13_47_application_qualification=pass' "$SCRIPT_200_REPORT" \
  || preflight_block script_200_not_clean
grep -Fxq 'qualification=pass;body_mrr_at_20=0.895450;body_coverage=120/120;cases=180' \
  "$SCRIPT_200_REPORT" || preflight_block script_200_metric_contract_invalid
grep -Fxq 'next_gate=isolated_corpus_v3_ingestion_and_complete_api_qualification' \
  "$SCRIPT_200_REPORT" || preflight_block script_200_next_gate_invalid

PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$SCRIPT_200_ARTIFACT" "$PRODUCT_ROOT" <<'PY' \
  || preflight_block script_200_artifact_contract_invalid
import hashlib
import json
import pathlib
import sys

artifact = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
root = pathlib.Path(sys.argv[2])
assert artifact["qualification_status"] == "pass"
assert artifact["selected_candidate"] == "raw_l1_v3_fc1_d1_h010"
assert artifact["implemented_retrieval_profile_id"] == "7c8f8f37ccce47cde1bdbb6cb43b321be14e54a11c8435e845ab7508c3dc8edb"
assert artifact["metrics"]["body"]["mrr_at_20"] == "0.895450"
assert artifact["metrics"]["body"]["relevant_at_20"] == 120
assert artifact["metrics"]["relationship"]["relevant_at_20"] == 30
assert artifact["metrics"]["header"]["relevant_at_20"] == 30
assert artifact["next_gate"] == "isolated_corpus_v3_ingestion_and_complete_api_qualification"
expected_implementation_names = {
    "retrieval", "postgres_retrieval", "method_profile",
    "relationship_registry", "database_schema",
}
assert set(artifact["implementation_sha256"]) == expected_implementation_names
for value in artifact["implementation_sha256"].values():
    assert isinstance(value, str) and len(value) == 64
    int(value, 16)
PY

bash -n "${BASH_SOURCE[0]}" "$SERVICE_ENTRYPOINT" "$PIPELINE_EXECUTABLE" \
  || preflight_block shell_syntax_invalid
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$BUNDLE_BUILDER" "$CAPTURE_ADAPTER" "$CHUNK_BUILDER" "$INGESTION_RUNNER" \
  "$EMBED_ADAPTER" "$ARTIFACT_PIPELINE" "$DATABASE_QUALIFIER" "$API_EVALUATOR" \
  "$MULTITURN_EVALUATOR" "$CATALOG_ROUTING_EVALUATOR" \
  "$GENERATION_CAPTURE_PROXY" \
  || preflight_block python_syntax_invalid
PYTHONDONTWRITEBYTECODE=1 python3 -B "$BUNDLE_BUILDER" --self-test \
  | grep -Fxq 'synthetic_corpus_v3_ingestion_bundle_self_test=pass' \
  || preflight_block bundle_builder_self_test_failed
PYTHONDONTWRITEBYTECODE=1 python3 -B "$DATABASE_QUALIFIER" --self-test \
  | grep -Fxq 'isolated_synthetic_corpus_v3_database_self_test=pass' \
  || preflight_block database_qualifier_self_test_failed
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EMBED_ADAPTER" --self-test \
  | grep -Fxq 'document_embedding_endpoint_producer_self_test=pass' \
  || preflight_block embed_adapter_self_test_failed
PYTHONDONTWRITEBYTECODE=1 python3 -B "$API_EVALUATOR" --self-test \
  | grep -Fxq 'v1_3_complete_api_evaluator_self_test=pass' \
  || preflight_block api_evaluator_self_test_failed
PYTHONDONTWRITEBYTECODE=1 python3 -B "$MULTITURN_EVALUATOR" --self-test \
  | grep -Fxq 'v1_3_multiturn_resolution_evaluator_self_test=pass' \
  || preflight_block multiturn_evaluator_self_test_failed
PYTHONDONTWRITEBYTECODE=1 python3 -B "$CATALOG_ROUTING_EVALUATOR" --self-test \
  | grep -Fxq 'v1_3_catalog_routing_evaluator_self_test=pass' \
  || preflight_block catalog_routing_evaluator_self_test_failed
printf 'preflight_check=generation_capture_proxy_self_test;state=running\n'
PYTHONPATH="$PYTHON_ROOT" PYTHONDONTWRITEBYTECODE=1 \
  python3 -B "$GENERATION_CAPTURE_PROXY" --self-test \
  | grep -Fxq 'v1_3_generation_capture_proxy_self_test=pass' \
  || preflight_block generation_capture_proxy_self_test_failed
printf 'preflight_check=generation_capture_proxy_self_test;state=pass\n'
case_validation="$(PYTHONDONTWRITEBYTECODE=1 python3 -B "$API_EVALUATOR" \
  --validate-cases --cases "$API_CASES" 2>&1)" \
  || preflight_block api_case_validation_failed
expected_case_prefix="v1_3_complete_api_case_set=pass;cases=${EXPECTED_CASES};responsive=${EXPECTED_RESPONSIVE};nonresponsive=${EXPECTED_NONRESPONSIVE};broad_navigation=${EXPECTED_BROAD_NAVIGATION};required_evidence=${EXPECTED_REQUIRED_EVIDENCE};identity="
[[ "$case_validation" =~ ^${expected_case_prefix}[0-9a-f]{64}$ ]] \
  || preflight_block api_case_contract_invalid

script_sha256="$(sha256sum -- "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$mode" == '--validate-only' || "$mode" == '--validate-frontier' ]]; then
  printf '%s\n' \
    'purpose=validate_combined_isolated_corpus_v3_ingestion_and_api_qualification' \
    "script_sha256=$script_sha256" \
    "qualification_profile=$qualification_profile" \
    'corpus=synthetic-corpus-v3;documents=30;pages=150;retrieval_candidates=943;relationship_pairs=90' \
    "api_cases=${EXPECTED_CASES};responsive=${EXPECTED_RESPONSIVE};nonresponsive=${EXPECTED_NONRESPONSIVE};broad_navigation=${EXPECTED_BROAD_NAVIGATION};required_evidence=${EXPECTED_REQUIRED_EVIDENCE}" \
    'one_execution=true;self_validating=true;catalog_routing_canaries=9;catalog_failure_collection=all_cases_before_later_gates;multiturn_fail_fast_canary=true;r001_fail_fast_canary=true;generation_exchange_capture=true;runtime_flat_file_index=false' \
    'database_contact=false;model_contact=false;credential_read=false;service_started=false;corpus_changed=false' \
    '' \
    'SCRIPT RESULT' \
    'script_201_isolated_corpus_v3_api_qualification=ready'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT" \
  || preflight_block local_output_root_creation_failed
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/isolated_corpus_v3_api_${timestamp}_XXXXXX.txt")" \
  || preflight_block local_report_creation_failed
suffix="${report_path##*_}"; suffix="${suffix%.txt}"
database_artifact="$ARTIFACT_ROOT/isolated_corpus_v3_database_${timestamp}_${suffix}.json"
api_artifact="$ARTIFACT_ROOT/isolated_corpus_v3_api_${timestamp}_${suffix}.json"
diagnostic_bundle="$ARTIFACT_ROOT/isolated_corpus_v3_api_${timestamp}_${suffix}.diagnostics.tar.gz"
generation_capture_root="$ARTIFACT_ROOT/generation_capture_${timestamp}_${suffix}"
work_root="$(mktemp -d /tmp/ishikawa-script-201.XXXXXX)" \
  || preflight_block local_workspace_creation_failed
readonly MAIN_BASHPID="$BASHPID"

gemma_key=''
nomic_key=''
gemma_base_url=''
nomic_base_url=''
database_password='disposable-corpus-v3-qualification-password'
postgresql_started=false
service_pid=''
capture_proxy_pid=''
active_pid=''
failure_reason=''
failure_stage=''
failure_root_cause=''
failure_detail=''
failure_action=''
current_stage='initialization'

emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
block() {
  failure_reason="$1"
  failure_stage="$current_stage"
  exit "${2:-1}"
}
record_unexpected_error() {
  local status="$1"
  if [[ "$BASHPID" == "$MAIN_BASHPID" && -z "$failure_reason" ]]; then
    failure_reason="${current_stage}_unexpected_exit_${status}"
    failure_stage="$current_stage"
  fi
}
handle_signal() {
  failure_reason="interrupted_$1"
  failure_stage="$current_stage"
  exit "$2"
}
classify_failure() {
  local nested='' service_marker='' failed_cases='' capture_summary='' summary_path=''
  [[ -n "$failure_stage" ]] || failure_stage="$current_stage"
  case "$failure_reason" in
    gemma_forward_unavailable_on_18000_and_8000)
      failure_detail='Neither http://127.0.0.1:18000/health nor http://127.0.0.1:8000/health returned HTTP 200.'
      failure_action='Restore the Gemma SSH port forward, verify its /health endpoint locally, and rerun Script 201.'
      ;;
    nomic_forward_unavailable_on_18001_and_8001)
      failure_detail='Neither http://127.0.0.1:18001/health nor http://127.0.0.1:8001/health returned HTTP 200.'
      failure_action='Restore the Nomic SSH port forward, verify its /health endpoint locally, and rerun Script 201.'
      ;;
    qualification_port_in_use)
      failure_detail='A process is already listening on reserved qualification port 1384, 18002, or 65438.'
      failure_action='Stop the retained preview or disposable database listener using the reported port, then rerun Script 201.'
      ;;
    generation_capture_proxy_not_ready|generation_capture_proxy_exited|generation_capture_missing|generation_capture_invalid)
      failure_detail="The R-001 generation capture boundary failed;reason=${failure_reason};capture_root=${generation_capture_root}."
      failure_action='Inspect generation-capture-proxy stdout/stderr and the retained capture directory. Correct the named local capture fault, then rerun Script 201.'
      ;;
    interactive_terminal_unavailable|secret_entry_failed|gemma_credential_format_invalid|nomic_credential_format_invalid)
      failure_detail='The protected credential prompt could not read a nonempty value from the controlling terminal.'
      if [[ "$failure_reason" == nomic_credential_format_invalid ]]; then
        failure_detail='The Nomic credential did not meet the ingestion boundary: 32 through 1024 UTF-8 bytes with no line breaks.'
        failure_action='Rerun Script 201 and enter the complete Nomic API key when prompted.'
      elif [[ "$failure_reason" == gemma_credential_format_invalid ]]; then
        failure_detail='The Gemma credential must contain 1 through 4096 UTF-8 bytes with no line breaks.'
        failure_action='Rerun Script 201 and enter the complete Gemma API key when prompted.'
      else
        failure_action='Run Script 201 in an interactive terminal and enter the Gemma and Nomic API keys when prompted.'
      fi
      ;;
    gemma_authenticated_access_failed|gemma_authenticated_access_marker_missing)
      if [[ -f "$work_root/gemma-access.stdout" ]]; then
        nested="$(sed -n 's/^gemma_authenticated_access=blocked;reason=\([a-z0-9_]*\)$/\1/p' "$work_root/gemma-access.stdout" | tail -n 1)"
      fi
      failure_root_cause="${nested:-authenticated_probe_returned_no_stable_reason}"
      failure_detail="Gemma rejected or did not complete the authenticated /v1/models probe;inner_reason=${failure_root_cause};endpoint=${gemma_base_url:-not_detected}."
      case "$nested" in
        endpoint_http_401|endpoint_http_403)
          failure_action='Rerun Script 201 and enter the valid Gemma API key when prompted.'
          ;;
        endpoint_transport_failure)
          failure_action="Restore the Gemma forward on ${gemma_base_url:-http://127.0.0.1:18000}, verify /health, and rerun Script 201."
          ;;
        *)
          failure_action='Inspect gemma-access stdout/stderr in the diagnostic bundle and correct the reported Gemma access condition before rerunning Script 201.'
          ;;
      esac
      ;;
    ephemeral_workspace_creation_failed|ephemeral_bundle_assembly_failed|ephemeral_bundle_marker_missing|ephemeral_bundle_checksum_failed|ephemeral_bundle_receipt_hash_failed|chunk_regeneration_failed|regenerated_chunk_identity_mismatch)
      failure_detail="The frozen corpus-v3 input could not be reproduced exactly;reason=${failure_reason}."
      failure_action='Do not ingest. Inspect bundle.stdout or chunks.stdout in the diagnostic bundle and restore the named frozen input identity.'
      ;;
    temporary_postgresql_initialization_failed|temporary_postgresql_start_failed|temporary_role_creation_failed|temporary_database_creation_failed|temporary_database_access_configuration_failed|temporary_database_extension_install_failed|temporary_schema_install_failed)
      failure_detail="Disposable PostgreSQL setup failed before corpus publication;reason=${failure_reason}."
      failure_action='Inspect the matching PostgreSQL setup stderr and postgresql.log in the diagnostic bundle; no accepted database was contacted.'
      ;;
    ingestion_runtime_config_generation_failed|ingestion_dependency_config_generation_failed|ingestion_relationship_config_install_failed)
      failure_detail="The isolated ingestion runtime configuration could not be assembled;reason=${failure_reason}."
      failure_action='Inspect the configuration source identities and correct the named local assembly failure before rerunning Script 201.'
      ;;
    corpus_v3_ingestion_validation_failed|corpus_v3_ingestion_publication_failed)
      if [[ -f "$work_root/ingestion-publish.stdout" ]]; then
        nested="$(sed -n 's/^ishikawa_ingestion=blocked;reason=\([a-z0-9_]*\)$/\1/p' "$work_root/ingestion-publish.stdout" | tail -n 1)"
      fi
      if [[ -z "$nested" && -f "$work_root/ingestion-validate.stdout" ]]; then
        nested="$(sed -n 's/^ishikawa_ingestion=blocked;reason=\([a-z0-9_]*\)$/\1/p' "$work_root/ingestion-validate.stdout" | tail -n 1)"
      fi
      failure_root_cause="${nested:-no_stable_inner_reason_returned}"
      failure_detail="Ingestion stopped in ${failure_stage};inner_reason=${nested:-no_stable_inner_reason_returned}."
      case "$nested" in
        *embedding_endpoint_transport_failure*)
          failure_action="Verify the Nomic forward on ${nomic_base_url:-http://127.0.0.1:18001}, then rerun Script 201."
          ;;
        *embedding_endpoint_http_401*|*embedding_endpoint_http_403*)
          failure_action='Re-enter the valid Nomic API key when Script 201 prompts, then rerun it.'
          ;;
        *embedding_endpoint_boundary_invalid*)
          failure_action='The repository embedding endpoint boundary rejected the detected loopback port; use the corrected Script 201 source and rerun it.'
          ;;
        *credential_format_invalid*)
          failure_action='Enter the actual Nomic API key; the ingestion boundary requires a trimmed credential between 32 and 4096 bytes.'
          ;;
        *persistence_schema_contract_mismatch*)
          failure_action='The disposable database schema ledger does not match Ishikawa schema version 5; use the corrected Script 201 source and rerun it.'
          ;;
        postgresql_*)
          failure_action='Inspect postgresql.log and the retained producer artifacts in the diagnostic bundle for the named PostgreSQL contract failure, then correct that contract before rerunning Script 201.'
          ;;
        *)
          failure_action='Review the exact inner_reason and diagnostic bundle, correct that ingestion stage, and rerun Script 201.'
          ;;
      esac
      ;;
    corpus_v3_database_qualification_failed|database_qualification_marker_missing)
      if [[ -f "$work_root/database-qualifier.stdout" ]]; then
        nested="$(sed -n 's/^isolated_synthetic_corpus_v3_database=blocked;reason=\([a-z0-9_]*\)$/\1/p' "$work_root/database-qualifier.stdout" | tail -n 1)"
      fi
      if [[ -z "$nested" && -f "$work_root/database-qualifier.stderr" ]]; then
        nested="$(sed -n 's/^isolated_synthetic_corpus_v3_database=blocked;reason=\([a-zA-Z0-9_]*\)$/\1/p' "$work_root/database-qualifier.stderr" | tail -n 1)"
      fi
      failure_root_cause="${nested:-qualifier_exited_without_a_stable_reason}"
      failure_detail="The PostgreSQL corpus qualification failed;inner_reason=${nested:-qualifier_exited_without_a_stable_reason}."
      failure_action='Review the database qualifier stdout/stderr in the diagnostic bundle, correct the named contract, and rerun Script 201.'
      ;;
    temporary_retrieval_api_not_ready)
      if [[ -f "$work_root/service.stderr" ]]; then
        service_marker="$(grep -E '^[a-z0-9_]+=(blocked|unavailable);reason=[a-z0-9_]+$' "$work_root/service.stderr" | tail -n 1)"
      fi
      failure_root_cause="$(sed -n 's/^[a-z0-9_]*=\(blocked\|unavailable\);reason=\([a-z0-9_]*\)$/\2/p' <<<"$service_marker")"
      [[ -n "$failure_root_cause" ]] || failure_root_cause='retrieval_api_exited_or_readiness_timed_out'
      failure_detail="The temporary Ishikawa API did not become ready;service_marker=${service_marker:-none};Gemma=${gemma_base_url:-not_detected};Nomic=${nomic_base_url:-not_detected}."
      failure_action='Verify the forwarded model endpoints remain reachable and inspect service.stderr in the diagnostic bundle before rerunning Script 201.'
      ;;
    complete_api_*)
      failure_root_cause="${failure_reason#complete_api_}"
      if [[ -f "$work_root/api-evaluator.stdout" ]]; then
        failed_cases="$(awk -F'[=;]' -v terminal="$failure_root_cause" '
          $1 == "case_start" { pending = $2 }
          $1 == "case_result" {
            split($8, returned, "/"); split($10, cited, "/")
            if ($4 != $6 || returned[1] != returned[2] || cited[1] != cited[2]) {
              if (count++) printf ","
              printf "%s(actual=%s,expected=%s,returned=%s,cited=%s)", $2, $4, $6, $8, $10
            }
            pending = ""
          }
          END {
            if (pending != "") {
              if (count++) printf ","
              printf "%s(no_result=true,terminal=%s)", pending, terminal
            }
          }
        ' "$work_root/api-evaluator.stdout")"
      fi
      if [[ -d "$generation_capture_root" && ! -L "$generation_capture_root" ]]; then
        while IFS= read -r summary_path; do
          [[ -f "$summary_path" && ! -L "$summary_path" ]] || continue
          [[ -z "$capture_summary" ]] || capture_summary+=','
          capture_summary+="$(basename -- "$(dirname -- "$summary_path")"):$(tr -d '\r\n' <"$summary_path")"
        done < <(find "$generation_capture_root" -mindepth 2 -maxdepth 2 -type f -name summary.txt -print | sort)
      fi
      failure_detail="The complete API gate failed;root_cause=${failure_root_cause};failed_cases=${failed_cases:-not_available};generation_capture=${capture_summary:-not_available}."
      case "$failure_root_cause" in
        chat_http_status_503|chat_http_status_502|chat_http_status_504)
          failure_action='The temporary API reported a dependency outage during the named unfinished case. Verify authenticated Gemma and Nomic access remains available, inspect service.stderr, and rerun Script 201.'
          ;;
        chat_http_status_*)
          failure_action='The temporary API returned the named unexpected HTTP status. Inspect api-evaluator stderr and service stderr in the diagnostic bundle before rerunning Script 201.'
          ;;
        *)
          failure_action='Use the explicit actual/expected failed-case data above; the full content-safe case results and synthetic responses are retained in the diagnostic bundle.'
          ;;
      esac
      ;;
    multiturn_resolution_security_event_applicability_evidence_missing)
      failure_root_cause='resolved_followup_did_not_return_security_event_applicability'
      failure_detail='The multi-turn answer completed, but its returned evidence omitted page 1 of 99 TST 2043 establishing applicability to credential exposure.'
      failure_action='Inspect the retained final generation request, response, and reconstructed sources; do not run the sixty-question gate until the applicability evidence is returned.'
      ;;
    multiturn_resolution_security_event_applicability_evidence_not_cited)
      failure_root_cause='security_event_applicability_was_not_cited'
      failure_detail='The multi-turn answer returned page 1 of 99 TST 2043 but did not cite that evidence when establishing applicability to credential exposure.'
      failure_action='Inspect the retained final generation request and response; correct generation or validation before running the sixty-question gate.'
      ;;
    multiturn_resolution_incident_intake_form_evidence_missing)
      failure_root_cause='resolved_followup_did_not_return_incident_intake_form'
      failure_detail='The multi-turn answer completed, but its returned evidence omitted page 1 of TST-9030 identifying the Incident Intake Form for initial reporting.'
      failure_action='Inspect the retained final generation request, response, and reconstructed sources; do not run the sixty-question gate until the form evidence is returned.'
      ;;
    multiturn_resolution_incident_intake_form_evidence_not_cited)
      failure_root_cause='incident_intake_form_was_not_cited'
      failure_detail='The multi-turn answer returned page 1 of TST-9030 but did not cite that evidence when identifying the form to complete.'
      failure_action='Inspect the retained final generation request and response; correct generation or validation before running the sixty-question gate.'
      ;;
    multiturn_resolution_*)
      failure_root_cause="${failure_reason#multiturn_resolution_}"
      failure_detail="The fail-fast multi-turn canary failed;inner_reason=${failure_root_cause}."
      failure_action='Use the exact inner reason and retained canary capture to correct the follow-up path before running the sixty-question gate.'
      ;;
    catalog_routing_*)
      failure_root_cause="${failure_reason#catalog_routing_}"
      failure_detail="The deterministic catalog-routing canary failed;inner_reason=${failure_root_cause}."
      if [[ -f "$work_root/postgresql.log" ]] \
        && grep -Fq 'ishikawa.known-document.department-' "$work_root/postgresql.log" \
        && grep -Fq 'ERROR:' "$work_root/postgresql.log"; then
        failure_root_cause='department_catalog_postgresql_query_failed'
        failure_detail="The deterministic department-catalog PostgreSQL query failed before model scope;canary_reason=${failure_reason#catalog_routing_}."
        failure_action='Inspect the PostgreSQL ERROR and named ishikawa.known-document.department query in the retained diagnostic bundle; this is not a Gemma, Nomic, or port-forward outage.'
      else
      case "$failure_root_cause" in
        api_transport_failed|*_http_response_invalid|*_unexpected_status_temporarily_unavailable)
          failure_action='Verify the temporary API and forwarded Gemma/Nomic endpoints, then inspect catalog-routing stderr and service stderr in the retained diagnostic bundle.'
          ;;
        *_required_documents_missing)
          failure_action='The response omitted an expected department-owned or explicitly related document. Inspect catalog-routing output and the retained generation exchange before changing ranking or corpus state.'
          ;;
        *_required_documents_not_cited)
          failure_action='The response returned but did not cite every required catalog document. Inspect the retained generation exchange and citation validator output.'
          ;;
        *)
          failure_action='Use the exact inner reason and retained catalog-routing output to correct routing, constraint construction, or response validation before running the sixty-question gate.'
          ;;
      esac
      fi
      ;;
    staged_product_install_failed|staged_runtime_config_generation_failed|staged_dependency_config_generation_failed|staged_configuration_invalid)
      failure_detail="The temporary installed-product layout or configuration was rejected;reason=${failure_reason}."
      failure_action='Inspect check-config stdout/stderr and the staged service logs in the diagnostic bundle before rerunning Script 201.'
      ;;
    corpus_v3_ingestion_plan_invalid|corpus_v3_ingestion_marker_missing|database_qualification_marker_missing|database_qualification_artifact_hash_failed|complete_api_pass_marker_missing|complete_api_summary_invalid|retained_artifact_validation_failed)
      failure_detail="A stage completed but its exact acceptance contract was absent or mismatched;reason=${failure_reason}."
      failure_action='Inspect the named stage output in the diagnostic bundle; do not treat this run as qualified.'
      ;;
    native_regression_failed|native_regression_marker_missing|native_regression_count_invalid)
      failure_detail='The local Ishikawa regression suite failed or did not return its required pass contract.'
      failure_action='Inspect native-tests.txt in the diagnostic bundle, correct all reported test failures, and rerun Script 201.'
      ;;
    *)
      failure_detail="Script 201 stopped during ${failure_stage};reason=${failure_reason:-unclassified_failure}."
      failure_action='Inspect the named stage files in the diagnostic bundle, correct the reported condition, and rerun Script 201.'
      ;;
  esac
}
cleanup() {
  local status="$?" result=blocked cleanup_failed=false diagnostic_sha256=''
  trap - ERR EXIT HUP INT TERM
  set +e
  unset ISHIKAWA_GEMMA_API_KEY ISHIKAWA_NOMIC_API_KEY \
    ISHIKAWA_POSTGRESQL_PASSWORD ISHIKAWA_POSTGRESQL_INGEST_PASSWORD
  gemma_key=''; nomic_key=''; database_password=''
  for pid in "$active_pid" "$service_pid" "$capture_proxy_pid"; do
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null || true
      for _ in $(seq 1 20); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.25
      done
      if kill -0 "$pid" 2>/dev/null; then
        kill -KILL "$pid" 2>/dev/null || true
        cleanup_failed=true
      fi
      wait "$pid" 2>/dev/null || true
    fi
  done
  if [[ "$postgresql_started" == true && "$work_root" == /tmp/ishikawa-script-201.* ]]; then
    "$PG_CTL" -D "$work_root/postgresql" -m fast -w stop >/dev/null 2>&1 \
      || cleanup_failed=true
  fi
  if ss -H -ltn "( sport = :${API_PORT} or sport = :${GENERATION_CAPTURE_PROXY_PORT} or sport = :${TEMPORARY_POSTGRESQL_PORT} )" \
    2>/dev/null | grep -q .; then
    cleanup_failed=true
  fi
  if (( status != 0 )); then
    classify_failure
  fi
  if (( status != 0 )) && [[ -d "$work_root" && "$work_root" == /tmp/ishikawa-script-201.* ]]; then
    diagnostic_members=()
    for member in native-tests.txt bundle.stdout chunks.stdout \
      initdb.stdout initdb.stderr pg-start.stdout pg-start.stderr \
      roles.stdout roles.stderr createdb.stdout createdb.stderr \
      database-access.stdout database-access.stderr extensions.stdout extensions.stderr \
      schema.stdout schema.stderr ingestion-runtime-config.stderr \
      ingestion-dependency-config.stderr staged-runtime-config.stderr \
      staged-dependency-config.stderr \
      gemma-access.stdout gemma-access.stderr \
      ingestion-validate.stdout ingestion-validate.stderr \
      ingestion-publish.stdout ingestion-publish.stderr \
      database-qualifier.stdout database-qualifier.stderr \
      check-config.stdout check-config.stderr \
      api-evaluator.stdout api-evaluator.stderr \
      catalog-routing-evaluator.stdout catalog-routing-evaluator.stderr \
      multiturn-evaluator.stdout multiturn-evaluator.stderr \
      service.stdout service.stderr \
      generation-capture-proxy.stdout generation-capture-proxy.stderr \
      postgresql.log operator-reports producer-artifacts staged/Ishikawa/state/logs; do
      [[ -e "$work_root/$member" ]] && diagnostic_members+=("$member")
    done
    if (( ${#diagnostic_members[@]} > 0 )) && [[ ! -e "$diagnostic_bundle" ]] \
      && tar -C "$work_root" -czf "$diagnostic_bundle" -- "${diagnostic_members[@]}"; then
      diagnostic_sha256="$(sha256sum -- "$diagnostic_bundle" | awk '{print $1}')"
      printf '%s  %s\n' "$diagnostic_sha256" "$(basename -- "$diagnostic_bundle")" \
        >"$diagnostic_bundle.sha256"
    fi
  fi
  [[ -d "$work_root" && "$work_root" == /tmp/ishikawa-script-201.* ]] \
    && rm -rf -- "$work_root"
  if [[ "$cleanup_failed" == true ]]; then
    status=1
    [[ -n "$failure_reason" ]] || failure_reason='runtime_cleanup_failed'
  fi
  (( status == 0 )) && result=pass
  emit "milestone=cleanup;state=$([[ "$cleanup_failed" == false ]] && printf pass || printf blocked);temporary_postgresql_removed=true;retrieval_api_stopped=true;generation_capture_proxy_stopped=true;ports_free=$([[ "$cleanup_failed" == false ]] && printf true || printf false)"
  if [[ "$result" == blocked ]]; then
    [[ -n "$failure_detail" ]] || classify_failure
    emit 'FAILURE DETAIL'
    emit "stage=${failure_stage:-unclassified}"
    emit "reason=${failure_reason:-unclassified_failure}"
    [[ -z "$failure_root_cause" ]] || emit "root_cause=$failure_root_cause"
    emit "detail=$failure_detail"
    emit "operator_action=$failure_action"
  fi
  [[ -z "$diagnostic_sha256" ]] \
    || emit "diagnostic_bundle=$diagnostic_bundle;diagnostic_bundle_sha256=$diagnostic_sha256;synthetic_content_only=true"
  if [[ -f "$api_artifact" && ! -L "$api_artifact" ]]; then
    emit "partial_or_complete_api_artifact=$api_artifact;sha256=$(sha256sum -- "$api_artifact" | awk '{print $1}')"
  fi
  if [[ -d "$generation_capture_root" && ! -L "$generation_capture_root" ]]; then
    emit "generation_capture_root=$generation_capture_root;authorization_retained=false;synthetic_content_only=true"
    while IFS= read -r summary_path; do
      [[ -f "$summary_path" && ! -L "$summary_path" ]] || continue
      emit "generation_capture=$(basename -- "$(dirname -- "$summary_path")");$(tr -d '\r\n' <"$summary_path")"
    done < <(find "$generation_capture_root" -mindepth 2 -maxdepth 2 -type f -name summary.txt -print | sort)
  fi
  emit "local_report=$report_path"
  {
    printf '\nSCRIPT RESULT\n'
    printf 'script_201_isolated_corpus_v3_api_qualification=%s\n' "$result"
  } | tee -a "$report_path"
  exit "$status"
}
trap 'record_unexpected_error $?' ERR
trap cleanup EXIT
trap 'handle_signal HUP 129' HUP
trap 'handle_signal INT 130' INT
trap 'handle_signal TERM 143' TERM

read_secret() {
  local label="$1" destination="$2" minimum="$3" maximum="$4" reason="$5" value='' byte_count=''
  [[ -r /dev/tty && -w /dev/tty ]] || block interactive_terminal_unavailable
  IFS= read -r -s -p "$label: " value </dev/tty || block secret_entry_failed
  printf '\n' >/dev/tty
  byte_count="$(LC_ALL=C printf '%s' "$value" | wc -c | tr -d ' ')" \
    || block "$reason"
  [[ "$byte_count" =~ ^[0-9]+$ ]] || block "$reason"
  (( byte_count >= minimum && byte_count <= maximum )) || block "$reason"
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || block "$reason"
  printf -v "$destination" '%s' "$value"
  value=''
}

probe_gemma_access() {
  printf '%s' "$gemma_key" | PYTHONDONTWRITEBYTECODE=1 python3 -B \
    /dev/fd/3 "$gemma_base_url/v1/models" 3<<'PY'
import json
import sys
import urllib.error
import urllib.parse
import urllib.request

url = sys.argv[1]
parsed = urllib.parse.urlsplit(url)
if (
    parsed.scheme != "http"
    or parsed.hostname != "127.0.0.1"
    or parsed.port not in {8000, 18000}
    or parsed.path != "/v1/models"
    or parsed.query
    or parsed.fragment
    or parsed.username is not None
    or parsed.password is not None
):
    print("gemma_authenticated_access=blocked;reason=endpoint_boundary_invalid")
    raise SystemExit(1)
credential = sys.stdin.buffer.read(4097)
if not 1 <= len(credential) <= 4096 or b"\n" in credential or b"\r" in credential:
    print("gemma_authenticated_access=blocked;reason=credential_format_invalid")
    raise SystemExit(1)
try:
    authorization = "Bearer " + credential.decode("utf-8", errors="strict")
except UnicodeError:
    print("gemma_authenticated_access=blocked;reason=credential_not_utf8")
    raise SystemExit(1)
request = urllib.request.Request(
    url,
    headers={
        "Accept": "application/json",
        "Authorization": authorization,
    },
    method="GET",
)
try:
    with urllib.request.urlopen(request, timeout=30) as response:
        body = response.read(1024 * 1024 + 1)
        status = response.status
        content_type = response.headers.get_content_type()
except urllib.error.HTTPError as error:
    error.read(1024 * 1024 + 1)
    print(f"gemma_authenticated_access=blocked;reason=endpoint_http_{error.code}")
    raise SystemExit(1)
except (urllib.error.URLError, TimeoutError, OSError):
    print("gemma_authenticated_access=blocked;reason=endpoint_transport_failure")
    raise SystemExit(1)
finally:
    credential = b""
if status != 200 or content_type != "application/json" or len(body) > 1024 * 1024:
    print("gemma_authenticated_access=blocked;reason=endpoint_response_invalid")
    raise SystemExit(1)
try:
    document = json.loads(body.decode("utf-8"))
except (UnicodeError, json.JSONDecodeError):
    print("gemma_authenticated_access=blocked;reason=endpoint_response_invalid")
    raise SystemExit(1)
if not isinstance(document, dict) or not isinstance(document.get("data"), list):
    print("gemma_authenticated_access=blocked;reason=model_inventory_invalid")
    raise SystemExit(1)
print("gemma_authenticated_access=pass")
PY
}

wait_with_heartbeat() {
  local pid="$1" label="$2" output="$3" started next now lines=0 current
  started="$(date +%s)"; next=$(( started + 30 ))
  while kill -0 "$pid" 2>/dev/null; do
    if [[ -f "$output" ]]; then
      current="$(wc -l <"$output" | tr -d ' ')"
      if (( current > lines )); then
        sed -n "$(( lines + 1 )),${current}p" "$output" \
          | grep -E '^(case_(start|result)=|ishikawa_ingestion=|actions=)' \
          | while IFS= read -r line; do emit "[$label] $line"; done || true
        lines="$current"
      fi
    fi
    now="$(date +%s)"
    if (( now >= next )); then
      emit "milestone=$label;state=running;elapsed_seconds=$(( now - started ))"
      next=$(( now + 30 ))
    fi
    sleep 5
  done
  if wait "$pid"; then return 0; else return "$?"; fi
}

emit 'purpose=ingest_and_qualify_isolated_synthetic_corpus_v3_in_one_execution'
emit "started_utc=$timestamp;script_sha256=$script_sha256"
emit "qualification_profile=$qualification_profile;api_cases=$EXPECTED_CASES"
emit 'authorized_actions=read_loopback_gemma_and_nomic_start_disposable_postgresql_assemble_ephemeral_ingestion_bundle_ingest_corpus_v3_start_temporary_api_run_catalog_and_multiturn_fail_fast_canaries_then_r001_and_complete_api_gate_retain_synthetic_generation_exchange_and_metrics'
emit 'non_actions=no_credential_retention_no_accepted_database_contact_no_candidate_mutation_no_black_corpus_no_remote_host_no_package_or_release_change_no_service_install_or_autostart_no_runtime_flat_file_index'

current_stage=native_regression
emit 'milestone=native_regression;state=start'
if ! "$TEST_RUNNER" >"$work_root/native-tests.txt" 2>&1; then
  tail -n 100 "$work_root/native-tests.txt" | tee -a "$report_path"
  block native_regression_failed
fi
grep -Fq 'ishikawa_local_validation_tests=PASS' "$work_root/native-tests.txt" \
  || block native_regression_marker_missing
test_count="$(sed -n 's/^Ran \([0-9][0-9]*\) tests.*/\1/p' "$work_root/native-tests.txt" | tail -n 1)"
[[ "$test_count" =~ ^[0-9]+$ && "$test_count" -ge 450 ]] \
  || block native_regression_count_invalid
emit "milestone=native_regression;state=pass;tests=$test_count"

current_stage=readiness
ss -H -ltn "( sport = :${API_PORT} or sport = :${GENERATION_CAPTURE_PROXY_PORT} or sport = :${TEMPORARY_POSTGRESQL_PORT} )" | grep -q . \
  && block qualification_port_in_use
for candidate_base_url in "$GEMMA_PRIMARY_BASE_URL" "$GEMMA_LEGACY_BASE_URL"; do
  candidate_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
    --connect-timeout 5 --max-time 10 "$candidate_base_url/health" 2>/dev/null || true)"
  if [[ "$candidate_status" == 200 ]]; then
    gemma_base_url="$candidate_base_url"
    break
  fi
done
for candidate_base_url in "$NOMIC_PRIMARY_BASE_URL" "$NOMIC_LEGACY_BASE_URL"; do
  candidate_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
    --connect-timeout 5 --max-time 10 "$candidate_base_url/health" 2>/dev/null || true)"
  if [[ "$candidate_status" == 200 ]]; then
    nomic_base_url="$candidate_base_url"
    break
  fi
done
[[ -n "$gemma_base_url" ]] || block gemma_forward_unavailable_on_18000_and_8000
[[ -n "$nomic_base_url" ]] || block nomic_forward_unavailable_on_18001_and_8001
emit "milestone=readiness;state=pass;gemma=${gemma_base_url##*:};nomic=${nomic_base_url##*:};ports=free"

current_stage=credential_read
read_secret 'Gemma API key' gemma_key 1 4096 gemma_credential_format_invalid
read_secret 'Nomic API key' nomic_key 32 1024 nomic_credential_format_invalid
emit 'milestone=credentials;state=accepted;values_logged=false;values_retained=false'

current_stage=gemma_authenticated_access
if ! probe_gemma_access >"$work_root/gemma-access.stdout" \
  2>"$work_root/gemma-access.stderr"; then
  block gemma_authenticated_access_failed
fi
grep -Fxq 'gemma_authenticated_access=pass' "$work_root/gemma-access.stdout" \
  || block gemma_authenticated_access_marker_missing
emit "milestone=gemma_authenticated_access;state=pass;endpoint=${gemma_base_url##*:};content_logged=false"

current_stage=ephemeral_inputs
mkdir -m 0700 -- "$work_root/runtime-config" "$work_root/producer-work" \
  "$work_root/operator-reports" "$work_root/producer-artifacts" "$work_root/socket" \
  "$work_root/staged" || block ephemeral_workspace_creation_failed
PYTHONDONTWRITEBYTECODE=1 python3 -B "$BUNDLE_BUILDER" \
  --candidate "$CANDIDATE" \
  --class-registry "$CONFIG_ROOT/document_classes.yaml" \
  --output "$work_root/promotion-bundle" >"$work_root/bundle.stdout" \
  || block ephemeral_bundle_assembly_failed
grep -Fxq 'synthetic_corpus_v3_ingestion_bundle=pass;documents=30;pages=150;relationship_pairs=90' \
  "$work_root/bundle.stdout" || block ephemeral_bundle_marker_missing
(cd -- "$work_root/promotion-bundle" && sha256sum --quiet -c SHA256SUMS) \
  || block ephemeral_bundle_checksum_failed
bundle_receipt="$work_root/promotion-bundle/bundle-receipt.json"
bundle_receipt_sha256="$(sha256sum -- "$bundle_receipt" | awk '{print $1}')" \
  || block ephemeral_bundle_receipt_hash_failed
PYTHONDONTWRITEBYTECODE=1 python3 -B "$CHUNK_BUILDER" \
  --input "$NORMALIZED" --expected-input-sha256 "$NORMALIZED_SHA256" \
  --output "$work_root/corpus-v3-v6-chunks.json" --python-root "$PYTHON_ROOT" \
  >"$work_root/chunks.stdout" || block chunk_regeneration_failed
[[ "$(sha256sum -- "$work_root/corpus-v3-v6-chunks.json" | awk '{print $1}')" == "$CHUNKS_SHA256" ]] \
  || block regenerated_chunk_identity_mismatch
emit 'milestone=ephemeral_inputs;state=pass;documents=30;pages=150;retrieval_candidates=943;runtime_flat_file_index=false'

current_stage=temporary_postgresql
"$INITDB" -D "$work_root/postgresql" --username="$(id -un)" \
  --encoding=UTF8 --no-locale --auth=trust \
  >"$work_root/initdb.stdout" 2>"$work_root/initdb.stderr" \
  || block temporary_postgresql_initialization_failed
"$PG_CTL" -D "$work_root/postgresql" \
  -o "-k $work_root/socket -h 127.0.0.1 -p $TEMPORARY_POSTGRESQL_PORT -c fsync=off -c synchronous_commit=off -c full_page_writes=off" \
  -l "$work_root/postgresql.log" -w start \
  >"$work_root/pg-start.stdout" 2>"$work_root/pg-start.stderr" \
  || block temporary_postgresql_start_failed
postgresql_started=true
"$PSQL" -X -q -h "$work_root/socket" -p "$TEMPORARY_POSTGRESQL_PORT" \
  -d postgres -v ON_ERROR_STOP=1 >"$work_root/roles.stdout" \
  2>"$work_root/roles.stderr" <<'SQL' || block temporary_role_creation_failed
CREATE ROLE rag_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
CREATE ROLE rag_ingest LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOREPLICATION NOBYPASSRLS;
CREATE ROLE rag_retrieval LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOREPLICATION NOBYPASSRLS;
SQL
"$CREATEDB" -h "$work_root/socket" -p "$TEMPORARY_POSTGRESQL_PORT" \
  --owner=rag_owner --encoding=UTF8 --template=template0 rag_catalog \
  >"$work_root/createdb.stdout" 2>"$work_root/createdb.stderr" \
  || block temporary_database_creation_failed
"$PSQL" -X -q -h "$work_root/socket" -p "$TEMPORARY_POSTGRESQL_PORT" \
  -d postgres -v ON_ERROR_STOP=1 >"$work_root/database-access.stdout" \
  2>"$work_root/database-access.stderr" <<'SQL' \
  || block temporary_database_access_configuration_failed
REVOKE ALL ON DATABASE rag_catalog FROM PUBLIC;
GRANT CONNECT ON DATABASE rag_catalog TO rag_ingest, rag_retrieval;
ALTER ROLE rag_retrieval IN DATABASE rag_catalog SET default_transaction_read_only = on;
SQL
"$PSQL" -X -q -h "$work_root/socket" -p "$TEMPORARY_POSTGRESQL_PORT" \
  -d rag_catalog -v ON_ERROR_STOP=1 >"$work_root/extensions.stdout" \
  2>"$work_root/extensions.stderr" <<'SQL' \
  || block temporary_database_extension_install_failed
CREATE EXTENSION vector;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
SQL
"$PSQL" -X -q -h "$work_root/socket" -p "$TEMPORARY_POSTGRESQL_PORT" \
  -d rag_catalog -v ON_ERROR_STOP=1 -v owner_role=rag_owner \
  -v ingest_role=rag_ingest -v retrieval_role=rag_retrieval \
  -v schema_sha256="$SCHEMA_CONTRACT_SHA256" <"$SCHEMA" \
  >"$work_root/schema.stdout" 2>"$work_root/schema.stderr" \
  || block temporary_schema_install_failed
emit 'milestone=temporary_postgresql;state=pass;accepted_database_contact=false'

current_stage=corpus_v3_ingestion
PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$CONFIG_ROOT/deployment.yaml" "$work_root/runtime-config/deployment.yaml" \
  "$TEMPORARY_POSTGRESQL_PORT" 2>"$work_root/ingestion-runtime-config.stderr" <<'PY' \
  || block ingestion_runtime_config_generation_failed
import pathlib
import sys
source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
old = "postgresql:\n  bind_host: 127.0.0.1\n  port: 5432\n"
new = f"postgresql:\n  bind_host: 127.0.0.1\n  port: {sys.argv[3]}\n"
assert source.count(old) == 1
pathlib.Path(sys.argv[2]).write_text(source.replace(old, new), encoding="utf-8")
PY
PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$CONFIG_ROOT/ingestion_dependencies.yaml" \
  "$work_root/runtime-config/ingestion_dependencies.yaml" "$nomic_base_url" \
  2>"$work_root/ingestion-dependency-config.stderr" <<'PY' \
  || block ingestion_dependency_config_generation_failed
import pathlib
import sys
source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
old = "http://127.0.0.1:8001"
assert source.count(old) == 2
pathlib.Path(sys.argv[2]).write_text(source.replace(old, sys.argv[3]), encoding="utf-8")
PY
install -m 0644 -- "$CONFIG_ROOT/relationship_types.yaml" \
  "$work_root/runtime-config/relationship_types.yaml" \
  || block ingestion_relationship_config_install_failed
runner_arguments=(
  --product-root "$PRODUCT_ROOT"
  --promotion-bundle "$work_root/promotion-bundle"
  --runtime-config-root "$work_root/runtime-config"
  --work-root "$work_root/producer-work"
  --report-root "$work_root/operator-reports"
  --artifact-root "$work_root/producer-artifacts"
  --pipeline-executable "$PIPELINE_EXECUTABLE"
)
emit 'milestone=corpus_v3_ingestion_validation;state=start;documents=30'
current_stage=corpus_v3_ingestion_validation
ISHIKAWA_NOMIC_API_KEY="$nomic_key" \
ISHIKAWA_POSTGRESQL_INGEST_PASSWORD="$database_password" \
PYTHONDONTWRITEBYTECODE=1 timeout --signal=TERM --kill-after=15s 3600s \
  python3 -B "$INGESTION_RUNNER" --mode validate-only "${runner_arguments[@]}" \
  >"$work_root/ingestion-validate.stdout" 2>"$work_root/ingestion-validate.stderr" &
active_pid="$!"
wait_with_heartbeat "$active_pid" corpus_v3_ingestion_validation "$work_root/ingestion-validate.stdout" \
  || block corpus_v3_ingestion_validation_failed
active_pid=''
grep -Fxq 'actions=add:30,reprocess:0,retire:0,reuse:0,revise:0' \
  "$work_root/ingestion-validate.stdout" || block corpus_v3_ingestion_plan_invalid
emit 'milestone=corpus_v3_ingestion_validation;state=pass;actions=add:30,reprocess:0,retire:0,reuse:0,revise:0'
emit 'milestone=corpus_v3_ingestion_publication;state=start;documents=30'
current_stage=corpus_v3_ingestion_publication
ISHIKAWA_NOMIC_API_KEY="$nomic_key" \
ISHIKAWA_POSTGRESQL_INGEST_PASSWORD="$database_password" \
PYTHONDONTWRITEBYTECODE=1 timeout --signal=TERM --kill-after=15s 3600s \
  python3 -B "$INGESTION_RUNNER" --mode publish "${runner_arguments[@]}" \
  >"$work_root/ingestion-publish.stdout" 2>"$work_root/ingestion-publish.stderr" &
active_pid="$!"
wait_with_heartbeat "$active_pid" corpus_v3_ingestion_publication "$work_root/ingestion-publish.stdout" \
  || block corpus_v3_ingestion_publication_failed
active_pid=''
grep -Fxq 'ishikawa_ingestion=pass;exit_code=0' "$work_root/ingestion-publish.stdout" \
  || block corpus_v3_ingestion_marker_missing

current_stage=database_qualification
ISHIKAWA_POSTGRESQL_PASSWORD="$database_password" PYTHONDONTWRITEBYTECODE=1 \
  python3 -B "$DATABASE_QUALIFIER" --run \
  --chunks "$work_root/corpus-v3-v6-chunks.json" \
  --expected-chunks-sha256 "$CHUNKS_SHA256" \
  --corpus-truth "$CORPUS_TRUTH" \
  --expected-corpus-truth-sha256 "$CORPUS_TRUTH_SHA256" \
  --bundle-receipt "$bundle_receipt" \
  --expected-bundle-receipt-sha256 "$bundle_receipt_sha256" \
  --postgresql-socket "$work_root/socket" \
  --postgresql-port "$TEMPORARY_POSTGRESQL_PORT" \
  --output "$database_artifact" \
  >"$work_root/database-qualifier.stdout" 2>"$work_root/database-qualifier.stderr" \
  || block corpus_v3_database_qualification_failed
grep -Eq '^isolated_synthetic_corpus_v3_database=pass;documents=30;pages=150;authoritative_chunks=786;retrieval_candidates=943;representatives=157;relationship_records=[0-9]+;relationship_pairs=90$' \
  "$work_root/database-qualifier.stdout" || block database_qualification_marker_missing
database_artifact_sha256="$(sha256sum -- "$database_artifact" | awk '{print $1}')" \
  || block database_qualification_artifact_hash_failed
printf '%s  %s\n' "$database_artifact_sha256" "$(basename -- "$database_artifact")" \
  >"$database_artifact.sha256"
emit "milestone=database_qualification;state=pass;documents=30;pages=150;authoritative_chunks=786;retrieval_candidates=943;representatives=157;relationship_pairs=90;artifact_sha256=$database_artifact_sha256"

current_stage=generation_capture_proxy
# The retained synthetic artifact root may be on a DrvFS/NTFS mount, where
# mkdir succeeds but a follow-up POSIX chmod returns EPERM. Credentials are
# never written here; create the unique root under the already validated local
# artifact parent and let the capture writer use exclusive file creation.
mkdir -- "$generation_capture_root" \
  || block generation_capture_invalid
PYTHONPATH="$PYTHON_ROOT" PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 \
  python3 -B "$GENERATION_CAPTURE_PROXY" --serve \
  --listen-port "$GENERATION_CAPTURE_PROXY_PORT" \
  --upstream-base-url "$gemma_base_url" \
  --capture-root "$generation_capture_root" \
  >"$work_root/generation-capture-proxy.stdout" \
  2>"$work_root/generation-capture-proxy.stderr" &
capture_proxy_pid="$!"
capture_ready=false
for _ in $(seq 1 30); do
  kill -0 "$capture_proxy_pid" 2>/dev/null || break
  capture_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
    --connect-timeout 1 --max-time 5 \
    "${GENERATION_CAPTURE_PROXY_BASE_URL}/health" 2>/dev/null || true)"
  if [[ "$capture_status" == 200 ]] \
    && grep -Fxq "v1_3_generation_capture_proxy=ready;port=${GENERATION_CAPTURE_PROXY_PORT}" \
      "$work_root/generation-capture-proxy.stdout"; then
    capture_ready=true
    break
  fi
  sleep 1
done
[[ "$capture_ready" == true ]] || block generation_capture_proxy_not_ready
emit "milestone=generation_capture_proxy;state=pass;port=${GENERATION_CAPTURE_PROXY_PORT};upstream=${gemma_base_url##*:};credential_retained=false"

current_stage=temporary_retrieval_api
installed_root="$work_root/staged/Ishikawa"
install -d -m 0755 -- "$installed_root/application/python/ishikawa" \
  "$installed_root/config" "$installed_root/scripts" \
  || block staged_product_install_failed
install -d -m 0700 -- "$installed_root/state/logs" "$installed_root/state/run" \
  || block staged_product_install_failed
while IFS= read -r source; do
  install -m 0644 -- "$source" \
    "$installed_root/application/python/ishikawa/$(basename -- "$source")" \
    || block staged_product_install_failed
done < <(find "$PACKAGE_ROOT" -maxdepth 1 -type f -name '*.py' -print | sort)
while IFS= read -r source; do
  install -m 0644 -- "$source" "$installed_root/config/$(basename -- "$source")" \
    || block staged_product_install_failed
done < <(find "$CONFIG_ROOT" -maxdepth 1 -type f -name '*.yaml' -print | sort)
install -m 0755 -- "$SERVICE_ENTRYPOINT" "$installed_root/scripts/ishikawa-retrieval-api" \
  || block staged_product_install_failed
PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$installed_root/config/deployment.yaml" "$TEMPORARY_POSTGRESQL_PORT" \
  2>"$work_root/staged-runtime-config.stderr" <<'PY' \
  || block staged_runtime_config_generation_failed
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
old = "postgresql:\n  bind_host: 127.0.0.1\n  port: 5432\n"
new = f"postgresql:\n  bind_host: 127.0.0.1\n  port: {sys.argv[2]}\n"
assert source.count(old) == 1
path.write_text(source.replace(old, new), encoding="utf-8")
PY
PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$installed_root/config/runtime_dependencies.yaml" \
  "$GENERATION_CAPTURE_PROXY_BASE_URL" "$nomic_base_url" \
  2>"$work_root/staged-dependency-config.stderr" <<'PY' \
  || block staged_dependency_config_generation_failed
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
old_gemma = "http://127.0.0.1:8000"
old_nomic = "http://127.0.0.1:8001"
assert source.count(old_gemma) == 3
assert source.count(old_nomic) == 2
path.write_text(
    source.replace(old_gemma, sys.argv[2]).replace(old_nomic, sys.argv[3]),
    encoding="utf-8",
)
PY
env -u ISHIKAWA_GEMMA_API_KEY -u ISHIKAWA_NOMIC_API_KEY \
  -u ISHIKAWA_POSTGRESQL_PASSWORD PYTHONDONTWRITEBYTECODE=1 \
  "$installed_root/scripts/ishikawa-retrieval-api" --check-config \
  >"$work_root/check-config.stdout" 2>"$work_root/check-config.stderr" \
  || block staged_configuration_invalid
ISHIKAWA_GEMMA_API_KEY="$gemma_key" \
ISHIKAWA_NOMIC_API_KEY="$nomic_key" \
ISHIKAWA_POSTGRESQL_PASSWORD="$database_password" \
PYTHONDONTWRITEBYTECODE=1 \
  "$installed_root/scripts/ishikawa-retrieval-api" --serve \
  >"$work_root/service.stdout" 2>"$work_root/service.stderr" &
service_pid="$!"
ready=false; ready_started="$(date +%s)"; ready_heartbeat=$(( ready_started + 30 ))
for _ in $(seq 1 300); do
  kill -0 "$service_pid" 2>/dev/null || break
  ready_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
    --connect-timeout 1 --max-time 5 "http://127.0.0.1:${API_PORT}/ready" 2>/dev/null || true)"
  if [[ "$ready_status" == 200 ]]; then ready=true; break; fi
  now="$(date +%s)"
  if (( now >= ready_heartbeat )); then
    emit "milestone=temporary_retrieval_api;state=starting;elapsed_seconds=$(( now - ready_started ))"
    ready_heartbeat=$(( now + 30 ))
  fi
  sleep 1
done
[[ "$ready" == true ]] || block temporary_retrieval_api_not_ready
emit 'milestone=temporary_retrieval_api;state=pass;readiness=ready;corpus=synthetic-corpus-v3'

current_stage=catalog_routing_canaries
emit 'milestone=catalog_routing_canaries;state=start;cases=9;scenarios=legal_first_legal_repeat_legal_all_identifier_direct_identifier_recovery_access_authorization_direct_access_authorization_followup_controlled_access_exception_direct_controlled_access_exception_followup;failure_behavior=collect_all_catalog_failures_then_stop_before_multiturn_and_complete_api_gates'
PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 \
  python3 -B "$CATALOG_ROUTING_EVALUATOR" --run --endpoint "$API_ENDPOINT" \
  >"$work_root/catalog-routing-evaluator.stdout" \
  2>"$work_root/catalog-routing-evaluator.stderr" &
active_pid="$!"
wait_with_heartbeat "$active_pid" catalog_routing_canaries \
  "$work_root/catalog-routing-evaluator.stdout" \
  || {
    active_pid=''
    tail -n 60 "$work_root/catalog-routing-evaluator.stdout" \
      "$work_root/catalog-routing-evaluator.stderr" | tee -a "$report_path"
    reason="$(sed -n 's/^v1_3_catalog_routing_evaluation=blocked;reason=\([a-z0-9_]*\)$/\1/p' "$work_root/catalog-routing-evaluator.stderr" | tail -n 1)"
    block "catalog_routing_${reason:-unclassified_evaluation_failure}"
  }
active_pid=''
grep -Fxq 'v1_3_catalog_routing_evaluation=pass' \
  "$work_root/catalog-routing-evaluator.stdout" \
  || block catalog_routing_pass_marker_missing
catalog_routing_summary="$(sed -n 's/^\(catalog_routing=.*\)$/\1/p' "$work_root/catalog-routing-evaluator.stdout" | tail -n 1)"
[[ "$catalog_routing_summary" =~ ^catalog_routing=pass\;cases=9/9\;legal_first_turn=answered\;legal_repeat_equivalent=true\;legal_all_complete=true\;identifier_direct=answered\;identifier_recovery=answered\;access_authorization_direct=answered\;access_authorization_followup=answered\;controlled_access_exception_direct=answered\;controlled_access_exception_followup=answered\;request_ids=([0-9a-f]{64},){8}[0-9a-f]{64}$ ]] \
  || block catalog_routing_summary_invalid
emit "milestone=catalog_routing_canaries;state=pass;$catalog_routing_summary"

current_stage=multiturn_resolution_canary
emit 'milestone=multiturn_resolution_canary;state=start;scenario=clarification_followup_credential_exposure_form;failure_behavior=stop_before_complete_api_gate'
PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 \
  python3 -B "$MULTITURN_EVALUATOR" --run --endpoint "$API_ENDPOINT" \
  >"$work_root/multiturn-evaluator.stdout" \
  2>"$work_root/multiturn-evaluator.stderr" &
active_pid="$!"
wait_with_heartbeat "$active_pid" multiturn_resolution_canary \
  "$work_root/multiturn-evaluator.stdout" \
  || {
    active_pid=''
    tail -n 40 "$work_root/multiturn-evaluator.stdout" \
      "$work_root/multiturn-evaluator.stderr" | tee -a "$report_path"
    reason="$(sed -n 's/^v1_3_multiturn_resolution_evaluation=blocked;reason=\([a-z0-9_]*\)$/\1/p' "$work_root/multiturn-evaluator.stderr" | tail -n 1)"
    block "multiturn_resolution_${reason:-unclassified_evaluation_failure}"
  }
active_pid=''
grep -Fxq 'v1_3_multiturn_resolution_evaluation=pass' \
  "$work_root/multiturn-evaluator.stdout" \
  || block multiturn_resolution_pass_marker_missing
multiturn_summary="$(sed -n 's/^\(multiturn_resolution=.*\)$/\1/p' "$work_root/multiturn-evaluator.stdout" | tail -n 1)"
[[ "$multiturn_summary" =~ ^multiturn_resolution=pass\;status=answered\;sources=[1-9][0-9]*\;applicability_document=99_TST_2043\;applicability_page=1\;form_document=TST_9030\;form_page=1\;both_cited=true\;request_id=[0-9a-f]{64}$ ]] \
  || block multiturn_resolution_summary_invalid
emit "milestone=multiturn_resolution_canary;state=pass;$multiturn_summary"

current_stage=complete_api_gate
emit "milestone=complete_api_gate;state=start;cases=${EXPECTED_CASES};responsive=${EXPECTED_RESPONSIVE};nonresponsive=${EXPECTED_NONRESPONSIVE};broad_navigation=${EXPECTED_BROAD_NAVIGATION};required_evidence=${EXPECTED_REQUIRED_EVIDENCE}"
kill -0 "$capture_proxy_pid" 2>/dev/null || block generation_capture_proxy_exited
priority_case_arguments=()
if [[ "$qualification_profile" == frontier_60 ]]; then
  priority_case_arguments=(
    --priority-case-id R-028
    --priority-case-id R-012
    --priority-case-id R-016
    --priority-case-id R-036
    --priority-case-id R-048
    --priority-case-id R-052
    --priority-case-id R-054
  )
  emit 'frontier_priority_canaries=R-028,R-012,R-016,R-036,R-048,R-052,R-054;failure_behavior=stop_before_remaining_cases'
fi
PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 \
  python3 -B "$API_EVALUATOR" --run --endpoint "$API_ENDPOINT" \
  --cases "$API_CASES" --output "$api_artifact" \
  --expected-hostname "$EXPECTED_HOSTNAME" \
  --expected-os-version "$EXPECTED_OS_VERSION" \
  --expected-architecture "$EXPECTED_ARCHITECTURE" \
  "${priority_case_arguments[@]}" \
  >"$work_root/api-evaluator.stdout" 2>"$work_root/api-evaluator.stderr" &
active_pid="$!"
wait_with_heartbeat "$active_pid" complete_api_gate "$work_root/api-evaluator.stdout" \
  || {
    active_pid=''
    reason="$(sed -n 's/^v1_3_complete_api_evaluation=blocked;reason=\([a-z0-9_]*\)$/\1/p' "$work_root/api-evaluator.stdout" | tail -n 1)"
    block "complete_api_${reason:-unclassified_evaluation_failure}"
  }
active_pid=''
grep -Fxq 'v1_3_complete_api_evaluation=pass' "$work_root/api-evaluator.stdout" \
  || block complete_api_pass_marker_missing
if [[ "$qualification_profile" == frontier_60 ]]; then
  grep -Fxq 'priority_canary_set=pass;complete_gate_enabled=true' \
    "$work_root/api-evaluator.stdout" \
    || block complete_api_priority_canary_marker_missing
  emit 'priority_canary_set=pass;complete_gate_enabled=true'
fi
summary="$(sed -n 's/^\(complete_api_cases=.*\)$/\1/p' "$work_root/api-evaluator.stdout" | tail -n 1)"
expected_summary="complete_api_cases=${EXPECTED_CASES};expected_status_matches=${EXPECTED_CASES}/${EXPECTED_CASES};required_evidence_returned=${EXPECTED_REQUIRED_EVIDENCE}/${EXPECTED_REQUIRED_EVIDENCE};required_evidence_cited=${EXPECTED_REQUIRED_EVIDENCE}/${EXPECTED_REQUIRED_EVIDENCE};dependency_failures=0"
[[ "$summary" == "$expected_summary" ]] \
  || block complete_api_summary_invalid

current_stage=generation_capture_validation
kill -TERM "$capture_proxy_pid" 2>/dev/null || block generation_capture_proxy_exited
for _ in $(seq 1 40); do
  kill -0 "$capture_proxy_pid" 2>/dev/null || break
  sleep 0.25
done
kill -0 "$capture_proxy_pid" 2>/dev/null && block generation_capture_proxy_exited
if ! wait "$capture_proxy_pid"; then
  capture_proxy_pid=''
  block generation_capture_proxy_exited
fi
capture_proxy_pid=''
grep -Eq '^v1_3_generation_capture_proxy=stopped;captures=[1-9][0-9]*$' \
  "$work_root/generation-capture-proxy.stdout" \
  || block generation_capture_missing
PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$generation_capture_root" "$API_CASES" <<'PY' \
  || block generation_capture_invalid
import hashlib
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
case_set = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
r001 = next(case for case in case_set["cases"] if case["case_id"] == "R-001")
attempts = sorted(root.glob("attempt-*"))
assert attempts
assert [item.name for item in attempts] == [
    f"attempt-{index:02d}" for index in range(1, len(attempts) + 1)
]
r001_found = False
for index, attempt in enumerate(attempts, 1):
    assert attempt.is_dir() and not attempt.is_symlink()
    assert {item.name for item in attempt.iterdir()} == {
        "analysis.json", "request-body.json", "response-body.json", "summary.txt"
    }
    request_bytes = (attempt / "request-body.json").read_bytes()
    response_bytes = (attempt / "response-body.json").read_bytes()
    analysis = json.loads((attempt / "analysis.json").read_text(encoding="utf-8"))
    request = json.loads(request_bytes.decode("utf-8"))
    generation_payload = json.loads(request["messages"][1]["content"])
    r001_found |= generation_payload["question"] == r001["question"]
    assert analysis["attempt"] == index
    assert analysis["synthetic_content_only"] is True
    assert analysis["request_sha256"] == hashlib.sha256(request_bytes).hexdigest()
    assert analysis["response_sha256"] == hashlib.sha256(response_bytes).hexdigest()
    assert analysis["validator"] in {"pass", "blocked"}
    assert re.fullmatch(r"[0-9a-f]{64}", analysis["request_sha256"])
    assert re.fullmatch(r"[0-9a-f]{64}", analysis["response_sha256"])
assert r001_found
PY
capture_count="$(find "$generation_capture_root" -mindepth 1 -maxdepth 1 -type d -name 'attempt-*' -print | wc -l | tr -d ' ')"
emit "milestone=generation_capture_validation;state=pass;captures=$capture_count;r001_present=true;authorization_retained=false"

current_stage=retained_artifact_validation
PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$database_artifact" "$api_artifact" "$EXPECTED_CASES" \
  "$EXPECTED_REQUIRED_EVIDENCE" <<'PY' \
  || block retained_artifact_validation_failed
import json
import pathlib
import sys

database = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
api = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
expected_cases = int(sys.argv[3])
expected_evidence = int(sys.argv[4])
assert database["artifact_kind"] == "ishikawa_isolated_synthetic_corpus_v3_database_qualification"
assert database["status"] == "pass"
assert database["corpus_identity"] == "synthetic-corpus-v3"
assert database["inventory"]["documents"] == 30
assert database["inventory"]["pages"] == 150
assert database["inventory"]["authoritative_chunks"] == 786
assert database["inventory"]["retrieval_candidates"] == 943
assert database["inventory"]["retrieval_scoring_only"] == 157
assert database["inventory"]["relationship_pairs"] == 90
assert database["checks"]["candidate_identity_and_text"] == "943/943"
assert database["checks"]["embeddings_present"] == "943/943"
assert database["checks"]["relationship_pairs"] == "90/90"
assert database["checks"]["runtime_flat_file_index"] is False
summary = api["summary"]
assert api["artifact_kind"] == "ishikawa_v1_3_complete_api_qualification"
assert api["synthetic_content_only"] is True
assert api["canary"] == {"abort_reason": None, "case_id": "R-001", "passed": True}
expected_priority = (
    ["R-028", "R-012", "R-016", "R-036", "R-048", "R-052", "R-054"]
    if expected_cases == 60 else []
)
assert api["execution_order"][0] == "R-001"
assert api["execution_order"][1:1 + len(expected_priority)] == expected_priority
assert api["priority_canary"] == {
    "abort_case": None,
    "abort_reason": None,
    "passed_case_ids": expected_priority,
    "requested_case_ids": expected_priority,
}
assert summary["acceptance_gate"] == "pass"
assert summary["case_count"] == expected_cases
assert summary["contract_valid_count"] == expected_cases
assert summary["expected_status_match_count"] == expected_cases
assert summary["required_evidence_count"] == expected_evidence
assert summary["required_evidence_returned_count"] == expected_evidence
assert summary["required_evidence_cited_count"] == expected_evidence
assert summary["dependency_failure_count"] == 0
PY
api_artifact_sha256="$(sha256sum -- "$api_artifact" | awk '{print $1}')"
printf '%s  %s\n' "$api_artifact_sha256" "$(basename -- "$api_artifact")" \
  >"$api_artifact.sha256"
emit "milestone=complete_api_gate;state=pass;$summary;artifact_sha256=$api_artifact_sha256"
if [[ "$qualification_profile" == frontier_60 ]]; then
  emit 'qualification=pass;corpus_v3_database=pass;catalog_routing=9/9;multiturn_resolution=pass;frontier_60=pass;self_validation=pass'
  emit 'next_gate=local_human_ui_validation'
else
  emit 'qualification=pass;corpus_v3_database=pass;catalog_routing=9/9;multiturn_resolution=pass;complete_api=pass;self_validation=pass'
  emit 'next_gate=promote_corpus_v3_and_assemble_frontier_v1_3_candidate'
fi
emit "database_artifact=$database_artifact"
emit "api_artifact=$api_artifact"
current_stage=complete

