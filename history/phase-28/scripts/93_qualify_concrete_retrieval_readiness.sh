#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the complete fail-closed readiness composition for the native
#   Ishikawa Retrieval API without contacting live dependencies.
#
# Mental model:
#   Bind the work to accepted service-entrypoint evidence, run every local
#   test, assemble the installed configuration without credentials, and use
#   injected local ports to prove ready plus each required not-ready category.
#
# Inputs or prerequisites:
#   Accepted Script 92 evidence, current Ishikawa sources and configuration,
#   CODING_STANDARD.md, Python 3.12, and PyYAML.
#
# Outputs:
#   Content-free local readiness evidence. No target, database, model,
#   credential, listener, corpus, service, or package state is changed.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/93_qualify_concrete_retrieval_readiness.sh --run

usage() {
  sed -n '3,22p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Run locally and retain content-free evidence.' \
    '  --validate-only Run the same local qualification without retaining evidence.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$ISHIKAWA_ROOT/application/python"
readonly PACKAGE_ROOT="$PYTHON_ROOT/ishikawa"
readonly TEST_ROOT="$ISHIKAWA_ROOT/tests"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly ENTRYPOINT="$ISHIKAWA_ROOT/scripts/ishikawa-retrieval-api"
readonly READINESS_MODULE="$PACKAGE_ROOT/readiness.py"
readonly COMMAND_MODULE="$PACKAGE_ROOT/retrieval_command.py"
readonly RUNTIME_MODULE="$PACKAGE_ROOT/runtime.py"
readonly READINESS_TEST="$TEST_ROOT/test_readiness.py"
readonly COMMAND_TEST="$TEST_ROOT/test_retrieval_command.py"
readonly CONTRACT="$ISHIKAWA_ROOT/docs/RETRIEVAL_API_SERVICE.md"
readonly CONFIG_CONTRACT="$ISHIKAWA_ROOT/docs/CONFIGURATION_CONTRACTS.md"
readonly CONFIG_ROOT="$ISHIKAWA_ROOT/config/templates"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_concrete_readiness.py"
readonly CODING_STANDARD="$REPO_ROOT/CODING_STANDARD.md"
readonly ACCEPTED_REPORT="$REPO_ROOT/local/reports/ishikawa-retrieval-service-entrypoint/retrieval_service_entrypoint_20261020T235925Z_HoFsQx.txt"
readonly ACCEPTED_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/retrieval-service-entrypoint/retrieval_service_entrypoint_qualification_20261020T235925Z.json"
readonly ACCEPTED_CHECKSUM="$ACCEPTED_ARTIFACT.sha256"
readonly ACCEPTED_REPORT_SHA256='5b20407c64382131d8eea426d2e78285982a638e1b28742868e9bf4d31fd2079'
readonly ACCEPTED_ARTIFACT_SHA256='849be8ea857919761ac9ec8a62eef7fa88238749ad982175d13b6a96db2fbe9d'
readonly ACCEPTED_CHECKSUM_SHA256='5b2a0e10ab004d95db3d12f282817bdf7b237d726118756526f8ab1d444e2412'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-concrete-readiness"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/concrete-readiness"

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_93_concrete_readiness=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_93_concrete_readiness=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in awk bash basename cat chmod cp date env find grep install mkdir mktemp mv python3 rm sed sha256sum sort stat tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_93_concrete_readiness=blocked;reason=local_command_missing\n' >&2
    exit 2
  }
done
mapfile -t python_sources < <(find "$PACKAGE_ROOT" -maxdepth 1 -type f -name '*.py' -print | sort)
mapfile -t configuration_sources < <(find "$CONFIG_ROOT" -maxdepth 1 -type f -name '*.yaml' -print | sort)
for required_file in \
  "$TEST_RUNNER" "$ENTRYPOINT" "$READINESS_MODULE" "$COMMAND_MODULE" "$RUNTIME_MODULE" \
  "$READINESS_TEST" "$COMMAND_TEST" "$CONTRACT" "$CONFIG_CONTRACT" "$EVALUATOR" "$CODING_STANDARD" \
  "$ACCEPTED_REPORT" "$ACCEPTED_ARTIFACT" "$ACCEPTED_CHECKSUM" \
  "${python_sources[@]}" "${configuration_sources[@]}"; do
  [[ -f "$required_file" && ! -L "$required_file" && -r "$required_file" ]] || {
    printf 'script_93_concrete_readiness=blocked;reason=required_input_unsafe\n' >&2
    exit 2
  }
done
(( ${#python_sources[@]} >= 44 && ${#configuration_sources[@]} >= 14 )) || {
  printf 'script_93_concrete_readiness=blocked;reason=source_inventory_incomplete\n' >&2
  exit 2
}

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_93_concrete_readiness=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}
check_sha256 "$ACCEPTED_REPORT" "$ACCEPTED_REPORT_SHA256" 'accepted_report'
check_sha256 "$ACCEPTED_ARTIFACT" "$ACCEPTED_ARTIFACT_SHA256" 'accepted_artifact'
check_sha256 "$ACCEPTED_CHECKSUM" "$ACCEPTED_CHECKSUM_SHA256" 'accepted_checksum'
(
  cd -- "$(dirname -- "$ACCEPTED_ARTIFACT")"
  sha256sum --check --strict "$(basename -- "$ACCEPTED_CHECKSUM")" >/dev/null
) || { printf 'script_93_concrete_readiness=blocked;reason=accepted_checksum_failed\n' >&2; exit 2; }
for fact in \
  'configuration_check=pass;credential_read=false;dependency_contact=false' \
  'liveness_http_status=200;readiness_http_status=503;readiness_fail_closed=true' \
  'signal=SIGTERM;service_exit_code=0;listener_cleanup=pass' \
  'local_tests=325;failures=0;errors=0' \
  'script_92_retrieval_service_entrypoint=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_REPORT" || {
    printf 'script_93_concrete_readiness=blocked;reason=accepted_report_contract_failed\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$ENTRYPOINT" "$READINESS_MODULE" "$COMMAND_MODULE" "$RUNTIME_MODULE" "$READINESS_TEST" "$COMMAND_TEST" "$EVALUATOR" \
  "${python_sources[@]}"
for portable_source in "$ENTRYPOINT" "$READINESS_MODULE" "$COMMAND_MODULE"; do
  if grep -Eiq 'phase[-_ ]?[0-9]+|(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)|Danko|org[_ -]?lab|Agent|repository|Script[[:space:]_-]*[0-9]+' "$portable_source"; then
    printf 'script_93_concrete_readiness=blocked;reason=installed_source_jargon_found\n' >&2
    exit 2
  fi
done

work_root="$(mktemp -d /tmp/ishikawa-script-93.XXXXXX)"
artifact_committed=false
artifact_path=''
checksum_path=''
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$artifact_committed" != true ]]; then
    [[ "$artifact_path" == "$ARTIFACT_ROOT"/concrete_readiness_qualification_*.json ]] && rm -f -- "$artifact_path"
    [[ "$checksum_path" == "$ARTIFACT_ROOT"/concrete_readiness_qualification_*.json.sha256 ]] && rm -f -- "$checksum_path"
  fi
  if [[ "$work_root" == /tmp/ishikawa-script-93.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  printf 'script_93_concrete_readiness=blocked;reason=test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$test_result" | awk '{print $1}')" "$(stat -c '%s' "$test_result")" >&2
  exit 1
}
grep -Fq 'Ran 332 tests' "$test_result" || {
  printf 'script_93_concrete_readiness=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_93_concrete_readiness=blocked;reason=test_pass_marker_absent\n' >&2
  exit 1
}

evaluation_result="$work_root/evaluation.txt"
evaluation_error="$work_root/evaluation-error.txt"
qualification="$work_root/qualification.json"
if ! PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" \
  --python-root "$PYTHON_ROOT" \
  --config-root "$CONFIG_ROOT" \
  --output "$qualification" >"$evaluation_result" 2>"$evaluation_error"; then
  printf 'script_93_concrete_readiness=blocked;reason=evaluation_failed;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$evaluation_error" | awk '{print $1}')" "$(stat -c '%s' "$evaluation_error")" >&2
  exit 1
fi
for fact in \
  'readiness_components=5;complete_ready=true;active_corpus_required=true' \
  'lazy_assembly=true;credential_reads=0;dependency_contact=false' \
  'configuration_drift=not-ready;storage_missing=not-ready' \
  'inactive_corpus=not-ready;unhealthy_model=not-ready' \
  'database_cleanup=pass;client_component_details=false' \
  'concrete_readiness_qualification=pass'; do
  grep -Fqx "$fact" "$evaluation_result" || {
    printf 'script_93_concrete_readiness=blocked;reason=evaluation_contract_mismatch\n' >&2
    exit 1
  }
done

installed_root="$work_root/Ishikawa"
install -d -m 0755 -- \
  "$installed_root/application/python/ishikawa" \
  "$installed_root/config" \
  "$installed_root/scripts" \
  "$installed_root/state/logs"
for source in "${python_sources[@]}"; do
  install -m 0644 -- "$source" "$installed_root/application/python/ishikawa/$(basename -- "$source")"
done
for source in "${configuration_sources[@]}"; do
  install -m 0644 -- "$source" "$installed_root/config/$(basename -- "$source")"
done
install -m 0755 -- "$ENTRYPOINT" "$installed_root/scripts/ishikawa-retrieval-api"
check_result="$work_root/check-config.txt"
env -u ISHIKAWA_GEMMA_API_KEY -u ISHIKAWA_NOMIC_API_KEY -u ISHIKAWA_POSTGRESQL_PASSWORD \
  PYTHONDONTWRITEBYTECODE=1 "$installed_root/scripts/ishikawa-retrieval-api" --check-config >"$check_result"
grep -Eq '^ishikawa_retrieval_api_configuration=pass;policy_digest=[0-9a-f]{64};credential_read=false;dependency_contact=false$' "$check_result" || {
  printf 'script_93_concrete_readiness=blocked;reason=config_check_contract_failed\n' >&2
  exit 1
}

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
readiness_sha256="$(sha256sum "$READINESS_MODULE" | awk '{print $1}')"
command_sha256="$(sha256sum "$COMMAND_MODULE" | awk '{print $1}')"
runtime_sha256="$(sha256sum "$RUNTIME_MODULE" | awk '{print $1}')"
contract_sha256="$(sha256sum "$CONTRACT" | awk '{print $1}')"
config_contract_sha256="$(sha256sum "$CONFIG_CONTRACT" | awk '{print $1}')"
coding_standard_sha256="$(sha256sum "$CODING_STANDARD" | awk '{print $1}')"
policy_digest="$(sed -n 's/^ishikawa_retrieval_api_configuration=pass;policy_digest=\([0-9a-f]\{64\}\);.*/\1/p' "$check_result")"
qualification_sha256="$(sha256sum "$qualification" | awk '{print $1}')"
qualification_bytes="$(stat -c '%s' "$qualification")"

if [[ "$validate_only" == true ]]; then
  cat "$evaluation_result"
  printf '%s\n' \
    'purpose=validate_concrete_retrieval_readiness' \
    "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256;readiness_module_sha256=$readiness_sha256" \
    "command_module_sha256=$command_sha256;runtime_module_sha256=$runtime_sha256;contract_sha256=$contract_sha256;config_contract_sha256=$config_contract_sha256" \
    "coding_standard_sha256=$coding_standard_sha256;accepted_script_92_report_sha256=$ACCEPTED_REPORT_SHA256;accepted_script_92_artifact_sha256=$ACCEPTED_ARTIFACT_SHA256" \
    "runtime_policy_digest=$policy_digest;qualification_sha256=$qualification_sha256;qualification_bytes=$qualification_bytes" \
    'configuration_check=pass;credential_read=false;dependency_contact=false' \
    'target_contact=false;database_changed=false;model_call=false;listener_started=false;service_changed=false' \
    'local_tests=332;failures=0;errors=0' \
    'script_93_concrete_readiness_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/concrete_readiness_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  printf 'script_93_concrete_readiness=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
cp -- "$qualification" "$artifact_path"
printf '%s  %s\n' "$qualification_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true
(
  cd -- "$ARTIFACT_ROOT"
  sha256sum --check --strict "$(basename -- "$checksum_path")" >/dev/null
) || { printf 'script_93_concrete_readiness=blocked;reason=retained_checksum_failed\n' >&2; exit 1; }
artifact_committed=true

report_path="$(mktemp "$REPORT_ROOT/concrete_readiness_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=qualify_concrete_retrieval_readiness'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256;readiness_module_sha256=$readiness_sha256"
emit "command_module_sha256=$command_sha256;runtime_module_sha256=$runtime_sha256;contract_sha256=$contract_sha256;config_contract_sha256=$config_contract_sha256"
emit "coding_standard_sha256=$coding_standard_sha256;accepted_script_92_report_sha256=$ACCEPTED_REPORT_SHA256;accepted_script_92_artifact_sha256=$ACCEPTED_ARTIFACT_SHA256"
emit 'authorized_actions=read_checksum_bound_sources_run_local_tests_assemble_temporary_configuration_execute_injected_readiness_qualification_retain_content_free_evidence'
emit 'non_actions=no_target_database_or_model_contact_no_real_credential_read_no_listener_start_no_corpus_schema_service_package_or_port_forwarding_change'
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit "runtime_policy_digest=$policy_digest"
emit 'configuration_check=pass;credential_read=false;dependency_contact=false'
emit 'target_contact=false;database_changed=false;model_call=false;listener_started=false;service_changed=false'
emit 'local_tests=332;failures=0;errors=0'
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$qualification_sha256;accepted_artifact_bytes=$qualification_bytes;accepted_checksum=$checksum_path"
emit "script_93_concrete_readiness=pass;local_report=$report_path;next_gate=implement_classified_structured_logging"
chmod 0600 "$report_path" 2>/dev/null || true
