#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# Purpose:
#   Run the frozen disposable corpus-v3 ingestion and sixty-question Ishikawa
#   v1.3 frontier qualification on EmceeDanko.
#
# Mental model:
#   Verify Script 04 and every local qualification input, reuse one attended
#   SSH connection, transfer a checksum-bound qualification payload, stream the
#   target milestones, fetch and independently validate the synthetic result,
#   then delete the complete target transfer directory.
#
# Inputs or prerequisites:
#   A clean Script 04 report, staged v1.3 and corpus-v3 target inputs, active
#   v1.2 rollback posture, EmceeDanko model forwards on 8000/8001, SSH access,
#   and the Gemma/Nomic API keys entered only at the target's hidden prompts.
#
# Outputs or artifact lane:
#   A local report under local/reports/emceedanko-v1.3-frontier-qualification
#   and an atomically published synthetic-only current qualification artifact.
#   No accepted database, service, autostart, v1.2, or candidate file changes.
#
# Usage:
#   bash ./deployment/scripts/05_qualify-v1.3-on-emceedanko.sh --run

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
readonly target_helper="$repo_root/deployment/assets/qualify-v1.3-candidate"
readonly manifest_generator="$repo_root/deployment/assets/create-corpus-v3-ingestion-config.py"
readonly evaluator="$repo_root/qualification/frontier/evaluate-frontier.py"
readonly frontier_cases="$repo_root/qualification/frontier/frontier-cases.json"
readonly native_test_source="$repo_root/Ishikawa/tests"
readonly native_test_runner="$repo_root/Ishikawa/scripts/run-local-validation-tests.sh"
readonly native_config_source="$repo_root/Ishikawa/config/templates"
readonly native_systemd_source="$repo_root/Ishikawa/packaging/systemd"
readonly application_archive="$repo_root/local/artifacts/ishikawa-v1.3-current/ishikawa-v1.3.tar.gz"
readonly application_sidecar="$application_archive.sha256"
readonly stage_report_root="$repo_root/local/reports/emceedanko-v1.3-candidate-stage"
readonly default_report_root="$repo_root/local/reports/emceedanko-v1.3-frontier-qualification"
readonly default_artifact_parent="$repo_root/local/artifacts"
readonly current_artifact_name='emceedanko-v1.3-frontier-qualification-current'

target="${APPLICATION_HOST_TARGET:-DankoSurface_EmceeDanko}"
expected_hostname="${APPLICATION_HOST_EXPECTED_HOSTNAME:-EmceeDanko}"
expected_os_version="${APPLICATION_HOST_EXPECTED_OS_VERSION:-24.04}"
identity_file="${APPLICATION_HOST_IDENTITY_FILE:-}"
gemma_base_url="${ISHIKAWA_GEMMA_BASE_URL:-http://127.0.0.1:8000}"
nomic_base_url="${ISHIKAWA_NOMIC_BASE_URL:-http://127.0.0.1:8001}"
report_root="${ISHIKAWA_SCRIPT05_REPORT_ROOT:-$default_report_root}"
artifact_parent="${ISHIKAWA_SCRIPT05_ARTIFACT_PARENT:-$default_artifact_parent}"
stage_report_override="${ISHIKAWA_SCRIPT05_STAGE_REPORT:-}"
mode="${1:-}"
shift || true
stage='argument_validation'
report_path=''
work_root=''
publication_stage=''
publication_backup=''
published_current=''
publication_committed=false
remote_root=''
remote_created=false
master_started=false
ssh_args=()
remote_pid=''

usage() {
  printf '%s\n' \
    'Usage: 05_qualify-v1.3-on-emceedanko.sh --validate-only' \
    '       05_qualify-v1.3-on-emceedanko.sh --run [--target SSH_ALIAS]' \
    '              [--identity-file ABSOLUTE_PATH] [--report-root ABSOLUTE_PATH]' \
    '              [--artifact-parent ABSOLUTE_PATH] [--stage-report ABSOLUTE_PATH]' \
    '              [--gemma-base-url http://127.0.0.1:PORT]' \
    '              [--nomic-base-url http://127.0.0.1:PORT]'
}

result() {
  printf '\nSCRIPT RESULT\nscript_05_qualify_v1_3_on_emceedanko=%s\n' "$1"
}

block() {
  local reason="$1" detail="$2" action="$3" payload status="${4:-1}"
  trap - ERR
  payload="$(printf '%s\n' 'FAILURE DETAIL' "stage=$stage" "reason=$reason" \
    "detail=$detail" "operator_action=$action")"
  printf '%s\n' "$payload" >&2
  if [[ -n "$report_path" && -f "$report_path" && ! -L "$report_path" ]]; then
    printf '%s\n' "$payload" >>"$report_path"
    result blocked >>"$report_path"
  fi
  result blocked >&2
  exit "$status"
}

unexpected_error() {
  local status="$1" line="$2"
  trap - ERR
  block unexpected_command_failure \
    "An unhandled command failed at Script 05 line ${line} with exit code ${status}." \
    'Review the retained report and correct the complete failing stage before rerunning Script 05.' \
    "$status"
}

quiet_cleanup() {
  local status="$?"
  trap - ERR EXIT HUP INT TERM
  set +e
  if [[ -n "$remote_pid" ]] && kill -0 "$remote_pid" 2>/dev/null; then
    kill -TERM -- "-$remote_pid" 2>/dev/null || kill -TERM "$remote_pid" 2>/dev/null || true
    for _attempt in {1..100}; do
      kill -0 "$remote_pid" 2>/dev/null || break
      sleep 0.1
    done
    kill -0 "$remote_pid" 2>/dev/null \
      && { kill -KILL -- "-$remote_pid" 2>/dev/null || kill -KILL "$remote_pid" 2>/dev/null || true; }
    wait "$remote_pid" 2>/dev/null || true
  fi
  if [[ "$remote_created" == true && "$master_started" == true ]]; then
    timeout --foreground 120 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
      "rm -rf -- '$remote_root' && test ! -e '$remote_root'" >/dev/null 2>&1
  fi
  if [[ "$master_started" == true ]]; then
    timeout --foreground 10 ssh "${ssh_args[@]}" -O exit "$target" >/dev/null 2>&1
  fi
  if [[ "$publication_committed" == false && -n "$published_current" \
      && "$published_current" == "$artifact_parent/$current_artifact_name" \
      && -d "$published_current" && ! -L "$published_current" ]]; then
    rm -rf -- "$published_current"
  fi
  if [[ "$publication_committed" == false && -n "$publication_backup" \
      && "$publication_backup" == "$artifact_parent/superseded/$current_artifact_name-"* \
      && -d "$publication_backup" && ! -L "$publication_backup" \
      && ! -e "$artifact_parent/$current_artifact_name" \
      && ! -L "$artifact_parent/$current_artifact_name" ]]; then
    mv -- "$publication_backup" "$artifact_parent/$current_artifact_name"
  fi
  [[ -z "$work_root" || "$work_root" != /tmp/ishikawa-script-05.* || ! -d "$work_root" ]] \
    || rm -rf -- "$work_root"
  [[ -z "$publication_stage" || "$publication_stage" != "$artifact_parent"/.emceedanko-v1.3-frontier-qualification-current.* || ! -d "$publication_stage" ]] \
    || rm -rf -- "$publication_stage"
  exit "$status"
}

trap quiet_cleanup EXIT
trap 'stage=interrupted; block signal_hangup "Script 05 received SIGHUP." "Review cleanup and rerun Script 05." 129' HUP
trap 'stage=interrupted; block signal_interrupt "Script 05 was interrupted." "Review cleanup and rerun Script 05." 130' INT
trap 'stage=interrupted; block signal_termination "Script 05 received SIGTERM." "Review cleanup and rerun Script 05." 143' TERM
trap 'unexpected_error "$?" "$LINENO"' ERR

validate_loopback_url() {
  PYTHONDONTWRITEBYTECODE=1 python3 -B - "$1" <<'PY'
import sys
import urllib.parse
value = urllib.parse.urlsplit(sys.argv[1])
if (
    value.scheme != "http" or value.hostname != "127.0.0.1" or value.port is None
    or value.path not in {"", "/"} or value.query or value.fragment
    or value.username is not None or value.password is not None
):
    raise SystemExit(1)
PY
}

if [[ "$mode" == --help || "$mode" == -h ]]; then usage; exit 0; fi
while (( $# > 0 )); do
  case "$1" in
    --target) [[ $# -ge 2 ]] || block target_missing 'The target value is missing.' 'Supply one SSH alias.'; target="$2"; shift 2 ;;
    --expected-hostname) [[ $# -ge 2 ]] || block hostname_missing 'The hostname value is missing.' 'Supply the expected short hostname.'; expected_hostname="$2"; shift 2 ;;
    --expected-os-version) [[ $# -ge 2 ]] || block os_version_missing 'The OS version value is missing.' 'Supply NN.NN.'; expected_os_version="$2"; shift 2 ;;
    --identity-file) [[ $# -ge 2 ]] || block identity_missing 'The identity path is missing.' 'Supply an absolute identity path.'; identity_file="$2"; shift 2 ;;
    --report-root) [[ $# -ge 2 ]] || block report_root_missing 'The report path is missing.' 'Supply an absolute report directory.'; report_root="$2"; shift 2 ;;
    --artifact-parent) [[ $# -ge 2 ]] || block artifact_parent_missing 'The artifact path is missing.' 'Supply an absolute artifact parent.'; artifact_parent="$2"; shift 2 ;;
    --stage-report) [[ $# -ge 2 ]] || block stage_report_missing 'The Script 04 report path is missing.' 'Supply a completed Script 04 report.'; stage_report_override="$2"; shift 2 ;;
    --gemma-base-url) [[ $# -ge 2 ]] || block gemma_url_missing 'The Gemma URL is missing.' 'Supply a bounded loopback base URL.'; gemma_base_url="$2"; shift 2 ;;
    --nomic-base-url) [[ $# -ge 2 ]] || block nomic_url_missing 'The Nomic URL is missing.' 'Supply a bounded loopback base URL.'; nomic_base_url="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) block argument_invalid "Unsupported argument: $1" 'Use --help and rerun.' 2 ;;
  esac
done
[[ "$mode" == --validate-only || "$mode" == --run ]] \
  || block mode_invalid 'Select exactly one mode.' 'Use --validate-only or --run.' 2
[[ "$target" =~ ^[A-Za-z0-9_@.:-]+$ ]] \
  || block target_invalid 'The SSH target is not bounded.' 'Use a configured alias or USER@HOST.' 2
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ \
    && "$expected_os_version" =~ ^[0-9]{2}\.[0-9]{2}$ ]] \
  || block target_expectation_invalid 'The expected host identity is invalid.' 'Correct the expected hostname and OS version.' 2
for path in "$report_root" "$artifact_parent"; do
  [[ "$path" == /* && ! -L "$path" ]] \
    || block output_root_unsafe 'Report and artifact roots must be absolute non-symlink paths.' 'Correct the local output roots.' 2
done
if [[ -n "$identity_file" ]]; then
  [[ "$identity_file" == /* && -f "$identity_file" && ! -L "$identity_file" && -r "$identity_file" ]] \
    || block identity_unsafe 'The SSH identity is missing or unsafe.' 'Correct the identity path or use SSH configuration.' 2
fi
if [[ -n "$stage_report_override" ]]; then
  [[ "$stage_report_override" == /* && -f "$stage_report_override" && ! -L "$stage_report_override" && -r "$stage_report_override" ]] \
    || block stage_report_unsafe 'The explicit Script 04 report is missing or unsafe.' 'Supply one completed Script 04 report.' 2
fi
validate_loopback_url "$gemma_base_url" \
  || block gemma_url_invalid 'Gemma must use a bounded IPv4 loopback HTTP base URL.' 'Correct --gemma-base-url.' 2
validate_loopback_url "$nomic_base_url" \
  || block nomic_url_invalid 'Nomic must use a bounded IPv4 loopback HTTP base URL.' 'Correct --nomic-base-url.' 2

stage='local_preflight'
for command_name in awk bash basename chmod cp date find grep gzip kill mkdir mktemp mv python3 rm scp sed sha256sum sleep sort ssh tail tar tee timeout tr wc xargs; do
  command -v "$command_name" >/dev/null 2>&1 \
    || block "command_missing_${command_name}" "Required local command unavailable: ${command_name}." 'Restore it and rerun Script 05.'
done
for path in "$target_helper" "$manifest_generator" "$evaluator" "$frontier_cases" \
  "$native_test_runner" "$application_archive" "$application_sidecar"; do
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] \
    || block required_file_unsafe "Required Script 05 input is missing or unsafe: ${path}." 'Restore the tracked v1.3 qualification source.'
done
for path in "$native_test_source" "$native_config_source" "$native_systemd_source"; do
  [[ -d "$path" && ! -L "$path" ]] \
    || block required_directory_unsafe "Required native qualification source is missing or unsafe: ${path}." 'Restore the frozen v1.3 test source.'
  find "$path" -type l -print -quit | grep -q . \
    && block native_test_symlink_found "Native qualification source contains a symbolic link: ${path}." 'Restore the tracked source before target contact.'
done
(cd -- "$(dirname -- "$application_archive")" \
  && sha256sum --check --strict "$(basename -- "$application_sidecar")" >/dev/null) \
  || block application_archive_checksum_failed 'The Script 01 application handoff failed checksum verification.' 'Rebuild Script 01 before target qualification.'
bash -n "${BASH_SOURCE[0]}" "$target_helper" \
  || block shell_syntax_invalid 'Script 05 or its target helper failed shell parsing.' 'Correct every parse error before target contact.'
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"),item,"exec") for item in sys.argv[1:]]' \
  "$manifest_generator" "$evaluator" \
  || block python_syntax_invalid 'The manifest generator or frontier evaluator failed Python compilation.' 'Correct it before target contact.'
bash "$target_helper" --self-test \
  | grep -Fxq 'qualify_v1_3_candidate_self_test=pass' \
  || block helper_self_test_failed 'The target helper failed its local self-test.' 'Correct the helper before target contact.'
PYTHONDONTWRITEBYTECODE=1 python3 -B "$manifest_generator" --self-test \
  | grep -Fxq 'corpus_v3_ingestion_config_self_test=pass' \
  || block manifest_generator_self_test_failed 'The per-run corpus manifest generator failed its self-test.' 'Correct it before target contact.'
PYTHONDONTWRITEBYTECODE=1 python3 -B "$evaluator" --self-test \
  | grep -Fxq 'v1_3_complete_api_evaluator_self_test=pass' \
  || block evaluator_self_test_failed 'The frontier evaluator failed its self-test.' 'Correct it before target contact.'
case_validation="$(PYTHONDONTWRITEBYTECODE=1 python3 -B "$evaluator" \
  --validate-cases --cases "$frontier_cases")" \
  || block frontier_case_validation_failed 'The tracked frontier case set failed its validator.' 'Restore the frozen sixty-question set.'
[[ "$case_validation" =~ ^v1_3_complete_api_case_set=pass\;cases=60\;responsive=60\;nonresponsive=0\;broad_navigation=0\;required_evidence=60\;identity=[0-9a-f]{64}$ ]] \
  || block frontier_case_contract_invalid 'The frontier validator omitted its exact sixty-case result.' 'Restore the evaluator and frozen case set.'
stage_report="$stage_report_override"
if [[ -z "$stage_report" ]]; then
  stage_report="$(find "$stage_report_root" -maxdepth 1 -type f -name 'stage_v1_3_candidate_*.txt' -printf '%T@ %p\n' \
    | sort -nr | awk 'NR==1{sub(/^[^ ]+ /,""); print}')"
fi
[[ -n "$stage_report" && -f "$stage_report" && ! -L "$stage_report" ]] \
  || block stage_report_missing 'No completed Script 04 stage report exists.' 'Run Script 04 before Script 05.'
for fact in \
  '[CANDIDATE] active_v1_2_preserved=true;rollback_tree_preserved=true;active_service_unchanged=true;ports_3000_1384_unchanged=true' \
  '[CANDIDATE] database_changed=false;service_changed=false;boot_autostart_changed=false;model_contact=false;credential_read=false' \
  '[CANDIDATE] ishikawa_v1_3_candidate_stage=pass' \
  'script_04_stage_v1_3_candidate_on_emceedanko=pass'; do
  grep -Fxq "$fact" "$stage_report" \
    || block stage_report_contract_invalid "Script 04 report lacks required fact: ${fact}." 'Rerun and review Script 04 before qualification.'
done
stage_report_sha256="$(sha256sum -- "$stage_report" | awk '{print $1}')"
staged_application_sha256="$(sed -n 's/^\[READINESS\] application_archive_sha256=\([0-9a-f]\{64\}\);.*/\1/p' "$stage_report" | tail -n 1)"
local_application_sha256="$(sha256sum -- "$application_archive" | awk '{print $1}')"
[[ -n "$staged_application_sha256" && "$local_application_sha256" == "$staged_application_sha256" ]] \
  || block staged_application_identity_mismatch 'The local Script 01 handoff no longer matches the application archive staged by Script 04.' 'Restore or rebuild and restage the exact v1.3 application before qualification.'

work_root="$(mktemp -d /tmp/ishikawa-script-05.XXXXXX)"
mkdir -p -- "$work_root/payload/database" \
  "$work_root/payload/native-tests/tests" \
  "$work_root/payload/native-tests/config/templates" \
  "$work_root/payload/native-tests/packaging/systemd" \
  "$work_root/config-probe"
tar -xzf "$application_archive" -C "$work_root/config-probe" \
  ishikawa-v1.3/application/payload \
  || block private_configuration_extraction_failed 'The Script 01 application payload could not be extracted for its private-port preflight.' 'Rebuild the exact v1.3 application before target contact.'
probe_product="$work_root/config-probe/ishikawa-v1.3/application/payload"
PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$probe_product/config/deployment.yaml" \
  "$probe_product/config/retrieval_service_profile.yaml" <<'PY' \
  || block private_configuration_generation_failed 'The local private-port preflight configuration could not be generated.' 'Correct the qualification configuration before target contact.'
from pathlib import Path
import sys
import yaml

deployment_path, service_path = map(Path, sys.argv[1:])
deployment = yaml.safe_load(deployment_path.read_text(encoding="utf-8"))
deployment["web"]["retrieval_base_url"] = "http://127.0.0.1:1385"
deployment["retrieval"]["port"] = 1385
deployment["postgresql"]["port"] = 65438
deployment_path.write_text(yaml.safe_dump(deployment, sort_keys=False), encoding="utf-8")
service = yaml.safe_load(service_path.read_text(encoding="utf-8"))
service["network"]["default_port"] = 1385
service_path.write_text(yaml.safe_dump(service, sort_keys=False), encoding="utf-8")
PY
env -u ISHIKAWA_GEMMA_API_KEY -u ISHIKAWA_NOMIC_API_KEY \
  -u ISHIKAWA_POSTGRESQL_PASSWORD \
  "$probe_product/scripts/ishikawa-retrieval-api" --check-config \
  >"$work_root/private-check-config.stdout" 2>"$work_root/private-check-config.stderr" \
  || block private_configuration_invalid 'The exact Script 01 application rejected the reserved private ports before target contact.' 'Rebuild v1.3 with V13-71 and rerun Script 04 before Script 05.'
grep -Eq '^ishikawa_retrieval_api_configuration=pass;policy_digest=[0-9a-f]{64};credential_read=false;dependency_contact=false$' \
  "$work_root/private-check-config.stdout" \
  || block private_configuration_marker_invalid 'The exact Script 01 application omitted its private-port configuration pass marker.' 'Treat the application as unqualified and inspect the local preflight.'
cp -- "$target_helper" "$work_root/payload/qualify-v1.3-candidate"
cp -- "$manifest_generator" "$work_root/payload/create-corpus-v3-ingestion-config.py"
cp -- "$evaluator" "$work_root/payload/evaluate-frontier.py"
cp -- "$native_test_runner" "$work_root/payload/native-tests/run-local-validation-tests.sh"
find "$native_test_source" -maxdepth 1 -type f -name 'test_*.py' -print0 \
  | sort -z | xargs -0 -r cp -t "$work_root/payload/native-tests/tests/" --
cp -a -- "$native_test_source/fixtures" "$work_root/payload/native-tests/tests/fixtures"
find "$native_config_source" -maxdepth 1 -type f -name '*.yaml' -print0 \
  | sort -z | xargs -0 -r cp -t "$work_root/payload/native-tests/config/templates/" --
find "$native_systemd_source" -maxdepth 1 -type f -print0 \
  | sort -z | xargs -0 -r cp -t "$work_root/payload/native-tests/packaging/systemd/" --
[[ "$(find "$work_root/payload/native-tests/tests" -maxdepth 1 -type f -name 'test_*.py' | wc -l | tr -d ' ')" == 41 ]] \
  || block native_test_inventory_invalid 'The qualification payload did not contain exactly 41 canonical test modules.' 'Restore the frozen v1.3 test source before target contact.'
mkdir -p -- "$work_root/release-database"
for file in README.md install-schema schema.sql SHA256SUMS; do
  tar -xOf "$application_archive" "ishikawa-v1.3/database/$file" \
    >"$work_root/release-database/$file" \
    || block database_payload_extraction_failed "The shipped database payload omitted ${file}." 'Rebuild Script 01 before target qualification.'
done
chmod 0700 "$work_root/release-database/install-schema"
(cd -- "$work_root/release-database" && sha256sum --check --strict SHA256SUMS >/dev/null) \
  || block database_payload_checksum_failed 'The database installer inside the Script 01 release failed checksum verification.' 'Rebuild Script 01 before target qualification.'
cp -- "$work_root/release-database/README.md" "$work_root/release-database/install-schema" \
  "$work_root/release-database/schema.sql" "$work_root/release-database/SHA256SUMS" \
  "$work_root/payload/database/"
[[ -x "$work_root/payload/database/install-schema" ]] \
  || block database_installer_mode_invalid 'The assembled shipped database installer is not executable.' 'Correct the payload assembly before target contact.'
tar -xOf "$application_archive" ishikawa-v1.3/application/SHA256SUMS \
  | awk '$2 ~ /^payload\// {sub(/^payload\//, "", $2); print $1 "  " $2}' \
  >"$work_root/payload/candidate-SHA256SUMS"
[[ -s "$work_root/payload/candidate-SHA256SUMS" ]] \
  || block candidate_manifest_missing 'The Script 01 handoff did not yield an installed-candidate checksum manifest.' 'Rebuild Script 01 before target qualification.'
(cd -- "$work_root/payload" && find . -type f ! -name SHA256SUMS -printf '%P\n' | sort \
  | while IFS= read -r file; do sha256sum -- "$file"; done >SHA256SUMS)
(cd -- "$work_root/payload" && sha256sum --check --strict SHA256SUMS >/dev/null) \
  || block qualification_payload_checksum_failed 'The locally assembled qualification payload failed checksum verification.' 'Correct the local assembly before target contact.'
tar --sort=name --format=posix --mtime='UTC 2026-10-24' --owner=0 --group=0 --numeric-owner \
  --pax-option=delete=atime,delete=ctime -C "$work_root" -cf - payload \
  | gzip -n >"$work_root/qualification-payload.tar.gz"
payload_sha256="$(sha256sum -- "$work_root/qualification-payload.tar.gz" | awk '{print $1}')"

if [[ "$mode" == --validate-only ]]; then
  printf '%s\n' \
    'purpose=validate_emceedanko_disposable_v1_3_frontier_qualification' \
    "stage_report_sha256=$stage_report_sha256;qualification_payload_sha256=$payload_sha256" \
    "$case_validation" \
    'private_configuration=pass;retrieval_port=1385;postgresql_port=65438' \
    'target_contact=false;credential_read=false;database_contact=false;model_contact=false;service_changed=false' \
    'active_v1_2_required=true;accepted_database_contact=false;frontier_cases=60' 
  result ready
  exit 0
fi

stage='report_setup'
mkdir -p -- "$report_root" "$artifact_parent/superseded"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$report_root/qualify_v1_3_${timestamp}_XXXXXX.txt")"
emit() {
  local message="$1" tag="${2:-READINESS}"
  printf '[%s] %s\n' "$tag" "$message" | tee -a "$report_path"
}
emit "report_path=$report_path;state=start" READINESS
emit 'purpose=qualify_staged_ishikawa_v1_3_and_corpus_v3_on_emceedanko' READINESS
emit "stage_report_sha256=$stage_report_sha256;qualification_payload_sha256=$payload_sha256" READINESS
emit "$case_validation" READINESS
emit 'authorized_actions=authenticate_transfer_verify_start_private_postgresql_chunk_embed_ingest_start_private_retrieval_api_run_sixty_frontier_cases_fetch_synthetic_result_cleanup' READINESS
emit 'non_actions=no_v1_2_change_no_accepted_database_contact_no_candidate_mutation_no_service_install_no_boot_autostart_no_black_corpus_no_org_lab_contact_no_credential_retention' READINESS
emit 'expected_duration=approximately_30_to_60_minutes;prompts=ssh_private_key_passphrase_then_hidden_gemma_api_key_then_hidden_nomic_api_key;heartbeat_max_seconds=25' READINESS

stage='authentication'
emit 'state=waiting_for_ssh_private_key_passphrase_if_prompted' AUTHENTICATION
control_path="/tmp/is05-${timestamp}-%C"
ssh_args=(-o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 \
  -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto \
  -o "ControlPath=$control_path" -o ControlPersist=300)
[[ -z "$identity_file" ]] || ssh_args+=(-i "$identity_file" -o IdentitiesOnly=yes)
ssh -G "${ssh_args[@]}" "$target" >/dev/null \
  || block ssh_configuration_invalid 'OpenSSH rejected the bounded connection configuration.' 'Correct the target or identity and rerun Script 05.'
timeout --foreground 120 ssh "${ssh_args[@]}" -Nf "$target" \
  || block ssh_master_start_failed 'SSH authentication or connection failed.' 'Correct SSH access and rerun Script 05.'
master_started=true
timeout --foreground 10 ssh "${ssh_args[@]}" -O check "$target" >/dev/null \
  || block ssh_master_check_failed 'The authenticated SSH control master was not ready.' 'Correct SSH access and rerun Script 05.'
emit 'state=pass;control_master=ready' AUTHENTICATION

stage='transfer'
remote_root="/tmp/ishikawa-v1.3-qualification-${timestamp}-$$"
timeout --foreground 30 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "test ! -e '$remote_root' && mkdir -m 0700 -- '$remote_root'" >/dev/null \
  || block remote_directory_failed 'The private target transfer directory could not be created.' 'Review target permissions and rerun Script 05.'
remote_created=true
emit 'state=start;payload=qualification-only' TRANSFER
timeout --foreground 180 scp "${ssh_args[@]}" "$work_root/qualification-payload.tar.gz" \
  "$target:$remote_root/" >/dev/null \
  || block transfer_failed 'The checksum-bound qualification payload failed to transfer.' 'Correct transport and rerun Script 05.'
timeout --foreground 60 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "cd '$remote_root' && printf '%s  %s\n' '$payload_sha256' 'qualification-payload.tar.gz' | sha256sum --check --strict - >/dev/null && tar -xzf qualification-payload.tar.gz && cd payload && sha256sum --check --strict SHA256SUMS >/dev/null" \
  || block transferred_payload_invalid 'Target-side qualification payload verification failed.' 'Do not qualify; correct the transfer and rerun.'
emit 'state=pass;target_checksum=pass' TRANSFER

stage='target_qualification'
emit 'state=start;next_prompt=gemma_api_key;then=nomic_api_key;credential_input_hidden=true;accepted_database_contact=false' QUALIFICATION
if ssh -tt "${ssh_args[@]}" -o BatchMode=yes "$target" \
    "cd '$remote_root/payload' && bash ./qualify-v1.3-candidate --run --expected-hostname '$expected_hostname' --expected-os-version '$expected_os_version' --expected-architecture amd64 --payload-root '$remote_root/payload' --result-path '$remote_root/payload/target-result.txt' --artifact-path '$remote_root/payload/frontier-result.json' --gemma-base-url '$gemma_base_url' --nomic-base-url '$nomic_base_url'" \
    </dev/tty 2>&1 | tee -a "$report_path"; then
  remote_status=0
else
  pipeline_status=("${PIPESTATUS[@]}")
  remote_status="${pipeline_status[0]}"
fi

stage='result_fetch'
timeout --foreground 60 scp "${ssh_args[@]}" \
  "$target:$remote_root/payload/target-result.txt" "$work_root/target-result.txt" >/dev/null \
  || block target_result_fetch_failed 'The content-safe target result could not be fetched.' 'Review the streamed target output and SSH connection before rerunning.'
tee -a "$report_path" <"$work_root/target-result.txt" >/dev/null
if [[ "$remote_status" -ne 0 ]]; then
  target_reason="$(sed -n 's/^reason=\([a-z0-9_]*\)$/\1/p' "$work_root/target-result.txt" | tail -n 1)"
  target_stage="$(sed -n 's/^stage=\([a-z0-9_]*\)$/\1/p' "$work_root/target-result.txt" | tail -n 1)"
  target_root_cause="$(sed -n 's/^root_cause=\([a-z0-9_]*\)$/\1/p' "$work_root/target-result.txt" | tail -n 1)"
  target_detail="$(sed -n 's/^detail=\(.*\)$/\1/p' "$work_root/target-result.txt" | tail -n 1)"
  target_action="$(sed -n 's/^operator_action=\(.*\)$/\1/p' "$work_root/target-result.txt" | tail -n 1)"
  if [[ -n "$target_root_cause" && "$target_detail" != *"root_cause=${target_root_cause}"* ]]; then
    target_detail="${target_detail:-The target qualification failed.};root_cause=${target_root_cause}."
  fi
  stage="target_${target_stage:-qualification}"
  block "${target_reason:-remote_qualification_failed}" \
    "${target_detail:-The target helper exited with status ${remote_status}.}" \
    "${target_action:-Use the streamed target stage and rerun Script 05 after correcting all conditions.}" \
    "$remote_status"
fi
for fact in \
  'active_v1_2_preserved=true;accepted_database_contact=false;candidate_mutated=false;boot_autostart_changed=false' \
  'cleanup=pass;temporary_postgresql_removed=true;temporary_api_stopped=true;qualification_ports_free=true' \
  'native_qualification=pass;tests=486' \
  'corpus_v3_ingestion=pass;documents=30;pages=150;authoritative_chunks=786;retrieval_candidates=943;retrieval_scoring_only=157;embeddings=943;relationship_records=240;relationship_pairs=90' \
  'frontier_qualification=pass;cases=60/60;required_evidence_returned=60/60;required_evidence_cited=60/60;dependency_failures=0' \
  'ishikawa_v1_3_emceedanko_disposable_qualification=pass'; do
  grep -Fxq "$fact" "$work_root/target-result.txt" \
    || block target_result_contract_invalid "Target result lacks required fact: ${fact}." 'Treat qualification as blocked and inspect the streamed target output.'
done
timeout --foreground 180 scp "${ssh_args[@]}" \
  "$target:$remote_root/payload/frontier-result.json" "$work_root/frontier-result.json" >/dev/null \
  || block frontier_artifact_fetch_failed 'The synthetic frontier artifact could not be fetched.' 'Do not accept the target result; correct transport and rerun.'
emit 'state=pass;target_result=pass;synthetic_artifact=fetched' QUALIFICATION

stage='artifact_validation'
PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$work_root/frontier-result.json" "$expected_hostname" "$expected_os_version" <<'PY' \
  || block frontier_artifact_invalid 'The fetched synthetic artifact failed independent validation.' 'Do not publish; restore the exact target evaluator and rerun Script 05.'
import json
import pathlib
import sys
path, expected_hostname, expected_os_version = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
data = json.loads(path.read_text(encoding="utf-8"))
summary = data["summary"]
assert data["artifact_kind"] == "ishikawa_v1_3_complete_api_qualification"
assert data["synthetic_content_only"] is True
assert data["target"] == {
    "architecture": "amd64", "hostname": expected_hostname,
    "os_id": "ubuntu", "os_version": expected_os_version,
}
assert summary["acceptance_gate"] == "pass"
assert summary["case_count"] == 60
assert summary["contract_valid_count"] == 60
assert summary["expected_status_match_count"] == 60
assert summary["required_evidence_count"] == 60
assert summary["required_evidence_returned_count"] == 60
assert summary["required_evidence_cited_count"] == 60
assert summary["dependency_failure_count"] == 0
assert len(data["cases"]) == 60
PY
artifact_sha256="$(sha256sum -- "$work_root/frontier-result.json" | awk '{print $1}')"
emit "state=pass;artifact_sha256=$artifact_sha256" VERIFY

stage='publication'
emit 'state=start;artifact=synthetic_only_target_qualification' PUBLISH
publication_stage="$artifact_parent/.${current_artifact_name}.${timestamp}.$$"
mkdir -p -- "$publication_stage"
cp -- "$work_root/frontier-result.json" "$publication_stage/frontier-result.json"
cp -- "$work_root/target-result.txt" "$publication_stage/target-result.txt"
PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$publication_stage/receipt.json" "$artifact_sha256" "$payload_sha256" \
  "$stage_report_sha256" "$target" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
receipt = {
    "accepted_database_contact": False,
    "active_v1_2_preserved": True,
    "application_release": "Ishikawa v1.3",
    "candidate_mutated": False,
    "corpus_identity": "synthetic-corpus-v3",
    "frontier_artifact_sha256": sys.argv[2],
    "frontier_cases": 60,
    "qualification_payload_sha256": sys.argv[3],
    "qualification_scope": "disposable_target_runtime",
    "schema_version": 1,
    "script_04_report_sha256": sys.argv[4],
    "status": "pass",
    "synthetic_content_only": True,
    "target_alias": sys.argv[5],
}
path.write_text(json.dumps(receipt, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
PY
(cd -- "$publication_stage" && find . -type f ! -name SHA256SUMS -printf '%P\n' | sort \
  | while IFS= read -r file; do sha256sum -- "$file"; done >SHA256SUMS)
(cd -- "$publication_stage" && sha256sum --check --strict SHA256SUMS >/dev/null) \
  || block publication_checksum_failed 'The staged local qualification artifact failed checksum verification.' 'Do not publish; inspect the local result assembly.'
current_root="$artifact_parent/$current_artifact_name"
backup=''
if [[ -e "$current_root" || -L "$current_root" ]]; then
  [[ -d "$current_root" && ! -L "$current_root" ]] \
    || block current_artifact_unsafe 'The current qualification artifact path is unsafe.' 'Inspect it before publication.'
  backup="$artifact_parent/superseded/${current_artifact_name}-${timestamp}"
  [[ ! -e "$backup" && ! -L "$backup" ]] \
    || block superseded_artifact_exists 'The superseded artifact destination already exists.' 'Inspect the artifact lane before rerunning.'
  mv -- "$current_root" "$backup"
  publication_backup="$backup"
fi
mv -- "$publication_stage" "$current_root"
publication_stage=''
published_current="$current_root"
(cd -- "$current_root" && sha256sum --check --strict SHA256SUMS >/dev/null) \
  || block published_artifact_invalid 'The published qualification artifact failed final verification.' 'Do not continue to human UI validation.'
publication_committed=true
publication_backup=''
emit "state=pass;current_artifact=$current_root;artifact_sha256=$artifact_sha256" PUBLISH

stage='remote_cleanup'
emit 'state=start' CLEANUP
timeout --foreground 120 ssh "${ssh_args[@]}" -o BatchMode=yes "$target" \
  "rm -rf -- '$remote_root' && test ! -e '$remote_root'" >/dev/null \
  || block remote_cleanup_failed 'The temporary target transfer could not be removed.' 'Inspect the exact /tmp transfer path before continuing.'
remote_created=false
emit 'state=pass;temporary_transfer_removed=true;payload_bytes_deleted=true' CLEANUP

stage='complete'
emit "local_report=$report_path;current_artifact=$current_root;next_gate=attended_v1_3_human_ui_validation_on_emceedanko" SUMMARY
result pass | tee -a "$report_path"
