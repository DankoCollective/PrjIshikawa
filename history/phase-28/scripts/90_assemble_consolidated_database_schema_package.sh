#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Assemble and locally qualify the deterministic final-state Ishikawa
#   database schema package without contacting a persistent or remote target.
#
# Mental model:
#   Bind accepted application-install evidence and the four development schema
#   ancestors, validate one canonical version-4 schema, package only that final
#   schema plus its installer and documentation, and prove reproducibility.
#
# Inputs or prerequisites:
#   Accepted Script 89 evidence, the exact accepted schema ancestors, the
#   canonical schema sources, CODING_STANDARD.md, Python 3, and GNU archives.
#
# Outputs:
#   A deterministic fresh-install database archive, checksums, and content-free
#   local receipts. SQL runs only in a throw-away local PostgreSQL cluster.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/90_assemble_consolidated_database_schema_package.sh --run

usage() {
  sed -n '3,22p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Assemble, validate, and retain the package.' \
    '  --validate-only Assemble and validate without retaining outputs.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PACKAGE_SOURCE="$PHASE_ROOT/Ishikawa/packaging/database"
readonly SCHEMA_SOURCE="$PACKAGE_SOURCE/schema.sql"
readonly INSTALLER_SOURCE="$PACKAGE_SOURCE/install-schema"
readonly README_SOURCE="$PACKAGE_SOURCE/README.md"
readonly SCHEMA_EVALUATOR="$SCRIPT_DIR/evaluate_consolidated_database_schema.py"
readonly CATALOG_EQUIVALENCE_TEST="$SCRIPT_DIR/tests/test_consolidated_database_schema.sh"
readonly CODING_STANDARD="$REPO_ROOT/CODING_STANDARD.md"
readonly CODING_STANDARD_EVALUATOR="$SCRIPT_DIR/evaluate_consolidated_build_coding_standard.py"
readonly BUNDLE_NAME='ishikawa-database-schema-package'
readonly ACCEPTED_REPORT="$REPO_ROOT/local/reports/ishikawa-application-installation/application_installation_20261020T233047Z_PirFSA.txt"
readonly ACCEPTED_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/application-installation/application_installation_qualification_20261020T233047Z.json"
readonly ACCEPTED_CHECKSUM="$ACCEPTED_ARTIFACT.sha256"
readonly ACCEPTED_REPORT_SHA256='21a1cff79f59c32a7713ffd342fc812fcb82c73529d8c8c9869365a1911d75b9'
readonly ACCEPTED_ARTIFACT_SHA256='0c64ce985ee21299c41f9b32d963fcc8b48e74f15a4b3d657c1b74b3dbb15a14'
readonly ACCEPTED_CHECKSUM_SHA256='2982ec1718eeaf95fa89ad8b9b854f2a0439a47015e67c51755db24a38c394fe'
readonly -a ANCESTOR_PATHS=(
  "$PHASE_ROOT/migrations/0001_initial_rag_catalog.sql"
  "$PHASE_ROOT/migrations/0002_align_ingestion_ownership.sql"
  "$PHASE_ROOT/migrations/0003_separate_special_token_count.sql"
  "$PHASE_ROOT/migrations/0004_preserve_relationship_override_audit.sql"
)
readonly -a ANCESTOR_SHA256=(
  '3e2f5e61bd8038bc29764024e21b8bec754fad8a282f89abaf6130e345d6380a'
  '74b08adb8aac9828ac076744fedfd22619751326c911bf17f1fa8690e01345e4'
  '5e833d8ff556c0e6158daf0419b1013235a11e1a94f1f560206ba813e1fc3761'
  '5764f6e12a74b18747163c61ef3f314e8dff140a3586b298c62be616a1dc185f'
)
readonly OUTPUT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/database-schema-package"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-database-schema-package"
readonly FORBIDDEN_PATTERN='phase[-_ ]*[0-9]|org[-_ ]*lab|danko|agentdanko|dankorepos|prj[0-9]|codex|opencode|local/artifacts|/mnt/|\.git/'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_90_database_schema_package=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_90_database_schema_package=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in awk bash cmp cp createdb date find grep gzip install mkdir mktemp mv pg_dump pg_virtualenv psql python3 rm sed sha256sum stat tar tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_90_database_schema_package=blocked;reason=local_command_missing\n' >&2
    exit 2
  }
done
for required_file in \
  "$SCHEMA_SOURCE" "$INSTALLER_SOURCE" "$README_SOURCE" "$SCHEMA_EVALUATOR" "$CATALOG_EQUIVALENCE_TEST" \
  "$CODING_STANDARD" "$CODING_STANDARD_EVALUATOR" \
  "$ACCEPTED_REPORT" "$ACCEPTED_ARTIFACT" "$ACCEPTED_CHECKSUM" \
  "${ANCESTOR_PATHS[@]}"; do
  [[ -f "$required_file" && ! -L "$required_file" && -r "$required_file" ]] || {
    printf 'script_90_database_schema_package=blocked;reason=required_input_unsafe\n' >&2
    exit 2
  }
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_90_database_schema_package=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}
check_sha256 "$ACCEPTED_REPORT" "$ACCEPTED_REPORT_SHA256" 'accepted_report'
check_sha256 "$ACCEPTED_ARTIFACT" "$ACCEPTED_ARTIFACT_SHA256" 'accepted_artifact'
check_sha256 "$ACCEPTED_CHECKSUM" "$ACCEPTED_CHECKSUM_SHA256" 'accepted_checksum'
(
  cd -- "$(dirname -- "$ACCEPTED_ARTIFACT")"
  sha256sum --check --strict "$(basename -- "$ACCEPTED_CHECKSUM")" >/dev/null
) || { printf 'script_90_database_schema_package=blocked;reason=accepted_artifact_checksum_failed\n' >&2; exit 2; }
for fact in \
  'current_coding_standard_compliance=pass;historical_migration_or_mutation_files=0' \
  'ishikawa_application_install_qualification=pass' \
  'script_89_application_installation=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_REPORT" || {
    printf 'script_90_database_schema_package=blocked;reason=accepted_report_contract_failed\n' >&2
    exit 2
  }
done
for ancestor_index in "${!ANCESTOR_PATHS[@]}"; do
  check_sha256 \
    "${ANCESTOR_PATHS[$ancestor_index]}" \
    "${ANCESTOR_SHA256[$ancestor_index]}" \
    "schema_ancestor_$ancestor_index"
done

bash -n "${BASH_SOURCE[0]}" "$INSTALLER_SOURCE" "$CATALOG_EQUIVALENCE_TEST"
python3 -B -c 'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$SCHEMA_EVALUATOR" "$CODING_STANDARD_EVALUATOR"
bash "$INSTALLER_SOURCE" --help >/dev/null

work_root="$(mktemp -d /tmp/ishikawa-script-90.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$work_root" == /tmp/ishikawa-script-90.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

catalog_test_result="$work_root/catalog-equivalence.txt"
bash "$CATALOG_EQUIVALENCE_TEST" >"$catalog_test_result" 2>&1 || {
  printf 'script_90_database_schema_package=blocked;reason=catalog_equivalence_test_failed;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$catalog_test_result" | awk '{print $1}')" \
    "$(stat -c '%s' "$catalog_test_result")" >&2
  exit 1
}
grep -Fxq \
  'consolidated_database_schema_test=pass;schema_version=4;catalog_equivalence=exact;ancestor_ledger_rows=4;consolidated_ledger_rows=1' \
  "$catalog_test_result" || {
  printf 'script_90_database_schema_package=blocked;reason=catalog_equivalence_pass_marker_absent\n' >&2
  exit 1
}

schema_validation="$work_root/schema-validation.json"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$SCHEMA_EVALUATOR" \
  --schema "$SCHEMA_SOURCE" \
  --output "$schema_validation" >/dev/null || {
  printf 'script_90_database_schema_package=blocked;reason=canonical_schema_validation_failed\n' >&2
  exit 1
}

assemble_bundle() {
  local destination="$1"
  local bundle="$destination/$BUNDLE_NAME"
  install -d -m 0755 -- "$bundle"
  install -m 0644 -- "$README_SOURCE" "$bundle/README.md"
  install -m 0755 -- "$INSTALLER_SOURCE" "$bundle/install-schema"
  install -m 0644 -- "$SCHEMA_SOURCE" "$bundle/schema.sql"
  (
    cd -- "$bundle"
    while IFS= read -r path; do
      sha256sum "$path"
    done < <(find . -type f ! -name SHA256SUMS -printf '%P\n' | sort) >SHA256SUMS
  )
}

mkdir -p -- "$work_root/build-a" "$work_root/build-b"
assemble_bundle "$work_root/build-a"
assemble_bundle "$work_root/build-b"

for bundle in "$work_root/build-a/$BUNDLE_NAME" "$work_root/build-b/$BUNDLE_NAME"; do
  (
    cd -- "$bundle"
    sha256sum --check --strict SHA256SUMS >/dev/null
  ) || { printf 'script_90_database_schema_package=blocked;reason=internal_checksum_failure\n' >&2; exit 1; }
  if find "$bundle" -type l -print -quit | grep -q .; then
    printf 'script_90_database_schema_package=blocked;reason=package_symlink_found\n' >&2
    exit 1
  fi
  if grep -ERiq -- "$FORBIDDEN_PATTERN" "$bundle"; then
    printf 'script_90_database_schema_package=blocked;reason=development_jargon_found\n' >&2
    exit 1
  fi
  if grep -ERq -- 'BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY|Authorization:[[:space:]]*Bearer[[:space:]]+[^$]' "$bundle"; then
    printf 'script_90_database_schema_package=blocked;reason=credential_material_found\n' >&2
    exit 1
  fi
done

coding_standard_result="$work_root/coding-standard.json"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$CODING_STANDARD_EVALUATOR" \
  --bundle-root "$work_root/build-a/$BUNDLE_NAME" \
  --standard "$CODING_STANDARD" \
  --output "$coding_standard_result" >/dev/null || {
  printf 'script_90_database_schema_package=blocked;reason=coding_standard_noncompliance\n' >&2
  exit 1
}

if ! cmp -s \
  <(cd "$work_root/build-a/$BUNDLE_NAME" && find . -type f -printf '%P\n' | sort | while IFS= read -r path; do sha256sum "$path"; done) \
  <(cd "$work_root/build-b/$BUNDLE_NAME" && find . -type f -printf '%P\n' | sort | while IFS= read -r path; do sha256sum "$path"; done); then
  printf 'script_90_database_schema_package=blocked;reason=bundle_not_reproducible\n' >&2
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
) || { printf 'script_90_database_schema_package=blocked;reason=extracted_checksum_failure\n' >&2; exit 1; }

archive_sha256="$(sha256sum "$temporary_archive" | awk '{print $1}')"
archive_bytes="$(stat -c '%s' "$temporary_archive")"
schema_sha256="$(sha256sum "$SCHEMA_SOURCE" | awk '{print $1}')"
schema_bytes="$(stat -c '%s' "$SCHEMA_SOURCE")"
schema_validation_sha256="$(sha256sum "$schema_validation" | awk '{print $1}')"
schema_validation_bytes="$(stat -c '%s' "$schema_validation")"
coding_standard_sha256="$(sha256sum "$CODING_STANDARD" | awk '{print $1}')"
coding_standard_result_sha256="$(sha256sum "$coding_standard_result" | awk '{print $1}')"
coding_standard_result_bytes="$(stat -c '%s' "$coding_standard_result")"
bundle_file_count="$(find "$extracted_bundle" -type f | awk 'END {print NR}')"

printf '{"archive_bytes":%s,"archive_sha256":"%s","canonical_final_schema":true,"catalog_equivalence":"exact","coding_standard_compliant":true,"historical_mutation_files":0,"local_disposable_database":true,"package_file_count":%s,"persistent_database_changed":false,"receipt_schema_version":1,"remote_target_contact":false,"schema_sha256":"%s","schema_version":4,"sql_execution_performed":true}\n' \
  "$archive_bytes" "$archive_sha256" "$bundle_file_count" "$schema_sha256" >"$work_root/qualification.json"
qualification_sha256="$(sha256sum "$work_root/qualification.json" | awk '{print $1}')"
qualification_bytes="$(stat -c '%s' "$work_root/qualification.json")"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_consolidated_database_schema_package' \
    "schema_sha256=$schema_sha256;schema_bytes=$schema_bytes;schema_version=4" \
    'canonical_final_schema=true;tables=20;indexes=14;views=5;baseline_rows=1' \
    'catalog_equivalence=exact;ancestor_ledger_rows=4;consolidated_ledger_rows=1' \
    "archive_sha256=$archive_sha256;archive_bytes=$archive_bytes;package_file_count=$bundle_file_count" \
    "coding_standard_sha256=$coding_standard_sha256;coding_standard_result_sha256=$coding_standard_result_sha256;coding_standard_result_bytes=$coding_standard_result_bytes" \
    'historical_mutation_files=0;internal_checksums=pass;deterministic_archive=true' \
    'target_contact=false;local_disposable_database=true;sql_execution_performed=true;persistent_database_changed=false' \
    'script_90_database_schema_package_source=pass'
  exit 0
fi

mkdir -p -- "$OUTPUT_ROOT" "$REPORT_ROOT"
archive_name="$BUNDLE_NAME-${archive_sha256:0:16}.tar.gz"
archive_path="$OUTPUT_ROOT/$archive_name"
archive_checksum="$archive_path.sha256"
qualification_path="$OUTPUT_ROOT/database_schema_package_qualification_${archive_sha256:0:16}.json"
qualification_checksum="$qualification_path.sha256"
schema_validation_path="$OUTPUT_ROOT/database_schema_validation_${archive_sha256:0:16}.json"
schema_validation_checksum="$schema_validation_path.sha256"
coding_standard_path="$OUTPUT_ROOT/database_schema_coding_standard_${archive_sha256:0:16}.json"
coding_standard_checksum="$coding_standard_path.sha256"

retain_exact() {
  local source="$1" destination="$2" conflict_reason="$3"
  [[ ! -L "$destination" ]] || {
    printf 'script_90_database_schema_package=blocked;reason=output_symlink_found\n' >&2
    exit 1
  }
  if [[ -e "$destination" ]]; then
    cmp -s "$source" "$destination" || {
      printf 'script_90_database_schema_package=blocked;reason=%s\n' "$conflict_reason" >&2
      exit 1
    }
  else
    local candidate
    candidate="$(mktemp "$OUTPUT_ROOT/.database-schema.XXXXXX")"
    cp -- "$source" "$candidate"
    mv -- "$candidate" "$destination"
  fi
}

retain_exact "$temporary_archive" "$archive_path" 'archive_identity_conflict'
retain_exact "$work_root/qualification.json" "$qualification_path" 'qualification_identity_conflict'
retain_exact "$schema_validation" "$schema_validation_path" 'schema_validation_identity_conflict'
retain_exact "$coding_standard_result" "$coding_standard_path" 'coding_standard_identity_conflict'
printf '%s  %s\n' "$archive_sha256" "$archive_name" >"$work_root/archive.sha256"
printf '%s  %s\n' "$qualification_sha256" "$(basename -- "$qualification_path")" >"$work_root/qualification.sha256"
printf '%s  %s\n' "$schema_validation_sha256" "$(basename -- "$schema_validation_path")" >"$work_root/schema-validation.sha256"
printf '%s  %s\n' "$coding_standard_result_sha256" "$(basename -- "$coding_standard_path")" >"$work_root/coding-standard.sha256"
retain_exact "$work_root/archive.sha256" "$archive_checksum" 'archive_checksum_identity_conflict'
retain_exact "$work_root/qualification.sha256" "$qualification_checksum" 'qualification_checksum_identity_conflict'
retain_exact "$work_root/schema-validation.sha256" "$schema_validation_checksum" 'schema_validation_checksum_identity_conflict'
retain_exact "$work_root/coding-standard.sha256" "$coding_standard_checksum" 'coding_standard_checksum_identity_conflict'
(
  cd -- "$OUTPUT_ROOT"
  sha256sum --check --strict \
    "$(basename -- "$archive_checksum")" \
    "$(basename -- "$qualification_checksum")" \
    "$(basename -- "$schema_validation_checksum")" \
    "$(basename -- "$coding_standard_checksum")" >/dev/null
) || { printf 'script_90_database_schema_package=blocked;reason=retained_checksum_failure\n' >&2; exit 1; }

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/database_schema_package_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=assemble_consolidated_database_schema_package'
emit "started_utc=$timestamp"
emit "script_sha256=$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}');schema_evaluator_sha256=$(sha256sum "$SCHEMA_EVALUATOR" | awk '{print $1}')"
emit "accepted_script_89_report_sha256=$ACCEPTED_REPORT_SHA256;accepted_script_89_artifact_sha256=$ACCEPTED_ARTIFACT_SHA256"
emit "schema_ancestor_count=4;schema_ancestor_1_sha256=${ANCESTOR_SHA256[0]};schema_ancestor_2_sha256=${ANCESTOR_SHA256[1]};schema_ancestor_3_sha256=${ANCESTOR_SHA256[2]};schema_ancestor_4_sha256=${ANCESTOR_SHA256[3]}"
emit 'authorized_actions=read_checksum_bound_sources_validate_final_schema_assemble_deterministic_package_retain_content_free_package_evidence'
emit 'non_actions=no_target_contact_no_persistent_database_or_service_change_no_model_call_no_credential_read_no_source_document_or_vector_inclusion'
emit "schema_sha256=$schema_sha256;schema_bytes=$schema_bytes;schema_version=4"
emit 'canonical_final_schema=true;tables=20;indexes=14;views=5;baseline_rows=1'
emit 'catalog_equivalence=exact;ancestor_ledger_rows=4;consolidated_ledger_rows=1'
emit "archive=$archive_path;archive_sha256=$archive_sha256;archive_bytes=$archive_bytes;package_file_count=$bundle_file_count"
emit "archive_checksum=$archive_checksum;qualification=$qualification_path;qualification_sha256=$qualification_sha256;qualification_bytes=$qualification_bytes;qualification_checksum=$qualification_checksum"
emit "schema_validation=$schema_validation_path;schema_validation_sha256=$schema_validation_sha256;schema_validation_bytes=$schema_validation_bytes;schema_validation_checksum=$schema_validation_checksum"
emit "coding_standard_sha256=$coding_standard_sha256;coding_standard_receipt=$coding_standard_path;coding_standard_receipt_sha256=$coding_standard_result_sha256;coding_standard_receipt_bytes=$coding_standard_result_bytes;coding_standard_receipt_checksum=$coding_standard_checksum"
emit 'coding_standard_compliant=true;coding_standard_findings=0;historical_mutation_files=0'
emit 'internal_checksums=pass;deterministic_archive=true;repository_references=false;secret_material=false'
emit 'target_contact=false;local_disposable_database=true;sql_execution_performed=true;persistent_database_changed=false;service_changed=false;model_contact=false'
emit "script_90_database_schema_package=pass;local_report=$report_path;next_gate=qualify_final_schema_in_disposable_database_on_emceedanko"
chmod 0600 "$report_path" 2>/dev/null || true
