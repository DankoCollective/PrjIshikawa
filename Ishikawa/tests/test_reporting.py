from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path

from ishikawa.models import EntryPlan, ValidationPlan
from ishikawa.reporting import render_terminal_summary, write_protected_reports


class ReportingTests(unittest.TestCase):
    def plan(self) -> ValidationPlan:
        return ValidationPlan(
            schema_version=1,
            validation_id="1" * 64,
            validation_only=True,
            mutation_performed=False,
            overall_outcome="PASS",
            registry_digest="2" * 64,
            catalog_digest="3" * 64,
            manifest_digest="4" * 64,
            method_profile_id="5" * 64,
            entries=(
                EntryPlan(
                    entry_kind="document",
                    entry_index=0,
                    manifest_entry_identity="6" * 64,
                    document_key="policy.alpha",
                    outcome="PASS",
                    reason_code="VALID",
                    action="add",
                    source_path="policies/alpha.pdf",
                    source_digest="7" * 64,
                ),
            ),
            issues=(),
        )

    def test_reports_are_private_and_json_contains_relative_path(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "reports"
            text_path, json_path = write_protected_reports(self.plan(), root)
            self.assertEqual(os.stat(root).st_mode & 0o777, 0o700)
            self.assertEqual(os.stat(text_path).st_mode & 0o777, 0o600)
            self.assertEqual(os.stat(json_path).st_mode & 0o777, 0o600)
            payload = json.loads(json_path.read_text(encoding="utf-8"))
            self.assertEqual(payload["entries"][0]["relative_source_path"], "policies/alpha.pdf")
            self.assertTrue(payload["atomic_publication_eligible"])

    def test_text_and_terminal_do_not_disclose_source_path(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "reports"
            text_path, _ = write_protected_reports(self.plan(), root)
            text = text_path.read_text(encoding="utf-8")
            terminal = render_terminal_summary(self.plan(), root)
            self.assertNotIn("policies/alpha.pdf", text)
            self.assertNotIn("policies/alpha.pdf", terminal)

    def test_validation_only_report_records_no_mutation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            _, json_path = write_protected_reports(self.plan(), temporary)
            payload = json.loads(json_path.read_text(encoding="utf-8"))
            self.assertTrue(payload["validation_only"])
            self.assertFalse(payload["mutation_performed"])


if __name__ == "__main__":
    unittest.main()
