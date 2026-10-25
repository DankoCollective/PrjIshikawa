#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Search a bounded set of retrieval parameters from the accepted Script 118
#   lane rankings without contacting PostgreSQL or a model.
#
# Mental model:
#   Verify the accepted baseline, replay its top-20 exact, lexical, and vector
#   rankings under temporary depth, weight, and RRF settings, retain candidates
#   that meet the frozen ranking gate, and recommend the smallest clear change.
#   The script does not modify or freeze the tracked method profile.
#
# Inputs or prerequisites:
#   The checksum-valid Script 118 pass receipt and its accepted ranking artifact.
#
# Outputs or artifact lane:
#   One content-free report and one checksum-bound parameter-search artifact.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/119_search_local_retrieval_parameters.sh --run

usage() {
  sed -n '3,24p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run            Execute the bounded offline parameter search.' \
    '  --validate-only  Validate bound inputs and helper self-tests only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly SEARCH_HELPER="$SCRIPT_DIR/search_local_retrieval_parameters.py"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_1_TUNING_DECISIONS.md"
readonly BASELINE_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.1-local-ranking-baseline/local_ranking_baseline_20261021T171008Z_K0UNmH.txt"
readonly BASELINE_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/v1.1-local-ranking-baseline/accepted_profile_ranking_7ee0a825a4ae6754434d4438df57a42be2d17731976f120183df91b558894472.json"
readonly BASELINE_CHECKSUM="$BASELINE_ARTIFACT.sha256"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.1-parameter-search"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v1.1-parameter-search"
readonly BASELINE_REPORT_SHA256='0a4f9680d31425f3e51abe3a8b449a3490c1a319c7100c83198c6b0d2f4123b4'
readonly BASELINE_ARTIFACT_SHA256='7150de1d07850c2d6f7376e0120845ee811609b44401b5049ae9fe776c968290'
readonly BASELINE_CHECKSUM_SHA256='d38580c1e7987eead4b592f93221d4620a28c9dd448e19b6ecc610a4d16bb311'
readonly SEARCH_HELPER_SHA256='edafc4ccec5150ce427d2d97d4939e03699a6ac9ab2894f5e9bf1cae20406a95'
readonly DECISIONS_SHA256='e8089e746d94c1149121aa4ba1631065d165b8ab2b45f35a12deab6e8d0f9fa5'

run_mode=false
validate_mode=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_mode=true; shift ;;
    --validate-only) validate_mode=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_119_parameter_search=blocked;reason=argument_invalid\n' >&2; exit 2 ;;
  esac
done
[[ "$run_mode" != "$validate_mode" ]] || {
  printf 'script_119_parameter_search=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in awk bash basename date grep mkdir mktemp mv python3 rm sed sha256sum stat tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_119_parameter_search=blocked;reason=local_command_missing;command=%s\n' "$required" >&2
    exit 2
  }
done

check_file() {
  [[ -f "$1" && ! -L "$1" && -r "$1" ]] || {
    printf 'script_119_parameter_search=blocked;reason=%s_unsafe\n' "$3" >&2
    exit 2
  }
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_119_parameter_search=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}

check_file "$SEARCH_HELPER" "$SEARCH_HELPER_SHA256" search_helper
check_file "$DECISIONS" "$DECISIONS_SHA256" tuning_decisions
check_file "$BASELINE_REPORT" "$BASELINE_REPORT_SHA256" baseline_report
check_file "$BASELINE_ARTIFACT" "$BASELINE_ARTIFACT_SHA256" baseline_artifact
check_file "$BASELINE_CHECKSUM" "$BASELINE_CHECKSUM_SHA256" baseline_checksum
(
  cd -- "$(dirname -- "$BASELINE_CHECKSUM")"
  sha256sum --check --strict "$(basename -- "$BASELINE_CHECKSUM")" >/dev/null
) || {
  printf 'script_119_parameter_search=blocked;reason=baseline_checksum_failed\n' >&2
  exit 2
}
for fact in \
  'mrr_at_20=0.690476;responsive_top_five=5/6;required_evidence_at_20=13/13' \
  'ranking_gate=not_met;nonresponsive_acceptance_measured=false;broad_navigation=clarification-required' \
  'script_118_local_ranking_baseline=pass;ranking_gate=not_met;next_gate=run_bounded_retrieval_parameter_search;'; do
  grep -Fq "$fact" "$BASELINE_REPORT" || {
    printf 'script_119_parameter_search=blocked;reason=baseline_report_contract_invalid\n' >&2
    exit 2
  }
done
grep -Eq '^\| `T06` \|.*\| FROZEN \|$' "$DECISIONS" || {
  printf 'script_119_parameter_search=blocked;reason=tuning_decision_contract_invalid\n' >&2
  exit 2
}

bash -n "${BASH_SOURCE[0]}"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
  "$SEARCH_HELPER"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$SEARCH_HELPER" --self-test \
  | grep -Fxq 'local_retrieval_parameter_search_self_test=pass' || {
    printf 'script_119_parameter_search=blocked;reason=search_helper_self_test_failed\n' >&2
    exit 2
  }

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_mode" == true ]]; then
  printf '%s\n' \
    'purpose=validate_bounded_local_retrieval_parameter_search' \
    "script_sha256=$script_sha256;search_helper_sha256=$SEARCH_HELPER_SHA256;decision_list_sha256=$DECISIONS_SHA256" \
    "baseline_report_sha256=$BASELINE_REPORT_SHA256;baseline_artifact_sha256=$BASELINE_ARTIFACT_SHA256;baseline_checksum_sha256=$BASELINE_CHECKSUM_SHA256" \
    'candidate_count=43120;search_dimensions=exact_depth_lexical_depth_vector_depth_rrf_constant_lane_weights;fused_depth=20' \
    'database_contact=false;model_contact=false;credential_read=false;method_profile_changed=false' \
    'script_119_parameter_search_source=pass'
  exit 0
fi

umask 077
work_root="$(mktemp -d /tmp/ishikawa-script-119.XXXXXX)"
report_path=''
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  [[ "$work_root" == /tmp/ishikawa-script-119.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  exit "$status"
}
trap cleanup EXIT

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" && -d "$ARTIFACT_ROOT" && ! -L "$ARTIFACT_ROOT" ]] || {
  printf 'script_119_parameter_search=blocked;reason=output_directory_unsafe\n' >&2
  exit 1
}
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/parameter_search_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
block() { emit "script_119_parameter_search=blocked;reason=$1"; exit 1; }
current_stage='initialization'
unexpected_failure() {
  local status="$?"
  trap - ERR
  emit "script_119_parameter_search=blocked;reason=unexpected_shell_failure;stage=$current_stage;exit_code=$status"
  exit "$status"
}
trap unexpected_failure ERR
trap 'block interrupted_by_operator' INT
trap 'block terminated_by_signal' TERM

emit 'purpose=search_bounded_local_retrieval_parameters'
emit "started_utc=$timestamp;local_report=$report_path"
emit "script_sha256=$script_sha256;search_helper_sha256=$SEARCH_HELPER_SHA256;decision_list_sha256=$DECISIONS_SHA256"
emit "baseline_report_sha256=$BASELINE_REPORT_SHA256;baseline_artifact_sha256=$BASELINE_ARTIFACT_SHA256;baseline_checksum_sha256=$BASELINE_CHECKSUM_SHA256"
emit 'authorized_actions=read_checksum_bound_content_free_ranking_artifact_replay_finite_parameter_grid_retain_content_free_candidates'
emit 'non_actions=no_database_or_model_contact_no_credential_read_no_question_vector_or_source_text_read_no_method_profile_change_no_package_build'

candidate_artifact="$work_root/parameter-search.json"
search_output="$work_root/search.stdout"
search_error="$work_root/search.stderr"
current_stage='bounded_parameter_search'
emit 'milestone=bounded_parameter_search;state=start;candidate_count=43120'
if PYTHONDONTWRITEBYTECODE=1 python3 -B "$SEARCH_HELPER" \
    --run \
    --baseline "$BASELINE_ARTIFACT" \
    --output "$candidate_artifact" \
    >"$search_output" 2>"$search_error"; then
  search_status=0
else
  search_status=$?
fi
if (( search_status != 0 )); then
  reason="$(sed -nE 's/^local_retrieval_parameter_search=blocked;reason=([A-Za-z0-9_]+)$/\1/p' "$search_error" | tail -n 1)"
  [[ -n "$reason" ]] || reason=unclassified_search_failure
  emit "script_119_parameter_search=blocked;reason=$reason;stdout_sha256=$(sha256sum "$search_output" | awk '{print $1}');stderr_sha256=$(sha256sum "$search_error" | awk '{print $1}');raw_output_retained=false"
  exit 1
fi
for marker in \
  'candidate_count=43120;qualifying_candidate_count=' \
  'local_retrieval_parameter_search=pass;selection_status=review_required'; do
  grep -Fq "$marker" "$search_output" || block search_output_contract_invalid
done
emit 'milestone=bounded_parameter_search;state=pass'

current_stage='artifact_validation'
PYTHONDONTWRITEBYTECODE=1 python3 -B - "$candidate_artifact" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
value = json.loads(path.read_text(encoding="utf-8"))
if (
    not isinstance(value, dict)
    or value.get("artifact_kind") != "ishikawa_local_retrieval_parameter_search"
    or value.get("schema_version") != 1
    or value.get("candidate_count") != 43120
    or not isinstance(value.get("qualifying_candidate_count"), int)
    or value.get("qualifying_candidate_count", 0) < 1
    or value.get("method_profile_changed") is not False
    or value.get("database_contact") is not False
    or value.get("model_contact") is not False
    or value.get("operator_freeze_required") is not True
    or value.get("question_text_retained") is not False
    or value.get("query_vectors_retained") is not False
    or value.get("source_text_retained") is not False
):
    raise SystemExit("parameter-search artifact contract invalid")
recommended = value.get("recommended_candidate")
if not isinstance(recommended, dict) or recommended.get("ranking_gate") != "pass":
    raise SystemExit("recommended candidate is invalid")
for forbidden in (
    "question", "query_vector", "embedding_vector", "vector_values",
    "retrieval_text", "source_text", "credential",
):
    stack = [value]
    while stack:
        current = stack.pop()
        if isinstance(current, dict):
            if forbidden in current:
                raise SystemExit("parameter-search artifact contains a forbidden field")
            stack.extend(current.values())
        elif isinstance(current, list):
            stack.extend(current)
PY

artifact_sha256="$(sha256sum "$candidate_artifact" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$candidate_artifact")"
search_id="$(sed -nE 's/^search_id=([0-9a-f]{64});artifact_sha256=.*/\1/p' "$search_output")"
[[ "$search_id" =~ ^[0-9a-f]{64}$ ]] || block search_identity_invalid
artifact_path="$ARTIFACT_ROOT/parameter_search_${search_id}.json"
checksum_path="$artifact_path.sha256"
current_stage='artifact_publication'
if [[ -f "$artifact_path" && ! -L "$artifact_path" && -f "$checksum_path" && ! -L "$checksum_path" ]]; then
  (cd -- "$ARTIFACT_ROOT" && sha256sum --check --strict "$(basename -- "$checksum_path")" >/dev/null) \
    || block accepted_artifact_checksum_failed
  [[ "$(sha256sum "$artifact_path" | awk '{print $1}')" == "$artifact_sha256" ]] \
    || block accepted_artifact_identity_conflict
  rm -f -- "$candidate_artifact"
else
  [[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] \
    || block accepted_artifact_path_unsafe
  mv -- "$candidate_artifact" "$artifact_path"
  printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
fi

current_stage='result_projection'
candidate_line="$(grep -E '^candidate_count=43120;qualifying_candidate_count=[0-9]+;database_contact=false;model_contact=false;method_profile_changed=false$' "$search_output")" \
  || block search_metric_contract_invalid
recommendation_line="$(grep -E '^recommended_candidate_id=[0-9a-f]{64};mrr_at_20=[0-9]+\.[0-9]{6};responsive_top_five=[0-9]+/6;required_evidence_at_20=[0-9]+/13$' "$search_output")" \
  || block search_metric_contract_invalid
parameter_line="$(grep -E '^recommended_depths=[0-9]+,[0-9]+,[0-9]+,20;rrf_constant=[0-9]+;lane_weights=[0-9]+,[0-9]+,[0-9]+$' "$search_output")" \
  || block search_metric_contract_invalid
emit "$candidate_line"
emit "$recommendation_line"
emit "$parameter_line"
emit "accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$artifact_bytes;checksum=$checksum_path"
emit "script_119_parameter_search=pass;selection_status=review_required;next_gate=review_and_freeze_winning_profile;local_report=$report_path"
