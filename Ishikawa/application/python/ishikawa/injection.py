"""Deterministic direct- and indirect-prompt-injection gate.

The scanner detects a deliberately narrow set of high-signal indicators. It
is one layer in the boundary and does not claim prompt injection is solved.
It has no model, network, filesystem, database, or tool access.
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass
from typing import Any, Mapping, Sequence

from .canonical import domain_digest


_ORIGINS = frozenset({"current_question", "conversation_history", "retrieved_content"})
_STATUS = "security_rejected"
_RULESET = "builtin_v1"
_NORMALIZATION = "NFKC"
_REASON_CODES = (
    "hidden_or_control_characters",
    "encoded_or_obfuscated_instruction",
    "instruction_override_attempt",
    "role_impersonation_attempt",
    "prompt_extraction_attempt",
    "data_exfiltration_attempt",
    "tool_or_system_access_attempt",
)

# Priority order is stable and becomes part of the policy identity.
_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    (
        "instruction_override_attempt",
        re.compile(
            r"\b(?:ignore|disregard|override|bypass|forget)\b.{0,48}"
            r"\b(?:previous|prior|system|developer|instruction|rule|policy|guardrail)s?\b",
            re.IGNORECASE | re.DOTALL,
        ),
    ),
    (
        "role_impersonation_attempt",
        re.compile(
            r"(?:^|\n)\s*(?:system|developer|assistant)\s*:|"
            r"\b(?:you are now|act as|pretend to be)\b.{0,40}"
            r"\b(?:system|developer|administrator|unrestricted|unfiltered)\b",
            re.IGNORECASE | re.DOTALL,
        ),
    ),
    (
        "prompt_extraction_attempt",
        re.compile(
            r"\b(?:show|give|send|reveal|print|repeat|expose)\s+(?:me|us)\b.{0,32}"
            r"\b(?:system|developer|hidden|original)\b.{0,24}"
            r"\b(?:prompt|message|instruction)s?\b",
            re.IGNORECASE | re.DOTALL,
        ),
    ),
    (
        "data_exfiltration_attempt",
        re.compile(
            r"\b(?:show|give|send|reveal|print|return|expose)\s+(?:to\s+)?(?:me|us)\b.{0,40}"
            r"\b(?:api[ _-]?key|credential|password|secret|token|environment variable)s?\b",
            re.IGNORECASE | re.DOTALL,
        ),
    ),
    (
        "tool_or_system_access_attempt",
        re.compile(
            r"\b(?:use|open|access)\s+(?:the\s+)?(?:shell|terminal|filesystem|database)\b|"
            r"\b(?:run|execute)\s+(?:this\s+|the\s+)?(?:command|script)\b|"
            r"\b(?:read|write|delete)\s+(?:the\s+)?(?:file|directory)\s+[/~]",
            re.IGNORECASE,
        ),
    ),
)
_BASE64_RUN = re.compile(r"(?<![A-Za-z0-9+/=])[A-Za-z0-9+/]{80,}={0,2}(?![A-Za-z0-9+/=])")


class InjectionContractError(ValueError):
    """Raised when scanner configuration or typed input is invalid."""


@dataclass(frozen=True, slots=True)
class InjectionPolicy:
    maximum_fields: int
    maximum_field_characters: int
    maximum_total_characters: int
    reason_codes: tuple[str, ...]
    digest: str


@dataclass(frozen=True, slots=True)
class UntrustedText:
    origin: str
    text: str

    def __post_init__(self) -> None:
        if self.origin not in _ORIGINS:
            raise InjectionContractError("untrusted text origin is invalid")
        if not isinstance(self.text, str) or not self.text or "\x00" in self.text:
            raise InjectionContractError("untrusted text is invalid")


@dataclass(frozen=True, slots=True)
class InjectionDecision:
    status: str
    reason_code: str | None
    origin: str | None
    finding_count: int


def _exact_mapping(value: Any, keys: frozenset[str], label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping) or set(value) != keys:
        raise InjectionContractError(f"{label} fields are invalid")
    return value


def _positive_integer(value: Any, label: str, maximum: int) -> int:
    if type(value) is not int or not 1 <= value <= maximum:
        raise InjectionContractError(f"{label} is invalid")
    return value


def validate_injection_profile(value: Any) -> InjectionPolicy:
    root = _exact_mapping(
        value,
        frozenset({"schema_version", "scanner", "limits", "reason_codes"}),
        "injection profile",
    )
    if root["schema_version"] != 1 or type(root["schema_version"]) is not int:
        raise InjectionContractError("injection profile schema version is invalid")
    scanner = _exact_mapping(
        root["scanner"],
        frozenset({"ruleset", "unicode_normalization", "rejection_status"}),
        "injection scanner",
    )
    limits = _exact_mapping(
        root["limits"],
        frozenset({"maximum_fields", "maximum_field_characters", "maximum_total_characters"}),
        "injection limits",
    )
    reasons = root["reason_codes"]
    if (
        scanner != {
            "ruleset": _RULESET,
            "unicode_normalization": _NORMALIZATION,
            "rejection_status": _STATUS,
        }
        or not isinstance(reasons, list)
        or tuple(reasons) != _REASON_CODES
    ):
        raise InjectionContractError("injection scanner contract is invalid")
    maximum_fields = _positive_integer(limits["maximum_fields"], "maximum fields", 1024)
    maximum_field_characters = _positive_integer(
        limits["maximum_field_characters"], "maximum field characters", 1048576
    )
    maximum_total_characters = _positive_integer(
        limits["maximum_total_characters"], "maximum total characters", 4194304
    )
    if maximum_total_characters < maximum_field_characters:
        raise InjectionContractError("injection aggregate limit is invalid")
    rule_identity = [
        {"reason_code": reason, "pattern": pattern.pattern, "flags": pattern.flags}
        for reason, pattern in _PATTERNS
    ]
    canonical = {
        "limits": dict(limits),
        "reason_codes": list(_REASON_CODES),
        "rules": rule_identity,
        "scanner": dict(scanner),
        "schema_version": 1,
        "special_checks": ["unicode_controls", _BASE64_RUN.pattern],
    }
    return InjectionPolicy(
        maximum_fields,
        maximum_field_characters,
        maximum_total_characters,
        _REASON_CODES,
        domain_digest("ishikawa.injection-profile.v1", canonical),
    )


def _contains_hidden_control(text: str) -> bool:
    for character in text:
        if character in "\n\t":
            continue
        category = unicodedata.category(character)
        if category in {"Cc", "Cf"}:
            return True
    return False


def scan_untrusted_texts(
    fields: Sequence[UntrustedText],
    policy: InjectionPolicy,
) -> InjectionDecision:
    if not isinstance(policy, InjectionPolicy):
        raise InjectionContractError("injection policy is invalid")
    if not isinstance(fields, Sequence) or isinstance(fields, (str, bytes)) or not fields:
        raise InjectionContractError("untrusted text fields are invalid")
    if len(fields) > policy.maximum_fields or any(not isinstance(item, UntrustedText) for item in fields):
        raise InjectionContractError("untrusted text field count is invalid")
    total = 0
    findings: list[tuple[str, str]] = []
    for field in fields:
        total += len(field.text)
        if len(field.text) > policy.maximum_field_characters or total > policy.maximum_total_characters:
            raise InjectionContractError("untrusted text exceeds scan limits")
        normalized = unicodedata.normalize(_NORMALIZATION, field.text)
        if _contains_hidden_control(field.text):
            findings.append(("hidden_or_control_characters", field.origin))
        if _BASE64_RUN.search(normalized):
            findings.append(("encoded_or_obfuscated_instruction", field.origin))
        for reason, pattern in _PATTERNS:
            if pattern.search(normalized):
                findings.append((reason, field.origin))
    if not findings:
        return InjectionDecision("pass", None, None, 0)
    reason, origin = min(
        findings,
        key=lambda item: (policy.reason_codes.index(item[0]), tuple(sorted(_ORIGINS)).index(item[1])),
    )
    return InjectionDecision(_STATUS, reason, origin, len(findings))
