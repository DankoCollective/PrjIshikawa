#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Review the remaining Script 164 body-rank failures without changing the
#   corpus, answer key, retrieval candidate, or production method profile.
#
# Boundaries:
#   Local retained synthetic artifacts only. No database, model, credential,
#   black-corpus, ingestion, service, package, or production-profile contact.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/165_review_v2_candidate_rank_failures.sh --run

usage() {
  sed -n '3,16p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Produce and retain the bounded rank-failure review.' \
    '  --validate-only Validate bound inputs and the reviewer self-test.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly REVIEWER="$SCRIPT_DIR/review_synthetic_corpus_v2_rank_failures.py"
readonly TRUTH="$PHASE_ROOT/reference/ishikawa-synthetic-corpus-v2-body-mrr-cases.json"
readonly SCRIPT_164_REPORT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-routing-assembly/v2_metadata_routing_sibling_assembly_20261022T185141Z_SzKI8o.txt"
readonly OBSERVATION="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-routing-assembly/v2_routing_assembly_observation_20261022T185141Z.json"
readonly CANDIDATE="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-routing-assembly/v2_routing_assembly_candidate_20261022T185141Z/qualification/retrieval-candidate.json"
readonly BASELINE="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-corrected-preingestion/corrected_corpus_v2_retrieval_observation_20261022T183418Z.json"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-rank-review"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-rank-review"

readonly SCRIPT_164_REPORT_SHA256='0096a0c16e04a19c6554eafeabb06cf739da57747fbd3a1009d19436f64c6acd'
readonly OBSERVATION_SHA256='c3705a323f9c23d1a472cd67cbcd890926f406c5db61fcbccdc41d8cda502073'
readonly CANDIDATE_SHA256='f8ef761a2835192f690c21ba39a535ee0f76f062a7750fc9873f44bc46d4dfd6'
readonly BASELINE_SHA256='4378ffa79fe61814758d9dc982b836cb91f1f13c09c858a9af10f70b897b5bef'
readonly TRUTH_SHA256='47882a93996ef1d8331606c173c85f2076e457c989c9ab3cd6bad31d5ce5613e'
readonly REVIEWER_SHA256='43fac68ca95d20bbfeebacebfe1fd1e29f322b7a46369ce50a7ba0045df9595c'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      printf 'reason=argument_invalid\n' >&2
      printf '\nSCRIPT RESULT\nscript_165_v2_rank_failure_review=blocked\n' >&2
      usage >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'reason=mode_invalid\n' >&2
  printf '\nSCRIPT RESULT\nscript_165_v2_rank_failure_review=blocked\n' >&2
  exit 2
}

for command_name in awk date dirname grep hostname mkdir mktemp python3 rm sed sha256sum tee; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'reason=local_command_missing;command=%s\n' "$command_name" >&2
    printf '\nSCRIPT RESULT\nscript_165_v2_rank_failure_review=blocked\n' >&2
    exit 2
  }
done

check_file() {
  local path="$1" expected_sha256="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] || {
    printf 'reason=%s_unsafe\n' "$label" >&2
    printf '\nSCRIPT RESULT\nscript_165_v2_rank_failure_review=blocked\n' >&2
    exit 2
  }
  [[ "$(sha256sum "$path" | awk '{print $1}')" == "$expected_sha256" ]] || {
    printf 'reason=%s_identity_changed\n' "$label" >&2
    printf '\nSCRIPT RESULT\nscript_165_v2_rank_failure_review=blocked\n' >&2
    exit 2
  }
}

check_file "$SCRIPT_164_REPORT" "$SCRIPT_164_REPORT_SHA256" script_164_report
check_file "$OBSERVATION" "$OBSERVATION_SHA256" script_164_observation
check_file "$CANDIDATE" "$CANDIDATE_SHA256" script_164_candidate
check_file "$BASELINE" "$BASELINE_SHA256" script_163_observation
check_file "$TRUTH" "$TRUTH_SHA256" v2_truth
check_file "$REVIEWER" "$REVIEWER_SHA256" reviewer

grep -Fxq \
  'script_164_v2_metadata_routing_sibling_assembly=pass;measurement_gate=not_met;next_gate=review_remaining_v2_candidate_rank_failures_before_promotion' \
  "$SCRIPT_164_REPORT" || {
  printf 'reason=script_164_result_not_bound\n' >&2
  printf '\nSCRIPT RESULT\nscript_165_v2_rank_failure_review=blocked\n' >&2
  exit 1
}

PYTHONDONTWRITEBYTECODE=1 python3 -B -m py_compile "$REVIEWER"

validation_root="$(mktemp -d /tmp/ishikawa-script-165-validation.XXXXXX)"
cleanup_validation() {
  case "$validation_root" in
    /tmp/ishikawa-script-165-validation.*) rm -rf -- "$validation_root" ;;
  esac
}
trap cleanup_validation EXIT
validation_output="$validation_root/review.json"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$REVIEWER" \
  --observation "$OBSERVATION" \
  --baseline-observation "$BASELINE" \
  --candidate "$CANDIDATE" \
  --truth "$TRUTH" \
  --output "$validation_output" >"$validation_root/reviewer.stdout"
python3 -B - "$validation_output" <<'PY'
import json
import pathlib
import sys

value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert value["artifact_kind"] == "ishikawa_synthetic_corpus_v2_rank_failure_review"
assert value["observed"]["current_body_mrr_at_20"] == "0.870992"
assert value["observed"]["current_header_mrr_at_20"] == "1.000000"
assert value["observed"]["rank_distribution"] == {
    "1": 48, "2": 5, "3": 3, "4": 1, "5": 1, "6": 1, "7": 1,
}
assert value["observed"]["non_rank_one_case_count"] == 12
assert value["promotion_authorized"] is False
assert value["boundaries"]["truth_used_by_retrieval"] is False
assert value["next_gate"] == "design_bounded_evidence_equivalence_and_source_unit_diversification_experiment"
PY

if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_v2_rank_failure_review' \
    "script_164_report_sha256=$SCRIPT_164_REPORT_SHA256" \
    "observation_sha256=$OBSERVATION_SHA256" \
    "candidate_sha256=$CANDIDATE_SHA256" \
    'boundaries=local_retained_synthetic_artifacts_only;truth_used_by_retrieval=false;production_profile_changed=false' \
    '' \
    'SCRIPT RESULT' \
    'script_165_v2_rank_failure_review=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
suffix="$(python3 -B -c 'import secrets; print(secrets.token_hex(3))')"
report_path="$REPORT_ROOT/v2_rank_failure_review_${timestamp}_${suffix}.txt"
artifact_path="$ARTIFACT_ROOT/v2_rank_failure_review_${timestamp}_${suffix}.json"
[[ ! -e "$report_path" && ! -L "$report_path" && ! -e "$artifact_path" && ! -L "$artifact_path" ]] || {
  printf 'reason=retained_output_path_exists\n' >&2
  printf '\nSCRIPT RESULT\nscript_165_v2_rank_failure_review=blocked\n' >&2
  exit 1
}
exec > >(tee "$report_path") 2>&1

printf '%s\n' \
  'purpose=review_remaining_v2_candidate_rank_failures_without_mutation' \
  "started_utc=$timestamp;hostname=$(hostname)" \
  "script_164_report_sha256=$SCRIPT_164_REPORT_SHA256;observation_sha256=$OBSERVATION_SHA256" \
  "candidate_sha256=$CANDIDATE_SHA256;baseline_sha256=$BASELINE_SHA256;truth_sha256=$TRUTH_SHA256" \
  'authorized_actions=read_bound_local_synthetic_artifacts_compare_retained_ranks_retain_local_review' \
  'non_actions=no_database_contact_no_model_contact_no_credential_read_no_black_corpus_access_no_ingestion_no_truth_change_no_retrieval_change_no_service_change_no_package_change_no_production_profile_change'

PYTHONDONTWRITEBYTECODE=1 python3 -B "$REVIEWER" \
  --observation "$OBSERVATION" \
  --baseline-observation "$BASELINE" \
  --candidate "$CANDIDATE" \
  --truth "$TRUTH" \
  --output "$artifact_path"
artifact_sha256="$(sha256sum "$artifact_path" | awk '{print $1}')"
printf '%s\n' \
  "review_artifact=$artifact_path" \
  "review_artifact_sha256=$artifact_sha256" \
  'truth_evaluation_only=true;truth_used_by_retrieval=false;truth_changed=false' \
  'accepted_database_contact=false;model_contact=false;black_corpus_access=false;corpus_ingestion=false;retrieval_changed=false;production_profile_changed=false;promotion_authorized=false' \
  'next_gate=design_bounded_evidence_equivalence_and_source_unit_diversification_experiment' \
  '' \
  'SCRIPT RESULT' \
  'script_165_v2_rank_failure_review=pass'
