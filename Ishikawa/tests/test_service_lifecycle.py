from __future__ import annotations

import unittest
from pathlib import Path


class RetrievalServiceLifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[1]
        cls.unit_path = root / "packaging/systemd/ishikawa-retrieval-api.service"
        cls.unit_text = cls.unit_path.read_text(encoding="utf-8")
        cls.stack_text = (root / "scripts/ishikawa-stack").read_text(encoding="utf-8")

    def test_unit_runs_exact_installed_foreground_command(self):
        self.assertIn("Type=simple", self.unit_text)
        self.assertIn("WorkingDirectory=%h/Documents/Ishikawa", self.unit_text)
        self.assertIn(
            "ExecStart=%h/Documents/Ishikawa/scripts/ishikawa-retrieval-api --serve",
            self.unit_text,
        )

    def test_unit_is_deliberately_boot_disabled(self):
        self.assertNotIn("[Install]", self.unit_text)
        self.assertNotIn("WantedBy=", self.unit_text)
        self.assertNotIn("RequiredBy=", self.unit_text)

    def test_unit_accepts_only_named_runtime_secret_environment(self):
        self.assertIn(
            "PassEnvironment=ISHIKAWA_GEMMA_API_KEY ISHIKAWA_NOMIC_API_KEY "
            "ISHIKAWA_POSTGRESQL_PASSWORD",
            self.unit_text,
        )
        self.assertNotIn("EnvironmentFile=", self.unit_text)
        self.assertNotIn("API_KEY=", self.unit_text)
        self.assertNotIn("PASSWORD=", self.unit_text)

    def test_unit_has_bounded_restart_shutdown_and_write_scope(self):
        for directive in (
            "Restart=on-failure",
            "RestartSec=2s",
            "TimeoutStopSec=20s",
            "KillSignal=SIGTERM",
            "UMask=0077",
            "NoNewPrivileges=yes",
            "ProtectHome=read-only",
            "ReadWritePaths=%h/Documents/Ishikawa/state/logs "
            "%h/Documents/Ishikawa/state/run",
        ):
            self.assertIn(directive, self.unit_text)

    def test_stack_runs_component_readiness_before_importing_credentials(self):
        preflight = self.stack_text.index(
            '"$SCRIPT_DIR/ishikawa-retrieval-api" --check-readiness'
        )
        import_environment = self.stack_text.index(
            'systemctl --user import-environment "${SECRET_NAMES[@]}"'
        )
        self.assertLess(preflight, import_environment)
        self.assertIn("retrieval_readiness_preflight_failed", self.stack_text)

    def test_stack_rechecks_components_after_runtime_readiness_failure(self):
        self.assertEqual(self.stack_text.count("--check-readiness"), 2)
        self.assertIn("retrieval_readiness_failed_after_preflight", self.stack_text)


if __name__ == "__main__":
    unittest.main()
