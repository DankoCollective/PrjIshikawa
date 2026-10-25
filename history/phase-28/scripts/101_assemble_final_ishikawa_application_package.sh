#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Assemble and locally qualify the complete final-state Ishikawa application
#   package without contacting a target, database, container, or model.
#
# Mental model:
#   Bind the accepted stack-control proof, run the complete native test suite,
#   copy only final runtime files, enforce package and coding standards, prove
#   reproducibility, and exercise one fresh temporary installation.
#
# Inputs or prerequisites:
#   Accepted explicit-stack evidence, current Ishikawa sources, Python 3.12,
#   PyYAML, CODING_STANDARD.md, and standard GNU archive utilities.
#
# Outputs:
#   A deterministic final application archive, checksums, content-free
#   qualification evidence, and a coding-standard compliance receipt.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/101_assemble_final_ishikawa_application_package.sh --run

usage() {
  sed -n '3,21p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Assemble, validate, and retain the final package.' \
    '  --validate-only Run the same proof without retaining outputs.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_PACKAGE="$ISHIKAWA_ROOT/application/python/ishikawa"
readonly WEB_ROOT="$ISHIKAWA_ROOT/application/web"
readonly CONFIG_ROOT="$ISHIKAWA_ROOT/config/templates"
readonly PACKAGING_ROOT="$ISHIKAWA_ROOT/packaging"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly CODING_STANDARD="$REPO_ROOT/CODING_STANDARD.md"
readonly CODING_STANDARD_EVALUATOR="$SCRIPT_DIR/evaluate_consolidated_build_coding_standard.py"
readonly BUNDLE_NAME='ishikawa-application-package'
readonly ACCEPTED_REPORT="$REPO_ROOT/local/reports/ishikawa-explicit-stack-control/explicit_stack_control_20261021T020857Z_OmTn63.txt"
readonly ACCEPTED_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/explicit-stack-control/explicit_stack_control_qualification_20261021T020857Z.json"
readonly ACCEPTED_CHECKSUM="$ACCEPTED_ARTIFACT.sha256"
readonly ACCEPTED_REPORT_SHA256='c7863ab6b6917dc47eef943c093765bef8af23d82b6fb5247cb82d94678c9157'
readonly ACCEPTED_ARTIFACT_SHA256='a5ee8581a8ec7f3dab8ccdddf090295f2c9d835d1d0053467168b4854b9c5580'
readonly ACCEPTED_CHECKSUM_SHA256='4b782f0c9ea2ac7e75776ea8d01c629a7b2f7cec303d9cc3bf0adf0951e64e78'
readonly OUTPUT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/final-application-package"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-final-application-package"
readonly FORBIDDEN_PATTERN='phase[-_ ]*[0-9]|org[-_ ]*lab|danko|agentdanko|dankorepos|prj[0-9]|codex|opencode|local/artifacts|/mnt/|\.git/|repository|script[[:space:]_-]*[0-9]+'

readonly -a RUNTIME_CONFIGS=(
  api_profile.yaml
  deployment.yaml
  document_classes.yaml
  ingestion_dependencies.yaml
  injection_profile.yaml
  logging_profile.yaml
  method_profile.yaml
  product.yaml
  query_resolution_profile.yaml
  reconstruction_profile.yaml
  relationship_types.yaml
  relevance_profile.yaml
  retrieval_service_profile.yaml
  runtime_dependencies.yaml
  scope_profile.yaml
  sufficiency_profile.yaml
)
readonly -a PRODUCT_COMMANDS=(
  "$ISHIKAWA_ROOT/scripts/ishikawa-ingest"
  "$ISHIKAWA_ROOT/scripts/ishikawa-log-control"
  "$ISHIKAWA_ROOT/scripts/ishikawa-observability-retention"
  "$ISHIKAWA_ROOT/scripts/ishikawa-produce-artifacts"
  "$ISHIKAWA_ROOT/scripts/ishikawa-retrieval-api"
  "$ISHIKAWA_ROOT/scripts/ishikawa-stack"
)
readonly -a PIPELINE_COMMANDS=(
  "$SCRIPT_DIR/capture-pdf-extraction-observations.py"
  "$SCRIPT_DIR/normalize-pdf-extraction.py"
  "$SCRIPT_DIR/create-structural-chunk-candidates.py"
  "$SCRIPT_DIR/embed_document_candidates_via_endpoint.py"
)
readonly -a WEB_FILES=(
  app/api/live/route.js
  app/api/ready/route.js
  app/api/v1/chat/route.js
  app/globals.css
  app/layout.js
  app/page.js
  components/chat-workspace.js
  lib/chat-contract.mjs
  lib/runtime-config.mjs
  next.config.mjs
  package.json
)
readonly -a PRODUCT_DOCS=(
  "$ISHIKAWA_ROOT/docs/CHAT_UI.md"
  "$ISHIKAWA_ROOT/docs/INSTALLED_OPERATOR_INGESTION.md"
  "$ISHIKAWA_ROOT/docs/SERVICE_OPERATIONS.md"
  "$ISHIKAWA_ROOT/docs/STACK_CONTROL.md"
)
readonly -a SYSTEMD_UNITS=(
  "$PACKAGING_ROOT/systemd/ishikawa-observability-retention.service"
  "$PACKAGING_ROOT/systemd/ishikawa-observability-retention.timer"
  "$PACKAGING_ROOT/systemd/ishikawa-retrieval-api.service"
)

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_101_final_application_package=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_101_final_application_package=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in awk bash basename cmp cp date find grep gzip install mkdir mktemp mv python3 rm sed sha256sum sort stat tar tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_101_final_application_package=blocked;reason=local_command_missing\n' >&2
    exit 2
  }
done

mapfile -t python_sources < <(find "$PYTHON_PACKAGE" -maxdepth 1 -type f -name '*.py' -print | sort)
(( ${#python_sources[@]} >= 45 )) || {
  printf 'script_101_final_application_package=blocked;reason=python_source_inventory_incomplete\n' >&2
  exit 2
}

required_files=(
  "$TEST_RUNNER"
  "$CODING_STANDARD"
  "$CODING_STANDARD_EVALUATOR"
  "$PACKAGING_ROOT/README.md"
  "$PACKAGING_ROOT/install-ishikawa"
  "$PACKAGING_ROOT/document_catalog.yaml"
  "$PACKAGING_ROOT/ingestion_manifest.example.yaml"
  "$ACCEPTED_REPORT"
  "$ACCEPTED_ARTIFACT"
  "$ACCEPTED_CHECKSUM"
  "${python_sources[@]}"
  "${PRODUCT_COMMANDS[@]}"
  "${PIPELINE_COMMANDS[@]}"
  "${PRODUCT_DOCS[@]}"
  "${SYSTEMD_UNITS[@]}"
)
for name in "${RUNTIME_CONFIGS[@]}"; do required_files+=("$CONFIG_ROOT/$name"); done
for name in "${WEB_FILES[@]}"; do required_files+=("$WEB_ROOT/$name"); done
for source in "${required_files[@]}"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'script_101_final_application_package=blocked;reason=required_input_unsafe\n' >&2
    exit 2
  }
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_101_final_application_package=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}
check_sha256 "$ACCEPTED_REPORT" "$ACCEPTED_REPORT_SHA256" 'accepted_report'
check_sha256 "$ACCEPTED_ARTIFACT" "$ACCEPTED_ARTIFACT_SHA256" 'accepted_artifact'
check_sha256 "$ACCEPTED_CHECKSUM" "$ACCEPTED_CHECKSUM_SHA256" 'accepted_checksum'
(
  cd -- "$(dirname -- "$ACCEPTED_ARTIFACT")"
  sha256sum --check --strict "$(basename -- "$ACCEPTED_CHECKSUM")" >/dev/null
) || {
  printf 'script_101_final_application_package=blocked;reason=accepted_checksum_failed\n' >&2
  exit 2
}
for fact in \
  'explicit_stack_control_qualification=pass' \
  'local_tests=360;failures=0;errors=0' \
  'lifecycle=start-ready-status-stop-stopped;rollback=pass;missing_credential=blocked' \
  'credential_disclosure=false;target_contact=false;service_changed=false;database_changed=false;image_changed=false' \
  'script_100_explicit_stack_control=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_REPORT" || {
    printf 'script_101_final_application_package=blocked;reason=accepted_report_contract_failed\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER" "$PACKAGING_ROOT/install-ishikawa" "$ISHIKAWA_ROOT/scripts/ishikawa-stack"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$CODING_STANDARD_EVALUATOR" "${python_sources[@]}" "${PIPELINE_COMMANDS[@]}" \
  "${PRODUCT_COMMANDS[@]:0:5}"

work_root="$(mktemp -d /tmp/ishikawa-script-101.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-101.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/native-tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  printf 'script_101_final_application_package=blocked;reason=test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$test_result" | awk '{print $1}')" "$(stat -c '%s' "$test_result")" >&2
  exit 1
}
grep -Fq 'Ran 360 tests' "$test_result" || {
  printf 'script_101_final_application_package=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_101_final_application_package=blocked;reason=test_pass_marker_absent\n' >&2
  exit 1
}

assemble_bundle() {
  local destination="$1"
  local bundle="$destination/$BUNDLE_NAME"
  install -d -m 0755 -- \
    "$bundle/payload/application/python/ishikawa" \
    "$bundle/payload/application/web/app/api/live" \
    "$bundle/payload/application/web/app/api/ready" \
    "$bundle/payload/application/web/app/api/v1/chat" \
    "$bundle/payload/application/web/components" \
    "$bundle/payload/application/web/lib" \
    "$bundle/payload/config/examples" \
    "$bundle/payload/docs" \
    "$bundle/payload/scripts" \
    "$bundle/payload/systemd"
  install -m 0644 -- "$PACKAGING_ROOT/README.md" "$bundle/README.md"
  install -m 0755 -- "$PACKAGING_ROOT/install-ishikawa" "$bundle/install-ishikawa"

  local source name destination_name
  for source in "${python_sources[@]}"; do
    install -m 0644 -- "$source" "$bundle/payload/application/python/ishikawa/$(basename -- "$source")"
  done
  for name in "${WEB_FILES[@]}"; do
    install -m 0644 -- "$WEB_ROOT/$name" "$bundle/payload/application/web/$name"
  done
  for source in "${PRODUCT_COMMANDS[@]}" "${PIPELINE_COMMANDS[@]}"; do
    install -m 0755 -- "$source" "$bundle/payload/scripts/$(basename -- "$source")"
  done
  for name in "${RUNTIME_CONFIGS[@]}"; do
    install -m 0644 -- "$CONFIG_ROOT/$name" "$bundle/payload/config/$name"
  done
  install -m 0644 -- "$PACKAGING_ROOT/document_catalog.yaml" "$bundle/payload/config/document_catalog.yaml"
  install -m 0644 -- "$PACKAGING_ROOT/ingestion_manifest.example.yaml" "$bundle/payload/config/examples/ingestion_manifest.yaml"
  install -m 0644 -- "$CONFIG_ROOT/document_catalog.yaml" "$bundle/payload/config/examples/document_catalog.yaml"
  for source in "${PRODUCT_DOCS[@]}"; do
    destination_name="$(basename -- "$source")"
    [[ "$destination_name" != INSTALLED_OPERATOR_INGESTION.md ]] || destination_name='OPERATOR_INGESTION.md'
    install -m 0644 -- "$source" "$bundle/payload/docs/$destination_name"
  done
  for source in "${SYSTEMD_UNITS[@]}"; do
    install -m 0644 -- "$source" "$bundle/payload/systemd/$(basename -- "$source")"
  done
  (
    cd -- "$bundle"
    while IFS= read -r name; do sha256sum "$name"; done < <(
      find . -type f ! -name SHA256SUMS -printf '%P\n' | sort
    ) >SHA256SUMS
  )
}

mkdir -p -- "$work_root/build-a" "$work_root/build-b"
assemble_bundle "$work_root/build-a"
assemble_bundle "$work_root/build-b"

for bundle in "$work_root/build-a/$BUNDLE_NAME" "$work_root/build-b/$BUNDLE_NAME"; do
  (cd -- "$bundle" && sha256sum --check --strict SHA256SUMS >/dev/null) || {
    printf 'script_101_final_application_package=blocked;reason=internal_checksum_failure\n' >&2
    exit 1
  }
  if find "$bundle" -type l -print -quit | grep -q .; then
    printf 'script_101_final_application_package=blocked;reason=package_symlink_found\n' >&2
    exit 1
  fi
  if find "$bundle" -type f \( -name '*.pyc' -o -name '*.pyo' \) -print -quit | grep -q . \
    || find "$bundle" -type d -name __pycache__ -print -quit | grep -q .; then
    printf 'script_101_final_application_package=blocked;reason=generated_python_file_found\n' >&2
    exit 1
  fi
  if find "$bundle" -type f \( -iname '*migration*' -o -iname '*mutation*' -o -iname '*patch*' -o -iname '*repair*' \) -print -quit | grep -q .; then
    printf 'script_101_final_application_package=blocked;reason=historical_mutation_file_found\n' >&2
    exit 1
  fi
  if grep -ERiq -- "$FORBIDDEN_PATTERN" "$bundle"; then
    printf 'script_101_final_application_package=blocked;reason=development_jargon_found\n' >&2
    exit 1
  fi
  if grep -ERq -- 'BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY|Authorization:[[:space:]]*Bearer[[:space:]]+[^$]' "$bundle"; then
    printf 'script_101_final_application_package=blocked;reason=credential_material_found\n' >&2
    exit 1
  fi
done

coding_standard_result="$work_root/coding-standard.json"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$CODING_STANDARD_EVALUATOR" \
  --bundle-root "$work_root/build-a/$BUNDLE_NAME" \
  --standard "$CODING_STANDARD" \
  --output "$coding_standard_result" >/dev/null || {
  printf 'script_101_final_application_package=blocked;reason=coding_standard_noncompliance\n' >&2
  exit 1
}

if ! cmp -s \
  <(cd "$work_root/build-a/$BUNDLE_NAME" && find . -type f -printf '%P\n' | sort | while IFS= read -r name; do sha256sum "$name"; done) \
  <(cd "$work_root/build-b/$BUNDLE_NAME" && find . -type f -printf '%P\n' | sort | while IFS= read -r name; do sha256sum "$name"; done); then
  printf 'script_101_final_application_package=blocked;reason=bundle_not_reproducible\n' >&2
  exit 1
fi

temporary_archive="$work_root/$BUNDLE_NAME.tar.gz"
tar \
  --sort=name \
  --format=posix \
  --pax-option=delete=atime,delete=ctime \
  --mtime='UTC 1970-01-01' \
  --owner=0 \
  --group=0 \
  --numeric-owner \
  -C "$work_root/build-a" \
  -cf - \
  "$BUNDLE_NAME" | gzip -n >"$temporary_archive"

mkdir -p -- "$work_root/extracted"
tar -xzf "$temporary_archive" -C "$work_root/extracted"
readonly extracted_bundle="$work_root/extracted/$BUNDLE_NAME"
(cd -- "$extracted_bundle" && sha256sum --check --strict SHA256SUMS >/dev/null) || {
  printf 'script_101_final_application_package=blocked;reason=extracted_checksum_failure\n' >&2
  exit 1
}

install_root="$work_root/installed/Ishikawa"
bash "$extracted_bundle/install-ishikawa" --install-root "$install_root" >"$work_root/install.txt"
grep -Fq 'ishikawa_install=pass;' "$work_root/install.txt" || {
  printf 'script_101_final_application_package=blocked;reason=installer_pass_marker_absent\n' >&2
  exit 1
}
for command_name in ishikawa-ingest ishikawa-log-control ishikawa-observability-retention ishikawa-produce-artifacts ishikawa-retrieval-api ishikawa-stack; do
  [[ -x "$install_root/scripts/$command_name" ]] || {
    printf 'script_101_final_application_package=blocked;reason=installed_entrypoint_not_executable\n' >&2
    exit 1
  }
done

PYTHONDONTWRITEBYTECODE=1 "$install_root/scripts/ishikawa-retrieval-api" --check-config >/dev/null || {
  printf 'script_101_final_application_package=blocked;reason=installed_retrieval_config_invalid\n' >&2
  exit 1
}
PYTHONDONTWRITEBYTECODE=1 "$install_root/scripts/ishikawa-observability-retention" --check-config >/dev/null || {
  printf 'script_101_final_application_package=blocked;reason=installed_retention_config_invalid\n' >&2
  exit 1
}
"$install_root/scripts/ishikawa-stack" --help >/dev/null
"$install_root/scripts/ishikawa-ingest" --help >/dev/null

archive_sha256="$(sha256sum "$temporary_archive" | awk '{print $1}')"
archive_bytes="$(stat -c '%s' "$temporary_archive")"
bundle_file_count="$(find "$extracted_bundle" -type f | awk 'END {print NR}')"
python_file_count="$(find "$install_root/application/python/ishikawa" -maxdepth 1 -type f -name '*.py' | awk 'END {print NR}')"
web_file_count="$(find "$install_root/application/web" -type f | awk 'END {print NR}')"
command_file_count="$(find "$install_root/scripts" -maxdepth 1 -type f | awk 'END {print NR}')"
unit_file_count="$(find "$install_root/systemd" -maxdepth 1 -type f | awk 'END {print NR}')"
coding_standard_sha256="$(sha256sum "$CODING_STANDARD" | awk '{print $1}')"
coding_standard_result_sha256="$(sha256sum "$coding_standard_result" | awk '{print $1}')"
coding_standard_result_bytes="$(stat -c '%s' "$coding_standard_result")"

printf '{"archive_bytes":%s,"archive_sha256":"%s","bundle_file_count":%s,"coding_standard_compliant":true,"command_file_count":%s,"database_changed":false,"fresh_installation":true,"historical_mutation_files":0,"model_contact":false,"python_file_count":%s,"receipt_schema_version":1,"repository_references":false,"secret_material":false,"service_changed":false,"source_documents_included":false,"target_contact":false,"unit_file_count":%s,"web_file_count":%s}\n' \
  "$archive_bytes" "$archive_sha256" "$bundle_file_count" "$command_file_count" \
  "$python_file_count" "$unit_file_count" "$web_file_count" >"$work_root/qualification.json"
qualification_sha256="$(sha256sum "$work_root/qualification.json" | awk '{print $1}')"
qualification_bytes="$(stat -c '%s' "$work_root/qualification.json")"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_final_ishikawa_application_package' \
    "archive_sha256=$archive_sha256;archive_bytes=$archive_bytes;bundle_file_count=$bundle_file_count" \
    "python_file_count=$python_file_count;web_file_count=$web_file_count;command_file_count=$command_file_count;unit_file_count=$unit_file_count" \
    "coding_standard_sha256=$coding_standard_sha256;coding_standard_result_sha256=$coding_standard_result_sha256;coding_standard_result_bytes=$coding_standard_result_bytes" \
    'native_tests=360;failures=0;errors=0' \
    'internal_checksums=pass;deterministic_archive=true;fresh_installation=pass' \
    'historical_mutation_files=0;repository_references=false;secret_material=false;source_documents_included=false' \
    'target_contact=false;database_changed=false;service_changed=false;model_contact=false' \
    'script_101_final_application_package_source=pass'
  exit 0
fi

mkdir -p -- "$OUTPUT_ROOT" "$REPORT_ROOT"
archive_name="$BUNDLE_NAME-${archive_sha256:0:16}.tar.gz"
archive_path="$OUTPUT_ROOT/$archive_name"
archive_checksum="$archive_path.sha256"
qualification_path="$OUTPUT_ROOT/final_application_package_qualification_${archive_sha256:0:16}.json"
qualification_checksum="$qualification_path.sha256"
coding_standard_path="$OUTPUT_ROOT/final_application_coding_standard_${archive_sha256:0:16}.json"
coding_standard_checksum="$coding_standard_path.sha256"

retain_exact() {
  local source="$1" destination="$2" conflict_reason="$3"
  [[ ! -L "$destination" ]] || {
    printf 'script_101_final_application_package=blocked;reason=output_symlink_found\n' >&2
    exit 1
  }
  if [[ -e "$destination" ]]; then
    cmp -s "$source" "$destination" || {
      printf 'script_101_final_application_package=blocked;reason=%s\n' "$conflict_reason" >&2
      exit 1
    }
  else
    local candidate
    candidate="$(mktemp "$OUTPUT_ROOT/.final-application.XXXXXX")"
    cp -- "$source" "$candidate"
    mv -- "$candidate" "$destination"
  fi
}

retain_exact "$temporary_archive" "$archive_path" 'archive_identity_conflict'
retain_exact "$work_root/qualification.json" "$qualification_path" 'qualification_identity_conflict'
retain_exact "$coding_standard_result" "$coding_standard_path" 'coding_standard_identity_conflict'
printf '%s  %s\n' "$archive_sha256" "$archive_name" >"$work_root/archive.sha256"
printf '%s  %s\n' "$qualification_sha256" "$(basename -- "$qualification_path")" >"$work_root/qualification.sha256"
printf '%s  %s\n' "$coding_standard_result_sha256" "$(basename -- "$coding_standard_path")" >"$work_root/coding-standard.sha256"
retain_exact "$work_root/archive.sha256" "$archive_checksum" 'archive_checksum_identity_conflict'
retain_exact "$work_root/qualification.sha256" "$qualification_checksum" 'qualification_checksum_identity_conflict'
retain_exact "$work_root/coding-standard.sha256" "$coding_standard_checksum" 'coding_standard_checksum_identity_conflict'
(
  cd -- "$OUTPUT_ROOT"
  sha256sum --check --strict \
    "$(basename -- "$archive_checksum")" \
    "$(basename -- "$qualification_checksum")" \
    "$(basename -- "$coding_standard_checksum")" >/dev/null
) || {
  printf 'script_101_final_application_package=blocked;reason=retained_checksum_failure\n' >&2
  exit 1
}

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/final_application_package_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=assemble_final_ishikawa_application_package'
emit "started_utc=$timestamp"
emit "script_sha256=$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}');installer_sha256=$(sha256sum "$PACKAGING_ROOT/install-ishikawa" | awk '{print $1}')"
emit "accepted_script_100_report_sha256=$ACCEPTED_REPORT_SHA256;accepted_script_100_artifact_sha256=$ACCEPTED_ARTIFACT_SHA256"
emit 'authorized_actions=read_checksum_bound_sources_run_native_tests_assemble_deterministic_final_package_test_fresh_local_install_retain_content_free_evidence'
emit 'non_actions=no_target_database_service_container_image_model_credential_corpus_or_host_port_contact_or_change'
emit "archive=$archive_path;archive_sha256=$archive_sha256;archive_bytes=$archive_bytes;bundle_file_count=$bundle_file_count;archive_checksum=$archive_checksum"
emit "python_file_count=$python_file_count;web_file_count=$web_file_count;command_file_count=$command_file_count;unit_file_count=$unit_file_count"
emit "qualification=$qualification_path;qualification_sha256=$qualification_sha256;qualification_bytes=$qualification_bytes;qualification_checksum=$qualification_checksum"
emit "coding_standard_sha256=$coding_standard_sha256;coding_standard_receipt=$coding_standard_path;coding_standard_receipt_sha256=$coding_standard_result_sha256;coding_standard_receipt_bytes=$coding_standard_result_bytes;coding_standard_receipt_checksum=$coding_standard_checksum"
emit 'coding_standard_compliant=true;coding_standard_findings=0;historical_mutation_files=0'
emit 'internal_checksums=pass;deterministic_archive=true;fresh_installation=pass'
emit 'repository_references=false;secret_material=false;source_documents_included=false'
emit 'target_contact=false;database_changed=false;service_changed=false;model_contact=false'
emit 'native_tests=360;failures=0;errors=0'
emit "script_101_final_application_package=pass;local_report=$report_path;next_gate=install_and_qualify_refreshed_application_on_emceedanko"
chmod 0600 "$report_path" 2>/dev/null || true
