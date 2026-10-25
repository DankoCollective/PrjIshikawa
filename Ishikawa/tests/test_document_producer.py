from __future__ import annotations

import hashlib
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

from ishikawa.document_producer import (
    METHOD_PROFILE_ID,
    DocumentProducerContractError,
    NativeDocumentProducer,
    ProducerArtifactBundle,
)
from ishikawa.models import IngestionManifest, ManifestDocument
from ishikawa.operator_ingestion import DocumentProductionRequest, ProductionBatch


class DocumentProducerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"
        self.work = self.root / "work"
        self.source.mkdir()
        self.work.mkdir()
        self.pdf = self.source / "alpha.pdf"
        self.pdf.write_bytes(b"%PDF-1.4\nproducer fixture\n%%EOF\n")
        self.digest = hashlib.sha256(self.pdf.read_bytes()).hexdigest()
        item = ManifestDocument("alpha.pdf", "policy.alpha", "policy")
        self.manifest = IngestionManifest(1, (item,), (), "a" * 64)
        self.request = DocumentProductionRequest(
            "add", "policy.alpha", "policy", "alpha.pdf", self.digest
        )
        self.batch = ProductionBatch(
            "b" * 64, METHOD_PROFILE_ID, self.source.resolve(), (self.request,)
        )
        self.stage_calls = []
        self.retained = []
        self.workspaces = []

    def stage(self, batch, manifest, workspace):
        self.stage_calls.append((batch, manifest))
        self.workspaces.append(workspace)
        paths = [workspace / name for name in ("normalized.json", "chunks.json", "embeddings.json")]
        for index, path in enumerate(paths):
            path.write_bytes(f"artifact-{index}".encode("ascii"))
        return ProducerArtifactBundle(
            paths[0], hashlib.sha256(paths[0].read_bytes()).hexdigest(),
            paths[1], hashlib.sha256(paths[1].read_bytes()).hexdigest(),
            paths[2], hashlib.sha256(paths[2].read_bytes()).hexdigest(),
        )

    def adapter(self, **values):
        self.assertEqual(len(values["manifest"].documents), 1)
        return (SimpleNamespace(
            document_key="policy.alpha", class_id="policy", source_digest=self.digest
        ),)

    def producer(self, *, stage=None, adapter=None):
        return NativeDocumentProducer(
            self.manifest,
            self.work.resolve(),
            stage or self.stage,
            self.retained.append,
            adapter or self.adapter,
        )

    def test_one_changed_document_runs_one_stage_and_retains_after_validation(self):
        result = self.producer()(self.batch)
        self.assertEqual([item.document_key for item in result], ["policy.alpha"])
        self.assertEqual(len(self.stage_calls), 1)
        self.assertEqual(len(self.retained), 1)
        self.assertEqual(self.stage_calls[0][1].retirements, ())
        self.assertFalse(self.workspaces[0].exists())

    def test_empty_and_nonproduction_actions_fail_before_stage(self):
        for documents in (
            (),
            (DocumentProductionRequest("reuse", "policy.alpha", "policy", "alpha.pdf", self.digest),),
        ):
            with self.subTest(documents=documents), self.assertRaises(DocumentProducerContractError):
                self.producer()(ProductionBatch("b" * 64, METHOD_PROFILE_ID, self.source.resolve(), documents))
        self.assertEqual(self.stage_calls, [])

    def test_method_profile_must_be_the_frozen_chunk_profile(self):
        with self.assertRaisesRegex(DocumentProducerContractError, "production_method_profile_mismatch"):
            self.producer()(ProductionBatch("b" * 64, "f" * 64, self.source.resolve(), (self.request,)))

    def test_manifest_identity_mismatch_fails_before_stage(self):
        changed = DocumentProductionRequest("add", "policy.alpha", "wrong", "alpha.pdf", self.digest)
        with self.assertRaisesRegex(DocumentProducerContractError, "production_request_differs_from_manifest"):
            self.producer()(ProductionBatch("b" * 64, METHOD_PROFILE_ID, self.source.resolve(), (changed,)))

    def test_source_digest_mismatch_fails_before_stage(self):
        changed = DocumentProductionRequest("add", "policy.alpha", "policy", "alpha.pdf", "0" * 64)
        with self.assertRaisesRegex(DocumentProducerContractError, "production_source_identity_mismatch"):
            self.producer()(ProductionBatch("b" * 64, METHOD_PROFILE_ID, self.source.resolve(), (changed,)))

    def test_artifacts_must_be_checksum_bound_inside_workspace(self):
        outside = self.root / "outside.json"
        outside.write_text("outside", encoding="ascii")
        digest = hashlib.sha256(outside.read_bytes()).hexdigest()

        def stage(_batch, _manifest, workspace):
            local = workspace / "local.json"
            local.write_text("local", encoding="ascii")
            local_digest = hashlib.sha256(local.read_bytes()).hexdigest()
            return ProducerArtifactBundle(outside, digest, local, local_digest, local, local_digest)

        with self.assertRaises(DocumentProducerContractError):
            self.producer(stage=stage)(self.batch)
        self.assertEqual(self.retained, [])

    def test_prepared_coverage_must_equal_requested_documents(self):
        def wrong_adapter(**_values):
            return (SimpleNamespace(
                document_key="policy.other", class_id="policy", source_digest=self.digest
            ),)

        with self.assertRaisesRegex(DocumentProducerContractError, "prepared_document_coverage_mismatch"):
            self.producer(adapter=wrong_adapter)(self.batch)
        self.assertEqual(self.retained, [])

    def test_stage_failure_cleans_workspace_and_does_not_retain(self):
        def fail(_batch, _manifest, workspace):
            self.workspaces.append(workspace)
            raise RuntimeError("bounded stage failure")

        with self.assertRaisesRegex(RuntimeError, "bounded stage failure"):
            self.producer(stage=fail)(self.batch)
        self.assertFalse(self.workspaces[0].exists())
        self.assertEqual(self.retained, [])


if __name__ == "__main__":
    unittest.main()
