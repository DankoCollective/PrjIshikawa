#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Prove the accepted normalization, chunk, and Nomic embedding artifacts
#   through the schema-v3 four-bucket writer in a disposable PostgreSQL database.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/31_test_four_bucket_pipeline_writer_on_emceedanko.sh --run

usage() {
  sed -n '3,9p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run                      Explicitly authorize the disposable proof.' \
    '  --target VALUE             SSH destination or configured SSH alias.' \
    '  --expected-hostname NAME   Exact target short hostname.' \
    '  --expected-os-version VER  Exact expected Ubuntu major.minor version.' \
    '  --identity-file PATH       Optional explicit SSH private key.' \
    '  --report-root PATH         Absolute local result directory.' \
    '  --validate-only            Validate all sources without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$ISHIKAWA_ROOT/application/python/ishikawa"
readonly TARGET_HELPER="$SCRIPT_DIR/test-four-bucket-pipeline-writer-integration"
readonly TEST_RUNNER="$SCRIPT_DIR/test-four-bucket-pipeline-writer-integration.py"
readonly ADAPTER_TESTS="$ISHIKAWA_ROOT/tests/artifact_adapter_checks.py"
readonly BASE_TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly FIXTURE_ROOT="$ISHIKAWA_ROOT/tests/fixtures/pipeline_writer"
readonly SOURCE_ROOT="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/anderson-upload"
readonly NORMALIZED="$REPO_ROOT/local/artifacts/ishikawa/normalization/normalized_structural_units_20261019T214207Z.json"
readonly CHUNKS="$REPO_ROOT/local/artifacts/ishikawa/chunking/structural_chunk_candidates_20261019T214924Z.json"
readonly EMBEDDINGS="$REPO_ROOT/local/artifacts/ishikawa/embeddings/measured_nomic_chunk_embeddings_20261019T224719Z.json"
readonly MIGRATION_0001="$PHASE_ROOT/migrations/0001_initial_rag_catalog.sql"
readonly MIGRATION_0002="$PHASE_ROOT/migrations/0002_align_ingestion_ownership.sql"
readonly MIGRATION_0003="$PHASE_ROOT/migrations/0003_separate_special_token_count.sql"
readonly ACCEPTED_DATABASE_REPORT="$REPO_ROOT/local/reports/native-postgresql-special-token-count-migration/special_token_count_migration_20261019T231003Z_9C2eSx.txt"
readonly ACCEPTED_EMBEDDING_REPORT="$REPO_ROOT/local/reports/ishikawa-embedding-qualification/chunk_embedding_qualification_20261019T224719Z_X9fCPX.txt"
readonly NORMALIZED_SHA256='736d619ac5a7e10f768bdb8b8f3f117cb52231f8dc2f4d186d52d96c8bd41e28'
readonly CHUNK_SHA256='0b351ef579ff134a5fb1fb5f37843d5461a100f1fc2d803e278a9b20d3126548'
readonly EMBEDDING_SHA256='5876c94380421741227f1bcaa494490158c1c83aeb5f54b39e894e9356b0f14d'
readonly MIGRATION_0003_SHA256='5e833d8ff556c0e6158daf0419b1013235a11e1a94f1f560206ba813e1fc3761'
readonly ACCEPTED_DATABASE_REPORT_SHA256='6455c98f2f7e9eac28c3406e85332b24faac00e2790a2c5aa31abdfcb4dff5d4'
readonly ACCEPTED_EMBEDDING_REPORT_SHA256='f29b7d727d8955a482ce3b3c4ae8a0c2e939cfc7c5c941e4c89db48ecc8c05ca'
readonly DEFAULT_REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-four-bucket-pipeline-writer-integration"

python_sources=(
  "$PYTHON_ROOT/__init__.py" "$PYTHON_ROOT/artifact_adapter.py" "$PYTHON_ROOT/canonical.py"
  "$PYTHON_ROOT/errors.py" "$PYTHON_ROOT/models.py" "$PYTHON_ROOT/persistence.py"
  "$PYTHON_ROOT/persistence_models.py" "$PYTHON_ROOT/planner.py" "$PYTHON_ROOT/reasons.py"
  "$PYTHON_ROOT/reporting.py" "$PYTHON_ROOT/validators.py" "$PYTHON_ROOT/yaml_loader.py"
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
report_root="$DEFAULT_REPORT_ROOT"
run_authorized=false
validate_only=false

while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --target) target="${2:-}"; shift 2 ;;
    --expected-hostname) expected_hostname="${2:-}"; shift 2 ;;
    --expected-os-version) expected_os_version="${2:-}"; shift 2 ;;
    --identity-file) identity_file="${2:-}"; shift 2 ;;
    --report-root) report_root="${2:-}"; shift 2 ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'ERROR: unsupported argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$run_authorized" != "$validate_only" ]] || { printf 'BLOCKED: choose exactly one of --run or --validate-only.\n' >&2; exit 2; }
[[ "$target" =~ ^[A-Za-z0-9_@.:-]+$ ]] || { printf 'BLOCKED: invalid SSH target or alias.\n' >&2; exit 2; }
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || { printf 'BLOCKED: invalid expected hostname.\n' >&2; exit 2; }
[[ "$expected_os_version" =~ ^[0-9]{2}\.[0-9]{2}$ ]] || { printf 'BLOCKED: invalid expected Ubuntu version.\n' >&2; exit 2; }
[[ "$report_root" == /* && ! -L "$report_root" ]] || { printf 'BLOCKED: report root must be absolute and not a symlink.\n' >&2; exit 2; }
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] || { printf 'BLOCKED: identity file is unsafe.\n' >&2; exit 2; }
fi
for required in awk bash basename cat chmod date env grep install mkdir mktemp python3 rm scp sha256sum ssh tee timeout tr wc; do
  command -v "$required" >/dev/null 2>&1 || { printf 'BLOCKED: missing local command: %s\n' "$required" >&2; exit 2; }
done
for source in "$TARGET_HELPER" "$TEST_RUNNER" "$ADAPTER_TESTS" "$BASE_TEST_RUNNER" "$MIGRATION_0001" "$MIGRATION_0002" "$MIGRATION_0003" "$NORMALIZED" "$CHUNKS" "$EMBEDDINGS" "$ACCEPTED_DATABASE_REPORT" "$ACCEPTED_EMBEDDING_REPORT" "${python_sources[@]}" "${config_sources[@]}" "${pdf_sources[@]}"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || { printf 'BLOCKED: a required Script 31 input is missing or unsafe.\n' >&2; exit 2; }
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || { printf 'BLOCKED: %s checksum mismatch.\n' "$3" >&2; exit 2; }
}
check_sha256 "$NORMALIZED" "$NORMALIZED_SHA256" 'accepted normalization artifact'
check_sha256 "$CHUNKS" "$CHUNK_SHA256" 'accepted chunk artifact'
check_sha256 "$EMBEDDINGS" "$EMBEDDING_SHA256" 'accepted embedding artifact'
check_sha256 "$MIGRATION_0003" "$MIGRATION_0003_SHA256" 'accepted schema-v3 migration'
check_sha256 "$ACCEPTED_DATABASE_REPORT" "$ACCEPTED_DATABASE_REPORT_SHA256" 'accepted database report'
check_sha256 "$ACCEPTED_EMBEDDING_REPORT" "$ACCEPTED_EMBEDDING_REPORT_SHA256" 'accepted embedding report'
grep -Fxq 'publication_eligible=false;publication_blocker=pipeline_writer_integration_pending' "$ACCEPTED_EMBEDDING_REPORT" || { printf 'BLOCKED: expected embedding integration gate is absent.\n' >&2; exit 2; }
grep -Fq 'script_28_embedding=pass;' "$ACCEPTED_EMBEDDING_REPORT" || { printf 'BLOCKED: accepted embedding pass marker is absent.\n' >&2; exit 2; }
grep -Fxq 'migration_metadata_row_count=3;corpus_content_row_count=0' "$ACCEPTED_DATABASE_REPORT" || { printf 'BLOCKED: accepted empty database fact is absent.\n' >&2; exit 2; }
grep -Fxq 'token_buckets=content_context_prefix_special;exact_total_constraint=pass' "$ACCEPTED_DATABASE_REPORT" || { printf 'BLOCKED: accepted four-bucket database contract is absent.\n' >&2; exit 2; }
grep -Fq 'script_30_special_token_migration=pass;' "$ACCEPTED_DATABASE_REPORT" || { printf 'BLOCKED: accepted schema-v3 migration pass marker is absent.\n' >&2; exit 2; }

bash -n "$TARGET_HELPER" "$BASE_TEST_RUNNER"
python3 -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' "$TEST_RUNNER" "$ADAPTER_TESTS" "${python_sources[@]}"
for neutral_source in "$TARGET_HELPER" "$TEST_RUNNER"; do
  if grep -Eiq 'phase[-_ ]?[0-9]+|(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)|Danko|org[_ -]?lab|Agent|repository' "$neutral_source"; then
    printf 'BLOCKED: development or environment jargon found in a neutral target source.\n' >&2
    exit 2
  fi
done

work_root="$(mktemp -d /tmp/ishikawa-script-31.XXXXXX)"
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
  else emit 'cleanup_remote_temporary_files=not_required'; fi
  if [[ "$master_started" == true ]]; then
    timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1 || close_code=$?
    emit "cleanup_ssh_master_exit_code=$close_code"
    (( close_code == 0 )) || status=1
  fi
  if [[ "$work_root" == /tmp/ishikawa-script-31.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

base_result="$work_root/base-tests.txt"
bash "$BASE_TEST_RUNNER" >"$base_result" 2>&1 || { cat "$base_result" >&2; printf 'script_31_four_bucket_pipeline_writer=blocked;reason=base_regression\n' >&2; exit 1; }
grep -Fq 'Ran 64 tests' "$base_result" || { printf 'script_31_four_bucket_pipeline_writer=blocked;reason=base_test_count_mismatch\n' >&2; exit 1; }
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$base_result" || { printf 'script_31_four_bucket_pipeline_writer=blocked;reason=base_pass_marker_absent\n' >&2; exit 1; }
adapter_result="$work_root/adapter-tests.txt"
env PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$ISHIKAWA_ROOT/application/python" python3 "$ADAPTER_TESTS" -v >"$adapter_result" 2>&1 || { cat "$adapter_result" >&2; printf 'script_31_four_bucket_pipeline_writer=blocked;reason=adapter_regression\n' >&2; exit 1; }
grep -Fq 'Ran 8 tests' "$adapter_result" || { printf 'script_31_four_bucket_pipeline_writer=blocked;reason=adapter_test_count_mismatch\n' >&2; exit 1; }
grep -Fxq 'OK' "$adapter_result" || { printf 'script_31_four_bucket_pipeline_writer=blocked;reason=adapter_pass_marker_absent\n' >&2; exit 1; }

for source in "${python_sources[@]}"; do install -m 0600 "$source" "$stage_root/payload/ishikawa/$(basename "$source")"; done
for source in "${config_sources[@]}"; do install -m 0600 "$source" "$stage_root/payload/config/$(basename "$source")"; done
for source in "${pdf_sources[@]}"; do install -m 0600 "$source" "$stage_root/payload/source/$(basename "$source")"; done
install -m 0600 "$TARGET_HELPER" "$stage_root/test-four-bucket-pipeline-writer-integration"
install -m 0600 "$TEST_RUNNER" "$stage_root/test-four-bucket-pipeline-writer-integration.py"
install -m 0600 "$MIGRATION_0001" "$stage_root/0001_initial_rag_catalog.sql"
install -m 0600 "$MIGRATION_0002" "$stage_root/0002_align_ingestion_ownership.sql"
install -m 0600 "$MIGRATION_0003" "$stage_root/0003_separate_special_token_count.sql"
install -m 0600 "$NORMALIZED" "$stage_root/normalized.json"
install -m 0600 "$CHUNKS" "$stage_root/chunks.json"
install -m 0600 "$EMBEDDINGS" "$stage_root/embeddings.json"
printf '%s  %s\n' "$NORMALIZED_SHA256" normalized.json "$CHUNK_SHA256" chunks.json "$EMBEDDING_SHA256" embeddings.json >"$stage_root/artifact-identities.sha256"
chmod 0600 "$stage_root/artifact-identities.sha256"

payload_manifest="$stage_root/payload.sha256"
: >"$payload_manifest"
for source in "$stage_root"/payload/ishikawa/*.py; do printf '%s  payload/ishikawa/%s\n' "$(sha256sum "$source" | awk '{print $1}')" "$(basename "$source")" >>"$payload_manifest"; done
for source in "$stage_root"/payload/config/*.yaml; do printf '%s  payload/config/%s\n' "$(sha256sum "$source" | awk '{print $1}')" "$(basename "$source")" >>"$payload_manifest"; done
for source in "$stage_root"/payload/source/*.pdf; do printf '%s  payload/source/%s\n' "$(sha256sum "$source" | awk '{print $1}')" "$(basename "$source")" >>"$payload_manifest"; done
for name in normalized.json chunks.json embeddings.json artifact-identities.sha256 0001_initial_rag_catalog.sql 0002_align_ingestion_ownership.sql 0003_separate_special_token_count.sql test-four-bucket-pipeline-writer-integration.py; do printf '%s  %s\n' "$(sha256sum "$stage_root/$name" | awk '{print $1}')" "$name" >>"$payload_manifest"; done
manifest_sha256="$(sha256sum "$payload_manifest" | awk '{print $1}')"
helper_sha256="$(sha256sum "$TARGET_HELPER" | awk '{print $1}')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_four_bucket_pipeline_writer_integration_source' \
    'target_contact=false;postgresql_connection=false;corpus_mutation=false' \
    "script_sha256=$script_sha256;helper_sha256=$helper_sha256" \
    "payload_manifest_sha256=$manifest_sha256;payload_file_count=$(wc -l <"$payload_manifest" | tr -d ' ')" \
    'base_tests=64;adapter_tests=8;failures=0;errors=0' \
    "normalization_sha256=$NORMALIZED_SHA256;chunk_sha256=$CHUNK_SHA256;embedding_sha256=$EMBEDDING_SHA256" \
    "migration_0003_sha256=$MIGRATION_0003_SHA256;accepted_schema_version=3" \
    'script_31_four_bucket_pipeline_writer_source=pass'
  exit 0
fi

mkdir -p -- "$report_root"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_root/four_bucket_pipeline_writer_integration_${timestamp}_XXXXXX.txt")"
remote_root="/tmp/four-bucket-pipeline-writer-integration-$timestamp-$$"
emit 'purpose=run_four_bucket_pipeline_writer_target_integration'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;helper_sha256=$helper_sha256;payload_manifest_sha256=$manifest_sha256"
emit "normalization_sha256=$NORMALIZED_SHA256;chunk_sha256=$CHUNK_SHA256;embedding_sha256=$EMBEDDING_SHA256"
emit "migration_0003_sha256=$MIGRATION_0003_SHA256;accepted_database_report_sha256=$ACCEPTED_DATABASE_REPORT_SHA256"
emit 'authorized_actions=stage_verified_synthetic_artifacts_start_postgresql_create_disposable_database_apply_accepted_schema_write_and_query_synthetic_artifacts_drop_disposable_database_verify_accepted_database_stop_postgresql_remove_temporary_files'
emit 'non_actions=no_package_change_no_accepted_database_mutation_no_organizational_document_read_no_model_call_no_secret_processing_no_service_enablement'
emit "selected_target=$target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version"
emit 'operator_expectation=ssh_key_passphrase_up_to_once;target_sudo_password_may_be_prompted;no_application_secret_prompt'

control_path="$work_root/ssh-control"
ssh_args=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto -o "ControlPath=$control_path" -o ControlPersist=1800)
if [[ -n "$identity_file" ]]; then ssh_args+=(-i "$identity_file" -o IdentitiesOnly=yes); fi
emit 'milestone=authentication;state=waiting_for_operator_if_prompted'
timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$target" >"$work_root/master.stdout" 2>"$work_root/master.stderr" || { emit 'four_bucket_pipeline_writer_target_integration_wrapper=blocked;reason=ssh_master_start_failed'; exit 1; }
master_started=true
emit 'milestone=authentication;state=pass'
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root' && mkdir -m 0700 -- '$remote_root/payload' '$remote_root/payload/ishikawa' '$remote_root/payload/config' '$remote_root/payload/source'" >"$work_root/create.stdout" 2>"$work_root/create.stderr" || { emit 'four_bucket_pipeline_writer_target_integration_wrapper=blocked;reason=remote_temporary_directory_not_created'; exit 1; }
remote_created=true
timeout --foreground 180 scp "${ssh_args[@]}" "$stage_root"/test-four-bucket-pipeline-writer-integration "$stage_root"/test-four-bucket-pipeline-writer-integration.py "$stage_root"/0001_initial_rag_catalog.sql "$stage_root"/0002_align_ingestion_ownership.sql "$stage_root"/0003_separate_special_token_count.sql "$stage_root"/normalized.json "$stage_root"/chunks.json "$stage_root"/embeddings.json "$stage_root"/artifact-identities.sha256 "$stage_root"/payload.sha256 "$target:$remote_root/" >"$work_root/scp-root.stdout" 2>"$work_root/scp-root.stderr" || { emit 'four_bucket_pipeline_writer_target_integration_wrapper=blocked;reason=root_payload_copy_failed'; exit 1; }
timeout --foreground 180 scp "${ssh_args[@]}" "$stage_root"/payload/ishikawa/*.py "$target:$remote_root/payload/ishikawa/" >"$work_root/scp-python.stdout" 2>"$work_root/scp-python.stderr" || { emit 'four_bucket_pipeline_writer_target_integration_wrapper=blocked;reason=python_payload_copy_failed'; exit 1; }
timeout --foreground 120 scp "${ssh_args[@]}" "$stage_root"/payload/config/*.yaml "$target:$remote_root/payload/config/" >"$work_root/scp-config.stdout" 2>"$work_root/scp-config.stderr" || { emit 'four_bucket_pipeline_writer_target_integration_wrapper=blocked;reason=config_payload_copy_failed'; exit 1; }
timeout --foreground 180 scp "${ssh_args[@]}" "$stage_root"/payload/source/*.pdf "$target:$remote_root/payload/source/" >"$work_root/scp-source.stdout" 2>"$work_root/scp-source.stderr" || { emit 'four_bucket_pipeline_writer_target_integration_wrapper=blocked;reason=source_payload_copy_failed'; exit 1; }
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "cd '$remote_root' && printf '%s  %s\n%s  %s\n' '$helper_sha256' test-four-bucket-pipeline-writer-integration '$manifest_sha256' payload.sha256 | sha256sum --check --strict -" >"$work_root/hash.stdout" 2>"$work_root/hash.stderr" || { emit 'four_bucket_pipeline_writer_target_integration_wrapper=blocked;reason=target_outer_payload_hash_mismatch'; exit 1; }
emit 'milestone=target_payload_verification;state=pass'

emit 'milestone=pipeline_writer_integration;state=waiting_for_operator_sudo_if_prompted'
set +e
timeout --foreground 1200 ssh -tt "${ssh_args[@]}" -o BatchMode=yes "$target" "cd '$remote_root' && sudo -p '[sudo] password for disposable four-bucket writer integration: ' bash ./test-four-bucket-pipeline-writer-integration '$expected_hostname' '$expected_os_version' rag_catalog rag_owner rag_ingest rag_retrieval '$remote_root' '$manifest_sha256' > four-bucket-pipeline-writer-integration.txt" < /dev/tty
remote_code=$?
set -e
emit "remote_execution_exit_code=$remote_code;raw_stderr_retained=false"
fetched_result="$work_root/four-bucket-pipeline-writer-integration.txt"
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/four-bucket-pipeline-writer-integration.txt" "$fetched_result" >"$work_root/fetch.stdout" 2>"$work_root/fetch.stderr" || { emit 'four_bucket_pipeline_writer_target_integration_wrapper=blocked;reason=result_fetch_failed'; exit 1; }

output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then output_contract=blocked; continue; fi
  emit "$line"
done <"$fetched_result"
emit "remote_output_contract=$output_contract"

required_fact_contract=pass
for fact in \
  'purpose=test_four_bucket_pipeline_artifacts_with_disposable_native_postgresql' \
  "host=$expected_hostname;os_version=$expected_os_version;architecture=amd64" \
  'postgresql_version=16.15;vector_default_version=0.8.7' \
  'temporary_database_created=true;accepted_schema_version=3' \
  'synthetic_documents=6;organizational_documents=0' \
  'prepared_structural_units=230;prepared_chunks=125;prepared_embeddings=125' \
  'token_buckets=content_context_prefix_special;token_count_min=10;token_count_max=57' \
  'special_token_count=2;special_token_rows=125;exact_total_contract=pass' \
  'embedding_space_id=fd970d304662357a07f7712639bdc0c70cc7e72b22f04c126acce57a6f9143a3;embedding_dimension=768' \
  'writer_action=add_6;reuse_verification=skipped_6' \
  'active_projection=documents_6_chunks_125_citations_125_embeddings_125' \
  'retrieval_role_active_view_read=pass;retrieval_role_base_table_read=denied' \
  'four_bucket_pipeline_writer_postgresql_integration=pass' \
  'temporary_database_dropped=true;accepted_database_unchanged=true' \
  'cluster_status=down;postgresql_port_5432=free;postgresql_service_active=inactive;postgresql_service_enabled=disabled' \
  'four_bucket_pipeline_writer_target_integration=pass'; do
  [[ "$(grep -Fxc "$fact" "$fetched_result" || true)" == 1 ]] || required_fact_contract=blocked
done
[[ "$(grep -Ec '^python_version=3\.12\.[0-9]+;psycopg_version=3\.1\.17$' "$fetched_result" || true)" == 1 ]] || required_fact_contract=blocked
pass_markers="$(grep -Fxc 'four_bucket_pipeline_writer_target_integration=pass' "$fetched_result" || true)"
blocked_markers="$(grep -Ec '^four_bucket_pipeline_writer_target_integration=blocked;' "$fetched_result" || true)"
emit "required_fact_contract=$required_fact_contract;pass_markers=$pass_markers;blocked_markers=$blocked_markers"
if (( remote_code == 0 )) && [[ "$output_contract" == pass && "$required_fact_contract" == pass && "$pass_markers" == 1 && "$blocked_markers" == 0 ]]; then
  emit 'milestone=pipeline_writer_integration;state=pass'
  emit "script_31_four_bucket_pipeline_writer=pass;local_report=$report_path;next_gate=freeze_pipeline_writer_contract"
  exit 0
fi
emit 'milestone=pipeline_writer_integration;state=blocked'
emit "script_31_four_bucket_pipeline_writer=blocked;local_report=$report_path;next_gate=inspect_result_before_any_retry"
exit 1
