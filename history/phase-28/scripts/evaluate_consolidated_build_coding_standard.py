#!/usr/bin/env python3
"""Evaluate a packaged Ishikawa build against the repository coding standard.

Role:
    This local qualification helper checks every text file in one assembled
    package before the package may be retained or transferred.

Mental model:
    Inventory the closed package, classify every file, apply syntax and
    file-open readability checks appropriate to that file type, and emit one
    deterministic content-free compliance receipt. It never executes package
    code, contacts a dependency, or modifies the package.
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

import yaml


_PORTABLE_NAME = re.compile(
    r"(?:^|[-_.])(phase[-_ ]*[0-9]+|script[-_ ]*[0-9]+|prj[0-9]+)(?:$|[-_.])",
    re.IGNORECASE,
)
_HISTORICAL_MUTATION_NAME = re.compile(
    r"(?:^|[-_.])(migration|migrations|mutation|mutations|patch|patches|repair|repairs)"
    r"(?:$|[-_.])",
    re.IGNORECASE,
)
_NUMBERED_SQL_NAME = re.compile(r"^[0-9]{3,}[-_].*\.sql$", re.IGNORECASE)
_SHELL_HEADER_FIELDS = (
    "# Purpose:",
    "# Mental model:",
    "# Inputs or prerequisites:",
    "# Outputs:",
    "# Usage:",
)
_ONE_CHARACTER_EXCEPTIONS = frozenset({"_"})


class ComplianceError(ValueError):
    """A content-free coding-standard finding for the assembled package."""


def parse_arguments() -> argparse.Namespace:
    """Return the exact local evaluator inputs."""

    parser = argparse.ArgumentParser(
        description="Validate every file in an assembled Ishikawa package."
    )
    parser.add_argument("--bundle-root", required=True)
    parser.add_argument("--standard", required=True)
    parser.add_argument("--output", required=True)
    return parser.parse_args()


def require_regular_file(path: Path, label: str) -> Path:
    """Resolve one required non-symlink file or fail closed."""

    if not path.is_absolute() or path.is_symlink() or not path.is_file():
        raise ComplianceError(f"{label}_unsafe")
    return path.resolve(strict=True)


def require_directory(path: Path, label: str) -> Path:
    """Resolve one required non-symlink directory or fail closed."""

    if not path.is_absolute() or path.is_symlink() or not path.is_dir():
        raise ComplianceError(f"{label}_unsafe")
    return path.resolve(strict=True)


def text_content(path: Path) -> str:
    """Read strict UTF-8 and enforce the common text-file hygiene rules."""

    try:
        content = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise ComplianceError("text_encoding_invalid") from error
    if "\x00" in content or "\r" in content or "\t" in content:
        raise ComplianceError("text_format_invalid")
    if any(line != line.rstrip() for line in content.splitlines()):
        raise ComplianceError("trailing_whitespace_found")
    if not content.endswith("\n"):
        raise ComplianceError("final_newline_missing")
    return content


def python_names(tree: ast.AST) -> set[str]:
    """Collect reader-visible local names for anti-compression validation."""

    names: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Name):
            names.add(node.id)
        elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            arguments = (
                *node.args.posonlyargs,
                *node.args.args,
                *node.args.kwonlyargs,
            )
            names.update(argument.arg for argument in arguments)
    return names


def validate_python(path: Path, content: str, *, executable: bool) -> None:
    """Validate Python syntax, module responsibility, and readable names."""

    try:
        tree = ast.parse(content, filename=path.name)
    except SyntaxError as error:
        raise ComplianceError("python_syntax_invalid") from error
    summary = ast.get_docstring(tree, clean=True)
    if summary is None or len(summary.split()) < 5:
        raise ComplianceError("python_module_summary_missing")
    compressed_names = sorted(
        name
        for name in python_names(tree)
        if len(name) == 1 and name not in _ONE_CHARACTER_EXCEPTIONS
    )
    if compressed_names:
        raise ComplianceError("python_compressed_name_found")
    if executable:
        if not content.startswith("#!/usr/bin/env python3\n"):
            raise ComplianceError("python_entrypoint_shebang_invalid")
        has_main = any(
            isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
            and node.name == "main"
            for node in tree.body
        )
        has_main_guard = '__name__ == "__main__"' in content
        if not has_main or not has_main_guard:
            raise ComplianceError("python_entrypoint_flow_unclear")


def validate_shell(path: Path, content: str) -> None:
    """Validate the operator-facing shell header and fail-closed posture."""

    if not content.startswith("#!/usr/bin/env bash\nset -Eeuo pipefail\n"):
        raise ComplianceError("shell_strict_mode_missing")
    positions = [content.find(field) for field in _SHELL_HEADER_FIELDS]
    if any(position < 0 for position in positions) or positions != sorted(positions):
        raise ComplianceError("shell_file_open_contract_missing")
    if "--help" not in content or "blocked;reason=" not in content:
        raise ComplianceError("shell_operator_surface_incomplete")
    if not path.stat().st_mode & 0o100:
        raise ComplianceError("shell_entrypoint_not_executable")


def validate_yaml(content: str) -> None:
    """Validate that a configuration file is one plain YAML mapping."""

    try:
        documents = list(yaml.safe_load_all(content))
    except yaml.YAMLError as error:
        raise ComplianceError("yaml_syntax_invalid") from error
    if len(documents) != 1 or not isinstance(documents[0], dict):
        raise ComplianceError("yaml_root_invalid")


def validate_markdown(content: str) -> None:
    """Require an immediately discoverable document role."""

    first_line = next((line for line in content.splitlines() if line), "")
    if not first_line.startswith("# "):
        raise ComplianceError("markdown_title_missing")


def validate_javascript(content: str) -> None:
    """Require a readable module or the bounded pre-hydration theme IIFE."""

    module_contract = any(
        marker in content for marker in ("import ", "export ", '"use client"')
    )
    pre_hydration_iife = content.startswith("(() => {\n") and content.endswith("})();\n")
    if not module_contract and not pre_hydration_iife:
        raise ComplianceError("javascript_module_contract_missing")


def validate_json(content: str) -> None:
    """Require one ordinary JSON object with no duplicate-key approximation."""

    try:
        value = json.loads(content)
    except json.JSONDecodeError as error:
        raise ComplianceError("json_syntax_invalid") from error
    if not isinstance(value, dict):
        raise ComplianceError("json_root_invalid")


def validate_css(content: str) -> None:
    """Reject an empty or structurally incomplete stylesheet."""

    if "{" not in content or "}" not in content:
        raise ComplianceError("css_structure_invalid")


def validate_systemd(content: str) -> None:
    """Require a recognizable final user service or timer definition."""

    if "[Unit]" not in content or not any(
        section in content for section in ("[Service]", "[Timer]")
    ):
        raise ComplianceError("systemd_unit_structure_invalid")


def validate_final_schema(path: Path, content: str) -> None:
    """Require one readable canonical fresh-install database schema."""

    if path.name != "schema.sql":
        raise ComplianceError("fresh_schema_name_invalid")
    required_fields = (
        "-- Purpose:",
        "-- Mental model:",
        "-- Inputs or prerequisites:",
        "-- Outputs:",
    )
    positions = [content.find(field) for field in required_fields]
    if any(position < 0 for position in positions) or positions != sorted(positions):
        raise ComplianceError("sql_file_open_contract_missing")


def validate_checksum_manifest(
    bundle_root: Path,
    manifest_path: Path,
    content: str,
) -> None:
    """Ensure each checksum manifest closes its own package subtree."""

    listed: set[str] = set()
    for line in content.splitlines():
        digest, separator, relative_name = line.partition("  ")
        if (
            re.fullmatch(r"[0-9a-f]{64}", digest) is None
            or separator != "  "
            or not relative_name
            or relative_name in listed
        ):
            raise ComplianceError("checksum_manifest_invalid")
        listed.add(relative_name)
    scope_root = manifest_path.parent
    actual = {
        path.relative_to(scope_root).as_posix()
        for path in scope_root.rglob("*")
        if path.is_file() and path != manifest_path
    }
    if listed != actual:
        raise ComplianceError("checksum_manifest_coverage_invalid")


def write_exclusive(path: Path, payload: dict[str, Any]) -> None:
    """Write one deterministic receipt without replacing prior evidence."""

    if not path.is_absolute() or path.exists() or path.is_symlink() or not path.parent.is_dir():
        raise ComplianceError("output_path_unsafe")
    encoded = json.dumps(
        payload,
        ensure_ascii=True,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8") + b"\n"
    with path.open("xb") as output_stream:
        output_stream.write(encoded)


def evaluate(bundle_root: Path, standard_path: Path) -> dict[str, Any]:
    """Apply the applicable standard checks to the complete closed bundle."""

    standard_content = text_content(standard_path)
    required_standard_terms = (
        "File-Open Readability Standard",
        "Naming Standard",
        "Human Interpretability Standard",
        "Failure And Side-Effect Standard",
        "Deployable Package Final-State Standard",
        "CLI And Operator Surface",
    )
    if not all(term in standard_content for term in required_standard_terms):
        raise ComplianceError("coding_standard_identity_invalid")

    files = sorted(path for path in bundle_root.rglob("*") if path.is_file())
    if not files or any(path.is_symlink() for path in bundle_root.rglob("*")):
        raise ComplianceError("bundle_inventory_invalid")

    counts = {
        "css": 0,
        "javascript": 0,
        "json": 0,
        "manifest": 0,
        "markdown": 0,
        "python": 0,
        "shell": 0,
        "sql": 0,
        "systemd": 0,
        "yaml": 0,
    }
    for path in files:
        relative_name = path.relative_to(bundle_root).as_posix()
        if _PORTABLE_NAME.search(relative_name):
            raise ComplianceError("implementation_name_not_portable")
        if any(
            _HISTORICAL_MUTATION_NAME.search(part)
            for part in path.relative_to(bundle_root).parts
        ) or _NUMBERED_SQL_NAME.fullmatch(path.name):
            raise ComplianceError("historical_mutation_file_packaged")
        content = text_content(path)
        if path.name == "SHA256SUMS":
            validate_checksum_manifest(bundle_root, path, content)
            counts["manifest"] += 1
        elif content.startswith("#!/usr/bin/env bash\n"):
            validate_shell(path, content)
            counts["shell"] += 1
        elif path.suffix == ".py" or content.startswith("#!/usr/bin/env python3\n"):
            validate_python(
                path,
                content,
                executable=path.is_relative_to(bundle_root / "payload" / "scripts"),
            )
            counts["python"] += 1
        elif path.suffix == ".yaml":
            validate_yaml(content)
            counts["yaml"] += 1
        elif path.suffix == ".md":
            validate_markdown(content)
            counts["markdown"] += 1
        elif path.suffix in {".js", ".mjs"}:
            validate_javascript(content)
            counts["javascript"] += 1
        elif path.suffix == ".json":
            validate_json(content)
            counts["json"] += 1
        elif path.suffix == ".css":
            validate_css(content)
            counts["css"] += 1
        elif path.suffix in {".service", ".timer"}:
            validate_systemd(content)
            counts["systemd"] += 1
        elif path.suffix == ".sql":
            validate_final_schema(path, content)
            counts["sql"] += 1
        else:
            raise ComplianceError("unclassified_package_file")

    if (
        sum(counts.values()) != len(files)
        or counts["shell"] < 1
        or counts["sql"] > 1
    ):
        raise ComplianceError("package_category_coverage_invalid")
    return {
        "applicable_file_count": len(files),
        "category_counts": counts,
        "coding_standard_sha256": hashlib.sha256(
            standard_content.encode("utf-8")
        ).hexdigest(),
        "compliant": True,
        "finding_count": 0,
        "package_root_retained": False,
        "purpose": "consolidated_build_coding_standard_compliance",
        "schema_version": 1,
    }


def main() -> int:
    """Validate inputs, evaluate the package, and retain only safe counts."""

    arguments = parse_arguments()
    try:
        bundle_root = require_directory(Path(arguments.bundle_root), "bundle_root")
        standard_path = require_regular_file(Path(arguments.standard), "coding_standard")
        output_path = Path(arguments.output)
        result = evaluate(bundle_root, standard_path)
        write_exclusive(output_path, result)
    except ComplianceError as error:
        print(f"coding_standard_compliance=blocked;reason={error}", file=sys.stderr)
        return 1
    print(
        "coding_standard_compliance=pass;finding_count=0;"
        f"applicable_file_count={result['applicable_file_count']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
