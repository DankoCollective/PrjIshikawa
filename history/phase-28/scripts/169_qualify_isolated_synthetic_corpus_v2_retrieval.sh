#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify live read-only retrieval against the Script 168-published isolated
#   synthetic-corpus-v2 database before returning to optimization work.
#
# Boundaries:
#   Read-only PostgreSQL on cluster 16/ishikawa-v2, fresh query embeddings from
#   the forwarded Nomic endpoint, no Gemma call, no corpus-v1 contact, no
#   database mutation, no profile change, and restoration of the cluster's
#   initial online/down state.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/169_qualify_isolated_synthetic_corpus_v2_retrieval.sh --run

usage() {
  sed -n '3,18p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Run the 68-case live isolated retrieval qualification.' \
    '  --validate-only Validate bound inputs and evaluator self-test only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly CONFIG_ROOT="$PRODUCT_ROOT/config/templates"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly SCRIPT_168="$SCRIPT_DIR/168_publish_synthetic_corpus_v2_isolated.sh"
readonly EVALUATOR="$SCRIPT_DIR/measure_live_synthetic_corpus_v2_retrieval.py"
readonly BODY_CASES="$PHASE_ROOT/reference/ishikawa-synthetic-corpus-v2-body-mrr-cases.json"
readonly HEADER_CASES="$PHASE_ROOT/reference/ishikawa-synthetic-corpus-v2-header-cases.json"
readonly SCRIPT_168_REPORT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-isolated-publication/isolated_synthetic_corpus_v2_publication_20261022T204745Z_1DmnRN.txt"
readonly PUBLICATION_RECEIPT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-isolated-publication/isolated_synthetic_corpus_v2_publication_20261022T204745Z.json"
readonly PUBLICATION_RECEIPT_SUMS="$PUBLICATION_RECEIPT.sha256"
readonly RETAINED_ARTIFACTS="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-isolated-publication/retained-derived-artifacts-20261022T204745Z"
readonly PUBLISHED_CHUNKS="$RETAINED_ARTIFACTS/22/22a4d2694938268462f0c78a79b51771abb48a8e1a23420ec0f443e1e7d8c5fd"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-live-retrieval"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-live-retrieval"

readonly DECISIONS_SHA256='f210a94a3b5413efb107fb97a77e5085e9da37bda53348c3006adad7a11c35f9'
readonly SCRIPT_168_SHA256='0c4b7696e8f2e7f0ad0040764d24db2233e279382185fc5086467137bd5cd73b'
readonly EVALUATOR_SHA256='a7b17fcad0255ae9678741289e383bbc02dfcc72d4f20c2140aa1727adb4d276'
readonly BODY_CASES_SHA256='47882a93996ef1d8331606c173c85f2076e457c989c9ab3cd6bad31d5ce5613e'
readonly HEADER_CASES_SHA256='a873a61b59de0a8ea082c3fc0c987ab9cf7b97d79ed843832be354af8eae6e2c'
readonly PUBLISHED_CHUNKS_SHA256='22a4d2694938268462f0c78a79b51771abb48a8e1a23420ec0f443e1e7d8c5fd'
readonly METHOD_PROFILE_SHA256='0d329981f1259e5d5f8138350af538a08a3d70a704241b384da6714f3b17724c'
readonly RUNTIME_DEPENDENCIES_SHA256='6254c1737babc3226d8e733c057886673133948af1b19eb66c1b29f48d2386f1'
readonly SCRIPT_168_REPORT_SHA256='bdf7811635bc8fd447bd6838330cada91e183ffe860c5198fb37e95d79ec0f04'
readonly PUBLICATION_RECEIPT_SHA256='e06a7b1affc96b0c0acf625084b280a9689e8e5ed0153b773bc14227d0975a12'
readonly EXPECTED_HOSTNAME='DankoSurface'
readonly EXPECTED_OS_VERSION='24.04'
readonly EXPECTED_ARCHITECTURE='aarch64'
readonly POSTGRESQL_VERSION='16'
readonly V2_CLUSTER_NAME='ishikawa-v2'
readonly V2_PORT='5433'
readonly NOMIC_HEALTH_URL='http://127.0.0.1:8001/health'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_169_isolated_v2_retrieval_qualification=blocked;reason=argument_invalid\n' >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_169_isolated_v2_retrieval_qualification=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required_command in awk bash curl date find grep hostname kill mkdir mktemp \
  pg_ctlcluster pg_isready pg_lsclusters python3 rm sed sha256sum sleep sort \
  sudo tee tr uname; do
  command -v "$required_command" >/dev/null 2>&1 || {
    printf 'script_169_isolated_v2_retrieval_qualification=blocked;reason=local_command_missing;command=%s\n' \
      "$required_command" >&2
    exit 2
  }
done

check_file() {
  local path="$1" expected_sha256="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] || {
    printf 'script_169_isolated_v2_retrieval_qualification=blocked;reason=%s_unsafe\n' \
      "$label" >&2
    exit 2
  }
  [[ "$(sha256sum "$path" | sed 's/[[:space:]].*$//')" == "$expected_sha256" ]] || {
    printf 'script_169_isolated_v2_retrieval_qualification=blocked;reason=%s_identity_changed\n' \
      "$label" >&2
    exit 2
  }
}

check_file "$DECISIONS" "$DECISIONS_SHA256" decisions
check_file "$SCRIPT_168" "$SCRIPT_168_SHA256" script_168
check_file "$EVALUATOR" "$EVALUATOR_SHA256" evaluator
check_file "$BODY_CASES" "$BODY_CASES_SHA256" body_cases
check_file "$HEADER_CASES" "$HEADER_CASES_SHA256" header_cases
check_file "$PUBLISHED_CHUNKS" "$PUBLISHED_CHUNKS_SHA256" published_chunks
check_file "$CONFIG_ROOT/method_profile.yaml" "$METHOD_PROFILE_SHA256" method_profile
check_file "$CONFIG_ROOT/runtime_dependencies.yaml" "$RUNTIME_DEPENDENCIES_SHA256" runtime_dependencies
check_file "$SCRIPT_168_REPORT" "$SCRIPT_168_REPORT_SHA256" script_168_report
check_file "$PUBLICATION_RECEIPT" "$PUBLICATION_RECEIPT_SHA256" publication_receipt
[[ -f "$PUBLICATION_RECEIPT_SUMS" && ! -L "$PUBLICATION_RECEIPT_SUMS" ]] || {
  printf 'script_169_isolated_v2_retrieval_qualification=blocked;reason=publication_receipt_checksum_unsafe\n' >&2
  exit 2
}
(cd -- "$(dirname -- "$PUBLICATION_RECEIPT")" \
  && sha256sum --quiet -c "$(basename -- "$PUBLICATION_RECEIPT_SUMS")") || {
  printf 'script_169_isolated_v2_retrieval_qualification=blocked;reason=publication_receipt_checksum_failed\n' >&2
  exit 2
}
[[ -d "$RETAINED_ARTIFACTS" && ! -L "$RETAINED_ARTIFACTS" ]] || {
  printf 'script_169_isolated_v2_retrieval_qualification=blocked;reason=retained_artifacts_unsafe\n' >&2
  exit 2
}
(cd -- "$RETAINED_ARTIFACTS" && sha256sum --quiet -c SHA256SUMS) || {
  printf 'script_169_isolated_v2_retrieval_qualification=blocked;reason=retained_artifact_checksum_failed\n' >&2
  exit 2
}

grep -Fxq 'script_168_isolated_synthetic_corpus_v2_publication=pass' \
  "$SCRIPT_168_REPORT" || {
  printf 'script_169_isolated_v2_retrieval_qualification=blocked;reason=script_168_not_clean\n' >&2
  exit 1
}
grep -Fxq 'next_gate=qualify_isolated_synthetic_corpus_v2_retrieval_before_optimization_return' \
  "$SCRIPT_168_REPORT" || {
  printf 'script_169_isolated_v2_retrieval_qualification=blocked;reason=script_168_next_gate_invalid\n' >&2
  exit 1
}
for decision in V13-24 V13-25 V13-26 V13-27 V13-28 V13-29 V13-30; do
  grep -Fq "| \`$decision\` " "$DECISIONS" || {
    printf 'script_169_isolated_v2_retrieval_qualification=blocked;reason=decision_not_frozen;decision=%s\n' \
      "$decision" >&2
    exit 1
  }
done

PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$PUBLICATION_RECEIPT" "$PUBLISHED_CHUNKS_SHA256" <<'PY'
import json
import pathlib
import sys

receipt = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert receipt["schema"] == "ishikawa.synthetic-corpus-v2-isolated-publication.v1"
assert receipt["postgresql"] == {
    "version": 16,
    "cluster": "ishikawa-v2",
    "port": 5433,
    "start_policy": "manual",
    "database": "rag_catalog",
}
assert receipt["published"]["corpus_identity"] == "synthetic-corpus-v2"
assert receipt["published"]["documents"] == 6
assert receipt["published"]["pages"] == 26
assert receipt["published"]["chunks"] == 139
assert receipt["published"]["citations"] == 139
assert receipt["published"]["embeddings"] == 139
assert receipt["published"]["document_control_metadata_candidates"] == 6
assert receipt["published"]["departments"] == 4
assert receipt["published"]["chunk_artifact_sha256"] == sys.argv[2]
assert receipt["corpus_v1"]["unchanged"] is True
assert receipt["boundaries"]["optimization_gate_used"] is False
assert receipt["boundaries"]["retrieval_profile_changed"] is False
assert receipt["status"] == "published_isolated"
assert receipt["next_gate"] == "qualify_isolated_synthetic_corpus_v2_retrieval"
PY

bash -n "${BASH_SOURCE[0]}"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
  "$EVALUATOR"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" --self-test \
  | grep -Fxq 'live_synthetic_corpus_v2_retrieval_measurement_self_test=pass' || {
  printf 'script_169_isolated_v2_retrieval_qualification=blocked;reason=evaluator_self_test_failed\n' >&2
  exit 2
}
PYTHONDONTWRITEBYTECODE=1 python3 -B -c 'import psycopg; assert psycopg.__version__' || {
  printf 'script_169_isolated_v2_retrieval_qualification=blocked;reason=psycopg_unavailable\n' >&2
  exit 2
}

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | sed 's/[[:space:]].*$//')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_isolated_synthetic_corpus_v2_live_retrieval_qualification' \
    "script_sha256=$script_sha256;evaluator_sha256=$EVALUATOR_SHA256;script_168_report_sha256=$SCRIPT_168_REPORT_SHA256" \
    "body_cases_sha256=$BODY_CASES_SHA256;header_cases_sha256=$HEADER_CASES_SHA256;published_chunks_sha256=$PUBLISHED_CHUNKS_SHA256" \
    'case_count=68;body_cases=60;header_cases=8;expected_inventory=6,26,139,139,139,6' \
    'database_contact=false;model_contact=false;credential_read=false;database_write=false;corpus_v1_contact=false;retrieval_profile_changed=false;service_state_changed=false' \
    '' \
    'SCRIPT RESULT' \
    'script_169_isolated_v2_retrieval_qualification=pass'
  exit 0
fi

umask 077
report_path=''
artifact_path=''
artifact_checksum_path=''
work_root=''
evaluator_pid=''
nomic_key=''
database_password=''
failure_reason=''
script_result=''
cluster_started_by_script=false

emit() {
  printf '%s\n' "$1" | tee -a "$report_path"
}

block() {
  failure_reason="$1"
  exit 1
}

cleanup() {
  local initial_status="$?"
  trap - EXIT HUP INT TERM
  set +e
  unset ISHIKAWA_NOMIC_API_KEY ISHIKAWA_POSTGRESQL_PASSWORD
  nomic_key=''
  database_password=''
  if [[ "$evaluator_pid" =~ ^[0-9]+$ ]] && kill -0 "$evaluator_pid" 2>/dev/null; then
    kill -TERM "$evaluator_pid" 2>/dev/null || true
    wait "$evaluator_pid" 2>/dev/null || true
  fi
  if [[ "$cluster_started_by_script" == true ]]; then
    if ! sudo -n pg_ctlcluster --skip-systemctl-redirect \
        "$POSTGRESQL_VERSION" "$V2_CLUSTER_NAME" stop >/dev/null 2>&1; then
      printf 'milestone=isolated_cluster_state_restoration;state=awaiting_attended_sudo\n'
      if sudo -v && sudo -n pg_ctlcluster --skip-systemctl-redirect \
          "$POSTGRESQL_VERSION" "$V2_CLUSTER_NAME" stop >/dev/null 2>&1; then
        printf 'milestone=isolated_cluster_state_restoration;state=pass;restored_status=down\n'
      else
        printf 'milestone=isolated_cluster_state_restoration;state=blocked;restored_status=unknown\n'
        initial_status=1
        [[ -n "$failure_reason" ]] || failure_reason='isolated_cluster_state_restoration_failed'
      fi
    else
      printf 'milestone=isolated_cluster_state_restoration;state=pass;restored_status=down\n'
    fi
  fi
  if (( initial_status != 0 )); then
    [[ -n "$artifact_path" && "$artifact_path" == "$ARTIFACT_ROOT"/* ]] \
      && rm -f -- "$artifact_path"
    [[ -n "$artifact_checksum_path" && "$artifact_checksum_path" == "$ARTIFACT_ROOT"/* ]] \
      && rm -f -- "$artifact_checksum_path"
  fi
  [[ -n "$work_root" && "$work_root" == /tmp/ishikawa-script-169.* ]] \
    && rm -rf -- "$work_root"
  if (( initial_status == 0 )); then
    script_result='pass'
  else
    script_result='blocked'
    [[ -n "$failure_reason" ]] || failure_reason="unexpected_failure_exit_$initial_status"
  fi
  if [[ -n "$report_path" && -f "$report_path" ]]; then
    {
      printf '\nSCRIPT RESULT\n'
      [[ "$script_result" == pass ]] || printf 'reason=%s\n' "$failure_reason"
      printf 'script_169_isolated_v2_retrieval_qualification=%s\n' "$script_result"
    } >>"$report_path"
    printf 'local_report=%s\n' "$report_path"
    printf 'local_report_sha256=%s\n' \
      "$(sha256sum "$report_path" | sed 's/[[:space:]].*$//')"
  fi
  printf '\nSCRIPT RESULT\n'
  [[ "$script_result" == pass ]] || printf 'reason=%s\n' "$failure_reason"
  printf 'script_169_isolated_v2_retrieval_qualification=%s\n' "$script_result"
  exit "$initial_status"
}
trap cleanup EXIT HUP INT TERM

read_secret() {
  local label="$1" output_name="$2" value=''
  printf '%s (input hidden): ' "$label" >/dev/tty
  IFS= read -r -s value </dev/tty || block secret_input_failed
  printf '\n' >/dev/tty
  (( ${#value} >= 1 && ${#value} <= 4096 )) || block secret_length_invalid
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] \
    || block secret_character_invalid
  printf -v "$output_name" '%s' "$value"
  value=''
}

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/isolated_v2_live_retrieval_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-script-169.XXXXXX)"
artifact_path="$ARTIFACT_ROOT/isolated_v2_live_retrieval_${timestamp}.json"
artifact_checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" \
  && ! -e "$artifact_checksum_path" && ! -L "$artifact_checksum_path" ]] \
  || block artifact_path_collision

emit 'purpose=qualify_published_synthetic_corpus_v2_live_retrieval'
emit "started_utc=$timestamp;script_sha256=$script_sha256;evaluator_sha256=$EVALUATOR_SHA256"
emit 'authorized_actions=read_isolated_v2_database_call_forwarded_nomic_retain_content_free_ranking_observation'
emit 'non_actions=no_database_write_no_corpus_v1_contact_no_gemma_contact_no_black_corpus_access_no_profile_change_no_persistent_service_state_change_no_optimization_promotion'

actual_hostname="$(hostname -s)"
actual_architecture="$(uname -m)"
actual_os="$(. /etc/os-release && printf '%s|%s' "$ID" "$VERSION_ID")"
[[ "$actual_hostname" == "$EXPECTED_HOSTNAME" ]] || block hostname_mismatch
[[ "$actual_os" == "ubuntu|$EXPECTED_OS_VERSION" ]] || block os_identity_mismatch
[[ "$actual_architecture" == "$EXPECTED_ARCHITECTURE" ]] || block architecture_mismatch
emit "milestone=local_host_identity;state=pass;hostname=$actual_hostname;os=ubuntu-$EXPECTED_OS_VERSION;architecture=$actual_architecture"

cluster_line="$(pg_lsclusters --no-header 2>/dev/null \
  | awk -v version="$POSTGRESQL_VERSION" -v name="$V2_CLUSTER_NAME" \
    '$1 == version && $2 == name {print; found=1} END {if (!found) exit 1}')" \
  || block isolated_cluster_missing
read -r observed_version observed_name observed_port observed_status _ <<<"$cluster_line"
[[ "$observed_version|$observed_name|$observed_port" \
  == "$POSTGRESQL_VERSION|$V2_CLUSTER_NAME|$V2_PORT" \
  && "$observed_status" =~ ^(online|down)$ ]] \
  || block isolated_cluster_posture_invalid
cluster_start_policy="$(awk '
  /^[[:space:]]*#/ {next}
  /^[[:space:]]*$/ {next}
  {print $1; exit}
' "/etc/postgresql/$POSTGRESQL_VERSION/$V2_CLUSTER_NAME/start.conf" 2>/dev/null)" \
  || block isolated_cluster_start_policy_unreadable
[[ "$cluster_start_policy" == manual ]] || block isolated_cluster_start_policy_changed
if [[ "$observed_status" == down ]]; then
  emit 'milestone=isolated_cluster_start;state=awaiting_attended_sudo;initial_status=down'
  sudo -v || block sudo_authorization_failed
  cluster_started_by_script=true
  sudo -n pg_ctlcluster --skip-systemctl-redirect \
    "$POSTGRESQL_VERSION" "$V2_CLUSTER_NAME" start \
    >"$work_root/cluster-start.stdout" 2>"$work_root/cluster-start.stderr" \
    || block isolated_cluster_start_failed
fi
pg_isready -q -h 127.0.0.1 -p "$V2_PORT" -d rag_catalog -t 5 \
  || block isolated_cluster_unready
emit "milestone=isolated_cluster;state=pass;cluster=16/ishikawa-v2;port=5433;database=rag_catalog;start_policy=manual;initial_status=$observed_status;current_status=online"

nomic_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
  --connect-timeout 5 --max-time 10 "$NOMIC_HEALTH_URL" 2>/dev/null || true)"
[[ "$nomic_status" == 200 ]] || block nomic_forwarded_health_unavailable
emit 'milestone=nomic_forwarded_health;state=pass;http_status=200;gemma_required=false'

read_secret 'Nomic API key' nomic_key
read_secret 'isolated v2 rag_retrieval PostgreSQL password' database_password
export ISHIKAWA_NOMIC_API_KEY="$nomic_key"
export ISHIKAWA_POSTGRESQL_PASSWORD="$database_password"
emit 'milestone=runtime_credentials;state=accepted;credential_values_retained=false'

evaluator_output="$work_root/evaluator.stdout"
evaluator_error="$work_root/evaluator.stderr"
emit 'milestone=live_retrieval_measurement;state=start;cases=68;query_embeddings=68'
measurement_started="$(date +%s)"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" \
  --run \
  --scripts-root "$SCRIPT_DIR" \
  --python-root "$PYTHON_ROOT" \
  --config-root "$CONFIG_ROOT" \
  --chunks "$PUBLISHED_CHUNKS" \
  --expected-chunks-sha256 "$PUBLISHED_CHUNKS_SHA256" \
  --body-cases "$BODY_CASES" \
  --expected-body-cases-sha256 "$BODY_CASES_SHA256" \
  --header-cases "$HEADER_CASES" \
  --expected-header-cases-sha256 "$HEADER_CASES_SHA256" \
  --postgresql-port "$V2_PORT" \
  --output "$artifact_path" \
  >"$evaluator_output" 2>"$evaluator_error" &
evaluator_pid="$!"
next_heartbeat=$(( measurement_started + 30 ))
while kill -0 "$evaluator_pid" 2>/dev/null; do
  sleep 5
  current_epoch="$(date +%s)"
  if (( current_epoch >= next_heartbeat )) && kill -0 "$evaluator_pid" 2>/dev/null; then
    emit "milestone=live_retrieval_measurement;state=running;elapsed_seconds=$(( current_epoch - measurement_started ))"
    next_heartbeat=$(( current_epoch + 30 ))
  fi
done
if wait "$evaluator_pid"; then
  evaluator_status=0
else
  evaluator_status="$?"
fi
evaluator_pid=''
unset ISHIKAWA_NOMIC_API_KEY ISHIKAWA_POSTGRESQL_PASSWORD
nomic_key=''
database_password=''
if (( evaluator_status != 0 )); then
  evaluator_reason="$(sed -nE \
    's/^live_synthetic_corpus_v2_retrieval_measurement=blocked;reason=([A-Za-z0-9_]+)$/\1/p' \
    "$evaluator_error" | tail -n 1)"
  [[ -n "$evaluator_reason" ]] || evaluator_reason=unclassified_evaluator_failure
  emit "milestone=live_retrieval_measurement;state=blocked;reason=$evaluator_reason;stdout_sha256=$(sha256sum "$evaluator_output" | sed 's/[[:space:]].*$//');stderr_sha256=$(sha256sum "$evaluator_error" | sed 's/[[:space:]].*$//');raw_output_retained=false"
  block "live_retrieval_$evaluator_reason"
fi
for marker in \
  'case_count=68;body_cases=60;header_cases=8;query_embeddings=68' \
  'header_mrr_at_20=1.000000;header_relevant_at_5=8/8;header_required_evidence_at_20=11/11' \
  'live_synthetic_corpus_v2_retrieval_measurement=pass'; do
  grep -Fxq "$marker" "$evaluator_output" || block evaluator_pass_contract_invalid
done
mapfile -t body_summaries < <(grep -E \
  '^body_mrr_at_20=[0-9]+\.[0-9]{6};body_relevant_at_5=[0-9]+/60;body_relevant_at_20=[0-9]+/60$' \
  "$evaluator_output" || true)
(( ${#body_summaries[@]} == 1 )) || block evaluator_body_summary_invalid
body_summary="${body_summaries[0]}"
mapfile -t baseline_summaries < <(grep -E \
  '^preingestion_baseline_reproduced=(true|false);preingestion_baseline_comparison_recorded=true;database_write=false;gemma_contact=false;optimization_gate_used=false$' \
  "$evaluator_output" || true)
(( ${#baseline_summaries[@]} == 1 )) || block evaluator_baseline_summary_invalid
baseline_summary="${baseline_summaries[0]}"
emit "milestone=live_retrieval_measurement;state=pass;elapsed_seconds=$(( $(date +%s) - measurement_started ));cases=68;query_embeddings=68"
emit "milestone=published_body_measurement;state=pass;$body_summary"
emit 'milestone=published_header_gate;state=pass;header_mrr_at_20=1.000000;header_relevant_at_5=8/8;header_required_evidence_at_20=11/11'
emit "milestone=preingestion_baseline_comparison;state=recorded;$baseline_summary"

(cd -- "$ARTIFACT_ROOT" && sha256sum "$(basename -- "$artifact_path")" \
  >"$(basename -- "$artifact_checksum_path")")
(cd -- "$ARTIFACT_ROOT" \
  && sha256sum --quiet -c "$(basename -- "$artifact_checksum_path")") \
  || block retained_observation_checksum_failed
emit "retained_observation=$artifact_path;retained_observation_sha256=$(sha256sum "$artifact_path" | sed 's/[[:space:]].*$//')"
emit 'isolated_v2_retrieval_qualification=pass;database_write=false;corpus_v1_contact=false;gemma_contact=false;retrieval_profile_changed=false;cluster_initial_state_restored_on_exit=true'
emit 'optimization_status=observational_baseline_not_promoted;next_gate=return_to_bounded_retrieval_optimization_review'
