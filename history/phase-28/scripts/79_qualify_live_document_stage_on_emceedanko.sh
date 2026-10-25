#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify live Poppler extraction, normalization, structural chunking, and
#   Nomic document embedding on the application host with synthetic PDFs.
#
# Explicit execution from the repository root after forwarding Nomic port 8001:
#   bash ./phase-28-apisachi-tokuli/scripts/79_qualify_live_document_stage_on_emceedanko.sh --run

usage() {
  sed -n '3,10p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run                      Authorize the bounded target qualification.' \
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
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly TARGET_HELPER="$SCRIPT_DIR/produce-live-document-artifacts"
readonly CAPTURE="$SCRIPT_DIR/capture-pdf-extraction-observations.py"
readonly NORMALIZER="$SCRIPT_DIR/normalize-pdf-extraction.py"
readonly CHUNKER="$SCRIPT_DIR/create-structural-chunk-candidates.py"
readonly EMBEDDER="$SCRIPT_DIR/embed_document_candidates_via_endpoint.py"
readonly STAGE_EVALUATOR="$SCRIPT_DIR/evaluate_live_document_stage.py"
readonly EXTRACTION_EVALUATOR="$SCRIPT_DIR/evaluate_pdf_extraction.py"
readonly SOURCE_ROOT="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/anderson-upload"
readonly SOURCE_MANIFEST="$ISHIKAWA_ROOT/tests/fixtures/synthetic_pdf_sources.json"
readonly GROUND_TRUTH="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/evaluation/ground_truth.json"
readonly ACCEPTANCE_TRUTH="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/evaluation/extraction_acceptance_truth.json"
readonly ACCEPTED_NORMALIZED="$REPO_ROOT/local/artifacts/ishikawa/normalization/normalized_structural_units_20261019T214207Z.json"
readonly ACCEPTED_CHUNKS="$REPO_ROOT/local/artifacts/ishikawa/retrieval-gap-method-profile/structural_chunk_candidates_20261020T002645Z.json"
readonly ACCEPTED_EMBEDDINGS="$REPO_ROOT/local/artifacts/ishikawa/retrieval-gap-method-profile/measured_nomic_chunk_embeddings_20261020T002645Z.json"
readonly ACCEPTED_SCRIPT_74_REPORT="$REPO_ROOT/local/reports/ishikawa-configured-model-dependencies/configured_model_dependencies_20261020T163502Z_G2t0ym.txt"
readonly ACCEPTED_SCRIPT_78_REPORT="$REPO_ROOT/local/reports/ishikawa-document-producer-contract/document_producer_contract_20261020T175807Z_Gy3Erz.txt"
readonly SOURCE_MANIFEST_SHA256='456279482e50681c4c07cb41fbdff10f1ca8e9de458df4a99aa725f3ed94fd14'
readonly GROUND_TRUTH_SHA256='85e4bcf8e4d07bd786c8d2566957a4e75555084e5f3b11e58dd96af9af7c2ec8'
readonly ACCEPTANCE_TRUTH_SHA256='f83fd0bc8e0a25cd6bad35c5377b72a921205e7dd50565641fb58b229c635b1b'
readonly ACCEPTED_NORMALIZED_SHA256='736d619ac5a7e10f768bdb8b8f3f117cb52231f8dc2f4d186d52d96c8bd41e28'
readonly ACCEPTED_CHUNKS_SHA256='bc993ca0a417353f0d2313bcb2d1c94a1d526a513253139be71117bf88626bf3'
readonly ACCEPTED_EMBEDDINGS_SHA256='5bd79048bb59d53b6f6903eec9f4797955763a5fc12c064b17d19db89ba9d641'
readonly ACCEPTED_SCRIPT_74_REPORT_SHA256='374c87ad6888aee8120c996dfc307cefccb6baf684bb125c2a1fd9ec667e70e3'
readonly ACCEPTED_SCRIPT_78_REPORT_SHA256='101d55be24551858ad95627cac3a793d81d14ce1b626c6d4265a7f68c1065a09'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-live-document-stage"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/live-document-stage"

mapfile -t PYTHON_SOURCES < <(find "$PACKAGE_ROOT" -maxdepth 1 -type f -name '*.py' -print | sort)
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
for required in awk bash basename chmod cp date find grep install mkdir mktemp python3 rm scp sha256sum sort ssh stat tee timeout tr wc; do
  command -v "$required" >/dev/null 2>&1 || { printf 'BLOCKED: missing local command: %s\n' "$required" >&2; exit 2; }
done
(( ${#PYTHON_SOURCES[@]} > 0 )) || { printf 'BLOCKED: no Python application sources were found.\n' >&2; exit 2; }
for source in \
  "$TARGET_HELPER" "$CAPTURE" "$NORMALIZER" "$CHUNKER" "$EMBEDDER" \
  "$STAGE_EVALUATOR" "$EXTRACTION_EVALUATOR" "$TEST_RUNNER" \
  "$SOURCE_MANIFEST" "$GROUND_TRUTH" "$ACCEPTANCE_TRUTH" \
  "$ACCEPTED_NORMALIZED" "$ACCEPTED_CHUNKS" "$ACCEPTED_EMBEDDINGS" \
  "$ACCEPTED_SCRIPT_74_REPORT" "$ACCEPTED_SCRIPT_78_REPORT" \
  "${PYTHON_SOURCES[@]}" "${pdf_sources[@]}"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || { printf 'BLOCKED: a required Script 79 input is missing or unsafe.\n' >&2; exit 2; }
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || { printf 'BLOCKED: %s identity changed.\n' "$3" >&2; exit 2; }
}
check_sha256 "$SOURCE_MANIFEST" "$SOURCE_MANIFEST_SHA256" 'synthetic source manifest'
check_sha256 "$GROUND_TRUTH" "$GROUND_TRUTH_SHA256" 'held-out extraction truth'
check_sha256 "$ACCEPTANCE_TRUTH" "$ACCEPTANCE_TRUTH_SHA256" 'held-out extraction acceptance truth'
check_sha256 "$ACCEPTED_NORMALIZED" "$ACCEPTED_NORMALIZED_SHA256" 'accepted normalized artifact'
check_sha256 "$ACCEPTED_CHUNKS" "$ACCEPTED_CHUNKS_SHA256" 'accepted chunk artifact'
check_sha256 "$ACCEPTED_EMBEDDINGS" "$ACCEPTED_EMBEDDINGS_SHA256" 'accepted embedding artifact'
check_sha256 "$ACCEPTED_SCRIPT_74_REPORT" "$ACCEPTED_SCRIPT_74_REPORT_SHA256" 'accepted Script 74 report'
check_sha256 "$ACCEPTED_SCRIPT_78_REPORT" "$ACCEPTED_SCRIPT_78_REPORT_SHA256" 'accepted Script 78 report'
for fact in \
  'configured_model_dependency_evaluation=pass' \
  'target_changed=false;forwarding_changed=false;operator_forward_ports_after_test=listening;credentials_retained=false;generation_calls=0;tokenization_calls=2;embedding_calls=2' \
  'script_74_configured_model_dependencies=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_SCRIPT_74_REPORT" || { printf 'BLOCKED: an accepted Script 74 fact is absent.\n' >&2; exit 2; }
done
for fact in \
  'document_producer_contract_qualification=pass' \
  'local_tests=287;failures=0;errors=0' \
  'script_78_document_producer_contract=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_SCRIPT_78_REPORT" || { printf 'BLOCKED: an accepted Script 78 fact is absent.\n' >&2; exit 2; }
done

bash -n "${BASH_SOURCE[0]}" "$TARGET_HELPER" "$TEST_RUNNER"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$CAPTURE" "$NORMALIZER" "$CHUNKER" "$EMBEDDER" "$STAGE_EVALUATOR" "$EXTRACTION_EVALUATOR" "${PYTHON_SOURCES[@]}"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$CAPTURE" --self-test >/dev/null
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EMBEDDER" --self-test | grep -Fxq 'document_embedding_endpoint_producer_self_test=pass'
PYTHONDONTWRITEBYTECODE=1 python3 -B "$STAGE_EVALUATOR" --self-test | grep -Fxq 'live_document_stage_evaluator_self_test=pass'
for neutral_source in "$TARGET_HELPER" "$CAPTURE" "$NORMALIZER" "$CHUNKER" "$EMBEDDER"; do
  if grep -Eq '(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)' "$neutral_source" \
    || grep -Eiq 'phase[-_ ]?[0-9]+|Danko|org[_ -]?lab|Agent|repository' "$neutral_source"; then
    printf 'BLOCKED: development or environment jargon found in a neutral target source.\n' >&2
    exit 2
  fi
done

work_root="$(mktemp -d /tmp/ishikawa-script-79.XXXXXX)"
stage_root="$work_root/stage"
mkdir -m 0700 -p -- "$stage_root/payload/ishikawa" "$stage_root/payload/source"
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
  if [[ "$work_root" == /tmp/ishikawa-script-79.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  printf 'script_79_live_document_stage=blocked;reason=test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$test_result" | awk '{print $1}')" "$(stat -c '%s' "$test_result")" >&2
  exit 1
}
grep -Fq 'Ran 287 tests' "$test_result" || { printf 'script_79_live_document_stage=blocked;reason=test_count_mismatch\n' >&2; exit 1; }
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || { printf 'script_79_live_document_stage=blocked;reason=test_pass_marker_absent\n' >&2; exit 1; }

for source in "${PYTHON_SOURCES[@]}"; do install -m 0600 "$source" "$stage_root/payload/ishikawa/$(basename "$source")"; done
for source in "${pdf_sources[@]}"; do install -m 0600 "$source" "$stage_root/payload/source/$(basename "$source")"; done
for source in "$CAPTURE" "$NORMALIZER" "$CHUNKER" "$EMBEDDER" "$SOURCE_MANIFEST"; do install -m 0600 "$source" "$stage_root/$(basename "$source")"; done
install -m 0600 "$TARGET_HELPER" "$stage_root/produce-live-document-artifacts"
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$stage_root/payload" python3 -B -c 'import ishikawa.normalization, ishikawa.chunking'

payload_manifest="$stage_root/payload.sha256"
: >"$payload_manifest"
for source in "$stage_root"/payload/ishikawa/*.py; do printf '%s  payload/ishikawa/%s\n' "$(sha256sum "$source" | awk '{print $1}')" "$(basename "$source")" >>"$payload_manifest"; done
for source in "$stage_root"/payload/source/*.pdf; do printf '%s  payload/source/%s\n' "$(sha256sum "$source" | awk '{print $1}')" "$(basename "$source")" >>"$payload_manifest"; done
for name in capture-pdf-extraction-observations.py normalize-pdf-extraction.py create-structural-chunk-candidates.py embed_document_candidates_via_endpoint.py synthetic_pdf_sources.json; do
  printf '%s  %s\n' "$(sha256sum "$stage_root/$name" | awk '{print $1}')" "$name" >>"$payload_manifest"
done
manifest_sha256="$(sha256sum "$payload_manifest" | awk '{print $1}')"
manifest_entries="$(wc -l <"$payload_manifest" | tr -d ' ')"
helper_sha256="$(sha256sum "$TARGET_HELPER" | awk '{print $1}')"
embedder_sha256="$(sha256sum "$EMBEDDER" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$STAGE_EVALUATOR" | awk '{print $1}')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_live_document_stage_qualification_source' \
    'target_contact=false;database_contact=false;model_call=false;credential_read=false' \
    "script_sha256=$script_sha256;helper_sha256=$helper_sha256;embedder_sha256=$embedder_sha256;evaluator_sha256=$evaluator_sha256" \
    "payload_manifest_sha256=$manifest_sha256;payload_file_count=$manifest_entries" \
    "accepted_script_74_report_sha256=$ACCEPTED_SCRIPT_74_REPORT_SHA256;accepted_script_78_report_sha256=$ACCEPTED_SCRIPT_78_REPORT_SHA256" \
    'synthetic_documents=6;synthetic_pages=27;expected_chunk_candidates=126' \
    'transport_owner=operator;port_8001_required_preexisting=true;forwarding_managed_by_script=false' \
    'local_tests=287;failures=0;errors=0;staged_package_import=pass' \
    'script_79_live_document_stage_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/live_document_stage_${timestamp}_XXXXXX.txt")"
remote_root="/tmp/live-document-stage-$timestamp-$$"
emit 'purpose=qualify_live_poppler_normalization_chunking_and_nomic_document_embedding'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;helper_sha256=$helper_sha256;embedder_sha256=$embedder_sha256;evaluator_sha256=$evaluator_sha256"
emit "payload_manifest_sha256=$manifest_sha256;payload_file_count=$manifest_entries"
emit "accepted_script_74_report_sha256=$ACCEPTED_SCRIPT_74_REPORT_SHA256;accepted_script_78_report_sha256=$ACCEPTED_SCRIPT_78_REPORT_SHA256"
emit 'authorized_actions=stage_checksum_bound_synthetic_pdfs_run_native_poppler_normalization_and_chunking_prompt_for_nomic_key_call_preexisting_loopback_nomic_tokenizer_and_embedding_endpoints_fetch_and_evaluate_synthetic_artifacts_remove_target_temporary_files'
emit 'non_actions=no_forward_start_stop_or_change_no_sudo_no_package_service_firewall_or_configuration_change_no_database_contact_no_generation_model_call_no_organizational_content'
emit "selected_target=$target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version"
emit 'operator_expectation=forward_port_8001_before_script_ssh_key_passphrase_up_to_once_nomic_api_key_once_sudo_prompt=none;script_leaves_forwarding_running=true'
emit 'local_tests=287;failures=0;errors=0'

control_path="$work_root/ssh-control"
ssh_args=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto -o "ControlPath=$control_path" -o ControlPersist=1800)
if [[ -n "$identity_file" ]]; then ssh_args+=(-i "$identity_file" -o IdentitiesOnly=yes); fi
emit 'milestone=authentication;state=waiting_for_operator_if_prompted'
timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$target" >/dev/null 2>&1 || { emit 'script_79_live_document_stage=blocked;reason=ssh_master_start_failed'; exit 1; }
master_started=true
emit 'milestone=authentication;state=pass'
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root' && mkdir -m 0700 -p -- '$remote_root/payload/ishikawa' '$remote_root/payload/source'" >/dev/null \
  || { emit 'script_79_live_document_stage=blocked;reason=remote_temporary_directory_not_created'; exit 1; }
remote_created=true
timeout --foreground 180 scp "${ssh_args[@]}" "$stage_root"/produce-live-document-artifacts "$stage_root"/*.py "$stage_root"/synthetic_pdf_sources.json "$stage_root"/payload.sha256 "$target:$remote_root/" >/dev/null \
  || { emit 'script_79_live_document_stage=blocked;reason=root_payload_copy_failed'; exit 1; }
timeout --foreground 180 scp "${ssh_args[@]}" "$stage_root"/payload/ishikawa/*.py "$target:$remote_root/payload/ishikawa/" >/dev/null \
  || { emit 'script_79_live_document_stage=blocked;reason=python_payload_copy_failed'; exit 1; }
timeout --foreground 180 scp "${ssh_args[@]}" "$stage_root"/payload/source/*.pdf "$target:$remote_root/payload/source/" >/dev/null \
  || { emit 'script_79_live_document_stage=blocked;reason=source_payload_copy_failed'; exit 1; }
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && printf '%s  %s\n%s  %s\n' '$helper_sha256' produce-live-document-artifacts '$manifest_sha256' payload.sha256 | sha256sum --check --strict -" >/dev/null \
  || { emit 'script_79_live_document_stage=blocked;reason=target_outer_payload_hash_mismatch'; exit 1; }
emit 'milestone=target_payload_verification;state=pass'

emit 'milestone=live_document_stage;state=waiting_for_operator_nomic_credential'
set +e
timeout --foreground 1800 ssh -tt "${ssh_args[@]}" "$target" \
  "cd '$remote_root' && bash ./produce-live-document-artifacts '$expected_hostname' '$expected_os_version' '$remote_root' '$manifest_sha256' '$manifest_entries' '$SOURCE_MANIFEST_SHA256' > live-document-stage.txt" </dev/tty
remote_code=$?
set -e
emit "remote_execution_exit_code=$remote_code;raw_stderr_retained=false"
fetched_result="$work_root/live-document-stage.txt"
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/live-document-stage.txt" "$fetched_result" >/dev/null \
  || { emit 'script_79_live_document_stage=blocked;reason=result_fetch_failed'; exit 1; }

output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then output_contract=blocked; continue; fi
  emit "$line"
done <"$fetched_result"
emit "remote_output_contract=$output_contract"
required_fact_contract=pass
for fact in \
  'purpose=produce_live_document_artifacts_from_checksum_bound_synthetic_batch' \
  "host=$expected_hostname;os_version=$expected_os_version;architecture=amd64;python_version=" \
  'source_documents=6;source_pages=27;expected_chunk_candidates=126' \
  'operator_forward_port_8001_after_stage=listening;forwarding_changed=false' \
  'credential_retained=false;raw_text_logged=false;vectors_logged=false' \
  'database_contact=false;generation_model_contact=false' \
  'live_document_stage=pass'; do
  if [[ "$fact" == *'python_version=' ]]; then grep -Eq "^${fact//./\\.}3\\.12\\.[0-9]+$" "$fetched_result" || required_fact_contract=blocked
  else grep -Fxq "$fact" "$fetched_result" || required_fact_contract=blocked
  fi
done
grep -Eq '^tokenization_calls=[0-9]+;embedding_calls=[0-9]+;repeat_request_cardinality=16;repeat_max_abs_delta=[0-9.e+-]+;repeat_min_cosine_similarity=[0-9.e+-]+;repeat_max_cosine_distance=[0-9.e+-]+;repeat_within_tolerance=(true|false)$' "$fetched_result" \
  || required_fact_contract=blocked
pass_markers="$(grep -Fxc 'live_document_stage=pass' "$fetched_result" || true)"
blocked_markers="$(grep -Ec '^live_document_stage=blocked;' "$fetched_result" || true)"
emit "required_fact_contract=$required_fact_contract;pass_markers=$pass_markers;blocked_markers=$blocked_markers"
if (( remote_code != 0 )) || [[ "$output_contract" != pass || "$required_fact_contract" != pass || "$pass_markers" != 1 || "$blocked_markers" != 0 ]]; then
  emit 'milestone=live_document_stage;state=blocked'
  emit "script_79_live_document_stage=blocked;local_report=$report_path;next_gate=review_content_free_result_before_any_retry"
  exit 1
fi

fetched_root="$work_root/fetched"
mkdir -m 0700 -- "$fetched_root"
for name in extraction.tar normalized.json chunks.json embeddings.json artifacts.sha256; do
  timeout --foreground 180 scp "${ssh_args[@]}" "$target:$remote_root/output/$name" "$fetched_root/$name" >/dev/null \
    || { emit "script_79_live_document_stage=blocked;reason=${name//./_}_fetch_failed"; exit 1; }
done
(cd "$fetched_root" && sha256sum --check --strict artifacts.sha256 >/dev/null) \
  || { emit 'script_79_live_document_stage=blocked;reason=fetched_artifact_identity_mismatch'; exit 1; }

# Preserve the checksum-verified synthetic artifacts before local grading so a
# blocked comparison can be diagnosed without repeating model calls blindly.
artifact_directory="$ARTIFACT_ROOT/live_document_stage_${timestamp}"
[[ ! -e "$artifact_directory" && ! -L "$artifact_directory" ]] || { emit 'script_79_live_document_stage=blocked;reason=artifact_directory_exists'; exit 1; }
mkdir -- "$artifact_directory" \
  || { emit 'script_79_live_document_stage=blocked;reason=artifact_directory_create_failed'; exit 1; }
[[ -d "$artifact_directory" && ! -L "$artifact_directory" && -w "$artifact_directory" ]] \
  || { emit 'script_79_live_document_stage=blocked;reason=artifact_directory_unsafe'; exit 1; }
for name in extraction.tar normalized.json chunks.json embeddings.json artifacts.sha256; do
  cp -- "$fetched_root/$name" "$artifact_directory/$name" \
    || { emit "script_79_live_document_stage=blocked;reason=retained_${name//./_}_write_failed"; exit 1; }
done
if ! (
  cd "$artifact_directory"
  sha256sum extraction.tar normalized.json chunks.json embeddings.json >SHA256SUMS
); then
  emit 'script_79_live_document_stage=blocked;reason=retained_checksum_manifest_write_failed'
  exit 1
fi
emit "retained_synthetic_artifact_directory=$artifact_directory;artifact_files=6;retained_before_local_evaluation=true"
emit 'milestone=live_document_stage;state=pass'
emit 'milestone=local_held_out_evaluation;state=start'

extraction_result="$work_root/extraction-evaluation.txt"
diagnostic_path="$work_root/extraction-diagnostic.json"
set +e
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EXTRACTION_EVALUATOR" \
  --source-dir "$SOURCE_ROOT" \
  --source-manifest "$SOURCE_MANIFEST" \
  --ground-truth "$GROUND_TRUTH" \
  --acceptance-truth "$ACCEPTANCE_TRUTH" \
  --diagnostic-output "$diagnostic_path" \
  --archive "$fetched_root/extraction.tar" >"$extraction_result"
extraction_code=$?
set -e
if (( extraction_code != 0 )) || ! grep -Fxq 'pdf_extraction_evaluation=pass' "$extraction_result"; then
  if [[ -f "$diagnostic_path" && ! -L "$diagnostic_path" ]]; then
    emit "script_79_live_document_stage=blocked;reason=held_out_extraction_evaluation_failed;diagnostic_sha256=$(sha256sum "$diagnostic_path" | awk '{print $1}');diagnostic_bytes=$(stat -c '%s' "$diagnostic_path");raw_diagnostic_retained=false"
  else
    emit "script_79_live_document_stage=blocked;reason=held_out_extraction_evaluation_failed;diagnostic_sha256=$(sha256sum "$extraction_result" | awk '{print $1}');diagnostic_bytes=$(stat -c '%s' "$extraction_result");raw_diagnostic_retained=false"
  fi
  exit 1
fi
for fact in \
  'source_documents=6;source_pages=27;intentional_blank_pages=1' \
  'token_oracle_pages=27;layout_token_mismatch_pages=0;bbox_token_mismatch_pages=0' \
  'table_row_checks=4;table_cell_checks=16' \
  'form_field_pair_checks=8;checkbox_checks=10' \
  'pdf_extraction_evaluation=pass'; do
  grep -Fxq "$fact" "$extraction_result" || { emit 'script_79_live_document_stage=blocked;reason=held_out_extraction_fact_mismatch'; exit 1; }
  emit "$fact"
done

qualification_artifact="$work_root/live-document-stage-qualification.json"
stage_result="$work_root/stage-evaluation.txt"
set +e
PYTHONDONTWRITEBYTECODE=1 python3 -B "$STAGE_EVALUATOR" \
  --normalized "$fetched_root/normalized.json" \
  --chunks "$fetched_root/chunks.json" \
  --embeddings "$fetched_root/embeddings.json" \
  --accepted-normalized "$ACCEPTED_NORMALIZED" \
  --accepted-chunks "$ACCEPTED_CHUNKS" \
  --accepted-embeddings "$ACCEPTED_EMBEDDINGS" \
  --extraction "$fetched_root/extraction.tar" \
  --output "$qualification_artifact" >"$stage_result"
stage_evaluation_code=$?
set -e
stage_output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then stage_output_contract=blocked; continue; fi
  emit "$line"
done <"$stage_result"
if [[ -f "$qualification_artifact" && ! -L "$qualification_artifact" ]]; then
  cp -- "$qualification_artifact" "$artifact_directory/qualification.json" \
    || { emit 'script_79_live_document_stage=blocked;reason=retained_qualification_write_failed'; exit 1; }
  if ! (
    cd "$artifact_directory"
    sha256sum extraction.tar normalized.json chunks.json embeddings.json qualification.json >SHA256SUMS
  ); then
    emit 'script_79_live_document_stage=blocked;reason=retained_final_checksum_manifest_write_failed'
    exit 1
  fi
fi
if (( stage_evaluation_code != 0 )) || ! grep -Fxq 'live_document_stage_evaluation=pass' "$stage_result"; then
  emit "stage_output_contract=$stage_output_contract;retained_synthetic_artifact_directory=$artifact_directory"
  emit "script_79_live_document_stage=blocked;reason=semantic_evaluation_failed;diagnostic_sha256=$(sha256sum "$stage_result" | awk '{print $1}');diagnostic_bytes=$(stat -c '%s' "$stage_result");raw_diagnostic_retained=false"
  exit 1
fi
[[ "$stage_output_contract" == pass ]] || { emit 'script_79_live_document_stage=blocked;reason=semantic_evaluation_output_contract'; exit 1; }
repeat_within_tolerance="$(awk -F'[=;]' '$1 == "tokenization_calls" {print $14}' "$fetched_result")"
if [[ "$repeat_within_tolerance" != true ]]; then
  emit "script_79_live_document_stage=blocked;reason=repeat_embedding_tolerance_exceeded;retained_synthetic_artifact_directory=$artifact_directory"
  exit 1
fi
emit 'milestone=local_held_out_evaluation;state=pass'

emit "accepted_artifact_directory=$artifact_directory;artifact_files=7"
emit "accepted_qualification_sha256=$(sha256sum "$artifact_directory/qualification.json" | awk '{print $1}');accepted_qualification_bytes=$(stat -c '%s' "$artifact_directory/qualification.json")"
emit 'source_fixture=synthetic;organizational_content_retained=false;credential_retained=false'
emit "script_79_live_document_stage=pass;local_report=$report_path;next_gate=connect_live_document_stage_to_document_producer_and_operator_ingestion"
chmod 0600 "$report_path" 2>/dev/null || true
