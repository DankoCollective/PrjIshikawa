#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Qualify the frozen T09 retrieval-profile implementation and run the
#   complete native Ishikawa regression suite.
#
# Mental model:
#   Rebind the accepted Script 119 recommendation, prove the tracked YAML and
#   runtime implement exactly that candidate, exercise the evaluator self-test,
#   and run every native application test. This is source qualification; the
#   next gate remeasures all live tuning cases against PostgreSQL and Nomic.
#
# Inputs or prerequisites:
#   The checksum-valid Script 119 report, artifact, and checksum; frozen T09;
#   and the tracked Ishikawa v1.1 working source.
#
# Outputs or artifact lane:
#   One content-free local qualification report. No package, database, model,
#   service, credential, or accepted Ishikawa v1 artifact is changed.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/120_qualify_frozen_t09_retrieval_profile.sh --run

usage() {
  sed -n '3,25p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run            Qualify the frozen T09 implementation.' \
    '  --validate-only  Validate bound source and run tests without a report.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly CONFIG_ROOT="$PRODUCT_ROOT/config/templates"
readonly TEST_RUNNER="$PRODUCT_ROOT/scripts/run-local-validation-tests.sh"
readonly EVALUATOR="$SCRIPT_DIR/evaluate_local_retrieval_ranking.py"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_1_TUNING_DECISIONS.md"
readonly SEARCH_REPORT="$REPO_ROOT/local/reports/ishikawa-v1.1-parameter-search/parameter_search_20261021T172249Z_ZUphTD.txt"
readonly SEARCH_ARTIFACT="$REPO_ROOT/local/artifacts/ishikawa/v1.1-parameter-search/parameter_search_08487b666fe2431491bbaee23071d98cc07774dd7f774aa374cff8d6e85fe6de.json"
readonly SEARCH_CHECKSUM="$SEARCH_ARTIFACT.sha256"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v1.1-t09-implementation"

readonly SEARCH_REPORT_SHA256='9f6a1a6ba7ae40944775ceed549f6f7dc99b1b11259a7892f27c584009b1da67'
readonly SEARCH_ARTIFACT_SHA256='542143679f4310add2520ba25c76546176b2e510487048b972523f5160b562e9'
readonly SEARCH_CHECKSUM_SHA256='f823ee8435943985f8545cd155f3f4e2f9f9925cfaa824dde64d8cb3a2a3301f'
readonly DECISIONS_SHA256='7834ffbc01b6687f49f52066d7c3e8757c01f7492683a49dd30407e517ef8dbc'
readonly METHOD_PROFILE_SOURCE_SHA256='8f0b1c32f3e0b5f56ec7c280298362746736b1bb9ee9a3f91f20229d595be004'
readonly RETRIEVAL_SOURCE_SHA256='7b3acf2a8a47fd466d33f147d5d023ec65bccf38bfc75b2ead1e548704ff5ba1'
readonly POSTGRES_RETRIEVAL_SOURCE_SHA256='c3dd56ee1de37162428d47a683289508a841718fd857b446bdbe92bc18fa824a'
readonly METHOD_PROFILE_CONFIG_SHA256='0d329981f1259e5d5f8138350af538a08a3d70a704241b384da6714f3b17724c'
readonly RELATIONSHIP_CONFIG_SHA256='448ce592b9165321a9ab48e328dd8a83c532ef6fc7132c7e03bc7864e4f47a1f'
readonly METHOD_PROFILE_TEST_SHA256='19f65f7cfccf0b4ad874b99e7823125fcddb0eaf90051faaf497e40146d10cd1'
readonly RETRIEVAL_TEST_SHA256='bc4cad09fd4a453cb7070fc02083e69d264eb055bbb8be85c6ea62c68cd166ef'
readonly POSTGRES_RETRIEVAL_TEST_SHA256='dee29a906a1ec585fda6a0274edd6d2ec76162b71a3ee817112c1ff4c45381f2'
readonly RELATIONSHIP_TEST_SHA256='1f897f3a3ac7861609a246598fb9dc677068f65d083eb04a9fc8e7306e31f9fa'
readonly EVALUATOR_SHA256='4572e0682b052af8b5f498c207c3e7f0b512fc2405f0e2b353278bdaa0b5d996'
readonly TEST_RUNNER_SHA256='092b2cb8e5254d1ca2b6e71a496bf76743004134848e249d5d7b9f37d9d62eb7'
readonly T09_CANDIDATE_ID='a767efb74a690f4ded16b1aed5f4d2c0b880a40dfc4b22e653be366e616f4eda'
readonly T09_RETRIEVAL_PROFILE_ID='ba4bac60b3f09f6be89db148d1df883748a2003f35a1cecfb6c74f53be74b865'

run_mode=false
validate_mode=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_mode=true; shift ;;
    --validate-only) validate_mode=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'script_120_t09_implementation=blocked;reason=argument_invalid\n' >&2; exit 2 ;;
  esac
done
[[ "$run_mode" != "$validate_mode" ]] || {
  printf 'script_120_t09_implementation=blocked;reason=mode_invalid\n' >&2
  exit 2
}

for required in awk bash basename date grep mkdir mktemp python3 rm sed sha256sum stat tee; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'script_120_t09_implementation=blocked;reason=local_command_missing;command=%s\n' "$required" >&2
    exit 2
  }
done

check_file() {
  [[ -f "$1" && ! -L "$1" && -r "$1" ]] || {
    printf 'script_120_t09_implementation=blocked;reason=%s_unsafe\n' "$3" >&2
    exit 2
  }
  [[ "$(sha256sum "$1" | awk '{print $1}')" == "$2" ]] || {
    printf 'script_120_t09_implementation=blocked;reason=%s_identity_changed\n' "$3" >&2
    exit 2
  }
}

check_file "$SEARCH_REPORT" "$SEARCH_REPORT_SHA256" search_report
check_file "$SEARCH_ARTIFACT" "$SEARCH_ARTIFACT_SHA256" search_artifact
check_file "$SEARCH_CHECKSUM" "$SEARCH_CHECKSUM_SHA256" search_checksum
check_file "$DECISIONS" "$DECISIONS_SHA256" tuning_decisions
check_file "$PYTHON_ROOT/ishikawa/method_profile.py" "$METHOD_PROFILE_SOURCE_SHA256" method_profile_source
check_file "$PYTHON_ROOT/ishikawa/retrieval.py" "$RETRIEVAL_SOURCE_SHA256" retrieval_source
check_file "$PYTHON_ROOT/ishikawa/postgres_retrieval.py" "$POSTGRES_RETRIEVAL_SOURCE_SHA256" postgres_retrieval_source
check_file "$CONFIG_ROOT/method_profile.yaml" "$METHOD_PROFILE_CONFIG_SHA256" method_profile_config
check_file "$CONFIG_ROOT/relationship_types.yaml" "$RELATIONSHIP_CONFIG_SHA256" relationship_config
check_file "$PRODUCT_ROOT/tests/test_method_profile.py" "$METHOD_PROFILE_TEST_SHA256" method_profile_test
check_file "$PRODUCT_ROOT/tests/test_retrieval.py" "$RETRIEVAL_TEST_SHA256" retrieval_test
check_file "$PRODUCT_ROOT/tests/test_postgres_retrieval.py" "$POSTGRES_RETRIEVAL_TEST_SHA256" postgres_retrieval_test
check_file "$PRODUCT_ROOT/tests/test_relationships.py" "$RELATIONSHIP_TEST_SHA256" relationship_test
check_file "$EVALUATOR" "$EVALUATOR_SHA256" ranking_evaluator
check_file "$TEST_RUNNER" "$TEST_RUNNER_SHA256" test_runner

(
  cd -- "$(dirname -- "$SEARCH_CHECKSUM")"
  sha256sum --check --strict "$(basename -- "$SEARCH_CHECKSUM")" >/dev/null
) || {
  printf 'script_120_t09_implementation=blocked;reason=search_checksum_failed\n' >&2
  exit 2
}
for fact in \
  "recommended_candidate_id=$T09_CANDIDATE_ID;mrr_at_20=0.916667;responsive_top_five=6/6;required_evidence_at_20=13/13" \
  'recommended_depths=1,20,20,20;rrf_constant=60;lane_weights=1,1,4' \
  'script_119_parameter_search=pass;selection_status=review_required;'; do
  grep -Fq "$fact" "$SEARCH_REPORT" || {
    printf 'script_120_t09_implementation=blocked;reason=search_report_contract_invalid\n' >&2
    exit 2
  }
done
grep -Eq '^\| `T09` \|.*a767efb74a690f4ded16b1aed5f4d2c0b880a40dfc4b22e653be366e616f4eda.*\| FROZEN \|$' "$DECISIONS" || {
  printf 'script_120_t09_implementation=blocked;reason=t09_decision_contract_invalid\n' >&2
  exit 2
}

bash -n "${BASH_SOURCE[0]}" "$TEST_RUNNER"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
  "$EVALUATOR"

work_root="$(mktemp -d /tmp/ishikawa-script-120.XXXXXX)"
report_path=''
cleanup() {
  local status="$?"
  trap - EXIT INT TERM
  [[ "$work_root" == /tmp/ishikawa-script-120.* && -d "$work_root" ]] && rm -rf -- "$work_root"
  exit "$status"
}
trap cleanup EXIT

emit() {
  if [[ -n "$report_path" ]]; then
    printf '%s\n' "$1" | tee -a "$report_path"
  else
    printf '%s\n' "$1"
  fi
}
block() {
  emit "script_120_t09_implementation=blocked;reason=$1"
  exit 1
}
trap 'block interrupted_by_operator' INT
trap 'block terminated_by_signal' TERM

if [[ "$run_mode" == true ]]; then
  mkdir -p -- "$REPORT_ROOT"
  [[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" ]] || block report_directory_unsafe
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  report_path="$(mktemp "$REPORT_ROOT/t09_implementation_${timestamp}_XXXXXX.txt")"
  emit '[PROFILE] milestone=t09_contract;state=start'
fi

profile_output="$work_root/profile.stdout"
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PYTHON_ROOT" python3 -B - \
  "$CONFIG_ROOT" "$SEARCH_ARTIFACT" "$T09_CANDIDATE_ID" "$T09_RETRIEVAL_PROFILE_ID" \
  >"$profile_output" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

from ishikawa.method_profile import validate_retrieval_profile
from ishikawa.relationships import validate_relationship_registry
from ishikawa.yaml_loader import load_restricted_yaml

config_root = Path(sys.argv[1])
search = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
candidate_id = sys.argv[3]
expected_profile_id = sys.argv[4]
profile = validate_retrieval_profile(
    load_restricted_yaml(config_root / "method_profile.yaml", label="method profile")
)
relationships = validate_relationship_registry(
    load_restricted_yaml(config_root / "relationship_types.yaml", label="relationship registry")
)
parameters = {
    "exact_candidate_depth": profile.exact_candidate_depth,
    "lexical_candidate_depth": profile.lexical_candidate_depth,
    "vector_candidate_depth": profile.vector_candidate_depth,
    "fused_candidate_depth": profile.fused_candidate_depth,
    "rrf_constant": profile.rrf_constant,
    "lane_weights": {
        "exact": profile.exact_weight,
        "lexical": profile.lexical_weight,
        "vector": profile.vector_weight,
    },
}
recommended = search.get("recommended_candidate")
if (
    search.get("operator_freeze_required") is not True
    or not isinstance(recommended, dict)
    or recommended.get("candidate_id") != candidate_id
    or recommended.get("parameters") != parameters
    or profile.digest != expected_profile_id
    or relationships.base_retrieval_profile_id != profile.digest
    or profile.learned_reranker is not False
):
    raise SystemExit("T09 source contract mismatch")
print(f"retrieval_profile_id={profile.digest}")
print("depths=1,20,20,20;rrf_constant=60;lane_weights=1,1,4;learned_reranker=false")
print("relationship_profile_binding=pass")
print("t09_profile_contract=pass")
PY
grep -Fxq "retrieval_profile_id=$T09_RETRIEVAL_PROFILE_ID" "$profile_output" \
  || block retrieval_profile_identity_invalid
grep -Fxq 't09_profile_contract=pass' "$profile_output" || block t09_profile_contract_invalid
[[ "$run_mode" == true ]] && emit "[PROFILE] milestone=t09_contract;state=pass;retrieval_profile_id=$T09_RETRIEVAL_PROFILE_ID"

evaluator_output="$work_root/evaluator.stdout"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" --self-test >"$evaluator_output" \
  || block ranking_evaluator_self_test_failed
grep -Fxq 'local_retrieval_ranking_evaluator_self_test=pass' "$evaluator_output" \
  || block ranking_evaluator_self_test_marker_absent

[[ "$run_mode" == true ]] && emit '[REGRESSION] milestone=native_tests;state=start;expected_tests=371'
test_output="$work_root/native-tests.txt"
if PYTHONDONTWRITEBYTECODE=1 bash "$TEST_RUNNER" >"$test_output" 2>&1; then
  test_status=0
else
  test_status=$?
fi
(( test_status == 0 )) || {
  emit "script_120_t09_implementation=blocked;reason=native_test_regression;diagnostic_sha256=$(sha256sum "$test_output" | awk '{print $1}');diagnostic_bytes=$(stat -c '%s' "$test_output");raw_output_retained=false"
  exit 1
}
grep -Fq 'Ran 371 tests' "$test_output" || block native_test_count_mismatch
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$test_output" \
  || block native_test_pass_marker_absent

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_mode" == true ]]; then
  printf '%s\n' \
    'purpose=validate_frozen_t09_retrieval_profile_implementation' \
    "script_sha256=$script_sha256;decision_list_sha256=$DECISIONS_SHA256;search_artifact_sha256=$SEARCH_ARTIFACT_SHA256" \
    "candidate_id=$T09_CANDIDATE_ID;retrieval_profile_id=$T09_RETRIEVAL_PROFILE_ID" \
    'depths=1,20,20,20;rrf_constant=60;lane_weights=1,1,4;learned_reranker=false' \
    'native_tests=371;failures=0;errors=0;evaluator_self_test=pass' \
    'database_contact=false;model_contact=false;credential_read=false;service_changed=false;package_built=false' \
    'script_120_t09_implementation_source=pass'
  exit 0
fi

emit '[REGRESSION] milestone=native_tests;state=pass;tests=371;failures=0;errors=0'
emit "[SUMMARY] candidate_id=$T09_CANDIDATE_ID;retrieval_profile_id=$T09_RETRIEVAL_PROFILE_ID"
emit '[SUMMARY] depths=1,20,20,20;rrf_constant=60;lane_weights=1,1,4;learned_reranker=false'
emit '[SUMMARY] database_contact=false;model_contact=false;credential_read=false;service_changed=false;package_built=false'
emit "script_120_t09_implementation=pass;next_gate=remeasure_live_t09_ranking_all_13_cases;local_report=$report_path"
