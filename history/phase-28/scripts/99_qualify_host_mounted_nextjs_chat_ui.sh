#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the host-resident Ishikawa Chat UI in the unchanged Node 24 and
#   Next.js 16.4.1 runtime image.
#
# Mental model:
#   Bind to accepted Retrieval API lifecycle evidence, run every native test,
#   inspect the complete web source, then use the already-local architecture-
#   matching image to run JavaScript tests, build Next.js, and exercise the
#   web page, health routes, and server-side chat proxy against a safe fixture.
#
# Inputs or prerequisites:
#   Accepted Script 98 evidence, current Ishikawa source and configuration,
#   CODING_STANDARD.md, Python 3.12, PyYAML, Docker, curl, and the existing
#   node-24-slim-nextjs-16-4-1 image for this host architecture.
#
# Outputs:
#   Content-free local web qualification evidence. The command does not pull,
#   rebuild, retag, or alter an image. Temporary containers and the fixture are
#   stopped and removed. No target, database, model, credential, corpus,
#   service installation, port forwarding, or persistent container is changed.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/99_qualify_host_mounted_nextjs_chat_ui.sh --run

usage() {
  sed -n '3,27p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Run the local container proof and retain content-free evidence.' \
    '  --validate-only Run native tests and source validation without Docker.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly WEB_ROOT="$ISHIKAWA_ROOT/application/web"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly CONTRACT="$ISHIKAWA_ROOT/docs/CHAT_UI.md"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_nextjs_chat_ui.py"
readonly FIXTURE="$SCRIPT_DIR/mock_ishikawa_retrieval_for_web.py"
readonly CODING_STANDARD="$REPO_ROOT/CODING_STANDARD.md"
readonly ACCEPTED_REPORT="$REPO_ROOT/local/reports/ishikawa-native-service-lifecycle/native_service_lifecycle_20261021T005424Z_ViZ6kw.txt"
readonly ACCEPTED_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/native-service-lifecycle/native_service_lifecycle_qualification_20261021T005424Z.json"
readonly ACCEPTED_CHECKSUM="$ACCEPTED_ARTIFACT.sha256"
readonly ACCEPTED_REPORT_SHA256='fb787b7e3792bdfd04e6e32e2da74af5d6a2c911a1fe9ccc9072ee85abfcbafb'
readonly ACCEPTED_ARTIFACT_SHA256='a6568eab20b596dadca9a836759a1fef013d906412a358b6eaaa84655f913f44'
readonly ACCEPTED_CHECKSUM_SHA256='82f19339a88f236de0587da4dc37a4a6f463430735fa05f03605229b8ce32498'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-nextjs-chat-ui"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/nextjs-chat-ui"

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_99_nextjs_chat_ui=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_99_nextjs_chat_ui=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in awk bash basename cat chmod cp curl date find grep kill mkdir mktemp mv python3 rm sed seq sha256sum sleep ss stat tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_99_nextjs_chat_ui=blocked;reason=local_command_missing;command=%s\n' "$required" >&2
    exit 2
  }
done
mapfile -t web_sources < <(find "$WEB_ROOT" -type f -print | sort)
for required_file in \
  "$TEST_RUNNER" "$CONTRACT" "$EVALUATOR" "$FIXTURE" "$CODING_STANDARD" \
  "$ACCEPTED_REPORT" "$ACCEPTED_ARTIFACT" "$ACCEPTED_CHECKSUM" \
  "${web_sources[@]}"; do
  [[ -f "$required_file" && ! -L "$required_file" && -r "$required_file" ]] || {
    printf 'script_99_nextjs_chat_ui=blocked;reason=required_input_unsafe\n' >&2
    exit 2
  }
done
(( ${#web_sources[@]} == 13 )) || {
  printf 'script_99_nextjs_chat_ui=blocked;reason=web_source_inventory_invalid\n' >&2
  exit 2
}

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_99_nextjs_chat_ui=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}
check_sha256 "$ACCEPTED_REPORT" "$ACCEPTED_REPORT_SHA256" 'accepted_report'
check_sha256 "$ACCEPTED_ARTIFACT" "$ACCEPTED_ARTIFACT_SHA256" 'accepted_artifact'
check_sha256 "$ACCEPTED_CHECKSUM" "$ACCEPTED_CHECKSUM_SHA256" 'accepted_checksum'
(
  cd -- "$(dirname -- "$ACCEPTED_ARTIFACT")"
  sha256sum --check --strict "$(basename -- "$ACCEPTED_CHECKSUM")" >/dev/null
) || { printf 'script_99_nextjs_chat_ui=blocked;reason=accepted_checksum_failed\n' >&2; exit 2; }
for fact in \
  'native_service_lifecycle_qualification=pass' \
  'systemd_unit_verify=pass;installed_config=pass;liveness=pass;sigterm_cleanup=pass;boot_enabled=false' \
  'local_tests=360;failures=0;errors=0' \
  'script_98_native_service_lifecycle=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_REPORT" || {
    printf 'script_99_nextjs_chat_ui=blocked;reason=accepted_report_contract_failed\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$EVALUATOR" "$FIXTURE"
for portable_source in "${web_sources[@]}" "$CONTRACT"; do
  if grep -Eiq 'phase[-_ ]?[0-9]+|(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)|Danko|org[_ -]?lab|Agent|repository|Script[[:space:]_-]*[0-9]+' "$portable_source"; then
    printf 'script_99_nextjs_chat_ui=blocked;reason=installed_source_jargon_found\n' >&2
    exit 2
  fi
done

work_root="$(mktemp -d /tmp/ishikawa-script-99.XXXXXX)"
fixture_pid=''
container_name=''
artifact_committed=false
artifact_path=''
checksum_path=''
declare -a docker_command=()
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ -n "$container_name" && ${#docker_command[@]} -gt 0 ]]; then
    "${docker_command[@]}" rm --force -- "$container_name" >/dev/null 2>&1 || true
  fi
  if [[ -n "$fixture_pid" ]] && kill -0 "$fixture_pid" 2>/dev/null; then
    kill -TERM "$fixture_pid" 2>/dev/null || true
    wait "$fixture_pid" 2>/dev/null || true
  fi
  if [[ "$artifact_committed" != true ]]; then
    [[ "$artifact_path" == "$ARTIFACT_ROOT"/nextjs_chat_ui_qualification_*.json ]] && rm -f -- "$artifact_path"
    [[ "$checksum_path" == "$ARTIFACT_ROOT"/nextjs_chat_ui_qualification_*.json.sha256 ]] && rm -f -- "$checksum_path"
  fi
  if [[ "$work_root" == /tmp/ishikawa-script-99.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf 'milestone=native_tests;state=start\n'
test_result="$work_root/native-tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  printf 'script_99_nextjs_chat_ui=blocked;reason=test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$test_result" | awk '{print $1}')" "$(stat -c '%s' "$test_result")" >&2
  exit 1
}
grep -Fq 'Ran 360 tests' "$test_result" || {
  printf 'script_99_nextjs_chat_ui=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_99_nextjs_chat_ui=blocked;reason=test_pass_marker_absent\n' >&2
  exit 1
}
printf 'milestone=native_tests;state=pass;tests=360\n'

qualification="$work_root/qualification.json"
if [[ "$validate_only" == true ]]; then
  PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" \
    --web-root "$WEB_ROOT" \
    --architecture source-only \
    --runtime-proven false \
    --output "$qualification"
  printf '%s\n' \
    'javascript_tests=not-run;next_build=not-run;http_proof=not-run' \
    'local_tests=360;failures=0;errors=0' \
    'script_99_nextjs_chat_ui_source=pass'
  exit 0
fi

for required in docker dpkg; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_99_nextjs_chat_ui=blocked;reason=container_command_missing;command=%s\n' "$required" >&2
    exit 2
  }
done
docker_command=(docker)
if ! docker info >/dev/null 2>&1; then
  command -v sudo >/dev/null 2>&1 || {
    printf 'script_99_nextjs_chat_ui=blocked;reason=sudo_command_missing\n' >&2
    exit 2
  }
  printf 'milestone=container_access;state=awaiting_attended_sudo\n'
  sudo -v
  docker_command=(sudo docker)
  "${docker_command[@]}" info >/dev/null 2>&1 || {
    printf 'script_99_nextjs_chat_ui=blocked;reason=docker_access_failed\n' >&2
    exit 2
  }
fi

architecture="$(dpkg --print-architecture)"
case "$architecture" in
  arm64|amd64) ;;
  *) printf 'script_99_nextjs_chat_ui=blocked;reason=host_architecture_unsupported\n' >&2; exit 2 ;;
esac
image="node-24-slim-nextjs-16-4-1:$architecture"
"${docker_command[@]}" image inspect "$image" >/dev/null 2>&1 || {
  printf 'script_99_nextjs_chat_ui=blocked;reason=required_local_image_missing;image=%s\n' "$image" >&2
  exit 2
}
image_architecture="$("${docker_command[@]}" image inspect "$image" --format '{{.Architecture}}')"
[[ "$image_architecture" == "$architecture" ]] || {
  printf 'script_99_nextjs_chat_ui=blocked;reason=image_architecture_mismatch\n' >&2
  exit 2
}

version_result="$work_root/runtime-versions.txt"
"${docker_command[@]}" run --rm --network none "$image" node -e \
  'console.log(`node_version=${process.version}`); console.log(`next_version=${require("next/package.json").version}`); console.log(`react_version=${require("react/package.json").version}`)' \
  >"$version_result"
grep -Fxq 'node_version=v24.22.0' "$version_result" || {
  printf 'script_99_nextjs_chat_ui=blocked;reason=node_version_mismatch\n' >&2; exit 1;
}
grep -Fxq 'next_version=16.4.1' "$version_result" || {
  printf 'script_99_nextjs_chat_ui=blocked;reason=next_version_mismatch\n' >&2; exit 1;
}
grep -Fxq 'react_version=19.2.0' "$version_result" || {
  printf 'script_99_nextjs_chat_ui=blocked;reason=react_version_mismatch\n' >&2; exit 1;
}

declare -a web_mounts=(
  --mount "type=bind,src=$WEB_ROOT/app,dst=/opt/nextjs/app,readonly"
  --mount "type=bind,src=$WEB_ROOT/components,dst=/opt/nextjs/components,readonly"
  --mount "type=bind,src=$WEB_ROOT/lib,dst=/opt/nextjs/lib,readonly"
  --mount "type=bind,src=$WEB_ROOT/tests,dst=/opt/nextjs/tests,readonly"
  --mount "type=bind,src=$WEB_ROOT/package.json,dst=/opt/nextjs/package.json,readonly"
  --mount "type=bind,src=$WEB_ROOT/next.config.mjs,dst=/opt/nextjs/next.config.mjs,readonly"
)

printf 'milestone=javascript_tests;state=start\n'
javascript_result="$work_root/javascript-tests.txt"
"${docker_command[@]}" run --rm --network none \
  "${web_mounts[@]}" \
  "$image" node --test --test-reporter=tap \
  tests/chat-contract.test.mjs tests/runtime-config.test.mjs \
  >"$javascript_result" 2>&1 || {
  printf 'script_99_nextjs_chat_ui=blocked;reason=javascript_tests_failed;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$javascript_result" | awk '{print $1}')" "$(stat -c '%s' "$javascript_result")" >&2
  exit 1
}
javascript_counts="$(python3 -B - "$javascript_result" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="strict")
observed: dict[str, int] = {}
for name, value in re.findall(
    r"^\s*#\s+(tests|pass|fail)\s+([0-9]+)\s*$",
    text,
    flags=re.MULTILINE,
):
    if name in observed:
        raise SystemExit(1)
    observed[name] = int(value)
if set(observed) != {"tests", "pass", "fail"}:
    raise SystemExit(1)
print(f"tests={observed['tests']};pass={observed['pass']};fail={observed['fail']}")
PY
)" || {
  printf 'script_99_nextjs_chat_ui=blocked;reason=javascript_test_summary_invalid\n' >&2
  exit 1
}
[[ "$javascript_counts" == 'tests=8;pass=8;fail=0' ]] || {
  printf 'script_99_nextjs_chat_ui=blocked;reason=javascript_test_count_mismatch;%s\n' \
    "$javascript_counts" >&2
  exit 1
}
printf 'milestone=javascript_tests;state=pass;tests=8\n'

printf 'milestone=next_build;state=start\n'
build_result="$work_root/next-build.txt"
"${docker_command[@]}" run --rm --network none \
  -e ISHIKAWA_PRODUCT_DISPLAY_NAME=Ishikawa \
  -e ISHIKAWA_RETRIEVAL_BASE_URL=http://127.0.0.1:1384 \
  "${web_mounts[@]}" \
  "$image" npm run build >"$build_result" 2>&1 &
build_pid=$!
while kill -0 "$build_pid" 2>/dev/null; do
  sleep 5
  kill -0 "$build_pid" 2>/dev/null && printf 'milestone=next_build;state=running\n'
done
set +e
wait "$build_pid"
build_status=$?
set -e
if (( build_status != 0 )); then
  printf 'script_99_nextjs_chat_ui=blocked;reason=next_build_failed;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$build_result" | awk '{print $1}')" "$(stat -c '%s' "$build_result")" >&2
  exit 1
fi
printf 'milestone=next_build;state=pass\n'

port_file="$work_root/fixture-port.txt"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$FIXTURE" --port-file "$port_file" >"$work_root/fixture.txt" 2>&1 &
fixture_pid=$!
for _attempt in $(seq 1 50); do
  [[ -s "$port_file" ]] && break
  kill -0 "$fixture_pid" 2>/dev/null || break
  sleep 0.1
done
[[ -s "$port_file" ]] || {
  printf 'script_99_nextjs_chat_ui=blocked;reason=fixture_start_failed\n' >&2
  exit 1
}
fixture_port="$(cat "$port_file")"
[[ "$fixture_port" =~ ^[0-9]+$ ]] || {
  printf 'script_99_nextjs_chat_ui=blocked;reason=fixture_port_invalid\n' >&2
  exit 1
}
web_port="$(python3 -B - <<'PY'
import socket
with socket.socket() as listener:
    listener.bind(("127.0.0.1", 0))
    print(listener.getsockname()[1])
PY
)"
container_name="ishikawa-web-qualification-$(date -u +%Y%m%dT%H%M%SZ)-$$"
"${docker_command[@]}" inspect "$container_name" >/dev/null 2>&1 && {
  printf 'script_99_nextjs_chat_ui=blocked;reason=temporary_container_name_in_use\n' >&2
  exit 1
}

printf 'milestone=http_proof;state=start\n'
"${docker_command[@]}" run --detach --rm \
  --name "$container_name" \
  --network host \
  -e ISHIKAWA_PRODUCT_DISPLAY_NAME=Ishikawa \
  -e "ISHIKAWA_RETRIEVAL_BASE_URL=http://127.0.0.1:$fixture_port" \
  "${web_mounts[@]}" \
  "$image" next dev --hostname 127.0.0.1 --port "$web_port" \
  >"$work_root/container-id.txt"
for _attempt in $(seq 1 120); do
  live_code="$(curl --silent --output "$work_root/live.json" --write-out '%{http_code}' --max-time 2 "http://127.0.0.1:$web_port/api/live" 2>/dev/null || true)"
  [[ "$live_code" == 200 ]] && break
  sleep 0.25
done
if [[ "${live_code:-}" != 200 ]]; then
  "${docker_command[@]}" logs "$container_name" >"$work_root/container-log.txt" 2>&1 || true
  printf 'script_99_nextjs_chat_ui=blocked;reason=web_start_failed;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$work_root/container-log.txt" | awk '{print $1}')" "$(stat -c '%s' "$work_root/container-log.txt")" >&2
  exit 1
fi
[[ "$(cat "$work_root/live.json")" == '{"schema":"ishikawa.web-health.v1","status":"live"}' ]] || {
  printf 'script_99_nextjs_chat_ui=blocked;reason=web_liveness_contract_failed\n' >&2
  exit 1
}
ready_code="$(curl --silent --show-error --output "$work_root/ready.json" --write-out '%{http_code}' --max-time 5 "http://127.0.0.1:$web_port/api/ready")"
[[ "$ready_code" == 200 && "$(cat "$work_root/ready.json")" == '{"schema":"ishikawa.web-health.v1","status":"ready"}' ]] || {
  printf 'script_99_nextjs_chat_ui=blocked;reason=web_readiness_contract_failed\n' >&2
  exit 1
}
curl --silent --show-error --output "$work_root/page.html" --max-time 5 "http://127.0.0.1:$web_port/"
grep -Fq '>Ishikawa<' "$work_root/page.html" && grep -Fq 'What would you like to understand?' "$work_root/page.html" || {
  printf 'script_99_nextjs_chat_ui=blocked;reason=web_page_contract_failed\n' >&2
  exit 1
}
python3 -B - "$work_root/chat-request.json" <<'PY'
import json
import sys
from pathlib import Path

request = {
    "conversation_id": "a" * 64,
    "filters": {"document_classes": [], "document_keys": []},
    "history": [],
    "message": "How are reports submitted?",
    "schema": "ishikawa.chat-request.v1",
    "source_references": [],
    "turn_id": "d" * 64,
}
Path(sys.argv[1]).write_text(json.dumps(request, separators=(",", ":")), encoding="utf-8")
PY
chat_code="$(curl --silent --show-error --output "$work_root/chat-response.json" --write-out '%{http_code}' --max-time 10 \
  --header 'Content-Type: application/json' \
  --data-binary "@$work_root/chat-request.json" \
  "http://127.0.0.1:$web_port/api/v1/chat")"
[[ "$chat_code" == 200 ]] || {
  printf 'script_99_nextjs_chat_ui=blocked;reason=web_chat_proxy_http_failed\n' >&2
  exit 1
}
python3 -B - "$work_root/chat-response.json" <<'PY' || {
import json
import sys
from pathlib import Path

response = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if response.get("schema") != "ishikawa.chat-response.v1":
    raise SystemExit(1)
if response.get("status") != "answered" or response.get("answer") != "Reports are submitted promptly.":
    raise SystemExit(1)
if response.get("conversation_id") != "a" * 64 or response.get("turn_id") != "d" * 64:
    raise SystemExit(1)
if response.get("sources", [{}])[0].get("source_label") != "Source 1":
    raise SystemExit(1)
PY
  printf 'script_99_nextjs_chat_ui=blocked;reason=web_chat_proxy_contract_failed\n' >&2
  exit 1
}
"${docker_command[@]}" stop --time 10 "$container_name" >/dev/null
container_name=''
kill -TERM "$fixture_pid"
wait "$fixture_pid" 2>/dev/null || true
fixture_pid=''
if ss -H -ltn "( sport = :$web_port or sport = :$fixture_port )" | grep -q .; then
  printf 'script_99_nextjs_chat_ui=blocked;reason=temporary_listener_cleanup_failed\n' >&2
  exit 1
fi
printf 'milestone=http_proof;state=pass;liveness=pass;readiness=pass;chat_proxy=pass;cleanup=pass\n'

PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" \
  --web-root "$WEB_ROOT" \
  --architecture "$architecture" \
  --runtime-proven true \
  --output "$qualification" >"$work_root/evaluation.txt"
for fact in \
  'web_source=host-resident;container_image_changed=false' \
  'browser_path=/api/v1/chat;native_path=/v1/chat;browser_direct_retrieval=false' \
  'history_turns=12;history_characters=65536;source_references=20' \
  'health=/api/live,/api/ready;open_download=false' \
  "runtime_proven=true;architecture=$architecture" \
  'target_contact=false;database_changed=false;model_call=false' \
  'nextjs_chat_ui_qualification=pass'; do
  grep -Fqx "$fact" "$work_root/evaluation.txt" || {
    printf 'script_99_nextjs_chat_ui=blocked;reason=evaluation_contract_mismatch\n' >&2
    exit 1
  }
done

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
fixture_sha256="$(sha256sum "$FIXTURE" | awk '{print $1}')"
contract_sha256="$(sha256sum "$CONTRACT" | awk '{print $1}')"
web_source_identity="$(while IFS= read -r source; do sha256sum "$source"; done < <(printf '%s\n' "${web_sources[@]}") | sha256sum | awk '{print $1}')"
qualification_sha256="$(sha256sum "$qualification" | awk '{print $1}')"
qualification_bytes="$(stat -c '%s' "$qualification")"

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/nextjs_chat_ui_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  printf 'script_99_nextjs_chat_ui=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
cp -- "$qualification" "$artifact_path"
printf '%s  %s\n' "$qualification_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true
(
  cd -- "$ARTIFACT_ROOT"
  sha256sum --check --strict "$(basename -- "$checksum_path")" >/dev/null
) || { printf 'script_99_nextjs_chat_ui=blocked;reason=retained_checksum_failed\n' >&2; exit 1; }
artifact_committed=true

report_path="$(mktemp "$REPORT_ROOT/nextjs_chat_ui_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=qualify_host_mounted_nextjs_chat_ui'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256;fixture_sha256=$fixture_sha256"
emit "contract_sha256=$contract_sha256;web_source_identity=$web_source_identity;web_source_files=${#web_sources[@]}"
emit "accepted_script_98_report_sha256=$ACCEPTED_REPORT_SHA256;accepted_script_98_artifact_sha256=$ACCEPTED_ARTIFACT_SHA256"
emit "image=$image;architecture=$architecture;node=24.22.0;next=16.4.1;react=19.2.0"
emit 'authorized_actions=read_checksum_bound_sources_run_native_and_javascript_tests_run_temporary_local_container_build_start_local_fixture_call_local_web_routes_stop_and_remove_temporary_runtime_retain_content_free_evidence'
emit 'non_actions=no_pull_build_retag_or_image_change_no_target_database_model_credential_corpus_service_install_or_forwarding_contact_or_change_no_persistent_container_or_process'
while IFS= read -r line; do emit "$line"; done <"$work_root/evaluation.txt"
emit 'native_tests=360;javascript_tests=8;next_build=pass'
emit 'http_proof=liveness:pass,readiness:pass,page:pass,chat_proxy:pass;temporary_cleanup=pass'
emit 'credential_read=false;target_contact=false;database_changed=false;model_call=false;image_changed=false;service_changed=false'
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$qualification_sha256;accepted_artifact_bytes=$qualification_bytes;accepted_checksum=$checksum_path"
emit "script_99_nextjs_chat_ui=pass;local_report=$report_path;next_gate=implement_explicit_stack_control"
chmod 0600 "$report_path" 2>/dev/null || true
