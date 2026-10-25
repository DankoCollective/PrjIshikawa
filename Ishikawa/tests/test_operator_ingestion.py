from __future__ import annotations

import hashlib
import json
import os
import tempfile
import unittest
from pathlib import Path

from ishikawa.operator_ingestion import (
    OperatorIngestionContractError,
    OperatorIngestionPaths,
    _active_reference_owners,
    run_operator_ingestion,
)
from ishikawa.canonical import domain_digest
from ishikawa.persistence_models import WriteResult


METHOD = "a" * 64


class Rows:
    def __init__(self, values=()):
        self.values = list(values)

    def fetchall(self):
        return list(self.values)


class PlanningConnection:
    def __init__(self, published=(), catalog_keys=()):
        self.published = list(published)
        self.catalog_keys = list(catalog_keys)
        self.tags: list[str] = []

    def execute(self, sql, _parameters=()):
        if "ishikawa.load-published-state" in sql:
            self.tags.append("load-published-state")
            return Rows(self.published)
        if "ishikawa.load-catalog-keys" in sql:
            self.tags.append("load-catalog-keys")
            return Rows((key,) for key in self.catalog_keys)
        raise AssertionError("unexpected SQL")


class OperatorIngestionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.config = self.root / "config"
        self.source = self.root / "corpus"
        self.reports = self.root / "reports"
        self.config.mkdir()
        (self.source / "policies").mkdir(parents=True)
        self.pdf = self.source / "policies" / "alpha.pdf"
        self.pdf.write_bytes(b"%PDF-1.4\noperator ingestion fixture\n%%EOF\n")
        self.source_digest = hashlib.sha256(self.pdf.read_bytes()).hexdigest()
        self.class_path = self.config / "document_classes.yaml"
        self.catalog_path = self.config / "document_catalog.yaml"
        self.manifest_path = self.config / "ingestion_manifest.yaml"
        self.class_path.write_text(
            """schema_version: 1
classes:
  - class_id: policy
    display_name: Policy
    status: active
""",
            encoding="utf-8",
        )
        self.catalog_path.write_text(
            """schema_version: 1
documents:
  - document_key: policy.alpha
    display_name: Alpha Policy
    status: active
""",
            encoding="utf-8",
        )
        self.write_document_manifest()

    def paths(self, report_name: str) -> OperatorIngestionPaths:
        return OperatorIngestionPaths(
            self.class_path,
            self.catalog_path,
            self.manifest_path,
            self.source,
            self.reports / report_name,
        )

    def write_document_manifest(self, *, class_id="policy", key="policy.alpha"):
        self.manifest_path.write_text(
            f"""schema_version: 1
documents:
  - source_path: policies/alpha.pdf
    document_key: {key}
    class_id: {class_id}
retirements: []
""",
            encoding="utf-8",
        )

    @staticmethod
    def writer_result(outcome: str) -> WriteResult:
        return WriteResult(
            ingestion_run_id="1" * 64,
            publication_batch_id="2" * 64 if outcome == "PUBLISHED" else None,
            outcome=outcome,
            published_document_count=1 if outcome == "PUBLISHED" else 0,
            retired_document_count=0,
            reused_document_count=1 if outcome == "SKIPPED" else 0,
            quarantine_record_count=1 if outcome == "QUARANTINED" else 0,
        )

    def test_validate_only_reads_state_but_never_produces_or_writes(self):
        calls = {"producer": 0, "writer": 0}

        def producer(_batch):
            calls["producer"] += 1
            return ()

        def writer(*_args):
            calls["writer"] += 1
            return self.writer_result("PUBLISHED")

        connection = PlanningConnection()
        result = run_operator_ingestion(
            paths=self.paths("validate"),
            method_profile_id=METHOD,
            connection=connection,
            validate_only=True,
            producer=producer,
            writer=writer,
        )
        self.assertEqual(result.exit_code, 0)
        self.assertTrue(result.plan.validation_only)
        self.assertFalse(result.plan.mutation_performed)
        self.assertEqual(calls, {"producer": 0, "writer": 0})
        self.assertEqual(connection.tags, ["load-published-state", "load-catalog-keys"])

    def test_active_reference_owners_preserve_reused_document_declarations(self):
        document_id = domain_digest(
            "ishikawa.document.v1", {"document_key": "policy.beta"}
        )

        class ActiveOwnerConnection:
            def execute(self, sql, parameters=()):
                self.sql = sql
                self.parameters = parameters
                return Rows(
                    (
                        ("policy.beta", document_id, "Policy Number: 99 TST 2002."),
                        ("policy.beta", document_id, "Apply 99 TST 2001."),
                    )
                )

        connection = ActiveOwnerConnection()
        owners = _active_reference_owners(
            connection,
            excluded_document_keys=frozenset({"policy.alpha"}),
        )
        self.assertEqual(len(owners), 1)
        self.assertEqual(owners[0].reference_value, "99 TST 2002")
        self.assertEqual(owners[0].document_key, "policy.beta")
        self.assertIn("ishikawa.load-active-reference-owners", connection.sql)

    def test_actual_add_produces_only_planned_document_then_writes(self):
        observed = {}

        def producer(batch):
            observed["batch"] = batch
            return (object(),)

        def writer(_connection, registry, catalog, manifest, plan, prepared):
            observed["identities"] = (
                registry.digest,
                catalog.digest,
                manifest.digest,
                plan.validation_id,
            )
            observed["prepared"] = prepared
            return self.writer_result("PUBLISHED")

        result = run_operator_ingestion(
            paths=self.paths("add"),
            method_profile_id=METHOD,
            connection=PlanningConnection(),
            validate_only=False,
            producer=producer,
            writer=writer,
        )
        request = observed["batch"].documents[0]
        self.assertEqual(request.action, "add")
        self.assertEqual(request.document_key, "policy.alpha")
        self.assertEqual(request.relative_source_path, "policies/alpha.pdf")
        self.assertEqual(request.source_digest, self.source_digest)
        self.assertEqual(len(observed["prepared"]), 1)
        self.assertEqual(result.exit_code, 0)
        self.assertFalse(result.plan.validation_only)
        self.assertTrue(result.plan.mutation_performed)
        self.assertEqual(result.write_result.outcome, "PUBLISHED")

    def test_reuse_skips_producer_but_still_records_writer_run(self):
        producer_calls = 0
        writer_prepared = None
        published = [
            (
                "policy.alpha",
                self.source_digest,
                "policy",
                METHOD,
                "1" * 64,
                "2" * 64,
                "3" * 64,
            )
        ]

        def producer(_batch):
            nonlocal producer_calls
            producer_calls += 1
            return ()

        def writer(_connection, _registry, _catalog, _manifest, _plan, prepared):
            nonlocal writer_prepared
            writer_prepared = prepared
            return self.writer_result("SKIPPED")

        result = run_operator_ingestion(
            paths=self.paths("reuse"),
            method_profile_id=METHOD,
            connection=PlanningConnection(published=published, catalog_keys=("policy.alpha",)),
            validate_only=False,
            producer=producer,
            writer=writer,
        )
        self.assertEqual(producer_calls, 0)
        self.assertEqual(writer_prepared, ())
        self.assertEqual(result.plan.entries[0].action, "reuse")
        self.assertFalse(result.plan.mutation_performed)
        self.assertEqual(result.write_result.outcome, "SKIPPED")

    def test_quarantine_invokes_writer_without_producer_and_returns_nonzero(self):
        self.write_document_manifest(key="policy.unknown")
        producer_calls = 0
        writer_calls = 0

        def producer(_batch):
            nonlocal producer_calls
            producer_calls += 1
            return ()

        def writer(_connection, _registry, _catalog, _manifest, plan, prepared):
            nonlocal writer_calls
            writer_calls += 1
            self.assertEqual(plan.overall_outcome, "QUARANTINED")
            self.assertEqual(prepared, ())
            return self.writer_result("QUARANTINED")

        result = run_operator_ingestion(
            paths=self.paths("quarantine"),
            method_profile_id=METHOD,
            connection=PlanningConnection(),
            validate_only=False,
            producer=producer,
            writer=writer,
        )
        self.assertEqual(producer_calls, 0)
        self.assertEqual(writer_calls, 1)
        self.assertEqual(result.exit_code, 1)
        self.assertTrue(result.plan.mutation_performed)

    def test_quarantined_batch_does_not_produce_other_passing_entries(self):
        self.manifest_path.write_text(
            """schema_version: 1
documents:
  - source_path: policies/alpha.pdf
    document_key: policy.alpha
    class_id: policy
  - source_path: policies/missing.pdf
    document_key: policy.unknown
    class_id: policy
retirements: []
""",
            encoding="utf-8",
        )
        producer_calls = 0

        def producer(_batch):
            nonlocal producer_calls
            producer_calls += 1
            return (object(),)

        def writer(_connection, _registry, _catalog, _manifest, plan, prepared):
            self.assertEqual(plan.overall_outcome, "QUARANTINED")
            self.assertEqual(prepared, ())
            return self.writer_result("QUARANTINED")

        result = run_operator_ingestion(
            paths=self.paths("mixed-quarantine"),
            method_profile_id=METHOD,
            connection=PlanningConnection(),
            validate_only=False,
            producer=producer,
            writer=writer,
        )
        self.assertEqual(producer_calls, 0)
        self.assertEqual(result.write_result.outcome, "QUARANTINED")

    def test_rejected_plan_invokes_neither_producer_nor_writer(self):
        self.write_document_manifest(class_id="unknown")
        calls = []
        result = run_operator_ingestion(
            paths=self.paths("rejected"),
            method_profile_id=METHOD,
            connection=PlanningConnection(),
            validate_only=False,
            producer=lambda _batch: calls.append("producer"),
            writer=lambda *_args: calls.append("writer"),
        )
        self.assertEqual(result.exit_code, 2)
        self.assertEqual(result.plan.overall_outcome, "REJECTED")
        self.assertEqual(calls, [])

    def test_actual_changed_document_requires_producer(self):
        with self.assertRaises(OperatorIngestionContractError) as caught:
            run_operator_ingestion(
                paths=self.paths("missing-producer"),
                method_profile_id=METHOD,
                connection=PlanningConnection(),
                validate_only=False,
                producer=None,
            )
        self.assertEqual(str(caught.exception), "prepared_document_producer_required")

    def test_reports_are_private_and_reflect_actual_mutation(self):
        result = run_operator_ingestion(
            paths=self.paths("private"),
            method_profile_id=METHOD,
            connection=PlanningConnection(),
            validate_only=False,
            producer=lambda _batch: (object(),),
            writer=lambda *_args: self.writer_result("PUBLISHED"),
        )
        payload = json.loads(result.json_report.read_text(encoding="utf-8"))
        self.assertFalse(payload["validation_only"])
        self.assertTrue(payload["mutation_performed"])
        self.assertEqual(os.stat(result.text_report).st_mode & 0o777, 0o600)
        self.assertEqual(os.stat(result.json_report).st_mode & 0o777, 0o600)
        self.assertNotIn(str(self.source), result.terminal_summary)

    def test_retirement_never_invokes_document_producer(self):
        self.catalog_path.write_text(
            """schema_version: 1
documents:
  - document_key: policy.alpha
    display_name: Alpha Policy
    status: retired
""",
            encoding="utf-8",
        )
        self.manifest_path.write_text(
            """schema_version: 1
documents: []
retirements:
  - document_key: policy.alpha
""",
            encoding="utf-8",
        )
        published = [
            (
                "policy.alpha",
                self.source_digest,
                "policy",
                METHOD,
                "1" * 64,
                "2" * 64,
                "3" * 64,
            )
        ]
        producer_calls = 0

        def producer(_batch):
            nonlocal producer_calls
            producer_calls += 1
            return ()

        def writer(_connection, _registry, _catalog, _manifest, plan, prepared):
            self.assertEqual(plan.entries[0].action, "retire")
            self.assertEqual(prepared, ())
            return WriteResult("1" * 64, "2" * 64, "PUBLISHED", 0, 1, 0, 0)

        result = run_operator_ingestion(
            paths=self.paths("retire"),
            method_profile_id=METHOD,
            connection=PlanningConnection(published=published, catalog_keys=("policy.alpha",)),
            validate_only=False,
            producer=producer,
            writer=writer,
        )
        self.assertEqual(producer_calls, 0)
        self.assertEqual(result.write_result.retired_document_count, 1)


if __name__ == "__main__":
    unittest.main()
