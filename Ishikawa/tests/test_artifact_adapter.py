#!/usr/bin/env python3
"""Hermetic regression checks for artifact-to-writer conversion.

The original checks depended on historical artifacts in a sibling repository
and were named so normal unittest discovery skipped them.  These tests create
the smallest complete accepted artifact set in a protected temporary directory
and therefore run in every ordinary application test pass.
"""

from __future__ import annotations

import copy
import json
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path

from ishikawa.artifact_adapter import ArtifactAdapterError, load_prepared_documents
from ishikawa.canonical import domain_digest, file_sha256
from ishikawa.document_producer import (
    NativeDocumentProducer,
    ProducerArtifactBundle,
)
from ishikawa.operator_ingestion import DocumentProductionRequest, ProductionBatch
from ishikawa.persistence import CONSOLIDATED_SCHEMA_V5_SHA256, write_incremental_plan
from ishikawa.persistence_models import EmbeddingSpace
from ishikawa.planner import plan_ingestion
from ishikawa.validators import (
    validate_class_registry,
    validate_document_catalog,
    validate_ingestion_manifest,
)


METHOD_PROFILE_ID = "d72a07f81eabc1f521ab1fd54f84289979365c6c71f8e3220a53b1e8c9a1c037"


def _write_json(path: Path, value: dict) -> str:
    path.write_text(json.dumps(value, sort_keys=True), encoding="utf-8")
    return file_sha256(str(path))


class _Cursor:
    def __init__(self, rows=()):
        self.rows = list(rows)

    def fetchone(self):
        return self.rows[0] if self.rows else None

    def fetchall(self):
        return list(self.rows)


class _Transaction:
    def __init__(self, connection):
        self.connection = connection

    def __enter__(self):
        self.connection.transaction_entries += 1
        return self

    def __exit__(self, kind, _value, _traceback):
        if kind is None:
            self.connection.commits += 1
        else:
            self.connection.rollbacks += 1
        return False


class _WriteConnection:
    """Minimal transaction-aware PostgreSQL double for the publication proof."""

    def __init__(self):
        self.calls = []
        self.transaction_entries = 0
        self.commits = 0
        self.rollbacks = 0

    def transaction(self):
        return _Transaction(self)

    def execute(self, sql, parameters=()):
        self.calls.append((" ".join(sql.split()), tuple(parameters)))
        if "ishikawa.verify-schema" in sql:
            return _Cursor(
                [
                    (
                        "ishikawa_consolidated_schema_v5|"
                        f"{CONSOLIDATED_SCHEMA_V5_SHA256}|5",
                    )
                ]
            )
        if "ishikawa.load-published-state" in sql:
            return _Cursor()
        if "ishikawa.active-embedding-space" in sql:
            return _Cursor([("",)])
        return _Cursor()

    def tags(self):
        return [
            sql.split("*/", 1)[0].split("/* ", 1)[1].strip()
            for sql, _ in self.calls
            if sql.startswith("/* ")
        ]


class ArtifactAdapterTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="ishikawa-artifact-adapter.")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source_root = self.root / "source"
        self.source_root.mkdir()
        self.source = self.source_root / "alpha.pdf"
        self.source.write_bytes(b"%PDF-1.4\nhermetic artifact fixture\n%%EOF\n")
        self.source_sha256 = file_sha256(str(self.source))
        self.manifest = validate_ingestion_manifest(
            {
                "schema_version": 1,
                "documents": [
                    {
                        "source_path": "alpha.pdf",
                        "document_key": "policy.alpha",
                        "class_id": "policy",
                    }
                ],
                "retirements": [],
            }
        )

        self.unit_id = "1" * 64
        self.chunk_id = "2" * 64
        self.document_id = "3" * 64
        self.normalization_set_digest = "4" * 64
        self.chunk_set_digest = "5" * 64
        self.content = "Operators follow the approved policy."
        self.retrieval = "Section: I. Purpose\n\n" + self.content

        space = EmbeddingSpace(
            model_name="nomic-ai/nomic-embed-text-v1.5",
            model_revision="accepted",
            model_digest="6" * 64,
            tokenizer_digest="7" * 64,
            pooling_method="mean_tokens",
            document_prefix="search_document: ",
            query_prefix="search_query: ",
            dimension=768,
            maximum_input_tokens=2048,
            initial_target_tokens=512,
            token_count_mode="with_special_tokens",
            vector_transform="none",
            distance_metric="cosine",
            numeric_tolerance=0.00001,
        )
        self.embedding_space_id = space.identity
        self.embedding_space = {
            "schema_version": 1,
            "model_id": space.model_name,
            "model_revision": space.model_revision,
            "model_sha256": space.model_digest,
            "tokenizer_sha256": space.tokenizer_digest,
            "pooling": space.pooling_method,
            "document_prefix": space.document_prefix,
            "dimension": space.dimension,
            "maximum_input_tokens": space.maximum_input_tokens,
            "initial_target_tokens": space.initial_target_tokens,
            "token_count_mode": space.token_count_mode,
            "vector_transform": space.vector_transform,
            "distance": space.distance_metric,
            "numeric_tolerance": space.numeric_tolerance,
        }

        self.normalized = {
            "schema_version": 1,
            "normalization_set_digest": self.normalization_set_digest,
            "documents": [
                {
                    "source_sha256": self.source_sha256,
                    "doc_id": self.document_id,
                    "page_count": 1,
                    "units": [
                        {
                            "ordinal": 0,
                            "unit_id": self.unit_id,
                            "kind": "paragraph",
                            "page_start": 1,
                            "page_end": 1,
                            "structural_path": ["I. Purpose"],
                            "source_spans": [{"page": 1, "line_id": "p0001-l0001"}],
                            "rules": ["unicode_nfc_v1"],
                            "text": self.content,
                        }
                    ],
                }
            ],
        }
        self.chunked = {
            "schema_version": 1,
            "normalization_set_digest": self.normalization_set_digest,
            "method_profile_id": METHOD_PROFILE_ID,
            "chunk_candidate_set_digest": self.chunk_set_digest,
            "documents": [
                {
                    "source_sha256": self.source_sha256,
                    "document_ref": self.document_id,
                    "candidate_count": 1,
                    "candidates": [
                        {
                            "chunk_id": self.chunk_id,
                            "method_profile_id": METHOD_PROFILE_ID,
                            "projection_kind": "paragraph",
                            "retrieval_text": self.retrieval,
                            "content_text": self.content,
                            "content_digest": domain_digest(
                                "ishikawa.test-content.v1", {"text": self.content}
                            ),
                            "source_unit_ids": [self.unit_id],
                            "citation_anchor": {
                                "anchor_kind": "paragraph",
                                "page_start": 1,
                                "page_end": 1,
                                "structural_path": ["I. Purpose"],
                                "source_spans": [
                                    {"page": 1, "line_id": "p0001-l0001"}
                                ],
                            },
                            "projection_properties": {
                                "source_kind": "paragraph",
                                "source_ordinal": 0,
                            },
                            "lexical_fields": {},
                            "sequence": {},
                            "retrieval_filters": {},
                        }
                    ],
                }
            ],
        }
        self.embedded = {
            "schema_version": 1,
            "source_chunk_candidate_set_digest": self.chunk_set_digest,
            "source_method_profile_id": METHOD_PROFILE_ID,
            "embedding_space": self.embedding_space,
            "embedding_space_id": self.embedding_space_id,
            "publication_eligible": False,
            "publication_blocker": "retrieval_profile_calibration_pending",
            "records": [
                {
                    "schema_version": 1,
                    "chunk_id": self.chunk_id,
                    "embedding_space_id": self.embedding_space_id,
                    "submitted_input_digest": domain_digest(
                        "ishikawa.embedding-input.v1",
                        {"input": "search_document: " + self.retrieval},
                    ),
                    "token_accounting": {
                        "content_tokens_without_special": 6,
                        "context_tokens_without_special": 4,
                        "prefix_tokens_without_special": 2,
                        "total_without_special": 12,
                        "total_embedding_input_tokens": 14,
                    },
                    "vector_dimension": 768,
                    "vector": [0.0] * 768,
                }
            ],
        }

    def load(self, *, normalized=None, chunked=None, embedded=None, manifest=None):
        normalized_path = self.root / "normalized.json"
        chunk_path = self.root / "chunks.json"
        embedding_path = self.root / "embeddings.json"
        normalized_sha = _write_json(normalized_path, normalized or self.normalized)
        chunk_sha = _write_json(chunk_path, chunked or self.chunked)
        selected_embedding = copy.deepcopy(embedded or self.embedded)
        selected_embedding["source_chunk_candidate_sha256"] = chunk_sha
        embedding_sha = _write_json(embedding_path, selected_embedding)
        return load_prepared_documents(
            normalized_path=normalized_path,
            normalized_sha256=normalized_sha,
            chunk_path=chunk_path,
            chunk_sha256=chunk_sha,
            embedding_path=embedding_path,
            embedding_sha256=embedding_sha,
            manifest=manifest or self.manifest,
            source_root=self.source_root,
        )

    def test_complete_artifact_set_is_writer_ready(self):
        documents = self.load()
        self.assertEqual(len(documents), 1)
        document = documents[0]
        self.assertEqual(document.document_key, "policy.alpha")
        self.assertEqual(document.source_digest, self.source_sha256)
        self.assertEqual(len(document.structural_units), 1)
        self.assertEqual(len(document.chunks), 1)
        self.assertEqual(document.embedding_space.identity, self.embedding_space_id)
        self.assertEqual(document.chunks[0].total_embedding_token_count, 14)

    def test_changed_pdf_runs_adapter_and_atomic_publication(self):
        """Prove source identity through artifacts into one committed batch."""

        normalized_path = self.root / "stage-normalized.json"
        chunk_path = self.root / "stage-chunks.json"
        embedding_path = self.root / "stage-embeddings.json"

        def stage(_batch, _manifest, _workspace):
            normalized_sha = _write_json(normalized_path, self.normalized)
            chunk_sha = _write_json(chunk_path, self.chunked)
            embedded = copy.deepcopy(self.embedded)
            embedded["source_chunk_candidate_sha256"] = chunk_sha
            embedding_sha = _write_json(embedding_path, embedded)
            # The producer requires artifacts inside its protected workspace.
            workspace = _workspace
            local_normalized = workspace / "normalized.json"
            local_chunks = workspace / "chunks.json"
            local_embeddings = workspace / "embeddings.json"
            local_normalized.write_bytes(normalized_path.read_bytes())
            local_chunks.write_bytes(chunk_path.read_bytes())
            local_embeddings.write_bytes(embedding_path.read_bytes())
            return ProducerArtifactBundle(
                local_normalized,
                normalized_sha,
                local_chunks,
                chunk_sha,
                local_embeddings,
                embedding_sha,
            )

        retained = []
        work_root = self.root / "work"
        work_root.mkdir()
        producer = NativeDocumentProducer(
            self.manifest,
            work_root.resolve(),
            stage,
            retained.append,
        )
        request = DocumentProductionRequest(
            "add",
            "policy.alpha",
            "policy",
            "alpha.pdf",
            self.source_sha256,
        )
        prepared = producer(
            ProductionBatch(
                "8" * 64,
                METHOD_PROFILE_ID,
                self.source_root.resolve(),
                (request,),
            )
        )

        registry = validate_class_registry(
            {
                "schema_version": 1,
                "classes": [
                    {
                        "class_id": "policy",
                        "display_name": "Policy",
                        "status": "active",
                    }
                ],
            }
        )
        catalog = validate_document_catalog(
            {
                "schema_version": 1,
                "documents": [
                    {
                        "document_key": "policy.alpha",
                        "display_name": "Alpha Policy",
                        "status": "active",
                    }
                ],
            }
        )
        plan = plan_ingestion(
            registry,
            catalog,
            self.manifest,
            source_root=self.source_root,
            method_profile_id=METHOD_PROFILE_ID,
            published_state=(),
        )
        connection = _WriteConnection()
        result = write_incremental_plan(
            connection,
            registry,
            catalog,
            self.manifest,
            plan,
            prepared,
        )

        self.assertEqual(result.outcome, "PUBLISHED")
        self.assertEqual(result.published_document_count, 1)
        self.assertEqual(connection.transaction_entries, 1)
        self.assertEqual(connection.commits, 1)
        self.assertEqual(connection.rollbacks, 0)
        self.assertEqual(len(retained), 1)
        for required in (
            "ishikawa.insert-document-version",
            "ishikawa.insert-structural-unit",
            "ishikawa.insert-chunk",
            "ishikawa.insert-citation",
            "ishikawa.insert-embedding",
            "ishikawa.publish-batch",
        ):
            self.assertIn(required, connection.tags())

    def test_manifest_must_cover_exact_accepted_sources(self):
        incomplete = replace(self.manifest, documents=())
        with self.assertRaisesRegex(
            ArtifactAdapterError, "artifact_manifest_source_coverage_mismatch"
        ):
            self.load(manifest=incomplete)

    def test_duplicate_embedding_is_rejected(self):
        embedded = copy.deepcopy(self.embedded)
        embedded["records"].append(copy.deepcopy(embedded["records"][0]))
        with self.assertRaisesRegex(ArtifactAdapterError, "duplicate_embedding_record"):
            self.load(embedded=embedded)

    def test_missing_embedding_is_rejected(self):
        embedded = copy.deepcopy(self.embedded)
        embedded["records"] = []
        with self.assertRaisesRegex(
            ArtifactAdapterError, "invalid_embedding_record_inventory"
        ):
            self.load(embedded=embedded)

    def test_submitted_input_identity_is_recomputed(self):
        embedded = copy.deepcopy(self.embedded)
        embedded["records"][0]["submitted_input_digest"] = "0" * 64
        with self.assertRaisesRegex(
            ArtifactAdapterError, "submitted_input_identity_mismatch"
        ):
            self.load(embedded=embedded)

    def test_vector_dimension_is_enforced(self):
        embedded = copy.deepcopy(self.embedded)
        embedded["records"][0]["vector_dimension"] = 767
        with self.assertRaisesRegex(
            ArtifactAdapterError, "embedding_dimension_mismatch"
        ):
            self.load(embedded=embedded)

    def test_chunk_to_normalization_identity_is_enforced(self):
        chunked = copy.deepcopy(self.chunked)
        chunked["normalization_set_digest"] = "f" * 64
        with self.assertRaisesRegex(
            ArtifactAdapterError, "chunk_normalization_link_mismatch"
        ):
            self.load(chunked=chunked)


if __name__ == "__main__":
    unittest.main()
