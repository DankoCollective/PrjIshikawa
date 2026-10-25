#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Purpose:
#   Exercise Script 05 from local validation through transfer, nested target
#   result handling, artifact publication, failure propagation, and cleanup.
#
# Mental model:
#   Replace only SSH/SCP and the already independently tested target lifecycle,
#   then run the real operator wrapper through success and remote-gate failure.
#
# Inputs or prerequisites:
#   Current Script 01 and Script 03 handoffs plus the Script 05 implementation.
#
# Outputs or artifact lane:
#   Temporary files under /tmp only; no remote contact or repository mutation.
#
# Usage:
#   bash ./deployment/tests/qualify-candidate-wrapper.sh

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
readonly wrapper="$repo_root/deployment/scripts/05_qualify-v1.3-on-emceedanko.sh"
readonly application="$repo_root/local/artifacts/ishikawa-v1.3-current/ishikawa-v1.3.tar.gz"

fail() {
  printf '\nSCRIPT RESULT\nqualify_candidate_wrapper_test=blocked;reason=%s\n' "$1" >&2
  exit 1
}

for file in "$wrapper" "$application"; do
  [[ -f "$file" && ! -L "$file" && -r "$file" ]] || fail input_unsafe
done
for command_name in script python3 sha256sum; do
  command -v "$command_name" >/dev/null 2>&1 || fail "command_missing_${command_name}"
done
bash -n "$wrapper" || fail wrapper_syntax_invalid

test_root="$(mktemp -d /tmp/ishikawa-qualify-wrapper-test.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  find /tmp -maxdepth 1 -type d -name 'ishikawa-v1.3-qualification-*' \
    -newer "$test_root" -exec rm -rf -- {} + 2>/dev/null || true
  [[ "$test_root" == /tmp/ishikawa-qualify-wrapper-test.* && -d "$test_root" ]] \
    && rm -rf -- "$test_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p -- "$test_root/bin" "$test_root/reports" "$test_root/artifacts"
application_sha256="$(sha256sum -- "$application" | awk '{print $1}')"
printf '%s\n' \
  "[READINESS] application_archive_sha256=$application_sha256;corpus_archive_sha256=$(printf 'c%.0s' {1..64});helper_sha256=$(printf 'd%.0s' {1..64})" \
  '[CANDIDATE] active_v1_2_preserved=true;rollback_tree_preserved=true;active_service_unchanged=true;ports_3000_1384_unchanged=true' \
  '[CANDIDATE] database_changed=false;service_changed=false;boot_autostart_changed=false;model_contact=false;credential_read=false' \
  '[CANDIDATE] ishikawa_v1_3_candidate_stage=pass' \
  'script_04_stage_v1_3_candidate_on_emceedanko=pass' \
  >"$test_root/stage-report.txt"

printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' \
  'for argument in "$@"; do' \
  '  [[ "$argument" != -G ]] || { printf "hostname fake-target\\n"; exit 0; }' \
  'done' \
  'for ((index=1; index <= $#; index++)); do' \
  '  [[ "${!index}" != -O ]] || exit 0' \
  '  [[ "${!index}" != -Nf ]] || exit 0' \
  'done' \
  'remote_command="${!#}"' \
  'if [[ "$remote_command" == *"qualify-v1.3-candidate --run"* ]]; then' \
  '  result_path="$(sed -n "s/.*--result-path '\''\\([^'\'']*\\)'\''.*/\\1/p" <<<"$remote_command")"' \
  '  artifact_path="$(sed -n "s/.*--artifact-path '\''\\([^'\'']*\\)'\''.*/\\1/p" <<<"$remote_command")"' \
  '  expected_hostname="$(sed -n "s/.*--expected-hostname '\''\\([^'\'']*\\)'\''.*/\\1/p" <<<"$remote_command")"' \
  '  expected_os="$(sed -n "s/.*--expected-os-version '\''\\([^'\'']*\\)'\''.*/\\1/p" <<<"$remote_command")"' \
  '  if [[ "${ISHIKAWA_FAKE_QUALIFY_FAIL:-0}" == 1 ]]; then' \
  '    printf "%s\\n" "target_hostname=$expected_hostname;os_id=ubuntu;os_version=$expected_os;architecture=amd64" "qualification_database=disposable;postgresql_port=65438;retrieval_api_port=1385" "active_v1_2_preserved=true;accepted_database_contact=false;candidate_mutated=false;boot_autostart_changed=false" "cleanup=pass;temporary_postgresql_removed=true;temporary_api_stopped=true;qualification_ports_free=true" "FAILURE DETAIL" "stage=frontier_qualification" "reason=frontier_gate_failed" "detail=The isolated frontier double reported one failed case." "operator_action=Correct the named case before rerunning Script 05." "root_cause=case_failure" "ishikawa_v1_3_emceedanko_disposable_qualification=blocked" >"$result_path"' \
  '    printf "\\nSCRIPT RESULT\\nqualify_v1_3_candidate=blocked\\n"' \
  '    exit 1' \
  '  fi' \
  '  printf "%s\\n" "target_hostname=$expected_hostname;os_id=ubuntu;os_version=$expected_os;architecture=amd64" "qualification_database=disposable;postgresql_port=65438;retrieval_api_port=1385" "active_v1_2_preserved=true;accepted_database_contact=false;candidate_mutated=false;boot_autostart_changed=false" "cleanup=pass;temporary_postgresql_removed=true;temporary_api_stopped=true;qualification_ports_free=true" "native_qualification=pass;tests=486" "corpus_v3_ingestion=pass;documents=30;pages=150;authoritative_chunks=786;retrieval_candidates=943;retrieval_scoring_only=157;embeddings=943;relationship_records=240;relationship_pairs=90" "frontier_qualification=pass;cases=60/60;required_evidence_returned=60/60;required_evidence_cited=60/60;dependency_failures=0" "ishikawa_v1_3_emceedanko_disposable_qualification=pass" >"$result_path"' \
  '  python3 -B - "$artifact_path" "$expected_hostname" "$expected_os" <<'\''PY'\''' \
  'import json, pathlib, sys' \
  'path = pathlib.Path(sys.argv[1])' \
  'summary = {"acceptance_gate":"pass","case_count":60,"contract_valid_count":60,"expected_status_match_count":60,"required_evidence_count":60,"required_evidence_returned_count":60,"required_evidence_cited_count":60,"dependency_failure_count":0}' \
  'target = {"architecture":"amd64","hostname":sys.argv[2],"os_id":"ubuntu","os_version":sys.argv[3]}' \
  'path.write_text(json.dumps({"artifact_kind":"ishikawa_v1_3_complete_api_qualification","synthetic_content_only":True,"target":target,"summary":summary,"cases":[{} for _ in range(60)]}), encoding="utf-8")' \
  'PY' \
  '  printf "\\nSCRIPT RESULT\\nqualify_v1_3_candidate=pass\\n"' \
  '  exit 0' \
  'fi' \
  'bash -c "$remote_command"' \
  >"$test_root/bin/ssh"
chmod 0700 "$test_root/bin/ssh"

printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' \
  'positionals=()' \
  'while (( $# > 0 )); do case "$1" in -o|-i) shift 2 ;; -*) shift ;; *) positionals+=("$1"); shift ;; esac; done' \
  '(( ${#positionals[@]} >= 2 )) || exit 2' \
  'source_path="${positionals[0]}"; destination="${positionals[${#positionals[@]}-1]}"' \
  'if [[ "$source_path" == *:* ]]; then /usr/bin/cp -- "${source_path#*:}" "$destination"; else /usr/bin/cp -- "$source_path" "${destination#*:}/"; fi' \
  >"$test_root/bin/scp"
chmod 0700 "$test_root/bin/scp"

run_wrapper() {
  local name="$1" fail_target="${2:-0}" output command
  output="$test_root/${name}.stdout"
  command="bash '$wrapper' --run --target FakeEmcee --stage-report '$test_root/stage-report.txt' --report-root '$test_root/reports' --artifact-parent '$test_root/artifacts'"
  set +e
  PATH="$test_root/bin:$PATH" ISHIKAWA_FAKE_QUALIFY_FAIL="$fail_target" \
    script -qefc "$command" /dev/null 2>&1 | tr -d '\r' >"$output"
  wrapper_status="${PIPESTATUS[0]}"
  set -e
}

validation="$(ISHIKAWA_SCRIPT05_STAGE_REPORT="$test_root/stage-report.txt" \
  bash "$wrapper" --validate-only 2>&1)" || fail validate_only_failed
grep -Fxq 'script_05_qualify_v1_3_on_emceedanko=ready' <<<"$validation" \
  || fail validate_only_marker_missing
grep -Fq 'target_contact=false;credential_read=false;database_contact=false;model_contact=false;service_changed=false' <<<"$validation" \
  || fail validate_only_noncontact_missing

run_wrapper pass
(( wrapper_status == 0 )) || fail wrapper_success_failed
grep -Fq '[AUTHENTICATION] state=waiting_for_ssh_private_key_passphrase_if_prompted' "$test_root/pass.stdout" \
  || fail ssh_prompt_announcement_missing
grep -Fq '[QUALIFICATION] state=start;next_prompt=gemma_api_key;then=nomic_api_key;credential_input_hidden=true;accepted_database_contact=false' "$test_root/pass.stdout" \
  || fail model_prompt_announcement_missing
grep -Fxq 'script_05_qualify_v1_3_on_emceedanko=pass' "$test_root/pass.stdout" \
  || fail wrapper_pass_marker_missing
current="$test_root/artifacts/emceedanko-v1.3-frontier-qualification-current"
[[ -d "$current" && ! -L "$current" ]] || fail current_artifact_missing
(cd -- "$current" && sha256sum --check --strict SHA256SUMS >/dev/null) \
  || fail current_artifact_checksum_failed
receipt_before="$(sha256sum -- "$current/receipt.json" | awk '{print $1}')"

PYTHONDONTWRITEBYTECODE=1 python3 -B - "$test_root/pass.stdout" <<'PY' \
  || fail milestone_order_invalid
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
tags = ("[READINESS]", "[AUTHENTICATION]", "[TRANSFER]", "[QUALIFICATION]", "[VERIFY]", "[PUBLISH]", "[CLEANUP]", "[SUMMARY]")
positions = [text.index(tag) for tag in tags]
if positions != sorted(positions):
    raise SystemExit(1)
PY

run_wrapper failure 1
(( wrapper_status != 0 )) || fail nested_failure_reported_success
grep -Fq 'reason=frontier_gate_failed' "$test_root/failure.stdout" \
  || { sed -n '1,240p' "$test_root/failure.stdout" >&2; fail nested_failure_reason_missing; }
grep -Fq 'root_cause=case_failure' "$test_root/failure.stdout" \
  || fail nested_failure_root_cause_missing
grep -Fxq 'script_05_qualify_v1_3_on_emceedanko=blocked' "$test_root/failure.stdout" \
  || fail nested_block_marker_missing
[[ "$(sha256sum -- "$current/receipt.json" | awk '{print $1}')" == "$receipt_before" ]] \
  || fail accepted_artifact_changed_after_failure
if find /tmp -maxdepth 1 -type d -name 'ishikawa-v1.3-qualification-*' \
  -newer "$test_root" -print -quit | grep -q .; then
  fail remote_transfer_retained
fi

printf '%s\n' \
  'validate_only=pass;target_contact=false;transfer=pass;nested_target_result=pass' \
  'artifact_validation=pass;atomic_publication=pass;milestone_order=pass' \
  'nested_failure_propagation=pass;accepted_artifact_preserved_after_failure=pass;remote_cleanup=pass'
printf '\nSCRIPT RESULT\nqualify_candidate_wrapper_test=pass\n'
