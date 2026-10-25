#!/usr/bin/env python3
"""Measure the frozen 60-case Ishikawa retrieval-only MRR gate."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from dataclasses import dataclass, replace
from fractions import Fraction
from pathlib import Path
from typing import Any, Sequence


EXPECTED_CASE_COUNT = 60
MRR_THRESHOLD = Fraction(85, 100)


class ExtendedEvaluationError(RuntimeError):
    """Stable, content-free evaluation failure."""


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise ExtendedEvaluationError(reason)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


@dataclass(frozen=True, slots=True)
class EvidenceTarget:
    display_name: str
    page: int


@dataclass(frozen=True, slots=True)
class ExtendedCase:
    case_id: str
    question: str
    query_sha256: str
    relevant_evidence: tuple[EvidenceTarget, ...]


def load_cases(path: Path) -> tuple[ExtendedCase, ...]:
    require(path.is_absolute() and path.is_file() and not path.is_symlink(), "case_set_unsafe")
    require(path.stat().st_size <= 1024 * 1024, "case_set_too_large")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ExtendedEvaluationError("case_set_invalid") from error
    require(
        isinstance(value, dict)
        and set(value) == {
            "artifact_kind", "cases", "manual_review_required", "metric",
            "schema_version", "synthetic_content_only",
        }
        and value.get("artifact_kind") == "ishikawa_extended_retrieval_mrr_cases"
        and value.get("schema_version") == 1
        and value.get("synthetic_content_only") is True
        and value.get("manual_review_required") is False
        and value.get("metric") == "MRR@20"
        and isinstance(value.get("cases"), list)
        and len(value["cases"]) == EXPECTED_CASE_COUNT,
        "case_set_contract_invalid",
    )
    cases: list[ExtendedCase] = []
    seen: set[str] = set()
    expected_ids = {f"E-{index:03d}" for index in range(1, EXPECTED_CASE_COUNT + 1)}
    for item in value["cases"]:
        require(
            isinstance(item, dict)
            and set(item) == {"case_id", "question", "relevant_evidence"}
            and isinstance(item.get("case_id"), str)
            and item["case_id"] not in seen
            and isinstance(item.get("question"), str)
            and item["question"].strip() == item["question"]
            and 1 <= len(item["question"]) <= 4096
            and "\x00" not in item["question"]
            and isinstance(item.get("relevant_evidence"), list)
            and item["relevant_evidence"],
            "case_contract_invalid",
        )
        targets: list[EvidenceTarget] = []
        for target in item["relevant_evidence"]:
            require(
                isinstance(target, dict)
                and set(target) == {"display_name", "page"}
                and isinstance(target.get("display_name"), str)
                and target["display_name"].strip() == target["display_name"]
                and 1 <= len(target["display_name"]) <= 256
                and type(target.get("page")) is int
                and 1 <= target["page"] <= 999999,
                "relevance_target_invalid",
            )
            targets.append(EvidenceTarget(target["display_name"], target["page"]))
        seen.add(item["case_id"])
        cases.append(
            ExtendedCase(
                item["case_id"],
                item["question"],
                hashlib.sha256(item["question"].encode("utf-8")).hexdigest(),
                tuple(targets),
            )
        )
    require(seen == expected_ids, "case_inventory_invalid")
    return tuple(cases)


def matches(record: dict[str, Any], target: EvidenceTarget) -> bool:
    return record["display_name"] == target.display_name and any(
        start <= target.page <= end for start, end in record["pages"]
    )


def metrics_for_ranks(ranks: Sequence[int | None]) -> dict[str, Any]:
    require(len(ranks) == EXPECTED_CASE_COUNT, "rank_count_invalid")
    require(all(rank is None or 1 <= rank <= 20 for rank in ranks), "rank_invalid")
    reciprocal_sum = sum(
        (Fraction(1, rank) if rank is not None else Fraction(0, 1)) for rank in ranks
    )
    mrr = reciprocal_sum / EXPECTED_CASE_COUNT
    return {
        "mrr_at_20": format(float(mrr), ".6f"),
        "mrr_fraction_numerator": mrr.numerator,
        "mrr_fraction_denominator": mrr.denominator,
        "cases_with_relevant_at_20": sum(rank is not None for rank in ranks),
        "cases_with_relevant_at_5": sum(rank is not None and rank <= 5 for rank in ranks),
        "promotion_gate": "pass" if mrr >= MRR_THRESHOLD else "not_met",
    }


def self_test() -> int:
    passing = metrics_for_ranks([1] * 51 + [None] * 9)
    failing = metrics_for_ranks([1] * 50 + [None] * 10)
    require(
        passing["mrr_at_20"] == "0.850000"
        and passing["promotion_gate"] == "pass"
        and failing["mrr_at_20"] == "0.833333"
        and failing["promotion_gate"] == "not_met",
        "metric_self_test_failed",
    )
    print("extended_retrieval_mrr_evaluator_self_test=pass")
    return 0


def run(arguments: argparse.Namespace) -> int:
    python_root = Path(arguments.python_root).resolve(strict=True)
    scripts_root = Path(__file__).resolve().parent
    sys.path.insert(0, str(python_root))
    sys.path.insert(0, str(scripts_root))
    from evaluate_local_retrieval_ranking import (
        load_candidate_metadata,
        merge_exact,
    )
    from ishikawa.canonical import canonical_json_bytes, domain_digest
    from ishikawa.deployment import validate_deployment_profile
    from ishikawa.method_profile import validate_retrieval_profile
    from ishikawa.native_adapters import ACCEPTED_EMBEDDING_SPACE_ID, NativeQueryEmbeddingAdapter
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
    output_path = Path(arguments.output)
    require(
        config_root.is_dir()
        and not config_root.is_symlink()
        and output_path.is_absolute()
        and not output_path.exists()
        and not output_path.is_symlink(),
        "runtime_path_invalid",
    )
    cases_path = Path(arguments.cases).resolve(strict=True)
    cases = load_cases(cases_path)
    deployment = validate_deployment_profile(
        load_restricted_yaml(config_root / "deployment.yaml", label="deployment profile")
    )
    dependencies = validate_runtime_dependencies(
        load_restricted_yaml(config_root / "runtime_dependencies.yaml", label="runtime dependencies")
    )
    profile = validate_retrieval_profile(
        load_restricted_yaml(config_root / "method_profile.yaml", label="method profile")
    )
    database_factory = NativePostgresConnectionFactory(
        deployment.postgresql,
        dependencies,
        ProtectedEnvironmentValue(dependencies.database_credential_environment, os.environ),
    )
    embed_query = NativeQueryEmbeddingAdapter(
        dependencies.embedding_endpoint,
        ProtectedEnvironmentValue(dependencies.embedding_credential_environment, os.environ),
    )

    connection = database_factory()
    results: list[dict[str, Any]] = []
    lane_totals = {"exact": 0, "lexical": 0, "vector": 0, "fused": 0}
    try:
        connection.execute("BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
        boundary = connection.execute(
            """/* ishikawa.extended-mrr.boundary */
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
            """/* ishikawa.extended-mrr.inventory */
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
                        connection, terms[0], page, depth=profile.exact_candidate_depth
                    )
                )
            for term_order, term in enumerate(terms):
                exact_parts.extend(
                    (term_order, item)
                    for item in exact_term_lookup(
                        connection, term, depth=profile.exact_candidate_depth
                    )
                )
            exact = merge_exact(exact_parts, profile.exact_candidate_depth)
            lexical = lexical_search(
                connection,
                case.question,
                depth=profile.lexical_candidate_depth,
                text_search_config=profile.lexical_search_config,
            )
            vector = vector_search(
                connection,
                embedding.vector,
                embedding.embedding_space_id,
                depth=profile.vector_candidate_depth,
            )
            fused = reciprocal_rank_fusion(
                {"exact": exact, "lexical": lexical, "vector": vector},
                rrf_constant=profile.rrf_constant,
                lane_weights={
                    "exact": profile.exact_weight,
                    "lexical": profile.lexical_weight,
                    "vector": profile.vector_weight,
                },
            )[: profile.fused_candidate_depth]
            metadata = load_candidate_metadata(connection, [item.chunk_id for item in fused])
            first_rank = next(
                (
                    rank
                    for rank, candidate in enumerate(fused, start=1)
                    if any(
                        matches(metadata[candidate.chunk_id], target)
                        for target in case.relevant_evidence
                    )
                ),
                None,
            )
            results.append(
                {
                    "case_id": case.case_id,
                    "query_sha256": case.query_sha256,
                    "first_relevant_rank": first_rank,
                    "reciprocal_rank": (
                        "0" if first_rank is None else format(1 / first_rank, ".17g")
                    ),
                }
            )
            for lane_name, lane in (("exact", exact), ("lexical", lexical), ("vector", vector)):
                lane_totals[lane_name] += len(lane)
            lane_totals["fused"] += len(fused)
        connection.execute("ROLLBACK")
    finally:
        connection.close()

    metrics = metrics_for_ranks([item["first_relevant_rank"] for item in results])
    artifact: dict[str, Any] = {
        "artifact_kind": "ishikawa_extended_retrieval_mrr_observation",
        "schema_version": 1,
        "case_set_sha256": sha256_file(cases_path),
        "case_count": EXPECTED_CASE_COUNT,
        "retrieval_profile_id": profile.digest,
        "retrieval_profile": profile.observation_contract(),
        "deployment_profile_id": deployment.digest,
        "runtime_dependency_profile_id": dependencies.digest,
        "embedding_space_id": ACCEPTED_EMBEDDING_SPACE_ID,
        "database_boundary": "repeatable_read_read_only",
        "corpus_inventory": {
            "documents": 6, "pages": 27, "chunks": 126,
            "citations": 126, "embeddings": 126,
        },
        "lane_candidate_totals": lane_totals,
        "metrics": metrics,
        "promotion_gate_basis": "mrr_at_20_only",
        "mrr_threshold": "0.850000",
        "manual_review_performed": False,
        "gemma_contact": False,
        "database_write": False,
        "question_text_retained": False,
        "query_vectors_retained": False,
        "source_text_retained": False,
        "cases": results,
    }
    artifact["observation_set_id"] = domain_digest(
        "ishikawa.extended-retrieval-mrr-observation.v1", artifact
    )
    payload = canonical_json_bytes(artifact) + b"\n"
    descriptor = os.open(output_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)
    print("purpose=measure_extended_ishikawa_retrieval_mrr")
    print("case_count=60;query_embeddings=60;gemma_contact=false;database_write=false")
    print(
        f"mrr_at_20={metrics['mrr_at_20']};mrr_threshold=0.850000;"
        f"relevant_at_5={metrics['cases_with_relevant_at_5']}/60;"
        f"relevant_at_20={metrics['cases_with_relevant_at_20']}/60"
    )
    print(
        f"promotion_gate={metrics['promotion_gate']};gate_basis=mrr_at_20_only;"
        "manual_review_performed=false"
    )
    print(
        f"observation_set_id={artifact['observation_set_id']};"
        f"artifact_sha256={hashlib.sha256(payload).hexdigest()};artifact_bytes={len(payload)}"
    )
    print("extended_retrieval_mrr_evaluator=pass")
    return 0


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--python-root")
    parser.add_argument("--config-root")
    parser.add_argument("--cases")
    parser.add_argument("--output")
    arguments = parser.parse_args()
    if arguments.self_test == arguments.run:
        raise ExtendedEvaluationError("mode_invalid")
    if arguments.run and not all(
        (arguments.python_root, arguments.config_root, arguments.cases, arguments.output)
    ):
        raise ExtendedEvaluationError("argument_missing")
    return arguments


def main() -> int:
    try:
        arguments = parse_arguments()
        return self_test() if arguments.self_test else run(arguments)
    except ExtendedEvaluationError as error:
        print(f"extended_retrieval_mrr_evaluator=blocked;reason={error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("extended_retrieval_mrr_evaluator=blocked;reason=interrupted", file=sys.stderr)
        return 130
    except Exception as error:
        print(
            f"extended_retrieval_mrr_evaluator=blocked;reason=bounded_{type(error).__name__}",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
