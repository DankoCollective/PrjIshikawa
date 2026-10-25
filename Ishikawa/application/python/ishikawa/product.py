"""Validate Ishikawa's operator-controlled product presentation profile.

The profile contains display text only. It is converted into one canonical,
non-secret browser-runtime payload after strict YAML validation; it cannot add
HTML, CSS, scripts, external resources, or arbitrary presentation values.
"""

from __future__ import annotations

import base64
import re
from dataclasses import dataclass
from typing import Any, Mapping

from .canonical import canonical_json_bytes, domain_digest


_BLOCK_TYPES = frozenset({"heading", "body"})
_FONT_TOKENS = frozenset({"sans", "serif", "mono"})
_SIZE_TOKENS = frozenset({"small", "medium", "large", "display"})
_BREAK_TAG = re.compile(r"<br\s*/?>", re.IGNORECASE)


class ProductProfileError(ValueError):
    """Stable product-profile validation failure."""


def _exact_mapping(
    value: Any,
    fields: frozenset[str],
    reason: str,
) -> Mapping[str, Any]:
    if not isinstance(value, Mapping) or set(value) != fields:
        raise ProductProfileError(reason)
    return value


def _single_line_text(value: Any, maximum: int, reason: str) -> str:
    if (
        not isinstance(value, str)
        or not value
        or value != value.strip()
        or len(value) > maximum
        or any(ord(character) < 32 or ord(character) == 127 for character in value)
    ):
        raise ProductProfileError(reason)
    return value


def _markdown_text(value: Any) -> str:
    normalized = value.rstrip("\n") if isinstance(value, str) else value
    if (
        not isinstance(normalized, str)
        or not normalized
        or normalized != normalized.strip()
        or len(normalized) > 4096
        or "\r" in normalized
        or any(
            (ord(character) < 32 and character != "\n")
            or ord(character) == 127
            for character in normalized
        )
    ):
        raise ProductProfileError("PRODUCT_EMPTY_CHAT_MARKDOWN_INVALID")
    without_breaks = _BREAK_TAG.sub("", normalized)
    if "<" in without_breaks or ">" in without_breaks:
        raise ProductProfileError("PRODUCT_EMPTY_CHAT_MARKUP_NOT_ALLOWED")
    return normalized


@dataclass(frozen=True, slots=True)
class ProductPresentationBlock:
    block_type: str
    font: str
    size: str
    markdown: str

    def canonical(self) -> dict[str, str]:
        return {
            "font": self.font,
            "markdown": self.markdown,
            "size": self.size,
            "type": self.block_type,
        }


@dataclass(frozen=True, slots=True)
class ProductProfile:
    display_name: str
    tagline: str
    quick_questions: tuple[str, ...]
    footer_notice: str
    empty_chat_blocks: tuple[ProductPresentationBlock, ...]
    digest: str

    def browser_configuration(self) -> dict[str, Any]:
        """Return only the validated presentation values consumed by Next.js."""

        return {
            "empty_chat": {
                "blocks": [block.canonical() for block in self.empty_chat_blocks],
            },
            "footer_notice": self.footer_notice,
            "quick_questions": list(self.quick_questions),
            "tagline": self.tagline,
        }

    def browser_configuration_base64(self) -> str:
        encoded = base64.urlsafe_b64encode(
            canonical_json_bytes(self.browser_configuration())
        )
        return encoded.decode("ascii")


def validate_product_profile(value: Any) -> ProductProfile:
    """Validate the exact v2 product profile and derive its stable identity."""

    root = _exact_mapping(
        value,
        frozenset({"schema_version", "display_name", "tagline", "ui"}),
        "PRODUCT_PROFILE_FIELDS_INVALID",
    )
    if root["schema_version"] != 2 or type(root["schema_version"]) is not int:
        raise ProductProfileError("PRODUCT_PROFILE_VERSION_INVALID")
    display_name = _single_line_text(
        root["display_name"], 128, "PRODUCT_DISPLAY_NAME_INVALID"
    )
    tagline = _single_line_text(root["tagline"], 256, "PRODUCT_TAGLINE_INVALID")
    ui = _exact_mapping(
        root["ui"],
        frozenset({"quick_questions", "footer_notice", "empty_chat"}),
        "PRODUCT_UI_FIELDS_INVALID",
    )
    raw_questions = ui["quick_questions"]
    if not isinstance(raw_questions, list) or len(raw_questions) > 8:
        raise ProductProfileError("PRODUCT_QUICK_QUESTIONS_INVALID")
    quick_questions = tuple(
        _single_line_text(item, 512, "PRODUCT_QUICK_QUESTION_INVALID")
        for item in raw_questions
    )
    if len(set(quick_questions)) != len(quick_questions):
        raise ProductProfileError("PRODUCT_QUICK_QUESTION_DUPLICATE")
    footer_notice = _single_line_text(
        ui["footer_notice"], 512, "PRODUCT_FOOTER_NOTICE_INVALID"
    )
    empty_chat = _exact_mapping(
        ui["empty_chat"],
        frozenset({"blocks"}),
        "PRODUCT_EMPTY_CHAT_FIELDS_INVALID",
    )
    raw_blocks = empty_chat["blocks"]
    if not isinstance(raw_blocks, list) or not 1 <= len(raw_blocks) <= 8:
        raise ProductProfileError("PRODUCT_EMPTY_CHAT_BLOCKS_INVALID")
    blocks: list[ProductPresentationBlock] = []
    for raw_block in raw_blocks:
        block = _exact_mapping(
            raw_block,
            frozenset({"type", "font", "size", "markdown"}),
            "PRODUCT_EMPTY_CHAT_BLOCK_FIELDS_INVALID",
        )
        if block["type"] not in _BLOCK_TYPES:
            raise ProductProfileError("PRODUCT_EMPTY_CHAT_BLOCK_TYPE_INVALID")
        if block["font"] not in _FONT_TOKENS:
            raise ProductProfileError("PRODUCT_EMPTY_CHAT_FONT_INVALID")
        if block["size"] not in _SIZE_TOKENS:
            raise ProductProfileError("PRODUCT_EMPTY_CHAT_SIZE_INVALID")
        blocks.append(
            ProductPresentationBlock(
                block["type"],
                block["font"],
                block["size"],
                _markdown_text(block["markdown"]),
            )
        )
    if sum(len(block.markdown) for block in blocks) > 8192:
        raise ProductProfileError("PRODUCT_EMPTY_CHAT_TOTAL_SIZE_INVALID")

    canonical = {
        "display_name": display_name,
        "schema_version": 2,
        "tagline": tagline,
        "ui": {
            "empty_chat": {"blocks": [block.canonical() for block in blocks]},
            "footer_notice": footer_notice,
            "quick_questions": list(quick_questions),
        },
    }
    return ProductProfile(
        display_name,
        tagline,
        quick_questions,
        footer_notice,
        tuple(blocks),
        domain_digest("ishikawa.product-profile.v2", canonical),
    )
