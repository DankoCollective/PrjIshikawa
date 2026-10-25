#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Purpose:
#   Exercise the target-side Script 04 helper without contacting EmceeDanko.
#
# Mental model:
#   Substitute only host/runtime inspection commands, then run the real helper
#   and real release installers through fresh, exact-rerun, drift, checksum,
#   runtime-readiness, and partial-publication failure paths.
#
# Inputs or prerequisites:
#   The current checksum-bound application and qualification-corpus handoffs.
#
# Outputs or artifact lane:
#   Temporary state under /tmp only; every scenario is removed on exit.
#
# Usage:
#   bash ./deployment/tests/stage-candidate-helper.sh

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
readonly helper="$repo_root/deployment/assets/stage-v1.3-candidate"
readonly application="$repo_root/local/artifacts/ishikawa-v1.3-current/ishikawa-v1.3.tar.gz"
readonly corpus="$repo_root/local/artifacts/qualification-corpus-v3-current/qualification-corpus-v3.tar.gz"

fail() {
  printf '\nSCRIPT RESULT\nstage_candidate_helper_test=blocked;reason=%s\n' "$1" >&2
  exit 1
}
for file in "$helper" "$application" "$corpus"; do
  [[ -f "$file" && ! -L "$file" && -r "$file" ]] || fail input_unsafe
done
bash -n "$helper" || fail helper_syntax_invalid

test_root="$(mktemp -d /tmp/ishikawa-stage-helper-test.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  [[ "$test_root" == /tmp/ishikawa-stage-helper-test.* && -d "$test_root" ]] \
    && rm -rf -- "$test_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p -- "$test_root/home/Documents/Ishikawa" \
  "$test_root/home/Documents/Ishikawa-before-v1.2" "$test_root/bin" "$test_root/work"
cp -- "$application" "$test_root/work/ishikawa-v1.3.tar.gz"
cp -- "$corpus" "$test_root/work/qualification-corpus-v3.tar.gz"

write_command() {
  local name="$1" body="$2"
  printf '#!/usr/bin/env bash\n%s\n' "$body" >"$test_root/bin/$name"
  chmod 0700 "$test_root/bin/$name" 2>/dev/null || true
}
write_command hostname "printf 'EmceeDanko\\n'"
write_command dpkg "[[ \"\${1:-}\" == --print-architecture ]] && printf 'amd64\\n'"
write_command uname "[[ \"\${1:-}\" == -m ]] && printf 'x86_64\\n'"
write_command systemctl "[[ \"\${1:-}\" == --user && \"\${2:-}\" == is-active ]] && printf '%s\\n' \"\${ISHIKAWA_TEST_SERVICE_STATE:-active}\""
write_command ss "printf '%b' \"\${ISHIKAWA_TEST_LISTENERS:-LISTEN 0 4096 127.0.0.1:1384 0.0.0.0:*\\nLISTEN 0 4096 127.0.0.1:3000 0.0.0.0:*\\n}\""

application_sha256="$(sha256sum -- "$test_root/work/ishikawa-v1.3.tar.gz" | awk '{print $1}')"
corpus_sha256="$(sha256sum -- "$test_root/work/qualification-corpus-v3.tar.gz" | awk '{print $1}')"
run_helper() {
  local output="$1"
  local expected_application_sha256="${2:-$application_sha256}"
  local expected_corpus_sha256="${3:-$corpus_sha256}"
  local replace_unqualified_candidate="${4:-false}"
  local replace_qualification_inputs="${5:-false}"
  (
    cd -- "$test_root/work"
    HOME="$test_root/home" PATH="$test_root/bin:$PATH" bash "$helper" \
      EmceeDanko 24.04 \
      "$test_root/work/ishikawa-v1.3.tar.gz" "$expected_application_sha256" \
      "$test_root/work/qualification-corpus-v3.tar.gz" "$expected_corpus_sha256" \
      "$output" "$replace_unqualified_candidate" "$replace_qualification_inputs"
  )
}

expect_blocked() {
  local output="$1" reason="$2"
  shift 2
  set +e
  run_helper "$output" "$@"
  local status="$?"
  set -e
  (( status != 0 )) || fail "${reason}_accepted"
  grep -Fxq "ishikawa_v1_3_candidate_stage=blocked;reason=$reason" "$output" \
    || fail "${reason}_missing"
}

reset_staged_state() {
  rm -rf -- "$test_root/home/Documents/Ishikawa-v1.3" \
    "$test_root/home/Documents/Ishikawa-v1.3-qualification-inputs"
}

run_helper "$test_root/work/first.txt" || fail first_install_failed
grep -Fxq "application_archive_sha256=$application_sha256;application_verification=pass;candidate_action=installed_new" \
  "$test_root/work/first.txt" || fail first_application_action_invalid
grep -Fxq "corpus_archive_sha256=$corpus_sha256;corpus_verification=pass;corpus_action=staged_new" \
  "$test_root/work/first.txt" || fail first_corpus_action_invalid
grep -Fxq 'active_v1_2_preserved=true;rollback_tree_preserved=true;active_service_unchanged=true;ports_3000_1384_unchanged=true' \
  "$test_root/work/first.txt" || fail preservation_contract_missing

run_helper "$test_root/work/second.txt" || fail exact_reuse_failed
grep -Fxq "application_archive_sha256=$application_sha256;application_verification=pass;candidate_action=reused_exact" \
  "$test_root/work/second.txt" || fail reuse_application_action_invalid
grep -Fxq "corpus_archive_sha256=$corpus_sha256;corpus_verification=pass;corpus_action=reused_exact" \
  "$test_root/work/second.txt" || fail reuse_corpus_action_invalid

printf 'corrupt\n' >>"$test_root/home/Documents/Ishikawa-v1.3/config/product.yaml"
expect_blocked "$test_root/work/third.txt" existing_candidate_identity_mismatch
[[ -d "$test_root/home/Documents/Ishikawa" && -d "$test_root/home/Documents/Ishikawa-before-v1.2" ]] \
  || fail accepted_installation_removed
grep -Fq 'corrupt' "$test_root/home/Documents/Ishikawa-v1.3/config/product.yaml" \
  || fail preexisting_candidate_mutated

printf 'corrupt\n' >>"$test_root/home/Documents/Ishikawa-v1.3-qualification-inputs/qualification-corpus-v3.tar.gz"
expect_blocked "$test_root/work/replacement-rollback.txt" existing_corpus_identity_mismatch \
  "$application_sha256" "$corpus_sha256" true
grep -Fq 'corrupt' "$test_root/home/Documents/Ishikawa-v1.3/config/product.yaml" \
  || fail replacement_failure_did_not_restore_candidate
find "$test_root/home/Documents" -maxdepth 1 -type d -name '.ishikawa-v1.3-replacement.*' -print -quit \
  | grep -q . && fail replacement_failure_retained_workspace
rm -rf -- "$test_root/home/Documents/Ishikawa-v1.3-qualification-inputs"

run_helper "$test_root/work/replacement.txt" "$application_sha256" "$corpus_sha256" true \
  || fail explicit_unqualified_replacement_failed
grep -Fxq "application_archive_sha256=$application_sha256;application_verification=pass;candidate_action=replaced_unqualified" \
  "$test_root/work/replacement.txt" || fail replacement_action_invalid
grep -Fq 'corrupt' "$test_root/home/Documents/Ishikawa-v1.3/config/product.yaml" \
  && fail replacement_retained_old_candidate

printf 'corrupt\n' >>"$test_root/home/Documents/Ishikawa-v1.3-qualification-inputs/qualification-corpus-v3.tar.gz"
run_helper "$test_root/work/input-replacement.txt" "$application_sha256" "$corpus_sha256" false true \
  || fail explicit_qualification_input_replacement_failed
grep -Fxq "corpus_archive_sha256=$corpus_sha256;corpus_verification=pass;corpus_action=replaced_unqualified" \
  "$test_root/work/input-replacement.txt" || fail qualification_input_replacement_action_invalid
(cd -- "$test_root/home/Documents/Ishikawa-v1.3-qualification-inputs" \
  && sha256sum --check --strict qualification-corpus-v3.tar.gz.sha256 >/dev/null) \
  || fail qualification_input_replacement_checksum_invalid

reset_staged_state
expect_blocked "$test_root/work/bad-application-checksum.txt" application_archive_checksum_mismatch \
  "$(printf '0%.0s' {1..64})" "$corpus_sha256"
[[ ! -e "$test_root/home/Documents/Ishikawa-v1.3" \
    && ! -e "$test_root/home/Documents/Ishikawa-v1.3-qualification-inputs" ]] \
  || fail checksum_failure_created_state

ISHIKAWA_TEST_SERVICE_STATE=inactive \
  expect_blocked "$test_root/work/runtime-not-ready.txt" active_v1_2_runtime_not_ready
[[ ! -e "$test_root/home/Documents/Ishikawa-v1.3" \
    && ! -e "$test_root/home/Documents/Ishikawa-v1.3-qualification-inputs" ]] \
  || fail readiness_failure_created_state

run_helper "$test_root/work/reinstall.txt" || fail reinstall_failed
printf 'corrupt\n' >>"$test_root/home/Documents/Ishikawa-v1.3-qualification-inputs/qualification-corpus-v3.tar.gz"
expect_blocked "$test_root/work/corpus-drift.txt" existing_corpus_identity_mismatch
[[ -d "$test_root/home/Documents/Ishikawa-v1.3" ]] || fail corpus_drift_removed_candidate

reset_staged_state
printf 'preserve\n' >"$test_root/home/Documents/Ishikawa-v1.3-qualification-inputs"
expect_blocked "$test_root/work/partial-publication.txt" qualification_inputs_unsafe
[[ ! -e "$test_root/home/Documents/Ishikawa-v1.3" ]] \
  || fail partial_failure_left_new_candidate
grep -Fxq preserve "$test_root/home/Documents/Ishikawa-v1.3-qualification-inputs" \
  || fail partial_failure_mutated_preexisting_input

printf '%s\n' \
  'fresh_side_by_side_install=pass;exact_rerun_reuse=pass;mismatch_rejection=pass;replacement_rollback=pass;explicit_unqualified_replacement=pass;explicit_qualification_input_replacement=pass' \
  'checksum_rejection=pass;runtime_readiness_rejection=pass;corpus_drift_rejection=pass' \
  'partial_failure_cleanup=pass;active_v1_2_preservation=pass;rollback_tree_preservation=pass;corpus_separation=pass'
printf '\nSCRIPT RESULT\nstage_candidate_helper_test=pass\n'
