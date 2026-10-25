#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Assemble the single final-state Ishikawa v1 application-and-database
#   deployment package from the accepted corrected component packages.
#
# Mental model:
#   Bind the accepted database qualification, runtime correction, and complete
#   runtime proof; expand only the two final component packages; add one neutral
#   package verifier; prove reproducibility, fresh application installation,
#   final-schema identity, and coding-standard compliance; retain one archive.
#
# Inputs or prerequisites:
#   Exact accepted application and database archives, their qualification
#   evidence, the accepted corrected runtime proof, and the coding standard.
#
# Outputs:
#   One deterministic Ishikawa v1 deployment archive, checksum, qualification
#   receipt, coding-standard receipt, and content-free local report.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/107_assemble_ishikawa_v1_deployment_package.sh --run

usage() {
  sed -n '3,24p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Assemble, validate, and retain the deployment package.' \
    '  --validate-only Run the same qualification without retaining outputs.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly DEPLOYMENT_SOURCE="$PHASE_ROOT/Ishikawa/packaging/deployment"
readonly PACKAGE_README="$DEPLOYMENT_SOURCE/README.md"
readonly PACKAGE_VERIFIER="$DEPLOYMENT_SOURCE/verify-ishikawa-v1"
readonly CODING_STANDARD="$REPO_ROOT/CODING_STANDARD.md"
readonly CODING_STANDARD_EVALUATOR="$SCRIPT_DIR/evaluate_consolidated_build_coding_standard.py"
readonly APPLICATION_ARCHIVE="$REPO_ROOT/local/artifacts/ishikawa/final-application-package/ishikawa-application-package-bb3eb2c33e6380d0.tar.gz"
readonly APPLICATION_CHECKSUM="$APPLICATION_ARCHIVE.sha256"
readonly DATABASE_ARCHIVE="$REPO_ROOT/local/artifacts/ishikawa/database-schema-package/ishikawa-database-schema-package-0402fdff8f886129.tar.gz"
readonly DATABASE_CHECKSUM="$DATABASE_ARCHIVE.sha256"
readonly DATABASE_REPORT="$REPO_ROOT/local/reports/ishikawa-database-schema-qualification/database_schema_qualification_20261020T234958Z_VAT4I9.txt"
readonly DATABASE_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/database-schema-qualification/database_schema_qualification_20261020T234958Z.json"
readonly DATABASE_ARTIFACT_CHECKSUM="$DATABASE_ARTIFACT.sha256"
readonly PROMOTION_REPORT="$REPO_ROOT/local/reports/ishikawa-runtime-candidate-promotion/runtime_candidate_promotion_20261021T040140Z_ovnNdq.txt"
readonly PROMOTION_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/runtime-candidate-promotion/runtime_candidate_promotion_20261021T040140Z.json"
readonly PROMOTION_ARTIFACT_CHECKSUM="$PROMOTION_ARTIFACT.sha256"
readonly RUNTIME_REPORT="$REPO_ROOT/local/reports/ishikawa-first-runtime-proof/first_runtime_proof_20261021T040535Z_0NNzcY.txt"
readonly RUNTIME_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/first-runtime-proof/first_runtime_proof_qualification_20261021T040535Z.json"
readonly RUNTIME_ARTIFACT_CHECKSUM="$RUNTIME_ARTIFACT.sha256"
readonly APPLICATION_ARCHIVE_SHA256='bb3eb2c33e6380d04e32fa474a7592260604d2ccef0c3cdb9181db116965e1b0'
readonly APPLICATION_CHECKSUM_SHA256='8c50398e4f2f8c3088016a748c528da92031dcd3673b70aae3f86cb754e8c898'
readonly DATABASE_ARCHIVE_SHA256='0402fdff8f886129ffc6cdc688250c7e196e843b01b180a324ae7864ceeba710'
readonly DATABASE_CHECKSUM_SHA256='777d0baf8887a355e65a68bded2fcc00f93c04eabe46dd54ef2f7d6d31c4aa9a'
readonly DATABASE_REPORT_SHA256='27dd70ab765fe645f94677396f95f77c58f45607a185d90ecd54b48465cc18f1'
readonly DATABASE_ARTIFACT_SHA256='e200fdf5f6e26f4fd94d655880032f76cb5f5ea5e1894de57e718fa3fc13f6e8'
readonly DATABASE_ARTIFACT_CHECKSUM_SHA256='26c12e754ab845da837ba8cb519cfe7f28c3866d5bd77c2bc65ffd4530efd7a9'
readonly PROMOTION_REPORT_SHA256='adb9b987cc28a3c28291868c166b3afd83b5248a98f0aa57334167f3d6769615'
readonly PROMOTION_ARTIFACT_SHA256='9cca07bc3ec0e6929e7a6cb42850ea4b15199ec06d0e00181705290025f7c98f'
readonly PROMOTION_ARTIFACT_CHECKSUM_SHA256='0c702230ce3175daa65fd98e80a0f51c3428fb4fe663b702db83373ae56611c0'
readonly RUNTIME_REPORT_SHA256='fb04896d0f05a5106f6f23c16a83cdb2534dfac75afea5ff2a1dd2b90c821e46'
readonly RUNTIME_ARTIFACT_SHA256='c293581d40a07782b4656f6fc87937083769cd3ecdf85c2e678ec29da2caa8bd'
readonly RUNTIME_ARTIFACT_CHECKSUM_SHA256='9c959f39931f423f112beb8b91d0378e6d9732c277d6ced11fd0c7ebec4695ea'
readonly CORRECTED_MODULE_SHA256='8e64799a02b6c6f6833e19c29c8157602f94647009d25d78bb1e9be083ebb029'
readonly FINAL_SCHEMA_SHA256='5cfd397152b726aedc97be84d8a06fc8f21cad6e1a11563e5e9dd3a1f026d568'
readonly BUNDLE_NAME='ishikawa-v1-deployment-package'
readonly OUTPUT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v1-deployment-package"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1-deployment-package"
readonly FORBIDDEN_PATTERN='phase[-_ ]*[0-9]|org[-_ ]*lab|danko|agentdanko|dankorepos|prj[0-9]|codex|opencode|local/artifacts|/mnt/|\.git/|repository|script[[:space:]_-]*[0-9]+'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_107_v1_deployment_package=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_107_v1_deployment_package=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in awk bash basename cmp cp date find grep gzip install mkdir mktemp mv python3 rm sed sha256sum sort stat tar tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_107_v1_deployment_package=blocked;reason=local_command_missing\n' >&2
    exit 2
  }
done
required_files=(
  "$PACKAGE_README"
  "$PACKAGE_VERIFIER"
  "$CODING_STANDARD"
  "$CODING_STANDARD_EVALUATOR"
  "$APPLICATION_ARCHIVE"
  "$APPLICATION_CHECKSUM"
  "$DATABASE_ARCHIVE"
  "$DATABASE_CHECKSUM"
  "$DATABASE_REPORT"
  "$DATABASE_ARTIFACT"
  "$DATABASE_ARTIFACT_CHECKSUM"
  "$PROMOTION_REPORT"
  "$PROMOTION_ARTIFACT"
  "$PROMOTION_ARTIFACT_CHECKSUM"
  "$RUNTIME_REPORT"
  "$RUNTIME_ARTIFACT"
  "$RUNTIME_ARTIFACT_CHECKSUM"
)
for file in "${required_files[@]}"; do
  [[ -f "$file" && ! -L "$file" && -r "$file" ]] || {
    printf 'script_107_v1_deployment_package=blocked;reason=required_input_unsafe\n' >&2
    exit 2
  }
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_107_v1_deployment_package=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}
check_sha256 "$APPLICATION_ARCHIVE" "$APPLICATION_ARCHIVE_SHA256" application_archive
check_sha256 "$APPLICATION_CHECKSUM" "$APPLICATION_CHECKSUM_SHA256" application_checksum
check_sha256 "$DATABASE_ARCHIVE" "$DATABASE_ARCHIVE_SHA256" database_archive
check_sha256 "$DATABASE_CHECKSUM" "$DATABASE_CHECKSUM_SHA256" database_checksum
check_sha256 "$DATABASE_REPORT" "$DATABASE_REPORT_SHA256" database_report
check_sha256 "$DATABASE_ARTIFACT" "$DATABASE_ARTIFACT_SHA256" database_artifact
check_sha256 "$DATABASE_ARTIFACT_CHECKSUM" "$DATABASE_ARTIFACT_CHECKSUM_SHA256" database_artifact_checksum
check_sha256 "$PROMOTION_REPORT" "$PROMOTION_REPORT_SHA256" promotion_report
check_sha256 "$PROMOTION_ARTIFACT" "$PROMOTION_ARTIFACT_SHA256" promotion_artifact
check_sha256 "$PROMOTION_ARTIFACT_CHECKSUM" "$PROMOTION_ARTIFACT_CHECKSUM_SHA256" promotion_artifact_checksum
check_sha256 "$RUNTIME_REPORT" "$RUNTIME_REPORT_SHA256" runtime_report
check_sha256 "$RUNTIME_ARTIFACT" "$RUNTIME_ARTIFACT_SHA256" runtime_artifact
check_sha256 "$RUNTIME_ARTIFACT_CHECKSUM" "$RUNTIME_ARTIFACT_CHECKSUM_SHA256" runtime_artifact_checksum

for checksum in \
  "$APPLICATION_CHECKSUM" "$DATABASE_CHECKSUM" \
  "$DATABASE_ARTIFACT_CHECKSUM" "$PROMOTION_ARTIFACT_CHECKSUM" "$RUNTIME_ARTIFACT_CHECKSUM"; do
  (cd -- "$(dirname -- "$checksum")" && sha256sum --check --strict "$(basename -- "$checksum")" >/dev/null) || {
    printf 'script_107_v1_deployment_package=blocked;reason=accepted_checksum_failed\n' >&2
    exit 2
  }
done

for fact in \
  'database_schema_package_qualification=pass' \
  'catalog_equivalence=exact;tables=20;views=5;explicit_indexes=14;required_named_constraints=11' \
  'temporary_database_dropped=true;accepted_database_unchanged=true' \
  'script_91_database_schema_qualification=pass;'; do
  grep -Fq "$fact" "$DATABASE_REPORT" || {
    printf 'script_107_v1_deployment_package=blocked;reason=database_evidence_contract_failed\n' >&2
    exit 2
  }
done
for fact in \
  "new_archive_sha256=$APPLICATION_ARCHIVE_SHA256" \
  "module_identity=$CORRECTED_MODULE_SHA256;connection_autocommit=true;atomic_writer_boundary=explicit_transaction" \
  'operator_configuration=preserved;corpus=preserved;application_state=preserved;candidate_retained=true' \
  'ishikawa_runtime_candidate_promotion=pass' \
  'script_105_runtime_candidate_promotion=pass;'; do
  grep -Fq "$fact" "$PROMOTION_REPORT" || {
    printf 'script_107_v1_deployment_package=blocked;reason=promotion_evidence_contract_failed\n' >&2
    exit 2
  }
done
for fact in \
  '[INGEST] state=pass;action=published_new;documents=6;pages=27;chunks=126;citations=126;embeddings=126' \
  'runtime_path=nextjs_to_retrieval_to_postgresql_nomic_gemma;chat_status=answered;citation_closure=pass' \
  'stack_final_state=stopped;boot_enabled=false;forwarding_changed=false' \
  'ishikawa_first_runtime_proof=pass' \
  'script_104_first_runtime_proof=pass;'; do
  grep -Fq "$fact" "$RUNTIME_REPORT" || {
    printf 'script_107_v1_deployment_package=blocked;reason=runtime_evidence_contract_failed\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}" "$PACKAGE_VERIFIER"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
  "$CODING_STANDARD_EVALUATOR"

work_root="$(mktemp -d /tmp/ishikawa-script-107.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  [[ "$work_root" == /tmp/ishikawa-script-107.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p -- "$work_root/application-source" "$work_root/database-source"
tar -xzf "$APPLICATION_ARCHIVE" -C "$work_root/application-source"
tar -xzf "$DATABASE_ARCHIVE" -C "$work_root/database-source"
readonly application_source="$work_root/application-source/ishikawa-application-package"
readonly database_source="$work_root/database-source/ishikawa-database-schema-package"
for directory in "$application_source" "$database_source"; do
  [[ -d "$directory" && ! -L "$directory" ]] || {
    printf 'script_107_v1_deployment_package=blocked;reason=component_root_invalid\n' >&2
    exit 1
  }
  (cd -- "$directory" && sha256sum --check --strict SHA256SUMS >/dev/null) || {
    printf 'script_107_v1_deployment_package=blocked;reason=component_checksum_failed\n' >&2
    exit 1
  }
done
check_sha256 "$application_source/payload/application/python/ishikawa/ingestion_runtime.py" "$CORRECTED_MODULE_SHA256" corrected_module
check_sha256 "$database_source/schema.sql" "$FINAL_SCHEMA_SHA256" final_schema

assemble_bundle() {
  local destination="$1"
  local bundle="$destination/$BUNDLE_NAME"
  install -d -m 0755 -- "$bundle/application" "$bundle/database"
  cp -a -- "$application_source/." "$bundle/application/"
  cp -a -- "$database_source/." "$bundle/database/"
  install -m 0644 -- "$PACKAGE_README" "$bundle/README.md"
  install -m 0755 -- "$PACKAGE_VERIFIER" "$bundle/verify-ishikawa-v1"
  (
    cd -- "$bundle"
    while IFS= read -r name; do sha256sum "$name"; done < <(
      find . -type f ! -path './SHA256SUMS' -printf '%P\n' | sort
    ) >SHA256SUMS
  )
}

mkdir -p -- "$work_root/build-a" "$work_root/build-b"
assemble_bundle "$work_root/build-a"
assemble_bundle "$work_root/build-b"
readonly bundle_a="$work_root/build-a/$BUNDLE_NAME"
readonly bundle_b="$work_root/build-b/$BUNDLE_NAME"

for bundle in "$bundle_a" "$bundle_b"; do
  bash "$bundle/verify-ishikawa-v1" | grep -Fxq \
    'ishikawa_v1_verification=pass;application=final;database_schema=version_4;historical_mutation_files=0' || {
      printf 'script_107_v1_deployment_package=blocked;reason=package_verification_failed\n' >&2
      exit 1
    }
  find "$bundle" -type l -print -quit | grep -q . && {
    printf 'script_107_v1_deployment_package=blocked;reason=package_symlink_found\n' >&2
    exit 1
  }
  if find "$bundle" -type f \( -name '*.pyc' -o -name '*.pyo' \) -print -quit | grep -q . \
    || find "$bundle" -type d -name __pycache__ -print -quit | grep -q .; then
    printf 'script_107_v1_deployment_package=blocked;reason=generated_python_file_found\n' >&2
    exit 1
  fi
  if find "$bundle" -type f \( -iname '*migration*' -o -iname '*mutation*' -o -iname '*patch*' -o -iname '*repair*' \) -print -quit | grep -q .; then
    printf 'script_107_v1_deployment_package=blocked;reason=historical_mutation_file_found\n' >&2
    exit 1
  fi
  if grep -ERiq -- "$FORBIDDEN_PATTERN" "$bundle"; then
    printf 'script_107_v1_deployment_package=blocked;reason=development_jargon_found\n' >&2
    exit 1
  fi
  if grep -ERq -- 'BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY|Authorization:[[:space:]]*Bearer[[:space:]]+[^$]' "$bundle"; then
    printf 'script_107_v1_deployment_package=blocked;reason=credential_material_found\n' >&2
    exit 1
  fi
done

if ! cmp -s \
  <(cd -- "$bundle_a" && find . -type f -printf '%P\n' | sort | while IFS= read -r name; do sha256sum "$name"; done) \
  <(cd -- "$bundle_b" && find . -type f -printf '%P\n' | sort | while IFS= read -r name; do sha256sum "$name"; done); then
  printf 'script_107_v1_deployment_package=blocked;reason=bundle_not_reproducible\n' >&2
  exit 1
fi

coding_standard_result="$work_root/coding-standard.json"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$CODING_STANDARD_EVALUATOR" \
  --bundle-root "$bundle_a" \
  --standard "$CODING_STANDARD" \
  --output "$coding_standard_result" >/dev/null || {
    printf 'script_107_v1_deployment_package=blocked;reason=coding_standard_noncompliance\n' >&2
    exit 1
  }

install_root="$work_root/fresh-install/Ishikawa"
bash "$bundle_a/application/install-ishikawa" --install-root "$install_root" >"$work_root/application-install.txt"
grep -Fq 'ishikawa_install=pass;' "$work_root/application-install.txt" || {
  printf 'script_107_v1_deployment_package=blocked;reason=fresh_application_install_failed\n' >&2
  exit 1
}
check_sha256 "$install_root/application/python/ishikawa/ingestion_runtime.py" "$CORRECTED_MODULE_SHA256" installed_corrected_module
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
bash "$extracted_bundle/verify-ishikawa-v1" >/dev/null || {
  printf 'script_107_v1_deployment_package=blocked;reason=extracted_package_verification_failed\n' >&2
  exit 1
}

archive_sha256="$(sha256sum "$temporary_archive" | awk '{print $1}')"
archive_bytes="$(stat -c '%s' "$temporary_archive")"
package_file_count="$(find "$extracted_bundle" -type f | awk 'END {print NR+0}')"
application_file_count="$(find "$extracted_bundle/application" -type f | awk 'END {print NR+0}')"
database_file_count="$(find "$extracted_bundle/database" -type f | awk 'END {print NR+0}')"
coding_standard_sha256="$(sha256sum "$CODING_STANDARD" | awk '{print $1}')"
coding_standard_result_sha256="$(sha256sum "$coding_standard_result" | awk '{print $1}')"
printf '{"application_archive_sha256":"%s","application_file_count":%s,"archive_bytes":%s,"archive_sha256":"%s","coding_standard_compliant":true,"database_archive_sha256":"%s","database_file_count":%s,"final_schema_version":4,"fresh_application_install":true,"historical_mutation_files":0,"model_contact":false,"package_file_count":%s,"receipt_schema_version":1,"repository_references":false,"runtime_proof":"pass","secret_material":false,"source_documents_included":false,"target_contact":false}\n' \
  "$APPLICATION_ARCHIVE_SHA256" "$application_file_count" "$archive_bytes" "$archive_sha256" \
  "$DATABASE_ARCHIVE_SHA256" "$database_file_count" "$package_file_count" >"$work_root/qualification.json"
qualification_sha256="$(sha256sum "$work_root/qualification.json" | awk '{print $1}')"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_single_ishikawa_v1_deployment_package' \
    "archive_sha256=$archive_sha256;archive_bytes=$archive_bytes;package_file_count=$package_file_count" \
    "application_archive_sha256=$APPLICATION_ARCHIVE_SHA256;application_file_count=$application_file_count;corrected_module_sha256=$CORRECTED_MODULE_SHA256" \
    "database_archive_sha256=$DATABASE_ARCHIVE_SHA256;database_file_count=$database_file_count;schema_version=4;schema_sha256=$FINAL_SCHEMA_SHA256" \
    "coding_standard_sha256=$coding_standard_sha256;coding_standard_result_sha256=$coding_standard_result_sha256" \
    'runtime_proof=pass;internal_checksums=pass;deterministic_archive=true;fresh_application_install=pass' \
    'historical_mutation_files=0;repository_references=false;secret_material=false;source_documents_included=false' \
    'target_contact=false;database_changed=false;service_changed=false;model_contact=false' \
    'script_107_v1_deployment_package_source=pass'
  exit 0
fi

mkdir -p -- "$OUTPUT_ROOT" "$REPORT_ROOT"
archive_name="$BUNDLE_NAME-${archive_sha256:0:16}.tar.gz"
archive_path="$OUTPUT_ROOT/$archive_name"
archive_checksum="$archive_path.sha256"
qualification_path="$OUTPUT_ROOT/v1_deployment_package_qualification_${archive_sha256:0:16}.json"
qualification_checksum="$qualification_path.sha256"
coding_standard_path="$OUTPUT_ROOT/v1_deployment_coding_standard_${archive_sha256:0:16}.json"
coding_standard_checksum="$coding_standard_path.sha256"

retain_exact() {
  local source="$1" destination="$2" conflict_reason="$3"
  [[ ! -L "$destination" ]] || {
    printf 'script_107_v1_deployment_package=blocked;reason=output_symlink_found\n' >&2
    exit 1
  }
  if [[ -e "$destination" ]]; then
    cmp -s "$source" "$destination" || {
      printf 'script_107_v1_deployment_package=blocked;reason=%s\n' "$conflict_reason" >&2
      exit 1
    }
  else
    cp -- "$source" "$destination"
  fi
}

retain_exact "$temporary_archive" "$archive_path" archive_identity_conflict
printf '%s  %s\n' "$archive_sha256" "$archive_name" >"$work_root/archive.sha256"
retain_exact "$work_root/archive.sha256" "$archive_checksum" archive_checksum_conflict
retain_exact "$work_root/qualification.json" "$qualification_path" qualification_identity_conflict
printf '%s  %s\n' "$qualification_sha256" "$(basename -- "$qualification_path")" >"$work_root/qualification.sha256"
retain_exact "$work_root/qualification.sha256" "$qualification_checksum" qualification_checksum_conflict
retain_exact "$coding_standard_result" "$coding_standard_path" coding_standard_identity_conflict
printf '%s  %s\n' "$coding_standard_result_sha256" "$(basename -- "$coding_standard_path")" >"$work_root/coding-standard.sha256"
retain_exact "$work_root/coding-standard.sha256" "$coding_standard_checksum" coding_standard_checksum_conflict

(cd -- "$OUTPUT_ROOT" && sha256sum --check --strict "$(basename -- "$archive_checksum")" >/dev/null)
(cd -- "$OUTPUT_ROOT" && sha256sum --check --strict "$(basename -- "$qualification_checksum")" >/dev/null)
(cd -- "$OUTPUT_ROOT" && sha256sum --check --strict "$(basename -- "$coding_standard_checksum")" >/dev/null)

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/v1_deployment_package_${timestamp}_XXXXXX.txt")"
{
  printf 'purpose=assemble_single_ishikawa_v1_deployment_package\n'
  printf 'started_utc=%s\n' "$timestamp"
  printf 'application_archive_sha256=%s;corrected_module_sha256=%s\n' "$APPLICATION_ARCHIVE_SHA256" "$CORRECTED_MODULE_SHA256"
  printf 'database_archive_sha256=%s;schema_version=4;schema_sha256=%s\n' "$DATABASE_ARCHIVE_SHA256" "$FINAL_SCHEMA_SHA256"
  printf 'accepted_runtime_promotion_report_sha256=%s;accepted_runtime_proof_report_sha256=%s\n' "$PROMOTION_REPORT_SHA256" "$RUNTIME_REPORT_SHA256"
  printf 'archive=%s;archive_sha256=%s;archive_bytes=%s;package_file_count=%s\n' "$archive_path" "$archive_sha256" "$archive_bytes" "$package_file_count"
  printf 'application_file_count=%s;database_file_count=%s;component_checksums=pass;outer_checksums=pass\n' "$application_file_count" "$database_file_count"
  printf 'coding_standard_sha256=%s;coding_standard_receipt_sha256=%s;coding_standard_compliant=true\n' "$coding_standard_sha256" "$coding_standard_result_sha256"
  printf 'runtime_proof=pass;deterministic_archive=true;fresh_application_install=pass;historical_mutation_files=0\n'
  printf 'repository_references=false;secret_material=false;source_documents_included=false;target_contact=false\n'
  printf 'accepted_artifact=%s;accepted_artifact_sha256=%s;accepted_checksum=%s\n' "$qualification_path" "$qualification_sha256" "$qualification_checksum"
  printf 'script_107_v1_deployment_package=pass;next_gate=qualify_fresh_v1_installation_on_application_host\n'
} | tee "$report_path"
chmod 0600 "$report_path" 2>/dev/null || true
