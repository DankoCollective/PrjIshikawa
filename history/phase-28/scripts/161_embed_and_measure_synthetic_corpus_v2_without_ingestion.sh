#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Embed and measure the checksum-bound synthetic corpus v2 candidate without
#   ingesting or publishing it to the accepted Ishikawa PostgreSQL database.
#
# Mental model:
#   Bind Script 160's clean candidate; obtain measured document and query
#   embeddings from the existing loopback Nomic forward; execute PostgreSQL
#   English lexical search in a private temporary cluster over transient JSON;
#   fuse the exact, lexical, and vector lanes with the frozen T09 profile; and
#   retain content-free 60-case and header/department ranking evidence.
#
# Inputs or prerequisites:
#   The exact Script 160 report and retained corpus-v2 candidate, PostgreSQL 16
#   client/server binaries already installed on DankoSurface, psycopg, the
#   operator-managed Nomic forward on 127.0.0.1:8001, and its API key.
#
# Outputs or artifact lane:
#   Private document-embedding and ranking-observation JSON artifacts plus one
#   content-free report. The temporary PostgreSQL cluster is under /tmp, has no
#   TCP listener, receives no corpus tables, and is removed on exit. The
#   accepted v1 database is never contacted or changed. Gemma is never called.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/161_embed_and_measure_synthetic_corpus_v2_without_ingestion.sh --run

usage() {
  sed -n '3,34p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Embed and measure corpus v2 without ingestion.' \
    '  --validate-only Validate bound inputs and local contracts only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly EMBEDDER="$SCRIPT_DIR/embed_document_candidates_via_endpoint.py"
readonly EVALUATOR="$SCRIPT_DIR/measure_synthetic_corpus_v2_without_ingestion.py"
readonly BODY_CASES="$PHASE_ROOT/reference/ishikawa-extended-retrieval-mrr-cases-v1.1.json"
readonly HEADER_CASES="$PHASE_ROOT/reference/ishikawa-synthetic-corpus-v2-header-cases.json"
readonly SCRIPT_160_REPORT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2/header_aware_synthetic_corpus_v2_20261022T173923Z_UlZyg2.txt"
readonly CANDIDATE_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2/synthetic_corpus_v2_candidate_20261022T173923Z"
readonly CHECKSUM_MANIFEST="$CANDIDATE_ROOT/SHA256SUMS"
readonly CHUNKS="$CANDIDATE_ROOT/qualification/chunks.json"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-preingestion"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-preingestion"
readonly INITDB='/usr/lib/postgresql/16/bin/initdb'
readonly PG_CTL='/usr/lib/postgresql/16/bin/pg_ctl'
readonly NOMIC_HEALTH_URL='http://127.0.0.1:8001/health'
readonly NOMIC_EMBEDDING_URL='http://127.0.0.1:8001/v1/embeddings'
readonly NOMIC_TOKENIZER_URL='http://127.0.0.1:8001/tokenize'
readonly TEMPORARY_POSTGRESQL_PORT=65432
readonly EXPECTED_HOST='DankoSurface'
readonly EXPECTED_OS_ID='ubuntu'
readonly EXPECTED_OS_VERSION='24.04'
readonly EXPECTED_ARCHITECTURE='aarch64'
readonly EXPECTED_CANDIDATES=134
readonly SCRIPT_160_REPORT_SHA256='36e595db94197db5cad335e840abadeb7b341c90188b22ccb891080088d4ce06'
readonly CHECKSUM_MANIFEST_SHA256='368a0662da417cd564a6eb1de673e36472f8be2781c64badf74e7ca37dc51003'
readonly CHUNKS_SHA256='eb473260b4ea21d6d33a873a513df604741cffb162589673bf2926cc263be16a'
readonly BODY_CASES_SHA256='14814166168c4dfd97e85668a29fd11538e2cf585a0176fdcd50f072ef5958ce'
readonly HEADER_CASES_SHA256='a873a61b59de0a8ea082c3fc0c987ab9cf7b97d79ed843832be354af8eae6e2c'
readonly EMBEDDER_SHA256='8f3c23ca30904dfb48a37f3366fd4b7873769bb92a527479fec5696f7fc456dc'
readonly EVALUATOR_SHA256='51b41ba2e3638669b2b195dccd38928a9b9a6148469e406f37c90489959d32e3'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      printf 'script_161_embed_measure_corpus_v2=blocked;reason=argument_invalid\n' >&2
      usage >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_161_embed_measure_corpus_v2=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for command_name in \
  awk bash chmod curl date dirname grep hostname id kill mkdir mktemp mv \
  python3 rm sed sha256sum sleep stat tee tr uname; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'script_161_embed_measure_corpus_v2=blocked;reason=local_command_missing;command=%s\n' \
      "$command_name" >&2
    exit 2
  }
done

check_file() {
  local path="$1" expected_sha256="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] || {
    printf 'script_161_embed_measure_corpus_v2=blocked;reason=%s_unsafe\n' "$label" >&2
    exit 2
  }
  [[ "$(sha256sum "$path" | awk '{print $1}')" == "$expected_sha256" ]] || {
    printf 'script_161_embed_measure_corpus_v2=blocked;reason=%s_identity_changed\n' "$label" >&2
    exit 2
  }
}

check_file "$SCRIPT_160_REPORT" "$SCRIPT_160_REPORT_SHA256" script_160_report
check_file "$CHECKSUM_MANIFEST" "$CHECKSUM_MANIFEST_SHA256" candidate_checksum_manifest
check_file "$CHUNKS" "$CHUNKS_SHA256" candidate_chunks
check_file "$BODY_CASES" "$BODY_CASES_SHA256" body_case_set
check_file "$HEADER_CASES" "$HEADER_CASES_SHA256" header_case_set
check_file "$EMBEDDER" "$EMBEDDER_SHA256" embedding_producer
check_file "$EVALUATOR" "$EVALUATOR_SHA256" measurement_evaluator
for executable in "$INITDB" "$PG_CTL"; do
  [[ -f "$executable" && ! -L "$executable" && -x "$executable" ]] || {
    printf 'script_161_embed_measure_corpus_v2=blocked;reason=postgresql_16_binary_unsafe\n' >&2
    exit 2
  }
done

grep -Fxq \
  'script_160_header_aware_synthetic_corpus_v2=pass;next_gate=embed_and_measure_corpus_v2_retrieval_without_ingestion' \
  "$SCRIPT_160_REPORT" || {
  printf 'script_161_embed_measure_corpus_v2=blocked;reason=script_160_not_clean_pass\n' >&2
  exit 1
}
grep -Fxq \
  'corpus_v1_changed=false;database_contact=false;model_contact=false;service_changed=false;package_changed=false' \
  "$SCRIPT_160_REPORT" || {
  printf 'script_161_embed_measure_corpus_v2=blocked;reason=script_160_boundary_invalid\n' >&2
  exit 1
}

checksum_output="$(cd -- "$CANDIDATE_ROOT" && sha256sum --check --strict SHA256SUMS 2>&1)" || {
  printf 'script_161_embed_measure_corpus_v2=blocked;reason=candidate_inventory_invalid\n' >&2
  exit 1
}
[[ "$(grep -c ': OK$' <<<"$checksum_output")" == 13 ]] || {
  printf 'script_161_embed_measure_corpus_v2=blocked;reason=candidate_inventory_count_invalid\n' >&2
  exit 1
}

bash -n "${BASH_SOURCE[0]}"
for python_source in "$EMBEDDER" "$EVALUATOR" "$PYTHON_ROOT/ishikawa/retrieval.py"; do
  PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
    'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
    "$python_source"
done
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EMBEDDER" --self-test \
  | grep -Fxq 'document_embedding_endpoint_producer_self_test=pass' || {
  printf 'script_161_embed_measure_corpus_v2=blocked;reason=embedding_producer_self_test_failed\n' >&2
  exit 2
}
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" --self-test \
  | grep -Fxq 'synthetic_corpus_v2_preingestion_measurement_self_test=pass' || {
  printf 'script_161_embed_measure_corpus_v2=blocked;reason=measurement_evaluator_self_test_failed\n' >&2
  exit 2
}
PYTHONDONTWRITEBYTECODE=1 python3 -B -c 'import psycopg; assert psycopg.__version__' || {
  printf 'script_161_embed_measure_corpus_v2=blocked;reason=psycopg_unavailable\n' >&2
  exit 2
}

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_synthetic_corpus_v2_preingestion_embedding_and_measurement' \
    "script_sha256=$script_sha256;script_160_report_sha256=$SCRIPT_160_REPORT_SHA256" \
    "candidate_checksum_manifest_sha256=$CHECKSUM_MANIFEST_SHA256;candidate_files=13;candidate_chunks=$EXPECTED_CANDIDATES" \
    "chunks_sha256=$CHUNKS_SHA256;body_cases_sha256=$BODY_CASES_SHA256;header_cases_sha256=$HEADER_CASES_SHA256" \
    "embedder_sha256=$EMBEDDER_SHA256;evaluator_sha256=$EVALUATOR_SHA256" \
    'retrieval_profile=exact_1_lexical_20_vector_20_fused_20_rrf_60_weights_1_1_4_no_reranker' \
    'accepted_v1_database_contact=false;database_write=false;model_contact=false;credential_read=false;service_changed=false;corpus_changed=false;package_changed=false' \
    'script_161_embed_measure_corpus_v2=pass'
  exit 0
fi

work_root=''
report_path=''
nomic_key=''
active_pid=''
private_pg_started=false
failure_recorded=false

emit() {
  if [[ -n "$report_path" ]]; then
    printf '%s\n' "$1" | tee -a "$report_path"
  else
    printf '%s\n' "$1"
  fi
}

block() {
  failure_recorded=true
  emit "script_161_embed_measure_corpus_v2=blocked;reason=$1"
  exit 1
}

cleanup() {
  local initial_status="$?"
  trap - EXIT HUP INT TERM
  set +e
  if (( initial_status != 0 )) && [[ "$failure_recorded" != true ]]; then
    emit "script_161_embed_measure_corpus_v2=blocked;reason=unexpected_failure;exit_code=$initial_status"
  fi
  if [[ "$active_pid" =~ ^[0-9]+$ ]] && kill -0 "$active_pid" 2>/dev/null; then
    kill -TERM "$active_pid" 2>/dev/null || true
    wait "$active_pid" 2>/dev/null || true
  fi
  active_pid=''
  nomic_key=''
  unset nomic_key ISHIKAWA_NOMIC_API_KEY
  if [[ "$private_pg_started" == true && -n "$work_root" \
        && "$work_root" == /tmp/ishikawa-script-161.* ]]; then
    "$PG_CTL" -D "$work_root/postgresql" -m fast -w stop >/dev/null 2>&1 || true
  fi
  private_pg_started=false
  if [[ -n "$work_root" && "$work_root" == /tmp/ishikawa-script-161.* \
        && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  if [[ -n "$report_path" && -f "$report_path" ]]; then
    chmod 0600 "$report_path" 2>/dev/null || true
    printf 'local_report=%s;local_report_sha256=%s\n' \
      "$report_path" "$(sha256sum "$report_path" | awk '{print $1}')"
  fi
  exit "$initial_status"
}
trap cleanup EXIT HUP INT TERM

read_secret() {
  local prompt_label="$1" destination_name="$2" secret_value=''
  [[ -r /dev/tty && -w /dev/tty ]] || block interactive_terminal_unavailable
  IFS= read -r -s -p "$prompt_label: " secret_value </dev/tty || block secret_entry_failed
  printf '\n' >/dev/tty
  (( ${#secret_value} >= 32 && ${#secret_value} <= 1024 )) || block secret_value_invalid
  [[ "$secret_value" != *$'\n'* && "$secret_value" != *$'\r'* ]] \
    || block secret_value_invalid
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
  if wait "$active_pid"; then
    process_status=0
  else
    process_status="$?"
  fi
  active_pid=''
  return "$process_status"
}

umask 077
mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" \
    && -d "$ARTIFACT_ROOT" && ! -L "$ARTIFACT_ROOT" ]] \
  || block output_directory_unsafe
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/corpus_v2_preingestion_measurement_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-script-161.XXXXXX)"

actual_hostname="$(hostname -s)"
actual_os_id="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"' | awk 'NR == 1')"
actual_os_version="$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"' | awk 'NR == 1')"
actual_architecture="$(uname -m)"
local_user="$(id -un)"

emit 'purpose=embed_and_measure_synthetic_corpus_v2_without_ingestion'
emit "started_utc=$timestamp;hostname=$actual_hostname;os_version=$actual_os_version;architecture=$actual_architecture"
emit "script_sha256=$script_sha256;script_160_report_sha256=$SCRIPT_160_REPORT_SHA256"
emit "candidate_checksum_manifest_sha256=$CHECKSUM_MANIFEST_SHA256;chunks_sha256=$CHUNKS_SHA256"
emit "body_cases_sha256=$BODY_CASES_SHA256;header_cases_sha256=$HEADER_CASES_SHA256"
emit "embedder_sha256=$EMBEDDER_SHA256;evaluator_sha256=$EVALUATOR_SHA256"
emit 'authorized_actions=call_existing_loopback_nomic_embed_candidate_and_queries_start_private_temporary_postgresql_run_transient_english_lexical_search_write_private_embeddings_ranking_observation_and_content_free_report'
emit 'non_actions=no_accepted_v1_database_contact_no_database_ingestion_no_database_write_no_gemma_contact_no_service_configuration_change_no_remote_host_contact_no_corpus_mutation_no_package_change_no_accepted_release_change_no_secret_retention_no_question_text_retention_no_query_vector_retention_no_source_text_retention'

[[ "$actual_hostname" == "$EXPECTED_HOST" \
    && "$actual_os_id" == "$EXPECTED_OS_ID" \
    && "$actual_os_version" == "$EXPECTED_OS_VERSION" \
    && "$actual_architecture" == "$EXPECTED_ARCHITECTURE" ]] \
  || block local_host_identity_mismatch

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
emit 'milestone=temporary_postgresql;state=pass;tcp_listener=false;corpus_tables=false;accepted_v1_contact=false'

read_secret 'Nomic API key' nomic_key
emit 'milestone=credential;state=accepted;value_logged=false;value_retained=false'

embedding_candidate="$work_root/corpus-v2-document-embeddings.json"
embedding_stdout="$work_root/embedding.stdout"
embedding_stderr="$work_root/embedding.stderr"
emit "milestone=document_embeddings;state=start;candidates=$EXPECTED_CANDIDATES"
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
) >"$embedding_stdout" 2>"$embedding_stderr" &
active_pid="$!"
if ! wait_with_heartbeat document_embeddings "$embedding_started"; then
  block document_embedding_stage_failed
fi
grep -Fxq 'document_embedding_stage=pass' "$embedding_stdout" \
  || block document_embedding_pass_marker_absent
grep -Fq "documents=6;candidates=$EXPECTED_CANDIDATES;embedding_dimension=768" "$embedding_stdout" \
  || block document_embedding_inventory_invalid
grep -Fq 'repeat_within_tolerance=true' "$embedding_stdout" \
  || block document_embedding_repeatability_invalid
[[ -f "$embedding_candidate" && ! -L "$embedding_candidate" && -s "$embedding_candidate" ]] \
  || block document_embedding_artifact_absent
embedding_sha256="$(sha256sum "$embedding_candidate" | awk '{print $1}')"
emit "milestone=document_embeddings;state=pass;elapsed_seconds=$(( $(date +%s) - embedding_started ));artifact_sha256=$embedding_sha256"

observation_candidate="$work_root/corpus-v2-retrieval-observation.json"
measurement_stdout="$work_root/measurement.stdout"
measurement_stderr="$work_root/measurement.stderr"
emit 'milestone=retrieval_measurement;state=start;body_cases=60;header_cases=8;query_embeddings=68'
measurement_started="$(date +%s)"
export ISHIKAWA_NOMIC_API_KEY="$nomic_key"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" \
  --python-root "$PYTHON_ROOT" \
  --chunks "$CHUNKS" \
  --expected-chunks-sha256 "$CHUNKS_SHA256" \
  --document-embeddings "$embedding_candidate" \
  --expected-document-embeddings-sha256 "$embedding_sha256" \
  --body-cases "$BODY_CASES" \
  --expected-body-cases-sha256 "$BODY_CASES_SHA256" \
  --header-cases "$HEADER_CASES" \
  --expected-header-cases-sha256 "$HEADER_CASES_SHA256" \
  --embedding-url "$NOMIC_EMBEDDING_URL" \
  --tokenizer-url "$NOMIC_TOKENIZER_URL" \
  --postgresql-socket "$postgresql_socket" \
  --postgresql-port "$TEMPORARY_POSTGRESQL_PORT" \
  --postgresql-user "$local_user" \
  --output "$observation_candidate" \
  >"$measurement_stdout" 2>"$measurement_stderr" &
active_pid="$!"
unset ISHIKAWA_NOMIC_API_KEY
nomic_key=''
if ! wait_with_heartbeat retrieval_measurement "$measurement_started"; then
  block retrieval_measurement_failed
fi
grep -Fxq 'synthetic_corpus_v2_preingestion_measurement=pass' "$measurement_stdout" \
  || block retrieval_measurement_pass_marker_absent
[[ -f "$observation_candidate" && ! -L "$observation_candidate" \
    && -s "$observation_candidate" ]] || block retrieval_observation_absent
observation_sha256="$(sha256sum "$observation_candidate" | awk '{print $1}')"

validation_summary="$work_root/validation-summary.txt"
PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$observation_candidate" "$CHUNKS_SHA256" "$embedding_sha256" \
  "$BODY_CASES_SHA256" "$HEADER_CASES_SHA256" >"$validation_summary" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
value = json.loads(path.read_text(encoding="utf-8"))
assert value["artifact_kind"] == "ishikawa_synthetic_corpus_v2_preingestion_retrieval_observation"
assert value["schema_version"] == 1
assert value["source_chunks_sha256"] == sys.argv[2]
assert value["source_document_embeddings_sha256"] == sys.argv[3]
assert value["body_case_set_sha256"] == sys.argv[4]
assert value["header_case_set_sha256"] == sys.argv[5]
assert value["document_count"] == 6
assert value["candidate_count"] == 134
assert value["query_embedding_count"] == 68
assert len(value["cases"]) == 68
assert value["database_boundary"] == "private_temporary_postgresql_repeatable_read_read_only"
assert value["database_tables_read"] is False
assert value["database_write"] is False
assert value["accepted_v1_database_contact"] is False
assert value["gemma_contact"] is False
assert value["question_text_retained"] is False
assert value["query_vectors_retained"] is False
assert value["source_text_retained"] is False
assert value["credentials_retained"] is False
body = value["body_metrics"]
header = value["header_metrics"]
gate = value["preingestion_measurement_gate"]
assert gate in {"pass", "not_met"}
print(
    f"body_mrr_at_20={body['mrr_at_20']};"
    f"body_relevant_at_5={body['relevant_at_5']}/60;"
    f"body_relevant_at_20={body['relevant_at_20']}/60"
)
print(
    f"header_mrr_at_20={header['mrr_at_20']};"
    f"header_relevant_at_5={header['relevant_at_5']}/8;"
    f"header_required_evidence_at_20={header['required_evidence_matched_at_20']}/"
    f"{header['required_evidence_total']}"
)
print(f"preingestion_measurement_gate={gate};strict_body_target=greater_than_0.91")
PY
while IFS= read -r summary_line; do
  emit "$summary_line"
done <"$validation_summary"
measurement_gate="$(sed -nE 's/^preingestion_measurement_gate=(pass|not_met);.*$/\1/p' "$validation_summary")"
[[ "$measurement_gate" == pass || "$measurement_gate" == not_met ]] \
  || block retrieval_measurement_gate_invalid
emit "milestone=retrieval_measurement;state=pass;elapsed_seconds=$(( $(date +%s) - measurement_started ));artifact_sha256=$observation_sha256"

embedding_artifact="$ARTIFACT_ROOT/corpus_v2_document_embeddings_${timestamp}.json"
observation_artifact="$ARTIFACT_ROOT/corpus_v2_retrieval_observation_${timestamp}.json"
[[ ! -e "$embedding_artifact" && ! -L "$embedding_artifact" \
    && ! -e "$observation_artifact" && ! -L "$observation_artifact" ]] \
  || block retained_artifact_path_exists
mv -- "$embedding_candidate" "$embedding_artifact"
mv -- "$observation_candidate" "$observation_artifact"
chmod 0600 "$embedding_artifact" "$observation_artifact" 2>/dev/null || true
[[ "$(sha256sum "$embedding_artifact" | awk '{print $1}')" == "$embedding_sha256" \
    && "$(sha256sum "$observation_artifact" | awk '{print $1}')" == "$observation_sha256" ]] \
  || block retained_artifact_identity_mismatch

"$PG_CTL" -D "$postgresql_data" -m fast -w stop \
  >"$work_root/pg-stop.stdout" 2>"$work_root/pg-stop.stderr" \
  || block temporary_postgresql_stop_failed
private_pg_started=false
emit 'milestone=temporary_postgresql_cleanup;state=pass;cluster_retained=false;listener_retained=false'
emit "embedding_artifact=$embedding_artifact;embedding_artifact_sha256=$embedding_sha256;artifact_mode=$(stat -c '%a' "$embedding_artifact")"
emit "observation_artifact=$observation_artifact;observation_artifact_sha256=$observation_sha256;artifact_mode=$(stat -c '%a' "$observation_artifact")"
emit 'accepted_v1_database_contact=false;database_ingestion=false;database_write=false;gemma_contact=false;corpus_v1_changed=false;corpus_v2_published=false;service_changed=false;package_changed=false;credentials_retained=false'

if [[ "$measurement_gate" == pass ]]; then
  next_gate='review_v2_metrics_then_prepare_isolated_v2_ingestion'
else
  next_gate='review_v2_rank_failures_before_ingestion'
fi
emit "script_161_embed_measure_corpus_v2=pass;measurement_gate=$measurement_gate;next_gate=$next_gate"
