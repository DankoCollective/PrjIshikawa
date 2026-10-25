#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Search bounded RRF, lane-weight, and lane-depth profiles against the exact
#   synthetic-corpus-v2 retrieval baseline promoted by Script 174.
#
# Boundaries:
#   Existing loopback Nomic only, one disposable Unix-socket PostgreSQL
#   cluster, no Gemma, no accepted database, and no corpus, truth, release, or
#   production-profile mutation. Observed finalists require a later review.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/175_search_frozen_synthetic_corpus_v2_retrieval_optimizations.sh --run

usage() {
  sed -n '3,14p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Capture lanes once and search 2,646 offline profiles.' \
    '  --validate-only Validate frozen inputs and local contracts only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PYTHON_ROOT="$PHASE_ROOT/Ishikawa/application/python"
readonly OPTIMIZER="$SCRIPT_DIR/search_promoted_v2_section_page_optimizations.py"
readonly EXPERIMENT_EVALUATOR="$SCRIPT_DIR/measure_published_v2_section_page_experiment.py"
readonly CANDIDATE_EVALUATOR="$SCRIPT_DIR/measure_synthetic_corpus_v2_candidate_profile.py"
readonly BASE_EVALUATOR="$SCRIPT_DIR/measure_synthetic_corpus_v2_without_ingestion.py"
readonly EMBEDDER="$SCRIPT_DIR/embed_document_candidates_via_endpoint.py"
readonly RETRIEVAL_MODULE="$PYTHON_ROOT/ishikawa/retrieval.py"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly SCRIPT_174_REPORT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-retrieval-baseline-promotion/retrieval_baseline_promotion_20261022T233825Z_8HJFhu.txt"
readonly BASELINE_RECEIPT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-retrieval-baseline-promotion/retrieval_optimization_baseline_20261022T233825Z_8HJFhu.json"
readonly DESIGN="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-section-page-design/section_page_experiment_design_20261022T214310Z_irpXet.json"
readonly REPRESENTATIVES="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-section-page-experiment/section_page_representatives_20261022T233308Z_6XRxP3.json"
readonly REPRESENTATIVE_EMBEDDINGS="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-section-page-experiment/section_page_representative_embeddings_20261022T233308Z_6XRxP3.json"
readonly RETAINED_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-isolated-publication/retained-derived-artifacts-20261022T204745Z"
readonly NORMALIZED="$RETAINED_ROOT/71/711997caa99c2b92ee555f7ea29e012e2fbb86e39fd65f662cd52e174ec07ead"
readonly ATOMIC_CHUNKS="$RETAINED_ROOT/22/22a4d2694938268462f0c78a79b51771abb48a8e1a23420ec0f443e1e7d8c5fd"
readonly ATOMIC_EMBEDDINGS="$RETAINED_ROOT/ff/ff040e9244a0a9213aec028715d3e52ba5ab7855c324b24c5a4abf8fcc83865f"
readonly PROMOTION_BUNDLE="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-promotion/synthetic_corpus_v2_promotion_candidate_20261022T201026Z"
readonly BODY_CASES="$PHASE_ROOT/reference/ishikawa-synthetic-corpus-v2-body-mrr-cases.json"
readonly HEADER_CASES="$PHASE_ROOT/reference/ishikawa-synthetic-corpus-v2-header-cases.json"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-frozen-optimization-search"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-frozen-optimization-search"
readonly INITDB='/usr/lib/postgresql/16/bin/initdb'
readonly PG_CTL='/usr/lib/postgresql/16/bin/pg_ctl'
readonly TEMPORARY_POSTGRESQL_PORT=65433
readonly NOMIC_HEALTH_URL='http://127.0.0.1:8001/health'
readonly NOMIC_EMBEDDING_URL='http://127.0.0.1:8001/v1/embeddings'
readonly NOMIC_TOKENIZER_URL='http://127.0.0.1:8001/tokenize'

readonly OPTIMIZER_SHA256='8071df71be4210aa26be03e0bd0a695fe088276eba46587279b7ae883148374f'
readonly EXPERIMENT_EVALUATOR_SHA256='c7fc9b1584ef8a4fb811e3e25367c36247abd31981478a6f068a54b6900f5ef0'
readonly CANDIDATE_EVALUATOR_SHA256='8d8507993c3ad266d3c487a71415b6606db73a0916d3920a8c91e03fcd1327bb'
readonly BASE_EVALUATOR_SHA256='eb9eb9f3adbf10ebd3679bdba5a0befb9b2d1ed48957ab00e2b0a88f313680af'
readonly EMBEDDER_SHA256='8f3c23ca30904dfb48a37f3366fd4b7873769bb92a527479fec5696f7fc456dc'
readonly RETRIEVAL_MODULE_SHA256='0307dba6facac397c417b5c9e4345ae1da01c3ce8ea1ba9a9b4a90a5a4353b68'
readonly DECISIONS_SHA256='8b0ce284f90b661a5f48acd275e375b69292fa4035d93e42c2ca7b2b3c9c1013'
readonly SCRIPT_174_REPORT_SHA256='cdf19803004e7997073b4f1d3e8f0c8369e1f28a916cb6fbfe6e2d32180f25cc'
readonly BASELINE_RECEIPT_SHA256='6201b2dabc3112e71ad15e70c73cff6a87ba4e9534a69a0d3a037784b9905d92'
readonly DESIGN_SHA256='d6c282571cdefcf0f24945be97a3d5be32f25ced6382dfcb204c89b3d41dc55a'
readonly REPRESENTATIVES_SHA256='3554061e9a818af0dd948d3112bf9b48196cf6ed4c67db61d4a3b564eb1ae004'
readonly REPRESENTATIVE_EMBEDDINGS_SHA256='13b01e159af4db91cfab3aac601254800ce97313341a8d3fbb6efba606496684'
readonly NORMALIZED_SHA256='711997caa99c2b92ee555f7ea29e012e2fbb86e39fd65f662cd52e174ec07ead'
readonly ATOMIC_CHUNKS_SHA256='22a4d2694938268462f0c78a79b51771abb48a8e1a23420ec0f443e1e7d8c5fd'
readonly ATOMIC_EMBEDDINGS_SHA256='ff040e9244a0a9213aec028715d3e52ba5ab7855c324b24c5a4abf8fcc83865f'
readonly RETAINED_MANIFEST_SHA256='fe7c37741637437539ddec542325bb9506141225414f650b81d3895f7934092b'
readonly PROMOTION_MANIFEST_SHA256='614c4ce64597aeed7d0d03da8dcbef0d59db052dbd3c56092a33e86fd40d42f5'
readonly BODY_CASES_SHA256='47882a93996ef1d8331606c173c85f2076e457c989c9ab3cd6bad31d5ce5613e'
readonly HEADER_CASES_SHA256='a873a61b59de0a8ea082c3fc0c987ab9cf7b97d79ed843832be354af8eae6e2c'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      printf 'reason=argument_invalid\n\nSCRIPT RESULT\nscript_175_frozen_synthetic_corpus_v2_retrieval_optimization_search=blocked\n' >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'reason=mode_invalid\n\nSCRIPT RESULT\nscript_175_frozen_synthetic_corpus_v2_retrieval_optimization_search=blocked\n' >&2
  exit 2
}

for command_name in awk basename bash curl date dirname grep hostname id mkdir \
  mktemp python3 rm sed sha256sum tee timeout tr uname; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'reason=local_command_missing;command=%s\n\nSCRIPT RESULT\nscript_175_frozen_synthetic_corpus_v2_retrieval_optimization_search=blocked\n' \
      "$command_name" >&2
    exit 2
  }
done

check_file() {
  local path="$1" expected_sha256="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] || {
    printf 'reason=%s_unsafe\n\nSCRIPT RESULT\nscript_175_frozen_synthetic_corpus_v2_retrieval_optimization_search=blocked\n' \
      "$label" >&2
    exit 2
  }
  [[ "$(sha256sum "$path" | awk '{print $1}')" == "$expected_sha256" ]] || {
    printf 'reason=%s_identity_changed\n\nSCRIPT RESULT\nscript_175_frozen_synthetic_corpus_v2_retrieval_optimization_search=blocked\n' \
      "$label" >&2
    exit 2
  }
}

check_file "$OPTIMIZER" "$OPTIMIZER_SHA256" optimizer
check_file "$EXPERIMENT_EVALUATOR" "$EXPERIMENT_EVALUATOR_SHA256" experiment_evaluator
check_file "$CANDIDATE_EVALUATOR" "$CANDIDATE_EVALUATOR_SHA256" candidate_evaluator
check_file "$BASE_EVALUATOR" "$BASE_EVALUATOR_SHA256" base_evaluator
check_file "$EMBEDDER" "$EMBEDDER_SHA256" embedder
check_file "$RETRIEVAL_MODULE" "$RETRIEVAL_MODULE_SHA256" retrieval_module
check_file "$DECISIONS" "$DECISIONS_SHA256" decisions
check_file "$SCRIPT_174_REPORT" "$SCRIPT_174_REPORT_SHA256" script_174_report
check_file "$BASELINE_RECEIPT" "$BASELINE_RECEIPT_SHA256" baseline_receipt
check_file "$DESIGN" "$DESIGN_SHA256" design
check_file "$REPRESENTATIVES" "$REPRESENTATIVES_SHA256" representatives
check_file "$REPRESENTATIVE_EMBEDDINGS" "$REPRESENTATIVE_EMBEDDINGS_SHA256" representative_embeddings
check_file "$NORMALIZED" "$NORMALIZED_SHA256" normalized
check_file "$ATOMIC_CHUNKS" "$ATOMIC_CHUNKS_SHA256" atomic_chunks
check_file "$ATOMIC_EMBEDDINGS" "$ATOMIC_EMBEDDINGS_SHA256" atomic_embeddings
check_file "$RETAINED_ROOT/SHA256SUMS" "$RETAINED_MANIFEST_SHA256" retained_manifest
check_file "$PROMOTION_BUNDLE/SHA256SUMS" "$PROMOTION_MANIFEST_SHA256" promotion_manifest
check_file "$BODY_CASES" "$BODY_CASES_SHA256" body_cases
check_file "$HEADER_CASES" "$HEADER_CASES_SHA256" header_cases

(cd -- "$(dirname -- "$BASELINE_RECEIPT")" \
  && sha256sum --quiet -c "$(basename -- "$BASELINE_RECEIPT").sha256") || {
  printf 'reason=baseline_receipt_checksum_manifest_failed\n\nSCRIPT RESULT\nscript_175_frozen_synthetic_corpus_v2_retrieval_optimization_search=blocked\n' >&2
  exit 2
}
(cd -- "$RETAINED_ROOT" && sha256sum --quiet -c SHA256SUMS) || {
  printf 'reason=retained_artifact_manifest_failed\n\nSCRIPT RESULT\nscript_175_frozen_synthetic_corpus_v2_retrieval_optimization_search=blocked\n' >&2
  exit 2
}
(cd -- "$PROMOTION_BUNDLE" && sha256sum --quiet -c SHA256SUMS) || {
  printf 'reason=promotion_manifest_failed\n\nSCRIPT RESULT\nscript_175_frozen_synthetic_corpus_v2_retrieval_optimization_search=blocked\n' >&2
  exit 2
}
grep -Fxq 'script_174_frozen_synthetic_corpus_v2_retrieval_baseline_promotion=pass' \
  "$SCRIPT_174_REPORT" || {
  printf 'reason=script_174_not_clean\n\nSCRIPT RESULT\nscript_175_frozen_synthetic_corpus_v2_retrieval_optimization_search=blocked\n' >&2
  exit 1
}
grep -Fxq 'next_gate=optimize_frozen_synthetic_corpus_v2_retrieval_baseline' \
  "$SCRIPT_174_REPORT" || {
  printf 'reason=script_174_next_gate_invalid\n\nSCRIPT RESULT\nscript_175_frozen_synthetic_corpus_v2_retrieval_optimization_search=blocked\n' >&2
  exit 1
}
grep -Fq '| `V13-31` ' "$DECISIONS" || {
  printf 'reason=decision_v13_31_not_frozen\n\nSCRIPT RESULT\nscript_175_frozen_synthetic_corpus_v2_retrieval_optimization_search=blocked\n' >&2
  exit 1
}
for executable in "$INITDB" "$PG_CTL"; do
  [[ -f "$executable" && ! -L "$executable" && -x "$executable" ]] || {
    printf 'reason=postgresql_16_binary_unsafe\n\nSCRIPT RESULT\nscript_175_frozen_synthetic_corpus_v2_retrieval_optimization_search=blocked\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}"
for python_source in "$OPTIMIZER" "$EXPERIMENT_EVALUATOR" \
  "$CANDIDATE_EVALUATOR" "$BASE_EVALUATOR" "$EMBEDDER"; do
  PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
    'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
    "$python_source"
done
PYTHONDONTWRITEBYTECODE=1 python3 -B "$OPTIMIZER" --self-test \
  | grep -Fxq 'promoted_v2_section_page_optimization_search_self_test=pass'
PYTHONDONTWRITEBYTECODE=1 python3 -B -c 'import psycopg; assert psycopg.__version__'
PYTHONDONTWRITEBYTECODE=1 python3 -B - "$BASELINE_RECEIPT" <<'PY'
import json
import pathlib
import sys

value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert value["artifact_kind"] == "ishikawa_synthetic_corpus_v2_retrieval_optimization_baseline"
assert value["schema_version"] == 1
assert value["state"] == "promoted_frozen_optimization_baseline"
assert value["decision"]["id"] == "V13-31"
assert value["accepted_gate"]["body_mrr_at_20"] == ">=0.890000"
assert value["selected_variant"]["name"] == "section_page_duplicate_canonical"
assert value["selected_variant"]["metrics"]["body"]["mrr_at_20"] == "0.903333"
assert value["selected_variant"]["metrics"]["body"]["relevant_at_5"] == 60
assert value["selected_variant"]["metrics"]["body"]["relevant_at_20"] == 60
assert value["selected_variant"]["metrics"]["header"]["mrr_at_20"] == "1.000000"
assert value["next_gate"] == "optimize_frozen_synthetic_corpus_v2_retrieval_baseline"
assert not any(value["boundaries"].values())
PY

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_frozen_synthetic_corpus_v2_retrieval_optimization_search' \
    "script_sha256=$script_sha256;optimizer_sha256=$OPTIMIZER_SHA256;decision=V13-31" \
    "baseline_receipt_sha256=$BASELINE_RECEIPT_SHA256;baseline_body_mrr_at_20=0.903333" \
    'search_profiles=2646;rrf_constants=6;lexical_weights=7;vector_weights=7;lexical_depths=3;vector_depths=3' \
    'database_contact=false;model_contact=false;credential_read=false;corpus_changed=false;truth_changed=false;production_profile_changed=false;candidate_promoted=false' \
    '' \
    'SCRIPT RESULT' \
    'script_175_frozen_synthetic_corpus_v2_retrieval_optimization_search=pass'
  exit 0
fi

umask 077
mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT" || {
  printf 'reason=local_output_root_creation_failed\n\nSCRIPT RESULT\nscript_175_frozen_synthetic_corpus_v2_retrieval_optimization_search=blocked\n' >&2
  exit 2
}
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" && -w "$REPORT_ROOT" ]] || {
  printf 'reason=report_root_unsafe\n\nSCRIPT RESULT\nscript_175_frozen_synthetic_corpus_v2_retrieval_optimization_search=blocked\n' >&2
  exit 2
}
[[ -d "$ARTIFACT_ROOT" && ! -L "$ARTIFACT_ROOT" && -w "$ARTIFACT_ROOT" ]] || {
  printf 'reason=artifact_root_unsafe\n\nSCRIPT RESULT\nscript_175_frozen_synthetic_corpus_v2_retrieval_optimization_search=blocked\n' >&2
  exit 2
}

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/frozen_v2_optimization_search_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-script-175.XXXXXX)"
suffix="${report_path##*_}"; suffix="${suffix%.txt}"
artifact_path="$ARTIFACT_ROOT/frozen_v2_optimization_search_${timestamp}_${suffix}.json"
artifact_checksum_path="$artifact_path.sha256"
nomic_key=''
private_pg_started=false
failure_reason=''
current_stage='runtime_initialization'
readonly MAIN_BASHPID="$BASHPID"

emit() {
  if ! printf '%s\n' "$1" | tee -a "$report_path"; then
    failure_reason='report_write_failed'
    exit 1
  fi
}
block() { failure_reason="$1"; exit 1; }

stage_failure_reason() {
  local marker="$1" path line candidate reason=''
  shift
  for path in "$@"; do
    [[ -f "$path" && ! -L "$path" ]] || continue
    while IFS= read -r line; do
      [[ "$line" == "$marker=blocked;reason="* ]] || continue
      candidate="${line#*=blocked;reason=}"
      [[ "$candidate" =~ ^[a-z0-9_]+$ ]] || continue
      reason="$candidate"
    done <"$path"
  done
  printf '%s' "$reason"
}

record_unexpected_error() {
  local status="$1"
  if [[ "$BASHPID" == "$MAIN_BASHPID" && -z "$failure_reason" ]]; then
    failure_reason="${current_stage}_unexpected_exit_${status}"
  fi
}

handle_signal() {
  local signal_name="$1" signal_status="$2"
  failure_reason="interrupted_${signal_name}"
  exit "$signal_status"
}

cleanup() {
  local initial_status="$?" result='blocked' optimizer_reason=''
  trap - ERR EXIT HUP INT TERM
  if [[ "$BASHPID" != "$MAIN_BASHPID" ]]; then
    exit "$initial_status"
  fi
  set +e
  unset ISHIKAWA_NOMIC_API_KEY nomic_key
  if (( initial_status != 0 )) && [[ -z "$failure_reason" ]]; then
    optimizer_reason="$(stage_failure_reason \
      promoted_v2_section_page_optimization_search \
      "$work_root/optimizer.stdout" "$work_root/optimizer.stderr")"
    if [[ -n "$optimizer_reason" ]]; then
      failure_reason="optimization_${optimizer_reason}"
    else
      failure_reason="${current_stage}_unexpected_exit_${initial_status}"
    fi
  fi
  if [[ "$private_pg_started" == true \
      && "$work_root" == /tmp/ishikawa-script-175.* ]]; then
    "$PG_CTL" -D "$work_root/postgresql" -m fast -w stop >/dev/null 2>&1 || true
  fi
  [[ "$work_root" == /tmp/ishikawa-script-175.* ]] && rm -rf -- "$work_root"
  if (( initial_status == 0 )); then
    result='pass'
  else
    [[ -n "$failure_reason" ]] \
      || failure_reason="${current_stage}_unexpected_exit_${initial_status}"
    [[ "$artifact_path" == "$ARTIFACT_ROOT"/* ]] \
      && rm -f -- "$artifact_path" "$artifact_checksum_path"
  fi
  {
    printf '\nSCRIPT RESULT\n'
    [[ "$result" == pass ]] || printf 'reason=%s\n' "$failure_reason"
    printf 'script_175_frozen_synthetic_corpus_v2_retrieval_optimization_search=%s\n' "$result"
  } >>"$report_path"
  printf 'local_report=%s\n' "$report_path"
  printf 'local_report_sha256=%s\n' "$(sha256sum "$report_path" | awk '{print $1}')"
  printf '\nSCRIPT RESULT\n'
  [[ "$result" == pass ]] || printf 'reason=%s\n' "$failure_reason"
  printf 'script_175_frozen_synthetic_corpus_v2_retrieval_optimization_search=%s\n' "$result"
  exit "$initial_status"
}
trap cleanup EXIT
trap 'record_unexpected_error "$?"' ERR
trap 'handle_signal hup 129' HUP
trap 'handle_signal int 130' INT
trap 'handle_signal term 143' TERM

read_secret() {
  local value=''
  [[ -r /dev/tty && -w /dev/tty ]] || block interactive_terminal_unavailable
  IFS= read -r -s -p 'Nomic API key: ' value </dev/tty || block secret_entry_failed
  printf '\n' >/dev/tty
  (( ${#value} >= 32 && ${#value} <= 1024 )) || block secret_value_invalid
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || block secret_value_invalid
  nomic_key="$value"
  value=''
}

retain_artifact() {
  local source_path="$1" destination_path="$2" expected_sha256="$3"
  [[ -f "$source_path" && ! -L "$source_path" && -r "$source_path" ]] \
    || block optimization_artifact_source_unsafe
  [[ "$destination_path" == "$ARTIFACT_ROOT"/* ]] \
    || block optimization_artifact_destination_outside_root
  [[ ! -e "$destination_path" && ! -L "$destination_path" ]] \
    || block optimization_artifact_destination_exists
  tee -- "$destination_path" <"$source_path" >/dev/null \
    || block optimization_artifact_copy_failed
  [[ "$(sha256sum "$destination_path" | awk '{print $1}')" == "$expected_sha256" ]] \
    || block optimization_artifact_identity_changed_after_copy
  rm -f -- "$source_path" || block optimization_artifact_source_cleanup_failed
}

current_stage='host_identity'
actual_hostname="$(hostname -s)"
actual_os_id="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"' | awk 'NR == 1')"
actual_os_version="$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"' | awk 'NR == 1')"
actual_architecture="$(uname -m)"
local_user="$(id -un)"
emit 'purpose=search_frozen_synthetic_corpus_v2_retrieval_optimizations'
emit "started_utc=$timestamp;hostname=$actual_hostname;os_version=$actual_os_version;architecture=$actual_architecture"
emit "script_sha256=$script_sha256;optimizer_sha256=$OPTIMIZER_SHA256;baseline_receipt_sha256=$BASELINE_RECEIPT_SHA256"
emit 'authorized_actions=call_existing_loopback_nomic_once_for_fixed_queries_start_private_unix_socket_postgresql_capture_fixed_lanes_search_2646_profiles_offline_retain_local_content_free_evidence'
emit 'non_actions=no_gemma_no_accepted_database_no_database_write_no_ingestion_no_publication_no_black_corpus_no_remote_host_no_service_change_no_package_change_no_truth_change_no_profile_change_no_candidate_promotion'
[[ "$actual_hostname" == 'DankoSurface' && "$actual_os_id" == ubuntu \
    && "$actual_os_version" == '24.04' && "$actual_architecture" == aarch64 ]] \
  || block local_host_identity_mismatch

current_stage='nomic_readiness'
nomic_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
  --connect-timeout 5 --max-time 10 "$NOMIC_HEALTH_URL" 2>/dev/null || true)"
[[ "$nomic_status" == 200 ]] || block nomic_forward_unavailable
emit 'milestone=readiness;state=pass;nomic=pass;gemma_required=false;accepted_postgresql_contact=false'

current_stage='credential_read'
read_secret
emit 'milestone=credential;state=accepted;value_logged=false;value_retained=false'

current_stage='temporary_postgresql_initialization'
postgresql_data="$work_root/postgresql"
postgresql_socket="$work_root/socket"
mkdir -p -- "$postgresql_data" "$postgresql_socket"
"$INITDB" -D "$postgresql_data" --username="$local_user" --encoding=UTF8 \
  --no-locale --auth=trust >"$work_root/initdb.stdout" 2>"$work_root/initdb.stderr" \
  || block temporary_postgresql_initialization_failed
if ! "$PG_CTL" -D "$postgresql_data" -l "$work_root/postgresql.log" \
  -o "-k $postgresql_socket -c listen_addresses='' -p $TEMPORARY_POSTGRESQL_PORT -c fsync=off -c synchronous_commit=off -c full_page_writes=off" \
  -w start >"$work_root/pg-start.stdout" 2>"$work_root/pg-start.stderr"; then
  if "$PG_CTL" -D "$postgresql_data" status >/dev/null 2>&1; then
    private_pg_started=true
  fi
  block temporary_postgresql_start_failed
fi
private_pg_started=true
emit 'milestone=temporary_postgresql;state=pass;tcp_listener=false;corpus_tables=false;accepted_database_contact=false'

current_stage='optimization_search'
observation="$work_root/optimization-search.json"
search_started="$(date +%s)"
emit 'milestone=optimization_search;state=start;profiles=2646;cases=68;nomic_query_passes=1;postgresql_lane_captures=1'
export ISHIKAWA_NOMIC_API_KEY="$nomic_key"
optimizer_status=0
PYTHONDONTWRITEBYTECODE=1 timeout --signal=TERM --kill-after=10s 1800s \
  python3 -B "$OPTIMIZER" --run \
  --python-root "$PYTHON_ROOT" \
  --baseline-receipt "$BASELINE_RECEIPT" --expected-baseline-receipt-sha256 "$BASELINE_RECEIPT_SHA256" \
  --design "$DESIGN" --expected-design-sha256 "$DESIGN_SHA256" \
  --atomic-chunks "$ATOMIC_CHUNKS" --expected-atomic-chunks-sha256 "$ATOMIC_CHUNKS_SHA256" \
  --representatives "$REPRESENTATIVES" --expected-representatives-sha256 "$REPRESENTATIVES_SHA256" \
  --atomic-embeddings "$ATOMIC_EMBEDDINGS" --expected-atomic-embeddings-sha256 "$ATOMIC_EMBEDDINGS_SHA256" \
  --normalized "$NORMALIZED" --expected-normalized-sha256 "$NORMALIZED_SHA256" \
  --promotion-bundle "$PROMOTION_BUNDLE" --expected-promotion-manifest-sha256 "$PROMOTION_MANIFEST_SHA256" \
  --representative-embeddings "$REPRESENTATIVE_EMBEDDINGS" --expected-representative-embeddings-sha256 "$REPRESENTATIVE_EMBEDDINGS_SHA256" \
  --body-cases "$BODY_CASES" --expected-body-cases-sha256 "$BODY_CASES_SHA256" \
  --header-cases "$HEADER_CASES" --expected-header-cases-sha256 "$HEADER_CASES_SHA256" \
  --embedding-url "$NOMIC_EMBEDDING_URL" --tokenizer-url "$NOMIC_TOKENIZER_URL" \
  --postgresql-socket "$postgresql_socket" --postgresql-port "$TEMPORARY_POSTGRESQL_PORT" \
  --postgresql-user "$local_user" --output "$observation" \
  >"$work_root/optimizer.stdout" 2>"$work_root/optimizer.stderr" \
  || optimizer_status="$?"
unset ISHIKAWA_NOMIC_API_KEY
nomic_key=''
if (( optimizer_status != 0 )); then
  if (( optimizer_status == 124 || optimizer_status == 137 )); then
    block optimization_search_timeout
  fi
  optimizer_reason="$(stage_failure_reason \
    promoted_v2_section_page_optimization_search \
    "$work_root/optimizer.stdout" "$work_root/optimizer.stderr")"
  [[ -z "$optimizer_reason" ]] || block "optimization_${optimizer_reason}"
  block optimization_search_unclassified_failure
fi
grep -Fxq 'promoted_v2_section_page_optimization_search=pass' \
  "$work_root/optimizer.stdout" || block optimization_search_pass_marker_absent
while IFS= read -r line; do emit "$line"; done <"$work_root/optimizer.stdout"
observation_sha256="$(sha256sum "$observation" | awk '{print $1}')"
emit "milestone=optimization_search;state=pass;elapsed_seconds=$(( $(date +%s) - search_started ));artifact_sha256=$observation_sha256"

current_stage='observation_validation'
validation_summary="$work_root/validation-summary.txt"
PYTHONDONTWRITEBYTECODE=1 python3 -B - "$observation" >"$validation_summary" <<'PY'
import json
import pathlib
import sys
from fractions import Fraction

value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert value["artifact_kind"] == "ishikawa_promoted_v2_section_page_optimization_search"
assert value["schema_version"] == 1
assert value["profile_counts"]["evaluated"] == 2646
assert value["profile_counts"]["acceptance_gate"] >= 1
assert value["deterministic_finalist_replay"] is True
assert value["baseline_replay"]["profile"] == {
    "exact_weight": 1,
    "lexical_depth": 20,
    "lexical_weight": 1,
    "rrf_constant": 60,
    "vector_depth": 20,
    "vector_weight": 4,
}
baseline = value["baseline_replay"]["body_metrics"]
best = value["best_observed_profile"]["body_metrics"]
assert baseline["mrr_at_20"] == "0.903333"
assert baseline["relevant_at_5"] == 60
assert baseline["relevant_at_20"] == 60
assert value["best_observed_profile"]["acceptance_gate_met"] is True
assert Fraction(best["mrr_fraction_numerator"], best["mrr_fraction_denominator"]) >= Fraction(
    baseline["mrr_fraction_numerator"], baseline["mrr_fraction_denominator"]
)
assert best["relevant_at_20"] == 60
assert best["required_evidence_matched_at_20"] == 60
assert value["best_observed_profile"]["header_metrics"]["mrr_at_20"] == "1.000000"
assert value["best_observed_profile"]["header_metrics"]["required_evidence_matched_at_20"] == 11
assert value["boundaries"] == {
    "accepted_database_contact": False,
    "black_corpus_access": False,
    "candidate_promoted": False,
    "corpus_changed": False,
    "database_tables_read": False,
    "database_write": False,
    "gemma_contact": False,
    "nomic_contact": True,
    "private_temporary_postgresql": True,
    "production_profile_changed": False,
    "truth_changed": False,
}
assert value["next_gate"] == "review_promoted_baseline_optimization_finalists_before_profile_freeze"
print("best_profile=" + json.dumps(value["best_observed_profile"]["profile"], sort_keys=True, separators=(",", ":")))
print("best_body_mrr_at_20=" + best["mrr_at_20"])
print("acceptance_gate_profiles=" + str(value["profile_counts"]["acceptance_gate"]))
print("acceptance_gate_without_body_regressions=" + str(value["profile_counts"]["acceptance_gate_without_body_regressions"]))
print("next_gate=" + value["next_gate"])
PY
while IFS= read -r line; do emit "$line"; done <"$validation_summary"

current_stage='temporary_postgresql_cleanup'
"$PG_CTL" -D "$postgresql_data" -m fast -w stop \
  >"$work_root/pg-stop.stdout" 2>"$work_root/pg-stop.stderr" \
  || block temporary_postgresql_stop_failed
private_pg_started=false
emit 'milestone=temporary_postgresql_cleanup;state=pass;cluster_retained=false;listener_retained=false'

current_stage='artifact_retention'
retain_artifact "$observation" "$artifact_path" "$observation_sha256"
if ! printf '%s  %s\n' "$observation_sha256" "$(basename -- "$artifact_path")" \
    >"$artifact_checksum_path"; then
  block optimization_artifact_checksum_manifest_write_failed
fi
if ! (trap - ERR EXIT HUP INT TERM; cd -- "$ARTIFACT_ROOT" \
    && sha256sum --quiet -c "$(basename -- "$artifact_checksum_path")"); then
  block optimization_artifact_checksum_manifest_failed
fi
emit 'milestone=artifact_retention;state=pass;artifacts=1;checksum_manifests=1;filesystem_permissions=mount_managed;umask=077'
emit "optimization_observation=$artifact_path;optimization_observation_sha256=$observation_sha256"
emit 'database_write=false;accepted_database_contact=false;gemma_contact=false;corpus_changed=false;truth_changed=false;profile_changed=false;candidate_promoted=false;credentials_retained=false'
current_stage='complete'
