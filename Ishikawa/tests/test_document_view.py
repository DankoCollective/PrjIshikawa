from __future__ import annotations

import json
import unittest

from ishikawa.canonical import canonical_json_bytes
from ishikawa.document_view import (
    DocumentViewContractError,
    DocumentViewNotAvailable,
    NativePostgresDocumentReader,
    decode_document_view_request,
)
from ishikawa.retrieval_service import RetrievalServiceContractError


def ident(character: str) -> str:
    return character * 64


class _Result:
    def __init__(self, value):
        self.value = value

    def fetchone(self):
        return self.value

    def fetchall(self):
        return self.value


class _Connection:
    def __init__(self, rows, role="rag_retrieval"):
        self.rows = rows
        self.role = role
        self.calls = []
        self.rolled_back = False
        self.closed = False

    def execute(self, sql, parameters=()):
        self.calls.append((sql, parameters))
        if "document-view.boundary" in sql:
            return _Result((self.role, "on", "repeatable read"))
        if "document-view.active-version" in sql:
            return _Result(self.rows)
        return _Result(None)

    def rollback(self):
        self.rolled_back = True

    def close(self):
        self.closed = True


def _rows():
    common = (
        ident("b"),
        "policy.controlled-materials",
        "Controlled Materials Access Policy",
        "policy_sop",
        3,
    )
    return [
        (
            ident("1"), *common, "paragraph", 1,
            "Policy Number: 99 TST 2001.", 1, 1,
            ["I. Purpose and Scope"], "Policy Number: 99 TST 2001.",
        ),
        (
            ident("2"), *common, "paragraph", 2,
            "This policy establishes synthetic controls.", 1, 1,
            ["I. Purpose and Scope"], "This policy establishes synthetic controls.",
        ),
        (
            ident("3"), *common, "procedure_step", 3,
            "The requester submits the approved form.", 2, 2,
            ["II. Procedure", "Step 1"], "The requester submits the approved form.",
        ),
    ]


class DocumentViewTests(unittest.TestCase):
    def request(self, *, offset=0, limit=1):
        return decode_document_view_request(
            canonical_json_bytes(
                {
                    "schema": "ishikawa.document-view-request.v1",
                    "section_limit": limit,
                    "section_offset": offset,
                    "source_id": ident("b"),
                }
            )
        )

    def test_request_is_exact_bounded_and_duplicate_safe(self):
        request = self.request()
        self.assertEqual(request.source_id, ident("b"))
        self.assertEqual(request.section_limit, 1)
        with self.assertRaises(DocumentViewContractError):
            decode_document_view_request(
                b'{"schema":"ishikawa.document-view-request.v1",'
                b'"source_id":"' + ident("b").encode() + b'",'
                b'"section_offset":0,"section_limit":1,"section_limit":2}'
            )

    def test_reader_reconstructs_sections_in_ordinal_order_and_pages(self):
        connection = _Connection(list(reversed(_rows())))
        response = json.loads(
            NativePostgresDocumentReader(lambda: connection)(self.request())
        )
        self.assertEqual(response["source"]["document_identifier"], "99 TST 2001")
        self.assertEqual(response["source"]["page_count"], 3)
        self.assertEqual(response["schema"], "ishikawa.document-view-response.v2")
        self.assertEqual(response["total_sections"], 2)
        self.assertEqual(response["sections"][0]["heading"], "I. Purpose and Scope")
        self.assertEqual(len(response["sections"][0]["units"]), 2)
        self.assertEqual(response["next_section_offset"], 1)
        self.assertFalse(response["complete"])
        self.assertTrue(connection.rolled_back)
        self.assertTrue(connection.closed)
        sql = "\n".join(item[0] for item in connection.calls)
        self.assertIn("REPEATABLE READ READ ONLY", sql)
        self.assertIn("rag_search.active_chunks", sql)

    def test_next_page_returns_second_section_and_exact_active_version_only(self):
        response = json.loads(
            NativePostgresDocumentReader(lambda: _Connection(_rows()))(
                self.request(offset=1, limit=1)
            )
        )
        self.assertEqual(response["sections"][0]["heading"], "II. Procedure")
        self.assertTrue(response["complete"])
        self.assertIsNone(response["next_section_offset"])

    def test_missing_version_and_wrong_role_fail_closed(self):
        with self.assertRaises(DocumentViewNotAvailable):
            NativePostgresDocumentReader(lambda: _Connection([]))(self.request())
        with self.assertRaises(RetrievalServiceContractError):
            NativePostgresDocumentReader(
                lambda: _Connection(_rows(), role="rag_owner")
            )(self.request())


if __name__ == "__main__":
    unittest.main()
