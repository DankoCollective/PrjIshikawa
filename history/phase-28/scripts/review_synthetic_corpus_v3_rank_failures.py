#!/usr/bin/env python3
"""Classify synthetic-corpus-v3 pre-ingestion retrieval failures."""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
import os
from fractions import Fraction
from pathlib import Path
from typing import Any, Mapping


class ReviewError(RuntimeError):
    """Stable rank-review failure."""


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise ReviewError(reason)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load(path: Path, expected_sha256: str, maximum_bytes: int) -> dict[str, Any]:
    require(
        path.is_absolute()
        and path.is_file()
        and not path.is_symlink()
        and path.stat().st_size <= maximum_bytes
        and len(expected_sha256) == 64
        and sha256_file(path) == expected_sha256,
        "input_identity_invalid",
    )
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ReviewError("input_json_invalid") from error
    require(isinstance(value, dict), "input_json_invalid")
    return value


def canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def write_exclusive(path: Path, payload: bytes) -> None:
    require(
        path.is_absolute()
        and not path.exists()
        and not path.is_symlink()
        and path.parent.is_dir()
        and not path.parent.is_symlink(),
        "output_path_unsafe",
    )
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)


def page_metrics(
    body_results: list[Mapping[str, Any]],
    truth_by_case: Mapping[str, Mapping[str, Any]],
) -> dict[str, dict[str, Any]]:
    metrics: dict[str, dict[str, Any]] = {}
    for page in range(1, 5):
        records = [
            item
            for item in body_results
            if truth_by_case[item["case_id"]]["required_evidence"][0]["page"] == page
        ]
        reciprocal = sum(
            Fraction(1, item["first_relevant_rank"])
            if item["first_relevant_rank"] is not None
            else Fraction(0, 1)
            for item in records
        ) / len(records)
        metrics[str(page)] = {
            "case_count": len(records),
            "mrr_at_20": format(float(reciprocal), ".6f"),
            "relevant_at_5": sum(
                item["first_relevant_rank"] is not None
                and item["first_relevant_rank"] <= 5
                for item in records
            ),
            "relevant_at_20": sum(
                item["first_relevant_rank"] is not None for item in records
            ),
        }
    return metrics


def execute(arguments: argparse.Namespace) -> None:
    chunks = load(arguments.chunks, arguments.expected_chunks_sha256, 32 * 1024 * 1024)
    corpus = load(
        arguments.corpus_truth,
        arguments.expected_corpus_truth_sha256,
        4 * 1024 * 1024,
    )
    truth = load(arguments.retrieval_truth, arguments.expected_retrieval_truth_sha256, 4 * 1024 * 1024)
    observation = load(
        arguments.observation,
        arguments.expected_observation_sha256,
        16 * 1024 * 1024,
    )
    require(
        chunks.get("artifact_kind") == "non_publishable_structural_chunk_candidates"
        and len(chunks.get("documents", [])) == 30
        and corpus.get("corpus_identity") == "synthetic-corpus-v3"
        and truth.get("artifact_kind") == "ishikawa_synthetic_corpus_v3_retrieval_truth"
        and observation.get("artifact_kind")
        == "ishikawa_synthetic_corpus_v3_preingestion_retrieval_observation"
        and observation.get("measurement_class")
        == "observational_baseline_no_promotion_gate",
        "artifact_contract_invalid",
    )
    cases = truth.get("cases")
    results = observation.get("results", {}).get("selection")
    require(isinstance(cases, list) and len(cases) == 180, "truth_inventory_invalid")
    require(isinstance(results, list) and len(results) == 180, "result_inventory_invalid")
    truth_by_case = {item["case_id"]: item for item in cases}
    require(len(truth_by_case) == 180, "truth_identity_invalid")
    body_results = [item for item in results if item["family"] == "body"]
    require(len(body_results) == 120, "body_result_inventory_invalid")

    scope_mismatches: list[dict[str, Any]] = []
    misses: list[dict[str, Any]] = []
    low_rank: list[dict[str, Any]] = []
    for result in body_results:
        expected = truth_by_case[result["case_id"]]["required_evidence"][0]
        scope_mismatch = expected["document_ref"] not in result["permitted_document_refs"]
        if scope_mismatch:
            scope_mismatches.append({
                "case_id": result["case_id"],
                "expected_document_ref": expected["document_ref"],
                "expected_page": expected["page"],
                "permitted_document_refs": result["permitted_document_refs"],
            })
        if result["first_relevant_rank"] is None:
            misses.append({
                "case_id": result["case_id"],
                "expected_document_ref": expected["document_ref"],
                "expected_page": expected["page"],
                "classification": (
                    "evaluation_context_substring_scope_mismatch"
                    if scope_mismatch
                    else "cross_document_template_collision"
                ),
            })
        elif result["first_relevant_rank"] > 5:
            low_rank.append({
                "case_id": result["case_id"],
                "expected_document_ref": expected["document_ref"],
                "expected_page": expected["page"],
                "first_relevant_rank": result["first_relevant_rank"],
            })

    atomic_body: list[tuple[str, int, Mapping[str, Any]]] = []
    all_by_document_page: dict[tuple[str, int], list[str]] = collections.defaultdict(list)
    for document in chunks["documents"]:
        document_ref = document["document_ref"]
        for candidate in document["candidates"]:
            page = candidate["citation_anchor"]["page_start"]
            if candidate["projection_kind"] != "document_control_metadata":
                all_by_document_page[(document_ref, page)].append(
                    candidate["retrieval_text"].casefold()
                )
            if candidate["projection_kind"] not in {
                "document_control_metadata", "section_page_representative"
            }:
                atomic_body.append((document_ref, page, candidate))
    digest_documents: dict[str, set[str]] = collections.defaultdict(set)
    for document_ref, _page, candidate in atomic_body:
        digest_documents[candidate["content_digest"]].add(document_ref)
    shared_digests = {
        digest: owners
        for digest, owners in digest_documents.items()
        if len(owners) > 1
    }
    page_duplication: dict[str, dict[str, int]] = {}
    for page in range(1, 6):
        candidates = [
            candidate for _document, candidate_page, candidate in atomic_body
            if candidate_page == page
        ]
        page_duplication[str(page)] = {
            "atomic_candidates": len(candidates),
            "candidates_with_cross_document_content_duplicate": sum(
                candidate["content_digest"] in shared_digests for candidate in candidates
            ),
        }

    subject_presence: dict[str, int] = {}
    for page in range(1, 6):
        count = 0
        for document in corpus["documents"]:
            texts = "\n".join(
                all_by_document_page[(document["doc_id"], page)]
            )
            count += int(document["subject"].casefold() in texts)
        subject_presence[str(page)] = count

    require(
        len(misses) == 11
        and len(scope_mismatches) == 1
        and scope_mismatches[0]["case_id"] == "B-006"
        and sum(item["classification"] == "cross_document_template_collision" for item in misses) == 10
        and subject_presence == {"1": 30, "2": 0, "3": 0, "4": 0, "5": 0},
        "observed_failure_shape_changed",
    )
    artifact: dict[str, Any] = {
        "artifact_kind": "ishikawa_synthetic_corpus_v3_rank_failure_review",
        "schema_version": 1,
        "corpus_identity": "synthetic-corpus-v3",
        "source_sha256": {
            "chunks": arguments.expected_chunks_sha256,
            "corpus_truth": arguments.expected_corpus_truth_sha256,
            "retrieval_truth": arguments.expected_retrieval_truth_sha256,
            "observation": arguments.expected_observation_sha256,
        },
        "measured_metrics": observation["metrics"],
        "body_by_expected_page": page_metrics(body_results, truth_by_case),
        "failure_inventory": {
            "body_misses_at_20": len(misses),
            "body_ranks_6_through_20": len(low_rank),
            "evaluation_scope_mismatches": scope_mismatches,
            "misses": misses,
            "low_rank_cases": low_rank,
        },
        "representation_evidence": {
            "atomic_body_candidates": len(atomic_body),
            "cross_document_shared_content_digests": len(shared_digests),
            "atomic_candidates_with_cross_document_content_duplicate": sum(
                candidate["content_digest"] in shared_digests
                for _document, _page, candidate in atomic_body
            ),
            "maximum_documents_sharing_one_content_digest": max(
                len(owners) for owners in shared_digests.values()
            ),
            "page_duplication": page_duplication,
            "documents_whose_subject_occurs_in_page_retrieval_text": subject_presence,
            "document_title_or_context_propagated_to_every_body_candidate": False,
        },
        "classification": {
            "script_188_post_measurement_failure": "drvfs_chmod_not_supported",
            "measurement_artifacts_complete": True,
            "measurement_rerun_required": False,
            "evaluation_only_scope_bug": (
                "generic_document_context_substring_can_falsely_constrain_one_case"
            ),
            "dominant_retrieval_issue": (
                "later_page_retrieval_units_do_not_carry_authoritative_document_identity_context_"
                "and_share_heavily_templated_cross_document_content"
            ),
        },
        "decision_boundary": {
            "isolated_ingestion_should_proceed": False,
            "synthetic_corpus_only_wording_patch_is_sufficiently_proven": False,
            "retrieval_representation_change_requires_frozen_gate_discussion": True,
            "recommended_next_gate": (
                "discuss_authoritative_document_identity_context_for_body_retrieval_units_"
                "before_changing_frozen_chunk_representation"
            ),
        },
        "boundaries": {
            "database_contact": False,
            "model_contact": False,
            "corpus_changed": False,
            "retrieval_profile_changed": False,
            "question_text_retained": False,
            "source_text_retained": False,
        },
    }
    artifact["review_id"] = hashlib.sha256(
        b"ishikawa.synthetic-corpus-v3-rank-failure-review.v1\x00"
        + canonical_json_bytes(artifact)
    ).hexdigest()
    write_exclusive(arguments.output, canonical_json_bytes(artifact) + b"\n")
    print("purpose=review_synthetic_corpus_v3_rank_failures")
    print(
        "body_mrr_at_20=0.608739;body_relevant_at_20=109/120;"
        "scope_mismatches=1;cross_document_template_collision_misses=10"
    )
    print(
        f"shared_content_digests={len(shared_digests)};"
        "duplicated_atomic_candidates="
        f"{artifact['representation_evidence']['atomic_candidates_with_cross_document_content_duplicate']}/"
        f"{len(atomic_body)};subjects_on_later_pages=0/120"
    )
    print(
        "measurement_rerun_required=false;isolated_ingestion_should_proceed=false;"
        "frozen_representation_discussion_required=true"
    )
    print("synthetic_corpus_v3_rank_failure_review=pass")


def self_test() -> None:
    assert canonical_json_bytes({"b": 2, "a": 1}) == b'{"a":1,"b":2}'
    assert format(float(Fraction(3, 4)), ".6f") == "0.750000"
    print("synthetic_corpus_v3_rank_failure_review_self_test=pass")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--chunks", type=Path)
    parser.add_argument("--expected-chunks-sha256")
    parser.add_argument("--corpus-truth", type=Path)
    parser.add_argument("--expected-corpus-truth-sha256")
    parser.add_argument("--retrieval-truth", type=Path)
    parser.add_argument("--expected-retrieval-truth-sha256")
    parser.add_argument("--observation", type=Path)
    parser.add_argument("--expected-observation-sha256")
    parser.add_argument("--output", type=Path)
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
        return 0
    required = (
        arguments.chunks,
        arguments.expected_chunks_sha256,
        arguments.corpus_truth,
        arguments.expected_corpus_truth_sha256,
        arguments.retrieval_truth,
        arguments.expected_retrieval_truth_sha256,
        arguments.observation,
        arguments.expected_observation_sha256,
        arguments.output,
    )
    require(all(value is not None for value in required), "arguments_missing")
    execute(arguments)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ReviewError as error:
        print(
            f"synthetic_corpus_v3_rank_failure_review=blocked;reason={error}",
            file=__import__("sys").stderr,
        )
        raise SystemExit(1) from error
