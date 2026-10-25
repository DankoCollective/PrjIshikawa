#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the complete configured ingestion path on the application host
#   with live Nomic calls and a disposable native PostgreSQL database.
#
# Explicit execution from the repository root after forwarding port 8001:
#   bash ./phase-28-apisachi-tokuli/scripts/86_qualify_configured_live_ingestion_on_emceedanko.sh --run

usage() {
  sed -n '3,10p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run                      Authorize the bounded target qualification.' \
    '  --target VALUE             SSH destination or configured SSH alias.' \
    '  --expected-hostname NAME   Exact target short hostname.' \
    '  --expected-os-version VER  Exact expected Ubuntu major.minor version.' \
    '  --identity-file PATH       Optional explicit SSH private key.' \
    '  --validate-only            Validate and assemble without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$ISHIKAWA_ROOT/application/python"
readonly PACKAGE_ROOT="$PYTHON_ROOT/ishikawa"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly TARGET_HELPER="$SCRIPT_DIR/qualify-configured-live-ingestion"
readonly TARGET_RUNNER="$SCRIPT_DIR/qualify_configured_live_ingestion.py"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_configured_live_ingestion.py"
readonly PIPELINE_EXECUTABLE="$SCRIPT_DIR/ishikawa-produce-artifacts"
readonly CAPTURE="$SCRIPT_DIR/capture-pdf-extraction-observations.py"
readonly NORMALIZE="$SCRIPT_DIR/normalize-pdf-extraction.py"
readonly CHUNK="$SCRIPT_DIR/create-structural-chunk-candidates.py"
readonly EMBED="$SCRIPT_DIR/embed_document_candidates_via_endpoint.py"
readonly RUNTIME_CONFIG_ROOT="$ISHIKAWA_ROOT/config/templates"
readonly OPERATOR_CONFIG_ROOT="$ISHIKAWA_ROOT/tests/fixtures/pipeline_writer"
readonly SOURCE_ROOT="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/anderson-upload"
readonly MIGRATION_0001="$PHASE_ROOT/migrations/0001_initial_rag_catalog.sql"
readonly MIGRATION_0002="$PHASE_ROOT/migrations/0002_align_ingestion_ownership.sql"
readonly MIGRATION_0003="$PHASE_ROOT/migrations/0003_separate_special_token_count.sql"
readonly MIGRATION_0004="$PHASE_ROOT/migrations/0004_preserve_relationship_override_audit.sql"
readonly MIGRATION_0001_SHA256='3e2f5e61bd8038bc29764024e21b8bec754fad8a282f89abaf6130e345d6380a'
readonly MIGRATION_0002_SHA256='74b08adb8aac9828ac076744fedfd22619751326c911bf17f1fa8690e01345e4'
readonly MIGRATION_0003_SHA256='5e833d8ff556c0e6158daf0419b1013235a11e1a94f1f560206ba813e1fc3761'
readonly MIGRATION_0004_SHA256='5764f6e12a74b18747163c61ef3f314e8dff140a3586b298c62be616a1dc185f'
readonly ACCEPTED_SCRIPT_85_REPORT="$REPO_ROOT/local/reports/ishikawa-live-document-pipeline-target/live_document_pipeline_target_20261020T192247Z_kTxQTP.txt"
readonly ACCEPTED_SCRIPT_85_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/live-document-pipeline-target/live_document_pipeline_target_qualification_20261020T192247Z.json"
readonly ACCEPTED_SCRIPT_85_CHECKSUM="$ACCEPTED_SCRIPT_85_ARTIFACT.sha256"
readonly ACCEPTED_SCRIPT_85_REPORT_SHA256='c978268a6a9a0c27218306280472b3a24c7437c2fb4a63c5ff3b6040a06d8f3c'
readonly ACCEPTED_SCRIPT_85_ARTIFACT_SHA256='5554037767177fcfe844bdf835e2ab2c5c1050a3be2dd9d0f544cb73cca9e6b5'
readonly ACCEPTED_SCRIPT_85_CHECKSUM_SHA256='5695b294a9c280266f3b372d504fa08b80d3ec849aa42fcf33b0bb61860aae7d'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-configured-live-ingestion-target"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/configured-live-ingestion-target"

mapfile -t PYTHON_SOURCES < <(find "$PACKAGE_ROOT" -maxdepth 1 -type f -name '*.py' -print | sort)
mapfile -t PDF_SOURCES < <(find "$SOURCE_ROOT" -maxdepth 1 -type f -name '*.pdf' -print | sort)
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
for required in awk bash basename chmod cp date find grep install mkdir mktemp mv python3 rm scp sha256sum sort ssh stat tar tee timeout wc; do
  command -v "$required" >/dev/null 2>&1 || { printf 'BLOCKED: missing local command: %s\n' "$required" >&2; exit 2; }
done
(( ${#PYTHON_SOURCES[@]} > 0 )) || { printf 'BLOCKED: no Python application sources were found.\n' >&2; exit 2; }
(( ${#PDF_SOURCES[@]} == 6 )) || { printf 'BLOCKED: synthetic PDF inventory mismatch.\n' >&2; exit 2; }
for source in \
  "$TEST_RUNNER" "$TARGET_HELPER" "$TARGET_RUNNER" "$EVALUATOR" \
  "$PIPELINE_EXECUTABLE" "$CAPTURE" "$NORMALIZE" "$CHUNK" "$EMBED" \
  "$RUNTIME_CONFIG_ROOT/deployment.yaml" "$RUNTIME_CONFIG_ROOT/ingestion_dependencies.yaml" \
  "$OPERATOR_CONFIG_ROOT/document_classes.yaml" "$OPERATOR_CONFIG_ROOT/document_catalog.yaml" "$OPERATOR_CONFIG_ROOT/ingestion_manifest.yaml" \
  "$MIGRATION_0001" "$MIGRATION_0002" "$MIGRATION_0003" "$MIGRATION_0004" \
  "$ACCEPTED_SCRIPT_85_REPORT" "$ACCEPTED_SCRIPT_85_ARTIFACT" "$ACCEPTED_SCRIPT_85_CHECKSUM" \
  "${PYTHON_SOURCES[@]}" "${PDF_SOURCES[@]}"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || { printf 'BLOCKED: a required Script 86 input is missing or unsafe.\n' >&2; exit 2; }
done
[[ -x "$PIPELINE_EXECUTABLE" ]] || { printf 'BLOCKED: pipeline executable is not executable.\n' >&2; exit 2; }

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || { printf 'BLOCKED: %s identity changed.\n' "$3" >&2; exit 2; }
}
check_sha256 "$ACCEPTED_SCRIPT_85_REPORT" "$ACCEPTED_SCRIPT_85_REPORT_SHA256" 'accepted Script 85 report'
check_sha256 "$ACCEPTED_SCRIPT_85_ARTIFACT" "$ACCEPTED_SCRIPT_85_ARTIFACT_SHA256" 'accepted Script 85 artifact'
check_sha256 "$ACCEPTED_SCRIPT_85_CHECKSUM" "$ACCEPTED_SCRIPT_85_CHECKSUM_SHA256" 'accepted Script 85 checksum'
check_sha256 "$MIGRATION_0001" "$MIGRATION_0001_SHA256" 'accepted migration 0001'
check_sha256 "$MIGRATION_0002" "$MIGRATION_0002_SHA256" 'accepted migration 0002'
check_sha256 "$MIGRATION_0003" "$MIGRATION_0003_SHA256" 'accepted migration 0003'
check_sha256 "$MIGRATION_0004" "$MIGRATION_0004_SHA256" 'accepted migration 0004'
(cd "$(dirname -- "$ACCEPTED_SCRIPT_85_ARTIFACT")" && sha256sum --check --strict "$(basename -- "$ACCEPTED_SCRIPT_85_CHECKSUM")" >/dev/null) || { printf 'BLOCKED: accepted Script 85 artifact failed checksum verification.\n' >&2; exit 2; }
for fact in \
  'live_document_pipeline_target_evaluation=pass' \
  'documents=6;pages=27;structural_units=231;chunks=126' \
  'script_85_live_document_pipeline_target=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_SCRIPT_85_REPORT" || { printf 'BLOCKED: an accepted Script 85 fact is absent.\n' >&2; exit 2; }
done

bash -n "${BASH_SOURCE[0]}" "$TARGET_HELPER" "$TEST_RUNNER"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$TARGET_RUNNER" "$EVALUATOR" "$PIPELINE_EXECUTABLE" "$CAPTURE" "$NORMALIZE" "$CHUNK" "$EMBED" "${PYTHON_SOURCES[@]}"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" --self-test | grep -Fxq 'configured_live_ingestion_evaluator_self_test=pass'
for neutral_source in "$TARGET_HELPER" "$TARGET_RUNNER"; do
  if grep -Eq '(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)' "$neutral_source" || grep -Eiq 'phase[-_ ]?[0-9]+|Danko|org[_ -]?lab|Agent|repository' "$neutral_source"; then
    printf 'BLOCKED: development or environment jargon found in a neutral target source.\n' >&2
    exit 2
  fi
done

work_root="$(mktemp -d /tmp/ishikawa-script-86.XXXXXX)"
stage_root="$work_root/package"
mkdir -m 0700 -p -- \
  "$stage_root/Ishikawa/application/python/ishikawa" \
  "$stage_root/config/runtime" "$stage_root/config/operator" \
  "$stage_root/source" "$stage_root/scripts" "$stage_root/migrations"
report_path=''
remote_root=''
remote_created=false
master_started=false
artifact_path=''
checksum_path=''
artifact_temp=''
checksum_temp=''
local_artifact_committed=false
ssh_args=()
emit() { if [[ -n "$report_path" ]]; then printf '%s\n' "$1" | tee -a "$report_path"; else printf '%s\n' "$1"; fi; }
cleanup() {
  local status="$?" cleanup_code=0 close_code=0
  trap - EXIT INT TERM
  set +e
  if [[ "$remote_created" == true && "$master_started" == true ]]; then
    timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "rm -rf -- '$remote_root' && test ! -e '$remote_root'" >/dev/null 2>&1 || cleanup_code=$?
    if (( cleanup_code == 0 )); then emit 'cleanup_remote_temporary_files=removed'; else emit "cleanup_remote_temporary_files=review_required;exit_code=$cleanup_code"; status=1; fi
  fi
  if [[ "$master_started" == true ]]; then
    timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1 || close_code=$?
    emit "cleanup_ssh_master_exit_code=$close_code"
    (( close_code == 0 )) || status=1
  fi
  if [[ "$local_artifact_committed" != true ]]; then
    if [[ "$artifact_temp" == "$ARTIFACT_ROOT"/.configured-live-ingestion-artifact.* && -f "$artifact_temp" ]]; then rm -f -- "$artifact_temp"; fi
    if [[ "$checksum_temp" == "$ARTIFACT_ROOT"/.configured-live-ingestion-checksum.* && -f "$checksum_temp" ]]; then rm -f -- "$checksum_temp"; fi
    if [[ "$artifact_path" == "$ARTIFACT_ROOT"/configured_live_ingestion_target_qualification_*.json && -f "$artifact_path" ]]; then rm -f -- "$artifact_path"; fi
    if [[ "$checksum_path" == "$ARTIFACT_ROOT"/configured_live_ingestion_target_qualification_*.json.sha256 && -f "$checksum_path" ]]; then rm -f -- "$checksum_path"; fi
  fi
  if [[ "$work_root" == /tmp/ishikawa-script-86.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || { printf 'script_86_configured_live_ingestion_target=blocked;reason=test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s\n' "$(sha256sum "$test_result" | awk '{print $1}')" "$(stat -c '%s' "$test_result")" >&2; exit 1; }
grep -Fq 'Ran 310 tests' "$test_result" || { printf 'script_86_configured_live_ingestion_target=blocked;reason=test_count_mismatch\n' >&2; exit 1; }
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || { printf 'script_86_configured_live_ingestion_target=blocked;reason=test_pass_marker_absent\n' >&2; exit 1; }

for source in "${PYTHON_SOURCES[@]}"; do install -m 0600 "$source" "$stage_root/Ishikawa/application/python/ishikawa/$(basename -- "$source")"; done
for name in deployment.yaml ingestion_dependencies.yaml; do install -m 0600 "$RUNTIME_CONFIG_ROOT/$name" "$stage_root/config/runtime/$name"; done
for name in document_classes.yaml document_catalog.yaml ingestion_manifest.yaml; do install -m 0600 "$OPERATOR_CONFIG_ROOT/$name" "$stage_root/config/operator/$name"; done
for source in "${PDF_SOURCES[@]}"; do install -m 0600 "$source" "$stage_root/source/$(basename -- "$source")"; done
for source in "$CAPTURE" "$NORMALIZE" "$CHUNK" "$EMBED"; do install -m 0600 "$source" "$stage_root/scripts/$(basename -- "$source")"; done
install -m 0700 "$PIPELINE_EXECUTABLE" "$stage_root/scripts/ishikawa-produce-artifacts"
install -m 0700 "$TARGET_HELPER" "$stage_root/qualify-configured-live-ingestion"
install -m 0600 "$TARGET_RUNNER" "$stage_root/qualify_configured_live_ingestion.py"
install -m 0600 "$MIGRATION_0001" "$stage_root/migrations/0001_initial_rag_catalog.sql"
install -m 0600 "$MIGRATION_0002" "$stage_root/migrations/0002_align_ingestion_ownership.sql"
install -m 0600 "$MIGRATION_0003" "$stage_root/migrations/0003_separate_special_token_count.sql"
install -m 0600 "$MIGRATION_0004" "$stage_root/migrations/0004_preserve_relationship_override_audit.sql"

payload_manifest="$stage_root/payload.sha256"
: >"$payload_manifest"
while IFS= read -r relative; do
  printf '%s  %s\n' "$(sha256sum "$stage_root/$relative" | awk '{print $1}')" "$relative" >>"$payload_manifest"
done < <(cd "$stage_root" && find Ishikawa config migrations scripts source -type f -print | sort; printf '%s\n' qualify_configured_live_ingestion.py)
payload_sha256="$(sha256sum "$payload_manifest" | awk '{print $1}')"
payload_count="$(wc -l <"$payload_manifest" | tr -d ' ')"
bundle="$work_root/ishikawa-configured-live-ingestion.tar.gz"
tar -czf "$bundle" -C "$stage_root" .
bundle_sha256="$(sha256sum "$bundle" | awk '{print $1}')"
bundle_bytes="$(stat -c '%s' "$bundle")"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
helper_sha256="$(sha256sum "$TARGET_HELPER" | awk '{print $1}')"
runner_sha256="$(sha256sum "$TARGET_RUNNER" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_configured_live_ingestion_target_qualification_source' \
    'target_contact=false;database_contact=false;model_call=false;credential_read=false;forwarding_changed=false' \
    "script_sha256=$script_sha256;helper_sha256=$helper_sha256;runner_sha256=$runner_sha256;evaluator_sha256=$evaluator_sha256" \
    "payload_manifest_sha256=$payload_sha256;payload_file_count=$payload_count;bundle_sha256=$bundle_sha256;bundle_bytes=$bundle_bytes" \
    "accepted_script_85_report_sha256=$ACCEPTED_SCRIPT_85_REPORT_SHA256;accepted_script_85_artifact_sha256=$ACCEPTED_SCRIPT_85_ARTIFACT_SHA256" \
    'transport_owner=operator;port_8001_required_preexisting=true;forwarding_managed_by_script=false' \
    'accepted_database_targeted=false;disposable_database_only=true' \
    'local_tests=310;failures=0;errors=0;staged_source_compile=pass;payload_assembly=pass' \
    'script_86_configured_live_ingestion_target_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/configured_live_ingestion_target_${timestamp}_XXXXXX.txt")"
remote_root="/tmp/ishikawa-configured-live-ingestion-$timestamp-$$"
emit 'purpose=qualify_configured_live_ingestion_on_application_host'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;helper_sha256=$helper_sha256;runner_sha256=$runner_sha256;evaluator_sha256=$evaluator_sha256"
emit "payload_manifest_sha256=$payload_sha256;payload_file_count=$payload_count;bundle_sha256=$bundle_sha256;bundle_bytes=$bundle_bytes"
emit "accepted_script_85_report_sha256=$ACCEPTED_SCRIPT_85_REPORT_SHA256;accepted_script_85_artifact_sha256=$ACCEPTED_SCRIPT_85_ARTIFACT_SHA256"
emit 'authorized_actions=transfer_checksum_bound_synthetic_package_start_native_postgresql_create_disposable_database_run_configured_live_ingestion_drop_disposable_database_verify_accepted_database_unchanged_stop_postgresql_remove_temporary_files'
emit 'non_actions=no_forward_start_stop_or_change_no_package_firewall_or_accepted_database_change_no_generation_model_call_no_organizational_content_no_service_enablement'
emit "selected_target=$target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version"
emit 'operator_expectation=forward_port_8001_before_script_ssh_key_passphrase_up_to_once_target_sudo_password_once_nomic_api_key_once;script_leaves_forwarding_running=true'
emit 'local_tests=310;failures=0;errors=0'

control_path="$work_root/ssh-control"
ssh_args=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto -o "ControlPath=$control_path" -o ControlPersist=1800)
if [[ -n "$identity_file" ]]; then ssh_args+=(-i "$identity_file" -o IdentitiesOnly=yes); fi
emit 'milestone=authentication;state=waiting_for_operator_if_prompted'
timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$target" >/dev/null 2>&1 || { emit 'script_86_configured_live_ingestion_target=blocked;reason=ssh_master_start_failed'; exit 1; }
master_started=true
emit 'milestone=authentication;state=pass'
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" >/dev/null || { emit 'script_86_configured_live_ingestion_target=blocked;reason=remote_temporary_directory_not_created'; exit 1; }
remote_created=true
timeout --foreground 240 scp "${ssh_args[@]}" "$bundle" "$target:$remote_root/package.tar.gz" >/dev/null || { emit 'script_86_configured_live_ingestion_target=blocked;reason=package_transfer_failed'; exit 1; }
timeout --foreground 180 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "cd '$remote_root' && printf '%s  package.tar.gz\n' '$bundle_sha256' | sha256sum --check --strict - >/dev/null && tar -xzf package.tar.gz && printf '%s  qualify-configured-live-ingestion\n%s  payload.sha256\n' '$helper_sha256' '$payload_sha256' | sha256sum --check --strict - >/dev/null && sha256sum --check --strict payload.sha256 >/dev/null && chmod 0700 qualify-configured-live-ingestion scripts/ishikawa-produce-artifacts" >/dev/null || { emit 'script_86_configured_live_ingestion_target=blocked;reason=target_payload_verification_failed'; exit 1; }
emit 'milestone=target_payload_verification;state=pass'

emit 'milestone=configured_live_ingestion;state=waiting_for_operator_sudo_and_nomic_credential'
set +e
timeout --foreground 2400 ssh -tt "${ssh_args[@]}" "$target" "cd '$remote_root' && sudo -p '[sudo] password for configured live-ingestion qualification: ' bash ./qualify-configured-live-ingestion '$expected_hostname' '$expected_os_version' rag_catalog rag_owner rag_ingest rag_retrieval '$remote_root' '$payload_sha256' '$payload_count' > qualification-result.txt" </dev/tty
remote_code=$?
set -e
emit "remote_execution_exit_code=$remote_code;raw_stderr_retained=false"
fetched_result="$work_root/qualification-result.txt"
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/qualification-result.txt" "$fetched_result" >/dev/null || { emit 'script_86_configured_live_ingestion_target=blocked;reason=result_fetch_failed'; exit 1; }

output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then output_contract=blocked; continue; fi
  emit "$line"
done <"$fetched_result"
emit "remote_output_contract=$output_contract"
pass_markers="$(grep -Fxc 'configured_live_ingestion_target=pass' "$fetched_result" || true)"
blocked_markers="$(grep -Ec '^configured_live_ingestion=blocked;' "$fetched_result" || true)"
required_fact_contract=pass
for fact in \
  'temporary_database_created=true;accepted_schema_version=4' \
  'validation_only=pass;planned_adds=6;stage_calls=0;database_mutations=0' \
  'publication=pass;published_documents=6;live_stage_calls=1;artifact_retention_calls=1' \
  'reuse=pass;reused_documents=6;live_stage_calls_after_reuse=1' \
  'persisted_documents=6;pages=27;structural_units=231;chunks=126;citations=126;embeddings=126' \
  'embedding_dimension=768;database_connections=3;retained_artifact_objects=3' \
  'temporary_database_dropped=true;accepted_database_unchanged=true' \
  'target_runtime_artifacts_removed=true;forwarding_changed=false;credential_retained=false' \
  'configured_live_ingestion_target=pass'; do
  [[ "$(grep -Fxc "$fact" "$fetched_result" || true)" == 1 ]] || required_fact_contract=blocked
done
emit "required_fact_contract=$required_fact_contract;pass_markers=$pass_markers;blocked_markers=$blocked_markers"
if (( remote_code != 0 )) || [[ "$output_contract" != pass || "$required_fact_contract" != pass || "$pass_markers" != 1 || "$blocked_markers" != 0 ]]; then
  emit 'milestone=configured_live_ingestion;state=blocked'
  emit "script_86_configured_live_ingestion_target=blocked;local_report=$report_path;next_gate=review_content_free_result_before_any_retry"
  exit 1
fi

fetched_artifact="$work_root/configured-live-ingestion.json"
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/configured-live-ingestion.json" "$fetched_artifact" >/dev/null || { emit 'script_86_configured_live_ingestion_target=blocked;reason=artifact_fetch_failed'; exit 1; }
evaluation_result="$work_root/evaluation.txt"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" --artifact "$fetched_artifact" >"$evaluation_result"
grep -Fxq 'configured_live_ingestion_target_evaluation=pass' "$evaluation_result" || { emit 'script_86_configured_live_ingestion_target=blocked;reason=local_artifact_evaluation_failed'; exit 1; }
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"

artifact_sha256="$(sha256sum "$fetched_artifact" | awk '{print $1}')"
artifact_path="$ARTIFACT_ROOT/configured_live_ingestion_target_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || { emit 'script_86_configured_live_ingestion_target=blocked;reason=artifact_path_exists'; exit 1; }
artifact_temp="$(mktemp "$ARTIFACT_ROOT/.configured-live-ingestion-artifact.XXXXXX")"
checksum_temp="$(mktemp "$ARTIFACT_ROOT/.configured-live-ingestion-checksum.XXXXXX")"

timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "rm -rf -- '$remote_root' && test ! -e '$remote_root'" >/dev/null 2>&1 || { emit 'script_86_configured_live_ingestion_target=blocked;reason=remote_temporary_cleanup_failed'; exit 1; }
remote_created=false
emit 'cleanup_remote_temporary_files=removed'
timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1 || { emit 'script_86_configured_live_ingestion_target=blocked;reason=ssh_master_close_failed'; exit 1; }
master_started=false
emit 'cleanup_ssh_master_exit_code=0'

cp -- "$fetched_artifact" "$artifact_temp"
[[ "$(sha256sum "$artifact_temp" | awk '{print $1}')" == "$artifact_sha256" ]] || { emit 'script_86_configured_live_ingestion_target=blocked;reason=local_artifact_copy_identity_mismatch'; exit 1; }
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_temp"
chmod 0600 "$artifact_temp" "$checksum_temp" 2>/dev/null || true
mv -- "$artifact_temp" "$artifact_path"
artifact_temp=''
mv -- "$checksum_temp" "$checksum_path"
checksum_temp=''
(cd "$ARTIFACT_ROOT" && sha256sum --check --strict "$(basename -- "$checksum_path")" >/dev/null) || { emit 'script_86_configured_live_ingestion_target=blocked;reason=local_artifact_checksum_verification_failed'; exit 1; }
local_artifact_committed=true
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$(stat -c '%s' "$artifact_path")"
emit "accepted_checksum=$checksum_path"
emit 'accepted_database_unchanged=true;disposable_database_removed=true;postgresql_restored_stopped_disabled=true;forwarding_changed=false;credential_retained=false;raw_content_retained=false;vectors_retained=false'
emit 'milestone=configured_live_ingestion;state=pass'
emit "script_86_configured_live_ingestion_target=pass;local_report=$report_path;next_gate=prepare_installed_operator_ingestion_entrypoint"
chmod 0600 "$report_path" 2>/dev/null || true
