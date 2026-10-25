#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Reclassify the accepted 60-case retrieval observation against the amended
#   strict MRR@20 greater-than-0.91 promotion target.
#
# Mental model:
#   The rankings already exist. Verify their immutable evidence, recompute MRR
#   exactly, record the rank distribution and target gap, and do not repeat 60
#   Nomic requests merely because the acceptance threshold changed.
#
# Inputs or prerequisites:
#   Clean Script 127 report and observation, frozen amended T11, and the exact
#   60-case identity.
#
# Outputs:
#   One content-free local reclassification receipt and report. No database,
#   target, model endpoint, service, credential, or source document is read.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/128_reclassify_extended_mrr_strict_target.sh --run

usage() {
  sed -n '3,22p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Retain the exact strict-target reclassification.' \
    '  --validate-only Validate immutable inputs without retaining output.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly SCRIPT_127_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.1-extended-mrr/extended_mrr_20261021T193408Z_Ouy4pH.txt"
readonly SCRIPT_127_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/v1.1-extended-mrr/extended_mrr_20261021T193408Z.json"
readonly SCRIPT_127_CHECKSUM="$SCRIPT_127_ARTIFACT.sha256"
readonly CASES="$PHASE_ROOT/reference/ishikawa-extended-retrieval-mrr-cases-v1.1.json"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_1_TUNING_DECISIONS.md"
readonly GATE_DEFINITION="$PHASE_ROOT/docs/ISHIKAWA_EXTENDED_EVALUATION_CANDIDATE.md"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.1-extended-mrr-strict-target"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v1.1-extended-mrr-strict-target"

readonly SCRIPT_127_REPORT_SHA256='e8b6c867cd71743c9ee7168f0bb25a5b58d9d055b1928ca657ab24a7c117cdbf'
readonly SCRIPT_127_ARTIFACT_SHA256='c79691e4deae363a87233376d18d7ce16169e434d688788a257258d503582e00'
readonly SCRIPT_127_CHECKSUM_SHA256='074d9d8f883452953480b5453f36a6c01c7079311ba8a58548dea5c5557c92c6'
readonly CASES_SHA256='14814166168c4dfd97e85668a29fd11538e2cf585a0176fdcd50f072ef5958ce'
readonly DECISIONS_SHA256='cdbc7a238bdbcc446b33dcb23fa78b751d7e73d9669d5d5eb7f6c63f14a072ca'
readonly GATE_DEFINITION_SHA256='322793215890947be1b989e5c42c2a640b1a83b67645c33d7df0517f782527aa'
readonly OBSERVATION_SET_ID='67d79abb057927886a51a2d5d1c3d34220dc5582d6695d1f764c85ffc3fcca52'
readonly RETRIEVAL_PROFILE_ID='ba4bac60b3f09f6be89db148d1df883748a2003f35a1cecfb6c74f53be74b865'

run_mode=false
validate_mode=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_mode=true; shift ;;
    --validate-only) validate_mode=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_128_strict_mrr=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_mode" != "$validate_mode" ]] || {
  printf 'script_128_strict_mrr=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in awk bash basename cat date dirname grep mkdir mktemp mv python3 rm sha256sum tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_128_strict_mrr=blocked;reason=local_command_missing;command=%s\n' "$required" >&2
    exit 2
  }
done

check_file() {
  [[ -f "$1" && ! -L "$1" && -r "$1" ]] || {
    printf 'script_128_strict_mrr=blocked;reason=%s_unsafe\n' "$3" >&2
    exit 2
  }
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_128_strict_mrr=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}

check_file "$SCRIPT_127_REPORT" "$SCRIPT_127_REPORT_SHA256" script_127_report
check_file "$SCRIPT_127_ARTIFACT" "$SCRIPT_127_ARTIFACT_SHA256" script_127_artifact
check_file "$SCRIPT_127_CHECKSUM" "$SCRIPT_127_CHECKSUM_SHA256" script_127_checksum
check_file "$CASES" "$CASES_SHA256" case_set
check_file "$DECISIONS" "$DECISIONS_SHA256" tuning_decisions
check_file "$GATE_DEFINITION" "$GATE_DEFINITION_SHA256" gate_definition
(
  cd -- "$(dirname -- "$SCRIPT_127_CHECKSUM")"
  sha256sum --check --strict "$(basename -- "$SCRIPT_127_CHECKSUM")" >/dev/null
) || {
  printf 'script_128_strict_mrr=blocked;reason=script_127_checksum_failed\n' >&2
  exit 2
}
for fact in \
  'mrr_at_20=0.852173;mrr_threshold=0.850000;relevant_at_5=56/60;relevant_at_20=60/60' \
  "observation_set_id=$OBSERVATION_SET_ID;artifact_sha256=$SCRIPT_127_ARTIFACT_SHA256;" \
  'script_127_extended_mrr=pass;promotion_gate=pass;'; do
  grep -Fq "$fact" "$SCRIPT_127_REPORT" || {
    printf 'script_128_strict_mrr=blocked;reason=script_127_contract_invalid\n' >&2
    exit 2
  }
done
grep -Eq '^\| `T11` \|.*strictly greater than `0\.91`.*\| FROZEN; STRICT TARGET AMENDED AFTER SCRIPT 127 \|$' "$DECISIONS" || {
  printf 'script_128_strict_mrr=blocked;reason=amended_t11_not_frozen\n' >&2
  exit 2
}

bash -n "${BASH_SOURCE[0]}"
work_root="$(mktemp -d /tmp/ishikawa-script-128.XXXXXX)"
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  [[ "$work_root" == /tmp/ishikawa-script-128.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

candidate="$work_root/strict-mrr-reclassification.json"
summary="$work_root/summary.txt"
PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$SCRIPT_127_ARTIFACT" "$candidate" "$summary" "$OBSERVATION_SET_ID" "$RETRIEVAL_PROFILE_ID" <<'PY'
from __future__ import annotations

import json
import os
import sys
from collections import Counter
from fractions import Fraction
from pathlib import Path

source = Path(sys.argv[1])
output = Path(sys.argv[2])
summary = Path(sys.argv[3])
expected_observation = sys.argv[4]
expected_profile = sys.argv[5]
value = json.loads(source.read_text(encoding="utf-8"))
cases = value.get("cases", [])
metrics = value.get("metrics", {})
if (
    value.get("artifact_kind") != "ishikawa_extended_retrieval_mrr_observation"
    or value.get("observation_set_id") != expected_observation
    or value.get("retrieval_profile_id") != expected_profile
    or value.get("case_count") != 60
    or len(cases) != 60
    or metrics.get("mrr_fraction_numerator") != 28633
    or metrics.get("mrr_fraction_denominator") != 33600
    or metrics.get("mrr_at_20") != "0.852173"
    or metrics.get("cases_with_relevant_at_5") != 56
    or metrics.get("cases_with_relevant_at_20") != 60
):
    raise SystemExit("script_127_artifact_contract_invalid")
ranks = [item.get("first_relevant_rank") for item in cases]
if any(type(rank) is not int or not 1 <= rank <= 20 for rank in ranks):
    raise SystemExit("rank_contract_invalid")
recomputed = sum(Fraction(1, rank) for rank in ranks) / 60
recorded = Fraction(28633, 33600)
target = Fraction(91, 100)
if recomputed != recorded:
    raise SystemExit("mrr_recomputation_mismatch")
distribution = Counter(ranks)
if distribution != Counter({1: 48, 2: 1, 3: 6, 5: 1, 7: 1, 8: 1, 10: 1, 16: 1}):
    raise SystemExit("rank_distribution_mismatch")
rank_tail = sorted(
    ({"case_id": item["case_id"], "first_relevant_rank": item["first_relevant_rank"]} for item in cases if item["first_relevant_rank"] > 1),
    key=lambda item: (-item["first_relevant_rank"], item["case_id"]),
)
receipt = {
    "artifact_kind": "ishikawa_extended_mrr_strict_target_reclassification",
    "schema_version": 1,
    "source_observation_set_id": expected_observation,
    "retrieval_profile_id": expected_profile,
    "case_count": 60,
    "mrr_at_20": "0.852173",
    "mrr_fraction_numerator": recomputed.numerator,
    "mrr_fraction_denominator": recomputed.denominator,
    "strict_target": "greater_than_0.91",
    "strict_target_met": recomputed > target,
    "mrr_gap_to_0_91": format(float(target - recomputed), ".6f"),
    "relevant_at_5": 56,
    "relevant_at_20": 60,
    "rank_distribution": {str(rank): distribution[rank] for rank in sorted(distribution)},
    "rank_tail": rank_tail,
    "model_contact": False,
    "database_contact": False,
    "manual_review_performed": False,
}
payload = json.dumps(receipt, sort_keys=True, separators=(",", ":")).encode() + b"\n"
descriptor = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(descriptor, "wb") as stream:
    stream.write(payload)
summary.write_text(
    "mrr_at_20=0.852173;strict_target=greater_than_0.91;strict_target_met=false\n"
    "relevant_at_5=56/60;relevant_at_20=60/60;rank_one=48/60\n"
    "rank_distribution=1:48,2:1,3:6,5:1,7:1,8:1,10:1,16:1\n"
    "mrr_gap_to_0_91=0.057827;model_contact=false;database_contact=false;manual_review_performed=false\n",
    encoding="utf-8",
)
PY

candidate_sha256="$(sha256sum "$candidate" | awk '{print $1}')"
script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_mode" == true ]]; then
  printf '%s\n' \
    'purpose=validate_extended_mrr_strict_target_reclassification' \
    "script_sha256=$script_sha256;script_127_report_sha256=$SCRIPT_127_REPORT_SHA256;script_127_artifact_sha256=$SCRIPT_127_ARTIFACT_SHA256" \
    "case_set_sha256=$CASES_SHA256;decision_list_sha256=$DECISIONS_SHA256;gate_definition_sha256=$GATE_DEFINITION_SHA256" \
    'mrr_at_20=0.852173;strict_target=greater_than_0.91;strict_target_met=false' \
    'model_contact=false;database_contact=false;credential_read=false;manual_review_performed=false' \
    'script_128_strict_mrr_source=pass'
  exit 0
fi

umask 077
mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
artifact_path="$ARTIFACT_ROOT/strict_mrr_reclassification_${timestamp}.json"
checksum_path="$artifact_path.sha256"
report_path="$(mktemp "$REPORT_ROOT/strict_mrr_reclassification_${timestamp}_XXXXXX.txt")"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] || {
  printf 'script_128_strict_mrr=blocked;reason=artifact_path_exists\n' >&2
  exit 1
}
mv -- "$candidate" "$artifact_path"
printf '%s  %s\n' "$candidate_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
(
  cd -- "$ARTIFACT_ROOT"
  sha256sum --check --strict "$(basename -- "$checksum_path")" >/dev/null
) || {
  printf 'script_128_strict_mrr=blocked;reason=artifact_checksum_failed\n' >&2
  exit 1
}
{
  printf 'purpose=reclassify_extended_mrr_against_strict_target\n'
  printf 'started_utc=%s;script_sha256=%s\n' "$timestamp" "$script_sha256"
  printf 'script_127_report_sha256=%s;script_127_artifact_sha256=%s;observation_set_id=%s\n' "$SCRIPT_127_REPORT_SHA256" "$SCRIPT_127_ARTIFACT_SHA256" "$OBSERVATION_SET_ID"
  cat "$summary"
  printf 'accepted_artifact=%s;accepted_artifact_sha256=%s;accepted_checksum=%s\n' "$artifact_path" "$candidate_sha256" "$checksum_path"
  printf 'script_128_strict_mrr=pass;promotion_gate=not_met;next_gate=capture_extended_lane_rankings_and_search_profile_candidates\n'
} | tee "$report_path"
