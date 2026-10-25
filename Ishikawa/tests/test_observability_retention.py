from __future__ import annotations

import io
import json
import os
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from ishikawa.observability import ObservabilityContractError, validate_logging_profile
from ishikawa.observability_retention import (
    apply_observability_retention,
    execute_observability_retention,
)
from ishikawa.yaml_loader import load_restricted_yaml


class ObservabilityRetentionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ishikawa_root = Path(__file__).resolve().parents[1]
        cls.profile_path = cls.ishikawa_root / "config/templates/logging_profile.yaml"
        cls.policy = validate_logging_profile(
            load_restricted_yaml(cls.profile_path, label="logging profile")
        )
        cls.now = datetime(2026, 10, 21, 4, 0, tzinfo=timezone.utc)

    def create_log_root(self, temporary_root: str) -> Path:
        log_root = Path(temporary_root) / "logs"
        log_root.mkdir(mode=0o700)
        return log_root

    def create_file(self, path: Path, age_days: int) -> None:
        path.write_text('{"safe":true}\n', encoding="utf-8")
        os.chmod(path, 0o600)
        timestamp = (self.now - timedelta(days=age_days)).timestamp()
        os.utime(path, (timestamp, timestamp))

    def test_only_expired_configured_files_are_deleted(self):
        with tempfile.TemporaryDirectory() as temporary_root:
            log_root = self.create_log_root(temporary_root)
            self.create_file(log_root / "retrieval.jsonl", 31)
            self.create_file(log_root / "retrieval.jsonl.1", 29)
            self.create_file(log_root / "metrics.jsonl.2", 31)
            self.create_file(log_root / "audit.jsonl.1", 91)
            self.create_file(log_root / "audit.jsonl.2", 89)
            self.create_file(log_root / "unrelated.jsonl", 1000)

            result = apply_observability_retention(self.policy, log_root, self.now)

            self.assertEqual(result.operational_deleted, 1)
            self.assertEqual(result.metrics_deleted, 1)
            self.assertEqual(result.audit_deleted, 1)
            self.assertEqual(result.total_deleted, 3)
            self.assertFalse((log_root / "retrieval.jsonl").exists())
            self.assertTrue((log_root / "retrieval.jsonl.1").is_file())
            self.assertTrue((log_root / "audit.jsonl.2").is_file())
            self.assertTrue((log_root / "unrelated.jsonl").is_file())
            for filename in (
                ".retrieval.jsonl.lock",
                ".metrics.jsonl.lock",
                ".audit.jsonl.lock",
            ):
                self.assertEqual(os.stat(log_root / filename).st_mode & 0o777, 0o600)

    def test_unsafe_candidate_blocks_before_any_deletion(self):
        with tempfile.TemporaryDirectory() as temporary_root:
            log_root = self.create_log_root(temporary_root)
            old_operational = log_root / "retrieval.jsonl.1"
            self.create_file(old_operational, 31)
            outside = Path(temporary_root) / "outside"
            outside.write_text("outside", encoding="utf-8")
            (log_root / "metrics.jsonl.1").symlink_to(outside)

            with self.assertRaises(ObservabilityContractError):
                apply_observability_retention(self.policy, log_root, self.now)

            self.assertTrue(old_operational.is_file())
            self.assertEqual(outside.read_text(encoding="utf-8"), "outside")

    def test_unrelated_numeric_and_nonnumeric_names_are_ignored(self):
        with tempfile.TemporaryDirectory() as temporary_root:
            log_root = self.create_log_root(temporary_root)
            for filename in (
                "retrieval.jsonl.backup",
                "retrieval.jsonl.1.extra",
                "other.jsonl.1",
            ):
                self.create_file(log_root / filename, 1000)
            result = apply_observability_retention(self.policy, log_root, self.now)
            self.assertEqual(result.total_deleted, 0)
            for filename in (
                "retrieval.jsonl.backup",
                "retrieval.jsonl.1.extra",
                "other.jsonl.1",
            ):
                self.assertTrue((log_root / filename).is_file())

    def prepare_product_root(self, temporary_root: str) -> Path:
        product_root = Path(temporary_root) / "Ishikawa"
        (product_root / "config").mkdir(parents=True)
        (product_root / "state/logs").mkdir(parents=True, mode=0o700)
        (product_root / "config/logging_profile.yaml").write_bytes(
            self.profile_path.read_bytes()
        )
        return product_root

    def test_check_config_is_read_only(self):
        with tempfile.TemporaryDirectory() as temporary_root:
            product_root = self.prepare_product_root(temporary_root)
            output = io.StringIO()
            status = execute_observability_retention(
                ["--check-config"], product_root=product_root, output=output
            )
            self.assertEqual(status, 0)
            self.assertIn("mode=check-config", output.getvalue())
            self.assertEqual(tuple((product_root / "state/logs").iterdir()), ())

    def test_apply_records_audit_and_reports_content_free_counts(self):
        with tempfile.TemporaryDirectory() as temporary_root:
            product_root = self.prepare_product_root(temporary_root)
            log_root = product_root / "state/logs"
            self.create_file(log_root / "retrieval.jsonl.1", 31)
            output = io.StringIO()
            status = execute_observability_retention(
                ["--apply"],
                product_root=product_root,
                output=output,
                clock=lambda: self.now,
            )
            self.assertEqual(status, 0)
            self.assertIn("operational_deleted=1", output.getvalue())
            audit_records = [
                json.loads(line)
                for line in (log_root / "audit.jsonl").read_text().splitlines()
            ]
            self.assertEqual(
                [record["event_code"] for record in audit_records],
                ["OBSERVABILITY_RETENTION_STARTED", "OBSERVABILITY_RETENTION_COMPLETED"],
            )
            self.assertNotIn(str(product_root), output.getvalue())

    def test_invalid_arguments_do_not_mutate_logs(self):
        with tempfile.TemporaryDirectory() as temporary_root:
            product_root = self.prepare_product_root(temporary_root)
            output = io.StringIO()
            status = execute_observability_retention(
                [], product_root=product_root, output=output
            )
            self.assertEqual(status, 2)
            self.assertTrue(output.getvalue().startswith("Usage:"))
            self.assertEqual(tuple((product_root / "state/logs").iterdir()), ())


if __name__ == "__main__":
    unittest.main()
