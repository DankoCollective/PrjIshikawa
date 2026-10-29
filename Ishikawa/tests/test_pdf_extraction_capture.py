"""Focused tests for the PDF extraction tool identity boundary.

Mental model:
    Deployment qualifies package provenance. Runtime extraction verifies that
    Poppler is installed, records its exact identity, and requires the two tools
    used for one capture to come from one coherent version.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).parents[1] / "scripts" / "capture-pdf-extraction-observations.py"
SPEC = importlib.util.spec_from_file_location("capture_pdf_extraction_observations", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
capture = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(capture)


class PdfExtractionIdentityTests(unittest.TestCase):
    def test_installed_package_identity_is_recorded_without_host_version_allowlist(self):
        with patch.object(
            capture,
            "run_command",
            return_value=(b"install ok installed\t26.01.0-2build2\n", b"", 0),
        ):
            self.assertEqual(capture.package_version(), "26.01.0-2build2")

    def test_uninstalled_package_is_rejected(self):
        with patch.object(
            capture,
            "run_command",
            return_value=(b"unknown ok not-installed\t26.01.0-2build2\n", b"", 0),
        ):
            with self.assertRaisesRegex(capture.CaptureError, "unexpected_poppler_package"):
                capture.package_version()

    def test_tool_version_is_recorded_without_host_version_allowlist(self):
        with patch.object(
            capture,
            "run_command",
            return_value=(b"", b"pdfinfo version 26.01.0\n", 0),
        ):
            self.assertEqual(capture.tool_version("/usr/bin/pdfinfo"), "26.01.0")

    def test_mixed_poppler_tool_versions_are_rejected(self):
        with self.assertRaisesRegex(capture.CaptureError, "poppler_tool_version_mismatch"):
            capture.require_matching_tool_versions("26.01.0", "24.02.0")


if __name__ == "__main__":
    unittest.main()
