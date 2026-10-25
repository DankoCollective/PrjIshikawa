#!/usr/bin/env python3
"""Qualify the frozen versioned Ishikawa chat API envelope locally."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
from pathlib import Path
from typing import Any, NoReturn

from ishikawa.api_contract import (
    ERRORS_BY_STATUS,
    STATUSES,
    ApiClaim,
    ApiError,
    ApiExcerpt,
    ApiSourceGroup,
    build_chat_response,
    decode_chat_request,
    validate_api_profile,
)
from ishikawa.canonical import canonical_json_bytes
from ishikawa.scope import validate_scope_profile
from ishikawa.yaml_loader import load_restricted_yaml


HEX = re.compile(r"^[0-9a-f]{64}$")


class EvaluationError(RuntimeError):
    pass


def fail(reason: str) -> NoReturn:
    raise EvaluationError(reason)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def require_identity(path: Path, expected: str) -> None:
    if (
        HEX.fullmatch(expected or "") is None
        or not path.is_file()
        or path.is_symlink()
        or path.stat().st_size > 1024 * 1024
        or sha256_file(path) != expected
    ):
        fail("source_identity_mismatch")


def write_artifact(path: Path, value: dict[str, Any]) -> str:
    if path.exists() or path.is_symlink() or not path.parent.is_dir():
        fail("output_path_invalid")
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(canonical_json_bytes(value) + b"\n")
    except OSError:
        fail("artifact_write_failed")
    return sha256_file(path)


def ident(character: str) -> str:
    return character * 64


def field_names(value: Any) -> set[str]:
    if isinstance(value, dict):
        return set(value).union(*(field_names(item) for item in value.values()))
    if isinstance(value, list):
        return set().union(*(field_names(item) for item in value))
    return set()


def evaluate(arguments: argparse.Namespace) -> dict[str, Any]:
    require_identity(arguments.api_profile, arguments.expected_api_profile_sha256)
    require_identity(arguments.scope_profile, arguments.expected_scope_profile_sha256)
    api_policy = validate_api_profile(
        load_restricted_yaml(arguments.api_profile, label="API profile")
    )
    scope_policy = validate_scope_profile(
        load_restricted_yaml(arguments.scope_profile, label="scope profile")
    )
    if (
        api_policy.maximum_question_characters != scope_policy.maximum_question_characters
        or api_policy.maximum_history_turns != scope_policy.maximum_history_turns
        or api_policy.maximum_history_characters != scope_policy.maximum_history_characters
        or api_policy.maximum_source_references != scope_policy.maximum_source_references
    ):
        fail("api_scope_limit_mismatch")

    request_value = {
        "conversation_id": ident("a"),
        "filters": {"document_classes": ["policy_sop"], "document_keys": []},
        "history": [
            {"content": "How are incidents reported?", "role": "user", "turn_id": ident("b")},
            {"content": "Reports are submitted promptly.", "role": "assistant", "turn_id": ident("c")},
        ],
        "message": "What else does Source 1 say about reporting?",
        "schema": "ishikawa.chat-request.v1",
        "source_references": [
            {"citation_id": ident("f"), "source_id": ident("e"), "source_label": "Source 1"}
        ],
        "turn_id": ident("d"),
    }
    request = decode_chat_request(canonical_json_bytes(request_value), api_policy)
    excerpt = ApiExcerpt(
        ident("f"), "Reports are submitted promptly.", 2, 2,
        ("Incident Reporting", "Submission"), "step", "Step 2",
    )
    source = ApiSourceGroup(
        ident("e"), "Source 1", "Incident Reporting Procedure", "policy_sop", (excerpt,)
    )
    claim = ApiClaim("Reports are submitted promptly.", (ident("f"),))
    answered = build_chat_response(
        request=request,
        request_id=ident("1"),
        status="answered",
        answer=claim.text,
        claims=(claim,),
        sources=(source,),
        policy=api_policy,
    )
    clarification = build_chat_response(
        request=request,
        request_id=ident("2"),
        status="clarification-required",
        clarification="Which policy do you mean?",
        policy=api_policy,
    )
    responses = [answered, clarification]
    for index, status in enumerate(STATUSES[2:], start=3):
        code, message = ERRORS_BY_STATUS[status]
        responses.append(
            build_chat_response(
                request=request,
                request_id=format(index, "x") * 64,
                status=status,
                error=ApiError(code, message),
                policy=api_policy,
            )
        )
    if tuple(response.body["status"] for response in responses) != STATUSES:
        fail("response_status_inventory_mismatch")
    private_names = {
        "filesystem_path", "raw_score", "retrieval_rank", "prompt", "credential",
        "internal_topology", "stack_trace", "method_profile_id",
    }
    for response in responses:
        if private_names.intersection(field_names(response.body)):
            fail("private_field_exposed")

    artifact = {
        "api_policy_identity": api_policy.digest,
        "claim_count": len(answered.body["claims"]),
        "conversation_turn_count": len(request.history),
        "features": {
            "download_document": False,
            "open_document": False,
            "streaming": False,
        },
        "purpose": "versioned_chat_api_contract_qualification",
        "request_envelope_identity": request.envelope_identity,
        "response_envelope_identities": [response.envelope_identity for response in responses],
        "response_statuses": list(STATUSES),
        "schema_version": 1,
        "source_count": len(answered.body["sources"]),
    }
    artifact_sha256 = write_artifact(arguments.output, artifact)
    return {
        "api_policy_identity": api_policy.digest,
        "artifact_sha256": artifact_sha256,
        "request_identity": request.envelope_identity,
        "scope_policy_identity": scope_policy.digest,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--api-profile", type=Path, required=True)
    parser.add_argument("--expected-api-profile-sha256", required=True)
    parser.add_argument("--scope-profile", type=Path, required=True)
    parser.add_argument("--expected-scope-profile-sha256", required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    try:
        result = evaluate(arguments)
    except (EvaluationError, KeyError, TypeError, ValueError, OSError) as error:
        reason = str(error) if isinstance(error, EvaluationError) else "bounded_runtime_failure"
        print(f"api_contract_qualification=blocked;reason={reason}")
        return 1
    print(
        f"api_policy_identity={result['api_policy_identity']};"
        f"scope_policy_identity={result['scope_policy_identity']}"
    )
    print(f"request_envelope_identity={result['request_identity']}")
    print("request_schema=ishikawa.chat-request.v1;multi_turn_history=true;structured_source_followup=true;allowlisted_filters=true")
    print("response_schema=ishikawa.chat-response.v1;statuses=8;answered_claims_citation_allowlisted=true;source_groups=true")
    print("streaming=false;open_document=false;download_document=false;private_fields_excluded=true")
    print("network_contact=false;database_contact=false;model_call=false;credential_read=false")
    print(f"qualification_artifact_sha256={result['artifact_sha256']};raw_content_retained=false")
    print("api_contract_qualification=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
