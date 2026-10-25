#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the frozen Ishikawa v1.3 product-presentation, page-metadata, and
#   turn-scoped developer-diagnostics corrections before local preview.
#
# Mental model:
#   Bind the complete corrected source slice and frozen decisions; validate the
#   exact product.yaml schema and its restricted text renderer; prove the v4
#   chat and v2 document-view contracts; then rerun every native and browser
#   contract test plus one network-disabled production Next.js build.
#
# Inputs or prerequisites:
#   The local Ishikawa source, Ubuntu Python dependencies, and the existing
#   architecture-matched node-24-slim-nextjs-16-4-1 image. Ishikawa and every
#   prior preview must be stopped. Docker may require one attended sudo prompt.
#   No application credential is requested or read.
#
# Outputs or artifact lane:
#   One content-free report under
#   local/reports/ishikawa-v1.3-product-presentation-diagnostics. No service,
#   database, deployment package, accepted release, or remote host is changed.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/157_qualify_v1_3_product_presentation_and_diagnostics.sh --run

usage() {
  sed -n '3,29p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Run full local qualification and the production build.' \
    '  --validate-only Validate inputs and script structure only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly PYTHON_SOURCE_ROOT="$PYTHON_ROOT/ishikawa"
readonly WEB_ROOT="$PRODUCT_ROOT/application/web"
readonly CONFIG_TEMPLATE_ROOT="$PRODUCT_ROOT/config/templates"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly BASELINE="$PHASE_ROOT/docs/PHASE_28_RAG_METHOD_BASELINE.md"
readonly PRODUCT_GUIDE="$PRODUCT_ROOT/docs/PRODUCT_PRESENTATION_CONFIGURATION.md"
readonly TEST_RUNNER="$PRODUCT_ROOT/scripts/run-local-validation-tests.sh"
readonly RETRIEVAL_ENTRYPOINT="$PRODUCT_ROOT/scripts/ishikawa-retrieval-api"
readonly STACK_ENTRYPOINT="$PRODUCT_ROOT/scripts/ishikawa-stack"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.3-product-presentation-diagnostics"
readonly EXPECTED_NATIVE_TESTS=407
readonly EXPECTED_JAVASCRIPT_TESTS=17
readonly EXPECTED_CANDIDATE_FILES=96

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      printf 'script_157_v1_3_product_presentation_diagnostics=blocked;reason=argument_invalid\n' >&2
      usage >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_157_v1_3_product_presentation_diagnostics=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required_command in \
  awk bash chmod date dirname docker dpkg find grep id kill mapfile mkdir mktemp \
  python3 rm sed sha256sum sleep sort stat sudo tee; do
  if [[ "$validate_only" == true && "$required_command" =~ ^(docker|sudo)$ ]]; then
    continue
  fi
  command -v "$required_command" >/dev/null 2>&1 || {
    printf 'script_157_v1_3_product_presentation_diagnostics=blocked;reason=local_command_missing;command=%s\n' \
      "$required_command" >&2
    exit 2
  }
done

readonly -a REQUIRED_FILES=(
  "$DECISIONS"
  "$BASELINE"
  "$PRODUCT_GUIDE"
  "$TEST_RUNNER"
  "$RETRIEVAL_ENTRYPOINT"
  "$STACK_ENTRYPOINT"
  "$PYTHON_SOURCE_ROOT/api_contract.py"
  "$PYTHON_SOURCE_ROOT/document_view.py"
  "$PYTHON_SOURCE_ROOT/product.py"
  "$PYTHON_SOURCE_ROOT/retrieval_service.py"
  "$PRODUCT_ROOT/docs/API_CONTRACT.md"
  "$PRODUCT_ROOT/docs/CHAT_UI.md"
  "$PRODUCT_ROOT/tests/test_product.py"
  "$WEB_ROOT/components/chat-workspace.js"
  "$WEB_ROOT/components/presentation-markdown.js"
  "$WEB_ROOT/lib/chat-contract.mjs"
  "$WEB_ROOT/lib/runtime-config.mjs"
  "$WEB_ROOT/tests/chat-contract.test.mjs"
  "$WEB_ROOT/tests/presentation.test.mjs"
  "$WEB_ROOT/tests/runtime-config.test.mjs"
  "$WEB_ROOT/package.json"
  "$WEB_ROOT/next.config.mjs"
  "$CONFIG_TEMPLATE_ROOT/product.yaml"
)
for file in "${REQUIRED_FILES[@]}"; do
  [[ -f "$file" && ! -L "$file" && -r "$file" ]] || {
    printf 'script_157_v1_3_product_presentation_diagnostics=blocked;reason=required_input_unsafe\n' >&2
    exit 2
  }
done

for decision in \
  V13-12 V13-13 V13-14 V13-15 V13-16 V13-17 V13-18 V13-19 V13-20 V13-21; do
  grep -Eq "^\| \`$decision\` \|.*\| FROZEN \|$" "$DECISIONS" || {
    printf 'script_157_v1_3_product_presentation_diagnostics=blocked;reason=decision_list_incomplete\n' >&2
    exit 1
  }
done

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER" "$RETRIEVAL_ENTRYPOINT" "$STACK_ENTRYPOINT"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(path.read_text(encoding="utf-8"), str(path), "exec") for path in pathlib.Path(sys.argv[1]).glob("*.py")]' \
  "$PYTHON_SOURCE_ROOT"

product_ui_config_base64="$(
  PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B - \
    "$CONFIG_TEMPLATE_ROOT/product.yaml" <<'PY'
import sys
from pathlib import Path

from ishikawa.product import validate_product_profile
from ishikawa.yaml_loader import load_restricted_yaml

profile = validate_product_profile(
    load_restricted_yaml(Path(sys.argv[1]), label="product profile")
)
print(profile.browser_configuration_base64())
PY
)" || {
  printf 'script_157_v1_3_product_presentation_diagnostics=blocked;reason=product_profile_invalid\n' >&2
  exit 1
}
[[ "$product_ui_config_base64" =~ ^[A-Za-z0-9_-]+=*$ ]] || {
  printf 'script_157_v1_3_product_presentation_diagnostics=blocked;reason=product_payload_invalid\n' >&2
  exit 1
}

grep -Fq 'RESPONSE_SCHEMA = "ishikawa.chat-response.v4"' "$PYTHON_SOURCE_ROOT/api_contract.py"
grep -Fq 'RESPONSE_SCHEMA = "ishikawa.document-view-response.v2"' "$PYTHON_SOURCE_ROOT/document_view.py"
grep -Fq 'class ApiDiagnostics:' "$PYTHON_SOURCE_ROOT/api_contract.py"
grep -Fq 'page_count' "$PYTHON_SOURCE_ROOT/document_view.py"
grep -Fq 'ISHIKAWA_PRODUCT_UI_CONFIG_BASE64' "$STACK_ENTRYPOINT"
grep -Fq 'except ProductProfileError as error:' "$STACK_ENTRYPOINT"
grep -Fq 'productConfiguration.emptyChat.blocks' "$WEB_ROOT/components/chat-workspace.js"
grep -Fq 'productConfiguration.quickQuestions' "$WEB_ROOT/components/chat-workspace.js"
grep -Fq 'productConfiguration.footerNotice' "$WEB_ROOT/components/chat-workspace.js"
grep -Fq 'Searching documents…' "$WEB_ROOT/components/chat-workspace.js"
grep -Fq 'Measured after the first answer' "$WEB_ROOT/components/chat-workspace.js"
grep -Fq 'Tag: {source.document_key}' "$WEB_ROOT/components/chat-workspace.js"
grep -Fq 'Developer diagnostics' "$WEB_ROOT/components/chat-workspace.js"
grep -Fq 'dangerouslySetInnerHTML' "$WEB_ROOT/components/presentation-markdown.js" && {
  printf 'script_157_v1_3_product_presentation_diagnostics=blocked;reason=raw_html_renderer_present\n' >&2
  exit 1
}
for removed_text in \
  'YOUR APPROVED KNOWLEDGE' \
  'Grounded answer' \
  'Retrieving grounded evidence' \
  'Measured after the first grounded answer'; do
  if grep -Fq "$removed_text" "$WEB_ROOT/components/chat-workspace.js"; then
    printf 'script_157_v1_3_product_presentation_diagnostics=blocked;reason=removed_presentation_text_present\n' >&2
    exit 1
  fi
done
for documented in \
  'schema_version' 'display_name' 'tagline' 'quick_questions' 'footer_notice' \
  'empty_chat.blocks' '`heading` or `body`' '`sans`, `serif`, or `mono`' \
  '`small`, `medium`, `large`, or `display`' '**bold text**' '_italic text_' '<br>' \
  'Invalid examples'; do
  grep -Fq "$documented" "$PRODUCT_GUIDE" || {
    printf 'script_157_v1_3_product_presentation_diagnostics=blocked;reason=product_guide_incomplete\n' >&2
    exit 1
  }
done

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
      "$RETRIEVAL_ENTRYPOINT" \
      "$STACK_ENTRYPOINT" \
      "$PRODUCT_ROOT/README.md" \
      "$PRODUCT_ROOT/docs/API_CONTRACT.md" \
      "$PRODUCT_ROOT/docs/CHAT_UI.md" \
      "$PRODUCT_ROOT/docs/CONFIGURATION_CONTRACTS.md" \
      "$PRODUCT_GUIDE" \
      "$PRODUCT_ROOT/docs/RETRIEVAL_API_SERVICE.md" \
      "$BASELINE"
  } | LC_ALL=C sort
)
(( ${#candidate_files[@]} == EXPECTED_CANDIDATE_FILES )) || {
  printf 'script_157_v1_3_product_presentation_diagnostics=blocked;reason=candidate_file_count_mismatch;observed=%s;expected=%s\n' \
    "${#candidate_files[@]}" "$EXPECTED_CANDIDATE_FILES" >&2
  exit 1
}
for file in "${candidate_files[@]}"; do
  [[ -f "$file" && ! -L "$file" && -r "$file" ]] || {
    printf 'script_157_v1_3_product_presentation_diagnostics=blocked;reason=candidate_file_unsafe\n' >&2
    exit 1
  }
done
candidate_manifest_sha256="$({
  for file in "${candidate_files[@]}"; do
    relative_path="${file#"$REPO_ROOT/"}"
    printf '%s  %s\n' "$(sha256sum "$file" | awk '{print $1}')" "$relative_path"
  done
} | sha256sum | awk '{print $1}')"
decision_sha256="$(sha256sum "$DECISIONS" | awk '{print $1}')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_v1_3_product_presentation_diagnostics' \
    "script_sha256=$script_sha256;decision_sha256=$decision_sha256" \
    "candidate_manifest_sha256=$candidate_manifest_sha256;candidate_files=$EXPECTED_CANDIDATE_FILES" \
    'product_profile=pass;product_guide=pass;api_schema=pass;document_schema=pass' \
    'native_tests=not_run;javascript_tests=not_run;next_build=not_run;prior_preview_state=not_checked' \
    'target_contact=false;database_contact=false;model_contact=false;credential_read=false;service_changed=false;package_changed=false;image_pulled=false' \
    'script_157_v1_3_product_presentation_diagnostics=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT"
probe="$(mktemp "$REPORT_ROOT/.write-probe.XXXXXX")"
rm -f -- "$probe"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/v1_3_product_presentation_diagnostics_${timestamp}_XXXXXX.txt")"
chmod 0600 "$report_path" 2>/dev/null || true

emit() {
  printf '%s\n' "$1" | tee -a "$report_path"
}

block() {
  local reason="$1"
  local code="${2:-1}"
  emit "script_157_v1_3_product_presentation_diagnostics=blocked;reason=$reason;report=$report_path"
  exit "$code"
}

emit 'purpose=qualify_v1_3_product_presentation_diagnostics'
emit "report_path=$report_path"
emit "started_utc=$timestamp;script_sha256=$script_sha256;decision_sha256=$decision_sha256"
emit "candidate_manifest_sha256=$candidate_manifest_sha256;candidate_files=$EXPECTED_CANDIDATE_FILES"
emit 'authorized_actions=inspect_prior_preview_final_state_run_local_native_tests_run_local_containerized_javascript_tests_run_local_containerized_next_build_write_content_free_local_report'
emit 'non_actions=no_remote_contact_no_database_contact_no_model_contact_no_credential_read_no_service_start_or_change_no_package_change_no_image_pull_no_accepted_release_change_no_original_pdf_access'

docker_command=(docker)
if ! docker info >/dev/null 2>&1; then
  emit 'milestone=container_access;state=awaiting_attended_sudo'
  sudo -v || block sudo_authentication_failed 2
  docker_command=(sudo docker)
  "${docker_command[@]}" info >/dev/null 2>&1 || block docker_access_failed 2
fi

architecture="$(dpkg --print-architecture)"
case "$architecture" in
  arm64|amd64) ;;
  *) block host_architecture_unsupported 2 ;;
esac
image="node-24-slim-nextjs-16-4-1:$architecture"
"${docker_command[@]}" image inspect "$image" >/dev/null 2>&1 || block required_local_image_missing 2
[[ "$("${docker_command[@]}" image inspect "$image" --format '{{.Architecture}}')" == "$architecture" ]] || \
  block image_architecture_mismatch 2

port_is_free() {
  PYTHONDONTWRITEBYTECODE=1 python3 -B - "$1" <<'PY'
import socket
import sys

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe_socket:
    probe_socket.bind(("127.0.0.1", int(sys.argv[1])))
PY
}

for preview_container in \
  ishikawa-v1-3-product-preview \
  ishikawa-v1-3-corrected-preview \
  ishikawa-v1-3-qualified-preview \
  ishikawa-v1-3-sql-corrected-preview; do
  [[ -z "$("${docker_command[@]}" container ls --all --quiet --filter "name=^/${preview_container}$")" ]] \
    || block prior_preview_container_present
done
port_is_free 3000 >/dev/null 2>&1 || block prior_preview_web_listener_present
port_is_free 1384 >/dev/null 2>&1 || block prior_preview_retrieval_listener_present
emit 'milestone=prior_preview_state;state=pass;containers=absent;ports=free'

umask 077
work_root="$(mktemp -d /tmp/ishikawa-script-157.XXXXXX)"
build_pid=''
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$build_pid" =~ ^[0-9]+$ ]] && kill -0 "$build_pid" 2>/dev/null; then
    kill -TERM "$build_pid" 2>/dev/null || true
    wait "$build_pid" 2>/dev/null || true
  fi
  [[ "$work_root" == /tmp/ishikawa-script-157.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

emit 'milestone=native_tests;state=start'
native_result="$work_root/native-tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$native_result" 2>&1 || {
  emit "diagnostic_sha256=$(sha256sum "$native_result" | awk '{print $1}');diagnostic_bytes=$(stat -c '%s' "$native_result");raw_output_retained=false"
  block native_test_regression
}
grep -Fq "Ran $EXPECTED_NATIVE_TESTS tests" "$native_result" || block native_test_count_mismatch
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$native_result" || block native_test_marker_absent
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
    block javascript_tests_failed
  }
for expected in \
  "# tests $EXPECTED_JAVASCRIPT_TESTS" \
  "# pass $EXPECTED_JAVASCRIPT_TESTS" \
  '# fail 0'; do
  grep -Eq "^[[:space:]]*$expected[[:space:]]*$" "$javascript_result" \
    || block javascript_test_count_mismatch
done
emit "milestone=javascript_tests;state=pass;tests=$EXPECTED_JAVASCRIPT_TESTS"

emit 'milestone=next_build;state=start'
build_result="$work_root/next-build.txt"
"${docker_command[@]}" run --rm --network none \
  -e ISHIKAWA_PRODUCT_DISPLAY_NAME=Ishikawa \
  -e "ISHIKAWA_PRODUCT_UI_CONFIG_BASE64=$product_ui_config_base64" \
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
build_status="$?"
set -e
build_pid=''
if (( build_status != 0 )); then
  emit "diagnostic_sha256=$(sha256sum "$build_result" | awk '{print $1}');diagnostic_bytes=$(stat -c '%s' "$build_result");raw_output_retained=false"
  block next_build_failed
fi
emit 'milestone=next_build;state=pass'

emit "architecture=$architecture;image=$image;image_pulled=false;image_changed=false"
emit "native_tests=$EXPECTED_NATIVE_TESTS;failures=0;errors=0;javascript_tests=$EXPECTED_JAVASCRIPT_TESTS;next_build=pass"
emit 'product_presentation=pass;exact_schema=true;restricted_markdown=true;guide_complete=true;empty_stage_duplicates_removed=true'
emit 'operator_wording=pass;page_counts=true;tag_prefix=true;grounded_operator_text_removed=true'
emit 'developer_diagnostics=pass;turn_scoped=true;content_free=true;retrieval_telemetry_preserved_on_generation_failure=true'
emit 'api_contracts=pass;chat_response=v4;document_view_response=v2'
emit 'target_contact=false;database_contact=false;model_contact=false;credential_read=false;service_changed=false;package_changed=false;accepted_release_changed=false'
emit "script_157_v1_3_product_presentation_diagnostics=pass;next_gate=launch_product_configured_local_v1_3_preview;report=$report_path"
