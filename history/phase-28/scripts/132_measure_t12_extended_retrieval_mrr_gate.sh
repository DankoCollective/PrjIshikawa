#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Freshly measure frozen T12 against the strict 60-case MRR promotion gate.
#
# Mental model:
#   Request one singleton Nomic embedding for each frozen question, read the
#   active synthetic corpus once, rank with T09 plus T12 deterministic page
#   routing, and require MRR@20 to be strictly greater than 0.91.
#
# Inputs or prerequisites:
#   Clean Script 131 evidence, the accepted local six-document corpus,
#   forwarded Nomic on 127.0.0.1:8001, the Nomic API key, and the local
#   rag_retrieval PostgreSQL password.
#
# Outputs:
#   One content-free report and one checksum-bound strict-gate observation.
#   Questions, source text, vectors, credentials, and generated answers are
#   not retained. Gemma is not called and PostgreSQL remains read-only.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/132_measure_t12_extended_retrieval_mrr_gate.sh --run

usage() {
  sed -n '3,26p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run            Execute the fresh 60-case T12 measurement.' \
    '  --validate-only  Validate bound inputs and helper self-tests only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly CONFIG_ROOT="$PRODUCT_ROOT/config/templates"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_extended_retrieval_mrr.py"
readonly CLASSIFIER="$SCRIPT_DIR/classify_t12_extended_retrieval_mrr.py"
readonly BASE_EVALUATOR="$SCRIPT_DIR/evaluate_local_retrieval_ranking.py"
readonly CASES="$PHASE_ROOT/reference/ishikawa-extended-retrieval-mrr-cases-v1.1.json"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_1_TUNING_DECISIONS.md"
readonly SCRIPT_117_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.1-local-tuning-corpus/local_tuning_corpus_20261021T165048Z_QfXYrD.txt"
readonly SCRIPT_131_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.1-t12-routing/t12_routing_20261021T204200Z_5Knlp9.txt"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.1-t12-extended-mrr"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v1.1-t12-extended-mrr"

readonly EVALUATOR_SHA256='784e90e890d05ce0b8eaed39385a79e5467683ce0a94067490362f3430e39993'
readonly CLASSIFIER_SHA256='ab58cd272a8f5f6f2431b5569ce77305c959b273c51cec983e541cb9a3b578e1'
readonly BASE_EVALUATOR_SHA256='4572e0682b052af8b5f498c207c3e7f0b512fc2405f0e2b353278bdaa0b5d996'
readonly CASES_SHA256='14814166168c4dfd97e85668a29fd11538e2cf585a0176fdcd50f072ef5958ce'
readonly DECISIONS_SHA256='3d2b2f79c1f0d58c9b14d6ca6c3e47be9fc6486ab433c3f70d3234fa241bf641'
readonly METHOD_PROFILE_SHA256='0d329981f1259e5d5f8138350af538a08a3d70a704241b384da6714f3b17724c'
readonly DEPLOYMENT_PROFILE_SHA256='2a5008b70a8ffe615cfcb2ca4b5d5a3687888c362861670a4a79e0de32874cfb'
readonly RUNTIME_DEPENDENCIES_SHA256='6254c1737babc3226d8e733c057886673133948af1b19eb66c1b29f48d2386f1'
readonly SCRIPT_117_REPORT_SHA256='5fab929e8e2cf838adc35d7c41d2dea5ed02f9670c9254ddf7f794c8e759ddff'
readonly SCRIPT_131_REPORT_SHA256='11b0c2f8fcfa3f2c353e3c1ff9b723df2ee464131a4f7eb27b4a13b5f221bc28'
readonly EXPECTED_RETRIEVAL_PROFILE_ID='ba4bac60b3f09f6be89db148d1df883748a2003f35a1cecfb6c74f53be74b865'
readonly EXPECTED_HOSTNAME='DankoSurface'
readonly EXPECTED_OS_VERSION='24.04'
readonly EXPECTED_ARCHITECTURE='aarch64'
readonly NOMIC_HEALTH_URL='http://127.0.0.1:8001/health'

run_mode=false
validate_mode=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_mode=true; shift ;;
    --validate-only) validate_mode=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_132_t12_extended_mrr=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_mode" != "$validate_mode" ]] || {
  printf 'script_132_t12_extended_mrr=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in awk bash chmod curl date grep head hostname kill mkdir mktemp mv pg_isready python3 rm sed sha256sum sleep tail tee tr uname; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_132_t12_extended_mrr=blocked;reason=local_command_missing;command=%s\n' "$required" >&2
    exit 2
  }
done

check_file() {
  [[ -f "$1" && ! -L "$1" && -r "$1" ]] || {
    printf 'script_132_t12_extended_mrr=blocked;reason=%s_unsafe\n' "$3" >&2
    exit 2
  }
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_132_t12_extended_mrr=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}

check_file "$EVALUATOR" "$EVALUATOR_SHA256" evaluator
check_file "$CLASSIFIER" "$CLASSIFIER_SHA256" classifier
check_file "$BASE_EVALUATOR" "$BASE_EVALUATOR_SHA256" base_evaluator
check_file "$CASES" "$CASES_SHA256" case_set
check_file "$DECISIONS" "$DECISIONS_SHA256" tuning_decisions
check_file "$CONFIG_ROOT/method_profile.yaml" "$METHOD_PROFILE_SHA256" method_profile
check_file "$CONFIG_ROOT/deployment.yaml" "$DEPLOYMENT_PROFILE_SHA256" deployment_profile
check_file "$CONFIG_ROOT/runtime_dependencies.yaml" "$RUNTIME_DEPENDENCIES_SHA256" runtime_dependencies
check_file "$SCRIPT_117_REPORT" "$SCRIPT_117_REPORT_SHA256" script_117_report
check_file "$SCRIPT_131_REPORT" "$SCRIPT_131_REPORT_SHA256" script_131_report

for fact in \
  'milestone=synthetic_corpus_publication;state=pass;documents=6;pages=27;chunks=126;citations=126;embeddings=126;retained_artifacts=3' \
  'script_117_local_tuning_corpus=pass;'; do
  grep -Fq "$fact" "$SCRIPT_117_REPORT" || {
    printf 'script_132_t12_extended_mrr=blocked;reason=script_117_contract_invalid\n' >&2
    exit 2
  }
done
for fact in \
  'milestone=native_tests;state=pass;tests=379;failures=0;errors=0' \
  'milestone=declared_identifier_page_routes;state=pass;routes=5;unique_owner=true;unknown_owner_fallback=true' \
  'projected_mrr_at_20=0.919306;projected_fraction=6619/7200;strict_target=greater_than_0.91;fresh_measurement_required=true' \
  'script_131_t12_routing=pass;next_gate=remeasure_extended_mrr_with_t12;'; do
  grep -Fq "$fact" "$SCRIPT_131_REPORT" || {
    printf 'script_132_t12_extended_mrr=blocked;reason=script_131_contract_invalid\n' >&2
    exit 2
  }
done
grep -Eq '^\| `T12` \|.*\| FROZEN \|$' "$DECISIONS" || {
  printf 'script_132_t12_extended_mrr=blocked;reason=t12_not_frozen\n' >&2
  exit 2
}

bash -n "${BASH_SOURCE[0]}"
for source in "$EVALUATOR" "$CLASSIFIER" "$BASE_EVALUATOR"; do
  PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
    'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
    "$source"
done
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" --self-test \
  | grep -Fxq 'extended_retrieval_mrr_evaluator_self_test=pass' || {
    printf 'script_132_t12_extended_mrr=blocked;reason=evaluator_self_test_failed\n' >&2
    exit 2
  }
PYTHONDONTWRITEBYTECODE=1 python3 -B "$CLASSIFIER" --self-test \
  | grep -Fxq 't12_extended_mrr_classifier_self_test=pass' || {
    printf 'script_132_t12_extended_mrr=blocked;reason=classifier_self_test_failed\n' >&2
    exit 2
  }

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_mode" == true ]]; then
  printf '%s\n' \
    'purpose=validate_fresh_t12_extended_retrieval_mrr_gate' \
    "script_sha256=$script_sha256;evaluator_sha256=$EVALUATOR_SHA256;classifier_sha256=$CLASSIFIER_SHA256" \
    "script_131_report_sha256=$SCRIPT_131_REPORT_SHA256;case_set_sha256=$CASES_SHA256;decision_list_sha256=$DECISIONS_SHA256" \
    "retrieval_profile_id=$EXPECTED_RETRIEVAL_PROFILE_ID;depths=1,20,20,20;rrf_constant=60;lane_weights=1,1,4" \
    'case_count=60;metric=mrr_at_20;strict_target=greater_than_0.91;manual_review_required=false' \
    'evaluator_self_tests=2;database_contact=false;model_contact=false;credential_read=false' \
    'script_132_t12_extended_mrr_source=pass'
  exit 0
fi

umask 077
work_root="$(mktemp -d /tmp/ishikawa-script-132.XXXXXX)"
nomic_key=''
database_password=''
report_path=''
active_pid=''
artifact_committed=false
artifact_path=''
checksum_path=''

cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  nomic_key=''
  database_password=''
  unset nomic_key database_password ISHIKAWA_NOMIC_API_KEY ISHIKAWA_POSTGRESQL_PASSWORD
  if [[ "$active_pid" =~ ^[0-9]+$ ]] && kill -0 "$active_pid" 2>/dev/null; then
    kill -TERM "$active_pid" 2>/dev/null || true
    wait "$active_pid" 2>/dev/null || true
  fi
  if [[ "$artifact_committed" != true ]]; then
    [[ "$artifact_path" == "$ARTIFACT_ROOT"/t12_extended_mrr_*.json ]] && rm -f -- "$artifact_path"
    [[ "$checksum_path" == "$ARTIFACT_ROOT"/t12_extended_mrr_*.json.sha256 ]] && rm -f -- "$checksum_path"
  fi
  [[ "$work_root" == /tmp/ishikawa-script-132.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  [[ -z "$report_path" ]] || chmod 0600 "$report_path" 2>/dev/null || true
  exit "$status"
}
trap cleanup EXIT

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" && -d "$ARTIFACT_ROOT" && ! -L "$ARTIFACT_ROOT" ]] || {
  printf 'script_132_t12_extended_mrr=blocked;reason=artifact_directory_unsafe\n' >&2
  exit 1
}
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/t12_extended_mrr_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
block() { emit "script_132_t12_extended_mrr=blocked;reason=$1"; exit 1; }
trap 'block interrupted_by_operator' INT
trap 'block terminated_by_signal' TERM

read_secret() {
  local label="$1" output_name="$2" value=''
  printf '%s (input hidden): ' "$label" >/dev/tty
  IFS= read -r -s value </dev/tty || block secret_input_failed
  printf '\n' >/dev/tty
  (( ${#value} >= 1 && ${#value} <= 4096 )) || block secret_length_invalid
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || block secret_character_invalid
  printf -v "$output_name" '%s' "$value"
  value=''
}

actual_hostname="$(hostname -s)"
actual_os_id="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"' | head -n 1)"
actual_os_version="$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"' | head -n 1)"
actual_architecture="$(uname -m)"
emit 'purpose=measure_fresh_t12_extended_retrieval_mrr_gate'
emit "started_utc=$timestamp;hostname=$actual_hostname;os_version=$actual_os_version;architecture=$actual_architecture"
emit "script_sha256=$script_sha256;evaluator_sha256=$EVALUATOR_SHA256;classifier_sha256=$CLASSIFIER_SHA256"
emit "script_131_report_sha256=$SCRIPT_131_REPORT_SHA256;retrieval_profile_id=$EXPECTED_RETRIEVAL_PROFILE_ID"
emit 'metric=mrr_at_20;strict_target=greater_than_0.91;case_count=60;manual_review_required=false;gemma_required=false'
[[ "$actual_hostname" == "$EXPECTED_HOSTNAME" \
    && "$actual_os_id" == ubuntu \
    && "$actual_os_version" == "$EXPECTED_OS_VERSION" \
    && "$actual_architecture" == "$EXPECTED_ARCHITECTURE" ]] \
  || block local_host_identity_mismatch

postgresql_ready=false
pg_isready -q -h 127.0.0.1 -p 5432 -d rag_catalog -t 5 && postgresql_ready=true
nomic_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
  --connect-timeout 5 --max-time 10 "$NOMIC_HEALTH_URL" 2>"$work_root/nomic-health.stderr")" \
  || nomic_status=000
emit "milestone=live_prerequisites;state=observed;postgresql_ready=$postgresql_ready;nomic_http_status=$nomic_status"
[[ "$postgresql_ready" == true ]] || block local_postgresql_unavailable
[[ "$nomic_status" == 200 ]] || block nomic_health_unavailable

read_secret 'Nomic API key' nomic_key
read_secret 'rag_retrieval PostgreSQL password' database_password
export ISHIKAWA_NOMIC_API_KEY="$nomic_key"
export ISHIKAWA_POSTGRESQL_PASSWORD="$database_password"

evaluator_output="$work_root/evaluator.stdout"
evaluator_error="$work_root/evaluator.stderr"
base_artifact="$work_root/base-observation.json"
final_candidate="$work_root/t12-observation.json"
emit 'milestone=fresh_t12_measurement;state=start;cases=60;query_embeddings=60'
started_epoch="$(date +%s)"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" \
    --run \
    --python-root "$PYTHON_ROOT" \
    --config-root "$CONFIG_ROOT" \
    --cases "$CASES" \
    --output "$base_artifact" \
    >"$evaluator_output" 2>"$evaluator_error" &
active_pid="$!"
next_heartbeat_epoch=$(( started_epoch + 30 ))
while kill -0 "$active_pid" 2>/dev/null; do
  sleep 5
  current_epoch="$(date +%s)"
  if (( current_epoch >= next_heartbeat_epoch )) && kill -0 "$active_pid" 2>/dev/null; then
    emit "milestone=fresh_t12_measurement;state=running;elapsed_seconds=$(( current_epoch - started_epoch ))"
    next_heartbeat_epoch=$(( current_epoch + 30 ))
  fi
done
if wait "$active_pid"; then evaluator_status=0; else evaluator_status=$?; fi
active_pid=''
nomic_key=''
database_password=''
unset ISHIKAWA_NOMIC_API_KEY ISHIKAWA_POSTGRESQL_PASSWORD
if (( evaluator_status != 0 )); then
  reason="$(sed -nE 's/^extended_retrieval_mrr_evaluator=blocked;reason=([A-Za-z0-9_]+)$/\1/p' "$evaluator_error" | tail -n 1)"
  [[ -n "$reason" ]] || reason=unclassified_evaluator_failure
  block "$reason"
fi
for marker in \
  'case_count=60;query_embeddings=60;gemma_contact=false;database_write=false' \
  'extended_retrieval_mrr_evaluator=pass'; do
  grep -Fxq "$marker" "$evaluator_output" || block evaluator_pass_contract_invalid
done

classifier_output="$work_root/classifier.stdout"
classifier_error="$work_root/classifier.stderr"
if ! PYTHONDONTWRITEBYTECODE=1 python3 -B "$CLASSIFIER" \
    --run --input "$base_artifact" --output "$final_candidate" \
    >"$classifier_output" 2>"$classifier_error"; then
  reason="$(sed -nE 's/^t12_extended_mrr_classifier=blocked;reason=([A-Za-z0-9_]+)$/\1/p' "$classifier_error" | tail -n 1)"
  [[ -n "$reason" ]] || reason=unclassified_classifier_failure
  block "$reason"
fi
for marker in \
  't12_direct_page_cases=5/5;t12_direct_page_first_relevant_rank=1' \
  't12_extended_mrr_classifier=pass'; do
  grep -Fxq "$marker" "$classifier_output" || block classifier_pass_contract_invalid
done
summary_line="$(sed -n '/^mrr_at_20=/p' "$classifier_output")"
gate_line="$(sed -n '/^promotion_gate=/p' "$classifier_output")"
identity_line="$(sed -n '/^observation_set_id=/p' "$classifier_output")"
[[ -n "$summary_line" && -n "$gate_line" && -n "$identity_line" ]] || block classifier_summary_missing
promotion_gate="$(sed -nE 's/^promotion_gate=(pass|not_met);.*$/\1/p' <<<"$gate_line")"
[[ "$promotion_gate" == pass || "$promotion_gate" == not_met ]] || block promotion_result_invalid
emit 'milestone=fresh_t12_measurement;state=pass'
emit "$summary_line"
emit 't12_direct_page_cases=5/5;t12_direct_page_first_relevant_rank=1'
emit "$gate_line"

PYTHONDONTWRITEBYTECODE=1 python3 -B - "$final_candidate" "$CASES_SHA256" "$EXPECTED_RETRIEVAL_PROFILE_ID" "$promotion_gate" <<'PY'
import json
import sys
from pathlib import Path

value = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
metrics = value.get("metrics", {})
cases = value.get("cases", [])
expected_ids = {f"E-{index:03d}" for index in range(1, 61)}
expected_t12 = {"E-034": 1, "E-036": 1, "E-040": 1, "E-046": 1, "E-052": 1}
if (
    value.get("artifact_kind") != "ishikawa_t12_extended_retrieval_mrr_observation"
    or value.get("schema_version") != 1
    or value.get("case_set_sha256") != sys.argv[2]
    or value.get("case_count") != 60
    or value.get("retrieval_profile_id") != sys.argv[3]
    or value.get("database_boundary") != "repeatable_read_read_only"
    or value.get("promotion_gate_basis") != "strict_mrr_at_20_only"
    or value.get("strict_production_target") != "greater_than_0.91"
    or value.get("t12_direct_page_case_ranks") != expected_t12
    or value.get("manual_review_performed") is not False
    or value.get("gemma_contact") is not False
    or value.get("database_write") is not False
    or value.get("question_text_retained") is not False
    or value.get("query_vectors_retained") is not False
    or value.get("source_text_retained") is not False
    or metrics.get("promotion_gate") != sys.argv[4]
    or not isinstance(cases, list)
    or len(cases) != 60
    or {item.get("case_id") for item in cases} != expected_ids
):
    raise SystemExit("t12_extended_artifact_contract_invalid")
PY

artifact_path="$ARTIFACT_ROOT/t12_extended_mrr_${timestamp}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] \
  || block artifact_path_exists
mv -- "$final_candidate" "$artifact_path"
artifact_sha256="$(sha256sum "$artifact_path" | awk '{print $1}')"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
(
  cd -- "$ARTIFACT_ROOT"
  sha256sum --check --strict "$(basename -- "$checksum_path")" >/dev/null
) || block artifact_checksum_failed
artifact_committed=true
emit "$identity_line"
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_checksum=$checksum_path"
if [[ "$promotion_gate" == pass ]]; then
  emit 'script_132_t12_extended_mrr=pass;promotion_gate=pass;next_gate=qualify_t12_complete_retrieval_api_before_package_refresh'
else
  emit 'script_132_t12_extended_mrr=pass;promotion_gate=not_met;next_gate=review_fresh_t12_rank_failures_before_any_further_change'
fi
