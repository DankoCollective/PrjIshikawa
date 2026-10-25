#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify DankoSurface for iterative Ishikawa v1.1 retrieval tuning without
#   building a deployment package or changing the local corpus.
#
# Mental model:
#   Bind the immutable v1 fallback and frozen tuning decisions, run the complete
#   source regression suite, verify the operator-established model forwarding,
#   then inspect the local active corpus through the read-only retrieval role.
#
# Inputs or prerequisites:
#   Forwarded Gemma and Nomic health endpoints, local PostgreSQL containing the
#   accepted six-document synthetic corpus, and the rag_retrieval password. The
#   script prompts for that password if it is not already in the protected
#   ISHIKAWA_POSTGRESQL_PASSWORD environment variable.
#
# Outputs or artifact lane:
#   One content-free local readiness report. No package, model request, database
#   write, service change, credential value, vector, or corpus text is retained.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/115_qualify_local_retrieval_tuning_preflight.sh --run

usage() {
  sed -n '3,28p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run                    Run the complete local preflight.' \
    '  --validate-only          Validate source without endpoint or database contact.' \
    '  --expected-hostname NAME Exact expected local short hostname.' \
    '  --expected-os-version V  Exact expected Ubuntu major.minor version.' \
    '  --expected-architecture A Exact expected machine architecture.' \
    '  --gemma-health-url URL   Forwarded loopback Gemma health endpoint.' \
    '  --nomic-health-url URL   Forwarded loopback Nomic health endpoint.' \
    '  --postgresql-host HOST   Local PostgreSQL host; only 127.0.0.1 is accepted.' \
    '  --postgresql-port PORT   Local PostgreSQL port.' \
    '  --database NAME          Expected application database.' \
    '  --database-user ROLE     Expected read-only retrieval role.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly ISHIKAWA_ROOT="$PHASE_ROOT/Ishikawa"
readonly TEST_RUNNER="$ISHIKAWA_ROOT/scripts/run-local-validation-tests.sh"
readonly DECISION_LIST="$PHASE_ROOT/docs/ISHIKAWA_V1_1_TUNING_DECISIONS.md"
readonly V1_1_CASES="$PHASE_ROOT/reference/ishikawa-retrieval-tuning-cases-v1.1.json"
readonly SCRIPT_114_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.1-query-routing/v1_1_query_routing_20261021T150118Z_IZiiGq.txt"
readonly SCRIPT_114_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/v1.1-query-routing/request_stage_diagnostics_20261021T150118Z.json"
readonly SCRIPT_114_CHECKSUM="$SCRIPT_114_ARTIFACT.sha256"
readonly V1_ARCHIVE="$REPO_ROOT/local/artifacts/ishikawa/v1-deployment-package/ishikawa-v1-deployment-package-c848680051786b2b.tar.gz"
readonly V1_CHECKSUM="$V1_ARCHIVE.sha256"
readonly SCRIPT_114_REPORT_SHA256='4556d5ed6e149bcfb68fa36354b055a94845249d68e3b4f218de8723badddbc5'
readonly SCRIPT_114_ARTIFACT_SHA256='0a928441b4234d8fd99d18fe402b216b50c540437fdcc757f94d65e921f66727'
readonly SCRIPT_114_CHECKSUM_SHA256='9a4f5e1aeefa8820b33fde4ee2e5cdd76e3202bb5160cad6dc1ff3833954b805'
readonly V1_ARCHIVE_SHA256='c848680051786b2b3c6ac454b3f007be1632d45215ddf9c8f1d4d04b924845b1'
readonly V1_CHECKSUM_SHA256='25313c7065cfa038ba63f51deb29585e763aae0561c672057c28c86c5fe57550'
readonly V1_1_CASES_SHA256='feb2303d8433461846974015078d88ca42593636c399fc90fcd9c2e67beab6f9'
readonly ROUTING_IDENTITY='89d5e245fb19a4873c4ea5cc404952ec1771348d0dd3d5e9e76bd69979043a5e'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.1-local-tuning-preflight"

expected_hostname="${ISHIKAWA_TUNING_EXPECTED_HOSTNAME:-DankoSurface}"
expected_os_version="${ISHIKAWA_TUNING_EXPECTED_OS_VERSION:-24.04}"
expected_architecture="${ISHIKAWA_TUNING_EXPECTED_ARCHITECTURE:-aarch64}"
gemma_health_url="${ISHIKAWA_GEMMA_HEALTH_URL:-http://127.0.0.1:8000/health}"
nomic_health_url="${ISHIKAWA_NOMIC_HEALTH_URL:-http://127.0.0.1:8001/health}"
postgresql_host="${ISHIKAWA_POSTGRESQL_HOST:-127.0.0.1}"
postgresql_port="${ISHIKAWA_POSTGRESQL_PORT:-5432}"
database_name="${ISHIKAWA_POSTGRESQL_DATABASE:-rag_catalog}"
database_user="${ISHIKAWA_POSTGRESQL_USER:-rag_retrieval}"
run_authorized=false
validate_only=false

while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --expected-hostname) expected_hostname="${2:-}"; shift 2 ;;
    --expected-os-version) expected_os_version="${2:-}"; shift 2 ;;
    --expected-architecture) expected_architecture="${2:-}"; shift 2 ;;
    --gemma-health-url) gemma_health_url="${2:-}"; shift 2 ;;
    --nomic-health-url) nomic_health_url="${2:-}"; shift 2 ;;
    --postgresql-host) postgresql_host="${2:-}"; shift 2 ;;
    --postgresql-port) postgresql_port="${2:-}"; shift 2 ;;
    --database) database_name="${2:-}"; shift 2 ;;
    --database-user) database_user="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_115_local_tuning_preflight=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_115_local_tuning_preflight=blocked;reason=mode_invalid\n' >&2
  exit 2
}
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || {
  printf 'script_115_local_tuning_preflight=blocked;reason=expected_hostname_invalid\n' >&2
  exit 2
}
[[ "$expected_os_version" =~ ^[0-9]{2}\.[0-9]{2}$ ]] || {
  printf 'script_115_local_tuning_preflight=blocked;reason=expected_os_version_invalid\n' >&2
  exit 2
}
[[ "$expected_architecture" =~ ^[A-Za-z0-9_-]+$ ]] || {
  printf 'script_115_local_tuning_preflight=blocked;reason=expected_architecture_invalid\n' >&2
  exit 2
}
[[ "$gemma_health_url" == 'http://127.0.0.1:8000/health' ]] || {
  printf 'script_115_local_tuning_preflight=blocked;reason=gemma_health_url_invalid\n' >&2
  exit 2
}
[[ "$nomic_health_url" == 'http://127.0.0.1:8001/health' ]] || {
  printf 'script_115_local_tuning_preflight=blocked;reason=nomic_health_url_invalid\n' >&2
  exit 2
}
[[ "$postgresql_host" == '127.0.0.1' ]] || {
  printf 'script_115_local_tuning_preflight=blocked;reason=postgresql_host_invalid\n' >&2
  exit 2
}
[[ "$postgresql_port" =~ ^[0-9]{1,5}$ ]] && (( 10#$postgresql_port >= 1 && 10#$postgresql_port <= 65535 )) || {
  printf 'script_115_local_tuning_preflight=blocked;reason=postgresql_port_invalid\n' >&2
  exit 2
}
[[ "$database_name" == rag_catalog && "$database_user" == rag_retrieval ]] || {
  printf 'script_115_local_tuning_preflight=blocked;reason=database_identity_invalid\n' >&2
  exit 2
}

for required in awk bash basename curl date grep hostname mktemp pg_isready psql python3 rm sed sha256sum stat tee uname; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_115_local_tuning_preflight=blocked;reason=local_command_missing;command=%s\n' "$required" >&2
    exit 2
  }
done

readonly -a REQUIRED_FILES=(
  "$TEST_RUNNER"
  "$DECISION_LIST"
  "$V1_1_CASES"
  "$SCRIPT_114_REPORT"
  "$SCRIPT_114_ARTIFACT"
  "$SCRIPT_114_CHECKSUM"
  "$V1_ARCHIVE"
  "$V1_CHECKSUM"
)
for required_file in "${REQUIRED_FILES[@]}"; do
  [[ -f "$required_file" && ! -L "$required_file" && -r "$required_file" ]] || {
    printf 'script_115_local_tuning_preflight=blocked;reason=required_input_unsafe\n' >&2
    exit 2
  }
done

work_root="$(mktemp -d /tmp/ishikawa-script-115.XXXXXX)"
report_path=''
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  unset PGPASSWORD ISHIKAWA_POSTGRESQL_PASSWORD
  [[ "$work_root" == /tmp/ishikawa-script-115.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  [[ -z "$report_path" ]] || chmod 0600 "$report_path" 2>/dev/null || true
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

emit() {
  if [[ -n "$report_path" ]]; then
    printf '%s\n' "$1" | tee -a "$report_path"
  else
    printf '%s\n' "$1"
  fi
}
block() {
  emit "script_115_local_tuning_preflight=blocked;reason=$1"
  exit 1
}
check_sha256() {
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || block "$3"'_identity_changed'
}

check_sha256 "$SCRIPT_114_REPORT" "$SCRIPT_114_REPORT_SHA256" script_114_report
check_sha256 "$SCRIPT_114_ARTIFACT" "$SCRIPT_114_ARTIFACT_SHA256" script_114_artifact
check_sha256 "$SCRIPT_114_CHECKSUM" "$SCRIPT_114_CHECKSUM_SHA256" script_114_checksum
check_sha256 "$V1_ARCHIVE" "$V1_ARCHIVE_SHA256" v1_archive
check_sha256 "$V1_CHECKSUM" "$V1_CHECKSUM_SHA256" v1_checksum
check_sha256 "$V1_1_CASES" "$V1_1_CASES_SHA256" v1_1_cases
(
  cd -- "$(dirname -- "$SCRIPT_114_CHECKSUM")"
  sha256sum --check --strict "$(basename -- "$SCRIPT_114_CHECKSUM")" >/dev/null
) || block 'script_114_checksum_failed'
(
  cd -- "$(dirname -- "$V1_CHECKSUM")"
  sha256sum --check --strict "$(basename -- "$V1_CHECKSUM")" >/dev/null
) || block 'v1_checksum_failed'

for decision in T01 T02 T03 T04 T05 T06 T07; do
  grep -Fq "| \`$decision\` |" "$DECISION_LIST" || block 'tuning_decision_list_incomplete'
done
[[ "$(grep -c '| FROZEN |' "$DECISION_LIST")" == 7 ]] || block 'tuning_decision_state_invalid'
for fact in \
  "checkpoint_artifact_sha256=a9f2af44ef7368bb96c4e512168c7ecc9839f1f565bd47c3b5a717dc6386e736;v1_archive_sha256=$V1_ARCHIVE_SHA256;routing_identity=$ROUTING_IDENTITY" \
  'runtime_changed=false;database_changed=false;service_changed=false;model_contact=false;accepted_v1_changed=false' \
  'script_114_v1_1_query_routing=pass;tests=367;next_gate=assemble_and_install_v1_1_candidate;'; do
  grep -Fq "$fact" "$SCRIPT_114_REPORT" || block 'script_114_contract_failed'
done

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER"
PYTHONDONTWRITEBYTECODE=1 python3 -B - "$V1_1_CASES" <<'PY'
import json
import pathlib
import sys

value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert value["artifact_kind"] == "ishikawa_retrieval_tuning_cases"
assert value["schema_version"] == 2
assert value["synthetic_content_only"] is True
assert len(value["cases"]) == 13
by_class = {}
required = []
for case in value["cases"]:
    by_class[case["class"]] = by_class.get(case["class"], 0) + 1
    for evidence in case["required_evidence"]:
        required.append((evidence["display_name"], evidence["page"]))
assert by_class == {"responsive": 6, "nonresponsive": 6, "broad-navigation": 1}
assert len(required) == 13
assert len(set(required)) == 12
assert next(case for case in value["cases"] if case["case_id"] == "B-001")["expected_status"] == "clarification-required"
print("tuning_case_contract=pass;cases=13;responsive=6;nonresponsive=6;broad_navigation=1;required_evidence_expectations=13;unique_evidence_pairs=12")
PY

test_result="$work_root/native-tests.txt"
PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_result" 2>&1 || {
  printf 'script_115_local_tuning_preflight=blocked;reason=test_regression;diagnostic_sha256=%s;diagnostic_bytes=%s\n' \
    "$(sha256sum "$test_result" | awk '{print $1}')" "$(stat -c '%s' "$test_result")" >&2
  exit 1
}
grep -Fq 'Ran 367 tests' "$test_result" || block 'test_count_mismatch'
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_result" || block 'test_pass_marker_absent'

decision_list_sha256="$(sha256sum "$DECISION_LIST" | awk '{print $1}')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_local_retrieval_tuning_preflight_source' \
    "script_sha256=$script_sha256;decision_list_sha256=$decision_list_sha256;case_file_sha256=$V1_1_CASES_SHA256" \
    "accepted_v1_archive_sha256=$V1_ARCHIVE_SHA256;routing_identity=$ROUTING_IDENTITY" \
    'tuning_decisions=T01-T07;decision_state=frozen;native_tests=367;failures=0;errors=0' \
    'target_contact=false;model_contact=false;database_contact=false;database_changed=false;service_changed=false;package_built=false' \
    'script_115_local_tuning_preflight_source=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT"
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" ]] || block 'report_directory_unsafe'
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/local_tuning_preflight_${timestamp}_XXXXXX.txt")"
emit 'purpose=qualify_local_ishikawa_v1_1_retrieval_tuning_preflight'
emit "started_utc=$timestamp;local_report=$report_path"
emit "script_sha256=$script_sha256;decision_list_sha256=$decision_list_sha256;case_file_sha256=$V1_1_CASES_SHA256"
emit "accepted_v1_archive_sha256=$V1_ARCHIVE_SHA256;routing_identity=$ROUTING_IDENTITY"
emit 'authorized_actions=run_local_tests_check_loopback_health_read_active_corpus_counts_with_retrieval_role_retain_content_free_report'
emit 'non_actions=no_sudo_no_remote_access_no_port_forwarding_change_no_model_inference_no_database_write_no_service_change_no_package_build_no_credential_retention_no_corpus_or_vector_read'
emit 'operator_expectation=postgresql_password_prompt_if_not_exported;gemma_or_nomic_key_prompt=false;sudo_prompt=false;estimated_duration_minutes=1-2'

actual_hostname="$(hostname -s)"
actual_architecture="$(uname -m)"
actual_os="$(. /etc/os-release && printf '%s|%s' "$ID" "$VERSION_ID")"
[[ "$actual_hostname" == "$expected_hostname" ]] || block 'hostname_mismatch'
[[ "$actual_os" == "ubuntu|$expected_os_version" ]] || block 'os_identity_mismatch'
[[ "$actual_architecture" == "$expected_architecture" ]] || block 'architecture_mismatch'
emit "milestone=local_host_identity;state=pass;hostname=$actual_hostname;os_id=ubuntu;os_version=$expected_os_version;architecture=$actual_architecture"

gemma_status="$(curl -sS --fail --max-time 10 -o /dev/null -w '%{http_code}' "$gemma_health_url" 2>"$work_root/gemma-health-error.txt")" \
  || block 'gemma_forwarded_health_unavailable'
nomic_status="$(curl -sS --fail --max-time 10 -o /dev/null -w '%{http_code}' "$nomic_health_url" 2>"$work_root/nomic-health-error.txt")" \
  || block 'nomic_forwarded_health_unavailable'
[[ "$gemma_status" == 200 && "$nomic_status" == 200 ]] || block 'forwarded_health_status_invalid'
emit 'milestone=forwarded_model_health;state=pass;gemma_http_status=200;nomic_http_status=200;model_inference=false'

pg_isready -q -h "$postgresql_host" -p "$postgresql_port" -d "$database_name" -t 5 \
  || block 'local_postgresql_unavailable'

postgresql_password="${ISHIKAWA_POSTGRESQL_PASSWORD:-}"
if [[ -z "$postgresql_password" ]]; then
  [[ -t 0 ]] || block 'postgresql_password_required'
  read -r -s -p 'PostgreSQL password for rag_retrieval: ' postgresql_password
  printf '\n'
fi
[[ -n "$postgresql_password" && "$postgresql_password" != *$'\n'* && ${#postgresql_password} -le 4096 ]] \
  || block 'postgresql_password_invalid'

set +e
corpus_inventory="$({
  PGPASSWORD="$postgresql_password" psql \
    -X -q -A -t \
    -h "$postgresql_host" \
    -p "$postgresql_port" \
    -U "$database_user" \
    -d "$database_name" \
    -v ON_ERROR_STOP=1 \
    -c "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
        SELECT concat_ws('|',
          current_user,
          current_database(),
          (SELECT count(*) FROM rag_search.active_documents),
          (SELECT coalesce(sum(page_count), 0) FROM rag_search.active_documents),
          (SELECT count(*) FROM rag_search.active_chunks),
          (SELECT count(*) FROM rag_search.active_citations),
          (SELECT count(*) FROM rag_search.active_embeddings));
        ROLLBACK;"
} 2>"$work_root/postgresql-error.txt")"
postgresql_status=$?
set -e
postgresql_password=''
unset ISHIKAWA_POSTGRESQL_PASSWORD PGPASSWORD
(( postgresql_status == 0 )) || block 'local_postgresql_inventory_failed'
[[ "$corpus_inventory" == 'rag_retrieval|rag_catalog|6|27|126|126|126' ]] \
  || block 'local_synthetic_corpus_inventory_mismatch'
emit 'milestone=local_synthetic_corpus;state=pass;database=rag_catalog;role=rag_retrieval;documents=6;pages=27;chunks=126;citations=126;embeddings=126;transaction=repeatable_read_read_only'

check_sha256 "$V1_ARCHIVE" "$V1_ARCHIVE_SHA256" v1_archive_after_preflight
emit 'native_tests=367;failures=0;errors=0;tuning_cases=13;required_evidence_expectations=13;unique_evidence_pairs=12'
emit 'accepted_v1_changed=false;database_changed=false;service_changed=false;package_built=false;model_inference=false;credential_retained=false'
emit "script_115_local_tuning_preflight=pass;next_gate=implement_and_measure_read_only_mrr_evaluator;local_report=$report_path"
