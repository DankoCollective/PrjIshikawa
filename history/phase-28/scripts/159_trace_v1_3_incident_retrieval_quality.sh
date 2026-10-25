#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Replay the observed synthetic controlled-materials incident question through
#   the unchanged Ishikawa v1.3 retrieval path and expose why sufficiency stops.
#
# Mental model:
#   Bind the qualified v1.3 candidate; run one first-turn deterministic query;
#   capture exact, lexical, vector, fused, relationship, lexeme, and final gate
#   observations; and retain a private synthetic-only diagnostic artifact. The
#   replay calls Nomic once and Gemma's tokenizer, but never calls Gemma scope,
#   query resolution, or answer generation.
#
# Inputs or prerequisites:
#   The Script 157-qualified local source; the accepted six-document synthetic
#   corpus in running local PostgreSQL; operator-managed Gemma and Nomic forwards
#   on 127.0.0.1:8000/8001; and three operator-entered credentials. The local
#   v1.3 preview may remain running. No credential is accepted on the command
#   line, printed, retained, or read from another process.
#
# Outputs or artifact lane:
#   One private-lane synthetic-only JSON artifact under
#   local/artifacts/ishikawa/v1.3-answer-quality-trace and one content-free
#   report under local/reports/ishikawa-v1.3-answer-quality-trace. The database
#   transaction is repeatable-read and read-only. No source, configuration,
#   corpus, service, package, accepted release, or remote host is changed.
#
# Usage:
#   In a second terminal while the local v1.3 preview and model forwards run:
#   bash ./phase-28-apisachi-tokuli/scripts/159_trace_v1_3_incident_retrieval_quality.sh --run

usage() {
  sed -n '3,35p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Perform the one-question read-only live replay.' \
    '  --validate-only Validate inputs, structure, and helper self-tests only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly CONFIG_ROOT="$PRODUCT_ROOT/config/templates"
readonly HELPER="$SCRIPT_DIR/trace_v1_3_incident_retrieval_quality.py"
readonly SCRIPT_157="$SCRIPT_DIR/157_qualify_v1_3_product_presentation_and_diagnostics.sh"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v1.3-answer-quality-trace"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.3-answer-quality-trace"
readonly GEMMA_HEALTH_URL='http://127.0.0.1:8000/health'
readonly NOMIC_HEALTH_URL='http://127.0.0.1:8001/health'
readonly EXPECTED_HOST='DankoSurface'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      printf 'script_159_v1_3_incident_retrieval_quality=blocked;reason=argument_invalid\n' >&2
      usage >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_159_v1_3_incident_retrieval_quality=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for command_name in \
  bash chmod curl date dirname hostname mkdir mktemp pg_isready python3 rm sed \
  sha256sum stat tee; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'script_159_v1_3_incident_retrieval_quality=blocked;reason=local_command_missing;command=%s\n' \
      "$command_name" >&2
    exit 2
  }
done

readonly -a REQUIRED_PATHS=(
  "$HELPER"
  "$SCRIPT_157"
  "$PYTHON_ROOT/ishikawa/__init__.py"
  "$PYTHON_ROOT/ishikawa/postgres_retrieval.py"
  "$PYTHON_ROOT/ishikawa/relevance.py"
  "$PYTHON_ROOT/ishikawa/sufficiency.py"
  "$CONFIG_ROOT/api_profile.yaml"
  "$CONFIG_ROOT/deployment.yaml"
  "$CONFIG_ROOT/method_profile.yaml"
  "$CONFIG_ROOT/relevance_profile.yaml"
  "$CONFIG_ROOT/sufficiency_profile.yaml"
  "$CONFIG_ROOT/runtime_dependencies.yaml"
)
for required_path in "${REQUIRED_PATHS[@]}"; do
  [[ -f "$required_path" && ! -L "$required_path" && -r "$required_path" ]] || {
    printf 'script_159_v1_3_incident_retrieval_quality=blocked;reason=required_input_unsafe\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}" "$SCRIPT_157"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
  "$HELPER"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$HELPER" --self-test >/dev/null

candidate_validation="$({ bash "$SCRIPT_157" --validate-only; } 2>&1)" || {
  printf 'script_159_v1_3_incident_retrieval_quality=blocked;reason=qualified_candidate_validation_failed\n' >&2
  exit 1
}
grep -Fq 'script_157_v1_3_product_presentation_diagnostics=pass' <<<"$candidate_validation" || {
  printf 'script_159_v1_3_incident_retrieval_quality=blocked;reason=qualified_candidate_identity_mismatch\n' >&2
  exit 1
}

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | sed 's/[[:space:]].*$//')"
helper_sha256="$(sha256sum "$HELPER" | sed 's/[[:space:]].*$//')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_v1_3_incident_retrieval_quality_trace' \
    "script_sha256=$script_sha256;helper_sha256=$helper_sha256" \
    'helper_self_test=pass;qualified_candidate=pass' \
    'database_contact=false;model_contact=false;credential_read=false;service_changed=false;corpus_changed=false;package_changed=false' \
    'script_159_v1_3_incident_retrieval_quality=pass'
  exit 0
fi

report_path=''
artifact_path=''
temporary_root=''
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
  emit "script_159_v1_3_incident_retrieval_quality=blocked;reason=$1"
  exit 1
}

cleanup() {
  local initial_status="$?"
  trap - EXIT HUP INT TERM
  set +e
  if (( initial_status != 0 )) && [[ "$failure_recorded" != true ]]; then
    emit "script_159_v1_3_incident_retrieval_quality=blocked;reason=unexpected_failure;exit_code=$initial_status"
  fi
  unset ISHIKAWA_GEMMA_API_KEY ISHIKAWA_NOMIC_API_KEY ISHIKAWA_POSTGRESQL_PASSWORD
  if [[ -n "$temporary_root" && "$temporary_root" == /tmp/ishikawa-v1-3-answer-quality-trace.* ]]; then
    rm -rf -- "$temporary_root"
  fi
  if [[ -n "$report_path" && -f "$report_path" ]]; then
    printf 'local_report=%s;local_report_sha256=%s\n' \
      "$report_path" "$(sha256sum "$report_path" | sed 's/[[:space:]].*$//')"
  fi
  exit "$initial_status"
}
trap cleanup EXIT HUP INT TERM

umask 077
mkdir -p -- "$ARTIFACT_ROOT" "$REPORT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/v1_3_incident_retrieval_quality_${timestamp}_XXXXXX.txt")"
artifact_path="$(mktemp "$ARTIFACT_ROOT/v1_3_incident_retrieval_quality_${timestamp}_XXXXXX.json")"
rm -f -- "$artifact_path"
temporary_root="$(mktemp -d /tmp/ishikawa-v1-3-answer-quality-trace.XXXXXX)"
chmod 0600 "$report_path" 2>/dev/null || true

emit 'purpose=trace_v1_3_incident_retrieval_quality'
emit "started_utc=$timestamp;script_sha256=$script_sha256;helper_sha256=$helper_sha256"
emit 'authorized_actions=one_synthetic_query_replay_one_nomic_embedding_gemma_tokenization_repeatable_read_database_queries_write_private_synthetic_diagnostic_and_content_free_report'
emit 'non_actions=no_scope_call_no_query_resolution_model_call_no_answer_generation_no_database_write_no_corpus_change_no_service_change_no_remote_host_contact_no_package_change_no_secret_retention_no_embedding_vector_retention_no_document_text_retention'

[[ "$(hostname -s)" == "$EXPECTED_HOST" ]] || block local_host_identity_mismatch
pg_isready --quiet --host 127.0.0.1 --port 5432 --dbname rag_catalog --timeout 2 \
  || block local_postgresql_unavailable
gemma_status="$(curl --silent --output /dev/null --write-out '%{http_code}' --connect-timeout 5 --max-time 10 "$GEMMA_HEALTH_URL" 2>/dev/null || true)"
nomic_status="$(curl --silent --output /dev/null --write-out '%{http_code}' --connect-timeout 5 --max-time 10 "$NOMIC_HEALTH_URL" 2>/dev/null || true)"
[[ "$gemma_status" == 200 ]] || block gemma_forward_unavailable
[[ "$nomic_status" == 200 ]] || block nomic_forward_unavailable
emit 'milestone=readiness;state=pass;postgresql=pass;gemma_tokenizer=pass;nomic=pass'

read_secret() {
  local prompt_label="$1"
  local destination_name="$2"
  local secret_value=''
  [[ -r /dev/tty && -w /dev/tty ]] || block interactive_terminal_unavailable
  IFS= read -r -s -p "$prompt_label: " secret_value </dev/tty || block secret_entry_failed
  printf '\n' >/dev/tty
  [[ -n "$secret_value" && ${#secret_value} -le 16384 \
      && "$secret_value" != *$'\n'* && "$secret_value" != *$'\r'* ]] \
    || block secret_value_invalid
  printf -v "$destination_name" '%s' "$secret_value"
  secret_value=''
}

read_secret 'DankoSurface local rag_retrieval PostgreSQL password' ISHIKAWA_POSTGRESQL_PASSWORD
read_secret 'Gemma API key' ISHIKAWA_GEMMA_API_KEY
read_secret 'Nomic API key' ISHIKAWA_NOMIC_API_KEY
export ISHIKAWA_GEMMA_API_KEY ISHIKAWA_NOMIC_API_KEY ISHIKAWA_POSTGRESQL_PASSWORD
emit 'milestone=credentials;state=accepted;values_logged=false;values_retained=false'

diagnostic_stdout="$temporary_root/diagnostic.stdout"
diagnostic_stderr="$temporary_root/diagnostic.stderr"
emit 'milestone=replay;state=start;query_class=synthetic_incident_controlled_materials'
set +e
PYTHONDONTWRITEBYTECODE=1 python3 -B "$HELPER" --run \
  --python-root "$PYTHON_ROOT" \
  --config-root "$CONFIG_ROOT" \
  --output "$artifact_path" \
  >"$diagnostic_stdout" 2>"$diagnostic_stderr"
diagnostic_status="$?"
set -e
if (( diagnostic_status != 0 )); then
  emit "milestone=replay;state=blocked;failure_output_sha256=$(sha256sum "$diagnostic_stderr" | sed 's/[[:space:]].*$//');raw_failure_retained=false"
  block replay_failed
fi
[[ -f "$artifact_path" && ! -L "$artifact_path" && -s "$artifact_path" ]] \
  || block diagnostic_artifact_absent
chmod 0600 "$artifact_path" 2>/dev/null || true
while IFS= read -r diagnostic_line; do
  case "$diagnostic_line" in
    purpose=*|sufficiency_status=*|relevance_support=*|relaxing_only_relevance_gate_would_reach_generation=*|observation_identity=*|incident_retrieval_quality_trace=pass)
      emit "$diagnostic_line"
      ;;
    *) block diagnostic_output_invalid ;;
  esac
done <"$diagnostic_stdout"
emit "artifact_path=$artifact_path;artifact_mode=$(stat -c '%a' "$artifact_path")"
emit 'milestone=replay;state=pass;database_write=false;gemma_generation=false;corpus_changed=false'
emit 'script_159_v1_3_incident_retrieval_quality=pass;next_gate=review_rank_and_sufficiency_evidence'
