from __future__ import annotations

import io
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from ishikawa.retrieval_command import (
    execute_installed_retrieval,
    run_foreground_retrieval_service,
)
from ishikawa.readiness import ConfiguredReadinessProbe
from ishikawa.observability import ConfiguredObservability
from ishikawa.runtime import assemble_configured_retrieval_runtime


class _StoppedServer:
    def __init__(self):
        self.serve_calls = 0
        self.shutdown_calls = 0
        self.close_calls = 0

    def serve_forever(self, *, poll_interval):
        self.serve_calls += 1
        if poll_interval != 0.2:
            raise AssertionError("unexpected polling interval")

    def shutdown(self):
        self.shutdown_calls += 1

    def server_close(self):
        self.close_calls += 1


class RetrievalCommandTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path(__file__).resolve().parents[1]
        cls.config_root = cls.root / "config/templates"
        cls.runtime = assemble_configured_retrieval_runtime(cls.config_root, environment={})

    def product_root(self, temporary_root: str) -> Path:
        root = Path(temporary_root) / "Ishikawa"
        (root / "config").mkdir(parents=True)
        (root / "state/logs").mkdir(parents=True)
        (root / "state/run").mkdir(parents=True)
        return root

    def test_check_config_reads_no_credential_and_contacts_no_dependency(self):
        calls = []

        def assemble(config_root, *, environment):
            calls.append((config_root.name, dict(environment)))
            return self.runtime

        with tempfile.TemporaryDirectory() as temporary_root:
            output = io.StringIO()
            result = execute_installed_retrieval(
                ["--check-config"],
                product_root=self.product_root(temporary_root),
                output=output,
                environment={},
                runtime_assembler=assemble,
            )
        self.assertEqual(result, 0)
        self.assertEqual(calls, [("config", {})])
        self.assertIn("ishikawa_retrieval_api_configuration=pass;", output.getvalue())
        self.assertIn("credential_read=false;dependency_contact=false", output.getvalue())

    def test_serve_uses_assembled_runtime_and_explicit_runner(self):
        runner_calls = []

        def assemble(_config_root, *, environment):
            self.assertEqual(dict(environment), {})
            return self.runtime

        readiness_probe = ConfiguredReadinessProbe(
            lambda: True,
            lambda: True,
            lambda: False,
            lambda: True,
            lambda: True,
        )

        def assemble_readiness(_product_root, runtime, *, environment):
            self.assertIs(runtime, self.runtime)
            self.assertEqual(dict(environment), {})
            return readiness_probe

        observability = object()

        def assemble_observability(_product_root, policy):
            self.assertIs(policy, self.runtime.policies.logging)
            return observability

        def run(runtime, probe, observed, output):
            runner_calls.append((runtime, probe, observed))
            output.write("test_runner=pass\n")
            return 0

        with tempfile.TemporaryDirectory() as temporary_root:
            output = io.StringIO()
            result = execute_installed_retrieval(
                ["--serve"],
                product_root=self.product_root(temporary_root),
                output=output,
                environment={},
                runtime_assembler=assemble,
                readiness_assembler=assemble_readiness,
                observability_assembler=assemble_observability,
                service_runner=run,
            )
        self.assertEqual(result, 0)
        self.assertEqual(runner_calls, [(self.runtime, readiness_probe, observability)])
        self.assertEqual(output.getvalue(), "test_runner=pass\n")

    def test_check_readiness_names_failed_components_without_private_detail(self):
        probe = ConfiguredReadinessProbe(
            lambda: True,
            lambda: True,
            lambda: False,
            lambda: (_ for _ in ()).throw(RuntimeError("private")),
            lambda: True,
        )

        with tempfile.TemporaryDirectory() as temporary_root:
            output = io.StringIO()
            result = execute_installed_retrieval(
                ["--check-readiness"],
                product_root=self.product_root(temporary_root),
                output=output,
                environment={},
                runtime_assembler=lambda *_args, **_kwargs: self.runtime,
                readiness_assembler=lambda *_args, **_kwargs: probe,
            )
        self.assertEqual(result, 1)
        self.assertEqual(
            output.getvalue(),
            "ishikawa_retrieval_api_readiness=blocked;"
            "configuration=pass;storage=pass;postgresql=blocked;"
            "gemma=blocked;nomic=pass\n",
        )
        self.assertNotIn("private", output.getvalue())

    def test_invalid_arguments_fail_before_runtime_assembly(self):
        calls = []
        with tempfile.TemporaryDirectory() as temporary_root:
            output = io.StringIO()
            result = execute_installed_retrieval(
                ["--config", "private-path"],
                product_root=self.product_root(temporary_root),
                output=output,
                runtime_assembler=lambda *_args, **_kwargs: calls.append("called"),
            )
        self.assertEqual(result, 2)
        self.assertEqual(calls, [])
        self.assertEqual(
            output.getvalue(),
            "ishikawa_retrieval_api=blocked;reason=arguments_invalid\n",
        )

    def test_foreground_runner_closes_a_naturally_stopped_listener(self):
        server = _StoppedServer()
        with tempfile.TemporaryDirectory() as temporary_root:
            product_root = self.product_root(temporary_root)
            observability = ConfiguredObservability(
                self.runtime.policies.logging,
                product_root / "state/logs",
                control_root=product_root / "state/run",
            )
            output = io.StringIO()
            with patch.object(type(self.runtime), "create_http_server", return_value=server):
                result = run_foreground_retrieval_service(
                    self.runtime,
                    lambda: False,
                    observability,
                    output,
                    install_signal_handlers=False,
                )
        self.assertEqual(result, 0)
        self.assertEqual(server.serve_calls, 1)
        self.assertEqual(server.shutdown_calls, 0)
        self.assertEqual(server.close_calls, 1)
        self.assertIn("ishikawa_retrieval_api=started;", output.getvalue())
        self.assertIn("ishikawa_retrieval_api=stopped;cleanup=complete", output.getvalue())


if __name__ == "__main__":
    unittest.main()
