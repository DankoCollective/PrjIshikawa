#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Run the frozen 60-body/8-header retrieval gate from the implemented
#   V13-32 chunking, representation, fusion, collapse, and expansion source.
#   Ranking metrics are measured at collapsed selection; expansion is checked
#   separately as authoritative evidence hydration and is not reranking.
#
# Boundaries:
#   Existing loopback Nomic and one disposable Unix-socket PostgreSQL cluster
#   only. No Gemma, accepted database, corpus, truth, profile, package, release,
#   black-corpus, remote-host, service, or org-lab state is read or changed.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/180_qualify_implemented_v13_32_retrieval.sh --run

usage() {
  sed -n '3,14p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Execute the fresh implemented-source retrieval gate.' \
    '  --validate-only Validate frozen inputs and local contracts only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly QUALIFIER="$SCRIPT_DIR/qualify_implemented_v13_32_retrieval.py"
readonly EMBEDDER="$SCRIPT_DIR/embed_document_candidates_via_endpoint.py"
readonly BASE_EVALUATOR="$SCRIPT_DIR/measure_synthetic_corpus_v2_without_ingestion.py"
readonly CANDIDATE_EVALUATOR="$SCRIPT_DIR/measure_synthetic_corpus_v2_candidate_profile.py"
readonly EXPERIMENT_EVALUATOR="$SCRIPT_DIR/measure_published_v2_section_page_experiment.py"
readonly CHUNKING="$PYTHON_ROOT/ishikawa/chunking.py"
readonly METHOD_PROFILE_MODULE="$PYTHON_ROOT/ishikawa/method_profile.py"
readonly RETRIEVAL="$PYTHON_ROOT/ishikawa/retrieval.py"
readonly METHOD_PROFILE="$PRODUCT_ROOT/config/templates/method_profile.yaml"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly SCRIPT_179_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.3-v13-32-application-implementation/v13_32_application_implementation_20261023T002814Z_aNSicw.txt"
readonly PRIOR_QUALIFICATION="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-finalist-live-qualification/finalist_live_qualification_20261022T235752Z_FLhBmy.json"
readonly NORMALIZED="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-isolated-publication/retained-derived-artifacts-20261022T204745Z/71/711997caa99c2b92ee555f7ea29e012e2fbb86e39fd65f662cd52e174ec07ead"
readonly BODY_CASES="$PHASE_ROOT/reference/ishikawa-synthetic-corpus-v2-body-mrr-cases.json"
readonly HEADER_CASES="$PHASE_ROOT/reference/ishikawa-synthetic-corpus-v2-header-cases.json"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.3-v13-32-implemented-retrieval"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v1.3-v13-32-implemented-retrieval"
readonly INITDB='/usr/lib/postgresql/16/bin/initdb'
readonly PG_CTL='/usr/lib/postgresql/16/bin/pg_ctl'
readonly TEMPORARY_POSTGRESQL_PORT=65436
readonly NOMIC_HEALTH_URL='http://127.0.0.1:8001/health'
readonly NOMIC_EMBEDDING_URL='http://127.0.0.1:8001/v1/embeddings'
readonly NOMIC_TOKENIZER_URL='http://127.0.0.1:8001/tokenize'

readonly QUALIFIER_SHA256='7dc02ab6dbb0315000a688102209f4d9fb9e542794c4bd91e02afe3e33207c7e'
readonly EMBEDDER_SHA256='8f3c23ca30904dfb48a37f3366fd4b7873769bb92a527479fec5696f7fc456dc'
readonly BASE_EVALUATOR_SHA256='eb9eb9f3adbf10ebd3679bdba5a0befb9b2d1ed48957ab00e2b0a88f313680af'
readonly CANDIDATE_EVALUATOR_SHA256='8d8507993c3ad266d3c487a71415b6606db73a0916d3920a8c91e03fcd1327bb'
readonly EXPERIMENT_EVALUATOR_SHA256='c7fc9b1584ef8a4fb811e3e25367c36247abd31981478a6f068a54b6900f5ef0'
readonly CHUNKING_SHA256='551b8c53d38c8a96584b0919cb667318f33a7845364938065cc59209c2fb9308'
readonly METHOD_PROFILE_MODULE_SHA256='2ca2eb71396b28941f3d1e16930a1ff82bfd4f8df8a9bd18ebdcc89c1bb5a3d9'
readonly RETRIEVAL_SHA256='1750e7343ab90a719a5692d3b4cf1a48eb2e0d72c835bd9223fdc2687b748c73'
readonly METHOD_PROFILE_SHA256='1219e0176535ba07ea18936ee7d528dcb5409781f3a374fc9147dbec4d9674b6'
readonly DECISIONS_SHA256='dbcd6f38a17a312e2480a9a002f55237b64c58fdc5fbfbb6e854874825e7cdeb'
readonly SCRIPT_179_REPORT_SHA256='f98927ac0258ca982a9cd44bcbbb91e3e4026f66d3f2cdb1778f10570ea78f6a'
readonly PRIOR_QUALIFICATION_SHA256='a1158ea7b85532bc3c8bebaa7c7f9ef820ef4aee703d50aee79a7b363391c801'
readonly NORMALIZED_SHA256='711997caa99c2b92ee555f7ea29e012e2fbb86e39fd65f662cd52e174ec07ead'
readonly BODY_CASES_SHA256='47882a93996ef1d8331606c173c85f2076e457c989c9ab3cd6bad31d5ce5613e'
readonly HEADER_CASES_SHA256='a873a61b59de0a8ea082c3fc0c987ab9cf7b97d79ed843832be354af8eae6e2c'
readonly EXPECTED_CANDIDATE_ID='bf732e402004d70b0aa3318e179fe1a1e14d0bd4a70aaa2b4d71528088b7d518'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      printf 'reason=argument_invalid\n\nSCRIPT RESULT\nscript_180_implemented_v13_32_retrieval_gate=blocked\n' >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'reason=mode_invalid\n\nSCRIPT RESULT\nscript_180_implemented_v13_32_retrieval_gate=blocked\n' >&2
  exit 2
}

preflight_block() {
  printf 'reason=%s\n\nSCRIPT RESULT\nscript_180_implemented_v13_32_retrieval_gate=blocked\n' "$1" >&2
  exit "${2:-2}"
}

for command_name in awk basename bash curl date dirname grep hostname id mkdir \
  mktemp python3 rm sed sha256sum tail tee timeout tr uname; do
  command -v "$command_name" >/dev/null 2>&1 \
    || preflight_block "local_command_missing_$command_name"
done

check_file() {
  local path="$1" expected="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] \
    || preflight_block "${label}_unsafe"
  [[ "$(sha256sum "$path" | awk '{print $1}')" == "$expected" ]] \
    || preflight_block "${label}_identity_changed"
}

check_file "$QUALIFIER" "$QUALIFIER_SHA256" qualifier
check_file "$EMBEDDER" "$EMBEDDER_SHA256" embedder
check_file "$BASE_EVALUATOR" "$BASE_EVALUATOR_SHA256" base_evaluator
check_file "$CANDIDATE_EVALUATOR" "$CANDIDATE_EVALUATOR_SHA256" candidate_evaluator
check_file "$EXPERIMENT_EVALUATOR" "$EXPERIMENT_EVALUATOR_SHA256" experiment_evaluator
check_file "$CHUNKING" "$CHUNKING_SHA256" chunking
check_file "$METHOD_PROFILE_MODULE" "$METHOD_PROFILE_MODULE_SHA256" method_profile_module
check_file "$RETRIEVAL" "$RETRIEVAL_SHA256" retrieval
check_file "$METHOD_PROFILE" "$METHOD_PROFILE_SHA256" method_profile
check_file "$DECISIONS" "$DECISIONS_SHA256" decisions
check_file "$SCRIPT_179_REPORT" "$SCRIPT_179_REPORT_SHA256" script_179_report
check_file "$PRIOR_QUALIFICATION" "$PRIOR_QUALIFICATION_SHA256" prior_qualification
check_file "$NORMALIZED" "$NORMALIZED_SHA256" normalized
check_file "$BODY_CASES" "$BODY_CASES_SHA256" body_cases
check_file "$HEADER_CASES" "$HEADER_CASES_SHA256" header_cases

grep -Fxq 'script_179_v13_32_application_implementation=pass' "$SCRIPT_179_REPORT" \
  || preflight_block script_179_not_clean 1
grep -Fxq 'next_gate=repeat_60_body_and_8_header_retrieval_gate_from_implemented_source' \
  "$SCRIPT_179_REPORT" || preflight_block script_179_next_gate_invalid 1
grep -Eq "^\| \`V13-32\` \|.*${EXPECTED_CANDIDATE_ID}.*\| FROZEN \|$" "$DECISIONS" \
  || preflight_block v13_32_freeze_record_invalid 1
for executable in "$INITDB" "$PG_CTL"; do
  [[ -f "$executable" && ! -L "$executable" && -x "$executable" ]] \
    || preflight_block postgresql_16_binary_unsafe
done

bash -n "${BASH_SOURCE[0]}"
for python_source in "$QUALIFIER" "$EMBEDDER" "$BASE_EVALUATOR" \
  "$CANDIDATE_EVALUATOR" "$EXPERIMENT_EVALUATOR"; do
  PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
    'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
    "$python_source"
done
PYTHONDONTWRITEBYTECODE=1 python3 -B "$QUALIFIER" --self-test \
  | grep -Fxq 'implemented_v13_32_retrieval_qualification_self_test=pass'
PYTHONDONTWRITEBYTECODE=1 python3 -B -c 'import psycopg; assert psycopg.__version__'

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_implemented_v13_32_retrieval_gate' \
    "script_sha256=$script_sha256;qualifier_sha256=$QUALIFIER_SHA256;decision=V13-32" \
    "candidate_identity=$EXPECTED_CANDIDATE_ID;cases=68;body_cases=60;header_cases=8" \
    'fresh_candidate_embeddings=true;fresh_query_embeddings=true;implemented_collapse_and_expansion=true' \
    'database_contact=false;model_contact=false;credential_read=false;corpus_changed=false;truth_changed=false;profile_changed=false;release_changed=false' \
    '' \
    'SCRIPT RESULT' \
    'script_180_implemented_v13_32_retrieval_gate=pass'
  exit 0
fi

umask 077
mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT" \
  || preflight_block local_output_root_creation_failed
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" && -w "$REPORT_ROOT" ]] \
  || preflight_block report_root_unsafe
[[ -d "$ARTIFACT_ROOT" && ! -L "$ARTIFACT_ROOT" && -w "$ARTIFACT_ROOT" ]] \
  || preflight_block artifact_root_unsafe

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/implemented_retrieval_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-script-180.XXXXXX)"
suffix="${report_path##*_}"; suffix="${suffix%.txt}"
artifact_path="$ARTIFACT_ROOT/implemented_retrieval_${timestamp}_${suffix}.json"
artifact_checksum_path="$artifact_path.sha256"
nomic_key=''
postgresql_started=false
failure_observation_retained=false
failure_reason=''
current_stage='runtime_initialization'
readonly MAIN_BASHPID="$BASHPID"

emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
block() { failure_reason="$1"; exit "${2:-1}"; }
record_unexpected_error() {
  local status="$1"
  if [[ "$BASHPID" == "$MAIN_BASHPID" && -z "$failure_reason" ]]; then
    failure_reason="${current_stage}_unexpected_exit_${status}"
  fi
}
handle_signal() { failure_reason="interrupted_$1"; exit "$2"; }
cleanup() {
  local status="$?" result=blocked
  trap - ERR EXIT HUP INT TERM
  set +e
  unset ISHIKAWA_NOMIC_API_KEY nomic_key
  if [[ "$postgresql_started" == true && "$work_root" == /tmp/ishikawa-script-180.* ]]; then
    "$PG_CTL" -D "$work_root/postgresql" -m fast -w stop >/dev/null 2>&1 || true
  fi
  [[ "$work_root" == /tmp/ishikawa-script-180.* && -d "$work_root" ]] \
    && rm -rf -- "$work_root"
  if (( status == 0 )); then
    result=pass
  else
    [[ -n "$failure_reason" ]] || failure_reason="${current_stage}_unexpected_exit_${status}"
    [[ "$failure_observation_retained" == false \
        && "$artifact_path" == "$ARTIFACT_ROOT"/* ]] \
      && rm -f -- "$artifact_path" "$artifact_checksum_path"
  fi
  if [[ -f "$report_path" ]]; then
    printf 'local_report=%s\n' "$report_path" | tee -a "$report_path"
    {
      printf '\nSCRIPT RESULT\n'
      [[ "$result" == pass ]] || printf 'reason=%s\n' "$failure_reason"
      printf 'script_180_implemented_v13_32_retrieval_gate=%s\n' "$result"
    } | tee -a "$report_path"
  else
    printf '\nSCRIPT RESULT\n'
    [[ "$result" == pass ]] || printf 'reason=%s\n' "$failure_reason"
    printf 'script_180_implemented_v13_32_retrieval_gate=%s\n' "$result"
  fi
  exit "$status"
}
trap 'record_unexpected_error $?' ERR
trap cleanup EXIT
trap 'handle_signal HUP 129' HUP
trap 'handle_signal INT 130' INT
trap 'handle_signal TERM 143' TERM

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

emit 'purpose=qualify_implemented_v13_32_retrieval'
emit "started_utc=$timestamp;script_sha256=$script_sha256;qualifier_sha256=$QUALIFIER_SHA256"
emit "candidate_identity=$EXPECTED_CANDIDATE_ID;cases=68;body_cases=60;header_cases=8"
emit 'authorized_actions=call_existing_loopback_nomic_start_private_unix_socket_postgresql_build_candidates_from_implemented_source_embed_candidates_and_queries_execute_content_free_retrieval_measurement_retain_local_evidence'
emit 'non_actions=no_gemma_no_accepted_database_no_ingestion_no_publication_no_corpus_change_no_truth_change_no_profile_change_no_package_change_no_release_change_no_black_corpus_no_remote_host_no_service_change_no_org_lab_change'

current_stage=nomic_readiness
nomic_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
  --connect-timeout 5 --max-time 10 "$NOMIC_HEALTH_URL" 2>/dev/null || true)"
[[ "$nomic_status" == 200 ]] || block nomic_forward_unavailable
emit 'milestone=readiness;state=pass;nomic=pass;gemma_required=false;accepted_postgresql_contact=false'

current_stage=credential_read
read_secret
emit 'milestone=credential;state=accepted;value_logged=false;value_retained=false'

current_stage=temporary_postgresql
mkdir -p -- "$work_root/socket"
"$INITDB" -D "$work_root/postgresql" --username="$(id -un)" --encoding=UTF8 \
  --no-locale --auth=trust >"$work_root/initdb.txt" 2>&1 \
  || block temporary_postgresql_initialization_failed
if ! "$PG_CTL" -D "$work_root/postgresql" \
  -o "-k $work_root/socket -h '' -p $TEMPORARY_POSTGRESQL_PORT -c fsync=off -c synchronous_commit=off -c full_page_writes=off" \
  -l "$work_root/postgresql.log" -w start >"$work_root/pg-start.txt" 2>&1; then
  if "$PG_CTL" -D "$work_root/postgresql" status >/dev/null 2>&1; then
    postgresql_started=true
  fi
  block temporary_postgresql_start_failed
fi
postgresql_started=true
emit 'milestone=temporary_postgresql;state=pass;tcp_listener=false;corpus_tables=false;accepted_database_contact=false'

current_stage=retrieval_gate
observation="$work_root/implemented-retrieval.json"
export ISHIKAWA_NOMIC_API_KEY="$nomic_key"
qualifier_status=0
PYTHONDONTWRITEBYTECODE=1 timeout --signal=TERM --kill-after=10s 900s \
  python3 -B "$QUALIFIER" --run \
  --python-root "$PYTHON_ROOT" \
  --normalized "$NORMALIZED" --expected-normalized-sha256 "$NORMALIZED_SHA256" \
  --body-cases "$BODY_CASES" --expected-body-cases-sha256 "$BODY_CASES_SHA256" \
  --header-cases "$HEADER_CASES" --expected-header-cases-sha256 "$HEADER_CASES_SHA256" \
  --prior-qualification "$PRIOR_QUALIFICATION" \
  --expected-prior-qualification-sha256 "$PRIOR_QUALIFICATION_SHA256" \
  --embedding-url "$NOMIC_EMBEDDING_URL" --tokenizer-url "$NOMIC_TOKENIZER_URL" \
  --postgresql-socket "$work_root/socket" --postgresql-port "$TEMPORARY_POSTGRESQL_PORT" \
  --postgresql-user "$(id -un)" --output "$observation" \
  >"$work_root/qualifier.stdout" 2>"$work_root/qualifier.stderr" \
  || qualifier_status="$?"
unset ISHIKAWA_NOMIC_API_KEY
nomic_key=''
if (( qualifier_status != 0 )); then
  if [[ -f "$work_root/qualifier.stdout" && ! -L "$work_root/qualifier.stdout" ]]; then
    while IFS= read -r line; do emit "$line"; done <"$work_root/qualifier.stdout"
  fi
  if [[ -f "$observation" && ! -L "$observation" ]]; then
    PYTHONDONTWRITEBYTECODE=1 python3 -B - "$observation" <<'PY'
import json
import pathlib
import sys

value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert value["artifact_kind"] == "ishikawa_implemented_v13_32_retrieval_qualification"
assert value["schema_version"] == 2
assert value["qualification_gate_met"] is False
assert value["boundaries"]["black_corpus_access"] is False
assert value["boundaries"]["accepted_database_contact"] is False
PY
    failed_observation_sha256="$(sha256sum "$observation" | awk '{print $1}')"
    tee -- "$artifact_path" <"$observation" >/dev/null \
      || block failure_observation_copy_failed
    [[ "$(sha256sum "$artifact_path" | awk '{print $1}')" == "$failed_observation_sha256" ]] \
      || block failure_observation_identity_changed_after_copy
    printf '%s  %s\n' "$failed_observation_sha256" "$(basename -- "$artifact_path")" \
      >"$artifact_checksum_path" || block failure_observation_checksum_write_failed
    failure_observation_retained=true
    emit "failed_qualification_observation=$artifact_path;failed_qualification_observation_sha256=$failed_observation_sha256"
  fi
  if (( qualifier_status == 124 || qualifier_status == 137 )); then
    block retrieval_gate_timeout
  fi
  reason="$(sed -n 's/^implemented_v13_32_retrieval_qualification=blocked;reason=\([a-z0-9_]*\)$/\1/p' "$work_root/qualifier.stdout" | tail -n 1)"
  [[ -z "$reason" ]] || block "qualification_$reason"
  block retrieval_gate_unclassified_failure
fi
grep -Fxq 'implemented_v13_32_retrieval_qualification=pass' \
  "$work_root/qualifier.stdout" || block retrieval_gate_pass_marker_absent
while IFS= read -r line; do emit "$line"; done <"$work_root/qualifier.stdout"
observation_sha256="$(sha256sum "$observation" | awk '{print $1}')"
emit "milestone=retrieval_gate;state=pass;artifact_sha256=$observation_sha256"

current_stage=observation_validation
validation_summary="$work_root/validation-summary.txt"
PYTHONDONTWRITEBYTECODE=1 python3 -B - "$observation" >"$validation_summary" <<'PY'
import json
import pathlib
import sys

value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert value["artifact_kind"] == "ishikawa_implemented_v13_32_retrieval_qualification"
assert value["schema_version"] == 2
assert value["qualification_gate_met"] is True
assert value["candidate_identity"] == "bf732e402004d70b0aa3318e179fe1a1e14d0bd4a70aaa2b4d71528088b7d518"
assert value["candidate_inventory"] == {
    "atomic": 139,
    "canonical_atomic": 118,
    "representatives": 29,
    "total": 168,
}
assert value["metrics"]["body"]["relevant_at_5"] == 60
assert value["metrics"]["body"]["required_evidence_matched_at_20"] == 60
assert value["metrics"]["header"]["mrr_at_20"] == "1.000000"
assert value["metrics"]["header"]["required_evidence_matched_at_20"] == 11
assert value["metrics"]["expanded_atomic_diagnostic"]["authoritative_evidence"] == {
    "body_matched": 60,
    "body_total": 60,
    "header_matched": 11,
    "header_total": 11,
}
assert value["gate"]["ranking_boundary"] == "collapsed_structural_selection_before_atomic_evidence_expansion"
assert value["next_gate"] == "complete_retrieval_api_and_gemma_evaluation"
assert value["boundaries"] == {
    "accepted_database_contact": False,
    "accepted_database_write": False,
    "black_corpus_access": False,
    "corpus_changed": False,
    "gemma_contact": False,
    "nomic_contact": True,
    "private_temporary_postgresql": True,
    "profile_changed": False,
    "truth_changed": False,
}
print("implemented_body_mrr_at_20=" + value["metrics"]["body"]["mrr_at_20"])
print("next_gate=" + value["next_gate"])
PY
while IFS= read -r line; do emit "$line"; done <"$validation_summary"

current_stage=temporary_postgresql_cleanup
"$PG_CTL" -D "$work_root/postgresql" -m fast -w stop \
  >"$work_root/pg-stop.txt" 2>&1 || block temporary_postgresql_stop_failed
postgresql_started=false
emit 'milestone=temporary_postgresql_cleanup;state=pass;cluster_retained=false;listener_retained=false'

current_stage=artifact_retention
[[ ! -e "$artifact_path" && ! -L "$artifact_path" ]] \
  || block qualification_artifact_destination_exists
tee -- "$artifact_path" <"$observation" >/dev/null \
  || block qualification_artifact_copy_failed
[[ "$(sha256sum "$artifact_path" | awk '{print $1}')" == "$observation_sha256" ]] \
  || block qualification_artifact_identity_changed_after_copy
printf '%s  %s\n' "$observation_sha256" "$(basename -- "$artifact_path")" \
  >"$artifact_checksum_path" || block qualification_checksum_write_failed
(trap - ERR EXIT HUP INT TERM; cd -- "$ARTIFACT_ROOT" \
  && sha256sum --quiet -c "$(basename -- "$artifact_checksum_path")") \
  || block qualification_checksum_verification_failed
emit 'milestone=artifact_retention;state=pass;artifacts=1;checksum_manifests=1'
emit "qualification_observation=$artifact_path;qualification_observation_sha256=$observation_sha256"
emit 'candidate_frozen=true;implemented_retrieval_qualified=true;accepted_release_changed=false;deployment_candidate_assembled=false'
emit 'next_gate=complete_retrieval_api_and_gemma_evaluation'
current_stage=complete
