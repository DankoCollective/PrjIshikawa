#!/usr/bin/env python3
"""Build and inspect one deterministic synthetic grounded-generation request."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
from typing import Any

from ishikawa.canonical import canonical_json_bytes, domain_digest
from ishikawa.generation import (
    ConversationTurn,
    GroundedEvidence,
    build_grounded_generation_request,
)
from ishikawa.reconstruction import validate_reconstruction_profile
from ishikawa.yaml_loader import load_restricted_yaml


def fail(reason: str) -> None:
    print(f"generation_request_builder_qualification=blocked;reason={reason}")
    raise SystemExit(1)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def require_file(path: Path, expected_sha256: str, label: str) -> None:
    if not path.is_file() or path.is_symlink():
        fail(f"unsafe_{label}")
    if sha256_file(path) != expected_sha256:
        fail(f"{label}_identity_mismatch")


def read_json(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail(f"invalid_{label}")
    if not isinstance(value, dict):
        fail(f"invalid_{label}")
    return value


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", required=True)
    parser.add_argument("--expected-profile-sha256", required=True)
    parser.add_argument("--chunks", required=True)
    parser.add_argument("--expected-chunks-sha256", required=True)
    parser.add_argument("--output", required=True)
    arguments = parser.parse_args()

    profile_path = Path(arguments.profile)
    chunks_path = Path(arguments.chunks)
    output_path = Path(arguments.output)
    require_file(profile_path, arguments.expected_profile_sha256, "profile")
    require_file(chunks_path, arguments.expected_chunks_sha256, "chunks")
    if output_path.exists() or output_path.is_symlink() or not output_path.parent.is_dir():
        fail("output_path_unsafe")

    try:
        profile_value = load_restricted_yaml(profile_path, label="reconstruction profile")
        policy = validate_reconstruction_profile(profile_value)
    except (OSError, UnicodeError, ValueError):
        fail("invalid_reconstruction_profile")
    chunks = read_json(chunks_path, "chunks")
    documents = chunks.get("documents")
    if not isinstance(documents, list) or len(documents) != 6:
        fail("document_inventory_mismatch")
    procedure = next((item for item in documents if item.get("document_ref") == "SYN-006"), None)
    if not isinstance(procedure, dict):
        fail("procedure_document_absent")
    candidates = procedure.get("candidates")
    if not isinstance(candidates, list) or len(candidates) != 15:
        fail("procedure_candidate_inventory_mismatch")

    selected = candidates[:3]
    evidence = tuple(
        GroundedEvidence(
            citation_id=domain_digest(
                "ishikawa.citation.v1",
                {
                    "chunk_id": item["chunk_id"],
                    "page_start": item["citation_anchor"]["page_start"],
                    "page_end": item["citation_anchor"]["page_end"],
                },
            ),
            source_label="Source 1",
            excerpt=item["retrieval_text"],
            page_start=item["citation_anchor"]["page_start"],
            page_end=item["citation_anchor"]["page_end"],
            structural_path=tuple(item["citation_anchor"]["structural_path"]),
        )
        for item in selected
    )
    history = (
        ConversationTurn("user", "What is the initial reporting requirement?"),
        ConversationTurn("assistant", "The earlier answer identified the cited reporting requirement."),
    )
    values = {
        "conversation_id": domain_digest("ishikawa.synthetic-conversation.v1", "conversation"),
        "turn_id": domain_digest("ishikawa.synthetic-turn.v1", "turn-2"),
        "history": history,
        "question": "What does Source 1 say happens next?",
        "evidence": evidence,
        "policy": policy,
    }
    first = build_grounded_generation_request(**values)
    second = build_grounded_generation_request(**values)
    if first != second or first.canonical_bytes() != second.canonical_bytes():
        fail("request_is_not_deterministic")
    body = first.body
    if set(body) != {
        "chat_template_kwargs", "max_tokens", "messages", "model", "stream",
        "temperature", "top_k", "top_p",
    }:
        fail("request_field_contract_mismatch")
    if (
        body["model"] != policy.tokenizer_model
        or body["max_tokens"] != policy.answer_token_reserve
        or body["stream"] is not False
        or body["temperature"] != 1.0
        or body["top_p"] != 0.95
        or body["top_k"] != 64
        or body["chat_template_kwargs"] != {"enable_thinking": False}
    ):
        fail("generation_setting_mismatch")
    messages = body["messages"]
    if (
        not isinstance(messages, list)
        or len(messages) != 2
        or messages[0].get("role") != "system"
        or messages[1].get("role") != "user"
    ):
        fail("trusted_untrusted_message_boundary_mismatch")
    try:
        payload = json.loads(messages[1]["content"])
    except (TypeError, json.JSONDecodeError):
        fail("untrusted_payload_is_not_canonical_json")
    if (
        payload.get("schema") != "ishikawa.grounded-generation-input.v1"
        or len(payload.get("conversation", [])) != 2
        or len(payload.get("evidence", [])) != 3
        or payload.get("allowed_citation_ids") != list(first.allowed_citation_ids)
    ):
        fail("untrusted_payload_contract_mismatch")
    if any(item["citation_id"] not in first.allowed_citation_ids for item in payload["evidence"]):
        fail("citation_allowlist_mismatch")

    artifact = {
        "body": body,
        "chunk_source_sha256": arguments.expected_chunks_sha256,
        "prompt_identity": first.prompt_identity,
        "purpose": "synthetic_grounded_generation_request",
        "reconstruction_policy_identity": policy.digest,
        "request_identity": first.request_identity,
        "schema_version": 1,
        "synthetic_only": True,
    }
    try:
        descriptor = os.open(output_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(canonical_json_bytes(artifact) + b"\n")
    except OSError:
        fail("request_artifact_write_failed")

    print("purpose=qualify_grounded_generation_request_builder")
    print(f"reconstruction_policy_id={policy.digest};generation_prompt_id={first.prompt_identity}")
    print(f"generation_request_id={first.request_identity}")
    print("messages=2;history_turns=2;evidence_excerpts=3;source_groups=1")
    print("trusted_instruction_boundary=pass;untrusted_json_payload_boundary=pass")
    print("conversation_preservation=pass;citation_allowlist=pass;deterministic_serialization=pass")
    print("model_call=false;endpoint_present=false;credential_present=false;organizational_content=false")
    print("exact_composed_token_measurement=pending_deployed_tokenizer")
    print("generation_request_builder_qualification=pass")


if __name__ == "__main__":
    main()
