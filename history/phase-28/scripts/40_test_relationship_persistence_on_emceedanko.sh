#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Prove relationship persistence, audit fields, and one-hop traversal against
#   accepted synthetic data in a disposable application-host database.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/40_test_relationship_persistence_on_emceedanko.sh --run

usage() {
  sed -n '3,9p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run                      Explicitly authorize the disposable proof.' \
    '  --target VALUE             SSH destination or configured SSH alias.' \
    '  --expected-hostname NAME   Exact target short hostname.' \
    '  --expected-os-version VER  Exact expected Ubuntu major.minor version.' \
    '  --identity-file PATH       Optional explicit SSH private key.' \
    '  --report-root PATH         Absolute local content-free report directory.' \
    '  --validate-only            Validate sources without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$ISHIKAWA_ROOT/application/python/ishikawa"
readonly TARGET_HELPER="$SCRIPT_DIR/test-relationship-persistence-integration"
readonly TEST_RUNNER="$SCRIPT_DIR/test-relationship-persistence-integration.py"
readonly BASE_TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly FIXTURE_ROOT="$ISHIKAWA_ROOT/tests/fixtures/pipeline_writer"
readonly SOURCE_ROOT="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/anderson-upload"
readonly NORMALIZED="$REPO_ROOT/local/artifacts/ishikawa/normalization/normalized_structural_units_20261019T214207Z.json"
readonly CHUNKS="$REPO_ROOT/local/artifacts/ishikawa/retrieval-gap-method-profile/structural_chunk_candidates_20261020T002645Z.json"
readonly EMBEDDINGS="$REPO_ROOT/local/artifacts/ishikawa/retrieval-gap-method-profile/measured_nomic_chunk_embeddings_20261020T002645Z.json"
readonly RELATIONSHIP_REGISTRY="$ISHIKAWA_ROOT/config/templates/relationship_types.yaml"
readonly TRUTH="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/evaluation/ground_truth.json"
readonly MIGRATION_0001="$PHASE_ROOT/migrations/0001_initial_rag_catalog.sql"
readonly MIGRATION_0002="$PHASE_ROOT/migrations/0002_align_ingestion_ownership.sql"
readonly MIGRATION_0003="$PHASE_ROOT/migrations/0003_separate_special_token_count.sql"
readonly MIGRATION_0004="$PHASE_ROOT/migrations/0004_preserve_relationship_override_audit.sql"
readonly ACCEPTED_RELATIONSHIP_REPORT="$REPO_ROOT/local/reports/ishikawa-relationship-contract/relationship_contract_20261020T005950Z_YhSbWr.txt"
readonly NORMALIZED_SHA256='736d619ac5a7e10f768bdb8b8f3f117cb52231f8dc2f4d186d52d96c8bd41e28'
readonly CHUNK_SHA256='bc993ca0a417353f0d2313bcb2d1c94a1d526a513253139be71117bf88626bf3'
readonly EMBEDDING_SHA256='5bd79048bb59d53b6f6903eec9f4797955763a5fc12c064b17d19db89ba9d641'
readonly RELATIONSHIP_REGISTRY_SHA256='9518c6b46837edf8f1448742155c9d7a39d062178e8e9e86d234ebd9e21d3a59'
readonly TRUTH_SHA256='85e4bcf8e4d07bd786c8d2566957a4e75555084e5f3b11e58dd96af9af7c2ec8'
readonly MIGRATION_0004_SHA256='5764f6e12a74b18747163c61ef3f314e8dff140a3586b298c62be616a1dc185f'
readonly ACCEPTED_RELATIONSHIP_REPORT_SHA256='83e03094d4c7810dba9b840da3a4596d71eade9362639d57e3c145a5f29e2939'
readonly DEFAULT_REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-relationship-persistence-integration"

python_sources=(
  "$PYTHON_ROOT/__init__.py" "$PYTHON_ROOT/artifact_adapter.py" "$PYTHON_ROOT/canonical.py"
  "$PYTHON_ROOT/errors.py" "$PYTHON_ROOT/models.py" "$PYTHON_ROOT/persistence.py"
  "$PYTHON_ROOT/persistence_models.py" "$PYTHON_ROOT/planner.py" "$PYTHON_ROOT/reasons.py"
  "$PYTHON_ROOT/reporting.py" "$PYTHON_ROOT/retrieval.py" "$PYTHON_ROOT/relationships.py"
  "$PYTHON_ROOT/validators.py" "$PYTHON_ROOT/yaml_loader.py"
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
for source in "$TARGET_HELPER" "$TEST_RUNNER" "$BASE_TEST_RUNNER" "$MIGRATION_0001" "$MIGRATION_0002" "$MIGRATION_0003" "$MIGRATION_0004" "$NORMALIZED" "$CHUNKS" "$EMBEDDINGS" "$RELATIONSHIP_REGISTRY" "$TRUTH" "$ACCEPTED_RELATIONSHIP_REPORT" "${python_sources[@]}" "${config_sources[@]}" "${pdf_sources[@]}"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || { printf 'BLOCKED: a required Script 40 input is missing or unsafe.\n' >&2; exit 2; }
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || { printf 'BLOCKED: %s checksum mismatch.\n' "$3" >&2; exit 2; }
}
check_sha256 "$NORMALIZED" "$NORMALIZED_SHA256" 'accepted normalization artifact'
check_sha256 "$CHUNKS" "$CHUNK_SHA256" 'accepted chunk artifact'
check_sha256 "$EMBEDDINGS" "$EMBEDDING_SHA256" 'accepted embedding artifact'
check_sha256 "$RELATIONSHIP_REGISTRY" "$RELATIONSHIP_REGISTRY_SHA256" 'relationship registry'
check_sha256 "$TRUTH" "$TRUTH_SHA256" 'held-out relationship truth'
check_sha256 "$MIGRATION_0004" "$MIGRATION_0004_SHA256" 'schema-v4 migration'
check_sha256 "$ACCEPTED_RELATIONSHIP_REPORT" "$ACCEPTED_RELATIONSHIP_REPORT_SHA256" 'accepted relationship report'
grep -Fxq 'relationship_contract_qualification=pass' "$ACCEPTED_RELATIONSHIP_REPORT" || { printf 'BLOCKED: accepted relationship qualification marker is absent.\n' >&2; exit 2; }
grep -Fxq 'unresolved_references=0' "$ACCEPTED_RELATIONSHIP_REPORT" || { printf 'BLOCKED: accepted unresolved-reference fact is absent.\n' >&2; exit 2; }
grep -Fq 'script_39_relationship_contract=pass;' "$ACCEPTED_RELATIONSHIP_REPORT" || { printf 'BLOCKED: accepted Script 39 pass marker is absent.\n' >&2; exit 2; }

bash -n "$TARGET_HELPER" "$BASE_TEST_RUNNER"
python3 -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' "$TEST_RUNNER" "${python_sources[@]}"
for neutral_source in "$TARGET_HELPER" "$TEST_RUNNER"; do
  if grep -Eq '(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)' "$neutral_source" \
    || grep -Eiq 'phase[-_ ]?[0-9]+|Danko|org[_ -]?lab|Agent|repository' "$neutral_source"; then
    printf 'BLOCKED: development or environment jargon found in a neutral target source.\n' >&2
    exit 2
  fi
done

work_root="$(mktemp -d /tmp/ishikawa-script-40.XXXXXX)"
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
  if [[ "$work_root" == /tmp/ishikawa-script-40.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

base_result="$work_root/base-tests.txt"
bash "$BASE_TEST_RUNNER" >"$base_result" 2>&1 || { cat "$base_result" >&2; printf 'script_40_relationship_persistence=blocked;reason=base_regression\n' >&2; exit 1; }
grep -Fq 'Ran 106 tests' "$base_result" || { printf 'script_40_relationship_persistence=blocked;reason=base_test_count_mismatch\n' >&2; exit 1; }
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$base_result" || { printf 'script_40_relationship_persistence=blocked;reason=base_pass_marker_absent\n' >&2; exit 1; }

for source in "${python_sources[@]}"; do install -m 0600 "$source" "$stage_root/payload/ishikawa/$(basename "$source")"; done
for source in "${config_sources[@]}"; do install -m 0600 "$source" "$stage_root/payload/config/$(basename "$source")"; done
for source in "${pdf_sources[@]}"; do install -m 0600 "$source" "$stage_root/payload/source/$(basename "$source")"; done
install -m 0600 "$TARGET_HELPER" "$stage_root/test-relationship-persistence-integration"
install -m 0600 "$TEST_RUNNER" "$stage_root/test-relationship-persistence-integration.py"
install -m 0600 "$MIGRATION_0001" "$stage_root/0001_initial_rag_catalog.sql"
install -m 0600 "$MIGRATION_0002" "$stage_root/0002_align_ingestion_ownership.sql"
install -m 0600 "$MIGRATION_0003" "$stage_root/0003_separate_special_token_count.sql"
install -m 0600 "$MIGRATION_0004" "$stage_root/0004_preserve_relationship_override_audit.sql"
install -m 0600 "$NORMALIZED" "$stage_root/normalized.json"
install -m 0600 "$CHUNKS" "$stage_root/chunks.json"
install -m 0600 "$EMBEDDINGS" "$stage_root/embeddings.json"
install -m 0600 "$RELATIONSHIP_REGISTRY" "$stage_root/relationship-types.yaml"
install -m 0600 "$TRUTH" "$stage_root/truth.json"
printf '%s  %s\n' \
  "$NORMALIZED_SHA256" normalized.json \
  "$CHUNK_SHA256" chunks.json \
  "$EMBEDDING_SHA256" embeddings.json \
  "$RELATIONSHIP_REGISTRY_SHA256" relationship-types.yaml \
  "$TRUTH_SHA256" truth.json >"$stage_root/artifact-identities.sha256"
chmod 0600 "$stage_root/artifact-identities.sha256"

payload_manifest="$stage_root/payload.sha256"
: >"$payload_manifest"
for source in "$stage_root"/payload/ishikawa/*.py; do printf '%s  payload/ishikawa/%s\n' "$(sha256sum "$source" | awk '{print $1}')" "$(basename "$source")" >>"$payload_manifest"; done
for source in "$stage_root"/payload/config/*.yaml; do printf '%s  payload/config/%s\n' "$(sha256sum "$source" | awk '{print $1}')" "$(basename "$source")" >>"$payload_manifest"; done
for source in "$stage_root"/payload/source/*.pdf; do printf '%s  payload/source/%s\n' "$(sha256sum "$source" | awk '{print $1}')" "$(basename "$source")" >>"$payload_manifest"; done
for name in normalized.json chunks.json embeddings.json artifact-identities.sha256 relationship-types.yaml truth.json 0001_initial_rag_catalog.sql 0002_align_ingestion_ownership.sql 0003_separate_special_token_count.sql 0004_preserve_relationship_override_audit.sql test-relationship-persistence-integration.py; do printf '%s  %s\n' "$(sha256sum "$stage_root/$name" | awk '{print $1}')" "$name" >>"$payload_manifest"; done
manifest_sha256="$(sha256sum "$payload_manifest" | awk '{print $1}')"
helper_sha256="$(sha256sum "$TARGET_HELPER" | awk '{print $1}')"
runner_sha256="$(sha256sum "$TEST_RUNNER" | awk '{print $1}')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_relationship_persistence_integration_source' \
    'target_contact=false;postgresql_connection=false;corpus_mutation=false' \
    "script_sha256=$script_sha256;helper_sha256=$helper_sha256;runner_sha256=$runner_sha256" \
    "payload_manifest_sha256=$manifest_sha256;payload_file_count=$(wc -l <"$payload_manifest" | tr -d ' ')" \
    'base_tests=106;failures=0;errors=0' \
    "relationship_registry_sha256=$RELATIONSHIP_REGISTRY_SHA256;migration_0004_sha256=$MIGRATION_0004_SHA256" \
    'script_40_relationship_persistence_source=pass'
  exit 0
fi

mkdir -p -- "$report_root"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_root/relationship_persistence_integration_${timestamp}_XXXXXX.txt")"
remote_root="/tmp/relationship-persistence-integration-$timestamp-$$"
emit 'purpose=run_relationship_persistence_target_integration'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;helper_sha256=$helper_sha256;runner_sha256=$runner_sha256"
emit "payload_manifest_sha256=$manifest_sha256;relationship_registry_sha256=$RELATIONSHIP_REGISTRY_SHA256"
emit "migration_0004_sha256=$MIGRATION_0004_SHA256;accepted_relationship_report_sha256=$ACCEPTED_RELATIONSHIP_REPORT_SHA256"
emit 'authorized_actions=stage_verified_synthetic_artifacts_start_postgresql_verify_accepted_database_create_disposable_database_apply_reviewed_schema_write_and_query_synthetic_relationships_drop_disposable_database_verify_accepted_database_stop_postgresql_remove_temporary_files'
emit 'non_actions=no_package_change_no_accepted_database_mutation_no_organizational_document_read_no_model_call_no_secret_processing_no_service_enablement'
emit "selected_target=$target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version"
emit 'operator_expectation=ssh_key_passphrase_up_to_once;target_sudo_password_may_be_prompted;no_application_secret_prompt'

control_path="$work_root/ssh-control"
ssh_args=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto -o "ControlPath=$control_path" -o ControlPersist=1800)
if [[ -n "$identity_file" ]]; then ssh_args+=(-i "$identity_file" -o IdentitiesOnly=yes); fi
emit 'milestone=authentication;state=waiting_for_operator_if_prompted'
timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$target" >"$work_root/master.stdout" 2>"$work_root/master.stderr" || { emit 'relationship_persistence_target_integration_wrapper=blocked;reason=ssh_master_start_failed'; exit 1; }
master_started=true
emit 'milestone=authentication;state=pass'
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root' && mkdir -m 0700 -- '$remote_root/payload' '$remote_root/payload/ishikawa' '$remote_root/payload/config' '$remote_root/payload/source'" >"$work_root/create.stdout" 2>"$work_root/create.stderr" || { emit 'relationship_persistence_target_integration_wrapper=blocked;reason=remote_temporary_directory_not_created'; exit 1; }
remote_created=true
timeout --foreground 180 scp "${ssh_args[@]}" "$stage_root"/test-relationship-persistence-integration "$stage_root"/test-relationship-persistence-integration.py "$stage_root"/0001_initial_rag_catalog.sql "$stage_root"/0002_align_ingestion_ownership.sql "$stage_root"/0003_separate_special_token_count.sql "$stage_root"/0004_preserve_relationship_override_audit.sql "$stage_root"/normalized.json "$stage_root"/chunks.json "$stage_root"/embeddings.json "$stage_root"/artifact-identities.sha256 "$stage_root"/relationship-types.yaml "$stage_root"/truth.json "$stage_root"/payload.sha256 "$target:$remote_root/" >"$work_root/scp-root.stdout" 2>"$work_root/scp-root.stderr" || { emit 'relationship_persistence_target_integration_wrapper=blocked;reason=root_payload_copy_failed'; exit 1; }
timeout --foreground 180 scp "${ssh_args[@]}" "$stage_root"/payload/ishikawa/*.py "$target:$remote_root/payload/ishikawa/" >"$work_root/scp-python.stdout" 2>"$work_root/scp-python.stderr" || { emit 'relationship_persistence_target_integration_wrapper=blocked;reason=python_payload_copy_failed'; exit 1; }
timeout --foreground 120 scp "${ssh_args[@]}" "$stage_root"/payload/config/*.yaml "$target:$remote_root/payload/config/" >"$work_root/scp-config.stdout" 2>"$work_root/scp-config.stderr" || { emit 'relationship_persistence_target_integration_wrapper=blocked;reason=config_payload_copy_failed'; exit 1; }
timeout --foreground 180 scp "${ssh_args[@]}" "$stage_root"/payload/source/*.pdf "$target:$remote_root/payload/source/" >"$work_root/scp-source.stdout" 2>"$work_root/scp-source.stderr" || { emit 'relationship_persistence_target_integration_wrapper=blocked;reason=source_payload_copy_failed'; exit 1; }
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "cd '$remote_root' && printf '%s  %s\n%s  %s\n' '$helper_sha256' test-relationship-persistence-integration '$manifest_sha256' payload.sha256 | sha256sum --check --strict -" >"$work_root/hash.stdout" 2>"$work_root/hash.stderr" || { emit 'relationship_persistence_target_integration_wrapper=blocked;reason=target_outer_payload_hash_mismatch'; exit 1; }
emit 'milestone=target_payload_verification;state=pass'

emit 'milestone=relationship_persistence;state=waiting_for_operator_sudo_if_prompted'
set +e
timeout --foreground 1200 ssh -tt "${ssh_args[@]}" -o BatchMode=yes "$target" "cd '$remote_root' && sudo -p '[sudo] password for disposable relationship integration: ' bash ./test-relationship-persistence-integration '$expected_hostname' '$expected_os_version' rag_catalog rag_owner rag_ingest rag_retrieval '$remote_root' '$manifest_sha256' > relationship-persistence-integration.txt" < /dev/tty
remote_code=$?
set -e
emit "remote_execution_exit_code=$remote_code;raw_stderr_retained=false"
fetched_result="$work_root/relationship-persistence-integration.txt"
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/relationship-persistence-integration.txt" "$fetched_result" >"$work_root/fetch.stdout" 2>"$work_root/fetch.stderr" || { emit 'relationship_persistence_target_integration_wrapper=blocked;reason=result_fetch_failed'; exit 1; }

output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then output_contract=blocked; continue; fi
  emit "$line"
done <"$fetched_result"
emit "remote_output_contract=$output_contract"

required_fact_contract=pass
for fact in \
  'purpose=test_relationship_persistence_with_disposable_native_postgresql' \
  "host=$expected_hostname;os_version=$expected_os_version;architecture=amd64" \
  'postgresql_version=16.15;vector_default_version=0.8.7' \
  'temporary_database_created=true;accepted_schema_version=4' \
  'synthetic_documents=6;organizational_documents=0' \
  'prepared_chunks=126;relationship_observations=44' \
  'accepted_internal_edges=27;ignored_self_references=17;unresolved_references=0' \
  'relationship_types=3;persisted_relationships=27;active_relationships=27' \
  'relationship_registry_id=0211fc5adc842faba0f18ffe4ca92c1cda9f53a9447efcb2ccabab4ccd4b2e77' \
  'relationship_method_profile_id=d16d72726a5548af1b1abd3d2ca7a35da5a6b805d8d26c3369a2c35c78a8f76d' \
  'override_audit_columns=present;deterministic_rows_with_override_data=0' \
  'held_out_relationships=5;held_out_relationships_covered=5' \
  'maximum_hops=1;held_out_traversals_covered=5' \
  'retrieval_role_active_view_read=pass;retrieval_role_base_table_read=denied' \
  'relationship_persistence_foundation=pass' \
  'temporary_database_dropped=true;accepted_database_unchanged=true' \
  'cluster_status=down;postgresql_port_5432=free;postgresql_service_active=inactive;postgresql_service_enabled=disabled' \
  'relationship_persistence_target_integration=pass'; do
  [[ "$(grep -Fxc "$fact" "$fetched_result" || true)" == 1 ]] || required_fact_contract=blocked
done
[[ "$(grep -Ec '^python_version=3\.12\.[0-9]+;psycopg_version=3\.1\.17$' "$fetched_result" || true)" == 1 ]] || required_fact_contract=blocked
pass_markers="$(grep -Fxc 'relationship_persistence_target_integration=pass' "$fetched_result" || true)"
blocked_markers="$(grep -Ec '^relationship_persistence_target_integration=blocked;' "$fetched_result" || true)"
emit "required_fact_contract=$required_fact_contract;pass_markers=$pass_markers;blocked_markers=$blocked_markers"
if (( remote_code == 0 )) && [[ "$output_contract" == pass && "$required_fact_contract" == pass && "$pass_markers" == 1 && "$blocked_markers" == 0 ]]; then
  emit 'milestone=relationship_persistence;state=pass'
  emit "script_40_relationship_persistence=pass;local_report=$report_path;next_gate=apply_schema_v4_to_accepted_empty_database"
  exit 0
fi
emit 'milestone=relationship_persistence;state=blocked'
emit "script_40_relationship_persistence=blocked;local_report=$report_path;next_gate=inspect_result_before_any_retry"
exit 1
