"""Neutral executable pipeline for changed-document artifact production.

The pipeline accepts the checksum-bound request written by
``NativeLiveDocumentArtifactStage`` and runs the already-qualified Poppler,
normalization, structural chunking, and Nomic document-embedding tools.  It
never chooses documents by scanning the corpus: only request members are
copied into its private temporary input directory.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any

from .canonical import canonical_json_bytes, file_sha256


MAX_REQUEST_BYTES = 1024 * 1024
MAX_CREDENTIAL_BYTES = 1024
MAX_DIAGNOSTIC_BYTES = 1024 * 1024
PIPELINE_TIMEOUT_SECONDS = 3600
NOMIC_MODEL = "nomic-ai/nomic-embed-text-v1.5"
HEX_PATTERN = re.compile(r"[0-9a-f]{64}")
IDENTIFIER_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}")
STAGE_FAILURE_PATTERN = re.compile(
    r"^(?:pdf_extraction_capture|normalization|chunk_candidates|"
    r"document_embedding_stage)=blocked;reason=([a-z][a-z0-9_]{0,95})$",
    re.MULTILINE,
)


class ArtifactPipelineError(RuntimeError):
    """Stable, content-free artifact-pipeline failure."""


@dataclass(frozen=True, slots=True)
class PipelineLayout:
    """Absolute installed locations of the four qualified stage programs."""

    python_root: Path
    capture: Path
    normalize: Path
    chunk: Path
    embed: Path


PipelineRunner = Callable[[tuple[str, ...], bytes | None, Path, Path, Path], int]


def _fail(reason: str) -> None:
    raise ArtifactPipelineError(reason)


def _load_exact_json(path: Path) -> Mapping[str, Any]:
    if (
        not path.is_absolute()
        or not path.is_file()
        or path.is_symlink()
        or path.stat().st_size > MAX_REQUEST_BYTES
    ):
        _fail("request_unsafe")
    def strict_object(values: list[tuple[str, Any]]) -> dict[str, Any]:
        keys = [item[0] for item in values]
        if len(keys) != len(set(keys)):
            raise ValueError("duplicate_json_field")
        return dict(values)
    try:
        value = json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=strict_object,
            parse_constant=lambda _value: (_ for _ in ()).throw(ValueError()),
        )
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError):
        _fail("request_invalid")
    if not isinstance(value, dict):
        _fail("request_invalid")
    return value


def _require_hex(value: Any, reason: str) -> str:
    if not isinstance(value, str) or HEX_PATTERN.fullmatch(value) is None:
        _fail(reason)
    return value


def _validate_request(path: Path) -> Mapping[str, Any]:
    request = _load_exact_json(path)
    if set(request) != {
        "schema_version",
        "validation_id",
        "method_profile_id",
        "manifest_digest",
        "documents",
    } or request.get("schema_version") != 1:
        _fail("request_invalid")
    _require_hex(request.get("validation_id"), "validation_identity_invalid")
    _require_hex(request.get("method_profile_id"), "method_profile_identity_invalid")
    _require_hex(request.get("manifest_digest"), "manifest_identity_invalid")
    documents = request.get("documents")
    if not isinstance(documents, list) or not 1 <= len(documents) <= 1000:
        _fail("request_document_inventory_invalid")
    seen_keys: set[str] = set()
    seen_paths: set[str] = set()
    for item in documents:
        if not isinstance(item, dict) or set(item) != {
            "action",
            "document_key",
            "class_id",
            "relative_source_path",
            "source_sha256",
        }:
            _fail("request_document_invalid")
        document_key = item.get("document_key")
        class_id = item.get("class_id")
        source_path = item.get("relative_source_path")
        if (
            item.get("action") not in {"add", "revise", "reprocess"}
            or not isinstance(document_key, str)
            or IDENTIFIER_PATTERN.fullmatch(document_key) is None
            or not isinstance(class_id, str)
            or IDENTIFIER_PATTERN.fullmatch(class_id) is None
            or not isinstance(source_path, str)
        ):
            _fail("request_document_invalid")
        relative = PurePosixPath(source_path)
        if relative.is_absolute() or not relative.parts or any(
            part in {"", ".", ".."} for part in relative.parts
        ):
            _fail("request_source_path_invalid")
        _require_hex(item.get("source_sha256"), "request_source_identity_invalid")
        if document_key in seen_keys or source_path in seen_paths:
            _fail("request_document_duplicate")
        seen_keys.add(document_key)
        seen_paths.add(source_path)
    return request


def _validate_layout(layout: PipelineLayout) -> None:
    if not layout.python_root.is_absolute() or not layout.python_root.is_dir() or layout.python_root.is_symlink():
        _fail("pipeline_layout_unsafe")
    for program in (layout.capture, layout.normalize, layout.chunk, layout.embed):
        if not program.is_absolute() or not program.is_file() or program.is_symlink():
            _fail("pipeline_layout_unsafe")


def _read_os_version() -> str:
    try:
        values = dict(
            line.split("=", 1)
            for line in Path("/etc/os-release").read_text(encoding="utf-8").splitlines()
            if "=" in line
        )
    except OSError:
        _fail("host_identity_unavailable")
    value = values.get("VERSION_ID", "").strip().strip('"')
    if re.fullmatch(r"[0-9]{2}\.[0-9]{2}", value) is None:
        _fail("host_identity_unavailable")
    return value


def _read_credential() -> bytearray:
    value = bytearray()
    while len(value) <= MAX_CREDENTIAL_BYTES + 1:
        block = os.read(sys.stdin.fileno(), MAX_CREDENTIAL_BYTES + 2 - len(value))
        if not block:
            break
        value.extend(block)
    if value.endswith(b"\n"):
        value.pop()
    if not 32 <= len(value) <= MAX_CREDENTIAL_BYTES or b"\n" in value or b"\r" in value:
        _wipe(value)
        _fail("credential_format_invalid")
    return value


def _wipe(value: bytearray) -> None:
    for index in range(len(value)):
        value[index] = 0


def native_pipeline_runner(
    command: tuple[str, ...],
    stdin: bytes | None,
    cwd: Path,
    stdout_path: Path,
    stderr_path: Path,
) -> int:
    """Run one stage without a shell, inherited secrets, or unbounded output."""

    try:
        with stdout_path.open("xb") as stdout, stderr_path.open("xb") as stderr:
            completed = subprocess.run(
                command,
                cwd=cwd,
                env={
                    "HOME": "/tmp",
                    "LANG": "C.UTF-8",
                    "LC_ALL": "C.UTF-8",
                    "PATH": "/usr/bin:/bin",
                    "PYTHONDONTWRITEBYTECODE": "1",
                },
                input=stdin,
                stdout=stdout,
                stderr=stderr,
                timeout=PIPELINE_TIMEOUT_SECONDS,
                check=False,
                shell=False,
            )
    except (OSError, subprocess.SubprocessError):
        _fail("pipeline_stage_unavailable")
    if stdout_path.stat().st_size > MAX_DIAGNOSTIC_BYTES or stderr_path.stat().st_size > MAX_DIAGNOSTIC_BYTES:
        _fail("pipeline_stage_output_limit")
    return int(completed.returncode)


def _run_stage(
    name: str,
    command: Sequence[str],
    stdin: bytes | None,
    work: Path,
    runner: PipelineRunner,
) -> None:
    stdout_path = work / f"{name}.stdout"
    stderr_path = work / f"{name}.stderr"
    status = runner(
        tuple(command),
        stdin,
        work,
        stdout_path,
        stderr_path,
    )
    if status != 0:
        for path in (stdout_path, stderr_path):
            try:
                output = path.read_text(encoding="utf-8")
            except (FileNotFoundError, OSError, UnicodeError):
                continue
            matches = STAGE_FAILURE_PATTERN.findall(output)
            if matches:
                _fail(f"{name}_{matches[-1]}")
        _fail(f"{name}_failed")


def _write_exclusive(path: Path, payload: bytes) -> None:
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)


def _stage_sources(
    request: Mapping[str, Any], source_root: Path, destination: Path
) -> Path:
    destination.mkdir(mode=0o700)
    files: list[dict[str, Any]] = []
    root = source_root.resolve(strict=True)
    for ordinal, item in enumerate(request["documents"], start=1):
        relative = PurePosixPath(item["relative_source_path"])
        source = root.joinpath(*relative.parts)
        candidate = root
        for part in relative.parts:
            candidate = candidate / part
            if candidate.is_symlink():
                _fail("source_file_unsafe")
        try:
            resolved_source = source.resolve(strict=True)
        except OSError:
            _fail("source_file_unsafe")
        if (
            not source.is_file()
            or source.is_symlink()
            or not resolved_source.is_relative_to(root)
        ):
            _fail("source_file_unsafe")
        if source.suffix.lower() != ".pdf" or file_sha256(str(source)) != item["source_sha256"]:
            _fail("source_file_identity_mismatch")
        filename = f"document-{ordinal:04d}.pdf"
        staged = destination / filename
        with source.open("rb") as input_stream, staged.open("xb") as output_stream:
            shutil.copyfileobj(input_stream, output_stream, 1024 * 1024)
        staged.chmod(0o600)
        if file_sha256(str(staged)) != item["source_sha256"]:
            _fail("staged_source_identity_mismatch")
        files.append(
            {
                "bytes": staged.stat().st_size,
                "doc_id": item["document_key"],
                "filename": filename,
                "sha256": item["source_sha256"],
            }
        )
    manifest_path = destination.parent / "source-manifest.json"
    _write_exclusive(
        manifest_path,
        canonical_json_bytes(
            {
                "files": files,
                "fixture_status": "operator_manifest_bound_source",
                "schema_version": 1,
            }
        )
        + b"\n",
    )
    return manifest_path


def run_artifact_pipeline(
    *,
    request_path: Path,
    source_root: Path,
    workspace: Path,
    embedding_url: str,
    tokenization_url: str,
    served_model: str,
    batch_size: int,
    credential: bytearray,
    layout: PipelineLayout,
    runner: PipelineRunner = native_pipeline_runner,
) -> Mapping[str, Any]:
    """Run the four stages and return the exact stage-result document."""

    _validate_layout(layout)
    request = _validate_request(request_path)
    if (
        not source_root.is_absolute()
        or not source_root.is_dir()
        or source_root.is_symlink()
        or not workspace.is_absolute()
        or not workspace.is_dir()
        or workspace.is_symlink()
        or request_path.parent.resolve(strict=True) != workspace.resolve(strict=True)
        or served_model != NOMIC_MODEL
        or type(batch_size) is not int
        or not 1 <= batch_size <= 64
        or not callable(runner)
    ):
        _fail("pipeline_request_invalid")
    outputs = {
        "normalized": workspace / "normalized.json",
        "chunk": workspace / "chunks.json",
        "embedding": workspace / "embeddings.json",
        "result": workspace / "stage-result.json",
    }
    if any(path.exists() or path.is_symlink() for path in outputs.values()):
        _fail("pipeline_output_exists")

    with tempfile.TemporaryDirectory(prefix=".artifact-pipeline-", dir=workspace) as temporary:
        work = Path(temporary)
        work.chmod(0o700)
        staged_sources = work / "source"
        source_manifest = _stage_sources(request, source_root, staged_sources)
        extraction_directory = work / "extraction"
        extraction_archive = work / "extraction.tar"
        _run_stage(
            "extraction",
            (
                "/usr/bin/python3", "-B", str(layout.capture),
                "--expected-hostname", socket.gethostname().split(".", 1)[0],
                "--expected-os-version", _read_os_version(),
                "--input-dir", str(staged_sources),
                "--source-manifest", str(source_manifest),
                "--output-dir", str(extraction_directory),
                "--archive", str(extraction_archive),
            ),
            None,
            work,
            runner,
        )
        if not extraction_archive.is_file() or extraction_archive.is_symlink():
            _fail("extraction_artifact_missing")
        extraction_sha256 = file_sha256(str(extraction_archive))
        _run_stage(
            "normalization",
            (
                "/usr/bin/python3", "-B", str(layout.normalize),
                "--archive", str(extraction_archive),
                "--expected-archive-sha256", extraction_sha256,
                "--output", str(outputs["normalized"]),
                "--python-root", str(layout.python_root),
                "--source-manifest", str(source_manifest),
            ),
            None,
            work,
            runner,
        )
        if not outputs["normalized"].is_file() or outputs["normalized"].is_symlink():
            _fail("normalized_artifact_missing")
        normalized_sha256 = file_sha256(str(outputs["normalized"]))
        _run_stage(
            "chunking",
            (
                "/usr/bin/python3", "-B", str(layout.chunk),
                "--input", str(outputs["normalized"]),
                "--expected-input-sha256", normalized_sha256,
                "--output", str(outputs["chunk"]),
                "--python-root", str(layout.python_root),
            ),
            None,
            work,
            runner,
        )
        if not outputs["chunk"].is_file() or outputs["chunk"].is_symlink():
            _fail("chunk_artifact_missing")
        chunk_sha256 = file_sha256(str(outputs["chunk"]))
        _run_stage(
            "embedding",
            (
                "/usr/bin/python3", "-B", str(layout.embed),
                "--credential-stdin",
                "--input", str(outputs["chunk"]),
                "--expected-input-sha256", chunk_sha256,
                "--embedding-url", embedding_url,
                "--tokenizer-url", tokenization_url,
                "--batch-size", str(batch_size),
                "--output", str(outputs["embedding"]),
            ),
            bytes(credential),
            work,
            runner,
        )
        if not outputs["embedding"].is_file() or outputs["embedding"].is_symlink():
            _fail("embedding_artifact_missing")
        embedding_sha256 = file_sha256(str(outputs["embedding"]))

    result = {
        "schema_version": 1,
        "outcome": "pass",
        "validation_id": request["validation_id"],
        "method_profile_id": request["method_profile_id"],
        "manifest_digest": request["manifest_digest"],
        "served_model": served_model,
        "normalized_sha256": normalized_sha256,
        "chunk_sha256": chunk_sha256,
        "embedding_sha256": embedding_sha256,
        "credential_retained": False,
    }
    _write_exclusive(outputs["result"], canonical_json_bytes(result) + b"\n")
    return result


def main(layout: PipelineLayout, argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="ishikawa-produce-artifacts")
    parser.add_argument("--request", required=True, type=Path)
    parser.add_argument("--source-root", required=True, type=Path)
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--embedding-url", required=True)
    parser.add_argument("--tokenization-url", required=True)
    parser.add_argument("--served-model", required=True)
    parser.add_argument("--batch-size", required=True, type=int)
    parser.add_argument("--credential-stdin", action="store_true")
    arguments = parser.parse_args(argv)
    credential = bytearray()
    try:
        if not arguments.credential_stdin:
            _fail("credential_transport_invalid")
        credential = _read_credential()
        run_artifact_pipeline(
            request_path=arguments.request,
            source_root=arguments.source_root,
            workspace=arguments.workspace,
            embedding_url=arguments.embedding_url,
            tokenization_url=arguments.tokenization_url,
            served_model=arguments.served_model,
            batch_size=arguments.batch_size,
            credential=credential,
            layout=layout,
        )
    except ArtifactPipelineError as error:
        print(f"live_document_pipeline=blocked;reason={error}")
        return 1
    finally:
        _wipe(credential)
    print("credential_retained=false;source_workspace_retained=false")
    print("live_document_pipeline=pass")
    return 0
