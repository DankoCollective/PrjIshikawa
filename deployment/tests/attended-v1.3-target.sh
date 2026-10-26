#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Purpose:
#   Exercise the complete Script 06 target lifecycle without a lab connection.
#
# Mental model:
#   Install the real release into an isolated HOME, retain the real corpus and
#   validators, and replace only host identity, PostgreSQL, systemd, Docker,
#   listener, and long-running service boundaries. Cover fresh creation,
#   cleanup, durable reuse, failed-launch v1.2 restoration, acceptance, and
#   explicit rollback.
#
# Inputs or prerequisites:
#   Current Script 01 and Script 03 handoffs plus standard local test tools.
#
# Outputs or artifact lane:
#   Temporary /tmp state only; no network target or repository mutation.
#
# Usage:
#   bash ./deployment/tests/attended-v1.3-target.sh

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
readonly orchestrator="$repo_root/deployment/scripts/06_attended-v1.3-on-emceedanko.sh"
readonly application="$repo_root/local/artifacts/ishikawa-v1.3-current/ishikawa-v1.3.tar.gz"
readonly corpus="$repo_root/local/artifacts/qualification-corpus-v3-current/qualification-corpus-v3.tar.gz"
readonly generator="$repo_root/deployment/assets/create-corpus-v3-ingestion-config.py"

last_output=''
last_result=''

fail() {
  [[ -z "$last_output" || ! -f "$last_output" ]] || tail -n 160 "$last_output" >&2 || true
  [[ -z "$last_result" || ! -f "$last_result" ]] || tail -n 80 "$last_result" >&2 || true
  [[ -z "${test_root:-}" || ! -f "$test_root/state/ss-calls" ]] \
    || tail -n 40 "$test_root/state/ss-calls" >&2 || true
  printf '\nSCRIPT RESULT\nattended_v1_3_target_test=blocked;reason=%s\n' "$1" >&2
  exit 1
}

for file in "$orchestrator" "$application" "$corpus" "$generator"; do
  [[ -f "$file" && ! -L "$file" && -r "$file" ]] || fail input_unsafe
done
for command_name in awk bash cp find grep mktemp python3 script sha256sum sort tar; do
  command -v "$command_name" >/dev/null 2>&1 || fail "command_missing_${command_name}"
done
bash -n "$orchestrator" || fail orchestrator_syntax_invalid

test_root="$(mktemp -d /tmp/ishikawa-attended-target-test.XXXXXX)"
model_pid=''
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$model_pid" =~ ^[0-9]+$ ]] && kill -0 "$model_pid" 2>/dev/null; then
    kill -TERM "$model_pid" 2>/dev/null || true
    wait "$model_pid" 2>/dev/null || true
  fi
  if [[ -f "$test_root/state/v13-api-pid" ]]; then
    pid="$(<"$test_root/state/v13-api-pid")"
    [[ "$pid" =~ ^[0-9]+$ ]] && kill -TERM -- "-$pid" 2>/dev/null || true
  fi
  [[ "$test_root" == /tmp/ishikawa-attended-target-test.* && -d "$test_root" ]] \
    && rm -rf -- "$test_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p -- "$test_root/bin" "$test_root/home/Documents" "$test_root/package" \
  "$test_root/payload/database" "$test_root/state" "$test_root/pgshare/extension"
printf '%s\n' '# test pgvector control' >"$test_root/pgshare/extension/vector.control"
tar -xzf "$application" -C "$test_root/package"
release_root="$test_root/package/ishikawa-v1.3"
for install_root in \
  "$test_root/home/Documents/Ishikawa" \
  "$test_root/home/Documents/Ishikawa-v1.3"; do
  bash "$release_root/application/install-ishikawa" --install-root "$install_root" >/dev/null \
    || fail candidate_install_failed
done
mkdir -- "$test_root/home/Documents/Ishikawa-before-v1.2"
mkdir -- "$test_root/home/Documents/Ishikawa-v1.3-qualification-inputs"
cp -- "$corpus" "$test_root/home/Documents/Ishikawa-v1.3-qualification-inputs/qualification-corpus-v3.tar.gz"
(cd -- "$test_root/home/Documents/Ishikawa-v1.3-qualification-inputs" \
  && sha256sum qualification-corpus-v3.tar.gz >qualification-corpus-v3.tar.gz.sha256)

candidate="$test_root/home/Documents/Ishikawa-v1.3"
active="$test_root/home/Documents/Ishikawa"
mv -- "$candidate/scripts/ishikawa-retrieval-api" "$candidate/scripts/ishikawa-retrieval-api.real"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -Eeuo pipefail' \
  'case "${1:-}" in' \
  '  --check-config) exec "$(dirname -- "$0")/ishikawa-retrieval-api.real" "$@" ;;' \
  '  --check-readiness) printf "%s\n" "ishikawa_retrieval_api_readiness=pass;configuration=pass;storage=pass;postgresql=pass;gemma=pass;nomic=pass" ;;' \
  '  --serve)' \
  '    [[ "${ISHIKAWA_TEST_API_FAIL:-0}" != 1 ]] || { printf "%s\n" "ishikawa_retrieval_api=blocked;reason=test_api_failure"; exit 1; }' \
  '    printf "%s\n" "$$" >"$ISHIKAWA_TEST_STATE/v13-api-pid"' \
  '    trap "exit 0" TERM INT' \
  '    while :; do sleep 1; done' \
  '    ;;' \
  '  *) exit 2 ;;' \
  'esac' >"$candidate/scripts/ishikawa-retrieval-api"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -Eeuo pipefail' \
  'case "${1:-}" in' \
  '  --validate-only) printf "%s\n" "actions=add:30,reprocess:0,retire:0,reuse:0,revise:0" "ishikawa_ingestion=pass;exit_code=0" ;;' \
  '  --publish)' \
  '    if [[ "${ISHIKAWA_TEST_INGEST_FAIL:-0}" == 1 ]]; then' \
  '      printf "%s\n" "ishikawa_ingestion=blocked;reason=test_embedding_failure"' \
  '      exit 1' \
  '    fi' \
  '    printf "%s\n" "ishikawa_ingestion=pass;exit_code=0"' \
  '    ;;' \
  '  *) exit 2 ;;' \
  'esac' >"$candidate/scripts/ishikawa-ingest"
chmod 0700 "$candidate/scripts/ishikawa-retrieval-api" "$candidate/scripts/ishikawa-ingest"

mv -- "$active/scripts/ishikawa-retrieval-api" "$active/scripts/ishikawa-retrieval-api.real"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -Eeuo pipefail' \
  'if [[ "${1:-}" == --check-readiness ]]; then' \
  '  [[ "${ISHIKAWA_TEST_V12_PASSWORD:-}" == "${ISHIKAWA_POSTGRESQL_PASSWORD:-}" ]] || exit 1' \
  '  printf "%s\n" "ishikawa_retrieval_api_readiness=pass;configuration=pass;storage=pass;postgresql=pass;gemma=pass;nomic=pass"' \
  '  exit 0' \
  'fi' \
  'exec "$(dirname -- "$0")/ishikawa-retrieval-api.real" "$@"' \
  >"$active/scripts/ishikawa-retrieval-api"
chmod 0700 "$active/scripts/ishikawa-retrieval-api"

cp -- "$orchestrator" "$test_root/payload/attended-v1.3-on-emceedanko"
cp -- "$generator" "$test_root/payload/create-corpus-v3-ingestion-config.py"
cp -- "$release_root/database/README.md" "$release_root/database/install-schema" \
  "$release_root/database/schema.sql" "$release_root/database/SHA256SUMS" \
  "$test_root/payload/database/"
(cd -- "$candidate" \
  && find . -type f -printf '%P\n' | sort \
  | while IFS= read -r file; do sha256sum -- "$file"; done) \
  >"$test_root/payload/candidate-SHA256SUMS"
(cd -- "$candidate" && find . -type f -printf '%m %P\n' | sort) \
  >"$test_root/payload/candidate-MODES"
(cd -- "$test_root/payload" \
  && find . -type f ! -name SHA256SUMS ! -path './database/SHA256SUMS' -printf '%P\n' | sort \
  | while IFS= read -r file; do sha256sum -- "$file"; done >SHA256SUMS)

printf '%s\n' active >"$test_root/state/unit"
printf '%s\n' active >"$test_root/state/postgres"
printf '%s\n' ishikawa-web >"$test_root/state/containers"
printf '%s\n' none >"$test_root/state/database"
printf '%s\n' none >"$test_root/state/private-pg-port"
schema_sha256="$(sha256sum "$test_root/payload/database/schema.sql" | awk '{print $1}')"

write_command() {
  local name="$1" body="$2"
  printf '#!/usr/bin/env bash\nset -Eeuo pipefail\n%s\n' "$body" >"$test_root/bin/$name"
  chmod 0700 "$test_root/bin/$name"
}

write_command hostname '[[ "${1:-}" == -s ]] && printf "EmceeDanko\n"'
write_command dpkg '[[ "${1:-}" == --print-architecture ]] && printf "amd64\n"'
write_command sudo '
if [[ "${1:-}" == -v ]]; then exit 0; fi
if [[ "${1:-}" == -u ]]; then shift 2; fi
exec "$@"'
write_command systemctl '
scope=system
if [[ "${1:-}" == --user ]]; then scope=user; shift; fi
action="${1:-}"; unit="${2:-}"
case "$action" in
  is-enabled) [[ "$unit" == ishikawa-retrieval-api.service ]] && printf "static\n" || printf "disabled\n" ;;
  is-active)
    if [[ "$scope" == user && "$unit" == ishikawa-retrieval-api.service ]]; then cat "$ISHIKAWA_TEST_STATE/unit"; elif [[ "$unit" == postgresql@16-main.service ]]; then cat "$ISHIKAWA_TEST_STATE/postgres"; else printf "inactive\n"; fi ;;
  stop)
    if [[ "$scope" == user ]]; then printf "inactive\n" >"$ISHIKAWA_TEST_STATE/unit"; else printf "inactive\n" >"$ISHIKAWA_TEST_STATE/postgres"; fi ;;
  start)
    [[ "${ISHIKAWA_TEST_RESTORE_FAIL:-0}" != 1 ]] || exit 1
    if [[ "$scope" == user ]]; then printf "active\n" >"$ISHIKAWA_TEST_STATE/unit"; else printf "active\n" >"$ISHIKAWA_TEST_STATE/postgres"; fi ;;
  import-environment|unset-environment) exit 0 ;;
  cat) [[ "$unit" != ishikawa-v1.3-retrieval-api.service ]] ;;
  *) exit 0 ;;
esac'
write_command docker '
action="${1:-}"; shift || true
case "$action" in
  info) exit 0 ;;
  image)
    shift
    if [[ "$*" == *Architecture* ]]; then printf "amd64\n"; else printf "sha256:368f4381b61bf90ad27aa5a9dd4c10e1de0b4b4666006911e1b6cb4aafcfb8a6\n"; fi ;;
  inspect)
    name="${!#}"
    if grep -Fxq "$name" "$ISHIKAWA_TEST_STATE/containers"; then printf "true\n"; else exit 1; fi ;;
  stop)
    name="${!#}"
    grep -Fxv "$name" "$ISHIKAWA_TEST_STATE/containers" >"$ISHIKAWA_TEST_STATE/containers.next" || true
    mv "$ISHIKAWA_TEST_STATE/containers.next" "$ISHIKAWA_TEST_STATE/containers" ;;
  run)
    name=""
    while (( $# )); do [[ "$1" == --name ]] && { name="$2"; break; }; shift; done
    [[ -n "$name" ]] || exit 2
    if [[ "$name" == ishikawa-v1.3-web && "${ISHIKAWA_TEST_WEB_FAIL:-0}" == 1 ]]; then exit 1; fi
    grep -Fxq "$name" "$ISHIKAWA_TEST_STATE/containers" || printf "%s\n" "$name" >>"$ISHIKAWA_TEST_STATE/containers"
    printf "test-container-id\n" ;;
  *) exit 2 ;;
esac'
write_command ss '
printf "call=%s;unit=%s;containers=%s\n" "$*" "$(cat "$ISHIKAWA_TEST_STATE/unit")" "$(paste -sd, "$ISHIKAWA_TEST_STATE/containers")" >>"$ISHIKAWA_TEST_STATE/ss-calls"
output=""
if [[ ( "$(cat "$ISHIKAWA_TEST_STATE/postgres")" == active || "$(cat "$ISHIKAWA_TEST_STATE/private-pg-port")" == 5432 ) && ( "$*" != *sport* || "$*" == *5432* ) ]]; then output+="LISTEN 0 4096 127.0.0.1:5432 0.0.0.0:*\n"; fi
if [[ "$(cat "$ISHIKAWA_TEST_STATE/private-pg-port")" == 65438 && ( "$*" != *sport* || "$*" == *65438* ) ]]; then output+="LISTEN 0 4096 127.0.0.1:65438 0.0.0.0:*\n"; fi
if [[ "$(cat "$ISHIKAWA_TEST_STATE/unit")" == active && ( "$*" != *sport* || "$*" == *1384* ) ]]; then output+="LISTEN 0 4096 127.0.0.1:1384 0.0.0.0:*\n"; fi
if grep -Fxq ishikawa-web "$ISHIKAWA_TEST_STATE/containers" && [[ "$*" != *sport* || "$*" == *3000* ]]; then output+="LISTEN 0 4096 127.0.0.1:3000 0.0.0.0:*\n"; fi
if [[ -s "$ISHIKAWA_TEST_STATE/v13-api-pid" && ( "$*" != *sport* || "$*" == *8384* ) ]]; then pid="$(cat "$ISHIKAWA_TEST_STATE/v13-api-pid")"; kill -0 "$pid" 2>/dev/null && output+="LISTEN 0 4096 127.0.0.1:8384 0.0.0.0:*\n" || true; fi
if grep -Fxq ishikawa-v1.3-web "$ISHIKAWA_TEST_STATE/containers" && [[ "$*" != *sport* || "$*" == *3384* ]]; then output+="LISTEN 0 4096 127.0.0.1:3384 0.0.0.0:*\n"; fi
printf "%b" "$output"'
write_command curl '
url="${!#}"; status=200
if [[ "$url" == */health && "${ISHIKAWA_TEST_MODEL_FAIL:-0}" == 1 ]]; then status=503; fi
if [[ "$url" == *:8384/* ]]; then
  status=503
  if [[ -s "$ISHIKAWA_TEST_STATE/v13-api-pid" ]]; then pid="$(cat "$ISHIKAWA_TEST_STATE/v13-api-pid")"; kill -0 "$pid" 2>/dev/null && status=200 || true; fi
fi
if [[ "$url" == *:3384/* ]] && ! grep -Fxq ishikawa-v1.3-web "$ISHIKAWA_TEST_STATE/containers"; then status=503; fi
if [[ "$url" == *:1384/* && "$(cat "$ISHIKAWA_TEST_STATE/unit")" != active ]]; then status=503; fi
if [[ "$url" == *:3000/* ]] && ! grep -Fxq ishikawa-web "$ISHIKAWA_TEST_STATE/containers"; then status=503; fi
printf "%s" "$status"'
write_command createdb '
if [[ "${1:-}" == --version ]]; then printf "createdb (PostgreSQL) 16.10\n"; exit 0; fi
printf "%s\n" "${!#}" >"$ISHIKAWA_TEST_STATE/database"'
write_command initdb '
if [[ "${1:-}" == --version ]]; then printf "initdb (PostgreSQL) 16.10\n"; exit 0; fi
data=""
while (( $# )); do [[ "$1" == -D ]] && { data="$2"; break; }; shift; done
[[ -n "$data" ]] || exit 2
mkdir -p "$data"
printf "16\n" >"$data/PG_VERSION"'
write_command pg_ctl '
if [[ "${1:-}" == --version ]]; then printf "pg_ctl (PostgreSQL) 16.10\n"; exit 0; fi
data=""; action=""; options=""
while (( $# )); do
  case "$1" in -D) data="$2"; shift 2 ;; -o) options="$2"; shift 2 ;; status|start|stop) action="$1"; shift ;; *) shift ;; esac
done
case "$action" in
  status) [[ "$(cat "$ISHIKAWA_TEST_STATE/private-pg-port")" != none ]] ;;
  start)
    port="$(sed -n "s/.*-p \([0-9][0-9]*\).*/\1/p" <<<"$options")"
    [[ -n "$port" ]] || exit 2
    printf "%s\n" "$port" >"$ISHIKAWA_TEST_STATE/private-pg-port" ;;
  stop) printf "none\n" >"$ISHIKAWA_TEST_STATE/private-pg-port" ;;
  *) exit 2 ;;
esac'
write_command pg_isready '
if [[ "${1:-}" == --version ]]; then printf "pg_isready (PostgreSQL) 16.10\n"; exit 0; fi
port=""
while (( $# )); do [[ "$1" == --port ]] && { port="$2"; break; }; shift; done
if [[ "$port" == 5432 ]]; then [[ "$(cat "$ISHIKAWA_TEST_STATE/postgres")" == active || "$(cat "$ISHIKAWA_TEST_STATE/private-pg-port")" == 5432 ]]; else [[ "$(cat "$ISHIKAWA_TEST_STATE/private-pg-port")" == "$port" ]]; fi'
write_command psql '
if [[ "${1:-}" == --version ]]; then printf "psql (PostgreSQL) 16.10\n"; exit 0; fi
command_text=""; database=""
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  [[ "${args[i]}" == -c ]] && command_text="${args[i+1]}"
  [[ "${args[i]}" == -d ]] && database="${args[i+1]}"
done
if [[ -z "$command_text" && ! " $* " =~ " --file " ]]; then input="$(cat)"; else input=""; fi
if [[ "$command_text" == *"schema_migrations"* ]]; then
  printf "ishikawa_consolidated_schema_v5|%s|5\n" "$ISHIKAWA_TEST_SCHEMA_SHA"
elif [[ "$command_text" == "SELECT 1;" ]]; then
  printf "1\n"
elif [[ "$input" == *"active_documents"* ]]; then
  if [[ "${ISHIKAWA_TEST_DB_COUNT_FAIL:-0}" == 1 ]]; then
    printf "29;145;760;910;150;910;220;80\n"
  else
    printf "30;150;786;943;157;943;240;90\n"
  fi
fi
exit 0'
write_command pg_config '
case "${1:-}" in
  --version) printf "PostgreSQL 16.10\n" ;;
  --sharedir) printf "%s\n" "$ISHIKAWA_TEST_ROOT/pgshare" ;;
  *) exit 2 ;;
esac'

printf '%s\n' \
  'import http.server, pathlib, sys' \
  'class Handler(http.server.BaseHTTPRequestHandler):' \
  '    def do_POST(self):' \
  '        length = int(self.headers.get("Content-Length", "0")); self.rfile.read(length)' \
  '        if self.path == "/v1/embeddings": body = b"{\"data\":[{\"embedding\":[1.0" + b",1.0" * 767 + b"],\"index\":0,\"object\":\"embedding\"}],\"model\":\"nomic-ai/nomic-embed-text-v1.5\",\"object\":\"list\",\"usage\":{\"prompt_tokens\":12,\"total_tokens\":12}}"' \
  '        else: body = b"{\"count\":3,\"max_model_len\":2048,\"tokens\":[1,2,3]}"' \
  '        self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)' \
  '    def do_GET(self):' \
  '        body = b"{\"data\":[]}" if self.path == "/v1/models" else b"{\"status\":\"ok\"}"' \
  '        self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)' \
  '    def log_message(self, *args): pass' \
  'server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)' \
  'pathlib.Path(sys.argv[1]).write_text(str(server.server_port), encoding="utf-8")' \
  'server.serve_forever()' >"$test_root/model-server.py"
python3 -B "$test_root/model-server.py" "$test_root/model-port" &
model_pid="$!"
for _attempt in {1..100}; do [[ -s "$test_root/model-port" ]] && break; sleep 0.05; done
[[ -s "$test_root/model-port" ]] || fail model_double_not_ready
model_port="$(<"$test_root/model-port")"

reset_fresh_state() {
  printf '%s\n' active >"$test_root/state/unit"
  printf '%s\n' active >"$test_root/state/postgres"
  printf '%s\n' ishikawa-web >"$test_root/state/containers"
  printf '%s\n' none >"$test_root/state/database"
  printf '%s\n' none >"$test_root/state/private-pg-port"
  rm -f -- "$test_root/state/v13-api-pid"
  rm -rf -- "$test_root/home/Documents/Ishikawa-v1.3-attended"
}

run_target() {
  local name="$1" internal_mode="$2" secret_count="$3"
  local ingest_fail="${4:-0}" web_fail="${5:-0}" model_fail="${6:-0}" restore_fail="${7:-0}"
  local database_count_fail="${8:-0}"
  local output="$test_root/${name}.stdout" result_path="$test_root/payload/${name}-result.txt"
  local command secrets=''
  rm -f -- "$result_path"
  last_output="$output"; last_result="$result_path"
  case "$secret_count" in
    0) secrets='' ;;
    3) secrets=$'gemma-test-key\nnomic-test-key-012345678901234567890123456789\nv12-test-password\n' ;;
    5) secrets=$'gemma-test-key\nnomic-test-key-012345678901234567890123456789\nv12-test-password\nv13-ingest-test-password\nv13-retrieval-test-password\n' ;;
    *) fail invalid_test_secret_count ;;
  esac
  command="ISHIKAWA_SCRIPT06_INTERNAL=1 bash '$orchestrator' '$internal_mode' --expected-hostname EmceeDanko --expected-os-version 24.04 --expected-architecture amd64 --payload-root '$test_root/payload' --result-path '$result_path' --gemma-base-url 'http://127.0.0.1:$model_port' --nomic-base-url 'http://127.0.0.1:$model_port'"
  set +e
  printf '%s' "$secrets" | \
    HOME="$test_root/home" PATH="$test_root/bin:$PATH" \
    ISHIKAWA_TEST_STATE="$test_root/state" \
    ISHIKAWA_TEST_ROOT="$test_root" \
    ISHIKAWA_TEST_SCHEMA_SHA="$schema_sha256" \
    ISHIKAWA_TEST_V12_PASSWORD='v12-test-password' \
    ISHIKAWA_TEST_INGEST_FAIL="$ingest_fail" \
    ISHIKAWA_TEST_WEB_FAIL="$web_fail" \
    ISHIKAWA_TEST_MODEL_FAIL="$model_fail" \
    ISHIKAWA_TEST_RESTORE_FAIL="$restore_fail" \
    ISHIKAWA_TEST_DB_COUNT_FAIL="$database_count_fail" \
      script -qefc "$command" /dev/null 2>&1 | tr -d '\r' >"$output"
  target_status="${PIPESTATUS[1]}"
  set -e
}

reset_fresh_state
run_target ingestion-failure --target-launch 5 1
(( target_status != 0 )) || fail ingestion_failure_accepted
grep -Fxq 'reason=ingestion_publication_failed' "$last_result" || fail ingestion_failure_reason_missing
grep -Fq 'root_cause=test_embedding_failure' "$last_result" || fail ingestion_failure_root_cause_missing
[[ "$(<"$test_root/state/private-pg-port")" == none \
    && ! -e "$test_root/home/Documents/Ishikawa-v1.3-attended" ]] \
  || fail ingestion_failure_database_cleanup_failed
[[ ! -e "$test_root/home/Documents/Ishikawa-v1.3-attended" \
    && "$(<"$test_root/state/unit")" == active ]] \
  || fail ingestion_failure_state_cleanup_failed

reset_fresh_state
run_target model-failure --target-launch 5 0 0 1
(( target_status != 0 )) || fail model_failure_accepted
grep -Fxq 'reason=model_health_unavailable' "$last_result" || fail model_failure_reason_missing
[[ "$(<"$test_root/state/database")" == none && "$(<"$test_root/state/unit")" == active ]] \
  || fail model_failure_mutated_state

reset_fresh_state
run_target web-failure --target-launch 5 0 1
(( target_status != 0 )) || fail web_failure_accepted
grep -Fxq 'reason=v1_3_web_start_failed' "$last_result" || fail web_failure_reason_missing
grep -Fxq 'v1_2_restored=true;cleanup=pass' "$last_result" || fail automatic_v1_2_restoration_missing
[[ "$(<"$test_root/state/database")" == rag_catalog \
    && "$(<"$test_root/state/private-pg-port")" == none \
    && "$(<"$test_root/state/postgres")" == active \
    && -f "$test_root/home/Documents/Ishikawa-v1.3-attended/state/postgresql/data/PG_VERSION" \
    && -d "$test_root/home/Documents/Ishikawa-v1.3-attended" \
    && "$(<"$test_root/state/unit")" == active ]] \
  || fail durable_state_or_v1_2_restoration_invalid

run_target reuse-launch --target-launch 5
(( target_status == 0 )) || fail durable_reuse_launch_failed
grep -Fxq 'ishikawa_v1_3_emceedanko_attended_launch=pass' "$last_result" || fail launch_pass_marker_missing
grep -Fq 'port_1384_purpose=v1_2_runtime_and_rollback' "$last_result" \
  || fail launch_port_purpose_missing
grep -Fq 'action=reused_exact' "$last_output" || fail durable_reuse_marker_missing
[[ "$(<"$test_root/state/unit")" == inactive ]] || fail v1_2_not_stopped_for_attended_launch
[[ "$(<"$test_root/state/postgres")" == inactive \
    && "$(<"$test_root/state/private-pg-port")" == 5432 ]] \
  || fail postgresql_switchover_invalid
grep -Fxq ishikawa-v1.3-web "$test_root/state/containers" || fail v1_3_web_not_running

run_target accept --target-accept 0
(( target_status == 0 )) || fail acceptance_failed
grep -Fxq 'ishikawa_v1_3_emceedanko_human_ui_acceptance=pass' "$last_result" || fail acceptance_marker_missing
grep -Fq 'port_1384_purpose=v1_2_runtime_and_rollback' "$last_result" \
  || fail acceptance_port_purpose_missing
[[ -f "$test_root/home/Documents/Ishikawa-v1.3-attended/state/reports/acceptance/emceedanko-v1.3-human-ui.txt" ]] \
  || fail acceptance_receipt_missing

run_target rollback --target-rollback 3
(( target_status == 0 )) || fail explicit_rollback_failed
grep -Fxq 'ishikawa_v1_3_emceedanko_attended_rollback=pass' "$last_result" || fail rollback_marker_missing
grep -Fq 'port_1384_purpose=v1_2_runtime_and_rollback' "$last_result" \
  || fail rollback_port_purpose_missing
grep -Fxq 'attended_runtime=stopped;v1_2_restored=true;durable_v1_3_database=preserved' "$last_result" \
  || fail rollback_contract_missing
[[ "$(<"$test_root/state/unit")" == active \
    && "$(<"$test_root/state/postgres")" == active \
    && "$(<"$test_root/state/private-pg-port")" == none \
    && "$(<"$test_root/state/database")" == rag_catalog ]] \
  || fail rollback_state_invalid
grep -Fxq ishikawa-web "$test_root/state/containers" || fail v1_2_web_not_restored
! grep -Fxq ishikawa-v1.3-web "$test_root/state/containers" || fail v1_3_web_not_stopped

run_target reuse-database-failure --target-launch 5 0 0 0 0 1
(( target_status != 0 )) || fail reuse_database_failure_accepted
grep -Fxq 'reason=database_inventory_mismatch' "$last_result" || fail reuse_database_failure_reason_missing
[[ "$(<"$test_root/state/private-pg-port")" == none \
    && "$(<"$test_root/state/postgres")" == active \
    && "$(<"$test_root/state/unit")" == active ]] \
  || fail reuse_database_failure_cleanup_invalid

mkdir -p -- "$test_root/home/Documents/Ishikawa-v1.3-attended/state/run"
printf '%s\n' "$model_pid" >"$test_root/home/Documents/Ishikawa-v1.3-attended/state/run/attended-v1.3.pid"
run_target pid-identity-mismatch --target-rollback 0
(( target_status != 0 )) || fail unrelated_pid_accepted
grep -Fxq 'reason=attended_api_pid_identity_mismatch' "$last_result" || fail unrelated_pid_reason_missing
kill -0 "$model_pid" 2>/dev/null || fail unrelated_pid_was_terminated
[[ -f "$test_root/home/Documents/Ishikawa-v1.3-attended/state/run/attended-v1.3.pid" ]] \
  || fail unrelated_pid_evidence_removed
rm -- "$test_root/home/Documents/Ishikawa-v1.3-attended/state/run/attended-v1.3.pid"

run_target restoration-failure --target-launch 5 0 1 0 1
(( target_status != 0 )) || fail automatic_restoration_failure_accepted
grep -Fxq 'reason=v1_3_web_start_failed' "$last_result" || fail restoration_failure_root_reason_missing
grep -Fq 'Automatic v1.2 restoration also failed.' "$last_result" || fail restoration_failure_detail_missing
grep -Fxq 'v1_2_restored=false;cleanup=blocked' "$last_result" || fail restoration_failure_cleanup_marker_missing
[[ "$(<"$test_root/state/private-pg-port")" == none ]] || fail restoration_failure_v1_3_cluster_left_running

reset_fresh_state
mkdir -p -- "$test_root/home/Documents/Ishikawa-v1.3-attended"
run_target partial-state --target-launch 5
(( target_status != 0 )) || fail partial_state_accepted
grep -Fxq 'reason=partial_v1_3_state_found' "$last_result" || fail partial_state_reason_missing
[[ "$(<"$test_root/state/unit")" == active \
    && -d "$test_root/home/Documents/Ishikawa-v1.3-attended" ]] \
  || fail partial_state_changed_or_removed

reset_fresh_state
ln -s -- "$test_root/state" "$test_root/home/Documents/Ishikawa-v1.3-attended"
run_target unsafe-runtime-root --target-launch 5
(( target_status != 0 )) || fail unsafe_runtime_root_accepted
grep -Fxq 'reason=durable_runtime_control_path_unsafe' "$last_result" || fail unsafe_runtime_root_reason_missing
[[ -L "$test_root/home/Documents/Ishikawa-v1.3-attended" ]] || fail unsafe_runtime_root_removed

candidate_after="$(cd -- "$candidate" && find . -type f -printf '%P\n' | sort | while IFS= read -r file; do sha256sum -- "$file"; done)"
[[ "$candidate_after" == "$(<"$test_root/payload/candidate-SHA256SUMS")" ]] \
  || fail qualified_candidate_changed

printf '%s\n' \
  'fresh_ingestion_failure_cleanup=pass;model_preflight_no_mutation=pass;partial_state_rejection=pass' \
  'post_switchover_launch_failure=pass;automatic_v1_2_restoration=pass;durable_database_preservation=pass' \
  'automatic_restoration_failure_reporting=pass;failed_restore_v1_3_cleanup=pass' \
  'pre_switchover_reuse_failure_cleanup=pass' \
  'unrelated_pid_protection=pass;partial_state_preservation=pass' \
  'unsafe_runtime_path_rejection_and_preservation=pass' \
  'durable_reuse=pass;installed_layout_parity=pass;real_configuration_validator=pass;real_catalog_manifest_validators=pass' \
  'attended_launch=pass;human_acceptance=pass;explicit_rollback=pass;v1_2_database_untouched=pass;candidate_unchanged=pass'
printf '\nSCRIPT RESULT\nattended_v1_3_target_test=pass\n'
