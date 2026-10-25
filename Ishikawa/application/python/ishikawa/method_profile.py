"""Validated, versioned retrieval settings for Ishikawa.

The retrieval-profile identity is distinct from the chunk-method identity.
Changing retrieval settings requires retrieval requalification; changing the
chunk method may additionally require candidate regeneration and embedding.
"""

from __future__ import annotations

import re
from collections.abc import Mapping
from dataclasses import dataclass, replace
from typing import Any

from .canonical import domain_digest
from .errors import IshikawaValidationError


_HEX_DIGEST = re.compile(r"^[0-9a-f]{64}$")
_QUALIFIED_LANE_WEIGHTS = {"exact": 1, "lexical": 2, "vector": 4}


def _fail(reason_code: str, message: str) -> None:
    raise IshikawaValidationError("REJECTED", reason_code, message)


def _mapping(value: Any, label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping) or not all(isinstance(key, str) for key in value):
        _fail("METHOD_PROFILE_TYPE_INVALID", f"{label} must be a string-keyed mapping.")
    return value


def _exact_fields(value: Mapping[str, Any], expected: frozenset[str], label: str) -> None:
    keys = frozenset(value)
    missing = sorted(expected - keys)
    unknown = sorted(keys - expected)
    if missing:
        _fail("METHOD_PROFILE_FIELD_MISSING", f"{label} is missing '{missing[0]}'.")
    if unknown:
        _fail("METHOD_PROFILE_FIELD_UNKNOWN", f"{label} contains unknown field '{unknown[0]}'.")


def _integer(value: Any, label: str, minimum: int, maximum: int) -> int:
    if type(value) is not int or not minimum <= value <= maximum:
        _fail(
            "METHOD_PROFILE_VALUE_INVALID",
            f"{label} must be an integer between {minimum} and {maximum}.",
        )
    return value


def _literal(value: Any, expected: str, label: str) -> str:
    if value != expected:
        _fail("METHOD_PROFILE_VALUE_UNSUPPORTED", f"{label} has no qualified implementation.")
    return expected


def _number(value: Any, expected: float, label: str) -> float:
    if type(value) not in {int, float} or float(value) != expected:
        _fail("METHOD_PROFILE_VALUE_UNSUPPORTED", f"{label} has no qualified implementation.")
    return expected


@dataclass(frozen=True, slots=True)
class RetrievalProfile:
    schema_version: int
    chunk_method_profile_id: str
    explicit_page_route: str
    exact_candidate_depth: int
    lexical_search_config: str
    lexical_fallback: str
    lexical_candidate_depth: int
    vector_distance: str
    vector_candidate_depth: int
    fusion_algorithm: str
    fused_candidate_depth: int
    rrf_constant: int
    exact_weight: int
    lexical_weight: int
    vector_weight: int
    learned_reranker: bool
    section_page_representatives: bool
    document_local_duplicate_canonicalization: bool
    representative_evidence: str
    document_shortlist_per_lane: int
    expansion_baseline_weight: int
    expansion_best_facet_weight: int
    expansion_facet_coverage_weight: int
    digest: str

    def canonical(self) -> dict[str, Any]:
        return {
            "schema_version": self.schema_version,
            "chunk_method_profile_id": self.chunk_method_profile_id,
            "retrieval": {
                "exact": {
                    "explicit_page_route": self.explicit_page_route,
                    "candidate_depth": self.exact_candidate_depth,
                },
                "lexical": {
                    "search_config": self.lexical_search_config,
                    "fallback": self.lexical_fallback,
                    "candidate_depth": self.lexical_candidate_depth,
                },
                "vector": {
                    "distance": self.vector_distance,
                    "candidate_depth": self.vector_candidate_depth,
                },
                "fusion": {
                    "algorithm": self.fusion_algorithm,
                    "candidate_depth": self.fused_candidate_depth,
                    "rrf_constant": self.rrf_constant,
                    "lane_weights": {
                        "exact": self.exact_weight,
                        "lexical": self.lexical_weight,
                        "vector": self.vector_weight,
                    },
                },
                "reranker": {"enabled": self.learned_reranker},
                "candidate_representation": {
                    "section_page_representatives": self.section_page_representatives,
                    "document_local_duplicate_canonicalization": (
                        self.document_local_duplicate_canonicalization
                    ),
                    "representative_evidence": self.representative_evidence,
                },
                "candidate_expansion": {
                    "enabled": True,
                    "route": "ordinary_body_excluding_metadata_relationship_page",
                    "query_decomposition": "literal_clauses_v1",
                    "maximum_facets": 4,
                    "minimum_facet_words": 3,
                    "document_shortlist_per_lane": self.document_shortlist_per_lane,
                    "baseline_weight": self.expansion_baseline_weight,
                    "best_facet_weight": self.expansion_best_facet_weight,
                    "facet_coverage_weight": self.expansion_facet_coverage_weight,
                },
                "score_calibration": {
                    "enabled": True,
                    "algorithm": "query_local_min_max_global_v1",
                    "weights": {
                        "original_lexical": 1.0,
                        "original_vector": 3.0,
                        "vector_facet_coverage": 1.0,
                        "document_lexical_affinity": 1.0,
                        "heading_path_overlap": 0.10,
                    },
                    "tie_breaks": "heading_baseline_source_rank_chunk_id",
                },
            },
        }

    def observation_contract(self) -> dict[str, Any]:
        """Return the settings shape retained by the accepted calibration."""

        return {
            "schema_version": self.schema_version,
            "method_profile_id": self.chunk_method_profile_id,
            "lexical_search_config": self.lexical_search_config,
            "lexical_fallback": self.lexical_fallback,
            "explicit_page_route": self.explicit_page_route,
            "exact_candidate_depth": self.exact_candidate_depth,
            "lexical_candidate_depth": self.lexical_candidate_depth,
            "vector_candidate_depth": self.vector_candidate_depth,
            "fused_candidate_depth": self.fused_candidate_depth,
            "rrf_constant": self.rrf_constant,
            "lane_weights": {
                "exact": self.exact_weight,
                "lexical": self.lexical_weight,
                "vector": self.vector_weight,
            },
            "vector_distance": self.vector_distance,
            "learned_reranker": self.learned_reranker,
            "section_page_representatives": self.section_page_representatives,
            "document_local_duplicate_canonicalization": (
                self.document_local_duplicate_canonicalization
            ),
            "representative_evidence": self.representative_evidence,
            "document_shortlist_per_lane": self.document_shortlist_per_lane,
            "expansion_baseline_weight": self.expansion_baseline_weight,
            "expansion_best_facet_weight": self.expansion_best_facet_weight,
            "expansion_facet_coverage_weight": self.expansion_facet_coverage_weight,
            "score_calibration": "raw_l1_v3_fc1_d1_h010",
        }


def validate_retrieval_profile(value: Any) -> RetrievalProfile:
    """Validate and canonically identify ``method_profile.yaml`` v1."""

    root = _mapping(value, "method profile")
    _exact_fields(
        root,
        frozenset({"schema_version", "chunk_method_profile_id", "retrieval"}),
        "method profile",
    )
    if type(root["schema_version"]) is not int or root["schema_version"] != 3:
        _fail("METHOD_PROFILE_SCHEMA_UNSUPPORTED", "method profile requires schema version 3.")
    chunk_identity = root["chunk_method_profile_id"]
    if not isinstance(chunk_identity, str) or _HEX_DIGEST.fullmatch(chunk_identity) is None:
        _fail(
            "METHOD_PROFILE_CHUNK_IDENTITY_INVALID",
            "chunk_method_profile_id must be a lowercase SHA-256 identity.",
        )

    retrieval = _mapping(root["retrieval"], "retrieval settings")
    _exact_fields(
        retrieval,
        frozenset(
            {
                "exact", "lexical", "vector", "fusion", "reranker",
                "candidate_representation", "candidate_expansion", "score_calibration",
            }
        ),
        "retrieval settings",
    )
    exact = _mapping(retrieval["exact"], "exact settings")
    lexical = _mapping(retrieval["lexical"], "lexical settings")
    vector = _mapping(retrieval["vector"], "vector settings")
    fusion = _mapping(retrieval["fusion"], "fusion settings")
    reranker = _mapping(retrieval["reranker"], "reranker settings")
    representation = _mapping(
        retrieval["candidate_representation"], "candidate representation settings"
    )
    expansion = _mapping(retrieval["candidate_expansion"], "candidate expansion settings")
    calibration = _mapping(retrieval["score_calibration"], "score calibration settings")
    _exact_fields(exact, frozenset({"explicit_page_route", "candidate_depth"}), "exact settings")
    _exact_fields(
        lexical,
        frozenset({"search_config", "fallback", "candidate_depth"}),
        "lexical settings",
    )
    _exact_fields(vector, frozenset({"distance", "candidate_depth"}), "vector settings")
    _exact_fields(
        fusion,
        frozenset({"algorithm", "candidate_depth", "rrf_constant", "lane_weights"}),
        "fusion settings",
    )
    _exact_fields(reranker, frozenset({"enabled"}), "reranker settings")
    _exact_fields(
        representation,
        frozenset(
            {
                "section_page_representatives",
                "document_local_duplicate_canonicalization",
                "representative_evidence",
            }
        ),
        "candidate representation settings",
    )
    _exact_fields(
        expansion,
        frozenset(
            {
                "enabled", "route", "query_decomposition", "maximum_facets",
                "minimum_facet_words", "document_shortlist_per_lane",
                "baseline_weight", "best_facet_weight", "facet_coverage_weight",
            }
        ),
        "candidate expansion settings",
    )
    _exact_fields(
        calibration,
        frozenset({"enabled", "algorithm", "weights", "tie_breaks"}),
        "score calibration settings",
    )
    calibration_weights = _mapping(calibration["weights"], "score calibration weights")
    _exact_fields(
        calibration_weights,
        frozenset(
            {
                "original_lexical", "original_vector", "vector_facet_coverage",
                "document_lexical_affinity", "heading_path_overlap",
            }
        ),
        "score calibration weights",
    )

    weights = _mapping(fusion["lane_weights"], "lane weights")
    _exact_fields(weights, frozenset({"exact", "lexical", "vector"}), "lane weights")
    if weights != _QUALIFIED_LANE_WEIGHTS:
        _fail(
            "METHOD_PROFILE_VALUE_UNSUPPORTED",
            "lane weights must match the frozen V13-32 retrieval profile.",
        )
    if reranker["enabled"] is not False:
        _fail("METHOD_PROFILE_VALUE_UNSUPPORTED", "a learned reranker is not qualified.")

    provisional = RetrievalProfile(
        schema_version=3,
        chunk_method_profile_id=chunk_identity,
        explicit_page_route=_literal(
            exact["explicit_page_route"], "document_identifier_plus_page", "explicit page route"
        ),
        exact_candidate_depth=_integer(exact["candidate_depth"], "exact candidate depth", 1, 100),
        lexical_search_config=_literal(lexical["search_config"], "english", "lexical search config"),
        lexical_fallback=_literal(
            lexical["fallback"], "native_or_when_strict_empty", "lexical fallback"
        ),
        lexical_candidate_depth=_integer(
            lexical["candidate_depth"], "lexical candidate depth", 1, 100
        ),
        vector_distance=_literal(vector["distance"], "cosine", "vector distance"),
        vector_candidate_depth=_integer(
            vector["candidate_depth"], "vector candidate depth", 1, 100
        ),
        fusion_algorithm=_literal(
            fusion["algorithm"], "reciprocal_rank_fusion", "fusion algorithm"
        ),
        fused_candidate_depth=_integer(
            fusion["candidate_depth"], "fused candidate depth", 1, 100
        ),
        rrf_constant=_integer(fusion["rrf_constant"], "RRF constant", 1, 1000),
        exact_weight=_QUALIFIED_LANE_WEIGHTS["exact"],
        lexical_weight=_QUALIFIED_LANE_WEIGHTS["lexical"],
        vector_weight=_QUALIFIED_LANE_WEIGHTS["vector"],
        learned_reranker=False,
        section_page_representatives=(
            representation["section_page_representatives"] is True
        ),
        document_local_duplicate_canonicalization=(
            representation["document_local_duplicate_canonicalization"] is True
        ),
        representative_evidence=_literal(
            representation["representative_evidence"],
            "expand_to_ordered_atomic_members",
            "representative evidence",
        ),
        document_shortlist_per_lane=_integer(
            expansion["document_shortlist_per_lane"],
            "document shortlist per lane", 5, 5,
        ),
        expansion_baseline_weight=_integer(
            expansion["baseline_weight"], "expansion baseline weight", 2, 2
        ),
        expansion_best_facet_weight=_integer(
            expansion["best_facet_weight"], "expansion best-facet weight", 1, 1
        ),
        expansion_facet_coverage_weight=_integer(
            expansion["facet_coverage_weight"], "expansion facet-coverage weight", 1, 1
        ),
        digest="",
    )
    if not (
        provisional.section_page_representatives
        and provisional.document_local_duplicate_canonicalization
    ):
        _fail(
            "METHOD_PROFILE_VALUE_UNSUPPORTED",
            "the frozen V13-32 candidate representation must remain enabled.",
        )
    expected_expansion = {
        "enabled": True,
        "route": "ordinary_body_excluding_metadata_relationship_page",
        "query_decomposition": "literal_clauses_v1",
        "maximum_facets": 4,
        "minimum_facet_words": 3,
        "document_shortlist_per_lane": 5,
        "baseline_weight": 2,
        "best_facet_weight": 1,
        "facet_coverage_weight": 1,
    }
    if dict(expansion) != expected_expansion:
        _fail(
            "METHOD_PROFILE_VALUE_UNSUPPORTED",
            "candidate expansion must match the frozen V13-47 profile.",
        )
    if (
        calibration["enabled"] is not True
        or _literal(
            calibration["algorithm"],
            "query_local_min_max_global_v1",
            "score calibration algorithm",
        ) != "query_local_min_max_global_v1"
        or _literal(
            calibration["tie_breaks"],
            "heading_baseline_source_rank_chunk_id",
            "score calibration tie breaks",
        ) != "heading_baseline_source_rank_chunk_id"
    ):
        _fail("METHOD_PROFILE_VALUE_UNSUPPORTED", "score calibration is not qualified.")
    for name, expected in {
        "original_lexical": 1.0,
        "original_vector": 3.0,
        "vector_facet_coverage": 1.0,
        "document_lexical_affinity": 1.0,
        "heading_path_overlap": 0.10,
    }.items():
        _number(calibration_weights[name], expected, f"{name} weight")
    canonical = provisional.canonical()
    return replace(
        provisional,
        digest=domain_digest("ishikawa.retrieval-profile.v1", canonical),
    )


ACCEPTED_RETRIEVAL_PROFILE_VALUE: dict[str, Any] = {
    "schema_version": 3,
    "chunk_method_profile_id": "d72a07f81eabc1f521ab1fd54f84289979365c6c71f8e3220a53b1e8c9a1c037",
    "retrieval": {
        "exact": {
            "explicit_page_route": "document_identifier_plus_page",
            "candidate_depth": 1,
        },
        "lexical": {
            "search_config": "english",
            "fallback": "native_or_when_strict_empty",
            "candidate_depth": 20,
        },
        "vector": {"distance": "cosine", "candidate_depth": 20},
        "fusion": {
            "algorithm": "reciprocal_rank_fusion",
            "candidate_depth": 20,
            "rrf_constant": 60,
            "lane_weights": {"exact": 1, "lexical": 2, "vector": 4},
        },
        "reranker": {"enabled": False},
        "candidate_representation": {
            "section_page_representatives": True,
            "document_local_duplicate_canonicalization": True,
            "representative_evidence": "expand_to_ordered_atomic_members",
        },
        "candidate_expansion": {
            "enabled": True,
            "route": "ordinary_body_excluding_metadata_relationship_page",
            "query_decomposition": "literal_clauses_v1",
            "maximum_facets": 4,
            "minimum_facet_words": 3,
            "document_shortlist_per_lane": 5,
            "baseline_weight": 2,
            "best_facet_weight": 1,
            "facet_coverage_weight": 1,
        },
        "score_calibration": {
            "enabled": True,
            "algorithm": "query_local_min_max_global_v1",
            "weights": {
                "original_lexical": 1.0,
                "original_vector": 3.0,
                "vector_facet_coverage": 1.0,
                "document_lexical_affinity": 1.0,
                "heading_path_overlap": 0.10,
            },
            "tie_breaks": "heading_baseline_source_rank_chunk_id",
        },
    },
}
ACCEPTED_RETRIEVAL_PROFILE = validate_retrieval_profile(ACCEPTED_RETRIEVAL_PROFILE_VALUE)

