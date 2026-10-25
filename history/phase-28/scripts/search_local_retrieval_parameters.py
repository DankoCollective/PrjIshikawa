#!/usr/bin/env python3
"""Search bounded retrieval settings from an accepted ranking observation.

Script 119 uses this helper to replay already-retained lane rankings. The
helper never connects to PostgreSQL or a model and never receives questions,
query vectors, credentials, or source text. It recommends one candidate using
an explicit KISS rule but does not modify or freeze the method profile.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import sys
from dataclasses import dataclass
from decimal import Decimal, localcontext
from fractions import Fraction
from itertools import product
from pathlib import Path
from typing import Any, Mapping, Sequence


EXACT_DEPTHS = (1, 2, 3, 5, 8, 10, 20)
LEXICAL_DEPTHS = (5, 10, 15, 20)
VECTOR_DEPTHS = (5, 10, 15, 20)
RRF_CONSTANTS = (1, 10, 20, 40, 60, 80, 100)
WEIGHT_VALUES = (1, 2, 3, 4)
FUSED_DEPTH = 20
EXPECTED_BASELINE_PROFILE = {
    "schema_version": 1,
    "method_profile_id": "5797961aee919aa73bbd99d6cc188084d57d22839a1d4cff0febc2e73e17b4b0",
    "explicit_page_route": "document_identifier_plus_page",
    "exact_candidate_depth": 20,
    "lexical_search_config": "english",
    "lexical_fallback": "native_or_when_strict_empty",
    "lexical_candidate_depth": 20,
    "vector_distance": "cosine",
    "vector_candidate_depth": 20,
    "fused_candidate_depth": 20,
    "rrf_constant": 60,
    "lane_weights": {"exact": 1, "lexical": 1, "vector": 1},
    "learned_reranker": False,
}
EXPECTED_BASELINE_ID = "7ee0a825a4ae6754434d4438df57a42be2d17731976f120183df91b558894472"


class SearchError(RuntimeError):
    """Stable, content-free parameter-search failure."""


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise SearchError(reason)


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode(
        "utf-8"
    )


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_json(path: Path, maximum_bytes: int) -> Any:
    require(
        path.is_absolute()
        and path.is_file()
        and not path.is_symlink()
        and path.stat().st_size <= maximum_bytes,
        "json_input_unsafe",
    )
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise SearchError("json_input_invalid") from error


@dataclass(frozen=True, slots=True)
class Parameters:
    """One temporary fusion profile evaluated without changing configuration."""

    exact_depth: int
    lexical_depth: int
    vector_depth: int
    rrf_constant: int
    exact_weight: int
    lexical_weight: int
    vector_weight: int

    def record(self) -> dict[str, Any]:
        return {
            "exact_candidate_depth": self.exact_depth,
            "lexical_candidate_depth": self.lexical_depth,
            "vector_candidate_depth": self.vector_depth,
            "fused_candidate_depth": FUSED_DEPTH,
            "rrf_constant": self.rrf_constant,
            "lane_weights": {
                "exact": self.exact_weight,
                "lexical": self.lexical_weight,
                "vector": self.vector_weight,
            },
        }

    def ordering(self) -> tuple[int, ...]:
        return (
            self.exact_depth,
            self.lexical_depth,
            self.vector_depth,
            self.rrf_constant,
            self.exact_weight,
            self.lexical_weight,
            self.vector_weight,
        )

    def changed_field_count(self) -> int:
        baseline = Parameters(20, 20, 20, 60, 1, 1, 1)
        return sum(left != right for left, right in zip(self.ordering(), baseline.ordering()))

    def absolute_distance(self) -> int:
        baseline = Parameters(20, 20, 20, 60, 1, 1, 1)
        return sum(abs(left - right) for left, right in zip(self.ordering(), baseline.ordering()))


@dataclass(frozen=True, slots=True)
class Outcome:
    """Metrics and stable per-case ranks produced by one temporary profile."""

    parameters: Parameters
    mrr: Fraction
    top_five_count: int
    matched_evidence_count: int
    case_results: tuple[dict[str, Any], ...]

    @property
    def gate_passed(self) -> bool:
        return (
            self.mrr >= Fraction(85, 100)
            and self.top_five_count == 6
            and self.matched_evidence_count == 13
        )

    def record(self) -> dict[str, Any]:
        body = {
            "parameters": self.parameters.record(),
            "changed_field_count": self.parameters.changed_field_count(),
            "absolute_parameter_distance": self.parameters.absolute_distance(),
            "mrr_at_20": format_fraction(self.mrr),
            "mrr_fraction_numerator": self.mrr.numerator,
            "mrr_fraction_denominator": self.mrr.denominator,
            "responsive_top_five": self.top_five_count,
            "required_evidence_at_20": self.matched_evidence_count,
            "ranking_gate": "pass" if self.gate_passed else "not_met",
            "case_results": list(self.case_results),
        }
        body["candidate_id"] = hashlib.sha256(
            b"ishikawa.retrieval-parameter-candidate.v1\0" + canonical_bytes(body)
        ).hexdigest()
        return body


def format_fraction(value: Fraction) -> str:
    with localcontext() as context:
        context.prec = 28
        decimal_value = Decimal(value.numerator) / Decimal(value.denominator)
        return format(decimal_value, ".6f")


def primitive_weights() -> tuple[tuple[int, int, int], ...]:
    weights = []
    for exact_weight, lexical_weight, vector_weight in product(WEIGHT_VALUES, repeat=3):
        if math.gcd(math.gcd(exact_weight, lexical_weight), vector_weight) == 1:
            weights.append((exact_weight, lexical_weight, vector_weight))
    return tuple(weights)


def parameter_grid() -> tuple[Parameters, ...]:
    return tuple(
        Parameters(
            exact_depth,
            lexical_depth,
            vector_depth,
            rrf_constant,
            exact_weight,
            lexical_weight,
            vector_weight,
        )
        for exact_depth, lexical_depth, vector_depth, rrf_constant, weights in product(
            EXACT_DEPTHS,
            LEXICAL_DEPTHS,
            VECTOR_DEPTHS,
            RRF_CONSTANTS,
            primitive_weights(),
        )
        for exact_weight, lexical_weight, vector_weight in (weights,)
    )


def validate_baseline(value: Any) -> tuple[Mapping[str, Any], ...]:
    require(
        isinstance(value, dict)
        and value.get("artifact_kind") == "ishikawa_local_retrieval_ranking_baseline"
        and value.get("schema_version") == 1
        and value.get("observation_set_id") == EXPECTED_BASELINE_ID
        and value.get("case_count") == 13
        and value.get("query_embedding_count") == 12
        and value.get("retrieval_profile") == EXPECTED_BASELINE_PROFILE
        and value.get("database_boundary") == "repeatable_read_read_only"
        and value.get("gemma_contact") is False
        and value.get("question_text_retained") is False
        and value.get("query_vectors_retained") is False
        and value.get("source_text_retained") is False
        and isinstance(value.get("cases"), list)
        and len(value["cases"]) == 13,
        "baseline_contract_invalid",
    )
    metrics = value.get("metrics")
    require(
        isinstance(metrics, dict)
        and metrics.get("mrr_at_20") == "0.690476"
        and metrics.get("responsive_cases_with_relevant_top_five") == 5
        and metrics.get("required_evidence_matched_at_20") == 13
        and metrics.get("required_evidence_total") == 13
        and metrics.get("ranking_gate") == "not_met",
        "baseline_metric_contract_invalid",
    )
    cases = tuple(value["cases"])
    require(
        sum(case.get("case_class") == "responsive" for case in cases) == 6
        and sum(case.get("case_class") == "nonresponsive" for case in cases) == 6
        and sum(case.get("case_class") == "broad-navigation" for case in cases) == 1,
        "baseline_case_inventory_invalid",
    )
    for case in cases:
        require(
            isinstance(case, dict)
            and isinstance(case.get("case_id"), str)
            and isinstance(case.get("lanes"), dict)
            and set(case["lanes"]) == {"exact", "lexical", "vector"}
            and isinstance(case.get("matched_evidence"), list),
            "baseline_case_contract_invalid",
        )
        if case["case_class"] == "responsive":
            require(
                case.get("matched_evidence_count") == case.get("required_evidence_count")
                and case.get("matched_evidence_count") >= 1,
                "baseline_truth_projection_incomplete",
            )
        for lane_name, lane in case["lanes"].items():
            require(isinstance(lane, list) and len(lane) <= 20, "baseline_lane_invalid")
            for expected_rank, candidate in enumerate(lane, start=1):
                require(
                    isinstance(candidate, dict)
                    and candidate.get("rank") == expected_rank
                    and isinstance(candidate.get("chunk_id"), str)
                    and isinstance(candidate.get("display_name"), str)
                    and isinstance(candidate.get("pages"), list)
                    and lane_name in {"exact", "lexical", "vector"},
                    "baseline_lane_invalid",
                )
    return cases


def evidence_matches(candidate: Mapping[str, Any], expected: Mapping[str, Any]) -> bool:
    return candidate["display_name"] == expected["display_name"] and any(
        page_start <= expected["page"] <= page_end
        for page_start, page_end in candidate["pages"]
    )


def evaluate_case(case: Mapping[str, Any], parameters: Parameters) -> dict[str, Any]:
    lane_settings = (
        ("exact", parameters.exact_depth, parameters.exact_weight),
        ("lexical", parameters.lexical_depth, parameters.lexical_weight),
        ("vector", parameters.vector_depth, parameters.vector_weight),
    )
    accumulated: dict[str, dict[str, Any]] = {}
    for lane_name, depth, weight in lane_settings:
        for candidate in case["lanes"][lane_name]:
            if candidate["rank"] > depth:
                continue
            state = accumulated.setdefault(
                candidate["chunk_id"],
                {
                    "candidate": candidate,
                    "score": Fraction(0, 1),
                    "exact_priority": False,
                    "minimum_rank": candidate["rank"],
                },
            )
            state["score"] += Fraction(weight, parameters.rrf_constant + candidate["rank"])
            state["exact_priority"] = state["exact_priority"] or lane_name == "exact"
            state["minimum_rank"] = min(state["minimum_rank"], candidate["rank"])
    fused = sorted(
        accumulated.values(),
        key=lambda state: (
            -int(state["exact_priority"]),
            -state["score"],
            state["minimum_rank"],
            state["candidate"]["chunk_id"],
        ),
    )[:FUSED_DEPTH]
    expected_evidence = case["matched_evidence"]
    first_relevant_rank = next(
        (
            rank
            for rank, state in enumerate(fused, start=1)
            if any(evidence_matches(state["candidate"], expected) for expected in expected_evidence)
        ),
        None,
    )
    matched_count = sum(
        any(evidence_matches(state["candidate"], expected) for state in fused)
        for expected in expected_evidence
    )
    return {
        "case_id": case["case_id"],
        "first_relevant_rank": first_relevant_rank,
        "relevant_within_top_five": (
            first_relevant_rank is not None and first_relevant_rank <= 5
        ),
        "matched_evidence_count": matched_count,
        "required_evidence_count": len(expected_evidence),
    }


def evaluate_parameters(
    responsive_cases: Sequence[Mapping[str, Any]], parameters: Parameters
) -> Outcome:
    case_results = tuple(evaluate_case(case, parameters) for case in responsive_cases)
    reciprocal_sum = sum(
        (
            Fraction(1, result["first_relevant_rank"])
            if result["first_relevant_rank"] is not None
            else Fraction(0, 1)
        )
        for result in case_results
    )
    return Outcome(
        parameters=parameters,
        mrr=reciprocal_sum / len(responsive_cases),
        top_five_count=sum(result["relevant_within_top_five"] for result in case_results),
        matched_evidence_count=sum(result["matched_evidence_count"] for result in case_results),
        case_results=case_results,
    )


def quality_order(outcome: Outcome) -> tuple[Any, ...]:
    return (
        -outcome.mrr,
        outcome.parameters.changed_field_count(),
        outcome.parameters.absolute_distance(),
        outcome.parameters.ordering(),
    )


def kiss_order(outcome: Outcome) -> tuple[Any, ...]:
    return (
        outcome.parameters.changed_field_count(),
        -outcome.mrr,
        outcome.parameters.absolute_distance(),
        outcome.parameters.ordering(),
    )


def self_test() -> int:
    require(len(primitive_weights()) == 55, "weight_grid_size_invalid")
    require(len(parameter_grid()) == 43120, "parameter_grid_size_invalid")
    baseline = Parameters(20, 20, 20, 60, 1, 1, 1)
    require(baseline.changed_field_count() == 0, "baseline_change_count_invalid")
    candidate = Parameters(1, 20, 20, 60, 1, 1, 4)
    require(
        candidate.changed_field_count() == 2 and candidate.absolute_distance() == 22,
        "candidate_change_measure_invalid",
    )
    print("local_retrieval_parameter_search_self_test=pass")
    return 0


def run(arguments: argparse.Namespace) -> int:
    baseline_path = Path(arguments.baseline).resolve(strict=True)
    output_path = Path(arguments.output)
    require(
        output_path.is_absolute() and not output_path.exists() and not output_path.is_symlink(),
        "output_path_invalid",
    )
    baseline_value = load_json(baseline_path, 1024 * 1024)
    cases = validate_baseline(baseline_value)
    responsive_cases = tuple(case for case in cases if case["case_class"] == "responsive")
    outcomes = tuple(
        evaluate_parameters(responsive_cases, parameters) for parameters in parameter_grid()
    )
    qualifying = tuple(outcome for outcome in outcomes if outcome.gate_passed)
    require(qualifying, "no_qualifying_candidate")
    by_quality = tuple(sorted(qualifying, key=quality_order))
    by_kiss = tuple(sorted(qualifying, key=kiss_order))
    recommended = by_kiss[0]
    artifact: dict[str, Any] = {
        "artifact_kind": "ishikawa_local_retrieval_parameter_search",
        "schema_version": 1,
        "baseline_artifact_sha256": sha256_file(baseline_path),
        "baseline_observation_set_id": baseline_value["observation_set_id"],
        "search_grid": {
            "exact_candidate_depths": list(EXACT_DEPTHS),
            "lexical_candidate_depths": list(LEXICAL_DEPTHS),
            "vector_candidate_depths": list(VECTOR_DEPTHS),
            "fused_candidate_depth": FUSED_DEPTH,
            "rrf_constants": list(RRF_CONSTANTS),
            "primitive_lane_weights": [list(weights) for weights in primitive_weights()],
        },
        "candidate_count": len(outcomes),
        "qualifying_candidate_count": len(qualifying),
        "acceptance_gate": {
            "minimum_mrr_at_20": "0.850000",
            "responsive_top_five_required": 6,
            "required_evidence_at_20_required": 13,
        },
        "selection_rule": (
            "fewest_changed_fields_then_highest_mrr_then_smallest_absolute_"
            "parameter_distance_then_lexicographic_parameters"
        ),
        "recommended_candidate": recommended.record(),
        "highest_quality_candidates": [outcome.record() for outcome in by_quality[:20]],
        "smallest_change_candidates": [outcome.record() for outcome in by_kiss[:20]],
        "method_profile_changed": False,
        "database_contact": False,
        "model_contact": False,
        "operator_freeze_required": True,
        "question_text_retained": False,
        "query_vectors_retained": False,
        "source_text_retained": False,
    }
    artifact["search_id"] = hashlib.sha256(
        b"ishikawa.local-retrieval-parameter-search.v1\0" + canonical_bytes(artifact)
    ).hexdigest()
    payload = canonical_bytes(artifact) + b"\n"
    descriptor = os.open(output_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)
    recommended_record = artifact["recommended_candidate"]
    print("purpose=search_bounded_local_retrieval_parameters")
    print(
        f"candidate_count={len(outcomes)};qualifying_candidate_count={len(qualifying)};"
        "database_contact=false;model_contact=false;method_profile_changed=false"
    )
    print(
        f"recommended_candidate_id={recommended_record['candidate_id']};"
        f"mrr_at_20={recommended_record['mrr_at_20']};"
        f"responsive_top_five={recommended_record['responsive_top_five']}/6;"
        f"required_evidence_at_20={recommended_record['required_evidence_at_20']}/13"
    )
    parameters = recommended_record["parameters"]
    weights = parameters["lane_weights"]
    print(
        f"recommended_depths={parameters['exact_candidate_depth']},"
        f"{parameters['lexical_candidate_depth']},{parameters['vector_candidate_depth']},"
        f"{parameters['fused_candidate_depth']};"
        f"rrf_constant={parameters['rrf_constant']};"
        f"lane_weights={weights['exact']},{weights['lexical']},{weights['vector']}"
    )
    print(
        f"search_id={artifact['search_id']};artifact_sha256={hashlib.sha256(payload).hexdigest()};"
        f"artifact_bytes={len(payload)}"
    )
    print("local_retrieval_parameter_search=pass;selection_status=review_required")
    return 0


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--baseline")
    parser.add_argument("--output")
    arguments = parser.parse_args()
    if arguments.self_test == arguments.run:
        raise SearchError("mode_invalid")
    if arguments.run and not all((arguments.baseline, arguments.output)):
        raise SearchError("argument_missing")
    return arguments


def main() -> int:
    try:
        arguments = parse_arguments()
        return self_test() if arguments.self_test else run(arguments)
    except SearchError as error:
        print(f"local_retrieval_parameter_search=blocked;reason={error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("local_retrieval_parameter_search=blocked;reason=interrupted", file=sys.stderr)
        return 130
    except Exception as error:
        print(
            f"local_retrieval_parameter_search=blocked;reason=bounded_{type(error).__name__}",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
