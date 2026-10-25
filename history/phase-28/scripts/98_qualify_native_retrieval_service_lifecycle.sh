#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the boot-disabled native Ishikawa Retrieval API service lifecycle.
#
# Mental model:
#   Bind to accepted retention evidence, run every local test, validate the
#   final systemd user unit, and run the exact installed foreground command in
#   temporary storage. Prove liveness, graceful SIGTERM, and complete cleanup.
#
# Inputs or prerequisites:
#   Accepted Script 97 evidence, current Ishikawa sources and configuration,
#   CODING_STANDARD.md, Python 3.12, PyYAML, curl, and systemd-analyze.
#
# Outputs:
#   Content-free local lifecycle evidence. No unit is installed or enabled and
#   no target, database, model, credential, corpus, package, or forwarding state
#   is contacted or changed.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/98_qualify_native_retrieval_service_lifecycle.sh --run

usage() {
  sed -n '3,24p' "${BASH_SOURCE[0]}"
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
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly SERVICE_ENTRYPOINT="$ISHIKAWA_ROOT/scripts/ishikawa-retrieval-api"
readonly SERVICE_UNIT="$ISHIKAWA_ROOT/packaging/systemd/ishikawa-retrieval-api.service"
readonly SERVICE_CONTRACT="$ISHIKAWA_ROOT/docs/RETRIEVAL_API_SERVICE.md"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_native_service_lifecycle.py"
readonly CODING_STANDARD="$REPO_ROOT/CODING_STANDARD.md"
readonly ACCEPTED_REPORT="$REPO_ROOT/local/reports/ishikawa-observability-retention/observability_retention_20261021T004945Z_h7yxYr.txt"
readonly ACCEPTED_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/observability-retention/observability_retention_qualification_20261021T004945Z.json"
readonly ACCEPTED_CHECKSUM="$ACCEPTED_ARTIFACT.sha256"
readonly ACCEPTED_REPORT_SHA256='c24221407e494370dd6c9a3204eb68966c7818981964e5a59653915d9be6035b'
readonly ACCEPTED_ARTIFACT_SHA256='ff6e15bf7e883607c86929a137f56548df7ae052d547d29f314d413ccda02811'
readonly ACCEPTED_CHECKSUM_SHA256='fc5807734a8f7e3fc5140ea3748ca07b03eafab76ff35022df95b36325c71fa5'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-native-service-lifecycle"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/native-service-lifecycle"

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_98_native_service_lifecycle=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_98_native_service_lifecycle=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in awk bash basename cat chmod cp curl date env find grep install kill mkdir mktemp mv python3 rm sed seq sha256sum sleep sort ss stat systemd-analyze tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_98_native_service_lifecycle=blocked;reason=local_command_missing\n' >&2
    exit 2
  }
done
mapfile -t python_sources < <(find "$PACKAGE_ROOT" -maxdepth 1 -type f -name '*.py' -print | sort)
mapfile -t configuration_sources < <(find "$CONFIG_ROOT" -maxdepth 1 -type f -name '*.yaml' -print | sort)
for required_file in \
  "$TEST_RUNNER" "$SERVICE_ENTRYPOINT" "$SERVICE_UNIT" "$SERVICE_CONTRACT" \
  "$EVALUATOR" "$CODING_STANDARD" "$ACCEPTED_REPORT" "$ACCEPTED_ARTIFACT" \
  "$ACCEPTED_CHECKSUM" "${python_sources[@]}" "${configuration_sources[@]}"; do
  [[ -f "$required_file" && ! -L "$required_file" && -r "$required_file" ]] || {
    printf 'script_98_native_service_lifecycle=blocked;reason=required_input_unsafe\n' >&2
    exit 2
  }
done
(( ${#python_sources[@]} >= 47 && ${#configuration_sources[@]} >= 18 )) || {
  printf 'script_98_native_service_lifecycle=blocked;reason=source_inventory_incomplete\n' >&2
  exit 2
}

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_98_native_service_lifecycle=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}
check_sha256 "$ACCEPTED_REPORT" "$ACCEPTED_REPORT_SHA256" 'accepted_report'
check_sha256 "$ACCEPTED_ARTIFACT" "$ACCEPTED_ARTIFACT_SHA256" 'accepted_artifact'
check_sha256 "$ACCEPTED_CHECKSUM" "$ACCEPTED_CHECKSUM_SHA256" 'accepted_checksum'
(
  cd -- "$(dirname -- "$ACCEPTED_ARTIFACT")"
  sha256sum --check --strict "$(basename -- "$ACCEPTED_CHECKSUM")" >/dev/null
) || { printf 'script_98_native_service_lifecycle=blocked;reason=accepted_checksum_failed\n' >&2; exit 2; }
for fact in \
  'observability_retention_qualification=pass' \
  'installed_check=pass;installed_apply=pass;timer_calendar=pass;systemd_unit_verify=pass' \
  'local_tests=356;failures=0;errors=0' \
  'script_97_observability_retention=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_REPORT" || {
    printf 'script_98_native_service_lifecycle=blocked;reason=accepted_report_contract_failed\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$SERVICE_ENTRYPOINT" "$EVALUATOR" "${python_sources[@]}"
for portable_source in "$SERVICE_ENTRYPOINT" "$SERVICE_UNIT"; do
  if grep -Eiq 'phase[-_ ]?[0-9]+|(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)|Danko|org[_ -]?lab|Agent|repository|Script[[:space:]_-]*[0-9]+' "$portable_source"; then
    printf 'script_98_native_service_lifecycle=blocked;reason=installed_source_jargon_found\n' >&2
    exit 2
  fi
done

work_root="$(mktemp -d /tmp/ishikawa-script-98.XXXXXX)"
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
    [[ "$artifact_path" == "$ARTIFACT_ROOT"/native_service_lifecycle_qualification_*.json ]] && rm -f -- "$artifact_path"
    [[ "$checksum_path" == "$ARTIFACT_ROOT"/native_service_lifecycle_qualification_*.json.sha256 ]] && rm -f -- "$checksum_path"
  fi
  if [[ "$work_root" == /tmp/ishikawa-script-98.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  printf 'script_98_native_service_lifecycle=blocked;reason=test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$test_result" | awk '{print $1}')" "$(stat -c '%s' "$test_result")" >&2
  exit 1
}
grep -Fq 'Ran 360 tests' "$test_result" || {
  printf 'script_98_native_service_lifecycle=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_98_native_service_lifecycle=blocked;reason=test_pass_marker_absent\n' >&2
  exit 1
}

evaluation_result="$work_root/evaluation.txt"
qualification="$work_root/qualification.json"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" \
  --service-unit "$SERVICE_UNIT" \
  --output "$qualification" >"$evaluation_result" || {
  printf 'script_98_native_service_lifecycle=blocked;reason=evaluation_failed\n' >&2
  exit 1
}
for fact in \
  'service=ishikawa-retrieval-api.service;type=simple;boot_enabled=false' \
  'start=explicit;restart=on-failure;shutdown=SIGTERM' \
  'environment=three-named-values;credential_values=false;environment_file=false' \
  'write_scope=state-logs-and-run;listener=loopback-configured' \
  'target_contact=false;database_changed=false;model_call=false' \
  'native_service_lifecycle_qualification=pass'; do
  grep -Fqx "$fact" "$evaluation_result" || {
    printf 'script_98_native_service_lifecycle=blocked;reason=evaluation_contract_mismatch\n' >&2
    exit 1
  }
done

unit_stage="$work_root/systemd"
install -d -m 0755 -- "$unit_stage"
install -m 0644 -- "$SERVICE_UNIT" "$unit_stage/ishikawa-retrieval-api.service"
sed -i \
  -e 's#%h/Documents/Ishikawa/scripts/ishikawa-retrieval-api#/bin/true#g' \
  -e 's#%h/Documents/Ishikawa#/tmp#g' \
  -e '/Documentation=file:/d' \
  "$unit_stage/ishikawa-retrieval-api.service"
systemd-analyze verify --user "$unit_stage/ishikawa-retrieval-api.service" \
  >"$work_root/unit-verify.txt" 2>&1 || {
  printf 'script_98_native_service_lifecycle=blocked;reason=systemd_unit_invalid\n' >&2
  exit 1
}

installed_root="$work_root/Ishikawa"
install -d -m 0755 -- \
  "$installed_root/application/python/ishikawa" \
  "$installed_root/config" \
  "$installed_root/scripts"
install -d -m 0700 -- "$installed_root/state/logs" "$installed_root/state/run"
for source in "${python_sources[@]}"; do
  install -m 0644 -- "$source" "$installed_root/application/python/ishikawa/$(basename -- "$source")"
done
for source in "${configuration_sources[@]}"; do
  install -m 0644 -- "$source" "$installed_root/config/$(basename -- "$source")"
done
install -m 0755 -- "$SERVICE_ENTRYPOINT" "$installed_root/scripts/ishikawa-retrieval-api"

check_result="$work_root/check.txt"
env -u ISHIKAWA_GEMMA_API_KEY -u ISHIKAWA_NOMIC_API_KEY -u ISHIKAWA_POSTGRESQL_PASSWORD \
  PYTHONDONTWRITEBYTECODE=1 "$installed_root/scripts/ishikawa-retrieval-api" --check-config >"$check_result"
grep -Eq '^ishikawa_retrieval_api_configuration=pass;policy_digest=[0-9a-f]{64};credential_read=false;dependency_contact=false$' "$check_result" || {
  printf 'script_98_native_service_lifecycle=blocked;reason=config_check_contract_failed\n' >&2
  exit 1
}
if ss -H -ltn '( sport = :1384 )' | grep -q .; then
  printf 'script_98_native_service_lifecycle=blocked;reason=port_1384_in_use\n' >&2
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
  printf 'script_98_native_service_lifecycle=blocked;reason=service_start_failed\n' >&2
  exit 1
}
live_body="$work_root/live.json"
live_code="$(curl --silent --show-error --output "$live_body" --write-out '%{http_code}' --max-time 5 http://127.0.0.1:1384/live)"
[[ "$live_code" == 200 && "$(cat "$live_body")" == '{"schema":"ishikawa.health.v1","status":"live"}' ]] || {
  printf 'script_98_native_service_lifecycle=blocked;reason=liveness_failed\n' >&2
  exit 1
}
kill -TERM "$service_pid"
set +e
wait "$service_pid"
service_exit=$?
set -e
service_pid=''
(( service_exit == 0 )) || {
  printf 'script_98_native_service_lifecycle=blocked;reason=graceful_exit_failed\n' >&2
  exit 1
}
[[ ! -e "$installed_root/state/run/logging-control.sock" ]] || {
  printf 'script_98_native_service_lifecycle=blocked;reason=control_socket_cleanup_failed\n' >&2
  exit 1
}
if ss -H -ltn '( sport = :1384 )' | grep -q .; then
  printf 'script_98_native_service_lifecycle=blocked;reason=listener_cleanup_failed\n' >&2
  exit 1
fi
grep -Fq 'ishikawa_retrieval_api=started;bind_host=127.0.0.1;port=1384' "$service_output" || {
  printf 'script_98_native_service_lifecycle=blocked;reason=start_marker_absent\n' >&2
  exit 1
}
grep -Fq 'ishikawa_retrieval_api=stopped;cleanup=complete' "$service_output" || {
  printf 'script_98_native_service_lifecycle=blocked;reason=stop_marker_absent\n' >&2
  exit 1
}
PYTHONDONTWRITEBYTECODE=1 python3 -B - "$installed_root/state/logs/retrieval.jsonl" <<'PY' || {
import json
import sys
from pathlib import Path

records = [json.loads(line) for line in Path(sys.argv[1]).read_text().splitlines()]
event_codes = [record["event_code"] for record in records]
if event_codes[0] != "SERVICE_STARTED" or event_codes[-1] != "SERVICE_STOPPED":
    raise SystemExit(1)
if any("restricted" in record or "diagnostic" in record for record in records):
    raise SystemExit(1)
PY
  printf 'script_98_native_service_lifecycle=blocked;reason=lifecycle_log_contract_failed\n' >&2
  exit 1
}

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
service_unit_sha256="$(sha256sum "$SERVICE_UNIT" | awk '{print $1}')"
entrypoint_sha256="$(sha256sum "$SERVICE_ENTRYPOINT" | awk '{print $1}')"
contract_sha256="$(sha256sum "$SERVICE_CONTRACT" | awk '{print $1}')"
qualification_sha256="$(sha256sum "$qualification" | awk '{print $1}')"
qualification_bytes="$(stat -c '%s' "$qualification")"

if [[ "$validate_only" == true ]]; then
  cat "$evaluation_result"
  printf '%s\n' \
    'purpose=validate_native_retrieval_service_lifecycle' \
    "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256;service_unit_sha256=$service_unit_sha256" \
    "entrypoint_sha256=$entrypoint_sha256;contract_sha256=$contract_sha256" \
    "qualification_sha256=$qualification_sha256;qualification_bytes=$qualification_bytes" \
    'systemd_unit_verify=pass;installed_config=pass;liveness=pass;sigterm_cleanup=pass;boot_enabled=false' \
    'credential_read=false;dependency_contact=false;target_contact=false;database_changed=false;model_call=false;service_changed=false' \
    'local_tests=360;failures=0;errors=0' \
    'script_98_native_service_lifecycle_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/native_service_lifecycle_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  printf 'script_98_native_service_lifecycle=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
cp -- "$qualification" "$artifact_path"
printf '%s  %s\n' "$qualification_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true
(
  cd -- "$ARTIFACT_ROOT"
  sha256sum --check --strict "$(basename -- "$checksum_path")" >/dev/null
) || { printf 'script_98_native_service_lifecycle=blocked;reason=retained_checksum_failed\n' >&2; exit 1; }
artifact_committed=true

report_path="$(mktemp "$REPORT_ROOT/native_service_lifecycle_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=qualify_native_retrieval_service_lifecycle'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256;service_unit_sha256=$service_unit_sha256"
emit "entrypoint_sha256=$entrypoint_sha256;contract_sha256=$contract_sha256"
emit "accepted_script_97_report_sha256=$ACCEPTED_REPORT_SHA256;accepted_script_97_artifact_sha256=$ACCEPTED_ARTIFACT_SHA256"
emit 'authorized_actions=read_checksum_bound_sources_run_local_tests_validate_systemd_unit_start_temporary_installed_loopback_listener_call_liveness_send_sigterm_validate_cleanup_retain_content_free_evidence'
emit 'non_actions=no_unit_install_enable_or_systemd_mutation_no_target_database_model_credential_corpus_package_or_forwarding_contact_or_change_no_persistent_process'
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit 'systemd_unit_verify=pass;installed_config=pass;liveness=pass;sigterm_cleanup=pass;boot_enabled=false'
emit 'credential_read=false;dependency_contact=false;target_contact=false;database_changed=false;model_call=false;service_changed=false'
emit 'local_tests=360;failures=0;errors=0'
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$qualification_sha256;accepted_artifact_bytes=$qualification_bytes;accepted_checksum=$checksum_path"
emit "script_98_native_service_lifecycle=pass;local_report=$report_path;next_gate=implement_nextjs_chat_ui"
chmod 0600 "$report_path" 2>/dev/null || true
