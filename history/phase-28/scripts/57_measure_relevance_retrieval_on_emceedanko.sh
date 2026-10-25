#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Measure responsive and nonresponsive retrieval signals against synthetic
#   content in a disposable application-host PostgreSQL database.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/57_measure_relevance_retrieval_on_emceedanko.sh --run

usage() {
  sed -n '3,10p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run                      Authorize the disposable target measurement.' \
    '  --target VALUE             SSH destination or configured SSH alias.' \
    '  --expected-hostname NAME   Exact target short hostname.' \
    '  --expected-os-version VER  Exact expected Ubuntu major.minor version.' \
    '  --identity-file PATH       Optional explicit SSH private key.' \
    '  --validate-only            Validate all sources without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$ISHIKAWA_ROOT/application/python/ishikawa"
readonly TARGET_HELPER="$SCRIPT_DIR/calibrate-held-out-retrieval"
readonly TARGET_RUNNER="$SCRIPT_DIR/measure_relevance_retrieval.py"
readonly LOCAL_EVALUATOR="$SCRIPT_DIR/evaluate_relevance_retrieval.py"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly ADAPTER_TESTS="$ISHIKAWA_ROOT/tests/artifact_adapter_checks.py"
readonly FIXTURE_ROOT="$ISHIKAWA_ROOT/tests/fixtures/pipeline_writer"
readonly SOURCE_ROOT="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/anderson-upload"
readonly CASES="$REPO_ROOT/local/artifacts/ishikawa/relevance-calibration-input/relevance_cases_v1.json"
readonly NORMALIZED="$REPO_ROOT/local/artifacts/ishikawa/normalization/normalized_structural_units_20261019T214207Z.json"
readonly CHUNKS="$REPO_ROOT/local/artifacts/ishikawa/retrieval-gap-method-profile/structural_chunk_candidates_20261020T002645Z.json"
readonly DOCUMENT_EMBEDDINGS="$REPO_ROOT/local/artifacts/ishikawa/retrieval-gap-method-profile/measured_nomic_chunk_embeddings_20261020T002645Z.json"
readonly ACCEPTED_QUERY_EMBEDDINGS="$REPO_ROOT/local/artifacts/ishikawa/relevance-query-embeddings/measured_nomic_relevance_query_embeddings_20261020T042140Z.json"
readonly MIGRATION_0001="$PHASE_ROOT/migrations/0001_initial_rag_catalog.sql"
readonly MIGRATION_0002="$PHASE_ROOT/migrations/0002_align_ingestion_ownership.sql"
readonly MIGRATION_0003="$PHASE_ROOT/migrations/0003_separate_special_token_count.sql"
readonly MIGRATION_0004="$PHASE_ROOT/migrations/0004_preserve_relationship_override_audit.sql"
readonly ACCEPTED_DATABASE_REPORT="$REPO_ROOT/local/reports/ishikawa-four-bucket-pipeline-writer-integration/four_bucket_pipeline_writer_integration_20261019T231406Z_F00dU4.txt"
readonly ACCEPTED_PROFILE_REPORT="$REPO_ROOT/local/reports/ishikawa-retrieval-profile-freeze/retrieval_profile_freeze_20261020T004819Z_LojmOl.txt"
readonly ACCEPTED_CASE_REPORT="$REPO_ROOT/local/reports/ishikawa-relevance-case-contract/relevance_case_contract_20261020T040222Z_mTwrP1.txt"
readonly ACCEPTED_QUERY_REPORT="$REPO_ROOT/local/reports/ishikawa-relevance-query-embedding/relevance_query_embedding_20261020T042140Z_knr636.txt"
readonly ACCEPTED_SCHEMA_V4_REPORT="$REPO_ROOT/local/reports/native-postgresql-relationship-override-audit-migration/relationship_override_audit_migration_20261020T014143Z_pEVwvS.txt"
readonly CASES_SHA256='2fa6a20fc77f1faa25d141838b50ad0e95e2467035a0193d7f94451202cd94da'
readonly NORMALIZED_SHA256='736d619ac5a7e10f768bdb8b8f3f117cb52231f8dc2f4d186d52d96c8bd41e28'
readonly CHUNKS_SHA256='bc993ca0a417353f0d2313bcb2d1c94a1d526a513253139be71117bf88626bf3'
readonly DOCUMENT_EMBEDDINGS_SHA256='5bd79048bb59d53b6f6903eec9f4797955763a5fc12c064b17d19db89ba9d641'
readonly ACCEPTED_QUERY_EMBEDDINGS_SHA256='517fbd372b89b9090a9c0fc13e7f292aae73d5a245302dc19e74c7cafd52e1a8'
readonly MIGRATION_0003_SHA256='5e833d8ff556c0e6158daf0419b1013235a11e1a94f1f560206ba813e1fc3761'
readonly MIGRATION_0004_SHA256='5764f6e12a74b18747163c61ef3f314e8dff140a3586b298c62be616a1dc185f'
readonly ACCEPTED_DATABASE_REPORT_SHA256='1c7a96b411746528ae0babb2bb83352f1873c2275a160f61af0ed59767fda9de'
readonly ACCEPTED_PROFILE_REPORT_SHA256='8a8de4990700530c794ef86bcc8f22b50278603701822649b73012bfc96db114'
readonly ACCEPTED_CASE_REPORT_SHA256='5fd84f351a062373dd49894f912d243647fa2a33206d895c73de447822ce8693'
readonly ACCEPTED_QUERY_REPORT_SHA256='e608b9e7be0969e25185e1de4467cde3e4617bb0caa145b37c924d5865044e23'
readonly ACCEPTED_SCHEMA_V4_REPORT_SHA256='448f4bc3c124dcc34e66c3429639722a515a2b888b5d2deeba2b49c1eb00a446'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-relevance-retrieval-observation"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/relevance-retrieval-observations"

python_sources=(
  "$PYTHON_ROOT/__init__.py" "$PYTHON_ROOT/artifact_adapter.py" "$PYTHON_ROOT/canonical.py"
  "$PYTHON_ROOT/errors.py" "$PYTHON_ROOT/models.py" "$PYTHON_ROOT/persistence.py"
  "$PYTHON_ROOT/persistence_models.py" "$PYTHON_ROOT/planner.py" "$PYTHON_ROOT/reasons.py"
  "$PYTHON_ROOT/reporting.py" "$PYTHON_ROOT/retrieval.py" "$PYTHON_ROOT/validators.py"
  "$PYTHON_ROOT/yaml_loader.py" "$PYTHON_ROOT/method_profile.py" "$PYTHON_ROOT/relationships.py"
)
config_sources=(
  "$FIXTURE_ROOT/document_classes.yaml" "$FIXTURE_ROOT/document_catalog.yaml"
  "$FIXTURE_ROOT/ingestion_manifest.yaml"
)
pdf_sources=(
  "$SOURCE_ROOT/31_SCH_2003.pdf" "$SOURCE_ROOT/Form_TST9001.pdf"
  "$SOURCE_ROOT/Governance_Manual_2005_Revision_3.pdf" "$SOURCE_ROOT/OPS_17_CTL_2001.pdf"
  "$SOURCE_ROOT/OPS_17_CTL_2002_RevA.pdf" "$SOURCE_ROOT/SOP_42_IR_2006.pdf"
)

target="${APPLICATION_HOST_TARGET:-DankoSurface_EmceeDanko}"
expected_hostname="${APPLICATION_HOST_EXPECTED_HOSTNAME:-EmceeDanko}"
expected_os_version="${APPLICATION_HOST_EXPECTED_OS_VERSION:-24.04}"
identity_file="${APPLICATION_HOST_IDENTITY_FILE:-}"
run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --target) target="${2:-}"; shift 2 ;;
    --expected-hostname) expected_hostname="${2:-}"; shift 2 ;;
    --expected-os-version) expected_os_version="${2:-}"; shift 2 ;;
    --identity-file) identity_file="${2:-}"; shift 2 ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'ERROR: unsupported argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$run_authorized" != "$validate_only" ]] || { printf 'BLOCKED: choose exactly one of --run or --validate-only.\n' >&2; exit 2; }
[[ "$target" =~ ^[A-Za-z0-9_@.:-]+$ ]] || { printf 'BLOCKED: invalid SSH target or alias.\n' >&2; exit 2; }
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || { printf 'BLOCKED: invalid expected hostname.\n' >&2; exit 2; }
[[ "$expected_os_version" =~ ^[0-9]{2}\.[0-9]{2}$ ]] || { printf 'BLOCKED: invalid expected Ubuntu version.\n' >&2; exit 2; }
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] || { printf 'BLOCKED: identity file is unsafe.\n' >&2; exit 2; }
fi
for required in awk bash basename cat chmod cp date env grep install mkdir mktemp python3 rm scp sed sha256sum ssh stat tee timeout tr wc; do
  command -v "$required" >/dev/null 2>&1 || { printf 'BLOCKED: missing local command: %s\n' "$required" >&2; exit 2; }
done
for source in "$TARGET_HELPER" "$TARGET_RUNNER" "$LOCAL_EVALUATOR" "$TEST_RUNNER" "$ADAPTER_TESTS" "$CASES" "$NORMALIZED" "$CHUNKS" "$DOCUMENT_EMBEDDINGS" "$ACCEPTED_QUERY_EMBEDDINGS" "$MIGRATION_0001" "$MIGRATION_0002" "$MIGRATION_0003" "$MIGRATION_0004" "$ACCEPTED_DATABASE_REPORT" "$ACCEPTED_PROFILE_REPORT" "$ACCEPTED_CASE_REPORT" "$ACCEPTED_QUERY_REPORT" "$ACCEPTED_SCHEMA_V4_REPORT" "${python_sources[@]}" "${config_sources[@]}" "${pdf_sources[@]}"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || { printf 'BLOCKED: a required Script 57 input is missing or unsafe.\n' >&2; exit 2; }
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || { printf 'BLOCKED: %s checksum mismatch.\n' "$3" >&2; exit 2; }
}
check_sha256 "$CASES" "$CASES_SHA256" 'protected relevance cases'
check_sha256 "$NORMALIZED" "$NORMALIZED_SHA256" 'accepted normalization artifact'
check_sha256 "$CHUNKS" "$CHUNKS_SHA256" 'accepted chunk artifact'
check_sha256 "$DOCUMENT_EMBEDDINGS" "$DOCUMENT_EMBEDDINGS_SHA256" 'accepted document embeddings'
check_sha256 "$ACCEPTED_QUERY_EMBEDDINGS" "$ACCEPTED_QUERY_EMBEDDINGS_SHA256" 'accepted relevance query embeddings'
check_sha256 "$MIGRATION_0003" "$MIGRATION_0003_SHA256" 'accepted schema-v3 migration'
check_sha256 "$MIGRATION_0004" "$MIGRATION_0004_SHA256" 'accepted schema-v4 migration'
check_sha256 "$ACCEPTED_DATABASE_REPORT" "$ACCEPTED_DATABASE_REPORT_SHA256" 'accepted database report'
check_sha256 "$ACCEPTED_PROFILE_REPORT" "$ACCEPTED_PROFILE_REPORT_SHA256" 'accepted retrieval profile report'
check_sha256 "$ACCEPTED_CASE_REPORT" "$ACCEPTED_CASE_REPORT_SHA256" 'accepted relevance case report'
check_sha256 "$ACCEPTED_QUERY_REPORT" "$ACCEPTED_QUERY_REPORT_SHA256" 'accepted relevance query report'
check_sha256 "$ACCEPTED_SCHEMA_V4_REPORT" "$ACCEPTED_SCHEMA_V4_REPORT_SHA256" 'accepted schema-v4 report'
grep -Fq 'script_31_four_bucket_pipeline_writer=pass;' "$ACCEPTED_DATABASE_REPORT" || { printf 'BLOCKED: accepted writer marker is absent.\n' >&2; exit 2; }
grep -Fq 'script_38_retrieval_profile_freeze=pass;' "$ACCEPTED_PROFILE_REPORT" || { printf 'BLOCKED: accepted retrieval profile marker is absent.\n' >&2; exit 2; }
grep -Fq 'script_55_relevance_case_contract=pass;' "$ACCEPTED_CASE_REPORT" || { printf 'BLOCKED: accepted relevance case marker is absent.\n' >&2; exit 2; }
grep -Fq 'script_56_relevance_query_embedding=pass;' "$ACCEPTED_QUERY_REPORT" || { printf 'BLOCKED: accepted relevance query marker is absent.\n' >&2; exit 2; }
grep -Fq 'script_41_relationship_override_audit_migration=pass;' "$ACCEPTED_SCHEMA_V4_REPORT" || { printf 'BLOCKED: accepted schema-v4 marker is absent.\n' >&2; exit 2; }

bash -n "$TARGET_HELPER" "$TEST_RUNNER"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' "$TARGET_RUNNER" "$LOCAL_EVALUATOR" "$ADAPTER_TESTS" "${python_sources[@]}"
python3 -B "$LOCAL_EVALUATOR" --self-test >/dev/null
for neutral_source in "$TARGET_HELPER" "$TARGET_RUNNER"; do
  if grep -Eq '(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)' "$neutral_source" || grep -Eiq 'phase[-_ ]?[0-9]+|Danko|org[_ -]?lab|Agent|repository' "$neutral_source"; then
    printf 'BLOCKED: development or environment jargon found in a neutral target source.\n' >&2
    exit 2
  fi
done

work_root="$(mktemp -d /tmp/ishikawa-script-57.XXXXXX)"
stage_root="$work_root/stage"
mkdir -m 0700 -p -- "$stage_root/payload/ishikawa" "$stage_root/payload/config" "$stage_root/payload/source"
report_path=''
remote_root=''
remote_created=false
master_started=false
ssh_args=()
emit() { if [[ -n "$report_path" ]]; then printf '%s\n' "$1" | tee -a "$report_path"; else printf '%s\n' "$1"; fi; }
cleanup() {
  local status="$?" cleanup_code=0 close_code=0
  trap - EXIT INT TERM
  set +e
  if [[ "$remote_created" == true && "$master_started" == true ]]; then
    timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "rm -rf -- '$remote_root'" >/dev/null 2>&1 || cleanup_code=$?
    if (( cleanup_code == 0 )); then emit 'cleanup_remote_temporary_files=removed'; else emit "cleanup_remote_temporary_files=review_required;exit_code=$cleanup_code"; status=1; fi
  else
    emit 'cleanup_remote_temporary_files=not_required'
  fi
  if [[ "$master_started" == true ]]; then
    timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1 || close_code=$?
    emit "cleanup_ssh_master_exit_code=$close_code"
    (( close_code == 0 )) || status=1
  fi
  if [[ "$work_root" == /tmp/ishikawa-script-57.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

base_result="$work_root/base-tests.txt"
bash "$TEST_RUNNER" >"$base_result" 2>&1 || { cat "$base_result" >&2; printf 'script_57_relevance_retrieval_observation=blocked;reason=base_regression\n' >&2; exit 1; }
grep -Fq 'Ran 195 tests' "$base_result" || { printf 'script_57_relevance_retrieval_observation=blocked;reason=base_test_count_mismatch\n' >&2; exit 1; }
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$base_result" || { printf 'script_57_relevance_retrieval_observation=blocked;reason=base_pass_marker_absent\n' >&2; exit 1; }
adapter_result="$work_root/adapter-tests.txt"
env PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$ISHIKAWA_ROOT/application/python" python3 "$ADAPTER_TESTS" -v >"$adapter_result" 2>&1 || { cat "$adapter_result" >&2; printf 'script_57_relevance_retrieval_observation=blocked;reason=adapter_regression\n' >&2; exit 1; }
grep -Fq 'Ran 9 tests' "$adapter_result" || { printf 'script_57_relevance_retrieval_observation=blocked;reason=adapter_test_count_mismatch\n' >&2; exit 1; }
grep -Fxq 'OK' "$adapter_result" || { printf 'script_57_relevance_retrieval_observation=blocked;reason=adapter_pass_marker_absent\n' >&2; exit 1; }

queries_path="$stage_root/queries.json"
query_vectors_path="$stage_root/query-embeddings.json"
python3 -B - "$CASES" "$ACCEPTED_QUERY_EMBEDDINGS" "$queries_path" "$query_vectors_path" "$CASES_SHA256" "$ACCEPTED_QUERY_EMBEDDINGS_SHA256" <<'PY'
import hashlib
import json
import os
import sys

cases_path, embeddings_path, queries_path, vectors_path, cases_sha, embeddings_sha = sys.argv[1:]
cases = json.load(open(cases_path, encoding="utf-8"))
embeddings = json.load(open(embeddings_path, encoding="utf-8"))
records = {item["case_id"]: item for item in embeddings["records"]}
queries = []
vectors = []
for index, case in enumerate(cases["cases"], start=1):
    source_case_id = case["case_id"]
    target_case_id = f"C-{index:03d}"
    record = records[source_case_id]
    digest = hashlib.sha256(
        b"ishikawa.retrieval-question.v1\x00"
        + json.dumps({"question": case["question"]}, ensure_ascii=False, allow_nan=False, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()
    if digest != record["question_digest"]:
        raise SystemExit("query digest mismatch")
    queries.append({"case_id": target_case_id, "question": case["question"], "question_digest": digest})
    vectors.append({"case_id": target_case_id, "question_digest": digest, "vector": record["vector"], "vector_dimension": record["vector_dimension"]})
if len(queries) != 12 or len(vectors) != 12:
    raise SystemExit("relevance inventory mismatch")
documents = (
    {
        "schema_version": 1,
        "artifact_kind": "relevance_retrieval_queries",
        "source_case_set_sha256": cases_sha,
        "source_query_embedding_sha256": embeddings_sha,
        "cases": queries,
    },
    {
        "schema_version": 1,
        "artifact_kind": "relevance_retrieval_query_vectors",
        "source_query_embedding_sha256": embeddings_sha,
        "embedding_space_id": embeddings["embedding_space_id"],
        "case_count": 12,
        "query_method": embeddings["query_method"],
        "records": vectors,
    },
)
for path, document in zip((queries_path, vectors_path), documents):
    payload = json.dumps(document, ensure_ascii=False, allow_nan=False, sort_keys=True, separators=(",", ":")).encode()
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)
PY
if grep -Eq '"(class|required_citations|absence_terms|challenge_kind|source_case_id)"|"[RN]-[0-9]{3}"' "$queries_path" "$query_vectors_path"; then
  printf 'script_57_relevance_retrieval_observation=blocked;reason=calibration_truth_in_target_payload\n' >&2
  exit 1
fi
queries_sha256="$(sha256sum "$queries_path" | awk '{print $1}')"
query_vectors_sha256="$(sha256sum "$query_vectors_path" | awk '{print $1}')"

for source in "${python_sources[@]}"; do install -m 0600 "$source" "$stage_root/payload/ishikawa/$(basename "$source")"; done
for source in "${config_sources[@]}"; do install -m 0600 "$source" "$stage_root/payload/config/$(basename "$source")"; done
for source in "${pdf_sources[@]}"; do install -m 0600 "$source" "$stage_root/payload/source/$(basename "$source")"; done
env PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$stage_root/payload" python3 -B -c 'import ishikawa.method_profile, ishikawa.persistence, ishikawa.relationships, ishikawa.retrieval'
install -m 0600 "$TARGET_HELPER" "$stage_root/calibrate-held-out-retrieval"
install -m 0600 "$TARGET_RUNNER" "$stage_root/calibrate-held-out-retrieval.py"
install -m 0600 "$MIGRATION_0001" "$stage_root/0001_initial_rag_catalog.sql"
install -m 0600 "$MIGRATION_0002" "$stage_root/0002_align_ingestion_ownership.sql"
install -m 0600 "$MIGRATION_0003" "$stage_root/0003_separate_special_token_count.sql"
install -m 0600 "$MIGRATION_0004" "$stage_root/0004_preserve_relationship_override_audit.sql"
install -m 0600 "$NORMALIZED" "$stage_root/normalized.json"
install -m 0600 "$CHUNKS" "$stage_root/chunks.json"
install -m 0600 "$DOCUMENT_EMBEDDINGS" "$stage_root/embeddings.json"
printf '%s  %s\n' "$NORMALIZED_SHA256" normalized.json "$CHUNKS_SHA256" chunks.json "$DOCUMENT_EMBEDDINGS_SHA256" embeddings.json "$queries_sha256" queries.json "$query_vectors_sha256" query-embeddings.json >"$stage_root/artifact-identities.sha256"
chmod 0600 "$stage_root/artifact-identities.sha256"

payload_manifest="$stage_root/payload.sha256"
: >"$payload_manifest"
for source in "$stage_root"/payload/ishikawa/*.py; do printf '%s  payload/ishikawa/%s\n' "$(sha256sum "$source" | awk '{print $1}')" "$(basename "$source")" >>"$payload_manifest"; done
for source in "$stage_root"/payload/config/*.yaml; do printf '%s  payload/config/%s\n' "$(sha256sum "$source" | awk '{print $1}')" "$(basename "$source")" >>"$payload_manifest"; done
for source in "$stage_root"/payload/source/*.pdf; do printf '%s  payload/source/%s\n' "$(sha256sum "$source" | awk '{print $1}')" "$(basename "$source")" >>"$payload_manifest"; done
for name in normalized.json chunks.json embeddings.json queries.json query-embeddings.json artifact-identities.sha256 0001_initial_rag_catalog.sql 0002_align_ingestion_ownership.sql 0003_separate_special_token_count.sql 0004_preserve_relationship_override_audit.sql calibrate-held-out-retrieval.py; do printf '%s  %s\n' "$(sha256sum "$stage_root/$name" | awk '{print $1}')" "$name" >>"$payload_manifest"; done
manifest_sha256="$(sha256sum "$payload_manifest" | awk '{print $1}')"
helper_sha256="$(sha256sum "$TARGET_HELPER" | awk '{print $1}')"
runner_sha256="$(sha256sum "$TARGET_RUNNER" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$LOCAL_EVALUATOR" | awk '{print $1}')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_relevance_retrieval_observation_source' \
    'target_contact=false;database_contact=false;model_call=false;truth_transferred=false;threshold_selected=false' \
    "script_sha256=$script_sha256;helper_sha256=$helper_sha256;runner_sha256=$runner_sha256;evaluator_sha256=$evaluator_sha256" \
    "payload_manifest_sha256=$manifest_sha256;payload_file_count=$(wc -l <"$payload_manifest" | tr -d ' ')" \
    "case_set_sha256=$CASES_SHA256;accepted_query_embeddings_sha256=$ACCEPTED_QUERY_EMBEDDINGS_SHA256" \
    "accepted_schema_v4_report_sha256=$ACCEPTED_SCHEMA_V4_REPORT_SHA256;migration_0004_sha256=$MIGRATION_0004_SHA256" \
    "queries_sha256=$queries_sha256;query_vectors_sha256=$query_vectors_sha256;class_labels_in_target_payload=false" \
    'base_tests=195;adapter_tests=9;evaluator_self_tests=1;staged_package_import=pass;failures=0;errors=0' \
    'script_57_relevance_retrieval_observation_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/relevance_retrieval_observation_${timestamp}_XXXXXX.txt")"
remote_root="/tmp/held-out-retrieval-calibration-$timestamp-$$"
emit 'purpose=measure_relevance_retrieval_signals_in_disposable_native_postgresql'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;helper_sha256=$helper_sha256;runner_sha256=$runner_sha256;evaluator_sha256=$evaluator_sha256"
emit "payload_manifest_sha256=$manifest_sha256;queries_sha256=$queries_sha256;query_vectors_sha256=$query_vectors_sha256"
emit "case_set_sha256=$CASES_SHA256;accepted_query_embeddings_sha256=$ACCEPTED_QUERY_EMBEDDINGS_SHA256"
emit "accepted_schema_v4_report_sha256=$ACCEPTED_SCHEMA_V4_REPORT_SHA256;migration_0004_sha256=$MIGRATION_0004_SHA256"
emit 'authorized_actions=stage_verified_synthetic_artifacts_start_postgresql_create_disposable_database_apply_accepted_schema_write_synthetic_artifacts_measure_retrieval_fetch_observations_grade_locally_drop_disposable_database_verify_accepted_database_stop_postgresql_remove_temporary_files'
emit 'non_actions=no_package_change_no_accepted_database_mutation_no_organizational_document_read_no_model_call_no_secret_processing_no_service_enablement_no_calibration_truth_transfer_no_threshold_selection'
emit "selected_target=$target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version"
emit 'operator_expectation=ssh_key_passphrase_up_to_once;target_sudo_password_may_be_prompted;no_application_secret_prompt'

control_path="$work_root/ssh-control"
ssh_args=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto -o "ControlPath=$control_path" -o ControlPersist=1800)
if [[ -n "$identity_file" ]]; then ssh_args+=(-i "$identity_file" -o IdentitiesOnly=yes); fi
emit 'milestone=authentication;state=waiting_for_operator_if_prompted'
timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$target" >"$work_root/master.stdout" 2>"$work_root/master.stderr" || { emit 'script_57_relevance_retrieval_observation=blocked;reason=ssh_master_start_failed'; exit 1; }
master_started=true
emit 'milestone=authentication;state=pass'
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root' && mkdir -m 0700 -- '$remote_root/payload' '$remote_root/payload/ishikawa' '$remote_root/payload/config' '$remote_root/payload/source'" >"$work_root/create.stdout" 2>"$work_root/create.stderr" || { emit 'script_57_relevance_retrieval_observation=blocked;reason=remote_temporary_directory_not_created'; exit 1; }
remote_created=true
timeout --foreground 180 scp "${ssh_args[@]}" "$stage_root"/calibrate-held-out-retrieval "$stage_root"/calibrate-held-out-retrieval.py "$stage_root"/0001_initial_rag_catalog.sql "$stage_root"/0002_align_ingestion_ownership.sql "$stage_root"/0003_separate_special_token_count.sql "$stage_root"/0004_preserve_relationship_override_audit.sql "$stage_root"/normalized.json "$stage_root"/chunks.json "$stage_root"/embeddings.json "$stage_root"/queries.json "$stage_root"/query-embeddings.json "$stage_root"/artifact-identities.sha256 "$stage_root"/payload.sha256 "$target:$remote_root/" >"$work_root/scp-root.stdout" 2>"$work_root/scp-root.stderr" || { emit 'script_57_relevance_retrieval_observation=blocked;reason=root_payload_copy_failed'; exit 1; }
timeout --foreground 180 scp "${ssh_args[@]}" "$stage_root"/payload/ishikawa/*.py "$target:$remote_root/payload/ishikawa/" >"$work_root/scp-python.stdout" 2>"$work_root/scp-python.stderr" || { emit 'script_57_relevance_retrieval_observation=blocked;reason=python_payload_copy_failed'; exit 1; }
timeout --foreground 120 scp "${ssh_args[@]}" "$stage_root"/payload/config/*.yaml "$target:$remote_root/payload/config/" >"$work_root/scp-config.stdout" 2>"$work_root/scp-config.stderr" || { emit 'script_57_relevance_retrieval_observation=blocked;reason=config_payload_copy_failed'; exit 1; }
timeout --foreground 180 scp "${ssh_args[@]}" "$stage_root"/payload/source/*.pdf "$target:$remote_root/payload/source/" >"$work_root/scp-source.stdout" 2>"$work_root/scp-source.stderr" || { emit 'script_57_relevance_retrieval_observation=blocked;reason=source_payload_copy_failed'; exit 1; }
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "cd '$remote_root' && printf '%s  %s\n%s  %s\n' '$helper_sha256' calibrate-held-out-retrieval '$manifest_sha256' payload.sha256 | sha256sum --check --strict -" >"$work_root/hash.stdout" 2>"$work_root/hash.stderr" || { emit 'script_57_relevance_retrieval_observation=blocked;reason=target_outer_payload_hash_mismatch'; exit 1; }
emit 'milestone=target_payload_verification;state=pass'

emit 'milestone=relevance_retrieval_measurement;state=waiting_for_operator_sudo_if_prompted'
set +e
timeout --foreground 1200 ssh -tt "${ssh_args[@]}" -o BatchMode=yes "$target" "cd '$remote_root' && sudo -p '[sudo] password for disposable relevance measurement: ' bash ./calibrate-held-out-retrieval '$expected_hostname' '$expected_os_version' rag_catalog rag_owner rag_ingest rag_retrieval '$remote_root' '$manifest_sha256' > relevance-retrieval-observation.txt" < /dev/tty
remote_code=$?
set -e
emit "remote_execution_exit_code=$remote_code;raw_stderr_retained=false"
fetched_result="$work_root/relevance-retrieval-observation.txt"
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/relevance-retrieval-observation.txt" "$fetched_result" >"$work_root/fetch-result.stdout" 2>"$work_root/fetch-result.stderr" || { emit 'script_57_relevance_retrieval_observation=blocked;reason=result_fetch_failed'; exit 1; }
output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then output_contract=blocked; continue; fi
  emit "$line"
done <"$fetched_result"
emit "remote_output_contract=$output_contract"
pass_markers="$(grep -Fxc 'held_out_retrieval_target_calibration=pass' "$fetched_result" || true)"
blocked_markers="$(grep -Ec '^held_out_retrieval_target_calibration=blocked;' "$fetched_result" || true)"
if (( remote_code != 0 )) || [[ "$output_contract" != pass || "$pass_markers" != 1 || "$blocked_markers" != 0 ]]; then
  emit 'milestone=relevance_retrieval_measurement;state=blocked'
  emit "script_57_relevance_retrieval_observation=blocked;local_report=$report_path;next_gate=inspect_target_result_before_any_retry"
  exit 1
fi
fetched_observations="$work_root/retrieval-observations.json"
timeout --foreground 180 scp "${ssh_args[@]}" "$target:$remote_root/retrieval-observations.json" "$fetched_observations" >"$work_root/fetch-observations.stdout" 2>"$work_root/fetch-observations.stderr" || { emit 'script_57_relevance_retrieval_observation=blocked;reason=observation_artifact_fetch_failed'; exit 1; }
emit 'milestone=relevance_retrieval_measurement;state=pass'

emit 'milestone=local_protected_relevance_evaluation;state=start'
evaluation_result="$work_root/evaluation-result.txt"
set +e
python3 -B "$LOCAL_EVALUATOR" --cases "$CASES" --expected-cases-sha256 "$CASES_SHA256" --chunks "$CHUNKS" --expected-chunks-sha256 "$CHUNKS_SHA256" --queries "$queries_path" --expected-queries-sha256 "$queries_sha256" --query-embeddings "$query_vectors_path" --expected-query-embeddings-sha256 "$query_vectors_sha256" --expected-source-query-embeddings-sha256 "$ACCEPTED_QUERY_EMBEDDINGS_SHA256" --expected-document-embeddings-sha256 "$DOCUMENT_EMBEDDINGS_SHA256" --observations "$fetched_observations" >"$evaluation_result"
evaluation_code=$?
set -e
evaluation_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then evaluation_contract=blocked; continue; fi
  emit "$line"
done <"$evaluation_result"
evaluation_pass_markers="$(grep -Fxc 'relevance_retrieval_evaluation=pass' "$evaluation_result" || true)"
evaluation_blocked_markers="$(grep -Ec '^relevance_retrieval_evaluation=blocked;' "$evaluation_result" || true)"
emit "evaluation_exit_code=$evaluation_code;evaluation_output_contract=$evaluation_contract;evaluation_pass_markers=$evaluation_pass_markers;evaluation_blocked_markers=$evaluation_blocked_markers"
if (( evaluation_code != 0 )) || [[ "$evaluation_contract" != pass || "$evaluation_pass_markers" != 1 || "$evaluation_blocked_markers" != 0 ]]; then
  emit 'milestone=local_protected_relevance_evaluation;state=blocked'
  emit "script_57_relevance_retrieval_observation=blocked;local_report=$report_path;next_gate=inspect_local_evaluation_before_any_retry"
  exit 1
fi
emit 'milestone=local_protected_relevance_evaluation;state=pass'

artifact_sha256="$(sha256sum "$fetched_observations" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$fetched_observations")"
artifact_path="$ARTIFACT_ROOT/relevance_retrieval_observations_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || { emit 'script_57_relevance_retrieval_observation=blocked;reason=local_artifact_path_exists'; exit 1; }
cp -- "$fetched_observations" "$artifact_path"
check_sha256 "$artifact_path" "$artifact_sha256" 'retained relevance observation artifact'
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true
emit "accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$artifact_bytes"
emit "accepted_artifact=$artifact_path;accepted_checksum=$checksum_path"
emit 'threshold_selected=false;publication_eligible=false'
emit "script_57_relevance_retrieval_observation=pass;local_report=$report_path;next_gate=review_relevance_signal_separation"
exit 0
