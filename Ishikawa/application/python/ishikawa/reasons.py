"""Versioned stable reason-code registry for Ishikawa validation v1."""

from __future__ import annotations


REASON_REGISTRY_VERSION = 1

# Codes are intentionally content-free. Additional processing-stage codes are
# reserved here even though extraction and chunking are not implemented yet.
REASON_CODES = frozenset(
    {
        "VALID",
        "CONFIG_FILE_UNREADABLE",
        "CONFIG_NOT_UTF8",
        "YAML_INVALID",
        "YAML_DUPLICATE_KEY",
        "YAML_FORBIDDEN_FEATURE",
        "YAML_DOCUMENT_COUNT_INVALID",
        "SCHEMA_TYPE_INVALID",
        "SCHEMA_FIELD_INVALID",
        "SCHEMA_FIELD_MISSING",
        "SCHEMA_FIELD_UNKNOWN",
        "SCHEMA_VERSION_UNSUPPORTED",
        "SCHEMA_LIST_EMPTY",
        "SCHEMA_VALUE_INVALID",
        "IDENTIFIER_INVALID",
        "IDENTIFIER_DUPLICATE",
        "IDENTIFIER_PUNCTUATION_COLLISION",
        "STATUS_INVALID",
        "MANIFEST_EMPTY",
        "MANIFEST_DOCUMENT_KEY_DUPLICATE",
        "MANIFEST_SOURCE_PATH_DUPLICATE",
        "MANIFEST_RETIREMENT_DUPLICATE",
        "MANIFEST_ACTION_CONFLICT",
        "SOURCE_PATH_INVALID",
        "SOURCE_PATH_ABSOLUTE",
        "SOURCE_PATH_TRAVERSAL",
        "SOURCE_FORMAT_UNSUPPORTED",
        "SOURCE_ROOT_UNAVAILABLE",
        "SOURCE_ROOT_NOT_DIRECTORY",
        "SOURCE_PATH_SYMLINK",
        "SOURCE_PATH_OUTSIDE_ROOT",
        "SOURCE_FILE_UNAVAILABLE",
        "SOURCE_FILE_UNREADABLE",
        "SOURCE_NOT_REGULAR_FILE",
        "UNSUPPORTED_PDF",
        "UNKNOWN_DOCUMENT_KEY",
        "CATALOG_DOCUMENT_RETIRED",
        "CATALOG_KEY_REMOVED",
        "UNKNOWN_CLASS_ID",
        "CLASS_RETIRED",
        "RETIREMENT_STATUS_MISMATCH",
        "RETIREMENT_NOT_PUBLISHED",
        "METHOD_PROFILE_ID_INVALID",
        "ENCRYPTED_PDF",
        "IMAGE_ONLY_PDF",
        "UNSUPPORTED_STRUCTURE",
        "YAML_DEPENDENCY_UNAVAILABLE",
        "POSTGRESQL_CAPABILITY_UNAVAILABLE",
        "POPLER_CAPABILITY_UNAVAILABLE",
        "UNEXPECTED_FAILURE",
    }
)


def is_registered_reason(reason_code: str) -> bool:
    return reason_code in REASON_CODES
