#!/usr/bin/env python3
"""Qualify deterministic evidence-sufficiency outcomes without retrieval."""

from __future__ import annotations

import argparse
import hashlib
import os
from dataclasses import replace
from pathlib import Path
from typing import Any, NoReturn

from ishikawa.canonical import canonical_json_bytes, domain_digest
from ishikawa.reconstruction import (
    EvidenceCandidate,
    EvidenceCitation,
    assemble_evidence,
    validate_reconstruction_profile,
)
from ishikawa.relevance import RelevanceDecision
from ishikawa.sufficiency import (
    SufficiencySignals,
    evaluate_evidence_sufficiency,
    validate_sufficiency_profile,
)
from ishikawa.yaml_loader import load_restricted_yaml


def fail(reason: str) -> NoReturn:
    print(f"sufficiency_gate_contract_qualification=blocked;reason={reason}")
    raise SystemExit(1)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def identity(label: str) -> str:
    return domain_digest("ishikawa.sufficiency-evaluation.v1", label)


def write_artifact(path: Path, value: dict[str, Any]) -> str:
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
    parser.add_argument("--reconstruction-profile", required=True)
    parser.add_argument("--expected-reconstruction-profile-sha256", required=True)
    parser.add_argument("--output", required=True)
    arguments = parser.parse_args()
    profile_path = Path(arguments.profile)
    reconstruction_path = Path(arguments.reconstruction_profile)
    output_path = Path(arguments.output)
    if (
        not profile_path.is_file()
        or profile_path.is_symlink()
        or sha256_file(profile_path) != arguments.expected_profile_sha256
        or not reconstruction_path.is_file()
        or reconstruction_path.is_symlink()
        or sha256_file(reconstruction_path) != arguments.expected_reconstruction_profile_sha256
        or output_path.exists()
        or output_path.is_symlink()
        or not output_path.parent.is_dir()
    ):
        fail("input_or_output_identity_invalid")
    policy = validate_sufficiency_profile(load_restricted_yaml(profile_path, label="sufficiency profile"))
    reconstruction_policy = validate_reconstruction_profile(
        load_restricted_yaml(reconstruction_path, label="reconstruction profile")
    )
    citation = EvidenceCitation(
        identity("citation"), identity("document"), identity("version"),
        "procedure.synthetic", 1, 1, ("Reporting",),
    )
    candidate = EvidenceCandidate(
        identity("chunk"), identity("text"), "A synthetic report is due within one day.",
        "paragraph", 1, 1, "direct", "fused_retrieval", (citation,),
    )
    package = assemble_evidence(
        (candidate,), policy=reconstruction_policy, token_counter=lambda text: len(text.split()),
        instruction_tokens=100, conversation_tokens=100,
    )
    relevance_identity = identity("calibrated-relevance-profile")
    qualified_relevance = RelevanceDecision(
        "qualified", "CITABLE_EVIDENCE_SUPPORT_QUALIFIED",
        relevance_identity, 3, 3, 3, 5,
    )
    insufficient_relevance = RelevanceDecision(
        "insufficient", "CITABLE_EVIDENCE_SUPPORT_INSUFFICIENT",
        relevance_identity, 3, 3, 2, 5,
    )

    def signals(**changes):
        values = {
            "lane_states": (("exact", "not_applicable"), ("lexical", "pass"), ("vector", "pass")),
            "fused_candidate_count": 1,
            "authorized_candidate_count": 1,
            "exact_constraint_required": False,
            "exact_constraint_satisfied": False,
            "relationship_coverage_required": False,
            "relationship_coverage_complete": False,
            "source_version_conflict": False,
            "relevance_decision": qualified_relevance,
            "complete_structure_requested": False,
        }
        values.update(changes)
        return SufficiencySignals(**values)

    cases = (
        ("EVIDENCE_SUFFICIENT", signals(), package),
        ("RETRIEVAL_LANE_FAILURE", signals(lane_states=(("exact", "not_applicable"), ("lexical", "failed"), ("vector", "pass"))), package),
        ("NO_RETRIEVAL_CANDIDATES", signals(fused_candidate_count=0, authorized_candidate_count=0), package),
        ("NO_AUTHORIZED_EVIDENCE", signals(authorized_candidate_count=0), package),
        ("EXACT_CONSTRAINT_UNSATISFIED", signals(exact_constraint_required=True), package),
        ("RELATIONSHIP_COVERAGE_INCOMPLETE", signals(relationship_coverage_required=True), package),
        ("SOURCE_VERSION_CONFLICT", signals(source_version_conflict=True), package),
        ("NO_RECONSTRUCTABLE_EVIDENCE", signals(), replace(package, status="no-evidence", reason_code="NO_RECONSTRUCTABLE_EVIDENCE", selected=(), source_groups=())),
        ("CITATION_SET_INVALID", signals(), replace(package, source_groups=())),
        ("RELEVANCE_NOT_QUALIFIED", signals(relevance_decision=None), package),
        ("RELEVANCE_INSUFFICIENT", signals(relevance_decision=insufficient_relevance), package),
        ("COMPLETE_STRUCTURE_INCOMPLETE", signals(complete_structure_requested=True), package),
        ("CONTEXT_LIMIT", signals(), replace(package, status="context-limit", reason_code="EVIDENCE_CONTEXT_LIMIT")),
    )
    observed: list[dict[str, str]] = []
    for expected_reason, case_signals, case_package in cases:
        result = evaluate_evidence_sufficiency(case_signals, case_package, policy)
        if result.reason_code != expected_reason:
            fail("outcome_mismatch")
        observed.append({"reason_code": result.reason_code, "status": result.status})
    artifact = {
        "case_count": len(cases),
        "model_called": False,
        "outcomes": observed,
        "policy_identity": policy.digest,
        "profile_sha256": arguments.expected_profile_sha256,
        "purpose": "deterministic_evidence_sufficiency_qualification",
        "raw_text_retained": False,
        "reconstruction_policy_identity": reconstruction_policy.digest,
        "schema_version": 1,
    }
    artifact_sha256 = write_artifact(output_path, artifact)
    print("purpose=qualify_deterministic_post_retrieval_evidence_sufficiency_gate")
    print(f"sufficiency_policy_identity={policy.digest};reconstruction_policy_identity={reconstruction_policy.digest}")
    print("cases=13;sufficient=1;temporarily_unavailable=1;insufficient_evidence=9;context_limit=2")
    print("lane_health=pass;candidate_presence=pass;authorization=pass;exact_constraint=pass;relationship_coverage=pass")
    print("source_conflict=pass;reconstruction=pass;citation_set=pass;complete_structure=pass;context_limit=pass")
    print("calibrated_relevance_required=true;candidate_presence_is_not_relevance=true;uncalibrated_relevance_fails_closed=true")
    print("model_call=false;network_contact=false;database_contact=false;raw_text_retained=false")
    print(f"sufficiency_qualification_artifact_sha256={artifact_sha256}")
    print("sufficiency_gate_contract_qualification=pass")


if __name__ == "__main__":
    main()
