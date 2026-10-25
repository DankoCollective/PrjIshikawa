#!/usr/bin/env python3
"""Prove an isolated corpus-v3 publication equals the frozen v6 representation."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path
from typing import Any


EXPECTED_EMBEDDING_SPACE_ID = (
    "fd970d304662357a07f7712639bdc0c70cc7e72b22f04c126acce57a6f9143a3"
)
EXPECTED_CHUNK_PROFILE_ID = (
    "d72a07f81eabc1f521ab1fd54f84289979365c6c71f8e3220a53b1e8c9a1c037"
)
POSTGRESQL_SQLSTATE_REASONS = {
    "08001": "postgresql_connection_establishment_failure",
    "08003": "postgresql_connection_absent",
    "08006": "postgresql_connection_failure",
    "23502": "postgresql_not_null_violation",
    "23503": "postgresql_foreign_key_violation",
    "23505": "postgresql_unique_violation",
    "23514": "postgresql_check_violation",
    "40001": "postgresql_serialization_failure",
    "40P01": "postgresql_deadlock_detected",
    "42501": "postgresql_insufficient_privilege",
    "42703": "postgresql_undefined_column",
    "42P01": "postgresql_undefined_table",
    "53300": "postgresql_too_many_connections",
    "57P01": "postgresql_admin_shutdown",
}


class QualificationError(RuntimeError):
    """Stable isolated-publication qualification failure."""


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise QualificationError(reason)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_json(path: Path, expected: str, label: str) -> dict[str, Any]:
    require(
        path.is_absolute()
        and path.is_file()
        and not path.is_symlink()
        and sha256(path) == expected,
        f"{label}_identity_invalid",
    )
    try:
        value = json.loads(path.read_text(encoding="utf-8", errors="strict"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise QualificationError(f"{label}_invalid") from error
    require(isinstance(value, dict), f"{label}_invalid")
    return value


def canonical(value: Any) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, separators=(",", ":"), sort_keys=True
    ).encode("utf-8")


def write_exclusive(path: Path, payload: bytes) -> None:
    require(
        path.is_absolute()
        and not path.exists()
        and not path.is_symlink()
        and path.parent.is_dir()
        and not path.parent.is_symlink(),
        "output_unsafe",
    )
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)


def execute(arguments: argparse.Namespace) -> None:
    chunks = load_json(
        arguments.chunks, arguments.expected_chunks_sha256, "chunks"
    )
    truth = load_json(
        arguments.corpus_truth, arguments.expected_corpus_truth_sha256, "corpus_truth"
    )
    receipt = load_json(
        arguments.bundle_receipt,
        arguments.expected_bundle_receipt_sha256,
        "bundle_receipt",
    )
    require(
        chunks.get("method_profile_id") == EXPECTED_CHUNK_PROFILE_ID
        and len(chunks.get("documents", [])) == 30
        and truth.get("corpus_identity") == "synthetic-corpus-v3"
        and len(truth.get("relationships", [])) == 90
        and receipt.get("corpus_identity") == "synthetic-corpus-v3"
        and receipt.get("document_count") == 30
        and receipt.get("page_count") == 150
        and receipt.get("relationship_pair_count") == 90
        and receipt.get("persistent_flat_file_index") is False,
        "input_contract_invalid",
    )
    key_map = receipt.get("document_keys")
    require(
        isinstance(key_map, dict)
        and set(key_map) == {f"SYN-V3-{index:03d}" for index in range(1, 31)},
        "document_key_map_invalid",
    )
    truth_documents = {item["doc_id"]: item for item in truth["documents"]}
    expected_candidates: dict[tuple[str, int], dict[str, Any]] = {}
    for document in chunks["documents"]:
        document_ref = document.get("document_ref")
        require(document_ref in key_map, "chunk_document_ref_invalid")
        document_key = key_map[document_ref]
        for ordinal, candidate in enumerate(document.get("candidates", [])):
            producer_id = candidate.get("chunk_id")
            require(
                isinstance(producer_id, str)
                and (document_key, ordinal) not in expected_candidates,
                "candidate_identity_invalid",
            )
            expected_candidates[(document_key, ordinal)] = candidate
    scoring_only = sum(
        item["projection_properties"].get("retrieval_scoring_only") is True
        for item in expected_candidates.values()
    )
    require(
        len(expected_candidates) == 943 and scoring_only == 157,
        "candidate_inventory_invalid",
    )

    password = os.environ.pop("ISHIKAWA_POSTGRESQL_PASSWORD", "")
    require(
        1 <= len(password) <= 4096 and "\n" not in password and "\r" not in password,
        "database_credential_invalid",
    )
    try:
        import psycopg

        connection = psycopg.connect(
            host=str(arguments.postgresql_socket),
            port=arguments.postgresql_port,
            dbname="rag_catalog",
            user="rag_retrieval",
            password=password,
            connect_timeout=5,
        )
    except Exception as error:
        raise QualificationError("database_connection_failed") from error
    finally:
        password = ""

    try:
        connection.execute("BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
        boundary = connection.execute(
            "SELECT current_user, current_database(), current_setting('transaction_read_only'), current_setting('transaction_isolation')"
        ).fetchone()
        require(
            boundary == ("rag_retrieval", "rag_catalog", "on", "repeatable read"),
            "database_boundary_invalid",
        )
        inventory = connection.execute(
            """SELECT
                 (SELECT count(*) FROM rag_search.active_documents),
                 (SELECT coalesce(sum(page_count), 0) FROM rag_search.active_documents),
                 (SELECT count(*) FROM rag_search.active_chunks),
                 (SELECT count(*) FROM rag_search.active_citations),
                 (SELECT count(*) FROM rag_search.active_embeddings),
                 (SELECT count(*) FROM rag_search.active_retrieval_candidates),
                 (SELECT count(*) FROM rag_search.active_retrieval_candidates WHERE retrieval_scoring_only),
                 (SELECT count(*) FROM rag_search.active_retrieval_embeddings),
                 (SELECT count(*) FROM rag_search.active_relationships),
                 (SELECT count(*) FROM (
                    SELECT DISTINCT source_document_id, target_identity
                    FROM rag_search.active_relationships
                  ) pairs)"""
        ).fetchone()
        require(
            inventory[:8] == (30, 150, 786, 786, 786, 943, 157, 943)
            and inventory[8] >= 90
            and inventory[9] == 90,
            "database_inventory_invalid",
        )
        documents = connection.execute(
            """SELECT document_id, document_key, display_name, page_count,
                      method_profile_id
               FROM rag_search.active_documents
               ORDER BY document_key"""
        ).fetchall()
        actual_by_key = {row[1]: row for row in documents}
        require(set(actual_by_key) == set(key_map.values()), "document_key_inventory_invalid")
        for document_ref, key in key_map.items():
            row = actual_by_key[key]
            expected = truth_documents[document_ref]
            require(
                row[2] == expected["title"]
                and row[3] == expected["pages"] == 5
                and row[4] == EXPECTED_CHUNK_PROFILE_ID,
                "document_metadata_mismatch",
            )

        rows = connection.execute(
            """SELECT candidate.document_key, candidate.projection_kind,
                      candidate.ordinal, candidate.retrieval_text,
                      candidate.retrieval_filters, candidate.client_metadata,
                      candidate.total_embedding_token_count,
                      candidate.retrieval_scoring_only,
                      candidate.structural_path,
                      vector_dims(embedding.embedding),
                      embedding.embedding_space_id
               FROM rag_search.active_retrieval_candidates candidate
               JOIN rag_search.active_retrieval_embeddings embedding
                 ON embedding.chunk_id = candidate.chunk_id
               ORDER BY candidate.document_key, candidate.ordinal"""
        ).fetchall()
        require(len(rows) == 943, "retrieval_candidate_inventory_invalid")
        seen_slots: set[tuple[str, int]] = set()
        seen_producer_ids: set[str] = set()
        for row in rows:
            metadata = row[5]
            producer_id = (
                metadata.get("producer_chunk_id") if isinstance(metadata, dict) else None
            )
            slot = (row[0], row[2])
            candidate = expected_candidates.get(slot)
            require(
                candidate is not None
                and slot not in seen_slots
                and isinstance(producer_id, str)
                and len(producer_id) == 64
                and all(character in "0123456789abcdef" for character in producer_id)
                and producer_id not in seen_producer_ids,
                "producer_candidate_identity_mismatch",
            )
            expected_scoring = (
                candidate["projection_properties"].get("retrieval_scoring_only") is True
            )
            require(
                row[1] == candidate["projection_kind"]
                and row[3] == candidate["retrieval_text"]
                and row[4] == candidate["retrieval_filters"]
                and type(row[6]) is int
                and 1 <= row[6] <= 2048
                and row[7] is expected_scoring
                and list(row[8]) == candidate["citation_anchor"]["structural_path"]
                and row[9] == 768
                and row[10] == EXPECTED_EMBEDDING_SPACE_ID,
                "persisted_candidate_mismatch",
            )
            seen_slots.add(slot)
            seen_producer_ids.add(producer_id)
        require(
            seen_slots == set(expected_candidates) and len(seen_producer_ids) == 943,
            "producer_candidate_coverage_incomplete",
        )

        actual_pairs = {
            (row[0], row[1])
            for row in connection.execute(
                """SELECT source.document_key, target.document_key
                   FROM rag_search.active_relationships relationship
                   JOIN rag_search.active_documents source
                     ON source.document_id = relationship.source_document_id
                   JOIN rag_search.active_documents target
                     ON target.document_id = relationship.target_identity"""
            ).fetchall()
        }
        expected_pairs = {
            (key_map[item["source_doc_id"]], key_map[item["target_doc_id"]])
            for item in truth["relationships"]
        }
        require(
            len(expected_pairs) == 90 and actual_pairs == expected_pairs,
            "relationship_pair_inventory_mismatch",
        )
        connection.execute("ROLLBACK")
    finally:
        connection.close()

    artifact = {
        "artifact_kind": "ishikawa_isolated_synthetic_corpus_v3_database_qualification",
        "schema_version": 1,
        "corpus_identity": "synthetic-corpus-v3",
        "chunk_profile_id": EXPECTED_CHUNK_PROFILE_ID,
        "embedding_space_id": EXPECTED_EMBEDDING_SPACE_ID,
        "inventory": {
            "documents": 30,
            "pages": 150,
            "authoritative_chunks": 786,
            "retrieval_candidates": 943,
            "retrieval_scoring_only": 157,
            "relationship_pairs": 90,
            "relationship_records": inventory[8],
        },
        "checks": {
            "candidate_identity_and_text": "943/943",
            "embeddings_present": "943/943",
            "relationship_pairs": "90/90",
            "postgresql_read_only_boundary": True,
            "runtime_flat_file_index": False,
        },
        "status": "pass",
    }
    payload = canonical(artifact) + b"\n"
    write_exclusive(arguments.output, payload)
    print(
        "isolated_synthetic_corpus_v3_database=pass;documents=30;pages=150;"
        "authoritative_chunks=786;retrieval_candidates=943;representatives=157;"
        f"relationship_records={inventory[8]};relationship_pairs=90"
    )
    print(f"artifact_sha256={hashlib.sha256(payload).hexdigest()}")


def main() -> int:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--chunks", type=Path)
    parser.add_argument("--expected-chunks-sha256")
    parser.add_argument("--corpus-truth", type=Path)
    parser.add_argument("--expected-corpus-truth-sha256")
    parser.add_argument("--bundle-receipt", type=Path)
    parser.add_argument("--expected-bundle-receipt-sha256")
    parser.add_argument("--postgresql-socket", type=Path)
    parser.add_argument("--postgresql-port", type=int, default=65438)
    parser.add_argument("--output", type=Path)
    arguments = parser.parse_args()
    require(arguments.self_test != arguments.run, "mode_invalid")
    if arguments.self_test:
        require(
            len(EXPECTED_CHUNK_PROFILE_ID) == 64
            and len(EXPECTED_EMBEDDING_SPACE_ID) == 64,
            "self_test_failed",
        )
        print("isolated_synthetic_corpus_v3_database_self_test=pass")
        return 0
    required = (
        arguments.chunks,
        arguments.expected_chunks_sha256,
        arguments.corpus_truth,
        arguments.expected_corpus_truth_sha256,
        arguments.bundle_receipt,
        arguments.expected_bundle_receipt_sha256,
        arguments.postgresql_socket,
        arguments.output,
    )
    require(all(required), "argument_missing")
    require(1024 <= arguments.postgresql_port <= 65535, "postgresql_port_invalid")
    execute(arguments)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except QualificationError as error:
        print(f"isolated_synthetic_corpus_v3_database=blocked;reason={error}", file=sys.stderr)
        raise SystemExit(1)
    except Exception as error:
        reason = POSTGRESQL_SQLSTATE_REASONS.get(
            getattr(error, "sqlstate", None),
            f"qualification_unexpected_{type(error).__name__}",
        )
        print(
            "isolated_synthetic_corpus_v3_database=blocked;"
            f"reason={reason}",
            file=sys.stderr,
        )
        raise SystemExit(1)
