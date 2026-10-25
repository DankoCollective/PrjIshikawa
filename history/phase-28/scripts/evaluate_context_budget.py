#!/usr/bin/env python3
"""Content-free qualification of Ishikawa's provisional context budget.

This evaluator binds the proposed application budget to the accepted Gemma
tokenizer measurement and exercises the deterministic reconstruction limits.
It does not construct a final model request or call a model.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from ishikawa.canonical import domain_digest
from ishikawa.reconstruction import (
    CompleteProcedureTarget,
    EvidenceCandidate,
    EvidenceCitation,
    ReconstructionContractError,
    assemble_evidence,
    reconstruct_complete_procedure,
    validate_reconstruction_profile,
)
from ishikawa.yaml_loader import load_restricted_yaml


def fail(reason: str) -> None:
    print(f"numeric_context_budget_qualification=blocked;reason={reason}")
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


def convert(document: dict[str, Any], raw: dict[str, Any], rank: int) -> EvidenceCandidate:
    anchor = raw["citation_anchor"]
    citation = EvidenceCitation(
        citation_id=domain_digest(
            "ishikawa.citation.v1",
            {
                "chunk_id": raw["chunk_id"],
                "page_start": anchor["page_start"],
                "page_end": anchor["page_end"],
            },
        ),
        document_id=document["document_id"],
        document_version_id=document["document_version_id"],
        document_key="procedure.incident-reporting",
        page_start=anchor["page_start"],
        page_end=anchor["page_end"],
        structural_path=tuple(anchor["structural_path"]),
    )
    return EvidenceCandidate(
        chunk_id=raw["chunk_id"],
        retrieval_text_digest=raw["retrieval_text_digest"],
        retrieval_text=raw["retrieval_text"],
        projection_kind=raw["projection_kind"],
        ordinal=raw["projection_properties"].get("source_ordinal", rank - 1),
        retrieval_rank=rank,
        origin="direct",
        inclusion_reason="direct_retrieval",
        citations=(citation,),
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", required=True)
    parser.add_argument("--expected-profile-sha256", required=True)
    parser.add_argument("--measurement", required=True)
    parser.add_argument("--expected-measurement-sha256", required=True)
    parser.add_argument("--chunks", required=True)
    parser.add_argument("--expected-chunks-sha256", required=True)
    arguments = parser.parse_args()

    profile_path = Path(arguments.profile)
    measurement_path = Path(arguments.measurement)
    chunks_path = Path(arguments.chunks)
    require_file(profile_path, arguments.expected_profile_sha256, "profile")
    require_file(measurement_path, arguments.expected_measurement_sha256, "measurement")
    require_file(chunks_path, arguments.expected_chunks_sha256, "chunks")

    try:
        profile_value = load_restricted_yaml(profile_path, label="reconstruction profile")
        policy = validate_reconstruction_profile(profile_value)
    except (OSError, UnicodeError, ReconstructionContractError, ValueError):
        fail("invalid_reconstruction_profile")
    if not isinstance(profile_value, dict):
        fail("invalid_reconstruction_profile")

    measurement = read_json(measurement_path, "measurement")
    chunks = read_json(chunks_path, "chunks")
    generation = profile_value["generation"]
    if measurement.get("schema_version") != 1:
        fail("measurement_schema_mismatch")
    expected_measurement_facts = {
        "purpose": "generation_tokenizer_qualification_measurement",
        "source_sha256": arguments.expected_chunks_sha256,
        "served_model": generation["served_model"],
        "tokenizer_identity": generation["tokenizer_identity"],
        "chat_template_sha256": generation["chat_template_sha256"],
        "configured_max_model_len": generation["qualified_service_maximum_tokens"],
        "enable_thinking": False,
        "raw_text_retained": False,
        "model_called": False,
    }
    for name, expected in expected_measurement_facts.items():
        if measurement.get(name) != expected:
            fail(f"measurement_{name}_mismatch")

    documents = chunks.get("documents")
    if not isinstance(documents, list) or len(documents) != 6:
        fail("document_inventory_mismatch")
    flattened = [item for document in documents for item in document.get("candidates", [])]
    measured = measurement.get("measurements")
    if not isinstance(measured, dict):
        fail("measurement_counts_absent")
    candidate_counts = measured.get("candidate_without_special")
    candidate_counts_with_special = measured.get("candidate_with_special")
    if (
        not isinstance(candidate_counts, list)
        or len(candidate_counts) != len(flattened)
        or candidate_counts != candidate_counts_with_special
        or any(type(item) is not int or item < 1 for item in candidate_counts)
    ):
        fail("candidate_token_inventory_mismatch")
    counts_by_digest: dict[str, int] = {}
    for candidate, count in zip(flattened, candidate_counts, strict=True):
        digest = candidate.get("retrieval_text_digest")
        if not isinstance(digest, str):
            fail("candidate_digest_absent")
        prior = counts_by_digest.setdefault(digest, count)
        if prior != count:
            fail("candidate_token_count_conflict")

    procedure = next((item for item in documents if item.get("document_ref") == "SYN-006"), None)
    if not isinstance(procedure, dict):
        fail("procedure_document_absent")
    inventory = tuple(
        convert(procedure, item, index + 1)
        for index, item in enumerate(procedure.get("candidates", []))
    )
    whole = reconstruct_complete_procedure(
        CompleteProcedureTarget(procedure["document_version_id"], ()),
        inventory,
        inventory_complete=True,
    )
    triage = reconstruct_complete_procedure(
        CompleteProcedureTarget(
            procedure["document_version_id"], ("II. Triage Sequence",)
        ),
        inventory,
        inventory_complete=True,
    )
    if len(whole) != 15 or len(triage) != 3:
        fail("procedure_reconstruction_mismatch")

    whole_text = "\n\n".join(item.retrieval_text for item in whole)
    triage_text = "\n\n".join(item.retrieval_text for item in triage)
    whole_tokens = measured.get("whole_procedure_without_special")
    triage_tokens = measured.get("triage_without_special")
    whole_chat_tokens = measured.get("whole_procedure_chat_template")
    triage_chat_tokens = measured.get("triage_chat_template")
    if (whole_tokens, triage_tokens, whole_chat_tokens, triage_chat_tokens) != (292, 59, 317, 86):
        fail("accepted_procedure_measurement_mismatch")

    joined_counts = {whole_text: whole_tokens, triage_text: triage_tokens}

    def exact_counter(text: str) -> int:
        joined = joined_counts.get(text)
        if joined is not None:
            return joined
        digest = domain_digest("ishikawa.retrieval-text.v1", {"retrieval_text": text})
        if digest not in counts_by_digest:
            raise ReconstructionContractError("text is absent from accepted tokenizer measurement")
        return counts_by_digest[digest]

    fitted = assemble_evidence(
        whole,
        policy=policy,
        token_counter=exact_counter,
        instruction_tokens=policy.instruction_token_limit,
        conversation_tokens=policy.conversation_token_limit,
        complete_procedure=True,
    )
    instruction_limited = assemble_evidence(
        whole,
        policy=policy,
        token_counter=exact_counter,
        instruction_tokens=policy.instruction_token_limit + 1,
        conversation_tokens=0,
        complete_procedure=True,
    )
    conversation_limited = assemble_evidence(
        whole,
        policy=policy,
        token_counter=exact_counter,
        instruction_tokens=0,
        conversation_tokens=policy.conversation_token_limit + 1,
        complete_procedure=True,
    )
    evidence_limited = assemble_evidence(
        whole,
        policy=policy,
        token_counter=lambda _text: policy.evidence_token_limit + 1,
        instruction_tokens=0,
        conversation_tokens=0,
        complete_procedure=True,
    )
    if (
        fitted.status != "ok"
        or fitted.evidence_tokens != whole_tokens
        or len(fitted.selected) != 15
    ):
        fail("complete_procedure_fit_mismatch")
    if instruction_limited.reason_code != "INSTRUCTION_CONTEXT_LIMIT":
        fail("instruction_boundary_mismatch")
    if conversation_limited.reason_code != "CONVERSATION_CONTEXT_LIMIT":
        fail("conversation_boundary_mismatch")
    if evidence_limited.reason_code != "COMPLETE_PROCEDURE_CONTEXT_LIMIT":
        fail("evidence_boundary_mismatch")

    print("purpose=qualify_numeric_generation_context_budget")
    print(f"reconstruction_policy_id={policy.digest}")
    print(
        f"total_context_tokens={policy.total_context_tokens};"
        f"instruction_token_limit={policy.instruction_token_limit};"
        f"conversation_token_limit={policy.conversation_token_limit};"
        f"evidence_token_limit={policy.evidence_token_limit};"
        f"answer_token_reserve={policy.answer_token_reserve}"
    )
    print(
        f"qualified_service_maximum_tokens={generation['qualified_service_maximum_tokens']};"
        "service_configuration_changed=false"
    )
    print(
        f"whole_procedure_units={len(whole)};raw_evidence_tokens={whole_tokens};"
        f"diagnostic_chat_tokens={whole_chat_tokens}"
    )
    print(
        f"triage_units={len(triage)};raw_evidence_tokens={triage_tokens};"
        f"diagnostic_chat_tokens={triage_chat_tokens}"
    )
    print("instruction_boundary=pass;conversation_boundary=pass;evidence_boundary=pass")
    print("complete_procedure_fit=pass;complete_procedure_context_limit=pass")
    print("full_prompt_composition_qualification=pending_request_builder")
    print("latency_and_answer_quality_qualification=pending_model_integration")
    print("numeric_context_budget_qualification=pass")


if __name__ == "__main__":
    main()
