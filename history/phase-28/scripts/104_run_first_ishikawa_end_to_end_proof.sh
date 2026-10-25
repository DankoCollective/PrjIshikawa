#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Run Ishikawa's first complete proof on the promoted application host.
#
# Mental model:
#   Bind to the accepted promotion and synthetic corpus, assemble one small
#   checksum manifest, transfer it through one attended SSH session, and let a
#   neutral target helper publish or reuse the corpus, start the stack, prove a
#   cited chat response, and stop the stack. Fetch only content-free evidence.
#
# Inputs or prerequisites:
#   Clean Script 103 evidence, the accepted six-document synthetic corpus,
#   pre-forwarded model ports 8000/8001 on the target, strict SSH trust,
#   attended sudo, and operator-supplied Gemma, Nomic, rag_ingest, and
#   rag_retrieval credentials.
#
# Outputs or artifact lane:
#   A local report under local/reports/ishikawa-first-runtime-proof, one
#   content-free JSON artifact and checksum, a retained searchable synthetic
#   corpus on the target, and a stopped boot-disabled Ishikawa stack.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/104_run_first_ishikawa_end_to_end_proof.sh --run

usage() {
  sed -n '3,29p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run                      Run the attended target proof.' \
    '  --target VALUE             SSH destination or configured SSH alias.' \
    '  --expected-hostname NAME   Exact target short hostname.' \
    '  --expected-os-version VER  Exact expected Ubuntu major.minor version.' \
    '  --identity-file PATH       Optional explicit SSH private key.' \
    '  --validate-only            Validate and assemble without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly TARGET_HELPER="$SCRIPT_DIR/run-first-ishikawa-proof"
readonly CHAT_PROOF="$SCRIPT_DIR/prove-ishikawa-chat-path.py"
readonly OPERATOR_CONFIG_ROOT="$PHASE_ROOT/Ishikawa/tests/fixtures/pipeline_writer"
readonly SOURCE_ROOT="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/anderson-upload"
readonly SYNTHETIC_MANIFEST="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/manifest.json"
readonly ACCEPTED_REPORT="$REPO_ROOT/local/reports/ishikawa-application-promotion/application_promotion_20261021T025244Z_D3WGT3.txt"
readonly ACCEPTED_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/application-promotion/application_promotion_qualification_20261021T025244Z.json"
readonly ACCEPTED_CHECKSUM="$ACCEPTED_ARTIFACT.sha256"
readonly ACCEPTED_REPORT_SHA256='1e4dec012f799fec5f4104e84d4d2757251b444a8659e92afb6182b016d0db46'
readonly ACCEPTED_ARTIFACT_SHA256='a2070983a61b0cd1e8c100bb3df895112a576e55d2892fcd6b308a7a0f04959b'
readonly ACCEPTED_CHECKSUM_SHA256='8b4b53d4d45011bbe79592401786e751eedee26fd47460c27d803975e9f51e9c'
readonly SYNTHETIC_MANIFEST_SHA256='c00a7a5dc6969ca5c22e0ac4adb5f2d8878439dd0b41adb46ccb079e6f866cfa'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-first-runtime-proof"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/first-runtime-proof"

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
    *) printf 'script_104_first_runtime_proof=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_104_first_runtime_proof=blocked;reason=mode_invalid\n' >&2
  exit 2
}
[[ "$target" =~ ^[A-Za-z0-9_@.:-]+$ ]] || {
  printf 'script_104_first_runtime_proof=blocked;reason=target_invalid\n' >&2
  exit 2
}
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || {
  printf 'script_104_first_runtime_proof=blocked;reason=expected_hostname_invalid\n' >&2
  exit 2
}
[[ "$expected_os_version" =~ ^[0-9]{2}\.[0-9]{2}$ ]] || {
  printf 'script_104_first_runtime_proof=blocked;reason=expected_os_version_invalid\n' >&2
  exit 2
}
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] || {
    printf 'script_104_first_runtime_proof=blocked;reason=identity_file_unsafe\n' >&2
    exit 2
  }
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" && -d "$ARTIFACT_ROOT" && ! -L "$ARTIFACT_ROOT" ]] || {
  printf 'script_104_first_runtime_proof=blocked;reason=local_output_directory_unsafe\n' >&2
  exit 2
}
report_path=''
if [[ "$run_authorized" == true ]]; then
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  report_path="$(mktemp "$REPORT_ROOT/first_runtime_proof_${timestamp}_XXXXXX.txt")"
fi
emit() {
  if [[ -n "$report_path" ]]; then
    printf '%s\n' "$1" | tee -a "$report_path"
  else
    printf '%s\n' "$1"
  fi
}
block() {
  emit "script_104_first_runtime_proof=blocked;reason=$1${report_path:+;local_report=$report_path}"
  exit 1
}

emit '[LOCAL] state=start'
emit 'purpose=run_first_complete_ishikawa_runtime_proof'
emit "selected_target=$target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version"
emit 'authorized_actions=authenticate_transfer_checksum_bound_synthetic_inputs_stage_synthetic_operator_configuration_publish_or_reuse_synthetic_corpus_start_test_and_stop_ishikawa_retain_content_free_evidence_remove_transfer_directory'
emit 'non_actions=no_package_install_no_image_pull_build_or_change_no_schema_migration_no_boot_enable_no_port_forward_change_no_firewall_change_no_secret_storage_no_raw_question_answer_excerpt_prompt_vector_or_model_response_retention'

for required in awk bash basename chmod cp date find grep install mkdir mktemp mv python3 rm scp sed sha256sum sort ssh stat tar tee timeout wc; do
  command -v "$required" >/dev/null 2>&1 || block "local_command_missing_$required"
done
for required_file in \
  "$TARGET_HELPER" "$CHAT_PROOF" \
  "$OPERATOR_CONFIG_ROOT/document_classes.yaml" \
  "$OPERATOR_CONFIG_ROOT/document_catalog.yaml" \
  "$OPERATOR_CONFIG_ROOT/ingestion_manifest.yaml" \
  "$SYNTHETIC_MANIFEST" \
  "$ACCEPTED_REPORT" "$ACCEPTED_ARTIFACT" "$ACCEPTED_CHECKSUM"; do
  [[ -f "$required_file" && ! -L "$required_file" && -r "$required_file" ]] || block 'required_input_unsafe'
done
mapfile -t pdf_sources < <(find "$SOURCE_ROOT" -maxdepth 1 -type f -name '*.pdf' -print | sort)
(( ${#pdf_sources[@]} == 6 )) || block 'synthetic_pdf_inventory_invalid'

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || block "$3_identity_changed"
}
check_sha256 "$ACCEPTED_REPORT" "$ACCEPTED_REPORT_SHA256" 'accepted_report'
check_sha256 "$ACCEPTED_ARTIFACT" "$ACCEPTED_ARTIFACT_SHA256" 'accepted_artifact'
check_sha256 "$ACCEPTED_CHECKSUM" "$ACCEPTED_CHECKSUM_SHA256" 'accepted_checksum'
check_sha256 "$SYNTHETIC_MANIFEST" "$SYNTHETIC_MANIFEST_SHA256" 'synthetic_manifest'
(
  cd -- "$(dirname -- "$ACCEPTED_ARTIFACT")"
  sha256sum --check --strict "$(basename -- "$ACCEPTED_CHECKSUM")" >/dev/null
) || block 'accepted_checksum_failed'
for fact in \
  'ishikawa_candidate_promotion=pass' \
  'active_payload_files=94;rollback_preserved=true;candidate_consumed=true' \
  'user_units=3;unit_identity=exact;services_started=false;boot_enabled=false' \
  'script_103_application_promotion=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_REPORT" || block 'accepted_report_contract_failed'
done

declare -A expected_pdf_sha256=(
  [31_SCH_2003.pdf]='00f4489faa8f15ed50ed3095c476fcdc9dd05852d56daf08bec33f0faafbaa02'
  [Form_TST9001.pdf]='96a91dab4d748cb5d80ae211bdf4aa435a8d679b0fc7dd3668cfdde066909000'
  [Governance_Manual_2005_Revision_3.pdf]='4cef995f8ae67b2184b52ddf59635ea5adf05d8df6e40ac110eff0c04357dd47'
  [OPS_17_CTL_2001.pdf]='32d3cc0361e4b2a26ea552c1e8e6013c6a1635f036ad759b50d0e29b447b0e79'
  [OPS_17_CTL_2002_RevA.pdf]='1c44ff8c5f1b30046e265b619a08e76a9c1139e15e6eb85164ebcf3655b6b442'
  [SOP_42_IR_2006.pdf]='962f8c6dd5835fc713cea6292ee1f30cb18d0abe6db38efe91f9a4ecea8d5175'
)
for pdf_source in "${pdf_sources[@]}"; do
  pdf_name="$(basename -- "$pdf_source")"
  [[ -n "${expected_pdf_sha256[$pdf_name]:-}" ]] || block 'synthetic_pdf_name_unexpected'
  check_sha256 "$pdf_source" "${expected_pdf_sha256[$pdf_name]}" 'synthetic_pdf'
done

bash -n "${BASH_SOURCE[0]}" "$TARGET_HELPER"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
  "$CHAT_PROOF"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$CHAT_PROOF" --self-test \
  | grep -Fxq 'ishikawa_chat_path_self_test=pass' || block 'chat_proof_self_test_failed'
for neutral_source in "$TARGET_HELPER" "$CHAT_PROOF"; do
  if grep -Eq '(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)' "$neutral_source" \
    || grep -Eiq 'phase[-_ ]?[0-9]+|Danko|org[_ -]?lab|Agent|repository|Script[[:space:]_-]*[0-9]+' "$neutral_source"; then
    block 'target_source_jargon_found'
  fi
done

work_root="$(mktemp -d /tmp/ishikawa-script-104.XXXXXX)"
remote_root=''
remote_created=false
master_started=false
artifact_path=''
checksum_path=''
artifact_committed=false
ssh_args=()
cleanup() {
  local status="$?" remote_cleanup_code=0 master_close_code=0
  trap - EXIT INT TERM
  set +e
  if [[ "$remote_created" == true && "$master_started" == true ]]; then
    timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
      "rm -rf -- '$remote_root' && test ! -e '$remote_root'" >/dev/null 2>&1 || remote_cleanup_code=$?
    if (( remote_cleanup_code == 0 )); then
      emit 'cleanup_remote_temporary_files=removed'
    else
      emit "cleanup_remote_temporary_files=review_required;exit_code=$remote_cleanup_code"
      status=1
    fi
  fi
  if [[ "$master_started" == true ]]; then
    timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1 || master_close_code=$?
    emit "cleanup_ssh_master_exit_code=$master_close_code"
    (( master_close_code == 0 )) || status=1
  fi
  if [[ "$artifact_committed" != true ]]; then
    [[ "$artifact_path" == "$ARTIFACT_ROOT"/first_runtime_proof_qualification_*.json ]] && rm -f -- "$artifact_path"
    [[ "$checksum_path" == "$ARTIFACT_ROOT"/first_runtime_proof_qualification_*.json.sha256 ]] && rm -f -- "$checksum_path"
  fi
  if [[ "$work_root" == /tmp/ishikawa-script-104.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  [[ -z "$report_path" ]] || chmod 0600 "$report_path" 2>/dev/null || true
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

stage_root="$work_root/package"
mkdir -m 0700 -p -- "$stage_root/operator" "$stage_root/source"
install -m 0600 -- "$OPERATOR_CONFIG_ROOT/document_classes.yaml" "$stage_root/operator/document_classes.yaml"
install -m 0600 -- "$OPERATOR_CONFIG_ROOT/document_catalog.yaml" "$stage_root/operator/document_catalog.yaml"
install -m 0600 -- "$OPERATOR_CONFIG_ROOT/ingestion_manifest.yaml" "$stage_root/operator/ingestion_manifest.yaml"
for pdf_source in "${pdf_sources[@]}"; do
  install -m 0600 -- "$pdf_source" "$stage_root/source/$(basename -- "$pdf_source")"
done
install -m 0700 -- "$TARGET_HELPER" "$stage_root/run-first-ishikawa-proof"
install -m 0600 -- "$CHAT_PROOF" "$stage_root/prove-ishikawa-chat-path.py"

payload_manifest="$stage_root/payload.sha256"
: >"$payload_manifest"
while IFS= read -r relative_path; do
  printf '%s  %s\n' "$(sha256sum "$stage_root/$relative_path" | awk '{print $1}')" "$relative_path" >>"$payload_manifest"
done < <(cd -- "$stage_root" && find operator source -type f -print | sort; printf '%s\n' prove-ishikawa-chat-path.py run-first-ishikawa-proof)
payload_sha256="$(sha256sum "$payload_manifest" | awk '{print $1}')"
payload_count="$(wc -l <"$payload_manifest" | tr -d ' ')"
[[ "$payload_count" == 11 ]] || block 'payload_file_count_invalid'

bundle="$work_root/ishikawa-first-runtime-proof.tar.gz"
tar -czf "$bundle" -C "$stage_root" .
bundle_sha256="$(sha256sum "$bundle" | awk '{print $1}')"
bundle_bytes="$(stat -c '%s' "$bundle")"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
helper_sha256="$(sha256sum "$TARGET_HELPER" | awk '{print $1}')"
chat_proof_sha256="$(sha256sum "$CHAT_PROOF" | awk '{print $1}')"
emit "script_sha256=$script_sha256;target_helper_sha256=$helper_sha256;chat_proof_sha256=$chat_proof_sha256"
emit "payload_manifest_sha256=$payload_sha256;payload_file_count=$payload_count;bundle_sha256=$bundle_sha256;bundle_bytes=$bundle_bytes"
emit "accepted_script_103_report_sha256=$ACCEPTED_REPORT_SHA256;accepted_script_103_artifact_sha256=$ACCEPTED_ARTIFACT_SHA256"
emit '[LOCAL] state=pass;synthetic_documents=6;chat_proof_self_test=pass'

if [[ "$validate_only" == true ]]; then
  emit 'target_contact=false;database_changed=false;service_changed=false;model_contact=false;credential_read=false'
  emit 'script_104_first_runtime_proof_source=pass'
  exit 0
fi

ssh_resolution_args=()
if [[ -n "$identity_file" ]]; then
  ssh_resolution_args=(-i "$identity_file" -o IdentitiesOnly=yes)
fi
selected_remote_user="$(ssh -G "${ssh_resolution_args[@]}" "$target" 2>/dev/null | awk '$1 == "user" {print $2; exit}')"
[[ "$selected_remote_user" =~ ^[A-Za-z_][A-Za-z0-9._-]*$ ]] || block 'ssh_remote_user_unresolved'
emit "selected_ssh_destination=$target;selected_remote_user=$selected_remote_user;expected_target_hostname=$expected_hostname"
emit 'operator_expectation=ssh_key_passphrase_up_to_once_target_sudo_password_if_cache_cold_four_hidden_runtime_credentials;estimated_duration_minutes=5-15'
emit '[AUTH] state=waiting_for_operator_if_prompted'
control_path="$work_root/cm-%C"
ssh_args=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto -o "ControlPath=$control_path" -o ControlPersist=3600)
if [[ -n "$identity_file" ]]; then
  ssh_args+=(-i "$identity_file" -o IdentitiesOnly=yes)
fi
timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$target" >/dev/null 2>&1 || block 'ssh_master_start_failed'
master_started=true
emit '[AUTH] state=pass'

remote_root="/tmp/ishikawa-first-runtime-proof-$timestamp-$$"
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" >/dev/null \
  || block 'remote_temporary_directory_not_created'
remote_created=true

emit '[TRANSFER] state=start'
timeout --foreground 180 scp "${ssh_args[@]}" "$bundle" "$target:$remote_root/package.tar.gz" >/dev/null \
  || block 'payload_transfer_failed'
timeout --foreground 120 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && printf '%s  package.tar.gz\n' '$bundle_sha256' | sha256sum --check --strict - >/dev/null && tar -xzf package.tar.gz && printf '%s  payload.sha256\n%s  run-first-ishikawa-proof\n%s  prove-ishikawa-chat-path.py\n' '$payload_sha256' '$helper_sha256' '$chat_proof_sha256' | sha256sum --check --strict - >/dev/null && sha256sum --check --strict payload.sha256 >/dev/null && chmod 0700 run-first-ishikawa-proof" >/dev/null \
  || block 'target_payload_verification_failed'
emit "[TRANSFER] state=pass;transferred_bytes=$bundle_bytes;reused_bytes=0"

emit '[TARGET] state=start;credentials_will_be_requested_on_target_terminal'
set +e
timeout --foreground 3600 ssh -tt "${ssh_args[@]}" "$target" \
  "cd '$remote_root' && set -o pipefail && bash ./run-first-ishikawa-proof '$expected_hostname' '$expected_os_version' '$remote_root' '$payload_sha256' '$payload_count' | tee qualification-result.txt >/dev/null; exit \${PIPESTATUS[0]}" </dev/tty
remote_code=$?
set -e
emit "remote_execution_exit_code=$remote_code;raw_remote_output_retained=false"

fetched_result="$work_root/qualification-result.txt"
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/qualification-result.txt" "$fetched_result" >/dev/null \
  || block 'result_fetch_failed'
output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]]; then
    output_contract=blocked
    continue
  fi
  if [[ "$line" =~ ^\[[A-Z]+\][[:space:]][A-Za-z0-9_.=-]+(\;[A-Za-z0-9_.=-]+)*$ ]] \
    || [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then
    emit "$line"
  else
    output_contract=blocked
  fi
done <"$fetched_result"
emit "remote_output_contract=$output_contract"

if (( remote_code != 0 )); then
  emit '[TARGET] state=blocked'
  block 'target_runtime_proof_failed'
fi
[[ "$output_contract" == pass ]] || block 'remote_output_contract_failed'
for fact in \
  "target_hostname=$expected_hostname;os_id=ubuntu;os_version=$expected_os_version;architecture=amd64" \
  'synthetic_corpus=active;ingestion_action=' \
  'runtime_path=nextjs_to_retrieval_to_postgresql_nomic_gemma;chat_status=answered;citation_closure=pass' \
  'stack_final_state=stopped;boot_enabled=false;forwarding_changed=false' \
  'source_documents=retained;database_publication=retained;raw_chat_content_retained=false;credential_values_retained=false' \
  'durable_target_receipt=HOME/Documents/Ishikawa/state/reports/qualification/first-runtime-proof.txt' \
  'ishikawa_first_runtime_proof=pass'; do
  grep -Fq "$fact" "$fetched_result" || block 'remote_result_contract_failed'
done
grep -Eq '^synthetic_corpus=active;ingestion_action=(published_new|reused_existing);documents=6;pages=27;chunks=126;citations=126;embeddings=126$' "$fetched_result" \
  || block 'remote_corpus_inventory_invalid'

fetched_artifact="$work_root/chat-proof.json"
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/chat-proof.json" "$fetched_artifact" >/dev/null \
  || block 'chat_artifact_fetch_failed'
artifact_evaluation="$work_root/chat-artifact-evaluation.txt"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$CHAT_PROOF" --validate-artifact "$fetched_artifact" >"$artifact_evaluation" \
  || block 'chat_artifact_validation_failed'
grep -Eq '^ishikawa_chat_path_artifact=pass;http_status=200;status=answered;sources=[0-9]+;excerpts=[0-9]+;claims=[0-9]+;citations=[0-9]+;raw_content_retained=false$' "$artifact_evaluation" \
  || block 'chat_artifact_marker_invalid'
while IFS= read -r line; do emit "$line"; done <"$artifact_evaluation"

artifact_sha256="$(sha256sum "$fetched_artifact" | awk '{print $1}')"
artifact_path="$ARTIFACT_ROOT/first_runtime_proof_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || block 'artifact_path_exists'
cp -- "$fetched_artifact" "$artifact_path"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true
(
  cd -- "$ARTIFACT_ROOT"
  sha256sum --check --strict "$(basename -- "$checksum_path")" >/dev/null
) || block 'local_artifact_checksum_failed'
artifact_committed=true

emit '[TARGET] state=pass;stack_final_state=stopped'
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$(stat -c '%s' "$artifact_path");accepted_checksum=$checksum_path"
emit 'target_persistent_changes=synthetic_source_configuration_and_searchable_database_publication;services_running=false;boot_enabled=false'
emit "script_104_first_runtime_proof=pass;local_report=$report_path;next_gate=review_first_runtime_proof_and_run_operator_ui_acceptance"
