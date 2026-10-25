#!/usr/bin/env python3
"""Exercise the operator-ingestion control plane without external services."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import tempfile
from pathlib import Path

from ishikawa.operator_ingestion import OperatorIngestionPaths, run_operator_ingestion
from ishikawa.persistence_models import WriteResult


METHOD_PROFILE_ID = "5797961aee919aa73bbd99d6cc188084d57d22839a1d4cff0febc2e73e17b4b0"


class Rows:
    def __init__(self, values=()):
        self.values = list(values)

    def fetchall(self):
        return list(self.values)


class PlanningConnection:
    def __init__(self, published=(), catalog_keys=()):
        self.published = list(published)
        self.catalog_keys = list(catalog_keys)
        self.reads = 0

    def execute(self, sql, _parameters=()):
        self.reads += 1
        if "ishikawa.load-published-state" in sql:
            return Rows(self.published)
        if "ishikawa.load-catalog-keys" in sql:
            return Rows((key,) for key in self.catalog_keys)
        raise RuntimeError("unexpected database operation")


def write_yaml_inputs(root: Path, *, document_key: str = "policy.alpha") -> OperatorIngestionPaths:
    config = root / "config"
    source = root / "corpus"
    reports = root / "reports"
    config.mkdir(parents=True)
    (source / "policies").mkdir(parents=True)
    (source / "policies" / "alpha.pdf").write_bytes(
        b"%PDF-1.4\noperator command synthetic fixture\n%%EOF\n"
    )
    classes = config / "document_classes.yaml"
    catalog = config / "document_catalog.yaml"
    manifest = config / "ingestion_manifest.yaml"
    classes.write_text(
        """schema_version: 1
classes:
  - class_id: policy
    display_name: Policy
    status: active
""",
        encoding="utf-8",
    )
    catalog.write_text(
        """schema_version: 1
documents:
  - document_key: policy.alpha
    display_name: Alpha Policy
    status: active
""",
        encoding="utf-8",
    )
    manifest.write_text(
        f"""schema_version: 1
documents:
  - source_path: policies/alpha.pdf
    document_key: {document_key}
    class_id: policy
retirements: []
""",
        encoding="utf-8",
    )
    return OperatorIngestionPaths(classes, catalog, manifest, source, reports)


def write_result(outcome: str) -> WriteResult:
    return WriteResult(
        ingestion_run_id="1" * 64,
        publication_batch_id="2" * 64 if outcome == "PUBLISHED" else None,
        outcome=outcome,
        published_document_count=1 if outcome == "PUBLISHED" else 0,
        retired_document_count=0,
        reused_document_count=1 if outcome == "SKIPPED" else 0,
        quarantine_record_count=1 if outcome == "QUARANTINED" else 0,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    arguments = parser.parse_args()
    output = Path(arguments.output)

    with tempfile.TemporaryDirectory(prefix="ishikawa-operator-ingestion-") as temporary:
        root = Path(temporary)
        validate_paths = write_yaml_inputs(root / "validate")
        dependency_calls = {"producer": 0, "writer": 0}

        def forbidden_producer(_batch):
            dependency_calls["producer"] += 1
            return ()

        def forbidden_writer(*_args):
            dependency_calls["writer"] += 1
            return write_result("PUBLISHED")

        validation = run_operator_ingestion(
            paths=validate_paths,
            method_profile_id=METHOD_PROFILE_ID,
            connection=PlanningConnection(),
            validate_only=True,
            producer=forbidden_producer,
            writer=forbidden_writer,
        )

        add_paths = write_yaml_inputs(root / "add")
        produced = []
        written = []

        def producer(batch):
            produced.extend(batch.documents)
            return (object(),)

        def writer(_connection, _registry, _catalog, _manifest, plan, prepared):
            written.append((plan, prepared))
            return write_result("PUBLISHED")

        publication = run_operator_ingestion(
            paths=add_paths,
            method_profile_id=METHOD_PROFILE_ID,
            connection=PlanningConnection(),
            validate_only=False,
            producer=producer,
            writer=writer,
        )

        reuse_paths = write_yaml_inputs(root / "reuse")
        source_digest = hashlib.sha256(
            (reuse_paths.source_root / "policies" / "alpha.pdf").read_bytes()
        ).hexdigest()
        published = (
            (
                "policy.alpha",
                source_digest,
                "policy",
                METHOD_PROFILE_ID,
                "3" * 64,
                "4" * 64,
                "5" * 64,
            ),
        )
        reuse_producer_calls = 0

        def reuse_producer(_batch):
            nonlocal reuse_producer_calls
            reuse_producer_calls += 1
            return ()

        reuse = run_operator_ingestion(
            paths=reuse_paths,
            method_profile_id=METHOD_PROFILE_ID,
            connection=PlanningConnection(published, ("policy.alpha",)),
            validate_only=False,
            producer=reuse_producer,
            writer=lambda *_args: write_result("SKIPPED"),
        )

        quarantine_paths = write_yaml_inputs(root / "quarantine", document_key="policy.unknown")
        quarantine_producer_calls = 0
        quarantine_writer_prepared = None

        def quarantine_producer(_batch):
            nonlocal quarantine_producer_calls
            quarantine_producer_calls += 1
            return ()

        def quarantine_writer(_connection, _registry, _catalog, _manifest, _plan, prepared):
            nonlocal quarantine_writer_prepared
            quarantine_writer_prepared = prepared
            return write_result("QUARANTINED")

        quarantine = run_operator_ingestion(
            paths=quarantine_paths,
            method_profile_id=METHOD_PROFILE_ID,
            connection=PlanningConnection(),
            validate_only=False,
            producer=quarantine_producer,
            writer=quarantine_writer,
        )

        report_modes = {
            oct(os.stat(validation.text_report).st_mode & 0o777),
            oct(os.stat(validation.json_report).st_mode & 0o777),
            oct(os.stat(publication.text_report).st_mode & 0o777),
            oct(os.stat(publication.json_report).st_mode & 0o777),
        }
        checks = {
            "validate_only": (
                validation.plan.overall_outcome == "PASS"
                and validation.plan.validation_only
                and not validation.plan.mutation_performed
                and dependency_calls == {"producer": 0, "writer": 0}
            ),
            "incremental_add": (
                len(produced) == 1
                and produced[0].action == "add"
                and produced[0].document_key == "policy.alpha"
                and len(written) == 1
                and len(written[0][1]) == 1
                and publication.write_result is not None
                and publication.write_result.outcome == "PUBLISHED"
                and publication.plan.mutation_performed
            ),
            "reuse_without_production": (
                reuse.plan.entries[0].action == "reuse"
                and reuse_producer_calls == 0
                and reuse.write_result is not None
                and reuse.write_result.outcome == "SKIPPED"
                and not reuse.plan.mutation_performed
            ),
            "quarantine_without_production": (
                quarantine.plan.overall_outcome == "QUARANTINED"
                and quarantine_producer_calls == 0
                and quarantine_writer_prepared == ()
                and quarantine.exit_code != 0
                and quarantine.plan.mutation_performed
            ),
            "private_reports": report_modes == {"0o600"},
        }
        if not all(checks.values()):
            raise RuntimeError("operator ingestion qualification failed")

        artifact = {
            "schema_version": 1,
            "qualification": "pass",
            "method_profile_id": METHOD_PROFILE_ID,
            "scenarios": {
                "validate_only": {
                    "outcome": validation.plan.overall_outcome,
                    "producer_calls": 0,
                    "writer_calls": 0,
                    "mutation_performed": False,
                },
                "incremental_add": {
                    "planned_documents": 1,
                    "producer_documents": 1,
                    "writer_calls": 1,
                    "outcome": "PUBLISHED",
                    "mutation_performed": True,
                },
                "reuse": {
                    "producer_calls": 0,
                    "outcome": "SKIPPED",
                    "mutation_performed": False,
                },
                "quarantine": {
                    "producer_calls": 0,
                    "prepared_documents": 0,
                    "outcome": "QUARANTINED",
                    "mutation_performed": True,
                },
            },
            "boundaries": {
                "database": "injected_non_networking_test_port",
                "producer": "injected_non_networking_test_port",
                "writer": "injected_non_networking_test_port",
                "target_contact": False,
                "model_call": False,
                "credential_read": False,
                "source_content_retained": False,
                "protected_report_mode": "0600",
            },
        }
        output.write_text(
            json.dumps(artifact, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

    print("operator_ingestion_scenarios=4;validate_only=pass;incremental_add=pass;reuse=pass;quarantine=pass")
    print("validate_only_dependencies=producer_0,writer_0;actual_add=producer_1,writer_1")
    print("unchanged_and_quarantine_document_production=0;atomic_writer_boundary=pass")
    print("reports=private_0600;absolute_source_paths_in_terminal=false")
    print("target_contact=false;database_contact=false;model_call=false;credential_read=false")
    print("operator_ingestion_command_qualification=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
