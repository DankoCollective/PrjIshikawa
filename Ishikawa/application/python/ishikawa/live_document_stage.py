"""Concrete process boundary for extraction through document embedding."""

from __future__ import annotations

import json
import os
import re
import subprocess
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .canonical import canonical_json_bytes, file_sha256
from .document_producer import METHOD_PROFILE_ID, ProducerArtifactBundle
from .ingestion_runtime import IngestionDependencyPolicy
from .models import IngestionManifest
from .operator_ingestion import ProductionBatch
from .runtime import ProtectedEnvironmentValue


MAX_STAGE_OUTPUT_BYTES = 1024 * 1024
_PIPELINE_FAILURE = re.compile(
    r"live_document_pipeline=blocked;reason=([a-z][a-z0-9_]{0,127})\n?"
)


class LiveDocumentStageError(RuntimeError):
    """Stable, content-free live document-stage failure."""


StageProcessRunner = Callable[[tuple[str, ...], bytes, Path, int], int]


def _fail(reason: str) -> None:
    raise LiveDocumentStageError(reason)


def _load_exact_json(path: Path, fields: frozenset[str]) -> Mapping[str, Any]:
    if not path.is_file() or path.is_symlink() or path.stat().st_size > 65536:
        _fail("stage_result_unsafe")
    try:
        pairs = json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=lambda values: values,
            parse_constant=lambda _value: (_ for _ in ()).throw(ValueError()),
        )
        if not isinstance(pairs, list) or any(
            not isinstance(item, tuple) or len(item) != 2 for item in pairs
        ):
            _fail("stage_result_invalid")
        keys = [item[0] for item in pairs]
        if len(keys) != len(set(keys)):
            _fail("stage_result_invalid")
        value = dict(pairs)
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError):
        _fail("stage_result_invalid")
    if set(value) != fields:
        _fail("stage_result_invalid")
    return value


def native_stage_process(
    command: tuple[str, ...], credential: bytes, workspace: Path, timeout_seconds: int
) -> int:
    """Run one installed pipeline executable without a shell or inherited secrets."""

    stdout_path = workspace / ".stage-stdout"
    stderr_path = workspace / ".stage-stderr"
    descriptors: list[int] = []
    process = None
    try:
        for path in (stdout_path, stderr_path):
            descriptors.append(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600))
        with os.fdopen(descriptors.pop(0), "wb") as stdout, os.fdopen(
            descriptors.pop(0), "wb"
        ) as stderr:
            process = subprocess.Popen(
                command,
                cwd=workspace,
                env={
                    "LANG": "C.UTF-8",
                    "LC_ALL": "C.UTF-8",
                    "PATH": "/usr/bin:/bin",
                    "PYTHONDONTWRITEBYTECODE": "1",
                },
                stdin=subprocess.PIPE,
                stdout=stdout,
                stderr=stderr,
                shell=False,
            )
            try:
                process.communicate(input=credential, timeout=timeout_seconds)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate()
                _fail("stage_process_timeout")
        if any(path.stat().st_size > MAX_STAGE_OUTPUT_BYTES for path in (stdout_path, stderr_path)):
            _fail("stage_process_output_limit")
        if process.returncode != 0:
            try:
                output = stdout_path.read_text(encoding="utf-8")
            except (OSError, UnicodeError):
                _fail("stage_process_failed")
            match = _PIPELINE_FAILURE.fullmatch(output)
            if match is None:
                _fail("stage_process_failed")
            _fail(f"stage_process_{match.group(1)}")
        return int(process.returncode)
    except LiveDocumentStageError:
        raise
    except (OSError, ValueError, subprocess.SubprocessError):
        _fail("stage_process_unavailable")
    finally:
        for descriptor in descriptors:
            try:
                os.close(descriptor)
            except OSError:
                pass
        for path in (stdout_path, stderr_path):
            try:
                path.unlink()
            except FileNotFoundError:
                pass


@dataclass(frozen=True, slots=True)
class NativeLiveDocumentArtifactStage:
    """Invoke one installed pipeline for exactly one planned document batch."""

    executable: Path
    dependencies: IngestionDependencyPolicy
    credential_provider: ProtectedEnvironmentValue
    process_runner: StageProcessRunner = native_stage_process
    timeout_seconds: int = 3600

    def __post_init__(self) -> None:
        if (
            not self.executable.is_absolute()
            or self.executable.is_symlink()
            or not self.executable.is_file()
            or not os.access(self.executable, os.X_OK)
        ):
            _fail("stage_executable_unsafe")
        if not callable(self.credential_provider) or not callable(self.process_runner):
            _fail("stage_dependency_invalid")
        if type(self.timeout_seconds) is not int or not 1 <= self.timeout_seconds <= 7200:
            _fail("stage_timeout_invalid")

    def __call__(
        self,
        batch: ProductionBatch,
        manifest: IngestionManifest,
        workspace: Path,
    ) -> ProducerArtifactBundle:
        if (
            not isinstance(batch, ProductionBatch)
            or not isinstance(manifest, IngestionManifest)
            or batch.method_profile_id != METHOD_PROFILE_ID
        ):
            _fail("stage_request_invalid")
        if not workspace.is_absolute() or workspace.is_symlink() or not workspace.is_dir():
            _fail("stage_workspace_unsafe")
        if len(batch.documents) != len(manifest.documents) or {
            item.document_key for item in batch.documents
        } != {item.document_key for item in manifest.documents}:
            _fail("stage_manifest_coverage_mismatch")

        request_path = workspace / "stage-request.json"
        request = {
            "schema_version": 1,
            "validation_id": batch.validation_id,
            "method_profile_id": batch.method_profile_id,
            "manifest_digest": manifest.digest,
            "documents": [
                {
                    "action": item.action,
                    "document_key": item.document_key,
                    "class_id": item.class_id,
                    "relative_source_path": item.relative_source_path,
                    "source_sha256": item.source_digest,
                }
                for item in batch.documents
            ],
        }
        descriptor = os.open(request_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(canonical_json_bytes(request) + b"\n")

        normalized_path = workspace / "normalized.json"
        chunk_path = workspace / "chunks.json"
        embedding_path = workspace / "embeddings.json"
        result_path = workspace / "stage-result.json"
        command = (
            str(self.executable),
            "--request", str(request_path),
            "--source-root", str(batch.source_root),
            "--workspace", str(workspace),
            "--embedding-url", self.dependencies.embedding_endpoint.url,
            "--tokenization-url", self.dependencies.tokenization_endpoint.url,
            "--served-model", self.dependencies.served_model,
            "--batch-size", str(self.dependencies.embedding_batch_size),
            "--credential-stdin",
        )
        secret = bytearray((self.credential_provider() + "\n").encode("utf-8"))
        try:
            status = self.process_runner(command, bytes(secret), workspace, self.timeout_seconds)
        finally:
            for index in range(len(secret)):
                secret[index] = 0
        if status != 0:
            _fail("stage_process_failed")

        fields = frozenset(
            {
                "schema_version",
                "outcome",
                "validation_id",
                "method_profile_id",
                "manifest_digest",
                "served_model",
                "normalized_sha256",
                "chunk_sha256",
                "embedding_sha256",
                "credential_retained",
            }
        )
        result = _load_exact_json(result_path, fields)
        expected = {
            "schema_version": 1,
            "outcome": "pass",
            "validation_id": batch.validation_id,
            "method_profile_id": batch.method_profile_id,
            "manifest_digest": manifest.digest,
            "served_model": self.dependencies.served_model,
            "credential_retained": False,
        }
        if any(result.get(key) != value for key, value in expected.items()):
            _fail("stage_result_contract_mismatch")
        entries = (
            (normalized_path, result.get("normalized_sha256")),
            (chunk_path, result.get("chunk_sha256")),
            (embedding_path, result.get("embedding_sha256")),
        )
        for path, digest in entries:
            if (
                not isinstance(digest, str)
                or len(digest) != 64
                or any(character not in "0123456789abcdef" for character in digest)
                or not path.is_file()
                or path.is_symlink()
                or file_sha256(str(path)) != digest
            ):
                _fail("stage_artifact_identity_mismatch")
        return ProducerArtifactBundle(
            normalized_path,
            str(entries[0][1]),
            chunk_path,
            str(entries[1][1]),
            embedding_path,
            str(entries[2][1]),
        )


@dataclass(frozen=True, slots=True)
class NativeLiveDocumentArtifactStageFactory:
    executable: Path
    process_runner: StageProcessRunner = native_stage_process
    timeout_seconds: int = 3600

    def __call__(
        self,
        dependencies: IngestionDependencyPolicy,
        credential_provider: ProtectedEnvironmentValue,
    ) -> NativeLiveDocumentArtifactStage:
        return NativeLiveDocumentArtifactStage(
            self.executable,
            dependencies,
            credential_provider,
            self.process_runner,
            self.timeout_seconds,
        )
