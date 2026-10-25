#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Rebuild synthetic corpus v2 with its physical page-one references aligned,
#   create the isolated metadata-routing and compatible-sibling candidate, and
#   measure it before any ingestion or production-profile change.
#
# Mental model:
#   The v2 truth file is a scorer answer key only. It is never ingested or sent
#   to Gemma. Generate and qualify v2 twice, add bounded sibling assemblies,
#   embed through the existing loopback Nomic service, run PostgreSQL lexical
#   ranking in a private temporary cluster, and enforce the strict body/header
#   promotion gate.
#
# Boundaries:
#   No accepted database contact, corpus ingestion, Gemma call, black-corpus
#   access, service change, package change, accepted-release change, or corpus
#   v1 mutation. Production retrieval remains unchanged regardless of result.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/164_measure_v2_metadata_routing_and_sibling_assembly.sh --run

usage() {
  sed -n '3,31p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Build, embed, and measure the isolated v2 candidate.' \
    '  --validate-only Validate bound inputs and local contracts only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly V1_GENERATOR="$REPO_ROOT/local/artifacts/org_lab/synthetic_corpus_v1/generate_synthetic_corpus.py"
readonly V2_GENERATOR="$PHASE_ROOT/reference/generate_synthetic_corpus_v2.py"
readonly V1_BODY_CASES="$PHASE_ROOT/reference/ishikawa-extended-retrieval-mrr-cases-v1.1.json"
readonly V2_BODY_CASES="$PHASE_ROOT/reference/ishikawa-synthetic-corpus-v2-body-mrr-cases.json"
readonly HEADER_CASES="$PHASE_ROOT/reference/ishikawa-synthetic-corpus-v2-header-cases.json"
readonly CAPTURE="$SCRIPT_DIR/capture-pdf-extraction-observations.py"
readonly QUALIFIER="$SCRIPT_DIR/qualify_synthetic_corpus_v2.py"
readonly CANDIDATE_BUILDER="$SCRIPT_DIR/build_synthetic_corpus_v2_retrieval_candidate.py"
readonly EMBEDDER="$SCRIPT_DIR/embed_document_candidates_via_endpoint.py"
readonly EVALUATOR="$SCRIPT_DIR/measure_synthetic_corpus_v2_candidate_profile.py"
readonly BASE_EVALUATOR="$SCRIPT_DIR/measure_synthetic_corpus_v2_without_ingestion.py"
readonly SCRIPT_163_REPORT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-corrected-preingestion/corrected_corpus_v2_remeasurement_20261022T183418Z_Pj1VNB.txt"
readonly SCRIPT_163_OBSERVATION="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-corrected-preingestion/corrected_corpus_v2_retrieval_observation_20261022T183418Z.json"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-routing-assembly"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-routing-assembly"
readonly INITDB='/usr/lib/postgresql/16/bin/initdb'
readonly PG_CTL='/usr/lib/postgresql/16/bin/pg_ctl'
readonly NOMIC_HEALTH_URL='http://127.0.0.1:8001/health'
readonly NOMIC_EMBEDDING_URL='http://127.0.0.1:8001/v1/embeddings'
readonly NOMIC_TOKENIZER_URL='http://127.0.0.1:8001/tokenize'
readonly TEMPORARY_POSTGRESQL_PORT=65432
readonly EXPECTED_HOST='DankoSurface'
readonly EXPECTED_OS_ID='ubuntu'
readonly EXPECTED_OS_VERSION='24.04'
readonly EXPECTED_ARCHITECTURE='aarch64'
readonly EXPECTED_ATOMIC_CANDIDATES=139
readonly EXPECTED_ASSEMBLIES=24
readonly EXPECTED_CANDIDATES=163

readonly DECISIONS_SHA256='1ca24195dfff1445b523134d797483eb2af76b115962d4285a7b96f8e146b6b2'
readonly V1_GENERATOR_SHA256='1e17cacd16a9f0792262311816b2952fbd6707e96b5928c6af1139674c54c843'
readonly V2_GENERATOR_SHA256='749d38f40690c0affb3916ad9a5d7b29d614a5bd22fc1497dd003275647b0696'
readonly V1_BODY_CASES_SHA256='14814166168c4dfd97e85668a29fd11538e2cf585a0176fdcd50f072ef5958ce'
readonly V2_BODY_CASES_SHA256='47882a93996ef1d8331606c173c85f2076e457c989c9ab3cd6bad31d5ce5613e'
readonly HEADER_CASES_SHA256='a873a61b59de0a8ea082c3fc0c987ab9cf7b97d79ed843832be354af8eae6e2c'
readonly CAPTURE_SHA256='a303e63d1a2329ddec39d563b5a7bdddea5bd7d720206544744876171a5371e2'
readonly QUALIFIER_SHA256='6b0e64b55039c573a4bbd16c2790fb3bca4bfa4650cb7c348c91832d14e54d4a'
readonly CANDIDATE_BUILDER_SHA256='aaf54e20391c5ae2e6d0139f962aff5ec3e9b2e8a82dc71d7c7f27fdf9fffd8d'
readonly EMBEDDER_SHA256='8f3c23ca30904dfb48a37f3366fd4b7873769bb92a527479fec5696f7fc456dc'
readonly EVALUATOR_SHA256='8d8507993c3ad266d3c487a71415b6606db73a0916d3920a8c91e03fcd1327bb'
readonly BASE_EVALUATOR_SHA256='eb9eb9f3adbf10ebd3679bdba5a0befb9b2d1ed48957ab00e2b0a88f313680af'
readonly SCRIPT_163_REPORT_SHA256='2b60b35120d6595df7dbe94e589e4506732c6e6f848892d72ecb59524380908e'
readonly SCRIPT_163_OBSERVATION_SHA256='4378ffa79fe61814758d9dc982b836cb91f1f13c09c858a9af10f70b897b5bef'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      printf 'script_164_v2_metadata_routing_sibling_assembly=blocked;reason=argument_invalid\n' >&2
      usage >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'script_164_v2_metadata_routing_sibling_assembly=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for command_name in awk bash chmod cmp curl date diff dirname dpkg-query find \
  grep hostname id kill mkdir mktemp mv pdfinfo pdftotext python3 rm sed \
  sha256sum sleep sort stat tee tr uname; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'script_164_v2_metadata_routing_sibling_assembly=blocked;reason=local_command_missing;command=%s\n' \
      "$command_name" >&2
    exit 2
  }
done

check_file() {
  local path="$1" expected_sha256="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] || {
    printf 'script_164_v2_metadata_routing_sibling_assembly=blocked;reason=%s_unsafe\n' "$label" >&2
    exit 2
  }
  [[ "$(sha256sum "$path" | awk '{print $1}')" == "$expected_sha256" ]] || {
    printf 'script_164_v2_metadata_routing_sibling_assembly=blocked;reason=%s_identity_changed\n' "$label" >&2
    exit 2
  }
}

check_file "$DECISIONS" "$DECISIONS_SHA256" decisions
check_file "$V1_GENERATOR" "$V1_GENERATOR_SHA256" v1_generator
check_file "$V2_GENERATOR" "$V2_GENERATOR_SHA256" v2_generator
check_file "$V1_BODY_CASES" "$V1_BODY_CASES_SHA256" v1_body_cases
check_file "$V2_BODY_CASES" "$V2_BODY_CASES_SHA256" v2_body_cases
check_file "$HEADER_CASES" "$HEADER_CASES_SHA256" header_cases
check_file "$CAPTURE" "$CAPTURE_SHA256" extraction_capture
check_file "$QUALIFIER" "$QUALIFIER_SHA256" corpus_qualifier
check_file "$CANDIDATE_BUILDER" "$CANDIDATE_BUILDER_SHA256" candidate_builder
check_file "$EMBEDDER" "$EMBEDDER_SHA256" embedding_producer
check_file "$EVALUATOR" "$EVALUATOR_SHA256" candidate_evaluator
check_file "$BASE_EVALUATOR" "$BASE_EVALUATOR_SHA256" base_evaluator
check_file "$SCRIPT_163_REPORT" "$SCRIPT_163_REPORT_SHA256" script_163_report
check_file "$SCRIPT_163_OBSERVATION" "$SCRIPT_163_OBSERVATION_SHA256" script_163_observation
for executable in "$INITDB" "$PG_CTL"; do
  [[ -f "$executable" && ! -L "$executable" && -x "$executable" ]] || {
    printf 'script_164_v2_metadata_routing_sibling_assembly=blocked;reason=postgresql_16_binary_unsafe\n' >&2
    exit 2
  }
done

grep -Fxq \
  'script_163_remeasure_corrected_corpus_v2=pass;measurement_gate=not_met;next_gate=review_corrected_v2_rank_failures_before_ingestion' \
  "$SCRIPT_163_REPORT" || {
  printf 'script_164_v2_metadata_routing_sibling_assembly=blocked;reason=script_163_not_bound\n' >&2
  exit 1
}
for decision in V13-28 V13-29; do
  grep -Fq "| \`$decision\` " "$DECISIONS" || {
    printf 'script_164_v2_metadata_routing_sibling_assembly=blocked;reason=decision_not_frozen;decision=%s\n' \
      "$decision" >&2
    exit 1
  }
done

PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$V1_BODY_CASES" "$V2_BODY_CASES" "$SCRIPT_163_OBSERVATION" <<'PY'
import json
import pathlib
import sys

v1 = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
v2 = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
observation = json.loads(pathlib.Path(sys.argv[3]).read_text(encoding="utf-8"))
assert v2["evaluation_only"] is True
assert v2["excluded_from_corpus_ingestion"] is True
assert v2["excluded_from_generation_context"] is True
v1_cases = {item["case_id"]: item for item in v1["cases"]}
v2_cases = {item["case_id"]: item for item in v2["cases"]}
assert set(v1_cases) == set(v2_cases) == {f"E-{index:03d}" for index in range(1, 61)}
changed = {case_id for case_id in v1_cases if v1_cases[case_id] != v2_cases[case_id]}
assert changed == {"E-010", "E-011", "E-012"}
for case_id in changed:
    assert v1_cases[case_id]["relevant_evidence"][0]["page"] == 2
    assert v2_cases[case_id]["relevant_evidence"][0]["page"] == 1
assert observation["preingestion_measurement_gate"] == "not_met"
assert observation["body_metrics"]["mrr_at_20"] == "0.811825"
assert observation["header_metrics"]["mrr_at_20"] == "1.000000"
assert observation["accepted_v1_database_contact"] is False
assert observation["database_write"] is False
assert observation["gemma_contact"] is False
PY

bash -n "${BASH_SOURCE[0]}"
for python_source in "$V2_GENERATOR" "$CAPTURE" "$QUALIFIER" \
  "$CANDIDATE_BUILDER" "$EMBEDDER" "$EVALUATOR" "$BASE_EVALUATOR"; do
  PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
    'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
    "$python_source"
done
PYTHONDONTWRITEBYTECODE=1 python3 -B "$CANDIDATE_BUILDER" --self-test \
  | grep -Fxq 'synthetic_corpus_v2_retrieval_candidate_builder_self_test=pass' || {
  printf 'script_164_v2_metadata_routing_sibling_assembly=blocked;reason=candidate_builder_self_test_failed\n' >&2
  exit 2
}
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EMBEDDER" --self-test \
  | grep -Fxq 'document_embedding_endpoint_producer_self_test=pass' || {
  printf 'script_164_v2_metadata_routing_sibling_assembly=blocked;reason=embedding_producer_self_test_failed\n' >&2
  exit 2
}
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" --self-test \
  | grep -Fxq 'synthetic_corpus_v2_candidate_profile_measurement_self_test=pass' || {
  printf 'script_164_v2_metadata_routing_sibling_assembly=blocked;reason=candidate_evaluator_self_test_failed\n' >&2
  exit 2
}
PYTHONDONTWRITEBYTECODE=1 python3 -B -c 'import psycopg; assert psycopg.__version__' || {
  printf 'script_164_v2_metadata_routing_sibling_assembly=blocked;reason=psycopg_unavailable\n' >&2
  exit 2
}

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_v2_metadata_routing_and_sibling_assembly_measurement' \
    "script_sha256=$script_sha256;script_163_report_sha256=$SCRIPT_163_REPORT_SHA256" \
    "v2_generator_sha256=$V2_GENERATOR_SHA256;v2_body_cases_sha256=$V2_BODY_CASES_SHA256" \
    "candidate_builder_sha256=$CANDIDATE_BUILDER_SHA256;evaluator_sha256=$EVALUATOR_SHA256" \
    'frozen_decisions=V13-28_V13-29;truth_evaluation_only=true;truth_applied_to_black_corpus=false' \
    'accepted_v1_database_contact=false;database_write=false;model_contact=false;credential_read=false;service_changed=false;corpus_v1_changed=false;package_changed=false;production_profile_changed=false' \
    'script_164_v2_metadata_routing_sibling_assembly=pass'
  exit 0
fi

work_root=''
report_path=''
artifact_path=''
nomic_key=''
active_pid=''
private_pg_started=false
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
  emit "script_164_v2_metadata_routing_sibling_assembly=blocked;reason=$1"
  exit 1
}

cleanup() {
  local initial_status="$?"
  trap - EXIT HUP INT TERM
  set +e
  if (( initial_status != 0 )) && [[ "$failure_recorded" != true ]]; then
    emit "script_164_v2_metadata_routing_sibling_assembly=blocked;reason=unexpected_failure;exit_code=$initial_status"
  fi
  if [[ "$active_pid" =~ ^[0-9]+$ ]] && kill -0 "$active_pid" 2>/dev/null; then
    kill -TERM "$active_pid" 2>/dev/null || true
    wait "$active_pid" 2>/dev/null || true
  fi
  active_pid=''
  nomic_key=''
  unset nomic_key ISHIKAWA_NOMIC_API_KEY
  if [[ "$private_pg_started" == true && -n "$work_root" \
        && "$work_root" == /tmp/ishikawa-script-164.* ]]; then
    "$PG_CTL" -D "$work_root/postgresql" -m fast -w stop >/dev/null 2>&1 || true
  fi
  private_pg_started=false
  if [[ -n "$work_root" && "$work_root" == /tmp/ishikawa-script-164.* \
        && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  if [[ -n "$report_path" && -f "$report_path" ]]; then
    chmod 0600 "$report_path" 2>/dev/null || true
    printf 'local_report=%s;local_report_sha256=%s\n' \
      "$report_path" "$(sha256sum "$report_path" | awk '{print $1}')"
  fi
  exit "$initial_status"
}
trap cleanup EXIT HUP INT TERM

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
    && -d "$ARTIFACT_ROOT" && ! -L "$ARTIFACT_ROOT" ]] || block output_directory_unsafe
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/v2_metadata_routing_sibling_assembly_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-script-164.XXXXXX)"
artifact_path="$ARTIFACT_ROOT/v2_routing_assembly_candidate_$timestamp"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" ]] || block artifact_path_exists

actual_hostname="$(hostname -s)"
actual_os_id="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"' | awk 'NR == 1')"
actual_os_version="$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"' | awk 'NR == 1')"
actual_architecture="$(uname -m)"
local_user="$(id -un)"

emit 'purpose=measure_v2_metadata_routing_and_compatible_sibling_assembly_without_ingestion'
emit "started_utc=$timestamp;hostname=$actual_hostname;os_version=$actual_os_version;architecture=$actual_architecture"
emit "script_sha256=$script_sha256;script_163_report_sha256=$SCRIPT_163_REPORT_SHA256;script_163_observation_sha256=$SCRIPT_163_OBSERVATION_SHA256"
emit "v2_generator_sha256=$V2_GENERATOR_SHA256;v2_body_cases_sha256=$V2_BODY_CASES_SHA256;header_cases_sha256=$HEADER_CASES_SHA256"
emit "candidate_builder_sha256=$CANDIDATE_BUILDER_SHA256;embedder_sha256=$EMBEDDER_SHA256;evaluator_sha256=$EVALUATOR_SHA256"
emit 'authorized_actions=generate_synthetic_v2_twice_extract_normalize_build_experimental_candidates_call_existing_loopback_nomic_start_private_temporary_postgresql_measure_and_retain_local_evidence'
emit 'non_actions=no_accepted_v1_database_contact_no_ingestion_no_database_write_no_gemma_contact_no_black_corpus_access_no_remote_host_contact_no_service_change_no_package_change_no_accepted_release_change_no_production_profile_change_no_secret_retention_no_question_text_retention_no_query_vector_retention'
emit 'truth_usage=evaluation_only;truth_ingested=false;truth_sent_to_gemma=false;truth_applied_to_black_corpus=false'

[[ "$actual_hostname" == "$EXPECTED_HOST" \
    && "$actual_os_id" == "$EXPECTED_OS_ID" \
    && "$actual_os_version" == "$EXPECTED_OS_VERSION" \
    && "$actual_architecture" == "$EXPECTED_ARCHITECTURE" ]] || block local_host_identity_mismatch
[[ "$(dpkg-query -W -f='${Version}' poppler-utils)" == '24.02.0-1ubuntu9.10' ]] \
  || block poppler_package_identity_mismatch
[[ "$(pdfinfo -v 2>&1 | sed -n '1s/.* //p')" == '24.02.0' ]] \
  || block pdfinfo_identity_mismatch
[[ "$(pdftotext -v 2>&1 | sed -n '1s/.* //p')" == '24.02.0' ]] \
  || block pdftotext_identity_mismatch
nomic_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
  --connect-timeout 5 --max-time 10 "$NOMIC_HEALTH_URL" 2>/dev/null || true)"
[[ "$nomic_status" == 200 ]] || block nomic_forward_unavailable
emit 'milestone=readiness;state=pass;nomic=pass;gemma_required=false;accepted_postgresql_required=false'

corpus_a="$work_root/corpus-a"
corpus_b="$work_root/corpus-b"
emit 'milestone=corpus_generation;state=start;repetitions=2'
python3 -B "$V2_GENERATOR" --v1-generator "$V1_GENERATOR" --output-root "$corpus_a" \
  >"$work_root/generator-a.txt" 2>&1 || block corpus_generation_first_failed
python3 -B "$V2_GENERATOR" --v1-generator "$V1_GENERATOR" --output-root "$corpus_b" \
  >"$work_root/generator-b.txt" 2>&1 || block corpus_generation_repeat_failed
grep -Fxq \
  'synthetic_corpus_v2_generation=pass;documents=6;pages=26;departments=4;mastheads=6;header_fields=6;page_reference_rewrites=3' \
  "$work_root/generator-a.txt" || block corpus_generation_marker_absent
diff -u \
  <(cd "$corpus_a" && find . -type f -print | LC_ALL=C sort) \
  <(cd "$corpus_b" && find . -type f -print | LC_ALL=C sort) \
  >/dev/null || block corpus_file_inventory_not_repeatable
while IFS= read -r relative_path; do
  cmp --silent "$corpus_a/$relative_path" "$corpus_b/$relative_path" \
    || block corpus_bytes_not_repeatable
done < <(cd "$corpus_a" && find . -type f -printf '%P\n' | LC_ALL=C sort)
for pdf_path in "$corpus_a"/source/*.pdf; do
  pdftotext -layout "$pdf_path" - >>"$work_root/v2-extracted-text.txt" \
    || block generated_pdf_text_check_failed
done
[[ "$(grep -Fc '99 TST 2002, Page 2' "$work_root/v2-extracted-text.txt" || true)" == 0 ]] \
  || block stale_page_reference_retained
[[ "$(grep -Fc '99 TST 2002, Page 1' "$work_root/v2-extracted-text.txt" || true)" == 2 ]] \
  || block corrected_page_reference_inventory_invalid
PYTHONDONTWRITEBYTECODE=1 python3 -B - "$corpus_a/evaluation/header_acceptance_truth.json" <<'PY'
import json
import pathlib
import sys
value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert value["page_reference_rewrites"] == {
    "count": 3, "document": "99 TST 2002", "from_page": 2, "to_page": 1,
}
assert value["accepted_v1_mutated"] is False
PY
emit 'milestone=corpus_generation;state=pass;documents=6;pages=26;byte_repeatable=true;page_reference_rewrites=3;stale_page_references=0'

capture_root="$work_root/extraction"
capture_archive="$work_root/extraction.tar"
emit 'milestone=pdf_extraction;state=start;repetitions=2'
python3 -B "$CAPTURE" \
  --archive "$capture_archive" \
  --expected-hostname "$EXPECTED_HOST" \
  --expected-os-version "$EXPECTED_OS_VERSION" \
  --input-dir "$corpus_a/source" \
  --output-dir "$capture_root" \
  --source-manifest "$corpus_a/source_manifest.json" \
  >"$work_root/capture.txt" 2>&1 || block pdf_extraction_failed
grep -Fxq 'pdf_extraction_capture=pass' "$work_root/capture.txt" \
  || block pdf_extraction_marker_absent
grep -Fxq 'source_documents=6;source_pages=26;observed_blank_pages=0' "$work_root/capture.txt" \
  || block pdf_extraction_inventory_mismatch
emit 'milestone=pdf_extraction;state=pass;documents=6;pages=26;blank_pages=0;repeatable=true'

qualification_a="$work_root/qualification-a"
qualification_b="$work_root/qualification-b"
mkdir -p -- "$qualification_a" "$qualification_b"
emit 'milestone=normalization_and_atomic_chunking;state=start;repetitions=2'
for qualification_root in "$qualification_a" "$qualification_b"; do
  PYTHONDONTWRITEBYTECODE=1 python3 -B "$QUALIFIER" \
    --python-root "$PYTHON_ROOT" \
    --archive "$capture_archive" \
    --source-manifest "$corpus_a/source_manifest.json" \
    --truth "$corpus_a/evaluation/header_acceptance_truth.json" \
    --normalized-output "$qualification_root/normalized.json" \
    --chunks-output "$qualification_root/chunks.json" \
    >"$qualification_root/result.txt" 2>&1 \
    || block normalization_and_atomic_chunking_failed
done
cmp --silent "$qualification_a/normalized.json" "$qualification_b/normalized.json" \
  || block normalized_bytes_not_repeatable
cmp --silent "$qualification_a/chunks.json" "$qualification_b/chunks.json" \
  || block atomic_chunk_bytes_not_repeatable
grep -Fq \
  'header_aware_corpus_v2_qualification=pass;documents=6;departments=4;candidates=139;' \
  "$qualification_a/result.txt" || block atomic_qualification_marker_absent
atomic_chunks_sha256="$(sha256sum "$qualification_a/chunks.json" | awk '{print $1}')"
emit "milestone=normalization_and_atomic_chunking;state=pass;documents=6;atomic_candidates=$EXPECTED_ATOMIC_CANDIDATES;chunks_sha256=$atomic_chunks_sha256"

candidate_a="$qualification_a/retrieval-candidate.json"
candidate_b="$qualification_b/retrieval-candidate.json"
emit 'milestone=compatible_sibling_candidate;state=start;repetitions=2'
PYTHONDONTWRITEBYTECODE=1 python3 -B "$CANDIDATE_BUILDER" \
  --input "$qualification_a/chunks.json" \
  --expected-input-sha256 "$atomic_chunks_sha256" \
  --output "$candidate_a" >"$qualification_a/builder-result.txt" 2>&1 \
  || block candidate_build_first_failed
PYTHONDONTWRITEBYTECODE=1 python3 -B "$CANDIDATE_BUILDER" \
  --input "$qualification_b/chunks.json" \
  --expected-input-sha256 "$atomic_chunks_sha256" \
  --output "$candidate_b" >"$qualification_b/builder-result.txt" 2>&1 \
  || block candidate_build_repeat_failed
cmp --silent "$candidate_a" "$candidate_b" || block candidate_bytes_not_repeatable
grep -Fxq \
  "documents=6;atomic_candidates=$EXPECTED_ATOMIC_CANDIDATES;compatible_sibling_assemblies=$EXPECTED_ASSEMBLIES;candidate_count=$EXPECTED_CANDIDATES" \
  "$qualification_a/builder-result.txt" || block candidate_inventory_invalid
candidate_sha256="$(sha256sum "$candidate_a" | awk '{print $1}')"
emit "milestone=compatible_sibling_candidate;state=pass;atomic_candidates=$EXPECTED_ATOMIC_CANDIDATES;assemblies=$EXPECTED_ASSEMBLIES;candidates=$EXPECTED_CANDIDATES;candidate_sha256=$candidate_sha256"

read_secret 'Nomic API key' nomic_key
emit 'milestone=credential;state=accepted;value_logged=false;value_retained=false'
embedding_candidate="$work_root/v2-routing-assembly-embeddings.json"
embedding_stdout="$work_root/embedding.stdout"
embedding_stderr="$work_root/embedding.stderr"
emit "milestone=document_embeddings;state=start;candidates=$EXPECTED_CANDIDATES"
embedding_started="$(date +%s)"
(
  printf '%s' "$nomic_key" | PYTHONDONTWRITEBYTECODE=1 python3 -B "$EMBEDDER" \
    --input "$candidate_a" \
    --expected-input-sha256 "$candidate_sha256" \
    --output "$embedding_candidate" \
    --embedding-url "$NOMIC_EMBEDDING_URL" \
    --tokenizer-url "$NOMIC_TOKENIZER_URL" \
    --batch-size 16 \
    --credential-stdin
) >"$embedding_stdout" 2>"$embedding_stderr" &
active_pid="$!"
if ! wait_with_heartbeat document_embeddings "$embedding_started"; then
  block document_embedding_stage_failed
fi
grep -Fxq 'document_embedding_stage=pass' "$embedding_stdout" \
  || block document_embedding_pass_marker_absent
grep -Fq "documents=6;candidates=$EXPECTED_CANDIDATES;embedding_dimension=768" "$embedding_stdout" \
  || block document_embedding_inventory_invalid
grep -Fq 'repeat_within_tolerance=true' "$embedding_stdout" \
  || block document_embedding_repeatability_invalid
[[ -f "$embedding_candidate" && ! -L "$embedding_candidate" && -s "$embedding_candidate" ]] \
  || block document_embedding_artifact_absent
embedding_sha256="$(sha256sum "$embedding_candidate" | awk '{print $1}')"
emit "milestone=document_embeddings;state=pass;elapsed_seconds=$(( $(date +%s) - embedding_started ));artifact_sha256=$embedding_sha256"

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
emit 'milestone=temporary_postgresql;state=pass;tcp_listener=false;corpus_tables=false;accepted_v1_contact=false'

observation_candidate="$work_root/v2-routing-assembly-observation.json"
measurement_stdout="$work_root/measurement.stdout"
measurement_stderr="$work_root/measurement.stderr"
emit 'milestone=retrieval_measurement;state=start;body_cases=60;header_cases=8;query_embeddings=68'
measurement_started="$(date +%s)"
export ISHIKAWA_NOMIC_API_KEY="$nomic_key"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" \
  --python-root "$PYTHON_ROOT" \
  --chunks "$candidate_a" \
  --expected-chunks-sha256 "$candidate_sha256" \
  --document-embeddings "$embedding_candidate" \
  --expected-document-embeddings-sha256 "$embedding_sha256" \
  --body-cases "$V2_BODY_CASES" \
  --expected-body-cases-sha256 "$V2_BODY_CASES_SHA256" \
  --header-cases "$HEADER_CASES" \
  --expected-header-cases-sha256 "$HEADER_CASES_SHA256" \
  --embedding-url "$NOMIC_EMBEDDING_URL" \
  --tokenizer-url "$NOMIC_TOKENIZER_URL" \
  --postgresql-socket "$postgresql_socket" \
  --postgresql-port "$TEMPORARY_POSTGRESQL_PORT" \
  --postgresql-user "$local_user" \
  --output "$observation_candidate" \
  >"$measurement_stdout" 2>"$measurement_stderr" &
active_pid="$!"
unset ISHIKAWA_NOMIC_API_KEY
nomic_key=''
if ! wait_with_heartbeat retrieval_measurement "$measurement_started"; then
  block retrieval_measurement_failed
fi
grep -Fxq 'synthetic_corpus_v2_candidate_profile_measurement=pass' "$measurement_stdout" \
  || block retrieval_measurement_pass_marker_absent
[[ -f "$observation_candidate" && ! -L "$observation_candidate" \
    && -s "$observation_candidate" ]] || block retrieval_observation_absent
observation_sha256="$(sha256sum "$observation_candidate" | awk '{print $1}')"

validation_summary="$work_root/validation-summary.txt"
PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$observation_candidate" "$candidate_sha256" "$embedding_sha256" \
  "$V2_BODY_CASES_SHA256" "$HEADER_CASES_SHA256" >"$validation_summary" <<'PY'
import json
import pathlib
import sys
value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert value["artifact_kind"] == "ishikawa_synthetic_corpus_v2_candidate_profile_observation"
assert value["source_chunks_sha256"] == sys.argv[2]
assert value["source_document_embeddings_sha256"] == sys.argv[3]
assert value["body_case_set_sha256"] == sys.argv[4]
assert value["header_case_set_sha256"] == sys.argv[5]
assert value["document_count"] == 6
assert value["candidate_count"] == 163
assert value["compatible_sibling_assembly_count"] == 24
assert value["query_embedding_count"] == 68
assert len(value["cases"]) == 68
assert value["truth_usage"] == {
    "black_corpus_application": False,
    "corpus_ingestion": False,
    "evaluation_only": True,
    "generation_context": False,
    "production_retrieval_hint": False,
}
assert value["database_boundary"] == "private_temporary_postgresql_repeatable_read_read_only"
assert value["database_tables_read"] is False
assert value["database_write"] is False
assert value["accepted_v1_database_contact"] is False
assert value["gemma_contact"] is False
assert value["production_profile_changed"] is False
body = value["body_metrics"]
header = value["header_metrics"]
gate = value["preingestion_measurement_gate"]
assert gate in {"pass", "not_met"}
print(
    f"body_mrr_at_20={body['mrr_at_20']};body_relevant_at_5={body['relevant_at_5']}/60;"
    f"body_relevant_at_20={body['relevant_at_20']}/60"
)
print(
    f"header_mrr_at_20={header['mrr_at_20']};header_relevant_at_5={header['relevant_at_5']}/8;"
    f"header_required_evidence_at_20={header['required_evidence_matched_at_20']}/"
    f"{header['required_evidence_total']}"
)
print(f"preingestion_measurement_gate={gate};strict_body_target=greater_than_0.91")
PY
while IFS= read -r summary_line; do emit "$summary_line"; done <"$validation_summary"
measurement_gate="$(sed -nE 's/^preingestion_measurement_gate=(pass|not_met);.*$/\1/p' "$validation_summary")"
[[ "$measurement_gate" == pass || "$measurement_gate" == not_met ]] \
  || block retrieval_measurement_gate_invalid
emit "milestone=retrieval_measurement;state=pass;elapsed_seconds=$(( $(date +%s) - measurement_started ));artifact_sha256=$observation_sha256"

"$PG_CTL" -D "$postgresql_data" -m fast -w stop \
  >"$work_root/pg-stop.stdout" 2>"$work_root/pg-stop.stderr" \
  || block temporary_postgresql_stop_failed
private_pg_started=false
emit 'milestone=temporary_postgresql_cleanup;state=pass;cluster_retained=false;listener_retained=false'

mkdir -p -- "$corpus_a/qualification"
mv -- "$qualification_a/normalized.json" "$corpus_a/qualification/normalized.json"
mv -- "$qualification_a/chunks.json" "$corpus_a/qualification/atomic-chunks.json"
mv -- "$candidate_a" "$corpus_a/qualification/retrieval-candidate.json"
mv -- "$qualification_a/result.txt" "$corpus_a/qualification/qualifier-result.txt"
mv -- "$qualification_a/builder-result.txt" "$corpus_a/qualification/builder-result.txt"
mv -- "$capture_archive" "$corpus_a/qualification/extraction.tar"
(
  cd "$corpus_a"
  find . -type f ! -name SHA256SUMS -printf '%P\n' | LC_ALL=C sort | while IFS= read -r relative_path; do
    printf '%s  %s\n' "$(sha256sum "$relative_path" | awk '{print $1}')" "$relative_path"
  done >SHA256SUMS
)
candidate_files="$(sed -n '$=' "$corpus_a/SHA256SUMS")"
candidate_manifest_sha256="$(sha256sum "$corpus_a/SHA256SUMS" | awk '{print $1}')"
mv -- "$corpus_a" "$artifact_path"

embedding_artifact="$ARTIFACT_ROOT/v2_routing_assembly_embeddings_${timestamp}.json"
observation_artifact="$ARTIFACT_ROOT/v2_routing_assembly_observation_${timestamp}.json"
[[ ! -e "$embedding_artifact" && ! -L "$embedding_artifact" \
    && ! -e "$observation_artifact" && ! -L "$observation_artifact" ]] \
  || block retained_artifact_path_exists
mv -- "$embedding_candidate" "$embedding_artifact"
mv -- "$observation_candidate" "$observation_artifact"
chmod 0600 "$embedding_artifact" "$observation_artifact" 2>/dev/null || true
[[ "$(sha256sum "$embedding_artifact" | awk '{print $1}')" == "$embedding_sha256" \
    && "$(sha256sum "$observation_artifact" | awk '{print $1}')" == "$observation_sha256" ]] \
  || block retained_artifact_identity_mismatch

emit "candidate_artifact=$artifact_path;candidate_files=$candidate_files;candidate_manifest_sha256=$candidate_manifest_sha256"
emit "embedding_artifact=$embedding_artifact;embedding_artifact_sha256=$embedding_sha256;artifact_mode=$(stat -c '%a' "$embedding_artifact")"
emit "observation_artifact=$observation_artifact;observation_artifact_sha256=$observation_sha256;artifact_mode=$(stat -c '%a' "$observation_artifact")"
emit 'truth_evaluation_only=true;truth_ingested=false;truth_sent_to_gemma=false;truth_applied_to_black_corpus=false'
emit 'accepted_v1_database_contact=false;database_ingestion=false;database_write=false;gemma_contact=false;black_corpus_access=false;corpus_v1_changed=false;corpus_v2_published=false;service_changed=false;package_changed=false;production_profile_changed=false;credentials_retained=false'

if [[ "$measurement_gate" == pass ]]; then
  next_gate='review_v2_candidate_before_any_promotion_or_ingestion'
else
  next_gate='review_remaining_v2_candidate_rank_failures_before_promotion'
fi
emit "script_164_v2_metadata_routing_sibling_assembly=pass;measurement_gate=$measurement_gate;next_gate=$next_gate"
