from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from ishikawa.errors import IshikawaValidationError
from ishikawa.yaml_loader import load_restricted_yaml


class RestrictedYamlLoaderTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def write(self, content: bytes | str) -> Path:
        path = self.root / "input.yaml"
        path.write_bytes(content.encode("utf-8") if isinstance(content, str) else content)
        return path

    def assert_reason(self, content: bytes | str, reason: str) -> None:
        with self.assertRaises(IshikawaValidationError) as caught:
            load_restricted_yaml(self.write(content), label="test input")
        self.assertEqual(caught.exception.reason_code, reason)

    def test_loads_one_plain_mapping(self) -> None:
        loaded = load_restricted_yaml(self.write("schema_version: 1\nitems: []\n"), label="test input")
        self.assertEqual(loaded, {"schema_version": 1, "items": []})

    def test_rejects_duplicate_mapping_key(self) -> None:
        self.assert_reason("schema_version: 1\nschema_version: 1\n", "YAML_DUPLICATE_KEY")

    def test_rejects_multiple_documents(self) -> None:
        self.assert_reason("a: 1\n---\nb: 2\n", "YAML_DOCUMENT_COUNT_INVALID")

    def test_rejects_empty_document(self) -> None:
        self.assert_reason("# only a comment\n", "YAML_DOCUMENT_COUNT_INVALID")

    def test_rejects_anchor_and_alias(self) -> None:
        self.assert_reason("a: &shared value\nb: *shared\n", "YAML_FORBIDDEN_FEATURE")

    def test_rejects_custom_tag(self) -> None:
        self.assert_reason("a: !custom value\n", "YAML_FORBIDDEN_FEATURE")

    def test_rejects_merge_key(self) -> None:
        self.assert_reason("base: &base {a: 1}\nmerged: {<<: *base}\n", "YAML_FORBIDDEN_FEATURE")

    def test_rejects_non_utf8(self) -> None:
        self.assert_reason(b"schema_version: \xff\n", "CONFIG_NOT_UTF8")

    def test_missing_file_has_content_safe_failure(self) -> None:
        missing = self.root / "missing.yaml"
        with self.assertRaises(IshikawaValidationError) as caught:
            load_restricted_yaml(missing, label="document catalog")
        self.assertEqual(caught.exception.reason_code, "CONFIG_FILE_UNREADABLE")
        self.assertNotIn(str(missing), caught.exception.safe_message)


if __name__ == "__main__":
    unittest.main()
