#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Exercise Script 12 end to end through its SSH/transfer/report/evidence
# orchestration without contacting a real target.

readonly test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$test_dir/../.." && pwd -P)"
readonly wrapper="$repo_root/deployment/scripts/12_requalify-v1.3.1-corrected-runtime-on-emceedanko.sh"
readonly profile='runtime-refresh'
readonly expected_runtime_archive_sha256='b92dd71eb155493d7e331e85c92566eee113ed4c8f0eda605c1c3dd951b836e1'
readonly expected_image_id='sha256:6c93bcb5ed22de92420c4de4892eecdd08f1badc8b19e4d6f4488711f8f7a31a'
readonly artifact_basename='emceedanko-v1.3.1-runtime-requalification-current'
readonly candidate_relative='Documents/Ishikawa-v1.3.1-runtime-qualification'
readonly result_key='script_12_v1_3_1_corrected_runtime_requalification'
readonly run_marker='v1_3_1_runtime_requalification=pass'
readonly accept_marker='v1_3_1_runtime_requalification_acceptance=pass'
readonly cleanup_marker='v1_3_1_runtime_requalification_cleanup=pass'
readonly qualification_schema='ishikawa.emceedanko-v1.3.1-runtime-qualification.v1'
readonly acceptance_schema='ishikawa.emceedanko-v1.3.1-runtime-acceptance.v1'
readonly action_schema='ishikawa.emceedanko-v1.3.1-runtime-action.v1'
readonly baseline_invariant='accepted_v1_3_1_mutated'
root="$(mktemp -d /tmp/ishikawa-script-12-wrapper-test.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT
  if (( status != 0 )); then
    for output in "$root"/*.out; do
      [[ -f "$output" ]] || continue
      printf '%s\n' "--- ${output##*/} ---" >&2
      tail -n 120 "$output" >&2 || true
    done
  fi
  find /tmp -maxdepth 1 -type d -name 'ishikawa-requalification-20*' -user "$(id -u)" \
    -exec rm -rf -- {} + 2>/dev/null || true
  rm -rf -- "$root"
  exit "$status"
}
trap cleanup EXIT
mkdir -p -- "$root/bin" "$root/reports" "$root/artifacts"
remote_qualification="$root/remote-qualification-receipt.txt"

printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' '
for argument in "$@"; do
  [[ "$argument" != -G ]] || { printf "%s\n" "hostname fake"; exit 0; }
done
for ((index=1; index <= $#; index++)); do
  [[ "${!index}" != -O ]] || exit 0
  [[ "${!index}" != -Nf ]] || exit 0
done
remote_command="${!#}"
if [[ "$remote_command" == *"bash ./requalify-v1.3.1-on-emceedanko"* ]]; then
  [[ "$remote_command" == *"http://127.0.0.1:18000"* \
      && "$remote_command" == *"http://127.0.0.1:18001"* ]] || exit 21
  payload="$(tr "'\''" "\n" <<<"$remote_command" | awk "/\\/payload\\/target-result[.]txt$/ {print; exit}")"
  mode="$(tr "'\''" "\n" <<<"$remote_command" | awk "/^--(run|accept|cleanup)$/ {print; exit}")"
  if [[ "${MOCK_TARGET_FAIL:-0}" == 1 ]]; then
    printf "%s\n" "FAILURE DETAIL" "stage=production_web_first_build" "reason=candidate_web_build_failed" "detail=mock" "cleanup_failed=false" "operator_action=mock" >&2
    exit 19
  fi
  case "$mode" in
    --run) marker="$MOCK_RUN_MARKER"; schema="$MOCK_QUALIFICATION_SCHEMA" ;;
    --accept) marker="$MOCK_ACCEPT_MARKER"; schema="$MOCK_ACCEPTANCE_SCHEMA" ;;
    --cleanup) marker="$MOCK_CLEANUP_MARKER"; schema="$MOCK_ACTION_SCHEMA" ;;
    *) exit 20 ;;
  esac
  {
    printf "schema=%s\n" "$schema"
    printf "%s\n" \
      "application_archive_sha256=2dbf08b9e15fb4436e54ce492f2ad430129e794d33a1a45cdc6abf1a7b0b5f69" \
      "runtime_archive_sha256=$MOCK_RUNTIME_ARCHIVE_SHA256" \
      "image_id=$MOCK_IMAGE_ID" \
      "$MOCK_BASELINE_INVARIANT=false" "accepted_database_mutated=false" "boot_autostart=false"
    if [[ "$mode" == --run ]]; then
      printf "%s\n" \
        "production_build_start=pass" "fresh_container_rebuild=pass" \
        "frontier_cases=60/60" "human_ui_acceptance=pending"
    elif [[ "$mode" == --accept ]]; then
      printf "%s\n" \
        "production_build_start=pass" "frontier_cases=60/60" \
        "human_ui_acceptance=accepted"
    else
      printf "%s\n" "mode=cleanup" "state=pass" "detail=candidate_removed=true"
    fi
  } >"$payload"
  if [[ "$mode" == --run ]]; then
    cp -- "$payload" "$MOCK_REMOTE_QUALIFICATION"
  elif [[ "$mode" == --cleanup ]]; then
    rm -f -- "$MOCK_REMOTE_QUALIFICATION"
  fi
  if [[ "${MOCK_BAD_RECEIPT:-0}" == 1 ]]; then
    sed -i "s/application_archive_sha256=.*/application_archive_sha256=bad/" "$payload"
  fi
  printf "%s\n" "$marker"
  exit 0
fi
bash -c "$remote_command"' >"$root/bin/ssh"

printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' '
positionals=()
while (( $# > 0 )); do
  case "$1" in
    -o|-i) shift 2 ;;
    -*) shift ;;
    *) positionals+=("$1"); shift ;;
  esac
done
(( ${#positionals[@]} == 2 ))
source_path="${positionals[0]}"
destination="${positionals[1]}"
if [[ "$source_path" == *:* ]]; then
  if [[ "$source_path" == *"$MOCK_CANDIDATE_RELATIVE/state/reports/qualification/emceedanko-v1.3.1-qualification.txt" ]]; then
    cp -- "$MOCK_REMOTE_QUALIFICATION" "$destination"
  else
    cp -- "${source_path#*:}" "$destination"
  fi
else
  cp -- "$source_path" "${destination#*:}"
fi' >"$root/bin/scp"
printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' '
for argument in "$@"; do
  if [[ "$argument" == "$MOCK_ARTIFACT_PARENT"* && " $* " == *" -m "* ]]; then
    exit 95
  fi
done
exec /usr/bin/mkdir "$@"' >"$root/bin/mkdir"
printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' '
for argument in "$@"; do
  [[ "$argument" != "$MOCK_ARTIFACT_PARENT"* ]] || exit 96
done
exec /usr/bin/install "$@"' >"$root/bin/install"
printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' '
for argument in "$@"; do
  [[ "$argument" != -R && "$argument" != --no-preserve=* ]] || exit 94
done
exec /usr/bin/cp "$@"' >"$root/bin/cp"
chmod 0755 "$root/bin/ssh" "$root/bin/scp" "$root/bin/mkdir" "$root/bin/install" "$root/bin/cp"

run_wrapper() {
  local selected_mode="$1" output="$2" selected_artifact_parent
  shift 2
  selected_artifact_parent="${MOCK_SELECTED_ARTIFACT_PARENT:-$root/artifacts}"
  mkdir -p -- "$selected_artifact_parent"
  PATH="$root/bin:$PATH" \
  ISHIKAWA_SCRIPT09_REPORT_ROOT="$root/reports" \
  ISHIKAWA_SCRIPT09_ARTIFACT_PARENT="$selected_artifact_parent" \
  MOCK_ARTIFACT_PARENT="$selected_artifact_parent" \
  MOCK_REMOTE_QUALIFICATION="$remote_qualification" \
  MOCK_RUNTIME_ARCHIVE_SHA256="$expected_runtime_archive_sha256" \
  MOCK_IMAGE_ID="$expected_image_id" \
  MOCK_CANDIDATE_RELATIVE="$candidate_relative" \
  MOCK_RUN_MARKER="$run_marker" MOCK_ACCEPT_MARKER="$accept_marker" \
  MOCK_CLEANUP_MARKER="$cleanup_marker" \
  MOCK_QUALIFICATION_SCHEMA="$qualification_schema" \
  MOCK_ACCEPTANCE_SCHEMA="$acceptance_schema" MOCK_ACTION_SCHEMA="$action_schema" \
  MOCK_BASELINE_INVARIANT="$baseline_invariant" \
  MOCK_TARGET_FAIL="${MOCK_TARGET_FAIL:-0}" MOCK_BAD_RECEIPT="${MOCK_BAD_RECEIPT:-0}" \
    bash "$wrapper" "$selected_mode" --target FakeEmcee "$@" >"$output" 2>&1
}

validation="$(PATH="$root/bin:$PATH" \
  ISHIKAWA_SCRIPT09_ARTIFACT_PARENT="$root/artifacts" \
  bash "$wrapper" --validate-only --target FakeEmcee)"
grep -Fxq "$result_key=ready" <<<"$validation"
grep -Fq 'target_contact=false' <<<"$validation"

primary_artifact_parent="${MOCK_SELECTED_ARTIFACT_PARENT:-$root/artifacts}"
run_wrapper --run "$root/run.out"
grep -Fxq "$result_key=pass" "$root/run.out"
evidence="$primary_artifact_parent/$artifact_basename"
[[ -f "$evidence/qualification-receipt.txt" && ! -e "$evidence/acceptance-receipt.txt" ]]
(cd -- "$evidence" && sha256sum --check --strict SHA256SUMS >/dev/null)

recovered_evidence="$root/recovered-artifacts/$artifact_basename"
MOCK_SELECTED_ARTIFACT_PARENT="$root/recovered-artifacts" \
  run_wrapper --accept "$root/recovered-accept.out"
grep -Fxq "$result_key=pass" "$root/recovered-accept.out"
[[ -f "$recovered_evidence/qualification-receipt.txt" \
    && -f "$recovered_evidence/acceptance-receipt.txt" ]]
(cd -- "$recovered_evidence" && sha256sum --check --strict SHA256SUMS >/dev/null)

run_wrapper --accept "$root/accept.out"
grep -Fxq "$result_key=pass" "$root/accept.out"
[[ -f "$evidence/qualification-receipt.txt" && -f "$evidence/acceptance-receipt.txt" ]]
(cd -- "$evidence" && sha256sum --check --strict SHA256SUMS >/dev/null)

run_wrapper --cleanup "$root/cleanup.out"
grep -Fxq "$result_key=pass" "$root/cleanup.out"
[[ -f "$evidence/cleanup-receipt.txt" ]]
(cd -- "$evidence" && sha256sum --check --strict SHA256SUMS >/dev/null)

cp -- "$evidence/qualification-receipt.txt" "$remote_qualification"
recovered_cleanup_evidence="$root/recovered-cleanup-artifacts/$artifact_basename"
MOCK_SELECTED_ARTIFACT_PARENT="$root/recovered-cleanup-artifacts" \
  run_wrapper --cleanup "$root/recovered-cleanup.out"
grep -Fxq "$result_key=pass" "$root/recovered-cleanup.out"
[[ -f "$recovered_cleanup_evidence/qualification-receipt.txt" \
    && -f "$recovered_cleanup_evidence/cleanup-receipt.txt" ]]
(cd -- "$recovered_cleanup_evidence" && sha256sum --check --strict SHA256SUMS >/dev/null)

manifest_before="$(sha256sum -- "$evidence/SHA256SUMS" | awk '{print $1}')"
set +e
MOCK_TARGET_FAIL=1 run_wrapper --run "$root/target-failure.out"
target_failure_status="$?"
set -e
(( target_failure_status != 0 ))
grep -Fq 'reason=candidate_web_build_failed' "$root/target-failure.out"
! grep -Fq 'reason=unexpected_command_failure' "$root/target-failure.out"
[[ "$(sha256sum -- "$evidence/SHA256SUMS" | awk '{print $1}')" == "$manifest_before" ]]

set +e
MOCK_BAD_RECEIPT=1 run_wrapper --run "$root/bad-receipt.out"
bad_receipt_status="$?"
set -e
(( bad_receipt_status != 0 ))
grep -Fq 'reason=returned_receipt_invalid' "$root/bad-receipt.out"
[[ "$(sha256sum -- "$evidence/SHA256SUMS" | awk '{print $1}')" == "$manifest_before" ]]

find /tmp -maxdepth 1 -type d -name 'ishikawa-requalification-20*' -user "$(id -u)" -print -quit \
  | grep -q . && exit 1
printf '%s\n' 'v1_3_1_runtime_requalification_wrapper_harness=pass;validate=pass;run=pass;accept=pass;cleanup=pass;receipt_recovery=pass;wsl_publication=pass;target_failure=pass;receipt_failure=pass'
