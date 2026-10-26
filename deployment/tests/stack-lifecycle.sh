#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Exercise the installed production stack controller through complete start,
#   status, stop, restart, timeout, service-failure, and cleanup branches.
#
# Boundary:
#   The harness uses a private installed-layout copy and deterministic command
#   doubles. It contacts no service, changes no system unit, and uses no Docker
#   daemon, credentials, database, model, or corpus.

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
test_root="$(mktemp -d /tmp/ishikawa-stack-lifecycle.XXXXXX)"

fail() {
  printf '\nSCRIPT RESULT\nishikawa_stack_lifecycle_test=blocked;reason=%s\n' "$1" >&2
  exit 1
}

cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  [[ "$test_root" == /tmp/ishikawa-stack-lifecycle.* && -d "$test_root" ]] \
    && rm -rf -- "$test_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p -- "$test_root/installed" "$test_root/bin" "$test_root/mock-state"
cp -a -- "$repo_root/Ishikawa/." "$test_root/installed/"
mkdir -p -- "$test_root/installed/state/run"
cp -- "$test_root/installed/config/templates/"*.yaml "$test_root/installed/config/"

cat >"$test_root/installed/scripts/ishikawa-retrieval-api" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == --check-readiness ]] || exit 91
[[ "${MOCK_RETRIEVAL_PREFLIGHT:-pass}" == pass ]] || exit 1
printf 'ishikawa_retrieval_readiness=pass\n'
MOCK
chmod 0755 "$test_root/installed/scripts/ishikawa-retrieval-api"

cat >"$test_root/bin/sudo" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${1:-}" == -v ]]; then exit 0; fi
exec "$@"
MOCK

cat >"$test_root/bin/dpkg" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == --print-architecture ]] || exit 91
printf 'amd64\n'
MOCK

cat >"$test_root/bin/sleep" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK

cat >"$test_root/bin/pg_isready" <<'MOCK'
#!/usr/bin/env bash
[[ "${MOCK_POSTGRESQL_READINESS:-pass}" == pass ]]
MOCK

cat >"$test_root/bin/ss" <<'MOCK'
#!/usr/bin/env bash
[[ "${MOCK_PORT_OCCUPIED:-false}" != true ]] || printf 'LISTEN mock\n'
MOCK

cat >"$test_root/bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
url="${!#}"
code=200
case "${MOCK_WEB_MODE:-pass}:$url" in
  liveness_fail:http://127.0.0.1:3000/api/live) code=503 ;;
  readiness_fail:http://127.0.0.1:3000/api/ready) code=503 ;;
esac
case "${MOCK_RETRIEVAL_HTTP:-pass}:$url" in
  fail:http://127.0.0.1:1384/*) code=503 ;;
esac
printf '%s' "$code"
MOCK

cat >"$test_root/bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
state="${MOCK_STATE:?}"
scope=system
if [[ "${1:-}" == --user ]]; then scope=user; shift; fi
operation="${1:-}"
shift || true
unit="${1:-}"
key="${scope}_${unit//[^A-Za-z0-9_.-]/_}"
case "$operation" in
  is-enabled)
    printf 'disabled\n'
    exit 1
    ;;
  is-active)
    if [[ -f "$state/$key.active" ]]; then printf 'active\n'; exit 0; fi
    printf 'inactive\n'
    exit 3
    ;;
  start)
    [[ "${MOCK_SYSTEMCTL_START_FAIL:-}" != "$unit" ]] || exit 1
    : >"$state/$key.active"
    printf 'start %s %s\n' "$scope" "$unit" >>"$state/systemctl.log"
    ;;
  stop)
    rm -f -- "$state/$key.active"
    printf 'stop %s %s\n' "$scope" "$unit" >>"$state/systemctl.log"
    ;;
  cat)
    [[ "$scope" == user && "$unit" == ishikawa-retrieval-api.service ]]
    ;;
  import-environment|unset-environment)
    printf '%s %s\n' "$operation" "$scope" >>"$state/systemctl.log"
    ;;
  *) exit 92 ;;
esac
MOCK

cat >"$test_root/bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -Eeuo pipefail
state="${MOCK_STATE:?}"
command="${1:-}"
shift || true
case "$command" in
  info) exit 0 ;;
  image)
    [[ "${1:-}" == inspect ]] || exit 91
    case "$*" in
      *'{{.Architecture}}'*) printf 'amd64\n' ;;
      *'org.opencontainers.image.version'*) printf '24.22.1-next16.4.3-react19.2.9\n' ;;
      *'{{.Id}}'*) printf 'sha256:%064d\n' 0 ;;
      *) printf '{}\n' ;;
    esac
    ;;
  inspect)
    [[ -f "$state/container.exists" ]] || exit 1
    if [[ "$*" == *'{{.State.Running}}'* ]]; then
      [[ -f "$state/container.running" ]] && printf 'true\n' || printf 'false\n'
    else
      printf '{}\n'
    fi
    ;;
  run)
    if [[ "$*" == *'--entrypoint node'* ]]; then exit 0; fi
    [[ "$*" == *'--detach'* ]] || exit 92
    : >"$state/container.exists"
    : >"$state/container.running"
    count=0
    [[ ! -f "$state/docker-runs" ]] || read -r count <"$state/docker-runs"
    printf '%s\n' "$((count + 1))" >"$state/docker-runs"
    case "${MOCK_WEB_MODE:-pass}" in
      pass|liveness_fail|readiness_fail)
        printf '%s\n' '[RUNTIME] stage=build;state=pass' >"$state/container.log"
        ;;
      build_fail)
        printf '%s\n' 'mock production build failed' >"$state/container.log"
        rm -f -- "$state/container.running"
        ;;
      timeout)
        printf '%s\n' '[RUNTIME] stage=build;state=start' >"$state/container.log"
        ;;
      *) exit 93 ;;
    esac
    printf 'mock-container-id\n'
    ;;
  logs)
    cat -- "$state/container.log"
    ;;
  exec)
    [[ -f "$state/container.running" ]] || exit 1
    printf '123456\t/opt/nextjs/.next\n'
    ;;
  stop)
    rm -f -- "$state/container.running"
    printf 'docker-stop\n' >>"$state/docker.log"
    ;;
  rm)
    rm -f -- "$state/container.exists" "$state/container.running" "$state/container.log"
    printf 'docker-rm\n' >>"$state/docker.log"
    ;;
  *) exit 94 ;;
esac
MOCK
chmod 0755 "$test_root/bin/"*

readonly stack="$test_root/installed/scripts/ishikawa-stack"
export PATH="$test_root/bin:$PATH"
export MOCK_STATE="$test_root/mock-state"
export ISHIKAWA_GEMMA_API_KEY='fixture-gemma'
export ISHIKAWA_NOMIC_API_KEY='fixture-nomic'
export ISHIKAWA_POSTGRESQL_PASSWORD='fixture-postgresql'

reset_runtime() {
  rm -f -- "$MOCK_STATE"/* "$test_root/installed/state/run/stack.state"
  unset MOCK_PORT_OCCUPIED MOCK_POSTGRESQL_READINESS MOCK_RETRIEVAL_HTTP \
    MOCK_RETRIEVAL_PREFLIGHT MOCK_SYSTEMCTL_START_FAIL MOCK_WEB_MODE
}

run_expect_pass() {
  local expected="$1"
  shift
  local output
  output="$("$@" 2>&1)" || fail "${expected}_failed"
  grep -Fq "$expected" <<<"$output" || fail "${expected}_marker_missing"
}

run_expect_blocked() {
  local reason="$1"
  shift
  local output status
  set +e
  output="$("$@" 2>&1)"
  status="$?"
  set -e
  (( status != 0 )) || fail "${reason}_reported_success"
  grep -Fxq "ishikawa_stack=blocked;reason=$reason" <<<"$output" \
    || fail "${reason}_marker_missing"
}

assert_clean_runtime() {
  [[ ! -e "$test_root/installed/state/run/stack.state" ]] || fail cleanup_state_retained
  [[ ! -e "$MOCK_STATE/container.exists" ]] || fail cleanup_container_retained
  [[ ! -e "$MOCK_STATE/system_postgresql@16-main.service.active" ]] \
    || fail cleanup_postgresql_active
  [[ ! -e "$MOCK_STATE/user_ishikawa-retrieval-api.service.active" ]] \
    || fail cleanup_retrieval_active
}

reset_runtime
run_expect_pass 'ishikawa_stack=start;state=ready;boot_enabled=false' "$stack" start
run_expect_pass 'ishikawa_stack=status;state=ready;boot_enabled=false' "$stack" status
run_expect_pass 'ishikawa_stack=stop;state=stopped;boot_enabled=false' "$stack" stop
assert_clean_runtime
run_expect_pass 'ishikawa_stack=start;state=ready;boot_enabled=false' "$stack" start
[[ "$(<"$MOCK_STATE/docker-runs")" == 2 ]] || fail restart_did_not_rebuild
run_expect_pass 'ishikawa_stack=stop;state=stopped;boot_enabled=false' "$stack" stop
assert_clean_runtime

reset_runtime
export MOCK_WEB_MODE=build_fail
run_expect_blocked web_build_or_start_failed "$stack" start
assert_clean_runtime

reset_runtime
export MOCK_WEB_MODE=timeout
run_expect_blocked web_build_timeout "$stack" start
assert_clean_runtime

reset_runtime
export MOCK_WEB_MODE=liveness_fail
run_expect_blocked web_liveness_failed "$stack" start
assert_clean_runtime

reset_runtime
: >"$MOCK_STATE/container.exists"
run_expect_blocked web_container_already_exists "$stack" start
[[ ! -e "$test_root/installed/state/run/stack.state" ]] || fail preflight_created_state
[[ ! -e "$MOCK_STATE/system_postgresql@16-main.service.active" ]] || fail preflight_started_postgresql

reset_runtime
export MOCK_POSTGRESQL_READINESS=fail
run_expect_blocked postgresql_readiness_failed "$stack" start
assert_clean_runtime

reset_runtime
export MOCK_PORT_OCCUPIED=true
run_expect_blocked configured_port_in_use "$stack" start
assert_clean_runtime

printf '%s\n' \
  'start_status_stop=pass;restart_rebuild=pass;source_read_only_contract=pass' \
  'build_failure_cleanup=pass;timeout_cleanup=pass;liveness_cleanup=pass' \
  'stale_container_preflight=pass;postgresql_failure_cleanup=pass;port_preflight=pass'
printf '\nSCRIPT RESULT\nishikawa_stack_lifecycle_test=pass\n'
