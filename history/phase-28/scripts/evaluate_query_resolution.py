#!/usr/bin/env python3
"""Qualify standalone query resolution and its retrieval-service position."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
from pathlib import Path
from typing import Any, NoReturn

from ishikawa.api_contract import (
    ApiExcerpt,
    ApiSourceGroup,
    decode_chat_request,
    validate_api_profile,
)
from ishikawa.canonical import canonical_json_bytes
from ishikawa.generation_transport import (
    GenerationEndpoint,
    GenerationHTTPResponse,
    GroundedClaim,
    ValidatedGroundedAnswer,
)
from ishikawa.injection import validate_injection_profile
from ishikawa.query_resolution import validate_query_resolution_profile
from ishikawa.query_resolution_transport import NativeQueryResolutionAdapter
from ishikawa.retrieval_service import (
    RetrievedEvidence,
    RetrievalServicePorts,
    orchestrate_chat,
    validate_retrieval_service_profile,
)
from ishikawa.scope import ScopeDecision
from ishikawa.sufficiency import SufficiencyDecision
from ishikawa.yaml_loader import load_restricted_yaml


HEX = re.compile(r"^[0-9a-f]{64}$")


class EvaluationError(RuntimeError):
    pass


def fail(reason: str) -> NoReturn:
    raise EvaluationError(reason)


def ident(character: str) -> str:
    return character * 64


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


def evaluate(arguments: argparse.Namespace) -> dict[str, Any]:
    sources = (
        (arguments.api_profile, arguments.expected_api_profile_sha256),
        (arguments.injection_profile, arguments.expected_injection_profile_sha256),
        (arguments.service_profile, arguments.expected_service_profile_sha256),
        (arguments.resolution_profile, arguments.expected_resolution_profile_sha256),
    )
    for path, expected in sources:
        require_identity(path, expected)
    api_policy = validate_api_profile(
        load_restricted_yaml(arguments.api_profile, label="API profile")
    )
    injection_policy = validate_injection_profile(
        load_restricted_yaml(arguments.injection_profile, label="injection profile")
    )
    service_policy = validate_retrieval_service_profile(
        load_restricted_yaml(arguments.service_profile, label="service profile")
    )
    resolution_policy = validate_query_resolution_profile(
        load_restricted_yaml(arguments.resolution_profile, label="resolution profile")
    )

    followup = decode_chat_request(
        canonical_json_bytes(
            {
                "conversation_id": ident("a"),
                "filters": {
                    "document_classes": ["policy_sop"],
                    "document_keys": ["procedure.incident-reporting"],
                },
                "history": [
                    {"content": "How are incidents reported?", "role": "user", "turn_id": ident("b")},
                    {"content": "The prior answer cited Source 1.", "role": "assistant", "turn_id": ident("c")},
                ],
                "message": "What else does Source 1 say?",
                "schema": "ishikawa.chat-request.v1",
                "source_references": [
                    {
                        "citation_id": ident("f"),
                        "source_id": ident("e"),
                        "source_label": "Source 1",
                    }
                ],
                "turn_id": ident("d"),
            }
        ),
        api_policy,
    )
    model_calls: list[dict[str, Any]] = []
    credential_reads = 0

    def credential_provider() -> str:
        nonlocal credential_reads
        credential_reads += 1
        return "qualification-only-secret"

    def exchange(prepared):
        model_calls.append(json.loads(prepared.body))
        content = json.dumps(
            {
                "ambiguity": "none",
                "clarification": None,
                "referenced_source_labels": ["Source 1"],
                "resolved_query": "What additional incident reporting requirements apply?",
            },
            separators=(",", ":"),
        )
        body = {
            "choices": [
                {
                    "finish_reason": "stop",
                    "index": 0,
                    "message": {"content": content, "reasoning": None, "role": "assistant"},
                }
            ],
            "created": 1,
            "id": "resolution-qualification",
            "model": resolution_policy.served_model,
            "object": "chat.completion",
            "usage": {"completion_tokens": 25, "prompt_tokens": 100, "total_tokens": 125},
        }
        return GenerationHTTPResponse(200, "application/json", canonical_json_bytes(body))

    resolver = NativeQueryResolutionAdapter(
        GenerationEndpoint("http://127.0.0.1:8000/v1/chat/completions"),
        resolution_policy,
        credential_provider,
        lambda _reference: "Incident Reporting Procedure",
        exchange,
    )
    calls: list[str] = []
    observed_resolution = []
    source = ApiSourceGroup(
        ident("e"),
        "Source 1",
        "Incident Reporting Procedure",
        "policy_sop",
        (ApiExcerpt(ident("f"), "Reports are submitted promptly.", 2, 2, ("Reporting",)),),
    )
    sufficient = SufficiencyDecision(
        "sufficient", "EVIDENCE_SUFFICIENT", ident("8"), 1, 1, ident("7")
    )

    def classify(_request):
        calls.append("scope")
        return ScopeDecision("allow", "prior_answer_or_source_followup", None)

    def resolve(request):
        calls.append("resolve")
        return resolver(request)

    def retrieve(retrieval_request, resolution):
        calls.append("retrieve")
        if retrieval_request is not followup:
            fail("retrieval_request_identity_mismatch")
        observed_resolution.append(resolution)
        return RetrievedEvidence(sufficient, (source,))

    def generate(_request, _evidence):
        calls.append("generate")
        claim = GroundedClaim("Reports are submitted promptly.", (ident("f"),))
        return ValidatedGroundedAnswer(claim.text, (claim,), "stop", 10, 5, 15)

    execution = orchestrate_chat(
        request=followup,
        request_id=ident("1"),
        api_policy=api_policy,
        injection_policy=injection_policy,
        service_policy=service_policy,
        ports=RetrievalServicePorts(classify, resolve, retrieve, generate),
    )
    expected_trace = (
        "request-accepted",
        "direct-injection-passed",
        "scope-allowed",
        "query-resolved",
        "retrieval-completed",
        "indirect-injection-passed",
        "sufficiency-passed",
        "generation-completed",
        "response-built",
    )
    if (
        execution.response.body["status"] != "answered"
        or execution.stage_trace != expected_trace
        or calls != ["scope", "resolve", "retrieve", "generate"]
        or len(model_calls) != 1
        or credential_reads != 1
        or len(observed_resolution) != 1
    ):
        fail("contextual_orchestration_mismatch")
    resolution = observed_resolution[0]
    if (
        resolution.original_query != followup.message
        or resolution.resolved_query != "What additional incident reporting requirements apply?"
        or resolution.filters != followup.filters
        or len(resolution.source_constraints) != 1
        or resolution.source_constraints[0].source_id != ident("e")
        or resolution.source_constraints[0].citation_id != ident("f")
        or "Source 1" in resolution.resolved_query
    ):
        fail("resolved_query_contract_mismatch")

    direct = decode_chat_request(
        canonical_json_bytes(
            {
                "conversation_id": ident("2"),
                "filters": {"document_classes": [], "document_keys": []},
                "history": [],
                "message": "How are incidents reported?",
                "schema": "ishikawa.chat-request.v1",
                "source_references": [],
                "turn_id": ident("3"),
            }
        ),
        api_policy,
    )
    direct_result = resolver(direct)
    if (
        direct_result.used_model
        or direct_result.original_query != direct_result.resolved_query
        or len(model_calls) != 1
        or credential_reads != 1
    ):
        fail("direct_bypass_mismatch")

    unresolved = decode_chat_request(
        canonical_json_bytes(
            {
                "conversation_id": ident("4"),
                "filters": {"document_classes": [], "document_keys": []},
                "history": [],
                "message": "What does Source 9 say?",
                "schema": "ishikawa.chat-request.v1",
                "source_references": [],
                "turn_id": ident("5"),
            }
        ),
        api_policy,
    )
    unresolved_calls: list[str] = []

    def unresolved_scope(_request):
        unresolved_calls.append("scope")
        return ScopeDecision("allow", "prior_answer_or_source_followup", None)

    def unresolved_resolve(request):
        unresolved_calls.append("resolve")
        return resolver(request)

    def forbidden_retrieve(_resolution):
        unresolved_calls.append("retrieve")
        raise EvaluationError("unresolved_source_reached_retrieval")

    clarification = orchestrate_chat(
        request=unresolved,
        request_id=ident("6"),
        api_policy=api_policy,
        injection_policy=injection_policy,
        service_policy=service_policy,
        ports=RetrievalServicePorts(
            unresolved_scope, unresolved_resolve, forbidden_retrieve, generate
        ),
    )
    if (
        clarification.response.body["status"] != "clarification-required"
        or unresolved_calls != ["scope", "resolve"]
        or clarification.stage_trace[-1] != "query-clarification"
        or len(model_calls) != 1
        or credential_reads != 1
    ):
        fail("unresolved_source_clarification_mismatch")

    payload = json.loads(model_calls[0]["messages"][1]["content"])
    artifact = {
        "contextual_model_requests": 1,
        "direct_model_requests": 0,
        "filters_code_owned": payload["explicit_filters"] == followup.filters.canonical(),
        "full_transcript_embedding": False,
        "model_call": False,
        "network_contact": False,
        "orchestration_trace": list(expected_trace),
        "policy_identity": resolution_policy.digest,
        "purpose": "standalone_query_resolution_qualification",
        "resolved_source_constraints": len(resolution.source_constraints),
        "schema_version": 1,
        "unresolved_label_retrieval_calls": 0,
    }
    artifact_sha256 = write_artifact(arguments.output, artifact)
    return {"artifact_sha256": artifact_sha256, "policy_identity": resolution_policy.digest}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("api", "injection", "service", "resolution"):
        parser.add_argument(f"--{name}-profile", type=Path, required=True)
        parser.add_argument(f"--expected-{name}-profile-sha256", required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    try:
        result = evaluate(arguments)
    except (EvaluationError, KeyError, TypeError, ValueError, OSError) as error:
        reason = str(error) if isinstance(error, EvaluationError) else "bounded_runtime_failure"
        print(f"query_resolution_qualification=blocked;reason={reason}")
        return 1
    print("resolution=standalone_query;original_query_preserved=true;full_transcript_embedded=false")
    print("direct_question=model_bypass;contextual_followup=one_gemma_request;retry=false")
    print("source_labels=trusted_structured_map;literal_label_embedded=false;filters=code_owned")
    print("unresolved_source=clarification;retrieval_called=false;model_called=false")
    print("orchestration_order=direct_injection,scope,query_resolution,retrieval,indirect_injection,sufficiency,generation,response")
    print("network_contact=false;database_contact=false;model_call=false;credential_read=false")
    print(f"query_resolution_policy_identity={result['policy_identity']}")
    print(f"artifact_sha256={result['artifact_sha256']}")
    print("query_resolution_qualification=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
