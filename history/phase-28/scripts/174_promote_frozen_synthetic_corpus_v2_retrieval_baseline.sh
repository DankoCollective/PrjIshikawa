#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Apply frozen decision V13-31 to the retained Script 173 evidence and
#   promote the best qualifying variant as the immutable synthetic-corpus-v2
#   retrieval optimization baseline.
#
# Boundaries:
#   Local checksum-bound evidence only. No database, model, credential,
#   service, corpus, truth, package, accepted-release, or production-profile
#   change. This promotion authorizes subsequent optimization measurement only.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/174_promote_frozen_synthetic_corpus_v2_retrieval_baseline.sh --run

usage() {
  sed -n '3,16p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Retain the checksum-bound optimization baseline receipt.' \
    '  --validate-only Validate inputs and reproduce the receipt without retention.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly SCRIPT_173_REPORT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-section-page-experiment/section_page_candidate_experiment_20261022T233308Z_6XRxP3.txt"
readonly PUBLICATION_RECEIPT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-isolated-publication/isolated_synthetic_corpus_v2_publication_20261022T204745Z.json"
readonly RETAINED_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-isolated-publication/retained-derived-artifacts-20261022T204745Z"
readonly PROMOTION_BUNDLE="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-promotion/synthetic_corpus_v2_promotion_candidate_20261022T201026Z"
readonly DESIGN="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-section-page-design/section_page_experiment_design_20261022T214310Z_irpXet.json"
readonly OBSERVATION="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-section-page-experiment/section_page_candidate_experiment_20261022T233308Z_6XRxP3.json"
readonly REPRESENTATIVES="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-section-page-experiment/section_page_representatives_20261022T233308Z_6XRxP3.json"
readonly REPRESENTATIVE_EMBEDDINGS="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-section-page-experiment/section_page_representative_embeddings_20261022T233308Z_6XRxP3.json"
readonly BODY_TRUTH="$PHASE_ROOT/reference/ishikawa-synthetic-corpus-v2-body-mrr-cases.json"
readonly HEADER_TRUTH="$PHASE_ROOT/reference/ishikawa-synthetic-corpus-v2-header-cases.json"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-synthetic-corpus-v2-retrieval-baseline-promotion"
readonly ARTIFACT_ROOT="$REPO_ROOT/local/artifacts/ishikawa/synthetic-corpus-v2-retrieval-baseline-promotion"

readonly DECISIONS_SHA256='8b0ce284f90b661a5f48acd275e375b69292fa4035d93e42c2ca7b2b3c9c1013'
readonly SCRIPT_173_REPORT_SHA256='16cebe6a399cb42a760f51dd9588f1801709eff689f39f32c6961794025e9c88'
readonly PUBLICATION_RECEIPT_SHA256='e06a7b1affc96b0c0acf625084b280a9689e8e5ed0153b773bc14227d0975a12'
readonly RETAINED_MANIFEST_SHA256='fe7c37741637437539ddec542325bb9506141225414f650b81d3895f7934092b'
readonly PROMOTION_MANIFEST_SHA256='614c4ce64597aeed7d0d03da8dcbef0d59db052dbd3c56092a33e86fd40d42f5'
readonly DESIGN_SHA256='d6c282571cdefcf0f24945be97a3d5be32f25ced6382dfcb204c89b3d41dc55a'
readonly OBSERVATION_SHA256='d1cdc02f54a49a1c5e110efca9ec093991f00c01ad9268d21045d304240017f3'
readonly REPRESENTATIVES_SHA256='3554061e9a818af0dd948d3112bf9b48196cf6ed4c67db61d4a3b564eb1ae004'
readonly REPRESENTATIVE_EMBEDDINGS_SHA256='13b01e159af4db91cfab3aac601254800ce97313341a8d3fbb6efba606496684'
readonly BODY_TRUTH_SHA256='47882a93996ef1d8331606c173c85f2076e457c989c9ab3cd6bad31d5ce5613e'
readonly HEADER_TRUTH_SHA256='a873a61b59de0a8ea082c3fc0c987ab9cf7b97d79ed843832be354af8eae6e2c'
readonly ACCEPTED_BODY_MRR='0.890000'
readonly SELECTED_VARIANT='section_page_duplicate_canonical'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      printf 'reason=argument_invalid\n\nSCRIPT RESULT\nscript_174_frozen_synthetic_corpus_v2_retrieval_baseline_promotion=blocked\n' >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'reason=mode_invalid\n\nSCRIPT RESULT\nscript_174_frozen_synthetic_corpus_v2_retrieval_baseline_promotion=blocked\n' >&2
  exit 2
}

for command_name in awk basename bash date dirname grep hostname mkdir mktemp \
  python3 rm sed sha256sum tee; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'reason=local_command_missing;command=%s\n\nSCRIPT RESULT\nscript_174_frozen_synthetic_corpus_v2_retrieval_baseline_promotion=blocked\n' \
      "$command_name" >&2
    exit 2
  }
done

check_file() {
  local path="$1" expected_sha256="$2" label="$3"
  local actual_sha256=''
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] || {
    printf 'reason=%s_unsafe\n\nSCRIPT RESULT\nscript_174_frozen_synthetic_corpus_v2_retrieval_baseline_promotion=blocked\n' \
      "$label" >&2
    exit 2
  }
  actual_sha256="$(sha256sum "$path" | awk '{print $1}')" || {
    printf 'reason=%s_checksum_read_failed\n\nSCRIPT RESULT\nscript_174_frozen_synthetic_corpus_v2_retrieval_baseline_promotion=blocked\n' \
      "$label" >&2
    exit 2
  }
  [[ "$actual_sha256" == "$expected_sha256" ]] || {
    printf 'reason=%s_identity_changed\n\nSCRIPT RESULT\nscript_174_frozen_synthetic_corpus_v2_retrieval_baseline_promotion=blocked\n' \
      "$label" >&2
    exit 2
  }
}

verify_sidecar() {
  local artifact_path="$1" label="$2"
  local artifact_directory artifact_name
  artifact_directory="$(dirname -- "$artifact_path")"
  artifact_name="$(basename -- "$artifact_path")"
  [[ -f "$artifact_path.sha256" && ! -L "$artifact_path.sha256" ]] || {
    printf 'reason=%s_checksum_manifest_unsafe\n\nSCRIPT RESULT\nscript_174_frozen_synthetic_corpus_v2_retrieval_baseline_promotion=blocked\n' \
      "$label" >&2
    exit 2
  }
  (cd -- "$artifact_directory" && sha256sum --quiet -c "$artifact_name.sha256") || {
    printf 'reason=%s_checksum_manifest_failed\n\nSCRIPT RESULT\nscript_174_frozen_synthetic_corpus_v2_retrieval_baseline_promotion=blocked\n' \
      "$label" >&2
    exit 2
  }
}

check_file "$DECISIONS" "$DECISIONS_SHA256" frozen_decisions
check_file "$SCRIPT_173_REPORT" "$SCRIPT_173_REPORT_SHA256" script_173_report
check_file "$PUBLICATION_RECEIPT" "$PUBLICATION_RECEIPT_SHA256" publication_receipt
check_file "$RETAINED_ROOT/SHA256SUMS" "$RETAINED_MANIFEST_SHA256" retained_manifest
check_file "$PROMOTION_BUNDLE/SHA256SUMS" "$PROMOTION_MANIFEST_SHA256" corpus_promotion_manifest
check_file "$DESIGN" "$DESIGN_SHA256" section_page_design
check_file "$OBSERVATION" "$OBSERVATION_SHA256" section_page_observation
check_file "$REPRESENTATIVES" "$REPRESENTATIVES_SHA256" section_page_representatives
check_file "$REPRESENTATIVE_EMBEDDINGS" "$REPRESENTATIVE_EMBEDDINGS_SHA256" representative_embeddings
check_file "$BODY_TRUTH" "$BODY_TRUTH_SHA256" body_truth
check_file "$HEADER_TRUTH" "$HEADER_TRUTH_SHA256" header_truth

verify_sidecar "$PUBLICATION_RECEIPT" publication_receipt
verify_sidecar "$DESIGN" section_page_design
verify_sidecar "$OBSERVATION" section_page_observation
verify_sidecar "$REPRESENTATIVES" section_page_representatives
verify_sidecar "$REPRESENTATIVE_EMBEDDINGS" representative_embeddings
(cd -- "$RETAINED_ROOT" && sha256sum --quiet -c SHA256SUMS) || {
  printf 'reason=retained_artifact_manifest_failed\n\nSCRIPT RESULT\nscript_174_frozen_synthetic_corpus_v2_retrieval_baseline_promotion=blocked\n' >&2
  exit 2
}
(cd -- "$PROMOTION_BUNDLE" && sha256sum --quiet -c SHA256SUMS) || {
  printf 'reason=corpus_promotion_manifest_failed\n\nSCRIPT RESULT\nscript_174_frozen_synthetic_corpus_v2_retrieval_baseline_promotion=blocked\n' >&2
  exit 2
}
grep -Fq '| `V13-31` ' "$DECISIONS" || {
  printf 'reason=decision_v13_31_not_frozen\n\nSCRIPT RESULT\nscript_174_frozen_synthetic_corpus_v2_retrieval_baseline_promotion=blocked\n' >&2
  exit 1
}
grep -Fxq 'script_173_bounded_section_page_candidate_experiment=pass' \
  "$SCRIPT_173_REPORT" || {
  printf 'reason=script_173_not_clean\n\nSCRIPT RESULT\nscript_174_frozen_synthetic_corpus_v2_retrieval_baseline_promotion=blocked\n' >&2
  exit 1
}
grep -Fxq 'eligible_variants=none' "$SCRIPT_173_REPORT" || {
  printf 'reason=script_173_historical_gate_state_changed\n\nSCRIPT RESULT\nscript_174_frozen_synthetic_corpus_v2_retrieval_baseline_promotion=blocked\n' >&2
  exit 1
}
grep -Fxq 'database_write=false;accepted_database_contact=false;gemma_contact=false;corpus_changed=false;profile_changed=false;candidate_promoted=false;credentials_retained=false' \
  "$SCRIPT_173_REPORT" || {
  printf 'reason=script_173_boundary_evidence_missing\n\nSCRIPT RESULT\nscript_174_frozen_synthetic_corpus_v2_retrieval_baseline_promotion=blocked\n' >&2
  exit 1
}

build_receipt() {
  local output_path="$1"
  PYTHONDONTWRITEBYTECODE=1 python3 -B - \
    "$PUBLICATION_RECEIPT" "$DESIGN" "$OBSERVATION" "$output_path" \
    "$DECISIONS_SHA256" "$SCRIPT_173_REPORT_SHA256" \
    "$PUBLICATION_RECEIPT_SHA256" "$RETAINED_MANIFEST_SHA256" \
    "$PROMOTION_MANIFEST_SHA256" "$DESIGN_SHA256" "$OBSERVATION_SHA256" \
    "$REPRESENTATIVES_SHA256" "$REPRESENTATIVE_EMBEDDINGS_SHA256" \
    "$BODY_TRUTH_SHA256" "$HEADER_TRUTH_SHA256" <<'PY'
import json
import pathlib
import sys
from decimal import Decimal

(
    publication_path,
    design_path,
    observation_path,
    output_path,
    decisions_sha256,
    report_sha256,
    publication_sha256,
    retained_manifest_sha256,
    promotion_manifest_sha256,
    design_sha256,
    observation_sha256,
    representatives_sha256,
    representative_embeddings_sha256,
    body_truth_sha256,
    header_truth_sha256,
) = sys.argv[1:]

publication = json.loads(pathlib.Path(publication_path).read_text(encoding="utf-8"))
design = json.loads(pathlib.Path(design_path).read_text(encoding="utf-8"))
observation = json.loads(pathlib.Path(observation_path).read_text(encoding="utf-8"))

assert publication["schema"] == "ishikawa.synthetic-corpus-v2-isolated-publication.v1"
assert publication["status"] == "published_isolated"
assert publication["published"]["corpus_identity"] == "synthetic-corpus-v2"
assert publication["published"]["documents"] == 6
assert publication["published"]["pages"] == 26
assert publication["published"]["chunks"] == 139
assert publication["published"]["embeddings"] == 139
assert publication["published"]["retained_artifact_checksum_manifest_sha256"] == retained_manifest_sha256

assert design["artifact_kind"] == "ishikawa_published_synthetic_corpus_v2_section_page_experiment_design"
assert design["schema_version"] == 1
assert design["eligibility_gate"]["body_mrr_at_20"] == ">0.91"
assert design["eligibility_gate"]["automatic_promotion"] is False

assert observation["artifact_kind"] == "ishikawa_published_v2_section_page_candidate_experiment"
assert observation["schema_version"] == 1
assert observation["accepted_atomic_baseline_exactly_replayed"] is True
assert observation["deterministic_replay"] is True
assert observation["eligible_variants"] == []
assert observation["source_sha256"]["design"] == design_sha256
assert observation["source_sha256"]["representatives"] == representatives_sha256
assert observation["source_sha256"]["representative_embeddings"] == representative_embeddings_sha256
assert observation["source_sha256"]["body_truth"] == body_truth_sha256
assert observation["source_sha256"]["header_truth"] == header_truth_sha256
assert observation["source_sha256"]["promotion_manifest"] == promotion_manifest_sha256
assert observation["source_sha256"]["atomic_chunks"] == publication["published"]["chunk_artifact_sha256"]
assert observation["source_sha256"]["atomic_embeddings"] == publication["published"]["embedding_artifact_sha256"]
assert observation["source_sha256"]["normalized"] == publication["published"]["normalized_artifact_sha256"]
assert observation["inventory"] == {
    "atomic_candidates": 139,
    "cases": 68,
    "maximum_pre_collapse_candidates": 168,
    "query_embedding_tokens": 1204,
    "section_page_representatives": 29,
}
assert all(observation["boundaries"][key] is False for key in (
    "accepted_database_contact", "candidate_promoted", "corpus_changed",
    "database_tables_read", "database_write", "gemma_contact",
    "production_profile_changed", "truth_changed",
))

minimum_mrr = Decimal("0.890000")

def qualifies(variant):
    body = variant["body_metrics"]
    header = variant["header_metrics"]
    return (
        Decimal(body["mrr_at_20"]) >= minimum_mrr
        and body["relevant_at_20"] == 60
        and body["required_evidence_matched_at_20"] == 60
        and body["required_evidence_total"] == 60
        and header["mrr_at_20"] == "1.000000"
        and header["relevant_at_5"] == 8
        and header["required_evidence_matched_at_20"] == 11
        and header["required_evidence_total"] == 11
    )

qualifying = [variant for variant in observation["variants"] if qualifies(variant)]
assert [variant["name"] for variant in qualifying] == [
    "section_page", "section_page_duplicate_canonical"
]
selected = max(
    qualifying,
    key=lambda variant: (
        Decimal(variant["body_metrics"]["mrr_at_20"]),
        variant["body_metrics"]["relevant_at_5"],
        -Decimal(variant["latency_ms"]["p95"]),
    ),
)
assert selected["name"] == "section_page_duplicate_canonical"
assert selected["body_metrics"]["mrr_at_20"] == "0.903333"
assert selected["body_metrics"]["relevant_at_5"] == 60
assert selected["body_metrics"]["relevant_at_20"] == 60

configuration_by_name = {item["name"]: item for item in design["variants"]}
receipt = {
    "accepted_gate": {
        "body_mrr_at_20": ">=0.890000",
        "body_required_evidence_at_20": "60/60",
        "deterministic_replay_required": True,
        "header_mrr_at_20": "1.000000",
        "header_relevant_at_5": "8/8",
        "header_required_evidence_at_20": "11/11",
    },
    "artifact_kind": "ishikawa_synthetic_corpus_v2_retrieval_optimization_baseline",
    "boundaries": {
        "accepted_release_changed": False,
        "black_corpus_access": False,
        "corpus_v1_changed": False,
        "corpus_v2_changed": False,
        "database_contact": False,
        "database_write": False,
        "deployment_package_changed": False,
        "model_contact": False,
        "org_lab_changed": False,
        "production_profile_changed": False,
        "truth_changed": False,
    },
    "corpus": {
        "atomic_candidates": 139,
        "documents": 6,
        "embeddings": 139,
        "identity": "synthetic-corpus-v2",
        "maximum_pre_collapse_candidates": 168,
        "pages": 26,
        "section_page_representatives": 29,
        "state": "published_isolated_frozen_for_optimization",
    },
    "decision": {
        "decision_list_sha256": decisions_sha256,
        "id": "V13-31",
    },
    "frozen_inputs": {
        "body_truth_sha256": body_truth_sha256,
        "corpus_promotion_manifest_sha256": promotion_manifest_sha256,
        "isolated_publication_receipt_sha256": publication_sha256,
        "published_atomic_chunks_sha256": observation["source_sha256"]["atomic_chunks"],
        "published_atomic_embeddings_sha256": observation["source_sha256"]["atomic_embeddings"],
        "published_normalized_sha256": observation["source_sha256"]["normalized"],
        "representative_embeddings_sha256": representative_embeddings_sha256,
        "retained_artifact_manifest_sha256": retained_manifest_sha256,
        "script_173_report_sha256": report_sha256,
        "section_page_design_sha256": design_sha256,
        "section_page_observation_sha256": observation_sha256,
        "section_page_representatives_sha256": representatives_sha256,
        "header_truth_sha256": header_truth_sha256,
    },
    "next_gate": "optimize_frozen_synthetic_corpus_v2_retrieval_baseline",
    "qualifying_variants": [variant["name"] for variant in qualifying],
    "retrieval_profile": observation["frozen_profile"],
    "schema_version": 1,
    "selected_variant": {
        "configuration": configuration_by_name[selected["name"]],
        "metrics": {
            "body": selected["body_metrics"],
            "header": selected["header_metrics"],
            "latency_diagnostic": selected["latency_ms"],
        },
        "name": selected["name"],
    },
    "selection_rule": [
        "highest_body_mrr_at_20",
        "highest_body_relevant_at_5",
        "lowest_diagnostic_warm_p95_ms",
    ],
    "state": "promoted_frozen_optimization_baseline",
    "truth_usage": observation["truth_usage"],
}
pathlib.Path(output_path).write_text(
    json.dumps(receipt, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY
}

validate_receipt() {
  local path="$1"
  PYTHONDONTWRITEBYTECODE=1 python3 -B - "$path" <<'PY'
import json
import pathlib
import sys

value = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert value["artifact_kind"] == "ishikawa_synthetic_corpus_v2_retrieval_optimization_baseline"
assert value["schema_version"] == 1
assert value["state"] == "promoted_frozen_optimization_baseline"
assert value["decision"]["id"] == "V13-31"
assert value["accepted_gate"]["body_mrr_at_20"] == ">=0.890000"
assert value["qualifying_variants"] == [
    "section_page", "section_page_duplicate_canonical"
]
assert value["selected_variant"]["name"] == "section_page_duplicate_canonical"
assert value["selected_variant"]["configuration"] == {
    "document_local_duplicate_canonicalization": True,
    "name": "section_page_duplicate_canonical",
    "section_page_representatives": True,
}
assert value["selected_variant"]["metrics"]["body"]["mrr_at_20"] == "0.903333"
assert value["selected_variant"]["metrics"]["body"]["relevant_at_5"] == 60
assert value["selected_variant"]["metrics"]["body"]["relevant_at_20"] == 60
assert value["selected_variant"]["metrics"]["header"]["mrr_at_20"] == "1.000000"
assert value["corpus"]["documents"] == 6
assert value["corpus"]["pages"] == 26
assert value["corpus"]["atomic_candidates"] == 139
assert value["corpus"]["section_page_representatives"] == 29
assert value["next_gate"] == "optimize_frozen_synthetic_corpus_v2_retrieval_baseline"
assert not any(value["boundaries"].values())
assert value["truth_usage"] == {
    "black_corpus_application": False,
    "corpus_ingestion": False,
    "evaluation_only": True,
    "generation_context": False,
}
PY
}

bash -n "${BASH_SOURCE[0]}"
validation_root="$(mktemp -d /tmp/ishikawa-script-174-validation.XXXXXX)"
trap 'rm -rf -- "$validation_root"' EXIT
build_receipt "$validation_root/receipt.json"
validate_receipt "$validation_root/receipt.json"
validation_receipt_sha256="$(sha256sum "$validation_root/receipt.json" | awk '{print $1}')"
rm -rf -- "$validation_root"
trap - EXIT

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_frozen_synthetic_corpus_v2_retrieval_baseline_promotion' \
    "script_sha256=$script_sha256;decision=V13-31;decisions_sha256=$DECISIONS_SHA256" \
    "accepted_body_mrr_at_20=>=$ACCEPTED_BODY_MRR;qualifying_variants=section_page,section_page_duplicate_canonical" \
    "selected_variant=$SELECTED_VARIANT;selected_body_mrr_at_20=0.903333;body_relevant_at_5=60/60;body_relevant_at_20=60/60" \
    "validation_receipt_sha256=$validation_receipt_sha256" \
    'database_contact=false;model_contact=false;credential_read=false;corpus_changed=false;truth_changed=false;production_profile_changed=false' \
    '' \
    'SCRIPT RESULT' \
    'script_174_frozen_synthetic_corpus_v2_retrieval_baseline_promotion=pass'
  exit 0
fi

umask 077
mkdir -p -- "$REPORT_ROOT" "$ARTIFACT_ROOT" || {
  printf 'reason=local_output_root_creation_failed\n\nSCRIPT RESULT\nscript_174_frozen_synthetic_corpus_v2_retrieval_baseline_promotion=blocked\n' >&2
  exit 2
}
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" && -w "$REPORT_ROOT" ]] || {
  printf 'reason=report_root_unsafe\n\nSCRIPT RESULT\nscript_174_frozen_synthetic_corpus_v2_retrieval_baseline_promotion=blocked\n' >&2
  exit 2
}
[[ -d "$ARTIFACT_ROOT" && ! -L "$ARTIFACT_ROOT" && -w "$ARTIFACT_ROOT" ]] || {
  printf 'reason=artifact_root_unsafe\n\nSCRIPT RESULT\nscript_174_frozen_synthetic_corpus_v2_retrieval_baseline_promotion=blocked\n' >&2
  exit 2
}

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/retrieval_baseline_promotion_${timestamp}_XXXXXX.txt")"
work_root="$(mktemp -d /tmp/ishikawa-script-174.XXXXXX)"
suffix="${report_path##*_}"; suffix="${suffix%.txt}"
artifact_path="$ARTIFACT_ROOT/retrieval_optimization_baseline_${timestamp}_${suffix}.json"
artifact_checksum_path="$artifact_path.sha256"
failure_reason=''
readonly MAIN_BASHPID="$BASHPID"

emit() {
  if ! printf '%s\n' "$1" | tee -a "$report_path"; then
    failure_reason='report_write_failed'
    exit 1
  fi
}

block() {
  failure_reason="$1"
  exit 1
}

cleanup() {
  local initial_status="$?" result='blocked'
  trap - ERR EXIT HUP INT TERM
  if [[ "$BASHPID" != "$MAIN_BASHPID" ]]; then
    exit "$initial_status"
  fi
  set +e
  [[ "$work_root" == /tmp/ishikawa-script-174.* ]] && rm -rf -- "$work_root"
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
    printf 'script_174_frozen_synthetic_corpus_v2_retrieval_baseline_promotion=%s\n' "$result"
  } >>"$report_path"
  printf 'local_report=%s\n' "$report_path"
  printf 'local_report_sha256=%s\n' "$(sha256sum "$report_path" | awk '{print $1}')"
  printf '\nSCRIPT RESULT\n'
  [[ "$result" == pass ]] || printf 'reason=%s\n' "$failure_reason"
  printf 'script_174_frozen_synthetic_corpus_v2_retrieval_baseline_promotion=%s\n' "$result"
  exit "$initial_status"
}
trap cleanup EXIT
trap 'failure_reason="interrupted_hup"; exit 129' HUP
trap 'failure_reason="interrupted_int"; exit 130' INT
trap 'failure_reason="interrupted_term"; exit 143' TERM

emit 'purpose=promote_frozen_synthetic_corpus_v2_retrieval_optimization_baseline'
emit "started_utc=$timestamp;hostname=$(hostname -s);script_sha256=$script_sha256;decision=V13-31"
emit 'authorized_actions=validate_checksum_bound_published_synthetic_corpus_v2_evidence_apply_frozen_mrr_gate_select_best_qualifying_variant_retain_local_promotion_receipt'
emit 'non_actions=no_database_contact_no_model_contact_no_credential_read_no_corpus_change_no_truth_change_no_service_change_no_package_change_no_accepted_release_change_no_production_profile_change_no_org_lab_change'
emit "milestone=gate_application;state=start;body_mrr_at_20_minimum=$ACCEPTED_BODY_MRR;comparison=greater_than_or_equal"

build_receipt "$work_root/receipt.json" || block baseline_receipt_build_failed
validate_receipt "$work_root/receipt.json" || block baseline_receipt_validation_failed
[[ "$(sha256sum "$work_root/receipt.json" | awk '{print $1}')" == "$validation_receipt_sha256" ]] \
  || block baseline_receipt_not_repeatable
[[ ! -e "$artifact_path" && ! -L "$artifact_path" ]] \
  || block baseline_receipt_destination_exists
if ! tee -- "$artifact_path" <"$work_root/receipt.json" >/dev/null; then
  block baseline_receipt_retention_failed
fi
artifact_sha256="$(sha256sum "$artifact_path" | awk '{print $1}')" \
  || block baseline_receipt_checksum_read_failed
[[ "$artifact_sha256" == "$validation_receipt_sha256" ]] \
  || block baseline_receipt_identity_changed_after_retention
if ! printf '%s  %s\n' "$artifact_sha256" "$(basename -- "$artifact_path")" \
    >"$artifact_checksum_path"; then
  block baseline_receipt_checksum_manifest_write_failed
fi
if ! (trap - EXIT HUP INT TERM; cd -- "$ARTIFACT_ROOT" \
    && sha256sum --quiet -c "$(basename -- "$artifact_checksum_path")"); then
  block baseline_receipt_checksum_manifest_failed
fi

emit 'milestone=gate_application;state=pass;qualifying_variants=2;selection_rule=highest_mrr_then_top5_then_lower_p95'
emit 'qualifying_variant=section_page;body_mrr_at_20=0.890833;body_relevant_at_5=60/60;body_relevant_at_20=60/60'
emit 'qualifying_variant=section_page_duplicate_canonical;body_mrr_at_20=0.903333;body_relevant_at_5=60/60;body_relevant_at_20=60/60'
emit 'milestone=baseline_promotion;state=pass;selected_variant=section_page_duplicate_canonical;selected_body_mrr_at_20=0.903333;corpus=synthetic-corpus-v2;documents=6;pages=26'
emit "baseline_receipt=$artifact_path;baseline_receipt_sha256=$artifact_sha256"
emit 'database_contact=false;model_contact=false;credential_read=false;corpus_changed=false;truth_changed=false;production_profile_changed=false;accepted_release_changed=false;deployment_package_changed=false;org_lab_changed=false'
emit 'next_gate=optimize_frozen_synthetic_corpus_v2_retrieval_baseline'

