#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Exercise Script 10 target promotion, acceptance/finalization, explicit
# rollback, automatic failed-launch restoration, and refusal branches.

readonly test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$test_dir/../.." && pwd -P)"
readonly helper="$repo_root/deployment/assets/promote-v1.3.1-on-emceedanko"
readonly application="$repo_root/local/artifacts/ishikawa-v1.3.1-candidate-current/ishikawa-v1.3.1.tar.gz"
readonly identity="$repo_root/local/artifacts/node-next-runtime-current/image-identity.json"

root="$(mktemp -d /tmp/ishikawa-promotion-target-test.XXXXXX)"
cleanup() {
  local status="$?" pid=''
  trap - EXIT
  if (( status != 0 )); then
    for output in "$root"/*.out; do
      [[ -f "$output" ]] || continue
      printf '%s\n' "--- ${output##*/} ---" >&2
      tail -n 120 "$output" >&2 || true
    done
  fi
  while IFS= read -r pid_file; do
    IFS= read -r pid <"$pid_file" || pid=''
    [[ "$pid" =~ ^[0-9]+$ ]] && kill -TERM "$pid" 2>/dev/null || true
  done < <(find "$root/home" -type f -name '*.pid' 2>/dev/null || true)
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
make_mock psql '
[[ -n "${PGPASSWORD:-}" ]] || exit 97
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
if [[ "$*" == *"%{http_code}"* ]]; then printf 200; fi
exit 0'
make_mock pg_ctl '
state="${MOCK_STATE:?}"
case "$*" in
  *" status"*) [[ -f "$state/pg.running" ]] ;;
  *" stop"*) rm -f -- "$state/pg.running" ;;
  *" start"*) : >"$state/pg.running" ;;
  *) exit 1 ;;
esac'
make_mock python3 '
real_python=/usr/bin/python3
for argument in "$@"; do
  if [[ "$argument" == */scripts/ishikawa-retrieval-api ]]; then
    if [[ "$*" == *" --check-readiness"* ]]; then
      printf "%s\n" "ishikawa_retrieval_api_readiness=pass;configuration=pass;storage=pass;postgresql=pass;gemma=pass;nomic=pass"
      exit 0
    fi
    if [[ "$*" == *" --serve"* ]]; then
      exec -a "$argument --serve" sleep 10000
    fi
  fi
  if [[ "$argument" == */config/product.yaml ]]; then
    printf "%s\n" "Ishikawa" "fixture-browser-configuration"
    exit 0
  fi
done
exec "$real_python" "$@"'
make_mock docker '
state="${MOCK_STATE:?}"
exists() { [[ -f "$state/container.$1.exists" ]]; }
running() { [[ -f "$state/container.$1.running" ]]; }
command="${1:-}"; shift || true
case "$command" in
  info) exit 0 ;;
  image)
    sub="${1:-}"; shift || true
    case "$sub" in
      inspect)
        reference="${1:-}"
        if [[ ( "$reference" == node-24-slim-nextjs-16-4-1:amd64 \
              || "$reference" == sha256:368f4381b61bf90ad27aa5a9dd4c10e1de0b4b4666006911e1b6cb4aafcfb8a6 ) \
            && -f "$state/old-image.removed" ]]; then exit 1; fi
        if [[ "$*" == *Architecture* ]]; then printf "%s\n" amd64
        elif [[ "$reference" == node-24-slim-nextjs-16-4-1:amd64 \
            || "$reference" == sha256:368f4381b61bf90ad27aa5a9dd4c10e1de0b4b4666006911e1b6cb4aafcfb8a6 ]]; then printf "%s\n" "sha256:368f4381b61bf90ad27aa5a9dd4c10e1de0b4b4666006911e1b6cb4aafcfb8a6"
        else printf "%s\n" "sha256:79f39435329920c9c834e55cf5e18528540220111ae2a35d779a86d0b539d298"; fi
        ;;
      rm) : >"$state/old-image.removed" ;;
      *) exit 1 ;;
    esac
    ;;
  inspect)
    if [[ "${1:-}" == --format ]]; then
      format="$2"; name="$3"
      if [[ "$format" == *State.Running* ]]; then running "$name" && printf "%s\n" true || printf "%s\n" false
      elif [[ "$format" == *HostConfig.Tmpfs* ]]; then printf "%s\n" "rw,nosuid,nodev,size=536870912,mode=0700,uid=1000,gid=1000"
      elif [[ "$format" == *Config.User* ]]; then printf "%s:%s\n" "$(id -u)" "$(id -g)"
      elif [[ "$format" == *ReadonlyRootfs* ]]; then printf "%s\n" true
      elif [[ "$format" == *NetworkMode* ]]; then printf "%s\n" host
      elif [[ "$format" == *RestartPolicy.Name* ]]; then printf "%s\n" no
      elif [[ "$format" == *PidsLimit* ]]; then printf "%s\n" 512
      elif [[ "$format" == *CapDrop* ]]; then printf "%s\n" "[\"ALL\"]"
      elif [[ "$format" == *SecurityOpt* ]]; then printf "%s\n" "[\"no-new-privileges\"]"
      elif [[ "$format" == *Image* ]]; then
        if [[ "$name" == ishikawa-v1.3.1-web ]]; then
          printf "%s\n" "sha256:79f39435329920c9c834e55cf5e18528540220111ae2a35d779a86d0b539d298"
        else
          printf "%s\n" "sha256:368f4381b61bf90ad27aa5a9dd4c10e1de0b4b4666006911e1b6cb4aafcfb8a6"
        fi
      fi
      exit 0
    fi
    exists "${1:-}"
    ;;
  run)
    name=''
    previous=''
    for value in "$@"; do
      [[ "$previous" != --name ]] || name="$value"
      previous="$value"
    done
    [[ -n "$name" ]] || exit 1
    : >"$state/container.$name.exists"
    if [[ !( "$name" == ishikawa-v1.3.1-web && "${MOCK_FAIL_NEW_WEB:-0}" == 1 ) ]]; then
      : >"$state/container.$name.running"
    fi
    printf "%s\n" mock-container-id
    ;;
  logs)
    name="${*: -1}"
    if [[ "$name" == ishikawa-v1.3.1-web && "${MOCK_FAIL_NEW_WEB:-0}" == 1 ]]; then
      printf "%s\n" "mock build failure"
    else
      printf "%s\n" "[RUNTIME] stage=build;state=start" "[RUNTIME] stage=build;state=pass" "[RUNTIME] stage=server;state=start"
    fi
    ;;
  stop)
    name="${*: -1}"
    rm -f -- "$state/container.$name.running"
    ;;
  rm)
    name="${*: -1}"
    rm -f -- "$state/container.$name.running" "$state/container.$name.exists"
    ;;
  ps)
    [[ "${MOCK_OLD_CONSUMER:-0}" != 1 ]] || printf "%s\n" old-consumer-id
    ;;
  *) exit 1 ;;
esac'

payload="$root/payload"
mkdir -p -- "$payload"
cp -- "$application" "$payload/ishikawa-v1.3.1.tar.gz"
cp -- "$identity" "$payload/image-identity.json"
cp -- "$helper" "$payload/promote-v1.3.1-on-emceedanko"
printf '%s\n' \
  'schema=ishikawa.emceedanko-v1.3.1-qualification.v1' \
  'application_archive_sha256=2dbf08b9e15fb4436e54ce492f2ad430129e794d33a1a45cdc6abf1a7b0b5f69' \
  'runtime_archive_sha256=af95820f63798b39c6538e3f9b5653d47b07aed1d81625e2382485ff559eff3f' \
  'image_id=sha256:79f39435329920c9c834e55cf5e18528540220111ae2a35d779a86d0b539d298' \
  'frontier_cases=60/60' >"$payload/qualification-receipt.txt"
printf '%s\n' \
  'schema=ishikawa.emceedanko-v1.3.1-acceptance.v1' \
  'application_archive_sha256=2dbf08b9e15fb4436e54ce492f2ad430129e794d33a1a45cdc6abf1a7b0b5f69' \
  'runtime_archive_sha256=af95820f63798b39c6538e3f9b5653d47b07aed1d81625e2382485ff559eff3f' \
  'image_id=sha256:79f39435329920c9c834e55cf5e18528540220111ae2a35d779a86d0b539d298' \
  'human_ui_acceptance=accepted' >"$payload/acceptance-receipt.txt"
printf '%s\n' \
  'schema=ishikawa.emceedanko-v1.3.1-action.v1' \
  'mode=cleanup' 'state=pass' 'detail=candidate_removed=true' \
  'application_archive_sha256=2dbf08b9e15fb4436e54ce492f2ad430129e794d33a1a45cdc6abf1a7b0b5f69' \
  'runtime_archive_sha256=af95820f63798b39c6538e3f9b5653d47b07aed1d81625e2382485ff559eff3f' \
  'image_id=sha256:79f39435329920c9c834e55cf5e18528540220111ae2a35d779a86d0b539d298' \
  >"$payload/cleanup-receipt.txt"

refresh_payload() {
  rm -rf -- "$payload/extracted"
  find "$payload" -maxdepth 1 -type f -name '*-result.txt' -delete
  (
    cd -- "$payload"
    find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' | sort | xargs sha256sum -- >SHA256SUMS
  )
}
refresh_payload
helper_sha="$(sha256sum -- "$payload/promote-v1.3.1-on-emceedanko" | awk '{print $1}')"

start_old_api() {
  local old_root="$root/home/Documents/Ishikawa-v1.3-attended" pid
  PATH="$root/bin:/usr/bin:/bin" python3 "$old_root/scripts/ishikawa-retrieval-api" --serve &
  pid="$!"
  printf '%s\n' "$pid" >"$old_root/state/run/attended-v1.3.pid"
}

reset_fixture() {
  local pid=''
  while IFS= read -r pid_file; do
    IFS= read -r pid <"$pid_file" || pid=''
    [[ "$pid" =~ ^[0-9]+$ ]] && kill -TERM "$pid" 2>/dev/null || true
  done < <(find "$root/home" -type f -name '*.pid' 2>/dev/null || true)
  rm -rf -- "$root/home" "$root/state"
  mkdir -p -- \
    "$root/home/Documents/Ishikawa-v1.3-attended/scripts" \
    "$root/home/Documents/Ishikawa-v1.3-attended/application/web/app" \
    "$root/home/Documents/Ishikawa-v1.3-attended/application/web/components" \
    "$root/home/Documents/Ishikawa-v1.3-attended/application/web/lib" \
    "$root/home/Documents/Ishikawa-v1.3-attended/application/web/public" \
    "$root/home/Documents/Ishikawa-v1.3-attended/state/postgresql/data" \
    "$root/home/Documents/Ishikawa-v1.3-attended/state/postgresql/socket" \
    "$root/home/Documents/Ishikawa-v1.3-attended/state/run" \
    "$root/home/Documents/Ishikawa-v1.3-attended/state/logs" \
    "$root/home/Documents/Ishikawa-v1.3-attended/state/deployment" \
    "$root/state"
  printf '%s\n' '#!/usr/bin/env python3' >"$root/home/Documents/Ishikawa-v1.3-attended/scripts/ishikawa-retrieval-api"
  chmod 0755 "$root/home/Documents/Ishikawa-v1.3-attended/scripts/ishikawa-retrieval-api"
  mkdir -p -- "$root/home/Documents/Ishikawa-v1.3-attended/config"
  printf '%s\n' '{}' >"$root/home/Documents/Ishikawa-v1.3-attended/config/product.yaml"
  printf '%s\n' '{}' >"$root/home/Documents/Ishikawa-v1.3-attended/application/web/package.json"
  printf '%s\n' 'export default {}' >"$root/home/Documents/Ishikawa-v1.3-attended/application/web/next.config.mjs"
  printf '%s\n' '{"application_archive_sha256":"53da57b745fb4c8be6335896d05bdb6f63f2de3494862b99acca09e156863f3c","schema_version":5,"documents":30,"ui_port":3384,"retrieval_api_port":8384,"postgresql_runtime_port":5432}' \
    >"$root/home/Documents/Ishikawa-v1.3-attended/state/deployment/emceedanko-v1.3-attended.json"
  : >"$root/state/pg.running"
  : >"$root/state/container.ishikawa-v1.3-web.exists"
  : >"$root/state/container.ishikawa-v1.3-web.running"
  start_old_api
  refresh_payload
}

run_helper() {
  local selected_mode="$1" result="$2" output="$3"
  shift 3
  printf '%s\n' gemma-test-key nomic-test-key-000000000000000000000000 v1.3-test-password-000000000000 \
    | script -qefc "env HOME='$root/home' PATH='$root/bin:/usr/bin:/bin' MOCK_STATE='$root/state' $* bash '$payload/promote-v1.3.1-on-emceedanko' '$selected_mode' --payload-root '$payload' --result-path '$result' --expected-hostname EmceeDanko --expected-os-version 24.04 --expected-architecture amd64 --expected-helper-sha256 '$helper_sha'" /dev/null \
      >"$output" 2>&1
}

reset_fixture
run_helper --run "$payload/run-result.txt" "$root/run.out"
grep -Fq 'v1_3_1_promotion=pass' "$root/run.out"
grep -Fxq 'human_ui_acceptance=pending' "$payload/run-result.txt"
[[ -d "$root/home/Documents/Ishikawa-v1.3.1" \
    && -d "$root/home/Documents/Ishikawa-v1.3-retired-for-v1.3.1" \
    && ! -e "$root/home/Documents/Ishikawa-v1.3-attended" \
    && -f "$root/state/container.ishikawa-v1.3.1-web.running" ]]

run_helper --accept "$payload/accept-result.txt" "$root/accept.out"
grep -Fq 'v1_3_1_promotion_acceptance=pass' "$root/accept.out"
grep -Fxq 'human_ui_acceptance=accepted' "$payload/accept-result.txt"
[[ ! -e "$root/home/Documents/Ishikawa-v1.3-retired-for-v1.3.1" \
    && -f "$root/state/old-image.removed" ]]
refresh_payload
run_helper --accept "$payload/accept-repeat-result.txt" "$root/accept-repeat.out"
grep -Fq 'human_ui_acceptance=already_recorded' "$root/accept-repeat.out"
grep -Fxq 'human_ui_acceptance=accepted' "$payload/accept-repeat-result.txt"

reset_fixture
run_helper --run "$payload/rollback-run-result.txt" "$root/rollback-run.out"
refresh_payload
run_helper --rollback "$payload/rollback-result.txt" "$root/rollback.out"
grep -Fq 'v1_3_1_promotion_rollback=pass' "$root/rollback.out"
grep -Fxq 'detail=accepted_v1_3_restored=true' "$payload/rollback-result.txt"
[[ -d "$root/home/Documents/Ishikawa-v1.3-attended" \
    && ! -e "$root/home/Documents/Ishikawa-v1.3.1" \
    && ! -e "$root/home/Documents/Ishikawa-v1.3-retired-for-v1.3.1" \
    && -f "$root/state/container.ishikawa-v1.3-web.running" ]]

reset_fixture
set +e
run_helper --run "$payload/failure-result.txt" "$root/failure.out" 'MOCK_FAIL_NEW_WEB=1'
failure_status="$?"
set -e
(( failure_status != 0 ))
grep -Fq 'reason=v1_3_1_launch_failed' "$root/failure.out"
grep -Fq 'rollback_restored=true' "$root/failure.out"
[[ -d "$root/home/Documents/Ishikawa-v1.3-attended" \
    && ! -e "$root/home/Documents/Ishikawa-v1.3.1" \
    && ! -e "$root/home/Documents/Ishikawa-v1.3-retired-for-v1.3.1" \
    && -f "$root/state/container.ishikawa-v1.3-web.running" ]]

reset_fixture
run_helper --run "$payload/consumer-run-result.txt" "$root/consumer-run.out"
refresh_payload
set +e
run_helper --accept "$payload/consumer-result.txt" "$root/consumer.out" 'MOCK_OLD_CONSUMER=1'
consumer_status="$?"
set -e
(( consumer_status != 0 ))
grep -Fq 'reason=superseded_image_in_use' "$root/consumer.out"
[[ -d "$root/home/Documents/Ishikawa-v1.3-retired-for-v1.3.1" \
    && ! -e "$root/state/old-image.removed" ]]

reset_fixture
set +e
run_helper --run "$payload/database-result.txt" "$root/database.out" 'MOCK_BAD_DATABASE=1'
database_status="$?"
set -e
(( database_status != 0 ))
grep -Fq 'reason=accepted_database_inventory_mismatch' "$root/database.out"
[[ -d "$root/home/Documents/Ishikawa-v1.3-attended" && ! -e "$root/home/Documents/Ishikawa-v1.3.1" ]]

printf '%s\n' 'v1_3_1_promotion_target_harness=pass;run=pass;accept=pass;rollback=pass;launch_failure_restoration=pass;consumer_refusal=pass;database_refusal=pass'
