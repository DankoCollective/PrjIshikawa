#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Measure the frozen V13-44 bounded query-decomposition, within-document
#   passage-expansion, and deterministic final-reranking experiment.
#
# Boundaries:
#   Calls only loopback Nomic and a private Unix-socket PostgreSQL instance.
#   Does not ingest, contact Gemma or an accepted database, access the black
#   corpus, change a production profile, or assemble a package or release.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/196_measure_v13_44_decomposed_passage_reranking.sh --run

usage() {
  sed -n '3,15p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Execute the frozen 5-candidate, 180-case experiment.' \
    '  --validate-only Validate all local inputs and implementation contracts.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly CHUNKER="$PYTHON_ROOT/ishikawa/chunking.py"
readonly METHOD_PROFILE="$PYTHON_ROOT/ishikawa/method_profile.py"
readonly BASE_EVALUATOR="$SCRIPT_DIR/measure_synthetic_corpus_v2_without_ingestion.py"
readonly V3_EVALUATOR="$SCRIPT_DIR/measure_synthetic_corpus_v3_preingestion.py"
readonly V40_EVALUATOR="$SCRIPT_DIR/measure_v13_40_bounded_ranking_candidates.py"
readonly V41_EVALUATOR="$SCRIPT_DIR/measure_v13_41_supplemental_ranking.py"
readonly EVALUATOR="$SCRIPT_DIR/measure_v13_44_decomposed_passage_reranking.py"
readonly ENDPOINT_CLIENT="$SCRIPT_DIR/embed_document_candidates_via_endpoint.py"
readonly TEST_RUNNER="$PRODUCT_ROOT/scripts/run-local-validation-tests.sh"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly SCRIPT_195_REPORT="$REPO_ROOT/local/reports/ishikawa-v13-43-document-affinity/v13_43_document_affinity_20261023T072325Z_Kxyz0L.txt"
readonly SCRIPT_195_OBSERVATION="$REPO_ROOT/local/artifacts/ishikawa/v13-43-document-affinity/v13_43_document_affinity_20261023T072325Z.json"
readonly NORMALIZED="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v3/synthetic_corpus_v3_candidate_20261023T043639Z/qualification/normalized.json"
readonly TRUTH="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v3-preingestion/v3_retrieval_truth_20261023T045046Z.json"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v13-44-decomposed-passage-reranking"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v13-44-decomposed-passage-reranking"
readonly INITDB='/usr/lib/postgresql/16/bin/initdb'
readonly PG_CTL='/usr/lib/postgresql/16/bin/pg_ctl'
readonly NOMIC_HEALTH_URL='http://127.0.0.1:8001/health'
readonly NOMIC_EMBEDDING_URL='http://127.0.0.1:8001/v1/embeddings'
readonly NOMIC_TOKENIZER_URL='http://127.0.0.1:8001/tokenize'
readonly TEMPORARY_POSTGRESQL_PORT=65439
readonly EXPECTED_HOST='DankoSurface'
readonly EXPECTED_OS_ID='ubuntu'
readonly EXPECTED_OS_VERSION='24.04'
readonly EXPECTED_ARCHITECTURE='aarch64'
readonly CHUNK_PROFILE_ID='d72a07f81eabc1f521ab1fd54f84289979365c6c71f8e3220a53b1e8c9a1c037'
readonly RETRIEVAL_PROFILE_ID='cfa9bbc353dc82d3ba74396de40df6ba429b7df2750e7809b92eeefd4a433147'
readonly SCRIPT_195_REPORT_SHA256='67456d12d575d4aac51f4981aa49139fcb034ede03af10a943e2063e27ca86fb'
readonly SCRIPT_195_OBSERVATION_SHA256='119588b068efc4afe4a41397db63d36de606067ef5a8271ff5b21c66d2521c57'
readonly NORMALIZED_SHA256='1772584ecc02c86cc0bd96946318e608f576fd259676bc9851ab7c54bf766b02'
readonly TRUTH_SHA256='f74302d899d000b9493fecfeca4ffbe2995bb04aabef00bf327061c34c2a18a0'
readonly CHUNKS_SHA256='49a67ac067d06b6068878be6530ae4971bddb4a1f687545578bd1ef9254d19e4'
readonly CHUNKER_SHA256='18cde74095f66108918edad2183752cdcc2ce7eeab6c2cc13a3d16dab588e995'
readonly METHOD_PROFILE_SHA256='a915dd57b9c783a1f34e0744f20748809399057b956d1cc6ee3d68abedddfa77'
readonly EVALUATOR_SHA256='fdea573adf5a6dec893f0df20c8b5b4c6992175f711f35cf9f9804f3a5168586'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      usage >&2
      printf '\nSCRIPT RESULT\nscript_196_v13_44_decomposed_passage_reranking=blocked\n' >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'reason=exactly_one_mode_required\n\nSCRIPT RESULT\nscript_196_v13_44_decomposed_passage_reranking=blocked\n' >&2
  exit 2
}

for command_name in awk bash curl date grep hostname id kill mkdir mktemp mv \
  python3 rm sed sha256sum sleep tee tr uname; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'reason=missing_command_%s\n\nSCRIPT RESULT\nscript_196_v13_44_decomposed_passage_reranking=blocked\n' \
      "$command_name" >&2
    exit 2
  }
done

check_file() {
  local path="$1" expected_sha256="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] || {
    printf 'reason=%s_unsafe\n\nSCRIPT RESULT\nscript_196_v13_44_decomposed_passage_reranking=blocked\n' \
      "$label" >&2
    exit 2
  }
  [[ "$(sha256sum "$path" | awk '{print $1}')" == "$expected_sha256" ]] || {
    printf 'reason=%s_identity_changed\n\nSCRIPT RESULT\nscript_196_v13_44_decomposed_passage_reranking=blocked\n' \
      "$label" >&2
    exit 2
  }
}

check_file "$SCRIPT_195_REPORT" "$SCRIPT_195_REPORT_SHA256" script_195_report
check_file "$SCRIPT_195_OBSERVATION" "$SCRIPT_195_OBSERVATION_SHA256" script_195_observation
check_file "$NORMALIZED" "$NORMALIZED_SHA256" normalized_v3
check_file "$TRUTH" "$TRUTH_SHA256" retrieval_truth
check_file "$CHUNKER" "$CHUNKER_SHA256" chunker
check_file "$METHOD_PROFILE" "$METHOD_PROFILE_SHA256" method_profile
check_file "$EVALUATOR" "$EVALUATOR_SHA256" evaluator
for executable in "$INITDB" "$PG_CTL"; do
  [[ -f "$executable" && ! -L "$executable" && -x "$executable" ]] || {
    printf 'reason=postgresql_16_binary_unsafe\n\nSCRIPT RESULT\nscript_196_v13_44_decomposed_passage_reranking=blocked\n' >&2
    exit 2
  }
done
grep -Fq '| `V13-44` |' "$DECISIONS" || {
  printf 'reason=v13_44_not_frozen\n\nSCRIPT RESULT\nscript_196_v13_44_decomposed_passage_reranking=blocked\n' >&2
  exit 1
}
grep -Fxq 'observation_validation=pass' "$SCRIPT_195_REPORT" || {
  printf 'reason=v13_43_antecedent_missing\n\nSCRIPT RESULT\nscript_196_v13_44_decomposed_passage_reranking=blocked\n' >&2
  exit 1
}
PYTHONDONTWRITEBYTECODE=1 python3 -B - "$SCRIPT_195_OBSERVATION" <<'PY'
import json,pathlib,sys
x=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert x["artifact_kind"]=="ishikawa_v13_43_document_affinity_experiment"
assert x["selection_status"]=="not_met" and x["selected_candidate"] is None
assert x["promotion_authorized"] is False and x["qualified_candidates"]==[]
assert x["variants"]["accepted_v6"]["metrics"]["body"]["mrr_at_20"]=="0.807533"
assert all(
 x["variants"][name]["metrics"]["body"]["mrr_at_20"]<"0.807533"
 for name in ("doc_l1_v0","doc_l0_v1","doc_l1_v1","doc_l1_v2","doc_l2_v1")
)
PY

bash -n "${BASH_SOURCE[0]}"
for python_source in "$CHUNKER" "$BASE_EVALUATOR" "$V3_EVALUATOR" \
  "$V40_EVALUATOR" "$V41_EVALUATOR" "$EVALUATOR" "$ENDPOINT_CLIENT"; do
  PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
    'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
    "$python_source"
done
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B - \
  "$CHUNK_PROFILE_ID" "$RETRIEVAL_PROFILE_ID" <<'PY'
import sys
from ishikawa.chunking import METHOD_PROFILE, METHOD_PROFILE_ID
from ishikawa.method_profile import ACCEPTED_RETRIEVAL_PROFILE
assert METHOD_PROFILE["name"]=="ishikawa-structural-chunk-candidates-v6"
assert METHOD_PROFILE_ID==sys.argv[1]
assert ACCEPTED_RETRIEVAL_PROFILE.chunk_method_profile_id==sys.argv[1]
assert ACCEPTED_RETRIEVAL_PROFILE.digest==sys.argv[2]
assert ACCEPTED_RETRIEVAL_PROFILE.exact_weight==1
assert ACCEPTED_RETRIEVAL_PROFILE.lexical_weight==2
assert ACCEPTED_RETRIEVAL_PROFILE.vector_weight==4
assert ACCEPTED_RETRIEVAL_PROFILE.exact_candidate_depth==1
assert ACCEPTED_RETRIEVAL_PROFILE.lexical_candidate_depth==20
assert ACCEPTED_RETRIEVAL_PROFILE.vector_candidate_depth==20
assert ACCEPTED_RETRIEVAL_PROFILE.fused_candidate_depth==20
assert ACCEPTED_RETRIEVAL_PROFILE.rrf_constant==60
PY
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" --self-test \
  | grep -Fxq 'v13_44_decomposed_passage_reranking_measurement_self_test=pass'
PYTHONDONTWRITEBYTECODE=1 python3 -B -c 'import psycopg; assert psycopg.__version__'

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_frozen_v13_44_decomposed_passage_reranking_experiment' \
    "script_sha256=$script_sha256;evaluator_sha256=$EVALUATOR_SHA256" \
    "chunk_profile_id=$CHUNK_PROFILE_ID;retrieval_profile_id=$RETRIEVAL_PROFILE_ID" \
    'documents=30;passage_candidates=943;cases=180;candidates=5' \
    'maximum_query_facets=4;document_shortlists=3,5;learned_reranker=false' \
    'body_mrr_gate=0.89;body_coverage_gate=120/120;authoritative_expansion_gate=180/180' \
    'retained_question_text=false;retained_decomposed_query_text=false;retained_vectors=false' \
    'accepted_database_contact=false;model_contact=false;corpus_ingestion=false' \
    '' \
    'SCRIPT RESULT' \
    'script_196_v13_44_decomposed_passage_reranking=pass'
  exit 0
fi

work_root=''
report_path=''
nomic_key=''
active_pid=''
private_pg_started=false
failure_reason='unexpected_failure'
timestamp=''
observation_candidate=''

emit() {
  if [[ -n "$report_path" ]]; then
    printf '%s\n' "$1" | tee -a "$report_path"
  else
    printf '%s\n' "$1"
  fi
}

stop_private_postgresql() {
  if [[ "$private_pg_started" == true && -n "$work_root" \
        && "$work_root" == /tmp/ishikawa-script-196.* ]]; then
    "$PG_CTL" -D "$work_root/postgresql" -m fast -w stop >/dev/null 2>&1 || true
  fi
  private_pg_started=false
}

remove_work_root() {
  if [[ -n "$work_root" && "$work_root" == /tmp/ishikawa-script-196.* \
        && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  work_root=''
}

failure_cleanup() {
  local initial_status="$?" diagnostic
  trap - EXIT HUP INT TERM
  set +e
  if [[ "$active_pid" =~ ^[0-9]+$ ]] && kill -0 "$active_pid" 2>/dev/null; then
    kill -TERM "$active_pid" 2>/dev/null || true
    wait "$active_pid" 2>/dev/null || true
  fi
  active_pid=''
  nomic_key=''
  unset nomic_key ISHIKAWA_NOMIC_API_KEY
  for diagnostic in native-tests.stderr measurement.stdout measurement.stderr \
    validation-summary.txt validation.stderr postgresql.log; do
    if [[ -n "$work_root" && -s "$work_root/$diagnostic" ]]; then
      emit "diagnostic_${diagnostic//[^a-zA-Z0-9]/_}_begin"
      while IFS= read -r line; do emit "$line"; done <"$work_root/$diagnostic"
      emit "diagnostic_${diagnostic//[^a-zA-Z0-9]/_}_end"
    fi
  done
  stop_private_postgresql
  remove_work_root
  if [[ -n "$report_path" && -f "$report_path" ]]; then
    emit "script_state=blocked;reason=$failure_reason;exit_code=$initial_status"
    printf 'local_report=%s;local_report_sha256=%s\n' \
      "$report_path" "$(sha256sum "$report_path" | awk '{print $1}')"
  else
    printf 'script_state=blocked;reason=%s;exit_code=%s\n' \
      "$failure_reason" "$initial_status"
  fi
  printf '\nSCRIPT RESULT\nscript_196_v13_44_decomposed_passage_reranking=blocked\n'
  exit "$initial_status"
}
trap failure_cleanup EXIT
trap 'failure_reason=interrupted; exit 130' HUP INT TERM
trap 'failure_reason="unexpected_failure_line_${LINENO}"' ERR
block() { failure_reason="$1"; exit 1; }

read_secret() {
  local prompt_label="$1" destination_name="$2" secret_value='' attempt=1
  [[ -r /dev/tty && -w /dev/tty ]] || block interactive_terminal_unavailable
  while (( attempt <= 3 )); do
    IFS= read -r -s -p "$prompt_label (32-1024 characters): " secret_value </dev/tty \
      || block secret_entry_failed
    printf '\n' >/dev/tty
    if (( ${#secret_value} >= 32 && ${#secret_value} <= 1024 )) \
        && [[ "$secret_value" != *$'\n'* && "$secret_value" != *$'\r'* ]]; then
      printf -v "$destination_name" '%s' "$secret_value"
      secret_value=''
      return 0
    fi
    secret_value=''
    if (( attempt < 3 )); then
      printf 'Credential rejected: enter the complete 32-1024 character key. Attempt %d of 3.\n' \
        "$attempt" >/dev/tty
    fi
    (( attempt += 1 ))
  done
  block secret_value_invalid_after_3_attempts
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
report_path="$(mktemp "$REPORT_ROOT/v13_44_decomposed_passage_reranking_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-script-196.XXXXXX)"
actual_hostname="$(hostname -s)"
actual_os_id="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"' | awk 'NR == 1')"
actual_os_version="$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"' | awk 'NR == 1')"
actual_architecture="$(uname -m)"
local_user="$(id -un)"

emit 'purpose=measure_frozen_v13_44_decomposed_passage_reranking'
emit "started_utc=$timestamp;hostname=$actual_hostname;os_version=$actual_os_version;architecture=$actual_architecture"
emit "script_sha256=$script_sha256;evaluator_sha256=$EVALUATOR_SHA256"
emit "chunk_profile_id=$CHUNK_PROFILE_ID;retrieval_profile_id=$RETRIEVAL_PROFILE_ID"
emit 'authorized_actions=run_native_tests_build_accepted_chunks_call_loopback_nomic_start_private_postgresql_measure_180_cases_write_metrics_only_observation'
emit 'non_actions=no_accepted_database_contact_no_ingestion_no_gemma_no_black_corpus_no_production_profile_no_package_or_release_change'
[[ "$actual_hostname" == "$EXPECTED_HOST" && "$actual_os_id" == "$EXPECTED_OS_ID" \
    && "$actual_os_version" == "$EXPECTED_OS_VERSION" \
    && "$actual_architecture" == "$EXPECTED_ARCHITECTURE" ]] \
  || block local_host_identity_mismatch

emit 'milestone=native_tests;state=start'
bash "$TEST_RUNNER" >"$work_root/native-tests.stdout" 2>"$work_root/native-tests.stderr" \
  || block native_tests_failed
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$work_root/native-tests.stdout" \
  || block native_tests_pass_marker_absent
test_count="$(sed -n 's/^Ran \([0-9][0-9]*\) tests\{0,1\} in .*/\1/p' \
  "$work_root/native-tests.stderr" | tail -n 1)"
[[ "$test_count" =~ ^[0-9]+$ && "$test_count" -ge 444 ]] \
  || block native_test_count_invalid
emit "milestone=native_tests;state=pass;tests=$test_count"

chunks="$work_root/accepted-v6-chunks.json"
emit 'milestone=candidate_build;state=start;documents=30;passage_candidates=943'
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B - \
  "$NORMALIZED" "$NORMALIZED_SHA256" "$chunks" "$CHUNK_PROFILE_ID" <<'PY' \
  || block candidate_build_failed
import hashlib,json,os,pathlib,sys
from ishikawa.canonical import canonical_json_bytes
from ishikawa.chunking import build_chunk_candidates
source=pathlib.Path(sys.argv[1])
assert hashlib.sha256(source.read_bytes()).hexdigest()==sys.argv[2]
chunks=build_chunk_candidates(json.loads(source.read_text(encoding="utf-8")))
assert chunks["method_profile_id"]==sys.argv[4]
assert len(chunks["documents"])==30
assert sum(len(item["candidates"]) for item in chunks["documents"])==943
destination=pathlib.Path(sys.argv[3])
descriptor=os.open(destination,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
with os.fdopen(descriptor,"wb") as stream:
 stream.write(canonical_json_bytes(chunks))
PY
chunks_sha256="$(sha256sum "$chunks" | awk '{print $1}')"
[[ "$chunks_sha256" == "$CHUNKS_SHA256" ]] || block accepted_chunks_changed
emit "milestone=candidate_build;state=pass;chunks_sha256=$chunks_sha256"

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
emit 'milestone=temporary_postgresql;state=pass;tcp_listener=false;accepted_database_contact=false'
read_secret 'Nomic API key' nomic_key
emit 'milestone=credential;state=accepted;value_logged=false;value_retained=false'

observation_candidate="$work_root/v13-44-observation.json"
emit 'milestone=decomposed_passage_reranking_measurement;state=start;cases=180;candidates=5'
measurement_started="$(date +%s)"
export ISHIKAWA_NOMIC_API_KEY="$nomic_key"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" \
  --python-root "$PYTHON_ROOT" \
  --chunks "$chunks" --expected-chunks-sha256 "$chunks_sha256" \
  --chunk-profile-id "$CHUNK_PROFILE_ID" \
  --truth "$TRUTH" --expected-truth-sha256 "$TRUTH_SHA256" \
  --embedding-url "$NOMIC_EMBEDDING_URL" --tokenizer-url "$NOMIC_TOKENIZER_URL" \
  --postgresql-socket "$postgresql_socket" --postgresql-port "$TEMPORARY_POSTGRESQL_PORT" \
  --postgresql-user "$local_user" --output "$observation_candidate" \
  >"$work_root/measurement.stdout" 2>"$work_root/measurement.stderr" &
active_pid="$!"
unset ISHIKAWA_NOMIC_API_KEY
nomic_key=''
wait_with_heartbeat decomposed_passage_reranking_measurement "$measurement_started" \
  || block decomposed_passage_reranking_measurement_failed
grep -Fxq 'v13_44_decomposed_passage_reranking_measurement=pass' \
  "$work_root/measurement.stdout" || block measurement_pass_marker_absent
if grep -Eq ' (WARNING|ERROR|FATAL|PANIC):' "$work_root/postgresql.log"; then
  block temporary_postgresql_reported_diagnostic
fi

PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$SCRIPT_DIR" "$observation_candidate" "$chunks_sha256" "$TRUTH_SHA256" \
  "$CHUNK_PROFILE_ID" "$RETRIEVAL_PROFILE_ID" \
  >"$work_root/validation-summary.txt" 2>"$work_root/validation.stderr" <<'PY' \
  || block observation_invalid
import json,math,pathlib,re,sys
sys.path.insert(0,sys.argv[1])
import measure_synthetic_corpus_v2_without_ingestion as base
import measure_v13_40_bounded_ranking_candidates as v40
import measure_v13_44_decomposed_passage_reranking as v44
p=pathlib.Path(sys.argv[2])
assert p.is_file() and not p.is_symlink() and p.stat().st_size<=128*1024*1024
x=json.loads(p.read_text(encoding="utf-8"))
assert x["artifact_kind"]=="ishikawa_v13_44_decomposed_passage_reranking_experiment"
assert x["schema_version"]==1 and x["corpus_identity"]=="synthetic-corpus-v3"
assert x["measurement_class"]=="evaluation_only_no_promotion"
assert x["source_sha256"]=={"chunks":sys.argv[3],"retrieval_truth":sys.argv[4]}
assert x["profiles"]=={"chunk_profile_id":sys.argv[5],"retrieval_profile_id":sys.argv[6]}
experiment=x["experiment"]
assert experiment["variant_order"]==list(v44.VARIANT_ORDER)
assert experiment["variant_configs"]==v44.CONFIG_BY_NAME
assert experiment["body_mrr_gate"]=="0.89" and experiment["body_coverage_gate"]=="120/120"
assert experiment["maximum_facets"]==4 and experiment["minimum_facet_words"]==3
assert experiment["primary_weights"]=={"exact":1,"lexical":2,"vector":4}
assert experiment["facet_weights"]=={"lexical":2,"vector":4}
assert experiment["rrf_constant"]==60 and experiment["learned_reranker"] is False
assert x["candidate_inventory"]=={"documents":30,"atomic":786,"representatives":157,"passage_total":943}
assert x["case_inventory"]=={"body":120,"relationship":30,"header":30,"total":180}
assert re.fullmatch(r"[0-9a-f]{64}",x["runtime_identity_digest"])
assert all(type(v) is int and v>0 for v in x["token_usage"].values())
assert all(math.isfinite(float(v)) and float(v)>=0 for v in x["latency_ms"].values())
assert x["promotion_authorized"] is False
assert x["boundaries"]=={
 "accepted_database_contact":False,"accepted_database_write":False,
 "black_corpus_access":False,"corpus_ingestion":False,"corpus_v3_changed":False,
 "gemma_contact":False,"nomic_contact":True,"private_temporary_postgresql":True,
 "production_profile_changed":False,"retained_runtime_flat_file_index":False,
 "question_text_retained":False,"decomposed_query_text_retained":False,
 "query_vectors_retained":False,"source_text_retained":False,
}
names=["accepted_v6",*v44.VARIANT_ORDER]
assert len(x["variants"])==len(names) and set(x["variants"])==set(names)
def validate(name,candidate):
 selections=candidate["results"]["selection"]
 expansions=candidate["results"]["expanded_atomic_diagnostic"]
 assert len(selections)==len(expansions)==180
 assert [i["case_id"] for i in selections]==[i["case_id"] for i in expansions]
 assert len({i["case_id"] for i in selections})==180
 assert sum(i["family"]=="body" for i in selections)==120
 assert sum(i["family"]=="relationship" for i in selections)==30
 assert sum(i["family"]=="header" for i in selections)==30
 for item in selections:
  assert "question" not in item and re.fullmatch(r"[0-9a-f]{64}",item["query_sha256"])
  assert len(item["fused"])<=20
  if name=="accepted_v6" or item["family"]!="body":
   assert item["decomposition"] is None
  else:
   diagnostic=item["decomposition"]
   assert 1<=diagnostic["facet_count"]<=4
   assert len(diagnostic["facet_sha256"])==diagnostic["facet_count"]
   assert all(re.fullmatch(r"[0-9a-f]{64}",v) for v in diagnostic["facet_sha256"])
   assert diagnostic["document_shortlist"] and len(diagnostic["document_shortlist"])<=10
   assert diagnostic["expanded_searchable_count"]>0
   assert len(diagnostic["facet_lanes"])==diagnostic["facet_count"]
   for facet in diagnostic["facet_lanes"]:
    assert set(facet)=={"lexical","vector"}
    assert all(len(lane)<=20 for lane in facet.values())
 assert all(item["decomposed_rerank_config"] is None for item in selections) if name=="accepted_v6" else True
 for family in ("body","relationship","header"):
  assert candidate["metrics"][family]==base.aggregate([i for i in selections if i["family"]==family])
 assert candidate["metrics"]["overall"]==base.aggregate(selections)
 matched=sum(i["matched_evidence_count"] for i in expansions)
 required=sum(i["required_evidence_count"] for i in expansions)
 assert candidate["authoritative_expansion"]=={
  "matched_evidence":matched,"required_evidence":required,"complete":matched==required,
 }
 assert candidate["gate"]==v40.gate_for(candidate["metrics"],matched,required)
 if name!="accepted_v6":
  movement=candidate["rank_movement"]
  assert set(movement)=={"improved","unchanged","regressed","missing_fixed","new_missing"}
  assert sum(movement[key] for key in ("improved","unchanged","regressed"))==120
for name in names: validate(name,x["variants"][name])
qualified=[name for name in v44.VARIANT_ORDER if x["variants"][name]["gate"]["status"]=="qualified"]
selected=max(qualified,key=lambda name:v44.selection_key(name,x["variants"][name])) if qualified else None
assert x["qualified_candidates"]==qualified and x["selected_candidate"]==selected
assert x["selection_status"]==("qualified_for_separate_freeze" if selected else "not_met")
for name in names:
 b=x["variants"][name]["metrics"]["body"]
 movement=x["variants"][name].get("rank_movement")
 movement_text="reference" if movement is None else f"{movement['improved']}/{movement['unchanged']}/{movement['regressed']}"
 print(f"variant={name};body_mrr_at_20={b['mrr_at_20']};body_relevant_at_5={b['relevant_at_5']}/120;body_relevant_at_20={b['relevant_at_20']}/120;movement_i_u_r={movement_text};gate={x['variants'][name]['gate']['status']}")
print(f"selection_status={x['selection_status']};selected_candidate={selected or 'none'};promotion_authorized=false")
print("observation_validation=pass")
PY
while IFS= read -r line; do emit "$line"; done <"$work_root/validation-summary.txt"
grep -Fxq 'observation_validation=pass' "$work_root/validation-summary.txt" \
  || block observation_validation_marker_absent
observation_sha256="$(sha256sum "$observation_candidate" | awk '{print $1}')"
emit "milestone=decomposed_passage_reranking_measurement;state=pass;elapsed_seconds=$(( $(date +%s) - measurement_started ));observation_sha256=$observation_sha256"
observation_artifact="$ARTIFACT_ROOT/v13_44_decomposed_passage_reranking_${timestamp}.json"
[[ ! -e "$observation_artifact" && ! -L "$observation_artifact" ]] \
  || block retained_artifact_path_exists
mv -- "$observation_candidate" "$observation_artifact"
stop_private_postgresql
emit 'milestone=temporary_postgresql_cleanup;state=pass;cluster_retained=false;listener_retained=false'
emit "observation_artifact=$observation_artifact;observation_artifact_sha256=$observation_sha256"
emit 'retained_generated_chunks=false;retained_question_text=false;retained_decomposed_query_text=false;retained_vectors=false;credentials_retained=false'
emit 'accepted_database_contact=false;corpus_ingestion=false;gemma_contact=false;black_corpus_access=false;production_profile_changed=false'
emit 'next_gate=review_v13_44_metrics_and_separately_freeze_any_selected_candidate'
remove_work_root
unset ISHIKAWA_NOMIC_API_KEY
trap - EXIT HUP INT TERM
report_sha256="$(sha256sum "$report_path" | awk '{print $1}')"
printf 'local_report=%s;local_report_sha256=%s\n' "$report_path" "$report_sha256"
printf '\nSCRIPT RESULT\nscript_196_v13_44_decomposed_passage_reranking=pass\n'
