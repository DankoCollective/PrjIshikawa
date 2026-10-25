"""Restricted safe-YAML loader for Ishikawa operator configuration."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from .errors import IshikawaDependencyError, IshikawaValidationError

try:
    import yaml
    from yaml.constructor import ConstructorError
    from yaml.nodes import MappingNode
    from yaml.tokens import AliasToken, AnchorToken, DirectiveToken, TagToken
except ImportError as exc:  # pragma: no cover - exercised on targets without YAML
    raise IshikawaDependencyError(
        "YAML_DEPENDENCY_UNAVAILABLE",
        "The reviewed native Python YAML dependency is unavailable.",
    ) from exc


class _RestrictedSafeLoader(yaml.SafeLoader):
    pass


def _construct_unique_mapping(
    loader: _RestrictedSafeLoader,
    node: MappingNode,
    deep: bool = False,
) -> dict[Any, Any]:
    if not isinstance(node, MappingNode):
        raise ConstructorError(None, None, "expected a mapping", node.start_mark)
    result: dict[Any, Any] = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key == "<<":
            raise ConstructorError(None, None, "merge keys are forbidden", key_node.start_mark)
        try:
            duplicate = key in result
        except TypeError as exc:
            raise ConstructorError(None, None, "mapping key must be scalar", key_node.start_mark) from exc
        if duplicate:
            raise ConstructorError(None, None, "duplicate mapping key", key_node.start_mark)
        result[key] = loader.construct_object(value_node, deep=deep)
    return result


_RestrictedSafeLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,
    _construct_unique_mapping,
)


def load_restricted_yaml(path: str | Path, *, label: str) -> Any:
    """Load one UTF-8 YAML document while rejecting YAML graph features."""

    source = Path(path)
    try:
        raw = source.read_bytes()
    except OSError as exc:
        raise IshikawaValidationError(
            "REJECTED",
            "CONFIG_FILE_UNREADABLE",
            f"{label} is missing or unreadable.",
        ) from exc

    try:
        text = raw.decode("utf-8", errors="strict")
    except UnicodeDecodeError as exc:
        raise IshikawaValidationError(
            "REJECTED",
            "CONFIG_NOT_UTF8",
            f"{label} must be valid UTF-8.",
        ) from exc

    try:
        tokens = tuple(yaml.scan(text))
    except yaml.YAMLError as exc:
        raise IshikawaValidationError(
            "REJECTED", "YAML_INVALID", f"{label} is not valid YAML."
        ) from exc

    forbidden = (AliasToken, AnchorToken, DirectiveToken, TagToken)
    if any(isinstance(token, forbidden) for token in tokens):
        raise IshikawaValidationError(
            "REJECTED",
            "YAML_FORBIDDEN_FEATURE",
            f"{label} uses a forbidden YAML tag, directive, anchor, or alias.",
        )

    try:
        documents = list(yaml.load_all(text, Loader=_RestrictedSafeLoader))
    except yaml.YAMLError as exc:
        message = str(exc)
        reason = "YAML_DUPLICATE_KEY" if "duplicate mapping key" in message else "YAML_INVALID"
        raise IshikawaValidationError(
            "REJECTED", reason, f"{label} violates the restricted YAML contract."
        ) from exc

    if len(documents) != 1 or documents[0] is None:
        raise IshikawaValidationError(
            "REJECTED",
            "YAML_DOCUMENT_COUNT_INVALID",
            f"{label} must contain exactly one nonempty YAML document.",
        )
    return documents[0]
