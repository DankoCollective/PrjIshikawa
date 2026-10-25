#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the protected local operator control surface for Ishikawa logging.
#
# Mental model:
#   Bind to accepted classified-logging evidence, run all local tests, exercise
#   exact control records over an owner-only Unix socket, then start a temporary
#   installed Retrieval API and prove the installed control command against it.
#
# Inputs or prerequisites:
#   Accepted Script 94 evidence, current Ishikawa sources and configuration,
#   CODING_STANDARD.md, Python 3.12, PyYAML, curl, and an available port 1384.
#
# Outputs:
#   Content-free local control evidence. No target, database, model, credential,
#   corpus, schema, service definition, package, or forwarding state is changed.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/95_qualify_operator_logging_control.sh --run

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
readonly CONFIG_ROOT="$ISHIKAWA_ROOT/config/templates"
readonly TEST_ROOT="$ISHIKAWA_ROOT/tests"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly SERVICE_ENTRYPOINT="$ISHIKAWA_ROOT/scripts/ishikawa-retrieval-api"
readonly CONTROL_ENTRYPOINT="$ISHIKAWA_ROOT/scripts/ishikawa-log-control"
readonly CONTROL_MODULE="$PACKAGE_ROOT/logging_control.py"
readonly OBSERVABILITY_MODULE="$PACKAGE_ROOT/observability.py"
readonly COMMAND_MODULE="$PACKAGE_ROOT/retrieval_command.py"
readonly READINESS_MODULE="$PACKAGE_ROOT/readiness.py"
readonly CONTROL_TEST="$TEST_ROOT/test_logging_control.py"
readonly CONTRACT="$ISHIKAWA_ROOT/docs/OBSERVABILITY.md"
readonly SERVICE_CONTRACT="$ISHIKAWA_ROOT/docs/RETRIEVAL_API_SERVICE.md"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_logging_control.py"
readonly CODING_STANDARD="$REPO_ROOT/CODING_STANDARD.md"
readonly ACCEPTED_REPORT="$REPO_ROOT/local/reports/ishikawa-classified-logging/classified_logging_20261021T001947Z_BsUIrL.txt"
readonly ACCEPTED_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/classified-logging/classified_logging_qualification_20261021T001947Z.json"
readonly ACCEPTED_CHECKSUM="$ACCEPTED_ARTIFACT.sha256"
readonly ACCEPTED_REPORT_SHA256='fcd5a46a50aab7c9457f8dbb0556a77dcca2c32500e529716a431ef0d723dd3a'
readonly ACCEPTED_ARTIFACT_SHA256='d01856489db7e3d84a3b9e7082be955de547e7b72c230bc9442101884a44dfd8'
readonly ACCEPTED_CHECKSUM_SHA256='2d5ddce1a3f2bd269dac410add53005890c977c68391fc138a552f3304439c20'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-logging-control"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/logging-control"

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_95_logging_control=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_95_logging_control=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in awk bash basename cat chmod cp curl date env find grep install kill mkdir mktemp mv python3 rm sed seq sha256sum sleep sort ss stat tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_95_logging_control=blocked;reason=local_command_missing\n' >&2
    exit 2
  }
done
mapfile -t python_sources < <(find "$PACKAGE_ROOT" -maxdepth 1 -type f -name '*.py' -print | sort)
mapfile -t configuration_sources < <(find "$CONFIG_ROOT" -maxdepth 1 -type f -name '*.yaml' -print | sort)
for required_file in \
  "$TEST_RUNNER" "$SERVICE_ENTRYPOINT" "$CONTROL_ENTRYPOINT" "$CONTROL_MODULE" \
  "$OBSERVABILITY_MODULE" "$COMMAND_MODULE" "$READINESS_MODULE" "$CONTROL_TEST" \
  "$CONTRACT" "$SERVICE_CONTRACT" "$EVALUATOR" "$CODING_STANDARD" \
  "$ACCEPTED_REPORT" "$ACCEPTED_ARTIFACT" "$ACCEPTED_CHECKSUM" \
  "${python_sources[@]}" "${configuration_sources[@]}"; do
  [[ -f "$required_file" && ! -L "$required_file" && -r "$required_file" ]] || {
    printf 'script_95_logging_control=blocked;reason=required_input_unsafe\n' >&2
    exit 2
  }
done
(( ${#python_sources[@]} >= 46 && ${#configuration_sources[@]} >= 18 )) || {
  printf 'script_95_logging_control=blocked;reason=source_inventory_incomplete\n' >&2
  exit 2
}

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_95_logging_control=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}
check_sha256 "$ACCEPTED_REPORT" "$ACCEPTED_REPORT_SHA256" 'accepted_report'
check_sha256 "$ACCEPTED_ARTIFACT" "$ACCEPTED_ARTIFACT_SHA256" 'accepted_artifact'
check_sha256 "$ACCEPTED_CHECKSUM" "$ACCEPTED_CHECKSUM_SHA256" 'accepted_checksum'
(
  cd -- "$(dirname -- "$ACCEPTED_ARTIFACT")"
  sha256sum --check --strict "$(basename -- "$ACCEPTED_CHECKSUM")" >/dev/null
) || { printf 'script_95_logging_control=blocked;reason=accepted_checksum_failed\n' >&2; exit 2; }
for fact in \
  'logging_profiles=default,debug,verbose;profile_count=3' \
  'verbose=bounded-scoped;automatic_restoration=pass;emergency_stop=pass' \
  'audit=separate-content-free;rotation=bounded;file_mode=0600' \
  'classified_logging_qualification=pass' \
  'local_tests=341;failures=0;errors=0' \
  'script_94_classified_logging=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_REPORT" || {
    printf 'script_95_logging_control=blocked;reason=accepted_report_contract_failed\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$SERVICE_ENTRYPOINT" "$CONTROL_ENTRYPOINT" "$EVALUATOR" "${python_sources[@]}"
for portable_source in \
  "$SERVICE_ENTRYPOINT" "$CONTROL_ENTRYPOINT" "$CONTROL_MODULE" \
  "$OBSERVABILITY_MODULE" "$COMMAND_MODULE"; do
  if grep -Eiq 'phase[-_ ]?[0-9]+|(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)|Danko|org[_ -]?lab|Agent|repository|Script[[:space:]_-]*[0-9]+' "$portable_source"; then
    printf 'script_95_logging_control=blocked;reason=installed_source_jargon_found\n' >&2
    exit 2
  fi
done

work_root="$(mktemp -d /tmp/ishikawa-script-95.XXXXXX)"
service_pid=''
artifact_committed=false
artifact_path=''
checksum_path=''
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ -n "$service_pid" ]] && kill -0 "$service_pid" 2>/dev/null; then
    kill -TERM "$service_pid" 2>/dev/null || true
    wait "$service_pid" 2>/dev/null || true
  fi
  if [[ "$artifact_committed" != true ]]; then
    [[ "$artifact_path" == "$ARTIFACT_ROOT"/logging_control_qualification_*.json ]] && rm -f -- "$artifact_path"
    [[ "$checksum_path" == "$ARTIFACT_ROOT"/logging_control_qualification_*.json.sha256 ]] && rm -f -- "$checksum_path"
  fi
  if [[ "$work_root" == /tmp/ishikawa-script-95.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  printf 'script_95_logging_control=blocked;reason=test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$test_result" | awk '{print $1}')" "$(stat -c '%s' "$test_result")" >&2
  exit 1
}
grep -Fq 'Ran 347 tests' "$test_result" || {
  printf 'script_95_logging_control=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_95_logging_control=blocked;reason=test_pass_marker_absent\n' >&2
  exit 1
}

evaluation_result="$work_root/evaluation.txt"
evaluation_error="$work_root/evaluation-error.txt"
qualification="$work_root/qualification.json"
if ! PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" \
  --python-root "$PYTHON_ROOT" \
  --config-root "$CONFIG_ROOT" \
  --output "$qualification" >"$evaluation_result" 2>"$evaluation_error"; then
  printf 'script_95_logging_control=blocked;reason=evaluation_failed;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$evaluation_error" | awk '{print $1}')" "$(stat -c '%s' "$evaluation_error")" >&2
  exit 1
fi
for fact in \
  'control_transport=unix-domain;socket_mode=0600;same_user=required' \
  'actions=status,enable,disable;request_contract=exact-bounded-json' \
  'verbose=request-or-service-scoped;duration=bounded;restart_restoration=pass' \
  'malformed_request=blocked;server_continuity=pass;socket_cleanup=pass' \
  'audit=content-free;request_scope_isolation=pass;network_listener=false' \
  'target_contact=false;database_changed=false;model_call=false' \
  'logging_control_qualification=pass'; do
  grep -Fqx "$fact" "$evaluation_result" || {
    printf 'script_95_logging_control=blocked;reason=evaluation_contract_mismatch\n' >&2
    exit 1
  }
done

installed_root="$work_root/Ishikawa"
install -d -m 0755 -- \
  "$installed_root/application/python/ishikawa" \
  "$installed_root/config" \
  "$installed_root/scripts"
install -d -m 0700 -- \
  "$installed_root/state/logs" \
  "$installed_root/state/run"
for source in "${python_sources[@]}"; do
  install -m 0644 -- "$source" "$installed_root/application/python/ishikawa/$(basename -- "$source")"
done
for source in "${configuration_sources[@]}"; do
  install -m 0644 -- "$source" "$installed_root/config/$(basename -- "$source")"
done
install -m 0755 -- "$SERVICE_ENTRYPOINT" "$installed_root/scripts/ishikawa-retrieval-api"
install -m 0755 -- "$CONTROL_ENTRYPOINT" "$installed_root/scripts/ishikawa-log-control"

check_result="$work_root/check-config.txt"
env -u ISHIKAWA_GEMMA_API_KEY -u ISHIKAWA_NOMIC_API_KEY -u ISHIKAWA_POSTGRESQL_PASSWORD \
  PYTHONDONTWRITEBYTECODE=1 "$installed_root/scripts/ishikawa-retrieval-api" --check-config >"$check_result"
grep -Eq '^ishikawa_retrieval_api_configuration=pass;policy_digest=[0-9a-f]{64};credential_read=false;dependency_contact=false$' "$check_result" || {
  printf 'script_95_logging_control=blocked;reason=config_check_contract_failed\n' >&2
  exit 1
}
help_result="$work_root/control-help.txt"
PYTHONDONTWRITEBYTECODE=1 "$installed_root/scripts/ishikawa-log-control" --help >"$help_result"
grep -Fxq 'Usage: ishikawa-log-control status | disable | enable --reason CODE --duration-seconds N (--scope service | --request-id ID)' "$help_result" || {
  printf 'script_95_logging_control=blocked;reason=control_help_contract_failed\n' >&2
  exit 1
}

if ss -H -ltn '( sport = :1384 )' | grep -q .; then
  printf 'script_95_logging_control=blocked;reason=port_1384_in_use\n' >&2
  exit 1
fi
service_output="$work_root/service.txt"
env -u ISHIKAWA_GEMMA_API_KEY -u ISHIKAWA_NOMIC_API_KEY -u ISHIKAWA_POSTGRESQL_PASSWORD \
  PYTHONDONTWRITEBYTECODE=1 "$installed_root/scripts/ishikawa-retrieval-api" --serve >"$service_output" 2>&1 &
service_pid=$!
for _attempt in $(seq 1 50); do
  [[ -S "$installed_root/state/run/logging-control.sock" ]] && break
  kill -0 "$service_pid" 2>/dev/null || break
  sleep 0.1
done
[[ -S "$installed_root/state/run/logging-control.sock" ]] || {
  printf 'script_95_logging_control=blocked;reason=control_socket_start_failed\n' >&2
  exit 1
}
[[ "$(stat -c '%a' "$installed_root/state/run/logging-control.sock")" == 600 ]] || {
  printf 'script_95_logging_control=blocked;reason=control_socket_mode_failed\n' >&2
  exit 1
}

status_before="$work_root/status-before.txt"
enable_result="$work_root/enable.txt"
status_enabled="$work_root/status-enabled.txt"
disable_result="$work_root/disable.txt"
PYTHONDONTWRITEBYTECODE=1 "$installed_root/scripts/ishikawa-log-control" status >"$status_before"
PYTHONDONTWRITEBYTECODE=1 "$installed_root/scripts/ishikawa-log-control" enable \
  --reason qualification --duration-seconds 60 --scope service >"$enable_result"
PYTHONDONTWRITEBYTECODE=1 "$installed_root/scripts/ishikawa-log-control" status >"$status_enabled"
PYTHONDONTWRITEBYTECODE=1 "$installed_root/scripts/ishikawa-log-control" disable >"$disable_result"
grep -Fxq 'ishikawa_logging_control=pass;action=status;profile=default' "$status_before" || {
  printf 'script_95_logging_control=blocked;reason=initial_status_failed\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_logging_control=pass;action=enable;profile=verbose' "$enable_result" || {
  printf 'script_95_logging_control=blocked;reason=enable_failed\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_logging_control=pass;action=status;profile=verbose' "$status_enabled" || {
  printf 'script_95_logging_control=blocked;reason=enabled_status_failed\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_logging_control=pass;action=disable;profile=default' "$disable_result" || {
  printf 'script_95_logging_control=blocked;reason=disable_failed\n' >&2
  exit 1
}

kill -TERM "$service_pid"
set +e
wait "$service_pid"
service_exit=$?
set -e
service_pid=''
(( service_exit == 0 )) || {
  printf 'script_95_logging_control=blocked;reason=service_exit_failed\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_retrieval_api=started;bind_host=127.0.0.1;port=1384' "$service_output" || {
  printf 'script_95_logging_control=blocked;reason=start_marker_absent\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_retrieval_api=stopped;cleanup=complete' "$service_output" || {
  printf 'script_95_logging_control=blocked;reason=stop_marker_absent\n' >&2
  exit 1
}
[[ ! -e "$installed_root/state/run/logging-control.sock" ]] || {
  printf 'script_95_logging_control=blocked;reason=control_socket_cleanup_failed\n' >&2
  exit 1
}
if ss -H -ltn '( sport = :1384 )' | grep -q .; then
  printf 'script_95_logging_control=blocked;reason=listener_cleanup_failed\n' >&2
  exit 1
fi
PYTHONDONTWRITEBYTECODE=1 python3 -B - "$installed_root/state/logs" <<'PY' || {
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
audit = [json.loads(line) for line in (root / "audit.jsonl").read_text().splitlines()]
operational = [
    json.loads(line) for line in (root / "retrieval.jsonl").read_text().splitlines()
]
if [item["event_code"] for item in audit] != [
    "VERBOSE_CAPTURE_ENABLED",
    "VERBOSE_CAPTURE_DISABLED",
]:
    raise SystemExit(1)
if any("restricted" in item for item in audit):
    raise SystemExit(1)
if [item["event_code"] for item in operational] != [
    "SERVICE_STARTED",
    "SERVICE_STOPPED",
]:
    raise SystemExit(1)
PY
  printf 'script_95_logging_control=blocked;reason=installed_log_contract_failed\n' >&2
  exit 1
}

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
control_module_sha256="$(sha256sum "$CONTROL_MODULE" | awk '{print $1}')"
observability_sha256="$(sha256sum "$OBSERVABILITY_MODULE" | awk '{print $1}')"
command_sha256="$(sha256sum "$COMMAND_MODULE" | awk '{print $1}')"
control_entrypoint_sha256="$(sha256sum "$CONTROL_ENTRYPOINT" | awk '{print $1}')"
contract_sha256="$(sha256sum "$CONTRACT" | awk '{print $1}')"
coding_standard_sha256="$(sha256sum "$CODING_STANDARD" | awk '{print $1}')"
policy_digest="$(sed -n 's/^ishikawa_retrieval_api_configuration=pass;policy_digest=\([0-9a-f]\{64\}\);.*/\1/p' "$check_result")"
qualification_sha256="$(sha256sum "$qualification" | awk '{print $1}')"
qualification_bytes="$(stat -c '%s' "$qualification")"

if [[ "$validate_only" == true ]]; then
  cat "$evaluation_result"
  printf '%s\n' \
    'purpose=validate_operator_logging_control' \
    "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256;control_module_sha256=$control_module_sha256" \
    "observability_module_sha256=$observability_sha256;command_module_sha256=$command_sha256;control_entrypoint_sha256=$control_entrypoint_sha256;contract_sha256=$contract_sha256" \
    "coding_standard_sha256=$coding_standard_sha256;accepted_script_94_report_sha256=$ACCEPTED_REPORT_SHA256;accepted_script_94_artifact_sha256=$ACCEPTED_ARTIFACT_SHA256" \
    "runtime_policy_digest=$policy_digest;qualification_sha256=$qualification_sha256;qualification_bytes=$qualification_bytes" \
    'installed_control=pass;service_lifecycle=pass;socket_cleanup=pass;credential_read=false;dependency_contact=false' \
    'target_contact=false;database_changed=false;model_call=false;local_listener_started=true;service_definition_changed=false' \
    'local_tests=347;failures=0;errors=0' \
    'script_95_logging_control_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/logging_control_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  printf 'script_95_logging_control=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
cp -- "$qualification" "$artifact_path"
printf '%s  %s\n' "$qualification_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true
(
  cd -- "$ARTIFACT_ROOT"
  sha256sum --check --strict "$(basename -- "$checksum_path")" >/dev/null
) || { printf 'script_95_logging_control=blocked;reason=retained_checksum_failed\n' >&2; exit 1; }
artifact_committed=true

report_path="$(mktemp "$REPORT_ROOT/logging_control_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=qualify_operator_logging_control'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256;control_module_sha256=$control_module_sha256"
emit "observability_module_sha256=$observability_sha256;command_module_sha256=$command_sha256;control_entrypoint_sha256=$control_entrypoint_sha256;contract_sha256=$contract_sha256"
emit "coding_standard_sha256=$coding_standard_sha256;accepted_script_94_report_sha256=$ACCEPTED_REPORT_SHA256;accepted_script_94_artifact_sha256=$ACCEPTED_ARTIFACT_SHA256"
emit 'authorized_actions=read_checksum_bound_sources_run_local_tests_create_temporary_unix_socket_and_loopback_listener_exercise_installed_control_write_temporary_synthetic_logs_retain_content_free_evidence'
emit 'non_actions=no_target_database_or_model_contact_no_real_credential_read_no_corpus_schema_service_definition_package_or_port_forwarding_change_no_persistent_service_or_socket'
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit "runtime_policy_digest=$policy_digest"
emit 'installed_control=pass;service_lifecycle=pass;socket_cleanup=pass;credential_read=false;dependency_contact=false'
emit 'target_contact=false;database_changed=false;model_call=false;local_listener_started=true;service_definition_changed=false'
emit 'local_tests=347;failures=0;errors=0'
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$qualification_sha256;accepted_artifact_bytes=$qualification_bytes;accepted_checksum=$checksum_path"
emit "script_95_logging_control=pass;local_report=$report_path;next_gate=implement_content_free_operational_metrics"
chmod 0600 "$report_path" 2>/dev/null || true
