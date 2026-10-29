"""Installed one-shot ingestion command for the Ishikawa host layout.

The operator chooses only a mode and one pending manifest filename.  All
filesystem locations come from the installed product root, while credentials
remain protected environment values consumed by the configured runtime.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import tempfile
import threading
import time
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any, TextIO

from .canonical import file_sha256
from .document_producer import ProducerArtifactBundle
from .ingestion_runtime import ConfiguredIngestionRuntime, assemble_configured_ingestion_runtime
from .ingestion_command import _safe_runtime_reason
from .live_document_stage import NativeLiveDocumentArtifactStageFactory
from .operator_ingestion import OperatorIngestionPaths


_MANIFEST_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,126}\.yaml")


class InstalledIngestionError(ValueError):
    """Stable, content-free failure at the installed command boundary."""


class _Parser(argparse.ArgumentParser):
    def error(self, _message: str) -> None:
        raise InstalledIngestionError("arguments_invalid")


def _required_directory(path: Path, label: str) -> Path:
    if not path.is_absolute() or path.is_symlink() or not path.is_dir():
        raise InstalledIngestionError(f"{label}_unsafe")
    return path.resolve(strict=True)


def _required_file(path: Path, label: str, *, executable: bool = False) -> Path:
    if (
        not path.is_absolute()
        or path.is_symlink()
        or not path.is_file()
        or (executable and not os.access(path, os.X_OK))
    ):
        raise InstalledIngestionError(f"{label}_unsafe")
    return path.resolve(strict=True)


@dataclass(frozen=True, slots=True)
class InstalledIngestionLayout:
    """Validated paths owned by one installed Ishikawa product root."""

    product_root: Path
    runtime_config_root: Path
    class_registry: Path
    document_catalog: Path
    pending_manifest_root: Path
    source_root: Path
    report_root: Path
    work_root: Path
    artifact_root: Path
    pipeline_executable: Path

    @classmethod
    def from_product_root(cls, product_root: str | Path) -> "InstalledIngestionLayout":
        root = _required_directory(Path(product_root), "product_root")
        config = _required_directory(root / "config", "config_root")
        pending = _required_directory(config / "ingestion" / "pending", "pending_manifest_root")
        source = _required_directory(root / "corpus" / "source", "source_root")
        reports = _required_directory(root / "state" / "reports" / "ingestion", "report_root")
        work = _required_directory(root / "state" / "work", "work_root")
        artifacts = _required_directory(root / "state" / "artifacts" / "sha256", "artifact_root")
        return cls(
            root,
            config,
            _required_file(config / "document_classes.yaml", "class_registry"),
            _required_file(config / "document_catalog.yaml", "document_catalog"),
            pending,
            source,
            reports,
            work,
            artifacts,
            _required_file(
                root / "scripts" / "ishikawa-produce-artifacts",
                "pipeline_executable",
                executable=True,
            ),
        )

    def manifest(self, name: str) -> Path:
        if not isinstance(name, str) or _MANIFEST_NAME.fullmatch(name) is None:
            raise InstalledIngestionError("manifest_name_invalid")
        return _required_file(self.pending_manifest_root / name, "ingestion_manifest")


@dataclass(frozen=True, slots=True)
class ContentAddressedArtifactRetainer:
    """Retain verified pipeline artifacts once under their SHA-256 identity."""

    root: Path

    def __post_init__(self) -> None:
        object.__setattr__(self, "root", _required_directory(self.root, "artifact_root"))

    @staticmethod
    def _validate_source(path: Path, digest: str) -> None:
        if (
            not isinstance(digest, str)
            or re.fullmatch(r"[0-9a-f]{64}", digest) is None
            or path.is_symlink()
            or not path.is_file()
            or file_sha256(str(path)) != digest
        ):
            raise InstalledIngestionError("retention_source_invalid")

    def _retain_one(self, source: Path, digest: str) -> None:
        self._validate_source(source, digest)
        directory = self.root / digest[:2]
        if directory.exists():
            directory = _required_directory(directory, "artifact_digest_directory")
        else:
            directory.mkdir(mode=0o700)
        destination = directory / digest
        if destination.exists():
            if (
                destination.is_symlink()
                or not destination.is_file()
                or file_sha256(str(destination)) != digest
            ):
                raise InstalledIngestionError("retained_artifact_conflict")
            return

        descriptor, temporary_name = tempfile.mkstemp(prefix=f".{digest}.", dir=directory)
        temporary = Path(temporary_name)
        try:
            with os.fdopen(descriptor, "wb") as output, source.open("rb") as input_stream:
                os.chmod(temporary, 0o600)
                shutil.copyfileobj(input_stream, output)
                output.flush()
                os.fsync(output.fileno())
            if file_sha256(str(temporary)) != digest:
                raise InstalledIngestionError("retained_artifact_identity_mismatch")
            try:
                os.link(temporary, destination)
            except FileExistsError:
                if (
                    destination.is_symlink()
                    or not destination.is_file()
                    or file_sha256(str(destination)) != digest
                ):
                    raise InstalledIngestionError("retained_artifact_conflict")
        finally:
            try:
                temporary.unlink()
            except FileNotFoundError:
                pass

    def __call__(self, bundle: ProducerArtifactBundle) -> None:
        if not isinstance(bundle, ProducerArtifactBundle):
            raise InstalledIngestionError("retention_bundle_invalid")
        for source, digest in (
            (bundle.normalized_path, bundle.normalized_sha256),
            (bundle.chunk_path, bundle.chunk_sha256),
            (bundle.embedding_path, bundle.embedding_sha256),
        ):
            self._retain_one(source, digest)


RuntimeFactory = Callable[
    [InstalledIngestionLayout, OperatorIngestionPaths, Mapping[str, str]],
    Any,
]


class _IngestionMilestoneStream:
    """Emit bounded operator progress without exposing nested stage output."""

    def __init__(self, output: TextIO, heartbeat_seconds: float) -> None:
        if heartbeat_seconds <= 0 or heartbeat_seconds > 300:
            raise InstalledIngestionError("heartbeat_interval_invalid")
        self._output = output
        self._heartbeat_seconds = heartbeat_seconds
        self._started = 0.0
        self._stopped = threading.Event()
        self._thread: threading.Thread | None = None

    def _emit(self, line: str) -> None:
        self._output.write(line + "\n")
        self._output.flush()

    def _heartbeat(self) -> None:
        while not self._stopped.wait(self._heartbeat_seconds):
            elapsed_seconds = max(1, int(time.monotonic() - self._started))
            self._emit(f"[INGEST] state=heartbeat;elapsed_seconds={elapsed_seconds}")

    def start(self, mode: str) -> None:
        self._started = time.monotonic()
        self._emit(f"[INGEST] state=start;mode={mode}")
        self._thread = threading.Thread(
            target=self._heartbeat,
            name="ishikawa-ingestion-heartbeat",
            daemon=True,
        )
        self._thread.start()

    def finish(self, exit_code: int, *, reason: str | None = None) -> None:
        self._stopped.set()
        if self._thread is not None:
            self._thread.join()
        state = "pass" if exit_code == 0 else "blocked"
        suffix = "" if reason is None else f";reason={reason}"
        self._emit(f"[INGEST] state={state};exit_code={exit_code}{suffix}")


def build_installed_runtime(
    layout: InstalledIngestionLayout,
    paths: OperatorIngestionPaths,
    environment: Mapping[str, str],
) -> ConfiguredIngestionRuntime:
    """Assemble the accepted native runtime for one installed invocation."""

    return assemble_configured_ingestion_runtime(
        paths,
        runtime_config_root=layout.runtime_config_root,
        work_root=layout.work_root,
        artifact_stage_factory=NativeLiveDocumentArtifactStageFactory(
            layout.pipeline_executable
        ),
        artifact_retainer=ContentAddressedArtifactRetainer(layout.artifact_root),
        environment=environment,
    )


def _arguments(values: Sequence[str]) -> tuple[str, str]:
    parser = _Parser(add_help=False, allow_abbrev=False, prog="ishikawa-ingest")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--validate-only", action="store_true")
    mode.add_argument("--publish", action="store_true")
    parser.add_argument("--manifest", required=True)
    parsed = parser.parse_args(list(values))
    return ("validate-only" if parsed.validate_only else "publish", parsed.manifest)


def execute_installed_ingestion(
    values: Sequence[str],
    *,
    product_root: str | Path,
    output: TextIO,
    environment: Mapping[str, str] = os.environ,
    runtime_factory: RuntimeFactory = build_installed_runtime,
    heartbeat_seconds: float = 30.0,
) -> int:
    """Execute one installed command without accepting paths or secrets as options."""

    try:
        if tuple(values) in {("--help",), ("-h",)}:
            output.write(
                "Usage: ishikawa-ingest "
                "(--validate-only|--publish) --manifest BATCH.yaml\n"
            )
            output.flush()
            return 0
        mode, manifest_name = _arguments(values)
        layout = InstalledIngestionLayout.from_product_root(product_root)
        paths = OperatorIngestionPaths(
            layout.class_registry,
            layout.document_catalog,
            layout.manifest(manifest_name),
            layout.source_root,
            layout.report_root,
        )
        runtime = runtime_factory(layout, paths, environment)
        if not callable(getattr(runtime, "execute", None)):
            raise InstalledIngestionError("runtime_invalid")
        milestones = _IngestionMilestoneStream(output, heartbeat_seconds)
        milestones.start(mode)
        try:
            exit_code = runtime.execute(mode, output=output)
            if type(exit_code) is not int or not 0 <= exit_code <= 255:
                raise InstalledIngestionError("runtime_exit_code_invalid")
        except KeyboardInterrupt:
            milestones.finish(130, reason="interrupted")
            return 130
        except Exception as error:
            reason = _safe_runtime_reason(error)
            milestones.finish(1, reason=reason)
            output.write(f"ishikawa_ingest=blocked;reason={reason}\n")
            output.flush()
            return 1
        milestones.finish(exit_code)
        return exit_code
    except InstalledIngestionError as error:
        output.write(f"ishikawa_ingest=blocked;reason={error}\n")
        output.flush()
        return 2
    except Exception:
        output.write("ishikawa_ingest=blocked;reason=runtime_failure\n")
        output.flush()
        return 1

