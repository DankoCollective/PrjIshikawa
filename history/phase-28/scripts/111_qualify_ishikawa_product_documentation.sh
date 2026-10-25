#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify Ishikawa's portable operator, command, definition, design,
#   architecture, and method documentation against the accepted application.
#
# Mental model:
#   Bind the accepted prerequisite-kit gate, rerun the native regression suite,
#   compare every documented runtime and method fact with live source
#   configuration, and retain one content-free receipt. Do not rebuild the
#   already accepted release in this gate.
#
# Inputs or prerequisites:
#   Clean Script 110 evidence and the six reviewed product documents.
#
# Outputs:
#   One checksum-bound documentation qualification receipt and local report.
#   No target, service, database, container, model, credential, or package is
#   contacted or changed.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/111_qualify_ishikawa_product_documentation.sh --run

usage() {
  sed -n '3,21p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Validate and retain the documentation receipt.' \
    '  --validate-only Validate the same source without retaining outputs.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly DOCS_ROOT="$ISHIKAWA_ROOT/docs"
readonly CONFIG_ROOT="$ISHIKAWA_ROOT/config/templates"
readonly COMMAND_ROOT="$ISHIKAWA_ROOT/scripts"
readonly PYTHON_ROOT="$ISHIKAWA_ROOT/application/python"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_ishikawa_documentation.py"
readonly ACCEPTED_REPORT="$REPO_ROOT/local/reports/ishikawa-native-prerequisite-inventory-kit/native_prerequisite_inventory_kit_20261021T043024Z_C5dlhj.txt"
readonly ACCEPTED_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/native-prerequisite-inventory-kit/native_prerequisite_inventory_kit_qualification_bbca7aa5c4325308.json"
readonly ACCEPTED_CHECKSUM="$ACCEPTED_ARTIFACT.sha256"
readonly ACCEPTED_REPORT_SHA256='62288f5af045f91dc075234a0bba855c32488748529386451751c61f3fd91539'
readonly ACCEPTED_ARTIFACT_SHA256='a3e4f73d282ce591191788dde646ea76a436c40a00fa47185ab46a6470320306'
readonly ACCEPTED_CHECKSUM_SHA256='6c2d5e0913afae94446c56b0874d1c7ae566e394a8decb7c2e5043f1afe9acb2'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-product-documentation"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/product-documentation"
readonly -a DOCUMENTS=(
  "$DOCS_ROOT/APPLICATION_DEFINITION.md"
  "$DOCS_ROOT/APPLICATION_DESIGN.md"
  "$DOCS_ROOT/ARCHITECTURE.md"
  "$DOCS_ROOT/CHUNKING_INGESTION_RETRIEVAL.md"
  "$DOCS_ROOT/COMMAND_SHEET.md"
  "$DOCS_ROOT/OPERATOR_GUIDE.md"
)

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_111_product_documentation=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_111_product_documentation=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required_command in awk bash basename chmod cp date dirname grep mkdir mktemp python3 rm sed sha256sum stat tee; do
  command -v "$required_command" >/dev/null 2>&1 || {
    printf 'script_111_product_documentation=blocked;reason=local_command_missing\n' >&2
    exit 2
  }
done
readonly -a REQUIRED_FILES=(
  "$TEST_RUNNER" "$EVALUATOR"
  "$ACCEPTED_REPORT" "$ACCEPTED_ARTIFACT" "$ACCEPTED_CHECKSUM"
  "${DOCUMENTS[@]}"
)
for required_file in "${REQUIRED_FILES[@]}"; do
  [[ -f "$required_file" && ! -L "$required_file" && -r "$required_file" ]] || {
    printf 'script_111_product_documentation=blocked;reason=required_input_unsafe\n' >&2
    exit 2
  }
done

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_111_product_documentation=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}
check_sha256 "$ACCEPTED_REPORT" "$ACCEPTED_REPORT_SHA256" accepted_report
check_sha256 "$ACCEPTED_ARTIFACT" "$ACCEPTED_ARTIFACT_SHA256" accepted_artifact
check_sha256 "$ACCEPTED_CHECKSUM" "$ACCEPTED_CHECKSUM_SHA256" accepted_checksum
(
  cd -- "$(dirname -- "$ACCEPTED_CHECKSUM")"
  sha256sum --check --strict "$(basename -- "$ACCEPTED_CHECKSUM")" >/dev/null
) || {
  printf 'script_111_product_documentation=blocked;reason=accepted_checksum_failed\n' >&2
  exit 2
}
for accepted_fact in \
  'deterministic_archive=true;internal_checksums=pass;transfer_jargon=false;credential_material=false' \
  'target_contact=false;network_contact=false;package_downloaded=false;package_installed=false;service_changed=false' \
  'script_110_native_prerequisite_inventory_kit=pass;'; do
  grep -Fq "$accepted_fact" "$ACCEPTED_REPORT" || {
    printf 'script_111_product_documentation=blocked;reason=accepted_report_contract_failed\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER" "$COMMAND_ROOT/ishikawa-stack"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
  "$EVALUATOR"

work_root="$(mktemp -d /tmp/ishikawa-script-111.XXXXXX)"
artifact_committed=false
artifact_path=''
checksum_path=''
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$artifact_committed" != true ]]; then
    [[ "$artifact_path" == "$ARTIFACT_ROOT"/product_documentation_qualification_*.json ]] && rm -f -- "$artifact_path"
    [[ "$checksum_path" == "$ARTIFACT_ROOT"/product_documentation_qualification_*.json.sha256 ]] && rm -f -- "$checksum_path"
  fi
  [[ "$work_root" == /tmp/ishikawa-script-111.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/native-tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  printf 'script_111_product_documentation=blocked;reason=test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$test_result" | awk '{print $1}')" "$(stat -c '%s' "$test_result")" >&2
  exit 1
}
grep -Fq 'Ran 360 tests' "$test_result" || {
  printf 'script_111_product_documentation=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_111_product_documentation=blocked;reason=test_pass_marker_absent\n' >&2
  exit 1
}

stack_help="$work_root/stack-help.txt"
ingestion_help="$work_root/ingestion-help.txt"
retrieval_help="$work_root/retrieval-help.txt"
logging_help="$work_root/logging-help.txt"
retention_help="$work_root/retention-help.txt"
for command_and_output in \
  "ishikawa-stack:$stack_help" \
  "ishikawa-ingest:$ingestion_help" \
  "ishikawa-retrieval-api:$retrieval_help" \
  "ishikawa-log-control:$logging_help"; do
  command_name="${command_and_output%%:*}"
  command_output="${command_and_output#*:}"
  "$COMMAND_ROOT/$command_name" --help >"$command_output" 2>&1 || {
    printf 'script_111_product_documentation=blocked;reason=command_help_failed\n' >&2
    exit 1
  }
done
if "$COMMAND_ROOT/ishikawa-observability-retention" --help >"$retention_help" 2>&1; then
  retention_help_status=0
else
  retention_help_status="$?"
fi
[[ "$retention_help_status" == 2 ]] || {
  printf 'script_111_product_documentation=blocked;reason=retention_usage_status_mismatch\n' >&2
  exit 1
}
for help_contract in \
  "Usage: ishikawa-stack {start|status|stop}@@$stack_help" \
  "Usage: ishikawa-ingest (--validate-only|--publish) --manifest BATCH.yaml@@$ingestion_help" \
  "Usage: ishikawa-retrieval-api --check-config | --serve@@$retrieval_help" \
  "Usage: ishikawa-log-control status | disable | enable --reason CODE --duration-seconds N (--scope service | --request-id ID)@@$logging_help" \
  "Usage: ishikawa-observability-retention --check-config | --apply@@$retention_help"; do
  expected_help="${help_contract%%@@*}"
  help_output="${help_contract#*@@}"
  grep -Fxq "$expected_help" "$help_output" || {
    printf 'script_111_product_documentation=blocked;reason=command_help_contract_mismatch\n' >&2
    exit 1
  }
done

qualification="$work_root/documentation-qualification.json"
evaluation="$work_root/documentation-evaluation.txt"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" \
  --docs-root "$DOCS_ROOT" \
  --config-root "$CONFIG_ROOT" \
  --command-root "$COMMAND_ROOT" \
  --python-root "$PYTHON_ROOT" \
  --output "$qualification" >"$evaluation" || {
  printf 'script_111_product_documentation=blocked;reason=documentation_evaluation_failed\n' >&2
  exit 1
}
for expected_line in \
  'documentation_files=6;portable_jargon=false;credential_material=false' \
  'command_contracts=5;configuration_contract=pass;method_contract=pass' \
  'documentation_qualification=pass'; do
  grep -Fxq "$expected_line" "$evaluation" || {
    printf 'script_111_product_documentation=blocked;reason=evaluation_contract_mismatch\n' >&2
    exit 1
  }
done

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
qualification_sha256="$(sha256sum "$qualification" | awk '{print $1}')"
qualification_bytes="$(stat -c '%s' "$qualification")"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_ishikawa_product_documentation' \
    "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256" \
    "accepted_script_110_report_sha256=$ACCEPTED_REPORT_SHA256;accepted_script_110_artifact_sha256=$ACCEPTED_ARTIFACT_SHA256" \
    'documentation_files=6;command_contracts=5;configuration_contract=pass;method_contract=pass' \
    'native_tests=360;failures=0;errors=0' \
    'target_contact=false;runtime_changed=false;accepted_package_changed=false' \
    'script_111_product_documentation_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/product_documentation_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  printf 'script_111_product_documentation=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
cp -- "$qualification" "$artifact_path"
printf '%s  %s\n' "$qualification_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true
(
  cd -- "$ARTIFACT_ROOT"
  sha256sum --check --strict "$(basename -- "$checksum_path")" >/dev/null
) || {
  printf 'script_111_product_documentation=blocked;reason=retained_checksum_failed\n' >&2
  exit 1
}
artifact_committed=true

report_path="$(mktemp "$REPORT_ROOT/product_documentation_${timestamp}_XXXXXX.txt")"
{
  printf 'purpose=qualify_ishikawa_product_documentation\n'
  printf 'started_utc=%s\n' "$timestamp"
  printf 'script_sha256=%s;evaluator_sha256=%s\n' "$script_sha256" "$evaluator_sha256"
  printf 'accepted_script_110_report_sha256=%s;accepted_script_110_artifact_sha256=%s\n' "$ACCEPTED_REPORT_SHA256" "$ACCEPTED_ARTIFACT_SHA256"
  printf 'documentation_files=6;command_contracts=5;configuration_contract=pass;method_contract=pass\n'
  printf 'portable_jargon=false;credential_material=false;native_tests=360;failures=0;errors=0\n'
  printf 'target_contact=false;network_contact=false;runtime_changed=false;database_changed=false;service_changed=false\n'
  printf 'accepted_package_changed=false;package_refresh_required_to_ship_documents=true\n'
  printf 'accepted_artifact=%s;accepted_artifact_sha256=%s;accepted_artifact_bytes=%s;accepted_checksum=%s\n' "$artifact_path" "$qualification_sha256" "$qualification_bytes" "$checksum_path"
  printf 'script_111_product_documentation=pass;next_gate=refresh_ishikawa_v1_package_with_qualified_documentation\n'
} | tee "$report_path"
chmod 0600 "$report_path" 2>/dev/null || true
