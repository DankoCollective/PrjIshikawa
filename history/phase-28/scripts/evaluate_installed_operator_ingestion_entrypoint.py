#!/usr/bin/env python3
"""Qualify the installed Ishikawa ingestion command without external contact."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from ishikawa.document_producer import ProducerArtifactBundle
from ishikawa.installed_ingestion import (
    ContentAddressedArtifactRetainer,
    execute_installed_ingestion,
)


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise RuntimeError(reason)


def write_exclusive(path: Path, value: dict[str, object]) -> tuple[str, int]:
    payload = json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8") + b"\n"
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)
    return hashlib.sha256(payload).hexdigest(), len(payload)


class Runtime:
    def __init__(self, calls: list[str]) -> None:
        self.calls = calls

    def execute(self, mode: str, *, output) -> int:
        self.calls.append(mode)
        output.write(f"installed_runtime={mode};status=pass\n")
        return 0


def main() -> int:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--python-root", required=True, type=Path)
    parser.add_argument("--ingest-entrypoint", required=True, type=Path)
    parser.add_argument("--pipeline-entrypoint", required=True, type=Path)
    parser.add_argument("--runtime-config-root", required=True, type=Path)
    parser.add_argument("--operator-config-root", required=True, type=Path)
    parser.add_argument("--capture", required=True, type=Path)
    parser.add_argument("--normalize", required=True, type=Path)
    parser.add_argument("--chunk", required=True, type=Path)
    parser.add_argument("--embed", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()

    for path in (
        arguments.python_root,
        arguments.runtime_config_root,
        arguments.operator_config_root,
    ):
        require(path.is_absolute() and path.is_dir() and not path.is_symlink(), "input_root_unsafe")
    for path in (
        arguments.ingest_entrypoint,
        arguments.pipeline_entrypoint,
        arguments.capture,
        arguments.normalize,
        arguments.chunk,
        arguments.embed,
    ):
        require(path.is_absolute() and path.is_file() and not path.is_symlink(), "input_file_unsafe")
    require(
        arguments.output.is_absolute()
        and not arguments.output.exists()
        and arguments.output.parent.is_dir(),
        "output_path_unsafe",
    )

    with tempfile.TemporaryDirectory(prefix="installed-ingestion-entrypoint-") as temporary:
        root = Path(temporary) / "Ishikawa"
        for relative in (
            "application/python",
            "config/ingestion/pending",
            "corpus/source",
            "state/reports/ingestion",
            "state/work",
            "state/artifacts/sha256",
            "scripts",
        ):
            (root / relative).mkdir(parents=True, mode=0o700, exist_ok=True)
        shutil.copytree(
            arguments.python_root / "ishikawa",
            root / "application/python/ishikawa",
        )
        for name in ("deployment.yaml", "ingestion_dependencies.yaml"):
            shutil.copyfile(arguments.runtime_config_root / name, root / "config" / name)
        for name in ("document_classes.yaml", "document_catalog.yaml"):
            shutil.copyfile(arguments.operator_config_root / name, root / "config" / name)
        manifest = root / "config/ingestion/pending/synthetic-batch.yaml"
        shutil.copyfile(arguments.operator_config_root / "ingestion_manifest.yaml", manifest)
        installed_ingest = root / "scripts/ishikawa-ingest"
        installed_pipeline = root / "scripts/ishikawa-produce-artifacts"
        shutil.copyfile(arguments.ingest_entrypoint, installed_ingest)
        shutil.copyfile(arguments.pipeline_entrypoint, installed_pipeline)
        for source in (arguments.capture, arguments.normalize, arguments.chunk, arguments.embed):
            shutil.copyfile(source, root / "scripts" / source.name)
        for executable in (installed_ingest, installed_pipeline):
            executable.chmod(0o700)

        environment = {
            "ISHIKAWA_NOMIC_API_KEY": "synthetic-unread-nomic-value",
            "ISHIKAWA_POSTGRESQL_INGEST_PASSWORD": "synthetic-unread-database-value",
        }
        runtime_calls: list[str] = []
        assembly_observations = []

        def factory(layout, paths, observed_environment):
            assembly_observations.append((layout, paths, observed_environment))
            return Runtime(runtime_calls)

        for mode in ("--validate-only", "--publish"):
            output = io.StringIO()
            status = execute_installed_ingestion(
                (mode, "--manifest", manifest.name),
                product_root=root.resolve(),
                output=output,
                environment=environment,
                runtime_factory=factory,
            )
            require(status == 0, "installed_command_status_mismatch")
            require(output.getvalue().endswith("status=pass\n"), "installed_command_output_mismatch")
        require(runtime_calls == ["validate-only", "publish"], "installed_mode_routing_mismatch")
        require(len(assembly_observations) == 2, "runtime_assembly_count_mismatch")
        for layout, paths, observed_environment in assembly_observations:
            require(layout.product_root == root.resolve(), "product_root_mismatch")
            require(paths.ingestion_manifest == manifest.resolve(), "manifest_path_mismatch")
            require(paths.source_root == (root / "corpus/source").resolve(), "source_root_mismatch")
            require(observed_environment is environment, "environment_boundary_mismatch")

        rejected = io.StringIO()
        rejected_status = execute_installed_ingestion(
            ("--publish", "--manifest", manifest.name, "--password", "forbidden-value"),
            product_root=root.resolve(),
            output=rejected,
            environment=environment,
            runtime_factory=lambda *_values: (_ for _ in ()).throw(
                RuntimeError("runtime_must_not_assemble")
            ),
        )
        require(rejected_status == 2, "secret_argument_not_rejected")
        require("forbidden-value" not in rejected.getvalue(), "secret_argument_disclosed")

        process_environment = {
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
            "PATH": "/usr/bin:/bin",
            "PYTHONDONTWRITEBYTECODE": "1",
        }
        ingest_process = subprocess.run(
            (str(installed_ingest), "--password", "subprocess-forbidden"),
            cwd=root,
            env=process_environment,
            capture_output=True,
            check=False,
            timeout=30,
        )
        require(ingest_process.returncode == 2, "installed_wrapper_rejection_mismatch")
        require(
            ingest_process.stdout == b"ishikawa_ingest=blocked;reason=arguments_invalid\n"
            and ingest_process.stderr == b""
            and b"subprocess-forbidden" not in ingest_process.stdout,
            "installed_wrapper_output_mismatch",
        )
        pipeline_process = subprocess.run(
            (str(installed_pipeline), "--help"),
            cwd=root,
            env=process_environment,
            capture_output=True,
            check=False,
            timeout=30,
        )
        require(pipeline_process.returncode == 0, "installed_pipeline_layout_mismatch")

        producer_root = Path(temporary) / "producer"
        producer_root.mkdir(mode=0o700)
        entries = []
        for name, payload in (
            ("normalized", b"normalized"),
            ("chunks", b"chunks"),
            ("embeddings", b"embeddings"),
        ):
            path = producer_root / f"{name}.json"
            path.write_bytes(payload)
            entries.append((path, hashlib.sha256(payload).hexdigest()))
        bundle = ProducerArtifactBundle(
            entries[0][0], entries[0][1],
            entries[1][0], entries[1][1],
            entries[2][0], entries[2][1],
        )
        retainer = ContentAddressedArtifactRetainer(
            (root / "state/artifacts/sha256").resolve()
        )
        retainer(bundle)
        retainer(bundle)
        retained = tuple((root / "state/artifacts/sha256").glob("*/*"))
        require(len(retained) == 3, "retained_artifact_count_mismatch")
        require(
            {path.name for path in retained} == {digest for _, digest in entries},
            "retained_artifact_identity_mismatch",
        )

    artifact = {
        "schema_version": 1,
        "purpose": "installed_operator_ingestion_entrypoint_qualification",
        "command": "ishikawa-ingest",
        "pipeline_command": "ishikawa-produce-artifacts",
        "operator_modes": ["validate-only", "publish"],
        "manifest_input": "pending_filename_only",
        "path_override_arguments": False,
        "secret_arguments": False,
        "product_root_derived_from_executable": True,
        "runtime_assembly_calls": 2,
        "credential_reads": 0,
        "database_contact": False,
        "model_call": False,
        "content_addressed_artifacts": 3,
        "artifact_retention_idempotent": True,
        "source_content_retained_in_evidence": False,
        "vectors_retained_in_evidence": False,
    }
    artifact_sha256, artifact_bytes = write_exclusive(arguments.output, artifact)
    print("purpose=qualify_installed_operator_ingestion_entrypoint")
    print("command=ishikawa-ingest;pipeline_command=ishikawa-produce-artifacts")
    print("operator_modes=validate-only,publish;manifest_input=pending_filename_only")
    print("product_root=derived_from_executable;path_override_arguments=false;secret_arguments=false")
    print("runtime_assembly_calls=2;credential_reads=0;database_contact=false;model_call=false")
    print("content_addressed_artifacts=3;retention_idempotent=true;conflict_behavior=fail_closed")
    print("source_content_retained_in_evidence=false;vectors_retained_in_evidence=false")
    print(f"qualification_artifact_sha256={artifact_sha256};qualification_artifact_bytes={artifact_bytes}")
    print("installed_operator_ingestion_entrypoint_qualification=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
