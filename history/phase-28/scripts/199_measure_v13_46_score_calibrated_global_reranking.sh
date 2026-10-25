#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Measure the frozen V13-46 score-calibrated global reranking experiment.
#
# Boundaries:
#   Reuses checksum-bound V13-44 evidence.  It contacts no service, database,
#   model, or remote host and changes no corpus, profile, package, or release.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/199_measure_v13_46_score_calibrated_global_reranking.sh --run

usage() {
  sed -n '3,13p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Execute the frozen five-candidate, 180-case experiment.' \
    '  --validate-only Validate local inputs and implementation contracts.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly PRODUCT_ROOT="$PHASE_ROOT/Ishikawa"
readonly PYTHON_ROOT="$PRODUCT_ROOT/application/python"
readonly EVALUATOR="$SCRIPT_DIR/measure_v13_46_score_calibrated_global_reranking.py"
readonly BASE_EVALUATOR="$SCRIPT_DIR/measure_synthetic_corpus_v2_without_ingestion.py"
readonly V3_EVALUATOR="$SCRIPT_DIR/measure_synthetic_corpus_v3_preingestion.py"
readonly V40_EVALUATOR="$SCRIPT_DIR/measure_v13_40_bounded_ranking_candidates.py"
readonly V41_EVALUATOR="$SCRIPT_DIR/measure_v13_41_supplemental_ranking.py"
readonly V44_EVALUATOR="$SCRIPT_DIR/measure_v13_44_decomposed_passage_reranking.py"
readonly CHUNKER="$PYTHON_ROOT/ishikawa/chunking.py"
readonly TEST_RUNNER="$PRODUCT_ROOT/scripts/run-local-validation-tests.sh"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly SOURCE_OBSERVATION="$REPO_ROOT/local/artifacts/ishikawa/v13-44-decomposed-passage-reranking/v13_44_decomposed_passage_reranking_20261023T074033Z.json"
readonly NORMALIZED="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v3/synthetic_corpus_v3_candidate_20261023T043639Z/qualification/normalized.json"
readonly TRUTH="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v3-preingestion/v3_retrieval_truth_20261023T045046Z.json"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v13-46-score-calibrated-global-reranking"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/v13-46-score-calibrated-global-reranking"
readonly EXPECTED_HOST='DankoSurface'
readonly EXPECTED_OS_ID='ubuntu'
readonly EXPECTED_OS_VERSION='24.04'
readonly EXPECTED_ARCHITECTURE='aarch64'
readonly CHUNK_PROFILE_ID='d72a07f81eabc1f521ab1fd54f84289979365c6c71f8e3220a53b1e8c9a1c037'
readonly RETRIEVAL_PROFILE_ID='cfa9bbc353dc82d3ba74396de40df6ba429b7df2750e7809b92eeefd4a433147'
readonly SOURCE_OBSERVATION_SHA256='43cdc1ee0c2acb23034ce0a9315ca7c11fcc095d5d38b1d010cd98ff6c88d7f2'
readonly NORMALIZED_SHA256='1772584ecc02c86cc0bd96946318e608f576fd259676bc9851ab7c54bf766b02'
readonly TRUTH_SHA256='f74302d899d000b9493fecfeca4ffbe2995bb04aabef00bf327061c34c2a18a0'
readonly CHUNKS_SHA256='49a67ac067d06b6068878be6530ae4971bddb4a1f687545578bd1ef9254d19e4'
readonly EVALUATOR_SHA256='fa0b30369cb47ad8499ee2f7acff9d1fa056392286d11e537a91fec8f7e60dd5'
readonly BASE_EVALUATOR_SHA256='094b30ac886c36ffa1f2269898b69b7bab7e5e19729de22b0e13fd3aa39e5176'
readonly V3_EVALUATOR_SHA256='4d7138d5ca94a8422c02727b24014a04abc0a3ac0c2e48f3fbfa0bd07a7633dc'
readonly V40_EVALUATOR_SHA256='5c3b43c52db1617be6c089f1ac20afb5a47e2b18c47ada41341c9ee4d0669662'
readonly V41_EVALUATOR_SHA256='4c05544d55294be6bd82d01d32c53d28a4f11687322d6edd086b9f752523f1ea'
readonly V44_EVALUATOR_SHA256='fdea573adf5a6dec893f0df20c8b5b4c6992175f711f35cf9f9804f3a5168586'
readonly CHUNKER_SHA256='18cde74095f66108918edad2183752cdcc2ce7eeab6c2cc13a3d16dab588e995'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      usage >&2
      printf '\nSCRIPT RESULT\nscript_199_v13_46_score_calibrated_global_reranking=blocked\n' >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'reason=exactly_one_mode_required\n\nSCRIPT RESULT\nscript_199_v13_46_score_calibrated_global_reranking=blocked\n' >&2
  exit 2
}

for command_name in awk bash date grep hostname id mkdir mktemp mv python3 rm \
  sed sha256sum tail tee tr uname; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'reason=missing_command_%s\n\nSCRIPT RESULT\nscript_199_v13_46_score_calibrated_global_reranking=blocked\n' \
      "$command_name" >&2
    exit 2
  }
done

check_file() {
  local path="$1" expected_sha256="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] || {
    printf 'reason=%s_unsafe\n\nSCRIPT RESULT\nscript_199_v13_46_score_calibrated_global_reranking=blocked\n' \
      "$label" >&2
    exit 2
  }
  [[ "$(sha256sum "$path" | awk '{print $1}')" == "$expected_sha256" ]] || {
    printf 'reason=%s_identity_changed\n\nSCRIPT RESULT\nscript_199_v13_46_score_calibrated_global_reranking=blocked\n' \
      "$label" >&2
    exit 2
  }
}

check_file "$EVALUATOR" "$EVALUATOR_SHA256" evaluator
check_file "$BASE_EVALUATOR" "$BASE_EVALUATOR_SHA256" base_evaluator
check_file "$V3_EVALUATOR" "$V3_EVALUATOR_SHA256" v3_evaluator
check_file "$V40_EVALUATOR" "$V40_EVALUATOR_SHA256" v40_evaluator
check_file "$V41_EVALUATOR" "$V41_EVALUATOR_SHA256" v41_evaluator
check_file "$V44_EVALUATOR" "$V44_EVALUATOR_SHA256" v44_evaluator
check_file "$CHUNKER" "$CHUNKER_SHA256" chunker
check_file "$SOURCE_OBSERVATION" "$SOURCE_OBSERVATION_SHA256" v13_44_observation
check_file "$NORMALIZED" "$NORMALIZED_SHA256" normalized_v3
check_file "$TRUTH" "$TRUTH_SHA256" retrieval_truth
grep -Fq '| `V13-46` |' "$DECISIONS" || {
  printf 'reason=v13_46_not_frozen\n\nSCRIPT RESULT\nscript_199_v13_46_score_calibrated_global_reranking=blocked\n' >&2
  exit 1
}

bash -n "${BASH_SOURCE[0]}"
for python_source in "$EVALUATOR" "$BASE_EVALUATOR" "$V3_EVALUATOR" \
  "$V40_EVALUATOR" "$V41_EVALUATOR" "$V44_EVALUATOR" "$CHUNKER"; do
  PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
    'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
    "$python_source"
done
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" --self-test \
  | grep -Fxq 'v13_46_score_calibrated_global_reranking_measurement_self_test=pass'
PYTHONDONTWRITEBYTECODE=1 python3 -B - "$SOURCE_OBSERVATION" <<'PY'
import json,pathlib,sys
x=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert x["artifact_kind"]=="ishikawa_v13_44_decomposed_passage_reranking_experiment"
assert x["selection_status"]=="not_met" and x["selected_candidate"] is None
assert x["promotion_authorized"] is False and x["qualified_candidates"]==[]
best=x["variants"]["facet5_b2_e1_c1"]
assert best["metrics"]["body"]["mrr_at_20"]=="0.823546"
assert best["metrics"]["body"]["relevant_at_20"]==120
assert len(best["results"]["selection"])==180
PY

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_frozen_v13_46_score_calibrated_global_reranking' \
    "script_sha256=$script_sha256;evaluator_sha256=$EVALUATOR_SHA256" \
    "chunk_profile_id=$CHUNK_PROFILE_ID;retrieval_profile_id=$RETRIEVAL_PROFILE_ID" \
    'documents=30;cases=180;candidates=5;source_candidate_pool=v13_44_top_20' \
    'body_mrr_gate=0.89;body_coverage_gate=120/120;authoritative_expansion_gate=180/180' \
    'model_contact=false;database_contact=false;service_contact=false;corpus_ingestion=false' \
    '' \
    'SCRIPT RESULT' \
    'script_199_v13_46_score_calibrated_global_reranking=pass'
  exit 0
fi

work_root=''
report_path=''
observation_candidate=''
failure_reason='unexpected_failure'

emit() {
  if [[ -n "$report_path" ]]; then
    printf '%s\n' "$1" | tee -a "$report_path"
  else
    printf '%s\n' "$1"
  fi
}

remove_work_root() {
  if [[ -n "$work_root" && "$work_root" == /tmp/ishikawa-script-199.* \
        && -d "$work_root" ]]; then
    rm -rf -- "$work_root"
  fi
  work_root=''
}

failure_cleanup() {
  local initial_status="$?" diagnostic
  trap - EXIT HUP INT TERM
  set +e
  for diagnostic in native-tests.stdout native-tests.stderr measurement.stdout \
    measurement.stderr validation-summary.txt validation.stderr; do
    if [[ -n "$work_root" && -s "$work_root/$diagnostic" ]]; then
      emit "diagnostic_${diagnostic//[^a-zA-Z0-9]/_}_tail_begin;maximum_lines=120"
      while IFS= read -r line; do emit "$line"; done \
        < <(tail -n 120 -- "$work_root/$diagnostic")
      emit "diagnostic_${diagnostic//[^a-zA-Z0-9]/_}_tail_end"
    fi
  done
  remove_work_root
  if [[ -n "$report_path" && -f "$report_path" ]]; then
    emit "script_state=blocked;reason=$failure_reason;exit_code=$initial_status"
    printf 'local_report=%s;local_report_sha256=%s\n' \
      "$report_path" "$(sha256sum "$report_path" | awk '{print $1}')"
  else
    printf 'script_state=blocked;reason=%s;exit_code=%s\n' \
      "$failure_reason" "$initial_status"
  fi
  printf '\nSCRIPT RESULT\nscript_199_v13_46_score_calibrated_global_reranking=blocked\n'
  exit "$initial_status"
}
trap failure_cleanup EXIT
trap 'failure_reason=interrupted; exit 130' HUP INT TERM
trap 'failure_reason="unexpected_failure_line_${LINENO}"' ERR
block() { failure_reason="$1"; exit 1; }

umask 077
mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT"
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" \
   && -d "$ARTIFACT_ROOT" && ! -L "$ARTIFACT_ROOT" ]] \
  || block output_directory_unsafe
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/v13_46_score_calibrated_global_reranking_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-script-199.XXXXXX)"
actual_hostname="$(hostname -s)"
actual_os_id="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"' | awk 'NR == 1')"
actual_os_version="$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"' | awk 'NR == 1')"
actual_architecture="$(uname -m)"

emit 'purpose=measure_frozen_v13_46_score_calibrated_global_reranking'
emit "started_utc=$timestamp;hostname=$actual_hostname;os_version=$actual_os_version;architecture=$actual_architecture"
emit "script_sha256=$script_sha256;evaluator_sha256=$EVALUATOR_SHA256"
emit "source_observation_sha256=$SOURCE_OBSERVATION_SHA256;chunk_profile_id=$CHUNK_PROFILE_ID;retrieval_profile_id=$RETRIEVAL_PROFILE_ID"
emit 'authorized_actions=run_native_tests_reuse_checksum_bound_v13_44_evidence_measure_180_cases_write_metrics_only_observation'
emit 'non_actions=no_service_or_model_or_database_contact_no_ingestion_no_black_corpus_no_profile_package_or_release_change'
[[ "$actual_hostname" == "$EXPECTED_HOST" && "$actual_os_id" == "$EXPECTED_OS_ID" \
    && "$actual_os_version" == "$EXPECTED_OS_VERSION" \
    && "$actual_architecture" == "$EXPECTED_ARCHITECTURE" ]] \
  || block local_host_identity_mismatch

emit 'milestone=native_tests;state=start'
bash "$TEST_RUNNER" >"$work_root/native-tests.stdout" 2>"$work_root/native-tests.stderr" \
  || block native_tests_failed
grep -Fxq 'ishikawa_local_validation_tests=PASS' "$work_root/native-tests.stdout" \
  || block native_tests_pass_marker_absent
test_count="$(sed -n 's/^Ran \([0-9][0-9]*\) tests\{0,1\} in .*/\1/p' \
  "$work_root/native-tests.stderr" | tail -n 1)"
[[ "$test_count" =~ ^[0-9]+$ && "$test_count" -ge 444 ]] \
  || block native_test_count_invalid
emit "milestone=native_tests;state=pass;tests=$test_count"

observation_candidate="$work_root/v13-46-observation.json"
emit 'milestone=score_calibrated_global_reranking;state=start;cases=180;candidates=5;external_calls=0'
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" \
  --python-root "$PYTHON_ROOT" \
  --source-observation "$SOURCE_OBSERVATION" \
  --expected-source-observation-sha256 "$SOURCE_OBSERVATION_SHA256" \
  --normalized "$NORMALIZED" --expected-normalized-sha256 "$NORMALIZED_SHA256" \
  --truth "$TRUTH" --expected-truth-sha256 "$TRUTH_SHA256" \
  --expected-chunks-sha256 "$CHUNKS_SHA256" \
  --chunk-profile-id "$CHUNK_PROFILE_ID" \
  --retrieval-profile-id "$RETRIEVAL_PROFILE_ID" \
  --output "$observation_candidate" \
  >"$work_root/measurement.stdout" 2>"$work_root/measurement.stderr" \
  || block score_calibrated_global_reranking_measurement_failed
grep -Fxq 'v13_46_score_calibrated_global_reranking_measurement=pass' \
  "$work_root/measurement.stdout" || block measurement_pass_marker_absent

PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$SCRIPT_DIR" "$observation_candidate" "$SOURCE_OBSERVATION_SHA256" \
  "$NORMALIZED_SHA256" "$TRUTH_SHA256" "$CHUNKS_SHA256" \
  "$CHUNK_PROFILE_ID" "$RETRIEVAL_PROFILE_ID" \
  >"$work_root/validation-summary.txt" 2>"$work_root/validation.stderr" <<'PY' \
  || block observation_invalid
import json,math,pathlib,re,sys
sys.path.insert(0,sys.argv[1])
import measure_synthetic_corpus_v2_without_ingestion as base
import measure_v13_40_bounded_ranking_candidates as v40
import measure_v13_44_decomposed_passage_reranking as v44
import measure_v13_46_score_calibrated_global_reranking as v46
p=pathlib.Path(sys.argv[2])
assert p.is_file() and not p.is_symlink() and p.stat().st_size<=32*1024*1024
x=json.loads(p.read_text(encoding="utf-8"))
assert x["artifact_kind"]=="ishikawa_v13_46_score_calibrated_global_reranking_experiment"
assert x["schema_version"]==1 and x["corpus_identity"]=="synthetic-corpus-v3"
assert x["measurement_class"]=="evaluation_only_no_promotion"
assert x["source_sha256"]=={
 "v13_44_observation":sys.argv[3],"normalized_corpus":sys.argv[4],
 "retrieval_truth":sys.argv[5],"accepted_v6_chunks":sys.argv[6],
}
assert x["profiles"]=={
 "chunk_profile_id":sys.argv[7],"retrieval_profile_id":sys.argv[8],
}
experiment=x["experiment"]
assert experiment["variant_order"]==list(v46.VARIANT_ORDER)
assert experiment["variant_configs"]==v46.CONFIG_BY_NAME
assert experiment["feature_order"]==list(v46.FEATURES)
assert experiment["body_mrr_gate"]=="0.89"
assert experiment["body_coverage_gate"]=="120/120"
assert experiment["candidate_pool"]=="unchanged_v13_44_top_20"
assert experiment["learned_reranker"] is False
assert x["candidate_inventory"]=={
 "atomic":786,"documents":30,"passage_total":943,"representatives":157,
}
assert x["case_inventory"]=={"body":120,"relationship":30,"header":30,"total":180}
assert re.fullmatch(r"[0-9a-f]{64}",x["runtime_identity_digest"])
assert math.isfinite(float(x["latency_ms"]["score_calibration_and_measurement"]))
assert x["promotion_authorized"] is False
assert x["boundaries"]=={
 "accepted_database_contact":False,"accepted_database_write":False,
 "black_corpus_access":False,"corpus_ingestion":False,"corpus_v3_changed":False,
 "gemma_contact":False,"nomic_contact":False,"postgresql_contact":False,
 "production_profile_changed":False,"question_text_retained":False,
 "retained_runtime_flat_file_index":False,"source_text_retained":False,
 "structural_path_text_retained":False,"vectors_retained":False,
}
names=[v46.REFERENCE_VARIANT,*v46.VARIANT_ORDER]
assert set(x["variants"])==set(names) and len(x["variants"])==6
reference=x["variants"][v46.REFERENCE_VARIANT]
assert reference["metrics"]["body"]["mrr_at_20"]=="0.823546"
assert reference["metrics"]["body"]["relevant_at_20"]==120
for name in v46.VARIANT_ORDER:
 candidate=x["variants"][name]
 selections=candidate["results"]["selection"]
 expansions=candidate["results"]["expanded_atomic_diagnostic"]
 assert len(selections)==len(expansions)==180
 assert len({item["case_id"] for item in selections})==180
 for item in selections:
  assert "question" not in item and re.fullmatch(r"[0-9a-f]{64}",item["query_sha256"])
  assert len(item["fused"])<=20
  assert item["score_calibration_source"]==v46.SOURCE_VARIANT
  if item["family"]=="body":
   assert item["score_calibration_config"]==v46.CONFIG_BY_NAME[name]
  else:
   assert item["score_calibration_config"] is None
 for family in ("body","relationship","header"):
  assert candidate["metrics"][family]==base.aggregate(
   [item for item in selections if item["family"]==family]
  )
 assert candidate["metrics"]["overall"]==base.aggregate(selections)
 matched=sum(item["matched_evidence_count"] for item in expansions)
 required=sum(item["required_evidence_count"] for item in expansions)
 assert candidate["authoritative_expansion"]=={
  "matched_evidence":matched,"required_evidence":required,"complete":matched==required,
 }
 assert candidate["gate"]==v40.gate_for(candidate["metrics"],matched,required)
 movement=candidate["rank_movement"]
 assert sum(movement[key] for key in ("improved","unchanged","regressed"))==120
qualified=[name for name in v46.VARIANT_ORDER if x["variants"][name]["gate"]["status"]=="qualified"]
selected=max(qualified,key=lambda name:v46.selection_key(name,x["variants"][name])) if qualified else None
assert qualified==[
 "raw_l1_v3_fc1_d1_h010","rrf2_v3_fl1_fc1_d1_h010","raw_l1_v3_fc1_d1_h025",
]
assert selected=="raw_l1_v3_fc1_d1_h010"
assert x["qualified_candidates"]==qualified and x["selected_candidate"]==selected
assert x["selection_status"]=="qualified_for_separate_implementation"
assert x["variants"][selected]["metrics"]["body"]=={
 "case_count":120,"mrr_at_20":"0.895450","mrr_fraction_numerator":4231,
 "mrr_fraction_denominator":4725,"relevant_at_5":117,"relevant_at_20":120,
 "required_evidence_matched_at_20":120,"required_evidence_total":120,
}
for forbidden in ("question","retrieval_text","content_text","structural_path"):
 def contains(value):
  if isinstance(value,dict):
   return forbidden in value or any(contains(item) for item in value.values())
  if isinstance(value,list): return any(contains(item) for item in value)
  return False
 assert not contains(x), forbidden
for name in names:
 body=x["variants"][name]["metrics"]["body"]
 movement=x["variants"][name].get("rank_movement")
 movement_text="reference" if movement is None else f"{movement['improved']}/{movement['unchanged']}/{movement['regressed']}"
 print(f"variant={name};body_mrr_at_20={body['mrr_at_20']};body_relevant_at_5={body['relevant_at_5']}/120;body_relevant_at_20={body['relevant_at_20']}/120;movement_i_u_r={movement_text};gate={x['variants'][name]['gate']['status']}")
print(f"selection_status={x['selection_status']};selected_candidate={selected};promotion_authorized=false")
print("observation_validation=pass")
PY
while IFS= read -r line; do emit "$line"; done <"$work_root/validation-summary.txt"
grep -Fxq 'observation_validation=pass' "$work_root/validation-summary.txt" \
  || block observation_validation_marker_absent
observation_sha256="$(sha256sum "$observation_candidate" | awk '{print $1}')"
observation_artifact="$ARTIFACT_ROOT/v13_46_score_calibrated_global_reranking_${timestamp}.json"
[[ ! -e "$observation_artifact" && ! -L "$observation_artifact" ]] \
  || block retained_artifact_path_exists
mv -- "$observation_candidate" "$observation_artifact"
emit "milestone=score_calibrated_global_reranking;state=pass;observation_sha256=$observation_sha256"
emit "observation_artifact=$observation_artifact;observation_artifact_sha256=$observation_sha256"
emit 'retained_question_text=false;retained_source_text=false;retained_structural_path_text=false;retained_vectors=false;credentials_retained=false'
emit 'service_contact=false;database_contact=false;model_contact=false;corpus_ingestion=false;production_profile_changed=false'
emit 'next_gate=freeze_selected_v13_46_candidate_then_implement_and_qualify_application'
remove_work_root
trap - EXIT HUP INT TERM
report_sha256="$(sha256sum "$report_path" | awk '{print $1}')"
printf 'local_report=%s;local_report_sha256=%s\n' "$report_path" "$report_sha256"
printf '\nSCRIPT RESULT\nscript_199_v13_46_score_calibrated_global_reranking=pass\n'
