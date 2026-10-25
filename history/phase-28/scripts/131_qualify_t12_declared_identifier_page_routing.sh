#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify frozen T12 declared-identifier page routing against native tests,
#   the retained 60-case ranks, and the active local synthetic corpus.
#
# Mental model:
#   Prove that a document's own citation declaration identifies one owner and
#   routes five explicit page questions directly. No-owner input falls back to
#   ordinary retrieval, and ambiguity remains a clarification in native tests.
#
# Inputs or prerequisites:
#   Clean Script 130 evidence, frozen T12, local read-only PostgreSQL, and the
#   rag_retrieval password. Nomic and Gemma are not used.
#
# Outputs:
#   One content-free report. No database, profile, package, service, model,
#   forwarding, source document, or accepted release is changed.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/131_qualify_t12_declared_identifier_page_routing.sh --run

usage() {
  sed -n '3,22p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run            Run native regression and read-only corpus qualification.' \
    '  --validate-only  Validate bound source and retained evidence only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly TEST_ROOT="$PRODUCT_ROOT/tests"
readonly HELPER="$SCRIPT_DIR/qualify_t12_declared_identifier_page_routing.py"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_1_TUNING_DECISIONS.md"
readonly RETRIEVAL="$PYTHON_ROOT/ishikawa/retrieval.py"
readonly QUERY_ROUTING="$PYTHON_ROOT/ishikawa/query_routing.py"
readonly POSTGRES_RETRIEVAL="$PYTHON_ROOT/ishikawa/postgres_retrieval.py"
readonly TEST_RETRIEVAL="$TEST_ROOT/test_retrieval.py"
readonly TEST_QUERY_ROUTING="$TEST_ROOT/test_query_routing.py"
readonly TEST_POSTGRES_RETRIEVAL="$TEST_ROOT/test_postgres_retrieval.py"
readonly SCRIPT_130_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.1-extended-profile-search/extended_profile_search_20261021T202524Z_JJArWD.txt"
readonly SCRIPT_130_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/v1.1-extended-profile-search/extended_profile_search_7aa208c295fc748c0adc56ba5b9ea886177ce8cafd64b37b244518560e6d2ad2.json"
readonly SCRIPT_130_CHECKSUM="$SCRIPT_130_ARTIFACT.sha256"
readonly LANE_OBSERVATION="$REPO_ROOT/local/artifacts/ishikawa/v1.1-extended-lane-rankings/extended_lane_rankings_362598ff121817c718aac7449d9fe481d416394b8ecc14a5cd44b91c949f6db6.json"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.1-t12-routing"

readonly HELPER_SHA256='8fed0a557f7a7007055009ab45c4c79bd8cb39c761e95715360b6ee6702ef715'
readonly DECISIONS_SHA256='9ed1305d5e75bf18ede97e27b2fc19e8d4423718017ec659ea736ea4bd29af7a'
readonly RETRIEVAL_SHA256='0307dba6facac397c417b5c9e4345ae1da01c3ce8ea1ba9a9b4a90a5a4353b68'
readonly QUERY_ROUTING_SHA256='15e832bf973ea11edccbe0e593546c2d1656dfc39e871870d3c5b58f1e6eaebb'
readonly POSTGRES_RETRIEVAL_SHA256='50fa0d407399b674d29eb44e90bc8202416cdece2da54f6fbc1156e2a4dc3828'
readonly TEST_RETRIEVAL_SHA256='f05ddc01427814a1b4e3b982d861edf66503f938e23d98b0436f8285cf99556e'
readonly TEST_QUERY_ROUTING_SHA256='9ddf90fefb07e5bf6f8ecded2018a3c83afec04ad3222a2dd5047d9b15bebc69'
readonly TEST_POSTGRES_RETRIEVAL_SHA256='be2ed66373439ba2038e54898743b5464f340d96922fd7a4a6fc68f292120113'
readonly SCRIPT_130_REPORT_SHA256='81a382632fcbe8a910ca00a98da6f869ac4b946859bcf7d454c84d66c198eb9d'
readonly SCRIPT_130_ARTIFACT_SHA256='224b18fc85fe72beb7033fae62f0ac22503ef71b48f6d0beaf3611b2f7efeca6'
readonly SCRIPT_130_CHECKSUM_SHA256='61f90ed921f08580a762df93b7177f921eb33d9a2211c3a6e2053312b890e0db'
readonly LANE_OBSERVATION_SHA256='16de18c2d6b485fac6001edf44268f50cbfae23ac2fc404664ad2e29717db6a5'

run_mode=false
validate_mode=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_mode=true; shift ;;
    --validate-only) validate_mode=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_131_t12_routing=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_mode" != "$validate_mode" ]] || {
  printf 'script_131_t12_routing=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in awk bash basename chmod date dirname grep mkdir mktemp pg_isready python3 rm sed sha256sum tail tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_131_t12_routing=blocked;reason=local_command_missing;command=%s\n' "$required" >&2
    exit 2
  }
done

check_file() {
  [[ -f "$1" && ! -L "$1" && -r "$1" ]] || {
    printf 'script_131_t12_routing=blocked;reason=%s_unsafe\n' "$3" >&2
    exit 2
  }
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_131_t12_routing=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}

check_file "$HELPER" "$HELPER_SHA256" helper
check_file "$DECISIONS" "$DECISIONS_SHA256" tuning_decisions
check_file "$RETRIEVAL" "$RETRIEVAL_SHA256" retrieval_source
check_file "$QUERY_ROUTING" "$QUERY_ROUTING_SHA256" query_routing_source
check_file "$POSTGRES_RETRIEVAL" "$POSTGRES_RETRIEVAL_SHA256" postgres_retrieval_source
check_file "$TEST_RETRIEVAL" "$TEST_RETRIEVAL_SHA256" retrieval_tests
check_file "$TEST_QUERY_ROUTING" "$TEST_QUERY_ROUTING_SHA256" query_routing_tests
check_file "$TEST_POSTGRES_RETRIEVAL" "$TEST_POSTGRES_RETRIEVAL_SHA256" postgres_retrieval_tests
check_file "$SCRIPT_130_REPORT" "$SCRIPT_130_REPORT_SHA256" script_130_report
check_file "$SCRIPT_130_ARTIFACT" "$SCRIPT_130_ARTIFACT_SHA256" script_130_artifact
check_file "$SCRIPT_130_CHECKSUM" "$SCRIPT_130_CHECKSUM_SHA256" script_130_checksum
check_file "$LANE_OBSERVATION" "$LANE_OBSERVATION_SHA256" lane_observation
(
  cd -- "$(dirname -- "$SCRIPT_130_CHECKSUM")"
  sha256sum --check --strict "$(basename -- "$SCRIPT_130_CHECKSUM")" >/dev/null
) || {
  printf 'script_131_t12_routing=blocked;reason=script_130_checksum_failed\n' >&2
  exit 2
}
grep -Fq 'script_130_extended_profile_search=pass;selection_status=no_candidate_meets_target;profile_changed=false' "$SCRIPT_130_REPORT" || {
  printf 'script_131_t12_routing=blocked;reason=script_130_contract_invalid\n' >&2
  exit 2
}
grep -Eq '^\| `T12` \|.*\| FROZEN \|$' "$DECISIONS" || {
  printf 'script_131_t12_routing=blocked;reason=t12_not_frozen\n' >&2
  exit 2
}

bash -n "${BASH_SOURCE[0]}"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
  "$HELPER"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$HELPER" --self-test \
  | grep -Fxq 't12_declared_identifier_page_routing_self_test=pass' || {
    printf 'script_131_t12_routing=blocked;reason=helper_self_test_failed\n' >&2
    exit 2
  }
projection="$(PYTHONDONTWRITEBYTECODE=1 python3 -B "$HELPER" \
  --project --observation "$LANE_OBSERVATION")" || {
    printf 'script_131_t12_routing=blocked;reason=projection_validation_failed\n' >&2
    exit 2
  }
grep -Fxq 'projected_mrr_at_20=0.919306;projected_fraction=6619/7200;strict_target=greater_than_0.91;fresh_measurement_required=true' <<<"$projection" || {
  printf 'script_131_t12_routing=blocked;reason=projection_contract_invalid\n' >&2
  exit 2
}

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_mode" == true ]]; then
  printf '%s\n' \
    'purpose=validate_t12_declared_identifier_page_routing_qualification' \
    "script_sha256=$script_sha256;helper_sha256=$HELPER_SHA256;decision_list_sha256=$DECISIONS_SHA256" \
    "script_130_report_sha256=$SCRIPT_130_REPORT_SHA256;script_130_artifact_sha256=$SCRIPT_130_ARTIFACT_SHA256;lane_observation_sha256=$LANE_OBSERVATION_SHA256" \
    "$projection" \
    'native_test_count=379;database_contact=false;model_contact=false;database_write=false;credential_read=false' \
    'script_131_t12_routing_source=pass'
  exit 0
fi

umask 077
work_root="$(mktemp -d /tmp/ishikawa-script-131.XXXXXX)"
report_path=''
database_password=''
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  database_password=''
  unset database_password ISHIKAWA_POSTGRESQL_PASSWORD
  [[ "$work_root" == /tmp/ishikawa-script-131.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  [[ -z "$report_path" ]] || chmod 0600 "$report_path" 2>/dev/null || true
  exit "$status"
}
trap cleanup EXIT

mkdir -p -- "$REPORT_ROOT"
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" ]] || {
  printf 'script_131_t12_routing=blocked;reason=report_directory_unsafe\n' >&2
  exit 1
}
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/t12_routing_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
block() { emit "script_131_t12_routing=blocked;reason=$1"; exit 1; }
trap 'block interrupted_by_operator' INT
trap 'block terminated_by_signal' TERM

emit 'purpose=qualify_t12_declared_identifier_page_routing'
emit "started_utc=$timestamp;script_sha256=$script_sha256;helper_sha256=$HELPER_SHA256"
emit "script_130_report_sha256=$SCRIPT_130_REPORT_SHA256;script_130_artifact_sha256=$SCRIPT_130_ARTIFACT_SHA256;lane_observation_sha256=$LANE_OBSERVATION_SHA256"
emit 'authorized_actions=run_native_tests_read_active_citation_declarations_and_pages_in_repeatable_read_transaction_recompute_content_free_projection'
emit 'non_actions=no_database_write_no_nomic_or_gemma_contact_no_profile_schema_package_service_or_forwarding_change'

test_output="$work_root/native-tests.txt"
emit 'milestone=native_tests;state=start;expected_tests=379'
if ! PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B -m unittest discover \
    -s "$TEST_ROOT" -p 'test_*.py' >"$test_output" 2>&1; then
  block native_tests_failed
fi
grep -Fq 'Ran 379 tests' "$test_output" && grep -Fxq 'OK' "$test_output" \
  || block native_test_contract_invalid
emit 'milestone=native_tests;state=pass;tests=379;failures=0;errors=0'

pg_isready -q -h 127.0.0.1 -p 5432 -d rag_catalog -t 5 \
  || block local_postgresql_unavailable
if [[ -n "${ISHIKAWA_POSTGRESQL_PASSWORD:-}" ]]; then
  database_password="$ISHIKAWA_POSTGRESQL_PASSWORD"
else
  printf 'rag_retrieval PostgreSQL password (input hidden): ' >/dev/tty
  IFS= read -r -s database_password </dev/tty || block secret_input_failed
  printf '\n' >/dev/tty
fi
(( ${#database_password} >= 1 && ${#database_password} <= 4096 )) \
  || block secret_length_invalid
export ISHIKAWA_POSTGRESQL_PASSWORD="$database_password"

helper_output="$work_root/helper.stdout"
helper_error="$work_root/helper.stderr"
emit 'milestone=declared_identifier_page_routes;state=start;routes=5'
if ! PYTHONDONTWRITEBYTECODE=1 python3 -B "$HELPER" --run \
    --python-root "$PYTHON_ROOT" --observation "$LANE_OBSERVATION" \
    >"$helper_output" 2>"$helper_error"; then
  database_password=''
  unset ISHIKAWA_POSTGRESQL_PASSWORD
  reason="$(sed -nE 's/^t12_declared_identifier_page_routing=blocked;reason=([A-Za-z0-9_]+)$/\1/p' "$helper_error" | tail -n 1)"
  [[ -n "$reason" ]] || reason=unclassified_helper_failure
  block "$reason"
fi
database_password=''
unset ISHIKAWA_POSTGRESQL_PASSWORD
for marker in \
  'declared_identifier=99_TST_2005;unique_owner=true;page_routes=5/5;unknown_owner_fallback=true' \
  'projected_mrr_at_20=0.919306;projected_fraction=6619/7200;strict_target=greater_than_0.91;fresh_measurement_required=true' \
  'database_boundary=repeatable_read_read_only;database_write=false;nomic_contact=false;gemma_contact=false' \
  't12_declared_identifier_page_routing=pass'; do
  grep -Fxq "$marker" "$helper_output" || block helper_pass_contract_invalid
done
emit 'milestone=declared_identifier_page_routes;state=pass;routes=5;unique_owner=true;unknown_owner_fallback=true'
emit "$projection"
emit 'database_boundary=repeatable_read_read_only;database_write=false;nomic_contact=false;gemma_contact=false;credentials_retained=false'
emit "script_131_t12_routing=pass;next_gate=remeasure_extended_mrr_with_t12;local_report=$report_path"
