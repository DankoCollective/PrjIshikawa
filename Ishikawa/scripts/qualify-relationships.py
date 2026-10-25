#!/usr/bin/env python3
"""Qualify deterministic relationships against separate synthetic truth."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from ishikawa.canonical import domain_digest, file_sha256
from ishikawa.relationships import (
    ReferenceEvidence,
    ReferenceOwner,
    TraversalEdge,
    expand_one_hop,
    extract_declared_identifiers,
    extract_explicit_references,
    resolve_explicit_references,
    validate_relationship_registry,
)
from ishikawa.validators import validate_ingestion_manifest
from ishikawa.yaml_loader import load_restricted_yaml


def _load_json(path: Path, expected_sha256: str, label: str) -> dict[str, Any]:
    if not path.is_file() or path.is_symlink() or file_sha256(str(path)) != expected_sha256:
        raise ValueError(f"{label}_identity_invalid")
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict) or value.get("schema_version") != 1:
        raise ValueError(f"{label}_schema_invalid")
    return value


def _document_identity(document_key: str) -> str:
    return domain_digest("ishikawa.document.v1", {"document_key": document_key})


def _document_version_identity(document_identity: str, source_digest: str) -> str:
    return domain_digest(
        "ishikawa.document-version.v1",
        {"document_id": document_identity, "source_digest": source_digest},
    )


def _artifact_set_identity(
    document_version_identity: str, method_profile_id: str, class_id: str
) -> str:
    return domain_digest(
        "ishikawa.document-artifact-set.v1",
        {
            "document_version_id": document_version_identity,
            "method_profile_id": method_profile_id,
            "class_id": class_id,
        },
    )


def _citation_identity(artifact_id: str, ordinal: int, candidate: dict[str, Any]) -> str:
    retrieval_digest = domain_digest(
        "ishikawa.retrieval-text.v1", candidate["retrieval_text"]
    )
    chunk_id = domain_digest(
        "ishikawa.chunk.v1",
        {"artifact_set_id": artifact_id, "ordinal": ordinal, "digest": retrieval_digest},
    )
    anchor = candidate["citation_anchor"]
    return domain_digest(
        "ishikawa.citation.v1",
        {
            "chunk_id": chunk_id,
            "page_start": anchor["page_start"],
            "page_end": anchor["page_end"],
        },
    )


def _source_inventory(source_root: Path, manifest: Any) -> dict[str, tuple[str, str]]:
    result: dict[str, tuple[str, str]] = {}
    for item in manifest.documents:
        source = source_root / item.source_path
        if source.is_symlink() or not source.is_file():
            raise ValueError("synthetic_source_unavailable")
        digest = file_sha256(str(source))
        if digest in result:
            raise ValueError("synthetic_source_digest_duplicate")
        result[digest] = (item.document_key, item.class_id)
    return result


def qualify(args: argparse.Namespace) -> dict[str, Any]:
    registry_value = load_restricted_yaml(args.registry, label="relationship registry")
    registry = validate_relationship_registry(registry_value)
    manifest_value = load_restricted_yaml(args.manifest, label="ingestion manifest")
    manifest = validate_ingestion_manifest(manifest_value)
    chunks = _load_json(args.chunks, args.chunks_sha256, "chunk_artifact")
    truth = _load_json(args.truth, args.truth_sha256, "held_out_truth")
    source_inventory = _source_inventory(args.source_root, manifest)
    documents = chunks.get("documents")
    if not isinstance(documents, list) or len(documents) != 6:
        raise ValueError("chunk_document_inventory_invalid")
    if set(source_inventory) != {item.get("source_sha256") for item in documents}:
        raise ValueError("chunk_manifest_coverage_mismatch")

    owners: list[ReferenceOwner] = []
    raw_evidence: list[ReferenceEvidence] = []
    identities: dict[str, tuple[str, str, str, str]] = {}
    for document in documents:
        source_digest = document["source_sha256"]
        document_key, class_id = source_inventory[source_digest]
        document_id = _document_identity(document_key)
        version_id = _document_version_identity(document_id, source_digest)
        artifact_id = _artifact_set_identity(version_id, chunks["method_profile_id"], class_id)
        identities[document["document_ref"]] = (document_key, document_id, version_id, artifact_id)
        candidates = document.get("candidates")
        if not isinstance(candidates, list) or document.get("candidate_count") != len(candidates):
            raise ValueError("chunk_candidate_inventory_invalid")
        aliases = extract_declared_identifiers(
            candidate.get("content_text") for candidate in candidates
        )
        if len(aliases) != 1:
            raise ValueError("synthetic_document_identifier_declaration_invalid")
        owners.append(ReferenceOwner(aliases[0], document_key, document_id))

        for ordinal, candidate in enumerate(candidates):
            text = candidate.get("content_text")
            citation = candidate.get("citation_anchor")
            if not isinstance(text, str) or not isinstance(citation, dict):
                raise ValueError("chunk_relationship_evidence_invalid")
            unit_id = citation.get("source_unit_id")
            if not isinstance(unit_id, str) or len(unit_id) != 64:
                raise ValueError("chunk_relationship_unit_identity_invalid")
            citation_id = _citation_identity(artifact_id, ordinal, candidate)
            for reference in extract_explicit_references(text):
                raw_evidence.append(
                    ReferenceEvidence(
                        document_key,
                        document_id,
                        version_id,
                        artifact_id,
                        unit_id,
                        citation_id,
                        reference,
                        citation["page_start"],
                    )
                )

    # The chunker's lexical identifier inventory also contains record-instance
    # identifiers (for example request or event IDs).  An identifier becomes a
    # document relationship candidate only when a candidate-corpus document
    # declares that identifier as its own.  This keeps lexical identifiers
    # available for exact search without inventing document edges.
    declared = {item.reference_value for item in owners}
    evidence = [item for item in raw_evidence if item.reference_value in declared]
    non_document_identifiers = len(raw_evidence) - len(evidence)
    observations = resolve_explicit_references(tuple(evidence), tuple(owners), registry)
    unresolved = [item for item in observations if item.requires_quarantine]
    accepted = [item for item in observations if item.outcome == "accepted"]
    ignored = [item for item in observations if item.outcome == "ignored"]
    if unresolved:
        raise ValueError("synthetic_relationship_resolution_unresolved")

    truth_documents = truth.get("documents")
    truth_edges = truth.get("cross_references")
    if not isinstance(truth_documents, list) or not isinstance(truth_edges, list):
        raise ValueError("held_out_relationship_truth_invalid")
    filename_to_key = {
        item.source_path: item.document_key for item in manifest.documents
    }
    truth_ref_to_key: dict[str, str] = {}
    for document in truth_documents:
        filename = document.get("filename")
        doc_ref = document.get("doc_id")
        if filename not in filename_to_key or not isinstance(doc_ref, str):
            raise ValueError("held_out_document_mapping_invalid")
        truth_ref_to_key[doc_ref] = filename_to_key[filename]

    actual = {
        (
            item.evidence.source_document_key,
            item.evidence.page_start,
            item.edge.target_document_key,
        )
        for item in accepted
        if item.edge is not None
    }
    expected: set[tuple[str, int, str]] = set()
    for item in truth_edges:
        source_ref, page_text = item["from"].rsplit(":", 1)
        target_ref, _target_page = item["to"].rsplit(":", 1)
        expected.add((truth_ref_to_key[source_ref], int(page_text), truth_ref_to_key[target_ref]))
    missing = expected - actual
    if missing:
        raise ValueError("held_out_relationship_coverage_failed")

    traversal_edges: list[TraversalEdge] = []
    seen_traversal: set[tuple[str, str]] = set()
    key_to_identity = {key: (document_id, version_id) for key, document_id, version_id, _ in identities.values()}
    for item in accepted:
        edge = item.edge
        if edge is None or edge.target_document_key is None:
            continue
        target_id, target_version_id = key_to_identity[edge.target_document_key]
        pair = (item.evidence.source_document_identity, target_id)
        if pair in seen_traversal:
            continue
        seen_traversal.add(pair)
        traversal_edges.append(
            TraversalEdge(
                edge.relationship_id,
                edge.relationship_type,
                item.evidence.source_document_identity,
                target_id,
                target_version_id,
                edge.evidence_citation_identity,
            )
        )
    allowed = {document_id for _, document_id, _, _ in identities.values()}
    traversal_covered = 0
    for source_key, _page, target_key in sorted(expected):
        source_id, _ = key_to_identity[source_key]
        target_id, _ = key_to_identity[target_key]
        expanded = expand_one_hop(
            (source_id,), tuple(traversal_edges),
            allowed_document_identities=allowed,
            registry=registry,
        )
        if target_id in {item.target_document_identity for item in expanded}:
            traversal_covered += 1
    if traversal_covered != len(expected):
        raise ValueError("held_out_relationship_traversal_failed")

    return {
        "relationship_registry_sha256": file_sha256(str(args.registry)),
        "relationship_registry_id": registry.digest,
        "relationship_method_profile_id": registry.method_profile_id,
        "base_retrieval_profile_id": registry.base_retrieval_profile_id,
        "chunk_method_profile_id": chunks["method_profile_id"],
        "documents": len(documents),
        "declared_identifiers": len(owners),
        "reference_observations": len(observations),
        "non_document_identifier_observations": non_document_identifiers,
        "accepted_internal_edges": len(accepted),
        "ignored_self_references": len(ignored),
        "unresolved_references": len(unresolved),
        "held_out_relationships": len(expected),
        "held_out_relationships_covered": len(expected) - len(missing),
        "held_out_traversals_covered": traversal_covered,
        "maximum_hops": registry.maximum_hops,
        "model_assisted_discovery": False,
        "routine_relationship_manifest": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--registry", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--chunks", type=Path, required=True)
    parser.add_argument("--chunks-sha256", required=True)
    parser.add_argument("--truth", type=Path, required=True)
    parser.add_argument("--truth-sha256", required=True)
    args = parser.parse_args()
    result = qualify(args)
    for key, value in result.items():
        rendered = str(value).lower() if isinstance(value, bool) else str(value)
        print(f"{key}={rendered}")
    print("relationship_contract_qualification=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
