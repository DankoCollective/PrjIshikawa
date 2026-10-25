#!/usr/bin/env python3
"""Validate the portable Ishikawa operating and architecture documents.

The evaluator compares documented ports, methods, credentials, commands, and
installed paths with the authoritative application configuration and command
sources. It performs no network, database, service, container, or target
operation and writes only a content-free qualification receipt.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any


DOCUMENT_NAMES = (
    "APPLICATION_DEFINITION.md",
    "APPLICATION_DESIGN.md",
    "ARCHITECTURE.md",
    "CHUNKING_INGESTION_RETRIEVAL.md",
    "COMMAND_SHEET.md",
    "OPERATOR_GUIDE.md",
)

FORBIDDEN_DEPLOYMENT_JARGON = re.compile(
    r"phase[-_ ]*[0-9]|org[-_ ]*lab|danko|agent|repository|"
    r"script[\s_-]*[0-9]+|local/artifacts|/mnt/|\.git/",
    re.IGNORECASE,
)

SECRET_MATERIAL = re.compile(
    r"BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY|"
    r"Authorization:\s*Bearer\s+(?!\$|ENVIRONMENT|REDACTED)\S+",
    re.IGNORECASE,
)


class DocumentationQualificationError(ValueError):
    """Stable failure raised when a documentation contract is not met."""


def parse_arguments() -> argparse.Namespace:
    """Parse exact local source locations and one receipt destination."""

    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--docs-root", required=True, type=Path)
    parser.add_argument("--config-root", required=True, type=Path)
    parser.add_argument("--command-root", required=True, type=Path)
    parser.add_argument("--python-root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def safe_directory(path: Path, label: str) -> Path:
    """Resolve one required non-symlink directory."""

    if path.is_symlink() or not path.is_dir():
        raise DocumentationQualificationError(f"{label}_unsafe")
    return path.resolve(strict=True)


def safe_file(path: Path, label: str) -> Path:
    """Resolve one required readable, non-symlink regular file."""

    if path.is_symlink() or not path.is_file():
        raise DocumentationQualificationError(f"{label}_unsafe")
    return path.resolve(strict=True)


def file_sha256(path: Path) -> str:
    """Return the SHA-256 identity of one local file."""

    digest = hashlib.sha256()
    with path.open("rb") as input_stream:
        for block in iter(lambda: input_stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def require_text(text: str, required: tuple[str, ...], label: str) -> None:
    """Require every authoritative phrase in one document or command."""

    missing = [value for value in required if value not in text]
    if missing:
        raise DocumentationQualificationError(f"{label}_contract_mismatch")


def load_documents(docs_root: Path) -> dict[str, str]:
    """Load and boundary-check the six portable documentation files."""

    documents: dict[str, str] = {}
    for document_name in DOCUMENT_NAMES:
        document_path = safe_file(docs_root / document_name, "document")
        document_text = document_path.read_text(encoding="utf-8")
        if not document_text.endswith("\n"):
            raise DocumentationQualificationError("document_newline_missing")
        if FORBIDDEN_DEPLOYMENT_JARGON.search(document_text):
            raise DocumentationQualificationError("deployment_jargon_found")
        if SECRET_MATERIAL.search(document_text):
            raise DocumentationQualificationError("credential_material_found")
        documents[document_name] = document_text
    return documents


def validate_document_contracts(documents: dict[str, str]) -> None:
    """Validate the operator, application, architecture, and method surfaces."""

    require_text(
        documents["OPERATOR_GUIDE.md"],
        (
            "./scripts/ishikawa-stack start",
            "./scripts/ishikawa-stack status",
            "./scripts/ishikawa-stack stop",
            "ISHIKAWA_GEMMA_API_KEY",
            "ISHIKAWA_NOMIC_API_KEY",
            "ISHIKAWA_POSTGRESQL_PASSWORD",
            "ISHIKAWA_POSTGRESQL_INGEST_PASSWORD",
            "./scripts/ishikawa-ingest --validate-only --manifest BATCH.yaml",
            "./scripts/ishikawa-ingest --publish --manifest BATCH.yaml",
            "One manifest is one atomic publication boundary.",
            "30 days for retrieval logs, 30 days for metrics, and 90",
        ),
        "operator_guide",
    )
    require_text(
        documents["COMMAND_SHEET.md"],
        (
            "ishikawa_stack=status;state=ready;boot_enabled=false",
            "http://127.0.0.1:3000",
            "http://127.0.0.1:1384/ready",
            "./scripts/ishikawa-retrieval-api --check-config",
            "./scripts/ishikawa-retrieval-api --check-readiness",
            "./scripts/ishikawa-observability-retention --apply",
        ),
        "command_sheet",
    )
    require_text(
        documents["APPLICATION_DEFINITION.md"],
        (
            "Ishikawa is a locally hosted retrieval-augmented knowledge application.",
            "There is no application login, role system, or per-user document authorization.",
            "PDF input only.",
            "Atomic publication per ingestion manifest.",
            "Exact-reference, PostgreSQL English full-text, and Nomic cosine retrieval.",
        ),
        "application_definition",
    )
    require_text(
        documents["APPLICATION_DESIGN.md"],
        (
            "Enforced invariants",
            "Versioned method profiles",
            "Deployment settings",
            "The exact-reference lane retains only its best candidate.",
            "The lexical and\nvector lanes each retain at most 20 candidates.",
            "Reciprocal-rank fusion",
            "constant 60",
            "32,768-token context budget",
            "temperature\n`1.0`, top-p `0.95`, and top-k `64`",
            "Startup is on demand, not at boot.",
        ),
        "application_design",
    )
    require_text(
        documents["ARCHITECTURE.md"],
        (
            "# Ishikawa As-Built Architecture",
            "127.0.0.1:3000",
            "127.0.0.1:1384",
            "127.0.0.1:5432",
            "127.0.0.1:8000",
            "127.0.0.1:8001",
            "rag_ingest",
            "rag_retrieval",
            "rag_search",
            "security-barrier views",
            "PostgreSQL, then the Retrieval API, then the web container",
        ),
        "architecture",
    )
    require_text(
        documents["CHUNKING_INGESTION_RETRIEVAL.md"],
        (
            "native Poppler tools",
            "one table-context chunk",
            "one atomic chunk for each table row",
            "768 finite values",
            "add",
            "revise",
            "reprocess",
            "reuse",
            "retire",
            "Exact lane.",
            "Lexical lane.",
            "Vector lane.",
            "Reciprocal-rank fusion",
            "top three fused evidence envelopes",
            "At\nleast 60 percent",
        ),
        "method_guide",
    )


def load_yaml(path: Path, label: str) -> Any:
    """Load one profile with Ishikawa's restricted YAML implementation."""

    from ishikawa.yaml_loader import load_restricted_yaml

    return load_restricted_yaml(safe_file(path, label), label=label)


def validate_configuration(config_root: Path) -> None:
    """Assert that every numeric and endpoint fact documented for v1 is live."""

    product = load_yaml(config_root / "product.yaml", "product")
    deployment = load_yaml(config_root / "deployment.yaml", "deployment")
    runtime = load_yaml(config_root / "runtime_dependencies.yaml", "runtime_dependencies")
    method = load_yaml(config_root / "method_profile.yaml", "method_profile")
    reconstruction = load_yaml(
        config_root / "reconstruction_profile.yaml", "reconstruction_profile"
    )
    relevance = load_yaml(config_root / "relevance_profile.yaml", "relevance_profile")
    logging = load_yaml(config_root / "logging_profile.yaml", "logging_profile")

    if product != {"schema_version": 1, "display_name": "Ishikawa"}:
        raise DocumentationQualificationError("product_configuration_mismatch")
    if (
        deployment["web"]
        != {
            "bind_host": "127.0.0.1",
            "port": 3000,
            "retrieval_base_url": "http://127.0.0.1:1384",
        }
        or deployment["retrieval"]["bind_host"] != "127.0.0.1"
        or deployment["retrieval"]["port"] != 1384
        or deployment["postgresql"] != {"bind_host": "127.0.0.1", "port": 5432}
    ):
        raise DocumentationQualificationError("deployment_configuration_mismatch")
    expected_runtime_values = (
        runtime["gemma"]["chat_endpoint_url"] == "http://127.0.0.1:8000/v1/chat/completions",
        runtime["nomic"]["embedding_endpoint_url"] == "http://127.0.0.1:8001/v1/embeddings",
        runtime["postgresql"]["database_user"] == "rag_retrieval",
    )
    if not all(expected_runtime_values):
        raise DocumentationQualificationError("runtime_dependency_mismatch")
    retrieval = method["retrieval"]
    if (
        retrieval["exact"]["candidate_depth"] != 1
        or retrieval["lexical"]["candidate_depth"] != 20
        or retrieval["vector"]["candidate_depth"] != 20
        or retrieval["fusion"]["candidate_depth"] != 20
        or retrieval["fusion"]["rrf_constant"] != 60
        or retrieval["fusion"]["lane_weights"]
        != {"exact": 1, "lexical": 1, "vector": 4}
        or retrieval["reranker"]["enabled"] is not False
    ):
        raise DocumentationQualificationError("retrieval_method_mismatch")
    if reconstruction["budget"] != {
        "total_context_tokens": 32768,
        "instruction_token_limit": 2048,
        "conversation_token_limit": 12288,
        "evidence_token_limit": 16384,
        "answer_token_reserve": 2048,
    }:
        raise DocumentationQualificationError("reconstruction_budget_mismatch")
    if (
        reconstruction["generation"]["temperature"] != 1.0
        or reconstruction["generation"]["top_p"] != 0.95
        or reconstruction["generation"]["top_k"] != 64
    ):
        raise DocumentationQualificationError("generation_profile_mismatch")
    if (
        relevance["measurement"]["fused_depth"] != 3
        or relevance["decision"]["minimum_supported_numerator"] != 3
        or relevance["decision"]["minimum_supported_denominator"] != 5
        or relevance["decision"]["model_authority"] is not False
    ):
        raise DocumentationQualificationError("relevance_profile_mismatch")
    if (
        logging["operational_retention_days"] != 30
        or logging["metrics_retention_days"] != 30
        or logging["audit_retention_days"] != 90
    ):
        raise DocumentationQualificationError("logging_profile_mismatch")


def validate_command_sources(command_root: Path) -> None:
    """Bind documented commands to their actual installed entrypoints."""

    stack_text = safe_file(command_root / "ishikawa-stack", "stack_command").read_text(
        encoding="utf-8"
    )
    ingestion_text = safe_file(
        command_root / "ishikawa-ingest", "ingestion_command"
    ).read_text(encoding="utf-8")
    retrieval_text = safe_file(
        command_root / "ishikawa-retrieval-api", "retrieval_command"
    ).read_text(encoding="utf-8")
    logging_text = safe_file(
        command_root / "ishikawa-log-control", "logging_command"
    ).read_text(encoding="utf-8")
    retention_text = safe_file(
        command_root / "ishikawa-observability-retention", "retention_command"
    ).read_text(encoding="utf-8")

    require_text(
        stack_text,
        (
            "Usage: ishikawa-stack {start|status|stop}",
            "POSTGRESQL_UNIT='postgresql@16-main.service'",
            "RETRIEVAL_UNIT='ishikawa-retrieval-api.service'",
            "WEB_CONTAINER='ishikawa-web'",
            "ISHIKAWA_GEMMA_API_KEY",
            "ISHIKAWA_NOMIC_API_KEY",
            "ISHIKAWA_POSTGRESQL_PASSWORD",
            "--check-readiness",
            "retrieval_readiness_preflight_failed",
            "retrieval_readiness_failed_after_preflight",
            "npm run dev -- --hostname",
        ),
        "stack_command",
    )
    start_positions = (
        stack_text.index('sudo systemctl start "$POSTGRESQL_UNIT"'),
        stack_text.index('"$SCRIPT_DIR/ishikawa-retrieval-api" --check-readiness'),
        stack_text.index('systemctl --user start "$RETRIEVAL_UNIT"'),
        stack_text.index('"${docker_command[@]}" run --detach --rm'),
    )
    if start_positions != tuple(sorted(start_positions)):
        raise DocumentationQualificationError("stack_start_order_mismatch")
    require_text(ingestion_text, ("execute_installed_ingestion",), "ingestion_command")
    require_text(retrieval_text, ("execute_installed_retrieval",), "retrieval_command")
    require_text(logging_text, ("execute_logging_control",), "logging_command")
    require_text(
        retention_text,
        ("execute_observability_retention",),
        "retention_command",
    )


def write_receipt(
    output_path: Path,
    documents: dict[str, str],
    docs_root: Path,
    command_root: Path,
) -> None:
    """Write one content-free, deterministic documentation receipt."""

    if output_path.exists() or output_path.is_symlink():
        raise DocumentationQualificationError("output_exists")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    receipt = {
        "command_contract_count": 5,
        "credential_material": False,
        "deployment_jargon": False,
        "document_count": len(documents),
        "documents": {
            document_name: file_sha256(docs_root / document_name)
            for document_name in sorted(documents)
        },
        "receipt_schema_version": 1,
        "runtime_changed": False,
        "source_commands": {
            command_name: file_sha256(command_root / command_name)
            for command_name in (
                "ishikawa-ingest",
                "ishikawa-log-control",
                "ishikawa-observability-retention",
                "ishikawa-retrieval-api",
                "ishikawa-stack",
            )
        },
        "target_contact": False,
    }
    output_path.write_text(
        json.dumps(receipt, ensure_ascii=True, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    """Validate all documentation contracts and retain the requested receipt."""

    arguments = parse_arguments()
    docs_root = safe_directory(arguments.docs_root, "docs_root")
    config_root = safe_directory(arguments.config_root, "config_root")
    command_root = safe_directory(arguments.command_root, "command_root")
    python_root = safe_directory(arguments.python_root, "python_root")
    sys.path.insert(0, str(python_root))

    documents = load_documents(docs_root)
    validate_document_contracts(documents)
    validate_configuration(config_root)
    validate_command_sources(command_root)
    write_receipt(arguments.output, documents, docs_root, command_root)

    print("documentation_files=6;portable_jargon=false;credential_material=false")
    print("command_contracts=5;configuration_contract=pass;method_contract=pass")
    print("documentation_qualification=pass")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except DocumentationQualificationError as error:
        print(f"documentation_qualification=blocked;reason={error}", file=sys.stderr)
        raise SystemExit(1) from None

