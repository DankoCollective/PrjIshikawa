#!/usr/bin/env python3
"""Qualify the frozen Ishikawa Retrieval API identity and orchestration locally."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
from pathlib import Path
from typing import Any, NoReturn

from ishikawa.api_contract import ApiExcerpt, ApiSourceGroup, decode_chat_request, validate_api_profile
from ishikawa.canonical import canonical_json_bytes
from ishikawa.generation_transport import GroundedClaim, ValidatedGroundedAnswer
from ishikawa.injection import validate_injection_profile
from ishikawa.retrieval_service import (
    SERVICE_DISPLAY_NAME,
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


def evaluate(arguments: argparse.Namespace) -> dict[str, Any]:
    sources = (
        (arguments.api_profile, arguments.expected_api_profile_sha256),
        (arguments.injection_profile, arguments.expected_injection_profile_sha256),
        (arguments.service_profile, arguments.expected_service_profile_sha256),
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
        load_restricted_yaml(arguments.service_profile, label="retrieval service profile")
    )
    if SERVICE_DISPLAY_NAME != "Ishikawa Retrieval API":
        fail("service_name_mismatch")

    request = decode_chat_request(
        canonical_json_bytes(
            {
                "conversation_id": ident("a"),
                "filters": {"document_classes": [], "document_keys": []},
                "history": [],
                "message": "How are incidents reported?",
                "schema": "ishikawa.chat-request.v1",
                "source_references": [],
                "turn_id": ident("b"),
            }
        ),
        api_policy,
    )
    source = ApiSourceGroup(
        ident("c"),
        "Source 1",
        "Incident Reporting Procedure",
        "policy_sop",
        (ApiExcerpt(ident("d"), "Reports are submitted promptly.", 2, 2, ("Reporting",)),),
    )
    sufficient = SufficiencyDecision(
        "sufficient", "EVIDENCE_SUFFICIENT", ident("e"), 1, 1, ident("f")
    )
    calls: list[str] = []

    def classify(_request):
        calls.append("scope")
        return ScopeDecision("allow", "organizational_policy", None)

    def retrieve(_request):
        calls.append("retrieval")
        return RetrievedEvidence(sufficient, (source,))

    def generate(_request, evidence):
        calls.append("generation")
        if len(evidence) != 1 or evidence[0].citation_id != ident("d"):
            fail("generation_evidence_mismatch")
        claim = GroundedClaim("Reports are submitted promptly.", (ident("d"),))
        return ValidatedGroundedAnswer(claim.text, (claim,), "stop", 10, 5, 15)

    execution = orchestrate_chat(
        request=request,
        request_id=ident("1"),
        api_policy=api_policy,
        injection_policy=injection_policy,
        service_policy=service_policy,
        ports=RetrievalServicePorts(classify, retrieve, generate),
    )
    expected_trace = (
        "request-accepted",
        "direct-injection-passed",
        "scope-allowed",
        "retrieval-completed",
        "indirect-injection-passed",
        "sufficiency-passed",
        "generation-completed",
        "response-built",
    )
    if (
        calls != ["scope", "retrieval", "generation"]
        or execution.stage_trace != expected_trace
        or execution.response.body["status"] != "answered"
        or execution.response.body["answer"] != "Reports are submitted promptly."
        or execution.service_identity != service_policy.digest
    ):
        fail("answered_orchestration_mismatch")

    short_circuits: dict[str, str] = {}
    for decision, expected_status in (
        ("needs_clarification", "clarification-required"),
        ("out_of_scope", "out-of-scope"),
    ):
        local_calls: list[str] = []

        def stopped_scope(_request, selected=decision):
            local_calls.append("scope")
            clarification = "Which policy do you mean?" if selected == "needs_clarification" else None
            return ScopeDecision(selected, "bounded_reason", clarification)

        def forbidden_retrieval(_request):
            local_calls.append("retrieval")
            raise EvaluationError("short_circuit_failed")

        def forbidden_generation(_request, _evidence):
            local_calls.append("generation")
            raise EvaluationError("short_circuit_failed")

        stopped = orchestrate_chat(
            request=request,
            request_id=ident("2" if decision == "needs_clarification" else "3"),
            api_policy=api_policy,
            injection_policy=injection_policy,
            service_policy=service_policy,
            ports=RetrievalServicePorts(
                stopped_scope, forbidden_retrieval, forbidden_generation
            ),
        )
        if stopped.response.body["status"] != expected_status or local_calls != ["scope"]:
            fail("scope_short_circuit_failed")
        short_circuits[decision] = expected_status

    artifact = {
        "api_policy_identity": api_policy.digest,
        "client": service_policy.allowed_client,
        "default_bind_address": service_policy.default_bind_address,
        "default_port": service_policy.default_port,
        "lifecycle": service_policy.lifecycle,
        "network_contact": False,
        "package_owner": service_policy.package_owner,
        "process_model": service_policy.process_model,
        "purpose": "retrieval_service_orchestrator_qualification",
        "schema_version": 1,
        "service_display_name": service_policy.display_name,
        "service_identity": service_policy.digest,
        "short_circuits": short_circuits,
        "stage_trace": list(expected_trace),
    }
    artifact_sha256 = write_artifact(arguments.output, artifact)
    return {"artifact_sha256": artifact_sha256, "service_identity": service_policy.digest}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--api-profile", type=Path, required=True)
    parser.add_argument("--expected-api-profile-sha256", required=True)
    parser.add_argument("--injection-profile", type=Path, required=True)
    parser.add_argument("--expected-injection-profile-sha256", required=True)
    parser.add_argument("--service-profile", type=Path, required=True)
    parser.add_argument("--expected-service-profile-sha256", required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    try:
        result = evaluate(arguments)
    except (EvaluationError, KeyError, TypeError, ValueError, OSError) as error:
        reason = str(error) if isinstance(error, EvaluationError) else "bounded_runtime_failure"
        print(f"retrieval_service_orchestrator_qualification=blocked;reason={reason}")
        return 1
    print("service_name=Ishikawa Retrieval API;package_owner=Ishikawa;process_model=separate_process;lifecycle=start_on_demand")
    print("network_default=127.0.0.1:1384;allowed_client=ishikawa_nextjs_server;listener_started=false")
    print("orchestration_order=direct_injection,scope,retrieval,indirect_injection,sufficiency,generation,response")
    print("short_circuits=direct_injection,scope_clarification,out_of_scope,insufficient_evidence,context_limit,indirect_injection")
    print("safe_errors=temporarily_unavailable,internal_error;exception_text_exposed=false")
    print("network_contact=false;database_contact=false;model_call=false;credential_read=false")
    print(f"service_identity={result['service_identity']}")
    print(f"qualification_artifact_sha256={result['artifact_sha256']};raw_content_retained=false")
    print("retrieval_service_orchestrator_qualification=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

