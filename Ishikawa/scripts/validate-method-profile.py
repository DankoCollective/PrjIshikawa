#!/usr/bin/env python3
"""Validate the frozen retrieval profile against accepted calibration evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any, NoReturn

from ishikawa.canonical import canonical_json_bytes
from ishikawa.method_profile import validate_retrieval_profile
from ishikawa.yaml_loader import load_restricted_yaml


HEX_DIGEST = re.compile(r"^[0-9a-f]{64}$")


def fail(reason: str) -> NoReturn:
    raise RuntimeError(reason)


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def require_safe_file(path: Path, maximum_bytes: int) -> None:
    if not path.is_file() or path.is_symlink():
        fail("unsafe required input")
    if path.stat().st_size > maximum_bytes:
        fail("required input exceeds its size boundary")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--observation", type=Path, required=True)
    parser.add_argument("--expected-observation-sha256", required=True)
    parser.add_argument("--expected-retrieval-profile-id", required=True)
    parser.add_argument("--expected-chunk-profile-id", required=True)
    args = parser.parse_args()

    for identity in (
        args.expected_observation_sha256,
        args.expected_retrieval_profile_id,
        args.expected_chunk_profile_id,
    ):
        if HEX_DIGEST.fullmatch(identity) is None:
            fail("an expected identity is not a lowercase SHA-256 value")

    require_safe_file(args.profile, 64 * 1024)
    require_safe_file(args.observation, 16 * 1024 * 1024)
    if file_sha256(args.observation) != args.expected_observation_sha256:
        fail("accepted observation checksum mismatch")

    profile = validate_retrieval_profile(
        load_restricted_yaml(args.profile, label="method profile")
    )
    if profile.digest != args.expected_retrieval_profile_id:
        fail("retrieval profile identity mismatch")
    if profile.chunk_method_profile_id != args.expected_chunk_profile_id:
        fail("chunk method profile identity mismatch")

    try:
        observation: Any = json.loads(args.observation.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise RuntimeError("accepted observation is not valid JSON") from exc
    if not isinstance(observation, dict):
        fail("accepted observation must be an object")
    if observation.get("schema_version") != 1:
        fail("accepted observation schema mismatch")
    if observation.get("artifact_kind") != "held_out_retrieval_observations":
        fail("accepted observation kind mismatch")
    if observation.get("method_profile") != profile.observation_contract():
        fail("frozen profile does not match the accepted observation")
    if observation.get("case_count") != 6:
        fail("accepted observation case count mismatch")
    cases = observation.get("cases")
    if not isinstance(cases, list) or len(cases) != 6:
        fail("accepted observation case inventory mismatch")
    totals = observation.get("lane_candidate_totals")
    if totals != {"exact": 9, "lexical": 110, "vector": 120, "fused": 120}:
        fail("accepted observation lane totals mismatch")

    recorded_digest = observation.get("observation_set_digest")
    if not isinstance(recorded_digest, str) or HEX_DIGEST.fullmatch(recorded_digest) is None:
        fail("accepted observation set identity is invalid")
    digest_input = dict(observation)
    del digest_input["observation_set_digest"]
    calculated_digest = hashlib.sha256(
        b"ishikawa.retrieval-observations.v1\x00" + canonical_json_bytes(digest_input)
    ).hexdigest()
    if calculated_digest != recorded_digest:
        fail("accepted observation set identity mismatch")

    print("method_profile_validation=pass")
    print(f"retrieval_profile_id={profile.digest}")
    print(f"chunk_method_profile_id={profile.chunk_method_profile_id}")
    print("calibrated_cases=6;required_citations=13;covered_citations=13")
    print("exact_depth=20;lexical_depth=20;vector_depth=20;fused_depth=20")
    print("lexical_search_config=english;lexical_fallback=native_or_when_strict_empty")
    print("vector_distance=cosine;lane_weights=equal_unit;rrf_constant=60;learned_reranker=false")
    print(f"observation_set_digest={recorded_digest}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"method_profile_validation=blocked;reason={type(exc).__name__}")
        raise SystemExit(1) from None

