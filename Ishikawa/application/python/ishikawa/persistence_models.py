"""Validated inputs to the incremental PostgreSQL writer.

These models contain already-extracted, already-chunked, and already-embedded
candidate data.  The writer never extracts PDFs or calls a model service.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Any

from .canonical import domain_digest


def _require_digest(value: str, label: str) -> None:
    if len(value) != 64 or any(character not in "0123456789abcdef" for character in value):
        raise ValueError(f"{label} must be a lowercase SHA-256 digest")


def _require_nonblank(value: str, label: str) -> None:
    if not isinstance(value, str) or not value.strip() or value != value.strip():
        raise ValueError(f"{label} must be a trimmed nonblank string")


@dataclass(frozen=True, slots=True)
class EmbeddingSpace:
    model_name: str
    model_revision: str
    model_digest: str
    tokenizer_digest: str
    pooling_method: str
    document_prefix: str
    query_prefix: str
    dimension: int = 768
    maximum_input_tokens: int = 2048
    initial_target_tokens: int = 512
    token_count_mode: str = "with_special_tokens"
    vector_transform: str = "none"
    distance_metric: str = "cosine"
    numeric_tolerance: float = 0.00001

    def __post_init__(self) -> None:
        for label, value in (
            ("model_name", self.model_name),
            ("model_revision", self.model_revision),
            ("pooling_method", self.pooling_method),
        ):
            _require_nonblank(value, label)
        _require_digest(self.model_digest, "model_digest")
        _require_digest(self.tokenizer_digest, "tokenizer_digest")
        if (
            self.dimension != 768
            or self.maximum_input_tokens != 2048
            or self.initial_target_tokens != 512
            or self.token_count_mode != "with_special_tokens"
            or self.numeric_tolerance != 0.00001
        ):
            raise ValueError("embedding space must use the accepted Nomic measurement contract")
        if self.vector_transform != "none" or self.distance_metric != "cosine":
            raise ValueError("embedding space transform or distance metric is unsupported")

    @property
    def identity(self) -> str:
        return domain_digest(
            "ishikawa.embedding-space.v1",
            {
                "schema_version": 1,
                "model_id": self.model_name,
                "model_revision": self.model_revision,
                "model_sha256": self.model_digest,
                "tokenizer_sha256": self.tokenizer_digest,
                "pooling": self.pooling_method,
                "document_prefix": self.document_prefix,
                "dimension": self.dimension,
                "maximum_input_tokens": self.maximum_input_tokens,
                "initial_target_tokens": self.initial_target_tokens,
                "token_count_mode": self.token_count_mode,
                "vector_transform": self.vector_transform,
                "distance": self.distance_metric,
                "numeric_tolerance": self.numeric_tolerance,
            },
        )


@dataclass(frozen=True, slots=True)
class PreparedStructuralUnit:
    ordinal: int
    structural_kind: str
    page_start: int
    page_end: int
    structural_path: tuple[str, ...]
    source_anchor: dict[str, Any]
    normalized_text: str
    parent_ordinal: int | None = None

    def __post_init__(self) -> None:
        _require_nonblank(self.structural_kind, "structural_kind")
        _require_nonblank(self.normalized_text, "normalized_text")
        if self.ordinal < 0 or self.page_start < 1 or self.page_end < self.page_start:
            raise ValueError("invalid structural-unit ordinal or page range")
        if self.parent_ordinal is not None and self.parent_ordinal >= self.ordinal:
            raise ValueError("a structural-unit parent must precede its child")


@dataclass(frozen=True, slots=True)
class PreparedChunk:
    ordinal: int
    projection_kind: str
    retrieval_text: str
    structural_unit_ordinals: tuple[int, ...]
    relevant_excerpt: str
    page_start: int
    page_end: int
    structural_path: tuple[str, ...]
    citation_anchor: dict[str, Any]
    embedding: tuple[float, ...]
    content_token_count: int
    context_token_count: int
    prefix_token_count: int
    special_token_count: int
    submitted_input_digest: str
    processing_profile: str
    authoritative_component_ordinals: tuple[int, ...] = ()
    lexical_search_config: str = "english"
    contextual_fields: dict[str, Any] = field(default_factory=dict)
    retrieval_filters: dict[str, Any] = field(default_factory=dict)
    client_metadata: dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        _require_nonblank(self.projection_kind, "projection_kind")
        _require_nonblank(self.retrieval_text, "retrieval_text")
        _require_nonblank(self.relevant_excerpt, "relevant_excerpt")
        _require_nonblank(self.processing_profile, "processing_profile")
        _require_nonblank(self.lexical_search_config, "lexical_search_config")
        _require_digest(self.submitted_input_digest, "submitted_input_digest")
        if self.ordinal < 0 or self.page_start < 1 or self.page_end < self.page_start:
            raise ValueError("invalid chunk ordinal or page range")
        if not self.structural_unit_ordinals:
            raise ValueError("a chunk must reference at least one structural unit")
        if len(set(self.structural_unit_ordinals)) != len(self.structural_unit_ordinals):
            raise ValueError("chunk structural-unit ordinals must be unique")
        if (
            len(set(self.authoritative_component_ordinals))
            != len(self.authoritative_component_ordinals)
            or any(value < 0 for value in self.authoritative_component_ordinals)
        ):
            raise ValueError("authoritative component ordinals are invalid")
        counts = (
            self.content_token_count,
            self.context_token_count,
            self.prefix_token_count,
            self.special_token_count,
        )
        if any(value < 0 for value in counts) or not 0 < sum(counts) <= 2048:
            raise ValueError("chunk token counts are invalid")
        if len(self.embedding) != 768 or not all(math.isfinite(value) for value in self.embedding):
            raise ValueError("embedding must contain 768 finite values")

    @property
    def total_embedding_token_count(self) -> int:
        return (
            self.content_token_count
            + self.context_token_count
            + self.prefix_token_count
            + self.special_token_count
        )


@dataclass(frozen=True, slots=True)
class PreparedDocument:
    document_key: str
    class_id: str
    source_digest: str
    page_count: int
    processing_profiles: tuple[str, ...]
    structural_units: tuple[PreparedStructuralUnit, ...]
    chunks: tuple[PreparedChunk, ...]
    embedding_space: EmbeddingSpace
    language: str | None = None

    def __post_init__(self) -> None:
        _require_nonblank(self.document_key, "document_key")
        _require_nonblank(self.class_id, "class_id")
        _require_digest(self.source_digest, "source_digest")
        if self.page_count < 1:
            raise ValueError("page_count must be positive")
        if not self.processing_profiles or not self.structural_units or not self.chunks:
            raise ValueError("prepared document must contain profiles, structures, and chunks")
        unit_ordinals = [unit.ordinal for unit in self.structural_units]
        chunk_ordinals = [chunk.ordinal for chunk in self.chunks]
        if unit_ordinals != list(range(len(unit_ordinals))):
            raise ValueError("structural-unit ordinals must be contiguous from zero")
        if chunk_ordinals != list(range(len(chunk_ordinals))):
            raise ValueError("chunk ordinals must be contiguous from zero")
        known_units = set(unit_ordinals)
        for chunk in self.chunks:
            if not set(chunk.structural_unit_ordinals) <= known_units:
                raise ValueError("chunk references an unknown structural-unit ordinal")
            if chunk.page_end > self.page_count:
                raise ValueError("chunk page range exceeds document page count")
            if not set(chunk.authoritative_component_ordinals) <= set(chunk_ordinals):
                raise ValueError("chunk references an unknown authoritative component")
            if chunk.ordinal in chunk.authoritative_component_ordinals:
                raise ValueError("a retrieval representative cannot reference itself")
        for unit in self.structural_units:
            if unit.page_end > self.page_count:
                raise ValueError("structural-unit page range exceeds document page count")


@dataclass(frozen=True, slots=True)
class WriteResult:
    ingestion_run_id: str
    publication_batch_id: str | None
    outcome: str
    published_document_count: int
    retired_document_count: int
    reused_document_count: int
    quarantine_record_count: int
