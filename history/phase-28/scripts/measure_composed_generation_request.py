#!/usr/bin/env python3
"""Measure one synthetic request with the installed generation tokenizer.

The exact configured runtime image is used in a temporary network-disabled
container with the model directory mounted read-only. No credential is read,
no endpoint is contacted, and no raw request text is retained in the result.
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
APPLICATION_CONTEXT_LIMIT = 32768
ANSWER_TOKEN_RESERVE = 2048
HEX = re.compile(r"^[0-9a-f]{64}$")
MANIFEST_LINE = re.compile(r"^([0-9a-f]{64}) [ *](.+)$")


def fail(reason: str) -> NoReturn:
    print(f"[composed-request] result=BLOCKED reason={reason}")
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


def require_identity(value: Any, reason: str) -> str:
    if not isinstance(value, str) or HEX.fullmatch(value) is None:
        fail(reason)
    return value


def load_request(path: Path, expected_sha256: str) -> dict[str, Any]:
    if not HEX.fullmatch(expected_sha256) or sha256_file(path) != expected_sha256:
        fail("synthetic_request_identity_mismatch")
    artifact = load_json(path, "synthetic_request_invalid")
    expected = {
        "body", "chunk_source_sha256", "prompt_identity", "purpose",
        "reconstruction_policy_identity", "request_identity", "schema_version",
        "synthetic_only",
    }
    if not isinstance(artifact, dict) or set(artifact) != expected:
        fail("synthetic_request_contract_mismatch")
    if (
        artifact["schema_version"] != 1
        or artifact["purpose"] != "synthetic_grounded_generation_request"
        or artifact["synthetic_only"] is not True
    ):
        fail("synthetic_request_contract_mismatch")
    for name in ("chunk_source_sha256", "prompt_identity", "reconstruction_policy_identity", "request_identity"):
        require_identity(artifact[name], "synthetic_request_identity_invalid")
    body = artifact["body"]
    if not isinstance(body, dict) or set(body) != {
        "chat_template_kwargs", "max_tokens", "messages", "model", "stream",
        "temperature", "top_k", "top_p",
    }:
        fail("request_body_contract_mismatch")
    if (
        body["model"] != EXPECTED_MODEL
        or body["max_tokens"] != ANSWER_TOKEN_RESERVE
        or body["stream"] is not False
        or body["temperature"] != 1.0
        or body["top_p"] != 0.95
        or body["top_k"] != 64
        or body["chat_template_kwargs"] != {"enable_thinking": False}
    ):
        fail("request_generation_settings_mismatch")
    messages = body["messages"]
    if (
        not isinstance(messages, list)
        or len(messages) != 2
        or set(messages[0]) != {"content", "role"}
        or set(messages[1]) != {"content", "role"}
        or messages[0]["role"] != "system"
        or messages[1]["role"] != "user"
        or any(not isinstance(item["content"], str) or not item["content"] for item in messages)
    ):
        fail("request_message_contract_mismatch")
    try:
        payload = json.loads(messages[1]["content"])
    except (TypeError, json.JSONDecodeError):
        fail("request_payload_invalid")
    if (
        not isinstance(payload, dict)
        or payload.get("schema") != "ishikawa.grounded-generation-input.v1"
        or len(payload.get("conversation", [])) != 2
        or len(payload.get("evidence", [])) != 3
        or len(payload.get("allowed_citation_ids", [])) != 3
    ):
        fail("request_payload_contract_mismatch")
    if canonical_bytes(payload).decode("utf-8") != messages[1]["content"]:
        fail("request_payload_not_canonical")
    return artifact


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


def inspect_image(config: dict[str, Any]) -> tuple[str, str]:
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


def measure_in_container(image_reference: str, model_path: Path, body: dict[str, Any]) -> dict[str, Any]:
    code = r'''import hashlib,json,sys
from transformers import AutoTokenizer
b=json.load(sys.stdin)
t=AutoTokenizer.from_pretrained('/models/gemma',local_files_only=True,trust_remote_code=False)
def enc(value):
    tokens=t.encode(value,add_special_tokens=False)
    return len(tokens)
messages=b['messages']
tokens=t.apply_chat_template(messages,tokenize=True,add_generation_prompt=True,enable_thinking=False)
if hasattr(tokens,'get'):
    tokens=tokens.get('input_ids')
if hasattr(tokens,'tolist'):
    tokens=tokens.tolist()
while isinstance(tokens,list) and len(tokens)==1 and isinstance(tokens[0],list):
    tokens=tokens[0]
if not isinstance(tokens,list) or not tokens or any(not isinstance(item,int) for item in tokens):
    raise SystemExit(4)
payload=json.loads(messages[1]['content'])
template=t.chat_template
if not isinstance(template,str) or not template:
    raise SystemExit(3)
result={
 'tokenizer_class':type(t).__name__,
 'vocab_size':len(t),
 'chat_template_sha256':hashlib.sha256(template.encode('utf-8')).hexdigest(),
 'prompt_tokens':len(tokens),
 'system_content_tokens':enc(messages[0]['content']),
 'untrusted_payload_tokens':enc(messages[1]['content']),
 'history_content_tokens':[enc(item['content']) for item in payload['conversation']],
 'question_tokens':enc(payload['question']),
 'evidence_excerpt_tokens':[enc(item['excerpt']) for item in payload['evidence']],
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
    completed = run(command, input_bytes=canonical_bytes(body), timeout=600)
    if completed.returncode != 0:
        fail("isolated_tokenizer_execution_failed")
    try:
        result = json.loads(completed.stdout)
    except (UnicodeError, json.JSONDecodeError):
        fail("isolated_tokenizer_output_invalid")
    expected = {
        "tokenizer_class", "vocab_size", "chat_template_sha256", "prompt_tokens",
        "system_content_tokens", "untrusted_payload_tokens", "history_content_tokens",
        "question_tokens", "evidence_excerpt_tokens",
    }
    scalar = expected - {
        "tokenizer_class", "chat_template_sha256", "history_content_tokens",
        "evidence_excerpt_tokens",
    }
    if (
        not isinstance(result, dict)
        or set(result) != expected
        or not isinstance(result["tokenizer_class"], str)
        or not result["tokenizer_class"]
        or not HEX.fullmatch(result["chat_template_sha256"] or "")
        or any(type(result[name]) is not int or result[name] < 1 for name in scalar)
        or not isinstance(result["history_content_tokens"], list)
        or len(result["history_content_tokens"]) != 2
        or not isinstance(result["evidence_excerpt_tokens"], list)
        or len(result["evidence_excerpt_tokens"]) != 3
        or any(type(item) is not int or item < 1 for item in result["history_content_tokens"] + result["evidence_excerpt_tokens"])
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
    request = load_request(input_path, arguments.expected_input_sha256)
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
    image_reference, image_id = inspect_image(config)
    measured = measure_in_container(image_reference, model_path, request["body"])
    if measured["chat_template_sha256"] != observed_files["chat_template.jinja"]:
        fail("active_chat_template_identity_mismatch")
    total_reserved = measured["prompt_tokens"] + ANSWER_TOKEN_RESERVE
    if total_reserved > APPLICATION_CONTEXT_LIMIT:
        fail("application_context_limit_exceeded")
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
        "application_context_limit": APPLICATION_CONTEXT_LIMIT,
        "chat_template_sha256": measured["chat_template_sha256"],
        "configured_max_model_len": EXPECTED_MAX_MODEL_LEN,
        "enable_thinking": False,
        "measurements": {
            **{key: value for key, value in measured.items() if key not in {"tokenizer_class", "vocab_size", "chat_template_sha256"}},
            "answer_token_reserve": ANSWER_TOKEN_RESERVE,
            "application_remaining_tokens": APPLICATION_CONTEXT_LIMIT - total_reserved,
            "service_remaining_tokens": EXPECTED_MAX_MODEL_LEN - total_reserved,
            "total_reserved_tokens": total_reserved,
        },
        "model_called": False,
        "model_manifest_sha256": tokenizer_identity_input["model_manifest_sha256"],
        "prompt_identity": request["prompt_identity"],
        "purpose": "composed_generation_request_token_measurement",
        "raw_text_retained": False,
        "reconstruction_policy_identity": request["reconstruction_policy_identity"],
        "request_identity": request["request_identity"],
        "runtime_image_id": image_id,
        "schema_version": 1,
        "served_model": EXPECTED_MODEL,
        "source_sha256": arguments.expected_input_sha256,
        "tokenizer_class": measured["tokenizer_class"],
        "tokenizer_files": observed_files,
        "tokenizer_identity": digest_identity("ishikawa.generation-tokenizer.v1", tokenizer_identity_input),
        "vocab_size": measured["vocab_size"],
    }
    try:
        descriptor = os.open(output_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(canonical_bytes(artifact) + b"\n")
    except OSError:
        fail("measurement_artifact_write_failed")
    print(
        "[composed-request] identity=pass template=pass request=pass budget=pass "
        f"prompt_tokens={measured['prompt_tokens']} total_reserved_tokens={total_reserved} "
        "raw_text_retained=false model_called=false credential_read=false"
    )
    print("[composed-request] result=PASS next=request_transport_and_response_validation")


if __name__ == "__main__":
    main()
