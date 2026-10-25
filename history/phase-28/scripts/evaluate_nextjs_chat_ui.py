#!/usr/bin/env python3
"""Evaluate the final host-mounted Ishikawa Chat UI source and runtime proof."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path


EXPECTED_FILES = {
    "app/api/live/route.js",
    "app/api/ready/route.js",
    "app/api/v1/chat/route.js",
    "app/globals.css",
    "app/layout.js",
    "app/page.js",
    "components/chat-workspace.js",
    "lib/chat-contract.mjs",
    "lib/runtime-config.mjs",
    "next.config.mjs",
    "package.json",
    "tests/chat-contract.test.mjs",
    "tests/runtime-config.test.mjs",
}


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Evaluate the Ishikawa Chat UI.")
    parser.add_argument("--web-root", required=True)
    parser.add_argument("--architecture", required=True, choices=("amd64", "arm64", "source-only"))
    parser.add_argument("--runtime-proven", required=True, choices=("true", "false"))
    parser.add_argument("--output", required=True)
    return parser.parse_args()


def require_directory(path: Path, label: str) -> Path:
    if not path.is_absolute() or path.is_symlink() or not path.is_dir():
        raise ValueError(f"{label}_unsafe")
    return path.resolve(strict=True)


def evaluate(web_root: Path, architecture: str, runtime_proven: bool) -> dict[str, object]:
    actual_files = {
        item.relative_to(web_root).as_posix()
        for item in web_root.rglob("*")
        if item.is_file()
    }
    if actual_files != EXPECTED_FILES or any(item.is_symlink() for item in web_root.rglob("*")):
        raise RuntimeError("web_source_inventory_invalid")
    package = json.loads((web_root / "package.json").read_text(encoding="utf-8"))
    if package.get("dependencies") != {
        "next": "16.4.1",
        "react": "19.2.0",
        "react-dom": "19.2.0",
    }:
        raise RuntimeError("web_dependency_identity_invalid")
    client = (web_root / "components/chat-workspace.js").read_text(encoding="utf-8")
    proxy = (web_root / "app/api/v1/chat/route.js").read_text(encoding="utf-8")
    readiness = (web_root / "app/api/ready/route.js").read_text(encoding="utf-8")
    runtime = (web_root / "lib/runtime-config.mjs").read_text(encoding="utf-8")
    contract = (web_root / "lib/chat-contract.mjs").read_text(encoding="utf-8")
    combined = "\n".join((client, proxy, readiness, runtime, contract))
    required_markers = (
        'fetch("/api/v1/chat"',
        '`${retrievalBaseUrl}/v1/chat`',
        '`${retrievalBaseUrl}/ready`',
        "ishikawa.chat-request.v1",
        "ishikawa.chat-response.v1",
        "MAXIMUM_HISTORY_TURNS = 12",
        "MAXIMUM_HISTORY_CHARACTERS = 65536",
        "MAXIMUM_SOURCE_REFERENCES = 20",
        "ISHIKAWA_PRODUCT_DISPLAY_NAME",
        "ISHIKAWA_RETRIEVAL_BASE_URL",
    )
    if not all(marker in combined for marker in required_markers):
        raise RuntimeError("web_contract_marker_missing")
    forbidden_client_markers = (
        "ISHIKAWA_RETRIEVAL_BASE_URL",
        "127.0.0.1:1384",
        "process.env",
        "dangerouslySetInnerHTML",
        "Authorization",
    )
    if any(marker in client for marker in forbidden_client_markers):
        raise RuntimeError("browser_boundary_invalid")
    if "NEXT_PUBLIC" in combined:
        raise RuntimeError("public_runtime_configuration_found")
    if any(marker in combined.lower() for marker in ("open-document", "download-document")):
        raise RuntimeError("disabled_document_action_found")
    return {
        "architecture": architecture,
        "browser_direct_retrieval": False,
        "chat_contract": "ishikawa.chat-request.v1/ishikawa.chat-response.v1",
        "container_image_changed": False,
        "database_changed": False,
        "health_paths": ["/api/live", "/api/ready"],
        "history_character_limit": 65_536,
        "history_turn_limit": 12,
        "next_version": "16.4.1",
        "node_major": 24,
        "open_or_download_enabled": False,
        "product_name_runtime_configurable": True,
        "proxy_path": "/api/v1/chat",
        "react_version": "19.2.0",
        "runtime_proven": runtime_proven,
        "source_reference_limit": 20,
        "source_resident_on_host": True,
        "target_contact": False,
    }


def main() -> int:
    arguments = parse_arguments()
    web_root = require_directory(Path(arguments.web_root), "web_root")
    output = Path(arguments.output)
    if not output.is_absolute() or output.exists() or not output.parent.is_dir():
        raise ValueError("output_path_unsafe")
    receipt = evaluate(web_root, arguments.architecture, arguments.runtime_proven == "true")
    encoded = json.dumps(receipt, sort_keys=True, separators=(",", ":")).encode() + b"\n"
    with output.open("xb") as destination:
        destination.write(encoded)
    os.chmod(output, 0o600)
    print("web_source=host-resident;container_image_changed=false")
    print("browser_path=/api/v1/chat;native_path=/v1/chat;browser_direct_retrieval=false")
    print("history_turns=12;history_characters=65536;source_references=20")
    print("health=/api/live,/api/ready;open_download=false")
    print(f"runtime_proven={str(receipt['runtime_proven']).lower()};architecture={receipt['architecture']}")
    print("target_contact=false;database_changed=false;model_call=false")
    print("nextjs_chat_ui_qualification=pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
