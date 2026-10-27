#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Exercise the complete Script 13 target lifecycle with deterministic command
# doubles. No real target, credential, model, database, or container is used.

readonly test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$test_dir/../.." && pwd -P)"
readonly helper="$repo_root/deployment/assets/promote-corrected-runtime-on-emceedanko"
readonly identity="$repo_root/local/artifacts/node-next-runtime-current/image-identity.json"
readonly baseline="$repo_root/local/artifacts/emceedanko-v1.3.1-promotion-current/acceptance-receipt.txt"
readonly script12="$repo_root/local/artifacts/emceedanko-v1.3.1-runtime-requalification-current"
readonly old_image='sha256:79f39435329920c9c834e55cf5e18528540220111ae2a35d779a86d0b539d298'
readonly new_image='sha256:6c93bcb5ed22de92420c4de4892eecdd08f1badc8b19e4d6f4488711f8f7a31a'

root="$(mktemp -d /tmp/ishikawa-runtime-promotion-target-test.XXXXXX)"
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
  rm -rf -- "$root"
  exit "$status"
}
trap cleanup EXIT
mkdir -p -- "$root/bin" "$root/state"

make_mock() {
  local name="$1"
  shift
  printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' "$@" >"$root/bin/$name"
  chmod 0755 "$root/bin/$name"
}

make_mock hostname '[[ "${1:-}" == -s ]] && printf "%s\n" EmceeDanko'
make_mock dpkg '[[ "${1:-}" == --print-architecture ]] && printf "%s\n" amd64'
make_mock pg_isready 'exit 0'
make_mock systemctl '
if [[ "${1:-}" == --user ]]; then shift; fi
case "${1:-}" in is-enabled) printf "%s\n" disabled; exit 1 ;; *) exit 0 ;; esac'
make_mock sudo '
if [[ "${1:-}" == -v ]]; then exit 0; fi
exec "$@"'
make_mock ss '
if [[ -n "${MOCK_OCCUPIED_PORT:-}" && "$*" == *":${MOCK_OCCUPIED_PORT}"* ]]; then
  printf "%s\n" LISTEN
fi'
make_mock curl '
if [[ "$*" == *"%{http_code}"* ]]; then
  if [[ "${MOCK_API_FAIL:-0}" == 1 && "$*" == *"127.0.0.1:8384/ready"* ]]; then
    printf 503
  else
    printf 200
  fi
fi
exit 0'
make_mock sha256sum '
last="${!#:-}"
case "$last" in
  */previous-node-next-runtime-amd64.tar)
    if [[ "${MOCK_BAD_PREVIOUS_ARCHIVE_HASH:-0}" == 1 ]]; then
      printf "%064d  %s\n" 0 "$last"
    else
      printf "%s  %s\n" af95820f63798b39c6538e3f9b5653d47b07aed1d81625e2382485ff559eff3f "$last"
    fi ;;
  */corrected-node-next-runtime-amd64.tar)
    printf "%s  %s\n" b92dd71eb155493d7e331e85c92566eee113ed4c8f0eda605c1c3dd951b836e1 "$last" ;;
  *) exec /usr/bin/sha256sum "$@" ;;
esac'
make_mock df '
if [[ "${MOCK_LOW_DOCKER_SPACE:-0}" == 1 ]]; then
  printf "%s\n" "Filesystem 1-blocks Used Available Use% Mounted on" "mock 1000 999 1 99% /mock"
else
  exec /usr/bin/df "$@"
fi'
make_mock python3 '
real_python=/usr/bin/python3
for argument in "$@"; do
  if [[ "$argument" == */config/product.yaml ]]; then
    printf "%s\n" "Ishikawa" "fixture-browser-configuration"
    exit 0
  fi
done
exec "$real_python" "$@"'
make_mock docker '
state="${MOCK_STATE:?}"
old_image="${MOCK_OLD_IMAGE:?}"
new_image="${MOCK_NEW_IMAGE:?}"
exists() { [[ -f "$state/container.$1.exists" ]]; }
running() { [[ -f "$state/container.$1.running" ]]; }
container_image() { [[ -f "$state/container.$1.image" ]] && cat "$state/container.$1.image"; }
command="${1:-}"; shift || true
case "$command" in
  info)
    if [[ "$*" == *DockerRootDir* ]]; then printf "%s\n" "$state"; fi
    exit 0
    ;;
  load)
    archive=""
    while (( $# > 0 )); do
      case "$1" in --input) archive="$2"; shift 2 ;; *) shift ;; esac
    done
    case "$archive" in
      */previous-node-next-runtime-amd64.tar)
        [[ "${MOCK_FAIL_PREVIOUS_LOAD:-0}" != 1 ]] || exit 51
        [[ "${MOCK_BAD_PREVIOUS_AFTER_LOAD:-0}" == 1 ]] || rm -f -- "$state/old-image.removed"
        printf "%s\n" previous >>"$state/load-order"
        ;;
      */corrected-node-next-runtime-amd64.tar)
        [[ "${MOCK_FAIL_CORRECTED_LOAD:-0}" != 1 ]] || exit 52
        [[ "${MOCK_BAD_CORRECTED_AFTER_LOAD:-0}" == 1 ]] || rm -f -- "$state/new-image.removed"
        printf "%s\n" corrected >>"$state/load-order"
        ;;
      *) exit 1 ;;
    esac
    ;;
  image)
    sub="${1:-}"; shift || true
    case "$sub" in
      inspect)
        reference="${1:-}"
        if [[ "$reference" == "$old_image" && -f "$state/old-image.removed" ]]; then exit 1; fi
        if [[ "$reference" == "$new_image" && -f "$state/new-image.removed" ]]; then exit 1; fi
        if [[ "$reference" == node-next-runtime:24.22.1-next16.4.3-react19.2.9-amd64 ]]; then
          [[ ! -f "$state/new-image.removed" ]] || exit 1
          reference="$new_image"
        fi
        [[ "$reference" == "$old_image" || "$reference" == "$new_image" ]] || exit 1
        if [[ "$*" == *Architecture* ]]; then printf "%s\n" amd64; else printf "%s\n" "$reference"; fi
        ;;
      rm)
        [[ "${MOCK_IMAGE_RM_FAIL:-0}" != 1 ]] || exit 44
        [[ "${1:-}" == "$old_image" ]] || exit 1
        : >"$state/old-image.removed"
        ;;
      tag)
        [[ "${1:-}" == "$new_image" ]] || exit 1
        rm -f -- "$state/new-image.removed"
        ;;
      *) exit 1 ;;
    esac
    ;;
  inspect)
    if [[ "${1:-}" == --format ]]; then
      format="$2"; name="$3"
      if [[ "$format" == *"name={{.Name}}"* ]]; then
        if [[ "$name" == unknown-old-consumer ]]; then
          printf "name=/unknown-old-consumer;running=true;image=%s\n" "$old_image"
        else
          printf "name=/%s;running=%s;image=%s\n" "$name" "$(running "$name" && printf true || printf false)" "$(container_image "$name")"
        fi
      elif [[ "$format" == *State.Running* ]]; then
        running "$name" && printf "%s\n" true || printf "%s\n" false
      elif [[ "$format" == *HostConfig.Tmpfs* ]]; then printf "%s\n" "rw,nosuid,nodev,size=536870912,mode=0700,uid=1000,gid=1000"
      elif [[ "$format" == *Config.User* ]]; then printf "%s:%s\n" "$(id -u)" "$(id -g)"
      elif [[ "$format" == *ReadonlyRootfs* ]]; then printf "%s\n" true
      elif [[ "$format" == *NetworkMode* ]]; then printf "%s\n" host
      elif [[ "$format" == *RestartPolicy.Name* ]]; then printf "%s\n" no
      elif [[ "$format" == *PidsLimit* ]]; then printf "%s\n" 512
      elif [[ "$format" == *CapDrop* ]]; then printf "%s\n" "[\"ALL\"]"
      elif [[ "$format" == *SecurityOpt* ]]; then printf "%s\n" "[\"no-new-privileges\"]"
      elif [[ "$format" == *Image* ]]; then container_image "$name"
      fi
      exit 0
    fi
    exists "${1:-}"
    ;;
  run)
    if [[ " $* " == *" --rm "* && " $* " != *" --name "* ]]; then exit 0; fi
    name=""; previous=""; image=""
    for value in "$@"; do
      [[ "$previous" != --name ]] || name="$value"
      [[ "$value" != "$old_image" && "$value" != "$new_image" ]] || image="$value"
      previous="$value"
    done
    [[ -n "$name" && -n "$image" ]] || exit 1
    : >"$state/container.$name.exists"
    printf "%s\n" "$image" >"$state/container.$name.image"
    if [[ !( "$image" == "$new_image" && "${MOCK_FAIL_CORRECTED:-0}" == 1 ) ]]; then
      : >"$state/container.$name.running"
    fi
    printf "%s\n" mock-container-id
    ;;
  logs)
    name="${*: -1}"; image="$(container_image "$name")"
    if [[ "$image" == "$new_image" && "${MOCK_FAIL_CORRECTED:-0}" == 1 ]]; then
      printf "%s\n" "mock corrected build failure"
    else
      printf "%s\n" "[RUNTIME] stage=build;state=start" "[RUNTIME] stage=build;state=pass" "[RUNTIME] stage=server;state=start"
    fi
    ;;
  stop)
    name="${*: -1}"; rm -f -- "$state/container.$name.running"
    ;;
  rm)
    name="${*: -1}"
    rm -f -- "$state/container.$name.running" "$state/container.$name.exists" "$state/container.$name.image"
    ;;
  ps)
    [[ "${MOCK_OLD_CONSUMER:-0}" != 1 ]] || printf "%s\n" unknown-old-consumer
    ;;
  *) exit 1 ;;
esac'

payload="$root/payload"
mkdir -p -- "$payload"
cp -- "$identity" "$payload/image-identity.json"
printf '%s\n' previous-runtime-fixture >"$payload/previous-node-next-runtime-amd64.tar"
printf '%s\n' corrected-runtime-fixture >"$payload/corrected-node-next-runtime-amd64.tar"
cp -- "$baseline" "$payload/baseline-acceptance-receipt.txt"
cp -- "$script12/qualification-receipt.txt" \
  "$script12/acceptance-receipt.txt" \
  "$script12/cleanup-receipt.txt" "$payload/"
cp -- "$helper" "$payload/promote-corrected-runtime-on-emceedanko"
helper_sha="$(sha256sum -- "$payload/promote-corrected-runtime-on-emceedanko" | awk '{print $1}')"

application_fixture="$root/home/Documents/Ishikawa-v1.3.1"

refresh_payload() {
  find "$payload" -maxdepth 1 -type f -name '*-result.txt' -delete
  (
    cd -- "$application_fixture"
    {
      find application/web/app application/web/components application/web/lib application/web/public -type f -print
      printf '%s\n' application/web/package.json application/web/next.config.mjs config/product.yaml
    } | sort >"$payload/web-layout-paths.txt"
    while IFS= read -r path; do sha256sum -- "$path"; done \
      <"$payload/web-layout-paths.txt" >"$payload/web-layout-SHA256SUMS"
  )
  (
    cd -- "$payload"
    find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' | sort | xargs sha256sum -- >SHA256SUMS
  )
}

reset_fixture() {
  rm -rf -- "$root/home" "$root/state"
  mkdir -p -- \
    "$root/state" \
    "$application_fixture/application/web/app" \
    "$application_fixture/application/web/components" \
    "$application_fixture/application/web/lib" \
    "$application_fixture/application/web/public" \
    "$application_fixture/application/python" \
    "$application_fixture/config" \
    "$application_fixture/state/logs" \
    "$application_fixture/state/reports/promotion"
  printf '%s\n' fixture-page >"$application_fixture/application/web/app/page.js"
  printf '%s\n' fixture-component >"$application_fixture/application/web/components/chat.js"
  printf '%s\n' fixture-lib >"$application_fixture/application/web/lib/runtime.mjs"
  printf '%s\n' fixture-public >"$application_fixture/application/web/public/theme-init.js"
  printf '%s\n' '{}' >"$application_fixture/application/web/package.json"
  printf '%s\n' 'export default {}' >"$application_fixture/application/web/next.config.mjs"
  printf '%s\n' '{}' >"$application_fixture/config/product.yaml"
  cp -- "$baseline" "$application_fixture/state/reports/promotion/emceedanko-v1.3.1-acceptance.txt"
  : >"$root/state/container.ishikawa-v1.3.1-web.exists"
  : >"$root/state/container.ishikawa-v1.3.1-web.running"
  printf '%s\n' "$old_image" >"$root/state/container.ishikawa-v1.3.1-web.image"
  refresh_payload
}

run_helper() {
  local selected_mode="$1" result="$2" output="$3"
  shift 3
  env HOME="$root/home" PATH="$root/bin:/usr/bin:/bin" \
    MOCK_STATE="$root/state" MOCK_OLD_IMAGE="$old_image" MOCK_NEW_IMAGE="$new_image" \
    "$@" bash "$payload/promote-corrected-runtime-on-emceedanko" "$selected_mode" \
      --payload-root "$payload" --result-path "$result" \
      --expected-hostname EmceeDanko --expected-os-version 24.04 \
      --expected-architecture amd64 --expected-helper-sha256 "$helper_sha" \
      >"$output" 2>&1
}

reset_fixture
touch "$root/state/old-image.removed"
run_helper --run "$payload/image-restore-result.txt" "$root/image-restore.out"
grep -Fq 'action=restored;previous=exact;corrected=exact' "$root/image-restore.out"
[[ ! -e "$root/state/old-image.removed" ]]
printf '%s\n' previous corrected | cmp -- "$root/state/load-order" - >/dev/null
grep -Fxq "$new_image" "$root/state/container.ishikawa-v1.3.1-web.image"

for failure_case in bad_hash low_capacity old_load old_identity corrected_load corrected_identity; do
  reset_fixture
  touch "$root/state/old-image.removed"
  case "$failure_case" in
    bad_hash) failure_env=(MOCK_BAD_PREVIOUS_ARCHIVE_HASH=1); expected_status=11 ;;
    low_capacity) failure_env=(MOCK_LOW_DOCKER_SPACE=1); expected_status=14 ;;
    old_load) failure_env=(MOCK_FAIL_PREVIOUS_LOAD=1); expected_status=15 ;;
    old_identity) failure_env=(MOCK_BAD_PREVIOUS_AFTER_LOAD=1); expected_status=16 ;;
    corrected_load) failure_env=(MOCK_FAIL_CORRECTED_LOAD=1); expected_status=17 ;;
    corrected_identity)
      touch "$root/state/new-image.removed"
      failure_env=(MOCK_BAD_CORRECTED_AFTER_LOAD=1)
      expected_status=18
      ;;
  esac
  set +e
  run_helper --run "$payload/image-${failure_case}-result.txt" \
    "$root/image-${failure_case}.out" "${failure_env[@]}"
  failure_status="$?"
  set -e
  (( failure_status != 0 ))
  grep -Fq 'reason=runtime_image_preparation_failed' "$root/image-${failure_case}.out"
  grep -Fq "status $expected_status" "$root/image-${failure_case}.out"
  grep -Fq 'previous_runtime_restored=false' "$root/image-${failure_case}.out"
  grep -Fxq "$old_image" "$root/state/container.ishikawa-v1.3.1-web.image"
done

reset_fixture
rm -f -- "$payload/previous-node-next-runtime-amd64.tar"
refresh_payload
set +e
run_helper --run "$payload/image-missing-result.txt" "$root/image-missing.out"
missing_archive_status="$?"
set -e
(( missing_archive_status != 0 ))
grep -Fq 'reason=runtime_archives_missing' "$root/image-missing.out"
grep -Fxq "$old_image" "$root/state/container.ishikawa-v1.3.1-web.image"
printf '%s\n' previous-runtime-fixture >"$payload/previous-node-next-runtime-amd64.tar"
refresh_payload

reset_fixture
run_helper --run "$payload/run-result.txt" "$root/run.out"
grep -Fq 'v1_3_1_corrected_runtime_promotion=pass' "$root/run.out"
grep -Fxq 'human_ui_acceptance=pending' "$payload/run-result.txt"
grep -Fxq "$new_image" "$root/state/container.ishikawa-v1.3.1-web.image"
grep -Fxq fixture-page "$application_fixture/application/web/app/page.js"

refresh_payload
run_helper --accept "$payload/accept-result.txt" "$root/accept.out"
grep -Fq 'v1_3_1_corrected_runtime_promotion_acceptance=pass' "$root/accept.out"
grep -Fxq 'human_ui_acceptance=accepted' "$payload/accept-result.txt"
[[ -f "$root/state/old-image.removed" ]]

refresh_payload
run_helper --accept "$payload/accept-repeat-result.txt" "$root/accept-repeat.out"
grep -Fq 'human_ui_acceptance=already_recorded' "$root/accept-repeat.out"

reset_fixture
run_helper --run "$payload/rollback-run-result.txt" "$root/rollback-run.out"
refresh_payload
run_helper --rollback "$payload/rollback-result.txt" "$root/rollback.out"
grep -Fq 'v1_3_1_corrected_runtime_promotion_rollback=pass' "$root/rollback.out"
grep -Fxq 'detail=previous_runtime_restored=true' "$payload/rollback-result.txt"
grep -Fxq "$old_image" "$root/state/container.ishikawa-v1.3.1-web.image"
[[ ! -e "$application_fixture/state/reports/runtime-promotion/emceedanko-v1.3.1-corrected-runtime-promotion.txt" ]]

reset_fixture
set +e
run_helper --run "$payload/launch-failure-result.txt" "$root/launch-failure.out" MOCK_FAIL_CORRECTED=1
launch_failure_status="$?"
set -e
(( launch_failure_status != 0 ))
grep -Fq 'reason=corrected_web_launch_failed' "$root/launch-failure.out"
grep -Fq 'previous_runtime_restored=true' "$root/launch-failure.out"
grep -Fxq "$old_image" "$root/state/container.ishikawa-v1.3.1-web.image"

reset_fixture
set +e
run_helper --run "$payload/baseline-failure-result.txt" "$root/baseline-failure.out" MOCK_API_FAIL=1
baseline_failure_status="$?"
set -e
(( baseline_failure_status != 0 ))
grep -Fq 'reason=accepted_runtime_not_ready' "$root/baseline-failure.out"
grep -Fq 'previous_runtime_restored=false' "$root/baseline-failure.out"
grep -Fxq "$old_image" "$root/state/container.ishikawa-v1.3.1-web.image"

reset_fixture
printf '%s\n' changed-page >"$application_fixture/application/web/app/page.js"
set +e
run_helper --run "$payload/layout-failure-result.txt" "$root/layout-failure.out"
layout_failure_status="$?"
set -e
(( layout_failure_status != 0 ))
grep -Fq 'reason=installed_web_layout_mismatch' "$root/layout-failure.out"
grep -Fxq "$old_image" "$root/state/container.ishikawa-v1.3.1-web.image"

reset_fixture
printf '%s\n' unexpected-route >"$application_fixture/application/web/app/unexpected.js"
set +e
run_helper --run "$payload/path-failure-result.txt" "$root/path-failure.out"
path_failure_status="$?"
set -e
(( path_failure_status != 0 ))
grep -Fq 'reason=installed_web_path_set_mismatch' "$root/path-failure.out"
grep -Fxq "$old_image" "$root/state/container.ishikawa-v1.3.1-web.image"

reset_fixture
run_helper --run "$payload/consumer-run-result.txt" "$root/consumer-run.out"
refresh_payload
set +e
run_helper --accept "$payload/consumer-accept-result.txt" "$root/consumer-accept.out" MOCK_OLD_CONSUMER=1
consumer_status="$?"
set -e
(( consumer_status != 0 ))
grep -Fq 'reason=superseded_image_in_use' "$root/consumer-accept.out"
grep -Fxq "$new_image" "$root/state/container.ishikawa-v1.3.1-web.image"
[[ ! -e "$root/state/old-image.removed" ]]

reset_fixture
run_helper --run "$payload/removal-run-result.txt" "$root/removal-run.out"
refresh_payload
set +e
run_helper --accept "$payload/removal-result.txt" "$root/removal.out" MOCK_IMAGE_RM_FAIL=1
removal_status="$?"
set -e
(( removal_status != 0 ))
grep -Fq 'reason=superseded_image_removal_failed' "$root/removal.out"
grep -Fxq "$new_image" "$root/state/container.ishikawa-v1.3.1-web.image"
[[ ! -e "$application_fixture/state/reports/runtime-promotion/emceedanko-v1.3.1-corrected-runtime-acceptance.txt" ]]

printf '%s\n' 'v1_3_1_corrected_runtime_promotion_target_harness=pass;image_restoration=pass;archive_refusal=pass;capacity_refusal=pass;load_refusal=pass;identity_refusal=pass;run=pass;accept=pass;idempotent_accept=pass;rollback=pass;automatic_restoration=pass;baseline_refusal=pass;layout_refusal=pass;path_set_refusal=pass;consumer_refusal=pass;removal_failure=pass'
