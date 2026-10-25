#!/usr/bin/env python3
"""Strictly validate content-free configured live-ingestion evidence."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


METHOD_PROFILE_ID = "5797961aee919aa73bbd99d6cc188084d57d22839a1d4cff0febc2e73e17b4b0"
FIELDS = frozenset({
    "schema_version", "outcome", "method_profile_id", "documents", "pages",
    "structural_units", "chunks", "citations", "embeddings", "embedding_dimension",
    "validation_planned_adds", "published_documents", "reused_documents",
    "database_connections", "live_stage_calls", "artifact_retention_calls",
    "retained_artifact_objects", "accepted_database_changed", "credential_retained",
})
EXPECTED = {
    "schema_version": 1,
    "outcome": "pass",
    "method_profile_id": METHOD_PROFILE_ID,
    "documents": 6,
    "pages": 27,
    "structural_units": 231,
    "chunks": 126,
    "citations": 126,
    "embeddings": 126,
    "embedding_dimension": 768,
    "validation_planned_adds": 6,
    "published_documents": 6,
    "reused_documents": 6,
    "database_connections": 3,
    "live_stage_calls": 1,
    "artifact_retention_calls": 1,
    "retained_artifact_objects": 3,
    "accepted_database_changed": False,
    "credential_retained": False,
}


def load(path: Path) -> dict[str, Any]:
    if not path.is_file() or path.is_symlink() or not 1 <= path.stat().st_size <= 4096:
        raise RuntimeError("qualification_artifact_unsafe")
    pairs = json.loads(
        path.read_text(encoding="utf-8"),
        object_pairs_hook=lambda values: values,
        parse_constant=lambda _value: (_ for _ in ()).throw(ValueError()),
    )
    if not isinstance(pairs, list) or any(not isinstance(item, tuple) or len(item) != 2 for item in pairs):
        raise RuntimeError("qualification_artifact_invalid")
    keys = [item[0] for item in pairs]
    if len(keys) != len(set(keys)):
        raise RuntimeError("qualification_artifact_duplicate_field")
    value = dict(pairs)
    if set(value) != FIELDS or value != EXPECTED:
        raise RuntimeError("qualification_artifact_contract_mismatch")
    return value


def self_test() -> None:
    if set(EXPECTED) != FIELDS or EXPECTED["accepted_database_changed"] is not False:
        raise RuntimeError("evaluator_self_test_failed")
    print("configured_live_ingestion_evaluator_self_test=pass")


def main() -> int:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--artifact", type=Path)
    group.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
        return 0
    value = load(arguments.artifact)
    print("purpose=evaluate_configured_live_ingestion_target")
    print(
        f"documents={value['documents']};pages={value['pages']};"
        f"structural_units={value['structural_units']};chunks={value['chunks']}"
    )
    print(
        f"citations={value['citations']};embeddings={value['embeddings']};"
        f"embedding_dimension={value['embedding_dimension']}"
    )
    print("configured_live_ingestion_target_evaluation=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
