#!/usr/bin/env python3
"""Build retrieval-only section/page representatives for corpus v2."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence


HEX = re.compile(r"^[0-9a-f]{64}$")
MAXIMUM_INPUT_BYTES = 32 * 1024 * 1024


class RepresentativeError(RuntimeError):
    """Stable representative-construction failure."""


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise RepresentativeError(reason)


def canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, allow_nan=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")


def domain_digest(domain: str, value: Any) -> str:
    digest = hashlib.sha256()
    digest.update(domain.encode("ascii"))
    digest.update(b"\x00")
    digest.update(canonical_json_bytes(value))
    return digest.hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_source(path: Path, expected_sha256: str) -> dict[str, Any]:
    require(
        path.is_absolute()
        and path.is_file()
        and not path.is_symlink()
        and path.stat().st_size <= MAXIMUM_INPUT_BYTES,
        "source_candidate_unsafe",
    )
    require(HEX.fullmatch(expected_sha256) is not None, "source_identity_invalid")
    require(sha256_file(path) == expected_sha256, "source_identity_mismatch")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise RepresentativeError("source_candidate_invalid") from error
    require(
        isinstance(value, dict)
        and value.get("schema_version") == 1
        and value.get("artifact_kind") == "non_publishable_structural_chunk_candidates"
        and value.get("publication_eligible") is False
        and isinstance(value.get("documents"), list)
        and len(value["documents"]) == 6,
        "source_candidate_invalid",
    )
    return value


def ordered_unique(values: Iterable[Any]) -> list[Any]:
    result: list[Any] = []
    for value in values:
        if value not in result:
            result.append(value)
    return result


def merge_lexical_fields(group: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    fields = [candidate["lexical_fields"] for candidate in group]
    controls = [field.get("document_control") for field in fields]
    aliases = [field.get("department_aliases") for field in fields]
    require(all(item == controls[0] for item in controls), "group_control_mismatch")
    require(all(item == aliases[0] for item in aliases), "group_department_mismatch")
    return {
        "references": sorted({value for field in fields for value in field.get("references", [])}),
        "labels": ordered_unique(value for field in fields for value in field.get("labels", [])),
        "numeric_values": ordered_unique(
            value for field in fields for value in field.get("numeric_values", [])
        ),
        "boolean_states": ordered_unique(
            value for field in fields for value in field.get("boolean_states", [])
        ),
        "document_control": copy.deepcopy(controls[0]),
        "department_aliases": copy.deepcopy(aliases[0]),
    }


def profile(source: Mapping[str, Any]) -> dict[str, Any]:
    value = copy.deepcopy(source.get("method_profile"))
    require(isinstance(value, dict), "source_method_profile_invalid")
    value.update({
        "name": "ishikawa-section-page-representatives-v1-experimental",
        "section_page_representative": (
            "retrieval_only_same_document_version_parent_structural_unit_and_physical_page"
        ),
        "selected_group_expansion": "ordered_authoritative_atomic_members",
        "production_profile_changed": False,
    })
    return value


def candidate_identity(candidate: Mapping[str, Any], method_profile_id: str) -> str:
    return domain_digest(
        "ishikawa.chunk.v1",
        {
            "document_version_id": candidate["document_version_id"],
            "method_profile_id": method_profile_id,
            "projection_kind": candidate["projection_kind"],
            "source_unit_ids": candidate["source_unit_ids"],
            "context_digest": candidate["context_digest"],
            "retrieval_text_digest": candidate["retrieval_text_digest"],
        },
    )


def build_representative(
    group: Sequence[Mapping[str, Any]], method_profile_id: str
) -> dict[str, Any]:
    first = group[0]
    anchors = [candidate["citation_anchor"] for candidate in group]
    require(
        len(group) >= 1
        and all(candidate["document_id"] == first["document_id"] for candidate in group)
        and all(candidate["document_version_id"] == first["document_version_id"] for candidate in group)
        and all(candidate["parent_unit_id"] == first["parent_unit_id"] for candidate in group)
        and all(candidate["retrieval_filters"] == first["retrieval_filters"] for candidate in group)
        and all(anchor["page_start"] == anchor["page_end"] for anchor in anchors)
        and len({anchor["page_start"] for anchor in anchors}) == 1
        and len({tuple(anchor["structural_path"]) for anchor in anchors}) == 1,
        "section_page_boundary_mismatch",
    )
    content = "\n\n".join(candidate["content_text"] for candidate in group)
    # A table-context atom may carry one extra retrieval-only context line.
    # The representative emits the structural section heading once and keeps
    # the table context in the ordered member content.
    context = min(
        (candidate["context_text"] for candidate in group),
        key=lambda value: (len(value), value),
    )
    retrieval = f"{context}\n\n{content}" if context else content
    source_unit_ids = ordered_unique(
        unit for candidate in group for unit in candidate["source_unit_ids"]
    )
    structural_path = copy.deepcopy(anchors[0]["structural_path"])
    context_digest = domain_digest(
        "ishikawa.chunk-context.v1",
        {"context_text": context, "structural_path": structural_path},
    )
    retrieval_digest = domain_digest(
        "ishikawa.retrieval-text.v1", {"retrieval_text": retrieval}
    )
    value: dict[str, Any] = {
        "schema_version": 1,
        "chunk_id": "",
        "document_id": first["document_id"],
        "document_version_id": first["document_version_id"],
        "method_profile_id": method_profile_id,
        "projection_kind": "section_page_representative",
        "source_unit_ids": source_unit_ids,
        "parent_unit_id": first["parent_unit_id"],
        "content_text": content,
        "context_text": context,
        "retrieval_text": retrieval,
        "content_digest": domain_digest(
            "ishikawa.chunk-content.v1", {"content_text": content}
        ),
        "context_digest": context_digest,
        "retrieval_text_digest": retrieval_digest,
        "citation_anchor": {
            "anchor_kind": "section_page_representative",
            "page_start": anchors[0]["page_start"],
            "page_end": anchors[0]["page_end"],
            "structural_path": structural_path,
            "source_spans": [
                copy.deepcopy(span)
                for anchor in anchors
                for span in anchor.get("source_spans", [])
            ],
            "source_unit_id": source_unit_ids[0],
            "component_source_unit_ids": source_unit_ids,
        },
        "lexical_fields": merge_lexical_fields(group),
        "projection_properties": {
            "body_overlap_units": 0,
            "source_kind": "section_page_representative",
            "component_chunk_ids": [candidate["chunk_id"] for candidate in group],
            "component_projection_kinds": [candidate["projection_kind"] for candidate in group],
            "component_count": len(group),
            "assembly_rule": (
                "same_document_version_parent_structural_unit_and_physical_page_all_members"
            ),
            "retrieval_scoring_only": True,
            "atomic_evidence_authoritative": True,
        },
        "retrieval_filters": copy.deepcopy(first["retrieval_filters"]),
        "sequence": {
            "previous_chunk_id": None,
            "next_chunk_id": None,
            "continuation_index": 0,
            "previous_continuation_id": None,
            "next_continuation_id": None,
        },
        "token_accounting": {
            "status": "pending_authoritative_nomic_measurement",
            "tokenizer_identity": None,
            "content_tokens": None,
            "context_tokens": None,
            "prefix_tokens": None,
            "total_embedding_input_tokens": None,
        },
        "publication_eligibility": {
            "eligible": False,
            "blockers": ["retrieval_experiment_only", "not_authoritative_evidence"],
        },
    }
    value["chunk_id"] = candidate_identity(value, method_profile_id)
    return value


def build(source: Mapping[str, Any], source_sha256: str) -> dict[str, Any]:
    method_profile = profile(source)
    method_profile_id = domain_digest("ishikawa.chunk-method-profile.v1", method_profile)
    documents: list[dict[str, Any]] = []
    all_ids: set[str] = set()
    group_sizes: list[int] = []
    for source_document in source["documents"]:
        groups: dict[tuple[Any, ...], list[dict[str, Any]]] = defaultdict(list)
        for candidate in source_document["candidates"]:
            anchor = candidate.get("citation_anchor")
            if (
                candidate.get("projection_kind") != "document_control_metadata"
                and isinstance(candidate.get("parent_unit_id"), str)
                and isinstance(anchor, dict)
                and anchor.get("page_start") == anchor.get("page_end")
                and isinstance(anchor.get("structural_path"), list)
            ):
                groups[(
                    candidate["parent_unit_id"],
                    anchor["page_start"],
                    tuple(anchor["structural_path"]),
                )].append(candidate)
        representatives = [
            build_representative(group, method_profile_id)
            for group in groups.values()
        ]
        group_sizes.extend(len(group) for group in groups.values())
        ids = {item["chunk_id"] for item in representatives}
        require(len(ids) == len(representatives) and not ids & all_ids, "duplicate_identity")
        all_ids.update(ids)
        document = copy.deepcopy(source_document)
        document["candidate_count"] = len(representatives)
        document["candidates"] = representatives
        documents.append(document)
    require(len(all_ids) == 29 and sum(group_sizes) == 123, "representative_inventory_changed")
    result: dict[str, Any] = {
        "schema_version": 1,
        "artifact_kind": "non_publishable_structural_chunk_candidates",
        "normalization_set_digest": source["normalization_set_digest"],
        "method_profile": method_profile,
        "method_profile_id": method_profile_id,
        "token_measurement_status": "pending_authoritative_nomic_measurement",
        "publication_eligible": False,
        "source_candidate_sha256": source_sha256,
        "source_candidate_set_digest": source["chunk_candidate_set_digest"],
        "experiment": {
            "section_page_representatives": len(all_ids),
            "grouped_atomic_candidates": sum(group_sizes),
            "minimum_group_members": min(group_sizes),
            "maximum_group_members": max(group_sizes),
            "retrieval_scoring_only": True,
            "atomic_evidence_authoritative": True,
            "production_profile_changed": False,
        },
        "documents": documents,
    }
    digest_input = copy.deepcopy(result)
    result["chunk_candidate_set_digest"] = domain_digest(
        "ishikawa.chunk-candidate-set.v1", digest_input
    )
    return result


def write_exclusive(path: Path, payload: bytes) -> None:
    require(
        path.is_absolute()
        and path.parent.is_dir()
        and not path.parent.is_symlink()
        and not path.exists()
        and not path.is_symlink(),
        "output_path_unsafe",
    )
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)


def self_test() -> None:
    assert domain_digest("x", {"a": 1}) == domain_digest("x", {"a": 1})
    assert ordered_unique(["a", "b", "a"]) == ["a", "b"]
    print("published_v2_section_page_representative_builder_self_test=pass")


def main() -> int:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--input", type=Path)
    parser.add_argument("--expected-input-sha256")
    parser.add_argument("--output", type=Path)
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
        return 0
    require(
        arguments.input is not None
        and arguments.expected_input_sha256 is not None
        and arguments.output is not None,
        "required_argument_missing",
    )
    source = load_source(arguments.input, arguments.expected_input_sha256)
    result = build(source, arguments.expected_input_sha256)
    payload = canonical_json_bytes(result) + b"\n"
    write_exclusive(arguments.output, payload)
    print(
        "documents=6;section_page_representatives=29;grouped_atomic_candidates=123;"
        "publication_eligible=false"
    )
    print(f"artifact_sha256={hashlib.sha256(payload).hexdigest()};artifact_bytes={len(payload)}")
    print("published_v2_section_page_representative_builder=pass")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RepresentativeError as error:
        print(
            f"published_v2_section_page_representative_builder=blocked;reason={error}",
            file=sys.stderr,
        )
        raise SystemExit(1)
