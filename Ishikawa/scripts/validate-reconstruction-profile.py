#!/usr/bin/env python3
"""Validate and identify one Ishikawa reconstruction profile."""

from __future__ import annotations

import argparse
from pathlib import Path

from ishikawa.reconstruction import validate_reconstruction_profile
from ishikawa.yaml_loader import load_restricted_yaml


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", required=True)
    arguments = parser.parse_args()
    profile_path = Path(arguments.profile)
    if not profile_path.is_file() or profile_path.is_symlink():
        raise SystemExit("reconstruction_profile_validation=blocked;reason=profile_unsafe")
    value = load_restricted_yaml(profile_path, label="reconstruction profile")
    policy = validate_reconstruction_profile(value)
    print(f"reconstruction_policy_id={policy.digest}")
    print(
        f"total_context_tokens={policy.total_context_tokens};"
        f"instruction_token_limit={policy.instruction_token_limit};"
        f"conversation_token_limit={policy.conversation_token_limit};"
        f"evidence_token_limit={policy.evidence_token_limit};"
        f"answer_token_reserve={policy.answer_token_reserve}"
    )
    print(
        f"normal_per_document_limit={policy.normal_per_document_limit};"
        f"explicit_document_limit={policy.explicit_document_limit}"
    )
    print("reconstruction_profile_validation=pass")


if __name__ == "__main__":
    main()
