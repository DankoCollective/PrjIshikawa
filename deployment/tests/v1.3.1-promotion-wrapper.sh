#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Exercise Script 10 transport, report streaming, evidence publication,
# lifecycle receipts, nested failures, WSL semantics, and interruption cleanup.

readonly test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$test_dir/../.." && pwd -P)"
readonly wrapper="$repo_root/deployment/scripts/10_promote-v1.3.1-on-emceedanko.sh"
root="$(mktemp -d /tmp/ishikawa-promotion-wrapper-test.XXXXXX)"
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
  find /tmp -maxdepth 1 -type d -name 'ishikawa-promotion-20*' -user "$(id -u)" -exec rm -rf -- {} + 2>/dev/null || true
  rm -rf -- "$root"
  exit "$status"
}
trap cleanup EXIT

mkdir -p -- "$root/bin" "$root/reports" "$root/artifacts" "$root/script09"
printf '%s\n' \
  'schema=ishikawa.emceedanko-v1.3.1-qualification.v1' \
  'application_archive_sha256=2dbf08b9e15fb4436e54ce492f2ad430129e794d33a1a45cdc6abf1a7b0b5f69' \
  'runtime_archive_sha256=af95820f63798b39c6538e3f9b5653d47b07aed1d81625e2382485ff559eff3f' \
  'image_id=sha256:79f39435329920c9c834e55cf5e18528540220111ae2a35d779a86d0b539d298' \
  'frontier_cases=60/60' >"$root/script09/qualification-receipt.txt"
printf '%s\n' \
  'schema=ishikawa.emceedanko-v1.3.1-acceptance.v1' \
  'application_archive_sha256=2dbf08b9e15fb4436e54ce492f2ad430129e794d33a1a45cdc6abf1a7b0b5f69' \
  'runtime_archive_sha256=af95820f63798b39c6538e3f9b5653d47b07aed1d81625e2382485ff559eff3f' \
  'image_id=sha256:79f39435329920c9c834e55cf5e18528540220111ae2a35d779a86d0b539d298' \
  'human_ui_acceptance=accepted' >"$root/script09/acceptance-receipt.txt"
printf '%s\n' \
  'schema=ishikawa.emceedanko-v1.3.1-action.v1' \
  'mode=cleanup' 'state=pass' 'detail=candidate_removed=true' \
  'application_archive_sha256=2dbf08b9e15fb4436e54ce492f2ad430129e794d33a1a45cdc6abf1a7b0b5f69' \
  'runtime_archive_sha256=af95820f63798b39c6538e3f9b5653d47b07aed1d81625e2382485ff559eff3f' \
  'image_id=sha256:79f39435329920c9c834e55cf5e18528540220111ae2a35d779a86d0b539d298' \
  >"$root/script09/cleanup-receipt.txt"
(
  cd -- "$root/script09"
  sha256sum -- qualification-receipt.txt acceptance-receipt.txt cleanup-receipt.txt >SHA256SUMS
)

printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' '
for argument in "$@"; do
  [[ "$argument" != -G ]] || { printf "%s\n" "hostname fake"; exit 0; }
done
for ((index=1; index <= $#; index++)); do
  [[ "${!index}" != -O ]] || exit 0
  [[ "${!index}" != -Nf ]] || exit 0
done
remote_command="${!#}"
if [[ "$remote_command" == *"bash ./promote-v1.3.1-on-emceedanko"* ]]; then
  payload="$(tr "'\''" "\n" <<<"$remote_command" | awk "/\/payload\/target-result[.]txt$/ {print; exit}")"
  mode="$(tr "'\''" "\n" <<<"$remote_command" | awk "/^--(run|accept|rollback)$/ {print; exit}")"
  if [[ "${MOCK_TARGET_FAIL:-0}" == 1 ]]; then
    printf "%s\n" "FAILURE DETAIL" "stage=v1_3_1_launch" "reason=v1_3_1_launch_failed" "detail=mock" "rollback_restored=true" "cleanup_failed=false" "operator_action=mock" >&2
    exit 19
  fi
  if [[ "${MOCK_TARGET_DELAY:-0}" == 1 ]]; then
    printf "%s\n" "[SWITCH] state=start;next=stop_v1_3;rollback=automatic"
    sleep 60
  fi
  {
    case "$mode" in
      --run)
        printf "%s\n" \
          "schema=ishikawa.emceedanko-v1.3.1-promotion.v1" \
          "database_state=moved_unchanged" "human_ui_acceptance=pending" "rollback_v1_3=available"
        ;;
      --accept)
        printf "%s\n" \
          "schema=ishikawa.emceedanko-v1.3.1-promotion-acceptance.v1" \
          "human_ui_acceptance=accepted" "superseded_v1_3_removed=true" "superseded_image_removed=true"
        ;;
      --rollback)
        printf "%s\n" \
          "schema=ishikawa.emceedanko-v1.3.1-promotion-action.v1" \
          "mode=rollback" "state=pass" "detail=accepted_v1_3_restored=true"
        ;;
      *) exit 20 ;;
    esac
    printf "%s\n" \
      "application_archive_sha256=2dbf08b9e15fb4436e54ce492f2ad430129e794d33a1a45cdc6abf1a7b0b5f69" \
      "runtime_archive_sha256=af95820f63798b39c6538e3f9b5653d47b07aed1d81625e2382485ff559eff3f" \
      "image_id=sha256:79f39435329920c9c834e55cf5e18528540220111ae2a35d779a86d0b539d298" \
      "database_mutated=false" "schema_mutated=false" "corpus_mutated=false" "boot_autostart=false"
  } >"$payload"
  if [[ "${MOCK_BAD_RECEIPT:-0}" == 1 ]]; then
    sed -i "s/application_archive_sha256=.*/application_archive_sha256=bad/" "$payload"
  fi
  case "$mode" in
    --run) printf "%s\n" v1_3_1_promotion=pass ;;
    --accept) printf "%s\n" v1_3_1_promotion_acceptance=pass ;;
    --rollback) printf "%s\n" v1_3_1_promotion_rollback=pass ;;
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
  cp -- "${source_path#*:}" "$destination"
else
  cp -- "$source_path" "${destination#*:}"
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
  ISHIKAWA_SCRIPT10_REPORT_ROOT="$root/reports" \
  ISHIKAWA_SCRIPT10_ARTIFACT_PARENT="$selected_artifact_parent" \
  ISHIKAWA_SCRIPT10_SCRIPT09_EVIDENCE="$root/script09" \
  MOCK_ARTIFACT_PARENT="$selected_artifact_parent" \
  MOCK_TARGET_FAIL="${MOCK_TARGET_FAIL:-0}" \
  MOCK_TARGET_DELAY="${MOCK_TARGET_DELAY:-0}" \
  MOCK_BAD_RECEIPT="${MOCK_BAD_RECEIPT:-0}" \
    bash "$wrapper" "$selected_mode" --target FakeEmcee "$@" >"$output" 2>&1
}

validation="$(PATH="$root/bin:$PATH" \
  ISHIKAWA_SCRIPT10_SCRIPT09_EVIDENCE="$root/script09" \
  ISHIKAWA_SCRIPT10_ARTIFACT_PARENT="$root/artifacts" \
  bash "$wrapper" --validate-only --target FakeEmcee)"
grep -Fxq 'script_10_v1_3_1_promotion=ready' <<<"$validation"
grep -Fq 'target_contact=false' <<<"$validation"

primary_artifact_parent="${MOCK_SELECTED_ARTIFACT_PARENT:-$root/artifacts}"
run_wrapper --run "$root/run.out"
grep -Fxq 'script_10_v1_3_1_promotion=pass' "$root/run.out"
evidence="$primary_artifact_parent/emceedanko-v1.3.1-promotion-current"
[[ -f "$evidence/promotion-receipt.txt" && ! -e "$evidence/acceptance-receipt.txt" ]]
(cd -- "$evidence" && sha256sum --check --strict SHA256SUMS >/dev/null)

run_wrapper --accept "$root/accept.out"
grep -Fxq 'script_10_v1_3_1_promotion=pass' "$root/accept.out"
[[ -f "$evidence/promotion-receipt.txt" && -f "$evidence/acceptance-receipt.txt" ]]
(cd -- "$evidence" && sha256sum --check --strict SHA256SUMS >/dev/null)

rollback_parent="$root/rollback-artifacts"
MOCK_SELECTED_ARTIFACT_PARENT="$rollback_parent" run_wrapper --run "$root/rollback-run.out"
MOCK_SELECTED_ARTIFACT_PARENT="$rollback_parent" run_wrapper --rollback "$root/rollback.out"
rollback_evidence="$rollback_parent/emceedanko-v1.3.1-promotion-current"
grep -Fxq 'script_10_v1_3_1_promotion=pass' "$root/rollback.out"
[[ -f "$rollback_evidence/promotion-receipt.txt" && -f "$rollback_evidence/rollback-receipt.txt" ]]
(cd -- "$rollback_evidence" && sha256sum --check --strict SHA256SUMS >/dev/null)

manifest_before="$(sha256sum -- "$evidence/SHA256SUMS" | awk '{print $1}')"
set +e
MOCK_TARGET_FAIL=1 run_wrapper --run "$root/target-failure.out"
target_failure_status="$?"
set -e
(( target_failure_status != 0 ))
grep -Fq 'reason=v1_3_1_launch_failed' "$root/target-failure.out"
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
  ISHIKAWA_SCRIPT10_REPORT_ROOT="$root/reports" \
  ISHIKAWA_SCRIPT10_ARTIFACT_PARENT="$root/interrupted-artifacts" \
  ISHIKAWA_SCRIPT10_SCRIPT09_EVIDENCE="$root/script09" \
  MOCK_ARTIFACT_PARENT="$root/interrupted-artifacts" \
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
find /tmp -maxdepth 1 -type d -name 'ishikawa-promotion-20*' -user "$(id -u)" -print -quit | grep -q . && exit 1

printf '%s\n' 'v1_3_1_promotion_wrapper_harness=pass;validate=pass;run=pass;accept=pass;rollback=pass;wsl_publication=pass;target_failure=pass;receipt_failure=pass;signal=pass;remote_cleanup=pass'
