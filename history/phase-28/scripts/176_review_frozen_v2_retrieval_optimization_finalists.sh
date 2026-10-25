#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Review Script 175's checksum-bound optimization finalists and authorize a
#   minimal repeated live-qualification set before any profile freeze.
#
# Boundaries:
#   Local content-free evidence only. No database, model, credential, corpus,
#   truth, service, release, package, or production-profile change.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/176_review_frozen_v2_retrieval_optimization_finalists.sh --run

usage() {
  sed -n '3,13p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Retain the checksum-bound finalist review.' \
    '  --validate-only Validate inputs and reproduce the review without retention.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly SCRIPT_175_REPORT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-frozen-optimization-search/frozen_v2_optimization_search_20261022T234515Z_OczP81.txt"
readonly OPTIMIZATION_OBSERVATION="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-frozen-optimization-search/frozen_v2_optimization_search_20261022T234515Z_OczP81.json"
readonly BASELINE_RECEIPT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-retrieval-baseline-promotion/retrieval_optimization_baseline_20261022T233825Z_8HJFhu.json"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-finalist-review"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-finalist-review"

readonly DECISIONS_SHA256='8b0ce284f90b661a5f48acd275e375b69292fa4035d93e42c2ca7b2b3c9c1013'
readonly SCRIPT_175_REPORT_SHA256='c810e7560616de9ee87ada2c1e10ca782b5d9a609fe9578aa61a9b65be3744e3'
readonly OPTIMIZATION_OBSERVATION_SHA256='b3da5e1c5faa51c202808e17d83437d32b2ddb34ce99ea43e9140169bfd55bda'
readonly BASELINE_RECEIPT_SHA256='6201b2dabc3112e71ad15e70c73cff6a87ba4e9534a69a0d3a037784b9905d92'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      printf 'reason=argument_invalid\n\nSCRIPT RESULT\nscript_176_frozen_v2_retrieval_optimization_finalist_review=blocked\n' >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'reason=mode_invalid\n\nSCRIPT RESULT\nscript_176_frozen_v2_retrieval_optimization_finalist_review=blocked\n' >&2
  exit 2
}

for command_name in awk basename bash cmp date dirname grep mkdir mktemp \
  python3 rm sed sha256sum tee; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'reason=local_command_missing;command=%s\n\nSCRIPT RESULT\nscript_176_frozen_v2_retrieval_optimization_finalist_review=blocked\n' \
      "$command_name" >&2
    exit 2
  }
done

check_file() {
  local path="$1" expected_sha256="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] || {
    printf 'reason=%s_unsafe\n\nSCRIPT RESULT\nscript_176_frozen_v2_retrieval_optimization_finalist_review=blocked\n' \
      "$label" >&2
    exit 2
  }
  [[ "$(sha256sum "$path" | awk '{print $1}')" == "$expected_sha256" ]] || {
    printf 'reason=%s_identity_changed\n\nSCRIPT RESULT\nscript_176_frozen_v2_retrieval_optimization_finalist_review=blocked\n' \
      "$label" >&2
    exit 2
  }
}

check_file "$DECISIONS" "$DECISIONS_SHA256" decisions
check_file "$SCRIPT_175_REPORT" "$SCRIPT_175_REPORT_SHA256" script_175_report
check_file "$OPTIMIZATION_OBSERVATION" "$OPTIMIZATION_OBSERVATION_SHA256" optimization_observation
check_file "$BASELINE_RECEIPT" "$BASELINE_RECEIPT_SHA256" baseline_receipt

(cd -- "$(dirname -- "$OPTIMIZATION_OBSERVATION")" \
  && sha256sum --quiet -c "$(basename -- "$OPTIMIZATION_OBSERVATION").sha256") || {
  printf 'reason=optimization_observation_checksum_manifest_failed\n\nSCRIPT RESULT\nscript_176_frozen_v2_retrieval_optimization_finalist_review=blocked\n' >&2
  exit 2
}
(cd -- "$(dirname -- "$BASELINE_RECEIPT")" \
  && sha256sum --quiet -c "$(basename -- "$BASELINE_RECEIPT").sha256") || {
  printf 'reason=baseline_receipt_checksum_manifest_failed\n\nSCRIPT RESULT\nscript_176_frozen_v2_retrieval_optimization_finalist_review=blocked\n' >&2
  exit 2
}
grep -Fxq 'script_175_frozen_synthetic_corpus_v2_retrieval_optimization_search=pass' \
  "$SCRIPT_175_REPORT" || {
  printf 'reason=script_175_not_clean\n\nSCRIPT RESULT\nscript_176_frozen_v2_retrieval_optimization_finalist_review=blocked\n' >&2
  exit 1
}
grep -Fxq 'next_gate=review_promoted_baseline_optimization_finalists_before_profile_freeze' \
  "$SCRIPT_175_REPORT" || {
  printf 'reason=script_175_next_gate_invalid\n\nSCRIPT RESULT\nscript_176_frozen_v2_retrieval_optimization_finalist_review=blocked\n' >&2
  exit 1
}
grep -Fxq 'database_write=false;accepted_database_contact=false;gemma_contact=false;corpus_changed=false;truth_changed=false;profile_changed=false;candidate_promoted=false;credentials_retained=false' \
  "$SCRIPT_175_REPORT" || {
  printf 'reason=script_175_boundary_evidence_missing\n\nSCRIPT RESULT\nscript_176_frozen_v2_retrieval_optimization_finalist_review=blocked\n' >&2
  exit 1
}
grep -Fq '| `V13-31` ' "$DECISIONS" || {
  printf 'reason=decision_v13_31_not_frozen\n\nSCRIPT RESULT\nscript_176_frozen_v2_retrieval_optimization_finalist_review=blocked\n' >&2
  exit 1
}

build_review() {
  local output_path="$1"
  PYTHONDONTWRITEBYTECODE=1 python3 -B - \
    "$OPTIMIZATION_OBSERVATION" "$BASELINE_RECEIPT" "$output_path" \
    "$DECISIONS_SHA256" "$SCRIPT_175_REPORT_SHA256" \
    "$OPTIMIZATION_OBSERVATION_SHA256" "$BASELINE_RECEIPT_SHA256" <<'PY'
import json
import os
import pathlib
import sys
from fractions import Fraction

(
    observation_path,
    baseline_path,
    output_path,
    decisions_sha256,
    script_175_report_sha256,
    observation_sha256,
    baseline_sha256,
) = sys.argv[1:]

observation = json.loads(pathlib.Path(observation_path).read_text(encoding="utf-8"))
baseline_receipt = json.loads(pathlib.Path(baseline_path).read_text(encoding="utf-8"))

assert observation["artifact_kind"] == "ishikawa_promoted_v2_section_page_optimization_search"
assert observation["schema_version"] == 1
assert observation["profile_counts"] == {
    "acceptance_gate": 1250,
    "acceptance_gate_without_body_regressions": 465,
    "evaluated": 2646,
}
assert observation["deterministic_finalist_replay"] is True
assert observation["next_gate"] == "review_promoted_baseline_optimization_finalists_before_profile_freeze"
assert observation["boundaries"] == {
    "accepted_database_contact": False,
    "black_corpus_access": False,
    "candidate_promoted": False,
    "corpus_changed": False,
    "database_tables_read": False,
    "database_write": False,
    "gemma_contact": False,
    "nomic_contact": True,
    "private_temporary_postgresql": True,
    "production_profile_changed": False,
    "truth_changed": False,
}
assert baseline_receipt["artifact_kind"] == "ishikawa_synthetic_corpus_v2_retrieval_optimization_baseline"
assert baseline_receipt["state"] == "promoted_frozen_optimization_baseline"
assert baseline_receipt["decision"]["id"] == "V13-31"

promoted = observation["baseline_replay"]
selected = observation["best_observed_profile"]
promoted_profile = promoted["profile"]
selected_profile = selected["profile"]
assert promoted_profile == {
    "exact_weight": 1,
    "lexical_depth": 20,
    "lexical_weight": 1,
    "rrf_constant": 60,
    "vector_depth": 20,
    "vector_weight": 4,
}
assert selected_profile == {
    "exact_weight": 1,
    "lexical_depth": 20,
    "lexical_weight": 2,
    "rrf_constant": 60,
    "vector_depth": 20,
    "vector_weight": 4,
}
assert promoted["body_metrics"]["mrr_at_20"] == "0.903333"
assert selected["body_metrics"]["mrr_at_20"] == "0.915833"
assert selected["body_metrics"]["relevant_at_5"] == 60
assert selected["body_metrics"]["relevant_at_20"] == 60
assert selected["body_metrics"]["required_evidence_matched_at_20"] == 60
assert selected["body_metrics"]["required_evidence_total"] == 60
assert selected["header_metrics"]["mrr_at_20"] == "1.000000"
assert selected["header_metrics"]["relevant_at_5"] == 8
assert selected["header_metrics"]["required_evidence_matched_at_20"] == 11
assert selected["improved_body_case_ids"] == ["E-033", "E-051"]
assert selected["regressed_body_case_ids"] == []
assert selected["profile_distance_from_promoted"] == 1

finalists = observation["finalists"]
assert len(finalists) == 25
assert all(item["body_metrics"]["mrr_at_20"] == "0.915833" for item in finalists)
assert all(item["body_metrics"]["relevant_at_5"] == 60 for item in finalists)
assert all(item["body_metrics"]["relevant_at_20"] == 60 for item in finalists)
assert all(item["regressed_body_case_ids"] == [] for item in finalists)
assert finalists[0] == selected
assert any(
    item["profile"]["lexical_weight"] == 1
    and item["profile"]["vector_weight"] == 2
    for item in finalists
)

promoted_mrr = Fraction(
    promoted["body_metrics"]["mrr_fraction_numerator"],
    promoted["body_metrics"]["mrr_fraction_denominator"],
)
selected_mrr = Fraction(
    selected["body_metrics"]["mrr_fraction_numerator"],
    selected["body_metrics"]["mrr_fraction_denominator"],
)
assert selected_mrr - promoted_mrr == Fraction(1, 80)

review = {
    "artifact_kind": "ishikawa_synthetic_corpus_v2_optimization_finalist_review",
    "boundaries": {
        "accepted_database_contact": False,
        "candidate_promoted": False,
        "corpus_changed": False,
        "credential_read": False,
        "database_contact": False,
        "database_write": False,
        "model_contact": False,
        "production_profile_changed": False,
        "truth_changed": False,
    },
    "comparison": {
        "body_mrr_absolute_gain": "0.012500",
        "body_relevant_at_20_preserved": "60/60",
        "body_relevant_at_5_preserved": "60/60",
        "header_mrr_preserved": "1.000000",
        "header_required_evidence_preserved": "11/11",
        "improved_body_case_ids": selected["improved_body_case_ids"],
        "regressed_body_case_ids": selected["regressed_body_case_ids"],
    },
    "decision": {
        "decision_list_sha256": decisions_sha256,
        "governing_id": "V13-31",
        "profile_freeze_authorized": False,
    },
    "live_qualification_design": {
        "baseline_profile": promoted_profile,
        "candidate_profile": selected_profile,
        "cases_per_run": 68,
        "candidate_gate": {
            "body_mrr_at_20": ">0.910000",
            "body_mrr_not_below_baseline": True,
            "body_relevant_at_20": "60/60",
            "body_required_evidence_at_20": "60/60",
            "header_mrr_at_20": "1.000000",
            "header_relevant_at_5": "8/8",
            "header_required_evidence_at_20": "11/11",
            "new_body_case_regressions": 0,
        },
        "fresh_nomic_query_embeddings_each_run": True,
        "fresh_postgresql_lexical_measurement_each_run": True,
        "latency_percentiles": ["median", "p95"],
        "latency_stages": [
            "query_embedding",
            "exact_lane",
            "lexical_lane",
            "vector_lane",
            "fusion_and_collapse",
            "total_retrieval",
        ],
        "profile_freeze_authorized_by_live_qualification": False,
        "repeated_warm_runs": 5,
        "same_captured_lanes_compare_baseline_and_candidate": True,
    },
    "next_gate": "execute_repeated_live_qualification_of_selected_v2_retrieval_finalist",
    "review": {
        "all_retained_finalists_metric_tied": True,
        "retained_finalist_count": 25,
        "selection_basis": [
            "highest_body_mrr_at_20",
            "complete_body_and_header_coverage",
            "zero_observed_body_case_regressions",
            "minimum_parameter_distance_from_promoted_baseline",
            "single_parameter_change",
        ],
        "proportional_non_exact_weight_alternative_observed": True,
        "proportional_alternative_assumed_globally_equivalent": False,
        "reason_not_assumed_globally_equivalent": "exact-lane contribution remains independently weighted",
        "selected_parameter_delta": {
            "lexical_weight": {"from": 1, "to": 2},
        },
    },
    "schema_version": 1,
    "selected_candidate": selected,
    "source_sha256": {
        "baseline_receipt": baseline_sha256,
        "decisions": decisions_sha256,
        "optimization_observation": observation_sha256,
        "script_175_report": script_175_report_sha256,
    },
}

payload = (json.dumps(review, indent=2, sort_keys=True) + "\n").encode("utf-8")
path = pathlib.Path(output_path)
descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(descriptor, "wb") as stream:
    stream.write(payload)
PY
}

validate_review() {
  local path="$1"
  PYTHONDONTWRITEBYTECODE=1 python3 -B - "$path" <<'PY'
import json
import pathlib
import sys

value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert value["artifact_kind"] == "ishikawa_synthetic_corpus_v2_optimization_finalist_review"
assert value["schema_version"] == 1
assert value["decision"]["governing_id"] == "V13-31"
assert value["decision"]["profile_freeze_authorized"] is False
assert value["review"]["retained_finalist_count"] == 25
assert value["review"]["all_retained_finalists_metric_tied"] is True
assert value["review"]["selected_parameter_delta"] == {
    "lexical_weight": {"from": 1, "to": 2}
}
assert value["comparison"]["body_mrr_absolute_gain"] == "0.012500"
assert value["comparison"]["improved_body_case_ids"] == ["E-033", "E-051"]
assert value["comparison"]["regressed_body_case_ids"] == []
assert value["live_qualification_design"]["repeated_warm_runs"] == 5
assert value["live_qualification_design"]["candidate_gate"]["body_mrr_at_20"] == ">0.910000"
assert value["live_qualification_design"]["profile_freeze_authorized_by_live_qualification"] is False
assert value["next_gate"] == "execute_repeated_live_qualification_of_selected_v2_retrieval_finalist"
assert not any(value["boundaries"].values())
PY
}

bash -n "${BASH_SOURCE[0]}"
validation_root="$(mktemp -d /tmp/ishikawa-script-176-validation.XXXXXX)"
trap 'rm -rf -- "$validation_root"' EXIT
build_review "$validation_root/review-a.json"
build_review "$validation_root/review-b.json"
cmp --silent "$validation_root/review-a.json" "$validation_root/review-b.json" || {
  printf 'reason=finalist_review_not_repeatable\n\nSCRIPT RESULT\nscript_176_frozen_v2_retrieval_optimization_finalist_review=blocked\n' >&2
  exit 2
}
validate_review "$validation_root/review-a.json"
validation_review_sha256="$(sha256sum "$validation_root/review-a.json" | awk '{print $1}')"
rm -rf -- "$validation_root"
trap - EXIT

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_frozen_v2_retrieval_optimization_finalist_review' \
    "script_sha256=$script_sha256;optimization_observation_sha256=$OPTIMIZATION_OBSERVATION_SHA256;decision=V13-31" \
    'baseline_body_mrr_at_20=0.903333;selected_body_mrr_at_20=0.915833;absolute_gain=0.012500' \
    'selected_delta=lexical_weight_1_to_2;improved_cases=E-033,E-051;regressed_cases=none' \
    'retained_finalists=25;retained_finalists_metric_tied=true;live_qualification_runs=5' \
    "validation_review_sha256=$validation_review_sha256" \
    'database_contact=false;model_contact=false;credential_read=false;corpus_changed=false;truth_changed=false;production_profile_changed=false;candidate_promoted=false' \
    '' \
    'SCRIPT RESULT' \
    'script_176_frozen_v2_retrieval_optimization_finalist_review=pass'
  exit 0
fi

umask 077
mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT" || {
  printf 'reason=local_output_root_creation_failed\n\nSCRIPT RESULT\nscript_176_frozen_v2_retrieval_optimization_finalist_review=blocked\n' >&2
  exit 2
}
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" && -w "$REPORT_ROOT" ]] || {
  printf 'reason=report_root_unsafe\n\nSCRIPT RESULT\nscript_176_frozen_v2_retrieval_optimization_finalist_review=blocked\n' >&2
  exit 2
}
[[ -d "$ARTIFACT_ROOT" && ! -L "$ARTIFACT_ROOT" && -w "$ARTIFACT_ROOT" ]] || {
  printf 'reason=artifact_root_unsafe\n\nSCRIPT RESULT\nscript_176_frozen_v2_retrieval_optimization_finalist_review=blocked\n' >&2
  exit 2
}

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/finalist_review_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-script-176.XXXXXX)"
suffix="${report_path##*_}"; suffix="${suffix%.txt}"
artifact_path="$ARTIFACT_ROOT/finalist_review_${timestamp}_${suffix}.json"
artifact_checksum_path="$artifact_path.sha256"
failure_reason=''
readonly MAIN_BASHPID="$BASHPID"

emit() {
  if ! printf '%s\n' "$1" | tee -a "$report_path"; then
    failure_reason='report_write_failed'
    exit 1
  fi
}
block() { failure_reason="$1"; exit 1; }

cleanup() {
  local initial_status="$?" result='blocked'
  trap - ERR EXIT HUP INT TERM
  if [[ "$BASHPID" != "$MAIN_BASHPID" ]]; then
    exit "$initial_status"
  fi
  set +e
  [[ "$work_root" == /tmp/ishikawa-script-176.* ]] && rm -rf -- "$work_root"
  if (( initial_status == 0 )); then
    result='pass'
  else
    [[ -n "$failure_reason" ]] || failure_reason="unexpected_failure_exit_$initial_status"
    [[ "$artifact_path" == "$ARTIFACT_ROOT"/* ]] \
      && rm -f -- "$artifact_path" "$artifact_checksum_path"
  fi
  {
    printf '\nSCRIPT RESULT\n'
    [[ "$result" == pass ]] || printf 'reason=%s\n' "$failure_reason"
    printf 'script_176_frozen_v2_retrieval_optimization_finalist_review=%s\n' "$result"
  } >>"$report_path"
  printf 'local_report=%s\n' "$report_path"
  printf 'local_report_sha256=%s\n' "$(sha256sum "$report_path" | awk '{print $1}')"
  printf '\nSCRIPT RESULT\n'
  [[ "$result" == pass ]] || printf 'reason=%s\n' "$failure_reason"
  printf 'script_176_frozen_v2_retrieval_optimization_finalist_review=%s\n' "$result"
  exit "$initial_status"
}
trap cleanup EXIT
trap 'failure_reason="interrupted_hup"; exit 129' HUP
trap 'failure_reason="interrupted_int"; exit 130' INT
trap 'failure_reason="interrupted_term"; exit 143' TERM

emit 'purpose=review_frozen_v2_retrieval_optimization_finalists'
emit "started_utc=$timestamp;script_sha256=$script_sha256;decision=V13-31"
emit 'authorized_actions=validate_checksum_bound_script_175_observation_review_retained_finalists_select_minimum_delta_candidate_define_repeated_live_qualification_retain_local_review'
emit 'non_actions=no_database_contact_no_model_contact_no_credential_read_no_corpus_change_no_truth_change_no_service_change_no_package_change_no_release_change_no_profile_change_no_candidate_promotion'

build_review "$work_root/review.json" || block finalist_review_build_failed
validate_review "$work_root/review.json" || block finalist_review_validation_failed
review_sha256="$(sha256sum "$work_root/review.json" | awk '{print $1}')"
[[ "$review_sha256" == "$validation_review_sha256" ]] \
  || block finalist_review_not_repeatable_at_retention

[[ ! -e "$artifact_path" && ! -L "$artifact_path" ]] \
  || block finalist_review_destination_exists
tee -- "$artifact_path" <"$work_root/review.json" >/dev/null \
  || block finalist_review_retention_failed
[[ "$(sha256sum "$artifact_path" | awk '{print $1}')" == "$review_sha256" ]] \
  || block finalist_review_identity_changed_after_retention
if ! printf '%s  %s\n' "$review_sha256" "$(basename -- "$artifact_path")" \
    >"$artifact_checksum_path"; then
  block finalist_review_checksum_manifest_write_failed
fi
if ! (trap - EXIT HUP INT TERM; cd -- "$ARTIFACT_ROOT" \
    && sha256sum --quiet -c "$(basename -- "$artifact_checksum_path")"); then
  block finalist_review_checksum_manifest_failed
fi

emit 'milestone=finalist_review;state=pass;retained_finalists=25;all_metric_tied=true;selected_delta=lexical_weight_1_to_2'
emit 'baseline_body_mrr_at_20=0.903333;selected_body_mrr_at_20=0.915833;absolute_gain=0.012500;body_top5=60/60;body_top20=60/60'
emit 'improved_body_cases=E-033,E-051;regressed_body_cases=none;header_mrr_at_20=1.000000;header_required_evidence=11/11'
emit 'milestone=live_qualification_design;state=pass;warm_runs=5;cases_per_run=68;candidate_profile_freeze_authorized=false'
emit "finalist_review=$artifact_path;finalist_review_sha256=$review_sha256"
emit 'database_contact=false;model_contact=false;credential_read=false;corpus_changed=false;truth_changed=false;profile_changed=false;candidate_promoted=false'
emit 'next_gate=execute_repeated_live_qualification_of_selected_v2_retrieval_finalist'
