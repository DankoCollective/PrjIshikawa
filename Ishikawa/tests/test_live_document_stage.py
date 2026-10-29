from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path

from ishikawa.canonical import canonical_json_bytes, file_sha256
from ishikawa.document_producer import METHOD_PROFILE_ID
from ishikawa.ingestion_runtime import validate_ingestion_dependencies
from ishikawa.live_document_stage import LiveDocumentStageError, NativeLiveDocumentArtifactStage
from ishikawa.models import IngestionManifest, ManifestDocument
from ishikawa.operator_ingestion import DocumentProductionRequest, ProductionBatch
from ishikawa.runtime import ProtectedEnvironmentValue
from ishikawa.yaml_loader import load_restricted_yaml


class LiveDocumentStageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.workspace = self.root / "workspace"
        self.source = self.root / "source"
        self.workspace.mkdir()
        self.source.mkdir()
        self.executable = self.root / "produce-artifacts"
        self.executable.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        self.executable.chmod(0o700)
        config_root = Path(__file__).resolve().parents[1] / "config/templates"
        self.dependencies = validate_ingestion_dependencies(
            load_restricted_yaml(
                config_root / "ingestion_dependencies.yaml", label="ingestion dependencies"
            )
        )
        document = ManifestDocument("sample.pdf", "policy.sample", "policy_sop")
        self.manifest = IngestionManifest(1, (document,), (), "a" * 64)
        request = DocumentProductionRequest(
            "add", "policy.sample", "policy_sop", "sample.pdf", "b" * 64
        )
        self.batch = ProductionBatch(
            "c" * 64, METHOD_PROFILE_ID, self.source.resolve(), (request,)
        )

    def stage(self, runner, environment=None):
        return NativeLiveDocumentArtifactStage(
            self.executable.resolve(),
            self.dependencies,
            ProtectedEnvironmentValue(
                "ISHIKAWA_NOMIC_API_KEY", environment or {"ISHIKAWA_NOMIC_API_KEY": "secret"}
            ),
            runner,
            30,
        )

    @staticmethod
    def write_outputs(command, workspace, *, corrupt=False):
        request_path = Path(command[command.index("--request") + 1])
        request = json.loads(request_path.read_text(encoding="utf-8"))
        digests = {}
        for filename in ("normalized.json", "chunks.json", "embeddings.json"):
            path = workspace / filename
            path.write_bytes(canonical_json_bytes({"schema_version": 1, "name": filename}) + b"\n")
            digests[filename] = file_sha256(str(path))
        result = {
            "schema_version": 1,
            "outcome": "pass",
            "validation_id": request["validation_id"],
            "method_profile_id": request["method_profile_id"],
            "manifest_digest": request["manifest_digest"],
            "served_model": "nomic-ai/nomic-embed-text-v1.5",
            "normalized_sha256": "0" * 64 if corrupt else digests["normalized.json"],
            "chunk_sha256": digests["chunks.json"],
            "embedding_sha256": digests["embeddings.json"],
            "credential_retained": False,
        }
        (workspace / "stage-result.json").write_bytes(canonical_json_bytes(result) + b"\n")

    def test_exact_process_contract_and_checksum_bound_bundle(self):
        calls = []

        def runner(command, credential, workspace, timeout):
            calls.append((command, credential, timeout))
            self.write_outputs(command, workspace)
            return 0

        bundle = self.stage(runner)(self.batch, self.manifest, self.workspace.resolve())
        self.assertEqual(len(calls), 1)
        command, credential, timeout = calls[0]
        self.assertEqual(credential, b"secret\n")
        self.assertEqual(timeout, 30)
        self.assertNotIn("secret", command)
        self.assertEqual(command[-1], "--credential-stdin")
        self.assertEqual(bundle.normalized_sha256, file_sha256(str(bundle.normalized_path)))

    def test_nonzero_process_fails_with_stable_reason(self):
        with self.assertRaisesRegex(LiveDocumentStageError, "stage_process_failed"):
            self.stage(lambda *_items: 7)(self.batch, self.manifest, self.workspace.resolve())

    def test_artifact_identity_mismatch_fails_closed(self):
        def runner(command, _credential, workspace, _timeout):
            self.write_outputs(command, workspace, corrupt=True)
            return 0

        with self.assertRaisesRegex(LiveDocumentStageError, "stage_artifact_identity_mismatch"):
            self.stage(runner)(self.batch, self.manifest, self.workspace.resolve())

    def test_manifest_coverage_must_match_batch(self):
        empty = IngestionManifest(1, (), (), "d" * 64)
        with self.assertRaisesRegex(LiveDocumentStageError, "stage_manifest_coverage_mismatch"):
            self.stage(lambda *_items: 0)(self.batch, empty, self.workspace.resolve())

    def test_executable_must_be_absolute_regular_and_executable(self):
        unsafe = self.root / "unsafe"
        unsafe.write_text("no", encoding="utf-8")
        unsafe.chmod(0o600)
        with self.assertRaisesRegex(LiveDocumentStageError, "stage_executable_unsafe"):
            NativeLiveDocumentArtifactStage(
                unsafe,
                self.dependencies,
                ProtectedEnvironmentValue("ISHIKAWA_NOMIC_API_KEY", {}),
            )

    def test_default_timeout_covers_one_complete_real_corpus_stage(self):
        stage = NativeLiveDocumentArtifactStage(
            self.executable.resolve(),
            self.dependencies,
            ProtectedEnvironmentValue(
                "ISHIKAWA_NOMIC_API_KEY", {"ISHIKAWA_NOMIC_API_KEY": "secret"}
            ),
        )
        self.assertEqual(stage.timeout_seconds, 7200)


if __name__ == "__main__":
    unittest.main()
