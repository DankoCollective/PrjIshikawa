#!/usr/bin/env python3
"""Measure Ishikawa's frozen retrieval profile against the local corpus.

The retained artifact contains ranks, stable identities, citations, and metric
results. It never contains credentials, query vectors, document text, or the
case questions themselves.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import sys
from dataclasses import dataclass, replace
from fractions import Fraction
from pathlib import Path
from typing import Any, Mapping, Sequence


EXPECTED_CASE_COUNT = 13
EXPECTED_RESPONSIVE_COUNT = 6
EXPECTED_NONRESPONSIVE_COUNT = 6
EXPECTED_EVIDENCE_COUNT = 13
EXPECTED_BROAD_CASE = "B-001"


class EvaluationError(RuntimeError):
    """Stable, content-free evaluator failure."""


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise EvaluationError(reason)


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
        raise EvaluationError("json_input_invalid") from error


@dataclass(frozen=True, slots=True)
class EvidenceExpectation:
    display_name: str
    page: int


@dataclass(frozen=True, slots=True)
class TuningCase:
    case_id: str
    case_class: str
    expected_status: str
    question: str
    query_sha256: str
    required_evidence: tuple[EvidenceExpectation, ...]


def load_cases(path: Path) -> tuple[TuningCase, ...]:
    value = load_json(path, 1024 * 1024)
    require(
        isinstance(value, dict)
        and set(value) == {
            "artifact_kind", "cases", "schema_version", "synthetic_content_only"
        }
        and value.get("artifact_kind") == "ishikawa_retrieval_tuning_cases"
        and value.get("schema_version") == 2
        and value.get("synthetic_content_only") is True
        and isinstance(value.get("cases"), list)
        and len(value["cases"]) == EXPECTED_CASE_COUNT,
        "case_set_contract_invalid",
    )
    cases: list[TuningCase] = []
    seen: set[str] = set()
    allowed = {
        "responsive": "answered",
        "nonresponsive": "insufficient-evidence",
        "broad-navigation": "clarification-required",
    }
    for item in value["cases"]:
        require(
            isinstance(item, dict)
            and set(item) == {
                "case_id", "class", "expected_status", "question", "required_evidence"
            },
            "case_contract_invalid",
        )
        case_id = item["case_id"]
        case_class = item["class"]
        question = item["question"]
        require(
            isinstance(case_id, str)
            and case_id not in seen
            and isinstance(case_class, str)
            and item["expected_status"] == allowed.get(case_class)
            and isinstance(question, str)
            and question.strip() == question
            and 1 <= len(question) <= 4096
            and "\x00" not in question
            and isinstance(item["required_evidence"], list),
            "case_contract_invalid",
        )
        evidence: list[EvidenceExpectation] = []
        for expected in item["required_evidence"]:
            require(
                isinstance(expected, dict)
                and set(expected) == {"display_name", "page"}
                and isinstance(expected["display_name"], str)
                and expected["display_name"].strip() == expected["display_name"]
                and 1 <= len(expected["display_name"]) <= 256
                and type(expected["page"]) is int
                and 1 <= expected["page"] <= 999999,
                "evidence_expectation_invalid",
            )
            evidence.append(EvidenceExpectation(expected["display_name"], expected["page"]))
        require(
            (case_class == "responsive" and bool(evidence))
            or (case_class != "responsive" and not evidence),
            "evidence_expectation_invalid",
        )
        seen.add(case_id)
        cases.append(
            TuningCase(
                case_id,
                case_class,
                item["expected_status"],
                question,
                hashlib.sha256(question.encode("utf-8")).hexdigest(),
                tuple(evidence),
            )
        )
    require(
        sum(item.case_class == "responsive" for item in cases) == EXPECTED_RESPONSIVE_COUNT
        and sum(item.case_class == "nonresponsive" for item in cases)
        == EXPECTED_NONRESPONSIVE_COUNT
        and sum(len(item.required_evidence) for item in cases) == EXPECTED_EVIDENCE_COUNT
        and sum(item.case_id == EXPECTED_BROAD_CASE for item in cases) == 1,
        "case_inventory_invalid",
    )
    return tuple(cases)


def merge_exact(candidates: Sequence[tuple[int, Any]], depth: int) -> tuple[Any, ...]:
    selected: dict[str, tuple[int, Any]] = {}
    for term_order, candidate in candidates:
        ordering = (term_order, candidate.rank, candidate.chunk_id)
        current = selected.get(candidate.chunk_id)
        if current is None or ordering < (
            current[0], current[1].rank, current[1].chunk_id
        ):
            selected[candidate.chunk_id] = (term_order, candidate)
    ordered = sorted(
        selected.values(), key=lambda item: (item[0], item[1].rank, item[1].chunk_id)
    )
    return tuple(
        replace(candidate, rank=rank)
        for rank, (_, candidate) in enumerate(ordered[:depth], start=1)
    )


def load_candidate_metadata(connection: Any, chunk_ids: Sequence[str]) -> dict[str, dict[str, Any]]:
    identities = tuple(dict.fromkeys(chunk_ids))
    if not identities:
        return {}
    rows = connection.execute(
        """/* ishikawa.tuning.candidate-metadata */
        SELECT ac.chunk_id, ac.display_name, ci.page_start, ci.page_end
        FROM rag_search.active_chunks ac
        JOIN rag_search.active_citations ci ON ci.chunk_id = ac.chunk_id
        WHERE ac.chunk_id = ANY(%s::text[])
        ORDER BY ac.chunk_id, ci.page_start, ci.page_end, ci.citation_id
        """,
        (list(identities),),
    ).fetchall()
    grouped: dict[str, dict[str, Any]] = {}
    for chunk_id, display_name, page_start, page_end in rows:
        require(
            isinstance(chunk_id, str)
            and isinstance(display_name, str)
            and type(page_start) is int
            and type(page_end) is int
            and 1 <= page_start <= page_end,
            "candidate_metadata_invalid",
        )
        record = grouped.setdefault(
            chunk_id, {"display_name": display_name, "pages": []}
        )
        require(record["display_name"] == display_name, "candidate_metadata_conflict")
        page_range = [page_start, page_end]
        if page_range not in record["pages"]:
            record["pages"].append(page_range)
    require(set(grouped) == set(identities), "candidate_metadata_incomplete")
    return grouped


def lane_record(candidate: Any, metadata: Mapping[str, Mapping[str, Any]]) -> dict[str, Any]:
    record = metadata[candidate.chunk_id]
    return {
        "chunk_id": candidate.chunk_id,
        "document_key": candidate.document_key,
        "display_name": record["display_name"],
        "pages": record["pages"],
        "rank": candidate.rank,
        "raw_score": format(candidate.raw_score, ".17g"),
        "exact_reason": candidate.exact_reason,
        "retrieval_variant": candidate.retrieval_variant,
    }


def fused_record(rank: int, candidate: Any, metadata: Mapping[str, Mapping[str, Any]]) -> dict[str, Any]:
    record = metadata[candidate.chunk_id]
    return {
        "chunk_id": candidate.chunk_id,
        "document_key": candidate.document_key,
        "display_name": record["display_name"],
        "pages": record["pages"],
        "rank": rank,
        "fused_score": format(candidate.fused_score, ".17g"),
        "exact_priority": candidate.exact_priority,
        "lane_evidence": [
            {
                "lane": item.lane,
                "rank": item.rank,
                "raw_score": format(item.raw_score, ".17g"),
                "exact_reason": item.exact_reason,
                "retrieval_variant": item.retrieval_variant,
            }
            for item in candidate.evidence
        ],
    }


def record_matches(record: Mapping[str, Any], expected: EvidenceExpectation) -> bool:
    return record["display_name"] == expected.display_name and any(
        start <= expected.page <= end for start, end in record["pages"]
    )


def measure_case(case: TuningCase, fused: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    matched = [
        expected
        for expected in case.required_evidence
        if any(record_matches(record, expected) for record in fused[:20])
    ]
    first_relevant_rank = next(
        (
            rank
            for rank, record in enumerate(fused[:20], start=1)
            if any(record_matches(record, expected) for expected in case.required_evidence)
        ),
        None,
    )
    return {
        "case_id": case.case_id,
        "case_class": case.case_class,
        "expected_status": case.expected_status,
        "query_sha256": case.query_sha256,
        "first_relevant_rank": first_relevant_rank,
        "relevant_within_top_five": (
            first_relevant_rank is not None and first_relevant_rank <= 5
        ),
        "required_evidence_count": len(case.required_evidence),
        "matched_evidence": [
            {"display_name": item.display_name, "page": item.page} for item in matched
        ],
        "matched_evidence_count": len(matched),
    }


def aggregate_metrics(results: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    responsive = [item for item in results if item["case_class"] == "responsive"]
    require(len(responsive) == EXPECTED_RESPONSIVE_COUNT, "responsive_result_count_invalid")
    reciprocal_sum = sum(
        (Fraction(1, item["first_relevant_rank"]) if item["first_relevant_rank"] else Fraction(0, 1))
        for item in responsive
    )
    mrr = reciprocal_sum / len(responsive)
    matched = sum(item["matched_evidence_count"] for item in responsive)
    expected = sum(item["required_evidence_count"] for item in responsive)
    top_five = sum(bool(item["relevant_within_top_five"]) for item in responsive)
    ranking_gate = mrr >= Fraction(85, 100) and top_five == 6 and matched == expected == 13
    return {
        "mrr_at_20": format(float(mrr), ".6f"),
        "mrr_fraction_numerator": mrr.numerator,
        "mrr_fraction_denominator": mrr.denominator,
        "responsive_cases": len(responsive),
        "responsive_cases_with_relevant_top_five": top_five,
        "required_evidence_matched_at_20": matched,
        "required_evidence_total": expected,
        "ranking_gate": "pass" if ranking_gate else "not_met",
    }


def self_test() -> int:
    cases = tuple(
        TuningCase(
            f"R-{index:03d}",
            "responsive",
            "answered",
            "synthetic question",
            "0" * 64,
            (EvidenceExpectation(f"Document {index}", 1),),
        )
        for index in range(1, 7)
    )
    results = [
        measure_case(
            case,
            (
                {
                    "display_name": case.required_evidence[0].display_name,
                    "pages": [[1, 1]],
                },
            ),
        )
        for case in cases
    ]
    metrics = aggregate_metrics(results)
    require(
        metrics["mrr_at_20"] == "1.000000"
        and metrics["ranking_gate"] != "pass"
        and metrics["required_evidence_matched_at_20"] == 6,
        "self_test_metric_failure",
    )
    print("local_retrieval_ranking_evaluator_self_test=pass")
    return 0


def run(arguments: argparse.Namespace) -> int:
    python_root = Path(arguments.python_root).resolve(strict=True)
    sys.path.insert(0, str(python_root))
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
    output_path = Path(arguments.output)
    require(
        config_root.is_dir()
        and not config_root.is_symlink()
        and output_path.is_absolute()
        and not output_path.exists()
        and not output_path.is_symlink(),
        "runtime_path_invalid",
    )
    cases = load_cases(Path(arguments.cases).resolve(strict=True))
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
    environment = os.environ
    database_factory = NativePostgresConnectionFactory(
        deployment.postgresql,
        dependencies,
        ProtectedEnvironmentValue(dependencies.database_credential_environment, environment),
    )
    embed_query = NativeQueryEmbeddingAdapter(
        dependencies.embedding_endpoint,
        ProtectedEnvironmentValue(dependencies.embedding_credential_environment, environment),
    )

    connection = database_factory()
    observations: list[dict[str, Any]] = []
    query_embedding_count = 0
    lane_totals = {"exact": 0, "lexical": 0, "vector": 0, "fused": 0}
    try:
        connection.execute(
            "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY"
        )
        boundary = connection.execute(
            """/* ishikawa.tuning.boundary */
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
            """/* ishikawa.tuning.inventory */
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
            if case.case_class == "broad-navigation":
                observation = measure_case(case, ())
                observation.update(
                    {
                        "deterministic_status": "clarification-required",
                        "embedding_request_identity": None,
                        "embedding_prompt_tokens": None,
                        "lanes": {"exact": [], "lexical": [], "vector": []},
                        "fused": [],
                    }
                )
                observations.append(observation)
                continue

            embedding = embed_query(case.question)
            query_embedding_count += 1
            require(
                embedding.embedding_space_id == ACCEPTED_EMBEDDING_SPACE_ID,
                "embedding_space_invalid",
            )
            terms = extract_structured_terms(case.question)
            explicit_page = extract_explicit_page(case.question)
            exact_parts: list[tuple[int, Any]] = []
            if explicit_page is not None and len(terms) == 1:
                exact_parts.extend(
                    (-1, item)
                    for item in exact_document_page_lookup(
                        connection,
                        terms[0],
                        explicit_page,
                        depth=profile.exact_candidate_depth,
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
            all_ids = [
                item.chunk_id for lane in (exact, lexical, vector, fused) for item in lane
            ]
            metadata = load_candidate_metadata(connection, all_ids)
            fused_records = [
                fused_record(rank, item, metadata)
                for rank, item in enumerate(fused, start=1)
            ]
            observation = measure_case(case, fused_records)
            observation.update(
                {
                    "deterministic_status": "retrieved",
                    "embedding_request_identity": embedding.request_identity,
                    "embedding_prompt_tokens": embedding.prompt_tokens,
                    "structured_term_count": len(terms),
                    "explicit_page": explicit_page,
                    "lanes": {
                        "exact": [lane_record(item, metadata) for item in exact],
                        "lexical": [lane_record(item, metadata) for item in lexical],
                        "vector": [lane_record(item, metadata) for item in vector],
                    },
                    "fused": fused_records,
                }
            )
            observations.append(observation)
            for name, lane in (("exact", exact), ("lexical", lexical), ("vector", vector)):
                lane_totals[name] += len(lane)
            lane_totals["fused"] += len(fused)
        connection.execute("ROLLBACK")
    finally:
        connection.close()

    metrics = aggregate_metrics(observations)
    broad = next(item for item in observations if item["case_id"] == EXPECTED_BROAD_CASE)
    require(
        broad["deterministic_status"] == "clarification-required"
        and broad["embedding_request_identity"] is None,
        "broad_navigation_contract_invalid",
    )
    artifact: dict[str, Any] = {
        "artifact_kind": "ishikawa_local_retrieval_ranking_baseline",
        "schema_version": 1,
        "case_set_sha256": sha256_file(Path(arguments.cases).resolve(strict=True)),
        "deployment_profile_id": deployment.digest,
        "runtime_dependency_profile_id": dependencies.digest,
        "retrieval_profile_id": profile.digest,
        "retrieval_profile": profile.observation_contract(),
        "embedding_space_id": ACCEPTED_EMBEDDING_SPACE_ID,
        "database_boundary": "repeatable_read_read_only",
        "corpus_inventory": {
            "documents": 6,
            "pages": 27,
            "chunks": 126,
            "citations": 126,
            "embeddings": 126,
        },
        "case_count": len(cases),
        "query_embedding_count": query_embedding_count,
        "lane_candidate_totals": lane_totals,
        "metrics": metrics,
        "nonresponsive_acceptance_measured": False,
        "gemma_contact": False,
        "question_text_retained": False,
        "query_vectors_retained": False,
        "source_text_retained": False,
        "cases": observations,
    }
    from ishikawa.canonical import canonical_json_bytes, domain_digest

    artifact["observation_set_id"] = domain_digest(
        "ishikawa.local-retrieval-ranking-baseline.v1", artifact
    )
    payload = canonical_json_bytes(artifact) + b"\n"
    descriptor = os.open(output_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)
    print("purpose=measure_local_ishikawa_retrieval_ranking_baseline")
    print(
        f"case_count={len(cases)};query_embeddings={query_embedding_count};"
        "gemma_contact=false;database_write=false"
    )
    print(
        f"mrr_at_20={metrics['mrr_at_20']};"
        f"responsive_top_five={metrics['responsive_cases_with_relevant_top_five']}/6;"
        f"required_evidence_at_20={metrics['required_evidence_matched_at_20']}/13"
    )
    print(
        f"ranking_gate={metrics['ranking_gate']};"
        "nonresponsive_acceptance_measured=false;"
        "broad_navigation=clarification-required"
    )
    print(
        f"observation_set_id={artifact['observation_set_id']};"
        f"artifact_sha256={hashlib.sha256(payload).hexdigest()};"
        f"artifact_bytes={len(payload)}"
    )
    print("local_retrieval_ranking_evaluator=pass")
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
        raise EvaluationError("mode_invalid")
    if arguments.run and not all(
        (arguments.python_root, arguments.config_root, arguments.cases, arguments.output)
    ):
        raise EvaluationError("argument_missing")
    return arguments


def main() -> int:
    try:
        arguments = parse_arguments()
        return self_test() if arguments.self_test else run(arguments)
    except EvaluationError as error:
        print(f"local_retrieval_ranking_evaluator=blocked;reason={error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("local_retrieval_ranking_evaluator=blocked;reason=interrupted", file=sys.stderr)
        return 130
    except Exception as error:
        print(
            f"local_retrieval_ranking_evaluator=blocked;reason=bounded_{type(error).__name__}",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
