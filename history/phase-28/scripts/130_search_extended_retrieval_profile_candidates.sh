#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Search a bounded set of retrieval-profile candidates against the accepted
#   60-case lane-ranking observation.
#
# Mental model:
#   Replay the already-observed exact, lexical, and vector ranks through the
#   production RRF ordering contract. Report the smallest qualifying change
#   and the highest-MRR candidate without changing or freezing either one.
#
# Inputs or prerequisites:
#   Clean Script 129 report, artifact, and checksum plus frozen T11.
#
# Outputs:
#   One checksum-bound, content-free candidate-search artifact and report. No
#   model, database, credential, service, package, or target is contacted.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/130_search_extended_retrieval_profile_candidates.sh --run

usage() {
  sed -n '3,22p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run            Search and retain bounded candidate evidence.' \
    '  --validate-only  Validate inputs and helper self-tests only.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly HELPER="$SCRIPT_DIR/search_extended_retrieval_profile_candidates.py"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_1_TUNING_DECISIONS.md"
readonly GATE_DEFINITION="$PHASE_ROOT/docs/ISHIKAWA_EXTENDED_EVALUATION_CANDIDATE.md"
readonly SCRIPT_129_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.1-extended-lane-rankings/extended_lane_rankings_20261021T201906Z_SOlRsJ.txt"
readonly SCRIPT_129_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/v1.1-extended-lane-rankings/extended_lane_rankings_362598ff121817c718aac7449d9fe481d416394b8ecc14a5cd44b91c949f6db6.json"
readonly SCRIPT_129_CHECKSUM="$SCRIPT_129_ARTIFACT.sha256"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.1-extended-profile-search"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v1.1-extended-profile-search"

readonly HELPER_SHA256='288fcde5975d4765d40618a54ac0cc01c474d6836d7da68dd86a5905a80fc395'
readonly DECISIONS_SHA256='cdbc7a238bdbcc446b33dcb23fa78b751d7e73d9669d5d5eb7f6c63f14a072ca'
readonly GATE_DEFINITION_SHA256='322793215890947be1b989e5c42c2a640b1a83b67645c33d7df0517f782527aa'
readonly SCRIPT_129_REPORT_SHA256='5aa0fc82d576da368fdfaa5c967bd5ad4467eacc2a72d52fde5efb60caecd2ca'
readonly SCRIPT_129_ARTIFACT_SHA256='16de18c2d6b485fac6001edf44268f50cbfae23ac2fc404664ad2e29717db6a5'
readonly SCRIPT_129_CHECKSUM_SHA256='3e4e4844fd4116915e2557dbff6e2b0c8ffc1a2b706af8218189a7428fd4c783'
readonly SCRIPT_129_OBSERVATION_ID='362598ff121817c718aac7449d9fe481d416394b8ecc14a5cd44b91c949f6db6'

run_mode=false
validate_mode=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_mode=true; shift ;;
    --validate-only) validate_mode=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_130_extended_profile_search=blocked;reason=argument_invalid\n' >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$run_mode" != "$validate_mode" ]] || {
  printf 'script_130_extended_profile_search=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in awk bash basename chmod date dirname grep kill mkdir mktemp mv python3 rm sed sha256sum sleep stat tail tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_130_extended_profile_search=blocked;reason=local_command_missing;command=%s\n' "$required" >&2
    exit 2
  }
done

check_file() {
  [[ -f "$1" && ! -L "$1" && -r "$1" ]] || {
    printf 'script_130_extended_profile_search=blocked;reason=%s_unsafe\n' "$3" >&2
    exit 2
  }
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_130_extended_profile_search=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}

check_file "$HELPER" "$HELPER_SHA256" search_helper
check_file "$DECISIONS" "$DECISIONS_SHA256" tuning_decisions
check_file "$GATE_DEFINITION" "$GATE_DEFINITION_SHA256" gate_definition
check_file "$SCRIPT_129_REPORT" "$SCRIPT_129_REPORT_SHA256" script_129_report
check_file "$SCRIPT_129_ARTIFACT" "$SCRIPT_129_ARTIFACT_SHA256" script_129_artifact
check_file "$SCRIPT_129_CHECKSUM" "$SCRIPT_129_CHECKSUM_SHA256" script_129_checksum
(
  cd -- "$(dirname -- "$SCRIPT_129_CHECKSUM")"
  sha256sum --check --strict "$(basename -- "$SCRIPT_129_CHECKSUM")" >/dev/null
) || {
  printf 'script_130_extended_profile_search=blocked;reason=script_129_checksum_failed\n' >&2
  exit 2
}
for fact in \
  "observation_set_id=$SCRIPT_129_OBSERVATION_ID;accepted_artifact=$SCRIPT_129_ARTIFACT;accepted_artifact_sha256=$SCRIPT_129_ARTIFACT_SHA256" \
  'script_129_extended_lane_capture=pass;baseline_reproduced=true;next_gate=search_extended_retrieval_profile_candidates'; do
  grep -Fq "$fact" "$SCRIPT_129_REPORT" || {
    printf 'script_130_extended_profile_search=blocked;reason=script_129_contract_invalid\n' >&2
    exit 2
  }
done
grep -Eq '^\| `T11` \|.*strictly greater than `0\.91`.*\| FROZEN; STRICT TARGET AMENDED AFTER SCRIPT 127 \|$' "$DECISIONS" || {
  printf 'script_130_extended_profile_search=blocked;reason=amended_t11_not_frozen\n' >&2
  exit 2
}

bash -n "${BASH_SOURCE[0]}"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
  "$HELPER"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$HELPER" --self-test \
  | grep -Fxq 'extended_retrieval_profile_search_self_test=pass' || {
    printf 'script_130_extended_profile_search=blocked;reason=helper_self_test_failed\n' >&2
    exit 2
  }

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_mode" == true ]]; then
  printf '%s\n' \
    'purpose=validate_extended_retrieval_profile_candidate_search' \
    "script_sha256=$script_sha256;helper_sha256=$HELPER_SHA256;script_129_report_sha256=$SCRIPT_129_REPORT_SHA256" \
    "script_129_artifact_sha256=$SCRIPT_129_ARTIFACT_SHA256;script_129_observation_id=$SCRIPT_129_OBSERVATION_ID" \
    'candidate_count=43120;strict_production_target=greater_than_0.91;gate_basis=mrr_at_20_only' \
    'helper_self_tests=1;database_contact=false;model_contact=false;credential_read=false;method_profile_changed=false' \
    'script_130_extended_profile_search_source=pass'
  exit 0
fi

umask 077
work_root="$(mktemp -d /tmp/ishikawa-script-130.XXXXXX)"
report_path=''
helper_pid=''
artifact_committed=false
artifact_path=''
checksum_path=''

cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  if [[ "$helper_pid" =~ ^[0-9]+$ ]] && kill -0 "$helper_pid" 2>/dev/null; then
    kill -TERM "$helper_pid" 2>/dev/null || true
    wait "$helper_pid" 2>/dev/null || true
  fi
  if [[ "$artifact_committed" != true ]]; then
    [[ "$artifact_path" == "$ARTIFACT_ROOT"/extended_profile_search_*.json ]] && rm -f -- "$artifact_path"
    [[ "$checksum_path" == "$ARTIFACT_ROOT"/extended_profile_search_*.json.sha256 ]] && rm -f -- "$checksum_path"
  fi
  [[ "$work_root" == /tmp/ishikawa-script-130.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  [[ -z "$report_path" ]] || chmod 0600 "$report_path" 2>/dev/null || true
  exit "$status"
}
trap cleanup EXIT

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" && -d "$ARTIFACT_ROOT" && ! -L "$ARTIFACT_ROOT" ]] || {
  printf 'script_130_extended_profile_search=blocked;reason=artifact_directory_unsafe\n' >&2
  exit 1
}
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/extended_profile_search_${timestamp}_XXXXXX.txt")"
emit() { printf '%s\n' "$1" | tee -a "$report_path"; }
block() { emit "script_130_extended_profile_search=blocked;reason=$1"; exit 1; }
trap 'block interrupted_by_operator' INT
trap 'block terminated_by_signal' TERM

emit 'purpose=search_extended_ishikawa_retrieval_profile_candidates'
emit "started_utc=$timestamp;script_sha256=$script_sha256;helper_sha256=$HELPER_SHA256"
emit "script_129_artifact_sha256=$SCRIPT_129_ARTIFACT_SHA256;script_129_observation_id=$SCRIPT_129_OBSERVATION_ID"
emit 'authorized_actions=read_checksum_bound_content_free_lane_rankings_replay_finite_parameter_grid_retain_content_free_candidate_evidence'
emit 'non_actions=no_database_or_model_contact_no_credential_read_no_question_vector_or_source_text_read_no_profile_change_no_package_change'

helper_output="$work_root/helper.stdout"
helper_error="$work_root/helper.stderr"
artifact_candidate="$work_root/extended-profile-search.json"
emit 'milestone=bounded_profile_search;state=start;candidate_count=43120;cases=60'
started_epoch="$(date +%s)"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$HELPER" \
    --run \
    --observation "$SCRIPT_129_ARTIFACT" \
    --output "$artifact_candidate" \
    >"$helper_output" 2>"$helper_error" &
helper_pid="$!"
next_heartbeat_epoch=$(( started_epoch + 30 ))
while kill -0 "$helper_pid" 2>/dev/null; do
  sleep 5
  current_epoch="$(date +%s)"
  if (( current_epoch >= next_heartbeat_epoch )) && kill -0 "$helper_pid" 2>/dev/null; then
    emit "milestone=bounded_profile_search;state=running;elapsed_seconds=$(( current_epoch - started_epoch ))"
    next_heartbeat_epoch=$(( current_epoch + 30 ))
  fi
done
if wait "$helper_pid"; then helper_status=0; else helper_status=$?; fi
helper_pid=''
if (( helper_status != 0 )); then
  reason="$(sed -nE 's/^extended_retrieval_profile_search=blocked;reason=([A-Za-z0-9_]+)$/\1/p' "$helper_error" | tail -n 1)"
  [[ -n "$reason" ]] || reason=unclassified_helper_failure
  block "$reason"
fi
for marker in \
  'candidate_count=43120;qualifying_candidate_count=0;database_contact=false;model_contact=false;method_profile_changed=false' \
  'released_mrr_at_20=0.852173;strict_production_target=greater_than_0.91;gate_basis=mrr_at_20_only' \
  'minimal_candidate=none;strict_target_met=false' \
  'extended_retrieval_profile_search=pass;selection_status=no_candidate_meets_target'; do
  grep -Fxq "$marker" "$helper_output" || block helper_pass_contract_invalid
done

PYTHONDONTWRITEBYTECODE=1 python3 -B - "$artifact_candidate" "$SCRIPT_129_ARTIFACT_SHA256" <<'PY'
import json
import sys
from pathlib import Path

value = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
released = value.get("released_profile", {})
highest = value.get("highest_mrr_candidate", {})
if (
    value.get("artifact_kind") != "ishikawa_extended_retrieval_profile_search"
    or value.get("schema_version") != 1
    or value.get("lane_observation_sha256") != sys.argv[2]
    or value.get("case_count") != 60
    or value.get("strict_production_target") != "greater_than_0.91"
    or value.get("candidate_count") != 43120
    or value.get("qualifying_candidate_count") != 0
    or value.get("gate_basis") != "strict_mrr_at_20_only"
    or value.get("minimal_change_qualifying_candidate") is not None
    or value.get("selection_status") != "no_candidate_meets_target"
    or value.get("method_profile_changed") is not False
    or value.get("database_contact") is not False
    or value.get("model_contact") is not False
    or value.get("question_text_read") is not False
    or value.get("query_vectors_read") is not False
    or value.get("source_text_read") is not False
    or released.get("mrr_at_20") != "0.852173"
    or highest.get("mrr_at_20") != "0.853168"
    or highest.get("strict_target_met") is not False
    or highest.get("relevant_at_5") != 56
    or highest.get("relevant_at_20") != 60
):
    raise SystemExit("extended profile search artifact contract invalid")
for forbidden in (
    "question", "query_vector", "embedding_vector", "vector_values",
    "retrieval_text", "source_text", "credential", "generated_answer",
):
    stack = [value]
    while stack:
        current = stack.pop()
        if isinstance(current, dict):
            if forbidden in current:
                raise SystemExit("search artifact contains a forbidden field")
            stack.extend(current.values())
        elif isinstance(current, list):
            stack.extend(current)
PY

identity_line="$(grep -E '^search_id=[0-9a-f]{64};artifact_sha256=[0-9a-f]{64};artifact_bytes=[0-9]+$' "$helper_output")" \
  || block search_identity_invalid
search_id="$(sed -nE 's/^search_id=([0-9a-f]{64});.*/\1/p' <<<"$identity_line")"
helper_artifact_sha256="$(sed -nE 's/^.*;artifact_sha256=([0-9a-f]{64});.*/\1/p' <<<"$identity_line")"
artifact_sha256="$(sha256sum "$artifact_candidate" | awk '{print $1}')"
artifact_bytes="$(stat -c '%s' "$artifact_candidate")"
[[ "$artifact_sha256" == "$helper_artifact_sha256" ]] || block artifact_identity_mismatch
artifact_path="$ARTIFACT_ROOT/extended_profile_search_${search_id}.json"
checksum_path="$artifact_path.sha256"
[[ ! -e "$artifact_path" && ! -L "$artifact_path" && ! -e "$checksum_path" && ! -L "$checksum_path" ]] \
  || block artifact_path_exists
mv -- "$artifact_candidate" "$artifact_path"
printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" >"$checksum_path"
(
  cd -- "$ARTIFACT_ROOT"
  sha256sum --check --strict "$(basename -- "$checksum_path")" >/dev/null
) || block artifact_checksum_failed
chmod 0600 "$artifact_path" "$checksum_path" 2>/dev/null || true
artifact_committed=true

candidate_line="$(grep -E '^candidate_count=43120;qualifying_candidate_count=0;.*$' "$helper_output")" \
  || block candidate_summary_missing
highest_line="$(grep -E '^highest_candidate_id=[0-9a-f]{64};mrr_at_20=0\.853168;.*$' "$helper_output")" \
  || block highest_candidate_summary_missing
highest_parameters="$(grep -E '^highest_depths=1,10,20,20;rrf_constant=20;lane_weights=1,2,4$' "$helper_output")" \
  || block highest_candidate_parameters_missing
emit 'milestone=bounded_profile_search;state=pass'
emit "$candidate_line"
emit 'released_mrr_at_20=0.852173;strict_production_target=greater_than_0.91;strict_target_met=false'
emit "$highest_line"
emit "$highest_parameters"
emit "search_id=$search_id;accepted_artifact=$artifact_path;accepted_artifact_sha256=$artifact_sha256;accepted_artifact_bytes=$artifact_bytes;accepted_checksum=$checksum_path"
emit 'script_130_extended_profile_search=pass;selection_status=no_candidate_meets_target;profile_changed=false;next_gate=review_retrieval_failure_modes_and_new_bounded_candidates'
