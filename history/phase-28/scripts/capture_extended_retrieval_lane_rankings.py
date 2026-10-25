#!/usr/bin/env python3
"""Capture content-free lane rankings for the frozen 60-case retrieval set.

The retained artifact contains stable chunk identities, ranks, and relevance
booleans. It excludes questions, source text, vectors, credentials, and model
responses. The accepted profile is reproduced before the observation can pass.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from fractions import Fraction
from pathlib import Path
from typing import Any, Mapping, Sequence


EXPECTED_CASE_COUNT = 60
CAPTURE_DEPTH = 20
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


class LaneCaptureError(RuntimeError):
    """Stable, content-free capture failure."""


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise LaneCaptureError(reason)


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
        raise LaneCaptureError("json_input_invalid") from error


def load_baseline_ranks(path: Path) -> tuple[str, Mapping[str, int]]:
    value = load_json(path, 1024 * 1024)
    metrics = value.get("metrics") if isinstance(value, dict) else None
    cases = value.get("cases") if isinstance(value, dict) else None
    require(
        value.get("artifact_kind") == "ishikawa_extended_retrieval_mrr_observation"
        and value.get("schema_version") == 1
        and value.get("case_count") == EXPECTED_CASE_COUNT
        and value.get("retrieval_profile") == EXPECTED_PROFILE
        and value.get("database_boundary") == "repeatable_read_read_only"
        and isinstance(metrics, dict)
        and metrics.get("mrr_fraction_numerator") == 28633
        and metrics.get("mrr_fraction_denominator") == 33600
        and metrics.get("mrr_at_20") == "0.852173"
        and metrics.get("cases_with_relevant_at_20") == EXPECTED_CASE_COUNT
        and isinstance(cases, list)
        and len(cases) == EXPECTED_CASE_COUNT,
        "baseline_observation_contract_invalid",
    )
    ranks: dict[str, int] = {}
    for item in cases:
        require(
            isinstance(item, dict)
            and isinstance(item.get("case_id"), str)
            and type(item.get("first_relevant_rank")) is int
            and 1 <= item["first_relevant_rank"] <= 20
            and item["case_id"] not in ranks,
            "baseline_rank_contract_invalid",
        )
        ranks[item["case_id"]] = item["first_relevant_rank"]
    require(
        set(ranks) == {f"E-{index:03d}" for index in range(1, 61)},
        "baseline_rank_inventory_invalid",
    )
    observation_id = value.get("observation_set_id")
    require(
        isinstance(observation_id, str)
        and len(observation_id) == 64
        and all(character in "0123456789abcdef" for character in observation_id),
        "baseline_observation_identity_invalid",
    )
    return observation_id, ranks


def reciprocal_metrics(ranks: Sequence[int]) -> tuple[Fraction, int, int]:
    require(
        len(ranks) == EXPECTED_CASE_COUNT
        and all(type(rank) is int and 1 <= rank <= 20 for rank in ranks),
        "rank_contract_invalid",
    )
    mrr = sum(Fraction(1, rank) for rank in ranks) / EXPECTED_CASE_COUNT
    return mrr, sum(rank <= 5 for rank in ranks), len(ranks)


def lane_record(candidate: Any, relevant: bool) -> dict[str, Any]:
    return {
        "chunk_id": candidate.chunk_id,
        "rank": candidate.rank,
        "relevant": relevant,
    }


def self_test() -> int:
    ranks = [1] * 48 + [2] + [3] * 6 + [5, 7, 8, 10, 16]
    mrr, top_five, top_twenty = reciprocal_metrics(ranks)
    require(
        mrr == Fraction(28633, 33600)
        and format(float(mrr), ".6f") == "0.852173"
        and top_five == 56
        and top_twenty == 60,
        "metric_self_test_failed",
    )
    print("extended_retrieval_lane_capture_self_test=pass")
    return 0


def run(arguments: argparse.Namespace) -> int:
    python_root = Path(arguments.python_root).resolve(strict=True)
    scripts_root = Path(__file__).resolve().parent
    sys.path.insert(0, str(python_root))
    sys.path.insert(0, str(scripts_root))
    from evaluate_extended_retrieval_mrr import load_cases, matches
    from evaluate_local_retrieval_ranking import load_candidate_metadata, merge_exact
    from ishikawa.canonical import canonical_json_bytes, domain_digest
    from ishikawa.deployment import validate_deployment_profile
    from ishikawa.method_profile import validate_retrieval_profile
    from ishikawa.native_adapters import (
        ACCEPTED_EMBEDDING_SPACE_ID,
        NativeQueryEmbeddingAdapter,
    )
    from ishikawa.retrieval import (
        exact_document_page_lookup,
        exact_term_lookup,
        extract_explicit_page,
        extract_structured_terms,
        lexical_search,
        reciprocal_rank_fusion,
        vector_search,
    )
    from ishikawa.runtime import (
        NativePostgresConnectionFactory,
        ProtectedEnvironmentValue,
        validate_runtime_dependencies,
    )
    from ishikawa.yaml_loader import load_restricted_yaml

    config_root = Path(arguments.config_root).resolve(strict=True)
    cases_path = Path(arguments.cases).resolve(strict=True)
    baseline_path = Path(arguments.baseline_observation).resolve(strict=True)
    output_path = Path(arguments.output)
    require(
        config_root.is_dir()
        and not config_root.is_symlink()
        and output_path.is_absolute()
        and not output_path.exists()
        and not output_path.is_symlink(),
        "runtime_path_invalid",
    )
    cases = load_cases(cases_path)
    baseline_observation_id, baseline_ranks = load_baseline_ranks(baseline_path)
    deployment = validate_deployment_profile(
        load_restricted_yaml(config_root / "deployment.yaml", label="deployment profile")
    )
    dependencies = validate_runtime_dependencies(
        load_restricted_yaml(
            config_root / "runtime_dependencies.yaml", label="runtime dependencies"
        )
    )
    profile = validate_retrieval_profile(
        load_restricted_yaml(config_root / "method_profile.yaml", label="method profile")
    )
    require(profile.observation_contract() == EXPECTED_PROFILE, "retrieval_profile_invalid")
    database_factory = NativePostgresConnectionFactory(
        deployment.postgresql,
        dependencies,
        ProtectedEnvironmentValue(
            dependencies.database_credential_environment, os.environ
        ),
    )
    embed_query = NativeQueryEmbeddingAdapter(
        dependencies.embedding_endpoint,
        ProtectedEnvironmentValue(
            dependencies.embedding_credential_environment, os.environ
        ),
    )

    connection = database_factory()
    observations: list[dict[str, Any]] = []
    lane_totals = {"exact": 0, "lexical": 0, "vector": 0}
    try:
        connection.execute("BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
        boundary = connection.execute(
            """/* ishikawa.extended-lane-capture.boundary */
            SELECT current_user, current_database(),
                   current_setting('transaction_read_only'),
                   current_setting('transaction_isolation')
            """
        ).fetchone()
        require(
            boundary == ("rag_retrieval", "rag_catalog", "on", "repeatable read"),
            "database_boundary_invalid",
        )
        inventory = connection.execute(
            """/* ishikawa.extended-lane-capture.inventory */
            SELECT
              (SELECT count(*) FROM rag_search.active_documents),
              (SELECT coalesce(sum(page_count), 0) FROM rag_search.active_documents),
              (SELECT count(*) FROM rag_search.active_chunks),
              (SELECT count(*) FROM rag_search.active_citations),
              (SELECT count(*) FROM rag_search.active_embeddings)
            """
        ).fetchone()
        require(inventory == (6, 27, 126, 126, 126), "corpus_inventory_invalid")

        for case in cases:
            embedding = embed_query(case.question)
            require(
                embedding.embedding_space_id == ACCEPTED_EMBEDDING_SPACE_ID,
                "embedding_space_invalid",
            )
            terms = extract_structured_terms(case.question)
            page = extract_explicit_page(case.question)
            exact_parts: list[tuple[int, Any]] = []
            if page is not None and len(terms) == 1:
                exact_parts.extend(
                    (-1, item)
                    for item in exact_document_page_lookup(
                        connection, terms[0], page, depth=CAPTURE_DEPTH
                    )
                )
            for term_order, term in enumerate(terms):
                exact_parts.extend(
                    (term_order, item)
                    for item in exact_term_lookup(
                        connection, term, depth=CAPTURE_DEPTH
                    )
                )
            exact = merge_exact(exact_parts, CAPTURE_DEPTH)
            lexical = lexical_search(
                connection,
                case.question,
                depth=CAPTURE_DEPTH,
                text_search_config=profile.lexical_search_config,
            )
            vector = vector_search(
                connection,
                embedding.vector,
                embedding.embedding_space_id,
                depth=CAPTURE_DEPTH,
            )
            current_fused = reciprocal_rank_fusion(
                {
                    "exact": exact[: profile.exact_candidate_depth],
                    "lexical": lexical[: profile.lexical_candidate_depth],
                    "vector": vector[: profile.vector_candidate_depth],
                },
                rrf_constant=profile.rrf_constant,
                lane_weights={
                    "exact": profile.exact_weight,
                    "lexical": profile.lexical_weight,
                    "vector": profile.vector_weight,
                },
            )[: profile.fused_candidate_depth]
            all_ids = [
                candidate.chunk_id
                for lane in (exact, lexical, vector)
                for candidate in lane
            ]
            metadata = load_candidate_metadata(connection, all_ids)

            def is_relevant(candidate: Any) -> bool:
                return any(
                    matches(metadata[candidate.chunk_id], target)
                    for target in case.relevant_evidence
                )

            current_rank = next(
                (
                    rank
                    for rank, candidate in enumerate(current_fused, start=1)
                    if is_relevant(candidate)
                ),
                None,
            )
            require(
                current_rank == baseline_ranks[case.case_id],
                "baseline_rank_reproduction_failed",
            )
            observations.append(
                {
                    "case_id": case.case_id,
                    "query_sha256": case.query_sha256,
                    "relevance_target_count": len(case.relevant_evidence),
                    "current_first_relevant_rank": current_rank,
                    "lanes": {
                        "exact": [lane_record(item, is_relevant(item)) for item in exact],
                        "lexical": [
                            lane_record(item, is_relevant(item)) for item in lexical
                        ],
                        "vector": [
                            lane_record(item, is_relevant(item)) for item in vector
                        ],
                    },
                }
            )
            for name, lane in (("exact", exact), ("lexical", lexical), ("vector", vector)):
                lane_totals[name] += len(lane)
        connection.execute("ROLLBACK")
    finally:
        connection.close()

    current_ranks = [item["current_first_relevant_rank"] for item in observations]
    mrr, top_five, top_twenty = reciprocal_metrics(current_ranks)
    require(
        mrr == Fraction(28633, 33600)
        and top_five == 56
        and top_twenty == EXPECTED_CASE_COUNT,
        "baseline_metric_reproduction_failed",
    )
    artifact: dict[str, Any] = {
        "artifact_kind": "ishikawa_extended_retrieval_lane_ranking_observation",
        "schema_version": 1,
        "case_set_sha256": sha256_file(cases_path),
        "baseline_observation_sha256": sha256_file(baseline_path),
        "baseline_observation_set_id": baseline_observation_id,
        "case_count": EXPECTED_CASE_COUNT,
        "query_embedding_count": EXPECTED_CASE_COUNT,
        "retrieval_profile_id": profile.digest,
        "retrieval_profile": profile.observation_contract(),
        "capture_depths": {"exact": 20, "lexical": 20, "vector": 20},
        "deployment_profile_id": deployment.digest,
        "runtime_dependency_profile_id": dependencies.digest,
        "embedding_space_id": ACCEPTED_EMBEDDING_SPACE_ID,
        "database_boundary": "repeatable_read_read_only",
        "corpus_inventory": {
            "documents": 6,
            "pages": 27,
            "chunks": 126,
            "citations": 126,
            "embeddings": 126,
        },
        "lane_candidate_totals": lane_totals,
        "reproduced_metrics": {
            "mrr_at_20": "0.852173",
            "mrr_fraction_numerator": mrr.numerator,
            "mrr_fraction_denominator": mrr.denominator,
            "cases_with_relevant_at_5": top_five,
            "cases_with_relevant_at_20": top_twenty,
        },
        "strict_production_target": "greater_than_0.91",
        "baseline_reproduced": True,
        "profile_changed": False,
        "manual_review_performed": False,
        "gemma_contact": False,
        "database_write": False,
        "question_text_retained": False,
        "query_vectors_retained": False,
        "source_text_retained": False,
        "cases": observations,
    }
    artifact["observation_set_id"] = domain_digest(
        "ishikawa.extended-retrieval-lane-ranking-observation.v1", artifact
    )
    payload = canonical_json_bytes(artifact) + b"\n"
    descriptor = os.open(output_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)
    print("purpose=capture_extended_ishikawa_retrieval_lane_rankings")
    print(
        "case_count=60;query_embeddings=60;capture_depths=20,20,20;"
        "gemma_contact=false;database_write=false"
    )
    print(
        "baseline_mrr_at_20=0.852173;baseline_reproduced=true;"
        "relevant_at_5=56/60;relevant_at_20=60/60"
    )
    print(
        f"observation_set_id={artifact['observation_set_id']};"
        f"artifact_sha256={hashlib.sha256(payload).hexdigest()};"
        f"artifact_bytes={len(payload)}"
    )
    print("extended_retrieval_lane_capture=pass;profile_changed=false")
    return 0


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--python-root")
    parser.add_argument("--config-root")
    parser.add_argument("--cases")
    parser.add_argument("--baseline-observation")
    parser.add_argument("--output")
    arguments = parser.parse_args()
    if arguments.self_test == arguments.run:
        raise LaneCaptureError("mode_invalid")
    if arguments.run and not all(
        (
            arguments.python_root,
            arguments.config_root,
            arguments.cases,
            arguments.baseline_observation,
            arguments.output,
        )
    ):
        raise LaneCaptureError("argument_missing")
    return arguments


def main() -> int:
    try:
        arguments = parse_arguments()
        return self_test() if arguments.self_test else run(arguments)
    except LaneCaptureError as error:
        print(f"extended_retrieval_lane_capture=blocked;reason={error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("extended_retrieval_lane_capture=blocked;reason=interrupted", file=sys.stderr)
        return 130
    except Exception as error:
        print(
            f"extended_retrieval_lane_capture=blocked;reason=bounded_{type(error).__name__}",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
