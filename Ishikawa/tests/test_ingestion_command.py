from __future__ import annotations

import hashlib
import io
import tempfile
import unittest
from pathlib import Path

from ishikawa.ingestion_command import (
    IngestionCommandPorts,
    execute_ingestion_command,
    parse_ingestion_arguments,
)
from ishikawa.live_document_stage import LiveDocumentStageError
from ishikawa.operator_ingestion import OperatorIngestionContractError
from ishikawa.persistence import PersistenceContractError
from ishikawa.persistence_models import WriteResult


class Rows:
    def __init__(self, values=()):
        self.values = list(values)

    def fetchall(self):
        return list(self.values)


class Connection:
    def __init__(self):
        self.closed = False

    def execute(self, sql, _parameters=()):
        if "ishikawa.load-published-state" in sql or "ishikawa.load-catalog-keys" in sql:
            return Rows()
        raise AssertionError("unexpected SQL")

    def close(self):
        self.closed = True


class IngestionCommandTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.config = self.root / "config"
        self.source = self.root / "source"
        self.config.mkdir()
        self.source.mkdir()
        pdf = self.source / "sample.pdf"
        pdf.write_bytes(b"%PDF-1.4\nportable command fixture\n%%EOF\n")
        digest = hashlib.sha256(pdf.read_bytes()).hexdigest()
        (self.config / "document_classes.yaml").write_text(
            "schema_version: 1\nclasses:\n  - class_id: policy\n    display_name: Policy\n    status: active\n",
            encoding="utf-8",
        )
        (self.config / "document_catalog.yaml").write_text(
            "schema_version: 1\ndocuments:\n  - document_key: policy.sample\n    display_name: Sample\n    status: active\n",
            encoding="utf-8",
        )
        (self.config / "ingestion_manifest.yaml").write_text(
            "schema_version: 1\ndocuments:\n  - source_path: sample.pdf\n    document_key: policy.sample\n    class_id: policy\nretirements: []\n",
            encoding="utf-8",
        )
        self.digest = digest
        self.reports = self.root / "reports"

    def arguments(self, mode="--validate-only"):
        return [
            mode,
            "--class-registry", str((self.config / "document_classes.yaml").resolve()),
            "--document-catalog", str((self.config / "document_catalog.yaml").resolve()),
            "--ingestion-manifest", str((self.config / "ingestion_manifest.yaml").resolve()),
            "--source-root", str(self.source.resolve()),
            "--report-root", str(self.reports.resolve()),
        ]

    @staticmethod
    def result():
        return WriteResult("1" * 64, "2" * 64, "PUBLISHED", 1, 0, 0, 0)

    def test_validate_only_reads_connection_but_calls_no_mutating_port(self):
        connection = Connection()
        calls = []
        output = io.StringIO()
        status = execute_ingestion_command(
            self.arguments(),
            ports=IngestionCommandPorts(
                lambda: connection,
                lambda _batch: calls.append("producer"),
                lambda *_items: calls.append("writer"),
            ),
            output=output,
        )
        self.assertEqual(status, 0)
        self.assertEqual(calls, [])
        self.assertTrue(connection.closed)
        self.assertIn("ishikawa_ingestion=pass;exit_code=0", output.getvalue())
        self.assertNotIn(str(self.source), output.getvalue())

    def test_publish_calls_producer_and_writer_once(self):
        connection = Connection()
        calls = []

        def producer(batch):
            calls.append(("producer", len(batch.documents)))
            return (object(),)

        def writer(*items):
            calls.append(("writer", len(items[-1])))
            return self.result()

        status = execute_ingestion_command(
            self.arguments("--publish"),
            ports=IngestionCommandPorts(lambda: connection, producer, writer),
            output=io.StringIO(),
        )
        self.assertEqual(status, 0)
        self.assertEqual(calls, [("producer", 1), ("writer", 1)])
        self.assertTrue(connection.closed)

    def test_publish_requires_producer_before_connection(self):
        connection_calls = []
        output = io.StringIO()
        status = execute_ingestion_command(
            self.arguments("--publish"),
            ports=IngestionCommandPorts(lambda: connection_calls.append(True), None),
            output=output,
        )
        self.assertEqual(status, 2)
        self.assertEqual(connection_calls, [])
        self.assertEqual(
            output.getvalue(),
            "ishikawa_ingestion=blocked;reason=producer_required_for_publish\n",
        )

    def test_relationship_registry_port_must_be_validated(self):
        with self.assertRaisesRegex(Exception, "dependency_port_invalid"):
            IngestionCommandPorts(
                lambda: Connection(),
                None,
                relationship_registry=object(),
            )

    def test_modes_are_exactly_one_and_unknown_options_are_rejected(self):
        for values in (
            self.arguments()[1:],
            self.arguments() + ["--publish"],
            self.arguments() + ["--database-password", "secret"],
        ):
            with self.subTest(values=values), self.assertRaises(Exception):
                parse_ingestion_arguments(values)

    def test_paths_must_be_absolute_and_non_symlink(self):
        values = self.arguments()
        values[2] = "relative.yaml"
        with self.assertRaises(Exception):
            parse_ingestion_arguments(values)
        link = self.root / "classes-link.yaml"
        link.symlink_to(self.config / "document_classes.yaml")
        values = self.arguments()
        values[2] = str(link)
        with self.assertRaises(Exception):
            parse_ingestion_arguments(values)

    def test_unexpected_failure_is_content_safe_and_closes_connection(self):
        connection = Connection()
        output = io.StringIO()

        def fail(*_items):
            raise RuntimeError("private database detail")

        status = execute_ingestion_command(
            self.arguments("--publish"),
            ports=IngestionCommandPorts(lambda: connection, lambda _batch: (object(),), fail),
            output=output,
        )
        self.assertEqual(status, 1)
        self.assertTrue(connection.closed)
        self.assertEqual(output.getvalue(), "ishikawa_ingestion=blocked;reason=runtime_failure\n")
        self.assertNotIn("private", output.getvalue())

        classified_connection = Connection()
        classified_output = io.StringIO()

        def classified_failure(_batch):
            raise LiveDocumentStageError("stage_process_pipeline_layout_unsafe")

        classified_status = execute_ingestion_command(
            self.arguments("--publish"),
            ports=IngestionCommandPorts(
                lambda: classified_connection,
                classified_failure,
                lambda *_items: self.result(),
            ),
            output=classified_output,
        )
        self.assertEqual(classified_status, 1)
        self.assertTrue(classified_connection.closed)
        self.assertEqual(
            classified_output.getvalue(),
            "ishikawa_ingestion=blocked;"
            "reason=live_document_stage_stage_process_pipeline_layout_unsafe\n",
        )

    def test_persistence_and_operator_failures_return_safe_actionable_reasons(self):
        cases = (
            (
                PersistenceContractError(
                    "PostgreSQL consolidated contract does not match schema version 5"
                ),
                "persistence_schema_contract_mismatch",
            ),
            (
                OperatorIngestionContractError("planned_document_source_digest_absent"),
                "operator_ingestion_planned_document_source_digest_absent",
            ),
        )
        for error, expected_reason in cases:
            with self.subTest(expected_reason=expected_reason):
                connection = Connection()
                output = io.StringIO()

                def fail(*_items, selected_error=error):
                    raise selected_error

                status = execute_ingestion_command(
                    self.arguments("--publish"),
                    ports=IngestionCommandPorts(
                        lambda: connection,
                        lambda _batch: (object(),),
                        fail,
                    ),
                    output=output,
                )
                self.assertEqual(status, 1)
                self.assertTrue(connection.closed)
                self.assertEqual(
                    output.getvalue(),
                    f"ishikawa_ingestion=blocked;reason={expected_reason}\n",
                )

    def test_unrecognized_persistence_message_remains_content_safe(self):
        connection = Connection()
        output = io.StringIO()

        def fail(*_items):
            raise PersistenceContractError("private database detail")

        status = execute_ingestion_command(
            self.arguments("--publish"),
            ports=IngestionCommandPorts(
                lambda: connection,
                lambda _batch: (object(),),
                fail,
            ),
            output=output,
        )
        self.assertEqual(status, 1)
        self.assertEqual(output.getvalue(), "ishikawa_ingestion=blocked;reason=runtime_failure\n")
        self.assertNotIn("private", output.getvalue())

    def test_postgresql_sqlstate_is_reported_without_database_detail(self):
        class CheckViolation(RuntimeError):
            sqlstate = "23514"

        connection = Connection()
        output = io.StringIO()

        def fail(*_items):
            raise CheckViolation("private relation and row detail")

        status = execute_ingestion_command(
            self.arguments("--publish"),
            ports=IngestionCommandPorts(
                lambda: connection,
                lambda _batch: (object(),),
                fail,
            ),
            output=output,
        )
        self.assertEqual(status, 1)
        self.assertEqual(
            output.getvalue(),
            "ishikawa_ingestion=blocked;reason=postgresql_check_violation\n",
        )
        self.assertNotIn("private", output.getvalue())


if __name__ == "__main__":
    unittest.main()
