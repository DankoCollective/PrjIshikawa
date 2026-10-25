#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Run the complete 13-case Retrieval API/Gemma gate against the exact
#   Script 180-qualified Ishikawa v1.3 candidate and synthetic corpus v2.
#
# Boundaries:
#   Existing loopback Gemma/Nomic endpoints and one disposable PostgreSQL 16
#   cluster only. The cluster is populated through the real ingestion pipeline
#   and always removed. No accepted database, corpus, package, release, remote
#   host, black corpus, service, or org-lab state is changed.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/181_qualify_v1_3_complete_retrieval_api_and_gemma.sh --run

usage() {
  sed -n '3,16p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Execute the complete v1.3 API/Gemma gate.' \
    '  --validate-only Validate frozen inputs and local contracts only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly PACKAGE_ROOT="$PYTHON_ROOT/ishikawa"
readonly WEB_ROOT="$PRODUCT_ROOT/application/web"
readonly CONFIG_ROOT="$PRODUCT_ROOT/config/templates"
readonly SERVICE_ENTRYPOINT="$PRODUCT_ROOT/scripts/ishikawa-retrieval-api"
readonly TEST_RUNNER="$PRODUCT_ROOT/scripts/run-local-validation-tests.sh"
readonly SCHEMA="$PRODUCT_ROOT/packaging/database/schema.sql"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_v1_3_complete_api.py"
readonly CASES="$PHASE_ROOT/reference/ishikawa-retrieval-api-cases-v1.3.json"
readonly INGESTION_RUNNER="$SCRIPT_DIR/run_isolated_synthetic_v2_ingestion.py"
readonly PIPELINE_EXECUTABLE="$SCRIPT_DIR/ishikawa-produce-artifacts"
readonly PROMOTION_BUNDLE="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-promotion/synthetic_corpus_v2_promotion_candidate_20261022T201026Z"
readonly SCRIPT_179_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.3-v13-32-application-implementation/v13_32_application_implementation_20261023T002814Z_aNSicw.txt"
readonly SCRIPT_180_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.3-v13-32-implemented-retrieval/implemented_retrieval_20261023T004802Z_f3cbyT.txt"
readonly SCRIPT_180_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/v1.3-v13-32-implemented-retrieval/implemented_retrieval_20261023T004802Z_f3cbyT.json"
readonly SCRIPT_180_CHECKSUM="$SCRIPT_180_ARTIFACT.sha256"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.3-complete-api-gemma"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v1.3-complete-api-gemma"
readonly INITDB='/usr/lib/postgresql/16/bin/initdb'
readonly PG_CTL='/usr/lib/postgresql/16/bin/pg_ctl'
readonly CREATEDB='/usr/lib/postgresql/16/bin/createdb'
readonly PSQL='/usr/lib/postgresql/16/bin/psql'
readonly TEMPORARY_POSTGRESQL_PORT=65437
readonly API_ENDPOINT='http://127.0.0.1:1384/v1/chat'
readonly GEMMA_HEALTH_URL='http://127.0.0.1:8000/health'
readonly NOMIC_HEALTH_URL='http://127.0.0.1:8001/health'

readonly EVALUATOR_SHA256='8a86d9f3fb79a10abd67b6b1e7ba400fb60fdbb26eca3db675c7a02ad5b06e15'
readonly CASES_SHA256='b181d2d83f50270c743032c3de19322de070fd906a9e356d0890e794528e2907'
readonly DECISIONS_SHA256='9c0b17b26e22298929a87b1d10ea6faca730efa9e953b0862497a4c8a244ba3b'
readonly SCHEMA_SHA256='3b55d00880e6e09e401e282b7f62314fb635c6a859c23ad3e87c58aa23237e8b'
readonly INGESTION_RUNNER_SHA256='147b415d09f76d869d8da75a5ef07f9525fa54d7a6d034ab3d1829ca51687591'
readonly PIPELINE_EXECUTABLE_SHA256='0faa5c65fbf8af454040158813308fb239ec70535bd956c3ffbc0523f5904b94'
readonly PROMOTION_MANIFEST_SHA256='614c4ce64597aeed7d0d03da8dcbef0d59db052dbd3c56092a33e86fd40d42f5'
readonly SCRIPT_179_REPORT_SHA256='f98927ac0258ca982a9cd44bcbbb91e3e4026f66d3f2cdb1778f10570ea78f6a'
readonly SCRIPT_180_REPORT_SHA256='684e14a3fba069dc92981b961c8cf16471c13339f3e579956105a274ab1206d1'
readonly SCRIPT_180_ARTIFACT_SHA256='edc0b69ce84b5cb5c0c8736770b535bb4d44ea8ca2c6f975e6a64d38a3a456c1'
readonly SCRIPT_180_CHECKSUM_SHA256='4641dbdef8c147ab1a6fdcfb0f94dfc699b6b83b35ee539aca41a97d59c9cdca'
readonly APPLICATION_MANIFEST_SHA256='96cccc64757d9c736d0798c6cfe4c3f6b4cda29754f25d1bee38245c4a93bb25'
readonly APPLICATION_FILE_COUNT=174
readonly EXPECTED_HOSTNAME='DankoSurface'
readonly EXPECTED_OS_VERSION='24.04'
readonly EXPECTED_ARCHITECTURE='aarch64'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      printf 'reason=argument_invalid\n\nSCRIPT RESULT\nscript_181_v1_3_complete_api_gemma=blocked\n' >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'reason=mode_invalid\n\nSCRIPT RESULT\nscript_181_v1_3_complete_api_gemma=blocked\n' >&2
  exit 2
}

preflight_block() {
  printf 'reason=%s\n\nSCRIPT RESULT\nscript_181_v1_3_complete_api_gemma=blocked\n' "$1" >&2
  exit "${2:-2}"
}

for command_name in awk bash basename chmod cp curl date dirname env find grep \
  head hostname id install kill mkdir mktemp python3 rm sed seq sha256sum \
  sleep sort ss stat tail tar tee timeout tr uname wc; do
  command -v "$command_name" >/dev/null 2>&1 \
    || preflight_block "local_command_missing_$command_name"
done
for executable in "$INITDB" "$PG_CTL" "$CREATEDB" "$PSQL"; do
  [[ -f "$executable" && ! -L "$executable" && -x "$executable" ]] \
    || preflight_block postgresql_16_binary_unsafe
done

check_file() {
  local path="$1" expected="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] \
    || preflight_block "${label}_unsafe"
  [[ "$(sha256sum "$path" | awk '{print $1}')" == "$expected" ]] \
    || preflight_block "${label}_identity_changed"
}

check_file "$EVALUATOR" "$EVALUATOR_SHA256" evaluator
check_file "$CASES" "$CASES_SHA256" case_set
check_file "$DECISIONS" "$DECISIONS_SHA256" decisions
check_file "$SCHEMA" "$SCHEMA_SHA256" schema_v5
check_file "$INGESTION_RUNNER" "$INGESTION_RUNNER_SHA256" ingestion_runner
check_file "$PIPELINE_EXECUTABLE" "$PIPELINE_EXECUTABLE_SHA256" pipeline_executable
check_file "$PROMOTION_BUNDLE/SHA256SUMS" "$PROMOTION_MANIFEST_SHA256" promotion_manifest
check_file "$SCRIPT_179_REPORT" "$SCRIPT_179_REPORT_SHA256" script_179_report
check_file "$SCRIPT_180_REPORT" "$SCRIPT_180_REPORT_SHA256" script_180_report
check_file "$SCRIPT_180_ARTIFACT" "$SCRIPT_180_ARTIFACT_SHA256" script_180_artifact
check_file "$SCRIPT_180_CHECKSUM" "$SCRIPT_180_CHECKSUM_SHA256" script_180_checksum
[[ -x "$PIPELINE_EXECUTABLE" && -x "$SERVICE_ENTRYPOINT" && -x "$TEST_RUNNER" ]] \
  || preflight_block executable_input_invalid
[[ -d "$PROMOTION_BUNDLE" && ! -L "$PROMOTION_BUNDLE" ]] \
  || preflight_block promotion_bundle_unsafe
(cd -- "$PROMOTION_BUNDLE" && sha256sum --quiet -c SHA256SUMS) \
  || preflight_block promotion_bundle_checksum_failed 1
(cd -- "$(dirname -- "$SCRIPT_180_ARTIFACT")" \
  && sha256sum --quiet -c "$(basename -- "$SCRIPT_180_CHECKSUM")") \
  || preflight_block script_180_checksum_failed 1

grep -Eq "^\| \`V13-32\` \|.*bf732e402004d70b0aa3318e179fe1a1e14d0bd4a70aaa2b4d71528088b7d518.*\| FROZEN \|$" \
  "$DECISIONS" || preflight_block v13_32_freeze_record_invalid 1
grep -Eq "^\| \`V13-33\` \|.*without changing its frozen weights, depths, corpus, truth, or acceptance thresholds.*\| FROZEN \|$" \
  "$DECISIONS" || preflight_block v13_33_freeze_record_invalid 1
grep -Eq "^\| \`V13-34\` \|.*structural section/page representative counts as one diversity unit.*\| FROZEN \|$" \
  "$DECISIONS" || preflight_block v13_34_freeze_record_invalid 1
grep -Fxq 'script_179_v13_32_application_implementation=pass' \
  "$SCRIPT_179_REPORT" || preflight_block script_179_not_clean 1
grep -Fxq 'script_180_implemented_v13_32_retrieval_gate=pass' \
  "$SCRIPT_180_REPORT" || preflight_block script_180_not_clean 1
grep -Fxq 'next_gate=complete_retrieval_api_and_gemma_evaluation' \
  "$SCRIPT_180_REPORT" || preflight_block script_180_next_gate_invalid 1
for metric in \
  'body_mrr_at_20=0.911667;body_top5=60/60;body_required_evidence=60/60' \
  'header_mrr_at_20=1.000000;header_top5=8/8;header_required_evidence=11/11' \
  'expanded_atomic_diagnostic_mrr_at_20=0.893876;expanded_atomic_top5=56/60;expanded_atomic_required_evidence=60/60;expanded_header_required_evidence=11/11'; do
  grep -Fxq "$metric" "$SCRIPT_180_REPORT" \
    || preflight_block script_180_metric_contract_invalid 1
done

PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$SCRIPT_180_ARTIFACT" "$PROMOTION_BUNDLE/promotion-receipt.json" <<'PY'
import json
import pathlib
import sys

qualification = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert qualification["schema_version"] == 2
assert qualification["qualification_gate_met"] is True
assert qualification["candidate_identity"] == "bf732e402004d70b0aa3318e179fe1a1e14d0bd4a70aaa2b4d71528088b7d518"
assert qualification["next_gate"] == "complete_retrieval_api_and_gemma_evaluation"
assert qualification["metrics"]["body"]["mrr_at_20"] == "0.911667"
assert qualification["metrics"]["body"]["relevant_at_5"] == 60
assert qualification["metrics"]["expanded_atomic_diagnostic"]["authoritative_evidence"] == {
    "body_matched": 60,
    "body_total": 60,
    "header_matched": 11,
    "header_total": 11,
}

promotion = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
assert promotion["schema"] == "ishikawa.synthetic-corpus-v2-promotion-candidate.v1"
assert promotion["corpus_identity"] == "synthetic-corpus-v2"
assert promotion["document_count"] == 6
assert promotion["page_count"] == 26
assert promotion["status"] == "qualified_for_isolated_ingestion"
PY

mapfile -t application_files < <(
  {
    find "$PACKAGE_ROOT" "$PRODUCT_ROOT/tests" \
      "$WEB_ROOT/app" "$WEB_ROOT/components" "$WEB_ROOT/lib" \
      "$WEB_ROOT/public" "$WEB_ROOT/tests" "$CONFIG_ROOT" \
      "$PRODUCT_ROOT/docs" "$PRODUCT_ROOT/packaging/database" \
      -type f ! -path '*/__pycache__/*' ! -path '*/.next/*' \
      ! -name '*.pyc' -print
    printf '%s\n' \
      "$PRODUCT_ROOT/README.md" \
      "$WEB_ROOT/package.json" \
      "$WEB_ROOT/next.config.mjs" \
      "$TEST_RUNNER"
  } | LC_ALL=C sort -u
)
(( ${#application_files[@]} == APPLICATION_FILE_COUNT )) \
  || preflight_block application_file_count_mismatch 1
application_manifest_sha256="$({
  for path in "${application_files[@]}"; do
    [[ -f "$path" && ! -L "$path" && -r "$path" ]] \
      || preflight_block application_source_unsafe 1
    relative="${path#"$PRODUCT_ROOT"/}"
    printf '%s  %s\n' "$(sha256sum "$path" | awk '{print $1}')" "$relative"
  done
} | sha256sum | awk '{print $1}')"
[[ "$application_manifest_sha256" == "$APPLICATION_MANIFEST_SHA256" ]] \
  || preflight_block application_source_identity_changed 1

bash -n "${BASH_SOURCE[0]}" "$SERVICE_ENTRYPOINT" "$PIPELINE_EXECUTABLE"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(pathlib.Path(item).read_text(encoding="utf-8"), item, "exec") for item in sys.argv[1:]]' \
  "$EVALUATOR" "$INGESTION_RUNNER"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" --self-test \
  | grep -Fxq 'v1_3_complete_api_evaluator_self_test=pass' \
  || preflight_block evaluator_self_test_failed
case_validation="$({
  PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" \
    --validate-cases --cases "$CASES"
} 2>&1)" || preflight_block case_set_validation_failed
grep -Eq '^v1_3_complete_api_case_set=pass;cases=13;responsive=6;nonresponsive=6;broad_navigation=1;required_evidence=13;identity=[0-9a-f]{64}$' \
  <<<"$case_validation" || preflight_block case_set_contract_invalid

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_v1_3_complete_retrieval_api_and_gemma_gate' \
    "script_sha256=$script_sha256;evaluator_sha256=$EVALUATOR_SHA256;case_set_sha256=$CASES_SHA256" \
    "script_180_report_sha256=$SCRIPT_180_REPORT_SHA256;script_180_artifact_sha256=$SCRIPT_180_ARTIFACT_SHA256" \
    "application_manifest_sha256=$APPLICATION_MANIFEST_SHA256;application_files=$APPLICATION_FILE_COUNT" \
    'cases=13;responsive=6;nonresponsive=6;broad_navigation=1;required_evidence=13' \
    'database_contact=false;model_contact=false;credential_read=false;service_started=false;corpus_changed=false;package_changed=false;release_changed=false' \
    '' \
    'SCRIPT RESULT' \
    'script_181_v1_3_complete_api_gemma=pass'
  exit 0
fi

umask 077
mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT" \
  || preflight_block local_output_root_creation_failed
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/complete_api_gemma_${timestamp}_XXXXXX.txt")"
suffix="${report_path##*_}"; suffix="${suffix%.txt}"
artifact_path="$ARTIFACT_ROOT/complete_api_gemma_${timestamp}_${suffix}.json"
artifact_checksum_path="$artifact_path.sha256"
diagnostic_bundle_path="$ARTIFACT_ROOT/complete_api_gemma_${timestamp}_${suffix}.diagnostics.tar.gz"
diagnostic_bundle_checksum_path="$diagnostic_bundle_path.sha256"
work_root="$(mktemp -d /tmp/ishikawa-script-181.XXXXXX)"
gemma_key=''
nomic_key=''
database_password='disposable-qualification-database-password'
postgresql_started=false
service_pid=''
evaluator_pid=''
failure_reason=''
failure_observation_retained=false
failure_diagnostics_retained=false
current_stage='runtime_initialization'
readonly MAIN_BASHPID="$BASHPID"

emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
block() { failure_reason="$1"; exit "${2:-1}"; }
record_unexpected_error() {
  local status="$1"
  if [[ "$BASHPID" == "$MAIN_BASHPID" && -z "$failure_reason" ]]; then
    failure_reason="${current_stage}_unexpected_exit_${status}"
  fi
}
handle_signal() { failure_reason="interrupted_$1"; exit "$2"; }
cleanup() {
  local status="$?" result=blocked cleanup_failed=false
  trap - ERR EXIT HUP INT TERM
  set +e
  unset ISHIKAWA_GEMMA_API_KEY ISHIKAWA_NOMIC_API_KEY \
    ISHIKAWA_POSTGRESQL_PASSWORD ISHIKAWA_POSTGRESQL_INGEST_PASSWORD
  gemma_key=''; nomic_key=''; database_password=''
  if [[ "$evaluator_pid" =~ ^[0-9]+$ ]] && kill -0 "$evaluator_pid" 2>/dev/null; then
    kill -TERM "$evaluator_pid" 2>/dev/null || true
    wait "$evaluator_pid" 2>/dev/null || true
  fi
  if [[ "$service_pid" =~ ^[0-9]+$ ]] && kill -0 "$service_pid" 2>/dev/null; then
    kill -TERM "$service_pid" 2>/dev/null || true
    for _ in $(seq 1 20); do
      kill -0 "$service_pid" 2>/dev/null || break
      sleep 0.25
    done
    if kill -0 "$service_pid" 2>/dev/null; then
      kill -KILL "$service_pid" 2>/dev/null || true
      cleanup_failed=true
    fi
    wait "$service_pid" 2>/dev/null || true
  fi
  if [[ "$postgresql_started" == true && "$work_root" == /tmp/ishikawa-script-181.* ]]; then
    "$PG_CTL" -D "$work_root/postgresql" -m fast -w stop >/dev/null 2>&1 \
      || cleanup_failed=true
  fi
  if ss -H -ltn '( sport = :1384 or sport = :65437 )' 2>/dev/null | grep -q .; then
    cleanup_failed=true
  fi
  if (( status != 0 )) \
    && [[ "$work_root" == /tmp/ishikawa-script-181.* && -d "$work_root" ]]; then
    diagnostic_members=()
    for diagnostic_member in \
      evaluator.stdout evaluator.stderr service.stdout service.stderr \
      staged/Ishikawa/state/logs; do
      [[ -e "$work_root/$diagnostic_member" ]] \
        && diagnostic_members+=("$diagnostic_member")
    done
    if (( ${#diagnostic_members[@]} > 0 )) \
      && [[ ! -e "$diagnostic_bundle_path" ]] \
      && tar -C "$work_root" -czf "$diagnostic_bundle_path" \
        -- "${diagnostic_members[@]}"; then
      diagnostic_bundle_sha256="$(sha256sum "$diagnostic_bundle_path" | awk '{print $1}')"
      printf '%s  %s\n' "$diagnostic_bundle_sha256" \
        "$(basename -- "$diagnostic_bundle_path")" \
        >"$diagnostic_bundle_checksum_path"
      failure_diagnostics_retained=true
    fi
  fi
  [[ "$work_root" == /tmp/ishikawa-script-181.* && -d "$work_root" ]] \
    && rm -rf -- "$work_root"
  if [[ "$cleanup_failed" == true ]]; then
    status=1
    [[ -n "$failure_reason" ]] || failure_reason='runtime_cleanup_failed'
  fi
  if (( status == 0 )); then
    result=pass
  else
    [[ -n "$failure_reason" ]] || failure_reason="${current_stage}_unexpected_exit_${status}"
    if [[ "$failure_observation_retained" == false ]]; then
      [[ "$artifact_path" == "$ARTIFACT_ROOT"/* ]] \
        && rm -f -- "$artifact_path" "$artifact_checksum_path"
    fi
  fi
  emit 'milestone=cleanup;state='"$([[ "$cleanup_failed" == false ]] && printf pass || printf blocked)"';temporary_postgresql_removed=true;retrieval_api_stopped=true;ports_free='"$([[ "$cleanup_failed" == false ]] && printf true || printf false)"
  if [[ "$failure_diagnostics_retained" == true ]]; then
    emit "diagnostic_bundle=$diagnostic_bundle_path;diagnostic_bundle_sha256=$diagnostic_bundle_sha256;synthetic_content_only=true"
  fi
  emit "local_report=$report_path"
  {
    printf '\nSCRIPT RESULT\n'
    [[ "$result" == pass ]] || printf 'reason=%s\n' "$failure_reason"
    printf 'script_181_v1_3_complete_api_gemma=%s\n' "$result"
  } | tee -a "$report_path"
  exit "$status"
}
trap 'record_unexpected_error $?' ERR
trap cleanup EXIT
trap 'handle_signal HUP 129' HUP
trap 'handle_signal INT 130' INT
trap 'handle_signal TERM 143' TERM

read_secret() {
  local label="$1" destination="$2" value=''
  [[ -r /dev/tty && -w /dev/tty ]] || block interactive_terminal_unavailable
  IFS= read -r -s -p "$label: " value </dev/tty || block secret_entry_failed
  printf '\n' >/dev/tty
  (( ${#value} >= 1 && ${#value} <= 4096 )) || block secret_value_invalid
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || block secret_value_invalid
  printf -v "$destination" '%s' "$value"
  value=''
}

emit 'purpose=qualify_v1_3_complete_retrieval_api_and_gemma'
emit "started_utc=$timestamp;script_sha256=$script_sha256;evaluator_sha256=$EVALUATOR_SHA256"
emit "candidate_identity=bf732e402004d70b0aa3318e179fe1a1e14d0bd4a70aaa2b4d71528088b7d518;script_180_artifact_sha256=$SCRIPT_180_ARTIFACT_SHA256"
emit 'authorized_actions=call_existing_loopback_gemma_and_nomic_start_disposable_postgresql_ingest_synthetic_corpus_v2_start_temporary_retrieval_api_execute_13_case_api_gate_retain_synthetic_evidence'
emit 'non_actions=no_accepted_database_contact_no_persistent_database_mutation_no_corpus_v1_or_v2_mutation_no_black_corpus_no_remote_host_no_package_or_release_change_no_service_install_or_autostart'

current_stage=readiness
ss -H -ltn '( sport = :1384 or sport = :65437 )' | grep -q . \
  && block qualification_port_in_use
gemma_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
  --connect-timeout 5 --max-time 10 "$GEMMA_HEALTH_URL" 2>/dev/null || true)"
nomic_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
  --connect-timeout 5 --max-time 10 "$NOMIC_HEALTH_URL" 2>/dev/null || true)"
[[ "$gemma_status" == 200 ]] || block gemma_forward_unavailable
[[ "$nomic_status" == 200 ]] || block nomic_forward_unavailable
emit 'milestone=readiness;state=pass;gemma=pass;nomic=pass;ports=free'

current_stage=credential_read
read_secret 'Gemma API key' gemma_key
read_secret 'Nomic API key' nomic_key
emit 'milestone=credentials;state=accepted;values_logged=false;values_retained=false'

current_stage=temporary_postgresql
mkdir -m 0700 -- "$work_root/socket" "$work_root/runtime-config" \
  "$work_root/producer-work" "$work_root/operator-reports" \
  "$work_root/retained-artifacts" "$work_root/staged"
"$INITDB" -D "$work_root/postgresql" --username="$(id -un)" \
  --encoding=UTF8 --no-locale --auth=trust \
  >"$work_root/initdb.stdout" 2>"$work_root/initdb.stderr" \
  || block temporary_postgresql_initialization_failed
"$PG_CTL" -D "$work_root/postgresql" \
  -o "-k $work_root/socket -h 127.0.0.1 -p $TEMPORARY_POSTGRESQL_PORT -c fsync=off -c synchronous_commit=off -c full_page_writes=off" \
  -l "$work_root/postgresql.log" -w start \
  >"$work_root/pg-start.stdout" 2>"$work_root/pg-start.stderr" \
  || block temporary_postgresql_start_failed
postgresql_started=true
"$PSQL" -X -q -h "$work_root/socket" -p "$TEMPORARY_POSTGRESQL_PORT" \
  -d postgres -v ON_ERROR_STOP=1 >"$work_root/roles.stdout" <<'SQL'
CREATE ROLE rag_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
CREATE ROLE rag_ingest LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOREPLICATION NOBYPASSRLS;
CREATE ROLE rag_retrieval LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOREPLICATION NOBYPASSRLS;
SQL
"$CREATEDB" -h "$work_root/socket" -p "$TEMPORARY_POSTGRESQL_PORT" \
  --owner=rag_owner --encoding=UTF8 --template=template0 rag_catalog
"$PSQL" -X -q -h "$work_root/socket" -p "$TEMPORARY_POSTGRESQL_PORT" \
  -d postgres -v ON_ERROR_STOP=1 >"$work_root/database-access.stdout" <<'SQL'
REVOKE ALL ON DATABASE rag_catalog FROM PUBLIC;
GRANT CONNECT ON DATABASE rag_catalog TO rag_ingest, rag_retrieval;
ALTER ROLE rag_retrieval IN DATABASE rag_catalog SET default_transaction_read_only = on;
SQL
"$PSQL" -X -q -h "$work_root/socket" -p "$TEMPORARY_POSTGRESQL_PORT" \
  -d rag_catalog -v ON_ERROR_STOP=1 >"$work_root/extensions.stdout" <<'SQL'
CREATE EXTENSION vector;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
SQL
"$PSQL" -X -q -h "$work_root/socket" -p "$TEMPORARY_POSTGRESQL_PORT" \
  -d rag_catalog -v ON_ERROR_STOP=1 \
  -v owner_role=rag_owner -v ingest_role=rag_ingest \
  -v retrieval_role=rag_retrieval -v schema_sha256="$SCHEMA_SHA256" \
  <"$SCHEMA" >"$work_root/schema.stdout" 2>"$work_root/schema.stderr" \
  || block temporary_schema_install_failed
emit 'milestone=temporary_postgresql;state=pass;schema_version=5;accepted_database_contact=false'

current_stage=synthetic_v2_ingestion
PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$CONFIG_ROOT/deployment.yaml" "$work_root/runtime-config/deployment.yaml" \
  "$TEMPORARY_POSTGRESQL_PORT" <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
old = "postgresql:\n  bind_host: 127.0.0.1\n  port: 5432\n"
new = f"postgresql:\n  bind_host: 127.0.0.1\n  port: {sys.argv[3]}\n"
assert source.count(old) == 1
pathlib.Path(sys.argv[2]).write_text(source.replace(old, new), encoding="utf-8")
PY
install -m 0644 -- "$CONFIG_ROOT/ingestion_dependencies.yaml" \
  "$work_root/runtime-config/ingestion_dependencies.yaml"
runner_arguments=(
  --product-root "$PRODUCT_ROOT"
  --promotion-bundle "$PROMOTION_BUNDLE"
  --runtime-config-root "$work_root/runtime-config"
  --work-root "$work_root/producer-work"
  --report-root "$work_root/operator-reports"
  --artifact-root "$work_root/retained-artifacts"
  --pipeline-executable "$PIPELINE_EXECUTABLE"
)
ISHIKAWA_NOMIC_API_KEY="$nomic_key" \
ISHIKAWA_POSTGRESQL_INGEST_PASSWORD="$database_password" \
PYTHONDONTWRITEBYTECODE=1 timeout --signal=TERM --kill-after=10s 900s \
  python3 -B "$INGESTION_RUNNER" --mode validate-only "${runner_arguments[@]}" \
  >"$work_root/ingestion-validate.stdout" 2>"$work_root/ingestion-validate.stderr" \
  || block synthetic_v2_ingestion_validation_failed
grep -Fxq 'actions=add:6,reprocess:0,retire:0,reuse:0,revise:0' \
  "$work_root/ingestion-validate.stdout" || block synthetic_v2_ingestion_plan_invalid
ISHIKAWA_NOMIC_API_KEY="$nomic_key" \
ISHIKAWA_POSTGRESQL_INGEST_PASSWORD="$database_password" \
PYTHONDONTWRITEBYTECODE=1 timeout --signal=TERM --kill-after=10s 900s \
  python3 -B "$INGESTION_RUNNER" --mode publish "${runner_arguments[@]}" \
  >"$work_root/ingestion-publish.stdout" 2>"$work_root/ingestion-publish.stderr" \
  || block synthetic_v2_ingestion_publication_failed
grep -Fxq 'ishikawa_ingestion=pass;exit_code=0' \
  "$work_root/ingestion-publish.stdout" || block synthetic_v2_ingestion_marker_absent
inventory="$("$PSQL" -X -q -A -t -h "$work_root/socket" \
  -p "$TEMPORARY_POSTGRESQL_PORT" -d rag_catalog -v ON_ERROR_STOP=1 \
  -c "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
      SELECT concat_ws('|',
        (SELECT count(*) FROM rag_search.active_documents),
        (SELECT coalesce(sum(page_count), 0) FROM rag_search.active_documents),
        (SELECT count(*) FROM rag_search.active_chunks),
        (SELECT count(*) FROM rag_search.active_citations),
        (SELECT count(*) FROM rag_search.active_embeddings),
        (SELECT count(*) FROM rag_search.active_retrieval_candidates),
        (SELECT count(*) FROM rag_search.active_retrieval_candidates WHERE retrieval_scoring_only),
        (SELECT count(*) FROM rag_search.active_retrieval_embeddings));
      ROLLBACK;")" || block synthetic_v2_inventory_query_failed
[[ "$inventory" == '6|26|139|139|139|168|29|168' ]] \
  || block synthetic_v2_inventory_mismatch
emit 'milestone=synthetic_v2_ingestion;state=pass;documents=6;pages=26;authoritative_chunks=139;retrieval_candidates=168;representatives=29'

current_stage=temporary_retrieval_api
installed_root="$work_root/staged/Ishikawa"
install -d -m 0755 -- "$installed_root/application/python/ishikawa" \
  "$installed_root/config" "$installed_root/scripts"
install -d -m 0700 -- "$installed_root/state/logs" "$installed_root/state/run"
while IFS= read -r source; do
  install -m 0644 -- "$source" \
    "$installed_root/application/python/ishikawa/$(basename -- "$source")"
done < <(find "$PACKAGE_ROOT" -maxdepth 1 -type f -name '*.py' -print | LC_ALL=C sort)
while IFS= read -r source; do
  install -m 0644 -- "$source" "$installed_root/config/$(basename -- "$source")"
done < <(find "$CONFIG_ROOT" -maxdepth 1 -type f -name '*.yaml' -print | LC_ALL=C sort)
install -m 0755 -- "$SERVICE_ENTRYPOINT" "$installed_root/scripts/ishikawa-retrieval-api"
PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$installed_root/config/deployment.yaml" "$TEMPORARY_POSTGRESQL_PORT" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
old = "postgresql:\n  bind_host: 127.0.0.1\n  port: 5432\n"
new = f"postgresql:\n  bind_host: 127.0.0.1\n  port: {sys.argv[2]}\n"
assert source.count(old) == 1
path.write_text(source.replace(old, new), encoding="utf-8")
PY
env -u ISHIKAWA_GEMMA_API_KEY -u ISHIKAWA_NOMIC_API_KEY \
  -u ISHIKAWA_POSTGRESQL_PASSWORD PYTHONDONTWRITEBYTECODE=1 \
  "$installed_root/scripts/ishikawa-retrieval-api" --check-config \
  >"$work_root/check-config.stdout" 2>"$work_root/check-config.stderr" \
  || block staged_configuration_invalid
ISHIKAWA_GEMMA_API_KEY="$gemma_key" \
ISHIKAWA_NOMIC_API_KEY="$nomic_key" \
ISHIKAWA_POSTGRESQL_PASSWORD="$database_password" \
PYTHONDONTWRITEBYTECODE=1 \
  "$installed_root/scripts/ishikawa-retrieval-api" --serve \
  >"$work_root/service.stdout" 2>"$work_root/service.stderr" &
service_pid="$!"
ready=false
ready_started="$(date +%s)"
ready_heartbeat=$(( ready_started + 30 ))
for _ in $(seq 1 180); do
  kill -0 "$service_pid" 2>/dev/null || break
  ready_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
    --connect-timeout 1 --max-time 5 http://127.0.0.1:1384/ready 2>/dev/null || true)"
  if [[ "$ready_status" == 200 ]]; then ready=true; break; fi
  now="$(date +%s)"
  if (( now >= ready_heartbeat )); then
    emit "milestone=temporary_retrieval_api;state=starting;elapsed_seconds=$(( now - ready_started ))"
    ready_heartbeat=$(( now + 30 ))
  fi
  sleep 1
done
[[ "$ready" == true ]] || block temporary_retrieval_api_not_ready
emit 'milestone=temporary_retrieval_api;state=pass;readiness=ready;database=disposable_schema_v5'

current_stage=complete_api_gemma_gate
observation="$work_root/complete-api.json"
evaluator_output="$work_root/evaluator.stdout"
evaluator_error="$work_root/evaluator.stderr"
emit 'milestone=complete_api_gemma_gate;state=start;cases=13;responsive=6;nonresponsive=6;broad_navigation=1'
PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 \
  python3 -B "$EVALUATOR" --run --endpoint "$API_ENDPOINT" \
  --cases "$CASES" --output "$observation" \
  --expected-hostname "$EXPECTED_HOSTNAME" \
  --expected-os-version "$EXPECTED_OS_VERSION" \
  --expected-architecture "$EXPECTED_ARCHITECTURE" \
  >"$evaluator_output" 2>"$evaluator_error" &
evaluator_pid="$!"
reported_lines=0
evaluation_started="$(date +%s)"
next_heartbeat=$(( evaluation_started + 30 ))
while kill -0 "$evaluator_pid" 2>/dev/null; do
  current_lines="$(wc -l <"$evaluator_output" | tr -d ' ')"
  if (( current_lines > reported_lines )); then
    sed -n "$(( reported_lines + 1 )),${current_lines}p" "$evaluator_output" \
      | while IFS= read -r safe_line; do
          if [[ "$safe_line" =~ ^case_(start|result)=[A-Z0-9-]+($|\;) ]]; then
            emit "[API] $safe_line"
          fi
        done
    reported_lines="$current_lines"
  fi
  now="$(date +%s)"
  if (( now >= next_heartbeat )); then
    emit "milestone=complete_api_gemma_gate;state=running;elapsed_seconds=$(( now - evaluation_started ))"
    next_heartbeat=$(( now + 30 ))
  fi
  sleep 5
done
if wait "$evaluator_pid"; then evaluator_status=0; else evaluator_status=$?; fi
evaluator_pid=''
current_lines="$(wc -l <"$evaluator_output" | tr -d ' ')"
if (( current_lines > reported_lines )); then
  sed -n "$(( reported_lines + 1 )),${current_lines}p" "$evaluator_output" \
    | while IFS= read -r safe_line; do
        if [[ "$safe_line" =~ ^case_(start|result)=[A-Z0-9-]+($|\;) ]]; then
          emit "[API] $safe_line"
        fi
      done
fi
if [[ -f "$observation" && ! -L "$observation" ]]; then
  observation_sha256="$(sha256sum "$observation" | awk '{print $1}')"
  [[ ! -e "$artifact_path" ]] || block observation_destination_exists
  cp -- "$observation" "$artifact_path" \
    || block observation_retention_failed
  chmod 0600 "$artifact_path" 2>/dev/null || true
  [[ "$(sha256sum "$artifact_path" | awk '{print $1}')" == "$observation_sha256" ]] \
    || block observation_identity_changed_after_copy
  printf '%s  %s\n' "$observation_sha256" "$(basename -- "$artifact_path")" \
    >"$artifact_checksum_path" || block observation_checksum_write_failed
  failure_observation_retained=true
  emit "qualification_observation=$artifact_path;qualification_observation_sha256=$observation_sha256"
fi
if (( evaluator_status != 0 )); then
  reason="$(sed -n 's/^v1_3_complete_api_evaluation=blocked;reason=\([a-z0-9_]*\)$/\1/p' "$evaluator_output" | tail -n 1)"
  [[ -n "$reason" ]] || reason='unclassified_evaluation_failure'
  block "complete_api_gemma_$reason"
fi
grep -Fxq 'v1_3_complete_api_evaluation=pass' "$evaluator_output" \
  || block complete_api_gemma_pass_marker_absent
summary="$(sed -n 's/^\(complete_api_cases=.*\)$/\1/p' "$evaluator_output" | tail -n 1)"
[[ "$summary" == 'complete_api_cases=13;expected_status_matches=13/13;required_evidence_returned=13/13;required_evidence_cited=13/13;dependency_failures=0' ]] \
  || block complete_api_gemma_summary_invalid
emit "milestone=complete_api_gemma_gate;state=pass;$summary"
emit 'candidate_frozen=true;implemented_retrieval_qualified=true;complete_api_gemma_qualified=true;accepted_release_changed=false;deployment_candidate_assembled=false'
emit 'next_gate=assemble_v1_3_deployment_candidate'
failure_observation_retained=false
current_stage=complete
