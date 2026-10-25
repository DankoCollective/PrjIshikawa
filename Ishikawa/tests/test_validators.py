from __future__ import annotations

import copy
import unittest
from pathlib import Path

from ishikawa.errors import IshikawaValidationError
from ishikawa.yaml_loader import load_restricted_yaml
from ishikawa.validators import (
    validate_class_registry,
    validate_document_catalog,
    validate_ingestion_manifest,
)


VALID_CLASSES = {
    "schema_version": 1,
    "classes": [
        {"class_id": "policy_sop", "display_name": "Policy or SOP", "status": "active"},
        {"class_id": "regulation", "display_name": "Regulation", "status": "active"},
    ],
}
VALID_CATALOG = {
    "schema_version": 1,
    "documents": [
        {"document_key": "policy.social-media", "display_name": "Social Media", "status": "active"},
        {"document_key": "regulation.records", "display_name": "Records", "status": "retired"},
    ],
}
VALID_MANIFEST = {
    "schema_version": 1,
    "documents": [
        {
            "source_path": "policies/social-media.pdf",
            "document_key": "policy.social-media",
            "class_id": "policy_sop",
        }
    ],
    "retirements": [{"document_key": "regulation.records"}],
}


class ValidatorTests(unittest.TestCase):
    def assert_reason(self, function, value, reason: str) -> None:
        with self.assertRaises(IshikawaValidationError) as caught:
            function(value)
        self.assertEqual(caught.exception.reason_code, reason)

    def test_valid_contracts(self) -> None:
        self.assertEqual(len(validate_class_registry(VALID_CLASSES).classes), 2)
        self.assertEqual(len(validate_document_catalog(VALID_CATALOG).documents), 2)
        self.assertEqual(len(validate_ingestion_manifest(VALID_MANIFEST).documents), 1)

    def test_tracked_templates_load_and_validate(self) -> None:
        templates = Path(__file__).resolve().parents[1] / "config" / "templates"
        classes = load_restricted_yaml(
            templates / "document_classes.yaml", label="document-class registry"
        )
        catalog_value = load_restricted_yaml(
            templates / "document_catalog.yaml", label="document catalog"
        )
        manifest_value = load_restricted_yaml(
            templates / "ingestion_manifest.yaml", label="ingestion manifest"
        )
        validate_class_registry(classes)
        validate_document_catalog(catalog_value)
        validate_ingestion_manifest(manifest_value)

    def test_registry_rejects_unknown_field(self) -> None:
        value = copy.deepcopy(VALID_CLASSES)
        value["classes"][0]["patterns"] = ["policy"]
        self.assert_reason(validate_class_registry, value, "SCHEMA_FIELD_UNKNOWN")

    def test_registry_rejects_empty_class_list(self) -> None:
        self.assert_reason(
            validate_class_registry,
            {"schema_version": 1, "classes": []},
            "SCHEMA_LIST_EMPTY",
        )

    def test_registry_rejects_boolean_schema_version(self) -> None:
        value = copy.deepcopy(VALID_CLASSES)
        value["schema_version"] = True
        self.assert_reason(validate_class_registry, value, "SCHEMA_VERSION_UNSUPPORTED")

    def test_registry_rejects_invalid_identifier(self) -> None:
        value = copy.deepcopy(VALID_CLASSES)
        value["classes"][0]["class_id"] = "Policy SOP"
        self.assert_reason(validate_class_registry, value, "IDENTIFIER_INVALID")

    def test_registry_rejects_exact_duplicate(self) -> None:
        value = copy.deepcopy(VALID_CLASSES)
        value["classes"].append(copy.deepcopy(value["classes"][0]))
        self.assert_reason(validate_class_registry, value, "IDENTIFIER_DUPLICATE")

    def test_registry_rejects_punctuation_collision(self) -> None:
        value = copy.deepcopy(VALID_CLASSES)
        value["classes"].append(
            {"class_id": "policy.sop", "display_name": "Duplicate", "status": "active"}
        )
        self.assert_reason(validate_class_registry, value, "IDENTIFIER_PUNCTUATION_COLLISION")

    def test_catalog_may_be_empty(self) -> None:
        catalog = validate_document_catalog({"schema_version": 1, "documents": []})
        self.assertEqual(catalog.documents, ())

    def test_catalog_rejects_punctuation_collision(self) -> None:
        value = copy.deepcopy(VALID_CATALOG)
        value["documents"].append(
            {"document_key": "policy.social_media", "display_name": "Duplicate", "status": "active"}
        )
        self.assert_reason(validate_document_catalog, value, "IDENTIFIER_PUNCTUATION_COLLISION")

    def test_catalog_rejects_invalid_status(self) -> None:
        value = copy.deepcopy(VALID_CATALOG)
        value["documents"][0]["status"] = "disabled"
        self.assert_reason(validate_document_catalog, value, "STATUS_INVALID")

    def test_catalog_rejects_unknown_field(self) -> None:
        value = copy.deepcopy(VALID_CATALOG)
        value["documents"][0]["source_path"] = "must-not-live-here.pdf"
        self.assert_reason(validate_document_catalog, value, "SCHEMA_FIELD_UNKNOWN")

    def test_manifest_rejects_empty_actions(self) -> None:
        self.assert_reason(
            validate_ingestion_manifest,
            {"schema_version": 1, "documents": [], "retirements": []},
            "MANIFEST_EMPTY",
        )

    def test_manifest_rejects_unknown_field(self) -> None:
        value = copy.deepcopy(VALID_MANIFEST)
        value["documents"][0]["optional"] = True
        self.assert_reason(validate_ingestion_manifest, value, "SCHEMA_FIELD_UNKNOWN")

    def test_manifest_rejects_absolute_path(self) -> None:
        value = copy.deepcopy(VALID_MANIFEST)
        value["documents"][0]["source_path"] = "/tmp/file.pdf"
        self.assert_reason(validate_ingestion_manifest, value, "SOURCE_PATH_ABSOLUTE")

    def test_manifest_rejects_parent_traversal(self) -> None:
        value = copy.deepcopy(VALID_MANIFEST)
        value["documents"][0]["source_path"] = "policies/../file.pdf"
        self.assert_reason(validate_ingestion_manifest, value, "SOURCE_PATH_TRAVERSAL")

    def test_manifest_rejects_backslash(self) -> None:
        value = copy.deepcopy(VALID_MANIFEST)
        value["documents"][0]["source_path"] = "policies\\file.pdf"
        self.assert_reason(validate_ingestion_manifest, value, "SOURCE_PATH_INVALID")

    def test_manifest_rejects_non_pdf_extension(self) -> None:
        value = copy.deepcopy(VALID_MANIFEST)
        value["documents"][0]["source_path"] = "policies/file.txt"
        self.assert_reason(validate_ingestion_manifest, value, "SOURCE_FORMAT_UNSUPPORTED")

    def test_manifest_rejects_duplicate_source_path(self) -> None:
        value = copy.deepcopy(VALID_MANIFEST)
        duplicate = copy.deepcopy(value["documents"][0])
        duplicate["document_key"] = "policy.another"
        value["documents"].append(duplicate)
        self.assert_reason(validate_ingestion_manifest, value, "MANIFEST_SOURCE_PATH_DUPLICATE")

    def test_manifest_rejects_conflicting_action(self) -> None:
        value = copy.deepcopy(VALID_MANIFEST)
        value["retirements"] = [{"document_key": "policy.social-media"}]
        self.assert_reason(validate_ingestion_manifest, value, "MANIFEST_ACTION_CONFLICT")

    def test_canonical_identity_ignores_mapping_and_list_order(self) -> None:
        first = validate_class_registry(VALID_CLASSES)
        reordered = {
            "classes": [
                {"status": item["status"], "display_name": item["display_name"], "class_id": item["class_id"]}
                for item in reversed(VALID_CLASSES["classes"])
            ],
            "schema_version": 1,
        }
        second = validate_class_registry(reordered)
        self.assertEqual(first.digest, second.digest)


if __name__ == "__main__":
    unittest.main()
