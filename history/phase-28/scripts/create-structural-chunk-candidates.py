#!/usr/bin/env python3
"""Create one deterministic structural chunk-candidate artifact."""

from __future__ import annotations

import argparse
import hashlib
import os
import sys
from pathlib import Path


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--expected-input-sha256", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--python-root", required=True)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    python_root = Path(arguments.python_root)
    output = Path(arguments.output)
    if not python_root.is_dir() or python_root.is_symlink():
        print("chunk_candidates=blocked;reason=unsafe_python_root")
        return 2
    if not output.is_absolute() or output.exists() or output.is_symlink():
        print("chunk_candidates=blocked;reason=unsafe_output_path")
        return 2
    if not output.parent.is_dir() or output.parent.is_symlink():
        print("chunk_candidates=blocked;reason=unsafe_output_parent")
        return 2
    sys.path.insert(0, str(python_root))
    try:
        from ishikawa.chunking import (  # pylint: disable=import-outside-toplevel
            ChunkingError,
            build_from_file,
            chunk_candidates_json_bytes,
        )

        artifact = build_from_file(
            arguments.input,
            expected_normalized_sha256=arguments.expected_input_sha256,
        )
        payload = chunk_candidates_json_bytes(artifact)
        descriptor = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(payload)
    except ChunkingError as exc:
        print(f"chunk_candidates=blocked;reason={exc}")
        return 1
    except (KeyError, OSError, TypeError, ValueError) as exc:
        print(
            "chunk_candidates=blocked;reason=bounded_runtime_failure;"
            f"error_type={type(exc).__name__}"
        )
        return 1

    candidates = [
        candidate
        for document in artifact["documents"]
        for candidate in document["candidates"]
    ]
    kinds: dict[str, int] = {}
    for candidate in candidates:
        kind = candidate["projection_kind"]
        kinds[kind] = kinds.get(kind, 0) + 1
    print("purpose=create_structure_aware_chunk_candidates_and_metadata")
    print(
        f"documents={len(artifact['documents'])};chunk_candidates={len(candidates)};"
        f"body_overlap_units={artifact['method_profile']['body_overlap_units']}"
    )
    print(
        f"paragraphs={kinds.get('paragraph', 0)};list_items={kinds.get('list_item', 0)};"
        f"definitions={kinds.get('definition', 0)}"
    )
    print(
        f"table_contexts={kinds.get('table_context', 0)};table_rows={kinds.get('table_row', 0)};"
        f"form_fields={kinds.get('form_field', 0)};checkbox_groups={kinds.get('checkbox_group', 0)}"
    )
    print(f"method_profile_id={artifact['method_profile_id']}")
    print(f"chunk_candidate_set_digest={artifact['chunk_candidate_set_digest']}")
    print(f"artifact_sha256={hashlib.sha256(payload).hexdigest()};artifact_bytes={len(payload)}")
    print(
        "token_measurement=pending_authoritative_nomic_measurement;"
        "publication_eligible=false"
    )
    print("chunk_candidates=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
