#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify native Poppler PDF extraction against all six synthetic PDFs and
#   held-out structure truth without sending that truth to the target host.
#
# Explicit execution from the repository root:
#   bash ./phase-28-apisachi-tokuli/scripts/25_qualify_pdf_extraction_on_emceedanko.sh --run

usage() {
  sed -n '3,9p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run                      Explicitly authorize target qualification.' \
    '  --target VALUE             SSH destination or configured SSH alias.' \
    '  --expected-hostname NAME   Exact target short hostname.' \
    '  --expected-os-version VER  Exact expected Ubuntu major.minor version.' \
    '  --identity-file PATH       Optional explicit SSH private key.' \
    '  --report-root PATH         Absolute local result directory.' \
    '  --artifact-root PATH       Absolute local extraction-artifact directory.' \
    '  --validate-only            Validate sources without target contact.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly TARGET_CAPTURE="$SCRIPT_DIR/capture-pdf-extraction-observations.py"
readonly LOCAL_EVALUATOR="$SCRIPT_DIR/evaluate_pdf_extraction.py"
readonly SOURCE_DIR="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/anderson-upload"
readonly SOURCE_MANIFEST="$PHASE_ROOT/Ishikawa/tests/fixtures/synthetic_pdf_sources.json"
readonly CORPUS_MANIFEST="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/manifest.json"
readonly GROUND_TRUTH="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/evaluation/ground_truth.json"
readonly ACCEPTANCE_TRUTH="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/evaluation/extraction_acceptance_truth.json"
readonly ACCEPTED_TARGET_REPORT="$REPO_ROOT/local/reports/application-host-inventory/application_host_inventory_20261019T014205Z_hQirh3.txt"
readonly ACCEPTED_TARGET_REPORT_SHA256='a02fd0767b5db8e9584abfd8e720bb6dd039552fa45e301001191f795e60f69b'
readonly CORPUS_MANIFEST_SHA256='c00a7a5dc6969ca5c22e0ac4adb5f2d8878439dd0b41adb46ccb079e6f866cfa'
readonly GROUND_TRUTH_SHA256='85e4bcf8e4d07bd786c8d2566957a4e75555084e5f3b11e58dd96af9af7c2ec8'
readonly SOURCE_MANIFEST_SHA256='456279482e50681c4c07cb41fbdff10f1ca8e9de458df4a99aa725f3ed94fd14'
readonly ACCEPTANCE_TRUTH_SHA256='f83fd0bc8e0a25cd6bad35c5377b72a921205e7dd50565641fb58b229c635b1b'
readonly DEFAULT_REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-pdf-extraction-qualification"
readonly DEFAULT_ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/pdf-extraction-qualification"

source_files=(
  "$SOURCE_DIR/31_SCH_2003.pdf"
  "$SOURCE_DIR/Form_TST9001.pdf"
  "$SOURCE_DIR/Governance_Manual_2005_Revision_3.pdf"
  "$SOURCE_DIR/OPS_17_CTL_2001.pdf"
  "$SOURCE_DIR/OPS_17_CTL_2002_RevA.pdf"
  "$SOURCE_DIR/SOP_42_IR_2006.pdf"
)

target="${APPLICATION_HOST_TARGET:-DankoSurface_EmceeDanko}"
expected_hostname="${APPLICATION_HOST_EXPECTED_HOSTNAME:-EmceeDanko}"
expected_os_version="${APPLICATION_HOST_EXPECTED_OS_VERSION:-24.04}"
identity_file="${APPLICATION_HOST_IDENTITY_FILE:-}"
report_root="$DEFAULT_REPORT_ROOT"
artifact_root="$DEFAULT_ARTIFACT_ROOT"
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
    --artifact-root) artifact_root="${2:-}"; shift 2 ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'ERROR: unsupported argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$target" =~ ^[A-Za-z0-9_@.:-]+$ ]] || { printf 'BLOCKED: invalid SSH target or alias.\n' >&2; exit 2; }
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || { printf 'BLOCKED: invalid expected hostname.\n' >&2; exit 2; }
[[ "$expected_os_version" =~ ^[0-9]{2}\.[0-9]{2}$ ]] || { printf 'BLOCKED: invalid expected Ubuntu version.\n' >&2; exit 2; }
for destination in "$report_root" "$artifact_root"; do
  [[ "$destination" == /* && ! -L "$destination" ]] || { printf 'BLOCKED: local output roots must be absolute and not symlinks.\n' >&2; exit 2; }
done
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] || { printf 'BLOCKED: identity file is unsafe.\n' >&2; exit 2; }
fi
for source in "$TARGET_CAPTURE" "$LOCAL_EVALUATOR" "$SOURCE_MANIFEST" "$CORPUS_MANIFEST" "$GROUND_TRUTH" "$ACCEPTANCE_TRUTH" "$ACCEPTED_TARGET_REPORT" "${source_files[@]}"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || { printf 'BLOCKED: required Script 25 source is missing or unsafe.\n' >&2; exit 2; }
done
for required in awk bash basename chmod cp date grep mkdir mktemp python3 rm scp sha256sum ssh stat tee timeout tr wc; do
  command -v "$required" >/dev/null 2>&1 || { printf 'BLOCKED: missing local command: %s\n' "$required" >&2; exit 2; }
done

python3 -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' "$TARGET_CAPTURE" "$LOCAL_EVALUATOR"
python3 "$TARGET_CAPTURE" --self-test
python3 "$LOCAL_EVALUATOR" --self-test
if grep -Eiq 'phase[-_ ]?[0-9]+|(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)|Danko|org[_ -]?lab|Agent|repository' "$TARGET_CAPTURE"; then
  printf 'BLOCKED: development or environment jargon found in the neutral target source.\n' >&2
  exit 2
fi

[[ "$(sha256sum "$ACCEPTED_TARGET_REPORT" | awk '{print $1}')" == "$ACCEPTED_TARGET_REPORT_SHA256" ]] || { printf 'BLOCKED: accepted target inventory checksum mismatch.\n' >&2; exit 2; }
[[ "$(sha256sum "$CORPUS_MANIFEST" | awk '{print $1}')" == "$CORPUS_MANIFEST_SHA256" ]] || { printf 'BLOCKED: synthetic corpus manifest checksum mismatch.\n' >&2; exit 2; }
[[ "$(sha256sum "$GROUND_TRUTH" | awk '{print $1}')" == "$GROUND_TRUTH_SHA256" ]] || { printf 'BLOCKED: synthetic ground truth checksum mismatch.\n' >&2; exit 2; }
[[ "$(sha256sum "$SOURCE_MANIFEST" | awk '{print $1}')" == "$SOURCE_MANIFEST_SHA256" ]] || { printf 'BLOCKED: PDF source manifest checksum mismatch.\n' >&2; exit 2; }
[[ "$(sha256sum "$ACCEPTANCE_TRUTH" | awk '{print $1}')" == "$ACCEPTANCE_TRUTH_SHA256" ]] || { printf 'BLOCKED: extraction acceptance truth checksum mismatch.\n' >&2; exit 2; }
for accepted_fact in \
  'hostname_match=true' \
  'os_version=24.04' \
  'machine=x86_64' \
  'dpkg_architecture=amd64' \
  'pdftotext_version=pdftotext_version_24.02.0' \
  'pdfinfo_version=pdfinfo_version_24.02.0' \
  'package_poppler_utils=install_ok_installed;installed_version=24.02.0-1ubuntu9.10;candidate_version=24.02.0-1ubuntu9.10' \
  'application_host_inventory=pass'; do
  grep -Fxq "$accepted_fact" "$ACCEPTED_TARGET_REPORT" || { printf 'BLOCKED: required accepted target inventory fact is absent.\n' >&2; exit 2; }
done

fixture_result="$(python3 "$LOCAL_EVALUATOR" \
  --validate-fixtures \
  --source-dir "$SOURCE_DIR" \
  --source-manifest "$SOURCE_MANIFEST" \
  --ground-truth "$GROUND_TRUTH" \
  --acceptance-truth "$ACCEPTANCE_TRUTH")"
[[ "$fixture_result" == 'synthetic_pdf_fixture_validation=pass;documents=6;pages=27' ]] || { printf 'BLOCKED: synthetic PDF fixture validation failed.\n' >&2; exit 2; }

work_root="$(mktemp -d /tmp/pdf-extraction-script-25.XXXXXX)"
payload_manifest="$work_root/payload.sha256"
: >"$payload_manifest"
printf '%s  %s\n' "$(sha256sum "$TARGET_CAPTURE" | awk '{print $1}')" 'capture-pdf-extraction-observations.py' >>"$payload_manifest"
printf '%s  %s\n' "$SOURCE_MANIFEST_SHA256" 'synthetic_pdf_sources.json' >>"$payload_manifest"
for source in "${source_files[@]}"; do
  printf '%s  input/%s\n' "$(sha256sum "$source" | awk '{print $1}')" "$(basename "$source")" >>"$payload_manifest"
done
payload_manifest_sha256="$(sha256sum "$payload_manifest" | awk '{print $1}')"
capture_sha256="$(sha256sum "$TARGET_CAPTURE" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$LOCAL_EVALUATOR" | awk '{print $1}')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'pdf_extraction_qualification_source=pass' \
    'target_contact=false;source_documents=6;source_pages=27;held_out_truth_transferred=false' \
    "script_sha256=$script_sha256" \
    "capture_sha256=$capture_sha256" \
    "evaluator_sha256=$evaluator_sha256" \
    "payload_manifest_sha256=$payload_manifest_sha256" \
    "payload_file_count=$(wc -l <"$payload_manifest" | tr -d ' ')" \
    "source_manifest_sha256=$SOURCE_MANIFEST_SHA256" \
    "ground_truth_sha256=$GROUND_TRUTH_SHA256" \
    "acceptance_truth_sha256=$ACCEPTANCE_TRUTH_SHA256" \
    "accepted_target_report_sha256=$ACCEPTED_TARGET_REPORT_SHA256"
  rm -rf -- "$work_root"
  exit 0
fi

[[ "$run_authorized" == true ]] || { rm -rf -- "$work_root"; printf 'BLOCKED: Script 25 requires the explicit --run argument.\n' >&2; exit 2; }

mkdir -p -- "$report_root" "$artifact_root"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_root/pdf_extraction_qualification_${timestamp}_XXXXXX.txt")"
remote_root="/tmp/pdf-extraction-qualification-$timestamp-$$"
remote_created=false
master_started=false
ssh_args=()

emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
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
  if [[ "$work_root" == /tmp/pdf-extraction-script-25.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

emit 'purpose=qualify_native_pdf_extraction_with_synthetic_corpus'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;capture_sha256=$capture_sha256;evaluator_sha256=$evaluator_sha256"
emit "payload_manifest_sha256=$payload_manifest_sha256;source_manifest_sha256=$SOURCE_MANIFEST_SHA256"
emit "ground_truth_sha256=$GROUND_TRUTH_SHA256;acceptance_truth_sha256=$ACCEPTANCE_TRUTH_SHA256"
emit "accepted_target_report_sha256=$ACCEPTED_TARGET_REPORT_SHA256;corpus_manifest_sha256=$CORPUS_MANIFEST_SHA256"
emit 'authorized_actions=stage_verified_synthetic_pdfs_run_bounded_poppler_capture_fetch_synthetic_outputs_grade_against_local_held_out_truth_write_local_report_and_artifact_remove_target_temporary_files'
emit 'non_actions=no_package_change_no_database_or_service_change_no_model_call_no_organizational_document_read_no_secret_processing_no_held_out_truth_transfer'
emit "selected_target=$target;expected_hostname=$expected_hostname;expected_os_version=$expected_os_version"
emit 'operator_expectation=ssh_key_passphrase_up_to_once;no_sudo_prompt;no_application_secret_prompt'
emit 'synthetic_fixture_validation=pass;documents=6;pages=27'

control_path="$work_root/ssh-control"
ssh_args=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto -o "ControlPath=$control_path" -o ControlPersist=1800)
if [[ -n "$identity_file" ]]; then ssh_args+=(-i "$identity_file" -o IdentitiesOnly=yes); fi

emit 'milestone=authentication;state=waiting_for_operator_if_prompted'
timeout --foreground 60 ssh "${ssh_args[@]}" -Nf "$target" >"$work_root/master.stdout" 2>"$work_root/master.stderr" || { emit 'pdf_extraction_qualification_wrapper=blocked;reason=ssh_master_start_failed'; exit 1; }
master_started=true
emit 'milestone=authentication;state=pass'
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root' && mkdir -m 0700 -- '$remote_root/input'" \
  >"$work_root/create.stdout" 2>"$work_root/create.stderr" || { emit 'pdf_extraction_qualification_wrapper=blocked;reason=remote_temporary_directory_not_created'; exit 1; }
remote_created=true

timeout --foreground 120 scp "${ssh_args[@]}" "$TARGET_CAPTURE" "$SOURCE_MANIFEST" "$payload_manifest" "$target:$remote_root/" >"$work_root/scp-root.stdout" 2>"$work_root/scp-root.stderr" || { emit 'pdf_extraction_qualification_wrapper=blocked;reason=root_payload_copy_failed'; exit 1; }
timeout --foreground 120 scp "${ssh_args[@]}" "${source_files[@]}" "$target:$remote_root/input/" >"$work_root/scp-pdf.stdout" 2>"$work_root/scp-pdf.stderr" || { emit 'pdf_extraction_qualification_wrapper=blocked;reason=synthetic_pdf_copy_failed'; exit 1; }
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && sha256sum --check --strict payload.sha256" \
  >"$work_root/hash.stdout" 2>"$work_root/hash.stderr" || { emit 'pdf_extraction_qualification_wrapper=blocked;reason=target_payload_hash_mismatch'; exit 1; }
emit 'milestone=target_payload_verification;state=pass'

emit 'milestone=target_pdf_extraction;state=start'
set +e
timeout --foreground 900 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && umask 077 && python3 ./capture-pdf-extraction-observations.py --expected-hostname '$expected_hostname' --expected-os-version '$expected_os_version' --input-dir '$remote_root/input' --source-manifest '$remote_root/synthetic_pdf_sources.json' --output-dir '$remote_root/output' --archive '$remote_root/pdf-extraction-observations.tar' > '$remote_root/capture-result.txt'"
remote_code=$?
set -e
emit "remote_execution_exit_code=$remote_code;raw_stderr_retained=false"

fetched_result="$work_root/capture-result.txt"
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/capture-result.txt" "$fetched_result" >"$work_root/fetch-result.stdout" 2>"$work_root/fetch-result.stderr" || { emit 'pdf_extraction_qualification_wrapper=blocked;reason=result_fetch_failed'; exit 1; }

output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then output_contract=blocked; continue; fi
  emit "$line"
done <"$fetched_result"
emit "remote_output_contract=$output_contract"

target_fact_contract=pass
for fact in \
  'purpose=capture_pdf_extraction_observations' \
  "host=$expected_hostname;os_version=$expected_os_version;architecture=amd64" \
  'poppler_package_version=24.02.0-1ubuntu9.10;pdfinfo_version=24.02.0;pdftotext_version=24.02.0' \
  'source_documents=6;source_pages=27;observed_blank_pages=1' \
  'repeatability=pass;document_failures=0' \
  'pdf_extraction_capture=pass'; do
  [[ "$(grep -Fxc "$fact" "$fetched_result" || true)" == 1 ]] || target_fact_contract=blocked
done
archive_markers="$(grep -Ec '^archive_sha256=[0-9a-f]{64};archive_bytes=[0-9]+$' "$fetched_result" || true)"
pass_markers="$(grep -Fxc 'pdf_extraction_capture=pass' "$fetched_result" || true)"
blocked_markers="$(grep -Ec '^pdf_extraction_capture=blocked;' "$fetched_result" || true)"
emit "target_fact_contract=$target_fact_contract;archive_markers=$archive_markers;pass_markers=$pass_markers;blocked_markers=$blocked_markers"
if (( remote_code != 0 )) || [[ "$output_contract" != pass || "$target_fact_contract" != pass || "$archive_markers" != 1 || "$pass_markers" != 1 || "$blocked_markers" != 0 ]]; then
  emit 'milestone=target_pdf_extraction;state=blocked'
  emit "pdf_extraction_qualification_wrapper=blocked;local_report=$report_path;next_gate=inspect_content_free_capture_result_before_any_retry"
  exit 1
fi
emit 'milestone=target_pdf_extraction;state=pass'

fetched_archive="$work_root/pdf-extraction-observations.tar"
timeout --foreground 120 scp "${ssh_args[@]}" "$target:$remote_root/pdf-extraction-observations.tar" "$fetched_archive" >"$work_root/fetch-archive.stdout" 2>"$work_root/fetch-archive.stderr" || { emit 'pdf_extraction_qualification_wrapper=blocked;reason=archive_fetch_failed'; exit 1; }
expected_archive_sha256="$(awk -F'[=;]' '$1 == "archive_sha256" {print $2}' "$fetched_result")"
expected_archive_bytes="$(awk -F'[=;]' '$1 == "archive_sha256" {print $4}' "$fetched_result")"
actual_archive_sha256="$(sha256sum "$fetched_archive" | awk '{print $1}')"
actual_archive_bytes="$(stat -c '%s' "$fetched_archive")"
[[ "$actual_archive_sha256" == "$expected_archive_sha256" && "$actual_archive_bytes" == "$expected_archive_bytes" ]] || { emit 'pdf_extraction_qualification_wrapper=blocked;reason=fetched_archive_identity_mismatch'; exit 1; }
emit "fetched_archive_sha256=$actual_archive_sha256;fetched_archive_bytes=$actual_archive_bytes"

# Retain the checksum-verified synthetic capture before grading. If the local
# held-out evaluator blocks, this artifact is the evidence needed to diagnose
# the grading or extraction discrepancy without repeating target execution.
artifact_path="$artifact_root/pdf_extraction_observations_${timestamp}.tar"
checksum_path="$artifact_path.sha256"
diagnostic_path="$artifact_root/pdf_extraction_diagnostic_${timestamp}.json"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" && ! -e "$diagnostic_path" && ! -L "$diagnostic_path" ]] || { emit 'pdf_extraction_qualification_wrapper=blocked;reason=local_artifact_path_exists'; exit 1; }
# The repository may reside on a Windows-mounted filesystem where Unix mode
# changes are unsupported. These retained files contain only synthetic data,
# so copy them without making mode emulation an acceptance dependency.
cp -- "$fetched_archive" "$artifact_path"
[[ "$(sha256sum "$artifact_path" | awk '{print $1}')" == "$actual_archive_sha256" ]] || { emit 'pdf_extraction_qualification_wrapper=blocked;reason=retained_archive_identity_mismatch'; exit 1; }
printf '%s  %s\n' "$actual_archive_sha256" "$(basename "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true
emit "retained_synthetic_artifact_sha256=$actual_archive_sha256;retained_synthetic_artifact_bytes=$actual_archive_bytes"
emit "retained_synthetic_artifact=$artifact_path;retained_checksum=$checksum_path"

emit 'milestone=held_out_local_evaluation;state=start'
evaluation_result="$work_root/evaluation-result.txt"
set +e
python3 "$LOCAL_EVALUATOR" \
  --source-dir "$SOURCE_DIR" \
  --source-manifest "$SOURCE_MANIFEST" \
  --ground-truth "$GROUND_TRUTH" \
  --acceptance-truth "$ACCEPTANCE_TRUTH" \
  --diagnostic-output "$diagnostic_path" \
  --archive "$fetched_archive" >"$evaluation_result"
evaluation_code=$?
set -e
evaluation_output_contract=pass
while IFS= read -r line; do
  if (( ${#line} > 2048 )) || [[ "$line" == *$'\t'* ]] || ! [[ "$line" =~ ^[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+(\;[A-Za-z0-9_.-]+=[A-Za-z0-9_.:+@/~,-]+)*$ ]]; then evaluation_output_contract=blocked; continue; fi
  emit "$line"
done <"$evaluation_result"
emit "evaluation_exit_code=$evaluation_code;evaluation_output_contract=$evaluation_output_contract"

evaluation_fact_contract=pass
for fact in \
  'purpose=evaluate_synthetic_pdf_extraction' \
  'source_documents=6;source_pages=27;intentional_blank_pages=1' \
  'token_oracle_pages=27;layout_token_mismatch_pages=0;bbox_token_mismatch_pages=0' \
  'heading_checks=27;ordered_phrase_checks=40;repeated_furniture_page_checks=16' \
  'table_row_checks=4;table_cell_checks=16' \
  'form_field_pair_checks=8;checkbox_checks=10' \
  'pdf_extraction_evaluation=pass'; do
  [[ "$(grep -Fxc "$fact" "$evaluation_result" || true)" == 1 ]] || evaluation_fact_contract=blocked
done
evaluation_pass_markers="$(grep -Fxc 'pdf_extraction_evaluation=pass' "$evaluation_result" || true)"
evaluation_blocked_markers="$(grep -Ec '^pdf_extraction_evaluation=blocked;' "$evaluation_result" || true)"
emit "evaluation_fact_contract=$evaluation_fact_contract;evaluation_pass_markers=$evaluation_pass_markers;evaluation_blocked_markers=$evaluation_blocked_markers"
if (( evaluation_code != 0 )) || [[ "$evaluation_output_contract" != pass || "$evaluation_fact_contract" != pass || "$evaluation_pass_markers" != 1 || "$evaluation_blocked_markers" != 0 ]]; then
  if [[ -f "$diagnostic_path" && ! -L "$diagnostic_path" ]]; then
    emit "protected_diagnostic_sha256=$(sha256sum "$diagnostic_path" | awk '{print $1}');protected_diagnostic_bytes=$(stat -c '%s' "$diagnostic_path")"
    emit "protected_diagnostic=$diagnostic_path"
  else
    emit 'protected_diagnostic=unavailable'
  fi
  emit 'milestone=held_out_local_evaluation;state=blocked'
  emit "pdf_extraction_qualification_wrapper=blocked;local_report=$report_path;next_gate=inspect_retained_synthetic_artifact_and_protected_diagnostic_before_any_retry"
  exit 1
fi
emit 'milestone=held_out_local_evaluation;state=pass'

emit "accepted_artifact_sha256=$actual_archive_sha256;accepted_artifact_bytes=$actual_archive_bytes"
emit "accepted_artifact=$artifact_path;accepted_checksum=$checksum_path"
emit "pdf_extraction_qualification_wrapper=pass;local_report=$report_path;next_gate=implement_normalization_and_structural_units"
exit 0
