from __future__ import annotations

import copy
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path

from ishikawa.readiness import (
    ActiveCorpusProbe,
    ConfiguredReadinessProbe,
    HealthEndpoint,
    HealthHTTPResponse,
    NativeHealthProbe,
    ReadinessInspection,
    ReadinessContractError,
    WarmedNomicProbe,
    assemble_configured_readiness_probe,
    prepare_health_request,
)
from ishikawa.native_adapters import ACCEPTED_EMBEDDING_SPACE_ID, ValidatedQueryEmbedding
from ishikawa.runtime import assemble_configured_retrieval_runtime, validate_runtime_dependencies
from ishikawa.yaml_loader import load_restricted_yaml


class _Result:
    def __init__(self, row):
        self.row = row

    def fetchone(self):
        return self.row


class _Connection:
    def __init__(self, row):
        self.row = row
        self.calls = []
        self.rolled_back = False
        self.closed = False

    def execute(self, statement):
        self.calls.append(statement)
        return _Result(self.row)

    def rollback(self):
        self.rolled_back = True

    def close(self):
        self.closed = True


class ReadinessTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path(__file__).resolve().parents[1]
        cls.config_root = cls.root / "config/templates"
        cls.runtime = assemble_configured_retrieval_runtime(cls.config_root, environment={})

    def test_health_endpoint_and_request_keep_credential_out_of_url(self):
        endpoint = HealthEndpoint.from_url(
            "http://127.0.0.1:8000/health",
            timeout_seconds=30,
        )
        prepared = prepare_health_request(endpoint, "runtime-secret")
        self.assertEqual(endpoint.scheme, "http")
        self.assertEqual(endpoint.host, "127.0.0.1")
        self.assertEqual(endpoint.path, "/health")
        self.assertEqual(prepared.headers["Authorization"], "Bearer runtime-secret")
        self.assertNotIn("runtime-secret", repr(endpoint))

    def test_health_endpoint_rejects_credentials_query_and_wrong_path(self):
        for url in (
            "http://user:secret@127.0.0.1:8000/health",
            "http://127.0.0.1:8000/health?detail=true",
            "http://127.0.0.1:8000/v1/models",
        ):
            with self.subTest(url=url), self.assertRaises(ReadinessContractError):
                HealthEndpoint.from_url(url, timeout_seconds=30)

    def test_runtime_health_endpoint_must_share_service_origin(self):
        raw = load_restricted_yaml(
            self.config_root / "runtime_dependencies.yaml",
            label="runtime dependencies",
        )
        accepted = validate_runtime_dependencies(raw)
        self.assertEqual(
            accepted.generation_health_endpoint_url,
            "http://127.0.0.1:8000/health",
        )
        invalid = copy.deepcopy(raw)
        invalid["gemma"]["health_endpoint_url"] = "http://127.0.0.1:8001/health"
        with self.assertRaisesRegex(ValueError, "Gemma health endpoint"):
            validate_runtime_dependencies(invalid)

    def test_active_corpus_requires_read_only_retrieval_role_and_one_chunk(self):
        accepted_connection = _Connection(("rag_retrieval", "on", True))
        self.assertTrue(ActiveCorpusProbe(lambda: accepted_connection)())
        self.assertTrue(accepted_connection.rolled_back)
        self.assertTrue(accepted_connection.closed)
        self.assertIn("rag_search.active_chunks", accepted_connection.calls[0])

        for row in (
            ("rag_retrieval", "on", False),
            ("rag_owner", "on", True),
            ("rag_retrieval", "off", True),
        ):
            with self.subTest(row=row):
                connection = _Connection(row)
                self.assertFalse(ActiveCorpusProbe(lambda: connection)())
                self.assertTrue(connection.closed)

    def test_composite_probe_runs_every_component_and_requires_all(self):
        calls = []

        def component(name, result):
            def probe():
                calls.append(name)
                if isinstance(result, Exception):
                    raise result
                return result

            return probe

        probe = ConfiguredReadinessProbe(
            component("configuration", True),
            component("storage", True),
            component("database", False),
            component("gemma", RuntimeError("private")),
            component("nomic", True),
        )
        inspection = probe.inspect()
        self.assertFalse(inspection.ready)
        self.assertEqual(calls, ["configuration", "storage", "database", "gemma", "nomic"])
        self.assertEqual(
            inspection.marker(),
            "ishikawa_retrieval_api_readiness=blocked;"
            "configuration=pass;storage=pass;postgresql=blocked;"
            "gemma=blocked;nomic=pass",
        )
        calls.clear()
        self.assertFalse(probe())
        self.assertEqual(calls, ["configuration", "storage", "database", "gemma", "nomic"])
        calls.clear()
        self.assertEqual(
            probe.inspect_dependencies(),
            (("gemma", False), ("nomic", True)),
        )
        self.assertEqual(calls, ["gemma", "nomic"])

    def test_readiness_inspection_rejects_unknown_or_non_boolean_states(self):
        for components in (
            (("configuration", True),),
            (
                ("configuration", True),
                ("storage", True),
                ("postgresql", 1),
                ("gemma", True),
                ("nomic", True),
            ),
        ):
            with self.subTest(components=components), self.assertRaises(
                ReadinessContractError
            ):
                ReadinessInspection(components)

    def test_assembly_is_lazy_and_complete_probe_can_be_ready(self):
        environment_reads = []

        class Environment(dict):
            def __getitem__(self, key):
                environment_reads.append(key)
                return super().__getitem__(key)

        environment = Environment(
            {
                "ISHIKAWA_GEMMA_API_KEY": "gemma-secret",
                "ISHIKAWA_NOMIC_API_KEY": "nomic-secret",
                "ISHIKAWA_POSTGRESQL_PASSWORD": "database-secret",
            }
        )
        database_connections = []
        health_requests = []
        warmup_queries = []

        def connect(**parameters):
            database_connections.append(parameters)
            return _Connection(("rag_retrieval", "on", True))

        def health_exchange(request):
            health_requests.append(request)
            return HealthHTTPResponse(200, 0)

        with tempfile.TemporaryDirectory() as temporary_root:
            product_root = Path(temporary_root) / "Ishikawa"
            config_root = product_root / "config"
            state_root = product_root / "state/logs"
            config_root.mkdir(parents=True)
            state_root.mkdir(parents=True)
            (product_root / "state/run").mkdir(parents=True)
            for source in self.config_root.glob("*.yaml"):
                (config_root / source.name).write_bytes(source.read_bytes())
            runtime = assemble_configured_retrieval_runtime(config_root, environment=environment)
            runtime = replace(
                runtime,
                query_embedder=lambda query: (
                    warmup_queries.append(query)
                    or ValidatedQueryEmbedding(
                        tuple([0.0] * 768),
                        5,
                        ACCEPTED_EMBEDDING_SPACE_ID,
                        "7" * 64,
                    )
                ),
            )
            probe = assemble_configured_readiness_probe(
                product_root,
                runtime,
                environment=environment,
                database_connector=connect,
                health_exchange=health_exchange,
            )
            self.assertEqual(environment_reads, [])
            self.assertEqual(database_connections, [])
            self.assertEqual(health_requests, [])
            self.assertTrue(probe())
        self.assertEqual(
            environment_reads,
            [
                "ISHIKAWA_POSTGRESQL_PASSWORD",
                "ISHIKAWA_GEMMA_API_KEY",
                "ISHIKAWA_NOMIC_API_KEY",
            ],
        )
        self.assertEqual(len(database_connections), 1)
        self.assertEqual(len(health_requests), 2)
        self.assertEqual(warmup_queries, ["Ishikawa readiness warmup"])
        self.assertEqual(database_connections[0]["application_name"], "ishikawa-retrieval-api")
        self.assertEqual(database_connections[0]["options"], "-c default_transaction_read_only=on")
        self.assertEqual(
            [request.endpoint.path for request in health_requests],
            ["/health", "/health"],
        )

    def test_nomic_warmup_runs_once_while_health_is_checked_each_time(self):
        health_calls = []
        warmup_queries = []
        probe = WarmedNomicProbe(
            lambda: health_calls.append(True) or True,
            lambda query: (
                warmup_queries.append(query)
                or ValidatedQueryEmbedding(
                    tuple([0.0] * 768),
                    5,
                    ACCEPTED_EMBEDDING_SPACE_ID,
                    "8" * 64,
                )
            ),
        )
        self.assertTrue(probe())
        self.assertTrue(probe())
        self.assertEqual(health_calls, [True, True])
        self.assertEqual(warmup_queries, ["Ishikawa readiness warmup"])

    def test_health_probe_fails_closed_without_exposing_exception(self):
        probe = NativeHealthProbe(
            HealthEndpoint.from_url(
                "http://127.0.0.1:8001/health",
                timeout_seconds=30,
            ),
            lambda: "runtime-secret",
            lambda _request: (_ for _ in ()).throw(RuntimeError("private detail")),
        )
        self.assertFalse(probe())


if __name__ == "__main__":
    unittest.main()
