#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Freeze a bounded section/page candidate experiment from Script 171's
#   accepted content-free rank review.
#
# Boundaries:
#   Local synthetic artifacts only. No database, model, credential, service,
#   package, corpus, truth, or production-profile change.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/172_design_bounded_section_page_candidate_experiment.sh --run

usage() {
  sed -n '3,14p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Validate and retain the bounded experiment manifest.' \
    '  --validate-only Validate inputs and reproduce the expected manifest.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly DESIGNER="$SCRIPT_DIR/design_published_v2_section_page_experiment.py"
readonly PLAN="$PHASE_ROOT/docs/ISHIKAWA_V1_3_SECTION_PAGE_EXPERIMENT.md"
readonly SCRIPT_171_REPORT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-published-rank-review/published_v2_atomic_rank_review_20261022T213811Z_EAw3NW.txt"
readonly REVIEW="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-published-rank-review/published_v2_atomic_rank_review_20261022T213811Z_EAw3NW.json"
readonly REVIEW_SUMS="$REVIEW.sha256"
readonly CHUNKS="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-isolated-publication/retained-derived-artifacts-20261022T204745Z/22/22a4d2694938268462f0c78a79b51771abb48a8e1a23420ec0f443e1e7d8c5fd"
readonly BODY_TRUTH="$PHASE_ROOT/reference/ishikawa-synthetic-corpus-v2-body-mrr-cases.json"
readonly HEADER_TRUTH="$PHASE_ROOT/reference/ishikawa-synthetic-corpus-v2-header-cases.json"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-section-page-design"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-section-page-design"

readonly DESIGNER_SHA256='827b9373a96dbe9dfdcc67febd5cb5bd04ae11fc60ac29cf63b6d4288ec2426a'
readonly PLAN_SHA256='c588f67a5c647dc7700d7fa89366c80972595d5ad3e059fd45cbde7a667d1fba'
readonly SCRIPT_171_REPORT_SHA256='97a8517de57d80c8a6e615859b701ab4eba6dce9428e4f74a18a9e34437e9747'
readonly REVIEW_SHA256='160b570c1a0fd7000009b67f80c8ee1cf2c197af563b207f1153e8f959744207'
readonly REVIEW_SUMS_SHA256='825e527a137c6a3dbf574499bfe36b0c3abf338424ed18378495d4d8902c3115'
readonly CHUNKS_SHA256='22a4d2694938268462f0c78a79b51771abb48a8e1a23420ec0f443e1e7d8c5fd'
readonly BODY_TRUTH_SHA256='47882a93996ef1d8331606c173c85f2076e457c989c9ab3cd6bad31d5ce5613e'
readonly HEADER_TRUTH_SHA256='a873a61b59de0a8ea082c3fc0c987ab9cf7b97d79ed843832be354af8eae6e2c'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      printf 'reason=argument_invalid\n\nSCRIPT RESULT\nscript_172_section_page_experiment_design=blocked\n' >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'reason=mode_invalid\n\nSCRIPT RESULT\nscript_172_section_page_experiment_design=blocked\n' >&2
  exit 2
}

for required_command in bash basename date dirname grep hostname mkdir mktemp mv \
  python3 rm sed sha256sum tee; do
  command -v "$required_command" >/dev/null 2>&1 || {
    printf 'reason=local_command_missing;command=%s\n\nSCRIPT RESULT\nscript_172_section_page_experiment_design=blocked\n' \
      "$required_command" >&2
    exit 2
  }
done

check_file() {
  local path="$1" expected_sha256="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] || {
    printf 'reason=%s_unsafe\n\nSCRIPT RESULT\nscript_172_section_page_experiment_design=blocked\n' \
      "$label" >&2
    exit 2
  }
  [[ "$(sha256sum "$path" | sed 's/[[:space:]].*$//')" == "$expected_sha256" ]] || {
    printf 'reason=%s_identity_changed\n\nSCRIPT RESULT\nscript_172_section_page_experiment_design=blocked\n' \
      "$label" >&2
    exit 2
  }
}

check_file "$DESIGNER" "$DESIGNER_SHA256" designer
check_file "$PLAN" "$PLAN_SHA256" experiment_plan
check_file "$SCRIPT_171_REPORT" "$SCRIPT_171_REPORT_SHA256" script_171_report
check_file "$REVIEW" "$REVIEW_SHA256" rank_review
check_file "$REVIEW_SUMS" "$REVIEW_SUMS_SHA256" rank_review_checksum
check_file "$CHUNKS" "$CHUNKS_SHA256" chunk_artifact
check_file "$BODY_TRUTH" "$BODY_TRUTH_SHA256" body_truth
check_file "$HEADER_TRUTH" "$HEADER_TRUTH_SHA256" header_truth
(cd -- "$(dirname -- "$REVIEW")" \
  && sha256sum --quiet -c "$(basename -- "$REVIEW_SUMS")") || {
  printf 'reason=rank_review_checksum_failed\n\nSCRIPT RESULT\nscript_172_section_page_experiment_design=blocked\n' >&2
  exit 2
}
grep -Fxq 'script_171_published_v2_atomic_rank_failure_review=pass' \
  "$SCRIPT_171_REPORT" || {
  printf 'reason=script_171_not_clean\n\nSCRIPT RESULT\nscript_172_section_page_experiment_design=blocked\n' >&2
  exit 1
}
grep -Fq 'next_gate=design_bounded_section_page_aware_candidate_experiment_without_profile_or_corpus_promotion' \
  "$SCRIPT_171_REPORT" || {
  printf 'reason=script_171_next_gate_invalid\n\nSCRIPT RESULT\nscript_172_section_page_experiment_design=blocked\n' >&2
  exit 1
}

bash -n "${BASH_SOURCE[0]}"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
  "$DESIGNER"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$DESIGNER" --self-test \
  | grep -Fxq 'published_v2_section_page_experiment_design_self_test=pass' || {
  printf 'reason=designer_self_test_failed\n\nSCRIPT RESULT\nscript_172_section_page_experiment_design=blocked\n' >&2
  exit 2
}

run_designer() {
  local output_path="$1" stdout_path="$2" stderr_path="$3"
  PYTHONDONTWRITEBYTECODE=1 python3 -B "$DESIGNER" \
    --review "$REVIEW" \
    --chunks "$CHUNKS" \
    --body-truth "$BODY_TRUTH" \
    --header-truth "$HEADER_TRUTH" \
    --plan "$PLAN" \
    --output "$output_path" >"$stdout_path" 2>"$stderr_path"
}

validate_result() {
  local path="$1"
  PYTHONDONTWRITEBYTECODE=1 python3 -B - "$path" \
    "$REVIEW_SHA256" "$CHUNKS_SHA256" "$BODY_TRUTH_SHA256" \
    "$HEADER_TRUTH_SHA256" "$PLAN_SHA256" <<'PY'
import json
import pathlib
import sys

value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert value["artifact_kind"] == (
    "ishikawa_published_synthetic_corpus_v2_section_page_experiment_design"
)
assert value["schema_version"] == 1
assert value["source_sha256"] == {
    "rank_review": sys.argv[2],
    "chunk_artifact": sys.argv[3],
    "body_truth": sys.argv[4],
    "header_truth": sys.argv[5],
    "experiment_plan": sys.argv[6],
}
assert value["frozen_profile"] == {
    "exact_candidate_depth": 1,
    "lexical_candidate_depth": 20,
    "vector_candidate_depth": 20,
    "fused_candidate_depth": 20,
    "rrf_constant": 60,
    "lane_weights": {"exact": 1, "lexical": 1, "vector": 4},
    "learned_reranker": False,
}
inventory = value["candidate_inventory"]
assert inventory["published_atomic_candidates"] == 139
assert inventory["document_control_metadata_candidates"] == 6
assert inventory["body_atomic_candidates"] == 133
assert inventory["eligible_section_page_groups"] == 29
assert inventory["grouped_body_atomic_candidates"] == 123
assert inventory["ungrouped_body_atomic_candidates"] == 10
assert inventory["maximum_pre_collapse_candidates"] == 168
assert inventory["duplicate_evidence_groups"] == 3
assert inventory["duplicate_member_occurrences"] == 24
assert inventory["repeated_occurrences_beyond_canonical"] == 21
assert [item["name"] for item in value["variants"]] == [
    "atomic_baseline",
    "atomic_duplicate_canonical",
    "section_page",
    "section_page_duplicate_canonical",
]
assert value["measurement_contract"]["body_cases"] == 60
assert value["measurement_contract"]["header_cases"] == 8
assert value["eligibility_gate"]["body_mrr_at_20"] == ">0.91"
assert value["eligibility_gate"]["automatic_promotion"] is False
assert all(value["boundaries"][key] is False for key in (
    "black_corpus_access", "database_contact", "model_contact", "credential_read",
    "corpus_changed", "truth_changed", "service_changed", "package_changed",
    "production_profile_changed", "candidate_promoted",
))
assert value["next_gate"] == "execute_bounded_section_page_candidate_experiment"
PY
}

if [[ "$validate_only" == true ]]; then
  validation_root="$(mktemp -d /tmp/ishikawa-script-172-validation.XXXXXX)"
  trap 'rm -rf -- "$validation_root"' EXIT
  run_designer "$validation_root/design.json" \
    "$validation_root/designer.stdout" "$validation_root/designer.stderr"
  validate_result "$validation_root/design.json"
  printf '%s\n' \
    'purpose=validate_bounded_section_page_candidate_experiment_design' \
    'variants=4;section_page_groups=29;maximum_pre_collapse_candidates=168' \
    'duplicate_groups=3;duplicate_members=24;repeated_beyond_canonical=21' \
    'database_contact=false;model_contact=false;corpus_changed=false;profile_changed=false' \
    '' \
    'SCRIPT RESULT' \
    'script_172_section_page_experiment_design=pass'
  exit 0
fi

umask 077
mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/section_page_experiment_design_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-script-172.XXXXXX)"
suffix="${report_path##*_}"
suffix="${suffix%.txt}"
artifact_path="$ARTIFACT_ROOT/section_page_experiment_design_${timestamp}_${suffix}.json"
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
  [[ -n "$work_root" && "$work_root" == /tmp/ishikawa-script-172.* ]] \
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
    printf 'script_172_section_page_experiment_design=%s\n' "$script_result"
  } >>"$report_path"
  printf 'local_report=%s\n' "$report_path"
  printf 'local_report_sha256=%s\n' \
    "$(sha256sum "$report_path" | sed 's/[[:space:]].*$//')"
  printf '\nSCRIPT RESULT\n'
  [[ "$script_result" == pass ]] || printf 'reason=%s\n' "$failure_reason"
  printf 'script_172_section_page_experiment_design=%s\n' "$script_result"
  exit "$initial_status"
}
trap cleanup EXIT HUP INT TERM

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | sed 's/[[:space:]].*$//')"
emit 'purpose=design_bounded_section_page_candidate_experiment'
emit "started_utc=$timestamp;hostname=$(hostname);script_sha256=$script_sha256;designer_sha256=$DESIGNER_SHA256;plan_sha256=$PLAN_SHA256"
emit "script_171_report_sha256=$SCRIPT_171_REPORT_SHA256;rank_review_sha256=$REVIEW_SHA256;chunk_artifact_sha256=$CHUNKS_SHA256"
emit 'authorized_actions=validate_checksum_bound_synthetic_inputs_freeze_experiment_contract_retain_content_free_manifest'
emit 'non_actions=no_database_contact_no_model_contact_no_credential_read_no_black_corpus_access_no_corpus_change_no_truth_change_no_service_change_no_package_change_no_production_profile_change_no_candidate_promotion'
emit 'milestone=experiment_design;state=start;variants=4'

if ! run_designer "$work_root/design.json" \
  "$work_root/designer.stdout" "$work_root/designer.stderr"; then
  block designer_failed
fi
grep -Fxq 'published_v2_section_page_experiment_design=pass' \
  "$work_root/designer.stdout" || block designer_result_invalid
[[ ! -s "$work_root/designer.stderr" ]] || block designer_stderr_nonempty
validate_result "$work_root/design.json" || block design_contract_invalid
mv -- "$work_root/design.json" "$artifact_path"
printf '%s  %s\n' "$(sha256sum "$artifact_path" | sed 's/[[:space:]].*$//')" \
  "$(basename -- "$artifact_path")" >"$artifact_checksum_path"

artifact_sha256="$(sha256sum "$artifact_path" | sed 's/[[:space:]].*$//')"
emit 'milestone=experiment_design;state=pass;variants=4;section_page_groups=29;maximum_pre_collapse_candidates=168'
emit 'duplicate_canonicalization=groups:3,members:24,repeated_beyond_canonical:21;stored_atoms_removed:0'
emit 'frozen_profile=exact_depth:1,lexical_depth:20,vector_depth:20,fused_depth:20,rrf:60,weights:1:1:4,reranker:none'
emit 'eligibility_gate=body_mrr_at_20:strictly_greater_than_0.91,body_top20:60/60,header_mrr:1.000000,header_top5:8/8,header_evidence:11/11'
emit "design_artifact=$artifact_path;design_artifact_sha256=$artifact_sha256"
emit 'database_contact=false;model_contact=false;credential_read=false;corpus_changed=false;truth_changed=false;production_profile_changed=false;candidate_promoted=false'
emit 'next_gate=execute_bounded_section_page_candidate_experiment'
