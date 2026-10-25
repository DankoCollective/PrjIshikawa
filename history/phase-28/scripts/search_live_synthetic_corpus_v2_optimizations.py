#!/usr/bin/env python3
"""Search bounded retrieval profiles from Script 169's live lane capture."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import sys
from fractions import Fraction
from pathlib import Path
from typing import Any


class LiveOptimizationError(RuntimeError):
    """Stable failure from the live-observation optimization boundary."""


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise LiveOptimizationError(reason)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_json(path: Path) -> dict[str, Any]:
    require(path.is_file() and not path.is_symlink(), "json_input_unsafe")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise LiveOptimizationError("json_input_invalid") from error
    require(isinstance(value, dict), "json_input_invalid")
    return value


def self_test() -> int:
    profile_count = 6 * 7 * 7 * 3 * 3 * 4
    require(profile_count == 10_584, "self_test_failed")
    print("live_synthetic_corpus_v2_optimization_search_self_test=pass")
    return 0


def fuse_live_lanes(
    case: dict[str, Any], profile: dict[str, Any]
) -> list[str]:
    """Replay the captured lanes, preserving deterministic exact priority."""

    weights = {
        "exact": profile["exact_weight"],
        "lexical": profile["lexical_weight"],
        "vector": profile["vector_weight"],
    }
    depths = {
        "exact": len(case["lanes"]["exact"]),
        "lexical": profile["lexical_depth"],
        "vector": profile["vector_depth"],
    }
    accumulated: dict[str, dict[str, Any]] = {}
    for lane in ("exact", "lexical", "vector"):
        for item in case["lanes"][lane][: depths[lane]]:
            chunk_id = item["chunk_id"]
            state = accumulated.setdefault(
                chunk_id,
                {"score": Fraction(0, 1), "exact": False, "ranks": []},
            )
            rank = int(item["rank"])
            state["score"] += Fraction(
                weights[lane], profile["rrf_constant"] + rank
            )
            state["ranks"].append(rank)
            state["exact"] = state["exact"] or lane == "exact"
    return sorted(
        accumulated,
        key=lambda chunk_id: (
            -int(accumulated[chunk_id]["exact"]),
            -accumulated[chunk_id]["score"],
            min(accumulated[chunk_id]["ranks"]),
            chunk_id,
        ),
    )


def evaluate_live_profile(
    cached: Any,
    cases: list[dict[str, Any]],
    inventory: dict[str, dict[str, Any]],
    profile: dict[str, Any],
    baseline_ranks: dict[str, int],
    e032_digest: str,
) -> dict[str, Any]:
    """Apply the accepted scorer to one profile over captured live lanes."""

    body_results: list[dict[str, Any]] = []
    body_equivalence_results: list[dict[str, Any]] = []
    header_results: list[dict[str, Any]] = []
    case_ranks: dict[str, int | None] = {}
    for case in cases:
        fused = fuse_live_lanes(case, profile)
        diversified = cached._diversify(
            fused, inventory, profile["diversification"]
        )
        strict = cached._case_metrics(case, diversified, inventory)
        case_ranks[case["case_id"]] = strict["first_relevant_rank"]
        if case["family"] == "body":
            body_results.append(strict)
            body_equivalence_results.append(
                cached._case_metrics(
                    case,
                    diversified,
                    inventory,
                    e032_digest if case["case_id"] == "E-032" else None,
                )
            )
        else:
            header_results.append(strict)
    body = cached._aggregate(body_results)
    body_equivalence = cached._aggregate(body_equivalence_results)
    header = cached._aggregate(header_results)
    for metrics, count in ((body, 60), (body_equivalence, 60), (header, 8)):
        metrics["case_count"] = count
    regressed = [
        case_id
        for case_id, rank in case_ranks.items()
        if case_id.startswith("E-")
        and (rank is None or rank > baseline_ranks[case_id])
    ]
    improved = [
        case_id
        for case_id, rank in case_ranks.items()
        if case_id.startswith("E-")
        and rank is not None
        and rank < baseline_ranks[case_id]
    ]
    eligible = (
        Fraction(body["mrr_fraction_numerator"], body["mrr_fraction_denominator"])
        > Fraction(91, 100)
        and body["relevant_at_20"] == 60
        and header["relevant_at_5"] == 8
        and header["required_evidence_matched_at_20"]
        == header["required_evidence_total"]
    )
    return {
        "profile": profile,
        "body_metrics": body,
        "body_equivalence_diagnostic": body_equivalence,
        "header_metrics": header,
        "strict_gate_met": eligible,
        "regressed_body_case_ids": regressed,
        "improved_body_case_ids": improved,
        "profile_distance_from_current": cached._profile_distance(profile),
        "case_ranks": case_ranks,
    }


def execute(arguments: argparse.Namespace) -> int:
    scripts_root = Path(arguments.scripts_root).resolve(strict=True)
    python_root = Path(arguments.python_root).resolve(strict=True)
    promotion_bundle = Path(arguments.promotion_bundle).resolve(strict=True)
    output_path = Path(arguments.output)
    require(not output_path.exists() and not output_path.is_symlink(), "output_exists")
    sys.path.insert(0, str(scripts_root))
    sys.path.insert(0, str(python_root))

    import search_synthetic_corpus_v2_optimizations as cached
    from ishikawa.artifact_adapter import load_prepared_documents
    from ishikawa.canonical import domain_digest, file_sha256
    from ishikawa.operator_ingestion import (
        OperatorIngestionPaths,
        load_operator_configuration,
    )
    from ishikawa.persistence import (
        _artifact_set_id,
        _document_id,
        _document_version_id,
    )

    observation_path = Path(arguments.observation).resolve(strict=True)
    normalized_path = Path(arguments.normalized).resolve(strict=True)
    chunks_path = Path(arguments.chunks).resolve(strict=True)
    embeddings_path = Path(arguments.embeddings).resolve(strict=True)
    observation = load_json(observation_path)
    chunk_artifact = load_json(chunks_path)
    require(
        observation.get("artifact_kind")
        == "ishikawa_live_synthetic_corpus_v2_retrieval_observation"
        and observation.get("schema_version") == 1
        and observation.get("database_boundary")
        == "isolated_postgresql_repeatable_read_read_only"
        and observation.get("corpus_inventory")
        == {
            "documents": 6,
            "pages": 26,
            "chunks": 139,
            "citations": 139,
            "embeddings": 139,
            "metadata_candidates": 6,
        }
        and observation.get("database_write") is False
        and observation.get("gemma_contact") is False
        and observation.get("optimization_gate_used") is False,
        "observation_contract_invalid",
    )
    require(
        observation.get("body_metrics", {}).get("mrr_at_20") == "0.873056"
        and observation.get("body_metrics", {}).get("relevant_at_20") == 60
        and observation.get("header_metrics", {}).get("mrr_at_20") == "1.000000"
        and observation.get("header_metrics", {}).get("relevant_at_5") == 8
        and observation.get("header_metrics", {}).get(
            "required_evidence_matched_at_20"
        )
        == 11,
        "accepted_live_metrics_changed",
    )
    require(
        chunk_artifact.get("artifact_kind")
        == "non_publishable_structural_chunk_candidates"
        and chunk_artifact.get("publication_eligible") is False,
        "chunk_artifact_contract_invalid",
    )

    config_root = promotion_bundle / "config"
    source_root = promotion_bundle / "source"
    paths = OperatorIngestionPaths(
        config_root / "document_classes.yaml",
        config_root / "document_catalog.yaml",
        config_root / "ingestion_manifest.yaml",
        source_root,
        output_path.parent,
    )
    _registry, _catalog, manifest = load_operator_configuration(paths)
    prepared = load_prepared_documents(
        normalized_path=normalized_path,
        normalized_sha256=file_sha256(str(normalized_path)),
        chunk_path=chunks_path,
        chunk_sha256=file_sha256(str(chunks_path)),
        embedding_path=embeddings_path,
        embedding_sha256=file_sha256(str(embeddings_path)),
        manifest=manifest,
        source_root=source_root,
    )
    raw_by_producer = {
        candidate["chunk_id"]: (document["document_ref"], candidate)
        for document in chunk_artifact["documents"]
        for candidate in document["candidates"]
    }
    require(len(raw_by_producer) == 139, "producer_inventory_invalid")
    key_to_ref = {
        "policy.ops-17-control-2001": "SYN-V2-001",
        "policy.ops-17-control-2002": "SYN-V2-002",
        "policy.schedule-2003": "SYN-V2-003",
        "form.tst-9001": "SYN-V2-004",
        "policy.governance-manual": "SYN-V2-005",
        "procedure.incident-reporting": "SYN-V2-006",
    }
    inventory: dict[str, dict[str, Any]] = {}
    consumed_producer_ids: set[str] = set()
    for document in prepared:
        require(document.document_key in key_to_ref, "document_key_unexpected")
        document_id = _document_id(document.document_key)
        version_id = _document_version_id(document_id, document.source_digest)
        artifact_set_id = _artifact_set_id(
            version_id, chunk_artifact["method_profile_id"], document.class_id
        )
        for chunk in document.chunks:
            producer_chunk_id = chunk.client_metadata.get("producer_chunk_id")
            raw = raw_by_producer.get(producer_chunk_id)
            require(
                raw is not None and producer_chunk_id not in consumed_producer_ids,
                "producer_mapping_invalid",
            )
            _producer_document_ref, candidate = raw
            require(
                candidate["retrieval_text"] == chunk.retrieval_text
                and candidate["projection_kind"] == chunk.projection_kind
                and candidate["retrieval_filters"] == chunk.retrieval_filters
                and candidate["citation_anchor"]["page_start"] == chunk.page_start
                and candidate["citation_anchor"]["page_end"] == chunk.page_end,
                "producer_projection_changed",
            )
            retrieval_digest = domain_digest(
                "ishikawa.retrieval-text.v1", chunk.retrieval_text
            )
            published_chunk_id = domain_digest(
                "ishikawa.chunk.v1",
                {
                    "artifact_set_id": artifact_set_id,
                    "ordinal": chunk.ordinal,
                    "digest": retrieval_digest,
                },
            )
            require(published_chunk_id not in inventory, "published_identity_duplicate")
            inventory[published_chunk_id] = {
                "chunk_id": published_chunk_id,
                "document_ref": key_to_ref[document.document_key],
                "page_start": chunk.page_start,
                "page_end": chunk.page_end,
                "projection_kind": chunk.projection_kind,
                "source_unit_ids": tuple(candidate["source_unit_ids"]),
                "content_digest": candidate["content_digest"],
            }
            consumed_producer_ids.add(producer_chunk_id)
    require(
        len(inventory) == 139
        and consumed_producer_ids == set(raw_by_producer),
        "published_inventory_invalid",
    )

    cases = observation.get("cases")
    require(isinstance(cases, list) and len(cases) == 68, "case_inventory_invalid")
    observed_chunk_ids: set[str] = set()
    for case in cases:
        require(
            isinstance(case, dict)
            and isinstance(case.get("family"), str)
            and bool(case["family"]),
            "case_contract_invalid",
        )
        for lane_name in ("exact", "lexical", "vector"):
            lane = case.get("lanes", {}).get(lane_name)
            require(isinstance(lane, list), "lane_contract_invalid")
            for item in lane:
                expected = inventory.get(item.get("chunk_id"))
                require(
                    expected is not None
                    and item.get("document_ref") == expected["document_ref"]
                    and item.get("page_start") == expected["page_start"]
                    and item.get("page_end") == expected["page_end"],
                    "lane_inventory_mismatch",
                )
                observed_chunk_ids.add(item["chunk_id"])
    require(len(observed_chunk_ids) == 135, "observed_lane_inventory_changed")

    baseline_ranks = {
        case["case_id"]: int(case["first_relevant_rank"])
        for case in cases
        if case["family"] == "body"
    }
    require(len(baseline_ranks) == 60, "body_baseline_inventory_invalid")
    e032 = next(case for case in cases if case["case_id"] == "E-032")
    e032_chunk_id = e032["fused"][int(e032["first_relevant_rank"]) - 1]["chunk_id"]
    e032_digest = inventory[e032_chunk_id]["content_digest"]

    results: list[dict[str, Any]] = []
    for rrf_constant in cached.RRF_CONSTANTS:
        for lexical_weight in cached.LEXICAL_WEIGHTS:
            for vector_weight in cached.VECTOR_WEIGHTS:
                for lexical_depth in cached.LANE_DEPTHS:
                    for vector_depth in cached.LANE_DEPTHS:
                        for diversification in cached.DIVERSIFICATION_MODES:
                            profile = {
                                "rrf_constant": rrf_constant,
                                "exact_weight": 1,
                                "lexical_weight": lexical_weight,
                                "vector_weight": vector_weight,
                                "lexical_depth": lexical_depth,
                                "vector_depth": vector_depth,
                                "diversification": diversification,
                            }
                            results.append(
                                evaluate_live_profile(
                                    cached,
                                    cases,
                                    inventory,
                                    profile,
                                    baseline_ranks,
                                    e032_digest,
                                )
                            )
    require(len(results) == 10_584, "search_space_invalid")
    results.sort(key=cached._sort_key)
    current = next(
        result for result in results if result["profile"] == cached.CURRENT_PROFILE
    )
    require(
        current["body_metrics"] == observation["body_metrics"]
        and current["header_metrics"] == observation["header_metrics"],
        "live_lane_replay_drift",
    )
    strict_gate_count = sum(result["strict_gate_met"] for result in results)
    finalists = copy.deepcopy(results[:25])
    for result in finalists:
        result.pop("case_ranks")
    best = finalists[0]
    output = {
        "schema_version": 1,
        "artifact_kind": "ishikawa_live_synthetic_corpus_v2_optimization_search",
        "source_sha256": {
            "live_observation": sha256_file(observation_path),
            "normalized_artifact": sha256_file(normalized_path),
            "chunk_artifact": sha256_file(chunks_path),
            "embedding_artifact": sha256_file(embeddings_path),
        },
        "published_inventory": {
            "chunks": len(inventory),
            "chunks_observed_in_lanes": len(observed_chunk_ids),
            "producer_to_published_identity_verified": True,
        },
        "search_space": {
            "rrf_constants": list(cached.RRF_CONSTANTS),
            "lexical_weights": list(cached.LEXICAL_WEIGHTS),
            "vector_weights": list(cached.VECTOR_WEIGHTS),
            "lexical_depths": list(cached.LANE_DEPTHS),
            "vector_depths": list(cached.LANE_DEPTHS),
            "diversification_modes": list(cached.DIVERSIFICATION_MODES),
            "profile_count": len(results),
            "cached_live_lane_depth_limit": 20,
        },
        "selection_rules": {
            "strict_body_mrr_target": "greater_than_0.91",
            "strict_body_relevant_at_20": 60,
            "header_relevant_at_5": 8,
            "header_required_evidence_at_20": 11,
            "e032_content_equivalence_is_diagnostic_only": True,
            "offline_profile_promotion": False,
        },
        "current_profile_replay": current,
        "strict_gate_profile_count": strict_gate_count,
        "finalists": finalists,
        "best_profile": best,
        "boundaries": {
            "accepted_live_lane_replay_only": True,
            "database_contact": False,
            "model_contact": False,
            "credential_read": False,
            "black_corpus_access": False,
            "truth_changed": False,
            "corpus_changed": False,
            "retrieval_source_changed": False,
            "production_profile_changed": False,
            "retrieval_profile_promotion_authorized": False,
        },
        "next_gate": "review_published_atomic_rank_failures_before_new_retrieval_candidate_design",
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(output, indent=2, sort_keys=True) + "\n"
    with output_path.open("x", encoding="utf-8") as stream:
        stream.write(payload)
    print("purpose=search_published_v2_live_lane_retrieval_optimizations")
    print(
        f"profiles={len(results)};strict_gate_profiles={strict_gate_count};"
        f"current_body_mrr_at_20={current['body_metrics']['mrr_at_20']}"
    )
    print(
        f"best_body_mrr_at_20={best['body_metrics']['mrr_at_20']};"
        f"best_body_relevant_at_5={best['body_metrics']['relevant_at_5']}/60;"
        f"best_body_relevant_at_20={best['body_metrics']['relevant_at_20']}/60"
    )
    print(
        f"best_header_mrr_at_20={best['header_metrics']['mrr_at_20']};"
        f"best_header_relevant_at_5={best['header_metrics']['relevant_at_5']}/8;"
        f"best_header_required_evidence_at_20="
        f"{best['header_metrics']['required_evidence_matched_at_20']}/11"
    )
    print(
        f"best_regressed_body_cases={len(best['regressed_body_case_ids'])};"
        "retrieval_profile_promotion_authorized=false"
    )
    print(f"optimization_artifact_sha256={hashlib.sha256(payload.encode()).hexdigest()}")
    print("live_synthetic_corpus_v2_optimization_search=pass")
    return 0


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--scripts-root")
    parser.add_argument("--python-root")
    parser.add_argument("--promotion-bundle")
    parser.add_argument("--observation")
    parser.add_argument("--normalized")
    parser.add_argument("--chunks")
    parser.add_argument("--embeddings")
    parser.add_argument("--output")
    arguments = parser.parse_args()
    if arguments.self_test == arguments.run:
        raise LiveOptimizationError("mode_invalid")
    required = (
        arguments.scripts_root,
        arguments.python_root,
        arguments.promotion_bundle,
        arguments.observation,
        arguments.normalized,
        arguments.chunks,
        arguments.embeddings,
        arguments.output,
    )
    if arguments.run and not all(required):
        raise LiveOptimizationError("argument_missing")
    return arguments


def main() -> int:
    try:
        arguments = parse_arguments()
        return self_test() if arguments.self_test else execute(arguments)
    except LiveOptimizationError as error:
        print(
            f"live_synthetic_corpus_v2_optimization_search=blocked;reason={error}",
            file=sys.stderr,
        )
        return 1
    except Exception as error:
        print(
            "live_synthetic_corpus_v2_optimization_search=blocked;"
            f"reason=bounded_{type(error).__name__}",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
