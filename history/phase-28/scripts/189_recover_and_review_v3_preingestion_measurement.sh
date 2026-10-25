#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Recover Script 188's complete retained measurement after its DrvFS chmod
#   failure and classify the observed synthetic-corpus-v3 rank failures.
#
# Boundaries:
#   Local read-only review plus new local report/review/checksum files. No model,
#   database, corpus mutation, ingestion, retrieval tuning, package, or release
#   change.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/189_recover_and_review_v3_preingestion_measurement.sh --run

usage() {
  sed -n '3,17p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Recover and classify the retained Script 188 result.' \
    '  --validate-only Validate bound inputs and review contracts only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly REVIEWER="$SCRIPT_DIR/review_synthetic_corpus_v3_rank_failures.py"
readonly SCRIPT_188_REPORT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v3-preingestion/v3_preingestion_retrieval_20261023T045046Z_4Dggzj.txt"
readonly CANDIDATE_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v3/synthetic_corpus_v3_candidate_20261023T043639Z"
readonly CHUNKS="$CANDIDATE_ROOT/qualification/chunks.json"
readonly CORPUS_TRUTH="$CANDIDATE_ROOT/evaluation/corpus_truth.json"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v3-preingestion"
readonly RETRIEVAL_TRUTH="$ARTIFACT_ROOT/v3_retrieval_truth_20261023T045046Z.json"
readonly EMBEDDINGS="$ARTIFACT_ROOT/v3_document_embeddings_20261023T045046Z.json"
readonly OBSERVATION="$ARTIFACT_ROOT/v3_preingestion_retrieval_observation_20261023T045046Z.json"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v3-rank-review"
readonly REVIEW_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v3-rank-review"

readonly SCRIPT_188_REPORT_SHA256='0f424c565264b168a1ae6450dcc10a5d2a4f87cdd9ad836bec46b7718b34211e'
readonly CHUNKS_SHA256='d659ed731cced4c22a6cabda940cb5d8246acd97ef050f46efbf45717c552703'
readonly CORPUS_TRUTH_SHA256='85f753ced3956e609b1fada2419888bae1099a308be3c905310765796c80f573'
readonly RETRIEVAL_TRUTH_SHA256='f74302d899d000b9493fecfeca4ffbe2995bb04aabef00bf327061c34c2a18a0'
readonly EMBEDDINGS_SHA256='fd13061d42ce056049596c3eff4a806af8bd2676b894e0238ce55edbcef97a69'
readonly OBSERVATION_SHA256='28c3c134cd1d78adb7672aa699bbe50784112fa865dbb65dca3f1931e3d8974c'
readonly REVIEWER_SHA256='27fe6805c2d7901b4f1faa177df1a0bde758edcfef58578e1e432f40570b8f49'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      printf 'reason=argument_invalid\n\nSCRIPT RESULT\nscript_189_v3_rank_failure_review=blocked\n' >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'reason=mode_invalid\n\nSCRIPT RESULT\nscript_189_v3_rank_failure_review=blocked\n' >&2
  exit 2
}

for command_name in awk bash basename date dirname grep mkdir mktemp mv python3 \
  rm sha256sum tee; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'reason=local_command_missing;command=%s\n\nSCRIPT RESULT\nscript_189_v3_rank_failure_review=blocked\n' \
      "$command_name" >&2
    exit 2
  }
done

check_file() {
  local path="$1" expected_sha256="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] || {
    printf 'reason=%s_unsafe\n\nSCRIPT RESULT\nscript_189_v3_rank_failure_review=blocked\n' \
      "$label" >&2
    exit 2
  }
  [[ "$(sha256sum "$path" | awk '{print $1}')" == "$expected_sha256" ]] || {
    printf 'reason=%s_identity_changed\n\nSCRIPT RESULT\nscript_189_v3_rank_failure_review=blocked\n' \
      "$label" >&2
    exit 2
  }
}

check_file "$SCRIPT_188_REPORT" "$SCRIPT_188_REPORT_SHA256" script_188_report
check_file "$CHUNKS" "$CHUNKS_SHA256" chunks
check_file "$CORPUS_TRUTH" "$CORPUS_TRUTH_SHA256" corpus_truth
check_file "$RETRIEVAL_TRUTH" "$RETRIEVAL_TRUTH_SHA256" retrieval_truth
check_file "$EMBEDDINGS" "$EMBEDDINGS_SHA256" embeddings
check_file "$OBSERVATION" "$OBSERVATION_SHA256" observation
check_file "$REVIEWER" "$REVIEWER_SHA256" reviewer

grep -Fxq \
  'milestone=retrieval_measurement;state=pass;elapsed_seconds=17;artifact_sha256=28c3c134cd1d78adb7672aa699bbe50784112fa865dbb65dca3f1931e3d8974c' \
  "$SCRIPT_188_REPORT" || {
  printf 'reason=script_188_measurement_not_complete\n\nSCRIPT RESULT\nscript_189_v3_rank_failure_review=blocked\n' >&2
  exit 1
}
grep -Fxq 'script_state=blocked;reason=unexpected_failure;exit_code=1' \
  "$SCRIPT_188_REPORT" || {
  printf 'reason=script_188_failure_shape_changed\n\nSCRIPT RESULT\nscript_189_v3_rank_failure_review=blocked\n' >&2
  exit 1
}

bash -n "${BASH_SOURCE[0]}"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
  "$REVIEWER"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$REVIEWER" --self-test \
  | grep -Fxq 'synthetic_corpus_v3_rank_failure_review_self_test=pass'

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_v3_preingestion_measurement_recovery_and_rank_review' \
    "script_sha256=$script_sha256;reviewer_sha256=$REVIEWER_SHA256" \
    "script_188_report_sha256=$SCRIPT_188_REPORT_SHA256;observation_sha256=$OBSERVATION_SHA256" \
    'measurement_complete=true;measurement_rerun_required=false;wrapper_failure=drvfs_chmod_not_supported' \
    'authorized_actions=local_read_only_review_write_new_local_review_report_and_checksum_manifest' \
    'database_contact=false;model_contact=false;corpus_changed=false;retrieval_profile_changed=false' \
    '' \
    'SCRIPT RESULT' \
    'script_189_v3_rank_failure_review=pass'
  exit 0
fi

umask 077
mkdir -p -- "$REPORT_ROOT" "$REVIEW_ROOT"
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" \
    && -d "$REVIEW_ROOT" && ! -L "$REVIEW_ROOT" ]] || {
  printf 'reason=output_directory_unsafe\n\nSCRIPT RESULT\nscript_189_v3_rank_failure_review=blocked\n' >&2
  exit 1
}
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/v3_rank_failure_review_${timestamp}_XXXXXX.txt")"
review_candidate="$(mktemp /tmp/ishikawa-v3-rank-review.XXXXXX.json)"
rm -f -- "$review_candidate"
review_artifact="$REVIEW_ROOT/v3_rank_failure_review_${timestamp}.json"
checksum_artifact="$REVIEW_ROOT/SHA256SUMS_${timestamp}"

cleanup() {
  local initial_status="$?"
  trap - EXIT HUP INT TERM
  if [[ -n "${review_candidate:-}" && "$review_candidate" == /tmp/ishikawa-v3-rank-review.* \
        && -e "$review_candidate" ]]; then
    rm -f -- "$review_candidate"
  fi
  if (( initial_status != 0 )); then
    printf 'script_state=blocked;exit_code=%s\n' "$initial_status" | tee -a "$report_path"
    printf 'local_report=%s;local_report_sha256=%s\n' \
      "$report_path" "$(sha256sum "$report_path" | awk '{print $1}')"
    printf '\nSCRIPT RESULT\nscript_189_v3_rank_failure_review=blocked\n'
  fi
  exit "$initial_status"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

emit() { printf '%s\n' "$1" | tee -a "$report_path"; }

emit 'purpose=recover_script_188_measurement_and_review_v3_rank_failures'
emit "started_utc=$timestamp;script_sha256=$script_sha256;reviewer_sha256=$REVIEWER_SHA256"
emit "script_188_report_sha256=$SCRIPT_188_REPORT_SHA256;retrieval_truth_sha256=$RETRIEVAL_TRUTH_SHA256;embeddings_sha256=$EMBEDDINGS_SHA256;observation_sha256=$OBSERVATION_SHA256"
emit 'authorized_actions=validate_retained_script_188_artifacts_classify_rank_failures_write_new_local_review_and_checksum_manifest'
emit 'non_actions=no_model_contact_no_database_contact_no_corpus_change_no_ingestion_no_retrieval_tuning_no_package_change_no_release_change'

review_stdout="$(PYTHONDONTWRITEBYTECODE=1 python3 -B "$REVIEWER" \
  --chunks "$CHUNKS" --expected-chunks-sha256 "$CHUNKS_SHA256" \
  --corpus-truth "$CORPUS_TRUTH" --expected-corpus-truth-sha256 "$CORPUS_TRUTH_SHA256" \
  --retrieval-truth "$RETRIEVAL_TRUTH" --expected-retrieval-truth-sha256 "$RETRIEVAL_TRUTH_SHA256" \
  --observation "$OBSERVATION" --expected-observation-sha256 "$OBSERVATION_SHA256" \
  --output "$review_candidate")" || exit 1
grep -Fxq 'synthetic_corpus_v3_rank_failure_review=pass' <<<"$review_stdout" || exit 1
while IFS= read -r output_line; do emit "$output_line"; done <<<"$review_stdout"

[[ ! -e "$review_artifact" && ! -L "$review_artifact" \
    && ! -e "$checksum_artifact" && ! -L "$checksum_artifact" ]] || exit 1
mv -- "$review_candidate" "$review_artifact"
review_candidate=''
review_sha256="$(sha256sum "$review_artifact" | awk '{print $1}')"
(
  cd -- "$REVIEW_ROOT"
  sha256sum "$(basename -- "$review_artifact")" >"$(basename -- "$checksum_artifact")"
)

emit 'milestone=script_188_recovery;state=pass;measurement_complete=true;measurement_rerun_required=false;wrapper_patch_applied=true'
emit "review_artifact=$review_artifact;review_artifact_sha256=$review_sha256"
emit "checksum_artifact=$checksum_artifact;checksum_artifact_sha256=$(sha256sum "$checksum_artifact" | awk '{print $1}')"
emit 'next_gate=discuss_authoritative_document_identity_context_before_changing_frozen_chunk_representation'
emit 'database_contact=false;model_contact=false;corpus_changed=false;retrieval_profile_changed=false'

trap - EXIT HUP INT TERM
report_sha256="$(sha256sum "$report_path" | awk '{print $1}')"
printf 'local_report=%s;local_report_sha256=%s\n' "$report_path" "$report_sha256"
printf '\nSCRIPT RESULT\nscript_189_v3_rank_failure_review=pass\n'
