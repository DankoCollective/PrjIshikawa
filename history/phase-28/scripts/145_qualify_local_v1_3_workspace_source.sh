#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the local Ishikawa v1.3 citation, reconstruction, and three-pane
#   workspace source before any live local service is started.
#
# Mental model:
#   Preserve accepted v1.2, bind the frozen v1.3 decisions, run the complete
#   native regression suite, then use the existing architecture-matched Node
#   24 / Next.js image to run JavaScript tests and a production build. The
#   image is inspected locally and is never pulled or changed.
#
# Inputs or prerequisites:
#   The working Ishikawa source and the existing
#   node-24-slim-nextjs-16-4-1 image for this host architecture.
#
# Outputs:
#   One content-free local qualification report. No service, database, model,
#   accepted package, corpus, or remote host is contacted or changed.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/145_qualify_local_v1_3_workspace_source.sh --run

usage() {
  sed -n '3,23p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Run native tests, containerized JavaScript tests, and build.' \
    '  --validate-only Validate source and shell structure without Docker execution.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly WEB_ROOT="$PRODUCT_ROOT/application/web"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly TEST_RUNNER="$PRODUCT_ROOT/scripts/run-local-validation-tests.sh"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.3-workspace-source"
readonly EXPECTED_NATIVE_TESTS=388
readonly EXPECTED_JAVASCRIPT_TESTS=12

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_145_v1_3_workspace_source=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_145_v1_3_workspace_source=blocked;reason=mode_invalid\n' >&2
  exit 2
}

readonly -a REQUIRED_FILES=(
  "$DECISIONS"
  "$TEST_RUNNER"
  "$PYTHON_ROOT/ishikawa/api_contract.py"
  "$PYTHON_ROOT/ishikawa/generation.py"
  "$PYTHON_ROOT/ishikawa/http_listener.py"
  "$PYTHON_ROOT/ishikawa/postgres_retrieval.py"
  "$PYTHON_ROOT/ishikawa/readiness.py"
  "$PYTHON_ROOT/ishikawa/reconstruction.py"
  "$PYTHON_ROOT/ishikawa/retrieval_service.py"
  "$WEB_ROOT/app/globals.css"
  "$WEB_ROOT/app/api/dependencies/route.js"
  "$WEB_ROOT/app/api/v1/chat/route.js"
  "$WEB_ROOT/components/chat-workspace.js"
  "$WEB_ROOT/lib/chat-contract.mjs"
  "$WEB_ROOT/public/theme-init.js"
  "$WEB_ROOT/tests/presentation.test.mjs"
  "$WEB_ROOT/package.json"
  "$WEB_ROOT/next.config.mjs"
)

for required in awk bash date dirname dpkg grep mkdir mktemp python3 rm sed sha256sum stat tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_145_v1_3_workspace_source=blocked;reason=local_command_missing;command=%s\n' "$required" >&2
    exit 2
  }
done
for file in "${REQUIRED_FILES[@]}"; do
  [[ -f "$file" && ! -L "$file" && -r "$file" ]] || {
    printf 'script_145_v1_3_workspace_source=blocked;reason=required_input_unsafe\n' >&2
    exit 2
  }
done
for decision in V13-01 V13-02 V13-03 V13-04 V13-05 V13-06 V13-07 V13-08 V13-09 V13-10 V13-11; do
  grep -Eq "^\| \`$decision\` \|.*\| FROZEN \|$" "$DECISIONS" || {
    printf 'script_145_v1_3_workspace_source=blocked;reason=decision_list_incomplete\n' >&2
    exit 1
  }
done

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(path.read_text(encoding="utf-8"), str(path), "exec") for path in pathlib.Path(sys.argv[1]).glob("*.py")]' \
  "$PYTHON_ROOT/ishikawa"

for contract in \
  'ishikawa.chat-response.v2' \
  'document_identifier' \
  'context_budget' \
  'inspect_dependencies' \
  'requested_complete_section' \
  'sessionStorage' \
  'Citations' \
  'Context budget'; do
  grep -FRq -- "$contract" \
    "$PRODUCT_ROOT/application" \
    "$PRODUCT_ROOT/tests" \
    "$PRODUCT_ROOT/docs" || {
      printf 'script_145_v1_3_workspace_source=blocked;reason=required_contract_missing\n' >&2
      exit 1
    }
done

source_manifest_sha256="$({
  for file in "${REQUIRED_FILES[@]}"; do
    sha256sum "$file"
  done
} | sha256sum | awk '{print $1}')"
decision_sha256="$(sha256sum "$DECISIONS" | awk '{print $1}')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_local_v1_3_workspace_source' \
    "script_sha256=$script_sha256;decision_sha256=$decision_sha256;source_manifest_sha256=$source_manifest_sha256" \
    'v1_2_changed=false;native_tests=not_run;javascript_tests=not_run;next_build=not_run' \
    'target_contact=false;database_contact=false;model_contact=false;service_changed=false;package_changed=false;image_pulled=false' \
    'script_145_v1_3_workspace_source=pass'
  exit 0
fi

for required in docker; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_145_v1_3_workspace_source=blocked;reason=container_command_missing\n' >&2
    exit 2
  }
done

docker_command=(docker)
if ! docker info >/dev/null 2>&1; then
  command -v sudo >/dev/null 2>&1 || {
    printf 'script_145_v1_3_workspace_source=blocked;reason=sudo_command_missing\n' >&2
    exit 2
  }
  printf 'milestone=container_access;state=awaiting_attended_sudo\n'
  sudo -v
  docker_command=(sudo docker)
  "${docker_command[@]}" info >/dev/null 2>&1 || {
    printf 'script_145_v1_3_workspace_source=blocked;reason=docker_access_failed\n' >&2
    exit 2
  }
fi

architecture="$(dpkg --print-architecture)"
case "$architecture" in
  arm64|amd64) ;;
  *) printf 'script_145_v1_3_workspace_source=blocked;reason=host_architecture_unsupported\n' >&2; exit 2 ;;
esac
image="node-24-slim-nextjs-16-4-1:$architecture"
"${docker_command[@]}" image inspect "$image" >/dev/null 2>&1 || {
  printf 'script_145_v1_3_workspace_source=blocked;reason=required_local_image_missing;image=%s\n' "$image" >&2
  exit 2
}
[[ "$("${docker_command[@]}" image inspect "$image" --format '{{.Architecture}}')" == "$architecture" ]] || {
  printf 'script_145_v1_3_workspace_source=blocked;reason=image_architecture_mismatch\n' >&2
  exit 2
}

umask 077
work_root="$(mktemp -d /tmp/ishikawa-script-145.XXXXXX)"
report_path=''
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  [[ "$work_root" == /tmp/ishikawa-script-145.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf 'milestone=native_tests;state=start\n'
native_result="$work_root/native-tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$native_result" 2>&1 || {
  printf 'script_145_v1_3_workspace_source=blocked;reason=native_test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$native_result" | awk '{print $1}')" "$(stat -c '%s' "$native_result")" >&2
  exit 1
}
grep -Fq "Ran $EXPECTED_NATIVE_TESTS tests" "$native_result" || {
  printf 'script_145_v1_3_workspace_source=blocked;reason=native_test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$native_result" || {
  printf 'script_145_v1_3_workspace_source=blocked;reason=native_test_marker_absent\n' >&2
  exit 1
}
printf 'milestone=native_tests;state=pass;tests=%s\n' "$EXPECTED_NATIVE_TESTS"

declare -a web_mounts=(
  --mount "type=bind,src=$WEB_ROOT/app,dst=/opt/nextjs/app,readonly"
  --mount "type=bind,src=$WEB_ROOT/components,dst=/opt/nextjs/components,readonly"
  --mount "type=bind,src=$WEB_ROOT/lib,dst=/opt/nextjs/lib,readonly"
  --mount "type=bind,src=$WEB_ROOT/public,dst=/opt/nextjs/public,readonly"
  --mount "type=bind,src=$WEB_ROOT/tests,dst=/opt/nextjs/tests,readonly"
  --mount "type=bind,src=$WEB_ROOT/package.json,dst=/opt/nextjs/package.json,readonly"
  --mount "type=bind,src=$WEB_ROOT/next.config.mjs,dst=/opt/nextjs/next.config.mjs,readonly"
)

printf 'milestone=javascript_tests;state=start\n'
javascript_result="$work_root/javascript-tests.txt"
"${docker_command[@]}" run --rm --network none \
  "${web_mounts[@]}" \
  "$image" node --test --test-reporter=tap \
  tests/chat-contract.test.mjs tests/presentation.test.mjs tests/runtime-config.test.mjs \
  >"$javascript_result" 2>&1 || {
    printf 'script_145_v1_3_workspace_source=blocked;reason=javascript_tests_failed;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
      "$(sha256sum "$javascript_result" | awk '{print $1}')" "$(stat -c '%s' "$javascript_result")" >&2
    exit 1
  }
for expected in \
  "# tests $EXPECTED_JAVASCRIPT_TESTS" \
  "# pass $EXPECTED_JAVASCRIPT_TESTS" \
  '# fail 0'; do
  grep -Eq "^[[:space:]]*$expected[[:space:]]*$" "$javascript_result" || {
    printf 'script_145_v1_3_workspace_source=blocked;reason=javascript_test_count_mismatch\n' >&2
    exit 1
  }
done
printf 'milestone=javascript_tests;state=pass;tests=%s\n' "$EXPECTED_JAVASCRIPT_TESTS"

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
  printf 'script_145_v1_3_workspace_source=blocked;reason=next_build_failed;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$build_result" | awk '{print $1}')" "$(stat -c '%s' "$build_result")" >&2
  exit 1
fi
printf 'milestone=next_build;state=pass\n'

mkdir -p -- "$REPORT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/v1_3_workspace_source_${timestamp}_XXXXXX.txt")"
{
  printf '%s\n' \
    'purpose=qualify_local_v1_3_workspace_source' \
    "script_sha256=$script_sha256;decision_sha256=$decision_sha256;source_manifest_sha256=$source_manifest_sha256" \
    "architecture=$architecture;image=$image;image_pulled=false;image_changed=false" \
    "native_tests=$EXPECTED_NATIVE_TESTS;failures=0;errors=0;javascript_tests=$EXPECTED_JAVASCRIPT_TESTS;next_build=pass" \
    'response_schema=ishikawa.chat-response.v2;complete_section=true;expanded_display_citations=true;document_identifier=true' \
    'session_chats=true;chat_rename=true;context_budget=true;citation_pane=true;dependency_indicator=true;anderson_visual_alignment=true;theme_toggle=true' \
    'accepted_v1_2_changed=false;target_contact=false;database_contact=false;model_contact=false;service_changed=false;package_changed=false' \
    'script_145_v1_3_workspace_source=pass;next_gate=launch_local_v1_3_candidate'
} | tee "$report_path"
chmod 0600 "$report_path" 2>/dev/null || true
