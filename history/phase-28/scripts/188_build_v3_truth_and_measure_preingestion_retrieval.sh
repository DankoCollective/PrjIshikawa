#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Build checksum-bound retrieval truth for all 30 synthetic-corpus-v3
#   documents and measure the frozen v1.3 retrieval implementation before any
#   corpus-v3 ingestion or retrieval tuning.
#
# Boundaries:
#   Calls only the existing loopback Nomic endpoint. Uses a private temporary
#   PostgreSQL cluster with no TCP listener and no corpus tables for native
#   lexical ranking. Does not call Gemma, ingest or publish corpus v3, contact
#   an accepted database, tune retrieval, or change any accepted release.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/188_build_v3_truth_and_measure_preingestion_retrieval.sh --run

usage() {
  sed -n '3,19p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Build truth, embed candidates, and measure retrieval.' \
    '  --validate-only Validate bound inputs and local contracts only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly TRUTH_BUILDER="$PHASE_ROOT/reference/generate_synthetic_corpus_v3_retrieval_truth.py"
readonly EMBEDDER="$SCRIPT_DIR/embed_document_candidates_via_endpoint.py"
readonly EVALUATOR="$SCRIPT_DIR/measure_synthetic_corpus_v3_preingestion.py"
readonly SCRIPT_187_REPORT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v3/synthetic_corpus_v3_20261023T043639Z_Ow3DXh.txt"
readonly CANDIDATE_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v3/synthetic_corpus_v3_candidate_20261023T043639Z"
readonly CHECKSUM_MANIFEST="$CANDIDATE_ROOT/SHA256SUMS"
readonly CORPUS_TRUTH="$CANDIDATE_ROOT/evaluation/corpus_truth.json"
readonly CHUNKS="$CANDIDATE_ROOT/qualification/chunks.json"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v3-preingestion"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v3-preingestion"
readonly INITDB='/usr/lib/postgresql/16/bin/initdb'
readonly PG_CTL='/usr/lib/postgresql/16/bin/pg_ctl'
readonly NOMIC_HEALTH_URL='http://127.0.0.1:8001/health'
readonly NOMIC_EMBEDDING_URL='http://127.0.0.1:8001/v1/embeddings'
readonly NOMIC_TOKENIZER_URL='http://127.0.0.1:8001/tokenize'
readonly TEMPORARY_POSTGRESQL_PORT=65433
readonly EXPECTED_HOST='DankoSurface'
readonly EXPECTED_OS_ID='ubuntu'
readonly EXPECTED_OS_VERSION='24.04'
readonly EXPECTED_ARCHITECTURE='aarch64'

readonly SCRIPT_187_REPORT_SHA256='2536d865e94b99c9df0fa3b216eeacc55d1ef445019ffcc5c0f2cafd169a83ac'
readonly CHECKSUM_MANIFEST_SHA256='3220c5ae7fd16c37086511893c63c4784b9adf10635e40c79332b4a7b4c79fce'
readonly CORPUS_TRUTH_SHA256='85f753ced3956e609b1fada2419888bae1099a308be3c905310765796c80f573'
readonly CHUNKS_SHA256='d659ed731cced4c22a6cabda940cb5d8246acd97ef050f46efbf45717c552703'
readonly TRUTH_BUILDER_SHA256='8a96fecf5950159b58a72702d27435d55c91b515cfa7278e2882521505865fa6'
readonly EMBEDDER_SHA256='8f3c23ca30904dfb48a37f3366fd4b7873769bb92a527479fec5696f7fc456dc'
readonly EVALUATOR_SHA256='4d7138d5ca94a8422c02727b24014a04abc0a3ac0c2e48f3fbfa0bd07a7633dc'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      printf '%s\n' 'script_188_v3_preingestion_retrieval=blocked' >&2
      usage >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf '%s\n' 'script_188_v3_preingestion_retrieval=blocked' >&2
  exit 2
}

for command_name in awk bash basename chmod curl date dirname grep hostname id kill \
  mkdir mktemp mv python3 rm sed sha256sum sleep stat tee tr uname; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'missing_command=%s\n\nSCRIPT RESULT\nscript_188_v3_preingestion_retrieval=blocked\n' \
      "$command_name" >&2
    exit 2
  }
done

check_file() {
  local path="$1" expected_sha256="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] || {
    printf 'reason=%s_unsafe\n\nSCRIPT RESULT\nscript_188_v3_preingestion_retrieval=blocked\n' \
      "$label" >&2
    exit 2
  }
  [[ "$(sha256sum "$path" | awk '{print $1}')" == "$expected_sha256" ]] || {
    printf 'reason=%s_identity_changed\n\nSCRIPT RESULT\nscript_188_v3_preingestion_retrieval=blocked\n' \
      "$label" >&2
    exit 2
  }
}

check_file "$SCRIPT_187_REPORT" "$SCRIPT_187_REPORT_SHA256" script_187_report
check_file "$CHECKSUM_MANIFEST" "$CHECKSUM_MANIFEST_SHA256" candidate_checksum_manifest
check_file "$CORPUS_TRUTH" "$CORPUS_TRUTH_SHA256" corpus_truth
check_file "$CHUNKS" "$CHUNKS_SHA256" chunks
check_file "$TRUTH_BUILDER" "$TRUTH_BUILDER_SHA256" truth_builder
check_file "$EMBEDDER" "$EMBEDDER_SHA256" embedder
check_file "$EVALUATOR" "$EVALUATOR_SHA256" evaluator
for executable in "$INITDB" "$PG_CTL"; do
  [[ -f "$executable" && ! -L "$executable" && -x "$executable" ]] || {
    printf '%s\n\nSCRIPT RESULT\n%s\n' \
      'reason=postgresql_16_binary_unsafe' \
      'script_188_v3_preingestion_retrieval=blocked' >&2
    exit 2
  }
done

grep -Fxq 'script_187_synthetic_corpus_v3=pass' "$SCRIPT_187_REPORT" || {
  printf '%s\n\nSCRIPT RESULT\n%s\n' \
    'reason=script_187_not_clean_pass' \
    'script_188_v3_preingestion_retrieval=blocked' >&2
  exit 1
}
grep -Fxq 'next_gate=build_v3_retrieval_truth_and_preingestion_measurement' \
  "$SCRIPT_187_REPORT" || {
  printf '%s\n\nSCRIPT RESULT\n%s\n' \
    'reason=script_187_next_gate_invalid' \
    'script_188_v3_preingestion_retrieval=blocked' >&2
  exit 1
}

checksum_output="$(cd -- "$CANDIDATE_ROOT" && sha256sum --check --strict SHA256SUMS 2>&1)" || {
  printf '%s\n\nSCRIPT RESULT\n%s\n' \
    'reason=candidate_inventory_invalid' \
    'script_188_v3_preingestion_retrieval=blocked' >&2
  exit 1
}
[[ "$(grep -c ': OK$' <<<"$checksum_output")" == 40 ]] || {
  printf '%s\n\nSCRIPT RESULT\n%s\n' \
    'reason=candidate_inventory_count_invalid' \
    'script_188_v3_preingestion_retrieval=blocked' >&2
  exit 1
}

bash -n "${BASH_SOURCE[0]}"
for python_source in "$TRUTH_BUILDER" "$EMBEDDER" "$EVALUATOR" \
  "$PYTHON_ROOT/ishikawa/retrieval.py"; do
  PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
    'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
    "$python_source"
done
PYTHONDONTWRITEBYTECODE=1 python3 -B "$TRUTH_BUILDER" --self-test \
  | grep -Fxq 'synthetic_corpus_v3_retrieval_truth_builder_self_test=pass'
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EMBEDDER" --self-test \
  | grep -Fxq 'document_embedding_endpoint_producer_self_test=pass'
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" --self-test \
  | grep -Fxq 'synthetic_corpus_v3_preingestion_measurement_self_test=pass'
PYTHONDONTWRITEBYTECODE=1 python3 -B -c 'import psycopg; assert psycopg.__version__'
PYTHONDONTWRITEBYTECODE=1 python3 -B - "$CHUNKS" <<'PY'
import collections
import json
import pathlib
import sys

value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
candidates = [item for document in value["documents"] for item in document["candidates"]]
counts = collections.Counter(item["projection_kind"] for item in candidates)
assert len(value["documents"]) == 30
assert len(candidates) == 943
assert counts["document_control_metadata"] == 30
assert counts["section_page_representative"] == 157
assert value["method_profile"]["name"] == "ishikawa-structural-chunk-candidates-v5"
assert value["method_profile"]["document_local_duplicate_canonicalization"] == "first_atomic_content_digest_in_source_order"
PY

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_v3_retrieval_truth_and_preingestion_measurement' \
    "script_sha256=$script_sha256;script_187_report_sha256=$SCRIPT_187_REPORT_SHA256" \
    "candidate_manifest_sha256=$CHECKSUM_MANIFEST_SHA256;candidate_files=40" \
    "corpus_truth_sha256=$CORPUS_TRUTH_SHA256;chunks_sha256=$CHUNKS_SHA256" \
    "truth_builder_sha256=$TRUTH_BUILDER_SHA256;embedder_sha256=$EMBEDDER_SHA256;evaluator_sha256=$EVALUATOR_SHA256" \
    'documents=30;pages=150;candidates=943;atomic=786;section_page_representatives=157' \
    'planned_cases=180;body=120;relationships=30;headers=30;promotion_gate_used=false' \
    'database_ingestion=false;accepted_database_contact=false;gemma_contact=false;retrieval_tuning=false;black_corpus_access=false' \
    '' \
    'SCRIPT RESULT' \
    'script_188_v3_preingestion_retrieval=pass'
  exit 0
fi

work_root=''
report_path=''
nomic_key=''
active_pid=''
private_pg_started=false
failure_reason='unexpected_failure'

emit() {
  if [[ -n "$report_path" ]]; then
    printf '%s\n' "$1" | tee -a "$report_path"
  else
    printf '%s\n' "$1"
  fi
}

stop_private_postgresql() {
  if [[ "$private_pg_started" == true && -n "$work_root" \
        && "$work_root" == /tmp/ishikawa-script-188.* ]]; then
    "$PG_CTL" -D "$work_root/postgresql" -m fast -w stop >/dev/null 2>&1 || true
  fi
  private_pg_started=false
}

remove_work_root() {
  if [[ -n "$work_root" && "$work_root" == /tmp/ishikawa-script-188.* \
        && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  work_root=''
}

failure_cleanup() {
  local initial_status="$?"
  trap - EXIT HUP INT TERM
  set +e
  if [[ "$active_pid" =~ ^[0-9]+$ ]] && kill -0 "$active_pid" 2>/dev/null; then
    kill -TERM "$active_pid" 2>/dev/null || true
    wait "$active_pid" 2>/dev/null || true
  fi
  active_pid=''
  nomic_key=''
  unset nomic_key ISHIKAWA_NOMIC_API_KEY
  stop_private_postgresql
  remove_work_root
  if [[ -n "$report_path" && -f "$report_path" ]]; then
    emit "script_state=blocked;reason=$failure_reason;exit_code=$initial_status"
    chmod 0600 "$report_path" 2>/dev/null || true
    printf 'local_report=%s;local_report_sha256=%s\n' \
      "$report_path" "$(sha256sum "$report_path" | awk '{print $1}')"
  else
    printf 'script_state=blocked;reason=%s;exit_code=%s\n' \
      "$failure_reason" "$initial_status"
  fi
  printf '\nSCRIPT RESULT\nscript_188_v3_preingestion_retrieval=blocked\n'
  exit "$initial_status"
}
trap failure_cleanup EXIT
trap 'failure_reason=interrupted; exit 130' HUP INT TERM

block() {
  failure_reason="$1"
  exit 1
}

read_secret() {
  local prompt_label="$1" destination_name="$2" secret_value=''
  [[ -r /dev/tty && -w /dev/tty ]] || block interactive_terminal_unavailable
  IFS= read -r -s -p "$prompt_label: " secret_value </dev/tty || block secret_entry_failed
  printf '\n' >/dev/tty
  (( ${#secret_value} >= 32 && ${#secret_value} <= 1024 )) || block secret_value_invalid
  [[ "$secret_value" != *$'\n'* && "$secret_value" != *$'\r'* ]] || block secret_value_invalid
  printf -v "$destination_name" '%s' "$secret_value"
  secret_value=''
}

wait_with_heartbeat() {
  local milestone="$1" started_epoch="$2" next_heartbeat current_epoch process_status
  next_heartbeat=$(( started_epoch + 30 ))
  while kill -0 "$active_pid" 2>/dev/null; do
    sleep 5
    current_epoch="$(date +%s)"
    if (( current_epoch >= next_heartbeat )) && kill -0 "$active_pid" 2>/dev/null; then
      emit "milestone=$milestone;state=running;elapsed_seconds=$(( current_epoch - started_epoch ))"
      next_heartbeat=$(( current_epoch + 30 ))
    fi
  done
  if wait "$active_pid"; then process_status=0; else process_status="$?"; fi
  active_pid=''
  return "$process_status"
}

umask 077
mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" \
    && -d "$ARTIFACT_ROOT" && ! -L "$ARTIFACT_ROOT" ]] \
  || block output_directory_unsafe
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/v3_preingestion_retrieval_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-script-188.XXXXXX)"

actual_hostname="$(hostname -s)"
actual_os_id="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"' | awk 'NR == 1')"
actual_os_version="$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"' | awk 'NR == 1')"
actual_architecture="$(uname -m)"
local_user="$(id -un)"

emit 'purpose=build_v3_retrieval_truth_and_measure_preingestion_retrieval'
emit "started_utc=$timestamp;hostname=$actual_hostname;os_version=$actual_os_version;architecture=$actual_architecture"
emit "script_sha256=$script_sha256;script_187_report_sha256=$SCRIPT_187_REPORT_SHA256"
emit "candidate_manifest_sha256=$CHECKSUM_MANIFEST_SHA256;corpus_truth_sha256=$CORPUS_TRUTH_SHA256;chunks_sha256=$CHUNKS_SHA256"
emit 'authorized_actions=build_local_synthetic_evaluation_truth_call_existing_loopback_nomic_start_private_temporary_postgresql_measure_frozen_retrieval_write_private_local_artifacts_and_content_free_report'
emit 'non_actions=no_corpus_ingestion_no_corpus_publication_no_accepted_database_contact_no_gemma_contact_no_black_corpus_access_no_retrieval_tuning_no_service_change_no_package_change_no_release_change_no_secret_retention'

[[ "$actual_hostname" == "$EXPECTED_HOST" \
    && "$actual_os_id" == "$EXPECTED_OS_ID" \
    && "$actual_os_version" == "$EXPECTED_OS_VERSION" \
    && "$actual_architecture" == "$EXPECTED_ARCHITECTURE" ]] \
  || block local_host_identity_mismatch

truth_candidate="$work_root/retrieval-truth.json"
truth_stdout="$work_root/truth.stdout"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$TRUTH_BUILDER" \
  --corpus-truth "$CORPUS_TRUTH" \
  --expected-corpus-truth-sha256 "$CORPUS_TRUTH_SHA256" \
  --output "$truth_candidate" >"$truth_stdout" 2>"$work_root/truth.stderr" \
  || block retrieval_truth_build_failed
grep -Fxq \
  'synthetic_corpus_v3_retrieval_truth=pass;cases=180;body=120;relationships=30;headers=30;documents=30;document_pages=150' \
  "$truth_stdout" || block retrieval_truth_pass_marker_absent
truth_sha256="$(sha256sum "$truth_candidate" | awk '{print $1}')"
emit "milestone=retrieval_truth;state=pass;cases=180;body=120;relationships=30;headers=30;document_page_coverage=150/150;artifact_sha256=$truth_sha256"

nomic_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
  --connect-timeout 5 --max-time 10 "$NOMIC_HEALTH_URL" 2>/dev/null || true)"
[[ "$nomic_status" == 200 ]] || block nomic_forward_unavailable
emit 'milestone=readiness;state=pass;nomic=pass;gemma_required=false;accepted_postgresql_required=false'

postgresql_data="$work_root/postgresql"
postgresql_socket="$work_root/socket"
mkdir -p -- "$postgresql_data" "$postgresql_socket"
"$INITDB" -D "$postgresql_data" --username="$local_user" --encoding=UTF8 \
  --no-locale --auth=trust >"$work_root/initdb.stdout" 2>"$work_root/initdb.stderr" \
  || block temporary_postgresql_initialization_failed
"$PG_CTL" -D "$postgresql_data" -l "$work_root/postgresql.log" \
  -o "-k $postgresql_socket -c listen_addresses='' -p $TEMPORARY_POSTGRESQL_PORT -c fsync=off -c synchronous_commit=off -c full_page_writes=off" \
  -w start >"$work_root/pg-start.stdout" 2>"$work_root/pg-start.stderr" \
  || block temporary_postgresql_start_failed
private_pg_started=true
emit 'milestone=temporary_postgresql;state=pass;tcp_listener=false;corpus_tables=false;accepted_database_contact=false'

read_secret 'Nomic API key' nomic_key
emit 'milestone=credential;state=accepted;value_logged=false;value_retained=false'

embedding_candidate="$work_root/v3-document-embeddings.json"
embedding_stdout="$work_root/embedding.stdout"
emit 'milestone=document_embeddings;state=start;candidates=943'
embedding_started="$(date +%s)"
(
  printf '%s' "$nomic_key" | PYTHONDONTWRITEBYTECODE=1 python3 -B "$EMBEDDER" \
    --input "$CHUNKS" \
    --expected-input-sha256 "$CHUNKS_SHA256" \
    --output "$embedding_candidate" \
    --embedding-url "$NOMIC_EMBEDDING_URL" \
    --tokenizer-url "$NOMIC_TOKENIZER_URL" \
    --batch-size 16 \
    --credential-stdin
) >"$embedding_stdout" 2>"$work_root/embedding.stderr" &
active_pid="$!"
wait_with_heartbeat document_embeddings "$embedding_started" \
  || block document_embedding_stage_failed
grep -Fxq 'document_embedding_stage=pass' "$embedding_stdout" \
  || block document_embedding_pass_marker_absent
grep -Fq 'documents=30;candidates=943;embedding_dimension=768' "$embedding_stdout" \
  || block document_embedding_inventory_invalid
grep -Fq 'repeat_within_tolerance=true' "$embedding_stdout" \
  || block document_embedding_repeatability_invalid
embedding_sha256="$(sha256sum "$embedding_candidate" | awk '{print $1}')"
emit "milestone=document_embeddings;state=pass;elapsed_seconds=$(( $(date +%s) - embedding_started ));artifact_sha256=$embedding_sha256"

observation_candidate="$work_root/v3-retrieval-observation.json"
measurement_stdout="$work_root/measurement.stdout"
emit 'milestone=retrieval_measurement;state=start;cases=180;promotion_gate_used=false'
measurement_started="$(date +%s)"
export ISHIKAWA_NOMIC_API_KEY="$nomic_key"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" \
  --python-root "$PYTHON_ROOT" \
  --chunks "$CHUNKS" \
  --expected-chunks-sha256 "$CHUNKS_SHA256" \
  --document-embeddings "$embedding_candidate" \
  --expected-document-embeddings-sha256 "$embedding_sha256" \
  --truth "$truth_candidate" \
  --expected-truth-sha256 "$truth_sha256" \
  --embedding-url "$NOMIC_EMBEDDING_URL" \
  --tokenizer-url "$NOMIC_TOKENIZER_URL" \
  --postgresql-socket "$postgresql_socket" \
  --postgresql-port "$TEMPORARY_POSTGRESQL_PORT" \
  --postgresql-user "$local_user" \
  --output "$observation_candidate" \
  >"$measurement_stdout" 2>"$work_root/measurement.stderr" &
active_pid="$!"
unset ISHIKAWA_NOMIC_API_KEY
nomic_key=''
wait_with_heartbeat retrieval_measurement "$measurement_started" \
  || block retrieval_measurement_failed
grep -Fxq 'synthetic_corpus_v3_preingestion_measurement=pass' "$measurement_stdout" \
  || block retrieval_measurement_pass_marker_absent
observation_sha256="$(sha256sum "$observation_candidate" | awk '{print $1}')"

validation_summary="$work_root/validation-summary.txt"
PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$observation_candidate" "$CHUNKS_SHA256" "$embedding_sha256" "$truth_sha256" \
  >"$validation_summary" <<'PY'
import json
import pathlib
import sys

value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert value["artifact_kind"] == "ishikawa_synthetic_corpus_v3_preingestion_retrieval_observation"
assert value["schema_version"] == 1
assert value["corpus_identity"] == "synthetic-corpus-v3"
assert value["measurement_class"] == "observational_baseline_no_promotion_gate"
assert value["source_sha256"] == {
    "chunks": sys.argv[2],
    "document_embeddings": sys.argv[3],
    "retrieval_truth": sys.argv[4],
}
assert value["candidate_inventory"] == {
    "documents": 30, "atomic": 786, "representatives": 157, "total": 943
}
assert value["case_inventory"] == {
    "body": 120, "relationship": 30, "header": 30, "total": 180
}
assert value["promotion_gate_used"] is False
assert value["boundaries"] == {
    "accepted_database_contact": False,
    "accepted_database_write": False,
    "black_corpus_access": False,
    "corpus_ingestion": False,
    "corpus_v1_changed": False,
    "corpus_v2_changed": False,
    "corpus_v3_changed": False,
    "gemma_contact": False,
    "nomic_contact": True,
    "private_temporary_postgresql": True,
    "profile_changed": False,
    "question_text_retained_in_observation": False,
    "query_vectors_retained": False,
    "source_text_retained_in_observation": False,
}
for family, expected in (("body", 120), ("relationship", 30), ("header", 30), ("overall", 180)):
    metric = value["metrics"][family]
    assert metric["case_count"] == expected
    print(
        f"{family}_mrr_at_20={metric['mrr_at_20']};"
        f"relevant_at_5={metric['relevant_at_5']}/{expected};"
        f"relevant_at_20={metric['relevant_at_20']}/{expected};"
        f"required_evidence_at_20={metric['required_evidence_matched_at_20']}/"
        f"{metric['required_evidence_total']}"
    )
expansion = value["authoritative_expansion"]
print(
    f"authoritative_expansion={expansion['matched_evidence']}/"
    f"{expansion['required_evidence']};complete={str(expansion['complete']).lower()}"
)
print("promotion_gate_used=false;measurement_status=observed")
PY
while IFS= read -r summary_line; do emit "$summary_line"; done <"$validation_summary"
emit "milestone=retrieval_measurement;state=pass;elapsed_seconds=$(( $(date +%s) - measurement_started ));artifact_sha256=$observation_sha256"

truth_artifact="$ARTIFACT_ROOT/v3_retrieval_truth_${timestamp}.json"
embedding_artifact="$ARTIFACT_ROOT/v3_document_embeddings_${timestamp}.json"
observation_artifact="$ARTIFACT_ROOT/v3_preingestion_retrieval_observation_${timestamp}.json"
checksum_artifact="$ARTIFACT_ROOT/SHA256SUMS_${timestamp}"
for destination in "$truth_artifact" "$embedding_artifact" "$observation_artifact" "$checksum_artifact"; do
  [[ ! -e "$destination" && ! -L "$destination" ]] || block retained_artifact_path_exists
done
mv -- "$truth_candidate" "$truth_artifact"
mv -- "$embedding_candidate" "$embedding_artifact"
mv -- "$observation_candidate" "$observation_artifact"
chmod 0600 "$truth_artifact" "$embedding_artifact" "$observation_artifact" \
  2>/dev/null || true
(
  cd -- "$ARTIFACT_ROOT"
  sha256sum "$(basename -- "$truth_artifact")" \
    "$(basename -- "$embedding_artifact")" \
    "$(basename -- "$observation_artifact")" >"$(basename -- "$checksum_artifact")"
)
chmod 0600 "$checksum_artifact" 2>/dev/null || true

stop_private_postgresql
emit 'milestone=temporary_postgresql_cleanup;state=pass;cluster_retained=false;listener_retained=false'
emit "truth_artifact=$truth_artifact;truth_artifact_sha256=$truth_sha256"
emit "embedding_artifact=$embedding_artifact;embedding_artifact_sha256=$embedding_sha256"
emit "observation_artifact=$observation_artifact;observation_artifact_sha256=$observation_sha256"
emit "checksum_artifact=$checksum_artifact;checksum_artifact_sha256=$(sha256sum "$checksum_artifact" | awk '{print $1}')"
emit 'database_ingestion=false;accepted_database_contact=false;gemma_contact=false;retrieval_tuning=false;promotion_gate_used=false;corpus_v1_changed=false;corpus_v2_changed=false;corpus_v3_changed=false'
emit 'next_gate=review_v3_observational_metrics_before_isolated_ingestion'

remove_work_root
unset ISHIKAWA_NOMIC_API_KEY
trap - EXIT HUP INT TERM
chmod 0600 "$report_path" 2>/dev/null || true
report_sha256="$(sha256sum "$report_path" | awk '{print $1}')"
printf 'local_report=%s;local_report_sha256=%s\n' "$report_path" "$report_sha256"
printf '\nSCRIPT RESULT\nscript_188_v3_preingestion_retrieval=pass\n'
