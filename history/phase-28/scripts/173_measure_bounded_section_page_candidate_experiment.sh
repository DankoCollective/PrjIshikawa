#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Measure the four Script 172 section/page variants against the accepted
#   published-corpus-v2 baseline without changing any corpus or live profile.
#
# Boundaries:
#   Existing loopback Nomic only, a disposable Unix-socket PostgreSQL cluster,
#   no Gemma, no accepted database, no publication, and no profile mutation.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/173_measure_bounded_section_page_candidate_experiment.sh --run

usage() {
  sed -n '3,13p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Build, embed, and measure all four bounded variants.' \
    '  --validate-only Validate bound inputs and local contracts only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PYTHON_ROOT="$PHASE_ROOT/Ishikawa/application/python"
readonly BUILDER="$SCRIPT_DIR/build_published_v2_section_page_representatives.py"
readonly EMBEDDER="$SCRIPT_DIR/embed_document_candidates_via_endpoint.py"
readonly EVALUATOR="$SCRIPT_DIR/measure_published_v2_section_page_experiment.py"
readonly BASE_EVALUATOR="$SCRIPT_DIR/measure_synthetic_corpus_v2_without_ingestion.py"
readonly CANDIDATE_EVALUATOR="$SCRIPT_DIR/measure_synthetic_corpus_v2_candidate_profile.py"
readonly RETRIEVAL_MODULE="$PYTHON_ROOT/ishikawa/retrieval.py"
readonly SCRIPT_172_REPORT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-section-page-design/section_page_experiment_design_20261022T214310Z_irpXet.txt"
readonly DESIGN="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-section-page-design/section_page_experiment_design_20261022T214310Z_irpXet.json"
readonly DESIGN_SUMS="$DESIGN.sha256"
readonly RETAINED_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-isolated-publication/retained-derived-artifacts-20261022T204745Z"
readonly NORMALIZED="$RETAINED_ROOT/71/711997caa99c2b92ee555f7ea29e012e2fbb86e39fd65f662cd52e174ec07ead"
readonly ATOMIC_CHUNKS="$RETAINED_ROOT/22/22a4d2694938268462f0c78a79b51771abb48a8e1a23420ec0f443e1e7d8c5fd"
readonly ATOMIC_EMBEDDINGS="$RETAINED_ROOT/ff/ff040e9244a0a9213aec028715d3e52ba5ab7855c324b24c5a4abf8fcc83865f"
readonly PROMOTION_BUNDLE="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-promotion/synthetic_corpus_v2_promotion_candidate_20261022T201026Z"
readonly ACCEPTED_OBSERVATION="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-live-retrieval/isolated_v2_live_retrieval_20261022T211121Z.json"
readonly BODY_CASES="$PHASE_ROOT/reference/ishikawa-synthetic-corpus-v2-body-mrr-cases.json"
readonly HEADER_CASES="$PHASE_ROOT/reference/ishikawa-synthetic-corpus-v2-header-cases.json"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-section-page-experiment"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-section-page-experiment"
readonly INITDB='/usr/lib/postgresql/16/bin/initdb'
readonly PG_CTL='/usr/lib/postgresql/16/bin/pg_ctl'
readonly TEMPORARY_POSTGRESQL_PORT=65432
readonly NOMIC_HEALTH_URL='http://127.0.0.1:8001/health'
readonly NOMIC_EMBEDDING_URL='http://127.0.0.1:8001/v1/embeddings'
readonly NOMIC_TOKENIZER_URL='http://127.0.0.1:8001/tokenize'

readonly BUILDER_SHA256='b1ae8b3653c195b13d8e80b107b7f5169cacc22a44959706507d8cfcaba4e829'
readonly EMBEDDER_SHA256='8f3c23ca30904dfb48a37f3366fd4b7873769bb92a527479fec5696f7fc456dc'
readonly EVALUATOR_SHA256='c7fc9b1584ef8a4fb811e3e25367c36247abd31981478a6f068a54b6900f5ef0'
readonly BASE_EVALUATOR_SHA256='eb9eb9f3adbf10ebd3679bdba5a0befb9b2d1ed48957ab00e2b0a88f313680af'
readonly CANDIDATE_EVALUATOR_SHA256='8d8507993c3ad266d3c487a71415b6606db73a0916d3920a8c91e03fcd1327bb'
readonly RETRIEVAL_MODULE_SHA256='0307dba6facac397c417b5c9e4345ae1da01c3ce8ea1ba9a9b4a90a5a4353b68'
readonly SCRIPT_172_REPORT_SHA256='365f9ef85ee6e1502c62f73d3147e0e0d62c62ae9fb562f5f0f0089d52dbb1c3'
readonly DESIGN_SHA256='d6c282571cdefcf0f24945be97a3d5be32f25ced6382dfcb204c89b3d41dc55a'
readonly NORMALIZED_SHA256='711997caa99c2b92ee555f7ea29e012e2fbb86e39fd65f662cd52e174ec07ead'
readonly ATOMIC_CHUNKS_SHA256='22a4d2694938268462f0c78a79b51771abb48a8e1a23420ec0f443e1e7d8c5fd'
readonly ATOMIC_EMBEDDINGS_SHA256='ff040e9244a0a9213aec028715d3e52ba5ab7855c324b24c5a4abf8fcc83865f'
readonly RETAINED_SUMS_SHA256='fe7c37741637437539ddec542325bb9506141225414f650b81d3895f7934092b'
readonly PROMOTION_SUMS_SHA256='614c4ce64597aeed7d0d03da8dcbef0d59db052dbd3c56092a33e86fd40d42f5'
readonly ACCEPTED_OBSERVATION_SHA256='baab346b25374c44237e37787bd0ef64a1f3f447551212965777358d8c385718'
readonly BODY_CASES_SHA256='47882a93996ef1d8331606c173c85f2076e457c989c9ab3cd6bad31d5ce5613e'
readonly HEADER_CASES_SHA256='a873a61b59de0a8ea082c3fc0c987ab9cf7b97d79ed843832be354af8eae6e2c'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'reason=argument_invalid\n\nSCRIPT RESULT\nscript_173_bounded_section_page_candidate_experiment=blocked\n' >&2; exit 2 ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'reason=mode_invalid\n\nSCRIPT RESULT\nscript_173_bounded_section_page_candidate_experiment=blocked\n' >&2
  exit 2
}

for command_name in awk basename bash cmp curl date dirname grep hostname \
  id mkdir mktemp python3 rm sed sha256sum tee timeout tr uname; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'reason=local_command_missing;command=%s\n\nSCRIPT RESULT\nscript_173_bounded_section_page_candidate_experiment=blocked\n' "$command_name" >&2
    exit 2
  }
done

check_file() {
  local path="$1" expected="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] || {
    printf 'reason=%s_unsafe\n\nSCRIPT RESULT\nscript_173_bounded_section_page_candidate_experiment=blocked\n' "$label" >&2
    exit 2
  }
  [[ "$(sha256sum "$path" | awk '{print $1}')" == "$expected" ]] || {
    printf 'reason=%s_identity_changed\n\nSCRIPT RESULT\nscript_173_bounded_section_page_candidate_experiment=blocked\n' "$label" >&2
    exit 2
  }
}

check_file "$BUILDER" "$BUILDER_SHA256" builder
check_file "$EMBEDDER" "$EMBEDDER_SHA256" embedder
check_file "$EVALUATOR" "$EVALUATOR_SHA256" evaluator
check_file "$BASE_EVALUATOR" "$BASE_EVALUATOR_SHA256" base_evaluator
check_file "$CANDIDATE_EVALUATOR" "$CANDIDATE_EVALUATOR_SHA256" candidate_evaluator
check_file "$RETRIEVAL_MODULE" "$RETRIEVAL_MODULE_SHA256" retrieval_module
check_file "$SCRIPT_172_REPORT" "$SCRIPT_172_REPORT_SHA256" script_172_report
check_file "$DESIGN" "$DESIGN_SHA256" design
check_file "$NORMALIZED" "$NORMALIZED_SHA256" normalized
check_file "$ATOMIC_CHUNKS" "$ATOMIC_CHUNKS_SHA256" atomic_chunks
check_file "$ATOMIC_EMBEDDINGS" "$ATOMIC_EMBEDDINGS_SHA256" atomic_embeddings
check_file "$ACCEPTED_OBSERVATION" "$ACCEPTED_OBSERVATION_SHA256" accepted_observation
check_file "$BODY_CASES" "$BODY_CASES_SHA256" body_cases
check_file "$HEADER_CASES" "$HEADER_CASES_SHA256" header_cases
check_file "$RETAINED_ROOT/SHA256SUMS" "$RETAINED_SUMS_SHA256" retained_manifest
check_file "$PROMOTION_BUNDLE/SHA256SUMS" "$PROMOTION_SUMS_SHA256" promotion_manifest
[[ -f "$DESIGN_SUMS" && ! -L "$DESIGN_SUMS" ]] || {
  printf 'reason=design_checksum_unsafe\n\nSCRIPT RESULT\nscript_173_bounded_section_page_candidate_experiment=blocked\n' >&2
  exit 2
}
(cd -- "$(dirname -- "$DESIGN")" && sha256sum --quiet -c "$(basename -- "$DESIGN_SUMS")") || {
  printf 'reason=design_checksum_failed\n\nSCRIPT RESULT\nscript_173_bounded_section_page_candidate_experiment=blocked\n' >&2
  exit 2
}
(cd -- "$RETAINED_ROOT" && sha256sum --quiet -c SHA256SUMS) || {
  printf 'reason=retained_artifact_checksum_failed\n\nSCRIPT RESULT\nscript_173_bounded_section_page_candidate_experiment=blocked\n' >&2
  exit 2
}
(cd -- "$PROMOTION_BUNDLE" && sha256sum --quiet -c SHA256SUMS) || {
  printf 'reason=promotion_bundle_checksum_failed\n\nSCRIPT RESULT\nscript_173_bounded_section_page_candidate_experiment=blocked\n' >&2
  exit 2
}
grep -Fxq 'script_172_section_page_experiment_design=pass' "$SCRIPT_172_REPORT" || {
  printf 'reason=script_172_not_clean\n\nSCRIPT RESULT\nscript_173_bounded_section_page_candidate_experiment=blocked\n' >&2
  exit 1
}
grep -Fxq 'next_gate=execute_bounded_section_page_candidate_experiment' "$SCRIPT_172_REPORT" || {
  printf 'reason=script_172_next_gate_invalid\n\nSCRIPT RESULT\nscript_173_bounded_section_page_candidate_experiment=blocked\n' >&2
  exit 1
}
for executable in "$INITDB" "$PG_CTL"; do
  [[ -f "$executable" && ! -L "$executable" && -x "$executable" ]] || {
    printf 'reason=postgresql_16_binary_unsafe\n\nSCRIPT RESULT\nscript_173_bounded_section_page_candidate_experiment=blocked\n' >&2
    exit 2
  }
done

bash -n "${BASH_SOURCE[0]}"
for python_source in "$BUILDER" "$EMBEDDER" "$EVALUATOR" "$BASE_EVALUATOR" "$CANDIDATE_EVALUATOR"; do
  PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
    'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
    "$python_source"
done
PYTHONDONTWRITEBYTECODE=1 python3 -B "$BUILDER" --self-test \
  | grep -Fxq 'published_v2_section_page_representative_builder_self_test=pass'
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EMBEDDER" --self-test \
  | grep -Fxq 'document_embedding_endpoint_producer_self_test=pass'
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" --self-test \
  | grep -Fxq 'published_v2_section_page_candidate_experiment_self_test=pass'
PYTHONDONTWRITEBYTECODE=1 python3 -B -c 'import psycopg; assert psycopg.__version__'

validation_root="$(mktemp -d /tmp/ishikawa-script-173-validation.XXXXXX)"
trap 'rm -rf -- "$validation_root"' EXIT
PYTHONDONTWRITEBYTECODE=1 python3 -B "$BUILDER" \
  --input "$ATOMIC_CHUNKS" --expected-input-sha256 "$ATOMIC_CHUNKS_SHA256" \
  --output "$validation_root/representatives-a.json" >"$validation_root/a.stdout"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$BUILDER" \
  --input "$ATOMIC_CHUNKS" --expected-input-sha256 "$ATOMIC_CHUNKS_SHA256" \
  --output "$validation_root/representatives-b.json" >"$validation_root/b.stdout"
cmp --silent "$validation_root/representatives-a.json" "$validation_root/representatives-b.json" || {
  printf 'reason=representative_bytes_not_repeatable\n\nSCRIPT RESULT\nscript_173_bounded_section_page_candidate_experiment=blocked\n' >&2
  exit 2
}
grep -Fxq 'published_v2_section_page_representative_builder=pass' "$validation_root/a.stdout"
representative_validation_sha256="$(sha256sum "$validation_root/representatives-a.json" | awk '{print $1}')"
rm -rf -- "$validation_root"
trap - EXIT

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_bounded_section_page_candidate_experiment' \
    "script_sha256=$script_sha256;builder_sha256=$BUILDER_SHA256;evaluator_sha256=$EVALUATOR_SHA256" \
    "design_sha256=$DESIGN_SHA256;atomic_chunks_sha256=$ATOMIC_CHUNKS_SHA256;accepted_observation_sha256=$ACCEPTED_OBSERVATION_SHA256" \
    "normalized_sha256=$NORMALIZED_SHA256;promotion_manifest_sha256=$PROMOTION_SUMS_SHA256" \
    "representative_validation_sha256=$representative_validation_sha256;representatives=29;variants=4;cases=68" \
    'database_contact=false;model_contact=false;credential_read=false;corpus_changed=false;profile_changed=false;candidate_promoted=false' \
    '' \
    'SCRIPT RESULT' \
    'script_173_bounded_section_page_candidate_experiment=pass'
  exit 0
fi

umask 077
mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT" || {
  printf 'reason=local_output_root_creation_failed\n\nSCRIPT RESULT\nscript_173_bounded_section_page_candidate_experiment=blocked\n' >&2
  exit 2
}
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" && -w "$REPORT_ROOT" ]] || {
  printf 'reason=report_root_unsafe\n\nSCRIPT RESULT\nscript_173_bounded_section_page_candidate_experiment=blocked\n' >&2
  exit 2
}
[[ -d "$ARTIFACT_ROOT" && ! -L "$ARTIFACT_ROOT" && -w "$ARTIFACT_ROOT" ]] || {
  printf 'reason=artifact_root_unsafe\n\nSCRIPT RESULT\nscript_173_bounded_section_page_candidate_experiment=blocked\n' >&2
  exit 2
}
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/section_page_candidate_experiment_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-script-173.XXXXXX)"
suffix="${report_path##*_}"; suffix="${suffix%.txt}"
representative_artifact="$ARTIFACT_ROOT/section_page_representatives_${timestamp}_${suffix}.json"
embedding_artifact="$ARTIFACT_ROOT/section_page_representative_embeddings_${timestamp}_${suffix}.json"
observation_artifact="$ARTIFACT_ROOT/section_page_candidate_experiment_${timestamp}_${suffix}.json"
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

retain_artifact() {
  local source_path="$1" destination_path="$2" expected_sha256="$3" label="$4"
  local actual_sha256=''
  [[ -f "$source_path" && ! -L "$source_path" && -r "$source_path" ]] \
    || block "${label}_source_unsafe"
  [[ "$destination_path" == "$ARTIFACT_ROOT"/* ]] \
    || block "${label}_destination_outside_artifact_root"
  [[ ! -e "$destination_path" && ! -L "$destination_path" ]] \
    || block "${label}_destination_already_exists"
  # /tmp and the repository are different filesystems on DankoSurface.  Copy
  # bytes without attempting to preserve Unix metadata that the /mnt/g mount
  # does not support, verify identity, and only then remove the temporary copy.
  if ! tee -- "$destination_path" <"$source_path" >/dev/null; then
    block "${label}_copy_failed"
  fi
  [[ -f "$destination_path" && ! -L "$destination_path" && -r "$destination_path" ]] \
    || block "${label}_retained_file_unsafe"
  actual_sha256="$(sha256sum "$destination_path" | awk '{print $1}')" \
    || block "${label}_checksum_read_failed"
  [[ "$actual_sha256" == "$expected_sha256" ]] \
    || block "${label}_identity_changed_after_copy"
  rm -f -- "$source_path" || block "${label}_temporary_source_removal_failed"
  [[ ! -e "$source_path" && ! -L "$source_path" ]] \
    || block "${label}_temporary_source_retained"
}

write_and_verify_checksum_manifest() {
  local artifact_path="$1" expected_sha256="$2" label="$3"
  local artifact_directory artifact_name manifest_path
  artifact_directory="$(dirname -- "$artifact_path")" \
    || block "${label}_manifest_directory_resolution_failed"
  artifact_name="$(basename -- "$artifact_path")" \
    || block "${label}_manifest_name_resolution_failed"
  manifest_path="$artifact_path.sha256"
  [[ "$manifest_path" == "$ARTIFACT_ROOT"/* ]] \
    || block "${label}_manifest_outside_artifact_root"
  [[ ! -e "$manifest_path" && ! -L "$manifest_path" ]] \
    || block "${label}_manifest_already_exists"
  if ! printf '%s  %s\n' "$expected_sha256" "$artifact_name" >"$manifest_path"; then
    block "${label}_manifest_write_failed"
  fi
  [[ -f "$manifest_path" && ! -L "$manifest_path" && -r "$manifest_path" ]] \
    || block "${label}_manifest_unsafe"
  if ! (trap - ERR EXIT HUP INT TERM; cd -- "$artifact_directory" \
      && sha256sum --quiet -c "$(basename -- "$manifest_path")"); then
    block "${label}_manifest_verification_failed"
  fi
}

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
  local initial_status="$?" result='blocked'
  trap - ERR EXIT HUP INT TERM
  if [[ "$BASHPID" != "$MAIN_BASHPID" ]]; then
    exit "$initial_status"
  fi
  set +e
  unset ISHIKAWA_NOMIC_API_KEY nomic_key
  if (( initial_status != 0 )) && [[ -z "$failure_reason" ]]; then
    embedding_failure_reason="$(stage_failure_reason document_embedding_stage \
      "$work_root/embedding.stdout" "$work_root/embedding.stderr")"
    measurement_failure_reason="$(stage_failure_reason \
      published_v2_section_page_candidate_experiment \
      "$work_root/measurement.stdout" "$work_root/measurement.stderr")"
    if [[ -n "$embedding_failure_reason" ]]; then
      failure_reason="representative_embedding_${embedding_failure_reason}"
    elif [[ -n "$measurement_failure_reason" ]]; then
      failure_reason="variant_measurement_${measurement_failure_reason}"
    else
      failure_reason="${current_stage}_unexpected_exit_${initial_status}"
    fi
  fi
  if [[ "$private_pg_started" == true && "$work_root" == /tmp/ishikawa-script-173.* ]]; then
    "$PG_CTL" -D "$work_root/postgresql" -m fast -w stop >/dev/null 2>&1 || true
  fi
  [[ "$work_root" == /tmp/ishikawa-script-173.* ]] && rm -rf -- "$work_root"
  if (( initial_status == 0 )); then
    result='pass'
  else
    [[ -n "$failure_reason" ]] \
      || failure_reason="${current_stage}_unexpected_exit_${initial_status}"
    for path in "$representative_artifact" "$embedding_artifact" "$observation_artifact"; do
      [[ "$path" == "$ARTIFACT_ROOT"/* ]] && rm -f -- "$path" "$path.sha256"
    done
  fi
  {
    printf '\nSCRIPT RESULT\n'
    [[ "$result" == pass ]] || printf 'reason=%s\n' "$failure_reason"
    printf 'script_173_bounded_section_page_candidate_experiment=%s\n' "$result"
  } >>"$report_path"
  printf 'local_report=%s\n' "$report_path"
  printf 'local_report_sha256=%s\n' "$(sha256sum "$report_path" | awk '{print $1}')"
  printf '\nSCRIPT RESULT\n'
  [[ "$result" == pass ]] || printf 'reason=%s\n' "$failure_reason"
  printf 'script_173_bounded_section_page_candidate_experiment=%s\n' "$result"
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
  nomic_key="$value"; value=''
}

current_stage='host_identity'
actual_hostname="$(hostname -s)"
actual_os_id="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"' | awk 'NR == 1')"
actual_os_version="$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"' | awk 'NR == 1')"
actual_architecture="$(uname -m)"
local_user="$(id -un)"
emit 'purpose=measure_bounded_section_page_candidate_experiment'
emit "started_utc=$timestamp;hostname=$actual_hostname;os_version=$actual_os_version;architecture=$actual_architecture"
emit "script_sha256=$script_sha256;design_sha256=$DESIGN_SHA256;builder_sha256=$BUILDER_SHA256;evaluator_sha256=$EVALUATOR_SHA256"
emit 'authorized_actions=build_29_retrieval_only_representatives_call_existing_loopback_nomic_start_private_unix_socket_postgresql_measure_four_variants_retain_local_content_free_evidence'
emit 'non_actions=no_gemma_no_accepted_database_no_database_write_no_ingestion_no_publication_no_black_corpus_no_remote_host_no_service_change_no_package_change_no_profile_change_no_candidate_promotion'
[[ "$actual_hostname" == 'DankoSurface' && "$actual_os_id" == ubuntu \
    && "$actual_os_version" == '24.04' && "$actual_architecture" == aarch64 ]] \
  || block local_host_identity_mismatch
current_stage='nomic_readiness'
nomic_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
  --connect-timeout 5 --max-time 10 "$NOMIC_HEALTH_URL" 2>/dev/null || true)"
[[ "$nomic_status" == 200 ]] || block nomic_forward_unavailable
emit 'milestone=readiness;state=pass;nomic=pass;gemma_required=false;accepted_postgresql_contact=false'

current_stage='representative_build'
representatives_a="$work_root/representatives-a.json"
representatives_b="$work_root/representatives-b.json"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$BUILDER" \
  --input "$ATOMIC_CHUNKS" --expected-input-sha256 "$ATOMIC_CHUNKS_SHA256" \
  --output "$representatives_a" >"$work_root/builder-a.stdout" 2>"$work_root/builder-a.stderr" \
  || block representative_build_failed
PYTHONDONTWRITEBYTECODE=1 python3 -B "$BUILDER" \
  --input "$ATOMIC_CHUNKS" --expected-input-sha256 "$ATOMIC_CHUNKS_SHA256" \
  --output "$representatives_b" >"$work_root/builder-b.stdout" 2>"$work_root/builder-b.stderr" \
  || block representative_repeat_build_failed
cmp --silent "$representatives_a" "$representatives_b" || block representative_bytes_not_repeatable
representatives_sha256="$(sha256sum "$representatives_a" | awk '{print $1}')"
emit "milestone=section_page_representatives;state=pass;representatives=29;grouped_atoms=123;artifact_sha256=$representatives_sha256"

current_stage='credential_read'
read_secret
emit 'milestone=credential;state=accepted;value_logged=false;value_retained=false'
representative_embeddings="$work_root/representative-embeddings.json"
embedding_started="$(date +%s)"
current_stage='representative_embeddings'
emit 'milestone=representative_embeddings;state=start;candidates=29'
embedding_status=0
printf '%s' "$nomic_key" | PYTHONDONTWRITEBYTECODE=1 timeout \
  --signal=TERM --kill-after=10s 600s python3 -B "$EMBEDDER" \
    --input "$representatives_a" --expected-input-sha256 "$representatives_sha256" \
    --output "$representative_embeddings" --embedding-url "$NOMIC_EMBEDDING_URL" \
    --tokenizer-url "$NOMIC_TOKENIZER_URL" --batch-size 16 --credential-stdin \
    >"$work_root/embedding.stdout" 2>"$work_root/embedding.stderr" \
  || embedding_status="$?"
if (( embedding_status != 0 )); then
  if (( embedding_status == 124 || embedding_status == 137 )); then
    block representative_embedding_timeout
  fi
  embedding_failure_reason="$(stage_failure_reason document_embedding_stage \
    "$work_root/embedding.stdout" "$work_root/embedding.stderr")"
  if [[ -n "$embedding_failure_reason" ]]; then
    block "representative_embedding_${embedding_failure_reason}"
  fi
  block representative_embedding_unclassified_failure
fi
if ! grep -Fxq 'document_embedding_stage=pass' "$work_root/embedding.stdout"; then
  embedding_failure_reason="$(stage_failure_reason document_embedding_stage \
    "$work_root/embedding.stdout" "$work_root/embedding.stderr")"
  if [[ -n "$embedding_failure_reason" ]]; then
    block "representative_embedding_${embedding_failure_reason}"
  fi
  block representative_embedding_pass_marker_absent
fi
representative_embeddings_sha256="$(sha256sum "$representative_embeddings" | awk '{print $1}')"
emit "milestone=representative_embeddings;state=pass;elapsed_seconds=$(( $(date +%s) - embedding_started ));artifact_sha256=$representative_embeddings_sha256"

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

observation="$work_root/observation.json"
measurement_started="$(date +%s)"
current_stage='variant_measurement'
emit 'milestone=variant_measurement;state=start;variants=4;cases=68;deterministic_replays=2'
export ISHIKAWA_NOMIC_API_KEY="$nomic_key"
measurement_status=0
PYTHONDONTWRITEBYTECODE=1 timeout --signal=TERM --kill-after=10s 1800s \
  python3 -B "$EVALUATOR" --run \
  --python-root "$PYTHON_ROOT" \
  --design "$DESIGN" --expected-design-sha256 "$DESIGN_SHA256" \
  --atomic-chunks "$ATOMIC_CHUNKS" --expected-atomic-chunks-sha256 "$ATOMIC_CHUNKS_SHA256" \
  --representatives "$representatives_a" --expected-representatives-sha256 "$representatives_sha256" \
  --atomic-embeddings "$ATOMIC_EMBEDDINGS" --expected-atomic-embeddings-sha256 "$ATOMIC_EMBEDDINGS_SHA256" \
  --normalized "$NORMALIZED" --expected-normalized-sha256 "$NORMALIZED_SHA256" \
  --promotion-bundle "$PROMOTION_BUNDLE" --expected-promotion-manifest-sha256 "$PROMOTION_SUMS_SHA256" \
  --representative-embeddings "$representative_embeddings" --expected-representative-embeddings-sha256 "$representative_embeddings_sha256" \
  --body-cases "$BODY_CASES" --expected-body-cases-sha256 "$BODY_CASES_SHA256" \
  --header-cases "$HEADER_CASES" --expected-header-cases-sha256 "$HEADER_CASES_SHA256" \
  --accepted-observation "$ACCEPTED_OBSERVATION" --expected-accepted-observation-sha256 "$ACCEPTED_OBSERVATION_SHA256" \
  --embedding-url "$NOMIC_EMBEDDING_URL" --tokenizer-url "$NOMIC_TOKENIZER_URL" \
  --postgresql-socket "$postgresql_socket" --postgresql-port "$TEMPORARY_POSTGRESQL_PORT" \
  --postgresql-user "$local_user" --output "$observation" \
  >"$work_root/measurement.stdout" 2>"$work_root/measurement.stderr" \
  || measurement_status="$?"
unset ISHIKAWA_NOMIC_API_KEY
nomic_key=''
if (( measurement_status != 0 )); then
  if (( measurement_status == 124 || measurement_status == 137 )); then
    block variant_measurement_timeout
  fi
  measurement_failure_reason="$(stage_failure_reason \
    published_v2_section_page_candidate_experiment \
    "$work_root/measurement.stdout" "$work_root/measurement.stderr")"
  if [[ -n "$measurement_failure_reason" ]]; then
    block "variant_measurement_${measurement_failure_reason}"
  fi
  block variant_measurement_unclassified_failure
fi
if ! grep -Fxq 'published_v2_section_page_candidate_experiment=pass' "$work_root/measurement.stdout"; then
  measurement_failure_reason="$(stage_failure_reason \
    published_v2_section_page_candidate_experiment \
    "$work_root/measurement.stdout" "$work_root/measurement.stderr")"
  if [[ -n "$measurement_failure_reason" ]]; then
    block "variant_measurement_${measurement_failure_reason}"
  fi
  block variant_measurement_pass_marker_absent
fi
while IFS= read -r line; do emit "$line"; done <"$work_root/measurement.stdout"
observation_sha256="$(sha256sum "$observation" | awk '{print $1}')"
emit "milestone=variant_measurement;state=pass;elapsed_seconds=$(( $(date +%s) - measurement_started ));artifact_sha256=$observation_sha256"

current_stage='measurement_validation'
validation_summary="$work_root/validation-summary.txt"
PYTHONDONTWRITEBYTECODE=1 python3 -B - "$observation" >"$validation_summary" <<'PY'
import json, pathlib, sys
value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert value["artifact_kind"] == "ishikawa_published_v2_section_page_candidate_experiment"
assert value["accepted_atomic_baseline_exactly_replayed"] is True
assert value["deterministic_replay"] is True
assert [item["name"] for item in value["variants"]] == [
    "atomic_baseline", "atomic_duplicate_canonical", "section_page",
    "section_page_duplicate_canonical",
]
assert value["inventory"]["atomic_candidates"] == 139
assert value["inventory"]["section_page_representatives"] == 29
assert value["inventory"]["maximum_pre_collapse_candidates"] == 168
assert value["boundaries"]["database_write"] is False
assert value["boundaries"]["accepted_database_contact"] is False
assert value["boundaries"]["gemma_contact"] is False
assert value["boundaries"]["production_profile_changed"] is False
assert value["boundaries"]["candidate_promoted"] is False
print("eligible_variants=" + (",".join(value["eligible_variants"]) or "none"))
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
retain_artifact "$representatives_a" "$representative_artifact" \
  "$representatives_sha256" representative_artifact
retain_artifact "$representative_embeddings" "$embedding_artifact" \
  "$representative_embeddings_sha256" embedding_artifact
retain_artifact "$observation" "$observation_artifact" \
  "$observation_sha256" observation_artifact
write_and_verify_checksum_manifest "$representative_artifact" \
  "$representatives_sha256" representative_artifact
write_and_verify_checksum_manifest "$embedding_artifact" \
  "$representative_embeddings_sha256" embedding_artifact
write_and_verify_checksum_manifest "$observation_artifact" \
  "$observation_sha256" observation_artifact
for path in "$representative_artifact" "$embedding_artifact" "$observation_artifact"; do
  [[ -f "$path" && ! -L "$path" && -f "$path.sha256" && ! -L "$path.sha256" ]] \
    || block artifact_retention_final_state_incomplete
done
emit 'milestone=artifact_retention;state=pass;artifacts=3;checksum_manifests=3;filesystem_permissions=mount_managed;umask=077'
emit "representative_artifact=$representative_artifact;representative_artifact_sha256=$representatives_sha256"
emit "embedding_artifact=$embedding_artifact;embedding_artifact_sha256=$representative_embeddings_sha256"
emit "observation_artifact=$observation_artifact;observation_artifact_sha256=$observation_sha256"
emit 'truth_evaluation_only=true;truth_ingested=false;truth_sent_to_gemma=false;truth_applied_to_black_corpus=false'
emit 'database_write=false;accepted_database_contact=false;gemma_contact=false;corpus_changed=false;profile_changed=false;candidate_promoted=false;credentials_retained=false'
current_stage='complete'
