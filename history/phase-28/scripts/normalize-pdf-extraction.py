#!/usr/bin/env python3
"""Create one deterministic normalized structural-unit artifact."""

from __future__ import annotations

import argparse
import hashlib
import os
import sys
from pathlib import Path


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", required=True)
    parser.add_argument("--expected-archive-sha256", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--python-root", required=True)
    parser.add_argument("--source-manifest", required=True)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    python_root = Path(arguments.python_root)
    output = Path(arguments.output)
    if not python_root.is_dir() or python_root.is_symlink():
        print("normalization=blocked;reason=unsafe_python_root")
        return 2
    if not output.is_absolute() or output.exists() or output.is_symlink():
        print("normalization=blocked;reason=unsafe_output_path")
        return 2
    if not output.parent.is_dir() or output.parent.is_symlink():
        print("normalization=blocked;reason=unsafe_output_parent")
        return 2
    sys.path.insert(0, str(python_root))
    try:
        from ishikawa.normalization import (  # pylint: disable=import-outside-toplevel
            NormalizationError,
            normalize_extraction_archive,
            normalized_json_bytes,
        )

        normalized = normalize_extraction_archive(
            arguments.archive,
            arguments.source_manifest,
            expected_archive_sha256=arguments.expected_archive_sha256,
        )
        payload = normalized_json_bytes(normalized)
        descriptor = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(payload)
    except NormalizationError as exc:
        print(f"normalization=blocked;reason={exc}")
        return 1
    except (OSError, ValueError) as exc:
        print(f"normalization=blocked;reason=bounded_runtime_failure;error_type={type(exc).__name__}")
        return 1

    documents = normalized["documents"]
    units = [unit for document in documents for unit in document["units"]]
    kinds: dict[str, int] = {}
    for unit in units:
        kinds[unit["kind"]] = kinds.get(unit["kind"], 0) + 1
    print("purpose=normalize_pdf_extraction_and_create_structural_units")
    print(
        f"documents={len(documents)};pages={sum(item['page_count'] for item in documents)};"
        f"blank_pages={sum(len(item['blank_pages']) for item in documents)}"
    )
    print(
        f"structural_units={len(units)};headings={kinds.get('heading', 0)};"
        f"paragraphs={kinds.get('paragraph', 0)};list_items={kinds.get('list_item', 0)};"
        f"definitions={kinds.get('definition', 0)}"
    )
    print(
        f"tables={kinds.get('table', 0)};form_fields={kinds.get('form_field', 0)};"
        f"checkbox_groups={kinds.get('checkbox_group', 0)};page_furniture={kinds.get('page_furniture', 0)}"
    )
    print(f"normalization_set_digest={normalized['normalization_set_digest']}")
    print(f"artifact_sha256={hashlib.sha256(payload).hexdigest()};artifact_bytes={len(payload)}")
    print("normalization=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
