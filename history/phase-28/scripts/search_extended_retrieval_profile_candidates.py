#!/usr/bin/env python3
"""Search bounded retrieval profiles from accepted 60-case lane rankings.

This helper performs no database or model calls. It replays checksum-bound lane
ranks, applies the production RRF ordering contract, and reports candidates
without changing or freezing the released method profile.
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
EXPECTED_CASE_COUNT = 60
STRICT_TARGET = Fraction(91, 100)
EXPECTED_PROFILE = {
    "schema_version": 1,
    "method_profile_id": "5797961aee919aa73bbd99d6cc188084d57d22839a1d4cff0febc2e73e17b4b0",
    "explicit_page_route": "document_identifier_plus_page",
    "exact_candidate_depth": 1,
    "lexical_search_config": "english",
    "lexical_fallback": "native_or_when_strict_empty",
    "lexical_candidate_depth": 20,
    "vector_distance": "cosine",
    "vector_candidate_depth": 20,
    "fused_candidate_depth": 20,
    "rrf_constant": 60,
    "lane_weights": {"exact": 1, "lexical": 1, "vector": 4},
    "learned_reranker": False,
}


class CandidateSearchError(RuntimeError):
    """Stable, content-free search failure."""


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise CandidateSearchError(reason)


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=True
    ).encode("utf-8")


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
        raise CandidateSearchError("json_input_invalid") from error


@dataclass(frozen=True, slots=True)
class Parameters:
    """One temporary profile evaluated without changing configuration."""

    exact_depth: int
    lexical_depth: int
    vector_depth: int
    rrf_constant: int
    exact_weight: int
    lexical_weight: int
    vector_weight: int

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

    def changed_field_count(self) -> int:
        return sum(
            left != right
            for left, right in zip(self.ordering(), released_parameters().ordering())
        )

    def absolute_distance(self) -> int:
        return sum(
            abs(left - right)
            for left, right in zip(self.ordering(), released_parameters().ordering())
        )


@dataclass(frozen=True, slots=True)
class Outcome:
    """Metrics and stable per-case ranks for one temporary profile."""

    parameters: Parameters
    mrr: Fraction
    top_five_count: int
    top_twenty_count: int
    rank_one_count: int
    case_results: tuple[dict[str, Any], ...]

    @property
    def target_met(self) -> bool:
        return self.mrr > STRICT_TARGET

    def record(self) -> dict[str, Any]:
        body = {
            "parameters": self.parameters.record(),
            "changed_field_count": self.parameters.changed_field_count(),
            "absolute_parameter_distance": self.parameters.absolute_distance(),
            "mrr_at_20": format_fraction(self.mrr),
            "mrr_fraction_numerator": self.mrr.numerator,
            "mrr_fraction_denominator": self.mrr.denominator,
            "rank_one_count": self.rank_one_count,
            "relevant_at_5": self.top_five_count,
            "relevant_at_20": self.top_twenty_count,
            "strict_target_met": self.target_met,
            "case_results": list(self.case_results),
        }
        body["candidate_id"] = hashlib.sha256(
            b"ishikawa.extended-retrieval-profile-candidate.v1\0"
            + canonical_bytes(body)
        ).hexdigest()
        return body


def released_parameters() -> Parameters:
    return Parameters(1, 20, 20, 60, 1, 1, 4)


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


def validate_observation(value: Any) -> tuple[Mapping[str, Any], ...]:
    require(
        isinstance(value, dict)
        and value.get("artifact_kind")
        == "ishikawa_extended_retrieval_lane_ranking_observation"
        and value.get("schema_version") == 1
        and value.get("case_count") == EXPECTED_CASE_COUNT
        and value.get("query_embedding_count") == EXPECTED_CASE_COUNT
        and value.get("retrieval_profile") == EXPECTED_PROFILE
        and value.get("capture_depths")
        == {"exact": 20, "lexical": 20, "vector": 20}
        and value.get("database_boundary") == "repeatable_read_read_only"
        and value.get("baseline_reproduced") is True
        and value.get("profile_changed") is False
        and value.get("gemma_contact") is False
        and value.get("database_write") is False
        and value.get("question_text_retained") is False
        and value.get("query_vectors_retained") is False
        and value.get("source_text_retained") is False
        and isinstance(value.get("cases"), list)
        and len(value["cases"]) == EXPECTED_CASE_COUNT,
        "lane_observation_contract_invalid",
    )
    metrics = value.get("reproduced_metrics")
    require(
        isinstance(metrics, dict)
        and metrics.get("mrr_fraction_numerator") == 28633
        and metrics.get("mrr_fraction_denominator") == 33600
        and metrics.get("mrr_at_20") == "0.852173"
        and metrics.get("cases_with_relevant_at_5") == 56
        and metrics.get("cases_with_relevant_at_20") == 60,
        "baseline_metric_contract_invalid",
    )
    cases = tuple(value["cases"])
    require(
        {case.get("case_id") for case in cases}
        == {f"E-{index:03d}" for index in range(1, 61)},
        "case_inventory_invalid",
    )
    for case in cases:
        require(
            isinstance(case, dict)
            and isinstance(case.get("case_id"), str)
            and isinstance(case.get("query_sha256"), str)
            and isinstance(case.get("relevance_target_count"), int)
            and case["relevance_target_count"] >= 1
            and type(case.get("current_first_relevant_rank")) is int
            and isinstance(case.get("lanes"), dict)
            and set(case["lanes"]) == {"exact", "lexical", "vector"},
            "case_contract_invalid",
        )
        relevance_by_chunk: dict[str, bool] = {}
        for lane in case["lanes"].values():
            require(isinstance(lane, list) and len(lane) <= 20, "lane_contract_invalid")
            for expected_rank, candidate in enumerate(lane, start=1):
                require(
                    isinstance(candidate, dict)
                    and set(candidate) == {"chunk_id", "rank", "relevant"}
                    and isinstance(candidate.get("chunk_id"), str)
                    and candidate.get("rank") == expected_rank
                    and type(candidate.get("relevant")) is bool,
                    "candidate_contract_invalid",
                )
                prior = relevance_by_chunk.setdefault(
                    candidate["chunk_id"], candidate["relevant"]
                )
                require(prior is candidate["relevant"], "candidate_relevance_conflict")
    return cases


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
                    "relevant": candidate["relevant"],
                    "score": Fraction(0, 1),
                    "exact_priority": False,
                    "minimum_rank": candidate["rank"],
                },
            )
            require(
                state["relevant"] is candidate["relevant"],
                "candidate_relevance_conflict",
            )
            state["score"] += Fraction(weight, parameters.rrf_constant + candidate["rank"])
            state["exact_priority"] = state["exact_priority"] or lane_name == "exact"
            state["minimum_rank"] = min(state["minimum_rank"], candidate["rank"])
    fused = sorted(
        accumulated.items(),
        key=lambda item: (
            -int(item[1]["exact_priority"]),
            -item[1]["score"],
            item[1]["minimum_rank"],
            item[0],
        ),
    )[:FUSED_DEPTH]
    first_relevant_rank = next(
        (
            rank
            for rank, (_, state) in enumerate(fused, start=1)
            if state["relevant"]
        ),
        None,
    )
    return {
        "case_id": case["case_id"],
        "first_relevant_rank": first_relevant_rank,
    }


def evaluate_parameters(
    cases: Sequence[Mapping[str, Any]], parameters: Parameters
) -> Outcome:
    results = tuple(evaluate_case(case, parameters) for case in cases)
    reciprocal_sum = sum(
        (
            Fraction(1, result["first_relevant_rank"])
            if result["first_relevant_rank"] is not None
            else Fraction(0, 1)
        )
        for result in results
    )
    return Outcome(
        parameters=parameters,
        mrr=reciprocal_sum / EXPECTED_CASE_COUNT,
        top_five_count=sum(
            result["first_relevant_rank"] is not None
            and result["first_relevant_rank"] <= 5
            for result in results
        ),
        top_twenty_count=sum(
            result["first_relevant_rank"] is not None for result in results
        ),
        rank_one_count=sum(result["first_relevant_rank"] == 1 for result in results),
        case_results=results,
    )


def quality_order(outcome: Outcome) -> tuple[Any, ...]:
    return (
        -outcome.mrr,
        outcome.parameters.changed_field_count(),
        outcome.parameters.absolute_distance(),
        outcome.parameters.ordering(),
    )


def minimal_change_order(outcome: Outcome) -> tuple[Any, ...]:
    return (
        outcome.parameters.changed_field_count(),
        -outcome.mrr,
        outcome.parameters.absolute_distance(),
        outcome.parameters.ordering(),
    )


def self_test() -> int:
    require(len(primitive_weights()) == 55, "weight_grid_size_invalid")
    require(len(parameter_grid()) == 43120, "parameter_grid_size_invalid")
    released = released_parameters()
    require(
        released.changed_field_count() == 0 and released.absolute_distance() == 0,
        "released_parameter_identity_invalid",
    )
    changed = Parameters(1, 20, 20, 60, 1, 2, 4)
    require(
        changed.changed_field_count() == 1 and changed.absolute_distance() == 1,
        "change_measure_invalid",
    )
    synthetic_case = {
        "case_id": "E-001",
        "lanes": {
            "exact": [],
            "lexical": [
                {"chunk_id": "irrelevant", "rank": 1, "relevant": False},
                {"chunk_id": "relevant", "rank": 2, "relevant": True},
            ],
            "vector": [
                {"chunk_id": "relevant", "rank": 1, "relevant": True},
                {"chunk_id": "irrelevant", "rank": 2, "relevant": False},
            ],
        },
    }
    result = evaluate_case(synthetic_case, released)
    require(result["first_relevant_rank"] == 1, "fusion_self_test_failed")
    print("extended_retrieval_profile_search_self_test=pass")
    return 0


def run(arguments: argparse.Namespace) -> int:
    observation_path = Path(arguments.observation).resolve(strict=True)
    output_path = Path(arguments.output)
    require(
        output_path.is_absolute()
        and not output_path.exists()
        and not output_path.is_symlink(),
        "output_path_invalid",
    )
    observation = load_json(observation_path, 2 * 1024 * 1024)
    cases = validate_observation(observation)
    released = evaluate_parameters(cases, released_parameters())
    require(
        released.mrr == Fraction(28633, 33600)
        and released.top_five_count == 56
        and released.top_twenty_count == 60
        and released.rank_one_count == 48,
        "released_profile_replay_failed",
    )
    outcomes = tuple(
        evaluate_parameters(cases, parameters) for parameters in parameter_grid()
    )
    qualifying = tuple(outcome for outcome in outcomes if outcome.target_met)
    by_quality = tuple(sorted(outcomes, key=quality_order))
    qualifying_by_quality = tuple(sorted(qualifying, key=quality_order))
    qualifying_by_minimal_change = tuple(
        sorted(qualifying, key=minimal_change_order)
    )
    highest = by_quality[0]
    minimal = qualifying_by_minimal_change[0] if qualifying else None
    artifact: dict[str, Any] = {
        "artifact_kind": "ishikawa_extended_retrieval_profile_search",
        "schema_version": 1,
        "lane_observation_sha256": sha256_file(observation_path),
        "lane_observation_set_id": observation["observation_set_id"],
        "case_count": EXPECTED_CASE_COUNT,
        "strict_production_target": "greater_than_0.91",
        "search_grid": {
            "exact_candidate_depths": list(EXACT_DEPTHS),
            "lexical_candidate_depths": list(LEXICAL_DEPTHS),
            "vector_candidate_depths": list(VECTOR_DEPTHS),
            "fused_candidate_depth": FUSED_DEPTH,
            "rrf_constants": list(RRF_CONSTANTS),
            "primitive_lane_weights": [list(item) for item in primitive_weights()],
        },
        "candidate_count": len(outcomes),
        "qualifying_candidate_count": len(qualifying),
        "gate_basis": "strict_mrr_at_20_only",
        "released_profile": released.record(),
        "minimal_change_qualifying_candidate": minimal.record() if minimal else None,
        "highest_mrr_candidate": highest.record(),
        "highest_mrr_qualifying_candidates": [
            outcome.record() for outcome in qualifying_by_quality[:20]
        ],
        "minimal_change_qualifying_candidates": [
            outcome.record() for outcome in qualifying_by_minimal_change[:20]
        ],
        "selection_status": "review_required" if qualifying else "no_candidate_meets_target",
        "method_profile_changed": False,
        "database_contact": False,
        "model_contact": False,
        "manual_review_performed": False,
        "question_text_read": False,
        "query_vectors_read": False,
        "source_text_read": False,
    }
    artifact["search_id"] = hashlib.sha256(
        b"ishikawa.extended-retrieval-profile-search.v1\0"
        + canonical_bytes(artifact)
    ).hexdigest()
    payload = canonical_bytes(artifact) + b"\n"
    descriptor = os.open(output_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)
    minimal_record = minimal.record() if minimal else None
    highest_record = highest.record()
    print("purpose=search_extended_ishikawa_retrieval_profiles")
    print(
        f"candidate_count={len(outcomes)};qualifying_candidate_count={len(qualifying)};"
        "database_contact=false;model_contact=false;method_profile_changed=false"
    )
    print(
        "released_mrr_at_20=0.852173;strict_production_target=greater_than_0.91;"
        "gate_basis=mrr_at_20_only"
    )
    if minimal_record is not None:
        parameters = minimal_record["parameters"]
        weights = parameters["lane_weights"]
        print(
            f"minimal_candidate_id={minimal_record['candidate_id']};"
            f"mrr_at_20={minimal_record['mrr_at_20']};"
            f"changed_fields={minimal_record['changed_field_count']};"
            f"relevant_at_5={minimal_record['relevant_at_5']}/60;"
            f"relevant_at_20={minimal_record['relevant_at_20']}/60"
        )
        print(
            f"minimal_depths={parameters['exact_candidate_depth']},"
            f"{parameters['lexical_candidate_depth']},"
            f"{parameters['vector_candidate_depth']},20;"
            f"rrf_constant={parameters['rrf_constant']};"
            f"lane_weights={weights['exact']},{weights['lexical']},{weights['vector']}"
        )
    else:
        print("minimal_candidate=none;strict_target_met=false")
    highest_parameters = highest_record["parameters"]
    highest_weights = highest_parameters["lane_weights"]
    print(
        f"highest_candidate_id={highest_record['candidate_id']};"
        f"mrr_at_20={highest_record['mrr_at_20']};"
        f"changed_fields={highest_record['changed_field_count']};"
        f"relevant_at_5={highest_record['relevant_at_5']}/60;"
        f"relevant_at_20={highest_record['relevant_at_20']}/60"
    )
    print(
        f"highest_depths={highest_parameters['exact_candidate_depth']},"
        f"{highest_parameters['lexical_candidate_depth']},"
        f"{highest_parameters['vector_candidate_depth']},20;"
        f"rrf_constant={highest_parameters['rrf_constant']};"
        f"lane_weights={highest_weights['exact']},{highest_weights['lexical']},"
        f"{highest_weights['vector']}"
    )
    print(
        f"search_id={artifact['search_id']};"
        f"artifact_sha256={hashlib.sha256(payload).hexdigest()};"
        f"artifact_bytes={len(payload)}"
    )
    print(f"extended_retrieval_profile_search=pass;selection_status={artifact['selection_status']}")
    return 0


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--observation")
    parser.add_argument("--output")
    arguments = parser.parse_args()
    if arguments.self_test == arguments.run:
        raise CandidateSearchError("mode_invalid")
    if arguments.run and not all((arguments.observation, arguments.output)):
        raise CandidateSearchError("argument_missing")
    return arguments


def main() -> int:
    try:
        arguments = parse_arguments()
        return self_test() if arguments.self_test else run(arguments)
    except CandidateSearchError as error:
        print(f"extended_retrieval_profile_search=blocked;reason={error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("extended_retrieval_profile_search=blocked;reason=interrupted", file=sys.stderr)
        return 130
    except Exception as error:
        print(
            f"extended_retrieval_profile_search=blocked;reason=bounded_{type(error).__name__}",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
