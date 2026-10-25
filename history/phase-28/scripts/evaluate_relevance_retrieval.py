#!/usr/bin/env python3
"""Evaluate protected relevance-retrieval observations without exposing text."""

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
    "chunk_method_profile_id": "5797961aee919aa73bbd99d6cc188084d57d22839a1d4cff0febc2e73e17b4b0",
    "retrieval_profile_id": "33102734a29ea8170cffcfa7cdff6feae66d4663d09d7bca86c04a6419f77ad7",
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
EXPECTED_SOURCE_IDS = tuple(f"R-{number:03d}" for number in range(1, 7)) + tuple(
    f"N-{number:03d}" for number in range(1, 7)
)
EXPECTED_TARGET_IDS = tuple(f"C-{number:03d}" for number in range(1, 13))


class EvaluationError(RuntimeError):
    pass


def fail(reason: str) -> NoReturn:
    raise EvaluationError(reason)


def canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, allow_nan=False, sort_keys=True, separators=(",", ":")
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


def require_identity(path: Path, expected: str) -> None:
    if HEX.fullmatch(expected or "") is None or sha256_file(path) != expected:
        fail("source_identity_mismatch")


def validate_ranked_lane(
    candidates: Any,
    lane: str,
    valid_chunks: set[str],
) -> list[dict[str, Any]]:
    if not isinstance(candidates, list) or len(candidates) > 20:
        fail("lane_observation_invalid")
    if [item.get("rank") for item in candidates] != list(range(1, len(candidates) + 1)):
        fail("lane_rank_sequence_invalid")
    for item in candidates:
        if item.get("chunk_id") not in valid_chunks:
            fail("lane_chunk_identity_invalid")
        score = item.get("raw_score")
        if not isinstance(score, (int, float)) or isinstance(score, bool) or not math.isfinite(float(score)):
            fail("lane_score_invalid")
        variant = item.get("retrieval_variant")
        reason = item.get("exact_reason")
        if lane == "exact":
            if not isinstance(reason, str) or variant is not None:
                fail("exact_lane_contract_invalid")
        elif lane == "lexical":
            if reason is not None or variant not in {"strict", "or_fallback"}:
                fail("lexical_lane_contract_invalid")
        elif reason is not None or variant is not None:
            fail("vector_lane_contract_invalid")
    return candidates


def evaluate(arguments: argparse.Namespace) -> dict[str, Any]:
    for path, expected in (
        (arguments.cases, arguments.expected_cases_sha256),
        (arguments.chunks, arguments.expected_chunks_sha256),
        (arguments.queries, arguments.expected_queries_sha256),
        (arguments.query_embeddings, arguments.expected_query_embeddings_sha256),
    ):
        require_identity(path, expected)
    cases_document = load_json(arguments.cases, 1024 * 1024)
    chunks = load_json(arguments.chunks, 32 * 1024 * 1024)
    queries = load_json(arguments.queries, 1024 * 1024)
    query_embeddings = load_json(arguments.query_embeddings, 32 * 1024 * 1024)
    observations = load_json(arguments.observations, 32 * 1024 * 1024)

    cases = cases_document.get("cases") if isinstance(cases_document, dict) else None
    if (
        not isinstance(cases, list)
        or tuple(item.get("case_id") for item in cases) != EXPECTED_SOURCE_IDS
    ):
        fail("relevance_case_inventory_invalid")
    source_by_target_id = dict(zip(EXPECTED_TARGET_IDS, cases))
    query_cases = {item["case_id"]: item for item in queries.get("cases", [])}
    embedding_cases = {
        item["case_id"]: item for item in query_embeddings.get("records", [])
    }
    if (
        queries.get("schema_version") != 1
        or queries.get("artifact_kind") != "relevance_retrieval_queries"
        or queries.get("source_case_set_sha256") != arguments.expected_cases_sha256
        or queries.get("source_query_embedding_sha256")
        != arguments.expected_source_query_embeddings_sha256
        or set(query_cases) != set(EXPECTED_TARGET_IDS)
        or query_embeddings.get("artifact_kind") != "relevance_retrieval_query_vectors"
        or query_embeddings.get("embedding_space_id") != EMBEDDING_SPACE_ID
        or query_embeddings.get("source_query_embedding_sha256")
        != arguments.expected_source_query_embeddings_sha256
        or set(embedding_cases) != set(EXPECTED_TARGET_IDS)
    ):
        fail("query_contract_invalid")
    for target_case_id in EXPECTED_TARGET_IDS:
        query = query_cases[target_case_id]
        source = source_by_target_id[target_case_id]
        if (
            set(query) != {"case_id", "question", "question_digest"}
            or query["question"] != source["question"]
            or query["question_digest"]
            != embedding_cases[target_case_id].get("question_digest")
        ):
            fail("query_case_mapping_invalid")

    chunk_anchors: dict[str, set[str]] = {}
    for document in chunks.get("documents", []):
        document_ref = document.get("document_ref")
        for chunk in document.get("candidates", []):
            anchor = chunk.get("citation_anchor", {})
            chunk_id = chunk.get("chunk_id")
            page_start = anchor.get("page_start")
            page_end = anchor.get("page_end")
            if (
                not isinstance(document_ref, str)
                or HEX.fullmatch(chunk_id or "") is None
                or not isinstance(page_start, int)
                or not isinstance(page_end, int)
                or page_start < 1
                or page_end < page_start
            ):
                fail("chunk_citation_mapping_invalid")
            chunk_anchors[chunk_id] = {
                f"{document_ref}:{page}" for page in range(page_start, page_end + 1)
            }
    if len(chunk_anchors) != 126:
        fail("chunk_inventory_mismatch")

    if (
        observations.get("schema_version") != 1
        or observations.get("artifact_kind") != "relevance_retrieval_observations"
        or observations.get("source_query_input_sha256") != arguments.expected_queries_sha256
        or observations.get("source_query_embedding_sha256")
        != arguments.expected_source_query_embeddings_sha256
        or observations.get("query_vector_payload_sha256")
        != arguments.expected_query_embeddings_sha256
        or observations.get("source_document_embedding_sha256")
        != arguments.expected_document_embeddings_sha256
        or observations.get("method_profile") != EXPECTED_PROFILE
        or observations.get("embedding_space_id") != EMBEDDING_SPACE_ID
        or observations.get("case_count") != 12
    ):
        fail("observation_contract_mismatch")
    digest_input = dict(observations)
    stored_digest = digest_input.pop("observation_set_digest", None)
    expected_digest = hashlib.sha256(
        b"ishikawa.relevance-retrieval-observations.v1\x00"
        + canonical_json_bytes(digest_input)
    ).hexdigest()
    if stored_digest != expected_digest:
        fail("observation_set_digest_invalid")
    observed_cases = {
        item["case_id"]: item for item in observations.get("cases", [])
    }
    if set(observed_cases) != set(EXPECTED_TARGET_IDS):
        fail("observation_case_inventory_invalid")

    results: list[dict[str, Any]] = []
    for target_case_id in EXPECTED_TARGET_IDS:
        expected = source_by_target_id[target_case_id]
        observed = observed_cases[target_case_id]
        if (
            observed.get("question_digest")
            != query_cases[target_case_id]["question_digest"]
        ):
            fail("observation_question_digest_mismatch")
        lanes = observed.get("lanes")
        if not isinstance(lanes, dict) or set(lanes) != {"exact", "lexical", "vector"}:
            fail("observation_lane_contract_invalid")
        exact = validate_ranked_lane(lanes["exact"], "exact", set(chunk_anchors))
        lexical = validate_ranked_lane(lanes["lexical"], "lexical", set(chunk_anchors))
        vector = validate_ranked_lane(lanes["vector"], "vector", set(chunk_anchors))
        fused = observed.get("fused")
        if not isinstance(fused, list) or len(fused) > 20:
            fail("fused_observation_invalid")
        if [item.get("rank") for item in fused] != list(range(1, len(fused) + 1)):
            fail("fused_rank_sequence_invalid")
        if len({item.get("chunk_id") for item in fused}) != len(fused):
            fail("fused_candidate_duplicate")
        for item in fused:
            if item.get("chunk_id") not in chunk_anchors:
                fail("fused_chunk_identity_invalid")
            score = item.get("fused_score")
            provenance = item.get("lane_provenance")
            if (
                not isinstance(score, (int, float))
                or isinstance(score, bool)
                or not math.isfinite(float(score))
                or not isinstance(provenance, list)
                or not provenance
                or set(provenance) - {"exact", "lexical", "vector"}
            ):
                fail("fused_candidate_contract_invalid")

        required = set(expected.get("required_citations", []))
        if expected["class"] == "responsive" and not required:
            fail("responsive_truth_missing")
        if expected["class"] == "nonresponsive" and required:
            fail("nonresponsive_truth_present")
        covered: set[str] = set()
        first_relevant_rank = 0
        for item in fused:
            matched = chunk_anchors[item["chunk_id"]] & required
            if matched and first_relevant_rank == 0:
                first_relevant_rank = item["rank"]
            covered.update(matched)
        top_vector = float(vector[0]["raw_score"]) if vector else -1.0
        top_lexical = float(lexical[0]["raw_score"]) if lexical else 0.0
        top_fused = float(fused[0]["fused_score"]) if fused else 0.0
        top_lane_count = len(fused[0]["lane_provenance"]) if fused else 0
        best_required_vector = max(
            (
                float(item["raw_score"])
                for item in vector
                if chunk_anchors[item["chunk_id"]] & required
            ),
            default=-1.0,
        )
        results.append(
            {
                "case_id": expected["case_id"],
                "class": expected["class"],
                "required": len(required),
                "covered": len(covered),
                "first_relevant_rank": first_relevant_rank,
                "exact_count": len(exact),
                "lexical_count": len(lexical),
                "vector_count": len(vector),
                "fused_count": len(fused),
                "top_vector": top_vector,
                "top_lexical": top_lexical,
                "top_fused": top_fused,
                "top_lane_count": top_lane_count,
                "best_required_vector": best_required_vector,
            }
        )

    responsive = [item for item in results if item["class"] == "responsive"]
    nonresponsive = [item for item in results if item["class"] == "nonresponsive"]
    return {
        "results": results,
        "responsive_coverage": sum(item["covered"] for item in responsive),
        "responsive_required": sum(item["required"] for item in responsive),
        "responsive_top_vector_min": min(item["top_vector"] for item in responsive),
        "responsive_top_vector_max": max(item["top_vector"] for item in responsive),
        "nonresponsive_top_vector_min": min(item["top_vector"] for item in nonresponsive),
        "nonresponsive_top_vector_max": max(item["top_vector"] for item in nonresponsive),
        "responsive_top_fused_min": min(item["top_fused"] for item in responsive),
        "responsive_top_fused_max": max(item["top_fused"] for item in responsive),
        "nonresponsive_top_fused_min": min(item["top_fused"] for item in nonresponsive),
        "nonresponsive_top_fused_max": max(item["top_fused"] for item in nonresponsive),
        "digest": stored_digest,
        "artifact_sha256": sha256_file(arguments.observations),
        "artifact_bytes": arguments.observations.stat().st_size,
    }


def self_test() -> None:
    assert canonical_json_bytes({"b": 2, "a": 1}) == b'{"a":1,"b":2}'
    assert len(EXPECTED_PROFILE) == 14
    assert len(EXPECTED_SOURCE_IDS) == 12
    assert len(EXPECTED_TARGET_IDS) == 12
    print("relevance_retrieval_evaluator_self_test=PASS")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cases", type=Path)
    parser.add_argument("--expected-cases-sha256")
    parser.add_argument("--chunks", type=Path)
    parser.add_argument("--expected-chunks-sha256")
    parser.add_argument("--queries", type=Path)
    parser.add_argument("--expected-queries-sha256")
    parser.add_argument("--query-embeddings", type=Path)
    parser.add_argument("--expected-query-embeddings-sha256")
    parser.add_argument("--expected-source-query-embeddings-sha256")
    parser.add_argument("--expected-document-embeddings-sha256")
    parser.add_argument("--observations", type=Path)
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    try:
        if arguments.self_test:
            self_test()
            return 0
        if not all(
            (
                arguments.cases,
                arguments.expected_cases_sha256,
                arguments.chunks,
                arguments.expected_chunks_sha256,
                arguments.queries,
                arguments.expected_queries_sha256,
                arguments.query_embeddings,
                arguments.expected_query_embeddings_sha256,
                arguments.expected_source_query_embeddings_sha256,
                arguments.expected_document_embeddings_sha256,
                arguments.observations,
            )
        ):
            fail("required_argument_missing")
        summary = evaluate(arguments)
    except (EvaluationError, KeyError, TypeError, ValueError, OSError) as error:
        reason = str(error) if isinstance(error, EvaluationError) else "bounded_runtime_failure"
        print(f"relevance_retrieval_evaluation=blocked;reason={reason}")
        return 1
    for result in summary["results"]:
        print(
            f"case_{result['case_id'].replace('-', '_')}={result['class']};"
            f"required={result['required']};covered={result['covered']};"
            f"first_relevant_rank={result['first_relevant_rank']};"
            f"exact={result['exact_count']};lexical={result['lexical_count']};"
            f"vector={result['vector_count']};fused={result['fused_count']};"
            f"top_vector={result['top_vector']:.9f};top_lexical={result['top_lexical']:.9f};"
            f"top_fused={result['top_fused']:.9f};top_lane_count={result['top_lane_count']};"
            f"best_required_vector={result['best_required_vector']:.9f}"
        )
    print(
        f"responsive_required={summary['responsive_required']};"
        f"responsive_covered={summary['responsive_coverage']}"
    )
    print(
        f"responsive_top_vector_min={summary['responsive_top_vector_min']:.9f};"
        f"responsive_top_vector_max={summary['responsive_top_vector_max']:.9f};"
        f"nonresponsive_top_vector_min={summary['nonresponsive_top_vector_min']:.9f};"
        f"nonresponsive_top_vector_max={summary['nonresponsive_top_vector_max']:.9f}"
    )
    print(
        f"responsive_top_fused_min={summary['responsive_top_fused_min']:.9f};"
        f"responsive_top_fused_max={summary['responsive_top_fused_max']:.9f};"
        f"nonresponsive_top_fused_min={summary['nonresponsive_top_fused_min']:.9f};"
        f"nonresponsive_top_fused_max={summary['nonresponsive_top_fused_max']:.9f}"
    )
    print(
        f"observation_set_digest={summary['digest']};"
        f"observation_artifact_sha256={summary['artifact_sha256']};"
        f"observation_artifact_bytes={summary['artifact_bytes']}"
    )
    print("threshold_selected=false;next_gate=review_relevance_signal_separation")
    print("relevance_retrieval_evaluation=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
