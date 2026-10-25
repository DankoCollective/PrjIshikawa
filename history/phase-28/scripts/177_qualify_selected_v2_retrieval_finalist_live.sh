#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify Script 176's selected retrieval finalist through one warm-up and
#   five fresh Nomic/PostgreSQL runs with stage-level latency measurement.
#
# Boundaries:
#   Existing loopback Nomic only, one disposable Unix-socket PostgreSQL
#   cluster, no Gemma, no accepted database, and no corpus, truth, release, or
#   production-profile mutation. Passing does not freeze or promote a profile.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/177_qualify_selected_v2_retrieval_finalist_live.sh --run

usage() {
  sed -n '3,15p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Execute one warm-up and five measured live runs.' \
    '  --validate-only Validate frozen inputs and local contracts only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PYTHON_ROOT="$PHASE_ROOT/Ishikawa/application/python"
readonly QUALIFIER="$SCRIPT_DIR/qualify_selected_v2_retrieval_finalist.py"
readonly EXPERIMENT_EVALUATOR="$SCRIPT_DIR/measure_published_v2_section_page_experiment.py"
readonly CANDIDATE_EVALUATOR="$SCRIPT_DIR/measure_synthetic_corpus_v2_candidate_profile.py"
readonly BASE_EVALUATOR="$SCRIPT_DIR/measure_synthetic_corpus_v2_without_ingestion.py"
readonly EMBEDDER="$SCRIPT_DIR/embed_document_candidates_via_endpoint.py"
readonly RETRIEVAL_MODULE="$PYTHON_ROOT/ishikawa/retrieval.py"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly SCRIPT_176_REPORT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-finalist-review/finalist_review_20261022T234902Z_xpGoA6.txt"
readonly FINALIST_REVIEW="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-finalist-review/finalist_review_20261022T234902Z_xpGoA6.json"
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
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-finalist-live-qualification"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-finalist-live-qualification"
readonly INITDB='/usr/lib/postgresql/16/bin/initdb'
readonly PG_CTL='/usr/lib/postgresql/16/bin/pg_ctl'
readonly TEMPORARY_POSTGRESQL_PORT=65434
readonly NOMIC_HEALTH_URL='http://127.0.0.1:8001/health'
readonly NOMIC_EMBEDDING_URL='http://127.0.0.1:8001/v1/embeddings'
readonly NOMIC_TOKENIZER_URL='http://127.0.0.1:8001/tokenize'

readonly QUALIFIER_SHA256='c5b9834a13955ecb7235ecbb0c5da3c4a2e3a3a3e6b8837f87366c958707b594'
readonly EXPERIMENT_EVALUATOR_SHA256='c7fc9b1584ef8a4fb811e3e25367c36247abd31981478a6f068a54b6900f5ef0'
readonly CANDIDATE_EVALUATOR_SHA256='8d8507993c3ad266d3c487a71415b6606db73a0916d3920a8c91e03fcd1327bb'
readonly BASE_EVALUATOR_SHA256='eb9eb9f3adbf10ebd3679bdba5a0befb9b2d1ed48957ab00e2b0a88f313680af'
readonly EMBEDDER_SHA256='8f3c23ca30904dfb48a37f3366fd4b7873769bb92a527479fec5696f7fc456dc'
readonly RETRIEVAL_MODULE_SHA256='0307dba6facac397c417b5c9e4345ae1da01c3ce8ea1ba9a9b4a90a5a4353b68'
readonly DECISIONS_SHA256='8b0ce284f90b661a5f48acd275e375b69292fa4035d93e42c2ca7b2b3c9c1013'
readonly SCRIPT_176_REPORT_SHA256='6168bdd2f79bfccd3ce69dad3a6eb06192d72a8a407c12ed067509afd6bf45b0'
readonly FINALIST_REVIEW_SHA256='5aa174419d105ba98326d91c5fa370151ba7962c43a502a97357f49ee6e16184'
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
      printf 'reason=argument_invalid\n\nSCRIPT RESULT\nscript_177_selected_v2_retrieval_finalist_live_qualification=blocked\n' >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'reason=mode_invalid\n\nSCRIPT RESULT\nscript_177_selected_v2_retrieval_finalist_live_qualification=blocked\n' >&2
  exit 2
}

for command_name in awk basename bash curl date dirname grep hostname id mkdir \
  mktemp python3 rm sed sha256sum tee timeout tr uname; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'reason=local_command_missing;command=%s\n\nSCRIPT RESULT\nscript_177_selected_v2_retrieval_finalist_live_qualification=blocked\n' \
      "$command_name" >&2
    exit 2
  }
done

check_file() {
  local path="$1" expected_sha256="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] || {
    printf 'reason=%s_unsafe\n\nSCRIPT RESULT\nscript_177_selected_v2_retrieval_finalist_live_qualification=blocked\n' \
      "$label" >&2
    exit 2
  }
  [[ "$(sha256sum "$path" | awk '{print $1}')" == "$expected_sha256" ]] || {
    printf 'reason=%s_identity_changed\n\nSCRIPT RESULT\nscript_177_selected_v2_retrieval_finalist_live_qualification=blocked\n' \
      "$label" >&2
    exit 2
  }
}

check_file "$QUALIFIER" "$QUALIFIER_SHA256" qualifier
check_file "$EXPERIMENT_EVALUATOR" "$EXPERIMENT_EVALUATOR_SHA256" experiment_evaluator
check_file "$CANDIDATE_EVALUATOR" "$CANDIDATE_EVALUATOR_SHA256" candidate_evaluator
check_file "$BASE_EVALUATOR" "$BASE_EVALUATOR_SHA256" base_evaluator
check_file "$EMBEDDER" "$EMBEDDER_SHA256" embedder
check_file "$RETRIEVAL_MODULE" "$RETRIEVAL_MODULE_SHA256" retrieval_module
check_file "$DECISIONS" "$DECISIONS_SHA256" decisions
check_file "$SCRIPT_176_REPORT" "$SCRIPT_176_REPORT_SHA256" script_176_report
check_file "$FINALIST_REVIEW" "$FINALIST_REVIEW_SHA256" finalist_review
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

for artifact in "$FINALIST_REVIEW" "$BASELINE_RECEIPT"; do
  (cd -- "$(dirname -- "$artifact")" \
    && sha256sum --quiet -c "$(basename -- "$artifact").sha256") || {
    printf 'reason=input_checksum_manifest_failed\n\nSCRIPT RESULT\nscript_177_selected_v2_retrieval_finalist_live_qualification=blocked\n' >&2
    exit 2
  }
done
(cd -- "$RETAINED_ROOT" && sha256sum --quiet -c SHA256SUMS) || {
  printf 'reason=retained_artifact_manifest_failed\n\nSCRIPT RESULT\nscript_177_selected_v2_retrieval_finalist_live_qualification=blocked\n' >&2
  exit 2
}
(cd -- "$PROMOTION_BUNDLE" && sha256sum --quiet -c SHA256SUMS) || {
  printf 'reason=promotion_manifest_failed\n\nSCRIPT RESULT\nscript_177_selected_v2_retrieval_finalist_live_qualification=blocked\n' >&2
  exit 2
}
grep -Fxq 'script_176_frozen_v2_retrieval_optimization_finalist_review=pass' \
  "$SCRIPT_176_REPORT" || {
  printf 'reason=script_176_not_clean\n\nSCRIPT RESULT\nscript_177_selected_v2_retrieval_finalist_live_qualification=blocked\n' >&2
  exit 1
}
grep -Fxq 'next_gate=execute_repeated_live_qualification_of_selected_v2_retrieval_finalist' \
  "$SCRIPT_176_REPORT" || {
  printf 'reason=script_176_next_gate_invalid\n\nSCRIPT RESULT\nscript_177_selected_v2_retrieval_finalist_live_qualification=blocked\n' >&2
  exit 1
}
grep -Fq '| `V13-31` ' "$DECISIONS" || {
  printf 'reason=decision_v13_31_not_frozen\n\nSCRIPT RESULT\nscript_177_selected_v2_retrieval_finalist_live_qualification=blocked\n' >&2
  exit 1
}
for executable in "$INITDB" "$PG_CTL"; do
  [[ -f "$executable" && ! -L "$executable" && -x "$executable" ]] || {
    printf 'reason=postgresql_16_binary_unsafe\n\nSCRIPT RESULT\nscript_177_selected_v2_retrieval_finalist_live_qualification=blocked\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}"
for python_source in "$QUALIFIER" "$EXPERIMENT_EVALUATOR" \
  "$CANDIDATE_EVALUATOR" "$BASE_EVALUATOR" "$EMBEDDER"; do
  PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
    'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
    "$python_source"
done
PYTHONDONTWRITEBYTECODE=1 python3 -B "$QUALIFIER" --self-test \
  | grep -Fxq 'selected_v2_retrieval_finalist_live_qualification_self_test=pass'
PYTHONDONTWRITEBYTECODE=1 python3 -B -c 'import psycopg; assert psycopg.__version__'
PYTHONDONTWRITEBYTECODE=1 python3 -B - "$FINALIST_REVIEW" <<'PY'
import json
import pathlib
import sys

value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert value["artifact_kind"] == "ishikawa_synthetic_corpus_v2_optimization_finalist_review"
assert value["schema_version"] == 1
assert value["live_qualification_design"]["repeated_warm_runs"] == 5
assert value["live_qualification_design"]["candidate_profile"] == {
    "exact_weight": 1,
    "lexical_depth": 20,
    "lexical_weight": 2,
    "rrf_constant": 60,
    "vector_depth": 20,
    "vector_weight": 4,
}
assert value["next_gate"] == "execute_repeated_live_qualification_of_selected_v2_retrieval_finalist"
assert value["decision"]["profile_freeze_authorized"] is False
assert not any(value["boundaries"].values())
PY

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_selected_v2_retrieval_finalist_live_qualification' \
    "script_sha256=$script_sha256;qualifier_sha256=$QUALIFIER_SHA256;decision=V13-31" \
    "finalist_review_sha256=$FINALIST_REVIEW_SHA256;baseline_receipt_sha256=$BASELINE_RECEIPT_SHA256" \
    'warmup_runs=1;measured_runs=5;cases_per_run=68;selected_delta=lexical_weight_1_to_2' \
    'database_contact=false;model_contact=false;credential_read=false;corpus_changed=false;truth_changed=false;production_profile_changed=false;candidate_promoted=false' \
    '' \
    'SCRIPT RESULT' \
    'script_177_selected_v2_retrieval_finalist_live_qualification=pass'
  exit 0
fi

umask 077
mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT" || {
  printf 'reason=local_output_root_creation_failed\n\nSCRIPT RESULT\nscript_177_selected_v2_retrieval_finalist_live_qualification=blocked\n' >&2
  exit 2
}
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" && -w "$REPORT_ROOT" ]] || {
  printf 'reason=report_root_unsafe\n\nSCRIPT RESULT\nscript_177_selected_v2_retrieval_finalist_live_qualification=blocked\n' >&2
  exit 2
}
[[ -d "$ARTIFACT_ROOT" && ! -L "$ARTIFACT_ROOT" && -w "$ARTIFACT_ROOT" ]] || {
  printf 'reason=artifact_root_unsafe\n\nSCRIPT RESULT\nscript_177_selected_v2_retrieval_finalist_live_qualification=blocked\n' >&2
  exit 2
}

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/finalist_live_qualification_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-script-177.XXXXXX)"
suffix="${report_path##*_}"; suffix="${suffix%.txt}"
artifact_path="$ARTIFACT_ROOT/finalist_live_qualification_${timestamp}_${suffix}.json"
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
  local initial_status="$?" result='blocked' qualifier_reason=''
  trap - ERR EXIT HUP INT TERM
  if [[ "$BASHPID" != "$MAIN_BASHPID" ]]; then
    exit "$initial_status"
  fi
  set +e
  unset ISHIKAWA_NOMIC_API_KEY nomic_key
  if (( initial_status != 0 )) && [[ -z "$failure_reason" ]]; then
    qualifier_reason="$(stage_failure_reason \
      selected_v2_retrieval_finalist_live_qualification \
      "$work_root/qualifier.stdout" "$work_root/qualifier.stderr")"
    if [[ -n "$qualifier_reason" ]]; then
      failure_reason="qualification_${qualifier_reason}"
    else
      failure_reason="${current_stage}_unexpected_exit_${initial_status}"
    fi
  fi
  if [[ "$private_pg_started" == true \
      && "$work_root" == /tmp/ishikawa-script-177.* ]]; then
    "$PG_CTL" -D "$work_root/postgresql" -m fast -w stop >/dev/null 2>&1 || true
  fi
  [[ "$work_root" == /tmp/ishikawa-script-177.* ]] && rm -rf -- "$work_root"
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
    printf 'script_177_selected_v2_retrieval_finalist_live_qualification=%s\n' "$result"
  } >>"$report_path"
  printf 'local_report=%s\n' "$report_path"
  printf 'local_report_sha256=%s\n' "$(sha256sum "$report_path" | awk '{print $1}')"
  printf '\nSCRIPT RESULT\n'
  [[ "$result" == pass ]] || printf 'reason=%s\n' "$failure_reason"
  printf 'script_177_selected_v2_retrieval_finalist_live_qualification=%s\n' "$result"
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
    || block qualification_artifact_source_unsafe
  [[ "$destination_path" == "$ARTIFACT_ROOT"/* ]] \
    || block qualification_artifact_destination_outside_root
  [[ ! -e "$destination_path" && ! -L "$destination_path" ]] \
    || block qualification_artifact_destination_exists
  tee -- "$destination_path" <"$source_path" >/dev/null \
    || block qualification_artifact_copy_failed
  [[ "$(sha256sum "$destination_path" | awk '{print $1}')" == "$expected_sha256" ]] \
    || block qualification_artifact_identity_changed_after_copy
  rm -f -- "$source_path" || block qualification_artifact_source_cleanup_failed
}

current_stage='host_identity'
actual_hostname="$(hostname -s)"
actual_os_id="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"' | awk 'NR == 1')"
actual_os_version="$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"' | awk 'NR == 1')"
actual_architecture="$(uname -m)"
local_user="$(id -un)"
emit 'purpose=qualify_selected_v2_retrieval_finalist_live'
emit "started_utc=$timestamp;hostname=$actual_hostname;os_version=$actual_os_version;architecture=$actual_architecture"
emit "script_sha256=$script_sha256;qualifier_sha256=$QUALIFIER_SHA256;finalist_review_sha256=$FINALIST_REVIEW_SHA256"
emit 'authorized_actions=call_existing_loopback_nomic_start_private_unix_socket_postgresql_execute_one_warmup_and_five_measured_runs_compare_baseline_and_selected_candidate_record_stage_latency_retain_local_content_free_evidence'
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

current_stage='live_qualification'
observation="$work_root/live-qualification.json"
qualification_started="$(date +%s)"
emit 'milestone=live_qualification;state=start;warmup_runs=1;measured_runs=5;cases_per_run=68;fresh_nomic_and_lexical_each_run=true'
export ISHIKAWA_NOMIC_API_KEY="$nomic_key"
qualifier_status=0
PYTHONDONTWRITEBYTECODE=1 timeout --signal=TERM --kill-after=10s 1800s \
  python3 -B "$QUALIFIER" --run \
  --python-root "$PYTHON_ROOT" \
  --review "$FINALIST_REVIEW" --expected-review-sha256 "$FINALIST_REVIEW_SHA256" \
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
  >"$work_root/qualifier.stdout" 2>"$work_root/qualifier.stderr" \
  || qualifier_status="$?"
unset ISHIKAWA_NOMIC_API_KEY
nomic_key=''
if (( qualifier_status != 0 )); then
  if (( qualifier_status == 124 || qualifier_status == 137 )); then
    block live_qualification_timeout
  fi
  qualifier_reason="$(stage_failure_reason \
    selected_v2_retrieval_finalist_live_qualification \
    "$work_root/qualifier.stdout" "$work_root/qualifier.stderr")"
  [[ -z "$qualifier_reason" ]] || block "qualification_${qualifier_reason}"
  block live_qualification_unclassified_failure
fi
grep -Fxq 'selected_v2_retrieval_finalist_live_qualification=pass' \
  "$work_root/qualifier.stdout" || block live_qualification_pass_marker_absent
while IFS= read -r line; do emit "$line"; done <"$work_root/qualifier.stdout"
observation_sha256="$(sha256sum "$observation" | awk '{print $1}')"
emit "milestone=live_qualification;state=pass;elapsed_seconds=$(( $(date +%s) - qualification_started ));artifact_sha256=$observation_sha256"

current_stage='observation_validation'
validation_summary="$work_root/validation-summary.txt"
PYTHONDONTWRITEBYTECODE=1 python3 -B - "$observation" >"$validation_summary" <<'PY'
import json
import pathlib
import sys

value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert value["artifact_kind"] == "ishikawa_selected_v2_retrieval_finalist_live_qualification"
assert value["schema_version"] == 1
assert value["qualification_gate_met"] is True
assert value["deterministic_across_measured_runs"] is True
assert value["profile_freeze_authorized"] is False
assert value["inventory"] == {
    "atomic_candidates": 139,
    "cases_per_run": 68,
    "measured_runs": 5,
    "query_embedding_tokens_per_run": 1204,
    "section_page_representatives": 29,
    "warmup_runs": 1,
}
assert len(value["runs"]) == 5
assert all(run["candidate_gate_met"] for run in value["runs"])
assert all(run["candidate_metrics"]["body"]["mrr_at_20"] == "0.915833" for run in value["runs"])
assert all(run["baseline_metrics"]["body"]["mrr_at_20"] == "0.903333" for run in value["runs"])
assert all(run["improved_body_case_ids"] == ["E-033", "E-051"] for run in value["runs"])
assert all(run["regressed_body_case_ids"] == [] for run in value["runs"])
assert value["candidate_profile"]["lexical_weight"] == 2
assert value["promoted_baseline_profile"]["lexical_weight"] == 1
assert value["next_gate"] == "review_repeated_live_finalist_qualification_before_profile_freeze"
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
print("candidate_total_retrieval_median_ms=" + value["latency"]["candidate_total_retrieval"]["median_ms"])
print("candidate_total_retrieval_p95_ms=" + value["latency"]["candidate_total_retrieval"]["p95_ms"])
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
  block qualification_artifact_checksum_manifest_write_failed
fi
if ! (trap - ERR EXIT HUP INT TERM; cd -- "$ARTIFACT_ROOT" \
    && sha256sum --quiet -c "$(basename -- "$artifact_checksum_path")"); then
  block qualification_artifact_checksum_manifest_failed
fi
emit 'milestone=artifact_retention;state=pass;artifacts=1;checksum_manifests=1;filesystem_permissions=mount_managed;umask=077'
emit "qualification_observation=$artifact_path;qualification_observation_sha256=$observation_sha256"
emit 'database_write=false;accepted_database_contact=false;gemma_contact=false;corpus_changed=false;truth_changed=false;profile_changed=false;candidate_promoted=false;credentials_retained=false'
current_stage='complete'
