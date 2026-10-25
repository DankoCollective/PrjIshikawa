#!/usr/bin/env bash
# Freeze, regress, measure, and self-validate the V13-47 application ranking.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/200_implement_and_qualify_v13_47_application_ranking.sh --check
#   bash ./phase-28-apisachi-tokuli/scripts/200_implement_and_qualify_v13_47_application_ranking.sh --run

set -euo pipefail
umask 077

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly EVALUATOR="$SCRIPT_DIR/qualify_v13_47_application_ranking.py"
readonly TEST_RUNNER="$PRODUCT_ROOT/scripts/run-local-validation-tests.sh"
readonly METHOD_PROFILE="$PRODUCT_ROOT/config/templates/method_profile.yaml"
readonly RELATIONSHIP_REGISTRY="$PRODUCT_ROOT/config/templates/relationship_types.yaml"
readonly RETRIEVAL_SOURCE="$PYTHON_ROOT/ishikawa/retrieval.py"
readonly ADAPTER_SOURCE="$PYTHON_ROOT/ishikawa/postgres_retrieval.py"
readonly DATABASE_SCHEMA="$PRODUCT_ROOT/packaging/database/schema.sql"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly SOURCE_OBSERVATION="$REPO_ROOT/local/artifacts/ishikawa/v13-44-decomposed-passage-reranking/v13_44_decomposed_passage_reranking_20261023T074033Z.json"
readonly SELECTED_OBSERVATION="$REPO_ROOT/local/artifacts/ishikawa/v13-46-score-calibrated-global-reranking/v13_46_score_calibrated_global_reranking_20261023T143248Z.json"
readonly NORMALIZED="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v3/synthetic_corpus_v3_candidate_20261023T043639Z/qualification/normalized.json"
readonly TRUTH="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v3-preingestion/v3_retrieval_truth_20261023T045046Z.json"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v13-47-application-ranking"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v13-47-application-ranking"
readonly SOURCE_OBSERVATION_SHA256='43cdc1ee0c2acb23034ce0a9315ca7c11fcc095d5d38b1d010cd98ff6c88d7f2'
readonly SELECTED_OBSERVATION_SHA256='9b6198f287d9480b4b5390844f6eff44cb2e6094133b6e995eaf290c811cfa82'
readonly NORMALIZED_SHA256='1772584ecc02c86cc0bd96946318e608f576fd259676bc9851ab7c54bf766b02'
readonly TRUTH_SHA256='f74302d899d000b9493fecfeca4ffbe2995bb04aabef00bf327061c34c2a18a0'
readonly CHUNKS_SHA256='49a67ac067d06b6068878be6530ae4971bddb4a1f687545578bd1ef9254d19e4'
readonly CHUNK_PROFILE_ID='d72a07f81eabc1f521ab1fd54f84289979365c6c71f8e3220a53b1e8c9a1c037'
readonly RETRIEVAL_PROFILE_ID='7c8f8f37ccce47cde1bdbb6cb43b321be14e54a11c8435e845ab7508c3dc8edb'

mode="${1:-}"
if [[ "$#" -ne 1 || ( "$mode" != "--check" && "$mode" != "--run" ) ]]; then
  printf 'reason=exactly_one_mode_required\n\nSCRIPT RESULT\nscript_200_v13_47_application_qualification=blocked\n' >&2
  exit 2
fi

for command in bash python3 sha256sum mktemp grep sed mkdir date tee tail rm; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'reason=missing_command_%s\n\nSCRIPT RESULT\nscript_200_v13_47_application_qualification=blocked\n' "$command" >&2
    exit 1
  fi
done

for path in \
  "$EVALUATOR" "$TEST_RUNNER" "$METHOD_PROFILE" "$RELATIONSHIP_REGISTRY" \
  "$RETRIEVAL_SOURCE" "$ADAPTER_SOURCE" "$DATABASE_SCHEMA" "$DECISIONS" \
  "$SOURCE_OBSERVATION" "$SELECTED_OBSERVATION" "$NORMALIZED" "$TRUTH"; do
  if [[ ! -f "$path" || -L "$path" ]]; then
    printf 'reason=required_input_unsafe\n\nSCRIPT RESULT\nscript_200_v13_47_application_qualification=blocked\n' >&2
    exit 1
  fi
done

verify_sha256() {
  local path="$1"
  local expected="$2"
  local actual
  actual="$(sha256sum -- "$path")"
  actual="${actual%% *}"
  [[ "$actual" == "$expected" ]]
}

verify_sha256 "$SOURCE_OBSERVATION" "$SOURCE_OBSERVATION_SHA256" || {
  printf 'reason=v13_44_observation_identity_changed\n\nSCRIPT RESULT\nscript_200_v13_47_application_qualification=blocked\n' >&2
  exit 1
}
verify_sha256 "$SELECTED_OBSERVATION" "$SELECTED_OBSERVATION_SHA256" || {
  printf 'reason=v13_46_observation_identity_changed\n\nSCRIPT RESULT\nscript_200_v13_47_application_qualification=blocked\n' >&2
  exit 1
}
verify_sha256 "$NORMALIZED" "$NORMALIZED_SHA256" || {
  printf 'reason=normalized_corpus_identity_changed\n\nSCRIPT RESULT\nscript_200_v13_47_application_qualification=blocked\n' >&2
  exit 1
}
verify_sha256 "$TRUTH" "$TRUTH_SHA256" || {
  printf 'reason=retrieval_truth_identity_changed\n\nSCRIPT RESULT\nscript_200_v13_47_application_qualification=blocked\n' >&2
  exit 1
}
grep -Fq '| `V13-47` |' "$DECISIONS" || {
  printf 'reason=v13_47_not_frozen\n\nSCRIPT RESULT\nscript_200_v13_47_application_qualification=blocked\n' >&2
  exit 1
}

if [[ "$mode" == "--check" ]]; then
  printf 'script=200;state=ready;action=regress_measure_and_self_validate_v13_47\n'
  printf 'external_calls=none;database_writes=none;corpus_ingestion=false\n'
  printf '\nSCRIPT RESULT\nscript_200_v13_47_application_qualification=ready\n'
  exit 0
fi

mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/v13_47_application_ranking_${timestamp}_XXXXXX.txt")"
run_dir="$(mktemp -d /tmp/ishikawa-script-200.XXXXXX)"
test_log="$run_dir/native-tests.txt"
artifact_path="$ARTIFACT_ROOT/v13_47_application_ranking_${timestamp}.json"
[[ ! -e "$artifact_path" ]] || {
  printf 'reason=qualification_artifact_already_exists\n\nSCRIPT RESULT\nscript_200_v13_47_application_qualification=blocked\n' >&2
  exit 1
}

cleanup() {
  rm -rf -- "$run_dir"
}
trap cleanup EXIT

emit() {
  printf '%s\n' "$1" | tee -a "$report_path"
}

block() {
  emit "script_state=blocked;reason=$1"
  emit "local_report=$report_path"
  printf '\nSCRIPT RESULT\nscript_200_v13_47_application_qualification=blocked\n' | tee -a "$report_path"
  exit 1
}

emit 'purpose=implement_regress_measure_and_validate_v13_47_in_one_execution'
emit "started_utc=$timestamp"
emit 'external_calls=none;database_writes=none;corpus_ingestion=false'
emit 'milestone=native_regression;state=start'
if ! bash "$TEST_RUNNER" >"$test_log" 2>&1; then
  tail -n 80 "$test_log" | tee -a "$report_path"
  block native_regression_failed
fi
grep -Fq 'ishikawa_local_validation_tests=PASS' "$test_log" \
  || block native_regression_result_missing
test_count="$(sed -n 's/^Ran \([0-9][0-9]*\) tests.*/\1/p' "$test_log" | tail -n 1)"
[[ "$test_count" =~ ^[0-9]+$ && "$test_count" -ge 449 ]] \
  || block native_regression_count_invalid
emit "milestone=native_regression;state=pass;tests=$test_count"

emit 'milestone=implemented_source_qualification;state=start;cases=180'
if ! python3 "$EVALUATOR" \
  --python-root "$PYTHON_ROOT" \
  --source-observation "$SOURCE_OBSERVATION" \
  --expected-source-observation-sha256 "$SOURCE_OBSERVATION_SHA256" \
  --selected-observation "$SELECTED_OBSERVATION" \
  --expected-selected-observation-sha256 "$SELECTED_OBSERVATION_SHA256" \
  --normalized "$NORMALIZED" \
  --expected-normalized-sha256 "$NORMALIZED_SHA256" \
  --truth "$TRUTH" \
  --expected-truth-sha256 "$TRUTH_SHA256" \
  --expected-chunks-sha256 "$CHUNKS_SHA256" \
  --expected-chunk-profile-id "$CHUNK_PROFILE_ID" \
  --expected-retrieval-profile-id "$RETRIEVAL_PROFILE_ID" \
  --method-profile "$METHOD_PROFILE" \
  --relationship-registry "$RELATIONSHIP_REGISTRY" \
  --retrieval-source "$RETRIEVAL_SOURCE" \
  --adapter-source "$ADAPTER_SOURCE" \
  --database-schema "$DATABASE_SCHEMA" \
  --output "$artifact_path" \
  2>&1 | tee -a "$report_path"; then
  block implemented_source_qualification_failed
fi
grep -Fq 'v13_47_application_ranking_qualification=pass' "$report_path" \
  || block implemented_source_qualification_result_missing

python3 - "$artifact_path" "$RETRIEVAL_PROFILE_ID" <<'PY' \
  || block retained_qualification_validation_failed
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
expected_profile = sys.argv[2]
value = json.loads(path.read_text(encoding="utf-8"))
assert value["artifact_kind"] == "ishikawa_v13_47_application_ranking_qualification"
assert value["qualification_status"] == "pass"
assert value["implemented_retrieval_profile_id"] == expected_profile
assert value["selected_candidate"] == "raw_l1_v3_fc1_d1_h010"
assert value["case_count"] == 180
assert value["candidate_pool_matches"] == 180
assert value["first_relevant_rank_matches"] == 180
assert value["exact_full_order_matches"] >= 179
assert value["metrics"]["body"]["mrr_at_20"] == "0.895450"
assert value["metrics"]["body"]["relevant_at_20"] == 120
assert value["metrics"]["relationship"]["relevant_at_20"] == 30
assert value["metrics"]["header"]["relevant_at_20"] == 30
assert value["gate"]["status"] == "qualified"
assert value["boundaries"] == {
    "accepted_database_contact": False,
    "application_source_imported": True,
    "black_corpus_access": False,
    "corpus_ingestion": False,
    "gemma_contact": False,
    "nomic_contact": False,
    "postgresql_contact": False,
    "runtime_flat_file_index": False,
}
assert set(value["implementation_sha256"]) == {
    "retrieval", "postgres_retrieval", "method_profile",
    "relationship_registry", "database_schema",
}
PY

artifact_sha256="$(sha256sum -- "$artifact_path")"
artifact_sha256="${artifact_sha256%% *}"
emit "milestone=implemented_source_qualification;state=pass;artifact_sha256=$artifact_sha256"
emit 'qualification=pass;body_mrr_at_20=0.895450;body_coverage=120/120;cases=180'
emit 'next_gate=isolated_corpus_v3_ingestion_and_complete_api_qualification'
emit "local_artifact=$artifact_path"
emit "local_report=$report_path"

printf '\nSCRIPT RESULT\nscript_200_v13_47_application_qualification=pass\n' | tee -a "$report_path"
