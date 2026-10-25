#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Assemble and locally qualify one consolidated final-state Ishikawa v1.2
#   application-and-database deployment package.
#
# Mental model:
#   Preserve the accepted v1.1 predecessor, bind the accepted complete v1.2 API
#   gate, run the complete native regression suite, copy only current final
#   runtime files and the final schema, prove reproducibility and fresh local
#   installation, and retain one checksum-bound portable archive.
#
# Inputs or prerequisites:
#   Clean Script 126 and 137 evidence, current checksum-bound Ishikawa sources,
#   Python 3.12 with PyYAML, the coding standard, and GNU archive utilities.
#
# Outputs or artifact lane:
#   One deterministic v1.2 deployment archive, checksum, qualification receipt,
#   coding-standard receipt, and content-free local report. No target, database,
#   model, credential, service, container, or source-document state is touched.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/138_assemble_ishikawa_v1_2_deployment_package.sh --run

usage() {
  sed -n '3,27p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Assemble, qualify, and retain the v1.2 package.' \
    '  --validate-only Run the same local proof without retaining outputs.'
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
readonly APPLICATION_README="$PACKAGING_ROOT/README.md"
readonly APPLICATION_INSTALLER="$PACKAGING_ROOT/install-ishikawa"
readonly DATABASE_README="$PACKAGING_ROOT/database/README.md"
readonly DATABASE_INSTALLER="$PACKAGING_ROOT/database/install-schema"
readonly FINAL_SCHEMA="$PACKAGING_ROOT/database/schema.sql"
readonly DEPLOYMENT_README="$PACKAGING_ROOT/deployment/README-v1.2.md"
readonly PACKAGE_VERIFIER="$PACKAGING_ROOT/deployment/verify-ishikawa-v1.2"
readonly CODING_STANDARD="$REPO_ROOT/CODING_STANDARD.md"
readonly CODING_STANDARD_EVALUATOR="$SCRIPT_DIR/evaluate_consolidated_build_coding_standard.py"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_1_TUNING_DECISIONS.md"

readonly SCRIPT_137_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.2-t14-complete-api/complete_api_20261021T221333Z_1XiuPf.txt"
readonly SCRIPT_137_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/v1.2-t14-complete-api/complete_api_ad2a09462ec39631ce28ff402b46e73f308bb13874bb4f839db4f5aa809275e2.json"
readonly SCRIPT_137_CHECKSUM="$SCRIPT_137_ARTIFACT.sha256"
readonly V1_1_PREDECESSOR_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.1-release/ishikawa_v1_1_acceptance_20261021T192019Z_i20rat.txt"
readonly V1_1_PREDECESSOR_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/v1.1-release/ishikawa_v1_1_acceptance_20261021T192019Z.json"
readonly V1_1_PREDECESSOR_CHECKSUM="$V1_1_PREDECESSOR_ARTIFACT.sha256"

readonly SCRIPT_137_REPORT_SHA256='cdc1ed97a91003777ef9cb054633e9285341bf055062659ec0e96552c3dde09d'
readonly SCRIPT_137_ARTIFACT_SHA256='ad2a09462ec39631ce28ff402b46e73f308bb13874bb4f839db4f5aa809275e2'
readonly SCRIPT_137_CHECKSUM_SHA256='3c5d3f2f1d144ab20859ce247ba069c0dc590e64b8de6c7af52ba95a56b08a11'
readonly V1_1_PREDECESSOR_REPORT_SHA256='87089c174f7c80f968176e336d1e9f63c6fb2e0d3583da5476e03e9bdcb5fa5a'
readonly V1_1_PREDECESSOR_ARTIFACT_SHA256='de66077dee347f3c185b0b8ab0621b8a7a2ad80631e7942b0fb183f6b0f9215e'
readonly V1_1_PREDECESSOR_CHECKSUM_SHA256='62a42148d9118c2f07fa710d347906c10c7fd83589c77e6f97a68014b1d8eec6'
readonly DECISIONS_SHA256='3c656c2032f35f8612446e70668145e18a8a80b9f040343a12dee5125eccfc8a'
readonly TEST_RUNNER_SHA256='092b2cb8e5254d1ca2b6e71a496bf76743004134848e249d5d7b9f37d9d62eb7'
readonly DEPLOYMENT_README_SHA256='c137195e0414bb6653643819962136764a252a9a0e9887ad2b57f926cfc9c4a5'
readonly PACKAGE_VERIFIER_SHA256='36cbaf04794907baa615e39a517ff4271ba178c9420a461fcf67c360d738848f'
readonly FINAL_SCHEMA_SHA256='5cfd397152b726aedc97be84d8a06fc8f21cad6e1a11563e5e9dd3a1f026d568'
readonly ACCEPTED_SOURCE_MANIFEST_SHA256='324aff3117ba823a5e1e52f33060d89d27c90441d3b1e080ea0cda28b3b67556'
readonly ACCEPTED_SOURCE_FILE_COUNT='67'
readonly ACCEPTED_RETRIEVAL_PROFILE_ID='ba4bac60b3f09f6be89db148d1df883748a2003f35a1cecfb6c74f53be74b865'
readonly V1_1_PREDECESSOR_ARCHIVE_SHA256='e5e11c6054b1163868bc21d3b267d804894de0e936c1c1d28c6f506680746e25'
readonly BUNDLE_NAME='ishikawa-v1.2-deployment-package'
readonly OUTPUT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v1.2-deployment-package"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.2-deployment-package"
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
  "$ISHIKAWA_ROOT/docs/APPLICATION_DEFINITION.md"
  "$ISHIKAWA_ROOT/docs/APPLICATION_DESIGN.md"
  "$ISHIKAWA_ROOT/docs/ARCHITECTURE.md"
  "$ISHIKAWA_ROOT/docs/CHAT_UI.md"
  "$ISHIKAWA_ROOT/docs/CHUNKING_INGESTION_RETRIEVAL.md"
  "$ISHIKAWA_ROOT/docs/COMMAND_SHEET.md"
  "$ISHIKAWA_ROOT/docs/INSTALLED_OPERATOR_INGESTION.md"
  "$ISHIKAWA_ROOT/docs/OPERATOR_GUIDE.md"
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
    *) printf 'script_138_v1_2_deployment_package=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_138_v1_2_deployment_package=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in awk bash basename cmp cp date find grep gzip install mkdir mktemp mv python3 rm sed sha256sum sort stat tar tee tr wc; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_138_v1_2_deployment_package=blocked;reason=local_command_missing;command=%s\n' "$required" >&2
    exit 2
  }
done

mapfile -t python_sources < <(find "$PYTHON_PACKAGE" -maxdepth 1 -type f -name '*.py' -print | sort)
mapfile -t configuration_sources < <(find "$CONFIG_ROOT" -maxdepth 1 -type f -name '*.yaml' -print | sort)
(( ${#python_sources[@]} == 48 && ${#configuration_sources[@]} == 18 )) || {
  printf 'script_138_v1_2_deployment_package=blocked;reason=accepted_source_inventory_count_changed\n' >&2
  exit 2
}

required_files=(
  "$TEST_RUNNER" "$APPLICATION_README" "$APPLICATION_INSTALLER"
  "$DATABASE_README" "$DATABASE_INSTALLER" "$FINAL_SCHEMA"
  "$DEPLOYMENT_README" "$PACKAGE_VERIFIER"
  "$CODING_STANDARD" "$CODING_STANDARD_EVALUATOR" "$DECISIONS"
  "$SCRIPT_137_REPORT" "$SCRIPT_137_ARTIFACT" "$SCRIPT_137_CHECKSUM"
  "$V1_1_PREDECESSOR_REPORT" "$V1_1_PREDECESSOR_ARTIFACT" "$V1_1_PREDECESSOR_CHECKSUM"
  "$PACKAGING_ROOT/document_catalog.yaml"
  "$PACKAGING_ROOT/ingestion_manifest.example.yaml"
  "${python_sources[@]}" "${PRODUCT_COMMANDS[@]}" "${PIPELINE_COMMANDS[@]}"
  "${PRODUCT_DOCS[@]}" "${SYSTEMD_UNITS[@]}"
)
for name in "${RUNTIME_CONFIGS[@]}"; do required_files+=("$CONFIG_ROOT/$name"); done
for name in "${WEB_FILES[@]}"; do required_files+=("$WEB_ROOT/$name"); done
for file in "${required_files[@]}"; do
  [[ -f "$file" && ! -L "$file" && -r "$file" ]] || {
    printf 'script_138_v1_2_deployment_package=blocked;reason=required_input_unsafe\n' >&2
    exit 2
  }
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_138_v1_2_deployment_package=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}

check_sha256 "$SCRIPT_137_REPORT" "$SCRIPT_137_REPORT_SHA256" script_137_report
check_sha256 "$SCRIPT_137_ARTIFACT" "$SCRIPT_137_ARTIFACT_SHA256" script_137_artifact
check_sha256 "$SCRIPT_137_CHECKSUM" "$SCRIPT_137_CHECKSUM_SHA256" script_137_checksum
check_sha256 "$V1_1_PREDECESSOR_REPORT" "$V1_1_PREDECESSOR_REPORT_SHA256" v1_1_predecessor_report
check_sha256 "$V1_1_PREDECESSOR_ARTIFACT" "$V1_1_PREDECESSOR_ARTIFACT_SHA256" v1_1_predecessor_artifact
check_sha256 "$V1_1_PREDECESSOR_CHECKSUM" "$V1_1_PREDECESSOR_CHECKSUM_SHA256" v1_1_predecessor_checksum
check_sha256 "$DECISIONS" "$DECISIONS_SHA256" tuning_decisions
check_sha256 "$TEST_RUNNER" "$TEST_RUNNER_SHA256" test_runner
check_sha256 "$DEPLOYMENT_README" "$DEPLOYMENT_README_SHA256" deployment_readme
check_sha256 "$PACKAGE_VERIFIER" "$PACKAGE_VERIFIER_SHA256" package_verifier
check_sha256 "$FINAL_SCHEMA" "$FINAL_SCHEMA_SHA256" final_schema

for sidecar in "$SCRIPT_137_CHECKSUM" "$V1_1_PREDECESSOR_CHECKSUM"; do
  (
    cd -- "$(dirname -- "$sidecar")"
    sha256sum --check --strict "$(basename -- "$sidecar")" >/dev/null
  ) || {
    printf 'script_138_v1_2_deployment_package=blocked;reason=accepted_checksum_failed\n' >&2
    exit 2
  }
done

for fact in \
  '[SUMMARY] full_api_gate=pass;responsive_answered=6/6;nonresponsive_abstained=6/6;broad_clarification=1/1;dependency_failures=0' \
  '[SUMMARY] database_write=false;temporary_service_stopped=true;configuration_changed=false;package_built=false;accepted_v1_1_changed=false;credentials_retained=false' \
  'script_137_t14_complete_api=pass;full_api_gate=pass;next_gate=assemble_ishikawa_v1_2_final_state_package;'; do
  grep -Fq "$fact" "$SCRIPT_137_REPORT" || {
    printf 'script_138_v1_2_deployment_package=blocked;reason=script_137_contract_invalid\n' >&2
    exit 2
  }
done
for fact in \
  "archive_sha256=$V1_1_PREDECESSOR_ARCHIVE_SHA256" \
  'host_qualification=pass' \
  'v1_fallback_unchanged=true' \
  'script_126_v1_1_acceptance=pass;'; do
  grep -Fq "$fact" "$V1_1_PREDECESSOR_REPORT" || {
    printf 'script_138_v1_2_deployment_package=blocked;reason=v1_1_predecessor_contract_invalid\n' >&2
    exit 2
  }
done
grep -Fq "\"archive_sha256\":\"$V1_1_PREDECESSOR_ARCHIVE_SHA256\"" "$V1_1_PREDECESSOR_ARTIFACT" || {
  printf 'script_138_v1_2_deployment_package=blocked;reason=v1_1_predecessor_artifact_invalid\n' >&2
  exit 2
}
for decision in T09 T10 T12 T13 T14; do
  grep -F "| \`$decision\` |" "$DECISIONS" | grep -Fq '| FROZEN |' || {
    printf 'script_138_v1_2_deployment_package=blocked;reason=%s_not_frozen\n' "${decision,,}" >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER" "$APPLICATION_INSTALLER" "$DATABASE_INSTALLER" "$PACKAGE_VERIFIER"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$CODING_STANDARD_EVALUATOR" "${python_sources[@]}" "${PIPELINE_COMMANDS[@]}" "${PRODUCT_COMMANDS[@]:0:5}"

umask 077
work_root="$(mktemp -d /tmp/ishikawa-script-138.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  [[ "$work_root" == /tmp/ishikawa-script-138.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

source_manifest="$work_root/accepted-source.sha256"
for source in "${python_sources[@]}" "${configuration_sources[@]}" "$ISHIKAWA_ROOT/scripts/ishikawa-retrieval-api"; do
  printf '%s  %s\n' \
    "$(sha256sum "$source" | awk '{print $1}')" \
    "${source#"$ISHIKAWA_ROOT"/}"
done >"$source_manifest"
[[ "$(wc -l <"$source_manifest" | tr -d ' ')" == "$ACCEPTED_SOURCE_FILE_COUNT" ]] || {
  printf 'script_138_v1_2_deployment_package=blocked;reason=accepted_source_manifest_count_changed\n' >&2
  exit 2
}
[[ "$(sha256sum "$source_manifest" | awk '{print $1}')" == "$ACCEPTED_SOURCE_MANIFEST_SHA256" ]] || {
  printf 'script_138_v1_2_deployment_package=blocked;reason=accepted_source_manifest_identity_changed\n' >&2
  exit 2
}

test_result="$work_root/native-tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  printf 'script_138_v1_2_deployment_package=blocked;reason=native_test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s;raw_output_retained=false\n' \
    "$(sha256sum "$test_result" | awk '{print $1}')" "$(stat -c '%s' "$test_result")" >&2
  exit 1
}
grep -Fq 'Ran 381 tests' "$test_result" || {
  printf 'script_138_v1_2_deployment_package=blocked;reason=native_test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_138_v1_2_deployment_package=blocked;reason=native_test_pass_marker_absent\n' >&2
  exit 1
}

assemble_application() {
  local destination="$1" source name destination_name
  install -d -m 0755 -- \
    "$destination/payload/application/python/ishikawa" \
    "$destination/payload/application/web/app/api/live" \
    "$destination/payload/application/web/app/api/ready" \
    "$destination/payload/application/web/app/api/v1/chat" \
    "$destination/payload/application/web/components" \
    "$destination/payload/application/web/lib" \
    "$destination/payload/config/examples" \
    "$destination/payload/docs" \
    "$destination/payload/scripts" \
    "$destination/payload/systemd"
  install -m 0644 -- "$APPLICATION_README" "$destination/README.md"
  install -m 0755 -- "$APPLICATION_INSTALLER" "$destination/install-ishikawa"
  for source in "${python_sources[@]}"; do
    install -m 0644 -- "$source" "$destination/payload/application/python/ishikawa/$(basename -- "$source")"
  done
  for name in "${WEB_FILES[@]}"; do
    install -m 0644 -- "$WEB_ROOT/$name" "$destination/payload/application/web/$name"
  done
  for source in "${PRODUCT_COMMANDS[@]}" "${PIPELINE_COMMANDS[@]}"; do
    install -m 0755 -- "$source" "$destination/payload/scripts/$(basename -- "$source")"
  done
  for name in "${RUNTIME_CONFIGS[@]}"; do
    install -m 0644 -- "$CONFIG_ROOT/$name" "$destination/payload/config/$name"
  done
  install -m 0644 -- "$PACKAGING_ROOT/document_catalog.yaml" "$destination/payload/config/document_catalog.yaml"
  install -m 0644 -- "$PACKAGING_ROOT/ingestion_manifest.example.yaml" "$destination/payload/config/examples/ingestion_manifest.yaml"
  install -m 0644 -- "$CONFIG_ROOT/document_catalog.yaml" "$destination/payload/config/examples/document_catalog.yaml"
  for source in "${PRODUCT_DOCS[@]}"; do
    destination_name="$(basename -- "$source")"
    [[ "$destination_name" != INSTALLED_OPERATOR_INGESTION.md ]] || destination_name='OPERATOR_INGESTION.md'
    install -m 0644 -- "$source" "$destination/payload/docs/$destination_name"
  done
  for source in "${SYSTEMD_UNITS[@]}"; do
    install -m 0644 -- "$source" "$destination/payload/systemd/$(basename -- "$source")"
  done
  (
    cd -- "$destination"
    while IFS= read -r name; do sha256sum "$name"; done < <(
      find . -type f ! -name SHA256SUMS -printf '%P\n' | sort
    ) >SHA256SUMS
  )
  chmod 0644 "$destination/SHA256SUMS"
}

assemble_database() {
  local destination="$1" name
  install -d -m 0755 -- "$destination"
  install -m 0644 -- "$DATABASE_README" "$destination/README.md"
  install -m 0755 -- "$DATABASE_INSTALLER" "$destination/install-schema"
  install -m 0644 -- "$FINAL_SCHEMA" "$destination/schema.sql"
  (
    cd -- "$destination"
    while IFS= read -r name; do sha256sum "$name"; done < <(
      find . -type f ! -name SHA256SUMS -printf '%P\n' | sort
    ) >SHA256SUMS
  )
  chmod 0644 "$destination/SHA256SUMS"
}

assemble_bundle() {
  local destination="$1" bundle="$1/$BUNDLE_NAME" name
  install -d -m 0755 -- "$bundle/application" "$bundle/database"
  assemble_application "$bundle/application"
  assemble_database "$bundle/database"
  install -m 0644 -- "$DEPLOYMENT_README" "$bundle/README.md"
  install -m 0755 -- "$PACKAGE_VERIFIER" "$bundle/verify-ishikawa-v1.2"
  (
    cd -- "$bundle"
    while IFS= read -r name; do sha256sum "$name"; done < <(
      find . -type f ! -path './SHA256SUMS' -printf '%P\n' | sort
    ) >SHA256SUMS
  )
  chmod 0644 "$bundle/SHA256SUMS"
}

mkdir -p -- "$work_root/build-a" "$work_root/build-b"
assemble_bundle "$work_root/build-a"
assemble_bundle "$work_root/build-b"
readonly bundle_a="$work_root/build-a/$BUNDLE_NAME"
readonly bundle_b="$work_root/build-b/$BUNDLE_NAME"

for bundle in "$bundle_a" "$bundle_b"; do
  bash "$bundle/verify-ishikawa-v1.2" | grep -Fxq \
    'ishikawa_v1_2_verification=pass;application=final;database_schema=version_4;python_modules=48;operator_documents=10;document_page_routing=bound;structured_generation=bound;historical_mutation_files=0' || {
      printf 'script_138_v1_2_deployment_package=blocked;reason=package_verification_failed\n' >&2
      exit 1
    }
  find "$bundle" -type l -print -quit | grep -q . && {
    printf 'script_138_v1_2_deployment_package=blocked;reason=package_symlink_found\n' >&2
    exit 1
  }
  if find "$bundle" -type f \( -name '*.pyc' -o -name '*.pyo' \) -print -quit | grep -q . \
    || find "$bundle" -type d -name __pycache__ -print -quit | grep -q .; then
    printf 'script_138_v1_2_deployment_package=blocked;reason=generated_python_file_found\n' >&2
    exit 1
  fi
  if find "$bundle" -type f \( -iname '*migration*' -o -iname '*mutation*' -o -iname '*patch*' -o -iname '*repair*' \) -print -quit | grep -q .; then
    printf 'script_138_v1_2_deployment_package=blocked;reason=historical_mutation_file_found\n' >&2
    exit 1
  fi
  if find "$bundle" -type d ! -perm -005 -print -quit | grep -q . \
    || find "$bundle" -type f ! -perm -004 -print -quit | grep -q .; then
    printf 'script_138_v1_2_deployment_package=blocked;reason=nonroot_package_readability_invalid\n' >&2
    exit 1
  fi
  if grep -ERiq -- "$FORBIDDEN_PATTERN" "$bundle"; then
    printf 'script_138_v1_2_deployment_package=blocked;reason=development_jargon_found\n' >&2
    exit 1
  fi
  if grep -ERq -- 'BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY|Authorization:[[:space:]]*Bearer[[:space:]]+[^$]' "$bundle"; then
    printf 'script_138_v1_2_deployment_package=blocked;reason=credential_material_found\n' >&2
    exit 1
  fi
done

if ! cmp -s \
  <(cd -- "$bundle_a" && find . -type f -printf '%P\n' | sort | while IFS= read -r name; do sha256sum "$name"; done) \
  <(cd -- "$bundle_b" && find . -type f -printf '%P\n' | sort | while IFS= read -r name; do sha256sum "$name"; done); then
  printf 'script_138_v1_2_deployment_package=blocked;reason=bundle_not_reproducible\n' >&2
  exit 1
fi

coding_standard_result="$work_root/coding-standard.json"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$CODING_STANDARD_EVALUATOR" \
  --bundle-root "$bundle_a" \
  --standard "$CODING_STANDARD" \
  --output "$coding_standard_result" >/dev/null || {
    printf 'script_138_v1_2_deployment_package=blocked;reason=coding_standard_noncompliance\n' >&2
    exit 1
  }

install_root="$work_root/fresh-install/Ishikawa"
bash "$bundle_a/application/install-ishikawa" --install-root "$install_root" >"$work_root/application-install.txt"
grep -Fq 'ishikawa_install=pass;' "$work_root/application-install.txt" || {
  printf 'script_138_v1_2_deployment_package=blocked;reason=fresh_application_install_failed\n' >&2
  exit 1
}
[[ "$(find "$install_root/application/python/ishikawa" -maxdepth 1 -type f -name '*.py' | awk 'END {print NR+0}')" == 48 ]] || {
  printf 'script_138_v1_2_deployment_package=blocked;reason=installed_python_inventory_invalid\n' >&2
  exit 1
}
[[ "$(find "$install_root/docs" -maxdepth 1 -type f -name '*.md' | awk 'END {print NR+0}')" == 10 ]] || {
  printf 'script_138_v1_2_deployment_package=blocked;reason=installed_document_inventory_invalid\n' >&2
  exit 1
}
PYTHONDONTWRITEBYTECODE=1 "$install_root/scripts/ishikawa-retrieval-api" --check-config >/dev/null || {
  printf 'script_138_v1_2_deployment_package=blocked;reason=installed_retrieval_config_invalid\n' >&2
  exit 1
}
PYTHONDONTWRITEBYTECODE=1 "$install_root/scripts/ishikawa-observability-retention" --check-config >/dev/null || {
  printf 'script_138_v1_2_deployment_package=blocked;reason=installed_retention_config_invalid\n' >&2
  exit 1
}
"$install_root/scripts/ishikawa-stack" --help >/dev/null
"$install_root/scripts/ishikawa-ingest" --help >/dev/null
bash "$bundle_a/database/install-schema" --help >/dev/null

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
bash "$extracted_bundle/verify-ishikawa-v1.2" >/dev/null || {
  printf 'script_138_v1_2_deployment_package=blocked;reason=extracted_package_verification_failed\n' >&2
  exit 1
}

archive_sha256="$(sha256sum "$temporary_archive" | awk '{print $1}')"
archive_bytes="$(stat -c '%s' "$temporary_archive")"
package_file_count="$(find "$extracted_bundle" -type f | awk 'END {print NR+0}')"
application_file_count="$(find "$extracted_bundle/application" -type f | awk 'END {print NR+0}')"
database_file_count="$(find "$extracted_bundle/database" -type f | awk 'END {print NR+0}')"
coding_standard_sha256="$(sha256sum "$CODING_STANDARD" | awk '{print $1}')"
coding_standard_result_sha256="$(sha256sum "$coding_standard_result" | awk '{print $1}')"
coding_standard_result_bytes="$(stat -c '%s' "$coding_standard_result")"

printf '{"application_file_count":%s,"archive_bytes":%s,"archive_sha256":"%s","coding_standard_compliant":true,"database_file_count":%s,"deterministic_archive":true,"document_page_routing_qualified":true,"fresh_application_install":true,"historical_mutation_files":0,"native_test_count":381,"package_file_count":%s,"predecessor_archive_sha256":"%s","receipt_schema_version":1,"release_name":"Ishikawa v1.2","repository_references":false,"retrieval_profile_id":"%s","schema_version":4,"secret_material":false,"source_documents_included":false,"structured_generation_qualified":true}\n' \
  "$application_file_count" "$archive_bytes" "$archive_sha256" "$database_file_count" \
  "$package_file_count" "$V1_1_PREDECESSOR_ARCHIVE_SHA256" "$ACCEPTED_RETRIEVAL_PROFILE_ID" \
  >"$work_root/qualification.json"
qualification_sha256="$(sha256sum "$work_root/qualification.json" | awk '{print $1}')"

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_consolidated_ishikawa_v1_2_deployment_package' \
    "script_sha256=$script_sha256;archive_sha256=$archive_sha256;archive_bytes=$archive_bytes" \
    "script_137_report_sha256=$SCRIPT_137_REPORT_SHA256;script_137_artifact_sha256=$SCRIPT_137_ARTIFACT_SHA256" \
    "v1_1_predecessor_report_sha256=$V1_1_PREDECESSOR_REPORT_SHA256;v1_1_predecessor_archive_sha256=$V1_1_PREDECESSOR_ARCHIVE_SHA256" \
    "accepted_source_manifest_sha256=$ACCEPTED_SOURCE_MANIFEST_SHA256;source_files=$ACCEPTED_SOURCE_FILE_COUNT;retrieval_profile_id=$ACCEPTED_RETRIEVAL_PROFILE_ID" \
    "package_files=$package_file_count;application_files=$application_file_count;database_files=$database_file_count;python_modules=48;operator_documents=10" \
    "coding_standard_sha256=$coding_standard_sha256;coding_standard_receipt_sha256=$coding_standard_result_sha256;coding_standard_receipt_bytes=$coding_standard_result_bytes" \
    'native_tests=381;failures=0;errors=0;full_api_gate=pass;document_page_routing=bound;structured_generation=bound' \
    'internal_checksums=pass;deterministic_archive=true;fresh_application_install=pass;nonroot_package_readability=pass;final_schema=version_4' \
    'historical_mutation_files=0;repository_references=false;secret_material=false;source_documents_included=false' \
    'target_contact=false;database_contact=false;model_contact=false;credential_read=false;service_changed=false' \
    'script_138_v1_2_deployment_package_source=pass'
  exit 0
fi

mkdir -p -- "$OUTPUT_ROOT" "$REPORT_ROOT"
archive_name="$BUNDLE_NAME-${archive_sha256:0:16}.tar.gz"
archive_path="$OUTPUT_ROOT/$archive_name"
archive_checksum="$archive_path.sha256"
qualification_path="$OUTPUT_ROOT/v1_2_deployment_package_qualification_${archive_sha256:0:16}.json"
qualification_checksum="$qualification_path.sha256"
coding_standard_path="$OUTPUT_ROOT/v1_2_deployment_coding_standard_${archive_sha256:0:16}.json"
coding_standard_checksum="$coding_standard_path.sha256"

retain_exact() {
  local source="$1" destination="$2" conflict_reason="$3" candidate
  [[ ! -L "$destination" ]] || {
    printf 'script_138_v1_2_deployment_package=blocked;reason=output_symlink_found\n' >&2
    exit 1
  }
  if [[ -e "$destination" ]]; then
    cmp -s "$source" "$destination" || {
      printf 'script_138_v1_2_deployment_package=blocked;reason=%s\n' "$conflict_reason" >&2
      exit 1
    }
  else
    candidate="$(mktemp "$OUTPUT_ROOT/.v1.2-package.XXXXXX")"
    cp -- "$source" "$candidate"
    mv -- "$candidate" "$destination"
  fi
}

retain_exact "$temporary_archive" "$archive_path" archive_identity_conflict
retain_exact "$work_root/qualification.json" "$qualification_path" qualification_identity_conflict
retain_exact "$coding_standard_result" "$coding_standard_path" coding_standard_identity_conflict
printf '%s  %s\n' "$archive_sha256" "$archive_name" >"$work_root/archive.sha256"
printf '%s  %s\n' "$qualification_sha256" "$(basename -- "$qualification_path")" >"$work_root/qualification.sha256"
printf '%s  %s\n' "$coding_standard_result_sha256" "$(basename -- "$coding_standard_path")" >"$work_root/coding-standard.sha256"
retain_exact "$work_root/archive.sha256" "$archive_checksum" archive_checksum_identity_conflict
retain_exact "$work_root/qualification.sha256" "$qualification_checksum" qualification_checksum_identity_conflict
retain_exact "$work_root/coding-standard.sha256" "$coding_standard_checksum" coding_standard_checksum_identity_conflict
(
  cd -- "$OUTPUT_ROOT"
  sha256sum --check --strict \
    "$(basename -- "$archive_checksum")" \
    "$(basename -- "$qualification_checksum")" \
    "$(basename -- "$coding_standard_checksum")" >/dev/null
) || {
  printf 'script_138_v1_2_deployment_package=blocked;reason=retained_checksum_failure\n' >&2
  exit 1
}

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/v1_2_deployment_package_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=assemble_consolidated_final_ishikawa_v1_2_deployment_package'
emit "started_utc=$timestamp;script_sha256=$script_sha256"
emit "script_137_report_sha256=$SCRIPT_137_REPORT_SHA256;script_137_artifact_sha256=$SCRIPT_137_ARTIFACT_SHA256;full_api_gate=pass"
emit "v1_1_predecessor_report_sha256=$V1_1_PREDECESSOR_REPORT_SHA256;v1_1_predecessor_archive_sha256=$V1_1_PREDECESSOR_ARCHIVE_SHA256;predecessor_unchanged=true"
emit "accepted_source_manifest_sha256=$ACCEPTED_SOURCE_MANIFEST_SHA256;source_files=$ACCEPTED_SOURCE_FILE_COUNT;retrieval_profile_id=$ACCEPTED_RETRIEVAL_PROFILE_ID;document_page_routing=bound;structured_generation=bound"
emit "archive=$archive_path;archive_sha256=$archive_sha256;archive_bytes=$archive_bytes;archive_checksum=$archive_checksum"
emit "package_files=$package_file_count;application_files=$application_file_count;database_files=$database_file_count;python_modules=48;operator_documents=10"
emit "qualification=$qualification_path;qualification_sha256=$qualification_sha256;qualification_checksum=$qualification_checksum"
emit "coding_standard_sha256=$coding_standard_sha256;coding_standard_receipt=$coding_standard_path;coding_standard_receipt_sha256=$coding_standard_result_sha256;coding_standard_receipt_checksum=$coding_standard_checksum"
emit 'native_tests=381;failures=0;errors=0;internal_checksums=pass;deterministic_archive=true;fresh_application_install=pass;nonroot_package_readability=pass'
emit 'final_schema=version_4;historical_mutation_files=0;repository_references=false;secret_material=false;source_documents_included=false'
emit 'target_contact=false;database_contact=false;model_contact=false;credential_read=false;service_changed=false'
emit "script_138_v1_2_deployment_package=pass;next_gate=qualify_fresh_v1_2_installation_on_emceedanko;local_report=$report_path"
chmod 0600 "$report_path" 2>/dev/null || true
