from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from ishikawa.models import PublishedDocumentState
from ishikawa.persistence import (
    CONSOLIDATED_SCHEMA_V5_SHA256,
    PersistenceContractError,
    load_published_state,
    write_incremental_plan,
)
from ishikawa.persistence_models import (
    EmbeddingSpace,
    PreparedChunk,
    PreparedDocument,
    PreparedStructuralUnit,
)
from ishikawa.planner import plan_ingestion
from ishikawa.validators import (
    validate_class_registry,
    validate_document_catalog,
    validate_ingestion_manifest,
)

METHOD = "a" * 64


class FakeCursor:
    def __init__(self, rows=()):
        self.rows = list(rows)

    def fetchone(self):
        return self.rows[0] if self.rows else None

    def fetchall(self):
        return list(self.rows)


class FakeTransaction:
    def __init__(self, connection):
        self.connection = connection

    def __enter__(self):
        self.connection.transaction_entries += 1
        return self

    def __exit__(self, kind, _value, _traceback):
        if kind is None:
            self.connection.commits += 1
        else:
            self.connection.rollbacks += 1
        return False


class FakeConnection:
    def __init__(self, *, published=(), catalog_keys=(), schema_contract=None, active_space=""):
        self.published = list(published)
        self.catalog_keys = list(catalog_keys)
        self.schema_contract = schema_contract or (
            "ishikawa_consolidated_schema_v5|"
            f"{CONSOLIDATED_SCHEMA_V5_SHA256}|5"
        )
        self.active_space = active_space
        self.calls = []
        self.transaction_entries = 0
        self.commits = 0
        self.rollbacks = 0

    def transaction(self):
        return FakeTransaction(self)

    def execute(self, sql, parameters=()):
        normalized = " ".join(sql.split())
        self.calls.append((normalized, tuple(parameters)))
        if "ishikawa.verify-schema" in sql:
            return FakeCursor([(self.schema_contract,)])
        if "ishikawa.load-published-state" in sql:
            return FakeCursor(self.published)
        if "ishikawa.load-catalog-keys" in sql:
            return FakeCursor((key,) for key in self.catalog_keys)
        if "ishikawa.active-embedding-space" in sql:
            return FakeCursor([(self.active_space,)])
        return FakeCursor()

    def tags(self):
        return [sql.split("*/", 1)[0].split("/* ", 1)[1].strip() for sql, _ in self.calls]


def registry():
    return validate_class_registry(
        {
            "schema_version": 1,
            "classes": [
                {"class_id": "policy", "display_name": "Policy", "status": "active"}
            ],
        }
    )


def catalog(status="active"):
    return validate_document_catalog(
        {
            "schema_version": 1,
            "documents": [
                {"document_key": "policy.alpha", "display_name": "Alpha", "status": status}
            ],
        }
    )


def manifest(*, key="policy.alpha", retirement=False):
    return validate_ingestion_manifest(
        {
            "schema_version": 1,
            "documents": []
            if retirement
            else [{"source_path": "policies/alpha.pdf", "document_key": key, "class_id": "policy"}],
            "retirements": [{"document_key": key}] if retirement else [],
        }
    )


def embedding_space():
    return EmbeddingSpace(
        model_name="nomic-embed-text-v1.5",
        model_revision="accepted",
        model_digest="b" * 64,
        tokenizer_digest="c" * 64,
        pooling_method="mean",
        document_prefix="search_document: ",
        query_prefix="search_query: ",
    )


def prepared(source_digest):
    unit = PreparedStructuralUnit(
        ordinal=0,
        structural_kind="paragraph",
        page_start=1,
        page_end=1,
        structural_path=("Policy",),
        source_anchor={"page": 1},
        normalized_text="Operators follow the policy.",
    )
    chunk = PreparedChunk(
        ordinal=0,
        projection_kind="narrative",
        retrieval_text=(
            "Document: Alpha\nDocument identifier: 99 TST 2001\n"
            "Section: Policy\n\nOperators follow the policy."
        ),
        structural_unit_ordinals=(0,),
        relevant_excerpt="Operators follow the policy.",
        page_start=1,
        page_end=1,
        structural_path=("Policy",),
        citation_anchor={"page": 1},
        embedding=(0.0,) * 768,
        content_token_count=5,
        context_token_count=1,
        prefix_token_count=2,
        special_token_count=0,
        submitted_input_digest="d" * 64,
        processing_profile="hierarchical_narrative",
        contextual_fields={
            "projection_properties": {
                "retrieval_document_identity_context": {
                    "document_context": "Alpha",
                    "policy_number": "99 TST 2001",
                    "source": "recognized_document_control_header",
                    "included_in_retrieval_text": True,
                }
            }
        },
        retrieval_filters={
            "document_control": {
                "document_context": "Alpha",
                "policy_number": "99 TST 2001",
            }
        },
    )
    return PreparedDocument(
        document_key="policy.alpha",
        class_id="policy",
        source_digest=source_digest,
        page_count=1,
        processing_profiles=("hierarchical_narrative",),
        structural_units=(unit,),
        chunks=(chunk,),
        embedding_space=embedding_space(),
        language="en",
    )


class PersistenceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "policies").mkdir()
        self.pdf = self.root / "policies" / "alpha.pdf"
        self.pdf.write_bytes(b"%PDF-1.4\nsynthetic fixture\n%%EOF\n")
        self.source_digest = hashlib.sha256(self.pdf.read_bytes()).hexdigest()
        self.registry = registry()
        self.catalog = catalog()
        self.manifest = manifest()

    def plan(self, *, published=None, selected_catalog=None, selected_manifest=None):
        return plan_ingestion(
            self.registry,
            selected_catalog or self.catalog,
            selected_manifest or self.manifest,
            source_root=self.root,
            method_profile_id=METHOD,
            published_state=published,
        )

    def test_add_writes_complete_candidate_and_publishes_atomically(self):
        plan = self.plan()
        connection = FakeConnection()
        result = write_incremental_plan(
            connection,
            self.registry,
            self.catalog,
            self.manifest,
            plan,
            (prepared(self.source_digest),),
        )
        self.assertEqual(result.outcome, "PUBLISHED")
        self.assertEqual(result.published_document_count, 1)
        self.assertEqual(connection.commits, 1)
        self.assertEqual(connection.rollbacks, 0)
        tags = connection.tags()
        for required in (
            "ishikawa.lock-writer",
            "ishikawa.insert-run",
            "ishikawa.insert-document-version",
            "ishikawa.insert-artifact-set",
            "ishikawa.insert-structural-unit",
            "ishikawa.insert-chunk",
            "ishikawa.insert-citation",
            "ishikawa.insert-embedding",
            "ishikawa.activate-document",
            "ishikawa.publish-batch",
            "ishikawa.finish-run",
        ):
            self.assertIn(required, tags)
        insert_run_sql = next(
            sql for sql, _ in connection.calls if "ishikawa.insert-run" in sql
        )
        finish_run_sql = next(
            sql for sql, _ in connection.calls if "ishikawa.finish-run" in sql
        )
        self.assertIn("statement_timestamp()", insert_run_sql)
        self.assertIn("GREATEST(clock_timestamp(), started_at)", finish_run_sql)

    def test_document_text_and_vector_are_parameters_not_sql_text(self):
        plan = self.plan()
        connection = FakeConnection()
        write_incremental_plan(
            connection,
            self.registry,
            self.catalog,
            self.manifest,
            plan,
            (prepared(self.source_digest),),
        )
        for sql, _ in connection.calls:
            self.assertNotIn("Operators follow the policy", sql)
            self.assertNotIn("[0,0,0", sql)
        chunk_call = next(call for call in connection.calls if "ishikawa.insert-chunk" in call[0])
        self.assertTrue(
            any("Operators follow the policy" in value for value in chunk_call[1] if isinstance(value, str))
        )

    def test_document_identity_context_is_persisted_in_postgresql_chunk_fields(self):
        plan = self.plan()
        connection = FakeConnection()
        write_incremental_plan(
            connection,
            self.registry,
            self.catalog,
            self.manifest,
            plan,
            (prepared(self.source_digest),),
        )
        chunk_call = next(
            call for call in connection.calls if "ishikawa.insert-chunk" in call[0]
        )
        self.assertIn("Document: Alpha", chunk_call[1][5])
        contextual_fields = json.loads(chunk_call[1][7])
        retrieval_filters = json.loads(chunk_call[1][8])
        identity = contextual_fields["projection_properties"][
            "retrieval_document_identity_context"
        ]
        self.assertEqual(identity["document_context"], "Alpha")
        self.assertEqual(identity["policy_number"], "99 TST 2001")
        self.assertEqual(
            retrieval_filters["document_control"]["policy_number"],
            "99 TST 2001",
        )
        citation_call = next(
            call for call in connection.calls if "ishikawa.insert-citation" in call[0]
        )
        self.assertIn("Operators follow the policy.", citation_call[1])
        self.assertNotIn("Document: Alpha", citation_call[1])

    def test_schema_mismatch_rolls_back_before_application_writes(self):
        schema_path = (
            Path(__file__).resolve().parents[1]
            / "packaging"
            / "database"
            / "schema.sql"
        )
        self.assertEqual(
            hashlib.sha256(schema_path.read_bytes()).hexdigest(),
            CONSOLIDATED_SCHEMA_V5_SHA256,
        )
        connection = FakeConnection(schema_contract="wrong")
        with self.assertRaises(PersistenceContractError):
            write_incremental_plan(
                connection,
                self.registry,
                self.catalog,
                self.manifest,
                self.plan(),
                (prepared(self.source_digest),),
            )
        self.assertEqual(connection.commits, 0)
        self.assertEqual(connection.rollbacks, 1)
        self.assertNotIn("ishikawa.insert-run", connection.tags())

    def test_live_state_change_rolls_back_before_run_creation(self):
        plan = self.plan()
        connection = FakeConnection(
            published=[("policy.alpha", self.source_digest, "policy", METHOD, "1" * 64, "2" * 64, "3" * 64)],
            catalog_keys=["policy.alpha"],
        )
        with self.assertRaises(PersistenceContractError):
            write_incremental_plan(
                connection,
                self.registry,
                self.catalog,
                self.manifest,
                plan,
                (prepared(self.source_digest),),
            )
        self.assertEqual(connection.rollbacks, 1)
        self.assertNotIn("ishikawa.insert-run", connection.tags())

    def test_reuse_only_run_is_skipped_without_publication_batch(self):
        prior = PublishedDocumentState(
            "policy.alpha", self.source_digest, "policy", METHOD, "1" * 64, "2" * 64, "3" * 64
        )
        plan = self.plan(published={"policy.alpha": prior})
        connection = FakeConnection(
            published=[("policy.alpha", self.source_digest, "policy", METHOD, "1" * 64, "2" * 64, "3" * 64)],
            catalog_keys=["policy.alpha"],
        )
        result = write_incremental_plan(
            connection, self.registry, self.catalog, self.manifest, plan
        )
        self.assertEqual(result.outcome, "SKIPPED")
        self.assertEqual(result.reused_document_count, 1)
        self.assertNotIn("ishikawa.insert-publication-batch", connection.tags())

    def test_unknown_document_quarantine_creates_no_publication(self):
        unknown_manifest = manifest(key="policy.unknown")
        plan = self.plan(selected_manifest=unknown_manifest)
        connection = FakeConnection()
        result = write_incremental_plan(
            connection, self.registry, self.catalog, unknown_manifest, plan
        )
        self.assertEqual(result.outcome, "QUARANTINED")
        self.assertEqual(result.quarantine_record_count, 1)
        self.assertIn("ishikawa.insert-quarantine", connection.tags())
        self.assertNotIn("ishikawa.insert-publication-batch", connection.tags())

    def test_rejected_plan_never_opens_transaction(self):
        missing = self.root / "policies" / "alpha.pdf"
        missing.unlink()
        plan = self.plan()
        connection = FakeConnection()
        with self.assertRaises(PersistenceContractError):
            write_incremental_plan(connection, self.registry, self.catalog, self.manifest, plan)
        self.assertEqual(connection.transaction_entries, 0)

    def test_retirement_deletes_only_the_selected_active_pointer(self):
        retirement_manifest = manifest(retirement=True)
        retired_catalog = catalog("retired")
        prior = PublishedDocumentState(
            "policy.alpha", self.source_digest, "policy", METHOD, "1" * 64, "2" * 64, "3" * 64
        )
        plan = self.plan(
            published={"policy.alpha": prior},
            selected_catalog=retired_catalog,
            selected_manifest=retirement_manifest,
        )
        connection = FakeConnection(
            published=[("policy.alpha", self.source_digest, "policy", METHOD, "1" * 64, "2" * 64, "3" * 64)],
            catalog_keys=["policy.alpha"],
        )
        result = write_incremental_plan(
            connection, self.registry, retired_catalog, retirement_manifest, plan
        )
        self.assertEqual(result.retired_document_count, 1)
        self.assertIn("ishikawa.retire-active-document", connection.tags())
        self.assertNotIn("ishikawa.insert-document-version", connection.tags())

    def test_missing_persisted_catalog_key_rolls_back(self):
        plan = self.plan()
        connection = FakeConnection(catalog_keys=["policy.alpha", "policy.removed"])
        with self.assertRaises(PersistenceContractError):
            write_incremental_plan(
                connection,
                self.registry,
                self.catalog,
                self.manifest,
                plan,
                (prepared(self.source_digest),),
            )
        self.assertEqual(connection.rollbacks, 1)

    def test_prepared_document_must_exactly_match_plan(self):
        plan = self.plan()
        wrong = PreparedDocument(
            document_key="policy.alpha",
            class_id="policy",
            source_digest="f" * 64,
            page_count=1,
            processing_profiles=prepared(self.source_digest).processing_profiles,
            structural_units=prepared(self.source_digest).structural_units,
            chunks=prepared(self.source_digest).chunks,
            embedding_space=embedding_space(),
        )
        connection = FakeConnection()
        with self.assertRaises(PersistenceContractError):
            write_incremental_plan(
                connection, self.registry, self.catalog, self.manifest, plan, (wrong,)
            )
        self.assertEqual(connection.transaction_entries, 0)

    def test_load_published_state_preserves_database_identities(self):
        connection = FakeConnection(
            published=[("policy.alpha", "a" * 64, "policy", "b" * 64, "c" * 64, "d" * 64, "e" * 64)]
        )
        state = load_published_state(connection)["policy.alpha"]
        self.assertEqual(state.artifact_set_id, "e" * 64)

    def test_embedding_dimension_is_enforced_before_database_access(self):
        with self.assertRaises(ValueError):
            PreparedChunk(
                ordinal=0,
                projection_kind="narrative",
                retrieval_text="x",
                structural_unit_ordinals=(0,),
                relevant_excerpt="x",
                page_start=1,
                page_end=1,
                structural_path=(),
                citation_anchor={},
                embedding=(0.0,) * 767,
                content_token_count=1,
                context_token_count=0,
                prefix_token_count=0,
                special_token_count=0,
                submitted_input_digest="d" * 64,
                processing_profile="narrative",
            )


if __name__ == "__main__":
    unittest.main()
