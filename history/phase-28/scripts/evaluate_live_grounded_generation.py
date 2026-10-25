#!/usr/bin/env python3
"""Evaluate one protected synthetic live-grounded-generation artifact."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any, NoReturn


EXPECTED_MODEL = "google/gemma-4-26B-A4B-it"
EXPECTED_PROMPT_TOKENS = 885
EXPECTED_STEP_CITATIONS = {
    "39d9df33994b2d5a78d7745fdb11c45b3d81caee5157e5619adab699fb828f8e",
    "af099964e084a5b2ce29a2a0fd1e8e06a03e66c103a3ee5db5ea6ccba167c894",
}
ALLOWED_CITATIONS = EXPECTED_STEP_CITATIONS | {
    "3cab69e6fc7458f5b746d32b5b48ce28ab677d5ffa437643f3f1ad558f6b24cb"
}
HEX = re.compile(r"^[0-9a-f]{64}$")


def fail(reason: str) -> NoReturn:
    print(f"live_grounded_generation_evaluation=blocked;reason={reason}")
    raise SystemExit(1)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact", required=True)
    parser.add_argument("--expected-source-sha256", required=True)
    parser.add_argument("--expected-request-identity", required=True)
    parser.add_argument("--expected-prompt-identity", required=True)
    arguments = parser.parse_args()
    path = Path(arguments.artifact)
    if not path.is_file() or path.is_symlink():
        fail("artifact_missing_or_unsafe")
    for identity in (
        arguments.expected_source_sha256,
        arguments.expected_request_identity,
        arguments.expected_prompt_identity,
    ):
        if HEX.fullmatch(identity) is None:
            fail("expected_identity_invalid")
    try:
        artifact = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail("artifact_invalid")
    required = {
        "answer", "answer_sha256", "claims", "completion_tokens", "finish_reason",
        "model", "prompt_identity", "prompt_tokens", "purpose", "request_identity",
        "schema_version", "source_sha256", "synthetic_only", "total_tokens",
    }
    if not isinstance(artifact, dict) or set(artifact) != required:
        fail("artifact_contract_mismatch")
    if (
        artifact["purpose"] != "bounded_live_grounded_generation"
        or artifact["schema_version"] != 1
        or artifact["synthetic_only"] is not True
        or artifact["model"] != EXPECTED_MODEL
        or artifact["source_sha256"] != arguments.expected_source_sha256
        or artifact["request_identity"] != arguments.expected_request_identity
        or artifact["prompt_identity"] != arguments.expected_prompt_identity
        or artifact["finish_reason"] != "stop"
        or artifact["prompt_tokens"] != EXPECTED_PROMPT_TOKENS
        or type(artifact["completion_tokens"]) is not int
        or not 1 <= artifact["completion_tokens"] <= 2048
        or artifact["total_tokens"]
        != artifact["prompt_tokens"] + artifact["completion_tokens"]
    ):
        fail("artifact_contract_mismatch")
    answer = artifact["answer"]
    claims = artifact["claims"]
    if (
        not isinstance(answer, str)
        or not answer.strip()
        or hashlib.sha256(answer.encode("utf-8")).hexdigest() != artifact["answer_sha256"]
        or not isinstance(claims, list)
        or not claims
    ):
        fail("answer_contract_mismatch")
    claim_texts: list[str] = []
    used_citations: set[str] = set()
    for claim in claims:
        if not isinstance(claim, dict) or set(claim) != {"citation_ids", "text"}:
            fail("claim_contract_mismatch")
        text = claim["text"]
        citations = claim["citation_ids"]
        if (
            not isinstance(text, str)
            or not text.strip()
            or not isinstance(citations, list)
            or not citations
            or any(not isinstance(item, str) or item not in ALLOWED_CITATIONS for item in citations)
        ):
            fail("claim_contract_mismatch")
        claim_texts.append(text)
        used_citations.update(citations)
    if answer != " ".join(claim_texts):
        fail("citation_coverage_mismatch")
    normalized = " ".join(answer.lower().split())
    if "evt-0001" not in normalized or "detection time" not in normalized:
        fail("held_out_answer_content_mismatch")
    if not EXPECTED_STEP_CITATIONS <= used_citations:
        fail("held_out_citation_coverage_mismatch")

    print("purpose=evaluate_bounded_live_grounded_generation")
    print(f"model={EXPECTED_MODEL};prompt_tokens={artifact['prompt_tokens']};completion_tokens={artifact['completion_tokens']};total_tokens={artifact['total_tokens']}")
    print(f"request_identity={artifact['request_identity']};prompt_identity={artifact['prompt_identity']}")
    print(f"claims={len(claims)};distinct_citations={len(used_citations)};answer_sha256={artifact['answer_sha256']}")
    print("strict_response_validation=pass;held_out_answer_content=pass;held_out_citation_coverage=pass")
    print("synthetic_only=true;raw_text_in_routine_report=false")
    print("live_grounded_generation_evaluation=pass")
    print(f"generation_artifact_sha256={sha256_file(path)}")


if __name__ == "__main__":
    main()
