#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Bind the operator's V13-32 freeze to the measured retrieval finalist,
#   qualify its application implementation, and stop before live retrieval.
#
# Boundaries:
#   Local source, retained synthetic evidence, a disposable Unix-socket-only
#   PostgreSQL cluster, and the existing architecture-matched Node image only.
#   No accepted database, model, credential, corpus, service, package, release,
#   remote host, black corpus, or org-lab state is read or changed.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/179_freeze_and_qualify_v13_32_application_implementation.sh --run

usage() {
  sed -n '3,15p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Execute the complete local implementation qualification.' \
    '  --validate-only Validate frozen inputs, identities, and script structure only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly WEB_ROOT="$PRODUCT_ROOT/application/web"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly TEST_RUNNER="$PRODUCT_ROOT/scripts/run-local-validation-tests.sh"
readonly SCHEMA="$PRODUCT_ROOT/packaging/database/schema.sql"
readonly METHOD_PROFILE="$PRODUCT_ROOT/config/templates/method_profile.yaml"
readonly PRE_FREEZE_REPORT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-pre-freeze-review/pre_freeze_review_20261023T000028Z_lZNTX5.txt"
readonly PRE_FREEZE_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-pre-freeze-review/pre_freeze_review_20261023T000028Z_lZNTX5.json"
readonly NORMALIZED="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-isolated-publication/retained-derived-artifacts-20261022T204745Z/71/711997caa99c2b92ee555f7ea29e012e2fbb86e39fd65f662cd52e174ec07ead"
readonly MEASURED_REPRESENTATIVES="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-section-page-experiment/section_page_representatives_20261022T233308Z_6XRxP3.json"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.3-v13-32-application-implementation"
readonly INITDB='/usr/lib/postgresql/16/bin/initdb'
readonly PG_CTL='/usr/lib/postgresql/16/bin/pg_ctl'
readonly CREATEDB='/usr/lib/postgresql/16/bin/createdb'
readonly PSQL='/usr/lib/postgresql/16/bin/psql'

readonly EXPECTED_DECISIONS_SHA256='dbcd6f38a17a312e2480a9a002f55237b64c58fdc5fbfbb6e854874825e7cdeb'
readonly EXPECTED_PRE_FREEZE_REPORT_SHA256='0b9c7b054a3b552bd8644692bcd2e9caee437c188a4b63a2cc8ec9262a4c1384'
readonly EXPECTED_PRE_FREEZE_ARTIFACT_SHA256='e8ba3d8e9e2f5fd58b003131b3fbf2f80d2ba9cd7b0b30e373ef01db58870398'
readonly EXPECTED_NORMALIZED_SHA256='711997caa99c2b92ee555f7ea29e012e2fbb86e39fd65f662cd52e174ec07ead'
readonly EXPECTED_MEASURED_REPRESENTATIVES_SHA256='3554061e9a818af0dd948d3112bf9b48196cf6ed4c67db61d4a3b564eb1ae004'
readonly EXPECTED_CANDIDATE_ID='bf732e402004d70b0aa3318e179fe1a1e14d0bd4a70aaa2b4d71528088b7d518'
readonly EXPECTED_CHUNK_METHOD_ID='0c16e785006d8f68cf942bf9f76a84d0d837b84be629fe898898d319f45d34a1'
readonly EXPECTED_RETRIEVAL_PROFILE_ID='96915e0cbb0547bebf3af54b21d92a3ec923bba6e058ad2460ced05336d41a1d'
readonly EXPECTED_SCHEMA_SHA256='3b55d00880e6e09e401e282b7f62314fb635c6a859c23ad3e87c58aa23237e8b'
readonly EXPECTED_CHUNK_SET_DIGEST='64672ba2d446a60a8ba299d356eb2bc0d758cd07ce47f6d117979e6c2d759baa'
readonly EXPECTED_APPLICATION_MANIFEST_SHA256='6b6f6aeb866e37821a00e38cd417e1c1e7c02f48212a3a354389aac74d40adf3'
readonly EXPECTED_APPLICATION_FILES=174
readonly EXPECTED_NATIVE_TESTS=414
readonly EXPECTED_SUPPLEMENTAL_TESTS=24
readonly EXPECTED_JAVASCRIPT_TESTS=17
readonly TEMPORARY_POSTGRESQL_PORT=65435

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      printf 'reason=argument_invalid\n\nSCRIPT RESULT\nscript_179_v13_32_application_implementation=blocked\n' >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'reason=mode_invalid\n\nSCRIPT RESULT\nscript_179_v13_32_application_implementation=blocked\n' >&2
  exit 2
}

preflight_block() {
  printf 'reason=%s\n\nSCRIPT RESULT\nscript_179_v13_32_application_implementation=blocked\n' "$1" >&2
  exit "${2:-2}"
}

for command_name in awk bash cmp date dirname find grep kill mkdir mktemp \
  python3 rm sed sha256sum sort stat tee; do
  command -v "$command_name" >/dev/null 2>&1 \
    || preflight_block "local_command_missing_$command_name"
done
if [[ "$validate_only" != true ]]; then
  for command_name in docker dpkg sleep sudo; do
    command -v "$command_name" >/dev/null 2>&1 \
      || preflight_block "local_command_missing_$command_name"
  done
  for executable in "$INITDB" "$PG_CTL" "$CREATEDB" "$PSQL"; do
    [[ -f "$executable" && ! -L "$executable" && -x "$executable" ]] \
      || preflight_block postgresql_16_binary_unsafe
  done
fi

check_file() {
  local path="$1" expected="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] \
    || preflight_block "${label}_unsafe"
  [[ "$(sha256sum "$path" | awk '{print $1}')" == "$expected" ]] \
    || preflight_block "${label}_identity_changed"
}

check_file "$DECISIONS" "$EXPECTED_DECISIONS_SHA256" decisions
check_file "$PRE_FREEZE_REPORT" "$EXPECTED_PRE_FREEZE_REPORT_SHA256" pre_freeze_report
check_file "$PRE_FREEZE_ARTIFACT" "$EXPECTED_PRE_FREEZE_ARTIFACT_SHA256" pre_freeze_artifact
check_file "$NORMALIZED" "$EXPECTED_NORMALIZED_SHA256" normalized_v2
check_file "$MEASURED_REPRESENTATIVES" "$EXPECTED_MEASURED_REPRESENTATIVES_SHA256" measured_representatives
check_file "$SCHEMA" "$EXPECTED_SCHEMA_SHA256" schema_v5
[[ -f "$METHOD_PROFILE" && ! -L "$METHOD_PROFILE" && -r "$METHOD_PROFILE" ]] \
  || preflight_block method_profile_unsafe
[[ -x "$TEST_RUNNER" && ! -L "$TEST_RUNNER" ]] \
  || preflight_block native_test_runner_unsafe

grep -Eq "^\| \`V13-32\` \|.*${EXPECTED_CANDIDATE_ID}.*\| FROZEN \|$" "$DECISIONS" \
  || preflight_block v13_32_freeze_record_invalid 1
grep -Fxq 'script_178_live_v2_retrieval_finalist_pre_freeze_review=pass' \
  "$PRE_FREEZE_REPORT" || preflight_block script_178_not_clean 1
grep -Fxq 'next_gate=operator_freeze_decision_for_v2_retrieval_candidate' \
  "$PRE_FREEZE_REPORT" || preflight_block script_178_next_gate_invalid 1

mapfile -t application_files < <(
  {
    find "$PYTHON_ROOT/ishikawa" "$PRODUCT_ROOT/tests" \
      "$WEB_ROOT/app" "$WEB_ROOT/components" "$WEB_ROOT/lib" \
      "$WEB_ROOT/public" "$WEB_ROOT/tests" "$PRODUCT_ROOT/config/templates" \
      "$PRODUCT_ROOT/docs" "$PRODUCT_ROOT/packaging/database" \
      -type f ! -path '*/__pycache__/*' ! -path '*/.next/*' \
      ! -name '*.pyc' -print
    printf '%s\n' \
      "$PRODUCT_ROOT/README.md" \
      "$WEB_ROOT/package.json" \
      "$WEB_ROOT/next.config.mjs" \
      "$TEST_RUNNER"
  } | LC_ALL=C sort -u
)
(( ${#application_files[@]} == EXPECTED_APPLICATION_FILES )) \
  || preflight_block application_file_count_mismatch 1
for path in "${application_files[@]}"; do
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] \
    || preflight_block application_source_unsafe
done
application_manifest_sha256="$({
  for path in "${application_files[@]}"; do
    relative="${path#"$PRODUCT_ROOT/"}"
    printf '%s  %s\n' "$(sha256sum "$path" | awk '{print $1}')" "$relative"
  done
} | sha256sum | awk '{print $1}')"
[[ "$application_manifest_sha256" == "$EXPECTED_APPLICATION_MANIFEST_SHA256" ]] \
  || preflight_block application_source_identity_changed 1

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; [compile(p.read_text(encoding="utf-8"), str(p), "exec") for p in pathlib.Path(sys.argv[1]).glob("*.py")]' \
  "$PYTHON_ROOT/ishikawa"

PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B - \
  "$PRE_FREEZE_ARTIFACT" "$NORMALIZED" "$MEASURED_REPRESENTATIVES" \
  "$METHOD_PROFILE" "$EXPECTED_CANDIDATE_ID" "$EXPECTED_CHUNK_METHOD_ID" \
  "$EXPECTED_RETRIEVAL_PROFILE_ID" "$EXPECTED_CHUNK_SET_DIGEST" <<'PY'
import json
import pathlib
import sys

from ishikawa.chunking import (
    METHOD_PROFILE_ID,
    build_chunk_candidates,
    chunk_candidates_json_bytes,
)
from ishikawa.method_profile import ACCEPTED_RETRIEVAL_PROFILE
from ishikawa.yaml_loader import load_restricted_yaml
from ishikawa.method_profile import validate_retrieval_profile

(
    review_path,
    normalized_path,
    measured_path,
    method_profile_path,
    candidate_id,
    chunk_method_id,
    retrieval_profile_id,
    chunk_set_digest,
) = sys.argv[1:]

review = json.loads(pathlib.Path(review_path).read_text(encoding="utf-8"))
assert review["candidate"]["identity"] == candidate_id
assert review["candidate"]["profile"] == {
    "exact_weight": 1,
    "lexical_depth": 20,
    "lexical_weight": 2,
    "rrf_constant": 60,
    "vector_depth": 20,
    "vector_weight": 4,
}
assert review["candidate"]["behavior"] == {
    "document_local_duplicate_canonicalization": True,
    "section_page_representatives": True,
}
assert review["ready_for_operator_freeze_decision"] is True

profile = validate_retrieval_profile(
    load_restricted_yaml(pathlib.Path(method_profile_path), label="method profile")
)
assert METHOD_PROFILE_ID == chunk_method_id == profile.chunk_method_profile_id
assert ACCEPTED_RETRIEVAL_PROFILE.digest == profile.digest == retrieval_profile_id
assert (profile.exact_weight, profile.lexical_weight, profile.vector_weight) == (1, 2, 4)
assert profile.section_page_representatives is True
assert profile.document_local_duplicate_canonicalization is True
assert profile.representative_evidence == "expand_to_ordered_atomic_members"

normalized = json.loads(pathlib.Path(normalized_path).read_text(encoding="utf-8"))
first = build_chunk_candidates(normalized)
second = build_chunk_candidates(normalized)
assert chunk_candidates_json_bytes(first) == chunk_candidates_json_bytes(second)
assert first["chunk_candidate_set_digest"] == chunk_set_digest

all_candidates = [
    (document["document_ref"], candidate)
    for document in first["documents"]
    for candidate in document["candidates"]
]
representatives = [
    pair for pair in all_candidates
    if pair[1]["projection_kind"] == "section_page_representative"
]
atomic = [
    pair for pair in all_candidates
    if pair[1]["projection_kind"] != "section_page_representative"
]
assert len(all_candidates) == 168
assert len(atomic) == 139
assert len(representatives) == 29
assert sum(
    bool(item["projection_properties"]["document_local_content_canonical"])
    for _, item in atomic
) == 118
assert sum(
    len(item["projection_properties"]["component_chunk_ids"])
    for _, item in representatives
) == 123

atomic_ids = {item["chunk_id"] for _, item in atomic}
for _, representative in representatives:
    properties = representative["projection_properties"]
    assert properties["retrieval_scoring_only"] is True
    assert properties["atomic_evidence_authoritative"] is True
    assert properties["component_chunk_ids"]
    assert set(properties["component_chunk_ids"]) <= atomic_ids

measured = json.loads(pathlib.Path(measured_path).read_text(encoding="utf-8"))
measured_representatives = [
    (document["document_ref"], candidate)
    for document in measured["documents"]
    for candidate in document["candidates"]
]
assert len(measured_representatives) == 29

def key(pair):
    document_ref, candidate = pair
    anchor = candidate["citation_anchor"]
    return (
        document_ref,
        anchor["page_start"],
        anchor["page_end"],
        tuple(anchor["structural_path"]),
    )

implemented_by_key = {key(pair): pair[1] for pair in representatives}
measured_by_key = {key(pair): pair[1] for pair in measured_representatives}
assert set(implemented_by_key) == set(measured_by_key)
semantic_fields = (
    "content_text",
    "context_text",
    "retrieval_text",
    "source_unit_ids",
    "parent_unit_id",
    "lexical_fields",
    "retrieval_filters",
)
for identity in implemented_by_key:
    implemented = implemented_by_key[identity]
    measured_candidate = measured_by_key[identity]
    assert all(
        implemented.get(field) == measured_candidate.get(field)
        for field in semantic_fields
    )
PY

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_v13_32_application_implementation' \
    "script_sha256=$script_sha256" \
    "candidate_identity=$EXPECTED_CANDIDATE_ID;chunk_method_id=$EXPECTED_CHUNK_METHOD_ID;retrieval_profile_id=$EXPECTED_RETRIEVAL_PROFILE_ID" \
    "application_manifest_sha256=$application_manifest_sha256;application_files=$EXPECTED_APPLICATION_FILES" \
    'implemented_candidate_equivalence=pass;representatives=29;authoritative_atomic_candidates=139;canonical_atomic_candidates=118' \
    'native_tests=not_run;supplemental_tests=not_run;schema_v5=not_applied;javascript_tests=not_run;next_build=not_run' \
    'database_contact=false;model_contact=false;credential_read=false;service_changed=false;package_changed=false;accepted_release_changed=false' \
    '' \
    'SCRIPT RESULT' \
    'script_179_v13_32_application_implementation=pass'
  exit 0
fi

umask 077
mkdir -p -- "$REPORT_ROOT" || preflight_block local_report_root_creation_failed
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" && -w "$REPORT_ROOT" ]] \
  || preflight_block local_report_root_unsafe
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/v13_32_application_implementation_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-script-179.XXXXXX)"
postgresql_started=false
build_pid=''
failure_reason=''
current_stage='runtime_initialization'
readonly MAIN_BASHPID="$BASHPID"

emit() {
  printf '%s\n' "$1" | tee -a "$report_path"
}

block() {
  failure_reason="$1"
  exit "${2:-1}"
}

record_unexpected_error() {
  local status="$1"
  if [[ "$BASHPID" == "$MAIN_BASHPID" && -z "$failure_reason" ]]; then
    failure_reason="${current_stage}_unexpected_exit_${status}"
  fi
}

cleanup() {
  local status="$?" result=blocked stop_status=0
  trap - ERR EXIT HUP INT TERM
  set +e
  if [[ "$build_pid" =~ ^[0-9]+$ ]] && kill -0 "$build_pid" 2>/dev/null; then
    kill -TERM "$build_pid" 2>/dev/null
    wait "$build_pid" 2>/dev/null
  fi
  if [[ "$postgresql_started" == true && "$work_root" == /tmp/ishikawa-script-179.* ]]; then
    "$PG_CTL" -D "$work_root/postgresql" -m fast -w stop >/dev/null 2>&1 \
      || stop_status=$?
    if (( stop_status != 0 && status == 0 )); then
      status=1
      failure_reason=temporary_postgresql_cleanup_failed
    fi
  fi
  [[ "$work_root" == /tmp/ishikawa-script-179.* && -d "$work_root" ]] \
    && rm -rf -- "$work_root"
  if (( status == 0 )); then
    result=pass
  elif [[ -z "$failure_reason" ]]; then
    failure_reason="${current_stage}_unexpected_exit_${status}"
  fi
  if [[ -f "$report_path" ]]; then
    printf 'local_report=%s\n' "$report_path" | tee -a "$report_path"
    {
      printf '\nSCRIPT RESULT\n'
      [[ "$result" == pass ]] || printf 'reason=%s\n' "$failure_reason"
      printf 'script_179_v13_32_application_implementation=%s\n' "$result"
    } | tee -a "$report_path"
  else
    printf '\nSCRIPT RESULT\n'
    [[ "$result" == pass ]] || printf 'reason=%s\n' "$failure_reason"
    printf 'script_179_v13_32_application_implementation=%s\n' "$result"
  fi
  exit "$status"
}
handle_signal() {
  failure_reason="interrupted_$1"
  exit "$2"
}
trap 'record_unexpected_error $?' ERR
trap cleanup EXIT
trap 'handle_signal HUP 129' HUP
trap 'handle_signal INT 130' INT
trap 'handle_signal TERM 143' TERM

emit 'purpose=freeze_and_qualify_v13_32_application_implementation'
emit "started_utc=$timestamp;script_sha256=$script_sha256"
emit "candidate_identity=$EXPECTED_CANDIDATE_ID;chunk_method_id=$EXPECTED_CHUNK_METHOD_ID;retrieval_profile_id=$EXPECTED_RETRIEVAL_PROFILE_ID"
emit "application_manifest_sha256=$application_manifest_sha256;application_files=$EXPECTED_APPLICATION_FILES"
emit 'authorized_actions=read_checksum_bound_local_evidence_run_local_tests_apply_schema_to_disposable_unix_socket_postgresql_run_offline_web_tests_and_build_write_content_free_local_report'
emit 'non_actions=no_remote_contact_no_accepted_database_contact_no_model_contact_no_credential_read_no_service_start_or_change_no_corpus_change_no_package_change_no_release_change_no_black_corpus_access_no_org_lab_change'
emit 'milestone=implemented_candidate_equivalence;state=pass;representatives=29;authoritative_atomic_candidates=139;canonical_atomic_candidates=118;component_memberships=123'

current_stage=native_tests
emit 'milestone=native_tests;state=start'
native_result="$work_root/native-tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$native_result" 2>&1 \
  || block native_test_regression
grep -Fq "Ran $EXPECTED_NATIVE_TESTS tests" "$native_result" \
  || block native_test_count_mismatch
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$native_result" \
  || block native_test_marker_absent
emit "milestone=native_tests;state=pass;tests=$EXPECTED_NATIVE_TESTS"

current_stage=supplemental_tests
emit 'milestone=supplemental_tests;state=start'
supplemental_result="$work_root/supplemental-tests.txt"
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B -m unittest -v \
  "$PRODUCT_ROOT/tests/chunking_checks.py" \
  "$PRODUCT_ROOT/tests/artifact_adapter_checks.py" \
  >"$supplemental_result" 2>&1 || block supplemental_test_regression
grep -Fq "Ran $EXPECTED_SUPPLEMENTAL_TESTS tests" "$supplemental_result" \
  || block supplemental_test_count_mismatch
grep -Fxq 'OK' "$supplemental_result" || block supplemental_test_marker_absent
emit "milestone=supplemental_tests;state=pass;tests=$EXPECTED_SUPPLEMENTAL_TESTS"

current_stage=schema_v5
emit 'milestone=schema_v5;state=start;isolation=private_unix_socket_cluster'
mkdir -p -- "$work_root/socket"
"$INITDB" -D "$work_root/postgresql" --auth-local=trust --auth-host=reject \
  --encoding=UTF8 --no-locale --no-instructions \
  >"$work_root/initdb.txt" 2>&1 || block temporary_postgresql_init_failed
"$PG_CTL" -D "$work_root/postgresql" \
  -o "-k $work_root/socket -h '' -p $TEMPORARY_POSTGRESQL_PORT" \
  -l "$work_root/postgresql.log" -w start \
  >"$work_root/pg-start.txt" 2>&1 || block temporary_postgresql_start_failed
postgresql_started=true
readonly -a pg_connection=(--host="$work_root/socket" --port="$TEMPORARY_POSTGRESQL_PORT")
"$PSQL" "${pg_connection[@]}" --dbname=postgres --no-psqlrc \
  --set=ON_ERROR_STOP=1 --quiet --command='CREATE ROLE ishikawa_owner NOLOGIN; CREATE ROLE rag_ingest NOLOGIN; CREATE ROLE rag_retrieval NOLOGIN;' \
  >"$work_root/roles.txt" 2>&1 || block temporary_postgresql_role_creation_failed
"$CREATEDB" "${pg_connection[@]}" --owner=ishikawa_owner ishikawa_v13_32_test \
  >"$work_root/createdb.txt" 2>&1 || block temporary_database_creation_failed
"$PSQL" "${pg_connection[@]}" --dbname=ishikawa_v13_32_test --no-psqlrc \
  --set=ON_ERROR_STOP=1 --quiet --command='CREATE EXTENSION vector; REVOKE CREATE ON SCHEMA public FROM PUBLIC;' \
  >"$work_root/vector.txt" 2>&1 || block temporary_vector_extension_failed
"$PSQL" "${pg_connection[@]}" --dbname=ishikawa_v13_32_test --no-psqlrc \
  --set=ON_ERROR_STOP=1 --quiet \
  --set=owner_role=ishikawa_owner --set=ingest_role=rag_ingest \
  --set=retrieval_role=rag_retrieval --set="schema_sha256=$EXPECTED_SCHEMA_SHA256" \
  --file="$SCHEMA" >"$work_root/schema.txt" 2>&1 \
  || block schema_v5_application_failed
schema_contract="$("$PSQL" "${pg_connection[@]}" --dbname=ishikawa_v13_32_test \
  --no-psqlrc --set=ON_ERROR_STOP=1 --quiet --tuples-only --no-align \
  --command="SELECT migration_id || '|' || migration_sha256 || '|' || schema_version FROM rag.schema_migrations;")" \
  || block schema_v5_contract_read_failed
[[ "$schema_contract" == "ishikawa_consolidated_schema_v5|$EXPECTED_SCHEMA_SHA256|5" ]] \
  || block schema_v5_contract_mismatch
view_contract="$("$PSQL" "${pg_connection[@]}" --dbname=ishikawa_v13_32_test \
  --no-psqlrc --set=ON_ERROR_STOP=1 --quiet --tuples-only --no-align \
  --command="SELECT count(*) FROM pg_views WHERE schemaname='rag_search' AND viewname IN ('active_chunks','active_retrieval_candidates','active_embeddings','active_retrieval_embeddings');")" \
  || block retrieval_view_contract_read_failed
[[ "$view_contract" == 4 ]] || block retrieval_view_contract_mismatch
security_contract="$("$PSQL" "${pg_connection[@]}" --dbname=ishikawa_v13_32_test \
  --no-psqlrc --set=ON_ERROR_STOP=1 --quiet --tuples-only --no-align \
  --command="SELECT count(*) FROM pg_class WHERE relnamespace='rag_search'::regnamespace AND relname IN ('active_chunks','active_retrieval_candidates','active_embeddings','active_retrieval_embeddings') AND reloptions @> ARRAY['security_barrier=true'];")" \
  || block retrieval_view_security_read_failed
[[ "$security_contract" == 4 ]] || block retrieval_view_security_mismatch
"$PSQL" "${pg_connection[@]}" --dbname=ishikawa_v13_32_test --no-psqlrc \
  --set=ON_ERROR_STOP=1 --quiet \
  --command='SELECT retrieval_group_id, authoritative_chunk_ids, retrieval_scoring_only, document_local_content_canonical FROM rag_search.active_retrieval_candidates LIMIT 0; SELECT chunk_id FROM rag_search.active_retrieval_embeddings LIMIT 0;' \
  >"$work_root/view-shape.txt" 2>&1 || block retrieval_view_shape_invalid
"$PG_CTL" -D "$work_root/postgresql" -m fast -w stop \
  >"$work_root/pg-stop.txt" 2>&1 || block temporary_postgresql_stop_failed
postgresql_started=false
emit "milestone=schema_v5;state=pass;schema_sha256=$EXPECTED_SCHEMA_SHA256;accepted_database_contact=false"

current_stage=container_access
docker_command=(docker)
if ! docker info >/dev/null 2>&1; then
  emit 'milestone=container_access;state=awaiting_attended_sudo'
  sudo -v || block sudo_authentication_failed 2
  docker_command=(sudo docker)
  "${docker_command[@]}" info >/dev/null 2>&1 || block docker_access_failed 2
fi
architecture="$(dpkg --print-architecture)"
case "$architecture" in arm64|amd64) ;; *) block host_architecture_unsupported 2 ;; esac
image="node-24-slim-nextjs-16-4-1:$architecture"
"${docker_command[@]}" image inspect "$image" >/dev/null 2>&1 \
  || block required_local_image_missing 2
[[ "$("${docker_command[@]}" image inspect "$image" --format '{{.Architecture}}')" == "$architecture" ]] \
  || block image_architecture_mismatch 2
emit "milestone=container_access;state=pass;architecture=$architecture;image=$image;image_pulled=false"

declare -a web_mounts=(
  --mount "type=bind,src=$WEB_ROOT/app,dst=/opt/nextjs/app,readonly"
  --mount "type=bind,src=$WEB_ROOT/components,dst=/opt/nextjs/components,readonly"
  --mount "type=bind,src=$WEB_ROOT/lib,dst=/opt/nextjs/lib,readonly"
  --mount "type=bind,src=$WEB_ROOT/public,dst=/opt/nextjs/public,readonly"
  --mount "type=bind,src=$WEB_ROOT/tests,dst=/opt/nextjs/tests,readonly"
  --mount "type=bind,src=$WEB_ROOT/package.json,dst=/opt/nextjs/package.json,readonly"
  --mount "type=bind,src=$WEB_ROOT/next.config.mjs,dst=/opt/nextjs/next.config.mjs,readonly"
)

current_stage=javascript_tests
emit 'milestone=javascript_tests;state=start'
javascript_result="$work_root/javascript-tests.txt"
"${docker_command[@]}" run --rm --network none "${web_mounts[@]}" \
  "$image" node --test --test-reporter=tap \
  tests/chat-contract.test.mjs tests/presentation.test.mjs tests/runtime-config.test.mjs \
  >"$javascript_result" 2>&1 || block javascript_tests_failed
for expected in \
  "# tests $EXPECTED_JAVASCRIPT_TESTS" \
  "# pass $EXPECTED_JAVASCRIPT_TESTS" \
  '# fail 0'; do
  grep -Eq "^[[:space:]]*$expected[[:space:]]*$" "$javascript_result" \
    || block javascript_test_count_mismatch
done
emit "milestone=javascript_tests;state=pass;tests=$EXPECTED_JAVASCRIPT_TESTS"

current_stage=next_build
emit 'milestone=next_build;state=start'
build_result="$work_root/next-build.txt"
"${docker_command[@]}" run --rm --network none \
  -e ISHIKAWA_PRODUCT_DISPLAY_NAME=Ishikawa \
  -e ISHIKAWA_RETRIEVAL_BASE_URL=http://127.0.0.1:1384 \
  "${web_mounts[@]}" "$image" npm run build >"$build_result" 2>&1 &
build_pid=$!
while kill -0 "$build_pid" 2>/dev/null; do
  sleep 5
  kill -0 "$build_pid" 2>/dev/null && emit 'milestone=next_build;state=running'
done
set +e
wait "$build_pid"
build_status=$?
set -e
(( build_status == 0 )) || block next_build_failed
emit 'milestone=next_build;state=pass'

current_stage=finalization
emit "native_tests=$EXPECTED_NATIVE_TESTS;supplemental_tests=$EXPECTED_SUPPLEMENTAL_TESTS;javascript_tests=$EXPECTED_JAVASCRIPT_TESTS;next_build=pass"
emit 'implemented_candidate_equivalence=pass;schema_v5=pass;representative_evidence=ordered_authoritative_atomic_members'
emit 'candidate_frozen=true;implementation_qualified=true;retrieval_profile_promoted=false;deployment_candidate_assembled=false'
emit 'database_contact=false;model_contact=false;credential_read=false;service_changed=false;corpus_changed=false;package_changed=false;accepted_release_changed=false;black_corpus_access=false;org_lab_changed=false'
emit 'next_gate=repeat_60_body_and_8_header_retrieval_gate_from_implemented_source'
