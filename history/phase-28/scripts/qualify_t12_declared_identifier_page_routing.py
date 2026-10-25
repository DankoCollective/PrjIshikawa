#!/usr/bin/env python3
"""Qualify T12 against retained ranks and the active read-only corpus."""

from __future__ import annotations

import argparse
import json
import os
import sys
from fractions import Fraction
from pathlib import Path


T12_CASES = {
    "E-034": 2,
    "E-036": 3,
    "E-040": 5,
    "E-046": 8,
    "E-052": 11,
}
EXPECTED_CURRENT_RANKS = {
    "E-034": 10,
    "E-036": 3,
    "E-040": 7,
    "E-046": 16,
    "E-052": 3,
}
EXPECTED_PROJECTED_MRR = Fraction(6619, 7200)


def _projected_mrr(path: Path) -> Fraction:
    value = json.loads(path.read_text(encoding="utf-8"))
    cases = value.get("cases")
    if (
        value.get("artifact_kind") != "ishikawa_extended_retrieval_lane_ranking_observation"
        or value.get("schema_version") != 1
        or value.get("case_count") != 60
        or not isinstance(cases, list)
        or len(cases) != 60
    ):
        raise ValueError("lane observation contract is invalid")
    ranks: list[int] = []
    observed_t12: dict[str, int] = {}
    for item in cases:
        if not isinstance(item, dict):
            raise ValueError("lane observation case is invalid")
        case_id = item.get("case_id")
        rank = item.get("current_first_relevant_rank")
        if not isinstance(case_id, str) or type(rank) is not int or not 1 <= rank <= 20:
            raise ValueError("lane observation rank is invalid")
        if case_id in T12_CASES:
            observed_t12[case_id] = rank
            rank = 1
        ranks.append(rank)
    if observed_t12 != EXPECTED_CURRENT_RANKS:
        raise ValueError("T12 source ranks changed")
    return sum((Fraction(1, rank) for rank in ranks), start=Fraction()) / len(ranks)


def _self_test() -> None:
    if T12_CASES != {"E-034": 2, "E-036": 3, "E-040": 5, "E-046": 8, "E-052": 11}:
        raise AssertionError("T12 case boundary changed")
    if EXPECTED_PROJECTED_MRR <= Fraction(91, 100):
        raise AssertionError("projected strict target is not met")
    print("t12_declared_identifier_page_routing_self_test=pass")


def _run(python_root: Path, observation: Path) -> None:
    password = os.environ.get("ISHIKAWA_POSTGRESQL_PASSWORD", "")
    if not password:
        raise ValueError("postgresql credential is unavailable")
    sys.path.insert(0, str(python_root.resolve()))
    import psycopg  # type: ignore[import-not-found]
    from ishikawa.retrieval import exact_document_page_lookup

    projected = _projected_mrr(observation)
    if projected != EXPECTED_PROJECTED_MRR:
        raise ValueError("T12 projected MRR changed")

    connection = psycopg.connect(
        host="127.0.0.1",
        port=5432,
        dbname="rag_catalog",
        user="rag_retrieval",
        password=password,
        connect_timeout=5,
        application_name="ishikawa-t12-qualification",
        options="-c default_transaction_read_only=on",
    )
    try:
        connection.execute(
            "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY"
        )
        boundary = connection.execute(
            """SELECT current_user,
                      current_setting('transaction_read_only'),
                      current_setting('transaction_isolation')"""
        ).fetchone()
        if boundary != ("rag_retrieval", "on", "repeatable read"):
            raise ValueError("database boundary is invalid")
        inventory = connection.execute(
            """SELECT
                 (SELECT count(*) FROM rag_search.active_documents),
                 (SELECT count(*) FROM rag_search.active_chunks),
                 (SELECT count(*) FROM rag_search.active_citations),
                 (SELECT count(*) FROM rag_search.active_embeddings)"""
        ).fetchone()
        if inventory != (6, 126, 126, 126):
            raise ValueError("active corpus inventory changed")

        routed: dict[str, str] = {}
        for case_id, page in T12_CASES.items():
            candidates = exact_document_page_lookup(
                connection, "99 TST 2005", page, depth=1
            )
            if len(candidates) != 1:
                raise ValueError("declared owner page route did not return one result")
            candidate = candidates[0]
            evidence = connection.execute(
                """SELECT DISTINCT ac.display_name
                   FROM rag_search.active_chunks ac
                   JOIN rag_search.active_citations citation
                     ON citation.chunk_id = ac.chunk_id
                   WHERE ac.chunk_id = %s
                     AND citation.page_start <= %s
                     AND citation.page_end >= %s""",
                (candidate.chunk_id, page, page),
            ).fetchall()
            if evidence != [("Synthetic Governance Manual",)]:
                raise ValueError("declared owner page evidence is incorrect")
            routed[case_id] = candidate.chunk_id
        if len(routed) != 5 or len(set(routed.values())) != 5:
            raise ValueError("T12 route coverage is incomplete")
        if exact_document_page_lookup(connection, "99 TST 9999", 1, depth=1):
            raise ValueError("unknown declaration was guessed")
    finally:
        try:
            connection.rollback()
        finally:
            connection.close()

    print(
        "declared_identifier=99_TST_2005;unique_owner=true;"
        "page_routes=5/5;unknown_owner_fallback=true"
    )
    print(
        "projected_mrr_at_20=0.919306;projected_fraction=6619/7200;"
        "strict_target=greater_than_0.91;fresh_measurement_required=true"
    )
    print(
        "database_boundary=repeatable_read_read_only;database_write=false;"
        "nomic_contact=false;gemma_contact=false"
    )
    print("t12_declared_identifier_page_routing=pass")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--project", action="store_true")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--python-root", type=Path)
    parser.add_argument("--observation", type=Path)
    args = parser.parse_args()
    if sum((args.self_test, args.project, args.run)) != 1:
        parser.error("select exactly one mode")
    try:
        if args.self_test:
            _self_test()
        elif args.project:
            if args.observation is None:
                parser.error("--project requires --observation")
            projected = _projected_mrr(args.observation)
            if projected != EXPECTED_PROJECTED_MRR:
                raise ValueError("T12 projected MRR changed")
            print(
                "projected_mrr_at_20=0.919306;projected_fraction=6619/7200;"
                "strict_target=greater_than_0.91;fresh_measurement_required=true"
            )
        else:
            if args.python_root is None or args.observation is None:
                parser.error("--run requires --python-root and --observation")
            _run(args.python_root, args.observation)
    except Exception as error:
        print(
            f"t12_declared_identifier_page_routing=blocked;"
            f"reason={type(error).__name__}",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
