#!/usr/bin/env python3
"""Run one source-tree Ishikawa ingestion mode for the local tuning corpus."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path


def _directory(environment_name: str) -> Path:
    value = os.environ.get(environment_name, "")
    path = Path(value)
    if not value or not path.is_absolute() or path.is_symlink() or not path.is_dir():
        raise ValueError(f"{environment_name.lower()}_unsafe")
    return path.resolve(strict=True)


def main() -> int:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--mode", choices=("validate-only", "publish"), required=True)
    arguments = parser.parse_args()

    script_path = Path(__file__).resolve(strict=True)
    phase_root = script_path.parent.parent
    repository_root = phase_root.parent
    product_root = phase_root / "Ishikawa"
    python_root = product_root / "application" / "python"
    sys.path.insert(0, str(python_root.resolve(strict=True)))

    from ishikawa.ingestion_runtime import assemble_configured_ingestion_runtime
    from ishikawa.installed_ingestion import ContentAddressedArtifactRetainer
    from ishikawa.live_document_stage import NativeLiveDocumentArtifactStageFactory
    from ishikawa.operator_ingestion import OperatorIngestionPaths

    operator_root = product_root / "tests" / "fixtures" / "pipeline_writer"
    source_root = (
        repository_root
        / "local"
        / "artifacts"
        / "org_lab"
        / "synthetic_corpus_v1"
        / "anderson-upload"
    )
    report_root = _directory("ISHIKAWA_LOCAL_INGESTION_REPORT_ROOT")
    work_root = _directory("ISHIKAWA_LOCAL_INGESTION_WORK_ROOT")
    artifact_root = _directory("ISHIKAWA_LOCAL_INGESTION_ARTIFACT_ROOT")

    paths = OperatorIngestionPaths(
        (operator_root / "document_classes.yaml").resolve(strict=True),
        (operator_root / "document_catalog.yaml").resolve(strict=True),
        (operator_root / "ingestion_manifest.yaml").resolve(strict=True),
        source_root.resolve(strict=True),
        report_root,
    )
    runtime = assemble_configured_ingestion_runtime(
        paths,
        runtime_config_root=(product_root / "config" / "templates").resolve(strict=True),
        work_root=work_root,
        artifact_stage_factory=NativeLiveDocumentArtifactStageFactory(
            (script_path.parent / "ishikawa-produce-artifacts").resolve(strict=True)
        ),
        artifact_retainer=ContentAddressedArtifactRetainer(artifact_root),
        environment=os.environ,
    )
    return runtime.execute(arguments.mode, output=sys.stdout)


if __name__ == "__main__":
    raise SystemExit(main())
