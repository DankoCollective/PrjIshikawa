#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Exercise the Script 12 corrected-runtime target profile through run,
# acceptance, cleanup, and post-mutation failure cleanup with deterministic
# command doubles.

readonly test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$test_dir/../.." && pwd -P)"
readonly helper="$repo_root/deployment/assets/requalify-v1.3.1-on-emceedanko"
readonly application="$repo_root/local/artifacts/ishikawa-v1.3.1-candidate-current/ishikawa-v1.3.1.tar.gz"
readonly identity="$repo_root/local/artifacts/node-next-runtime-current/image-identity.json"
readonly evaluator="$repo_root/qualification/frontier/evaluate-frontier.py"
readonly cases="$repo_root/qualification/frontier/frontier-cases.json"
readonly profile='runtime-refresh'
readonly expected_runtime_archive_sha256='b92dd71eb155493d7e331e85c92566eee113ed4c8f0eda605c1c3dd951b836e1'
readonly expected_image_id='sha256:6c93bcb5ed22de92420c4de4892eecdd08f1badc8b19e4d6f4488711f8f7a31a'
readonly accepted_relative='Documents/Ishikawa-v1.3.1'
readonly candidate_relative='Documents/Ishikawa-v1.3.1-runtime-qualification'
readonly qualification_slug='v1.3.1-runtime-qualification'
readonly run_marker='v1_3_1_runtime_requalification=pass'
readonly accept_marker='v1_3_1_runtime_requalification_acceptance=pass'
readonly cleanup_marker='v1_3_1_runtime_requalification_cleanup=pass'

root="$(mktemp -d /tmp/ishikawa-requalification-target-test.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT
  if (( status != 0 )); then
    for output in "$root"/*.out; do
      [[ -f "$output" ]] || continue
      printf '%s\n' "--- ${output##*/} ---" >&2
      tail -n 80 "$output" >&2 || true
    done
  fi
  if [[ -f "$root/home/$candidate_relative/state/run/$qualification_slug.pid" ]]; then
    pid="$(<"$root/home/$candidate_relative/state/run/$qualification_slug.pid")"
    [[ "$pid" =~ ^[0-9]+$ ]] && kill -TERM "$pid" 2>/dev/null || true
  fi
  rm -rf -- "$root"
  exit "$status"
}
trap cleanup EXIT

mkdir -p -- "$root/bin" "$root/state" "$root/home/$accepted_relative"
printf '%s\n' accepted-v1.3.1-unchanged >"$root/home/$accepted_relative/sentinel"

make_mock() {
  local name="$1"
  shift
  printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' "$@" >"$root/bin/$name"
  chmod 0755 "$root/bin/$name"
}

make_mock hostname '[[ "${1:-}" == -s ]] && printf "%s\n" EmceeDanko'
make_mock dpkg '[[ "${1:-}" == --print-architecture ]] && printf "%s\n" amd64'
make_mock pg_isready 'exit 0'
make_mock psql '
if [[ "${MOCK_BAD_DATABASE:-0}" == 1 ]]; then
  printf "%s\n" "rag_retrieval;on;29;145;780;930;150;930;230;85"
else
  printf "%s\n" "rag_retrieval;on;30;150;786;943;157;943;240;90"
fi'
make_mock systemctl '
if [[ "${1:-}" == --user ]]; then shift; fi
case "${1:-}" in
  is-enabled) printf "%s\n" disabled; exit 1 ;;
  *) exit 0 ;;
esac'
make_mock sudo '
if [[ "${1:-}" == -v ]]; then exit 0; fi
exec "$@"'
make_mock ss '
if [[ -n "${MOCK_OCCUPIED_PORT:-}" && "$*" == *":${MOCK_OCCUPIED_PORT}"* ]]; then
  printf "%s\n" LISTEN
fi'
make_mock curl '
if [[ "$*" == *"%{http_code}"* ]]; then
  if [[ "${MOCK_ACCEPTED_API_FAIL:-0}" == 1 && "$*" == *"127.0.0.1:8384/ready"* ]]; then
    printf 503
  else
    printf 200
  fi
fi
exit 0'
make_mock docker '
state="${MOCK_STATE:?}"
command="${1:-}"; shift || true
case "$command" in
  info) exit 0 ;;
  image)
    [[ "${1:-}" == inspect ]] || exit 1
    if [[ "$*" == *Architecture* ]]; then printf "%s\n" amd64; else printf "%s\n" "${MOCK_IMAGE_ID:?}"; fi
    ;;
  inspect)
    if [[ "${1:-}" == --format ]]; then
      format="$2"
      if [[ "$format" == *State.Running* ]]; then
        [[ -f "$state/container.running" ]] && printf "%s\n" true || printf "%s\n" false
      elif [[ "$format" == *HostConfig.Tmpfs* ]]; then
        printf "%s\n" "rw,nosuid,nodev,size=536870912,mode=0700,uid=1000,gid=1000"
      fi
      exit 0
    fi
    [[ -f "$state/container.exists" ]]
    ;;
  run)
    if [[ " $* " == *" --detach "* ]]; then
      : >"$state/container.exists"
      if [[ "${MOCK_FAIL_WEB:-0}" != 1 ]]; then : >"$state/container.running"; fi
      printf "%s\n" mock-container-id
    fi
    ;;
  logs)
    if [[ "${MOCK_FAIL_WEB:-0}" == 1 ]]; then
      printf "%s\n" "mock production build failure"
    else
      printf "%s\n" "[RUNTIME] stage=build;state=start" "[RUNTIME] stage=build;state=pass" "[RUNTIME] stage=server;state=start"
    fi
    ;;
  exec) printf "%s\n" "123456 /opt/nextjs/.next" ;;
  stop) rm -f -- "$state/container.running" ;;
  rm) rm -f -- "$state/container.running" "$state/container.exists" ;;
  *) exit 1 ;;
esac'
make_mock python3 '
real_python=/usr/bin/python3
for argument in "$@"; do
  if [[ "$argument" == */scripts/ishikawa-retrieval-api ]]; then
    script_path="$argument"
    if [[ "$*" == *" --check-readiness"* ]]; then
      printf "%s\n" "ishikawa_retrieval_api_readiness=pass;configuration=pass;storage=pass;postgresql=pass;gemma=pass;nomic=pass"
      exit 0
    fi
    if [[ "$*" == *" --serve"* ]]; then
      exec -a "$script_path --serve" sleep 10000
    fi
  fi
  if [[ "$argument" == */evaluate-frontier.py ]]; then
    output=""
    previous=""
    for value in "$@"; do
      [[ "$previous" != --output ]] || output="$value"
      previous="$value"
    done
    if [[ "${MOCK_FRONTIER_FAIL:-0}" == 1 ]]; then
      printf "%s\n" "v1_3_complete_api_evaluation=blocked;reason=mock_frontier_failure"
      exit 7
    fi
    printf "%s\n" "{\"summary\":\"synthetic-pass\"}" >"$output"
    printf "%s\n" \
      "v1_3_complete_api_evaluation=pass" \
      "complete_api_cases=60;expected_status_matches=60/60;required_evidence_returned=60/60;required_evidence_cited=60/60;dependency_failures=0"
    exit 0
  fi
done
exec "$real_python" "$@"'

payload="$root/payload"
mkdir -p -- "$payload"
cp -- "$application" "$payload/ishikawa-v1.3.1.tar.gz"
cp -- "$identity" "$payload/image-identity.json"
cp -- "$evaluator" "$payload/evaluate-frontier.py"
cp -- "$cases" "$payload/frontier-cases.json"
cp -- "$helper" "$payload/requalify-v1.3.1-on-emceedanko"
(
  cd -- "$payload"
  find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' | sort \
    | xargs sha256sum -- >SHA256SUMS
)
helper_sha="$(sha256sum -- "$payload/requalify-v1.3.1-on-emceedanko" | awk '{print $1}')"

run_helper() {
  local selected_mode="$1" result="$2" output="$3"
  shift 3
  printf '%s\n' gemma-test-key nomic-test-key-000000000000000000000000 v1.3-test-password-000000000000 \
    | script -qefc "env HOME='$root/home' PATH='$root/bin:/usr/bin:/bin' MOCK_STATE='$root/state' MOCK_IMAGE_ID='$expected_image_id' ISHIKAWA_REQUALIFICATION_PROFILE='$profile' $* bash '$payload/requalify-v1.3.1-on-emceedanko' '$selected_mode' --payload-root '$payload' --result-path '$result' --expected-hostname EmceeDanko --expected-os-version 24.04 --expected-architecture amd64 --expected-helper-sha256 '$helper_sha'" /dev/null \
      >"$output" 2>&1
}

reset_payload() {
  rm -rf -- "$payload/extracted"
  find "$payload" -maxdepth 1 -type f \
    \( -name '*-result.txt' -o -name 'frontier-result.json' \) -delete
  (
    cd -- "$payload"
    find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' | sort \
      | xargs sha256sum -- >SHA256SUMS
  )
}

run_helper --run "$payload/run-result.txt" "$root/run.out"
grep -Fq "$run_marker" "$root/run.out"
grep -Fxq 'human_ui_acceptance=pending' "$payload/run-result.txt"
grep -Fxq 'accepted-v1.3.1-unchanged' "$root/home/$accepted_relative/sentinel"
[[ -d "$root/home/$candidate_relative" && -f "$root/state/container.running" ]]

run_helper --accept "$payload/accept-result.txt" "$root/accept.out"
grep -Fq "$accept_marker" "$root/accept.out"
grep -Fxq 'human_ui_acceptance=accepted' "$payload/accept-result.txt"

run_helper --cleanup "$payload/cleanup-result.txt" "$root/cleanup.out"
grep -Fq "$cleanup_marker" "$root/cleanup.out"
[[ ! -e "$root/home/$candidate_relative" && ! -e "$root/state/container.exists" ]]
grep -Fxq 'accepted-v1.3.1-unchanged' "$root/home/$accepted_relative/sentinel"

reset_payload
set +e
run_helper --run "$payload/baseline-failure-result.txt" "$root/baseline-failure.out" 'MOCK_ACCEPTED_API_FAIL=1'
baseline_failure_status="$?"
set -e
(( baseline_failure_status != 0 ))
grep -Fq 'reason=accepted_v1_3_1_baseline_not_ready' "$root/baseline-failure.out"
grep -Fq 'installation=pass;api_ready_http=503;ui_ready_http=200;postgresql=pass' "$root/baseline-failure.out"
[[ ! -e "$root/home/$candidate_relative" && ! -e "$root/state/container.exists" ]]

reset_payload
set +e
run_helper --run "$payload/failure-result.txt" "$root/failure.out" 'MOCK_FAIL_WEB=1'
failure_status="$?"
set -e
(( failure_status != 0 ))
grep -Fq 'reason=candidate_web_build_failed' "$root/failure.out"
grep -Fxq 'state=blocked' "$payload/failure-result.txt"
grep -Fxq 'detail=cleanup_failed=false' "$payload/failure-result.txt"
[[ ! -e "$root/home/$candidate_relative" && ! -e "$root/state/container.exists" ]]
grep -Fxq 'accepted-v1.3.1-unchanged' "$root/home/$accepted_relative/sentinel"

reset_payload
set +e
run_helper --run "$payload/database-failure-result.txt" "$root/database-failure.out" 'MOCK_BAD_DATABASE=1'
database_failure_status="$?"
set -e
(( database_failure_status != 0 ))
grep -Fq 'reason=accepted_database_inventory_mismatch' "$root/database-failure.out"
[[ ! -e "$root/home/$candidate_relative" && ! -e "$root/state/container.exists" ]]

reset_payload
set +e
run_helper --run "$payload/frontier-failure-result.txt" "$root/frontier-failure.out" 'MOCK_FRONTIER_FAIL=1'
frontier_failure_status="$?"
set -e
(( frontier_failure_status != 0 ))
grep -Fq 'reason=frontier_gate_failed' "$root/frontier-failure.out"
grep -Fxq 'detail=cleanup_failed=false' "$payload/frontier-failure-result.txt"
[[ ! -e "$root/home/$candidate_relative" && ! -e "$root/state/container.exists" ]]
grep -Fxq 'accepted-v1.3.1-unchanged' "$root/home/$accepted_relative/sentinel"

printf '%s\n' 'v1_3_1_runtime_requalification_target_harness=pass;run=pass;accept=pass;cleanup=pass;baseline_diagnostic=pass;web_failure_cleanup=pass;database_mismatch=pass;frontier_failure_cleanup=pass'
