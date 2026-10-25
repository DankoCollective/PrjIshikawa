#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the accepted operator-ingestion control plane, producer-artifact
#   adapter, and writer in a disposable native PostgreSQL database.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/77_qualify_operator_ingestion_on_emceedanko.sh --run

usage() {
  sed -n '3,10p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run                      Authorize the disposable target qualification.' \
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
readonly PACKAGE_ROOT="$ISHIKAWA_ROOT/application/python/ishikawa"
readonly TARGET_HELPER="$SCRIPT_DIR/qualify-operator-ingestion-integration"
readonly TARGET_RUNNER="$SCRIPT_DIR/qualify_operator_ingestion_integration.py"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly FIXTURE_ROOT="$ISHIKAWA_ROOT/tests/fixtures/pipeline_writer"
readonly SOURCE_ROOT="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/anderson-upload"
readonly NORMALIZED="$REPO_ROOT/local/artifacts/ishikawa/normalization/normalized_structural_units_20261019T214207Z.json"
readonly CHUNKS="$REPO_ROOT/local/artifacts/ishikawa/retrieval-gap-method-profile/structural_chunk_candidates_20261020T002645Z.json"
readonly EMBEDDINGS="$REPO_ROOT/local/artifacts/ishikawa/retrieval-gap-method-profile/measured_nomic_chunk_embeddings_20261020T002645Z.json"
readonly MIGRATION_0001="$PHASE_ROOT/migrations/0001_initial_rag_catalog.sql"
readonly MIGRATION_0002="$PHASE_ROOT/migrations/0002_align_ingestion_ownership.sql"
readonly MIGRATION_0003="$PHASE_ROOT/migrations/0003_separate_special_token_count.sql"
readonly MIGRATION_0004="$PHASE_ROOT/migrations/0004_preserve_relationship_override_audit.sql"
readonly ACCEPTED_SCRIPT_76_REPORT="$REPO_ROOT/local/reports/ishikawa-operator-ingestion-command/operator_ingestion_command_20261020T173950Z_sG746u.txt"
readonly ACCEPTED_SCRIPT_76_REPORT_SHA256='a8518f4873d7a6bdaed981480898e66c9b2f8c92340cdaa165b1c0262d4df017'
readonly ACCEPTED_SCRIPT_76_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/operator-ingestion-command/operator_ingestion_command_qualification_20261020T173950Z.json"
readonly ACCEPTED_SCRIPT_76_ARTIFACT_SHA256='177ce380f01093343a29c4515661ab4b1be737b093fe2ad7b669221f6d054d7e'
readonly NORMALIZED_SHA256='736d619ac5a7e10f768bdb8b8f3f117cb52231f8dc2f4d186d52d96c8bd41e28'
readonly CHUNKS_SHA256='bc993ca0a417353f0d2313bcb2d1c94a1d526a513253139be71117bf88626bf3'
readonly EMBEDDINGS_SHA256='5bd79048bb59d53b6f6903eec9f4797955763a5fc12c064b17d19db89ba9d641'
readonly MIGRATION_0001_SHA256='3e2f5e61bd8038bc29764024e21b8bec754fad8a282f89abaf6130e345d6380a'
readonly MIGRATION_0002_SHA256='74b08adb8aac9828ac076744fedfd22619751326c911bf17f1fa8690e01345e4'
readonly MIGRATION_0003_SHA256='5e833d8ff556c0e6158daf0419b1013235a11e1a94f1f560206ba813e1fc3761'
readonly MIGRATION_0004_SHA256='5764f6e12a74b18747163c61ef3f314e8dff140a3586b298c62be616a1dc185f'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-operator-ingestion-target"

python_sources=("$PACKAGE_ROOT"/*.py)
config_sources=(
  "$FIXTURE_ROOT/document_classes.yaml"
  "$FIXTURE_ROOT/document_catalog.yaml"
  "$FIXTURE_ROOT/ingestion_manifest.yaml"
)
pdf_sources=(
  "$SOURCE_ROOT/31_SCH_2003.pdf"
  "$SOURCE_ROOT/Form_TST9001.pdf"
  "$SOURCE_ROOT/Governance_Manual_2005_Revision_3.pdf"
  "$SOURCE_ROOT/OPS_17_CTL_2001.pdf"
  "$SOURCE_ROOT/OPS_17_CTL_2002_RevA.pdf"
  "$SOURCE_ROOT/SOP_42_IR_2006.pdf"
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
for source in "$TARGET_HELPER" "$TARGET_RUNNER" "$TEST_RUNNER" "$NORMALIZED" "$CHUNKS" "$EMBEDDINGS" "$MIGRATION_0001" "$MIGRATION_0002" "$MIGRATION_0003" "$MIGRATION_0004" "$ACCEPTED_SCRIPT_76_REPORT" "$ACCEPTED_SCRIPT_76_ARTIFACT" "${python_sources[@]}" "${config_sources[@]}" "${pdf_sources[@]}"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || { printf 'BLOCKED: a required Script 77 input is missing or unsafe.\n' >&2; exit 2; }
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || { printf 'BLOCKED: %s checksum mismatch.\n' "$3" >&2; exit 2; }
}
check_sha256 "$NORMALIZED" "$NORMALIZED_SHA256" 'accepted normalization artifact'
check_sha256 "$CHUNKS" "$CHUNKS_SHA256" 'accepted chunk artifact'
check_sha256 "$EMBEDDINGS" "$EMBEDDINGS_SHA256" 'accepted embedding artifact'
check_sha256 "$MIGRATION_0001" "$MIGRATION_0001_SHA256" 'schema-v1 migration'
check_sha256 "$MIGRATION_0002" "$MIGRATION_0002_SHA256" 'schema-v2 migration'
check_sha256 "$MIGRATION_0003" "$MIGRATION_0003_SHA256" 'schema-v3 migration'
check_sha256 "$MIGRATION_0004" "$MIGRATION_0004_SHA256" 'schema-v4 migration'
check_sha256 "$ACCEPTED_SCRIPT_76_REPORT" "$ACCEPTED_SCRIPT_76_REPORT_SHA256" 'accepted Script 76 report'
check_sha256 "$ACCEPTED_SCRIPT_76_ARTIFACT" "$ACCEPTED_SCRIPT_76_ARTIFACT_SHA256" 'accepted Script 76 artifact'
for fact in \
  'operator_ingestion_command_qualification=pass' \
  'local_tests=279;failures=0;errors=0' \
  'next_gate=connect_operator_ingestion_to_native_producer_and_postgresql'; do
  grep -Fq "$fact" "$ACCEPTED_SCRIPT_76_REPORT" || { printf 'BLOCKED: an accepted Script 76 fact is absent.\n' >&2; exit 2; }
done

bash -n "${BASH_SOURCE[0]}" "$TARGET_HELPER" "$TEST_RUNNER"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' "$TARGET_RUNNER" "${python_sources[@]}"
for neutral_source in "$TARGET_HELPER" "$TARGET_RUNNER"; do
  if grep -Eq '(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)' "$neutral_source" \
    || grep -Eiq 'phase[-_ ]?[0-9]+|Danko|org[_ -]?lab|Agent|repository' "$neutral_source"; then
    printf 'BLOCKED: development or environment jargon found in a neutral target source.\n' >&2
    exit 2
  fi
done

work_root="$(mktemp -d /tmp/ishikawa-script-77.XXXXXX)"
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
  if [[ "$work_root" == /tmp/ishikawa-script-77.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || { cat "$test_result" >&2; printf 'script_77_operator_ingestion_target=blocked;reason=test_regression\n' >&2; exit 1; }
grep -Fq 'Ran 279 tests' "$test_result" || { printf 'script_77_operator_ingestion_target=blocked;reason=test_count_mismatch\n' >&2; exit 1; }
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || { printf 'script_77_operator_ingestion_target=blocked;reason=test_pass_marker_absent\n' >&2; exit 1; }

for source in "${python_sources[@]}"; do install -m 0600 "$source" "$stage_root/payload/ishikawa/$(basename "$source")"; done
for source in "${config_sources[@]}"; do install -m 0600 "$source" "$stage_root/payload/config/$(basename "$source")"; done
for source in "${pdf_sources[@]}"; do install -m 0600 "$source" "$stage_root/payload/source/$(basename "$source")"; done
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$stage_root/payload" python3 -B -c 'import ishikawa.operator_ingestion, ishikawa.artifact_adapter, ishikawa.persistence'
install -m 0600 "$TARGET_HELPER" "$stage_root/qualify-operator-ingestion-integration"
install -m 0600 "$TARGET_RUNNER" "$stage_root/qualify-operator-ingestion-integration.py"
install -m 0600 "$MIGRATION_0001" "$stage_root/0001_initial_rag_catalog.sql"
install -m 0600 "$MIGRATION_0002" "$stage_root/0002_align_ingestion_ownership.sql"
install -m 0600 "$MIGRATION_0003" "$stage_root/0003_separate_special_token_count.sql"
install -m 0600 "$MIGRATION_0004" "$stage_root/0004_preserve_relationship_override_audit.sql"
install -m 0600 "$NORMALIZED" "$stage_root/normalized.json"
install -m 0600 "$CHUNKS" "$stage_root/chunks.json"
install -m 0600 "$EMBEDDINGS" "$stage_root/embeddings.json"
printf '%s  %s\n' "$NORMALIZED_SHA256" normalized.json "$CHUNKS_SHA256" chunks.json "$EMBEDDINGS_SHA256" embeddings.json >"$stage_root/artifact-identities.sha256"
chmod 0600 "$stage_root/artifact-identities.sha256"

payload_manifest="$stage_root/payload.sha256"
: >"$payload_manifest"
for source in "$stage_root"/payload/ishikawa/*.py; do printf '%s  payload/ishikawa/%s\n' "$(sha256sum "$source" | awk '{print $1}')" "$(basename "$source")" >>"$payload_manifest"; done
for source in "$stage_root"/payload/config/*.yaml; do printf '%s  payload/config/%s\n' "$(sha256sum "$source" | awk '{print $1}')" "$(basename "$source")" >>"$payload_manifest"; done
for source in "$stage_root"/payload/source/*.pdf; do printf '%s  payload/source/%s\n' "$(sha256sum "$source" | awk '{print $1}')" "$(basename "$source")" >>"$payload_manifest"; done
for name in normalized.json chunks.json embeddings.json artifact-identities.sha256 0001_initial_rag_catalog.sql 0002_align_ingestion_ownership.sql 0003_separate_special_token_count.sql 0004_preserve_relationship_override_audit.sql qualify-operator-ingestion-integration.py; do printf '%s  %s\n' "$(sha256sum "$stage_root/$name" | awk '{print $1}')" "$name" >>"$payload_manifest"; done
manifest_sha256="$(sha256sum "$payload_manifest" | awk '{print $1}')"
manifest_entries="$(wc -l <"$payload_manifest" | tr -d ' ')"
helper_sha256="$(sha256sum "$TARGET_HELPER" | awk '{print $1}')"
runner_sha256="$(sha256sum "$TARGET_RUNNER" | awk '{print $1}')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_operator_ingestion_target_qualification_source' \
    'target_contact=false;database_contact=false;model_call=false;credential_read=false' \
    "script_sha256=$script_sha256;helper_sha256=$helper_sha256;runner_sha256=$runner_sha256" \
    "payload_manifest_sha256=$manifest_sha256;payload_file_count=$manifest_entries" \
    "accepted_script_76_report_sha256=$ACCEPTED_SCRIPT_76_REPORT_SHA256;accepted_script_76_artifact_sha256=$ACCEPTED_SCRIPT_76_ARTIFACT_SHA256" \
    'local_tests=279;failures=0;errors=0;staged_package_import=pass' \
    'script_77_operator_ingestion_target_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/operator_ingestion_target_${timestamp}_XXXXXX.txt")"
remote_root="/tmp/operator-ingestion-integration-$timestamp-$$"
emit 'purpose=qualify_operator_ingestion_on_application_host'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;helper_sha256=$helper_sha256;runner_sha256=$runner_sha256"
emit "payload_manifest_sha256=$manifest_sha256;payload_file_count=$manifest_entries"
emit "accepted_script_76_report_sha256=$ACCEPTED_SCRIPT_76_REPORT_SHA256;accepted_script_76_artifact_sha256=$ACCEPTED_SCRIPT_76_ARTIFACT_SHA256"
emit 'authorized_actions=stage_verified_synthetic_artifacts_start_postgresql_verify_accepted_database_create_disposable_database_apply_reviewed_schema_exercise_operator_ingestion_drop_disposable_database_verify_accepted_database_stop_postgresql_remove_temporary_files'
emit 'non_actions=no_package_change_no_accepted_database_mutation_no_organizational_document_read_no_embedding_endpoint_call_no_generation_model_call_no_secret_processing_no_service_enablement'
emit "selected_target=$target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version"
emit 'operator_expectation=ssh_key_passphrase_up_to_once;target_sudo_password_may_be_prompted;no_application_secret_prompt'

control_path="$work_root/ssh-control"
ssh_args=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto -o "ControlPath=$control_path" -o ControlPersist=1800)
if [[ -n "$identity_file" ]]; then ssh_args+=(-i "$identity_file" -o IdentitiesOnly=yes); fi
emit 'milestone=authentication;state=waiting_for_operator_if_prompted'
timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$target" >"$work_root/master.stdout" 2>"$work_root/master.stderr" || { emit 'script_77_operator_ingestion_target=blocked;reason=ssh_master_start_failed'; exit 1; }
master_started=true
emit 'milestone=authentication;state=pass'
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root' && mkdir -m 0700 -- '$remote_root/payload' '$remote_root/payload/ishikawa' '$remote_root/payload/config' '$remote_root/payload/source'" >"$work_root/create.stdout" 2>"$work_root/create.stderr" || { emit 'script_77_operator_ingestion_target=blocked;reason=remote_temporary_directory_not_created'; exit 1; }
remote_created=true
timeout --foreground 240 scp "${ssh_args[@]}" "$stage_root"/qualify-operator-ingestion-integration "$stage_root"/qualify-operator-ingestion-integration.py "$stage_root"/0001_initial_rag_catalog.sql "$stage_root"/0002_align_ingestion_ownership.sql "$stage_root"/0003_separate_special_token_count.sql "$stage_root"/0004_preserve_relationship_override_audit.sql "$stage_root"/normalized.json "$stage_root"/chunks.json "$stage_root"/embeddings.json "$stage_root"/artifact-identities.sha256 "$stage_root"/payload.sha256 "$target:$remote_root/" >"$work_root/scp-root.stdout" 2>"$work_root/scp-root.stderr" || { emit 'script_77_operator_ingestion_target=blocked;reason=root_payload_copy_failed'; exit 1; }
timeout --foreground 180 scp "${ssh_args[@]}" "$stage_root"/payload/ishikawa/*.py "$target:$remote_root/payload/ishikawa/" >"$work_root/scp-python.stdout" 2>"$work_root/scp-python.stderr" || { emit 'script_77_operator_ingestion_target=blocked;reason=python_payload_copy_failed'; exit 1; }
timeout --foreground 120 scp "${ssh_args[@]}" "$stage_root"/payload/config/*.yaml "$target:$remote_root/payload/config/" >"$work_root/scp-config.stdout" 2>"$work_root/scp-config.stderr" || { emit 'script_77_operator_ingestion_target=blocked;reason=config_payload_copy_failed'; exit 1; }
timeout --foreground 180 scp "${ssh_args[@]}" "$stage_root"/payload/source/*.pdf "$target:$remote_root/payload/source/" >"$work_root/scp-source.stdout" 2>"$work_root/scp-source.stderr" || { emit 'script_77_operator_ingestion_target=blocked;reason=source_payload_copy_failed'; exit 1; }
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "cd '$remote_root' && printf '%s  %s\n%s  %s\n' '$helper_sha256' qualify-operator-ingestion-integration '$manifest_sha256' payload.sha256 | sha256sum --check --strict -" >"$work_root/hash.stdout" 2>"$work_root/hash.stderr" || { emit 'script_77_operator_ingestion_target=blocked;reason=target_outer_payload_hash_mismatch'; exit 1; }
emit 'milestone=target_payload_verification;state=pass'

emit 'milestone=operator_ingestion_integration;state=waiting_for_operator_sudo_if_prompted'
set +e
timeout --foreground 1200 ssh -tt "${ssh_args[@]}" -o BatchMode=yes "$target" "cd '$remote_root' && sudo -p '[sudo] password for disposable operator ingestion qualification: ' bash ./qualify-operator-ingestion-integration '$expected_hostname' '$expected_os_version' rag_catalog rag_owner rag_ingest rag_retrieval '$remote_root' '$manifest_sha256' '$manifest_entries' > operator-ingestion-integration.txt" < /dev/tty
remote_code=$?
set -e
emit "remote_execution_exit_code=$remote_code;raw_stderr_retained=false"
fetched_result="$work_root/operator-ingestion-integration.txt"
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/operator-ingestion-integration.txt" "$fetched_result" >"$work_root/fetch.stdout" 2>"$work_root/fetch.stderr" || { emit 'script_77_operator_ingestion_target=blocked;reason=result_fetch_failed'; exit 1; }

output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then output_contract=blocked; continue; fi
  emit "$line"
done <"$fetched_result"
emit "remote_output_contract=$output_contract"

required_fact_contract=pass
for fact in \
  'purpose=qualify_operator_ingestion_with_disposable_native_postgresql' \
  "host=$expected_hostname;os_version=$expected_os_version;architecture=amd64" \
  'postgresql_version=16.15;vector_default_version=0.8.7' \
  'temporary_database_created=true;accepted_schema_version=4' \
  'validation_only=pass;planned_adds=6;producer_calls=0;database_mutations=0' \
  'publication=pass;published_documents=6;producer_calls=1;produced_documents=6' \
  'reuse=pass;reused_documents=6;producer_calls_after_reuse=1' \
  'quarantine=pass;quarantine_records=1;producer_calls_after_quarantine=1;active_chunks=126' \
  'persisted_documents=6;structural_units=231;chunks=126;citations=126;embeddings=126' \
  'reports=4;json_mode=0600;source_content_reported=false' \
  'embedding_endpoint_contact=false;generation_model_contact=false' \
  'operator_ingestion_target_qualification=pass' \
  'temporary_database_dropped=true;accepted_database_unchanged=true' \
  'cluster_status=down;postgresql_port_5432=free;postgresql_service_active=inactive;postgresql_service_enabled=disabled' \
  'operator_ingestion_target=pass'; do
  grep -Fq "$fact" "$fetched_result" || required_fact_contract=blocked
done
[[ "$(grep -Ec '^python_version=3\.12\.[0-9]+;psycopg_version=3\.1\.17$' "$fetched_result" || true)" == 1 ]] || required_fact_contract=blocked
pass_markers="$(grep -Fxc 'operator_ingestion_target=pass' "$fetched_result" || true)"
blocked_markers="$(grep -Ec '^operator_ingestion_target=blocked;' "$fetched_result" || true)"
emit "required_fact_contract=$required_fact_contract;pass_markers=$pass_markers;blocked_markers=$blocked_markers"
if (( remote_code == 0 )) && [[ "$output_contract" == pass && "$required_fact_contract" == pass && "$pass_markers" == 1 && "$blocked_markers" == 0 ]]; then
  emit 'milestone=operator_ingestion_integration;state=pass'
  emit "script_77_operator_ingestion_target=pass;local_report=$report_path;next_gate=implement_live_native_document_producer"
  chmod 0600 "$report_path" 2>/dev/null || true
  exit 0
fi
emit 'milestone=operator_ingestion_integration;state=blocked'
emit "script_77_operator_ingestion_target=blocked;local_report=$report_path;next_gate=inspect_target_result_before_any_retry"
chmod 0600 "$report_path" 2>/dev/null || true
exit 1
