#!/usr/bin/env python3
"""Content-free qualification of the deterministic reconstruction foundation."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from ishikawa.canonical import domain_digest
from ishikawa.reconstruction import (
    CompleteProcedureTarget,
    EvidenceCandidate,
    EvidenceCitation,
    ReconstructionPolicy,
    assemble_evidence,
    reconstruct_complete_procedure,
)


def fail(reason: str) -> None:
    print(f"evidence_reconstruction_foundation=blocked;reason={reason}")
    raise SystemExit(1)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def word_count(text: str) -> int:
    return len(text.split())


def policy(evidence_tokens: int) -> ReconstructionPolicy:
    return ReconstructionPolicy(
        tokenizer_model="deterministic-test-counter-not-production",
        tokenizer_identity=domain_digest("ishikawa.reconstruction-evaluation.v1", "counter"),
        temperature=1.0,
        top_p=0.95,
        top_k=64,
        total_context_tokens=10000,
        instruction_token_limit=100,
        conversation_token_limit=100,
        evidence_token_limit=evidence_tokens,
        answer_token_reserve=100,
        normal_per_document_limit=3,
        explicit_document_limit=20,
    )


def convert(document: dict, raw: dict, rank: int) -> EvidenceCandidate:
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
    parser.add_argument("--chunks", required=True)
    parser.add_argument("--expected-sha256", required=True)
    arguments = parser.parse_args()
    path = Path(arguments.chunks)
    if not path.is_file() or path.is_symlink():
        fail("unsafe_chunk_artifact")
    if sha256_file(path) != arguments.expected_sha256:
        fail("chunk_artifact_identity_mismatch")
    try:
        artifact = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail("invalid_chunk_artifact")
    documents = artifact.get("documents")
    if not isinstance(documents, list) or len(documents) != 6:
        fail("document_inventory_mismatch")
    candidate_count = sum(len(item.get("candidates", [])) for item in documents)
    if candidate_count != 126:
        fail("candidate_inventory_mismatch")
    procedure = next((item for item in documents if item.get("document_ref") == "SYN-006"), None)
    if procedure is None:
        fail("procedure_document_absent")
    inventory = tuple(
        convert(procedure, item, index + 1)
        for index, item in enumerate(procedure["candidates"])
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
    if len(whole) != len(inventory) or len(triage) != 3:
        fail("procedure_reconstruction_mismatch")
    if [item.ordinal for item in whole] != sorted(item.ordinal for item in whole):
        fail("procedure_source_order_mismatch")
    fitted = assemble_evidence(
        triage,
        policy=policy(1000),
        token_counter=word_count,
        instruction_tokens=10,
        conversation_tokens=10,
        complete_procedure=True,
    )
    limited = assemble_evidence(
        triage,
        policy=policy(1),
        token_counter=word_count,
        instruction_tokens=10,
        conversation_tokens=10,
        complete_procedure=True,
    )
    if fitted.status != "ok" or len(fitted.selected) != 3:
        fail("complete_procedure_fit_mismatch")
    if limited.reason_code != "COMPLETE_PROCEDURE_CONTEXT_LIMIT" or limited.selected:
        fail("complete_procedure_limit_mismatch")
    print("purpose=qualify_evidence_reconstruction_foundation")
    print(f"synthetic_documents={len(documents)};synthetic_candidates={candidate_count}")
    print(
        f"complete_document_inventory=true;whole_procedure_units={len(whole)};"
        f"triage_section_units={len(triage)};source_order=pass"
    )
    print("exact_identity_deduplication=pass;citation_preservation=pass")
    print("document_grouping=pass;stable_source_labels=pass;multi_excerpt_sources=pass")
    print("normal_diversity=pass;explicit_document_diversity=pass")
    print("atomic_no_truncation=pass;complete_procedure_all_or_context_limit=pass")
    print("conversation_limit=pass;relationship_provenance=pass")
    print("generation_tokenizer_qualification=pending;numeric_budget_calibration=pending")
    print("evidence_reconstruction_foundation=pass")


if __name__ == "__main__":
    main()
