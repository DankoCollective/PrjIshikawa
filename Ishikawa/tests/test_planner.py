from __future__ import annotations

import hashlib
import tempfile
import unittest
from pathlib import Path

from ishikawa.errors import IshikawaValidationError
from ishikawa.models import PublishedDocumentState
from ishikawa.planner import plan_ingestion
from ishikawa.validators import (
    validate_class_registry,
    validate_document_catalog,
    validate_ingestion_manifest,
)

METHOD_A = "a" * 64
METHOD_B = "b" * 64


def registry(*, retired: bool = False):
    return validate_class_registry(
        {
            "schema_version": 1,
            "classes": [
                {
                    "class_id": "policy",
                    "display_name": "Policy",
                    "status": "retired" if retired else "active",
                },
                {"class_id": "regulation", "display_name": "Regulation", "status": "active"},
            ],
        }
    )


def catalog(status: str = "active"):
    return validate_document_catalog(
        {
            "schema_version": 1,
            "documents": [
                {"document_key": "policy.alpha", "display_name": "Alpha", "status": status}
            ],
        }
    )


def document_manifest(path: str = "policies/alpha.pdf", class_id: str = "policy", key: str = "policy.alpha"):
    return validate_ingestion_manifest(
        {
            "schema_version": 1,
            "documents": [{"source_path": path, "document_key": key, "class_id": class_id}],
            "retirements": [],
        }
    )


class PlannerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "policies").mkdir()
        self.pdf = self.root / "policies" / "alpha.pdf"
        self.pdf.write_bytes(b"%PDF-1.4\nfixture-one\n%%EOF\n")

    def source_digest(self) -> str:
        return hashlib.sha256(self.pdf.read_bytes()).hexdigest()

    def plan(self, **kwargs):
        return plan_ingestion(
            kwargs.pop("registry", registry()),
            kwargs.pop("catalog", catalog()),
            kwargs.pop("manifest", document_manifest()),
            source_root=self.root,
            method_profile_id=kwargs.pop("method_profile_id", METHOD_A),
            **kwargs,
        )

    def test_add_action_and_no_mutation(self) -> None:
        plan = self.plan()
        self.assertEqual(plan.overall_outcome, "PASS")
        self.assertEqual(plan.entries[0].action, "add")
        self.assertTrue(plan.validation_only)
        self.assertFalse(plan.mutation_performed)

    def test_revise_action(self) -> None:
        prior = PublishedDocumentState("policy.alpha", "0" * 64, "policy", METHOD_A)
        self.assertEqual(self.plan(published_state={"policy.alpha": prior}).entries[0].action, "revise")

    def test_reprocess_for_class_change(self) -> None:
        prior = PublishedDocumentState("policy.alpha", self.source_digest(), "regulation", METHOD_A)
        self.assertEqual(self.plan(published_state={"policy.alpha": prior}).entries[0].action, "reprocess")

    def test_reprocess_for_method_change(self) -> None:
        prior = PublishedDocumentState("policy.alpha", self.source_digest(), "policy", METHOD_B)
        self.assertEqual(self.plan(published_state={"policy.alpha": prior}).entries[0].action, "reprocess")

    def test_reuse_action(self) -> None:
        prior = PublishedDocumentState("policy.alpha", self.source_digest(), "policy", METHOD_A)
        self.assertEqual(self.plan(published_state={"policy.alpha": prior}).entries[0].action, "reuse")

    def test_retire_action(self) -> None:
        manifest = validate_ingestion_manifest(
            {"schema_version": 1, "documents": [], "retirements": [{"document_key": "policy.alpha"}]}
        )
        prior = PublishedDocumentState("policy.alpha", self.source_digest(), "policy", METHOD_A)
        plan = self.plan(
            catalog=catalog("retired"),
            manifest=manifest,
            published_state={"policy.alpha": prior},
        )
        self.assertEqual(plan.overall_outcome, "PASS")
        self.assertEqual(plan.entries[0].action, "retire")

    def test_unknown_document_key_is_quarantined_before_file_read(self) -> None:
        plan = self.plan(manifest=document_manifest(path="missing.pdf", key="policy.unknown"))
        self.assertEqual(plan.overall_outcome, "QUARANTINED")
        self.assertEqual(plan.entries[0].reason_code, "UNKNOWN_DOCUMENT_KEY")

    def test_unknown_class_is_rejected(self) -> None:
        plan = self.plan(manifest=document_manifest(class_id="unknown"))
        self.assertEqual(plan.overall_outcome, "REJECTED")
        self.assertEqual(plan.entries[0].reason_code, "UNKNOWN_CLASS_ID")

    def test_retired_class_is_rejected(self) -> None:
        plan = self.plan(registry=registry(retired=True))
        self.assertEqual(plan.entries[0].reason_code, "CLASS_RETIRED")

    def test_missing_file_is_rejected(self) -> None:
        plan = self.plan(manifest=document_manifest(path="policies/missing.pdf"))
        self.assertEqual(plan.entries[0].reason_code, "SOURCE_FILE_UNAVAILABLE")

    def test_source_symlink_is_rejected(self) -> None:
        linked = self.root / "policies" / "linked.pdf"
        linked.symlink_to(self.pdf)
        plan = self.plan(manifest=document_manifest(path="policies/linked.pdf"))
        self.assertEqual(plan.entries[0].reason_code, "SOURCE_PATH_SYMLINK")

    def test_non_regular_source_is_rejected(self) -> None:
        directory = self.root / "policies" / "directory.pdf"
        directory.mkdir()
        plan = self.plan(manifest=document_manifest(path="policies/directory.pdf"))
        self.assertEqual(plan.entries[0].reason_code, "SOURCE_NOT_REGULAR_FILE")

    def test_non_pdf_signature_is_quarantined(self) -> None:
        self.pdf.write_text("not actually a PDF", encoding="utf-8")
        plan = self.plan()
        self.assertEqual(plan.overall_outcome, "QUARANTINED")
        self.assertEqual(plan.entries[0].reason_code, "UNSUPPORTED_PDF")

    def test_removed_catalog_key_blocks_batch(self) -> None:
        plan = self.plan(prior_catalog_keys={"policy.alpha", "policy.missing"})
        self.assertEqual(plan.overall_outcome, "REJECTED")
        self.assertEqual(plan.entries[0].outcome, "PASS")
        self.assertEqual(plan.issues[0].reason_code, "CATALOG_KEY_REMOVED")

    def test_one_quarantined_entry_blocks_entire_batch(self) -> None:
        manifest = validate_ingestion_manifest(
            {
                "schema_version": 1,
                "documents": [
                    {
                        "source_path": "policies/alpha.pdf",
                        "document_key": "policy.alpha",
                        "class_id": "policy",
                    },
                    {
                        "source_path": "policies/unknown.pdf",
                        "document_key": "policy.unknown",
                        "class_id": "policy",
                    },
                ],
                "retirements": [],
            }
        )
        plan = self.plan(manifest=manifest)
        self.assertEqual(plan.entries[0].action, "add")
        self.assertEqual(plan.entries[0].outcome, "PASS")
        self.assertEqual(plan.entries[1].outcome, "QUARANTINED")
        self.assertEqual(plan.overall_outcome, "QUARANTINED")
        self.assertFalse(plan.mutation_performed)

    def test_retirement_requires_catalog_retired_status(self) -> None:
        manifest = validate_ingestion_manifest(
            {"schema_version": 1, "documents": [], "retirements": [{"document_key": "policy.alpha"}]}
        )
        prior = PublishedDocumentState("policy.alpha", self.source_digest(), "policy", METHOD_A)
        plan = self.plan(manifest=manifest, published_state={"policy.alpha": prior})
        self.assertEqual(plan.entries[0].reason_code, "RETIREMENT_STATUS_MISMATCH")

    def test_retirement_requires_published_document(self) -> None:
        manifest = validate_ingestion_manifest(
            {"schema_version": 1, "documents": [], "retirements": [{"document_key": "policy.alpha"}]}
        )
        plan = self.plan(catalog=catalog("retired"), manifest=manifest)
        self.assertEqual(plan.entries[0].reason_code, "RETIREMENT_NOT_PUBLISHED")

    def test_method_profile_identity_is_validated(self) -> None:
        with self.assertRaises(IshikawaValidationError) as caught:
            self.plan(method_profile_id="manual-version")
        self.assertEqual(caught.exception.reason_code, "METHOD_PROFILE_ID_INVALID")

    def test_validation_identity_is_deterministic(self) -> None:
        self.assertEqual(self.plan().validation_id, self.plan().validation_id)


if __name__ == "__main__":
    unittest.main()
