#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Search a bounded offline matrix of corpus-v2 RRF, lane-depth, lane-weight,
#   and post-fusion diversification candidates from the retained Script 164
#   lane ranks. Retain finalists without changing production retrieval.
#
# Boundaries:
#   Cached synthetic lane ranks only. No database, model, credential,
#   black-corpus, ingestion, service, package, truth, or production change.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/166_search_v2_retrieval_optimizations.sh --run

usage() {
  sed -n '3,17p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Execute and retain the bounded optimization search.' \
    '  --validate-only Validate inputs and reproduce the expected search result.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly OPTIMIZER="$SCRIPT_DIR/search_synthetic_corpus_v2_optimizations.py"
readonly PLAN="$PHASE_ROOT/docs/ISHIKAWA_V1_3_RETRIEVAL_OPTIMIZATION_PLAN.md"
readonly SCRIPT_165_REPORT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-rank-review/v2_rank_failure_review_20261022T185957Z_749547.txt"
readonly RANK_REVIEW="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-rank-review/v2_rank_failure_review_20261022T185957Z_749547.json"
readonly OBSERVATION="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-routing-assembly/v2_routing_assembly_observation_20261022T185141Z.json"
readonly CANDIDATE="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-routing-assembly/v2_routing_assembly_candidate_20261022T185141Z/qualification/retrieval-candidate.json"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-optimization-search"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-optimization-search"

readonly OPTIMIZER_SHA256='8a8417ffa4c792a221b85f806f88e1ee8221b8f841bf016c520e69df03968720'
readonly PLAN_SHA256='5a84d24dd2110bfc37dcea358a8967e5bebc279abfc8737b21762f605b06a08f'
readonly SCRIPT_165_REPORT_SHA256='f42887f153fa26ab8557dd010590c0e295a0c989ad65ad28eebe3db59163eff4'
readonly RANK_REVIEW_SHA256='cd87a4037b8c40e1ffaed59d698118df9f3c9129337082a2d91e5d496175dd93'
readonly OBSERVATION_SHA256='c3705a323f9c23d1a472cd67cbcd890926f406c5db61fcbccdc41d8cda502073'
readonly CANDIDATE_SHA256='f8ef761a2835192f690c21ba39a535ee0f76f062a7750fc9873f44bc46d4dfd6'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      printf 'reason=argument_invalid\n' >&2
      printf '\nSCRIPT RESULT\nscript_166_v2_retrieval_optimization_search=blocked\n' >&2
      usage >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'reason=mode_invalid\n' >&2
  printf '\nSCRIPT RESULT\nscript_166_v2_retrieval_optimization_search=blocked\n' >&2
  exit 2
}

for command_name in awk date dirname grep hostname jq mkdir mktemp python3 rm sed sha256sum tee; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'reason=local_command_missing;command=%s\n' "$command_name" >&2
    printf '\nSCRIPT RESULT\nscript_166_v2_retrieval_optimization_search=blocked\n' >&2
    exit 2
  }
done

check_file() {
  local path="$1" expected_sha256="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] || {
    printf 'reason=%s_unsafe\n' "$label" >&2
    printf '\nSCRIPT RESULT\nscript_166_v2_retrieval_optimization_search=blocked\n' >&2
    exit 2
  }
  [[ "$(sha256sum "$path" | awk '{print $1}')" == "$expected_sha256" ]] || {
    printf 'reason=%s_identity_changed\n' "$label" >&2
    printf '\nSCRIPT RESULT\nscript_166_v2_retrieval_optimization_search=blocked\n' >&2
    exit 2
  }
}

check_file "$OPTIMIZER" "$OPTIMIZER_SHA256" optimizer
check_file "$PLAN" "$PLAN_SHA256" optimization_plan
check_file "$SCRIPT_165_REPORT" "$SCRIPT_165_REPORT_SHA256" script_165_report
check_file "$RANK_REVIEW" "$RANK_REVIEW_SHA256" script_165_rank_review
check_file "$OBSERVATION" "$OBSERVATION_SHA256" script_164_observation
check_file "$CANDIDATE" "$CANDIDATE_SHA256" script_164_candidate
grep -Fxq 'script_165_v2_rank_failure_review=pass' "$SCRIPT_165_REPORT" || {
  printf 'reason=script_165_result_not_bound\n' >&2
  printf '\nSCRIPT RESULT\nscript_166_v2_retrieval_optimization_search=blocked\n' >&2
  exit 1
}
grep -Fxq 'next_gate=design_bounded_evidence_equivalence_and_source_unit_diversification_experiment' \
  "$SCRIPT_165_REPORT" || {
  printf 'reason=script_165_next_gate_not_bound\n' >&2
  printf '\nSCRIPT RESULT\nscript_166_v2_retrieval_optimization_search=blocked\n' >&2
  exit 1
}
PYTHONDONTWRITEBYTECODE=1 python3 -B -m py_compile "$OPTIMIZER"

validate_result() {
  local path="$1"
  python3 -B - "$path" <<'PY'
import json
import pathlib
import sys

value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert value["artifact_kind"] == "ishikawa_synthetic_corpus_v2_optimization_search"
assert value["search_space"]["profile_count"] == 10584
assert value["current_profile_replay"]["body_metrics"]["mrr_at_20"] == "0.870992"
assert value["strict_gate_profile_count"] == 0
best = value["best_profile"]
assert best["body_metrics"]["mrr_at_20"] == "0.890833"
assert best["body_metrics"]["relevant_at_5"] == 60
assert best["body_metrics"]["relevant_at_20"] == 60
assert best["body_equivalence_diagnostic"]["mrr_at_20"] == "0.904167"
assert best["strict_gate_met"] is False
assert value["boundaries"]["retrieval_profile_promotion_authorized"] is False
assert value["boundaries"]["production_profile_changed"] is False
assert value["boundaries"]["corpus_v2_promotion_blocked_by_optimization"] is False
assert value["primary_next_gate"] == "continue_synthetic_corpus_v2_promotion"
assert value["optional_optimization_next_step"] == (
    "review_optimization_finalists_then_live_remeasure_selected_profiles_with_latency"
)
PY
}

if [[ "$validate_only" == true ]]; then
  validation_root="$(mktemp -d /tmp/ishikawa-script-166-validation.XXXXXX)"
  cleanup_validation() {
    case "$validation_root" in
      /tmp/ishikawa-script-166-validation.*) rm -rf -- "$validation_root" ;;
    esac
  }
  trap cleanup_validation EXIT
  validation_output="$validation_root/optimization.json"
  PYTHONDONTWRITEBYTECODE=1 python3 -B "$OPTIMIZER" \
    --observation "$OBSERVATION" \
    --candidate "$CANDIDATE" \
    --rank-review "$RANK_REVIEW" \
    --output "$validation_output" >"$validation_root/optimizer.stdout"
  validate_result "$validation_output"
  printf '%s\n' \
    'purpose=validate_v2_retrieval_optimization_search' \
    "plan_sha256=$PLAN_SHA256" \
    "script_165_rank_review_sha256=$RANK_REVIEW_SHA256" \
    'profiles=10584;strict_gate_profiles=0;best_strict_body_mrr_at_20=0.890833' \
    'corpus_v2_promotion_blocked_by_optimization=false;primary_next_gate=continue_synthetic_corpus_v2_promotion' \
    'boundaries=cached_lane_replay_only;model_contact=false;database_contact=false;production_profile_changed=false' \
    '' \
    'SCRIPT RESULT' \
    'script_166_v2_retrieval_optimization_search=pass'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
suffix="$(python3 -B -c 'import secrets; print(secrets.token_hex(3))')"
report_path="$REPORT_ROOT/v2_retrieval_optimization_search_${timestamp}_${suffix}.txt"
artifact_path="$ARTIFACT_ROOT/v2_retrieval_optimization_search_${timestamp}_${suffix}.json"
[[ ! -e "$report_path" && ! -L "$report_path" && ! -e "$artifact_path" && ! -L "$artifact_path" ]] || {
  printf 'reason=retained_output_path_exists\n' >&2
  printf '\nSCRIPT RESULT\nscript_166_v2_retrieval_optimization_search=blocked\n' >&2
  exit 1
}
exec > >(tee "$report_path") 2>&1
printf '%s\n' \
  'purpose=search_bounded_v2_retrieval_optimizations_without_promotion' \
  "started_utc=$timestamp;hostname=$(hostname)" \
  "plan_sha256=$PLAN_SHA256;script_165_rank_review_sha256=$RANK_REVIEW_SHA256" \
  "observation_sha256=$OBSERVATION_SHA256;candidate_sha256=$CANDIDATE_SHA256" \
  'authorized_actions=replay_cached_synthetic_lane_ranks_search_bounded_profiles_retain_local_finalists' \
  'non_actions=no_database_contact_no_model_contact_no_credential_read_no_black_corpus_access_no_ingestion_no_truth_change_no_retrieval_source_change_no_service_change_no_package_change_no_production_profile_change'

PYTHONDONTWRITEBYTECODE=1 python3 -B "$OPTIMIZER" \
  --observation "$OBSERVATION" \
  --candidate "$CANDIDATE" \
  --rank-review "$RANK_REVIEW" \
  --output "$artifact_path"
validate_result "$artifact_path"
artifact_sha256="$(sha256sum "$artifact_path" | awk '{print $1}')"
printf '%s\n' \
  "optimization_artifact=$artifact_path" \
  "optimization_artifact_sha256=$artifact_sha256" \
  'optimization_observation=strict_threshold_not_reached;strict_gate_profiles=0;retrieval_profile_promotion_authorized=false' \
  'corpus_v2_promotion_blocked_by_optimization=false' \
  'primary_next_gate=continue_synthetic_corpus_v2_promotion' \
  'optional_optimization_next_step=review_optimization_finalists_then_live_remeasure_selected_profiles_with_latency' \
  'database_contact=false;model_contact=false;black_corpus_access=false;corpus_ingestion=false;truth_changed=false;retrieval_source_changed=false;production_profile_changed=false' \
  '' \
  'SCRIPT RESULT' \
  'script_166_v2_retrieval_optimization_search=pass'
