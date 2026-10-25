#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify frozen V13-39 by rebuilding synthetic corpus v3 with the production
#   chunker, freshly embedding its PostgreSQL-bound retrieval representation,
#   and replaying all 180 retrieval cases before any corpus-v3 ingestion.
#
# Boundaries:
#   Calls only the existing loopback Nomic endpoint. PostgreSQL is temporary,
#   Unix-socket-only, and used only for native lexical measurement. Does not
#   call Gemma, contact or mutate an accepted database, access the black corpus,
#   ingest corpus v3, change retrieval parameters, or assemble a release.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/190_qualify_v13_39_postgresql_document_identity_context.sh --run

usage() {
  sed -n '3,18p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Rebuild, embed, and execute the 180-case qualification.' \
    '  --validate-only Validate bound inputs and implementation contracts only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly CHUNKER="$PYTHON_ROOT/ishikawa/chunking.py"
readonly BASE_EVALUATOR="$SCRIPT_DIR/measure_synthetic_corpus_v2_without_ingestion.py"
readonly EVALUATOR="$SCRIPT_DIR/measure_synthetic_corpus_v3_preingestion.py"
readonly EMBEDDER="$SCRIPT_DIR/embed_document_candidates_via_endpoint.py"
readonly TEST_RUNNER="$PRODUCT_ROOT/scripts/run-local-validation-tests.sh"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly SCRIPT_189_REPORT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v3-rank-review/v3_rank_failure_review_20261023T045931Z_CXiwZI.txt"
readonly NORMALIZED="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v3/synthetic_corpus_v3_candidate_20261023T043639Z/qualification/normalized.json"
readonly TRUTH="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v3-preingestion/v3_retrieval_truth_20261023T045046Z.json"
readonly BASELINE_OBSERVATION="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v3-preingestion/v3_preingestion_retrieval_observation_20261023T045046Z.json"
readonly RANK_REVIEW="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v3-rank-review/v3_rank_failure_review_20261023T045931Z.json"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v13-39-document-identity-context"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v13-39-document-identity-context"
readonly INITDB='/usr/lib/postgresql/16/bin/initdb'
readonly PG_CTL='/usr/lib/postgresql/16/bin/pg_ctl'
readonly NOMIC_HEALTH_URL='http://127.0.0.1:8001/health'
readonly NOMIC_EMBEDDING_URL='http://127.0.0.1:8001/v1/embeddings'
readonly NOMIC_TOKENIZER_URL='http://127.0.0.1:8001/tokenize'
readonly TEMPORARY_POSTGRESQL_PORT=65434
readonly EXPECTED_HOST='DankoSurface'
readonly EXPECTED_OS_ID='ubuntu'
readonly EXPECTED_OS_VERSION='24.04'
readonly EXPECTED_ARCHITECTURE='aarch64'
readonly EXPECTED_METHOD_PROFILE_ID='d72a07f81eabc1f521ab1fd54f84289979365c6c71f8e3220a53b1e8c9a1c037'
readonly EXPECTED_RETRIEVAL_PROFILE_ID='cfa9bbc353dc82d3ba74396de40df6ba429b7df2750e7809b92eeefd4a433147'
readonly SCRIPT_189_REPORT_SHA256='b5abe498bc8ef951e87d3e95ee7d223557760262c83a67a295cea2f76139e233'
readonly NORMALIZED_SHA256='1772584ecc02c86cc0bd96946318e608f576fd259676bc9851ab7c54bf766b02'
readonly TRUTH_SHA256='f74302d899d000b9493fecfeca4ffbe2995bb04aabef00bf327061c34c2a18a0'
readonly BASELINE_OBSERVATION_SHA256='28c3c134cd1d78adb7672aa699bbe50784112fa865dbb65dca3f1931e3d8974c'
readonly RANK_REVIEW_SHA256='6fb090e1a710f39c296f0a7ab41cd88bf41c8301610d8015627301599041c3d3'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      usage >&2
      printf '\nSCRIPT RESULT\nscript_190_v13_39_document_identity_context=blocked\n' >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'reason=exactly_one_mode_required\n\nSCRIPT RESULT\nscript_190_v13_39_document_identity_context=blocked\n' >&2
  exit 2
}

for command_name in awk bash basename curl date grep hostname id kill mkdir mktemp mv \
  python3 rm sed sha256sum sleep tee tr uname; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'reason=missing_command_%s\n\nSCRIPT RESULT\nscript_190_v13_39_document_identity_context=blocked\n' \
      "$command_name" >&2
    exit 2
  }
done

check_file() {
  local path="$1" expected_sha256="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] || {
    printf 'reason=%s_unsafe\n\nSCRIPT RESULT\nscript_190_v13_39_document_identity_context=blocked\n' \
      "$label" >&2
    exit 2
  }
  [[ "$(sha256sum "$path" | awk '{print $1}')" == "$expected_sha256" ]] || {
    printf 'reason=%s_identity_changed\n\nSCRIPT RESULT\nscript_190_v13_39_document_identity_context=blocked\n' \
      "$label" >&2
    exit 2
  }
}

check_file "$SCRIPT_189_REPORT" "$SCRIPT_189_REPORT_SHA256" script_189_report
check_file "$NORMALIZED" "$NORMALIZED_SHA256" normalized_v3
check_file "$TRUTH" "$TRUTH_SHA256" retrieval_truth
check_file "$BASELINE_OBSERVATION" "$BASELINE_OBSERVATION_SHA256" baseline_observation
check_file "$RANK_REVIEW" "$RANK_REVIEW_SHA256" rank_review
for executable in "$INITDB" "$PG_CTL"; do
  [[ -f "$executable" && ! -L "$executable" && -x "$executable" ]] || {
    printf 'reason=postgresql_16_binary_unsafe\n\nSCRIPT RESULT\nscript_190_v13_39_document_identity_context=blocked\n' >&2
    exit 2
  }
done
grep -Fxq 'synthetic_corpus_v3_rank_failure_review=pass' "$SCRIPT_189_REPORT" || {
  printf 'reason=script_189_not_clean_pass\n\nSCRIPT RESULT\nscript_190_v13_39_document_identity_context=blocked\n' >&2
  exit 1
}
grep -Fq '| `V13-39` |' "$DECISIONS" || {
  printf 'reason=v13_39_not_frozen\n\nSCRIPT RESULT\nscript_190_v13_39_document_identity_context=blocked\n' >&2
  exit 1
}

bash -n "${BASH_SOURCE[0]}"
for python_source in "$CHUNKER" "$BASE_EVALUATOR" "$EVALUATOR" "$EMBEDDER"; do
  PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
    'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
    "$python_source"
done
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B - \
  "$EXPECTED_METHOD_PROFILE_ID" "$EXPECTED_RETRIEVAL_PROFILE_ID" <<'PY'
import sys
from ishikawa.chunking import METHOD_PROFILE, METHOD_PROFILE_ID
from ishikawa.method_profile import ACCEPTED_RETRIEVAL_PROFILE
assert METHOD_PROFILE["name"] == "ishikawa-structural-chunk-candidates-v6"
assert METHOD_PROFILE_ID == sys.argv[1]
assert ACCEPTED_RETRIEVAL_PROFILE.chunk_method_profile_id == sys.argv[1]
assert ACCEPTED_RETRIEVAL_PROFILE.digest == sys.argv[2]
PY
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EMBEDDER" --self-test \
  | grep -Fxq 'document_embedding_endpoint_producer_self_test=pass'
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" --self-test \
  | grep -Fxq 'synthetic_corpus_v3_preingestion_measurement_self_test=pass'
PYTHONDONTWRITEBYTECODE=1 python3 -B -c 'import psycopg; assert psycopg.__version__'

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_frozen_v13_39_postgresql_document_identity_context_qualification' \
    "script_sha256=$script_sha256;method_profile_id=$EXPECTED_METHOD_PROFILE_ID" \
    "retrieval_profile_id=$EXPECTED_RETRIEVAL_PROFILE_ID;native_tests=443" \
    'documents=30;pages=150;cases=180;candidates=943' \
    'operational_storage=postgresql;runtime_flat_file_index=false' \
    'accepted_database_contact=false;model_contact=false;corpus_ingestion=false' \
    '' \
    'SCRIPT RESULT' \
    'script_190_v13_39_document_identity_context=pass'
  exit 0
fi

work_root=''
report_path=''
nomic_key=''
active_pid=''
private_pg_started=false
failure_reason='unexpected_failure'

emit() {
  if [[ -n "$report_path" ]]; then printf '%s\n' "$1" | tee -a "$report_path"
  else printf '%s\n' "$1"; fi
}

stop_private_postgresql() {
  if [[ "$private_pg_started" == true && -n "$work_root" \
        && "$work_root" == /tmp/ishikawa-script-190.* ]]; then
    "$PG_CTL" -D "$work_root/postgresql" -m fast -w stop >/dev/null 2>&1 || true
  fi
  private_pg_started=false
}

remove_work_root() {
  if [[ -n "$work_root" && "$work_root" == /tmp/ishikawa-script-190.* \
        && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
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
    printf 'local_report=%s;local_report_sha256=%s\n' \
      "$report_path" "$(sha256sum "$report_path" | awk '{print $1}')"
  else
    printf 'script_state=blocked;reason=%s;exit_code=%s\n' "$failure_reason" "$initial_status"
  fi
  printf '\nSCRIPT RESULT\nscript_190_v13_39_document_identity_context=blocked\n'
  exit "$initial_status"
}
trap failure_cleanup EXIT
trap 'failure_reason=interrupted; exit 130' HUP INT TERM
trap 'failure_reason="unexpected_failure_line_${LINENO}"' ERR

block() { failure_reason="$1"; exit 1; }

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
report_path="$(mktemp "$REPORT_ROOT/v13_39_document_identity_context_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-script-190.XXXXXX)"

actual_hostname="$(hostname -s)"
actual_os_id="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"' | awk 'NR == 1')"
actual_os_version="$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"' | awk 'NR == 1')"
actual_architecture="$(uname -m)"
local_user="$(id -un)"

emit 'purpose=qualify_frozen_v13_39_postgresql_document_identity_context'
emit "started_utc=$timestamp;hostname=$actual_hostname;os_version=$actual_os_version;architecture=$actual_architecture"
emit "script_sha256=$script_sha256;method_profile_id=$EXPECTED_METHOD_PROFILE_ID;retrieval_profile_id=$EXPECTED_RETRIEVAL_PROFILE_ID"
emit 'authorized_actions=run_local_native_tests_build_v3_candidates_call_loopback_nomic_start_private_postgresql_measure_180_cases_write_local_qualification_evidence'
emit 'non_actions=no_accepted_database_contact_no_corpus_ingestion_no_gemma_contact_no_black_corpus_access_no_parameter_tuning_no_package_or_release_change'
emit 'operational_storage=postgresql;runtime_flat_file_index=false;retained_files=qualification_evidence_only'

[[ "$actual_hostname" == "$EXPECTED_HOST" \
    && "$actual_os_id" == "$EXPECTED_OS_ID" \
    && "$actual_os_version" == "$EXPECTED_OS_VERSION" \
    && "$actual_architecture" == "$EXPECTED_ARCHITECTURE" ]] \
  || block local_host_identity_mismatch

native_stdout="$work_root/native-tests.stdout"
emit 'milestone=native_tests;state=start'
bash "$TEST_RUNNER" >"$native_stdout" 2>"$work_root/native-tests.stderr" \
  || block native_tests_failed
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$native_stdout" \
  || block native_tests_pass_marker_absent
emit 'milestone=native_tests;state=pass;tests=443'

candidate_chunks="$work_root/v3-v13-39-chunks.json"
candidate_stdout="$work_root/candidate-build.stdout"
emit 'milestone=candidate_build;state=start;documents=30;expected_candidates=943'
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B - \
  "$NORMALIZED" "$NORMALIZED_SHA256" "$candidate_chunks" \
  "$EXPECTED_METHOD_PROFILE_ID" >"$candidate_stdout" <<'PY' \
  || block candidate_build_failed
import hashlib
import json
import os
import pathlib
import sys
from ishikawa.canonical import canonical_json_bytes
from ishikawa.chunking import build_chunk_candidates

source = pathlib.Path(sys.argv[1])
assert hashlib.sha256(source.read_bytes()).hexdigest() == sys.argv[2]
result = build_chunk_candidates(json.loads(source.read_text(encoding="utf-8")))
assert result["method_profile_id"] == sys.argv[4]
assert result["method_profile"]["name"] == "ishikawa-structural-chunk-candidates-v6"
assert len(result["documents"]) == 30
candidates = [item for document in result["documents"] for item in document["candidates"]]
assert len(candidates) == 943
assert sum(item["projection_kind"] == "document_control_metadata" for item in candidates) == 30
assert sum(item["projection_kind"] == "section_page_representative" for item in candidates) == 157
for document in result["documents"]:
    metadata = [item for item in document["candidates"] if item["projection_kind"] == "document_control_metadata"]
    assert len(metadata) == 1
    control = metadata[0]["retrieval_filters"]["document_control"]
    expected = [
        f"Document: {control['document_context']}",
        f"Document identifier: {control['policy_number']}",
    ]
    for candidate in document["candidates"]:
        identity = candidate["projection_properties"]["retrieval_document_identity_context"]
        assert identity["document_context"] == control["document_context"]
        assert identity["policy_number"] == control["policy_number"]
        if candidate["projection_kind"] == "document_control_metadata":
            assert identity["included_in_retrieval_text"] is False
        else:
            assert candidate["context_text"].splitlines()[:2] == expected
            assert candidate["retrieval_text"].splitlines()[:2] == expected
            assert identity["included_in_retrieval_text"] is True
output = pathlib.Path(sys.argv[3])
descriptor = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(descriptor, "wb") as stream:
    stream.write(canonical_json_bytes(result))
print(result["chunk_candidate_set_digest"])
PY
grep -Eq '^[0-9a-f]{64}$' "$candidate_stdout" \
  || block candidate_build_identity_invalid
candidate_sha256="$(sha256sum "$candidate_chunks" | awk '{print $1}')"
emit "milestone=candidate_build;state=pass;documents=30;candidates=943;identity_enriched_body_candidates=913/913;artifact_sha256=$candidate_sha256"

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

embedding_candidate="$work_root/v3-v13-39-embeddings.json"
embedding_stdout="$work_root/embedding.stdout"
emit 'milestone=document_embeddings;state=start;candidates=943'
embedding_started="$(date +%s)"
(
  printf '%s' "$nomic_key" | PYTHONDONTWRITEBYTECODE=1 python3 -B "$EMBEDDER" \
    --input "$candidate_chunks" \
    --expected-input-sha256 "$candidate_sha256" \
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

observation_candidate="$work_root/v3-v13-39-observation.json"
measurement_stdout="$work_root/measurement.stdout"
emit 'milestone=retrieval_measurement;state=start;cases=180;body_mrr_gate=0.89'
measurement_started="$(date +%s)"
export ISHIKAWA_NOMIC_API_KEY="$nomic_key"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" \
  --python-root "$PYTHON_ROOT" \
  --chunks "$candidate_chunks" \
  --expected-chunks-sha256 "$candidate_sha256" \
  --document-embeddings "$embedding_candidate" \
  --expected-document-embeddings-sha256 "$embedding_sha256" \
  --truth "$TRUTH" \
  --expected-truth-sha256 "$TRUTH_SHA256" \
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
  "$observation_candidate" "$BASELINE_OBSERVATION" "$candidate_sha256" \
  "$embedding_sha256" "$TRUTH_SHA256" "$EXPECTED_RETRIEVAL_PROFILE_ID" \
  >"$validation_summary" <<'PY' \
  || block retrieval_qualification_validation_failed
import json
import pathlib
import sys

candidate = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
baseline = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
body = candidate["metrics"]["body"]
relationship = candidate["metrics"]["relationship"]
header = candidate["metrics"]["header"]
case_b006 = next(
    (
        item
        for item in candidate["results"]["selection"]
        if item["case_id"] == "B-006"
    ),
    None,
)
b006_refs = (
    case_b006.get("permitted_document_refs", [])
    if isinstance(case_b006, dict)
    else []
)
baseline_mrr = baseline["metrics"]["body"]["mrr_at_20"]
print(
    f"body_mrr_at_20={body['mrr_at_20']};baseline_body_mrr_at_20={baseline_mrr};"
    f"relevant_at_20={body['relevant_at_20']}/120;"
    f"required_evidence_at_20={body['required_evidence_matched_at_20']}/"
    f"{body['required_evidence_total']}"
)
print(
    f"relationship_mrr_at_20={relationship['mrr_at_20']};"
    f"relationship_relevant_at_20={relationship['relevant_at_20']}/30;"
    f"relationship_required_evidence_at_20="
    f"{relationship['required_evidence_matched_at_20']}/"
    f"{relationship['required_evidence_total']};"
    f"header_mrr_at_20={header['mrr_at_20']};"
    f"header_relevant_at_20={header['relevant_at_20']}/30;"
    f"header_required_evidence_at_20={header['required_evidence_matched_at_20']}/"
    f"{header['required_evidence_total']}"
)
print(
    f"authoritative_expansion="
    f"{candidate['authoritative_expansion']['matched_evidence']}/"
    f"{candidate['authoritative_expansion']['required_evidence']};"
    f"b006_present={'true' if case_b006 is not None else 'false'};"
    f"b006_permitted_documents={len(b006_refs)}"
)

checks = {
    "source_identities": candidate["source_sha256"] == {
        "chunks": sys.argv[3],
        "document_embeddings": sys.argv[4],
        "retrieval_truth": sys.argv[5],
    },
    "retrieval_profile": (
        candidate["retrieval_profile"]["profile_id"] == sys.argv[6]
    ),
    "candidate_inventory": candidate["candidate_inventory"] == {
        "documents": 30,
        "atomic": 786,
        "representatives": 157,
        "total": 943,
    },
    "case_inventory": candidate["case_inventory"] == {
        "body": 120,
        "relationship": 30,
        "header": 30,
        "total": 180,
    },
    "body_mrr_at_20": float(body["mrr_at_20"]) >= 0.89,
    "body_relevant_at_20": body["relevant_at_20"] == 120,
    "body_required_evidence_at_20": (
        body["required_evidence_matched_at_20"]
        == body["required_evidence_total"]
        == 120
    ),
    "relationship_relevant_at_20": relationship["relevant_at_20"] == 30,
    "relationship_required_evidence_at_20": (
        relationship["required_evidence_matched_at_20"]
        == relationship["required_evidence_total"]
        == 30
    ),
    "header_mrr_at_20": header["mrr_at_20"] == "1.000000",
    "header_relevant_at_20": header["relevant_at_20"] == 30,
    "header_required_evidence_at_20": (
        header["required_evidence_matched_at_20"]
        == header["required_evidence_total"]
        == 30
    ),
    "authoritative_expansion": candidate["authoritative_expansion"] == {
        "matched_evidence": 180,
        "required_evidence": 180,
        "complete": True,
    },
    "b006_corpus_wide_scope": (
        "SYN-V3-002" in b006_refs and len(b006_refs) == 30
    ),
}
for name, passed in checks.items():
    print(f"gate_check={name};state={'pass' if passed else 'failed'}")
failed = [name for name, passed in checks.items() if not passed]
print(f"failed_gate_count={len(failed)};failed_gates={','.join(failed) if failed else 'none'}")
print(f"qualification_gate={'pass' if not failed else 'blocked'}")
PY
while IFS= read -r summary_line; do emit "$summary_line"; done <"$validation_summary"
if ! grep -Fxq 'qualification_gate=pass' "$validation_summary"; then
  diagnostic_root="$ARTIFACT_ROOT/blocked_${timestamp}"
  [[ ! -e "$diagnostic_root" && ! -L "$diagnostic_root" ]] \
    || block diagnostic_artifact_path_exists
  # DrvFS may create the directory and then reject chmod(2).  These retained
  # files contain only synthetic qualification evidence and no credentials,
  # so inherit the mounted workspace permissions instead of requesting a mode.
  mkdir -- "$diagnostic_root"
  mv -- "$candidate_chunks" "$diagnostic_root/v3_v13_39_chunks.json"
  mv -- "$embedding_candidate" "$diagnostic_root/v3_v13_39_embeddings.json"
  mv -- "$observation_candidate" "$diagnostic_root/v3_v13_39_observation.json"
  (
    cd -- "$diagnostic_root"
    sha256sum v3_v13_39_chunks.json v3_v13_39_embeddings.json \
      v3_v13_39_observation.json >SHA256SUMS
  )
  emit "blocked_diagnostic_artifacts=$diagnostic_root"
  emit 'blocked_diagnostic_permissions=workspace_inherited;credentials_retained=false'
  emit "blocked_diagnostic_checksums_sha256=$(sha256sum "$diagnostic_root/SHA256SUMS" | awk '{print $1}')"
  block retrieval_qualification_gate_failed
fi
emit "milestone=retrieval_measurement;state=pass;elapsed_seconds=$(( $(date +%s) - measurement_started ));artifact_sha256=$observation_sha256"

chunks_artifact="$ARTIFACT_ROOT/v3_v13_39_chunks_${timestamp}.json"
embedding_artifact="$ARTIFACT_ROOT/v3_v13_39_embeddings_${timestamp}.json"
observation_artifact="$ARTIFACT_ROOT/v3_v13_39_observation_${timestamp}.json"
checksum_artifact="$ARTIFACT_ROOT/SHA256SUMS_${timestamp}"
for destination in "$chunks_artifact" "$embedding_artifact" "$observation_artifact" "$checksum_artifact"; do
  [[ ! -e "$destination" && ! -L "$destination" ]] || block retained_artifact_path_exists
done
mv -- "$candidate_chunks" "$chunks_artifact"
mv -- "$embedding_candidate" "$embedding_artifact"
mv -- "$observation_candidate" "$observation_artifact"
(
  cd -- "$ARTIFACT_ROOT"
  sha256sum "$(basename -- "$chunks_artifact")" \
    "$(basename -- "$embedding_artifact")" \
    "$(basename -- "$observation_artifact")" >"$(basename -- "$checksum_artifact")"
)

stop_private_postgresql
emit 'milestone=temporary_postgresql_cleanup;state=pass;cluster_retained=false;listener_retained=false'
emit "chunks_artifact=$chunks_artifact;chunks_artifact_sha256=$candidate_sha256"
emit "embedding_artifact=$embedding_artifact;embedding_artifact_sha256=$embedding_sha256"
emit "observation_artifact=$observation_artifact;observation_artifact_sha256=$observation_sha256"
emit "checksum_artifact=$checksum_artifact;checksum_artifact_sha256=$(sha256sum "$checksum_artifact" | awk '{print $1}')"
emit 'operational_storage=postgresql;runtime_flat_file_index=false;retained_files=qualification_evidence_only'
emit 'accepted_database_contact=false;corpus_ingestion=false;gemma_contact=false;black_corpus_access=false;retrieval_parameters_changed=false'
emit 'next_gate=isolated_postgresql_ingestion_and_complete_v3_api_gemma_qualification'

remove_work_root
unset ISHIKAWA_NOMIC_API_KEY
trap - EXIT HUP INT TERM
report_sha256="$(sha256sum "$report_path" | awk '{print $1}')"
printf 'local_report=%s;local_report_sha256=%s\n' "$report_path" "$report_sha256"
printf '\nSCRIPT RESULT\nscript_190_v13_39_document_identity_context=pass\n'
