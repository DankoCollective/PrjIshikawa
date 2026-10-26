#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Exercise Script 09 end to end through its SSH/transfer/report/evidence
# orchestration without contacting a real target.

readonly test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$test_dir/../.." && pwd -P)"
readonly wrapper="$repo_root/deployment/scripts/09_requalify-v1.3.1-on-emceedanko.sh"
root="$(mktemp -d /tmp/ishikawa-script-09-wrapper-test.XXXXXX)"
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
    --run) marker=v1_3_1_requalification=pass; schema=ishikawa.emceedanko-v1.3.1-qualification.v1 ;;
    --accept) marker=v1_3_1_requalification_acceptance=pass; schema=ishikawa.emceedanko-v1.3.1-acceptance.v1 ;;
    --cleanup) marker=v1_3_1_requalification_cleanup=pass; schema=ishikawa.emceedanko-v1.3.1-action.v1 ;;
    *) exit 20 ;;
  esac
  {
    printf "schema=%s\n" "$schema"
    printf "%s\n" \
      "application_archive_sha256=2dbf08b9e15fb4436e54ce492f2ad430129e794d33a1a45cdc6abf1a7b0b5f69" \
      "runtime_archive_sha256=af95820f63798b39c6538e3f9b5653d47b07aed1d81625e2382485ff559eff3f" \
      "image_id=sha256:79f39435329920c9c834e55cf5e18528540220111ae2a35d779a86d0b539d298" \
      "accepted_v1_3_mutated=false" "accepted_database_mutated=false" "boot_autostart=false"
    [[ "$mode" != --run ]] || printf "%s\n" "human_ui_acceptance=pending"
    [[ "$mode" != --accept ]] || printf "%s\n" "human_ui_acceptance=accepted"
  } >"$payload"
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
  cp -- "${source_path#*:}" "$destination"
else
  cp -- "$source_path" "${destination#*:}"
fi' >"$root/bin/scp"
chmod 0755 "$root/bin/ssh" "$root/bin/scp"

run_wrapper() {
  local selected_mode="$1" output="$2"
  shift 2
  PATH="$root/bin:$PATH" \
  ISHIKAWA_SCRIPT09_REPORT_ROOT="$root/reports" \
  ISHIKAWA_SCRIPT09_ARTIFACT_PARENT="$root/artifacts" \
  MOCK_TARGET_FAIL="${MOCK_TARGET_FAIL:-0}" MOCK_BAD_RECEIPT="${MOCK_BAD_RECEIPT:-0}" \
    bash "$wrapper" "$selected_mode" --target FakeEmcee "$@" >"$output" 2>&1
}

validation="$(PATH="$root/bin:$PATH" \
  ISHIKAWA_SCRIPT09_ARTIFACT_PARENT="$root/artifacts" \
  bash "$wrapper" --validate-only --target FakeEmcee)"
grep -Fxq 'script_09_v1_3_1_requalification=ready' <<<"$validation"
grep -Fq 'target_contact=false' <<<"$validation"

run_wrapper --run "$root/run.out"
grep -Fxq 'script_09_v1_3_1_requalification=pass' "$root/run.out"
evidence="$root/artifacts/emceedanko-v1.3.1-requalification-current"
[[ -f "$evidence/qualification-receipt.txt" && ! -e "$evidence/acceptance-receipt.txt" ]]
(cd -- "$evidence" && sha256sum --check --strict SHA256SUMS >/dev/null)

run_wrapper --accept "$root/accept.out"
grep -Fxq 'script_09_v1_3_1_requalification=pass' "$root/accept.out"
[[ -f "$evidence/qualification-receipt.txt" && -f "$evidence/acceptance-receipt.txt" ]]
(cd -- "$evidence" && sha256sum --check --strict SHA256SUMS >/dev/null)

run_wrapper --cleanup "$root/cleanup.out"
grep -Fxq 'script_09_v1_3_1_requalification=pass' "$root/cleanup.out"
[[ -f "$evidence/cleanup-receipt.txt" ]]
(cd -- "$evidence" && sha256sum --check --strict SHA256SUMS >/dev/null)

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
printf '%s\n' 'v1_3_1_requalification_wrapper_harness=pass;validate=pass;run=pass;accept=pass;cleanup=pass;target_failure=pass;receipt_failure=pass'
