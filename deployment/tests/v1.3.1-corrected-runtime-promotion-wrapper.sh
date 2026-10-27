#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Exercise Script 13 transport, reporting, evidence publication, lifecycle
# receipts, failure propagation, recovery, and interruption cleanup.

readonly test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$test_dir/../.." && pwd -P)"
readonly wrapper="$repo_root/deployment/scripts/13_promote-v1.3.1-corrected-runtime-on-emceedanko.sh"
root="$(mktemp -d /tmp/ishikawa-script-13-wrapper-test.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT
  if (( status != 0 )); then
    for output in "$root"/*.out; do
      [[ -f "$output" ]] || continue
      printf '%s\n' "--- ${output##*/} ---" >&2
      tail -n 140 "$output" >&2 || true
    done
  fi
  find /tmp -maxdepth 1 -type d -name 'ishikawa-runtime-promotion-20*' -user "$(id -u)" \
    -exec rm -rf -- {} + 2>/dev/null || true
  rm -rf -- "$root"
  exit "$status"
}
trap cleanup EXIT
mkdir -p -- "$root/bin" "$root/reports" "$root/artifacts"
remote_promotion="$root/remote-promotion-receipt.txt"

printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' '
for argument in "$@"; do
  [[ "$argument" != -G ]] || { printf "%s\n" "hostname fake"; exit 0; }
done
for ((index=1; index <= $#; index++)); do
  [[ "${!index}" != -O ]] || exit 0
  [[ "${!index}" != -Nf ]] || exit 0
done
remote_command="${!#}"
if [[ "$remote_command" == *"df -PB1"* && "${MOCK_LOW_TRANSFER_CAPACITY:-0}" == 1 ]]; then
  printf "%s\n" 1
  exit 0
fi
if [[ "$remote_command" == *"previous-node-next-runtime-amd64.tar"* \
    && "$remote_command" == *"sha256sum --check"* ]]; then
  [[ "${MOCK_BAD_TRANSFERRED_ARCHIVE:-0}" != 1 ]] || exit 61
  exit 0
fi
if [[ "$remote_command" == *"bash ./promote-corrected-runtime-on-emceedanko"* ]]; then
  payload="$(tr "'\''" "\n" <<<"$remote_command" | awk "/\/payload\/target-result[.]txt$/ {print; exit}")"
  mode="$(tr "'\''" "\n" <<<"$remote_command" | awk "/^--(run|accept|rollback)$/ {print; exit}")"
  if [[ "${MOCK_TARGET_FAIL:-0}" == 1 ]]; then
    printf "%s\n" "FAILURE DETAIL" "stage=runtime_switch" \
      "reason=corrected_web_launch_failed" "detail=mock" \
      "previous_runtime_restored=true" "cleanup_failed=false" "operator_action=mock" >&2
    exit 19
  fi
  if [[ "${MOCK_TARGET_DELAY:-0}" == 1 ]]; then
    printf "%s\n" "[SWITCH] state=start;next=replace_web_container;automatic_restoration=previous_runtime"
    sleep 60
  fi
  {
    case "$mode" in
      --run)
        printf "%s\n" \
          "schema=ishikawa.emceedanko-v1.3.1-runtime-promotion.v1" \
          "previous_runtime_archive_sha256=af95820f63798b39c6538e3f9b5653d47b07aed1d81625e2382485ff559eff3f" \
          "previous_image_id=sha256:79f39435329920c9c834e55cf5e18528540220111ae2a35d779a86d0b539d298" \
          "production_build_start=pass" "human_ui_acceptance=pending" \
          "previous_runtime_rollback=available"
        ;;
      --accept)
        printf "%s\n" \
          "schema=ishikawa.emceedanko-v1.3.1-runtime-promotion-acceptance.v1" \
          "human_ui_acceptance=accepted" "production_runtime=pass" \
          "superseded_runtime_image_removed=true"
        ;;
      --rollback)
        printf "%s\n" \
          "schema=ishikawa.emceedanko-v1.3.1-runtime-promotion-action.v1" \
          "mode=rollback" "state=pass" "detail=previous_runtime_restored=true"
        ;;
      *) exit 20 ;;
    esac
    printf "%s\n" \
      "application_archive_sha256=2dbf08b9e15fb4436e54ce492f2ad430129e794d33a1a45cdc6abf1a7b0b5f69" \
      "runtime_archive_sha256=b92dd71eb155493d7e331e85c92566eee113ed4c8f0eda605c1c3dd951b836e1" \
      "image_id=sha256:6c93bcb5ed22de92420c4de4892eecdd08f1badc8b19e4d6f4488711f8f7a31a" \
      "application_mutated=false" "retrieval_api_restarted=false" "postgresql_restarted=false" \
      "database_mutated=false" "schema_mutated=false" "corpus_mutated=false" "boot_autostart=false"
  } >"$payload"
  if [[ "$mode" == --run ]]; then cp -- "$payload" "$MOCK_REMOTE_PROMOTION"; fi
  if [[ "${MOCK_BAD_RECEIPT:-0}" == 1 ]]; then
    sed -i "s/application_archive_sha256=.*/application_archive_sha256=bad/" "$payload"
  fi
  case "$mode" in
    --run) printf "%s\n" v1_3_1_corrected_runtime_promotion=pass ;;
    --accept) printf "%s\n" v1_3_1_corrected_runtime_promotion_acceptance=pass ;;
    --rollback) printf "%s\n" v1_3_1_corrected_runtime_promotion_rollback=pass ;;
  esac
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
  if [[ "$source_path" == *"Documents/Ishikawa-v1.3.1/state/reports/runtime-promotion/emceedanko-v1.3.1-corrected-runtime-promotion.txt" ]]; then
    cp -- "$MOCK_REMOTE_PROMOTION" "$destination"
  else
    cp -- "${source_path#*:}" "$destination"
  fi
else
  if [[ "$destination" == *"/previous-node-next-runtime-amd64.tar" \
      || "$destination" == *"/corrected-node-next-runtime-amd64.tar" ]]; then
    if [[ "$destination" == *"/previous-node-next-runtime-amd64.tar" \
        && "${MOCK_FAIL_PREVIOUS_ARCHIVE_TRANSFER:-0}" == 1 ]]; then exit 62; fi
    if [[ "$destination" == *"/corrected-node-next-runtime-amd64.tar" \
        && "${MOCK_FAIL_CORRECTED_ARCHIVE_TRANSFER:-0}" == 1 ]]; then exit 63; fi
    : >"${destination#*:}"
  else
    cp -- "$source_path" "${destination#*:}"
  fi
fi' >"$root/bin/scp"

printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' '
for argument in "$@"; do
  if [[ "$argument" == "$MOCK_ARTIFACT_PARENT"* && " $* " == *" -m "* ]]; then exit 95; fi
done
exec /usr/bin/mkdir "$@"' >"$root/bin/mkdir"
printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' '
for argument in "$@"; do
  [[ "$argument" != -R && "$argument" != --no-preserve=* ]] || exit 94
done
exec /usr/bin/cp "$@"' >"$root/bin/cp"
chmod 0755 "$root/bin/ssh" "$root/bin/scp" "$root/bin/mkdir" "$root/bin/cp"

run_wrapper() {
  local selected_mode="$1" output="$2" selected_artifact_parent
  shift 2
  selected_artifact_parent="${MOCK_SELECTED_ARTIFACT_PARENT:-$root/artifacts}"
  mkdir -p -- "$selected_artifact_parent"
  PATH="$root/bin:$PATH" \
  ISHIKAWA_SCRIPT13_REPORT_ROOT="$root/reports" \
  ISHIKAWA_SCRIPT13_ARTIFACT_PARENT="$selected_artifact_parent" \
  MOCK_ARTIFACT_PARENT="$selected_artifact_parent" \
  MOCK_REMOTE_PROMOTION="$remote_promotion" \
  MOCK_TARGET_FAIL="${MOCK_TARGET_FAIL:-0}" \
  MOCK_TARGET_DELAY="${MOCK_TARGET_DELAY:-0}" \
  MOCK_BAD_RECEIPT="${MOCK_BAD_RECEIPT:-0}" \
  MOCK_LOW_TRANSFER_CAPACITY="${MOCK_LOW_TRANSFER_CAPACITY:-0}" \
  MOCK_FAIL_PREVIOUS_ARCHIVE_TRANSFER="${MOCK_FAIL_PREVIOUS_ARCHIVE_TRANSFER:-0}" \
  MOCK_FAIL_CORRECTED_ARCHIVE_TRANSFER="${MOCK_FAIL_CORRECTED_ARCHIVE_TRANSFER:-0}" \
  MOCK_BAD_TRANSFERRED_ARCHIVE="${MOCK_BAD_TRANSFERRED_ARCHIVE:-0}" \
    bash "$wrapper" "$selected_mode" --target FakeEmcee "$@" >"$output" 2>&1
}

validation="$(PATH="$root/bin:$PATH" \
  ISHIKAWA_SCRIPT13_ARTIFACT_PARENT="$root/artifacts" \
  bash "$wrapper" --validate-only --target FakeEmcee)"
grep -Fxq 'script_13_v1_3_1_corrected_runtime_promotion=ready' <<<"$validation"
grep -Fq 'target_contact=false' <<<"$validation"
grep -Fq 'scope=web_runtime_only' <<<"$validation"

run_wrapper --run "$root/run.out"
grep -Fxq 'script_13_v1_3_1_corrected_runtime_promotion=pass' "$root/run.out"
evidence="$root/artifacts/emceedanko-v1.3.1-corrected-runtime-promotion-current"
[[ -f "$evidence/promotion-receipt.txt" && ! -e "$evidence/acceptance-receipt.txt" ]]
(cd -- "$evidence" && sha256sum --check --strict SHA256SUMS >/dev/null)

run_wrapper --accept "$root/accept.out"
grep -Fxq 'script_13_v1_3_1_corrected_runtime_promotion=pass' "$root/accept.out"
[[ -f "$evidence/promotion-receipt.txt" && -f "$evidence/acceptance-receipt.txt" ]]
(cd -- "$evidence" && sha256sum --check --strict SHA256SUMS >/dev/null)

recovered_parent="$root/recovered-artifacts"
MOCK_SELECTED_ARTIFACT_PARENT="$recovered_parent" run_wrapper --accept "$root/recovered-accept.out"
recovered_evidence="$recovered_parent/emceedanko-v1.3.1-corrected-runtime-promotion-current"
grep -Fxq 'script_13_v1_3_1_corrected_runtime_promotion=pass' "$root/recovered-accept.out"
[[ -f "$recovered_evidence/promotion-receipt.txt" && -f "$recovered_evidence/acceptance-receipt.txt" ]]
(cd -- "$recovered_evidence" && sha256sum --check --strict SHA256SUMS >/dev/null)

rollback_parent="$root/rollback-artifacts"
MOCK_SELECTED_ARTIFACT_PARENT="$rollback_parent" run_wrapper --run "$root/rollback-run.out"
MOCK_SELECTED_ARTIFACT_PARENT="$rollback_parent" run_wrapper --rollback "$root/rollback.out"
rollback_evidence="$rollback_parent/emceedanko-v1.3.1-corrected-runtime-promotion-current"
grep -Fxq 'script_13_v1_3_1_corrected_runtime_promotion=pass' "$root/rollback.out"
[[ -f "$rollback_evidence/promotion-receipt.txt" && -f "$rollback_evidence/rollback-receipt.txt" ]]
(cd -- "$rollback_evidence" && sha256sum --check --strict SHA256SUMS >/dev/null)

manifest_before="$(sha256sum -- "$evidence/SHA256SUMS" | awk '{print $1}')"
for transfer_case in capacity previous corrected checksum; do
  case "$transfer_case" in
    capacity) transfer_env=(MOCK_LOW_TRANSFER_CAPACITY=1); transfer_reason=target_transfer_capacity_insufficient ;;
    previous) transfer_env=(MOCK_FAIL_PREVIOUS_ARCHIVE_TRANSFER=1); transfer_reason=previous_runtime_archive_transfer_failed ;;
    corrected) transfer_env=(MOCK_FAIL_CORRECTED_ARCHIVE_TRANSFER=1); transfer_reason=corrected_runtime_archive_transfer_failed ;;
    checksum) transfer_env=(MOCK_BAD_TRANSFERRED_ARCHIVE=1); transfer_reason=transferred_runtime_archive_invalid ;;
  esac
  set +e
  env "${transfer_env[@]}" \
    PATH="$root/bin:$PATH" \
    ISHIKAWA_SCRIPT13_REPORT_ROOT="$root/reports" \
    ISHIKAWA_SCRIPT13_ARTIFACT_PARENT="$root/artifacts" \
    MOCK_ARTIFACT_PARENT="$root/artifacts" \
    MOCK_REMOTE_PROMOTION="$remote_promotion" \
    bash "$wrapper" --run --target FakeEmcee >"$root/transfer-${transfer_case}.out" 2>&1
  transfer_status="$?"
  set -e
  (( transfer_status != 0 ))
  grep -Fq "reason=$transfer_reason" "$root/transfer-${transfer_case}.out"
  [[ "$(sha256sum -- "$evidence/SHA256SUMS" | awk '{print $1}')" == "$manifest_before" ]]
done

set +e
MOCK_TARGET_FAIL=1 run_wrapper --run "$root/target-failure.out"
target_failure_status="$?"
set -e
(( target_failure_status != 0 ))
grep -Fq 'reason=corrected_web_launch_failed' "$root/target-failure.out"
! grep -Fq 'reason=unexpected_command_failure' "$root/target-failure.out"
[[ "$(sha256sum -- "$evidence/SHA256SUMS" | awk '{print $1}')" == "$manifest_before" ]]

set +e
MOCK_BAD_RECEIPT=1 run_wrapper --run "$root/bad-receipt.out"
bad_receipt_status="$?"
set -e
(( bad_receipt_status != 0 ))
grep -Fq 'reason=returned_receipt_invalid' "$root/bad-receipt.out"
[[ "$(sha256sum -- "$evidence/SHA256SUMS" | awk '{print $1}')" == "$manifest_before" ]]

env \
  PATH="$root/bin:$PATH" \
  ISHIKAWA_SCRIPT13_REPORT_ROOT="$root/reports" \
  ISHIKAWA_SCRIPT13_ARTIFACT_PARENT="$root/interrupted-artifacts" \
  MOCK_ARTIFACT_PARENT="$root/interrupted-artifacts" \
  MOCK_REMOTE_PROMOTION="$remote_promotion" \
  MOCK_TARGET_DELAY=1 \
  bash "$wrapper" --run --target FakeEmcee >"$root/interrupted.out" 2>&1 &
wrapper_pid="$!"
switch_seen=false
for _attempt in {1..200}; do
  if grep -Fq '[SWITCH] state=start' "$root/interrupted.out" 2>/dev/null; then
    switch_seen=true
    break
  fi
  sleep 0.1
done
[[ "$switch_seen" == true ]] || { kill -TERM "$wrapper_pid" 2>/dev/null || true; exit 1; }
kill -TERM "$wrapper_pid"
set +e
wait "$wrapper_pid"
interrupted_status="$?"
set -e
(( interrupted_status == 143 ))
grep -Fq 'reason=signal_termination' "$root/interrupted.out"
find /tmp -maxdepth 1 -type d -name 'ishikawa-runtime-promotion-20*' -user "$(id -u)" -print -quit \
  | grep -q . && exit 1

printf '%s\n' 'v1_3_1_corrected_runtime_promotion_wrapper_harness=pass;validate=pass;runtime_archive_transfer=pass;transfer_capacity_refusal=pass;transfer_failure=pass;transfer_checksum_refusal=pass;run=pass;accept=pass;rollback=pass;receipt_recovery=pass;publication=pass;target_failure=pass;receipt_failure=pass;signal=pass;remote_cleanup=pass'
