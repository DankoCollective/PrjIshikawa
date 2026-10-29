"""Focused tests for the PDF extraction tool identity boundary.

Mental model:
    Deployment qualifies package provenance. Runtime extraction verifies that
    Poppler is installed, records its exact identity, and requires the two tools
    used for one capture to come from one coherent version.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
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

    def test_repeat_outputs_are_proved_but_not_retained_in_archive_input(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.pdf"
            source.write_bytes(b"%PDF-1.4\n%%EOF\n")
            raw = root / "raw"
            raw.mkdir()

            pdfinfo = b"Pages: 1\nEncrypted: no\nPage size: 612 x 792 pts\n"
            layout = b"body text\f"
            bbox = (
                b'<?xml version="1.0"?><doc><page width="612" height="792">'
                b'<word xMin="1" yMin="2" xMax="3" yMax="4">body</word>'
                b'</page></doc>'
            )

            def fake_run(arguments):
                if arguments[0] == "/usr/bin/pdfinfo":
                    return pdfinfo, b"", 1
                output = Path(arguments[-1])
                output.write_bytes(bbox if "-bbox-layout" in arguments else layout)
                return b"", b"", 1

            entry = {
                "bytes": source.stat().st_size,
                "doc_id": "policy.sample",
                "filename": "sample.pdf",
                "sha256": capture.sha256_file(source),
            }
            with patch.object(capture, "run_command", side_effect=fake_run):
                observation = capture.capture_document(source, entry, raw)

            self.assertEqual(observation["pdfinfo"]["pages"], 1)
            self.assertTrue((raw / "sample").is_dir())
            self.assertFalse((raw / "sample.repeat").exists())


if __name__ == "__main__":
    unittest.main()
