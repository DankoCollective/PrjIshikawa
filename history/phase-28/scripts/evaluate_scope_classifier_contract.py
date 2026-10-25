#!/usr/bin/env python3
"""Evaluate the local scope-classifier contract without a model call."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
from typing import Any, NoReturn

from ishikawa.canonical import canonical_json_bytes, domain_digest
from ishikawa.generation import ConversationTurn
from ishikawa.scope import (
    ScopeResponseError,
    ScopeSourceReference,
    build_scope_request,
    validate_scope_content,
    validate_scope_profile,
)
from ishikawa.yaml_loader import load_restricted_yaml


def fail(reason: str) -> NoReturn:
    print(f"scope_classifier_contract_qualification=blocked;reason={reason}")
    raise SystemExit(1)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def expect_rejection(content: str, policy, reason: str) -> None:
    try:
        validate_scope_content(content, policy)
    except ScopeResponseError as error:
        if error.reason_code == reason:
            return
    fail("failure_path_mismatch")


def write_artifact(path: Path, request) -> str:
    value: dict[str, Any] = {
        "body": request.body,
        "policy_identity": request.policy_identity,
        "prompt_identity": request.prompt_identity,
        "purpose": "synthetic_scope_classifier_request",
        "request_identity": request.request_identity,
        "schema_version": 1,
        "synthetic_only": True,
    }
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(canonical_json_bytes(value) + b"\n")
    except OSError:
        fail("artifact_write_failed")
    return sha256_file(path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", required=True)
    parser.add_argument("--expected-profile-sha256", required=True)
    parser.add_argument("--output", required=True)
    arguments = parser.parse_args()
    profile_path = Path(arguments.profile)
    output_path = Path(arguments.output)
    if (
        not profile_path.is_file()
        or profile_path.is_symlink()
        or sha256_file(profile_path) != arguments.expected_profile_sha256
        or output_path.exists()
        or output_path.is_symlink()
        or not output_path.parent.is_dir()
    ):
        fail("input_or_output_identity_invalid")
    policy = validate_scope_profile(load_restricted_yaml(profile_path, label="scope profile"))
    reference = ScopeSourceReference(
        domain_digest("ishikawa.scope-evaluation.v1", "source"),
        "Source 1",
        "Synthetic Incident Reporting Procedure",
    )
    question = "What else does Source 1 say about the reporting deadline?"
    request = build_scope_request(
        conversation_id=domain_digest("ishikawa.scope-evaluation.v1", "conversation"),
        turn_id=domain_digest("ishikawa.scope-evaluation.v1", "turn"),
        history=(
            ConversationTurn("user", "What is the synthetic reporting deadline?"),
            ConversationTurn("assistant", "The prior cited answer identified the deadline."),
        ),
        question=question,
        source_references=(reference,),
        policy=policy,
    )
    payload = json.loads(request.body["messages"][1]["content"])
    if (
        question in request.body["messages"][0]["content"]
        or payload["current_question"] != question
        or payload["source_references"] != [reference.canonical()]
        or request.body["messages"][0]["role"] != "system"
        or request.body["messages"][1]["role"] != "user"
    ):
        fail("trusted_untrusted_boundary_invalid")
    validated_pairs = 0
    for decision, reasons in policy.reason_codes:
        for reason in reasons:
            clarification = "Which organizational policy or procedure do you mean?" if decision == "needs_clarification" else None
            content = json.dumps(
                {"clarification": clarification, "decision": decision, "reason_code": reason},
                separators=(",", ":"),
            )
            result = validate_scope_content(content, policy)
            if result.decision != decision or result.reason_code != reason:
                fail("decision_validation_mismatch")
            validated_pairs += 1
    fenced = '```json\n{"clarification":null,"decision":"allow","reason_code":"organizational_policy"}\n```'
    if validate_scope_content(fenced, policy).decision != "allow":
        fail("isolated_json_fence_invalid")
    expect_rejection(
        '{"clarification":null,"decision":"allow","reason_code":"personal_or_recreational"}',
        policy,
        "SCOPE_REASON_INVALID",
    )
    expect_rejection(
        '{"answer":"no","clarification":null,"decision":"allow","reason_code":"organizational_policy"}',
        policy,
        "SCOPE_OUTPUT_SCHEMA_INVALID",
    )
    expect_rejection(
        '{"clarification":null,"decision":"needs_clarification","reason_code":"professional_context_unclear"}',
        policy,
        "SCOPE_CLARIFICATION_INVALID",
    )
    expect_rejection("Result:\n" + fenced, policy, "SCOPE_OUTPUT_JSON_INVALID")
    artifact_sha256 = write_artifact(output_path, request)
    print("purpose=qualify_pre_retrieval_scope_classifier_contract_locally")
    print(f"scope_policy_identity={policy.digest};scope_prompt_identity={request.prompt_identity};scope_request_identity={request.request_identity}")
    print(f"decisions=3;reason_codes={validated_pairs};max_output_tokens={policy.max_output_tokens}")
    print("trusted_instruction_boundary=pass;untrusted_json_payload_boundary=pass;structured_source_followup=pass")
    print("allow_needs_clarification_out_of_scope_validation=pass;reason_decision_binding=pass;clarification_semantics=pass")
    print("isolated_json_fence=pass;surrounding_prose_rejection=pass;answer_field_rejection=pass")
    print("scope_only=true;injection_gate_separate=true;retrieval_reached=false")
    print("network_contact=false;model_call=false;database_contact=false;credential_read=false")
    print(f"synthetic_scope_request_sha256={artifact_sha256}")
    print("scope_classifier_contract_qualification=pass")


if __name__ == "__main__":
    main()
