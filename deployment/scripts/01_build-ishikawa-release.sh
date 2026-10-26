#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Purpose:
#   Build, qualify, and atomically publish the corpus-agnostic Ishikawa v1.3
#   application release.
#
# Mental model:
#   Validate frozen inputs, run native and browser tests, build twice, require
#   byte-identical archives, prove a fresh installation, and publish only the
#   verified archive to the stable current handoff.
#
# Inputs or prerequisites:
#   Frozen v1.3 source, local test/build dependencies, Docker, and attended sudo
#   only when the local container test path requires it.
#
# Outputs or artifact lane:
#   local/artifacts/ishikawa-v1.3-current and a detailed ignored local report.
#
# Usage:
#   bash ./deployment/scripts/01_build-ishikawa-release.sh --run

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
readonly product_root="$repo_root/Ishikawa"
readonly python_root="$product_root/application/python/ishikawa"
readonly web_root="$product_root/application/web"
readonly config_root="$product_root/config/templates"
readonly packaging_root="$product_root/packaging"
readonly test_runner="$product_root/scripts/run-local-validation-tests.sh"
readonly source_manifest="$repo_root/docs/releases/ISHIKAWA_V1_3_SOURCE_SHA256SUMS"
readonly release_readme="$repo_root/deployment/assets/README-v1.3.md"
readonly release_verifier="$repo_root/deployment/assets/verify-ishikawa-release"
readonly decision_record="$repo_root/docs/decisions/ISHIKAWA_RELEASE_DECISIONS.md"
readonly freeze_record="$repo_root/docs/releases/ISHIKAWA_V1_3_RELEASE_FREEZE.md"
readonly report_root="$repo_root/local/reports/ishikawa-release-build"
readonly artifact_root="$repo_root/local/artifacts"
readonly application_current="$artifact_root/ishikawa-v1.3-current"
readonly bundle_name='ishikawa-v1.3'
readonly expected_native_tests=486
readonly expected_javascript_tests=17
readonly frontier_artifact_sha256='1ccb7d59ed67073213051d28cd6142ab445b616e34a6ef7eecb22b174b52d972'
readonly frontier_report_sha256='1e7a4a4d93d9e7ceebc5e447dd86c12a436389f8a791e3895c93f90fbfbfbfe4'

mode="${1:-}"
report_path=''
work_root=''
current_stage='initialization'
build_pid=''
application_stage=''

result() {
  printf '\nSCRIPT RESULT\nscript_01_build_ishikawa_release=%s\n' "$1"
}

block() {
  local reason="$1" detail="$2" action="$3" payload
  payload="$(printf '%s\n' \
    'FAILURE DETAIL' \
    "stage=$current_stage" \
    "reason=$reason" \
    "detail=$detail" \
    "operator_action=$action")"
  printf '%s\n' "$payload" >&2
  if [[ -n "$report_path" && -f "$report_path" && ! -L "$report_path" ]]; then
    printf '%s\n' "$payload" >>"$report_path"
    result blocked >>"$report_path"
  fi
  result blocked >&2
  exit 1
}

cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ -n "$build_pid" ]] && kill -0 "$build_pid" 2>/dev/null; then
    kill -TERM "$build_pid" 2>/dev/null || true
    wait "$build_pid" 2>/dev/null || true
  fi
  if [[ -n "$work_root" && "$work_root" == /tmp/ishikawa-release-build.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  if [[ -n "$application_stage" && "$application_stage" == "$artifact_root"/.ishikawa-v1.3-current.* \
      && -d "$application_stage" && ! -L "$application_stage" ]]; then
    rm -rf -- "$application_stage"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'current_stage=interrupted; block signal_interrupt "The operator interrupted release assembly." "Review the retained report and rerun the same command."' INT
trap 'current_stage=interrupted; block signal_termination "Release assembly received SIGTERM." "Review the retained report and rerun the same command."' TERM

if [[ "$#" -ne 1 || ( "$mode" != '--validate-only' && "$mode" != '--run' ) ]]; then
  current_stage='argument_validation'
  block exactly_one_supported_mode_required \
    'Use exactly one mode: --validate-only or --run.' \
    'Rerun this command with one supported mode.'
fi

for command_name in awk bash cmp cp date diff docker dpkg find grep gzip install \
  kill mkdir mktemp mv python3 rm sed sha256sum sort stat sudo tar tee; do
  command -v "$command_name" >/dev/null 2>&1 \
    || { current_stage='preflight'; block "command_missing_${command_name}" \
      "A required local command is unavailable: ${command_name}." \
      'Restore the named command and rerun this script.'; }
done

for file in "$test_runner" "$source_manifest" "$release_readme" \
  "$release_verifier" "$decision_record" "$freeze_record" \
  "$packaging_root/install-ishikawa" "$packaging_root/database/install-schema" \
  "$packaging_root/database/schema.sql"; do
  [[ -f "$file" && ! -L "$file" && -r "$file" ]] \
    || { current_stage='preflight'; block required_file_unsafe \
      "A required release input is missing, unreadable, or a symbolic link: ${file}." \
      'Restore the frozen repository input and rerun this script.'; }
done
for directory in "$product_root" "$python_root" "$web_root"; do
  [[ -d "$directory" && ! -L "$directory" ]] \
    || { current_stage='preflight'; block required_directory_unsafe \
      "A required release directory is missing or unsafe: ${directory}." \
      'Restore the frozen repository directory and rerun this script.'; }
done

find "$product_root" -type l -print -quit | grep -q . \
  && { current_stage='preflight'; block source_symlink_found \
    'The frozen product contains a symbolic link.' \
    'Replace the link with an explicitly reviewed regular file.'; }
[[ "$(find "$python_root" -maxdepth 1 -type f -name '*.py' | awk 'END {print NR+0}')" == 52 ]] \
  || { current_stage='preflight'; block python_inventory_mismatch \
    'The canonical Python module inventory is not 52 files.' \
    'Review source drift before rebuilding the release.'; }
for decision in V13-60 V13-61 V13-62 V13-63 V13-64 V13-65 V13-66 V13-67 \
  V13-68 V13-69 V13-70 V13-71 V13-72 V13-73 V13-74 V13-75 V13-76; do
  decision_block="$(awk -v header="### ${decision} " '
    index($0, header) == 1 {capture=1}
    capture && /^### / && index($0, header) != 1 {exit}
    capture {print}
  ' "$decision_record")"
  [[ -n "$decision_block" ]] \
    || { current_stage='preflight'; block "${decision,,}_missing" \
      "The frozen release decision ${decision} is absent." \
      'Restore the frozen decision record and rerun this script.'; }
  for field in Decision Recommendation Reason/Evidence; do
    [[ "$(grep -c "^${field}:" <<<"$decision_block")" == 1 ]] \
      || { current_stage='preflight'; block "${decision,,}_format_invalid" \
        "The release decision ${decision} does not contain exactly one ${field} field." \
        'Reconcile the decision with the repository control-surface format and rerun this script.'; }
  done
  [[ "$(grep -Ec '^Status: Frozen([. ]|$)' <<<"$decision_block")" == 1 ]] \
    || { current_stage='preflight'; block "${decision,,}_not_frozen" \
      "The release decision ${decision} is not recorded with the canonical Frozen status." \
      'Restore the frozen decision status and rerun this script.'; }
done

actual_manifest="$(mktemp /tmp/ishikawa-source-manifest.XXXXXX)"
(
  cd -- "$repo_root"
  while IFS= read -r name; do sha256sum -- "$name"; done < <(
    find Ishikawa -type f ! -path '*/__pycache__/*' ! -name '*.pyc' ! -name '*.pyo' -printf '%p\n' | sort
  )
) >"$actual_manifest"
cmp -s "$source_manifest" "$actual_manifest" \
  || { rm -f -- "$actual_manifest"; current_stage='preflight'; block source_manifest_mismatch \
    'Canonical Ishikawa source differs from the frozen v1.3 manifest.' \
    'Review the complete source diff and deliberately re-freeze before packaging.'; }
rm -f -- "$actual_manifest"

bash -n "${BASH_SOURCE[0]}" "$test_runner" "$release_verifier" \
  "$packaging_root/install-ishikawa" "$packaging_root/database/install-schema" \
  || { current_stage='preflight'; block shell_syntax_invalid \
    'One or more active release scripts failed shell parsing.' \
    'Correct every reported parse error before packaging.'; }
PYTHONDONTWRITEBYTECODE=1 python3 -B - "$python_root" <<'PY' \
  || { current_stage='preflight'; block python_source_invalid \
    'One or more canonical Python modules failed compilation.' \
    'Correct every reported Python error before packaging.'; }
import pathlib
import sys
for path in pathlib.Path(sys.argv[1]).glob("*.py"):
    compile(path.read_text(encoding="utf-8"), str(path), "exec")
PY

if [[ "$mode" == '--validate-only' ]]; then
  printf '%s\n' \
    'purpose=validate_frozen_ishikawa_v1_3_release_build' \
    'source_manifest=pass;python_modules=52;source_documents=0;corpus_dependency=false;remote_contact=false;model_contact=false;database_contact=false' \
    'expected_prompts=at_most_one_attended_sudo_prompt_for_docker_during_run' \
    'expected_duration=about_2_to_5_minutes'
  result ready
  exit 0
fi

mkdir -p -- "$report_root" "$artifact_root"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_root/build_ishikawa_release_${timestamp}_XXXXXX.txt")" \
  || { current_stage='report_setup'; block report_creation_failed \
    'The content-free release report could not be created.' \
    'Correct local report permissions and rerun this script.'; }
work_root="$(mktemp -d /tmp/ishikawa-release-build.XXXXXX)" \
  || { current_stage='workspace_setup'; block workspace_creation_failed \
    'The private temporary build workspace could not be created.' \
    'Correct /tmp availability and rerun this script.'; }

emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=build_and_publish_frozen_ishikawa_v1_3_release'
emit "report_path=$report_path"
emit 'authorized_actions=run_local_tests_use_existing_local_container_image_assemble_verify_and_publish_local_application_release'
emit 'non_actions=no_remote_contact_no_model_contact_no_database_contact_no_credential_read_no_service_start_no_image_pull_no_black_corpus_access_no_boot_autostart_change'

current_stage='container_access'
docker_command=(docker)
if ! docker info >/dev/null 2>&1; then
  emit 'milestone=container_access;state=awaiting_attended_sudo'
  sudo -v || block sudo_authentication_failed \
    'Attended sudo authentication for local Docker failed.' \
    'Authenticate locally and rerun the same command.'
  docker_command=(sudo docker)
  "${docker_command[@]}" info >/dev/null 2>&1 \
    || block docker_access_failed \
      'Docker remained unavailable after attended sudo.' \
      'Restore local Docker access and rerun the same command.'
fi
architecture="$(dpkg --print-architecture)"
case "$architecture" in arm64|amd64) ;; *) block unsupported_architecture \
  "Unsupported host architecture: ${architecture}." \
  'Use an accepted arm64 or amd64 release-build host.' ;; esac
image="node-24-slim-nextjs-16-4-1:${architecture}"
"${docker_command[@]}" image inspect "$image" >/dev/null 2>&1 \
  || block required_local_image_missing \
    "The accepted local web image is missing: ${image}." \
    'Restore the checksum-accepted image locally; this script will not pull it.'
[[ "$("${docker_command[@]}" image inspect "$image" --format '{{.Architecture}}')" == "$architecture" ]] \
  || block image_architecture_mismatch \
    'The accepted web image architecture does not match the build host.' \
    'Restore the correct architecture-tagged image.'
emit "milestone=container_access;state=pass;architecture=$architecture;image=$image"

current_stage='native_tests'
emit 'milestone=native_tests;state=start'
native_result="$work_root/native-tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$test_runner" >"$native_result" 2>&1 \
  || { tail -n 120 "$native_result" | tee -a "$report_path"; block native_tests_failed \
    'The complete canonical native test suite failed.' \
    'Correct every test failure before rebuilding.'; }
grep -Fq "Ran $expected_native_tests tests" "$native_result" \
  || block native_test_count_mismatch \
    'The native suite passed with an unexpected test inventory.' \
    'Review missing or added tests before rebuilding.'
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$native_result" \
  || block native_pass_marker_missing \
    'The native suite omitted its exact pass marker.' \
    'Treat the run as unqualified and inspect the retained report.'
emit "milestone=native_tests;state=pass;tests=$expected_native_tests"

declare -a web_mounts=(
  --mount "type=bind,src=$web_root/app,dst=/opt/nextjs/app,readonly"
  --mount "type=bind,src=$web_root/components,dst=/opt/nextjs/components,readonly"
  --mount "type=bind,src=$web_root/lib,dst=/opt/nextjs/lib,readonly"
  --mount "type=bind,src=$web_root/public,dst=/opt/nextjs/public,readonly"
  --mount "type=bind,src=$web_root/tests,dst=/opt/nextjs/tests,readonly"
  --mount "type=bind,src=$web_root/package.json,dst=/opt/nextjs/package.json,readonly"
  --mount "type=bind,src=$web_root/next.config.mjs,dst=/opt/nextjs/next.config.mjs,readonly"
)

current_stage='javascript_tests'
emit 'milestone=javascript_tests;state=start'
javascript_result="$work_root/javascript-tests.txt"
"${docker_command[@]}" run --rm --network none "${web_mounts[@]}" \
  "$image" node --test --test-reporter=tap \
  tests/chat-contract.test.mjs tests/presentation.test.mjs tests/runtime-config.test.mjs \
  >"$javascript_result" 2>&1 \
  || { tail -n 120 "$javascript_result" | tee -a "$report_path"; block javascript_tests_failed \
    'The complete browser contract suite failed in the accepted image.' \
    'Correct every JavaScript failure before rebuilding.'; }
for expected in "# tests $expected_javascript_tests" "# pass $expected_javascript_tests" '# fail 0'; do
  grep -Eq "^[[:space:]]*${expected}[[:space:]]*$" "$javascript_result" \
    || block javascript_test_count_mismatch \
      'The JavaScript suite passed with an unexpected test inventory.' \
      'Review missing or added browser tests before rebuilding.'
done
emit "milestone=javascript_tests;state=pass;tests=$expected_javascript_tests"

product_ui_config_base64="$(
  PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$product_root/application/python" python3 -B - \
    "$config_root/product.yaml" <<'PY'
import sys
from pathlib import Path
from ishikawa.product import validate_product_profile
from ishikawa.yaml_loader import load_restricted_yaml
profile = validate_product_profile(load_restricted_yaml(Path(sys.argv[1]), label="product profile"))
print(profile.browser_configuration_base64())
PY
)" || block product_profile_invalid \
  'The frozen product presentation profile is invalid.' \
  'Correct the profile and its tests before rebuilding.'

current_stage='next_build'
emit 'milestone=next_build;state=start'
build_result="$work_root/next-build.txt"
"${docker_command[@]}" run --rm --network none \
  -e ISHIKAWA_PRODUCT_DISPLAY_NAME=Ishikawa \
  -e "ISHIKAWA_PRODUCT_UI_CONFIG_BASE64=$product_ui_config_base64" \
  -e ISHIKAWA_RETRIEVAL_BASE_URL=http://127.0.0.1:1384 \
  "${web_mounts[@]}" "$image" npm run build >"$build_result" 2>&1 &
build_pid="$!"
elapsed=0
while kill -0 "$build_pid" 2>/dev/null; do
  sleep 5
  elapsed=$((elapsed + 5))
  kill -0 "$build_pid" 2>/dev/null && emit "milestone=next_build;state=running;elapsed_seconds=$elapsed"
done
set +e
wait "$build_pid"
build_status="$?"
set -e
build_pid=''
if (( build_status != 0 )); then
  tail -n 120 "$build_result" | tee -a "$report_path"
  block next_build_failed \
    'The accepted containerized Next.js production build failed.' \
    'Correct every build error before rebuilding the release.'
fi
emit 'milestone=next_build;state=pass'

declare -a runtime_configs=(
  api_profile.yaml deployment.yaml document_classes.yaml ingestion_dependencies.yaml
  injection_profile.yaml logging_profile.yaml method_profile.yaml product.yaml
  query_resolution_profile.yaml reconstruction_profile.yaml relationship_types.yaml
  relevance_profile.yaml retrieval_service_profile.yaml runtime_dependencies.yaml
  scope_profile.yaml sufficiency_profile.yaml
)
declare -a web_files=(
  app/api/dependencies/route.js app/api/live/route.js app/api/ready/route.js
  app/api/v1/chat/route.js app/api/v1/document/route.js app/globals.css
  app/layout.js app/page.js components/chat-workspace.js
  components/presentation-markdown.js lib/chat-contract.mjs
  lib/runtime-config.mjs next.config.mjs package.json public/theme-init.js
)
declare -a product_docs=(
  APPLICATION_DEFINITION.md APPLICATION_DESIGN.md ARCHITECTURE.md CHAT_UI.md
  CHUNKING_INGESTION_RETRIEVAL.md COMMAND_SHEET.md
  INSTALLED_OPERATOR_INGESTION.md OPERATOR_GUIDE.md
  PRODUCT_PRESENTATION_CONFIGURATION.md SERVICE_OPERATIONS.md STACK_CONTROL.md
)
declare -a product_commands=(
  ishikawa-ingest ishikawa-log-control ishikawa-observability-retention
  ishikawa-produce-artifacts ishikawa-retrieval-api ishikawa-stack
  capture-pdf-extraction-observations.py normalize-pdf-extraction.py
  create-structural-chunk-candidates.py embed_document_candidates_via_endpoint.py
)

write_manifest() {
  local root="$1"
  (
    cd -- "$root"
    while IFS= read -r name; do sha256sum -- "$name"; done < <(
      find . -type f ! -path './SHA256SUMS' -printf '%P\n' | sort
    ) >SHA256SUMS
  )
}

assemble_application() {
  local destination="$1" source name destination_name
  install -d -m 0755 -- \
    "$destination/payload/application/python/ishikawa" \
    "$destination/payload/application/web/app/api/dependencies" \
    "$destination/payload/application/web/app/api/live" \
    "$destination/payload/application/web/app/api/ready" \
    "$destination/payload/application/web/app/api/v1/chat" \
    "$destination/payload/application/web/app/api/v1/document" \
    "$destination/payload/application/web/components" \
    "$destination/payload/application/web/lib" \
    "$destination/payload/application/web/public" \
    "$destination/payload/config/examples" "$destination/payload/docs" \
    "$destination/payload/scripts" "$destination/payload/systemd"
  install -m 0644 -- "$packaging_root/README.md" "$destination/README.md"
  install -m 0755 -- "$packaging_root/install-ishikawa" "$destination/install-ishikawa"
  while IFS= read -r source; do
    install -m 0644 -- "$source" "$destination/payload/application/python/ishikawa/$(basename -- "$source")"
  done < <(find "$python_root" -maxdepth 1 -type f -name '*.py' | sort)
  for name in "${web_files[@]}"; do
    install -m 0644 -- "$web_root/$name" "$destination/payload/application/web/$name"
  done
  for name in "${product_commands[@]}"; do
    install -m 0755 -- "$product_root/scripts/$name" "$destination/payload/scripts/$name"
  done
  for name in "${runtime_configs[@]}"; do
    install -m 0644 -- "$config_root/$name" "$destination/payload/config/$name"
  done
  install -m 0644 -- "$packaging_root/document_catalog.yaml" "$destination/payload/config/document_catalog.yaml"
  install -m 0644 -- "$packaging_root/ingestion_manifest.example.yaml" "$destination/payload/config/examples/ingestion_manifest.yaml"
  install -m 0644 -- "$config_root/document_catalog.yaml" "$destination/payload/config/examples/document_catalog.yaml"
  for name in "${product_docs[@]}"; do
    destination_name="$name"
    [[ "$name" != INSTALLED_OPERATOR_INGESTION.md ]] || destination_name=OPERATOR_INGESTION.md
    install -m 0644 -- "$product_root/docs/$name" "$destination/payload/docs/$destination_name"
  done
  for source in "$packaging_root"/systemd/*; do
    install -m 0644 -- "$source" "$destination/payload/systemd/$(basename -- "$source")"
  done
  write_manifest "$destination"
}

assemble_database() {
  local destination="$1"
  install -d -m 0755 -- "$destination"
  install -m 0644 -- "$packaging_root/database/README.md" "$destination/README.md"
  install -m 0755 -- "$packaging_root/database/install-schema" "$destination/install-schema"
  install -m 0644 -- "$packaging_root/database/schema.sql" "$destination/schema.sql"
  write_manifest "$destination"
}

source_manifest_sha256="$(sha256sum -- "$source_manifest" | awk '{print $1}')"
assemble_bundle() {
  local destination="$1" bundle="$1/$bundle_name"
  install -d -m 0755 -- "$bundle/application" "$bundle/database"
  assemble_application "$bundle/application"
  assemble_database "$bundle/database"
  install -m 0644 -- "$release_readme" "$bundle/README.md"
  install -m 0755 -- "$release_verifier" "$bundle/verify-ishikawa-release"
  python3 -B - "$bundle/release.json" "$source_manifest_sha256" \
    "$frontier_artifact_sha256" "$frontier_report_sha256" <<'PY'
import json
import sys
from pathlib import Path
output, source_manifest, frontier_artifact, frontier_report = sys.argv[1:]
record = {
    "boot_autostart": False,
    "frontier_artifact_sha256": frontier_artifact,
    "frontier_case_count": 60,
    "frontier_report_sha256": frontier_report,
    "historical_mutation_files": 0,
    "javascript_test_count": 17,
    "native_test_count": 486,
    "release_name": "Ishikawa v1.3",
    "retrieval_mrr_at_20": 0.89545,
    "schema_version": 5,
    "source_document_count": 0,
    "source_manifest_sha256": source_manifest,
}
Path(output).write_text(json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
PY
  write_manifest "$bundle"
}

current_stage='deterministic_assembly'
emit 'milestone=deterministic_assembly;state=start;builds=2'
mkdir -p -- "$work_root/build-a" "$work_root/build-b" "$work_root/extracted"
assemble_bundle "$work_root/build-a"
assemble_bundle "$work_root/build-b"
for bundle in "$work_root/build-a/$bundle_name" "$work_root/build-b/$bundle_name"; do
  bash "$bundle/verify-ishikawa-release" >/dev/null \
    || block assembled_package_verification_failed \
      'An assembled package failed its own verifier.' \
      'Inspect the build inputs and verifier before publication.'
done
diff -qr "$work_root/build-a/$bundle_name" "$work_root/build-b/$bundle_name" >/dev/null \
  || block deterministic_directory_mismatch \
    'Two independent package assemblies produced different bytes.' \
    'Remove nondeterministic input before publication.'

archive_a="$work_root/$bundle_name-a.tar.gz"
archive_b="$work_root/$bundle_name-b.tar.gz"
for build in a b; do
  archive_variable="archive_${build}"
  archive_path="${!archive_variable}"
  tar --sort=name --format=posix --mtime='UTC 2026-10-24' --owner=0 --group=0 --numeric-owner \
    --pax-option=delete=atime,delete=ctime -C "$work_root/build-$build" -cf - "$bundle_name" \
    | gzip -n >"$archive_path"
done
cmp -s "$archive_a" "$archive_b" \
  || block deterministic_archive_mismatch \
    'Two independent deterministic archives produced different bytes.' \
    'Remove nondeterministic package metadata before publication.'
application_archive_sha256="$(sha256sum -- "$archive_a" | awk '{print $1}')"
tar -xzf "$archive_a" -C "$work_root/extracted"
bash "$work_root/extracted/$bundle_name/verify-ishikawa-release" >/dev/null \
  || block extracted_archive_verification_failed \
    'The extracted archive failed its bundled verifier.' \
    'Do not publish the archive; inspect the build report.'
emit "milestone=deterministic_assembly;state=pass;archive_sha256=$application_archive_sha256"

current_stage='fresh_install'
emit 'milestone=fresh_install;state=start'
fresh_install="$work_root/fresh-install/Ishikawa"
bash "$work_root/extracted/$bundle_name/application/install-ishikawa" --install-root "$fresh_install" \
  >"$work_root/fresh-install.txt" 2>&1 \
  || { tail -n 120 "$work_root/fresh-install.txt" | tee -a "$report_path"; block fresh_install_failed \
    'The extracted release could not install into a new directory.' \
    'Correct the installer or package inventory before publication.'; }
grep -Fq 'ishikawa_install=pass;' "$work_root/fresh-install.txt" \
  || block fresh_install_marker_missing \
    'The fresh installer omitted its exact pass marker.' \
    'Treat the package as unqualified and inspect the retained report.'
PYTHONDONTWRITEBYTECODE=1 "$fresh_install/scripts/ishikawa-retrieval-api" --check-config >/dev/null \
  || block installed_configuration_invalid \
    'The fresh installation failed its retrieval configuration check.' \
    'Correct the packaged configuration before publication.'
emit 'milestone=fresh_install;state=pass;service_started=false;database_changed=false'

current_stage='coding_standard'
emit 'milestone=coding_standard;state=start'
if tar -tzf "$archive_a" | grep -E '/(__pycache__|node_modules|\.next)/|\.(pyc|pyo)$' >/dev/null; then
  block generated_content_in_archive \
    'The application archive contains generated development state.' \
    'Correct the package inventory before publication.'
fi
if tar -tzf "$archive_a" | grep -Ei '(migration|mutation|patch|repair)' >/dev/null; then
  block historical_repair_in_archive \
    'The application archive contains a historical migration or repair path.' \
    'Fold final state into the canonical package instead.'
fi
emit 'milestone=coding_standard;state=pass;deterministic=true;fresh_install=true;historical_repairs=0;source_documents=0'

current_stage='publication'
emit 'milestone=publication;state=start'
application_stage="$artifact_root/.ishikawa-v1.3-current.${timestamp}.$$"
mkdir -p -- "$application_stage" "$artifact_root/superseded"
cp -- "$archive_a" "$application_stage/$bundle_name.tar.gz"
(
  cd -- "$application_stage"
  sha256sum "$bundle_name.tar.gz" >"$bundle_name.tar.gz.sha256"
)
cp -- "$source_manifest" "$application_stage/ISHIKAWA_V1_3_SOURCE_SHA256SUMS"
python3 -B - "$application_stage/release-receipt.json" "$application_archive_sha256" \
  "$source_manifest_sha256" "$frontier_artifact_sha256" "$frontier_report_sha256" <<'PY'
import json
import sys
from pathlib import Path
output, archive, source_manifest, frontier_artifact, frontier_report = sys.argv[1:]
record = {
    "archive_sha256": archive,
    "coding_standard": "pass",
    "deterministic_archive": True,
    "fresh_install": "pass",
    "frontier_artifact_sha256": frontier_artifact,
    "frontier_report_sha256": frontier_report,
    "human_ui_validation": "accepted",
    "release": "Ishikawa v1.3",
    "source_manifest_sha256": source_manifest,
}
Path(output).write_text(json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
PY
(cd -- "$application_stage" && sha256sum --check --strict "$bundle_name.tar.gz.sha256" >/dev/null) \
  || block application_publication_checksum_failed \
    'The staged application handoff failed its sidecar verification.' \
    'Do not publish the application handoff.'
application_backup=''
if [[ -e "$application_current" || -L "$application_current" ]]; then
  [[ -d "$application_current" && ! -L "$application_current" ]] \
    || block application_current_unsafe \
      'The stable application handoff exists but is not a regular directory.' \
      'Inspect the path before publication.'
  application_backup="$artifact_root/superseded/ishikawa-v1.3-current-$timestamp"
  [[ ! -e "$application_backup" && ! -L "$application_backup" ]] \
    || block application_backup_exists \
      'The selected superseded application path already exists.' \
      'Review the retained handoff directories before rebuilding.'
fi

[[ -z "$application_backup" ]] || mv -- "$application_current" "$application_backup"
if ! mv -- "$application_stage" "$application_current"; then
  [[ -z "$application_backup" ]] || mv -- "$application_backup" "$application_current"
  block application_publication_failed \
    'The staged application handoff could not be promoted.' \
    'Review local filesystem state and rerun; the prior current handoff was restored.'
fi
application_stage=''

(cd -- "$application_current" && sha256sum --check --strict "$bundle_name.tar.gz.sha256" >/dev/null) \
  || block published_application_checksum_failed \
    'The published application handoff failed independent verification.' \
    'Stop and inspect the stable handoff path.'
emit "milestone=publication;state=pass;application_current=$application_current"
emit "application_archive_sha256=$application_archive_sha256;source_documents=0;corpus_dependency=false"
emit 'target_contact=false;database_contact=false;model_contact=false;service_changed=false;boot_autostart_changed=false'
emit 'next_gate=operator_run_emceedanko_inventory_and_disposable_qualification'
result pass | tee -a "$report_path"
