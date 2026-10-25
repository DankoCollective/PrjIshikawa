from __future__ import annotations

import base64
import json
import unittest
from pathlib import Path

from ishikawa.product import ProductProfileError, validate_product_profile
from ishikawa.yaml_loader import load_restricted_yaml


class ProductProfileTests(unittest.TestCase):
    def value(self):
        return {
            "schema_version": 2,
            "display_name": "Ishikawa",
            "tagline": "Knowledge assistant",
            "ui": {
                "quick_questions": ["What policy applies?"],
                "footer_notice": "Verify provided information using official documents.",
                "empty_chat": {
                    "blocks": [
                        {
                            "type": "heading",
                            "font": "serif",
                            "size": "display",
                            "markdown": "**What would you like**\n**to understand?**",
                        },
                        {
                            "type": "body",
                            "font": "sans",
                            "size": "medium",
                            "markdown": "First line.<br>\nSecond line.",
                        },
                    ]
                },
            },
        }

    def test_template_is_valid_and_browser_payload_is_canonical(self):
        root = Path(__file__).resolve().parents[1]
        profile = validate_product_profile(
            load_restricted_yaml(
                root / "config/templates/product.yaml", label="product profile"
            )
        )
        decoded = json.loads(
            base64.urlsafe_b64decode(profile.browser_configuration_base64())
        )
        self.assertEqual(decoded["tagline"], "Knowledge assistant")
        self.assertEqual(len(decoded["quick_questions"]), 3)
        self.assertEqual(decoded["empty_chat"]["blocks"][0]["font"], "serif")
        self.assertEqual(len(profile.digest), 64)

    def test_supported_break_and_formatting_markers_are_preserved(self):
        profile = validate_product_profile(self.value())
        markdown = profile.empty_chat_blocks[1].markdown
        self.assertIn("<br>", markdown)
        self.assertIn("\n", markdown)

    def test_raw_html_unknown_fields_and_tokens_fail_closed(self):
        for mutation, reason in (
            (("html", "<script>alert(1)</script>"), "PRODUCT_EMPTY_CHAT_MARKUP_NOT_ALLOWED"),
            (("font", "Comic Sans MS"), "PRODUCT_EMPTY_CHAT_FONT_INVALID"),
            (("size", "72px"), "PRODUCT_EMPTY_CHAT_SIZE_INVALID"),
        ):
            value = self.value()
            field, replacement = mutation
            if field == "html":
                value["ui"]["empty_chat"]["blocks"][0]["markdown"] = replacement
            else:
                value["ui"]["empty_chat"]["blocks"][0][field] = replacement
            with self.assertRaisesRegex(ProductProfileError, reason):
                validate_product_profile(value)
        value = self.value()
        value["ui"]["unknown"] = "not allowed"
        with self.assertRaisesRegex(ProductProfileError, "PRODUCT_UI_FIELDS_INVALID"):
            validate_product_profile(value)


if __name__ == "__main__":
    unittest.main()
