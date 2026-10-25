#!/usr/bin/env python3
"""Build an isolated corpus-v2 retrieval candidate with sibling assemblies."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import re
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence


HEX_DIGEST = re.compile(r"^[0-9a-f]{64}$")
COMPATIBLE_KINDS = frozenset({"paragraph", "definition", "list_item"})
MAXIMUM_SIBLINGS = 8
MAXIMUM_INPUT_BYTES = 16 * 1024 * 1024


class CandidateError(RuntimeError):
    """Stable candidate-construction failure."""


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise CandidateError(reason)


def canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":"),
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
    require(HEX_DIGEST.fullmatch(expected_sha256) is not None, "source_identity_invalid")
    require(sha256_file(path) == expected_sha256, "source_identity_mismatch")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise CandidateError("source_candidate_invalid") from error
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


def _method_profile(source: Mapping[str, Any]) -> dict[str, Any]:
    source_profile = source.get("method_profile")
    require(isinstance(source_profile, dict), "source_method_profile_invalid")
    profile = dict(source_profile)
    profile.update({
        "name": "ishikawa-structural-chunk-candidates-v5-experimental",
        "compatible_sibling_assembly": (
            "one_additive_same_parent_same_page_narrative_definition_or_list_assembly_"
            "maximum_8_exact_nomic_ceiling_required"
        ),
        "metadata_lane_behavior": (
            "exact_and_explicit_header_or_department_queries_only_for_lexical_and_vector"
        ),
    })
    return profile


def _candidate_identity(candidate: Mapping[str, Any], method_profile_id: str) -> str:
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


def _clone_atomic(candidate: Mapping[str, Any], method_profile_id: str) -> dict[str, Any]:
    cloned = copy.deepcopy(candidate)
    cloned["method_profile_id"] = method_profile_id
    cloned["chunk_id"] = _candidate_identity(cloned, method_profile_id)
    cloned["sequence"] = {
        "previous_chunk_id": None,
        "next_chunk_id": None,
        "continuation_index": 0,
        "previous_continuation_id": None,
        "next_continuation_id": None,
    }
    return cloned


def _assembly_key(candidate: Mapping[str, Any]) -> tuple[Any, ...] | None:
    anchor = candidate.get("citation_anchor")
    if (
        candidate.get("projection_kind") not in COMPATIBLE_KINDS
        or not isinstance(candidate.get("parent_unit_id"), str)
        or not isinstance(anchor, dict)
        or not isinstance(anchor.get("structural_path"), list)
    ):
        return None
    return (
        candidate["parent_unit_id"],
        anchor.get("page_start"),
        anchor.get("page_end"),
        tuple(anchor["structural_path"]),
    )


def compatible_groups(candidates: Sequence[Mapping[str, Any]]) -> tuple[tuple[Mapping[str, Any], ...], ...]:
    groups: list[tuple[Mapping[str, Any], ...]] = []
    current: list[Mapping[str, Any]] = []
    current_key: tuple[Any, ...] | None = None
    for candidate in candidates:
        key = _assembly_key(candidate)
        if key is None or key != current_key or len(current) >= MAXIMUM_SIBLINGS:
            if len(current) >= 2:
                groups.append(tuple(current))
            current = []
            current_key = key
        if key is not None:
            current.append(candidate)
    if len(current) >= 2:
        groups.append(tuple(current))
    return tuple(groups)


def _ordered_unique(values: Iterable[Any]) -> list[Any]:
    result: list[Any] = []
    for value in values:
        if value not in result:
            result.append(value)
    return result


def _merge_lexical_fields(group: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    fields = [candidate["lexical_fields"] for candidate in group]
    controls = [field.get("document_control") for field in fields]
    departments = [field.get("department_aliases") for field in fields]
    require(all(control == controls[0] for control in controls), "assembly_control_mismatch")
    require(all(value == departments[0] for value in departments), "assembly_department_mismatch")
    return {
        "references": sorted({value for field in fields for value in field.get("references", [])}),
        "labels": _ordered_unique(value for field in fields for value in field.get("labels", [])),
        "numeric_values": _ordered_unique(
            value for field in fields for value in field.get("numeric_values", [])
        ),
        "boolean_states": _ordered_unique(
            value for field in fields for value in field.get("boolean_states", [])
        ),
        "document_control": copy.deepcopy(controls[0]),
        "department_aliases": copy.deepcopy(departments[0]),
    }


def _build_assembly(
    group: Sequence[Mapping[str, Any]],
    method_profile_id: str,
) -> dict[str, Any]:
    first = group[0]
    anchors = [candidate["citation_anchor"] for candidate in group]
    require(
        all(candidate["document_id"] == first["document_id"] for candidate in group)
        and all(candidate["document_version_id"] == first["document_version_id"] for candidate in group)
        and all(candidate["parent_unit_id"] == first["parent_unit_id"] for candidate in group)
        and all(candidate["context_text"] == first["context_text"] for candidate in group)
        and all(candidate["retrieval_filters"] == first["retrieval_filters"] for candidate in group),
        "assembly_boundary_mismatch",
    )
    content = "\n".join(candidate["content_text"] for candidate in group)
    context = first["context_text"]
    retrieval = f"{context}\n\n{content}" if context else content
    source_unit_ids = _ordered_unique(
        unit_id for candidate in group for unit_id in candidate["source_unit_ids"]
    )
    context_digest = domain_digest(
        "ishikawa.chunk-context.v1",
        {"context_text": context, "structural_path": anchors[0]["structural_path"]},
    )
    retrieval_digest = domain_digest(
        "ishikawa.retrieval-text.v1", {"retrieval_text": retrieval}
    )
    assembly: dict[str, Any] = {
        "schema_version": 1,
        "chunk_id": "",
        "document_id": first["document_id"],
        "document_version_id": first["document_version_id"],
        "method_profile_id": method_profile_id,
        "projection_kind": "compatible_sibling_assembly",
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
            "anchor_kind": "compatible_sibling_assembly",
            "page_start": anchors[0]["page_start"],
            "page_end": anchors[0]["page_end"],
            "structural_path": copy.deepcopy(anchors[0]["structural_path"]),
            "source_spans": [
                copy.deepcopy(span)
                for anchor in anchors
                for span in anchor.get("source_spans", [])
            ],
            "source_unit_id": source_unit_ids[0],
            "component_source_unit_ids": source_unit_ids,
        },
        "lexical_fields": _merge_lexical_fields(group),
        "projection_properties": {
            "body_overlap_units": 0,
            "source_kind": "compatible_sibling_assembly",
            "component_chunk_ids": [candidate["chunk_id"] for candidate in group],
            "component_projection_kinds": [candidate["projection_kind"] for candidate in group],
            "component_count": len(group),
            "assembly_rule": "same_parent_same_page_adjacent_maximum_8",
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
            "blockers": ["nomic_token_measurement_pending", "retrieval_experiment_pending"],
        },
    }
    assembly["chunk_id"] = _candidate_identity(assembly, method_profile_id)
    return assembly


def _link_sequence(candidates: list[dict[str, Any]]) -> None:
    for index, candidate in enumerate(candidates):
        candidate["sequence"]["previous_chunk_id"] = (
            candidates[index - 1]["chunk_id"] if index else None
        )
        candidate["sequence"]["next_chunk_id"] = (
            candidates[index + 1]["chunk_id"] if index + 1 < len(candidates) else None
        )


def build_candidate(source: Mapping[str, Any], source_sha256: str) -> dict[str, Any]:
    profile = _method_profile(source)
    profile_id = domain_digest("ishikawa.chunk-method-profile.v1", profile)
    documents: list[dict[str, Any]] = []
    all_ids: set[str] = set()
    assembly_count = 0
    for source_document in source["documents"]:
        source_candidates = source_document.get("candidates")
        require(isinstance(source_candidates, list) and source_candidates, "candidate_inventory_invalid")
        atomic = [_clone_atomic(candidate, profile_id) for candidate in source_candidates]
        assemblies = [
            _build_assembly(group, profile_id)
            for group in compatible_groups(atomic)
        ]
        candidates = atomic + assemblies
        _link_sequence(candidates)
        ids = {candidate["chunk_id"] for candidate in candidates}
        require(len(ids) == len(candidates) and not ids.intersection(all_ids), "duplicate_chunk_identity")
        all_ids.update(ids)
        assembly_count += len(assemblies)
        document = copy.deepcopy(source_document)
        document["candidate_count"] = len(candidates)
        document["candidates"] = candidates
        documents.append(document)
    result: dict[str, Any] = {
        "schema_version": 1,
        "artifact_kind": "non_publishable_structural_chunk_candidates",
        "normalization_set_digest": source["normalization_set_digest"],
        "method_profile": profile,
        "method_profile_id": profile_id,
        "token_measurement_status": "pending_authoritative_nomic_measurement",
        "publication_eligible": False,
        "source_candidate_sha256": source_sha256,
        "source_candidate_set_digest": source["chunk_candidate_set_digest"],
        "experiment": {
            "atomic_candidates_preserved": sum(
                len(document["candidates"]) for document in source["documents"]
            ),
            "compatible_sibling_assemblies": assembly_count,
            "metadata_lane_routing": "evaluator_enforced",
            "production_profile_changed": False,
        },
        "documents": documents,
    }
    result["chunk_candidate_set_digest"] = domain_digest(
        "ishikawa.chunk-candidate-set.v1", result
    )
    return result


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


def self_test() -> None:
    candidates = [
        {
            "projection_kind": "list_item",
            "parent_unit_id": "a" * 64,
            "citation_anchor": {"page_start": 1, "page_end": 1, "structural_path": ["I"]},
        },
        {
            "projection_kind": "paragraph",
            "parent_unit_id": "a" * 64,
            "citation_anchor": {"page_start": 1, "page_end": 1, "structural_path": ["I"]},
        },
        {
            "projection_kind": "form_field",
            "parent_unit_id": "a" * 64,
            "citation_anchor": {"page_start": 1, "page_end": 1, "structural_path": ["I"]},
        },
    ]
    groups = compatible_groups(candidates)
    assert len(groups) == 1 and len(groups[0]) == 2
    assert domain_digest("test", {"a": 1}) == domain_digest("test", {"a": 1})
    print("synthetic_corpus_v2_retrieval_candidate_builder_self_test=pass")


def main() -> int:
    parser = argparse.ArgumentParser()
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
    candidate = build_candidate(source, arguments.expected_input_sha256)
    payload = canonical_json_bytes(candidate)
    write_exclusive(arguments.output, payload)
    atomic = candidate["experiment"]["atomic_candidates_preserved"]
    assemblies = candidate["experiment"]["compatible_sibling_assemblies"]
    print(
        f"documents=6;atomic_candidates={atomic};compatible_sibling_assemblies={assemblies};"
        f"candidate_count={atomic + assemblies}"
    )
    print(
        f"method_profile_id={candidate['method_profile_id']};"
        f"candidate_set_digest={candidate['chunk_candidate_set_digest']}"
    )
    print(
        f"artifact_sha256={hashlib.sha256(payload).hexdigest()};artifact_bytes={len(payload)}"
    )
    print("production_profile_changed=false;corpus_ingestion=false")
    print("synthetic_corpus_v2_retrieval_candidate_builder=pass")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except CandidateError as error:
        print(
            f"synthetic_corpus_v2_retrieval_candidate_builder=blocked;reason={error}",
            file=os.sys.stderr,
        )
        raise SystemExit(1)
