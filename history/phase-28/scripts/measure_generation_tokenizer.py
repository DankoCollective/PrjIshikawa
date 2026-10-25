#!/usr/bin/env python3
"""Measure synthetic evidence with the installed generation tokenizer.

The measurement runs in a temporary, network-disabled container created from
the exact configured runtime image. The model directory is mounted read-only.
No credential is read, no model endpoint is called, and no raw text is written
to the output artifact.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import subprocess
from pathlib import Path, PurePosixPath
from typing import Any, NoReturn


INSTALLED_CONFIG = Path("/etc/ai-runtime/vllm/vllm-container-services-site-config.json")
INSTALL_RECORD = Path("/var/lib/ai-runtime/vllm/install-records/current.json")
EXPECTED_MODEL = "google/gemma-4-26B-A4B-it"
EXPECTED_MAX_MODEL_LEN = 204800
HEX = re.compile(r"^[0-9a-f]{64}$")
MANIFEST_LINE = re.compile(r"^([0-9a-f]{64}) [ *](.+)$")


def fail(reason: str) -> NoReturn:
    print(f"[generation-tokenizer] result=BLOCKED reason={reason}")
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


def load_json(path: Path, reason: str) -> Any:
    try:
        metadata = path.lstat()
        if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
            fail(reason)
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail(reason)


def parse_manifest(path: Path) -> dict[str, str]:
    try:
        metadata = path.lstat()
        if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
            fail("model_manifest_unsafe")
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError):
        fail("model_manifest_unreadable")
    entries: dict[str, str] = {}
    for line in lines:
        match = MANIFEST_LINE.fullmatch(line)
        if match is None:
            fail("model_manifest_invalid")
        digest, relative = match.groups()
        candidate = PurePosixPath(relative)
        if candidate.is_absolute() or ".." in candidate.parts or relative in entries:
            fail("model_manifest_invalid")
        entries[relative] = digest
    if not entries:
        fail("model_manifest_empty")
    return entries


def require_profile(config: Any) -> dict[str, Any]:
    if not isinstance(config, dict) or config.get("schema") not in {
        "vllm-container-services-site-config/v1",
        "vllm-container-services-site-config/v2.5",
    }:
        fail("installed_configuration_invalid")
    models = config.get("models")
    matches = [item for item in models or [] if isinstance(item, dict) and item.get("profile") == "gemma"]
    if len(matches) != 1:
        fail("generation_profile_missing_or_ambiguous")
    profile = matches[0]
    runtime = profile.get("runtime")
    reasoning = profile.get("reasoning")
    if (
        profile.get("enabled") is not True
        or profile.get("served_model_name") != EXPECTED_MODEL
        or not isinstance(runtime, dict)
        or runtime.get("max_model_len") != EXPECTED_MAX_MODEL_LEN
        or profile.get("runner") != "generate"
        or not isinstance(reasoning, dict)
        or reasoning.get("parser") != "gemma4"
        or reasoning.get("default_enable_thinking") is not False
    ):
        fail("generation_profile_contract_mismatch")
    return profile


def load_measurement_input(path: Path, expected_sha256: str) -> dict[str, Any]:
    if not HEX.fullmatch(expected_sha256) or sha256_file(path) != expected_sha256:
        fail("synthetic_input_identity_mismatch")
    artifact = load_json(path, "synthetic_input_invalid")
    documents = artifact.get("documents") if isinstance(artifact, dict) else None
    if not isinstance(documents, list) or len(documents) != 6:
        fail("synthetic_document_inventory_mismatch")
    candidates = [candidate for document in documents for candidate in document.get("candidates", [])]
    if len(candidates) != 126:
        fail("synthetic_candidate_inventory_mismatch")
    texts = [item.get("retrieval_text") for item in candidates]
    if any(not isinstance(text, str) or not text.strip() or "\x00" in text for text in texts):
        fail("synthetic_candidate_text_invalid")
    procedures = [document for document in documents if document.get("document_ref") == "SYN-006"]
    if len(procedures) != 1 or len(procedures[0].get("candidates", [])) != 15:
        fail("synthetic_procedure_inventory_mismatch")
    ordered = sorted(
        procedures[0]["candidates"],
        key=lambda item: item.get("projection_properties", {}).get("source_ordinal", -1),
    )
    triage = [
        item
        for item in ordered
        if item.get("citation_anchor", {}).get("structural_path") == ["II. Triage Sequence"]
    ]
    if len(triage) != 3:
        fail("synthetic_triage_inventory_mismatch")
    whole_text = "\n\n".join(item["retrieval_text"] for item in ordered)
    triage_text = "\n\n".join(item["retrieval_text"] for item in triage)
    return {
        "candidate_texts": texts,
        "whole_procedure_text": whole_text,
        "triage_text": triage_text,
    }


def run(arguments: list[str], *, input_bytes: bytes | None = None, timeout: int = 300) -> subprocess.CompletedProcess[bytes]:
    try:
        return subprocess.run(
            arguments,
            input=input_bytes,
            stdin=subprocess.DEVNULL if input_bytes is None else None,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        fail("isolated_tokenizer_execution_failed")


def inspect_image(profile: dict[str, Any], config: dict[str, Any]) -> tuple[str, str]:
    image = config.get("image")
    if not isinstance(image, dict):
        fail("configured_image_invalid")
    reference = image.get("reference")
    expected_id = image.get("id")
    if not isinstance(reference, str) or not reference or not isinstance(expected_id, str):
        fail("configured_image_invalid")
    completed = run([
        "/usr/bin/docker", "image", "inspect", reference,
        "--format", "{{.Id}} {{.Architecture}}/{{.Os}}",
    ])
    try:
        observed = completed.stdout.decode("ascii").strip().split()
    except UnicodeError:
        fail("configured_image_inspection_failed")
    expected_platform = image.get("platform")
    platform = f"{expected_platform.get('architecture')}/{expected_platform.get('os')}" if isinstance(expected_platform, dict) else ""
    if completed.returncode != 0 or observed != [expected_id, platform]:
        fail("configured_image_identity_mismatch")
    return reference, expected_id


def measure_in_container(image_reference: str, model_path: Path, request: dict[str, Any]) -> dict[str, Any]:
    code = r'''import hashlib,json,sys
from transformers import AutoTokenizer
x=json.load(sys.stdin)
t=AutoTokenizer.from_pretrained('/models/gemma',local_files_only=True,trust_remote_code=False)
enc=lambda value,special:len(t.encode(value,add_special_tokens=special))
candidate_with=[enc(value,True) for value in x['candidate_texts']]
candidate_without=[enc(value,False) for value in x['candidate_texts']]
def chat_count(question,evidence):
    content='Question:\n'+question+'\n\nEvidence:\n'+evidence
    tokens=t.apply_chat_template([{'role':'user','content':content}],tokenize=True,add_generation_prompt=True,enable_thinking=False)
    if hasattr(tokens,'get'):
        tokens=tokens.get('input_ids')
    if hasattr(tokens,'tolist'):
        tokens=tokens.tolist()
    while isinstance(tokens,list) and len(tokens)==1 and isinstance(tokens[0],list):
        tokens=tokens[0]
    if not isinstance(tokens,list) or not tokens or any(not isinstance(item,int) for item in tokens):
        raise SystemExit(4)
    return len(tokens)
template=t.chat_template
if not isinstance(template,str) or not template:
    raise SystemExit(3)
result={
 'tokenizer_class':type(t).__name__,
 'vocab_size':len(t),
 'chat_template_sha256':hashlib.sha256(template.encode('utf-8')).hexdigest(),
 'candidate_with_special':candidate_with,
 'candidate_without_special':candidate_without,
 'whole_procedure_with_special':enc(x['whole_procedure_text'],True),
 'whole_procedure_without_special':enc(x['whole_procedure_text'],False),
 'triage_with_special':enc(x['triage_text'],True),
 'triage_without_special':enc(x['triage_text'],False),
 'whole_procedure_chat_template':chat_count('Provide the complete procedure.',x['whole_procedure_text']),
 'triage_chat_template':chat_count('What are the required triage steps?',x['triage_text']),
}
print(json.dumps(result,sort_keys=True,separators=(',',':')))
'''
    command = [
        "/usr/bin/docker", "run", "--rm", "--network", "none", "--read-only",
        "--pull", "never", "--tmpfs", "/tmp:rw,noexec,nosuid,nodev,size=64m",
        "--env", "HF_HUB_OFFLINE=1", "--env", "TRANSFORMERS_OFFLINE=1",
        "--env", "HF_HOME=/tmp/hf", "--env", "PYTHONDONTWRITEBYTECODE=1",
        "--volume", f"{model_path}:/models/gemma:ro", "--entrypoint", "python3",
        "-i", image_reference, "-c", code,
    ]
    completed = run(command, input_bytes=canonical_bytes(request), timeout=600)
    if completed.returncode != 0:
        fail("isolated_tokenizer_execution_failed")
    try:
        result = json.loads(completed.stdout)
    except (UnicodeError, json.JSONDecodeError):
        fail("isolated_tokenizer_output_invalid")
    expected = {
        "tokenizer_class", "vocab_size", "chat_template_sha256",
        "candidate_with_special", "candidate_without_special",
        "whole_procedure_with_special", "whole_procedure_without_special",
        "triage_with_special", "triage_without_special",
        "whole_procedure_chat_template", "triage_chat_template",
    }
    if not isinstance(result, dict) or set(result) != expected:
        fail("isolated_tokenizer_output_invalid")
    with_special = result["candidate_with_special"]
    without_special = result["candidate_without_special"]
    scalar_keys = expected - {"tokenizer_class", "chat_template_sha256", "candidate_with_special", "candidate_without_special"}
    if (
        not isinstance(result["tokenizer_class"], str)
        or not result["tokenizer_class"]
        or not HEX.fullmatch(result["chat_template_sha256"] or "")
        or not isinstance(with_special, list)
        or not isinstance(without_special, list)
        or len(with_special) != 126
        or len(without_special) != 126
        or any(type(value) is not int or value < 1 for value in with_special + without_special)
        or any(type(result[key]) is not int or result[key] < 1 for key in scalar_keys)
    ):
        fail("isolated_tokenizer_output_invalid")
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--expected-input-sha256", required=True)
    parser.add_argument("--output", required=True)
    arguments = parser.parse_args()
    if os.geteuid() != 0:
        fail("root_execution_required")
    input_path = Path(arguments.input)
    output_path = Path(arguments.output)
    if output_path.exists() or output_path.is_symlink() or not output_path.parent.is_dir():
        fail("output_path_unsafe")
    source = load_measurement_input(input_path, arguments.expected_input_sha256)
    config = load_json(INSTALLED_CONFIG, "installed_configuration_invalid")
    install_record = load_json(INSTALL_RECORD, "installation_record_invalid")
    if (
        not isinstance(install_record, dict)
        or install_record.get("configuration_sha256") != sha256_file(INSTALLED_CONFIG)
    ):
        fail("installed_configuration_receipt_mismatch")
    profile = require_profile(config)
    model_path = Path(profile.get("model_path", ""))
    if not model_path.is_absolute() or not model_path.is_dir() or model_path.is_symlink():
        fail("configured_model_path_unsafe")
    manifest_name = profile.get("checksum_manifest")
    if not isinstance(manifest_name, str) or PurePosixPath(manifest_name).name != manifest_name:
        fail("model_manifest_name_invalid")
    manifest_path = model_path / manifest_name
    manifest = parse_manifest(manifest_path)
    observed_files: dict[str, str] = {}
    for name in ("chat_template.jinja", "config.json", "tokenizer.json", "tokenizer_config.json"):
        path = model_path / name
        if name not in manifest or not path.is_file() or path.is_symlink():
            fail("required_tokenizer_artifact_missing_or_unsafe")
        observed = sha256_file(path)
        if observed != manifest[name]:
            fail("required_tokenizer_artifact_identity_mismatch")
        observed_files[name] = observed
    image_reference, image_id = inspect_image(profile, config)
    measured = measure_in_container(image_reference, model_path, source)
    if measured["chat_template_sha256"] != observed_files["chat_template.jinja"]:
        fail("active_chat_template_identity_mismatch")
    tokenizer_identity_input = {
        "served_model": EXPECTED_MODEL,
        "model_manifest_sha256": sha256_file(manifest_path),
        "config_sha256": observed_files["config.json"],
        "tokenizer_json_sha256": observed_files["tokenizer.json"],
        "tokenizer_config_sha256": observed_files["tokenizer_config.json"],
        "chat_template_sha256": measured["chat_template_sha256"],
        "enable_thinking": False,
        "runtime_image_id": image_id,
    }
    artifact = {
        "schema_version": 1,
        "purpose": "generation_tokenizer_qualification_measurement",
        "source_sha256": arguments.expected_input_sha256,
        "served_model": EXPECTED_MODEL,
        "configured_max_model_len": EXPECTED_MAX_MODEL_LEN,
        "runtime_image_id": image_id,
        "model_manifest_sha256": tokenizer_identity_input["model_manifest_sha256"],
        "tokenizer_files": observed_files,
        "chat_template_sha256": measured["chat_template_sha256"],
        "enable_thinking": False,
        "tokenizer_identity": digest_identity("ishikawa.generation-tokenizer.v1", tokenizer_identity_input),
        "tokenizer_class": measured["tokenizer_class"],
        "vocab_size": measured["vocab_size"],
        "measurements": {key: value for key, value in measured.items() if key not in {"tokenizer_class", "vocab_size", "chat_template_sha256"}},
        "numeric_budget_status": "pending_review",
        "raw_text_retained": False,
        "model_called": False,
    }
    try:
        descriptor = os.open(output_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(canonical_bytes(artifact) + b"\n")
    except OSError:
        fail("measurement_artifact_write_failed")
    print(
        "[generation-tokenizer] identity=pass measurement=pass "
        "synthetic_candidates=126 procedure_units=15 triage_units=3 "
        "raw_text_retained=false model_called=false credential_read=false"
    )
    print("[generation-tokenizer] result=PASS next=numeric_budget_review")


if __name__ == "__main__":
    main()
