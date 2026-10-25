#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Execute the frozen V13-41 evaluation-only supplemental-signal experiment
#   over all 180 checksum-bound synthetic-corpus-v3 cases.
#
# Boundaries:
#   Calls only loopback Nomic and a private Unix-socket PostgreSQL instance.
#   Does not ingest or modify corpus v3, contact Gemma or an accepted database,
#   access the black corpus, change a production profile, or assemble a release.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/193_measure_v13_41_supplemental_ranking.sh --run

usage() {
  sed -n '3,16p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Execute the bounded 10-candidate, 180-case experiment.' \
    '  --validate-only Validate every local input and implementation contract.'
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
readonly EVALUATOR="$SCRIPT_DIR/measure_v13_41_supplemental_ranking.py"
readonly ENDPOINT_CLIENT="$SCRIPT_DIR/embed_document_candidates_via_endpoint.py"
readonly TEST_RUNNER="$PRODUCT_ROOT/scripts/run-local-validation-tests.sh"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly SCRIPT_192_REPORT="$REPO_ROOT/local/reports/ishikawa-v13-40-bounded-ranking-review/v13_40_measurement_review_20261023T061852Z_wL7Duj.txt"
readonly NORMALIZED="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v3/synthetic_corpus_v3_candidate_20261023T043639Z/qualification/normalized.json"
readonly TRUTH="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v3-preingestion/v3_retrieval_truth_20261023T045046Z.json"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v13-41-supplemental-ranking"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v13-41-supplemental-ranking"
readonly INITDB='/usr/lib/postgresql/16/bin/initdb'
readonly PG_CTL='/usr/lib/postgresql/16/bin/pg_ctl'
readonly NOMIC_HEALTH_URL='http://127.0.0.1:8001/health'
readonly NOMIC_EMBEDDING_URL='http://127.0.0.1:8001/v1/embeddings'
readonly NOMIC_TOKENIZER_URL='http://127.0.0.1:8001/tokenize'
readonly TEMPORARY_POSTGRESQL_PORT=65436
readonly EXPECTED_HOST='DankoSurface'
readonly EXPECTED_OS_ID='ubuntu'
readonly EXPECTED_OS_VERSION='24.04'
readonly EXPECTED_ARCHITECTURE='aarch64'
readonly EXPECTED_METHOD_PROFILE_ID='d72a07f81eabc1f521ab1fd54f84289979365c6c71f8e3220a53b1e8c9a1c037'
readonly EXPECTED_RETRIEVAL_PROFILE_ID='cfa9bbc353dc82d3ba74396de40df6ba429b7df2750e7809b92eeefd4a433147'
readonly SCRIPT_192_REPORT_SHA256='6eff698fcb310657304bc2edf0ca95317f151fc3d7edb113aa26f12e5874027c'
readonly NORMALIZED_SHA256='1772584ecc02c86cc0bd96946318e608f576fd259676bc9851ab7c54bf766b02'
readonly TRUTH_SHA256='f74302d899d000b9493fecfeca4ffbe2995bb04aabef00bf327061c34c2a18a0'
readonly EXPECTED_CHUNKS_SHA256='49a67ac067d06b6068878be6530ae4971bddb4a1f687545578bd1ef9254d19e4'
readonly CHUNKER_SHA256='14f8019d64af04a4a1afe5028dcbab97fca6c50d703ccd231b04fa1caafe2265'
readonly METHOD_PROFILE_SHA256='a915dd57b9c783a1f34e0744f20748809399057b956d1cc6ee3d68abedddfa77'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      usage >&2
      printf '\nSCRIPT RESULT\nscript_193_v13_41_supplemental_ranking=blocked\n' >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'reason=exactly_one_mode_required\n\nSCRIPT RESULT\nscript_193_v13_41_supplemental_ranking=blocked\n' >&2
  exit 2
}

for command_name in awk bash curl date grep hostname id kill mkdir mktemp mv \
  python3 rm sed sha256sum sleep tee tr uname; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'reason=missing_command_%s\n\nSCRIPT RESULT\nscript_193_v13_41_supplemental_ranking=blocked\n' \
      "$command_name" >&2
    exit 2
  }
done

check_file() {
  local path="$1" expected_sha256="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] || {
    printf 'reason=%s_unsafe\n\nSCRIPT RESULT\nscript_193_v13_41_supplemental_ranking=blocked\n' \
      "$label" >&2
    exit 2
  }
  [[ "$(sha256sum "$path" | awk '{print $1}')" == "$expected_sha256" ]] || {
    printf 'reason=%s_identity_changed\n\nSCRIPT RESULT\nscript_193_v13_41_supplemental_ranking=blocked\n' \
      "$label" >&2
    exit 2
  }
}

check_file "$SCRIPT_192_REPORT" "$SCRIPT_192_REPORT_SHA256" script_192_report
check_file "$NORMALIZED" "$NORMALIZED_SHA256" normalized_v3
check_file "$TRUTH" "$TRUTH_SHA256" retrieval_truth
check_file "$CHUNKER" "$CHUNKER_SHA256" chunker
check_file "$METHOD_PROFILE" "$METHOD_PROFILE_SHA256" method_profile
for executable in "$INITDB" "$PG_CTL"; do
  [[ -f "$executable" && ! -L "$executable" && -x "$executable" ]] || {
    printf 'reason=postgresql_16_binary_unsafe\n\nSCRIPT RESULT\nscript_193_v13_41_supplemental_ranking=blocked\n' >&2
    exit 2
  }
done
grep -Fq '| `V13-41` |' "$DECISIONS" || {
  printf 'reason=v13_41_not_frozen\n\nSCRIPT RESULT\nscript_193_v13_41_supplemental_ranking=blocked\n' >&2
  exit 1
}
grep -Fxq 'v13_40_measurement_review=pass' "$SCRIPT_192_REPORT" || {
  printf 'reason=v13_40_review_antecedent_missing\n\nSCRIPT RESULT\nscript_193_v13_41_supplemental_ranking=blocked\n' >&2
  exit 1
}

bash -n "${BASH_SOURCE[0]}"
for python_source in "$CHUNKER" "$BASE_EVALUATOR" "$V3_EVALUATOR" \
  "$V40_EVALUATOR" "$EVALUATOR" "$ENDPOINT_CLIENT"; do
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
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" --self-test \
  | grep -Fxq 'v13_41_supplemental_ranking_measurement_self_test=pass'
PYTHONDONTWRITEBYTECODE=1 python3 -B -c 'import psycopg; assert psycopg.__version__'

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
evaluator_sha256="$(sha256sum "$EVALUATOR" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_frozen_v13_41_supplemental_ranking_experiment' \
    "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256" \
    "method_profile_id=$EXPECTED_METHOD_PROFILE_ID;retrieval_profile_id=$EXPECTED_RETRIEVAL_PROFILE_ID" \
    'documents=30;pages=150;cases=180;initial_candidates=10;maximum_finalists=3' \
    'body_mrr_gate=0.89;body_coverage_gate=120/120;authoritative_expansion_gate=180/180' \
    'fresh_repeat_passes=2;operational_storage=postgresql;runtime_flat_file_index=false' \
    'accepted_database_contact=false;model_contact=false;corpus_ingestion=false' \
    '' \
    'SCRIPT RESULT' \
    'script_193_v13_41_supplemental_ranking=pass'
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
  if [[ -n "$report_path" ]]; then printf '%s\n' "$1" | tee -a "$report_path"
  else printf '%s\n' "$1"; fi
}

stop_private_postgresql() {
  if [[ "$private_pg_started" == true && -n "$work_root" \
        && "$work_root" == /tmp/ishikawa-script-193.* ]]; then
    "$PG_CTL" -D "$work_root/postgresql" -m fast -w stop >/dev/null 2>&1 || true
  fi
  private_pg_started=false
}

remove_work_root() {
  if [[ -n "$work_root" && "$work_root" == /tmp/ishikawa-script-193.* \
        && -d "$work_root" ]]; then rm -rf -- "$work_root"; fi
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
  if [[ -n "$observation_candidate" && -f "$observation_candidate" \
        && ! -L "$observation_candidate" && -n "$timestamp" ]]; then
    blocked_observation="$ARTIFACT_ROOT/blocked_v13_41_supplemental_ranking_${timestamp}.json"
    if [[ ! -e "$blocked_observation" && ! -L "$blocked_observation" ]]; then
      mv -- "$observation_candidate" "$blocked_observation"
      emit "blocked_observation=$blocked_observation;blocked_observation_sha256=$(sha256sum "$blocked_observation" | awk '{print $1}')"
    else
      emit 'blocked_observation_retention=skipped;reason=destination_exists'
    fi
  fi
  stop_private_postgresql
  remove_work_root
  if [[ -n "$report_path" && -f "$report_path" ]]; then
    emit "script_state=blocked;reason=$failure_reason;exit_code=$initial_status"
    printf 'local_report=%s;local_report_sha256=%s\n' \
      "$report_path" "$(sha256sum "$report_path" | awk '{print $1}')"
  else
    printf 'script_state=blocked;reason=%s;exit_code=%s\n' "$failure_reason" "$initial_status"
  fi
  printf '\nSCRIPT RESULT\nscript_193_v13_41_supplemental_ranking=blocked\n'
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
report_path="$(mktemp "$REPORT_ROOT/v13_41_supplemental_ranking_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-script-193.XXXXXX)"

actual_hostname="$(hostname -s)"
actual_os_id="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"' | awk 'NR == 1')"
actual_os_version="$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"' | awk 'NR == 1')"
actual_architecture="$(uname -m)"
local_user="$(id -un)"

emit 'purpose=measure_frozen_v13_41_supplemental_ranking'
emit "started_utc=$timestamp;hostname=$actual_hostname;os_version=$actual_os_version;architecture=$actual_architecture"
emit "script_sha256=$script_sha256;evaluator_sha256=$evaluator_sha256"
emit "method_profile_id=$EXPECTED_METHOD_PROFILE_ID;retrieval_profile_id=$EXPECTED_RETRIEVAL_PROFILE_ID"
emit 'experiment=10_initial_candidates_top_3_qualifying_finalists_2_fresh_repeats'
emit 'authorized_actions=run_local_native_tests_build_v3_candidates_call_loopback_nomic_start_private_postgresql_measure_180_cases_write_local_observation'
emit 'non_actions=no_accepted_database_contact_no_corpus_ingestion_no_gemma_contact_no_black_corpus_access_no_production_profile_change_no_package_or_release_change'
emit 'operational_storage=postgresql;runtime_flat_file_index=false;retained_files=qualification_evidence_only'

[[ "$actual_hostname" == "$EXPECTED_HOST" \
    && "$actual_os_id" == "$EXPECTED_OS_ID" \
    && "$actual_os_version" == "$EXPECTED_OS_VERSION" \
    && "$actual_architecture" == "$EXPECTED_ARCHITECTURE" ]] \
  || block local_host_identity_mismatch

emit 'milestone=native_tests;state=start'
bash "$TEST_RUNNER" >"$work_root/native-tests.stdout" 2>"$work_root/native-tests.stderr" \
  || block native_tests_failed
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$work_root/native-tests.stdout" \
  || block native_tests_pass_marker_absent
grep -Eq '^Ran [0-9]+ tests? in ' "$work_root/native-tests.stderr" \
  || block native_test_count_absent
test_count="$(sed -n 's/^Ran \([0-9][0-9]*\) tests\{0,1\} in .*/\1/p' \
  "$work_root/native-tests.stderr" | tail -n 1)"
[[ "$test_count" =~ ^[0-9]+$ && "$test_count" -ge 443 ]] || block native_test_count_invalid
emit "milestone=native_tests;state=pass;tests=$test_count"

candidate_chunks="$work_root/v3-v13-41-chunks.json"
emit 'milestone=candidate_build;state=start;documents=30;expected_candidates=943'
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B - \
  "$NORMALIZED" "$NORMALIZED_SHA256" "$candidate_chunks" \
  "$EXPECTED_METHOD_PROFILE_ID" <<'PY' \
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
assert sum(item["projection_kind"] != "document_control_metadata" for item in candidates) == 913
for document in result["documents"]:
    metadata = [item for item in document["candidates"] if item["projection_kind"] == "document_control_metadata"]
    assert len(metadata) == 1
    control = metadata[0]["retrieval_filters"]["document_control"]
    expected = [f"Document: {control['document_context']}", f"Document identifier: {control['policy_number']}"]
    for candidate in document["candidates"]:
        identity = candidate["projection_properties"]["retrieval_document_identity_context"]
        assert identity["document_context"] == control["document_context"]
        assert identity["policy_number"] == control["policy_number"]
        if candidate["projection_kind"] == "document_control_metadata":
            assert identity["included_in_retrieval_text"] is False
        else:
            assert candidate["retrieval_text"].splitlines()[:2] == expected
            assert identity["included_in_retrieval_text"] is True
output = pathlib.Path(sys.argv[3])
descriptor = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(descriptor, "wb") as stream:
    stream.write(canonical_json_bytes(result))
PY
candidate_sha256="$(sha256sum "$candidate_chunks" | awk '{print $1}')"
[[ "$candidate_sha256" == "$EXPECTED_CHUNKS_SHA256" ]] \
  || block generated_candidate_identity_changed
emit "milestone=candidate_build;state=pass;documents=30;candidates=943;artifact_sha256=$candidate_sha256"

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

observation_candidate="$work_root/v13-41-observation.json"
emit 'milestone=supplemental_ranking_measurement;state=start;cases=180;initial_candidates=10;maximum_finalists=3;fresh_repeat_passes=2'
measurement_started="$(date +%s)"
export ISHIKAWA_NOMIC_API_KEY="$nomic_key"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" \
  --python-root "$PYTHON_ROOT" \
  --chunks "$candidate_chunks" \
  --expected-chunks-sha256 "$candidate_sha256" \
  --truth "$TRUTH" \
  --expected-truth-sha256 "$TRUTH_SHA256" \
  --embedding-url "$NOMIC_EMBEDDING_URL" \
  --tokenizer-url "$NOMIC_TOKENIZER_URL" \
  --postgresql-socket "$postgresql_socket" \
  --postgresql-port "$TEMPORARY_POSTGRESQL_PORT" \
  --postgresql-user "$local_user" \
  --output "$observation_candidate" \
  >"$work_root/measurement.stdout" 2>"$work_root/measurement.stderr" &
active_pid="$!"
unset ISHIKAWA_NOMIC_API_KEY
nomic_key=''
wait_with_heartbeat supplemental_ranking_measurement "$measurement_started" \
  || block supplemental_ranking_measurement_failed
grep -Fxq 'v13_41_supplemental_ranking_measurement=pass' "$work_root/measurement.stdout" \
  || block supplemental_ranking_measurement_pass_marker_absent

PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$SCRIPT_DIR" "$observation_candidate" "$candidate_sha256" "$TRUTH_SHA256" \
  "$EXPECTED_RETRIEVAL_PROFILE_ID" >"$work_root/validation-summary.txt" \
  2>"$work_root/validation.stderr" <<'PY' \
  || block supplemental_ranking_observation_invalid
import json
import math
import pathlib
import re
import sys
from fractions import Fraction

sys.path.insert(0, sys.argv[1])
import measure_synthetic_corpus_v2_without_ingestion as base
import measure_v13_40_bounded_ranking_candidates as v40
import measure_v13_41_supplemental_ranking as v41

source_path = pathlib.Path(sys.argv[2])
assert source_path.is_file() and not source_path.is_symlink()
assert source_path.stat().st_size <= 96 * 1024 * 1024
source = json.loads(source_path.read_text(encoding="utf-8"))
order = list(v41.VARIANT_ORDER)
expected_configs = v41.CONFIG_BY_NAME
assert source["artifact_kind"] == "ishikawa_v13_41_supplemental_ranking_experiment"
assert source["schema_version"] == 1
assert source["corpus_identity"] == "synthetic-corpus-v3"
assert source["measurement_class"] == "evaluation_only_no_promotion"
assert source["source_sha256"] == {"chunks": sys.argv[3], "retrieval_truth": sys.argv[4]}
assert source["retrieval_profile"] == {
    "reference_profile_id": sys.argv[5],
    "exact_candidate_depth": 1,
    "identity_lexical_candidate_depth": 20,
    "identity_vector_candidate_depth": 20,
    "passage_lexical_candidate_depth": 20,
    "passage_vector_candidate_depth": 20,
    "fused_candidate_depth": 20,
    "rrf_constant": 60,
    "primary_weights": {"exact": 1, "identity_lexical": 2, "identity_vector": 4},
    "learned_reranker": False,
}
assert source["experiment"] == {
    "variant_order": order,
    "variant_configs": expected_configs,
    "balanced_shortlist": "union_of_top_unique_documents_per_primary_lane_plus_exact",
    "body_mrr_gate": "0.89",
    "maximum_initial_candidates": 10,
    "maximum_finalists": 3,
    "required_fresh_repeat_passes": 2,
    "selection_order": [
        "worst_pass_body_mrr_at_20_desc",
        "worst_pass_body_relevant_at_5_desc",
        "declared_variant_order",
    ],
}
assert source["candidate_inventory"] == {"documents": 30, "atomic": 786, "representatives": 157, "total": 943}
assert source["case_inventory"] == {"body": 120, "relationship": 30, "header": 30, "total": 180}
assert re.fullmatch(r"[0-9a-f]{64}", source["runtime_identity_digest"])
assert source["boundaries"] == {
    "accepted_database_contact": False,
    "accepted_database_write": False,
    "black_corpus_access": False,
    "corpus_ingestion": False,
    "corpus_v3_changed": False,
    "gemma_contact": False,
    "nomic_contact": True,
    "private_temporary_postgresql": True,
    "production_profile_changed": False,
    "runtime_flat_file_index": False,
    "question_text_retained": False,
    "query_vectors_retained": False,
    "source_text_retained": False,
}
assert source["promotion_authorized"] is False
assert source["next_gate"] == "review_and_separately_freeze_any_selected_candidate"
assert type(source["token_usage"]["all_embedding_tokens"]) is int and source["token_usage"]["all_embedding_tokens"] > 0
assert all(math.isfinite(float(value)) and float(value) >= 0 for value in source["latency_ms"].values())

passes = source["measurement_passes"]
assert 1 <= len(passes) <= 3
assert [item["pass"] for item in passes] == list(range(1, len(passes) + 1))
assert all(item["fresh_embeddings"] is True and item["embedding_tokens"] > 0 for item in passes)
first = passes[0]["variants"]
assert list(first) == sorted(["reference_current_identity", *order])

def validate_variant(name, candidate, reference=False):
    selections = candidate["results"]["selection"]
    expansions = candidate["results"]["expanded_atomic_diagnostic"]
    assert len(selections) == len(expansions) == 180
    assert [item["case_id"] for item in selections] == [item["case_id"] for item in expansions]
    assert len({item["case_id"] for item in selections}) == 180
    assert sum(item["family"] == "body" for item in selections) == 120
    assert sum(item["family"] == "relationship" for item in selections) == 30
    assert sum(item["family"] == "header" for item in selections) == 30
    config = None if reference else expected_configs[name]
    for item in selections:
        assert "question" not in item
        assert re.fullmatch(r"[0-9a-f]{64}", item["query_sha256"])
        assert len(item["fused"]) <= 20
        for lane in item["lanes"].values():
            assert [row["rank"] for row in lane] == list(range(1, len(lane) + 1))
            assert all(math.isfinite(float(row["score"])) for row in lane)
        if reference:
            assert item["document_shortlist"] == []
            assert item["supplemental_weights"] == {"passage_lexical": 0, "passage_vector": 0}
            assert "supplemental_lanes" not in item
        else:
            shortlist = item["document_shortlist"]
            assert 1 <= len(shortlist) <= 2 * config["shortlist_per_lane"] + 1
            assert len(shortlist) == len(set(shortlist))
            assert set(shortlist) <= set(item["permitted_document_refs"])
            assert item["supplemental_weights"] == {
                "passage_lexical": config["passage_lexical_weight"],
                "passage_vector": config["passage_vector_weight"],
            }
            assert set(item["supplemental_lanes"]) == {"passage_lexical", "passage_vector"}
            for lane_name, lane in item["supplemental_lanes"].items():
                assert [row["rank"] for row in lane] == list(range(1, len(lane) + 1))
                assert all(row["document_ref"] in shortlist for row in lane)
                assert all(math.isfinite(float(row["score"])) for row in lane)
            for lane_name in ("lexical", "vector"):
                assert all(row["document_ref"] in shortlist for row in item["lanes"][lane_name])
            assert all(row["document_ref"] in shortlist for row in item["lanes"]["exact"])
    for family in ("body", "relationship", "header"):
        assert candidate["metrics"][family] == base.aggregate([item for item in selections if item["family"] == family])
    assert candidate["metrics"]["overall"] == base.aggregate(selections)
    matched = sum(item["matched_evidence_count"] for item in expansions)
    required = sum(item["required_evidence_count"] for item in expansions)
    assert candidate["authoritative_expansion"] == {
        "matched_evidence": matched,
        "required_evidence": required,
        "complete": matched == required,
    }
    assert candidate["gate"] == v40.gate_for(candidate["metrics"], matched, required)

validate_variant("reference_current_identity", first["reference_current_identity"], True)
for name in order:
    validate_variant(name, first[name])

initial_qualified = [name for name in order if first[name]["gate"]["status"] == "qualified"]
assert source["initial_qualified_candidates"] == initial_qualified
expected_finalists = sorted(
    initial_qualified,
    key=lambda name: v41.selection_key(name, first[name]),
    reverse=True,
)[:3]
assert source["initial_finalists"] == expected_finalists
assert len(passes) == (3 if expected_finalists else 1)
repeat_maps = []
for pass_record in passes[1:]:
    assert set(pass_record["variants"]) == set(expected_finalists)
    repeat_maps.append(pass_record["variants"])
    for name in expected_finalists:
        validate_variant(name, pass_record["variants"][name])
repeat_qualified = [
    name for name in expected_finalists
    if len(repeat_maps) == 2
    and all(item[name]["gate"]["status"] == "qualified" for item in repeat_maps)
]
assert source["repeat_qualified_candidates"] == repeat_qualified
selected = max(
    repeat_qualified,
    key=lambda name: v41.worst_pass_key(name, first, repeat_maps),
) if repeat_qualified else None
assert source["selected_candidate"] == selected
assert source["selection_status"] == ("qualified" if selected else "not_met")

body = first["reference_current_identity"]["metrics"]["body"]
print(f"reference=current_identity;body_mrr_at_20={body['mrr_at_20']};body_relevant_at_5={body['relevant_at_5']}/120;body_relevant_at_20={body['relevant_at_20']}/120")
for name in order:
    candidate = first[name]
    body = candidate["metrics"]["body"]
    print(f"variant={name};body_mrr_at_20={body['mrr_at_20']};body_relevant_at_5={body['relevant_at_5']}/120;body_relevant_at_20={body['relevant_at_20']}/120;gate={candidate['gate']['status']}")
print(f"initial_qualified={','.join(initial_qualified) if initial_qualified else 'none'};initial_finalists={','.join(expected_finalists) if expected_finalists else 'none'};fresh_repeat_passes={len(repeat_maps)}")
print(f"selection_status={source['selection_status']};selected_candidate={selected or 'none'};promotion_authorized=false")
print("observation_validation=pass")
PY
while IFS= read -r summary_line; do emit "$summary_line"; done <"$work_root/validation-summary.txt"
grep -Fxq 'observation_validation=pass' "$work_root/validation-summary.txt" \
  || block observation_validation_pass_marker_absent
observation_sha256="$(sha256sum "$observation_candidate" | awk '{print $1}')"
emit "milestone=supplemental_ranking_measurement;state=pass;elapsed_seconds=$(( $(date +%s) - measurement_started ));observation_sha256=$observation_sha256"

observation_artifact="$ARTIFACT_ROOT/v13_41_supplemental_ranking_${timestamp}.json"
[[ ! -e "$observation_artifact" && ! -L "$observation_artifact" ]] \
  || block retained_artifact_path_exists
mv -- "$observation_candidate" "$observation_artifact"

stop_private_postgresql
emit 'milestone=temporary_postgresql_cleanup;state=pass;cluster_retained=false;listener_retained=false'
emit "observation_artifact=$observation_artifact;observation_artifact_sha256=$observation_sha256"
emit 'retained_generated_chunks=false;retained_vectors=false;credentials_retained=false'
emit 'accepted_database_contact=false;corpus_ingestion=false;gemma_contact=false;black_corpus_access=false;production_profile_changed=false'
emit 'next_gate=review_v13_41_metrics_and_separately_freeze_any_selected_candidate'

remove_work_root
unset ISHIKAWA_NOMIC_API_KEY
trap - EXIT HUP INT TERM
report_sha256="$(sha256sum "$report_path" | awk '{print $1}')"
printf 'local_report=%s;local_report_sha256=%s\n' "$report_path" "$report_sha256"
printf '\nSCRIPT RESULT\nscript_193_v13_41_supplemental_ranking=pass\n'
