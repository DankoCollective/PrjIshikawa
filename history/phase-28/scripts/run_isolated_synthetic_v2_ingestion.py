#!/usr/bin/env python3
"""Run the qualified synthetic-corpus-v2 bundle through Ishikawa ingestion.

Script 168 owns this helper.  The helper keeps the application ingestion
assembly intact while supplying an isolated operator bundle, runtime config,
work lane, report lane, and artifact-retention lane.  PostgreSQL and Nomic
credentials remain protected environment values consumed by the accepted
runtime; they are never accepted as command-line arguments.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path


def _directory(value: str, label: str) -> Path:
    path = Path(value)
    if not path.is_absolute() or path.is_symlink() or not path.is_dir():
        raise ValueError(f"{label}_unsafe")
    return path.resolve(strict=True)


def _file(value: str, label: str, *, executable: bool = False) -> Path:
    path = Path(value)
    if (
        not path.is_absolute()
        or path.is_symlink()
        or not path.is_file()
        or (executable and not os.access(path, os.X_OK))
    ):
        raise ValueError(f"{label}_unsafe")
    return path.resolve(strict=True)


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--mode", choices=("validate-only", "publish"), required=True)
    parser.add_argument("--product-root", required=True)
    parser.add_argument("--promotion-bundle", required=True)
    parser.add_argument("--runtime-config-root", required=True)
    parser.add_argument("--work-root", required=True)
    parser.add_argument("--report-root", required=True)
    parser.add_argument("--artifact-root", required=True)
    parser.add_argument("--pipeline-executable", required=True)
    return parser.parse_args()


def main() -> int:
    """Assemble and execute one isolated v2 validation or publication."""

    arguments = _arguments()
    product_root = _directory(arguments.product_root, "product_root")
    promotion_bundle = _directory(arguments.promotion_bundle, "promotion_bundle")
    runtime_config_root = _directory(
        arguments.runtime_config_root, "runtime_config_root"
    )
    work_root = _directory(arguments.work_root, "work_root")
    report_root = _directory(arguments.report_root, "report_root")
    artifact_root = _directory(arguments.artifact_root, "artifact_root")
    pipeline_executable = _file(
        arguments.pipeline_executable, "pipeline_executable", executable=True
    )

    python_root = _directory(
        str(product_root / "application" / "python"), "python_root"
    )
    sys.path.insert(0, str(python_root))

    from ishikawa.ingestion_runtime import (  # pylint: disable=import-outside-toplevel
        assemble_configured_ingestion_runtime,
    )
    from ishikawa.installed_ingestion import (  # pylint: disable=import-outside-toplevel
        ContentAddressedArtifactRetainer,
    )
    from ishikawa.live_document_stage import (  # pylint: disable=import-outside-toplevel
        NativeLiveDocumentArtifactStageFactory,
    )
    from ishikawa.operator_ingestion import (  # pylint: disable=import-outside-toplevel
        OperatorIngestionPaths,
    )

    config_root = _directory(str(promotion_bundle / "config"), "bundle_config_root")
    source_root = _directory(str(promotion_bundle / "source"), "bundle_source_root")
    paths = OperatorIngestionPaths(
        _file(str(config_root / "document_classes.yaml"), "document_class_registry"),
        _file(str(config_root / "document_catalog.yaml"), "document_catalog"),
        _file(str(config_root / "ingestion_manifest.yaml"), "ingestion_manifest"),
        source_root,
        report_root,
    )
    runtime = assemble_configured_ingestion_runtime(
        paths,
        runtime_config_root=runtime_config_root,
        work_root=work_root,
        artifact_stage_factory=NativeLiveDocumentArtifactStageFactory(
            pipeline_executable
        ),
        artifact_retainer=ContentAddressedArtifactRetainer(artifact_root),
        environment=os.environ,
    )
    return runtime.execute(arguments.mode, output=sys.stdout)


if __name__ == "__main__":
    raise SystemExit(main())
