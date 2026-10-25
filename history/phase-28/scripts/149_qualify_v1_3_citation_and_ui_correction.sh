#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the local Ishikawa v1.3 additive citation-integrity correction and
#   the operator-requested workspace simplification before another live launch.
#
# Mental model:
#   Preserve accepted v1.2 and the earlier v1.3 evidence, prove every accepted
#   generation citation remains displayable, prove the duplicate dependency
#   header, left session summary, and visible CONTENT-FREE label are absent,
#   then rerun the complete native and browser-source qualification.
#
# Inputs or prerequisites:
#   The local Ishikawa working source and the already-present architecture-
#   matched node-24-slim-nextjs-16-4-1 image.
#
# Outputs:
#   One content-free local qualification report. No database, model, remote
#   target, running service, accepted release, package, or image is changed.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/149_qualify_v1_3_citation_and_ui_correction.sh --run

usage() {
  sed -n '3,23p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Run native tests, JavaScript tests, and a production build.' \
    '  --validate-only Validate source and shell structure without Docker execution.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly PYTHON_SOURCE_ROOT="$PYTHON_ROOT/ishikawa"
readonly WEB_ROOT="$PRODUCT_ROOT/application/web"
readonly CONFIG_TEMPLATE_ROOT="$PRODUCT_ROOT/config/templates"
readonly SERVICE_ENTRYPOINT="$PRODUCT_ROOT/scripts/ishikawa-retrieval-api"
readonly TEST_RUNNER="$PRODUCT_ROOT/scripts/run-local-validation-tests.sh"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly RETRIEVAL_DOC="$PRODUCT_ROOT/docs/POSTGRES_RETRIEVAL_ADAPTER.md"
readonly CHAT_UI_DOC="$PRODUCT_ROOT/docs/CHAT_UI.md"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.3-citation-ui-correction"
readonly EXPECTED_NATIVE_TESTS=389
readonly EXPECTED_JAVASCRIPT_TESTS=12
readonly EXPECTED_CANDIDATE_FILES=83

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_149_v1_3_correction=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_149_v1_3_correction=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in \
  awk bash chmod date dirname docker dpkg find grep kill mapfile mkdir mktemp \
  python3 rm sed sha256sum sleep sort stat sudo tee; do
  if [[ "$validate_only" == true && "$required" =~ ^(docker|sudo)$ ]]; then
    continue
  fi
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_149_v1_3_correction=blocked;reason=local_command_missing;command=%s\n' \
      "$required" >&2
    exit 2
  }
done

readonly -a REQUIRED_FILES=(
  "$DECISIONS"
  "$RETRIEVAL_DOC"
  "$CHAT_UI_DOC"
  "$TEST_RUNNER"
  "$PYTHON_SOURCE_ROOT/postgres_retrieval.py"
  "$PRODUCT_ROOT/tests/test_postgres_retrieval.py"
  "$WEB_ROOT/app/globals.css"
  "$WEB_ROOT/components/chat-workspace.js"
  "$WEB_ROOT/tests/presentation.test.mjs"
  "$WEB_ROOT/package.json"
  "$WEB_ROOT/next.config.mjs"
  "$SERVICE_ENTRYPOINT"
)
for file in "${REQUIRED_FILES[@]}"; do
  [[ -f "$file" && ! -L "$file" && -r "$file" ]] || {
    printf 'script_149_v1_3_correction=blocked;reason=required_input_unsafe\n' >&2
    exit 2
  }
done

for decision in V13-01 V13-02 V13-03 V13-04 V13-05 V13-06 V13-07 V13-08 V13-09 V13-10 V13-11; do
  grep -Eq "^\| \`$decision\` \|.*\| FROZEN \|$" "$DECISIONS" || {
    printf 'script_149_v1_3_correction=blocked;reason=decision_list_incomplete\n' >&2
    exit 1
  }
done

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER" "$SERVICE_ENTRYPOINT"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(path.read_text(encoding="utf-8"), str(path), "exec") for path in pathlib.Path(sys.argv[1]).glob("*.py")]' \
  "$PYTHON_SOURCE_ROOT"

mapfile -t candidate_files < <(
  {
    find \
      "$PYTHON_SOURCE_ROOT" \
      "$WEB_ROOT/app" \
      "$WEB_ROOT/components" \
      "$WEB_ROOT/lib" \
      "$WEB_ROOT/public" \
      "$WEB_ROOT/tests" \
      "$CONFIG_TEMPLATE_ROOT" \
      -type f -print
    printf '%s\n' \
      "$WEB_ROOT/package.json" \
      "$WEB_ROOT/next.config.mjs" \
      "$SERVICE_ENTRYPOINT"
  } | LC_ALL=C sort
)
(( ${#candidate_files[@]} == EXPECTED_CANDIDATE_FILES )) || {
  printf 'script_149_v1_3_correction=blocked;reason=candidate_file_count_mismatch;observed=%s;expected=%s\n' \
    "${#candidate_files[@]}" "$EXPECTED_CANDIDATE_FILES" >&2
  exit 1
}
for file in "${candidate_files[@]}"; do
  [[ -f "$file" && ! -L "$file" && -r "$file" ]] || {
    printf 'script_149_v1_3_correction=blocked;reason=candidate_file_unsafe\n' >&2
    exit 1
  }
done

for removed in 'Content-free' 'Gemma + Nomic ready' 'Session overview'; do
  if grep -Fq -- "$removed" "$WEB_ROOT/components/chat-workspace.js"; then
    printf 'script_149_v1_3_correction=blocked;reason=removed_ui_surface_present\n' >&2
    exit 1
  fi
done
for required_contract in \
  'Model connections' \
  'test_display_expansion_preserves_nonexpanded_generation_citation' \
  'Display expansion is additive' \
  'table-context and page-status projections'; do
  grep -FRq -- "$required_contract" \
    "$PRODUCT_ROOT/application" \
    "$PRODUCT_ROOT/tests" \
    "$PRODUCT_ROOT/docs" || {
      printf 'script_149_v1_3_correction=blocked;reason=correction_contract_missing\n' >&2
      exit 1
    }
done

candidate_manifest_sha256="$({
  for file in "${candidate_files[@]}"; do
    relative_path="${file#"$PRODUCT_ROOT/"}"
    printf '%s  %s\n' "$(sha256sum "$file" | awk '{print $1}')" "$relative_path"
  done
} | sha256sum | awk '{print $1}')"
correction_manifest_sha256="$({
  for file in "${REQUIRED_FILES[@]}"; do
    relative_path="${file#"$REPO_ROOT/"}"
    printf '%s  %s\n' "$(sha256sum "$file" | awk '{print $1}')" "$relative_path"
  done
} | sha256sum | awk '{print $1}')"
decision_sha256="$(sha256sum "$DECISIONS" | awk '{print $1}')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_v1_3_citation_and_ui_correction' \
    "script_sha256=$script_sha256;decision_sha256=$decision_sha256;correction_manifest_sha256=$correction_manifest_sha256" \
    "candidate_manifest_sha256=$candidate_manifest_sha256;candidate_files=$EXPECTED_CANDIDATE_FILES" \
    'native_tests=not_run;javascript_tests=not_run;next_build=not_run' \
    'target_contact=false;database_contact=false;model_contact=false;service_changed=false;package_changed=false;image_pulled=false' \
    'script_149_v1_3_correction=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT"
probe="$(mktemp "$REPORT_ROOT/.write-probe.XXXXXX")"
rm -f -- "$probe"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/v1_3_citation_ui_correction_${timestamp}_XXXXXX.txt")"
chmod 0600 "$report_path" 2>/dev/null || true

emit() {
  printf '%s\n' "$1" | tee -a "$report_path"
}

block() {
  local reason="$1"
  local code="${2:-1}"
  emit "script_149_v1_3_correction=blocked;reason=$reason;report=$report_path"
  exit "$code"
}

emit 'purpose=qualify_v1_3_citation_and_ui_correction'
emit "started_utc=$timestamp;script_sha256=$script_sha256;decision_sha256=$decision_sha256"
emit "correction_manifest_sha256=$correction_manifest_sha256;candidate_manifest_sha256=$candidate_manifest_sha256;candidate_files=$EXPECTED_CANDIDATE_FILES"
emit 'authorized_actions=run_local_native_tests_run_local_containerized_javascript_tests_run_local_containerized_next_build_write_content_free_local_report'
emit 'non_actions=no_remote_contact_no_database_contact_no_model_contact_no_credential_read_no_service_change_no_package_change_no_image_pull_no_accepted_release_change'

docker_command=(docker)
if ! docker info >/dev/null 2>&1; then
  emit 'milestone=container_access;state=awaiting_attended_sudo'
  sudo -v || block 'sudo_authentication_failed' 2
  docker_command=(sudo docker)
  "${docker_command[@]}" info >/dev/null 2>&1 || block 'docker_access_failed' 2
fi

architecture="$(dpkg --print-architecture)"
case "$architecture" in
  arm64|amd64) ;;
  *) block 'host_architecture_unsupported' 2 ;;
esac
image="node-24-slim-nextjs-16-4-1:$architecture"
"${docker_command[@]}" image inspect "$image" >/dev/null 2>&1 || block 'required_local_image_missing' 2
[[ "$("${docker_command[@]}" image inspect "$image" --format '{{.Architecture}}')" == "$architecture" ]] || \
  block 'image_architecture_mismatch' 2

umask 077
work_root="$(mktemp -d /tmp/ishikawa-script-149.XXXXXX)"
build_pid=''
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$build_pid" =~ ^[0-9]+$ ]] && kill -0 "$build_pid" 2>/dev/null; then
    kill -TERM "$build_pid" 2>/dev/null || true
    wait "$build_pid" 2>/dev/null || true
  fi
  [[ "$work_root" == /tmp/ishikawa-script-149.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

emit 'milestone=native_tests;state=start'
native_result="$work_root/native-tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$native_result" 2>&1 || {
  emit "diagnostic_sha256=$(sha256sum "$native_result" | awk '{print $1}');diagnostic_bytes=$(stat -c '%s' "$native_result");raw_output_retained=false"
  block 'native_test_regression'
}
grep -Fq "Ran $EXPECTED_NATIVE_TESTS tests" "$native_result" || block 'native_test_count_mismatch'
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$native_result" || block 'native_test_marker_absent'
emit "milestone=native_tests;state=pass;tests=$EXPECTED_NATIVE_TESTS"

declare -a web_mounts=(
  --mount "type=bind,src=$WEB_ROOT/app,dst=/opt/nextjs/app,readonly"
  --mount "type=bind,src=$WEB_ROOT/components,dst=/opt/nextjs/components,readonly"
  --mount "type=bind,src=$WEB_ROOT/lib,dst=/opt/nextjs/lib,readonly"
  --mount "type=bind,src=$WEB_ROOT/public,dst=/opt/nextjs/public,readonly"
  --mount "type=bind,src=$WEB_ROOT/tests,dst=/opt/nextjs/tests,readonly"
  --mount "type=bind,src=$WEB_ROOT/package.json,dst=/opt/nextjs/package.json,readonly"
  --mount "type=bind,src=$WEB_ROOT/next.config.mjs,dst=/opt/nextjs/next.config.mjs,readonly"
)

emit 'milestone=javascript_tests;state=start'
javascript_result="$work_root/javascript-tests.txt"
"${docker_command[@]}" run --rm --network none \
  "${web_mounts[@]}" \
  "$image" node --test --test-reporter=tap \
  tests/chat-contract.test.mjs tests/presentation.test.mjs tests/runtime-config.test.mjs \
  >"$javascript_result" 2>&1 || {
    emit "diagnostic_sha256=$(sha256sum "$javascript_result" | awk '{print $1}');diagnostic_bytes=$(stat -c '%s' "$javascript_result");raw_output_retained=false"
    block 'javascript_tests_failed'
  }
for expected in \
  "# tests $EXPECTED_JAVASCRIPT_TESTS" \
  "# pass $EXPECTED_JAVASCRIPT_TESTS" \
  '# fail 0'; do
  grep -Eq "^[[:space:]]*$expected[[:space:]]*$" "$javascript_result" || block 'javascript_test_count_mismatch'
done
emit "milestone=javascript_tests;state=pass;tests=$EXPECTED_JAVASCRIPT_TESTS"

emit 'milestone=next_build;state=start'
build_result="$work_root/next-build.txt"
"${docker_command[@]}" run --rm --network none \
  -e ISHIKAWA_PRODUCT_DISPLAY_NAME=Ishikawa \
  -e ISHIKAWA_RETRIEVAL_BASE_URL=http://127.0.0.1:1384 \
  "${web_mounts[@]}" \
  "$image" npm run build >"$build_result" 2>&1 &
build_pid=$!
while kill -0 "$build_pid" 2>/dev/null; do
  sleep 5
  kill -0 "$build_pid" 2>/dev/null && emit 'milestone=next_build;state=running'
done
set +e
wait "$build_pid"
build_status=$?
set -e
build_pid=''
if (( build_status != 0 )); then
  emit "diagnostic_sha256=$(sha256sum "$build_result" | awk '{print $1}');diagnostic_bytes=$(stat -c '%s' "$build_result");raw_output_retained=false"
  block 'next_build_failed'
fi
emit 'milestone=next_build;state=pass'

emit "architecture=$architecture;image=$image;image_pulled=false;image_changed=false"
emit "native_tests=$EXPECTED_NATIVE_TESTS;failures=0;errors=0;javascript_tests=$EXPECTED_JAVASCRIPT_TESTS;next_build=pass"
emit 'citation_integrity=pass;generation_citations_displayable=true;display_expansion_additive=true'
emit 'header_dependency_status=false;left_session_overview=false;model_connections_content_free_label=false;right_rail_model_connections=true'
emit 'accepted_v1_2_changed=false;target_contact=false;database_contact=false;model_contact=false;credential_read=false;service_changed=false;package_changed=false'
emit "script_149_v1_3_correction=pass;next_gate=launch_corrected_local_v1_3_candidate;report=$report_path"
