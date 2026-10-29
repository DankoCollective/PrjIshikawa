#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Purpose:
#   Prove the final update archive across every accepted and refusal state.
# Mental model:
#   Exercise pristine v1.3.1, the earlier partial update, rerun idempotency,
#   altered-target refusal, and verifier-triggered all-file rollback using the
#   exact archive produced by the assembler.
# Usage:
#   bash ./test-final-update.sh

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../../.." && pwd -P)"
readonly accepted_application_archive="$repo_root/local/artifacts/ishikawa-v1.3.1-candidate-current/ishikawa-v1.3.1.tar.gz"
readonly prior_update="$repo_root/deployment/hotfixes/v1.3.1-black-corpus-compatibility"
root="$(mktemp -d /tmp/ishikawa-final-update-test.XXXXXX)"

fail() {
  printf '\nSCRIPT RESULT\nishikawa_v1_3_1_cumulative_update_test=blocked;reason=%s\n' "$1" >&2
  exit 1
}

cleanup() {
  local status=$?
  trap - EXIT
  [[ "$root" == /tmp/ishikawa-final-update-test.* && -d "$root" ]] \
    && rm -rf -- "$root"
  exit "$status"
}
trap cleanup EXIT

for command_name in bash cp find install mkdir mktemp python3 sha256sum tar; do
  command -v "$command_name" >/dev/null 2>&1 || fail required_command_missing
done
[[ -f "$accepted_application_archive" && ! -L "$accepted_application_archive" ]] \
  || fail accepted_archive_missing

mkdir -p -- "$root/assembly" "$root/application"
bash "$script_dir/assemble-update.sh" "$root/assembly" >"$root/assemble.out" \
  || fail update_assembly_failed
archive="$root/assembly/ishikawa-v1.3.1-cumulative-update.tar.gz"
[[ -f "$archive" ]] || fail update_archive_missing
(cd -- "$root/assembly" && sha256sum --check --strict "${archive##*/}.sha256" >/dev/null) \
  || fail adjacent_checksum_failed
tar -xzf "$archive" -C "$root" || fail update_extraction_failed
bundle="$root/ishikawa-v1.3.1-cumulative-update"
(cd -- "$bundle" && sha256sum --check --strict SHA256SUMS >/dev/null) \
  || fail internal_checksum_failed
bash -n "$bundle/apply-update" || fail apply_script_syntax_failed
python3 -m py_compile "$bundle/verify-update.py" \
  || fail verifier_compile_failed

tar -xzf "$accepted_application_archive" -C "$root/application" \
  || fail accepted_archive_extraction_failed
accepted_payload="$root/application/ishikawa-v1.3.1/application/payload"
[[ -d "$accepted_payload" && ! -L "$accepted_payload" ]] || fail accepted_payload_missing

install_fixture() {
  local destination="$1"
  mkdir -p -- "$destination"
  cp -a -- "$accepted_payload/." "$destination/"
}

manifest_digest_for_root() {
  local destination="$1" relative _mode _accepted _final
  while IFS=$'\t' read -r relative _mode _accepted _final; do
    sha256sum -- "$destination/$relative"
  done <"$bundle/UPDATE_MANIFEST.tsv"
}

# Pristine v1.3.1 applies and an exact rerun is idempotent.
pristine="$root/pristine/Ishikawa"
install_fixture "$pristine"
ISHIKAWA_ROOT="$pristine" bash "$bundle/apply-update" --apply >"$root/pristine-first.out"
grep -Fxq 'ishikawa_v1_3_1_cumulative_update=pass' "$root/pristine-first.out" \
  || fail pristine_result_marker_missing
grep -Fq 'change=applied' "$root/pristine-first.out" \
  || fail pristine_apply_not_reported
pristine_final="$(manifest_digest_for_root "$pristine")"
ISHIKAWA_ROOT="$pristine" bash "$bundle/apply-update" --apply >"$root/pristine-second.out"
grep -Fq 'change=already_applied' "$root/pristine-second.out" \
  || fail idempotent_result_missing
[[ "$(manifest_digest_for_root "$pristine")" == "$pristine_final" ]] \
  || fail idempotent_rerun_changed_files

# The exact earlier three-file update already on Tech is an accepted input.
prior="$root/prior/Ishikawa"
install_fixture "$prior"
install -m 0755 -- "$prior_update/payload/capture-pdf-extraction-observations.py" \
  "$prior/scripts/capture-pdf-extraction-observations.py"
install -m 0644 -- "$prior_update/payload/document_control.py" \
  "$prior/application/python/ishikawa/document_control.py"
install -m 0644 -- "$prior_update/payload/document_footer.py" \
  "$prior/application/python/ishikawa/document_footer.py"
ISHIKAWA_ROOT="$prior" bash "$bundle/apply-update" --apply >"$root/prior.out"
grep -Fxq 'ishikawa_v1_3_1_cumulative_update=pass' "$root/prior.out" \
  || fail prior_update_result_marker_missing

# An unknown installed byte is refused before any target is changed.
altered="$root/altered/Ishikawa"
install_fixture "$altered"
printf '# local drift\n' >>"$altered/application/python/ishikawa/normalization.py"
altered_before="$(manifest_digest_for_root "$altered")"
set +e
ISHIKAWA_ROOT="$altered" bash "$bundle/apply-update" --apply >"$root/altered.out" 2>&1
altered_status=$?
set -e
(( altered_status != 0 )) || fail altered_target_was_accepted
grep -Fq 'reason=target_identity_mismatch' "$root/altered.out" \
  || fail altered_target_reason_missing
[[ "$(manifest_digest_for_root "$altered")" == "$altered_before" ]] \
  || fail altered_refusal_changed_files

# If focused verification fails after publication, all seven files roll back.
rollback="$root/rollback/Ishikawa"
install_fixture "$rollback"
rollback_before="$(manifest_digest_for_root "$rollback")"
mkdir -p -- "$root/bin"
real_python3="$(command -v python3)"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -Eeuo pipefail' \
  'for argument in "$@"; do' \
  '  [[ "$argument" != */verify-update.py ]] || exit 91' \
  'done' \
  'exec "$ISHIKAWA_TEST_REAL_PYTHON3" "$@"' \
  >"$root/bin/python3"
chmod 0755 "$root/bin/python3"
set +e
PATH="$root/bin:$PATH" ISHIKAWA_TEST_REAL_PYTHON3="$real_python3" \
  ISHIKAWA_ROOT="$rollback" bash "$bundle/apply-update" --apply \
  >"$root/rollback.out" 2>&1
rollback_status=$?
set -e
(( rollback_status != 0 )) || fail verifier_failure_was_accepted
grep -Fq 'reason=replacement_verification_failed' "$root/rollback.out" \
  || fail rollback_reason_missing
[[ "$(manifest_digest_for_root "$rollback")" == "$rollback_before" ]] \
  || fail verifier_failure_did_not_restore_all_files

printf '%s\n' \
  'fresh_install=pass' \
  'prior_partial_update=pass' \
  'idempotent_rerun=pass' \
  'altered_target_refusal=pass' \
  'all_file_rollback=pass'
printf '\nSCRIPT RESULT\nishikawa_v1_3_1_cumulative_update_test=pass\n'
