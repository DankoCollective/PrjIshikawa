#!/usr/bin/env python3
"""Persist and traverse qualified relationships in a disposable database."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import psycopg

from ishikawa.artifact_adapter import load_prepared_documents
from ishikawa.persistence import write_incremental_plan
from ishikawa.planner import plan_ingestion
from ishikawa.relationships import (
    TraversalEdge,
    discover_prepared_relationships,
    expand_one_hop,
    validate_relationship_registry,
)
from ishikawa.validators import (
    validate_class_registry,
    validate_document_catalog,
    validate_ingestion_manifest,
)
from ishikawa.yaml_loader import load_restricted_yaml


METHOD_PROFILE_ID = "5797961aee919aa73bbd99d6cc188084d57d22839a1d4cff0febc2e73e17b4b0"
RELATIONSHIP_REGISTRY_ID = "0211fc5adc842faba0f18ffe4ca92c1cda9f53a9447efcb2ccabab4ccd4b2e77"
RELATIONSHIP_METHOD_PROFILE_ID = "d16d72726a5548af1b1abd3d2ca7a35da5a6b805d8d26c3369a2c35c78a8f76d"


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise RuntimeError(reason)


def scalar(connection: psycopg.Connection, query: str, parameters=()):
    row = connection.execute(query, parameters).fetchone()
    if row is None:
        raise RuntimeError("required query returned no row")
    return row[0]


def load_json(path: Path) -> object:
    require(path.is_file() and not path.is_symlink(), "unsafe JSON input")
    return json.loads(path.read_text(encoding="utf-8"))


def expected_truth(truth: dict, manifest) -> set[tuple[str, int, str]]:
    filename_to_key = {item.source_path: item.document_key for item in manifest.documents}
    truth_ref_to_key = {}
    for document in truth["documents"]:
        truth_ref_to_key[document["doc_id"]] = filename_to_key[document["filename"]]
    expected = set()
    for edge in truth["cross_references"]:
        source_ref, page = edge["from"].rsplit(":", 1)
        target_ref, _ = edge["to"].rsplit(":", 1)
        expected.add((truth_ref_to_key[source_ref], int(page), truth_ref_to_key[target_ref]))
    return expected


def main() -> int:
    if len(sys.argv) != 10 or not sys.argv[1].startswith("ishikawa_relationship_test"):
        raise RuntimeError("one safe disposable database and eight payload paths are required")
    database = sys.argv[1]
    config_root = Path(sys.argv[2])
    source_root = Path(sys.argv[3])
    normalized_path = Path(sys.argv[4])
    chunk_path = Path(sys.argv[5])
    embedding_path = Path(sys.argv[6])
    identity_path = Path(sys.argv[7])
    relationship_registry_path = Path(sys.argv[8])
    truth_path = Path(sys.argv[9])
    identities = dict(
        line.split("  ", 1)[::-1]
        for line in identity_path.read_text(encoding="ascii").splitlines()
        if line
    )

    registry = validate_class_registry(
        load_restricted_yaml(config_root / "document_classes.yaml", label="class registry")
    )
    catalog = validate_document_catalog(
        load_restricted_yaml(config_root / "document_catalog.yaml", label="document catalog")
    )
    manifest = validate_ingestion_manifest(
        load_restricted_yaml(config_root / "ingestion_manifest.yaml", label="ingestion manifest")
    )
    relationship_registry = validate_relationship_registry(
        load_restricted_yaml(relationship_registry_path, label="relationship registry")
    )
    require(relationship_registry.digest == RELATIONSHIP_REGISTRY_ID, "relationship registry mismatch")
    require(
        relationship_registry.method_profile_id == RELATIONSHIP_METHOD_PROFILE_ID,
        "relationship method profile mismatch",
    )
    truth = load_json(truth_path)
    require(isinstance(truth, dict) and truth.get("schema_version") == 1, "truth contract mismatch")
    prepared = load_prepared_documents(
        normalized_path=normalized_path,
        normalized_sha256=identities[normalized_path.name],
        chunk_path=chunk_path,
        chunk_sha256=identities[chunk_path.name],
        embedding_path=embedding_path,
        embedding_sha256=identities[embedding_path.name],
        manifest=manifest,
        source_root=source_root,
    )
    observations = discover_prepared_relationships(
        prepared,
        method_profile_id=METHOD_PROFILE_ID,
        registry=relationship_registry,
    )
    accepted = tuple(item for item in observations if item.outcome == "accepted")
    ignored = tuple(item for item in observations if item.outcome == "ignored")
    require(len(observations) == 44, "relationship observation count mismatch")
    require(len(accepted) == 27 and len(ignored) == 17, "relationship outcome count mismatch")
    require(not any(item.requires_quarantine for item in observations), "unresolved relationship found")

    connection_info = f"dbname={database} host=/var/run/postgresql port=5432 user=postgres"
    with psycopg.connect(connection_info, autocommit=True) as connection:
        connection.execute("SET ROLE rag_ingest")
        plan = plan_ingestion(
            registry,
            catalog,
            manifest,
            source_root=source_root,
            method_profile_id=METHOD_PROFILE_ID,
            published_state={},
            prior_catalog_keys=set(),
        )
        require(plan.overall_outcome == "PASS", "initial validation plan failed")
        result = write_incremental_plan(
            connection,
            registry,
            catalog,
            manifest,
            plan,
            prepared,
            relationship_registry=relationship_registry,
            relationship_observations=observations,
        )
        require(
            result.outcome == "PUBLISHED" and result.published_document_count == 6,
            "relationship publication failed",
        )
        require(scalar(connection, "SELECT count(*) FROM rag.relationship_types") == 3, "type count mismatch")
        require(scalar(connection, "SELECT count(*) FROM rag.relationships") == 27, "edge count mismatch")
        require(
            scalar(
                connection,
                "SELECT count(*) FROM rag.relationships WHERE relationship_definition_version=%s",
                (relationship_registry.digest,),
            ) == 27,
            "relationship registry provenance mismatch",
        )
        require(
            scalar(
                connection,
                "SELECT count(*) FROM rag.relationships WHERE detection_method<>'deterministic' OR override_audit_identity IS NOT NULL OR override_reason_code IS NOT NULL",
            ) == 0,
            "deterministic relationship audit columns mismatch",
        )
        require(
            scalar(
                connection,
                """SELECT count(*) FROM rag.relationships r
                   LEFT JOIN rag.structural_units su
                     ON su.structural_unit_id=r.source_identity
                    AND su.artifact_set_id=r.artifact_set_id
                   WHERE r.source_kind='structural_unit' AND su.structural_unit_id IS NULL""",
            ) == 0,
            "relationship structural source integrity mismatch",
        )

    expected = expected_truth(truth, manifest)
    with psycopg.connect(connection_info, autocommit=True) as retrieval:
        retrieval.execute("SET ROLE rag_retrieval")
        require(
            scalar(retrieval, "SELECT count(*) FROM rag_search.active_relationships") == 27,
            "active relationship count mismatch",
        )
        rows = retrieval.execute(
            """/* ishikawa.relationship-held-out-coverage */
            SELECT source.document_key, citation.page_start, target.document_key
            FROM rag_search.active_relationships relationship
            JOIN rag_search.active_documents source
              ON source.document_id=relationship.source_document_id
            JOIN rag_search.active_citations citation
              ON citation.citation_id=relationship.evidence_citation_id
            JOIN rag_search.active_documents target
              ON target.document_id=relationship.target_identity
            WHERE relationship.relationship_type='explicit_reference.document'
            ORDER BY source.document_key, citation.page_start, target.document_key
            """
        ).fetchall()
        actual = set(rows)
        require(expected <= actual and len(expected) == 5, "held-out relationship coverage mismatch")

        documents = {
            key: (document_id, version_id)
            for document_id, key, version_id in retrieval.execute(
                "SELECT document_id, document_key, document_version_id FROM rag_search.active_documents"
            ).fetchall()
        }
        traversal_covered = 0
        for source_key, _page, target_key in sorted(expected):
            source_id = documents[source_key][0]
            edge_rows = retrieval.execute(
                """/* ishikawa.relationship-one-hop */
                SELECT relationship.relationship_id, relationship.relationship_type,
                       relationship.source_document_id, relationship.target_identity,
                       target.document_version_id, relationship.evidence_citation_id
                FROM rag_search.active_relationships relationship
                JOIN rag_search.active_documents target
                  ON target.document_id=relationship.target_identity
                WHERE relationship.source_document_id=%s
                  AND relationship.influences_retrieval=true
                  AND relationship.relationship_type='explicit_reference.document'
                ORDER BY relationship.relationship_id, relationship.target_identity
                """,
                (source_id,),
            ).fetchall()
            traversal_edges = tuple(TraversalEdge(*row) for row in edge_rows)
            expanded = expand_one_hop(
                (source_id,),
                traversal_edges,
                allowed_document_identities={item[0] for item in documents.values()},
                registry=relationship_registry,
            )
            if documents[target_key][0] in {item.target_document_identity for item in expanded}:
                traversal_covered += 1
        require(traversal_covered == 5, "one-hop traversal coverage mismatch")

        denied = False
        try:
            retrieval.execute("SELECT count(*) FROM rag.relationships").fetchone()
        except psycopg.errors.InsufficientPrivilege:
            denied = True
        require(denied, "retrieval role read relationship base table")

    print("runner_purpose=test_relationship_persistence_with_disposable_native_postgresql")
    print("synthetic_documents=6;organizational_documents=0")
    print("prepared_chunks=126;relationship_observations=44")
    print("accepted_internal_edges=27;ignored_self_references=17;unresolved_references=0")
    print("relationship_types=3;persisted_relationships=27;active_relationships=27")
    print(f"relationship_registry_id={relationship_registry.digest}")
    print(f"relationship_method_profile_id={relationship_registry.method_profile_id}")
    print("override_audit_columns=present;deterministic_rows_with_override_data=0")
    print("held_out_relationships=5;held_out_relationships_covered=5")
    print("maximum_hops=1;held_out_traversals_covered=5")
    print("retrieval_role_active_view_read=pass;retrieval_role_base_table_read=denied")
    print("relationship_persistence_foundation=pass")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(
            "relationship_persistence_foundation=blocked;"
            f"reason={type(error).__name__}",
            file=sys.stderr,
        )
        raise
