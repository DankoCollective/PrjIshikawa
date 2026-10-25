#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Assemble and locally qualify a deterministic, repository-free Ishikawa
#   application package. This command contacts no target, database, or model.
#
# Mental model:
#   Bind the package to accepted application evidence, run the full local test
#   suite, copy only allowlisted product files, enforce the coding standard,
#   prove reproducibility, and test one fresh temporary installation.
#
# Inputs or prerequisites:
#   The accepted installed-ingestion receipt, the current Ishikawa product
#   sources, CODING_STANDARD.md, Python 3.12, PyYAML, and GNU archive tools.
#
# Outputs:
#   A deterministic application archive, checksums, a content-free coding-
#   standard receipt, and a local qualification report. No target is contacted.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/88_assemble_portable_ishikawa_application_package.sh --run

usage() {
  sed -n '3,9p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Assemble, validate, and retain the package.' \
    '  --validate-only Assemble and validate without retaining outputs.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$ISHIKAWA_ROOT/application/python"
readonly PACKAGE_ROOT="$PYTHON_ROOT/ishikawa"
readonly CONFIG_ROOT="$ISHIKAWA_ROOT/config/templates"
readonly PACKAGING_ROOT="$ISHIKAWA_ROOT/packaging"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly CODING_STANDARD="$REPO_ROOT/CODING_STANDARD.md"
readonly CODING_STANDARD_EVALUATOR="$SCRIPT_DIR/evaluate_consolidated_build_coding_standard.py"
readonly BUNDLE_NAME='ishikawa-application-package'
readonly ACCEPTED_SCRIPT_87_REPORT="$REPO_ROOT/local/reports/ishikawa-installed-ingestion-entrypoint/installed_ingestion_entrypoint_20261020T215218Z_G18dcu.txt"
readonly ACCEPTED_SCRIPT_87_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/installed-ingestion-entrypoint/installed_ingestion_entrypoint_qualification_20261020T215218Z.json"
readonly ACCEPTED_SCRIPT_87_CHECKSUM="$ACCEPTED_SCRIPT_87_ARTIFACT.sha256"
readonly ACCEPTED_SCRIPT_87_REPORT_SHA256='f8a609be32f8b30cc6c0f5bd72956469d21db2d0047ab5aaf36aa56f59e9f33c'
readonly ACCEPTED_SCRIPT_87_ARTIFACT_SHA256='548ab6c8656b840b07f9b4065e57c39cc92ba8538070709784b636c2e8eda657'
readonly ACCEPTED_SCRIPT_87_CHECKSUM_SHA256='1713c799fe2cfed8ded86ae74449f8deb867c4b2164ba980bfab8da9d93c6d18'
readonly OUTPUT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/application-package"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-application-package"
readonly FORBIDDEN_PATTERN='phase[-_ ]*[0-9]|org[-_ ]*lab|danko|agentdanko|dankorepos|prj[0-9]|codex|opencode|local/artifacts|/mnt/|\.git/'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'ERROR: unsupported argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'BLOCKED: choose exactly one of --run or --validate-only.\n' >&2
  exit 2
}

for required in awk bash basename cmp cp date find grep gzip install mkdir mktemp mv python3 rm sed sha256sum sort stat tar tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'BLOCKED: missing local command: %s\n' "$required" >&2
    exit 2
  }
done

mapfile -t python_sources < <(find "$PACKAGE_ROOT" -maxdepth 1 -type f -name '*.py' -print | sort)
readonly -a RUNTIME_CONFIGS=(
  api_profile.yaml
  deployment.yaml
  document_classes.yaml
  ingestion_dependencies.yaml
  injection_profile.yaml
  method_profile.yaml
  query_resolution_profile.yaml
  reconstruction_profile.yaml
  relationship_types.yaml
  relevance_profile.yaml
  retrieval_service_profile.yaml
  runtime_dependencies.yaml
  scope_profile.yaml
  sufficiency_profile.yaml
)
readonly -a INSTALLED_SCRIPTS=(
  "$ISHIKAWA_ROOT/scripts/ishikawa-ingest"
  "$ISHIKAWA_ROOT/scripts/ishikawa-produce-artifacts"
  "$SCRIPT_DIR/capture-pdf-extraction-observations.py"
  "$SCRIPT_DIR/normalize-pdf-extraction.py"
  "$SCRIPT_DIR/create-structural-chunk-candidates.py"
  "$SCRIPT_DIR/embed_document_candidates_via_endpoint.py"
)

for source in \
  "$TEST_RUNNER" "$CODING_STANDARD" "$CODING_STANDARD_EVALUATOR" \
  "$PACKAGING_ROOT/README.md" "$PACKAGING_ROOT/install-ishikawa" \
  "$PACKAGING_ROOT/document_catalog.yaml" "$PACKAGING_ROOT/ingestion_manifest.example.yaml" "$CONFIG_ROOT/product.yaml" \
  "$CONFIG_ROOT/document_catalog.yaml" \
  "$ACCEPTED_SCRIPT_87_REPORT" "$ACCEPTED_SCRIPT_87_ARTIFACT" "$ACCEPTED_SCRIPT_87_CHECKSUM" \
  "${python_sources[@]}" "${INSTALLED_SCRIPTS[@]}"; do
  [[ -f "$source" && ! -L "$source" && -r "$source" ]] || {
    printf 'BLOCKED: a required Script 88 input is missing or unsafe.\n' >&2
    exit 2
  }
done
(( ${#python_sources[@]} >= 35 )) || { printf 'BLOCKED: Python source inventory is incomplete.\n' >&2; exit 2; }
for name in "${RUNTIME_CONFIGS[@]}"; do
  [[ -f "$CONFIG_ROOT/$name" && ! -L "$CONFIG_ROOT/$name" ]] || {
    printf 'BLOCKED: runtime configuration inventory is incomplete.\n' >&2
    exit 2
  }
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'BLOCKED: %s identity changed.\n' "$3" >&2
    exit 2
  }
}
check_sha256 "$ACCEPTED_SCRIPT_87_REPORT" "$ACCEPTED_SCRIPT_87_REPORT_SHA256" 'accepted Script 87 report'
check_sha256 "$ACCEPTED_SCRIPT_87_ARTIFACT" "$ACCEPTED_SCRIPT_87_ARTIFACT_SHA256" 'accepted Script 87 artifact'
check_sha256 "$ACCEPTED_SCRIPT_87_CHECKSUM" "$ACCEPTED_SCRIPT_87_CHECKSUM_SHA256" 'accepted Script 87 checksum'
(cd "$(dirname -- "$ACCEPTED_SCRIPT_87_ARTIFACT")" && sha256sum --check --strict "$(basename -- "$ACCEPTED_SCRIPT_87_CHECKSUM")" >/dev/null) || {
  printf 'BLOCKED: accepted Script 87 artifact failed checksum verification.\n' >&2
  exit 2
}
for fact in \
  'installed_operator_ingestion_entrypoint_qualification=pass' \
  'local_tests=316;failures=0;errors=0' \
  'script_87_installed_ingestion_entrypoint=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_SCRIPT_87_REPORT" || {
    printf 'BLOCKED: an accepted Script 87 fact is absent.\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}" "$PACKAGING_ROOT/install-ishikawa" "$TEST_RUNNER"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$CODING_STANDARD_EVALUATOR" "${python_sources[@]}" "${INSTALLED_SCRIPTS[@]}"

work_root="$(mktemp -d /tmp/ishikawa-script-88.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-88.* && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  printf 'script_88_application_package=blocked;reason=test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$test_result" | awk '{print $1}')" "$(stat -c '%s' "$test_result")" >&2
  exit 1
}
grep -Fq 'Ran 319 tests' "$test_result" || {
  printf 'script_88_application_package=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_88_application_package=blocked;reason=test_pass_marker_absent\n' >&2
  exit 1
}

assemble_bundle() {
  local destination="$1"
  local bundle="$destination/$BUNDLE_NAME"
  install -d -m 0755 -- \
    "$bundle/payload/application/python/ishikawa" \
    "$bundle/payload/config/examples" \
    "$bundle/payload/scripts" \
    "$bundle/payload/docs"
  install -m 0644 -- "$PACKAGING_ROOT/README.md" "$bundle/README.md"
  install -m 0755 -- "$PACKAGING_ROOT/install-ishikawa" "$bundle/install-ishikawa"

  local source
  for source in "${python_sources[@]}"; do
    install -m 0644 -- "$source" "$bundle/payload/application/python/ishikawa/$(basename -- "$source")"
  done
  for source in "${INSTALLED_SCRIPTS[@]}"; do
    install -m 0755 -- "$source" "$bundle/payload/scripts/$(basename -- "$source")"
  done

  install -m 0644 -- "$CONFIG_ROOT/product.yaml" "$bundle/payload/config/product.yaml"
  install -m 0644 -- "$PACKAGING_ROOT/document_catalog.yaml" "$bundle/payload/config/document_catalog.yaml"
  local name
  for name in "${RUNTIME_CONFIGS[@]}"; do
    install -m 0644 -- "$CONFIG_ROOT/$name" "$bundle/payload/config/$name"
  done
  install -m 0644 -- "$CONFIG_ROOT/document_catalog.yaml" "$bundle/payload/config/examples/document_catalog.yaml"
  install -m 0644 -- "$PACKAGING_ROOT/ingestion_manifest.example.yaml" "$bundle/payload/config/examples/ingestion_manifest.yaml"
  install -m 0644 -- "$ISHIKAWA_ROOT/docs/INSTALLED_OPERATOR_INGESTION.md" "$bundle/payload/docs/OPERATOR_INGESTION.md"

  (
    cd -- "$bundle"
    while IFS= read -r path; do sha256sum "$path"; done < <(
      find . -type f ! -name SHA256SUMS -printf '%P\n' | sort
    ) > SHA256SUMS
  )
}

mkdir -p -- "$work_root/build-a" "$work_root/build-b"
assemble_bundle "$work_root/build-a"
assemble_bundle "$work_root/build-b"

for bundle in "$work_root/build-a/$BUNDLE_NAME" "$work_root/build-b/$BUNDLE_NAME"; do
  (
    cd -- "$bundle"
    sha256sum --check --strict SHA256SUMS >/dev/null
  ) || { printf 'script_88_application_package=blocked;reason=internal_checksum_failure\n' >&2; exit 1; }
  if find "$bundle" -type l -print -quit | grep -q .; then
    printf 'script_88_application_package=blocked;reason=package_symlink_found\n' >&2
    exit 1
  fi
  if find "$bundle" -type f \( -name '*.pyc' -o -name '*.pyo' \) -print -quit | grep -q . || find "$bundle" -type d -name __pycache__ -print -quit | grep -q .; then
    printf 'script_88_application_package=blocked;reason=generated_python_file_found\n' >&2
    exit 1
  fi
  if grep -ERiq -- "$FORBIDDEN_PATTERN" "$bundle"; then
    printf 'script_88_application_package=blocked;reason=development_jargon_found\n' >&2
    exit 1
  fi
  if grep -ERq -- 'BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY|Authorization:[[:space:]]*Bearer[[:space:]]+[^$]' "$bundle"; then
    printf 'script_88_application_package=blocked;reason=credential_material_found\n' >&2
    exit 1
  fi
done

coding_standard_result="$work_root/coding-standard.json"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$CODING_STANDARD_EVALUATOR" \
  --bundle-root "$work_root/build-a/$BUNDLE_NAME" \
  --standard "$CODING_STANDARD" \
  --output "$coding_standard_result" || {
  printf 'script_88_application_package=blocked;reason=coding_standard_noncompliance\n' >&2
  exit 1
}
coding_standard_sha256="$(sha256sum "$CODING_STANDARD" | awk '{print $1}')"
coding_standard_result_sha256="$(sha256sum "$coding_standard_result" | awk '{print $1}')"
coding_standard_result_bytes="$(stat -c '%s' "$coding_standard_result")"
if ! cmp -s \
  <(cd "$work_root/build-a/$BUNDLE_NAME" && find . -type f -printf '%P\n' | sort | while IFS= read -r path; do sha256sum "$path"; done) \
  <(cd "$work_root/build-b/$BUNDLE_NAME" && find . -type f -printf '%P\n' | sort | while IFS= read -r path; do sha256sum "$path"; done); then
  printf 'script_88_application_package=blocked;reason=bundle_not_reproducible\n' >&2
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
extracted_bundle="$work_root/extracted/$BUNDLE_NAME"
(
  cd -- "$extracted_bundle"
  sha256sum --check --strict SHA256SUMS >/dev/null
) || { printf 'script_88_application_package=blocked;reason=extracted_checksum_failure\n' >&2; exit 1; }

install_root="$work_root/installed/Ishikawa"
bash "$extracted_bundle/install-ishikawa" --install-root "$install_root" >"$work_root/install.txt"
grep -Fq 'ishikawa_install=pass;' "$work_root/install.txt" || {
  printf 'script_88_application_package=blocked;reason=installer_pass_marker_absent\n' >&2
  exit 1
}
[[ -x "$install_root/scripts/ishikawa-ingest" && -x "$install_root/scripts/ishikawa-produce-artifacts" ]] || {
  printf 'script_88_application_package=blocked;reason=installed_entrypoint_not_executable\n' >&2
  exit 1
}
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$install_root/application/python" python3 -B - "$install_root" <<'PY' || {
from pathlib import Path
import sys
import yaml

from ishikawa.installed_ingestion import InstalledIngestionLayout
from ishikawa.validators import validate_class_registry, validate_document_catalog
from ishikawa.yaml_loader import load_restricted_yaml

root = Path(sys.argv[1]).resolve(strict=True)
InstalledIngestionLayout.from_product_root(root)
classes = validate_class_registry(
    load_restricted_yaml(root / "config/document_classes.yaml", label="document class registry")
)
catalog = validate_document_catalog(
    load_restricted_yaml(root / "config/document_catalog.yaml", label="document catalog")
)
product = yaml.safe_load((root / "config/product.yaml").read_text(encoding="utf-8"))
if len(classes.classes) != 3 or catalog.documents or product != {"schema_version": 1, "display_name": "Ishikawa"}:
    raise SystemExit(1)
PY
  printf 'script_88_application_package=blocked;reason=installed_contract_validation_failed\n' >&2
  exit 1
}

archive_sha256="$(sha256sum "$temporary_archive" | awk '{print $1}')"
archive_bytes="$(stat -c '%s' "$temporary_archive")"
bundle_file_count="$(find "$extracted_bundle" -type f | awk 'END {print NR}')"
python_file_count="$(find "$install_root/application/python/ishikawa" -maxdepth 1 -type f -name '*.py' | awk 'END {print NR}')"
cat >"$work_root/qualification.json" <<EOF
{"archive_bytes":$archive_bytes,"archive_sha256":"$archive_sha256","bundle_file_count":$bundle_file_count,"coding_standard_compliant":true,"coding_standard_sha256":"$coding_standard_sha256","database_changed":false,"model_contact":false,"python_file_count":$python_file_count,"repository_references":false,"schema_version":1,"secret_material":false,"service_changed":false,"source_documents_included":false,"target_contact":false}
EOF
qualification_sha256="$(sha256sum "$work_root/qualification.json" | awk '{print $1}')"
qualification_bytes="$(stat -c '%s' "$work_root/qualification.json")"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_portable_ishikawa_application_package' \
    "archive_sha256=$archive_sha256;archive_bytes=$archive_bytes;bundle_file_count=$bundle_file_count;python_file_count=$python_file_count" \
    "coding_standard_sha256=$coding_standard_sha256;coding_standard_result_sha256=$coding_standard_result_sha256;coding_standard_result_bytes=$coding_standard_result_bytes" \
    'coding_standard_compliant=true;coding_standard_findings=0' \
    'deterministic_archive=true;internal_checksums=pass;fresh_installation=pass' \
    'repository_references=false;secret_material=false;source_documents_included=false' \
    'target_contact=false;database_changed=false;service_changed=false;model_contact=false' \
    'local_tests=319;failures=0;errors=0' \
    'script_88_application_package_source=pass'
  exit 0
fi

mkdir -p -- "$OUTPUT_ROOT" "$REPORT_ROOT"
archive_name="ishikawa-application-package-${archive_sha256:0:16}.tar.gz"
archive_path="$OUTPUT_ROOT/$archive_name"
archive_checksum="$archive_path.sha256"
qualification_path="$OUTPUT_ROOT/ishikawa_application_package_qualification_${archive_sha256:0:16}.json"
qualification_checksum="$qualification_path.sha256"
coding_standard_path="$OUTPUT_ROOT/ishikawa_coding_standard_compliance_${archive_sha256:0:16}.json"
coding_standard_checksum="$coding_standard_path.sha256"
for destination in "$archive_path" "$archive_checksum" "$qualification_path" "$qualification_checksum" "$coding_standard_path" "$coding_standard_checksum"; do
  [[ ! -L "$destination" ]] || { printf 'script_88_application_package=blocked;reason=output_symlink_found\n' >&2; exit 1; }
done
if [[ -e "$archive_path" ]]; then
  cmp -s "$temporary_archive" "$archive_path" || {
    printf 'script_88_application_package=blocked;reason=archive_identity_conflict\n' >&2
    exit 1
  }
else
  candidate="$(mktemp "$OUTPUT_ROOT/.application-package.XXXXXX")"
  cp -- "$temporary_archive" "$candidate"
  mv -- "$candidate" "$archive_path"
fi
printf '%s  %s\n' "$archive_sha256" "$archive_name" >"$archive_checksum"
if [[ -e "$qualification_path" ]]; then
  cmp -s "$work_root/qualification.json" "$qualification_path" || {
    printf 'script_88_application_package=blocked;reason=qualification_identity_conflict\n' >&2
    exit 1
  }
else
  cp -- "$work_root/qualification.json" "$qualification_path"
fi
printf '%s  %s\n' "$qualification_sha256" "$(basename -- "$qualification_path")" >"$qualification_checksum"
if [[ -e "$coding_standard_path" ]]; then
  cmp -s "$coding_standard_result" "$coding_standard_path" || {
    printf 'script_88_application_package=blocked;reason=coding_standard_receipt_identity_conflict\n' >&2
    exit 1
  }
else
  cp -- "$coding_standard_result" "$coding_standard_path"
fi
printf '%s  %s\n' "$coding_standard_result_sha256" "$(basename -- "$coding_standard_path")" >"$coding_standard_checksum"
(cd "$OUTPUT_ROOT" && sha256sum --check --strict "$(basename -- "$archive_checksum")" "$(basename -- "$qualification_checksum")" "$(basename -- "$coding_standard_checksum")" >/dev/null) || {
  printf 'script_88_application_package=blocked;reason=retained_checksum_failure\n' >&2
  exit 1
}

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/application_package_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=assemble_portable_ishikawa_application_package'
emit "started_utc=$timestamp"
emit "script_sha256=$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}');installer_sha256=$(sha256sum "$PACKAGING_ROOT/install-ishikawa" | awk '{print $1}')"
emit "accepted_script_87_report_sha256=$ACCEPTED_SCRIPT_87_REPORT_SHA256;accepted_script_87_artifact_sha256=$ACCEPTED_SCRIPT_87_ARTIFACT_SHA256"
emit 'authorized_actions=read_checksum_bound_sources_run_local_tests_assemble_deterministic_package_test_fresh_local_install_retain_content_free_package_evidence'
emit 'non_actions=no_target_contact_no_database_or_service_change_no_model_call_no_credential_read_no_source_document_or_vector_inclusion_no_package_install_on_target'
emit "archive=$archive_path;archive_sha256=$archive_sha256;archive_bytes=$archive_bytes"
emit "archive_checksum=$archive_checksum;bundle_file_count=$bundle_file_count;python_file_count=$python_file_count"
emit "qualification=$qualification_path;qualification_sha256=$qualification_sha256;qualification_bytes=$qualification_bytes;qualification_checksum=$qualification_checksum"
emit "coding_standard_sha256=$coding_standard_sha256;coding_standard_receipt=$coding_standard_path;coding_standard_receipt_sha256=$coding_standard_result_sha256;coding_standard_receipt_bytes=$coding_standard_result_bytes;coding_standard_receipt_checksum=$coding_standard_checksum"
emit 'coding_standard_compliant=true;coding_standard_findings=0'
emit 'deterministic_archive=true;internal_checksums=pass;fresh_installation=pass'
emit 'repository_references=false;secret_material=false;source_documents_included=false'
emit 'target_contact=false;database_changed=false;service_changed=false;model_contact=false'
emit 'local_tests=319;failures=0;errors=0'
emit "script_88_application_package=pass;local_report=$report_path;next_gate=install_and_qualify_application_package_on_emceedanko"
chmod 0600 "$report_path" 2>/dev/null || true
