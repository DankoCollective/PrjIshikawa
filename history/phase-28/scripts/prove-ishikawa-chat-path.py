#!/usr/bin/env python3
"""Prove one complete Ishikawa web-to-retrieval chat exchange.

Role:
  Submit one fixed synthetic-corpus question through the loopback Next.js API,
  validate the complete answered-response envelope and citation closure, and
  retain only content-free counts. Raw questions, answers, excerpts, and model
  output are never written to the qualification artifact or terminal.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import tempfile
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Mapping, Sequence


REQUEST_SCHEMA = "ishikawa.chat-request.v1"
RESPONSE_SCHEMA = "ishikawa.chat-response.v1"
QUESTION = "Which checked controls and decision appear on request REQ-0001?"
HEX_IDENTITY = re.compile(r"^[0-9a-f]{64}$")
SOURCE_LABEL = re.compile(r"^Source [1-9][0-9]*$")
CLASS_ID = re.compile(r"^[a-z][a-z0-9_]{1,63}$")
EXPECTED_RESPONSE_FIELDS = frozenset(
    {
        "answer",
        "claims",
        "clarification",
        "conversation_id",
        "error",
        "request_id",
        "schema",
        "sources",
        "status",
        "turn_id",
    }
)


class ChatProofError(ValueError):
    """Stable failure that never includes response content."""


def _exact_mapping(value: Any, fields: frozenset[str], reason: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping) or set(value) != fields:
        raise ChatProofError(reason)
    return value


def _identity(value: Any, reason: str) -> str:
    if not isinstance(value, str) or HEX_IDENTITY.fullmatch(value) is None:
        raise ChatProofError(reason)
    return value


def _bounded_text(value: Any, maximum: int, reason: str) -> str:
    if (
        not isinstance(value, str)
        or not value
        or value != value.strip()
        or len(value) > maximum
        or "\x00" in value
    ):
        raise ChatProofError(reason)
    return value


def _request(conversation_id: str, turn_id: str) -> bytes:
    value = {
        "conversation_id": conversation_id,
        "filters": {"document_classes": [], "document_keys": []},
        "history": [],
        "message": QUESTION,
        "schema": REQUEST_SCHEMA,
        "source_references": [],
        "turn_id": turn_id,
    }
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode(
        "utf-8"
    )


def _validate_response(
    value: Any,
    *,
    conversation_id: str,
    turn_id: str,
) -> dict[str, int | str | bool]:
    root = _exact_mapping(value, EXPECTED_RESPONSE_FIELDS, "response_fields_invalid")
    if (
        root["schema"] != RESPONSE_SCHEMA
        or root["status"] != "answered"
        or root["conversation_id"] != conversation_id
        or root["turn_id"] != turn_id
        or root["clarification"] is not None
        or root["error"] is not None
    ):
        raise ChatProofError("response_identity_or_status_invalid")
    _identity(root["request_id"], "response_request_id_invalid")
    answer = _bounded_text(root["answer"], 131072, "response_answer_invalid")

    sources = root["sources"]
    claims = root["claims"]
    if not isinstance(sources, list) or not 1 <= len(sources) <= 20:
        raise ChatProofError("response_sources_invalid")
    if not isinstance(claims, list) or not 1 <= len(claims) <= 64:
        raise ChatProofError("response_claims_invalid")

    source_ids: set[str] = set()
    source_labels: set[str] = set()
    citation_ids: set[str] = set()
    excerpt_count = 0
    for source_value in sources:
        source = _exact_mapping(
            source_value,
            frozenset(
                {"display_name", "document_class", "excerpts", "source_id", "source_label"}
            ),
            "response_source_invalid",
        )
        source_id = _identity(source["source_id"], "response_source_id_invalid")
        source_label = source["source_label"]
        if not isinstance(source_label, str) or SOURCE_LABEL.fullmatch(source_label) is None:
            raise ChatProofError("response_source_label_invalid")
        if source_id in source_ids or source_label in source_labels:
            raise ChatProofError("response_source_duplicate")
        source_ids.add(source_id)
        source_labels.add(source_label)
        _bounded_text(source["display_name"], 512, "response_display_name_invalid")
        if (
            not isinstance(source["document_class"], str)
            or CLASS_ID.fullmatch(source["document_class"]) is None
        ):
            raise ChatProofError("response_document_class_invalid")
        excerpts = source["excerpts"]
        if not isinstance(excerpts, list) or not 1 <= len(excerpts) <= 20:
            raise ChatProofError("response_excerpts_invalid")
        for excerpt_value in excerpts:
            excerpt = _exact_mapping(
                excerpt_value,
                frozenset(
                    {
                        "anchor",
                        "citation_id",
                        "excerpt",
                        "page_end",
                        "page_start",
                        "structural_path",
                    }
                ),
                "response_excerpt_invalid",
            )
            citation_id = _identity(excerpt["citation_id"], "response_citation_id_invalid")
            if citation_id in citation_ids:
                raise ChatProofError("response_citation_duplicate")
            citation_ids.add(citation_id)
            _bounded_text(excerpt["excerpt"], 262144, "response_excerpt_invalid")
            if (
                type(excerpt["page_start"]) is not int
                or type(excerpt["page_end"]) is not int
                or excerpt["page_start"] < 1
                or excerpt["page_end"] < excerpt["page_start"]
                or not isinstance(excerpt["structural_path"], list)
                or any(
                    not isinstance(item, str) or not item.strip()
                    for item in excerpt["structural_path"]
                )
            ):
                raise ChatProofError("response_excerpt_location_invalid")
            anchor = excerpt["anchor"]
            if anchor is not None:
                anchor = _exact_mapping(
                    anchor, frozenset({"kind", "label"}), "response_anchor_invalid"
                )
                if anchor["kind"] not in {"table", "row", "form", "field", "procedure", "step"}:
                    raise ChatProofError("response_anchor_invalid")
                _bounded_text(anchor["label"], 512, "response_anchor_invalid")
            excerpt_count += 1

    claim_texts: list[str] = []
    cited_claim_count = 0
    for claim_value in claims:
        claim = _exact_mapping(
            claim_value, frozenset({"citation_ids", "text"}), "response_claim_invalid"
        )
        claim_texts.append(_bounded_text(claim["text"], 65536, "response_claim_invalid"))
        claim_citations = claim["citation_ids"]
        if (
            not isinstance(claim_citations, list)
            or not claim_citations
            or len(set(claim_citations)) != len(claim_citations)
            or any(citation_id not in citation_ids for citation_id in claim_citations)
        ):
            raise ChatProofError("response_claim_citations_invalid")
        cited_claim_count += 1

    if answer != " ".join(claim_texts):
        raise ChatProofError("response_answer_not_claim_derived")
    return {
        "answered": True,
        "citation_count": len(citation_ids),
        "claim_count": cited_claim_count,
        "excerpt_count": excerpt_count,
        "source_count": len(source_ids),
        "status": "answered",
    }


def _atomic_private_json(path: Path, value: Mapping[str, Any]) -> None:
    if not path.is_absolute() or path.exists() or path.is_symlink():
        raise ChatProofError("output_path_invalid")
    if not path.parent.is_dir() or path.parent.is_symlink():
        raise ChatProofError("output_parent_invalid")
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            json.dump(value, output, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
        os.chmod(path, 0o600)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def _execute(endpoint: str, output: Path) -> int:
    if endpoint != "http://127.0.0.1:3000/api/v1/chat":
        raise ChatProofError("endpoint_invalid")
    conversation_id = "1" * 64
    turn_id = "2" * 64
    request_bytes = _request(conversation_id, turn_id)
    request = urllib.request.Request(
        endpoint,
        data=request_bytes,
        headers={"Accept": "application/json", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            status = response.status
            response_bytes = response.read(4 * 1024 * 1024 + 1)
            content_type = response.headers.get_content_type()
    except urllib.error.HTTPError as error:
        error.read(4 * 1024 * 1024 + 1)
        raise ChatProofError(f"http_status_{error.code}") from None
    except (OSError, TimeoutError, urllib.error.URLError):
        raise ChatProofError("http_exchange_failed") from None
    if status != 200 or content_type != "application/json":
        raise ChatProofError("http_response_contract_invalid")
    if not 1 <= len(response_bytes) <= 4 * 1024 * 1024:
        raise ChatProofError("http_response_size_invalid")
    try:
        value = json.loads(response_bytes.decode("utf-8", errors="strict"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise ChatProofError("http_response_json_invalid") from None
    metrics = _validate_response(value, conversation_id=conversation_id, turn_id=turn_id)
    artifact = {
        "answered": metrics["answered"],
        "citation_count": metrics["citation_count"],
        "claim_count": metrics["claim_count"],
        "excerpt_count": metrics["excerpt_count"],
        "http_status": 200,
        "raw_request_retained": False,
        "raw_response_retained": False,
        "schema_version": 1,
        "source_count": metrics["source_count"],
        "status": metrics["status"],
    }
    _atomic_private_json(output, artifact)
    print(
        "ishikawa_chat_path=pass;http_status=200;status=answered;"
        f"sources={metrics['source_count']};excerpts={metrics['excerpt_count']};"
        f"claims={metrics['claim_count']};citations={metrics['citation_count']};"
        "raw_content_retained=false"
    )
    return 0


def _self_test() -> int:
    conversation_id = "1" * 64
    turn_id = "2" * 64
    citation_id = "3" * 64
    value = {
        "answer": "Validated synthetic claim.",
        "claims": [{"citation_ids": [citation_id], "text": "Validated synthetic claim."}],
        "clarification": None,
        "conversation_id": conversation_id,
        "error": None,
        "request_id": "4" * 64,
        "schema": RESPONSE_SCHEMA,
        "sources": [
            {
                "display_name": "Synthetic source",
                "document_class": "policy_sop",
                "excerpts": [
                    {
                        "anchor": None,
                        "citation_id": citation_id,
                        "excerpt": "Synthetic excerpt.",
                        "page_end": 1,
                        "page_start": 1,
                        "structural_path": [],
                    }
                ],
                "source_id": "5" * 64,
                "source_label": "Source 1",
            }
        ],
        "status": "answered",
        "turn_id": turn_id,
    }
    metrics = _validate_response(value, conversation_id=conversation_id, turn_id=turn_id)
    if metrics != {
        "answered": True,
        "citation_count": 1,
        "claim_count": 1,
        "excerpt_count": 1,
        "source_count": 1,
        "status": "answered",
    }:
        raise ChatProofError("self_test_result_invalid")
    print("ishikawa_chat_path_self_test=pass")
    return 0


def _validate_artifact(path: Path) -> int:
    if not path.is_absolute() or not path.is_file() or path.is_symlink():
        raise ChatProofError("artifact_path_invalid")
    try:
        value = json.loads(path.read_text(encoding="utf-8", errors="strict"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        raise ChatProofError("artifact_json_invalid") from None
    artifact = _exact_mapping(
        value,
        frozenset(
            {
                "answered",
                "citation_count",
                "claim_count",
                "excerpt_count",
                "http_status",
                "raw_request_retained",
                "raw_response_retained",
                "schema_version",
                "source_count",
                "status",
            }
        ),
        "artifact_fields_invalid",
    )
    if (
        artifact["schema_version"] != 1
        or artifact["http_status"] != 200
        or artifact["status"] != "answered"
        or artifact["answered"] is not True
        or artifact["raw_request_retained"] is not False
        or artifact["raw_response_retained"] is not False
    ):
        raise ChatProofError("artifact_contract_invalid")
    limits = {
        "source_count": 20,
        "excerpt_count": 400,
        "claim_count": 64,
        "citation_count": 400,
    }
    if any(
        type(artifact[name]) is not int or not 1 <= artifact[name] <= maximum
        for name, maximum in limits.items()
    ):
        raise ChatProofError("artifact_count_invalid")
    print(
        "ishikawa_chat_path_artifact=pass;http_status=200;status=answered;"
        f"sources={artifact['source_count']};excerpts={artifact['excerpt_count']};"
        f"claims={artifact['claim_count']};citations={artifact['citation_count']};"
        "raw_content_retained=false"
    )
    return 0


def main(arguments: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--endpoint")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--validate-artifact", type=Path)
    values = parser.parse_args(arguments)
    try:
        if values.self_test:
            if (
                values.endpoint is not None
                or values.output is not None
                or values.validate_artifact is not None
            ):
                raise ChatProofError("arguments_invalid")
            return _self_test()
        if values.validate_artifact is not None:
            if values.endpoint is not None or values.output is not None:
                raise ChatProofError("arguments_invalid")
            return _validate_artifact(values.validate_artifact)
        if values.endpoint is None or values.output is None:
            raise ChatProofError("arguments_invalid")
        return _execute(values.endpoint, values.output)
    except ChatProofError as error:
        print(f"ishikawa_chat_path=blocked;reason={error}")
        return 1
    except Exception:
        print("ishikawa_chat_path=blocked;reason=unexpected_failure")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
