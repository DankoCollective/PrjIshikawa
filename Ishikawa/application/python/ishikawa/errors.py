"""Stable, content-safe Ishikawa validation failures."""

from __future__ import annotations


class IshikawaValidationError(ValueError):
    """A known validation failure with a stable outcome and reason code."""

    def __init__(self, outcome: str, reason_code: str, safe_message: str) -> None:
        super().__init__(safe_message)
        self.outcome = outcome
        self.reason_code = reason_code
        self.safe_message = safe_message


class IshikawaDependencyError(RuntimeError):
    """A required local dependency is unavailable."""

    def __init__(self, reason_code: str, safe_message: str) -> None:
        super().__init__(safe_message)
        self.outcome = "BLOCKED"
        self.reason_code = reason_code
        self.safe_message = safe_message
