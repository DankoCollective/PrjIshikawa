#!/usr/bin/env python3
"""Regression checks for accepted-artifact to writer-input conversion."""

from __future__ import annotations

import json
import shutil
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path

from ishikawa.artifact_adapter import ArtifactAdapterError, load_prepared_documents
from ishikawa.canonical import file_sha256
from ishikawa.validators import validate_ingestion_manifest
from ishikawa.yaml_loader import load_restricted_yaml


REPO_ROOT = Path(__file__).resolve().parents[3]
FIXTURES = Path(__file__).resolve().parent / "fixtures" / "pipeline_writer"
SOURCE_ROOT = REPO_ROOT / "local/artifacts/org_lab/synthetic_corpus_v1/anderson-upload"
NORMALIZED = REPO_ROOT / "local/artifacts/ishikawa/normalization/normalized_structural_units_20261019T214207Z.json"
CHUNKS = REPO_ROOT / "local/artifacts/ishikawa/chunking/structural_chunk_candidates_20261019T214924Z.json"
EMBEDDINGS = REPO_ROOT / "local/artifacts/ishikawa/embeddings/measured_nomic_chunk_embeddings_20261019T224719Z.json"
NORMALIZED_SHA256 = "736d619ac5a7e10f768bdb8b8f3f117cb52231f8dc2f4d186d52d96c8bd41e28"
CHUNK_SHA256 = "0b351ef579ff134a5fb1fb5f37843d5461a100f1fc2d803e278a9b20d3126548"
EMBEDDING_SHA256 = "5876c94380421741227f1bcaa494490158c1c83aeb5f54b39e894e9356b0f14d"
AMENDED_CHUNKS = REPO_ROOT / "local/artifacts/ishikawa/retrieval-gap-method-profile/structural_chunk_candidates_20261020T002645Z.json"
AMENDED_EMBEDDINGS = REPO_ROOT / "local/artifacts/ishikawa/retrieval-gap-method-profile/measured_nomic_chunk_embeddings_20261020T002645Z.json"
AMENDED_CHUNK_SHA256 = "bc993ca0a417353f0d2313bcb2d1c94a1d526a513253139be71117bf88626bf3"
AMENDED_EMBEDDING_SHA256 = "5bd79048bb59d53b6f6903eec9f4797955763a5fc12c064b17d19db89ba9d641"
EMBEDDING_SPACE_ID = "fd970d304662357a07f7712639bdc0c70cc7e72b22f04c126acce57a6f9143a3"
V4_METHOD_PROFILE_ID = "d5df385930cd801abb7296f03f64f6a950bddc6ea9e550b389db215e084a1350"


class ArtifactAdapterChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.manifest = validate_ingestion_manifest(
            load_restricted_yaml(FIXTURES / "ingestion_manifest.yaml", label="manifest")
        )

    def load(self, *, embedding_path=EMBEDDINGS, embedding_sha=EMBEDDING_SHA256, manifest=None):
        return load_prepared_documents(
            normalized_path=NORMALIZED,
            normalized_sha256=NORMALIZED_SHA256,
            chunk_path=CHUNKS,
            chunk_sha256=CHUNK_SHA256,
            embedding_path=embedding_path,
            embedding_sha256=embedding_sha,
            manifest=manifest or self.manifest,
            source_root=SOURCE_ROOT,
        )

    def changed_embedding(self, mutate):
        temporary = tempfile.TemporaryDirectory(prefix="ishikawa-adapter-test.")
        path = Path(temporary.name) / "embeddings.json"
        value = json.loads(EMBEDDINGS.read_text(encoding="utf-8"))
        mutate(value)
        path.write_text(json.dumps(value, sort_keys=True), encoding="utf-8")
        return temporary, path, file_sha256(str(path))

    def test_full_artifact_set_is_prepared(self):
        documents = self.load()
        self.assertEqual(len(documents), 6)
        self.assertEqual(sum(len(item.structural_units) for item in documents), 230)
        self.assertEqual(sum(len(item.chunks) for item in documents), 125)

    def test_amended_profile_adds_one_page_status_chunk_and_unit(self):
        documents = load_prepared_documents(
            normalized_path=NORMALIZED,
            normalized_sha256=NORMALIZED_SHA256,
            chunk_path=AMENDED_CHUNKS,
            chunk_sha256=AMENDED_CHUNK_SHA256,
            embedding_path=AMENDED_EMBEDDINGS,
            embedding_sha256=AMENDED_EMBEDDING_SHA256,
            manifest=self.manifest,
            source_root=SOURCE_ROOT,
        )
        chunks = [chunk for document in documents for chunk in document.chunks]
        self.assertEqual(sum(len(item.structural_units) for item in documents), 231)
        self.assertEqual(len(chunks), 126)
        self.assertEqual(
            sum(chunk.processing_profile == "page_status" for chunk in chunks),
            1,
        )

    def test_v4_profile_and_retrieval_calibration_blocker_are_accepted_together(self):
        with tempfile.TemporaryDirectory(prefix="ishikawa-adapter-v4-test.") as temporary:
            root = Path(temporary)
            chunk_path = root / "chunks.json"
            embedding_path = root / "embeddings.json"

            chunks = json.loads(CHUNKS.read_text(encoding="utf-8"))
            chunks["method_profile_id"] = V4_METHOD_PROFILE_ID
            for document in chunks["documents"]:
                for candidate in document["candidates"]:
                    candidate["method_profile_id"] = V4_METHOD_PROFILE_ID
            chunk_path.write_text(json.dumps(chunks, sort_keys=True), encoding="utf-8")
            chunk_sha256 = file_sha256(str(chunk_path))

            embeddings = json.loads(EMBEDDINGS.read_text(encoding="utf-8"))
            embeddings["source_chunk_candidate_sha256"] = chunk_sha256
            embeddings["source_method_profile_id"] = V4_METHOD_PROFILE_ID
            embeddings["publication_blocker"] = "retrieval_profile_calibration_pending"
            embedding_path.write_text(
                json.dumps(embeddings, sort_keys=True), encoding="utf-8"
            )

            documents = load_prepared_documents(
                normalized_path=NORMALIZED,
                normalized_sha256=NORMALIZED_SHA256,
                chunk_path=chunk_path,
                chunk_sha256=chunk_sha256,
                embedding_path=embedding_path,
                embedding_sha256=file_sha256(str(embedding_path)),
                manifest=self.manifest,
                source_root=SOURCE_ROOT,
            )

        self.assertEqual(len(documents), 6)

    def test_embedding_identity_and_exact_token_totals_are_preserved(self):
        documents = self.load()
        chunks = [chunk for document in documents for chunk in document.chunks]
        self.assertEqual({item.embedding_space.identity for item in documents}, {EMBEDDING_SPACE_ID})
        self.assertEqual((min(item.total_embedding_token_count for item in chunks), max(item.total_embedding_token_count for item in chunks)), (10, 57))
        for chunk in chunks:
            details = chunk.contextual_fields["token_accounting"]
            self.assertEqual(chunk.total_embedding_token_count, details["total_embedding_input_tokens"])
            self.assertEqual(chunk.prefix_token_count, details["prefix_tokens_without_special"])
            self.assertEqual(chunk.special_token_count, details["special_tokens"])
            self.assertEqual(len(chunk.embedding), 768)

    def test_document_identity_comes_from_manifest_and_source_digest(self):
        documents = {item.document_key: item for item in self.load()}
        self.assertEqual(documents["form.tst-9001"].class_id, "administrative_form")
        self.assertEqual(documents["procedure.incident-reporting"].source_digest, "962f8c6dd5835fc713cea6292ee1f30cb18d0abe6db38efe91f9a4ecea8d5175")

    def test_manifest_must_cover_exactly_the_accepted_sources(self):
        incomplete = replace(self.manifest, documents=self.manifest.documents[:-1])
        with self.assertRaisesRegex(ArtifactAdapterError, "artifact_manifest_source_coverage_mismatch"):
            self.load(manifest=incomplete)

    def test_duplicate_embedding_is_rejected(self):
        temporary, path, digest = self.changed_embedding(lambda value: value["records"].append(dict(value["records"][0])))
        with temporary:
            with self.assertRaisesRegex(ArtifactAdapterError, "duplicate_embedding_record"):
                self.load(embedding_path=path, embedding_sha=digest)

    def test_missing_embedding_is_rejected(self):
        temporary, path, digest = self.changed_embedding(lambda value: value["records"].pop())
        with temporary:
            with self.assertRaisesRegex(ArtifactAdapterError, "embedding_coverage_mismatch"):
                self.load(embedding_path=path, embedding_sha=digest)

    def test_submitted_input_identity_is_recomputed(self):
        def mutate(value):
            value["records"][0]["submitted_input_digest"] = "0" * 64
        temporary, path, digest = self.changed_embedding(mutate)
        with temporary:
            with self.assertRaisesRegex(ArtifactAdapterError, "submitted_input_identity_mismatch"):
                self.load(embedding_path=path, embedding_sha=digest)

    def test_vector_dimension_is_enforced(self):
        def mutate(value):
            value["records"][0]["vector_dimension"] = 767
        temporary, path, digest = self.changed_embedding(mutate)
        with temporary:
            with self.assertRaisesRegex(ArtifactAdapterError, "embedding_dimension_mismatch"):
                self.load(embedding_path=path, embedding_sha=digest)


if __name__ == "__main__":
    unittest.main()
