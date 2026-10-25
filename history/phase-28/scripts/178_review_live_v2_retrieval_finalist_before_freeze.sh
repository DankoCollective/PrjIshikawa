#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Review Script 177's repeated live qualification and produce a bounded
#   ready-to-freeze recommendation for an explicit operator decision.
#
# Boundaries:
#   Local content-free evidence only. No database, model, credential, corpus,
#   truth, source-profile, release, package, service, or org-lab change.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/178_review_live_v2_retrieval_finalist_before_freeze.sh --run

usage() {
  sed -n '3,13p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Retain the checksum-bound pre-freeze review.' \
    '  --validate-only Validate inputs and reproduce the review without retention.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly SCRIPT_177_REPORT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-finalist-live-qualification/finalist_live_qualification_20261022T235752Z_FLhBmy.txt"
readonly LIVE_QUALIFICATION="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-finalist-live-qualification/finalist_live_qualification_20261022T235752Z_FLhBmy.json"
readonly FINALIST_REVIEW="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-finalist-review/finalist_review_20261022T234902Z_xpGoA6.json"
readonly BASELINE_RECEIPT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-retrieval-baseline-promotion/retrieval_optimization_baseline_20261022T233825Z_8HJFhu.json"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-pre-freeze-review"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-pre-freeze-review"

readonly DECISIONS_SHA256='8b0ce284f90b661a5f48acd275e375b69292fa4035d93e42c2ca7b2b3c9c1013'
readonly SCRIPT_177_REPORT_SHA256='1c5aa7357e0a1b44930269eb73757b242c6a93247bd5ab77e6157953feb9fb11'
readonly LIVE_QUALIFICATION_SHA256='a1158ea7b85532bc3c8bebaa7c7f9ef820ef4aee703d50aee79a7b363391c801'
readonly FINALIST_REVIEW_SHA256='5aa174419d105ba98326d91c5fa370151ba7962c43a502a97357f49ee6e16184'
readonly BASELINE_RECEIPT_SHA256='6201b2dabc3112e71ad15e70c73cff6a87ba4e9534a69a0d3a037784b9905d92'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      printf 'reason=argument_invalid\n\nSCRIPT RESULT\nscript_178_live_v2_retrieval_finalist_pre_freeze_review=blocked\n' >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'reason=mode_invalid\n\nSCRIPT RESULT\nscript_178_live_v2_retrieval_finalist_pre_freeze_review=blocked\n' >&2
  exit 2
}

for command_name in awk basename bash cmp date dirname grep mkdir mktemp \
  python3 rm sed sha256sum tee; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'reason=local_command_missing;command=%s\n\nSCRIPT RESULT\nscript_178_live_v2_retrieval_finalist_pre_freeze_review=blocked\n' \
      "$command_name" >&2
    exit 2
  }
done

check_file() {
  local path="$1" expected_sha256="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] || {
    printf 'reason=%s_unsafe\n\nSCRIPT RESULT\nscript_178_live_v2_retrieval_finalist_pre_freeze_review=blocked\n' \
      "$label" >&2
    exit 2
  }
  [[ "$(sha256sum "$path" | awk '{print $1}')" == "$expected_sha256" ]] || {
    printf 'reason=%s_identity_changed\n\nSCRIPT RESULT\nscript_178_live_v2_retrieval_finalist_pre_freeze_review=blocked\n' \
      "$label" >&2
    exit 2
  }
}

check_file "$DECISIONS" "$DECISIONS_SHA256" decisions
check_file "$SCRIPT_177_REPORT" "$SCRIPT_177_REPORT_SHA256" script_177_report
check_file "$LIVE_QUALIFICATION" "$LIVE_QUALIFICATION_SHA256" live_qualification
check_file "$FINALIST_REVIEW" "$FINALIST_REVIEW_SHA256" finalist_review
check_file "$BASELINE_RECEIPT" "$BASELINE_RECEIPT_SHA256" baseline_receipt

for artifact in "$LIVE_QUALIFICATION" "$FINALIST_REVIEW" "$BASELINE_RECEIPT"; do
  (cd -- "$(dirname -- "$artifact")" \
    && sha256sum --quiet -c "$(basename -- "$artifact").sha256") || {
    printf 'reason=input_checksum_manifest_failed\n\nSCRIPT RESULT\nscript_178_live_v2_retrieval_finalist_pre_freeze_review=blocked\n' >&2
    exit 2
  }
done
grep -Fxq 'script_177_selected_v2_retrieval_finalist_live_qualification=pass' \
  "$SCRIPT_177_REPORT" || {
  printf 'reason=script_177_not_clean\n\nSCRIPT RESULT\nscript_178_live_v2_retrieval_finalist_pre_freeze_review=blocked\n' >&2
  exit 1
}
grep -Fxq 'next_gate=review_repeated_live_finalist_qualification_before_profile_freeze' \
  "$SCRIPT_177_REPORT" || {
  printf 'reason=script_177_next_gate_invalid\n\nSCRIPT RESULT\nscript_178_live_v2_retrieval_finalist_pre_freeze_review=blocked\n' >&2
  exit 1
}
grep -Fxq 'database_write=false;accepted_database_contact=false;gemma_contact=false;corpus_changed=false;truth_changed=false;profile_changed=false;candidate_promoted=false;credentials_retained=false' \
  "$SCRIPT_177_REPORT" || {
  printf 'reason=script_177_boundary_evidence_missing\n\nSCRIPT RESULT\nscript_178_live_v2_retrieval_finalist_pre_freeze_review=blocked\n' >&2
  exit 1
}
grep -Fq '| `V13-31` ' "$DECISIONS" || {
  printf 'reason=decision_v13_31_not_frozen\n\nSCRIPT RESULT\nscript_178_live_v2_retrieval_finalist_pre_freeze_review=blocked\n' >&2
  exit 1
}

build_review() {
  local output_path="$1"
  PYTHONDONTWRITEBYTECODE=1 python3 -B - \
    "$LIVE_QUALIFICATION" "$FINALIST_REVIEW" "$BASELINE_RECEIPT" \
    "$output_path" "$DECISIONS_SHA256" "$SCRIPT_177_REPORT_SHA256" \
    "$LIVE_QUALIFICATION_SHA256" "$FINALIST_REVIEW_SHA256" \
    "$BASELINE_RECEIPT_SHA256" <<'PY'
import hashlib
import json
import os
import pathlib
import sys
from decimal import Decimal

(
    qualification_path,
    finalist_review_path,
    baseline_path,
    output_path,
    decisions_sha256,
    script_177_report_sha256,
    qualification_sha256,
    finalist_review_sha256,
    baseline_sha256,
) = sys.argv[1:]

qualification = json.loads(pathlib.Path(qualification_path).read_text(encoding="utf-8"))
finalist_review = json.loads(pathlib.Path(finalist_review_path).read_text(encoding="utf-8"))
baseline = json.loads(pathlib.Path(baseline_path).read_text(encoding="utf-8"))

assert qualification["artifact_kind"] == "ishikawa_selected_v2_retrieval_finalist_live_qualification"
assert qualification["schema_version"] == 1
assert qualification["qualification_gate_met"] is True
assert qualification["deterministic_across_measured_runs"] is True
assert qualification["profile_freeze_authorized"] is False
assert qualification["inventory"] == {
    "atomic_candidates": 139,
    "cases_per_run": 68,
    "measured_runs": 5,
    "query_embedding_tokens_per_run": 1204,
    "section_page_representatives": 29,
    "warmup_runs": 1,
}
assert qualification["next_gate"] == "review_repeated_live_finalist_qualification_before_profile_freeze"
assert finalist_review["artifact_kind"] == "ishikawa_synthetic_corpus_v2_optimization_finalist_review"
assert finalist_review["live_qualification_design"]["candidate_profile"] == qualification["candidate_profile"]
assert baseline["artifact_kind"] == "ishikawa_synthetic_corpus_v2_retrieval_optimization_baseline"
assert baseline["selected_variant"]["name"] == "section_page_duplicate_canonical"
assert baseline["selected_variant"]["metrics"]["body"]["mrr_at_20"] == "0.903333"

runs = qualification["runs"]
assert len(runs) == 5
assert [run["run"] for run in runs] == [1, 2, 3, 4, 5]
assert all(run["measured"] is True for run in runs)
assert all(run["candidate_gate_met"] is True for run in runs)
assert all(run["query_embedding_tokens"] == 1204 for run in runs)
assert all(run["baseline_metrics"]["body"]["mrr_at_20"] == "0.903333" for run in runs)
assert all(run["candidate_metrics"]["body"]["mrr_at_20"] == "0.915833" for run in runs)
assert all(run["candidate_metrics"]["body"]["relevant_at_5"] == 60 for run in runs)
assert all(run["candidate_metrics"]["body"]["relevant_at_20"] == 60 for run in runs)
assert all(run["candidate_metrics"]["body"]["required_evidence_matched_at_20"] == 60 for run in runs)
assert all(run["candidate_metrics"]["header"]["mrr_at_20"] == "1.000000" for run in runs)
assert all(run["candidate_metrics"]["header"]["relevant_at_5"] == 8 for run in runs)
assert all(run["candidate_metrics"]["header"]["required_evidence_matched_at_20"] == 11 for run in runs)
assert all(run["improved_body_case_ids"] == ["E-033", "E-051"] for run in runs)
assert all(run["regressed_body_case_ids"] == [] for run in runs)
assert not any(
    value
    for key, value in qualification["boundaries"].items()
    if key not in {"nomic_contact", "private_temporary_postgresql"}
)
assert qualification["boundaries"]["nomic_contact"] is True
assert qualification["boundaries"]["private_temporary_postgresql"] is True

latency = qualification["latency"]
baseline_median = Decimal(latency["baseline_total_retrieval"]["median_ms"])
candidate_median = Decimal(latency["candidate_total_retrieval"]["median_ms"])
baseline_p95 = Decimal(latency["baseline_total_retrieval"]["p95_ms"])
candidate_p95 = Decimal(latency["candidate_total_retrieval"]["p95_ms"])
assert candidate_median <= baseline_median
assert candidate_p95 <= baseline_p95

candidate = {
    "behavior": {
        "document_local_duplicate_canonicalization": True,
        "section_page_representatives": True,
    },
    "profile": qualification["candidate_profile"],
}
candidate_identity = hashlib.sha256(
    b"ishikawa.v2-retrieval-candidate.v1\x00"
    + json.dumps(candidate, sort_keys=True, separators=(",", ":")).encode("utf-8")
).hexdigest()

review = {
    "artifact_kind": "ishikawa_live_v2_retrieval_finalist_pre_freeze_review",
    "boundaries": {
        "accepted_release_changed": False,
        "candidate_frozen": False,
        "candidate_promoted": False,
        "corpus_changed": False,
        "database_contact": False,
        "database_write": False,
        "deployment_package_changed": False,
        "model_contact": False,
        "org_lab_changed": False,
        "production_profile_changed": False,
        "source_profile_changed": False,
        "truth_changed": False,
    },
    "candidate": {
        **candidate,
        "identity": candidate_identity,
        "parameter_delta_from_promoted_baseline": {
            "lexical_weight": {"from": 1, "to": 2},
        },
    },
    "decision": {
        "decision_list_sha256": decisions_sha256,
        "governing_id": "V13-31",
        "new_freeze_decision_required": True,
        "operator_freeze_received": False,
    },
    "evidence": {
        "baseline_body_mrr_at_20": "0.903333",
        "candidate_body_mrr_at_20": "0.915833",
        "candidate_body_relevant_at_5": "60/60",
        "candidate_body_relevant_at_20": "60/60",
        "candidate_header_mrr_at_20": "1.000000",
        "candidate_header_required_evidence_at_20": "11/11",
        "improved_body_case_ids": ["E-033", "E-051"],
        "measured_runs": 5,
        "rank_deterministic": True,
        "regressed_body_case_ids": [],
    },
    "latency_diagnostic": {
        "baseline_total_median_ms": format(baseline_median, "f"),
        "baseline_total_p95_ms": format(baseline_p95, "f"),
        "candidate_minus_baseline_median_ms": format(candidate_median - baseline_median, "f"),
        "candidate_minus_baseline_p95_ms": format(candidate_p95 - baseline_p95, "f"),
        "candidate_total_median_ms": format(candidate_median, "f"),
        "candidate_total_p95_ms": format(candidate_p95, "f"),
        "gate": "no_observed_latency_regression",
        "sample_is_diagnostic_not_sla": True,
    },
    "next_gate": "operator_freeze_decision_for_v2_retrieval_candidate",
    "post_freeze_qualification_order": [
        "record_new_frozen_decision_and_candidate_identity",
        "implement_section_page_duplicate_canonical_behavior_and_lexical_weight_2_in_application_source",
        "run_complete_native_and_web_regression",
        "repeat_60_body_and_8_header_retrieval_gate_from_implemented_source",
        "run_complete_retrieval_api_gate_with_gemma",
        "assemble_and_qualify_a_new_deployment_candidate",
    ],
    "ready_for_operator_freeze_decision": True,
    "schema_version": 1,
    "scope": {
        "black_corpus_validated": False,
        "deployment_promotion": False,
        "production_profile": False,
        "synthetic_corpus_v2_retrieval_candidate": True,
    },
    "source_sha256": {
        "baseline_receipt": baseline_sha256,
        "decisions": decisions_sha256,
        "finalist_review": finalist_review_sha256,
        "live_qualification": qualification_sha256,
        "script_177_report": script_177_report_sha256,
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
assert value["artifact_kind"] == "ishikawa_live_v2_retrieval_finalist_pre_freeze_review"
assert value["schema_version"] == 1
assert value["ready_for_operator_freeze_decision"] is True
assert value["decision"]["new_freeze_decision_required"] is True
assert value["decision"]["operator_freeze_received"] is False
assert value["candidate"]["profile"] == {
    "exact_weight": 1,
    "lexical_depth": 20,
    "lexical_weight": 2,
    "rrf_constant": 60,
    "vector_depth": 20,
    "vector_weight": 4,
}
assert value["candidate"]["behavior"] == {
    "document_local_duplicate_canonicalization": True,
    "section_page_representatives": True,
}
assert value["evidence"]["candidate_body_mrr_at_20"] == "0.915833"
assert value["evidence"]["rank_deterministic"] is True
assert value["evidence"]["regressed_body_case_ids"] == []
assert value["latency_diagnostic"]["gate"] == "no_observed_latency_regression"
assert value["latency_diagnostic"]["sample_is_diagnostic_not_sla"] is True
assert value["scope"] == {
    "black_corpus_validated": False,
    "deployment_promotion": False,
    "production_profile": False,
    "synthetic_corpus_v2_retrieval_candidate": True,
}
assert value["next_gate"] == "operator_freeze_decision_for_v2_retrieval_candidate"
assert not any(value["boundaries"].values())
PY
}

bash -n "${BASH_SOURCE[0]}"
validation_root="$(mktemp -d /tmp/ishikawa-script-178-validation.XXXXXX)"
trap 'rm -rf -- "$validation_root"' EXIT
build_review "$validation_root/review-a.json"
build_review "$validation_root/review-b.json"
cmp --silent "$validation_root/review-a.json" "$validation_root/review-b.json" || {
  printf 'reason=pre_freeze_review_not_repeatable\n\nSCRIPT RESULT\nscript_178_live_v2_retrieval_finalist_pre_freeze_review=blocked\n' >&2
  exit 2
}
validate_review "$validation_root/review-a.json"
validation_review_sha256="$(sha256sum "$validation_root/review-a.json" | awk '{print $1}')"
candidate_identity="$(PYTHONDONTWRITEBYTECODE=1 python3 -B - "$validation_root/review-a.json" <<'PY'
import json, pathlib, sys
print(json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))["candidate"]["identity"])
PY
)"
rm -rf -- "$validation_root"
trap - EXIT

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_live_v2_retrieval_finalist_pre_freeze_review' \
    "script_sha256=$script_sha256;live_qualification_sha256=$LIVE_QUALIFICATION_SHA256;decision=V13-31" \
    "candidate_identity=$candidate_identity;candidate_body_mrr_at_20=0.915833;measured_runs=5;regressed_cases=none" \
    'selected_behavior=section_page_representatives_plus_document_local_duplicate_canonicalization;selected_delta=lexical_weight_1_to_2' \
    'ready_for_operator_freeze_decision=true;candidate_frozen=false;production_profile_changed=false' \
    "validation_review_sha256=$validation_review_sha256" \
    'database_contact=false;model_contact=false;credential_read=false;corpus_changed=false;truth_changed=false;candidate_promoted=false' \
    '' \
    'SCRIPT RESULT' \
    'script_178_live_v2_retrieval_finalist_pre_freeze_review=pass'
  exit 0
fi

umask 077
mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT" || {
  printf 'reason=local_output_root_creation_failed\n\nSCRIPT RESULT\nscript_178_live_v2_retrieval_finalist_pre_freeze_review=blocked\n' >&2
  exit 2
}
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" && -w "$REPORT_ROOT" ]] || {
  printf 'reason=report_root_unsafe\n\nSCRIPT RESULT\nscript_178_live_v2_retrieval_finalist_pre_freeze_review=blocked\n' >&2
  exit 2
}
[[ -d "$ARTIFACT_ROOT" && ! -L "$ARTIFACT_ROOT" && -w "$ARTIFACT_ROOT" ]] || {
  printf 'reason=artifact_root_unsafe\n\nSCRIPT RESULT\nscript_178_live_v2_retrieval_finalist_pre_freeze_review=blocked\n' >&2
  exit 2
}

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/pre_freeze_review_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-script-178.XXXXXX)"
suffix="${report_path##*_}"; suffix="${suffix%.txt}"
artifact_path="$ARTIFACT_ROOT/pre_freeze_review_${timestamp}_${suffix}.json"
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
  [[ "$work_root" == /tmp/ishikawa-script-178.* ]] && rm -rf -- "$work_root"
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
    printf 'script_178_live_v2_retrieval_finalist_pre_freeze_review=%s\n' "$result"
  } >>"$report_path"
  printf 'local_report=%s\n' "$report_path"
  printf 'local_report_sha256=%s\n' "$(sha256sum "$report_path" | awk '{print $1}')"
  printf '\nSCRIPT RESULT\n'
  [[ "$result" == pass ]] || printf 'reason=%s\n' "$failure_reason"
  printf 'script_178_live_v2_retrieval_finalist_pre_freeze_review=%s\n' "$result"
  exit "$initial_status"
}
trap cleanup EXIT
trap 'failure_reason="interrupted_hup"; exit 129' HUP
trap 'failure_reason="interrupted_int"; exit 130' INT
trap 'failure_reason="interrupted_term"; exit 143' TERM

emit 'purpose=review_live_v2_retrieval_finalist_before_freeze'
emit "started_utc=$timestamp;script_sha256=$script_sha256;decision=V13-31"
emit 'authorized_actions=validate_checksum_bound_script_177_evidence_review_metrics_and_latency_define_candidate_identity_retain_local_pre_freeze_review'
emit 'non_actions=no_database_contact_no_model_contact_no_credential_read_no_corpus_change_no_truth_change_no_source_change_no_service_change_no_package_change_no_release_change_no_profile_freeze_no_candidate_promotion_no_org_lab_change'

build_review "$work_root/review.json" || block pre_freeze_review_build_failed
validate_review "$work_root/review.json" || block pre_freeze_review_validation_failed
review_sha256="$(sha256sum "$work_root/review.json" | awk '{print $1}')"
[[ "$review_sha256" == "$validation_review_sha256" ]] \
  || block pre_freeze_review_not_repeatable_at_retention

[[ ! -e "$artifact_path" && ! -L "$artifact_path" ]] \
  || block pre_freeze_review_destination_exists
tee -- "$artifact_path" <"$work_root/review.json" >/dev/null \
  || block pre_freeze_review_retention_failed
[[ "$(sha256sum "$artifact_path" | awk '{print $1}')" == "$review_sha256" ]] \
  || block pre_freeze_review_identity_changed_after_retention
if ! printf '%s  %s\n' "$review_sha256" "$(basename -- "$artifact_path")" \
    >"$artifact_checksum_path"; then
  block pre_freeze_review_checksum_manifest_write_failed
fi
if ! (trap - EXIT HUP INT TERM; cd -- "$ARTIFACT_ROOT" \
    && sha256sum --quiet -c "$(basename -- "$artifact_checksum_path")"); then
  block pre_freeze_review_checksum_manifest_failed
fi

emit "milestone=pre_freeze_review;state=pass;candidate_identity=$candidate_identity;ready_for_operator_freeze_decision=true"
emit 'candidate_behavior=section_page_representatives_plus_document_local_duplicate_canonicalization;candidate_profile=exact_1_lexical_2_vector_4_depths_20_rrf_60'
emit 'baseline_body_mrr_at_20=0.903333;candidate_body_mrr_at_20=0.915833;body_top5=60/60;body_top20=60/60;regressed_body_cases=none'
emit 'latency_gate=no_observed_regression;latency_sample=diagnostic_not_sla;candidate_frozen=false;production_profile_changed=false'
emit "pre_freeze_review=$artifact_path;pre_freeze_review_sha256=$review_sha256"
emit 'database_contact=false;model_contact=false;credential_read=false;corpus_changed=false;truth_changed=false;source_profile_changed=false;candidate_promoted=false;org_lab_changed=false'
emit 'next_gate=operator_freeze_decision_for_v2_retrieval_candidate'
