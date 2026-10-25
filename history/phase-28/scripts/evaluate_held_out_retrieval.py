#!/usr/bin/env python3
"""Evaluate held-out retrieval observations locally without disclosing content."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
from pathlib import Path
from typing import Any, NoReturn


EMBEDDING_SPACE_ID = "fd970d304662357a07f7712639bdc0c70cc7e72b22f04c126acce57a6f9143a3"
EXPECTED_PROFILE = {
    "schema_version": 1,
    "method_profile_id": "5797961aee919aa73bbd99d6cc188084d57d22839a1d4cff0febc2e73e17b4b0",
    "lexical_search_config": "english",
    "lexical_fallback": "native_or_when_strict_empty",
    "explicit_page_route": "document_identifier_plus_page",
    "exact_candidate_depth": 20,
    "lexical_candidate_depth": 20,
    "vector_candidate_depth": 20,
    "fused_candidate_depth": 20,
    "rrf_constant": 60,
    "lane_weights": {"exact": 1, "lexical": 1, "vector": 1},
    "vector_distance": "cosine",
    "learned_reranker": False,
}
HEX = re.compile(r"^[0-9a-f]{64}$")
PAGE_REFERENCE = re.compile(r"\bpage\s+([1-9][0-9]{0,5})\b", re.IGNORECASE)


class EvaluationError(RuntimeError):
    pass


def fail(reason: str) -> NoReturn:
    raise EvaluationError(reason)


def canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_json(path: Path, maximum_bytes: int) -> Any:
    if not path.is_file() or path.is_symlink() or path.stat().st_size > maximum_bytes:
        fail("unsafe_or_oversized_json")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail("invalid_json")


def evaluate(arguments: argparse.Namespace) -> dict[str, Any]:
    expected_hashes = {
        arguments.cases: arguments.expected_cases_sha256,
        arguments.chunks: arguments.expected_chunks_sha256,
        arguments.queries: arguments.expected_queries_sha256,
        arguments.query_embeddings: arguments.expected_query_embeddings_sha256,
    }
    for path, expected in expected_hashes.items():
        if HEX.fullmatch(expected or "") is None or sha256_file(path) != expected:
            fail("source_identity_mismatch")
    truth = load_json(arguments.cases, 1024 * 1024)
    chunks = load_json(arguments.chunks, 32 * 1024 * 1024)
    queries = load_json(arguments.queries, 1024 * 1024)
    query_embeddings = load_json(arguments.query_embeddings, 16 * 1024 * 1024)
    observations = load_json(arguments.observations, 16 * 1024 * 1024)
    if not isinstance(truth, list) or len(truth) != 7:
        fail("held_out_truth_inventory_invalid")
    expected_cases = {
        item["id"]: item for item in truth if item.get("expected_abstention") is not True
    }
    if len(expected_cases) != 6:
        fail("eligible_truth_inventory_invalid")
    query_cases = {item["case_id"]: item for item in queries.get("cases", [])}
    if set(query_cases) != set(expected_cases):
        fail("query_case_inventory_mismatch")
    embedding_cases = {item["case_id"]: item for item in query_embeddings.get("records", [])}
    if set(embedding_cases) != set(expected_cases):
        fail("query_embedding_inventory_mismatch")
    for case_id, query in query_cases.items():
        if query.get("question_digest") != embedding_cases[case_id].get("question_digest"):
            fail("query_digest_mismatch")

    chunk_anchors: dict[str, set[str]] = {}
    for document in chunks.get("documents", []):
        doc_ref = document.get("document_ref")
        for chunk in document.get("candidates", []):
            chunk_id = chunk.get("chunk_id")
            anchor = chunk.get("citation_anchor", {})
            page_start = anchor.get("page_start")
            page_end = anchor.get("page_end")
            if (
                not isinstance(doc_ref, str)
                or HEX.fullmatch(chunk_id or "") is None
                or not isinstance(page_start, int)
                or not isinstance(page_end, int)
                or page_start < 1
                or page_end < page_start
            ):
                fail("chunk_citation_mapping_invalid")
            chunk_anchors[chunk_id] = {
                f"{doc_ref}:{page}" for page in range(page_start, page_end + 1)
            }
    if len(chunk_anchors) != 126:
        fail("chunk_inventory_mismatch")

    if (
        observations.get("schema_version") != 1
        or observations.get("artifact_kind") != "held_out_retrieval_observations"
        or observations.get("source_query_input_sha256") != arguments.expected_queries_sha256
        or observations.get("source_query_embedding_sha256")
        != arguments.expected_query_embeddings_sha256
        or observations.get("source_document_embedding_sha256")
        != arguments.expected_document_embeddings_sha256
        or observations.get("method_profile") != EXPECTED_PROFILE
        or observations.get("embedding_space_id") != EMBEDDING_SPACE_ID
        or observations.get("case_count") != 6
    ):
        fail("observation_contract_mismatch")
    stored_digest = observations.get("observation_set_digest")
    digest_input = dict(observations)
    digest_input.pop("observation_set_digest", None)
    expected_digest = hashlib.sha256(
        b"ishikawa.retrieval-observations.v1\x00" + canonical_json_bytes(digest_input)
    ).hexdigest()
    if stored_digest != expected_digest:
        fail("observation_set_digest_invalid")
    observed_cases = {item["case_id"]: item for item in observations.get("cases", [])}
    if set(observed_cases) != set(expected_cases):
        fail("observation_case_inventory_mismatch")

    case_results: list[dict[str, Any]] = []
    reciprocal_ranks: list[float] = []
    total_required = 0
    total_covered = 0
    total_returned = 0
    total_relevant_returned = 0
    lexical_or_fallback_observed = False
    for case_id in sorted(expected_cases):
        expected = expected_cases[case_id]
        observed = observed_cases[case_id]
        if observed.get("question_digest") != query_cases[case_id].get("question_digest"):
            fail("observation_question_digest_mismatch")
        lanes = observed.get("lanes")
        fused = observed.get("fused")
        if not isinstance(lanes, dict) or set(lanes) != {"exact", "lexical", "vector"}:
            fail("observation_lane_contract_invalid")
        if not isinstance(fused, list) or len(fused) > 20:
            fail("fused_observation_invalid")
        for lane_name, depth in (("exact", 20), ("lexical", 20), ("vector", 20)):
            candidates = lanes[lane_name]
            if not isinstance(candidates, list) or len(candidates) > depth:
                fail("lane_observation_invalid")
            if [item.get("rank") for item in candidates] != list(range(1, len(candidates) + 1)):
                fail("lane_rank_sequence_invalid")
            if any(item.get("chunk_id") not in chunk_anchors for item in candidates):
                fail("lane_chunk_identity_invalid")
            variants = {item.get("retrieval_variant") for item in candidates}
            if lane_name == "lexical":
                if candidates and (len(variants) != 1 or not variants <= {"strict", "or_fallback"}):
                    fail("lexical_variant_invalid")
                lexical_or_fallback_observed |= "or_fallback" in variants
            elif variants - {None}:
                fail("nonlexical_variant_invalid")
        if [item.get("rank") for item in fused] != list(range(1, len(fused) + 1)):
            fail("fused_rank_sequence_invalid")
        if len({item.get("chunk_id") for item in fused}) != len(fused):
            fail("fused_candidate_duplicate")
        if any(item.get("chunk_id") not in chunk_anchors for item in fused):
            fail("fused_chunk_identity_invalid")
        if any(
            not isinstance(item.get("fused_score"), (int, float))
            or not math.isfinite(float(item["fused_score"]))
            for item in fused
        ):
            fail("fused_score_invalid")

        required = set(expected.get("required_citations", []))
        if not required:
            fail("required_citation_truth_missing")
        query_pages = {
            int(match.group(1))
            for match in PAGE_REFERENCE.finditer(query_cases[case_id]["question"])
        }
        expected_page = next(iter(query_pages)) if len(query_pages) == 1 else None
        if observed.get("explicit_page") != expected_page:
            fail("explicit_page_observation_mismatch")
        ranks: dict[str, int | None] = {citation: None for citation in required}
        relevant_results = 0
        first_relevant_rank: int | None = None
        for item in fused:
            anchors = chunk_anchors[item["chunk_id"]]
            matched = anchors & required
            if matched:
                relevant_results += 1
                if first_relevant_rank is None:
                    first_relevant_rank = item["rank"]
                for citation in matched:
                    if ranks[citation] is None:
                        ranks[citation] = item["rank"]
        covered = sum(rank is not None for rank in ranks.values())
        exact_required = observed.get("structured_term_count", 0) > 0
        exact_returned = len(lanes["exact"])
        exact_page_status = expected_page is None or any(
            item.get("exact_reason") == "document_page_match"
            and bool(chunk_anchors[item["chunk_id"]] & required)
            for item in lanes["exact"]
        )
        exact_status = ((not exact_required) or exact_returned > 0) and exact_page_status
        status = "PASS" if covered == len(required) and exact_status else "FAIL"
        reciprocal_rank = 0.0 if first_relevant_rank is None else 1.0 / first_relevant_rank
        reciprocal_ranks.append(reciprocal_rank)
        total_required += len(required)
        total_covered += covered
        total_returned += len(fused)
        total_relevant_returned += relevant_results
        case_results.append({
            "case_id": case_id,
            "status": status,
            "required": len(required),
            "covered": covered,
            "first_relevant_rank": first_relevant_rank or 0,
            "reciprocal_rank": reciprocal_rank,
            "fused_returned": len(fused),
            "relevant_returned": relevant_results,
            "exact_required": exact_required,
            "exact_returned": exact_returned,
            "exact_page_route": exact_page_status,
            "lexical_returned": len(lanes["lexical"]),
            "vector_returned": len(lanes["vector"]),
        })

    passed = sum(item["status"] == "PASS" for item in case_results)
    artifact_sha256 = sha256_file(arguments.observations)
    return {
        "case_results": case_results,
        "passed": passed,
        "failed": len(case_results) - passed,
        "total_required": total_required,
        "total_covered": total_covered,
        "coverage": total_covered / total_required,
        "precision": 0.0 if total_returned == 0 else total_relevant_returned / total_returned,
        "mean_reciprocal_rank": sum(reciprocal_ranks) / len(reciprocal_ranks),
        "promotion_eligible": passed == len(case_results) and lexical_or_fallback_observed,
        "lexical_or_fallback_observed": lexical_or_fallback_observed,
        "observation_set_digest": stored_digest,
        "artifact_sha256": artifact_sha256,
        "artifact_bytes": arguments.observations.stat().st_size,
    }


def self_test() -> None:
    value = {"b": 2, "a": 1}
    assert canonical_json_bytes(value) == b'{"a":1,"b":2}'
    assert len(EXPECTED_PROFILE) == 13
    print("held_out_retrieval_evaluator_self_test=PASS")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cases", type=Path)
    parser.add_argument("--expected-cases-sha256")
    parser.add_argument("--chunks", type=Path)
    parser.add_argument("--expected-chunks-sha256")
    parser.add_argument("--queries", type=Path)
    parser.add_argument("--expected-queries-sha256")
    parser.add_argument("--query-embeddings", type=Path)
    parser.add_argument("--expected-query-embeddings-sha256")
    parser.add_argument("--expected-document-embeddings-sha256")
    parser.add_argument("--observations", type=Path)
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        if arguments.self_test:
            self_test()
            return 0
        required = (
            arguments.cases,
            arguments.expected_cases_sha256,
            arguments.chunks,
            arguments.expected_chunks_sha256,
            arguments.queries,
            arguments.expected_queries_sha256,
            arguments.query_embeddings,
            arguments.expected_query_embeddings_sha256,
            arguments.expected_document_embeddings_sha256,
            arguments.observations,
        )
        if not all(required):
            fail("required_argument_missing")
        summary = evaluate(arguments)
    except (EvaluationError, KeyError, TypeError, ValueError, OSError) as exc:
        reason = str(exc) if isinstance(exc, EvaluationError) else "bounded_runtime_failure"
        print(f"held_out_retrieval_evaluation=blocked;reason={reason}")
        return 1
    print("purpose=evaluate_held_out_retrieval_calibration")
    for result in summary["case_results"]:
        print(
            f"case_{result['case_id'].replace('-', '_')}={result['status']};"
            f"required={result['required']};covered={result['covered']};"
            f"first_relevant_rank={result['first_relevant_rank']};"
            f"reciprocal_rank={result['reciprocal_rank']:.6f};"
            f"exact_required={str(result['exact_required']).lower()};"
            f"exact_returned={result['exact_returned']};"
            f"exact_page_route={str(result['exact_page_route']).lower()};"
            f"lexical_returned={result['lexical_returned']};"
            f"vector_returned={result['vector_returned']};"
            f"fused_returned={result['fused_returned']}"
        )
    print(
        f"cases_passed={summary['passed']};cases_failed={summary['failed']};"
        f"required_citations={summary['total_required']};covered_citations={summary['total_covered']}"
    )
    print(
        f"citation_coverage={summary['coverage']:.6f};"
        f"citation_precision_at_20={summary['precision']:.6f};"
        f"mean_reciprocal_rank={summary['mean_reciprocal_rank']:.6f}"
    )
    print(
        "lexical_or_fallback_observed="
        f"{str(summary['lexical_or_fallback_observed']).lower()}"
    )
    print(
        f"observation_set_digest={summary['observation_set_digest']};"
        f"observation_artifact_sha256={summary['artifact_sha256']};"
        f"observation_artifact_bytes={summary['artifact_bytes']}"
    )
    print(
        f"profile_promotion_eligible={str(summary['promotion_eligible']).lower()};"
        f"next_gate={'freeze_calibrated_profile' if summary['promotion_eligible'] else 'close_observed_retrieval_gaps'}"
    )
    print("held_out_retrieval_evaluation=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
