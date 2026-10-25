#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Capture reusable exact, lexical, and vector lane rankings for the frozen
#   60-case Ishikawa retrieval set.
#
# Mental model:
#   Request each query embedding once, read the accepted corpus in one
#   repeatable-read transaction, reproduce Script 127 under the released
#   profile, and retain only content-free lane ranks and relevance booleans.
#
# Inputs or prerequisites:
#   Clean Script 128 evidence, forwarded Nomic on 127.0.0.1:8001, the Nomic
#   key, and the local rag_retrieval PostgreSQL password.
#
# Outputs:
#   One checksum-bound lane-ranking artifact and content-free report. The
#   retrieval profile and accepted package are not changed.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/129_capture_extended_retrieval_lane_rankings.sh --run

usage() {
  sed -n '3,23p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run            Capture the 60-case lane-ranking observation.' \
    '  --validate-only  Validate bound inputs and helper self-tests only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly CONFIG_ROOT="$PRODUCT_ROOT/config/templates"
readonly HELPER="$SCRIPT_DIR/capture_extended_retrieval_lane_rankings.py"
readonly EXTENDED_EVALUATOR="$SCRIPT_DIR/evaluate_extended_retrieval_mrr.py"
readonly BASE_EVALUATOR="$SCRIPT_DIR/evaluate_local_retrieval_ranking.py"
readonly CASES="$PHASE_ROOT/reference/ishikawa-extended-retrieval-mrr-cases-v1.1.json"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_1_TUNING_DECISIONS.md"
readonly GATE_DEFINITION="$PHASE_ROOT/docs/ISHIKAWA_EXTENDED_EVALUATION_CANDIDATE.md"
readonly SCRIPT_117_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.1-local-tuning-corpus/local_tuning_corpus_20261021T165048Z_QfXYrD.txt"
readonly SCRIPT_127_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/v1.1-extended-mrr/extended_mrr_20261021T193408Z.json"
readonly SCRIPT_127_CHECKSUM="$SCRIPT_127_ARTIFACT.sha256"
readonly SCRIPT_128_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.1-extended-mrr-strict-target/strict_mrr_reclassification_20261021T194854Z_sac0I0.txt"
readonly SCRIPT_128_RECEIPT="$REPO_ROOT/local/artifacts/ishikawa/v1.1-extended-mrr-strict-target/strict_mrr_reclassification_20261021T194854Z.json"
readonly SCRIPT_128_CHECKSUM="$SCRIPT_128_RECEIPT.sha256"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.1-extended-lane-rankings"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v1.1-extended-lane-rankings"

readonly HELPER_SHA256='885f62e8490c99c789e315caab05df85813f781546c0c307a2e0a7d38f433703'
readonly EXTENDED_EVALUATOR_SHA256='784e90e890d05ce0b8eaed39385a79e5467683ce0a94067490362f3430e39993'
readonly BASE_EVALUATOR_SHA256='4572e0682b052af8b5f498c207c3e7f0b512fc2405f0e2b353278bdaa0b5d996'
readonly CASES_SHA256='14814166168c4dfd97e85668a29fd11538e2cf585a0176fdcd50f072ef5958ce'
readonly DECISIONS_SHA256='cdbc7a238bdbcc446b33dcb23fa78b751d7e73d9669d5d5eb7f6c63f14a072ca'
readonly GATE_DEFINITION_SHA256='322793215890947be1b989e5c42c2a640b1a83b67645c33d7df0517f782527aa'
readonly METHOD_PROFILE_SHA256='0d329981f1259e5d5f8138350af538a08a3d70a704241b384da6714f3b17724c'
readonly DEPLOYMENT_PROFILE_SHA256='2a5008b70a8ffe615cfcb2ca4b5d5a3687888c362861670a4a79e0de32874cfb'
readonly RUNTIME_DEPENDENCIES_SHA256='6254c1737babc3226d8e733c057886673133948af1b19eb66c1b29f48d2386f1'
readonly SCRIPT_117_REPORT_SHA256='5fab929e8e2cf838adc35d7c41d2dea5ed02f9670c9254ddf7f794c8e759ddff'
readonly SCRIPT_127_ARTIFACT_SHA256='c79691e4deae363a87233376d18d7ce16169e434d688788a257258d503582e00'
readonly SCRIPT_127_CHECKSUM_SHA256='074d9d8f883452953480b5453f36a6c01c7079311ba8a58548dea5c5557c92c6'
readonly SCRIPT_128_REPORT_SHA256='670fc0d8291c2e976ee191e171cfc30d82af017c8400ca669abf7f89c0804535'
readonly SCRIPT_128_RECEIPT_SHA256='681c83af5fe0f27fca04e50b965902a2050343cbb83e77a8160290a9ec9f166d'
readonly SCRIPT_128_CHECKSUM_SHA256='4dce90731fe9440f518552787a0f1e542d1a116d818c3033a1dabfac59b77d7b'
readonly EXPECTED_PROFILE_ID='ba4bac60b3f09f6be89db148d1df883748a2003f35a1cecfb6c74f53be74b865'
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
    *) printf 'script_129_extended_lane_capture=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_mode" != "$validate_mode" ]] || {
  printf 'script_129_extended_lane_capture=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in awk bash basename chmod curl date dirname grep head hostname kill mkdir mktemp mv pg_isready python3 rm sed sha256sum sleep stat tail tee tr uname; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_129_extended_lane_capture=blocked;reason=local_command_missing;command=%s\n' "$required" >&2
    exit 2
  }
done

check_file() {
  [[ -f "$1" && ! -L "$1" && -r "$1" ]] || {
    printf 'script_129_extended_lane_capture=blocked;reason=%s_unsafe\n' "$3" >&2
    exit 2
  }
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_129_extended_lane_capture=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}

check_file "$HELPER" "$HELPER_SHA256" lane_capture_helper
check_file "$EXTENDED_EVALUATOR" "$EXTENDED_EVALUATOR_SHA256" extended_evaluator
check_file "$BASE_EVALUATOR" "$BASE_EVALUATOR_SHA256" base_evaluator
check_file "$CASES" "$CASES_SHA256" case_set
check_file "$DECISIONS" "$DECISIONS_SHA256" tuning_decisions
check_file "$GATE_DEFINITION" "$GATE_DEFINITION_SHA256" gate_definition
check_file "$CONFIG_ROOT/method_profile.yaml" "$METHOD_PROFILE_SHA256" method_profile
check_file "$CONFIG_ROOT/deployment.yaml" "$DEPLOYMENT_PROFILE_SHA256" deployment_profile
check_file "$CONFIG_ROOT/runtime_dependencies.yaml" "$RUNTIME_DEPENDENCIES_SHA256" runtime_dependencies
check_file "$SCRIPT_117_REPORT" "$SCRIPT_117_REPORT_SHA256" script_117_report
check_file "$SCRIPT_127_ARTIFACT" "$SCRIPT_127_ARTIFACT_SHA256" script_127_artifact
check_file "$SCRIPT_127_CHECKSUM" "$SCRIPT_127_CHECKSUM_SHA256" script_127_checksum
check_file "$SCRIPT_128_REPORT" "$SCRIPT_128_REPORT_SHA256" script_128_report
check_file "$SCRIPT_128_RECEIPT" "$SCRIPT_128_RECEIPT_SHA256" script_128_receipt
check_file "$SCRIPT_128_CHECKSUM" "$SCRIPT_128_CHECKSUM_SHA256" script_128_checksum
for checksum in "$SCRIPT_127_CHECKSUM" "$SCRIPT_128_CHECKSUM"; do
  (
    cd -- "$(dirname -- "$checksum")"
    sha256sum --check --strict "$(basename -- "$checksum")" >/dev/null
  ) || {
    printf 'script_129_extended_lane_capture=blocked;reason=accepted_checksum_failed\n' >&2
    exit 2
  }
done
for fact in \
  'mrr_at_20=0.852173;strict_target=greater_than_0.91;strict_target_met=false' \
  'script_128_strict_mrr=pass;promotion_gate=not_met;next_gate=capture_extended_lane_rankings_and_search_profile_candidates'; do
  grep -Fq "$fact" "$SCRIPT_128_REPORT" || {
    printf 'script_129_extended_lane_capture=blocked;reason=script_128_contract_invalid\n' >&2
    exit 2
  }
done
grep -Eq '^\| `T11` \|.*strictly greater than `0\.91`.*\| FROZEN; STRICT TARGET AMENDED AFTER SCRIPT 127 \|$' "$DECISIONS" || {
  printf 'script_129_extended_lane_capture=blocked;reason=amended_t11_not_frozen\n' >&2
  exit 2
}

bash -n "${BASH_SOURCE[0]}"
for source in "$HELPER" "$EXTENDED_EVALUATOR" "$BASE_EVALUATOR"; do
  PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
    'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
    "$source"
done
PYTHONDONTWRITEBYTECODE=1 python3 -B "$HELPER" --self-test \
  | grep -Fxq 'extended_retrieval_lane_capture_self_test=pass' || {
    printf 'script_129_extended_lane_capture=blocked;reason=helper_self_test_failed\n' >&2
    exit 2
  }

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_mode" == true ]]; then
  printf '%s\n' \
    'purpose=validate_extended_retrieval_lane_ranking_capture' \
    "script_sha256=$script_sha256;helper_sha256=$HELPER_SHA256;case_set_sha256=$CASES_SHA256" \
    "script_127_artifact_sha256=$SCRIPT_127_ARTIFACT_SHA256;script_128_report_sha256=$SCRIPT_128_REPORT_SHA256" \
    "retrieval_profile_id=$EXPECTED_PROFILE_ID;capture_depths=20,20,20;case_count=60" \
    'helper_self_tests=1;database_contact=false;model_contact=false;credential_read=false;profile_changed=false' \
    'script_129_extended_lane_capture_source=pass'
  exit 0
fi

umask 077
work_root="$(mktemp -d /tmp/ishikawa-script-129.XXXXXX)"
nomic_key=''
database_password=''
report_path=''
helper_pid=''
artifact_committed=false
artifact_path=''
checksum_path=''

cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  nomic_key=''
  database_password=''
  unset nomic_key database_password ISHIKAWA_NOMIC_API_KEY ISHIKAWA_POSTGRESQL_PASSWORD
  if [[ "$helper_pid" =~ ^[0-9]+$ ]] && kill -0 "$helper_pid" 2>/dev/null; then
    kill -TERM "$helper_pid" 2>/dev/null || true
    wait "$helper_pid" 2>/dev/null || true
  fi
  if [[ "$artifact_committed" != true ]]; then
    [[ "$artifact_path" == "$ARTIFACT_ROOT"/extended_lane_rankings_*.json ]] && rm -f -- "$artifact_path"
    [[ "$checksum_path" == "$ARTIFACT_ROOT"/extended_lane_rankings_*.json.sha256 ]] && rm -f -- "$checksum_path"
  fi
  [[ "$work_root" == /tmp/ishikawa-script-129.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  [[ -z "$report_path" ]] || chmod 0600 "$report_path" 2>/dev/null || true
  exit "$status"
}
trap cleanup EXIT

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" && -d "$ARTIFACT_ROOT" && ! -L "$ARTIFACT_ROOT" ]] || {
  printf 'script_129_extended_lane_capture=blocked;reason=artifact_directory_unsafe\n' >&2
  exit 1
}
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/extended_lane_rankings_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
block() { emit "script_129_extended_lane_capture=blocked;reason=$1"; exit 1; }
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
emit 'purpose=capture_extended_ishikawa_retrieval_lane_rankings'
emit "started_utc=$timestamp;hostname=$actual_hostname;os_version=$actual_os_version;architecture=$actual_architecture"
emit "script_sha256=$script_sha256;helper_sha256=$HELPER_SHA256;case_set_sha256=$CASES_SHA256"
emit "script_128_report_sha256=$SCRIPT_128_REPORT_SHA256;retrieval_profile_id=$EXPECTED_PROFILE_ID"
emit 'authorized_actions=read_accepted_local_corpus_request_60_singleton_nomic_embeddings_retain_content_free_lane_rankings'
emit 'non_actions=no_database_write_no_gemma_contact_no_profile_change_no_package_change_no_question_vector_source_text_or_credential_retention'
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

helper_output="$work_root/helper.stdout"
helper_error="$work_root/helper.stderr"
artifact_candidate="$work_root/extended-lane-rankings.json"
emit 'milestone=extended_lane_capture;state=start;cases=60;query_embeddings=60;capture_depths=20,20,20'
started_epoch="$(date +%s)"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$HELPER" \
    --run \
    --python-root "$PYTHON_ROOT" \
    --config-root "$CONFIG_ROOT" \
    --cases "$CASES" \
    --baseline-observation "$SCRIPT_127_ARTIFACT" \
    --output "$artifact_candidate" \
    >"$helper_output" 2>"$helper_error" &
helper_pid="$!"
next_heartbeat_epoch=$(( started_epoch + 30 ))
while kill -0 "$helper_pid" 2>/dev/null; do
  sleep 5
  current_epoch="$(date +%s)"
  if (( current_epoch >= next_heartbeat_epoch )) && kill -0 "$helper_pid" 2>/dev/null; then
    emit "milestone=extended_lane_capture;state=running;elapsed_seconds=$(( current_epoch - started_epoch ))"
    next_heartbeat_epoch=$(( current_epoch + 30 ))
  fi
done
if wait "$helper_pid"; then helper_status=0; else helper_status=$?; fi
helper_pid=''
nomic_key=''
database_password=''
unset ISHIKAWA_NOMIC_API_KEY ISHIKAWA_POSTGRESQL_PASSWORD
if (( helper_status != 0 )); then
  reason="$(sed -nE 's/^extended_retrieval_lane_capture=blocked;reason=([A-Za-z0-9_]+)$/\1/p' "$helper_error" | tail -n 1)"
  [[ -n "$reason" ]] || reason=unclassified_helper_failure
  block "$reason"
fi
for marker in \
  'case_count=60;query_embeddings=60;capture_depths=20,20,20;gemma_contact=false;database_write=false' \
  'baseline_mrr_at_20=0.852173;baseline_reproduced=true;relevant_at_5=56/60;relevant_at_20=60/60' \
  'extended_retrieval_lane_capture=pass;profile_changed=false'; do
  grep -Fxq "$marker" "$helper_output" || block helper_pass_contract_invalid
done

PYTHONDONTWRITEBYTECODE=1 python3 -B - "$artifact_candidate" "$SCRIPT_127_ARTIFACT_SHA256" "$EXPECTED_PROFILE_ID" <<'PY'
import json
import sys
from pathlib import Path

value = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
metrics = value.get("reproduced_metrics", {})
cases = value.get("cases", [])
if (
    value.get("artifact_kind") != "ishikawa_extended_retrieval_lane_ranking_observation"
    or value.get("schema_version") != 1
    or value.get("baseline_observation_sha256") != sys.argv[2]
    or value.get("retrieval_profile_id") != sys.argv[3]
    or value.get("case_count") != 60
    or value.get("query_embedding_count") != 60
    or value.get("capture_depths") != {"exact": 20, "lexical": 20, "vector": 20}
    or value.get("database_boundary") != "repeatable_read_read_only"
    or value.get("baseline_reproduced") is not True
    or value.get("profile_changed") is not False
    or value.get("gemma_contact") is not False
    or value.get("database_write") is not False
    or value.get("question_text_retained") is not False
    or value.get("query_vectors_retained") is not False
    or value.get("source_text_retained") is not False
    or metrics.get("mrr_at_20") != "0.852173"
    or metrics.get("mrr_fraction_numerator") != 28633
    or metrics.get("mrr_fraction_denominator") != 33600
    or metrics.get("cases_with_relevant_at_5") != 56
    or metrics.get("cases_with_relevant_at_20") != 60
    or not isinstance(cases, list)
    or len(cases) != 60
):
    raise SystemExit("lane ranking artifact contract invalid")
expected_ids = {f"E-{index:03d}" for index in range(1, 61)}
if {case.get("case_id") for case in cases} != expected_ids:
    raise SystemExit("lane ranking case inventory invalid")
for case in cases:
    lanes = case.get("lanes")
    if not isinstance(lanes, dict) or set(lanes) != {"exact", "lexical", "vector"}:
        raise SystemExit("lane ranking case contract invalid")
    for lane in lanes.values():
        if not isinstance(lane, list) or len(lane) > 20:
            raise SystemExit("lane ranking depth invalid")
        for expected_rank, candidate in enumerate(lane, start=1):
            if (
                not isinstance(candidate, dict)
                or set(candidate) != {"chunk_id", "rank", "relevant"}
                or not isinstance(candidate.get("chunk_id"), str)
                or candidate.get("rank") != expected_rank
                or type(candidate.get("relevant")) is not bool
            ):
                raise SystemExit("lane ranking candidate invalid")
for forbidden in (
    "question", "query_vector", "embedding_vector", "vector_values",
    "retrieval_text", "source_text", "credential", "generated_answer",
):
    stack = [value]
    while stack:
        current = stack.pop()
        if isinstance(current, dict):
            if forbidden in current:
                raise SystemExit("lane ranking artifact contains a forbidden field")
            stack.extend(current.values())
        elif isinstance(current, list):
            stack.extend(current)
PY

identity_line="$(grep -E '^observation_set_id=[0-9a-f]{64};artifact_sha256=[0-9a-f]{64};artifact_bytes=[0-9]+$' "$helper_output")" \
  || block observation_identity_invalid
observation_set_id="$(sed -nE 's/^observation_set_id=([0-9a-f]{64});.*/\1/p' <<<"$identity_line")"
helper_artifact_sha256="$(sed -nE 's/^.*;artifact_sha256=([0-9a-f]{64});.*/\1/p' <<<"$identity_line")"
artifact_sha256="$(sha256sum "$artifact_candidate" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$artifact_candidate")"
[[ "$artifact_sha256" == "$helper_artifact_sha256" ]] || block artifact_identity_mismatch
artifact_path="$ARTIFACT_ROOT/extended_lane_rankings_${observation_set_id}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] \
  || block artifact_path_exists
mv -- "$artifact_candidate" "$artifact_path"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
(
  cd -- "$ARTIFACT_ROOT"
  sha256sum --check --strict "$(basename -- "$checksum_path")" >/dev/null
) || block artifact_checksum_failed
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true
artifact_committed=true
emit 'milestone=extended_lane_capture;state=pass'
emit 'baseline_mrr_at_20=0.852173;baseline_reproduced=true;strict_production_target=greater_than_0.91;profile_changed=false'
emit 'database_boundary=repeatable_read_read_only;database_write=false;nomic_contact=true;gemma_contact=false;questions_retained=false;vectors_retained=false;source_text_retained=false;credentials_retained=false'
emit "observation_set_id=$observation_set_id;accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$artifact_bytes;accepted_checksum=$checksum_path"
emit 'script_129_extended_lane_capture=pass;baseline_reproduced=true;next_gate=search_extended_retrieval_profile_candidates'
