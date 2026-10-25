"""Convert accepted extraction artifacts into incremental-writer inputs.

The adapter is deliberately strict.  It joins documents by source SHA-256,
joins chunks and embeddings by producer chunk identity, and refuses partial or
ambiguous coverage.  It never calls a model and never writes PostgreSQL.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .canonical import domain_digest, file_sha256
from .models import IngestionManifest
from .persistence_models import (
    EmbeddingSpace,
    PreparedChunk,
    PreparedDocument,
    PreparedStructuralUnit,
)


class ArtifactAdapterError(RuntimeError):
    """A stable failure at the accepted-artifact/writer boundary."""


def _fail(reason: str) -> None:
    raise ArtifactAdapterError(reason)


def _load_json(path: Path, expected_sha256: str, label: str) -> dict[str, Any]:
    if not path.is_file() or path.is_symlink():
        _fail(f"unsafe_{label}_artifact")
    if file_sha256(str(path)) != expected_sha256:
        _fail(f"{label}_artifact_identity_mismatch")
    try:
        value = json.loads(
            path.read_text(encoding="utf-8"),
            parse_constant=lambda _value: (_ for _ in ()).throw(ValueError()),
        )
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as exc:
        raise ArtifactAdapterError(f"invalid_{label}_artifact") from exc
    if not isinstance(value, dict) or value.get("schema_version") != 1:
        _fail(f"invalid_{label}_artifact")
    return value


def _embedding_space(value: dict[str, Any]) -> EmbeddingSpace:
    raw = value.get("embedding_space")
    if not isinstance(raw, dict):
        _fail("invalid_embedding_space")
    try:
        space = EmbeddingSpace(
            model_name=raw["model_id"],
            model_revision=raw["model_revision"],
            model_digest=raw["model_sha256"],
            tokenizer_digest=raw["tokenizer_sha256"],
            pooling_method=raw["pooling"],
            document_prefix=raw["document_prefix"],
            query_prefix="search_query: ",
            dimension=raw["dimension"],
            maximum_input_tokens=raw["maximum_input_tokens"],
            initial_target_tokens=raw["initial_target_tokens"],
            token_count_mode=raw["token_count_mode"],
            vector_transform=raw["vector_transform"],
            distance_metric=raw["distance"],
            numeric_tolerance=raw["numeric_tolerance"],
        )
    except (KeyError, TypeError, ValueError) as exc:
        raise ArtifactAdapterError("invalid_embedding_space") from exc
    if space.identity != value.get("embedding_space_id"):
        _fail("embedding_space_identity_mismatch")
    return space


def _processing_profile(kind: str) -> str:
    if kind == "page_status":
        return "page_status"
    if kind.startswith("table"):
        return "tables"
    if kind in {"form_field", "checkbox_group"}:
        return "forms"
    if kind == "definition":
        return "definitions"
    return "hierarchical_narrative"


def _manifest_sources(
    manifest: IngestionManifest, source_root: Path
) -> dict[str, tuple[str, str]]:
    root = source_root.resolve(strict=True)
    result: dict[str, tuple[str, str]] = {}
    for item in manifest.documents:
        source = source_root / item.source_path
        if source.is_symlink() or not source.is_file():
            _fail("manifest_source_unavailable")
        resolved = source.resolve(strict=True)
        try:
            resolved.relative_to(root)
        except ValueError as exc:
            raise ArtifactAdapterError("manifest_source_escapes_root") from exc
        digest = file_sha256(str(resolved))
        if digest in result:
            _fail("manifest_source_digest_duplicate")
        result[digest] = (item.document_key, item.class_id)
    return result


def load_prepared_documents(
    *,
    normalized_path: str | Path,
    normalized_sha256: str,
    chunk_path: str | Path,
    chunk_sha256: str,
    embedding_path: str | Path,
    embedding_sha256: str,
    manifest: IngestionManifest,
    source_root: str | Path,
) -> tuple[PreparedDocument, ...]:
    """Load three checksum-bound artifacts and produce writer-ready documents."""

    normalized = _load_json(Path(normalized_path), normalized_sha256, "normalization")
    chunked = _load_json(Path(chunk_path), chunk_sha256, "chunk")
    embedded = _load_json(Path(embedding_path), embedding_sha256, "embedding")

    normalization_set = normalized.get("normalization_set_digest")
    method_profile_id = chunked.get("method_profile_id")
    chunk_set = chunked.get("chunk_candidate_set_digest")
    if chunked.get("normalization_set_digest") != normalization_set:
        _fail("chunk_normalization_link_mismatch")
    if embedded.get("source_chunk_candidate_sha256") != chunk_sha256:
        _fail("embedding_chunk_file_link_mismatch")
    if embedded.get("source_chunk_candidate_set_digest") != chunk_set:
        _fail("embedding_chunk_set_link_mismatch")
    if embedded.get("source_method_profile_id") != method_profile_id:
        _fail("embedding_method_profile_link_mismatch")
    # Qualified embeddings remain fail-closed until their next named gate.
    # The original profile awaited writer integration; the amended profile has
    # already passed that boundary and awaits retrieval recalibration.
    if embedded.get("publication_eligible") is not False:
        _fail("embedding_gate_state_invalid")
    accepted_blocker = {
        "13fd11355c7eee3b35faadea8e14c5df0787eb70578129377c836e55dff303e4":
            "pipeline_writer_integration_pending",
        "5797961aee919aa73bbd99d6cc188084d57d22839a1d4cff0febc2e73e17b4b0":
            "retrieval_profile_calibration_pending",
        "d5df385930cd801abb7296f03f64f6a950bddc6ea9e550b389db215e084a1350":
            "retrieval_profile_calibration_pending",
        "0c16e785006d8f68cf942bf9f76a84d0d837b84be629fe898898d319f45d34a1":
            "retrieval_profile_calibration_pending",
        "d72a07f81eabc1f521ab1fd54f84289979365c6c71f8e3220a53b1e8c9a1c037":
            "retrieval_profile_calibration_pending",
    }.get(method_profile_id)
    if accepted_blocker is None or embedded.get("publication_blocker") != accepted_blocker:
        _fail("embedding_publication_blocker_mismatch")

    space = _embedding_space(embedded)
    embedding_records = embedded.get("records")
    if not isinstance(embedding_records, list) or not embedding_records:
        _fail("invalid_embedding_record_inventory")
    embeddings_by_chunk: dict[str, dict[str, Any]] = {}
    for record in embedding_records:
        if not isinstance(record, dict) or not isinstance(record.get("chunk_id"), str):
            _fail("invalid_embedding_record")
        if record["chunk_id"] in embeddings_by_chunk:
            _fail("duplicate_embedding_record")
        embeddings_by_chunk[record["chunk_id"]] = record

    normalized_documents = normalized.get("documents")
    chunk_documents = chunked.get("documents")
    if not isinstance(normalized_documents, list) or not isinstance(chunk_documents, list):
        _fail("invalid_document_inventory")
    normalized_by_source = {
        item.get("source_sha256"): item for item in normalized_documents if isinstance(item, dict)
    }
    chunked_by_source = {
        item.get("source_sha256"): item for item in chunk_documents if isinstance(item, dict)
    }
    if len(normalized_by_source) != len(normalized_documents):
        _fail("duplicate_normalized_source_identity")
    if len(chunked_by_source) != len(chunk_documents):
        _fail("duplicate_chunk_source_identity")

    configured = _manifest_sources(manifest, Path(source_root))
    if set(configured) != set(normalized_by_source) or set(configured) != set(chunked_by_source):
        _fail("artifact_manifest_source_coverage_mismatch")

    prepared_documents: list[PreparedDocument] = []
    consumed_embeddings: set[str] = set()
    for source_digest, (document_key, class_id) in configured.items():
        source_document = normalized_by_source[source_digest]
        chunk_document = chunked_by_source[source_digest]
        if chunk_document.get("document_ref") != source_document.get("doc_id"):
            _fail("document_reference_mismatch")
        units = source_document.get("units")
        candidates = chunk_document.get("candidates")
        if not isinstance(units, list) or not isinstance(candidates, list):
            _fail("invalid_document_artifact_inventory")
        if chunk_document.get("candidate_count") != len(candidates):
            _fail("chunk_candidate_count_mismatch")
        candidate_ordinals: dict[str, int] = {}
        for candidate_ordinal, candidate in enumerate(candidates):
            producer_identity = (
                candidate.get("chunk_id") if isinstance(candidate, dict) else None
            )
            if (
                not isinstance(producer_identity, str)
                or producer_identity in candidate_ordinals
            ):
                _fail("invalid_chunk_candidate_identity")
            candidate_ordinals[producer_identity] = candidate_ordinal

        unit_ordinals: dict[str, int] = {}
        prepared_units: list[PreparedStructuralUnit] = []
        for expected_ordinal, unit in enumerate(units):
            if not isinstance(unit, dict) or unit.get("ordinal") != expected_ordinal:
                _fail("structural_unit_ordinal_mismatch")
            unit_id = unit.get("unit_id")
            if not isinstance(unit_id, str) or unit_id in unit_ordinals:
                _fail("structural_unit_identity_invalid")
            unit_ordinals[unit_id] = expected_ordinal
            prepared_units.append(
                PreparedStructuralUnit(
                    ordinal=expected_ordinal,
                    structural_kind=unit["kind"],
                    page_start=unit["page_start"],
                    page_end=unit["page_end"],
                    structural_path=tuple(unit["structural_path"]),
                    source_anchor={
                        "source_spans": unit["source_spans"],
                        "producer_unit_id": unit_id,
                        "normalization_rules": unit["rules"],
                    },
                    normalized_text=unit["text"],
                )
            )

        prepared_chunks: list[PreparedChunk] = []
        profiles: set[str] = set()
        for candidate in candidates:
            if not isinstance(candidate, dict) or candidate.get("projection_kind") != "page_status":
                continue
            source_unit_ids = candidate.get("source_unit_ids")
            citation = candidate.get("citation_anchor")
            properties = candidate.get("projection_properties")
            if (
                not isinstance(source_unit_ids, list)
                or len(source_unit_ids) != 1
                or source_unit_ids[0] in unit_ordinals
                or not isinstance(citation, dict)
                or citation.get("anchor_kind") != "page_status"
                or not isinstance(properties, dict)
                or properties.get("source_kind") != "verified_page_inventory"
                or properties.get("blank") is not True
                or properties.get("derived_evidence") is not True
            ):
                _fail("invalid_page_status_candidate")
            producer_unit_id = source_unit_ids[0]
            ordinal = len(prepared_units)
            unit_ordinals[producer_unit_id] = ordinal
            prepared_units.append(
                PreparedStructuralUnit(
                    ordinal=ordinal,
                    structural_kind="page_status",
                    page_start=citation["page_start"],
                    page_end=citation["page_end"],
                    structural_path=tuple(citation["structural_path"]),
                    source_anchor={
                        "source_spans": citation["source_spans"],
                        "producer_unit_id": producer_unit_id,
                        "derived_evidence": True,
                    },
                    normalized_text=candidate["content_text"],
                )
            )
        for ordinal, candidate in enumerate(candidates):
            if not isinstance(candidate, dict):
                _fail("invalid_chunk_candidate")
            producer_chunk_id = candidate.get("chunk_id")
            record = embeddings_by_chunk.get(producer_chunk_id)
            if record is None or producer_chunk_id in consumed_embeddings:
                _fail("embedding_coverage_mismatch")
            consumed_embeddings.add(producer_chunk_id)
            if record.get("embedding_space_id") != space.identity:
                _fail("record_embedding_space_mismatch")
            if candidate.get("method_profile_id") != method_profile_id:
                _fail("candidate_method_profile_mismatch")
            retrieval_text = candidate.get("retrieval_text")
            expected_input_digest = domain_digest(
                "ishikawa.embedding-input.v1",
                {"input": space.document_prefix + retrieval_text},
            )
            if record.get("submitted_input_digest") != expected_input_digest:
                _fail("submitted_input_identity_mismatch")
            accounting = record.get("token_accounting")
            if not isinstance(accounting, dict):
                _fail("invalid_token_accounting")
            content_tokens = accounting.get("content_tokens_without_special")
            context_tokens = accounting.get("context_tokens_without_special")
            prefix_without_special = accounting.get("prefix_tokens_without_special")
            total_without_special = accounting.get("total_without_special")
            total_tokens = accounting.get("total_embedding_input_tokens")
            counts = (content_tokens, context_tokens, prefix_without_special, total_without_special, total_tokens)
            if any(type(value) is not int or value < 0 for value in counts):
                _fail("invalid_token_accounting")
            if content_tokens + context_tokens + prefix_without_special != total_without_special:
                _fail("token_component_sum_mismatch")
            special_tokens = total_tokens - total_without_special
            if special_tokens < 0 or total_tokens > space.maximum_input_tokens:
                _fail("token_total_invalid")
            vector = record.get("vector")
            if record.get("vector_dimension") != space.dimension or not isinstance(vector, list):
                _fail("embedding_dimension_mismatch")

            projection_kind = candidate.get("projection_kind")
            profile = _processing_profile(projection_kind)
            profiles.add(profile)
            properties = candidate.get("projection_properties")
            if not isinstance(properties, dict):
                _fail("candidate_projection_properties_invalid")
            scoring_only = properties.get("retrieval_scoring_only") is True
            component_ids = properties.get("component_chunk_ids", [])
            if scoring_only:
                if (
                    projection_kind != "section_page_representative"
                    or properties.get("atomic_evidence_authoritative") is not True
                    or not isinstance(component_ids, list)
                    or not component_ids
                    or any(
                        not isinstance(value, str) or value == producer_chunk_id
                        for value in component_ids
                    )
                ):
                    _fail("retrieval_representative_invalid")
            elif component_ids:
                _fail("atomic_candidate_components_invalid")
            try:
                component_ordinals = tuple(
                    candidate_ordinals[value] for value in component_ids
                )
            except KeyError as exc:
                raise ArtifactAdapterError("retrieval_representative_component_missing") from exc
            source_unit_ids = candidate.get("source_unit_ids")
            if not isinstance(source_unit_ids, list) or not source_unit_ids:
                _fail("candidate_structural_unit_link_invalid")
            try:
                linked_ordinals = tuple(unit_ordinals[item] for item in source_unit_ids)
            except KeyError as exc:
                raise ArtifactAdapterError("candidate_structural_unit_link_invalid") from exc
            citation = candidate.get("citation_anchor")
            if not isinstance(citation, dict):
                _fail("candidate_citation_invalid")
            retrieval_filters = candidate.get("retrieval_filters", {})
            if not isinstance(retrieval_filters, dict):
                _fail("candidate_retrieval_filters_invalid")
            prepared_chunks.append(
                PreparedChunk(
                    ordinal=ordinal,
                    projection_kind=projection_kind,
                    retrieval_text=retrieval_text,
                    structural_unit_ordinals=linked_ordinals,
                    relevant_excerpt=candidate["content_text"],
                    page_start=citation["page_start"],
                    page_end=citation["page_end"],
                    structural_path=tuple(citation["structural_path"]),
                    citation_anchor=citation,
                    embedding=tuple(vector),
                    content_token_count=content_tokens,
                    context_token_count=context_tokens,
                    prefix_token_count=prefix_without_special,
                    special_token_count=special_tokens,
                    submitted_input_digest=expected_input_digest,
                    processing_profile=profile,
                    authoritative_component_ordinals=component_ordinals,
                    contextual_fields={
                        "content_digest": candidate.get("content_digest"),
                        "lexical_fields": candidate.get("lexical_fields", {}),
                        "projection_properties": properties,
                        "sequence": candidate.get("sequence", {}),
                        "producer_chunk_id": producer_chunk_id,
                        "token_accounting": {
                            **accounting,
                            "special_tokens": special_tokens,
                            "database_token_buckets_are_exact": True,
                        },
                    },
                    retrieval_filters=retrieval_filters,
                    client_metadata={"producer_chunk_id": producer_chunk_id},
                )
            )

        prepared_documents.append(
            PreparedDocument(
                document_key=document_key,
                class_id=class_id,
                source_digest=source_digest,
                page_count=source_document["page_count"],
                processing_profiles=tuple(sorted(profiles)),
                structural_units=tuple(prepared_units),
                chunks=tuple(prepared_chunks),
                embedding_space=space,
                language="en",
            )
        )

    if consumed_embeddings != set(embeddings_by_chunk):
        _fail("embedding_coverage_mismatch")
    return tuple(sorted(prepared_documents, key=lambda item: item.document_key))
