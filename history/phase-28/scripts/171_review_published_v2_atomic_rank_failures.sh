#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Review every below-rank-one body case in Script 169's accepted live lane
#   capture after Script 170 exhausted the bounded profile search.
#
# Boundaries:
#   Content-free local artifacts only. No database, model, credential,
#   service, package, corpus, truth, or production-profile change.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/171_review_published_v2_atomic_rank_failures.sh --run

usage() {
  sed -n '3,14p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Run and retain the content-free rank-failure review.' \
    '  --validate-only Validate inputs and reproduce the expected review.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly REVIEWER="$SCRIPT_DIR/review_published_v2_atomic_rank_failures.py"
readonly SCRIPT_170_REPORT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-live-optimization-search/published_v2_live_optimization_20261022T212932Z_J525E0.txt"
readonly OPTIMIZATION="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-live-optimization-search/published_v2_live_optimization_20261022T212932Z_J525E0.json"
readonly OPTIMIZATION_SUMS="$OPTIMIZATION.sha256"
readonly OBSERVATION="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-live-retrieval/isolated_v2_live_retrieval_20261022T211121Z.json"
readonly OBSERVATION_SUMS="$OBSERVATION.sha256"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-published-rank-review"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-published-rank-review"

readonly REVIEWER_SHA256='8f57f7190e39775469c78a6326f57bc949e0c6e8036994ccbcdd33327c16233c'
readonly SCRIPT_170_REPORT_SHA256='ba7f0d07d3b0ede9c47be3a8ce1de021ed019a73520357727b9df0219dde61d3'
readonly OPTIMIZATION_SHA256='f68353cd324dcc2ea50aafe2d7e578c231f94b566871ee9f78671e5466e5c8bf'
readonly OPTIMIZATION_SUMS_SHA256='a96a48a9a42c8319580e3635dda6745e253982e1c2f8b73e3e5c666ecaa5ba28'
readonly OBSERVATION_SHA256='baab346b25374c44237e37787bd0ef64a1f3f447551212965777358d8c385718'
readonly OBSERVATION_SUMS_SHA256='7583e679e01899ba398047b8709a003570439a09ccf242bcd97838b5713e0a67'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      printf 'reason=argument_invalid\n\nSCRIPT RESULT\nscript_171_published_v2_atomic_rank_failure_review=blocked\n' >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'reason=mode_invalid\n\nSCRIPT RESULT\nscript_171_published_v2_atomic_rank_failure_review=blocked\n' >&2
  exit 2
}

for required_command in bash basename date dirname grep hostname mkdir mktemp mv \
  python3 rm sed sha256sum tee; do
  command -v "$required_command" >/dev/null 2>&1 || {
    printf 'reason=local_command_missing;command=%s\n\nSCRIPT RESULT\nscript_171_published_v2_atomic_rank_failure_review=blocked\n' \
      "$required_command" >&2
    exit 2
  }
done

check_file() {
  local path="$1" expected_sha256="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] || {
    printf 'reason=%s_unsafe\n\nSCRIPT RESULT\nscript_171_published_v2_atomic_rank_failure_review=blocked\n' \
      "$label" >&2
    exit 2
  }
  [[ "$(sha256sum "$path" | sed 's/[[:space:]].*$//')" == "$expected_sha256" ]] || {
    printf 'reason=%s_identity_changed\n\nSCRIPT RESULT\nscript_171_published_v2_atomic_rank_failure_review=blocked\n' \
      "$label" >&2
    exit 2
  }
}

check_file "$SCRIPT_170_REPORT" "$SCRIPT_170_REPORT_SHA256" script_170_report
check_file "$REVIEWER" "$REVIEWER_SHA256" reviewer
check_file "$OPTIMIZATION" "$OPTIMIZATION_SHA256" optimization_artifact
check_file "$OPTIMIZATION_SUMS" "$OPTIMIZATION_SUMS_SHA256" optimization_checksum
check_file "$OBSERVATION" "$OBSERVATION_SHA256" live_observation
check_file "$OBSERVATION_SUMS" "$OBSERVATION_SUMS_SHA256" observation_checksum
(cd -- "$(dirname -- "$OPTIMIZATION")" \
  && sha256sum --quiet -c "$(basename -- "$OPTIMIZATION_SUMS")") || {
  printf 'reason=optimization_checksum_failed\n\nSCRIPT RESULT\nscript_171_published_v2_atomic_rank_failure_review=blocked\n' >&2
  exit 2
}
(cd -- "$(dirname -- "$OBSERVATION")" \
  && sha256sum --quiet -c "$(basename -- "$OBSERVATION_SUMS")") || {
  printf 'reason=observation_checksum_failed\n\nSCRIPT RESULT\nscript_171_published_v2_atomic_rank_failure_review=blocked\n' >&2
  exit 2
}
grep -Fxq 'script_170_published_v2_live_optimization_search=pass' \
  "$SCRIPT_170_REPORT" || {
  printf 'reason=script_170_not_clean\n\nSCRIPT RESULT\nscript_171_published_v2_atomic_rank_failure_review=blocked\n' >&2
  exit 1
}
grep -Fq 'next_gate=review_published_atomic_rank_failures_before_new_retrieval_candidate_design' \
  "$SCRIPT_170_REPORT" || {
  printf 'reason=script_170_next_gate_invalid\n\nSCRIPT RESULT\nscript_171_published_v2_atomic_rank_failure_review=blocked\n' >&2
  exit 1
}

bash -n "${BASH_SOURCE[0]}"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
  "$REVIEWER"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$REVIEWER" --self-test \
  | grep -Fxq 'published_v2_atomic_rank_failure_review_self_test=pass' || {
  printf 'reason=reviewer_self_test_failed\n\nSCRIPT RESULT\nscript_171_published_v2_atomic_rank_failure_review=blocked\n' >&2
  exit 2
}

run_reviewer() {
  local output_path="$1" stdout_path="$2" stderr_path="$3"
  PYTHONDONTWRITEBYTECODE=1 python3 -B "$REVIEWER" \
    --observation "$OBSERVATION" \
    --optimization "$OPTIMIZATION" \
    --output "$output_path" >"$stdout_path" 2>"$stderr_path"
}

validate_result() {
  local path="$1"
  PYTHONDONTWRITEBYTECODE=1 python3 -B - "$path" \
    "$OBSERVATION_SHA256" "$OPTIMIZATION_SHA256" <<'PY'
import json
import pathlib
import sys

value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert value["artifact_kind"] == (
    "ishikawa_published_synthetic_corpus_v2_atomic_rank_failure_review"
)
assert value["schema_version"] == 1
assert value["source_sha256"] == {
    "live_observation": sys.argv[2],
    "bounded_optimization": sys.argv[3],
}
baseline = value["accepted_baseline"]
assert baseline["body_mrr_at_20"] == "0.873056"
assert baseline["body_relevant_at_5"] == 58
assert baseline["body_relevant_at_20"] == 60
assert baseline["header_mrr_at_20"] == "1.000000"
assert baseline["rank_one_cases"] == 48
assert baseline["below_rank_one_cases"] == 12
assert baseline["outside_top_five_case_ids"] == ["E-032", "E-033"]
assert baseline["rank_distribution"] == {
    "1": 48, "2": 6, "3": 2, "4": 1, "5": 1, "6": 1, "10": 1
}
search = value["bounded_search"]
assert search["profiles_evaluated"] == 10584
assert search["strict_gate_profiles"] == 0
assert search["best_body_mrr_at_20"] == "0.882103"
assert search["improved_body_case_ids"] == ["E-015", "E-026", "E-033"]
assert search["regressed_body_case_ids"] == ["E-024", "E-032"]
summary = value["rank_failure_summary"]
assert summary["case_count"] == 12
assert summary["blocker_shapes"] == {
    "same_document_wrong_page": 5,
    "other_document": 3,
    "mixed": 4,
}
assert summary["cases_with_same_document_wrong_page_pressure"] == 9
assert summary["cases_with_cross_document_pressure"] == 7
assert summary["lane_leaders"] == {
    "lexical": 4, "vector": 6, "tie": 2, "neither": 0
}
assert summary["single_document_scope_cases"] == 3
assert summary["corpus_wide_scope_cases"] == 9
assert summary["minimum_current_rank_one_promotions_to_exceed_strict_target"] == 3
assert len(value["rank_failures"]) == 12
assert value["conclusions"]["current_profile_remains_frozen"] is True
assert value["conclusions"]["new_retrieval_candidate_authorized"] is False
assert all(value["boundaries"][key] is False for key in (
    "database_contact", "model_contact", "credential_read", "black_corpus_access",
    "corpus_changed", "truth_changed", "service_changed", "package_changed",
    "production_profile_changed",
))
assert value["next_gate"] == (
    "design_bounded_section_page_aware_candidate_experiment_"
    "without_profile_or_corpus_promotion"
)
PY
}

if [[ "$validate_only" == true ]]; then
  validation_root="$(mktemp -d /tmp/ishikawa-script-171-validation.XXXXXX)"
  trap 'rm -rf -- "$validation_root"' EXIT
  run_reviewer "$validation_root/review.json" \
    "$validation_root/reviewer.stdout" "$validation_root/reviewer.stderr"
  validate_result "$validation_root/review.json"
  printf '%s\n' \
    'purpose=validate_published_v2_atomic_rank_failure_review' \
    'rank_one_cases=48;below_rank_one_cases=12;outside_top_five_cases=2' \
    'same_document_wrong_page_pressure=9;cross_document_pressure=7' \
    'profiles_evaluated=10584;strict_gate_profiles=0;profile_changed=false' \
    'database_contact=false;model_contact=false;credential_read=false;corpus_changed=false' \
    '' \
    'SCRIPT RESULT' \
    'script_171_published_v2_atomic_rank_failure_review=pass'
  exit 0
fi

umask 077
mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/published_v2_atomic_rank_review_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-script-171.XXXXXX)"
suffix="${report_path##*_}"
suffix="${suffix%.txt}"
artifact_path="$ARTIFACT_ROOT/published_v2_atomic_rank_review_${timestamp}_${suffix}.json"
artifact_checksum_path="$artifact_path.sha256"
failure_reason=''
script_result=''

emit() {
  printf '%s\n' "$1" | tee -a "$report_path"
}

block() {
  failure_reason="$1"
  exit 1
}

cleanup() {
  local initial_status="$?"
  trap - EXIT HUP INT TERM
  set +e
  [[ -n "$work_root" && "$work_root" == /tmp/ishikawa-script-171.* ]] \
    && rm -rf -- "$work_root"
  if (( initial_status == 0 )); then
    script_result='pass'
  else
    script_result='blocked'
    [[ -n "$failure_reason" ]] || failure_reason="unexpected_failure_exit_$initial_status"
    [[ "$artifact_path" == "$ARTIFACT_ROOT"/* ]] && rm -f -- "$artifact_path"
    [[ "$artifact_checksum_path" == "$ARTIFACT_ROOT"/* ]] \
      && rm -f -- "$artifact_checksum_path"
  fi
  {
    printf '\nSCRIPT RESULT\n'
    [[ "$script_result" == pass ]] || printf 'reason=%s\n' "$failure_reason"
    printf 'script_171_published_v2_atomic_rank_failure_review=%s\n' "$script_result"
  } >>"$report_path"
  printf 'local_report=%s\n' "$report_path"
  printf 'local_report_sha256=%s\n' \
    "$(sha256sum "$report_path" | sed 's/[[:space:]].*$//')"
  printf '\nSCRIPT RESULT\n'
  [[ "$script_result" == pass ]] || printf 'reason=%s\n' "$failure_reason"
  printf 'script_171_published_v2_atomic_rank_failure_review=%s\n' "$script_result"
  exit "$initial_status"
}
trap cleanup EXIT HUP INT TERM

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | sed 's/[[:space:]].*$//')"
reviewer_sha256="$(sha256sum "$REVIEWER" | sed 's/[[:space:]].*$//')"
emit 'purpose=review_published_v2_atomic_rank_failures'
emit "started_utc=$timestamp;hostname=$(hostname);script_sha256=$script_sha256;reviewer_sha256=$reviewer_sha256"
emit "script_170_report_sha256=$SCRIPT_170_REPORT_SHA256;optimization_sha256=$OPTIMIZATION_SHA256;observation_sha256=$OBSERVATION_SHA256"
emit 'authorized_actions=read_checksum_bound_content_free_artifacts_classify_rank_failures_retain_content_free_local_review'
emit 'non_actions=no_database_contact_no_model_contact_no_credential_read_no_black_corpus_access_no_corpus_change_no_truth_change_no_service_change_no_package_change_no_production_profile_change'
emit 'milestone=rank_failure_review;state=start;below_rank_one_cases=12'

if ! run_reviewer "$work_root/review.json" \
  "$work_root/reviewer.stdout" "$work_root/reviewer.stderr"; then
  block reviewer_failed
fi
grep -Fxq 'published_v2_atomic_rank_failure_review=pass' \
  "$work_root/reviewer.stdout" || block reviewer_result_invalid
[[ ! -s "$work_root/reviewer.stderr" ]] || block reviewer_stderr_nonempty
validate_result "$work_root/review.json" || block review_contract_invalid
mv -- "$work_root/review.json" "$artifact_path"
printf '%s  %s\n' "$(sha256sum "$artifact_path" | sed 's/[[:space:]].*$//')" \
  "$(basename -- "$artifact_path")" >"$artifact_checksum_path"

artifact_sha256="$(sha256sum "$artifact_path" | sed 's/[[:space:]].*$//')"
emit 'milestone=rank_failure_review;state=pass;rank_one_cases=48;below_rank_one_cases=12;outside_top_five_cases=2'
emit 'failure_pressure=same_document_wrong_page:9/12,cross_document:7/12;lane_leaders=lexical:4,vector:6,tie:2'
emit 'bounded_search=profiles:10584,strict_gate_profiles:0,current_mrr:0.873056,best_mrr:0.882103;profile_promoted=false'
emit 'review_conclusion=weights_depths_and_rrf_are_insufficient;minimum_optimistic_rank_one_promotions_for_target=3'
emit "review_artifact=$artifact_path;review_artifact_sha256=$artifact_sha256"
emit 'database_contact=false;model_contact=false;credential_read=false;corpus_changed=false;truth_changed=false;production_profile_changed=false'
emit 'next_gate=design_bounded_section_page_aware_candidate_experiment_without_profile_or_corpus_promotion'
