from __future__ import annotations

import copy
import tempfile
import unittest
from pathlib import Path

from ishikawa.document_producer import NativeDocumentProducer, ProducerArtifactBundle
from ishikawa.ingestion_runtime import (
    ConfiguredIngestionRuntime,
    IngestionRuntimeConfigurationError,
    NativeIngestionConnectionFactory,
    assemble_configured_ingestion_runtime,
    validate_ingestion_dependencies,
)
from ishikawa.operator_ingestion import OperatorIngestionPaths
from ishikawa.runtime import ProtectedEnvironmentValue
from ishikawa.yaml_loader import load_restricted_yaml


class IngestionRuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path(__file__).resolve().parents[1]
        cls.runtime_config = cls.root / "config/templates"
        cls.fixture = cls.root / "tests/fixtures/pipeline_writer"
        cls.dependencies = load_restricted_yaml(
            cls.runtime_config / "ingestion_dependencies.yaml",
            label="ingestion dependencies",
        )

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name) / "work"
        self.reports = Path(self.temporary.name) / "reports"
        self.work.mkdir()
        self.paths = OperatorIngestionPaths(
            self.fixture / "document_classes.yaml",
            self.fixture / "document_catalog.yaml",
            self.fixture / "ingestion_manifest.yaml",
            self.fixture / "source",
            self.reports,
        )

    @staticmethod
    def stage_factory(calls):
        def factory(policy, credential):
            calls.append((policy, credential))

            def stage(_batch, _manifest, _workspace):
                raise AssertionError("stage must remain lazy during assembly")

            return stage

        return factory

    def test_dependency_profile_freezes_ingest_identity_and_locations(self):
        policy = validate_ingestion_dependencies(self.dependencies)
        self.assertEqual(policy.served_model, "nomic-ai/nomic-embed-text-v1.5")
        self.assertEqual(policy.embedding_endpoint.parsed.path, "/v1/embeddings")
        self.assertEqual(policy.tokenization_endpoint.parsed.path, "/tokenize")
        self.assertEqual(policy.database_name, "rag_catalog")
        self.assertEqual(policy.database_user, "rag_ingest")
        self.assertEqual(policy.database_credential_environment, "ISHIKAWA_POSTGRESQL_INGEST_PASSWORD")
        self.assertEqual(len(policy.digest), 64)

    def test_dependency_profile_rejects_secrets_and_wrong_database_role(self):
        secret = copy.deepcopy(self.dependencies)
        secret["postgresql"]["password"] = "forbidden"
        wrong_role = copy.deepcopy(self.dependencies)
        wrong_role["postgresql"]["database_user"] = "rag_retrieval"
        for candidate in (secret, wrong_role):
            with self.subTest(candidate=candidate), self.assertRaises(
                IngestionRuntimeConfigurationError
            ):
                validate_ingestion_dependencies(candidate)

    def test_connection_factory_reads_password_only_when_called(self):
        reads = []

        class Environment(dict):
            def __getitem__(self, key):
                reads.append(key)
                return super().__getitem__(key)

        parameters = []
        policy = validate_ingestion_dependencies(self.dependencies)
        deployment = __import__(
            "ishikawa.deployment", fromlist=["validate_deployment_profile"]
        ).validate_deployment_profile(
            load_restricted_yaml(self.runtime_config / "deployment.yaml", label="deployment")
        )
        factory = NativeIngestionConnectionFactory(
            deployment.postgresql,
            policy,
            ProtectedEnvironmentValue(
                "ISHIKAWA_POSTGRESQL_INGEST_PASSWORD",
                Environment(ISHIKAWA_POSTGRESQL_INGEST_PASSWORD="secret"),
            ),
            lambda **values: parameters.append(values) or object(),
        )
        self.assertEqual(reads, [])
        factory()
        self.assertEqual(reads, ["ISHIKAWA_POSTGRESQL_INGEST_PASSWORD"])
        self.assertEqual(parameters[0]["user"], "rag_ingest")
        self.assertEqual(parameters[0]["application_name"], "ishikawa-ingestion")
        self.assertIs(parameters[0]["autocommit"], True)
        self.assertNotIn("options", parameters[0])

    def test_assembly_is_lazy_and_uses_native_document_producer(self):
        environment_reads = []

        class Environment(dict):
            def __getitem__(self, key):
                environment_reads.append(key)
                return super().__getitem__(key)

        connections = []
        factories = []
        runtime = assemble_configured_ingestion_runtime(
            self.paths,
            runtime_config_root=self.runtime_config,
            work_root=self.work,
            artifact_stage_factory=self.stage_factory(factories),
            artifact_retainer=lambda _bundle: None,
            environment=Environment(),
            database_connector=lambda **values: connections.append(values),
        )
        self.assertIsInstance(runtime, ConfiguredIngestionRuntime)
        self.assertIsInstance(runtime.ports.producer, NativeDocumentProducer)
        self.assertIsNotNone(runtime.ports.relationship_registry)
        self.assertEqual(
            runtime.policy.relationship_registry_digest,
            runtime.ports.relationship_registry.digest,
        )
        self.assertEqual(len(factories), 1)
        self.assertEqual(environment_reads, [])
        self.assertEqual(connections, [])
        self.assertEqual(runtime.policy.dependencies.database_user, "rag_ingest")
        self.assertEqual(len(runtime.policy.digest), 64)

    def test_runtime_rejects_unknown_mode_before_dependencies(self):
        runtime = assemble_configured_ingestion_runtime(
            self.paths,
            runtime_config_root=self.runtime_config,
            work_root=self.work,
            artifact_stage_factory=self.stage_factory([]),
            artifact_retainer=lambda _bundle: None,
            environment={},
            database_connector=lambda **_values: self.fail("connector called"),
        )
        with self.assertRaises(IngestionRuntimeConfigurationError):
            runtime.execute("remove", output=__import__("io").StringIO())

    def test_assembly_rejects_unsafe_work_root_and_invalid_stage(self):
        missing = Path(self.temporary.name) / "missing"
        with self.assertRaises(IngestionRuntimeConfigurationError):
            assemble_configured_ingestion_runtime(
                self.paths,
                runtime_config_root=self.runtime_config,
                work_root=missing,
                artifact_stage_factory=self.stage_factory([]),
                artifact_retainer=lambda _bundle: None,
            )

        def invalid_factory(_policy, _credential):
            return None

        with self.assertRaises(IngestionRuntimeConfigurationError):
            assemble_configured_ingestion_runtime(
                self.paths,
                runtime_config_root=self.runtime_config,
                work_root=self.work,
                artifact_stage_factory=invalid_factory,
                artifact_retainer=lambda _bundle: None,
            )


if __name__ == "__main__":
    unittest.main()
