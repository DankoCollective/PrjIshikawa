#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Bind and review the clean, nonqualifying V13-45 observation without model,
#   database, corpus, retrieval-profile, or production changes.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/198_review_v13_45_hierarchical_failures.sh --run

usage() {
  sed -n '3,10p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Retain the content-free V13-45 failure review.' \
    '  --validate-only Validate inputs and review implementation only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly REVIEWER="$SCRIPT_DIR/review_v13_45_hierarchical_failures.py"
readonly REPORT="$REPO_ROOT/local/reports/ishikawa-v13-45-hierarchical-document-section-ranking/v13_45_hierarchical_document_section_20261023T140258Z_rZJx8d.txt"
readonly OBSERVATION="$REPO_ROOT/local/artifacts/ishikawa/v13-45-hierarchical-document-section-ranking/v13_45_hierarchical_document_section_20261023T140258Z.json"
readonly REPORT_SHA256='83e6fe9c4368fb670e2c59b3b0f0ed5aec84a51c795065e6e5ae7ae29ad20c21'
readonly OBSERVATION_SHA256='9cecc0f1ad037db726db708e1e0943001a415cefb9f0e344b5db858e729ec317'
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v13-45-hierarchical-failure-review"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v13-45-hierarchical-failure-review"

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      usage >&2
      printf '\nSCRIPT RESULT\nscript_198_v13_45_hierarchical_failure_review=blocked\n' >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'reason=exactly_one_mode_required\n\nSCRIPT RESULT\nscript_198_v13_45_hierarchical_failure_review=blocked\n' >&2
  exit 2
}

for command_name in awk date grep mkdir mktemp mv python3 rm sed sha256sum tail tee; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'reason=missing_command_%s\n\nSCRIPT RESULT\nscript_198_v13_45_hierarchical_failure_review=blocked\n' \
      "$command_name" >&2
    exit 2
  }
done

check_file() {
  local path="$1" expected="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] || {
    printf 'reason=%s_unsafe\n\nSCRIPT RESULT\nscript_198_v13_45_hierarchical_failure_review=blocked\n' \
      "$label" >&2
    exit 1
  }
  [[ "$(sha256sum "$path" | awk '{print $1}')" == "$expected" ]] || {
    printf 'reason=%s_identity_changed\n\nSCRIPT RESULT\nscript_198_v13_45_hierarchical_failure_review=blocked\n' \
      "$label" >&2
    exit 1
  }
}

check_file "$REPORT" "$REPORT_SHA256" script_197_report
check_file "$OBSERVATION" "$OBSERVATION_SHA256" script_197_observation
[[ -f "$REVIEWER" && ! -L "$REVIEWER" && -r "$REVIEWER" ]] || {
  printf 'reason=reviewer_unsafe\n\nSCRIPT RESULT\nscript_198_v13_45_hierarchical_failure_review=blocked\n' >&2
  exit 1
}

grep -Fxq 'milestone=native_tests;state=pass;tests=444' "$REPORT"
grep -Fxq 'selection_status=not_met;selected_candidate=none;promotion_authorized=false' "$REPORT"
grep -Fxq 'observation_validation=pass' "$REPORT"
grep -Fxq 'milestone=temporary_postgresql_cleanup;state=pass;cluster_retained=false;listener_retained=false' "$REPORT"
! grep -Fq 'script_state=blocked' "$REPORT"

bash -n "${BASH_SOURCE[0]}"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
  "$REVIEWER"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$REVIEWER" --self-test \
  | grep -Fxq 'v13_45_hierarchical_failure_review_self_test=pass'

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
reviewer_sha256="$(sha256sum "$REVIEWER" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_v13_45_hierarchical_failure_review' \
    "script_sha256=$script_sha256;reviewer_sha256=$reviewer_sha256" \
    "script_197_report_sha256=$REPORT_SHA256;script_197_observation_sha256=$OBSERVATION_SHA256" \
    'model_contact=false;database_contact=false;corpus_change=false;profile_change=false' \
    '' \
    'SCRIPT RESULT' \
    'script_198_v13_45_hierarchical_failure_review=pass'
  exit 0
fi

umask 077
mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" \
   && -d "$ARTIFACT_ROOT" && ! -L "$ARTIFACT_ROOT" ]] || {
  printf 'reason=output_directory_unsafe\n\nSCRIPT RESULT\nscript_198_v13_45_hierarchical_failure_review=blocked\n' >&2
  exit 1
}
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/v13_45_hierarchical_failure_review_${timestamp}_XXXXXX.txt")"
artifact_path="$ARTIFACT_ROOT/v13_45_hierarchical_failure_review_${timestamp}.json"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" ]] || {
  printf 'reason=artifact_path_exists\n' | tee -a "$report_path"
  printf '\nSCRIPT RESULT\nscript_198_v13_45_hierarchical_failure_review=blocked\n'
  exit 1
}
work_root="$(mktemp -d "$ARTIFACT_ROOT/.script-198.XXXXXX")"
candidate="$work_root/review.json"
cleanup() {
  local status="$?"
  trap - EXIT
  if (( status != 0 )); then
    if [[ -s "$work_root/reviewer.stderr" ]]; then
      printf 'diagnostic_reviewer_stderr_tail_begin;maximum_lines=200\n' | tee -a "$report_path"
      tail -n 200 -- "$work_root/reviewer.stderr" | tee -a "$report_path"
      printf 'diagnostic_reviewer_stderr_tail_end\n' | tee -a "$report_path"
    fi
    printf 'script_state=blocked;exit_code=%s\n' "$status" | tee -a "$report_path"
    printf '\nSCRIPT RESULT\nscript_198_v13_45_hierarchical_failure_review=blocked\n'
  fi
  if [[ "$work_root" == "$ARTIFACT_ROOT"/.script-198.* && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  exit "$status"
}
trap cleanup EXIT

PYTHONDONTWRITEBYTECODE=1 python3 -B "$REVIEWER" \
  --observation "$OBSERVATION" --expected-sha256 "$OBSERVATION_SHA256" \
  --source-report-sha256 "$REPORT_SHA256" \
  --output "$candidate" >"$work_root/reviewer.stdout" 2>"$work_root/reviewer.stderr"
grep -Fxq 'v13_45_hierarchical_failure_review=pass' "$work_root/reviewer.stdout"

PYTHONDONTWRITEBYTECODE=1 python3 -B - "$candidate" <<'PY' | tee "$report_path"
import json,pathlib,sys
x=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
best=x["best_v13_45_variant"]
b=x["baseline"]
v=x["variant_summaries"][best]
f=x["findings"]
print("purpose=review_clean_nonqualifying_v13_45_observation")
print(f"baseline_body_mrr_at_20={b['body_mrr_at_20']};baseline_body_relevant_at_20={b['body_relevant_at_20']}/120")
print(f"best_variant={best};body_mrr_at_20={v['body_mrr_at_20']};body_relevant_at_20={v['body_relevant_at_20']}/120")
print(f"best_variant_section_position_2={f['best_variant_relevant_section_second_within_document']};section_position_3={f['best_variant_relevant_section_third_within_document']}")
print(f"best_variant_document_rank_1_but_section_after_rank_5={f['best_variant_document_rank_1_but_section_after_rank_5']};relevant_at_rank_9_or_later={f['best_variant_relevant_at_rank_9_or_later']}")
print(f"best_variant_document_not_shortlisted={f['best_variant_missing_because_document_not_shortlisted']};section_not_emitted_top_20={f['best_variant_missing_because_section_not_emitted_top_20']}")
print("diagnosis=strict_round_robin_is_primary_regression_source")
print("implementation_defect=false;v13_45_candidate_accepted=false;promotion_authorized=false")
print("next_gate=discuss_and_freeze_any_reopened_candidate_generation_and_cross_document_section_ordering")
PY

mv -- "$candidate" "$artifact_path"
artifact_sha256="$(sha256sum "$artifact_path" | awk '{print $1}')"
printf 'review_artifact=%s;review_artifact_sha256=%s\n' \
  "$artifact_path" "$artifact_sha256" | tee -a "$report_path"
printf 'script_state=pass;model_contact=false;database_contact=false;corpus_change=false;profile_change=false\n' \
  | tee -a "$report_path"
report_sha256="$(sha256sum "$report_path" | awk '{print $1}')"
printf 'local_report=%s;local_report_sha256=%s\n' "$report_path" "$report_sha256"
rm -rf -- "$work_root"
trap - EXIT
printf '\nSCRIPT RESULT\nscript_198_v13_45_hierarchical_failure_review=pass\n'
