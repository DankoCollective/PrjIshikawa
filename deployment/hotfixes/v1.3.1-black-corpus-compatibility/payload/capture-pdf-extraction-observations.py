#!/usr/bin/env python3
"""Capture repeatable manifest-bound PDF observations with Poppler tools."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import resource
import socket
import subprocess
import tarfile
import time
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any


EXPECTED_PACKAGE = "poppler-utils"
MAX_SOURCE_BYTES = 64 * 1024 * 1024
MAX_RESULT_BYTES = 128 * 1024 * 1024
COMMAND_TIMEOUT_SECONDS = 60


class CaptureError(RuntimeError):
    """A content-safe capture failure."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_json_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise CaptureError("invalid_source_manifest") from exc
    if not isinstance(value, dict):
        raise CaptureError("invalid_source_manifest")
    return value


def read_os_version() -> str:
    values: dict[str, str] = {}
    try:
        for line in Path("/etc/os-release").read_text(encoding="utf-8").splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                values[key] = value.strip().strip('"')
    except OSError as exc:
        raise CaptureError("os_identity_unavailable") from exc
    return values.get("VERSION_ID", "")


def canonical_architecture(value: str) -> str:
    """Return the supported Debian-style architecture identifier."""

    aliases = {
        "amd64": "amd64",
        "x86_64": "amd64",
        "arm64": "arm64",
        "aarch64": "arm64",
    }
    try:
        return aliases[value]
    except KeyError as exc:
        raise CaptureError("architecture_mismatch") from exc


def bounded_environment() -> dict[str, str]:
    return {
        "HOME": "/tmp",
        "LANG": "C.UTF-8",
        "LC_ALL": "C.UTF-8",
        "PATH": "/usr/bin:/bin",
        "TMPDIR": "/tmp",
    }


def set_command_limits() -> None:
    os.umask(0o077)
    resource.setrlimit(resource.RLIMIT_CPU, (45, 45))
    resource.setrlimit(resource.RLIMIT_FSIZE, (MAX_RESULT_BYTES, MAX_RESULT_BYTES))
    resource.setrlimit(resource.RLIMIT_NOFILE, (64, 64))
    memory_limit = 1024 * 1024 * 1024
    resource.setrlimit(resource.RLIMIT_AS, (memory_limit, memory_limit))


def run_command(arguments: list[str]) -> tuple[bytes, bytes, int]:
    started = time.monotonic_ns()
    try:
        completed = subprocess.run(
            arguments,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=COMMAND_TIMEOUT_SECONDS,
            env=bounded_environment(),
            preexec_fn=set_command_limits,
        )
    except subprocess.TimeoutExpired as exc:
        raise CaptureError("extraction_command_timeout") from exc
    duration_ms = max(0, (time.monotonic_ns() - started) // 1_000_000)
    if completed.returncode != 0:
        raise CaptureError("extraction_command_failed")
    if len(completed.stdout) > MAX_RESULT_BYTES or len(completed.stderr) > MAX_RESULT_BYTES:
        raise CaptureError("extraction_command_output_limit")
    return completed.stdout, completed.stderr, duration_ms


def package_version() -> str:
    stdout, _, _ = run_command(["/usr/bin/dpkg-query", "-W", "-f=${Status}\t${Version}\n", EXPECTED_PACKAGE])
    fields = stdout.decode("utf-8", "strict").strip().split("\t")
    if (
        len(fields) != 2
        or fields[0] != "install ok installed"
        or not re.fullmatch(r"[0-9][A-Za-z0-9.+:~_-]*", fields[1])
    ):
        raise CaptureError("unexpected_poppler_package")
    return fields[1]


def tool_version(executable: str) -> str:
    stdout, stderr, _ = run_command([executable, "-v"])
    match = re.search(rb"version\s+([0-9]+(?:\.[0-9]+)+)", stdout + b"\n" + stderr, re.IGNORECASE)
    if not match:
        raise CaptureError("poppler_tool_version_unavailable")
    version = match.group(1).decode("ascii")
    return version


def require_matching_tool_versions(pdfinfo_version: str, pdftotext_version: str) -> None:
    """Require one coherent Poppler toolset without encoding a host package revision."""

    if pdfinfo_version != pdftotext_version:
        raise CaptureError("poppler_tool_version_mismatch")


def validate_source_manifest(
    path: Path, input_dir: Path
) -> tuple[list[dict[str, Any]], str]:
    manifest = load_json_object(path)
    if set(manifest) != {"files", "fixture_status", "schema_version"}:
        raise CaptureError("invalid_source_manifest")
    fixture_status = manifest["fixture_status"]
    if manifest["schema_version"] != 1 or fixture_status not in {
        "fully_synthetic_no_source_text",
        "operator_manifest_bound_source",
    }:
        raise CaptureError("invalid_source_manifest")
    files = manifest["files"]
    if not isinstance(files, list) or not 1 <= len(files) <= 1000:
        raise CaptureError("invalid_source_manifest")
    validated: list[dict[str, Any]] = []
    seen_names: set[str] = set()
    seen_ids: set[str] = set()
    for entry in files:
        if not isinstance(entry, dict) or set(entry) != {"bytes", "doc_id", "filename", "sha256"}:
            raise CaptureError("invalid_source_manifest")
        filename = entry["filename"]
        doc_id = entry["doc_id"]
        expected_bytes = entry["bytes"]
        expected_hash = entry["sha256"]
        if (
            not isinstance(filename, str)
            or Path(filename).name != filename
            or not filename.endswith(".pdf")
            or filename in seen_names
            or not isinstance(doc_id, str)
            or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", doc_id)
            or doc_id in seen_ids
            or not isinstance(expected_bytes, int)
            or expected_bytes <= 0
            or expected_bytes > MAX_SOURCE_BYTES
            or not isinstance(expected_hash, str)
            or not re.fullmatch(r"[0-9a-f]{64}", expected_hash)
        ):
            raise CaptureError("invalid_source_manifest")
        source = input_dir / filename
        if not source.is_file() or source.is_symlink():
            raise CaptureError("source_file_missing_or_unsafe")
        stat = source.stat()
        if stat.st_size != expected_bytes or sha256_file(source) != expected_hash:
            raise CaptureError("source_file_identity_mismatch")
        seen_names.add(filename)
        seen_ids.add(doc_id)
        validated.append(dict(entry))
    actual_files = sorted(item.name for item in input_dir.iterdir() if item.is_file())
    if actual_files != sorted(seen_names):
        raise CaptureError("unexpected_source_file_set")
    return validated, fixture_status


def parse_pdfinfo(data: bytes) -> dict[str, Any]:
    try:
        lines = data.decode("utf-8", "strict").splitlines()
    except UnicodeError as exc:
        raise CaptureError("invalid_pdfinfo_output") from exc
    fields: dict[str, str] = {}
    for line in lines:
        if ":" in line:
            key, value = line.split(":", 1)
            fields[key.strip()] = value.strip()
    try:
        pages = int(fields["Pages"])
    except (KeyError, ValueError) as exc:
        raise CaptureError("invalid_pdfinfo_output") from exc
    if pages <= 0 or fields.get("Encrypted", "").lower() != "no":
        raise CaptureError("unsupported_or_encrypted_pdf")
    return {
        "encrypted": fields.get("Encrypted", ""),
        "page_size": fields.get("Page size", ""),
        "pages": pages,
    }


def layout_pages(data: bytes, expected_pages: int | None = None) -> list[str]:
    try:
        text = data.decode("utf-8", "strict")
    except UnicodeError as exc:
        raise CaptureError("invalid_layout_output") from exc
    pages = text.split("\f")
    if expected_pages is None:
        if pages and not pages[-1].strip():
            pages.pop()
    elif len(pages) == expected_pages + 1 and not pages[-1].strip():
        pages.pop()
    return pages


def bbox_pages(data: bytes) -> list[list[str]]:
    try:
        root = ET.fromstring(data)
    except ET.ParseError as exc:
        raise CaptureError("invalid_bbox_output") from exc
    pages: list[list[str]] = []
    for page in (item for item in root.iter() if item.tag.rsplit("}", 1)[-1] == "page"):
        words: list[str] = []
        for word in (item for item in page.iter() if item.tag.rsplit("}", 1)[-1] == "word"):
            value = "".join(word.itertext()).strip()
            if value:
                words.append(value)
        pages.append(words)
    return pages


def safe_stem(filename: str) -> str:
    value = re.sub(r"[^A-Za-z0-9_.-]+", "_", filename)
    return value[:-4] if value.lower().endswith(".pdf") else value


def write_bytes(path: Path, data: bytes) -> None:
    if path.exists() or path.is_symlink():
        raise CaptureError("result_path_already_exists")
    with path.open("xb") as handle:
        handle.write(data)
    path.chmod(0o600)


def create_archive(output_dir: Path, archive: Path) -> None:
    if archive.exists() or archive.is_symlink():
        raise CaptureError("archive_path_already_exists")
    with tarfile.open(archive, "w", format=tarfile.PAX_FORMAT) as bundle:
        for source in sorted(output_dir.rglob("*")):
            if source.is_symlink() or (not source.is_file() and not source.is_dir()):
                raise CaptureError("unsafe_result_member")
            relative = source.relative_to(output_dir)
            info = bundle.gettarinfo(str(source), arcname=relative.as_posix())
            info.uid = 0
            info.gid = 0
            info.uname = ""
            info.gname = ""
            info.mtime = 0
            info.mode = 0o700 if source.is_dir() else 0o600
            if source.is_file():
                with source.open("rb") as handle:
                    bundle.addfile(info, handle)
            else:
                bundle.addfile(info)
    archive.chmod(0o600)
    if archive.stat().st_size > MAX_RESULT_BYTES:
        raise CaptureError("archive_size_limit")


def capture_document(source: Path, entry: dict[str, Any], raw_dir: Path) -> dict[str, Any]:
    stem = safe_stem(entry["filename"])
    first_dir = raw_dir / stem
    repeat_dir = raw_dir / f"{stem}.repeat"
    first_dir.mkdir(mode=0o700)
    repeat_dir.mkdir(mode=0o700)
    durations: dict[str, int] = {}

    info_first, info_stderr_first, durations["pdfinfo_first_ms"] = run_command(["/usr/bin/pdfinfo", str(source)])
    info_second, info_stderr_second, durations["pdfinfo_repeat_ms"] = run_command(["/usr/bin/pdfinfo", str(source)])
    write_bytes(first_dir / "pdfinfo.txt", info_first)
    write_bytes(first_dir / "pdfinfo.stderr", info_stderr_first)
    write_bytes(repeat_dir / "pdfinfo.txt", info_second)
    write_bytes(repeat_dir / "pdfinfo.stderr", info_stderr_second)

    layout_first = first_dir / "layout.txt"
    layout_second = repeat_dir / "layout.txt"
    _, layout_stderr_first, durations["layout_first_ms"] = run_command([
        "/usr/bin/pdftotext", "-layout", "-enc", "UTF-8", "-eol", "unix", str(source), str(layout_first)
    ])
    _, layout_stderr_second, durations["layout_repeat_ms"] = run_command([
        "/usr/bin/pdftotext", "-layout", "-enc", "UTF-8", "-eol", "unix", str(source), str(layout_second)
    ])
    write_bytes(first_dir / "layout.stderr", layout_stderr_first)
    write_bytes(repeat_dir / "layout.stderr", layout_stderr_second)

    bbox_first = first_dir / "bbox.html"
    bbox_second = repeat_dir / "bbox.html"
    _, bbox_stderr_first, durations["bbox_first_ms"] = run_command([
        "/usr/bin/pdftotext", "-bbox-layout", "-enc", "UTF-8", str(source), str(bbox_first)
    ])
    _, bbox_stderr_second, durations["bbox_repeat_ms"] = run_command([
        "/usr/bin/pdftotext", "-bbox-layout", "-enc", "UTF-8", str(source), str(bbox_second)
    ])
    write_bytes(first_dir / "bbox.stderr", bbox_stderr_first)
    write_bytes(repeat_dir / "bbox.stderr", bbox_stderr_second)

    artifacts = {
        "bbox": (bbox_first, bbox_second),
        "layout": (layout_first, layout_second),
        "pdfinfo": (first_dir / "pdfinfo.txt", repeat_dir / "pdfinfo.txt"),
        "bbox_stderr": (first_dir / "bbox.stderr", repeat_dir / "bbox.stderr"),
        "layout_stderr": (first_dir / "layout.stderr", repeat_dir / "layout.stderr"),
        "pdfinfo_stderr": (first_dir / "pdfinfo.stderr", repeat_dir / "pdfinfo.stderr"),
    }
    repeat_hashes: dict[str, str] = {}
    for name, (first, second) in artifacts.items():
        first_hash = sha256_file(first)
        second_hash = sha256_file(second)
        if first_hash != second_hash:
            raise CaptureError("nonrepeatable_extraction_output")
        repeat_hashes[name] = first_hash

    info = parse_pdfinfo(info_first)
    layout = layout_pages(layout_first.read_bytes(), info["pages"])
    bbox = bbox_pages(bbox_first.read_bytes())
    if len(layout) != info["pages"] or len(bbox) != info["pages"]:
        raise CaptureError("extraction_page_count_mismatch")
    page_observations: list[dict[str, Any]] = []
    for index, (layout_text, words) in enumerate(zip(layout, bbox), start=1):
        layout_blank = not layout_text.strip()
        bbox_blank = not words
        if layout_blank != bbox_blank:
            raise CaptureError("blank_page_observation_mismatch")
        page_observations.append({
            "bbox_word_count": len(words),
            "blank": layout_blank,
            "layout_character_count": len(layout_text.strip()),
            "layout_token_count": len(layout_text.split()),
            "page": index,
        })
    return {
        "doc_id": entry["doc_id"],
        "durations": durations,
        "filename": entry["filename"],
        "outputs": repeat_hashes,
        "page_observations": page_observations,
        "pdfinfo": info,
        "source_bytes": entry["bytes"],
        "source_sha256": entry["sha256"],
    }


def self_test() -> int:
    sample_layout = b"\falpha beta\f"
    sample_bbox = b'''<?xml version="1.0"?><doc><page/><page><word xMin="1" yMin="2" xMax="3" yMax="4">alpha</word><word>beta</word></page></doc>'''
    if layout_pages(sample_layout, 2) != ["", "alpha beta"]:
        return 1
    if bbox_pages(sample_bbox) != [[], ["alpha", "beta"]]:
        return 1
    if canonical_architecture("x86_64") != "amd64":
        return 1
    if canonical_architecture("aarch64") != "arm64":
        return 1
    print("pdf_extraction_capture_self_test=pass")
    return 0


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive")
    parser.add_argument("--expected-hostname")
    parser.add_argument("--expected-os-version")
    parser.add_argument("--input-dir")
    parser.add_argument("--output-dir")
    parser.add_argument("--source-manifest")
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    if arguments.self_test:
        return self_test()
    os.umask(0o077)
    required = [
        arguments.archive,
        arguments.expected_hostname,
        arguments.expected_os_version,
        arguments.input_dir,
        arguments.output_dir,
        arguments.source_manifest,
    ]
    if not all(required):
        raise CaptureError("missing_required_argument")
    expected_hostname = str(arguments.expected_hostname)
    expected_os_version = str(arguments.expected_os_version)
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]*", expected_hostname):
        raise CaptureError("invalid_expected_hostname")
    if not re.fullmatch(r"[0-9]{2}\.[0-9]{2}", expected_os_version):
        raise CaptureError("invalid_expected_os_version")
    input_dir = Path(str(arguments.input_dir)).resolve(strict=True)
    manifest_path = Path(str(arguments.source_manifest)).resolve(strict=True)
    output_dir = Path(str(arguments.output_dir))
    archive = Path(str(arguments.archive))
    for candidate in (input_dir, manifest_path):
        if candidate.is_symlink():
            raise CaptureError("unsafe_input_path")
    if not input_dir.is_dir() or not manifest_path.is_file():
        raise CaptureError("missing_input")
    if not output_dir.is_absolute() or not archive.is_absolute():
        raise CaptureError("result_path_not_absolute")
    if output_dir.exists() or output_dir.is_symlink() or archive.exists() or archive.is_symlink():
        raise CaptureError("result_path_already_exists")
    if socket.gethostname().split(".", 1)[0] != expected_hostname:
        raise CaptureError("hostname_mismatch")
    if read_os_version() != expected_os_version:
        raise CaptureError("os_version_mismatch")
    architecture = canonical_architecture(platform.machine())
    for executable in ("/usr/bin/dpkg-query", "/usr/bin/pdfinfo", "/usr/bin/pdftotext"):
        if not Path(executable).is_file() or not os.access(executable, os.X_OK):
            raise CaptureError("required_executable_missing")

    files, fixture_status = validate_source_manifest(manifest_path, input_dir)
    package = package_version()
    pdfinfo_version = tool_version("/usr/bin/pdfinfo")
    pdftotext_version = tool_version("/usr/bin/pdftotext")
    require_matching_tool_versions(pdfinfo_version, pdftotext_version)
    output_dir.mkdir(mode=0o700)
    raw_dir = output_dir / "raw"
    raw_dir.mkdir(mode=0o700)
    observations: list[dict[str, Any]] = []
    for entry in sorted(files, key=lambda item: item["doc_id"]):
        observations.append(capture_document(input_dir / entry["filename"], entry, raw_dir))
    total_pages = sum(len(item["page_observations"]) for item in observations)
    blank_pages = sum(
        1
        for item in observations
        for page in item["page_observations"]
        if page["blank"]
    )
    result = {
        "architecture": architecture,
        "documents": observations,
        "fixture_status": fixture_status,
        "host": expected_hostname,
        "os_version": expected_os_version,
        "pdfinfo_version": pdfinfo_version,
        "pdftotext_version": pdftotext_version,
        "poppler_package": EXPECTED_PACKAGE,
        "poppler_package_version": package,
        "schema_version": 1,
        "source_manifest_sha256": sha256_file(manifest_path),
        "summary": {
            "blank_pages": blank_pages,
            "documents": len(observations),
            "pages": total_pages,
            "repeatability": "pass",
        },
    }
    observations_path = output_dir / "observations.json"
    observations_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    observations_path.chmod(0o600)
    create_archive(output_dir, archive)
    print("purpose=capture_pdf_extraction_observations")
    print(f"host={expected_hostname};os_version={expected_os_version};architecture={architecture}")
    print(f"poppler_package_version={package};pdfinfo_version={pdfinfo_version};pdftotext_version={pdftotext_version}")
    print(f"source_documents={len(observations)};source_pages={total_pages};observed_blank_pages={blank_pages}")
    print("repeatability=pass;document_failures=0")
    print(f"archive_sha256={sha256_file(archive)};archive_bytes={archive.stat().st_size}")
    print("pdf_extraction_capture=pass")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except CaptureError as exc:
        print(f"pdf_extraction_capture=blocked;reason={exc}")
        raise SystemExit(1)
    except (OSError, ValueError) as exc:
        print(f"pdf_extraction_capture=blocked;reason=bounded_runtime_failure;error_type={type(exc).__name__}")
        raise SystemExit(1)
