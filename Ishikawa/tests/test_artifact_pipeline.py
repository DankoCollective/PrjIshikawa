from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from ishikawa.artifact_pipeline import (
    ArtifactPipelineError,
    NOMIC_MODEL,
    PipelineLayout,
    run_artifact_pipeline,
)
from ishikawa.canonical import canonical_json_bytes, file_sha256


class ArtifactPipelineTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"
        self.workspace = self.root / "workspace"
        self.programs = self.root / "programs"
        self.python_root = self.root / "python"
        for path in (self.source, self.workspace, self.programs, self.python_root):
            path.mkdir()
        self.pdf = self.source / "alpha.pdf"
        self.pdf.write_bytes(b"%PDF-1.4\nartifact pipeline fixture\n%%EOF\n")
        self.source_digest = file_sha256(str(self.pdf))
        paths = []
        for name in ("capture.py", "normalize.py", "chunk.py", "embed.py"):
            path = self.programs / name
            path.write_text("# qualified helper\n", encoding="utf-8")
            paths.append(path.resolve())
        self.layout = PipelineLayout(self.python_root.resolve(), *paths)
        self.request = self.workspace / "stage-request.json"
        self.request_document = {
            "schema_version": 1,
            "validation_id": "1" * 64,
            "method_profile_id": "2" * 64,
            "manifest_digest": "3" * 64,
            "documents": [
                {
                    "action": "add",
                    "document_key": "policy.alpha",
                    "class_id": "policy",
                    "relative_source_path": "alpha.pdf",
                    "source_sha256": self.source_digest,
                }
            ],
        }
        self.request.write_bytes(canonical_json_bytes(self.request_document) + b"\n")
        self.calls = []
        self.observed_manifest = None

    @staticmethod
    def argument(command, name):
        return Path(command[command.index(name) + 1])

    def runner(self, command, stdin, _cwd, _stdout, _stderr):
        self.calls.append((command, stdin))
        program = Path(command[2]).name
        if program == "capture.py":
            manifest = self.argument(command, "--source-manifest")
            self.observed_manifest = json.loads(manifest.read_text(encoding="utf-8"))
            self.argument(command, "--archive").write_bytes(b"extraction")
        elif program == "normalize.py":
            self.argument(command, "--output").write_bytes(b"normalized")
        elif program == "chunk.py":
            self.argument(command, "--output").write_bytes(b"chunks")
        elif program == "embed.py":
            self.argument(command, "--output").write_bytes(b"embeddings")
        else:
            return 7
        return 0

    def invoke_pipeline(self):
        return run_artifact_pipeline(
            request_path=self.request.resolve(),
            source_root=self.source.resolve(),
            workspace=self.workspace.resolve(),
            embedding_url="http://127.0.0.1:8001/v1/embeddings",
            tokenization_url="http://127.0.0.1:8001/tokenize",
            served_model=NOMIC_MODEL,
            batch_size=16,
            credential=bytearray(b"s" * 32),
            layout=self.layout,
            runner=self.runner,
        )

    def test_runs_four_stages_and_writes_exact_checksum_bound_result(self):
        result = self.invoke_pipeline()
        self.assertEqual([Path(call[0][2]).name for call in self.calls], [
            "capture.py", "normalize.py", "chunk.py", "embed.py"
        ])
        self.assertEqual([call[1] for call in self.calls], [None, None, None, b"s" * 32])
        observed = json.loads((self.workspace / "stage-result.json").read_text(encoding="utf-8"))
        self.assertEqual(observed, result)
        self.assertEqual(result["normalized_sha256"], file_sha256(str(self.workspace / "normalized.json")))
        self.assertEqual(result["chunk_sha256"], file_sha256(str(self.workspace / "chunks.json")))
        self.assertEqual(result["embedding_sha256"], file_sha256(str(self.workspace / "embeddings.json")))
        self.assertFalse(result["credential_retained"])

    def test_only_requested_checksum_bound_source_is_staged(self):
        (self.source / "unrequested.pdf").write_bytes(b"not requested")
        self.invoke_pipeline()
        self.assertEqual(self.observed_manifest["fixture_status"], "operator_manifest_bound_source")
        self.assertEqual(len(self.observed_manifest["files"]), 1)
        entry = self.observed_manifest["files"][0]
        self.assertEqual(entry["doc_id"], "policy.alpha")
        self.assertEqual(entry["sha256"], self.source_digest)
        self.assertFalse(any(path.name.startswith(".artifact-pipeline-") for path in self.workspace.iterdir()))

    def test_source_identity_mismatch_fails_before_any_stage(self):
        self.request_document["documents"][0]["source_sha256"] = "0" * 64
        self.request.write_bytes(canonical_json_bytes(self.request_document) + b"\n")
        with self.assertRaisesRegex(ArtifactPipelineError, "source_file_identity_mismatch"):
            self.invoke_pipeline()
        self.assertEqual(self.calls, [])

    def test_duplicate_document_key_is_rejected(self):
        self.request_document["documents"].append(dict(self.request_document["documents"][0]))
        self.request_document["documents"][1]["relative_source_path"] = "other.pdf"
        self.request.write_bytes(canonical_json_bytes(self.request_document) + b"\n")
        with self.assertRaisesRegex(ArtifactPipelineError, "request_document_duplicate"):
            self.invoke_pipeline()

    def test_existing_output_fails_before_stage_execution(self):
        (self.workspace / "chunks.json").write_bytes(b"existing")
        with self.assertRaisesRegex(ArtifactPipelineError, "pipeline_output_exists"):
            self.invoke_pipeline()
        self.assertEqual(self.calls, [])

    def test_nonzero_stage_status_is_content_free_failure(self):
        def rejected(*_items):
            return 4

        with self.assertRaisesRegex(ArtifactPipelineError, "extraction_failed"):
            run_artifact_pipeline(
                request_path=self.request.resolve(),
                source_root=self.source.resolve(),
                workspace=self.workspace.resolve(),
                embedding_url="http://127.0.0.1:8001/v1/embeddings",
                tokenization_url="http://127.0.0.1:8001/tokenize",
                served_model=NOMIC_MODEL,
                batch_size=16,
                credential=bytearray(b"s" * 32),
                layout=self.layout,
                runner=rejected,
            )

    def test_nonzero_stage_preserves_stable_content_free_inner_reason(self):
        def rejected(_command, _stdin, _cwd, stdout, _stderr):
            stdout.write_text(
                "pdf_extraction_capture=blocked;reason=unexpected_poppler_package\n",
                encoding="utf-8",
            )
            return 4

        with self.assertRaisesRegex(
            ArtifactPipelineError,
            "extraction_unexpected_poppler_package",
        ):
            run_artifact_pipeline(
                request_path=self.request.resolve(),
                source_root=self.source.resolve(),
                workspace=self.workspace.resolve(),
                embedding_url="http://127.0.0.1:8001/v1/embeddings",
                tokenization_url="http://127.0.0.1:8001/tokenize",
                served_model=NOMIC_MODEL,
                batch_size=16,
                credential=bytearray(b"s" * 32),
                layout=self.layout,
                runner=rejected,
            )


if __name__ == "__main__":
    unittest.main()
