#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Replay the bounded optimization matrix over Script 169's accepted live
#   PostgreSQL lane capture without changing the published corpus or profile.
#
# Boundaries:
#   Local checksum-bound synthetic artifacts only. No database, model,
#   credential, service, package, corpus, truth, or production-profile change.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/170_search_published_v2_live_lane_optimizations.sh --run

usage() {
  sed -n '3,16p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Run and retain the bounded live-lane replay.' \
    '  --validate-only Validate inputs and reproduce the expected search result.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PYTHON_ROOT="$PHASE_ROOT/Ishikawa/application/python"
readonly APPLICATION_ROOT="$PYTHON_ROOT/ishikawa"
readonly OPTIMIZER="$SCRIPT_DIR/search_live_synthetic_corpus_v2_optimizations.py"
readonly CACHED_OPTIMIZER="$SCRIPT_DIR/search_synthetic_corpus_v2_optimizations.py"
readonly PLAN="$PHASE_ROOT/docs/ISHIKAWA_V1_3_RETRIEVAL_OPTIMIZATION_PLAN.md"
readonly SCRIPT_169_REPORT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-live-retrieval/isolated_v2_live_retrieval_20261022T211121Z_Gvmvg2.txt"
readonly OBSERVATION="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-live-retrieval/isolated_v2_live_retrieval_20261022T211121Z.json"
readonly OBSERVATION_SUMS="$OBSERVATION.sha256"
readonly PROMOTION_BUNDLE="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-promotion/synthetic_corpus_v2_promotion_candidate_20261022T201026Z"
readonly RETAINED_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-isolated-publication/retained-derived-artifacts-20261022T204745Z"
readonly NORMALIZED="$RETAINED_ROOT/71/711997caa99c2b92ee555f7ea29e012e2fbb86e39fd65f662cd52e174ec07ead"
readonly CHUNKS="$RETAINED_ROOT/22/22a4d2694938268462f0c78a79b51771abb48a8e1a23420ec0f443e1e7d8c5fd"
readonly EMBEDDINGS="$RETAINED_ROOT/ff/ff040e9244a0a9213aec028715d3e52ba5ab7855c324b24c5a4abf8fcc83865f"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-live-optimization-search"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-live-optimization-search"

readonly OPTIMIZER_SHA256='49e9f60329e7682a01c8964781e692e9e2a93d3e11f16537ebebf12bad67a1a7'
readonly CACHED_OPTIMIZER_SHA256='8a8417ffa4c792a221b85f806f88e1ee8221b8f841bf016c520e69df03968720'
readonly PLAN_SHA256='5a84d24dd2110bfc37dcea358a8967e5bebc279abfc8737b21762f605b06a08f'
readonly SCRIPT_169_REPORT_SHA256='28544cb55d54cf3b5ac1ba3903aa0289cd4c4f26e9c5d4173a2f9b86c6876c24'
readonly OBSERVATION_SHA256='baab346b25374c44237e37787bd0ef64a1f3f447551212965777358d8c385718'
readonly OBSERVATION_SUMS_SHA256='7583e679e01899ba398047b8709a003570439a09ccf242bcd97838b5713e0a67'
readonly PROMOTION_SUMS_SHA256='614c4ce64597aeed7d0d03da8dcbef0d59db052dbd3c56092a33e86fd40d42f5'
readonly NORMALIZED_SHA256='711997caa99c2b92ee555f7ea29e012e2fbb86e39fd65f662cd52e174ec07ead'
readonly CHUNKS_SHA256='22a4d2694938268462f0c78a79b51771abb48a8e1a23420ec0f443e1e7d8c5fd'
readonly EMBEDDINGS_SHA256='ff040e9244a0a9213aec028715d3e52ba5ab7855c324b24c5a4abf8fcc83865f'
readonly APPLICATION_SOURCE_TREE_SHA256='e90c4edb9b704fce0eb4d894728275e84d0f7208a9ea55e8331bf104194ce0cb'
readonly EXPECTED_APPLICATION_SOURCE_FILES='51'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      printf 'reason=argument_invalid\n\nSCRIPT RESULT\nscript_170_published_v2_live_optimization_search=blocked\n' >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'reason=mode_invalid\n\nSCRIPT RESULT\nscript_170_published_v2_live_optimization_search=blocked\n' >&2
  exit 2
}

for required_command in basename bash date dirname find grep hostname mkdir mktemp mv \
  python3 rm sed sha256sum sort tail tee wc; do
  command -v "$required_command" >/dev/null 2>&1 || {
    printf 'reason=local_command_missing;command=%s\n\nSCRIPT RESULT\nscript_170_published_v2_live_optimization_search=blocked\n' \
      "$required_command" >&2
    exit 2
  }
done

check_file() {
  local path="$1" expected_sha256="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] || {
    printf 'reason=%s_unsafe\n\nSCRIPT RESULT\nscript_170_published_v2_live_optimization_search=blocked\n' \
      "$label" >&2
    exit 2
  }
  [[ "$(sha256sum "$path" | sed 's/[[:space:]].*$//')" == "$expected_sha256" ]] || {
    printf 'reason=%s_identity_changed\n\nSCRIPT RESULT\nscript_170_published_v2_live_optimization_search=blocked\n' \
      "$label" >&2
    exit 2
  }
}

application_source_tree_sha256() {
  (
    cd -- "$APPLICATION_ROOT" || exit 1
    find . -type f -name '*.py' -printf '%P\n' | sort \
      | while IFS= read -r relative_path; do
          printf '%s:' "$relative_path"
          sha256sum "$relative_path" | sed 's/[[:space:]].*$//'
        done
  ) | sha256sum | sed 's/[[:space:]].*$//'
}

check_file "$OPTIMIZER" "$OPTIMIZER_SHA256" optimizer
check_file "$CACHED_OPTIMIZER" "$CACHED_OPTIMIZER_SHA256" cached_optimizer
check_file "$PLAN" "$PLAN_SHA256" optimization_plan
check_file "$SCRIPT_169_REPORT" "$SCRIPT_169_REPORT_SHA256" script_169_report
check_file "$OBSERVATION" "$OBSERVATION_SHA256" script_169_observation
check_file "$OBSERVATION_SUMS" "$OBSERVATION_SUMS_SHA256" observation_checksum
check_file "$PROMOTION_BUNDLE/SHA256SUMS" "$PROMOTION_SUMS_SHA256" promotion_manifest
check_file "$NORMALIZED" "$NORMALIZED_SHA256" normalized_artifact
check_file "$CHUNKS" "$CHUNKS_SHA256" chunk_artifact
check_file "$EMBEDDINGS" "$EMBEDDINGS_SHA256" embedding_artifact
[[ -d "$PROMOTION_BUNDLE" && ! -L "$PROMOTION_BUNDLE" \
  && -d "$RETAINED_ROOT" && ! -L "$RETAINED_ROOT" ]] || {
  printf 'reason=bound_artifact_directory_unsafe\n\nSCRIPT RESULT\nscript_170_published_v2_live_optimization_search=blocked\n' >&2
  exit 2
}
(cd -- "$(dirname -- "$OBSERVATION")" \
  && sha256sum --quiet -c "$(basename -- "$OBSERVATION_SUMS")") || {
  printf 'reason=observation_checksum_failed\n\nSCRIPT RESULT\nscript_170_published_v2_live_optimization_search=blocked\n' >&2
  exit 2
}
(cd -- "$PROMOTION_BUNDLE" && sha256sum --quiet -c SHA256SUMS) || {
  printf 'reason=promotion_bundle_checksum_failed\n\nSCRIPT RESULT\nscript_170_published_v2_live_optimization_search=blocked\n' >&2
  exit 2
}
(cd -- "$RETAINED_ROOT" && sha256sum --quiet -c SHA256SUMS) || {
  printf 'reason=retained_artifact_checksum_failed\n\nSCRIPT RESULT\nscript_170_published_v2_live_optimization_search=blocked\n' >&2
  exit 2
}
[[ "$(find "$APPLICATION_ROOT" -type f -name '*.py' | wc -l | sed 's/[[:space:]]//g')" \
    == "$EXPECTED_APPLICATION_SOURCE_FILES" \
  && "$(application_source_tree_sha256)" == "$APPLICATION_SOURCE_TREE_SHA256" ]] || {
  printf 'reason=application_source_tree_identity_changed\n\nSCRIPT RESULT\nscript_170_published_v2_live_optimization_search=blocked\n' >&2
  exit 2
}
grep -Fxq 'script_169_isolated_v2_retrieval_qualification=pass' \
  "$SCRIPT_169_REPORT" || {
  printf 'reason=script_169_not_clean\n\nSCRIPT RESULT\nscript_170_published_v2_live_optimization_search=blocked\n' >&2
  exit 1
}
grep -Fxq \
  'optimization_status=observational_baseline_not_promoted;next_gate=return_to_bounded_retrieval_optimization_review' \
  "$SCRIPT_169_REPORT" || {
  printf 'reason=script_169_next_gate_invalid\n\nSCRIPT RESULT\nscript_170_published_v2_live_optimization_search=blocked\n' >&2
  exit 1
}

bash -n "${BASH_SOURCE[0]}"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
  "$OPTIMIZER"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$OPTIMIZER" --self-test \
  | grep -Fxq 'live_synthetic_corpus_v2_optimization_search_self_test=pass' || {
  printf 'reason=optimizer_self_test_failed\n\nSCRIPT RESULT\nscript_170_published_v2_live_optimization_search=blocked\n' >&2
  exit 2
}

run_optimizer() {
  local output_path="$1" stdout_path="$2" stderr_path="$3"
  PYTHONDONTWRITEBYTECODE=1 python3 -B "$OPTIMIZER" --run \
    --scripts-root "$SCRIPT_DIR" \
    --python-root "$PYTHON_ROOT" \
    --promotion-bundle "$PROMOTION_BUNDLE" \
    --observation "$OBSERVATION" \
    --normalized "$NORMALIZED" \
    --chunks "$CHUNKS" \
    --embeddings "$EMBEDDINGS" \
    --output "$output_path" >"$stdout_path" 2>"$stderr_path"
}

validate_result() {
  local path="$1"
  PYTHONDONTWRITEBYTECODE=1 python3 -B - "$path" "$OBSERVATION_SHA256" \
    "$NORMALIZED_SHA256" "$CHUNKS_SHA256" "$EMBEDDINGS_SHA256" <<'PY'
import json
import pathlib
import sys

value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert value["artifact_kind"] == "ishikawa_live_synthetic_corpus_v2_optimization_search"
assert value["source_sha256"] == {
    "live_observation": sys.argv[2],
    "normalized_artifact": sys.argv[3],
    "chunk_artifact": sys.argv[4],
    "embedding_artifact": sys.argv[5],
}
assert value["published_inventory"] == {
    "chunks": 139,
    "chunks_observed_in_lanes": 135,
    "producer_to_published_identity_verified": True,
}
assert value["search_space"]["profile_count"] == 10584
assert value["current_profile_replay"]["body_metrics"]["mrr_at_20"] == "0.873056"
assert value["current_profile_replay"]["header_metrics"]["mrr_at_20"] == "1.000000"
assert value["strict_gate_profile_count"] == 0
best = value["best_profile"]
assert best["profile"] == {
    "rrf_constant": 60,
    "exact_weight": 1,
    "lexical_weight": 1,
    "vector_weight": 5,
    "lexical_depth": 20,
    "vector_depth": 10,
    "diversification": "source_unit_overlap_first",
}
assert best["body_metrics"]["mrr_at_20"] == "0.882103"
assert best["body_metrics"]["relevant_at_5"] == 59
assert best["body_metrics"]["relevant_at_20"] == 60
assert best["header_metrics"]["mrr_at_20"] == "1.000000"
assert best["header_metrics"]["relevant_at_5"] == 8
assert best["header_metrics"]["required_evidence_matched_at_20"] == 11
assert best["regressed_body_case_ids"] == ["E-024", "E-032"]
assert best["improved_body_case_ids"] == ["E-015", "E-026", "E-033"]
assert best["strict_gate_met"] is False
assert value["boundaries"]["database_contact"] is False
assert value["boundaries"]["model_contact"] is False
assert value["boundaries"]["production_profile_changed"] is False
assert value["boundaries"]["retrieval_profile_promotion_authorized"] is False
assert value["next_gate"] == (
    "review_published_atomic_rank_failures_before_new_retrieval_candidate_design"
)
PY
}

if [[ "$validate_only" == true ]]; then
  validation_root="$(mktemp -d /tmp/ishikawa-script-170-validation.XXXXXX)"
  trap 'rm -rf -- "$validation_root"' EXIT
  run_optimizer "$validation_root/result.json" \
    "$validation_root/optimizer.stdout" "$validation_root/optimizer.stderr"
  validate_result "$validation_root/result.json"
  printf '%s\n' \
    'purpose=validate_published_v2_live_lane_optimization_search' \
    "optimizer_sha256=$OPTIMIZER_SHA256;script_169_observation_sha256=$OBSERVATION_SHA256" \
    'profiles=10584;strict_gate_profiles=0;best_body_mrr_at_20=0.882103' \
    'database_contact=false;model_contact=false;credential_read=false;production_profile_changed=false' \
    '' \
    'SCRIPT RESULT' \
    'script_170_published_v2_live_optimization_search=pass'
  exit 0
fi

umask 077
mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/published_v2_live_optimization_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-script-170.XXXXXX)"
suffix="${report_path##*_}"
suffix="${suffix%.txt}"
artifact_path="$ARTIFACT_ROOT/published_v2_live_optimization_${timestamp}_${suffix}.json"
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
  [[ -n "$work_root" && "$work_root" == /tmp/ishikawa-script-170.* ]] \
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
    printf 'script_170_published_v2_live_optimization_search=%s\n' "$script_result"
  } >>"$report_path"
  printf 'local_report=%s\n' "$report_path"
  printf 'local_report_sha256=%s\n' \
    "$(sha256sum "$report_path" | sed 's/[[:space:]].*$//')"
  printf '\nSCRIPT RESULT\n'
  [[ "$script_result" == pass ]] || printf 'reason=%s\n' "$failure_reason"
  printf 'script_170_published_v2_live_optimization_search=%s\n' "$script_result"
  exit "$initial_status"
}
trap cleanup EXIT HUP INT TERM

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | sed 's/[[:space:]].*$//')"
emit 'purpose=search_published_v2_live_lane_retrieval_optimizations'
emit "started_utc=$timestamp;hostname=$(hostname);script_sha256=$script_sha256;optimizer_sha256=$OPTIMIZER_SHA256"
emit "script_169_report_sha256=$SCRIPT_169_REPORT_SHA256;script_169_observation_sha256=$OBSERVATION_SHA256"
emit 'authorized_actions=replay_checksum_bound_synthetic_live_lane_ranks_search_bounded_profiles_retain_content_free_local_result'
emit 'non_actions=no_database_contact_no_model_contact_no_credential_read_no_black_corpus_access_no_corpus_change_no_truth_change_no_service_change_no_package_change_no_production_profile_change'
emit 'milestone=bounded_live_lane_search;state=start;profiles=10584'
started_epoch="$(date +%s)"
if ! run_optimizer "$work_root/result.json" \
    "$work_root/optimizer.stdout" "$work_root/optimizer.stderr"; then
  optimizer_reason="$(sed -nE 's/^live_synthetic_corpus_v2_optimization_search=blocked;reason=([A-Za-z0-9_]+)$/\1/p' "$work_root/optimizer.stderr" | tail -n 1)"
  [[ -n "$optimizer_reason" ]] || optimizer_reason='unclassified_optimizer_failure'
  block "optimizer_$optimizer_reason"
fi
validate_result "$work_root/result.json" || block optimizer_result_invalid
grep -Fxq 'live_synthetic_corpus_v2_optimization_search=pass' \
  "$work_root/optimizer.stdout" || block optimizer_pass_marker_absent
mv -- "$work_root/result.json" "$artifact_path"
(cd -- "$ARTIFACT_ROOT" && sha256sum "$(basename -- "$artifact_path")" \
  >"$(basename -- "$artifact_checksum_path")")
(cd -- "$ARTIFACT_ROOT" \
  && sha256sum --quiet -c "$(basename -- "$artifact_checksum_path")") \
  || block retained_artifact_checksum_failed
emit "milestone=bounded_live_lane_search;state=pass;elapsed_seconds=$(( $(date +%s) - started_epoch ));profiles=10584;strict_gate_profiles=0"
emit 'current_profile=body_mrr_at_20:0.873056,body_relevant_at_5:58/60,body_relevant_at_20:60/60,header_mrr_at_20:1.000000'
emit 'best_observed_profile=rrf:60,exact_weight:1,lexical_weight:1,vector_weight:5,lexical_depth:20,vector_depth:10,diversification:source_unit_overlap_first'
emit 'best_observed_metrics=body_mrr_at_20:0.882103,body_relevant_at_5:59/60,body_relevant_at_20:60/60,header_mrr_at_20:1.000000,header_relevant_at_5:8/8,header_required_evidence_at_20:11/11,regressed_body_cases:2'
emit "optimization_artifact=$artifact_path;optimization_artifact_sha256=$(sha256sum "$artifact_path" | sed 's/[[:space:]].*$//')"
emit 'retrieval_profile_promotion_authorized=false;production_profile_changed=false;next_gate=review_published_atomic_rank_failures_before_new_retrieval_candidate_design'
