#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Run the accepted neutral live document pipeline executable on the
#   application host using synthetic PDFs and a pre-forwarded Nomic endpoint.
#
# Explicit execution from the repository root after forwarding port 8001:
#   bash ./phase-28-apisachi-tokuli/scripts/85_run_live_document_pipeline_executable_on_emceedanko.sh --run

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
readonly EVALUATOR="$SCRIPT_DIR/evaluate_live_document_pipeline_target.py"
readonly PIPELINE_EXECUTABLE="$SCRIPT_DIR/ishikawa-produce-artifacts"
readonly CAPTURE="$SCRIPT_DIR/capture-pdf-extraction-observations.py"
readonly NORMALIZE="$SCRIPT_DIR/normalize-pdf-extraction.py"
readonly CHUNK="$SCRIPT_DIR/create-structural-chunk-candidates.py"
readonly EMBED="$SCRIPT_DIR/embed_document_candidates_via_endpoint.py"
readonly CONFIG_ROOT="$ISHIKAWA_ROOT/tests/fixtures/pipeline_writer"
readonly SOURCE_ROOT="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/anderson-upload"
readonly ACCEPTED_SCRIPT_84_REPORT="$REPO_ROOT/local/reports/ishikawa-live-document-pipeline-executable/live_document_pipeline_executable_20261020T191606Z_sj2Cda.txt"
readonly ACCEPTED_SCRIPT_84_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/live-document-pipeline-executable/live_document_pipeline_executable_qualification_20261020T191606Z.json"
readonly ACCEPTED_SCRIPT_84_CHECKSUM="$ACCEPTED_SCRIPT_84_ARTIFACT.sha256"
readonly ACCEPTED_SCRIPT_84_REPORT_SHA256='7a0d7110aa7ad49ffe5ca79ade12edaba0b616f1390e739607e5e318b6096e73'
readonly ACCEPTED_SCRIPT_84_ARTIFACT_SHA256='0f1bd119d8825ae9a6628cc2732e9a85d686deef6d0b04eda5ad3182d001f4e2'
readonly ACCEPTED_SCRIPT_84_CHECKSUM_SHA256='9c3c227615387acf592d457dd5aaba68b47b87a03f47317706568a8fc5fedc53'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-live-document-pipeline-target"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/live-document-pipeline-target"

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
for required in awk bash basename chmod cp date find grep install mkdir mktemp python3 rm scp sha256sum sort ssh stat tar tee timeout wc; do
  command -v "$required" >/dev/null 2>&1 || { printf 'BLOCKED: missing local command: %s\n' "$required" >&2; exit 2; }
done
(( ${#PYTHON_SOURCES[@]} > 0 )) || { printf 'BLOCKED: no Python application sources were found.\n' >&2; exit 2; }
(( ${#PDF_SOURCES[@]} == 6 )) || { printf 'BLOCKED: synthetic PDF inventory mismatch.\n' >&2; exit 2; }
for source in \
  "$TEST_RUNNER" "$EVALUATOR" "$PIPELINE_EXECUTABLE" "$CAPTURE" "$NORMALIZE" "$CHUNK" "$EMBED" \
  "$CONFIG_ROOT/document_classes.yaml" "$CONFIG_ROOT/document_catalog.yaml" "$CONFIG_ROOT/ingestion_manifest.yaml" \
  "$ACCEPTED_SCRIPT_84_REPORT" "$ACCEPTED_SCRIPT_84_ARTIFACT" "$ACCEPTED_SCRIPT_84_CHECKSUM" \
  "${PYTHON_SOURCES[@]}" "${PDF_SOURCES[@]}"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || { printf 'BLOCKED: a required Script 85 input is missing or unsafe.\n' >&2; exit 2; }
done
[[ -x "$PIPELINE_EXECUTABLE" ]] || { printf 'BLOCKED: pipeline executable is not executable.\n' >&2; exit 2; }

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || { printf 'BLOCKED: %s identity changed.\n' "$3" >&2; exit 2; }
}
check_sha256 "$ACCEPTED_SCRIPT_84_REPORT" "$ACCEPTED_SCRIPT_84_REPORT_SHA256" 'accepted Script 84 report'
check_sha256 "$ACCEPTED_SCRIPT_84_ARTIFACT" "$ACCEPTED_SCRIPT_84_ARTIFACT_SHA256" 'accepted Script 84 artifact'
check_sha256 "$ACCEPTED_SCRIPT_84_CHECKSUM" "$ACCEPTED_SCRIPT_84_CHECKSUM_SHA256" 'accepted Script 84 checksum'
(cd "$(dirname -- "$ACCEPTED_SCRIPT_84_ARTIFACT")" && sha256sum --check --strict "$(basename -- "$ACCEPTED_SCRIPT_84_CHECKSUM")" >/dev/null) || {
  printf 'BLOCKED: accepted Script 84 artifact failed checksum verification.\n' >&2
  exit 2
}
for fact in \
  'live_document_pipeline_executable_qualification=pass' \
  'local_tests=310;failures=0;errors=0' \
  'script_84_live_document_pipeline_executable=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_SCRIPT_84_REPORT" || { printf 'BLOCKED: an accepted Script 84 fact is absent.\n' >&2; exit 2; }
done

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$EVALUATOR" "$PIPELINE_EXECUTABLE" "$CAPTURE" "$NORMALIZE" "$CHUNK" "$EMBED" "${PYTHON_SOURCES[@]}"
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B "$EVALUATOR" --self-test \
  | grep -Fxq 'live_document_pipeline_target_evaluator_self_test=pass'

work_root="$(mktemp -d /tmp/ishikawa-script-85.XXXXXX)"
stage_root="$work_root/package"
mkdir -m 0700 -p -- \
  "$stage_root/scripts" \
  "$stage_root/Ishikawa/application/python/ishikawa" \
  "$stage_root/source" \
  "$stage_root/workspace"
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
  if [[ "$work_root" == /tmp/ishikawa-script-85.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  printf 'script_85_live_document_pipeline_target=blocked;reason=test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$test_result" | awk '{print $1}')" "$(stat -c '%s' "$test_result")" >&2
  exit 1
}
grep -Fq 'Ran 310 tests' "$test_result" || { printf 'script_85_live_document_pipeline_target=blocked;reason=test_count_mismatch\n' >&2; exit 1; }
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || { printf 'script_85_live_document_pipeline_target=blocked;reason=test_pass_marker_absent\n' >&2; exit 1; }

for source in "${PYTHON_SOURCES[@]}"; do install -m 0600 "$source" "$stage_root/Ishikawa/application/python/ishikawa/$(basename -- "$source")"; done
for source in "${PDF_SOURCES[@]}"; do install -m 0600 "$source" "$stage_root/source/$(basename -- "$source")"; done
for source in "$CAPTURE" "$NORMALIZE" "$CHUNK" "$EMBED"; do install -m 0600 "$source" "$stage_root/scripts/$(basename -- "$source")"; done
install -m 0700 "$PIPELINE_EXECUTABLE" "$stage_root/scripts/ishikawa-produce-artifacts"

request_result="$work_root/request-result.txt"
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B "$EVALUATOR" prepare \
  --config-root "$CONFIG_ROOT" --source-root "$SOURCE_ROOT" \
  --output "$stage_root/workspace/stage-request.json" >"$request_result"
grep -Fxq 'live_document_pipeline_target_request=pass' "$request_result" || { printf 'script_85_live_document_pipeline_target=blocked;reason=request_preparation_failed\n' >&2; exit 1; }
request_sha256="$(sha256sum "$stage_root/workspace/stage-request.json" | awk '{print $1}')"

PYTHONDONTWRITEBYTECODE=1 "$stage_root/scripts/ishikawa-produce-artifacts" --help >/dev/null
for neutral_source in "$stage_root/scripts"/* "$stage_root/Ishikawa/application/python/ishikawa"/*.py; do
  if grep -Eiq 'phase[-_ ]?[0-9]+|Danko|org[_ -]?lab|AgentDanko|repository root' "$neutral_source"; then
    printf 'BLOCKED: development or environment jargon found in a target source.\n' >&2
    exit 2
  fi
done

payload_manifest="$stage_root/payload.sha256"
: >"$payload_manifest"
while IFS= read -r relative; do
  printf '%s  %s\n' "$(sha256sum "$stage_root/$relative" | awk '{print $1}')" "$relative" >>"$payload_manifest"
done < <(cd "$stage_root" && find Ishikawa scripts source workspace -type f -print | sort)
payload_sha256="$(sha256sum "$payload_manifest" | awk '{print $1}')"
payload_count="$(wc -l <"$payload_manifest" | tr -d ' ')"
bundle="$work_root/ishikawa-live-document-pipeline.tar.gz"
tar -czf "$bundle" -C "$stage_root" .
bundle_sha256="$(sha256sum "$bundle" | awk '{print $1}')"
bundle_bytes="$(stat -c '%s' "$bundle")"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
executable_sha256="$(sha256sum "$PIPELINE_EXECUTABLE" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  cat "$request_result"
  printf '%s\n' \
    'purpose=validate_live_document_pipeline_target_qualification_source' \
    'target_contact=false;database_contact=false;model_call=false;credential_read=false;forwarding_changed=false' \
    "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256;executable_sha256=$executable_sha256" \
    "payload_manifest_sha256=$payload_sha256;payload_file_count=$payload_count;bundle_sha256=$bundle_sha256;bundle_bytes=$bundle_bytes" \
    "request_sha256=$request_sha256;accepted_script_84_report_sha256=$ACCEPTED_SCRIPT_84_REPORT_SHA256;accepted_script_84_artifact_sha256=$ACCEPTED_SCRIPT_84_ARTIFACT_SHA256" \
    'transport_owner=operator;port_8001_required_preexisting=true;forwarding_managed_by_script=false' \
    'local_tests=310;failures=0;errors=0;staged_executable_import=pass' \
    'script_85_live_document_pipeline_target_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/live_document_pipeline_target_${timestamp}_XXXXXX.txt")"
remote_root="/tmp/ishikawa-live-document-pipeline-$timestamp-$$"
emit 'purpose=run_live_document_pipeline_executable_on_application_host'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256;executable_sha256=$executable_sha256"
emit "payload_manifest_sha256=$payload_sha256;payload_file_count=$payload_count;bundle_sha256=$bundle_sha256;bundle_bytes=$bundle_bytes;request_sha256=$request_sha256"
emit "accepted_script_84_report_sha256=$ACCEPTED_SCRIPT_84_REPORT_SHA256;accepted_script_84_artifact_sha256=$ACCEPTED_SCRIPT_84_ARTIFACT_SHA256"
emit 'authorized_actions=transfer_checksum_bound_synthetic_package_run_neutral_poppler_normalization_chunking_and_nomic_embedding_pipeline_fetch_and_validate_temporary_artifacts_retain_content_free_evidence_remove_target_temporary_files'
emit 'non_actions=no_forward_start_stop_or_change_no_sudo_no_package_service_firewall_schema_database_or_corpus_change_no_generation_model_call_no_organizational_content'
emit "selected_target=$target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version"
emit 'operator_expectation=forward_port_8001_before_script_ssh_key_passphrase_up_to_once_nomic_api_key_once_sudo_prompt=none;script_leaves_forwarding_running=true'
emit 'local_tests=310;failures=0;errors=0'

control_path="$work_root/ssh-control"
ssh_args=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto -o "ControlPath=$control_path" -o ControlPersist=1800)
if [[ -n "$identity_file" ]]; then ssh_args+=(-i "$identity_file" -o IdentitiesOnly=yes); fi
emit 'milestone=authentication;state=waiting_for_operator_if_prompted'
timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$target" >/dev/null 2>&1 || { emit 'script_85_live_document_pipeline_target=blocked;reason=ssh_master_start_failed'; exit 1; }
master_started=true
emit 'milestone=authentication;state=pass'
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" >/dev/null \
  || { emit 'script_85_live_document_pipeline_target=blocked;reason=remote_temporary_directory_not_created'; exit 1; }
remote_created=true
timeout --foreground 180 scp "${ssh_args[@]}" "$bundle" "$target:$remote_root/package.tar.gz" >/dev/null \
  || { emit 'script_85_live_document_pipeline_target=blocked;reason=package_transfer_failed'; exit 1; }
timeout --foreground 120 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && printf '%s  package.tar.gz\n' '$bundle_sha256' | sha256sum --check --strict - >/dev/null && tar -xzf package.tar.gz && sha256sum --check --strict payload.sha256 >/dev/null && chmod 0700 scripts/ishikawa-produce-artifacts && test \"\$(hostname -s)\" = '$expected_hostname' && . /etc/os-release && test \"\$ID\" = ubuntu && test \"\$VERSION_ID\" = '$expected_os_version' && test \"\$(dpkg --print-architecture)\" = amd64 && ss -H -ltn4 'sport = :8001' | awk '\$4 == \"127.0.0.1:8001\" {found=1} END {exit !found}'" >/dev/null \
  || { emit 'script_85_live_document_pipeline_target=blocked;reason=target_preflight_or_payload_verification_failed'; exit 1; }
emit 'milestone=target_payload_verification;state=pass'

listener_before="$(timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "ss -H -ltn4 'sport = :8001' | sha256sum | awk '{print \$1}'")"
[[ "$listener_before" =~ ^[0-9a-f]{64}$ ]] || { emit 'script_85_live_document_pipeline_target=blocked;reason=listener_identity_unavailable'; exit 1; }
emit 'milestone=live_document_pipeline;state=waiting_for_operator_nomic_credential'
set +e
timeout --foreground 1800 ssh -tt "${ssh_args[@]}" "$target" \
  "cd '$remote_root' && umask 077 && printf 'Nomic API key (input hidden): ' >/dev/tty && IFS= read -r -s nomic_key </dev/tty && printf '\n' >/dev/tty && printf '%s' \"\$nomic_key\" | ./scripts/ishikawa-produce-artifacts --request '$remote_root/workspace/stage-request.json' --source-root '$remote_root/source' --workspace '$remote_root/workspace' --embedding-url http://127.0.0.1:8001/v1/embeddings --tokenization-url http://127.0.0.1:8001/tokenize --served-model nomic-ai/nomic-embed-text-v1.5 --batch-size 16 --credential-stdin >pipeline-output.txt 2>pipeline-stderr.txt; pipeline_code=\$?; nomic_key=''; unset nomic_key; printf '%s\n' \"\$pipeline_code\" >pipeline-exit-code.txt; exit \"\$pipeline_code\"" </dev/tty
remote_code=$?
set -e
emit "remote_execution_exit_code=$remote_code;raw_stderr_retained=false"

fetched_output="$work_root/pipeline-output.txt"
fetched_stderr="$work_root/pipeline-stderr.txt"
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/pipeline-output.txt" "$fetched_output" >/dev/null \
  || { emit 'script_85_live_document_pipeline_target=blocked;reason=output_fetch_failed'; exit 1; }
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/pipeline-stderr.txt" "$fetched_stderr" >/dev/null \
  || { emit 'script_85_live_document_pipeline_target=blocked;reason=diagnostic_fetch_failed'; exit 1; }
output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then output_contract=blocked; continue; fi
  emit "$line"
done <"$fetched_output"
pass_markers="$(grep -Fxc 'live_document_pipeline=pass' "$fetched_output" || true)"
blocked_markers="$(grep -Ec '^live_document_pipeline=blocked;' "$fetched_output" || true)"
emit "remote_output_contract=$output_contract;pass_markers=$pass_markers;blocked_markers=$blocked_markers"
if (( remote_code != 0 )) || [[ "$output_contract" != pass || "$pass_markers" != 1 || "$blocked_markers" != 0 ]]; then
  emit "script_85_live_document_pipeline_target=blocked;reason=remote_pipeline_failed;diagnostic_sha256=$(sha256sum "$fetched_stderr" | awk '{print $1}');diagnostic_bytes=$(stat -c '%s' "$fetched_stderr");raw_diagnostic_retained=false"
  exit 1
fi
grep -Fxq 'credential_retained=false;source_workspace_retained=false' "$fetched_output" \
  || { emit 'script_85_live_document_pipeline_target=blocked;reason=credential_or_workspace_contract_mismatch'; exit 1; }

fetched_root="$work_root/fetched"
mkdir -m 0700 -- "$fetched_root"
for name in stage-result.json normalized.json chunks.json embeddings.json; do
  timeout --foreground 180 scp "${ssh_args[@]}" "$target:$remote_root/workspace/$name" "$fetched_root/$name" >/dev/null \
    || { emit "script_85_live_document_pipeline_target=blocked;reason=artifact_fetch_failed_$name"; exit 1; }
done
listener_after="$(timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" "ss -H -ltn4 'sport = :8001' | sha256sum | awk '{print \$1}'")"
[[ "$listener_after" == "$listener_before" ]] || { emit 'script_85_live_document_pipeline_target=blocked;reason=operator_forward_listener_identity_changed'; exit 1; }

qualification_artifact="$work_root/live-document-pipeline-target.json"
evaluation_result="$work_root/evaluation.txt"
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B "$EVALUATOR" evaluate \
  --config-root "$CONFIG_ROOT" --source-root "$SOURCE_ROOT" \
  --request "$stage_root/workspace/stage-request.json" \
  --result "$fetched_root/stage-result.json" \
  --normalized "$fetched_root/normalized.json" \
  --chunks "$fetched_root/chunks.json" \
  --embeddings "$fetched_root/embeddings.json" \
  --output "$qualification_artifact" >"$evaluation_result"
grep -Fxq 'live_document_pipeline_target_evaluation=pass' "$evaluation_result" \
  || { emit 'script_85_live_document_pipeline_target=blocked;reason=local_artifact_evaluation_failed'; exit 1; }
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit 'milestone=live_document_pipeline;state=pass'

artifact_sha256="$(sha256sum "$qualification_artifact" | awk '{print $1}')"
artifact_path="$ARTIFACT_ROOT/live_document_pipeline_target_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] \
  || { emit 'script_85_live_document_pipeline_target=blocked;reason=artifact_path_exists'; exit 1; }
cp -- "$qualification_artifact" "$artifact_path"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$(stat -c '%s' "$artifact_path")"
emit "accepted_checksum=$checksum_path"
emit 'target_temporary_only=true;forwarding_changed=false;operator_forward_port_8001_after_test=listening;credential_retained=false;source_content_retained=false;vectors_retained=false'
emit "script_85_live_document_pipeline_target=pass;local_report=$report_path;next_gate=connect_live_pipeline_executable_to_configured_operator_ingestion_on_emceedanko"
chmod 0600 "$report_path" 2>/dev/null || true
