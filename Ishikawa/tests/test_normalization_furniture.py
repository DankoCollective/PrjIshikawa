from __future__ import annotations

import unittest

from ishikawa.normalization import (
    SourceLine,
    SourcePage,
    SourceWord,
    _furniture_signatures,
    _line_furniture_signature,
)


def _line(page: int, ordinal: int, text: str) -> SourceLine:
    words = tuple(
        SourceWord(word, 10.0 + index * 20.0, 740.0, 25.0 + index * 20.0, 750.0)
        for index, word in enumerate(text.split())
    )
    return SourceLine(page, ordinal, words, 10.0, 740.0, 500.0, 750.0)


class NormalizationFurnitureTests(unittest.TestCase):
    def test_page_n_of_m_is_one_recurring_furniture_signature(self):
        first = _line(1, 0, "Page 1 of 3")
        second = _line(2, 0, "Page 2 of 3")
        third = _line(3, 0, "Page 3 of 3")
        pages = (
            SourcePage(1, 612.0, 792.0, (first,)),
            SourcePage(2, 612.0, 792.0, (second,)),
            SourcePage(3, 612.0, 792.0, (third,)),
        )
        signatures = _furniture_signatures(pages)
        self.assertEqual(len(signatures), 1)
        self.assertIn(_line_furniture_signature(first), signatures)
        self.assertEqual(
            _line_furniture_signature(first),
            _line_furniture_signature(third),
        )


if __name__ == "__main__":
    unittest.main()
