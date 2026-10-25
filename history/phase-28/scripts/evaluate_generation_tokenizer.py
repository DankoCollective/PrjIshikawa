#!/usr/bin/env python3
"""Evaluate one content-free generation-tokenizer measurement artifact."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, NoReturn


EXPECTED_MODEL = "google/gemma-4-26B-A4B-it"
EXPECTED_MAX_MODEL_LEN = 204800
HEX = re.compile(r"^[0-9a-f]{64}$")


def fail(reason: str) -> NoReturn:
    print(f"generation_tokenizer_evaluation=blocked;reason={reason}")
    raise SystemExit(1)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def digest_identity(domain: str, value: Any) -> str:
    return hashlib.sha256(domain.encode("ascii") + b"\0" + canonical_bytes(value)).hexdigest()


def self_test() -> None:
    files = {
        "chat_template.jinja": "f" * 64,
        "config.json": "c" * 64,
        "tokenizer.json": "d" * 64,
        "tokenizer_config.json": "e" * 64,
    }
    image_id = "sha256:" + "a" * 64
    manifest = "b" * 64
    identity = digest_identity(
        "ishikawa.generation-tokenizer.v1",
        {
            "served_model": EXPECTED_MODEL,
            "model_manifest_sha256": manifest,
            "config_sha256": files["config.json"],
            "tokenizer_json_sha256": files["tokenizer.json"],
            "tokenizer_config_sha256": files["tokenizer_config.json"],
            "chat_template_sha256": files["chat_template.jinja"],
            "enable_thinking": False,
            "runtime_image_id": image_id,
        },
    )
    artifact = {
        "schema_version": 1,
        "purpose": "generation_tokenizer_qualification_measurement",
        "source_sha256": "9" * 64,
        "served_model": EXPECTED_MODEL,
        "configured_max_model_len": EXPECTED_MAX_MODEL_LEN,
        "runtime_image_id": image_id,
        "model_manifest_sha256": manifest,
        "tokenizer_files": files,
        "chat_template_sha256": files["chat_template.jinja"],
        "enable_thinking": False,
        "tokenizer_identity": identity,
        "tokenizer_class": "SyntheticTokenizer",
        "vocab_size": 256000,
        "measurements": {
            "candidate_with_special": [11] * 126,
            "candidate_without_special": [10] * 126,
            "whole_procedure_with_special": 501,
            "whole_procedure_without_special": 500,
            "triage_with_special": 101,
            "triage_without_special": 100,
            "whole_procedure_chat_template": 520,
            "triage_chat_template": 120,
        },
        "numeric_budget_status": "pending_review",
        "raw_text_retained": False,
        "model_called": False,
    }
    with tempfile.TemporaryDirectory(prefix="generation-tokenizer-evaluator-") as temporary:
        path = Path(temporary) / "measurement.json"
        path.write_bytes(canonical_bytes(artifact) + b"\n")
        completed = subprocess.run(
            [sys.executable, __file__, "--artifact", str(path), "--expected-source-sha256", "9" * 64],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if completed.returncode != 0 or b"generation_tokenizer_evaluation=pass\n" not in completed.stdout:
            fail("evaluator_self_test_valid_artifact_rejected")
        artifact["tokenizer_identity"] = "8" * 64
        path.write_bytes(canonical_bytes(artifact) + b"\n")
        rejected = subprocess.run(
            [sys.executable, __file__, "--artifact", str(path), "--expected-source-sha256", "9" * 64],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if rejected.returncode == 0 or b"reason=tokenizer_identity_binding_mismatch\n" not in rejected.stdout:
            fail("evaluator_self_test_invalid_identity_accepted")
    print("generation_tokenizer_evaluator_self_test=pass")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact")
    parser.add_argument("--expected-source-sha256")
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test:
        if arguments.artifact is not None or arguments.expected_source_sha256 is not None:
            parser.error("--self-test cannot be combined with artifact arguments")
        self_test()
        return
    if arguments.artifact is None or arguments.expected_source_sha256 is None:
        parser.error("--artifact and --expected-source-sha256 are required")
    path = Path(arguments.artifact)
    if not path.is_file() or path.is_symlink():
        fail("measurement_artifact_unsafe")
    try:
        artifact: Any = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail("measurement_artifact_invalid")
    required = {
        "schema_version", "purpose", "source_sha256", "served_model",
        "configured_max_model_len", "runtime_image_id", "model_manifest_sha256",
        "tokenizer_files", "chat_template_sha256", "tokenizer_identity",
        "enable_thinking", "tokenizer_class", "vocab_size", "measurements", "numeric_budget_status",
        "raw_text_retained", "model_called",
    }
    if not isinstance(artifact, dict) or set(artifact) != required:
        fail("measurement_artifact_contract_mismatch")
    if (
        artifact["schema_version"] != 1
        or artifact["purpose"] != "generation_tokenizer_qualification_measurement"
        or artifact["source_sha256"] != arguments.expected_source_sha256
        or artifact["served_model"] != EXPECTED_MODEL
        or artifact["configured_max_model_len"] != EXPECTED_MAX_MODEL_LEN
        or artifact["numeric_budget_status"] != "pending_review"
        or artifact["enable_thinking"] is not False
        or artifact["raw_text_retained"] is not False
        or artifact["model_called"] is not False
        or not isinstance(artifact["tokenizer_class"], str)
        or not artifact["tokenizer_class"]
        or type(artifact["vocab_size"]) is not int
        or artifact["vocab_size"] < 1
    ):
        fail("measurement_artifact_contract_mismatch")
    for key in ("runtime_image_id", "model_manifest_sha256", "chat_template_sha256", "tokenizer_identity"):
        value = artifact[key]
        if key == "runtime_image_id":
            value = value.removeprefix("sha256:") if isinstance(value, str) else value
        if not isinstance(value, str) or HEX.fullmatch(value) is None:
            fail("measurement_identity_invalid")
    files = artifact["tokenizer_files"]
    if not isinstance(files, dict) or set(files) != {"chat_template.jinja", "config.json", "tokenizer.json", "tokenizer_config.json"}:
        fail("tokenizer_file_identity_invalid")
    if any(not isinstance(value, str) or HEX.fullmatch(value) is None for value in files.values()):
        fail("tokenizer_file_identity_invalid")
    if files["chat_template.jinja"] != artifact["chat_template_sha256"]:
        fail("chat_template_identity_mismatch")
    expected_identity = digest_identity(
        "ishikawa.generation-tokenizer.v1",
        {
            "served_model": artifact["served_model"],
            "model_manifest_sha256": artifact["model_manifest_sha256"],
            "config_sha256": files["config.json"],
            "tokenizer_json_sha256": files["tokenizer.json"],
            "tokenizer_config_sha256": files["tokenizer_config.json"],
            "chat_template_sha256": artifact["chat_template_sha256"],
            "enable_thinking": False,
            "runtime_image_id": artifact["runtime_image_id"],
        },
    )
    if artifact["tokenizer_identity"] != expected_identity:
        fail("tokenizer_identity_binding_mismatch")
    measurements = artifact["measurements"]
    expected_measurements = {
        "candidate_with_special", "candidate_without_special",
        "whole_procedure_with_special", "whole_procedure_without_special",
        "triage_with_special", "triage_without_special",
        "whole_procedure_chat_template", "triage_chat_template",
    }
    if not isinstance(measurements, dict) or set(measurements) != expected_measurements:
        fail("token_measurement_contract_mismatch")
    with_special = measurements["candidate_with_special"]
    without_special = measurements["candidate_without_special"]
    scalars = expected_measurements - {"candidate_with_special", "candidate_without_special"}
    if (
        not isinstance(with_special, list)
        or not isinstance(without_special, list)
        or len(with_special) != 126
        or len(without_special) != 126
        or any(type(value) is not int or value < 1 for value in with_special + without_special)
        or any(type(measurements[key]) is not int or measurements[key] < 1 for key in scalars)
        or any(value >= EXPECTED_MAX_MODEL_LEN for value in with_special + without_special)
        or any(measurements[key] >= EXPECTED_MAX_MODEL_LEN for key in scalars)
    ):
        fail("token_measurement_invalid")
    if (
        measurements["whole_procedure_with_special"] < max(with_special)
        or measurements["whole_procedure_without_special"] < max(without_special)
        or measurements["triage_with_special"] > measurements["whole_procedure_with_special"]
        or measurements["triage_without_special"] > measurements["whole_procedure_without_special"]
    ):
        fail("structural_token_measurement_inconsistent")
    if (
        measurements["whole_procedure_chat_template"] <= measurements["whole_procedure_with_special"]
        or measurements["triage_chat_template"] <= measurements["triage_with_special"]
        or measurements["whole_procedure_chat_template"] <= measurements["triage_chat_template"]
    ):
        fail("chat_template_token_measurement_inconsistent")
    print("purpose=evaluate_generation_tokenizer_qualification")
    print(f"served_model={EXPECTED_MODEL};configured_max_model_len={EXPECTED_MAX_MODEL_LEN}")
    print(f"tokenizer_identity={artifact['tokenizer_identity']};tokenizer_class={artifact['tokenizer_class']};vocab_size={artifact['vocab_size']}")
    print(f"synthetic_candidates=126;minimum_tokens={min(with_special)};maximum_tokens={max(with_special)}")
    print(
        f"whole_procedure_units=15;whole_procedure_tokens={measurements['whole_procedure_chat_template']};"
        f"triage_units=3;triage_tokens={measurements['triage_chat_template']}"
    )
    print("model_called=false;credential_read=false;raw_text_retained=false")
    print("numeric_budget_calibration=pending_review")
    print("generation_tokenizer_evaluation=pass")
    print(f"measurement_artifact_sha256={sha256_file(path)}")


if __name__ == "__main__":
    main()
