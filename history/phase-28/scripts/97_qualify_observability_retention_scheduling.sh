#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify protected local observability retention and its daily user timer.
#
# Mental model:
#   Bind to accepted operational-metrics evidence, run every local test, prove
#   retention in temporary storage, then execute the repository-free installed
#   command against synthetic aged telemetry. Validate the final systemd unit
#   definitions without installing or enabling them.
#
# Inputs or prerequisites:
#   Accepted Script 96 evidence, current Ishikawa sources and configuration,
#   CODING_STANDARD.md, Python 3.12, PyYAML, and systemd-analyze.
#
# Outputs:
#   Content-free local retention evidence. No target, database, model,
#   credential, corpus, service, timer, package, or forwarding state changes.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/97_qualify_observability_retention_scheduling.sh --run

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
readonly CONFIG_ROOT="$ISHIKAWA_ROOT/config/templates"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly RETENTION_ENTRYPOINT="$ISHIKAWA_ROOT/scripts/ishikawa-observability-retention"
readonly RETENTION_MODULE="$PACKAGE_ROOT/observability_retention.py"
readonly OBSERVABILITY_MODULE="$PACKAGE_ROOT/observability.py"
readonly LOGGING_PROFILE="$CONFIG_ROOT/logging_profile.yaml"
readonly SERVICE_UNIT="$ISHIKAWA_ROOT/packaging/systemd/ishikawa-observability-retention.service"
readonly TIMER_UNIT="$ISHIKAWA_ROOT/packaging/systemd/ishikawa-observability-retention.timer"
readonly CONTRACT="$ISHIKAWA_ROOT/docs/OBSERVABILITY.md"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_observability_retention.py"
readonly CODING_STANDARD="$REPO_ROOT/CODING_STANDARD.md"
readonly ACCEPTED_REPORT="$REPO_ROOT/local/reports/ishikawa-operational-metrics/operational_metrics_20261021T004116Z_VQBwOx.txt"
readonly ACCEPTED_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/operational-metrics/operational_metrics_qualification_20261021T004116Z.json"
readonly ACCEPTED_CHECKSUM="$ACCEPTED_ARTIFACT.sha256"
readonly ACCEPTED_REPORT_SHA256='62db467d33807f00ea0358b92cbd9609d9eaebf9afe7b5e60cace9ca28d3e1e8'
readonly ACCEPTED_ARTIFACT_SHA256='3101490e5c286d1a7d3b3163b30d1e27f567d5cfb18d83d0eef8e6cb629d01b2'
readonly ACCEPTED_CHECKSUM_SHA256='c5bbac73d233fd0680b646c84ad912e0093270648e387b02ea1dafcc5fa44aa1'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-observability-retention"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/observability-retention"

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_97_observability_retention=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_97_observability_retention=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in awk bash basename cat chmod cp date find grep install mkdir mktemp mv python3 rm sed sha256sum stat systemd-analyze tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_97_observability_retention=blocked;reason=local_command_missing\n' >&2
    exit 2
  }
done
mapfile -t python_sources < <(find "$PACKAGE_ROOT" -maxdepth 1 -type f -name '*.py' -print | sort)
mapfile -t configuration_sources < <(find "$CONFIG_ROOT" -maxdepth 1 -type f -name '*.yaml' -print | sort)
for required_file in \
  "$TEST_RUNNER" "$RETENTION_ENTRYPOINT" "$RETENTION_MODULE" \
  "$OBSERVABILITY_MODULE" "$LOGGING_PROFILE" "$SERVICE_UNIT" "$TIMER_UNIT" \
  "$CONTRACT" "$EVALUATOR" "$CODING_STANDARD" "$ACCEPTED_REPORT" \
  "$ACCEPTED_ARTIFACT" "$ACCEPTED_CHECKSUM" \
  "${python_sources[@]}" "${configuration_sources[@]}"; do
  [[ -f "$required_file" && ! -L "$required_file" && -r "$required_file" ]] || {
    printf 'script_97_observability_retention=blocked;reason=required_input_unsafe\n' >&2
    exit 2
  }
done
(( ${#python_sources[@]} >= 47 && ${#configuration_sources[@]} >= 18 )) || {
  printf 'script_97_observability_retention=blocked;reason=source_inventory_incomplete\n' >&2
  exit 2
}

check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_97_observability_retention=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}
check_sha256 "$ACCEPTED_REPORT" "$ACCEPTED_REPORT_SHA256" 'accepted_report'
check_sha256 "$ACCEPTED_ARTIFACT" "$ACCEPTED_ARTIFACT_SHA256" 'accepted_artifact'
check_sha256 "$ACCEPTED_CHECKSUM" "$ACCEPTED_CHECKSUM_SHA256" 'accepted_checksum'
(
  cd -- "$(dirname -- "$ACCEPTED_ARTIFACT")"
  sha256sum --check --strict "$(basename -- "$ACCEPTED_CHECKSUM")" >/dev/null
) || { printf 'script_97_observability_retention=blocked;reason=accepted_checksum_failed\n' >&2; exit 2; }
for fact in \
  'operational_metrics_qualification=pass' \
  'installed_short_circuit=pass;metrics_integration=pass;credential_read=false;dependency_contact=false' \
  'local_tests=350;failures=0;errors=0' \
  'script_96_operational_metrics=pass;'; do
  grep -Fq "$fact" "$ACCEPTED_REPORT" || {
    printf 'script_97_observability_retention=blocked;reason=accepted_report_contract_failed\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$RETENTION_ENTRYPOINT" "$EVALUATOR" "${python_sources[@]}"
for portable_source in "$RETENTION_ENTRYPOINT" "$RETENTION_MODULE" "$SERVICE_UNIT" "$TIMER_UNIT"; do
  if grep -Eiq 'phase[-_ ]?[0-9]+|(^|[^A-Za-z])(G|D)[0-9]{2}([^0-9]|$)|Danko|org[_ -]?lab|Agent|repository|Script[[:space:]_-]*[0-9]+' "$portable_source"; then
    printf 'script_97_observability_retention=blocked;reason=installed_source_jargon_found\n' >&2
    exit 2
  fi
done

work_root="$(mktemp -d /tmp/ishikawa-script-97.XXXXXX)"
artifact_committed=false
artifact_path=''
checksum_path=''
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$artifact_committed" != true ]]; then
    [[ "$artifact_path" == "$ARTIFACT_ROOT"/observability_retention_qualification_*.json ]] && rm -f -- "$artifact_path"
    [[ "$checksum_path" == "$ARTIFACT_ROOT"/observability_retention_qualification_*.json.sha256 ]] && rm -f -- "$checksum_path"
  fi
  if [[ "$work_root" == /tmp/ishikawa-script-97.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test_result="$work_root/tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  printf 'script_97_observability_retention=blocked;reason=test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$test_result" | awk '{print $1}')" "$(stat -c '%s' "$test_result")" >&2
  exit 1
}
grep -Fq 'Ran 356 tests' "$test_result" || {
  printf 'script_97_observability_retention=blocked;reason=test_count_mismatch\n' >&2
  exit 1
}
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || {
  printf 'script_97_observability_retention=blocked;reason=test_pass_marker_absent\n' >&2
  exit 1
}

evaluation_result="$work_root/evaluation.txt"
qualification="$work_root/qualification.json"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" \
  --python-root "$PYTHON_ROOT" \
  --config-root "$CONFIG_ROOT" \
  --service-unit "$SERVICE_UNIT" \
  --timer-unit "$TIMER_UNIT" \
  --output "$qualification" >"$evaluation_result" || {
  printf 'script_97_observability_retention=blocked;reason=evaluation_failed\n' >&2
  exit 1
}
for fact in \
  'retention_days=operational:30,metrics:30,audit:90;bounds=1-3650' \
  'candidate_scope=configured-active-and-numbered-rotations;unrelated=preserved' \
  'locking=protected-cross-process;unsafe-candidate=all-or-block' \
  'audit=start-and-completion;output=content-free-counts' \
  'scheduler=systemd-user-timer;schedule=daily;retrieval-api-started=false' \
  'target_contact=false;database_changed=false;model_call=false' \
  'observability_retention_qualification=pass'; do
  grep -Fqx "$fact" "$evaluation_result" || {
    printf 'script_97_observability_retention=blocked;reason=evaluation_contract_mismatch\n' >&2
    exit 1
  }
done
systemd-analyze calendar daily >"$work_root/calendar.txt"
grep -Fq 'Normalized form:' "$work_root/calendar.txt" || {
  printf 'script_97_observability_retention=blocked;reason=timer_calendar_invalid\n' >&2
  exit 1
}
unit_stage="$work_root/systemd"
install -d -m 0755 -- "$unit_stage"
install -m 0644 -- "$SERVICE_UNIT" "$unit_stage/ishikawa-observability-retention.service"
install -m 0644 -- "$TIMER_UNIT" "$unit_stage/ishikawa-observability-retention.timer"
sed -i \
  -e 's#%h/Documents/Ishikawa/scripts/ishikawa-observability-retention#/bin/true#g' \
  -e 's#%h/Documents/Ishikawa/state/logs#/tmp#g' \
  -e '/Documentation=file:/d' \
  "$unit_stage/ishikawa-observability-retention.service"
systemd-analyze verify --user \
  "$unit_stage/ishikawa-observability-retention.service" \
  "$unit_stage/ishikawa-observability-retention.timer" \
  >"$work_root/unit-verify.txt" 2>&1 || {
  printf 'script_97_observability_retention=blocked;reason=systemd_unit_invalid\n' >&2
  exit 1
}

installed_root="$work_root/Ishikawa"
install -d -m 0755 -- "$installed_root/application/python/ishikawa" "$installed_root/config" "$installed_root/scripts"
install -d -m 0700 -- "$installed_root/state/logs"
for source in "${python_sources[@]}"; do
  install -m 0644 -- "$source" "$installed_root/application/python/ishikawa/$(basename -- "$source")"
done
install -m 0644 -- "$LOGGING_PROFILE" "$installed_root/config/logging_profile.yaml"
install -m 0755 -- "$RETENTION_ENTRYPOINT" "$installed_root/scripts/ishikawa-observability-retention"
check_result="$work_root/check.txt"
PYTHONDONTWRITEBYTECODE=1 "$installed_root/scripts/ishikawa-observability-retention" --check-config >"$check_result"
grep -Eq '^ishikawa_observability_retention=pass;mode=check-config;policy_digest=[0-9a-f]{64};files_deleted=0$' "$check_result" || {
  printf 'script_97_observability_retention=blocked;reason=installed_check_failed\n' >&2
  exit 1
}
PYTHONDONTWRITEBYTECODE=1 python3 -B - "$installed_root/state/logs" <<'PY'
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

log_root = Path(sys.argv[1])
now = datetime.now(timezone.utc)
for filename, age_days in (
    ("retrieval.jsonl.1", 31),
    ("retrieval.jsonl.2", 29),
    ("metrics.jsonl.1", 31),
    ("audit.jsonl.1", 91),
    ("unrelated.jsonl", 1000),
):
    path = log_root / filename
    path.write_text('{"safe":true}\n', encoding="utf-8")
    os.chmod(path, 0o600)
    timestamp = (now - timedelta(days=age_days)).timestamp()
    os.utime(path, (timestamp, timestamp))
PY
apply_result="$work_root/apply.txt"
PYTHONDONTWRITEBYTECODE=1 "$installed_root/scripts/ishikawa-observability-retention" --apply >"$apply_result"
grep -Fxq 'ishikawa_observability_retention=pass;mode=apply;operational_deleted=1;metrics_deleted=1;audit_deleted=1;files_deleted=3' "$apply_result" || {
  printf 'script_97_observability_retention=blocked;reason=installed_apply_failed\n' >&2
  exit 1
}
[[ ! -e "$installed_root/state/logs/retrieval.jsonl.1" \
   && -f "$installed_root/state/logs/retrieval.jsonl.2" \
   && ! -e "$installed_root/state/logs/metrics.jsonl.1" \
   && ! -e "$installed_root/state/logs/audit.jsonl.1" \
   && -f "$installed_root/state/logs/unrelated.jsonl" \
   && -f "$installed_root/state/logs/audit.jsonl" ]] || {
  printf 'script_97_observability_retention=blocked;reason=installed_deletion_contract_failed\n' >&2
  exit 1
}

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
retention_module_sha256="$(sha256sum "$RETENTION_MODULE" | awk '{print $1}')"
observability_sha256="$(sha256sum "$OBSERVABILITY_MODULE" | awk '{print $1}')"
entrypoint_sha256="$(sha256sum "$RETENTION_ENTRYPOINT" | awk '{print $1}')"
profile_sha256="$(sha256sum "$LOGGING_PROFILE" | awk '{print $1}')"
service_unit_sha256="$(sha256sum "$SERVICE_UNIT" | awk '{print $1}')"
timer_unit_sha256="$(sha256sum "$TIMER_UNIT" | awk '{print $1}')"
contract_sha256="$(sha256sum "$CONTRACT" | awk '{print $1}')"
qualification_sha256="$(sha256sum "$qualification" | awk '{print $1}')"
qualification_bytes="$(stat -c '%s' "$qualification")"

if [[ "$validate_only" == true ]]; then
  cat "$evaluation_result"
  printf '%s\n' \
    'purpose=validate_observability_retention_scheduling' \
    "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256;retention_module_sha256=$retention_module_sha256" \
    "observability_module_sha256=$observability_sha256;entrypoint_sha256=$entrypoint_sha256;logging_profile_sha256=$profile_sha256" \
    "service_unit_sha256=$service_unit_sha256;timer_unit_sha256=$timer_unit_sha256;contract_sha256=$contract_sha256" \
    "qualification_sha256=$qualification_sha256;qualification_bytes=$qualification_bytes" \
    'installed_check=pass;installed_apply=pass;timer_calendar=pass;systemd_unit_verify=pass' \
    'target_contact=false;database_changed=false;model_call=false;credential_read=false;service_changed=false;timer_changed=false' \
    'local_tests=356;failures=0;errors=0' \
    'script_97_observability_retention_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/observability_retention_qualification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  printf 'script_97_observability_retention=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
cp -- "$qualification" "$artifact_path"
printf '%s  %s\n' "$qualification_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true
(
  cd -- "$ARTIFACT_ROOT"
  sha256sum --check --strict "$(basename -- "$checksum_path")" >/dev/null
) || { printf 'script_97_observability_retention=blocked;reason=retained_checksum_failed\n' >&2; exit 1; }
artifact_committed=true

report_path="$(mktemp "$REPORT_ROOT/observability_retention_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
emit 'purpose=qualify_observability_retention_scheduling'
emit "started_utc=$timestamp"
emit "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256;retention_module_sha256=$retention_module_sha256"
emit "observability_module_sha256=$observability_sha256;entrypoint_sha256=$entrypoint_sha256;logging_profile_sha256=$profile_sha256"
emit "service_unit_sha256=$service_unit_sha256;timer_unit_sha256=$timer_unit_sha256;contract_sha256=$contract_sha256"
emit "accepted_script_96_report_sha256=$ACCEPTED_REPORT_SHA256;accepted_script_96_artifact_sha256=$ACCEPTED_ARTIFACT_SHA256"
emit 'authorized_actions=read_checksum_bound_sources_run_local_tests_create_temporary_synthetic_telemetry_delete_only_expired_temporary_telemetry_validate_installed_command_and_timer_retain_content_free_evidence'
emit 'non_actions=no_target_database_model_credential_corpus_package_service_timer_or_forwarding_contact_or_change_no_persistent_process'
while IFS= read -r line; do emit "$line"; done <"$evaluation_result"
emit 'installed_check=pass;installed_apply=pass;timer_calendar=pass;systemd_unit_verify=pass'
emit 'target_contact=false;database_changed=false;model_call=false;credential_read=false;service_changed=false;timer_changed=false'
emit 'local_tests=356;failures=0;errors=0'
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$qualification_sha256;accepted_artifact_bytes=$qualification_bytes;accepted_checksum=$checksum_path"
emit "script_97_observability_retention=pass;local_report=$report_path;next_gate=implement_native_service_lifecycle"
chmod 0600 "$report_path" 2>/dev/null || true
