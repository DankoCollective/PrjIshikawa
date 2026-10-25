#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Measure the frozen Ishikawa retrieval profile against the 13-case synthetic
#   tuning set using local read-only PostgreSQL and forwarded Nomic.
#
# Mental model:
#   Embed each ranking question once, run the exact, lexical, and vector lanes,
#   fuse their ranks, and measure MRR@20 plus required-evidence recall. Gemma,
#   Next.js, database writes, and deployment-package assembly are excluded.
#
# Inputs or prerequisites:
#   Clean Script 115 and 117 receipts, forwarded Nomic on 127.0.0.1:8001, the
#   Nomic key, and the local rag_retrieval password.
#
# Outputs or artifact lane:
#   One content-free report and one checksum-bound ranking artifact.
#   The artifact retains ranks and synthetic citation identities, never query
#   vectors, credentials, source text, or case-question text.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/118_measure_local_retrieval_ranking_baseline.sh --run

usage() {
  sed -n '3,27p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run            Measure the accepted local retrieval profile.' \
    '  --validate-only  Validate bound inputs and evaluator self-tests only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly CONFIG_ROOT="$PRODUCT_ROOT/config/templates"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_local_retrieval_ranking.py"
readonly CASES="$PHASE_ROOT/reference/ishikawa-retrieval-tuning-cases-v1.1.json"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_1_TUNING_DECISIONS.md"
readonly SCRIPT_115_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.1-local-tuning-preflight/local_tuning_preflight_20261021T165204Z_EQbNaj.txt"
readonly SCRIPT_117_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.1-local-tuning-corpus/local_tuning_corpus_20261021T165048Z_QfXYrD.txt"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.1-local-ranking-baseline"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v1.1-local-ranking-baseline"
readonly CASES_SHA256='feb2303d8433461846974015078d88ca42593636c399fc90fcd9c2e67beab6f9'
readonly DECISIONS_SHA256='8db8b9ffd1a91f9c50250009452280705af8b9871692a437abe84d0bf791f7fa'
readonly EVALUATOR_SHA256='3c553baf1863d4be34631d242bf222f38da174f7fc0e24eca381361fe85775ae'
readonly METHOD_PROFILE_SHA256='821e8cac5c4b30222a814aedbb462dfcf635514c49a36ef1a36a7866ceb836a3'
readonly DEPLOYMENT_PROFILE_SHA256='2a5008b70a8ffe615cfcb2ca4b5d5a3687888c362861670a4a79e0de32874cfb'
readonly RUNTIME_DEPENDENCIES_SHA256='6254c1737babc3226d8e733c057886673133948af1b19eb66c1b29f48d2386f1'
readonly SCRIPT_115_REPORT_SHA256='1a2721d75296ecb113e86e9d3e4a5e692e6b9af50ccaacfc0caa67e491015c97'
readonly SCRIPT_117_REPORT_SHA256='5fab929e8e2cf838adc35d7c41d2dea5ed02f9670c9254ddf7f794c8e759ddff'
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
    *) printf 'script_118_local_ranking_baseline=blocked;reason=argument_invalid\n' >&2; exit 2 ;;
  esac
done
[[ "$run_mode" != "$validate_mode" ]] || {
  printf 'script_118_local_ranking_baseline=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in awk bash chmod curl date find grep hostname mkdir mktemp mv pg_isready python3 rm sed sha256sum stat tee uname; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_118_local_ranking_baseline=blocked;reason=local_command_missing;command=%s\n' "$required" >&2
    exit 2
  }
done

check_file() {
  [[ -f "$1" && ! -L "$1" && -r "$1" ]] || {
    printf 'script_118_local_ranking_baseline=blocked;reason=%s_unsafe\n' "$3" >&2
    exit 2
  }
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_118_local_ranking_baseline=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}

check_file "$EVALUATOR" "$EVALUATOR_SHA256" evaluator
check_file "$CASES" "$CASES_SHA256" case_set
check_file "$DECISIONS" "$DECISIONS_SHA256" tuning_decisions
check_file "$CONFIG_ROOT/method_profile.yaml" "$METHOD_PROFILE_SHA256" method_profile
check_file "$CONFIG_ROOT/deployment.yaml" "$DEPLOYMENT_PROFILE_SHA256" deployment_profile
check_file "$CONFIG_ROOT/runtime_dependencies.yaml" "$RUNTIME_DEPENDENCIES_SHA256" runtime_dependencies
check_file "$SCRIPT_115_REPORT" "$SCRIPT_115_REPORT_SHA256" script_115_report
check_file "$SCRIPT_117_REPORT" "$SCRIPT_117_REPORT_SHA256" script_117_report

for fact in \
  'milestone=forwarded_model_health;state=pass;gemma_http_status=200;nomic_http_status=200;model_inference=false' \
  'milestone=local_synthetic_corpus;state=pass;database=rag_catalog;role=rag_retrieval;documents=6;pages=27;chunks=126;citations=126;embeddings=126;transaction=repeatable_read_read_only' \
  'native_tests=367;failures=0;errors=0;' \
  'script_115_local_tuning_preflight=pass;'; do
  grep -Fq "$fact" "$SCRIPT_115_REPORT" || {
    printf 'script_118_local_ranking_baseline=blocked;reason=script_115_contract_invalid\n' >&2
    exit 2
  }
done
for fact in \
  'milestone=synthetic_corpus_publication;state=pass;documents=6;pages=27;chunks=126;citations=126;embeddings=126;retained_artifacts=3' \
  'script_117_local_tuning_corpus=pass;'; do
  grep -Fq "$fact" "$SCRIPT_117_REPORT" || {
    printf 'script_118_local_ranking_baseline=blocked;reason=script_117_contract_invalid\n' >&2
    exit 2
  }
done
grep -Eq '^\| `T08` \|.*\| FROZEN \|$' "$DECISIONS" || {
  printf 'script_118_local_ranking_baseline=blocked;reason=tuning_decision_contract_invalid\n' >&2
  exit 2
}

bash -n "${BASH_SOURCE[0]}"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
  "$EVALUATOR"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" --self-test \
  | grep -Fxq 'local_retrieval_ranking_evaluator_self_test=pass' || {
    printf 'script_118_local_ranking_baseline=blocked;reason=evaluator_self_test_failed\n' >&2
    exit 2
  }

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_mode" == true ]]; then
  printf '%s\n' \
    'purpose=validate_local_retrieval_ranking_baseline_measurement' \
    "script_sha256=$script_sha256;evaluator_sha256=$EVALUATOR_SHA256;case_set_sha256=$CASES_SHA256;decision_list_sha256=$DECISIONS_SHA256" \
    "script_115_report_sha256=$SCRIPT_115_REPORT_SHA256;script_117_report_sha256=$SCRIPT_117_REPORT_SHA256" \
    'evaluator_self_tests=1;case_count=13;responsive_cases=6;nonresponsive_cases=6;required_evidence_expectations=13' \
    'database_contact=false;model_contact=false;database_write=false;credential_read=false' \
    'script_118_local_ranking_baseline_source=pass'
  exit 0
fi

umask 077
work_root="$(mktemp -d /tmp/ishikawa-script-118.XXXXXX)"
nomic_key=''
database_password=''
report_path=''

cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  nomic_key=''
  database_password=''
  unset nomic_key database_password ISHIKAWA_NOMIC_API_KEY ISHIKAWA_POSTGRESQL_PASSWORD
  [[ "$work_root" == /tmp/ishikawa-script-118.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  [[ -z "$report_path" ]] || chmod 0600 "$report_path" 2>/dev/null || true
  exit "$status"
}
trap cleanup EXIT

mkdir -p -- "$REPORT_ROOT"
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" ]] || {
  printf 'script_118_local_ranking_baseline=blocked;reason=report_directory_unsafe\n' >&2
  exit 1
}
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/local_ranking_baseline_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }

block() {
  emit "script_118_local_ranking_baseline=blocked;reason=$1"
  exit 1
}

unexpected_failure() {
  local status="$?"
  trap - ERR
  emit "script_118_local_ranking_baseline=blocked;reason=unexpected_shell_failure;exit_code=$status"
  exit "$status"
}
trap unexpected_failure ERR
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
emit 'purpose=measure_local_ishikawa_v1_1_retrieval_ranking_baseline'
emit "started_utc=$timestamp;hostname=$actual_hostname;os_version=$actual_os_version;architecture=$actual_architecture;local_report=$report_path"
emit "script_sha256=$script_sha256;evaluator_sha256=$EVALUATOR_SHA256;case_set_sha256=$CASES_SHA256;decision_list_sha256=$DECISIONS_SHA256"
emit "script_115_report_sha256=$SCRIPT_115_REPORT_SHA256;script_117_report_sha256=$SCRIPT_117_REPORT_SHA256"
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
emit "milestone=live_prerequisites;postgresql_ready=$postgresql_ready;nomic_http_status=$nomic_status;gemma_required=false"
[[ "$postgresql_ready" == true ]] || block local_postgresql_unavailable
[[ "$nomic_status" == 200 ]] || block nomic_health_unavailable

read_secret 'Nomic API key' nomic_key
read_secret 'rag_retrieval PostgreSQL password' database_password
export ISHIKAWA_NOMIC_API_KEY="$nomic_key"
export ISHIKAWA_POSTGRESQL_PASSWORD="$database_password"

evaluator_output="$work_root/evaluator.stdout"
evaluator_error="$work_root/evaluator.stderr"
artifact_candidate="$work_root/ranking-baseline.json"
if PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" \
    --run \
    --python-root "$PYTHON_ROOT" \
    --config-root "$CONFIG_ROOT" \
    --cases "$CASES" \
    --output "$artifact_candidate" \
    >"$evaluator_output" 2>"$evaluator_error"; then
  evaluator_status=0
else
  evaluator_status=$?
fi
nomic_key=''
database_password=''
unset ISHIKAWA_NOMIC_API_KEY ISHIKAWA_POSTGRESQL_PASSWORD
if (( evaluator_status != 0 )); then
  evaluator_reason="$(sed -nE 's/^local_retrieval_ranking_evaluator=blocked;reason=([A-Za-z0-9_]+)$/\1/p' "$evaluator_error" | tail -n 1)"
  [[ -n "$evaluator_reason" ]] || evaluator_reason=unclassified_evaluator_failure
  emit "script_118_local_ranking_baseline=blocked;reason=$evaluator_reason;stdout_sha256=$(sha256sum "$evaluator_output" | awk '{print $1}');stderr_sha256=$(sha256sum "$evaluator_error" | awk '{print $1}');raw_output_retained=false"
  exit 1
fi

for marker in \
  'case_count=13;query_embeddings=12;gemma_contact=false;database_write=false' \
  'local_retrieval_ranking_evaluator=pass'; do
  grep -Fxq "$marker" "$evaluator_output" || block evaluator_pass_contract_invalid
done

PYTHONDONTWRITEBYTECODE=1 python3 -B - "$artifact_candidate" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
value = json.loads(path.read_text(encoding="utf-8"))
if (
    not isinstance(value, dict)
    or value.get("artifact_kind") != "ishikawa_local_retrieval_ranking_baseline"
    or value.get("schema_version") != 1
    or value.get("case_count") != 13
    or value.get("query_embedding_count") != 12
    or value.get("database_boundary") != "repeatable_read_read_only"
    or value.get("gemma_contact") is not False
    or value.get("question_text_retained") is not False
    or value.get("query_vectors_retained") is not False
    or value.get("source_text_retained") is not False
    or len(value.get("cases", [])) != 13
):
    raise SystemExit("ranking artifact contract invalid")
for forbidden in (
    "question",
    "query_vector",
    "embedding_vector",
    "vector_values",
    "retrieval_text",
    "source_text",
    "credential",
):
    stack = [value]
    while stack:
        current = stack.pop()
        if isinstance(current, dict):
            if forbidden in current:
                raise SystemExit("ranking artifact contains a forbidden field")
            stack.extend(current.values())
        elif isinstance(current, list):
            stack.extend(current)
PY

artifact_sha256="$(sha256sum "$artifact_candidate" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$artifact_candidate")"
observation_set_id="$(sed -nE 's/^observation_set_id=([0-9a-f]{64});artifact_sha256=.*/\1/p' "$evaluator_output")"
[[ "$observation_set_id" =~ ^[0-9a-f]{64}$ ]] || block observation_identity_invalid
mkdir -p -- "$ARTIFACT_ROOT" "$REPORT_ROOT"
artifact_path="$ARTIFACT_ROOT/accepted_profile_ranking_${observation_set_id}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] \
  || block accepted_artifact_path_exists
mv -- "$artifact_candidate" "$artifact_path"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true

metrics_line="$(grep -E '^mrr_at_20=[0-9]+\.[0-9]{6};responsive_top_five=[0-9]+/6;required_evidence_at_20=[0-9]+/13$' "$evaluator_output")" \
  || block evaluator_metric_contract_invalid
gate_line="$(grep -E '^ranking_gate=(pass|not_met);nonresponsive_acceptance_measured=false;broad_navigation=clarification-required$' "$evaluator_output")" \
  || block evaluator_metric_contract_invalid
[[ -n "$metrics_line" && -n "$gate_line" ]] || block evaluator_metric_contract_invalid
ranking_gate="$(sed -nE 's/^ranking_gate=(pass|not_met);.*/\1/p' <<<"$gate_line")"
if [[ "$ranking_gate" == pass ]]; then
  next_gate='qualify_nonresponsive_abstention_and_complete_api'
else
  next_gate='run_bounded_retrieval_parameter_search'
fi

emit 'database_boundary=repeatable_read_read_only;database_write=false;nomic_contact=true;gemma_contact=false;query_vectors_retained=false;question_text_retained=false;source_text_retained=false;credentials_retained=false'
emit 'corpus_documents=6;corpus_pages=27;corpus_chunks=126;corpus_citations=126;corpus_embeddings=126'
emit "$metrics_line"
emit "$gate_line"
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$artifact_bytes;checksum=$checksum_path"
emit "script_118_local_ranking_baseline=pass;ranking_gate=$ranking_gate;next_gate=$next_gate;local_report=$report_path"
