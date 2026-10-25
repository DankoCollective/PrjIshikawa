#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the native foreground Ishikawa Retrieval API command and its
#   loopback liveness and fail-closed readiness boundary.
#
# Mental model:
#   Bind the work to accepted database-package evidence, run the complete
#   local application suite, assemble a temporary installed layout, validate
#   configuration without secrets, start the service, probe only its local
#   health routes, stop it with SIGTERM, and prove listener cleanup.
#
# Inputs or prerequisites:
#   Accepted Script 91 evidence, current Ishikawa sources and configuration,
#   CODING_STANDARD.md, Python 3.12, PyYAML, curl, and a free local port 1384.
#
# Outputs:
#   Content-free local qualification evidence. No target, database, model,
#   credential, corpus, persistent service, or packaged installation changes.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/92_qualify_native_retrieval_service_entrypoint.sh --run

usage() {
  sed -n '3,23p' "${BASH_SOURCE[0]}"
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
readonly COMMAND_MODULE="$PACKAGE_ROOT/retrieval_command.py"
readonly LISTENER_MODULE="$PACKAGE_ROOT/http_listener.py"
readonly RUNTIME_MODULE="$PACKAGE_ROOT/runtime.py"
readonly COMMAND_TEST="$TEST_ROOT/test_retrieval_command.py"
readonly LISTENER_TEST="$TEST_ROOT/test_http_listener.py"
readonly CONTRACT="$ISHIKAWA_ROOT/docs/RETRIEVAL_API_SERVICE.md"
readonly CONFIG_ROOT="$ISHIKAWA_ROOT/config/templates"
readonly CODING_STANDARD="$REPO_ROOT/CODING_STANDARD.md"
readonly ACCEPTED_REPORT="$REPO_ROOT/local/reports/ishikawa-database-schema-qualification/database_schema_qualification_20261020T234958Z_VAT4I9.txt"
readonly ACCEPTED_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/database-schema-qualification/database_schema_qualification_20261020T234958Z.json"
readonly ACCEPTED_CHECKSUM="$ACCEPTED_ARTIFACT.sha256"
readonly ACCEPTED_REPORT_SHA256='27dd70ab765fe645f94677396f95f77c58f45607a185d90ecd54b48465cc18f1'
readonly ACCEPTED_ARTIFACT_SHA256='e200fdf5f6e26f4fd94d655880032f76cb5f5ea5e1894de57e718fa3fc13f6e8'
readonly ACCEPTED_CHECKSUM_SHA256='26c12e754ab845da837ba8cb519cfe7f28c3866d5bd77c2bc65ffd4530efd7a9'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-retrieval-service-entrypoint"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/retrieval-service-entrypoint"

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_92_retrieval_service_entrypoint=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_92_retrieval_service_entrypoint=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in awk bash basename cat chmod cp curl date dirname env find grep install kill mkdir mktemp mv python3 rm sed seq sha256sum sleep ss stat tee wc; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_92_retrieval_service_entrypoint=blocked;reason=local_command_missing\n' >&2
    exit 2
  }
done
mapfile -t python_sources < <(find "$PACKAGE_ROOT" -maxdepth 1 -type f -name '*.py' -print | sort)
mapfile -t configuration_sources < <(find "$CONFIG_ROOT" -maxdepth 1 -type f -name '*.yaml' -print | sort)
for required_file in \
  "$TEST_RUNNER" "$ENTRYPOINT" "$COMMAND_MODULE" "$LISTENER_MODULE" "$RUNTIME_MODULE" \
  "$COMMAND_TEST" "$LISTENER_TEST" "$CONTRACT" "$CODING_STANDARD" \
  "$ACCEPTED_REPORT" "$ACCEPTED_ARTIFACT" "$ACCEPTED_CHECKSUM" \
  "${python_sources[@]}" "${configuration_sources[@]}"; do
  [[ -f "$required_file" && ! -L "$required_file" && -r "$required_file" ]] || {
    printf 'script_92_retrieval_service_entrypoint=blocked;reason=required_input_unsafe\n' >&2
    exit 2
  }
done
(( ${#python_sources[@]} >= 40 && ${#configuration_sources[@]} >= 14 )) || {
  printf 'script_92_retrieval_service_entrypoint=blocked;reason=source_inventory_incomplete\n' >&2
  exit 2
}

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_92_retrieval_service_entrypoint=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}
check_sha256 "$ACCEPTED_REPORT" "$ACCEPTED_REPORT_SHA256" 'accepted_report'
check_sha256 "$ACCEPTED_ARTIFACT" "$ACCEPTED_ARTIFACT_SHA256" 'accepted_artifact'
check_sha256 "$ACCEPTED_CHECKSUM" "$ACCEPTED_CHECKSUM_SHA256" 'accepted_checksum'
(
  cd -- "$(dirname -- "$ACCEPTED_ARTIFACT")"
  sha256sum --check --strict "$(basename -- "$ACCEPTED_CHECKSUM")" >/dev/null
) || { printf 'script_92_retrieval_service_entrypoint=blocked;reason=accepted_checksum_failed\n' >&2; exit 2; }
for fact in \
  'database_schema_package_qualification=pass' \
  'temporary_database_dropped=true;accepted_database_unchanged=true' \
  'cluster_status=down;postgresql_port_5432=free;postgresql_service_active=inactive;postgresql_service_enabled=disabled' \
  'script_91_database_schema_qualification=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_REPORT" || {
    printf 'script_92_retrieval_service_entrypoint=blocked;reason=accepted_report_contract_failed\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$ENTRYPOINT" "$COMMAND_MODULE" "$LISTENER_MODULE" "$RUNTIME_MODULE" "$COMMAND_TEST" "$LISTENER_TEST" \
  "${python_sources[@]}"
for portable_source in "$ENTRYPOINT" "$COMMAND_MODULE" "$LISTENER_MODULE"; do
  if grep -Eiq 'phase[-_ ]?[0-9]+|(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)|Danko|org[_ -]?lab|Agent|repository|Script[[:space:]_-]*[0-9]+' "$portable_source"; then
    printf 'script_92_retrieval_service_entrypoint=blocked;reason=installed_source_jargon_found\n' >&2
    exit 2
  fi
done

work_root="$(mktemp -d /tmp/ishikawa-script-92.XXXXXX)"
service_pid=''
artifact_committed=false
artifact_path=''
checksum_path=''
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  set +e
  if [[ "$service_pid" =~ ^[0-9]+$ ]] && kill -0 "$service_pid" 2>/dev/null; then
    kill -TERM "$service_pid" 2>/dev/null
    wait "$service_pid" 2>/dev/null
  fi
  if [[ "$artifact_committed" != true ]]; then
    [[ "$artifact_path" == "$ARTIFACT_ROOT"/retrieval_service_entrypoint_qualification_*.json ]] && rm -f -- "$artifact_path"
    [[ "$checksum_path" == "$ARTIFACT_ROOT"/retrieval_service_entrypoint_qualification_*.json.sha256 ]] && rm -f -- "$checksum_path"
  fi
  if [[ "$work_root" == /tmp/ishikawa-script-92.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  printf 'script_92_retrieval_service_entrypoint=blocked;reason=test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$test_result" | awk '{print $1}')" "$(stat -c '%s' "$test_result")" >&2
  exit 1
}
grep -Fq 'Ran 325 tests' "$test_result" || {
  printf 'script_92_retrieval_service_entrypoint=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_92_retrieval_service_entrypoint=blocked;reason=test_pass_marker_absent\n' >&2
  exit 1
}

installed_root="$work_root/Ishikawa"
install -d -m 0755 -- \
  "$installed_root/application/python/ishikawa" \
  "$installed_root/config" \
  "$installed_root/scripts"
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
  printf 'script_92_retrieval_service_entrypoint=blocked;reason=config_check_contract_failed\n' >&2
  exit 1
}

if ss -H -ltn '( sport = :1384 )' | grep -q .; then
  printf 'script_92_retrieval_service_entrypoint=blocked;reason=port_1384_in_use\n' >&2
  exit 1
fi
service_output="$work_root/service.txt"
env -u ISHIKAWA_GEMMA_API_KEY -u ISHIKAWA_NOMIC_API_KEY -u ISHIKAWA_POSTGRESQL_PASSWORD \
  PYTHONDONTWRITEBYTECODE=1 "$installed_root/scripts/ishikawa-retrieval-api" --serve >"$service_output" 2>&1 &
service_pid=$!

live_body="$work_root/live.json"
live_code='000'
for _attempt in $(seq 1 50); do
  if ! kill -0 "$service_pid" 2>/dev/null; then break; fi
  live_code="$(curl --silent --show-error --output "$live_body" --write-out '%{http_code}' --max-time 2 http://127.0.0.1:1384/live 2>/dev/null || true)"
  [[ "$live_code" == 200 ]] && break
  sleep 0.1
done
[[ "$live_code" == 200 && "$(cat "$live_body")" == '{"schema":"ishikawa.health.v1","status":"live"}' ]] || {
  printf 'script_92_retrieval_service_entrypoint=blocked;reason=liveness_contract_failed\n' >&2
  exit 1
}
ready_body="$work_root/ready.json"
ready_code="$(curl --silent --show-error --output "$ready_body" --write-out '%{http_code}' --max-time 2 http://127.0.0.1:1384/ready)"
[[ "$ready_code" == 503 && "$(cat "$ready_body")" == '{"schema":"ishikawa.health.v1","status":"not-ready"}' ]] || {
  printf 'script_92_retrieval_service_entrypoint=blocked;reason=readiness_fail_closed_contract_failed\n' >&2
  exit 1
}

kill -TERM "$service_pid"
set +e
wait "$service_pid"
service_exit=$?
set -e
service_pid=''
(( service_exit == 0 )) || { printf 'script_92_retrieval_service_entrypoint=blocked;reason=service_exit_failed\n' >&2; exit 1; }
grep -Fxq 'ishikawa_retrieval_api=started;bind_host=127.0.0.1;port=1384' "$service_output" || {
  printf 'script_92_retrieval_service_entrypoint=blocked;reason=start_marker_absent\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_retrieval_api=stopped;cleanup=complete' "$service_output" || {
  printf 'script_92_retrieval_service_entrypoint=blocked;reason=stop_marker_absent\n' >&2
  exit 1
}
[[ "$(wc -l <"$service_output")" == 2 ]] || {
  printf 'script_92_retrieval_service_entrypoint=blocked;reason=unexpected_service_output\n' >&2
  exit 1
}
if ss -H -ltn '( sport = :1384 )' | grep -q .; then
  printf 'script_92_retrieval_service_entrypoint=blocked;reason=listener_cleanup_failed\n' >&2
  exit 1
fi

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
entrypoint_sha256="$(sha256sum "$ENTRYPOINT" | awk '{print $1}')"
command_module_sha256="$(sha256sum "$COMMAND_MODULE" | awk '{print $1}')"
listener_module_sha256="$(sha256sum "$LISTENER_MODULE" | awk '{print $1}')"
runtime_module_sha256="$(sha256sum "$RUNTIME_MODULE" | awk '{print $1}')"
contract_sha256="$(sha256sum "$CONTRACT" | awk '{print $1}')"
coding_standard_sha256="$(sha256sum "$CODING_STANDARD" | awk '{print $1}')"
policy_digest="$(sed -n 's/^ishikawa_retrieval_api_configuration=pass;policy_digest=\([0-9a-f]\{64\}\);.*/\1/p' "$check_result")"
printf '{"configuration_check":true,"credential_read":false,"dependency_contact":false,"entrypoint_sha256":"%s","health_routes":["/live","/ready"],"liveness_status":200,"listener_cleanup":true,"local_test_count":325,"policy_digest":"%s","readiness_concrete_dependencies":false,"readiness_status":503,"receipt_schema_version":1,"service_exit_code":0,"target_contact":false}\n' \
  "$entrypoint_sha256" "$policy_digest" >"$work_root/qualification.json"
qualification_sha256="$(sha256sum "$work_root/qualification.json" | awk '{print $1}')"
qualification_bytes="$(stat -c '%s' "$work_root/qualification.json")"

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_native_retrieval_service_entrypoint' \
    "script_sha256=$script_sha256;entrypoint_sha256=$entrypoint_sha256;command_module_sha256=$command_module_sha256" \
    "listener_module_sha256=$listener_module_sha256;runtime_module_sha256=$runtime_module_sha256;contract_sha256=$contract_sha256" \
    "coding_standard_sha256=$coding_standard_sha256;accepted_script_91_report_sha256=$ACCEPTED_REPORT_SHA256;accepted_script_91_artifact_sha256=$ACCEPTED_ARTIFACT_SHA256" \
    "runtime_policy_digest=$policy_digest;qualification_sha256=$qualification_sha256;qualification_bytes=$qualification_bytes" \
    'configuration_check=pass;credential_read=false;dependency_contact=false' \
    'liveness_http_status=200;readiness_http_status=503;readiness_fail_closed=true' \
    'signal=SIGTERM;service_exit_code=0;listener_cleanup=pass' \
    'target_contact=false;database_changed=false;model_call=false;service_installed=false' \
    'local_tests=325;failures=0;errors=0' \
    'script_92_retrieval_service_entrypoint_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/retrieval_service_entrypoint_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  printf 'script_92_retrieval_service_entrypoint=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
cp -- "$work_root/qualification.json" "$artifact_path"
printf '%s  %s\n' "$qualification_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true
(
  cd -- "$ARTIFACT_ROOT"
  sha256sum --check --strict "$(basename -- "$checksum_path")" >/dev/null
) || { printf 'script_92_retrieval_service_entrypoint=blocked;reason=retained_checksum_failed\n' >&2; exit 1; }
artifact_committed=true

report_path="$(mktemp "$REPORT_ROOT/retrieval_service_entrypoint_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=qualify_native_retrieval_service_entrypoint'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;entrypoint_sha256=$entrypoint_sha256;command_module_sha256=$command_module_sha256"
emit "listener_module_sha256=$listener_module_sha256;runtime_module_sha256=$runtime_module_sha256;contract_sha256=$contract_sha256"
emit "coding_standard_sha256=$coding_standard_sha256;accepted_script_91_report_sha256=$ACCEPTED_REPORT_SHA256;accepted_script_91_artifact_sha256=$ACCEPTED_ARTIFACT_SHA256"
emit 'authorized_actions=read_checksum_bound_sources_run_local_tests_build_temporary_installed_layout_validate_configuration_start_probe_and_stop_local_loopback_listener_retain_content_free_evidence'
emit 'non_actions=no_target_contact_no_database_or_model_contact_no_credential_read_no_corpus_or_schema_change_no_service_install_or_enablement_no_port_forwarding_change'
emit "runtime_policy_digest=$policy_digest"
emit 'configuration_check=pass;credential_read=false;dependency_contact=false'
emit 'application_route=POST_/v1/chat;liveness_route=GET_/live;readiness_route=GET_/ready'
emit 'liveness_http_status=200;readiness_http_status=503;readiness_fail_closed=true;dependency_details_exposed=false'
emit 'signal=SIGTERM;service_exit_code=0;listener_cleanup=pass;port_1384=free'
emit 'target_contact=false;database_changed=false;model_call=false;service_installed=false'
emit 'local_tests=325;failures=0;errors=0'
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$qualification_sha256;accepted_artifact_bytes=$qualification_bytes;accepted_checksum=$checksum_path"
emit "script_92_retrieval_service_entrypoint=pass;local_report=$report_path;next_gate=implement_and_qualify_concrete_readiness_dependencies"
chmod 0600 "$report_path" 2>/dev/null || true
