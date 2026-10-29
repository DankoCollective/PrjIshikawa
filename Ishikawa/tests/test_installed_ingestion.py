from __future__ import annotations

import hashlib
import io
import tempfile
import time
import unittest
from pathlib import Path

from ishikawa.document_producer import ProducerArtifactBundle
from ishikawa.installed_ingestion import (
    ContentAddressedArtifactRetainer,
    InstalledIngestionError,
    InstalledIngestionLayout,
    execute_installed_ingestion,
)
from ishikawa.live_document_stage import LiveDocumentStageError


class _Runtime:
    def __init__(self, calls):
        self.calls = calls

    def execute(self, mode, *, output):
        self.calls.append(mode)
        output.write("runtime=pass\n")
        return 0


class InstalledIngestionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "Ishikawa"
        for relative in (
            "application/python",
            "config/ingestion/pending",
            "corpus/source",
            "state/reports/ingestion",
            "state/work",
            "state/artifacts/sha256",
            "scripts",
        ):
            (self.root / relative).mkdir(parents=True, exist_ok=True)
        for relative in ("config/document_classes.yaml", "config/document_catalog.yaml"):
            (self.root / relative).write_text("schema_version: 1\n", encoding="utf-8")
        self.manifest = self.root / "config/ingestion/pending/batch-001.yaml"
        self.manifest.write_text("schema_version: 1\n", encoding="utf-8")
        self.pipeline = self.root / "scripts/ishikawa-produce-artifacts"
        self.pipeline.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        self.pipeline.chmod(0o700)

    def test_layout_uses_only_installed_product_paths(self):
        layout = InstalledIngestionLayout.from_product_root(self.root.resolve())
        self.assertEqual(layout.class_registry, (self.root / "config/document_classes.yaml").resolve())
        self.assertEqual(layout.document_catalog, (self.root / "config/document_catalog.yaml").resolve())
        self.assertEqual(layout.source_root, (self.root / "corpus/source").resolve())
        self.assertEqual(layout.pipeline_executable, self.pipeline.resolve())

    def test_manifest_is_a_filename_under_pending_only(self):
        layout = InstalledIngestionLayout.from_product_root(self.root.resolve())
        self.assertEqual(layout.manifest("batch-001.yaml"), self.manifest.resolve())
        for value in ("../batch-001.yaml", "/tmp/batch.yaml", "batch.yml", "sub/batch.yaml"):
            with self.subTest(value=value), self.assertRaises(InstalledIngestionError):
                layout.manifest(value)

    def test_command_exposes_only_mode_and_manifest(self):
        observations = []
        calls = []

        def factory(layout, paths, environment):
            observations.append((layout, paths, environment))
            return _Runtime(calls)

        output = io.StringIO()
        environment = {"ISHIKAWA_NOMIC_API_KEY": "not-read"}
        status = execute_installed_ingestion(
            ("--validate-only", "--manifest", "batch-001.yaml"),
            product_root=self.root.resolve(),
            output=output,
            environment=environment,
            runtime_factory=factory,
        )
        self.assertEqual(status, 0)
        self.assertEqual(calls, ["validate-only"])
        self.assertEqual(observations[0][1].ingestion_manifest, self.manifest.resolve())
        self.assertIs(observations[0][2], environment)
        self.assertEqual(
            output.getvalue().splitlines(),
            [
                "[INGEST] state=start;mode=validate-only",
                "runtime=pass",
                "[INGEST] state=pass;exit_code=0",
            ],
        )

    def test_help_is_available_without_runtime_or_manifest_access(self):
        output = io.StringIO()
        status = execute_installed_ingestion(
            ("--help",),
            product_root=self.root.resolve(),
            output=output,
            runtime_factory=lambda *_args: self.fail("runtime factory called"),
        )
        self.assertEqual(status, 0)
        self.assertEqual(
            output.getvalue(),
            "Usage: ishikawa-ingest "
            "(--validate-only|--publish) --manifest BATCH.yaml\n",
        )

    def test_long_nested_failure_streams_heartbeat_and_preserves_status(self):
        class FailingRuntime:
            @staticmethod
            def execute(_mode, *, output):
                time.sleep(0.03)
                output.write("runtime=blocked\n")
                return 7

        output = io.StringIO()
        status = execute_installed_ingestion(
            ("--publish", "--manifest", "batch-001.yaml"),
            product_root=self.root.resolve(),
            output=output,
            runtime_factory=lambda *_args: FailingRuntime(),
            heartbeat_seconds=0.005,
        )
        lines = output.getvalue().splitlines()
        self.assertEqual(status, 7)
        self.assertEqual(lines[0], "[INGEST] state=start;mode=publish")
        self.assertTrue(any(line.startswith("[INGEST] state=heartbeat;") for line in lines))
        self.assertEqual(lines[-2:], ["runtime=blocked", "[INGEST] state=blocked;exit_code=7"])

    def test_interruption_is_never_reported_as_success(self):
        class InterruptedRuntime:
            @staticmethod
            def execute(_mode, *, output):
                raise KeyboardInterrupt

        output = io.StringIO()
        status = execute_installed_ingestion(
            ("--publish", "--manifest", "batch-001.yaml"),
            product_root=self.root.resolve(),
            output=output,
            runtime_factory=lambda *_args: InterruptedRuntime(),
        )
        self.assertEqual(status, 130)
        self.assertEqual(
            output.getvalue().splitlines()[-1],
            "[INGEST] state=blocked;exit_code=130;reason=interrupted",
        )

    def test_safe_nested_stage_reason_reaches_operator_boundary(self):
        class FailingRuntime:
            @staticmethod
            def execute(_mode, *, output):
                raise LiveDocumentStageError(
                    "stage_process_normalization_document_footer_page_count_conflict"
                )

        output = io.StringIO()
        status = execute_installed_ingestion(
            ("--publish", "--manifest", "batch-001.yaml"),
            product_root=self.root.resolve(),
            output=output,
            runtime_factory=lambda *_args: FailingRuntime(),
        )
        reason = (
            "live_document_stage_"
            "stage_process_normalization_document_footer_page_count_conflict"
        )
        self.assertEqual(status, 1)
        self.assertEqual(
            output.getvalue().splitlines()[-2:],
            [
                f"[INGEST] state=blocked;exit_code=1;reason={reason}",
                f"ishikawa_ingest=blocked;reason={reason}",
            ],
        )

    def test_unknown_or_secret_bearing_arguments_fail_before_runtime(self):
        for values in (
            ("--publish", "--manifest", "batch-001.yaml", "--password", "secret"),
            ("--manifest", "batch-001.yaml"),
            ("--publish", "--validate-only", "--manifest", "batch-001.yaml"),
        ):
            with self.subTest(values=values):
                output = io.StringIO()
                status = execute_installed_ingestion(
                    values,
                    product_root=self.root.resolve(),
                    output=output,
                    runtime_factory=lambda *_args: self.fail("runtime factory called"),
                )
                self.assertEqual(status, 2)
                self.assertEqual(output.getvalue(), "ishikawa_ingest=blocked;reason=arguments_invalid\n")
                self.assertNotIn("secret", output.getvalue())

    def test_content_addressed_retention_is_verified_and_idempotent(self):
        source_root = Path(self.temporary.name) / "producer"
        source_root.mkdir()
        entries = []
        for name, payload in (("normalized", b"one"), ("chunks", b"two"), ("embeddings", b"three")):
            path = source_root / f"{name}.json"
            path.write_bytes(payload)
            entries.append((path, hashlib.sha256(payload).hexdigest()))
        bundle = ProducerArtifactBundle(
            entries[0][0], entries[0][1], entries[1][0], entries[1][1], entries[2][0], entries[2][1]
        )
        retainer = ContentAddressedArtifactRetainer(
            (self.root / "state/artifacts/sha256").resolve()
        )
        retainer(bundle)
        retainer(bundle)
        retained = sorted(
            path for path in (self.root / "state/artifacts/sha256").glob("*/*") if path.is_file()
        )
        self.assertEqual(len(retained), 3)
        self.assertEqual({path.name for path in retained}, {digest for _, digest in entries})
        self.assertTrue(all((path.stat().st_mode & 0o777) == 0o600 for path in retained))

    def test_content_addressed_retention_rejects_existing_conflict(self):
        source = Path(self.temporary.name) / "artifact.json"
        source.write_bytes(b"accepted")
        digest = hashlib.sha256(b"accepted").hexdigest()
        root = self.root / "state/artifacts/sha256"
        directory = root / digest[:2]
        directory.mkdir()
        (directory / digest).write_bytes(b"different")
        bundle = ProducerArtifactBundle(source, digest, source, digest, source, digest)
        with self.assertRaisesRegex(InstalledIngestionError, "retained_artifact_conflict"):
            ContentAddressedArtifactRetainer(root.resolve())(bundle)


if __name__ == "__main__":
    unittest.main()
