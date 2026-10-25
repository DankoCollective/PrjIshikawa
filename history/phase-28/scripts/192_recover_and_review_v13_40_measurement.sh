#!/usr/bin/env bash
set -Eeuo pipefail

# Purpose:
#   Recover and deeply validate the retained V13-40 observation after Script
#   191's canonical-order validator defect, without repeating model work.
#
# Boundaries:
#   Reads only checksum-bound synthetic evaluation evidence. Does not contact
#   PostgreSQL, Nomic, Gemma, an accepted service, or the black corpus. Does not
#   ingest, promote, publish, alter a profile, or assemble a release.
#
# Usage:
#   bash ./phase-28-apisachi-tokuli/scripts/192_recover_and_review_v13_40_measurement.sh --run

usage() {
  sed -n '3,15p' "${BASH_SOURCE[0]}"
  printf '%s\n' \
    'Options:' \
    '  --run           Validate and classify the retained V13-40 observation.' \
    '  --validate-only Validate script inputs and contracts without writing a report.'
}

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PHASE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
readonly REPO_ROOT="$(cd -- "$PHASE_ROOT/.." && pwd -P)"
readonly DECISIONS="$PHASE_ROOT/docs/ISHIKAWA_V1_3_CHANGE_DECISIONS.md"
readonly EVALUATOR="$SCRIPT_DIR/measure_v13_40_bounded_ranking_candidates.py"
readonly BASE_EVALUATOR="$SCRIPT_DIR/measure_synthetic_corpus_v2_without_ingestion.py"
readonly SCRIPT_191="$SCRIPT_DIR/191_measure_v13_40_bounded_ranking_candidates.sh"
readonly FIRST_REPORT="$REPO_ROOT/local/reports/ishikawa-v13-40-bounded-ranking/v13_40_bounded_ranking_20261023T055903Z_Z5mFHg.txt"
readonly SECOND_REPORT="$REPO_ROOT/local/reports/ishikawa-v13-40-bounded-ranking/v13_40_bounded_ranking_20261023T060501Z_8533gt.txt"
readonly OBSERVATION="$REPO_ROOT/local/artifacts/ishikawa/v13-40-bounded-ranking/blocked_v13_40_bounded_ranking_20261023T060501Z.json"
readonly REPORT_ROOT="$REPO_ROOT/local/reports/ishikawa-v13-40-bounded-ranking-review"
readonly EXPECTED_FIRST_REPORT_SHA256='f76b3afdbcdbb0147fb672f51f1c7d8679f12357c8f0cfa6faf657b61dd0ec9d'
readonly EXPECTED_SECOND_REPORT_SHA256='3f7cd10ae4e246e6f8187824419a2c8e7dcf4d64b278e3b02d30224c2366fa51'
readonly EXPECTED_OBSERVATION_SHA256='35eb155e634bf4d97fb66ab704c2e378b8c7085fd2a76c1e8b255d9fede64b95'
readonly EXPECTED_EVALUATOR_SHA256='5c3b43c52db1617be6c089f1ac20afb5a47e2b18c47ada41341c9ee4d0669662'
readonly EXPECTED_SCRIPT_191_SHA256='a9427cd148a20c772418183b27bf517a0ffb7e2b437c3639484426c41aa1f9d1'
readonly EXPECTED_CHUNKS_SHA256='49a67ac067d06b6068878be6530ae4971bddb4a1f687545578bd1ef9254d19e4'
readonly EXPECTED_TRUTH_SHA256='f74302d899d000b9493fecfeca4ffbe2995bb04aabef00bf327061c34c2a18a0'
readonly EXPECTED_RETRIEVAL_PROFILE_ID='cfa9bbc353dc82d3ba74396de40df6ba429b7df2750e7809b92eeefd4a433147'

run_authorized=false
validate_only=false
while (( $# > 0 )); do
  case "$1" in
    --run) run_authorized=true; shift ;;
    --validate-only) validate_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      usage >&2
      printf '\nSCRIPT RESULT\nscript_192_v13_40_measurement_review=blocked\n' >&2
      exit 2
      ;;
  esac
done
[[ "$run_authorized" != "$validate_only" ]] || {
  printf 'reason=exactly_one_mode_required\n\nSCRIPT RESULT\nscript_192_v13_40_measurement_review=blocked\n' >&2
  exit 2
}

for command_name in awk bash date grep mkdir mktemp mv python3 rm sed sha256sum tee; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'reason=missing_command_%s\n\nSCRIPT RESULT\nscript_192_v13_40_measurement_review=blocked\n' \
      "$command_name" >&2
    exit 2
  }
done

check_file() {
  local path="$1" expected_sha256="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -r "$path" ]] || {
    printf 'reason=%s_unsafe\n\nSCRIPT RESULT\nscript_192_v13_40_measurement_review=blocked\n' \
      "$label" >&2
    exit 2
  }
  [[ "$(sha256sum "$path" | awk '{print $1}')" == "$expected_sha256" ]] || {
    printf 'reason=%s_identity_changed\n\nSCRIPT RESULT\nscript_192_v13_40_measurement_review=blocked\n' \
      "$label" >&2
    exit 2
  }
}

check_file "$FIRST_REPORT" "$EXPECTED_FIRST_REPORT_SHA256" first_report
check_file "$SECOND_REPORT" "$EXPECTED_SECOND_REPORT_SHA256" second_report
check_file "$OBSERVATION" "$EXPECTED_OBSERVATION_SHA256" retained_observation
check_file "$EVALUATOR" "$EXPECTED_EVALUATOR_SHA256" evaluator
check_file "$SCRIPT_191" "$EXPECTED_SCRIPT_191_SHA256" corrected_script_191
grep -Fq '| `V13-40` |' "$DECISIONS" || {
  printf 'reason=v13_40_not_frozen\n\nSCRIPT RESULT\nscript_192_v13_40_measurement_review=blocked\n' >&2
  exit 1
}
grep -Fq 'v13_40_bounded_ranking_measurement=pass' "$FIRST_REPORT" || {
  printf 'reason=first_measurement_did_not_complete\n\nSCRIPT RESULT\nscript_192_v13_40_measurement_review=blocked\n' >&2
  exit 1
}
grep -Fq 'v13_40_bounded_ranking_measurement=pass' "$SECOND_REPORT" || {
  printf 'reason=second_measurement_did_not_complete\n\nSCRIPT RESULT\nscript_192_v13_40_measurement_review=blocked\n' >&2
  exit 1
}
grep -Fq 'reason=bounded_ranking_observation_invalid' "$SECOND_REPORT" || {
  printf 'reason=expected_harness_failure_not_present\n\nSCRIPT RESULT\nscript_192_v13_40_measurement_review=blocked\n' >&2
  exit 1
}

bash -n "${BASH_SOURCE[0]}"
PYTHONDONTWRITEBYTECODE=1 python3 -B -c \
  'import pathlib,sys; compile(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")' \
  "$EVALUATOR"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$EVALUATOR" --self-test \
  | grep -Fxq 'v13_40_bounded_ranking_measurement_self_test=pass'

script_sha256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
if [[ "$validate_only" == true ]]; then
  printf '%s\n' \
    'purpose=validate_v13_40_measurement_recovery_and_review' \
    "script_sha256=$script_sha256;observation_sha256=$EXPECTED_OBSERVATION_SHA256" \
    'measurement_runs=2;retained_complete_observations=1;cases=180;variants=5' \
    'model_contact=false;database_contact=false;corpus_ingestion=false;promotion=false' \
    '' \
    'SCRIPT RESULT' \
    'script_192_v13_40_measurement_review=pass'
  exit 0
fi

umask 077
mkdir -p -- "$REPORT_ROOT"
[[ -d "$REPORT_ROOT" && ! -L "$REPORT_ROOT" ]] || {
  printf 'reason=report_directory_unsafe\n\nSCRIPT RESULT\nscript_192_v13_40_measurement_review=blocked\n' >&2
  exit 1
}
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
report_path="$(mktemp "$REPORT_ROOT/v13_40_measurement_review_${timestamp}_XXXXXX.txt")"
review_stdout="$(mktemp /tmp/ishikawa-script-192-review.XXXXXX)"
cleanup() { rm -f -- "$review_stdout"; }
trap cleanup EXIT HUP INT TERM

if ! PYTHONDONTWRITEBYTECODE=1 python3 -B - \
  "$SCRIPT_DIR" "$OBSERVATION" "$FIRST_REPORT" "$SECOND_REPORT" \
  "$EXPECTED_CHUNKS_SHA256" "$EXPECTED_TRUTH_SHA256" \
  "$EXPECTED_RETRIEVAL_PROFILE_ID" >"$review_stdout" <<'PY'
import json
import math
import pathlib
import re
import sys
from fractions import Fraction

sys.path.insert(0, sys.argv[1])
import measure_synthetic_corpus_v2_without_ingestion as base


class ReviewError(RuntimeError):
    pass


def require(condition, reason):
    if not condition:
        raise ReviewError(reason)


def report_metrics(path):
    text = pathlib.Path(path).read_text(encoding="utf-8")
    pattern = re.compile(
        r"^variant=([^;]+);body_mrr_at_20=([^;]+);"
        r"body_relevant_at_5=([0-9]+)/120;body_relevant_at_20=([0-9]+)/120;"
        r"gate=([^;]+);failed_checks=(.+)$",
        re.MULTILINE,
    )
    rows = {
        match.group(1): {
            "mrr": match.group(2),
            "top5": int(match.group(3)),
            "top20": int(match.group(4)),
            "gate": match.group(5),
            "failed": match.group(6),
        }
        for match in pattern.finditer(text)
    }
    require(len(rows) == 5, "report_variant_inventory_invalid")
    require(
        "selection_status=not_met;selected_candidate=none;promotion_authorized=false"
        in text,
        "report_selection_outcome_invalid",
    )
    return rows


try:
    observation_path = pathlib.Path(sys.argv[2])
    require(
        observation_path.is_file()
        and not observation_path.is_symlink()
        and observation_path.stat().st_size <= 16 * 1024 * 1024,
        "observation_file_unsafe",
    )
    source = json.loads(observation_path.read_text(encoding="utf-8"))
    order = [
        "current_identity_both",
        "identity_lexical_passage_vector",
        "passage_only",
        "two_stage_top3",
        "two_stage_top5",
    ]
    require(
        source.get("artifact_kind")
        == "ishikawa_v13_40_bounded_ranking_experiment"
        and source.get("schema_version") == 1
        and source.get("corpus_identity") == "synthetic-corpus-v3"
        and source.get("measurement_class") == "evaluation_only_no_promotion",
        "observation_contract_invalid",
    )
    require(
        source.get("source_sha256")
        == {"chunks": sys.argv[5], "retrieval_truth": sys.argv[6]},
        "source_identity_invalid",
    )
    require(
        source.get("retrieval_profile")
        == {
            "profile_id": sys.argv[7],
            "exact_candidate_depth": 1,
            "lexical_candidate_depth": 20,
            "vector_candidate_depth": 20,
            "fused_candidate_depth": 20,
            "rrf_constant": 60,
            "lane_weights": {"exact": 1, "lexical": 2, "vector": 4},
            "learned_reranker": False,
        },
        "retrieval_profile_invalid",
    )
    require(
        source.get("experiment")
        == {
            "variant_order": order,
            "body_mrr_gate": "0.89",
            "document_affinity": "best_rank_per_lane",
            "document_shortlist_depths": [3, 5],
            "selection_order": [
                "body_mrr_at_20_desc",
                "body_relevant_at_5_desc",
                "declared_variant_order",
            ],
        },
        "experiment_contract_invalid",
    )
    require(
        source.get("candidate_inventory")
        == {"documents": 30, "atomic": 786, "representatives": 157, "total": 943}
        and source.get("case_inventory")
        == {"body": 120, "relationship": 30, "header": 30, "total": 180},
        "inventory_invalid",
    )
    require(set(source.get("variants", {})) == set(order), "variant_inventory_invalid")
    require(
        source.get("boundaries")
        == {
            "accepted_database_contact": False,
            "accepted_database_write": False,
            "black_corpus_access": False,
            "corpus_ingestion": False,
            "corpus_v3_changed": False,
            "gemma_contact": False,
            "nomic_contact": True,
            "private_temporary_postgresql": True,
            "production_profile_changed": False,
            "runtime_flat_file_index": False,
            "question_text_retained": False,
            "query_vectors_retained": False,
            "source_text_retained": False,
        }
        and source.get("promotion_authorized") is False,
        "boundary_invalid",
    )
    require(
        isinstance(source.get("runtime_identity_digest"), str)
        and re.fullmatch(r"[0-9a-f]{64}", source["runtime_identity_digest"]),
        "runtime_identity_invalid",
    )
    require(
        isinstance(source.get("token_usage"), dict)
        and all(type(value) is int and value > 0 for value in source["token_usage"].values()),
        "token_usage_invalid",
    )

    first = report_metrics(sys.argv[3])
    second = report_metrics(sys.argv[4])
    qualified = []
    shared_case_ids = None
    for name in order:
        candidate = source["variants"][name]
        selections = candidate["results"]["selection"]
        expansions = candidate["results"]["expanded_atomic_diagnostic"]
        require(len(selections) == len(expansions) == 180, f"{name}_case_count_invalid")
        case_ids = [item["case_id"] for item in selections]
        require(len(set(case_ids)) == 180, f"{name}_case_identity_invalid")
        require(
            case_ids == [item["case_id"] for item in expansions],
            f"{name}_expansion_case_order_invalid",
        )
        if shared_case_ids is None:
            shared_case_ids = case_ids
        require(case_ids == shared_case_ids, f"{name}_case_order_changed")
        require(
            sum(item["family"] == "body" for item in selections) == 120
            and sum(item["family"] == "relationship" for item in selections) == 30
            and sum(item["family"] == "header" for item in selections) == 30,
            f"{name}_family_inventory_invalid",
        )
        shortlist_limit = 3 if name == "two_stage_top3" else 5 if name == "two_stage_top5" else 0
        for item in selections:
            require("question" not in item, f"{name}_question_text_retained")
            require(
                re.fullmatch(r"[0-9a-f]{64}", item["query_sha256"]) is not None
                and type(item["searchable_candidate_count"]) is int
                and item["searchable_candidate_count"] > 0,
                f"{name}_selection_contract_invalid",
            )
            shortlist = item["document_shortlist"]
            if shortlist_limit:
                require(
                    1 <= len(shortlist) <= shortlist_limit
                    and len(shortlist) == len(set(shortlist))
                    and set(shortlist) <= set(item["permitted_document_refs"]),
                    f"{name}_shortlist_invalid",
                )
            else:
                require(shortlist == [], f"{name}_unexpected_shortlist")
            require(len(item["fused"]) <= 20, f"{name}_fused_depth_invalid")
            for lane_name, records in item["lanes"].items():
                require(lane_name in {"exact", "lexical", "vector"}, f"{name}_lane_invalid")
                require(
                    [record["rank"] for record in records]
                    == list(range(1, len(records) + 1)),
                    f"{name}_{lane_name}_rank_sequence_invalid",
                )
                require(
                    all(math.isfinite(float(record["score"])) for record in records),
                    f"{name}_{lane_name}_score_invalid",
                )
        for family in ("body", "relationship", "header"):
            require(
                candidate["metrics"][family]
                == base.aggregate([item for item in selections if item["family"] == family]),
                f"{name}_{family}_aggregate_invalid",
            )
        require(
            candidate["metrics"]["overall"] == base.aggregate(selections),
            f"{name}_overall_aggregate_invalid",
        )
        matched = sum(item["matched_evidence_count"] for item in expansions)
        required = sum(item["required_evidence_count"] for item in expansions)
        require(
            candidate["authoritative_expansion"]
            == {"matched_evidence": matched, "required_evidence": required, "complete": matched == required},
            f"{name}_expansion_aggregate_invalid",
        )
        body = candidate["metrics"]["body"]
        relationship = candidate["metrics"]["relationship"]
        header = candidate["metrics"]["header"]
        expected_checks = {
            "body_mrr_at_20": Fraction(body["mrr_fraction_numerator"], body["mrr_fraction_denominator"]) >= Fraction(89, 100),
            "body_relevant_at_20": body["relevant_at_20"] == 120,
            "body_required_evidence_at_20": body["required_evidence_matched_at_20"] == body["required_evidence_total"] == 120,
            "relationship_relevant_at_20": relationship["relevant_at_20"] == 30,
            "relationship_required_evidence_at_20": relationship["required_evidence_matched_at_20"] == relationship["required_evidence_total"] == 30,
            "header_mrr_at_20": header["mrr_at_20"] == "1.000000",
            "header_relevant_at_20": header["relevant_at_20"] == 30,
            "header_required_evidence_at_20": header["required_evidence_matched_at_20"] == header["required_evidence_total"] == 30,
            "authoritative_expansion": matched == required == 180,
        }
        failed = [key for key, value in expected_checks.items() if not value]
        require(candidate["gate"]["checks"] == expected_checks, f"{name}_gate_checks_invalid")
        require(candidate["gate"]["failed_checks"] == failed, f"{name}_failed_checks_invalid")
        status = "qualified" if not failed else "not_met"
        require(candidate["gate"]["status"] == status, f"{name}_gate_status_invalid")
        require(
            second[name]
            == {
                "mrr": body["mrr_at_20"],
                "top5": body["relevant_at_5"],
                "top20": body["relevant_at_20"],
                "gate": status,
                "failed": ",".join(failed) if failed else "none",
            },
            f"{name}_report_observation_mismatch",
        )
        if status == "qualified":
            qualified.append(name)
        print(
            f"variant={name};body_mrr_at_20={body['mrr_at_20']};"
            f"body_relevant_at_5={body['relevant_at_5']}/120;"
            f"body_relevant_at_20={body['relevant_at_20']}/120;"
            f"relationship_relevant_at_20={relationship['relevant_at_20']}/30;"
            f"header_relevant_at_20={header['relevant_at_20']}/30;"
            f"authoritative_expansion={matched}/180;gate={status};"
            f"failed_checks={','.join(failed) if failed else 'none'}"
        )

    require(source["qualified_candidates"] == qualified, "qualified_candidate_list_invalid")
    def selection_key(name):
        body = source["variants"][name]["metrics"]["body"]
        return (
            Fraction(body["mrr_fraction_numerator"], body["mrr_fraction_denominator"]),
            body["relevant_at_5"],
            -order.index(name),
        )
    selected = max(qualified, key=selection_key) if qualified else None
    require(source["selected_candidate"] == selected, "selected_candidate_invalid")
    require(
        source["selection_status"] == ("qualified" if selected else "not_met"),
        "selection_status_invalid",
    )
    baseline_repeatable = first["current_identity_both"] == second["current_identity_both"]
    variant_drift = any(first[name] != second[name] for name in order[1:])
    selection_repeatable = all(
        item["gate"] == "not_met" for report in (first, second) for item in report.values()
    )
    require(baseline_repeatable, "current_baseline_not_repeatable")
    require(selection_repeatable, "selection_outcome_not_repeatable")
    print(
        f"aggregate_repeatability=current_baseline_exact;"
        f"experimental_variant_drift={'true' if variant_drift else 'false'};"
        "selection_outcome_repeatable=true"
    )
    print(
        f"selection_status={source['selection_status']};"
        f"selected_candidate={selected or 'none'};promotion_authorized=false"
    )
    print("v13_40_measurement_review=pass")
except Exception as error:
    reason = str(error) if isinstance(error, ReviewError) else "observation_review_invalid"
    print(f"v13_40_measurement_review=blocked;reason={reason}")
    raise SystemExit(1) from error
PY
then
  while IFS= read -r line; do printf '%s\n' "$line" | tee -a "$report_path"; done <"$review_stdout"
  printf '\nSCRIPT RESULT\nscript_192_v13_40_measurement_review=blocked\n'
  exit 1
fi

printf '%s\n' \
  'purpose=recover_and_review_v13_40_measurement' \
  "started_utc=$timestamp;script_sha256=$script_sha256" \
  "first_report_sha256=$EXPECTED_FIRST_REPORT_SHA256" \
  "second_report_sha256=$EXPECTED_SECOND_REPORT_SHA256" \
  "retained_observation_sha256=$EXPECTED_OBSERVATION_SHA256" \
  'measurement_runs=2;retained_complete_observations=1;cases=180;variants=5' \
  'model_contact=false;database_contact=false;corpus_ingestion=false;promotion=false' \
  | tee -a "$report_path"
while IFS= read -r line; do printf '%s\n' "$line" | tee -a "$report_path"; done <"$review_stdout"
printf '%s\n' \
  'harness_correction=canonical_mapping_order_removed_from_validation;measurement_repeated=false' \
  'next_gate=discuss_retrieval_quality_direction_before_any_new_candidate' \
  | tee -a "$report_path"

cleanup
trap - EXIT HUP INT TERM
report_sha256="$(sha256sum "$report_path" | awk '{print $1}')"
printf 'local_report=%s;local_report_sha256=%s\n' "$report_path" "$report_sha256"
printf '\nSCRIPT RESULT\nscript_192_v13_40_measurement_review=pass\n'
